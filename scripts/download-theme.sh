#!/usr/bin/env bash
# Usage: ./scripts/download-theme.sh <theme-slug> <manifest.json>
#
# Reads the JSON produced by the image-sourcing AI prompt, downloads every
# image into themes/<theme>/images/, and writes themes/<theme>/config/theme.json.
# Also generates Roku branding assets (splash + icons) from manifest["branding"]["splash"].
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
import json, sys, urllib.request, urllib.error, os, re, time, subprocess, tempfile

manifest_path, theme_dir = sys.argv[1], sys.argv[2]

with open(manifest_path) as f:
    manifest = json.load(f)

TARGET_WIDTH  = 3840   # slideshow images
BRANDING_WIDTH = 5000  # branding source — needs enough height for 1080px crop

def wikimedia_thumbnail_url(url, width=TARGET_WIDTH):
    """
    Convert a Wikimedia Commons full-res URL to a thumbnail URL.
    Full-res: https://upload.wikimedia.org/wikipedia/commons/a/ab/File.jpg
    Thumb:    https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/File.jpg/3840px-File.jpg
    Returns original URL unchanged if it doesn't match the pattern.
    """
    m = re.match(
        r'(https://upload\.wikimedia\.org/wikipedia/commons/)([a-f0-9]/[a-f0-9]{2}/)(.*)',
        url
    )
    if not m:
        return url
    base, path, fname = m.group(1), m.group(2), m.group(3)
    return f"{base}thumb/{path}{fname}/{width}px-{fname}"

def fetch_with_retry(url, dest, retries=3):
    headers = {
        "User-Agent": "CoffeeTableBookScreensavers/1.0 (https://github.com/josaron/coffee-table-book-screensavers)"
    }
    delay = 5
    for attempt in range(1, retries + 1):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=60) as r, open(dest, "wb") as f:
                f.write(r.read())
            return True
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries:
                print(f"  rate-limited, waiting {delay}s…", end=" ", flush=True)
                time.sleep(delay)
                delay *= 2
            else:
                raise
    return False

def sips_dimensions(path):
    out = subprocess.check_output(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", path]
    ).decode()
    lines = out.splitlines()
    w = int(next(l for l in lines if "pixelWidth"  in l).split()[-1])
    h = int(next(l for l in lines if "pixelHeight" in l).split()[-1])
    return w, h

def make_branding_asset(source, dest, width, height, fmt="jpeg"):
    """Center-crop-resize source image to width×height and save as fmt."""
    src_w, src_h = sips_dimensions(source)

    # Scale so the image covers the target (no letterboxing)
    scale = max(width / src_w, height / src_h)
    scaled_w = max(width,  int(src_w * scale))
    scaled_h = max(height, int(src_h * scale))

    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tf:
        tmp = tf.name
    try:
        # Step 1: resize to scaled dimensions
        subprocess.run(
            ["sips", "-z", str(scaled_h), str(scaled_w), source, "--out", tmp],
            check=True, capture_output=True
        )
        # Step 2: center crop to exact target size
        crop_x = (scaled_w - width)  // 2
        crop_y = (scaled_h - height) // 2
        subprocess.run(
            ["sips", "--cropToHeightWidth", str(height), str(width),
             "--cropOffset", str(crop_y), str(crop_x), tmp, "--out", dest],
            check=True, capture_output=True
        )
        # Step 3: convert to PNG if needed
        if fmt == "png":
            subprocess.run(
                ["sips", "-s", "format", "png", dest, "--out", dest],
                check=True, capture_output=True
            )
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

# ── Slideshow images ──────────────────────────────────────────────────────────

images   = manifest["images"]
success  = []
failures = []

for i, img in enumerate(images, 1):
    filename  = img["filename"]
    raw_url   = img["url"]
    thumb_url = wikimedia_thumbnail_url(raw_url)
    dest      = os.path.join(theme_dir, "images", filename)
    print(f"[{i:02}/{len(images)}] {filename}", end="  ", flush=True)
    try:
        fetch_with_retry(thumb_url, dest)
        size_kb = os.path.getsize(dest) // 1024
        print(f"✓  {size_kb} KB")
        success.append({"filename": filename, "caption": img.get("caption", "")})
    except Exception as e:
        print(f"✗  {e}")
        failures.append({"filename": filename, "url": thumb_url, "error": str(e)})
    time.sleep(2)  # be polite to Wikimedia servers

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

# ── Branding assets ───────────────────────────────────────────────────────────

branding = manifest.get("branding", {})
splash   = branding.get("splash", {})
splash_url = splash.get("url", "")

if not splash_url:
    print("\nNo branding.splash.url in manifest — skipping branding assets.")
else:
    print(f"\nGenerating branding assets from: {splash_url}")
    images_dir = os.path.join(theme_dir, "images")

    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tf:
        raw_source = tf.name
    try:
        thumb_url = wikimedia_thumbnail_url(splash_url, width=BRANDING_WIDTH)
        print(f"  Downloading branding source…", end="  ", flush=True)
        fetch_with_retry(thumb_url, raw_source)
        src_kb = os.path.getsize(raw_source) // 1024
        print(f"✓  {src_kb} KB")

        assets = [
            ("splash_hd.jpg",      1920, 1080, "jpeg"),
            ("icon_focus_hd.png",   336,  210, "png"),
            ("icon_side_hd.png",    108,   69, "png"),
        ]
        for filename, w, h, fmt in assets:
            dest = os.path.join(images_dir, filename)
            make_branding_asset(raw_source, dest, w, h, fmt)
            size_kb = os.path.getsize(dest) // 1024
            print(f"  {filename}: {w}×{h}  ({size_kb} KB)")
    except Exception as e:
        print(f"  ✗ Branding generation failed: {e}")
    finally:
        if os.path.exists(raw_source):
            os.unlink(raw_source)

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
echo "  1. make build THEME=$THEME"
echo "  2. make deploy THEME=$THEME ROKU_IP=<ip> ROKU_PASS=<password>"
