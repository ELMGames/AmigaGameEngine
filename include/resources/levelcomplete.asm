;==============================================================================
; AMIGA GAME ENGINE
; levelcomplete.asm  -  Level Complete Screen (states 9 and 10)
;==============================================================================
;
; Screen layout (320x216 pixels, 5-plane interleaved):
;   Y=  4, bX=12   CONGRATULATIONS! (16 chars, white)
;   Y= 20, bX=11   LEVEL NNN CLEARED! (generic level number, white)
;   Y= 28..91      Portraits: Player 1 at bX=0, Player 2 at bX=32 (64x64 each)
;   Y=100..147     Copper banner (COLOR00 -> gradient)
;   Y=108, bX= 8   NEXT LEVEL ACCESS CODE: (23 chars, white)
;   Y=124, bX=17   6-char access code (white)
;   Y=168, bX=11   > PLAY NEXT LEVEL or   PLAY NEXT LEVEL (17 chars)
;   Y=184, bX=11   > RETURN TO TITLE  or   RETURN TO TITLE  (17 chars)
;
; Font (assets/font.bin):
;   96 glyphs, 8x8 pixels, 1 bitplane, ASCII 32-127.
;   Glyph for char c: FontData + (c - 32) * 8.
;   Required charset: A-Z, 0-9, space, '!', ':', '>', '.'.
;
; Portraits (assets/millie_pic.raw, molly_pic.raw):
;   64x64 pixels, 5 consecutive non-interleaved bitplanes.
;   Plane P: portrait_base + P * 512  (8 bytes/row x 64 rows = 512 bytes).
;   Total: 2560 bytes each. Palette colours 1-30 in cpLCPal should match artwork.
;
; Password:
;   6 uppercase chars generated from LevelId by LC_GenPassword.
;   Characters drawn at Y=124, horizontally centred.
;
; Input (ControlsTrigger / Keys[]):
;   UP / DOWN    - move cursor between menu items
;   FIRE / Return - execute: item 0 = PLAY NEXT LEVEL, item 1 = RETURN TO TITLE
;
; On PLAY NEXT LEVEL: increments LevelId, skips wipe, sets GameStatus = LEVEL_REVEAL.
; On RETURN TO TITLE: sets GameStatus = GAME_INIT (triggers LoadingSetup).
;
;==============================================================================

; ---------------------------------------------------------------------------
; Portrait blitter constants
; ---------------------------------------------------------------------------
LC_PORT_HEIGHT      = 64            ; portrait height in pixels
LC_PORT_WIDTH_BYTES = 8             ; portrait width in bytes (64px / 8)
LC_PORT_PLANE_SIZE  = 512           ; bytes per portrait plane (64 rows x 8 bytes)
LC_PORT_DMOD        = SCREEN_STRIDE-8 ; blitter dest modulo: SCREEN_STRIDE-8 = 200-8 = 192
LC_PORT_BLTSIZE     = $1004         ; BLTSIZE: 64 rows, 4 words wide = (64<<6)|4

LC_SHIMMER_SPEED      = 6            ; frames between gradient rotation steps
LC_GRADIENT_SCHEMES   = 8            ; number of banner colour schemes (must be power of 2)

; ---------------------------------------------------------------------------
; Screen-address offsets (assembly-time constants).
; Formula:  pixel_y * SCREEN_STRIDE + byte_x  = pixel_y * 200 + byte_x
; ---------------------------------------------------------------------------
LC_OFF_TITLE1  =  4*SCREEN_STRIDE+12   ; CONGRATULATIONS! (16 chars on 40 cols -> X=12)
LC_OFF_TITLE2  = 20*SCREEN_STRIDE+11   ; LEVEL NNN CLEARED! (18 chars on 40 cols -> X=11)
LC_OFF_PORTRAIT= 28*SCREEN_STRIDE      ; portrait row base (top-left)
LC_OFF_MILLIE  = LC_OFF_PORTRAIT+0     ; Player 1 portrait at byte X=0 (0..63 px)
LC_OFF_MOLLY   = LC_OFF_PORTRAIT+32    ; Player 2 portrait at byte X=32 (256..319 px)
LC_OFF_BAN1    =108*SCREEN_STRIDE+8    ; NEXT LEVEL ACCESS CODE: (23 chars -> X=8)
LC_OFF_PASS    =124*SCREEN_STRIDE+17   ; 6-char access code (centred on 40 cols -> X=17)
LC_OFF_MENU0   =168*SCREEN_STRIDE+11   ; menu item 0 (17 chars -> X=11)
LC_OFF_MENU1   =184*SCREEN_STRIDE+11   ; menu item 1 (17 chars -> X=11)

;==============================================================================
; LevelTest  -  Check for level completion or debug level navigation
;==============================================================================

LevelTest:
    tst.w       LevelComplete(a5)
    bne         .complete
    bsr         CheckLevelDone
    tst.w       d3
    beq         .flag_done
    bra         .nope

.flag_done:
    move.w      #1,LevelComplete(a5)

.complete:
    move.w      LevelCompleteHold(a5),d0
    bne         .counting
    move.w      #LEVEL_COMPLETE_HOLD_TICKS,LevelCompleteHold(a5)
    rts

.counting:
    subq.w      #1,d0
    move.w      d0,LevelCompleteHold(a5)
    bne         .done
    bsr         AudioStopMod
    move.w      #1,LevelCompleteWipe(a5)
    move.w      #LEVEL_INIT,GameStatus(a5)
.done:
    rts

.nope:
    lea         Keys,a0
    tst.b       KEY_F1(a0)
    beq         .nof1
    clr.b       KEY_F1(a0)
    tst.w       DebugMode(a5)
    beq         .nof1
    tst.w       LevelId(a5)
    beq         .nof1
    subq.w      #1,LevelId(a5)
    bra         .changelevel
.nof1:
    tst.b       KEY_F2(a0)
    beq         .nof2
    clr.b       KEY_F2(a0)
    tst.w       DebugMode(a5)
    beq         .nof2
    cmp.w       #9,LevelId(a5)
    beq         .nof2
    addq.w      #1,LevelId(a5)
    bra         .changelevel
.nof2:
    tst.b       KEY_F8(a0)
    beq         .nokeypress_lc
    clr.b       KEY_F8(a0)
.changelevel:
    bsr         AudioStopMod
    move.w      #LEVEL_INIT,GameStatus(a5)
.nokeypress_lc:
    rts


;==============================================================================
; LevelCompleteSetup  -  One-shot initialisation for level-complete screen
;==============================================================================

LevelCompleteSetup:
    cmp.w       #9,LevelId(a5)
    bne         .normal_lc
    move.w      #GAME_COMPLETE_SETUP,GameStatus(a5)
    rts
.normal_lc:

    PUSHALL

    ; 1. Clear DisplayScreen (SCREEN_SIZE = 43200 bytes)
    lea         DisplayScreen,a0
    move.l      #SCREEN_SIZE,d7
    bsr         TurboClear

    ; 2a. Patch cpLCPlanes with DisplayScreen bitplane addresses
    move.l      #DisplayScreen,d0
    lea         cpLCPlanes,a0
    moveq       #SCREEN_DEPTH-1,d7
.ploop:
    move.w      d0,6(a0)
    swap        d0
    move.w      d0,2(a0)
    swap        d0
    addq.l      #8,a0
    add.l       #SCREEN_WIDTH_BYTE,d0
    dbra        d7,.ploop

    ; 2b. Patch cpLCSprites -> NullSprite
    move.l      #NullSprite,d0
    lea         cpLCSprites,a0
    moveq       #8-1,d7
.sploop:
    move.w      d0,6(a0)
    swap        d0
    move.w      d0,2(a0)
    swap        d0
    addq.l      #8,a0
    dbra        d7,.sploop

    ; 2c. Install cpLevelComplete and restart copper
    move.l      #cpLevelComplete,COP1LC(a6)
    move.w      #0,COPJMP1(a6)

    ; 2d. Patch cpLCBanner with the colour scheme for this level.
    moveq       #0,d0
    move.w      LevelId(a5),d0
    and.w       #LC_GRADIENT_SCHEMES-1,d0
    muls        #12*2,d0
    lea         LC_GradientTable,a0
    add.l       d0,a0
    lea         cpLCBanner,a1
    addq.l      #6,a1
    moveq       #12-1,d7
.grad_copy:
    move.w      (a0)+,(a1)
    addq.l      #8,a1
    dbra        d7,.grad_copy

    ; 3. Blit portraits:
    ; Check if both players were in the level:
    tst.w       Millie+Player_Status(a5)
    beq         .single_player
    tst.w       Molly+Player_Status(a5)
    beq         .single_player

    ; --- Two-player level: draw Dr. Price (left) and Sgt. Cole (right) ---
    lea         MilliePic,a0
    lea         DisplayScreen+LC_OFF_MILLIE,a1
    bsr         LC_BltPortrait

    lea         MollyPic,a0
    lea         DisplayScreen+LC_OFF_MOLLY,a1
    bsr         LC_BltPortrait
    bra         .portraits_done

.single_player:
    ; Single-player level: identify who the active player was from Player_SpriteOffset
    ; (48 = Dr. Price, 0 = Sgt. Cole)
    move.l      PlayerPtrs(a5),a2
    move.w      Player_SpriteOffset(a2),d0
    cmp.w       #48,d0
    beq         .single_price

    ; Single-player Sgt. Cole:
    lea         MollyPic,a0
    lea         DisplayScreen+LC_OFF_MILLIE,a1
    bsr         LC_BltPortrait
    bra         .portraits_done

.single_price:
    ; Single-player Dr. Price:
    lea         MilliePic,a0
    lea         DisplayScreen+LC_OFF_MILLIE,a1
    bsr         LC_BltPortrait

.portraits_done:

    ; 5. WAITBLIT before CPU text writes
    WAITBLIT

    lea         .str_congrats,a0
    lea         DisplayScreen+LC_OFF_TITLE1,a1
    bsr         CHAR_BLTString

    lea         .str_level,a0
    lea         DisplayScreen+LC_OFF_TITLE2,a1
    bsr         CHAR_BLTString

    moveq       #0,d0
    move.w      LevelId(a5),d0
    addq.w      #1,d0
    bsr         CHAR_BLTNum3

    lea         .str_complete,a0
    bsr         CHAR_BLTString

    lea         .str_passhdr,a0
    lea         DisplayScreen+LC_OFF_BAN1,a1
    bsr         CHAR_BLTString

    ; 6. Password
    addq.w      #1,LevelId(a5)
    bsr         LC_GenPassword
    subq.w      #1,LevelId(a5)
    lea         LCPasswordBuf(a5),a0
    lea         DisplayScreen+LC_OFF_PASS,a1
    bsr         CHAR_BLTString

    lea         .str_play,a0
    lea         DisplayScreen+LC_OFF_MENU0+2,a1
    bsr         CHAR_BLTString

    lea         .str_return,a0
    lea         DisplayScreen+LC_OFF_MENU1+2,a1
    bsr         CHAR_BLTString

    ; 7. Init selection and draw cursor
    clr.w       LevelCompleteSel(a5)
    bsr         LC_DrawMenuCursor

    ; 8. Init shimmer countdown and advance state
    move.w      #LC_SHIMMER_SPEED,LCShimmerTick(a5)
    move.w      #LEVEL_COMPLETE_RUN,GameStatus(a5)

    POPALL
    rts

.str_congrats:  dc.b "CONGRATULATIONS!",0
.str_level:     dc.b "LEVEL ",0
.str_complete:  dc.b " CLEARED!",0
.str_passhdr:   dc.b "NEXT LEVEL ACCESS CODE:",0
.str_play:      dc.b "PLAY NEXT LEVEL",0
.str_return:    dc.b "RETURN TO TITLE",0
                even


;==============================================================================
; LevelCompleteRun  -  Per-frame handler for level-complete screen
;==============================================================================

LevelCompleteRun:
    PUSHALL

    bsr         UpdateControls
    move.b      ControlsTrigger(a5),d0

    btst        #CONTROLB_UP,d0
    beq         .no_up
    tst.w       LevelCompleteSel(a5)
    beq         .no_up
    clr.w       LevelCompleteSel(a5)
    bsr         LC_DrawMenuCursor
.no_up:

    btst        #CONTROLB_DOWN,d0
    beq         .no_down
    cmp.w       #1,LevelCompleteSel(a5)
    beq         .no_down
    move.w      #1,LevelCompleteSel(a5)
    bsr         LC_DrawMenuCursor
.no_down:

    btst        #CONTROLB_FIRE,d0
    bne         .do_confirm

    lea         Keys,a0
    tst.b       KEY_RETURN(a0)
    beq         .no_confirm
    clr.b       KEY_RETURN(a0)

.do_confirm:
    tst.w       LevelCompleteSel(a5)
    bne         .return_title

    addq.w      #1,LevelId(a5)
    bsr         LC_FlattenBanner
    move.w      #1,EnterGameCopper(a5)
    move.w      #LEVEL_INIT,GameStatus(a5)
    bra         .done

.return_title:
    move.w      #TITLE_SETUP,GameStatus(a5)

.no_confirm:
.done:
    subq.w      #1,LCShimmerTick(a5)
    bne.s       .no_shimmer
    move.w      #LC_SHIMMER_SPEED,LCShimmerTick(a5)
    bsr         LC_ShimmerBanner
.no_shimmer:
    POPALL
    rts


;==============================================================================
; LC_ShimmerBanner  -  Rotate 12 gradient colour words one step downward
;==============================================================================

LC_ShimmerBanner:
    PUSHM       d0/a0
    lea         cpLCBanner,a0
    move.w      6+11*8(a0),d0
    move.w      6+10*8(a0),6+11*8(a0)
    move.w      6+9*8(a0),6+10*8(a0)
    move.w      6+8*8(a0),6+9*8(a0)
    move.w      6+7*8(a0),6+8*8(a0)
    move.w      6+6*8(a0),6+7*8(a0)
    move.w      6+5*8(a0),6+6*8(a0)
    move.w      6+4*8(a0),6+5*8(a0)
    move.w      6+3*8(a0),6+4*8(a0)
    move.w      6+2*8(a0),6+3*8(a0)
    move.w      6+1*8(a0),6+2*8(a0)
    move.w      6+0*8(a0),6+1*8(a0)
    move.w      d0,6+0*8(a0)
    POPM        d0/a0
    rts


;==============================================================================
; LC_FlattenBanner  -  Kill the banner gradient
;==============================================================================

LC_FlattenBanner:
    PUSHM       d7/a0
    lea         cpLCBanner+6,a0
    moveq       #12-1,d7
.flat_loop:
    clr.w       (a0)
    addq.l      #8,a0
    dbra        d7,.flat_loop
    POPM        d7/a0
    rts


;==============================================================================
; LC_DrawMenuCursor  -  Draw '>' at selected item, ' ' at unselected
;==============================================================================

LC_DrawMenuCursor:
    PUSHALL
    tst.w       LevelCompleteSel(a5)
    beq         .item0_sel

    move.b      #" ",d2
    lea         DisplayScreen+LC_OFF_MENU0,a1
    bsr         CHAR_BLTOneChar

    move.b      #">",d2
    lea         DisplayScreen+LC_OFF_MENU1,a1
    bsr         CHAR_BLTOneChar
    bra         .done

.item0_sel:
    move.b      #">",d2
    lea         DisplayScreen+LC_OFF_MENU0,a1
    bsr         CHAR_BLTOneChar

    move.b      #" ",d2
    lea         DisplayScreen+LC_OFF_MENU1,a1
    bsr         CHAR_BLTOneChar

.done:
    POPALL
    rts


;==============================================================================
; LC_BltPortrait  -  Blit one 64x64, 5-plane portrait to DisplayScreen
;==============================================================================

LC_BltPortrait:
    ; Portraits bypassed until custom Alien Containment portraits are provided
    rts
    PUSHM       d0/d7/a0/a1
    WAITBLIT
    move.l      #$09F00000,BLTCON0(a6)
    move.l      #-1,BLTAFWM(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #LC_PORT_DMOD,BLTDMOD(a6)

    move.l      a0,d0
    moveq       #SCREEN_DEPTH-1,d7
.plane_loop:
    WAITBLIT
    move.l      d0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #LC_PORT_BLTSIZE,BLTSIZE(a6)
    add.l       #LC_PORT_PLANE_SIZE,d0
    add.l       #SCREEN_WIDTH_BYTE,a1
    dbra        d7,.plane_loop

    POPM        d0/d7/a0/a1
    rts


;==============================================================================
; Password generation and decode routines
;==============================================================================

LC_PASSWORD_MUL     = $4321
LC_PASSWORD_KEY     = $00B3C5D1

LC_GenPassword:
    PUSHM       d0-d3/a0
    moveq       #0,d0
    move.w      LevelId(a5),d0
    addq.w      #1,d0
    mulu        #LC_PASSWORD_MUL,d0
    eor.l       #LC_PASSWORD_KEY,d0

    lea         LCPasswordBuf(a5),a0
    moveq       #5,d3
.loop:
    move.l      d0,d1
    and.l       #$F,d1
    add.b       #"A",d1
    move.b      d1,(a0)+
    lsr.l       #4,d0
    dbra        d3,.loop

    clr.b       (a0)
    POPM        d0-d3/a0
    rts

LC_DecodePassword:
    PUSHM       d1-d3/a0
    addq.l      #5,a0
    moveq       #0,d0
    moveq       #5,d3
.assemble:
    move.b      (a0),d1
    sub.b       #"A",d1
    bmi         .invalid
    cmp.b       #16,d1
    bge         .invalid
    lsl.l       #4,d0
    and.l       #$F,d1
    or.l        d1,d0
    subq.l      #1,a0
    dbra        d3,.assemble

    eor.l       #LC_PASSWORD_KEY,d0
    move.w      #LC_PASSWORD_MUL,d1
    divu        d1,d0

    swap        d0
    tst.w       d0
    bne         .invalid
    swap        d0

    tst.w       d0
    beq         .invalid
    cmp.w       #100,d0
    bgt         .invalid

    subq.w      #1,d0
    bra         .done

.invalid:
    move.w      #$FFFF,d0

.done:
    POPM        d1-d3/a0
    rts


;------------------------------------------------------------------------------
; LC_GradientTable - banner gradient colour schemes
;------------------------------------------------------------------------------
                even
LC_GradientTable:
    ; 0: Warm Amber (orange-brown)
    dc.w    $0210,$0321,$0432,$0543,$0764,$0974,$0A74,$0974,$0764,$0543,$0432,$0321
    ; 1: Hot Orange (dark brick to bright orange)
    dc.w    $0100,$0210,$0320,$0430,$0640,$0860,$0B70,$0860,$0640,$0430,$0320,$0210
    ; 2: Lime Green (dark to bright yellow-green)
    dc.w    $0010,$0020,$0130,$0140,$0260,$0380,$04A0,$0380,$0260,$0140,$0130,$0020
    ; 3: Electric Blue (navy to bright cobalt)
    dc.w    $0001,$0002,$0013,$0025,$0038,$015B,$047E,$015B,$0038,$0025,$0013,$0002
    ; 4: Purple/Violet (dark to bright violet)
    dc.w    $0100,$0201,$0302,$0413,$0525,$0747,$0A5C,$0747,$0525,$0413,$0302,$0201
    ; 5: Gold (near-black to bright gold)
    dc.w    $0210,$0320,$0430,$0640,$0860,$0A80,$0CA0,$0A80,$0860,$0640,$0430,$0320
    ; 6: Teal/Cyan (dark to bright teal)
    dc.w    $0011,$0022,$0033,$0145,$0267,$0389,$04BB,$0389,$0267,$0145,$0033,$0022
    ; 7: Pink/Magenta (dark to bright pink-purple)
    dc.w    $0101,$0202,$0303,$0414,$0525,$0737,$0A49,$0737,$0525,$0414,$0303,$0202
