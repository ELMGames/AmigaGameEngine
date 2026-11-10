;==============================================================================
; GAME ENGINE - AMIGA ASSEMBLY
; main.asm  -  Duck Rescue Entry Point and Asset Declaration
;==============================================================================
;
; This is the top-level assembly file for the Duck Rescue game built on the
; AmigaGameEngine framework.
;
; It:
;   1. Configures INCDIR paths for both the reusable engine/ and game includes.
;   2. Includes register/bit definitions, macros, variables, and game consts.
;   3. Incorporates the engine lifecycle framework (engine_main.asm).
;   4. Defines GameInitHook to bootstrap initial game state.
;   5. INCLUDEs all required engine and game subsystems.
;   6. Defines data and BSS sections for Fast RAM and Chip RAM.
;
; Global register conventions (held constant after Init):
;   a5 = Variables base pointer  (Fast RAM BSS block)
;   a6 = $dff000  CUSTOM chip base
;   a4 = Player structure pointer (lea Player(a5),a4)
;   a3 = current Actor  structure pointer (set by actor routines)
;
;==============================================================================

    ; Include directories (resolved from repo root or game folder)
    incdir     "games/duck_rescue"
    incdir     "games/duck_rescue/include"
    incdir     "games/duck_rescue/include/core"
    incdir     "games/duck_rescue/include/gameplay"
    incdir     "games/duck_rescue/include/graphics"
    incdir     "games/duck_rescue/include/levels"
    incdir     "engine"
    incdir     "engine/include"
    incdir     "engine/core"
    incdir     "engine/audio"
    incdir     "engine/gameplay"
    incdir     "engine/graphics"
    incdir     "engine/screens"
    incdir     "engine/system"
    incdir     "engine/effects"
    incdir     "engine/audio/ptplayer"

    ; Relative fallbacks if assembled with cwd = games/duck_rescue/
    incdir     "."
    incdir     "include"
    incdir     "include/core"
    incdir     "include/gameplay"
    incdir     "include/graphics"
    incdir     "include/levels"
    incdir     "../../engine"
    incdir     "../../engine/include"
    incdir     "../../engine/core"
    incdir     "../../engine/audio"
    incdir     "../../engine/gameplay"
    incdir     "../../engine/graphics"
    incdir     "../../engine/screens"
    incdir     "../../engine/system"
    incdir     "../../engine/effects"
    incdir     "../../engine/audio/ptplayer"

    include    "amiga_hw.i"

    include    "macros.asm"
    include    "variables.asm"

    include    "const.asm"
    include    "struct.asm"

;==============================================================================
; Code section
;==============================================================================

CUSTOM_LEVEL_PROBE = 1

;==============================================================================
; Engine Lifecycle Framework (AmigaGameEngine)
; Provides: Main, Restart, MainLoop, QuitToOS, EngineInit, SetRasterLogicColor
;==============================================================================

    include    "engine_main.asm"

;==============================================================================
; GameInitHook  -  Game-Specific Bootstrap Hook (called by EngineInit)
;
; In:       a5 = Variables base
; Out:      none
; Destroys: d0-d7, a0-a4 (via PlayerInitFlippedSprites)
;==============================================================================

GameInitHook:
    move.w     #0,LevelId(a5)
    move.w     #FLASH_SETUP,GameStatus(a5)
    clr.w      SlowMode(a5)
    clr.w      SlowModeHold(a5)
    clr.w      PrevKeyS(a5)
    clr.w      DebugOverlayActive(a5)
    clr.w      PrevDebugDrawn(a5)
    move.w     #DEFAULT_LIVES,PlayerLives(a5)
    lea        Keys,a0
    clr.b      KEY_S(a0)
    clr.b      KEY_A(a0)
    clr.b      KEY_D(a0)
    bsr        PlayerInitFlippedSprites ; pre-generate left-facing player BOBs in Chip RAM
    rts

;==============================================================================
; Subsystem includes
;
; All game subsystems are assembled as a single translation unit by INCLUDEing
; them here.  They share the same section (main,code) and can call each other
; directly without any linking step.
;==============================================================================

; --- System & Hardware Drivers (engine/) ---
    include    "system.asm"
    include    "keyboard.asm"
    include    "tools.asm"
    include    "controls.asm"
    include    "zx0_faster.asm"

; --- Graphics & Blitter Routines (engine/ & game) ---
    include    "screenutils.asm"
    include    "palette_fade.asm"
    include    "spritetools.asm"
    include    "hud_sprites.asm"
    include    "char_bltroutines.asm"
    include    "dirty_tiles.asm"
    include    "tmx_renderer.asm"
    include    "bob_compositor.asm"
    include    "entities.asm"
    include    "entity_bobs.asm"
    include    "landing_puff.asm"
    include    "copper_sky.asm"
    include    "debug_hud.asm"
    include    "bob_mirror.asm"
    include    "water_effects.asm"
    include    "hud_sprite_data.asm"  ; HUD sprite images (Chip RAM), before the engine bubble effect
    include    "bubble_sprite.asm"
    include    "pause_system.asm"
    include    "bigfont.asm"

; --- Core Gameplay & Entities (engine/ & game) ---
    include    "levelutils.asm"
    include    "actors.asm"
    include    "actor_physics.asm"
    include    "player_fsm.asm"
    include    "player_combat.asm"
    include    "player_water.asm"
    include    "undo.asm"
    include    "vhs_rewind.asm"
    include    "gamestatus.asm"
    include    "customlevel.asm"
    include    "game_hooks.asm"
    include    "instructions_text.asm"

; --- Game Screens & States (engine/) ---
    include    "loading.asm"
    include    "levelcomplete.asm"
    include    "titlescreen.asm"
    include    "instructions.asm"
    include    "credits.asm"
    include    "gamecomplete.asm"
    include    "gameover.asm"
    include    "flashscreen.asm"

; --- Audio Subsystems (engine/) ---
    include    "audio.asm"
    include    "game_audio.asm"
    include    "ptplayer.asm"

;==============================================================================
; Fast RAM data section  (data_fast)
;
; Read-only tables and asset data that do not need to be in Chip RAM.
; Fast RAM is significantly faster to access than Chip RAM on expanded Amigas,
; so lookup tables, level definitions, and palette data live here.
;
; Contents:
;   Quadratic / Sinus            - pre-computed easing / sine tables (binary)
;   PlayerPal / SpritePal        - hardware sprite / player palette (player.pal)
;   CopperSkyTable               - copper background gradient line tables
;   Level Definitions            - multi-layer TMX definitions (level_01_entities.asm..level_06_entities.asm)
;   LevelTable                   - pointer table pointing to each LevelDef
;   Michroma font                - proportional font data for placards/banners
;==============================================================================

    section    data_fast,data

;------------------------------------------------------------------------------
; Easing / animation tables  (pre-computed, accessed by index each frame)
;
; Quadratic- quadratic ease curve, used for crate push easing
; Sinus    - full-period sine table (SINE_ANGLES entries of signed 16-bit words)
;            SinusEnd marks the end so SINE_ANGLES can be derived at assemble time
; Both are built from assets/data/*.txt by tools/convert_data_tables.py.
;------------------------------------------------------------------------------

Quadratic:
    incbin     "assets/data/quadratic.bin"
Sinus:
    incbin     "assets/data/sin.bin"
SinusEnd:

;------------------------------------------------------------------------------
; Palettes (read by the CPU only — Fast RAM is fine)
;   PlayerPal / SpritePal - hardware sprite / player palette (COLOR16-31)
;------------------------------------------------------------------------------
PlayerPal:
SpritePal:
    incbin     "assets/graphics/player/player.pal"

CopperSkyTable:
    incbin     "assets/graphics/copper/copper_sky.bin"
    even

    include    "level_01_entities.asm"
    include    "level_02_entities.asm"
    include    "level_03_entities.asm"
    include    "level_04_entities.asm"
    include    "level_05_entities.asm"
    include    "level_06_entities.asm"

;------------------------------------------------------------------------------
; Master Level Table (Pointers to Level Definitions)
;
; Contains 32-bit pointers to each level's LevelDef structure, terminated by 0.
; LevelInit accesses this table via LevelIndex(a5) * 4 to unpack the level's
; tile layers (Background, Platform, Ladder, Water, Foreground), camera bounds,
; player spawn coordinates, enemy patrol routes, animal friends, and oxygen kits.
; LEVEL_TABLE_COUNT is worked out from the table below, so adding a level
; needs only a new dc.l line.
;------------------------------------------------------------------------------
; Contract bindings: data the engine falls back to when no LevelDef is active
; (engine/gameplay/customlevel.asm, tmx_renderer.asm, water_effects.asm),
; and the friend sheet the engine's entity code draws from (entities.asm).
LevelDefaultPalette     = Level_01_Palette
LevelDefaultPlatformMap = Level_01_PlatformMap
LevelDefaultMusic       = LevelMod
FaultScreen             = DisplayScreen   ; Chip RAM the fault screen may overwrite
LevelDefaultEnemyList   = Level_01_EnemyList
FriendSpritesRaw        = AnimalSpritesRaw     ; friend sheet (engine/gameplay/entities.asm)
FriendSpritesMsk        = AnimalSpritesMsk

LevelTable:
    dc.l       Level_01_Def
    dc.l       Level_02_Def
    dc.l       Level_03_Def
    dc.l       Level_04_Def
    dc.l       Level_05_Def
    dc.l       Level_06_Def
LevelTableEnd:
    dc.l       0                       ; null terminator

LEVEL_TABLE_COUNT       = (LevelTableEnd-LevelTable)/4 ; built-in levels (engine contract)

;------------------------------------------------------------------------------
; Michroma proportional "hero text" font (placard/warning screens, e.g. the
; GAME OVER / PURGE flash effects) — CPU-read only (bigfont.asm), so Fast RAM like
; the other fonts above. See assets/font/generate_michroma_font.py for how this
; was rasterised and include/resources/bigfont.asm for the blit routines.
;------------------------------------------------------------------------------
    include    "michroma_font_data.asm"


;------------------------------------------------------------------------------
; Loading screen assets & tape audio (Fast RAM — CPU read / staged into Chip RAM)
;
; LoadingPal, LoadingRawZ, and tape audio PCM samples (zxsfx.asm) are offloaded
; to Fast RAM.  During boot loading setup, LoadingStageAudio dynamically stages
; the PCM samples into unused space in NonDisplayScreen (+40000) for Paula DMA.
; This saves ~53.7 KB of permanent Chip RAM.
;------------------------------------------------------------------------------
LoadingPal:
    incbin     "assets/graphics/title/loadingscreen.pal"
    even

LoadingRawZ:
    incbin     "assets/graphics/title/loadingscreen.zx0"
    even

    include    "zxsfx.asm"

;------------------------------------------------------------------------------
; Intro splash screen assets & fanfare audio (Fast RAM — staged into Chip RAM at boot)
;------------------------------------------------------------------------------
TitleLogoRaw:
    incbin     "assets/graphics/title/AGE_title.raw"
    even

TitleLogoPal:
    incbin     "assets/graphics/title/AGE_title.pal"
    even

SfxIntroFanfare:
    dc.l    0                           ; sfx_ptr dynamically patched by FlashScreenSetup
    dc.w    (SfxIntroFanfare_RawEnd-SfxIntroFanfare_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    64                          ; full volume intro splash trumpet fanfare
    dc.b    SFX_AUTO_CHANNEL
    dc.b    127                         ; absolute highest priority intro fanfare

SfxIntroFanfare_Raw:
    incbin      "assets/fx/sfx_intro_fanfare.raw"
    even
SfxIntroFanfare_RawEnd:

;------------------------------------------------------------------------------
; Menu screen title banner & victory duckling (Fast RAM — staged into Chip RAM)
;------------------------------------------------------------------------------
TitleHeroRaw:
    incbin     "assets/graphics/title/duck_rescue_title.raw"
    even

TitleHeroPal:
    incbin     "assets/graphics/title/duck_rescue_title.pal"
    even

GameCompleteHeroRaw:
    incbin     "assets/graphics/title/duckling_complete.raw"
    even

;------------------------------------------------------------------------------
; Level-complete player headshots & palettes (Fast RAM — staged into Chip RAM)
;------------------------------------------------------------------------------
LevelCompletePortraitRaw:
    incbin      "assets/graphics/headshots/headshot_mia_128x64.raw"
    even

LevelCompletePortraitPal:
    incbin      "assets/graphics/headshots/headshot_mia.pal"
    even

;------------------------------------------------------------------------------
; Title screen music (Fast RAM — staged into NonDisplayScreen+10000 at boot/title)
; Staged dynamically by TitleSetup into NonDisplayScreen in Chip RAM, then
; played via PTPlayer. Stopped by AudioStopMod when entering gameplay.
; Saves 46,414 bytes of permanent Chip RAM!
;------------------------------------------------------------------------------
TitleScreenMusicMod:
    incbin     "assets/music/heatwave_cruise.mod"
    even
TitleScreenMusicModEnd:

;------------------------------------------------------------------------------
; End-screen audio (Fast RAM: staged into NonDisplayScreen when its screen opens)
; Each is played only on its own screen, after AudioStopMod, and the screen
; stops it again before leaving, so the staged copy is never overwritten while
; Paula reads it. AudioPlayGameCompleteMusic and AudioPlayGameOver copy them.
; Saves 37,730 bytes of permanent Chip RAM.
;------------------------------------------------------------------------------
GameCompleteMod:
    incbin     "assets/music/10kdub.mod"
    even
GameCompleteModEnd:

SfxGameOver_Raw:
    incbin      "assets/fx/sfx_game_over.raw"
    even
SfxGameOver_RawEnd:

    dc.w       $ffff               ; non-zero end word: keeps the linker from trimming
                                   ; this section's trailing zero bytes out of the file

;==============================================================================
; Chip RAM data section  (data_chip)
;
; All data that must be in Chip RAM because it is accessed by the DMA hardware
; (Copper, Blitter, Agnus sprite DMA, audio DMA):
;
;   copperlists.asm     - cpGame and cpLoading copper list programs
;   LevelMod            - gameplay music module
;   game_sfx.asm        - in-game sound effect waveforms
;   GameTiles*          - tilemap graphics & mask
;   EnemySprites*       - enemy sprites & masks
;   DizzyStars*         - dizzy star sprites & mask
;   AnimalSprites*      - animal friend sprites & mask
;   SmokeSprites*       - landing dust puff & mask
;
; The Chip data is split into four sections (data_chip, chip_audio, chip_sfx,
; chip_gfx),
; and the Chip BSS into three more. Each becomes its own hunk, and AmigaOS
; loads each hunk into one unbroken block, so smaller hunks still fit when
; Chip RAM is fragmented, for example when launched from Workbench.
;==============================================================================

    section    data_chip,data_c

    include    "copperlists.asm"

;------------------------------------------------------------------------------
; Gameplay graphics and music (blitter / Paula DMA — must be Chip RAM).
; Placed BEFORE the loading-screen overlay region: all of this is needed for
; the rest of the session once gameplay starts.
;
;   LevelMod     - gameplay music module (AudioPlayLevelMusic, Phase B)
;------------------------------------------------------------------------------
    section    chip_audio,data_c

LevelMod:
    incbin     "assets/music/xlr8.mod"
    even

;------------------------------------------------------------------------------
; In-Game Sound Effects (Paula sample DMA — must be Chip RAM).
;------------------------------------------------------------------------------
    dc.w       $ffff               ; non-zero end word: keeps the linker from trimming
                                   ; this section's trailing zero bytes out of the file

    section    chip_sfx,data_c

    include    "game_sfx.asm"
    even
    dc.w       $ffff               ; non-zero end word: keeps the linker from trimming
                                   ; this section's trailing zero bytes out of the file

    section    chip_gfx,data_c

GameTilesRaw:
    incbin     "assets/graphics/tiles/tileset-compact_176x80.raw"
    even

GameTilesMsk:
    incbin     "assets/graphics/tiles/tileset-compact_176x80.msk"
    even

EnemySpritesRaw:
    incbin     "assets/graphics/enemies/enemies_64x48.raw"
    even

EnemySpritesWhiteRaw:
    incbin     "assets/graphics/enemies/enemies_64x48_white.raw"
    even

EnemySpritesMsk:
    incbin     "assets/graphics/enemies/enemies_64x48.msk"
    even

DizzyStarsRaw:
    incbin     "assets/graphics/enemies/dizzy_stars_64x16.raw"
    even

DizzyStarsMsk:
    incbin     "assets/graphics/enemies/dizzy_stars_64x16.msk"
    even

AnimalSpritesRaw:
    incbin     "assets/graphics/animals/animals_64x48.raw"
    even

AnimalSpritesMsk:
    incbin     "assets/graphics/animals/animals_64x48.msk"
    even

SmokeSpritesRaw:
    incbin     "assets/graphics/effects/smoke_64x32.raw"
    even

SmokeSpritesMsk:
    incbin     "assets/graphics/effects/smoke_64x32.msk"
    even

;------------------------------------------------------------------------------
; Player Character BOB Master Sheets (Chip RAM — Blitter DMA source)
;
; Mia's right-facing master graphics (24 frames, 16 colours, 4 bitplanes).
; Pre-loaded into Chip RAM so the Blitter can read them directly without
; runtime copying.
; Total: 3 * 9,216 = 27,648 bytes.
;------------------------------------------------------------------------------
PlayerRightRaw:
PlayerMiaRaw:
    incbin     "assets/graphics/player/player_bobs_female_128x144.raw"
    even

PlayerRightMsk:
PlayerMiaMsk:
    incbin     "assets/graphics/player/player_bobs_female_128x144.msk"
    even

PlayerRightWhiteRaw:
PlayerMiaWhiteRaw:
    incbin     "assets/graphics/player/player_bobs_female_128x144_white.raw"
    even
    dc.w       $ffff               ; non-zero end word: keeps the linker from trimming
                                   ; this section's trailing zero bytes out of the file

;==============================================================================
; Fast RAM BSS section  (mem_fast)
;
; Uninitialised working memory allocated in Fast RAM (cleared by TurboClear
; before gameplay begins).  Fast RAM gives the CPU faster access than Chip RAM
; for the data it accesses every frame.
;
;   Variables  - the global Variables block (layout defined in variables.asm),
;                permanently addressed via a5 throughout the game.
;   Keys       - 256-byte keyboard state buffer (KeyboardInterrupt writes here).
;                Followed by 200 bytes of padding to safely handle any out-of-
;                range scan-codes without corrupting adjacent data.
;==============================================================================

    section    mem_fast,bss
    even

AllFast:

Variables:
    ds.b       Variables_Sizeof
    even

Keys:
    ds.b       256          ; one byte per scan-code (0-255); max written index is 127
                            ; (KeyboardInterrupt masks with AND.W #$7F so no OOB access)

SnapshotBuffer:
    ds.b       Snap_Sizeof*UNDO_BUFFER_SIZE
    even

GameStack:
    ds.b       4096         ; the game's own stack (Restart switches to it, so the
                            ; game never depends on the CLI's configured stack size)
GameStackTop:

AllFastEnd:

;==============================================================================
; Chip RAM BSS section  (mem_chip)
;
; Uninitialised working buffers that must be in Chip RAM because they are read
; or written by the Blitter, Copper, or sprite DMA every frame.
;
;   NullSprite      - two zero longwords (terminated empty sprite structure).
;                     All unused sprite channels are pointed here so Agnus
;                     fetches nothing and outputs transparent pixels.
;   DisplayScreen   - the composited game frame.  DrawWalls, DrawPlayersAndActors,
;                     and BlitStar32 all write here; copper bitplane pointers
;                     point here so this is what appears on screen.
;   NonDisplayScreen - a clean copy of the background (walls + ladders + shadows
;                     only, no actors).  ClearActor restores DisplayScreen by
;                     copying from NonDisplayScreen.
;==============================================================================

    section    mem_chip,bss_c
AllChip:

NullSprite:
    ds.l       2                   ; SPRxPOS/SPRxCTL = 0,0 (sprite disabled).

; Each screen buffer has a section of its own, so each needs an 80 KB block
; rather than one 160 KB block. No code relies on them being adjacent.
    section    chip_display,bss_c
DisplayScreen:
    ds.b       LEVEL_SCREEN_SIZE

    section    chip_backdrop,bss_c
NonDisplayScreen:
    ds.b       LEVEL_SCREEN_SIZE

    section    mem_chip,bss_c

;------------------------------------------------------------------------------
; Left-facing flipped player BOB buffers (generated at boot by PlayerInitFlippedSprites)
;
; To minimise disk footprint and asset duplication, only right-facing player
; BOB frames are stored on disk (player_bobs_female_128x144.raw, .msk, and _white.raw).
; At boot, PlayerInitFlippedSprites performs a horizontal mirror on all 24 frames
; (6 rows of 4 cels, 32px cell storage containing 24px active graphics) into
; these Chip RAM buffers.  The blitter routines index these buffers directly
; when Player_Facing(a4) < 0 (facing left).
; Total per buffer: 6 rows * 1536 bytes/row = 9,216 bytes.
;------------------------------------------------------------------------------
PlayerLeftRaw:
    ds.b       PLAYER_BOB_TOTAL_BYTES ; 9,216 bytes
PlayerLeftMsk:
    ds.b       PLAYER_BOB_TOTAL_BYTES ; 9,216 bytes
PlayerLeftWhiteRaw:
    ds.b       PLAYER_BOB_TOTAL_BYTES ; 9,216 bytes

AllChipEnd:
