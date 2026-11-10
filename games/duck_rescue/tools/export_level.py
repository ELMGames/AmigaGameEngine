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

Binary .map format (8-byte BE header + 16-bit BE words):
  Offset 0..3: uint32 Width in tiles (Big-Endian)
  Offset 4..7: uint32 Height in tiles (Big-Endian)
  Offset 8+:   uint16 Tile indices row-by-row (Big-Endian, 0=Empty)
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
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
from amiga_planar import load_palette_ocs

GAME_ROOT = Path(__file__).resolve().parent.parent

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
BLOCK_SOLID       = 5
BLOCK_ENEMYFLOAT  = 6
BLOCK_PLAYERSTART = 7

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
    "lava": ATTR_HAZARD,
    "3": ATTR_HAZARD,
    "passthrough": ATTR_PASSTHROUGH,
    "oneway": ATTR_PASSTHROUGH,
    "one-way": ATTR_PASSTHROUGH,
    "platform": ATTR_PASSTHROUGH,
    "4": ATTR_PASSTHROUGH,
}

# Shared 16-color OCS playfield palette (games/duck_rescue/game_palette.json),
# also used by convert_player_bob.py, convert_enemies.py, and convert_animals.py.
DEFAULT_PALETTE_OCS = load_palette_ocs(GAME_ROOT / "game_palette.json")

# Mapping from (tileset_name, local_id) -> Amiga GameTilesRaw compact index
TILESET_TO_COMPACT = {
    # tileset-platforms (firstgid=1)
    ("tileset-platforms", 0): 1,   # Grass Left (src 1)
    ("tileset-platforms", 1): 2,   # Grass Mid (src 2)
    ("tileset-platforms", 2): 3,   # Grass Right (src 3)
    ("tileset-platforms", 3): 4,   # Grass Corner (src 4)
    ("tileset-platforms", 4): 11,  # Stone Left (src 18)
    ("tileset-platforms", 5): 12,  # Stone Mid (src 19)
    ("tileset-platforms", 6): 13,  # Stone Right (src 20)
    ("tileset-platforms", 7): 15,  # Platform Ledge (src 29)
    ("tileset-platforms", 8): 8,   # Soil Mid / Bedrock (src 14)
    ("tileset-platforms", 9): 7,   # Soil Corner (src 12)
    ("tileset-platforms", 10): 9,  # Soil Variant (src 15)
    ("tileset-platforms", 11): 10, # Earth Variant (src 17)
    ("tileset-platforms", 12): 5,  # Grass Variant 1 (src 7)
    ("tileset-platforms", 13): 6,  # Grass Variant 2 (src 9)

    # tileset-plants (firstgid=17)
    ("tileset-plants", 0): 20,     # Yellow Tree Top (src 39)
    ("tileset-plants", 1): 16,     # Green Tree Top (src 34)
    ("tileset-plants", 2): 23,     # Branch 1 (src 44)
    ("tileset-plants", 3): 17,     # Tree Foliage Canopy (src 35)
    ("tileset-plants", 4): 29,     # Yellow Tree Mid (src 50)
    ("tileset-plants", 5): 24,     # Green Tree Mid (src 45, moved from tile 6)
    ("tileset-plants", 6): 25,     # Branch 2 (src 46)
    ("tileset-plants", 7): 14,     # Tree Canopy Edge (src 21)
    ("tileset-plants", 8): 34,     # Yellow Tree Base (src 61)
    ("tileset-plants", 9): 30,     # Green Tree Base (src 56, moved from tile 17)
    ("tileset-plants", 10): 40,    # Tree Trunk Root (src 72)
    ("tileset-plants", 11): 22,    # Foliage Accent (src 43)
    ("tileset-plants", 12): 31,    # Palm Top-L (src 58)
    ("tileset-plants", 13): 32,    # Palm Top-M (src 59)
    ("tileset-plants", 14): 33,    # Palm Top-R (src 60)
    ("tileset-plants", 15): 45,    # Rock Accent / Plant on Rock (src 92)
    ("tileset-plants", 16): 37,    # Palm Mid-L (src 69)
    ("tileset-plants", 17): 38,    # Palm Mid-Trunk (src 70)
    ("tileset-plants", 18): 39,    # Palm Mid-R (src 71)
    ("tileset-plants", 21): 41,    # Palm Trunk Base / Roots (src 81)

    # tileset-water (firstgid=45)
    ("tileset-water", 0): 47,      # Water Surface (src 104)
    ("tileset-water", 1): 48,      # Water Deep (src 115)

    # tileset-ladders (firstgid=47)
    ("tileset-ladders", 0): 35,    # Ladder Top (src 66)
    ("tileset-ladders", 1): 36,    # Ladder Mid (src 67)

    # tileset-entities (firstgid=49)
    ("tileset-entities", 0): 18,   # Pushable Crate (src 37)
    ("tileset-entities", 1): 46,   # Oxygen Tank (src 95)
}


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
    elif "player" in ident:
        category = "player"
    elif "platform" in ident:
        category = "platforms"
    elif "plant" in ident:
        category = "plants"
    elif "ladder" in ident:
        category = "ladders"
    elif "entit" in ident:
        category = "entities"
    elif "water" in ident:
        category = "water"
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
    compact_png = project_root / "assets" / "graphics" / "tiles" / "tileset-compact.png"
    if compact_png.exists():
        img_path = compact_png
    elif not img_path.exists():
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

    semi_transparent_tiles = {47, 48, 104, 115}
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
    raw_path = tiles_dir / f"{img_path.stem}_{w}x{h}.raw"
    msk_path = tiles_dir / f"{img_path.stem}_{w}x{h}.msk"

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
      Offset 0..3: uint32 Width (Big-Endian)
      Offset 4..7: uint32 Height (Big-Endian)
      Offset 8+:   uint16 Tile Index words (Big-Endian)
    """
    file_path.parent.mkdir(parents=True, exist_ok=True)
    with open(file_path, "wb") as f:
        # 8-byte header
        f.write(struct.pack(">II", width, height))
        # Tile index grid
        for tile in tile_indices:
            f.write(struct.pack(">H", tile & 0xFFFF))


def align4(b: bytearray):
    """Align bytearray to 4-byte boundary."""
    while len(b) % 4 != 0:
        b.append(0)



def _append_cstring(buf: bytearray, text: str) -> int:
    """Append a null-terminated ASCII string, pad to 4 bytes; return its start offset."""
    offset = len(buf)
    buf.extend(text.encode("ascii", "replace") + b"\0")
    align4(buf)
    return offset


def _append_records(buf: bytearray, items, fmt: str, fields) -> int:
    """Append struct-packed records, a -1 terminator word, pad to 4 bytes; return the start offset."""
    offset = len(buf)
    for item in items:
        buf.extend(struct.pack(fmt, *fields(item)))
    buf.extend(struct.pack(">h", -1))
    align4(buf)
    return offset


def _append_layer_maps(buf: bytearray, width: int, height: int, layer_grids):
    """Append each present layer as (width, height, tiles...); return ({slug: offset}, [offsets in order])."""
    offsets = {slug: 0 for slug in ("background", "platform", "ladder", "foreground", "water")}
    ordered = []
    for slug, grid in layer_grids:
        if grid is None:
            continue
        off = len(buf)
        buf.extend(struct.pack(">II", width, height))
        for tile in grid:
            buf.extend(struct.pack(">H", tile & 0xFFFF))
        align4(buf)
        if slug in offsets:
            offsets[slug] = off
        ordered.append(off)
    return offsets, ordered


def package_level_binary(
    package_path: Path,
    width: int,
    height: int,
    min_cam_y: int,
    max_cam_y: int,
    init_cam_y: int,
    cam_margin_top: int,
    cam_margin_bottom: int,
    player_start: dict,
    player2_start: dict,
    enemies: list,
    friends: list,
    pushes: list,
    ladders: list,
    solids: list,
    triggers: list,
    hazards: list,
    bridges: list,
    oxygen_refills: list,
    pal: list,
    level_title: str,
    level_sub_title: str,
    gamemap: list,
    layer_grids: list
):
    """
    Package level into standalone .lvl binary file ('ALVL').
    Layout:
      0..7:    Header (ALVL magic, version 1, flags 0)
      8..125:  LevelDef struct (118 bytes)
      126..127: Alignment padding (2 bytes)
      128+:    Data sections (palette, text, entities, gamemap, layers, layer list)
    """

    package_path = Path(package_path).resolve()
    package_path.parent.mkdir(parents=True, exist_ok=True)

    buf = bytearray(128)
    # Header: magic 'ALVL', version 1, flags 0; the LevelDef record follows at offset 8
    struct.pack_into(">4sHH", buf, 0, b"ALVL", 1, 0)

    offset_palette = len(buf)
    for r, g, b in pal:
        buf.extend(struct.pack(">H", ((r & 0xF) << 8) | ((g & 0xF) << 4) | (b & 0xF)))
    align4(buf)
    offset_title = _append_cstring(buf, level_title)
    offset_subtitle = _append_cstring(buf, level_sub_title)

    offset_enemies = _append_records(buf, enemies, ">8h", lambda e: (e['type'], e['col'], e['row'], e['x'], e['y'], e['patrol_min'], e['patrol_max'], e['speed']))
    offset_friends = _append_records(buf, friends, ">8h", lambda f: (f['type'], f['col'], f['row'], f['x'], f['y'], 0, 0, 0))
    offset_blocks = _append_records(buf, pushes, ">4h", lambda p: (p['col'], p['row'], p['sprite'], 0))
    offset_ladders = _append_records(buf, ladders, ">4h", lambda l: (l['col_start'], l['col_end'], l['row_start'], l['row_end']))
    offset_solids = _append_records(buf, solids, ">4h", lambda s: (s['col_start'], s['col_end'], s['row_start'], s['row_end']))
    offset_triggers = _append_records(buf, triggers, ">5h", lambda t: (t['id'], t['left'], t['top'], t['right'], t['bottom']))
    offset_hazards = _append_records(buf, hazards, ">5h", lambda h: (h['damage'], h['left'], h['top'], h['right'], h['bottom']))
    offset_bridges = _append_records(buf, bridges, ">4h", lambda b: (b['x'], b['x'] + b['w'], b['row_start'], 0))
    offset_oxygens = _append_records(buf, oxygen_refills, ">8h", lambda ox: (ox['col'], ox['row'], ox['x'], ox['y'], ox['tile_id'], 0, 0, 0))

    offset_gamemap = len(buf)
    buf.extend(bytes(gamemap))
    align4(buf)

    layer_offsets, layer_list = _append_layer_maps(buf, width, height, layer_grids)
    offset_layer_list = len(buf)
    for off in layer_list:
        buf.extend(struct.pack(">I", off))
    buf.extend(struct.pack(">I", 0))
    align4(buf)

    leveldef_bytes = struct.pack(
        ">4I2H5I2H2I5h3h3h9I2I",
        0, 0, offset_palette, 0,
        width, height,
        layer_offsets["background"], layer_offsets["platform"], layer_offsets["ladder"],
        layer_offsets["foreground"], layer_offsets["water"],
        len(layer_list), 0,
        offset_layer_list, offset_gamemap,
        min_cam_y, max_cam_y, init_cam_y,
        cam_margin_top, cam_margin_bottom,
        player_start['col'], player_start['row'], player_start['dir'],
        player2_start['col'], player2_start['row'], player2_start['dir'],
        offset_enemies, offset_friends, offset_blocks,
        offset_ladders, offset_solids, offset_triggers,
        offset_hazards, offset_bridges, offset_oxygens,
        offset_title, offset_subtitle
    )
    buf[8:8 + len(leveldef_bytes)] = leveldef_bytes

    with open(package_path, "wb") as f_pkg:
        f_pkg.write(buf)

    print(f"[*] Packaged standalone level binary: {package_path} ({len(buf)} bytes)")


def _parse_header(lv: SimpleNamespace) -> None:
    """Map size, custom properties, camera bounds, tilesets, empty containers."""
    lv.tmx_path = Path(lv.tmx_file).resolve()
    if not lv.tmx_path.exists():
        print(f"Error: File not found: {lv.tmx_path}", file=sys.stderr)
        sys.exit(1)

    tmx_dir = lv.tmx_path.parent
    if lv.out_dir is None:
        lv.out_dir = tmx_dir
    else:
        lv.out_dir = Path(lv.out_dir).resolve()
    lv.out_dir.mkdir(parents=True, exist_ok=True)

    file_stem = lv.tmx_path.stem
    if lv.prefix is None:
        lv.prefix = sanitize_label(file_stem)

    print(f"[*] Processing Tiled TMX: {lv.tmx_path}")
    tree = ET.parse(lv.tmx_path)
    lv.root = tree.getroot()

    lv.width = int(lv.root.attrib.get("width", 20))
    lv.height = int(lv.root.attrib.get("height", 42))
    lv.tile_w = int(lv.root.attrib.get("tilewidth", 16))
    lv.tile_h = int(lv.root.attrib.get("tileheight", 16))

    print(f"    Map dimensions: {lv.width}x{lv.height} tiles ({lv.width * lv.tile_w}x{lv.height * lv.tile_h} px), tile size: {lv.tile_w}x{lv.tile_h}")

    MIN_MAP_ROWS = 13  # Minimum 13 rows (208 px) to cover the 200/216 px display window
    MAX_MAP_ROWS = 50  # Must match MAX_SCREEN_ROWS in engine/include/engine_const.i

    if lv.height < MIN_MAP_ROWS:
        raise ValueError(
            f"Level map '{lv.tmx_path}' height ({lv.height} rows) is below minimum of {MIN_MAP_ROWS} rows (208 px) required to fill the display window!"
        )
    if lv.height > MAX_MAP_ROWS:
        raise ValueError(
            f"Level map '{lv.tmx_path}' height ({lv.height} rows) exceeds maximum of {MAX_MAP_ROWS} rows budgeted in Chip RAM!"
        )

    # Parse map-level custom properties with sensible defaults
    map_props = parse_properties(lv.root)

    lv.music_name = map_props.get("music", map_props.get("bgm", map_props.get("mod", "LevelMod"))).strip()
    lv.tileset_raw = map_props.get("tileset_raw", map_props.get("tileset", "GameTilesRaw")).strip()
    lv.tileset_msk = map_props.get("tileset_msk", "GameTilesMsk").strip()
    lv.palette_name = map_props.get("palette", f"{lv.prefix}_Palette").strip()

    # Camera scroll bounds: map height minus visible viewport (216px display window)
    max_cam_y_default = max(0, lv.height * 16 - 216)
    lv.min_cam_y = int(map_props.get("min_camera_y", map_props.get("mincameray", 0)))
    raw_max_cam = map_props.get("max_camera_y", map_props.get("maxcameray"))
    if raw_max_cam is not None:
        # Enforce that max_cam_y is at least max_cam_y_default so camera can always reach bottom row
        lv.max_cam_y = max(max_cam_y_default, int(raw_max_cam))
    else:
        lv.max_cam_y = max_cam_y_default

    lv.has_explicit_init_cam = (
        "initial_camera_y" in map_props
        or "initial_row" in map_props
        or "initial_tile_row" in map_props
        or "initialcameray" in map_props
        or "cameray" in map_props
    )
    if "initial_camera_y" in map_props:
        lv.init_cam_y = int(map_props["initial_camera_y"])
    elif "initial_row" in map_props:
        lv.init_cam_y = int(map_props["initial_row"]) * 16
    elif "initial_tile_row" in map_props:
        lv.init_cam_y = int(map_props["initial_tile_row"]) * 16
    else:
        lv.init_cam_y = int(map_props.get("initialcameray", map_props.get("cameray", max_cam_y_default)))

    # Camera deadzone margins:
    # cam_margin_top = 16 (1 row below top)
    # cam_margin_bottom = (No_of_visible_rows - 1) * 16 = (12 - 1) * 16 = 176 (1 row above bottom of visible screen)
    VISIBLE_SCREEN_ROWS = 12
    lv.cam_margin_top = int(map_props.get("cam_margin_top", 16))
    lv.cam_margin_bottom = int(map_props.get("cam_margin_bottom", (VISIBLE_SCREEN_ROWS - 1) * 16))

    # Banner title & sub_title (hint alias maintained for compatibility)
    lv.level_title = map_props.get("title", map_props.get("level_title", map_props.get("name", lv.prefix.replace("_", " ").upper()))).strip()
    lv.level_sub_title = map_props.get("sub_title", map_props.get("subtitle", map_props.get("hint", map_props.get("level_hint", "")))).strip()

    # Parse tilesets with full categorization and properties
    lv.tileset_attrs = {}
    lv.tileset_info = None
    project_root = Path(__file__).resolve().parent.parent
    tilesets = []
    for ts_elem in lv.root.findall("tileset"):
        ts_data = parse_tileset_full(tmx_dir, ts_elem)
        tilesets.append(ts_data)
        for local_id, attr_val in ts_data["attr_table"].items():
            lv.tileset_attrs[local_id] = attr_val
        # Only convert graphics for the world tileset (AmigaGameEngine)
        if ts_data["category"] == "world" and not lv.tileset_info:
            ts_info = convert_tileset_image(tmx_dir, ts_elem, project_root)
            if ts_info:
                lv.tileset_info = ts_info

    tilesets.sort(key=lambda t: t["firstgid"], reverse=True)

    def lookup_tile(g: int):
        if g <= 0:
            return None
        for ts in tilesets:
            if g >= ts["firstgid"]:
                local_id = g - ts["firstgid"]
                ts_name = ts["name"]
                # In legacy tileset-compact or AmigaGameEngine, tile 0 is the 100% transparent dummy tile.
                if ts_name in ("tileset-compact", "AmigaGameEngine") and local_id == 0:
                    return None
                comp_id = TILESET_TO_COMPACT.get((ts_name, local_id), local_id)
                return {
                    "tileset": ts,
                    "local_id": local_id,
                    "compact_id": comp_id,
                    "category": ts["category"],
                    "type": ts["tile_types"].get(local_id, ""),
                    "props": ts["tile_props"].get(local_id, {}),
                    "attr": ts["attr_table"].get(local_id, ATTR_EMPTY)
                }
        return None

    # Grids & object containers
    lv.scenery_grid = [0] * (lv.width * lv.height)
    lv.platform_grid = [0] * (lv.width * lv.height)
    lv.ladder_grid = [0] * (lv.width * lv.height)
    lv.foreground_grid = [0] * (lv.width * lv.height)
    lv.water_grid = [0] * (lv.width * lv.height)
    lv.gamemap = [BLOCK_EMPTY] * (lv.width * lv.height)
    lv.platform_cells = set()    # cells painted on the platforms layer (for the layout lint)
    lv.ladder_cells = set()      # cells painted on the ladders layer
    tile_layers = []

    lv.player_start = {"x": 24, "y": 512, "col": 1, "row": 31, "xdec": 8, "dir": 1}
    lv.player2_start = {"x": 0, "y": 0, "col": 0, "row": 0, "xdec": 0, "dir": 0}
    player2_found = False
    lv.enemies = []
    lv.enemies_pending = []
    lv.friends = []
    lv.solids = []
    lv.ladders = []
    lv.pushes = []
    lv.triggers = []
    lv.hazards = []
    lv.bridges = []
    lv.oxygen_refills = []
    lv.generic_objects = []
    lv.lookup_tile = lookup_tile


def _parse_tile_layers(lv: SimpleNamespace) -> None:
    """Tile layers -> scenery/platform/ladder/foreground/water grids + tile-placed entities."""
    # Parse tile layers
    for layer in lv.root.findall("layer"):
        layer_name = layer.attrib.get("name", "layer").strip()
        layer_slug = sanitize_label(layer_name)
        lname = layer_name.lower()
        raw_tiles = parse_tile_layer(layer, lv.width, lv.height, raw=True)
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
            c = idx % lv.width
            r = idx // lv.width
            t_info = lv.lookup_tile(g)
            if not t_info:
                continue

            category = t_info["category"]
            ttype = t_info["type"]
            props = t_info["props"]
            local_id = t_info["local_id"]

            comp_id = t_info["compact_id"]
            is_world_tile = category in ("world", "platforms", "plants", "ladders", "entities", "water")

            # 1. Entity detection (runs on entities layer OR if an entity tileset was used anywhere)
            if is_entities_layer or category in ("enemies", "friends", "player") or ttype in ("player", "crate", "oxygen", "oxygen_refill", "air") or ttype.startswith("enemy") or ttype.startswith("friend") or comp_id in (18, 46) or (is_world_tile and local_id == 95):
                # Player
                if category == "player" or ttype == "player" or "player" in ttype:
                    lv.player_start["col"] = c
                    lv.player_start["row"] = r
                    lv.player_start["x"] = c * 16
                    lv.player_start["y"] = r * 16
                    dir_val = props.get("direction", 1)
                    lv.player_start["dir"] = 1 if str(dir_val).lower() in ("1", "right") else -1
                    print(f"      [Tile] -> Player Spawn: ({c*16}, {r*16}) -> Col={c}, Row={r}, dir={lv.player_start['dir']}")

                # Enemy
                elif category == "enemies" or ttype.startswith("enemy") or "enemy" in ttype:
                    if "type" in props:
                        e_type = int(props["type"])
                    else:
                        e_type = min(8, max(1, (local_id // 4) + 1))
                    e_speed = int(props.get("speed", 2 if e_type in (3, 6) else 1))
                    lv.enemies_pending.append({
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
                    f_name = props.get("name", f"FRIEND_{len(lv.friends)+1}")
                    lv.friends.append({
                        "type": f_type,
                        "name": f_name,
                        "col": c,
                        "row": r,
                        "x": c * 16,
                        "y": r * 16
                    })
                    print(f"      [Tile] -> Friend: '{f_name}' (type={f_type}) at Col={c}, Row={r} ({c*16}, {r*16})")

                # Push Crate (Tile ID 18, GID 19; legacy 37, GID 38)
                elif ttype == "crate" or comp_id == 18 or (is_world_tile and local_id in (18, 37)) or "crate" in ttype or g in (19, 38):
                    sprite_idx = int(props.get("sprite", 18 if comp_id == 18 or local_id == 18 else 37))
                    lv.pushes.append({
                        "col": c,
                        "row": r,
                        "sprite": sprite_idx,
                        "name": f"CRATE_{len(lv.pushes)+1}",
                        "col_start": c,
                        "col_end": c,
                        "row_start": r,
                        "row_end": r
                    })
                    lv.gamemap[idx] = BLOCK_PUSH
                    print(f"      [Tile] -> Push Block: Col={c}, Row={r} (sprite={sprite_idx})")

                # Oxygen Refill Pickup (Tile ID 46, GID 47; legacy 95, GID 96)
                elif comp_id == 46 or local_id in (46, 95) or ttype in ("oxygen", "oxygen_refill", "air") or "oxygen" in ttype or (is_world_tile and local_id in (46, 95)):
                    lv.oxygen_refills.append({
                        "col": c,
                        "row": r,
                        "x": c * 16,
                        "y": r * 16,
                        "tile_id": comp_id
                    })
                    print(f"      [Tile] -> Oxygen Refill: Col={c}, Row={r} ({c*16}, {r*16})")

                # Entities do NOT draw into tilemap
                continue

            # 2. Visual / Collision Layer processing
            if is_foreground_layer:
                if is_world_tile:
                    lv.foreground_grid[idx] = comp_id

            elif is_water_layer:
                if is_world_tile:
                    lv.water_grid[idx] = comp_id

            elif is_platforms_layer:
                if is_world_tile:
                    lv.platform_grid[idx] = comp_id
                lv.gamemap[idx] = BLOCK_SOLID
                lv.platform_cells.add(idx)

            elif is_ladders_layer:
                if is_world_tile:
                    lv.ladder_grid[idx] = comp_id
                lv.gamemap[idx] = BLOCK_LADDER
                lv.ladder_cells.add(idx)

            elif is_background_layer:
                if is_world_tile:
                    lv.scenery_grid[idx] = comp_id
                # Check TSX collision attribute
                attr = t_info["attr"]
                if attr == ATTR_SOLID:
                    lv.gamemap[idx] = BLOCK_SOLID
                elif attr == ATTR_LADDER:
                    lv.gamemap[idx] = BLOCK_LADDER


def _object_context(lv: SimpleNamespace, obj: ET.Element) -> SimpleNamespace:
    """Common fields of one Tiled object: ids, type tags, pixel box and tile box."""
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
    col_start = max(0, min(lv.width - 1, int(round(x / 16.0))))
    col_end = max(0, min(lv.width - 1, int(round((x + max(w, 1.0)) / 16.0)) - 1))
    row_start = max(0, min(lv.height - 1, int(round(y / 16.0))))
    row_end = max(0, min(lv.height - 1, int(round((y + max(h, 1.0)) / 16.0)) - 1))

    # Identify Player Spawn
    is_player = (
        "player" in tag or "player" in name_lower or
        "spawn" in tag or "spawn" in name_lower
    )
    return SimpleNamespace(obj=obj, obj_id=obj_id, name=name, obj_type=obj_type, x=x, y=y, w=w, h=h, props=props, tag=tag, name_lower=name_lower, col_start=col_start, col_end=col_end, row_start=row_start, row_end=row_end, is_player=is_player)


def _object_player(lv: SimpleNamespace, o: SimpleNamespace) -> None:
    """Object layer: player record."""
    p1_col = int(round(o.x)) // 16
    p1_row = int(round(o.y / 16.0))
    p1_xdec = int(round(o.x)) % 16
    p1_dir_raw = o.props.get("direction", o.props.get("dir", o.props.get("facing", 1)))
    p1_dir = -1 if str(p1_dir_raw).lower() in ("left", "-1", "0") else 1
    lv.player_start["x"] = int(round(o.x))
    lv.player_start["y"] = int(round(o.y))
    lv.player_start["col"] = max(0, min(lv.width - 1, p1_col))
    lv.player_start["row"] = max(0, min(lv.height - 1, p1_row))
    lv.player_start["xdec"] = p1_xdec
    lv.player_start["dir"] = p1_dir
    print(f"      -> Player Spawn (Object): ({o.x}, {o.y}) -> Col={lv.player_start['col']}, Row={lv.player_start['row']}, XDec={p1_xdec}, dir={p1_dir}")


def _object_enemy(lv: SimpleNamespace, o: SimpleNamespace) -> None:
    """Object layer: enemy record."""
    enemy_type = int(o.props.get("type", 1))
    patrol_min = int(o.props.get("patrol_min_x", int(round(o.x)) - 64))
    patrol_max = int(o.props.get("patrol_max_x", int(round(o.x)) + 64))
    speed = int(o.props.get("speed", 1))
    max_patrol_x = (lv.width - 2) * 16
    patrol_min = max(0, min(max_patrol_x, patrol_min))
    patrol_max = max(patrol_min + 16, min(max_patrol_x, patrol_max))
    e_col = max(0, min(lv.width - 1, int(round(o.x)) // 16))
    e_row = max(0, min(lv.height - 1, int(round(o.y / 16.0))))
    lv.enemies.append({
        "type": enemy_type,
        "x": int(round(o.x)),
        "y": int(round(o.y)),
        "col": e_col,
        "row": e_row,
        "patrol_min": patrol_min,
        "patrol_max": patrol_max,
        "speed": speed
    })
    print(f"      -> Enemy (Object): type={enemy_type} at ({o.x}, {o.y}) -> Col={e_col}, Row={e_row}, patrol=[{patrol_min}..{patrol_max}]")


def _object_friend(lv: SimpleNamespace, o: SimpleNamespace) -> None:
    """Object layer: friend record."""
    friend_type = 1
    if "dog1" in o.name_lower or "d1" in o.name_lower or "shiba" in o.name_lower or "tan" in o.name_lower:
        friend_type = 1
    elif "dog2" in o.name_lower or "d2" in o.name_lower or "puppy" in o.name_lower or "white" in o.name_lower or "dog" in o.name_lower:
        friend_type = 2
    elif "duck" in o.name_lower:
        friend_type = 3
    elif "bunny" in o.name_lower or "rabbit" in o.name_lower or "lion" in o.name_lower:
        friend_type = 1
    elif "kitten" in o.name_lower or "cat" in o.name_lower:
        friend_type = 2
    elif "chick" in o.name_lower or "bird" in o.name_lower:
        friend_type = 3

    if o.w > 0:
        center_x = o.x + (o.w / 2.0)
    else:
        center_x = o.x
    spawn_x = int(round(center_x)) - 8
    spawn_x = max(0, min((lv.width * 16) - 16, spawn_x))

    if o.h > 0:
        spawn_y = int(round(o.y + o.h)) - 16
    elif int(round(o.y)) % 16 == 0:
        spawn_y = int(round(o.y)) - 16
    else:
        spawn_y = int(round(o.y))
    spawn_y = max(0, min((lv.height * 16) - 16, spawn_y))

    f_col = max(0, min(lv.width - 1, spawn_x // 16))
    f_row = max(0, min(lv.height - 1, spawn_y // 16))

    lv.friends.append({
        "type": friend_type,
        "name": o.name,
        "x": spawn_x,
        "y": spawn_y,
        "col": f_col,
        "row": f_row,
    })
    print(f"      -> Friend (Object): '{o.name}' (type={friend_type}) at ({spawn_x}, {spawn_y}) -> Col={f_col}, Row={f_row}")


def _object_bridge(lv: SimpleNamespace, o: SimpleNamespace) -> None:
    """Object layer: bridge record."""
    lv.bridges.append({
        "col_start": o.col_start,
        "col_end": o.col_end,
        "row_start": o.row_start,
        "row_end": o.row_end,
        "x": int(round(o.x)),
        "y": int(round(o.y)),
        "w": int(round(o.w)),
        "h": int(round(o.h))
    })
    lv.solids.append({
        "col_start": o.col_start,
        "col_end": o.col_end,
        "row_start": o.row_start,
        "row_end": o.row_end,
        "x": int(round(o.x)),
        "y": int(round(o.y)),
        "w": int(round(o.w)),
        "h": int(round(o.h))
    })


def _object_ladder(lv: SimpleNamespace, o: SimpleNamespace) -> None:
    """Object layer: ladder record."""
    lv.ladders.append({
        "col_start": o.col_start,
        "col_end": o.col_end,
        "row_start": o.row_start,
        "row_end": o.row_end,
        "x": int(round(o.x)),
        "y": int(round(o.y)),
        "w": int(round(o.w)),
        "h": int(round(o.h))
    })


def _object_solid(lv: SimpleNamespace, o: SimpleNamespace) -> None:
    """Object layer: solid record."""
    lv.solids.append({
        "col_start": o.col_start,
        "col_end": o.col_end,
        "row_start": o.row_start,
        "row_end": o.row_end,
        "x": int(round(o.x)),
        "y": int(round(o.y)),
        "w": int(round(o.w)),
        "h": int(round(o.h))
    })


def _object_push(lv: SimpleNamespace, o: SimpleNamespace) -> None:
    """Object layer: push record."""
    sprite_index = 18
    if "crate" in o.name_lower or "crate" in o.tag:
        sprite_index = 18
    elif "sprite" in o.props:
        sprite_index = int(o.props["sprite"])
    elif "tile_id" in o.props:
        sprite_index = int(o.props["tile_id"])

    if o.w > 0 and o.h > 0:
        for r in range(o.row_start, o.row_end + 1):
            for c in range(o.col_start, o.col_end + 1):
                lv.pushes.append({
                    "col": c,
                    "row": r,
                    "sprite": sprite_index,
                    "name": o.name or "CRATE",
                    "col_start": c,
                    "col_end": c,
                    "row_start": r,
                    "row_end": r
                })
    else:
        spawn_x = int(round(o.x))
        spawn_y = int(round(o.y)) - 16 if int(round(o.y)) % 16 == 0 else int(round(o.y))
        p_col = max(0, min(lv.width - 1, spawn_x // 16))
        p_row = max(0, min(lv.height - 1, spawn_y // 16))
        lv.pushes.append({
            "col": p_col,
            "row": p_row,
            "sprite": sprite_index,
            "name": o.name or "CRATE",
            "col_start": p_col,
            "col_end": p_col,
            "row_start": p_row,
            "row_end": p_row
        })


def _object_hazard(lv: SimpleNamespace, o: SimpleNamespace) -> None:
    """Object layer: hazard record."""
    damage = int(o.props.get("damage", 1))
    lv.hazards.append({
        "damage": damage,
        "left": int(round(o.x)),
        "top": int(round(o.y)),
        "right": int(round(o.x + o.w)),
        "bottom": int(round(o.y + o.h))
    })


def _object_trigger(lv: SimpleNamespace, o: SimpleNamespace) -> None:
    """Object layer: trigger record."""
    trig_id = int(o.props.get("trigger_id", o.props.get("id", len(lv.triggers) + 1)))
    target = o.props.get("target", "")
    lv.triggers.append({
        "id": trig_id,
        "left": int(round(o.x)),
        "top": int(round(o.y)),
        "right": int(round(o.x + o.w)),
        "bottom": int(round(o.y + o.h)),
        "target": target
    })


def _object_oxygen(lv: SimpleNamespace, o: SimpleNamespace) -> None:
    """Object layer: oxygen record."""
    spawn_x = int(round(o.x))
    spawn_y = int(round(o.y)) - 16 if int(round(o.y)) % 16 == 0 else int(round(o.y))
    o_col = max(0, min(lv.width - 1, spawn_x // 16))
    o_row = max(0, min(lv.height - 1, spawn_y // 16))
    tile_idx = int(o.props.get("tile_id", o.props.get("sprite", 95)))
    lv.oxygen_refills.append({
        "col": o_col,
        "row": o_row,
        "x": o_col * 16,
        "y": o_row * 16,
        "tile_id": tile_idx
    })
    print(f"      [Object] -> Oxygen Refill: Col={o_col}, Row={o_row} ({o_col*16}, {o_row*16})")


def _object_generic(lv: SimpleNamespace, o: SimpleNamespace) -> None:
    """Object layer: anything not matched above."""
    lv.generic_objects.append({
        "name": o.name,
        "type": o.obj_type,
        "x": int(round(o.x)),
        "y": int(round(o.y)),
        "w": int(round(o.w)),
        "h": int(round(o.h)),
        "props": o.props
    })


def _parse_object(lv: SimpleNamespace, obj: ET.Element) -> None:
    """Classify one Tiled object by its type/name tags and record it."""
    o = _object_context(lv, obj)
    if o.is_player:
        _object_player(lv, o)
    elif "enemy" in o.tag or "patrol" in o.tag or "flyer" in o.tag or "crawler" in o.tag or "enemy" in o.name_lower:
        _object_enemy(lv, o)
    elif "friend" in o.tag or "friend" in o.name_lower:
        _object_friend(lv, o)
    elif "bridge" in o.tag or "bridge" in o.name_lower:
        _object_bridge(lv, o)
    elif "ladder" in o.tag or "ladder" in o.name_lower or "climb" in o.tag:
        _object_ladder(lv, o)
    elif "solid" in o.tag or "solid" in o.name_lower or "platform" in o.tag or "platform" in o.name_lower or "wall" in o.tag or "wall" in o.name_lower or (not o.tag and not o.name_lower and o.w > 0 and o.h > 0):
        _object_solid(lv, o)
    elif "push" in o.tag or "push" in o.name_lower or "movable" in o.tag or "movable" in o.name_lower or "crate" in o.tag or "crate" in o.name_lower:
        _object_push(lv, o)
    elif "hazard" in o.tag or "spike" in o.tag or "lava" in o.tag or "hazard" in o.name_lower:
        _object_hazard(lv, o)
    elif "trigger" in o.tag or "exit" in o.tag or "door" in o.tag or "boss" in o.tag or "trigger" in o.name_lower:
        _object_trigger(lv, o)
    elif "oxygen" in o.tag or "oxygen" in o.name_lower or "air" in o.tag or "bottle" in o.tag:
        _object_oxygen(lv, o)
    else:
        _object_generic(lv, o)


def _parse_object_layers(lv: SimpleNamespace) -> None:
    """Object layers -> spawns, patrols, triggers, hazards, bridges, overrides."""
    for objgroup in lv.root.findall("objectgroup"):
        group_name = objgroup.attrib.get("name", "elements")
        print(f"    Found Object Layer: '{group_name}'")
        for obj in objgroup.findall("object"):
            _parse_object(lv, obj)



def _build_gamemap(lv: SimpleNamespace) -> None:
    """1D GameMap: stamp solids/ladders/pushes, auto-detect, resolve patrols, camera."""
    # =========================================================================
    # Construct 1D GameMap Array & Auto-Extract Missing Objects
    # =========================================================================
    print(f"[*] Constructing 1D GameMap ({lv.width} cols x {lv.height} rows = {lv.width * lv.height} bytes)...")

    # 1. Stamp solids from objectgroup
    for s in lv.solids:
        for r in range(s["row_start"], s["row_end"] + 1):
            for c in range(s["col_start"], s["col_end"] + 1):
                lv.gamemap[r * lv.width + c] = BLOCK_SOLID

    # 2. Stamp ladders from objectgroup
    for l in lv.ladders:
        for r in range(l["row_start"], l["row_end"] + 1):
            for c in range(l["col_start"], l["col_end"] + 1):
                lv.gamemap[r * lv.width + c] = BLOCK_LADDER

    # 3. Auto-detect ladders from tilemap if not defined by objectgroup
    for c in range(lv.width):
        r = 0
        while r < lv.height:
            if lv.gamemap[r * lv.width + c] == BLOCK_LADDER:
                r_start = r
                while r < lv.height and lv.gamemap[r * lv.width + c] == BLOCK_LADDER:
                    r += 1
                r_end = r - 1
                already_covered = any(l["col_start"] <= c <= l["col_end"] and l["row_start"] <= r_start and l["row_end"] >= r_end for l in lv.ladders)
                if not already_covered:
                    lv.ladders.append({
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
    if not lv.solids:
        for r in range(lv.height):
            c = 0
            while c < lv.width:
                if lv.gamemap[r * lv.width + c] == BLOCK_SOLID:
                    c_start = c
                    while c < lv.width and lv.gamemap[r * lv.width + c] == BLOCK_SOLID:
                        c += 1
                    c_end = c - 1
                    lv.solids.append({
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
    if not lv.bridges:
        for r in range(lv.height):
            c = 0
            while c < lv.width:
                t = lv.platform_grid[r * lv.width + c]
                if t in (38, 39, 40, 90, 91, 92):
                    c_start = c
                    while c < lv.width and lv.platform_grid[r * lv.width + c] in (38, 39, 40, 90, 91, 92):
                        c += 1
                    c_end = c - 1
                    lv.bridges.append({
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

    # 5. Push Blocks
    for p in lv.pushes:
        for r in range(p["row_start"], p["row_end"] + 1):
            for c in range(p["col_start"], p["col_end"] + 1):
                lv.gamemap[r * lv.width + c] = BLOCK_PUSH

    # 6. Bottom boundary solid floor
    for c in range(lv.width):
        lv.gamemap[(lv.height - 1) * lv.width + c] = BLOCK_SOLID

    # 7. Auto-patrol resolution for pending tile-based enemies
    for ep in lv.enemies_pending:
        c = ep["col"]
        r = ep["row"]
        if lv.gamemap[r * lv.width + c] == BLOCK_SOLID and r > 0:
            r -= 1
            ep["row"] = r
            ep["y"] = r * 16

        if ep["patrol_min_x"] is not None and ep["patrol_max_x"] is not None:
            p_min = ep["patrol_min_x"]
            p_max = ep["patrol_max_x"]
        else:
            floor_r = r + 1
            if floor_r < lv.height and lv.gamemap[floor_r * lv.width + c] in (BLOCK_SOLID, BLOCK_PUSH):
                min_c = c
                while min_c > 0 and lv.gamemap[floor_r * lv.width + (min_c - 1)] in (BLOCK_SOLID, BLOCK_PUSH) and lv.gamemap[r * lv.width + (min_c - 1)] != BLOCK_SOLID:
                    min_c -= 1
                max_c = c
                while max_c < lv.width - 1 and lv.gamemap[floor_r * lv.width + (max_c + 1)] in (BLOCK_SOLID, BLOCK_PUSH) and lv.gamemap[r * lv.width + (max_c + 1)] != BLOCK_SOLID:
                    max_c += 1
                p_min = min_c * 16
                p_max = max_c * 16
            else:
                p_min = max(0, (c - 3) * 16)
                p_max = min((lv.width - 2) * 16, (c + 3) * 16)

        max_patrol_x = (lv.width - 2) * 16
        p_min = max(0, min(max_patrol_x, p_min))
        p_max = max(p_min + 16, min(max_patrol_x, p_max))

        lv.enemies.append({
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
    for e in lv.enemies:
        if lv.gamemap[e["row"] * lv.width + e["col"]] == BLOCK_SOLID and e["row"] > 0:
            e["row"] -= 1
            e["y"] = e["row"] * 16

    # 9. Player spawn check
    if lv.gamemap[lv.player_start["row"] * lv.width + lv.player_start["col"]] == BLOCK_SOLID and lv.player_start["row"] > 0:
        lv.player_start["row"] -= 1
    lv.gamemap[lv.player_start["row"] * lv.width + lv.player_start["col"]] = BLOCK_PLAYERSTART

    # Finalize initial camera: if not explicitly specified, center on player start
    if not lv.has_explicit_init_cam:
        desired_cam = lv.player_start["row"] * 16 - 100
        lv.init_cam_y = max(lv.min_cam_y, min(lv.max_cam_y, desired_cam))
    else:
        lv.init_cam_y = max(lv.min_cam_y, min(lv.max_cam_y, lv.init_cam_y))


def _write_binary_maps(lv: SimpleNamespace) -> bool:
    """Per-layer .map files, composite map, gamemap.bin, optional .lvl package."""
    # =========================================================================
    # Write Binary Tilemap & GameMap Files
    # =========================================================================
    print("[*] Generating Binary .map and -gamemap.bin files...")
    lv.exported_map_files = []

    # 1. Background layer map (contains visual scenery)
    out_bg = lv.out_dir / f"{lv.prefix}-background.map"
    write_binary_map(out_bg, lv.width, lv.height, lv.scenery_grid)
    lv.exported_map_files.append(("background", f"{lv.prefix}-background.map", out_bg))
    print(f"    Exported layer 'background': {out_bg} ({out_bg.stat().st_size} bytes)")

    # 2. Platform layer map (contains platforms, walls, floors, bridges)
    out_plat = lv.out_dir / f"{lv.prefix}-platform.map"
    write_binary_map(out_plat, lv.width, lv.height, lv.platform_grid)
    lv.exported_map_files.append(("platform", f"{lv.prefix}-platform.map", out_plat))
    print(f"    Exported layer 'platform': {out_plat} ({out_plat.stat().st_size} bytes)")

    # 3. Ladder layer map (contains climbable ladders)
    out_ladder = lv.out_dir / f"{lv.prefix}-ladder.map"
    write_binary_map(out_ladder, lv.width, lv.height, lv.ladder_grid)
    lv.exported_map_files.append(("ladder", f"{lv.prefix}-ladder.map", out_ladder))
    print(f"    Exported layer 'ladder': {out_ladder} ({out_ladder.stat().st_size} bytes)")

    # 4. Foreground layer map (contains trees, arches, canopy)
    out_fg = lv.out_dir / f"{lv.prefix}-foreground.map"
    write_binary_map(out_fg, lv.width, lv.height, lv.foreground_grid)
    lv.exported_map_files.append(("foreground", f"{lv.prefix}-foreground.map", out_fg))
    print(f"    Exported layer 'foreground': {out_fg} ({out_fg.stat().st_size} bytes)")

    # 5. Water layer map (contains water tiles)
    if any(lv.water_grid):
        out_water = lv.out_dir / f"{lv.prefix}-water.map"
        write_binary_map(out_water, lv.width, lv.height, lv.water_grid)
        lv.exported_map_files.append(("water", f"{lv.prefix}-water.map", out_water))
        print(f"    Exported layer 'water': {out_water} ({out_water.stat().st_size} bytes)")

    # 6. Composite / Merged map (scenery + platforms + ladders + foreground)
    composite_grid = [0] * (lv.width * lv.height)
    for i in range(lv.width * lv.height):
        if lv.scenery_grid[i] != 0:
            composite_grid[i] = lv.scenery_grid[i]
        if lv.platform_grid[i] != 0:
            composite_grid[i] = lv.platform_grid[i]
        if lv.ladder_grid[i] != 0:
            composite_grid[i] = lv.ladder_grid[i]
        if lv.foreground_grid[i] != 0:
            composite_grid[i] = lv.foreground_grid[i]

    lv.composite_name = f"{lv.prefix}.map"
    composite_path = lv.out_dir / lv.composite_name
    write_binary_map(composite_path, lv.width, lv.height, composite_grid)
    print(f"    Exported composite map: {composite_path} ({composite_path.stat().st_size} bytes)")

    # 7. 1D GameMap Binary
    lv.gamemap_name = f"{lv.prefix}-gamemap.bin"
    gamemap_path = lv.out_dir / lv.gamemap_name
    with open(gamemap_path, "wb") as f_gmap:
        f_gmap.write(bytes(lv.gamemap))
    print(f"    Exported 1D GameMap: {gamemap_path} ({len(lv.gamemap)} bytes)")

    if lv.package_out:
        layer_grids = [
            ("background", lv.scenery_grid),
            ("platform", lv.platform_grid),
            ("ladder", lv.ladder_grid),
            ("foreground", lv.foreground_grid),
            ("water", lv.water_grid if any(lv.water_grid) else None),
        ]
        pal = lv.tileset_info["palette"] if (lv.tileset_info and "palette" in lv.tileset_info) else DEFAULT_PALETTE_OCS
        package_level_binary(
            package_path=Path(lv.package_out),
            width=lv.width,
            height=lv.height,
            min_cam_y=lv.min_cam_y,
            max_cam_y=lv.max_cam_y,
            init_cam_y=lv.init_cam_y,
            cam_margin_top=lv.cam_margin_top,
            cam_margin_bottom=lv.cam_margin_bottom,
            player_start=lv.player_start,
            player2_start=lv.player2_start,
            enemies=lv.enemies,
            friends=lv.friends,
            pushes=lv.pushes,
            ladders=lv.ladders,
            solids=lv.solids,
            triggers=lv.triggers,
            hazards=lv.hazards,
            bridges=lv.bridges,
            oxygen_refills=lv.oxygen_refills,
            pal=pal,
            level_title=lv.level_title,
            level_sub_title=lv.level_sub_title,
            gamemap=lv.gamemap,
            layer_grids=layer_grids
        )
        if lv.asm_out is None:
            print("[*] Standalone level package created. Skipping assembly metadata.")
            return True


def _asm_begin(lv: SimpleNamespace) -> None:
    """Assembly file: header, incbin paths, layer presence flags."""
    # =========================================================================
    # Write Assembly Metadata File
    # =========================================================================
    if lv.asm_out is None:
        # Default to include/levels/<prefix>_entities.asm, or out_dir/<prefix>_entities.asm
        include_dir = Path(__file__).resolve().parent.parent / "include" / "levels"
        if include_dir.parent.exists():
            include_dir.mkdir(parents=True, exist_ok=True)
            lv.asm_path = include_dir / f"{lv.prefix.lower()}_entities.asm"
        else:
            lv.asm_path = lv.out_dir / f"{lv.prefix.lower()}_entities.asm"
    else:
        lv.asm_path = Path(lv.asm_out).resolve()

    lv.asm_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"[*] Generating Assembly Metadata: {lv.asm_path}")

    # Relative path from project root for incbins
    project_root = Path(__file__).resolve().parent.parent
    lv.rel_out_dir = os.path.relpath(lv.out_dir, project_root).replace("\\", "/")

    # The 4 reference source layers blitted into NonDisplayScreen:
    # 1. Scenery/Background, 2. Platforms, 3. Ladders, 4. Foreground
    ref_layer_slugs = ["background", "platform", "ladder", "foreground"]
    lv.ref_layers = [f"{lv.prefix}_{slug.capitalize()}Map" for slug in ref_layer_slugs if any(s == slug for s, _, _ in lv.exported_map_files)]
    lv.layer_count = len(lv.ref_layers)

    lv.asm_lines = [
        ";==============================================================================",
        f"; Auto-generated Level Metadata for {lv.prefix}",
        f"; Generated from: {lv.tmx_path.name}",
        ";==============================================================================",
        "",
        f"{lv.prefix}_MapWidth:        dc.w    {lv.width}",
        f"{lv.prefix}_MapHeight:       dc.w    {lv.height}",
        f"{lv.prefix}_MapSize:         dc.w    {lv.width * lv.height}",
        f"{lv.prefix}_TileWidth:       dc.w    {lv.tile_w}",
        f"{lv.prefix}_TileHeight:      dc.w    {lv.tile_h}",
        f"{lv.prefix}_LayerCount:      dc.w    {lv.layer_count}",
        "",
        ";------------------------------------------------------------------------------",
        "; Tilemap Layer Binaries",
        ";------------------------------------------------------------------------------",
    ]

    for slug, fname, _ in lv.exported_map_files:
        label = f"{lv.prefix}_{slug.capitalize()}Map"
        rel_path = f"{lv.rel_out_dir}/{fname}"
        lv.asm_lines.extend([
            f"{label}:",
            f'    incbin     "{rel_path}"',
            "    even",
            ""
        ])
        if slug == "background":
            lv.asm_lines.extend([
                f"{lv.prefix}_SceneryMap = {lv.prefix}_BackgroundMap",
                ""
            ])

    has_bg = any("bg" in slug.lower() or "background" in slug.lower() for slug, _, _ in lv.exported_map_files)
    has_plat = any("plat" in slug.lower() or "platform" in slug.lower() for slug, _, _ in lv.exported_map_files)
    has_ladder = any("ladder" in slug.lower() for slug, _, _ in lv.exported_map_files)
    has_fg = any("fg" in slug.lower() or "foreground" in slug.lower() for slug, _, _ in lv.exported_map_files)
    has_water = any("water" in slug.lower() for slug, _, _ in lv.exported_map_files)
    if not has_bg:
        lv.asm_lines.extend([
            f"{lv.prefix}_BackgroundMap = 0",
            f"{lv.prefix}_SceneryMap = 0",
            ""
        ])
    if not has_plat:
        lv.asm_lines.extend([
            f"{lv.prefix}_PlatformMap = 0",
            ""
        ])
    if not has_ladder:
        lv.asm_lines.extend([
            f"{lv.prefix}_LadderMap = 0",
            ""
        ])
    if not has_fg:
        lv.asm_lines.extend([
            f"{lv.prefix}_ForegroundMap = 0",
            ""
        ])
    if not has_water:
        lv.asm_lines.extend([
            f"{lv.prefix}_WaterMap = 0",
            ""
        ])


def _asm_layer_table(lv: SimpleNamespace) -> None:
    """Assembly file: ordered reference-layer table."""
    # Ordered Layer Table (Blit Reference Source for NonDisplayScreen)
    lv.asm_lines.extend([
        ";------------------------------------------------------------------------------",
        "; Ordered Tilemap Layer Table (Blit Reference Source for NonDisplayScreen)",
        "; Format: Pointers to each layer's binary map, terminated by 0",
        "; Order: 1. Scenery/Background, 2. Platforms, 3. Ladders, 4. Foreground",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_LayerList:"
    ])
    for label in lv.ref_layers:
        lv.asm_lines.append(f"    dc.l    {label}")
    lv.asm_lines.extend([
        "    dc.l    0                           ; Null termination",
        ""
    ])


def _asm_entity_tables(lv: SimpleNamespace) -> None:
    """Assembly file: composite incbin, entity/trigger/hazard/bridge tables."""
    # Composite map incbin
    lv.asm_lines.extend([
        f"{lv.prefix}_CompositeMap:",
        f'    incbin     "{lv.rel_out_dir}/{lv.composite_name}"',
        "    even",
        "",
        ";------------------------------------------------------------------------------",
        f"; 1D GameMap Binary ({lv.width} cols x {lv.height} rows = {lv.width * lv.height} bytes)",
        "; Format: 1 byte per tile, containing BLOCK_xxx values",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_GameMap:",
        f'    incbin     "{lv.rel_out_dir}/{lv.gamemap_name}"',
        "    even",
        "",
        ";------------------------------------------------------------------------------",
        "; Player Starting Coordinates",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_PlayerStartX:    dc.w    {lv.player_start['x']}",
        f"{lv.prefix}_PlayerStartY:    dc.w    {lv.player_start['y']}",
        f"{lv.prefix}_PlayerCol:       dc.w    {lv.player_start['col']}",
        f"{lv.prefix}_PlayerRow:       dc.w    {lv.player_start['row']}",
        f"{lv.prefix}_PlayerXDec:      dc.w    {lv.player_start['xdec']}",
        f"{lv.prefix}_PlayerDir:       dc.w    {lv.player_start['dir']}       ; -1=Left, +1=Right",
        "",
        ";------------------------------------------------------------------------------",
        "; Player 2 Starting Coordinates (0 if solo)",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_Player2StartX:   dc.w    {lv.player2_start['x']}",
        f"{lv.prefix}_Player2StartY:   dc.w    {lv.player2_start['y']}",
        f"{lv.prefix}_Player2Col:      dc.w    {lv.player2_start['col']}",
        f"{lv.prefix}_Player2Row:      dc.w    {lv.player2_start['row']}",
        f"{lv.prefix}_Player2XDec:     dc.w    {lv.player2_start['xdec']}",
        f"{lv.prefix}_Player2Dir:      dc.w    {lv.player2_start['dir']}       ; -1=Left, +1=Right (0=Solo)",
        "",
        ";------------------------------------------------------------------------------",
        "; Enemy Spawn Table",
        "; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), PatrolMinX (w), PatrolMaxX (w), Speed (w)",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_EnemyCount:      dc.w    {len(lv.enemies)}",
        f"{lv.prefix}_EnemyList:"
    ])

    if lv.enemies:
        for i, e in enumerate(lv.enemies):
            lv.asm_lines.append(
                f"    dc.w    {e['type']}, {e['col']}, {e['row']}, {e['x']}, {e['y']}, {e['patrol_min']}, {e['patrol_max']}, {e['speed']}   ; Enemy {i + 1}"
            )
    lv.asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Animal Friends Spawn Table",
        "; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), Res1 (w), Res2 (w), Res3 (w)",
        ";   Type: 1=DOG1 (Shiba), 2=DOG2 (Puppy), 3=DUCKLING",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_FriendCount:     dc.w    {len(lv.friends)}",
        f"{lv.prefix}_FriendList:"
    ])

    if lv.friends:
        for i, f in enumerate(lv.friends):
            lv.asm_lines.append(
                f"    dc.w    {f['type']}, {f['col']}, {f['row']}, {f['x']}, {f['y']}, 0, 0, 0   ; Friend {i + 1}: {f['name']}"
            )
    lv.asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Pushable / Movable Blocks Table",
        "; Format: Col (w), Row (w), SpriteIndex (w), Reserved (w)",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_BlockCount:      dc.w    {len(lv.pushes)}",
        f"{lv.prefix}_BlockList:",
    ])

    if lv.pushes:
        for i, p in enumerate(lv.pushes):
            lv.asm_lines.append(
                f"    dc.w    {p['col']}, {p['row']}, {p['sprite']}, 0   ; Block {i + 1}: {p['name']}"
            )
    lv.asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Ladder Zones",
        "; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_LadderCount:     dc.w    {len(lv.ladders)}",
        f"{lv.prefix}_LadderList:"
    ])

    if lv.ladders:
        for i, l in enumerate(lv.ladders):
            lv.asm_lines.append(
                f"    dc.w    {l['col_start']}, {l['col_end']}, {l['row_start']}, {l['row_end']}   ; Ladder {i + 1} (x={l['x']}, y={l['y']}, w={l['w']}, h={l['h']})"
            )
    lv.asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Solid Platform Zones",
        "; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_SolidCount:      dc.w    {len(lv.solids)}",
        f"{lv.prefix}_SolidList:"
    ])

    if lv.solids:
        for i, s in enumerate(lv.solids):
            lv.asm_lines.append(
                f"    dc.w    {s['col_start']}, {s['col_end']}, {s['row_start']}, {s['row_end']}   ; Solid {i + 1} (x={s['x']}, y={s['y']}, w={s['w']}, h={s['h']})"
            )
    lv.asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Triggers & Level Event Zones",
        "; Format: TriggerID (w), Left (w), Top (w), Right (w), Bottom (w)",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_TriggerCount:    dc.w    {len(lv.triggers)}",
        f"{lv.prefix}_TriggerList:"
    ])

    if lv.triggers:
        for t in lv.triggers:
            comment = f" ; target={t['target']}" if t['target'] else ""
            lv.asm_lines.append(
                f"    dc.w    {t['id']}, {t['left']}, {t['top']}, {t['right']}, {t['bottom']}{comment}"
            )
    lv.asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Hazard Zones",
        "; Format: Damage (w), Left (w), Top (w), Right (w), Bottom (w)",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_HazardCount:     dc.w    {len(lv.hazards)}",
        f"{lv.prefix}_HazardList:"
    ])

    if lv.hazards:
        for h in lv.hazards:
            lv.asm_lines.append(
                f"    dc.w    {h['damage']}, {h['left']}, {h['top']}, {h['right']}, {h['bottom']}"
            )
    lv.asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Bridge Zones",
        "; Format: LeftX (w), RightX (w), PlatformRow (w), Reserved (w)",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_BridgeCount:     dc.w    {len(lv.bridges)}",
        f"{lv.prefix}_BridgeList:"
    ])

    if lv.bridges:
        for b in lv.bridges:
            lv.asm_lines.append(
                f"    dc.w    {b['x']}, {b['x'] + b['w']}, {b['row_start']}, 0   ; Bridge (x={b['x']}, y={b['y']}, w={b['w']}, h={b['h']})"
            )
    lv.asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        "",
        ";------------------------------------------------------------------------------",
        "; Oxygen Refills Table",
        "; Format: Col (w), Row (w), PixelX (w), PixelY (w), TileId (w), Reserved (3 words)",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_OxygenCount:     dc.w    {len(lv.oxygen_refills)}",
        f"{lv.prefix}_OxygenList:"
    ])

    if lv.oxygen_refills:
        for i, ox in enumerate(lv.oxygen_refills):
            lv.asm_lines.append(
                f"    dc.w    {ox['col']}, {ox['row']}, {ox['x']}, {ox['y']}, {ox['tile_id']}, 0, 0, 0   ; Oxygen Refill {i + 1}"
            )
    lv.asm_lines.extend([
        "    dc.w    $ffff                       ; End of list marker",
        ""
    ])


def _asm_tile_attributes(lv: SimpleNamespace) -> None:
    """Assembly file: 256-byte tile attribute table."""
    # Tile Physical Attributes Table (256 bytes)
    lv.asm_lines.extend([
        ";------------------------------------------------------------------------------",
        "; Tile Physical Attributes Table (256 bytes)",
        "; Maps tile indices to collision flags: 0=Empty, 1=Solid, 2=Ladder, 3=Hazard, 4=Passthrough",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_TileAttributesTable:",
        "    ; Index 00: Empty space",
        "    dc.b    ATTR_EMPTY"
    ])

    # Build 255 remaining entries
    for row in range(1, 256, 16):
        row_entries = []
        for tid in range(row, min(row + 16, 256)):
            # Lookup attribute from tileset or default
            attr = lv.tileset_attrs.get(tid, ATTR_SOLID if (1 <= tid <= 32) else ATTR_EMPTY)
            attr_name = ["ATTR_EMPTY", "ATTR_SOLID", "ATTR_LADDER", "ATTR_HAZARD", "ATTR_PASSTHROUGH"][attr]
            row_entries.append(attr_name)
        lv.asm_lines.append("    dc.b    " + ", ".join(row_entries))


def _asm_leveldef(lv: SimpleNamespace) -> None:
    """Assembly file: layer labels, palette, strings, LevelDef struct; write file."""
    # Identify background, platform, ladder, foreground, and water layer labels
    bg_map_label = f"{lv.prefix}_BackgroundMap" if any(s == "background" for s, _, _ in lv.exported_map_files) else "0"
    plat_map_label = f"{lv.prefix}_PlatformMap" if any(s == "platform" for s, _, _ in lv.exported_map_files) else "0"
    ladder_map_label = f"{lv.prefix}_LadderMap" if any(s == "ladder" for s, _, _ in lv.exported_map_files) else "0"
    fg_map_label = f"{lv.prefix}_ForegroundMap" if any(s == "foreground" for s, _, _ in lv.exported_map_files) else "0"
    water_map_label = f"{lv.prefix}_WaterMap" if any(s == "water" for s, _, _ in lv.exported_map_files) else "0"

    # Palette words (16 words formatted as $0RGB)
    pal = lv.tileset_info["palette"] if (lv.tileset_info and "palette" in lv.tileset_info) else DEFAULT_PALETTE_OCS
    pal_words = [f"${(r << 8) | (g << 4) | b:04x}" for r, g, b in pal]
    pal_row1 = ", ".join(pal_words[:8])
    pal_row2 = ", ".join(pal_words[8:])

    # Escape strings if needed
    safe_title = lv.level_title.replace('"', "'")
    safe_sub_title = lv.level_sub_title.replace('"', "'")

    lv.asm_lines.extend([
        "    even",
        "",
        ";------------------------------------------------------------------------------",
        "; 16-Color OCS Level Palette",
        "; Format: 16 words (RGB444: 0x0RGB)",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_Palette:",
        f"    dc.w    {pal_row1}",
        f"    dc.w    {pal_row2}",
        "    even",
        "",
        ";------------------------------------------------------------------------------",
        "; Level Text Strings",
        ";------------------------------------------------------------------------------",
        f"{lv.prefix}_TitleStr:",
        f'    dc.b    "{safe_title}",0',
        "    even",
        "",
        f"{lv.prefix}_SubTitleStr:",
        f'    dc.b    "{safe_sub_title}",0',
        "    even",
        f"{lv.prefix}_HintStr = {lv.prefix}_SubTitleStr",
        "",
        ";==============================================================================",
        "; Level Descriptor Definition",
        "; Conforms to LevelDef record structure in include/resources/struct.asm",
        ";==============================================================================",
        f"{lv.prefix}_Def:",
        "    ; --- Visuals & Audio ---",
        asm_line("dc.l", lv.tileset_raw, "Tileset graphics pointer"),
        asm_line("dc.l", lv.tileset_msk, "Tileset mask pointer"),
        asm_line("dc.l", lv.palette_name, "Palette pointer (16 RGB words)"),
        asm_line("dc.l", lv.music_name, "BGM ProTracker MOD pointer"),
        "",
        "    ; --- Geometry & Binary Maps ---",
        asm_line("dc.w", f"{lv.width}, {lv.height}", "Map width, height in tiles"),
        asm_line("dc.l", bg_map_label, "Background layer binary pointer (0 if none)"),
        asm_line("dc.l", plat_map_label, "Platform layer binary pointer (0 if none)"),
        asm_line("dc.l", ladder_map_label, "Ladder layer binary pointer (0 if none)"),
        asm_line("dc.l", fg_map_label, "Foreground layer binary pointer (0 if none)"),
        asm_line("dc.l", water_map_label, "Water layer binary pointer (0 if none)"),
        asm_line("dc.w", f"{lv.layer_count}, 0", "Number of ordered tile layers, reserved"),
        asm_line("dc.l", f"{lv.prefix}_LayerList", "Ordered layer list pointer (TMX order)"),
        asm_line("dc.l", f"{lv.prefix}_GameMap", "1D collision GameMap binary pointer"),
        "",
        "    ; --- Camera Bounds & Margins ---",
        asm_line("dc.w", f"{lv.min_cam_y}, {lv.max_cam_y}", "MinCameraY, MaxCameraY"),
        asm_line("dc.w", str(lv.init_cam_y), "InitialCameraY"),
        asm_line("dc.w", f"{lv.cam_margin_top}, {lv.cam_margin_bottom}", "CamMarginTop, CamMarginBottom"),
        "",
        "    ; --- Player Starts ---",
        asm_line("dc.w", f"{lv.player_start['col']}, {lv.player_start['row']}, {lv.player_start['dir']}", "Player 1: Col, Row, Facing (+1=Right, -1=Left)"),
        asm_line("dc.w", f"{lv.player2_start['col']}, {lv.player2_start['row']}, {lv.player2_start['dir']}", "Player 2: Col, Row, Facing (0=None/Solo)"),
        "",
        "    ; --- Entity & Object Lists ---",
        asm_line("dc.l", f"{lv.prefix}_EnemyList", "Enemy spawn table"),
        asm_line("dc.l", f"{lv.prefix}_FriendList", "Animal friends spawn table"),
        asm_line("dc.l", f"{lv.prefix}_BlockList", "Pushable blocks table"),
        asm_line("dc.l", f"{lv.prefix}_LadderList", "Ladder zones table"),
        asm_line("dc.l", f"{lv.prefix}_SolidList", "Solid platform zones table"),
        asm_line("dc.l", f"{lv.prefix}_TriggerList", "Triggers / switches table"),
        asm_line("dc.l", f"{lv.prefix}_HazardList", "Hazard zones table"),
        asm_line("dc.l", f"{lv.prefix}_BridgeList", "Bridge zones table"),
        asm_line("dc.l", f"{lv.prefix}_OxygenList", "Oxygen refills table"),
        "",
        "    ; --- Banner Text ---",
        asm_line("dc.l", f"{lv.prefix}_TitleStr", "Null-terminated title string"),
        asm_line("dc.l", f"{lv.prefix}_SubTitleStr", "Null-terminated subtitle string"),
        "    even",
        ""
    ])

    with open(lv.asm_path, "w", encoding="utf-8") as f_asm:
        f_asm.write("\n".join(lv.asm_lines) + "\n")

    print(f"[*] Done! Level {lv.prefix} successfully exported.")


def _lint_layout(lv: SimpleNamespace) -> list[str]:
    """Check the ladder layout rules of Chapter 28 and return one warning per
    break. The checks only warn: a map that breaks a rule still exports.

    Rule 1a: the top rung of a ladder sits in the platform row, with a solid
             tile beside it, so the player can step on from the walkway.
    Rule 1b: the bottom rung sits in the open cell above the floor; a ladder
             tile painted over a floor cell turns that floor into a ladder.
    Rule 1c: a ladder ends on something solid, not in mid-air.
    """
    w, h = lv.width, lv.height
    warnings = []
    for idx in sorted(lv.ladder_cells):
        c, r = idx % w, idx // w
        above = idx - w if r > 0 else None
        below = idx + w if r < h - 1 else None
        is_top = above is None or above not in lv.ladder_cells
        is_bottom = below is None or below not in lv.ladder_cells
        if is_top and r > 0:
            beside = [lv.gamemap[idx + d] for d in (-1, 1) if 0 <= c + d < w]
            if BLOCK_SOLID not in beside:
                warnings.append(f"ladder top at col {c}, row {r} has no solid tile beside it (rule 1a)")
        if is_bottom:
            if idx in lv.platform_cells and above is not None and above in lv.ladder_cells:
                warnings.append(f"ladder tile over the floor at col {c}, row {r}: the floor becomes a ladder (rule 1b)")
            elif below is not None and lv.gamemap[below] not in (BLOCK_SOLID, BLOCK_PUSH):
                warnings.append(f"ladder at col {c} ends in mid-air at row {r} (rule 1c)")
    return warnings


def export_tmx(tmx_file: str, out_dir: str | None = None, asm_out: str | None = None, prefix: str | None = None, package_out: str | None = None) -> None:
    """Export one Tiled .tmx level: binary layer maps, gamemap.bin, and the
    assembly metadata file. Runs the stage functions above in order, sharing
    state through one SimpleNamespace `lv` (every cross-stage name is an
    attribute of it; stage-private names stay local)."""
    lv = SimpleNamespace(tmx_file=tmx_file, out_dir=out_dir, asm_out=asm_out, prefix=prefix, package_out=package_out)
    _parse_header(lv)
    _parse_tile_layers(lv)
    _parse_object_layers(lv)
    _build_gamemap(lv)
    for warning in _lint_layout(lv):
        print(f"    WARNING: {warning}")
    if _write_binary_maps(lv):
        return                       # standalone .lvl package only
    _asm_begin(lv)
    _asm_layer_table(lv)
    _asm_entity_tables(lv)
    _asm_tile_attributes(lv)
    _asm_leveldef(lv)


def main():
    parser = argparse.ArgumentParser(description="Export Tiled TMX map to Amiga binary and assembly format")
    parser.add_argument("tmx", nargs="*", default=[], help="Path to Tiled .tmx file(s)")
    parser.add_argument("--out-dir", "-o", default=None, help="Directory for binary .map output files")
    parser.add_argument("--asm-out", "-a", default=None, help="Path for assembly .asm metadata file")
    parser.add_argument("--prefix", "-p", default=None, help="Prefix for labels and filenames")
    parser.add_argument("--package", default=None, help="Package map into standalone .lvl binary (e.g. test.lvl)")

    args = parser.parse_args()
    if not args.tmx:
        # Auto-discover all .tmx files in assets/levels/
        levels_dir = Path(__file__).resolve().parent.parent / "assets" / "levels"
        # Skip scratch levels (any path component under assets/levels containing
        # "temp"). Test the path relative to levels_dir, not the absolute path,
        # so a checkout under a directory called "Temp" still exports.
        tmx_files = sorted(
            p for p in levels_dir.glob("**/*.tmx")
            if "temp" not in p.relative_to(levels_dir).as_posix().lower()
        )
        if not tmx_files:
            print("Error: No .tmx files found in assets/levels", file=sys.stderr)
            sys.exit(1)
        for tmx in tmx_files:
            export_tmx(str(tmx), package_out=args.package)
    else:
        for tmx in args.tmx:
            export_tmx(tmx, args.out_dir, args.asm_out, args.prefix, package_out=args.package)


if __name__ == "__main__":
    main()
