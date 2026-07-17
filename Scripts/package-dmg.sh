#!/usr/bin/env bash
#
# Builds a release Velo.app and packages it into a drag-to-install DMG.
#
#   Scripts/package-dmg.sh            # -> build/Velo.dmg
#
# Used by the release CI workflow and reproducible locally. The app is signed by
# build-app.sh (a stable local identity if you have one, otherwise ad-hoc — CI
# has no identity, so CI DMGs are ad-hoc-signed; users right-click ▸ Open once).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
DMG="$BUILD_DIR/Velo.dmg"

echo "==> Building release app bundle"
"$ROOT/Scripts/build-app.sh" release

echo "==> Staging DMG contents"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$BUILD_DIR/Velo.app" "$STAGE/Velo.app"
xattr -cr "$STAGE/Velo.app" 2>/dev/null || true
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
rm -f "$DMG"
hdiutil create -volname "Velo" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> Done: $DMG"
