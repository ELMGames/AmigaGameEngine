# AMIGA Game Engine

A high-performance Motorola 68000 assembly game engine for Commodore Amiga OCS/ECS systems (A500 / A600 / A2000), engineered for base 512 KB Chip RAM + Fast RAM configurations.

Out of the box, it features a complete boot-to-gameplay pipeline: custom OS takeover with clean CLI exit, intro flash banner splash, a retro ZX Spectrum-style tape loading sequence, an interactive title screen with dynamic Copper aurora effects, a 3-track ProTracker soundtrack composed by JAM (`h3xaflight`), playable adventurer **Denise** (featuring custom animations and ponytail physics), a Blade Runner-inspired **GAME OVER** terminal sequence, a starfield victory **Game Complete** screen, and a modern **Tiled `.tmx` level editor pipeline** supporting multi-layer 16×16 tilemaps, tall scrolling levels (up to 43 rows / 688 scanlines), cookie-cut Player & Enemy Blitter Objects (BOBs), asynchronous crate physics, animal friend rescue objectives, hardware sprite HUDs, rising water flood mechanics, and frame-by-frame debug stepping.

---

## Key Features

* **Modern Tiled (`.tmx`) Workflow:** Author multi-layer levels in the standard Tiled map editor. The Python pipeline (`tools/export_level.py`) automatically compiles levels into planar tileset graphics, blitter masks, composite maps, 1D collision logic maps, and 68000 assembly entity tables under `include/resources/levels/`.
* **Playable Protagonist (Denise):** Play as **Denise**, a female adventurer featuring custom animated ponytail physics and red adventurer tunic across all actions (walk, idle, ladder climbing, cane attack, flailing fall, and collapse death). Her master right-facing graphics stream directly from Chip RAM (`data_chip`). Dynamic boot-time horizontal mirroring (`PlayerInitFlippedSprites`) mirrors her right-facing master graphics into a single set of left-facing Chip RAM BSS buffers, cutting asset disk footprint in half while maintaining full 512 KB Chip RAM compatibility.
* **True VBlank Blitter Pipeline:** Player BOB erase, cookie-cut drawing (`minterm $0FCA`), and multi-layer foreground stamping execute at scanlines 0..22 during vertical blanking, eliminating scanline race tearing and foreground occlusion flicker.
* **16-Colour Player & Enemy BOBs:** Dedicated conversion tools (`tools/convert_player_bob.py`, `tools/convert_enemies.py`) generate 4-bitplane, 16-colour Blitter Objects (BOBs) with separate blitter masks and white flash/invulnerability silhouettes.
* **Blade Runner-Inspired "GAME OVER" Sequence:** Losing all 3 lives transitions to a dedicated terminal screen styled after the iconic Blade Runner spinner terminal (`purge.png`), featuring a deep crimson backdrop (`COLOR00 = $0711`), terminal header/telemetry, white horizontal dashed lines, and centered flashing Michroma typography (`GAME` / `OVER`) with a 4-second timeout returning cleanly to the Title Menu (or skippable via fire/key).
* **Pushable Blocks & Asynchronous Physics (`BLOCK_PUSH`):** Smooth quadratic-eased push animations. Crates pushed off platform edges fall asynchronously in parallel, allowing the player to continue walking immediately without freezing or waiting for the crate to land. Seamless overlap compositing guarantees zero cutout flicker between player and crates.
* **Hardware Sprite HUD Subsystem:** Real-time HUD elements rendered via Agnus hardware sprites with zero CPU/Blitter cycle overhead:
  * **SPR0:** Player Lives counter indicator.
  * **SPR2:** Oxygen Kit inventory pickup.
  * **SPR3:** Animal Friends Remaining counter, featuring a custom animal icon and live numerical digit tracking.
* **Animal Friends Rescue Objective:** Dynamic rescued friend tracking (Bunnies, Puppies, Kittens, Ducklings, Chicks) with sub-pixel animations, pickup collision, and audio feedback.
* **Dynamic Rising Water Flood:** Scaled PAL/NTSC timer-driven rising water layer with 50% cyan dither stippling, animated surface waves, and real-time actor submersion dimming.
* **Oxygen Depletion & Collectibles:** Submerged breath depletion meter with rising air bubbles, drowning hazards, and collectible oxygen refill canisters.
* **Interactive Slow Mode & Step Debugging:** Press **S** at any time to pause the gameloop and enter SLOW MODE with a real-time on-screen telemetry overlay. Tap **A** to advance the engine exactly one frame, or hold **A** to advance at full speed.
* **Rewind & Undo Subsystem:** Full move recording and VHS rewind effect engine (`undo.asm`, `vhs_rewind.asm`).
* **Efficient Memory Model:** Strict separation between Chip RAM (DMA-accessible copper lists, screen bitplanes, audio, and BOB buffers) and Fast RAM (code, state tables, level logic, and BSS variables). Runs comfortably in **512 KB Chip RAM** with over **118 KB free headroom**.
* **Audio & Soundtrack:** Built-in 4-channel ProTracker playback engine powered by Frank Wille's PTPlayer with 9 prioritized sound effects and a complete 3-track soundtrack composed by **JAM (`h3xaflight`)**:
  * Title Theme: *Heatwave Cruise*
  * Level Theme: *XLR8*
  * Completion Theme: *10k Reggae Dub*
* **Clean OS Takeover & Exit:** Gracefully suspends AmigaOS (saving viewports, DMACON, and interrupt vectors) and restores the system cleanly back to the CLI prompt upon exit.

---

## Quick Start

### Prerequisites
* **Assembler & Linker:** `vasmm68k_mot` and `vlink` (available on `PATH`, configured in `AMIGA_TOOLCHAIN`, or bundled with the [amiga-assembly](https://marketplace.visualstudio.com/items?itemName=prb28.amiga-assembly) VS Code extension).
* **Python 3:** Required for the automated asset and level pipeline (`pip install Pillow`).

### Building from Command Line (PowerShell)

```powershell
./build.ps1              # Export Tiled levels + convert assets + assemble + link + sync to UAE
./build.ps1 -Assets      # Optional: re-convert raw UI assets before building
./build.ps1 -Out my.exe  # Build executable to a custom output path
```

The compiled Amiga executable lands by default at `uae/dh0/main` (and synchronizes with parent emulator directories), ready to launch directly in FS-UAE, WinUAE, or real Amiga hardware.

### Controls

| Input | Context | Function |
| :--- | :--- | :--- |
| **Cursor Keys / Joystick** | In-Game | Player movement and ladder climbing |
| **Space / Fire Button** | In-Game | Cane hook action / swing trigger |
| **P** | In-Game | Toggle **PAUSE** / **UNPAUSE** (displays `** PAUSED **` banner) |
| **S** | In-Game | Toggle **SLOW MODE** on/off (activates debug HUD with `MODE:SLOW`) |
| **A** (Tap) | In-Game (Slow Mode) | **Step gameloop** forward by exactly one frame |
| **A** (Hold) | In-Game (Slow Mode) | Advance gameloop at full speed while held down |
| **D** | In-Game | Toggle **Debug Telemetry HUD** directly (`CAM`, `PLY`, `ACT`, `DIR`, `ENM`, `WTR`, `MODE`) |
| **ESC** | In-Game | Return to Title Screen immediately |
| **F5** | In-Game | Toggle developer debug mode (enables F1/F2 level skip and F4 complete skip) |
| **F1 / F2** | In-Game (Debug Mode) | Skip to previous / next level |
| **F4** | In-Game (Debug Mode) | Jump directly to Game Complete ending screen |
| **F3** | In-Game (Debug Mode) | Toggle raster CPU-timing bar (green = CPU load, red = VBlank overrun) |
| **Cursor Keys / Joystick** | Title Menu | Navigate menu options (Play Level, Instructions, Credits, Quit) |
| **Return / Fire / Space** | Title Menu | Confirm selection |
| **Fire / Return / ESC** | Game Over | Skip 4-second delay and return immediately to Title Screen |
| **ESC** | Title Screen | **Quit to OS** (clean return to CLI prompt) |
| **F6** | Loading Screen | Skip tape-loading animation |

---

## Architecture & Hardware Allocation

### Hardware Sprite Channel Mapping

| Sprite Channel | Copper Offset | Purpose | Characteristics |
| :---: | :---: | :--- | :--- |
| **SPR0** | `cpSprites + 0` | Player Lives Counter | Visual heart/head HUD counter for player lives |
| **SPR1** | `cpSprites + 8` | Spare / Paired SPR0 | Reserved for 15-colour paired sprite mode or secondary HUD |
| **SPR2** | `cpSprites + 16` | Oxygen Kit Indicator | Collectible scuba inventory item display |
| **SPR3** | `cpSprites + 24` | Friends Remaining Counter | Animal icon + live single-digit numerical countdown |
| **SPR4 / SPR5** | `cpSprites + 32/40` | Free / Reserved | Available for secondary player or cursor |
| **SPR6 / SPR7** | `cpSprites + 48/56` | Free / Profiler | Available for custom overlays / raster beam markers |

### Memory Footprint

Exact memory breakdown verified via `tools/chip_ram_report.py`:

| Section | Target RAM | Allocation | Description |
| :--- | :--- | :---: | :--- |
| **`main` (Code)** | Fast/Chip RAM | ~48.0 KB | Complete 68000 instruction stream assembled as a single translation unit |
| **`data_fast`** | Fast RAM | ~218.5 KB | Read-only tables (sine, easing), ZX0 loading assets, intro fanfare, TMX level tilemaps |
| **`mem_fast` (BSS)** | Fast RAM | ~54.2 KB | Game state, actor records (`a5` base), keyboard buffer, undo snapshot ring buffer, stack |
| **`data_chip`** | Chip RAM | ~157.4 KB | Copper lists, fonts, music (`xlr8.mod`, `10kdub.mod`), SFX PCM samples, BOBs (Denise), tilesets, enemies |
| **`mem_chip` (BSS)** | Chip RAM | ~248.0 KB | `DisplayScreen`, `NonDisplayScreen`, dynamic flipped player frames (`PlayerLeft*`), null sprites |

* **Total Chip RAM Usage:** **405,420 bytes (~395.9 KB)**
* **Chip RAM Free Headroom:** **118,868 bytes (~116.1 KB)** within the standard **512 KB** limit.

---

### State Machine (`include/resources/gameplay/gamestatus.asm`)

Game execution is dispatched every video frame via `GameStatus(a5)`:

| State Index | Identifier | Handler | Implementation File | Description |
| :---: | :--- | :--- | :--- | :--- |
| `0` | `GAME_INIT` | `LoadingSetup` | [`screens/loading.asm`](include/resources/screens/loading.asm) | One-shot tape loading initialization |
| `1` | `GAME_LOADING` | `LoadingRun` | [`screens/loading.asm`](include/resources/screens/loading.asm) | Per-frame tape loader animation & decode (F6 skips) |
| `2` | `GAME_RUN` | `GameRun` | [`gameplay/gamestatus.asm`](include/resources/gameplay/gamestatus.asm) | Active gameplay loop (player, actors, blits, slow mode) |
| `3` | `LEVEL_INIT` | `LevelTransitionRun` | [`gameplay/levelutils.asm`](include/resources/gameplay/levelutils.asm) | One-shot per-level initialization and wipe preparation |
| `4` | `LEVEL_WIPE` | `LevelTransitionRun` | [`gameplay/levelutils.asm`](include/resources/gameplay/levelutils.asm) | Blits end-of-level black wipe pattern |
| `5` | `LEVEL_HOLD` | `LevelTransitionRun` | [`gameplay/levelutils.asm`](include/resources/gameplay/levelutils.asm) | Holds black screen while next level is staged |
| `6` | `LEVEL_REVEAL` | `LevelTransitionRun` | [`gameplay/levelutils.asm`](include/resources/gameplay/levelutils.asm) | Reverse-wipe level reveal transition |
| `7–8` | `LEVEL_COMPLETE_*` | `LevelCompleteSetup/Run` | [`screens/levelcomplete.asm`](include/resources/screens/levelcomplete.asm) | Level victory summary, portrait, and password screen |
| `9` | `TITLE_SETUP` | `TitleSetup` | [`screens/titlescreen.asm`](include/resources/screens/titlescreen.asm) | Title screen init (copper aurora, title logo, menu) |
| `10` | `TITLE_RUN` | `TitleRun` | [`screens/titlescreen.asm`](include/resources/screens/titlescreen.asm) | Interactive title menu & background animation |
| `11–16` | `INSTR_*` | `InstrPage*Setup/Run` | [`screens/instructions.asm`](include/resources/screens/instructions.asm) | Multi-page how-to-play instruction booklet screens |
| `17–18` | `CREDITS_*` | `CreditsSetup/Run` | [`screens/credits.asm`](include/resources/screens/credits.asm) | Audio, graphics, tools, and engine credits screen |
| `19–20` | `GAME_COMPLETE_*` | `GameCompleteSetup/Run` | [`screens/gamecomplete.asm`](include/resources/screens/gamecomplete.asm) | Game complete victory sequence & credits starfield |
| `21–22` | `GAME_OVER_*` | `GameOverSetup/Run` | [`screens/gameover.asm`](include/resources/screens/gameover.asm) | Blade Runner terminal Game Over sequence |
| `23–24` | `FLASH_*` | `FlashSetup/Run` | [`screens/flashscreen.asm`](include/resources/screens/flashscreen.asm) | Initial boot splash banner & trumpet fanfare |

---

## Asset & Level Pipeline

All game assets are processed deterministically via scripts in [`tools/`](tools/):

1. **Level Authoring (`export_level.py`)**:
   - Converts Tiled `.tmx` maps (`assets/levels/Level_01/` through `Level_06/`) into planar Amiga data.
   - Outputs:
     - 16-colour planar raw tileset (`tileset-compact_176x80.raw`) and blitter mask (`.msk`).
     - Multi-layer binary maps: `*-background.map`, `*-platform.map`, `*-ladder.map`, `*-foreground.map`, and composite `*.map`.
     - 1D logic collision map (`*-gamemap.bin`).
     - 68000 assembly definitions (`include/resources/levels/level_XX_entities.asm`) specifying player spawns, ladders, patrol paths, push blocks, oxygen pickups, and animal friends.

2. **Player BOB Pipeline (`convert_player_bob.py`)**:
   - Generates 16-colour, 4-bitplane raw graphic sheets, blitter masks (`.msk`), and pure-white silhouettes (`_white.raw`) for **Denise** (`player_bobs_female_128x144.*`) (9,216 bytes).
   - Denise's sprite sheet features an animated ponytail across all 6 action rows (idle, walk, attack, death, ladder, falling) and custom red adventurer tunic.
   - At boot, `PlayerInitFlippedSprites` dynamically flips right-facing master graphics into a single set of left-facing Chip RAM BSS buffers (`PlayerLeftRaw`, `PlayerLeftMsk`, `PlayerLeftWhiteRaw`), cutting disk footprint in half and conserving precious Chip RAM.
   - Pass `--preview` to export a visual contact sheet (`player_female_preview.png`) for inspection.

3. **Animal Friend & Enemy Pipelines (`convert_animals.py`, `convert_enemies.py`)**:
   - Exports planar graphics, blitter masks, and optional animated GIF/PNG previews (via `--preview`) for enemies, dizzy stars, and animal companions.

4. **Audio & Sound Effects Pipeline (`generate_sfx.py`)**:
   - Synthesizes 8-bit signed PCM audio samples for game SFX (cane swing, crate push/impact, enemy stun, duck rescue, oxygen, player death, bubble pop, fanfare).

5. **ZX0 Decompression (`zx0_faster.asm` & `zx0.exe`)**:
   - Compresses title and overlay assets using Einar Saukas' ZX0 format (v2).
   - Real-time 68000 decompression into Chip RAM buffers with high speed and low overhead.

---

## Repository Structure

```
.
├── build.ps1                       # Primary automated build & sync script
├── build.py                        # Cross-platform Python build driver
├── main.asm                        # Entry point, memory sections, main loop, VBlank ISR
├── assets/
│   ├── data/                       # Sine & easing mathematical lookup tables
│   ├── font/                       # 8x8 font glyph raw data and proportional Michroma UI font
│   ├── fx/                         # 8-bit signed PCM SFX samples and ZX tape audio wavs
│   ├── graphics/
│   │   ├── animals/                # Animal friend raw/msk files
│   │   ├── copper/                 # Precalculated copper sky binary
│   │   ├── enemies/                # Enemy sprite sheets, dizzy stars raw/msk
│   │   ├── headshots/              # Denise portrait graphics and palettes
│   │   ├── sprites/                # Denise BOB raw/msk/white files, PNG master source
│   │   ├── tiles/                  # 16x16 raw compact tileset and blitter mask
│   │   └── title/                  # Title screen logo, duck banner, and palette files
│   ├── levels/                     # Tiled .tmx levels (Level_01/ through Level_06/, Test/)
│   └── music/                      # ProTracker modules by JAM (heatwave_cruise, xlr8, 10kdub)
├── include/resources/
│   ├── audio/                      # Audio driver integration (audio.asm, gamesfx.asm, zxsfx.asm)
│   ├── core/                       # Constants, macros, data structures, and variables (a5)
│   ├── gameplay/                   # Gameloop, player, actors, tilemap, undo, vhs_rewind, levelutils
│   ├── graphics/                   # Copper lists, font renderers, HUD sprites, blitter routines
│   ├── levels/                     # Auto-generated level entity tables and metadata
│   ├── ptplayer/                   # Frank Wille's PTPlayer ProTracker replayer (ptplayer.asm)
│   ├── screens/                    # Screen state handlers (loading, titlescreen, instructions,
│   │                               #   credits, levelcomplete, gamecomplete, gameover, flashscreen)
│   └── system/                     # OS takeover, keyboard, controls, tools, zx0_faster
└── tools/                          # Asset converters, level exporters, SFX generator, and chip RAM reporter
```

---

## Verification & Diagnostics

* **True VBlank Execution:** Player erase/draw operations run in early VBlank (scanlines 0..22), eliminating beam race tearing.
* **CPU Fault Trap (Red Screen):** If a bus error, address error, illegal instruction, or invalid state occurs, the engine intercepts the exception vector and displays a full-screen red diagnostic canvas.
* **Frame Budget Raster Meter:** Press **F5** then **F3** in-game to display the real-time raster bar (green = healthy frame budget headroom). If CPU processing exceeds the vertical blank budget, the meter shifts red, indicating dropped frames.
* **On-Screen Diagnostic Overlay:** Press **D** or **S** to view live camera coordinates, player X/Y tile and sub-tile positions, action state, direction, active enemy count, waterline row, and current loop speed mode (`RUN` or `SLOW`).
* **Frame Step Debugger:** Press **S** to halt execution and inspect animations, collision logic, crate movement, and enemy patrol behaviors frame-by-frame with the **A** key.
