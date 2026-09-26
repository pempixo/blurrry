#!/bin/zsh
set -e
cd "$(dirname "$0")"
# Assemble and sign outside the project folder: sync services such as iCloud Drive tag files with
# metadata that codesign rejects.
STAGE=$(mktemp -d)
APP="$STAGE/blurrry.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Universal binary: Apple silicon + Intel.
for arch in arm64 x86_64; do
    swiftc -O -target $arch-apple-macos14 Sources/*.swift -o "$STAGE/blurrry-$arch"
done
lipo -create "$STAGE/blurrry-arm64" "$STAGE/blurrry-x86_64" -output "$APP/Contents/MacOS/blurrry"
cp Resources/Info.plist "$APP/Contents/"
# Layered Icon Composer icon: macOS renders the window as a 3D glass object.
xcrun actool AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon AppIcon --output-partial-info-plist /dev/null >/dev/null
codesign --force --sign - "$APP"
mkdir -p build
rm -rf build/blurrry.app
ditto "$APP" build/blurrry.app
rm -rf "$STAGE"
echo "Built build/blurrry.app"
