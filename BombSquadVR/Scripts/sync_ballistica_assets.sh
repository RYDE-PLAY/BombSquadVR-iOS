#!/bin/sh
set -eu

APP_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$APP_ROOT"

# This may be overridden with a path relative to BombSquadVR or an absolute
# path. The default is the sibling checkout used by the Xcode project.
BALLISTICA_ROOT="${BALLISTICA_ROOT:-../ballistica}"
SOURCE_ASSETS="$BALLISTICA_ROOT/build/assets"
SOURCE_BUNDLE="$BALLISTICA_ROOT/.cache/asset_bundle/gui-minimal"
SOURCE_ASSETDATA="$BALLISTICA_ROOT/.cache/assetdata"
DEST="../BallisticaResources"

if [ ! -d "$SOURCE_ASSETS/ba_data" ] || [ ! -d "$SOURCE_ASSETS/pylib-apple" ]; then
  echo "Missing Ballistica build/assets output." >&2
  echo "Run: cd $BALLISTICA_ROOT && make assets-ios" >&2
  exit 1
fi

if [ ! -f "$SOURCE_BUNDLE/manifest.json" ] || [ ! -d "$SOURCE_ASSETDATA" ]; then
  echo "Missing Ballistica asset bundle output." >&2
  echo "Run: cd $BALLISTICA_ROOT && make assets-ios" >&2
  exit 1
fi

rm -rf \
  "$DEST/ba_data" \
  "$DEST/pylib" \
  "$DEST/pylib-apple" \
  "$DEST/asset_bundle" \
  "$DEST/assetdata"

rsync -a --delete "$SOURCE_ASSETS/ba_data/" "$DEST/ba_data/"
rsync -a --delete "$SOURCE_ASSETS/pylib-apple/" "$DEST/pylib-apple/"
rsync -a --delete "$SOURCE_ASSETS/pylib-apple/" "$DEST/pylib/"
rsync -a "$SOURCE_BUNDLE/manifest.json" "$DEST/ba_data/manifest.json"
rsync -a --delete "$SOURCE_ASSETDATA/" "$DEST/ba_data/assets/"

echo "Staged Ballistica resources in $DEST:"
du -sh "$DEST"
