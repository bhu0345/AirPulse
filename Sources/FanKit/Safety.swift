import Foundation

/// Shared constants and safety policy for AirPulse.
public enum AirPulseConfig {
  public static let appBundleID = "com.bingtaohu.AirPulse"
  public static let helperMachService = "com.bingtaohu.AirPulse.helper"
  public static let helperLabel = "com.bingtaohu.AirPulse.helper"

  /// Refuse / escalate Quiet at or above this temperature (°C).
  public static let blockQuietCelsius: Float = 78
  /// Refuse / escalate Balanced at or above this temperature (°C).
  public static let blockBalancedCelsius: Float = 85
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
  /// Quiet is unsafe; bump toward Balanced (or Cool if already hotter).
  case bumpFromQuiet
  /// Balanced / Quiet unsafe at this temp; force Cool.
  case escalateFromBalanced
  case forceCool
  case restoreAuto
}

public struct SafetyPolicy: Sendable {
  public var blockQuietCelsius: Float
  public var blockBalancedCelsius: Float
  public var warningCelsius: Float
  public var criticalCelsius: Float

  public init(
    blockQuietCelsius: Float = AirPulseConfig.blockQuietCelsius,
    blockBalancedCelsius: Float = AirPulseConfig.blockBalancedCelsius,
    warningCelsius: Float = AirPulseConfig.warningCelsius,
    criticalCelsius: Float = AirPulseConfig.criticalCelsius
  ) {
    self.blockQuietCelsius = blockQuietCelsius
    self.blockBalancedCelsius = blockBalancedCelsius
    self.warningCelsius = warningCelsius
    self.criticalCelsius = criticalCelsius
  }

  public func evaluate(maxTemp: Float?) -> SafetyAction {
    guard let maxTemp else { return .none }
    if maxTemp >= criticalCelsius { return .restoreAuto }
    if maxTemp >= warningCelsius { return .forceCool }
    if maxTemp >= blockBalancedCelsius { return .escalateFromBalanced }
    if maxTemp >= blockQuietCelsius { return .bumpFromQuiet }
    return .none
  }

  /// Whether applying this preset should be refused given current max temp.
  public func shouldBlock(preset: FanPreset, maxTemp: Float?) -> Bool {
    guard let maxTemp else { return false }
    switch preset {
    case .quiet:
      return maxTemp >= blockQuietCelsius
    case .balanced:
      return maxTemp >= blockBalancedCelsius
    case .auto, .cool, .curve:
      return false
    }
  }

  /// Minimum linked fraction so Quiet / low slider cannot pack heat.
  public func minimumFraction(forMaxTemp maxTemp: Float?) -> Double {
    guard let t = maxTemp else { return 0 }
    if t >= warningCelsius { return 0.85 }
    if t >= blockBalancedCelsius { return 0.70 }
    if t >= blockQuietCelsius { return 0.45 }
    return 0
  }
}

/// Default piecewise temperature → fan fraction curve (Curve preset).
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
