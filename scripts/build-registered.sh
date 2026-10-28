#!/bin/bash
# Builds Matchsight against its Wearables Developer Center project (voice
# launch: "Hey Meta, start Matchsight") instead of Developer Mode.
# The Application ID and Client Token live in the macOS Keychain, never git:
#   security add-generic-password -U -s copahud-meta-app-id -a matchsight -w <APP_ID>
#   security add-generic-password -U -s copahud-meta-client-token -a matchsight -w '<AR|...>'
set -euo pipefail
cd "$(dirname "$0")/.."
APP_ID=$(security find-generic-password -s copahud-meta-app-id -w)
TOKEN=$(security find-generic-password -s copahud-meta-client-token -w)
APP_LINK=${MATCHSIGHT_APP_LINK:-https://alienfader.com/matchsight}
xcodebuild -project CopaHUD.xcodeproj -scheme CopaHUD -configuration Debug \
  -destination "id=${DEVICE_ID:?set DEVICE_ID to the iPhone UDID from xcrun devicectl list devices}" \
  -allowProvisioningUpdates -skipPackagePluginValidation \
  META_APP_ID="$APP_ID" META_CLIENT_TOKEN="$TOKEN" META_APP_LINK="$APP_LINK" \
  MATCHSIGHT_ENTITLEMENTS=CopaHUD/CopaHUD-Registered.entitlements \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Matchsight-Registered" \
  build
echo "App: $HOME/Library/Developer/Xcode/DerivedData/Matchsight-Registered/Build/Products/Debug-iphoneos/CopaHUD.app"
