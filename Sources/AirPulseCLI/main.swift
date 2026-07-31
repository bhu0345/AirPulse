import AirPulseProtocol
import FanKit
import Foundation
import SMCKit

@main
struct AirPulseCLI {
  static func main() {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else {
      printUsage()
      exit(1)
    }

    do {
      switch command {
      case "probe":
        try runProbe(writeTest: args.contains("--write"))
      case "list":
        try runList()
      case "temps":
        try runTemps()
      case "set":
        guard args.count >= 3, let rpm = Float(args[2]) else {
          fputs("用法: airpulse-cli set <fanIndex> <rpm>\n", stderr)
          exit(1)
        }
        try runSet(fanIndex: Int(args[1]) ?? 0, rpm: rpm)
      case "linked":
        guard args.count >= 2, let fraction = Double(args[1]) else {
          fputs("用法: airpulse-cli linked <0.0-1.0>\n", stderr)
          exit(1)
        }
        try runLinked(fraction: fraction)
      case "preset":
        guard args.count >= 2, let preset = FanPreset(rawValue: args[1]) else {
          fputs("用法: airpulse-cli preset <auto|quiet|balanced|cool>\n", stderr)
          exit(1)
        }
        try runPreset(preset)
      case "auto":
        try runAuto()
      case "help", "-h", "--help":
        printUsage()
      default:
        fputs("未知命令: \(command)\n", stderr)
        printUsage()
        exit(1)
      }
    } catch {
      fputs("错误: \(error.localizedDescription)\n", stderr)
      exit(2)
    }
  }

  static func printUsage() {
    print(
      """
      AirPulse CLI

        airpulse-cli probe [--write]   硬件可行性探针（--write 需要 root）
        airpulse-cli list              列出风扇
        airpulse-cli temps             列出关键温度
        airpulse-cli linked <0-1>      联动设定转速比例（需 root）
        airpulse-cli preset <name>     应用预设（需 root）
        airpulse-cli set <i> <rpm>     单风扇目标转速（需 root）
        airpulse-cli auto              恢复系统自动（需 root）
      """
    )
  }

  static func makeController() throws -> FanController {
    FanController(connection: try SMCConnection())
  }

  static func runProbe(writeTest: Bool) throws {
    let model = SMCConnection.hardwareModel()
    let c = try makeController()
    let fans = try c.allFans()
    let temps = c.readTemperatures(primaryOnly: true)

    print("=== AirPulse SMC Probe ===")
    print("model: \(model)")
    print("modeKeyFormat: \(c.config.modeKeyFormat)")
    print("ftstAvailable: \(c.config.ftstAvailable)")
    print("fanCount: \(fans.count)")
    for fan in fans {
      print(
        "fan[\(fan.index)] actual=\(Int(fan.actualRPM)) target=\(Int(fan.targetRPM)) min=\(Int(fan.minRPM)) max=\(Int(fan.maxRPM)) mode=\(fan.mode.rawValue)"
      )
    }
    for t in temps {
      print("temp \(t.name) (\(t.key)): \(String(format: "%.1f", t.celsius))°C")
    }

    var writeOK = false
    var writeNote = "skipped (pass --write as root to test)"
    if writeTest {
      if geteuid() != 0 {
        writeNote = "FAILED: --write requires root (sudo)"
      } else {
        let before = fans.first?.actualRPM ?? 0
        let strategy = try c.setLinkedFraction(0.35)
        Thread.sleep(forTimeInterval: 2.0)
        let afterFans = try c.allFans()
        let after = afterFans.first?.actualRPM ?? 0
        try c.restoreSystemControl()
        writeOK = true
        writeNote =
          "OK strategy=\(strategy.rawValue) before≈\(Int(before)) after≈\(Int(after)) restored=auto"
      }
    }

    print("writeTest: \(writeOK ? "pass" : "n/a") — \(writeNote)")
    print("=== end ===")

    // Machine-readable summary for docs
    let summary = """
    model=\(model)
    modeKey=\(c.config.modeKeyFormat)
    ftst=\(c.config.ftstAvailable)
    fans=\(fans.count)
    write=\(writeTest ? (writeOK ? "pass" : "fail") : "skipped")
    """
    let url = URL(fileURLWithPath: "docs/spike-results.local.md")
    try? """
    # Spike results (local)

    Generated: \(ISO8601DateFormatter().string(from: Date()))

    ```
    \(summary.trimmingCharacters(in: .whitespacesAndNewlines))
    ```

    \(writeNote)
    """.write(to: url, atomically: true, encoding: .utf8)
  }

  static func runList() throws {
    for fan in try makeController().allFans() {
      print(
        "Fan \(fan.index): \(Int(fan.actualRPM)) RPM (target \(Int(fan.targetRPM)), \(Int(fan.minRPM))–\(Int(fan.maxRPM)), mode \(fan.mode.rawValue))"
      )
    }
  }

  static func runTemps() throws {
    for t in try makeController().readTemperatures(primaryOnly: false) {
      print("\(t.name)\t\(t.key)\t\(String(format: "%.1f", t.celsius))°C")
    }
  }

  static func runSet(fanIndex: Int, rpm: Float) throws {
    requireRoot()
    let c = try makeController()
    let strategy = try c.enableManualMode(fanIndex: fanIndex)
    try c.setTargetRPM(fanIndex: fanIndex, rpm: rpm)
    print("set fan \(fanIndex) -> \(Int(rpm)) RPM (\(strategy.rawValue))")
  }

  static func runLinked(fraction: Double) throws {
    requireRoot()
    let strategy = try makeController().setLinkedFraction(fraction)
    print("linked fraction \(fraction) (\(strategy.rawValue))")
  }

  static func runPreset(_ preset: FanPreset) throws {
    requireRoot()
    let strategy = try makeController().applyPreset(preset)
    print("preset \(preset.rawValue) (\(strategy.rawValue))")
  }

  static func runAuto() throws {
    requireRoot()
    try makeController().restoreSystemControl()
    print("restored auto")
  }

  static func requireRoot() {
    if geteuid() != 0 {
      fputs("此操作需要 root：请使用 sudo airpulse-cli ...\n", stderr)
      exit(3)
    }
  }
}
