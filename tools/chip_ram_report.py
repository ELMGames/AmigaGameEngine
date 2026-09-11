#!/usr/bin/env python3
"""
chip_ram_report.py — Amiga Chip RAM usage summary for Millie & Molly.

Run from the repo root:
    python tools/chip_ram_report.py

Reads actual incbin file sizes from disk.
BSS allocations use hardcoded constants that must match const.asm / main.asm.
"""

import os

CHIP_RAM_LIMIT = 524_288  # 512 KB
REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))


def fsize(rel_path):
    full = os.path.join(REPO_ROOT, rel_path)
    return os.path.getsize(full) if os.path.isfile(full) else None


def fmt(n):
    return f"{n:>10,}"


# ---------------------------------------------------------------------------
# data_chip — static assets linked into chip RAM via incbin (section data_chip)
#
# Order matches main.asm / copperlists.asm exactly.
# Copper list bytecode is estimated (no separate file to measure).
# ---------------------------------------------------------------------------

DATA_CHIP = [
    # (label, path-or-None, fallback-bytes, note)

    # --- copperlists.asm (included first inside data_chip) ---
    ("Copper list bytecode",     None,
     3_000,  "estimated (inline dc.w/dc.l)"),
    ("Font",                     "assets/font/font.bin",
     768,    ""),

    # ActorSprites removed (was 26,400 bytes)
    ("Shadows",                  "assets/graphics/shadows/shadows.bin",
     576,    ""),
    ("LevelFont",                "assets/font/levelfont.bin",
     400,    ""),
    ("LoadingRawZ (ZX0)",        "assets/graphics/title/336x200/millie_molly_336x200.zx0",
     26_420, "compressed from 42,000 bytes raw"),
    ("LoadingPal",               "assets/graphics/title/336x200/millie_molly_336x200.pal",
     64,     ""),
    ("Button0Raw",               "assets/graphics/ui/ui_0.bin",
     380,    ""),
    ("Button1Raw",               "assets/graphics/ui/ui_1.bin",
     380,    ""),
    ("Button2Raw",               "assets/graphics/ui/ui_2.bin",
     380,    ""),
    ("Button3Raw",               "assets/graphics/ui/ui_3.bin",
     380,    ""),
    ("Star32",                   "assets/graphics/star/star32.raw",
     128,    ""),
    ("LogoMaskRaw",              "assets/graphics/logo/logo_mask.raw",
     2_464,  ""),
    ("LogoOutlineRaw",           "assets/graphics/logo/logo_outline.raw",
     2_464,  ""),
    ("TitleStar16Raw",           "assets/graphics/star/star16.raw",
     32,     ""),
    ("LevelMod",                 "assets/music/millie_&_molly.mod",
     6_460,  ""),
    ("TitleScreenMusicMod",      "assets/music/playingw.mod",
     25_398, "title screen music (safe from overlay reuse)"),
    ("ZxAudioDataLoad",          "assets/fx/zx_audio_data.wav",
     10_480, "ZX tape-load SFX (loading screen only, overlay region)"),
    ("ZxAudioColorLoad",         "assets/fx/zx_audio_colors.wav",
     9_552,  "ZX colour-wash SFX (loading screen only, overlay region)"),
    ("ZxAudioScreenName",        "assets/fx/zx_audio_screenname.wav",
     26_936, "ZX screenname intro SFX (loading screen only, overlay region)"),
]

# ---------------------------------------------------------------------------
# data_fast — assets in Fast RAM; NOT counted toward 512 KB chip limit.
# Covers two sections:
#   data_overlay_src  ZX0-compressed sources decompressed into chip overlay
#                     post-loading by CopyOverlayAssets.
#   (code section)    palettes, tables, level data, SFX structures, etc.
# ---------------------------------------------------------------------------

DATA_FAST = [
    # --- data_overlay_src: ZX0-compressed; decompressed into chip overlay ---
    ("PlayerHWSprites_FastMem (ZX0)", "assets/graphics/sprites/player_hwsprites.zx0",
     11_283, "decompresses to 39,936 bytes in overlay"),
    ("MillieFace_FastMem (ZX0)",      "assets/graphics/face/millie.zx0",
      2_316, "decompresses to 2,560 bytes in overlay"),
    ("MollyFace_FastMem (ZX0)",       "assets/graphics/face/molly.zx0",
      2_356, "decompresses to 2,560 bytes in overlay"),

    # --- code section: palettes, tables, level data, SFX structures ---
    ("Quartic table",            "assets/data/quartic.bin",          4_096, ""),
    ("Quadratic table",          "assets/data/quadratic.bin",        4_096, ""),
    ("Sinus table",              "assets/data/sin.bin",              4_096, ""),
    ("TileSet0.pak (ZX0)",       "assets/graphics/tiles/Tiles_0.pak",3_221, ""),
    ("TileSet1.pak (ZX0)",       "assets/graphics/tiles/Tiles_1.pak",2_697, ""),
    ("TileSet2.pak (ZX0)",       "assets/graphics/tiles/Tiles_2.pak",3_545, ""),
    ("TileSet3.pak (ZX0)",       "assets/graphics/tiles/Tiles_3.pak",4_270, ""),
    ("TileSet4.pak (ZX0)",       "assets/graphics/tiles/Tiles_4.pak",3_333, ""),
    ("SpritePal",                "assets/graphics/sprites/sprites.pal",  64, ""),
    ("TilesPal0-4",              None,                                   320, "5 x 64 bytes (estimated)"),
    ("LevelData",                "assets/levels/levels.bin",         8_800, ""),
    ("WallpaperBase",            None,                                   196, "14 bytes x 14 rows (estimated)"),
    ("LevelCountRaw (ui_4)",     "assets/graphics/ui/ui_4.bin",        570, ""),
]

# ---------------------------------------------------------------------------
# mem_chip — BSS chip RAM allocations (section mem_chip, bss_c)
#
# Constants from const.asm:
#   SCREEN_SIZE    = SCREEN_WIDTH_BYTE * SCREEN_HEIGHT * SCREEN_DEPTH
#                  = 42 * 216 * 5  = 45,360 bytes
#   TILE_SIZE      = (TILE_WIDTHF/8) * SCREEN_DEPTH * TILE_HEIGHT = 480 bytes
#   TILESET_SIZE   = 29 * 480       = 13,920 bytes
#   SPRITESET_SIZE = 55 * 480       = 26,400 bytes
# ---------------------------------------------------------------------------

SCREEN_SIZE    = 42 * 216 * 5     # 45,360
TILESET_SIZE   = 29 * 480         # 13,920
SPRITESET_SIZE = 55 * 480         # 26,400

REALSPRITES_SIZE  = 96 * 416   # REALSPRITES_FRAMES * HW_FRAME_SIZE = 39,936
FACE_SIZE         = 2_560

# BSS chip allocations that add to chip RAM beyond DATA_CHIP.
MEM_CHIP_BSS = [
    ("NullSprite",        8,                "2 longwords (hardware sprite terminator)"),
    ("ButtonMaskTemp",    570,              "composited button UI working buffer"),
    ("LevelCountTemp",    570,              "composited level counter working buffer"),
    # ("SpriteMaskScratch", 480,              "one tile (TILE_SIZE), computed on-the-fly by DrawSprite"), - removed
    # ("FrozenPlayerMask",  480,              "one tile (TILE_SIZE), pre-computed per frozen pose change"), - removed
    ("DisplayScreen",     SCREEN_SIZE,      "42 x 216 x 5 planes"),
    ("NonDisplayScreen",  SCREEN_SIZE,      "42 x 216 x 5 planes"),
    ("ScreenMemEnd",      200,              "guard sentinel"),
]

# Overlay region post-loading layout — informational only, NOT added to chip total.
# This chip RAM is already counted in DATA_CHIP via the ZxAudio/LoadingPal/LoadingRawZ
# entries (73,452 bytes).  After loading those are overwritten with the entries below.
MEM_CHIP_OVERLAY = [
    ("TileSet",           TILESET_SIZE,     "overlay offset      0; overwritten each level load"),
    ("TileMask",          TILESET_SIZE,     "overlay offset 13,920; overwritten each level load"),
    ("PlayerHWSprites",   REALSPRITES_SIZE, "overlay offset 27,840; decompressed by CopyOverlayAssets"),
    ("MillieFace",        FACE_SIZE,        "overlay offset 67,776; decompressed by CopyOverlayAssets"),
    ("MollyFace",         FACE_SIZE,        "overlay offset 70,336; decompressed by CopyOverlayAssets"),
    ("(headroom)",        556,              "overlay offset 72,896; unused"),
]

# ---------------------------------------------------------------------------
# mem_fast — BSS fast RAM (section mem_fast, bss); NOT counted toward 512 KB
# ---------------------------------------------------------------------------

MEM_FAST = [
    ("Variables",   None,  "Variables_sizeof (exact size runtime-dependent)"),
    ("Keys",        456,   "256 scan-codes + 200 bytes padding"),
]


def section(title, rows, path_col=True, show_total=True):
    sep = "-" * 66
    print()
    print(f"=== {title} ===")
    print(sep)
    total = 0
    missing = []
    for row in rows:
        label = row[0]
        if path_col:
            path, fallback, note = row[1], row[2], row[3]
            if path is not None:
                s = fsize(path)
                if s is not None:
                    size, tag = s, ""
                else:
                    size, tag = fallback, " (estimated — file not found)"
                    missing.append(path)
            else:
                size, tag = fallback, " (estimated)"
        else:
            size, note = row[1], row[2]
            tag = ""
        note_str = (f"  {note}" if note else "") + tag
        print(f"  {label:<28}{fmt(size)} bytes{note_str}")
        total += size
    if show_total:
        print(sep)
        print(f"  {'SUBTOTAL':<28}{fmt(total)} bytes")
    return total, missing


def report():
    chip_data, miss1 = section(
        "data_chip — incbin assets in Chip RAM",
        DATA_CHIP)

    chip_bss, _ = section(
        "mem_chip BSS — additional Chip RAM allocations",
        [(l, s, n) for l, s, n in MEM_CHIP_BSS],
        path_col=False)

    section(
        "mem_chip overlay — post-loading layout [informational, not counted]",
        [(l, s, n) for l, s, n in MEM_CHIP_OVERLAY],
        path_col=False,
        show_total=False)

    fast_data, miss2 = section(
        "data_overlay_src + data_fast — incbin assets in Fast RAM",
        DATA_FAST)

    fast_bss = 456  # Keys (256 + 200 padding); Variables_sizeof excluded (runtime)
    print()
    print(f"  mem_fast BSS: Keys {fast_bss} bytes + Variables_sizeof (runtime-dependent, not counted)")

    total_chip = chip_data + chip_bss
    total_fast = fast_data + fast_bss
    chip_headroom = CHIP_RAM_LIMIT - total_chip

    sep = "-" * 66
    print()
    print("=== Summary ===")
    print(sep)
    print(f"  {'data_chip (static incbins)':<32}{fmt(chip_data)} bytes")
    print(f"  {'mem_chip BSS':<32}{fmt(chip_bss)} bytes")
    print(sep)
    print(f"  {'TOTAL CHIP RAM':<32}{fmt(total_chip)} bytes  ({total_chip/1024:.1f} KB)")
    print(f"  {'512 KB limit':<32}{fmt(CHIP_RAM_LIMIT)} bytes")
    if chip_headroom >= 0:
        print(f"  {'Chip headroom':<32}{fmt(chip_headroom)} bytes  ({chip_headroom/1024:.1f} KB free)")
    else:
        print(f"  {'OVER CHIP LIMIT BY':<32}{fmt(-chip_headroom)} bytes  *** EXCEEDS 512 KB ***")
    print(sep)
    print(f"  {'data_fast incbins':<32}{fmt(fast_data)} bytes")
    print(f"  {'mem_fast BSS (Keys only)':<32}{fmt(fast_bss)} bytes")
    print(sep)
    print(f"  {'TOTAL FAST RAM (minimum)':<32}{fmt(total_fast)} bytes  ({total_fast/1024:.1f} KB)")
    print(sep)

    all_missing = miss1 + miss2
    if all_missing:
        print()
        print("  Warning — files not found (fallback sizes used):")
        for p in all_missing:
            print(f"    {p}")
    print()


if __name__ == "__main__":
    report()
