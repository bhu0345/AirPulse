# AirPulse — Mac 风扇控制 / MacBook Pro Fan Control

<p align="center">
  <img src="Resources/AppIcon-256.png" width="128" height="128" alt="AirPulse 图标" />
</p>

**AirPulse** 是开源的 **Mac 风扇控制**（Mac fan control）应用：菜单栏监控温度，并在 **Apple Silicon**（M 系列）MacBook / MacBook Pro 上手动调节风扇转速。

默认**左右风扇联动**，一键预设（自动 / 安静 / 均衡 / 强冷）；也可解除联动分别控制。

> 寻找轻量的 **macOS 风扇控制器**、或基于 SMC 调节 MacBook 风扇 RPM 的方案？请下载下方 DMG 或自行编译。  
> English README: [README.md](README.md)

## 为什么选 AirPulse

- 原生 SwiftUI **菜单栏 Mac 风扇控制**，界面简洁
- 联动主滑杆 + 预设，兼顾 MacBook Pro 噪音与散热
- 从 Apple **SMC** 读取 CPU / GPU / 电池温度；写转速需一次特权 Helper
- 默认英语界面，应用内可切换 **English / 中文**
- 退出恢复系统 Auto；过热保护；睡眠唤醒后重申手动设定

## 功能

- 菜单栏 popover：关键温度、联动主滑杆、自动 / 安静 / 均衡 / 强冷
- 可解除联动，分别控制左右风扇
- Apple Silicon SMC（`F%dmd` / `F%dMd`，可选 `Ftst`）
- CLI 探针：`airpulse-cli probe [--write]`

## 下载

从 **[Releases](https://github.com/bhu0345/AirPulse/releases)** 获取最新 macOS 磁盘镜像：

1. 下载 `AirPulse-x.y.z.dmg`
2. 打开 DMG，将 **AirPulse** 拖到 **应用程序**
3. 从应用程序启动（菜单栏风扇图标）
4. 首次点击 **启用风扇控制**（输入一次管理员密码）安装助手

> 未签名构建首次打开：右键 → **打开**，或在 **系统设置 → 隐私与安全性** 中允许。

## 快速开始

### 直接运行仓库内预构建 App

```bash
open ./Release/AirPulse.app
```

### 从源码构建

```bash
chmod +x Scripts/*.sh
./Scripts/build-app.sh
./Scripts/package-dmg.sh   # 可选：生成 dist/AirPulse-0.1.0.dmg

./Release/AirPulse.app/Contents/MacOS/airpulse-cli probe
sudo ./Release/AirPulse.app/Contents/MacOS/airpulse-cli probe --write
```

可选：安装特权 Helper：

```bash
sudo ./Scripts/install-helper.sh
```

请勿同时运行其他 Mac 风扇控制 / SMC 风扇软件，以免抢写 SMC。

## 仓库结构

```text
├── README.md / README.zh-CN.md
├── Package.swift
├── Sources/
├── Scripts/
├── docs/
├── Resources/
├── Release/AirPulse.app
└── dist/                  # AirPulse-*.dmg（已 gitignore；见 Releases）
```

## 关键词

`mac风扇控制` · `macbook风扇` · `mac fan control` · `macbook fan control` · `macos风扇控制` · `苹果硅风扇` · `SMC风扇`

## 注意

手动控风扇可能影响散热与噪音，有损坏硬件风险。请监控温度；过热时应用会强制强冷或交还系统 Auto。
