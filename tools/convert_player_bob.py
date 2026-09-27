#!/usr/bin/env python3
"""
tools/convert_player_bob.py
---------------------------
Generates the 24-sprite player master spritesheet and converts it into
4-bitplane interleaved raw graphics, mask, and pure-white flash files for Blitter Objects (BOBs):
  - assets/graphics/sprites/player_master_128x144.png (Reference PNG)
  - assets/graphics/sprites/player_bobs_128x144.raw (9,216 bytes, 24 frames)
  - assets/graphics/sprites/player_bobs_128x144.msk (9,216 bytes, 24 frames)
  - assets/graphics/sprites/player_bobs_128x144_white.raw (9,216 bytes, 24 frames)
  - assets/graphics/sprites/player_bobs_preview.png (Visual contact sheet)

Layout (24 sprites in total, 6 rows x 4 frames):
  Row 0 (frames  0..3 ): IDLE (facing right)
  Row 1 (frames  4..7 ): WALK (facing right)
  Row 2 (frames  8..11): ATTACK (facing right, with full extended cane hook)
  Row 3 (frames 12..15): DEATH (facing right, Row 9 collapse sequence)
  Row 4 (frames 16..19): UP/DOWN LADDER (rear view climb sequence)
  Row 5 (frames 20..23): FALLING (flailing fall sequence)

Left-facing sprites are generated / flipped dynamically at runtime in the Amiga engine,
cutting asset memory down to 24 sprites.

Format:
  Width:  128 pixels (4 frames x 32 pixels cell storage, 24px active content)
          = 8 words = 16 bytes per plane row.
  Height: 144 scanlines (6 rows x 24 scanlines).
  Format: 4-bitplane interleaved:
          Scanline Y: Plane 0 (16B), Plane 1 (16B), Plane 2 (16B), Plane 3 (16B) = 64 bytes/row.
  Total size: 144 * 64 = 9,216 bytes.
"""

import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

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

W, H = 24, 24
CELL_W = 32


class Cel24:
    """24x24 pixel grid with color indices 0..15."""
    def __init__(self):
        self.g = [[0] * W for _ in range(H)]

    def mirror(self):
        """Horizontal flip (facing opposite direction)."""
        m = Cel24()
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

    # 5. Boots / Earth / Cane wood:
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
    """
    Load the 4x12 cells from player-animation-20x24.png and expand to 24x24 cels.
    Completes the cane hook artwork in attack cels (Row 7, Cels 0 & 1).
    """
    img = Image.open(sheet_path).convert('RGBA')
    cels = {}
    for r in range(12):
        for c in range(4):
            cel = Cel24()
            # Default offset: shift 20px art right by 2 to center 14px body in 24px cel
            ox = 2
            if r == 7 and c in (0, 1):
                # Attack strike cels: shift right by 4 so cane hook has 4 pixels on the left
                ox = 4

            for y in range(24):
                for x in range(20):
                    p = img.getpixel((c * 20 + x, r * 24 + y))
                    cel.g[y][ox + x] = quantize_pixel(p[0], p[1], p[2], p[3])

            # Complete the curved cane handle hook for strike cels:
            if r == 7 and c in (0, 1):
                # Scanline 4: top curve dark outline (x=1..4)
                cel.g[4][1] = 2
                cel.g[4][2] = 2
                cel.g[4][3] = 2
                cel.g[4][4] = 2
                # Scanline 5: curve loop on left (outline 2, wood 10)
                cel.g[5][0] = 2
                cel.g[5][1] = 10
                cel.g[5][2] = 10
                cel.g[5][3] = 10
                # Scanline 6: hook tip pointing down
                cel.g[6][0] = 2
                cel.g[6][1] = 10
                cel.g[6][2] = 2
                cel.g[6][3] = 2
                # Scanline 7: rounded tip outline
                cel.g[7][1] = 2

            cels[(r, c)] = cel
    return cels


def assemble_24_player_frames(cels):
    """
    Assemble exactly 24 animation frames for the player (6 rows x 4 frames):
      Row 0 (frames  0..3 ): IDLE (facing right)
      Row 1 (frames  4..7 ): WALK (facing right)
      Row 2 (frames  8..11): ATTACK (facing right)
      Row 3 (frames 12..15): DEATH (facing right)
      Row 4 (frames 16..19): UP/DOWN LADDER (climb sequence)
      Row 5 (frames 20..23): FALLING
    """
    frames = [Cel24() for _ in range(24)]

    # Row 0 (0..3): Idle right (Row 0 cels mirrored)
    for c in range(4):
        frames[0 + c] = cels[(0, c)].mirror()

    # Row 1 (4..7): Walk right (Row 1 cels mirrored)
    for c in range(4):
        frames[4 + c] = cels[(1, c)].mirror()

    # Row 2 (8..11): Attack right (Row 7 cels mirrored)
    frames[8]  = cels[(7, 2)].mirror()  # Wind-up overhead
    frames[9]  = cels[(7, 0)].mirror()  # Forward swing extension with complete cane hook!
    frames[10] = cels[(7, 3)].mirror()  # Follow-through recovery
    frames[11] = cels[(7, 1)].mirror()  # Mid swing return

    # Row 3 (12..15): Death right (Row 9 cels mirrored)
    frames[12] = cels[(9, 0)].mirror()  # Slumped
    frames[13] = cels[(9, 1)].mirror()  # Buckling
    frames[14] = cels[(9, 2)].mirror()  # Pitching forward
    frames[15] = cels[(9, 3)].mirror()  # Collapsed flat

    # Row 4 (16..19): Ladder climb (Row 11 rear view)
    frames[16] = cels[(11, 0)]          # Neutral pose (Ladder idle)
    frames[17] = cels[(11, 1)]          # Reach left
    frames[18] = cels[(11, 0)]          # Neutral pose
    frames[19] = cels[(11, 2)]          # Reach right

    # Row 5 (20..23): Falling (Row 2 flailing frames mirrored)
    frames[20] = cels[(2, 2)].mirror()
    frames[21] = cels[(2, 3)].mirror()
    frames[22] = cels[(2, 2)].mirror()
    frames[23] = cels[(2, 3)].mirror()

    return frames


def export_master_png(frames, out_path: Path):
    """
    Export assets/graphics/sprites/player_master_128x144.png (128x144 RGBA).
    6 rows x 4 columns of 32x24 cells (24px active art, 8px transparent padding).
    """
    img = Image.new('RGBA', (128, 144), (0, 0, 0, 0))
    for r in range(6):
        for c in range(4):
            cel = frames[r * 4 + c]
            bx = c * CELL_W
            by = r * H
            for y in range(H):
                for x in range(W):
                    idx = cel.g[y][x]
                    if idx > 0:
                        rgb = PAL_8BIT[idx]
                        img.putpixel((bx + x, by + y), (rgb[0], rgb[1], rgb[2], 255))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    print(f"  Exported master PNG: {out_path} ({img.size[0]}x{img.size[1]})")


def load_frames_from_master_png(master_path: Path):
    """Load frames directly from player_master_128x144.png if user edited it."""
    img = Image.open(master_path).convert('RGBA')
    w, h = img.size
    assert w == 128 and h == 144, f"Expected 128x144 master PNG, got {w}x{h}"
    frames = []
    for r in range(6):
        for c in range(4):
            cel = Cel24()
            bx = c * CELL_W
            by = r * H
            for y in range(H):
                for x in range(W):
                    p = img.getpixel((bx + x, by + y))
                    cel.g[y][x] = quantize_pixel(p[0], p[1], p[2], p[3])
            frames.append(cel)
    return frames


def build_bob_data(frames):
    """
    Encode 24 frames into 4-bitplane interleaved raw, mask, and pure-white flash streams.
    Width: 128 px (4 frames of 32px cell storage, 24px active content).
    Height: 144 scanlines (6 rows of 24px).
    Each scanline: Plane 0 (16B), Plane 1 (16B), Plane 2 (16B), Plane 3 (16B) = 64 bytes.
    Total size: 144 * 64 = 9,216 bytes.
    """
    assert len(frames) == 24, f"Expected 24 frames, got {len(frames)}"

    num_frame_rows = 6
    total_scanlines = num_frame_rows * H  # 144 scanlines

    raw_bytes = bytearray()
    msk_bytes = bytearray()
    white_bytes = bytearray()

    sheet_width = 4 * CELL_W  # 128 pixels
    row_bytes = sheet_width // 8  # 16 bytes per plane row

    for f_row in range(num_frame_rows):
        row_cels = [frames[f_row * 4 + c] for c in range(4)]
        for y in range(H):
            for plane in range(4):
                line = bytearray(row_bytes)
                mask = bytearray(row_bytes)
                white_line = bytearray(row_bytes)
                for col in range(4):
                    cel = row_cels[col]
                    for x in range(W):
                        idx = cel.g[y][x]
                        bit = (idx >> plane) & 1
                        solid = 1 if idx != 0 else 0
                        px = col * CELL_W + x
                        bp = px // 8
                        shift = 7 - (px % 8)
                        line[bp] |= (bit << shift)
                        mask[bp] |= (solid << shift)
                        # Pure white in 16-color palette is Color 3 ($0FFF):
                        # Plane 0 = 1, Plane 1 = 1, Plane 2 = 0, Plane 3 = 0
                        if plane in (0, 1) and solid:
                            white_line[bp] |= (1 << shift)
                raw_bytes.extend(line)
                msk_bytes.extend(mask)
                white_bytes.extend(white_line)

    expected_size = total_scanlines * 4 * row_bytes  # 144 * 64 = 9,216
    assert len(raw_bytes) == expected_size, f"Expected {expected_size} bytes, got {len(raw_bytes)}"
    assert len(msk_bytes) == expected_size
    assert len(white_bytes) == expected_size
    return raw_bytes, msk_bytes, white_bytes


def create_preview_sheet(frames, out_path: Path):
    """Generate contact sheet showing all 24 frames with category labels."""
    row_titles = [
        "Row 0: IDLE (Right)",
        "Row 1: WALK (Right)",
        "Row 2: ATTACK (Right)",
        "Row 3: DEATH (Right)",
        "Row 4: LADDER (Climb)",
        "Row 5: FALLING"
    ]

    cols = 4
    rows = 6
    scale = 3
    card_w = 32 * scale
    card_h = 24 * scale + 24
    sheet_w = 160 + cols * card_w + 20
    sheet_h = rows * card_h + 30

    img = Image.new('RGBA', (sheet_w, sheet_h), (20, 22, 30, 255))
    draw = ImageDraw.Draw(img)

    for r in range(rows):
        y_base = 20 + r * card_h
        # Draw category title on left margin
        draw.text((15, y_base + 20), row_titles[r], fill=(220, 210, 170, 255))

        for c in range(cols):
            f_idx = r * cols + c
            x_base = 160 + c * card_w

            # Cel box
            draw.rectangle(
                [x_base + 4, y_base + 4, x_base + 24 * scale + 6, y_base + 24 * scale + 6],
                outline=(50, 55, 75, 255),
                fill=(12, 14, 20, 255)
            )

            cel_im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
            for py in range(H):
                for px in range(W):
                    idx = frames[f_idx].g[py][px]
                    if idx > 0:
                        rgb = PAL_8BIT[idx]
                        cel_im.putpixel((px, py), (rgb[0], rgb[1], rgb[2], 255))

            spr = cel_im.resize((24 * scale, 24 * scale), Image.NEAREST)
            img.paste(spr, (x_base + 5, y_base + 5), spr)
            draw.text((x_base + 6, y_base + 24 * scale + 8), f"Frame {f_idx}", fill=(160, 165, 185, 255))

    img.save(out_path)
    print(f"  Exported preview contact sheet: {out_path} ({sheet_w}x{sheet_h})")


def main():
    print("=== Converting Player BOB Assets (24 Frames, 128x144) ===")
    src_png = PROJECT_ROOT / "assets/graphics/sprites/player-animation-20x24.png"
    master_png = PROJECT_ROOT / "assets/graphics/sprites/player_master_128x144.png"
    out_raw = PROJECT_ROOT / "assets/graphics/sprites/player_bobs_128x144.raw"
    out_msk = PROJECT_ROOT / "assets/graphics/sprites/player_bobs_128x144.msk"
    out_white = PROJECT_ROOT / "assets/graphics/sprites/player_bobs_128x144_white.raw"
    preview_png = PROJECT_ROOT / "assets/graphics/sprites/player_bobs_preview.png"

    if master_png.exists():
        print(f"[*] Loading from existing player master PNG: {master_png}")
        frames = load_frames_from_master_png(master_png)
    else:
        if not src_png.exists():
            print(f"Error: {src_png} does not exist!")
            sys.exit(1)
        print(f"[*] Assembling 24 frames from source spritesheet: {src_png}")
        cels = load_cels_from_sheet(src_png)
        frames = assemble_24_player_frames(cels)
        export_master_png(frames, master_png)

    raw_bytes, msk_bytes, white_bytes = build_bob_data(frames)

    out_raw.parent.mkdir(parents=True, exist_ok=True)
    with open(out_raw, "wb") as f:
        f.write(raw_bytes)
    with open(out_msk, "wb") as f:
        f.write(msk_bytes)
    with open(out_white, "wb") as f:
        f.write(white_bytes)

    print(f"  Exported player BOB raw: {out_raw} ({len(raw_bytes)} bytes)")
    print(f"  Exported player BOB msk: {out_msk} ({len(msk_bytes)} bytes)")
    print(f"  Exported player BOB white: {out_white} ({len(white_bytes)} bytes)")

    create_preview_sheet(frames, preview_png)
    print("=== Player Assets Conversion Complete! ===")


if __name__ == "__main__":
    main()
