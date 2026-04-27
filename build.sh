#!/usr/bin/env bash
# Usage: ./build.sh <theme-name>
#   Assembles framework + theme into a Roku-sideloadable ZIP at dist/<theme>.zip
set -euo pipefail

THEME=${1:?"Usage: $0 <theme-name>"}
THEME_DIR="themes/$THEME"
BUILD_DIR="build/$THEME"
OUTPUT="dist/${THEME}.zip"

if [ ! -d "$THEME_DIR" ]; then
  echo "ERROR: theme not found at $THEME_DIR" >&2
  exit 1
fi

echo "Building theme: $THEME"

# Clean and recreate build staging area
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" dist

# 1. Copy framework (source + components)
cp -r framework/source     "$BUILD_DIR/source"
cp -r framework/components "$BUILD_DIR/components"

# 2. Overlay theme files (manifest, images, config)
cp    "$THEME_DIR/manifest"  "$BUILD_DIR/manifest"
cp -r "$THEME_DIR/images"    "$BUILD_DIR/images"
cp -r "$THEME_DIR/config"    "$BUILD_DIR/config"

# 3. Package: Roku expects a ZIP of the channel root contents (not a wrapper dir)
rm -f "$OUTPUT"
(cd "$BUILD_DIR" && zip -r "../../$OUTPUT" . -x "*.DS_Store")

echo "Built: $OUTPUT  ($(du -sh "$OUTPUT" | cut -f1))"
