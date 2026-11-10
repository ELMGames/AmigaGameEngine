#!/usr/bin/env python3
"""
tools/convert_effects.py
------------------------
Converts the landing dust puff:
  - assets/graphics/effects/smoke_64x32.png (64x32 RGBA, 7 frames of 16x16,
    4 frames per row as every engine BOB sheet is; the 8th cell is empty)
  - Output: smoke_64x32.raw, smoke_64x32.msk (1,024 bytes each)

The frames are a low dust kick: every pixel sits in rows 12-15 of its
16x16 cell (the bottom of the tile the object landed on), spreading out from
the feet and thinning to single specks. The PNG is the source asset. Every
opaque pixel must already be a colour of the shared 16-colour palette
(game_palette.json): slate grey, with a few white highlights.

Format: 4-bitplane interleaved raw graphics and a cookie-cut mask.
"""

import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from amiga_planar import pack_row_planes, load_palette_ocs

PROJECT_ROOT = Path(__file__).resolve().parent.parent

PALETTE_OCS = load_palette_ocs(PROJECT_ROOT / "game_palette.json")
PAL_8BIT = [(r * 17, g * 17, b * 17) for r, g, b in PALETTE_OCS]


def sheet_to_bobs(sheet: Image.Image, raw_path: Path, msk_path: Path):
    index_of = {c: i for i, c in enumerate(PAL_8BIT)}
    raw_bytes, msk_bytes = bytearray(), bytearray()
    w, h = sheet.size
    for y in range(h):
        indices = []
        for x in range(w):
            r, g, b, a = sheet.getpixel((x, y))
            if not a:
                indices.append(0)
            elif (r, g, b) in index_of:
                indices.append(index_of[(r, g, b)])
            else:
                raise ValueError(f"{raw_path.stem}.png: pixel ({x},{y}) colour {(r, g, b)} is not in the game palette")
        raw_row, mask_row = pack_row_planes(indices)
        raw_bytes.extend(raw_row)
        msk_bytes.extend(mask_row)
    raw_path.write_bytes(raw_bytes)
    msk_path.write_bytes(msk_bytes)
    print(f"    Exported raw: {raw_path.name} ({len(raw_bytes)} bytes)")
    print(f"    Exported msk: {msk_path.name} ({len(msk_bytes)} bytes)")


def main():
    print("=== Converting Effect Assets ===")
    base = PROJECT_ROOT / "assets/graphics/effects"
    src_png = base / "smoke_64x32.png"
    sheet = Image.open(src_png).convert("RGBA")
    if sheet.size != (64, 32):
        raise ValueError(f"{src_png.name}: expected 64x32, got {sheet.size[0]}x{sheet.size[1]}")
    print(f"[*] Converting smoke puff: {src_png.name}")
    sheet_to_bobs(sheet, base / "smoke_64x32.raw", base / "smoke_64x32.msk")
    print("=== Effect Assets Conversion Complete! ===")


if __name__ == "__main__":
    from tool_cli import run_tool
    run_tool(main, __doc__)
