#!/usr/bin/env python3
"""
convert_headshots.py - Convert 128x64 headshot PNGs (Bob & Denise) to Amiga 5-plane raw bitplanes and palettes.

Each 128x64 PNG contains two 64x64 pixel art portraits side by side:
  - Frame 0 (X=0..63, Y=0..63)
  - Frame 1 (X=64..127, Y=0..63)

Output format per character:
  - <name>_128x64.raw: 5,120 bytes (2 frames x 5 planes x 512 bytes)
      Offset 0:     Frame 0 (2,560 bytes)
      Offset 2560:  Frame 1 (2,560 bytes)
  - <name>.pal: 64 bytes (32 big-endian 16-bit Amiga RGB444 color words)
      COLOR00: $0000 (black background)
      COLOR01..COLOR30: Character artwork colors
      COLOR31: $0FFF (pure white text/highlight)
"""

import os
import struct
from PIL import Image

def to_amiga_rgb(r, g, b):
    ar = round(r * 15 / 255)
    ag = round(g * 15 / 255)
    ab = round(b * 15 / 255)
    return (ar * 17, ag * 17, ab * 17), (ar << 8) | (ag << 4) | ab

def process_character(png_path, out_raw_path, out_pal_path, name):
    print(f"[*] Processing {name} headshots from: {png_path}")
    im = Image.open(png_path).convert('RGBA')
    w, h = im.size
    assert w == 128 and h == 64, f"Expected 128x64 image, got {w}x{h}"

    # Extract non-transparent pixels for palette quantization
    pixels = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = im.getpixel((x, y))
            if a > 64:
                (ar, ag, ab), _ = to_amiga_rgb(r, g, b)
                pixels.append((ar, ag, ab))

    dummy = Image.new('RGB', (len(pixels), 1))
    dummy.putdata(pixels)

    # Quantize to at most 30 colors (leaving slot 0 for black and slot 31 for white)
    q_dummy = dummy.quantize(colors=30, method=Image.MEDIANCUT)
    pal_entries = q_dummy.getpalette()
    num_cols = min(30, len(pal_entries) // 3)

    palette_32 = [(0, 0, 0)] # index 0: black
    palette_words = [0x0000]

    for i in range(num_cols):
        r = pal_entries[i*3]
        g = pal_entries[i*3 + 1]
        b = pal_entries[i*3 + 2]
        (ar, ag, ab), word = to_amiga_rgb(r, g, b)
        palette_32.append((ar, ag, ab))
        palette_words.append(word)

    while len(palette_32) < 31:
        palette_32.append((0, 0, 0))
        palette_words.append(0x0000)

    palette_32.append((255, 255, 255)) # index 31: white
    palette_words.append(0x0FFF)

    # Convert frames 0 and 1
    total_raw = bytearray()
    for frame_idx in range(2):
        frame_bytes = bytearray(5 * 512) # 5 planes x 512 bytes
        x_offset = frame_idx * 64

        for y in range(64):
            for x in range(64):
                r, g, b, a = im.getpixel((x_offset + x, y))
                if a <= 64:
                    cidx = 0
                else:
                    (ar, ag, ab), _ = to_amiga_rgb(r, g, b)
                    best_idx = 0
                    best_dist = 999999999
                    for idx in range(1, 32):
                        pr, pg, pb = palette_32[idx]
                        dist = (ar - pr)**2 + (ag - pg)**2 + (ab - pb)**2
                        if dist < best_dist:
                            best_dist = dist
                            best_idx = idx
                    if ar == 0 and ag == 0 and ab == 0:
                        best_idx = 0
                    cidx = best_idx

                byte_x = x // 8
                bit_pos = 7 - (x % 8)
                byte_offset = y * 8 + byte_x

                for p in range(5):
                    bit_val = (cidx >> p) & 1
                    if bit_val:
                        frame_bytes[p * 512 + byte_offset] |= (1 << bit_pos)

        total_raw.extend(frame_bytes)

    # Save .raw
    with open(out_raw_path, 'wb') as f:
        f.write(total_raw)
    print(f"    Exported {len(total_raw)} bytes to {out_raw_path}")

    # Save .pal
    pal_data = bytearray()
    for w in palette_words:
        pal_data.extend(struct.pack('>H', w))
    with open(out_pal_path, 'wb') as f:
        f.write(pal_data)
    print(f"    Exported {len(pal_data)} bytes to {out_pal_path}")

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    hs_dir = os.path.join(base_dir, 'assets', 'graphics', 'headshots')

    denise_png = os.path.join(hs_dir, 'headshot_denise_128x64.png')
    denise_raw = os.path.join(hs_dir, 'headshot_denise_128x64.raw')
    denise_pal = os.path.join(hs_dir, 'headshot_denise.pal')
    process_character(denise_png, denise_raw, denise_pal, 'Denise')

    print("[*] Headshot asset conversion complete!")

if __name__ == '__main__':
    main()
