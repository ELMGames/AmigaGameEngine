"""
png_to_amiga_raw.py  -  Convert an indexed-colour PNG to Amiga 5-plane interleaved raw + palette

Usage:
    python tools/png_to_amiga_raw.py <input.png> <output.raw> <output.pal>

The PNG must be:
  - Mode P (indexed, palette-based)
  - Exactly 32 palette entries (5 bitplanes = 32 colours)
  - Width divisible by 8 (pixel data packed into bytes)

Output .raw format:
  For each row y (0 .. height-1):
    For each plane p (0 .. 4):
      width/8 bytes: bit 7 of byte b = leftmost pixel (b*8+0), bit 0 = rightmost (b*8+7)
      Pixel colour index bit p determines whether this plane's pixel is set.
  Total size = (width/8) * 5 * height bytes.

Output .pal format:
  32 big-endian 16-bit words (64 bytes total).
  Each word = Amiga OCS 12-bit colour: $0RGB  (R/G/B each 4 bits, upper nibble of 8-bit channel).
"""

import struct
import sys
from PIL import Image


def convert(png_path, raw_path, pal_path):
    img = Image.open(png_path)
    assert img.mode == "P", f"PNG must be indexed (mode P), got: {img.mode}"

    width, height = img.size
    assert width % 8 == 0, f"Width {width} must be divisible by 8"

    pal = img.getpalette()           # flat RGB list: [r0,g0,b0, r1,g1,b1, ...]
    num_colors = len(pal) // 3
    assert num_colors == 32, f"Expected exactly 32 palette entries, got {num_colors}"

    px = img.load()
    planes = 5
    bytes_per_row = width // 8

    # -------------------------------------------------------------------------
    # Build the raw bitplane data: 5-plane interleaved layout
    # -------------------------------------------------------------------------
    raw = bytearray()
    for y in range(height):
        for plane in range(planes):
            for b in range(bytes_per_row):
                byte_val = 0
                for bit in range(8):
                    x = b * 8 + bit
                    if x < width:
                        idx = px[x, y]
                        if (idx >> plane) & 1:
                            byte_val |= (0x80 >> bit)   # MSB = leftmost pixel
                raw.append(byte_val)

    with open(raw_path, "wb") as f:
        f.write(raw)

    expected = bytes_per_row * planes * height
    assert len(raw) == expected, f"Raw size mismatch: {len(raw)} != {expected}"
    print(f"Written {len(raw):,} bytes  ->  {raw_path}")

    # -------------------------------------------------------------------------
    # Build the palette: 32 Amiga 12-bit colour words, big-endian
    # -------------------------------------------------------------------------
    pal_data = bytearray()
    for i in range(32):
        r, g, b = pal[i * 3], pal[i * 3 + 1], pal[i * 3 + 2]
        # Reduce each channel to 4 bits (take the upper nibble)
        amiga_word = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)
        pal_data += struct.pack(">H", amiga_word)

    with open(pal_path, "wb") as f:
        f.write(pal_data)

    print(f"Written {len(pal_data):,} bytes  ->  {pal_path}")
    print()
    print("Palette (Amiga 12-bit OCS):")
    for i in range(32):
        word = struct.unpack(">H", pal_data[i*2:i*2+2])[0]
        r, g, b = pal[i*3], pal[i*3+1], pal[i*3+2]
        print(f"  [{i:2d}] #{word:04X}  (src #{r:02X}{g:02X}{b:02X})")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2], sys.argv[3])
