#!/usr/bin/env python3
"""
remap_png_palette.py  --  Reorder a palette-indexed PNG so that the darkest
colour is at index 0 and the brightest is at the highest index.

On Amiga OCS, colour 0 is forced to black by the copper's background
strobe, so index 0 must hold the darkest (background/transparent) colour.
This script sorts the palette by luminance (dark-first) and remaps every
pixel index so the image looks identical after conversion.

Usage:
    python tools/remap_png_palette.py <input.png> [output.png]

If output.png is omitted the input file is overwritten in-place.
"""

import sys
from PIL import Image


def luminance(r, g, b):
    """Perceived luminance (standard Rec.601 coefficients)."""
    return 0.299 * r + 0.587 * g + 0.114 * b


def remap_palette_dark_first(src_path, dst_path):
    img = Image.open(src_path)
    if img.mode != "P":
        raise ValueError(f"{src_path} is not a palette-indexed PNG (mode={img.mode})")

    raw_pal = img.getpalette()          # flat list: R0,G0,B0, R1,G1,B1, ...
    n_colors = 256                      # Pillow always returns 256 entries

    # Count how many palette entries the image actually uses
    used = set(img.getdata())
    max_idx = max(used)
    active = max_idx + 1               # number of active palette entries

    # Build (index, R, G, B) list for active entries
    entries = [
        (i, raw_pal[i*3], raw_pal[i*3+1], raw_pal[i*3+2])
        for i in range(active)
    ]

    # Sort by luminance: darkest first
    sorted_entries = sorted(entries, key=lambda e: luminance(e[1], e[2], e[3]))

    # Build old→new index remapping
    remap = [0] * n_colors
    for new_idx, (old_idx, r, g, b) in enumerate(sorted_entries):
        remap[old_idx] = new_idx

    # Build new flat palette
    new_pal = raw_pal[:]               # start with copy (preserves unused slots)
    for new_idx, (old_idx, r, g, b) in enumerate(sorted_entries):
        new_pal[new_idx*3]   = r
        new_pal[new_idx*3+1] = g
        new_pal[new_idx*3+2] = b

    # Remap pixel data
    new_pixels = bytes(remap[p] for p in img.getdata())

    # Build output image
    out = Image.new("P", img.size)
    out.putpalette(new_pal)
    out.frombytes(new_pixels)
    out.save(dst_path)

    # Print summary
    print(f"Remapped {active} palette entries (dark-first):")
    for new_idx, (old_idx, r, g, b) in enumerate(sorted_entries[:active]):
        lum = luminance(r, g, b)
        amiga = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)
        marker = "  <-- background/transparent" if new_idx == 0 else \
                 "  <-- white"                  if new_idx == active-1 else ""
        print(f"  [{new_idx:2d}] RGB({r:3d},{g:3d},{b:3d})  lum={lum:5.1f}  "
              f"Amiga=${amiga:04X}{marker}")
    print(f"\nSaved: {dst_path}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else src
    remap_palette_dark_first(src, dst)
