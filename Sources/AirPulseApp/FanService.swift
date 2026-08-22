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
    pingRaw { reply in
      completion(reply != nil)
    }
  }

  /// Returns the raw ping payload (`pong` or `pong:<version>`).
  func pingRaw(completion: @escaping @Sendable (String?) -> Void) {
    let p = proxy { completion(nil) }
    guard let p else {
      completion(nil)
      return
    }
    p.ping { reply in completion(reply) }
  }

  func listFans(completion: @escaping @Sendable ([FanSnapshot]) -> Void) {
    let p = proxy { completion([]) }
    p?.listFans { data, _ in
      let fans = (data ?? []).compactMap { AirPulseCoding.decode(FanSnapshot.self, from: $0) }
      completion(fans)
    }
  }

  func openSMC(completion: @escaping @Sendable (Bool, String?) -> Void) {
    let p = proxy { completion(false, "XPC disconnected") }
    p?.openSMC(reply: completion)
  }

  func warmupManual(completion: @escaping @Sendable (Bool, String?) -> Void) {
    let p = proxy { completion(false, "XPC disconnected") }
    p?.warmupManual(reply: completion)
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
  @Published var statusMessage: String = L10n.current.connecting {
    didSet { lastSmartReading = nil }
  }
  @Published var canWrite = false
  @Published var hardwareSummary: String = ""
  /// Nil until SMC has been probed. 0 = fanless (e.g. MacBook Air).
  @Published var discoveredFanCount: Int?
  @Published var safetyNotice: String?
  @Published var unlinkRPM: [Int: Double] = [:]
  @Published var isInstallingHelper = false
  @Published var launchAtLoginEnabled = false
  @Published var helperNeedsUpdate = false

  /// While true, refresh must not overwrite the linked slider position.
  var isDraggingSlider = false

  private var xpc: HelperXPCClient?
  private var pollTimer: DispatchSourceTimer?
  private var localController: FanController?
  private var safety = SafetyPolicy()
  private var wakeObserver: NSObjectProtocol?
  private var desiredManual = false
  private var isStarted = false
  /// Bumps on every helper reconnect so stale disconnect/ping callbacks are ignored.
  private var helperGeneration = 0
  private var didRestoreAfterConnect = false
  private var lastCurveFraction: Double?
  private var lastSmartPhase: SmartPhase?
  private var isRestoringForTerminate = false
  /// Non-nil exactly while `statusMessage` shows the Smart readout, so the line
  /// can be rebuilt when the unit or language changes. Any other status write
  /// drops it through `statusMessage`'s observer.
  private var lastSmartReading: (celsius: Float, percent: Int, phase: SmartPhase)?
  private let cpuBrandName = SMCConnection.cpuBrand()
  private let log = DiagnosticLog.shared
  private let smartLock = NSLock()
  private var smartGovernor = SmartGovernor()

  private var L: L10n { L10n.current }

  private var maxPrimaryTemp: Float? {
    temperatures.map(\.celsius).max()
  }

  private func onMain(_ body: @escaping @Sendable () -> Void) {
    if Thread.isMainThread {
      body()
    } else {
      DispatchQueue.main.async(execute: body)
    }
  }

  private func persistSettings() {
    let defaults = UserDefaults.standard
    defaults.set(activePreset.rawValue, forKey: SettingsKeys.activePreset)
    defaults.set(linkedFraction, forKey: SettingsKeys.linkedFraction)
    defaults.set(linkedEnabled, forKey: SettingsKeys.linkedEnabled)
    defaults.set(desiredManual, forKey: SettingsKeys.desiredManual)
    defaults.set(launchAtLoginEnabled, forKey: SettingsKeys.launchAtLogin)
  }

  func persistLinkedEnabled() {
    onMain { self.persistSettings() }
  }

  private func loadPersistedSettings() {
    let defaults = UserDefaults.standard
    if let raw = defaults.string(forKey: SettingsKeys.activePreset) {
      let migrated: String
      switch raw {
      case "curve": migrated = "smart"
      case "balanced", "quiet", "cool": migrated = "custom"
      default: migrated = raw
      }
      if let preset = FanPreset(rawValue: migrated) {
        activePreset = preset
      }
    }
    if defaults.object(forKey: SettingsKeys.linkedFraction) != nil {
      linkedFraction = defaults.double(forKey: SettingsKeys.linkedFraction)
    }
    if defaults.object(forKey: SettingsKeys.linkedEnabled) != nil {
      linkedEnabled = defaults.bool(forKey: SettingsKeys.linkedEnabled)
    }
    desiredManual = defaults.bool(forKey: SettingsKeys.desiredManual)
    launchAtLoginEnabled = LaunchAtLogin.isEnabled
      || defaults.bool(forKey: SettingsKeys.launchAtLogin)
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    let ok = LaunchAtLogin.setEnabled(enabled)
    onMain {
      self.launchAtLoginEnabled = LaunchAtLogin.isEnabled
      if !ok {
        self.statusMessage = self.L.launchAtLoginFailed
      }
      self.persistSettings()
    }
  }

  func start() {
    if !isStarted {
      loadPersistedSettings()
      log.info("app", "Started — preset \(activePreset.rawValue), linked \(Int(linkedFraction * 100))%")
      onMain { self.statusMessage = self.L.readingSensors }
      openLocalRead()
      startPolling()
      observeWake()
      isStarted = true
      tryConnectHelper()
    } else if xpc == nil || !canWrite {
      // Reconnect only when the helper link is missing or not writable.
      tryConnectHelper()
    }
    refresh()
  }

  func stop() {
    prepareToTerminate(waitSeconds: 1.5)
    pollTimer?.cancel()
    pollTimer = nil
    if let wakeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
      self.wakeObserver = nil
    }
    helperGeneration += 1
    xpc?.invalidate()
    xpc = nil
    isStarted = false
    onMain {
      self.canWrite = false
      self.helperNeedsUpdate = false
    }
  }

  /// Best-effort restore Auto before the process exits (Quit or system terminate).
  func prepareToTerminate(waitSeconds: TimeInterval = 1.5) {
    guard !isRestoringForTerminate else { return }
    isRestoringForTerminate = true
    defer { isRestoringForTerminate = false }

    guard desiredManual else {
      onMain {
        self.activePreset = .auto
        self.desiredManual = false
        self.persistSettings()
      }
      return
    }

    // Prefer XPC restore; Helper also restores when the last client disconnects.
    if canWrite, let xpc {
      let sem = DispatchSemaphore(value: 0)
      xpc.restoreAuto { [weak self] ok, _ in
        DispatchQueue.main.async {
          guard let self else { return }
          self.activePreset = .auto
          self.desiredManual = false
          self.safety.reset()
          self.persistSettings()
          if ok {
            self.statusMessage = self.L.restoredAuto
          }
        }
        sem.signal()
      }
      _ = sem.wait(timeout: .now() + waitSeconds)
    } else {
      onMain {
        self.activePreset = .auto
        self.desiredManual = false
        self.safety.reset()
        self.persistSettings()
      }
    }
  }

  private static func parseHelperVersion(_ reply: String) -> Int {
    if reply.hasPrefix("pong:"), let v = Int(reply.dropFirst(5)) {
      return v
    }
    // Legacy helpers answered plain "pong".
    if reply == "pong" { return 1 }
    return 0
  }

  func reloadLocalizedStrings() {
    onMain {
      if let reading = self.lastSmartReading {
        self.setSmartStatus(celsius: reading.celsius, percent: reading.percent, phase: reading.phase)
      } else {
        self.statusMessage = self.canWrite ? self.L.helperConnected : self.L.monitorMode
      }
      self.updateHardwareSummary()
    }
  }

  /// Rebuilds the Smart readout in the current unit so the status line follows
  /// the °C/°F switch instead of waiting for the next fan write.
  func refreshStatusMessage() {
    onMain {
      guard let reading = self.lastSmartReading else { return }
      self.setSmartStatus(celsius: reading.celsius, percent: reading.percent, phase: reading.phase)
    }
  }

  /// Caller must be on main. `statusMessage` goes first so its observer clears
  /// the previous reading before the fresh one is stored.
  private func setSmartStatus(celsius: Float, percent: Int, phase: SmartPhase) {
    statusMessage = L.smartStatus(
      TemperatureUnit.cached.format(celsius: celsius), percent: percent, phase: phase)
    lastSmartReading = (celsius, percent, phase)
  }

  private func resetSmartGovernor() {
    smartLock.lock()
    smartGovernor.reset()
    smartLock.unlock()
    lastCurveFraction = nil
    lastSmartPhase = nil
  }

  private func updateHardwareSummary() {
    guard let c = localController else { return }
    let count = (try? c.fanCount()) ?? fans.count
    let summary = L.hardwareSummary(fanCount: count, chip: cpuBrandName)
    onMain {
      self.discoveredFanCount = count
      if count <= 1, self.linkedEnabled == false {
        self.linkedEnabled = true
      }
      self.hardwareSummary = summary
    }
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
    helperGeneration += 1
    let generation = helperGeneration
    didRestoreAfterConnect = false

    xpc?.invalidate()
    let client = HelperXPCClient(machServiceName: AirPulseConfig.helperMachService)
    client.setDisconnectHandler { [weak self] in
      DispatchQueue.main.async {
        guard let self, self.helperGeneration == generation else { return }
        self.canWrite = false
      }
    }
    xpc = client

    client.pingRaw { [weak self] reply in
      DispatchQueue.main.async {
        guard let self, self.helperGeneration == generation else { return }
        guard let reply else {
          self.canWrite = false
          self.helperNeedsUpdate = false
          self.statusMessage = self.L.monitorMode
          self.log.warning("helper", "XPC ping failed — monitoring only")
          return
        }
        let version = Self.parseHelperVersion(reply)
        let needsUpdate = version < AirPulseConfig.helperAPIVersion
        self.helperNeedsUpdate = needsUpdate
        self.canWrite = !needsUpdate
        self.log.info("helper", "Connected — API \(version) (need \(AirPulseConfig.helperAPIVersion))")
        if needsUpdate {
          self.statusMessage = self.L.helperNeedsUpdate
          self.log.warning("helper", "Helper update required")
        } else {
          self.statusMessage = self.L.helperConnected
          self.warmupHelperThenRestore(generation: generation)
        }
      }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
      guard let self, self.helperGeneration == generation, !self.canWrite else { return }
      self.statusMessage = self.L.monitorMode
    }
  }

  private func warmupHelperThenRestore(generation: Int) {
    xpc?.openSMC { [weak self] _, _ in
      self?.xpc?.warmupManual { [weak self] _, _ in
        DispatchQueue.main.async {
          guard let self, self.helperGeneration == generation else { return }
          self.restorePersistedControlIfNeeded()
        }
      }
    }
  }

  private func restorePersistedControlIfNeeded() {
    guard canWrite, !didRestoreAfterConnect else { return }
    didRestoreAfterConnect = true
    guard desiredManual || activePreset == .smart else { return }
    if activePreset == .auto { return }
    applyPreset(activePreset, userInitiated: false)
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
    // Dragging a slider: skip UI churn so SwiftUI does not rebuild mid-gesture.
    // Safety still runs on the next non-drag poll.
    if isDraggingSlider { return }

    if let c = localController {
      let newFans = (try? c.allFans()) ?? []
      let temps = c.readTemperatures(primaryOnly: true)
      let count = (try? c.fanCount()) ?? newFans.count
      let summary = L.hardwareSummary(fanCount: count, chip: cpuBrandName)

      onMain {
        guard !self.isDraggingSlider else { return }
        self.discoveredFanCount = count
        if count <= 1, self.linkedEnabled == false {
          self.linkedEnabled = true
        }
        if count == 0 {
          if !self.fans.isEmpty { self.fans = [] }
        } else if !newFans.isEmpty, newFans != self.fans {
          self.fans = newFans
        }
        if temps != self.temperatures { self.temperatures = temps }
        if summary != self.hardwareSummary { self.hardwareSummary = summary }
        if self.unlinkRPM.isEmpty {
          for fan in newFans {
            let span = max(1, fan.maxRPM - fan.minRPM)
            self.unlinkRPM[fan.index] = Double((fan.actualRPM - fan.minRPM) / span)
          }
        }
        // Keep the user's slider position as source of truth in manual mode;
        // never yank it back from hardware while dragging or after a write.
        self.enforceSafetyLocally()
      }
      // Local SMC already feeds the popover; skip a second XPC fan fetch that
      // would publish again ~1s and hitch the slider.
      return
    }

    // Fallback when local SMC is unavailable.
    xpc?.listFans { [weak self] remoteFans in
      guard let self, !remoteFans.isEmpty, !self.isDraggingSlider else { return }
      DispatchQueue.main.async {
        guard !self.isDraggingSlider, remoteFans != self.fans else { return }
        self.fans = remoteFans
      }
    }
  }

  private func requireWriteAccess() -> Bool {
    if canWrite { return true }
    onMain { self.statusMessage = self.L.needHelperToWrite }
    return false
  }

  func applyPreset(_ preset: FanPreset, userInitiated: Bool = true) {
    let maxTemp = maxPrimaryTemp
    let previous = activePreset
    if preset != .smart {
      resetSmartGovernor()
    } else if userInitiated, previous != .smart {
      resetSmartGovernor()
    }
    log.info(
      "preset",
      "\(userInitiated ? "User" : "Restore") \(previous.rawValue) → \(preset.rawValue)"
        + (maxTemp.map { String(format: " (%.1f°C)", $0) } ?? "")
    )

    onMain {
      self.activePreset = preset
      self.desiredManual = preset != .auto
      if preset == .custom {
        let base = self.linkedFraction > 0 ? self.linkedFraction : (preset.speedFraction ?? 0.45)
        self.linkedFraction = max(base, self.safety.minimumFraction(forMaxTemp: maxTemp))
      }
      self.persistSettings()
    }
    guard requireWriteAccess() else { return }

    if preset == .smart {
      xpc?.applyPreset(preset.rawValue) { [weak self] ok, err in
        if let self, !ok {
          self.log.warning("smart", err ?? "Helper applyPreset smart failed")
        }
        self?.applyCurveFraction(force: true)
      }
      return
    }

    if preset == .custom {
      let value = linkedFraction > 0 ? linkedFraction : (preset.speedFraction ?? 0.45)
      applyLinkedFraction(value, userInitiated: userInitiated)
      return
    }

    xpc?.applyPreset(preset.rawValue) { [weak self] ok, err in
      DispatchQueue.main.async {
        guard let self else { return }
        if ok {
          self.statusMessage = self.L.presetStatus(preset)
          self.log.info("preset", "Helper applied \(preset.rawValue)")
        } else {
          self.statusMessage = err ?? self.L.failed
          self.log.error("preset", err ?? self.L.failed)
        }
        self.refresh()
      }
    }
  }

  func applyLinkedFraction(_ fraction: Double, userInitiated: Bool = true) {
    let floored = max(fraction, safety.minimumFraction(forMaxTemp: maxPrimaryTemp))
    if floored > fraction + 0.01 {
      onMain {
        self.safetyNotice = self.L.safetyThermalFloor
        self.statusMessage = self.L.safetyThermalFloor
      }
      log.warning(
        "safety",
        String(format: "Thermal floor raised fan to %d%%", Int(floored * 100))
      )
    }
    if userInitiated {
      resetSmartGovernor()
    }
    onMain {
      self.linkedFraction = floored
      if userInitiated {
        if self.activePreset != .custom {
          self.log.info("preset", "\(self.activePreset.rawValue) → custom")
        }
        self.activePreset = .custom
      }
      self.desiredManual = true
      self.lastCurveFraction = nil
      self.persistSettings()
    }
    guard requireWriteAccess() else { return }
    xpc?.setLinkedFraction(floored) { [weak self] ok, err in
      DispatchQueue.main.async {
        guard let self else { return }
        if ok {
          self.statusMessage = self.L.linkedStatus(Int(floored * 100))
          self.log.info("fan", "Linked \(Int(floored * 100))%")
        } else {
          self.statusMessage = err ?? self.L.failed
          self.log.error("fan", err ?? self.L.failed)
        }
        self.refresh()
      }
    }
  }

  private func applyEmergencyCool() {
    onMain {
      self.safetyNotice = self.L.safetyWarning
      self.statusMessage = self.L.safetyWarning
    }
    applyLinkedFraction(FanPreset.emergencyCoolFraction)
  }

  private func applyCurveFraction(force: Bool = false) {
    guard canWrite, activePreset == .smart else { return }
    let temp = maxPrimaryTemp ?? localController?.maxPrimaryTemperature() ?? 60
    smartLock.lock()
    let decision = smartGovernor.evaluate(celsius: temp)
    smartLock.unlock()
    var fraction = max(decision.appliedFraction, safety.minimumFraction())
    fraction = min(1, max(0, fraction))
    if !force,
      let last = lastCurveFraction,
      abs(last - fraction) < AirPulseConfig.smartMinFractionDelta,
      lastSmartPhase == decision.phase
    {
      return
    }
    lastCurveFraction = fraction
    lastSmartPhase = decision.phase
    let applied = fraction
    let phase = decision.phase
    onMain {
      self.linkedFraction = applied
      self.activePreset = .smart
      self.desiredManual = true
      self.persistSettings()
    }
    log.info(
      "smart",
      String(
        format: "%.1f°C (hold %.1f°C) raw %d%% → %d%% %@",
        decision.sensorCelsius,
        decision.effectiveCelsius,
        Int(decision.rawFraction * 100),
        Int(applied * 100),
        phase.rawValue
      )
    )
    xpc?.setLinkedFraction(applied) { [weak self] ok, err in
      DispatchQueue.main.async {
        guard let self else { return }
        if self.activePreset != .smart { return }
        if ok {
          self.setSmartStatus(celsius: temp, percent: Int(applied * 100), phase: phase)
        } else {
          self.statusMessage = err ?? self.L.failed
          self.log.error("smart", err ?? self.L.failed)
        }
      }
    }
  }

  func applyUnlinked(fanIndex: Int, fraction: Double) {
    onMain {
      self.unlinkRPM[fanIndex] = fraction
      self.desiredManual = true
      self.persistSettings()
    }
    guard let fan = fans.first(where: { $0.index == fanIndex }) else { return }
    let rpm = fan.minRPM + Float(fraction) * (fan.maxRPM - fan.minRPM)
    guard requireWriteAccess() else { return }
    xpc?.setFanRPM(UInt(fanIndex), rpm: rpm) { [weak self] ok, err in
      DispatchQueue.main.async {
        guard let self else { return }
        if ok {
          self.statusMessage = self.L.fanRPMStatus(fanIndex, rpm: Int(rpm))
          self.log.info("fan", "Fan \(fanIndex) → \(Int(rpm)) RPM")
        } else {
          self.statusMessage = err ?? self.L.failed
          self.log.error("fan", err ?? self.L.failed)
        }
        self.refresh()
      }
    }
  }

  func restoreAuto() {
    resetSmartGovernor()
    log.info("preset", "Restore Auto")
    onMain {
      self.activePreset = .auto
      self.desiredManual = false
      self.lastCurveFraction = nil
      self.safety.reset()
      self.persistSettings()
    }
    guard requireWriteAccess() else { return }
    xpc?.restoreAuto { [weak self] ok, err in
      DispatchQueue.main.async {
        guard let self else { return }
        if ok {
          self.statusMessage = self.L.restoredAuto
          self.log.info("preset", "Helper restored Auto")
        } else {
          self.statusMessage = err ?? self.L.failed
          self.log.error("preset", err ?? self.L.failed)
        }
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
    if let wakeObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
      self.wakeObserver = nil
    }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self, self.desiredManual, self.canWrite else { return }
      self.statusMessage = self.L.reassertAfterWake
      self.log.info("app", "Wake — reassert \(self.activePreset.rawValue)")
      if self.activePreset == .smart {
        self.applyCurveFraction(force: true)
      } else if self.linkedEnabled {
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
      log.warning(
        "safety",
        String(format: "Critical %.1f°C — restore Auto", maxTemp ?? 0)
      )
      if desiredManual, canWrite { restoreAuto() }
    case .forceEmergencyCool:
      safetyNotice = L.safetyWarning
      log.warning(
        "safety",
        String(format: "Emergency cool at %.1f°C (preset %@)", maxTemp ?? 0, activePreset.rawValue)
      )
      if activePreset == .smart, canWrite {
        applyCurveFraction(force: true)
      } else if canWrite {
        applyEmergencyCool()
      }
    case .raiseHighFloor, .raiseLowFloor:
      if desiredManual {
        if activePreset == .smart, canWrite {
          applyCurveFraction(force: false)
        } else {
          let floor = safety.minimumFraction()
          if linkedFraction + 0.01 < floor, canWrite {
            safetyNotice = L.safetyThermalFloor
            applyLinkedFraction(floor, userInitiated: false)
          }
        }
      }
    case .none:
      if safetyNotice == L.safetyCritical || safetyNotice == L.safetyWarning
        || safetyNotice == L.safetyThermalFloor
      {
        let clearBelow =
          AirPulseConfig.lowFloorCelsius - AirPulseConfig.safetyHysteresisCelsius
        if let maxTemp, maxTemp < clearBelow {
          safetyNotice = nil
        }
      }
    }

    if activePreset == .smart, canWrite, !isDraggingSlider {
      applyCurveFraction(force: false)
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
