#!/bin/bash

# Installs the published Touchdown release. No Xcode, no repo, no signing
# identity -- unlike install.sh, which compiles from source and therefore needs
# the Developer ID cert that lives only on the build machine.
#
#   ./install-release.sh
#   curl -fsSL https://raw.githubusercontent.com/bencolson/Touchdown/main/install-release.sh | bash
#
#   ./install-release.sh --dry-run   # download and verify, install nothing
#
# Deliberately self-contained: it must run standalone over curl, so it cannot
# source version.sh and duplicates the few constants and the LaunchAgent plist
# that install.sh also writes. Keep the two in step.

set -euo pipefail

APP_NAME="Touchdown"
BUNDLE_ID="com.bencolson.touchdown"
REPO="bencolson/Touchdown"
TEAM_ID="99L757HY7N"
FEED_URL="https://raw.githubusercontent.com/$REPO/main/appcast.xml"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

APP="$HOME/Applications/$APP_NAME.app"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_NAME="$BUNDLE_ID.plist"
EXEC_PATH="$APP/Contents/MacOS/$APP_NAME"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Touchdown — installing the published release             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Read the same feed Sparkle reads, so a fresh install and an update always
# agree on what "current" means. release.sh prepends, so the first item is
# newest.
echo "📡 Reading $FEED_URL"
FEED="$(curl -fsSL "$FEED_URL")"
URL="$(printf '%s' "$FEED" | sed -n 's/.*enclosure url="\([^"]*\)".*/\1/p' | head -1)"
VERSION="$(printf '%s' "$FEED" | sed -n 's/.*<sparkle:shortVersionString>\([^<]*\)<.*/\1/p' | head -1)"

if [ -z "$URL" ]; then
    echo "❌ No release found in the appcast."
    echo "   If a release was just cut with --no-push, its feed entry is not"
    echo "   pushed yet. Check https://github.com/$REPO/releases"
    exit 1
fi

echo "⬇️  Downloading $APP_NAME ${VERSION:-?}"
echo "   $URL"
curl -fsSL -o "$STAGE/app.zip" "$URL"
ditto -x -k "$STAGE/app.zip" "$STAGE/x"

SRC="$STAGE/x/$APP_NAME.app"
[ -d "$SRC" ] || { echo "❌ Archive did not contain $APP_NAME.app"; exit 1; }

# Verify before trusting it. This runs on a machine with no signing identity
# and no Sparkle key, so the checks available are the ones macOS itself makes:
# an intact signature, the expected team, and a valid notarization.
echo "🔍 Verifying..."
codesign --verify --deep --strict "$SRC" || { echo "❌ Signature invalid."; exit 1; }
echo "   ✅ signature intact"

GOT_TEAM="$(codesign -dv "$SRC" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [ "$GOT_TEAM" != "$TEAM_ID" ]; then
    echo "❌ Wrong team: expected $TEAM_ID, got ${GOT_TEAM:-none}"
    exit 1
fi
echo "   ✅ team $TEAM_ID"

if ! spctl -a -t exec "$SRC" 2>/dev/null; then
    echo "❌ Gatekeeper rejected this build; it is not properly notarized."
    exit 1
fi
echo "   ✅ Gatekeeper accepted (notarized)"

if [ $DRY_RUN -eq 1 ]; then
    echo ""
    echo "🧪 DRY RUN — verified, installed nothing."
    exit 0
fi

# Stop the running copy before replacing the bundle on disk.
if launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "⏹️  Unloading existing LaunchAgent..."
    launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME" 2>/dev/null || true
fi
if pgrep -f "$APP_NAME" > /dev/null 2>&1; then
    pkill -f "$APP_NAME" 2>/dev/null || true
    sleep 1
fi

echo "📦 Installing to $APP..."
mkdir -p "$HOME/Applications"
rm -rf "$APP"
ditto "$SRC" "$APP"

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
echo "   Updates arrive automatically via Sparkle."
echo "════════════════════════════════════════════════════════════"
