#!/bin/bash

# Cuts a Touchdown release: builds, notarizes, signs the update, publishes a
# GitHub release, and prepends the entry to appcast.xml.
#
#   ./release.sh "Release notes go here."
#   ./release.sh --dry-run "Notes"   # build, sign, render appcast; publish nothing
#
# Bump VERSION in version.sh first. Requires:
#   - Developer ID in the Keychain (for codesign)
#   - Sparkle EdDSA private key in the Keychain (from generate_keys)
#   - gh authenticated with repo scope
#   - optional: notarytool keychain profile named by NOTARY_PROFILE

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/version.sh"

DRY_RUN=0
NO_PUSH=0
while true; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        # Publish the release and commit the appcast, but leave the push to you.
        # Sparkle reads the feed from main, so an unpushed appcast means no
        # installed copy sees the update yet -- a review window, not a release.
        --no-push) NO_PUSH=1; shift ;;
        *) break ;;
    esac
done

NOTES="${1:-Maintenance release.}"
TAG="v$VERSION"
DIST="$SCRIPT_DIR/dist"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
APPCAST="$SCRIPT_DIR/appcast.xml"
SIGN_UPDATE="$SCRIPT_DIR/vendor/sparkle/bin/sign_update"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Releasing $APP_NAME $VERSION"
echo "╚════════════════════════════════════════════════════════════╝"

# Refuse to clobber a published tag: the appcast enclosure URL points at it,
# so overwriting would silently change what existing installs download.
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    echo "❌ Release $TAG already exists. Bump VERSION in version.sh."
    exit 1
fi

if [ $DRY_RUN -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
    echo "❌ Working tree is dirty. Commit before releasing."
    exit 1
fi

[ $DRY_RUN -eq 1 ] && echo "🧪 DRY RUN — nothing will be published"

rm -rf "$DIST"
mkdir -p "$DIST"

"$SCRIPT_DIR/build.sh" "$DIST"

# ditto -k --keepParent is the archiver Sparkle expects; zip(1) mangles the
# signed bundle's symlinks and the signature no longer validates.
echo "🗜️  Archiving..."
ditto -c -k --sequesterRsrc --keepParent "$DIST/$APP_NAME.app" "$ZIP"
echo "✅ $ZIP ($(du -h "$ZIP" | cut -f1))"

# Notarization is not optional for a Sparkle feed. Sparkle downloads the
# archive from the internet, so macOS quarantines it; Gatekeeper then rejects
# an unnotarized Developer ID app and the update fails to launch after install.
# Signed-but-unnotarized is enough to build and run locally, not to ship.
if [ -n "$NOTARY_PROFILE" ]; then
    echo "📤 Notarizing (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    # Staple the .app, then re-archive so the ticket ships inside the zip.
    xcrun stapler staple "$DIST/$APP_NAME.app"
    rm -f "$ZIP"
    ditto -c -k --sequesterRsrc --keepParent "$DIST/$APP_NAME.app" "$ZIP"
    xcrun stapler validate "$DIST/$APP_NAME.app"
    echo "✅ Notarized and stapled"
elif [ "$ALLOW_UNNOTARIZED" = "1" ] || [ $DRY_RUN -eq 1 ]; then
    echo "⚠️  Not notarized (NOTARY_PROFILE unset)."
    echo "   Gatekeeper will REJECT this on any machine that downloads it."
else
    echo "❌ NOTARY_PROFILE is unset, so this build cannot be notarized."
    echo ""
    echo "   Sparkle-delivered updates arrive quarantined. Gatekeeper rejects"
    echo "   unnotarized Developer ID apps, so the update would install and"
    echo "   then refuse to launch. Set up a notarytool profile once:"
    echo ""
    echo "     xcrun notarytool store-credentials touchdown-notary \\"
    echo "       --apple-id <your-apple-id> \\"
    echo "       --team-id 99L757HY7N \\"
    echo "       --password <app-specific-password>"
    echo ""
    echo "   Then: NOTARY_PROFILE=touchdown-notary ./release.sh \"notes\""
    echo "   To publish anyway (local testing only): ALLOW_UNNOTARIZED=1"
    exit 1
fi

# EdDSA signature over the archive. Sparkle refuses any update whose signature
# does not verify against SUPublicEDKey, which is what makes the feed safe to
# serve over a URL you do not fully control.
echo "🔑 Signing update..."
SIGN_ARGS=()
[ -n "$SPARKLE_KEY_ACCOUNT" ] && SIGN_ARGS+=(--account "$SPARKLE_KEY_ACCOUNT")
SIG_LINE="$("$SIGN_UPDATE" "${SIGN_ARGS[@]}" "$ZIP")"
echo "   $SIG_LINE"

ED_SIG="$(echo "$SIG_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(echo "$SIG_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"

if [ -z "$ED_SIG" ] || [ -z "$LENGTH" ]; then
    echo "❌ Could not parse sign_update output."
    exit 1
fi

DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$APP_NAME-$VERSION.zip"
PUB_DATE="$(date -R)"

if [ $DRY_RUN -eq 1 ]; then
    echo "🧪 would publish: gh release create $TAG $ZIP"
else
    echo "🚀 Publishing GitHub release $TAG..."
    gh release create "$TAG" "$ZIP" \
        -R "$REPO" \
        --title "$APP_NAME $VERSION" \
        --notes "$NOTES"
fi

# Prepend the new item so the newest release is first. Sparkle does not care
# about order, but a human reading the feed does.
echo "📝 Updating appcast..."
APPCAST_TARGET="$APPCAST"
if [ $DRY_RUN -eq 1 ]; then
    APPCAST_TARGET="$DIST/appcast-preview.xml"
    cp "$APPCAST" "$APPCAST_TARGET"
fi
python3 - "$APPCAST_TARGET" <<PY
import sys, re, pathlib

path = pathlib.Path(sys.argv[1])
item = """        <item>
            <title>$VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
            <description><![CDATA[$NOTES]]></description>
            <enclosure url="$DOWNLOAD_URL"
                       sparkle:edSignature="$ED_SIG"
                       length="$LENGTH"
                       type="application/octet-stream" />
        </item>
"""

text = path.read_text()
marker = "<!-- releases -->"
if marker not in text:
    sys.exit("appcast.xml missing the '<!-- releases -->' marker")
path.write_text(text.replace(marker, marker + "\n" + item.rstrip("\n"), 1))
print("   appcast.xml updated")
PY

if [ $DRY_RUN -eq 1 ]; then
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "🧪 DRY RUN complete — nothing published, appcast.xml untouched"
    echo "   Archive:  $ZIP"
    echo "   Preview:  $APPCAST_TARGET"
    echo ""
    echo "   Rendered appcast item:"
    echo "════════════════════════════════════════════════════════════"
    sed -n '/<item>/,/<\/item>/p' "$APPCAST_TARGET"
    exit 0
fi

git add "$APPCAST"
git commit -q -m "Publish $APP_NAME $VERSION"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ Released $APP_NAME $VERSION"
echo "   Release:  https://github.com/$REPO/releases/tag/$TAG"
echo "   Appcast:  $FEED_URL"
echo ""

if [ $NO_PUSH -eq 1 ]; then
    echo "⏸️  Appcast committed but NOT pushed (--no-push)."
    echo "   The download URL above is already public, but the feed is not,"
    echo "   so no installed copy will offer the update until you run:"
    echo "     git push origin main"
else
    git push origin main
    echo "   Installed copies pick this up within 24h, or immediately"
    echo "   via the menu bar → Check for Updates…"
fi
echo "════════════════════════════════════════════════════════════"
