#!/bin/bash

# Touchdown installer — Corsair Xeneon Edge touchscreen driver for macOS
#
# Installs as a proper .app bundle in ~/Applications, with no sudo.
#
# Why a bundle and not a bare binary in /usr/local/bin:
# macOS TCC will not register a raw Mach-O executable for Accessibility.
# A bare binary never appears in the Privacy & Security list at all, so the
# permission can never be granted and the driver can never inject clicks.
# Only a code-signed .app with a CFBundleIdentifier gets a TCC record.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Touchdown"
BUNDLE_ID="com.bencolson.touchdown"
APP="$HOME/Applications/$APP_NAME.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="$BUNDLE_ID.plist"
EXEC_PATH="$APP/Contents/MacOS/$APP_NAME"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Touchdown — Xeneon Edge touch driver for macOS           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Stop anything already running, and unload before we overwrite the binary.
if launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "⏹️  Unloading existing LaunchAgent..."
    launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
fi
if pgrep -f "$APP_NAME" > /dev/null 2>&1; then
    echo "⏹️  Stopping existing driver..."
    pkill -f "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

echo "🔨 Compiling..."
cd "$SCRIPT_DIR"
swiftc TouchscreenDriver.swift -o "$APP_NAME" \
    -framework IOKit \
    -framework CoreFoundation \
    -framework CoreGraphics \
    -framework AppKit \
    -O
echo "✅ Compiled"

echo "📦 Building app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mv "$APP_NAME" "$EXEC_PATH"
chmod +x "$EXEC_PATH"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.4.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.4.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature is enough for TCC to keep a stable record, as long as the
# binary is not rebuilt. Rebuilding changes the cdhash and voids both grants.
codesign -s - --force --deep "$APP" >/dev/null 2>&1
echo "✅ Bundle built and signed: $APP"

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
echo "✅ Installed. Starts automatically at login."
echo ""
echo "⚠️  Grant two permissions to $APP_NAME.app now:"
echo "   → Privacy & Security → Accessibility"
echo "   → Privacy & Security → Input Monitoring"
echo ""
echo "   The driver waits for the grant and picks it up within 2s."
echo "   No restart needed."
echo ""
echo "Commands:"
echo "  Stop:    launchctl unload ~/Library/LaunchAgents/$PLIST_NAME"
echo "  Start:   launchctl load ~/Library/LaunchAgents/$PLIST_NAME"
echo "  Status:  pgrep -f $APP_NAME && echo Running || echo Stopped"
echo "  Logs:    tail -f /tmp/touchdown.log"
echo "════════════════════════════════════════════════════════════"
