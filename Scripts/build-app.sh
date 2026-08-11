#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Building AirPulse (release)"
swift build -c release --product airpulse-cli
swift build -c release --product AirPulseHelper
swift build -c release --product AirPulse

BIN="$ROOT/.build/release"
APP="$ROOT/Products/AirPulse.app"
RELEASE_APP="$ROOT/Release/AirPulse.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

cp "$BIN/AirPulse" "$MACOS/AirPulse"
cp "$BIN/airpulse-cli" "$MACOS/airpulse-cli"
cp "$BIN/AirPulseHelper" "$MACOS/AirPulseHelper"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$RES/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>AirPulse</string>
  <key>CFBundleIdentifier</key>
  <string>com.bingtaohu.AirPulse</string>
  <key>CFBundleName</key>
  <string>AirPulse</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.5.3</string>
  <key>CFBundleVersion</key>
  <string>10</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper is less angry for local runs
codesign --force --deep --sign - "$APP" 2>/dev/null || true

mkdir -p "$ROOT/Release"
rm -rf "$RELEASE_APP"
cp -R "$APP" "$RELEASE_APP"

echo "==> Built $APP"
echo "    Release copy: $RELEASE_APP"
echo "    CLI: $MACOS/airpulse-cli"
echo "    Helper: $MACOS/AirPulseHelper"
echo ""
echo "Run: open \"$RELEASE_APP\""
echo "Probe: \"$RELEASE_APP/Contents/MacOS/airpulse-cli\" probe"
echo "Write probe: sudo \"$RELEASE_APP/Contents/MacOS/airpulse-cli\" probe --write"
