import AppKit
import SwiftUI

@main
struct AirPulseApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var service = FanService()

  var body: some Scene {
    MenuBarExtra {
      MenuBarPopoverView(service: service)
        .onAppear { service.start() }
    } label: {
      Label {
        Text(menuTitle)
      } icon: {
        Image(systemName: "fanblades")
      }
    }
    .menuBarExtraStyle(.window)
  }

  private var menuTitle: String {
    if let cpu = service.temperatures.first(where: { $0.name == "CPU" }) {
      return "\(Int(cpu.celsius))°"
    }
    if let first = service.fans.first {
      return "\(Int(first.actualRPM))"
    }
    return "AirPulse"
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  func applicationWillTerminate(_ notification: Notification) {
    // FanService.stop() is also called from the Quit button.
  }
}
