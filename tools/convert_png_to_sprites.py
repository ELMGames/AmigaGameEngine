import struct
from PIL import Image

SRC  = "assets/original/16bit_sprites_new.png"
DST  = "assets/graphics/sprites/sprites_new.bin"

TILE_W, TILE_H = 24, 24
GRID_COLS, GRID_ROWS, PLANES = 12, 12, 5

# Compact tile index list — only the tiles actually referenced by the code.
# Order defines the new sprite sheet index (position 0, 1, 2, ...).
# See const.asm SPRITE_xxx constants for the new indices after compaction.
#
# Tiles 0-28   : game objects (walls, ladders, enemies, push block, background)
# Tiles 29-30  : Molly frozen standing (right, left)    [old 46-47]
# Tiles 31-32  : Millie frozen standing (right, left)   [old 94-95]
# Tiles 33-34  : ladder freeze frames (Molly=33, Millie=34) [old 96-97]
# Tiles 35-38  : landing impact smoke A-D               [old 98-101]
# Tiles 39-45  : dirt-break crumble A-G                 [old 108-114]
# Tiles 46-52  : enemy death cloud A-G                  [old 132-138]
# Tile  53     : trail star (small white)               [old 141]
# Tile  54     : intro star (large blue)                [old 143]
USED_TILES = (
    list(range(0, 29))   +   # 0-28  game objects
    [46, 47]             +   # 29-30 Molly frozen standing R/L
    [94, 95]             +   # 31-32 Millie frozen standing R/L
    [96, 97]             +   # 33-34 ladder freeze (Molly, Millie)
    list(range(98, 102)) +   # 35-38 smoke A-D
    list(range(108, 115))+   # 39-45 dirt A-G
    list(range(132, 139))+   # 46-52 cloud A-G
    [141, 143]               # 53-54 star small, star large
)

assert len(USED_TILES) == 55, f"Expected 55 tiles, got {len(USED_TILES)}"

img = Image.open(SRC)
assert img.mode == "P", "PNG must be indexed (palette mode, 8-bit)"
px = img.load()
out = bytearray()

for tile_idx in USED_TILES:
    gr = tile_idx // GRID_COLS
    gc = tile_idx  % GRID_COLS
    for y in range(TILE_H):
        for plane in range(PLANES):
            word = 0
            for x in range(TILE_W):
                idx = px[gc * TILE_W + x, gr * TILE_H + y]  # color index from PNG
                if idx != 0:
                    idx += 16  # sprites use upper colour registers (16-31); 0 stays transparent
                if (idx >> plane) & 1:
                    word |= (1 << (31 - x))   # pixel 0 → bit 31
            out += struct.pack(">I", word)

with open(DST, "wb") as f:
    f.write(out)
print(f"Written {len(out)} bytes ({len(USED_TILES)} tiles) -> {DST}")
