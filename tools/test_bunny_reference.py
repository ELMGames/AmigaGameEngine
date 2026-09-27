#!/usr/bin/env python3
"""
tools/test_bunny_reference.py
Pixel-perfect translation of bunny.png into 16x16.
"""

from pathlib import Path
from PIL import Image, ImageDraw

PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_ROOT / "assets" / "graphics" / "animals"

PALETTE_OCS = [
    (0, 0, 0),       # 0: Transparent
    (1, 11, 14),     # 1: Vibrant Cyan
    (3, 3, 2),       # 2: Dark Charcoal outline (X)
    (15, 15, 15),    # 3: Pure White (W)
    (2, 7, 4),       # 4: Forest Green
    (1, 9, 3),       # 5: Grass Green
    (15, 9, 1),      # 6: Vibrant Orange
    (2, 5, 12),      # 7: Deep Blue
    (15, 12, 2),     # 8: Vibrant Gold / Yellow (Y)
    (13, 10, 6),     # 9: Warm Sand / Cream (C)
    (11, 7, 4),      # 10: Earth Brown (B)
    (8, 1, 3),       # 11: Rich Maroon (M)
    (13, 1, 2),      # 12: Vibrant Red (R)
    (8, 9, 11),      # 13: Slate Grey (S)
    (1, 7, 7),       # 14: Vibrant Teal (T)
    (12, 10, 8),     # 15: Peach / Pink (P)
]
PAL_8BIT = [(r * 17, g * 17, b * 17) for r, g, b in PALETTE_OCS]

LEGEND = {
    '.': 0,   # Transparent
    'X': 2,   # Charcoal outline
    'W': 3,   # Pure White
    'C': 9,   # Warm Sand / Cream
    'B': 10,  # Brown shadow
    'M': 11,  # Maroon
    'R': 12,  # Red (pink nose accent)
    'S': 13,  # Slate Grey
    'P': 15,  # Peach / Pink
}

# Let's test a few variations of the stand frame
BUNNY_CANDIDATES = [
    # Option A: Faithful 16x16 translation of bunny.png
    [
        "....XX....XXXX..",
        "...XWWX..XPPPPX.",
        "..XWWCX.XPPPPPX.",
        "..XWWX..XPPPPX..",
        "...XX..XCCCCX...",
        "..XXXX..XXXX....",
        ".XWWWWXXXXCCCCX.",
        "XWWWWWWX.XCCCCCX",
        "XWWWWXWX.XCCCCCX",
        "XPPWWXXW.XCCCCX.",
        "XWWXWWWWXWWCCCXX",
        ".XWWWWWWWWWWCCXX",
        ".XWWXWWXWWWWCCXX",
        ".XWWXWWX.WWCCCCX",
        "..XX.XX..XXXXXX.",
        "................",
    ],
    # Option B: Cleaner silhouette, diamond eye, cute paws
    [
        "....XX....XXXX..",
        "...XWWX..XPPPPX.",
        "..XWWCX.XPPPPPX.",
        "..XWWX..XPPPPX..",
        "...XX..XCCCCX...",
        "..XXXX..XXXX....",
        ".XWWWWXXXXCCCCX.",
        "XWWWWWW..XCCCCCX",
        "XWWWW.X..XCCCCCX",
        "XPPW.XWX.XCCCCX.",
        "XWWX.XX..XWCCCXX",
        ".XWWWWWWWWWWCCXX",
        ".XWWXWWXWWWWCCXX",
        ".XWWXWWX.WWCCCCX",
        "..XX.XX..XXXXXX.",
        "................",
    ],
    # Option C: Highly polished 16x16 with diamond eye, pink nose, tail puff
    [
        "....XX....XXXX..",
        "...XWWX..XPPPPX.",
        "..XWWCX.XPPPPPX.",
        "..XWWX..XPPPPX..",
        "...XX..XCCCCX...",
        "..XXXX.XXXXXX...",
        ".XWWWWXCCCCCCX..",
        "XWWWWWWXCCCCCCX.",
        "XWWWW.X.XCCCCCX.",
        "XPPW.XWX.XCCCXX.",
        "XWWX.XX.XWWCCXX.",
        ".XWWWWWWWWWCCCXX",
        ".XWWXWWXWWWWCCXX",
        ".XWWXWWX.WWCCCCX",
        "..XX.XX..XXXXXX.",
        "................",
    ],
]

def render_candidates():
    scale = 12
    total_w = len(BUNNY_CANDIDATES) * (16 * scale + 10) + 10
    total_h = 16 * scale + 20
    im = Image.new("RGBA", (total_w, total_h), (28, 30, 42, 255))
    draw = ImageDraw.Draw(im)

    for i, cand in enumerate(BUNNY_CANDIDATES):
        ox = 10 + i * (16 * scale + 10)
        oy = 10
        for y, line in enumerate(cand):
            for x, char in enumerate(line):
                idx = LEGEND.get(char, 0)
                if idx > 0:
                    r, g, b = PAL_8BIT[idx]
                    draw.rectangle([ox + x*scale, oy + y*scale, ox + (x+1)*scale-1, oy + (y+1)*scale-1], fill=(r, g, b, 255))

    out_p = OUT_DIR / "bunny_candidates.png"
    im.save(out_p)
    print(f"Saved {out_p}")

if __name__ == "__main__":
    render_candidates()
