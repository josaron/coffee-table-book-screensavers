# Image Sourcing Prompt — Coffee Table Book Screensavers

Paste the block below into ChatGPT, Claude, or Gemini.
Replace the bracketed placeholders before sending.

---

I am building a smart TV screensaver app that displays high-quality landscape images like a coffee table book on screen.

**Theme:** [DESCRIBE THEME — e.g., "Israel's natural beauty: deserts, valleys, coastlines, seas, and geological formations"]

Source **100 open-license images** from Wikimedia Commons that match this theme. Every image must meet all requirements below.

**Quality bar — this is the most important requirement:**
Each image must be stunning enough to appear in a high-end coffee table book. Think: dramatic light, vivid color, striking composition, a sense of awe. Reject anything flat, mundane, poorly composed, or technically mediocre — even if it depicts the right subject. A beautiful shot of an ordinary rock beats an ordinary shot of a famous landmark. If you cannot find 100 images that clear this bar, include fewer rather than pad with mediocre ones.

**Image requirements:**
- Landscape orientation (width > height), aspect ratio between 1.5:1 and 3:1
- Minimum 3840 × 2160 px (4K) preferred; absolute minimum 3000 px on the long edge
- Open license: CC BY, CC BY-SA, or Public Domain
- Real photographs only (no illustrations, maps, or diagrams)
- No humans in the frame — wildlife is welcome
- Scenery, nature, or landmarks only

**Caption format:** "Location Name · Region/Context" (e.g., "Makhtesh Ramon · Crater Floor, Negev")

**Branding image requirements (1 image):**
- A single iconic, instantly recognizable landmark or scene for this theme
- Used as the channel splash screen (1920×1080 crop) and icon — must look great tightly cropped to a 16:9 rectangle centered on the subject
- Same license and resolution requirements as above

---

Output **only** valid JSON, exactly this schema (no commentary before or after):

```json
{
  "theme": "kebab-case-slug",
  "displayName": "Human-Readable Theme Name",
  "displayDuration": 12,
  "transitionDuration": 1.5,
  "shuffle": true,
  "branding": {
    "splash": {
      "url": "https://upload.wikimedia.org/wikipedia/commons/…",
      "caption": "Landmark Name · Location",
      "attribution": "Photographer Name",
      "license": "CC BY-SA 4.0"
    }
  },
  "images": [
    {
      "filename": "001_descriptive_name.jpg",
      "url": "https://upload.wikimedia.org/wikipedia/commons/…",
      "width": 5472,
      "height": 3648,
      "caption": "Location Name · Region",
      "license": "CC BY-SA 4.0",
      "attribution": "Photographer Name",
      "source": "Wikimedia Commons"
    }
  ]
}
```

Rules for the `filename` field: lowercase, underscores only, zero-padded 3-digit sequence prefix (001_, 002_, …), descriptive of the subject.

Verify each URL is a real, directly downloadable Wikimedia Commons file URL (starts with `https://upload.wikimedia.org/wikipedia/commons/`). Do not invent filenames — use the actual Wikimedia filename.
