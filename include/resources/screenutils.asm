
;==============================================================================
; AMIGA GAME ENGINE
; screenutils.asm  -  Screen Effects and Visual Transitions
;==============================================================================
;
;
; Register convention:
;   a6 = $dff000 (CUSTOM)   a5 = Variables base
;
;==============================================================================

;==============================================================================
; CopySaveToStatic  -  Copy NonDisplayScreen to DisplayScreen via blitter DMA
;
; NonDisplayScreen holds the clean background (walls + ladders + shadows, no actors).
; Copies it to DisplayScreen so actors can be blitted on top without corrupting
; the background.
;
; Uses a blitter B→D copy (BLTCON0=$05CC, minterm $CC = D=B).
; The copy is 567 rows × 40 words = 22680 words = 45360 bytes = SCREEN_SIZE.
;   BLTSIZE = (567<<6)|40 = $8DE8
;
; Fires the blit and returns immediately — the DMA runs in the background.
; All subsequent blitter operations begin with WAITBLIT, so the copy is
; guaranteed complete before any tile is drawn.
;
; Preserves: all registers (PUSHM a0-a1 / POPM a0-a1).
;==============================================================================

CopySaveToStatic:
    PUSHM         a0-a1
    WAITBLIT
    move.w        #$0000,BLTCON1(a6)
    move.w        #$05CC,BLTCON0(a6)      ; USEB|USED, minterm  (D=B)
    move.w        #0,BLTBMOD(a6)          ; no modulo: flat source
    move.w        #0,BLTDMOD(a6)          ; no modulo: flat dest
    lea           NonDisplayScreen,a0
    move.l        a0,BLTBPT(a6)           ; B = source (NonDisplayScreen)
    lea           DisplayScreen,a1
    move.l        a1,BLTDPT(a6)           ; D = dest   (DisplayScreen)
    move.w        #(540<<6)|20,BLTSIZE(a6); first half (540 rows x 20 words = 21600 bytes)
    WAITBLIT
    lea           NonDisplayScreen+21600,a0
    move.l        a0,BLTBPT(a6)
    lea           DisplayScreen+21600,a1
    move.l        a1,BLTDPT(a6)
    move.w        #(540<<6)|20,BLTSIZE(a6); second half (540 rows x 20 words = 21600 bytes)
    POPM          a0-a1
    rts

;==============================================================================
; WipeBlitBlack  -  Zero-fill one tile on DisplayScreen (black wipe step)
;
; Zero-fills the 24x24-pixel tile area at the given tile coordinates using
; the blitter.  Uses minterm $0A (~A & C): guard bits outside the 24-pixel
; tile boundary are preserved (D = C); pixels inside are cleared to 0 (black).
;
; A is constant $FFFF (USEA=0, BLTADAT=$FFFF), gated per-word by
; BLTAFWM/BLTALWM to restrict the clear to the 24-pixel tile width.
;
; On entry:
;   d0 = tile X (0..13)
;   d1 = tile Y (0..8)
;   a5 = Variables base
;   a6 = $dff000
;==============================================================================

WipeBlitBlack:
    PUSHALL

    lea         DisplayScreen,a1

    mulu        #24,d0                  ; pixel X
    mulu        #24,d1                  ; pixel Y

    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2                   ; byte column = X / 8
    add.w       d2,d1
    add.l       d1,a1                   ; a1 -> destination in DisplayScreen

    move.l      #$ffffff00,d1           ; mask: BLTAFWM=$FFFF, BLTALWM=$FF00 (shift=0)
    and.w       #$f,d0
    beq         .blit
    move.l      #$00ffffff,d1           ; mask: BLTAFWM=$00FF, BLTALWM=$FFFF (shift=8)

.blit
    WAITBLIT
    move.l      #$030a0000,BLTCON0(a6) ; USEC|USED, LF=$0A (~A&C), shift=0, BLTCON1=0
    move.l      d1,BLTAFWM(a6)         ; BLTAFWM + BLTALWM word masks
    move.w      #-1,BLTADAT(a6)        ; A = constant $FFFF (gated by BLTAFWM/BLTALWM)
    move.w      #0,BLTAMOD(a6)         ; A modulo = 0 (constant, no DMA advance)
    move.l      a1,BLTCPT(a6)          ; C = DisplayScreen (guard bits preserved)
    move.l      a1,BLTDPT(a6)          ; D = DisplayScreen (output)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)

    POPALL
    rts


;==============================================================================
; WipeBlitWhite  -  One-fill one tile on DisplayScreen (white wipe step)
;
; One-fills the 24x24-pixel tile area at the given tile coordinates using
; the blitter.  Uses minterm $FA (A|C): guard bits outside the 24-pixel
; tile boundary are preserved (D = C); pixels inside are set to 1 (white).
;
; A is constant $FFFF (USEA=0, BLTADAT=$FFFF), gated per-word by
; BLTAFWM/BLTALWM to restrict the fill to the 24-pixel tile width.
;
; On entry:
;   d0 = tile X (0..13)
;   d1 = tile Y (0..8)
;   a5 = Variables base
;   a6 = $dff000
;==============================================================================

WipeBlitWhite:
    PUSHALL

    lea         DisplayScreen,a1

    mulu        #24,d0                  ; pixel X
    mulu        #24,d1                  ; pixel Y

    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2                   ; byte column = X / 8
    add.w       d2,d1
    add.l       d1,a1                   ; a1 -> destination in DisplayScreen

    move.l      #$ffffff00,d1           ; mask: BLTAFWM=$FFFF, BLTALWM=$FF00 (shift=0)
    and.w       #$f,d0
    beq         .blit
    move.l      #$00ffffff,d1           ; mask: BLTAFWM=$00FF, BLTALWM=$FFFF (shift=8)

.blit
    WAITBLIT
    move.l      #$03fa0000,BLTCON0(a6) ; USEC|USED, LF=$FA (A|C), shift=0, BLTCON1=0
    move.l      d1,BLTAFWM(a6)         ; BLTAFWM + BLTALWM word masks
    move.w      #-1,BLTADAT(a6)        ; A = constant $FFFF (gated by BLTAFWM/BLTALWM)
    move.w      #0,BLTAMOD(a6)         ; A modulo = 0 (constant, no DMA advance)
    move.l      a1,BLTCPT(a6)          ; C = DisplayScreen (guard bits preserved)
    move.l      a1,BLTDPT(a6)          ; D = DisplayScreen (output)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)

    POPALL
    rts

;==============================================================================
; WipeFillTopBottom  -  Fill wipe order: row by row, top to bottom
;==============================================================================
WipeFillTopBottom:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2                      ; write index (0..125)
    moveq       #0,d1                   ; y = 0
.row
    moveq       #0,d0                   ; x = 0
.col
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
    addq.w      #1,d0
    cmp.w       #WALL_PAPER_WIDTH,d0
    blt         .col
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_HEIGHT,d1
    blt         .row
    rts


;==============================================================================
; WipeFillBottomTop  -  Fill wipe order: row by row, bottom to top
;==============================================================================

WipeFillBottomTop:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2
    moveq       #WALL_PAPER_HEIGHT-1,d1 ; y = 8, count down to 0
.row
    moveq       #0,d0
.col
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
    addq.w      #1,d0
    cmp.w       #WALL_PAPER_WIDTH,d0
    blt         .col
    subq.w      #1,d1
    bpl         .row                    ; loop while y >= 0
    rts


;==============================================================================
; WipeFillLeftRight  -  Fill wipe order: column by column, left to right
;==============================================================================

WipeFillLeftRight:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2
    moveq       #0,d0                   ; x = 0
.col
    moveq       #0,d1                   ; y = 0
.row
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_HEIGHT,d1
    blt         .row
    addq.w      #1,d0
    cmp.w       #WALL_PAPER_WIDTH,d0
    blt         .col
    rts


;==============================================================================
; WipeFillRightLeft  -  Fill wipe order: column by column, right to left
;==============================================================================

WipeFillRightLeft:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2
    moveq       #WALL_PAPER_WIDTH-1,d0  ; x = 13, count down to 0
.col
    moveq       #0,d1
.row
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_HEIGHT,d1
    blt         .row
    subq.w      #1,d0
    bpl         .col                    ; loop while x >= 0
    rts


;==============================================================================
; WipeFillDiagTLBR  -  Fill wipe order: diagonal stripes, top-left to bottom-right
;
; Iterates over diagonals where x+y = constant (d = 0..21).
; For each diagonal, emits all tiles (x,y) where x = d-y, 0<=x<=13, 0<=y<=8.
; 22 diagonals cover all 14x9 = 126 tiles exactly.
;==============================================================================

WipeFillDiagTLBR:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2                      ; write index
    moveq       #0,d3                   ; diagonal d = 0..21
.diag
    moveq       #0,d1                   ; y = 0
.scan
    move.w      d3,d0
    sub.w       d1,d0                   ; x = d - y
    blt         .next_y                 ; x < 0: y exceeds diagonal start
    cmp.w       #WALL_PAPER_WIDTH,d0    ; x >= 14: diagonal not yet reached
    bge         .next_y
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
.next_y
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_HEIGHT,d1
    blt         .scan
    addq.w      #1,d3
    cmp.w       #WALL_PAPER_WIDTH+WALL_PAPER_HEIGHT-1,d3  ; while d < 22
    blt         .diag
    rts


;==============================================================================
; WipeFillDiagBRTL  -  Fill wipe order: diagonal stripes, bottom-right to top-left
;==============================================================================

WipeFillDiagBRTL:
    bsr         WipeFillDiagTLBR
    bsr         WipeReverseBuffer
    rts


;==============================================================================
; WipeFillCenterOut  -  Fill wipe order: outward from centre by Chebyshev distance
;
; Emits tiles sorted ascending by max(|x-WIPE_CENTER_X|, |y-WIPE_CENTER_Y|).
; Distance levels 0..7 (WIPE_MAX_DIST) cover the full 14x9 grid.
;==============================================================================

WipeFillCenterOut:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2                      ; write index
    moveq       #0,d5                   ; distance level = 0
.dist_loop
    moveq       #0,d1                   ; y = 0
.y_loop
    moveq       #0,d0                   ; x = 0
.x_loop
    ; Chebyshev distance = max(|x-CX|, |y-CY|)
    move.w      d0,d3
    sub.w       #WIPE_CENTER_X,d3
    bge         .x_abs
    neg.w       d3
.x_abs
    move.w      d1,d4
    sub.w       #WIPE_CENTER_Y,d4
    bge         .y_abs
    neg.w       d4
.y_abs
    cmp.w       d4,d3
    bge         .have_dist              ; d3 >= d4: d3 is the max
    move.w      d4,d3                   ; d4 > d3: use d4
.have_dist
    cmp.w       d5,d3
    bne         .skip_tile
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
.skip_tile
    addq.w      #1,d0
    cmp.w       #WALL_PAPER_WIDTH,d0
    blt         .x_loop
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_HEIGHT,d1
    blt         .y_loop
    addq.w      #1,d5
    cmp.w       #WIPE_MAX_DIST+1,d5     ; while distance < 8
    blt         .dist_loop
    rts


;==============================================================================
; WipeFillCenterIn  -  Fill wipe order: inward from edges to centre
;==============================================================================

WipeFillCenterIn:
    bsr         WipeFillCenterOut
    bsr         WipeReverseBuffer
    rts


;==============================================================================
; WipeReverseBuffer  -  Reverse WipeTileX and WipeTileY arrays in place
;
; Two-pointer swap: lo starts at 0, hi starts at WALL_PAPER_SIZE-1.
; Both arrays are swapped in lockstep so they stay in sync.
;==============================================================================

WipeReverseBuffer:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d0                      ; lo index = 0
    move.w      #WALL_PAPER_SIZE-1,d1   ; hi index = 125
.rev_loop
    cmp.w       d1,d0
    bge         .rev_done

    ; reverse TileX coordinates
    move.b      (a0,d0.w),d2
    move.b      (a0,d1.w),(a0,d0.w)
    move.b      d2,(a0,d1.w)
    ; reverse TileY coordinates
    move.b      (a1,d0.w),d2
    move.b      (a1,d1.w),(a1,d0.w)
    move.b      d2,(a1,d1.w)

    addq.w      #1,d0
    subq.w      #1,d1
    bra         .rev_loop
.rev_done
    rts
WipeFillTable:
    dc.l        WipeFillTopBottom
    dc.l        WipeFillBottomTop
    dc.l        WipeFillLeftRight
    dc.l        WipeFillRightLeft
    dc.l        WipeFillDiagTLBR
    dc.l        WipeFillDiagBRTL
    dc.l        WipeFillCenterOut
    dc.l        WipeFillCenterIn
    even

;==============================================================================
; WipeOppositeTable  -  Maps each wipe pattern to its directional inverse
;
; Index: pattern number (0..NUM_WIPE_PATTERNS-1)
; Value: index of the directional opposite
;
; Usage example:
;   moveq  #0,d0
;   move.b WipePattern(a5),d0
;   lea    WipeOppositeTable(pc),a0
;   move.b (a0,d0.w),d0              ; d0 = opposite pattern index
;==============================================================================

WipeOppositeTable:
    dc.b    WIPE_BOTTOM_TOP     ; opposite of WIPE_TOP_BOTTOM  (0)
    dc.b    WIPE_TOP_BOTTOM     ; opposite of WIPE_BOTTOM_TOP  (1)
    dc.b    WIPE_RIGHT_LEFT     ; opposite of WIPE_LEFT_RIGHT  (2)
    dc.b    WIPE_LEFT_RIGHT     ; opposite of WIPE_RIGHT_LEFT  (3)
    dc.b    WIPE_DIAG_BRTL      ; opposite of WIPE_DIAG_TLBR   (4)
    dc.b    WIPE_DIAG_TLBR      ; opposite of WIPE_DIAG_BRTL   (5)
    dc.b    WIPE_CENTER_IN      ; opposite of WIPE_CENTER_OUT  (6)
    dc.b    WIPE_CENTER_OUT     ; opposite of WIPE_CENTER_IN   (7)
    even                        ; ensure word-aligned for following code