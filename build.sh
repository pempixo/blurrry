#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=build/blurrry.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macos14 Sources/*.swift -o "$APP/Contents/MacOS/blurrry"
cp Resources/Info.plist "$APP/Contents/"
# Layered Icon Composer icon: macOS renders the window as a 3D glass object.
xcrun actool AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist /dev/null >/dev/null
xattr -cr "$APP"   # iCloud Drive tags files with metadata codesign rejects
codesign --force --sign - "$APP"
echo "Built $APP"
