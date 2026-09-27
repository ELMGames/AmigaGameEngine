#!/usr/bin/env python3
"""
Generate redesigned Level 1 TMX for Amiga Game Engine using pure Tile Layers.
Features:
- 20 columns x 42 rows (320x672 pixels)
- 4 Tilesets: AmigaGameEngine (World), Enemies, Friends, Player
- 6 Tile Layers: scenery, platforms, ladders, entities, foreground, water
- NO manual objectgroup! All entities, platforms, and ladders are defined via tiles.
- 4 Crate Puzzles (pushable blocks dropping into gaps to create walkable bridges)
- 4 Patrol Enemies (stunnable with cane, auto-patrol detected from platforms)
- 6 Animal Friends to rescue across all vertical tiers
- Rising water from bottom (rows 40-41)
- Seamless ladder ascents connecting all sectors up to the Summit Sanctuary
"""

import xml.etree.ElementTree as ET
from xml.dom import minidom
from PIL import Image, ImageDraw

WIDTH = 20
HEIGHT = 42

# --- Tileset 1: AmigaGameEngine.tsx (firstgid = 1) ---
T_EMPTY = 0

# Platforms:
T_GRASS_L   = 1    # Left rounded grass edge
T_GRASS_M   = 2    # Flat grass middle
T_GRASS_R   = 3    # Right rounded grass edge
T_DIRT_M    = 14   # Under-grass dirt / earth
T_STONE_L   = 18   # Stone wall left
T_STONE_M   = 19   # Stone wall middle
T_STONE_R   = 20   # Stone wall right
T_WOOD_L    = 38   # Wooden bridge plank left
T_WOOD_M    = 39   # Wooden bridge plank mid
T_WOOD_R    = 40   # Wooden bridge plank right

# Tree / Canopy / Foliage:
T_LEAF_TL   = 34   # Top left leaves
T_LEAF_TM   = 35   # Top mid leaves
T_LEAF_BL   = 45   # Mid leaves
T_LEAF_BM   = 46   # Mid leaves
T_LEAF_DENSE= 59   # Dense green foliage
T_TRUNK_TOP = 50   # Tree trunk top
T_TRUNK_MID = 61   # Tree trunk middle
T_TRUNK_BOT = 72   # Tree trunk base

# Ladders:
T_LADDER_TOP = 66  # Ladder top rung with handles
T_LADDER_MID = 67  # Ladder vertical rungs

# Push Block (Crate):
T_CRATE = 37       # Wooden crate with cross bracing (TID 37 -> GID 38)

# Water:
T_WATER_SURF = 104 # Water wave surface (semi-transparent)
T_WATER_DEEP = 115 # Deep water (semi-transparent)

# --- Tileset 2: Enemies.tsx (firstgid = 177) ---
GID_ENEMY_SLIME_CYAN = 177  # Type 1
GID_ENEMY_SLIME_RED  = 181  # Type 2
GID_ENEMY_WASP       = 185  # Type 3
GID_ENEMY_BAT        = 189  # Type 4
GID_ENEMY_CYCLOPS    = 193  # Type 5
GID_ENEMY_OCTO       = 197  # Type 6
GID_ENEMY_SNAIL      = 201  # Type 7
GID_ENEMY_GHOST      = 205  # Type 8

# --- Tileset 3: Friends.tsx (firstgid = 209) ---
GID_FRIEND_DOG1      = 209  # Type 1 (Tan Shiba)
GID_FRIEND_DOG2      = 213  # Type 2 (White Puppy)
GID_FRIEND_DUCKLING  = 217  # Type 3 (Duckling)

# --- Tileset 4: Player.tsx (firstgid = 221) ---
GID_PLAYER_SPAWN     = 221  # Player Idle Spawn

def gid(t):
    return (t + 1) if t > 0 else 0

# Six dedicated tile layer grids:
scenery_grid   = [0] * (WIDTH * HEIGHT)
platforms_grid = [0] * (WIDTH * HEIGHT)
ladders_grid   = [0] * (WIDTH * HEIGHT)
entities_grid  = [0] * (WIDTH * HEIGHT)
foreground_grid= [0] * (WIDTH * HEIGHT)
water_grid     = [0] * (WIDTH * HEIGHT)

def set_scenery(c, r, tid):
    if 0 <= c < WIDTH and 0 <= r < HEIGHT:
        scenery_grid[r * WIDTH + c] = gid(tid)

def set_platform(c, r, tid):
    if 0 <= c < WIDTH and 0 <= r < HEIGHT:
        platforms_grid[r * WIDTH + c] = gid(tid)

def set_ladder(c, r, tid):
    if 0 <= c < WIDTH and 0 <= r < HEIGHT:
        ladders_grid[r * WIDTH + c] = gid(tid)

def set_entity(c, r, raw_gid):
    if 0 <= c < WIDTH and 0 <= r < HEIGHT:
        entities_grid[r * WIDTH + c] = raw_gid

def set_fg(c, r, tid):
    if 0 <= c < WIDTH and 0 <= r < HEIGHT:
        foreground_grid[r * WIDTH + c] = gid(tid)

def set_water(c, r, tid):
    if 0 <= c < WIDTH and 0 <= r < HEIGHT:
        water_grid[r * WIDTH + c] = gid(tid)

# Helpers to draw platforms:
def draw_grass_platform(c_start, c_end, r):
    for c in range(c_start, c_end + 1):
        if c == c_start:
            set_platform(c, r, T_GRASS_L)
        elif c == c_end:
            set_platform(c, r, T_GRASS_R)
        else:
            set_platform(c, r, T_GRASS_M)
        if r + 1 < HEIGHT:
            set_platform(c, r + 1, T_DIRT_M)

def draw_stone_platform(c_start, c_end, r):
    for c in range(c_start, c_end + 1):
        if c == c_start:
            set_platform(c, r, T_STONE_L)
        elif c == c_end:
            set_platform(c, r, T_STONE_R)
        else:
            set_platform(c, r, T_STONE_M)

def draw_wood_bridge(c_start, c_end, r):
    for c in range(c_start, c_end + 1):
        if c == c_start:
            set_platform(c, r, T_WOOD_L)
        elif c == c_end:
            set_platform(c, r, T_WOOD_R)
        else:
            set_platform(c, r, T_WOOD_M)

def draw_ladder_tiles(c, r_top, r_bot):
    set_ladder(c, r_top, T_LADDER_TOP)
    for r in range(r_top + 1, r_bot + 1):
        set_ladder(c, r, T_LADDER_MID)


# =============================================================================
# 1. POPULATE LAYERS
# =============================================================================

# --- Bottom Reservoir (Rows 40, 41) ---
for c in range(WIDTH):
    set_water(c, 40, T_WATER_SURF)
    set_water(c, 41, T_WATER_DEEP)
    set_platform(c, 41, T_STONE_M)

# --- Sector 1: Ground Docks (Row 39) ---
# Left ground: Cols 0..8
draw_grass_platform(0, 8, 39)

# Low wooden bridge over pit: Cols 9..11
draw_wood_bridge(9, 11, 39)

# Right dock: Cols 12..19
draw_grass_platform(12, 19, 39)

# Player Spawn at Col 2, Row 39
set_entity(2, 39, GID_PLAYER_SPAWN)

# Friend 1: DOG1 at Col 16, Row 38
set_entity(16, 38, GID_FRIEND_DOG1)

# Ladder 1: Col 5, Rows 35..38
draw_ladder_tiles(5, 35, 38)


# --- Sector 2: Lower Platform Tier & Puzzle 1 (Row 35) ---
# Left ledge: Cols 2..7
draw_grass_platform(2, 7, 35)

# Ladder 2: Col 3, Rows 31..34
draw_ladder_tiles(3, 31, 34)

# Right ledge: Cols 10..13, GAP at Col 14, Cols 15..19
draw_grass_platform(10, 13, 35)
draw_grass_platform(15, 19, 35)

# Friend 2: DOG2 trapped at Col 17, Row 34
set_entity(17, 34, GID_FRIEND_DOG2)


# --- Sector 3: Lower-Mid Tier & Crate 1 (Row 31) ---
# Left platform: Cols 2..9
draw_stone_platform(2, 9, 31)

# Ladder 4 on left: Col 3, Rows 27..30
draw_ladder_tiles(3, 27, 30)

# Right platform: Cols 11..18
draw_stone_platform(11, 18, 31)

# Ladder 3 on right: Col 17, Rows 27..30
draw_ladder_tiles(17, 27, 30)

# CRATE 1 at Col 14, Row 31 (drops down into gap at Col 14, Row 35!)
set_entity(14, 31, gid(T_CRATE))

# Enemy 1: SLIME (Red Slime, type 2) patrolling on Row 30
set_entity(12, 30, GID_ENEMY_SLIME_RED)


# --- Sector 4: Mid Platform & High Perch Tower (Rows 27, 23) ---
# Row 27 Left: Cols 1..7
draw_grass_platform(1, 7, 27)

# Ladder 7 on left: Col 2, Rows 21..26
draw_ladder_tiles(2, 21, 26)

# Row 27 Right: Cols 12..18
draw_grass_platform(12, 18, 27)

# Enemy 2: WASP (type 3) patrolling mid runway Row 24
set_entity(4, 24, GID_ENEMY_WASP)

# High Perch Tower at Cols 9..11, Row 23
draw_wood_bridge(9, 11, 23)

# Ladder 6 from Tower down to Row 27: Col 10, Rows 24..27
draw_ladder_tiles(10, 24, 27)

# Friend 3: DUCKLING at Col 9, Row 22
set_entity(9, 22, GID_FRIEND_DUCKLING)

# Stepping Ledge on Row 23: Cols 12..16
draw_wood_bridge(12, 16, 23)

# Ladder 5 connecting Row 27 to Row 23: Col 14, Rows 24..26
draw_ladder_tiles(14, 24, 26)

# CRATE 2 at Col 12, Row 23
set_entity(12, 23, gid(T_CRATE))


# --- Sector 5: Upper Gallery & Gantry Puzzle (Rows 19, 15) ---
# Row 19 Platform:
draw_stone_platform(1, 5, 19)
draw_stone_platform(7, 11, 19)
draw_stone_platform(13, 19, 19)

# Friend 4: DOG1 trapped at Col 0, Row 18
set_entity(0, 18, GID_FRIEND_DOG1)

# Gantry on Row 15: Cols 5..9
draw_wood_bridge(5, 9, 15)

# Ladder 8: Col 8, Rows 16..18
draw_ladder_tiles(8, 16, 18)

# CRATE 3 at Col 6, Row 15 (drops 4 tiles down into gap at Col 6, Row 19!)
set_entity(6, 15, gid(T_CRATE))

# Enemy 3: BAT (type 4) on Right Gallery Row 18
set_entity(14, 18, GID_ENEMY_BAT)

# Ladder 9: Col 17, Rows 12..18
draw_ladder_tiles(17, 12, 18)


# --- Sector 6: Tree Canopy Walkway & Nest Puzzle (Rows 11, 7) ---
draw_grass_platform(2, 10, 11)
draw_grass_platform(12, 17, 11)

# Foliage decorations above canopy in foreground:
set_fg(13, 10, T_LEAF_TL)
set_fg(14, 10, T_LEAF_TM)
set_fg(15, 10, T_LEAF_DENSE)
set_fg(16, 10, T_LEAF_BM)

# Friend 5: DUCKLING at Col 14, Row 10
set_entity(14, 10, GID_FRIEND_DUCKLING)

# High branch on Row 7: Cols 9..13
draw_wood_bridge(9, 13, 7)

# Ladder 11 to High Branch: Col 9, Rows 8..10
draw_ladder_tiles(9, 8, 10)

# CRATE 4 at Col 11, Row 7 (drops down into gap at Col 11 on Row 11!)
set_entity(11, 7, gid(T_CRATE))

# Enemy 4: WASP (type 3) on Row 10
set_entity(7, 10, GID_ENEMY_WASP)


# --- Sector 7: The Grand Ascent & Summit Sanctuary (Rows 3..5) ---
# Ladder 10: Col 5, Rows 4..10
draw_ladder_tiles(5, 4, 10)

# Summit Sanctuary Platform on Row 3: Cols 3..16
draw_stone_platform(3, 16, 3)

# Ceiling border on Row 0 & 1
for c in range(WIDTH):
    set_platform(c, 0, T_STONE_M)
    if c in (0, 1, 18, 19):
        set_platform(c, 1, T_STONE_M)
        set_platform(c, 2, T_STONE_M)

# Foreground arches on Summit:
set_fg(4, 2, T_LEAF_TL)
set_fg(5, 2, T_LEAF_TM)
set_fg(6, 2, T_LEAF_DENSE)
set_fg(13, 2, T_LEAF_TL)
set_fg(14, 2, T_LEAF_TM)
set_fg(15, 2, T_LEAF_DENSE)

# Friend 6: DOG2 at Col 12, Row 2 (The Summit Peak Sanctuary!)
set_entity(12, 2, GID_FRIEND_DOG2)


# =============================================================================
# 2. BUILD TMX XML TREE (Multi-Tileset + 6 Dedicated Layers, NO Objectgroup!)
# =============================================================================
root = ET.Element("map", {
    "version": "1.10",
    "tiledversion": "1.12.2",
    "orientation": "orthogonal",
    "renderorder": "right-down",
    "width": str(WIDTH),
    "height": str(HEIGHT),
    "tilewidth": "16",
    "tileheight": "16",
    "infinite": "0",
    "nextlayerid": "7",
    "nextobjectid": "1"
})

props_elem = ET.SubElement(root, "properties")
ET.SubElement(props_elem, "property", {"name": "initial_camera_y", "type": "int", "value": "464"})
ET.SubElement(props_elem, "property", {"name": "initial_row", "type": "int", "value": "29"})
ET.SubElement(props_elem, "property", {"name": "music", "value": "LevelMod"})
ET.SubElement(props_elem, "property", {"name": "title", "value": "CANOPY RESCUE"})
ET.SubElement(props_elem, "property", {"name": "sub_title", "value": "RESCUE ALL 6 ANIMAL FRIENDS"})

# 4 Modular Tilesets:
ET.SubElement(root, "tileset", {"firstgid": "1",   "source": "../graphics/tiles/AmigaGameEngine.tsx"})
ET.SubElement(root, "tileset", {"firstgid": "177", "source": "../graphics/enemies/Enemies.tsx"})
ET.SubElement(root, "tileset", {"firstgid": "209", "source": "../graphics/animals/Friends.tsx"})
ET.SubElement(root, "tileset", {"firstgid": "221", "source": "../graphics/sprites/Player.tsx"})

def add_tile_layer(layer_id, name, grid, visible="1"):
    layer = ET.SubElement(root, "layer", {
        "id": str(layer_id),
        "name": name,
        "width": str(WIDTH),
        "height": str(HEIGHT),
        "visible": str(visible)
    })
    data = ET.SubElement(layer, "data", {"encoding": "csv"})
    lines = []
    for r in range(HEIGHT):
        row_vals = [str(grid[r * WIDTH + c]) for c in range(WIDTH)]
        lines.append(",".join(row_vals))
    data.text = "\n" + ",\n".join(lines) + "\n"

# 6 Dedicated Tile Layers:
add_tile_layer(1, "scenery", scenery_grid)
add_tile_layer(2, "platforms", platforms_grid)
add_tile_layer(3, "ladders", ladders_grid)
add_tile_layer(4, "entities", entities_grid)
add_tile_layer(5, "foreground", foreground_grid)
add_tile_layer(6, "water", water_grid, visible="0")

# Save TMX
xml_str = ET.tostring(root, encoding="utf-8")
dom = minidom.parseString(xml_str)
pretty_xml = dom.toprettyxml(indent=" ")

lines = [l for l in pretty_xml.split("\n") if l.strip()]
final_xml = "\n".join(lines)

with open("assets/Levels/Level_01.tmx", "w", encoding="utf-8") as f:
    f.write(final_xml)

print("Saved pure-tile assets/Levels/Level_01.tmx successfully!")


# =============================================================================
# 3. RENDER VISUAL PREVIEW IMAGE
# =============================================================================
tileset_img = Image.open("assets/graphics/tiles/four-seasons-tileset.png").convert("RGBA")
enemies_img = Image.open("assets/graphics/enemies/enemies_16x16.png").convert("RGBA")
friends_img = Image.open("assets/graphics/animals/animals_16x16.png").convert("RGBA")
player_img  = Image.open("assets/graphics/sprites/player_idle_64x16.png").convert("RGBA")

canvas = Image.new("RGBA", (WIDTH * 16, HEIGHT * 16), (20, 24, 34, 255))

for r in range(HEIGHT):
    for c in range(WIDTH):
        # 1. Scenery
        sc_val = scenery_grid[r * WIDTH + c]
        if sc_val > 0:
            tid = sc_val - 1
            t = tileset_img.crop(((tid % 11) * 16, (tid // 11) * 16, (tid % 11) * 16 + 16, (tid // 11) * 16 + 16))
            canvas.paste(t, (c * 16, r * 16), t)

        # 2. Platforms
        pl_val = platforms_grid[r * WIDTH + c]
        if pl_val > 0:
            tid = pl_val - 1
            t = tileset_img.crop(((tid % 11) * 16, (tid // 11) * 16, (tid % 11) * 16 + 16, (tid // 11) * 16 + 16))
            canvas.paste(t, (c * 16, r * 16), t)

        # 3. Ladders
        ld_val = ladders_grid[r * WIDTH + c]
        if ld_val > 0:
            tid = ld_val - 1
            t = tileset_img.crop(((tid % 11) * 16, (tid // 11) * 16, (tid % 11) * 16 + 16, (tid // 11) * 16 + 16))
            canvas.paste(t, (c * 16, r * 16), t)

        # 4. Water
        wt_val = water_grid[r * WIDTH + c]
        if wt_val > 0:
            tid = wt_val - 1
            t = tileset_img.crop(((tid % 11) * 16, (tid // 11) * 16, (tid % 11) * 16 + 16, (tid // 11) * 16 + 16))
            canvas.paste(t, (c * 16, r * 16), t)

        # 5. Foreground
        fg_val = foreground_grid[r * WIDTH + c]
        if fg_val > 0:
            tid = fg_val - 1
            t = tileset_img.crop(((tid % 11) * 16, (tid // 11) * 16, (tid % 11) * 16 + 16, (tid // 11) * 16 + 16))
            canvas.paste(t, (c * 16, r * 16), t)

        # 6. Entities
        en_val = entities_grid[r * WIDTH + c]
        if en_val > 0:
            if en_val >= 221: # Player
                t = player_img.crop((0, 0, 16, 16))
                canvas.paste(t, (c * 16, r * 16), t)
            elif en_val >= 209: # Friends
                fid = en_val - 209
                fc = fid % 4
                fr = fid // 4
                t = friends_img.crop((fc * 16, fr * 16, fc * 16 + 16, fr * 16 + 16))
                canvas.paste(t, (c * 16, r * 16), t)
            elif en_val >= 177: # Enemies
                eid = en_val - 177
                ec = eid % 4
                er = eid // 4
                t = enemies_img.crop((ec * 16, er * 16, ec * 16 + 16, er * 16 + 16))
                canvas.paste(t, (c * 16, r * 16), t)
            elif en_val == 38: # Crate
                tid = 37
                t = tileset_img.crop(((tid % 11) * 16, (tid // 11) * 16, (tid % 11) * 16 + 16, (tid // 11) * 16 + 16))
                canvas.paste(t, (c * 16, r * 16), t)

canvas.save("scratch/level_01_new_preview.png")
print("Saved preview image: scratch/level_01_new_preview.png")
