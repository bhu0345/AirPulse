# AirPulse — M 系列 Mac 风扇控制

<p align="center">
  <img src="Resources/AppIcon-256.png" width="128" height="128" alt="AirPulse 图标" />
</p>

**AirPulse** 是开源的 **Mac 风扇控制**应用：菜单栏看温度、多风扇默认联动，以及 **AirPulse Smart mode（智能模式）**——在风扇突然狂转之前，就按温度平滑加速。

面向带风扇的 **Apple Silicon（M 系列）** Mac：MacBook Pro、Mac mini、Mac Studio、Mac Pro、iMac。风扇数量与传感器在运行时探测，单风扇桌面机和双风扇笔记本共用同一套逻辑。无风扇机型（MacBook Air）仍可查看温度。

> English README: [README.md](README.md)

## 支持的 Mac

AirPulse 通过 Apple Silicon SMC 工作，不绑定某一款机身：

| Mac | 风扇 | 说明 |
|-----|------|------|
| **MacBook Pro**（M1 起） | 1–2 | 默认联动（高级里可解除，分别控制） |
| **Mac mini**（M1 起） | 1 | 单风扇转速 + 智能 / 自定义 / 自动 |
| **Mac Studio** | 1+ | 对 SMC 报告的全部风扇联动 |
| **Mac Pro**（M 系列） | 多个 | 全部风扇联动 |
| **iMac**（M 系列） | 1+ | 与其他 M 系列桌面机相同 |
| **MacBook Air** | 无 | 仅温度，没有可控制的风扇 |

不面向 Intel Mac。开发机是 MacBook Pro（M5 Pro）；Mini / Studio / Pro 使用同一套 SMC 风扇 key（`FNum`、`F%dTg`、`F%dmd` / `F%dMd`）。

## 模式

控制模型刻意简化，只保留三种：

| 模式 | 作用 |
|------|------|
| **AirPulse Smart mode（智能）** | 日常推荐。按温度自动调速（见下方映射表）。 |
| **Custom（自定义）** | 用滑杆设定固定联动转速。 |
| **Auto（自动）** | 交还给 macOS / SMC。 |

## 为什么 AirPulse Smart mode 比系统 Auto 更好用

macOS **自动（Auto）** 把风扇交给系统。能用，但是黑盒：常常先憋很久，温度已经很高了才猛地拉高转速。你看不到规则，也调不了。

**AirPulse Smart mode** 是透明的 **温度 → 转速** 策略，由你掌控。

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

## 热安全

风扇开太低、负载又重时容易囤热。AirPulse 会主动拦住——尤其在 **自定义** 模式下：

| 阈值 | 行为 |
|------|------|
| **≥78°C** | 最低转速地板约 45%（降温约 4°C 后才放开） |
| **≥85°C** | 地板约 70%（带滞后） |
| **≥90°C** | 紧急抬升约 85%（或 Smart 映射，取更高） |
| **≥100°C** | 交还系统 **Auto** |

另外：退出 / Helper 断开时恢复 Auto、Helper 版本检测、睡眠唤醒后重申设定、Helper 预热减轻首次切手动延迟。

## 下载

最新 DMG：**[Releases](https://github.com/bhu0345/AirPulse/releases)**（当前 **v1.0.1**）

1. 下载 `AirPulse-x.y.z.dmg`
2. 拖到 **应用程序**
3. 启动（菜单栏风扇图标）
4. 点一次 **启用风扇控制**（管理员密码）
5. 日常选 **AirPulse Smart mode**，需要时再切 **自定义** / **自动**

在 **高级** 里点 **检查更新**，有新版本时可直接下载。

> 未签名构建：右键 → **打开**，或在 **系统设置 → 隐私与安全性** 允许。

## 功能

- 菜单栏：CPU / GPU / 电池（桌面机则为内存）温度 + 联动转速滑杆
- 三种预设：**自动 · 自定义 · 智能**（Smart 在界面上突出显示）
- 多风扇机型可解除联动，分别控制
- 语言、**摄氏 / 华氏**、登录时打开、毛玻璃**背景色**、**检查更新**、恢复自动等低频设置收进 **高级**
- 右键菜单栏图标即可 **恢复自动** / **退出**
- 登录时打开 + 记住上次预设 / 转速
- 默认英语，应用内 **English / 中文**
- Apple Silicon SMC（`F%dmd` / `F%dMd`，可选 `Ftst`）
- CLI：`airpulse-cli probe [--write]` / `preset <auto\|custom\|smart>`

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

`mac风扇控制` · `M系列风扇` · `mac mini风扇` · `mac studio风扇` · `AirPulse Smart mode` · `mac fan control` · `macos风扇控制` · `苹果硅风扇` · `SMC风扇`
