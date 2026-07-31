import Foundation
import SMCKit

public final class FanController: @unchecked Sendable {
  public let connection: SMCConnection
  public let config: SMCHardwareConfig

  private let ftstSettle: TimeInterval = 0.5
  private let ftstRetry: TimeInterval = 0.1

  public init(connection: SMCConnection) {
    self.connection = connection
    self.config = Self.detectHardware(connection: connection)
  }

  public static func detectHardware(connection: SMCConnection) -> SMCHardwareConfig {
    var modeFormat = SMCFanKey.modeLower
    for candidate in [SMCFanKey.modeLower, SMCFanKey.modeUpper] {
      let key = SMCFanKey.key(candidate, fan: 0)
      if connection.keyExists(key) {
        modeFormat = candidate
        break
      }
    }
    let ftst = connection.keyExists(SMCFanKey.forceTest)
    return SMCHardwareConfig(modeKeyFormat: modeFormat, ftstAvailable: ftst)
  }

  public func fanCount() throws -> Int {
    let (bytes, _) = try connection.readKey(SMCFanKey.count)
    return Int(SMCDataFormat.uint8(from: bytes))
  }

  public func readFloatKey(_ key: String) throws -> Float {
    let (bytes, size) = try connection.readKey(key)
    return SMCDataFormat.float(from: bytes, size: size)
  }

  public func readMode(fanIndex: Int) throws -> FanMode {
    let key = SMCFanKey.key(config.modeKeyFormat, fan: fanIndex)
    let (bytes, _) = try connection.readKey(key)
    let raw = SMCDataFormat.uint8(from: bytes)
    return FanMode(rawValue: raw) ?? .unknown
  }

  public func snapshot(fanIndex: Int) throws -> FanSnapshot {
    FanSnapshot(
      index: fanIndex,
      actualRPM: try readFloatKey(SMCFanKey.key(SMCFanKey.actual, fan: fanIndex)),
      targetRPM: try readFloatKey(SMCFanKey.key(SMCFanKey.target, fan: fanIndex)),
      minRPM: try readFloatKey(SMCFanKey.key(SMCFanKey.minimum, fan: fanIndex)),
      maxRPM: try readFloatKey(SMCFanKey.key(SMCFanKey.maximum, fan: fanIndex)),
      mode: try readMode(fanIndex: fanIndex)
    )
  }

  public func allFans() throws -> [FanSnapshot] {
    let count = try fanCount()
    return try (0..<count).map { try snapshot(fanIndex: $0) }
  }

  public func enableManualMode(fanIndex: Int) throws -> FanControlStrategy {
    let modeKey = SMCFanKey.key(config.modeKeyFormat, fan: fanIndex)
    do {
      try connection.writeKey(modeKey, bytes: [FanMode.manual.rawValue])
      return .direct
    } catch {
      guard config.ftstAvailable else { throw error }
    }
    try unlockWithFtst(fanIndex: fanIndex)
    return .ftstUnlock
  }

  public func unlockWithFtst(fanIndex: Int, timeout: TimeInterval = 10) throws {
    try connection.writeKey(SMCFanKey.forceTest, bytes: [1])
    Thread.sleep(forTimeInterval: ftstSettle)
    let modeKey = SMCFanKey.key(config.modeKeyFormat, fan: fanIndex)
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      do {
        try connection.writeKey(modeKey, bytes: [FanMode.manual.rawValue])
        return
      } catch {
        Thread.sleep(forTimeInterval: ftstRetry)
      }
    }
    throw SMCError.timeout
  }

  public func setTargetRPM(fanIndex: Int, rpm: Float) throws {
    let key = SMCFanKey.key(SMCFanKey.target, fan: fanIndex)
    let (_, size) = try connection.readKey(key)
    let bytes = SMCDataFormat.bytes(from: rpm, size: size)
    try connection.writeKey(key, bytes: bytes)
  }

  public func setAuto(fanIndex: Int) throws {
    let modeKey = SMCFanKey.key(config.modeKeyFormat, fan: fanIndex)
    try connection.writeKey(modeKey, bytes: [FanMode.auto.rawValue])
  }

  public func restoreSystemControl() throws {
    let count = try fanCount()
    for i in 0..<count {
      try? setAuto(fanIndex: i)
    }
    if config.ftstAvailable {
      try? connection.writeKey(SMCFanKey.forceTest, bytes: [0])
    }
  }

  /// Set all fans to the same normalized fraction of each fan's min...max range.
  public func setLinkedFraction(_ fraction: Double) throws -> FanControlStrategy {
    let fans = try allFans()
    guard let first = fans.first else { return .direct }
    let strategy = try enableManualMode(fanIndex: first.index)
    for fan in fans {
      _ = try enableManualMode(fanIndex: fan.index)
      let clamped = max(0, min(1, fraction))
      let rpm = fan.minRPM + Float(clamped) * max(0, fan.maxRPM - fan.minRPM)
      try setTargetRPM(fanIndex: fan.index, rpm: rpm)
    }
    return strategy
  }

  public func setLinkedRPM(_ rpm: Float) throws -> FanControlStrategy {
    let fans = try allFans()
    guard let first = fans.first else { return .direct }
    let strategy = try enableManualMode(fanIndex: first.index)
    for fan in fans {
      _ = try enableManualMode(fanIndex: fan.index)
      let clamped = min(max(rpm, fan.minRPM), fan.maxRPM)
      try setTargetRPM(fanIndex: fan.index, rpm: clamped)
    }
    return strategy
  }

  public func applyPreset(_ preset: FanPreset) throws -> FanControlStrategy {
    switch preset {
    case .auto:
      try restoreSystemControl()
      return .direct
    case .quiet, .balanced, .cool:
      return try setLinkedFraction(preset.speedFraction ?? 0.45)
    }
  }

  public func readTemperatures(primaryOnly: Bool = true) -> [TemperatureReading] {
    var seenNames = Set<String>()
    var results: [TemperatureReading] = []
    for def in SensorCatalog.candidates {
      if primaryOnly && !def.isPrimary { continue }
      guard let value = try? readFloatKey(def.key), value > 0, value < 150 else { continue }
      if seenNames.contains(def.name) { continue }
      seenNames.insert(def.name)
      results.append(TemperatureReading(key: def.key, name: def.name, celsius: value))
    }
    return results
  }

  public func maxPrimaryTemperature() -> Float? {
    readTemperatures(primaryOnly: true).map(\.celsius).max()
  }
}
