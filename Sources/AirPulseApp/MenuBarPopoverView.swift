import FanKit
import SwiftUI

struct MenuBarPopoverView: View {
  @ObservedObject var service: FanService
  @State private var showAdvanced = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      temperatureRow
      presetRow
      linkedSlider
      if showAdvanced || !service.linkedEnabled {
        unlinkedSection
      }
      footer
    }
    .padding(16)
    .frame(width: 320)
    .background(popoverBackground)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text("AirPulse")
          .font(.system(size: 18, weight: .semibold, design: .rounded))
        Text(service.hardwareSummary.isEmpty ? "Mac 风扇控制" : service.hardwareSummary)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer()
      Circle()
        .fill(service.canWrite ? Color.green.opacity(0.85) : Color.orange.opacity(0.85))
        .frame(width: 8, height: 8)
        .help(service.canWrite ? "可写入" : "只读 / 需授权")
    }
  }

  private var temperatureRow: some View {
    HStack(spacing: 10) {
      ForEach(service.temperatures.prefix(3)) { reading in
        VStack(spacing: 2) {
          Text(reading.name)
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
        Text("温度读取中…")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var presetRow: some View {
    HStack(spacing: 6) {
      ForEach(FanPreset.allCases) { preset in
        Button {
          service.applyPreset(preset)
        } label: {
          Text(preset.titleZH)
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
              service.activePreset == preset
                ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06)
            )
        )
        .overlay(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(
              service.activePreset == preset ? Color.accentColor.opacity(0.5) : Color.clear,
              lineWidth: 1
            )
        )
      }
    }
  }

  private var linkedSlider: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(service.linkedEnabled ? "左右风扇联动" : "已解除联动")
          .font(.subheadline.weight(.medium))
        Spacer()
        Toggle("", isOn: Binding(
          get: { service.linkedEnabled },
          set: { newValue in
            service.linkedEnabled = newValue
            if !newValue { showAdvanced = true }
          }
        ))
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .help("关闭后可分别调节左右风扇")
      }

      if service.linkedEnabled {
        HStack {
          Image(systemName: "fanblades")
            .foregroundStyle(.secondary)
          Slider(
            value: Binding(
              get: { service.linkedFraction },
              set: { service.linkedFraction = $0 }
            ),
            in: 0...1
          ) { editing in
            if !editing {
              service.applyLinkedFraction(service.linkedFraction)
            }
          }
          Text("\(Int(service.linkedFraction * 100))%")
            .font(.system(.caption, design: .monospaced))
            .frame(width: 36, alignment: .trailing)
        }

        HStack {
          ForEach(service.fans) { fan in
            Text("风扇\(fan.index) \(Int(fan.actualRPM))")
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
      Text("分别控制")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      ForEach(service.fans) { fan in
        HStack {
          Text("风扇 \(fan.index)")
            .font(.caption)
            .frame(width: 44, alignment: .leading)
          Slider(
            value: Binding(
              get: { service.unlinkRPM[fan.index] ?? 0.3 },
              set: { service.unlinkRPM[fan.index] = $0 }
            ),
            in: 0...1
          ) { editing in
            if !editing {
              service.applyUnlinked(
                fanIndex: fan.index,
                fraction: service.unlinkRPM[fan.index] ?? 0.3
              )
            }
          }
          .disabled(service.linkedEnabled)
          Text("\(Int(fan.actualRPM))")
            .font(.system(.caption2, design: .monospaced))
            .frame(width: 40, alignment: .trailing)
        }
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
        Button(showAdvanced ? "收起高级" : "高级") {
          withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
        }
        .buttonStyle(.borderless)
        .font(.caption)

        Spacer()

        Button("恢复自动") {
          service.restoreAuto()
        }
        .buttonStyle(.borderless)
        .font(.caption)

        Button("退出") {
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
