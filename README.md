# AMIGA Game Engine

A high-performance Motorola 68000 assembly game engine for Commodore Amiga OCS/ECS systems (A500 / A600 / A2000), engineered for 512 KB Chip RAM + Fast RAM setups.

Out of the box, it features a complete boot-to-gameplay pipeline: custom OS takeover with clean CLI exit, a retro ZX Spectrum-style tape loading sequence, an interactive title screen with dynamic Copper aurora effects and ProTracker audio, and a modern **Tiled `.tmx` level editor pipeline** supporting 16×16 tilemaps, multi-layer rendering, and 16-colour Player Blitter Objects (BOBs).

---

## Key Features

* **Modern Tiled (`.tmx`) Workflow:** Author multi-layer levels in the standard Tiled map editor. The Python pipeline (`tools/export_level.py`) automatically compiles levels into planar tileset graphics, blitter masks, composite maps, 1D collision logic maps, and 68000 assembly entity tables.
* **16-Colour Player BOBs:** Dedicated pipeline (`tools/convert_player_bob.py`) for generating 4-bitplane, 16-colour Blitter Objects (BOBs) with separate blitter masks, allowing clean layer ordering with background tiles and platforms. Hardware sprite player mode is also supported.
* **Efficient Memory Model:** Strict separation between Chip RAM (DMA-accessible copper lists, screen bitplanes, audio, and BOB buffers) and Fast RAM (code, state tables, level logic, and BSS variables).
* **Smooth 50 Hz PAL / 60 Hz NTSC:** Single-frame mainline execution model driven by a lightweight vertical blank interrupt, with automatic PAL/NTSC detection and timing compensation.
* **Audio & Music:** Built-in 4-channel ProTracker playback engine powered by PTPlayer with support for sound effects and music module switching.
* **Rewind & Undo Subsystem:** Full move recording and VHS rewind effect engine (`vhs_rewind.asm`, `undo.asm`).
* **Clean OS Takeover & Exit:** Gracefully suspends AmigaOS (saving viewports, DMACON, and interrupt vectors) and restores the system cleanly back to the CLI prompt upon exit.

---

## Quick Start

### Prerequisites
* **Assembler & Linker:** `vasmm68k_mot` and `vlink` (available on `PATH`, configured in `AMIGA_TOOLCHAIN`, or bundled with the [amiga-assembly](https://marketplace.visualstudio.com/items?itemName=prb28.amiga-assembly) VS Code extension).
* **Python 3:** Required for the automated asset and level pipeline (`pip install Pillow`).

### Building from Command Line (PowerShell)

```powershell
./build.ps1              # Export Tiled level + convert player BOBs + assemble + link
./build.ps1 -Assets      # Optional: re-convert title/raw UI assets before building
./build.ps1 -Out my.exe  # Build executable to a custom output path
```

The compiled Amiga executable lands by default at `../uae/dh0/main`, ready to launch directly in FS-UAE, WinUAE, or real Amiga hardware.

### Controls

| Input | Context | Function |
| :--- | :--- | :--- |
| **F6** | Loading Screen | Skip tape-loading animation |
| **Cursor Keys / Joystick** | Title Menu | Navigate menu options |
| **Return / Fire Button** | Title Menu | Select menu item |
| **Arrow Keys / Joystick** | In-Game | Player movement and climbing |
| **ESC** | In-Game | Return to Title Screen |
| **ESC** | Title Screen | **Quit to OS** (clean return to CLI prompt) |
| **F5** | Title / In-Game | Toggle debug mode |
| **F3** | In-Game (Debug) | Toggle raster CPU-time meter (yellow indicates frame overrun) |

---

## Architecture & Memory Layout

### Memory Footprint

| Section | Target RAM | Allocation | Description |
| :--- | :--- | :---: | :--- |
| **`main` (Code)** | Any (Fast/Chip) | ~36.8 KB | Full 68000 instruction stream assembled as a single translation unit |
| **`data_fast`** | Fast RAM | ~31.5 KB | Read-only lookup tables (easing/sine tables), level pointers, entity data |
| **`mem_fast` (BSS)** | Fast RAM | ~53.3 KB | Game state, actor variables (`a5` base), keyboard buffers, stack |
| **`data_chip`** | Chip RAM | ~198.7 KB | Copper lists, title graphics/palettes, ProTracker MODs, and 16×16 raw tilesets |
| **`mem_chip` (BSS)** | Chip RAM | ~241.3 KB | `DisplayScreen`, `NonDisplayScreen`, null sprite buffers, and scratch areas |

Total Chip RAM consumption is ~440 KB, fitting comfortably within the standard **512 KB Chip RAM** boundary of base Amiga 500/2000 models.

### State Machine (`gamestatus.asm`)

Game execution is orchestrated through a jump-table dispatcher indexed by `GameStatus(a5)`:

| State Index | Identifier | Handler | File | Description |
| :---: | :--- | :--- | :--- | :--- |
| `0` | `GAME_INIT` | `LoadingSetup` | [`loading.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/loading.asm) | One-shot tape loading initialization |
| `1` | `GAME_LOADING` | `LoadingRun` | [`loading.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/loading.asm) | Per-frame tape loader animation & decode |
| `2` | `GAME_RUN` | `GameRun` | [`gamestatus.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/gamestatus.asm) | Active gameplay loop (player, actors, blits) |
| `3–6` | `LEVEL_*` | `LevelTransitionRun` | [`tilemap.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/tilemap.asm) | Level init, screen wipes, hold, and reveals |
| `7–8` | `LEVEL_COMPLETE_*` | `LevelCompleteSetup/Run` | [`levelcomplete.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/levelcomplete.asm) | Level victory summary and password screen |
| `9` | `TITLE_SETUP` | `TitleSetup` | [`titlescreen.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/titlescreen.asm) | Title screen init (copper aurora, title logo) |
| `10` | `TITLE_RUN` | `TitleRun` | [`titlescreen.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/titlescreen.asm) | Interactive title menu & background animation |
| `11` | `INSTRUCTIONS` | `InstructionsRun` | [`instructions.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/instructions.asm) | How-to-play instruction booklet screen |
| `12` | `GAME_COMPLETE` | `GameCompleteRun` | [`gamecomplete.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/gamecomplete.asm) | Game completion ending cinematic screen |

---

## Asset & Level Pipeline

All game assets are processed deterministically via scripts in [`tools/`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/tools/):

1. **Level Authoring (`export_level.py`)**:
   - Converts Tiled `.tmx` maps (`assets/Levels/Level_01.tmx`) into planar Amiga data.
   - Outputs:
     - 16-colour planar raw tileset (`FourSeasons.tiles_176x256.raw`) and blitter mask (`.msk`).
     - Multi-layer binary maps: `Level_01-platform.map`, `Level_01-water.map`, and composite `Level_01.map`.
     - 1D logic collision map (`Level_01-gamemap.bin`).
     - 68000 assembly definitions (`level_01_entities.asm`) specifying player spawns, patrol paths, triggers, and enemy spawn tables.

2. **Player BOB Pipeline (`convert_player_bob.py`)**:
   - Processes player frame grids into 16-colour, 4-bitplane raw graphic sheets (`player_bobs_64x576.raw`) and matching blitter masks (`.msk`).
   - Exports contact sheets (`player_bobs_preview.png`) for inspection.

3. **ZX0 Decompression (`zx0_faster.asm` & `zx0.exe`)**:
   - Compresses title and overlay assets using Einar Saukas' ZX0 format (v2).
   - Real-time 68000 decompression into Chip RAM buffers with high speed and low overhead.

---

## Repository Structure

```
.
├── build.ps1                       # Primary automated build script
├── main.asm                        # Entry point, memory sections, main loop, VBlank ISR
├── assets/
│   ├── Levels/                     # Tiled .tmx levels and compiled binary maps
│   ├── graphics/
│   │   ├── sprites/                # Player BOB raw/msk files, HW sprites, and palettes
│   │   ├── tiles/                  # 16x16 raw tilesets and blitter masks
│   │   └── title/                  # Title screen logo raw and palette files
│   └── music/                      # ProTracker modules (10kdub.mod, supremacy_title.mod)
├── include/resources/
│   ├── system.asm                  # OS takeover, vector saves, and SystemRestore
│   ├── gamestatus.asm              # State machine dispatcher & GameRun mainline
│   ├── tilemap.asm                 # Blitter-based tile rendering & composite maps
│   ├── levelutils.asm              # Level initialisation, enemy tables, and object placement
│   ├── level_01_entities.asm       # Auto-generated level spawns & entity descriptors
│   ├── player.asm / actors.asm     # Player movement physics and enemy state machines
│   ├── undo.asm / vhs_rewind.asm   # Move recording and VHS rewind effect
│   ├── titlescreen.asm             # Title menu and Copper aurora animation
│   ├── copperlists.asm             # Display Copper lists, palettes, and bitplane registers
│   ├── keyboard.asm / controls.asm # CIA-A keyboard interrupt handler and joystick input
│   └── audio.asm                   # PTPlayer sound driver integration
└── tools/                          # Asset conversion, level exporters, and build utilities
```

---

## Verification & Diagnostics

* **CPU Fault Trap (Red Screen):** If a bus error, address error, illegal instruction, or invalid state occurs, the engine intercepts the exception vector and displays a full-screen red diagnostic canvas.
* **Frame Budget Raster Meter:** Press **F5** then **F3** in-game to display the real-time raster bar. If CPU processing exceeds the vertical blank budget, the meter shifts yellow, indicating dropped frames.
