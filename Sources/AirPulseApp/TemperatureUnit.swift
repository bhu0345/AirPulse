import Foundation

/// Sensors and every threshold in FanKit stay in Celsius; this only changes
/// what the user sees.
enum TemperatureUnit: String, CaseIterable, Identifiable {
  case celsius = "c"
  case fahrenheit = "f"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .celsius: return "°C"
    case .fahrenheit: return "°F"
    }
  }

  func value(celsius: Float) -> Float {
    switch self {
    case .celsius: return celsius
    case .fahrenheit: return celsius * 9 / 5 + 32
    }
  }

  /// "52°C" — where the unit is not obvious from context.
  func format(celsius: Float) -> String {
    String(format: "%.0f%@", value(celsius: celsius), displayName)
  }

  /// "52°" — the menu bar, where every point of width counts.
  func compact(celsius: Float) -> String {
    String(format: "%.0f°", value(celsius: celsius))
  }

  /// Thread-safe snapshot for status text built off the main actor.
  nonisolated(unsafe) static var cached: TemperatureUnit = .celsius
}

@MainActor
final class UnitStore: ObservableObject {
  static let shared = UnitStore()
  private static let defaultsKey = "airpulse.temperatureUnit"

  @Published var unit: TemperatureUnit {
    didSet {
      UserDefaults.standard.set(unit.rawValue, forKey: Self.defaultsKey)
      TemperatureUnit.cached = unit
    }
  }

  private init() {
    if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
      let saved = TemperatureUnit(rawValue: raw)
    {
      unit = saved
    } else {
      unit = .celsius
    }
    TemperatureUnit.cached = unit
  }
}
