#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)

./scripts/build-app.sh

STAGING="dist/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R dist/Heartbeat.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG_PATH="dist/Heartbeat-${VERSION}.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "Heartbeat" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING"

echo "Built $DMG_PATH"
