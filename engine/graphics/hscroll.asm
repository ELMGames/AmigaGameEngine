;==============================================================================
; AMIGA GAME ENGINE
; hscroll.asm  -  Horizontal scrolling tilemap with an ever-advancing pointer
;==============================================================================
;
; The engine's tilemap renderer (tmx_renderer.asm) scrolls up and down a
; screen one screen wide. This module scrolls sideways through a map of any
; width, in up to three tile layers, 16 colours, using the technique many A500 games
; used: the bitplane pointers simply move on through memory as the camera
; moves right, and the buffer costs only 2 bytes per tile column of level
; width beyond one screen.
;
; How it works. Each scanline holds 4 interleaved plane-rows of 23 words
; (HS_ROW_BYTES = 46). The display fetches 21 words of each plane-row
; (DDFSTRT = $30) and skips the rest with the modulo. World word w of
; scanline y and plane p always sits at the same address:
;
;     buffer + y * 184 + p * 46 + 2 * (w + 2)
;
; For large w that address runs past the end of its own plane-row into the
; next one: word w of plane p shares memory with word w - 23 of plane p + 1.
; Two columns 23 words apart are never both on screen, because only 21 are
; fetched, so the sharing is never seen. Scrolling right one word moves the
; pointer 2 bytes and brings one new column into view on the right; it is
; drawn into memory that belonged to a column that has just left on the
; left. Scrolling left works the same way in reverse.
;
; The module keeps 23 columns drawn: the 21 fetched and a spare on each
; side, so a column is always drawn at least a frame before it can scroll
; into view, and drawing never races the beam.
;
; Fine scrolling uses BPLCON1, which delays the picture to the right: the
; delay is (-CameraX) & 15 and the first fetched word is
; ((CameraX + 15) >> 4) - 1.
;
; Two buffers, as in the vertical engine: HsDisplayBuf is shown, HsCleanBuf
; holds the same tiles with nothing drawn over them and is the source for
; erasing BOBs.
;
; The game provides:
;   HsTileSheet      the tile sheet: interleaved, 4 planes, 16x16 tiles,
;                    HS_SHEET_COLS tiles per row (Chip RAM)
;   HsTileMask       its interleaved cookie-cut mask, same layout (Chip RAM)
;   HsDisplayBuf     HS_BUF_SIZE bytes of Chip RAM BSS (the shown screen)
;   HsCleanBuf       HS_BUF_SIZE bytes of Chip RAM BSS (the clean copy)
;   HsCopperScroll   a Copper MOVE to BPLCON1 (its data word is patched)
;   HsCopperPlanes   Copper MOVEs to BPL1PTH/L .. BPL4PTH/L (patched)
;   HsMapBack(a5), HsMapMid(a5), HsMapFront(a5)
;                    its three layers (word maps, 0 = layer unused), and
;                    HsAnimFirst/HsAnimFrames(a5) for an animated tile run,
;                    all set before HsInit
; Both Copper entries must sit after a WAIT for a line just above the
; display window, so a pointer change takes effect on the frame it is made
; (see games/meadow_run/main.asm).
;==============================================================================


;==============================================================================
; HsInit  -  Prepare the scroller and draw the view around a camera position
;
; Works out the byte offset of every tile in the sheet, sets the camera's
; limits, and draws the 23 columns around the camera into both buffers.
; Call it with bitplane DMA off, or the drawing shows.
;
; In:       d0.w = camera X in pixels, a5 = Variables, a6 = CUSTOM
; Destroys: none (preserves all registers)
;==============================================================================

HsInit:
    PUSHM       d0-d3/a0

    ; Byte offset of each tile: sheet row * one row of tiles + column * 2
    lea         HsTileOffsets(a5),a0
    moveq       #0,d1                   ; d1 = tile index
.offsets:
    moveq       #0,d2
    move.w      d1,d2
    divu        #HS_SHEET_COLS,d2       ; d2.lo = sheet row, d2.hi = column
    move.l      d2,d3
    swap        d3
    add.w       d3,d3                   ; d3 = column * 2 bytes
    mulu        #16*HS_SHEET_ROW_BYTES*HS_PLANES,d2 ; row * 16 lines of 4 planes
    add.w       d3,d2
    move.w      d2,(a0)+
    addq.w      #1,d1
    cmp.w       #HS_MAX_TILES,d1
    blt.s       .offsets

    move.w      #HS_MAP_COLS*16-HS_VIEW_WIDTH,HsMaxCameraX(a5)

    ; Mark nothing drawn: HsSetCamera then draws every column of the view
    move.w      #$7fff,HsDrawnLeft(a5)
    move.w      #$7ffe,HsDrawnRight(a5)
    bsr         HsSetCamera

    POPM        d0-d3/a0
    rts


;==============================================================================
; HsSetCamera  -  Move the view, and draw the columns that scroll into range
;
; Clamps the camera to the map, patches the fine scroll (BPLCON1) and the
; four bitplane pointers into the Copper list, then draws whatever columns
; are needed to keep [first word - 1, first word + 21] drawn in both
; buffers. A move of one column or less (16 pixels a frame) draws at most
; one column; a jump further than the view redraws all 23.
;
; Call it early in the frame, before the Copper reaches HsCopperPlanes, so
; the new position is shown on this frame.
;
; In:       d0.w = wanted camera X in pixels
; Destroys: none (preserves all registers)
;==============================================================================

HsSetCamera:
    PUSHM       d0-d3/d7/a0

    ; Clamp to 0 .. HsMaxCameraX
    tst.w       d0
    bpl.s       .min_ok
    moveq       #0,d0
.min_ok:
    cmp.w       HsMaxCameraX(a5),d0
    ble.s       .max_ok
    move.w      HsMaxCameraX(a5),d0
.max_ok:
    move.w      d0,HsCameraX(a5)

    ; Fine scroll: delay = (-CameraX) & 15, in both nibbles (odd and even planes)
    move.w      d0,d1
    neg.w       d1
    and.w       #15,d1
    move.w      d1,d2
    lsl.w       #4,d2
    or.w        d2,d1
    move.w      d1,HsCopperScroll+2

    ; Coarse scroll: the first fetched word is world word ((CameraX + 15) >> 4) - 1
    add.w       #15,d0
    lsr.w       #4,d0
    subq.w      #1,d0
    move.w      d0,HsFirstWord(a5)

    ; Bitplane pointers: HsDisplayBuf + 2 * (first word + 2), planes 46 bytes apart
    addq.w      #2,d0
    add.w       d0,d0
    ext.l       d0
    add.l       #HsDisplayBuf,d0
    lea         HsCopperPlanes,a0
    move.l      #HS_ROW_BYTES,d1
    moveq       #HS_PLANES,d7
    bsr         CopperSetPtrs

    ; Columns outside [first - 1, first + 21] share memory with ones inside:
    ; forget them first
    move.w      HsFirstWord(a5),d2
    move.w      d2,d3
    subq.w      #1,d3                   ; d3 = leftmost column to keep
    cmp.w       HsDrawnLeft(a5),d3
    ble.s       .left_kept
    move.w      d3,HsDrawnLeft(a5)
.left_kept:
    add.w       #HS_DRAWN_COLS-1,d3     ; d3 = rightmost column to keep
    cmp.w       HsDrawnRight(a5),d3
    bge.s       .right_kept
    move.w      d3,HsDrawnRight(a5)
.right_kept:
    ; Nothing left in range (a jump, or the first call): start again empty
    move.w      HsDrawnRight(a5),d1
    addq.w      #1,d1
    cmp.w       HsDrawnLeft(a5),d1
    bge.s       .extend
    move.w      d2,d1
    subq.w      #1,d1
    move.w      d1,HsDrawnLeft(a5)      ; empty range just left of the view:
    subq.w      #1,d1
    move.w      d1,HsDrawnRight(a5)     ; the right loop draws all 23 columns

.extend:
    ; Extend to the left
    move.w      d2,d3
    subq.w      #1,d3
.left_loop:
    move.w      HsDrawnLeft(a5),d0
    cmp.w       d3,d0
    ble.s       .left_done
    subq.w      #1,d0
    move.w      d0,HsDrawnLeft(a5)
    bsr         HsDrawColumnBoth
    bra.s       .left_loop
.left_done:
    ; Extend to the right
    add.w       #HS_DRAWN_COLS-1,d3
.right_loop:
    move.w      HsDrawnRight(a5),d0
    cmp.w       d3,d0
    bge.s       .right_done
    addq.w      #1,d0
    move.w      d0,HsDrawnRight(a5)
    bsr         HsDrawColumnBoth
    bra.s       .right_loop
.right_done:
    POPM        d0-d3/d7/a0
    rts


;==============================================================================
; HsDrawColumnBoth  -  Draw one map column into the clean and shown buffers
;
; In:       d0.w = world column (outside the map draws an empty column)
; Destroys: none (preserves all registers)
;==============================================================================

HsDrawColumnBoth:
    move.l      a0,-(sp)
    lea         HsCleanBuf,a0
    bsr         HsDrawColumn
    lea         HsDisplayBuf,a0
    bsr         HsDrawColumn
    move.l      (sp)+,a0
    rts


;==============================================================================
; HsDrawColumn  -  Draw one map column, top to bottom, into one buffer
;
; In:       a0 = HsDisplayBuf or HsCleanBuf, d0.w = world column
;           (a column outside the map is drawn empty)
; Destroys: none (preserves all registers)
;==============================================================================

HsDrawColumn:
    PUSHM       d1-d2/d4/a1
    move.w      d0,d1
    addq.w      #2,d1
    add.w       d1,d1
    lea         (a0,d1.w),a1            ; a1 = top cell of the column, plane 0
    moveq       #-1,d2                  ; d2 = map cell index, -1 outside the map
    tst.w       d0
    bmi.s       .go
    cmp.w       #HS_MAP_COLS,d0
    bge.s       .go
    move.w      d0,d2                   ; row 0 of this column
.go:
    moveq       #HS_MAP_ROWS-1,d4
.row:
    bsr         HsDrawCell
    lea         16*HS_LINE_STRIDE(a1),a1 ; next tile row down
    tst.w       d2
    bmi.s       .next
    add.w       #HS_MAP_COLS,d2         ; same column, next row
.next:
    dbra        d4,.row
    POPM        d1-d2/d4/a1
    rts


;==============================================================================
; HsDrawCell  -  Draw one map cell, all three layers, into one buffer
;
; The background tile is copied (A to D), or the cell cleared for tile 0;
; the platform and foreground tiles are cookie-cut over it with the sheet's
; mask, as Duck Rescue's renderer draws its layers (Section 27.4). Each blit
; is 1 word by 64 plane-rows; the buffer's plane-rows are 46 bytes apart.
;
; In:       a1 = the cell's top-left word, plane 0, in a buffer
;           d2.w = the cell's index in the maps (row * HS_MAP_COLS + column),
;                  or -1 for a cell outside the map (drawn empty)
; Destroys: none (preserves all registers)
;==============================================================================

HsDrawCell:
    PUSHM       d0-d4/a0
    moveq       #0,d0                   ; d0 = background tile
    moveq       #0,d1                   ; d1 = platform tile
    moveq       #0,d3                   ; d3 = foreground tile
    tst.w       d2
    bmi.s       .tiles
    add.w       d2,d2                   ; word index
    move.l      HsMapBack(a5),d4
    beq.s       .no_back
    movea.l     d4,a0
    move.w      (a0,d2.w),d0
.no_back:
    move.l      HsMapMid(a5),d4
    beq.s       .no_mid
    movea.l     d4,a0
    move.w      (a0,d2.w),d1
.no_mid:
    move.l      HsMapFront(a5),d4
    beq.s       .tiles
    movea.l     d4,a0
    move.w      (a0,d2.w),d3
.tiles:
    WAITBLIT
    move.l      #$ffffffff,BLTAFWM(a6)
    clr.w       BLTCON1(a6)
    move.w      #HS_SHEET_ROW_BYTES-2,BLTAMOD(a6)
    move.w      #HS_SHEET_ROW_BYTES-2,BLTBMOD(a6)
    move.w      #HS_ROW_BYTES-2,BLTCMOD(a6)
    move.w      #HS_ROW_BYTES-2,BLTDMOD(a6)
    move.w      #$0100,BLTCON0(a6)      ; tile 0: D only, minterm 0 (clear)
    tst.w       d0
    beq.s       .back_blit
    bsr         HsTileOffset            ; d0.l = the tile's offset in the sheet
    lea         HsTileSheet,a0
    adda.l      d0,a0
    move.l      a0,BLTAPT(a6)
    move.w      #MINTERM_COPY,BLTCON0(a6) ; A -> D: copy the background tile
.back_blit:
    move.l      a1,BLTDPT(a6)
    move.w      #(16*HS_PLANES<<6)|1,BLTSIZE(a6)

    move.w      d1,d0
    bsr.s       HsCookieTile            ; platforms (and pickups)
    move.w      d3,d0
    bsr.s       HsCookieTile            ; foreground
    POPM        d0-d4/a0
    rts


;==============================================================================
; HsCookieTile  -  Cookie-cut one tile into a cell (nothing for tile 0)
;
; In:       d0.w = tile index, a1 = the cell's top-left word, plane 0
; Destroys: none (preserves all registers)
;==============================================================================

HsCookieTile:
    tst.w       d0
    beq.s       .none
    PUSHM       d0/a0/a2
    bsr         HsTileOffset
    lea         HsTileMask,a0
    adda.l      d0,a0
    lea         HsTileSheet,a2
    adda.l      d0,a2
    WAITBLIT
    move.l      #$ffffffff,BLTAFWM(a6)
    clr.w       BLTCON1(a6)
    move.w      #HS_SHEET_ROW_BYTES-2,BLTAMOD(a6)
    move.w      #HS_SHEET_ROW_BYTES-2,BLTBMOD(a6)
    move.w      #HS_ROW_BYTES-2,BLTCMOD(a6)
    move.w      #HS_ROW_BYTES-2,BLTDMOD(a6)
    move.w      #MINTERM_COOKIE_CUT,BLTCON0(a6)
    move.l      a0,BLTAPT(a6)           ; mask
    move.l      a2,BLTBPT(a6)           ; tile
    move.l      a1,BLTCPT(a6)           ; what is there already
    move.l      a1,BLTDPT(a6)
    move.w      #(16*HS_PLANES<<6)|1,BLTSIZE(a6)
    POPM        d0/a0/a2
.none:
    rts


;==============================================================================
; HsTileOffset  -  Byte offset of a tile in the sheet, after animation
;
; A tile in the animated run [HsAnimFirst, HsAnimFirst + HsAnimFrames) is
; drawn as frame HsAnimFirst + HsAnimPhase, so the map only ever holds the
; run's first tile and one variable animates every duckling in the level.
;
; In:       d0.w = tile index
; Out:      d0.l = byte offset in HsTileSheet (and HsTileMask)
; Destroys: none besides d0
;==============================================================================

HsTileOffset:
    movem.l     d1/a0,-(sp)
    move.w      d0,d1
    sub.w       HsAnimFirst(a5),d1
    bcs.s       .plain                  ; below the run (unsigned compare)
    cmp.w       HsAnimFrames(a5),d1
    bcc.s       .plain                  ; past it, or no animation (0 frames)
    move.w      HsAnimFirst(a5),d0
    add.w       HsAnimPhase(a5),d0
.plain:
    add.w       d0,d0
    lea         HsTileOffsets(a5),a0
    moveq       #0,d1
    move.w      (a0,d0.w),d1
    move.l      d1,d0
    movem.l     (sp)+,d1/a0
    rts


;==============================================================================
; HsCellAddress  -  Where a map cell is in a buffer, and its map index
;
; In:       d0.w = column, d1.w = row
; Out:      d2.w = map index (row * HS_MAP_COLS + column)
;           d3.l = byte offset of the cell's top-left word in a buffer
;==============================================================================

HsCellAddress:
    move.w      d1,d2
    mulu        #HS_MAP_COLS,d2
    add.w       d0,d2
    move.w      d1,d3
    mulu        #16*HS_LINE_STRIDE,d3   ; d3.l = the tile row's offset
    move.l      d0,-(sp)
    addq.w      #2,d0
    add.w       d0,d0
    ext.l       d0
    add.l       d0,d3
    move.l      (sp)+,d0
    rts


;==============================================================================
; HsRedrawCell  -  Redraw one map cell in both buffers, if it is drawn
;
; For a map change during play, such as a collected duckling. The cell is built
; in HsCleanBuf and copied to HsDisplayBuf in one blit. Call it before the
; frame's BOBs are erased and drawn: the copy overwrites the whole cell,
; and the erase then copies the new clean cell back over the old BOB.
;
; In:       d0.w = column, d1.w = row
; Destroys: none (preserves all registers)
;==============================================================================

HsRedrawCell:
    cmp.w       HsDrawnLeft(a5),d0
    blt.s       .skip
    cmp.w       HsDrawnRight(a5),d0
    bgt.s       .skip
    PUSHM       d2-d3/a1
    bsr.s       HsCellAddress
    lea         HsCleanBuf,a1           ; build the cell in the clean buffer,
    adda.l      d3,a1                   ; layer by layer...
    bsr         HsDrawCell
    WAITBLIT                            ; ...then copy it to the shown one in a
    move.l      #$ffffffff,BLTAFWM(a6)  ; single blit, so the beam never shows
    clr.w       BLTCON1(a6)             ; a half-built cell
    move.w      #MINTERM_COPY,BLTCON0(a6)
    move.w      #HS_ROW_BYTES-2,BLTAMOD(a6)
    move.w      #HS_ROW_BYTES-2,BLTDMOD(a6)
    move.l      a1,BLTAPT(a6)
    lea         HsDisplayBuf,a1
    adda.l      d3,a1
    move.l      a1,BLTDPT(a6)
    move.w      #(16*HS_PLANES<<6)|1,BLTSIZE(a6)
    POPM        d2-d3/a1
.skip:
    rts


;==============================================================================
; HsAnimate  -  Show another frame of the animated tiles
;
; Sets HsAnimPhase and redraws, in both buffers, every drawn cell whose
; platform tile is in the animated run. Only the 23 drawn columns are
; scanned, so the cost depends on what is near the camera, not on the level.
; Call it before the frame's BOBs are erased and drawn, as HsRedrawCell.
;
; In:       d0.w = the new phase (0 .. HsAnimFrames - 1)
; Destroys: none (preserves all registers)
;==============================================================================

HsAnimate:
    move.w      d0,HsAnimPhase(a5)
    tst.l       HsMapMid(a5)
    beq.s       .none
    PUSHM       d0-d6/a0
    movea.l     HsMapMid(a5),a0
    move.w      HsDrawnLeft(a5),d0
    bpl.s       .left_ok
    moveq       #0,d0                   ; columns left of the map hold nothing
.left_ok:
    move.w      HsDrawnRight(a5),d6
    cmp.w       #HS_MAP_COLS-1,d6
    ble.s       .col
    move.w      #HS_MAP_COLS-1,d6
.col:
    cmp.w       d6,d0
    bgt.s       .done
    moveq       #0,d1                   ; row
    move.w      d0,d5
    add.w       d5,d5                   ; d5 = word offset of (column, row 0)
.row:
    move.w      (a0,d5.w),d4
    sub.w       HsAnimFirst(a5),d4
    cmp.w       HsAnimFrames(a5),d4     ; unsigned: inside the run?
    bcc.s       .not_anim
    bsr         HsRedrawCell
.not_anim:
    add.w       #HS_MAP_COLS*2,d5
    addq.w      #1,d1
    cmp.w       #HS_MAP_ROWS,d1
    blt.s       .row
    addq.w      #1,d0
    bra.s       .col
.done:
    POPM        d0-d6/a0
.none:
    rts


;==============================================================================
; HsStampFront  -  Cookie-cut the foreground over a rectangle of HsDisplayBuf
;
; Call it after drawing a BOB, with the BOB's rectangle: every foreground
; tile it overlaps is drawn again on top, so the BOB passes behind it. Only
; the shown buffer is touched; the BOB's erase next frame restores the
; clean cells, which already hold the foreground.
;
; In:       d0.w = world X, d1.w = world Y, d2.w = width, d3.w = height (pixels)
; Destroys: none (preserves all registers)
;==============================================================================

HsStampFront:
    tst.l       HsMapFront(a5)
    beq         .none
    PUSHM       d0-d7/a0-a1
    move.w      d0,d4
    add.w       d2,d4
    subq.w      #1,d4
    asr.w       #4,d4                   ; d4 = last column
    move.w      d1,d5
    add.w       d3,d5
    subq.w      #1,d5
    asr.w       #4,d5                   ; d5 = last row
    asr.w       #4,d0                   ; d0 = first column
    asr.w       #4,d1                   ; d1 = first row
    tst.w       d0                      ; clip to the map
    bpl.s       .c0
    moveq       #0,d0
.c0:
    tst.w       d1
    bpl.s       .r0
    moveq       #0,d1
.r0:
    cmp.w       #HS_MAP_COLS-1,d4
    ble.s       .c1
    move.w      #HS_MAP_COLS-1,d4
.c1:
    cmp.w       #HS_MAP_ROWS-1,d5
    ble.s       .r1
    move.w      #HS_MAP_ROWS-1,d5
.r1:
    movea.l     HsMapFront(a5),a0
    move.w      d0,d6                   ; d6 = first column, kept
.row:
    move.w      d6,d0
.cell:
    cmp.w       d4,d0
    bgt.s       .next_row
    bsr         HsCellAddress           ; d2 = index, d3.l = offset
    add.w       d2,d2
    move.w      (a0,d2.w),d7
    beq.s       .next_cell
    lea         HsDisplayBuf,a1
    adda.l      d3,a1
    move.w      d0,-(sp)
    move.w      d7,d0
    bsr         HsCookieTile
    move.w      (sp)+,d0
.next_cell:
    addq.w      #1,d0
    bra.s       .cell
.next_row:
    addq.w      #1,d1
    cmp.w       d5,d1
    ble.s       .row
    POPM        d0-d7/a0-a1
.none:
    rts

;==============================================================================
; HsBobOffset  -  Byte offset of a world pixel position in a screen buffer
;
; In:  d0.w = world X, d1.w = world Y (scanline)
; Out: d0.l = byte offset of the word holding X, plane 0
;      d1.w = X & 15, the barrel shift
;==============================================================================

HsBobOffset:
    move.w      d0,-(sp)
    mulu        #HS_LINE_STRIDE,d1      ; d1.l = Y * 184
    asr.w       #4,d0                   ; world word
    addq.w      #2,d0
    add.w       d0,d0
    ext.l       d0
    add.l       d1,d0                   ; d0.l = offset
    move.w      (sp)+,d1
    and.w       #15,d1                  ; d1 = shift
    rts


;==============================================================================
; HsDrawBob  -  Cookie-cut a BOB into HsDisplayBuf at a world position
;
; The source is an interleaved sheet with an interleaved mask of the same
; shape (Chapter 11). The blit is always one word wider than the cell, with
; BLTALWM = 0 masking the extra source word, as in bob_compositor.asm.
;
; In:  a0 = graphic, a1 = mask: the cell's top-left word in the sheet
;      d0.w = world X, d1.w = world Y (top line)
;      d2.w = height in scanlines
;      d3.w = bytes in one plane-row of the sheet
;      d4.w = cell width in words
; Destroys: none (preserves all registers)
;==============================================================================

HsDrawBob:
    PUSHM       d0-d6/a2
    bsr         HsBobOffset             ; d0.l = offset, d1 = shift
    lea         HsDisplayBuf,a2
    adda.l      d0,a2
    ror.w       #4,d1                   ; shift into bits 15-12
    move.w      d4,d5
    addq.w      #1,d5                   ; d5 = blit width in words
    move.w      d5,d6
    add.w       d6,d6                   ; d6 = blit width in bytes

    WAITBLIT
    move.w      d1,BLTCON1(a6)          ; B shift
    or.w        #MINTERM_COOKIE_CUT,d1
    move.w      d1,BLTCON0(a6)          ; A shift, ABCD, cookie-cut
    move.l      #$ffff0000,BLTAFWM(a6)  ; last word of A masked to 0
    move.w      d3,d0
    sub.w       d6,d0
    move.w      d0,BLTAMOD(a6)          ; sheet modulo
    move.w      d0,BLTBMOD(a6)
    move.w      #HS_ROW_BYTES,d0
    sub.w       d6,d0
    move.w      d0,BLTCMOD(a6)          ; buffer modulo
    move.w      d0,BLTDMOD(a6)
    move.l      a1,BLTAPT(a6)
    move.l      a0,BLTBPT(a6)
    move.l      a2,BLTCPT(a6)
    move.l      a2,BLTDPT(a6)
    move.w      d2,d0
    lsl.w       #2,d0                   ; height * 4 planes
    lsl.w       #6,d0
    or.w        d5,d0
    move.w      d0,BLTSIZE(a6)
    POPM        d0-d6/a2
    rts


;==============================================================================
; HsEraseBob  -  Restore a BOB's rectangle from HsCleanBuf
;
; In:  d0.w = world X, d1.w = world Y, d2.w = height, d4.w = cell width in
;      words: the same values the BOB was drawn with
; Destroys: none (preserves all registers)
;==============================================================================

HsEraseBob:
    PUSHM       d0-d6/a0-a1
    bsr         HsBobOffset             ; d0.l = offset
    lea         HsCleanBuf,a0
    adda.l      d0,a0
    lea         HsDisplayBuf,a1
    adda.l      d0,a1
    move.w      d4,d5
    addq.w      #1,d5                   ; same width as the draw
    move.w      #HS_ROW_BYTES,d6
    sub.w       d5,d6
    sub.w       d5,d6                   ; d6 = modulo

    WAITBLIT
    move.w      #MINTERM_COPY,BLTCON0(a6) ; A -> D
    clr.w       BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      d6,BLTAMOD(a6)
    move.w      d6,BLTDMOD(a6)
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      d2,d0
    lsl.w       #2,d0
    lsl.w       #6,d0
    or.w        d5,d0
    move.w      d0,BLTSIZE(a6)
    POPM        d0-d6/a0-a1
    rts
