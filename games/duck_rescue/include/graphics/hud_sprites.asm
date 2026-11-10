;==============================================================================
; AMIGA GAME ENGINE
; hud_sprites.asm  -  Hardware Sprite HUD (Lives, Oxygen Gauge, Air Bubbles)
;==============================================================================
;
; Channel allocation:
;   SPR0    Player Lives Badge (solo, 16px wide, 9 scanlines, COLOR17-19)
;   SPR1    Free (NullSprite)
;   SPR2    Oxygen Kit Inventory Bottle (solo, 16px wide, 13 scanlines, COLOR21-23)
;   SPR3    Friends Remaining Badge (solo, 16px wide, 9 scanlines, COLOR21-23)
;   SPR4    Oxygen / Lung Gauge (solo, 16px wide, 28 scanlines, COLOR25-27)
;   SPR5    Free (NullSprite)
;   SPR6    Dynamic In-World Air Bubble (solo, 16x8 pixels, COLOR29-31)
;   SPR7    Free (NullSprite)
;
; Zero Blitter / CPU raster overhead:
;   - Lives, Oxygen Kit, Friends Badge, and Oxygen Gauge sprites are screen-pinned (fixed HSTART/VSTART).
;   - Frame updates swap the 32-bit pointer in cpSprites (2 memory writes).
;   - Bubble sprite updates position headers dynamically each frame.
;
;==============================================================================

    section    main,code

;==============================================================================
; InitHUDSprites  -  Initialize sprite headers and palette for HUD
;
; Amiga Hardware Sprite Control Header Structure:
; Each sprite data block begins with two 16-bit control words (4 bytes total):
;   Word 0 (SPRxPOS):
;     Bits 15:8 = VSTART[7:0]  (Vertical start raster line, low 8 bits)
;     Bits  7:0 = HSTART[8:1]  (Horizontal start pixel column, bits 8 downto 1)
;   Word 1 (SPRxCTL):
;     Bits 15:8 = VSTOP[7:0]   (Vertical stop raster line, low 8 bits)
;     Bit     7 = ATTACH       (0 = solo 3-color sprite; 1 = attached 15-color pair)
;     Bit     2 = VSTART[8]    (Vertical start line high bit 8)
;     Bit     1 = VSTOP[8]     (Vertical stop line high bit 8)
;     Bit     0 = HSTART[0]    (Horizontal start pixel bit 0)
;
; Zero-Overhead Copper Pointer Patching:
; The Copper list defines sprite channel pointers as pairs of 4-byte MOVE instructions:
;   dc.w  $0120+offset, HIGH_WORD    ; MOVE SPRxPTH, <high 16 bits>
;   dc.w  $0122+offset, LOW_WORD     ; MOVE SPRxPTL, <low 16 bits>
;
; Writing to cpSprites + offset:
;   - Address + 2 = HIGH_WORD operand of SPRxPTH
;   - Address + 6 = LOW_WORD operand of SPRxPTL
;
; This routine computes the fixed VSTART/VSTOP/HSTART control words for the HUD
; badge sprites, patches their headers, and initializes the Copper palette entries.
;
; In: a5 = Variables base, a6 = CUSTOM ($dff000)
; Preserves: a5, a6
; Destroys: d0-d5, a0-a2
;==============================================================================

InitHUDSprites:
    ; -------------------------------------------------------------------------
    ; 1. Setup Lives Sprites (SPR0): Screen X=36, Y=4, Height=9
    ; -------------------------------------------------------------------------
    ; VSTART is adjusted by SpriteYOffset(a5) for video standard ($2C PAL, $1C NTSC)
    move.w      SpriteYOffset(a5),d0
    addq.w      #4,d0                   ; d0 = VSTART
    move.w      d0,d1
    add.w       #9,d1                   ; d1 = VSTOP = VSTART + 9 lines

    ; HSTART = 36 + WINDOW_X_START = 36 + $81 = 165 ($A5)
    move.w      #36+WINDOW_X_START,d2   ; d2 = HSTART ($A5)
    move.w      d0,d3
    andi.w      #$00ff,d3
    lsl.w       #8,d3                   ; d3 = VSTART[7:0] << 8
    move.w      d2,d4
    lsr.w       #1,d4                   ; d4 = HSTART[8:1] ($52)
    andi.w      #$00ff,d4
    or.w        d4,d3                   ; d3 = SPRxPOS word

    move.w      d1,d4
    andi.w      #$00ff,d4
    lsl.w       #8,d4                   ; d4 = VSTOP[7:0] << 8
    move.w      d2,d5
    andi.w      #1,d5                   ; d5 = HSTART[0] (bit 0)
    or.w        d5,d4                   ; d4 = SPRxCTL word

    ; Patch all 12 pre-rendered lives badge frames (0..3 lives x 3 anim frames)
    move.w      d6,-(sp)
    lea         SpriteLives_Table,a1
    moveq       #12-1,d6
.patch_lives_loop:
    move.l      (a1)+,a0
    move.w      d3,(a0)
    move.w      d4,2(a0)
    dbra        d6,.patch_lives_loop
    move.w      (sp)+,d6

    ; -------------------------------------------------------------------------
    ; 1b. Setup Oxygen Kit Bottle Sprite (SPR2): Screen X=56, Y=2, Height=13
    ; -------------------------------------------------------------------------
    move.w      SpriteYOffset(a5),d0
    addq.w      #2,d0                   ; d0 = VSTART
    move.w      d0,d1
    add.w       #13,d1                  ; d1 = VSTOP (13 scanlines)

    ; HSTART = 56 + WINDOW_X_START = 56 + $81 = 185 ($B9)
    move.w      #56+WINDOW_X_START,d2   ; d2 = HSTART ($B9)
    move.w      d0,d3
    andi.w      #$00ff,d3
    lsl.w       #8,d3
    move.w      d2,d4
    lsr.w       #1,d4                   ; d4 = HSTART[8:1] ($5C)
    andi.w      #$00ff,d4
    or.w        d4,d3                   ; d3 = SPRxPOS

    move.w      d1,d4
    andi.w      #$00ff,d4
    lsl.w       #8,d4
    move.w      d2,d5
    andi.w      #1,d5                   ; d5 = HSTART[0] (1)
    or.w        d5,d4                   ; d4 = SPRxCTL

    ; Patch SpriteOxygenKit header
    lea         SpriteOxygenKit,a0
    move.w      d3,(a0)
    move.w      d4,2(a0)

    ; Default SPR2 to NullSprite (hidden until collected into player inventory)
    move.l      #NullSprite,d0
    lea         cpSprites+16,a0         ; SPR2 Copper pointer offset (channel 2 * 8 bytes = 16)
    swap        d0
    move.w      d0,2(a0)                ; SPR2PTH high word operand
    swap        d0
    move.w      d0,6(a0)                ; SPR2PTL low word operand

    ; -------------------------------------------------------------------------
    ; 1c. Setup Friends Remaining Badge Sprite (SPR3): Screen X=76, Y=4, Height=9
    ; -------------------------------------------------------------------------
    move.w      SpriteYOffset(a5),d0
    addq.w      #4,d0                   ; d0 = VSTART
    move.w      d0,d1
    add.w       #9,d1                   ; d1 = VSTOP (9 scanlines)

    ; HSTART = 76 + WINDOW_X_START = 76 + $81 = 205 ($CD)
    move.w      #76+WINDOW_X_START,d2   ; d2 = HSTART ($CD)
    move.w      d0,d3
    andi.w      #$00ff,d3
    lsl.w       #8,d3
    move.w      d2,d4
    lsr.w       #1,d4                   ; d4 = HSTART[8:1] ($66)
    andi.w      #$00ff,d4
    or.w        d4,d3                   ; d3 = SPRxPOS

    move.w      d1,d4
    andi.w      #$00ff,d4
    lsl.w       #8,d4
    move.w      d2,d5
    andi.w      #1,d5                   ; d5 = HSTART[0] (1)
    or.w        d5,d4                   ; d4 = SPRxCTL

    ; Patch all 17 pre-rendered Friends frames (SpriteFriends_0 .. SpriteFriends_16)
    move.w      d6,-(sp)
    lea         SpriteFriends_Table,a1
    moveq       #17-1,d6
.patch_friends_loop:
    move.l      (a1)+,a0
    move.w      d3,(a0)
    move.w      d4,2(a0)
    dbra        d6,.patch_friends_loop
    move.w      (sp)+,d6

    ; Default SPR3 to NullSprite (shown only when level has friends to rescue)
    move.l      #NullSprite,d0
    lea         cpSprites+24,a0         ; SPR3 Copper pointer offset (channel 3 * 8 bytes = 24)
    swap        d0
    move.w      d0,2(a0)                ; SPR3PTH
    swap        d0
    move.w      d0,6(a0)                ; SPR3PTL

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

    ; Default SPR4 to NullSprite (hidden on dry land, shown only when submerged/depleted)
    move.l      #NullSprite,d0
    lea         cpSprites+32,a0         ; SPR4 Copper pointer offset (channel 4 * 8 bytes = 32)
    swap        d0
    move.w      d0,2(a0)                ; SPR4PTH
    swap        d0
    move.w      d0,6(a0)                ; SPR4PTL

    ; -------------------------------------------------------------------------
    ; 3. Setup Palette in cpPal: SPR0, SPR2/3, SPR4 & SPR6
    ; -------------------------------------------------------------------------
    ; SPR0 Player Lives Heart colors (COLOR17..19):
    move.w      #$0601,cpPal+(17*4)+2   ; Color 1: Dark Maroon / Crimson Outline
    move.w      #$0F22,cpPal+(18*4)+2   ; Color 2: Vivid Arcade Red Fill
    move.w      #$0FFF,cpPal+(19*4)+2   ; Color 3: Crisp White Glint & Number

    ; SPR2/SPR3 Oxygen Kit & Duckling Friends Badge colors (COLOR21..23):
    move.w      #$0E71,cpPal+(21*4)+2   ; Color 1: Amber Orange Beak, Eye & Tank Trim
    move.w      #$0FD1,cpPal+(22*4)+2   ; Color 2: Golden Yellow Duckling & Tank Cylinder
    move.w      #$0FFF,cpPal+(23*4)+2   ; Color 3: Crisp White Wing Sparkle, Cap & Number

    ; SPR4 Oxygen Gauge colors (COLOR25..27):
    move.w      #$0FFF,cpPal+(25*4)+2   ; Color 1: Crisp White (OXY text, glass borders)
    move.w      #$02DF,cpPal+(26*4)+2   ; Color 2: Neon Cyan (Oxygen fluid)
    move.w      #$0024,cpPal+(27*4)+2   ; Color 3: Deep Navy (Empty glass chamber)

    ; SPR6 In-World Bubble colors (COLOR29..31):
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
; Called every VBlank from GameRun.
;
; Handles:
;   - Lives badge frame selection (SPR0): patches pointer to SpriteLives_0..3
;   - Oxygen Kit inventory badge (SPR2): points to SpriteOxygenKit or NullSprite
;   - Oxygen fluid gauge (SPR4):
;       * Evaluates visibility conditions (submerged, recovering, or in water)
;       * Dynamically calculates liquid height: FillRows = PlayerOxygen / 20 (0..20)
;       * Patches 20 fluid scanline bitplane words in SpriteOxy in Chip RAM
;       * Triggers rapid warning red flashing if oxygen is critically low
;   - Dynamic rising in-world air bubbles (SPR6)
;
; In: a5 = Variables base
; Preserves: a5, a6
; Destroys: d0-d3, a0-a2
;==============================================================================

UpdateHUDSprites:
    ; -------------------------------------------------------------------------
    ; 1. Update Player Lives (SPR0 at cpSprites + 0)
    ;    Animated heartbeat: pulses larger then smaller with cardiac rhythm!
    ; -------------------------------------------------------------------------
    move.w      PlayerLives(a5),d0
    bpl.s       .lives_not_neg
    moveq       #0,d0
.lives_not_neg:
    cmp.w       #3,d0
    ble.s       .lives_clamp_ok
    moveq       #3,d0
.lives_clamp_ok:

    ; Determine animation frame (0=Normal, 1=Large, 2=Small)
    ; If player has 0 lives, flatline at resting normal heart (frame 0)
    tst.w       d0
    beq.s       .heart_frame_0

    move.w      TickCounter(a5),d1
    cmp.w       #1,d0
    bne.s       .heart_normal_rate
    ; 1 life remaining: rapid panic heartbeat (32-frame cycle = 94 bpm)
    andi.w      #31,d1
    bra.s       .heart_eval_phase

.heart_normal_rate:
    ; 2+ lives: calm resting heartbeat (64-frame cycle = 47 bpm)
    andi.w      #63,d1

.heart_eval_phase:
    ; Cardiac cycle phases:
    ;   0..3:   Large (Frame 1) - systolic pump 1
    ;   4..7:   Small (Frame 2) - diastolic contraction 1
    ;   8..11:  Large (Frame 1) - systolic pump 2 (lub-dub)
    ;   12..15: Small (Frame 2) - diastolic contraction 2
    ;   16+:    Normal (Frame 0) - resting diastole pause
    cmpi.w      #16,d1
    bge.s       .heart_frame_0

    ; Inside beat pulse window (frames 0..15):
    ; Bit 2 toggles every 4 frames:
    ;   Bit 2 = 0 -> Large (Frame 1)
    ;   Bit 2 = 1 -> Small (Frame 2)
    btst        #2,d1
    bne.s       .heart_frame_small
    moveq       #1,d1                   ; Frame 1: Large
    bra.s       .heart_calc_offset

.heart_frame_small:
    moveq       #2,d1                   ; Frame 2: Small
    bra.s       .heart_calc_offset

.heart_frame_0:
    moveq       #0,d1                   ; Frame 0: Normal / Rest

.heart_calc_offset:
    ; Table offset = (anim_frame * 4 + lives) * 4 bytes
    ;              = (anim_frame * 16) + (lives * 4)
    lsl.w       #4,d1                   ; d1 = anim_frame * 16
    lsl.w       #2,d0                   ; d0 = lives * 4
    add.w       d1,d0                   ; d0 = total byte offset into SpriteLives_Table
    lea         SpriteLives_Table,a0
    move.l      (a0,d0.w),d0            ; d0 = pointer to SpriteLives_N_Frame

    ; Write 32-bit address into SPR0PTH/L (cpSprites + 0)
    lea         cpSprites,a0
    swap        d0
    move.w      d0,2(a0)                ; SPR0PTH
    swap        d0
    move.w      d0,6(a0)                ; SPR0PTL

    ; -------------------------------------------------------------------------
    ; 1b. Update Oxygen Kit Inventory Sprite (SPR2 at cpSprites + 16)
    ; -------------------------------------------------------------------------
    tst.w       OxygenKitInventory(a5)
    beq.s       .hide_oxygen_kit

    move.l      #SpriteOxygenKit,d0
    bra.s       .set_spr2

.hide_oxygen_kit:
    move.l      #NullSprite,d0

.set_spr2:
    lea         cpSprites+16,a0         ; channel 2 * 8 = 16 bytes
    swap        d0
    move.w      d0,2(a0)                ; SPR2PTH
    swap        d0
    move.w      d0,6(a0)                ; SPR2PTL

    ; -------------------------------------------------------------------------
    ; 1c. Update Friends Remaining Counter Sprite (SPR3 at cpSprites + 24)
    ; -------------------------------------------------------------------------
    tst.w       ActiveFriendCount(a5)
    beq.s       .hide_friends_hud       ; no friends in this level -> hide SPR3

    move.w      ActiveFriendCount(a5),d0
    sub.w       FriendsCollectedCount(a5),d0 ; d0 = friends remaining to rescue
    bpl.s       .friends_not_neg
    moveq       #0,d0
.friends_not_neg:
    cmp.w       #16,d0
    ble.s       .friends_clamp_ok
    moveq       #16,d0
.friends_clamp_ok:
    lsl.w       #2,d0                   ; index * 4 (32-bit pointer offset)
    lea         SpriteFriends_Table,a0
    move.l      (a0,d0.w),d0            ; d0 = pointer to SpriteFriends_N
    bra.s       .set_spr3

.hide_friends_hud:
    move.l      #NullSprite,d0

.set_spr3:
    lea         cpSprites+24,a0         ; channel 3: cpSprites + 24
    swap        d0
    move.w      d0,2(a0)                ; SPR3PTH
    swap        d0
    move.w      d0,6(a0)                ; SPR3PTL

    ; -------------------------------------------------------------------------
    ; 2. Update Oxygen Bar (SPR4: 16x28 Vertical Gauge, 20 Fill Rows)
    ;    Visible ONLY when player is in water or replenishing breath!
    ; -------------------------------------------------------------------------
    ; Condition 1: If oxygen is depleted / replenishing (< OXYGEN_MAX), show gauge!
    move.w      PlayerOxygen(a5),d0     ; 0..OXYGEN_MAX (400)
    cmp.w       #OXYGEN_MAX,d0
    blt.s       .show_oxy

    ; Condition 2: If head is submerged underwater, show gauge!
    tst.w       PlayerSubmerged(a5)
    bne.s       .show_oxy

    ; Condition 3: Check if level has water and player's feet touch water
    move.w      WaterPixelY(a5),d1
    bmi.s       .hide_oxy               ; no water on level -> hide

    lea         Player(a5),a1
    move.w      Player_Y(a1),d2
    lsl.w       #4,d2
    add.w       Player_YDec(a1),d2
    add.w       #15,d2                  ; d2 = player feet Y
    cmp.w       d1,d2                   ; feet Y >= WaterPixelY?
    bge.s       .show_oxy               ; feet in water -> show!

.hide_oxy:
    ; Point SPR4 to NullSprite (hide gauge completely on dry land)
    move.l      #NullSprite,d0
    lea         cpSprites+32,a0
    swap        d0
    move.w      d0,2(a0)
    swap        d0
    move.w      d0,6(a0)
    bra         .oxy_update_done

.show_oxy:
    ; Point SPR4 to SpriteOxy (display gauge)
    move.l      #SpriteOxy,d0
    lea         cpSprites+32,a0
    swap        d0
    move.w      d0,2(a0)
    swap        d0
    move.w      d0,6(a0)

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
    bgt.s       .oxy_check_active_color
    move.w      TickCounter(a5),d1
    btst        #2,d1                   ; flash every 4 frames (~12Hz)
    beq.s       .oxy_check_active_color
    ; Flash color: Bright Warning Red
    move.w      #$0F30,cpPal+(26*4)+2
    bra.s       .oxy_update_done

.oxy_check_active_color:
    tst.w       OxygenKitActive(a5)
    beq.s       .oxy_normal_color
    ; Dark Blue for Oxygen Kit active
    move.w      #$016D,cpPal+(26*4)+2   ; Dark Blue liquid
    bra.s       .oxy_update_done

.oxy_normal_color:
    move.w      #$02DF,cpPal+(26*4)+2   ; Neon Cyan

.oxy_update_done:

    ; -------------------------------------------------------------------------
    ; 3. Update Air Bubble (SPR6 at cpSprites + 48, in bubble_sprite.asm)
    ; -------------------------------------------------------------------------
    bsr         UpdateAirBubble
    rts
