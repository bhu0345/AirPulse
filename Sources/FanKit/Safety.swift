import Foundation

/// Shared constants and safety policy for AirPulse.
public enum AirPulseConfig {
  public static let appBundleID = "com.bingtaohu.AirPulse"
  public static let helperMachService = "com.bingtaohu.AirPulse.helper"
  public static let helperLabel = "com.bingtaohu.AirPulse.helper"

  /// Raise minimum fan fraction at or above this temperature (°C).
  public static let lowFloorCelsius: Float = 78
  /// Stronger minimum fan fraction at or above this temperature (°C).
  public static let highFloorCelsius: Float = 85
  /// Force emergency cooling fraction at or above this (°C).
  public static let warningCelsius: Float = 90
  /// If exceeded, restore Auto so system thermal management takes over.
  public static let criticalCelsius: Float = 100

  public static let reassertInterval: TimeInterval = 2.0
  public static let pollInterval: TimeInterval = 1.0
}

public enum SafetyAction: String, Sendable, Codable {
  case none
  /// Mild heat — enforce a moderate RPM floor.
  case raiseLowFloor
  /// Hot — enforce a high RPM floor / emergency cool if still too low.
  case raiseHighFloor
  case forceEmergencyCool
  case restoreAuto
}

public struct SafetyPolicy: Sendable {
  public var lowFloorCelsius: Float
  public var highFloorCelsius: Float
  public var warningCelsius: Float
  public var criticalCelsius: Float

  public init(
    lowFloorCelsius: Float = AirPulseConfig.lowFloorCelsius,
    highFloorCelsius: Float = AirPulseConfig.highFloorCelsius,
    warningCelsius: Float = AirPulseConfig.warningCelsius,
    criticalCelsius: Float = AirPulseConfig.criticalCelsius
  ) {
    self.lowFloorCelsius = lowFloorCelsius
    self.highFloorCelsius = highFloorCelsius
    self.warningCelsius = warningCelsius
    self.criticalCelsius = criticalCelsius
  }

  public func evaluate(maxTemp: Float?) -> SafetyAction {
    guard let maxTemp else { return .none }
    if maxTemp >= criticalCelsius { return .restoreAuto }
    if maxTemp >= warningCelsius { return .forceEmergencyCool }
    if maxTemp >= highFloorCelsius { return .raiseHighFloor }
    if maxTemp >= lowFloorCelsius { return .raiseLowFloor }
    return .none
  }

  public func shouldBlock(preset: FanPreset, maxTemp: Float?) -> Bool {
    // Auto / Custom / Smart are always selectable; floors clamp speed instead.
    _ = preset
    _ = maxTemp
    return false
  }

  /// Minimum linked fraction so a low Custom slider cannot pack heat.
  public func minimumFraction(forMaxTemp maxTemp: Float?) -> Double {
    guard let t = maxTemp else { return 0 }
    if t >= warningCelsius { return FanPreset.emergencyCoolFraction }
    if t >= highFloorCelsius { return 0.70 }
    if t >= lowFloorCelsius { return 0.45 }
    return 0
  }
}

/// Default piecewise temperature → fan fraction curve (Smart preset).
public enum FanCurve {
  public struct Knot: Sendable {
    public let celsius: Float
    public let fraction: Double
    public init(celsius: Float, fraction: Double) {
      self.celsius = celsius
      self.fraction = fraction
    }
  }

  public static let `default`: [Knot] = [
    .init(celsius: 55, fraction: 0.15),
    .init(celsius: 70, fraction: 0.40),
    .init(celsius: 82, fraction: 0.70),
    .init(celsius: 92, fraction: 0.95),
  ]

  public static func fraction(forCelsius temp: Float, knots: [Knot] = FanCurve.default) -> Double {
    guard let first = knots.first, let last = knots.last else { return 0.45 }
    if temp <= first.celsius { return first.fraction }
    if temp >= last.celsius { return last.fraction }
    for i in 0..<(knots.count - 1) {
      let a = knots[i]
      let b = knots[i + 1]
      if temp >= a.celsius && temp <= b.celsius {
        let span = max(0.001, b.celsius - a.celsius)
        let t = Double((temp - a.celsius) / span)
        return a.fraction + t * (b.fraction - a.fraction)
      }
    }
    return last.fraction
  }
}
