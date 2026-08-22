import Foundation

/// Why Smart chose the fan speed it did — shown in the status line and log.
public enum SmartPhase: String, Sendable, Codable {
  case rise
  case hold
  case decay
  case steady
}

public struct SmartDecision: Sendable {
  public let sensorCelsius: Float
  public let effectiveCelsius: Float
  public let rawFraction: Double
  public let appliedFraction: Double
  public let phase: SmartPhase

  public init(
    sensorCelsius: Float,
    effectiveCelsius: Float,
    rawFraction: Double,
    appliedFraction: Double,
    phase: SmartPhase
  ) {
    self.sensorCelsius = sensorCelsius
    self.effectiveCelsius = effectiveCelsius
    self.rawFraction = rawFraction
    self.appliedFraction = appliedFraction
    self.phase = phase
  }
}

/// Fast-up / slow-down Smart curve so a 1-second temperature dip cannot
/// drop the fans and immediately retrigger another heat spike.
public struct SmartGovernor: Sendable {
  private var heldFraction: Double = 0
  private var peakCelsius: Float = 0
  private var lastEvaluate: Date?
  private var lastHighAt: Date?

  public init() {}

  public mutating func reset() {
    heldFraction = 0
    peakCelsius = 0
    lastEvaluate = nil
    lastHighAt = nil
  }

  public mutating func evaluate(celsius: Float, now: Date = Date()) -> SmartDecision {
    let dt = lastEvaluate.map { max(0, now.timeIntervalSince($0)) } ?? 0

    if celsius >= peakCelsius {
      peakCelsius = celsius
    } else if dt > 0 {
      let decay = Float(dt) * AirPulseConfig.smartPeakDecayCelsiusPerSecond
      peakCelsius = max(celsius, peakCelsius - decay)
    }

    let raw = FanCurve.fraction(forCelsius: celsius)
    let fromPeak = FanCurve.fraction(forCelsius: peakCelsius)
    let unheld = max(raw, fromPeak)

    if celsius >= AirPulseConfig.smartHighCelsius {
      lastHighAt = now
    }

    let inHold =
      lastHighAt.map { now.timeIntervalSince($0) < AirPulseConfig.smartHoldAfterHighSeconds }
      ?? false

    var target = unheld
    if inHold {
      target = max(target, heldFraction)
    }

    if target < heldFraction, dt > 0 {
      let floor = heldFraction - AirPulseConfig.smartMaxDownwardFractionPerSecond * dt
      target = max(target, floor)
    } else if target < heldFraction, lastEvaluate != nil {
      target = heldFraction
    }

    target = min(1, max(0, target))

    let previous = heldFraction
    let phase: SmartPhase
    if target > previous + 0.01 {
      phase = .rise
    } else if target < previous - 0.01 {
      phase = .decay
    } else if inHold {
      phase = .hold
    } else {
      phase = .steady
    }

    heldFraction = target
    lastEvaluate = now

    return SmartDecision(
      sensorCelsius: celsius,
      effectiveCelsius: peakCelsius,
      rawFraction: raw,
      appliedFraction: target,
      phase: phase
    )
  }
}
