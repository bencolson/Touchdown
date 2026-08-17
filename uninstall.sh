#!/bin/bash

# Touchdown uninstaller

APP_NAME="Touchdown"
BUNDLE_ID="com.bencolson.touchdown"
APP="$HOME/Applications/$APP_NAME.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="$BUNDLE_ID.plist"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Touchdown Uninstaller                                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

if [ -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME" ]; then
    echo "⏹️  Unloading LaunchAgent..."
    launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
    rm -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME"
    echo "✅ LaunchAgent removed"
fi

if pgrep -f "$APP_NAME" > /dev/null 2>&1; then
    echo "⏹️  Stopping driver..."
    pkill -f "$APP_NAME" 2>/dev/null || true
fi

if [ -d "$APP" ]; then
    echo "🗑️  Removing app bundle..."
    rm -rf "$APP"
    echo "✅ App removed"
fi

# Legacy layout from upstream: bare binary in /usr/local/bin.
if [ -f "/usr/local/bin/TouchscreenDriver" ]; then
    echo "🗑️  Removing legacy binary from /usr/local/bin (needs sudo)..."
    sudo rm -f "/usr/local/bin/TouchscreenDriver"
fi
rm -f "$HOME/.local/bin/TouchscreenDriver"

rm -f /tmp/touchdown.log /tmp/touchscreendriver.log

# Drop the TCC records so a later reinstall prompts cleanly.
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true

echo ""
echo "✅ Uninstallation complete."
