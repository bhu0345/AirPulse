import AppKit
import Combine
import FanKit
import SwiftUI

@main
struct AirPulseApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    // The whole UI is an AppKit status item (see AppDelegate) so that a
    // right-click can open a menu instead of the panel. `App` still demands
    // a scene, and an accessory app never surfaces this one.
    Settings {
      EmptyView()
    }
  }
}

/// Borderless panel used instead of `NSPopover`: a popover re-anchors itself to
/// the status item on every content resize, and when the menu bar is hidden
/// behind a full-screen window that anchor is gone, so expanding Advanced threw
/// the window into the top-left corner of the display.
final class MenuBarPanel: NSPanel {
  override var canBecomeKey: Bool { true }

  override func cancelOperation(_ sender: Any?) {
    close()
  }
}

/// Reports the SwiftUI content size so the delegate can grow the panel without
/// handing positioning back to AppKit.
///
/// Uses a tiny AppKit view instead of `GeometryReader` + `onChange`: on macOS 26
/// that combination keeps Observation tracking alive across 1 Hz sensor publishes
/// and eventually pins a CPU core.
private struct PanelContent: View {
  let service: FanService
  let onResize: (CGSize) -> Void

  var body: some View {
    MenuBarPopoverView(service: service)
      .background(SizeReporter(onResize: onResize))
  }
}

private struct SizeReporter: NSViewRepresentable {
  let onResize: (CGSize) -> Void

  func makeNSView(context: Context) -> SizeReporterView {
    SizeReporterView(onResize: onResize)
  }

  func updateNSView(_ view: SizeReporterView, context: Context) {
    view.onResize = onResize
  }
}

private final class SizeReporterView: NSView {
  var onResize: (CGSize) -> Void
  private var lastSize: CGSize = .zero

  init(onResize: @escaping (CGSize) -> Void) {
    self.onResize = onResize
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()
    reportIfNeeded()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    reportIfNeeded()
  }

  private func reportIfNeeded() {
    let size = bounds.size
    guard size.width > 0, size.height > 0 else { return }
    guard abs(size.width - lastSize.width) > 0.5 || abs(size.height - lastSize.height) > 0.5
    else {
      return
    }
    lastSize = size
    onResize(size)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Distance between the menu bar and the top of the panel.
  private static let panelGap: CGFloat = 6
  /// Keeps the panel off the very edge of the display.
  private static let screenMargin: CGFloat = 8

  private let service = FanService()
  private var statusItem: NSStatusItem?
  private var panel: MenuBarPanel?
  private var cancellables: Set<AnyCancellable> = []
  private var outsideClickMonitor: Any?
  /// Status item position captured when the panel opens, so later resizes stay
  /// put even if the menu bar has hidden itself in the meantime.
  private var anchorRect: NSRect = .zero
  private var anchorScreen: NSScreen?
  /// A click on the button while the panel is open closes it before our action
  /// runs — without this the action would immediately reopen it.
  private var lastPanelCloseTime = Date.distantPast

  private var L: L10n { LanguageStore.shared.strings }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    setUpStatusItem()
    observeMenuBarTitle()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(closePanel),
      name: NSApplication.didResignActiveNotification,
      object: nil
    )
    service.start()

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

  @objc private func statusItemClicked() {
    let isRightClick =
      NSApp.currentEvent?.type == .rightMouseUp
      || NSApp.currentEvent?.modifierFlags.contains(.control) == true
    if isRightClick {
      showContextMenu()
    } else {
      togglePanel()
    }
  }

  private func showContextMenu() {
    guard let statusItem, let button = statusItem.button else { return }
    closePanel()

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
    // click so left-clicks keep opening the panel.
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

  // MARK: - Panel

  private func togglePanel() {
    if panel?.isVisible == true {
      closePanel()
      return
    }
    if Date().timeIntervalSince(lastPanelCloseTime) < 0.25 { return }
    openPanel()
  }

  private func openPanel() {
    guard let button = statusItem?.button, let buttonWindow = button.window else { return }

    // Reconnects the helper if the link dropped while the panel was closed.
    service.start()

    let panel = panel ?? makePanel()
    self.panel = panel
    // Fresh hosting view every open. An ordered-out NSHostingView still
    // receives 1 Hz @Published sensor updates and leaks Observation records
    // on macOS 26 until the process pins a CPU core.
    installPanelContent(panel)
    anchorRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    anchorScreen = buttonWindow.screen ?? NSScreen.main

    panel.contentView?.layoutSubtreeIfNeeded()
    if let fitting = panel.contentView?.fittingSize, fitting.height > 0 {
      place(size: fitting)
    }

    button.isHighlighted = true
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    watchForOutsideClicks()
  }

  @objc private func closePanel() {
    guard let panel, panel.isVisible else { return }
    panel.close()
  }

  private func makePanel() -> MenuBarPanel {
    let panel = MenuBarPanel(
      contentRect: NSRect(x: 0, y: 0, width: 340, height: 320),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(panelWillClose),
      name: NSWindow.willCloseNotification,
      object: panel
    )
    return panel
  }

  private func panelContentDidResize(to size: CGSize) {
    guard let panel, panel.isVisible, size.height > 0 else { return }
    let current = panel.frame.size
    guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else {
      return
    }
    place(size: size)
  }

  /// Always measured from the anchor captured when the panel opened.
  private func place(size: CGSize) {
    guard let panel else { return }
    var origin = CGPoint(
      x: anchorRect.midX - size.width / 2,
      y: anchorRect.minY - size.height - Self.panelGap
    )
    if let visible = (anchorScreen ?? NSScreen.main)?.visibleFrame {
      let margin = Self.screenMargin
      origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
      origin.y = max(origin.y, visible.minY + margin)
    }
    panel.setFrame(NSRect(origin: origin, size: size), display: true)
  }

  @objc private func panelWillClose() {
    lastPanelCloseTime = Date()
    statusItem?.button?.isHighlighted = false
    stopWatchingForOutsideClicks()
    panel?.contentView = nil
  }

  private func installPanelContent(_ panel: MenuBarPanel) {
    panel.contentView = NSHostingView(
      rootView: PanelContent(service: service) { [weak self] size in
        self?.panelContentDidResize(to: size)
      }
    )
  }

  private func watchForOutsideClicks() {
    stopWatchingForOutsideClicks()
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.closePanel()
      }
    }
  }

  private func stopWatchingForOutsideClicks() {
    if let outsideClickMonitor {
      NSEvent.removeMonitor(outsideClickMonitor)
      self.outsideClickMonitor = nil
    }
  }

  // MARK: - Menu bar title

  private func observeMenuBarTitle() {
    Publishers.CombineLatest3(service.$temperatures, service.$fans, UnitStore.shared.$unit)
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
    fans: [FanSnapshot],
    unit: TemperatureUnit
  ) -> String {
    if let cpu = temperatures.first(where: { $0.name == "CPU" }) {
      return unit.compact(celsius: cpu.celsius)
    }
    if let first = fans.first {
      return "\(Int(first.actualRPM))"
    }
    return "AirPulse"
  }
}
