#!/usr/bin/env python3
"""
convert_assets.py
-----------------
Manifest-driven asset conversion for the Amiga GAME ENGINE.

All PNG -> Amiga bitplane conversions are declared in the ASSETS manifest at
the bottom of this file; the converter functions above it are generic.  Add a
new asset by adding a manifest entry — no new code needed for the common
cases.

Converter types:

  planar   RGBA PNG -> N-bitplane plane-by-plane raw file + OCS palette.
           Colour index 0 is reserved for transparent pixels (they show the
           screen background); opaque colours are ranked by frequency and
           assigned indices 1..(2^planes)-1.  Excess colours are remapped to
           the nearest kept colour (RGB distance) with a warning.
           Raw layout: plane 0 (LSB) first, rows padded to a word boundary.
           Palette: one big-endian $0RGB word per colour index.

  1plane   RGBA PNG -> single bitplane via a threshold function (masks,
           outlines).  1 bit set where threshold(r, g, b, a) is true.

  star     Indexed or RGBA PNG -> single bitplane (index != 0, or alpha).

Not covered here: the loading-screen image (template.raw/.pal/.zx0) is
produced externally with amigeconv (5-bitplane interleaved conversion) and a
ZX0 compressor — see README.md.

Requires: Pillow  (pip install Pillow)

Run from the repo root:
    python tools/convert_assets.py
or via the build script:
    ./build.ps1 -Assets
"""

import sys
from collections import Counter

from PIL import Image

ALPHA_THRESHOLD = 128       # alpha > this = opaque pixel


# ---------------------------------------------------------------------------
# Converters
# ---------------------------------------------------------------------------

def rgb_to_ocs_word(rgb):
    """Convert an (r, g, b) 8-bit tuple to a 12-bit OCS $0RGB colour word."""
    r, g, b = ((c * 15 + 127) // 255 for c in rgb)
    return (r << 8) | (g << 4) | b


def export_planar(src, raw, pal, planes=3, **_):
    """RGBA PNG -> N-bitplane plane-by-plane raw + palette (see module doc)."""
    img = Image.open(src).convert('RGBA')
    w, h = img.size
    bytes_per_row = ((w + 15) // 16) * 2       # round up to word boundary
    plane_size = bytes_per_row * h
    pixels = list(img.getdata())

    # Rank opaque colours by frequency (ties broken by colour value for
    # deterministic output across runs).
    counts = Counter((r, g, b) for r, g, b, a in pixels if a > ALPHA_THRESHOLD)
    max_colours = (1 << planes) - 1            # index 0 = transparent
    ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    kept = [rgb for rgb, _n in ranked[:max_colours]]

    # Remap any excess colours to the nearest kept colour.
    remap = {}
    for rgb, n in ranked[max_colours:]:
        nearest = min(kept, key=lambda k: sum((a - b) ** 2 for a, b in zip(k, rgb)))
        remap[rgb] = nearest
        print(f"  WARNING: {src}: colour {rgb} x{n} px remapped to {nearest}")

    index_of = {rgb: i + 1 for i, rgb in enumerate(kept)}

    # Build the bitplanes: bit p of the colour index goes to plane p.
    data = bytearray(plane_size * planes)
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[y * w + x]
            if a <= ALPHA_THRESHOLD:
                continue                       # index 0: all plane bits stay 0
            idx = index_of[remap.get((r, g, b), (r, g, b))]
            byte_off = y * bytes_per_row + x // 8
            bit = 0x80 >> (x & 7)
            for p in range(planes):
                if idx & (1 << p):
                    data[p * plane_size + byte_off] |= bit
    with open(raw, 'wb') as f:
        f.write(bytes(data))
    print(f"  {raw}: {w}x{h}x{planes}bpl -> {len(data)} bytes "
          f"({bytes_per_row} bytes/row, {plane_size} bytes/plane)")

    # Palette: index 0 = black/transparent, then the kept colours,
    # zero-padded to the full 2^planes entries.
    pal_words = [0] + [rgb_to_ocs_word(rgb) for rgb in kept]
    pal_words += [0] * ((1 << planes) - len(pal_words))
    with open(pal, 'wb') as f:
        for word in pal_words:
            f.write(word.to_bytes(2, 'big'))
    print(f"  {pal}: {len(pal_words)} colours -> {len(pal_words) * 2} bytes")
    for i, word in enumerate(pal_words):
        print(f"    colour {i}: ${word:03X}")


def export_1plane(src, raw, threshold, **_):
    """RGBA PNG -> 1-plane raw; threshold(r, g, b, a) -> True sets the bit."""
    img = Image.open(src).convert('RGBA')
    w, h = img.size
    bytes_per_row = ((w + 15) // 16) * 2
    data = bytearray(bytes_per_row * h)
    pixels = list(img.getdata())
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[y * w + x]
            if threshold(r, g, b, a):
                data[y * bytes_per_row + x // 8] |= 0x80 >> (x & 7)
    with open(raw, 'wb') as f:
        f.write(bytes(data))
    print(f"  {raw}: {w}x{h} -> {len(data)} bytes ({bytes_per_row} bytes/row)")


def export_star(src, raw, **_):
    """Indexed or RGBA PNG -> 1-plane raw (index != 0 / alpha > 128 sets bit)."""
    img = Image.open(src)
    w, h = img.size
    bytes_per_row = ((w + 15) // 16) * 2
    data = bytearray(bytes_per_row * h)
    if img.mode == 'P':
        pixels = list(img.getdata())
        test = lambda i: pixels[i] != 0
    else:
        rgba = list(img.convert('RGBA').getdata())
        test = lambda i: rgba[i][3] > ALPHA_THRESHOLD
    for y in range(h):
        for x in range(w):
            if test(y * w + x):
                data[y * bytes_per_row + x // 8] |= 0x80 >> (x & 7)
    with open(raw, 'wb') as f:
        f.write(bytes(data))
    print(f"  {raw}: {w}x{h} -> {len(data)} bytes ({bytes_per_row} bytes/row)")


def export_copper_sky(src, out_bin, **_):
    """Convert an image's vertical scanlines to Amiga 12-bit RGB color words ($0RGB)."""
    img = Image.open(src).convert('RGB')
    w, h = img.size
    data = bytearray()
    for y in range(h):
        r, g, b = img.getpixel((0, y))[:3]
        word = rgb_to_ocs_word((r, g, b))
        data.extend(word.to_bytes(2, 'big'))
    with open(out_bin, 'wb') as f:
        f.write(data)
    print(f"  {out_bin}: {h} scanlines -> {len(data)} bytes ({len(data)//2} words)")


CONVERTERS = {
    'planar':     export_planar,
    '1plane':     export_1plane,
    'star':       export_star,
    'copper_sky': export_copper_sky,
}


# ---------------------------------------------------------------------------
# Asset manifest — one entry per generated asset.
#
# Common keys:  type, src  plus the converter-specific output/parameter keys
# documented in the module docstring.
# ---------------------------------------------------------------------------

ASSETS = [
    # Title screen logo: 3 bitplanes (8 colours), blitted into planes 0-2 of
    # the title screen by TitleSetup (titlescreen.asm).
    {
        'type':   'planar',
        'src':    'assets/graphics/title/AGE_title.png',
        'raw':    'assets/graphics/title/AGE_title.raw',
        'pal':    'assets/graphics/title/AGE_title.pal',
        'planes': 3,
    },

    # Copper sky gradient (512 scanline colors for 1/2 parallax background)
    {
        'type':    'copper_sky',
        'src':     'assets/graphics/copper/copper_sky.png',
        'out_bin': 'assets/graphics/copper/copper_sky.bin',
    },
]


def main():
    import os
    print("Converting assets...")
    ok = True
    for entry in ASSETS:
        entry = dict(entry)
        conv = CONVERTERS[entry.pop('type')]
        src = entry.get('src')
        if src and not os.path.exists(src):
            temp_src = os.path.join('TEMP', src)
            if os.path.exists(temp_src):
                entry['src'] = temp_src
            else:
                print(f"  WARNING: {src} not found, skipping.")
                continue
        try:
            conv(**entry)
        except Exception as exc:          # keep converting the rest, fail at exit
            print(f"  ERROR: {entry.get('src', '?')}: {exc}")
            ok = False

    try:
        from convert_enemies import main as convert_enemies_main
        convert_enemies_main()
    except Exception as exc:
        print(f"  ERROR converting enemies: {exc}")
        ok = False

    print("Done." if ok else "FAILED.")
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
