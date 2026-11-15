#!/bin/sh
# Packages build/Decanter.app into build/Decanter.dmg with an Applications shortcut.
set -eu
cd "$(dirname "$0")/.."
STAGE=build/dmg
rm -rf "$STAGE" build/Decanter.dmg
mkdir -p "$STAGE"
cp -R build/Decanter.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Decanter -srcfolder "$STAGE" -format UDZO -quiet build/Decanter.dmg
rm -rf "$STAGE"
echo "Built build/Decanter.dmg"
