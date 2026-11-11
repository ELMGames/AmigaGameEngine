;==============================================================================
; AMIGA GAME ENGINE
; water_effects.asm  -  Real-Time Water Wave Simulation, Refraction & Submerge Engine
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapInitWater:
    PUSHM       d0-d7/a0-a4

    ; Check if LevelDef defines a water layer
    move.l      CurrentLevelDef(a5),d0
    beq         .no_water
    movea.l     d0,a0
    move.l      LevelDef_WaterMap(a0),d0
    beq         .no_water

    ; Copy binary water map into LiveWaterMap working buffer
    ; Size is 8-byte header (4 words) + CurrentMapSize words
    movea.l     d0,a0
    lea         LiveWaterMap(a5),a1
    move.w      CurrentMapSize(a5),d2
    addq.w      #4,d2                  ; 4 header words
    subq.w      #1,d2
.copy_map:
    move.w      (a0)+,(a1)+
    dbra        d2,.copy_map

    ; Scan LiveWaterMap (after 8-byte header) from top row (0) to bottom row
    ; to find the first row where water is placed in the level.
    lea         LiveWaterMap+8(a5),a0
    moveq       #0,d0                  ; d0 = current row index
    move.w      CurrentMapHeight(a5),d1 ; d1 = total rows
.find_row_loop:
    cmp.w       d1,d0
    bge.s       .fallback_bottom_row
    moveq       #TILEMAP_MAP_WIDTH-1,d2
.find_col_loop:
    tst.w       (a0)+
    bne.s       .found_water_row
    dbra        d2,.find_col_loop
    addq.w      #1,d0
    bra.s       .find_row_loop

.fallback_bottom_row:
    move.w      CurrentMapHeight(a5),d0
    subq.w      #1,d0
.found_water_row:
    move.w      d0,WaterCurrentRow(a5)
    lsl.w       #4,d0
    move.w      d0,WaterPixelY(a5)
    clr.w       WaterSubTick(a5)

    ; Populate LiveWaterMap from WaterCurrentRow down to CurrentMapHeight-1:
    ;   Row WaterCurrentRow     -> WATER_TILE_SURFACE
    ;   All rows below that     -> WATER_TILE_DEEP
    lea         LiveWaterMap+8(a5),a0
    move.w      WaterCurrentRow(a5),d1
    move.w      d1,d2
    mulu.w      #TILEMAP_MAP_WIDTH*2,d2
    adda.l      d2,a0
    moveq       #TILEMAP_MAP_WIDTH-1,d3
    move.w      #WATER_TILE_SURFACE,d4
.init_surf_loop:
    move.w      d4,(a0)+
    dbra        d3,.init_surf_loop

    addq.w      #1,d1                  ; d1 = WaterCurrentRow + 1
    move.w      #WATER_TILE_DEEP,d4
.init_deep_row_loop:
    cmp.w       CurrentMapHeight(a5),d1
    bge.s       .init_map_done
    moveq       #TILEMAP_MAP_WIDTH-1,d3
.init_deep_col_loop:
    move.w      d4,(a0)+
    dbra        d3,.init_deep_col_loop
    addq.w      #1,d1
    bra.s       .init_deep_row_loop
.init_map_done:

    ; 10-second period: 500 logic ticks on PAL and NTSC alike, because
    ; VBlankTick withholds every sixth NTSC VBlank
    move.w      #WATER_RISE_FRAMES,d0
    move.w      d0,WaterRisePeriod(a5)

    ; --- Render Initial Waterline & All Submerged Rows Below ---
    bsr         TilemapRenderWaterInBuffer
    bra.s       .done

.no_water:
    move.w      #-1,WaterCurrentRow(a5)
    move.w      #-1,WaterPixelY(a5)
    clr.w       WaterSubTick(a5)
    clr.w       WaterRisePeriod(a5)

.done:
    ; Initialize sprite priority: sprites in front of playfield (dry)
    move.w      #$0024,cpBPLCON2+2
    move.w      #$0024,BPLCON2(a6)

    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapRenderWaterInBuffer  -  Draw wave crest and fill all rows below
;
; Draws the 4-line wave profile starting at WaterPixelY, then fills all
; scanlines below down to the bottom of the level with solid blue water
; (Line 4 stipple) for any scanlines currently inside the active ring buffer.
;
; Preserves: all registers
;==============================================================================

TilemapRenderWaterInBuffer:
    PUSHM       d0-d1/d6
    move.w      WaterPixelY(a5),d0
    bmi.s       .trwb_done
    moveq       #0,d6                   ; Wave Line 0 (crest tips)
    bsr         TilemapApplyWaveScanline
    addq.w      #1,d0
    moveq       #1,d6                   ; Wave Line 1 (foam & highlight)
    bsr         TilemapApplyWaveScanline
    addq.w      #1,d0
    moveq       #2,d6                   ; Wave Line 2 (full contour)
    bsr         TilemapApplyWaveScanline
    addq.w      #1,d0
    moveq       #3,d6                   ; Wave Line 3 (base highlight)
    bsr         TilemapApplyWaveScanline
    addq.w      #1,d0                   ; WaterPixelY + 4

    ; Fill all scanlines below the wave down to the bottom of the map with
    ; the solid blue dither, on the Blitter
    move.w      CurrentMapHeight(a5),d1
    lsl.w       #4,d1
    subq.w      #1,d1                   ; d1 = (CurrentMapHeight * 16) - 1
    bsr         TilemapFillWaterRange

.trwb_done:
    POPM        d0-d1/d6
    rts


;==============================================================================
; TilemapBlitTileRow  -  Cookie-cut blit a full 20-tile row of a single tile
;
; Arguments:
;   d0.w = tile index (e.g. WATER_TILE_SURFACE or WATER_TILE_DEEP)
;   d1.w = map row index (0..41)
;   a0   = destination screen buffer base (NonDisplayScreen or DisplayScreen)
;
; Blits 20 columns across the row using the 50% dither mask in cookie-cut
; mode ($0FCA).
;
; Destroys: d0-d5, a1-a4 (preserves a5, a6)
;==============================================================================



WaterWaveTable_Even:
    ; Line 0 (EVEN scanline, dither mask $AAAA)
    dc.w    $f7f7, $0808, $0808, $0000, $0808
    ; Line 1 (EVEN scanline, dither mask $AAAA)
    dc.w    $d5d5, $2a2a, $2a2a, $0000, $2222
    ; Line 2 (EVEN scanline, dither mask $AAAA)
    dc.w    $5555, $aaaa, $a2a2, $0202, $8080
    ; Line 3 (EVEN scanline, dither mask $AAAA)
    dc.w    $5555, $aaaa, $8080, $0000, $0000
    ; Line 4 / Solid Blue Fill (EVEN scanline, dither mask $AAAA)
    dc.w    $5555, $aaaa, $0000, $0000, $0000

WaterWaveTable_Odd:
    ; Line 0 (ODD scanline, dither mask $5555)
    dc.w    $ebeb, $1414, $1414, $0000, $1414
    ; Line 1 (ODD scanline, dither mask $5555)
    dc.w    $ebeb, $1414, $1414, $0404, $0000
    ; Line 2 (ODD scanline, dither mask $5555)
    dc.w    $aaaa, $5555, $4141, $0000, $4141
    ; Line 3 (ODD scanline, dither mask $5555)
    dc.w    $aaaa, $5555, $4141, $0000, $0000
    ; Line 4 / Solid Blue Fill (ODD scanline, dither mask $5555)
    dc.w    $aaaa, $5555, $0000, $0000, $0000


;==============================================================================
; TilemapApplyWaveScanline  -  Apply wave graphic line or solid blue fill
;
; Arguments:
;   d0.w = scanline Y within the 688px level (0..LEVEL_SCREEN_HEIGHT-1)
;   d6.w = line type (0..4):
;          0 = Wave Line 0 (crest tips)
;          1 = Wave Line 1 (foam & highlight)
;          2 = Wave Line 2 (full wave contour)
;          3 = Wave Line 3 (wave base highlight)
;          4 = Solid Blue Tile fill (Line 4 / Tile 115)
;
; Applies cookie-cut semi-transparency directly to both NonDisplayScreen
; and DisplayScreen:
;   (PlaneX & not_m) | px_or
; Preserves all pristine background bits on non-dithered checkerboard pixels.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapApplyWaveScanline:
    PUSHM       d0-d7/a0-a2
    bsr         WaterWaveSetup          ; d1-d5 = masks, d0.l = byte offset
    tst.l       d0
    bmi.s       .exit                   ; scanline outside the ring buffer

    ; Apply to NonDisplayScreen (primary)
    lea         NonDisplayScreen,a0
    adda.l      d0,a0
    bsr         WaterApplyScanline

    ; Apply to DisplayScreen (primary)
    lea         DisplayScreen,a0
    adda.l      d0,a0
    bsr         WaterApplyScanline

    ; Mirror to Row + 16 (scanline + 256) in NonDisplayScreen
    lea         NonDisplayScreen,a0
    adda.l      d0,a0
    adda.l      #16*TILEMAP_ROW_STRIDE,a0
    bsr         WaterApplyScanline

    ; Mirror to Row + 16 (scanline + 256) in DisplayScreen
    lea         DisplayScreen,a0
    adda.l      d0,a0
    adda.l      #16*TILEMAP_ROW_STRIDE,a0
    bsr         WaterApplyScanline

.exit:
    POPM        d0-d7/a0-a2
    rts


;==============================================================================
; TilemapApplyWaveScanlineTo  -  Apply a wave line to one copy of the buffer
;
; Same as TilemapApplyWaveScanline, but writes only the buffer half in a0
; instead of all four copies. Row streaming uses it: it draws one copy of
; the row and blits that copy to the others.
;
; In:  d0.w = scanline Y within the level, d6.w = line type (0..4)
;      a0   = buffer half: NonDisplayScreen, or NonDisplayScreen + 16 rows
; Destroys: none (preserves all registers)
;==============================================================================

TilemapApplyWaveScanlineTo:
    PUSHM       d0-d7/a0-a2
    bsr         WaterWaveSetup
    tst.l       d0
    bmi.s       .exit
    adda.l      d0,a0
    bsr         WaterApplyScanline
.exit:
    POPM        d0-d7/a0-a2
    rts


;==============================================================================
; WaterWaveSetup  -  Look up a wave line and its buffer offset
;
; In:  d0.w = scanline Y within the level, d6.w = line type (0..4)
; Out: d1-d5 = AND mask and the four plane OR values
;      d0.l  = byte offset of the scanline in a buffer half,
;              or -1 if the scanline is outside the ring buffer
; Destroys: d6/a2
;==============================================================================

WaterWaveSetup:
    ; Bounds check against active ring buffer window
    ; Ring buffer holds 16 rows: RingBufferTopRow to RingBufferBotRow
    move.w      RingBufferTopRow(a5),d1
    lsl.w       #4,d1                   ; d1 = BufferTopWorldY
    cmp.w       d1,d0
    blt.s       .outside                ; below active buffer top, do not draw
    add.w       #RING_BUFFER_HEIGHT,d1  ; d1 = BufferTopWorldY + 256
    cmp.w       d1,d0
    bge.s       .outside                ; beyond active buffer bottom, do not draw

    ; Select table based on scanline parity (even / odd)
    btst        #0,d0
    bne.s       .odd_line
    lea         WaterWaveTable_Even(pc),a2
    bra.s       .table_ready
.odd_line:
    lea         WaterWaveTable_Odd(pc),a2
.table_ready:

    ; Table entry offset = line type * 10 bytes (5 words: not_m, p0, p1, p2, p3)
    mulu.w      #10,d6
    adda.w      d6,a2

    move.w      (a2)+,d1                ; d1 = not_m (AND mask)
    move.w      (a2)+,d2                ; d2 = p0_or (Plane 0 OR value)
    move.w      (a2)+,d3                ; d3 = p1_or (Plane 1 OR value)
    move.w      (a2)+,d4                ; d4 = p2_or (Plane 2 OR value)
    move.w      (a2)+,d5                ; d5 = p3_or (Plane 3 OR value)

    ; Calculate primary scanline byte offset = (Y & RING_BUFFER_MASK) * 160
    andi.w      #RING_BUFFER_MASK,d0
    mulu.w      #TILEMAP_LINE_STRIDE,d0 ; d0.l = Y * 160
    rts

.outside:
    moveq       #-1,d0
    rts


;==============================================================================
; WaterApplyScanline  -  Cookie-cut one wave line into one scanline
;
; In:  a0 = start of the scanline, d1-d5 = values from WaterWaveSetup
; Destroys: d7/a0
;==============================================================================

WaterApplyScanline:
    ; a0 -> start of scanline (Plane 0, 20 words = 40 bytes)
    ; Fast path for solid blue fill (Planes 1..3 OR values all zero)
    move.w      d3,d7
    or.w        d4,d7
    or.w        d5,d7
    bne.s       .generic_wave_line

    ; Fast path for Solid Blue Fill (Line 4 / Tile 115):
    ; Plane 0: OR with d2 (20 words)
    moveq       #20-1,d7
.blue_p0:
    or.w        d2,(a0)+
    dbra        d7,.blue_p0

    ; Planes 1, 2, 3: AND with d1 (60 words)
    moveq       #60-1,d7
.blue_p123:
    and.w       d1,(a0)+
    dbra        d7,.blue_p123
    rts

.generic_wave_line:
    ; Generic cookie-cut for wave lines 0..3 (the crest stays on the CPU:
    ; it is four lines, and each plane needs its own OR value)
    ; Plane 0 (20 words)
    moveq       #20-1,d7
.p0_loop:
    and.w       d1,(a0)
    or.w        d2,(a0)+
    dbra        d7,.p0_loop

    ; Plane 1 (20 words)
    moveq       #20-1,d7
.p1_loop:
    and.w       d1,(a0)
    or.w        d3,(a0)+
    dbra        d7,.p1_loop

    ; Plane 2 (20 words)
    moveq       #20-1,d7
.p2_loop:
    and.w       d1,(a0)
    or.w        d4,(a0)+
    dbra        d7,.p2_loop

    ; Plane 3 (20 words)
    moveq       #20-1,d7
.p3_loop:
    and.w       d1,(a0)
    or.w        d5,(a0)+
    dbra        d7,.p3_loop
    rts


;==============================================================================
; TilemapFillWaterRange  -  Water dither on a range of scanlines, all copies
;
; The Blitter version of calling TilemapApplyWaveScanline with line type 4
; on every scanline from d0 to d1. It clips the range to the 256 lines the
; ring buffer holds, then dithers both halves of NonDisplayScreen and of
; DisplayScreen with WaterBlitFill.
;
; In:  d0.w = first world scanline, d1.w = last world scanline (inclusive)
; Destroys: none (preserves all registers)
;==============================================================================

TilemapFillWaterRange:
    PUSHM       d0-d2/a0
    move.w      RingBufferTopRow(a5),d2
    lsl.w       #4,d2                   ; d2 = first world line held in the ring
    cmp.w       d2,d0
    bge.s       .top_ok
    move.w      d2,d0
.top_ok:
    add.w       #RING_BUFFER_HEIGHT-1,d2 ; d2 = last world line held in the ring
    cmp.w       d2,d1
    ble.s       .bot_ok
    move.w      d2,d1
.bot_ok:
    cmp.w       d0,d1
    blt.s       .done                   ; nothing of the range is in the ring
    lea         NonDisplayScreen,a0
    bsr         WaterBlitFill
    lea         DisplayScreen,a0
    bsr         WaterBlitFill
    lea         NonDisplayScreen+16*TILEMAP_ROW_STRIDE,a0 ; mirror halves
    bsr         WaterBlitFill
    lea         DisplayScreen+16*TILEMAP_ROW_STRIDE,a0
    bsr         WaterBlitFill
.done:
    POPM        d0-d2/a0
    rts


;==============================================================================
; WaterBlitFill  -  Blitter: the 50% water dither on a run of scanlines
;
; Below the wave crest, the water sets every other pixel to colour 1:
; plane 0 is ORed with a pattern and planes 1-3 are ANDed with its
; complement. The pattern is $AAAA on even world lines and $5555 on odd
; ones (Line 4 of WaterWaveTable_Even and _Odd).
;
; The Blitter does this with channels A and D only: A reads the screen and
; D writes it back. C's DMA is off, so C supplies the constant pattern held
; in BLTCDAT. An A+D blit takes 2 colour clocks per word, against 3 for C+D
; (the Blitter adds an idle cycle when C and D are used together). Each
; parity is a pass of its own, even lines then odd, stepping two scanlines
; (320 bytes) per blit row. Each pass is two blits: plane 0 with D = A | C
; (minterm $FA), then the three planes 1-3, which sit side by side in an
; interleaved scanline, with D = A & /C (minterm $50), 60 words wide.
;
; In:  a0   = buffer half: NonDisplayScreen or DisplayScreen, plus
;             16 * TILEMAP_ROW_STRIDE for the mirror half
;      d0.w = first world scanline, d1.w = last world scanline (inclusive),
;             both inside the ring buffer window (as WaterWaveSetup tests)
; Destroys: none. Waits for the Blitter before it returns, because the
;           CPU crest and actor dither may write the same lines next.
;==============================================================================

WaterBlitFill:
    PUSHM       d0-d5/a1-a2
    sub.w       d0,d1
    bmi.s       .done                   ; empty range
    addq.w      #1,d1                   ; d1 = number of lines
    move.w      d0,d2
    andi.w      #RING_BUFFER_MASK,d2    ; d2 = first ring line (0..255)
    move.w      #RING_BUFFER_HEIGHT,d3
    sub.w       d2,d3                   ; d3 = lines before the ring wraps
    cmp.w       d3,d1
    ble.s       .last_run
    ; The range crosses ring line 255: fill to the wrap, then from line 0
    move.w      d1,d4
    sub.w       d3,d4                   ; d4 = lines after the wrap
    move.w      d3,d1
    movem.w     d3-d4,-(sp)
    bsr.s       .run
    movem.w     (sp)+,d3-d4
    add.w       d3,d0                   ; world line just after the wrap
    moveq       #0,d2
    move.w      d4,d1
.last_run:
    bsr.s       .run
.done:
    POPM        d0-d5/a1-a2
    rts

; One run with no wrap: d0 = world line (for parity), d1 = lines, d2 = ring line
.run:
    move.w      d2,d5
    mulu.w      #TILEMAP_LINE_STRIDE,d5
    lea         (a0,d5.l),a1            ; a1 = plane 0 of the run's first line
    move.w      #$aaaa,d5               ; pattern for an even world line
    btst        #0,d0
    beq.s       .first_even
    move.w      #$5555,d5               ; pattern for an odd world line
.first_even:
    move.w      d1,d3
    addq.w      #1,d3
    lsr.w       #1,d3                   ; d3 = lines of the first parity
    bsr.s       .pass
    lea         TILEMAP_LINE_STRIDE(a1),a1 ; the other parity starts a line down
    not.w       d5                      ; and uses the other pattern
    move.w      d1,d3
    lsr.w       #1,d3                   ; d3 = lines of the second parity
    ; falls through: the second pass returns from .run

; One parity: a1 = plane 0 of its first line, d3 = lines, d5 = pattern
.pass:
    tst.w       d3
    beq         .pass_done
    WAITBLIT
    move.l      #$ffffffff,BLTAFWM(a6)
    clr.w       BLTCON1(a6)
    move.w      d5,BLTCDAT(a6)          ; C = the pattern, with no C DMA
    move.w      #$09fa,BLTCON0(a6)      ; USEA|USED, D = A | C: plane 0
    move.w      #2*TILEMAP_LINE_STRIDE-SCREEN_WIDTH_BYTE,BLTAMOD(a6) ; 320 - 40
    move.w      #2*TILEMAP_LINE_STRIDE-SCREEN_WIDTH_BYTE,BLTDMOD(a6)
    move.l      a1,BLTAPT(a6)           ; A = the screen
    move.l      a1,BLTDPT(a6)
    move.w      d3,d4
    lsl.w       #6,d4
    or.w        #SCREEN_WIDTH_BYTE/2,d4
    move.w      d4,BLTSIZE(a6)          ; d3 lines x 20 words
    WAITBLIT
    move.w      #$0950,BLTCON0(a6)      ; USEA|USED, D = A & /C: planes 1-3
    move.w      #2*TILEMAP_LINE_STRIDE-3*SCREEN_WIDTH_BYTE,BLTAMOD(a6) ; 320 - 120
    move.w      #2*TILEMAP_LINE_STRIDE-3*SCREEN_WIDTH_BYTE,BLTDMOD(a6)
    lea         SCREEN_WIDTH_BYTE(a1),a2 ; plane 1 of the same line
    move.l      a2,BLTAPT(a6)
    move.l      a2,BLTDPT(a6)
    move.w      d3,d4
    lsl.w       #6,d4
    or.w        #3*SCREEN_WIDTH_BYTE/2,d4
    move.w      d4,BLTSIZE(a6)          ; d3 lines x 60 words
    WAITBLIT
.pass_done:
    rts


;==============================================================================
; TilemapSubmergeScanline  -  Convenience wrapper for Solid Blue Tile submersion
;
; Arguments:
;   d0.w = scanline Y within the 688px level (0..LEVEL_SCREEN_HEIGHT-1)
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapSubmergeScanline:
    PUSHM       d6
    moveq       #4,d6                   ; line type 4 = solid blue fill
    bsr         TilemapApplyWaveScanline
    POPM        d6
    rts


;==============================================================================
; TilemapSubmergeActor  -  Apply wave surface graphic or solid blue stipple
;
; Called by TilemapDrawPlayer and TilemapDrawEnemy to submerge an actor.
; For scanlines WaterPixelY + 0..3, applies the wave crest profile from
; WaterWaveTable_Even / WaterWaveTable_Odd so the wave flows seamlessly across
; the actor with no straight-line cutoff.
; For scanlines >= WaterPixelY + 4, applies 50% solid blue dither.
;
; In:
;   a0   = Pointer to destination Plane 0 in DisplayScreen (Y * 160 + col * 2)
;   d0.w = Actor X coordinate (to test alignment: andi.w #15)
;   d1.w = Actor top scanline Y
;   d2.w = WaterPixelY
;   d7.w = Actor height in scanlines (e.g. PLAYER_HEIGHT or ENEMY_FRAME_HEIGHT)
;
; Preserves:
;   All caller registers (pushes d0-d7/a0-a3)
;==============================================================================

TilemapSubmergeActor:
    PUSHM       d0-d7/a0-a3

    ; Check if water is active
    tst.w       d2                      ; WaterPixelY
    bmi         .exit                   ; if < 0, no water!

    ; Check if actor is completely above water
    move.w      d1,d3                   ; d3 = actor top Y
    add.w       d7,d3
    subq.w      #1,d3                   ; d3 = actor bottom Y
    cmp.w       d2,d3                   ; compare bottom Y with WaterPixelY
    blt         .exit                   ; if bottom < WaterPixelY, completely dry!

    ; Determine span width: 1, 2, or 3 words based on actor type/height and X
    moveq       #1,d6                   ; default: 1 word
    cmp.w       #PLAYER_HEIGHT,d7
    beq.s       .is_player
    ; 16px Actor:
    andi.w      #15,d0
    beq.s       .width_determined
    moveq       #2,d6                   ; shifted 16px actor = 2 words
    bra.s       .width_determined

.is_player:
    moveq       #2,d6                   ; player default = 2 words (aligned or right edge)
    cmp.w       #288,d0
    bge.s       .width_determined
    andi.w      #15,d0
    beq.s       .width_determined
    moveq       #3,d6                   ; shifted player = 3 words

.width_determined:
    WAITBLIT                            ; ensure blitter has finished drawing actor BOB

    ; Fast-skip dry scanlines at the top of the actor (if d1 < d2)
    move.w      d2,d3
    sub.w       d1,d3                   ; d3 = dry scanline count (WaterPixelY - topY)
    ble.s       .no_dry_skip
    sub.w       d3,d7                   ; subtract dry lines from height
    ble         .exit
    move.w      d2,d1                   ; d1 = WaterPixelY (now first submerged scanline)
    mulu.w      #TILEMAP_LINE_STRIDE,d3
    adda.l      d3,a0                   ; a0 -> first submerged scanline
.no_dry_skip:

    ; Dispatch based on width: d6 = 1, 2, or 3
    subq.w      #1,d6
    beq.s       .span_1word
    subq.w      #1,d6
    beq.s       .span_2words
    bsr         TilemapSubmergeSpan3W   ; 3-word shifted span (24px player BOB)
    bra.s       .exit
.span_2words:
    bsr         TilemapSubmergeSpan2W   ; 2-word span
    bra.s       .exit
.span_1word:
    bsr         TilemapSubmergeSpan1W   ; 1-word aligned span

.exit:
    POPM        d0-d7/a0-a3
    rts


;==============================================================================
; TilemapUpdateWater  -  Advance rising water layer upwards
;
; Called every frame from GameRun in gamestatus.asm.
; Overall movement: 16 pixels every 10 seconds.
; Advances WATER_STEP_PIXELS (1 or 2 pixels) per step.
;
; Each step:
;   1. Decrements WaterPixelY by WATER_STEP_PIXELS.
;   2. Advances the first 5 pixel rows together as the wave graphic:
;      - Scanline Y + 0: Wave Line 0 (crest tips)
;      - Scanline Y + 1: Wave Line 1 (foam & highlight)
;      - Scanline Y + 2: Wave Line 2 (full wave contour)
;      - Scanline Y + 3: Wave Line 3 (wave base highlight)
;      - Scanline Y + 4: Wave Line 4 (solid blue body)
;   3. Overwrites the prior location lines vacated by the wave with
;      solid blue water (Tile 115 fill) at scanline Y + 5.
;   4. When crossing into a new tile row (WaterPixelY >> 4 != WaterCurrentRow):
;      Updates WaterCurrentRow and updates LiveWaterMap tile data.
;
; Destroys: none (preserves all registers)
;==============================================================================


;==============================================================================
; TilemapSubmergeSpan3W  -  Water tint for a 3-word shifted span (48px window for a 24px player BOB)
;
; Width-specific body of TilemapSubmergeActor; never called directly.
; Inherits that routine's register state (a0 = first submerged scanline in
; plane 0, d1 = first submerged Y, d2 = WaterPixelY, d7 = remaining lines) and
; runs inside its PUSHM/POPM frame, so it may clobber d0-d7/a0-a3.
;
; Destroys: d0-d1/d3-d7/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

TilemapSubmergeSpan3W:
    move.w      d1,d6
    sub.w       d2,d6                   ; d6 = offset from WaterPixelY
    cmp.w       #4,d6
    bge         .solid_blue_3w          ; d6 >= 4 -> already below wave crest, solid blue!

.crest_loop_3w:
    btst        #0,d1
    bne.s       .crest_odd_3w
    lea         WaterWaveTable_Even(pc),a1
    bra.s       .crest_table_ok_3w
.crest_odd_3w:
    lea         WaterWaveTable_Odd(pc),a1
.crest_table_ok_3w:
    move.w      d6,d3
    mulu.w      #10,d3
    adda.w      d3,a1

    move.w      (a1)+,d3                ; not_m
    move.w      (a1)+,d4                ; p0_or
    move.w      (a1)+,d5                ; p1_or
    move.w      (a1)+,d0                ; p2_or

    ; Plane 0:
    and.w       d3,(a0)
    or.w        d4,(a0)
    and.w       d3,2(a0)
    or.w        d4,2(a0)
    and.w       d3,4(a0)
    or.w        d4,4(a0)

    ; Plane 1:
    and.w       d3,40(a0)
    or.w        d5,40(a0)
    and.w       d3,42(a0)
    or.w        d5,42(a0)
    and.w       d3,44(a0)
    or.w        d5,44(a0)

    ; Plane 2:
    and.w       d3,80(a0)
    or.w        d0,80(a0)
    and.w       d3,82(a0)
    or.w        d0,82(a0)
    and.w       d3,84(a0)
    or.w        d0,84(a0)

    ; Plane 3:
    move.w      (a1),d0                 ; p3_or
    and.w       d3,120(a0)
    or.w        d0,120(a0)
    and.w       d3,122(a0)
    or.w        d0,122(a0)
    and.w       d3,124(a0)
    or.w        d0,124(a0)

    addq.w      #1,d1                   ; next scanline Y
    addq.w      #1,d6                   ; next crest line index
    lea         TILEMAP_LINE_STRIDE(a0),a0 ; next scanline in DisplayScreen (+160)
    subq.w      #1,d7
    beq        .done_3w                   ; all requested lines done!
    cmp.w       #4,d6
    blt         .crest_loop_3w

.solid_blue_3w:
    tst.w       d7
    ble        .done_3w

    move.l      #$aaaaaaaa,d4
    move.l      #$55555555,d5

    btst        #0,d1
    beq.s       .pair_loop_3w

    ; Odd starting scanline:
    move.l      (a0),d3
    or.l        d5,d3
    move.l      d3,(a0)
    move.w      4(a0),d3
    or.w        d5,d3
    move.w      d3,4(a0)

    move.l      40(a0),d3
    and.l       d4,d3
    move.l      d3,40(a0)
    move.w      44(a0),d3
    and.w       d4,d3
    move.w      d3,44(a0)

    move.l      80(a0),d3
    and.l       d4,d3
    move.l      d3,80(a0)
    move.w      84(a0),d3
    and.w       d4,d3
    move.w      d3,84(a0)

    move.l      120(a0),d3
    and.l       d4,d3
    move.l      d3,120(a0)
    move.w      124(a0),d3
    and.w       d4,d3
    move.w      d3,124(a0)

    lea         TILEMAP_LINE_STRIDE(a0),a0
    subq.w      #1,d7
    beq        .done_3w

.pair_loop_3w:
    cmp.w       #2,d7
    blt         .single_even_3w

    ; Line 0 (EVEN) at a0:
    move.l      (a0),d3
    or.l        d4,d3
    move.l      d3,(a0)
    move.w      4(a0),d3
    or.w        d4,d3
    move.w      d3,4(a0)

    move.l      40(a0),d3
    and.l       d5,d3
    move.l      d3,40(a0)
    move.w      44(a0),d3
    and.w       d5,d3
    move.w      d3,44(a0)

    move.l      80(a0),d3
    and.l       d5,d3
    move.l      d3,80(a0)
    move.w      84(a0),d3
    and.w       d5,d3
    move.w      d3,84(a0)

    move.l      120(a0),d3
    and.l       d5,d3
    move.l      d3,120(a0)
    move.w      124(a0),d3
    and.w       d5,d3
    move.w      d3,124(a0)

    ; Line 1 (ODD) at +160(a0):
    move.l      160(a0),d3
    or.l        d5,d3
    move.l      d3,160(a0)
    move.w      164(a0),d3
    or.w        d5,d3
    move.w      d3,164(a0)

    move.l      200(a0),d3
    and.l       d4,d3
    move.l      d3,200(a0)
    move.w      204(a0),d3
    and.w       d4,d3
    move.w      d3,204(a0)

    move.l      240(a0),d3
    and.l       d4,d3
    move.l      d3,240(a0)
    move.w      244(a0),d3
    and.w       d4,d3
    move.w      d3,244(a0)

    move.l      280(a0),d3
    and.l       d4,d3
    move.l      d3,280(a0)
    move.w      284(a0),d3
    and.w       d4,d3
    move.w      d3,284(a0)

    lea         320(a0),a0              ; advance 2 scanlines
    subq.w      #2,d7
    bgt         .pair_loop_3w
    rts

.single_even_3w:
    tst.w       d7
    ble        .done_3w
    move.l      (a0),d3
    or.l        d4,d3
    move.l      d3,(a0)
    move.w      4(a0),d3
    or.w        d4,d3
    move.w      d3,4(a0)

    move.l      40(a0),d3
    and.l       d5,d3
    move.l      d3,40(a0)
    move.w      44(a0),d3
    and.w       d5,d3
    move.w      d3,44(a0)

    move.l      80(a0),d3
    and.l       d5,d3
    move.l      d3,80(a0)
    move.w      84(a0),d3
    and.w       d5,d3
    move.w      d3,84(a0)

    move.l      120(a0),d3
    and.l       d5,d3
    move.l      d3,120(a0)
    move.w      124(a0),d3
    and.w       d5,d3
    move.w      d3,124(a0)
    rts
.done_3w:
    rts


;==============================================================================
; TilemapSubmergeSpan2W  -  Water tint for a 2-word shifted span (32px window)
;
; Width-specific body of TilemapSubmergeActor; never called directly.
; Inherits that routine's register state (a0 = first submerged scanline in
; plane 0, d1 = first submerged Y, d2 = WaterPixelY, d7 = remaining lines) and
; runs inside its PUSHM/POPM frame, so it may clobber d0-d7/a0-a3.
;
; Destroys: d0-d1/d3-d7/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

TilemapSubmergeSpan2W:
    move.w      d1,d6
    sub.w       d2,d6                   ; d6 = offset from WaterPixelY
    cmp.w       #4,d6
    bge         .solid_blue_2w

.crest_loop_2w:
    btst        #0,d1
    bne.s       .crest_odd_2w
    lea         WaterWaveTable_Even(pc),a1
    bra.s       .crest_table_ok_2w
.crest_odd_2w:
    lea         WaterWaveTable_Odd(pc),a1
.crest_table_ok_2w:
    move.w      d6,d3
    mulu.w      #10,d3
    adda.w      d3,a1

    move.w      (a1)+,d3                ; not_m
    move.w      (a1)+,d4                ; p0_or
    move.w      (a1)+,d5                ; p1_or
    move.w      (a1)+,d0                ; p2_or

    ; Plane 0:
    and.w       d3,(a0)
    or.w        d4,(a0)
    and.w       d3,2(a0)
    or.w        d4,2(a0)

    ; Plane 1:
    and.w       d3,40(a0)
    or.w        d5,40(a0)
    and.w       d3,42(a0)
    or.w        d5,42(a0)

    ; Plane 2:
    and.w       d3,80(a0)
    or.w        d0,80(a0)
    and.w       d3,82(a0)
    or.w        d0,82(a0)

    ; Plane 3:
    move.w      (a1),d0                 ; p3_or
    and.w       d3,120(a0)
    or.w        d0,120(a0)
    and.w       d3,122(a0)
    or.w        d0,122(a0)

    addq.w      #1,d1
    addq.w      #1,d6
    lea         TILEMAP_LINE_STRIDE(a0),a0
    subq.w      #1,d7
    beq        .done_2w
    cmp.w       #4,d6
    blt         .crest_loop_2w

.solid_blue_2w:
    tst.w       d7
    ble        .done_2w

    move.l      #$aaaaaaaa,d4
    move.l      #$55555555,d5

    btst        #0,d1
    beq.s       .pair_loop_2w

    ; Odd starting scanline:
    move.l      (a0),d3
    or.l        d5,d3
    move.l      d3,(a0)

    move.l      40(a0),d3
    and.l       d4,d3
    move.l      d3,40(a0)

    move.l      80(a0),d3
    and.l       d4,d3
    move.l      d3,80(a0)

    move.l      120(a0),d3
    and.l       d4,d3
    move.l      d3,120(a0)

    lea         TILEMAP_LINE_STRIDE(a0),a0
    subq.w      #1,d7
    beq        .done_2w

.pair_loop_2w:
    cmp.w       #2,d7
    blt         .single_even_2w

    ; Line 0 (EVEN) at a0:
    move.l      (a0),d3
    or.l        d4,d3
    move.l      d3,(a0)

    move.l      40(a0),d3
    and.l       d5,d3
    move.l      d3,40(a0)

    move.l      80(a0),d3
    and.l       d5,d3
    move.l      d3,80(a0)

    move.l      120(a0),d3
    and.l       d5,d3
    move.l      d3,120(a0)

    ; Line 1 (ODD) at +160(a0):
    move.l      160(a0),d3
    or.l        d5,d3
    move.l      d3,160(a0)

    move.l      200(a0),d3
    and.l       d4,d3
    move.l      d3,200(a0)

    move.l      240(a0),d3
    and.l       d4,d3
    move.l      d3,240(a0)

    move.l      280(a0),d3
    and.l       d4,d3
    move.l      d3,280(a0)

    lea         320(a0),a0
    subq.w      #2,d7
    bgt         .pair_loop_2w
    rts

.single_even_2w:
    tst.w       d7
    ble        .done_2w
    move.l      (a0),d3
    or.l        d4,d3
    move.l      d3,(a0)

    move.l      40(a0),d3
    and.l       d5,d3
    move.l      d3,40(a0)

    move.l      80(a0),d3
    and.l       d5,d3
    move.l      d3,80(a0)

    move.l      120(a0),d3
    and.l       d5,d3
    move.l      d3,120(a0)
    rts
.done_2w:
    rts


;==============================================================================
; TilemapSubmergeSpan1W  -  Water tint for a 1-word aligned span (16px window)
;
; Width-specific body of TilemapSubmergeActor; never called directly.
; Inherits that routine's register state (a0 = first submerged scanline in
; plane 0, d1 = first submerged Y, d2 = WaterPixelY, d7 = remaining lines) and
; runs inside its PUSHM/POPM frame, so it may clobber d0-d7/a0-a3.
;
; Destroys: d0-d1/d3-d7/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

TilemapSubmergeSpan1W:
    move.w      d1,d6
    sub.w       d2,d6                   ; d6 = offset from WaterPixelY
    cmp.w       #4,d6
    bge         .solid_blue_1w

.crest_loop_1w:
    btst        #0,d1
    bne.s       .crest_odd_1w
    lea         WaterWaveTable_Even(pc),a1
    bra.s       .crest_table_ok_1w
.crest_odd_1w:
    lea         WaterWaveTable_Odd(pc),a1
.crest_table_ok_1w:
    move.w      d6,d3
    mulu.w      #10,d3
    adda.w      d3,a1

    move.w      (a1)+,d3                ; not_m
    move.w      (a1)+,d4                ; p0_or
    move.w      (a1)+,d5                ; p1_or
    move.w      (a1)+,d0                ; p2_or

    and.w       d3,(a0)
    or.w        d4,(a0)
    and.w       d3,40(a0)
    or.w        d5,40(a0)
    and.w       d3,80(a0)
    or.w        d0,80(a0)
    move.w      (a1),d0
    and.w       d3,120(a0)
    or.w        d0,120(a0)

    addq.w      #1,d1
    addq.w      #1,d6
    lea         TILEMAP_LINE_STRIDE(a0),a0
    subq.w      #1,d7
    beq        .done_1w
    cmp.w       #4,d6
    blt         .crest_loop_1w

.solid_blue_1w:
    tst.w       d7
    ble        .done_1w

    move.w      #$aaaa,d4
    move.w      #$5555,d5

    btst        #0,d1
    beq.s       .pair_loop_1w

    ; Odd starting scanline:
    move.w      (a0),d3
    or.w        d5,d3
    move.w      d3,(a0)

    move.w      40(a0),d3
    and.w       d4,d3
    move.w      d3,40(a0)

    move.w      80(a0),d3
    and.w       d4,d3
    move.w      d3,80(a0)

    move.w      120(a0),d3
    and.w       d4,d3
    move.w      d3,120(a0)

    lea         TILEMAP_LINE_STRIDE(a0),a0
    subq.w      #1,d7
    beq        .done_1w

.pair_loop_1w:
    cmp.w       #2,d7
    blt         .single_even_1w

    ; Line 0 (EVEN) at a0:
    move.w      (a0),d3
    or.w        d4,d3
    move.w      d3,(a0)

    move.w      40(a0),d3
    and.w       d5,d3
    move.w      d3,40(a0)

    move.w      80(a0),d3
    and.w       d5,d3
    move.w      d3,80(a0)

    move.w      120(a0),d3
    and.w       d5,d3
    move.w      d3,120(a0)

    ; Line 1 (ODD) at +160(a0):
    move.w      160(a0),d3
    or.w        d5,d3
    move.w      d3,160(a0)

    move.w      200(a0),d3
    and.w       d4,d3
    move.w      d3,200(a0)

    move.w      240(a0),d3
    and.w       d4,d3
    move.w      d3,240(a0)

    move.w      280(a0),d3
    and.w       d4,d3
    move.w      d3,280(a0)

    lea         320(a0),a0
    subq.w      #2,d7
    bgt         .pair_loop_1w
    rts

.single_even_1w:
    tst.w       d7
    ble        .done_1w
    move.w      (a0),d3
    or.w        d4,d3
    move.w      d3,(a0)

    move.w      40(a0),d3
    and.w       d5,d3
    move.w      d3,40(a0)

    move.w      80(a0),d3
    and.w       d5,d3
    move.w      d3,80(a0)

    move.w      120(a0),d3
    and.w       d5,d3
    move.w      d3,120(a0)
.done_1w:
    rts

;==============================================================================
; TilemapUpdateWater  -  Advance the rising water by one frame
;
; Adds 16 to WaterSubTick each frame; once it reaches WaterRisePeriod *
; WATER_STEP_PIXELS the surface rises WATER_STEP_PIXELS scanlines: the five-row
; wave graphic is redrawn at the new WaterPixelY (TilemapApplyWaveScanline,
; line types 0-4), the scanlines it vacated are backfilled with solid water,
; and when the surface crosses a 16-pixel tile boundary WaterCurrentRow and
; the LiveWaterMap rows (surface tile, then deep tile) are updated so
; collision and rewind stay in step with the picture.
;
; No-op while WaterPixelY <= 0 (no water, or water at the ceiling).
;
; In:  a5 = Variables base, a6 = CUSTOM chip base
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapUpdateWater:
    ; If no water or water has reached the ceiling (scanline 0), do nothing
    move.w      WaterPixelY(a5),d0
    ble         .exit

    ; -------------------------------------------------------------------------
    ; 1. Advance Fractional Frame Accumulator
    ; -------------------------------------------------------------------------
    ; At 50Hz PAL, water rises at exactly 16 pixels per 10 seconds (500 frames).
    ; We add 16 to WaterSubTick every frame.
    ; When accumulator reaches WaterRisePeriod * WATER_STEP_PIXELS, one pixel step triggers.
    move.w      WaterSubTick(a5),d0
    add.w       #16,d0
    move.w      WaterRisePeriod(a5),d1
    IFNE        WATER_STEP_PIXELS-1
    mulu.w      #WATER_STEP_PIXELS,d1
    ENDC
    cmp.w       d1,d0
    blt         .store_subtick          ; period not yet reached: store remainder and exit

    ; Step interval elapsed! Subtract threshold and store fractional remainder
    sub.w       d1,d0
    move.w      d0,WaterSubTick(a5)

    PUSHM       d0-d7/a0-a2

    ; -------------------------------------------------------------------------
    ; 2. Advance Water Scanline Upwards
    ; -------------------------------------------------------------------------
    subq.w      #WATER_STEP_PIXELS,WaterPixelY(a5) ; decrement Y (advances up towards top of screen)
    move.w      WaterPixelY(a5),d0      ; d0 = new top scanline of water surface

    ; -------------------------------------------------------------------------
    ; 3. Render 5-Scanline Moving Wave Graphic onto Playfield
    ; -------------------------------------------------------------------------
    ; The animated waterline consists of 5 distinct wave profile rows:
    ;   Scanline Y + 0: Wave Line 0 (crest tips - semi-transparent highlights)
    move.w      d0,-(sp)
    moveq       #0,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ;   Scanline Y + 1: Wave Line 1 (foam & light cyan highlights)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #1,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ;   Scanline Y + 2: Wave Line 2 (full wave contour)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #2,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ;   Scanline Y + 3: Wave Line 3 (wave base transition)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #3,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ;   Scanline Y + 4: Wave Line 4 (solid blue water body)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #4,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; -------------------------------------------------------------------------
    ; 4. Backfill Lines Vacated by the Rising Wave
    ; -------------------------------------------------------------------------
    ; As the wave moves up by WATER_STEP_PIXELS, scanline Y+5 (and any subsequent
    ; step lines) are overwritten with solid blue water (type 4 fill) so no
    ; visual gaps or previous wave crests remain.
    moveq       #WATER_STEP_PIXELS-1,d5
.fill_prior_lines:
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #4,d6                   ; line type 4 = solid blue water fill
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0
    dbra        d5,.fill_prior_lines

    ; -------------------------------------------------------------------------
    ; 5. Tile Row Boundary Crossing Check
    ; -------------------------------------------------------------------------
    ; When WaterPixelY crosses a 16-pixel tile boundary (WaterPixelY >> 4 != WaterCurrentRow),
    ; update the live water tile layer in LiveWaterMap so tile-based collision,
    ; background rendering, and rewinding stay synchronized.
    move.w      WaterPixelY(a5),d1
    lsr.w       #4,d1                   ; d1 = current tile row (WaterPixelY >> 4)
    cmp.w       WaterCurrentRow(a5),d1
    beq.s       .pop_exit               ; still within same tile row: done!

    ; We crossed into a new tile row!
    move.w      d1,WaterCurrentRow(a5)

    ; Update LiveWaterMap: row d1 becomes surface water (tile 104),
    ; row d1+1 becomes deep water (tile 115).
    lea         LiveWaterMap(a5),a0
    addq.l      #8,a0                   ; skip 8-byte map header
    move.w      d1,d2
    mulu.w      #TILEMAP_MAP_WIDTH*2,d2
    lea         (a0,d2.w),a1            ; a1 -> row d1 in LiveWaterMap

    move.w      #TILEMAP_MAP_WIDTH-1,d3
    move.w      #WATER_TILE_SURFACE,d4  ; tile 104 (surface wave)
.fill_surface:
    move.w      d4,(a1)+
    dbra        d3,.fill_surface

    move.w      #TILEMAP_MAP_WIDTH-1,d3
    move.w      #WATER_TILE_DEEP,d4     ; tile 115 (deep solid water)
.fill_deep:
    move.w      d4,(a1)+
    dbra        d3,.fill_deep

.pop_exit:
    POPM        d0-d7/a0-a2
    rts

.store_subtick:
    move.w      d0,WaterSubTick(a5)
.exit:
    rts


;==============================================================================
; TilemapRedrawRows  -  Redraw all map layers for a specific row range
;
; In:
;   a0   = destination screen buffer base in Chip RAM (e.g. NonDisplayScreen)
;   d0.w = StartRow (0..41)
;   d1.w = EndRow (0..41)
;
; Preserves: all caller registers (pushes d0-d7/a0-a4)
;==============================================================================

TilemapRedrawRows:
    PUSHM       d2-d7/a0-a4

    move.w      d0,d2                   ; d2 = StartRow (preserved across calls)
    move.w      d1,d3                   ; d3 = EndRow   (preserved across calls)
    move.l      a0,a4                   ; a4 = destination buffer base (preserved)

    move.l      CurrentLevelDef(a5),d0
    beq         .legacy_layers
    movea.l     d0,a2

    move.w      LevelDef_LayerCount(a2),d7
    beq         .fallback_layers
    move.l      LevelDef_LayerList(a2),d6
    beq         .fallback_layers

    subq.w      #1,d7

.layer_loop:
    movea.l     d6,a1
    move.l      (a1)+,d0
    move.l      a1,d6
    tst.l       d0
    beq.s       .skip_layer

    movea.l     d0,a2                   ; a2 = map pointer
    move.l      a4,a0                   ; a0 = destination buffer
    move.w      d2,d0                   ; StartRow
    move.w      d3,d1                   ; EndRow
    bsr         TilemapDrawLayerRows

.skip_layer:
    dbra        d7,.layer_loop

    POPM        d2-d7/a0-a4
    rts

.fallback_layers:
    move.l      LevelDef_BackgroundMap(a2),d0
    beq.s       .no_bg
    movea.l     d0,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
.no_bg:
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_PlatformMap(a2),d0
    beq.s       .no_plat
    movea.l     d0,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
.no_plat:

    ; --- Pass 2.25: Render Ladder Layer ---
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_LadderMap(a2),d0
    beq.s       .no_ladder
    movea.l     d0,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
.no_ladder:

    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_ForegroundMap(a2),d0
    beq.s       .no_fg
    movea.l     d0,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
.no_fg:
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_WaterMap(a2),d0
    beq.s       .no_water
    movea.l     d0,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
.no_water:
    POPM        d2-d7/a0-a4
    rts

.legacy_layers:
    lea         LevelDefaultPlatformMap,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
    POPM        d2-d7/a0-a4
    rts


;==============================================================================
; TilemapRewindWater  -  Restore dried out screen rows and reapply wave graphic
;
; In:
;   d0.w = OldY (WaterPixelY before undo)
;   d1.w = RestoredY (Snap_WaterPixelY from snapshot)
;
; If RestoredY > OldY, water moved downwards (scanlines OldY..RestoredY dried out).
; Restores pristine background in NonDisplayScreen for affected tile rows,
; reapplies wave crest at RestoredY and solid blue underneath, and cleans LiveWaterMap.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapRewindWater:
    PUSHM       d0-d7/a0-a4

    ; If no water in level (RestoredY < 0 or OldY < 0), exit
    tst.w       d1
    bmi         .rewind_done
    tst.w       d0
    bmi         .rewind_done

    ; If water did not rise (RestoredY <= OldY), no rows dried out
    cmp.w       d0,d1
    ble         .rewind_done

    move.w      d1,d5                   ; d5 = RestoredY (preserve across calls)

    ; StartRow = OldY >> 4
    move.w      d0,d2
    lsr.w       #4,d2
    bpl.s       .start_ok
    moveq       #0,d2
.start_ok:

    ; EndRow = (RestoredY + 4) >> 4
    move.w      d5,d3
    addq.w      #4,d3
    lsr.w       #4,d3
    move.w      CurrentMapHeight(a5),d1
    subq.w      #1,d1
    cmp.w       d1,d3
    ble.s       .end_ok
    move.w      d1,d3
.end_ok:

    cmp.w       d2,d3
    blt         .rewind_done

    ; Step 1 & 2: Re-stream rows d2..d3 that overlap the active ring buffer
.rewind_row_loop:
    cmp.w       RingBufferTopRow(a5),d2
    blt.s       .rewind_row_next
    cmp.w       RingBufferBotRow(a5),d2
    bgt.s       .rewind_row_next
    move.w      d2,d0
    bsr         TilemapStreamTileRow
.rewind_row_next:
    addq.w      #1,d2
    cmp.w       d3,d2
    ble.s       .rewind_row_loop

    ; Step 3: Reapply wave at RestoredY (d5) down to bottom of EndRow (d3)
    move.w      d5,d0                   ; scanline RestoredY
    moveq       #0,d6                   ; Wave Line 0 (crest tips)
    bsr         TilemapApplyWaveScanline

    addq.w      #1,d0
    moveq       #1,d6                   ; Wave Line 1 (foam)
    bsr         TilemapApplyWaveScanline

    addq.w      #1,d0
    moveq       #2,d6                   ; Wave Line 2 (contour)
    bsr         TilemapApplyWaveScanline

    addq.w      #1,d0
    moveq       #3,d6                   ; Wave Line 3 (base highlight)
    bsr         TilemapApplyWaveScanline

    addq.w      #1,d0                   ; RestoredY + 4

    ; Calculate EndScanline = (EndRow + 1) * 16 - 1
    move.w      d3,d4
    addq.w      #1,d4
    lsl.w       #4,d4
    subq.w      #1,d4
    move.w      CurrentMapHeight(a5),d1
    lsl.w       #4,d1
    subq.w      #1,d1
    cmp.w       d1,d4
    ble.s       .scan_end_ok
    move.w      d1,d4
.scan_end_ok:

    move.w      d4,d1                   ; solid blue, RestoredY + 4 to EndScanline
    bsr         TilemapFillWaterRange   ; on the Blitter

    ; Step 4: Synchronize LiveWaterMap
    move.w      d5,d6                   ; RestoredY
    lsr.w       #4,d6                   ; d6 = RestoredRow
    cmp.w       d2,d6                   ; RestoredRow vs StartRow
    ble.s       .set_restored_surface

    ; Clear rows d2 up to d6 - 1
    lea         LiveWaterMap(a5),a1
    addq.l      #8,a1
    move.w      d2,d4
    mulu.w      #TILEMAP_MAP_WIDTH*2,d4
    adda.w      d4,a1

    move.w      d6,d7
    sub.w       d2,d7
    mulu.w      #TILEMAP_MAP_WIDTH,d7   ; total words
    subq.w      #1,d7
.clr_map_words:
    clr.w       (a1)+
    dbra        d7,.clr_map_words

.set_restored_surface:
    cmp.w       CurrentMapHeight(a5),d6
    bge.s       .rewind_done
    lea         LiveWaterMap(a5),a1
    addq.l      #8,a1
    move.w      d6,d4
    mulu.w      #TILEMAP_MAP_WIDTH*2,d4
    adda.w      d4,a1

    move.w      #TILEMAP_MAP_WIDTH-1,d7
    move.w      #WATER_TILE_SURFACE,d4
.set_surface_words:
    move.w      d4,(a1)+
    dbra        d7,.set_surface_words

.rewind_done:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapDrawEnemies  -  Blit all enemies over the screen buffer
;
; Arguments:
;   a0 = destination screen buffer base in Chip RAM
;
; Reads enemy definitions from LevelDef_EnemyList (or LevelDefaultEnemyList)
; and blits each enemy into its tile position on top of the background & platforms.
;
; Destroys: none (preserves all registers)
;==============================================================================



TilemapSubmergeTile:
    PUSHM       d0-d7/a0-a3

    move.w      WaterPixelY(a5),d2
    bmi.s       .tst_dry
    move.w      d1,d4
    lsl.w       #4,d4                   ; d4 = pixel Y (top of tile)
    move.w      d4,d3
    add.w       #15,d3                  ; d3 = bottom pixel Y of tile
    cmp.w       d2,d3
    blt.s       .tst_dry                ; bottom < WaterPixelY -> completely dry

    move.w      d0,d5
    lsl.w       #4,d5                   ; d5 = pixel X (col * 16)
    move.w      d5,d0                   ; d0 = pixel X (aligned)
    move.w      d4,d1                   ; d1 = pixel Y

    move.w      d1,d6
    andi.w      #RING_BUFFER_MASK,d6
    mulu.w      #TILEMAP_LINE_STRIDE,d6
    move.w      d0,d5
    lsr.w       #4,d5
    add.w       d5,d5                   ; byte column
    add.l       d5,d6
    lea         DisplayScreen,a0
    adda.l      d6,a0                   ; a0 = dest pointer in DisplayScreen

    move.w      #16,d7                  ; 16 scanlines
    bsr         TilemapSubmergeActor

    ; Mirror submerge to Row + 16 in DisplayScreen
    adda.l      #16*TILEMAP_ROW_STRIDE,a0
    move.w      #16,d7
    bsr         TilemapSubmergeActor

.tst_dry:
    POPM        d0-d7/a0-a3
    rts


;==============================================================================
; TilemapSubmergePlayer  -  Apply water tinting to player BOB if submerged
;
; Called in Green phase (after SetRasterLogicColor) so that WAITBLIT and CPU
; submersion loops do not delay the VBlank priority blit window.
;
; In:  a4 = pointer to active Player struct
;      a5 = Variables base
;      a6 = CUSTOM chip base
; Preserves: all registers (pushes d0-d7/a0-a3)
;==============================================================================
TilemapSubmergePlayer:
    move.w      WaterPixelY(a5),d2      ; d2 = WaterPixelY
    bmi.s       .tsp_exit               ; if water inactive (< 0), exit
    tst.w       Player_PrevDrawn(a4)    ; was player drawn this frame?
    beq.s       .tsp_exit               ; if culled/not drawn, exit

    move.w      Player_PrevY(a4),d3
    add.w       #PLAYER_HEIGHT-1,d3     ; d3 = player bottom Y
    cmp.w       d2,d3
    blt.s       .tsp_exit               ; player bottom < WaterPixelY -> completely dry!

    PUSHM       d0-d7/a0-a3

    move.w      Player_PrevX(a4),d0
    move.w      Player_PrevY(a4),d1
    ; Tint the copy that is on screen: the buffer line TilemapDrawPlayer drew
    ; at, (camera & 255) + (Y - camera). Near the bottom of a tall level that
    ; line is in the mirror half (256..511), so (Y & 255) would tint the
    ; primary copy, which is not being displayed.
    move.w      PrevPlayerCameraY(a5),d3
    andi.w      #RING_BUFFER_MASK,d3    ; d3 = buffer line of the camera
    add.w       d1,d3
    sub.w       PrevPlayerCameraY(a5),d3 ; d3 = buffer line of the BOB top
    bmi.s       .tsp_skip
    cmp.w       #RING_BUFFER_ALLOC_LINES-PLAYER_HEIGHT,d3
    bgt.s       .tsp_skip
    mulu.w      #TILEMAP_LINE_STRIDE,d3
    moveq       #0,d4
    move.w      d0,d4
    lsr.w       #4,d4
    add.w       d4,d4
    add.l       d4,d3
    lea         DisplayScreen,a0
    adda.l      d3,a0
    move.w      #PLAYER_HEIGHT,d7       ; 24 scanlines
    bsr         TilemapSubmergeActor
.tsp_skip:
    POPM        d0-d7/a0-a3
.tsp_exit:
    rts


