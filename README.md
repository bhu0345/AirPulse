# AirPulse

面向 MacBook Pro 的原生菜单栏风扇控制器：默认**左右风扇联动**、一键预设，替代 Macs Fan Control 的双表 + 分别 Custom 体验。

详解不足与对策见 [docs/ux-critique.md](docs/ux-critique.md)。环境前置见 [docs/prerequisites.md](docs/prerequisites.md)。

## 功能

- 菜单栏 popover：关键温度、联动主滑杆、自动 / 安静 / 均衡 / 强冷
- 可解除联动，分别控制左右风扇
- Apple Silicon SMC（探测 `F%dmd` / `F%dMd`，可选 `Ftst`）
- 退出恢复系统 Auto；过热保护；睡眠唤醒后重申手动设定
- CLI 探针：`airpulse-cli probe [--write]`

## 仓库结构

```text
├── README.md
├── Package.swift          # SwiftPM 工程
├── Sources/               # 源码（App / CLI / Helper / SMC）
├── Scripts/               # 构建与 Helper 安装脚本
├── docs/                  # UX 分析、前置条件、探针结果
├── Resources/             # LaunchDaemon 模板
└── Release/AirPulse.app   # 预构建可执行应用（菜单栏 App + CLI + Helper）
```

## 快速开始

### 直接运行预构建 App

```bash
open ./Release/AirPulse.app
```

### 从源码构建

```bash
chmod +x Scripts/*.sh
./Scripts/build-app.sh   # 输出到 Products/ 并同步到 Release/

# 只读探针（无需 root）
./Release/AirPulse.app/Contents/MacOS/airpulse-cli probe

# 写转速可行性（会短暂改风扇并恢复 Auto）
sudo ./Release/AirPulse.app/Contents/MacOS/airpulse-cli probe --write
```

可选：安装特权 Helper（免去每次 osascript 弹密码）：

```bash
sudo ./Scripts/install-helper.sh
```

开发期请先退出 **Macs Fan Control**，避免抢控。

## 架构

```text
AirPulse.app (SwiftUI MenuBarExtra)
    ├─ 只读：进程内 SMCKit
    └─ 写入：XPC → AirPulseHelper (LaunchDaemon)
              或 osascript + airpulse-cli（未装 Helper 时）
```

## 注意

手动控风扇可能影响散热与噪音，有损坏硬件风险。请监控温度；过热时应用会强制强冷或交还系统 Auto。
