import AirPulseProtocol
import FanKit
import Foundation
import SMCKit

final class AirPulseHelperService: NSObject, NSXPCListenerDelegate, AirPulseHelperProtocol,
  @unchecked Sendable
{
  private let listener: NSXPCListener
  private var controller: FanController?
  private var safety = SafetyPolicy()
  private var reassertTimer: DispatchSourceTimer?
  /// What the app asked for, before the thermal floor. Floors are applied on
  /// every write so fans come back down once a floor disengages.
  private var desiredFraction: Double?
  /// Per-fan targets from `setFanRPM`. While set they replace the linked fraction.
  private var desiredFanRPM: [Int: Float] = [:]
  private var desiredPreset: FanPreset = .auto
  private var smartGovernor = SmartGovernor()
  private let queue = DispatchQueue(label: "com.bingtaohu.AirPulse.helper")
  /// XPC requests arrive on connection queues while the reassert timer runs on
  /// `queue`; both read and write the state above and the SMC.
  private let stateLock = NSLock()
  private var connectionCount = 0
  private let connectionLock = NSLock()

  init(machServiceName: String) {
    listener = NSXPCListener(machServiceName: machServiceName)
    super.init()
    listener.delegate = self
  }

  func start() {
    listener.resume()
    installSignalHandlers()
    RunLoop.main.run()
  }

  private func installSignalHandlers() {
    signal(SIGTERM) { _ in
      // Best-effort; process is exiting. Prefer XPC disconnect restore.
    }
  }
  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection)
    -> Bool
  {
    newConnection.exportedInterface = NSXPCInterface(with: AirPulseHelperProtocol.self)
    newConnection.exportedObject = self
    connectionLock.lock()
    connectionCount += 1
    connectionLock.unlock()
    newConnection.invalidationHandler = { [weak self] in
      self?.clientDisconnected()
    }
    newConnection.resume()
    return true
  }

  private func clientDisconnected() {
    queue.async { [weak self] in
      guard let self else { return }
      self.connectionLock.lock()
      self.connectionCount = max(0, self.connectionCount - 1)
      let remaining = self.connectionCount
      self.connectionLock.unlock()
      if remaining == 0 {
        self.restoreOnClientGone()
        DispatchQueue.main.async { exit(0) }
      }
    }
  }

  /// Nobody is managing the fans any more, so hand them back to macOS whatever
  /// was asked for last. Guarding on the preset let a crashed app strand a fan
  /// it had set on its own in manual mode, with no thermal floor.
  private func restoreOnClientGone() {
    stateLock.lock()
    defer { stateLock.unlock() }
    stopReassert()
    try? ensureController().restoreSystemControl()
    desiredPreset = .auto
    desiredFraction = nil
    desiredFanRPM.removeAll()
    smartGovernor.reset()
  }

  private func ensureController() throws -> FanController {
    if let controller { return controller }
    let conn = try SMCConnection()
    let c = FanController(connection: conn)
    controller = c
    return c
  }

  func ping(reply: @escaping (String) -> Void) {
    reply("pong:\(AirPulseConfig.helperAPIVersion)")
  }

  func openSMC(reply: @escaping (Bool, String?) -> Void) {
    stateLock.lock()
    defer { stateLock.unlock() }
    do {
      _ = try ensureController()
      reply(true, nil)
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  func warmupManual(reply: @escaping (Bool, String?) -> Void) {
    stateLock.lock()
    defer { stateLock.unlock() }
    do {
      try ensureController().warmupManualMode()
      reply(true, nil)
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  func listFans(reply: @escaping ([Data]?, String?) -> Void) {
    stateLock.lock()
    defer { stateLock.unlock() }
    do {
      let fans = try ensureController().allFans()
      reply(fans.compactMap { AirPulseCoding.encode($0) }, nil)
    } catch {
      reply(nil, error.localizedDescription)
    }
  }

  func listTemperatures(reply: @escaping ([Data]?, String?) -> Void) {
    stateLock.lock()
    defer { stateLock.unlock() }
    do {
      let temps = try ensureController().readTemperatures(primaryOnly: false)
      reply(temps.compactMap { AirPulseCoding.encode($0) }, nil)
    } catch {
      reply(nil, error.localizedDescription)
    }
  }

  func applyPreset(_ rawPreset: String, reply: @escaping (Bool, String?) -> Void) {
    guard let preset = FanPreset(rawValue: rawPreset) else {
      reply(false, "Unknown preset")
      return
    }
    stateLock.lock()
    defer { stateLock.unlock() }
    do {
      let c = try ensureController()
      _ = try c.applyPreset(preset)
      desiredPreset = preset
      desiredFanRPM.removeAll()
      if preset == .smart {
        smartGovernor.reset()
        let temp = c.maxPrimaryTemperature() ?? 60
        desiredFraction = smartGovernor.evaluate(celsius: temp).appliedFraction
      } else {
        smartGovernor.reset()
        desiredFraction = preset.speedFraction
      }
      if preset == .auto {
        stopReassert()
      } else {
        startReassert()
      }
      reply(true, nil)
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  func setLinkedFraction(_ fraction: Double, reply: @escaping (Bool, String?) -> Void) {
    stateLock.lock()
    defer { stateLock.unlock() }
    do {
      let c = try ensureController()
      let applied = flooredFraction(fraction, controller: c)
      _ = try c.setLinkedFraction(applied)
      // Smart applies speeds through this same write path. Keep Smart so
      // reassert continues to hold / decay instead of becoming a fixed Custom.
      if desiredPreset != .smart {
        desiredPreset = .custom
        smartGovernor.reset()
      }
      desiredFraction = min(1, max(0, fraction))
      desiredFanRPM.removeAll()
      startReassert()
      reply(true, nil)
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  /// Safety is a floor. A 90°C emergency used to be stored as 0.85 and then
  /// reasserted, which capped fans under the speed macOS Auto was already using.
  private func flooredFraction(_ fraction: Double, controller: FanController) -> Double {
    let temp = controller.maxPrimaryTemperature()
    _ = safety.evaluate(maxTemp: temp)
    return min(1, max(0, max(fraction, safety.minimumFraction())))
  }

  /// Per-fan control. Reasserting the linked speed used to overwrite this
  /// within two seconds, so the target is held here instead.
  func setFanRPM(_ fanIndex: UInt, rpm: Float, reply: @escaping (Bool, String?) -> Void) {
    stateLock.lock()
    defer { stateLock.unlock() }
    do {
      let c = try ensureController()
      _ = safety.evaluate(maxTemp: c.maxPrimaryTemperature())
      desiredFanRPM[Int(fanIndex)] = rpm
      desiredPreset = .custom
      desiredFraction = nil
      smartGovernor.reset()
      try holdFanTargets(c)
      startReassert()
      reply(true, nil)
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  /// Writes every per-fan target, raised to the current thermal floor.
  private func holdFanTargets(_ c: FanController) throws {
    let floor = Float(safety.minimumFraction())
    for fan in try c.allFans() {
      guard let rpm = desiredFanRPM[fan.index] else { continue }
      let span = max(0, fan.maxRPM - fan.minRPM)
      let target = min(fan.maxRPM, max(rpm, fan.minRPM + floor * span))
      _ = try c.enableManualMode(fanIndex: fan.index)
      try c.setTargetRPM(fanIndex: fan.index, rpm: target)
    }
  }

  func restoreAuto(reply: @escaping (Bool, String?) -> Void) {
    stateLock.lock()
    defer { stateLock.unlock() }
    do {
      try ensureController().restoreSystemControl()
      desiredPreset = .auto
      desiredFraction = nil
      desiredFanRPM.removeAll()
      smartGovernor.reset()
      stopReassert()
      reply(true, nil)
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  func hardwareInfo(reply: @escaping ([String: String]) -> Void) {
    stateLock.lock()
    defer { stateLock.unlock() }
    do {
      let c = try ensureController()
      reply([
        "model": SMCConnection.hardwareModel(),
        "modeKeyFormat": c.config.modeKeyFormat,
        "ftstAvailable": c.config.ftstAvailable ? "true" : "false",
        "fanCount": String(try c.fanCount()),
      ])
    } catch {
      reply(["error": error.localizedDescription])
    }
  }

  private func startReassert() {
    stopReassert()
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + AirPulseConfig.reassertInterval, repeating: AirPulseConfig.reassertInterval)
    timer.setEventHandler { [weak self] in
      self?.reassertAndEnforceSafety()
    }
    timer.resume()
    reassertTimer = timer
  }

  private func stopReassert() {
    reassertTimer?.cancel()
    reassertTimer = nil
  }

  private func reassertAndEnforceSafety() {
    stateLock.lock()
    defer { stateLock.unlock() }
    // A tick can already be waiting on the lock when restoreAuto cancels the timer.
    guard reassertTimer != nil, let c = try? ensureController() else { return }
    if safety.evaluate(maxTemp: c.maxPrimaryTemperature()) == .restoreAuto {
      try? c.restoreSystemControl()
      desiredPreset = .auto
      desiredFraction = nil
      desiredFanRPM.removeAll()
      stopReassert()
      return
    }
    // Hold the last command — Smart's too: the app owns hold / decay, so a
    // 1-second temperature dip cannot drop the fans. The floor goes on top at
    // write time only; storing it kept Custom at full speed after a 90°C spike.
    if !desiredFanRPM.isEmpty {
      try? holdFanTargets(c)
    } else if let fraction = desiredFraction {
      _ = try? c.setLinkedFraction(max(fraction, safety.minimumFraction()))
    }
  }
}

@main
struct AirPulseHelperMain {
  static func main() {
    let service = AirPulseHelperService(machServiceName: AirPulseConfig.helperMachService)
    // Also accept anonymous connections when launched in foreground for debugging.
    service.start()
  }
}
