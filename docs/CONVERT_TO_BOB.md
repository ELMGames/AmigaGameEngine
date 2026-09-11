# Converting the Player from Hardware Sprite to Blitter Object (BOB)
## Detailed Step-by-Step Implementation Guide for *Alien Containment*

---

## 1. Architectural Motivation & Problem Statement

### 1.1 The Depth Ordering Conflict in Single Playfield Mode
In *Alien Containment*, the engine operates in **Single Playfield Mode (4 bitplanes = 16 colors)** via `BPLCON0 = $4200`. Both the platform geometry (including ladder rungs) and the water layer (the rising semi-transparent wavefront) exist within the **exact same bitplane bitmap** in Chip RAM (`DisplayScreen`).

The Amiga Denise custom chip's priority register `BPLCON2` (`$DFF044`) operates strictly at the whole-playfield level:
* **`BPLCON2 = $0024` (Dry Priority)**: All hardware sprites (`SP01..SP67`) render **in front** of Playfield 1.
  * *Result*: The player is in front of the ladder rungs (correct), but also in front of the water (incorrect — the player walks on top of the flood).
* **`BPLCON2 = $0000` (Submerged Priority)**: Playfield 1 renders **in front** of all hardware sprites.
  * *Result*: The water renders in front of the player (correct), but the platform and ladder tiles ALSO render in front of the player (incorrect — ladder rungs occlude the player's body).

Because both the ladder and the water live on Playfield 1, Denise cannot slice a hardware sprite between them.

```
CURRENT HARDWARE SPRITE CONFLICT:
+-------------------------------------------------------------------------+
| Mode $0024:  Copper BG  ->  [Platforms & Ladders]  ->  WATER  -> PLAYER |  (Water behind player!)
| Mode $0000:  Copper BG  ->  PLAYER  ->  [Platforms & Ladders]  -> WATER |  (Ladders in front of player!)
+-------------------------------------------------------------------------+

DESIRED VISUAL LAYERING:
+-------------------------------------------------------------------------+
| TARGET:      Copper BG  ->  Platform Tiles (Ladders)  ->  PLAYER  -> WATER
+-------------------------------------------------------------------------+
```

### 1.2 The BOB Solution
By converting the player character from a Denise hardware sprite to a **Blitter Object (BOB)**, the game gains **100% software control over the draw and blit ordering**:
1. **Background**: Platforms and ladders are already present in `DisplayScreen`.
2. **Player Blit**: The Blitter cookie-cut blits the player on top of `DisplayScreen` $\implies$ **Player is in front of the ladder!**
3. **Enemy Blits**: Enemies are blitted into `DisplayScreen`.
4. **Water Submersion Stipple**: The 50% cyan checkerboard dither stipple is applied onto the player for any scanlines $\ge \text{WaterPixelY}$ $\implies$ **Water is on top of the player!**
5. **Pristine Erase**: Next frame, the player is erased using the clean background from `NonDisplayScreen`, guaranteeing zero smearing.

### 1.3 Resource Balance Sheet

| Resource Metric | Hardware Sprite (Current) | Blitter Object / BOB (Target) | Net Impact |
| :---| :---: | :---: | :---|
| **Layer Ordering** | Binary (`$0000` vs `$0024`) | Fully arbitrary software ordering | **Solves ladder vs. water depth conflict** |
| **Chip RAM Usage** | **39,936 bytes** (`PlayerHWSprites`) | **$\sim 18,432$ bytes** (Raw + Mask) | **Saves $\sim 21.5$ KB of precious Chip RAM** |
| **Blitter Frame Budget** | 0% | $\sim 0.15$ ms (384 bytes blitted) | Negligible ($< 0.8\%$ of a 50 Hz frame) |
| **Free Hardware Sprites**| Channels `SPR0/SPR1` consumed | Channels `SPR0/SPR1` freed | Can be used for air bubbles or HUD |

---

## 2. Frame Execution Sequence: Unified Actor Pipeline

Both the player and enemies will share the identical triple-buffer restoration and submersion architecture:

```
[Frame Start (VBlank)]
      │
      ├─► 1. TilemapErasePlayer
      │      Restores background under player from NonDisplayScreen -> DisplayScreen.
      │
      ├─► 2. TilemapEraseEnemy
      │      Restores background under enemies from NonDisplayScreen -> DisplayScreen.
      │
      ├─► 3. PlayerLogic
      │      Updates player physics, ladder movement, facing direction, animation frame.
      │
      ├─► 4. TilemapUpdateWater
      │      Advances water scanline accumulator and updates wave graphics in both screens.
      │
      ├─► 5. TilemapDrawPlayerBob
      │      Cookie-cuts player into DisplayScreen (over ladders and platforms).
      │      Applies 50% cyan dither stipple if scanlines >= WaterPixelY.
      │
      ├─► 6. TilemapUpdateEnemies & TilemapDrawEnemySubPixel
      │      Cookie-cuts enemies and applies 50% water stipple if submerged.
      │
      ├─► 7. TilemapDrawDebugOverlay
      │      Renders green diagnostic HUD.
      │
      └─► [Raster Display]
```

---

## 3. Step 1: Asset Pipeline & Data Conversion

### 3.1 Source Graphic Specifications
* **Source Image**: `assets/graphics/sprites/player-animation-16x24.png`
* **Dimensions**: 64 pixels wide $\times$ 288 pixels high.
* **Layout**:
  * 4 columns of 16-pixel frames ($4 \times 16 = 64$ px).
  * 12 rows of 24-pixel frames ($12 \times 24 = 288$ px).
  * Total: **48 animation frames** per character sheet (Idle, Walk, Ladder, Fall, and Left-facing mirrors).

### 3.2 Target BOB Data Format
The Amiga Blitter operates most efficiently on **4-bitplane interleaved memory**, matching the display buffer:
* **Width**: 64 pixels = 4 words = 8 bytes per plane.
* **Planes**: 4 bitplanes interleaved:
  * Scanline $Y$, Plane 0 (8 bytes)
  * Scanline $Y$, Plane 1 (8 bytes)
  * Scanline $Y$, Plane 2 (8 bytes)
  * Scanline $Y$, Plane 3 (8 bytes)
  * **Stride**: 32 bytes per scanline row.
* **Height**: 288 scanlines.
* **Total Graphic Size**: $288 \times 32 = 9,216$ bytes (`player_bobs_64x288.raw`).
* **Total Mask Size**: $288 \times 32 = 9,216$ bytes (`player_bobs_64x288.msk`).
  *(Mask is replicated across all 4 planes so the Blitter minterm `$0FCA` can process all 4 planes in a single blit pass).*

### 3.3 Create the Conversion Tool: `tools/convert_player_bob.py`

Create this script to quantize the PNG against the 16-color playfield palette (`PALETTE_OCS`) and output the planar `.raw` and `.msk` files:

```python
#!/usr/bin/env python3
"""
tools/convert_player_bob.py
Converts player-animation-16x24.png into 4-bitplane interleaved raw and mask files.
"""

from pathlib import Path
from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# Vibrant 16-color OCS palette (matches export_level.py & FourSeasons tileset)
PALETTE_OCS = [
    (0, 0, 0),      # 0: Transparent
    (1, 11, 14),    # 1: 0x1BE Vibrant Cyan (Water)
    (3, 3, 2),      # 2: 0x332 Dark outline
    (15, 15, 15),   # 3: 0xFFF White highlight
    (2, 7, 4),      # 4: 0x274 Forest Green
    (1, 9, 3),      # 5: 0x193 Grass Green
    (15, 9, 1),     # 6: 0xF91 Vibrant Orange
    (2, 5, 12),     # 7: 0x25C Deep Blue
    (15, 12, 2),    # 8: 0xFC2 Vibrant Gold
    (13, 10, 6),    # 9: 0xDA6 Light Wood / Sand
    (11, 7, 4),     # 10: 0xB74 Stone / Earth
    (8, 1, 3),      # 11: 0x813 Rich Maroon / Boots
    (13, 1, 2),     # 12: 0xD12 Vibrant Red
    (8, 9, 11),     # 13: 0x89B Slate Grey / Suit
    (1, 7, 7),      # 14: 0x177 Vibrant Teal / Visor
    (12, 10, 8)     # 15: 0xCA8 Peach / Skin
]

def map_color(r, g, b, a):
    if a <= 128:
        return 0
    ro, go, bo = round(r * 15 / 255), round(g * 15 / 255), round(b * 15 / 255)
    best_dist, best_idx = 999999, 1
    for idx, (pr, pg, pb) in enumerate(PALETTE_OCS[1:], start=1):
        d = (ro - pr)**2 + (go - pg)**2 + (bo - pb)**2
        if d < best_dist:
            best_dist, best_idx = d, idx
    return best_idx

def convert_player():
    src_png = PROJECT_ROOT / "assets/graphics/sprites/player-animation-16x24.png"
    out_raw = PROJECT_ROOT / "assets/graphics/sprites/player_bobs_64x288.raw"
    out_msk = PROJECT_ROOT / "assets/graphics/sprites/player_bobs_64x288.msk"
    
    img = Image.open(src_png).convert("RGBA")
    w, h = img.size
    assert w == 64 and h == 288, f"Expected 64x288, got {w}x{h}"
    
    pixels = img.load()
    row_bytes = w // 8  # 8 bytes per plane
    raw_bytes = bytearray()
    msk_bytes = bytearray()
    
    for y in range(h):
        for plane in range(4):
            line = bytearray(row_bytes)
            mask = bytearray(row_bytes)
            for x in range(w):
                r, g, b, a = pixels[x, y]
                idx = map_color(r, g, b, a)
                bit = (idx >> plane) & 1
                solid = 1 if idx != 0 else 0
                bp = x // 8
                shift = 7 - (x % 8)
                line[bp] |= (bit << shift)
                mask[bp] |= (solid << shift)
            raw_bytes.extend(line)
            msk_bytes.extend(mask)
            
    with open(out_raw, "wb") as f:
        f.write(raw_bytes)
    with open(out_msk, "wb") as f:
        f.write(msk_bytes)
    print(f"Exported {out_raw} ({len(raw_bytes)} bytes)")
    print(f"Exported {out_msk} ({len(msk_bytes)} bytes)")

if __name__ == "__main__":
    convert_player()
```

### 3.4 Build Script Integration
In `build.ps1`, add the step before assembling `main.asm`:
```powershell
python tools/convert_player_bob.py
```

---

## 4. Step 2: Data Structures & State Variables

### 4.1 Player Structure Updates (`include/resources/struct.asm`)
Ensure the player structure tracks previous rendering positions for background restoration:

```m68k
; include/resources/struct.asm
                          RSRESET
Player_Status:            rs.w    1   ; 0=inactive, 1=active, 2=frozen
Player_X:                 rs.w    1   ; tile column (0..WALL_PAPER_WIDTH-1)
Player_Y:                 rs.w    1   ; tile row    (0..WALL_PAPER_HEIGHT-1)
Player_XDec:              rs.w    1   ; sub-tile horizontal pixel offset (+/-)
Player_YDec:              rs.w    1   ; sub-tile vertical   pixel offset (+/-)
Player_ActionCount:       rs.w    1   ; frames remaining in current move
Player_PrevX:             rs.w    1   ; previous screen pixel X (for BOB erase)
Player_PrevY:             rs.w    1   ; previous screen pixel Y (for BOB erase)
Player_PrevDrawn:         rs.w    1   ; non-zero if player was blitted last frame
Player_SpriteOffset:      rs.w    1   ; base frame index (Molly=0, Millie=48)
Player_AnimFrame:         rs.w    1   ; current animation frame
Player_Facing:            rs.w    1   ; +1 = right, -1 = left
Player_OnLadder:          rs.w    1   ; non-zero if on ladder
Player_Fallen:            rs.w    1   ; non-zero if falling
; ...
```

### 4.2 Constants Definition (`include/resources/const.asm`)
Add BOB geometry equates:

```m68k
; include/resources/const.asm
PLAYER_BOB_WIDTH          = 16    ; player frame width in pixels
PLAYER_BOB_HEIGHT         = 24    ; player frame height in pixels
PLAYER_BOB_PLANES         = 4     ; 4 bitplanes
PLAYER_SHEET_WIDTH        = 64    ; sheet width in pixels
PLAYER_SHEET_BYTES        = 8     ; 64 / 8 = 8 bytes per plane
PLAYER_ROW_STRIDE         = PLAYER_SHEET_BYTES*PLAYER_BOB_PLANES ; 32 bytes per row
PLAYER_FRAME_STRIDE       = PLAYER_ROW_STRIDE*PLAYER_BOB_HEIGHT  ; 768 bytes per frame row (4 frames)
```

### 4.3 Asset Inclusions (`main.asm`)
In the `data_chip` section of `main.asm`, replace `PlayerHWSprites` with the BOB assets:

```m68k
; main.asm (data_chip section)
PlayerBobRaw:
    incbin     "assets/graphics/sprites/player_bobs_64x288.raw"
    even

PlayerBobMsk:
    incbin     "assets/graphics/sprites/player_bobs_64x288.msk"
    even
```

---

## 5. Step 3: Background Erase Routine (`TilemapErasePlayer`)

Before moving or drawing the player, their prior frame footprint must be restored with clean background graphics copied from `NonDisplayScreen`.

Add `TilemapErasePlayer` to `include/resources/tilemap.asm`:

```m68k
;==============================================================================
; TilemapErasePlayer  -  Restore background under previous player blit
;
; In:  a4 = pointer to active Player struct
;      a5 = Variables base
;      a6 = CUSTOM chip base ($dff000)
; Destroys: d0-d4, a0-a2
;==============================================================================

TilemapErasePlayer:
    tst.w       Player_PrevDrawn(a4)
    beq.s       .exit                   ; nothing drawn last frame, skip

    clr.w       Player_PrevDrawn(a4)    ; reset drawn flag

    move.w      Player_PrevX(a4),d0
    move.w      Player_PrevY(a4),d1

    ; Screen byte offset = (Y * 160) + ((X / 16) * 2)
    mulu.w      #TILEMAP_LINE_STRIDE,d1 ; d1 = Y * 160
    move.w      d0,d2
    lsr.w       #4,d2
    add.w       d2,d2                   ; byte column
    add.l       d2,d1

    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1
    adda.l      d1,a0                   ; a0 = pristine background source
    adda.l      d1,a1                   ; a1 = display screen destination

    ; Check if X was word-aligned (1 word) or shifted (2 words)
    and.w       #15,d0
    beq.s       .erase_1word

    ; --- 2-Word Wide Restore (32px shifted) ---
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)      ; D = A (direct copy)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-4,BLTAMOD(a6) ; 40 - 4 = 36 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6) ; 40 - 4 = 36 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(PLAYER_BOB_HEIGHT*PLAYER_BOB_PLANES<<6)|2,BLTSIZE(a6) ; 96 rows x 2 words
    rts

.erase_1word:
    ; --- 1-Word Wide Restore (16px aligned) ---
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)      ; D = A
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-2,BLTAMOD(a6) ; 40 - 2 = 38 bytes
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6) ; 40 - 2 = 38 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(PLAYER_BOB_HEIGHT*PLAYER_BOB_PLANES<<6)|1,BLTSIZE(a6) ; 96 rows x 1 word
.exit:
    rts
```

---

## 6. Step 4: Cookie-Cut Blit Routine (`TilemapDrawPlayerBob`)

This routine calculates world-to-screen pixel coordinates, sets up Blitter minterm `$0FCA`, executes the cookie-cut blit over `DisplayScreen`, and applies the 50% water stipple if submerged.

Add `TilemapDrawPlayerBob` to `include/resources/tilemap.asm`:

```m68k
;==============================================================================
; TilemapDrawPlayerBob  -  Blit player BOB onto DisplayScreen with water depth
;
; In:  a4 = pointer to active Player struct
;      a5 = Variables base
;      a6 = CUSTOM chip base ($dff000)
; Destroys: d0-d5, a0-a3
;==============================================================================

TilemapDrawPlayerBob:
    tst.w       Player_Status(a4)
    beq         .culled                 ; inactive player, do not draw

    ; 1. Calculate World Pixel X: Player_X * 16 + Player_XDec
    move.w      Player_X(a4),d0
    lsl.w       #4,d0
    add.w       Player_XDec(a4),d0      ; d0 = World X (0..319)

    ; 2. Calculate World Pixel Y: Player_Y * 16 + Player_YDec - 8 (lift 8px)
    move.w      Player_Y(a4),d1
    lsl.w       #4,d1
    add.w       Player_YDec(a4),d1
    subq.w      #8,d1                   ; d1 = World Y (top of 24px sprite)

    ; Adjust Y for bridge sag if walking across a bridge
    bsr         GetBridgeYOffset        ; returns downward offset in d3
    add.w       d3,d1

    ; 3. Viewport Culling & Bounds Checks
    cmp.w       #0,d0
    blt         .culled
    cmp.w       #320-16,d0
    bgt         .culled
    cmp.w       #0,d1
    blt         .culled
    cmp.w       #LEVEL_SCREEN_HEIGHT-PLAYER_BOB_HEIGHT,d1
    bgt         .culled

    ; Camera viewport culling: CameraY - 24 <= Y <= CameraY + 224
    move.w      TilemapCameraY(a5),d2
    sub.w       #PLAYER_BOB_HEIGHT,d2
    cmp.w       d2,d1
    blt         .culled
    add.w       #216+PLAYER_BOB_HEIGHT,d2
    cmp.w       d2,d1
    bgt         .culled

    ; 4. Calculate Source Frame Pointer in PlayerBobRaw / PlayerBobMsk
    ; Frame index = Player_SpriteOffset + AnimFrame
    move.w      Player_SpriteOffset(a4),d2
    add.w       Player_AnimFrame(a4),d2 ; d2 = frame index (0..47)

    ; Row = d2 >> 2 (div 4), Col = d2 & 3
    move.w      d2,d3
    lsr.w       #2,d3                   ; d3 = frame row (0..11)
    mulu.w      #PLAYER_FRAME_STRIDE,d3 ; d3 = row byte offset (Row * 24 * 32)

    andi.w      #3,d2                   ; d2 = col (0..3)
    add.w       d2,d2                   ; d2 = col * 2 bytes
    add.l       d2,d3                   ; d3 = total source byte offset

    lea         PlayerBobMsk,a0
    lea         PlayerBobRaw,a1
    adda.l      d3,a0                   ; a0 = mask source
    adda.l      d3,a1                   ; a1 = raw graphic source

    ; 5. Calculate Destination Screen Address
    ; Dest offset = (Y * 160) + ((X / 16) * 2)
    move.w      d1,d2
    mulu.w      #TILEMAP_LINE_STRIDE,d2
    move.w      d0,d3
    lsr.w       #4,d3
    add.w       d3,d3                   ; byte column
    add.l       d3,d2

    lea         DisplayScreen,a2
    adda.l      d2,a2                   ; a2 = destination in DisplayScreen

    ; 6. Check Barrel Shift (X & 15)
    move.w      d0,d3
    andi.w      #15,d3                  ; shift = 0..15
    beq.s       .blit_aligned

    ; --- 2-Word Shifted Blit (32px span) ---
    lsl.w       #8,d3
    lsl.w       #4,d3                   ; d3 = Shift << 12
    move.w      d3,d4
    ori.w       #$0fca,d3               ; d3 = BLTCON0 (USEA|B|C|D, minterm $CA)

    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      d4,BLTCON1(a6)
    move.l      #$ffff0000,BLTAFWM(a6)  ; mask out adjacent frame bleed

    move.w      #PLAYER_SHEET_BYTES-4,BLTAMOD(a6) ; 8 - 4 = 4
    move.w      #PLAYER_SHEET_BYTES-4,BLTBMOD(a6) ; 8 - 4 = 4
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6)  ; 40 - 4 = 36
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6)  ; 40 - 4 = 36

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Background
    move.l      a2,BLTDPT(a6)           ; Destination

    move.w      #(PLAYER_BOB_HEIGHT*PLAYER_BOB_PLANES<<6)|2,BLTSIZE(a6) ; 96 rows x 2 words
    bra.s       .record_drawn

.blit_aligned:
    ; --- 1-Word Aligned Blit (16px span) ---
    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)

    move.w      #PLAYER_SHEET_BYTES-2,BLTAMOD(a6) ; 8 - 2 = 6
    move.w      #PLAYER_SHEET_BYTES-2,BLTBMOD(a6) ; 8 - 2 = 6
    move.w      #SCREEN_WIDTH_BYTE-2,BLTCMOD(a6)  ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6)  ; 40 - 2 = 38

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Background
    move.l      a2,BLTDPT(a6)           ; Destination

    move.w      #(PLAYER_BOB_HEIGHT*PLAYER_BOB_PLANES<<6)|1,BLTSIZE(a6) ; 96 rows x 1 word

.record_drawn:
    move.w      d0,Player_PrevX(a4)
    move.w      d1,Player_PrevY(a4)
    move.w      #1,Player_PrevDrawn(a4)

    ; 7. Water Submersion Check
    move.w      WaterPixelY(a5),d2      ; d2 = WaterPixelY
    bmi         .exit                   ; if no water (< 0), dry
    move.w      d1,d3                   ; d3 = player top Y
    add.w       #PLAYER_BOB_HEIGHT-1,d3 ; d3 = player bottom scanline
    cmp.w       d2,d3
    blt         .exit                   ; bottom < WaterPixelY -> completely dry!

    ; --- Player is Submerged: Apply 50% Water Stipple in DisplayScreen ---
    WAITBLIT                            ; ensure blitter is idle
    move.w      d7,-(sp)

    andi.w      #15,d0
    bne.s       .submerge_2words

    ; --- 1 Word Wide Stipple (Aligned) ---
    move.w      #PLAYER_BOB_HEIGHT-1,d7 ; 24 scanlines
    movea.l     a2,a0
.loop_1w:
    cmp.w       d2,d1                   ; scanline Y >= WaterPixelY?
    blt.s       .next_1w

    btst        #0,d1
    bne.s       .odd_1w
    ; EVEN scanline: Plane 0 OR $AAAA, Planes 1..3 AND $5555
    or.w        #$aaaa,(a0)
    and.w       #$5555,40(a0)
    and.w       #$5555,80(a0)
    and.w       #$5555,120(a0)
    bra.s       .next_1w

.odd_1w:
    ; ODD scanline: Plane 0 OR $5555, Planes 1..3 AND $AAAA
    or.w        #$5555,(a0)
    and.w       #$aaaa,40(a0)
    and.w       #$aaaa,80(a0)
    and.w       #$aaaa,120(a0)

.next_1w:
    addq.w      #1,d1
    lea         TILEMAP_LINE_STRIDE(a0),a0
    dbra        d7,.loop_1w
    bra.s       .pop_exit

.submerge_2words:
    ; --- 2 Words Wide Stipple (Shifted) ---
    move.w      #PLAYER_BOB_HEIGHT-1,d7 ; 24 scanlines
    movea.l     a2,a0
.loop_2w:
    cmp.w       d2,d1                   ; scanline Y >= WaterPixelY?
    blt.s       .next_2w

    btst        #0,d1
    bne.s       .odd_2w
    ; EVEN scanline
    or.w        #$aaaa,(a0)
    or.w        #$aaaa,2(a0)
    and.w       #$5555,40(a0)
    and.w       #$5555,42(a0)
    and.w       #$5555,80(a0)
    and.w       #$5555,82(a0)
    and.w       #$5555,120(a0)
    and.w       #$5555,122(a0)
    bra.s       .next_2w

.odd_2w:
    ; ODD scanline
    or.w        #$5555,(a0)
    or.w        #$5555,2(a0)
    and.w       #$aaaa,40(a0)
    and.w       #$aaaa,42(a0)
    and.w       #$aaaa,80(a0)
    and.w       #$aaaa,82(a0)
    and.w       #$aaaa,120(a0)
    and.w       #$aaaa,122(a0)

.next_2w:
    addq.w      #1,d1
    lea         TILEMAP_LINE_STRIDE(a0),a0
    dbra        d7,.loop_2w

.pop_exit:
    move.w      (sp)+,d7
.exit:
    rts

.culled:
    clr.w       Player_PrevDrawn(a4)
    rts
```

---

## 7. Step 5: Game Loop Integration (`gamestatus.asm`)

In `include/resources/gamestatus.asm`, integrate the new `TilemapErasePlayer` and `TilemapDrawPlayerBob` routines inside `GameRun`:

```m68k
; include/resources/gamestatus.asm - inside GameRun:

    ; 1. Erase dynamic actors using pristine background from NonDisplayScreen
    move.l      PlayerPtrs(a5),a4       ; a4 -> active player struct
    bsr         TilemapErasePlayer      ; erase player from last frame's position

    ; 2. Run player physics and state machine
    bsr         PlayerLogic             ; updates Player_X, Player_Y, AnimFrame

    ; 3. Scroll camera and handle water advance
    bsr         TilemapUpdateCamera     ; smooth vertical scrolling
    bsr         TilemapEraseDebugOverlay; clean debug HUD
    bsr         BubbleTick              ; air bubble animation
    bsr         TilemapUpdateWater      ; advance rising water layer

    ; 4. Draw player BOB on top of platforms/ladders
    move.l      PlayerPtrs(a5),a4
    bsr         TilemapDrawPlayerBob    ; blits player; applies water stipple if submerged

    ; 5. Update and blit dynamic enemies
    bsr         ActionCloudActors
    bsr         AnimateEnemies
    bsr         TilemapUpdateEnemies    ; erases, updates, and blits enemies
    bsr         UpdateCocoons
    bsr         FlushDirtyTiles

    ; 6. Draw diagnostic HUD on top
    bsr         TilemapDrawDebugOverlay
```

---

## 8. Step 6: Hardware Sprite Deprecation & Cleanup

Once the player is drawn as a BOB:
1. **Disable `ShowSprite`**: In `include/resources/player.asm`, remove calls to `ShowSprite` inside `PlayerLogic`, `ActionIdle`, `ActionMove`, `ActionPlayerFall`, and `ActionLadder`.
2. **Lock `BPLCON2` to Dry Mode (`$0024`)**:
   * In `include/resources/copperlists.asm`, `BPLCON2` remains statically set to `$0024`:
     ```m68k
     dc.w    BPLCON2,$0024   ; standard OCS priority: sprites in front of playfield
     ```
   * Remove any code that dynamically writes `$0000` to `cpBPLCON2+2` or `BPLCON2(a6)`.
3. **Clear Hardware Sprite Channels**:
   * Hardware sprite channels 0 and 1 (`SPR0` / `SPR1`) can be pointed to `NullSprite` (two zero words), completely freeing them for future use.

---

## 9. Verification & Quality Checklist

After completing the conversion, verify the following in the UAE emulator:

- [ ] **Ladder Depth Test**: Move the player to a ladder tile (e.g. Column 10, Row 38). Confirm that the player's body and limbs render **in front of** the wooden rungs and vertical rails.
- [ ] **Platform Alignment Test**: Stand on a solid platform. Confirm that the player's boots rest exactly on the platform's surface with zero floating gap or clipping.
- [ ] **Bridge Sag Test**: Walk across a 3-tile bridge. Confirm that the bridge sag calculation (`GetBridgeYOffset`) smoothly lowers the player BOB without visual jitter.
- [ ] **Water Submersion Test**: Wait for the water to rise to the player's row. Confirm that:
  - The player's body receives the 50% cyan water dither stipple.
  - The player remains **in front of** the ladder rungs behind them.
  - The water wavefront is **in front of** the player.
- [ ] **Waist-Deep Precision Test**: As water rises through the player, verify that the scanlines above `WaterPixelY` remain dry, while scanlines below `WaterPixelY` are submerged.
- [ ] **Smear-Free Motion Test**: Walk and jump through the water. Verify that `TilemapErasePlayer` cleanly restores the background from `NonDisplayScreen` without leaving trails, ghost pixels, or erased ladders.
- [ ] **Chip RAM Audit**: Run `build.ps1` and verify that total Chip RAM usage has decreased by $\sim 21$ KB compared to the hardware sprite implementation.
