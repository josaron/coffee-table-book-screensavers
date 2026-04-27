#!/usr/bin/env bash
# Usage: ./scripts/download-theme.sh <theme-slug> <manifest.json>
#
# Reads the JSON produced by the image-sourcing AI prompt, downloads every
# image into themes/<theme>/images/, and writes themes/<theme>/config/theme.json.
# Scaffolds the Roku manifest from themes/sample/manifest if none exists yet.
set -euo pipefail

THEME=${1:?"Usage: $0 <theme-slug> <manifest.json>"}
MANIFEST=${2:?"Usage: $0 <theme-slug> <manifest.json>"}
THEME_DIR="themes/$THEME"

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: manifest not found: $MANIFEST" >&2
  exit 1
fi

if [ -d "$THEME_DIR/images" ] && [ "$(ls -A "$THEME_DIR/images" 2>/dev/null)" ]; then
  echo "Theme directory already has images: $THEME_DIR/images"
  read -rp "Overwrite? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

mkdir -p "$THEME_DIR/images" "$THEME_DIR/config"

# Download images + write theme.json via Python (always present on macOS)
python3 - "$MANIFEST" "$THEME_DIR" <<'PYEOF'
import json, sys, urllib.request, urllib.error, os, time

manifest_path, theme_dir = sys.argv[1], sys.argv[2]

with open(manifest_path) as f:
    manifest = json.load(f)

images   = manifest["images"]
success  = []
failures = []

for i, img in enumerate(images, 1):
    filename = img["filename"]
    url      = img["url"]
    dest     = os.path.join(theme_dir, "images", filename)
    print(f"[{i:02}/{len(images)}] {filename}", end="  ", flush=True)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as r, open(dest, "wb") as f:
            f.write(r.read())
        size_kb = os.path.getsize(dest) // 1024
        print(f"✓  {size_kb} KB")
        success.append(filename)
    except Exception as e:
        print(f"✗  {e}")
        failures.append({"filename": filename, "url": url, "error": str(e)})
    time.sleep(0.25)

theme_config = {
    "displayDuration":    manifest.get("displayDuration",    10),
    "transitionDuration": manifest.get("transitionDuration", 1.5),
    "shuffle":            manifest.get("shuffle",            True),
    "images":             success,
}
config_path = os.path.join(theme_dir, "config", "theme.json")
with open(config_path, "w") as f:
    json.dump(theme_config, f, indent=2)

print(f"\n{len(success)} downloaded, {len(failures)} failed → {config_path}")
if failures:
    fail_path = os.path.join(theme_dir, "failed_downloads.json")
    with open(fail_path, "w") as f:
        json.dump(failures, f, indent=2)
    print(f"Failed URLs logged to: {fail_path}")
PYEOF

# Scaffold Roku manifest from sample template if this theme doesn't have one yet
if [ ! -f "$THEME_DIR/manifest" ]; then
  DISPLAY_NAME=$(python3 -c \
    "import json; d=json.load(open('$MANIFEST')); print(d.get('displayName','$THEME'))")
  sed "s/Sample Screensaver/$DISPLAY_NAME/g" \
    themes/sample/manifest > "$THEME_DIR/manifest"
  echo "Scaffolded: $THEME_DIR/manifest"
fi

echo ""
echo "Next steps:"
echo "  1. Add icon + splash images to $THEME_DIR/images/  (sizes in manifest comments)"
echo "  2. make build THEME=$THEME"
echo "  3. make deploy THEME=$THEME ROKU_IP=<ip> ROKU_PASS=<password>"
