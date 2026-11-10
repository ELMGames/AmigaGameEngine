;==============================================================================
; DUCK RESCUE
; instructions_text.asm  -  Gameplay page of the instructions screen
;==============================================================================
;
; engine/screens/instructions.asm draws page 3 from these tables: four
; section headings and ten body lines, null-terminated, in display order
; (contract binding, see engine/ENGINE_CONTRACT.md section 10).
;
; Destroys: none (preserves all registers)
;==============================================================================

GameInstructionsHeadings:
    dc.l    InstrGameplayHeading1
    dc.l    InstrGameplayHeading2
    dc.l    InstrGameplayHeading3
    dc.l    InstrGameplayHeading4

GameInstructionsText:
    dc.l    InstrGameplayLine1
    dc.l    InstrGameplayLine2
    dc.l    InstrGameplayLine3
    dc.l    InstrGameplayLine4
    dc.l    InstrGameplayLine5
    dc.l    InstrGameplayLine6
    dc.l    InstrGameplayLine7
    dc.l    InstrGameplayLine8
    dc.l    InstrGameplayLine9
    dc.l    InstrGameplayLine10

InstrGameplayLine1  dc.b    "JOY / CURSORS : RUN LEFT & RIGHT",0
InstrGameplayLine2  dc.b    "UP / DOWN     : CLIMB LADDERS",0
InstrGameplayLine3  dc.b    "FIRE / SPACE  : ATTACK / STUN FOES",0
InstrGameplayLine4  dc.b    "PRESS F9 OR HOLD FIRE TO REWIND MOVE",0
InstrGameplayLine5  dc.b    "CIRCULAR BUFFER RESTORES FULL STATE",0
InstrGameplayLine6  dc.b    "PUSH BLOCKS TO CREATE SAFE PATHS",0
InstrGameplayLine7  dc.b    "ESCAPE RISING WATER & REFILL OXYGEN",0
InstrGameplayLine8  dc.b    "RESCUE ALL DUCKS TO COMPLETE LEVEL",0
InstrGameplayLine9  dc.b    "P: PAUSE GAME       ESC: QUIT TO TITLE",0
InstrGameplayLine10  dc.b    "50 FPS PAL DISPLAY + PROTRACKER SOUND",0
InstrGameplayHeading1  dc.b    "CONTROLS & MOVEMENT:",0
InstrGameplayHeading2  dc.b    "REWIND / UNDO (VHS EFFECT):",0
InstrGameplayHeading3  dc.b    "INTERACTION & HAZARDS:",0
InstrGameplayHeading4  dc.b    "OBJECTIVE & GAME KEYS:",0
    even
