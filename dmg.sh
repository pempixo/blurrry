#!/bin/zsh
# Builds blurrry and packages it as a drag-to-Applications disk image in dist/.
set -e
cd "$(dirname "$0")"
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
STAGE=$(mktemp -d)
ditto --noextattr --norsrc build/blurrry.app "$STAGE/blurrry.app"   # leave sync-service metadata behind
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
DMG="dist/blurrry.dmg"
rm -f "$DMG"
hdiutil create -volname "blurrry" -srcfolder "$STAGE" -fs HFS+ -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
echo "Built $DMG"
shasum -a 256 "$DMG"
