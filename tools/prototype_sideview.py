#!/usr/bin/env python3
"""
tools/prototype_sideview.py
Prototyping side-view 16x16 rescue animals (Bunny, Puppy, Kitten, Duckling, Chick)
facing right, using Duckling as the reference for proportions, ground contact, and animation.
"""

from pathlib import Path
from PIL import Image, ImageDraw

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_ROOT / "assets" / "graphics" / "animals"

DEFAULT_PALETTE_OCS = [
    (0, 0, 0),       # 0: Transparent ($0000)
    (1, 11, 14),     # 1: 0x1BE Vibrant Cyan
    (3, 3, 2),       # 2: 0x332 Dark Charcoal outline (X)
    (15, 15, 15),    # 3: 0xFFF Pure White (W)
    (2, 7, 4),       # 4: 0x274 Forest Green (K)
    (1, 9, 3),       # 5: 0x193 Grass Green (G)
    (15, 9, 1),      # 6: 0xF91 Vibrant Orange (O)
    (2, 5, 12),      # 7: 0x25C Deep Blue (D)
    (15, 12, 2),     # 8: 0xFC2 Vibrant Gold / Yellow (Y)
    (13, 10, 6),     # 9: 0xDA6 Warm Sand / Cream (C)
    (11, 7, 4),      # 10: 0xB74 Warm Earth Brown (B)
    (8, 1, 3),       # 11: 0x813 Rich Maroon (M)
    (13, 1, 2),      # 12: 0xD12 Vibrant Red (R)
    (8, 9, 11),      # 13: 0x89B Slate Grey/Blue (S)
    (1, 7, 7),       # 14: 0x177 Vibrant Teal (T)
    (12, 10, 8),     # 15: 0xCA8 Peach / Pink (P)
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
# 1. BUNNY (Side View, facing right)
# Pure white fur with soft slate/cream shading, tall pink-lined ears angled back,
# sparkling eye (W catchlight + X pupil), cute pink nose, round cotton tail puff
# on rear left, grounded at line 15!
# ==============================================================================
BUNNY = [
    # F0: Stand (Alert, tall ears, round cotton tail, front paws held up, grounded at 15)
    [
        "......XX........",
        ".....XPPX...XX..",
        "....XPPX...XPPX.",
        "....XPPX...XPPX.",
        "....XWWX...XWWX.",
        "...XWWWWXXXWWX..",
        "..XWWWWWWWWWWX..",
        "..XWWWWXWWWWXPX.",
        "..XWWWWXXWWWWXX.",
        ".XXWWWWWWWWWWX..",
        "XWWXWWWWWWWWX...",
        "XWWXWWWWWWWWX...",
        ".XXSWWWWWWWWWX..",
        "..XSWWXXWWXXWX..",
        "..XWWWXXWWXXWX..",
        "..XXXX..XXXXXX..",
    ],
    # F1: Crouch (Anticipation squash, ears tilt back, body squashes down)
    [
        "................",
        "......XX........",
        ".....XPPX...XX..",
        "....XPPX...XPPX.",
        "....XWWX...XWWX.",
        "...XWWWWXXXWWX..",
        "..XWWWWWWWWWWX..",
        "..XWWWWXWWWWXPX.",
        "..XWWWWXXWWWWXX.",
        ".XXWWWWWWWWWWX..",
        "XWWXWWWWWWWWWWX.",
        "XWWXWWWWWWWWWWX.",
        ".XXSWWWWWWWWWWX.",
        "..XSWWWWWWWWWX..",
        "..XWWWWWWWWWWX..",
        "..XXXXXXXXXXXX..",
    ],
    # F2: Apex Jump (Airborne! 3px off ground! Ears stream back, paws extend, tail perked!)
    [
        "....XX..........",
        "...XPPX...XX....",
        "..XPPX...XPPX...",
        "..XPPX...XPPX...",
        "..XWWX...XWWX...",
        ".XWWWWXXXWWX....",
        "XWWWWWWWWWWX....",
        "XWWWWXWWWWXPX...",
        "XWWWWXXWWWWXX...",
        ".XXWWWWWWWWWWX..",
        "XWWXWWWWWWWWWWX.",
        "XWWXWWWWWWWWWWX.",
        ".XXXXSWWWWWWXXXX",
        "....XXXX.XXXX...",
        "................",
        "................",
    ],
    # F3: Land (Touchdown cushion, feet absorb landing, ears swing slightly forward)
    [
        "................",
        "......XX........",
        ".....XPPX...XX..",
        "....XPPX...XPPX.",
        "....XPPX...XPPX.",
        "....XWWX...XWWX.",
        "...XWWWWXXXWWX..",
        "..XWWWWWWWWWWX..",
        "..XWWWWXWWWWXPX.",
        "..XWWWWXXWWWWXX.",
        ".XXWWWWWWWWWWX..",
        "XWWXWWWWWWWWX...",
        ".XXSWWWWWWWWWX..",
        "..XSWWXXWWXXWX..",
        "..XWWWXXWWXXWX..",
        "..XXXX..XXXXXX..",
    ],
]

# ==============================================================================
# 2. PUPPY (Side View, facing right)
# Golden retriever pup, floppy brown ear, red collar, wagging tail on left,
# cute muzzle with black nose & tongue, sweet eye with catchlight.
# ==============================================================================
PUPPY = [
    # F0: Stand (Waiting, perked tail, floppy ear, black nose on right, paws on line 15)
    [
        "......XXXX......",
        ".....XBBBBX.....",
        "..XX.XBBBBX.....",
        ".XYX.XBBBBXXXX..",
        ".XYX.XBBXWYYX.X.",
        ".XYX.XBBXXYYX..X",
        "..XYX.XXXYYRPX.X",
        "...XYX.XXRRRRXX.",
        "...XYYYYYYYYYX..",
        "..XYYYYYYYYYYX..",
        "..XYYCYYYYYYX...",
        "..XYYCCYYYYYX...",
        "..XYYYYYYYYYX...",
        "..XYYXXYYXXYX...",
        "..XWWXXWWXXWX...",
        "..XXXX..XXXXX...",
    ],
    # F1: Crouch (Anticipation, tail wags lower, body squashes, paws flat)
    [
        "................",
        "......XXXX......",
        ".....XBBBBX.....",
        ".....XBBBBX.....",
        ".XXX.XBBBBXXXX..",
        "XYYX.XBBXWYYX.X.",
        "XYYX.XBBXXYYX..X",
        ".XYX..XXXYYRPX.X",
        "..XYX..XXRRRRXX.",
        "..XYYYYYYYYYYYX.",
        ".XYYYYCYYYYYYYX.",
        ".XYYYCCYYYYYYX..",
        "..XYYYYYYYYYYX..",
        "..XYYXXYYXXYYX..",
        "..XWWXXWWXXWWX..",
        "..XXXXXXXXXXXX..",
    ],
    # F2: Apex Jump (Airborne! 3px off ground! Ears flap back, paws reach forward, tail high!)
    [
        "..XX..XXXX......",
        ".XYX.XBBBBX.....",
        ".XYX.XBBBBX.....",
        "..XYX.XBBBBXXXX.",
        "..XYX.XBBXWYYX.X",
        "...XYX.BBXXYYX.X",
        "....XX.XXYYRPX.X",
        "....XRRRRRRRXX..",
        "...XYYYYYYYYYX..",
        "..XYYYYYYYYYYYX.",
        "..XYYCYYYYYYYYX.",
        "..XYYYCCYYYYYYX.",
        "...XXXXXXYYXXXX.",
        "......XWWXXWWX..",
        "................",
        "................",
    ],
    # F3: Land (Touchdown cushion, paws absorb ground contact)
    [
        "................",
        "......XXXX......",
        ".....XBBBBX.....",
        "..XX.XBBBBX.....",
        ".XYX.XBBBBXXXX..",
        ".XYX.XBBXWYYX.X.",
        ".XYX.XBBXXYYX..X",
        "..XYX.XXXYYRPX.X",
        "...XYX.XXRRRRXX.",
        "...XYYYYYYYYYX..",
        "..XYYYYYYYYYYX..",
        "..XYYCYYYYYYX...",
        "..XYYCCYYYYYX...",
        "..XYYXXYYXXYX...",
        "..XWWXXWWXXWX...",
        "..XXXX..XXXXX...",
    ],
]

# ==============================================================================
# 3. KITTEN (Side View, facing right)
# Ginger tabby kitten, perked pointed ears with pink, white bib & mittens,
# curved tail waving on left, expressive eye with catchlight, cute pink nose.
# ==============================================================================
KITTEN = [
    # F0: Stand (Alert, perked ears, curved tail, white bib & paws on line 15)
    [
        ".......XX.......",
        "......XPPX..XX..",
        ".....XPPX..XPPX.",
        "....XPPX...XPPX.",
        "...XWWX....XWWX.",
        "..XYYYYXXXXYYX..",
        ".XYYYYYYYYYYYX..",
        ".XYYYYYXWYYYXPX.",
        ".XYOYYYXXYYYXXX.",
        "..XYOOYYYYYYX...",
        "..XWWWWYYYYYX...",
        ".XYWWWWYYYYYYX..",
        "X..XYYYYYYYYYX..",
        "X.XYYXXYYXXYYX..",
        ".XWWXXWWXXWWX...",
        ".XXXX.XXXX.XX...",
    ],
    # F1: Crouch (Squash down, ears tilt back, tail swishes low)
    [
        "................",
        ".......XX.......",
        "......XPPX..XX..",
        ".....XPPX..XPPX.",
        "....XWWX...XWWX.",
        "...XYYYYXXXXYYX.",
        "..XYYYYYYYYYYYX.",
        "..XYYYYYXWYYYXPX",
        "..XYOYYYXXYYYXXX",
        "...XYOOYYYYYYX..",
        "..XYWWWWYYYYYX..",
        ".XYYWWWWYYYYYYX.",
        "X.XYYYYYYYYYYYX.",
        ".XXYYXXYYXXYYX..",
        ".XWWXXWWXXWWX...",
        ".XXXXXXXXXXXX...",
    ],
    # F2: Apex Jump (Airborne! 3px off ground! Paws stretch, tail curls high!)
    [
        "X......XX.......",
        "X     XPPX..XX..",
        ".X   XPPX..XPPX.",
        ".X  XPPX...XPPX.",
        "..X XWWX...XWWX.",
        "..XYYYYXXXXYYX..",
        ".XYYYYYYYYYYYX..",
        ".XYYYYYXWYYYXPX.",
        ".XYOYYYXXYYYXXX.",
        "..XYOOYYYYYYX...",
        "..XWWWWYYYYYX...",
        ".XYWWWWYYYYYYX..",
        "..XYYYYYYYYYYYX.",
        "...XXXX..XXXX...",
        "................",
        "................",
    ],
    # F3: Land (Touchdown cushion, landing paws on line 15)
    [
        "................",
        ".......XX.......",
        "......XPPX..XX..",
        ".....XPPX..XPPX.",
        "....XPPX...XPPX.",
        "...XWWX....XWWX.",
        "..XYYYYXXXXYYX..",
        ".XYYYYYYYYYYYX..",
        ".XYYYYYXWYYYXPX.",
        ".XYOYYYXXYYYXXX.",
        "..XYOOYYYYYYX...",
        "..XWWWWYYYYYX...",
        ".XYWWWWYYYYYYX..",
        "X.XYYXXYYXXYYX..",
        ".XWWXXWWXXWWX...",
        ".XXXX.XXXX.XX...",
    ],
]

# ==============================================================================
# 4. DUCKLING (Side View, facing right - VERBATIM GOLD STANDARD)
# ==============================================================================
DUCKLING = [
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

# ==============================================================================
# 5. CHICK (Side View, facing right)
# Downy puffball chick! Fluffy crest tuft, tiny sharp triangular beak,
# round bead eye, cream belly fluff, tiny winglet, delicate twiggy bird feet!
# ==============================================================================
CHICK = [
    # F0: Stand (Round puffball, sharp tiny beak, cream tummy, twiggy feet on line 15)
    [
        "......XX........",
        ".....XYYX.......",
        "....XYYYYX......",
        "...XYYYYYYX.....",
        "..XYYXWYYYX.....",
        "..XYYXXYYYXX....",
        "..XYYYYYYYOX....",
        "..XYYXYYYOOX....",
        "..XYYXYYYYXX....",
        ".XYYYXCCYYYX....",
        ".XYYYCCCCYYX....",
        ".XYYYCCCCYYX....",
        "..XYYYYYYYX.....",
        "...XYYYYYX......",
        "....XOX.XOX.....",
        "...XX.X.X.XX....",
    ],
    # F1: Crouch (Puffball squashes down, beak tilts up, winglet ruffles)
    [
        "................",
        "......XX........",
        ".....XYYX.......",
        "    XYYYYX......",
        "...XYYYYYYX.....",
        "..XYYXWYYYXX....",
        "..XYYXXYYYOX....",
        "..XYYYYYYOOX....",
        ".XYYYXYYYYXX....",
        "XYYYYXCCYYYX....",
        "XYYYYCCCCYYX....",
        ".XYYYCCCCYYX....",
        "..XYYYYYYYX.....",
        "...XYYYYYX......",
        "    XOX.XOX.....",
        "...XX.X.X.XX....",
    ],
    # F2: Apex Jump (Airborne flutter! Tiny wings flap open, twiggy feet tucked under body!)
    [
        "......XX........",
        ".....XYYX.......",
        "    XYYYYX......",
        "...XYYYYYYX.....",
        "..XYYXWYYYX.....",
        "..XYYXXYYYXX....",
        "..XYYYYYYYOX....",
        ".XXYYXYYYOOX....",
        "XYYXYYYYYYXX....",
        "XYYXYYCCCCXYX...",
        ".XYYYYCCCCXYX...",
        "..XYYYCCCCXX....",
        "...XYYYYYX......",
        "    XOX.XOX.....",
        "................",
        "................",
    ],
    # F3: Land (Touchdown cushion, feet absorb landing)
    [
        "................",
        "......XX........",
        ".....XYYX.......",
        "    XYYYYX......",
        "...XYYYYYYX     ",
        "..XYYXWYYYX.....",
        "..XYYXXYYYXX....",
        "..XYYYYYYYOX....",
        "..XYYXYYYOOX....",
        "..XYYXYYYYXX....",
        ".XYYYXCCYYYX....",
        ".XYYYCCCCYYX....",
        ".XYYYCCCCYYX....",
        "..XYYYYYYYX.....",
        "    XOX.XOX.....",
        "...XX.X.X.XX....",
    ],
]

ALL_ANIMALS = [
    ("bunny", "Bunny", BUNNY),
    ("puppy", "Puppy", PUPPY),
    ("kitten", "Kitten", KITTEN),
    ("duckling", "Duckling", DUCKLING),
    ("chick", "Chick", CHICK),
]


def test_render():
    print("[*] Verifying all 5 animals...")
    for name, title, frames in ALL_ANIMALS:
        assert len(frames) == 4, f"{name} must have 4 frames"
        for f_idx, f in enumerate(frames):
            assert len(f) == 16, f"{name} F{f_idx} must have 16 rows"
            for r_idx, row in enumerate(f):
                assert len(row) == 16, f"{name} F{f_idx} row {r_idx} must be 16 chars (got {len(row)}): {row}"
    print("[+] All 5 animals passed 16x16 grid validation!")

    # Render 64x80 image
    sheet = Image.new("RGBA", (64, 80), (0, 0, 0, 0))
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

    out_sheet = OUT_DIR / "animals_sideview_16x16.png"
    sheet.save(out_sheet)
    print(f"[+] Saved: {out_sheet}")

    # Magnified 8x contact sheet
    scale = 8
    w, h = 64 * scale, 80 * scale
    left_m, top_m = 140, 36
    preview = Image.new("RGBA", (left_m + w + 20, top_m + h + 20), (28, 30, 42, 255))
    draw = ImageDraw.Draw(preview)

    scaled_sheet = sheet.resize((w, h), Image.Resampling.NEAREST)
    preview.paste(scaled_sheet, (left_m, top_m), scaled_sheet)

    # Grid
    for i in range(5):
        gx = left_m + i * 16 * scale
        draw.line([(gx, top_m), (gx, top_m + h)], fill=(70, 75, 95, 200), width=1)
    for i in range(6):
        gy = top_m + i * 16 * scale
        draw.line([(left_m, gy), (left_m + w, gy)], fill=(70, 75, 95, 200), width=1)

    headers = ["F0: Stand", "F1: Crouch", "F2: Apex Jump", "F3: Land"]
    for i, title in enumerate(headers):
        draw.text((left_m + i * 16 * scale + 34, 12), title, fill=(220, 230, 245, 255))

    for row_idx, (_, title, _) in enumerate(ALL_ANIMALS):
        ry = top_m + row_idx * 16 * scale + 8 * scale - 6
        draw.text((12, ry), title, fill=(255, 215, 80, 255))

    preview_path = OUT_DIR / "animals_sideview_preview.png"
    preview.save(preview_path)
    print(f"[+] Saved: {preview_path}")

    # Animated GIFs
    durations = [180, 120, 260, 120]
    for name, title, frames in ALL_ANIMALS:
        gif_frames = []
        for frame in frames:
            im = Image.new("P", (16, 16), 0)
            im.putpalette(PAL_FLAT)
            for y, line in enumerate(frame):
                for x, char in enumerate(line):
                    idx = LEGEND.get(char, 0)
                    im.putpixel((x, y), idx)
            im_scaled = im.resize((96, 96), Image.Resampling.NEAREST)
            gif_frames.append(im_scaled)

        gif_path = OUT_DIR / f"{name}_sideview_anim.gif"
        gif_frames[0].save(
            gif_path,
            save_all=True,
            append_images=gif_frames[1:],
            duration=durations,
            loop=0,
            disposal=2,
            transparency=0,
        )
        print(f"[+] Saved: {gif_path}")


if __name__ == "__main__":
    test_render()
