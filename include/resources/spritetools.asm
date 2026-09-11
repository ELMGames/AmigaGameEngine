
;==============================================================================
; AMIGA GAME ENGINE
; spritetools.asm  -  Hardware Sprite Display
;==============================================================================
;
; Channel assignment:
;   SPR0+1  player character (attached pair, 16px wide, 16 colours from COLOR16-31)
;   SPR2-5  free (NullSprite)
;   SPR6    air bubble (solo, non-attached; lower priority than player)
;   SPR7    free (NullSprite)
;
; Note on SPR6+7 colour bleed: OCS pair 3 exhibits a colour-decode quirk when
; used as an attached pair — pixels at the right edge produce colour fringing.
; SPR6 is therefore used solo (non-attached) for the bubble; SPR7 stays at
; NullSprite so the pair is never attached and the quirk never triggers.
;
; Two sprites for the player:
;   - Hardware sprites are 16 pixels wide and 2 bitplanes deep.
;   - Attaching SPR1 to SPR0 combines them into a 4-bitplane (16-colour) sprite,
;     which renders the full 16x24 player character using COLOR16-31.
;   - Channels SPR2, SPR3, SPR4, and SPR5 are completely free.
;
; Sprite layout on screen:
;   SPR0 (16px wide, bitplanes 0 & 1) + SPR1 (attached, bitplanes 2 & 3)
;   SPR6 is reserved for the air bubble (lower priority than player sprites)
;
; The sprite data structures are in PlayerHWSprites (player_hwsprites.bin, Chip RAM).
; Each sprite frame occupies HW_FRAME_SIZE = 2 * SPRITE_SIZE = 208 bytes:
;   SPR0: 4 bytes header, 96 bytes data (24 rows * 4 bytes), 4 bytes terminator = 104 bytes
;   SPR1: 4 bytes header, 96 bytes data (24 rows * 4 bytes), 4 bytes terminator = 104 bytes
;
; ShowSprite updates SpritePtrs(a5), which are then copied into the copper
; list sprite pointer entries (cpSprites) so Agnus fetches the right data
; each frame.
;
;==============================================================================

;==============================================================================
; ClearSprites  -  Point all 8 hardware sprite channels at NullSprite
;
; Writes the address of NullSprite (two zero longwords = a terminated, empty
; sprite structure) into all eight SPRxPTH/L copper list entries in cpSprites.
; This hides all hardware sprites from the display.
;
; Called by GameCopperInit at startup and whenever no sprite should be shown.
;
; NullSprite is a dc.l 0,0 in bss_c (Chip RAM) - Agnus needs to fetch it,
; so it must be in Chip RAM.  The terminator pattern (two zero words) tells
; Agnus to stop fetching sprite data immediately on the first line.
;==============================================================================

ClearSprites:
    lea        cpSprites,a0
    move.l     #NullSprite,d0
    moveq      #8-1,d7
.loop
    move.w     d0,6(a0)
    swap       d0
    move.w     d0,2(a0)
    swap       d0
    add.l      #8,a0
    dbra       d7,.loop
    rts

;==============================================================================
; SpriteCoord  -  Write SPRxPOS and SPRxCTL words into a sprite structure header
;
; The Amiga hardware sprite position registers (SPRxPOS and SPRxCTL) are not
; written directly by the CPU - instead they are embedded in the sprite data
; structure as the first two words.  The Copper reads the sprite pointer
; (SPRxPTH/L) and Agnus copies these header words into the actual registers
; as it processes the sprite data each frame.
;
; Register format:
;   SPRxPOS (first word of sprite structure):
;     bits 15:8 = VSTART[7:0]  - vertical start (raster line, low 8 bits)
;     bits  7:1 = HSTART[8:1]  - horizontal start (colour-clock, bits 8:1)
;     bit   0   = VSTART[8]    - vertical start bit 8 (for > 255 lines)
;
;   SPRxCTL (second word of sprite structure):
;     bits 15:8 = VSTOP[7:0]   - vertical stop (raster line, low 8 bits)
;     bit   7   = attach bit   - 1 = attached to previous (even) sprite
;     bits  6:2 = reserved
;     bit   1   = VSTOP[8]     - vertical stop bit 8
;     bit   0   = VSTART[8]    - vertical start bit 8 (duplicate for SPRxCTL)
;
; On entry:
;   d1 = X pixel coordinate  (0-based from left edge of display)
;   d2 = Y pixel coordinate  (0-based from top  of display)
;   d5 = { attach_byte (high word), height_in_rows (low word) }
;        attach_byte: $80 = no attach, $c0 = attached (for odd sprites)
;        height_in_rows: TILE_HEIGHT (24) for this game
;   a0 = pointer to the 4-byte sprite structure header to fill
;
; Destroys: d3, d4  (d1/d2 preserved via PUSHM/POPM)
;
; The packing logic:
;   1. H_start = d1 + WINDOW_X_START - 1
;      The sprite X is relative to the display window start.
;      Bits 8:1 of H are packed into bits 7:1 of SPRxPOS.
;      Bit 0 of H (the LSB) goes to bit 0 of SPRxCTL.
;      LSR.L #1 / ROL.W #1 achieves this rotation.
;
;   2. V_start = d2 + SpriteYOffset(a5)  ($2c PAL / $21 NTSC, set by DetectNTSC)
;      Packed into bits 15:8 of SPRxPOS.
;      LSL.L #8 / SWAP / LSL.W #2 places V in the correct bit position.
;
;   3. V_stop = V_start + height
;      Packed into bits 15:8 of SPRxCTL.
;      ROL.W #8 / LSL.B #1 places it correctly.
;
;   4. Attach bit from d5 high byte is OR-ed into the result.
;
; The final combined longword d4 is stored as the sprite header (SPRxPOS:SPRxCTL).
;==============================================================================

SpriteCoord:
    PUSHM     d1/d2                       ; preserve X and Y across this calculation

    ; Adjust X: add display window offset
    add.w     #WINDOW_X_START-1,d1        ; d1 = absolute horizontal position

    ; Adjust Y: add display window top (PAL=$2c / NTSC=$21, set once by DetectNTSC)
    moveq     #0,d4
    move.w    SpriteYOffset(a5),d4
    add.w     d4,d2                        ; d2 = absolute vertical position

    ; --- Build SPRxPOS word ---
    ; Horizontal: H[8:1] -> SPRxPOS[7:1], H[0] -> SPRxCTL[0]
    move.l    d1,d4
    swap      d4                           ; d4.lo = d1 now in high word (prep for shift)
    lsr.l     #1,d4                        ; shift right 1: H[8:1] now in d4.hi[7:1], H[0] in carry
    rol.w     #1,d4                        ; rotate low word: carry -> bit 0, H[8:1] -> bits[8:2]
                                           ; NOTE: d4.lo now has the H_START portion of SPRxPOS

    ; Vertical start: V[7:0] -> SPRxPOS[15:8]
    move.l    d2,d3
    lsl.l     #8,d3                        ; shift V left 8
    swap      d3                           ; bring to low word
    lsl.w     #2,d3                        ; shift left 2 more = 10 total -> bits[9:2] (PAL line range)
    or.l      d3,d4                        ; OR into result (V bits into upper area of d4.lo)

    ; --- Build SPRxCTL word ---
    ; Vertical stop: VSTOP = VSTART + height
    move.l    d2,d3
    add.w     d5,d3                        ; d3 = VSTOP = VSTART + TILE_HEIGHT
    rol.w     #8,d3                        ; VSTOP[7:0] -> bits[15:8] of d3.lo
    lsl.b     #1,d3                        ; shift left 1: VSTOP[7:0] -> SPRxCTL[15:8] (low bits intact)
    or.l      d3,d4                        ; OR VSTOP into result

    ; Attach bit
    swap      d5                           ; bring attach byte to low word
    or.b      d5,d4                        ; OR attach bit into SPRxCTL bit 7

    move.l    d4,(a0)                      ; write SPRxPOS (high word) : SPRxCTL (low word)

    POPM      d1/d2                        ; restore X and Y
    rts
