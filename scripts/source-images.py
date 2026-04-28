#!/usr/bin/env python3
"""
Source high-quality landscape images from Wikimedia Commons for a screensaver theme.

Usage:
    python3 scripts/source-images.py <theme> <start_num> <output.json>

Where <theme> is one of: israel, synagogues, cathedrals
Or pass a comma-separated list of Wikimedia category names as a fourth argument
to source a custom theme:
    python3 scripts/source-images.py custom 1 out.json "Cat1,Cat2,Cat3"

The script:
  - Queries each Wikimedia Commons category for file listings
  - Fetches image metadata (URL, dimensions, license) in batches
  - Filters to landscape orientation, min 3000px long edge, open license
  - Caps at MAX_PER_PLACE (4) images per distinct place/landmark
  - Writes a JSON array of image entries ready for download-theme.sh
"""
import urllib.request, urllib.parse, json, time, sys, re

HEADERS = {"User-Agent": "CoffeeTableBookScreensavers/1.0 (joseph.aharon@gmail.com)"}
MAX_PER_PLACE = 4   # max images for any single place/landmark


# ---------------------------------------------------------------------------
# Wikimedia Commons API helpers
# ---------------------------------------------------------------------------

def api(params):
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def get_category_files(category, limit=100):
    files, cmcontinue = [], None
    while len(files) < limit:
        params = {
            "action": "query", "list": "categorymembers",
            "cmtitle": f"Category:{category}", "cmtype": "file",
            "cmlimit": 50, "format": "json",
        }
        if cmcontinue:
            params["cmcontinue"] = cmcontinue
        data = api(params)
        members = data.get("query", {}).get("categorymembers", [])
        files.extend(
            m["title"] for m in members
            if m["title"].lower().endswith((".jpg", ".jpeg"))
        )
        if "continue" in data:
            cmcontinue = data["continue"].get("cmcontinue")
        else:
            break
        time.sleep(0.3)
    return files[:limit]


def get_file_info(titles):
    params = {
        "action": "query", "titles": "|".join(titles),
        "prop": "imageinfo", "iiprop": "url|size|extmetadata",
        "format": "json",
    }
    data = api(params)
    results = {}
    for page in data.get("query", {}).get("pages", {}).values():
        title = page.get("title", "")
        info_list = page.get("imageinfo", [])
        if not info_list:
            continue
        info = info_list[0]
        meta = info.get("extmetadata", {})
        license_str = meta.get("LicenseShortName", {}).get("value", "")
        artist = re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value", "")).strip()
        results[title] = {
            "url":         info.get("url", ""),
            "width":       info.get("width", 0),
            "height":      info.get("height", 0),
            "license":     license_str,
            "attribution": artist[:80],
        }
    return results


def is_valid(info, min_long_edge=3000):
    w, h = info["width"], info["height"]
    if w <= h:
        return False
    if max(w, h) < min_long_edge:
        return False
    lic = info["license"].lower()
    if not any(x in lic for x in ["cc by", "cc0", "public domain", "pd "]):
        return False
    if "nd" in lic:   # no-derivatives not OK for redistribution
        return False
    return True


# ---------------------------------------------------------------------------
# Place deduplication
# ---------------------------------------------------------------------------

# Words that don't help identify a distinct place
_GENERIC = {
    "interior", "exterior", "nave", "apse", "facade", "view", "panorama",
    "detail", "ceiling", "dome", "tower", "altar", "window", "stained",
    "glass", "arch", "vault", "choir", "transept", "portal", "porch",
    "night", "aerial", "close", "wide", "photo", "image", "jpg", "jpeg",
    "file", "by", "the", "of", "in", "at", "a", "an", "and", "from",
    "landscape", "israel", "flickr", "wikimedia", "commons", "px",
}


def place_key(filename):
    """
    Extract a normalized place identifier from a Wikimedia filename.
    Takes the first 2–3 non-generic tokens as the place key so that
    e.g. 'Cologne_Cathedral_interior_1.jpg' and 'Cologne_Cathedral_nave.jpg'
    both map to 'cologne cathedral'.
    """
    base = filename.replace("File:", "").rsplit(".", 1)[0]
    # Split on underscores, spaces, hyphens; drop numbers and single chars
    tokens = [
        t.lower() for t in re.split(r"[\s_\-]+", base)
        if len(t) > 1 and not t.isdigit()
    ]
    significant = [t for t in tokens if t not in _GENERIC]
    # Use first 2 significant tokens (fall back to first 2 tokens if needed)
    key_tokens = significant[:2] if len(significant) >= 2 else tokens[:2]
    return " ".join(key_tokens)


# ---------------------------------------------------------------------------
# Collection
# ---------------------------------------------------------------------------

def collect(categories, target=120, min_long_edge=3000):
    seen_urls  = set()
    place_counts = {}   # place_key → count
    candidates = []

    for cat in categories:
        print(f"  Fetching Category:{cat}…", flush=True)
        try:
            files = get_category_files(cat, limit=100)
        except Exception as e:
            print(f"    Error: {e}")
            continue

        for i in range(0, len(files), 30):
            batch = files[i:i+30]
            try:
                infos = get_file_info(batch)
            except Exception as e:
                print(f"    Batch error: {e}")
                continue

            for title, info in infos.items():
                if not info["url"] or info["url"] in seen_urls:
                    continue
                if not is_valid(info, min_long_edge):
                    continue

                pk = place_key(title)
                if place_counts.get(pk, 0) >= MAX_PER_PLACE:
                    continue   # already have enough images of this place

                seen_urls.add(info["url"])
                place_counts[pk] = place_counts.get(pk, 0) + 1
                candidates.append({**info, "title": title})

            time.sleep(0.3)

            if len(candidates) >= target:
                break

        if len(candidates) >= target:
            break

    return candidates


# ---------------------------------------------------------------------------
# Built-in theme definitions
# ---------------------------------------------------------------------------

THEMES = {
    "israel": {
        "caption_suffix": "Israel",
        "categories": [
            "Landscapes_of_Israel", "Negev_Desert_landscapes",
            "Makhtesh_Ramon", "Dead_Sea", "Sea_of_Galilee",
            "Landscapes_of_the_Galilee", "Golan_Heights_landscapes",
            "Mediterranean_coast_of_Israel", "Judean_Desert",
            "Jezreel_Valley", "Jordan_Valley_(Israel)",
            "Landscapes_of_the_Negev", "Arava_valley",
            "Landscapes_of_the_Judean_Hills", "Landscapes_of_the_Carmel",
            "Red_Sea_coast_of_Israel", "Hula_valley",
        ],
    },
    "synagogues": {
        "caption_suffix": None,
        "categories": [
            "Interiors_of_synagogues_in_Hungary",
            "Interiors_of_synagogues_in_Czech_Republic",
            "Interiors_of_synagogues_in_Poland",
            "Interiors_of_synagogues_in_the_United_States",
            "Interiors_of_synagogues_in_Germany",
            "Interiors_of_synagogues_in_Austria",
            "Interiors_of_synagogues_in_Romania",
            "Interiors_of_synagogues_in_Italy",
            "Interiors_of_synagogues_in_France",
            "Interiors_of_synagogues_in_the_Netherlands",
            "Synagogues_in_Jerusalem",
            "Interiors_of_synagogues_in_Ukraine",
            "Interiors_of_synagogues_in_Russia",
        ],
    },
    "cathedrals": {
        "caption_suffix": None,
        "categories": [
            "Interiors_of_cathedrals_in_France",
            "Interiors_of_cathedrals_in_Germany",
            "Interiors_of_cathedrals_in_Spain",
            "Interiors_of_cathedrals_in_Italy",
            "Interiors_of_cathedrals_in_the_United_Kingdom",
            "Interiors_of_cathedrals_in_Belgium",
            "Interiors_of_cathedrals_in_the_Czech_Republic",
            "Interiors_of_cathedrals_in_Austria",
            "Interiors_of_cathedrals_in_Poland",
            "Notre-Dame_de_Paris_(interior)",
            "Interior_of_Cologne_Cathedral",
            "Interior_of_Sagrada_Família",
            "Interior_of_Saint_Peter's_Basilica",
            "Chartres_Cathedral_interior",
            "Canterbury_Cathedral_interior",
            "Exterior_of_Cologne_Cathedral",
            "Exterior_of_Sagrada_Família",
            "Cathedrals_in_France",
            "Cathedrals_in_Germany",
            "Interiors_of_churches_in_Austria",
            "Interiors_of_churches_in_Germany",
            "Interiors_of_churches_in_Italy",
            "Interiors_of_churches_in_Spain",
            "Interiors_of_churches_in_France",
        ],
    },
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)

    theme_name = sys.argv[1]
    start_num  = int(sys.argv[2])
    outfile    = sys.argv[3]

    if theme_name == "custom":
        if len(sys.argv) < 5:
            print("ERROR: pass comma-separated category names as 4th argument for custom theme")
            sys.exit(1)
        categories     = [c.strip() for c in sys.argv[4].split(",")]
        caption_suffix = None
    elif theme_name in THEMES:
        categories     = THEMES[theme_name]["categories"]
        caption_suffix = THEMES[theme_name]["caption_suffix"]
    else:
        print(f"ERROR: unknown theme '{theme_name}'. Use: {list(THEMES)} or 'custom'")
        sys.exit(1)

    print(f"Sourcing '{theme_name}' starting at {start_num:03d}  (max {MAX_PER_PLACE} per place)")
    candidates = collect(categories, target=120)
    print(f"Found {len(candidates)} valid candidates after place deduplication")

    entries = []
    for i, c in enumerate(candidates[:120]):
        num  = start_num + i
        name = re.sub(r"[^a-zA-Z0-9]+", "_",
                      c["title"].replace("File:", "").rsplit(".", 1)[0]).lower()[:50].strip("_")
        cap  = name.replace("_", " ").title()
        if caption_suffix:
            cap = f"{cap} · {caption_suffix}"
        entries.append({
            "filename":    f"{num:03d}_{name}.jpg",
            "url":         c["url"],
            "width":       c["width"],
            "height":      c["height"],
            "caption":     cap,
            "license":     c["license"],
            "attribution": c["attribution"],
            "source":      "Wikimedia Commons",
        })

    with open(outfile, "w") as f:
        json.dump(entries, f, indent=2)
    print(f"Wrote {len(entries)} entries → {outfile}")
