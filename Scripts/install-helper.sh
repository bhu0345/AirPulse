#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Products/AirPulse.app"
if [[ ! -x "$APP/Contents/Helpers/AirPulseHelper" ]]; then
  APP="$ROOT/Release/AirPulse.app"
fi
HELPER_SRC="$APP/Contents/Helpers/AirPulseHelper"
PLIST_DST="/Library/LaunchDaemons/com.bingtaohu.AirPulse.helper.plist"
LEGACY_DST="/usr/local/libexec/AirPulseHelper"

if [[ ! -x "$HELPER_SRC" ]]; then
  echo "请先运行 Scripts/build-app.sh"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "请使用: sudo Scripts/install-helper.sh"
  exit 1
fi

echo "==> Registering helper at $HELPER_SRC"
cat > "$PLIST_DST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.bingtaohu.AirPulse.helper</string>
  <key>ProgramArguments</key>
  <array>
    <string>$HELPER_SRC</string>
  </array>
  <key>MachServices</key>
  <dict>
    <key>com.bingtaohu.AirPulse.helper</key>
    <true/>
  </dict>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
</dict>
</plist>
PLIST

launchctl bootout system/com.bingtaohu.AirPulse.helper 2>/dev/null || true
rm -f "$LEGACY_DST"
launchctl bootstrap system "$PLIST_DST"
launchctl enable system/com.bingtaohu.AirPulse.helper
echo "==> Helper installed and loaded"
echo "    Uninstall: sudo Scripts/uninstall-helper.sh"
