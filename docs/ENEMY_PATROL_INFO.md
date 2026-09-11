# Enemy Dynamic Patrol & Sub-Pixel Blitter System

This document details the architecture, data structures, update loop, and Blitter mechanics implemented for active enemy patrolling, speed handling, frame animations, and sub-pixel cookie-cut rendering in *Alien Containment*.

---

## 1. Overview & Architecture

Enemies in *Alien Containment* are defined statically in Tiled maps (`assets/Levels/Level_XX.tmx`) and exported into spawn tables (`Level_XX_EnemyList`). At level initialization, these records are copied into a dynamic RAM array (`ActiveEnemies`). Every VBlank tick, the engine updates their patrol movement, advances their animations, erases their previous footprints from the display buffer, and cookie-cut blits them with hardware barrel shifting.

```
+-------------------------------------------------------------+
| Tiled Map (.tmx) -> Level_XX_EnemyList (Static Spawn Table) |
+-------------------------------------------------------------+
                              │
                              ▼ Level Load (LevelInitEnemies)
+-------------------------------------------------------------+
| ActiveEnemies[16] (Fast RAM / Variables Block)              |
| Tracks: X, Y, Direction, Speed, Patrol Bounds, Prev Pos     |
+-------------------------------------------------------------+
                              │
               ┌──────────────┴──────────────┐
               ▼ (Per-Frame GameRun Tick)     ▼ (Per-Frame Blit)
+-----------------------------+ +-----------------------------+
| 1. Erase Previous Footprint | | 3. Viewport Y Culling       |
|    (Restore from pristine   | | 4. Barrel Shift (X & 15)    |
|     NonDisplayScreen)       | | 5. Cookie-Cut Blit ($0FCA)  |
| 2. X += Direction * Speed   | |    2 words wide (32px)      |
|    Bounce off Patrol Bounds | |    4 bitplanes interleaved  |
+-----------------------------+ +-----------------------------+
```

---

## 2. Data Structures & Variables

### Constants & Structure Offsets (`include/resources/const.asm`)

```m68k
; Runtime Active Enemy Structure Offsets (in Variables block)
MAX_ACTIVE_ENEMIES       = 16
ei_Type                  = 0       ; Enemy Type (1..8, 0 = inactive)
ei_X                     = 2       ; Current X pixel position (0..319)
ei_Y                     = 4       ; Current Y pixel position (0..671)
ei_Direction             = 6       ; Direction (+1 = right, -1 = left)
ei_Speed                 = 8       ; Speed (pixels per frame)
ei_PatrolMinX            = 10      ; Left patrol boundary (pixel X)
ei_PatrolMaxX            = 12      ; Right patrol boundary (pixel X)
ei_AnimFrame             = 14      ; Current animation frame (0..3)
ei_PrevX                 = 16      ; Previous drawn X pixel position
ei_PrevY                 = 18      ; Previous drawn Y pixel position
ei_Drawn                 = 20      ; 1 if previously drawn and needs erase, 0 otherwise
ei_PAD                   = 22      ; word align
ei_SIZEOF                = 24
```

### Global Variables (`include/resources/variables.asm`)

```m68k
ActiveEnemyCount:     rs.w    1                             ; number of active enemies (0..16)
ActiveEnemies:        rs.b    ei_SIZEOF*MAX_ACTIVE_ENEMIES  ; runtime enemy instances array
```

---

## 3. Subsystem Breakdown

### A. Level Initialization (`LevelInitEnemies` in `levelutils.asm`)
- Clears the `ActiveEnemies` array.
- Reads records from `CurrentLevelDef -> LevelDef_EnemyList`.
- Initializes each active enemy instance with spawn coordinates $(X, Y)$, default moving direction ($+1$), patrol range $[MinX .. MaxX]$, and speed.

### B. Erasing Previous Footprints (`TilemapEraseEnemy` in `tilemap.asm`)
Because enemies move across arbitrary pixel coordinates, they cannot leave trails on the screen. Before moving or redrawing:
- Computes screen destination byte offset from previous coordinates:
  $$\text{Offset} = (\text{PrevY} \times 160) + \left(\lfloor\frac{\text{PrevX}}{16}\rfloor \times 2\right)$$
- If $\text{PrevX} \pmod{16} == 0$, performs a **1-word wide (16px)** restore blit ($D = A$).
- If $\text{PrevX} \pmod{16} \neq 0$, performs a **2-word wide (32px)** restore blit ($D = A$).
- Copies pristine pixels directly from `NonDisplayScreen` to `DisplayScreen`.

### C. Movement & Animation (`TilemapUpdateEnemies` in `tilemap.asm`)
- **Horizontal Movement**: $\text{ei\_X} += \text{ei\_Direction} \times \text{ei\_Speed}$.
- **Turnaround Detection**:
  - If $\text{ei\_X} \ge \text{ei\_PatrolMaxX} \implies \text{ei\_Direction} = -1$
  - If $\text{ei\_X} \le \text{ei\_PatrolMinX} \implies \text{ei\_Direction} = +1$
- **Animation Cycle**: Advances `ei_AnimFrame = (ei_AnimFrame + 1) & 3` every 8 frames using `TickCounter(a5)`.

### D. Sub-Pixel Cookie-Cut Blitting (`TilemapDrawEnemySubPixel` in `tilemap.asm`)
- **Viewport Culling**: Checks if $\text{CameraY} - 16 \le \text{ei\_Y} \le \text{CameraY} + 216$. Off-screen enemies are skipped.
- **Source Frame Pointer**:
  $$\text{SourceOffset} = (\text{ei\_Type} - 1) \times 512 + (\text{ei\_AnimFrame} \times 2)$$
- **Barrel Shift**:
  - $\text{Shift} = \text{ei\_X} \pmod{16}$
  - `BLTCON0 = (Shift << 12) | $0FCA`
  - `BLTCON1 = (Shift << 12)`
  - `BLTAFWM = $FFFF`, `BLTALWM = $0000`
- **Modulos & Width**:
  - Source Sheet Modulo (`BLTAMOD`, `BLTBMOD`): $8 - 4 = 4$ bytes
  - Screen Buffer Modulo (`BLTCMOD`, `BLTDMOD`): $40 - 4 = 36$ bytes
  - Blit Size: 64 lines ($16 \text{ rows} \times 4 \text{ planes}$) by **2 words wide** (32px).
- **History Tracking**: Stores current $(X, Y)$ into `ei_PrevX` / `ei_PrevY` and sets `ei_Drawn = 1`.

---

## 4. Modified Files Summary

| File | Changes Made |
| :--- | :--- |
| **`include/resources/const.asm`** | Added `MAX_ACTIVE_ENEMIES` and `ei_*` struct offsets (24-byte layout). |
| **`include/resources/variables.asm`** | Added `ActiveEnemyCount` and `ActiveEnemies` storage. |
| **`include/resources/levelutils.asm`** | Added `LevelInitEnemies` routine and integrated call in `LevelLoad`. |
| **`include/resources/gamestatus.asm`** | Added `TilemapUpdateEnemies` call to `GameRun` per-frame loop. |
| **`include/resources/tilemap.asm`** | Removed static pass from `TilemapDrawViewport`; implemented `TilemapUpdateEnemies`, `TilemapEraseEnemy`, and `TilemapDrawEnemySubPixel`. |
