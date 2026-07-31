# AirPulse — Mac Fan Control for MacBook Pro

<p align="center">
  <img src="Resources/AppIcon-256.png" width="128" height="128" alt="AirPulse icon" />
</p>

**AirPulse** is a free, open-source **Mac fan control** app for macOS. It sits in the menu bar and lets you monitor temperatures and manually set MacBook / MacBook Pro fan speeds on **Apple Silicon** (including M-series chips).

**Fans on both sides are controlled together by default**, with one-tap presets (Auto / Quiet / Balanced / Cool). Optional unlink for independent left/right control.

> Looking for a lightweight **macOS fan controller** or an alternative way to manage MacBook fan RPM via SMC? Download the DMG below or build from source.  
> 中文说明见 [README.zh-CN.md](README.zh-CN.md)。

## Why AirPulse

- Native SwiftUI **menu-bar Mac fan control** — no Electron, no cluttered dashboard
- Linked dual-fan slider + presets for everyday **MacBook Pro fan** noise/cooling tradeoffs
- Reads CPU / GPU / battery temps from Apple **SMC**; writes fan targets through a one-time privileged helper
- English UI by default, with in-app **English / 中文**
- Restore system Auto on quit; overheat safety; re-assert after sleep/wake

## Features

- Menu-bar popover: key temperatures, master slider for fans on both sides, Auto / Quiet / Balanced / Cool
- Optional unlink for independent left/right control
- Apple Silicon SMC (`F%dmd` / `F%dMd`, optional `Ftst`)
- CLI probe: `airpulse-cli probe [--write]`

## Download

Get the latest macOS disk image from **[Releases](https://github.com/bhu0345/AirPulse/releases)**:

1. Download `AirPulse-x.y.z.dmg`
2. Open the DMG and drag **AirPulse** into **Applications**
3. Launch AirPulse from Applications (menu-bar fan icon)
4. Tap **Enable Fan Control** once (admin password) to install the helper

> First launch of an unsigned build: right-click → **Open**, or allow it under **System Settings → Privacy & Security**.

## Quick start

### Run from this repo

```bash
open ./Release/AirPulse.app
```

### Build from source

```bash
chmod +x Scripts/*.sh
./Scripts/build-app.sh   # writes Products/ and syncs Release/
./Scripts/package-dmg.sh # optional: dist/AirPulse-0.1.0.dmg

./Release/AirPulse.app/Contents/MacOS/airpulse-cli probe
sudo ./Release/AirPulse.app/Contents/MacOS/airpulse-cli probe --write
```

Optional privileged helper (avoids repeated admin prompts):

```bash
sudo ./Scripts/install-helper.sh
```

Avoid running another Mac fan control / SMC fan app at the same time — they will conflict on SMC writes.

## Repository layout

```text
├── README.md / README.zh-CN.md
├── Package.swift
├── Sources/               # App / CLI / Helper / SMC
├── Scripts/               # Build, helper install, DMG package
├── docs/
├── Resources/
├── Release/AirPulse.app   # Prebuilt app (+ CLI + Helper)
└── dist/                  # AirPulse-*.dmg (gitignored; see Releases)
```

## Architecture

```text
AirPulse.app (SwiftUI MenuBarExtra)
    ├─ reads: in-process SMCKit
    └─ writes: XPC → AirPulseHelper (LaunchDaemon)
              or osascript + airpulse-cli (if helper is not installed)
```

## Keywords / topics

`mac fan control` · `macbook fan control` · `macbook pro fan` · `macos fan controller` · `apple silicon fan` · `smc fan control` · `menu bar fan app`

## Caution

Manual fan control can affect cooling and noise, and may risk hardware damage. Watch temperatures; on overheat AirPulse forces Cool or hands control back to system Auto.
