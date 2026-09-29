#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP_DIR="dist/Heartbeat.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$(swift build -c release --show-bin-path)/Heartbeat" "$APP_DIR/Contents/MacOS/Heartbeat"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/icon/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

# Ad-hoc sign the whole bundle so Info.plist (and its CFBundleIdentifier) is
# bound to the signature — without this, macOS won't reliably register the
# app with Notification Center under com.heartbeat.app.
codesign --force --deep -s - "$APP_DIR"

echo "Built $APP_DIR"
