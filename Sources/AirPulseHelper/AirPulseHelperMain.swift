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
  private var desiredFraction: Double?
  private var desiredPreset: FanPreset = .auto
  private var smartGovernor = SmartGovernor()
  private let queue = DispatchQueue(label: "com.bingtaohu.AirPulse.helper")
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
        self.restoreIfNeededOnClientGone()
        DispatchQueue.main.async { exit(0) }
      }
    }
  }

  private func restoreIfNeededOnClientGone() {
    guard desiredPreset != .auto || desiredFraction != nil else { return }
    try? ensureController().restoreSystemControl()
    desiredPreset = .auto
    desiredFraction = nil
    smartGovernor.reset()
    stopReassert()
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
    do {
      _ = try ensureController()
      reply(true, nil)
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  func warmupManual(reply: @escaping (Bool, String?) -> Void) {
    do {
      try ensureController().warmupManualMode()
      reply(true, nil)
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  func listFans(reply: @escaping ([Data]?, String?) -> Void) {
    do {
      let fans = try ensureController().allFans()
      reply(fans.compactMap { AirPulseCoding.encode($0) }, nil)
    } catch {
      reply(nil, error.localizedDescription)
    }
  }

  func listTemperatures(reply: @escaping ([Data]?, String?) -> Void) {
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
    do {
      let c = try ensureController()
      _ = try c.applyPreset(preset)
      desiredPreset = preset
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
    do {
      let c = try ensureController()
      _ = try c.setLinkedFraction(fraction)
      // Smart applies speeds through this same write path. Keep Smart so
      // reassert continues to hold / decay instead of becoming a fixed Custom.
      if desiredPreset != .smart {
        desiredPreset = .custom
        smartGovernor.reset()
      }
      desiredFraction = fraction
      startReassert()
      reply(true, nil)
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  func setFanRPM(_ fanIndex: UInt, rpm: Float, reply: @escaping (Bool, String?) -> Void) {
    do {
      let c = try ensureController()
      _ = try c.enableManualMode(fanIndex: Int(fanIndex))
      try c.setTargetRPM(fanIndex: Int(fanIndex), rpm: rpm)
      startReassert()
      reply(true, nil)
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  func restoreAuto(reply: @escaping (Bool, String?) -> Void) {
    do {
      try ensureController().restoreSystemControl()
      desiredPreset = .auto
      desiredFraction = nil
      smartGovernor.reset()
      stopReassert()
      reply(true, nil)
    } catch {
      reply(false, error.localizedDescription)
    }
  }

  func hardwareInfo(reply: @escaping ([String: String]) -> Void) {
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
    guard let c = try? ensureController() else { return }
    let maxTemp = c.maxPrimaryTemperature()
    switch safety.evaluate(maxTemp: maxTemp) {
    case .restoreAuto:
      try? c.restoreSystemControl()
      desiredPreset = .auto
      desiredFraction = nil
      stopReassert()
      return
    case .forceEmergencyCool:
      desiredFraction = FanPreset.emergencyCoolFraction
      if desiredPreset != .smart {
        desiredPreset = .custom
      }
    case .raiseHighFloor, .raiseLowFloor:
      let floor = safety.minimumFraction()
      if let f = desiredFraction, f < floor {
        desiredFraction = floor
        if desiredPreset != .smart {
          desiredPreset = .custom
        }
      }
    case .none:
      break
    }

    if desiredPreset == .smart {
      // The app owns hold / decay. Reassert the last commanded speed so the
      // helper cannot drop fans on a 1-second temperature dip.
      if var fraction = desiredFraction {
        fraction = max(fraction, safety.minimumFraction())
        desiredFraction = fraction
        _ = try? c.setLinkedFraction(fraction)
        return
      }
      if let temp = maxTemp {
        var fraction = smartGovernor.evaluate(celsius: temp).appliedFraction
        fraction = max(fraction, safety.minimumFraction())
        desiredFraction = fraction
        _ = try? c.setLinkedFraction(fraction)
      }
      return
    }

    if var fraction = desiredFraction {
      fraction = max(fraction, safety.minimumFraction())
      desiredFraction = fraction
      _ = try? c.setLinkedFraction(fraction)
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
