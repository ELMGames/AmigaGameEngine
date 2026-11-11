;==============================================================================
; MEADOW RUN - HUD
; hud_sprites.asm  -  The countdown and duckling counter, on hardware sprites
;==============================================================================
;
; As in Duck Rescue (Chapter 12), the HUD costs no Blitter time and never
; has to be redrawn when the screen scrolls:
;
;   SPR0  seconds left, two digits      colour COLOR17 (flashes red, LevelTick)
;   SPR2  a duckling icon, 16 x 16      colours COLOR21-23
;   SPR3  ducklings collected, 2 digits colour COLOR21 (shared with SPR2)
;
; The digit sprites are 8-line buffers in Chip RAM; HudUpdate writes the two
; digits of a number into one of them from the HudDigits font
; (hud_sprite_data.asm, made by tools/convert_tiles.py).
;==============================================================================


;==============================================================================
; HudInit  -  Position the three sprites and point the Copper list at them
;==============================================================================

HudInit:
    lea        HudTimerSprite,a0
    move.w     #HUD_TIMER_X,d0
    move.w     #HUD_TIMER_Y,d1
    moveq      #HUD_DIGIT_LINES,d2
    bsr.s      HudPlaceSprite
    lea        HudDuckSprite,a0
    move.w     #HUD_DUCK_X,d0
    move.w     #HUD_DUCK_Y,d1
    moveq      #16,d2
    bsr.s      HudPlaceSprite
    lea        HudCountSprite,a0
    move.w     #HUD_COUNT_X,d0
    move.w     #HUD_COUNT_Y,d1
    moveq      #HUD_DIGIT_LINES,d2
    bsr.s      HudPlaceSprite

    lea        cpSprites,a1            ; SPR0, SPR2, SPR3 pointers
    move.l     #HudTimerSprite,d0
    lea        0*8(a1),a0
    PLANE_TO_COPPER d0,a0
    move.l     #HudDuckSprite,d0
    lea        2*8(a1),a0
    PLANE_TO_COPPER d0,a0
    move.l     #HudCountSprite,d0
    lea        3*8(a1),a0
    PLANE_TO_COPPER d0,a0
    rts

;------------------------------------------------------------------------------
; HudPlaceSprite  -  Write a sprite's two control words (Section 12.3)
; In: a0 = sprite data, d0 = screen X, d1 = screen Y, d2 = height in lines.
; The HUD sits near the top, so VSTART and VSTOP stay below line 256.
;------------------------------------------------------------------------------
HudPlaceSprite:
    add.w      SpriteYOffset(a5),d1    ; d1 = VSTART (display top + Y)
    add.w      #WINDOW_X_START,d0      ; d0 = HSTART
    move.w     d1,d3
    lsl.w      #8,d3
    move.w     d0,d4
    lsr.w      #1,d4
    and.w      #$ff,d4
    or.w       d4,d3
    move.w     d3,(a0)                 ; SPRxPOS: VSTART[7:0], HSTART[8:1]
    add.w      d2,d1                   ; VSTOP
    lsl.w      #8,d1
    and.w      #1,d0
    or.w       d0,d1
    move.w     d1,2(a0)                ; SPRxCTL: VSTOP[7:0], HSTART[0]
    rts

;==============================================================================
; HudUpdate  -  Redraw the two numbers if they changed (HudDirty)
;==============================================================================

HudUpdate:
    tst.w      HudDirty(a5)
    beq.s      .done
    clr.w      HudDirty(a5)
    move.w     TimeLeft(a5),d0
    lea        HudTimerSprite,a0
    bsr.s      HudDrawNumber
    move.w     DuckCount(a5),d0
    lea        HudCountSprite,a0
    bsr.s      HudDrawNumber
.done:
    rts

;------------------------------------------------------------------------------
; HudDrawNumber  -  Two digits (00-99) into a digit sprite
; In: d0 = number, a0 = sprite (control words first). Each line's first
; data word holds the two 8-pixel digits; the second is 0, so every set
; pixel is sprite colour 1.
;------------------------------------------------------------------------------
HudDrawNumber:
    and.l      #$ffff,d0
    divu       #10,d0                  ; d0.lo = tens, d0.hi = units
    move.w     d0,d1
    swap       d0                      ; d0 = units
    lsl.w      #3,d1                   ; 8 bytes per digit
    lsl.w      #3,d0
    lea        HudDigits,a1
    lea        (a1,d1.w),a2            ; tens
    lea        (a1,d0.w),a1            ; units
    addq.l     #4,a0                   ; past the control words
    moveq      #HUD_DIGIT_LINES-1,d2
.line:
    move.b     (a2)+,(a0)+             ; left byte: tens
    move.b     (a1)+,(a0)+             ; right byte: units
    clr.w      (a0)+                   ; second plane: 0
    dbra       d2,.line
    rts
