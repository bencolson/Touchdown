#!/bin/bash

# Downloads and verifies the Sparkle framework into vendor/.
# Kept out of git: the tarball is ~15 MB and reproducible from this script.

set -e

SPARKLE_VERSION="2.9.6"
SPARKLE_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR="$SCRIPT_DIR/vendor"
TARBALL="$VENDOR/Sparkle-$SPARKLE_VERSION.tar.xz"
FRAMEWORK="$VENDOR/sparkle/Sparkle.framework"

if [ -d "$FRAMEWORK" ]; then
    echo "✅ Sparkle $SPARKLE_VERSION already present"
    exit 0
fi

mkdir -p "$VENDOR"

if [ ! -f "$TARBALL" ]; then
    echo "⬇️  Downloading Sparkle $SPARKLE_VERSION..."
    curl -fsSL -o "$TARBALL" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
fi

# Pin the tarball hash: the build links this framework into a signed app, so a
# swapped upload must fail loudly rather than ship.
ACTUAL="$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)"
if [ "$ACTUAL" != "$SPARKLE_SHA256" ]; then
    echo "❌ SHA-256 mismatch for $TARBALL"
    echo "   expected: $SPARKLE_SHA256"
    echo "   actual:   $ACTUAL"
    exit 1
fi
echo "✅ SHA-256 verified"

mkdir -p "$VENDOR/sparkle"
tar -xJf "$TARBALL" -C "$VENDOR/sparkle"
echo "✅ Extracted to $VENDOR/sparkle"
