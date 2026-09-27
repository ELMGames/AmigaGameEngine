# Dynamic Width Player BOBs: Architectural Specification & Implementation Guide
## Converting *Alien Containment* from Uniform 24px Blits to State-Dependent 16px / 24px Blitting

---

## 1. Executive Summary & Problem Statement

### 1.1 The Context
In *Alien Containment*, the player character is rendered as a 4-bitplane interleaved Blitter Object (BOB). Most character animation frames (idle, walking, climbing ladders, pushing crates, falling) feature a humanoid body that is **13–14 pixels wide** and fits within a standard 16-pixel tile column ($16 \times 24$ pixels).

However, two specific gameplay states require additional horizontal span:
1. **Cane Strike Attack (`ACTION_ATTACK`)**: The arm and cane reach out horizontally past the player's core body, extending the total width to **~22–24 pixels**.
2. **Death / Collapse Animation (`ACTION_DEATH`, Row 9)**: When collapsing flat onto the ground, the prone character occupies **~19–20 pixels**.

### 1.2 The Current Baseline (Uniform 24px Width)
The engine currently standardizes all 96 animation frames to a **uniform 24px active canvas** (packaged within 32px word-aligned cells):
- **On-Screen Span**: 
  - Aligned ($X \bmod 16 = 0$): **2 words** (32 pixels).
  - Shifted ($X \bmod 16 \ne 0$): **3 words** (48 pixels).
- **Coordinate Centering**: A static horizontal offset (`WorldX - 4`) centers the 14px body over the 16px tile grid while reserving 4px margins on each side.
- **Performance**: A 3-word blit takes **~0.20 ms** of blitter time ($< 1.0\%$ of a 50 Hz frame).

### 1.3 What "Dynamic Width Switching" Entails
Dynamic width switching optimizes the engine so that:
- **Standard Movement (Idle, Walk, Climb, Push, Fall)**: Blits strictly as a **16-pixel BOB** (1 word aligned, 2 words shifted).
- **Extended Actions (Attack, Death)**: Dynamically expands to a **24-pixel BOB** (2 words aligned, 3 words shifted).

This document details every engineering requirement, memory adjustment, state transition, and 68000 assembly implementation detail necessary to adopt this model.

---

## 2. Resource & Complexity Trade-Off Analysis

| Metric | Uniform 24px (Current) | Dynamic 16px / 24px (Proposed) | Net Impact |
| :--- | :---: | :---: | :--- |
| **Normal Blit Word Count** | 2 words (aligned) / 3 words (shifted) | 1 word (aligned) / 2 words (shifted) | **Saves 1 word DMA per raster row (~33% DMA reduction for 90% of frames)** |
| **Normal Blitter Time** | ~0.20 ms / frame | ~0.14 ms / frame | **Frees ~0.06 ms blitter budget during standard movement** |
| **Background Erase Area** | 32px / 48px footprint | 16px / 32px footprint | **Fewer background pixels restored from `NonDisplayScreen`** |
| **Foreground Re-Stamping** | Checks 2–3 columns (e.g. Cols 0, 1, 2) | Checks 1–2 columns (e.g. Cols 1, 2) | **Less Blitter work re-stamping foreground scenery** |
| **Water Submersion CPU Cost** | 2 or 3 word dither loop | 1 or 2 word dither loop | **Saves ~384 CPU cycles per submerged frame** |
| **Engine State Complexity** | Zero state tracking; single code path | Requires tracking previous frame's width & $X$ anchor | **Adds state variables & branch logic** |
| **Transition Edge Cases** | None; erase footprint is always consistent | Transitioning from 24px (Attack) $\to$ 16px (Idle) must erase previous 24px footprint | **Requires variable-width historical erase tracking** |

---

## 3. Core Architectural Requirements

Converting to dynamic width involves **five distinct systems**:

```
                  +-----------------------------------+
                  |  Animation Frame Classification   |
                  |  Narrow (16px) vs Wide (24px)     |
                  +-----------------+-----------------+
                                    │
                                    ▼
                  +-----------------------------------+
                  |   Anchor & Coordinate Alignment   |
                  |  WorldX (Narrow) vs WorldX-XOff   |
                  +-----------------+-----------------+
                                    │
         ┌──────────────────────────┴──────────────────────────┐
         ▼                                                     ▼
+-----------------------------------+         +-----------------------------------+
|       Blitter Draw Pipeline       |         |      Blitter Erase Pipeline       |
| 1w/2w (Narrow) vs 2w/3w (Wide)    |         | Dynamic Erase based on PrevWords  |
+-----------------+-----------------+         +-----------------+-----------------+
                  │                                                     │
                  └─────────────────────────┬───────────────────────────┘
                                            ▼
                  +-----------------------------------+
                  |      Peripheral Integrations      |
                  | - Foreground Tile Re-stamping     |
                  | - Water Wavefront Submersion      |
                  +-----------------------------------+
```

---

### Requirement 1: Frame Classification & Width Metadata

Every animation frame index ($0 \dots 47$) must be classified as either **Narrow (16px)** or **Wide (24px)**:

| Frame Range | State / Animation | Classification | Active Width | Reason |
| :---: | :--- | :---: | :---: | :--- |
| **0 .. 3** | Idle Right | **Narrow** | 14 px | Neutral standing pose |
| **4 .. 11** | Walk Right | **Narrow** | 14 px | Leg stride within 14px |
| **12 .. 15** | Cane Strike Right | **WIDE** | **22–24 px** | Arm + cane forward extension |
| **16 .. 19** | Ladder Climb | **Narrow** | 12 px | Rear climbing pose |
| **20 .. 23** | Push Left / Right | **Narrow** | 15 px | Braced stance against block |
| **24 .. 27** | Cane Strike Left | **WIDE** | **22–24 px** | Arm + cane forward extension |
| **28 .. 31** | Falling | **Narrow** | 14 px | Vertical tumbling frames |
| **32 .. 35** | Idle Left | **Narrow** | 14 px | Neutral standing pose |
| **36 .. 43** | Walk Left | **Narrow** | 14 px | Leg stride within 14px |
| **44 .. 47** | Death Collapse | **WIDE** | **20 px** | Prone body on ground |

#### Implementation Approaches:
1. **Action State Flag**: Check `ActionStatus(a5)`:
   - If `ActionStatus == ACTION_ATTACK` or `ActionStatus == ACTION_DEATH` $\implies$ **WIDE**.
   - Otherwise $\implies$ **NARROW**.
   - *Advantage*: Extremely fast (single word comparison), no table lookup.
2. **Per-Frame Lookup Table**:
   - A 48-byte table `PlayerFrameWidthTable: dc.b 16,16,16,16, ... 24,24,24,24, ...`
   - *Advantage*: Supports arbitrary frame-by-frame widths if future animations vary.

---

### Requirement 2: Horizontal Coordinate Anchoring

Because the cane extends horizontally in the direction the player is facing, the horizontal drawing anchor must adjust dynamically:

```
NARROW (16px):
Tile:      |  Col X (16px)  |
Player:    | .[PlayerBody]. |      -> Draw at d0 = WorldX (no offset)
Cane:      None

WIDE ATTACK RIGHT:
Tile:      |  Col X (16px)  | Col X+1 (16px) |
Player:    | .[PlayerBody]===CaneHook=>      | -> Draw at d0 = WorldX (cane extends right)

WIDE ATTACK LEFT:
Tile:      | Col X-1 (16px) |  Col X (16px)  |
Player:    |      <=HookCane===[PlayerBody]. | -> Draw at d0 = WorldX - 8 (cane extends left)
```

- **Narrow Frames**:
  - Drawn directly at `d0 = WorldX`.
  - Body sits centered at `WorldX + 1 .. WorldX + 14`.
- **Wide Frames (Attack Right)**:
  - Drawn at `d0 = WorldX`.
  - Body at `WorldX + 1 .. WorldX + 14`, cane reaches into `WorldX + 15 .. WorldX + 23`.
- **Wide Frames (Attack Left)**:
  - Drawn at `d0 = WorldX - 8` (clamped to $\ge 0$).
  - Cane reaches left into `WorldX - 8 .. WorldX`, body at `WorldX + 1 .. WorldX + 14`.
- **Wide Frames (Death / Prone)**:
  - Drawn at `d0 = WorldX - 4` (centered prone collapse).

---

### Requirement 3: Variable Blitter Draw Paths

The Blitter must configure its channels, modulos, and masks according to the active width and sub-pixel shift ($X \bmod 16$):

```
+──────────────────────────+──────────────────────────+──────────────────────────+
| Configuration            | Modulo (Source / Dest)   | BLTSIZE (Lines x Words)  | Mask (AFWM / ALWM)       |
+──────────────────────────+──────────────────────────+──────────────────────────+
| 16px Aligned (shift=0)   | BLTxMOD = 14 / 38        | (96 << 6) | 1 word       | $FFFF / $FFFF            |
| 16px Shifted (shift>0)   | BLTxMOD = 12 / 36        | (96 << 6) | 2 words      | $FFFF / $0000            |
| 24px Aligned (shift=0)   | BLTxMOD = 12 / 36        | (96 << 6) | 2 words      | $FFFF / $FFFF            |
| 24px Shifted (shift>0)   | BLTxMOD = 10 / 34        | (96 << 6) | 3 words      | $FFFF / $0000            |
+──────────────────────────+──────────────────────────+──────────────────────────+
```

*(Assuming source sheet is 128px wide = 16 bytes per bitplane row. Source modulo = $16 - (\text{words} \times 2)$; Dest modulo = $40 - (\text{words} \times 2)$).*

---

### Requirement 4: Historical Erase Tracking (The Transition Rule)

When the player swings the cane (24px, 3-word blit) on frame $T$, and returns to idle (16px, 2-word blit) on frame $T+1$:
- **The Bug to Avoid**: If `TilemapErasePlayer` only checks the *current* frame's width, it would only erase 2 words on frame $T+1$, leaving the tip of the cane permanently burned into the background!
- **The Solution**: The engine must store **what was actually blitted in the previous frame**:
  1. `Player_PrevX(a4)`: The exact screen $X$ pixel coordinate where the blit occurred.
  2. `Player_PrevY(a4)`: The screen $Y$ coordinate.
  3. `Player_PrevWords(a4)`: The exact number of words blitted (**1, 2, or 3**).
  4. `Player_PrevDrawn(a4)`: Flag indicating if a blit needs restoration.

`TilemapErasePlayer` then erases using `Player_PrevWords`:
```m68k
    move.w  Player_PrevWords(a4),d2
    cmp.w   #1,d2
    beq.s   .erase_1word
    cmp.w   #2,d2
    beq.s   .erase_2word
    ; otherwise erase 3 words
```

---

### Requirement 5: Peripheral Systems Integration

#### 1. Foreground Layer Stamping (`TilemapStampForegroundOverPlayer`)
Currently, the engine passes `PLAYER_WIDTH = 24` to determine which foreground tiles overlap the player box:
- With dynamic width, pass the actual width ($16$ or $24$) to `TilemapStampForegroundOverBox`.
- When walking, checks $1$ or $2$ tile columns instead of $2$ or $3$.

#### 2. Rising Water Submersion (`TilemapSubmergeActor`)
Currently, `TilemapSubmergeActor` has branches for 1-word, 2-word, and 3-word spans:
- Pass the word count or width in a register (e.g. `d3 = BlitWordCount`).
- `TilemapSubmergeActor` branches directly to `.submerge_1word`, `.submerge_2words`, or `.submerge_3words` based on `d3`.

---

## 4. Step-by-Step Implementation Blueprint

### Step 1: Update Constants & Structures

#### In [`include/resources/struct.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/struct.asm):
Add historical word count to `Player` structure:
```m68k
Player_PrevWords:       rs.w    1       ; words blitted last frame (1, 2, or 3)
```

#### In [`include/resources/const.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/const.asm):
Define width constants:
```m68k
PLAYER_WIDTH_NARROW     = 16
PLAYER_WIDTH_WIDE       = 24
```

---

### Step 2: Implement Width & Anchor Selector in `tilemap.asm`

In [`TilemapDrawPlayer`](file:///F:/GitHub/AmigaGameEngine/include/resources/tilemap.asm#L1881):

```m68k
    ; 1. Calculate Base World Pixel X
    move.w      Player_X(a4),d0
    lsl.w       #4,d0
    add.w       Player_XDec(a4),d0      ; d0 = World X (0..319)

    ; 2. Determine Active Width and Anchor Offset
    move.w      ActionStatus(a5),d2
    cmp.w       #ACTION_ATTACK,d2
    beq.s       .wide_attack
    cmp.w       #ACTION_DEATH,d2
    beq.s       .wide_death

    ; --- NARROW (16px) ---
    moveq       #PLAYER_WIDTH_NARROW,d5 ; d5 = active width (16)
    bra.s       .anchor_ready

.wide_death:
    ; --- WIDE DEATH (24px centered) ---
    subq.w      #4,d0                   ; center 20px collapse
    moveq       #PLAYER_WIDTH_WIDE,d5   ; d5 = active width (24)
    bra.s       .anchor_ready

.wide_attack:
    ; --- WIDE ATTACK (24px directional) ---
    moveq       #PLAYER_WIDTH_WIDE,d5
    tst.w       Player_Facing(a4)
    bpl.s       .anchor_ready           ; facing right: cane extends right (anchor = WorldX)
    subq.w      #8,d0                   ; facing left: cane extends left (anchor = WorldX - 8)

.anchor_ready:
    tst.w       d0
    bpl.s       .x_clamped
    moveq       #0,d0
.x_clamped:
```

---

### Step 3: Implement Dynamic Blitter Dispatch in `TilemapDrawPlayer`

```m68k
    ; Check barrel shift (X & 15)
    move.w      d0,d3
    andi.w      #15,d3                  ; d3 = shift (0..15)

    cmp.w       #PLAYER_WIDTH_WIDE,d5
    beq.s       .draw_wide

    ; -------------------------------------------------------------------------
    ; NARROW (16px) DRAW PATH
    ; -------------------------------------------------------------------------
    tst.w       d3
    bne.s       .narrow_shifted

    ; --- 1-Word Aligned Blit ---
    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #PLAYER_SHEET_BYTES-2,BLTAMOD(a6) ; 16 - 2 = 14
    move.w      #PLAYER_SHEET_BYTES-2,BLTBMOD(a6) ; 16 - 2 = 14
    move.w      #SCREEN_WIDTH_BYTE-2,BLTCMOD(a6)  ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6)  ; 40 - 2 = 38
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTBPT(a6)
    move.l      a2,BLTCPT(a6)
    move.l      a2,BLTDPT(a6)
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|1,BLTSIZE(a6)
    moveq       #1,d6                   ; 1 word drawn
    bra.s       .record_drawn

.narrow_shifted:
    ; --- 2-Word Shifted Blit ---
    lsl.w       #8,d3
    lsl.w       #4,d3
    move.w      d3,d4
    ori.w       #$0fca,d3
    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      d4,BLTCON1(a6)
    move.l      #$ffff0000,BLTAFWM(a6)
    move.w      #PLAYER_SHEET_BYTES-4,BLTAMOD(a6) ; 16 - 4 = 12
    move.w      #PLAYER_SHEET_BYTES-4,BLTBMOD(a6) ; 16 - 4 = 12
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6)  ; 40 - 4 = 36
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6)  ; 40 - 4 = 36
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTBPT(a6)
    move.l      a2,BLTCPT(a6)
    move.l      a2,BLTDPT(a6)
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|2,BLTSIZE(a6)
    moveq       #2,d6                   ; 2 words drawn
    bra.s       .record_drawn

    ; -------------------------------------------------------------------------
    ; WIDE (24px) DRAW PATH
    ; -------------------------------------------------------------------------
.draw_wide:
    tst.w       d3
    bne.s       .wide_shifted

    ; --- 2-Word Aligned Blit ---
    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #PLAYER_SHEET_BYTES-4,BLTAMOD(a6) ; 16 - 4 = 12
    move.w      #PLAYER_SHEET_BYTES-4,BLTBMOD(a6) ; 16 - 4 = 12
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6)  ; 40 - 4 = 36
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6)  ; 40 - 4 = 36
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTBPT(a6)
    move.l      a2,BLTCPT(a6)
    move.l      a2,BLTDPT(a6)
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|2,BLTSIZE(a6)
    moveq       #2,d6                   ; 2 words drawn
    bra.s       .record_drawn

.wide_shifted:
    ; --- 3-Word Shifted Blit ---
    lsl.w       #8,d3
    lsl.w       #4,d3
    move.w      d3,d4
    ori.w       #$0fca,d3
    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      d4,BLTCON1(a6)
    move.l      #$ffff0000,BLTAFWM(a6)
    move.w      #PLAYER_SHEET_BYTES-6,BLTAMOD(a6) ; 16 - 6 = 10
    move.w      #PLAYER_SHEET_BYTES-6,BLTBMOD(a6) ; 16 - 6 = 10
    move.w      #SCREEN_WIDTH_BYTE-6,BLTCMOD(a6)  ; 40 - 6 = 34
    move.w      #SCREEN_WIDTH_BYTE-6,BLTDMOD(a6)  ; 40 - 6 = 34
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTBPT(a6)
    move.l      a2,BLTCPT(a6)
    move.l      a2,BLTDPT(a6)
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|3,BLTSIZE(a6)
    moveq       #3,d6                   ; 3 words drawn

.record_drawn:
    move.w      d0,Player_PrevX(a4)
    move.w      d1,Player_PrevY(a4)
    move.w      d6,Player_PrevWords(a4) ; record 1, 2, or 3 words
    move.w      #1,Player_PrevDrawn(a4)
```

---

### Step 4: Implement Dynamic Background Erase in `tilemap.asm`

In [`TilemapErasePlayer`](file:///F:/GitHub/AmigaGameEngine/include/resources/tilemap.asm#L1819):

```m68k
TilemapErasePlayer:
    tst.w       Player_PrevDrawn(a4)
    beq         .exit

    clr.w       Player_PrevDrawn(a4)

    move.w      Player_PrevX(a4),d0
    move.w      Player_PrevY(a4),d1

    ; Screen byte offset = (Y * 160) + ((X / 16) * 2)
    mulu.w      #TILEMAP_LINE_STRIDE,d1
    moveq       #0,d2
    move.w      d0,d2
    lsr.w       #4,d2
    add.w       d2,d2
    add.l       d2,d1

    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1
    adda.l      d1,a0
    adda.l      d1,a1

    ; Dispatch based on the EXACT number of words drawn in the previous frame
    move.w      Player_PrevWords(a4),d2
    cmp.w       #1,d2
    beq.s       .erase_1word
    cmp.w       #2,d2
    beq.s       .erase_2word

    ; --- 3-Word Restore ---
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-6,BLTAMOD(a6) ; 40 - 6 = 34
    move.w      #SCREEN_WIDTH_BYTE-6,BLTDMOD(a6) ; 40 - 6 = 34
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|3,BLTSIZE(a6)
    rts

.erase_2word:
    ; --- 2-Word Restore ---
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-4,BLTAMOD(a6) ; 40 - 4 = 36
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6) ; 40 - 4 = 36
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|2,BLTSIZE(a6)
    rts

.erase_1word:
    ; --- 1-Word Restore ---
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-2,BLTAMOD(a6) ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6) ; 40 - 2 = 38
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|1,BLTSIZE(a6)
    rts

.exit:
    rts
```

---

## 5. Potential Pitfalls & How to Avoid Them

### Pitfall 1: Screen Right-Edge Overflow on Facing-Left Attacks
- **Risk**: If the player is at $X = 312$ and attacks facing right, $312 + 24 = 336$ (past screen border).
- **Mitigation**: Viewport bounds clamping already checks:
  ```m68k
  cmp.w   #320-PLAYER_WIDTH_WIDE,d0
  bgt     .culled
  ```
  Ensure the right-bound check uses `320 - d5` (subtracting the dynamic width $d5$).

### Pitfall 2: Left-Edge Underflow on Facing-Left Attacks
- **Risk**: If the player is at $X = 4$ and attacks facing left, $X - 8 = -4$. On the Amiga, negative coordinates wrap into previous scanlines or bitplanes!
- **Mitigation**: Unconditionally clamp `bpl.s .x_clamped; moveq #0, d0`. In practice, Level 1 column 0 is a solid wall, so $X \ge 16$.

### Pitfall 3: Source Agnus DMA Odd-Address Violations
- **Risk**: Storing 16px frames and 24px frames tightly packed without word alignment.
- **Rule**: Never pack odd-byte column widths (e.g. 24px = 3 bytes) into the raw spritesheet. **Keep the spritesheet in 32px (4-byte) column strides** so all source addresses remain 16-bit word-aligned on Motorola 68000 and OCS Agnus.

---

## 6. Conclusion & Recommendation

| Feature | Verdict |
| :--- | :--- |
| **Effort to Implement** | **Low to Medium** (~1–2 hours of focused assembly editing in `tilemap.asm`). |
| **Risk** | **Low** (provided `Player_PrevWords` is used for erase restoration). |
| **Performance Benefit** | **Modest** (saves ~0.06 ms blitter time per frame out of 20.0 ms budget). |
| **Visual Benefit** | **None** (current uniform 24px layout already produces identical pixel output). |

**Recommendation**: The current uniform 24px implementation uses $< 1.0\%$ of the Amiga's blitter frame budget and already masks transparent areas to 0. If Chip RAM or Blitter cycles become tight as more simultaneous enemies and particles are added, this dynamic width specification can be executed directly following the steps above.
