import AppKit
import Foundation
import SwiftUI

/// Apple-style frosted panel tints the user can pick under Advanced.
enum PanelBackgroundTheme: String, CaseIterable, Identifiable {
  case clear
  case graphite
  case blue
  case purple
  case mint

  var id: String { rawValue }

  /// Soft wash over the system menu material. `nil` keeps the native look.
  var tint: Color? {
    switch self {
    case .clear:
      return nil
    case .graphite:
      return Self.adaptiveTint(
        light: NSColor(calibratedWhite: 0.42, alpha: 0.10),
        dark: NSColor(calibratedWhite: 0.72, alpha: 0.14)
      )
    case .blue:
      return Self.adaptiveTint(
        light: NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.96, alpha: 0.13),
        dark: NSColor(calibratedRed: 0.35, green: 0.62, blue: 1.0, alpha: 0.18)
      )
    case .purple:
      return Self.adaptiveTint(
        light: NSColor(calibratedRed: 0.56, green: 0.35, blue: 0.90, alpha: 0.13),
        dark: NSColor(calibratedRed: 0.72, green: 0.52, blue: 1.0, alpha: 0.18)
      )
    case .mint:
      return Self.adaptiveTint(
        light: NSColor(calibratedRed: 0.18, green: 0.66, blue: 0.58, alpha: 0.13),
        dark: NSColor(calibratedRed: 0.35, green: 0.82, blue: 0.72, alpha: 0.18)
      )
    }
  }

  /// Solid preview chip used in the Advanced picker.
  var swatchColor: Color {
    switch self {
    case .clear:
      return Color(nsColor: .controlBackgroundColor)
    case .graphite:
      return Color(nsColor: .systemGray)
    case .blue:
      return Color(nsColor: .systemBlue)
    case .purple:
      return Color(nsColor: .systemPurple)
    case .mint:
      return Color(nsColor: .systemTeal)
    }
  }

  var prefersLightCheckmark: Bool {
    switch self {
    case .clear, .graphite: return false
    case .blue, .purple, .mint: return true
    }
  }

  private static func adaptiveTint(light: NSColor, dark: NSColor) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
      }
    )
  }
}

@MainActor
final class PanelBackgroundStore: ObservableObject {
  static let shared = PanelBackgroundStore()
  private static let defaultsKey = SettingsKeys.panelBackground

  @Published var theme: PanelBackgroundTheme {
    didSet {
      UserDefaults.standard.set(theme.rawValue, forKey: Self.defaultsKey)
    }
  }

  private init() {
    if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
      let saved = PanelBackgroundTheme(rawValue: raw)
    {
      theme = saved
    } else {
      theme = .clear
    }
  }
}
