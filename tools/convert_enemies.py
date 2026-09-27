#!/usr/bin/env python3
"""
tools/convert_enemies.py
------------------------
Converts:
  1. Enemy Walk Animations:
     - assets/graphics/enemies/enemies_16x16.png (64x128 RGBA, 8 enemy types x 4 walk frames)
     - Output: enemies_64x128.raw, enemies_64x128.msk, enemies_64x128_white.raw (4,096 bytes each)
  2. Stunned Dizzy Stars Animation:
     - assets/graphics/enemies/dizzy_stars_64x16.png (64x16 RGBA, 4 orbiting star frames)
     - Output: dizzy_stars_64x16.raw, dizzy_stars_64x16.msk (512 bytes each)

Format: 4-bitplane interleaved raw graphics and 1-bit cookie-cut masks.
"""

from pathlib import Path
from PIL import Image, ImageDraw

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

PAL_8BIT = [(r * 17, g * 17, b * 17) for r, g, b in PALETTE_OCS]


def map_pixel_to_index(r: int, g: int, b: int, a: int) -> int:
    if a <= 128:
        return 0

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
    if rgb in [(169, 140, 0), (255, 204, 34)]:
        return 8   # Vibrant Gold (Wasp body / Cyclops horns / Dizzy stars)
    if rgb in [(243, 216, 153), (255, 255, 255)]:
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
    if rgb in [(14, 21, 28), (0, 0, 0), (51, 51, 34)]:
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


def convert_image_to_bobs(img: Image.Image, raw_path: Path, msk_path: Path, white_raw_path: Path = None):
    w, h = img.size
    pixels = img.load()
    row_bytes = w // 8
    raw_bytes = bytearray()
    msk_bytes = bytearray()
    white_bytes = bytearray()

    for y in range(h):
        for plane in range(4):
            line = bytearray(row_bytes)
            mask = bytearray(row_bytes)
            white_line = bytearray(row_bytes)
            for x in range(w):
                r, g, b, a = pixels[x, y]
                idx = map_pixel_to_index(r, g, b, a)
                bit = (idx >> plane) & 1
                solid = 1 if idx != 0 else 0
                bp = x // 8
                shift = 7 - (x % 8)
                line[bp] |= (bit << shift)
                mask[bp] |= (solid << shift)
                # Pure white in 16-color palette is Color 3 ($0FFF):
                # Plane 0 = 1, Plane 1 = 1, Plane 2 = 0, Plane 3 = 0
                if plane in (0, 1) and solid:
                    white_line[bp] |= (1 << shift)
            raw_bytes.extend(line)
            msk_bytes.extend(mask)
            white_bytes.extend(white_line)

    raw_path.parent.mkdir(parents=True, exist_ok=True)
    with open(raw_path, "wb") as f:
        f.write(raw_bytes)
    with open(msk_path, "wb") as f:
        f.write(msk_bytes)
    if white_raw_path:
        with open(white_raw_path, "wb") as f:
            f.write(white_bytes)

    print(f"    Exported raw: {raw_path.name} ({len(raw_bytes)} bytes)")
    print(f"    Exported msk: {msk_path.name} ({len(msk_bytes)} bytes)")
    if white_raw_path:
        print(f"    Exported white raw: {white_raw_path.name} ({len(white_bytes)} bytes)")


def generate_dizzy_stars_png(out_png: Path):
    """Generate 4 animated frames of cute 16x16 orbiting dizzy stars (64x16 RGBA)."""
    img = Image.new('RGBA', (64, 16), (0, 0, 0, 0))

    def draw_star5(cel, cx, cy):
        # 5x5 cartoon sparkling star
        for dx, dy in [(0, -2), (0, 2), (-2, 0), (2, 0), (-1, -1), (1, -1), (-1, 1), (1, 1)]:
            x, y = cx + dx, cy + dy
            if 0 <= x < 16 and 0 <= y < 16: cel[y][x] = 2  # outline
        for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
            x, y = cx + dx, cy + dy
            if 0 <= x < 16 and 0 <= y < 16: cel[y][x] = 8  # gold
        if 0 <= cx < 16 and 0 <= cy < 16: cel[cy][cx] = 3  # white center

    def draw_star3(cel, cx, cy):
        # 3x3 cartoon star
        for dx, dy in [(-1, -1), (1, -1), (-1, 1), (1, 1)]:
            x, y = cx + dx, cy + dy
            if 0 <= x < 16 and 0 <= y < 16: cel[y][x] = 2  # outline
        for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
            x, y = cx + dx, cy + dy
            if 0 <= x < 16 and 0 <= y < 16: cel[y][x] = 8  # gold
        if 0 <= cx < 16 and 0 <= cy < 16: cel[cy][cx] = 3  # white center

    def draw_dot(cel, cx, cy):
        if 0 <= cx < 16 and 0 <= cy < 16: cel[cy][cx] = 3  # sparkle glint

    # Elliptical orbit positions across top of 16x16 box (y = 1..6)
    configs = [
        ((3, 3), (12, 3), (7, 1)),   # Frame 0: Star 1 left, Star 2 right, Dot top
        ((6, 2), (10, 5), (13, 3)),  # Frame 1: Star 1 top-mid, Star 2 bot-right, Dot right
        ((12, 3), (3, 4), (8, 5)),   # Frame 2: Star 1 right, Star 2 left, Dot bottom
        ((9, 4), (5, 2), (2, 3))     # Frame 3: Star 1 bot-mid, Star 2 top-left, Dot left
    ]

    for f_idx, (s1, s2, dot) in enumerate(configs):
        cel = [[0] * 16 for _ in range(16)]
        draw_star5(cel, s1[0], s1[1])
        draw_star3(cel, s2[0], s2[1])
        draw_dot(cel, dot[0], dot[1])

        bx = f_idx * 16
        for y in range(16):
            for x in range(16):
                idx = cel[y][x]
                if idx > 0:
                    rgb = PAL_8BIT[idx]
                    img.putpixel((bx + x, y), (rgb[0], rgb[1], rgb[2], 255))

    out_png.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_png)
    print(f"  Generated dizzy stars PNG: {out_png} ({img.size[0]}x{img.size[1]})")
    return img


def create_dizzy_preview(img: Image.Image, out_path: Path):
    """Generate scaled preview sheet for dizzy stars."""
    scale = 4
    w, h = img.size
    preview = Image.new('RGBA', (w * scale + 20, h * scale + 35), (20, 22, 30, 255))
    draw = ImageDraw.Draw(preview)
    draw.text((10, 6), "Dizzy Stars (Stunned Phase Orbit)", fill=(220, 210, 170, 255))

    for f in range(4):
        bx = f * 16
        cel_im = img.crop((bx, 0, bx + 16, 16))
        scaled_cel = cel_im.resize((16 * scale, 16 * scale), Image.NEAREST)
        x_pos = 10 + f * (16 * scale + 2)
        draw.rectangle([x_pos - 1, 23, x_pos + 16 * scale, 24 + 16 * scale], outline=(50, 55, 75, 255), fill=(10, 12, 18, 255))
        preview.paste(scaled_cel, (x_pos, 24), scaled_cel)

    preview.save(out_path)
    print(f"  Exported dizzy preview sheet: {out_path}")


def main():
    print("=== Converting Enemy & Dizzy Stars Assets ===")

    # 1. Enemies Walk Animations (64x128, 8 enemy types x 4 walk frames)
    src_enemies_png = PROJECT_ROOT / "assets/graphics/enemies/enemies_16x16.png"
    out_enemies_raw = PROJECT_ROOT / "assets/graphics/enemies/enemies_64x128.raw"
    out_enemies_msk = PROJECT_ROOT / "assets/graphics/enemies/enemies_64x128.msk"
    out_enemies_white = PROJECT_ROOT / "assets/graphics/enemies/enemies_64x128_white.raw"

    if not src_enemies_png.exists():
        print(f"Error: {src_enemies_png} does not exist!")
        return

    print(f"[*] Converting enemy spritesheet: {src_enemies_png.name}")
    enemies_img = Image.open(src_enemies_png).convert("RGBA")
    assert enemies_img.size == (64, 128), f"Expected 64x128 PNG, got {enemies_img.size}"
    convert_image_to_bobs(enemies_img, out_enemies_raw, out_enemies_msk, out_enemies_white)

    # 2. Dizzy Stars Animation (64x16, 4 frames of 16x16 orbiting stars)
    dizzy_png = PROJECT_ROOT / "assets/graphics/enemies/dizzy_stars_64x16.png"
    out_dizzy_raw = PROJECT_ROOT / "assets/graphics/enemies/dizzy_stars_64x16.raw"
    out_dizzy_msk = PROJECT_ROOT / "assets/graphics/enemies/dizzy_stars_64x16.msk"
    dizzy_preview = PROJECT_ROOT / "assets/graphics/enemies/dizzy_stars_preview.png"

    if dizzy_png.exists():
        print(f"[*] Loading existing dizzy stars PNG: {dizzy_png.name}")
        dizzy_img = Image.open(dizzy_png).convert("RGBA")
    else:
        print(f"[*] Generating dizzy stars PNG: {dizzy_png.name}")
        dizzy_img = generate_dizzy_stars_png(dizzy_png)

    assert dizzy_img.size == (64, 16), f"Expected 64x16 PNG, got {dizzy_img.size}"
    convert_image_to_bobs(dizzy_img, out_dizzy_raw, out_dizzy_msk)
    create_dizzy_preview(dizzy_img, dizzy_preview)

    print("=== Enemy Assets Conversion Complete! ===")


if __name__ == "__main__":
    main()
