#!/bin/sh
# Builds build/Decanter.app. Set ARCHS="arm64 x86_64" for a universal build (needs full Xcode).
set -eu
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
ARCH_FLAGS=""
for a in ${ARCHS:-}; do ARCH_FLAGS="$ARCH_FLAGS --arch $a"; done

# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS
BIN="$(swift build -c release $ARCH_FLAGS --show-bin-path)/Decanter"

APP=build/Decanter.app
rm -rf "$APP" build/Decanter.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Decanter"
swift scripts/icon.swift build/Decanter.iconset
iconutil -c icns build/Decanter.iconset -o "$APP/Contents/Resources/Decanter.icns"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
# Ad-hoc signature: required to run on Apple Silicon. Not notarized (see README).
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"
