#!/usr/bin/env python3
"""
amiga_planar.py
----------------
Shared asset-conversion helpers for the Duck Rescue tools (convert_player_bob.py,
convert_enemies.py, convert_animals.py, export_level.py):

  - pack_row_planes / pack_white_row: pack chunky palette-index pixels into
    Amiga interleaved bitplane rows. Each of those scripts used to do this
    with its own hand-written copy of the same bit loop; this is the one
    place that encodes the row layout now.

  - load_palette_ocs: load the shared 16-colour OCS palette from a per-game
    JSON config instead of each script hardcoding its own copy of the same
    16 RGB tuples (see games/duck_rescue/game_palette.json).
"""

import json
from pathlib import Path
from typing import Sequence
from pathlib import Path
from typing import Sequence


def pack_row_planes(indices: Sequence[int], planes: int = 4) -> tuple[bytearray, bytearray]:
    """
    Pack one scanline of palette indices into interleaved bitplane bytes
    and a matching cookie-cut mask.

    indices: a sequence of palette indices (0 = transparent), one per pixel.
             len(indices) must be a multiple of 8.
    planes:  number of bitplanes (default 4, i.e. a 16-colour palette).

    Returns (raw_planes, mask), each a bytearray of planes*row_bytes, laid
    out plane-major (plane 0's row bytes, then plane 1's, ...), matching
    the Amiga's interleaved-bitplane scanline order. The mask's "solid"
    bit (source index != 0) is replicated identically into every plane's
    slice — not computed once per scanline — because the blitter consumes
    mask and graphic as one combined interleaved stream when cookie-cutting
    a multi-plane destination, so channel A's data must align plane-for-
    plane with channels B/C/D rather than being a single shared row.
    """
    width = len(indices)
    assert width % 8 == 0, f"row width must be a multiple of 8, got {width}"
    row_bytes = width // 8

    raw = bytearray(planes * row_bytes)
    mask = bytearray(planes * row_bytes)

    for x, idx in enumerate(indices):
        if not idx:
            continue
        bp = x // 8
        shift = 7 - (x % 8)
        for plane in range(planes):
            mask[plane * row_bytes + bp] |= (1 << shift)
            if (idx >> plane) & 1:
                raw[plane * row_bytes + bp] |= (1 << shift)

    return raw, mask


def pack_white_row(indices: Sequence[int], white_index: int = 3, planes: int = 4) -> bytearray:
    """
    Like pack_row_planes, but every solid pixel is forced to white_index
    (default 3 = pure white, $0FFF, in the engine's 16-colour OCS palette)
    and every transparent pixel stays 0. Used for the stun-flash / damage
    silhouette BOB variants. Returns only the raw_planes bytearray (the
    mask is identical to pack_row_planes' mask and is not needed again).
    """
    forced = [white_index if idx else 0 for idx in indices]
    raw, _ = pack_row_planes(forced, planes)
    return raw


def load_palette_ocs(config_path: str | Path) -> list[tuple[int, int, int]]:
    """
    Load a 16-colour OCS palette from a JSON config (see
    games/duck_rescue/game_palette.json for the schema: a "colors" list of
    {"index", "rgb4", "name"} objects). Returns a list of (r, g, b) 4-bit
    tuples ordered by index, suitable for direct use as PALETTE_OCS /
    DEFAULT_PALETTE_OCS in the asset converters.

    A new game should copy that JSON file, edit it to its own palette, and
    pass its path here instead of hardcoding a Python literal.
    """
    with open(config_path, encoding="utf-8") as f:
        data = json.load(f)
    colors = sorted(data["colors"], key=lambda c: c["index"])
    return [tuple(c["rgb4"]) for c in colors]
