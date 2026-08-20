#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="${SCHEME:-Commando}"
CONFIGURATION="${CONFIGURATION:-Release}"
NOTARY_PROFILE="${NOTARY_PROFILE:-Commando-Notary}"
TEAM_ID="${TEAM_ID:-5D3622Q6DB}"

BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Commando.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Commando.app"
DMG_STAGE="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/Commando.dmg"
EXPORT_OPTIONS="$ROOT/ExportOptions-DeveloperID.plist"

echo "==> Cleaning previous build artifacts"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving $SCHEME ($CONFIGURATION)"
xcodebuild \
  -project "$ROOT/Commando.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo "==> Exporting Developer ID signed app"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

echo "==> Creating DMG with Applications shortcut"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
ditto "$APP_PATH" "$DMG_STAGE/Commando.app"
ln -s /Applications "$DMG_STAGE/Applications"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Commando" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Submitting DMG for notarization (profile: $NOTARY_PROFILE)"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler staple "$APP_PATH"

echo "==> Verifying notarization"
xcrun stapler validate "$DMG_PATH"
spctl -a -vv "$APP_PATH"

echo ""
echo "Done."
echo "  App: $APP_PATH"
echo "  DMG: $DMG_PATH"
echo "  Team ID: $TEAM_ID"
