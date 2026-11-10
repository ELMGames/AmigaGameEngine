;==============================================================================
; AMIGA GAME ENGINE
; copper_sky.asm  -  Copper Sky Background Gradient Parallax Engine
;                    for the 32-Row Continuous Twin-Mirror Buffer
;==============================================================================
;
; CONTINUOUS TWIN-MIRROR BUFFER & SKY GRADIENT DYNAMIC GENERATION
; ===============================================================
; In the 32-row (512-scanline) twin-mirror ring buffer architecture, rows 16..31
; are maintained as an exact copy of rows 0..15. Bitplane DMA streams all 216
; visible scanlines contiguously from DisplayScreen + (BufferCamY * 160) with
; no mid-screen bitplane pointer splits required:
;
;         CRT Viewport                            Chip RAM Twin-Mirror Buffer
;   +-------------------------------+         +-----------------------------+
;   | 216-Scanline Continuous View  | ======> | Primary Rows 0..15 (0..255) |
;   | (Any BufferCamY in 0..255)    |         |-----------------------------|
;   |                               |         | Mirror Rows 16..31(256..511)|
;   |                               |         | (Exact copy of Rows 0..15)  |
;   |                               |         +-----------------------------+
;   |                               |         (Zero mid-screen BPLxPT splits)
;   +-------------------------------+
;
; This generator writes 216 scanline WAIT/COLOR00 entries into cpGameSky at
; 1/2 vertical parallax speed (SkyY = TilemapCameraY >> 1), painting the
; twilight sky gradient behind color 0 with zero CPU raster overhead.
;==============================================================================

;==============================================================================
; TilemapDisableCopperSky  -  Halt sky gradient Copper list
;
; Emits COPPER_HALT directly.
;
; In:       none
; Out:      none
; Destroys: none (preserves all registers)
;==============================================================================

TilemapDisableCopperSky:
    PUSHM       a1
    lea         cpGameSky,a1
    move.l      #COPPER_HALT,(a1)+
    move.l      #COPPER_HALT,(a1)+
    POPM        a1
    rts

;==============================================================================
; TilemapEnableCopperSky  -  Restore Copper sky gradient and refresh colors
;
; In:       none
; Out:      none
; Destroys: none (preserves all registers)
;==============================================================================

TilemapEnableCopperSky:
    PUSHM       d0/d7/a0-a1
    bsr         TilemapUpdateCopperSkyForce
    move.w      #0,COLOR00(a6)          ; ensure background color returns to black
    POPM        d0/d7/a0-a1
    rts

;==============================================================================
; TilemapUpdateCopperSky  -  Update Copper Sky Gradient with 1/2 Parallax Speed
;
; If CPU raster profiler is active (DebugMode == 2), calls TilemapDisableCopperSky
; to preserve background profiling bars.
;
; Destroys: d0-d7, a0-a3
;==============================================================================

TilemapUpdateCopperSky:
    cmp.w       #2,DebugMode(a5)
    bne.s       TilemapUpdateCopperSkyForce
    bsr         TilemapDisableCopperSky
    rts

;==============================================================================
; TilemapUpdateCopperSkyForce  -  Build Dynamic Copper Sky List
;
; Computes SkyY = TilemapCameraY >> 1 (1/2 parallax), then linearly emits
; all 216 scanline WAITs/COLOR00 moves into cpGameSky.
; Continuous 32-row buffer requires no mid-screen seam splits!
;
; Destroys: d0-d7, a0-a3
;==============================================================================

TilemapUpdateCopperSkyForce:
    PUSHM       d0-d7/a0-a3

    ; Ensure VBlank top-of-frame COLOR00 in cpPal is reset to black ($0000)
    ; before cpGameSky begins painting scanline 0
    clr.w       cpPal+2

    ; 1. Calculate SkyY = CameraY >> 1 (1/2 parallax)
    move.w      TilemapCameraY(a5),d0
    lsr.w       #1,d0
    add.w       d0,d0                   ; 2 bytes per word
    lea         CopperSkyTable,a0
    adda.w      d0,a0                   ; a0 -> 216 words of sky palette
    tst.w       SkyFadeMode(a5)
    beq.s       .no_sky_fade
    bsr         SkyFadeApply            ; a0 -> the same 216 colours, faded
.no_sky_fade:

    lea         cpGameSky,a1            ; a1 -> destination copper buffer

    tst.w       IsPAL(a5)
    beq.s       .ntsc_sky

    ; --- PAL: 216 scanlines from PAL line 44 ($2c) to line 259 ($103) ---
    ; Lines 44..255 (212 scanlines)
    move.w      #$2c,d1                 ; current raster line
    move.w      #212-1,d7

.pal_loop1:
    move.w      d1,d0
    lsl.w       #8,d0
    ori.w       #$07,d0
    move.w      d0,(a1)+
    move.w      #$fffe,(a1)+

    move.w      #COLOR00,(a1)+
    move.w      (a0)+,(a1)+

    addq.w      #1,d1
    dbra        d7,.pal_loop1

    ; Line 255 crossing
    move.w      #$ffdf,(a1)+
    move.w      #$fffe,(a1)+

    ; Lines 256..259 (4 scanlines, VPOS $00..$03)
    clr.w       d1
    moveq       #4-1,d7

.pal_loop2:
    move.w      d1,d0
    lsl.w       #8,d0
    ori.w       #$07,d0
    move.w      d0,(a1)+
    move.w      #$fffe,(a1)+

    move.w      #COLOR00,(a1)+
    move.w      (a0)+,(a1)+

    addq.w      #1,d1
    dbra        d7,.pal_loop2

    ; Line 260: reset background at bottom margin before VBlank / row 0
    move.w      #$0407,(a1)+
    move.w      #$fffe,(a1)+
    move.w      #COLOR00,(a1)+
    clr.w       (a1)+

    move.l      #COPPER_HALT,(a1)+
    move.l      #COPPER_HALT,(a1)+
    POPM        d0-d7/a0-a3
    rts

.ntsc_sky:
    ; Lines 28..243 (216 scanlines)
    move.w      #NTSC_WINDOW_Y_START,d1
    move.w      #216-1,d7

.ntsc_loop:
    move.w      d1,d0
    lsl.w       #8,d0
    ori.w       #$07,d0
    move.w      d0,(a1)+
    move.w      #$fffe,(a1)+

    move.w      #COLOR00,(a1)+
    move.w      (a0)+,(a1)+

    addq.w      #1,d1
    dbra        d7,.ntsc_loop

    ; Bottom margin: reset background before VBlank / row 0
    move.w      #((NTSC_WINDOW_Y_START+216)<<8)|$07,(a1)+
    move.w      #$fffe,(a1)+
    move.w      #COLOR00,(a1)+
    clr.w       (a1)+

    move.l      #COPPER_HALT,(a1)+
    move.l      #COPPER_HALT,(a1)+
    POPM        d0-d7/a0-a3
    rts

;==============================================================================
; SkyFadeApply  -  Fade the 216 sky colours in step with the palette fade
;
; The palette fade (palette_fade.asm) moves every 4-bit channel one level per
; step, so after k steps (k = PalFadeStep) a fade-in has each channel at
; min(target, k) and a fade-out at max(target - k, 0). This applies the same
; rule to the sky gradient, so the sky brightens and darkens with the rest of
; the screen instead of being switched off and snapping back afterwards.
;
; In:       a0 = first of the SCREEN_HEIGHT sky colours to show
;           SkyFadeMode(a5) = SKY_FADE_IN or SKY_FADE_OUT, PalFadeStep(a5) = k
; Out:      a0 = SkyFadeBuf, holding the faded colours
; Destroys: d0-d7, a2
;==============================================================================

SkyFadeApply:
    move.w      PalFadeStep(a5),d6
    cmp.w       #FADE_MAX_STEPS,d6
    bls.s       .k_ok
    moveq       #FADE_MAX_STEPS,d6      ; d6 = k, at most 15
.k_ok:
    move.w      d6,d4
    lsl.w       #8,d4                   ; d4 = k in the red position
    move.w      d6,d5
    lsl.w       #4,d5                   ; d5 = k in the green position
    lea         SkyFadeBuf,a2
    move.w      #SCREEN_HEIGHT-1,d7
    cmp.w       #SKY_FADE_IN,SkyFadeMode(a5)
    bne.s       .out_loop

.in_loop:                               ; fade-in: each channel = min(channel, k)
    move.w      (a0)+,d0
    move.w      d0,d1
    and.w       #$0f00,d1
    cmp.w       d4,d1
    bls.s       .in_r
    move.w      d4,d1
.in_r:
    move.w      d0,d3
    and.w       #$00f0,d3
    cmp.w       d5,d3
    bls.s       .in_g
    move.w      d5,d3
.in_g:
    or.w        d3,d1
    and.w       #$000f,d0
    cmp.w       d6,d0
    bls.s       .in_b
    move.w      d6,d0
.in_b:
    or.w        d1,d0
    move.w      d0,(a2)+
    dbra        d7,.in_loop
    bra.s       .faded

.out_loop:                              ; fade-out: each channel = max(channel - k, 0)
    move.w      (a0)+,d0
    move.w      d0,d1
    and.w       #$0f00,d1
    sub.w       d4,d1
    bpl.s       .out_r
    moveq       #0,d1
.out_r:
    move.w      d0,d3
    and.w       #$00f0,d3
    sub.w       d5,d3
    bpl.s       .out_g
    moveq       #0,d3
.out_g:
    or.w        d3,d1
    and.w       #$000f,d0
    sub.w       d6,d0
    bpl.s       .out_b
    moveq       #0,d0
.out_b:
    or.w        d1,d0
    move.w      d0,(a2)+
    dbra        d7,.out_loop

.faded:
    lea         SkyFadeBuf,a0
    rts

    section     mem_fast,bss
SkyFadeBuf:     ds.w    SCREEN_HEIGHT   ; faded sky colours while SkyFadeMode is set
    section     main,code


; TileAttributesTable  -  Physics & Collision Attribute Lookup Table
;
; Maps 256 tile indices to physical attributes:
;   ATTR_EMPTY       = 0 (air / free movement)
;   ATTR_SOLID       = 1 (solid platform / wall)
;   ATTR_LADDER      = 2 (climbable ladder)
;   ATTR_HAZARD      = 3 (hazard / spikes)
;   ATTR_PASSTHROUGH = 4 (jump-through platform)
;==============================================================================
