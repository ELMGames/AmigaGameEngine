;==============================================================================
; vhs_rewind.asm  -  VHS Cassette Rewind Screen Effect
; AmigaGameEngine Core Reusable Screen Effect
; Amiga 68000 Assembly / OCS-ECS Chipset
;
; Triggered on F9 (UndoMove) or Rewind event:
;   1. Desaturates & darkens the palette with dynamic LFSR colour-channel noise.
;   2. Live Copper Scanline Tearing: patches BPLCON1 horizontal delays across
;      random scanline bands (using cpVHSDistort slots or cpGameSky raster entries),
;      creating real hardware horizontal tearing with analog chromatic aberration
;      fringing (odd vs even plane phase).
;   3. OSD Text: renders solid white 'REW  <<' in the top-left corner of the viewport
;      using FontData with dark drop-shadow outline.
;   4. Dynamic Variable Tracking Noise Snow Bar & Streaks:
;      Renders an organically fluctuating tracking snow band (variable Y, variable
;      height 8..15 scanlines, sudden tracking slips & speed changes) plus multiple
;      random static noise streaks scattered dynamically across the entire screen!
;   5. Non-Destructive Fast RAM Backup Buffers:
;      Before noise or text is stamped, the exact scanlines from DisplayScreen are
;      backed up into dedicated Fast RAM buffers and restored before each new frame.
;      This guarantees that ALL stationary crates, obstacles, and actors on
;      DisplayScreen are 100% preserved and never corrupted or erased!
;
; PUBLIC API:
;   VhsInit          - call once in GameInit
;   VhsStartEffect   - trigger the effect (ActionIdle, after bsr UndoMove)
;   VhsStopEffect    - cancel early or finish effect (restores screen & copper)
;   VhsDoFrame       - call every VBlank; d0=1 active, d0=0 just finished
;   VhsRestoreScreen - restore previous frame's noise before scene rendering
;   VhsClearDistort  - reset all BPLCON1 copper distortion slots to neutral
;   VhsStateActive   - byte flag: non-zero while effect is running
;   VhsNoiseDrawn    - byte flag: non-zero if noise is currently on DisplayScreen
;
; All routines preserve a5 (Variables) and a6 (CUSTOM).
; VhsDoFrame returns result in d0; all other registers preserved by all routines.
;==============================================================================

    IFD TILEMAP_LINE_STRIDE
VHS_STRIDE          = TILEMAP_LINE_STRIDE
    ELSE
    IFD VHS_STRIDE
VHS_STRIDE          = VHS_STRIDE
    ELSE
VHS_STRIDE          = 160
    ENDC
    ENDC

    IFD TILEMAP_TILE_PLANES
VHS_PLANES          = TILEMAP_TILE_PLANES
    ELSE
    IFD VHS_PLANES
VHS_PLANES          = VHS_PLANES
    ELSE
VHS_PLANES          = 4
    ENDC
    ENDC

    IFND SCREEN_HEIGHT
SCREEN_HEIGHT       = 200
    ENDC

VHS_BYTES_PER_ROW   = (VHS_STRIDE/VHS_PLANES)
VHS_WORDS_PER_STRIDE = (VHS_STRIDE/2)
    IFND WINDOW_Y_START
WINDOW_Y_START      = 44
    ENDC
    IFND NTSC_WINDOW_Y_START
NTSC_WINDOW_Y_START = $1c                ; must match engine_const.i
    ENDC
    IFND RING_BUFFER_ALLOC_LINES
RING_BUFFER_ALLOC_LINES = 512
    ENDC

VHS_EFFECT_DURATION =  40          ; frames at full effect (~0.8 s at 50 Hz PAL)
VHS_LFSR_POLY       =  $80000057   ; Galois LFSR polynomial (maximal-length 32-bit)
VHS_NOISE_BITS      =  $0111       ; XOR mask: bits 0,4,8 = B/G/R channel LSBs
VHS_MAX_BAR_H       =  18          ; maximum possible tracking snow bar height

;==============================================================================
; Fast RAM BSS  (CPU-only; zeroed by OS at load)
;==============================================================================

    section  mem_fast,bss
    even

VhsStateActive:    ds.b  1   ; non-zero while effect runs (exported symbol)
VhsTearActive:     ds.b  1   ; non-zero if copper scanline tear is currently patched
VhsTextDrawn:      ds.b  1   ; non-zero if REW << was drawn on screen
VhsNoiseDrawn:     ds.b  1   ; non-zero if noise is currently stamped on DisplayScreen
VhsJustFinished:   ds.b  1   ; non-zero on frame immediately post-unwind
    even

VhsFrameCount:     ds.w  1   ; frames elapsed since VhsStartEffect
VhsSavedPal:       ds.w  32  ; original colour values captured from cpPal
VhsDesPal:         ds.w  32  ; desaturated + darkened palette

VhsNoiseBarY:      ds.w  1   ; current Y offset within viewport (10..185)
VhsPrevNoiseY:     ds.w  1   ; previous absolute scanline Y in DisplayScreen (-1 if none)
VhsPrevNoiseH:     ds.w  1   ; previous height of noise bar in scanlines
VhsPrevStreak1Y:   ds.w  1   ; previous scanline Y of streak 1 (-1 if none)
VhsPrevStreak2Y:   ds.w  1   ; previous scanline Y of streak 2 (-1 if none)
VhsPrevStreak3Y:   ds.w  1   ; previous scanline Y of streak 3 (-1 if none)
VhsPrevTextY:      ds.w  1   ; scanline Y where REW << was drawn (-1 if none)
    even

    IFND VHS_USE_DISTORT_SLOTS
VhsTear1Start:    ds.w  1   ; scanline index in cpGameSky for Tear 1 start
VhsTear1End:      ds.w  1   ; scanline index in cpGameSky for Tear 1 end
VhsTear1ColorS:   ds.w  1   ; original color value at Tear 1 start
VhsTear1ColorE:   ds.w  1   ; original color value at Tear 1 end

VhsTear2Start:    ds.w  1
VhsTear2End:      ds.w  1
VhsTear2ColorS:   ds.w  1
VhsTear2ColorE:   ds.w  1

VhsTear3Start:    ds.w  1
VhsTear3End:      ds.w  1
VhsTear3ColorS:   ds.w  1
VhsTear3ColorE:   ds.w  1
    even
    ENDC

; Non-destructive scanline backup buffers in Fast RAM
VhsNoiseBarBackup: ds.b  VHS_MAX_BAR_H*VHS_STRIDE
VhsStreak1Backup:  ds.b  VHS_STRIDE
VhsStreak2Backup:  ds.b  VHS_STRIDE
VhsStreak3Backup:  ds.b  VHS_STRIDE
VhsTextBackup:     ds.b  8*8*VHS_PLANES
    even

;==============================================================================
; Fast RAM DATA
;==============================================================================

    section  data_fast,data
    even

VhsLfsr:           dc.l  $DEADBEEF
VhsStrRew:        dc.b  "REW  <<",0
    even

; Horizontal BPLCON1 delay values for tearing (bits 7-4 = even planes, bits 3-0 = odd planes)
; Asymmetric values (e.g. $CB, $DC) introduce chromatic aberration / RGB edge fringing
VhsTearShifts:     dc.w  $00CC, $00DD, $00BB, $00CB, $00EE, $0099, $00AA, $00DC
    even

;==============================================================================
; Code
;==============================================================================

    section  main,code
    even

;------------------------------------------------------------------------------
; VhsInit
; Call once in GameInit after the copper list is live.
;------------------------------------------------------------------------------
; Destroys: d0/a0 (preserves everything else, including a5/a6)

VhsInit:
    clr.b    VhsStateActive
    clr.b    VhsTearActive
    clr.b    VhsTextDrawn
    clr.b    VhsNoiseDrawn
    clr.b    VhsJustFinished
    move.w   #-1,VhsPrevNoiseY
    move.w   #-1,VhsPrevStreak1Y
    move.w   #-1,VhsPrevStreak2Y
    move.w   #-1,VhsPrevStreak3Y
    move.w   #-1,VhsPrevTextY
    bsr      VhsClearDistort
    rts

;------------------------------------------------------------------------------
; VhsStartEffect
; Snapshot cpPal colour values, compute the desaturated VHS palette, apply
; it immediately to cpPal, and start the frame counter.
;------------------------------------------------------------------------------
; Destroys: d4-d6/a2-a4 (preserves everything else, including a5/a6)

VhsStartEffect:
    movem.l  d0-d3/d7/a0-a1,-(sp)

    tst.b    VhsStateActive
    beq.s    .first_start

    ; Already running: clean copper tears and reset timer
    bsr      VhsClearDistort
    bsr      VhsRestoreScreen
    bsr      VhsRestoreText
    clr.b    VhsNoiseDrawn
    clr.b    VhsTextDrawn
    move.w   #-1,VhsPrevNoiseY
    move.w   #-1,VhsPrevStreak1Y
    move.w   #-1,VhsPrevStreak2Y
    move.w   #-1,VhsPrevStreak3Y
    move.w   #-1,VhsPrevTextY
    clr.w    VhsFrameCount
    bra      .draw_initial_frame

.first_start:
    ;--- Snapshot: cpPal colour values -> VhsSavedPal -----------------------
    lea      cpPal+2,a0            ; a0 -> first colour value word
    lea      VhsSavedPal,a1
    moveq    #32-1,d7
.snap:
    move.w   (a0),(a1)+
    addq.l   #4,a0                 ; next copper pair
    dbra     d7,.snap

    ;--- Desaturate: VhsSavedPal -> VhsDesPal ------------------------------
    lea      VhsSavedPal,a0
    lea      VhsDesPal,a1
    moveq    #32-1,d7
.desat:
    move.w   (a0)+,d0              ; d0 = source colour $0RGB

    ; extract channels into d0=B, d1=R, d2=G
    move.w   d0,d1
    lsr.w    #8,d1
    and.w    #$F,d1                ; d1 = R (0..15)
    move.w   d0,d2
    lsr.w    #4,d2
    and.w    #$F,d2                ; d2 = G (0..15)
    and.w    #$F,d0                ; d0 = B (0..15)

    ; grey = (R+G+B)*85 >> 8
    move.w   d1,d3
    add.w    d2,d3
    add.w    d0,d3                 ; d3 = R+G+B (0..45)
    mulu.w   #85,d3
    lsr.l    #8,d3
    and.w    #$F,d3                ; d3 = grey (0..14)

    ; desaturate 50%: new = (ch + grey) >> 1
    add.w    d3,d1
    lsr.w    #1,d1                 ; new R
    add.w    d3,d2
    lsr.w    #1,d2                 ; new G
    add.w    d3,d0
    lsr.w    #1,d0                 ; new B

    ; darken to 75%: new = new - new>>2
    move.w   d1,d3
    lsr.w    #2,d3
    sub.w    d3,d1
    move.w   d2,d3
    lsr.w    #2,d3
    sub.w    d3,d2
    move.w   d0,d3
    lsr.w    #2,d3
    sub.w    d3,d0

    ; pack $0RGB: (R<<8) | (G<<4) | B
    lsl.w    #4,d2
    or.w     d2,d0                 ; d0 = (G<<4)|B
    lsl.w    #8,d1
    or.w     d1,d0                 ; d0 = (R<<8)|(G<<4)|B
    move.w   d0,(a1)+
    dbra     d7,.desat

    ;--- Apply desaturated palette to cpPal immediately ----------------------
    lea      VhsDesPal,a0
    lea      cpPal+2,a1
    moveq    #32-1,d7
.apply0:
    move.w   (a0)+,(a1)
    addq.l   #4,a1
    dbra     d7,.apply0

    ; Ensure Color 3 in cpPal is brilliant solid white () from frame 0
    move.w   #$0FFF,cpPal+(3*4)+2

.activate:
    move.b   #1,VhsStateActive
    clr.w    VhsFrameCount
    clr.b    VhsTearActive
    clr.b    VhsTextDrawn
    clr.b    VhsNoiseDrawn
    clr.b    VhsJustFinished
    move.w   #40,VhsNoiseBarY
    move.w   #12,VhsPrevNoiseH
    move.w   #-1,VhsPrevNoiseY
    move.w   #-1,VhsPrevStreak1Y
    move.w   #-1,VhsPrevStreak2Y
    move.w   #-1,VhsPrevStreak3Y
    move.w   #-1,VhsPrevTextY

.draw_initial_frame:
    ; Immediately draw Frame 0 of snow bar, streaks, 'REW  <<', and copper tears
    ; so Frame 0 displays the complete VHS rewind effect from the very first scanline!
    bsr      VhsDrawNoiseBar
    bsr      VhsDrawStreaks
    bsr      VhsDrawRewindText
    move.b   #1,VhsNoiseDrawn
    bsr      VhsApplyCopperTears

    movem.l  (sp)+,d0-d3/d7/a0-a1
    rts

;------------------------------------------------------------------------------
; VhsStopEffect
; Restore the original palette, clean copper list tears, restore screen from
; Fast RAM backup buffers, and re-blit all static actors onto DisplayScreen.
;------------------------------------------------------------------------------
; Destroys: none (preserves all registers)

VhsStopEffect:
    movem.l  d0-d7/a0-a4,-(sp)

    ; 1. Restore live copper tears
    bsr      VhsClearDistort

    ; 2. Ensure hardware BPLCON1 register is reset to 0
    move.w   #$0000,CUSTOM+BPLCON1

    ; 3. Restore all modified DisplayScreen areas from Fast RAM backups
    bsr      VhsRestoreScreen
    bsr      VhsRestoreText

    ; 4. Restore original palette from VhsSavedPal to cpPal
    lea      VhsSavedPal,a0
    lea      cpPal+2,a1
    moveq    #32-1,d7
.restore:
    move.w   (a0)+,(a1)
    addq.l   #4,a1
    dbra     d7,.restore

    clr.b    VhsStateActive
    clr.b    VhsTextDrawn
    clr.b    VhsNoiseDrawn
    move.b   #1,VhsJustFinished
    move.w   #-1,VhsPrevNoiseY
    move.w   #-1,VhsPrevStreak1Y
    move.w   #-1,VhsPrevStreak2Y
    move.w   #-1,VhsPrevStreak3Y
    move.w   #-1,VhsPrevTextY

    ; 5. Redraw push blocks so DisplayScreen is 100% verified pristine
    IFD VHS_CUSTOM_STOP_HOOK
    jsr      VHS_CUSTOM_STOP_HOOK
    ELSE
    bsr      TilemapDrawPushBlocks
    ENDC

    ; 6. Reset VBlank overrun count
    clr.w    VBlankOverrunCount(a5)

    movem.l  (sp)+,d0-d7/a0-a4
    rts

;------------------------------------------------------------------------------
; VhsDoFrame
; Call once per frame while VhsStateActive is non-zero.
;------------------------------------------------------------------------------
; Destroys: d0 (preserves everything else, including a5/a6)

VhsDoFrame:
    movem.l  d1-d7/a0-a4,-(sp)

    ; Increment and check frame counter
    addq.w   #1,VhsFrameCount
    cmp.w    #VHS_EFFECT_DURATION,VhsFrameCount
    blt.s    .run

    ; Effect expired: stop effect cleanly
    bsr      VhsStopEffect
    clr.w    VBlankOverrunCount(a5)
    movem.l  (sp)+,d1-d7/a0-a4
    moveq    #0,d0
    rts

.run:
    ; 1. Write VhsDesPal + LFSR channel-noise to all 32 cpPal entries
    move.l   VhsLfsr,d2
    lea      VhsDesPal,a0
    lea      cpPal+2,a1
    moveq    #32-1,d7

.noise:
    VHS_LFSR_STEP
    move.w   (a0)+,d1              ; load desaturated colour
    move.w   d2,d0
    and.w    #VHS_NOISE_BITS,d0    ; isolate bits 0, 4, 8
    eor.w    d0,d1                 ; flip B/G/R LSBs at random
    move.w   d1,(a1)               ; write noisy colour to copper list
    addq.l   #4,a1
    dbra     d7,.noise

    move.l   d2,VhsLfsr

    ; Ensure Color 3 in cpPal is brilliant solid white ($0FFF) for VCR OSD overlay
    move.w   #$0FFF,cpPal+(3*4)+2

    ; 2. Clear previous frame's copper scanline tears
    bsr      VhsClearDistort

    ; 3. Restore previous frame's screen noise (if not already done at frame start)
    bsr      VhsRestoreScreen

    ; 4. Draw dynamically variable tracking noise snow bar (with Fast RAM backup)
    bsr      VhsDrawNoiseBar

    ; 5. Draw dynamic random static noise streaks across the screen (with Fast RAM backup)
    bsr      VhsDrawStreaks

    ; 6. Render 'REW <<' text in the top-left of the viewport (on top of noise)
    bsr      VhsDrawRewindText

    ; Mark that screen noise is currently stamped on DisplayScreen
    move.b   #1,VhsNoiseDrawn

    ; 7. Apply live Copper scanline tearing
    bsr      VhsApplyCopperTears

    movem.l  (sp)+,d1-d7/a0-a4
    moveq    #1,d0
    rts

;==============================================================================
; VhsRestoreScreen  -  Restore scanlines modified by VHS noise bar and streaks
;
; Restores all scanlines modified by the snow bar and streaks from the Fast RAM
; backup buffers back to DisplayScreen in strict LIFO reverse draw order.
; Note: 'REW  <<' remains stamped continuously throughout the entire effect and
; is only restored when the effect ends via VhsRestoreText.
;
; In:       none
; Out:      none
; Destroys: none (preserves all registers)
;==============================================================================

VhsRestoreScreen:
    tst.b    VhsNoiseDrawn
    beq      .done
    movem.l  d0-d7/a0-a2,-(sp)

    ;--- 1. Restore Streak 3 (1 scanline = WORDS_PER_STRIDE words) ---
    move.w   VhsPrevStreak3Y,d0
    bmi.s    .no_s3
    cmp.w    #RING_BUFFER_ALLOC_LINES,d0
    bge.s    .no_s3

    ext.l    d0
    mulu.w   #VHS_STRIDE,d0
    lea      DisplayScreen,a1
    add.l    d0,a1
    lea      VhsStreak3Backup,a0
    move.w   #VHS_WORDS_PER_STRIDE-1,d6
.res_s3_loop:
    move.w   (a0)+,(a1)+
    dbra     d6,.res_s3_loop

    move.w   #-1,VhsPrevStreak3Y
.no_s3:

    ;--- 2. Restore Streak 2 (1 scanline = WORDS_PER_STRIDE words) ---
    move.w   VhsPrevStreak2Y,d0
    bmi.s    .no_s2
    cmp.w    #RING_BUFFER_ALLOC_LINES,d0
    bge.s    .no_s2

    ext.l    d0
    mulu.w   #VHS_STRIDE,d0
    lea      DisplayScreen,a1
    add.l    d0,a1
    lea      VhsStreak2Backup,a0
    move.w   #VHS_WORDS_PER_STRIDE-1,d6
.res_s2_loop:
    move.w   (a0)+,(a1)+
    dbra     d6,.res_s2_loop

    move.w   #-1,VhsPrevStreak2Y
.no_s2:

    ;--- 3. Restore Streak 1 (1 scanline = WORDS_PER_STRIDE words) ---
    move.w   VhsPrevStreak1Y,d0
    bmi.s    .no_s1
    cmp.w    #RING_BUFFER_ALLOC_LINES,d0
    bge.s    .no_s1

    ext.l    d0
    mulu.w   #VHS_STRIDE,d0
    lea      DisplayScreen,a1
    add.l    d0,a1
    lea      VhsStreak1Backup,a0
    move.w   #VHS_WORDS_PER_STRIDE-1,d6
.res_s1_loop:
    move.w   (a0)+,(a1)+
    dbra     d6,.res_s1_loop

    move.w   #-1,VhsPrevStreak1Y
.no_s1:

    ;--- 4. Restore Noise Bar (VhsPrevNoiseH scanlines) ---
    move.w   VhsPrevNoiseY,d0
    bmi.s    .no_bar
    cmp.w    #RING_BUFFER_ALLOC_LINES-VHS_MAX_BAR_H,d0
    bge.s    .no_bar

    ext.l    d0
    mulu.w   #VHS_STRIDE,d0
    lea      DisplayScreen,a1
    add.l    d0,a1                       ; a1 -> dest in DisplayScreen
    lea      VhsNoiseBarBackup,a0       ; a0 -> source in Fast RAM

    ; Number of words to restore = VhsPrevNoiseH * WORDS_PER_STRIDE
    move.w   VhsPrevNoiseH,d6
    mulu.w   #VHS_WORDS_PER_STRIDE,d6
    subq.w   #1,d6

.res_bar_loop:
    move.w   (a0)+,(a1)+
    dbra     d6,.res_bar_loop

    move.w   #-1,VhsPrevNoiseY
.no_bar:

    clr.b    VhsNoiseDrawn
    movem.l  (sp)+,d0-d7/a0-a2
.done:
    rts

;------------------------------------------------------------------------------
; VhsRestoreText
; Restores the 'REW  <<' text box (8 scanlines, columns 2..9, VHS_PLANES planes)
; from VhsTextBackup back to DisplayScreen when the rewind effect completes.
;------------------------------------------------------------------------------
; Destroys: none (preserves all registers)

VhsRestoreText:
    tst.b    VhsTextDrawn
    beq.s    .no_text_done
    movem.l  d0/d5/d7/a0-a2,-(sp)

    move.w   VhsPrevTextY,d0
    bmi.s    .no_text
    cmp.w    #RING_BUFFER_ALLOC_LINES-8,d0
    bge.s    .no_text

    ext.l    d0
    mulu.w   #VHS_STRIDE,d0
    lea      DisplayScreen,a1
    add.l    d0,a1
    addq.l   #2,a1                       ; column 2
    lea      VhsTextBackup,a0
    moveq    #8-1,d7

.res_text_loop:
    movea.l  a1,a2
    moveq    #VHS_PLANES-1,d5
.res_plane_loop:
    move.l   (a0)+,(a2)
    move.l   (a0)+,4(a2)
    lea      VHS_BYTES_PER_ROW(a2),a2
    dbra     d5,.res_plane_loop

    lea      VHS_STRIDE(a1),a1
    dbra     d7,.res_text_loop

    move.w   #-1,VhsPrevTextY
.no_text:
    clr.b    VhsTextDrawn
    movem.l  (sp)+,d0/d5/d7/a0-a2
.no_text_done:
    rts

;==============================================================================
; VhsDrawRewindText  -  Render 'REW  <<' text overlay onto screen
;
; Backs up the 8x8 character bounding box to VhsTextBackup once per effect,
; then renders solid white 'REW  <<' (Color 3 = $0FFF) in the top-left corner
; of the viewport (at Y=18, column 2, cleanly below HUD sprites at Y=6..19).
;
; In:       none
; Out:      none
; Destroys: none (preserves all registers)
;==============================================================================

VhsDrawRewindText:
    movem.l  d0-d7/a0-a4,-(sp)

    ; 1. Calculate buffer-relative scanline: (TilemapCameraY(a5) & 255) + 18
    move.w   TilemapCameraY(a5),d0
    andi.w   #255,d0
    add.w    #18,d0                      ; 18 scanlines below visible top edge (18..25)
    ext.l    d0
    mulu.w   #VHS_STRIDE,d0

    ; Only back up the pristine background on the first frame of the effect!
    tst.b    VhsTextDrawn
    bne.s    .skip_text_backup

    move.w   TilemapCameraY(a5),d1
    andi.w   #255,d1
    add.w    #18,d1
    move.w   d1,VhsPrevTextY
    move.b   #1,VhsTextDrawn

    ; Backup text area from DisplayScreen to VhsTextBackup
    lea      DisplayScreen,a0
    add.l    d0,a0
    addq.l   #2,a0                       ; column 2 (X=16px)
    lea      VhsTextBackup,a1
    moveq    #8-1,d7

.bak_text_loop:
    movea.l  a0,a2
    moveq    #VHS_PLANES-1,d5
.bak_plane_loop:
    move.l   (a2),(a1)+
    move.l   4(a2),(a1)+
    lea      VHS_BYTES_PER_ROW(a2),a2
    dbra     d5,.bak_plane_loop

    lea      VHS_STRIDE(a0),a0
    dbra     d7,.bak_text_loop

.skip_text_backup:
    ; 2. Render high-contrast OSD text onto DisplayScreen
    lea      DisplayScreen,a1
    add.l    d0,a1
    addq.l   #2,a1                       ; byte column 2 (X=16px)

    lea      FontData,a2
    lea      VhsStrRew,a0

.char_loop:
    moveq    #0,d2
    move.b   (a0)+,d2
    beq.s    .text_done

    sub.b    #32,d2
    lsl.w    #3,d2                       ; d2 = (char - 32) * 8
    lea      (a2,d2.w),a4                ; a4 -> 8 bytes of glyph

    movea.l  a1,a3                       ; a3 = current column Plane 0
    moveq    #8-1,d7

.row_loop:
    move.b   (a4)+,d3                    ; d3 = glyph byte
    ; Bold smear: d4 = d3 | (d3 >> 1)
    move.b   d3,d4
    lsr.b    #1,d4
    or.b     d3,d4                       ; d4 = bold glyph bits

    ; Authentic VCR OSD: Solid black backdrop box + crisp pure white text ($0FFF)
    ; Plane 2 & 3 = 0 (black background)
    clr.b    VHS_BYTES_PER_ROW*2(a3)         ; Plane 2 = 0
    clr.b    VHS_BYTES_PER_ROW*3(a3)         ; Plane 3 = 0
    ; Plane 0 & 1 = glyph bits (Color 3 = $0FFF white on glyph, Color 0 = black on non-glyph)
    move.b   d4,(a3)                     ; Plane 0 = glyph (white)
    move.b   d4,VHS_BYTES_PER_ROW(a3)        ; Plane 1 = glyph (white)

    lea      VHS_STRIDE(a3),a3        ; next scanline
    dbra     d7,.row_loop

    addq.l   #1,a1                       ; advance to next character column
    bra.s    .char_loop

.text_done:
    movem.l  (sp)+,d0-d7/a0-a4
    rts

;==============================================================================
; VhsDrawNoiseBar  -  Render variable-height tracking snow band across screen
;
; Computes dynamic, variable Y position and height for the tracking snow band.
; Jumps, slips, and rolls organically across the entire screen.
; Backs up VhsPrevNoiseH scanlines to VhsNoiseBarBackup, then renders dense
; analog static noise onto DisplayScreen.
;
; In:       none
; Out:      none
; Destroys: none (preserves all registers)
;==============================================================================

VhsDrawNoiseBar:
    movem.l  d0-d7/a0-a4,-(sp)
    move.l   VhsLfsr,d2

    ; 1. Calculate variable advance delta & random tracking slip
    VHS_LFSR_STEP

    ; 1-in-4 chance of a sudden tracking slip / jump
    move.w   d2,d1
    and.w    #$03,d1
    bne.s    .normal_roll

    ; Sudden slip: jump +20..+51 pixels ahead
    move.w   d2,d1
    lsr.w    #2,d1
    and.w    #$1f,d1
    add.w    #20,d1
    add.w    d1,VhsNoiseBarY
    bra.s    .check_wrap

.normal_roll:
    ; Variable roll speed: +6 to +13 pixels per frame
    move.w   d2,d1
    lsr.w    #2,d1
    and.w    #$07,d1
    addq.w   #6,d1
    add.w    d1,VhsNoiseBarY

.check_wrap:
    cmp.w    #185,VhsNoiseBarY
    blt.s    .y_in_range
    ; Wrap around with random entry offset (28..59)
    move.w   d2,d1
    lsr.w    #5,d1
    and.w    #$1f,d1
    add.w    #28,d1                      ; wrap entry offset (28..59, strictly below REW <<)
    move.w   d1,VhsNoiseBarY
.y_in_range:
    ; Ensure snow bar never creeps into REW << region (lines 0..27)
    cmp.w    #28,VhsNoiseBarY
    bge.s    .y_clamp_ok
    move.w   #28,VhsNoiseBarY
.y_clamp_ok:

    ; 2. Variable height: 8 to 15 scanlines
    move.w   d2,d7
    lsr.w    #7,d7
    and.w    #$07,d7
    addq.w   #8,d7                       ; d7 = height (8..15 scanlines)
    move.w   d7,VhsPrevNoiseH

    ; Absolute scanline in DisplayScreen: (RingBufferCamY + VhsNoiseBarY)
    move.w   TilemapCameraY(a5),d0
    andi.w   #255,d0
    add.w    VhsNoiseBarY,d0
    cmp.w    #RING_BUFFER_ALLOC_LINES-VHS_MAX_BAR_H,d0
    bge      .bar_done
    move.w   d0,VhsPrevNoiseY

    ;--- 3. Backup d7 scanlines from DisplayScreen to VhsNoiseBarBackup ---
    ext.l    d0
    mulu.w   #VHS_STRIDE,d0
    lea      DisplayScreen,a0
    add.l    d0,a0                       ; a0 -> source in DisplayScreen
    lea      VhsNoiseBarBackup,a1       ; a1 -> dest in Fast RAM

    move.w   d7,d6
    mulu.w   #VHS_WORDS_PER_STRIDE,d6
    subq.w   #1,d6

.bak_bar_loop:
    move.w   (a0)+,(a1)+
    dbra     d6,.bak_bar_loop

    ;--- 4. Render variable analog LFSR snow band onto DisplayScreen ---
    lea      DisplayScreen,a1
    add.l    d0,a1                       ; a1 -> Plane 0

    subq.w   #1,d7                       ; for dbra scanlines

.bar_row_loop:
    movea.l  a1,a0                       ; a0 = Plane 0 for this scanline
    moveq    #(VHS_BYTES_PER_ROW/4)-1,d6

.chunk_loop:
    VHS_LFSR_STEP
    move.l   d2,d3
    lsr.l    #1,d3
    or.l     d2,d3                       ; horizontal analog smear in d3 (keep d2 pure LFSR!)

    ; Write noise to Plane 0 & Plane 1 (creates brilliant white snow dots)
    move.l   d3,(a0)                     ; Plane 0
    move.l   d3,VHS_BYTES_PER_ROW(a0)        ; Plane 1

    ; Secondary noise on Plane 2 for color static variation
    move.l   d2,d4
    eor.l    #$55555555,d4
    move.l   d4,VHS_BYTES_PER_ROW*2(a0)      ; Plane 2
    IFGE VHS_PLANES-4
    clr.l    VHS_BYTES_PER_ROW*3(a0)         ; Plane 3 = 0
    ENDC
    IFGE VHS_PLANES-5
    clr.l    VHS_BYTES_PER_ROW*4(a0)         ; Plane 4 = 0
    ENDC

    addq.l   #4,a0                       ; next longword
    dbra     d6,.chunk_loop

    IFNE (VHS_BYTES_PER_ROW&2)
    ; Handle last 2 bytes (1 word) if row is not multiple of 4
    VHS_LFSR_STEP
    move.w   d2,d3
    lsr.w    #1,d3
    or.w     d2,d3
    move.w   d3,(a0)                     ; Plane 0
    move.w   d3,VHS_BYTES_PER_ROW(a0)        ; Plane 1
    move.w   d4,VHS_BYTES_PER_ROW*2(a0)      ; Plane 2
    IFGE VHS_PLANES-4
    clr.w    VHS_BYTES_PER_ROW*3(a0)         ; Plane 3 = 0
    ENDC
    IFGE VHS_PLANES-5
    clr.w    VHS_BYTES_PER_ROW*4(a0)         ; Plane 4 = 0
    ENDC
    ENDC

    lea      VHS_STRIDE(a1),a1        ; next scanline
    dbra     d7,.bar_row_loop

.bar_done:
    move.l   d2,VhsLfsr
    movem.l  (sp)+,d0-d7/a0-a4
    rts

;==============================================================================
; VhsDrawStreaks  -  Generate dynamic static streaks scattered across viewport
;
; Generates 3 dynamic static streaks scattered at random scanlines across the
; entire viewport in non-overlapping bands. Ensures no streak collides with the
; snow bar.
;
; In:       none
; Out:      none
; Destroys: none (preserves all registers)
;==============================================================================

VhsDrawStreaks:
    movem.l  d0-d4/a2,-(sp)
    move.l   VhsLfsr,d2

    ; Base camera Y for viewport
    move.w   TilemapCameraY(a5),d4
    andi.w   #255,d4

    ;--- Streak 1: Upper band (scanlines 28..75) ---
    VHS_LFSR_STEP
    move.w   d2,d1
    and.w    #$3f,d1                     ; 0..63
    cmp.w    #48,d1
    blt.s    .s1_rng
    sub.w    #16,d1                      ; 0..47
.s1_rng:
    add.w    #28,d1                      ; 28..75 (strictly below REW <<)
    bsr      .check_bar_collision
    move.w   d1,d0
    add.w    d4,d0                       ; viewport relative
    cmp.w    #RING_BUFFER_ALLOC_LINES,d0
    bge.s    .s1_skip
    move.w   d0,VhsPrevStreak1Y
    lea      VhsStreak1Backup,a2
    bsr      VhsDrawSingleNoiseStreak
.s1_skip:

    ;--- Streak 2: Mid band (scanlines 82..129) ---
    VHS_LFSR_STEP
    move.w   d2,d1
    and.w    #$3f,d1                     ; 0..63
    cmp.w    #48,d1
    blt.s    .s2_rng
    sub.w    #16,d1                      ; 0..47
.s2_rng:
    add.w    #82,d1                      ; 82..129
    bsr      .check_bar_collision
    move.w   d1,d0
    add.w    d4,d0                       ; viewport relative
    cmp.w    #RING_BUFFER_ALLOC_LINES,d0
    bge.s    .s2_skip
    move.w   d0,VhsPrevStreak2Y
    lea      VhsStreak2Backup,a2
    bsr      VhsDrawSingleNoiseStreak
.s2_skip:

    ;--- Streak 3: Lower band (scanlines 136..183) ---
    VHS_LFSR_STEP
    move.w   d2,d1
    and.w    #$3f,d1                     ; 0..63
    cmp.w    #48,d1
    blt.s    .s3_rng
    sub.w    #16,d1                      ; 0..47
.s3_rng:
    add.w    #136,d1                     ; 136..183
    bsr      .check_bar_collision
    move.w   d1,d0
    add.w    d4,d0                       ; viewport relative
    cmp.w    #RING_BUFFER_ALLOC_LINES,d0
    bge.s    .s3_skip
    move.w   d0,VhsPrevStreak3Y
    lea      VhsStreak3Backup,a2
    bsr      VhsDrawSingleNoiseStreak
.s3_skip:

    move.l   d2,VhsLfsr
    movem.l  (sp)+,d0-d4/a2
    rts

; Helper: If d1 is within VhsNoiseBarY .. VhsNoiseBarY + VhsPrevNoiseH + 2, offset away!
.check_bar_collision:
    move.w   VhsNoiseBarY,d3
    subq.w   #2,d3
    cmp.w    d3,d1
    blt.s    .col_ok
    add.w    VhsPrevNoiseH,d3
    addq.w   #4,d3
    cmp.w    d3,d1
    bgt.s    .col_ok
    add.w    #20,d1
    cmp.w    #192,d1
    blt.s    .col_ok
    sub.w    #40,d1
.col_ok:
    ; Ensure streak never creeps into REW << region (lines 0..27)
    cmp.w    #28,d1
    bge.s    .col_clamp_ok
    move.w   #28,d1
.col_clamp_ok:
    rts

;==============================================================================
; VhsDrawSingleNoiseStreak  -  Render 1 scanline noise streak and back up line
;
; In:       d0.w = scanline Y in DisplayScreen
;           a2   = backup buffer pointer in Fast RAM
;           d2.l = current LFSR state (updated in-place)
; Out:      d2.l = advanced LFSR state
; Destroys: d2 (preserves all other registers)
;==============================================================================

VhsDrawSingleNoiseStreak:
    cmp.w    #RING_BUFFER_ALLOC_LINES,d0
    bge.s    .sn_done
    movem.l  d0-d1/d3-d6/a0-a2,-(sp)

    ext.l    d0
    mulu.w   #VHS_STRIDE,d0
    lea      DisplayScreen,a0
    add.l    d0,a0                       ; a0 -> scanline in DisplayScreen

    ; 1. Backup 1 scanline to Fast RAM
    movea.l  a0,a1
    move.w   #VHS_WORDS_PER_STRIDE-1,d6
.sn_bak:
    move.w   (a1)+,(a2)+
    dbra     d6,.sn_bak

    ; 2. Render LFSR noise static line across VHS_BYTES_PER_ROW
    movea.l  a0,a1                       ; a1 -> Plane 0
    moveq    #(VHS_BYTES_PER_ROW/4)-1,d6
.sn_loop:
    VHS_LFSR_STEP
    move.l   d2,(a1)                     ; Plane 0
    move.l   d2,VHS_BYTES_PER_ROW(a1)        ; Plane 1
    clr.l    VHS_BYTES_PER_ROW*2(a1)         ; Plane 2
    IFGE VHS_PLANES-4
    clr.l    VHS_BYTES_PER_ROW*3(a1)         ; Plane 3
    ENDC
    IFGE VHS_PLANES-5
    clr.l    VHS_BYTES_PER_ROW*4(a1)         ; Plane 4
    ENDC
    addq.l   #4,a1
    dbra     d6,.sn_loop

    IFNE (VHS_BYTES_PER_ROW&2)
    VHS_LFSR_STEP
    move.w   d2,(a1)
    move.w   d2,VHS_BYTES_PER_ROW(a1)
    clr.w    VHS_BYTES_PER_ROW*2(a1)
    IFGE VHS_PLANES-4
    clr.w    VHS_BYTES_PER_ROW*3(a1)
    ENDC
    IFGE VHS_PLANES-5
    clr.w    VHS_BYTES_PER_ROW*4(a1)
    ENDC
    ENDC

    movem.l  (sp)+,d0-d1/d3-d6/a0-a2
.sn_done:
    rts

;==============================================================================
; Live Copper Scanline Tearing
;==============================================================================

    IFD VHS_USE_DISTORT_SLOTS

;==============================================================================
; VhsApplyCopperTears  -  Patch Copper list with horizontal tearing shifts
;
; Patches three scanline bands in cpVHSDistort with BPLCON1 horizontal delay moves.
;
; In:       none
; Out:      none
; Destroys: none (preserves all registers)
;==============================================================================

VhsApplyCopperTears:
    movem.l  d0-d5/a0-a1,-(sp)
    move.l   VhsLfsr,d2
    lea      cpVHSDistort,a0
    lea      VhsTearShifts,a1

    ; Determine raster base (PAL line 44 vs NTSC line 33)
    move.w   #WINDOW_Y_START,d5
    tst.w    IsPAL(a5)
    bne.s    .base_ok
    move.w   #NTSC_WINDOW_Y_START,d5
.base_ok:

    ; --- Tear Band 1 (Upper region: lines 28..59, strictly below OSD text) ---
    VHS_LFSR_STEP
    move.w   d2,d0
    and.w    #$1f,d0
    add.w    #28,d0                      ; d0 = LineA (28..59, below OSD text!)

    move.w   d2,d1
    lsr.w    #5,d1
    and.w    #$07,d1
    addq.w   #4,d1                       ; d1 = HeightA (4..11)
    add.w    d0,d1                       ; d1 = LineA + HeightA

    ; Shift magnitude for Tear 1
    move.w   d2,d3
    lsr.w    #8,d3
    and.w    #$07,d3
    add.w    d3,d3
    move.w   (a1,d3.w),d4                ; d4 = shift word (e.g. $00CC)

    ; Patch Band 1 start (WAIT + BPLCON1)
    move.w   d0,d3
    add.w    d5,d3                       ; d3 = raster line
    lsl.w    #8,d3
    or.w     #$07,d3
    move.w   d3,(a0)                     ; patch WAIT line
    move.w   d4,6(a0)                    ; patch BPLCON1

    ; Patch Band 1 end (WAIT + BPLCON1 = 0)
    move.w   d1,d3
    add.w    d5,d3
    lsl.w    #8,d3
    or.w     #$07,d3
    move.w   d3,8(a0)                    ; patch WAIT line
    clr.w    14(a0)                      ; BPLCON1 = 0

    ; --- Tear Band 2 (Mid region: lines 60..91) ---
    VHS_LFSR_STEP
    move.w   d2,d0
    and.w    #$1f,d0
    add.w    #60,d0                      ; d0 = LineB (60..91)

    move.w   d2,d1
    lsr.w    #5,d1
    and.w    #$07,d1
    addq.w   #5,d1                       ; d1 = HeightB (5..12)
    add.w    d0,d1                       ; d1 = LineB + HeightB

    ; Shift magnitude for Tear 2
    move.w   d2,d3
    lsr.w    #8,d3
    and.w    #$07,d3
    add.w    d3,d3
    move.w   (a1,d3.w),d4

    ; Patch Band 2 start
    move.w   d0,d3
    add.w    d5,d3
    lsl.w    #8,d3
    or.w     #$07,d3
    move.w   d3,16(a0)
    move.w   d4,22(a0)

    ; Patch Band 2 end
    move.w   d1,d3
    add.w    d5,d3
    lsl.w    #8,d3
    or.w     #$07,d3
    move.w   d3,24(a0)
    clr.w    30(a0)

    ; --- Tear Band 3 (Lower region: lines 120..151) ---
    VHS_LFSR_STEP
    move.w   d2,d0
    and.w    #$1f,d0
    add.w    #120,d0                     ; d0 = LineC (120..151)

    move.w   d2,d1
    lsr.w    #5,d1
    and.w    #$07,d1
    addq.w   #5,d1                       ; d1 = HeightC (5..12)
    add.w    d0,d1                       ; d1 = LineC + HeightC

    ; Shift magnitude for Tear 3
    move.w   d2,d3
    lsr.w    #8,d3
    and.w    #$07,d3
    add.w    d3,d3
    move.w   (a1,d3.w),d4

    ; Patch Band 3 start
    move.w   d0,d3
    add.w    d5,d3
    lsl.w    #8,d3
    or.w     #$07,d3
    move.w   d3,32(a0)
    move.w   d4,38(a0)

    ; Patch Band 3 end
    move.w   d1,d3
    add.w    d5,d3
    lsl.w    #8,d3
    or.w     #$07,d3
    move.w   d3,40(a0)
    clr.w    46(a0)

    move.b   #1,VhsTearActive
    move.l   d2,VhsLfsr
    movem.l  (sp)+,d0-d5/a0-a1
    rts

;==============================================================================
; VhsClearDistort  -  Reset Copper distortion slots to monotonic baselines
;
; Resets all six cpVHSDistort copper slots to monotonic baseline scanlines.
;
; In:       none
; Out:      none
; Destroys: none (preserves all registers)
;==============================================================================

VhsClearDistort:
    movem.l  d0-d1/a0,-(sp)
    lea      cpVHSDistort,a0

    move.w   #WINDOW_Y_START,d1
    tst.w    IsPAL(a5)
    bne.s    .cd_base_ok
    move.w   #NTSC_WINDOW_Y_START,d1
.cd_base_ok:

    ; Band 0 start & end
    move.w   d1,d0
    lsl.w    #8,d0
    or.w     #$07,d0
    move.w   d0,(a0)                     ; WAIT line
    clr.w    6(a0)                       ; BPLCON1 = 0

    move.w   d1,d0
    add.w    #10,d0
    lsl.w    #8,d0
    or.w     #$07,d0
    move.w   d0,8(a0)
    clr.w    14(a0)

    ; Band 1 start & end
    move.w   d1,d0
    add.w    #60,d0
    lsl.w    #8,d0
    or.w     #$07,d0
    move.w   d0,16(a0)
    clr.w    22(a0)

    move.w   d1,d0
    add.w    #70,d0
    lsl.w    #8,d0
    or.w     #$07,d0
    move.w   d0,24(a0)
    clr.w    30(a0)

    ; Band 2 start & end
    move.w   d1,d0
    add.w    #120,d0
    lsl.w    #8,d0
    or.w     #$07,d0
    move.w   d0,32(a0)
    clr.w    38(a0)

    move.w   d1,d0
    add.w    #130,d0
    lsl.w    #8,d0
    or.w     #$07,d0
    move.w   d0,40(a0)
    clr.w    46(a0)

    clr.b    VhsTearActive
    movem.l  (sp)+,d0-d1/a0
    rts

    ELSE

;------------------------------------------------------------------------------
; VhsApplyCopperTears  (Raster Table Mode via cpGameSky)
; Patches three scanline bands in cpGameSky with BPLCON1 delay moves.
;------------------------------------------------------------------------------
; Destroys: none (preserves all registers)

VhsApplyCopperTears:
    movem.l  d0-d4/a0-a1,-(sp)
    move.l   VhsLfsr,d2
    lea      cpGameSky,a0
    lea      VhsTearShifts,a1

    ; --- Tear Band 1 (Upper region: lines 28..59, below OSD text & sky) ---
    VHS_LFSR_STEP
    move.w   d2,d0
    and.w    #$1f,d0
    add.w    #28,d0                      ; d0 = LineA (28..59, below OSD text!)
    move.w   d0,VhsTear1Start

    move.w   d2,d1
    lsr.w    #5,d1
    and.w    #$07,d1
    addq.w   #4,d1                       ; d1 = HeightA (4..11)
    add.w    d0,d1                       ; d1 = LineA + HeightA
    move.w   d1,VhsTear1End

    ; Shift magnitude for Tear 1
    move.w   d2,d3
    lsr.w    #8,d3
    and.w    #$07,d3
    add.w    d3,d3
    move.w   (a1,d3.w),d4                ; d4 = shift word (e.g. $00CC)

    ; Patch entry LineA
    move.w   d0,d3
    lsl.w    #3,d3                       ; d3 = LineA * 8
    move.w   6(a0,d3.w),VhsTear1ColorS ; save original color
    move.w   #$0102,4(a0,d3.w)           ; write BPLCON1 register
    move.w   d4,6(a0,d3.w)               ; write shift delay

    ; Patch entry LineA + HeightA (reset to 0)
    move.w   d1,d3
    lsl.w    #3,d3                       ; d3 = (LineA + HeightA) * 8
    move.w   6(a0,d3.w),VhsTear1ColorE ; save original color
    move.w   #$0102,4(a0,d3.w)           ; write BPLCON1 register
    move.w   #$0000,6(a0,d3.w)           ; shift = 0

    ; --- Tear Band 2 (Mid region: lines 60..95) ---
    VHS_LFSR_STEP
    move.w   d2,d0
    and.w    #$1f,d0
    add.w    #60,d0                      ; d0 = LineB (60..91)
    move.w   d0,VhsTear2Start

    move.w   d2,d1
    lsr.w    #5,d1
    and.w    #$07,d1
    addq.w   #5,d1                       ; d1 = HeightB (5..12)
    add.w    d0,d1                       ; d1 = LineB + HeightB
    move.w   d1,VhsTear2End

    ; Shift magnitude for Tear 2
    move.w   d2,d3
    lsr.w    #8,d3
    and.w    #$07,d3
    add.w    d3,d3
    move.w   (a1,d3.w),d4

    ; Patch entry LineB
    move.w   d0,d3
    lsl.w    #3,d3
    move.w   6(a0,d3.w),VhsTear2ColorS
    move.w   #$0102,4(a0,d3.w)
    move.w   d4,6(a0,d3.w)

    ; Patch entry LineB + HeightB (reset to 0)
    move.w   d1,d3
    lsl.w    #3,d3
    move.w   6(a0,d3.w),VhsTear2ColorE
    move.w   #$0102,4(a0,d3.w)
    move.w   #$0000,6(a0,d3.w)

    ; --- Tear Band 3 (Lower region: lines 120..160) ---
    VHS_LFSR_STEP
    move.w   d2,d0
    and.w    #$1f,d0
    add.w    #120,d0                     ; d0 = LineC (120..151)
    move.w   d0,VhsTear3Start

    move.w   d2,d1
    lsr.w    #5,d1
    and.w    #$07,d1
    addq.w   #5,d1                       ; d1 = HeightC (5..12)
    add.w    d0,d1                       ; d1 = LineC + HeightC
    move.w   d1,VhsTear3End

    ; Shift magnitude for Tear 3
    move.w   d2,d3
    lsr.w    #8,d3
    and.w    #$07,d3
    add.w    d3,d3
    move.w   (a1,d3.w),d4

    ; Patch entry LineC
    move.w   d0,d3
    lsl.w    #3,d3
    move.w   6(a0,d3.w),VhsTear3ColorS
    move.w   #$0102,4(a0,d3.w)
    move.w   d4,6(a0,d3.w)

    ; Patch entry LineC + HeightC (reset to 0)
    move.w   d1,d3
    lsl.w    #3,d3
    move.w   6(a0,d3.w),VhsTear3ColorE
    move.w   #$0102,4(a0,d3.w)
    move.w   #$0000,6(a0,d3.w)

    move.b   #1,VhsTearActive
    move.l   d2,VhsLfsr
    movem.l  (sp)+,d0-d4/a0-a1
    rts

;------------------------------------------------------------------------------
; VhsRestoreCopperTears  (Raster Table Mode via cpGameSky)
; Restores patched BPLCON1 entries in cpGameSky back to COLOR00 moves.
;------------------------------------------------------------------------------
; Destroys: none (preserves all registers)

VhsRestoreCopperTears:
    tst.b    VhsTearActive
    beq      .done
    movem.l  d0/a0,-(sp)
    lea      cpGameSky,a0

    ; Restore Tear 1 start & end
    move.w   VhsTear1Start,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VhsTear1ColorS,6(a0,d0.w)
    move.w   VhsTear1End,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VhsTear1ColorE,6(a0,d0.w)

    ; Restore Tear 2 start & end
    move.w   VhsTear2Start,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VhsTear2ColorS,6(a0,d0.w)
    move.w   VhsTear2End,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VhsTear2ColorE,6(a0,d0.w)

    ; Restore Tear 3 start & end
    move.w   VhsTear3Start,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VhsTear3ColorS,6(a0,d0.w)
    move.w   VhsTear3End,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VhsTear3ColorE,6(a0,d0.w)

    move.w   #$0000,CUSTOM+BPLCON1
    clr.b    VhsTearActive
    movem.l  (sp)+,d0/a0
.done:
    rts

;------------------------------------------------------------------------------
; VhsClearDistort  (Raster Table Mode via cpGameSky)
;------------------------------------------------------------------------------
; Destroys: d0/a0 (preserves everything else, including a5/a6)

VhsClearDistort:
    move.w   #$0000,CUSTOM+BPLCON1
    bsr      VhsRestoreCopperTears
    rts

    ENDC
