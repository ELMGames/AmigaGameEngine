#!/usr/bin/env python3
"""
tools/generate_animals.py
-------------------------
Generates cute 16x16 animated rescue animals (Rabbit, Puppy, Kitten, Duckling)
with 4-frame jumping / waiting-for-rescue animations for the Amiga OCS/ECS engine.

Outputs:
  - assets/graphics/animals/animals_16x16.png (64x64 master spritesheet: 4 frames x 4 animals)
  - assets/graphics/animals/animals_preview.png (magnified 8x preview with annotations)
  - assets/graphics/animals/animals_64x64.raw (2,048 bytes: 4-bitplane interleaved Amiga BOB data)
  - assets/graphics/animals/animals_64x64.msk (2,048 bytes: 1-bit blitter mask)
  - assets/graphics/animals/rabbit_anim.gif
  - assets/graphics/animals/puppy_anim.gif
  - assets/graphics/animals/kitten_anim.gif
  - assets/graphics/animals/duckling_anim.gif
"""

from pathlib import Path
from PIL import Image, ImageDraw

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_ROOT / "assets" / "graphics" / "animals"

# 16-color OCS playfield palette (matches FourSeasons tileset & player BOB)
PALETTE_OCS = [
    (0, 0, 0),       # 0: Transparent ($0000)
    (1, 11, 14),     # 1: 0x1BE Vibrant Cyan
    (3, 3, 2),       # 2: 0x332 Dark Charcoal outline (X)
    (15, 15, 15),    # 3: 0xFFF Pure White (W) - fur, highlights, eye catchlights
    (2, 7, 4),       # 4: 0x274 Forest Green (K)
    (1, 9, 3),       # 5: 0x193 Grass Green (G)
    (15, 9, 1),      # 6: 0xF91 Vibrant Orange (O) - duck bill/feet, tabby stripes
    (2, 5, 12),      # 7: 0x25C Deep Blue (D)
    (15, 12, 2),     # 8: 0xFC2 Vibrant Gold / Yellow (Y) - duckling, puppy, kitten
    (13, 10, 6),     # 9: 0xDA6 Warm Sand / Cream (C) - shading, snout
    (11, 7, 4),      # 10: 0xB74 Warm Earth Brown (B) - puppy floppy ears
    (8, 1, 3),       # 11: 0x813 Rich Maroon (M) - mouth interior, deep shadow
    (13, 1, 2),      # 12: 0xD12 Vibrant Red (R) - puppy collar, tongue
    (8, 9, 11),      # 13: 0x89B Slate Grey (S) - soft shadow
    (1, 7, 7),       # 14: 0x177 Vibrant Teal (T)
    (12, 10, 8),     # 15: 0xCA8 Peach / Pink (P) - inner ears, blush cheeks, nose
]

# 8-bit RGB representation
PAL_8BIT = [(r * 17, g * 17, b * 17) for r, g, b in PALETTE_OCS]

# Flat 768-byte palette table for mode 'P' GIF generation
PAL_FLAT = []
for r, g, b in PAL_8BIT:
    PAL_FLAT.extend([r, g, b])
PAL_FLAT.extend([0] * (768 - len(PAL_FLAT)))

# ASCII legend to palette indices
LEGEND = {
    '.': 0,   # Transparent
    'X': 2,   # Charcoal outline
    'W': 3,   # Pure White
    'O': 6,   # Vibrant Orange
    'Y': 8,   # Vibrant Gold / Yellow
    'C': 9,   # Warm Sand / Cream
    'B': 10,  # Earth Brown
    'M': 11,  # Maroon
    'R': 12,  # Vibrant Red
    'S': 13,  # Slate Grey
    'T': 14,  # Vibrant Teal
    'P': 15,  # Peach / Pink
}

# ==============================================================================
# 1. RABBIT / BUNNY (16x16)
# Pure white fur, tall pink-centered ears, big sparkling dark eyes,
# pink cheeks & nose, paws held to chest, round cotton tail puff.
# ==============================================================================
RABBIT = [
    # F0: Stand (Waiting, tall ears, front paws held up begging, cotton tail perked)
    [
        "...XX.....XX....",
        "..XPPX...XPPX...",
        "..XPPX...XPPX...",
        "..XPPX...XPPX...",
        "..XWWX...XWWX...",
        "...XXXXXXXXXX...",
        "..XWWWWWWWWWWX..",
        ".XWWWWWWWWWWWWX.",
        ".XWWXWWWWXWWWWX.",
        ".XWXXWWWWXXWWWX.",
        ".XPWWWWPWWWWPWX.",
        "..XWWWXWXWWWWX..",
        "..XWWWWWWWWWWXX.",
        ".XWW.XWWX.WWWWXX",
        ".XWW.XXXX.WWWWXX",
        "..XX......XXXX..",
    ],
    # F1: Crouch (Wind-up squash, ears angle back, body squashed 1px, paws tuck)
    [
        "................",
        "....XX.....XX...",
        "...XPPX...XPPX..",
        "...XPPX...XPPX..",
        "....XXXXXXXX....",
        "...XWWWWWWWWX...",
        "..XWWWWWWWWWWX..",
        ".XWWWWWWWWWWWWX.",
        ".XWWXWWWWXWWWWX.",
        ".XWXXWWWWXXWWWX.",
        ".XPWWWWPWWWWPWX.",
        ".XWWWWXWXWWWWXX.",
        "XWWWWWWWWWWWWWWX",
        "XWWW.XXXX.WWWWXX",
        ".XWWWWWWWWWWWWXX",
        "..XXXXXXXXXXXX..",
    ],
    # F2: Apex Jump (Airborne 4px! Ears spread joyfully, paws forward, feet kick down!)
    [
        "..XX.......XX...",
        ".XPPX.....XPPX..",
        ".XPPX.....XPPX..",
        "..XX.XXXXX.XX...",
        "...XWWWWWWWWX...",
        "..XWWWWWWWWWWX..",
        ".XWWWWWWWWWWWWX.",
        ".XWWXWWWWXWWWWX.",
        ".XWXXWWWWXXWWWX.",
        ".XPWWWWPWWWWPWX.",
        "..XWWWXWXWWWWX..",
        "..XWWWWWWWWWWXX.",
        "..XWWXWWXWWWWXX.",
        "..XWW....WWWW.XX",
        "...XX....XXXX...",
        "................",
    ],
    # F3: Land (Touchdown, feet meet ground, ears swing forward, soft rebound)
    [
        "................",
        "...XX.....XX....",
        "..XPPX...XPPX...",
        "..XPPX...XPPX...",
        "..XWWX...XWWX...",
        "...XXXXXXXXXX...",
        "..XWWWWWWWWWWX..",
        ".XWWWWWWWWWWWWX.",
        ".XWWXWWWWXWWWWX.",
        ".XWXXWWWWXXWWWX.",
        ".XPWWWWPWWWWPWX.",
        "..XWWWXWXWWWWX..",
        "..XWWWWWWWWWWXX.",
        ".XWW.XXXX.WWWWXX",
        ".XWW.WWWW.WWWWXX",
        "..XX......XXXX..",
    ],
]

# ==============================================================================
# 2. PUPPY (16x16)
# Golden retriever pup, floppy brown ears, sweet dark eyes with catchlight,
# cute white muzzle with charcoal nose & red tongue (:P), red collar, wagging tail!
# ==============================================================================
PUPPY = [
    # F0: Stand (Waiting, perked floppy ears, wagging tail, cute panting tongue)
    [
        "...XXXXXX.......",
        "..XBBXXBBX......",
        ".XBBBXXBBBX.XX..",
        ".XBBBYYYBBXXYYX.",
        ".XBYXWYYXWYXYYX.",
        ".XBYXXYYXXYYXYX.",
        "..XYYWWWWYYXXX..",
        "..XYWXXWWYX.....",
        "...XWWRWWX......",
        "...XRRRRRX......",
        "..XYYYYYYYX.....",
        ".XYYYYYYYYYX....",
        ".XYYXWWXYYWX....",
        ".XYYXWWXYYWX....",
        "..XX.XX..XX.....",
        "................",
    ],
    # F1: Crouch (Playful crouch bow, tail vibrating up, ears forward)
    [
        "................",
        "....XXXXXX......",
        "...XBBXXBBX.XX..",
        "..XBBBXXBBXXYYX.",
        "..XBYXWYYXWYXYX.",
        "..XBYXXYYXXYYX..",
        "...XYYWWWWYYX...",
        "...XYWXXWWYX....",
        "....XWWRWWX.....",
        "...XRRRRRRX.....",
        "..XYYYYYYYYX....",
        ".XYYYYYYYYYYX...",
        "XYYYXWWXYYWYYX..",
        "XYYYXWWXYYWYYX..",
        ".XXX.XX..XX.XX..",
        "................",
    ],
    # F2: Apex Jump (Airborne 4px! Ears fly wide, front paws pawing, happy pant!)
    [
        ".XX........XX...",
        "XBBX.XXXX.XBBX..",
        "XBBBX.YY.XBBBX..",
        ".XBBXYYYYXBBX...",
        "..XYXWYYXWYX.XX.",
        "..XYXXYYXXYX.XYX",
        "...YYWWWWYYXXYYX",
        "...YWXXWWYXYYYX.",
        "....WWRWWXXXX...",
        "...XRRRRRX......",
        "..XYYYYYYYX.....",
        ".XYXWWXYYWX.....",
        "..XX..XX.XX.....",
        "................",
        "................",
        "................",
    ],
    # F3: Land (Paws touch down, tail sweeps, ears settling)
    [
        "................",
        "...XXXXXX.......",
        "..XBBXXBBX......",
        ".XBBBXXBBBX.XX..",
        ".XBBBYYYBBXXYYX.",
        ".XBYXWYYXWYXYYX.",
        ".XBYXXYYXXYYXXX.",
        "..XYYWWWWYYX....",
        "..XYWXXWWYX.....",
        "...XWWRWWX......",
        "...XRRRRRX......",
        "..XYYYYYYYX.....",
        ".XYYYYYYYYYX....",
        ".XYYXWWXYYWX....",
        "..XX.XX..XX.....",
        "................",
    ],
]

# ==============================================================================
# 3. KITTEN (16x16)
# Ginger tabby, pointed triangle ears with pink inside, big sparkling eyes,
# cute white bib & mittens, orange tabby stripes, curled tail!
# ==============================================================================
KITTEN = [
    # F0: Stand (Alert, big eyes, white bib, tail curled up)
    [
        "...XX......XX...",
        "..XPPX....XPPX..",
        ".XPPYX....XYPPX.",
        ".XYYYYYYYYYYYYX.",
        "XYYOYYYYYYYYOYX.",
        "XYYXWYYYYYYXWYX.",
        "XYYXXYYYYYYXXYX.",
        "XYYYYWWPWWYYYYX.",
        ".XYYYWWWWWYYYX..",
        "..XYYWWWWWYYX.XX",
        "..XYOYYYYYOYYXOX",
        ".XYYYYYYYYYYYXOX",
        ".XYYYYYYYYYYYXXX",
        ".XWWXX...XXWWX..",
        "..XX.......XX...",
        "................",
    ],
    # F1: Crouch (Playful butt-wiggle crouch, ears back, ready to pounce)
    [
        "................",
        "....XX....XX....",
        "...XPPX..XPPX...",
        "..XPPYX..XYPPX..",
        ".XYYYYYYYYYYYYX.",
        "XYYOYYYYYYYYOYX.",
        "XYYXWYYYYYYXWYX.",
        "XYYXXYYYYYYXXYX.",
        "XYYYYWWPWWYYYYX.",
        ".XYYYWWWWWYYYX..",
        "..XYYWWWWWYYX.XX",
        ".XYOYYYYYOYYXXOX",
        "XYYYYYYYYYYYYXOX",
        "XYYYYYYYYYYYYXXX",
        ".XWWXXXXXXXWWX..",
        "..XX.......XX...",
    ],
    # F2: Apex Jump (High leap! Star-pounce with white mittens spread, tail straight up!)
    [
        "...............X",
        "...XX......XX.XO",
        "..XPPX....XPPXXO",
        ".XPPYX....XYPPXO",
        ".XYYYYYYYYYYYXXO",
        "XYYOYYYYYYYYOYXX",
        "XYYXWYYYYYYXWYX.",
        "XYYXXYYYYYYXXYX.",
        ".XYYYWWPWWYYYX..",
        "XXYYYWWWWWYYXX..",
        "XWWXYYYYYYYXWWX.",
        ".XX.XYYYYYX.XX..",
        "....XYYYYYX.....",
        "...XWWX.XWWX....",
        "....XX...XX.....",
        "................",
    ],
    # F3: Land (Soft landing on white paws, tail curves down)
    [
        "................",
        "...XX......XX...",
        "..XPPX....XPPX..",
        ".XPPYX....XYPPX.",
        ".XYYYYYYYYYYYYX.",
        "XYYOYYYYYYYYOYX.",
        "XYYXWYYYYYYXWYX.",
        "XYYXXYYYYYYXXYX.",
        "XYYYYWWPWWYYYYX.",
        ".XYYYWWWWWYYYX..",
        "..XYYWWWWWYYX...",
        ".XYOYYYYYOYYX.XX",
        ".XYYYYYYYYYYYXOX",
        ".XYYYYYYYYYYYXOX",
        ".XWWXX...XXWWXXX",
        "..XX.......XX...",
    ],
]

# ==============================================================================
# 4. DUCKLING (16x16)
# Chubby yellow duckling, perked tuft, shiny dark eye with catchlight,
# cute rounded orange bill, flappy winglet, orange webbed feet!
# ==============================================================================
DUCKLING = [
    # F0: Stand (Waiting, wing at side, cute perked stance)
    [
        ".....XX.........",
        "....XYYX........",
        "...XYYYYX.......",
        "..XYYXWYYX......",
        "..XYYXXYYXOOX...",
        "..XYYYYYYYOOOX..",
        "...XYYYYYYOOX...",
        "....XXXXXX......",
        "...XYYYYYYX.....",
        "..XYYXYYYYYX....",
        "..XYYXYYYYYYX...",
        ".XYYYXYYYYYYX...",
        ".XYYYYYYYYYYX...",
        "..XYYYYYYYYX....",
        "...XOOXXOOX.....",
        "...XXXX.XX......",
    ],
    # F1: Crouch (Squashes down, bill tilted up, wing tucked)
    [
        "................",
        ".....XX.........",
        "....XYYX........",
        "...XYYYYX.......",
        "..XYYXWYYX......",
        "..XYYXXYYXOOX...",
        "..XYYYYYYYOOOX..",
        "...XYYYYYYOOX...",
        "..XYYYYYYYX.....",
        ".XYYYXYYYYYX....",
        ".XYYYXYYYYYYX...",
        "XYYYYYYYYYYYYX..",
        ".XYYYYYYYYYYX...",
        "..XYYYYYYYYX....",
        "...XOOXXOOX.....",
        "...XXXX.XX......",
    ],
    # F2: Apex Jump (Airborne 4px! Wings flap wide, feet tucked up!)
    [
        ".....XX.........",
        "....XYYX........",
        "...XYYYYX.......",
        "..XYYXWYYX......",
        "..XYYXXYYXOOX...",
        "..XYYYYYYYOOOX..",
        ".XXYYYYYYYOOX...",
        "XYYXYYYYYYXXXX..",
        "XYYXYYYYYYYXYYX.",
        ".XYYYYYYYYYXYYX.",
        "..XYYYYYYYYXXXX.",
        "...XYYYYYYX.....",
        "....XOOXOOX.....",
        "....XXXXXX......",
        "................",
        "................",
    ],
    # F3: Land (Touchdown, feet meet ground, wings folding)
    [
        "................",
        ".....XX.........",
        "....XYYX........",
        "...XYYYYX.......",
        "..XYYXWYYX......",
        "..XYYXXYYXOOX...",
        "..XYYYYYYYOOOX..",
        "...XYYYYYYOOX...",
        "...XYYYYYYX.....",
        "..XYYXYYYYYX....",
        "..XYYXYYYYYYX...",
        ".XYYYXYYYYYYX...",
        ".XYYYYYYYYYYX...",
        "..XYYYYYYYYX....",
        "...XOOXXOOX.....",
        "...XXXX.XX......",
    ],
]

ALL_ANIMALS = [
    ("rabbit", "Rabbit / Bunny", RABBIT),
    ("puppy", "Puppy", PUPPY),
    ("kitten", "Kitten", KITTEN),
    ("duckling", "Duckling", DUCKLING),
]


def generate_all():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # 1. 64x64 master spritesheet
    sheet = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    for row_idx, (_, _, frames) in enumerate(ALL_ANIMALS):
        for col_idx, frame in enumerate(frames):
            fx = col_idx * 16
            fy = row_idx * 16
            for y, line in enumerate(frame):
                for x, char in enumerate(line):
                    idx = LEGEND.get(char, 0)
                    if idx > 0:
                        r, g, b = PAL_8BIT[idx]
                        sheet.putpixel((fx + x, fy + y), (r, g, b, 255))
    sheet_path = OUT_DIR / "animals_16x16.png"
    sheet.save(sheet_path)
    print(f"[*] Saved spritesheet: {sheet_path}")

    # 2. Magnified 8x preview sheet with labels
    scale = 8
    w, h = 64 * scale, 64 * scale
    left_m, top_m = 140, 36
    preview = Image.new("RGBA", (left_m + w + 20, top_m + h + 20), (28, 30, 42, 255))
    draw = ImageDraw.Draw(preview)

    scaled_sheet = sheet.resize((w, h), Image.Resampling.NEAREST)
    preview.paste(scaled_sheet, (left_m, top_m), scaled_sheet)

    # Grid
    for i in range(5):
        gx = left_m + i * 16 * scale
        draw.line([(gx, top_m), (gx, top_m + h)], fill=(70, 75, 95, 200), width=1)
        gy = top_m + i * 16 * scale
        draw.line([(left_m, gy), (left_m + w, gy)], fill=(70, 75, 95, 200), width=1)

    # Column headers
    headers = ["F0: Stand", "F1: Crouch", "F2: Apex Jump", "F3: Land"]
    for i, title in enumerate(headers):
        draw.text((left_m + i * 16 * scale + 34, 12), title, fill=(220, 230, 245, 255))

    # Row labels
    for row_idx, (_, title, _) in enumerate(ALL_ANIMALS):
        ry = top_m + row_idx * 16 * scale + 8 * scale - 6
        draw.text((12, ry), title, fill=(255, 215, 80, 255))

    preview_path = OUT_DIR / "animals_preview.png"
    preview.save(preview_path)
    print(f"[*] Saved preview: {preview_path}")

    # 3. Individual animated GIFs using mode 'P' with exact OCS palette
    # Scaled to 96x96 (6x nearest-neighbor)
    for name, title, frames in ALL_ANIMALS:
        gif_frames = []
        for frame in frames:
            im = Image.new("P", (16, 16), 0)
            im.putpalette(PAL_FLAT)
            for y, line in enumerate(frame):
                for x, char in enumerate(line):
                    idx = LEGEND.get(char, 0)
                    im.putpixel((x, y), idx)
            # Scale 6x preserving palette indices
            im_scaled = im.resize((96, 96), Image.Resampling.NEAREST)
            gif_frames.append(im_scaled)

        # Durations: 180ms stand, 120ms crouch, 260ms apex jump, 120ms land
        durations = [180, 120, 260, 120]
        gif_p = OUT_DIR / f"{name}_anim.gif"
        gif_frames[0].save(
            gif_p,
            save_all=True,
            append_images=gif_frames[1:],
            duration=durations,
            loop=0,
            disposal=2,
            transparency=0,
        )
        print(f"[*] Saved animated GIF: {gif_p}")

    # 4. Amiga 4-bitplane interleaved raw graphics & mask files (2,048 bytes each)
    # Layout:
    #   64 scanlines total (4 animal rows x 16 scanlines)
    #   64 pixels wide (4 frames x 16 pixels = 4 words = 8 bytes per plane)
    #   Plane 0 (8B), Plane 1 (8B), Plane 2 (8B), Plane 3 (8B) = 32 bytes/scanline
    #   Total size: 64 * 32 = 2,048 bytes.
    pixels = sheet.load()
    row_bytes = 64 // 8
    raw_bytes = bytearray()
    msk_bytes = bytearray()

    for y in range(64):
        for plane in range(4):
            line = bytearray(row_bytes)
            mask = bytearray(row_bytes)
            for x in range(64):
                r, g, b, a = pixels[x, y]
                if a > 128:
                    pal_idx = 0
                    for idx, (pr, pg, pb) in enumerate(PAL_8BIT):
                        if (r, g, b) == (pr, pg, pb):
                            pal_idx = idx
                            break
                    bit = (pal_idx >> plane) & 1
                    solid = 1 if pal_idx != 0 else 0
                else:
                    bit = 0
                    solid = 0

                bp = x // 8
                shift = 7 - (x % 8)
                line[bp] |= (bit << shift)
                mask[bp] |= (solid << shift)

            raw_bytes.extend(line)
            msk_bytes.extend(mask)

    out_raw = OUT_DIR / "animals_64x64.raw"
    out_msk = OUT_DIR / "animals_64x64.msk"
    with open(out_raw, "wb") as f:
        f.write(raw_bytes)
    with open(out_msk, "wb") as f:
        f.write(msk_bytes)
    print(f"[*] Exported Amiga RAW: {out_raw} ({len(raw_bytes)} bytes)")
    print(f"[*] Exported Amiga MSK: {out_msk} ({len(msk_bytes)} bytes)")


if __name__ == "__main__":
    generate_all()
