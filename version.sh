#!/bin/bash
# Single source of truth for release metadata. Sourced by build/install/release.
# Bump VERSION here; release.sh refuses to publish a tag that already exists.

APP_NAME="Touchdown"
BUNDLE_ID="com.bencolson.touchdown"
VERSION="1.5.0"

REPO="bencolson/Touchdown"

# The appcast Sparkle polls. Served from the repo so there is no Pages setup;
# raw.githubusercontent caches for ~5 minutes, which is fine for a daily check.
FEED_URL="https://raw.githubusercontent.com/$REPO/main/appcast.xml"

# Keychain account holding this app's Sparkle private key.
#
# Sparkle's own advice is that one key can serve every app you ship. That holds
# when all of them are equally trusted -- but this repo and its release pipeline
# are public, so a key shared with a private or commercial app would let a leak
# here forge updates there. Scoping to a named account keeps Touchdown's key
# distinct from any other Sparkle key on the build machine.
#
# Set empty to use the machine's default (unscoped) key instead.
SPARKLE_KEY_ACCOUNT="touchdown"

# EdDSA public key for the account above. Its private half stays in the
# Keychain and is never committed. Create it with:
#   vendor/sparkle/bin/generate_keys --account touchdown
PUBLIC_ED_KEY="Nc9tzLbpRRNpULi6oXdq9bhFSSe4C3aE9Cg3yBpKmaI="
