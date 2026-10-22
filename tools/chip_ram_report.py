#!/usr/bin/env python3
"""
chip_ram_report.py — Amiga Chip RAM and Fast RAM usage summary.

Run from the repo root:
    python tools/chip_ram_report.py

Reads actual incbin file sizes from disk.
BSS allocations use exact constants that match const.asm / main.asm.
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
# data_chip — static assets linked into Chip RAM via incbin (section data_chip)
#
# Order matches main.asm exactly.
# ---------------------------------------------------------------------------

DATA_CHIP = [
    # (label, path-or-None, fallback-bytes, note)

    # --- Hardware sprites & copper lists (copperlists.asm) ---
    ("HUD Hardware Sprites",     None,                                                  1_612, "SpriteLives, SpriteFriends, SpriteOxygen, SpriteBubble, SpriteOxygenKit"),
    ("Copper lists bytecode",    None,                                                  7_088, "cpGame, cpLoading, cpLevelComplete, cpTitle, cpGameComplete, cpGameOver, cpFlash"),
    ("FontData",                 "assets/font/font.bin",                                  768, "8x8 font glyphs"),

    # --- Gameplay music module (Paula DMA) ---
    ("LevelMod",                 "assets/music/xlr8.mod",                              47_302, "in-game music module"),
    ("GameCompleteMod",          "assets/music/10kdub.mod",                            10_166, "game complete victory music module"),

    # --- In-game sound effects (gamesfx.asm) ---
    ("Sfx structures (11x12B)",  None,                                                    132, "11 SFX descriptor headers"),
    ("SfxCane_Raw",              "assets/fx/sfx_cane.raw",                              1_546, "cane swing audio sample"),
    ("SfxCrateImpact_Raw",       "assets/fx/sfx_crate_impact.raw",                      1_986, "crate land audio sample"),
    ("SfxEnemyStun_Raw",         "assets/fx/sfx_enemy_stun.raw",                        2_648, "enemy stun sparkle audio sample"),
    ("SfxDuckRescue_Raw",        "assets/fx/sfx_duck_rescue.raw",                       2_868, "duckling rescue chime audio sample"),
    ("SfxOxygen_Raw",            "assets/fx/sfx_oxygen.raw",                            2_428, "oxygen refill audio sample"),
    ("SfxCratePush_Raw",         "assets/fx/sfx_crate_push.raw",                        1_656, "crate push friction audio sample"),
    ("SfxPlayerDie_Raw",         "assets/fx/sfx_player_die.raw",                        9_704, "death jingle audio sample"),
    ("SfxAirBubble_Raw",         "assets/fx/sfx_air_bubble.raw",                          994, "ambient bubble pop audio sample"),
    ("SfxLevelComplete_Raw",     "assets/fx/sfx_level_complete.raw",                   13_784, "level victory fanfare audio sample"),
    ("SfxGameOver_Raw",          "assets/fx/sfx_game_over.raw",                        27_564, "game over music fanfare audio sample"),
    ("SfxRewind_Raw",            "assets/fx/sfx_rewind.raw",                            6_618, "VHS rewind audio sample"),

    # --- Gameplay graphics & sprites ---
    ("GameTilesRaw",             "assets/graphics/tiles/tileset-compact_176x80.raw",    7_072, "176x80, 5 planes interleaved"),
    ("GameTilesMsk",             "assets/graphics/tiles/tileset-compact_176x80.msk",    7_040, "1-plane blitter mask"),
    ("EnemySpritesRaw",          "assets/graphics/enemies/enemies_64x48.raw",           1_536, "64x48, 4 planes interleaved"),
    ("EnemySpritesWhiteRaw",     "assets/graphics/enemies/enemies_64x48_white.raw",     1_536, "flash/stun mask"),
    ("EnemySpritesMsk",          "assets/graphics/enemies/enemies_64x48.msk",           1_536, "1-plane blitter mask"),
    ("DizzyStarsRaw",            "assets/graphics/enemies/dizzy_stars_64x16.raw",         512, "64x16, 4 planes"),
    ("DizzyStarsMsk",            "assets/graphics/enemies/dizzy_stars_64x16.msk",         512, "1-plane mask"),
    ("AnimalSpritesRaw",         "assets/graphics/animals/animals_64x48.raw",           1_536, "64x48, 4 planes"),
    ("AnimalSpritesMsk",         "assets/graphics/animals/animals_64x48.msk",           1_536, "1-plane mask"),
    ("PlayerRightRaw",           "assets/graphics/player/player_bobs_female_128x144.raw", 9_216, "24 frames, 4 planes (Mia right-facing)"),
    ("PlayerRightMsk",           "assets/graphics/player/player_bobs_female_128x144.msk", 9_216, "1-plane blitter mask (Mia right-facing)"),
    ("PlayerRightWhiteRaw",      "assets/graphics/player/player_bobs_female_128x144_white.raw", 9_216, "flash/stun mask (Mia right-facing)"),
]

# ---------------------------------------------------------------------------
# mem_chip — BSS Chip RAM allocations (section mem_chip, bss_c)
# ---------------------------------------------------------------------------

LEVEL_SCREEN_SIZE      = 110_080   # 688 lines x 160 bytes (4-plane interleaved)
PLAYER_BOB_TOTAL_BYTES = 9_216     # 24 frames x 384 bytes

MEM_CHIP_BSS = [
    ("NullSprite",          8,                      "2 longwords (hardware sprite terminator)"),
    ("DisplayScreen",       LEVEL_SCREEN_SIZE,      "688 scanlines x 160 bytes (active rendering buffer)"),
    ("NonDisplayScreen",    LEVEL_SCREEN_SIZE,      "688 scanlines x 160 bytes (clean background buffer)"),
    ("PlayerLeftRaw",       PLAYER_BOB_TOTAL_BYTES, "boot-generated flipped player frames"),
    ("PlayerLeftMsk",       PLAYER_BOB_TOTAL_BYTES, "boot-generated flipped player masks"),
    ("PlayerLeftWhiteRaw",  PLAYER_BOB_TOTAL_BYTES, "boot-generated flipped player white silhouettes"),
    ("ScreenMemEnd",        200,                    "guard sentinel"),
]

# ---------------------------------------------------------------------------
# data_fast — assets in Fast RAM (section data_fast, data)
# ---------------------------------------------------------------------------

DATA_FAST = [
    ("Quadratic table",          "assets/data/quadratic.bin",                            4_096, "precomputed fall ease table"),
    ("Sinus table",              "assets/data/sin.bin",                                  4_096, "precomputed sine table"),
    ("PlayerPal",                "assets/graphics/player/player.pal",                     64, "HUD & bubble sprite palette"),
    ("CopperSkyTable",           "assets/graphics/copper/copper_sky.bin",                1_024, "copper sky gradient lines"),
    ("Level 1-6 definitions",    None,                                                  25_542, "6 TMX tilemaps, patrol paths, entity metadata"),
    ("Michroma font",            None,                                                  13_928, "Michroma proportional placard font & character maps"),
    ("LoadingPal",               "assets/graphics/title/template.pal",                       64, "ZX loading screen palette"),
    ("LoadingRawZ (ZX0)",        "assets/graphics/title/template.zx0",                    18_051, "compressed ZX loading screen"),
    ("ZxAudioDataLoad",          "assets/fx/zx_audio_data.wav",                          10_480, "ZX tape-load SFX (8-bit PCM)"),
    ("ZxAudioColorLoad",         "assets/fx/zx_audio_colors.wav",                         9_552, "ZX colour-wash SFX (8-bit PCM)"),
    ("ZxAudioScreenName",        "assets/fx/zx_audio_screenname.wav",                    26_936, "ZX screenname intro SFX (8-bit PCM)"),
    # --- Offloaded assets (staged into NonDisplayScreen at runtime) ---
    ("TitleLogoRaw",             "assets/graphics/title/AGE_title.raw",                  6_912, "intro splash logo (staged to Chip RAM)"),
    ("TitleLogoPal",             "assets/graphics/title/AGE_title.pal",                     16, "intro splash palette (staged to Chip RAM)"),
    ("SfxIntroFanfare",          None,                                                      12, "intro fanfare SFX structure"),
    ("SfxIntroFanfare_Raw",      "assets/fx/sfx_intro_fanfare.raw",                     16_540, "intro fanfare PCM sample (staged to Chip RAM)"),
    ("TitleDuckRaw",             "assets/graphics/title/duck_rescue_title.raw",          9_216, "menu title banner (staged to Chip RAM)"),
    ("TitleDuckPal",             "assets/graphics/title/duck_rescue_title.pal",             32, "menu title banner palette"),
    ("GCDucklingRaw",            "assets/graphics/title/duckling_complete.raw",          3_072, "game complete duckling (staged to Chip RAM)"),
    ("HeadshotMiaRaw",           "assets/graphics/headshots/headshot_mia_128x64.raw",    5_120, "Mia headshots (staged to Chip RAM)"),
    ("HeadshotMiaPal",           "assets/graphics/headshots/headshot_mia.pal",             64, "Mia portrait palette"),
    ("TitleScreenMusicMod",      "assets/music/heatwave_cruise.mod",                   46_414, "title music module (staged to Chip RAM)"),
]

# ---------------------------------------------------------------------------
# mem_fast — BSS Fast RAM allocations (section mem_fast, bss)
# ---------------------------------------------------------------------------

MEM_FAST = [
    ("VHS State & Backup Buffers", 3_760, "VHS rewind state variables & scanline restore buffers"),
    ("Variables",               18_844,  "Variables_sizeof global state block (a5)"),
    ("Keys",                    256,     "256 scan-codes keyboard buffer"),
    ("SnapshotBuffer",          31_056,  "Undo rewind snapshot ring buffer"),
    ("GameStack",               4_096,   "dedicated game stack"),
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
        "data_chip — static incbin assets in Chip RAM",
        DATA_CHIP)

    chip_bss, _ = section(
        "mem_chip BSS — dynamic Chip RAM allocations",
        [(l, s, n) for l, s, n in MEM_CHIP_BSS],
        path_col=False)

    fast_data, miss2 = section(
        "data_fast — static assets in Fast RAM",
        DATA_FAST)

    fast_bss, _ = section(
        "mem_fast BSS — dynamic Fast RAM allocations",
        [(l, s, n) for l, s, n in MEM_FAST],
        path_col=False)

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
    print(f"  {'mem_fast BSS':<32}{fmt(fast_bss)} bytes")
    print(sep)
    print(f"  {'TOTAL FAST RAM':<32}{fmt(total_fast)} bytes  ({total_fast/1024:.1f} KB)")
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
