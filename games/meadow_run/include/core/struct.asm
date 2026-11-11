;==============================================================================
; MEADOW RUN - STRUCTURES
; struct.asm  -  The LevelDef record that export_level.py writes for each level
;==============================================================================

                          rsreset
LevelDef_Background:      rs.l    1   ; background layer: word per cell (after the .map header)
LevelDef_Platform:        rs.l    1   ; platforms and ducklings
LevelDef_Foreground:      rs.l    1   ; foreground, drawn over Mia
LevelDef_GameMap:         rs.l    1   ; collision: byte per cell, CLASS_*
LevelDef_StartX:          rs.w    1   ; Mia's start: X of her body box
LevelDef_StartY:          rs.w    1   ; and Y of her sprite's top
LevelDef_TimeLimit:       rs.w    1   ; seconds to reach the signpost
LevelDef_Ducks:           rs.w    1   ; ducklings in the level
LevelDef_Sizeof:          rs.w    0
