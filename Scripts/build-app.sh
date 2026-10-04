#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Building AirPulse (release)"
# SwiftPM's default Swift Build engine links without SDKROOT, so clang stamps
# the deployment target (14.0) as the SDK version. AppKit / SwiftUI then run in
# macOS 14 compatibility mode (1.0.6 opened an empty Settings window at launch).
# Hand the link step the SDK explicitly; the check below catches regressions.
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
BUILD_FLAGS=(-c release -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK_PATH")
swift build "${BUILD_FLAGS[@]}" --product airpulse-cli
swift build "${BUILD_FLAGS[@]}" --product AirPulseHelper
swift build "${BUILD_FLAGS[@]}" --product AirPulse

BIN="$ROOT/.build/release"
APP="$ROOT/Products/AirPulse.app"
RELEASE_APP="$ROOT/Release/AirPulse.app"
MACOS="$APP/Contents/MacOS"
HELPERS="$APP/Contents/Helpers"
RES="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$HELPERS" "$RES"

cp "$BIN/AirPulse" "$MACOS/AirPulse"
cp "$BIN/airpulse-cli" "$MACOS/airpulse-cli"
cp "$BIN/AirPulseHelper" "$HELPERS/AirPulseHelper"

for bin in "$MACOS/AirPulse" "$MACOS/airpulse-cli" "$HELPERS/AirPulseHelper"; do
  linked="$(otool -l "$bin" | awk '/LC_BUILD_VERSION/ { found = 1 } found && $1 == "sdk" { print $2; exit }')"
  if [[ "$linked" != "$SDK_VERSION" ]]; then
    echo "error: $(basename "$bin") is stamped with SDK ${linked:-?}, expected $SDK_VERSION" >&2
    exit 1
  fi
done

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
  <string>1.0.7</string>
  <key>CFBundleVersion</key>
  <string>18</string>
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

# The repo copy lives under Documents, so Launchpad/Spotlight would otherwise
# list it as a second AirPulse next to /Applications/AirPulse.app.
touch "$ROOT/Release/.metadata_never_index"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$RELEASE_APP" >/dev/null 2>&1 || true
if [[ -d /Applications/AirPulse.app ]]; then
  "$LSREGISTER" -f /Applications/AirPulse.app >/dev/null 2>&1 || true
fi

echo "==> Built $APP"
echo "    Release copy: $RELEASE_APP"
echo "    CLI: $MACOS/airpulse-cli"
echo "    Helper: $HELPERS/AirPulseHelper"
echo ""
echo "Run: open \"$RELEASE_APP\""
echo "Probe: \"$RELEASE_APP/Contents/MacOS/airpulse-cli\" probe"
echo "Write probe: sudo \"$RELEASE_APP/Contents/MacOS/airpulse-cli\" probe --write"
