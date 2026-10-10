#!/usr/bin/env bash
# Builds a release binary, wraps it into LP-700-App.app with the Info.plist
# template, embeds AppIcon.icns, optionally strips local symbols, and ad-hoc signs.
# Output: dist/LP-700-App.app
#
# Usage: VERSION=1.0.0 scripts/build-app.sh
#
# Env:
#   VERSION  Version string substituted into Info.plist (default 0.0.0-dev).
#   ARCHS    Space-separated list of slices. Default "arm64 x86_64" (universal,
#            what releases ship). "native" builds only this Mac's architecture:
#            half the compile time and half the binary. scripts/install-local.sh
#            uses "native" because a local install never runs anywhere else.
#   STRIP    0 (default) keeps the symbol table, so crash reports against a
#            release stay symbolicatable (no dSYM is archived anywhere). 1 runs
#            `strip -x` on the binary before signing, dropping local symbols
#            (roughly 55% smaller); scripts/install-local.sh sets this because a
#            local install is not something users send crash reports from.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/LP-700-App.app"
VERSION="${VERSION:-0.0.0-dev}"
ARCHS="${ARCHS:-arm64 x86_64}"
STRIP="${STRIP:-0}"

mkdir -p "$DIST"

# Translate ARCHS into `--arch` flags; "native" means no flag (host triple).
ARCH_FLAGS=()
if [ "$ARCHS" != "native" ]; then
    for a in $ARCHS; do ARCH_FLAGS+=(--arch "$a"); done
fi
# `${arr[@]+"${arr[@]}"}` is the bash 3.2 + `set -u` safe way to expand a
# possibly-empty array (/bin/bash on macOS is still 3.2).

echo "==> Building release binary ($ARCHS) — version $VERSION"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

BIN_PATH="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
BIN="$BIN_PATH/LP-700-App"
test -x "$BIN" || { echo "Binary not found at $BIN" >&2; exit 1; }

echo "==> Assembling .app bundle at $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/LP-700-App"
chmod +x "$APP/Contents/MacOS/LP-700-App"

if [ "$STRIP" = 1 ]; then
    echo "==> Stripping local symbols"
    strip -x "$APP/Contents/MacOS/LP-700-App"
fi

# Info.plist with version substitution.
sed "s/__VERSION__/${VERSION}/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"

# Icon (best-effort — falls back to no icon if generator fails).
if [ ! -f "$DIST/AppIcon.icns" ]; then
    if "$ROOT/scripts/make-icon.sh"; then
        :
    else
        echo "==> WARNING: AppIcon.icns generation failed, shipping without icon"
    fi
fi
if [ -f "$DIST/AppIcon.icns" ]; then
    cp "$DIST/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"

# Verify
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'
file "$APP/Contents/MacOS/LP-700-App" | sed 's/^/    /'
du -sh "$APP" | sed 's/^/    /'

echo "==> Built $APP"
