;==============================================================================
; AMIGA GAME ENGINE
; gameover.asm  -  Game Over Screen (states 17 and 18)
;==============================================================================
;
; Displayed when the player loses all 3 lives (PlayerLives reaches 0).
;
; Styled after the iconic Blade Runner spinner terminal:
;   - Solid deep crimson red background (COLOR00 = $0711).
;   - Top header: "ENVIRON CTR" (bold white 8x8 font, row 16).
;   - White horizontal dashed lines (rows 32..34 and 164..166, 4px on / 4px off).
;   - Flashing hero text in Michroma font (all 5 planes, COLOR31 = $0FFF white):
;       Row  48: "GAME" (centred horizontally)
;       Row 104: "OVER" (centred horizontally)
;   - Bottom terminal telemetry: "24556                      DR 5" (row 176).
;
; Flashes at MICHROMA_FLASH_PERIOD (~0.5s on, ~0.5s off) for 4.0 seconds total
; (GAME_OVER_DURATION = 200 frames @ 50 Hz PAL, scaled for NTSC via ScalePALFrames).
;
; After 4 seconds (or if the player presses FIRE / Return / ESC):
;   - MichromaFlashStop cleans up the armed flash strings.
;   - GameStatus transitions to TITLE_SETUP (state 9) to return to main menu.
;
; Register conventions:
;   a5 = Variables base
;   a6 = $dff000 (CUSTOM)
;==============================================================================


;==============================================================================
; DrawDashLine  -  Draw a horizontal white dashed line across columns 4..37
;
; In:  d1.w = start scanline row (Y)
;      d2.w = line height in scanlines (e.g. 3)
; Uses: DisplayScreen
; Destroys: d0-d5, a0-a3
;==============================================================================

DrawDashLine:
    PUSHM      d1-d5/a0-a3
    mulu       #LOADING_ROW_BYTES,d1
    lea        DisplayScreen,a0
    add.l      d1,a0                    ; a0 = start row address (plane 0)
    subq.w     #1,d2                    ; for dbra
.row_loop:
    move.l     a0,a1                    ; a1 = plane 0 of current scanline
    lea        CHAR_PLANE4(a1),a3       ; a3 = plane 4 of current scanline
    moveq      #4,d0                    ; start at byte column 4
.col_loop:
    move.b     #$F0,d3                  ; 4 pixels white, 4 pixels gap
    move.b     d3,0(a1,d0.w)            ; plane 0
    move.b     d3,CHAR_PLANE1(a1,d0.w)  ; plane 1
    move.b     d3,CHAR_PLANE2(a1,d0.w)  ; plane 2
    move.b     d3,CHAR_PLANE3(a1,d0.w)  ; plane 3
    move.b     d3,0(a3,d0.w)            ; plane 4
    addq.w     #1,d0
    cmp.w      #38,d0                   ; columns 4..37 (34 bytes = 272 pixels)
    blt.s      .col_loop

    add.w      #LOADING_ROW_BYTES,a0    ; next scanline
    dbra       d2,.row_loop
    POPM       d1-d5/a0-a3
    rts


;==============================================================================
; GameOverSetup  -  One-shot initialisation for Game Over screen (state 17)
;==============================================================================

GameOverSetup:
    PUSHALL

    ; 1. Stop active music / sound effects and play Game Over theme
    bsr         AudioStopMod
    bsr         AudioPlayGameOver

    ; 2. Clear all 8 hardware sprite DMA pointers
    bsr         ClearSprites

    ; 3. Clear entire DisplayScreen to zero (renders as crimson red background)
    lea         DisplayScreen,a0
    move.l      #SCREEN_SIZE,d7
    bsr         TurboClear

    ; 4. Patch cpGameOver bitplane pointers with DisplayScreen addresses
    lea         cpGameOverPlanes,a0
    move.l      #DisplayScreen,d0
    move.l      #LOADING_WIDTH_BYTE,d1
    moveq       #SCREEN_DEPTH,d7
    bsr         CopperSetPtrs

    ; 5. Patch cpGameOver sprite pointers (all 8 channels to NullSprite)
    lea         cpGameOverSprites,a0
    move.l      #NullSprite,d0
    moveq       #0,d1
    moveq       #8,d7
    bsr         CopperSetPtrs

    ; 6. Install cpGameOver copper list and restart Copper
    move.l      #cpGameOver,COP1LC(a6)
    move.w      #0,COPJMP1(a6)

    ; 7. Draw static Blade Runner terminal UI elements (white on red background):
    ;    a) Header text: "ENVIRON CTR" (centred at byte column 15, row 16)
    move.w      #1,FontBold(a5)
    lea         .str_top,a0
    lea         DisplayScreen+(16*LOADING_ROW_BYTES)+15,a1
    bsr         CHAR_BLTString

    ;    b) Top dashed line (row 32, 3 scanlines tall)
    move.w      #32,d1
    move.w      #3,d2
    bsr         DrawDashLine

    ;    c) Bottom dashed line (row 164, 3 scanlines tall)
    move.w      #164,d1
    move.w      #3,d2
    bsr         DrawDashLine

    ;    d) Bottom telemetry: "24556                      DR 5" (row 176)
    lea         .str_bottom,a0
    lea         DisplayScreen+(176*LOADING_ROW_BYTES)+5,a1
    bsr         CHAR_BLTString
    clr.w       FontBold(a5)

    ; 8. Arm two-line centered flashing "GAME" / "OVER" hero text (Michroma font)
    lea         .str_game,a0
    move.w      #48,d1                  ; row 48: "GAME"
    lea         .str_over,a3
    move.w      #104,d3                 ; row 104: "OVER"
    lea         DisplayScreen,a2
    bsr         MichromaFlashInit2

    ; 9. Arm 4-second hold timer (200 frames @ 50 Hz PAL, scaled for NTSC)
    move.w      #GAME_OVER_DURATION,d0
    bsr         ScalePALFrames
    move.w      d0,GameOverTimer(a5)

    ; 10. Advance to GAME_OVER_RUN (state 18)
    clr.w       VBlankOverrunCount(a5) ; clear multi-frame setup overruns
    move.w      #GAME_OVER_RUN,GameStatus(a5)

    POPALL
    rts

.str_top    dc.b    "ENVIRON CTR",0
.str_bottom dc.b    "24556                      DR 5",0
.str_game   dc.b    "GAME",0
.str_over   dc.b    "OVER",0
    even


;==============================================================================
; GameOverRun  -  Per-frame handler for Game Over screen (state 18)
;==============================================================================

GameOverRun:
    PUSHALL

    bsr         UpdateControls

    ; 1. Tick the flashing hero text (toggles on/off every ~0.5s)
    bsr         MichromaFlashTick

    ; 2. Check if player pressed FIRE, Return, or ESC to skip to title
    lea         Keys,a0
    tst.b       KEY_ESC(a0)
    bne.s       .go_menu_esc
    tst.b       KEY_RETURN(a0)
    bne.s       .go_menu_ret
    move.w      ControlsTrigger(a5),d0
    btst        #CONTROLB_FIRE,d0
    bne.s       .go_menu

    ; 3. Count down 4-second timer
    subq.w      #1,GameOverTimer(a5)
    bgt.s       .stay

.go_menu:
    bsr         AudioStopMod
    bsr         MichromaFlashStop
    move.w      #TITLE_SETUP,GameStatus(a5)
    POPALL
    rts

.go_menu_esc:
    clr.b       KEY_ESC(a0)
    bra.s       .go_menu

.go_menu_ret:
    clr.b       KEY_RETURN(a0)
    bra.s       .go_menu

.stay:
    POPALL
    rts
