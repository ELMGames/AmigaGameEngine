
;==============================================================================
; AMIGA GAME ENGINE TEMPLATE
; instructions.asm  -  Two-page instructions screen (states 11-14)
;==============================================================================
;
; State 11 (INSTR_SETUP1): InstrPage1Setup -- clear screen, draw page 1, -> INSTR_RUN1
; State 12 (INSTR_RUN1):   InstrPage1Run  -- FIRE/RETURN -> INSTR_SETUP2
; State 13 (INSTR_SETUP2): InstrPage2Setup -- clear screen, draw page 2, -> INSTR_RUN2
; State 14 (INSTR_RUN2):   InstrPage2Run  -- FIRE/RETURN -> TITLE_SETUP
;
; Reuses cpTitle copper list (already installed by TitleSetup).
; Text is rendered to DisplayScreen via CHAR_BLTString / CHAR_BLTOneChar.
; Screen: 320x200, 5 bitplanes interleaved, LOADING_ROW_BYTES stride.
;
; ===========================================================================
; DEVELOPER GUIDE -- THESE PAGES ARE YOUR IN-GAME README
; ===========================================================================
;
; Page 1 -- "ABOUT THIS TEMPLATE"
;   Engine overview: what is included, what platforms are supported.
;   Update this page with your own game''s story/instructions once you are
;   ready to make it your own.
;
; Page 2 -- "HOW TO CUSTOMISE"
;   Quick reference for developers. Key files to edit:
;
;     LEVELS   : assets/Levels/lv_NNN.bytes  (88 bytes, 11x8 grid)
;                Rebuild assets/Levels/levels.bin after changing levels.
;                Block values: 0=Empty 1=Ladder 2=FallEnemy 3=Push
;                              4=Dirt   5=Solid  6=FloatEnemy
;                              7=Player1Start  8=Player2Start
;
;     TILES    : assets/graphics/tiles/Tiles_0.pak  (32 tiles, 24x24 each)
;                Source PNG: Tiles_0.png (see tools/tiles_pipeline.py)
;                To use multiple tile sets, add Tiles_1..4 and update
;                assets.asm + the Chapters / LevelAssetSet tables.
;
;     SPRITES  : assets/graphics/enemies/enemies_64x128.raw
;                assets/graphics/sprites/player_bobs_64x576.raw
;
;     MUSIC    : assets/music/*.mod  (ProTracker modules)
;                TitleScreenMusicMod = supremacy_title.mod
;                LevelMod            = playingw.mod
;
;     LOADING  : assets/graphics/title/template.raw + template.zx0
;                336x200, 5-bitplane interleaved, ZX0 compressed
;
;     CODE     : All subsystems are in include/resources/*.asm
;                Entry point: main.asm
;==============================================================================

;------------------------------------------------------------------------------
; Page 1 screen offsets  (row_y * LOADING_ROW_BYTES + byte_x)
;------------------------------------------------------------------------------
INSTR1_OFF_HDR      = 4*LOADING_ROW_BYTES+8
INSTR1_OFF_L1       = 20*LOADING_ROW_BYTES+2
INSTR1_OFF_L2       = 32*LOADING_ROW_BYTES+2
INSTR1_OFF_L3       = 48*LOADING_ROW_BYTES+2
INSTR1_OFF_L4       = 60*LOADING_ROW_BYTES+2
INSTR1_OFF_L5       = 76*LOADING_ROW_BYTES+2
INSTR1_OFF_L6       = 88*LOADING_ROW_BYTES+2
INSTR1_OFF_L7       = 104*LOADING_ROW_BYTES+2
INSTR1_OFF_L8       = 116*LOADING_ROW_BYTES+2
INSTR1_OFF_L9       = 132*LOADING_ROW_BYTES+2
INSTR1_OFF_L10      = 144*LOADING_ROW_BYTES+2
INSTR1_OFF_L11      = 160*LOADING_ROW_BYTES+2
INSTR1_OFF_L12      = 172*LOADING_ROW_BYTES+2
INSTR1_OFF_NEXT     = 192*LOADING_ROW_BYTES+11
INSTR1_OFF_NEXTTXT  = 192*LOADING_ROW_BYTES+12

;------------------------------------------------------------------------------
; Page 2 screen offsets
;------------------------------------------------------------------------------
INSTR2_OFF_HDR      = 4*LOADING_ROW_BYTES+8
INSTR2_OFF_L1       = 24*LOADING_ROW_BYTES+2
INSTR2_OFF_L2       = 36*LOADING_ROW_BYTES+2
INSTR2_OFF_L3       = 48*LOADING_ROW_BYTES+2
INSTR2_OFF_L4       = 60*LOADING_ROW_BYTES+2
INSTR2_OFF_L5       = 76*LOADING_ROW_BYTES+2
INSTR2_OFF_L6       = 88*LOADING_ROW_BYTES+2
INSTR2_OFF_L7       = 100*LOADING_ROW_BYTES+2
INSTR2_OFF_L8       = 116*LOADING_ROW_BYTES+2
INSTR2_OFF_L9       = 128*LOADING_ROW_BYTES+2
INSTR2_OFF_L10      = 144*LOADING_ROW_BYTES+2
INSTR2_OFF_L11      = 156*LOADING_ROW_BYTES+2
INSTR2_OFF_L12      = 168*LOADING_ROW_BYTES+2
INSTR2_OFF_RET      = 192*LOADING_ROW_BYTES+11
INSTR2_OFF_RETTXT   = 192*LOADING_ROW_BYTES+12


;==============================================================================
; InstrPage1Setup  -  One-shot init for instructions page 1 (state INSTR_SETUP1)
;
; Clears DisplayScreen, blits page 1 text (engine overview), advances to INSTR_RUN1.
; cpTitle copper list remains active (installed by TitleSetup).
;
; To customise: replace the .str_* string data below with your own game text.
;   The CHAR_BLTString* routines draw 8x8 pixel characters:
;     CHAR_BLTString       = white
;     CHAR_BLTStringYellow = yellow
;     CHAR_BLTStringGreen  = green
;     CHAR_BLTStringRed    = red
;   Maximum ~38 characters per line at 8px each across a 320px screen.
;==============================================================================

InstrPage1Setup:
    WAITBLIT

    bsr         TS_FlattenSky           ; kill the aurora so background is solid black

    lea         DisplayScreen,a0
    move.l      #LOADING_ROW_BYTES*LOADING_HEIGHT,d7
    bsr         TurboClear

    lea         .str_hdr,a0
    lea         DisplayScreen+INSTR1_OFF_HDR,a1
    bsr         CHAR_BLTStringYellow

    lea         .str_l1,a0
    lea         DisplayScreen+INSTR1_OFF_L1,a1
    bsr         CHAR_BLTString

    lea         .str_l2,a0
    lea         DisplayScreen+INSTR1_OFF_L2,a1
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR1_OFF_L3,a1
    lea         .str_l3,a0
    bsr         CHAR_BLTStringGreen

    lea         .str_l4,a0
    lea         DisplayScreen+INSTR1_OFF_L4,a1
    bsr         CHAR_BLTString

    lea         .str_l5,a0
    lea         DisplayScreen+INSTR1_OFF_L5,a1
    bsr         CHAR_BLTString

    lea         .str_l6,a0
    lea         DisplayScreen+INSTR1_OFF_L6,a1
    bsr         CHAR_BLTString

    lea         .str_l7,a0
    lea         DisplayScreen+INSTR1_OFF_L7,a1
    bsr         CHAR_BLTString

    lea         .str_l8,a0
    lea         DisplayScreen+INSTR1_OFF_L8,a1
    bsr         CHAR_BLTString

    lea         .str_l9,a0
    lea         DisplayScreen+INSTR1_OFF_L9,a1
    bsr         CHAR_BLTString

    lea         .str_l10,a0
    lea         DisplayScreen+INSTR1_OFF_L10,a1
    bsr         CHAR_BLTString

    lea         .str_l11,a0
    lea         DisplayScreen+INSTR1_OFF_L11,a1
    bsr         CHAR_BLTString

    lea         .str_l12,a0
    lea         DisplayScreen+INSTR1_OFF_L12,a1
    bsr         CHAR_BLTString

    move.b      #'>',d2
    lea         DisplayScreen+INSTR1_OFF_NEXT,a1
    bsr         CHAR_BLTGreenChar
    lea         .str_next,a0
    bsr         CHAR_BLTString

    move.w      #INSTR_RUN1,GameStatus(a5)
    rts

; CUSTOMISE: Replace these strings with your own game description (null-terminated).
.str_hdr    dc.b    "AMIGA GAME ENGINE",0
.str_l1     dc.b    "WELCOME TO THE AMIGA GAME ENGINE",0
.str_l2     dc.b    "TEMPLATE - A FULLY WORKING 2D GAME.",0
.str_l3     dc.b    "THIS ENGINE INCLUDES:",0
.str_l4     dc.b    "- TILE-BASED LEVEL RENDERING",0
.str_l5     dc.b    "- PLAYER MOVEMENT AND ANIMATION",0
.str_l6     dc.b    "- ENEMY AI (FALLING AND FLOATING)",0
.str_l7     dc.b    "- HARDWARE SPRITES AND BLITTER",0
.str_l8     dc.b    "- ZX0 COMPRESSION FOR ASSETS",0
.str_l9     dc.b    "- PROTRACKER MUSIC SUPPORT",0
.str_l10    dc.b    "- TITLE AND LOADING SCREENS",0
.str_l11    dc.b    "- PAL AND NTSC COMPATIBLE",0
.str_l12    dc.b    "- OCS AND ECS CHIPSET SUPPORT",0
.str_next   dc.b    " NEXT",0
    even


;==============================================================================
; InstrPage1Run  -  Per-frame handler for instructions page 1 (state INSTR_RUN1)
;
; Waits for joystick FIRE or Return key, then advances to INSTR_SETUP2.
;==============================================================================

InstrPage1Run:
    PUSHALL

    bsr         UpdateControls
    move.b      ControlsTrigger(a5),d0

    btst        #CONTROLB_FIRE,d0
    bne         .advance

    lea         Keys,a0
    tst.b       KEY_RETURN(a0)
    beq         .no_advance
    clr.b       KEY_RETURN(a0)

.advance
    move.w      #INSTR_SETUP2,GameStatus(a5)

.no_advance
    POPALL
    rts


;==============================================================================
; InstrPage2Setup  -  One-shot init for instructions page 2 (state INSTR_SETUP2)
;
; Clears DisplayScreen, blits the developer customisation guide, advances to INSTR_RUN2.
;
; This page acts as an in-game README for anyone taking the engine forward.
; Replace the strings below with your game''s own controls/instructions once
; you no longer need the developer reference.
;==============================================================================

InstrPage2Setup:
    WAITBLIT

    bsr         TS_FlattenSky           ; keep sky flat black

    lea         DisplayScreen,a0
    move.l      #LOADING_ROW_BYTES*LOADING_HEIGHT,d7
    bsr         TurboClear

    lea         DisplayScreen+INSTR2_OFF_HDR,a1
    lea         .str_hdr,a0
    bsr         CHAR_BLTStringYellow

    lea         DisplayScreen+INSTR2_OFF_L1,a1
    lea         .str_sec1,a0
    bsr         CHAR_BLTStringGreen

    lea         .str_l1,a0
    lea         DisplayScreen+INSTR2_OFF_L2,a1
    bsr         CHAR_BLTString

    lea         .str_l2,a0
    lea         DisplayScreen+INSTR2_OFF_L3,a1
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR2_OFF_L4,a1
    lea         .str_sec2,a0
    bsr         CHAR_BLTStringGreen

    lea         .str_l3,a0
    lea         DisplayScreen+INSTR2_OFF_L5,a1
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR2_OFF_L6,a1
    lea         .str_sec3,a0
    bsr         CHAR_BLTStringGreen

    lea         .str_l4,a0
    lea         DisplayScreen+INSTR2_OFF_L7,a1
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR2_OFF_L8,a1
    lea         .str_sec4,a0
    bsr         CHAR_BLTStringGreen

    lea         .str_l5,a0
    lea         DisplayScreen+INSTR2_OFF_L9,a1
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR2_OFF_L10,a1
    lea         .str_sec5,a0
    bsr         CHAR_BLTStringGreen

    lea         .str_l6,a0
    lea         DisplayScreen+INSTR2_OFF_L11,a1
    bsr         CHAR_BLTString

    lea         .str_l7,a0
    lea         DisplayScreen+INSTR2_OFF_L12,a1
    bsr         CHAR_BLTString

    move.b      #'>',d2
    lea         DisplayScreen+INSTR2_OFF_RET,a1
    bsr         CHAR_BLTGreenChar
    lea         .str_ret,a0
    bsr         CHAR_BLTString

    move.w      #INSTR_RUN2,GameStatus(a5)
    rts

; CUSTOMISE: Replace with your game''s controls/story once the template is complete.
.str_hdr    dc.b    "HOW TO CUSTOMISE",0
.str_sec1   dc.b    "LEVELS:",0
.str_sec2   dc.b    "TILES:",0
.str_sec3   dc.b    "SPRITES:",0
.str_sec4   dc.b    "MUSIC:",0
.str_sec5   dc.b    "CODE:",0
.str_l1     dc.b    "EDIT ASSETS/LEVELS/LV_NNN.BYTES",0
.str_l2     dc.b    "88 BYTES (11X8 GRID), REBUILD BIN",0
.str_l3     dc.b    "REPLACE TILES_0 - KEEP 32 TILES",0
.str_l4     dc.b    "REPLACE ENEMIES_64X128.RAW",0
.str_l5     dc.b    "REPLACE ASSETS/MUSIC/*.MOD FILES",0
.str_l6     dc.b    "MAIN.ASM INCLUDES ALL SUBSYSTEMS",0
.str_l7     dc.b    "SEE INCLUDE/RESOURCES/ FOR MORE",0
.str_ret    dc.b    " RETURN TO TITLE",0
    even


;==============================================================================
; InstrPage2Run  -  Per-frame handler for instructions page 2 (state INSTR_RUN2)
;
; Waits for joystick FIRE or Return key, then returns to TITLE_SETUP.
;==============================================================================

InstrPage2Run:
    PUSHALL

    bsr         UpdateControls
    move.b      ControlsTrigger(a5),d0

    btst        #CONTROLB_FIRE,d0
    bne         .go_title

    lea         Keys,a0
    tst.b       KEY_RETURN(a0)
    beq         .no_title
    clr.b       KEY_RETURN(a0)

.go_title
    move.w      #TITLE_SETUP,GameStatus(a5)

.no_title
    POPALL
    rts
