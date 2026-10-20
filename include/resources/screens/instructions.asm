;==============================================================================
; AMIGA GAME ENGINE
; instructions.asm  -  Four-page in-game guide & controls screen (states 11-16, 25-26)
;==============================================================================
;
; State 11 (INSTR_SETUP1): InstrPage1Setup -- Book & ELMGames.com -> INSTR_RUN1
; State 12 (INSTR_RUN1):   InstrPage1Run  -- FIRE/RETURN -> INSTR_SETUP2, ESC -> TITLE_SETUP
; State 13 (INSTR_SETUP2): InstrPage2Setup -- Level Design & Dev Guide -> INSTR_RUN2
; State 14 (INSTR_RUN2):   InstrPage2Run  -- FIRE/RETURN -> INSTR_SETUP3, ESC -> TITLE_SETUP
; State 15 (INSTR_SETUP3): InstrPage3Setup -- Gameplay, Controls & Keys -> INSTR_RUN3
; State 16 (INSTR_RUN3):   InstrPage3Run  -- FIRE/RETURN -> INSTR_SETUP4, ESC -> TITLE_SETUP
; State 25 (INSTR_SETUP4): InstrPage4Setup -- Developer & Debug Keys -> INSTR_RUN4
; State 26 (INSTR_RUN4):   InstrPage4Run  -- FIRE/RETURN/ESC -> TITLE_SETUP
;
; Reuses cpTitle copper list (already installed by TitleSetup).
; Text is rendered to DisplayScreen via CHAR_BLTString / CHAR_BLTOneChar.
; Screen: 320x200, 5 bitplanes interleaved, LOADING_ROW_BYTES stride.
;
; ===========================================================================
; IN-GAME GUIDE & REFERENCE
; ===========================================================================
;
; Page 1 -- "BUILDING AN AMIGA GAME ENGINE"
;   Companion book available in Hardback via Amazon.
;   Architecture, custom chips (Copper, Blitter, Paula), 68000 assembly.
;   Open source codebase available to download via ELMGames.com website.
;
; Page 2 -- "LEVEL DESIGN & DEV GUIDE"
;   Visual level design using Tiled Map Editor (assets/Levels/Level_XX/*.tmx).
;   6 Map layers: Scenery, Platforms, Ladders, Entities, Foreground, Water.
;   Tileset: Modular TSX tilesets (16x16 pixel tiles).
;   Python export tool: tools/export_level.py & tools/generate_levels.py.
;   Build system: vasmm68k_mot via ./build.ps1 -> uae/dh0/main.
;
; Page 3 -- "GAMEPLAY & GAME KEYS"
;   Controls for movement, climbing ladders, cane attack.
;   Live move-by-move undo / rewind system (F9 / Hold Fire).
;   Block pushing, rising water, oxygen management, stunning foes.
;   Objective: rescue all ducks to complete the level.
;   Game keys: P - Pause, ESC - Quit to Title.
;
; Page 4 -- "DEVELOPER & DEBUG KEYS"
;   F5: Toggle Debug Mode (enables debug shortcuts).
;   F1 / F2: Warp to Previous / Next level (in Debug Mode).
;   S / A: Toggle Slow Mode & frame-by-frame single-step execution.
;   D: Toggle live HUD diagnostic metrics overlay.
;   F3: Toggle CPU / Blitter raster timing bar.
;   F4: Instant victory / Game Complete sequence.
;   F9: Undo move / VHS rewind effect.
;   P: Pause gameplay with Copper screen desaturation.
;==============================================================================

;------------------------------------------------------------------------------
; Page 1 screen offsets  (row_y * LOADING_ROW_BYTES + byte_x)
; "BUILDING AN AMIGA GAME ENGINE" (Book & Architecture Reference)
;------------------------------------------------------------------------------
INSTR1_OFF_HDR      = 4*LOADING_ROW_BYTES+5     ; "BUILDING AN AMIGA GAME ENGINE" (centred)
INSTR1_OFF_S1       = 18*LOADING_ROW_BYTES+2    ; "OFFICIAL COMPANION BOOK:"
INSTR1_OFF_L1       = 29*LOADING_ROW_BYTES+2    ; "LEARN HOW THIS ENGINE WAS DEVELOPED"
INSTR1_OFF_L2       = 40*LOADING_ROW_BYTES+2    ; "FROM SCRATCH IN 68000 ASSEMBLY."
INSTR1_OFF_S2       = 55*LOADING_ROW_BYTES+2    ; "AVAILABLE ON AMAZON:"
INSTR1_OFF_L3       = 66*LOADING_ROW_BYTES+2    ; "'BUILDING AN AMIGA GAME ENGINE'"
INSTR1_OFF_L4       = 77*LOADING_ROW_BYTES+2    ; "HARDBACK EDITION VIA AMAZON"
INSTR1_OFF_S3       = 92*LOADING_ROW_BYTES+2    ; "HARDWARE & SYSTEMS COVERED:"
INSTR1_OFF_L5       = 103*LOADING_ROW_BYTES+2   ; "COPPER, BLITTER, HW SPRITES & DMA"
INSTR1_OFF_L6       = 114*LOADING_ROW_BYTES+2   ; "TILE MAPS, BOB MASKS, AUDIO & REWIND"
INSTR1_OFF_L7       = 125*LOADING_ROW_BYTES+2   ; "FSM PHYSICS, CYCLE TIMING & TAKEOVER"
INSTR1_OFF_S4       = 140*LOADING_ROW_BYTES+2   ; "CODEBASE:"
INSTR1_OFF_L8       = 151*LOADING_ROW_BYTES+2   ; "DOWNLOAD COMPLETE SOURCE CODE AT:"
INSTR1_OFF_L9       = 162*LOADING_ROW_BYTES+2   ; "ELMGAMES.COM/AMIGA"
INSTR1_OFF_NEXT     = 186*LOADING_ROW_BYTES+3
INSTR1_OFF_NEXTTXT  = 186*LOADING_ROW_BYTES+5

;------------------------------------------------------------------------------
; Page 2 screen offsets
; "LEVEL DESIGN & DEV GUIDE"
;------------------------------------------------------------------------------
INSTR2_OFF_HDR      = 4*LOADING_ROW_BYTES+8     ; "LEVEL DESIGN & DEV GUIDE" (centred)
INSTR2_OFF_S1       = 18*LOADING_ROW_BYTES+2    ; "TILED MAP EDITOR (.TMX):"
INSTR2_OFF_L1       = 29*LOADING_ROW_BYTES+2    ; "EDIT ASSETS/LEVELS/LEVEL_XX/*.TMX"
INSTR2_OFF_L2       = 40*LOADING_ROW_BYTES+2    ; "DESIGN VISUALLY IN TILED MAP EDITOR"
INSTR2_OFF_S2       = 54*LOADING_ROW_BYTES+2    ; "MAP LAYERS & TILESET:"
INSTR2_OFF_L3       = 65*LOADING_ROW_BYTES+2    ; "6 LAYERS: SCENERY, PLATFORMS, WATER,"
INSTR2_OFF_L4       = 76*LOADING_ROW_BYTES+2    ; "LADDERS, FOREGROUND & ENTITY OBJECTS"
INSTR2_OFF_L5       = 87*LOADING_ROW_BYTES+2    ; "USES MODULAR TSX TILESETS (16X16 PX)"
INSTR2_OFF_S3       = 101*LOADING_ROW_BYTES+2   ; "PYTHON EXPORT PIPELINE:"
INSTR2_OFF_L6       = 112*LOADING_ROW_BYTES+2   ; "RUN TOOLS/GENERATE_LEVELS.PY OR:"
INSTR2_OFF_L7       = 123*LOADING_ROW_BYTES+2   ; "PYTHON TOOLS/EXPORT_LEVEL.PY <MAP>"
INSTR2_OFF_L8       = 134*LOADING_ROW_BYTES+2   ; "EXPORTS COLLISION BINS & ENTITY ASM"
INSTR2_OFF_S4       = 148*LOADING_ROW_BYTES+2   ; "BUILDING & RUNNING:"
INSTR2_OFF_L9       = 159*LOADING_ROW_BYTES+2   ; "RUN ./BUILD.PS1 TO COMPILE VASM ASM"
INSTR2_OFF_L10      = 170*LOADING_ROW_BYTES+2   ; "OUTPUT: UAE/DH0/MAIN (50 FPS PAL)"
INSTR2_OFF_NEXT     = 186*LOADING_ROW_BYTES+4
INSTR2_OFF_NEXTTXT  = 186*LOADING_ROW_BYTES+6

;------------------------------------------------------------------------------
; Page 3 screen offsets
; "GAMEPLAY & GAME KEYS"
;------------------------------------------------------------------------------
INSTR3_OFF_HDR      = 4*LOADING_ROW_BYTES+10    ; "GAMEPLAY & GAME KEYS" (centred)
INSTR3_OFF_S1       = 18*LOADING_ROW_BYTES+2    ; "CONTROLS & MOVEMENT:"
INSTR3_OFF_L1       = 29*LOADING_ROW_BYTES+2    ; "JOY / CURSORS : RUN LEFT & RIGHT"
INSTR3_OFF_L2       = 40*LOADING_ROW_BYTES+2    ; "UP / DOWN     : CLIMB LADDERS"
INSTR3_OFF_L3       = 51*LOADING_ROW_BYTES+2    ; "FIRE / SPACE  : ATTACK / STUN FOES"
INSTR3_OFF_S2       = 65*LOADING_ROW_BYTES+2    ; "REWIND / UNDO (VHS EFFECT):"
INSTR3_OFF_L4       = 76*LOADING_ROW_BYTES+2    ; "PRESS F9 OR HOLD FIRE TO REWIND MOVE"
INSTR3_OFF_L5       = 87*LOADING_ROW_BYTES+2    ; "CIRCULAR BUFFER RESTORES FULL STATE"
INSTR3_OFF_S3       = 101*LOADING_ROW_BYTES+2   ; "INTERACTION & HAZARDS:"
INSTR3_OFF_L6       = 112*LOADING_ROW_BYTES+2   ; "PUSH BLOCKS TO CREATE SAFE PATHS"
INSTR3_OFF_L7       = 123*LOADING_ROW_BYTES+2   ; "ESCAPE RISING WATER & REFILL OXYGEN"
INSTR3_OFF_S4       = 137*LOADING_ROW_BYTES+2   ; "OBJECTIVE & GAME KEYS:"
INSTR3_OFF_L8       = 148*LOADING_ROW_BYTES+2   ; "RESCUE ALL DUCKS TO COMPLETE LEVEL"
INSTR3_OFF_L9       = 159*LOADING_ROW_BYTES+2   ; "P: PAUSE GAME       ESC: QUIT TO TITLE"
INSTR3_OFF_L10      = 170*LOADING_ROW_BYTES+2   ; "50 FPS PAL DISPLAY + PROTRACKER SOUND"
INSTR3_OFF_NEXT     = 186*LOADING_ROW_BYTES+3
INSTR3_OFF_NEXTTXT  = 186*LOADING_ROW_BYTES+5

;------------------------------------------------------------------------------
; Page 4 screen offsets
; "DEVELOPER & DEBUG KEYS"
;------------------------------------------------------------------------------
INSTR4_OFF_HDR      = 4*LOADING_ROW_BYTES+9     ; "DEVELOPER & DEBUG KEYS" (centred)
INSTR4_OFF_S1       = 18*LOADING_ROW_BYTES+2    ; "DEBUG MODE & LEVEL WARP:"
INSTR4_OFF_L1       = 29*LOADING_ROW_BYTES+2    ; "F5      : TOGGLE DEBUG MODE"
INSTR4_OFF_L2       = 40*LOADING_ROW_BYTES+2    ; "F1 / F2 : WARP TO PREV / NEXT LEVEL"
INSTR4_OFF_S2       = 55*LOADING_ROW_BYTES+2    ; "FRAME STEPPER & SLOW MOTION:"
INSTR4_OFF_L3       = 66*LOADING_ROW_BYTES+2    ; "S       : TOGGLE SLOW MODE STEPPER"
INSTR4_OFF_L4       = 77*LOADING_ROW_BYTES+2    ; "A       : STEP 1 FRAME (HOLD TO RUN)"
INSTR4_OFF_S3       = 92*LOADING_ROW_BYTES+2    ; "DIAGNOSTICS & PROFILING:"
INSTR4_OFF_L5       = 103*LOADING_ROW_BYTES+2   ; "D       : TOGGLE HUD OVERLAY METRICS"
INSTR4_OFF_L6       = 114*LOADING_ROW_BYTES+2   ; "F3      : TOGGLE CPU RASTER TIME BAR"
INSTR4_OFF_S4       = 129*LOADING_ROW_BYTES+2   ; "SHORTCUTS & CHEATS:"
INSTR4_OFF_L7       = 140*LOADING_ROW_BYTES+2   ; "F4      : INSTANT GAME COMPLETE SCREEN"
INSTR4_OFF_L8       = 151*LOADING_ROW_BYTES+2   ; "F9      : INSTANT UNDO MOVE / REWIND"
INSTR4_OFF_L9       = 162*LOADING_ROW_BYTES+2   ; "P       : PAUSE GAME WITH COPPER DIM"
INSTR4_OFF_RET      = 186*LOADING_ROW_BYTES+5
INSTR4_OFF_RETTXT   = 186*LOADING_ROW_BYTES+7


;==============================================================================
; InstrPage1Setup  -  One-shot init for instructions page 1 (state INSTR_SETUP1)
;
; Clears DisplayScreen, blits page 1 text (book reference), advances to INSTR_RUN1.
; cpTitle copper list remains active (installed by TitleSetup).
;==============================================================================

InstrPage1Setup:
    WAITBLIT

    bsr         TS_FlattenSky           ; kill the aurora so background is solid black

    lea         DisplayScreen,a0
    move.l      #LOADING_ROW_BYTES*LOADING_HEIGHT,d7
    bsr         TurboClear

    ; Title
    lea         DisplayScreen+INSTR1_OFF_HDR,a1
    lea         .str_hdr,a0
    bsr         CHAR_BLTStringYellow

    ; Section 1: Official Companion Book
    lea         DisplayScreen+INSTR1_OFF_S1,a1
    lea         .str_s1,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR1_OFF_L1,a1
    lea         .str_l1,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR1_OFF_L2,a1
    lea         .str_l2,a0
    bsr         CHAR_BLTString

    ; Section 2: Available on Amazon
    lea         DisplayScreen+INSTR1_OFF_S2,a1
    lea         .str_s2,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR1_OFF_L3,a1
    lea         .str_l3,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR1_OFF_L4,a1
    lea         .str_l4,a0
    bsr         CHAR_BLTString

    ; Section 3: Hardware & Systems Covered
    lea         DisplayScreen+INSTR1_OFF_S3,a1
    lea         .str_s3,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR1_OFF_L5,a1
    lea         .str_l5,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR1_OFF_L6,a1
    lea         .str_l6,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR1_OFF_L7,a1
    lea         .str_l7,a0
    bsr         CHAR_BLTString

    ; Section 4: Codebase
    lea         DisplayScreen+INSTR1_OFF_S4,a1
    lea         .str_s4,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR1_OFF_L8,a1
    lea         .str_l8,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR1_OFF_L9,a1
    lea         .str_l9,a0
    bsr         CHAR_BLTString

    ; Footer prompt
    move.b      #'>',d2
    lea         DisplayScreen+INSTR1_OFF_NEXT,a1
    bsr         CHAR_BLTGreenChar
    lea         DisplayScreen+INSTR1_OFF_NEXTTXT,a1
    lea         .str_next,a0
    bsr         CHAR_BLTString

    move.w      #INSTR_RUN1,GameStatus(a5)
    rts

.str_hdr    dc.b    "BUILDING AN AMIGA GAME ENGINE",0
.str_s1     dc.b    "OFFICIAL COMPANION BOOK:",0
.str_l1     dc.b    "LEARN HOW THIS ENGINE WAS DEVELOPED",0
.str_l2     dc.b    "USING 68000 ASSEMBLY",0
.str_s2     dc.b    "AVAILABLE ON AMAZON:",0
.str_l3     dc.b    "'BUILDING AN AMIGA GAME ENGINE'",0
.str_l4     dc.b    "HARDBACK EDITION VIA AMAZON",0
.str_s3     dc.b    "HARDWARE & SYSTEMS COVERED:",0
.str_l5     dc.b    "COPPER, BLITTER, HW SPRITES & DMA",0
.str_l6     dc.b    "TILE MAPS, BOB MASKS, AUDIO & REWIND",0
.str_l7     dc.b    "FSM PHYSICS, CYCLE TIMING & TAKEOVER",0
.str_s4     dc.b    "CODEBASE:",0
.str_l8     dc.b    "DOWNLOAD COMPLETE SOURCE CODE AT:",0
.str_l9     dc.b    "ELMGAMES.COM/AMIGA",0
.str_next   dc.b    "PRESS FIRE FOR LEVEL DESIGN GUIDE",0
    even


;==============================================================================
; InstrPage1Run  -  Per-frame handler for instructions page 1 (state INSTR_RUN1)
;
; Waits for joystick FIRE or Return key, then advances to INSTR_SETUP2.
; ESC returns immediately to TITLE_SETUP.
;==============================================================================

InstrPage1Run:
    PUSHALL

    bsr         UpdateControls
    move.b      ControlsTrigger(a5),d0

    btst        #CONTROLB_FIRE,d0
    bne         .advance

    lea         Keys,a0
    tst.b       KEY_ESC(a0)
    beq         .no_esc
    clr.b       KEY_ESC(a0)
    move.w      #TITLE_SETUP,GameStatus(a5)
    bra         .no_advance

.no_esc
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
; Clears DisplayScreen, blits the level creation guide, advances to INSTR_RUN2.
;==============================================================================

InstrPage2Setup:
    WAITBLIT

    bsr         TS_FlattenSky           ; keep sky flat black

    lea         DisplayScreen,a0
    move.l      #LOADING_ROW_BYTES*LOADING_HEIGHT,d7
    bsr         TurboClear

    ; Title
    lea         DisplayScreen+INSTR2_OFF_HDR,a1
    lea         .str_hdr,a0
    bsr         CHAR_BLTStringYellow

    ; Section 1: Tiled Map Editor
    lea         DisplayScreen+INSTR2_OFF_S1,a1
    lea         .str_s1,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR2_OFF_L1,a1
    lea         .str_l1,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR2_OFF_L2,a1
    lea         .str_l2,a0
    bsr         CHAR_BLTString

    ; Section 2: Map Layers & Tileset
    lea         DisplayScreen+INSTR2_OFF_S2,a1
    lea         .str_s2,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR2_OFF_L3,a1
    lea         .str_l3,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR2_OFF_L4,a1
    lea         .str_l4,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR2_OFF_L5,a1
    lea         .str_l5,a0
    bsr         CHAR_BLTString

    ; Section 3: Python Export Pipeline
    lea         DisplayScreen+INSTR2_OFF_S3,a1
    lea         .str_s3,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR2_OFF_L6,a1
    lea         .str_l6,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR2_OFF_L7,a1
    lea         .str_l7,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR2_OFF_L8,a1
    lea         .str_l8,a0
    bsr         CHAR_BLTString

    ; Section 4: Building & Running
    lea         DisplayScreen+INSTR2_OFF_S4,a1
    lea         .str_s4,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR2_OFF_L9,a1
    lea         .str_l9,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR2_OFF_L10,a1
    lea         .str_l10,a0
    bsr         CHAR_BLTString

    ; Footer prompt
    move.b      #'>',d2
    lea         DisplayScreen+INSTR2_OFF_NEXT,a1
    bsr         CHAR_BLTGreenChar
    lea         DisplayScreen+INSTR2_OFF_NEXTTXT,a1
    lea         .str_next,a0
    bsr         CHAR_BLTString

    move.w      #INSTR_RUN2,GameStatus(a5)
    rts

.str_hdr    dc.b    "LEVEL DESIGN & DEV GUIDE",0
.str_s1     dc.b    "TILED MAP EDITOR (.TMX):",0
.str_l1     dc.b    "EDIT ASSETS/LEVELS/LEVEL_XX/*.TMX",0
.str_l2     dc.b    "DESIGN VISUALLY IN TILED MAP EDITOR",0
.str_s2     dc.b    "MAP LAYERS & TILESET:",0
.str_l3     dc.b    "6 LAYERS: SCENERY, PLATFORMS, WATER,",0
.str_l4     dc.b    "LADDERS, FOREGROUND & ENTITY OBJECTS",0
.str_l5     dc.b    "USES MODULAR TSX TILESETS (16X16 PX)",0
.str_s3     dc.b    "PYTHON EXPORT PIPELINE:",0
.str_l6     dc.b    "RUN TOOLS/GENERATE_LEVELS.PY OR:",0
.str_l7     dc.b    "PYTHON TOOLS/EXPORT_LEVEL.PY <MAP>",0
.str_l8     dc.b    "EXPORTS COLLISION BINS & ENTITY ASM",0
.str_s4     dc.b    "BUILDING & RUNNING:",0
.str_l9     dc.b    "RUN ./BUILD.PS1 TO COMPILE VASM ASM",0
.str_l10    dc.b    "OUTPUT: UAE/DH0/MAIN (50 FPS PAL)",0
.str_next   dc.b    "PRESS FIRE FOR CONTROLS & KEYS",0
    even


;==============================================================================
; InstrPage2Run  -  Per-frame handler for instructions page 2 (state INSTR_RUN2)
;
; Waits for joystick FIRE or Return key, then advances to INSTR_SETUP3.
; ESC returns immediately to TITLE_SETUP.
;==============================================================================

InstrPage2Run:
    PUSHALL

    bsr         UpdateControls
    move.b      ControlsTrigger(a5),d0

    btst        #CONTROLB_FIRE,d0
    bne         .advance

    lea         Keys,a0
    tst.b       KEY_ESC(a0)
    beq         .no_esc
    clr.b       KEY_ESC(a0)
    move.w      #TITLE_SETUP,GameStatus(a5)
    bra         .no_advance

.no_esc
    tst.b       KEY_RETURN(a0)
    beq         .no_advance
    clr.b       KEY_RETURN(a0)

.advance
    move.w      #INSTR_SETUP3,GameStatus(a5)

.no_advance
    POPALL
    rts


;==============================================================================
; InstrPage3Setup  -  One-shot init for instructions page 3 (state INSTR_SETUP3)
;
; Clears DisplayScreen, blits page 3 text (gameplay, controls & keys), advances to INSTR_RUN3.
;==============================================================================

InstrPage3Setup:
    WAITBLIT

    bsr         TS_FlattenSky           ; keep sky flat black

    lea         DisplayScreen,a0
    move.l      #LOADING_ROW_BYTES*LOADING_HEIGHT,d7
    bsr         TurboClear

    ; Title
    lea         DisplayScreen+INSTR3_OFF_HDR,a1
    lea         .str_hdr,a0
    bsr         CHAR_BLTStringYellow

    ; Section 1: Controls & Movement
    lea         DisplayScreen+INSTR3_OFF_S1,a1
    lea         .str_s1,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR3_OFF_L1,a1
    lea         .str_l1,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR3_OFF_L2,a1
    lea         .str_l2,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR3_OFF_L3,a1
    lea         .str_l3,a0
    bsr         CHAR_BLTString

    ; Section 2: Rewind / Undo
    lea         DisplayScreen+INSTR3_OFF_S2,a1
    lea         .str_s2,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR3_OFF_L4,a1
    lea         .str_l4,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR3_OFF_L5,a1
    lea         .str_l5,a0
    bsr         CHAR_BLTString

    ; Section 3: Interaction & Hazards
    lea         DisplayScreen+INSTR3_OFF_S3,a1
    lea         .str_s3,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR3_OFF_L6,a1
    lea         .str_l6,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR3_OFF_L7,a1
    lea         .str_l7,a0
    bsr         CHAR_BLTString

    ; Section 4: Objective & Game Keys
    lea         DisplayScreen+INSTR3_OFF_S4,a1
    lea         .str_s4,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR3_OFF_L8,a1
    lea         .str_l8,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR3_OFF_L9,a1
    lea         .str_l9,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR3_OFF_L10,a1
    lea         .str_l10,a0
    bsr         CHAR_BLTString

    ; Footer prompt
    move.b      #'>',d2
    lea         DisplayScreen+INSTR3_OFF_NEXT,a1
    bsr         CHAR_BLTGreenChar
    lea         DisplayScreen+INSTR3_OFF_NEXTTXT,a1
    lea         .str_next,a0
    bsr         CHAR_BLTString

    move.w      #INSTR_RUN3,GameStatus(a5)
    rts

.str_hdr    dc.b    "GAMEPLAY & GAME KEYS",0
.str_s1     dc.b    "CONTROLS & MOVEMENT:",0
.str_l1     dc.b    "JOY / CURSORS : RUN LEFT & RIGHT",0
.str_l2     dc.b    "UP / DOWN     : CLIMB LADDERS",0
.str_l3     dc.b    "FIRE / SPACE  : ATTACK / STUN FOES",0
.str_s2     dc.b    "REWIND / UNDO (VHS EFFECT):",0
.str_l4     dc.b    "PRESS F9 OR HOLD FIRE TO REWIND MOVE",0
.str_l5     dc.b    "CIRCULAR BUFFER RESTORES FULL STATE",0
.str_s3     dc.b    "INTERACTION & HAZARDS:",0
.str_l6     dc.b    "PUSH BLOCKS TO CREATE SAFE PATHS",0
.str_l7     dc.b    "ESCAPE RISING WATER & REFILL OXYGEN",0
.str_s4     dc.b    "OBJECTIVE & GAME KEYS:",0
.str_l8     dc.b    "RESCUE ALL DUCKS TO COMPLETE LEVEL",0
.str_l9     dc.b    "P: PAUSE GAME       ESC: QUIT TO TITLE",0
.str_l10    dc.b    "50 FPS PAL DISPLAY + PROTRACKER SOUND",0
.str_next   dc.b    "PRESS FIRE FOR DEBUG KEYS GUIDE",0
    even


;==============================================================================
; InstrPage3Run  -  Per-frame handler for instructions page 3 (state INSTR_RUN3)
;
; Waits for joystick FIRE or Return key, then advances to INSTR_SETUP4.
; ESC returns immediately to TITLE_SETUP.
;==============================================================================

InstrPage3Run:
    PUSHALL

    bsr         UpdateControls
    move.b      ControlsTrigger(a5),d0

    btst        #CONTROLB_FIRE,d0
    bne         .advance

    lea         Keys,a0
    tst.b       KEY_ESC(a0)
    beq         .no_esc
    clr.b       KEY_ESC(a0)
    move.w      #TITLE_SETUP,GameStatus(a5)
    bra         .no_advance

.no_esc
    tst.b       KEY_RETURN(a0)
    beq         .no_advance
    clr.b       KEY_RETURN(a0)

.advance
    move.w      #INSTR_SETUP4,GameStatus(a5)

.no_advance
    POPALL
    rts


;==============================================================================
; InstrPage4Setup  -  One-shot init for instructions page 4 (state INSTR_SETUP4)
;
; Clears DisplayScreen, blits developer & debug keys summary, advances to INSTR_RUN4.
;==============================================================================

InstrPage4Setup:
    WAITBLIT

    bsr         TS_FlattenSky           ; keep sky flat black

    lea         DisplayScreen,a0
    move.l      #LOADING_ROW_BYTES*LOADING_HEIGHT,d7
    bsr         TurboClear

    ; Title
    lea         DisplayScreen+INSTR4_OFF_HDR,a1
    lea         .str_hdr,a0
    bsr         CHAR_BLTStringYellow

    ; Section 1: Debug Mode & Level Warp
    lea         DisplayScreen+INSTR4_OFF_S1,a1
    lea         .str_s1,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR4_OFF_L1,a1
    lea         .str_l1,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR4_OFF_L2,a1
    lea         .str_l2,a0
    bsr         CHAR_BLTString

    ; Section 2: Frame Stepper & Slow Motion
    lea         DisplayScreen+INSTR4_OFF_S2,a1
    lea         .str_s2,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR4_OFF_L3,a1
    lea         .str_l3,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR4_OFF_L4,a1
    lea         .str_l4,a0
    bsr         CHAR_BLTString

    ; Section 3: Diagnostics & Profiling
    lea         DisplayScreen+INSTR4_OFF_S3,a1
    lea         .str_s3,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR4_OFF_L5,a1
    lea         .str_l5,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR4_OFF_L6,a1
    lea         .str_l6,a0
    bsr         CHAR_BLTString

    ; Section 4: Shortcuts & Cheats
    lea         DisplayScreen+INSTR4_OFF_S4,a1
    lea         .str_s4,a0
    bsr         CHAR_BLTStringGreen

    lea         DisplayScreen+INSTR4_OFF_L7,a1
    lea         .str_l7,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR4_OFF_L8,a1
    lea         .str_l8,a0
    bsr         CHAR_BLTString

    lea         DisplayScreen+INSTR4_OFF_L9,a1
    lea         .str_l9,a0
    bsr         CHAR_BLTString

    ; Footer prompt
    move.b      #'>',d2
    lea         DisplayScreen+INSTR4_OFF_RET,a1
    bsr         CHAR_BLTGreenChar
    lea         DisplayScreen+INSTR4_OFF_RETTXT,a1
    lea         .str_ret,a0
    bsr         CHAR_BLTString

    move.w      #INSTR_RUN4,GameStatus(a5)
    rts

.str_hdr    dc.b    "DEVELOPER & DEBUG KEYS",0
.str_s1     dc.b    "DEBUG MODE & LEVEL WARP:",0
.str_l1     dc.b    "F5      : TOGGLE DEBUG MODE",0
.str_l2     dc.b    "F1 / F2 : WARP TO PREV / NEXT LEVEL",0
.str_s2     dc.b    "FRAME STEPPER & SLOW MOTION:",0
.str_l3     dc.b    "S       : TOGGLE SLOW MODE STEPPER",0
.str_l4     dc.b    "A       : STEP 1 FRAME (HOLD TO RUN)",0
.str_s3     dc.b    "DIAGNOSTICS & PROFILING:",0
.str_l5     dc.b    "D       : TOGGLE HUD OVERLAY METRICS",0
.str_l6     dc.b    "F3      : TOGGLE CPU RASTER TIME BAR",0
.str_s4     dc.b    "SHORTCUTS & CHEATS:",0
.str_l7     dc.b    "F4      : INSTANT GAME COMPLETE SCREEN",0
.str_l8     dc.b    "F9      : INSTANT UNDO MOVE / REWIND",0
.str_l9     dc.b    "P       : PAUSE GAME WITH COPPER DIM",0
.str_ret    dc.b    "PRESS FIRE TO RETURN TO TITLE",0
    even


;==============================================================================
; InstrPage4Run  -  Per-frame handler for instructions page 4 (state INSTR_RUN4)
;
; Waits for joystick FIRE, Return, or ESC key, then returns to TITLE_SETUP.
;==============================================================================

InstrPage4Run:
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
