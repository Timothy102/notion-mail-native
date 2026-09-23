#!/bin/bash
# Demo-mode screenshots on an iOS Simulator, headless: boots a device with simctl and never opens Simulator.app.
# Usage: ios/scripts/snap.sh [out-dir] [screen ...]   (screens: see Launch in NMailApp.swift)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-build/snaps}
shift || true
SCREENS=${*:-inbox thread html compose search mailboxes accounts settings signin swipe empty}
NAME=NMail-iPhone
BUNDLE=com.timcvetko.nmail
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print(next((x['udid'] for v in d.values() for x in v if x['name']=='$NAME'), ''))")
if [ -z "$UDID" ]; then
  RUNTIME=$(xcrun simctl list runtimes -j | python3 -c "import json,sys; r=[x for x in json.load(sys.stdin)['runtimes'] if x['platform']=='iOS' and x['isAvailable']]; print(r[-1]['identifier'])")
  TYPE=$(xcrun simctl list devicetypes -j | python3 -c "import json,sys; t=[x['identifier'] for x in json.load(sys.stdin)['devicetypes'] if x['name'] in ('iPhone 17 Pro','iPhone 16 Pro')]; print(t[-1])")
  UDID=$(xcrun simctl create "$NAME" "$TYPE" "$RUNTIME")
fi
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null

xcodegen generate --quiet
xcodebuild build -project NMail.xcodeproj -scheme NMailPhone -configuration Debug -destination "id=$UDID" \
  -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO -quiet
xcrun simctl install "$UDID" build/dd/Build/Products/Debug-iphonesimulator/NMailPhone.app
# Skip the keyboard's one-time "slide to type" card.
xcrun simctl spawn "$UDID" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi

# The first launch after an install is slow; warm it up so every screenshot waits the same.
SIMCTL_CHILD_MAIL_DEMO=1 xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
sleep 6

for theme in light dark; do
  xcrun simctl ui "$UDID" appearance "$theme"
  for screen in $SCREENS; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    SIMCTL_CHILD_MAIL_DEMO=1 SIMCTL_CHILD_MAIL_SCREEN="$screen" xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
    sleep "${SNAP_DELAY:-6}"
    xcrun simctl io "$UDID" screenshot "$OUT/$screen-$theme.png" >/dev/null 2>&1
    echo "$OUT/$screen-$theme.png"
  done
done
