#!/usr/bin/env bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.dk.click2chat.plist"

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -rf "/Applications/Click2Chat.app" "$HOME/Applications/Click2Chat.app" "$HOME/.local/bin/Click2Chat"

echo "Uninstalled Click2Chat."
