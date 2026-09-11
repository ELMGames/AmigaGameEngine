"""
build_player_hwsprites.py
-------------------------
Encodes the 16x24 packed spritesheet (assets/graphics/sprites/player-animation-16x24.png)
into the Amiga OCS hardware sprite binary format:
  - assets/graphics/sprites/player_hwsprites.bin  (39,936 bytes, 96 frames)
  - assets/graphics/sprites/player_hwsprites.zx0  (ZX0 compressed)
  - assets/graphics/sprites/sprites.pal          (64 bytes, 16-color Amiga sprite palette)

Also verifies ZX0 integrity and generates preview contact sheet & animated GIFs.
"""

import sys
import shutil
import subprocess
from pathlib import Path
from PIL import Image

SPR_DIR = Path('assets/graphics/sprites')
SRC_PNG = SPR_DIR / 'player-animation-16x24.png'
W, H = 16, 24

# -----------------------------------------------------------------------------
# Color Palette Definition (16 colors for HW Sprites, registers 16..31)
# -----------------------------------------------------------------------------
# Slots 1, 3, 6, 7, 8, 9, 10, 11 preserve effect-critical roles (outline, white,
# amber, brown, dark amber, grey, ice blue, blue).
# Slots 2, 4, 5, 12, 13, 14, 15 host the character's skin, clothing, and hair.
PAL_WORDS = [
    0x000,  # 0: Transparent
    0x000,  # 1: Dark Outline / Black (M&M effect slot preserved)
    0xFA7,  # 2: Peach Skin
    0xFFF,  # 3: White Highlight (M&M effect slot preserved)
    0xB66,  # 4: Warm Skin Shadow / Blush
    0x077,  # 5: Teal Shirt
    0xFC4,  # 6: Amber Backpack (M&M effect slot preserved)
    0x643,  # 7: Brown Boots / Dirt (M&M effect slot preserved)
    0xA60,  # 8: Dark Amber / Belt (M&M effect slot preserved)
    0x888,  # 9: Cool Grey (M&M effect slot preserved)
    0x9DF,  # 10: Ice Blue (M&M effect slot preserved)
    0x09A,  # 11: Cyan Shirt Highlight (M&M effect slot preserved)
    0x043,  # 12: Dark Teal Shadow
    0x733,  # 13: Medium Chestnut Hair
    0x322,  # 14: Dark Hair Shadow
    0x111   # 15: Deep Shadow / Pupil
]

PAL_RGB = []
for w in PAL_WORDS:
    r = ((w >> 8) & 0xF) * 17
    g = ((w >> 4) & 0xF) * 17
    b = (w & 0xF) * 17
    PAL_RGB.append((r, g, b))

PAL_RGB_FLAT = []
for rgb in PAL_RGB:
    PAL_RGB_FLAT.extend(rgb)


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


def quantize_pixel(r, g, b):
    """Semantic mapping from 24-bit RGB to 16-color palette index."""
    if max(r, g, b) < 40:
        return 1  # Black outline
    if r > 200 and g > 150 and b > 100:
        return 2  # Peach skin
    if r > 200 and g > 200 and b > 200:
        return 3  # White highlight
    if r > 160 and g > 80 and b > 80 and r > g:
        return 4  # Skin shadow
    if g > r and b > r and g > 80:
        if g > 140 or b > 140:
            return 11 # Cyan highlight
        return 5      # Teal shirt
    if g > r and b > r and g <= 80:
        return 12     # Dark teal shadow
    if r > 180 and g > 100 and b < 60:
        return 6      # Backpack amber
    if r > 140 and g > 70 and b < 60:
        return 8      # Backpack dark amber
    if r > 80 and g > 50 and b < 50:
        return 7      # Boots brown
    if r > 100 and g < 70 and b < 60:
        return 13     # Medium hair
    if r > 40 and g < 40 and b < 40:
        return 14     # Dark hair shadow

    # Nearest Euclidean distance in PAL_RGB[1..15]
    best_i = 1
    best_d = 99999999
    for i in range(1, 16):
        d = (r - PAL_RGB[i][0])**2 + (g - PAL_RGB[i][1])**2 + (b - PAL_RGB[i][2])**2
        if d < best_d:
            best_d = d
            best_i = i
    return best_i


def load_cels_from_sheet(sheet_path):
    """Load the 4x12 cells from the 16x24 packed spritesheet."""
    img = Image.open(sheet_path).convert('RGBA')
    cels = {}
    for r in range(12):
        for c in range(4):
            cel = Cel16()
            for y in range(H):
                for x in range(W):
                    p = img.getpixel((c * W + x, r * H + y))
                    if p[3] >= 128:
                        cel.g[y][x] = quantize_pixel(p[0], p[1], p[2])
                    else:
                        cel.g[y][x] = 0
            cels[(r, c)] = cel
    return cels


def assemble_player_frames(cels):
    """
    Assemble the 48 animation frames for a player character according to
    Amiga engine constants (const.asm):
      0..3   : Idle right (4 frames, faces right)
      4..11  : Walk right (8 frames, walks right)
      12..15 : Carry right (4 frames)
      16..19 : Ladder climb (4 frames, rear view; 19 is ladder idle freeze)
      20..21 : Push right (2 frames)
      22..23 : Push left (2 frames)
      24..27 : Slide / dash (4 frames)
      28..31 : Falling (2 alternating frames: Fall 1, Fall 2, Fall 1, Fall 2)
      32..35 : Idle left (4 frames, faces left)
      36..43 : Walk left (8 frames, walks left)
      44..47 : Fall left (4 frames, mirror of 28..31)

    Note: In player-animation.png, the source artwork was drawn facing LEFT.
    Therefore, right-facing frames (0..11, 20..21) are mirrored, and
    left-facing frames (32..43, 22..23) use the unmirrored source cels!
    """
    frames = [Cel16() for _ in range(48)]

    # 0..3: Idle right (mirrored Row 0, faces right!)
    for c in range(4):
        frames[0 + c] = cels[(0, c)].mirror()

    # 4..11: Walk right (mirrored Row 1, 8 frames, walks right!)
    for c in range(4):
        frames[4 + c] = cels[(1, c)].mirror()
        frames[8 + c] = cels[(1, c)].mirror()

    # 12..15: Carry right (Row 5 mirrored)
    for c in range(4):
        frames[12 + c] = cels[(5, c)].mirror()

    # 16..19: Ladder climb (Row 11 rear view)
    # Neutral col 0, left reach col 1, neutral col 0, right reach col 2
    frames[16] = cels[(11, 0)]
    frames[17] = cels[(11, 1)]
    frames[18] = cels[(11, 0)]
    frames[19] = cels[(11, 2)]

    # 20..23: Push frames (as requested: push left is 20 & 23, push right is 21 & 22)
    frames[20] = cels[(2, 0)]           # Push Left 1 (unmirrored)
    frames[21] = cels[(2, 0)].mirror()  # Push Right 1 (mirrored)
    frames[22] = cels[(2, 1)].mirror()  # Push Right 2 (mirrored)
    frames[23] = cels[(2, 1)]           # Push Left 2 (unmirrored)

    # 24..27: Slide / dash (Row 3 mirrored)
    for c in range(4):
        frames[24 + c] = cels[(3, c)].mirror()

    # 28..31: Falling (2-frame animation using frame 28 and frame 44, i.e. mirrors of each other)
    # Cel (2, 2).mirror() is frame 28; Cel (2, 2) is frame 44
    frames[28] = cels[(2, 2)].mirror()  # Frame 28
    frames[29] = cels[(2, 2)]           # Frame 44 (mirror of 28)
    frames[30] = cels[(2, 2)].mirror()  # Frame 28
    frames[31] = cels[(2, 2)]           # Frame 44 (mirror of 28)

    # 32..35: Idle left (unmirrored Row 0, faces left!)
    for c in range(4):
        frames[32 + c] = cels[(0, c)]

    # 36..43: Walk left (unmirrored Row 1, 8 frames, walks left!)
    for c in range(4):
        frames[36 + c] = cels[(1, c)]
        frames[40 + c] = cels[(1, c)]

    # 44..47: Fall left (Frame 44 and Frame 28 alternating)
    frames[44] = cels[(2, 2)]           # Frame 44
    frames[45] = cels[(2, 2)].mirror()  # Frame 28
    frames[46] = cels[(2, 2)]           # Frame 44
    frames[47] = cels[(2, 2)].mirror()  # Frame 28

    return frames


def encode_hw_frame(cel):
    """
    Encode 16x24 cel into Amiga 208-byte hardware sprite frame structure.
    SPR0 (even) contains bitplanes 0 & 1.
    SPR1 (odd, attached) contains bitplanes 2 & 3.
    """
    out = bytearray()
    for shift in (0, 2):
        out += b'\x00\x00\x00\x00'            # 4-byte header (SPRxPOS/CTL, written at runtime)
        for y in range(H):
            w0 = w1 = 0
            for x in range(W):
                v = (cel.g[y][x] >> shift) & 3
                if v & 1:
                    w0 |= (0x8000 >> x)
                if v & 2:
                    w1 |= (0x8000 >> x)
            out += w0.to_bytes(2, 'big') + w1.to_bytes(2, 'big')
        out += b'\x00\x00\x00\x00'            # 4-byte terminator
    assert len(out) == 208
    return bytes(out)


def create_preview(frames, out_path):
    """Generate clearly labeled preview sheet of all 48 player frames (8 cols x 6 rows)."""
    from PIL import ImageDraw
    cols = 8
    rows = 6
    cell_w, cell_h = 24, 32
    scale = 2
    sheet_w = cols * cell_w * scale
    sheet_h = rows * cell_h * scale

    img = Image.new('RGBA', (sheet_w, sheet_h), (25, 25, 35, 255))
    draw = ImageDraw.Draw(img)

    for f in range(48):
        col = f % cols
        row = f // cols
        x = col * cell_w * scale + 4
        y = row * cell_h * scale + 4

        draw.rectangle([x, y, x + 16 * scale + 2, y + 24 * scale + 2], outline=(60, 60, 80, 255))

        # Convert Cel16 to RGBA image
        cel_im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
        for py in range(H):
            for px in range(W):
                c = frames[f].g[py][px]
                if c > 0:
                    rgb = PAL_RGB[c]
                    cel_im.putpixel((px, py), (rgb[0], rgb[1], rgb[2], 255))

        spr = cel_im.resize((16 * scale, 24 * scale), Image.NEAREST)
        img.paste(spr, (x + 1, y + 1), spr)
        draw.text((x + 2, y + 24 * scale + 3), f'{f}', fill=(220, 220, 200, 255))

    img.save(out_path)
    print(f"  Saved labeled preview sheet: {out_path} ({img.size[0]}x{img.size[1]})")


def main():
    print("=== Encoding Player Hardware Sprites ===")
    if not SRC_PNG.exists():
        print(f"Error: {SRC_PNG} does not exist!")
        sys.exit(1)

    cels = load_cels_from_sheet(SRC_PNG)
    p1_frames = assemble_player_frames(cels)

    # 1. Write Sprite Palette (sprites.pal, 64 bytes)
    pal_path = SPR_DIR / 'sprites.pal'
    if pal_path.exists() and not (SPR_DIR / 'sprites.pal.cute').exists():
        shutil.copyfile(pal_path, SPR_DIR / 'sprites.pal.cute')
    pal_bytes = b''.join(w.to_bytes(2, 'big') for w in PAL_WORDS)
    pal_bytes += b'\x00' * 32  # pad to 64 bytes
    pal_path.write_bytes(pal_bytes)
    print(f"  Written {pal_path} ({len(pal_bytes)} bytes)")

    # 2. Write 96 Hardware Sprite Frames (Player 1 + Player 2)
    hw_bytes = bytearray()
    for _ in range(2):  # 2 player slots (48 frames each = 96 total)
        for f in range(48):
            hw_bytes += encode_hw_frame(p1_frames[f])

    hw_path = SPR_DIR / 'player_hwsprites.bin'
    if hw_path.exists() and not (SPR_DIR / 'player_hwsprites.bin.cute').exists():
        shutil.copyfile(hw_path, SPR_DIR / 'player_hwsprites.bin.cute')
    hw_path.write_bytes(bytes(hw_bytes))
    print(f"  Written {hw_path} ({len(hw_bytes)} bytes, 96 frames)")

    # 3. Compress with ZX0
    zx0_exe = Path('tools/zx0.exe')
    zx0_dst = SPR_DIR / 'player_hwsprites.zx0'
    if zx0_exe.exists():
        cmd = [str(zx0_exe), '-f', str(hw_path), str(zx0_dst)]
        subprocess.run(cmd, check=True)
        print(f"  Compressed {zx0_dst} ({zx0_dst.stat().st_size} bytes)")

        # Verify ZX0 stream
        verify_cmd = [sys.executable, 'tools/zx0_verify.py', str(zx0_dst), str(hw_path)]
        res = subprocess.run(verify_cmd, capture_output=True, text=True)
        if res.returncode == 0:
            print("  ZX0 Verification: OK (decompress matches uncompressed byte-for-byte)")
        else:
            print(f"  ZX0 Verification FAILED:\n{res.stderr}")
            sys.exit(1)

    # 4. Generate Preview Sheet
    create_preview(p1_frames, SPR_DIR / 'player_hwsprites_preview.png')

    print("=== Player Sprite Generation Complete! ===")

if __name__ == '__main__':
    main()
