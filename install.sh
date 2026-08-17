#!/bin/bash

# Touchdown installer — Corsair Xeneon Edge touchscreen driver for macOS
#
# Builds via build.sh, installs to ~/Applications, registers a LaunchAgent.
# No sudo at any point.
#
# Why a bundle and not a bare binary in /usr/local/bin:
# macOS TCC will not register a raw Mach-O executable for Accessibility.
# A bare binary never appears in the Privacy & Security list at all, so the
# permission can never be granted and the driver can never inject clicks.
# Only a code-signed .app with a CFBundleIdentifier gets a TCC record.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/version.sh"

APP="$HOME/Applications/$APP_NAME.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="$BUNDLE_ID.plist"
EXEC_PATH="$APP/Contents/MacOS/$APP_NAME"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Touchdown — Xeneon Edge touch driver for macOS           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Stop the running copy before replacing the bundle on disk.
if launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "⏹️  Unloading existing LaunchAgent..."
    launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
fi
if pgrep -f "$APP_NAME" > /dev/null 2>&1; then
    echo "⏹️  Stopping existing driver..."
    pkill -f "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

# Build into a staging dir, then swap into place, so a failed compile leaves
# the working install untouched.
"$SCRIPT_DIR/build.sh" "$STAGE"

echo "📦 Installing to $APP..."
mkdir -p "$HOME/Applications"
rm -rf "$APP"
ditto "$STAGE/$APP_NAME.app" "$APP"

echo "📦 Installing LaunchAgent..."
mkdir -p "$LAUNCH_AGENTS_DIR"
cat > "$LAUNCH_AGENTS_DIR/$PLIST_NAME" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EXEC_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/touchdown.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/touchdown.log</string>
</dict>
</plist>
PLIST
echo "✅ LaunchAgent installed"

echo "🚀 Starting..."
rm -f /tmp/touchdown.log
launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ Installed $APP_NAME $VERSION. Starts automatically at login."
echo ""
echo "⚠️  Grant two permissions to $APP_NAME.app:"
echo "   → Privacy & Security → Accessibility"
echo "   → Privacy & Security → Input Monitoring"
echo ""
echo "   Developer ID signed, so these survive future updates."
echo "   You only do this once."
echo ""
echo "Commands:"
echo "  Stop:    launchctl unload ~/Library/LaunchAgents/$PLIST_NAME"
echo "  Start:   launchctl load ~/Library/LaunchAgents/$PLIST_NAME"
echo "  Status:  pgrep -f $APP_NAME && echo Running || echo Stopped"
echo "  Logs:    tail -f /tmp/touchdown.log"
echo "════════════════════════════════════════════════════════════"
