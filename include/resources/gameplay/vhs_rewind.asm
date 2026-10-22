;==============================================================================
; vhs_rewind.asm  -  VHS Cassette Rewind Screen Effect
; Amiga 68000 Assembly / OCS-ECS Chipset
;
; Triggered on F9 (UndoMove):
;   1. Desaturates & darkens the palette with dynamic LFSR colour-channel noise.
;   2. Live Copper Scanline Tearing: patches BPLCON1 horizontal delays across
;      three random scanline bands in cpGameSky, creating real hardware horizontal
;      tearing with analog chromatic aberration fringing (odd vs even plane phase).
;   3. OSD Text: renders solid white 'REW  <<' in the top-left corner of the viewport
;      using FontData with dark drop-shadow outline.
;   4. Dynamic Variable Tracking Noise Snow Bar & Streaks:
;      Renders an organically fluctuating tracking snow band (variable Y, variable
;      height 8..15 scanlines, sudden tracking slips & speed changes) plus multiple
;      random static noise streaks scattered dynamically across the entire screen!
;   5. Non-Destructive Fast RAM Backup Buffers:
;      Before noise or text is stamped, the exact scanlines from DisplayScreen are
;      backed up into dedicated Fast RAM buffers and restored before each new frame.
;      This guarantees that ALL stationary crates, dirt blocks, and actors on
;      DisplayScreen are 100% preserved and never corrupted or erased!
;
; PUBLIC API
;   VHS_Init          - call once in GameInit
;   VHS_StartEffect   - trigger the effect (ActionIdle, after bsr UndoMove)
;   VHS_StopEffect    - cancel early or finish effect (restores screen & copper)
;   VHS_DoFrame       - call every VBlank; d0=1 active, d0=0 just finished
;   VHS_RestoreScreen - restore previous frame's noise before scene rendering
;   VHS_StateActive   - byte flag: non-zero while effect is running
;   VHS_NoiseDrawn    - byte flag: non-zero if noise is currently on DisplayScreen
;
; All routines preserve a5 (Variables) and a6 (CUSTOM).
; VHS_DoFrame returns result in d0; all other registers preserved by all routines.
;==============================================================================

VHS_EFFECT_DURATION EQU  30          ; frames at full effect (~0.6 s at 50 Hz PAL)
VHS_LFSR_POLY       EQU  $80000057   ; Galois LFSR polynomial (maximal-length 32-bit)
VHS_NOISE_BITS      EQU  $0111       ; XOR mask: bits 0,4,8 = B/G/R channel LSBs
VHS_MAX_BAR_H       EQU  18          ; maximum possible tracking snow bar height

;==============================================================================
; Fast RAM BSS  (CPU-only; zeroed by OS at load)
;==============================================================================

    section  mem_fast,bss
    even

VHS_StateActive:    ds.b  1   ; non-zero while effect runs (exported symbol)
VHS_TearActive:     ds.b  1   ; non-zero if copper scanline tear is currently patched
VHS_TextDrawn:      ds.b  1   ; non-zero if REW << was drawn on screen
VHS_NoiseDrawn:     ds.b  1   ; non-zero if noise is currently stamped on DisplayScreen
VHS_JustFinished:   ds.b  1   ; non-zero on frame immediately post-unwind
    even

VHS_FrameCount:     ds.w  1   ; frames elapsed since VHS_StartEffect
VHS_SavedPal:       ds.w  32  ; original colour values captured from cpPal
VHS_DesPal:         ds.w  32  ; desaturated + darkened palette

VHS_NoiseBarY:      ds.w  1   ; current Y offset within viewport (10..185)
VHS_PrevNoiseY:     ds.w  1   ; previous absolute scanline Y in DisplayScreen (-1 if none)
VHS_PrevNoiseH:     ds.w  1   ; previous height of noise bar in scanlines
VHS_PrevStreak1Y:   ds.w  1   ; previous scanline Y of streak 1 (-1 if none)
VHS_PrevStreak2Y:   ds.w  1   ; previous scanline Y of streak 2 (-1 if none)
VHS_PrevStreak3Y:   ds.w  1   ; previous scanline Y of streak 3 (-1 if none)
VHS_PrevTextY:      ds.w  1   ; scanline Y where REW << was drawn (-1 if none)

; Live copper tear patch bookkeeping in cpGameSky
VHS_Tear1_Start:    ds.w  1   ; cpGameSky entry index for Tear 1 start
VHS_Tear1_End:      ds.w  1   ; cpGameSky entry index for Tear 1 end
VHS_Tear1_ColorS:   ds.w  1   ; original color save at Tear 1 start
VHS_Tear1_ColorE:   ds.w  1   ; original color save at Tear 1 end

VHS_Tear2_Start:    ds.w  1   ; cpGameSky entry index for Tear 2 start
VHS_Tear2_End:      ds.w  1   ; cpGameSky entry index for Tear 2 end
VHS_Tear2_ColorS:   ds.w  1   ; original color save at Tear 2 start
VHS_Tear2_ColorE:   ds.w  1   ; original color save at Tear 2 end

VHS_Tear3_Start:    ds.w  1   ; cpGameSky entry index for Tear 3 start
VHS_Tear3_End:      ds.w  1   ; cpGameSky entry index for Tear 3 end
VHS_Tear3_ColorS:   ds.w  1   ; original color save at Tear 3 start
VHS_Tear3_ColorE:   ds.w  1   ; original color save at Tear 3 end
    even

; Non-destructive scanline backup buffers in Fast RAM
; Captures exact DisplayScreen content before noise is stamped, restored before each frame
VHS_NoiseBarBackup: ds.b  VHS_MAX_BAR_H*TILEMAP_LINE_STRIDE  ; 18 * 160 = 2,880 bytes
VHS_Streak1Backup:  ds.b  TILEMAP_LINE_STRIDE                 ; 160 bytes
VHS_Streak2Backup:  ds.b  TILEMAP_LINE_STRIDE                 ; 160 bytes
VHS_Streak3Backup:  ds.b  TILEMAP_LINE_STRIDE                 ; 160 bytes
VHS_TextBackup:     ds.b  8*32                                ; 8 lines x 8 bytes x 4 planes = 256 bytes
    even

;==============================================================================
; Fast RAM DATA
;==============================================================================

    section  data_fast,data
    even

VHS_LFSR:           dc.l  $DEADBEEF
VHS_Str_Rew:        dc.b  "REW  <<",0
    even

; Horizontal BPLCON1 delay values for tearing (bits 7-4 = even planes, bits 3-0 = odd planes)
; Asymmetric values (e.g. $CB, $DC) introduce chromatic aberration / RGB edge fringing
VHS_TearShifts:     dc.w  $00CC, $00DD, $00BB, $00CB, $00EE, $0099, $00AA, $00DC
    even

;==============================================================================
; Code
;==============================================================================

    section  main,code
    even

;------------------------------------------------------------------------------
; VHS_Init
; Call once in GameInit after the copper list is live.
;------------------------------------------------------------------------------

VHS_Init:
    clr.b    VHS_StateActive
    clr.b    VHS_TearActive
    clr.b    VHS_TextDrawn
    clr.b    VHS_NoiseDrawn
    clr.b    VHS_JustFinished
    move.w   #-1,VHS_PrevNoiseY
    move.w   #-1,VHS_PrevStreak1Y
    move.w   #-1,VHS_PrevStreak2Y
    move.w   #-1,VHS_PrevStreak3Y
    move.w   #-1,VHS_PrevTextY
    rts

;------------------------------------------------------------------------------
; VHS_StartEffect
; Snapshot cpPal colour values, compute the desaturated VHS palette, apply
; it immediately to cpPal, and start the frame counter.
;------------------------------------------------------------------------------

VHS_StartEffect:
    movem.l  d0-d3/d7/a0-a1,-(sp)

    tst.b    VHS_StateActive
    beq.s    .first_start

    ; Already running: clean copper tears and reset timer
    bsr      VHS_RestoreCopperTears
    clr.b    VHS_NoiseDrawn
    move.w   #-1,VHS_PrevNoiseY
    move.w   #-1,VHS_PrevStreak1Y
    move.w   #-1,VHS_PrevStreak2Y
    move.w   #-1,VHS_PrevStreak3Y
    move.w   #-1,VHS_PrevTextY
    clr.w    VHS_FrameCount
    movem.l  (sp)+,d0-d3/d7/a0-a1
    rts

.first_start:
    ;--- Snapshot: cpPal colour values -> VHS_SavedPal -----------------------
    lea      cpPal+2,a0            ; a0 -> first colour value word
    lea      VHS_SavedPal,a1
    moveq    #32-1,d7
.snap:
    move.w   (a0),(a1)+
    addq.l   #4,a0                 ; next copper pair
    dbra     d7,.snap

    ;--- Desaturate: VHS_SavedPal -> VHS_DesPal ------------------------------
    lea      VHS_SavedPal,a0
    lea      VHS_DesPal,a1
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
    lea      VHS_DesPal,a0
    lea      cpPal+2,a1
    moveq    #32-1,d7
.apply0:
    move.w   (a0)+,(a1)
    addq.l   #4,a1
    dbra     d7,.apply0

.activate:
    move.b   #1,VHS_StateActive
    clr.w    VHS_FrameCount
    clr.b    VHS_TearActive
    clr.b    VHS_TextDrawn
    clr.b    VHS_NoiseDrawn
    clr.b    VHS_JustFinished
    move.w   #40,VHS_NoiseBarY
    move.w   #12,VHS_PrevNoiseH
    move.w   #-1,VHS_PrevNoiseY
    move.w   #-1,VHS_PrevStreak1Y
    move.w   #-1,VHS_PrevStreak2Y
    move.w   #-1,VHS_PrevStreak3Y
    move.w   #-1,VHS_PrevTextY

    movem.l  (sp)+,d0-d3/d7/a0-a1
    rts

;------------------------------------------------------------------------------
; VHS_StopEffect
; Restore the original palette, clean copper list tears, restore screen from
; Fast RAM backup buffers, and re-blit all static actors onto DisplayScreen.
;------------------------------------------------------------------------------

VHS_StopEffect:
    movem.l  d0-d7/a0-a4,-(sp)

    ; 1. Restore live copper tears in cpGameSky
    bsr      VHS_RestoreCopperTears

    ; 2. Ensure hardware BPLCON1 register is reset to 0
    move.w   #$0000,$dff102

    ; 3. Restore all modified DisplayScreen areas from Fast RAM backups
    bsr      VHS_RestoreScreen

    ; 4. Restore original palette from VHS_SavedPal to cpPal
    lea      VHS_SavedPal,a0
    lea      cpPal+2,a1
    moveq    #32-1,d7
.restore:
    move.w   (a0)+,(a1)
    addq.l   #4,a1
    dbra     d7,.restore

    clr.b    VHS_StateActive
    clr.b    VHS_TextDrawn
    clr.b    VHS_NoiseDrawn
    move.b   #1,VHS_JustFinished
    move.w   #-1,VHS_PrevNoiseY
    move.w   #-1,VHS_PrevStreak1Y
    move.w   #-1,VHS_PrevStreak2Y
    move.w   #-1,VHS_PrevStreak3Y
    move.w   #-1,VHS_PrevTextY

    ; 5. Re-mark all actors dirty and redraw static actors so DisplayScreen is 100% verified pristine
    bsr      MarkAllActorsDirty
    bsr      DrawStaticActors

    ; 6. Reset VBlank overrun count so post-unwind raster bar starts clean (green)
    clr.w    VBlankOverrunCount(a5)

    movem.l  (sp)+,d0-d7/a0-a4
    rts

;------------------------------------------------------------------------------
; VHS_DoFrame
; Call once per VBlank while VHS_StateActive is non-zero.
;------------------------------------------------------------------------------

VHS_DoFrame:
    movem.l  d1-d7/a0-a4,-(sp)

    ; Increment and check frame counter
    addq.w   #1,VHS_FrameCount
    cmp.w    #VHS_EFFECT_DURATION,VHS_FrameCount
    blt.s    .run

    ; Effect expired: stop effect cleanly
    bsr      VHS_StopEffect
    clr.w    VBlankOverrunCount(a5)
    movem.l  (sp)+,d1-d7/a0-a4
    moveq    #0,d0
    rts

.run:
    ; 1. Write VHS_DesPal + LFSR channel-noise to all 32 cpPal entries
    move.l   VHS_LFSR,d2
    lea      VHS_DesPal,a0
    lea      cpPal+2,a1
    moveq    #32-1,d7

.noise:
    lsr.l    #1,d2
    bcc.s    .no_xor
    eor.l    #VHS_LFSR_POLY,d2
.no_xor:
    move.w   (a0)+,d1              ; load desaturated colour
    move.w   d2,d0
    and.w    #VHS_NOISE_BITS,d0    ; isolate bits 0, 4, 8
    eor.w    d0,d1                 ; flip B/G/R LSBs at random
    move.w   d1,(a1)               ; write noisy colour to copper list
    addq.l   #4,a1
    dbra     d7,.noise

    move.l   d2,VHS_LFSR

    ; Ensure Color 3 in cpPal is brilliant solid white ($0FFF) for VCR OSD overlay
    move.w   #$0FFF,cpPal+(3*4)+2

    ; 2. Restore previous frame's copper scanline tears in cpGameSky
    bsr      VHS_RestoreCopperTears

    ; 3. Restore previous frame's screen noise (if not already done at frame start)
    bsr      VHS_RestoreScreen

    ; 4. Render 'REW <<' text in the top-left of the viewport (with Fast RAM backup)
    bsr      VHS_DrawRewindText

    ; 5. Draw dynamically variable tracking noise snow bar (with Fast RAM backup)
    bsr      VHS_DrawNoiseBar

    ; 6. Draw dynamic random static noise streaks across the screen (with Fast RAM backup)
    bsr      VHS_DrawStreaks

    ; Mark that screen noise is currently stamped on DisplayScreen
    move.b   #1,VHS_NoiseDrawn

    ; 7. Apply live Copper scanline tearing across cpGameSky
    bsr      VHS_ApplyCopperTears

    movem.l  (sp)+,d1-d7/a0-a4
    moveq    #1,d0
    rts

;------------------------------------------------------------------------------
; VHS_RestoreScreen
; Restores all scanlines and areas modified by the snow bar, streaks, and
; 'REW  <<' text box from the Fast RAM backup buffers back to DisplayScreen.
; Restores the EXACT pixels that were on DisplayScreen before the noise was drawn,
; guaranteeing that crates, dirt blocks, actors, and background are never lost.
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_RestoreScreen:
    tst.b    VHS_NoiseDrawn
    beq      .done
    movem.l  d0-d7/a0-a2,-(sp)

    ;--- 1. Restore Noise Bar (VHS_PrevNoiseH scanlines) ---
    move.w   VHS_PrevNoiseY,d0
    bmi.s    .no_bar
    cmp.w    #LEVEL_SCREEN_HEIGHT-VHS_MAX_BAR_H,d0
    bge.s    .no_bar

    ext.l    d0
    mulu.w   #TILEMAP_LINE_STRIDE,d0
    lea      DisplayScreen,a1
    add.l    d0,a1                       ; a1 -> dest in DisplayScreen
    lea      VHS_NoiseBarBackup,a0       ; a0 -> source in Fast RAM

    ; Number of longwords to restore = VHS_PrevNoiseH * 40
    move.w   VHS_PrevNoiseH,d6
    lsl.w    #3,d6                       ; H * 8
    move.w   d6,d5
    lsl.w    #2,d6                       ; H * 32
    add.w    d5,d6                       ; H * 40
    subq.w   #1,d6

.res_bar_loop:
    move.l   (a0)+,(a1)+
    dbra     d6,.res_bar_loop

    move.w   #-1,VHS_PrevNoiseY
.no_bar:

    ;--- 2. Restore Streak 1 (1 scanline = 40 longwords) ---
    move.w   VHS_PrevStreak1Y,d0
    bmi.s    .no_s1
    cmp.w    #LEVEL_SCREEN_HEIGHT,d0
    bge.s    .no_s1

    ext.l    d0
    mulu.w   #TILEMAP_LINE_STRIDE,d0
    lea      DisplayScreen,a1
    add.l    d0,a1
    lea      VHS_Streak1Backup,a0
    moveq    #40-1,d6
.res_s1_loop:
    move.l   (a0)+,(a1)+
    dbra     d6,.res_s1_loop

    move.w   #-1,VHS_PrevStreak1Y
.no_s1:

    ;--- 3. Restore Streak 2 (1 scanline = 40 longwords) ---
    move.w   VHS_PrevStreak2Y,d0
    bmi.s    .no_s2
    cmp.w    #LEVEL_SCREEN_HEIGHT,d0
    bge.s    .no_s2

    ext.l    d0
    mulu.w   #TILEMAP_LINE_STRIDE,d0
    lea      DisplayScreen,a1
    add.l    d0,a1
    lea      VHS_Streak2Backup,a0
    moveq    #40-1,d6
.res_s2_loop:
    move.l   (a0)+,(a1)+
    dbra     d6,.res_s2_loop

    move.w   #-1,VHS_PrevStreak2Y
.no_s2:

    ;--- 4. Restore Streak 3 (1 scanline = 40 longwords) ---
    move.w   VHS_PrevStreak3Y,d0
    bmi.s    .no_s3
    cmp.w    #LEVEL_SCREEN_HEIGHT,d0
    bge.s    .no_s3

    ext.l    d0
    mulu.w   #TILEMAP_LINE_STRIDE,d0
    lea      DisplayScreen,a1
    add.l    d0,a1
    lea      VHS_Streak3Backup,a0
    moveq    #40-1,d6
.res_s3_loop:
    move.l   (a0)+,(a1)+
    dbra     d6,.res_s3_loop

    move.w   #-1,VHS_PrevStreak3Y
.no_s3:

    ;--- 5. Restore 'REW  <<' text box (8 scanlines, columns 2..9) ---
    move.w   VHS_PrevTextY,d0
    bmi.s    .no_text
    cmp.w    #LEVEL_SCREEN_HEIGHT-8,d0
    bge.s    .no_text

    ext.l    d0
    mulu.w   #TILEMAP_LINE_STRIDE,d0
    lea      DisplayScreen,a1
    add.l    d0,a1
    addq.l   #2,a1                       ; column 2
    lea      VHS_TextBackup,a0
    moveq    #8-1,d7

.res_text_loop:
    move.l   (a0)+,(a1)                  ; Plane 0
    move.l   (a0)+,4(a1)
    move.l   (a0)+,40(a1)                ; Plane 1
    move.l   (a0)+,44(a1)
    move.l   (a0)+,80(a1)                ; Plane 2
    move.l   (a0)+,84(a1)
    move.l   (a0)+,120(a1)               ; Plane 3
    move.l   (a0)+,124(a1)
    lea      TILEMAP_LINE_STRIDE(a1),a1
    dbra     d7,.res_text_loop

    move.w   #-1,VHS_PrevTextY
.no_text:

    clr.b    VHS_NoiseDrawn
    movem.l  (sp)+,d0-d7/a0-a2
.done:
    rts

;------------------------------------------------------------------------------
; VHS_DrawRewindText
; Backs up the 8x8 character bounding box to VHS_TextBackup, then renders
; solid white 'REW  <<' (Color 3 = $0FFF) in the top-left corner of the
; viewport (at CameraPixelY + 12, column 2).
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_DrawRewindText:
    movem.l  d0-d7/a0-a4,-(sp)

    move.w   TilemapCameraY(a5),d0
    add.w    #12,d0                      ; 12 scanlines below top of viewport
    cmp.w    #LEVEL_SCREEN_HEIGHT-8,d0
    bge      .text_done
    move.w   d0,VHS_PrevTextY
    move.b   #1,VHS_TextDrawn

    ; 1. Backup text area from DisplayScreen to VHS_TextBackup
    ext.l    d0
    mulu.w   #TILEMAP_LINE_STRIDE,d0
    lea      DisplayScreen,a0
    add.l    d0,a0
    addq.l   #2,a0                       ; column 2
    lea      VHS_TextBackup,a1
    moveq    #8-1,d7

.bak_text_loop:
    move.l   (a0),(a1)+                  ; Plane 0
    move.l   4(a0),(a1)+
    move.l   40(a0),(a1)+                ; Plane 1
    move.l   44(a0),(a1)+
    move.l   80(a0),(a1)+                ; Plane 2
    move.l   84(a0),(a1)+
    move.l   120(a0),(a1)+               ; Plane 3
    move.l   124(a0),(a1)+
    lea      TILEMAP_LINE_STRIDE(a0),a0
    dbra     d7,.bak_text_loop

    ; 2. Render text glyphs onto DisplayScreen
    lea      DisplayScreen,a1
    add.l    d0,a1
    addq.l   #2,a1                       ; byte column 2 (X=16px)

    lea      FontData,a2
    lea      VHS_Str_Rew,a0

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
    beq.s    .next_row

    ; Bold smear + 1-pixel shadow outline
    move.b   d3,d4
    lsr.b    #1,d4
    or.b     d3,d4                       ; d4 = bold smear
    move.b   d4,d5
    lsl.b    #1,d5
    or.b     d4,d5                       ; d5 = shadow mask (smear + 1px left)
    not.b    d5                          ; d5 = inverted shadow mask (~shadow)

    ; Plane 0 & Plane 1: mask shadow, set glyph bits (Color 3 = white)
    and.b    d5,(a3)
    or.b     d4,(a3)                     ; Plane 0
    and.b    d5,40(a3)
    or.b     d4,40(a3)                   ; Plane 1

    ; Plane 2 & Plane 3: clear shadow & glyph bits
    and.b    d5,80(a3)                   ; Plane 2
    and.b    d5,120(a3)                  ; Plane 3

.next_row:
    lea      TILEMAP_LINE_STRIDE(a3),a3  ; next scanline (+160 bytes)
    dbra     d7,.row_loop

    addq.l   #1,a1                       ; advance to next character column
    bra.s    .char_loop

.text_done:
    movem.l  (sp)+,d0-d7/a0-a4
    rts

;------------------------------------------------------------------------------
; VHS_DrawNoiseBar
; Computes dynamic, variable Y position and height for the tracking snow band.
; Jumps, slips, and rolls organically across the entire screen (lines 10..185).
; Backs up VHS_PrevNoiseH scanlines to VHS_NoiseBarBackup, then renders dense
; analog static noise onto DisplayScreen.
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_DrawNoiseBar:
    movem.l  d0-d7/a0-a4,-(sp)
    move.l   VHS_LFSR,d2

    ; 1. Calculate variable advance delta & random tracking slip
    lsr.l    #1,d2
    bcc.s    .step_ok
    eor.l    #VHS_LFSR_POLY,d2
.step_ok:

    ; 1-in-4 chance of a sudden tracking slip / jump
    move.w   d2,d1
    and.w    #$03,d1
    bne.s    .normal_roll

    ; Sudden slip: jump +20..+51 pixels ahead
    move.w   d2,d1
    lsr.w    #2,d1
    and.w    #$1f,d1
    add.w    #20,d1
    add.w    d1,VHS_NoiseBarY
    bra.s    .check_wrap

.normal_roll:
    ; Variable roll speed: +6 to +13 pixels per frame
    move.w   d2,d1
    lsr.w    #2,d1
    and.w    #$07,d1
    addq.w   #6,d1
    add.w    d1,VHS_NoiseBarY

.check_wrap:
    cmp.w    #185,VHS_NoiseBarY
    blt.s    .y_in_range
    ; Wrap around with random entry offset (10..41)
    move.w   d2,d1
    lsr.w    #5,d1
    and.w    #$1f,d1
    add.w    #10,d1
    move.w   d1,VHS_NoiseBarY
.y_in_range:

    ; 2. Variable height: 8 to 15 scanlines
    move.w   d2,d7
    lsr.w    #7,d7
    and.w    #$07,d7
    addq.w   #8,d7                       ; d7 = height (8..15 scanlines)
    move.w   d7,VHS_PrevNoiseH

    ; Absolute scanline in DisplayScreen
    move.w   TilemapCameraY(a5),d0
    add.w    VHS_NoiseBarY,d0
    cmp.w    #LEVEL_SCREEN_HEIGHT-VHS_MAX_BAR_H,d0
    bge      .bar_done
    move.w   d0,VHS_PrevNoiseY

    ;--- 3. Backup d7 scanlines from DisplayScreen to VHS_NoiseBarBackup ---
    ext.l    d0
    mulu.w   #TILEMAP_LINE_STRIDE,d0
    lea      DisplayScreen,a0
    add.l    d0,a0                       ; a0 -> source in DisplayScreen
    lea      VHS_NoiseBarBackup,a1       ; a1 -> dest in Fast RAM

    ; Number of longwords to copy = d7 * 40
    move.w   d7,d6
    lsl.w    #3,d6                       ; d7 * 8
    move.w   d6,d5
    lsl.w    #2,d6                       ; d7 * 32
    add.w    d5,d6                       ; d6 = d7 * 40 longwords
    subq.w   #1,d6

.bak_bar_loop:
    move.l   (a0)+,(a1)+
    dbra     d6,.bak_bar_loop

    ;--- 4. Render variable analog LFSR snow band onto DisplayScreen ---
    lea      DisplayScreen,a1
    add.l    d0,a1                       ; a1 -> Plane 0

    subq.w   #1,d7                       ; for dbra scanlines

.bar_row_loop:
    movea.l  a1,a0                       ; a0 = Plane 0 for this scanline
    moveq    #10-1,d6                    ; 10 longwords = 40 bytes

.chunk_loop:
    lsr.l    #1,d2
    bcc.s    .np1
    eor.l    #VHS_LFSR_POLY,d2
.np1:
    move.l   d2,d3
    lsr.l    #1,d3
    or.l     d3,d2                       ; horizontal analog smear

    ; Write noise to Plane 0 & Plane 1 (creates brilliant white snow dots)
    move.l   d2,(a0)                     ; Plane 0
    move.l   d2,40(a0)                   ; Plane 1

    ; Secondary noise on Plane 2 for color static variation
    move.l   d2,d4
    eor.l    #$55555555,d4
    move.l   d4,80(a0)                   ; Plane 2
    clr.l    120(a0)                     ; Plane 3 = 0

    addq.l   #4,a0                       ; next longword
    dbra     d6,.chunk_loop

    lea      TILEMAP_LINE_STRIDE(a1),a1  ; next scanline
    dbra     d7,.bar_row_loop

.bar_done:
    move.l   d2,VHS_LFSR
    movem.l  (sp)+,d0-d7/a0-a4
    rts

;------------------------------------------------------------------------------
; VHS_DrawStreaks
; Generates 3 dynamic static streaks scattered at random scanlines across the
; entire viewport (lines 15..200). Ensures no streak collides with the snow bar.
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_DrawStreaks:
    movem.l  d0-d4/a2,-(sp)
    move.l   VHS_LFSR,d2

    ;--- Streak 1: Upper / Mid region (scanlines 22..85) ---
    lsr.l    #1,d2
    bcc.s    .s1_poly
    eor.l    #VHS_LFSR_POLY,d2
.s1_poly:
    move.w   d2,d1
    and.w    #$3f,d1                     ; 0..63
    add.w    #22,d1                      ; 22..85
    bsr      .check_bar_collision
    move.w   TilemapCameraY(a5),d0
    add.w    d1,d0
    move.w   d0,VHS_PrevStreak1Y
    lea      VHS_Streak1Backup,a2
    bsr      VHS_DrawSingleNoiseStreak

    ;--- Streak 2: Mid / Lower region (scanlines 95..158) ---
    swap     d2
    lsr.l    #1,d2
    bcc.s    .s2_poly
    eor.l    #VHS_LFSR_POLY,d2
.s2_poly:
    move.w   d2,d1
    and.w    #$3f,d1                     ; 0..63
    add.w    #95,d1                      ; 95..158
    bsr      .check_bar_collision
    move.w   TilemapCameraY(a5),d0
    add.w    d1,d0
    move.w   d0,VHS_PrevStreak2Y
    lea      VHS_Streak2Backup,a2
    bsr      VHS_DrawSingleNoiseStreak

    ;--- Streak 3: Full-range wild streak (scanlines 35..185) ---
    lsr.l    #1,d2
    bcc.s    .s3_poly
    eor.l    #VHS_LFSR_POLY,d2
.s3_poly:
    move.w   d2,d1
    and.w    #$7f,d1                     ; 0..127
    add.w    #35,d1                      ; 35..162
    bsr      .check_bar_collision
    move.w   TilemapCameraY(a5),d0
    add.w    d1,d0
    move.w   d0,VHS_PrevStreak3Y
    lea      VHS_Streak3Backup,a2
    bsr      VHS_DrawSingleNoiseStreak

    swap     d2
    move.l   d2,VHS_LFSR
    movem.l  (sp)+,d0-d4/a2
    rts

; Helper: If d1 is within VHS_NoiseBarY .. VHS_NoiseBarY + VHS_PrevNoiseH + 2, offset away!
.check_bar_collision:
    move.w   VHS_NoiseBarY,d3
    subq.w   #2,d3
    cmp.w    d3,d1
    blt.s    .col_ok
    add.w    VHS_PrevNoiseH,d3
    addq.w   #4,d3
    cmp.w    d3,d1
    bgt.s    .col_ok
    add.w    #25,d1
    cmp.w    #195,d1
    blt.s    .col_ok
    sub.w    #55,d1
.col_ok:
    rts

;------------------------------------------------------------------------------
; VHS_DrawSingleNoiseStreak
; In: d0.w = scanline Y in DisplayScreen, a2 = backup buffer pointer in Fast RAM
; Backs up 1 scanline (40 longwords) to a2, then writes LFSR noise.
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_DrawSingleNoiseStreak:
    cmp.w    #LEVEL_SCREEN_HEIGHT,d0
    bge.s    .sn_done
    movem.l  d0-d6/a0-a2,-(sp)

    ext.l    d0
    mulu.w   #TILEMAP_LINE_STRIDE,d0
    lea      DisplayScreen,a0
    add.l    d0,a0                       ; a0 -> scanline in DisplayScreen

    ; 1. Backup 1 scanline (40 longwords = 160 bytes) to Fast RAM
    movea.l  a0,a1
    moveq    #40-1,d6
.sn_bak:
    move.l   (a1)+,(a2)+
    dbra     d6,.sn_bak

    ; 2. Render LFSR noise static line
    move.l   VHS_LFSR,d2
    movea.l  a0,a1                       ; a1 -> Plane 0
    moveq    #10-1,d6
.sn_loop:
    lsr.l    #1,d2
    bcc.s    .sn_p
    eor.l    #VHS_LFSR_POLY,d2
.sn_p:
    move.l   d2,(a1)
    move.l   d2,40(a1)
    clr.l    80(a1)
    clr.l    120(a1)
    addq.l   #4,a1
    dbra     d6,.sn_loop

    move.l   d2,VHS_LFSR
    movem.l  (sp)+,d0-d6/a0-a2
.sn_done:
    rts

;------------------------------------------------------------------------------
; VHS_ApplyCopperTears
; Patches three scanline bands in cpGameSky with BPLCON1 delay moves, causing
; hardware-level horizontal tearing of the playfield across those lines.
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_ApplyCopperTears:
    movem.l  d0-d4/a0-a1,-(sp)
    move.l   VHS_LFSR,d2
    lea      cpGameSky,a0
    lea      VHS_TearShifts,a1

    ; --- Tear Band 1 (Upper region: lines 12..35, tearing across 'REW <<' & sky) ---
    lsr.l    #1,d2
    bcc.s    .tp1
    eor.l    #VHS_LFSR_POLY,d2
.tp1:
    move.w   d2,d0
    and.w    #$1f,d0
    add.w    #12,d0                      ; d0 = LineA (12..43)
    move.w   d0,VHS_Tear1_Start

    move.w   d2,d1
    lsr.w    #5,d1
    and.w    #$07,d1
    addq.w   #4,d1                       ; d1 = HeightA (4..11)
    add.w    d0,d1                       ; d1 = LineA + HeightA
    move.w   d1,VHS_Tear1_End

    ; Shift magnitude for Tear 1
    move.w   d2,d3
    lsr.w    #8,d3
    and.w    #$07,d3
    add.w    d3,d3
    move.w   (a1,d3.w),d4                ; d4 = shift word (e.g. $00CC)

    ; Patch entry LineA
    move.w   d0,d3
    lsl.w    #3,d3                       ; d3 = LineA * 8
    move.w   6(a0,d3.w),VHS_Tear1_ColorS ; save original color
    move.w   #$0102,4(a0,d3.w)           ; write BPLCON1 register
    move.w   d4,6(a0,d3.w)               ; write shift delay

    ; Patch entry LineA + HeightA (reset to 0)
    move.w   d1,d3
    lsl.w    #3,d3                       ; d3 = (LineA + HeightA) * 8
    move.w   6(a0,d3.w),VHS_Tear1_ColorE ; save original color
    move.w   #$0102,4(a0,d3.w)           ; write BPLCON1 register
    move.w   #$0000,6(a0,d3.w)           ; shift = 0

    ; --- Tear Band 2 (Mid region: lines 60..95) ---
    lsr.l    #1,d2
    bcc.s    .tp2
    eor.l    #VHS_LFSR_POLY,d2
.tp2:
    move.w   d2,d0
    and.w    #$1f,d0
    add.w    #60,d0                      ; d0 = LineB (60..91)
    move.w   d0,VHS_Tear2_Start

    move.w   d2,d1
    lsr.w    #5,d1
    and.w    #$07,d1
    addq.w   #5,d1                       ; d1 = HeightB (5..12)
    add.w    d0,d1                       ; d1 = LineB + HeightB
    move.w   d1,VHS_Tear2_End

    ; Shift magnitude for Tear 2
    move.w   d2,d3
    lsr.w    #8,d3
    and.w    #$07,d3
    add.w    d3,d3
    move.w   (a1,d3.w),d4

    ; Patch entry LineB
    move.w   d0,d3
    lsl.w    #3,d3
    move.w   6(a0,d3.w),VHS_Tear2_ColorS
    move.w   #$0102,4(a0,d3.w)
    move.w   d4,6(a0,d3.w)

    ; Patch entry LineB + HeightB (reset to 0)
    move.w   d1,d3
    lsl.w    #3,d3
    move.w   6(a0,d3.w),VHS_Tear2_ColorE
    move.w   #$0102,4(a0,d3.w)
    move.w   #$0000,6(a0,d3.w)

    ; --- Tear Band 3 (Lower region: lines 120..160) ---
    lsr.l    #1,d2
    bcc.s    .tp3
    eor.l    #VHS_LFSR_POLY,d2
.tp3:
    move.w   d2,d0
    and.w    #$1f,d0
    add.w    #120,d0                     ; d0 = LineC (120..151)
    move.w   d0,VHS_Tear3_Start

    move.w   d2,d1
    lsr.w    #5,d1
    and.w    #$07,d1
    addq.w   #5,d1                       ; d1 = HeightC (5..12)
    add.w    d0,d1                       ; d1 = LineC + HeightC
    move.w   d1,VHS_Tear3_End

    ; Shift magnitude for Tear 3
    move.w   d2,d3
    lsr.w    #8,d3
    and.w    #$07,d3
    add.w    d3,d3
    move.w   (a1,d3.w),d4

    ; Patch entry LineC
    move.w   d0,d3
    lsl.w    #3,d3
    move.w   6(a0,d3.w),VHS_Tear3_ColorS
    move.w   #$0102,4(a0,d3.w)
    move.w   d4,6(a0,d3.w)

    ; Patch entry LineC + HeightC (reset to 0)
    move.w   d1,d3
    lsl.w    #3,d3
    move.w   6(a0,d3.w),VHS_Tear3_ColorE
    move.w   #$0102,4(a0,d3.w)
    move.w   #$0000,6(a0,d3.w)

    move.b   #1,VHS_TearActive
    move.l   d2,VHS_LFSR
    movem.l  (sp)+,d0-d4/a0-a1
    rts

;------------------------------------------------------------------------------
; VHS_RestoreCopperTears
; Restores patched BPLCON1 entries in cpGameSky back to COLOR00 moves.
; Preserves all registers.
;------------------------------------------------------------------------------

VHS_RestoreCopperTears:
    tst.b    VHS_TearActive
    beq      .done
    movem.l  d0/a0,-(sp)
    lea      cpGameSky,a0

    ; Restore Tear 1 start & end
    move.w   VHS_Tear1_Start,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VHS_Tear1_ColorS,6(a0,d0.w)
    move.w   VHS_Tear1_End,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VHS_Tear1_ColorE,6(a0,d0.w)

    ; Restore Tear 2 start & end
    move.w   VHS_Tear2_Start,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VHS_Tear2_ColorS,6(a0,d0.w)
    move.w   VHS_Tear2_End,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VHS_Tear2_ColorE,6(a0,d0.w)

    ; Restore Tear 3 start & end
    move.w   VHS_Tear3_Start,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VHS_Tear3_ColorS,6(a0,d0.w)
    move.w   VHS_Tear3_End,d0
    lsl.w    #3,d0
    move.w   #$0180,4(a0,d0.w)
    move.w   VHS_Tear3_ColorE,6(a0,d0.w)

    clr.b    VHS_TearActive
    movem.l  (sp)+,d0/a0
.done:
    rts
