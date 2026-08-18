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
      L10n.cachedLanguage = language
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
    L10n.cachedLanguage = language
  }
}

struct L10n {
  let language: AppLanguage

  /// Thread-safe snapshot for background / XPC-adjacent code.
  nonisolated(unsafe) static var cachedLanguage: AppLanguage = .english

  nonisolated static var current: L10n { L10n(language: cachedLanguage) }

  private func t(_ en: String, _ zh: String) -> String {
    language == .chinese ? zh : en
  }

  var macFanControl: String { t("Mac fan control", "Mac 风扇控制") }
  var writable: String { t("Writable", "可写入") }
  var readOnlyNeedAuth: String { t("Read-only / needs authorization", "只读 / 需授权") }
  var readingTemps: String { t("Reading temperatures…", "温度读取中…") }
  var fanSpeed: String { t("Fan speed", "风扇转速") }
  var fansLinked: String { t("Linked fans", "风扇联动") }
  var fansUnlinked: String { t("Independent control", "已解除联动") }
  var unlinkHelp: String {
    t("Turn off to control each fan separately", "关闭后可分别调节各风扇")
  }
  var noFansTitle: String { t("No fans on this Mac", "这台 Mac 没有风扇") }
  var noFansHint: String {
    t(
      "Fanless M-series Macs (such as MacBook Air) can still show temperatures.",
      "无风扇的 M 系列 Mac（例如 MacBook Air）仍可查看温度。"
    )
  }
  var perFanControl: String { t("Per-fan control", "分别控制") }
  var fan: String { t("Fan", "风扇") }
  var advanced: String { t("Advanced", "高级") }
  var hideAdvanced: String { t("Hide advanced", "收起高级") }
  var restoreAuto: String { t("Restore Auto", "恢复自动") }
  var quit: String { t("Quit", "退出") }
  var quitApp: String { t("Quit AirPulse", "退出 AirPulse") }
  var languageLabel: String { t("Language", "语言") }
  var temperatureUnitLabel: String { t("Temperature", "温度单位") }
  var statusLabel: String { t("Status:", "状态：") }
  var enableFanControl: String { t("Enable Fan Control", "启用风扇控制") }
  var enableFanControlHint: String {
    t(
      "One-time password to install a system helper — then no more prompts. If the menu closes, click the fan icon in the menu bar again.",
      "只需输入一次密码安装系统助手，之后不再弹窗。若菜单关闭，请再次点击菜单栏风扇图标。"
    )
  }
  var helperInstalling: String { t("Installing helper…", "正在安装助手…") }
  var helperInstallFailed: String { t("Helper install failed", "助手安装失败") }
  var helperMissingBinary: String {
    t("Helper binary not found in the app bundle", "应用内未找到 Helper 程序")
  }
  var needHelperToWrite: String {
    t("Tap Enable Fan Control first (one-time setup)", "请先点「启用风扇控制」（只需一次）")
  }

  var connecting: String { t("Connecting…", "正在连接…") }
  var readingSensors: String { t("Reading sensors…", "读取传感器…") }
  var smcReadFailed: String { t("SMC read failed", "SMC 读取失败") }
  var helperConnected: String { t("Fan control ready", "风扇控制已就绪") }
  var helperNeedsUpdate: String {
    t("Helper update required", "需要更新系统助手")
  }
  var helperNeedsUpdateHint: String {
    t(
      "Your system helper is outdated. Tap Update Helper (one admin password) to keep Smart mode and safety features working.",
      "系统助手版本过旧。请点「更新助手」（需一次管理员密码），以继续使用智能模式与安全功能。"
    )
  }
  var updateHelper: String { t("Update Helper", "更新助手") }
  var monitorMode: String {
    t(
      "Monitoring only — enable fan control to change speeds",
      "仅监视中 — 启用风扇控制后才能调速"
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
    t(
      "Temperature high — raised fans to a safe cooling level",
      "温度偏高，已抬高风扇到安全散热水平"
    )
  }
  var safetyThermalFloor: String {
    t(
      "Fan speed raised to a safe minimum for current temperature",
      "已按当前温度抬高到安全最低转速"
    )
  }
  var launchAtLogin: String { t("Launch at Login", "登录时打开") }
  var launchAtLoginFailed: String {
    t("Could not change Launch at Login — check System Settings", "无法修改登录项 — 请检查系统设置")
  }
  var backgroundLabel: String { t("Background", "背景") }
  var updatesLabel: String { t("Updates", "更新") }
  var checkForUpdates: String { t("Check for Updates", "检查更新") }
  var checkAgain: String { t("Check Again", "重新检查") }
  var checkingUpdates: String { t("Checking…", "正在检查…") }
  var upToDate: String { t("You're up to date", "已是最新版本") }
  var installUpdate: String { t("Install Update", "立即更新") }
  var downloadingUpdate: String { t("Downloading…", "正在下载…") }
  var installingUpdate: String { t("Installing…", "正在安装…") }
  var restartingForUpdate: String { t("Restarting…", "正在重启…") }
  var updateCheckFailed: String { t("Could not check for updates", "无法检查更新") }

  func currentVersion(_ version: String) -> String {
    t("Current version \(version)", "当前版本 \(version)")
  }

  func updateAvailable(_ version: String) -> String {
    t("Version \(version) is available", "发现新版本 \(version)")
  }

  func newerThanRelease(_ latest: String) -> String {
    t("This build is newer than \(latest)", "当前版本新于 \(latest)")
  }

  func backgroundThemeName(_ theme: PanelBackgroundTheme) -> String {
    switch theme {
    case .clear: return t("Clear", "透明")
    case .graphite: return t("Graphite", "石墨")
    case .blue: return t("Blue", "蓝色")
    case .purple: return t("Purple", "紫色")
    case .mint: return t("Mint", "青绿")
    }
  }
  var smartHelp: String {
    t(
      "AirPulse Smart mode: fan speed follows temperature automatically — recommended daily mode",
      "AirPulse Smart mode：按温度自动调速 — 推荐日常使用"
    )
  }
  var ftstYes: String { t("yes", "有") }
  var ftstNo: String { t("no", "无") }

  func hardwareSummary(fanCount: Int, chip: String) -> String {
    let name = chip.isEmpty ? t("Apple Silicon", "Apple 芯片") : chip
    if fanCount <= 0 {
      return t("\(name) · no fans", "\(name) · 无风扇")
    }
    if fanCount == 1 {
      return t("\(name) · 1 fan", "\(name) · 1 个风扇")
    }
    return t("\(name) · \(fanCount) fans", "\(name) · \(fanCount) 个风扇")
  }

  func presetTitle(_ preset: FanPreset) -> String {
    switch preset {
    case .auto: return t("Auto", "自动")
    case .custom: return t("Custom", "自定义")
    case .smart: return t("Smart", "智能")
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
  func smartStatus(_ temperature: String, percent: Int) -> String {
    t("Smart \(temperature) → \(percent)%", "智能 \(temperature) → \(percent)%")
  }
  func fanRPMStatus(_ index: Int, rpm: Int) -> String {
    "\(fan) \(index): \(rpm) RPM"
  }
}
