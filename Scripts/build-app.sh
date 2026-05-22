#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"

swift build \
  --configuration "$CONFIGURATION" \
  --product ObviousSaveMD \
  --package-path "$ROOT_DIR"

BIN_DIR="$(swift build \
  --configuration "$CONFIGURATION" \
  --show-bin-path \
  --package-path "$ROOT_DIR")"

APP_DIR="$BIN_DIR/ObviousSaveMD.app"
CONTENTS_DIR="$APP_DIR/Contents"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$BIN_DIR/ObviousSaveMD" "$CONTENTS_DIR/MacOS/ObviousSaveMD"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$CONTENTS_DIR/MacOS/ObviousSaveMD"

echo "$APP_DIR"
