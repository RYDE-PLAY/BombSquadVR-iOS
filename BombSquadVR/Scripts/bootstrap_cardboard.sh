#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$ROOT_DIR/ThirdParty"
CARDBOARD_DIR="$THIRD_PARTY_DIR/cardboard"
CARDBOARD_TAG="${CARDBOARD_TAG:-v1.34.0}"
# v1.34.0 currently resolves to this commit. Keeping the commit check makes a
# moved tag fail loudly instead of silently changing the native dependency.
CARDBOARD_COMMIT="${CARDBOARD_COMMIT:-4775db6e0a92fdc8bd102a818d741f2bde372876}"

mkdir -p "$THIRD_PARTY_DIR"

if [[ -d "$CARDBOARD_DIR/Cardboard.xcworkspace" ]]; then
  # A source snapshot may already be staged without its Git metadata.
  :
elif [[ -d "$CARDBOARD_DIR/.git" ]]; then
  git -C "$CARDBOARD_DIR" fetch --tags --depth 1 origin "$CARDBOARD_TAG"
  git -C "$CARDBOARD_DIR" checkout "$CARDBOARD_TAG"
else
  git clone --depth 1 --branch "$CARDBOARD_TAG" \
    https://github.com/googlevr/cardboard.git "$CARDBOARD_DIR"
fi

if [[ -d "$CARDBOARD_DIR/.git" ]]; then
  actual_commit="$(git -C "$CARDBOARD_DIR" rev-parse HEAD)"
  if [[ "$actual_commit" != "$CARDBOARD_COMMIT" ]]; then
    echo "Cardboard revision mismatch: expected $CARDBOARD_COMMIT, got $actual_commit" >&2
    exit 1
  fi
fi

cd "$CARDBOARD_DIR"
pod install

cat <<MSG
Cardboard SDK is ready at:
  $CARDBOARD_DIR

Open or build the official SDK workspace:
  $CARDBOARD_DIR/Cardboard.xcworkspace

Next integration step for BombSquadVR:
  add sdk/sdk.xcodeproj as a subproject and link the sdk target plus Pods_*.a.
MSG
