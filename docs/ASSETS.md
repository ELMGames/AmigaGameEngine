# Asset Pipeline & Graphics / Audio Manifest

## Complete Inventory of Source Inputs, Conversion Toolchains, Generated Binaries, and 68000 Assembly Inclusions
*A Systems Architecture and Production Reference for the Amiga Game Engine*

---

## 1. Architectural Overview & Asset Pipeline

In retro game development on the Commodore Amiga (Motorola 68000 CPU; OCS/ECS custom chipset: Agnus, Denise, Paula), asset management is strictly divided between **source authoring formats** (PNG images, Tiled `.tmx` maps, ProTracker `.mod` music modules, PCM `.wav` samples, and TrueType `.ttf` fonts) and **Amiga hardware-native binary formats** (bitplane-interleaved `.raw` graphics, 1-bit cookie-cut `.msk` blitter masks, 12-bit RGB444 color words, and raw tile index maps).

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ASSET PRODUCTION PIPELINE                          │
├──────────────────────┬─────────────────────────┬────────────────────────────┤
│ Modern Authoring     │ Python Toolchain        │ Amiga Target Data          │
│ (PNG / TMX / WAV)    │ (tools/*.py)            │ (.raw / .msk / .map / .asm)│
├──────────────────────┼─────────────────────────┼────────────────────────────┤
│ Level_01.tmx         │ export_level.py         │ Level_01-*.map, GameMap    │
│ four-seasons.png     │ export_level.py         │ FourSeasons.tiles (raw/msk)│
│ player_master.png    │ convert_player_bob.py   │ player_bobs (raw/msk/white)│
│ enemies_16x16.png    │ convert_enemies.py      │ enemies_64x128 (raw/msk)   │
│ dizzy_stars.png      │ convert_enemies.py      │ dizzy_stars_64x16 (raw/msk)│
│ animals_16x16.png    │ convert_animals.py      │ animals_64x48 (raw/msk)    │
│ copper_sky.png       │ convert_assets.py       │ copper_sky.bin             │
│ AGE_title.png        │ convert_assets.py       │ AGE_title.raw / .pal       │
│ Michroma-Regular.ttf │ generate_michroma.py    │ michroma_font.bin / .asm   │
└──────────────────────┴─────────────────────────┴────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          VASM / VLINK AMIGA TARGET                          │
├──────────────────────────────────────┬──────────────────────────────────────┤
│ CHIP RAM (data_chip)                 │ FAST RAM (data_fast / main,code)     │
│ - Blitter source bitmaps & masks     │ - CPU-read binary maps & collision   │
│ - Paula audio DMA samples & modules  │ - Hardware sprite data & palettes    │
│ - Active & static framebuffers       │ - Trigonometric & easing tables      │
└──────────────────────────────────────┴──────────────────────────────────────┘
```

Every build executed via [`build.ps1`](file:///F:/GitHub/AmigaGameEngine/build.ps1) verifies and regenerates intermediate binary assets prior to running the `vasmm68k_mot` assembler and `vlink` linker.

---

## 2. Level Geometry, Tilemaps & Physical Collision Maps

### 2.1 Source Inputs
* **Tiled Level Map**: [`assets/Levels/Level_01.tmx`](file:///F:/GitHub/AmigaGameEngine/assets/Levels/Level_01.tmx)
  * Format: XML/CSV map file (width: 20 tiles, height: 42 tiles, tile size: 16×16 pixels).
  * Layer Architecture:
    * `scenery` (ID 1): Static distant backdrop tiles (rocks, soil).
    * `platforms` (ID 2): Walkable solid ledges and stone blocks.
    * `ladders` (ID 3): Climbable ladder shafts.
    * `entities` (ID 4): Dynamic entity spawn markers (Player start, enemies, animal friends, push blocks, oxygen refills).
    * `foreground` (ID 5): Overlapping canopy leaves and tree trunks.
    * `water` (ID 6): Semi-transparent rising water surface.
  * Map Properties:
    * `initial_camera_y = 464`
    * `initial_row = 29`
    * `music = "LevelMod"`
    * `title = "CANOPY RESCUE"`
    * `sub_title = "RESCUE ALL 6 ANIMAL FRIENDS"`
* **Master Tileset Definition**: [`assets/graphics/tiles/AmigaGameEngine.tsx`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/tiles/AmigaGameEngine.tsx)
  * Format: Tiled XML tileset definition declaring tile properties (semi-transparent water, ladder types, crate types).
* **Master Tileset Graphics**: [`assets/graphics/tiles/four-seasons-tileset.png`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/tiles/four-seasons-tileset.png)
  * Format: 176×256 pixels, 11 columns $\times$ 16 rows = **176 tiles** total.

### 2.2 Conversion Toolchain
* **Script**: [`tools/export_level.py`](file:///F:/GitHub/AmigaGameEngine/tools/export_level.py)
* **Execution**: Triggered automatically in [`build.ps1`](file:///F:/GitHub/AmigaGameEngine/build.ps1):
  ```powershell
  python tools/export_level.py assets/Levels/Level_01.tmx
  ```
* **Operations**:
  1. Parses layer data and extracts entity coordinates, patrol bounds, and spawn attributes.
  2. Quantizes and converts `four-seasons-tileset.png` into 4-bitplane interleaved raw graphics and masks.
  3. Emits discrete layer maps, a merged composite map, and an 840-byte 1D physical `GameMap` collision binary.
  4. Generates assembly definitions in [`include/resources/level_01_entities.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/level_01_entities.asm).

### 2.3 Generated Artifacts
* [`FourSeasons.tiles_176x256.raw`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/tiles/FourSeasons.tiles_176x256.raw) (22,560 bytes): 4-bitplane interleaved tile graphics.
* [`FourSeasons.tiles_176x256.msk`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/tiles/FourSeasons.tiles_176x256.msk) (22,528 bytes): 1-bit cookie-cut Blitter mask.
* [`Level_01-background.map`](file:///F:/GitHub/AmigaGameEngine/assets/Levels/Level_01-background.map) (1,688 bytes): Scenery tile index words.
* [`Level_01-platform.map`](file:///F:/GitHub/AmigaGameEngine/assets/Levels/Level_01-platform.map) (1,688 bytes): Platform tile index words.
* [`Level_01-ladder.map`](file:///F:/GitHub/AmigaGameEngine/assets/Levels/Level_01-ladder.map) (1,688 bytes): Ladder tile index words.
* [`Level_01-foreground.map`](file:///F:/GitHub/AmigaGameEngine/assets/Levels/Level_01-foreground.map) (1,688 bytes): Foreground tile index words.
* [`Level_01-water.map`](file:///F:/GitHub/AmigaGameEngine/assets/Levels/Level_01-water.map) (1,688 bytes): Water tile index words.
* [`Level_01.map`](file:///F:/GitHub/AmigaGameEngine/assets/Levels/Level_01.map) (1,688 bytes): Merged composite map.
* [`Level_01-gamemap.bin`](file:///F:/GitHub/AmigaGameEngine/assets/Levels/Level_01-gamemap.bin) (840 bytes): 20×42 1D byte array of `BLOCK_xxx` collision attributes.
* [`include/resources/level_01_entities.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/level_01_entities.asm) (Assembly definitions and `Level_01_Def` struct).

### 2.4 Assembly Inclusion
* **In [`include/resources/level_01_entities.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/level_01_entities.asm#L16-L61)**:
  ```assembly
  Level_01_BackgroundMap: incbin "assets/Levels/Level_01-background.map"
  Level_01_PlatformMap:   incbin "assets/Levels/Level_01-platform.map"
  Level_01_LadderMap:     incbin "assets/Levels/Level_01-ladder.map"
  Level_01_ForegroundMap: incbin "assets/Levels/Level_01-foreground.map"
  Level_01_WaterMap:      incbin "assets/Levels/Level_01-water.map"
  Level_01_CompositeMap:  incbin "assets/Levels/Level_01.map"
  Level_01_GameMap:       incbin "assets/Levels/Level_01-gamemap.bin"
  ```
* **In [`main.asm`](file:///F:/GitHub/AmigaGameEngine/main.asm#L568-L573) (`data_chip`)**:
  ```assembly
  GameTilesRaw:           incbin "assets/graphics/tiles/FourSeasons.tiles_176x256.raw"
  GameTilesMsk:           incbin "assets/graphics/tiles/FourSeasons.tiles_176x256.msk"
  ```

---

## 3. Player Character Blitter Objects (BOBs)

### 3.1 Source Inputs
* **Master Spritesheet**: [`assets/graphics/sprites/player_master_128x144.png`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/sprites/player_master_128x144.png)
  * Format: 128×144 RGBA PNG.
  * Structure: 24 distinct frames arranged in 6 rows $\times$ 4 frames (each cell 32×24 px, 24×24 active content):
    * Row 0 (Frames 0..3): Idle standing (facing right).
    * Row 1 (Frames 4..7): Walk cycle (facing right).
    * Row 2 (Frames 8..11): Cane attack / reach (facing right).
    * Row 3 (Frames 12..15): Death collapse animation.
    * Row 4 (Frames 16..19): Ladder climbing (rear view).
    * Row 5 (Frames 20..23): Flailing fall animation.
  * *Note: Left-facing frames are generated dynamically at engine startup in Chip RAM by `PlayerInitFlippedSprites`.*

### 3.2 Conversion Toolchain
* **Script**: [`tools/convert_player_bob.py`](file:///F:/GitHub/AmigaGameEngine/tools/convert_player_bob.py)
* **Execution**: Triggered in [`build.ps1`](file:///F:/GitHub/AmigaGameEngine/build.ps1):
  ```powershell
  python tools/convert_player_bob.py
  ```

### 3.3 Generated Artifacts
* [`player_bobs_128x144.raw`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/sprites/player_bobs_128x144.raw) (9,216 bytes): 4-bitplane interleaved raw graphic data (144 scanlines $\times$ 64 bytes/line).
* [`player_bobs_128x144.msk`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/sprites/player_bobs_128x144.msk) (9,216 bytes): 4-bitplane cookie-cut Blitter mask.
* [`player_bobs_128x144_white.raw`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/sprites/player_bobs_128x144_white.raw) (9,216 bytes): Pure-white hit-flash graphics.
* [`player_bobs_preview.png`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/sprites/player_bobs_preview.png): Visual contact sheet.

### 3.4 Assembly Inclusion
* **In [`main.asm`](file:///F:/GitHub/AmigaGameEngine/main.asm#L588-L598) (`data_chip`)**:
  ```assembly
  PlayerRaw:      incbin "assets/graphics/sprites/player_bobs_128x144.raw"
  PlayerMsk:      incbin "assets/graphics/sprites/player_bobs_128x144.msk"
  PlayerWhiteRaw: incbin "assets/graphics/sprites/player_bobs_128x144_white.raw"
  ```

---

## 4. Enemies & Stunned Dizzy Stars BOBs

### 4.1 Source Inputs
* **Enemy Master Spritesheet**: [`assets/graphics/enemies/enemies_16x16.png`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/enemies/enemies_16x16.png)
  * Format: 64×128 RGBA PNG (8 enemy types $\times$ 4 walk frames):
    * Row 0: Cyan Slime
    * Row 1: Red Slime
    * Row 2: Wasp
    * Row 3: Red Bat
    * Row 4: Green Cyclops
    * Row 5: Purple Octo
    * Row 6: Snail
    * Row 7: Blue Ghost
* **Dizzy Stars Spritesheet**: [`assets/graphics/enemies/dizzy_stars_64x16.png`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/enemies/dizzy_stars_64x16.png)
  * Format: 64×16 RGBA PNG (4 orbiting star animation frames for stunned enemies).

### 4.2 Conversion Toolchain
* **Script**: [`tools/convert_enemies.py`](file:///F:/GitHub/AmigaGameEngine/tools/convert_enemies.py)
* **Execution**: Triggered in [`build.ps1`](file:///F:/GitHub/AmigaGameEngine/build.ps1):
  ```powershell
  python tools/convert_enemies.py
  ```

### 4.3 Generated Artifacts
* [`enemies_64x128.raw`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/enemies/enemies_64x128.raw) (4,096 bytes): 4-bitplane interleaved raw BOB graphics.
* [`enemies_64x128.msk`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/enemies/enemies_64x128.msk) (4,096 bytes): Cookie-cut Blitter masks.
* [`enemies_64x128_white.raw`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/enemies/enemies_64x128_white.raw) (4,096 bytes): Pure-white hit-flash graphics.
* [`dizzy_stars_64x16.raw`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/enemies/dizzy_stars_64x16.raw) (512 bytes): 4-bitplane interleaved raw graphics.
* [`dizzy_stars_64x16.msk`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/enemies/dizzy_stars_64x16.msk) (512 bytes): Blitter mask for dizzy stars.
* [`dizzy_stars_preview.png`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/enemies/dizzy_stars_preview.png): Visual verification preview.

### 4.4 Assembly Inclusion
* **In [`main.asm`](file:///F:/GitHub/AmigaGameEngine/main.asm#L576-L606) (`data_chip`)**:
  ```assembly
  EnemySpritesRaw:      incbin "assets/graphics/enemies/enemies_64x128.raw"
  EnemySpritesWhiteRaw: incbin "assets/graphics/enemies/enemies_64x128_white.raw"
  EnemySpritesMsk:      incbin "assets/graphics/enemies/enemies_64x128.msk"
  DizzyStarsRaw:        incbin "assets/graphics/enemies/dizzy_stars_64x16.raw"
  DizzyStarsMsk:        incbin "assets/graphics/enemies/dizzy_stars_64x16.msk"
  ```

---

## 5. Animal Friends BOBs

### 5.1 Source Inputs
* **Animal Master Spritesheet**: [`assets/graphics/animals/animals_16x16.png`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/animals/animals_16x16.png)
  * Format: 64×48 RGBA PNG.
  * Contents: 3 rescue animal types $\times$ 4 animation frames:
    * Row 0: Dog 1 (Tan Dog / Shiba Inu)
    * Row 1: Dog 2 (White Puppy)
    * Row 2: Duckling (Side-view jumping duckling)

### 5.2 Conversion Toolchain
* **Script**: [`tools/convert_animals.py`](file:///F:/GitHub/AmigaGameEngine/tools/convert_animals.py)
* **Execution**: Triggered in [`build.ps1`](file:///F:/GitHub/AmigaGameEngine/build.ps1):
  ```powershell
  python tools/convert_animals.py
  ```

### 5.3 Generated Artifacts
* [`animals_64x48.raw`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/animals/animals_64x48.raw) (1,536 bytes): 4-bitplane interleaved raw graphics.
* [`animals_64x48.msk`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/animals/animals_64x48.msk) (1,536 bytes): 4-bitplane cookie-cut Blitter masks.
* [`animals_preview.png`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/animals/animals_preview.png), `dog1_anim.gif`, `dog2_anim.gif`, `duckling_anim.gif`: Visual verification previews.

### 5.4 Assembly Inclusion
* **In [`main.asm`](file:///F:/GitHub/AmigaGameEngine/main.asm#L608-L614) (`data_chip`)**:
  ```assembly
  AnimalSpritesRaw: incbin "assets/graphics/animals/animals_64x48.raw"
  AnimalSpritesMsk: incbin "assets/graphics/animals/animals_64x48.msk"
  ```

---

## 6. Hardware Sprites & HUD Graphics

### 6.1 Source Inputs & Binaries
* **Hardware Sprite Palette**: [`assets/graphics/sprites/sprites.pal`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/sprites/sprites.pal)
  * Format: 32 bytes (16 big-endian $0RGB words for OCS registers `COLOR16..COLOR31`).
* **Compressed Hardware Sprites**: [`assets/graphics/sprites/player_hwsprites.zx0`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/sprites/player_hwsprites.zx0)
  * Format: ZX0-compressed data containing lives counter badges, oxygen indicator badges, and bubble sprites.

### 6.2 Assembly Inclusion & Runtime Decompression
* **In [`main.asm`](file:///F:/GitHub/AmigaGameEngine/main.asm#L465-L509) (`data_fast`)**:
  ```assembly
  SpritePal:               incbin "assets/graphics/sprites/sprites.pal"
  PlayerHWSprites_FastMem: incbin "assets/graphics/sprites/player_hwsprites.zx0"
  ```
* At startup, `CopyOverlayAssets` ([`loading.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/loading.asm)) uses `zx0_decompress` to expand `PlayerHWSprites_FastMem` from Fast RAM into the Chip RAM buffer `PlayerHWSprites`.

---

## 7. Copper Background & Sky Gradient

### 7.1 Source Inputs
* **Sky Gradient PNG**: [`assets/graphics/copper/copper_sky.png`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/copper/copper_sky.png)
  * Format: 24-bit RGB PNG containing vertical gradient bars.

### 7.2 Conversion Toolchain
* **Script**: [`tools/convert_assets.py`](file:///F:/GitHub/AmigaGameEngine/tools/convert_assets.py) (`export_copper_sky`)

### 7.3 Generated Artifacts
* [`assets/graphics/copper/copper_sky.bin`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/copper/copper_sky.bin) (1,024 bytes): 512 big-endian $0RGB color words representing 512 scanline colors for 1/2 vertical parallax in `cpGameSky`.

### 7.4 Assembly Inclusion
* **In [`main.asm`](file:///F:/GitHub/AmigaGameEngine/main.asm#L468-L470) (`data_fast`)**:
  ```assembly
  CopperSkyTable: incbin "assets/graphics/copper/copper_sky.bin"
  ```

---

## 8. Title Screen & Loading Screen Artwork

### 8.1 Source Inputs
* **Title Logo Image**: [`assets/graphics/title/AGE_title.png`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/title/AGE_title.png) (288×64 pixels, 8-color logo).
* **Loading Artwork**: `template.raw`, `template.pal` (5-bitplane interleaved loading artwork).

### 8.2 Conversion Toolchain
* **Script**: [`tools/convert_assets.py`](file:///F:/GitHub/AmigaGameEngine/tools/convert_assets.py) (`export_planar`) and external `amigeconv`/`salvador` (ZX0).

### 8.3 Generated Artifacts
* [`assets/graphics/title/AGE_title.raw`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/title/AGE_title.raw) (6,912 bytes): 3-bitplane planar bitmap.
* [`assets/graphics/title/AGE_title.pal`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/title/AGE_title.pal) (16 bytes): 8 color words.
* [`assets/graphics/title/template.zx0`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/title/template.zx0): ZX0-compressed 5-bitplane loading image.
* [`assets/graphics/title/template.pal`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/title/template.pal) (64 bytes): 32-color palette.

### 8.4 Assembly Inclusion
* **In [`main.asm`](file:///F:/GitHub/AmigaGameEngine/main.asm#L540-L636) (`data_chip`)**:
  ```assembly
  TitleLogoRaw: incbin "assets/graphics/title/AGE_title.raw"
  TitleLogoPal: incbin "assets/graphics/title/AGE_title.pal"
  LoadingPal:   incbin "assets/graphics/title/template.pal"
  LoadingRawZ:  incbin "assets/graphics/title/template.zx0"
  ```

---

## 9. Audio Subsystem (Music Modules & Sound FX)

### 9.1 Source Inputs
* **ProTracker Modules**:
  * Title Music: [`assets/music/supremacy_title.mod`](file:///F:/GitHub/AmigaGameEngine/assets/music/supremacy_title.mod) (Standard 4-channel ProTracker format).
  * In-Game Music: [`assets/music/10kdub.mod`](file:///F:/GitHub/AmigaGameEngine/assets/music/10kdub.mod) (Standard 4-channel ProTracker format).
* **ZX Spectrum Tape Loading PCM Samples**:
  * [`assets/fx/zx_audio_data.wav`](file:///F:/GitHub/AmigaGameEngine/assets/fx/zx_audio_data.wav) (10,480 bytes): 8-bit signed mono PCM.
  * [`assets/fx/zx_audio_colors.wav`](file:///F:/GitHub/AmigaGameEngine/assets/fx/zx_audio_colors.wav) (9,552 bytes): 8-bit signed mono PCM.
  * [`assets/fx/zx_audio_screenname.wav`](file:///F:/GitHub/AmigaGameEngine/assets/fx/zx_audio_screenname.wav) (26,936 bytes): 8-bit signed mono PCM.

### 9.2 Assembly Inclusion
* **In [`main.asm`](file:///F:/GitHub/AmigaGameEngine/main.asm#L552-L565) (`data_chip`)**:
  ```assembly
  TitleScreenMusicMod: incbin "assets/music/supremacy_title.mod"
  LevelMod:            incbin "assets/music/10kdub.mod"
  ```
* **In [`include/resources/zxsfx.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/zxsfx.asm#L9-L26) (`data_chip`)**:
  ```assembly
  ZxAudioDataLoad_PCM:   incbin "assets/fx/zx_audio_data.wav"
  ZxAudioColorLoad_PCM:  incbin "assets/fx/zx_audio_colors.wav"
  ZxAudioScreenName_PCM: incbin "assets/fx/zx_audio_screenname.wav"
  ```

---

## 10. Typography & Fonts

### 10.1 Source Inputs
* **Bitmap UI Font**: [`assets/font/font.bin`](file:///F:/GitHub/AmigaGameEngine/assets/font/font.bin) (768 bytes: 8×8 pixels, 1-bitplane, ASCII 32–127; 96 characters $\times$ 8 bytes).
* **Hero Text Placard Font**:
  * Source TTF: `assets/font/Michroma-Regular.ttf`
  * Converter: `assets/font/generate_michroma_font.py`
  * Generated Binary: [`assets/font/michroma_font.bin`](file:///F:/GitHub/AmigaGameEngine/assets/font/michroma_font.bin) (13,524 bytes: 49 scanlines high, 1-bitplane proportional hero text).
  * Generated Metadata: [`include/resources/michroma_font_data.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/michroma_font_data.asm).

### 10.2 Assembly Inclusion
* **In [`include/resources/copperlists.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/copperlists.asm#L543) (`data_chip`)**:
  ```assembly
  FontData:     incbin "assets/font/font.bin"
  ```
* **In [`include/resources/michroma_font_data.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/michroma_font_data.asm#L17) (`data_fast`)**:
  ```assembly
  MichromaFont: incbin "assets/font/michroma_font.bin"
  ```

---

## 11. Motion, Physics & Trigonometric Tables

### 11.1 Source Binaries
* **Quadratic Fall Easing**: [`assets/data/quadratic.bin`](file:///F:/GitHub/AmigaGameEngine/assets/data/quadratic.bin) (4,096 bytes: pre-calculated quadratic fall velocities).
* **Trigonometric Sine Wave**: [`assets/data/sin.bin`](file:///F:/GitHub/AmigaGameEngine/assets/data/sin.bin) (4,096 bytes: full-period 16-bit signed sine table).

### 11.2 Assembly Inclusion
* **In [`main.asm`](file:///F:/GitHub/AmigaGameEngine/main.asm#L455-L460) (`data_fast`)**:
  ```assembly
  Quadratic: incbin "assets/data/quadratic.bin"
  Sinus:     incbin "assets/data/sin.bin"
  ```

---

## 12. Master Asset Manifest Table

The following table provides a complete, authoritative index of every binary asset included in the assembled executable:

| Asset Identifier | Source File | Build Converter | Included Binary Artifact | Memory Section | Size (Bytes) |
| :--- | :--- | :--- | :--- | :---: | :---: |
| **Tileset Graphics** | `four-seasons-tileset.png` | `export_level.py` | `FourSeasons.tiles_176x256.raw` | `data_chip` | 22,560 |
| **Tileset Masks** | `four-seasons-tileset.png` | `export_level.py` | `FourSeasons.tiles_176x256.msk` | `data_chip` | 22,528 |
| **Level Scenery Map** | `Level_01.tmx` | `export_level.py` | `Level_01-background.map` | `data_fast` | 1,688 |
| **Level Platform Map**| `Level_01.tmx` | `export_level.py` | `Level_01-platform.map` | `data_fast` | 1,688 |
| **Level Ladder Map** | `Level_01.tmx` | `export_level.py` | `Level_01-ladder.map` | `data_fast` | 1,688 |
| **Level Foreground Map**| `Level_01.tmx`| `export_level.py` | `Level_01-foreground.map` | `data_fast` | 1,688 |
| **Level Water Map** | `Level_01.tmx` | `export_level.py` | `Level_01-water.map` | `data_fast` | 1,688 |
| **Composite Map** | `Level_01.tmx` | `export_level.py` | `Level_01.map` | `data_fast` | 1,688 |
| **Physical GameMap** | `Level_01.tmx` | `export_level.py` | `Level_01-gamemap.bin` | `data_fast` | 840 |
| **Player BOB Raw** | `player_master_128x144.png`| `convert_player_bob.py` | `player_bobs_128x144.raw` | `data_chip` | 9,216 |
| **Player BOB Mask** | `player_master_128x144.png`| `convert_player_bob.py` | `player_bobs_128x144.msk` | `data_chip` | 9,216 |
| **Player White Flash**| `player_master_128x144.png`| `convert_player_bob.py` | `player_bobs_128x144_white.raw` | `data_chip` | 9,216 |
| **Enemies BOB Raw** | `enemies_16x16.png` | `convert_enemies.py` | `enemies_64x128.raw` | `data_chip` | 4,096 |
| **Enemies BOB Mask** | `enemies_16x16.png` | `convert_enemies.py` | `enemies_64x128.msk` | `data_chip` | 4,096 |
| **Enemies White Flash**| `enemies_16x16.png` | `convert_enemies.py` | `enemies_64x128_white.raw` | `data_chip` | 4,096 |
| **Dizzy Stars Raw** | `dizzy_stars_64x16.png` | `convert_enemies.py` | `dizzy_stars_64x16.raw` | `data_chip` | 512 |
| **Dizzy Stars Mask** | `dizzy_stars_64x16.png` | `convert_enemies.py` | `dizzy_stars_64x16.msk` | `data_chip` | 512 |
| **Animals BOB Raw** | `animals_16x16.png` | `convert_animals.py` | `animals_64x48.raw` | `data_chip` | 1,536 |
| **Animals BOB Mask** | `animals_16x16.png` | `convert_animals.py` | `animals_64x48.msk` | `data_chip` | 1,536 |
| **Hardware Sprites** | `player_hwsprites.zx0` | (ZX0 packed) | `player_hwsprites.zx0` | `data_fast` | ~3,400 |
| **Sprite Palette** | `sprites.pal` | (Native $0RGB) | `sprites.pal` | `data_fast` | 32 |
| **Copper Sky Gradient**| `copper_sky.png` | `convert_assets.py` | `copper_sky.bin` | `data_fast` | 1,024 |
| **Title Logo Bitmap** | `AGE_title.png` | `convert_assets.py` | `AGE_title.raw` | `data_chip` | 6,912 |
| **Title Logo Palette**| `AGE_title.png` | `convert_assets.py` | `AGE_title.pal` | `data_chip` | 16 |
| **Loading Screen Image**| `template.raw` | (ZX0 packed) | `template.zx0` | `data_chip` | ~18,000 |
| **Loading Palette** | `template.pal` | (Native $0RGB) | `template.pal` | `data_chip` | 64 |
| **Title Music Mod** | `supremacy_title.mod` | (ProTracker) | `supremacy_title.mod` | `data_chip` | ~60,000 |
| **Level Music Mod** | `10kdub.mod` | (ProTracker) | `10kdub.mod` | `data_chip` | ~75,000 |
| **ZX Tape SFX: Data** | `zx_audio_data.wav` | (8-bit PCM) | `zx_audio_data.wav` | `data_chip` | 10,480 |
| **ZX Tape SFX: Color**| `zx_audio_colors.wav` | (8-bit PCM) | `zx_audio_colors.wav` | `data_chip` | 9,552 |
| **ZX Tape SFX: Name** | `zx_audio_screenname.wav`| (8-bit PCM) | `zx_audio_screenname.wav` | `data_chip` | 26,936 |
| **Bitmap UI Font** | `font.bin` | (1-bpl ASCII) | `font.bin` | `data_chip` | 768 |
| **Michroma Hero Font**| `Michroma-Regular.ttf`| `generate_michroma.py`| `michroma_font.bin` | `data_fast` | 13,524 |
| **Quadratic Easing** | `quadratic.bin` | (Math table) | `quadratic.bin` | `data_fast` | 4,096 |
| **Sine Table** | `sin.bin` | (Math table) | `sin.bin` | `data_fast` | 4,096 |
