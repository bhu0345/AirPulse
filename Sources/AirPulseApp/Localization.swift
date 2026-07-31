import FanKit
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
  case english = "en"
  case chinese = "zh-Hans"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .english: return "English"
    case .chinese: return "中文"
    }
  }
}

@MainActor
final class LanguageStore: ObservableObject {
  static let shared = LanguageStore()
  private static let defaultsKey = "airpulse.language"

  @Published var language: AppLanguage {
    didSet {
      UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey)
    }
  }

  var strings: L10n { L10n(language: language) }

  private init() {
    if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
      let saved = AppLanguage(rawValue: raw)
    {
      language = saved
    } else {
      language = .english
    }
  }
}

struct L10n {
  let language: AppLanguage

  private func t(_ en: String, _ zh: String) -> String {
    language == .chinese ? zh : en
  }

  var macFanControl: String { t("Mac fan control", "Mac 风扇控制") }
  var writable: String { t("Writable", "可写入") }
  var readOnlyNeedAuth: String { t("Read-only / needs authorization", "只读 / 需授权") }
  var readingTemps: String { t("Reading temperatures…", "温度读取中…") }
  var fansLinked: String { t("Fans on both sides", "左右风扇联动") }
  var fansUnlinked: String { t("Independent control", "已解除联动") }
  var unlinkHelp: String {
    t("Turn off to control left and right fans separately", "关闭后可分别调节左右风扇")
  }
  var perFanControl: String { t("Per-fan control", "分别控制") }
  var fan: String { t("Fan", "风扇") }
  var advanced: String { t("Advanced", "高级") }
  var hideAdvanced: String { t("Hide advanced", "收起高级") }
  var restoreAuto: String { t("Restore Auto", "恢复自动") }
  var quit: String { t("Quit", "退出") }
  var languageLabel: String { t("Language", "语言") }

  var connecting: String { t("Connecting…", "正在连接…") }
  var readingSensors: String { t("Reading sensors…", "读取传感器…") }
  var smcReadFailed: String { t("SMC read failed", "SMC 读取失败") }
  var helperConnected: String { t("Privileged helper connected", "已连接特权 Helper") }
  var monitorMode: String {
    t(
      "Monitor mode (install Helper or use sudo CLI to write)",
      "监视模式（写入需安装 Helper 或使用 sudo CLI）"
    )
  }
  var presetApplied: String { t("Preset", "预设") }
  var failed: String { t("Failed", "失败") }
  var linkedPercent: String { t("Linked", "联动") }
  var restoredAuto: String { t("Restored system Auto", "已恢复系统自动") }
  var cliMissing: String {
    t("airpulse-cli not found — run Scripts/build-app.sh", "未找到 airpulse-cli，请先 Scripts/build-app.sh")
  }
  var appliedAdmin: String { t("Applied (administrator)", "已应用（管理员权限）") }
  var writeFailed: String { t("Write failed (permission or SMC)", "写入失败（权限或 SMC）") }
  var reassertAfterWake: String {
    t("Re-applying fan settings after wake…", "唤醒后重新施加风扇设定…")
  }
  var safetyCritical: String {
    t("Temperature critical — restored system Auto", "温度过高，已恢复系统自动控温")
  }
  var safetyWarning: String {
    t("Temperature high — switched to Cool", "温度偏高，已切换强冷")
  }
  var ftstYes: String { t("yes", "有") }
  var ftstNo: String { t("no", "无") }

  func presetTitle(_ preset: FanPreset) -> String {
    switch preset {
    case .auto: return t("Auto", "自动")
    case .quiet: return t("Quiet", "安静")
    case .balanced: return t("Balanced", "均衡")
    case .cool: return t("Cool", "强冷")
    }
  }

  func sensorName(_ key: String) -> String {
    switch key {
    case "CPU", "GPU": return key
    case "Battery": return t("Battery", "电池")
    case "Memory": return t("Memory", "内存")
    default:
      if key.hasPrefix("CPU") || key.hasPrefix("GPU") { return key }
      return key
    }
  }

  func fanLabel(_ index: Int) -> String { "\(fan) \(index)" }
  func fanRPM(_ index: Int, rpm: Int) -> String { "\(fan)\(index) \(rpm)" }
  func presetStatus(_ preset: FanPreset) -> String {
    "\(presetApplied): \(presetTitle(preset))"
  }
  func linkedStatus(_ percent: Int) -> String {
    "\(linkedPercent) \(percent)%"
  }
  func fanRPMStatus(_ index: Int, rpm: Int) -> String {
    "\(fan) \(index): \(rpm) RPM"
  }
}
