#!/bin/bash
# Sign with Developer ID and notarize for Gatekeeper-friendly distribution.
# Requires: Apple Developer Program, "Developer ID Application" identity,
# and a notarytool keychain profile (see docs/prerequisites.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/Release/AirPulse.app}"
PROFILE="${NOTARY_PROFILE:-AirPulse-notary}"

if [[ ! -d "$APP" ]]; then
  echo "error: app not found: $APP" >&2
  echo "Run Scripts/build-app.sh first." >&2
  exit 1
fi

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'\"' '/Developer ID Application/ {print $2; exit}')"
if [[ -z "${IDENTITY}" ]]; then
  cat >&2 <<'EOF'
error: no "Developer ID Application" signing identity found.

This Mac currently cannot notarize AirPulse. To enable Gatekeeper-friendly releases:
  1. Join the Apple Developer Program
  2. Create a Developer ID Application certificate in Xcode → Settings → Accounts
  3. Create a notarytool profile, e.g.:
       xcrun notarytool store-credentials AirPulse-notary \
         --apple-id YOU@email.com --team-id TEAMID --password app-specific-password
  4. Re-run: ./Scripts/sign-and-notarize.sh

Until then, Scripts/build-app.sh uses ad-hoc signing (local use / right-click Open).
EOF
  exit 1
fi

echo "==> Signing with: $IDENTITY"
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --verbose=2 "$APP"

ZIP="${TMPDIR:-/tmp}/AirPulse-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Submitting to notarytool (profile: $PROFILE)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute -vv "$APP" || true

echo "==> Done: $APP"
