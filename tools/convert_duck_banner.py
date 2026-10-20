#!/usr/bin/env python3
"""
tools/convert_duck_banner.py
-----------------------------
Converts assets/graphics/title/duck_rescue_complete_banner_alpha_280x96.png
into two separate assets:

1. Title / Menu screen banner (Text "DUCK RESCUE" only):
   assets/graphics/title/duck_rescue_title.raw (192x96, 4 bitplanes planar, 9216 bytes)
   assets/graphics/title/duck_rescue_title.pal (16 big-endian $0RGB words, 32 bytes)
   assets/graphics/title/duck_rescue_title.png (indexed PNG)

2. Game Complete screen duckling (Character only):
   assets/graphics/title/duckling_complete.raw (64x96, 4 bitplanes planar, 3072 bytes)
   assets/graphics/title/duckling_complete.pal (16 big-endian $0RGB words, 32 bytes)
   assets/graphics/title/duckling_complete.png (indexed PNG)
"""

import os
import struct
from PIL import Image

def convert():
    src_path = 'assets/graphics/title/duck_rescue_complete_banner_alpha_280x96.png'
    print(f"Loading {src_path}...")
    src = Image.open(src_path).convert('RGBA')

    # 16-color Amiga OCS palette (12-bit RGB)
    # Index 0: Transparent ($000)
    pal_12bit = [
        0x000, # 0: Transparent
        0xFFA, # 1: Cream/White highlight
        0xFE3, # 2: Bright lemon yellow
        0xFC1, # 3: Golden yellow
        0xFB2, # 4: Warm amber gold
        0xEB4, # 5: Amber transition
        0xE71, # 6: Bright orange
        0xE40, # 7: Deep red-orange
        0xC21, # 8: Rich red / shadow
        0x911, # 9: Deep crimson / maroon drop shadow
        0x742, # 10: Leather helmet brown
        0x412, # 11: Dark plum shadow
        0x39E, # 12: Bright cyan goggles highlight
        0x259, # 13: Mid teal/blue goggles
        0x125, # 14: Dark navy goggles rim
        0x101, # 15: Dark outline
    ]

    def ocs_to_rgb24(word):
        r = ((word >> 8) & 0xF) * 17
        g = ((word >> 4) & 0xF) * 17
        b = (word & 0xF) * 17
        return (r, g, b)

    pal_rgb24 = [ocs_to_rgb24(w) for w in pal_12bit]

    def color_dist(c1, c2):
        r1, g1, b1 = c1
        r2, g2, b2 = c2
        rmean = (r1 + r2) // 2
        r = r1 - r2
        g = g1 - g2
        b = b1 - b2
        return (((512 + rmean) * r * r) >> 8) + 4 * g * g + (((767 - rmean) * b * b) >> 8)

    def export_asset(canvas, raw_path, pal_path, png_path):
        w, h = canvas.size
        planes = 4
        bytes_per_row = w // 8
        plane_size = bytes_per_row * h
        total_raw_size = plane_size * planes

        data_pixels = bytearray(w * h)
        for y in range(h):
            for x in range(w):
                r, g, b, a = canvas.getpixel((x, y))
                if a < 100:
                    data_pixels[y * w + x] = 0
                else:
                    best_idx = 1
                    best_d = color_dist((r, g, b), pal_rgb24[1])
                    for i in range(2, 16):
                        d = color_dist((r, g, b), pal_rgb24[i])
                        if d < best_d:
                            best_d = d
                            best_idx = i
                    data_pixels[y * w + x] = best_idx

        # Save indexed PNG
        indexed_img = Image.new('P', (w, h))
        flat_pal = []
        for r, g, b in pal_rgb24:
            flat_pal.extend([r, g, b])
        flat_pal += [0] * ((256 - 16) * 3)
        indexed_img.putpalette(flat_pal)
        indexed_img.putdata(data_pixels)
        indexed_img.save(png_path)
        print(f"Exported PNG: {png_path} ({w}x{h})")

        # Build planar bitplanes
        raw_data = bytearray(total_raw_size)
        for y in range(h):
            for x in range(w):
                idx = data_pixels[y * w + x]
                if idx == 0:
                    continue
                byte_off = y * bytes_per_row + (x // 8)
                bit = 0x80 >> (x & 7)
                for p in range(planes):
                    if idx & (1 << p):
                        raw_data[p * plane_size + byte_off] |= bit

        with open(raw_path, 'wb') as f:
            f.write(raw_data)
        print(f"Exported RAW: {raw_path} ({len(raw_data)} bytes, {plane_size} bytes/plane)")

        # Build palette (.pal)
        pal_data = bytearray()
        for word in pal_12bit:
            pal_data.extend(struct.pack('>H', word))
        with open(pal_path, 'wb') as f:
            f.write(pal_data)
        print(f"Exported PAL: {pal_path} ({len(pal_data)} bytes, {len(pal_12bit)} words)")

    # 1. Process "DUCK RESCUE" text banner (192x96)
    # Original text columns 12..189 (width 177)
    text_crop = src.crop((12, 0, 189, 96))
    text_canvas = Image.new('RGBA', (192, 96), (0, 0, 0, 0))
    # Centered in 192px width: (192 - 177) // 2 = 7
    text_canvas.paste(text_crop, (7, 0))

    export_asset(
        canvas=text_canvas,
        raw_path='assets/graphics/title/duck_rescue_title.raw',
        pal_path='assets/graphics/title/duck_rescue_title.pal',
        png_path='assets/graphics/title/duck_rescue_title.png'
    )

    # 2. Process Duckling character for Game Complete (64x96)
    # Original duckling columns 204..267 (width 63)
    duck_crop = src.crop((204, 0, 267, 96))
    duck_canvas = Image.new('RGBA', (64, 96), (0, 0, 0, 0))
    # Centered in 64px width: (64 - 63) // 2 = 0
    duck_canvas.paste(duck_crop, (0, 0))

    export_asset(
        canvas=duck_canvas,
        raw_path='assets/graphics/title/duckling_complete.raw',
        pal_path='assets/graphics/title/duckling_complete.pal',
        png_path='assets/graphics/title/duckling_complete.png'
    )

if __name__ == '__main__':
    convert()
