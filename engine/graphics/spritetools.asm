;==============================================================================
; AMIGA GAME ENGINE
; spritetools.asm  -  Hardware Sprite Display Utilities
;==============================================================================
;
; Utilities for calculating and programming OCS/ECS Amiga hardware sprites.
;
; Provides:
;   SpriteCoord  - calculate packed SPRxPOS / SPRxCTL header words
;==============================================================================

    section    main,code
    even

;==============================================================================
; SpriteCoord  -  Write SPRxPOS and SPRxCTL words into a sprite structure header
;
; Amiga hardware sprite position registers (SPRxPOS and SPRxCTL) are embedded
; in the sprite data structure as the first two words. The Copper loads
; the sprite pointers (SPRxPTH/L), and Agnus reads these header words to arm
; the sprite beam counters.
;
; Register format:
;   SPRxPOS:
;     bits 15:8 = VSTART[7:0]  (low 8 bits of vertical start line)
;     bits  7:0 = HSTART[8:1]  (horizontal colour clock, bits 8:1)
;   SPRxCTL:
;     bits 15:8 = VSTOP[7:0]   (vertical stop line)
;     bit   7   = attach bit   (1 = attached to previous even sprite)
;     bit   2   = VSTART[8]    (vertical start bit 8 for PAL lines > 255)
;     bit   1   = VSTOP[8]     (vertical stop bit 8 for PAL lines > 255)
;     bit   0   = HSTART[0]    (horizontal low bit, 1 lo-res pixel precision)
;
; On entry:
;   d1 = X pixel coordinate  (0-based from left edge of display window)
;   d2 = Y pixel coordinate  (0-based from top of display window)
;   d5 = { attach_byte (high word), height_in_rows (low word) }
;        attach_byte: $80 = no attach, $c0 = attached (for odd sprites)
;        height_in_rows: height of the sprite in scanlines
;   a0 = pointer to the 4-byte sprite structure header to fill
;
; Uses WINDOW_X_START and SpriteYOffset(a5).
; Destroys: none (preserves all registers, writes 4 bytes at a0)
;==============================================================================

SpriteCoord:
    PUSHM     d1/d2                       ; preserve X and Y across this calculation

    ; Adjust X: add display window offset
    add.w     #WINDOW_X_START-1,d1        ; d1 = absolute horizontal position

    ; Adjust Y: add display window top (PAL=$2c / NTSC=$1c, set once by DetectNTSC)
    moveq     #0,d4
    move.w    SpriteYOffset(a5),d4
    add.w     d4,d2                       ; d2 = absolute vertical position

    ; --- Build SPRxPOS word ---
    move.l    d1,d4
    swap      d4                          ; d4.lo = d1 now in high word
    lsr.l     #1,d4                       ; shift right 1: H[8:1] in d4.hi[7:0], H[0] in carry
    rol.w     #1,d4                       ; rotate low word: carry -> bit 0 (SPRxCTL[0])

    ; Vertical start: V[7:0] -> SPRxPOS[15:8], V[8] -> SPRxCTL[2]
    move.l    d2,d3
    lsl.l     #8,d3
    swap      d3
    lsl.w     #2,d3                       ; V[8] -> SPRxCTL bit 2
    or.l      d3,d4

    ; --- Build SPRxCTL word ---
    move.l    d2,d3
    add.w     d5,d3                       ; d3 = VSTOP = VSTART + height
    rol.w     #8,d3                       ; VSTOP[7:0] -> bits[15:8]
    lsl.b     #1,d3                       ; VSTOP[8] -> SPRxCTL bit 1
    or.l      d3,d4

    ; Attach bit
    swap      d5                          ; bring attach byte to low word
    or.b      d5,d4                       ; OR attach bit into SPRxCTL bit 7

    move.l    d4,(a0)                     ; write SPRxPOS : SPRxCTL

    POPM      d1/d2                       ; restore X and Y
    rts

;==============================================================================
; ShowAttachedPlayerSprites - Position 4-sprite attached dual-pair player
;
; Positions a 24-pixel wide attached player avatar using 4 hardware sprites
; (SPR2+3 for left half, SPR4+5 for right half) at any pixel position.
;
; On entry:
;   a4 = Player structure pointer
;   a5 = Variables base pointer
;   a6 = CUSTOM
;   d0.w = base sprite frame offset (AnimFrame + SpriteOffset)
;   a0 = base pointer to PlayerHWSprites in Chip RAM
;==============================================================================

    IFND SPRITE_SIZE
SPRITE_SIZE     = 104
    ENDC
    IFND TILE_HEIGHT
TILE_HEIGHT     = 24
    ENDC

;==============================================================================
; ShowAttachedPlayerSprites  -  Position the four attached hardware sprites of a 24px-tile player
;
; Legacy helper for the attached-sprite player used by the TILE_* renderer
; (engine/graphics/tile_renderer.asm). Computes the pixel position from
; Player_X/Y (*24) plus the XDec/YDec sub-tile offsets, selects the frame
; from Player_BobOffset + d0, writes the SPR2-SPR5 control words via
; SpriteCoord, stores the data pointers in SpritePtrs+8..+20 and patches
; the cpSprites copper entries. Hides all sprites when the player is inactive.
;
; In:  a4 = Player struct, a0 = sprite sheet base, d0.w = animation frame
;
; Destroys: d0-d5/d7/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

ShowAttachedPlayerSprites:
    tst.w     Player_Status(a4)          ; is this player active?
    bne.s     .go                        ; yes - proceed to display
    bsr       ClearSprites               ; no  - hide all sprites
    rts

.go:
    ; Calculate pixel position from tile coordinates + sub-tile decimals
    moveq     #0,d1
    moveq     #0,d2
    move.w    Player_X(a4),d1            ; tile column
    move.w    Player_Y(a4),d2            ; tile row
    mulu      #24,d1                     ; pixel X = tile_col * 24
    mulu      #24,d2                     ; pixel Y = tile_row * 24

    add.w     Player_XDec(a4),d1         ; add sub-tile X offset (animation interpolation)
    add.w     Player_YDec(a4),d2         ; add sub-tile Y offset

    add.w     Player_BobOffset(a4),d0
    mulu      #SPRITE_SIZE*4,d0
    add.l     d0,a0                      ; a0 -> sprite data for this frame

    ; --- SPR2 (left half, top colour bits) ---
    move.w    #$80,d5
    swap      d5
    move.w    #TILE_HEIGHT,d5

    move.l    a0,SpritePtrs+8(a5)
    bsr       SpriteCoord

    ; --- SPR4 (right half, top colour bits) ---
    add.w     #16,d1
    add.w     #SPRITE_SIZE,a0
    move.l    a0,SpritePtrs+16(a5)

    move.w    #$80,d5
    swap      d5
    move.w    #TILE_HEIGHT,d5
    bsr       SpriteCoord

    ; --- SPR3 (left half, bottom colour bits - attached to SPR2) ---
    sub.w     #16,d1
    add.w     #SPRITE_SIZE,a0
    move.w    #$80,d5
    swap      d5
    move.w    #TILE_HEIGHT,d5
    move.l    a0,SpritePtrs+12(a5)
    bsr       SpriteCoord

    ; --- SPR5 (right half, bottom colour bits - attached to SPR4) ---
    add.w     #SPRITE_SIZE,a0
    add.w     #16,d1
    move.l    a0,SpritePtrs+20(a5)
    move.w    #$80,d5
    swap      d5
    move.w    #TILE_HEIGHT,d5
    bsr       SpriteCoord

    ; --- Patch the copper list sprite pointer entries ---
    lea       cpSprites+SPRITE_02_OFFSET,a0
    lea       SpritePtrs+8(a5),a1
    moveq     #4-1,d7
.loop:
    move.l    (a1)+,d0
    move.w    d0,6(a0)
    swap      d0
    move.w    d0,2(a0)
    swap      d0
    add.l     #8,a0
    dbra      d7,.loop

    rts
