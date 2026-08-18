import AppKit
import FanKit
import SwiftUI

struct MenuBarPopoverView: View {
  @ObservedObject var service: FanService
  @ObservedObject private var languageStore = LanguageStore.shared
  @ObservedObject private var unitStore = UnitStore.shared
  @ObservedObject private var backgroundStore = PanelBackgroundStore.shared
  @StateObject private var updateChecker = UpdateChecker()
  @State private var showAdvanced = false
  @State private var linkedSliderValue: Double = 0.3
  @State private var isDraggingLinked = false

  private var L: L10n { languageStore.strings }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      temperatureRow
      if !service.canWrite, service.discoveredFanCount != 0 {
        if service.helperNeedsUpdate {
          helperUpdateBanner
        } else {
          enableHelperBanner
        }
      }
      if service.discoveredFanCount == 0 {
        fanlessBanner
      } else {
        presetRow
        linkedSlider
        if (showAdvanced || !service.linkedEnabled) && hasMultipleFans {
          unlinkedSection
        }
      }
      if showAdvanced {
        advancedSection
      }
      footer
    }
    .padding(16)
    .frame(width: 340)
    .background(popoverBackground)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.08))
    )
    .onAppear {
      linkedSliderValue = service.linkedFraction
    }
    .onChange(of: service.linkedFraction) { _, newValue in
      if !isDraggingLinked {
        linkedSliderValue = newValue
      }
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text("AirPulse")
          .font(.system(size: 18, weight: .semibold, design: .rounded))
        Text(service.hardwareSummary.isEmpty ? L.macFanControl : service.hardwareSummary)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer()
      HStack(spacing: 6) {
        Text(L.statusLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
        Circle()
          .fill(service.canWrite ? Color.green.opacity(0.85) : Color.orange.opacity(0.85))
          .frame(width: 8, height: 8)
          .help(service.canWrite ? L.writable : L.readOnlyNeedAuth)
      }
    }
  }

  private var hasMultipleFans: Bool {
    (service.discoveredFanCount ?? service.fans.count) > 1
  }

  private var linkedSliderTitle: String {
    if !hasMultipleFans { return L.fanSpeed }
    return service.linkedEnabled ? L.fansLinked : L.fansUnlinked
  }

  /// Everything that is set once and then forgotten lives behind “Advanced”.
  private var advancedSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      languageRow
      temperatureUnitRow
      launchAtLoginRow
      backgroundRow
      Divider().opacity(0.4)
      updatesRow
      Divider().opacity(0.4)
      HStack {
        Button(L.restoreAuto) {
          service.restoreAuto()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        Spacer()
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
    .onAppear {
      if case .idle = updateChecker.state {
        updateChecker.check()
      }
    }
  }

  private var updatesRow: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(L.updatesLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Text("v\(UpdateChecker.currentVersion)")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.tertiary)
      }

      Text(updateStatusText)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      updateActionButton
    }
  }

  private var updateStatusText: String {
    switch updateChecker.state {
    case .idle:
      return L.currentVersion(UpdateChecker.currentVersion)
    case .checking:
      return L.checkingUpdates
    case .upToDate:
      return L.upToDate
    case .ahead(_, let latest):
      return L.newerThanRelease("v\(latest)")
    case .available(let latest, _, _):
      return L.updateAvailable(latest)
    case .downloading:
      return L.downloadingUpdate
    case .installed:
      return L.updateOpenedDMG
    case .failed(let message):
      return "\(L.updateCheckFailed): \(message)"
    }
  }

  @ViewBuilder
  private var updateActionButton: some View {
    switch updateChecker.state {
    case .available:
      Button {
        updateChecker.downloadUpdate()
      } label: {
        Text(L.downloadUpdate)
          .font(.system(size: 12, weight: .semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    case .checking, .downloading:
      HStack {
        ProgressView()
          .controlSize(.small)
        Spacer()
      }
    default:
      Button(updateChecker.state == .idle ? L.checkForUpdates : L.checkAgain) {
        updateChecker.check()
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
  }

  private var fanlessBanner: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(L.noFansTitle)
        .font(.caption.weight(.semibold))
      Text(L.noFansHint)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.primary.opacity(0.05))
    )
  }

  private var languageRow: some View {
    HStack {
      Text(L.languageLabel)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Picker("", selection: Binding(
        get: { languageStore.language },
        set: { newValue in
          languageStore.language = newValue
          service.reloadLocalizedStrings()
        }
      )) {
        ForEach(AppLanguage.allCases) { lang in
          Text(lang.displayName).tag(lang)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 150)
      .labelsHidden()
    }
  }

  private var temperatureUnitRow: some View {
    HStack {
      Text(L.temperatureUnitLabel)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Picker("", selection: Binding(
        get: { unitStore.unit },
        set: { newValue in
          unitStore.unit = newValue
          service.refreshStatusMessage()
        }
      )) {
        ForEach(TemperatureUnit.allCases) { unit in
          Text(unit.displayName).tag(unit)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 150)
      .labelsHidden()
    }
  }

  private var launchAtLoginRow: some View {
    HStack {
      Text(L.launchAtLogin)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      Toggle(
        "",
        isOn: Binding(
          get: { service.launchAtLoginEnabled },
          set: { service.setLaunchAtLogin($0) }
        )
      )
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.small)
    }
  }

  private var backgroundRow: some View {
    HStack(alignment: .center) {
      Text(L.backgroundLabel)
        .font(.caption)
        .foregroundStyle(.secondary)
      Spacer()
      HStack(spacing: 8) {
        ForEach(PanelBackgroundTheme.allCases) { theme in
          backgroundSwatch(theme)
        }
      }
    }
  }

  private func backgroundSwatch(_ theme: PanelBackgroundTheme) -> some View {
    let selected = backgroundStore.theme == theme
    return Button {
      withAnimation(.easeInOut(duration: 0.18)) {
        backgroundStore.theme = theme
      }
    } label: {
      ZStack {
        Circle()
          .fill(
            LinearGradient(
              colors: theme == .clear
                ? [Color.primary.opacity(0.06), Color.primary.opacity(0.02)]
                : [theme.swatchColor.opacity(0.95), theme.swatchColor.opacity(0.75)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: 20, height: 20)
          .overlay(
            Circle()
              .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
          )
        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(theme.prefersLightCheckmark ? Color.white : Color.primary.opacity(0.85))
        }
      }
      .frame(width: 26, height: 26)
      .overlay(
        Circle()
          .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
      )
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(L.backgroundThemeName(theme))
    .accessibilityLabel(L.backgroundThemeName(theme))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private var enableHelperBanner: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L.enableFanControlHint)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button {
        service.installHelper()
      } label: {
        Text(L.enableFanControl)
          .font(.system(size: 13, weight: .semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
      }
      .buttonStyle(.borderedProminent)
      .disabled(service.isInstallingHelper)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.accentColor.opacity(0.08))
    )
  }

  private var helperUpdateBanner: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L.helperNeedsUpdateHint)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button {
        service.installHelper()
      } label: {
        Text(L.updateHelper)
          .font(.system(size: 13, weight: .semibold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
      }
      .buttonStyle(.borderedProminent)
      .disabled(service.isInstallingHelper)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.orange.opacity(0.12))
    )
  }

  private var temperatureRow: some View {
    HStack(spacing: 10) {
      ForEach(service.temperatures.prefix(3)) { reading in
        VStack(spacing: 2) {
          Text(L.sensorName(reading.name))
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text(unitStore.unit.format(celsius: reading.celsius))
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundStyle(tempColor(reading.celsius))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.05))
        )
      }
      if service.temperatures.isEmpty {
        Text(L.readingTemps)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var presetRow: some View {
    HStack(alignment: .center, spacing: 6) {
      ForEach(FanPreset.allCases.filter { !$0.isFeatured }) { preset in
        presetChip(preset)
      }
      smartChip
    }
  }

  private func presetChip(_ preset: FanPreset) -> some View {
    let selected = service.activePreset == preset
    return Button {
      service.applyPreset(preset)
    } label: {
      Text(L.presetTitle(preset))
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.85))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(L.presetTitle(preset))
  }

  /// Featured Smart control — same idle chrome as other chips; accent only when selected.
  private var smartChip: some View {
    let selected = service.activePreset == .smart
    return Button {
      service.applyPreset(.smart)
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "sparkles")
          .font(.system(size: 10, weight: .semibold))
        Text(L.presetTitle(.smart))
          .font(.system(size: 11, weight: selected ? .semibold : .medium))
      }
      .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .padding(.horizontal, 4)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(selected ? Color.accentColor : Color.primary.opacity(0.05))
      )
      .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(L.presetTitle(.smart))
    .help(L.smartHelp)
  }

  private var linkedSlider: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(linkedSliderTitle)
          .font(.subheadline.weight(.medium))
        Spacer()
        if hasMultipleFans {
          Toggle(
            "",
            isOn: Binding(
              get: { service.linkedEnabled },
              set: { newValue in
                service.linkedEnabled = newValue
                if !newValue { showAdvanced = true }
                service.persistLinkedEnabled()
              }
            )
          )
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .help(L.unlinkHelp)
        }
      }

      if service.linkedEnabled {
        HStack {
          Image(systemName: "fanblades")
            .foregroundStyle(.secondary)
          Slider(value: $linkedSliderValue, in: 0...1) { editing in
            isDraggingLinked = editing
            service.isDraggingSlider = editing
            if !editing {
              service.applyLinkedFraction(linkedSliderValue)
            }
          }
          .transaction { $0.animation = nil }
          Text("\(Int(linkedSliderValue * 100))%")
            .font(.system(.caption, design: .monospaced))
            .frame(width: 36, alignment: .trailing)
        }

        HStack {
          ForEach(service.fans) { fan in
            Text(L.fanRPM(fan.index, rpm: Int(fan.actualRPM)))
              .font(.caption2)
              .foregroundStyle(.secondary)
            if fan.id != service.fans.last?.id {
              Text("·").foregroundStyle(.quaternary)
            }
          }
        }
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.primary.opacity(0.04))
    )
  }

  private var unlinkedSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L.perFanControl)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      ForEach(service.fans) { fan in
        UnlinkedFanSliderRow(
          fan: fan,
          label: L.fanLabel(fan.index),
          fraction: service.unlinkRPM[fan.index] ?? 0.3,
          disabled: service.linkedEnabled,
          onEditingChanged: { editing in
            service.isDraggingSlider = editing
          },
          onCommit: { fraction in
            service.applyUnlinked(fanIndex: fan.index, fraction: fraction)
          }
        )
      }
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let notice = service.safetyNotice {
        Text(notice)
          .font(.caption2)
          .foregroundStyle(.red)
      }
      Text(service.statusMessage)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)

      HStack {
        Button {
          showAdvanced.toggle()
        } label: {
          HStack(spacing: 4) {
            Text(showAdvanced ? L.hideAdvanced : L.advanced)
            Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
              .font(.system(size: 8, weight: .semibold))
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)

        Spacer()

        Button(L.quit) {
          service.stop()
          NSApp.terminate(nil)
        }
        .buttonStyle(.borderless)
      }
      .font(.caption)
    }
  }

  /// System menu vibrancy, with an optional Apple-style wash from Advanced.
  private var popoverBackground: some View {
    ZStack {
      VisualEffectBackdrop(material: .menu, cornerRadius: 12)
      if let tint = backgroundStore.theme.tint {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(tint)
      }
    }
  }

  private func tempColor(_ c: Float) -> Color {
    if c >= 90 { return .red }
    if c >= 75 { return .orange }
    return .primary
  }
}

/// Behind-window vibrancy is composited by the window server, which ignores
/// SwiftUI's `.clipShape`, so the rounded corners have to come from the
/// material's own mask image or the blur renders as a square behind the panel.
private struct VisualEffectBackdrop: NSViewRepresentable {
  let material: NSVisualEffectView.Material
  let cornerRadius: CGFloat

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = .behindWindow
    view.state = .active
    view.isEmphasized = false
    view.maskImage = Self.maskImage(cornerRadius: cornerRadius)
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    view.material = material
    view.maskImage = Self.maskImage(cornerRadius: cornerRadius)
  }

  private static func maskImage(cornerRadius: CGFloat) -> NSImage {
    let edge = cornerRadius * 2 + 1
    let image = NSImage(
      size: NSSize(width: edge, height: edge),
      flipped: false
    ) { rect in
      NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(
      top: cornerRadius,
      left: cornerRadius,
      bottom: cornerRadius,
      right: cornerRadius
    )
    image.resizingMode = .stretch
    return image
  }
}

/// Keeps unlinked slider value in local state while dragging so `@Published`
/// fan updates cannot rebuild the control on every thumb move.
private struct UnlinkedFanSliderRow: View {
  let fan: FanSnapshot
  let label: String
  let fraction: Double
  let disabled: Bool
  let onEditingChanged: (Bool) -> Void
  let onCommit: (Double) -> Void

  @State private var value: Double = 0.3
  @State private var isDragging = false

  var body: some View {
    HStack {
      Text(label)
        .font(.caption)
        .frame(width: 52, alignment: .leading)
      Slider(value: $value, in: 0...1) { editing in
        isDragging = editing
        onEditingChanged(editing)
        if !editing {
          onCommit(value)
        }
      }
      .disabled(disabled)
      Text("\(Int(fan.actualRPM))")
        .font(.system(.caption2, design: .monospaced))
        .frame(width: 40, alignment: .trailing)
    }
    .onAppear { value = fraction }
    .onChange(of: fraction) { _, newValue in
      if !isDragging {
        value = newValue
      }
    }
  }
}
