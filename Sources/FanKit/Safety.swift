import Foundation

/// Shared constants and safety policy for AirPulse.
public enum AirPulseConfig {
  public static let appBundleID = "com.bingtaohu.AirPulse"
  public static let helperMachService = "com.bingtaohu.AirPulse.helper"
  public static let helperLabel = "com.bingtaohu.AirPulse.helper"

  /// If any primary sensor exceeds this (°C), force Cool preset / raise fans.
  public static let warningCelsius: Float = 90
  /// If exceeded, restore Auto so system thermal management takes over.
  public static let criticalCelsius: Float = 100

  /// How often the app re-asserts manual targets against thermalmonitord reclaim.
  public static let reassertInterval: TimeInterval = 2.0
  public static let pollInterval: TimeInterval = 1.0
}

public enum SafetyAction: String, Sendable, Codable {
  case none
  case forceCool
  case restoreAuto
}

public struct SafetyPolicy: Sendable {
  public var warningCelsius: Float
  public var criticalCelsius: Float

  public init(
    warningCelsius: Float = AirPulseConfig.warningCelsius,
    criticalCelsius: Float = AirPulseConfig.criticalCelsius
  ) {
    self.warningCelsius = warningCelsius
    self.criticalCelsius = criticalCelsius
  }

  public func evaluate(maxTemp: Float?) -> SafetyAction {
    guard let maxTemp else { return .none }
    if maxTemp >= criticalCelsius { return .restoreAuto }
    if maxTemp >= warningCelsius { return .forceCool }
    return .none
  }
}
