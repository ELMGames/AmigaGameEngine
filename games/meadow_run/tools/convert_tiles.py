#!/usr/bin/env python3
"""convert_tiles.py - build Meadow Run's tile sheet, its Tiled tileset and HUD art.

Meadow Run reuses Duck Rescue's 55 compact tiles (tileset-compact.png, 11 x 5
tiles of 16 x 16) and adds a sixth row: Duck Rescue's duckling, its 4-frame
animation copied from animals_16x16.png (the same palette, so no colour is
lost). Outputs, in assets/graphics/tiles/:

  meadow_tiles.png          176 x 96, for Tiled (indexed to game_palette.json)
  meadow_tiles.tsx          the Tiled tileset: each tile's "type" is what the
                            exporter turns into collision (solid, hazard,
                            goal, duck); untyped tiles are scenery
  meadow_tiles_176x96.raw   4 interleaved bitplanes, 22 bytes per plane-row
  meadow_tiles_176x96.msk   the matching interleaved cookie-cut mask
  meadow_tiles.pal          16 OCS colour words

and in assets/graphics/hud/:

  hud_duck.png              the duckling as a 16 x 16 sprite image (preview)

plus include/graphics/hud_sprite_data.asm: the HUD's digit font and the
duckling icon as a 3-colour hardware sprite.

Run from anywhere; tools/build.py runs it on every build.
"""
import sys
from pathlib import Path

from PIL import Image

GAME = Path(__file__).resolve().parents[1]
REPO = GAME.parents[1]
sys.path.insert(0, str(REPO / "games" / "duck_rescue" / "tools"))
from amiga_planar import load_palette_ocs, pack_row_planes  # noqa: E402  (shared helpers)

SRC_SHEET = REPO / "games" / "duck_rescue" / "assets" / "graphics" / "tiles" / "tileset-compact.png"
TILES = GAME / "assets" / "graphics" / "tiles"
HUD = GAME / "assets" / "graphics" / "hud"
HUD_ASM = GAME / "include" / "graphics" / "hud_sprite_data.asm"

ANIMALS = REPO / "games" / "duck_rescue" / "assets" / "graphics" / "animals" / "animals_16x16.png"

COLS, ROWS = 11, 6
DUCK_FIRST, DUCK_FRAMES = 55, 4          # tiles 55..58: row 5, columns 0..3
DUCK_SRC_Y = 32                          # the duckling is row 2 of animals_16x16.png

# Palette indices in the duckling (game_palette.json)
OUTLINE, WHITE, ORANGE, GOLD = 2, 3, 6, 8

# Tile types for the Tiled tileset (compact tile index -> type)
SOLID = list(range(1, 14)) + [18]        # grass, earth, stone, snowy stone, crate
HAZARD = [15, 47, 48]                    # ice water block, water surface, deep water
GOAL = [19]                              # the signpost
DUCK = [DUCK_FIRST]


def nearest(palette, rgb):
    r, g, b = rgb
    best, best_d = 0, None
    for i, (pr, pg, pb) in enumerate(palette):
        d = (pr * 17 - r) ** 2 + (pg * 17 - g) ** 2 + (pb * 17 - b) ** 2
        if best_d is None or d < best_d:
            best, best_d = i, d
    return best


def duck_frames(palette):
    """The duckling's 4 animation frames, 16 x 16 palette indices each."""
    src = Image.open(ANIMALS).convert("RGBA")
    frames = []
    for k in range(DUCK_FRAMES):
        frames.append([[nearest(palette, src.getpixel((k * 16 + x, DUCK_SRC_Y + y))[:3])
                        if src.getpixel((k * 16 + x, DUCK_SRC_Y + y))[3] > 128 else 0
                        for x in range(16)] for y in range(16)])
    return frames


def main():
    palette = load_palette_ocs(GAME / "game_palette.json")
    src = Image.open(SRC_SHEET).convert("RGBA")
    w, h = COLS * 16, ROWS * 16
    idx = [[0] * w for _ in range(h)]
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, a = src.getpixel((x, y))
            idx[y][x] = nearest(palette, (r, g, b)) if a > 128 else 0
    ducks = duck_frames(palette)
    for k in range(DUCK_FRAMES):
        t = DUCK_FIRST + k
        ox, oy = (t % COLS) * 16, (t // COLS) * 16
        for y, row in enumerate(ducks[k]):
            for x, v in enumerate(row):
                idx[oy + y][ox + x] = v

    # Indexed PNG for Tiled
    TILES.mkdir(parents=True, exist_ok=True)
    img = Image.new("P", (w, h))
    flat = []
    for r, g, b in palette:
        flat += [r * 17, g * 17, b * 17]
    img.putpalette(flat + [0] * (768 - len(flat)))
    img.putdata([v for row in idx for v in row])
    img.info["transparency"] = 0
    img.save(TILES / "meadow_tiles.png", transparency=0)

    # Interleaved bitplanes and mask
    raw, msk = bytearray(), bytearray()
    for row in idx:
        r, m = pack_row_planes(row)
        raw += r
        msk += m
    (TILES / "meadow_tiles_176x96.raw").write_bytes(raw)
    (TILES / "meadow_tiles_176x96.msk").write_bytes(msk)
    pal = bytearray()
    for r, g, b in palette:
        v = (r << 8) | (g << 4) | b
        pal += bytes((v >> 8, v & 255))
    (TILES / "meadow_tiles.pal").write_bytes(pal)

    # Tiled tileset
    lines = ['<?xml version="1.0" encoding="UTF-8"?>',
             f'<tileset version="1.10" tiledversion="1.12.2" name="meadow_tiles" tilewidth="16" '
             f'tileheight="16" tilecount="{COLS * ROWS}" columns="{COLS}">',
             f' <image source="meadow_tiles.png" trans="000000" width="{w}" height="{h}"/>']
    types = {**{t: "solid" for t in SOLID}, **{t: "hazard" for t in HAZARD},
             **{t: "goal" for t in GOAL}, **{t: "duck" for t in DUCK}}
    for t in sorted(types):
        lines.append(f' <tile id="{t}" type="{types[t]}"/>')
    lines.append('</tileset>')
    (TILES / "meadow_tiles.tsx").write_text("\n".join(lines) + "\n", encoding="utf-8")

    # HUD: the duckling as a 3-colour sprite (sprite colours 1..3 = gold,
    # orange, outline); its white eye glint becomes gold
    HUD.mkdir(parents=True, exist_ok=True)
    duck = ducks[0]
    spr = {GOLD: 1, WHITE: 1, ORANGE: 2, OUTLINE: 3}
    prev = Image.new("P", (16, 16))
    prev.putpalette(flat + [0] * (768 - len(flat)))
    prev.putdata([v for row in duck for v in row])
    prev.save(HUD / "hud_duck.png", transparency=0)

    asm = [";" + "=" * 78,
           "; MEADOW RUN - HUD SPRITE DATA",
           "; hud_sprite_data.asm  -  Generated by tools/convert_tiles.py: do not edit",
           ";" + "=" * 78, "",
           "; HudDigits: 0-9, 8 x 8, one byte per line (bit 7 = left pixel).",
           "HudDigits:"]
    for d in DIGITS:
        asm.append("    dc.b    " + ",".join(f"${int(r.replace('.', '0').replace('#', '1'), 2):02x}" for r in d))
    asm += ["", "; HudDuckSprite: the duckling as a 16 x 16 hardware sprite, colours 1-3",
            "; (gold, orange, outline: COLOR21-23 on SPR2). Control words patched",
            "; at run time by HudInit.", "HudDuckSprite:", "    dc.w    0,0"]
    for row in duck:
        a = b = 0
        for x, v in enumerate(row):
            s = spr.get(v, 0)
            if s & 1:
                a |= 0x8000 >> x
            if s & 2:
                b |= 0x8000 >> x
        asm.append(f"    dc.w    ${a:04x},${b:04x}")
    asm += ["    dc.w    0,0", ""]
    HUD_ASM.write_text("\n".join(asm), encoding="utf-8", newline="\n")
    print(f"meadow_tiles: {len(raw)} bytes raw, {len(msk)} mask, duckling tiles {DUCK_FIRST}-{DUCK_FIRST + DUCK_FRAMES - 1}")


DIGITS = [
    ["..####..", ".##..##.", ".##.###.", ".######.", ".###.##.", ".##..##.", "..####..", "........"],
    ["...##...", "..###...", "...##...", "...##...", "...##...", "...##...", ".######.", "........"],
    ["..####..", ".##..##.", ".....##.", "....##..", "..##....", ".##.....", ".######.", "........"],
    ["..####..", ".##..##.", ".....##.", "...###..", ".....##.", ".##..##.", "..####..", "........"],
    ["....##..", "...###..", "..####..", ".##.##..", ".######.", "....##..", "....##..", "........"],
    [".######.", ".##.....", ".#####..", ".....##.", ".....##.", ".##..##.", "..####..", "........"],
    ["..####..", ".##.....", ".#####..", ".##..##.", ".##..##.", ".##..##.", "..####..", "........"],
    [".######.", ".....##.", "....##..", "...##...", "..##....", "..##....", "..##....", "........"],
    ["..####..", ".##..##.", ".##..##.", "..####..", ".##..##.", ".##..##.", "..####..", "........"],
    ["..####..", ".##..##.", ".##..##.", "..#####.", ".....##.", "....##..", "..###...", "........"],
]

if __name__ == "__main__":
    main()
