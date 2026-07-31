#!/bin/bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then
  echo "请使用: sudo Scripts/uninstall-helper.sh"
  exit 1
fi
launchctl bootout system/com.bingtaohu.AirPulse.helper 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.bingtaohu.AirPulse.helper.plist
rm -f /usr/local/libexec/AirPulseHelper
echo "==> Helper removed"
