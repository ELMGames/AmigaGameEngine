;==============================================================================
; AMIGA GAME ENGINE
; pause_system.asm  -  Universal Pause Banner & Copper Palette Desaturator
;==============================================================================

; PauseDesaturateColor  -  Helper: Desaturate (50%) and darken (50%) an OCS color
;
; In:   d0.w = $0RGB color (4 bits per channel)
; Out:  d0.w = desaturated and darkened $0RGB color
; Destroys: d1, d2, d3
;==============================================================================
PauseDesaturateColor:
    ; Extract channels into d1=R, d2=G, d0=B
    move.w      d0,d1
    lsr.w       #8,d1
    andi.w      #$F,d1                  ; d1 = R (0..15)

    move.w      d0,d2
    lsr.w       #4,d2
    andi.w      #$F,d2                  ; d2 = G (0..15)

    andi.w      #$F,d0                  ; d0 = B (0..15)

    ; Calculate luminance: grey = (R + G + B) * 85 >> 8
    move.w      d1,d3
    add.w       d2,d3
    add.w       d0,d3                   ; d3 = R + G + B (0..45)
    mulu.w      #85,d3
    lsr.l       #8,d3
    andi.w      #$F,d3                  ; d3 = grey (0..14)

    ; 50% desaturation towards grey: new = (ch + grey) >> 1
    add.w       d3,d1
    lsr.w       #1,d1                   ; new R
    add.w       d3,d2
    lsr.w       #1,d2                   ; new G
    add.w       d3,d0
    lsr.w       #1,d0                   ; new B

    ; 50% darkening: new = new >> 1
    lsr.w       #1,d1
    lsr.w       #1,d2
    lsr.w       #1,d0

    ; Pack into d0: (R << 8) | (G << 4) | B
    lsl.w       #4,d2
    or.w        d2,d0                   ; d0 = (G << 4) | B
    lsl.w       #8,d1
    or.w        d1,d0                   ; d0 = (R << 8) | (G << 4) | B
    rts

;==============================================================================
; PauseApplyPalette  -  Snapshot cpPal, desaturate & darken Copper palette & sky
;
; Desaturates and darkens all 32 palette colors in cpPal (stride 4) and the
; 216 scanline colors in cpGameSky (stride 8). Keeps Color 5 at $04F4 (bright green)
; so the centered "** PAUSED **" text overlay stands out vividly.
;
; In:  none
; Out: none
; Destroys: none (preserves all registers)
;==============================================================================
PauseApplyPalette:
    PUSHM       d0-d3/d7/a0-a1

    tst.w       PausePaletteActive(a5)
    bne         .pa_done                ; already active: do not re-snapshot

    ; 1. Snapshot original 32 palette values from cpPal+2 into PauseSavedPal
    lea         cpPal+2,a0              ; a0 -> first color operand in cpPal
    lea         PauseSavedPal(a5),a1
    moveq       #32-1,d7
.pa_snap:
    move.w      (a0),(a1)+
    addq.l      #4,a0                   ; stride 4 bytes per copper MOVE
    dbra        d7,.pa_snap

    ; 2. Compute desaturated + darkened colors and write into cpPal
    lea         PauseSavedPal(a5),a0
    lea         cpPal+2,a1
    moveq       #32-1,d7
.pa_desat:
    move.w      (a0)+,d0
    bsr         PauseDesaturateColor
    move.w      d0,(a1)
    addq.l      #4,a1
    dbra        d7,.pa_desat

    ; 3. Pin COLOR14 (entry 14) to bright neon green for the pause text overlay
    ; Color 14 is unused by all map tiles, actors, and friends.
    ; Entry 14 value word = cpPal + (14 * 4) + 2 = cpPal + 58
    move.w      #$04f4,cpPal+(14*4)+2

    ; 4. Desaturate and darken cpGameSky scanline gradient entries
    lea         cpGameSky+6,a1          ; first COLOR00 operand in cpGameSky
    tst.w       IsPAL(a5)
    beq.s       .pa_sky_ntsc

    ; --- PAL: 212 lines, skip 4-byte wait at line 255, then 4 lines ---
    move.w      #212-1,d7
.pa_sky_pal1:
    move.w      (a1),d0
    bsr         PauseDesaturateColor
    move.w      d0,(a1)
    addq.l      #8,a1                   ; stride 8 bytes (WAIT + MOVE COLOR00)
    dbra        d7,.pa_sky_pal1

    addq.l      #4,a1                   ; skip line-255 crossing WAIT ($FFDF, $FFFE)
    moveq       #4-1,d7
.pa_sky_pal2:
    move.w      (a1),d0
    bsr         PauseDesaturateColor
    move.w      d0,(a1)
    addq.l      #8,a1
    dbra        d7,.pa_sky_pal2
    bra.s       .pa_sky_done

.pa_sky_ntsc:
    ; --- NTSC: 216 contiguous scanlines ---
    move.w      #216-1,d7
.pa_sky_ntsc_loop:
    move.w      (a1),d0
    bsr         PauseDesaturateColor
    move.w      d0,(a1)
    addq.l      #8,a1
    dbra        d7,.pa_sky_ntsc_loop

.pa_sky_done:
    move.w      #1,PausePaletteActive(a5)

.pa_done:
    POPM        d0-d3/d7/a0-a1
    rts

;==============================================================================
; PauseRestorePalette  -  Restore original palette to cpPal and refresh cpGameSky
;
; In:  none
; Out: none
; Destroys: none (preserves all registers)
;==============================================================================
PauseRestorePalette:
    PUSHM       d0/d7/a0-a1

    tst.w       PausePaletteActive(a5)
    beq.s       .pr_done

    ; 1. Restore 32 colors to cpPal from PauseSavedPal
    lea         PauseSavedPal(a5),a0
    lea         cpPal+2,a1
    moveq       #32-1,d7
.pr_restore:
    move.w      (a0)+,(a1)
    addq.l      #4,a1
    dbra        d7,.pr_restore

    ; 2. Refresh Copper sky gradient from CopperSkyTable
    bsr         TilemapUpdateCopperSky

    clr.w       PausePaletteActive(a5)

.pr_done:
    POPM        d0/d7/a0-a1
    rts


;==============================================================================
; PauseDrawLine  -  Render pause banner text in Color 14 (unused by tiles)
;
; In:   d0.w = Screen Y coordinate
;       d1.w = Byte column (0..39)
;       a0   = Pointer to null-terminated string
;
; Writes glyph bits into Bitplanes 1, 2, and 3 (%1110 = Color 14), clearing Plane 0.
; Color 14 is completely unused by all map tiles, actors, and friends,
; ensuring zero tile color corruption when highlighted.
;
; Destroys: none (preserves all registers)
;==============================================================================
PauseDrawLine:
    PUSHM       d0-d5/d7/a0-a4

    ; Base pointer in DisplayScreen: ((Y & RING_BUFFER_MASK) * 160) + X + DisplayScreen
    andi.w      #511,d0
    mulu.w      #TILEMAP_LINE_STRIDE,d0     ; d0.l = 32-bit unsigned offset
    lea         DisplayScreen,a1
    add.l       d0,a1
    ext.l       d1
    add.l       d1,a1                       ; a1 = target byte in DisplayScreen (Plane 0)
    lea         FontData,a2                 ; a2 = base of FontData

.char_loop:
    move.b      (a0)+,d2
    beq.s       .done

    ; Bounds check character (only ASCII 32..127 in font)
    cmp.b       #32,d2
    bge.s       .char_ge32
    moveq       #32,d2
.char_ge32:
    cmp.b       #127,d2
    ble.s       .char_ok
    moveq       #32,d2
.char_ok:
    sub.b       #32,d2
    and.w       #$00ff,d2
    lsl.w       #3,d2                       ; d2 = (char - 32) * 8
    lea         (a2,d2.w),a4                ; a4 -> 8 bytes of glyph

    ; Render 8 scanlines for this character
    movea.l     a1,a3                       ; a3 = Plane 0 for current row
    moveq       #8-1,d7
.row_loop:
    move.b      (a4)+,d3
    move.b      d3,d4
    lsr.b       #1,d4
    or.b        d4,d3                       ; bold smear

    clr.b       (a3)                        ; Plane 0 = 0     (Color 14 bit 0)
    move.b      d3,40(a3)                   ; Plane 1 = glyph (Color 14 bit 1)
    move.b      d3,80(a3)                   ; Plane 2 = glyph (Color 14 bit 2)
    move.b      d3,120(a3)                  ; Plane 3 = glyph (Color 14 bit 3)

    lea         160(a3),a3                  ; advance to next scanline (+160 bytes)
    dbra        d7,.row_loop

    addq.l      #1,a1                       ; next byte column (+8 pixels)
    bra.s       .char_loop

.done:
    POPM        d0-d5/d7/a0-a4
    rts

;==============================================================================
; TilemapDrawPauseBanner  -  Dim the palette and draw the PAUSED banner
;
; Applies the desaturated pause palette, draws "PAUSED" at column 17,
; scanline (TilemapCameraY & 255) + 96 of the ring buffer. The display reads
; contiguous lines from (TilemapCameraY & 255) and the camera cannot move while
; paused, so one copy is enough. Records the scanline in PrevPauseCameraY for
; the erase.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapDrawPauseBanner:
    PUSHM       d0-d1/a0
    bsr         PauseApplyPalette
    move.w      TilemapCameraY(a5),d0
    andi.w      #255,d0
    add.w       #96,d0                      ; 96..351 in 512-line buffer
    move.w      d0,PrevPauseCameraY(a5)     ; save exact buffer scanline for erase on unpause
    moveq       #17,d1                      ; column 17: exactly centered for 6-char "PAUSED"
    lea         .str_paused(pc),a0
    bsr         PauseDrawLine

    POPM        d0-d1/a0
    rts

.str_paused:    dc.b    "PAUSED",0
                even


;==============================================================================
; TilemapErasePauseBanner  -  Restore screen background where pause banner was drawn
;
; Called when game is unpaused via 'P' key.
; Restores the 8-scanline background strip from NonDisplayScreen to DisplayScreen.
;
; Destroys: none (preserves all registers)
;==============================================================================
TilemapErasePauseBanner:
    PUSHM       d0-d7/a0-a4/a6
    lea         CUSTOM,a6
    WAITBLIT

    ; Calculate start byte offset of the banner
    move.w      PrevPauseCameraY(a5),d0
    andi.w      #511,d0
    mulu.w      #TILEMAP_LINE_STRIDE,d0
    add.l       #16,d0                      ; columns 16..23 (covers centered "PAUSED" at cols 17..22)

    lea         NonDisplayScreen,a0
    add.l       d0,a0
    lea         DisplayScreen,a1
    add.l       d0,a1

    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #32,BLTAMOD(a6)             ; 40 - 8 = 32
    move.w      #32,BLTDMOD(a6)             ; 40 - 8 = 32
    move.w      #0,BLTCON1(a6)
    move.w      #MINTERM_COPY,BLTCON0(a6)          ; A -> D copy (minterm $F0)
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(32<<6)|4,BLTSIZE(a6)      ; 32 plane-rows x 4 words = 8 scanlines x 8 bytes
    WAITBLIT

    ; Restore full-color palette to cpPal & cpGameSky
    bsr         PauseRestorePalette

    ; Mark all actors dirty and redraw push blocks / crates immediately
    bsr         MarkAllActorsDirty
    bsr         TilemapDrawPushBlocks

    ; Let the game invalidate anything it must redraw after the banner is gone
    bsr         GameUnpauseHook

    POPM        d0-d7/a0-a4/a6
    rts


