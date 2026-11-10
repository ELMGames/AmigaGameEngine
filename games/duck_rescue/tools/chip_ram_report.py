#!/usr/bin/env python3
"""
chip_ram_report.py — Amiga Chip RAM and Fast RAM usage summary.

Run from the repo root:
    python tools/chip_ram_report.py

Reads actual incbin file sizes from disk.
BSS allocations use exact constants that match const.asm / main.asm.
"""

import os
import re

CHIP_RAM_LIMIT = 524_288  # 512 KB
REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))  # games/duck_rescue
GIT_ROOT = os.path.normpath(os.path.join(REPO_ROOT, "..", ".."))            # repo root (where build.py runs from)
MAIN_ASM = os.path.join(REPO_ROOT, "main.asm")

INCBIN_RE = re.compile(r'incbin\s+"([^"]+)"', re.IGNORECASE)
INCLUDE_RE = re.compile(r'^\s*include\s+"([^"]+)"', re.IGNORECASE | re.MULTILINE)
INCDIR_RE = re.compile(r'^\s*INCDIR\s+"([^"]+)"', re.IGNORECASE | re.MULTILINE)


def fsize(rel_path):
    full = os.path.join(REPO_ROOT, rel_path)
    return os.path.getsize(full) if os.path.isfile(full) else None


def _resolve_include(name, current_dir, incdirs):
    """Mimic vasm's include/incbin search order: the including file's own
    directory first, then each INCDIR in the order main.asm declares them."""
    candidates = [os.path.join(current_dir, name)] + [os.path.join(d, name) for d in incdirs]
    for c in candidates:
        if os.path.isfile(c):
            return c
    return None


def main_asm_incbin_paths():
    """
    Every asset path incbinned anywhere in main.asm's actual build —
    following `include` directives recursively through engine/ and the
    game's own include tree, the same way vasm assembles it — rather than
    just main.asm's own text (most incbins actually live in included files
    like game_sfx.asm, not main.asm itself).

    Used to cross-check DATA_CHIP/DATA_FAST below instead of trusting that
    this hand-maintained list still matches the real build: if a file adds,
    drops, or renames an incbin, report() flags the drift instead of
    silently reporting stale numbers.

    Returns None if main.asm can't be found (report() then skips the check).
    """
    if not os.path.isfile(MAIN_ASM):
        return None

    with open(MAIN_ASM, encoding="utf-8") as f:
        main_text = f.read()
    incdirs = [os.path.normpath(os.path.join(GIT_ROOT, d)) for d in INCDIR_RE.findall(main_text)]

    incbins = []
    visited = set()

    def visit(path):
        real = os.path.normpath(path)
        if real in visited or not os.path.isfile(real):
            return
        visited.add(real)
        with open(real, encoding="utf-8", errors="replace") as f:
            text = f.read()
        incbins.extend(INCBIN_RE.findall(text))
        current_dir = os.path.dirname(real)
        for inc_name in INCLUDE_RE.findall(text):
            resolved = _resolve_include(inc_name, current_dir, incdirs)
            if resolved:
                visit(resolved)

    visit(MAIN_ASM)
    return incbins


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

    # --- In-game sound effects (game_sfx.asm) ---
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
    ("SfxRewind_Raw",            "assets/fx/sfx_rewind.raw",                            6_618, "VHS rewind audio sample"),

    # --- Gameplay graphics & sprites ---
    ("GameTilesRaw",             "assets/graphics/tiles/tileset-compact_176x80.raw",    7_072, "176x80, 4 planes interleaved + 32-byte palette"),
    ("GameTilesMsk",             "assets/graphics/tiles/tileset-compact_176x80.msk",    7_040, "4-plane cookie-cut mask"),
    ("EnemySpritesRaw",          "assets/graphics/enemies/enemies_64x48.raw",           1_536, "64x48, 4 planes interleaved"),
    ("EnemySpritesWhiteRaw",     "assets/graphics/enemies/enemies_64x48_white.raw",     1_536, "white flash silhouette"),
    ("EnemySpritesMsk",          "assets/graphics/enemies/enemies_64x48.msk",           1_536, "4-plane cookie-cut mask"),
    ("DizzyStarsRaw",            "assets/graphics/enemies/dizzy_stars_64x16.raw",         512, "64x16, 4 planes"),
    ("DizzyStarsMsk",            "assets/graphics/enemies/dizzy_stars_64x16.msk",         512, "4-plane cookie-cut mask"),
    ("AnimalSpritesRaw",         "assets/graphics/animals/animals_64x48.raw",           1_536, "64x48, 4 planes"),
    ("AnimalSpritesMsk",         "assets/graphics/animals/animals_64x48.msk",           1_536, "4-plane cookie-cut mask"),
    ("SmokeSpritesRaw",          "assets/graphics/effects/smoke_64x32.raw",            1_024, "64x32, 4 planes"),
    ("SmokeSpritesMsk",          "assets/graphics/effects/smoke_64x32.msk",            1_024, "4-plane cookie-cut mask"),
    ("PlayerRightRaw",           "assets/graphics/player/player_bobs_female_128x144.raw", 9_216, "24 frames, 4 planes (Mia right-facing)"),
    ("PlayerRightMsk",           "assets/graphics/player/player_bobs_female_128x144.msk", 9_216, "4-plane cookie-cut mask (Mia right-facing)"),
    ("PlayerRightWhiteRaw",      "assets/graphics/player/player_bobs_female_128x144_white.raw", 9_216, "white flash silhouette (Mia right-facing)"),
]

# ---------------------------------------------------------------------------
# mem_chip — BSS Chip RAM allocations (section mem_chip, bss_c)
# ---------------------------------------------------------------------------

LEVEL_SCREEN_SIZE      = 81_920    # 512 lines x 160 bytes (32-row ring buffer: 16 primary + 16 mirror rows)
PLAYER_BOB_TOTAL_BYTES = 9_216     # 24 frames x 384 bytes

MEM_CHIP_BSS = [
    ("NullSprite",          8,                      "2 longwords (hardware sprite terminator)"),
    ("DisplayScreen",       LEVEL_SCREEN_SIZE,      "512 scanlines x 160 bytes (32-row ring buffer, active rendering)"),
    ("NonDisplayScreen",    LEVEL_SCREEN_SIZE,      "512 scanlines x 160 bytes (32-row ring buffer, clean background)"),
    ("PlayerLeftRaw",       PLAYER_BOB_TOTAL_BYTES, "boot-generated flipped player frames"),
    ("PlayerLeftMsk",       PLAYER_BOB_TOTAL_BYTES, "boot-generated flipped player masks"),
    ("PlayerLeftWhiteRaw",  PLAYER_BOB_TOTAL_BYTES, "boot-generated flipped player white silhouettes"),
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
    ("LoadingPal",               "assets/graphics/title/loadingscreen.pal",                       64, "ZX loading screen palette"),
    ("LoadingRawZ (ZX0)",        "assets/graphics/title/loadingscreen.zx0",                    18_051, "compressed ZX loading screen"),
    ("ZxAudioDataLoad",          "assets/fx/zx_audio_data.raw",                          10_480, "ZX tape-load SFX (8-bit PCM)"),
    ("ZxAudioColorLoad",         "assets/fx/zx_audio_colors.raw",                         9_434, "ZX colour-wash SFX (8-bit PCM)"),
    ("ZxAudioHeader",            "assets/fx/zx_audio_header.raw",                           800, "ZX header data burst SFX (8-bit PCM)"),
    ("ZxAudioPilot",             "assets/fx/zx_audio_pilot.raw",                            382, "ZX pilot tone loop SFX (8-bit PCM)"),
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
    ("GameCompleteMod",          "assets/music/10kdub.mod",                            10_166, "game complete music module (staged to Chip RAM)"),
    ("SfxGameOver_Raw",          "assets/fx/sfx_game_over.raw",                        27_564, "game over fanfare (staged to Chip RAM)"),
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
        "Chip data — data_chip, chip_audio, chip_sfx, chip_gfx",
        DATA_CHIP)

    chip_bss, _ = section(
        "Chip BSS — mem_chip, chip_display, chip_backdrop",
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

    drift_warnings = check_incbin_drift()
    if drift_warnings:
        print()
        print("  Warning — this report has drifted from main.asm's incbin list:")
        for w in drift_warnings:
            print(f"    {w}")
    print()


#   "Level 1-6 definitions" (DATA_FAST) deliberately rolls up dozens of
#   per-level .map/.bin files into one estimated-size summary line instead
#   of itemizing each; the drift check treats any real incbin under these
#   prefixes as covered by that rollup rather than flagging it as missing.
AGGREGATE_PREFIXES = ("assets/levels/",)


def check_incbin_drift():
    """
    Compare this report's declared incbin paths (DATA_CHIP + DATA_FAST
    entries with a path, not the computed/BSS entries) against what
    main.asm actually incbins. Returns a list of human-readable warnings,
    empty if main.asm couldn't be found or everything matches.
    """
    actual = main_asm_incbin_paths()
    if actual is None:
        return [f"could not read {MAIN_ASM} — skipped verification"]

    actual_set = set(actual)
    declared = {row[1] for row in (DATA_CHIP + DATA_FAST) if row[1] is not None}

    warnings = []
    missing_from_report = sorted(actual_set - declared)
    extra_in_report = sorted(declared - actual_set)
    for p in missing_from_report:
        if p.startswith(AGGREGATE_PREFIXES):
            continue
        warnings.append(f"main.asm incbins '{p}' but it's not listed here")
    for p in extra_in_report:
        warnings.append(f"listed here as '{p}' but main.asm no longer incbins it")
    return warnings


if __name__ == "__main__":
    from tool_cli import run_tool
    run_tool(report, __doc__)
