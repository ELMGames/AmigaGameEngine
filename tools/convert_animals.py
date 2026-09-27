#!/usr/bin/env python3
"""
tools/convert_animals.py
------------------------
Generates and converts the 3 rescue animal BOBs:
  - Row 0: DOG1 (Tan Dog / Shiba, based on d1_raw_16x16_f3.png)
  - Row 1: DOG2 (White Dog / Puppy, based on d2_raw_16x16_f3.png)
  - Row 2: DUCKLING (Side-view Duckling)

Outputs:
  - assets/graphics/animals/animals_16x16.png (64x48 master PNG)
  - assets/graphics/animals/animals_64x48.raw (1,536 bytes: 4-bitplane interleaved)
  - assets/graphics/animals/animals_64x48.msk (1,536 bytes: 4-bitplane blitter mask)
  - assets/graphics/animals/animals_preview.png (8x magnified preview with annotations)
  - assets/graphics/animals/dog1_anim.gif
  - assets/graphics/animals/dog2_anim.gif
  - assets/graphics/animals/duckling_anim.gif
"""

from pathlib import Path
from PIL import Image, ImageDraw

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_ROOT / "assets" / "graphics" / "animals"
SRC_ANIMALS = OUT_DIR / "animals_16x16.png"

# In-game 16-color OCS playfield palette (matches FourSeasons tileset & LevelDef_Palette)
DEFAULT_PALETTE_OCS = [
    (0, 0, 0),       # 0: Transparent ($0000)
    (1, 11, 14),     # 1: 0x1BE Vibrant Cyan
    (3, 3, 2),       # 2: 0x332 Dark Charcoal outline
    (15, 15, 15),    # 3: 0xFFF Pure White (fur, catchlights, highlights)
    (2, 7, 4),       # 4: 0x274 Forest Green
    (1, 9, 3),       # 5: 0x193 Grass Green
    (15, 9, 1),      # 6: 0xF91 Vibrant Orange (duck bill/feet)
    (2, 5, 12),      # 7: 0x25C Deep Blue
    (15, 12, 2),     # 8: 0xFC2 Vibrant Gold / Yellow (duckling, tan dog)
    (13, 10, 6),     # 9: 0xDA6 Warm Sand / Cream (tan dog belly, muzzle)
    (11, 7, 4),      # 10: 0xB74 Warm Earth Brown (tan dog ears, paws)
    (8, 1, 3),       # 11: 0x813 Rich Maroon (mouth interior)
    (13, 1, 2),      # 12: 0xD12 Vibrant Red (collar, tongue)
    (8, 9, 11),      # 13: 0x89B Slate Grey/Blue (white dog shading)
    (1, 7, 7),       # 14: 0x177 Vibrant Teal
    (12, 10, 8),     # 15: 0xCA8 Peach / Pink (white dog inner ears, tongue)
]

PAL_8BIT = [(r * 17, g * 17, b * 17) for r, g, b in DEFAULT_PALETTE_OCS]

PAL_FLAT = []
for r, g, b in PAL_8BIT:
    PAL_FLAT.extend([r, g, b])
PAL_FLAT.extend([0] * (768 - len(PAL_FLAT)))

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
# 1. DOG1 (Tan Dog / Shiba, based on d1_raw_16x16_f3.png)
# ==============================================================================
DOG1_FRAMES = [
    # F0: Stand Alert
    [
        "......X......X..",
        ".....XWX....XWX.",
        ".....XBWXXXXXBWX",
        ".....XBBXCCBXBXX",
        ".XX..XXBCCCCBXX.",
        "XBX..XXCCCCCCBX.",
        "XBX..XCWXCWXBCXX",
        "XXX..XXCCBCCBBXX",
        "XXX...XXCXXCBX..",
        "XBBXXXBXXBBXXXX.",
        ".XBBXCCXXXXXXX..",
        "..XXCWWCCCCXX...",
        "..XXCCCCCCCCX...",
        "..XBXXCCBXXCX...",
        "..XBXXXBXXXBX...",
        "..XXBXXXBXXXBX..",
    ],
    # F1: Head bob / Step (Ears & head dip 1px, tail wags inward)
    [
        "................",
        ".....XXX.....XX.",
        ".....XBWXXXXXBWX",
        ".....XWWXXXXXWBX",
        "..XX.XXXBCCBBXXX",
        ".XBX..XBCWPPCBX.",
        "XXBX.XBWBCCBCBX.",
        "XXX..XBCXCCXCCXX",
        "XXX..XXBCXXCCXXX",
        "XBX..XXXBBBBXXX.",
        "XXBXXBCBXXXXXX..",
        ".XXBBCWPCBBBXX..",
        "..XXPWCCCCCCBX..",
        "..XCCXBCBBBCBX..",
        "..XBXXXBXXXXBX..",
        "..XXBXXXBXXXBX..",
    ],
    # F2: Step forward / Tail curls high
    [
        ".XX..XXX.....XX.",
        "XBWX.XBWXXXXXBWX",
        "XBBX.XWWXXXXXWBX",
        ".XBX.XXXBCCBBXXX",
        ".XBX..XBCWPPCBX.",
        "XBXX.XBWBCCBCBX.",
        "XBX..XBCXCCXCCXX",
        "XXX..XXBCXXCCXXX",
        "XBX..XXXBBBBXX..",
        "XXBXXBCBXXXXXXX.",
        "..XBBCWPCBBBXX..",
        "..XXCWCCCCCCXX..",
        "..XBCBXCCBBCB...",
        "..XBXXXBXXXBX...",
        "..XXBXXXBXXXBX..",
        "...XXXXXXXXXX...",
    ],
    # F3: Return / User Favorite (d1_raw_16x16_f3.png)
    [
        "......X......XX.",
        ".....XWX....XWXX",
        ".....XBWXXXXXBWX",
        ".....XBBXCCBXBXX",
        ".XX..XXBCCCCBXX.",
        "XBXX.XXCCCCCCBX.",
        "XBX..XCWXCWXBCXX",
        "XXX..XXCCBCCBBXX",
        "XXX...XXCXXCBXX.",
        "XBBXXXBXXBBXXXX.",
        ".XBBXCCXXXXXXX..",
        "..XXCWWCCCCXX...",
        "..XXCCCCCCCCX...",
        "..XBXXCCBXXCX...",
        "..XBXXXBXXXBX...",
        "..XXBXXXBXXXBX..",
    ],
]

# ==============================================================================
# 2. DOG2 (White Dog / Puppy, based on d2_raw_16x16_f3.png)
# ==============================================================================
DOG2_FRAMES = [
    # F0: Sitting happy, tail near rump
    [
        "....XX......XX..",
        "...XWX.....XWX..",
        "..XSWX....XXPWX.",
        "..XWWXXXXXXWPWX.",
        ".XWWWWWWWWWWWWSX",
        ".XWWXXWWWWXXWWSX",
        ".XWWXXWWWWXXWWXX",
        "..XWWWWXXWWWWX..",
        "..XSWWWXXWWWSX..",
        "...XXXXRRPXXX...",
        "..XWWWWWWWWWWX..",
        ".XSWWWWWWWWWWSX.",
        ".XWWWWWWWWWWWWXX",
        ".XWWXXWWXXWWXWWX",
        ".XWWXXWWXXWWXWWX",
        ".XXXXXXXXXXXXXX.",
    ],
    # F1: Tail wags to 45 degrees, head dips 1px, tongue wiggles
    [
        "................",
        "....XX......XX..",
        "...XWX.....XWX..",
        "..XSWX....XXPWX.",
        "..XWWXXXXXXWPWX.",
        ".XWWWWWWWWWWWWSX",
        ".XWWXXWWWWXXWWSX",
        ".XWWXXWWWWXXWWXX",
        "..XWWWWXXWWWWX..",
        "..XSWWWXXWWWSX..",
        "...XXXXPRPXXX.XX",
        "..XWWWWWWWWWWXWX",
        ".XSWWWWWWWWWWSWX",
        ".XWWXXWWXXWWX.WX",
        ".XWWXXWWXXWWX.XX",
        ".XXXXXXXXXXXX...",
    ],
    # F2: Tail horizontal full wag, mouth open happy
    [
        "....XX......XX..",
        "...XWX.....XWX..",
        "..XSWX....XXPWX.",
        "..XWWXXXXXXWPWX.",
        ".XWWWWWWWWWWWWSX",
        ".XWWXXWWWWXXWWSX",
        ".XWWXXWWWWXXWWXX",
        "..XWWWWXXWWWWX..",
        "..XSWWWXXWWWSX..",
        "...XXXXRRPXXX...",
        "..XWWWWWWWWWWXX.",
        ".XSWWWWWWWWWWSWW",
        ".XWWWWWWWWWWWWXX",
        ".XWWXXWWXXWWX...",
        ".XWWXXWWXXWWX...",
        ".XXXXXXXXXXXX...",
    ],
    # F3: Return / User Favorite (d2_raw_16x16_f3.png)
    [
        "....XX......XX..",
        "...XWX.....XWX..",
        "..XSWX....XXPWX.",
        "..XWWXXXXXXWPWX.",
        ".XWWWWWWWWWWWWSX",
        ".XWWXXWWWWXXWWSX",
        ".XWWXXWWWWXXWWXX",
        "..XWWWWXXWWWWX..",
        "..XSWWWXXWWWSX..",
        "...XXXXRRPXXX...",
        "..XWWWWWWWWWWX..",
        ".XSWWWWWWWWWWSXX",
        ".XWWWWWWWWWWWWXX",
        ".XWWXXWWXXWWXWWX",
        ".XWWXXWWXXWWXWWX",
        ".XXXXXXXXXXXXXX.",
    ],
]

# ==============================================================================
# 3. DUCKLING (Side-view Duckling)
# ==============================================================================
DUCKLING_FRAMES = [
    # F0: Stand
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
    # F1: Crouch
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
    # F2: Apex Jump
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
    # F3: Land
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

ANIMALS = [
    ("DOG1", DOG1_FRAMES),
    ("DOG2", DOG2_FRAMES),
    ("DUCKLING", DUCKLING_FRAMES),
]

ANIMAL_NAMES = [name for name, _ in ANIMALS]


def build_master_spritesheet() -> Image.Image:
    """Build the 64x48 master PNG image (3 animals x 4 frames)."""
    w = 64
    h = len(ANIMALS) * 16  # 48 pixels
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    for row_idx, (name, frames) in enumerate(ANIMALS):
        fy = row_idx * 16
        for col_idx, frame in enumerate(frames):
            fx = col_idx * 16
            for y, line in enumerate(frame):
                for x, char in enumerate(line):
                    idx = LEGEND.get(char, 0)
                    if idx > 0:
                        r, g, b = PAL_8BIT[idx]
                        sheet.putpixel((fx + x, fy + y), (r, g, b, 255))

    sheet.save(SRC_ANIMALS)
    print(f"    Saved master spritesheet: {SRC_ANIMALS} ({w}x{h})")
    return sheet


def convert_animal_spritesheet():
    img = build_master_spritesheet()
    w, h = img.size
    assert w == 64 and h == 48, f"Expected 64x48 PNG, got {w}x{h}"

    row_bytes = w // 8  # 8 bytes per plane row (4 words)
    raw_bytes = bytearray()
    msk_bytes = bytearray()

    # Remapped 64x48 image (mode 'P' with PAL_FLAT)
    remapped_img = Image.new("P", (w, h), 0)
    remapped_img.putpalette(PAL_FLAT)

    for row_idx, (name, frames) in enumerate(ANIMALS):
        for col_idx, frame in enumerate(frames):
            fx = col_idx * 16
            fy = row_idx * 16
            for y, line in enumerate(frame):
                for x, char in enumerate(line):
                    idx = LEGEND.get(char, 0)
                    remapped_img.putpixel((fx + x, fy + y), idx)

    # 4-bitplane interleaved conversion
    for y in range(h):
        for plane in range(4):
            line = bytearray(row_bytes)
            mask = bytearray(row_bytes)
            for x in range(w):
                ocs_idx = remapped_img.getpixel((x, y))
                bit = (ocs_idx >> plane) & 1
                solid = 1 if ocs_idx != 0 else 0
                bp = x // 8
                shift = 7 - (x % 8)
                line[bp] |= (bit << shift)
                mask[bp] |= (solid << shift)
            raw_bytes.extend(line)
            msk_bytes.extend(mask)

    out_raw = OUT_DIR / "animals_64x48.raw"
    out_msk = OUT_DIR / "animals_64x48.msk"

    with open(out_raw, "wb") as f:
        f.write(raw_bytes)
    with open(out_msk, "wb") as f:
        f.write(msk_bytes)

    print(f"    Exported animal raw: {out_raw} ({len(raw_bytes)} bytes)")
    print(f"    Exported animal msk: {out_msk} ({len(msk_bytes)} bytes)")

    # Also write animals_64x80 for backwards-compatibility if referenced
    compat_raw = OUT_DIR / "animals_64x80.raw"
    compat_msk = OUT_DIR / "animals_64x80.msk"
    pad = bytearray(512 * 2)  # pad to 2560 bytes
    with open(compat_raw, "wb") as f:
        f.write(raw_bytes + pad)
    with open(compat_msk, "wb") as f:
        f.write(msk_bytes + pad)

    # Export preview contact sheet
    export_preview_sheet(remapped_img)

    # Export animated GIFs
    export_animated_gifs(remapped_img)


def export_preview_sheet(remapped_img: Image.Image):
    scale = 8
    w, h = remapped_img.size
    left_m = 160
    top_m = 36
    preview = Image.new("RGBA", (left_m + w * scale + 20, top_m + h * scale + 20), (28, 30, 42, 255))
    draw = ImageDraw.Draw(preview)

    rgb_sheet = remapped_img.convert("RGBA")
    # Fix transparent pixels in preview
    for y in range(h):
        for x in range(w):
            if remapped_img.getpixel((x, y)) == 0:
                rgb_sheet.putpixel((x, y), (0, 0, 0, 0))

    scaled_sheet = rgb_sheet.resize((w * scale, h * scale), Image.Resampling.NEAREST)
    preview.paste(scaled_sheet, (left_m, top_m), scaled_sheet)

    # Grid lines
    for i in range(5):
        gx = left_m + i * 16 * scale
        draw.line([(gx, top_m), (gx, top_m + h * scale)], fill=(70, 75, 95, 200), width=1)
    for i in range(len(ANIMALS) + 1):
        gy = top_m + i * 16 * scale
        draw.line([(left_m, gy), (left_m + w * scale, gy)], fill=(70, 75, 95, 200), width=1)

    # Frame headers
    headers = ["F0: Stand / Sit", "F1: Bob / Crouch", "F2: Step / Jump", "F3: Return / Land"]
    for i, title in enumerate(headers):
        draw.text((left_m + i * 16 * scale + 14, 12), title, fill=(220, 230, 245, 255))

    # Animal row labels
    for row_idx, name in enumerate(ANIMAL_NAMES):
        ry = top_m + row_idx * 16 * scale + 8 * scale - 6
        draw.text((16, ry), f"{name}", fill=(255, 215, 80, 255))

    out_preview = OUT_DIR / "animals_preview.png"
    preview.save(out_preview)
    print(f"    Exported preview contact sheet: {out_preview}")


def export_animated_gifs(remapped_img: Image.Image):
    durations = [180, 150, 200, 150]  # ms per frame
    for row_idx, name in enumerate(ANIMAL_NAMES):
        frames = []
        for col_idx in range(4):
            box = (col_idx * 16, row_idx * 16, (col_idx + 1) * 16, (row_idx + 1) * 16)
            cel = remapped_img.crop(box)
            cel_scaled = cel.resize((96, 96), Image.Resampling.NEAREST)
            frames.append(cel_scaled)

        gif_path = OUT_DIR / f"{name.lower()}_anim.gif"
        frames[0].save(
            gif_path,
            save_all=True,
            append_images=frames[1:],
            duration=durations,
            loop=0,
            disposal=2,
            transparency=0,
        )
        print(f"    Exported animated GIF: {gif_path}")


if __name__ == "__main__":
    convert_animal_spritesheet()
