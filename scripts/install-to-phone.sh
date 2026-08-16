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

echo "==> Looking for a connected device..."
# match the UDID by shape, not by column position: both the Name and Model
# columns contain spaces, so counting fields picks up the wrong token
DEVICE=$(xcrun devicectl list devices 2>/dev/null \
  | grep -i "connected" \
  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' \
  | head -1)

if [ -z "${DEVICE:-}" ]; then
  echo "No connected device found."
  echo "  - plug the phone in and unlock it"
  echo "  - check Developer Mode is on (Settings > Privacy & Security)"
  exit 1
fi
echo "    device: $DEVICE"

# Release, not Debug: debug Swift is much slower, and the long-horizon
# projections are the part that feels it.
echo "==> Building (Release)..."
xcodebuild -project Budgetma.xcodeproj -scheme Budgetma -configuration Release \
  -destination "platform=iOS,id=$DEVICE" \
  -allowProvisioningUpdates build 2>&1 \
  | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED" || true

APP=$(find ~/Library/Developer/Xcode/DerivedData/Budgetma-*/Build/Products/Release-iphoneos \
  -maxdepth 1 -name "Budgetma.app" 2>/dev/null | head -1)

if [ -z "${APP:-}" ]; then
  echo "Build product not found -- the build probably failed above."
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
