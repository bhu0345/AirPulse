# AirPulse

面向 MacBook Pro 的原生菜单栏风扇控制器：默认**左右风扇联动**、一键预设。

> English README: [README.md](README.md)

## 功能

- 菜单栏 popover：关键温度、联动主滑杆、自动 / 安静 / 均衡 / 强冷
- 可解除联动，分别控制左右风扇
- **默认英语界面**，应用内可切换 English / 中文
- Apple Silicon SMC（探测 `F%dmd` / `F%dMd`，可选 `Ftst`）
- 退出恢复系统 Auto；过热保护；睡眠唤醒后重申手动设定
- CLI 探针：`airpulse-cli probe [--write]`

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

请勿同时运行其他风扇控制软件，以免抢写 SMC。

## 注意

手动控风扇可能影响散热与噪音，有损坏硬件风险。请监控温度；过热时应用会强制强冷或交还系统 Auto。
