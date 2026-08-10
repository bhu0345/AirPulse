import AppKit
import Combine
import FanKit
import SwiftUI

@main
struct AirPulseApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    // The whole UI is an AppKit status item (see AppDelegate) so that a
    // right-click can open a menu instead of the popover. `App` still demands
    // a scene, and an accessory app never surfaces this one.
    Settings {
      EmptyView()
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let service = FanService()
  private let popover = NSPopover()
  private var statusItem: NSStatusItem?
  private var cancellables: Set<AnyCancellable> = []
  private var outsideClickMonitor: Any?
  /// A click on the button while the popover is open closes it via the
  /// transient event monitor *before* our action runs — without this the
  /// action would immediately reopen it.
  private var lastPopoverCloseTime = Date.distantPast

  private var L: L10n { LanguageStore.shared.strings }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    setUpPopover()
    setUpStatusItem()
    observeMenuBarTitle()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(closePopoverIfShown),
      name: NSApplication.didResignActiveNotification,
      object: nil
    )
    service.start()
  }

  @objc private func closePopoverIfShown() {
    if popover.isShown { popover.performClose(nil) }
  }

  func applicationWillTerminate(_ notification: Notification) {
    service.prepareToTerminate(waitSeconds: 1.5)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  // MARK: - Status item

  private func setUpStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let icon = NSImage(systemSymbolName: "fanblades", accessibilityDescription: "AirPulse")
    icon?.isTemplate = true
    item.button?.image = icon
    item.button?.imagePosition = .imageLeading
    item.button?.title = "AirPulse"
    item.button?.target = self
    item.button?.action = #selector(statusItemClicked)
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    statusItem = item
  }

  private func setUpPopover() {
    let hosting = NSHostingController(rootView: MenuBarPopoverView(service: service))
    hosting.sizingOptions = [.preferredContentSize]
    popover.contentViewController = hosting
    popover.behavior = .transient
    popover.animates = false
    popover.delegate = self
  }

  @objc private func statusItemClicked() {
    let isRightClick =
      NSApp.currentEvent?.type == .rightMouseUp
      || NSApp.currentEvent?.modifierFlags.contains(.control) == true
    if isRightClick {
      showContextMenu()
    } else {
      togglePopover()
    }
  }

  private func togglePopover() {
    guard let button = statusItem?.button else { return }
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    if Date().timeIntervalSince(lastPopoverCloseTime) < 0.25 { return }

    // Reconnects the helper if the link dropped while the popover was closed.
    service.start()
    button.isHighlighted = true
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
    NSApp.activate(ignoringOtherApps: true)
    watchForOutsideClicks()
  }

  /// `.transient` alone can leave the popover on screen when the click lands in
  /// another app that never activates us, so dismiss it by hand as well.
  private func watchForOutsideClicks() {
    stopWatchingForOutsideClicks()
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.popover.isShown else { return }
        self.popover.performClose(nil)
      }
    }
  }

  private func stopWatchingForOutsideClicks() {
    if let outsideClickMonitor {
      NSEvent.removeMonitor(outsideClickMonitor)
      self.outsideClickMonitor = nil
    }
  }

  private func showContextMenu() {
    guard let statusItem, let button = statusItem.button else { return }
    if popover.isShown { popover.performClose(nil) }

    let menu = NSMenu()
    let restore = NSMenuItem(
      title: L.restoreAuto, action: #selector(restoreAutoFromMenu), keyEquivalent: "")
    restore.target = self
    menu.addItem(restore)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: L.quitApp, action: #selector(quitFromMenu), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)

    // A status item shows its menu on click only; hand it over for this one
    // click so left-clicks keep opening the popover.
    statusItem.menu = menu
    button.performClick(nil)
    statusItem.menu = nil
  }

  @objc private func restoreAutoFromMenu() {
    service.restoreAuto()
  }

  @objc private func quitFromMenu() {
    service.stop()
    NSApp.terminate(nil)
  }

  // MARK: - Menu bar title

  private func observeMenuBarTitle() {
    Publishers.CombineLatest(service.$temperatures, service.$fans)
      .map(Self.menuBarTitle)
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] title in
        MainActor.assumeIsolated {
          self?.statusItem?.button?.title = title
        }
      }
      .store(in: &cancellables)
  }

  private static func menuBarTitle(
    temperatures: [TemperatureReading],
    fans: [FanSnapshot]
  ) -> String {
    if let cpu = temperatures.first(where: { $0.name == "CPU" }) {
      return "\(Int(cpu.celsius))°"
    }
    if let first = fans.first {
      return "\(Int(first.actualRPM))"
    }
    return "AirPulse"
  }
}

extension AppDelegate: NSPopoverDelegate {
  func popoverDidClose(_ notification: Notification) {
    lastPopoverCloseTime = Date()
    statusItem?.button?.isHighlighted = false
    stopWatchingForOutsideClicks()
  }
}
