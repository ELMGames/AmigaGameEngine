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


def parse_tile_layer(layer_elem, width: int, height: int, tilesets: list = None, firstgid: int = 1) -> list:
    """Decode tile layer data across CSV, base64, zlib, gzip, or XML."""
    data_elem = layer_elem.find("data")
    if data_elem is None:
        return [0] * (width * height)

    encoding = data_elem.attrib.get("encoding", "").lower()
    compression = data_elem.attrib.get("compression", "").lower()

    def map_gid(g: int) -> int:
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

    # Parse tileset collision attributes and convert tileset image
    tileset_attrs = {}
    tileset_info = None
    project_root = Path(__file__).resolve().parent.parent
    tilesets = []
    for ts_elem in root.findall("tileset"):
        fg = int(ts_elem.attrib.get("firstgid", 1))
        tilesets.append({
            "firstgid": fg,
            "element": ts_elem
        })
        attrs = parse_tileset_attributes(tmx_dir, ts_elem)
        for local_id, attr_val in attrs.items():
            tileset_attrs[local_id] = attr_val
        if not tileset_info:
            ts_info = convert_tileset_image(tmx_dir, ts_elem, project_root)
            if ts_info:
                tileset_info = ts_info

    tilesets.sort(key=lambda t: t["firstgid"], reverse=True)

    # Parse tile layers
    tile_layers = []
    composite_grid = [0] * (width * height)

    for layer in root.findall("layer"):
        layer_name = layer.attrib.get("name", "layer").strip()
        layer_slug = sanitize_label(layer_name)
        tiles = parse_tile_layer(layer, width, height, tilesets=tilesets)
        non_zero = sum(1 for t in tiles if t != 0)
        
        tile_layers.append({
            "name": layer_name,
            "slug": layer_slug,
            "tiles": tiles,
            "non_zero": non_zero
        })
        print(f"    Found Tile Layer: '{layer_name}' (Non-zero tiles: {non_zero}/{len(tiles)})")

        # Merge non-empty tiles into composite grid
        for i, t in enumerate(tiles):
            if t != 0:
                composite_grid[i] = t

    # Parse object layers (metadata, spawns, triggers)
    player_start = {"x": 24, "y": 512, "col": 1, "row": 31, "xdec": 8, "dir": 1}
    player2_start = {"x": 0, "y": 0, "col": 0, "row": 0, "xdec": 0, "dir": 0}
    player2_found = False
    enemies = []
    solids = []
    ladders = []
    pushes = []
    dirts = []
    cocoons = []
    acids = []
    triggers = []
    hazards = []
    bridges = []
    generic_objects = []

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
                print(f"      -> Player Spawn: ({x}, {y}) -> Col={player_start['col']}, Row={player_start['row']}, XDec={p1_xdec}, dir={p1_dir}")

            # Identify Enemies
            elif "enemy" in tag or "patrol" in tag or "flyer" in tag or "crawler" in tag or "enemy" in name_lower:
                enemy_type = int(props.get("type", 1))
                patrol_min = int(props.get("patrol_min_x", int(round(x)) - 64))
                patrol_max = int(props.get("patrol_max_x", int(round(x)) + 64))
                speed = int(props.get("speed", 1))
                # Clamp patrol bounds to visible screen width range [0 .. 288]
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
                print(f"      -> Enemy: type={enemy_type} at ({x}, {y}) -> Col={e_col}, Row={e_row}, patrol=[{patrol_min}..{patrol_max}]")

            # Identify Bridges (explicit name or type)
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
                print(f"      -> Bridge: ({x},{y},{w},{h}) -> Cols [{col_start}..{col_end}], Rows [{row_start}..{row_end}]")
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

            # Identify Ladders
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
                print(f"      -> Ladder: ({x},{y},{w},{h}) -> Cols [{col_start}..{col_end}], Rows [{row_start}..{row_end}]")

            # Identify Solid Platforms (explicit name/type, or untyped bounding box in elements layer)
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
                print(f"      -> Solid Platform: ({x},{y},{w},{h}) -> Cols [{col_start}..{col_end}], Rows [{row_start}..{row_end}]")

            # Identify Push Blocks
            elif "push" in tag or "push" in name_lower or "crate" in tag:
                pushes.append({
                    "col_start": col_start,
                    "col_end": col_end,
                    "row_start": row_start,
                    "row_end": row_end,
                })
                print(f"      -> Push Block: Cols [{col_start}..{col_end}], Rows [{row_start}..{row_end}]")

            # Identify Dirt Blocks
            elif "dirt" in tag or "dirt" in name_lower or "breakable" in tag:
                dirts.append({
                    "col_start": col_start,
                    "col_end": col_end,
                    "row_start": row_start,
                    "row_end": row_end,
                })
                print(f"      -> Dirt Block: Cols [{col_start}..{col_end}], Rows [{row_start}..{row_end}]")

            # Identify Cocoons
            elif "cocoon" in tag or "cocoon" in name_lower:
                cocoons.append({
                    "col_start": col_start,
                    "col_end": col_end,
                    "row_start": row_start,
                    "row_end": row_end,
                })
                print(f"      -> Cocoon: Cols [{col_start}..{col_end}], Rows [{row_start}..{row_end}]")

            # Identify Hazards / Acid
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
                print(f"      -> Hazard: dmg={damage} bounds=({x},{y})-({x+w},{y+h})")

            # Identify Triggers
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
                print(f"      -> Trigger: id={trig_id} bounds=({x},{y})-({x+w},{y+h}) target='{target}'")

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
    # Construct 1D GameMap Array (width * height bytes)
    # =========================================================================
    print(f"[*] Constructing 1D GameMap ({width} cols x {height} rows = {width * height} bytes)...")
    gamemap = [BLOCK_EMPTY] * (width * height)

    # 1. Bottom boundary solid floor (prevent falling off the bottom of the map)
    for c in range(width):
        gamemap[(height - 1) * width + c] = BLOCK_SOLID

    # 2. Solid platforms from elements
    for s in solids:
        for r in range(s["row_start"], s["row_end"] + 1):
            for c in range(s["col_start"], s["col_end"] + 1):
                gamemap[r * width + c] = BLOCK_SOLID

    # 3. Ladders (stamped after solids so ladder openings cut through platforms)
    for l in ladders:
        for r in range(l["row_start"], l["row_end"] + 1):
            for c in range(l["col_start"], l["col_end"] + 1):
                gamemap[r * width + c] = BLOCK_LADDER

    # 4. Push, Dirt, Cocoon, Acid
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

    # 5. Enemies (if spawn tile is solid, stand on the row directly above)
    for e in enemies:
        if gamemap[e["row"] * width + e["col"]] == BLOCK_SOLID and e["row"] > 0:
            e["row"] -= 1
            e["y"] = e["row"] * 16

    # 6. Player spawn (if spawn tile is solid, stand on the row directly above)
    if gamemap[player_start["row"] * width + player_start["col"]] == BLOCK_SOLID and player_start["row"] > 0:
        player_start["row"] -= 1
    gamemap[player_start["row"] * width + player_start["col"]] = BLOCK_PLAYERSTART


    # =========================================================================
    # Write Binary Tilemap & GameMap Files
    # =========================================================================
    print("[*] Generating Binary .map and -gamemap.bin files...")
    exported_map_files = []

    # 1. Individual layer maps
    for layer in tile_layers:
        out_map_name = f"{prefix}-{layer['slug']}.map"
        out_map_path = out_dir / out_map_name
        write_binary_map(out_map_path, width, height, layer["tiles"])
        exported_map_files.append((layer["slug"], out_map_name, out_map_path))
        print(f"    Exported layer '{layer['name']}': {out_map_path} ({out_map_path.stat().st_size} bytes)")

    # 2. Composite / Merged map (platforms on top of background)
    composite_name = f"{prefix}.map"
    composite_path = out_dir / composite_name
    write_binary_map(composite_path, width, height, composite_grid)
    print(f"    Exported composite map: {composite_path} ({composite_path.stat().st_size} bytes)")

    # 3. 1D GameMap Binary
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
        f"{prefix}_LayerCount:      dc.w    {len(tile_layers)}",
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

    has_bg = any("bg" in slug.lower() or "background" in slug.lower() for slug, _, _ in exported_map_files)
    has_plat = any("plat" in slug.lower() or "platform" in slug.lower() for slug, _, _ in exported_map_files)
    has_fg = any("fg" in slug.lower() or "foreground" in slug.lower() for slug, _, _ in exported_map_files)
    has_water = any("water" in slug.lower() for slug, _, _ in exported_map_files)
    if not has_bg:
        asm_lines.extend([
            f"{prefix}_BackgroundMap = 0",
            ""
        ])
    if not has_plat:
        asm_lines.extend([
            f"{prefix}_PlatformMap = 0",
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

    # Ordered Layer Table (in TMX document order)
    asm_lines.extend([
        ";------------------------------------------------------------------------------",
        "; Ordered Tilemap Layer Table (in TMX document order)",
        "; Format: Pointers to each layer's binary map, terminated by 0",
        ";------------------------------------------------------------------------------",
        f"{prefix}_LayerList:"
    ])
    for slug, _, _ in exported_map_files:
        label = f"{prefix}_{slug.capitalize()}Map"
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
            attr = tileset_attrs.get(tid, ATTR_SOLID if tid <= 32 else ATTR_EMPTY)
            attr_name = ["ATTR_EMPTY", "ATTR_SOLID", "ATTR_LADDER", "ATTR_HAZARD", "ATTR_PASSTHROUGH"][attr]
            row_entries.append(attr_name)
        asm_lines.append("    dc.b    " + ", ".join(row_entries))

    # Identify background, platform, foreground, and water layer labels
    bg_map_label = "0"
    plat_map_label = "0"
    fg_map_label = "0"
    water_map_label = "0"
    for slug, _, _ in exported_map_files:
        if "bg" in slug.lower() or "background" in slug.lower():
            bg_map_label = f"{prefix}_{slug.capitalize()}Map"
        elif "plat" in slug.lower() or "platform" in slug.lower():
            plat_map_label = f"{prefix}_{slug.capitalize()}Map"
        elif "fg" in slug.lower() or "foreground" in slug.lower():
            fg_map_label = f"{prefix}_{slug.capitalize()}Map"
        elif "water" in slug.lower():
            water_map_label = f"{prefix}_{slug.capitalize()}Map"

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
        asm_line("dc.l", fg_map_label, "Foreground layer binary pointer (0 if none)"),
        asm_line("dc.l", water_map_label, "Water layer binary pointer (0 if none)"),
        asm_line("dc.w", f"{len(tile_layers)}, 0", "Number of ordered tile layers, reserved"),
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
        asm_line("dc.l", f"{prefix}_LadderList", "Ladder zones table"),
        asm_line("dc.l", f"{prefix}_SolidList", "Solid platform zones table"),
        asm_line("dc.l", f"{prefix}_TriggerList", "Triggers / switches table"),
        asm_line("dc.l", f"{prefix}_HazardList", "Hazard zones table"),
        asm_line("dc.l", f"{prefix}_BridgeList", "Bridge zones table"),
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
