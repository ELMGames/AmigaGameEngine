#!/usr/bin/env python3
"""
Tiled TMX Level Exporter for Amiga Engine
==========================================
Converts Tiled (.tmx) multi-layer maps into Amiga-ready binary and assembly files.

Handles:
1. Multi-layer Tilemaps:
   - Background Layer(s)  -> Binary .map file (e.g. Level_01-background.map)
   - Platform Layer(s)    -> Binary .map file (e.g. Level_01-platform.map)
   - Composite Map        -> Merged platforms over background (e.g. Level_01.map)
2. Object / Entity Layer:
   - PlayerStart (X, Y, direction)
   - Enemies (type, spawn X/Y, patrol bounds, speed)
   - Triggers / Exits (trigger_id, bounding boxes, target)
   - Hazards (damage, bounding boxes)
3. Collision Attributes:
   - Parses tileset properties from .tsx / .tmx and creates TileAttributesTable.

Binary .map format (8-byte LE header + 16-bit LE words):
  Offset 0..3: uint32 Width in tiles (Little-Endian)
  Offset 4..7: uint32 Height in tiles (Little-Endian)
  Offset 8+:   uint16 Tile indices row-by-row (Little-Endian, 0=Empty)
"""

import os
import sys
import argparse
import struct
import zlib
import gzip
import base64
import xml.etree.ElementTree as ET
from pathlib import Path

# Physical tile collision attribute constants (matches tilemap.asm)
ATTR_EMPTY       = 0
ATTR_SOLID       = 1
ATTR_LADDER      = 2
ATTR_HAZARD      = 3
ATTR_PASSTHROUGH = 4

# GameMap Block identifiers (matches const.asm)
BLOCK_EMPTY       = 0
BLOCK_LADDER      = 1
BLOCK_ENEMYFALL   = 2
BLOCK_PUSH        = 3
BLOCK_DIRT        = 4
BLOCK_SOLID       = 5
BLOCK_ENEMYFLOAT  = 6
BLOCK_PLAYERSTART = 7
BLOCK_MILLIESTART = BLOCK_PLAYERSTART
BLOCK_COCOON      = 11
BLOCK_ACID        = 12

ATTR_MAP = {
    "empty": ATTR_EMPTY,
    "air": ATTR_EMPTY,
    "none": ATTR_EMPTY,
    "0": ATTR_EMPTY,
    "solid": ATTR_SOLID,
    "wall": ATTR_SOLID,
    "ground": ATTR_SOLID,
    "block": ATTR_SOLID,
    "1": ATTR_SOLID,
    "ladder": ATTR_LADDER,
    "climb": ATTR_LADDER,
    "vine": ATTR_LADDER,
    "rope": ATTR_LADDER,
    "2": ATTR_LADDER,
    "hazard": ATTR_HAZARD,
    "spikes": ATTR_HAZARD,
    "spike": ATTR_HAZARD,
    "acid": ATTR_HAZARD,
    "lava": ATTR_HAZARD,
    "3": ATTR_HAZARD,
    "passthrough": ATTR_PASSTHROUGH,
    "oneway": ATTR_PASSTHROUGH,
    "one-way": ATTR_PASSTHROUGH,
    "platform": ATTR_PASSTHROUGH,
    "4": ATTR_PASSTHROUGH,
}

# Default 16-color OCS palette for level graphics (matches GameTilesRaw + 22528)
# Tuned for vibrant enemy sprites (cyan, teal, red, maroon, orange, gold, slate) and four-seasons tiles
DEFAULT_PALETTE_OCS = [
    (0, 0, 0),      # 0: Transparent ($0000)
    (1, 11, 14),    # 1: 0x1BE Vibrant Cyan (tile 122 / slimes / ghost)
    (3, 3, 2),      # 2: 0x332 Dark outline
    (15, 15, 15),   # 3: 0xFFF White glints / highlights
    (2, 7, 4),      # 4: 0x274 Forest Green
    (1, 9, 3),      # 5: 0x193 Grass Green
    (15, 9, 1),     # 6: 0xF91 Vibrant Orange
    (2, 5, 12),     # 7: 0x25C Deep Blue
    (15, 12, 2),    # 8: 0xFC2 Vibrant Gold / Yellow
    (13, 10, 6),    # 9: 0xDA6 Light Wood / Sand
    (11, 7, 4),     # 10: 0xB74 Stone / Earth
    (8, 1, 3),      # 11: 0x813 Rich Maroon (Red Slime & Bat body shadow)
    (13, 1, 2),     # 12: 0xD12 Vibrant Red (Red Slime & Bat wings / Snail foot)
    (8, 9, 11),     # 13: 0x89B Slate Grey/Blue (Octo dome / tiles 145/147/158)
    (1, 7, 7),      # 14: 0x177 Vibrant Teal (Slime & Ghost shadow)
    (12, 10, 8)     # 15: 0xCA8 Tan / Warm Stone / Peach
]


def asm_line(op: str, val: str, comment: str = "", col: int = 40) -> str:
    """Format an assembly directive line with aligned comments."""
    left = f"    {op:<8}{val}"
    if comment:
        spaces = max(1, col - len(left))
        return f"{left}{' ' * spaces}; {comment}"
    return left


def sanitize_label(name: str) -> str:
    """Sanitize string for use as an assembly label or filename."""
    clean = "".join(c if c.isalnum() or c == "_" else "_" for c in name.strip())
    while "__" in clean:
        clean = clean.replace("__", "_")
    return clean.strip("_")


def parse_tile_layer(layer_elem, width: int, height: int, tilesets: list = None, firstgid: int = 1, raw: bool = False) -> list:
    """Decode tile layer data across CSV, base64, zlib, gzip, or XML."""
    data_elem = layer_elem.find("data")
    if data_elem is None:
        return [0] * (width * height)

    encoding = data_elem.attrib.get("encoding", "").lower()
    compression = data_elem.attrib.get("compression", "").lower()

    def map_gid(g: int) -> int:
        if raw:
            return g
        # Tiled GID 0 = empty space (0).
        # GID >= firstgid maps to 0-based tileset index: g - firstgid
        if g <= 0:
            return 0
        if tilesets:
            for ts in tilesets:
                fg = ts["firstgid"]
                if g >= fg:
                    return g - fg
            return 0
        return max(0, g - firstgid)

    # 1. Plain CSV format
    if encoding == "csv":
        text = data_elem.text or ""
        tokens = [t.strip() for t in text.replace("\n", "").split(",") if t.strip()]
        tiles = [map_gid(int(t) & 0x1FFFFFFF) for t in tokens]
        if len(tiles) < width * height:
            tiles.extend([0] * (width * height - len(tiles)))
        return tiles[:width * height]

    # 2. Base64 format (uncompressed, zlib, gzip)
    elif encoding == "base64":
        raw_b64 = (data_elem.text or "").strip()
        binary_data = base64.b64decode(raw_b64)
        if compression == "zlib":
            binary_data = zlib.decompress(binary_data)
        elif compression == "gzip":
            binary_data = gzip.decompress(binary_data)
        elif compression != "":
            raise ValueError(f"Unsupported compression: {compression}")

        # Tile GIDs are 32-bit unsigned integers
        count = len(binary_data) // 4
        tiles = [map_gid(gid & 0x1FFFFFFF) for gid in struct.unpack(f"<{count}I", binary_data)]
        if len(tiles) < width * height:
            tiles.extend([0] * (width * height - len(tiles)))
        return tiles[:width * height]

    # 3. Raw XML <tile gid="..."/> elements
    else:
        tiles = []
        for tile in data_elem.findall("tile"):
            gid = int(tile.attrib.get("gid", 0)) & 0x1FFFFFFF
            tiles.append(map_gid(gid))
        if len(tiles) < width * height:
            tiles.extend([0] * (width * height - len(tiles)))
        return tiles[:width * height]


def parse_properties(elem) -> dict:
    """Extract properties dictionary from an XML element."""
    props = {}
    props_elem = elem.find("properties")
    if props_elem is not None:
        for p in props_elem.findall("property"):
            name = p.attrib.get("name", "")
            val = p.attrib.get("value")
            if val is None:
                val = p.text or ""
            props[name.lower()] = val
    return props


def parse_tileset_attributes(tmx_dir: Path, tileset_elem) -> dict:
    """Parse collision attributes from external .tsx or embedded tileset."""
    attr_table = {}
    tsx_source = tileset_elem.attrib.get("source")
    root = tileset_elem

    if tsx_source:
        tsx_path = (tmx_dir / tsx_source).resolve()
        if tsx_path.exists():
            tree = ET.parse(tsx_path)
            root = tree.getroot()

    for tile in root.findall("tile"):
        tile_id_str = tile.attrib.get("id")
        if tile_id_str is None:
            continue
        tile_id = int(tile_id_str)
        tile_type = (tile.attrib.get("type") or tile.attrib.get("class") or "").lower()
        props = parse_properties(tile)
        
        attr_val = None
        if tile_type in ATTR_MAP:
            attr_val = ATTR_MAP[tile_type]
        elif "attribute" in props:
            attr_val = ATTR_MAP.get(props["attribute"].lower(), ATTR_SOLID)
        elif "collision" in props:
            attr_val = ATTR_MAP.get(props["collision"].lower(), ATTR_SOLID)
        elif "solid" in props and props["solid"] in ("1", "true"):
            attr_val = ATTR_SOLID
        elif "ladder" in props and props["ladder"] in ("1", "true"):
            attr_val = ATTR_LADDER

        if attr_val is not None:
            attr_table[tile_id] = attr_val

    return attr_table


def parse_tileset_full(tmx_dir: Path, tileset_elem) -> dict:
    """Parse full metadata, collision attributes, tile types, and properties from a tileset."""
    fg = int(tileset_elem.attrib.get("firstgid", 1))
    tsx_source = tileset_elem.attrib.get("source")
    name = tileset_elem.attrib.get("name", "")
    root = tileset_elem

    if tsx_source:
        tsx_path = (tmx_dir / tsx_source).resolve()
        if tsx_path.exists():
            tree = ET.parse(tsx_path)
            root = tree.getroot()
            if not name:
                name = root.attrib.get("name", tsx_path.stem)

    img_elem = root.find("image")
    img_source = img_elem.attrib.get("source", "") if img_elem is not None else ""
    tilecount = int(root.attrib.get("tilecount", 256))

    # Category determination
    ident = f"{name} {tsx_source or ''} {img_source}".lower()
    if "enemy" in ident or "enemies" in ident:
        category = "enemies"
    elif "friend" in ident or "animal" in ident:
        category = "friends"
    elif "player" in ident or "millie" in ident:
        category = "player"
    else:
        category = "world"

    tile_types = {}
    tile_props = {}
    attr_table = {}

    for tile in root.findall("tile"):
        tid_str = tile.attrib.get("id")
        if tid_str is None:
            continue
        tid = int(tid_str)
        ttype = (tile.attrib.get("type") or tile.attrib.get("class") or "").lower()
        props = parse_properties(tile)
        tile_types[tid] = ttype
        tile_props[tid] = props

        attr_val = None
        if ttype in ATTR_MAP:
            attr_val = ATTR_MAP[ttype]
        elif "attribute" in props:
            attr_val = ATTR_MAP.get(props["attribute"].lower(), ATTR_SOLID)
        elif "collision" in props:
            attr_val = ATTR_MAP.get(props["collision"].lower(), ATTR_SOLID)
        elif "solid" in props and props["solid"] in ("1", "true"):
            attr_val = ATTR_SOLID
        elif "ladder" in props and props["ladder"] in ("1", "true"):
            attr_val = ATTR_LADDER

        if attr_val is not None:
            attr_table[tid] = attr_val

    return {
        "firstgid": fg,
        "name": name,
        "category": category,
        "source": tsx_source,
        "img_source": img_source,
        "tilecount": tilecount,
        "tile_types": tile_types,
        "tile_props": tile_props,
        "attr_table": attr_table,
        "element": tileset_elem,
        "root": root
    }


def convert_tileset_image(tmx_dir: Path, tileset_elem, project_root: Path):
    """
    Extract tileset image from TSX, convert to Amiga 4-bitplane interleaved .raw and .msk.
    Appends the 16-color OCS palette to the end of the .raw file.
    """
    try:
        from PIL import Image
    except ImportError:
        return None

    tsx_source = tileset_elem.attrib.get("source")
    root = tileset_elem
    tsx_dir = tmx_dir

    if tsx_source:
        tsx_path = (tmx_dir / tsx_source).resolve()
        if tsx_path.exists():
            tree = ET.parse(tsx_path)
            root = tree.getroot()
            tsx_dir = tsx_path.parent

    img_elem = root.find("image")
    if img_elem is None:
        return None

    img_source = img_elem.attrib.get("source")
    if not img_source:
        return None

    img_path = (tsx_dir / img_source).resolve()
    if not img_path.exists():
        return None

    print(f"  [*] Converting tileset image: {img_path.name}")
    img = Image.open(img_path).convert("RGBA")
    w, h = img.size
    pixels = img.load()

    palette_ocs = DEFAULT_PALETTE_OCS

    def nearest_pal(ro, go, bo):
        best_dist = 999999
        best_idx = 1
        for idx, (pr, pg, pb) in enumerate(palette_ocs[1:], start=1):
            dist = (ro - pr)**2 + (go - pg)**2 + (bo - pb)**2
            if dist < best_dist:
                best_dist = dist
                best_idx = idx
        return best_idx

    indexed = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a > 128:
                ro = round(r * 15 / 255)
                go = round(g * 15 / 255)
                bo = round(b * 15 / 255)
                indexed[y][x] = nearest_pal(ro, go, bo)

    semi_transparent_tiles = {104, 115}
    for tile in root.findall("tile"):
        tid_str = tile.attrib.get("id")
        if tid_str is not None:
            tid = int(tid_str)
            ttype = (tile.attrib.get("type") or tile.attrib.get("class") or "").lower()
            props = parse_properties(tile)
            if ttype == "water" or props.get("semi_transparent") in ("1", "true") or props.get("water") in ("1", "true"):
                semi_transparent_tiles.add(tid)
    if semi_transparent_tiles:
        print(f"    Semi-transparent tiles: {sorted(list(semi_transparent_tiles))}")

    row_bytes = w // 8
    raw_bytes = bytearray()
    msk_bytes = bytearray()
    cols = int(root.attrib.get("columns", w // 16))

    for y in range(h):
        tile_row = y // 16
        for plane in range(4):
            line = bytearray(row_bytes)
            mask = bytearray(row_bytes)
            for x in range(w):
                tile_col = x // 16
                tile_id = tile_row * cols + tile_col
                idx = indexed[y][x]
                bit = (idx >> plane) & 1
                if tile_id in semi_transparent_tiles:
                    # 50% checkerboard dither pattern for OCS semi-transparency
                    solid = 1 if (idx != 0 and (x + y) % 2 == 0) else 0
                else:
                    solid = 1 if idx != 0 else 0
                bp = x // 8
                shift = 7 - (x % 8)
                line[bp] |= (bit << shift)
                mask[bp] |= (solid << shift)
            raw_bytes.extend(line)
            msk_bytes.extend(mask)

    # Append 16-color palette
    for r, g, b in palette_ocs:
        wrd = (r << 8) | (g << 4) | b
        raw_bytes.extend(struct.pack('>H', wrd))

    tiles_dir = project_root / "assets" / "graphics" / "tiles"
    tiles_dir.mkdir(parents=True, exist_ok=True)
    raw_path = tiles_dir / "FourSeasons.tiles_176x256.raw"
    msk_path = tiles_dir / "FourSeasons.tiles_176x256.msk"

    with open(raw_path, "wb") as f:
        f.write(raw_bytes)
    with open(msk_path, "wb") as f:
        f.write(msk_bytes)

    print(f"    Exported tileset raw: {raw_path} ({len(raw_bytes)} bytes)")
    print(f"    Exported tileset msk: {msk_path} ({len(msk_bytes)} bytes)")
    return {
        "columns": int(root.attrib.get("columns", w // 16)),
        "width": w,
        "height": h,
        "raw_path": raw_path,
        "msk_path": msk_path,
        "palette": palette_ocs
    }


def write_binary_map(file_path: Path, width: int, height: int, tile_indices: list):
    """
    Write Amiga binary map format:
      Offset 0..3: uint32 Width (Little-Endian)
      Offset 4..7: uint32 Height (Little-Endian)
      Offset 8+:   uint16 Tile Index words (Little-Endian)
    """
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with open(file_path, "wb") as f:
        # 8-byte header
        f.write(struct.pack("<II", width, height))
        # Tile index grid
        for tile in tile_indices:
            f.write(struct.pack("<H", tile & 0xFFFF))


def export_tmx(tmx_file: str, out_dir: str = None, asm_out: str = None, prefix: str = None):
    tmx_path = Path(tmx_file).resolve()
    if not tmx_path.exists():
        print(f"Error: File not found: {tmx_path}", file=sys.stderr)
        sys.exit(1)

    tmx_dir = tmx_path.parent
    if out_dir is None:
        out_dir = tmx_dir
    else:
        out_dir = Path(out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    file_stem = tmx_path.stem
    if prefix is None:
        prefix = sanitize_label(file_stem)

    print(f"[*] Processing Tiled TMX: {tmx_path}")
    tree = ET.parse(tmx_path)
    root = tree.getroot()

    width = int(root.attrib.get("width", 20))
    height = int(root.attrib.get("height", 42))
    tile_w = int(root.attrib.get("tilewidth", 16))
    tile_h = int(root.attrib.get("tileheight", 16))

    print(f"    Map dimensions: {width}x{height} tiles ({width * tile_w}x{height * tile_h} px), tile size: {tile_w}x{tile_h}")

    # Parse map-level custom properties with sensible defaults
    map_props = parse_properties(root)

    music_name = map_props.get("music", map_props.get("bgm", map_props.get("mod", "LevelMod"))).strip()
    tileset_raw = map_props.get("tileset_raw", map_props.get("tileset", "GameTilesRaw")).strip()
    tileset_msk = map_props.get("tileset_msk", "GameTilesMsk").strip()
    palette_name = map_props.get("palette", f"{prefix}_Palette").strip()

    # Camera scroll bounds: map height minus visible viewport (13 rows = 208px)
    max_cam_y_default = max(0, (height - 13) * 16)
    min_cam_y = int(map_props.get("min_camera_y", map_props.get("mincameray", 0)))
    max_cam_y = int(map_props.get("max_camera_y", map_props.get("maxcameray", max_cam_y_default)))
    if "initial_row" in map_props:
        init_cam_y = int(map_props["initial_row"]) * 16
    elif "initial_tile_row" in map_props:
        init_cam_y = int(map_props["initial_tile_row"]) * 16
    else:
        init_cam_y = int(map_props.get("initial_camera_y", map_props.get("initialcameray", map_props.get("cameray", max_cam_y_default))))

    # Camera deadzone margins:
    # cam_margin_top = 16 (1 row below top)
    # cam_margin_bottom = (No_of_visible_rows - 1) * 16 = (12 - 1) * 16 = 176 (1 row above bottom of visible screen)
    VISIBLE_SCREEN_ROWS = 12
    cam_margin_top = int(map_props.get("cam_margin_top", 16))
    cam_margin_bottom = int(map_props.get("cam_margin_bottom", (VISIBLE_SCREEN_ROWS - 1) * 16))

    # Banner title & sub_title (hint alias maintained for compatibility)
    level_title = map_props.get("title", map_props.get("level_title", map_props.get("name", prefix.replace("_", " ").upper()))).strip()
    level_sub_title = map_props.get("sub_title", map_props.get("subtitle", map_props.get("hint", map_props.get("level_hint", "")))).strip()

    # Auto-generate 6-char access password from level prefix (e.g. Level_01 -> ACORN1, Level_02 -> ACORN2)
    level_num_str = "".join(ch for ch in prefix if ch.isdigit())
    default_code = f"ACORN{int(level_num_str)}" if level_num_str else "ACORN1"
    raw_code = map_props.get("access_code", map_props.get("password", map_props.get("code", default_code))).strip().upper()
    access_code = (raw_code[:6] if len(raw_code) >= 6 else raw_code.ljust(6, " "))[:6]

    # Parse tilesets with full categorization and properties
    tileset_attrs = {}
    tileset_info = None
    project_root = Path(__file__).resolve().parent.parent
    tilesets = []
    for ts_elem in root.findall("tileset"):
        ts_data = parse_tileset_full(tmx_dir, ts_elem)
        tilesets.append(ts_data)
        for local_id, attr_val in ts_data["attr_table"].items():
            tileset_attrs[local_id] = attr_val
        # Only convert graphics for the world tileset (AmigaGameEngine)
        if ts_data["category"] == "world" and not tileset_info:
            ts_info = convert_tileset_image(tmx_dir, ts_elem, project_root)
            if ts_info:
                tileset_info = ts_info

    tilesets.sort(key=lambda t: t["firstgid"], reverse=True)

    def lookup_tile(g: int):
        if g <= 0:
            return None
        for ts in tilesets:
            if g >= ts["firstgid"]:
                local_id = g - ts["firstgid"]
                # In the world tileset (AmigaGameEngine), tile 0 is the 100% transparent dummy tile.
                # In Tiled, selecting this empty tile writes GID = firstgid (usually 1).
                # It has no graphics and should be treated as empty.
                if ts["category"] == "world" and local_id == 0:
                    return None
                return {
                    "tileset": ts,
                    "local_id": local_id,
                    "category": ts["category"],
                    "type": ts["tile_types"].get(local_id, ""),
                    "props": ts["tile_props"].get(local_id, {}),
                    "attr": ts["attr_table"].get(local_id, ATTR_EMPTY)
                }
        return None

    # Grids & object containers
    scenery_grid = [0] * (width * height)
    platform_grid = [0] * (width * height)
    ladder_grid = [0] * (width * height)
    foreground_grid = [0] * (width * height)
    water_grid = [0] * (width * height)
    gamemap = [BLOCK_EMPTY] * (width * height)
    tile_layers = []

    player_start = {"x": 24, "y": 512, "col": 1, "row": 31, "xdec": 8, "dir": 1}
    player2_start = {"x": 0, "y": 0, "col": 0, "row": 0, "xdec": 0, "dir": 0}
    player2_found = False
    enemies = []
    enemies_pending = []
    friends = []
    solids = []
    ladders = []
    pushes = []
    dirts = []
    cocoons = []
    acids = []
    triggers = []
    hazards = []
    bridges = []
    oxygen_refills = []
    generic_objects = []

    # Parse tile layers
    for layer in root.findall("layer"):
        layer_name = layer.attrib.get("name", "layer").strip()
        layer_slug = sanitize_label(layer_name)
        lname = layer_name.lower()
        raw_tiles = parse_tile_layer(layer, width, height, raw=True)
        non_zero = sum(1 for t in raw_tiles if t != 0)

        is_foreground_layer = any(k in lname for k in ("foreground", "fg"))
        is_water_layer = "water" in lname
        is_entities_layer = any(k in lname for k in ("entit", "actor", "spawn", "object", "item"))
        is_ladders_layer = any(k in lname for k in ("ladder", "climb", "vine"))
        is_background_layer = any(k in lname for k in ("scenery", "bg", "back", "decor")) or lname == "background"
        is_platforms_layer = not (is_foreground_layer or is_background_layer or is_ladders_layer) and (any(k in lname for k in ("platform", "solid", "floor")) or lname in ("ground", "platforms", "solids"))

        # Fallback if no specific role matched: treat as background
        if not (is_entities_layer or is_platforms_layer or is_ladders_layer or is_water_layer or is_foreground_layer or is_background_layer):
            is_background_layer = True

        role_str = "entities" if is_entities_layer else "platforms" if is_platforms_layer else "ladders" if is_ladders_layer else "water" if is_water_layer else "foreground" if is_foreground_layer else "background"
        print(f"    Found Tile Layer: '{layer_name}' (Non-zero tiles: {non_zero}/{len(raw_tiles)}) [role: {role_str}]")

        for idx, g in enumerate(raw_tiles):
            if g == 0:
                continue
            c = idx % width
            r = idx // width
            t_info = lookup_tile(g)
            if not t_info:
                continue

            category = t_info["category"]
            ttype = t_info["type"]
            props = t_info["props"]
            local_id = t_info["local_id"]

            # 1. Entity detection (runs on entities layer OR if an entity tileset was used anywhere)
            if is_entities_layer or category in ("enemies", "friends", "player") or ttype in ("player", "crate", "oxygen", "oxygen_refill", "air") or ttype.startswith("enemy") or ttype.startswith("friend") or (category == "world" and local_id == 95):
                # Player
                if category == "player" or ttype == "player" or "player" in ttype:
                    player_start["col"] = c
                    player_start["row"] = r
                    player_start["x"] = c * 16
                    player_start["y"] = r * 16
                    dir_val = props.get("direction", 1)
                    player_start["dir"] = 1 if str(dir_val).lower() in ("1", "right") else -1
                    print(f"      [Tile] -> Player Spawn: ({c*16}, {r*16}) -> Col={c}, Row={r}, dir={player_start['dir']}")

                # Enemy
                elif category == "enemies" or ttype.startswith("enemy") or "enemy" in ttype:
                    if "type" in props:
                        e_type = int(props["type"])
                    else:
                        e_type = min(8, max(1, (local_id // 4) + 1))
                    e_speed = int(props.get("speed", 2 if e_type in (3, 6) else 1))
                    enemies_pending.append({
                        "type": e_type,
                        "col": c,
                        "row": r,
                        "x": c * 16,
                        "y": r * 16,
                        "speed": e_speed,
                        "patrol_min_x": int(props["patrol_min_x"]) if "patrol_min_x" in props else None,
                        "patrol_max_x": int(props["patrol_max_x"]) if "patrol_max_x" in props else None,
                    })

                # Friend
                elif category == "friends" or ttype.startswith("friend") or "friend" in ttype:
                    if "type" in props:
                        f_type = int(props["type"])
                    else:
                        f_type = min(5, max(1, (local_id // 4) + 1))
                    f_name = props.get("name", f"FRIEND_{len(friends)+1}")
                    friends.append({
                        "type": f_type,
                        "name": f_name,
                        "col": c,
                        "row": r,
                        "x": c * 16,
                        "y": r * 16
                    })
                    print(f"      [Tile] -> Friend: '{f_name}' (type={f_type}) at Col={c}, Row={r} ({c*16}, {r*16})")

                # Push Crate
                elif ttype == "crate" or (category == "world" and local_id == 37) or "crate" in ttype or g == 38:
                    sprite_idx = int(props.get("sprite", 37))
                    pushes.append({
                        "col": c,
                        "row": r,
                        "sprite": sprite_idx,
                        "name": f"CRATE_{len(pushes)+1}",
                        "col_start": c,
                        "col_end": c,
                        "row_start": r,
                        "row_end": r
                    })
                    gamemap[idx] = BLOCK_PUSH
                    print(f"      [Tile] -> Push Block: Col={c}, Row={r} (sprite={sprite_idx})")

                # Oxygen Refill Pickup (Tile ID 95, GID 96)
                elif local_id == 95 or ttype in ("oxygen", "oxygen_refill", "air") or "oxygen" in ttype or (category == "world" and local_id == 95):
                    oxygen_refills.append({
                        "col": c,
                        "row": r,
                        "x": c * 16,
                        "y": r * 16,
                        "tile_id": local_id
                    })
                    print(f"      [Tile] -> Oxygen Refill: Col={c}, Row={r} ({c*16}, {r*16})")

                # Entities do NOT draw into tilemap
                continue

            # 2. Visual / Collision Layer processing
            if is_foreground_layer:
                if category == "world":
                    foreground_grid[idx] = local_id

            elif is_water_layer:
                if category == "world":
                    water_grid[idx] = local_id

            elif is_platforms_layer:
                if category == "world":
                    platform_grid[idx] = local_id
                gamemap[idx] = BLOCK_SOLID

            elif is_ladders_layer:
                if category == "world":
                    ladder_grid[idx] = local_id
                gamemap[idx] = BLOCK_LADDER

            elif is_background_layer:
                if category == "world":
                    scenery_grid[idx] = local_id
                # Check TSX collision attribute
                attr = t_info["attr"]
                if attr == ATTR_SOLID:
                    gamemap[idx] = BLOCK_SOLID
                elif attr == ATTR_LADDER:
                    gamemap[idx] = BLOCK_LADDER

    # Parse object layers (metadata, spawns, triggers, overrides)
    for objgroup in root.findall("objectgroup"):
        group_name = objgroup.attrib.get("name", "elements")
        print(f"    Found Object Layer: '{group_name}'")
        for obj in objgroup.findall("object"):
            obj_id = int(obj.attrib.get("id", 0))
            name = (obj.attrib.get("name") or "").strip()
            obj_type = (obj.attrib.get("type") or obj.attrib.get("class") or name).strip()
            x = float(obj.attrib.get("x", 0))
            y = float(obj.attrib.get("y", 0))
            w = float(obj.attrib.get("width", 0))
            h = float(obj.attrib.get("height", 0))
            props = parse_properties(obj)

            tag = obj_type.lower()
            name_lower = name.lower()

            # Tile bounding box (16x16 grid)
            col_start = max(0, min(width - 1, int(round(x / 16.0))))
            col_end = max(0, min(width - 1, int(round((x + max(w, 1.0)) / 16.0)) - 1))
            row_start = max(0, min(height - 1, int(round(y / 16.0))))
            row_end = max(0, min(height - 1, int(round((y + max(h, 1.0)) / 16.0)) - 1))

            # Identify Player Spawn
            is_player = (
                "player" in tag or "player" in name_lower or
                "millie" in tag or "millie" in name_lower or
                "price" in tag or "price" in name_lower or
                "cole" in tag or "cole" in name_lower or
                "spawn" in tag or "spawn" in name_lower
            )

            if is_player:
                p1_col = int(round(x)) // 16
                p1_row = int(round(y / 16.0))
                p1_xdec = int(round(x)) % 16
                p1_dir_raw = props.get("direction", props.get("dir", props.get("facing", 1)))
                p1_dir = -1 if str(p1_dir_raw).lower() in ("left", "-1", "0") else 1
                player_start["x"] = int(round(x))
                player_start["y"] = int(round(y))
                player_start["col"] = max(0, min(width - 1, p1_col))
                player_start["row"] = max(0, min(height - 1, p1_row))
                player_start["xdec"] = p1_xdec
                player_start["dir"] = p1_dir
                print(f"      -> Player Spawn (Object): ({x}, {y}) -> Col={player_start['col']}, Row={player_start['row']}, XDec={p1_xdec}, dir={p1_dir}")

            # Identify Enemies
            elif "enemy" in tag or "patrol" in tag or "flyer" in tag or "crawler" in tag or "enemy" in name_lower:
                enemy_type = int(props.get("type", 1))
                patrol_min = int(props.get("patrol_min_x", int(round(x)) - 64))
                patrol_max = int(props.get("patrol_max_x", int(round(x)) + 64))
                speed = int(props.get("speed", 1))
                max_patrol_x = (width - 2) * 16
                patrol_min = max(0, min(max_patrol_x, patrol_min))
                patrol_max = max(patrol_min + 16, min(max_patrol_x, patrol_max))
                e_col = max(0, min(width - 1, int(round(x)) // 16))
                e_row = max(0, min(height - 1, int(round(y / 16.0))))
                enemies.append({
                    "type": enemy_type,
                    "x": int(round(x)),
                    "y": int(round(y)),
                    "col": e_col,
                    "row": e_row,
                    "patrol_min": patrol_min,
                    "patrol_max": patrol_max,
                    "speed": speed
                })
                print(f"      -> Enemy (Object): type={enemy_type} at ({x}, {y}) -> Col={e_col}, Row={e_row}, patrol=[{patrol_min}..{patrol_max}]")

            elif "friend" in tag or "friend" in name_lower:
                friend_type = 1
                if "dog1" in name_lower or "d1" in name_lower or "shiba" in name_lower or "tan" in name_lower:
                    friend_type = 1
                elif "dog2" in name_lower or "d2" in name_lower or "puppy" in name_lower or "white" in name_lower or "dog" in name_lower:
                    friend_type = 2
                elif "duck" in name_lower:
                    friend_type = 3
                elif "bunny" in name_lower or "rabbit" in name_lower or "lion" in name_lower:
                    friend_type = 1
                elif "kitten" in name_lower or "cat" in name_lower:
                    friend_type = 2
                elif "chick" in name_lower or "bird" in name_lower:
                    friend_type = 3

                if w > 0:
                    center_x = x + (w / 2.0)
                else:
                    center_x = x
                spawn_x = int(round(center_x)) - 8
                spawn_x = max(0, min((width * 16) - 16, spawn_x))

                if h > 0:
                    spawn_y = int(round(y + h)) - 16
                elif int(round(y)) % 16 == 0:
                    spawn_y = int(round(y)) - 16
                else:
                    spawn_y = int(round(y))
                spawn_y = max(0, min((height * 16) - 16, spawn_y))

                f_col = max(0, min(width - 1, spawn_x // 16))
                f_row = max(0, min(height - 1, spawn_y // 16))

                friends.append({
                    "type": friend_type,
                    "name": name,
                    "x": spawn_x,
                    "y": spawn_y,
                    "col": f_col,
                    "row": f_row,
                })
                print(f"      -> Friend (Object): '{name}' (type={friend_type}) at ({spawn_x}, {spawn_y}) -> Col={f_col}, Row={f_row}")

            elif "bridge" in tag or "bridge" in name_lower:
                bridges.append({
                    "col_start": col_start,
                    "col_end": col_end,
                    "row_start": row_start,
                    "row_end": row_end,
                    "x": int(round(x)),
                    "y": int(round(y)),
                    "w": int(round(w)),
                    "h": int(round(h))
                })
                solids.append({
                    "col_start": col_start,
                    "col_end": col_end,
                    "row_start": row_start,
                    "row_end": row_end,
                    "x": int(round(x)),
                    "y": int(round(y)),
                    "w": int(round(w)),
                    "h": int(round(h))
                })

            elif "ladder" in tag or "ladder" in name_lower or "climb" in tag:
                ladders.append({
                    "col_start": col_start,
                    "col_end": col_end,
                    "row_start": row_start,
                    "row_end": row_end,
                    "x": int(round(x)),
                    "y": int(round(y)),
                    "w": int(round(w)),
                    "h": int(round(h))
                })

            elif "solid" in tag or "solid" in name_lower or "platform" in tag or "platform" in name_lower or "wall" in tag or "wall" in name_lower or (not tag and not name_lower and w > 0 and h > 0):
                solids.append({
                    "col_start": col_start,
                    "col_end": col_end,
                    "row_start": row_start,
                    "row_end": row_end,
                    "x": int(round(x)),
                    "y": int(round(y)),
                    "w": int(round(w)),
                    "h": int(round(h))
                })

            elif "push" in tag or "push" in name_lower or "movable" in tag or "movable" in name_lower or "crate" in tag or "crate" in name_lower:
                sprite_index = 37
                if "crate" in name_lower or "crate" in tag:
                    sprite_index = 37
                elif "sprite" in props:
                    sprite_index = int(props["sprite"])
                elif "tile_id" in props:
                    sprite_index = int(props["tile_id"])

                if w > 0 and h > 0:
                    for r in range(row_start, row_end + 1):
                        for c in range(col_start, col_end + 1):
                            pushes.append({
                                "col": c,
                                "row": r,
                                "sprite": sprite_index,
                                "name": name or "CRATE",
                                "col_start": c,
                                "col_end": c,
                                "row_start": r,
                                "row_end": r
                            })
                else:
                    spawn_x = int(round(x))
                    spawn_y = int(round(y)) - 16 if int(round(y)) % 16 == 0 else int(round(y))
                    p_col = max(0, min(width - 1, spawn_x // 16))
                    p_row = max(0, min(height - 1, spawn_y // 16))
                    pushes.append({
                        "col": p_col,
                        "row": p_row,
                        "sprite": sprite_index,
                        "name": name or "CRATE",
                        "col_start": p_col,
                        "col_end": p_col,
                        "row_start": p_row,
                        "row_end": p_row
                    })

            elif "dirt" in tag or "dirt" in name_lower or "breakable" in tag:
                dirts.append({
                    "col_start": col_start,
                    "col_end": col_end,
                    "row_start": row_start,
                    "row_end": row_end,
                })

            elif "cocoon" in tag or "cocoon" in name_lower:
                cocoons.append({
                    "col_start": col_start,
                    "col_end": col_end,
                    "row_start": row_start,
                    "row_end": row_end,
                })

            elif "hazard" in tag or "spike" in tag or "acid" in tag or "lava" in tag or "hazard" in name_lower:
                damage = int(props.get("damage", 1))
                hazards.append({
                    "damage": damage,
                    "left": int(round(x)),
                    "top": int(round(y)),
                    "right": int(round(x + w)),
                    "bottom": int(round(y + h))
                })
                if "acid" in tag or "acid" in name_lower:
                    acids.append({
                        "col_start": col_start,
                        "col_end": col_end,
                        "row_start": row_start,
                        "row_end": row_end,
                    })

            elif "trigger" in tag or "exit" in tag or "door" in tag or "boss" in tag or "trigger" in name_lower:
                trig_id = int(props.get("trigger_id", props.get("id", len(triggers) + 1)))
                target = props.get("target", "")
                triggers.append({
                    "id": trig_id,
                    "left": int(round(x)),
                    "top": int(round(y)),
                    "right": int(round(x + w)),
                    "bottom": int(round(y + h)),
                    "target": target
                })

            elif "oxygen" in tag or "oxygen" in name_lower or "air" in tag or "bottle" in tag:
                spawn_x = int(round(x))
                spawn_y = int(round(y)) - 16 if int(round(y)) % 16 == 0 else int(round(y))
                o_col = max(0, min(width - 1, spawn_x // 16))
                o_row = max(0, min(height - 1, spawn_y // 16))
                tile_idx = int(props.get("tile_id", props.get("sprite", 95)))
                oxygen_refills.append({
                    "col": o_col,
                    "row": o_row,
                    "x": o_col * 16,
                    "y": o_row * 16,
                    "tile_id": tile_idx
                })
                print(f"      [Object] -> Oxygen Refill: Col={o_col}, Row={o_row} ({o_col*16}, {o_row*16})")

            else:
                generic_objects.append({
                    "name": name,
                    "type": obj_type,
                    "x": int(round(x)),
                    "y": int(round(y)),
                    "w": int(round(w)),
                    "h": int(round(h)),
                    "props": props
                })

    # =========================================================================
    # Construct 1D GameMap Array & Auto-Extract Missing Objects
    # =========================================================================
    print(f"[*] Constructing 1D GameMap ({width} cols x {height} rows = {width * height} bytes)...")

    # 1. Stamp solids from objectgroup
    for s in solids:
        for r in range(s["row_start"], s["row_end"] + 1):
            for c in range(s["col_start"], s["col_end"] + 1):
                gamemap[r * width + c] = BLOCK_SOLID

    # 2. Stamp ladders from objectgroup
    for l in ladders:
        for r in range(l["row_start"], l["row_end"] + 1):
            for c in range(l["col_start"], l["col_end"] + 1):
                gamemap[r * width + c] = BLOCK_LADDER

    # 3. Auto-detect ladders from tilemap if not defined by objectgroup
    for c in range(width):
        r = 0
        while r < height:
            if gamemap[r * width + c] == BLOCK_LADDER:
                r_start = r
                while r < height and gamemap[r * width + c] == BLOCK_LADDER:
                    r += 1
                r_end = r - 1
                already_covered = any(l["col_start"] <= c <= l["col_end"] and l["row_start"] <= r_start and l["row_end"] >= r_end for l in ladders)
                if not already_covered:
                    ladders.append({
                        "col_start": c,
                        "col_end": c,
                        "row_start": r_start,
                        "row_end": r_end,
                        "x": c * 16,
                        "y": r_start * 16,
                        "w": 16,
                        "h": (r_end - r_start + 1) * 16
                    })
                    print(f"      [Auto-Ladder] -> Col={c}, Rows [{r_start}..{r_end}] (h={(r_end - r_start + 1) * 16}px)")
            else:
                r += 1

    # 4. Auto-detect solids from tilemap if not defined by objectgroup
    if not solids:
        for r in range(height):
            c = 0
            while c < width:
                if gamemap[r * width + c] == BLOCK_SOLID:
                    c_start = c
                    while c < width and gamemap[r * width + c] == BLOCK_SOLID:
                        c += 1
                    c_end = c - 1
                    solids.append({
                        "col_start": c_start,
                        "col_end": c_end,
                        "row_start": r,
                        "row_end": r,
                        "x": c_start * 16,
                        "y": r * 16,
                        "w": (c_end - c_start + 1) * 16,
                        "h": 16
                    })
                else:
                    c += 1

    # 4b. Auto-detect bridges from platform_grid if not defined by objectgroup
    if not bridges:
        for r in range(height):
            c = 0
            while c < width:
                t = platform_grid[r * width + c]
                if t in (38, 39, 40, 90, 91, 92):
                    c_start = c
                    while c < width and platform_grid[r * width + c] in (38, 39, 40, 90, 91, 92):
                        c += 1
                    c_end = c - 1
                    bridges.append({
                        "col_start": c_start,
                        "col_end": c_end,
                        "row_start": r,
                        "row_end": r,
                        "x": c_start * 16,
                        "y": r * 16,
                        "w": (c_end - c_start + 1) * 16,
                        "h": 16
                    })
                    print(f"      [Auto-Bridge] -> Col [{c_start}..{c_end}], Row {r}, x={c_start * 16}, w={(c_end - c_start + 1) * 16}px")
                else:
                    c += 1

    # 5. Push, Dirt, Cocoon, Acid
    for p in pushes:
        for r in range(p["row_start"], p["row_end"] + 1):
            for c in range(p["col_start"], p["col_end"] + 1):
                gamemap[r * width + c] = BLOCK_PUSH
    for d in dirts:
        for r in range(d["row_start"], d["row_end"] + 1):
            for c in range(d["col_start"], d["col_end"] + 1):
                gamemap[r * width + c] = BLOCK_DIRT
    for co in cocoons:
        for r in range(co["row_start"], co["row_end"] + 1):
            for c in range(co["col_start"], co["col_end"] + 1):
                gamemap[r * width + c] = BLOCK_COCOON
    for a in acids:
        for r in range(a["row_start"], a["row_end"] + 1):
            for c in range(a["col_start"], a["col_end"] + 1):
                gamemap[r * width + c] = BLOCK_ACID

    # 6. Bottom boundary solid floor
    for c in range(width):
        gamemap[(height - 1) * width + c] = BLOCK_SOLID

    # 7. Auto-patrol resolution for pending tile-based enemies
    for ep in enemies_pending:
        c = ep["col"]
        r = ep["row"]
        if gamemap[r * width + c] == BLOCK_SOLID and r > 0:
            r -= 1
            ep["row"] = r
            ep["y"] = r * 16

        if ep["patrol_min_x"] is not None and ep["patrol_max_x"] is not None:
            p_min = ep["patrol_min_x"]
            p_max = ep["patrol_max_x"]
        else:
            floor_r = r + 1
            if floor_r < height and gamemap[floor_r * width + c] in (BLOCK_SOLID, BLOCK_PUSH):
                min_c = c
                while min_c > 0 and gamemap[floor_r * width + (min_c - 1)] in (BLOCK_SOLID, BLOCK_PUSH) and gamemap[r * width + (min_c - 1)] != BLOCK_SOLID:
                    min_c -= 1
                max_c = c
                while max_c < width - 1 and gamemap[floor_r * width + (max_c + 1)] in (BLOCK_SOLID, BLOCK_PUSH) and gamemap[r * width + (max_c + 1)] != BLOCK_SOLID:
                    max_c += 1
                p_min = min_c * 16
                p_max = max_c * 16
            else:
                p_min = max(0, (c - 3) * 16)
                p_max = min((width - 2) * 16, (c + 3) * 16)

        max_patrol_x = (width - 2) * 16
        p_min = max(0, min(max_patrol_x, p_min))
        p_max = max(p_min + 16, min(max_patrol_x, p_max))

        enemies.append({
            "type": ep["type"],
            "x": ep["x"],
            "y": ep["y"],
            "col": ep["col"],
            "row": ep["row"],
            "patrol_min": p_min,
            "patrol_max": p_max,
            "speed": ep["speed"]
        })
        print(f"      [Auto-Enemy] -> type={ep['type']} at ({ep['x']}, {ep['y']}) -> Col={c}, Row={r}, patrol=[{p_min}..{p_max}], speed={ep['speed']}")

    # 8. Enemy standing checks
    for e in enemies:
        if gamemap[e["row"] * width + e["col"]] == BLOCK_SOLID and e["row"] > 0:
            e["row"] -= 1
            e["y"] = e["row"] * 16

    # 9. Player spawn check
    if gamemap[player_start["row"] * width + player_start["col"]] == BLOCK_SOLID and player_start["row"] > 0:
        player_start["row"] -= 1
    gamemap[player_start["row"] * width + player_start["col"]] = BLOCK_PLAYERSTART

    # =========================================================================
    # Write Binary Tilemap & GameMap Files
    # =========================================================================
    print("[*] Generating Binary .map and -gamemap.bin files...")
    exported_map_files = []

    # 1. Background layer map (contains visual scenery)
    out_bg = out_dir / f"{prefix}-background.map"
    write_binary_map(out_bg, width, height, scenery_grid)
    exported_map_files.append(("background", f"{prefix}-background.map", out_bg))
    print(f"    Exported layer 'background': {out_bg} ({out_bg.stat().st_size} bytes)")

    # 2. Platform layer map (contains platforms, walls, floors, bridges)
    out_plat = out_dir / f"{prefix}-platform.map"
    write_binary_map(out_plat, width, height, platform_grid)
    exported_map_files.append(("platform", f"{prefix}-platform.map", out_plat))
    print(f"    Exported layer 'platform': {out_plat} ({out_plat.stat().st_size} bytes)")

    # 3. Ladder layer map (contains climbable ladders)
    out_ladder = out_dir / f"{prefix}-ladder.map"
    write_binary_map(out_ladder, width, height, ladder_grid)
    exported_map_files.append(("ladder", f"{prefix}-ladder.map", out_ladder))
    print(f"    Exported layer 'ladder': {out_ladder} ({out_ladder.stat().st_size} bytes)")

    # 4. Foreground layer map (contains trees, arches, canopy)
    out_fg = out_dir / f"{prefix}-foreground.map"
    write_binary_map(out_fg, width, height, foreground_grid)
    exported_map_files.append(("foreground", f"{prefix}-foreground.map", out_fg))
    print(f"    Exported layer 'foreground': {out_fg} ({out_fg.stat().st_size} bytes)")

    # 5. Water layer map (contains water tiles)
    out_water = out_dir / f"{prefix}-water.map"
    write_binary_map(out_water, width, height, water_grid)
    exported_map_files.append(("water", f"{prefix}-water.map", out_water))
    print(f"    Exported layer 'water': {out_water} ({out_water.stat().st_size} bytes)")

    # 6. Composite / Merged map (scenery + platforms + ladders + foreground)
    composite_grid = [0] * (width * height)
    for i in range(width * height):
        if scenery_grid[i] != 0:
            composite_grid[i] = scenery_grid[i]
        if platform_grid[i] != 0:
            composite_grid[i] = platform_grid[i]
        if ladder_grid[i] != 0:
            composite_grid[i] = ladder_grid[i]
        if foreground_grid[i] != 0:
            composite_grid[i] = foreground_grid[i]

    composite_name = f"{prefix}.map"
    composite_path = out_dir / composite_name
    write_binary_map(composite_path, width, height, composite_grid)
    print(f"    Exported composite map: {composite_path} ({composite_path.stat().st_size} bytes)")

    # 7. 1D GameMap Binary
    gamemap_name = f"{prefix}-gamemap.bin"
    gamemap_path = out_dir / gamemap_name
    with open(gamemap_path, "wb") as f_gmap:
        f_gmap.write(bytes(gamemap))
    print(f"    Exported 1D GameMap: {gamemap_path} ({len(gamemap)} bytes)")

    # =========================================================================
    # Write Assembly Metadata File
    # =========================================================================
    if asm_out is None:
        # Default to include/resources/<prefix>_entities.asm or out_dir/<prefix>_entities.asm
        include_dir = Path(__file__).resolve().parent.parent / "include" / "resources"
        if include_dir.exists():
            asm_path = include_dir / f"{prefix.lower()}_entities.asm"
        else:
            asm_path = out_dir / f"{prefix.lower()}_entities.asm"
    else:
        asm_path = Path(asm_out).resolve()

    asm_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"[*] Generating Assembly Metadata: {asm_path}")

    # Relative path from project root for incbins
    rel_out_dir = os.path.relpath(out_dir, asm_path.parent.parent.parent).replace("\\", "/")

    # The 4 reference source layers blitted into NonDisplayScreen:
    # 1. Scenery/Background, 2. Platforms, 3. Ladders, 4. Foreground
    ref_layer_slugs = ["background", "platform", "ladder", "foreground"]
    ref_layers = [f"{prefix}_{slug.capitalize()}Map" for slug in ref_layer_slugs if any(s == slug for s, _, _ in exported_map_files)]
    layer_count = len(ref_layers)

    asm_lines = [
        ";==============================================================================",
        f"; Auto-generated Level Metadata for {prefix}",
        f"; Generated from: {tmx_path.name}",
        ";==============================================================================",
        "",
        f"{prefix}_MapWidth:        dc.w    {width}",
        f"{prefix}_MapHeight:       dc.w    {height}",
        f"{prefix}_MapSize:         dc.w    {width * height}",
        f"{prefix}_TileWidth:       dc.w    {tile_w}",
        f"{prefix}_TileHeight:      dc.w    {tile_h}",
        f"{prefix}_LayerCount:      dc.w    {layer_count}",
        "",
        ";------------------------------------------------------------------------------",
        "; Tilemap Layer Binaries",
        ";------------------------------------------------------------------------------",
    ]

    for slug, fname, _ in exported_map_files:
        label = f"{prefix}_{slug.capitalize()}Map"
        rel_path = f"{rel_out_dir}/{fname}"
        asm_lines.extend([
            f"{label}:",
            f'    incbin     "{rel_path}"',
            "    even",
            ""
        ])
        if slug == "background":
            asm_lines.extend([
                f"{prefix}_SceneryMap = {prefix}_BackgroundMap",
                ""
            ])

    has_bg = any("bg" in slug.lower() or "background" in slug.lower() for slug, _, _ in exported_map_files)
    has_plat = any("plat" in slug.lower() or "platform" in slug.lower() for slug, _, _ in exported_map_files)
    has_ladder = any("ladder" in slug.lower() for slug, _, _ in exported_map_files)
    has_fg = any("fg" in slug.lower() or "foreground" in slug.lower() for slug, _, _ in exported_map_files)
    has_water = any("water" in slug.lower() for slug, _, _ in exported_map_files)
    if not has_bg:
        asm_lines.extend([
            f"{prefix}_BackgroundMap = 0",
            f"{prefix}_SceneryMap = 0",
            ""
        ])
    if not has_plat:
        asm_lines.extend([
            f"{prefix}_PlatformMap = 0",
            ""
        ])
    if not has_ladder:
        asm_lines.extend([
            f"{prefix}_LadderMap = 0",
            ""
        ])
    if not has_fg:
        asm_lines.extend([
            f"{prefix}_ForegroundMap = 0",
            ""
        ])
    if not has_water:
        asm_lines.extend([
            f"{prefix}_WaterMap = 0",
            ""
        ])

    # Ordered Layer Table (Blit Reference Source for NonDisplayScreen)
    asm_lines.extend([
        ";------------------------------------------------------------------------------",
        "; Ordered Tilemap Layer Table (Blit Reference Source for NonDisplayScreen)",
        "; Format: Pointers to each layer's binary map, terminated by 0",
        "; Order: 1. Scenery/Background, 2. Platforms, 3. Ladders, 4. Foreground",
        ";------------------------------------------------------------------------------",
        f"{prefix}_LayerList:"
    ])
    for label in ref_layers:
        asm_lines.append(f"    dc.l    {label}")
    asm_lines.extend([
        "    dc.l    0                           ; Null termination",
        ""
    ])

    # Composite map incbin
    asm_lines.extend([
        f"{prefix}_CompositeMap:",
        f'    incbin     "{rel_out_dir}/{composite_name}"',
        "    even",
        "",
        ";------------------------------------------------------------------------------",
        f"; 1D GameMap Binary ({width} cols x {height} rows = {width * height} bytes)",
        "; Format: 1 byte per tile, containing BLOCK_xxx values",
        ";------------------------------------------------------------------------------",
        f"{prefix}_GameMap:",
        f'    incbin     "{rel_out_dir}/{gamemap_name}"',
        "    even",
        "",
        ";------------------------------------------------------------------------------",
        "; Player Starting Coordinates",
        ";------------------------------------------------------------------------------",
        f"{prefix}_PlayerStartX:    dc.w    {player_start['x']}",
        f"{prefix}_PlayerStartY:    dc.w    {player_start['y']}",
        f"{prefix}_PlayerCol:       dc.w    {player_start['col']}",
        f"{prefix}_PlayerRow:       dc.w    {player_start['row']}",
        f"{prefix}_PlayerXDec:      dc.w    {player_start['xdec']}",
        f"{prefix}_PlayerDir:       dc.w    {player_start['dir']}       ; -1=Left, +1=Right",
        "",
        ";------------------------------------------------------------------------------",
        "; Player 2 Starting Coordinates (0 if solo)",
        ";------------------------------------------------------------------------------",
        f"{prefix}_Player2StartX:   dc.w    {player2_start['x']}",
        f"{prefix}_Player2StartY:   dc.w    {player2_start['y']}",
        f"{prefix}_Player2Col:      dc.w    {player2_start['col']}",
        f"{prefix}_Player2Row:      dc.w    {player2_start['row']}",
        f"{prefix}_Player2XDec:     dc.w    {player2_start['xdec']}",
        f"{prefix}_Player2Dir:      dc.w    {player2_start['dir']}       ; -1=Left, +1=Right (0=Solo)",
        "",
        ";------------------------------------------------------------------------------",
        "; Enemy Spawn Table",
        "; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), PatrolMinX (w), PatrolMaxX (w), Speed (w)",
        ";------------------------------------------------------------------------------",
        f"{prefix}_EnemyCount:      dc.w    {len(enemies)}",
        f"{prefix}_EnemyList:"
    ])

    if enemies:
        for i, e in enumerate(enemies):
            asm_lines.append(
                f"    dc.w    {e['type']}, {e['col']}, {e['row']}, {e['x']}, {e['y']}, {e['patrol_min']}, {e['patrol_max']}, {e['speed']}   ; Enemy {i + 1}"
            )
    asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Animal Friends Spawn Table",
        "; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), Res1 (w), Res2 (w), Res3 (w)",
        ";   Type: 1=BUNNY, 2=PUPPY, 3=KITTEN, 4=DUCKLING, 5=CHICK",
        ";------------------------------------------------------------------------------",
        f"{prefix}_FriendCount:     dc.w    {len(friends)}",
        f"{prefix}_FriendList:"
    ])

    if friends:
        for i, f in enumerate(friends):
            asm_lines.append(
                f"    dc.w    {f['type']}, {f['col']}, {f['row']}, {f['x']}, {f['y']}, 0, 0, 0   ; Friend {i + 1}: {f['name']}"
            )
    asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Pushable / Movable Blocks Table",
        "; Format: Col (w), Row (w), SpriteIndex (w), Reserved (w)",
        ";------------------------------------------------------------------------------",
        f"{prefix}_BlockCount:      dc.w    {len(pushes)}",
        f"{prefix}_BlockList:",
    ])

    if pushes:
        for i, p in enumerate(pushes):
            asm_lines.append(
                f"    dc.w    {p['col']}, {p['row']}, {p['sprite']}, 0   ; Block {i + 1}: {p['name']}"
            )
    asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Ladder Zones",
        "; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)",
        ";------------------------------------------------------------------------------",
        f"{prefix}_LadderCount:     dc.w    {len(ladders)}",
        f"{prefix}_LadderList:"
    ])

    if ladders:
        for i, l in enumerate(ladders):
            asm_lines.append(
                f"    dc.w    {l['col_start']}, {l['col_end']}, {l['row_start']}, {l['row_end']}   ; Ladder {i + 1} (x={l['x']}, y={l['y']}, w={l['w']}, h={l['h']})"
            )
    asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Solid Platform Zones",
        "; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)",
        ";------------------------------------------------------------------------------",
        f"{prefix}_SolidCount:      dc.w    {len(solids)}",
        f"{prefix}_SolidList:"
    ])

    if solids:
        for i, s in enumerate(solids):
            asm_lines.append(
                f"    dc.w    {s['col_start']}, {s['col_end']}, {s['row_start']}, {s['row_end']}   ; Solid {i + 1} (x={s['x']}, y={s['y']}, w={s['w']}, h={s['h']})"
            )
    asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Triggers & Level Event Zones",
        "; Format: TriggerID (w), Left (w), Top (w), Right (w), Bottom (w)",
        ";------------------------------------------------------------------------------",
        f"{prefix}_TriggerCount:    dc.w    {len(triggers)}",
        f"{prefix}_TriggerList:"
    ])

    if triggers:
        for t in triggers:
            comment = f" ; target={t['target']}" if t['target'] else ""
            asm_lines.append(
                f"    dc.w    {t['id']}, {t['left']}, {t['top']}, {t['right']}, {t['bottom']}{comment}"
            )
    asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Hazard Zones",
        "; Format: Damage (w), Left (w), Top (w), Right (w), Bottom (w)",
        ";------------------------------------------------------------------------------",
        f"{prefix}_HazardCount:     dc.w    {len(hazards)}",
        f"{prefix}_HazardList:"
    ])

    if hazards:
        for h in hazards:
            asm_lines.append(
                f"    dc.w    {h['damage']}, {h['left']}, {h['top']}, {h['right']}, {h['bottom']}"
            )
    asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Bridge Zones",
        "; Format: LeftX (w), RightX (w), PlatformRow (w), Reserved (w)",
        ";------------------------------------------------------------------------------",
        f"{prefix}_BridgeCount:     dc.w    {len(bridges)}",
        f"{prefix}_BridgeList:"
    ])

    if bridges:
        for b in bridges:
            asm_lines.append(
                f"    dc.w    {b['x']}, {b['x'] + b['w']}, {b['row_start']}, 0   ; Bridge (x={b['x']}, y={b['y']}, w={b['w']}, h={b['h']})"
            )
    asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Oxygen Refills Table",
        "; Format: Col (w), Row (w), PixelX (w), PixelY (w), TileId (w), Reserved (3 words)",
        ";------------------------------------------------------------------------------",
        f"{prefix}_OxygenCount:     dc.w    {len(oxygen_refills)}",
        f"{prefix}_OxygenList:"
    ])

    if oxygen_refills:
        for i, ox in enumerate(oxygen_refills):
            asm_lines.append(
                f"    dc.w    {ox['col']}, {ox['row']}, {ox['x']}, {ox['y']}, {ox['tile_id']}, 0, 0, 0   ; Oxygen Refill {i + 1}"
            )
    asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        ""
    ])

    # Tile Physical Attributes Table (256 bytes)
    asm_lines.extend([
        ";------------------------------------------------------------------------------",
        "; Tile Physical Attributes Table (256 bytes)",
        "; Maps tile indices to collision flags: 0=Empty, 1=Solid, 2=Ladder, 3=Hazard, 4=Passthrough",
        ";------------------------------------------------------------------------------",
        f"{prefix}_TileAttributesTable:",
        "    ; Index 00: Empty space",
        "    dc.b    ATTR_EMPTY"
    ])

    # Build 255 remaining entries
    for row in range(1, 256, 16):
        row_entries = []
        for tid in range(row, min(row + 16, 256)):
            # Lookup attribute from tileset or default
            attr = tileset_attrs.get(tid, ATTR_SOLID if (1 <= tid <= 32) else ATTR_EMPTY)
            attr_name = ["ATTR_EMPTY", "ATTR_SOLID", "ATTR_LADDER", "ATTR_HAZARD", "ATTR_PASSTHROUGH"][attr]
            row_entries.append(attr_name)
        asm_lines.append("    dc.b    " + ", ".join(row_entries))

    # Identify background, platform, ladder, foreground, and water layer labels
    bg_map_label = f"{prefix}_BackgroundMap" if any(s == "background" for s, _, _ in exported_map_files) else "0"
    plat_map_label = f"{prefix}_PlatformMap" if any(s == "platform" for s, _, _ in exported_map_files) else "0"
    ladder_map_label = f"{prefix}_LadderMap" if any(s == "ladder" for s, _, _ in exported_map_files) else "0"
    fg_map_label = f"{prefix}_ForegroundMap" if any(s == "foreground" for s, _, _ in exported_map_files) else "0"
    water_map_label = f"{prefix}_WaterMap" if any(s == "water" for s, _, _ in exported_map_files) else "0"

    # Palette words (16 words formatted as $0RGB)
    pal = tileset_info["palette"] if (tileset_info and "palette" in tileset_info) else DEFAULT_PALETTE_OCS
    pal_words = [f"${(r << 8) | (g << 4) | b:04x}" for r, g, b in pal]
    pal_row1 = ", ".join(pal_words[:8])
    pal_row2 = ", ".join(pal_words[8:])

    # Escape strings if needed
    safe_title = level_title.replace('"', "'")
    safe_sub_title = level_sub_title.replace('"', "'")

    asm_lines.extend([
        "    even",
        "",
        ";------------------------------------------------------------------------------",
        "; 16-Color OCS Level Palette",
        "; Format: 16 words (RGB444: 0x0RGB)",
        ";------------------------------------------------------------------------------",
        f"{prefix}_Palette:",
        f"    dc.w    {pal_row1}",
        f"    dc.w    {pal_row2}",
        "    even",
        "",
        ";------------------------------------------------------------------------------",
        "; Level Text Strings",
        ";------------------------------------------------------------------------------",
        f"{prefix}_TitleStr:",
        f'    dc.b    "{safe_title}",0',
        "    even",
        "",
        f"{prefix}_SubTitleStr:",
        f'    dc.b    "{safe_sub_title}",0',
        "    even",
        f"{prefix}_HintStr = {prefix}_SubTitleStr",
        "",
        ";==============================================================================",
        "; Level Descriptor Definition",
        "; Conforms to LevelDef record structure in include/resources/struct.asm",
        ";==============================================================================",
        f"{prefix}_Def:",
        "    ; --- Visuals & Audio ---",
        asm_line("dc.l", tileset_raw, "Tileset graphics pointer"),
        asm_line("dc.l", tileset_msk, "Tileset mask pointer"),
        asm_line("dc.l", palette_name, "Palette pointer (16 RGB words)"),
        asm_line("dc.l", music_name, "BGM ProTracker MOD pointer"),
        "",
        "    ; --- Geometry & Binary Maps ---",
        asm_line("dc.w", f"{width}, {height}", "Map width, height in tiles"),
        asm_line("dc.l", bg_map_label, "Background layer binary pointer (0 if none)"),
        asm_line("dc.l", plat_map_label, "Platform layer binary pointer (0 if none)"),
        asm_line("dc.l", ladder_map_label, "Ladder layer binary pointer (0 if none)"),
        asm_line("dc.l", fg_map_label, "Foreground layer binary pointer (0 if none)"),
        asm_line("dc.l", water_map_label, "Water layer binary pointer (0 if none)"),
        asm_line("dc.w", f"{layer_count}, 0", "Number of ordered tile layers, reserved"),
        asm_line("dc.l", f"{prefix}_LayerList", "Ordered layer list pointer (TMX order)"),
        asm_line("dc.l", f"{prefix}_GameMap", "1D collision GameMap binary pointer"),
        "",
        "    ; --- Camera Bounds & Margins ---",
        asm_line("dc.w", f"{min_cam_y}, {max_cam_y}", "MinCameraY, MaxCameraY"),
        asm_line("dc.w", str(init_cam_y), "InitialCameraY"),
        asm_line("dc.w", f"{cam_margin_top}, {cam_margin_bottom}", "CamMarginTop, CamMarginBottom"),
        "",
        "    ; --- Player Starts ---",
        asm_line("dc.w", f"{player_start['col']}, {player_start['row']}, {player_start['dir']}", "Player 1: Col, Row, Facing (+1=Right, -1=Left)"),
        asm_line("dc.w", f"{player2_start['col']}, {player2_start['row']}, {player2_start['dir']}", "Player 2: Col, Row, Facing (0=None/Solo)"),
        "",
        "    ; --- Entity & Object Lists ---",
        asm_line("dc.l", f"{prefix}_EnemyList", "Enemy spawn table"),
        asm_line("dc.l", f"{prefix}_FriendList", "Animal friends spawn table"),
        asm_line("dc.l", f"{prefix}_BlockList", "Pushable blocks table"),
        asm_line("dc.l", f"{prefix}_LadderList", "Ladder zones table"),
        asm_line("dc.l", f"{prefix}_SolidList", "Solid platform zones table"),
        asm_line("dc.l", f"{prefix}_TriggerList", "Triggers / switches table"),
        asm_line("dc.l", f"{prefix}_HazardList", "Hazard zones table"),
        asm_line("dc.l", f"{prefix}_BridgeList", "Bridge zones table"),
        asm_line("dc.l", f"{prefix}_OxygenList", "Oxygen refills table"),
        "",
        "    ; --- Banner Text & Access Code ---",
        asm_line("dc.l", f"{prefix}_TitleStr", "Null-terminated title string"),
        asm_line("dc.l", f"{prefix}_SubTitleStr", "Null-terminated subtitle string"),
        asm_line("dc.b", f'"{access_code}",0,0', "6-char access password + padding"),
        "    even",
        ""
    ])

    with open(asm_path, "w", encoding="utf-8") as f_asm:
        f_asm.write("\n".join(asm_lines) + "\n")

    print(f"[*] Done! Level {prefix} successfully exported.")


def main():
    parser = argparse.ArgumentParser(description="Export Tiled TMX map to Amiga binary and assembly format")
    parser.add_argument("tmx", nargs="?", default="assets/Levels/Level_01.tmx", help="Path to Tiled .tmx file")
    parser.add_argument("--out-dir", "-o", default=None, help="Directory for binary .map output files")
    parser.add_argument("--asm-out", "-a", default=None, help="Path for assembly .asm metadata file")
    parser.add_argument("--prefix", "-p", default=None, help="Prefix for labels and filenames")

    args = parser.parse_args()
    export_tmx(args.tmx, args.out_dir, args.asm_out, args.prefix)


if __name__ == "__main__":
    main()
