;==============================================================================
; STARTER GAME - GLOBAL VARIABLES
; variables.asm  -  Game Variable Block Layout in Fast RAM (RS layout)
;==============================================================================
;
; Extends the core AmigaGameEngine variable layout (engine_variables.i).
; This starter adds no fields of its own — a real game appends its own
; player/actor/entity state here, on the same rsreset chain, before
; closing with Variables_Sizeof. See ENGINE_CONTRACT.md section 2.
;
; Convention:
;   a5 = Variables base pointer throughout the entire program.
;   All fields are accessed as FieldName(a5).
;==============================================================================

    include    "engine_variables.i"

Variables_Sizeof:     rs.w    0               ; total size of Variables block in bytes
