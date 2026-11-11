#!/usr/bin/env python3
"""export_level.py - turn Meadow Run's Tiled maps into data the game includes.

For every assets/levels/Level_XX/Level_XX.tmx it writes, next to the map,
the same kinds of file Duck Rescue's exporter does:

  Level_XX-background.map   tile layer drawn first, a plain copy
  Level_XX-platform.map     platforms plus ducklings, cookie-cut over it
  Level_XX-foreground.map   cookie-cut last, and again over Mia each frame
  Level_XX-gamemap.bin      one collision byte per cell

Each .map is an 8-byte header (width, height as big-endian longwords)
followed by one big-endian word per cell: the tile's index in
meadow_tiles.png (0 = empty). And it writes include/levels/level_xx_entities.asm
with the level's LevelDef record (struct.asm): the four files, the player
start, the time limit and the number of ducklings.

The Tiled map must have:
  tile layers   background, platforms, ducks, foreground  (any may be empty)
  object layer  entities, holding an object named player_start
  property      time_limit (int, seconds)
and be HS_MAP_COLS x HS_MAP_ROWS tiles (128 x 14).

Collision comes from the tile "type" in meadow_tiles.tsx: on the platforms
layer solid, hazard and goal count; every tile on the ducks layer is a duckling;
a goal tile counts on any layer. Everything else is scenery.

    python games/meadow_run/tools/export_level.py            # every level
    python games/meadow_run/tools/export_level.py path.tmx   # one level
"""
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]
LEVELS = GAME / "assets" / "levels"
INCLUDE = GAME / "include" / "levels"

MAP_COLS, MAP_ROWS = 128, 14
EMPTY, SOLID, DUCK, HAZARD, GOAL = range(5)      # gamemap values (const.asm CLASS_*)
TYPE_CLASS = {"solid": SOLID, "hazard": HAZARD, "goal": GOAL, "duck": DUCK}


def load_tileset(tsx_path):
    root = ET.parse(tsx_path).getroot()
    return {int(t.get("id")): t.get("type") or t.get("class") for t in root.findall("tile")}


def read_layer(root, name, firstgid):
    for layer in root.findall("layer"):
        if layer.get("name") == name:
            text = layer.find("data").text
            gids = [int(v) for v in text.replace("\n", "").split(",") if v.strip()]
            return [[(g & 0x0FFFFFFF) - firstgid + 1 if g else 0
                     for g in gids[r * MAP_COLS:(r + 1) * MAP_COLS]] for r in range(MAP_ROWS)]
    return [[0] * MAP_COLS for _ in range(MAP_ROWS)]          # a missing layer is empty


def write_map(path, cells):
    with open(path, "wb") as f:
        f.write(struct.pack(">II", MAP_COLS, MAP_ROWS))
        for row in cells:
            for t in row:
                f.write(struct.pack(">H", t))


def export(tmx):
    root = ET.parse(tmx).getroot()
    name = tmx.stem                                           # Level_01
    if int(root.get("width")) != MAP_COLS or int(root.get("height")) != MAP_ROWS:
        sys.exit(f"{tmx}: must be {MAP_COLS} x {MAP_ROWS} tiles")
    tilesets = root.findall("tileset")
    if len(tilesets) != 1:
        sys.exit(f"{tmx}: use the single tileset meadow_tiles.tsx")
    firstgid = int(tilesets[0].get("firstgid"))
    types = load_tileset((tmx.parent / tilesets[0].get("source")).resolve())

    def t_index(cell):        # layer values are tile index + 1 (0 = empty)
        return cell - 1 if cell else None

    layers = {n: read_layer(root, n, firstgid) for n in ("background", "platforms", "ducks", "foreground")}
    back = [[t_index(c) or 0 for c in row] for row in layers["background"]]
    mid = [[t_index(c) or 0 for c in row] for row in layers["platforms"]]
    front = [[t_index(c) or 0 for c in row] for row in layers["foreground"]]
    game = [[EMPTY] * MAP_COLS for _ in range(MAP_ROWS)]

    ducks = 0
    for r in range(MAP_ROWS):
        for c in range(MAP_COLS):
            p = t_index(layers["platforms"][r][c])
            if p is not None:
                game[r][c] = TYPE_CLASS.get(types.get(p), EMPTY)
            for lname in ("background", "foreground"):
                t = t_index(layers[lname][r][c])
                if t is not None and types.get(t) == "goal":
                    game[r][c] = GOAL
            k = t_index(layers["ducks"][r][c])
            if k is not None:
                if p is not None:
                    sys.exit(f"{tmx}: duckling and platform share cell ({c}, {r})")
                mid[r][c] = k                                 # ducklings live in the platform layer
                game[r][c] = DUCK
                ducks += 1
    if not any(GOAL in row for row in game):
        sys.exit(f"{tmx}: no goal tile")

    start = None
    for group in root.findall("objectgroup"):
        for obj in group.findall("object"):
            if obj.get("name") == "player_start":
                x = int(float(obj.get("x")))
                y = int(float(obj.get("y"))) + int(float(obj.get("height", 16)))
                start = (x, y - 24)                           # sprite top: feet on the object's bottom
    if start is None:
        sys.exit(f"{tmx}: no player_start object in the entities layer")
    props = {p.get("name"): p.get("value") for p in root.iter("property")}
    time_limit = int(props.get("time_limit", 60))
    if not 1 <= time_limit <= 99:
        sys.exit(f"{tmx}: time_limit must be 1..99 seconds (the HUD shows two digits)")

    out = tmx.parent
    write_map(out / f"{name}-background.map", back)
    write_map(out / f"{name}-platform.map", mid)
    write_map(out / f"{name}-foreground.map", front)
    (out / f"{name}-gamemap.bin").write_bytes(bytes(v for row in game for v in row))

    lo = name.lower()
    rel = f"games/meadow_run/assets/levels/{name}"
    asm = f""";==============================================================================
; MEADOW RUN - {name.upper()}
; {lo}_entities.asm  -  Generated by tools/export_level.py from {name}.tmx: do not edit
;==============================================================================

{name}_Def:
    dc.l    {name}_Background+8         ; LevelDef_Background (cells, after the header)
    dc.l    {name}_Platform+8           ; LevelDef_Platform
    dc.l    {name}_Foreground+8         ; LevelDef_Foreground
    dc.l    {name}_GameMap              ; LevelDef_GameMap
    dc.w    {start[0]}                     ; LevelDef_StartX
    dc.w    {start[1]}                    ; LevelDef_StartY (sprite top)
    dc.w    {time_limit}                     ; LevelDef_TimeLimit (seconds)
    dc.w    {ducks}                     ; LevelDef_Ducks

{name}_Background:
    incbin  "{rel}/{name}-background.map"
{name}_Platform:
    incbin  "{rel}/{name}-platform.map"
{name}_Foreground:
    incbin  "{rel}/{name}-foreground.map"
{name}_GameMap:
    incbin  "{rel}/{name}-gamemap.bin"
    even
"""
    INCLUDE.mkdir(parents=True, exist_ok=True)
    (INCLUDE / f"{lo}_entities.asm").write_text(asm, encoding="utf-8", newline="\n")
    print(f"{name}: {ducks} ducklings, start {start}, {time_limit} s")


def main():
    paths = [Path(a).resolve() for a in sys.argv[1:]] or sorted(LEVELS.glob("Level_*/Level_*.tmx"))
    if not paths:
        sys.exit("no levels found")
    for p in paths:
        export(p)


if __name__ == "__main__":
    main()
