#!/bin/bash
# Rebuild and reinstall Budgetma on a connected iPhone.
#
# Free personal-team signing expires after ~7 days, at which point the app
# stops launching. Run this to revive it.
#
# This REINSTALLS OVER the existing app, so your budget data survives.
# Never delete the app to "fix" signing -- that wipes the SwiftData store.
#
# Requires: phone connected (cable or paired over Wi-Fi), unlocked,
#           Developer Mode on.

set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Looking for a connected iPhone..."
# Match on the *model* column, not just "connected": a paired Apple Watch is a
# connected device too, and it sorts first, so `head -1` cheerfully handed the
# whole build an Apple Watch Ultra and then failed twice in a row explaining it
# badly. Model codes look like (iPhone17,1); nothing else does.
#
# "connected (no DDI)" means the developer disk image isn't mounted -- usually
# Developer Mode off, or the device hasn't been unlocked since it was plugged
# in. Such a device can't be built for or installed to, so it isn't a candidate.
DEVICES=$(xcrun devicectl list devices 2>/dev/null | grep -i "connected" || true)

DEVICE=$(echo "$DEVICES" \
  | grep -v "no DDI" \
  | grep -E '\(iPhone[0-9]+,[0-9]+\)' \
  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
  | head -1)

if [ -z "${DEVICE:-}" ]; then
  echo "No usable iPhone found."
  echo

  UNREADY=$(echo "$DEVICES" | grep -E '\(iPhone[0-9]+,[0-9]+\)' | grep "no DDI" || true)
  if [ -n "$UNREADY" ]; then
    echo "  An iPhone is connected but not ready to be developed on:"
    echo "$UNREADY" | sed 's/^/    /'
    echo
    echo "  Usually one of:"
    echo "    - Developer Mode is off"
    echo "      (Settings > Privacy & Security > Developer Mode, then reboot)"
    echo "    - the phone is locked -- unlock it and re-run"
  else
    echo "  - plug the phone in and unlock it"
    echo "  - check Developer Mode is on (Settings > Privacy & Security)"
  fi

  if [ -n "$DEVICES" ]; then
    echo
    echo "  Connected devices seen:"
    echo "$DEVICES" | sed 's/^/    /'
  fi
  exit 1
fi

echo "    device: $(echo "$DEVICES" | grep "$DEVICE" | sed 's/  */ /g' | cut -c1-60)"

# Release, not Debug: debug Swift is much slower, and the long-horizon
# projections are the part that feels it.
echo "==> Building (Release)..."
BUILD_LOG=$(mktemp -t budgetma-build)
trap 'rm -f "$BUILD_LOG"' EXIT

xcodebuild -project Budgetma.xcodeproj -scheme Budgetma -configuration Release \
  -destination "platform=iOS,id=$DEVICE" \
  -allowProvisioningUpdates build > "$BUILD_LOG" 2>&1 || true

grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" "$BUILD_LOG" || true

# A previous Release build is still sitting in DerivedData, so "did the product
# appear" is not the same question as "did this build succeed" -- getting those
# two confused installs a stale binary and reports success.
if ! grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
  echo
  echo "Build failed -- nothing was installed, the app on your phone is untouched."
  echo "Last few lines:"
  tail -15 "$BUILD_LOG" | sed 's/^/    /'
  exit 1
fi

APP=$(find ~/Library/Developer/Xcode/DerivedData/Budgetma-*/Build/Products/Release-iphoneos \
  -maxdepth 1 -name "Budgetma.app" 2>/dev/null | head -1)

if [ -z "${APP:-}" ]; then
  echo "Build succeeded but the product is missing -- check DerivedData."
  exit 1
fi

echo "==> Installing..."
xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1 | grep -E "App installed|bundleID|ERROR"

echo "==> Launching..."
xcrun devicectl device process launch --device "$DEVICE" the-kern.com.Budgetma 2>&1 \
  | grep -E "Launched application|ERROR|NSLocalizedFailureReason" || true

echo
echo "Done. If launch failed with 'profile has not been explicitly trusted',"
echo "trust the cert once on the phone:"
echo "  Settings > General > VPN & Device Management > Apple Development: ... > Trust"
