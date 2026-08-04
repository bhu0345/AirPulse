# AirPulse — Mac 风扇控制 / MacBook Pro Fan Control

<p align="center">
  <img src="Resources/AppIcon-256.png" width="128" height="128" alt="AirPulse 图标" />
</p>

**AirPulse** 是开源的 **Mac 风扇控制**应用：菜单栏看温度、左右风扇默认联动，以及 **AirPulse Smart mode（智能模式）**——在风扇突然狂转之前，就按温度平滑加速。

面向 **Apple Silicon** MacBook / MacBook Pro（M 系列）。

> English README: [README.md](README.md)

## 为什么 AirPulse Smart mode 比系统 Auto 更好用

macOS **自动（Auto）** 把风扇交给系统。能用，但是黑盒：常常先憋很久，温度已经很高了才猛地拉高转速。你看不到规则，也调不了。

**AirPulse Smart mode** 是答案：一条透明的 **温度 → 转速** 策略，由你掌控。

| | 系统 **Auto** | **AirPulse Smart mode** |
|--|---------------|-------------------------|
| 谁决定转速 | 苹果 SMC / thermalmonitord | AirPulse，约每秒更新 |
| 何时加速 | 往往偏晚，然后很猛 | 更早、更平滑爬升 |
| 可预期？ | 否 | 是 — 固定折点，心里有数 |
| 噪音体验 | 负载下突然起飞 | 随温度渐变 |
| 安全网 | 仅系统 | Smart mode **再加** 转速地板与紧急抬升 |

默认 AirPulse Smart mode 映射（点与点之间线性插值）：

| 温度 | 风扇（相对最小～最大） |
|------|------------------------|
| ≤55°C | ~15% — 凉快时保持安静 |
| 70°C | ~40% |
| 82°C | ~70% |
| ≥92°C | ~95% — 强力散热 |

**日常建议直接用 AirPulse Smart mode。** 需要固定转速？切 **自定义（Custom）** 用滑杆。想交还给系统？点 **自动（Auto）**。

## 热安全

风扇开太低、负载又重时容易囤热。AirPulse 会主动拦住：

| 阈值 | 行为 |
|------|------|
| **≥78°C** | 自定义滑杆地板约 45% |
| **≥85°C** | 地板约 70% |
| **≥90°C** | 紧急抬升约 85%（或 Smart 曲线，取更高） |
| **≥100°C** | 交还系统 **Auto** |

另外：退出恢复 Auto、睡眠唤醒后重申设定、Helper 预热减轻首次切手动延迟。

## 下载

最新 DMG：**[Releases](https://github.com/bhu0345/AirPulse/releases)**

1. 下载 `AirPulse-x.y.z.dmg`
2. 拖到 **应用程序**
3. 启动（菜单栏风扇图标）
4. 点一次 **启用风扇控制**（管理员密码）
5. 日常优先选 **AirPulse Smart mode**，需要时再切 **自定义** / **自动**

> 未签名构建：右键 → **打开**，或在 **系统设置 → 隐私与安全性** 允许。

## 功能

- 菜单栏：CPU / GPU / 电池温度 + 联动主滑杆
- 预设：**自动 · 自定义 · 智能**（**AirPulse Smart mode**）
- 可解除联动，分别控制左右风扇
- 登录时打开 + 记住上次预设 / 转速
- 默认英语，应用内 **English / 中文**
- Apple Silicon SMC（`F%dmd` / `F%dMd`，可选 `Ftst`）
- CLI：`airpulse-cli probe [--write]`

## 快速开始

```bash
open ./Release/AirPulse.app
# 或从源码：
chmod +x Scripts/*.sh
./Scripts/build-app.sh
./Scripts/package-dmg.sh
```

```bash
sudo ./Scripts/install-helper.sh   # 可选；或用应用内「启用风扇控制」
```

请勿同时运行其他 Mac 风扇控制软件，以免抢写 SMC。

## 注意

手动控风扇可能影响散热、噪音与硬件寿命。安全层能降低风险，不能消除风险。未知负载下优先 **AirPulse Smart mode** 或 **Auto**，温度持续升高时请勿忽视。

## 关键词

`mac风扇控制` · `AirPulse Smart mode` · `mac fan control` · `macbook fan control` · `macos风扇控制` · `苹果硅风扇` · `SMC风扇`
