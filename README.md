# AirPulse

A native macOS menu-bar fan controller for MacBook Pro. **Fans on both sides are controlled together by default**, with one-tap presets.

> 中文说明见 [README.zh-CN.md](README.zh-CN.md)。

## Features

- Menu-bar popover: key temperatures, master slider for fans on both sides, Auto / Quiet / Balanced / Cool
- Optional unlink for independent left/right control
- **English by default**, with in-app language switch (English / 中文)
- Apple Silicon SMC (`F%dmd` / `F%dMd`, optional `Ftst`)
- Restore system Auto on quit; overheat safety; re-assert after sleep/wake
- CLI probe: `airpulse-cli probe [--write]`

## Repository layout

```text
├── README.md / README.zh-CN.md
├── Package.swift
├── Sources/               # App / CLI / Helper / SMC
├── Scripts/               # Build & helper install
├── docs/
├── Resources/
└── Release/AirPulse.app   # Prebuilt app (+ CLI + Helper)
```

## Quick start

### Run the prebuilt app

```bash
open ./Release/AirPulse.app
```

### Build from source

```bash
chmod +x Scripts/*.sh
./Scripts/build-app.sh   # writes Products/ and syncs Release/

./Release/AirPulse.app/Contents/MacOS/airpulse-cli probe
sudo ./Release/AirPulse.app/Contents/MacOS/airpulse-cli probe --write
```

Optional privileged helper (avoids repeated admin prompts):

```bash
sudo ./Scripts/install-helper.sh
```

Avoid running another fan-control app at the same time — they will conflict on SMC writes.

## Architecture

```text
AirPulse.app (SwiftUI MenuBarExtra)
    ├─ reads: in-process SMCKit
    └─ writes: XPC → AirPulseHelper (LaunchDaemon)
              or osascript + airpulse-cli (if helper is not installed)
```

## Caution

Manual fan control can affect cooling and noise, and may risk hardware damage. Watch temperatures; on overheat AirPulse forces Cool or hands control back to system Auto.
