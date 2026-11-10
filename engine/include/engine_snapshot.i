;==============================================================================
; AMIGA GAME ENGINE
; engine_snapshot.i  -  Base layout of one undo/rewind snapshot slot
;==============================================================================
;
; engine/gameplay/undo.asm serialises the engine-owned level state into these
; fields. A game INCLUDEs this file at the top of its own snapshot struct,
; appends whatever state its GameSnapshotSaveHook/GameSnapshotRestoreHook
; copy, and closes the struct with Snap_Sizeof (see games/duck_rescue/
; include/core/struct.asm). SnapshotBuffer must hold UNDO_BUFFER_SIZE slots.
;==============================================================================

                          rsreset
Snap_Map:                 rs.b    MAX_GAME_MAP_SIZE  ; GameMap copy (collision / block ids)
Snap_ActorCount:          rs.w    1   ; actor slots saved (0..TotalActorCount)
Snap_Actors:              rs.b    MAX_ACTIVE_CRATES*SNAP_ACTOR_WORDS*2 ; X,Y,Status,Type,SpriteOffset,Static per slot
Snap_WaterPixelY:         rs.w    1   ; rising water effect: surface scanline
Snap_WaterCurrentRow:     rs.w    1   ; rising water effect: surface tile row
Snap_WaterSubTick:        rs.w    1   ; rising water effect: fractional accumulator
Snap_PlayerSubmerged:     rs.w    1   ; rising water effect: head-underwater flag
