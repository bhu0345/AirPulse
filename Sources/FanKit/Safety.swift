import Foundation

/// Shared constants and safety policy for AirPulse.
public enum AirPulseConfig {
  public static let appBundleID = "com.bingtaohu.AirPulse"
  public static let helperMachService = "com.bingtaohu.AirPulse.helper"
  public static let helperLabel = "com.bingtaohu.AirPulse.helper"

  /// Bump when Helper XPC contract or required behavior changes.
  public static let helperAPIVersion = 3

  /// Raise minimum fan fraction at or above this temperature (°C).
  public static let lowFloorCelsius: Float = 78
  /// Stronger minimum fan fraction at or above this temperature (°C).
  public static let highFloorCelsius: Float = 85
  /// Force emergency cooling fraction at or above this (°C).
  public static let warningCelsius: Float = 90
  /// If exceeded, restore Auto so system thermal management takes over.
  public static let criticalCelsius: Float = 100
  /// Degrees below an enter threshold before a floor tier disengages.
  public static let safetyHysteresisCelsius: Float = 4

  public static let reassertInterval: TimeInterval = 2.0
  public static let pollInterval: TimeInterval = 1.0
}

public enum SafetyAction: String, Sendable, Codable {
  case none
  case raiseLowFloor
  case raiseHighFloor
  case forceEmergencyCool
  case restoreAuto
}

public enum SafetyFloorTier: Int, Sendable, Comparable {
  case none = 0
  case low = 1
  case high = 2
  case emergency = 3
  case critical = 4

  public static func < (lhs: SafetyFloorTier, rhs: SafetyFloorTier) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// Thermal safety with hysteresis so floors don't chatter at threshold edges.
public struct SafetyPolicy: Sendable {
  public var lowFloorCelsius: Float
  public var highFloorCelsius: Float
  public var warningCelsius: Float
  public var criticalCelsius: Float
  public var hysteresisCelsius: Float
  public private(set) var activeFloor: SafetyFloorTier = .none

  public init(
    lowFloorCelsius: Float = AirPulseConfig.lowFloorCelsius,
    highFloorCelsius: Float = AirPulseConfig.highFloorCelsius,
    warningCelsius: Float = AirPulseConfig.warningCelsius,
    criticalCelsius: Float = AirPulseConfig.criticalCelsius,
    hysteresisCelsius: Float = AirPulseConfig.safetyHysteresisCelsius
  ) {
    self.lowFloorCelsius = lowFloorCelsius
    self.highFloorCelsius = highFloorCelsius
    self.warningCelsius = warningCelsius
    self.criticalCelsius = criticalCelsius
    self.hysteresisCelsius = hysteresisCelsius
  }

  public mutating func evaluate(maxTemp: Float?) -> SafetyAction {
    guard let maxTemp else { return .none }

    let h = hysteresisCelsius
    var target: SafetyFloorTier = .none

    if maxTemp >= criticalCelsius
      || (activeFloor >= .critical && maxTemp >= criticalCelsius - h)
    {
      target = .critical
    } else if maxTemp >= warningCelsius
      || (activeFloor >= .emergency && maxTemp >= warningCelsius - h)
    {
      target = .emergency
    } else if maxTemp >= highFloorCelsius
      || (activeFloor >= .high && maxTemp >= highFloorCelsius - h)
    {
      target = .high
    } else if maxTemp >= lowFloorCelsius
      || (activeFloor >= .low && maxTemp >= lowFloorCelsius - h)
    {
      target = .low
    }

    activeFloor = target
    switch target {
    case .critical: return .restoreAuto
    case .emergency: return .forceEmergencyCool
    case .high: return .raiseHighFloor
    case .low: return .raiseLowFloor
    case .none: return .none
    }
  }

  public func shouldBlock(preset: FanPreset, maxTemp: Float?) -> Bool {
    _ = preset
    _ = maxTemp
    return false
  }

  /// Minimum linked fraction from the currently engaged floor tier.
  public func minimumFraction(forMaxTemp maxTemp: Float? = nil) -> Double {
    // Prefer hysteresis state; fall back to instantaneous temp for first call.
    let tier: SafetyFloorTier
    if activeFloor != .none {
      tier = activeFloor
    } else if let t = maxTemp {
      if t >= warningCelsius { tier = .emergency }
      else if t >= highFloorCelsius { tier = .high }
      else if t >= lowFloorCelsius { tier = .low }
      else { tier = .none }
    } else {
      tier = .none
    }

    switch tier {
    case .critical, .emergency: return FanPreset.emergencyCoolFraction
    case .high: return 0.70
    case .low: return 0.45
    case .none: return 0
    }
  }

  public mutating func reset() {
    activeFloor = .none
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
