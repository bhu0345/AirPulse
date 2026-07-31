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
└── Release/AirPulse.app
```

## 快速开始

### 直接运行预构建 App

```bash
open ./Release/AirPulse.app
```

### 从源码构建

```bash
chmod +x Scripts/*.sh
./Scripts/build-app.sh

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
