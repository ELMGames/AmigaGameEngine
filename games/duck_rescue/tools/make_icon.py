#!/usr/bin/env python3
"""make_icon.py - build the Workbench tool icon (main.info) from the duckling sprite.

Takes the first duckling frame from animals_16x16.png, scales it for Workbench's
tall hi-res pixels (4 wide x 2 high, so it looks square on a 640x256 screen) and
writes a standard 2-bitplane DiskObject. It uses no NewIcon or GlowIcon data, so
one file works from Workbench 1.3 upward.

The pens mean different colours on different Workbench versions:

    pen   1.3      2.x and later
    0     blue     grey             background
    1     white    black
    2     black    white
    3     orange   blue

    python games/duck_rescue/tools/make_icon.py [--style white|orange] [--preview out.png]
"""
import argparse
import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "games/duck_rescue/assets/graphics/animals/animals_16x16.png"
OUTPUTS = [ROOT / "games/duck_rescue/assets/graphics/icon/main.info", ROOT / "uae/dh0/main.info"]

FRAME = (0, 32, 16, 48)     # first duckling frame in the sheet
SCALE_X, SCALE_Y = 4, 2
STACK_SIZE = 8192
WBTOOL = 3
NO_ICON_POSITION = 0x80000000

# Which pen each part of the duck uses.
STYLES = {
    "white": {"body": 2, "outline": 1, "bill": 3, "highlight": 2},
    "orange": {"body": 3, "outline": 2, "bill": 1, "highlight": 1},
}
PALETTES = {
    "Workbench 1.3": [(0, 85, 170), (255, 255, 255), (0, 0, 0), (255, 136, 0)],
    "Workbench 2.x+": [(170, 170, 170), (0, 0, 0), (255, 255, 255), (102, 136, 187)],
}


def classify(rgba):
    """Name the part of the duck that one source pixel belongs to."""
    r, g, b, a = rgba
    if a < 128:
        return None
    if r + g + b < 200:
        return "outline"
    if r > 220 and g > 220 and b > 180:
        return "highlight"
    if g < 170:
        return "bill"
    return "body"


def build_pixels(style):
    """Return (width, height, rows of pen numbers)."""
    sprite = Image.open(SOURCE).convert("RGBA").crop(FRAME)
    sprite = sprite.crop(sprite.getbbox())
    pens = STYLES[style]
    rows = []
    for y in range(sprite.height):
        row = []
        for x in range(sprite.width):
            part = classify(sprite.getpixel((x, y)))
            row += [0 if part is None else pens[part]] * SCALE_X
        rows += [row] * SCALE_Y
    return len(rows[0]), len(rows), rows


def planes(width, rows):
    """Pack pen rows into two word-aligned bitplanes, plane 0 first."""
    row_bytes = (width + 15) // 16 * 2
    data = bytearray()
    for plane in range(2):
        for row in rows:
            packed = bytearray(row_bytes)
            for x, pen in enumerate(row):
                if pen >> plane & 1:
                    packed[x >> 3] |= 0x80 >> (x & 7)
            data += packed
    return bytes(data)


def disk_object(width, height, rows):
    gadget = struct.pack(
        ">IhhhhHHHIIIiIHI",
        0, 0, 0, width, height,
        4,              # Flags: GADGIMAGE, highlight by complement
        3,              # Activation: RELVERIFY | GADGIMMEDIATE
        1,              # GadgetType: BOOLGADGET
        1, 0, 0,        # GadgetRender set: an Image follows. No SelectRender or text.
        0, 0, 0,
        1,              # UserData: WB_DISKREVISION
    )
    header = struct.pack(">HH", 0xE310, 1) + gadget + struct.pack(
        ">BBIIIIIII",
        WBTOOL, 0,
        0, 0,           # no default tool, no tool types
        NO_ICON_POSITION, NO_ICON_POSITION,
        0, 0,           # no drawer data, no tool window
        STACK_SIZE,
    )
    image = struct.pack(">hhhhhIBBI", 0, 0, width, height, 2, 1, 3, 0, 0)
    return header + image + planes(width, rows)


def preview(path, width, height, rows):
    """Save the icon on each Workbench palette, shown at its on-screen shape."""
    pad = 8
    sheet = Image.new("RGB", ((width + pad * 2) * len(PALETTES), height * 2 + pad * 2), (60, 60, 60))
    for i, palette in enumerate(PALETTES.values()):
        icon = Image.new("RGB", (width, height), palette[0])
        for y, row in enumerate(rows):
            for x, pen in enumerate(row):
                icon.putpixel((x, y), palette[pen])
        panel = Image.new("RGB", (width + pad * 2, height * 2 + pad * 2), palette[0])
        panel.paste(icon.resize((width, height * 2), Image.NEAREST), (pad, pad))
        sheet.paste(panel, (i * (width + pad * 2), 0))
    sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST).save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--style", choices=STYLES, default="white")
    parser.add_argument("--preview", help="also save a PNG preview on both palettes")
    parser.add_argument("--preview-only", action="store_true", help="write no .info files")
    args = parser.parse_args()

    width, height, rows = build_pixels(args.style)
    if args.preview:
        preview(args.preview, width, height, rows)
    if args.preview_only:
        return
    data = disk_object(width, height, rows)
    for out in OUTPUTS:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
        print(f"{out.relative_to(ROOT)}: {width}x{height}, {len(data)} bytes")


if __name__ == "__main__":
    main()
