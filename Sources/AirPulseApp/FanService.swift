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
  @Published var statusMessage: String = LanguageStore.shared.strings.connecting
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

  private var L: L10n { LanguageStore.shared.strings }

  func start() {
    statusMessage = L.readingSensors
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

  /// Refresh status strings after the user changes language.
  func reloadLocalizedStrings() {
    let L = self.L
    if canWrite {
      statusMessage = L.helperConnected
    } else if statusMessage.isEmpty || !statusMessage.contains("SMC") {
      statusMessage = L.monitorMode
    }
    if let c = localController {
      hardwareSummary =
        "\(SMCConnection.hardwareModel()) · mode \(c.config.modeKeyFormat) · Ftst \(c.config.ftstAvailable ? L.ftstYes : L.ftstNo)"
    }
    enforceSafetyLocally()
  }

  private func openLocalRead() {
    let L = self.L
    do {
      localController = FanController(connection: try SMCConnection())
      if let c = localController {
        hardwareSummary =
          "\(SMCConnection.hardwareModel()) · mode \(c.config.modeKeyFormat) · Ftst \(c.config.ftstAvailable ? L.ftstYes : L.ftstNo)"
      }
    } catch {
      statusMessage = "\(L.smcReadFailed): \(error.localizedDescription)"
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
        self?.statusMessage = LanguageStore.shared.strings.helperConnected
      }
    }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 800_000_000)
      if self.canWrite == false {
        self.statusMessage = self.L.monitorMode
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
          guard let self else { return }
          let L = self.L
          self.statusMessage = ok ? L.presetStatus(preset) : (err ?? L.failed)
          self.refresh()
        }
      }
      return
    }

    runPrivilegedCLI(["preset", preset.rawValue])
  }

  func applyLinkedFraction(_ fraction: Double) {
    linkedFraction = fraction
    activePreset = .balanced
    desiredManual = true

    if let helper = helper(), canWrite {
      helper.setLinkedFraction(fraction) { [weak self] ok, err in
        Task { @MainActor in
          guard let self else { return }
          let L = self.L
          self.statusMessage =
            ok ? L.linkedStatus(Int(fraction * 100)) : (err ?? L.failed)
          self.refresh()
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
          guard let self else { return }
          let L = self.L
          self.statusMessage =
            ok ? L.fanRPMStatus(fanIndex, rpm: Int(rpm)) : (err ?? L.failed)
          self.refresh()
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
          guard let self else { return }
          let L = self.L
          self.statusMessage = ok ? L.restoredAuto : (err ?? L.failed)
          self.refresh()
        }
      }
      return
    }
    runPrivilegedCLI(["auto"])
  }

  private func runPrivilegedCLI(_ args: [String]) {
    let L = self.L
    let cli = Bundle.main.bundleURL
      .appendingPathComponent("Contents/MacOS/airpulse-cli").path
    let fallback = ProductPaths.cliPath
    let exe = FileManager.default.isExecutableFile(atPath: cli) ? cli : fallback
    guard FileManager.default.isExecutableFile(atPath: exe) else {
      statusMessage = L.cliMissing
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
      statusMessage = proc.terminationStatus == 0 ? L.appliedAdmin : L.writeFailed
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
        self.statusMessage = self.L.reassertAfterWake
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
    let L = self.L
    let maxTemp = temperatures.map(\.celsius).max()
    switch safety.evaluate(maxTemp: maxTemp) {
    case .restoreAuto:
      safetyNotice = L.safetyCritical
      if desiredManual { restoreAuto() }
    case .forceCool:
      safetyNotice = L.safetyWarning
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
      "\(cwd)/Release/AirPulse.app/Contents/MacOS/airpulse-cli",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
  }
}
