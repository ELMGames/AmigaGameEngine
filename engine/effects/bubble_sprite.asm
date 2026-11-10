
;==============================================================================
; AMIGA GAME ENGINE
; bubble_sprite.asm  -  Underwater Air Bubble Hardware Sprite (SPR6)
;==============================================================================
;
; While the player is underwater, air bubbles rise from their head. The bubble
; is a hardware sprite, so it costs no blits and never touches the screen
; buffers: each frame only updates the sprite's header and the Copper pointer.
;
; The game defines PLAYER_HEAD_Y_OFFSET (player top line to mouth line), sets
; COLOR29-31 and calls UpdateAirBubble once a frame. Without that constant,
; this file assembles to nothing.
;==============================================================================

    IFD PLAYER_HEAD_Y_OFFSET

;==============================================================================
; UpdateAirBubble  -  Animate and render dynamic submerged air bubble on SPR6
;
; Amiga Hardware Dynamic In-World Sprite:
; Unlike the HUD badges (which sit at fixed screen coordinates), the air bubble
; exists in the game world and moves with the water physics.
;
; Mechanics:
;   1. Spawns at the player's head/snorkel when PlayerSubmerged is non-zero,
;      about 50 frames (1.0s) after the previous bubble has gone.
;   2. Ascends toward the surface at 2 pixels per frame with a subtle horizontal
;      wobble (derived from the bubble's Y position). A rising bubble carries on
;      if the player surfaces.
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
;
; Destroys: d0-d5/a0-a1/a4 (preserves everything else, including a5/a6)
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

    ENDC
