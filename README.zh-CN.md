# AirPulse — Mac 风扇控制 / MacBook Pro Fan Control

<p align="center">
  <img src="Resources/AppIcon-256.png" width="128" height="128" alt="AirPulse 图标" />
</p>

**AirPulse** 是开源的 **Mac 风扇控制**应用：菜单栏看温度、左右风扇默认联动，以及**智能（Smart）** 模式——在风扇突然狂转之前，就按温度平滑加速。

面向 **Apple Silicon** MacBook / MacBook Pro（M 系列）。

> English README: [README.md](README.md)

## 为什么 Smart 比系统 Auto 更好用

macOS **自动（Auto）** 把风扇交给系统。能用，但是黑盒：常常先憋很久，温度已经很高了才猛地拉高转速。你看不到规则，也调不了。

**Smart** 是 AirPulse 的方案：一条透明的 **温度 → 转速** 策略，由你掌控。

| | 系统 **Auto** | AirPulse **Smart** |
|--|---------------|---------------------|
| 谁决定转速 | 苹果 SMC / thermalmonitord | AirPulse，约每秒更新 |
| 何时加速 | 往往偏晚，然后很猛 | 更早、更平滑爬升 |
| 可预期？ | 否 | 是 — 固定折点，心里有数 |
| 噪音体验 | 负载下突然起飞 | 随温度渐变 |
| 安全网 | 仅系统 | Smart **再加** 安静/均衡拦截与转速地板 |

默认智能映射（点与点之间线性插值）：

| 温度 | 风扇（相对最小～最大） |
|------|------------------------|
| ≤55°C | ~15% — 凉快时保持安静 |
| 70°C | ~40% |
| 82°C | ~70% |
| ≥92°C | ~95% — 强力散热 |

**日常建议直接用 Smart**：写代码、剪视频、轻度游戏时不用盯着滑杆，又比干等系统突然拉满更从容。需要时仍可一键切安静 / 均衡 / 强冷 / 自动。

## 热安全（高温不会还卡在安静模式）

手动控风扇最怕：重负载时还开着 **安静（Quiet）**。AirPulse 会主动拦住：

| 阈值 | 行为 |
|------|------|
| **≥78°C** | **禁止 Quiet**；已在 Quiet → 升到 Balanced；滑杆地板约 45% |
| **≥85°C** | **禁止 Balanced** / 倾向强冷；滑杆地板约 70% |
| **≥90°C** | 强制 **Cool（强冷）** |
| **≥100°C** | 交还系统 **Auto** |

另外：退出恢复 Auto、睡眠唤醒后重申设定、Helper 预热减轻首次切手动延迟。

## 下载

最新 DMG：**[Releases](https://github.com/bhu0345/AirPulse/releases)**

1. 下载 `AirPulse-x.y.z.dmg`
2. 拖到 **应用程序**
3. 启动（菜单栏风扇图标）
4. 点一次 **启用风扇控制**（管理员密码）
5. 日常优先选 **Smart**，需要时再切 Auto / Quiet / Balanced / Cool

> 未签名构建：右键 → **打开**，或在 **系统设置 → 隐私与安全性** 允许。

## 功能

- 菜单栏：CPU / GPU / 电池温度 + 联动主滑杆
- 预设：**自动 · 安静 · 均衡 · 强冷 · 智能**
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

手动控风扇可能影响散热、噪音与硬件寿命。安全层能降低风险，不能消除风险。未知负载下优先 **Smart** 或 **Auto**，温度持续升高时请勿忽视。

## 关键词

`mac风扇控制` · `macbook智能风扇` · `mac fan control` · `macbook fan control` · `macos风扇控制` · `苹果硅风扇` · `SMC风扇`
