import FanKit
import SwiftUI

struct MenuBarPopoverView: View {
  @ObservedObject var service: FanService
  @ObservedObject private var languageStore = LanguageStore.shared
  @State private var showAdvanced = false
  @State private var linkedSliderValue: Double = 0.3
  @State private var isDraggingLinked = false

  private var L: L10n { languageStore.strings }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      languageRow
      temperatureRow
      if !service.canWrite {
        if service.helperNeedsUpdate {
          helperUpdateBanner
        } else {
          enableHelperBanner
        }
      }
      presetRow
      linkedSlider
      if showAdvanced || !service.linkedEnabled {
        unlinkedSection
      }
      footer
    }
    .padding(16)
    .frame(width: 340)
    .background(popoverBackground)
    .id(languageStore.language)
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
      .frame(width: 180)
      .labelsHidden()
    }
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
          Text(String(format: "%.0f°", reading.celsius))
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
        Text(service.linkedEnabled ? L.fansLinked : L.fansUnlinked)
          .font(.subheadline.weight(.medium))
        Spacer()
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

      if showAdvanced {
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

      HStack(spacing: 8) {
        Button(showAdvanced ? L.hideAdvanced : L.advanced) {
          withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
        }
        .buttonStyle(.borderless)
        .font(.caption)

        Spacer()

        Button(L.restoreAuto) {
          service.restoreAuto()
        }
        .buttonStyle(.borderless)
        .font(.caption)

        Button(L.quit) {
          service.stop()
          NSApp.terminate(nil)
        }
        .buttonStyle(.borderless)
        .font(.caption)
      }
    }
  }

  private var popoverBackground: some View {
    LinearGradient(
      colors: [
        Color(nsColor: .windowBackgroundColor),
        Color.accentColor.opacity(0.06),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private func tempColor(_ c: Float) -> Color {
    if c >= 90 { return .red }
    if c >= 75 { return .orange }
    return .primary
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
