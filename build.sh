#!/usr/bin/env bash
# Usage: ./build.sh <theme-name> [max-image-width]
#   Assembles framework + theme into a Roku-sideloadable ZIP at dist/<theme>.zip
#   max-image-width defaults to 1920 to fit Roku device storage limits.
#   Pass 3840 to build a full 4K ZIP (requires ~80MB device storage).
set -euo pipefail

THEME=${1:?"Usage: $0 <theme-name> [max-image-width]"}
MAX_WIDTH=${2:-1920}
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

# 3. Downscale images in staging area to fit within MAX_WIDTH × (MAX_WIDTH*9/16)
#    Two-pass: first cap the longest side, then cap height for non-16:9 images.
MAX_HEIGHT=$(( MAX_WIDTH * 9 / 16 ))
echo "Resizing images to max ${MAX_WIDTH}×${MAX_HEIGHT}px…"
for f in "$BUILD_DIR"/images/*.jpg; do
  sips -Z "$MAX_WIDTH" "$f" --out "$f" > /dev/null 2>&1
  h=$(sips -g pixelHeight "$f" 2>/dev/null | awk '/pixelHeight/{print $2}')
  [ -n "$h" ] && [ "$h" -gt "$MAX_HEIGHT" ] && sips -Z "$MAX_HEIGHT" "$f" --out "$f" > /dev/null 2>&1
done

# 4. Package: Roku expects a ZIP of the channel root contents (not a wrapper dir)
#    Exclude store-only assets (not part of the running channel)
rm -f "$OUTPUT"
(cd "$BUILD_DIR" && zip -r "../../$OUTPUT" . \
  -x "*.DS_Store" \
  -x "images/store_poster.jpg" \
  -x "images/store_screenshot.jpg")

echo "Built: $OUTPUT  ($(du -sh "$OUTPUT" | cut -f1))"
