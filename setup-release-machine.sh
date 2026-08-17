#!/bin/bash

# Prepares a machine to cut Touchdown releases.
#
# Run this on the build machine (the Mac mini), not on a client. It checks the
# prerequisites, fetches Sparkle, and generates the Sparkle signing key if this
# machine does not already have one.
#
# What has to be on the build machine, and what does not:
#
#   Developer ID certificate  -- REQUIRED, but does not need to be exported
#     from another Mac. The app's designated requirement is
#       identifier "..." and anchor apple generic and certificate leaf[subject.OU] = "<TEAM>"
#     which pins the *team*, not a specific certificate. Any Developer ID
#     Application cert issued to the same team satisfies it, so TCC grants on
#     already-installed copies survive. Create a fresh one in Xcode:
#       Settings → Accounts → Manage Certificates → + → Developer ID Application
#     (Apple caps how many you may hold; revoke an unused one if you hit it.)
#
#   Sparkle EdDSA key         -- REQUIRED, and it is the one thing that cannot
#     be reissued once you have published. Its public half is baked into the
#     Info.plist of every copy already installed, and Sparkle rejects any
#     update whose signature does not match. Before the first release you can
#     freely generate a new one here; afterwards you must migrate the original.
#
#   notarytool credentials    -- re-create locally, nothing to migrate.
#   gh auth                   -- re-run `gh auth login`, nothing to migrate.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/version.sh"

TEAM_ID="99L757HY7N"
FAIL=0

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Touchdown — release machine setup                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Machine: $(hostname) — macOS $(sw_vers -productVersion) $(uname -m)"
echo ""

echo "── Xcode command line tools ─────────────────────────────────"
if xcode-select -p >/dev/null 2>&1; then
    echo "✅ $(xcode-select -p)"
    echo "   $(swift --version 2>&1 | head -1)"
else
    echo "❌ missing — run: xcode-select --install"
    FAIL=1
fi

echo ""
echo "── Developer ID Application certificate ─────────────────────"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application.*$TEAM_ID"; then
    security find-identity -v -p codesigning | grep "Developer ID Application.*$TEAM_ID" | sed 's/^/✅ /'
else
    echo "❌ no Developer ID Application cert for team $TEAM_ID"
    echo "   Xcode → Settings → Accounts → Manage Certificates → +"
    echo "   A NEW cert is fine; the designated requirement pins the team, not the cert."
    FAIL=1
fi

echo ""
echo "── GitHub CLI ──────────────────────────────────────────────"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "✅ $(gh auth status 2>&1 | grep -o 'account [^ ]*' | head -1)"
else
    echo "❌ not authenticated — run: gh auth login"
    FAIL=1
fi

echo ""
echo "── notarytool credentials ──────────────────────────────────"
if security find-generic-password -s "com.apple.gke.notary.tool" >/dev/null 2>&1 \
   || xcrun notarytool history --keychain-profile "touchdown-notary" >/dev/null 2>&1; then
    echo "✅ a notarytool profile is present"
else
    echo "⚠️  no notarytool profile found. Releases will refuse to publish."
    echo "   xcrun notarytool store-credentials touchdown-notary \\"
    echo "     --apple-id <your-apple-id> \\"
    echo "     --team-id $TEAM_ID \\"
    echo "     --password <app-specific-password>"
    echo "   App-specific password: appleid.apple.com → Sign-In and Security"
fi

echo ""
echo "── Sparkle framework ───────────────────────────────────────"
"$SCRIPT_DIR/fetch-sparkle.sh"

echo ""
echo "── Sparkle EdDSA signing key ───────────────────────────────"
# generate_keys prints the existing public key when a key is already present,
# and creates one when it is not. Either way we compare against version.sh.
KEY_OUTPUT="$("$SCRIPT_DIR/vendor/sparkle/bin/generate_keys" 2>&1 || true)"
LOCAL_KEY="$(echo "$KEY_OUTPUT" | grep -o '<string>[^<]*</string>' | sed 's/<[^>]*>//g' | head -1)"

if [ -z "$LOCAL_KEY" ]; then
    echo "⚠️  Could not read a public key from generate_keys. Raw output:"
    echo "$KEY_OUTPUT" | sed 's/^/   /'
elif [ "$LOCAL_KEY" = "$PUBLIC_ED_KEY" ]; then
    echo "✅ this machine holds the key matching version.sh"
    echo "   $LOCAL_KEY"
else
    echo "⚠️  this machine's key does NOT match version.sh"
    echo "   version.sh:    $PUBLIC_ED_KEY"
    echo "   this machine:  $LOCAL_KEY"
    echo ""
    echo "   If nothing has been released yet, adopt this machine's key:"
    echo "     update PUBLIC_ED_KEY in version.sh to the value above, commit,"
    echo "     then reinstall on every client once so the new public key is embedded."
    echo ""
    echo "   If releases already exist, do NOT adopt it. Export the original"
    echo "   from the machine that has it and import it here:"
    echo "     old machine:  vendor/sparkle/bin/generate_keys -x sparkle-key.txt"
    echo "     this machine: vendor/sparkle/bin/generate_keys -f sparkle-key.txt"
    echo "     then shred the file: rm -P sparkle-key.txt"
fi

echo ""
echo "── Build check ─────────────────────────────────────────────"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
if "$SCRIPT_DIR/build.sh" "$STAGE" >/dev/null 2>&1; then
    echo "✅ builds and signs cleanly"
    codesign -d --requirements - "$STAGE/$APP_NAME.app" 2>&1 | tail -1 | sed 's/^/   /'
else
    echo "❌ build failed — run ./build.sh /tmp/x to see why"
    FAIL=1
fi

echo ""
echo "════════════════════════════════════════════════════════════"
if [ $FAIL -eq 0 ]; then
    echo "✅ This machine can cut releases."
    echo "   NOTARY_PROFILE=touchdown-notary ./release.sh --dry-run \"notes\""
else
    echo "❌ Resolve the items marked above first."
fi
echo "════════════════════════════════════════════════════════════"
