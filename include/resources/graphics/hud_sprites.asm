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
    ; VSTART is adjusted by SpriteYOffset(a5) for video standard ($30 PAL, $20 NTSC)
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
    sub.w       FriendsRescuedCount(a5),d0 ; d0 = friends remaining to rescue
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
    ; 3. Update Air Bubble (SPR6 at cpSprites + 48)
    ; -------------------------------------------------------------------------
    bsr         UpdateAirBubble
    rts


;==============================================================================
; UpdateAirBubble  -  Animate and render dynamic submerged air bubble on SPR6
;
; Amiga Hardware Dynamic In-World Sprite:
; Unlike the HUD badges (which sit at fixed screen coordinates), the air bubble
; exists in the game world and moves with the water physics.
;
; Mechanics:
;   1. Spawns periodically (~every 50 frames / 1.0s) at the player's head/snorkel
;      when PlayerSubmerged is non-zero.
;   2. Ascends toward the surface at 2 pixels per frame with a subtle sinusoidal
;      horizontal wobble (derived from scanline phase).
;   3. Pops (resets to NullSprite) when:
;      - World Y breaches WaterPixelY (reaches the air surface)
;      - World Y scrolls outside the visible camera viewport (TilemapCameraY)
;   4. Dynamic Hardware Translation:
;      - Translates World coordinates to Screen coordinates via TilemapCameraY.
;      - Applies PAL/NTSC vertical beam origin (SpriteYOffset).
;      - Applies horizontal beam origin (WINDOW_X_START = $81).
;      - Encodes 9-bit vertical coordinates into SPRxPOS and SPRxCTL:
;          * Bits 15:8 of POS = VSTART[7:0]
;          * Bits  7:0 of POS = HSTART[8:1]
;          * Bits 15:8 of CTL = VSTOP[7:0]
;          * Bit      2 of CTL = SV8 (VSTART bit 8, for scanlines >= 256)
;          * Bit      1 of CTL = EV8 (VSTOP bit 8, for scanlines >= 256)
;          * Bit      0 of CTL = HSTART[0] (low-order horizontal pixel bit)
;   5. Patches Copper pointer at cpSprites+48 (Channel 6).
;==============================================================================

UpdateAirBubble:
    tst.w       PlayerSubmerged(a5)
    beq         .check_floating_bubble  ; not submerged: let existing bubble finish rising

    ; --- Player is submerged: tick spawn timer ---
    tst.w       BubbleActive(a5)
    bne.s       .bubble_rise            ; already rising

    subq.w      #1,BubbleTimer(a5)
    bgt         .hide_bubble

    ; Spawn new bubble at player's mouth / snorkel
    move.w      #1,BubbleActive(a5)
    move.w      #50,BubbleTimer(a5)     ; reset spawn timer (~1.0s interval)
    bsr         AudioPlayAirBubble

    lea         Player(a5),a4
    ; World X = Player_X * 16 + Player_XDec + 4 (offset to mouth)
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

    ; Check if bubble breached the rising water surface
    move.w      WaterPixelY(a5),d0
    bmi         .pop_bubble             ; no water active -> pop
    cmp.w       BubbleWorldY(a5),d0
    bge         .pop_bubble             ; WaterPixelY >= BubbleWorldY -> breached surface!

    ; Check if within camera viewport
    move.w      BubbleWorldY(a5),d0
    sub.w       TilemapCameraY(a5),d0   ; d0 = Screen Y relative to camera
    blt         .pop_bubble             ; scrolled off top of display
    cmp.w       #200,d0
    bgt         .pop_bubble             ; scrolled off bottom of display

    ; --- Bubble is visible: compute raster coordinates ---
    ; Screen X:
    move.w      BubbleWorldX(a5),d1
    ; Add subtle horizontal sinusoidal drift: (BubbleWorldY & 7) - 3 (-3..+4 pixels)
    move.w      BubbleWorldY(a5),d2
    andi.w      #7,d2
    subq.w      #3,d2
    add.w       d2,d1

    ; Screen Y:
    move.w      d0,d2                   ; d2 = Screen Y

    ; Raster VSTART / VSTOP:
    add.w       SpriteYOffset(a5),d2    ; d2 = VSTART in raster scanlines
    move.w      d2,d3
    addq.w      #8,d3                   ; d3 = VSTOP (8 scanlines tall)

    ; Raster HSTART:
    add.w       #WINDOW_X_START,d1      ; d1 = HSTART with hardware horizontal offset

    ; Build SPRxPOS and SPRxCTL:
    ; POS word: bits 15:8 = VSTART[7:0], bits 7:0 = HSTART[8:1]
    move.w      d2,d0
    andi.w      #$00ff,d0
    lsl.w       #8,d0
    move.w      d1,d4
    lsr.w       #1,d4                   ; d4 = HSTART[8:1]
    andi.w      #$00ff,d4
    or.w        d4,d0                   ; d0 = SPRxPOS

    ; CTL word: bits 15:8 = VSTOP[7:0], bit 0 = HSTART[0]
    move.w      d3,d4
    andi.w      #$00ff,d4
    lsl.w       #8,d4
    move.w      d1,d5
    andi.w      #1,d5                   ; d5 = HSTART[0]
    or.w        d5,d4                   ; d4 = SPRxCTL base

    ; Encode 9th vertical address bits:
    ; Amiga displays can extend past scanline 255 into 300+ in PAL:
    ;   Bit 2 of CTL = SV8 (VSTART high bit 8)
    ;   Bit 1 of CTL = EV8 (VSTOP high bit 8)
    btst        #8,d2
    beq.s       .no_sv8
    bset        #2,d4
.no_sv8:
    btst        #8,d3
    beq.s       .no_ev8
    bset        #1,d4
.no_ev8:

    ; Write updated header directly into SpriteBubble data block
    lea         SpriteBubble,a0
    move.w      d0,(a0)
    move.w      d4,2(a0)

    ; Point SPR6PTH/L to SpriteBubble (Channel 6: 6 * 8 bytes = 48)
    move.l      #SpriteBubble,d0
    lea         cpSprites+48,a0
    swap        d0
    move.w      d0,2(a0)                ; SPR6PTH
    swap        d0
    move.w      d0,6(a0)                ; SPR6PTL
    rts

.check_floating_bubble:
    tst.w       BubbleActive(a5)
    bne         .bubble_rise            ; finish rising even if player surfaced
    bra.s       .hide_bubble

.pop_bubble:
    clr.w       BubbleActive(a5)

.hide_bubble:
    ; Point SPR6PTH/L to NullSprite (hide bubble)
    move.l      #NullSprite,d0
    lea         cpSprites+48,a0
    swap        d0
    move.w      d0,2(a0)                ; SPR6PTH
    swap        d0
    move.w      d0,6(a0)                ; SPR6PTL
    rts


;==============================================================================
; Chip RAM Sprite Data Section
;==============================================================================

    section    data_chip,data_c

; -----------------------------------------------------------------------------
; Player Lives Sprites (SPR0, 16px wide x 9 scanlines)
;
; Animated Heartbeat HUD Indicator:
; Displays a polished arcade heart icon alongside the remaining lives count
; (0..3) using crisp white 5x5 font.
;
; Features a living cardiac rhythm animation:
;   - Frame 0 (Normal): 7x7 resting heart
;   - Frame 1 (Large):  8x8 expanded systolic pulse (larger)
;   - Frame 2 (Small):  6x5 contracted diastolic pulse (smaller)
;
; In-game rhythm:
;   - 2+ lives: Calm resting heartbeat (64 frames = ~1.28s, 47 bpm)
;   - 1 life:   Rapid urgent heartbeat (32 frames = ~0.64s, 94 bpm)
;   - 0 lives:  Flatline at resting frame 0 (no pulse)
;
; Colors (COLOR17..19):
;   Color 1 (Plane 0=1, Plane 1=0): Outline (Dark Maroon $0601)
;   Color 2 (Plane 0=0, Plane 1=1): Body (Vivid Arcade Red $0F22)
;   Color 3 (Plane 0=1, Plane 1=1): White Specular Glint & Number ($0FFF)
; -----------------------------------------------------------------------------

; --- Frame 0: Normal / Rest Heart (7x7) ---
SpriteLives_0:
SpriteLives_0_Norm:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3600,$0000
    dc.w    $593E,$363E
    dc.w    $6122,$3E22
    dc.w    $4122,$3E22
    dc.w    $2222,$1C22
    dc.w    $143E,$083E
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_1:
SpriteLives_1_Norm:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3600,$0000
    dc.w    $5908,$3608
    dc.w    $6118,$3E18
    dc.w    $4108,$3E08
    dc.w    $2208,$1C08
    dc.w    $143E,$083E
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_2:
SpriteLives_2_Norm:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3600,$0000
    dc.w    $593E,$363E
    dc.w    $6102,$3E02
    dc.w    $413E,$3E3E
    dc.w    $2220,$1C20
    dc.w    $143E,$083E
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_3:
SpriteLives_3_Norm:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3600,$0000
    dc.w    $593E,$363E
    dc.w    $6102,$3E02
    dc.w    $411C,$3E1C
    dc.w    $2202,$1C02
    dc.w    $143E,$083E
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

; --- Frame 1: Large / Expanded Pulse (8x8) ---
SpriteLives_0_Large:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $6600,$0000
    dc.w    $B93E,$763E
    dc.w    $E122,$7E22
    dc.w    $8122,$7E22
    dc.w    $4222,$3C22
    dc.w    $223E,$1C3E
    dc.w    $1400,$0800
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_1_Large:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $6600,$0000
    dc.w    $B908,$7608
    dc.w    $E118,$7E18
    dc.w    $8108,$7E08
    dc.w    $4208,$3C08
    dc.w    $223E,$1C3E
    dc.w    $1400,$0800
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_2_Large:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $6600,$0000
    dc.w    $B93E,$763E
    dc.w    $E102,$7E02
    dc.w    $813E,$7E3E
    dc.w    $4220,$3C20
    dc.w    $223E,$1C3E
    dc.w    $1400,$0800
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_3_Large:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $6600,$0000
    dc.w    $B93E,$763E
    dc.w    $E102,$7E02
    dc.w    $811C,$7E1C
    dc.w    $4202,$3C02
    dc.w    $223E,$1C3E
    dc.w    $1400,$0800
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

; --- Frame 2: Small / Contracted Pulse (6x5) ---
SpriteLives_0_Small:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $0000,$0000
    dc.w    $243E,$003E
    dc.w    $7A22,$2422
    dc.w    $4222,$3C22
    dc.w    $2422,$1822
    dc.w    $183E,$003E
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_1_Small:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $0000,$0000
    dc.w    $2408,$0008
    dc.w    $7A18,$2418
    dc.w    $4208,$3C08
    dc.w    $2408,$1808
    dc.w    $183E,$003E
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_2_Small:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $0000,$0000
    dc.w    $243E,$003E
    dc.w    $7A02,$2402
    dc.w    $423E,$3C3E
    dc.w    $2420,$1820
    dc.w    $183E,$003E
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_3_Small:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $0000,$0000
    dc.w    $243E,$003E
    dc.w    $7A02,$2402
    dc.w    $421C,$3C1C
    dc.w    $2402,$1802
    dc.w    $183E,$003E
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

; --- Table of 12 sprite pointers: 3 anim frames x 4 life counts ---
SpriteLives_Table:
    ; Frame 0: Normal / Rest (7x7)
    dc.l    SpriteLives_0
    dc.l    SpriteLives_1
    dc.l    SpriteLives_2
    dc.l    SpriteLives_3

    ; Frame 1: Large / Expanded Pulse (8x8)
    dc.l    SpriteLives_0_Large
    dc.l    SpriteLives_1_Large
    dc.l    SpriteLives_2_Large
    dc.l    SpriteLives_3_Large

    ; Frame 2: Small / Contracted Pulse (6x5)
    dc.l    SpriteLives_0_Small
    dc.l    SpriteLives_1_Small
    dc.l    SpriteLives_2_Small
    dc.l    SpriteLives_3_Small


; -----------------------------------------------------------------------------
; Oxygen Kit Inventory Sprite (SPR2, 16px wide x 13 scanlines)
;
; Displayed to the right of the lives counter when an oxygen bottle is in inventory.
;
; Colors:
;   Color 1 (Plane 0=1, Plane 1=0): Outline (Navy $0024)
;   Color 2 (Plane 0=0, Plane 1=1): Body (Neon Cyan $02DF)
;   Color 3 (Plane 0=1, Plane 1=1): Cap, Valve & Highlight (White $0FFF)
; -----------------------------------------------------------------------------

SpriteOxygenKit:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $03C0,$0180                 ; Row 0: Valve knob (White with dark outline)
    dc.w    $0180,$0000                 ; Row 1: Valve neck (Dark outline)
    dc.w    $07E0,$0000                 ; Row 2: Bottle shoulder top (Dark outline)
    dc.w    $0C20,$07C0                 ; Row 3: Bottle shoulder curve (Cyan with White highlight)
    dc.w    $0E20,$07C0                 ; Row 4: Cylinder body 1
    dc.w    $0E20,$07C0                 ; Row 5: Cylinder body 2
    dc.w    $0E20,$07C0                 ; Row 6: Cylinder body 3
    dc.w    $0E20,$07C0                 ; Row 7: Cylinder body 4
    dc.w    $0E20,$07C0                 ; Row 8: Cylinder body 5
    dc.w    $0E20,$07C0                 ; Row 9: Cylinder body 6
    dc.w    $0C20,$07C0                 ; Row 10: Lower cylinder
    dc.w    $07E0,$0000                 ; Row 11: Base boot
    dc.w    $03C0,$0000                 ; Row 12: Base bottom outline
    dc.w    0,0                         ; terminator


; -----------------------------------------------------------------------------
; Friends Remaining Counter Sprites (SPR3, 16px wide x 9 scanlines)
;
; Displays a cute 7x7 baby duckling badge icon alongside the remaining count
; (0..16) using the exact same 5x5 font and pure white ($0FFF) color as the
; player lives counter.
;
; Colors (shared with SPR2 Oxygen Kit via COLOR21..23):
;   Color 1 (Plane 0=1, Plane 1=0): Outline, Eye & Beak (Amber Orange $0E71)
;   Color 2 (Plane 0=0, Plane 1=1): Yellow Duckling Body (Golden Yellow $0FD1)
;   Color 3 (Plane 0=1, Plane 1=1): White Wing Sparkle & Number (Crisp White $0FFF)
; -----------------------------------------------------------------------------

SpriteFriends_0:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E22,$2022
    dc.w    $C222,$3C22
    dc.w    $C222,$7C22
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_1:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $4808,$3008
    dc.w    $5E18,$2018
    dc.w    $C208,$3C08
    dc.w    $C208,$7C08
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_2:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E02,$2002
    dc.w    $C23E,$3C3E
    dc.w    $C220,$7C20
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_3:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E02,$2002
    dc.w    $C21C,$3C1C
    dc.w    $C202,$7C02
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_4:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $4822,$3022
    dc.w    $5E22,$2022
    dc.w    $C23E,$3C3E
    dc.w    $C202,$7C02
    dc.w    $4402,$3802
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_5:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E20,$2020
    dc.w    $C23E,$3C3E
    dc.w    $C202,$7C02
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_6:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E20,$2020
    dc.w    $C23E,$3C3E
    dc.w    $C222,$7C22
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_7:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E02,$2002
    dc.w    $C204,$3C04
    dc.w    $C208,$7C08
    dc.w    $4408,$3808
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_8:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E22,$2022
    dc.w    $C23E,$3C3E
    dc.w    $C222,$7C22
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_9:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E22,$2022
    dc.w    $C23E,$3C3E
    dc.w    $C202,$7C02
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_10:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48BE,$30BE
    dc.w    $5EA2,$20A2
    dc.w    $C2A2,$3CA2
    dc.w    $C2A2,$7CA2
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_11:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $4888,$3088
    dc.w    $5E98,$2098
    dc.w    $C288,$3C88
    dc.w    $C288,$7C88
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_12:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48BE,$30BE
    dc.w    $5E82,$2082
    dc.w    $C2BE,$3CBE
    dc.w    $C2A0,$7CA0
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_13:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48BE,$30BE
    dc.w    $5E82,$2082
    dc.w    $C29C,$3C9C
    dc.w    $C282,$7C82
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_14:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48A2,$30A2
    dc.w    $5EA2,$20A2
    dc.w    $C2BE,$3CBE
    dc.w    $C282,$7C82
    dc.w    $4482,$3882
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_15:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48BE,$30BE
    dc.w    $5EA0,$20A0
    dc.w    $C2BE,$3CBE
    dc.w    $C282,$7C82
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_16:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48BE,$30BE
    dc.w    $5EA0,$20A0
    dc.w    $C2BE,$3CBE
    dc.w    $C2A2,$7CA2
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_Table:
    dc.l    SpriteFriends_0
    dc.l    SpriteFriends_1
    dc.l    SpriteFriends_2
    dc.l    SpriteFriends_3
    dc.l    SpriteFriends_4
    dc.l    SpriteFriends_5
    dc.l    SpriteFriends_6
    dc.l    SpriteFriends_7
    dc.l    SpriteFriends_8
    dc.l    SpriteFriends_9
    dc.l    SpriteFriends_10
    dc.l    SpriteFriends_11
    dc.l    SpriteFriends_12
    dc.l    SpriteFriends_13
    dc.l    SpriteFriends_14
    dc.l    SpriteFriends_15
    dc.l    SpriteFriends_16


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

