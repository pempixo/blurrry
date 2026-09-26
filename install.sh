#!/bin/bash
# Installs the latest blurrry release into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/pempixo/blurrry/main/install.sh | bash
set -euo pipefail

REPO="pempixo/blurrry"
APP="/Applications/blurrry.app"

echo "→ Finding the latest blurrry release…"
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
[ -n "$URL" ] || { echo "Couldn't find a release DMG." >&2; exit 1; }

TMP=$(mktemp -d)
trap 'hdiutil detach -quiet "$TMP/mnt" 2>/dev/null || true; rm -rf "$TMP"' EXIT

echo "→ Downloading $(basename "$URL")…"
curl -fsSL -o "$TMP/blurrry.dmg" "$URL"

echo "→ Installing to /Applications…"
mkdir "$TMP/mnt"
hdiutil attach -quiet -nobrowse -mountpoint "$TMP/mnt" "$TMP/blurrry.dmg"
pkill -x blurrry 2>/dev/null || true
rm -rf "$APP"
ditto "$TMP/mnt/blurrry.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "→ Opening blurrry — look for its icon in the menu bar."
open "$APP"
