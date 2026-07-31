import Foundation

public enum SMCFanKey {
  public static let count = "FNum"
  public static let actual = "F%dAc"
  public static let target = "F%dTg"
  public static let minimum = "F%dMn"
  public static let maximum = "F%dMx"
  public static let forceTest = "Ftst"
  public static let modeLower = "F%dmd"
  public static let modeUpper = "F%dMd"

  public static func key(_ template: String, fan: Int) -> String {
    String(format: template, fan)
  }
}

public struct SMCHardwareConfig: Sendable {
  public let modeKeyFormat: String
  public let ftstAvailable: Bool

  public init(modeKeyFormat: String, ftstAvailable: Bool) {
    self.modeKeyFormat = modeKeyFormat
    self.ftstAvailable = ftstAvailable
  }
}

public enum FanMode: UInt8, Sendable, Codable {
  case auto = 0
  case manual = 1
  case system = 3
  case unknown = 255
}

public enum FanControlStrategy: String, Sendable {
  case direct
  case ftstUnlock
}

public struct FanSnapshot: Sendable, Identifiable, Codable, Equatable {
  public var id: Int { index }
  public let index: Int
  public let actualRPM: Float
  public let targetRPM: Float
  public let minRPM: Float
  public let maxRPM: Float
  public let mode: FanMode

  public init(
    index: Int, actualRPM: Float, targetRPM: Float, minRPM: Float, maxRPM: Float, mode: FanMode
  ) {
    self.index = index
    self.actualRPM = actualRPM
    self.targetRPM = targetRPM
    self.minRPM = minRPM
    self.maxRPM = maxRPM
    self.mode = mode
  }
}

public struct TemperatureReading: Sendable, Identifiable, Codable, Equatable {
  public var id: String { key }
  public let key: String
  public let name: String
  public let celsius: Float

  public init(key: String, name: String, celsius: Float) {
    self.key = key
    self.name = name
    self.celsius = celsius
  }
}

public enum FanPreset: String, CaseIterable, Sendable, Codable, Identifiable {
  case auto
  case quiet
  case balanced
  case cool

  public var id: String { rawValue }

  public var titleZH: String {
    switch self {
    case .auto: return "自动"
    case .quiet: return "安静"
    case .balanced: return "均衡"
    case .cool: return "强冷"
    }
  }

  public var titleEN: String {
    switch self {
    case .auto: return "Auto"
    case .quiet: return "Quiet"
    case .balanced: return "Balanced"
    case .cool: return "Cool"
    }
  }

  /// Fraction of (min...max) range when not auto. Auto uses system control.
  public var speedFraction: Double? {
    switch self {
    case .auto: return nil
    case .quiet: return 0.15
    case .balanced: return 0.45
    case .cool: return 0.85
    }
  }
}

public enum SensorCatalog {
  public struct SensorDef: Sendable {
    public let key: String
    public let name: String
    public let isPrimary: Bool
  }

  /// M5-focused primary keys + common fallbacks. Probed at runtime.
  public static let candidates: [SensorDef] = [
    .init(key: "Tp0O", name: "CPU", isPrimary: true),
    .init(key: "Tp01", name: "CPU", isPrimary: true),
    .init(key: "TC0P", name: "CPU", isPrimary: true),
    .init(key: "Tg0U", name: "GPU", isPrimary: true),
    .init(key: "Tg05", name: "GPU", isPrimary: true),
    .init(key: "TG0P", name: "GPU", isPrimary: true),
    .init(key: "TB1T", name: "Battery", isPrimary: true),
    .init(key: "TB0T", name: "Battery", isPrimary: true),
    .init(key: "Tp00", name: "CPU S1", isPrimary: false),
    .init(key: "Tp04", name: "CPU S2", isPrimary: false),
    .init(key: "Tp08", name: "CPU S3", isPrimary: false),
    .init(key: "Tg0X", name: "GPU 2", isPrimary: false),
    .init(key: "Tg0d", name: "GPU 3", isPrimary: false),
    .init(key: "Tm0p", name: "Memory", isPrimary: false),
  ]
}
