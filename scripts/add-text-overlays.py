#!/usr/bin/env python3
"""
Add "<DisplayName> / Screensaver" text overlays to the icon and poster branding
assets of an already-downloaded theme.

Always regenerates icon/poster crops fresh from splash_hd.jpg so the source is
clean (no stale text from a prior run).

Usage:
    python3 scripts/add-text-overlays.py <theme-slug> "<Display Name>"

Example:
    python3 scripts/add-text-overlays.py historic-synagogues "Historic Synagogues"
    python3 scripts/add-text-overlays.py israel-natural-beauty "Israel Natural Beauty"
"""
import sys
import os
from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/HelveticaNeue.ttc"

# (filename, width, height, fmt)
ASSETS = [
    ("store_poster.jpg",  540,  405, "jpeg"),
    ("icon_focus_hd.png", 336,  210, "png"),
    ("icon_side_hd.png",  108,   69, "png"),
]


def center_crop(src: Image.Image, w: int, h: int) -> Image.Image:
    sw, sh = src.size
    scale  = max(w / sw, h / sh)
    nw, nh = max(w, int(sw * scale)), max(h, int(sh * scale))
    img    = src.resize((nw, nh), Image.LANCZOS)
    x      = (nw - w) // 2
    y      = (nh - h) // 2
    return img.crop((x, y, x + w, y + h))


def add_text_overlay(img: Image.Image, display_name: str) -> Image.Image:
    img = img.convert("RGBA")
    w, h = img.size

    # Start at 16% of height and shrink until the name fits in 90% of width
    sz1 = max(12, int(h * 0.16))
    max_tw = int(w * 0.90)

    def load_fonts(s1):
        try:
            f1 = ImageFont.truetype(FONT, s1,               index=1)
            f2 = ImageFont.truetype(FONT, max(8, int(s1 * 0.65)), index=0)
        except Exception:
            f1 = f2 = ImageFont.load_default()
        return f1, f2

    font1, font2 = load_fonts(sz1)
    probe = Image.new("RGBA", (1, 1))
    probe_draw = ImageDraw.Draw(probe)

    def text_wh(text, font):
        bb = probe_draw.textbbox((0, 0), text, font=font)
        return bb[2] - bb[0], bb[3] - bb[1]

    while sz1 > 8:
        tw1, _ = text_wh(display_name, font1)
        if tw1 <= max_tw:
            break
        sz1 -= 1
        font1, font2 = load_fonts(sz1)

    # Uniform semi-transparent dark overlay
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 140))
    img = Image.alpha_composite(img, overlay)

    draw = ImageDraw.Draw(img)

    tw1, th1 = text_wh(display_name,  font1)
    tw2, th2 = text_wh("Screensaver", font2)

    gap     = max(3, int(h * 0.03))
    block_h = th1 + gap + th2
    y1      = (h - block_h) // 2
    y2      = y1 + th1 + gap
    x1      = (w - tw1) // 2
    x2      = (w - tw2) // 2
    shad    = max(1, int(sz1 * 0.06))

    draw.text((x1 + shad, y1 + shad), display_name,  font=font1, fill=(0,   0,   0,   200))
    draw.text((x2 + shad, y2 + shad), "Screensaver", font=font2, fill=(0,   0,   0,   200))
    draw.text((x1, y1),               display_name,  font=font1, fill=(255, 255, 255, 255))
    draw.text((x2, y2),               "Screensaver", font=font2, fill=(210, 210, 210, 255))

    return img


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    theme_slug   = sys.argv[1]
    display_name = sys.argv[2]
    images_dir   = os.path.join("themes", theme_slug, "images")

    if not os.path.isdir(images_dir):
        print(f"ERROR: directory not found: {images_dir}")
        sys.exit(1)

    splash_path = os.path.join(images_dir, "splash_hd.jpg")
    if not os.path.exists(splash_path):
        print(f"ERROR: splash_hd.jpg not found in {images_dir}")
        sys.exit(1)

    splash = Image.open(splash_path)

    for filename, tw, th, fmt in ASSETS:
        dest = os.path.join(images_dir, filename)
        cropped = center_crop(splash, tw, th)
        result  = add_text_overlay(cropped, display_name)
        if fmt == "png":
            result.save(dest, "PNG")
        else:
            result.convert("RGB").save(dest, "JPEG", quality=92)
        size_kb = os.path.getsize(dest) // 1024
        print(f"  done  {filename}  ({tw}×{th}, {size_kb} KB)")


if __name__ == "__main__":
    main()
