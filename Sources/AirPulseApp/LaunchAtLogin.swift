import Foundation
import ServiceManagement

enum LaunchAtLogin {
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  @discardableResult
  static func setEnabled(_ enabled: Bool) -> Bool {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      UserDefaults.standard.set(enabled, forKey: SettingsKeys.launchAtLogin)
      return true
    } catch {
      return false
    }
  }
}

enum SettingsKeys {
  static let activePreset = "airpulse.activePreset"
  static let linkedFraction = "airpulse.linkedFraction"
  static let linkedEnabled = "airpulse.linkedEnabled"
  static let desiredManual = "airpulse.desiredManual"
  static let launchAtLogin = "airpulse.launchAtLogin"
  static let panelBackground = "airpulse.panelBackground"
}
