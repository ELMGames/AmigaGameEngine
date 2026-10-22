
;==============================================================================
; AMIGA GAME ENGINE
; gamecomplete.asm  -  Game Complete Screen (states 19 / 20)
;==============================================================================
;
; Displayed when the player completes the campaign (all 6 levels cleared, LevelId = 5).
; LevelCompleteSetup redirects to GameCompleteSetup before its normal flow.
;
; Screen layout (336x200 pixels, 5-plane interleaved, same geometry as cpTitle):
;
;   Y=5, bX=12   "YOU HAVE COMPLETED" (18 chars, green)
;   Y= 40..95      victory duckling (GCDucklingRaw, 64x96, 4 bitplanes) blitted
;                  into screen planes 1-4 with bobbing animation;
;                  colours patched from TitleDuckPal (plane 0 for starfield)
;   Y=150, bX=13   "CONGRATULATIONS!" (16 chars, green)
;   Y=190, bX=12   "THANKS FOR PLAYING" (18 chars, pink/red)
;
; Starfield: GC_NUM_STARS=64 stars in three depth layers, all drawn into plane 0.
;
;   Layer assignment by star index:
;     stars  0-23  speed 1 px/frame  1x1 pixel      far background (twinkle)
;     stars 24-47  speed 2 px/frame  2x2 pixels     mid-field
;     stars 48-63  speed 4 px/frame  3x1 h-streak   foreground (motion-blur look)
;
;   Twinkling: slow stars (0-23) skip drawing when (starY & 7) == (GCFrameTick & 7).
;   Each star has a unique phase so they drop out at different moments; at 50 Hz
;   the 1-in-8-frame gap is imperceptible as flicker but reads as dimness/distance.
;
;   Presimulation: GCMoveStars is called GC_PRESIM_FRAMES (336) times during setup
;   before the screen is first displayed.  After 336 simulated frames every slow
;   star (speed 1) has crossed the screen and respawned at least once, breaking
;   any correlation in the initial LFSR sequence and making the field look like
;   it has already been running for ~6-7 seconds on the very first visible frame.
;
;   LFSR X init: re-rolled to 0..335 (& $01FF + bhi) for full-width coverage.
;   LFSR Y init: & $FF + bhi/blo re-roll to GC_STAR_MIN_Y..GC_STAR_MAX_Y (23..184);
;   starts on the row after "YOU COMPLETED ALL LEVELS!" (row 15+8 = 23).
;
;   Multi-pixel mask technique:
;     mask_word = BASE >> (X & 7)   ; BASE $C000=2px wide, $E000=3px wide
;     high_byte = mask_word >> 8    ; bits for byte_x
;     low_byte  = mask_word & $FF   ; bits for byte_x+1 (zero when no crossing)
;   Max X per layer: 334 (2px), 333 (3px) -- ensures low_byte=0 when byte_x=41.
;
; Exits on FIRE / joystick button or Return -> TITLE_SETUP.
;
; Entry points:
;   GameCompleteSetup  -- one-shot init (GameStatus = GAME_COMPLETE_SETUP = 19)
;   GameCompleteRun    -- per-frame handler (GameStatus = GAME_COMPLETE_RUN = 20)
;
; Register convention: a5 = Variables base, a6 = $dff000 (CUSTOM).
;==============================================================================

; Screen-address offsets into DisplayScreen (LOADING_ROW_BYTES = 200 per row)
; 40 characters across: byte_x = (40 - strlen) / 2
GC_OFF_COMPLETE  = 15*LOADING_ROW_BYTES+7    ; "YOU COMPLETED ALL LEVELS!" (26 chars -> X=7)
GC_OFF_CONGRATS  = 145*LOADING_ROW_BYTES+12   ; "CONGRATULATIONS!" (16 chars -> X=12)
GC_OFF_THANKS    = 175*LOADING_ROW_BYTES+11   ; "THANKS FOR PLAYING" (18 chars -> X=11)

;------------------------------------------------------------------------------
; Duckling character geometry (GCDucklingRaw: 64x96 pixels, 4 bitplanes).
; Centered horizontally on 320px screen: (320 - 64) / 2 = 128 (byte col 16).
; Blitted into screen planes 1-4 (plane 0 belongs to the starfield).
;
; In screen planes 1-4, duck colour v (1-15) displays at colour index 2*v;
; a star pixel behind the duck adds bit 0 giving index 2*v+1.
; GameCompleteSetup patches BOTH entries of each pair with TitleDuckPal colour v,
; so the duckling naturally and solidly occludes the starfield without masking!
;
; Bobbing animation:
;   Vertical position Y = GC_DUCK_BASE_Y + Sinus[(GCFrameTick*16) & $0FFF] * amplitude.
;   Y oscillates gently between rows 30 and 42 (amplitude ±6 pixels),
;   leaving clean margins above row 145 and below row 23.
;------------------------------------------------------------------------------
GC_DUCK_X           = 128            ; pixel X: centered ((320-64)/2 = 128, 16 bytes)
GC_DUCK_BASE_Y      = 36             ; base pixel Y (centered between Y=23 and Y=145)
GC_DUCK_W           = 64             ; duck width in pixels
GC_DUCK_H           = 96             ; duck height in pixels
GC_DUCK_W_BYTES     = GC_DUCK_W/8    ; 8 bytes per row
GC_DUCK_W_WORDS     = GC_DUCK_W_BYTES/2 ; 4 words per row
GC_DUCK_PLANES      = 4              ; 4 bitplanes (16 colours)
GC_DUCK_PLANE_SIZE  = GC_DUCK_W_BYTES*GC_DUCK_H ; 768 bytes per plane
GC_DUCK_DMOD        = LOADING_ROW_BYTES-GC_DUCK_W_BYTES ; 200 - 8 = 192

; Dest offset of plane 1 at (GC_DUCK_X, Y):
; Row Y plane 1 is at DisplayScreen + Y * LOADING_ROW_BYTES + LOADING_WIDTH_BYTE + GC_DUCK_X/8
; LOADING_WIDTH_BYTE + GC_DUCK_X/8 = 40 + 16 = 56 bytes.
GC_DUCK_DEST_X_OFF  = LOADING_WIDTH_BYTE+GC_DUCK_X/8 ; 56


;==============================================================================
; GameCompleteSetup  -  One-shot init for the game complete screen (state 19)
;
; Sequence:
;   1. Stop music; clear DisplayScreen.
;   2. Patch cpGCPlanes + cpGCSprites; install cpGameComplete copper list.
;   3. Patch duckling palette into cpGCPal; blit GCDucklingRaw into planes 1-4.
;   4. Draw static text.
;   5. Seed LFSR; initialise GC_NUM_STARS stars with uniform random X (0..335)
;      and Y (0..GC_STAR_MAX_Y) from the Galois LFSR (each re-rolled into range).
;      Reset GCFrameTick to 0.
;   6. Pre-simulate GC_PRESIM_FRAMES frames via GCMoveStars so the field looks
;      populated and varied from the very first displayed frame.
;   7. Advance GameStatus to GAME_COMPLETE_RUN.
;==============================================================================

GameCompleteSetup:
    PUSHALL

    bsr         AudioStopMod

    ; 1. Clear DisplayScreen
    lea         DisplayScreen,a0
    move.l      #LOADING_ROW_BYTES*LOADING_HEIGHT,d7
    bsr         TurboClear

    ; 2a. Patch cpGCPlanes with DisplayScreen bitplane addresses
    move.l      #DisplayScreen,d0
    lea         cpGCPlanes,a0
    moveq       #SCREEN_DEPTH-1,d7
.ploop
    move.w      d0,6(a0)
    swap        d0
    move.w      d0,2(a0)
    swap        d0
    addq.l      #8,a0
    add.l       #LOADING_WIDTH_BYTE,d0
    dbra        d7,.ploop

    ; 2b. Patch cpGCSprites -> NullSprite
    move.l      #NullSprite,d0
    lea         cpGCSprites,a0
    moveq       #8-1,d7
.sploop
    move.w      d0,6(a0)
    swap        d0
    move.w      d0,2(a0)
    swap        d0
    addq.l      #8,a0
    dbra        d7,.sploop

    ; 2c. Build per-scanline star color copper entries.
    ;     Written before the copper is installed so the list is valid on frame 1.
    ;     Entries from Y=GC_STAR_MIN_Y..GC_STAR_MAX_Y: each scanline gets a random COLOR01
    ;     so stars appear in white, yellow, red or blue depending on their Y position.
    lea         cpGCDynColors,a0
    lea         .gcColorTab(pc),a1
    move.w      #GC_STAR_RAND_INIT,d5
    move.w      #GC_STAR_MIN_Y,d6
    bra.s       .gc_cop_loop
.gcColorTab
    dc.w        $0FFF               ; 0: white
    dc.w        $0FF0               ; 1: yellow
    dc.w        $0F00               ; 2: red
    dc.w        $00AF               ; 3: blue
.gc_cop_loop
    move.w      d6,d4
    add.w       #$2C,d4             ; raster line = $2C + screen Y
    lsl.w       #8,d4
    or.w        #$0007,d4
    move.w      d4,(a0)+            ; WAIT word 0: (raster<<8)|$07
    move.w      #$FFFE,(a0)+        ; WAIT word 1: enable mask
    lsr.w       #1,d5               ; step Galois LFSR
    bcc.s       .gc_no_xor
    eor.w       #$B400,d5
.gc_no_xor
    move.w      d5,d4
    and.w       #3,d4               ; 2-bit color index (0-3)
    add.w       d4,d4               ; word offset into color table
    move.w      #COLOR01,(a0)+      ; MOVE: target register
    move.w      (a1,d4.w),(a0)+     ; MOVE: color value

    ; If scanline is row 26, inject duckling palette (colors 12-15 -> COLOR24..COLOR31)
    cmp.w       #26,d6
    bne.s       .no_row26
    lea         TitleDuckPal+12*2,a2
    move.w      #COLOR24,d2
    moveq       #4-1,d3
.cop_duck_pal
    move.w      (a2)+,d1
    move.w      d2,(a0)+
    move.w      d1,(a0)+            ; COLOR(2v)
    addq.w      #2,d2
    move.w      d2,(a0)+
    move.w      d1,(a0)+            ; COLOR(2v+1)
    addq.w      #2,d2
    dbra        d3,.cop_duck_pal
.no_row26

    ; If scanline is row 140, restore text colors (COLOR24/25 = green, COLOR28/29 = red)
    cmp.w       #140,d6
    bne.s       .no_row140
    move.w      #COLOR24,(a0)+
    move.w      #$00C0,(a0)+        ; COLOR24 = green
    move.w      #COLOR25,(a0)+
    move.w      #$00C0,(a0)+        ; COLOR25 = green
    move.w      #COLOR28,(a0)+
    move.w      #$0C00,(a0)+        ; COLOR28 = red
    move.w      #COLOR29,(a0)+
    move.w      #$0C00,(a0)+        ; COLOR29 = red
.no_row140

    addq.w      #1,d6
    cmp.w       #GC_STAR_MAX_Y,d6
    ble         .gc_cop_loop
    move.l      #$FFFFFFFE,(a0)+    ; COPPER_HALT
    move.l      #$FFFFFFFE,(a0)+    ; COPPER_HALT (belt-and-braces)

    ; 2d. Install copper list and re-enable DMA
    move.l      #cpGameComplete,COP1LC(a6)
    move.w      #0,COPJMP1(a6)
  ;  move.w      #BASE_DMA,DMACON(a6)

    ; 3a. Patch duckling colours 1-11 into cpGCPal from TitleDuckPal (skip entry 0:
    ;     transparent). Each duck colour v fills the pair COLOR(2v)/COLOR(2v+1)
    ;     so duckling pixels solidly occlude plane-0 stars.
    lea         TitleDuckPal+2,a0       ; -> duck colour 1
    lea         cpGCPal+2*4+2,a1        ; -> COLOR02 value word
    moveq       #11-1,d7
.lpal
    move.w      (a0)+,d0
    move.w      d0,(a1)                 ; COLOR(2v)   = duck colour v
    move.w      d0,4(a1)                ; COLOR(2v+1) = same (star behind duck)
    addq.l      #8,a1                   ; next even/odd colour pair
    dbra        d7,.lpal

    ; 3b. Stage GCDucklingRaw into NonDisplayScreen (Chip RAM) and blit into screen planes 1-4
    lea         GCDucklingRaw,a0
    lea         NonDisplayScreen,a1
    move.w      #(GC_DUCK_PLANE_SIZE*GC_DUCK_PLANES/4)-1,d0
.gc_stage_duck:
    move.l      (a0)+,(a1)+
    dbra        d0,.gc_stage_duck

    WAITBLIT
    move.l      #$09F00000,BLTCON0(a6)  ; D=A, no shift, BLTCON1=0
    move.l      #-1,BLTAFWM(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #GC_DUCK_DMOD,BLTDMOD(a6)
    move.l      #NonDisplayScreen,d0    ; staged in Chip RAM
    lea         DisplayScreen+GC_DUCK_BASE_Y*LOADING_ROW_BYTES+GC_DUCK_DEST_X_OFF,a1
    moveq       #GC_DUCK_PLANES-1,d7
.lblit:
    WAITBLIT
    move.l      d0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(GC_DUCK_H<<6)|GC_DUCK_W_WORDS,BLTSIZE(a6)
    add.l       #GC_DUCK_PLANE_SIZE,d0  ; next source plane
    add.l       #LOADING_WIDTH_BYTE,a1  ; next interleaved screen plane
    dbra        d7,.lblit

    move.w      #GC_DUCK_BASE_Y,GCDuckPrevY(a5)

    ; 4. Draw static text
    WAITBLIT

    lea         .str_complete,a0
    lea         DisplayScreen+GC_OFF_COMPLETE,a1
    bsr         CHAR_BLTStringGreen
    
    lea         .str_congrats,a0
    lea         DisplayScreen+GC_OFF_CONGRATS,a1
    bsr         CHAR_BLTStringGreen

    lea         .str_thanks,a0
    lea         DisplayScreen+GC_OFF_THANKS,a1
    bsr         CHAR_BLTStringRed

    ; 5. Initialise all stars from the Galois LFSR.
    ;
    ;    X: & $01FF (0..511) re-rolled if > 335 -- uniform across full screen width.
    ;    Y: & $FF   (0..255) re-rolled if > 184 -- uniform, no gap at Y=64..127.
    move.w      #GC_STAR_RAND_INIT,d5
    lea         GCStarX(a5),a0
    lea         GCStarY(a5),a1
    moveq       #GC_NUM_STARS-1,d7

.star_init
.init_x
    lsr.w       #1,d5
    bcc.s       .no_xor_x
    eor.w       #$B400,d5
.no_xor_x
    move.w      d5,d0
    and.w       #$01FF,d0
    cmp.w       #GC_STAR_MAX_X,d0
    bhi.s       .init_x
    move.w      d0,(a0)+

.init_y
    lsr.w       #1,d5
    bcc.s       .no_xor_y
    eor.w       #$B400,d5
.no_xor_y
    move.w      d5,d0
    and.w       #$FF,d0
    cmp.w       #GC_STAR_MAX_Y,d0
    bhi.s       .init_y
    cmp.w       #GC_STAR_MIN_Y,d0
    blo.s       .init_y
    move.w      d0,(a1)+

    dbra        d7,.star_init

    move.w      d5,GCStarRand(a5)
    clr.w       GCFrameTick(a5)

    ; 6. Pre-simulate GC_PRESIM_FRAMES frames so every star (including the
    ;    slowest, speed-1 layer) has crossed the screen and respawned at least
    ;    once.  This breaks the sequential LFSR correlation in initial positions
    ;    and makes the field look like it has been scrolling for ~6-7 seconds.
    ;    GCMoveStars uses d0-d3/d5-d7/a0-a1; d4 is safe as the outer counter.
    move.w      #GC_PRESIM_FRAMES-1,d4
.presim
    bsr         GCMoveStars
    dbra        d4,.presim

    ; 7. Enter running state
    bsr         AudioPlayGameCompleteMusic
    clr.w       VBlankOverrunCount(a5) ; clear multi-frame setup overruns
    move.w      #GAME_COMPLETE_RUN,GameStatus(a5)

    POPALL
    rts

.str_complete   dc.b    "YOU COMPLETED ALL LEVELS!",0
.str_congrats   dc.b    "CONGRATULATIONS!",0
.str_thanks     dc.b    "THANKS FOR PLAYING",0
                even


;==============================================================================
; GCMoveStars  -  Advance all 64 star positions by one frame
;
; Called from GameCompleteSetup (GC_PRESIM_FRAMES times) and from
; GameCompleteRun (once per frame).  Defined between the two entry points so
; it can be reached by bsr from both without a forward reference.
;
; Speed by star index:
;   0-23   speed 1  (1x1 twinkle layer)
;   24-47  speed 2  (2x2 layer)
;   48-63  speed 4  (3x1 streak layer)
;
; On underflow (carry after sub), star respawns at X=GC_STAR_RESPAWN_X with
; a new Y from the Galois LFSR (& $FF, bhi re-roll into 0..GC_STAR_MAX_Y).
;
; Register use (no PUSHALL; caller saves what it needs):
;   d0  X value / LFSR temp
;   d2  speed
;   d3  LFSR byte / Y candidate
;   d5  LFSR state (loaded from GCStarRand on entry, saved on exit)
;   d6  star index i
;   d7  dbra counter
;   a0  -> GCStarX[i]
;   a1  -> GCStarY[i]
;==============================================================================

GCMoveStars:
    move.w      GCStarRand(a5),d5
    lea         GCStarX(a5),a0
    lea         GCStarY(a5),a1
    moveq       #GC_NUM_STARS-1,d7
    moveq       #0,d6

.ms_loop
    moveq       #1,d2
    cmp.w       #24,d6
    blt.s       .ms_speed
    moveq       #2,d2
    cmp.w       #48,d6
    blt.s       .ms_speed
    moveq       #4,d2
.ms_speed

    move.w      (a0),d0
    sub.w       d2,d0
    bcs.s       .ms_respawn
    cmp.w       #GC_STAR_MAX_X,d0
    bhi.s       .ms_respawn
    move.w      d0,(a0)
    bra.s       .ms_done

.ms_respawn
    move.w      #GC_STAR_RESPAWN_X,(a0)
.ms_ry
    lsr.w       #1,d5
    bcc.s       .ms_no_xor
    eor.w       #$B400,d5
.ms_no_xor
    move.w      d5,d3
    and.w       #$FF,d3
    cmp.w       #GC_STAR_MAX_Y,d3
    bhi.s       .ms_ry
    cmp.w       #GC_STAR_MIN_Y,d3
    blo.s       .ms_ry
    move.w      d3,(a1)

.ms_done
    addq.l      #2,a0
    addq.l      #2,a1
    addq.w      #1,d6
    dbra        d7,.ms_loop

    move.w      d5,GCStarRand(a5)
    rts


;==============================================================================
; GameCompleteRun  -  Per-frame handler for the game complete screen (state 16)
;
; Optimizations applied:
;   1. VBlank-Synchronized Duck Rendering: Duckling bobbing blits execute FIRST
;      during early VBlank (scanlines 0..36) with uncontested Blitter DMA.
;      All 4 planes are 100% rendered before the display window opens at line 44,
;      completely eliminating beam-race flicker on the duckling.
;   2. Selective Star Erase: Eliminates the 4,200-word full plane 0 Blitter clear.
;      Erases only previous star footprints using AND.B ~(mask).
;   3. GCRowTable: Direct 32-bit row offset table lookup eliminates 68000 mulu.
;
; Each frame:
;   1. Read controls; FIRE or Return -> AudioStopMod + TITLE_SETUP + return.
;   2. Duckling bobbing: compute new Y; if Y changed, blit planes 1-4 immediately during VBlank.
;   3. bsr GCEraseStars -- erase all 64 stars from their current plane-0 positions.
;   4. bsr GCMoveStars  -- advance all star positions (speed 1/2/4, respawn).
;   5. bsr GCDrawStars  -- draw all 64 stars into plane 0.
;==============================================================================

GameCompleteRun:
    bsr         UpdateControls

    move.b      ControlsTrigger(a5),d0
    btst        #CONTROLB_FIRE,d0
    bne.s       .quit

    lea         Keys,a0
    tst.b       KEY_RETURN(a0)
    beq.s       .no_quit
.quit:
    lea         Keys,a0
    clr.b       KEY_RETURN(a0)
    bsr         AudioStopMod
    move.w      #TITLE_SETUP,GameStatus(a5)
    rts
.no_quit:

    ;--------------------------------------------------------------------------
    ; 1. Bobbing Duckling Animation (RUNS FIRST DURING VBLANK!)
    ;    Executed immediately while raster beam is at scanlines 0..20, far
    ;    above the duck's display position (row 30..42, scanline 74+).
    ;    Uncontested Blitter DMA guarantees all 4 planes are fully written
    ;    by scanline 36 (well before the display window begins at scanline 44),
    ;    completely preventing any beam-race flicker.
    ;--------------------------------------------------------------------------
    addq.w      #1,GCFrameTick(a5)

    move.w      GCFrameTick(a5),d0
    lsl.w       #4,d0               ; speed: tick * 16 (cycle = 128 frames = 2.5s)
    and.w       #$0FFF,d0           ; wrap to 0..4095 byte offset into Sinus
    lea         Sinus,a0
    move.w      (a0,d0.w),d0        ; signed 16-bit sine: -32767..+32767
    muls.w      #12,d0
    swap        d0                  ; d0.w = -6..+6
    add.w       #GC_DUCK_BASE_Y,d0  ; d0.w = target Y (rows 30..42)

    cmp.w       GCDuckPrevY(a5),d0
    beq         .duck_no_move

    ; Y changed! Erase duckling at previous position in planes 1-4
    move.w      GCDuckPrevY(a5),d1
    lsl.w       #2,d1
    lea         GCRowTable,a0
    move.l      (a0,d1.w),d1
    lea         DisplayScreen+GC_DUCK_DEST_X_OFF,a1
    adda.l      d1,a1               ; a1 = dest plane 1 at PrevY

    WAITBLIT
    move.w      #$0100,BLTCON0(a6)  ; D=0 (clear)
    clr.w       BLTCON1(a6)
    move.w      #GC_DUCK_DMOD,BLTDMOD(a6)
    moveq       #GC_DUCK_PLANES-1,d7
.duck_clear:
    WAITBLIT
    move.l      a1,BLTDPT(a6)
    move.w      #(GC_DUCK_H<<6)|GC_DUCK_W_WORDS,BLTSIZE(a6)
    add.l       #LOADING_WIDTH_BYTE,a1
    dbra        d7,.duck_clear

    ; Blit duckling at new Y into planes 1-4
    move.w      d0,GCDuckPrevY(a5)
    move.w      d0,d1
    lsl.w       #2,d1
    lea         GCRowTable,a0
    move.l      (a0,d1.w),d1
    lea         DisplayScreen+GC_DUCK_DEST_X_OFF,a1
    adda.l      d1,a1               ; a1 = dest plane 1 at CurrY

    WAITBLIT
    move.l      #$09F00000,BLTCON0(a6) ; D=A, no shift
    move.l      #-1,BLTAFWM(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #GC_DUCK_DMOD,BLTDMOD(a6)
    move.l      #NonDisplayScreen,d1 ; staged in Chip RAM
    moveq       #GC_DUCK_PLANES-1,d7
.duck_draw:
    WAITBLIT
    move.l      d1,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(GC_DUCK_H<<6)|GC_DUCK_W_WORDS,BLTSIZE(a6)
    add.l       #GC_DUCK_PLANE_SIZE,d1
    add.l       #LOADING_WIDTH_BYTE,a1
    dbra        d7,.duck_draw

    WAITBLIT                        ; ensure duckling is 100% drawn before anything else

.duck_no_move:
    bsr         SetRasterLogicColor ; VBlank duck blit complete -> switch from Yellow to Green/Red

    ;--------------------------------------------------------------------------
    ; 2. Starfield Updates (Plane 0)
    ;    Now erase previous stars, move coordinates, and draw new stars.
    ;--------------------------------------------------------------------------
    bsr         GCEraseStars
    bsr         GCMoveStars
    bsr         GCDrawStars

    rts


;==============================================================================
; GCEraseStars  -  Erase all 64 stars from Plane 0 at current coordinates
;
; Clears each star's footprint with AND.B ~(mask) so overlapping stars
; and background are preserved. Uses GCRowTable (no 68000 mulu).
;==============================================================================

GCEraseStars:
    lea         GCStarX(a5),a0
    lea         GCStarY(a5),a1
    lea         DisplayScreen,a3
    lea         GCRowTable,a4

    ; Loop A: stars 0-23 (1x1 pixel)
    moveq       #24-1,d7
.e1_loop:
    move.w      (a0)+,d0
    move.w      (a1)+,d1

    cmp.w       #GC_STAR_MAX_X,d0
    bhi.s       .skip_e1
    cmp.w       #GC_STAR_MAX_Y,d1
    bhi.s       .skip_e1
    cmp.w       #GC_STAR_MIN_Y,d1
    blo.s       .skip_e1

    move.w      d0,d2
    and.w       #7,d2
    moveq       #0,d3
    move.b      #$80,d3
    lsr.b       d2,d3
    not.b       d3

    lsr.w       #3,d0
    lsl.w       #2,d1
    movea.l     (a4,d1.w),a2
    adda.l      a3,a2
    adda.w      d0,a2

    and.b       d3,(a2)

.skip_e1:
    dbra        d7,.e1_loop

    ; Loop B: stars 24-47 (2x2 pixels)
    moveq       #24-1,d7
.e2_loop:
    move.w      (a0)+,d0
    move.w      (a1)+,d1

    cmp.w       #GC_STAR_MAX_X-1,d0
    bhi.s       .skip_e2
    cmp.w       #GC_STAR_MAX_Y,d1
    bhi.s       .skip_e2
    cmp.w       #GC_STAR_MIN_Y,d1
    blo.s       .skip_e2

    move.w      d0,d2
    and.w       #7,d2
    move.w      #$C000,d3
    lsr.w       d2,d3
    move.w      d3,d4
    lsr.w       #8,d4
    not.b       d4
    not.b       d3

    lsr.w       #3,d0
    lsl.w       #2,d1
    movea.l     (a4,d1.w),a2
    adda.l      a3,a2
    adda.w      d0,a2

    and.b       d4,(a2)
    and.b       d3,1(a2)
    and.b       d4,LOADING_ROW_BYTES(a2)
    and.b       d3,LOADING_ROW_BYTES+1(a2)

.skip_e2:
    dbra        d7,.e2_loop

    ; Loop C: stars 48-63 (3x1 streak)
    moveq       #16-1,d7
.e3_loop:
    move.w      (a0)+,d0
    move.w      (a1)+,d1

    cmp.w       #GC_STAR_MAX_X-2,d0
    bhi.s       .skip_e3
    cmp.w       #GC_STAR_MAX_Y,d1
    bhi.s       .skip_e3
    cmp.w       #GC_STAR_MIN_Y,d1
    blo.s       .skip_e3

    move.w      d0,d2
    and.w       #7,d2
    move.w      #$E000,d3
    lsr.w       d2,d3
    move.w      d3,d4
    lsr.w       #8,d4
    not.b       d4
    not.b       d3

    lsr.w       #3,d0
    lsl.w       #2,d1
    movea.l     (a4,d1.w),a2
    adda.l      a3,a2
    adda.w      d0,a2

    and.b       d4,(a2)
    and.b       d3,1(a2)

.skip_e3:
    dbra        d7,.e3_loop
    rts


;==============================================================================
; GCDrawStars  -  Draw all 64 stars into Plane 0 at new coordinates
;
; Uses GCRowTable for maximum speed (no 68000 mulu).
;==============================================================================

GCDrawStars:
    move.w      GCFrameTick(a5),d5
    and.w       #7,d5

    lea         GCStarX(a5),a0
    lea         GCStarY(a5),a1
    lea         DisplayScreen,a3
    lea         GCRowTable,a4

    ; Loop A: stars 0-23 (1x1 pixel with twinkling)
    moveq       #24-1,d7
.d1_loop:
    move.w      (a0)+,d0
    move.w      (a1)+,d1

    cmp.w       #GC_STAR_MAX_X,d0
    bhi.s       .skip_d1
    cmp.w       #GC_STAR_MAX_Y,d1
    bhi.s       .skip_d1
    cmp.w       #GC_STAR_MIN_Y,d1
    blo.s       .skip_d1

    move.w      d1,d6
    and.w       #7,d6
    cmp.w       d5,d6
    beq.s       .skip_d1            ; twinkle skip

    move.w      d0,d2
    and.w       #7,d2
    moveq       #0,d3
    move.b      #$80,d3
    lsr.b       d2,d3

    lsr.w       #3,d0
    lsl.w       #2,d1
    movea.l     (a4,d1.w),a2
    adda.l      a3,a2
    adda.w      d0,a2

    or.b        d3,(a2)

.skip_d1:
    dbra        d7,.d1_loop

    ; Loop B: stars 24-47 (2x2 pixels)
    moveq       #24-1,d7
.d2_loop:
    move.w      (a0)+,d0
    move.w      (a1)+,d1

    cmp.w       #GC_STAR_MAX_X-1,d0
    bhi.s       .skip_d2
    cmp.w       #GC_STAR_MAX_Y,d1
    bhi.s       .skip_d2
    cmp.w       #GC_STAR_MIN_Y,d1
    blo.s       .skip_d2

    move.w      d0,d2
    and.w       #7,d2
    move.w      #$C000,d3
    lsr.w       d2,d3
    move.w      d3,d4
    lsr.w       #8,d4

    lsr.w       #3,d0
    lsl.w       #2,d1
    movea.l     (a4,d1.w),a2
    adda.l      a3,a2
    adda.w      d0,a2

    or.b        d4,(a2)
    or.b        d3,1(a2)
    or.b        d4,LOADING_ROW_BYTES(a2)
    or.b        d3,LOADING_ROW_BYTES+1(a2)

.skip_d2:
    dbra        d7,.d2_loop

    ; Loop C: stars 48-63 (3x1 streak)
    moveq       #16-1,d7
.d3_loop:
    move.w      (a0)+,d0
    move.w      (a1)+,d1

    cmp.w       #GC_STAR_MAX_X-2,d0
    bhi.s       .skip_d3
    cmp.w       #GC_STAR_MAX_Y,d1
    bhi.s       .skip_d3
    cmp.w       #GC_STAR_MIN_Y,d1
    blo.s       .skip_d3

    move.w      d0,d2
    and.w       #7,d2
    move.w      #$E000,d3
    lsr.w       d2,d3
    move.w      d3,d4
    lsr.w       #8,d4

    lsr.w       #3,d0
    lsl.w       #2,d1
    movea.l     (a4,d1.w),a2
    adda.l      a3,a2
    adda.w      d0,a2

    or.b        d4,(a2)
    or.b        d3,1(a2)

.skip_d3:
    dbra        d7,.d3_loop
    rts


;==============================================================================
; GCRowTable  -  Precalculated 32-bit row byte offsets (Y * LOADING_ROW_BYTES)
;==============================================================================

                even
GCRowTable:
row_idx set 0
    rept LOADING_HEIGHT
    dc.l row_idx*LOADING_ROW_BYTES
row_idx set row_idx+1
    endr
