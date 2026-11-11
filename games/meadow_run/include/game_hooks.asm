;==============================================================================
; AMIGA GAME ENGINE - MEADOW RUN
; game_hooks.asm  -  Every Game*Hook the engine can call, as empty stubs
;==============================================================================
;
; The engine never calls a game routine by its own name. Instead, at fixed
; points of its frame, level and undo pipelines it calls the hooks below
; (see engine/ENGINE_CONTRACT.md, section "Hooks"). The starter does not yet
; include the engine files that call most of these, so the stubs cost a few
; bytes and nothing else; fill one in when you include the subsystem that
; calls it. games/duck_rescue/include/game_hooks.asm is the worked example.
;
; A hook may be a routine (as here) or a binding equate that points the hook
; name at one of your own routines:  GameLogicHook = MyPlayerLogic
;
; Register convention: a5 = Variables base, a6 = CUSTOM chip base.
; Unless stated otherwise a hook may clobber d0-d7/a0-a4.
;==============================================================================

; --- Setup / level lifecycle (engine_main.asm, gamestatus.asm, levelutils.asm)
GameSetupHook:              rts     ; once per game start, after engine setup
GameLevelInitHook:          rts     ; end of LevelInit: reset per-level game state, fill pools
GameShowPlayerHook:         rts     ; draw the player at its current position (level reveal)
;==============================================================================
; GameLevelDoneHook  -  Check if level objective is met
;
; Out:      d3.w = 0 if level objective met, non-zero if still in progress
; Destroys: d3
;==============================================================================
GameLevelDoneHook:
    moveq       #1,d3
    rts

; --- Per-frame (gamestatus.asm GameRun), in call order
;==============================================================================
; GameUndoAllowedHook  -  Check if undo/rewind is permitted this frame
;
; Out:      d0.w = 0 if rewind allowed, non-zero if inhibited
; Destroys: d0
;==============================================================================
GameUndoAllowedHook:
    moveq       #0,d0
    rts
GameRestoreOverlapsHook:    rts     ; after TilemapDrawPlayer: re-blit entities the erase touched
GameDrawPriorityHook:       rts     ; d0/d1 = screen-Y slice: draw beam-raced entities in it
GameDrawHook:               rts     ; remaining blits, chasing the beam
GameLogicHook:              rts     ; after UpdateControls: player logic, collisions
GamePostLogicHook:          rts     ; after camera/water update: HUD, timers
GameActorPhaseHook:         rts     ; after AnimateEnemies, before TilemapDrawPushBlocks
GameDrawEntitiesHook:       rts     ; after TilemapDrawPushBlocks, before FlushDirtyTiles

; --- Pause / debug (pause_system.asm, debug_hud.asm, bob_compositor.asm)
GameUnpauseHook:            rts     ; pause banner or debug HUD erased: invalidate anything to redraw
;==============================================================================
; GameDebugCountHook  -  Return custom debug entity count for telemetry overlay
;
; Out:      d0.w = entity count
; Destroys: d0
;==============================================================================
GameDebugCountHook:
    moveq       #0,d0
    rts

; --- Undo / rewind (undo.asm). a0 = snapshot slot where stated; the engine
;     preserves a0 around every call. Extend the Snap_* struct in your own
;     struct file by including engine_snapshot.i first (see ENGINE_CONTRACT.md).
GameSnapshotSaveHook:       rts     ; copy game state into the slot at a0
GameUndoEraseHook:          rts     ; erase the game's on-screen entities before the restore
GameSnapshotRestoreHook:    rts     ; copy game state back out of the slot at a0
GameUndoRedrawHook:         rts     ; redraw the game's entities and HUD after the restore
