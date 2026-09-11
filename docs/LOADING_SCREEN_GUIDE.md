# Loading Screen Conversion Guide

How to take any PNG image and convert it to a 5-bitplane 32-colour interleaved
Amiga raw image, then ZX0 compress it for use as the loading screen.

---

## Prerequisites

| Tool | Location | Purpose |
|------|----------|---------|
| Python 3 + Pillow | system | resize and quantise the PNG |
| `tools/amigeconv.exe` | project `tools/` | convert to Amiga bitplane format |
| `tools/zx0.exe` | project `tools/` | ZX0 compress the raw image |

Install Pillow if needed:
```
pip install pillow
```

---

## Target Format

The loading screen must be exactly:

| Property | Value |
|----------|-------|
| Width | 336 pixels |
| Height | 200 pixels |
| Bitplanes | 5 (interleaved) |
| Colours | 32 max |
| Raw size | 42,000 bytes (200 rows x 5 planes x 42 bytes/row) |
| Palette | 64 bytes (32 x 16-bit Amiga `$0RGB` halfwords, big-endian) |
| Compressed | ZX0 format → `template.zx0` |

---

## Step-by-Step

### Step 1 — Prepare your PNG

Start with any PNG. It can be any size and colour depth.
Recommended: design at 336x200 or proportionally similar (wider images will be scaled down).

Save your PNG somewhere in the project, e.g.:
```
loading_screen.png
```

---

### Step 2 — Resize to 336x200 and quantise to 32 colours

Run this Python script (save as `tools/convert_loading_screen.py` or paste into a terminal):

```python
from PIL import Image

# ---- CONFIG ----
INPUT_PNG  = "loading_screen.png"        # your source PNG
OUTPUT_PNG = "loading_screen_32col.png"  # palette-mode output for amigeconv
BG_COLOR   = (255, 255, 255)             # background fill colour (white)
W, H       = 336, 200                    # Amiga loading screen dimensions
# ----------------

src = Image.open(INPUT_PNG).convert("RGBA")

# Composite onto solid background (removes transparency)
bg = Image.new("RGB", src.size, BG_COLOR)
bg.paste(src, mask=src.split()[3])

# Resize: scale to fit width=336, centre vertically, pad with background
scale = W / src.width
new_h = round(src.height * scale)
resized = bg.resize((W, new_h), Image.LANCZOS)
canvas = Image.new("RGB", (W, H), BG_COLOR)
y_off = (H - new_h) // 2
canvas.paste(resized, (0, y_off))

# Quantise to 32 colours (5 bitplanes = 2^5 = 32 colour max)
# dither=NONE gives sharper pixel-art edges; use FLOYDSTEINBERG for photos
quantised = canvas.quantize(colors=32, method=Image.Quantize.MEDIANCUT,
                             dither=Image.Dither.NONE)
quantised.save(OUTPUT_PNG)
print(f"Saved: {OUTPUT_PNG}  ({len(set(quantised.getdata()))} colours used)")
```

Run it:
```
python tools/convert_loading_screen.py
```

> **Tip — too many near-identical colours?**
> If your image has a large flat background (e.g. white), quantisation wastes
> palette slots on near-identical shades. Pre-posterise the image in your art
> tool first, or manually reduce the source to fewer colours before quantising.

---

### Step 3 — Generate the 5-bitplane interleaved raw file

Use `amigeconv.exe` with the quantised palette PNG from Step 2:

```powershell
.\tools\amigeconv.exe -f bitplane -l -d 5 loading_screen_32col.png assets/graphics/title/template.raw
```

| Flag | Meaning |
|------|---------|
| `-f bitplane` | output raw bitplane data |
| `-l` | **interleaved** format (required — the loading code expects this) |
| `-d 5` | 5 bitplanes |

Output: `assets/graphics/title/template.raw` — exactly **42,000 bytes**.

Verify:
```powershell
(Get-Item "assets/graphics/title/template.raw").Length
# Expected: 42000
```

---

### Step 4 — Generate the 32-colour Amiga palette file

```powershell
.\tools\amigeconv.exe -f palette -p pal4 -c 32 loading_screen_32col.png assets/graphics/title/template.pal
```

| Flag | Meaning |
|------|---------|
| `-f palette` | output palette only |
| `-p pal4` | Amiga 12-bit `$0RGB` halfwords (big-endian), 2 bytes per entry |
| `-c 32` | 32 colour entries |

Output: `assets/graphics/title/template.pal` — exactly **64 bytes** (32 × 2 bytes).

Verify:
```powershell
(Get-Item "assets/graphics/title/template.pal").Length
# Expected: 64
```

> **Note:** `pal4` format matches what `loading.asm` expects: 32 consecutive
> `dc.w $0RGB` values loaded directly into Amiga colour registers 0–31 via
> the copper list.

---

### Step 5 — ZX0 compress the raw file

```powershell
# Remove old compressed file first (zx0.exe will not overwrite)
Remove-Item "assets/graphics/title/template.zx0" -ErrorAction SilentlyContinue

.\tools\zx0.exe assets/graphics/title/template.raw assets/graphics/title/template.zx0
```

Output: `assets/graphics/title/template.zx0` — compressed loading screen.

Example output:
```
ZX0 v2.2: Optimal data compressor by Einar Saukas
[...............................................]
File compressed from 42000 to NNNNN bytes! (delta 2)
```

The compressed size varies with the image content (simpler images compress better).

---

### Step 6 — Build and test

```powershell
.\build.ps1 -ToolDir <path-to-vasm>
```

The assembler includes `template.zx0` and `template.pal` via `main.asm`:
```asm
LoadingPal:   incbin "assets/graphics/title/template.pal"
LoadingRawZ:  incbin "assets/graphics/title/template.zx0"
```

The loading screen is decompressed at runtime by `LoadingSetup` in `loading.asm`
using the ZX0 decompressor (`zx0_faster.asm`), then revealed row-by-row with a
copper colour wash.

---

## Quick Reference — Full Pipeline

```powershell
# 1. Quantise
python tools/convert_loading_screen.py

# 2. Convert to 5-bitplane interleaved raw
.\tools\amigeconv.exe -f bitplane -l -d 5 loading_screen_32col.png assets/graphics/title/template.raw

# 3. Extract palette
.\tools\amigeconv.exe -f palette -p pal4 -c 32 loading_screen_32col.png assets/graphics/title/template.pal

# 4. ZX0 compress
Remove-Item assets/graphics/title/template.zx0 -ErrorAction SilentlyContinue
.\tools\zx0.exe assets/graphics/title/template.raw assets/graphics/title/template.zx0

# 5. Build
.\build.ps1 -ToolDir <path-to-vasm>
```

---

## Files Summary

| File | Size | Description |
|------|------|-------------|
| `loading_screen.png` | any | your source artwork |
| `loading_screen_32col.png` | varies | quantised to 32 colours (intermediate) |
| `assets/graphics/title/template.raw` | 42,000 bytes | 5-bitplane interleaved raw (intermediate) |
| `assets/graphics/title/template.pal` | 64 bytes | 32 Amiga colour halfwords — **incbin'd** |
| `assets/graphics/title/template.zx0` | varies | ZX0 compressed raw — **incbin'd** |

Only `template.pal` and `template.zx0` are referenced by the assembler.
`template.raw` and `loading_screen_32col.png` are intermediates and can be
regenerated at any time.