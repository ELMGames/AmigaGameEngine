# AMIGA Game Engine

A high-performance Motorola 68000 assembly game engine for Commodore Amiga OCS/ECS systems (A500 / A600 / A2000), engineered for 512 KB Chip RAM + Fast RAM setups.

Out of the box, it features a complete boot-to-gameplay pipeline: custom OS takeover with clean CLI exit, a retro ZX Spectrum-style tape loading sequence, an interactive title screen with dynamic Copper aurora effects and ProTracker audio, and a modern **Tiled `.tmx` level editor pipeline** supporting 16×16 tilemaps, multi-layer rendering, cookie-cut Player & Enemy Blitter Objects (BOBs), rising water mechanics, and frame-by-frame debug step stepping.

---

## Key Features

* **Modern Tiled (`.tmx`) Workflow:** Author multi-layer levels in the standard Tiled map editor. The Python pipeline (`tools/export_level.py`) automatically compiles levels into planar tileset graphics, blitter masks, composite maps, 1D collision logic maps, and 68000 assembly entity tables.
* **16-Colour Player & Enemy BOBs:** Dedicated conversion tools (`tools/convert_player_bob.py`) generate 4-bitplane, 16-colour Blitter Objects (BOBs) with separate blitter masks. Supports cookie-cut blitting (`minterm $0FCA`) with pristine background restoration from `NonDisplayScreen`, ensuring artifact-free movement over ladders, platforms, and rising water.
* **Interactive Slow Mode & Step Debugging:** Press **S** at any time to pause the gameloop and enter SLOW MODE with a real-time on-screen telemetry overlay. Tap **A** to advance the engine exactly one frame, or hold **A** to advance at full speed.
* **Dynamic Rising Water:** Scaled PAL/NTSC timer-driven rising water layer with 50% cyan dither stippling and 5-pixel animated surface waves, seamlessly composited across active actors.
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
./build.ps1              # Export Tiled level + convert player BOBs + assemble + link + sync to UAE
./build.ps1 -Assets      # Optional: re-convert title/raw UI assets before building
./build.ps1 -Out my.exe  # Build executable to a custom output path
```

The compiled Amiga executable lands by default at `uae/dh0/main` (and synchronizes with any parent emulator directories), ready to launch directly in FS-UAE, WinUAE, or real Amiga hardware.

### Controls

| Input | Context | Function |
| :--- | :--- | :--- |
| **Cursor Keys / Joystick** | In-Game | Player movement and ladder climbing |
| **Space / Fire Button** | In-Game | Switch active player / action trigger |
| **S** | In-Game | Toggle **SLOW MODE** on/off (activates debug HUD with `MODE:SLOW`) |
| **A** (Tap) | In-Game (Slow Mode) | **Step gameloop** forward by exactly one frame |
| **A** (Hold) | In-Game (Slow Mode) | Advance gameloop at full speed while held down |
| **D** | In-Game | Toggle **Debug Telemetry HUD** directly (`CAM`, `PLY`, `ACT`, `DIR`, `ENM`, `WTR`, `MODE`) |
| **ESC** | In-Game | Return to Title Screen immediately |
| **F5** | In-Game | Toggle developer debug mode (enables F1/F2 level skip and F4 complete skip) |
| **F1 / F2** | In-Game (Debug Mode) | Skip to previous / next level |
| **F4** | In-Game (Debug Mode) | Jump directly to Game Complete ending screen |
| **F3** | In-Game (Debug Mode) | Toggle raster CPU-timing bar (red = CPU load, yellow = VBlank overrun) |
| **Cursor Keys / Joystick** | Title Menu | Navigate menu options |
| **Return / Fire Button** | Title Menu | Select menu item |
| **ESC** | Title Screen | **Quit to OS** (clean return to CLI prompt) |
| **F6** | Loading Screen | Skip tape-loading animation |

---

## Architecture & Memory Layout

### Memory Footprint

| Section | Target RAM | Allocation | Description |
| :--- | :--- | :---: | :--- |
| **`main` (Code)** | Any (Fast/Chip) | ~37.9 KB | Full 68000 instruction stream assembled as a single translation unit |
| **`data_fast`** | Fast RAM | ~33.2 KB | Read-only lookup tables (easing/sine tables), level pointers, entity data |
| **`mem_fast` (BSS)** | Fast RAM | ~53.2 KB | Game state, actor variables (`a5` base), keyboard buffers, stack |
| **`data_chip`** | Chip RAM | ~235.6 KB | Copper lists, title graphics/palettes, ProTracker MODs, player BOB graphics/masks, and 16×16 raw tilesets |
| **`mem_chip` (BSS)** | Chip RAM | ~221.3 KB | `DisplayScreen`, `NonDisplayScreen`, null sprite buffers, and scratch areas |

Total Chip RAM consumption fits comfortably within the standard **512 KB Chip RAM** boundary of base Amiga 500/2000 models.

### State Machine (`gamestatus.asm`)

Game execution is orchestrated through a jump-table dispatcher indexed by `GameStatus(a5)`:

| State Index | Identifier | Handler | File | Description |
| :---: | :--- | :--- | :--- | :--- |
| `0` | `GAME_INIT` | `LoadingSetup` | [`loading.asm`](include/resources/loading.asm) | One-shot tape loading initialization |
| `1` | `GAME_LOADING` | `LoadingRun` | [`loading.asm`](include/resources/loading.asm) | Per-frame tape loader animation & decode |
| `2` | `GAME_RUN` | `GameRun` | [`gamestatus.asm`](include/resources/gamestatus.asm) | Active gameplay loop (player, actors, blits, slow mode) |
| `3–6` | `LEVEL_*` | `LevelTransitionRun` | [`levelutils.asm`](include/resources/levelutils.asm) | Level init, screen wipes, hold, and reveals |
| `7–8` | `LEVEL_COMPLETE_*` | `LevelCompleteSetup/Run` | [`levelcomplete.asm`](include/resources/levelcomplete.asm) | Level victory summary and password screen |
| `9` | `TITLE_SETUP` | `TitleSetup` | [`titlescreen.asm`](include/resources/titlescreen.asm) | Title screen init (copper aurora, title logo) |
| `10` | `TITLE_RUN` | `TitleRun` | [`titlescreen.asm`](include/resources/titlescreen.asm) | Interactive title menu & background animation |
| `11–14` | `INSTR_*` | `InstrPage*Setup/Run` | [`instructions.asm`](include/resources/instructions.asm) | Multi-page how-to-play instruction booklet screens |
| `15–16` | `GAME_COMPLETE_*` | `GameCompleteSetup/Run` | [`gamecomplete.asm`](include/resources/gamecomplete.asm) | Game completion ending cinematic screen |

---

## Asset & Level Pipeline

All game assets are processed deterministically via scripts in [`tools/`](tools/):

1. **Level Authoring (`export_level.py`)**:
   - Converts Tiled `.tmx` maps (`assets/Levels/Level_01.tmx`) into planar Amiga data.
   - Outputs:
     - 16-colour planar raw tileset (`FourSeasons.tiles_176x256.raw`) and blitter mask (`.msk`).
     - Multi-layer binary maps: `Level_01-background.map`, `Level_01-foreground.map`, `Level_01-water.map`, and composite `Level_01.map`.
     - 1D logic collision map (`Level_01-gamemap.bin`).
     - 68000 assembly definitions (`level_01_entities.asm`) specifying player spawns, patrol paths, triggers, and enemy spawn tables.

2. **Player BOB Pipeline (`convert_player_bob.py`)**:
   - Processes player frame grids into 16-colour, 4-bitplane raw graphic sheets (`player_bobs_64x576.raw`) and matching blitter masks (`.msk`).
   - Exports contact sheets (`player_bobs_preview.png`) for visual inspection.

3. **ZX0 Decompression (`zx0_faster.asm` & `zx0.exe`)**:
   - Compresses title and overlay assets using Einar Saukas' ZX0 format (v2).
   - Real-time 68000 decompression into Chip RAM buffers with high speed and low overhead.

---

## Repository Structure

```
.
├── build.ps1                       # Primary automated build & sync script
├── main.asm                        # Entry point, memory sections, main loop, VBlank ISR
├── assets/
│   ├── Levels/                     # Tiled .tmx levels and compiled binary maps
│   ├── graphics/
│   │   ├── sprites/                # Player BOB raw/msk files and contact preview
│   │   ├── tiles/                  # 16x16 raw tilesets and blitter masks
│   │   └── title/                  # Title screen logo raw and palette files
│   └── music/                      # ProTracker modules (10kdub.mod, supremacy_title.mod)
├── include/resources/
│   ├── system.asm                  # OS takeover, vector saves, and SystemRestore
│   ├── gamestatus.asm              # State machine dispatcher, GameRun mainline & slow mode
│   ├── tilemap.asm                 # Blitter-based tile rendering, camera & debug overlay HUD
│   ├── levelutils.asm              # Level initialisation, transitions, and entity placement
│   ├── level_01_entities.asm       # Auto-generated level spawns & entity descriptors
│   ├── player.asm / actors.asm     # Player BOB movement physics, ladders, and enemy state machines
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
* **On-Screen Diagnostic Overlay:** Press **D** or **S** to view live camera coordinates, player X/Y tile and sub-tile positions, action state, direction, active enemy count, waterline row, and current loop speed mode (`RUN` or `SLOW`).
* **Frame Step Debugger:** Press **S** to halt execution and inspect animations, collision logic, and enemy patrol behaviors frame-by-frame with the **A** key.
