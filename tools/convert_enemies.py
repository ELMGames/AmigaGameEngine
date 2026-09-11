#!/usr/bin/env python3
"""
convert_enemies.py
------------------
Converts assets/graphics/enemies/enemies_16x16.png (64x128 RGBA)
into 4-bitplane interleaved raw graphic and mask files:
  - assets/graphics/enemies/enemies_64x128.raw (4096 bytes)
  - assets/graphics/enemies/enemies_64x128.msk (4096 bytes)

Layout:
  128 scanlines total (8 enemy creature rows x 16 scanlines each).
  Each scanline is 64 pixels wide (4 animation frames x 16 pixels).
  Interleaved: Plane 0 (8 bytes), Plane 1 (8 bytes), Plane 2 (8 bytes), Plane 3 (8 bytes) = 32 bytes/row.
  Total size: 128 * 32 = 4096 bytes.
"""

from pathlib import Path
from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# Vibrant 16-color OCS palette (matches export_level.py DEFAULT_PALETTE_OCS)
PALETTE_OCS = [
    (0, 0, 0),      # 0: Transparent ($0000)
    (1, 11, 14),    # 1: 0x1BE Vibrant Cyan
    (3, 3, 2),      # 2: 0x332 Dark outline
    (15, 15, 15),   # 3: 0xFFF White glints / highlights
    (2, 7, 4),      # 4: 0x274 Forest Green
    (1, 9, 3),      # 5: 0x193 Grass Green
    (15, 9, 1),     # 6: 0xF91 Vibrant Orange
    (2, 5, 12),     # 7: 0x25C Deep Blue
    (15, 12, 2),    # 8: 0xFC2 Vibrant Gold / Yellow
    (13, 10, 6),    # 9: 0xDA6 Light Wood / Sand
    (11, 7, 4),     # 10: 0xB74 Stone / Earth
    (8, 1, 3),      # 11: 0x813 Rich Maroon
    (13, 1, 2),     # 12: 0xD12 Vibrant Red
    (8, 9, 11),     # 13: 0x89B Slate Grey/Blue
    (1, 7, 7),      # 14: 0x177 Vibrant Teal
    (12, 10, 8)     # 15: 0xCA8 Tan / Warm Stone / Peach
]


def map_pixel_to_index(r: int, g: int, b: int, a: int) -> int:
    if a <= 128:
        return 0

    # Explicit vibrant assignments for enemy palette fidelity:
    rgb = (r, g, b)
    if rgb == (0, 162, 157):
        return 1   # Vibrant Cyan (Cyan Slime / Blue Ghost body)
    if rgb in [(1, 64, 57), (7, 61, 58)]:
        return 14  # Vibrant Teal (Cyan Slime / Blue Ghost shadow)
    if rgb == (169, 0, 0):
        return 12  # Vibrant Red (Red Slime & Bat body/wings / Snail foot)
    if rgb in [(93, 4, 4), (52, 12, 8)]:
        return 11  # Rich Maroon (Red Slime & Bat shadow)
    if rgb in [(250, 170, 0), (235, 160, 0)]:
        return 6   # Vibrant Orange (Wasp / Bat eyes / Ghost eyes)
    if rgb == (169, 140, 0):
        return 8   # Vibrant Gold (Wasp body / Cyclops horns / highlights)
    if rgb == (243, 216, 153):
        return 3   # Pure White glint / eye highlight
    if rgb == (249, 181, 105):
        return 6   # Vibrant Orange wings (Wasp)
    if rgb == (47, 89, 14):
        return 5   # Grass Green (Cyclops body & Wasp head)
    if rgb == (30, 36, 5):
        return 4   # Forest Green shadow (Cyclops)
    if rgb == (131, 118, 156):
        return 13  # Slate Blue (Octo dome)
    if rgb == (42, 39, 51):
        return 11  # Rich Maroon shadow (Octo underside)
    if rgb == (149, 124, 102):
        return 9   # Tan / Light Wood (Snail shell)
    if rgb == (109, 75, 57):
        return 10  # Warm Stone / Earth (Snail shell base)
    if rgb in [(14, 21, 28), (0, 0, 0)]:
        return 2   # Dark Charcoal Outline

    # Fallback to nearest Euclidean distance in OCS RGB space:
    ro, go, bo = round(r * 15 / 255), round(g * 15 / 255), round(b * 15 / 255)
    best_dist = 999999
    best_idx = 1
    for idx, (pr, pg, pb) in enumerate(PALETTE_OCS[1:], start=1):
        d = (ro - pr) ** 2 + (go - pg) ** 2 + (bo - pb) ** 2
        if d < best_dist:
            best_dist = d
            best_idx = idx
    return best_idx


def convert_enemy_spritesheet(src_path: Path, raw_path: Path, msk_path: Path):
    print(f"[*] Converting enemy spritesheet: {src_path.name}")
    img = Image.open(src_path).convert("RGBA")
    w, h = img.size
    assert w == 64 and h == 128, f"Expected 64x128 PNG, got {w}x{h}"

    pixels = img.load()
    row_bytes = w // 8  # 8 bytes per plane row
    raw_bytes = bytearray()
    msk_bytes = bytearray()

    for y in range(h):
        for plane in range(4):
            line = bytearray(row_bytes)
            mask = bytearray(row_bytes)
            for x in range(w):
                r, g, b, a = pixels[x, y]
                idx = map_pixel_to_index(r, g, b, a)
                bit = (idx >> plane) & 1
                solid = 1 if idx != 0 else 0
                bp = x // 8
                shift = 7 - (x % 8)
                line[bp] |= (bit << shift)
                mask[bp] |= (solid << shift)
            raw_bytes.extend(line)
            msk_bytes.extend(mask)

    raw_path.parent.mkdir(parents=True, exist_ok=True)
    with open(raw_path, "wb") as f:
        f.write(raw_bytes)
    with open(msk_path, "wb") as f:
        f.write(msk_bytes)

    print(f"    Exported enemy raw: {raw_path} ({len(raw_bytes)} bytes)")
    print(f"    Exported enemy msk: {msk_path} ({len(msk_bytes)} bytes)")


def main():
    src_png = PROJECT_ROOT / "assets" / "graphics" / "enemies" / "enemies_16x16.png"
    out_raw = PROJECT_ROOT / "assets" / "graphics" / "enemies" / "enemies_64x128.raw"
    out_msk = PROJECT_ROOT / "assets" / "graphics" / "enemies" / "enemies_64x128.msk"
    convert_enemy_spritesheet(src_png, out_raw, out_msk)


if __name__ == "__main__":
    main()
