#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="/Applications"
APP_BUNDLE="$APP_DIR/Click2Chat.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
AGENT_DIR="$HOME/Library/LaunchAgents"
PLIST="$AGENT_DIR/com.dk.click2chat.plist"
BIN="$APP_MACOS/Click2Chat"
SUPPORT_DIR="$HOME/Library/Application Support/Click2Chat"
CONFIG="$SUPPORT_DIR/config.json"
ENV_FILE="$SUPPORT_DIR/.env"
CHROME_PROFILE="$SUPPORT_DIR/ChromeProfile"

cd "$ROOT_DIR"
swift build -c release

mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$AGENT_DIR" "$SUPPORT_DIR" "$CHROME_PROFILE"
cp "$ROOT_DIR/.build/release/Click2Chat" "$BIN"
cp "$ROOT_DIR/scripts/chrome_voice.mjs" "$APP_RESOURCES/chrome_voice.mjs"
cp "$ROOT_DIR/Assets/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$ROOT_DIR/.env.example" "$APP_RESOURCES/.env.example"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"
fi

cat > "$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Click2Chat</string>
  <key>CFBundleIdentifier</key>
  <string>com.dk.click2chat</string>
  <key>CFBundleName</key>
  <string>Click2Chat</string>
  <key>CFBundleDisplayName</key>
  <string>Click2Chat</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Click2Chat controls Google Chrome to start and stop ChatGPT Web voice conversations from the button.</string>
</dict>
</plist>
PLIST

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.dk.click2chat</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>Crashed</key>
    <true/>
  </dict>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/Click2Chat.launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/Click2Chat.launchd.err.log</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/com.dk.click2chat"

echo "Installed Click2Chat."
echo "App bundle: $APP_BUNDLE"
echo "Environment: $ENV_FILE"
if [[ -f "$CONFIG" ]]; then
  echo "Legacy config fallback detected: $CONFIG"
fi
echo "Set CLICK2CHAT_PROJECT_URL and device names in .env before relying on the button."
echo "Grant permissions when prompted: Accessibility, Input Monitoring, Automation for Google Chrome, and Microphone for Chrome."
