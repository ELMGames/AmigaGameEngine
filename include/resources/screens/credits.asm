;==============================================================================
; AMIGA GAME ENGINE
; credits.asm  -  Game & Engine Credits Screen (states 17-18)
;==============================================================================
;
; State 17 (CREDITS_SETUP): CreditsSetup -- clear screen, draw credits, -> CREDITS_RUN
; State 18 (CREDITS_RUN):   CreditsRun   -- FIRE/RETURN/ESC -> TITLE_SETUP
;
; Reuses cpTitle copper list (already installed by TitleSetup).
; Text is rendered to DisplayScreen via CHAR_BLTString / CHAR_BLTOneChar.
; Screen: 320x200, 5 bitplanes interleaved, LOADING_ROW_BYTES stride.
;==============================================================================

;------------------------------------------------------------------------------
; Credits screen offsets  (row_y * LOADING_ROW_BYTES + byte_x)
;------------------------------------------------------------------------------
CRED_OFF_HDR        = 6*LOADING_ROW_BYTES+14    ; "GAME CREDITS" (centred)

CRED_OFF_S1         = 20*LOADING_ROW_BYTES+2    ; "AUDIO & GRAPHICS:"
CRED_OFF_L1         = 31*LOADING_ROW_BYTES+2    ; "TITLE: HEATWAVE CRUISE"
CRED_OFF_L2         = 42*LOADING_ROW_BYTES+2    ; "LEVELS: XLR8"
CRED_OFF_L3         = 53*LOADING_ROW_BYTES+2    ; "COMPLETION: 10K REGGAE DUB"
CRED_OFF_L4         = 64*LOADING_ROW_BYTES+2    ; "COMPOSER: JAM (H3XAFLIGHT)"
CRED_OFF_L5         = 75*LOADING_ROW_BYTES+2    ; "MOD REPLAYER: PTPLAYER (FRANK WILLE)"
CRED_OFF_L6         = 86*LOADING_ROW_BYTES+2    ; "TILESET: ROTTINGPIXELS"

CRED_OFF_S2         = 104*LOADING_ROW_BYTES+2   ; "TOOLS:"
CRED_OFF_L7         = 115*LOADING_ROW_BYTES+2   ; "ZX0 COMPRESSION: EINAR SAUKAS"
CRED_OFF_L8         = 126*LOADING_ROW_BYTES+2   ; "SYSTEM: AMIGA 500 OCS, 50 FPS"
CRED_OFF_L9         = 137*LOADING_ROW_BYTES+2   ; "CODE: MOTOROLA 68000 ASSEMBLY"
CRED_OFF_L10        = 148*LOADING_ROW_BYTES+2   ; "TOOLS: VASM, VLINK, TILED, PYTHON"
CRED_OFF_L11        = 170*LOADING_ROW_BYTES+2   ; "SPECIAL THANKS: ALL RETRO CODERS" (double line space)

CRED_OFF_RET        = 186*LOADING_ROW_BYTES+5
CRED_OFF_RETTXT     = 186*LOADING_ROW_BYTES+7


;==============================================================================
; CreditsSetup  -  One-shot init for credits screen (state CREDITS_SETUP)
;
; Clears DisplayScreen, blits credits text, advances to CREDITS_RUN.
; cpTitle copper list remains active (installed by TitleSetup).
;==============================================================================

CreditsSetup:
    WAITBLIT

    bsr         TS_FlattenSky           ; keep sky flat black

    lea         DisplayScreen,a0
    move.l      #LOADING_ROW_BYTES*LOADING_HEIGHT,d7
    bsr         TurboClear

    ; Title
    lea         DisplayScreen+CRED_OFF_HDR,a1
    lea         .str_hdr,a0
    bsr         CHAR_BLTStringYellow

    ; Section 1: Audio & Graphics
    lea         DisplayScreen+CRED_OFF_S1,a1
    lea         .str_s1,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+CRED_OFF_L1,a1
    lea         .str_l1,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+CRED_OFF_L2,a1
    lea         .str_l2,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+CRED_OFF_L3,a1
    lea         .str_l3,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+CRED_OFF_L4,a1
    lea         .str_l4,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+CRED_OFF_L5,a1
    lea         .str_l5,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+CRED_OFF_L6,a1
    lea         .str_l6,a0
    bsr         CHAR_BLTString

    ; Section 2: Tools
    lea         DisplayScreen+CRED_OFF_S2,a1
    lea         .str_s2,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+CRED_OFF_L7,a1
    lea         .str_l7,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+CRED_OFF_L8,a1
    lea         .str_l8,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+CRED_OFF_L9,a1
    lea         .str_l9,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+CRED_OFF_L10,a1
    lea         .str_l10,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+CRED_OFF_L11,a1
    lea         .str_l11,a0
    bsr         CHAR_BLTStringGreen

    ; Footer prompt
    move.b      #'>',d2
    lea         DisplayScreen+CRED_OFF_RET,a1
    bsr         CHAR_BLTGreenChar
    lea         DisplayScreen+CRED_OFF_RETTXT,a1
    lea         .str_ret,a0
    bsr         CHAR_BLTString

    move.w      #CREDITS_RUN,GameStatus(a5)
    rts

.str_hdr    dc.b    "GAME CREDITS",0
.str_s1     dc.b    "AUDIO & GRAPHICS:",0
.str_l1     dc.b    "TITLE: HEATWAVE CRUISE",0
.str_l2     dc.b    "LEVELS: XLR8",0
.str_l3     dc.b    "COMPLETION: 10K REGGAE DUB",0
.str_l4     dc.b    "COMPOSER: JAM (H3XAFLIGHT)",0
.str_l5     dc.b    "MOD REPLAYER: PTPLAYER (FRANK WILLE)",0
.str_l6     dc.b    "TILESET: ROTTINGPIXELS",0
.str_s2     dc.b    "TOOLS:",0
.str_l7     dc.b    "ZX0 COMPRESSION: EINAR SAUKAS",0
.str_l8     dc.b    "SYSTEM: AMIGA 500 OCS, 50 FPS",0
.str_l9     dc.b    "CODE: MOTOROLA 68000 ASSEMBLY",0
.str_l10    dc.b    "TOOLS: VASM, VLINK, TILED, PYTHON",0
.str_l11    dc.b    "SPECIAL THANKS: ALL RETRO CODERS",0
.str_ret    dc.b    "PRESS FIRE TO RETURN TO TITLE",0
    even


;==============================================================================
; CreditsRun  -  Per-frame handler for credits screen (state CREDITS_RUN)
;
; Waits for joystick FIRE, Return, or ESC key, then returns to TITLE_SETUP.
;==============================================================================

CreditsRun:
    PUSHALL

    bsr         UpdateControls
    move.b      ControlsTrigger(a5),d0

    btst        #CONTROLB_FIRE,d0
    bne         .go_title

    lea         Keys,a0
    tst.b       KEY_ESC(a0)
    bne         .quit_title
    tst.b       KEY_RETURN(a0)
    beq         .no_title

.quit_title
    clr.b       KEY_ESC(a0)
    clr.b       KEY_RETURN(a0)

.go_title
    move.w      #TITLE_SETUP,GameStatus(a5)

.no_title
    POPALL
    rts

