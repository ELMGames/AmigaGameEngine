# Copper Background Gradient & Parallax Architecture (Alien Containment)

This document details the architecture, mathematical model, and assembly implementation for the **Copper Sky Gradient** and **1/2-Speed Parallax Background** in *Alien Containment*.

---

## 1. Concept & Visual Goal

In classic Amiga arcade platformers (such as *Rainbow Islands*, *Shadow of the Beast*, and *Ruff 'n' Tumble*), distant backgrounds create a sense of scale and depth by moving slower than the foreground playfield.

By utilizing the **Amiga OCS/ECS Copper coprocessor**, we can change the hardware background color register (`COLOR00`) on every scanline with **zero bitplane memory overhead** and **zero Blitter cost**. Any transparent pixel (Color index 0) in the tilemap reveals this smooth, multi-colored Copper gradient.

Coupling this gradient with a **1/2 vertical parallax factor** creates a convincing illusion of depth:
- **Foreground Map**: Moves at 1:1 speed with the camera.
- **Background Sky**: Moves at 1:2 speed (`SkyY = CameraY >> 1`).

---

## 2. Mathematical Breakdown & Dimensions

### Level 1 Geometry
- **Map Dimensions**: 20 columns x 42 rows (16x16 pixel tiles).
- **Total Map Height**: 42 x 16 = **672 pixels**.
- **Visible Screen Viewport**: 200 scanlines (PAL display window lines `$2c` through `$f3` / lines 44 to 243).
- **Camera Travel Range**:
  `MaxCameraY = 672 - 200 = 472 pixels` (0 <= TilemapCameraY <= 472)
  - `CameraY = 472`: Level bottom / player spawn area.
  - `CameraY = 0`: Level summit.

### Parallax Travel & Buffer Sizing
With a 1/2 speed factor, the sky viewport moves 1 pixel for every 2 pixels of camera climbing:
`SkyScrollRange = MaxCameraY / 2 = 472 / 2 = 236 pixels`

To always display 200 scanlines without wrapping or clipping at any camera position:
`TotalGradientHeight = ViewportHeight (200) + SkyScrollRange (236) = 436 pixels`

### Source Asset Compatibility
- **Image**: `assets/graphics/copper/copper_sky.png`
- **Asset Size**: 64 x 512 RGB pixels.
- **Fit**: The 512-pixel height comfortably exceeds the required 436 pixels (512 >= 436). No stretching, distortion, or artificial padding is needed.

```
+------------------------------------+  y = 0  (Deep Indigo / Night)
| Visible Window at Summit (CamY=0)  |  [0..199]
| [ 200 scanlines ]                  |
+------------------------------------+  y = 200
|                                    |
| Parallax Scroll Travel: 236 pixels |
|                                    |
+------------------------------------+  y = 236
| Visible Window at Bottom (CamY=472)|  [236..435]
| [ 200 scanlines ]                  |
+------------------------------------+  y = 436 (Warm Sunset / Gold)
| (Unused headroom: 76 pixels)       |
+------------------------------------+  y = 512
```

---

## 3. Copper List Layout (`copperlists.asm`)

Inside `cpTest` (the main gameplay Copper list in Chip RAM), a dedicated `cpGameSky` sub-block is placed right after `cpPal`:

### Scanline Bands: 200 Scanlines vs 100 2-Line Bands
- **200 Scanlines (1:1 precision)**:
  - Requires 200 `WAIT` + `MOVE` pairs (200 x 4 words = 1600 bytes).
  - Full per-scanline color fidelity.
- **100 Bands (2 scanlines per band)**:
  - Requires 100 `WAIT` + `MOVE` pairs (800 bytes).
  - Halves the CPU write bandwidth per frame.

### Assembly Structure
```m68k
cpGameSky:
    ; Lines $2c..$f3 (PAL lines 44..243)
    ; Each entry: WAIT (line, pos), MOVE COLOR00, color
    dc.w    $2c07,$fffe, COLOR00,$0000
    dc.w    $2d07,$fffe, COLOR00,$0000
    dc.w    $2e07,$fffe, COLOR00,$0000
    ; ... 200 scanlines total ...
    dc.w    $f307,$fffe, COLOR00,$0000
```

---

## 4. Parallax Update Routine (`tilemap.asm`)

Each time the camera moves (or during `TilemapInit`), `TilemapUpdateCopperSky` calculates the parallax offset and updates the Copper list data words:

```m68k
;==============================================================================
; TilemapUpdateCopperSky - Update Copper Sky with 1/2 Parallax Speed
;
; Computes SkyY = TilemapCameraY >> 1 (0..236), then copies 200 words from
; CopperSkyTable[SkyY .. SkyY+199] into the cpGameSky Copper list entries.
;
; Destroys: d0, d7, a0, a1
;==============================================================================
TilemapUpdateCopperSky:
    move.w      TilemapCameraY(a5),d0
    lsr.w       #1,d0                   ; d0 = SkyY = CameraY / 2 (0..236) -> 1/2 parallax!
    add.w       d0,d0                   ; d0 = byte offset into word table
    lea         CopperSkyTable,a0
    adda.w      d0,a0                   ; a0 -> slice of 200 words for current viewport

    lea         cpGameSky+4+2,a1        ; a1 -> first COLOR00 data word in cpGameSky
    moveq       #(200/4)-1,d7           ; unrolled: 4 scanlines per iteration
.sky_loop:
    move.w      (a0)+,(a1)
    move.w      (a0)+,4(a1)
    move.w      (a0)+,8(a1)
    move.w      (a0)+,12(a1)
    lea         16(a1),a1               ; advance by 4 copper instructions (16 bytes)
    dbra        d7,.sky_loop
    rts
```

### Performance Impact
- **CPU Instructions**: ~50 loops x 7 cycles = ~350 cycles.
- **Frame Budget Percentage**: Less than **0.5%** of a single 50 Hz PAL frame budget (70,937 cycles available per frame on a stock 68000).
- **Tearing-Free**: Writes directly into the inactive slice of the Copper list before beam scan.

---

## 5. Asset Pipeline Integration

A Python export script (integrated with `convert_assets.py` or `export_tiled_levels.py`):
1. Reads `assets/graphics/copper/copper_sky.png`.
2. Converts the top 436 (or all 512) rows into Amiga 12-bit `$0RGB` words:
   `AmigaColor = ((R >> 4) << 8) | ((G >> 4) << 4) | (B >> 4)`
3. Generates binary file `assets/graphics/copper/copper_sky.bin` (or `copper_sky_data.asm`).

---

## 6. Implementation Checklist

- [ ] **Asset Tooling**: Add `convert_copper_sky.py` / integrate into asset build script.
- [ ] **Table Definition**: Add `CopperSkyTable` binary include in `main.asm` (`data_fast` section).
- [ ] **Copper List**: Add `cpGameSky` (200 lines) to `cpTest` in `copperlists.asm`.
- [ ] **Engine Update**: Add `TilemapUpdateCopperSky` to `tilemap.asm`.
- [ ] **Camera Hooks**:
  - Call in `TilemapInit` (initial frame at spawn).
  - Call in `TilemapApplyCameraY` (on camera scroll events).
- [ ] **Verification**: Run in WinUAE and verify smooth twilight-to-night parallax gradient as player ascends.
