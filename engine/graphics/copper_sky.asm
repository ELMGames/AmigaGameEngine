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


; TileAttributesTable  -  Physics & Collision Attribute Lookup Table
;
; Maps 256 tile indices to physical attributes:
;   ATTR_EMPTY       = 0 (air / free movement)
;   ATTR_SOLID       = 1 (solid platform / wall)
;   ATTR_LADDER      = 2 (climbable ladder)
;   ATTR_HAZARD      = 3 (hazard / spikes)
;   ATTR_PASSTHROUGH = 4 (jump-through platform)
;==============================================================================
