import AirPulseProtocol
import AppKit
import FanKit
import Foundation
import SMCKit

/// Holds the XPC connection and forwards callbacks onto the main actor safely.
/// XPC queues are not MainActor — calling @MainActor FanService directly from
/// those queues crashes with EXC_BREAKPOINT (dispatch_assert_queue_fail).
final class HelperXPCClient: @unchecked Sendable {
  private let connection: NSXPCConnection
  private let onConnected: @Sendable () -> Void
  private let onDisconnected: @Sendable () -> Void

  init(
    machServiceName: String,
    onConnected: @escaping @Sendable () -> Void,
    onDisconnected: @escaping @Sendable () -> Void
  ) {
    self.onConnected = onConnected
    self.onDisconnected = onDisconnected
    let conn = NSXPCConnection(machServiceName: machServiceName, options: [.privileged])
    conn.remoteObjectInterface = NSXPCInterface(with: AirPulseHelperProtocol.self)
    self.connection = conn

    conn.invalidationHandler = { [onDisconnected] in
      onDisconnected()
    }
    conn.interruptionHandler = { [onDisconnected] in
      onDisconnected()
    }
    conn.resume()

    let proxy = conn.remoteObjectProxyWithErrorHandler { [onDisconnected] _ in
      onDisconnected()
    } as? AirPulseHelperProtocol

    proxy?.ping { [onConnected] _ in
      onConnected()
    }
  }

  func proxy() -> AirPulseHelperProtocol? {
    connection.remoteObjectProxyWithErrorHandler { [onDisconnected] _ in
      onDisconnected()
    } as? AirPulseHelperProtocol
  }

  func invalidate() {
    connection.invalidate()
  }
}

/// Talks to the privileged helper over XPC when available.
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
  @Published var isInstallingHelper = false

  private var xpc: HelperXPCClient?
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
    xpc?.invalidate()
    xpc = nil
  }

  func reloadLocalizedStrings() {
    if canWrite {
      statusMessage = L.helperConnected
    } else {
      statusMessage = L.monitorMode
    }
    updateHardwareSummary()
    enforceSafetyLocally()
  }

  private func updateHardwareSummary() {
    guard let c = localController else { return }
    let count = (try? c.fanCount()) ?? fans.count
    hardwareSummary = L.hardwareSummary(model: SMCConnection.hardwareModel(), fanCount: count)
  }

  private func openLocalRead() {
    do {
      localController = FanController(connection: try SMCConnection())
      updateHardwareSummary()
    } catch {
      statusMessage = "\(L.smcReadFailed): \(error.localizedDescription)"
    }
  }

  private func tryConnectHelper() {
    xpc?.invalidate()
    xpc = HelperXPCClient(
      machServiceName: AirPulseConfig.helperMachService,
      onConnected: { [weak self] in
        Task { @MainActor in
          self?.canWrite = true
          self?.statusMessage = LanguageStore.shared.strings.helperConnected
        }
      },
      onDisconnected: { [weak self] in
        Task { @MainActor in
          self?.canWrite = false
        }
      }
    )

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 700_000_000)
      if self.canWrite == false {
        self.statusMessage = self.L.monitorMode
      }
    }
  }

  private func helper() -> AirPulseHelperProtocol? {
    guard canWrite else { return nil }
    return xpc?.proxy()
  }

  /// One-time install of the LaunchDaemon helper (single password prompt).
  func installHelper() {
    let L = self.L
    let helperURL = Bundle.main.bundleURL
      .appendingPathComponent("Contents/MacOS/AirPulseHelper")
    var helperPath = helperURL.path
    if !FileManager.default.isExecutableFile(atPath: helperPath) {
      helperPath = ProductPaths.helperPath
    }
    guard FileManager.default.isExecutableFile(atPath: helperPath) else {
      statusMessage = L.helperMissingBinary
      return
    }

    isInstallingHelper = true
    statusMessage = L.helperInstalling

    let dst = "/usr/local/libexec/AirPulseHelper"
    let plistPath = "/Library/LaunchDaemons/\(AirPulseConfig.helperLabel).plist"
    let label = AirPulseConfig.helperLabel
    let mach = AirPulseConfig.helperMachService

    // Keep heredoc terminator flush-left in the generated file.
    let script = """
    #!/bin/bash
    set -euo pipefail
    mkdir -p /usr/local/libexec
    cp "\(helperPath)" "\(dst)"
    chmod 755 "\(dst)"
    cat > "\(plistPath)" <<'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>\(label)</string>
      <key>ProgramArguments</key>
      <array>
        <string>\(dst)</string>
      </array>
      <key>MachServices</key>
      <dict>
        <key>\(mach)</key>
        <true/>
      </dict>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <true/>
    </dict>
    </plist>
    PLIST
    launchctl bootout system/\(label) 2>/dev/null || true
    launchctl bootstrap system "\(plistPath)"
    launchctl enable system/\(label)
    """

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("airpulse-install-helper.sh")
    do {
      try script.write(to: tempURL, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: tempURL.path
      )
    } catch {
      isInstallingHelper = false
      statusMessage = error.localizedDescription
      return
    }

    let scriptPath = tempURL.path

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      // Quote path for AppleScript string.
      let quoted = scriptPath.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
      proc.arguments = [
        "-e",
        "do shell script \"/bin/bash \\\"\(quoted)\\\"\" with administrator privileges",
      ]
      do {
        try proc.run()
        proc.waitUntilExit()
        let ok = proc.terminationStatus == 0
        DispatchQueue.main.async {
          guard let self else { return }
          self.isInstallingHelper = false
          try? FileManager.default.removeItem(at: tempURL)
          if ok {
            Task { @MainActor in
              try? await Task.sleep(nanoseconds: 1_000_000_000)
              self.tryConnectHelper()
              try? await Task.sleep(nanoseconds: 1_000_000_000)
              let success = self.canWrite
              self.statusMessage =
                success ? self.L.helperConnected : self.L.helperInstallFailed
              self.showInstallResultAlert(success: success)
            }
          } else {
            self.statusMessage = self.L.helperInstallFailed
            self.showInstallResultAlert(success: false)
          }
        }
      } catch {
        DispatchQueue.main.async {
          self?.isInstallingHelper = false
          self?.statusMessage = error.localizedDescription
          try? FileManager.default.removeItem(at: tempURL)
        }
      }
    }
  }

  private func showInstallResultAlert(success: Bool) {
    let L = self.L
    let alert = NSAlert()
    alert.messageText = success ? L.helperConnected : L.helperInstallFailed
    alert.informativeText =
      success
      ? L.enableFanControlHint
      : L.needHelperToWrite
    alert.alertStyle = success ? .informational : .warning
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }

  func refresh() {
    if let c = localController {
      fans = (try? c.allFans()) ?? fans
      temperatures = c.readTemperatures(primaryOnly: true)
      updateHardwareSummary()
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

  private func requireWriteAccess() -> Bool {
    if canWrite { return true }
    statusMessage = L.needHelperToWrite
    return false
  }

  func applyPreset(_ preset: FanPreset) {
    activePreset = preset
    desiredManual = preset != .auto
    if let fraction = preset.speedFraction {
      linkedFraction = fraction
    }
    guard requireWriteAccess(), let helper = helper() else { return }

    helper.applyPreset(preset.rawValue) { [weak self] ok, err in
      Task { @MainActor in
        guard let self else { return }
        let L = self.L
        self.statusMessage = ok ? L.presetStatus(preset) : (err ?? L.failed)
        self.refresh()
      }
    }
  }

  func applyLinkedFraction(_ fraction: Double) {
    linkedFraction = fraction
    activePreset = .balanced
    desiredManual = true
    guard requireWriteAccess(), let helper = helper() else { return }

    helper.setLinkedFraction(fraction) { [weak self] ok, err in
      Task { @MainActor in
        guard let self else { return }
        let L = self.L
        self.statusMessage = ok ? L.linkedStatus(Int(fraction * 100)) : (err ?? L.failed)
        self.refresh()
      }
    }
  }

  func applyUnlinked(fanIndex: Int, fraction: Double) {
    unlinkRPM[fanIndex] = fraction
    desiredManual = true
    guard let fan = fans.first(where: { $0.index == fanIndex }) else { return }
    let rpm = fan.minRPM + Float(fraction) * (fan.maxRPM - fan.minRPM)
    guard requireWriteAccess(), let helper = helper() else { return }

    helper.setFanRPM(UInt(fanIndex), rpm: rpm) { [weak self] ok, err in
      Task { @MainActor in
        guard let self else { return }
        let L = self.L
        self.statusMessage = ok ? L.fanRPMStatus(fanIndex, rpm: Int(rpm)) : (err ?? L.failed)
        self.refresh()
      }
    }
  }

  func restoreAuto() {
    activePreset = .auto
    desiredManual = false
    guard requireWriteAccess(), let helper = helper() else { return }

    helper.restoreAuto { [weak self] ok, err in
      Task { @MainActor in
        guard let self else { return }
        let L = self.L
        self.statusMessage = ok ? L.restoredAuto : (err ?? L.failed)
        self.refresh()
      }
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
        guard let self, self.desiredManual, self.canWrite else { return }
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
      if desiredManual, canWrite { restoreAuto() }
    case .forceCool:
      safetyNotice = L.safetyWarning
      if activePreset != .cool, canWrite { applyPreset(.cool) }
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

  static var helperPath: String {
    let cwd = FileManager.default.currentDirectoryPath
    let candidates = [
      "\(cwd)/.build/release/AirPulseHelper",
      "\(cwd)/Products/AirPulse.app/Contents/MacOS/AirPulseHelper",
      "\(cwd)/Release/AirPulse.app/Contents/MacOS/AirPulseHelper",
    ]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
  }
}
