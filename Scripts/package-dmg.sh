#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-0.1.0}"
APP="$ROOT/Release/AirPulse.app"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
VOLNAME="AirPulse"
DMG_NAME="AirPulse-${VERSION}.dmg"
DMG_PATH="$DIST/$DMG_NAME"

if [[ ! -d "$APP" ]]; then
  echo "==> App missing; building first"
  "$ROOT/Scripts/build-app.sh"
fi

echo "==> Packaging $DMG_NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP" "$STAGE/AirPulse.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

rm -rf "$STAGE"

echo "==> Created $DMG_PATH"
ls -lh "$DMG_PATH"
