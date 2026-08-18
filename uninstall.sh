#!/bin/bash

# Touchdown uninstaller

# Works standalone over curl as well as from a clone: an install done with
# install-release.sh has no repo to source version.sh from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/version.sh" ]; then
    source "$SCRIPT_DIR/version.sh"
else
    APP_NAME="Touchdown"
    BUNDLE_ID="com.bencolson.touchdown"
fi

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

# Sparkle's own state: update cache, and the per-bundle check-interval prefs.
rm -rf "$HOME/Library/Caches/$BUNDLE_ID" 2>/dev/null || true
rm -rf "$HOME/Library/Caches/org.sparkle-project.Sparkle/$BUNDLE_ID" 2>/dev/null || true
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true

# Legacy layouts from earlier versions and from upstream.
if [ -f "/usr/local/bin/TouchscreenDriver" ]; then
    echo "🗑️  Removing legacy binary from /usr/local/bin (needs sudo)..."
    sudo rm -f "/usr/local/bin/TouchscreenDriver"
fi
rm -f "$HOME/.local/bin/TouchscreenDriver"
rm -rf "$HOME/Applications/TouchscreenDriver.app"
rm -f "$LAUNCH_AGENTS_DIR/com.ymlaine.touchscreendriver.plist"

rm -f /tmp/touchdown.log /tmp/touchscreendriver.log

# Drop the TCC records so a later reinstall prompts cleanly.
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true

echo ""
echo "✅ Uninstallation complete."
echo ""
echo "Note: the Sparkle EdDSA private key remains in your Keychain as"
echo "\"Private key for signing Sparkle updates\". Keep it -- losing it means"
echo "existing installs can never verify another update."
