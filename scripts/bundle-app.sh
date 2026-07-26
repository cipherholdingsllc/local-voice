#!/bin/bash
set -euo pipefail

BINARY="${1:-.build/release/local-voice}"
APP_DIR="${2:-Local Voice.app}"
VERSION="${3:-0.51.0}"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/local-voice"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cp "$REPO_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$REPO_DIR/scripts/parakeet_daemon.py" "$APP_DIR/Contents/Resources/parakeet_daemon.py"

cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>local-voice</string>
    <key>CFBundleIdentifier</key>
    <string>com.cipherholdings.localvoice</string>
    <key>CFBundleName</key>
    <string>Local Voice</string>
    <key>CFBundleDisplayName</key>
    <string>Local Voice</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Local Voice uses the microphone only while you dictate and transcribes speech on this Mac.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier com.cipherholdings.localvoice "$APP_DIR"

echo "Built $APP_DIR"
