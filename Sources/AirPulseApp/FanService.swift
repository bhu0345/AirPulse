import AirPulseProtocol
import AppKit
import FanKit
import Foundation
import SMCKit

// MARK: - XPC client (never touches MainActor-isolated types)

final class HelperXPCClient: @unchecked Sendable {
  private let connection: NSXPCConnection

  init(machServiceName: String) {
    let conn = NSXPCConnection(machServiceName: machServiceName, options: [.privileged])
    conn.remoteObjectInterface = NSXPCInterface(with: AirPulseHelperProtocol.self)
    self.connection = conn
    conn.resume()
  }

  private func proxy(
    onError: @escaping @Sendable () -> Void
  ) -> AirPulseHelperProtocol? {
    connection.remoteObjectProxyWithErrorHandler { _ in
      onError()
    } as? AirPulseHelperProtocol
  }

  func setDisconnectHandler(_ handler: @escaping @Sendable () -> Void) {
    connection.invalidationHandler = handler
    connection.interruptionHandler = handler
  }

  func ping(completion: @escaping @Sendable (Bool) -> Void) {
    let p = proxy { completion(false) }
    guard let p else {
      completion(false)
      return
    }
    p.ping { _ in completion(true) }
  }

  func listFans(completion: @escaping @Sendable ([FanSnapshot]) -> Void) {
    let p = proxy { completion([]) }
    p?.listFans { data, _ in
      let fans = (data ?? []).compactMap { AirPulseCoding.decode(FanSnapshot.self, from: $0) }
      completion(fans)
    }
  }

  func applyPreset(
    _ raw: String,
    completion: @escaping @Sendable (Bool, String?) -> Void
  ) {
    let p = proxy { completion(false, "XPC disconnected") }
    p?.applyPreset(raw, reply: completion)
  }

  func setLinkedFraction(
    _ fraction: Double,
    completion: @escaping @Sendable (Bool, String?) -> Void
  ) {
    let p = proxy { completion(false, "XPC disconnected") }
    p?.setLinkedFraction(fraction, reply: completion)
  }

  func setFanRPM(
    _ index: UInt,
    rpm: Float,
    completion: @escaping @Sendable (Bool, String?) -> Void
  ) {
    let p = proxy { completion(false, "XPC disconnected") }
    p?.setFanRPM(index, rpm: rpm, reply: completion)
  }

  func restoreAuto(completion: @escaping @Sendable (Bool, String?) -> Void) {
    let p = proxy { completion(false, "XPC disconnected") }
    p?.restoreAuto(reply: completion)
  }

  func invalidate() {
    connection.invalidationHandler = nil
    connection.interruptionHandler = nil
    connection.invalidate()
  }
}

// MARK: - FanService

/// Not MainActor-isolated: XPC replies arrive on private queues.
/// All `@Published` mutations hop to the main queue explicitly.
final class FanService: ObservableObject, @unchecked Sendable {
  @Published var fans: [FanSnapshot] = []
  @Published var temperatures: [TemperatureReading] = []
  @Published var linkedEnabled = true
  @Published var linkedFraction: Double = 0.3
  @Published var activePreset: FanPreset = .auto
  @Published var statusMessage: String = L10n.current.connecting
  @Published var canWrite = false
  @Published var hardwareSummary: String = ""
  @Published var safetyNotice: String?
  @Published var unlinkRPM: [Int: Double] = [:]
  @Published var isInstallingHelper = false

  /// While true, refresh must not overwrite the linked slider position.
  var isDraggingSlider = false

  private var xpc: HelperXPCClient?
  private var pollTimer: DispatchSourceTimer?
  private var localController: FanController?
  private let safety = SafetyPolicy()
  private var wakeObserver: NSObjectProtocol?
  private var desiredManual = false

  private var L: L10n { L10n.current }

  private func onMain(_ body: @escaping @Sendable () -> Void) {
    if Thread.isMainThread {
      body()
    } else {
      DispatchQueue.main.async(execute: body)
    }
  }

  func start() {
    onMain { self.statusMessage = self.L.readingSensors }
    openLocalRead()
    tryConnectHelper()
    refresh()
    startPolling()
    observeWake()
  }

  func stop() {
    pollTimer?.cancel()
    pollTimer = nil
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
    onMain {
      self.statusMessage = self.canWrite ? self.L.helperConnected : self.L.monitorMode
      self.updateHardwareSummary()
    }
  }

  private func updateHardwareSummary() {
    guard let c = localController else { return }
    let count = (try? c.fanCount()) ?? fans.count
    let summary = L.hardwareSummary(fanCount: count)
    onMain { self.hardwareSummary = summary }
  }

  private func openLocalRead() {
    do {
      localController = FanController(connection: try SMCConnection())
      updateHardwareSummary()
    } catch {
      let msg = "\(L.smcReadFailed): \(error.localizedDescription)"
      onMain { self.statusMessage = msg }
    }
  }

  private func tryConnectHelper() {
    xpc?.invalidate()
    let client = HelperXPCClient(machServiceName: AirPulseConfig.helperMachService)
    client.setDisconnectHandler { [weak self] in
      DispatchQueue.main.async {
        self?.canWrite = false
      }
    }
    xpc = client

    client.ping { [weak self] ok in
      DispatchQueue.main.async {
        guard let self else { return }
        self.canWrite = ok
        self.statusMessage = ok ? self.L.helperConnected : self.L.monitorMode
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      guard let self, !self.canWrite else { return }
      self.statusMessage = self.L.monitorMode
    }
  }

  func installHelper() {
    let helperURL = Bundle.main.bundleURL
      .appendingPathComponent("Contents/MacOS/AirPulseHelper")
    var helperPath = helperURL.path
    if !FileManager.default.isExecutableFile(atPath: helperPath) {
      helperPath = ProductPaths.helperPath
    }
    guard FileManager.default.isExecutableFile(atPath: helperPath) else {
      onMain { self.statusMessage = self.L.helperMissingBinary }
      return
    }

    onMain {
      self.isInstallingHelper = true
      self.statusMessage = self.L.helperInstalling
    }

    let dst = "/usr/local/libexec/AirPulseHelper"
    let plistPath = "/Library/LaunchDaemons/\(AirPulseConfig.helperLabel).plist"
    let label = AirPulseConfig.helperLabel
    let mach = AirPulseConfig.helperMachService

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
        [.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
    } catch {
      onMain {
        self.isInstallingHelper = false
        self.statusMessage = error.localizedDescription
      }
      return
    }

    let scriptPath = tempURL.path
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      let quoted = scriptPath
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
      proc.arguments = [
        "-e",
        "do shell script \"/bin/bash \\\"\(quoted)\\\"\" with administrator privileges",
      ]
      do {
        try proc.run()
        proc.waitUntilExit()
        let ok = proc.terminationStatus == 0
        try? FileManager.default.removeItem(at: tempURL)
        DispatchQueue.main.async {
          guard let self else { return }
          self.isInstallingHelper = false
          if ok {
            // Helper may already be installed from a previous attempt.
            self.tryConnectHelper()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
              let success = self.canWrite
              self.statusMessage =
                success ? self.L.helperConnected : self.L.helperInstallFailed
              Task { @MainActor in
                self.showInstallResultAlert(success: success)
              }
            }
          } else {
            // Install may have succeeded earlier even if this run was cancelled.
            self.tryConnectHelper()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
              if self.canWrite {
                self.statusMessage = self.L.helperConnected
                Task { @MainActor in
                  self.showInstallResultAlert(success: true)
                }
              } else {
                self.statusMessage = self.L.helperInstallFailed
                Task { @MainActor in
                  self.showInstallResultAlert(success: false)
                }
              }
            }
          }
        }
      } catch {
        try? FileManager.default.removeItem(at: tempURL)
        DispatchQueue.main.async {
          self?.isInstallingHelper = false
          self?.statusMessage = error.localizedDescription
        }
      }
    }
  }

  @MainActor
  private func showInstallResultAlert(success: Bool) {
    let L = self.L
    let alert = NSAlert()
    alert.messageText = success ? L.helperConnected : L.helperInstallFailed
    alert.informativeText = success ? L.enableFanControlHint : L.needHelperToWrite
    alert.alertStyle = success ? .informational : .warning
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
  }

  func refresh() {
    if let c = localController {
      let newFans = (try? c.allFans()) ?? []
      let temps = c.readTemperatures(primaryOnly: true)
      let count = (try? c.fanCount()) ?? newFans.count
      let summary = L.hardwareSummary(fanCount: count)

      onMain {
        if !newFans.isEmpty { self.fans = newFans }
        self.temperatures = temps
        self.hardwareSummary = summary
        if self.unlinkRPM.isEmpty {
          for fan in newFans {
            let span = max(1, fan.maxRPM - fan.minRPM)
            self.unlinkRPM[fan.index] = Double((fan.actualRPM - fan.minRPM) / span)
          }
        }
        if !self.isDraggingSlider, self.activePreset != .auto,
          let first = newFans.first, first.maxRPM > first.minRPM
        {
          self.linkedFraction = Double(
            (first.targetRPM - first.minRPM) / (first.maxRPM - first.minRPM))
        }
        self.enforceSafetyLocally()
      }
    }

    // XPC path — decode on XPC queue inside HelperXPCClient, then hop to main.
    xpc?.listFans { [weak self] remoteFans in
      guard !remoteFans.isEmpty else { return }
      DispatchQueue.main.async {
        self?.fans = remoteFans
      }
    }
  }

  private func requireWriteAccess() -> Bool {
    if canWrite { return true }
    onMain { self.statusMessage = self.L.needHelperToWrite }
    return false
  }

  func applyPreset(_ preset: FanPreset) {
    onMain {
      self.activePreset = preset
      self.desiredManual = preset != .auto
      if let fraction = preset.speedFraction {
        self.linkedFraction = fraction
      }
    }
    guard requireWriteAccess() else { return }
    xpc?.applyPreset(preset.rawValue) { [weak self] ok, err in
      DispatchQueue.main.async {
        guard let self else { return }
        self.statusMessage = ok ? self.L.presetStatus(preset) : (err ?? self.L.failed)
        self.refresh()
      }
    }
  }

  func applyLinkedFraction(_ fraction: Double) {
    onMain {
      self.linkedFraction = fraction
      self.activePreset = .balanced
      self.desiredManual = true
    }
    guard requireWriteAccess() else { return }
    xpc?.setLinkedFraction(fraction) { [weak self] ok, err in
      DispatchQueue.main.async {
        guard let self else { return }
        self.statusMessage = ok ? self.L.linkedStatus(Int(fraction * 100)) : (err ?? self.L.failed)
        self.refresh()
      }
    }
  }

  func applyUnlinked(fanIndex: Int, fraction: Double) {
    onMain {
      self.unlinkRPM[fanIndex] = fraction
      self.desiredManual = true
    }
    guard let fan = fans.first(where: { $0.index == fanIndex }) else { return }
    let rpm = fan.minRPM + Float(fraction) * (fan.maxRPM - fan.minRPM)
    guard requireWriteAccess() else { return }
    xpc?.setFanRPM(UInt(fanIndex), rpm: rpm) { [weak self] ok, err in
      DispatchQueue.main.async {
        guard let self else { return }
        self.statusMessage =
          ok ? self.L.fanRPMStatus(fanIndex, rpm: Int(rpm)) : (err ?? self.L.failed)
        self.refresh()
      }
    }
  }

  func restoreAuto() {
    onMain {
      self.activePreset = .auto
      self.desiredManual = false
    }
    guard requireWriteAccess() else { return }
    xpc?.restoreAuto { [weak self] ok, err in
      DispatchQueue.main.async {
        guard let self else { return }
        self.statusMessage = ok ? self.L.restoredAuto : (err ?? self.L.failed)
        self.refresh()
      }
    }
  }

  private func startPolling() {
    pollTimer?.cancel()
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(deadline: .now() + 1, repeating: AirPulseConfig.pollInterval)
    timer.setEventHandler { [weak self] in
      self?.refresh()
    }
    timer.resume()
    pollTimer = timer
  }

  private func observeWake() {
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
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

  private func enforceSafetyLocally() {
    // Caller must be on main.
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
