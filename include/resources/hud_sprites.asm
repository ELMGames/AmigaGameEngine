;==============================================================================
; AMIGA GAME ENGINE
; hud_sprites.asm  -  Hardware Sprite HUD (Lives, Oxygen Gauge, Air Bubbles)
;==============================================================================
;
; Channel allocation:
;   SPR0    Player Lives Badge (solo, 16px wide, 9 scanlines, COLOR17-19)
;   SPR1    Free (NullSprite)
;   SPR2-3  Free (NullSprite / reserved for Tower Minimap)
;   SPR4    Oxygen / Lung Gauge (solo, 16px wide, 7 scanlines, COLOR25-27)
;   SPR5    Free (NullSprite)
;   SPR6    Dynamic In-World Air Bubble (solo, 16x8 pixels, COLOR29-31)
;   SPR7    Free (NullSprite)
;
; Zero Blitter / CPU raster overhead:
;   - Lives and Oxygen sprites are screen-pinned (fixed HSTART/VSTART).
;   - Frame updates swap the 32-bit pointer in cpSprites (2 memory writes).
;   - Bubble sprite updates position headers dynamically each frame.
;
;==============================================================================

    section    main,code

;==============================================================================
; InitHUDSprites  -  Initialize sprite headers and palette for HUD
;
; Computes hardware sprite control words based on PAL/NTSC vertical origin
; (SpriteYOffset(a5)) and patches bubble colours in cpPal.
;
; In: a5 = Variables base, a6 = CUSTOM ($dff000)
; Preserves: a5, a6
; Destroys: d0-d5, a0-a2
;==============================================================================

InitHUDSprites:
    ; -------------------------------------------------------------------------
    ; 1. Setup Lives Sprites (SPR0): Screen X=36, Y=4, Height=9
    ; -------------------------------------------------------------------------
    move.w      SpriteYOffset(a5),d0
    addq.w      #4,d0                   ; d0 = VSTART (e.g. $30 PAL, $20 NTSC)
    move.w      d0,d1
    add.w       #9,d1                   ; d1 = VSTOP

    ; HSTART = 36 + WINDOW_X_START = 36 + $81 = 165 ($A5)
    ; SPRxPOS: bits 15:8 = VSTART[7:0], bits 7:0 = HSTART[8:1]
    ; SPRxCTL: bits 15:8 = VSTOP[7:0],  bit 0    = HSTART[0]
    move.w      #36+WINDOW_X_START,d2   ; d2 = HSTART ($A5)
    move.w      d0,d3
    andi.w      #$00ff,d3
    lsl.w       #8,d3
    move.w      d2,d4
    lsr.w       #1,d4                   ; d4 = HSTART[8:1] ($52)
    andi.w      #$00ff,d4
    or.w        d4,d3                   ; d3 = SPRxPOS

    move.w      d1,d4
    andi.w      #$00ff,d4
    lsl.w       #8,d4
    move.w      d2,d5
    andi.w      #1,d5                   ; d5 = HSTART[0] (1)
    or.w        d5,d4                   ; d4 = SPRxCTL

    ; Patch all 4 Lives frames (SpriteLives_0 .. SpriteLives_3)
    lea         SpriteLives_0,a0
    move.w      d3,(a0)
    move.w      d4,2(a0)
    lea         SpriteLives_1,a0
    move.w      d3,(a0)
    move.w      d4,2(a0)
    lea         SpriteLives_2,a0
    move.w      d3,(a0)
    move.w      d4,2(a0)
    lea         SpriteLives_3,a0
    move.w      d3,(a0)
    move.w      d4,2(a0)

    ; -------------------------------------------------------------------------
    ; 2. Setup Oxygen Gauge (SPR4): Screen X=16, Y=4, Height=28
    ; -------------------------------------------------------------------------
    move.w      SpriteYOffset(a5),d0
    addq.w      #4,d0                   ; d0 = VSTART
    move.w      d0,d1
    add.w       #28,d1                  ; d1 = VSTOP (28 rows)

    ; HSTART = 16 + WINDOW_X_START = 16 + $81 = 145 ($91)
    move.w      #16+WINDOW_X_START,d2   ; d2 = HSTART ($91)
    move.w      d0,d3
    andi.w      #$00ff,d3
    lsl.w       #8,d3
    move.w      d2,d4
    lsr.w       #1,d4                   ; d4 = HSTART[8:1] ($48)
    andi.w      #$00ff,d4
    or.w        d4,d3                   ; d3 = SPRxPOS

    move.w      d1,d4
    andi.w      #$00ff,d4
    lsl.w       #8,d4
    move.w      d2,d5
    andi.w      #1,d5                   ; d5 = HSTART[0] (1)
    or.w        d5,d4                   ; d4 = SPRxCTL

    ; Patch SpriteOxy header
    lea         SpriteOxy,a0
    move.w      d3,(a0)
    move.w      d4,2(a0)

    ; Point SPR4PTH/L permanently to SpriteOxy
    move.l      #SpriteOxy,d0
    lea         cpSprites+32,a0
    swap        d0
    move.w      d0,2(a0)
    swap        d0
    move.w      d0,6(a0)

    ; -------------------------------------------------------------------------
    ; 3. Setup Palette in cpPal: SPR4 (COLOR25-27) & SPR6 (COLOR29-31)
    ; -------------------------------------------------------------------------
    ; SPR4 Oxygen Gauge colours:
    move.w      #$0FFF,cpPal+(25*4)+2   ; Color 1: Crisp White (OXY text, borders)
    move.w      #$02DF,cpPal+(26*4)+2   ; Color 2: Neon Cyan (Oxygen liquid)
    move.w      #$0024,cpPal+(27*4)+2   ; Color 3: Deep Navy (Empty chamber)

    ; SPR6 Bubble colours:
    move.w      #BUBBLE_COLOR_OUTLINE,cpPal+(29*4)+2    ; dark blue-green
    move.w      #BUBBLE_COLOR_BODY,cpPal+(30*4)+2       ; mid blue
    move.w      #BUBBLE_COLOR_HILIGHT,cpPal+(31*4)+2    ; light blue

    ; Clear bubble state
    clr.w       BubbleActive(a5)
    move.w      #30,BubbleTimer(a5)

    ; Initial HUD update
    bsr         UpdateHUDSprites
    rts


;==============================================================================
; UpdateHUDSprites  -  Update Hardware Sprite Copper Pointers each frame
;
; Called from GameRun in gamestatus.asm.
;
; In: a5 = Variables base
; Preserves: a5, a6
; Destroys: d0-d3, a0-a2
;==============================================================================

UpdateHUDSprites:
    ; -------------------------------------------------------------------------
    ; 1. Update Player Lives (SPR0 at cpSprites + 0)
    ; -------------------------------------------------------------------------
    move.w      PlayerLives(a5),d0
    bpl.s       .lives_not_neg
    moveq       #0,d0
.lives_not_neg:
    cmp.w       #3,d0
    ble.s       .lives_clamp_ok
    moveq       #3,d0
.lives_clamp_ok:
    lsl.w       #2,d0                   ; d0 = index * 4
    lea         SpriteLives_Table,a0
    move.l      (a0,d0.w),d0            ; d0 = pointer to SpriteLives_N

    ; Write 32-bit address into SPR0PTH/L (cpSprites + 0)
    lea         cpSprites,a0
    swap        d0
    move.w      d0,2(a0)
    swap        d0
    move.w      d0,6(a0)

    ; -------------------------------------------------------------------------
    ; 2. Update Oxygen Bar (SPR4: 16x28 Vertical Gauge, 20 Fill Rows)
    ; -------------------------------------------------------------------------
    move.w      PlayerOxygen(a5),d0     ; 0..OXYGEN_MAX (400)
    bpl.s       .oxy_not_neg
    moveq       #0,d0
.oxy_not_neg:
    cmp.w       #OXYGEN_MAX,d0
    ble.s       .oxy_clamp_ok
    move.w      #OXYGEN_MAX,d0
.oxy_clamp_ok:

    ; FillRows = PlayerOxygen / 20 (0..20 scanlines)
    ext.l       d0
    divu.w      #20,d0                  ; d0.w = 0..20
    cmp.w       #20,d0
    ble.s       .rows_ok
    moveq       #20,d0
.rows_ok:

    ; Rows 7..26: update 20 liquid rows in SpriteOxy (Word 0 at SpriteOxy+32)
    lea         SpriteOxy+32,a0         ; a0 -> Word 0 of Row 7
    move.w      #20,d1
    sub.w       d0,d1                   ; d1 = 20 - FillRows = empty rows count
    beq.s       .no_empty_rows

    subq.w      #1,d1
.fill_empty:
    move.w      #$3FF0,(a0)             ; empty chamber (Color 3: Deep Navy)
    addq.l      #4,a0
    dbra        d1,.fill_empty

.no_empty_rows:
    tst.w       d0
    beq.s       .no_liquid_rows

    subq.w      #1,d0
.fill_liquid:
    move.w      #$2010,(a0)             ; liquid fill (Color 2: Neon Cyan)
    addq.l      #4,a0
    dbra        d0,.fill_liquid

.no_liquid_rows:

    ; Flash liquid colour if critical (<= OXYGEN_CRITICAL)
    cmp.w       #OXYGEN_CRITICAL,PlayerOxygen(a5)
    bgt.s       .oxy_normal_color
    move.w      TickCounter(a5),d1
    btst        #2,d1                   ; flash every 4 frames (~12Hz)
    beq.s       .oxy_normal_color
    ; Flash color: Bright Warning Red
    move.w      #$0F30,cpPal+(26*4)+2
    bra.s       .oxy_color_done
.oxy_normal_color:
    move.w      #$02DF,cpPal+(26*4)+2   ; Neon Cyan
.oxy_color_done:

    ; -------------------------------------------------------------------------
    ; 3. Update Air Bubble (SPR6 at cpSprites + 48)
    ; -------------------------------------------------------------------------
    bsr         UpdateAirBubble
    rts


;==============================================================================
; UpdateAirBubble  -  Animate and render dynamic submerged air bubble on SPR6
;==============================================================================

UpdateAirBubble:
    tst.w       PlayerSubmerged(a5)
    beq         .check_floating_bubble  ; not submerged: let existing bubble finish rising

    ; --- Player is submerged: tick spawn timer ---
    tst.w       BubbleActive(a5)
    bne.s       .bubble_rise            ; already rising

    subq.w      #1,BubbleTimer(a5)
    bgt         .hide_bubble

    ; Spawn new bubble at player head
    move.w      #1,BubbleActive(a5)
    move.w      #50,BubbleTimer(a5)     ; reset spawn timer (~1.0s)

    lea         Player(a5),a4
    ; World X = Player_X * 16 + Player_XDec + 4
    move.w      Player_X(a4),d0
    lsl.w       #4,d0
    add.w       Player_XDec(a4),d0
    addq.w      #4,d0
    move.w      d0,BubbleWorldX(a5)

    ; World Y = Player_Y * 16 + Player_YDec - 8 + PLAYER_HEAD_Y_OFFSET
    move.w      Player_Y(a4),d0
    lsl.w       #4,d0
    add.w       Player_YDec(a4),d0
    subq.w      #8,d0
    add.w       #PLAYER_HEAD_Y_OFFSET,d0
    move.w      d0,BubbleWorldY(a5)

.bubble_rise:
    ; Ascend 2 pixels per frame
    subq.w      #2,BubbleWorldY(a5)

    ; Check if bubble reached water surface
    move.w      WaterPixelY(a5),d0
    bmi         .pop_bubble
    cmp.w       BubbleWorldY(a5),d0
    bge         .pop_bubble             ; WaterPixelY >= BubbleWorldY -> breached surface!

    ; Check if within camera viewport
    move.w      BubbleWorldY(a5),d0
    sub.w       TilemapCameraY(a5),d0   ; d0 = Screen Y
    blt         .pop_bubble             ; scrolled off top
    cmp.w       #200,d0
    bgt         .pop_bubble             ; scrolled off bottom

    ; --- Bubble is visible: compute raster coordinates ---
    ; Screen X:
    move.w      BubbleWorldX(a5),d1
    ; Add subtle horizontal sine wobble: (BubbleWorldY & 7) - 3
    move.w      BubbleWorldY(a5),d2
    andi.w      #7,d2
    subq.w      #3,d2
    add.w       d2,d1

    ; Screen Y:
    move.w      d0,d2                   ; d2 = Screen Y

    ; Raster VSTART / VSTOP:
    add.w       SpriteYOffset(a5),d2    ; d2 = VSTART
    move.w      d2,d3
    addq.w      #8,d3                   ; d3 = VSTOP (8 rows)

    ; Raster HSTART:
    add.w       #WINDOW_X_START,d1      ; d1 = HSTART

    ; Build SPRxPOS and SPRxCTL
    move.w      d2,d0
    andi.w      #$00ff,d0
    lsl.w       #8,d0
    move.w      d1,d4
    lsr.w       #1,d4                   ; d4 = HSTART[8:1] (bits 7:0)
    andi.w      #$00ff,d4
    or.w        d4,d0                   ; d0 = SPRxPOS

    move.w      d3,d4
    andi.w      #$00ff,d4
    lsl.w       #8,d4
    move.w      d1,d5
    andi.w      #1,d5                   ; d5 = HSTART[0]
    or.w        d5,d4                   ; d4 = SPRxCTL

    ; Set SV8 (VSTART[8] -> bit 2) and EV8 (VSTOP[8] -> bit 1)
    btst        #8,d2
    beq.s       .no_sv8
    bset        #2,d4
.no_sv8:
    btst        #8,d3
    beq.s       .no_ev8
    bset        #1,d4
.no_ev8:

    ; Write header to SpriteBubble
    lea         SpriteBubble,a0
    move.w      d0,(a0)
    move.w      d4,2(a0)

    ; Point SPR6PTH/L to SpriteBubble
    move.l      #SpriteBubble,d0
    lea         cpSprites+48,a0
    swap        d0
    move.w      d0,2(a0)
    swap        d0
    move.w      d0,6(a0)
    rts

.check_floating_bubble:
    tst.w       BubbleActive(a5)
    bne         .bubble_rise            ; finish rising even if player surfaced
    bra.s       .hide_bubble

.pop_bubble:
    clr.w       BubbleActive(a5)

.hide_bubble:
    ; Point SPR6PTH/L to NullSprite
    move.l      #NullSprite,d0
    lea         cpSprites+48,a0
    swap        d0
    move.w      d0,2(a0)
    swap        d0
    move.w      d0,6(a0)
    rts


;==============================================================================
; Chip RAM Sprite Data Section
;==============================================================================

    section    data_chip,data_c

; -----------------------------------------------------------------------------
; Player Lives Sprites (SPR0, 16px wide x 9 scanlines)
;
; Colors:
;   Color 1 (Plane 0=1, Plane 1=0): Outline (Black $0000 / $0043)
;   Color 2 (Plane 0=0, Plane 1=1): Body (Peach $0FA7)
;   Color 3 (Plane 0=1, Plane 1=1): White Visor & Digit ($0FFF)
; -----------------------------------------------------------------------------

SpriteLives_0:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $7800,$0000
    dc.w    $843e,$783e
    dc.w    $fc22,$7822
    dc.w    $fc22,$7822
    dc.w    $8422,$7822
    dc.w    $783e,$003e
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_1:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $7800,$0000
    dc.w    $8408,$7808
    dc.w    $fc18,$7818
    dc.w    $fc08,$7808
    dc.w    $8408,$7808
    dc.w    $783e,$003e
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_2:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $7800,$0000
    dc.w    $843e,$783e
    dc.w    $fc02,$7802
    dc.w    $fc3e,$783e
    dc.w    $8420,$7820
    dc.w    $783e,$003e
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_3:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $7800,$0000
    dc.w    $843e,$783e
    dc.w    $fc02,$7802
    dc.w    $fc1c,$781c
    dc.w    $8402,$7802
    dc.w    $783e,$003e
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_Table:
    dc.l    SpriteLives_0
    dc.l    SpriteLives_1
    dc.l    SpriteLives_2
    dc.l    SpriteLives_3


; -----------------------------------------------------------------------------
; Oxygen Gauge Sprite (SPR4, 16px wide x 28 scanlines)
;
; Colors:
;   Color 1 (Plane 0=1, Plane 1=0): White Text & Vial Borders ($0FFF)
;   Color 2 (Plane 0=0, Plane 1=1): Neon Cyan Oxygen Liquid ($02DF)
;   Color 3 (Plane 0=1, Plane 1=1): Deep Navy Empty Chamber ($0024)
; -----------------------------------------------------------------------------

SpriteOxy:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    ; Rows 0-4: 'O X Y' text (3x5 font, Color 1 White)
    dc.w    $3AA8,$0000
    dc.w    $2AA8,$0000
    dc.w    $2910,$0000
    dc.w    $2A90,$0000
    dc.w    $3A90,$0000
    ; Row 5: Blank separator gap
    dc.w    $0000,$0000
    ; Row 6: Vial top cap (shifted 1px left: cols 2..11)
    dc.w    $3FF0,$0000
    ; Rows 7-26: 20 liquid fill rows (Plane 1 statically $1FE0, Plane 0 updated dynamically)
    rept    20
    dc.w    $2010,$1FE0
    endr
    ; Row 27: Vial bottom cap
    dc.w    $3FF0,$0000
    dc.w    0,0                         ; terminator


; -----------------------------------------------------------------------------
; Dynamic Air Bubble Sprite (SPR6, 16px wide x 8 scanlines)
;
; Colors:
;   Color 1 (Plane 0=1, Plane 1=0): Outline (Dark Blue-Green $0046)
;   Color 2 (Plane 0=0, Plane 1=1): Body Fill (Mid Blue $068C)
;   Color 3 (Plane 0=1, Plane 1=1): Highlight Glint (Bright Light Blue $0BDF)
; -----------------------------------------------------------------------------

SpriteBubble:
    dc.w    0,0                         ; header (updated dynamically)
    dc.w    $0f00,$0000
    dc.w    $1f80,$0600
    dc.w    $3980,$0e00
    dc.w    $2080,$1f00
    dc.w    $2080,$1f00
    dc.w    $1980,$0600
    dc.w    $0f00,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

    section    main,code

