import AirPulseProtocol
import AppKit
import FanKit
import Foundation
import SMCKit

/// Talks to the privileged helper over XPC when available; otherwise uses
/// in-process SMC for reads and a local privileged CLI bridge for writes.
@MainActor
final class FanService: ObservableObject {
  @Published var fans: [FanSnapshot] = []
  @Published var temperatures: [TemperatureReading] = []
  @Published var linkedEnabled = true
  @Published var linkedFraction: Double = 0.3
  @Published var activePreset: FanPreset = .auto
  @Published var statusMessage: String = "正在连接…"
  @Published var canWrite = false
  @Published var hardwareSummary: String = ""
  @Published var safetyNotice: String?
  @Published var unlinkRPM: [Int: Double] = [:]

  private var connection: NSXPCConnection?
  private var pollTask: Task<Void, Never>?
  private var localController: FanController?
  private let safety = SafetyPolicy()
  private var wakeObserver: NSObjectProtocol?
  private var desiredManual = false

  func start() {
    statusMessage = "读取传感器…"
    openLocalRead()
    tryConnectHelper()
    refresh()
    startPolling()
    observeWake()
  }

  func stop() {
    pollTask?.cancel()
    if let wakeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
    }
    if desiredManual {
      restoreAuto()
    }
    connection?.invalidate()
  }

  private func openLocalRead() {
    do {
      localController = FanController(connection: try SMCConnection())
      if let c = localController {
        hardwareSummary =
          "\(SMCConnection.hardwareModel()) · mode \(c.config.modeKeyFormat) · Ftst \(c.config.ftstAvailable ? "有" : "无")"
      }
    } catch {
      statusMessage = "SMC 读取失败: \(error.localizedDescription)"
    }
  }

  private func tryConnectHelper() {
    let conn = NSXPCConnection(machServiceName: AirPulseConfig.helperMachService, options: [.privileged])
    conn.remoteObjectInterface = NSXPCInterface(with: AirPulseHelperProtocol.self)
    conn.invalidationHandler = { [weak self] in
      Task { @MainActor in
        self?.canWrite = false
        self?.connection = nil
      }
    }
    conn.resume()
    connection = conn

    guard let proxy = conn.remoteObjectProxy as? AirPulseHelperProtocol else { return }
    proxy.ping { [weak self] _ in
      Task { @MainActor in
        self?.canWrite = true
        self?.statusMessage = "已连接特权 Helper"
      }
    }
    // If helper isn't installed, ping never returns; mark after timeout.
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 800_000_000)
      if self.canWrite == false {
        self.statusMessage = "监视模式（写入需安装 Helper 或使用 sudo CLI）"
      }
    }
  }

  private func helper() -> AirPulseHelperProtocol? {
    connection?.remoteObjectProxy as? AirPulseHelperProtocol
  }

  func refresh() {
    if let c = localController {
      fans = (try? c.allFans()) ?? fans
      temperatures = c.readTemperatures(primaryOnly: true)
      if unlinkRPM.isEmpty {
        for fan in fans {
          let span = max(1, fan.maxRPM - fan.minRPM)
          unlinkRPM[fan.index] = Double((fan.actualRPM - fan.minRPM) / span)
        }
      }
      if activePreset != .auto, let first = fans.first, first.maxRPM > first.minRPM {
        linkedFraction = Double((first.targetRPM - first.minRPM) / (first.maxRPM - first.minRPM))
      }
      enforceSafetyLocally()
    }

    helper()?.listFans { [weak self] data, _ in
      guard let data else { return }
      let decoded = data.compactMap { AirPulseCoding.decode(FanSnapshot.self, from: $0) }
      Task { @MainActor in
        if !decoded.isEmpty { self?.fans = decoded }
      }
    }
  }

  func applyPreset(_ preset: FanPreset) {
    activePreset = preset
    desiredManual = preset != .auto
    if let fraction = preset.speedFraction {
      linkedFraction = fraction
    }

    if let helper = helper(), canWrite {
      helper.applyPreset(preset.rawValue) { [weak self] ok, err in
        Task { @MainActor in
          self?.statusMessage = ok ? "预设：\(preset.titleZH)" : (err ?? "失败")
          self?.refresh()
        }
      }
      return
    }

    // Fallback: spawn privileged CLI via osascript
    runPrivilegedCLI(["preset", preset.rawValue])
  }

  func applyLinkedFraction(_ fraction: Double) {
    linkedFraction = fraction
    activePreset = .balanced
    desiredManual = true

    if let helper = helper(), canWrite {
      helper.setLinkedFraction(fraction) { [weak self] ok, err in
        Task { @MainActor in
          self?.statusMessage = ok ? String(format: "联动 %.0f%%", fraction * 100) : (err ?? "失败")
          self?.refresh()
        }
      }
      return
    }
    runPrivilegedCLI(["linked", String(format: "%.3f", fraction)])
  }

  func applyUnlinked(fanIndex: Int, fraction: Double) {
    unlinkRPM[fanIndex] = fraction
    desiredManual = true
    guard let fan = fans.first(where: { $0.index == fanIndex }) else { return }
    let rpm = fan.minRPM + Float(fraction) * (fan.maxRPM - fan.minRPM)
    if let helper = helper(), canWrite {
      helper.setFanRPM(UInt(fanIndex), rpm: rpm) { [weak self] ok, err in
        Task { @MainActor in
          self?.statusMessage = ok ? "风扇 \(fanIndex)：\(Int(rpm)) RPM" : (err ?? "失败")
          self?.refresh()
        }
      }
      return
    }
    runPrivilegedCLI(["set", String(fanIndex), String(Int(rpm))])
  }

  func restoreAuto() {
    activePreset = .auto
    desiredManual = false
    if let helper = helper(), canWrite {
      helper.restoreAuto { [weak self] ok, err in
        Task { @MainActor in
          self?.statusMessage = ok ? "已恢复系统自动" : (err ?? "失败")
          self?.refresh()
        }
      }
      return
    }
    runPrivilegedCLI(["auto"])
  }

  private func runPrivilegedCLI(_ args: [String]) {
    let cli = Bundle.main.bundleURL
      .appendingPathComponent("Contents/MacOS/airpulse-cli").path
    let fallback = ProductPaths.cliPath
    let exe = FileManager.default.isExecutableFile(atPath: cli) ? cli : fallback
    guard FileManager.default.isExecutableFile(atPath: exe) else {
      statusMessage = "未找到 airpulse-cli，请先 Scripts/build-app.sh"
      return
    }
    let argString = args.map { "'\($0)'" }.joined(separator: " ")
    let script =
      "do shell script \"'\(exe)' \(argString)\" with administrator privileges"
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    proc.arguments = ["-e", script]
    do {
      try proc.run()
      proc.waitUntilExit()
      statusMessage = proc.terminationStatus == 0 ? "已应用（管理员权限）" : "写入失败（权限或 SMC）"
      refresh()
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  private func startPolling() {
    pollTask?.cancel()
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        await MainActor.run { self?.refresh() }
        // Privileged helper re-asserts targets on its own timer.
        // osascript fallback only re-applies on wake (see observeWake), not every poll.
        try? await Task.sleep(nanoseconds: UInt64(AirPulseConfig.pollInterval * 1_000_000_000))
      }
    }
  }

  private func observeWake() {
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.desiredManual else { return }
        self.statusMessage = "唤醒后重新施加风扇设定…"
        if self.linkedEnabled {
          self.applyLinkedFraction(self.linkedFraction)
        } else {
          for (index, fraction) in self.unlinkRPM {
            self.applyUnlinked(fanIndex: index, fraction: fraction)
          }
        }
      }
    }
  }

  private func enforceSafetyLocally() {
    let maxTemp = temperatures.map(\.celsius).max()
    switch safety.evaluate(maxTemp: maxTemp) {
    case .restoreAuto:
      safetyNotice = "温度过高，已恢复系统自动控温"
      if desiredManual { restoreAuto() }
    case .forceCool:
      safetyNotice = "温度偏高，已切换强冷"
      if activePreset != .cool { applyPreset(.cool) }
    case .none:
      safetyNotice = nil
    }
  }
}

enum ProductPaths {
  static var cliPath: String {
    let cwd = FileManager.default.currentDirectoryPath
    let candidates = [
      "\(cwd)/.build/release/airpulse-cli",
      "\(cwd)/.build/debug/airpulse-cli",
      "\(cwd)/Products/AirPulse.app/Contents/MacOS/airpulse-cli",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
  }
}
