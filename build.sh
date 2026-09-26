#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=build/blurrry.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Universal binary: Apple silicon + Intel.
for arch in arm64 x86_64; do
    swiftc -O -target $arch-apple-macos14 Sources/*.swift -o "build/blurrry-$arch"
done
lipo -create build/blurrry-arm64 build/blurrry-x86_64 -output "$APP/Contents/MacOS/blurrry"
rm build/blurrry-arm64 build/blurrry-x86_64
cp Resources/Info.plist "$APP/Contents/"
# Layered Icon Composer icon: macOS renders the window as a 3D glass object.
xcrun actool AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist /dev/null >/dev/null
xattr -cr "$APP"   # iCloud Drive tags files with metadata codesign rejects
codesign --force --sign - "$APP"
echo "Built $APP"
