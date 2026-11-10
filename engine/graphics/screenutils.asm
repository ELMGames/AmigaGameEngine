
;==============================================================================
; AMIGA GAME ENGINE
; screenutils.asm  -  Screen Effects and Visual Transitions
;==============================================================================
;
;
; Register convention:
;   a6 = CUSTOM   a5 = Variables base
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
    PUSHM         d0-d1/a0-a1

    ; Fast 4-pass Blitter copy of all 32 rows (81,920 bytes) from NonDisplayScreen to DisplayScreen
    lea           NonDisplayScreen,a0
    lea           DisplayScreen,a1

    WAITBLIT
    move.w        #$0000,BLTCON1(a6)
    move.w        #MINTERM_COPY,BLTCON0(a6)         ; USEA|USED, minterm $F0 (D=A)
    move.l        #$ffffffff,BLTAFWM(a6)     ; full mask
    move.w        #0,BLTAMOD(a6)
    move.w        #0,BLTDMOD(a6)

    ; Pass 1: 512 lines (20,480 bytes)
    move.l        a0,BLTAPT(a6)
    move.l        a1,BLTDPT(a6)
    move.w        #(512<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    ; Pass 2: 512 lines (20,480 bytes)
    adda.l        #512*SCREEN_WIDTH_BYTE,a0
    adda.l        #512*SCREEN_WIDTH_BYTE,a1
    move.l        a0,BLTAPT(a6)
    move.l        a1,BLTDPT(a6)
    move.w        #(512<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    ; Pass 3: 512 lines (20,480 bytes)
    adda.l        #512*SCREEN_WIDTH_BYTE,a0
    adda.l        #512*SCREEN_WIDTH_BYTE,a1
    move.l        a0,BLTAPT(a6)
    move.l        a1,BLTDPT(a6)
    move.w        #(512<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    ; Pass 4: 512 lines (20,480 bytes)
    adda.l        #512*SCREEN_WIDTH_BYTE,a0
    adda.l        #512*SCREEN_WIDTH_BYTE,a1
    move.l        a0,BLTAPT(a6)
    move.l        a1,BLTDPT(a6)
    move.w        #(512<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    POPM          d0-d1/a0-a1
    rts

;==============================================================================
; WipePickRandomColor  -  Select a random beveled color theme for the next wipe
;
; Picks one of 8 vibrant color themes (never repeating the immediately previous
; wipe color), patches COLOR17 (body) and COLOR18 (bevel highlight) in all
; 5-bitplane Copper palettes (cpTitlePal, cpLoadingPal, cpLevelCompletePal), and precomputes
; the 4-bitplane bitmasks for cpGame.
;
; Destroys: none (preserves all registers)
;==============================================================================

WipePickRandomColor:
    PUSHM       d0-d3/a0-a1

    RANDOMWORD
    add.w       VHPOSR(a6),d0
    add.w       TickCounter(a5),d0
    and.w       #7,d0
    cmp.w       WipePrevColorIdx(pc),d0
    bne.s       .color_ok
    addq.w      #1,d0
    and.w       #7,d0
.color_ok:
    lea         WipePrevColorIdx(pc),a0
    move.w      d0,(a0)

    lsl.w       #3,d0                   ; d0 = index * 8 bytes
    lea         WipeColorTable(pc),a0
    add.w       d0,a0

    move.w      (a0)+,d1                ; d1 = 5-plane Body RGB (COLOR17)
    move.w      (a0)+,d2                ; d2 = 5-plane Highlight RGB (COLOR18)

    ; Patch 5-bitplane Copper palettes (COLOR17 & COLOR18)
    move.w      d1,cpTitlePal+(17*4)+2
    move.w      d2,cpTitlePal+(18*4)+2
    move.w      d1,cpLoadingPal+(17*4)+2
    move.w      d2,cpLoadingPal+(18*4)+2
    move.w      d1,cpLevelCompletePal+(17*4)+2
    move.w      d2,cpLevelCompletePal+(18*4)+2

    ; Precompute 4-bitplane word masks ($7FFE or $0000 per plane) for cpGame
    move.w      (a0)+,d1                ; d1 = 4-plane Body color index (1..15)
    lea         Wipe4P_BodyWords(pc),a1
    moveq       #4-1,d3
.prep_body:
    moveq       #0,d0
    lsr.w       #1,d1
    bcc.s       .pb_set
    move.w      #$7ffe,d0
.pb_set:
    move.w      d0,(a1)+
    dbra        d3,.prep_body

    move.w      (a0)+,d2                ; d2 = 4-plane Highlight color index (1..15)
    lea         Wipe4P_HilightWords(pc),a1
    moveq       #4-1,d3
.prep_hi:
    moveq       #0,d0
    lsr.w       #1,d2
    bcc.s       .ph_set
    move.w      #$7ffe,d0
.ph_set:
    move.w      d0,(a1)+
    dbra        d3,.prep_hi

    POPM        d0-d3/a0-a1
    rts

WipePrevColorIdx:
    dc.w        -1
Wipe4P_BodyWords:
    dc.w        $7ffe, $7ffe, $7ffe, $0000
Wipe4P_HilightWords:
    dc.w        $7ffe, $0000, $0000, $0000

; 8 Vibrant Transition Block Color Themes:
;   dc.w BodyRGB_5P, HilightRGB_5P, BodyIdx_4P, HilightIdx_4P
; Destroys: none (preserves all registers)
WipeColorTable:
    dc.w        $025C, $03AE,  7,  1    ; 0: Royal Blue + Cyan-Blue bevel
    dc.w        $0193, $04E6,  5,  8    ; 1: Emerald Green + Bright Gold bevel
    dc.w        $0D12, $0F86, 12,  6    ; 2: Crimson Red + Sunset Orange bevel
    dc.w        $0E61, $0FC2,  6,  8    ; 3: Sunset Orange + Bright Yellow bevel
    dc.w        $0B72, $0FE6, 10,  8    ; 4: Golden Amber + Warm Yellow bevel
    dc.w        $072A, $0B6F, 11, 13    ; 5: Amethyst Purple + Lavender-Grey bevel
    dc.w        $0178, $03DF, 14,  1    ; 6: Deep Ocean Teal + Bright Cyan bevel
    dc.w        $0569, $09CD, 13,  3    ; 7: Steel Slate + Pure White bevel

;==============================================================================
; WipeBlitBlack  -  Draw one colored transition block on DisplayScreen
;
; Draws a 16x24-pixel beveled colored transition block at tile coordinates
; (d0 = 0..19, d1 = 0..8), covering the full 320x216 screen across the 20x9
; wipe grid:
;   - Row 0:      1px dark top border ($0000)
;   - Row 1:      1px bright bevel highlight ($7FFE)
;   - Rows 2..22: 21px colored block body ($7FFE, with 1px left/right border)
;   - Row 23:     1px dark bottom border ($0000)
;
; In:  d0.w = tile X (0..19)
;      d1.w = tile Y (0..8)
;      a5   = Variables base
;      a6   = CUSTOM
; Out: none
; Destroys: none (preserves all registers)
;==============================================================================

WipeBlitBlack:
WipeBlitTile:
    PUSHALL

    WAITBLIT

    lea         DisplayScreen,a1
    add.w       d0,d0                   ; d0 = byte column offset (X * 2 bytes = 16px per column)
    mulu.w      #24,d1                  ; d1 = pixel Y offset (Y * 24 scanlines)

    ; Check whether a 5-bitplane screen (Title / Loading / LevelComplete) or 4-bitplane cpGame is active
    tst.w       EnterGameCopper(a5)
    bne.s       .wipe_5plane
    tst.w       LoadingWipeActive(a5)
    bne.s       .wipe_5plane

    ; -------------------------------------------------------------------------
    ; 4-Bitplane In-Game Screen (cpGame: stride 160, camera ring buffer offset)
    ; -------------------------------------------------------------------------
    move.w      TilemapCameraY(a5),d2
    andi.w      #255,d2
    add.w       d2,d1                   ; d1 = absolute scanline in DisplayScreen ring buffer
    mulu.w      #TILEMAP_LINE_STRIDE,d1 ; d1 * 160
    ext.l       d0
    add.l       d0,d1
    add.l       d1,a1                   ; a1 -> top-left word of 16x24 tile in Plane 0

    moveq       #0,d6                   ; d6 = $0000 (border)

    ; Row 0: 1px dark top border (Color 0)
    move.w      d6,(a1)
    move.w      d6,40(a1)
    move.w      d6,80(a1)
    move.w      d6,120(a1)
    lea         TILEMAP_LINE_STRIDE(a1),a1

    ; Row 1: 1px top bevel highlight (precomputed in Wipe4P_HilightWords)
    lea         Wipe4P_HilightWords(pc),a0
    move.w      (a0)+,(a1)              ; Plane 0
    move.w      (a0)+,40(a1)            ; Plane 1
    move.w      (a0)+,80(a1)            ; Plane 2
    move.w      (a0)+,120(a1)           ; Plane 3
    lea         TILEMAP_LINE_STRIDE(a1),a1

    ; Rows 2..22 (21 scanlines): block body (precomputed in Wipe4P_BodyWords)
    lea         Wipe4P_BodyWords(pc),a0
    move.w      (a0)+,d2                ; Plane 0 word
    move.w      (a0)+,d3                ; Plane 1 word
    move.w      (a0)+,d4                ; Plane 2 word
    move.w      (a0)+,d5                ; Plane 3 word
    moveq       #21-1,d7
.loop_4p:
    move.w      d2,(a1)                 ; Plane 0
    move.w      d3,40(a1)               ; Plane 1
    move.w      d4,80(a1)               ; Plane 2
    move.w      d5,120(a1)              ; Plane 3
    lea         TILEMAP_LINE_STRIDE(a1),a1
    dbra        d7,.loop_4p

    ; Row 23: 1px dark bottom border (Color 0)
    move.w      d6,(a1)
    move.w      d6,40(a1)
    move.w      d6,80(a1)
    move.w      d6,120(a1)

    POPALL
    rts

.wipe_5plane:
    ; -------------------------------------------------------------------------
    ; 5-Bitplane Menu / Loading Screen (stride 200, DisplayScreen + 0)
    ; -------------------------------------------------------------------------
    mulu.w      #SCREEN_STRIDE,d1       ; d1 * 200
    ext.l       d0
    add.l       d0,d1
    add.l       d1,a1                   ; a1 -> top-left word of 16x24 tile in Plane 0

    moveq       #0,d3                   ; d3 = $0000
    move.w      #$7ffe,d4               ; d4 = $7FFE (14px interior fill with 1px left/right border)

    ; Row 0: 1px dark top border (Color 0)
    move.w      d3,(a1)
    move.w      d3,40(a1)
    move.w      d3,80(a1)
    move.w      d3,120(a1)
    move.w      d3,160(a1)
    lea         SCREEN_STRIDE(a1),a1

    ; Row 1: 1px sky-blue top bevel highlight (Color 18 = %10010 = $03AE)
    move.w      d3,(a1)                 ; Plane 0 = 0
    move.w      d4,40(a1)               ; Plane 1 = $7FFE
    move.w      d3,80(a1)               ; Plane 2 = 0
    move.w      d3,120(a1)              ; Plane 3 = 0
    move.w      d4,160(a1)              ; Plane 4 = $7FFE
    lea         SCREEN_STRIDE(a1),a1

    ; Rows 2..22 (21 scanlines): royal blue block body (Color 17 = %10001 = $025C)
    moveq       #21-1,d7
.loop_5p:
    move.w      d4,(a1)                 ; Plane 0 = $7FFE
    move.w      d3,40(a1)               ; Plane 1 = 0
    move.w      d3,80(a1)               ; Plane 2 = 0
    move.w      d3,120(a1)              ; Plane 3 = 0
    move.w      d4,160(a1)              ; Plane 4 = $7FFE
    lea         SCREEN_STRIDE(a1),a1
    dbra        d7,.loop_5p

    ; Row 23: 1px dark bottom border (Color 0)
    move.w      d3,(a1)
    move.w      d3,40(a1)
    move.w      d3,80(a1)
    move.w      d3,120(a1)
    move.w      d3,160(a1)

    POPALL
    rts




;==============================================================================
; WipeFillTopBottom  -  Fill wipe order: row by row, top to bottom
;
; Destroys: d0-d2/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================
WipeFillTopBottom:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2                      ; write index (0..179)
    moveq       #0,d1                   ; y = 0
.row
    moveq       #0,d0                   ; x = 0
.col
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
    addq.w      #1,d0
    cmp.w       #WIPE_GRID_COLS,d0
    blt         .col
    addq.w      #1,d1
    cmp.w       #WIPE_GRID_ROWS,d1
    blt         .row
    rts


;==============================================================================
; WipeFillBottomTop  -  Fill wipe order: row by row, bottom to top
;
; Destroys: d0-d2/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

WipeFillBottomTop:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2
    moveq       #WIPE_GRID_ROWS-1,d1 ; y = 8, count down to 0
.row
    moveq       #0,d0
.col
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
    addq.w      #1,d0
    cmp.w       #WIPE_GRID_COLS,d0
    blt         .col
    subq.w      #1,d1
    bpl         .row                    ; loop while y >= 0
    rts


;==============================================================================
; WipeFillLeftRight  -  Fill wipe order: column by column, left to right
;
; Destroys: d0-d2/a0-a1 (preserves everything else, including a5/a6)
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
    cmp.w       #WIPE_GRID_ROWS,d1
    blt         .row
    addq.w      #1,d0
    cmp.w       #WIPE_GRID_COLS,d0
    blt         .col
    rts


;==============================================================================
; WipeFillRightLeft  -  Fill wipe order: column by column, right to left
;
; Destroys: d0-d2/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

WipeFillRightLeft:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d2
    moveq       #WIPE_GRID_COLS-1,d0  ; x = 19, count down to 0
.col
    moveq       #0,d1
.row
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
    addq.w      #1,d1
    cmp.w       #WIPE_GRID_ROWS,d1
    blt         .row
    subq.w      #1,d0
    bpl         .col                    ; loop while x >= 0
    rts


;==============================================================================
; WipeFillDiagTLBR  -  Fill wipe order: diagonal stripes, top-left to bottom-right
;
; Iterates over diagonals where x+y = constant (d = 0..21).
; For each diagonal, emits all tiles (x,y) where x = d-y, 0<=x<=13, 0<=y<=8.
; 28 diagonals cover all 20x9 = 180 blocks exactly.
;
; Destroys: d0-d3/a0-a1 (preserves everything else, including a5/a6)
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
    cmp.w       #WIPE_GRID_COLS,d0    ; x >= 20: diagonal not yet reached
    bge         .next_y
    move.b      d0,(a0,d2.w)
    move.b      d1,(a1,d2.w)
    addq.w      #1,d2
.next_y
    addq.w      #1,d1
    cmp.w       #WIPE_GRID_ROWS,d1
    blt         .scan
    addq.w      #1,d3
    cmp.w       #WIPE_GRID_COLS+WIPE_GRID_ROWS-1,d3  ; while d < 28
    blt         .diag
    rts


;==============================================================================
; WipeFillDiagBRTL  -  Fill wipe order: diagonal stripes, bottom-right to top-left
;
; Destroys: d0-d3/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

WipeFillDiagBRTL:
    bsr         WipeFillDiagTLBR
    bsr         WipeReverseBuffer
    rts


;==============================================================================
; WipeFillCenterOut  -  Fill wipe order: outward from centre by Chebyshev distance
;
; Emits tiles sorted ascending by max(|x-WIPE_CENTER_X|, |y-WIPE_CENTER_Y|).
; Distance levels 0..10 (WIPE_MAX_DIST) cover the full 20x9 grid.
;
; Destroys: d0-d5/a0-a1 (preserves everything else, including a5/a6)
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
    cmp.w       #WIPE_GRID_COLS,d0
    blt         .x_loop
    addq.w      #1,d1
    cmp.w       #WIPE_GRID_ROWS,d1
    blt         .y_loop
    addq.w      #1,d5
    cmp.w       #WIPE_MAX_DIST+1,d5     ; while distance < 8
    blt         .dist_loop
    rts


;==============================================================================
; WipeFillCenterIn  -  Fill wipe order: inward from edges to centre
;
; Destroys: d0-d5/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

WipeFillCenterIn:
    bsr         WipeFillCenterOut
    bsr         WipeReverseBuffer
    rts


;==============================================================================
; WipeReverseBuffer  -  Reverse WipeTileX and WipeTileY arrays in place
;
; Two-pointer swap: lo starts at 0, hi starts at WIPE_GRID_SIZE-1.
; Both arrays are swapped in lockstep so they stay in sync.
;
; Destroys: d0-d2/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

WipeReverseBuffer:
    lea         WipeTileX(a5),a0
    lea         WipeTileY(a5),a1
    clr.w       d0                      ; lo index = 0
    move.w      #WIPE_GRID_SIZE-1,d1   ; hi index = 179
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
;
; Destroys: none (preserves all registers)
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
