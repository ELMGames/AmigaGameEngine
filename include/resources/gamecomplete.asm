
;==============================================================================
; AMIGA GAME ENGINE
; gamecomplete.asm  -  Game Complete Screen (states 15 / 16)
;==============================================================================
;
; Displayed when the player completes level 100 (LevelId = 99).
; LevelCompleteSetup redirects to GameCompleteSetup before its normal flow.
;
; Screen layout (336x200 pixels, 5-plane interleaved, same geometry as cpTitle):
;
;   Y=5, bX=12   "YOU HAVE COMPLETED" (18 chars, green)
;   Y= 40..95      AC title logo (TitleLogoRaw, 256x56, 3 bitplanes) blitted
;                  into screen planes 1-3; colours patched from TitleLogoPal
;                  (plane 0 stays free for the starfield)
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
;   LFSR Y init: & $FF + bhi re-roll to 0..184; avoids the gap at Y=64..127
;   that a & $BF mask would create by permanently zeroing bit 6.
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
;   GameCompleteSetup  -- one-shot init (GameStatus = GAME_COMPLETE_SETUP = 15)
;   GameCompleteRun    -- per-frame handler (GameStatus = GAME_COMPLETE_RUN = 16)
;
; Register convention: a5 = Variables base, a6 = $dff000 (CUSTOM).
;==============================================================================

; Screen-address offsets into DisplayScreen (LOADING_ROW_BYTES = 200 per row)
; 40 characters across: byte_x = (40 - strlen) / 2
GC_OFF_COMPLETE  = 15*LOADING_ROW_BYTES+7    ; "YOU COMPLETED ALL LEVELS!" (26 chars -> X=7)
GC_OFF_CONGRATS  = 145*LOADING_ROW_BYTES+12   ; "CONGRATULATIONS!" (16 chars -> X=12)
GC_OFF_THANKS    = 175*LOADING_ROW_BYTES+11   ; "THANKS FOR PLAYING" (18 chars -> X=11)

;------------------------------------------------------------------------------
; Logo — reuses the AC title logo (TitleLogoRaw/TitleLogoPal, main.asm
; data_chip; geometry in TITLE_LOGO_* from titlescreen.asm) but shifted UP one
; screen plane: the 3 source planes land in screen planes 1-3 because plane 0
; belongs to the starfield (cleared and redrawn every frame by GameCompleteRun).
;
; Colour consequence: logo pixel value v (1-7) displays at colour index v*2;
; a star pixel behind the logo adds bit 0 giving index v*2+1.  GameCompleteSetup
; patches BOTH entries of each pair with TitleLogoPal colour v, so the logo
; occludes the starfield.  Text planes (BPL4+BPL5, colours 24/28/31) do not
; overlap the logo rows.
;------------------------------------------------------------------------------
GC_LOGO_OFF      = TITLE_LOGO_OFF+LOADING_WIDTH_BYTE   ; plane-1 start of logo


;==============================================================================
; GameCompleteSetup  -  One-shot init for the game complete screen (state 15)
;
; Sequence:
;   1. Stop music; clear DisplayScreen.
;   2. Patch cpGCPlanes + cpGCSprites; install cpGameComplete copper list.
;   3. Patch logo colours into cpGCPal; blit TitleLogoRaw into planes 1-3.
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
    ;     185 entries (Y=0..GC_STAR_MAX_Y): each scanline gets a random COLOR01
    ;     so stars appear in white, yellow, red or blue depending on their Y position.
    lea         cpGCDynColors,a0
    lea         .gcColorTab(pc),a1
    move.w      #GC_STAR_RAND_INIT,d5
    moveq       #0,d6
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
    addq.w      #1,d6
    cmp.w       #GC_STAR_MAX_Y,d6
    ble.s       .gc_cop_loop
    move.l      #$FFFFFFFE,(a0)+    ; COPPER_HALT
    move.l      #$FFFFFFFE,(a0)+    ; COPPER_HALT (belt-and-braces)

    ; 2d. Install copper list and re-enable DMA
    move.l      #cpGameComplete,COP1LC(a6)
    move.w      #0,COPJMP1(a6)
  ;  move.w      #BASE_DMA,DMACON(a6)

    ; 3a. Patch the logo colours into cpGCPal from TitleLogoPal (skip entry 0:
    ;     transparent).  Each logo colour v fills the pair COLOR(2v)/COLOR(2v+1)
    ;     — see the GC_LOGO_OFF comment block for why.
    ;     cpGCPal entry layout: dc.w COLORnn,value — value word at entry*4+2.
    lea         TitleLogoPal+2,a0       ; -> logo colour 1
    lea         cpGCPal+2*4+2,a1        ; -> COLOR02 value word
    moveq       #7-1,d7
.lpal
    move.w      (a0)+,d0
    move.w      d0,(a1)                 ; COLOR(2v)   = logo colour v
    move.w      d0,4(a1)                ; COLOR(2v+1) = same (star behind logo)
    addq.l      #8,a1                   ; next even/odd colour pair
    dbra        d7,.lpal

    ; 3b. Blit the 3 logo source planes into screen planes 1-3.  Source planes
    ;     are consecutive (TITLE_LOGO_PLANE_SIZE bytes each); screen planes are
    ;     interleaved LOADING_WIDTH_BYTE apart.
    WAITBLIT
    move.l      #$09F00000,BLTCON0(a6)
    move.l      #-1,BLTAFWM(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #TITLE_LOGO_DMOD,BLTDMOD(a6)
    move.l      #TitleLogoRaw,d0        ; d0 = current source plane
    lea         DisplayScreen+GC_LOGO_OFF,a1   ; a1 = current dest plane (1)
    moveq       #TITLE_LOGO_PLANES-1,d7
.lblit
    WAITBLIT
    move.l      d0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(TITLE_LOGO_H<<6)|TITLE_LOGO_W_WORDS,BLTSIZE(a6)
    add.l       #TITLE_LOGO_PLANE_SIZE,d0      ; next source plane
    add.l       #LOADING_WIDTH_BYTE,a1         ; next interleaved screen plane
    dbra        d7,.lblit

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
; Each frame:
;   1. Read controls; FIRE or Return -> AudioStopMod + TITLE_SETUP + return.
;   2. bsr GCMoveStars -- advance all star positions one frame.
;   3. Blitter: zero-fill plane 0 (BLTCON0=$0100, BLTDMOD=SCREEN_MOD=168).
;   4. WAITBLIT; increment GCFrameTick; compute twinkle phase d5 = tick & 7.
;   5. Three CPU draw loops, a0/a1 advance continuously across all three:
;        Loop A  stars  0-23  1x1 pixel   skip if (Y&7)==d5 (twinkle)  max X=335
;        Loop B  stars 24-47  2x2 pixels  always drawn                  max X=334
;        Loop C  stars 48-63  3x1 h-streak always drawn                 max X=333
;
; Register usage (no PUSHALL):
;   d0  scratch (X, mask high byte)
;   d1  scratch (Y, row byte offset)
;   d2  bit-shift count (X & 7)
;   d3  mask word / low byte
;   d4  mask high byte
;   d5  twinkle phase (GCFrameTick & 7) in draw section
;   d6  twinkle scratch (Y & 7) in draw loop A
;   d7  dbra counter
;   a0  -> GCStarX[i]
;   a1  -> GCStarY[i]
;   a2  plane-0 target byte
;   a3  -> GCFrameTick
;==============================================================================

GameCompleteRun:
    bsr         UpdateControls

    move.b      ControlsTrigger(a5),d0
    btst        #CONTROLB_FIRE,d0
    bne         .quit

    lea         Keys,a0
    tst.b       KEY_RETURN(a0)
    beq         .no_quit
.quit
    lea         Keys,a0
    clr.b       KEY_RETURN(a0)
    bsr         AudioStopMod
    move.w      #TITLE_SETUP,GameStatus(a5)
    rts
.no_quit

    bsr         GCMoveStars

    ;--------------------------------------------------------------------------
    ; Clear plane 0
    ;--------------------------------------------------------------------------
    WAITBLIT
    move.w      #$0100,BLTCON0(a6)
    clr.w       BLTCON1(a6)
    move.w      #LOADING_MOD,BLTDMOD(a6)
    lea         DisplayScreen,a0
    move.l      a0,BLTDPT(a6)
    move.w      #(LOADING_HEIGHT<<6)|(LOADING_WIDTH_BYTE/2),BLTSIZE(a6)

    ;--------------------------------------------------------------------------
    ; Advance frame tick; compute twinkle phase d5 = GCFrameTick & 7.
    ; Slow stars (loop A) are skipped when their (Y & 7) matches d5.
    ;--------------------------------------------------------------------------
    lea         GCFrameTick(a5),a3
    addq.w      #1,(a3)
    move.w      (a3),d5
    and.w       #7,d5

    WAITBLIT
    lea         GCStarX(a5),a0
    lea         GCStarY(a5),a1

    ;----------------------------------------------------------
    ; Loop A: stars 0-23  --  1x1 pixel with twinkling
    ;   mask = $80 >> (X & 7)
    ;   Twinkle: skip when (Y & 7) == d5 (1 frame in 8 per star)
    ;   max X = GC_STAR_MAX_X (335)
    ;----------------------------------------------------------
    moveq       #24-1,d7

.draw1_loop
    move.w      (a0)+,d0
    move.w      (a1)+,d1

    cmp.w       #GC_STAR_MAX_X,d0
    bhi.s       .skip1
    cmp.w       #GC_STAR_MAX_Y,d1
    bhi.s       .skip1

    move.w      d1,d6
    and.w       #7,d6
    cmp.w       d5,d6
    beq.s       .skip1

    move.w      d0,d2
    and.w       #7,d2
    moveq       #0,d3
    move.b      #$80,d3
    lsr.b       d2,d3

    lsr.w       #3,d0
    mulu        #LOADING_ROW_BYTES,d1
    lea         DisplayScreen,a2
    add.l       d1,a2
    add.w       d0,a2

    or.b        d3,(a2)

.skip1
    dbra        d7,.draw1_loop

    ;----------------------------------------------------------
    ; Loop B: stars 24-47  --  2x2 pixels
    ;   mask_word = $C000 >> (X & 7); 2 rows x up to 2 bytes
    ;   max X = GC_STAR_MAX_X-1 (334)
    ;----------------------------------------------------------
    moveq       #24-1,d7

.draw2_loop
    move.w      (a0)+,d0
    move.w      (a1)+,d1

    cmp.w       #GC_STAR_MAX_X-1,d0
    bhi.s       .skip2
    cmp.w       #GC_STAR_MAX_Y,d1
    bhi.s       .skip2

    move.w      d0,d2
    and.w       #7,d2
    move.w      #$C000,d3
    lsr.w       d2,d3
    move.w      d3,d4
    lsr.w       #8,d4

    lsr.w       #3,d0
    mulu        #LOADING_ROW_BYTES,d1
    lea         DisplayScreen,a2
    add.l       d1,a2
    add.w       d0,a2

    or.b        d4,(a2)
    or.b        d3,1(a2)
    or.b        d4,LOADING_ROW_BYTES(a2)
    or.b        d3,LOADING_ROW_BYTES+1(a2)

.skip2
    dbra        d7,.draw2_loop

    ;----------------------------------------------------------
    ; Loop C: stars 48-63  --  3x1 horizontal streak
    ;   mask_word = $E000 >> (X & 7); 1 row x up to 2 bytes
    ;   Single row: reads as motion blur, not a large blob.
    ;   max X = GC_STAR_MAX_X-2 (333)
    ;----------------------------------------------------------
    moveq       #16-1,d7

.draw3_loop
    move.w      (a0)+,d0
    move.w      (a1)+,d1

    cmp.w       #GC_STAR_MAX_X-2,d0
    bhi.s       .skip3
    cmp.w       #GC_STAR_MAX_Y,d1
    bhi.s       .skip3

    move.w      d0,d2
    and.w       #7,d2
    move.w      #$E000,d3
    lsr.w       d2,d3
    move.w      d3,d4
    lsr.w       #8,d4

    lsr.w       #3,d0
    mulu        #LOADING_ROW_BYTES,d1
    lea         DisplayScreen,a2
    add.l       d1,a2
    add.w       d0,a2

    or.b        d4,(a2)
    or.b        d3,1(a2)

.skip3
    dbra        d7,.draw3_loop

    rts
