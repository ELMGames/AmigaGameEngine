#!/usr/bin/env python3
"""
tools/convert_player_bob.py
---------------------------
Converts assets/graphics/sprites/player-animation-16x24.png (64x288 RGBA)
into 4-bitplane interleaved raw graphics and mask files for Blitter Objects (BOBs):
  - assets/graphics/sprites/player_bobs_64x576.raw (18,432 bytes, 96 frames)
  - assets/graphics/sprites/player_bobs_64x576.msk (18,432 bytes, 96 frames)

Layout:
  Width:  64 pixels (4 frames x 16 pixels) = 4 words = 8 bytes per plane.
  Height: 576 scanlines (24 rows x 24 scanlines).
          Rows  0..11: Player 1 / Cole (Frames  0..47)
          Rows 12..23: Player 2 / Price (Frames 48..95)
  Format: 4-bitplane interleaved:
          Scanline Y: Plane 0 (8B), Plane 1 (8B), Plane 2 (8B), Plane 3 (8B) = 32 bytes/row.
  Total size: 576 * 32 = 18,432 bytes.
"""

import sys
from pathlib import Path
from PIL import Image, ImageDraw

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# Vibrant 16-color OCS palette (matches export_level.py & FourSeasons tileset)
PALETTE_OCS = [
    (0, 0, 0),      # 0: Transparent ($0000)
    (1, 11, 14),    # 1: 0x1BE Vibrant Cyan (Water)
    (3, 3, 2),      # 2: 0x332 Dark outline
    (15, 15, 15),   # 3: 0xFFF White highlight
    (2, 7, 4),      # 4: 0x274 Forest Green
    (1, 9, 3),      # 5: 0x193 Grass Green
    (15, 9, 1),     # 6: 0xF91 Vibrant Orange
    (2, 5, 12),     # 7: 0x25C Deep Blue
    (15, 12, 2),    # 8: 0xFC2 Vibrant Gold
    (13, 10, 6),    # 9: 0xDA6 Light Wood / Sand
    (11, 7, 4),     # 10: 0xB74 Stone / Earth
    (8, 1, 3),      # 11: 0x813 Rich Maroon / Boots
    (13, 1, 2),     # 12: 0xD12 Vibrant Red
    (8, 9, 11),     # 13: 0x89B Slate Grey / Suit
    (1, 7, 7),      # 14: 0x177 Vibrant Teal / Visor
    (12, 10, 8)     # 15: 0xCA8 Peach / Skin
]

PAL_8BIT = [(r * 17, g * 17, b * 17) for r, g, b in PALETTE_OCS]

W, H = 16, 24


class Cel16:
    """16x24 pixel grid with color indices 0..15."""
    def __init__(self):
        self.g = [[0] * W for _ in range(H)]

    def mirror(self):
        """Horizontal flip (facing left)."""
        m = Cel16()
        for y in range(H):
            for x in range(W):
                m.g[y][W - 1 - x] = self.g[y][x]
        return m


def quantize_pixel(r: int, g: int, b: int, a: int) -> int:
    """Map RGBA pixel to 16-color playfield palette."""
    if a <= 128:
        return 0

    # Semantic assignments for player sprite features:
    # 1. Dark outline / shadow:
    if max(r, g, b) < 45:
        return 2   # 0x332 Dark outline

    # 2. Visor / Cyan lights:
    if g > 70 and b > 70 and r < 40:
        if g > 130 or b > 130:
            return 1   # 0x1BE Vibrant Cyan
        return 14      # 0x177 Vibrant Teal

    # 3. Peach skin:
    if r > 180 and g > 130 and b > 90 and r > g:
        return 15  # 0xCA8 Peach / Warm Skin

    # 4. White glints:
    if r > 210 and g > 210 and b > 210:
        return 3   # 0xFFF White highlight

    # 5. Boots / Earth:
    if r > 80 and g > 50 and b < 50:
        return 10  # 0xB74 Stone / Earth

    # 6. Backpack / Amber:
    if r > 180 and g > 100 and b < 60:
        return 6   # 0xF91 Vibrant Orange

    # 7. Rich Maroon:
    if r > 90 and g < 45 and b < 50:
        return 11  # 0x813 Rich Maroon

    # 8. Suit slate grey:
    if abs(r - g) < 25 and abs(g - b) < 25 and 70 < r < 180:
        return 13  # 0x89B Slate Grey

    # Fallback to Euclidean distance:
    best_dist = 99999999
    best_idx = 2
    for idx, (pr, pg, pb) in enumerate(PAL_8BIT[1:], start=1):
        d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if d < best_dist:
            best_dist = d
            best_idx = idx
    return best_idx


def load_cels_from_sheet(sheet_path: Path):
    """Load the 4x12 cells from the 16x24 packed spritesheet."""
    img = Image.open(sheet_path).convert('RGBA')
    cels = {}
    for r in range(12):
        for c in range(4):
            cel = Cel16()
            for y in range(H):
                for x in range(W):
                    p = img.getpixel((c * W + x, r * H + y))
                    cel.g[y][x] = quantize_pixel(p[0], p[1], p[2], p[3])
            cels[(r, c)] = cel
    return cels


def assemble_player_frames(cels):
    """
    Assemble the 48 animation frames for a player character according to
    Amiga engine constants (const.asm):
      0..3   : Idle right (4 frames, faces right)
      4..11  : Walk right (8 frames, walks right)
      12..15 : Carry right (4 frames)
      16..19 : Ladder climb (4 frames, rear view; 16 is ladder idle neutral)
      20..21 : Push right (2 frames)
      22..23 : Push left (2 frames)
      24..27 : Slide / dash (4 frames)
      28..31 : Falling (2 alternating frames)
      32..35 : Idle left (4 frames, faces left)
      36..43 : Walk left (8 frames, walks left)
      44..47 : Fall left (4 frames, mirror of 28..31)
    """
    frames = [Cel16() for _ in range(48)]

    # 0..3: Idle right (mirrored Row 0, faces right)
    for c in range(4):
        frames[0 + c] = cels[(0, c)].mirror()

    # 4..11: Walk right (mirrored Row 1, 8 frames)
    for c in range(4):
        frames[4 + c] = cels[(1, c)].mirror()
        frames[8 + c] = cels[(1, c)].mirror()

    # 12..15: Carry right (Row 5 mirrored)
    for c in range(4):
        frames[12 + c] = cels[(5, c)].mirror()

    # 16..19: Ladder climb (Row 11 rear view)
    frames[16] = cels[(11, 0)]
    frames[17] = cels[(11, 1)]
    frames[18] = cels[(11, 0)]
    frames[19] = cels[(11, 2)]

    # 20..23: Push frames
    frames[20] = cels[(2, 0)]           # Push Left 1
    frames[21] = cels[(2, 0)].mirror()  # Push Right 1
    frames[22] = cels[(2, 1)].mirror()  # Push Right 2
    frames[23] = cels[(2, 1)]           # Push Left 2

    # 24..27: Slide / dash (Row 3 mirrored)
    for c in range(4):
        frames[24 + c] = cels[(3, c)].mirror()

    # 28..31: Falling (2-frame alternating: 28, 44, 28, 44)
    frames[28] = cels[(2, 2)].mirror()
    frames[29] = cels[(2, 2)]
    frames[30] = cels[(2, 2)].mirror()
    frames[31] = cels[(2, 2)]

    # 32..35: Idle left (unmirrored Row 0)
    for c in range(4):
        frames[32 + c] = cels[(0, c)]

    # 36..43: Walk left (unmirrored Row 1)
    for c in range(4):
        frames[36 + c] = cels[(1, c)]
        frames[40 + c] = cels[(1, c)]

    # 44..47: Fall left
    frames[44] = cels[(2, 2)]
    frames[45] = cels[(2, 2)].mirror()
    frames[46] = cels[(2, 2)]
    frames[47] = cels[(2, 2)].mirror()

    return frames


def build_bob_data(all_frames):
    """
    Encode 96 frames into 4-bitplane interleaved raw and mask streams.
    Width: 64 px (4 frames of 16px).
    Height: 576 scanlines (24 rows of 24px).
    Each scanline: Plane 0 (8B), Plane 1 (8B), Plane 2 (8B), Plane 3 (8B) = 32 bytes.
    """
    total_frames = len(all_frames)
    assert total_frames == 96, f"Expected 96 frames, got {total_frames}"

    num_frame_rows = total_frames // 4  # 24 rows
    total_scanlines = num_frame_rows * H  # 576 scanlines

    raw_bytes = bytearray()
    msk_bytes = bytearray()

    row_bytes = 64 // 8  # 8 bytes per plane row

    for f_row in range(num_frame_rows):
        row_cels = [all_frames[f_row * 4 + c] for c in range(4)]
        for y in range(H):
            for plane in range(4):
                line = bytearray(row_bytes)
                mask = bytearray(row_bytes)
                for col in range(4):
                    cel = row_cels[col]
                    for x in range(W):
                        idx = cel.g[y][x]
                        bit = (idx >> plane) & 1
                        solid = 1 if idx != 0 else 0
                        px = col * W + x
                        bp = px // 8
                        shift = 7 - (px % 8)
                        line[bp] |= (bit << shift)
                        mask[bp] |= (solid << shift)
                raw_bytes.extend(line)
                msk_bytes.extend(mask)

    assert len(raw_bytes) == 576 * 32
    assert len(msk_bytes) == 576 * 32
    return raw_bytes, msk_bytes


def create_preview_sheet(all_frames, out_path: Path):
    """Generate contact sheet showing all 96 frames with color labels."""
    cols = 8
    rows = 12
    cell_w, cell_h = 24, 32
    scale = 2
    sheet_w = cols * cell_w * scale
    sheet_h = rows * cell_h * scale

    img = Image.new('RGBA', (sheet_w, sheet_h), (25, 25, 35, 255))
    draw = ImageDraw.Draw(img)

    for f in range(len(all_frames)):
        col = f % cols
        row = f // cols
        x = col * cell_w * scale + 4
        y = row * cell_h * scale + 4

        draw.rectangle([x, y, x + 16 * scale + 2, y + 24 * scale + 2], outline=(60, 60, 80, 255))

        cel_im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        for py in range(H):
            for px in range(W):
                c = all_frames[f].g[py][px]
                if c > 0:
                    rgb = PAL_8BIT[c]
                    cel_im.putpixel((px, py), (rgb[0], rgb[1], rgb[2], 255))

        spr = cel_im.resize((16 * scale, 24 * scale), Image.NEAREST)
        img.paste(spr, (x + 1, y + 1), spr)
        draw.text((x + 2, y + 24 * scale + 3), f'{f}', fill=(220, 220, 200, 255))

    img.save(out_path)
    print(f"  Exported preview contact sheet: {out_path} ({sheet_w}x{sheet_h})")


def main():
    print("=== Converting Player to Blitter Object (BOB) Assets ===")
    src_png = PROJECT_ROOT / "assets/graphics/sprites/player-animation-16x24.png"
    out_raw = PROJECT_ROOT / "assets/graphics/sprites/player_bobs_64x576.raw"
    out_msk = PROJECT_ROOT / "assets/graphics/sprites/player_bobs_64x576.msk"
    preview_png = PROJECT_ROOT / "assets/graphics/sprites/player_bobs_preview.png"

    if not src_png.exists():
        print(f"Error: {src_png} does not exist!")
        sys.exit(1)

    cels = load_cels_from_sheet(src_png)
    p1_frames = assemble_player_frames(cels)

    # 96 frames: 48 for Player 1, 48 for Player 2
    # In Alien Containment, both players share the same animation set or palette variant
    all_frames = p1_frames + p1_frames

    raw_bytes, msk_bytes = build_bob_data(all_frames)

    out_raw.parent.mkdir(parents=True, exist_ok=True)
    with open(out_raw, "wb") as f:
        f.write(raw_bytes)
    with open(out_msk, "wb") as f:
        f.write(msk_bytes)

    print(f"  Exported player BOB raw: {out_raw} ({len(raw_bytes)} bytes)")
    print(f"  Exported player BOB msk: {out_msk} ({len(msk_bytes)} bytes)")

    create_preview_sheet(all_frames, preview_png)
    print("=== Step 1: Asset Pipeline Conversion Complete! ===")


if __name__ == "__main__":
    main()
