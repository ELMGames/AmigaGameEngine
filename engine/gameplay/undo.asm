
;==============================================================================
; AMIGA GAME ENGINE
; undo.asm  -  Move Rewind / Undo Snapshot System (engine feature)
;==============================================================================
;
; Circular snapshot ring buffer allowing the player to rewind up to
; UNDO_BUFFER_SIZE-1 completed moves. Pressing F9 (or VHS rewind trigger)
; restores the complete game state from one slot back.
;
; Buffer model (head = next slot to write, 0-based ring):
;   TakeSnapshot : write slot[head], head = (head+1) & mask, count = min(count+1, SIZE)
;   UndoMove     : need count>=2; count--; head=(head-1)&mask; restore slot[(head-1)&mask]
;
; What the engine serialises itself (engine_snapshot.i):
;   1. GameMap: complete collision and geometry map (CurrentMapSize bytes).
;   2. Dynamic actors: pushable blocks and falling obstacles (TotalActorCount).
;   3. Rising water effect: surface scanline, row, sub-tick, submerged flag.
; Everything else is the game's: it extends the Snap_* struct and implements
;   GameSnapshotSaveHook     (a0 = slot)  copy game state into the slot
;   GameUndoEraseHook                     erase the game's on-screen entities
;   GameSnapshotRestoreHook  (a0 = slot)  copy game state back out of the slot
;   GameUndoRedrawHook                    redraw the game's entities + HUD
; Each hook may clobber d0-d7/a1-a4; the engine preserves a0 around them.
;
; Rewind & Restoration Pipeline (UndoMove):
;   1. Erase: TilemapErasePlayer, GameUndoEraseHook, then every live actor.
;   2. Memory unpack: GameMap, Actors, engine volatile state, then
;      GameSnapshotRestoreHook.
;   3. Rebuild: TilemapSnapCamera, RebuildActorList, TilemapDrawPushBlocks.
;   4. Redraw: TilemapDrawPlayer, TilemapSubmergePlayer, GameUndoRedrawHook.
;
; Exported routines:
;   InitUndoBuffer   - reset circular buffer, capture initial level state
;   TakeSnapshot     - serialize current state to next slot (called on settled moves)
;   UndoMove         - restore state from previous slot (called on F9 / VHS rewind)
;   RebuildActorList - rebuild ActorList + ActorCount from Actors[] after undo
;==============================================================================

;==============================================================================
; AMIGA GAME ENGINE
; undo.asm  -  Move Rewind / Undo Snapshot System
;==============================================================================
;
; Circular snapshot ring buffer allowing the player to rewind up to
; UNDO_BUFFER_SIZE-1 completed moves. Pressing F9 (or VHS rewind trigger)
; restores the complete game state from one slot back.
;
; Buffer model (head = next slot to write, 0-based ring):
;   TakeSnapshot : write slot[head], head = (head+1) & mask, count = min(count+1, SIZE)
;   UndoMove     : need count>=2; count--; head=(head-1)&mask; restore slot[(head-1)&mask]
;
; Serialized state captured in each snapshot:
;   1. Player: Tile coordinates (X, Y), Status, Facing, OnLadder.
;   2. GameMap: Complete collision and geometry map (CurrentMapSize bytes).
;   3. Dynamic Actors: Active pushable blocks and falling obstacles (up to TotalActorCount).
;   4. Water: WaterPixelY, WaterCurrentRow, WaterSubTick.
;   5. Whatever the game copies in GameSnapshotSaveHook (Duck Rescue: oxygen and
;      safe-ground state, and the enemy, friend and pickup pools).
;
; Rewind & Restoration Pipeline:
;   1. Pre-restore Erase: TilemapErasePlayer, TilemapEraseEnemies, TilemapEraseFriends,
;      and TilemapErasePickups erase current on-screen BOBs to prevent ghosting.
;   2. Memory Unpack: Restores Player, GameMap, Actors, and dynamic entity arrays.
;   3. Waterline Rewind: TilemapRewindWater restores dry tiles in NonDisplayScreen
;      if the water scanline was lower (higher up the screen) before rewinding.
;   4. Actor Rebuild: RebuildActorList rebuilds the active actor tracking pool.
;
; Exported routines:
;   InitUndoBuffer   - reset circular buffer, capture initial level state
;   TakeSnapshot     - serialize current state to next slot (called on settled moves)
;   UndoMove         - restore state from previous slot (called on F9 / VHS rewind)
;   RebuildActorList - rebuild ActorList + ActorCount from Actors[] after undo
;==============================================================================

;==============================================================================
; InitUndoBuffer  -  Reset the snapshot buffer and capture the initial level state
;
; Called from LevelRevealSetup after DrawMap has built the level.
; Ensures the first F9 press restores to the freshly-loaded level.
;
; On entry: a5 = Variables base
;
; Destroys: d0/d7/a0-a2 (preserves everything else, including a5/a6)
;==============================================================================

InitUndoBuffer:
    clr.w       SnapshotHead(a5)
    clr.w       SnapshotCount(a5)
    bsr         TakeSnapshot           ; slot 0 = initial level state
    rts

;==============================================================================
; TakeSnapshot  -  Save current game state to the next circular buffer slot
;
; Serialises GameMap and the actor pool into SnapshotBuffer[SnapshotHead],
; then hands the slot to GameSnapshotSaveHook for the game's own state.
;
; Only call when the game is fully settled (ActionStatus = ACTION_IDLE and
; no fall animation pending), so the saved state is consistent.
;
; On entry: a5 = Variables base
; Destroys: nothing (PUSHALL / POPALL)
;==============================================================================

TakeSnapshot:
    PUSHALL

    ; Compute destination slot address: SnapshotBuffer + head * Snap_Sizeof
    moveq       #0,d0
    move.w      SnapshotHead(a5),d0
    mulu        #Snap_Sizeof,d0            ; 32-bit result (head < 16, slot < 64K)
    lea         SnapshotBuffer,a0
    add.l       d0,a0                      ; a0 -> snapshot slot to write

    ; Save GameMap: CurrentMapSize(a5) bytes (longword-aligned)
    lea         Snap_Map(a0),a2
    lea         GameMap(a5),a1
    move.w      CurrentMapSize(a5),d7
    lsr.w       #2,d7                   ; longwords count
    subq.w      #1,d7
    bmi.s       .mapsavedone
.mapsave
    move.l      (a1)+,(a2)+
    dbra        d7,.mapsave
.mapsavedone

    ; Save actor records: only up to TotalActorCount(a5) slots
    ; (X, Y, Status, Type, SpriteOffset, Static: SNAP_ACTOR_WORDS words per slot)
    move.w      TotalActorCount(a5),d7
    move.w      d7,Snap_ActorCount(a0)
    beq.s       .actorsavedone
    subq.w      #1,d7
    lea         Snap_Actors(a0),a2
    lea         Actors(a5),a1
.actorsave
    move.w      Actor_X(a1),(a2)+
    move.w      Actor_Y(a1),(a2)+
    move.w      Actor_Status(a1),(a2)+
    move.w      Actor_Type(a1),(a2)+
    move.w      Actor_SpriteOffset(a1),(a2)+
    move.w      Actor_Static(a1),(a2)+
    add.w       #Actor_Sizeof,a1
    dbra        d7,.actorsave
.actorsavedone

    ; Rising water effect state
    move.w      WaterPixelY(a5),Snap_WaterPixelY(a0)
    move.w      WaterCurrentRow(a5),Snap_WaterCurrentRow(a0)
    move.w      WaterSubTick(a5),Snap_WaterSubTick(a0)
    move.w      PlayerSubmerged(a5),Snap_PlayerSubmerged(a0)

    ; Game-owned state (player, pools, timers, ...)
    move.l      a0,-(sp)
    bsr         GameSnapshotSaveHook
    move.l      (sp)+,a0

    ; Advance head (circular wrap with power-of-2 mask)
    move.w      SnapshotHead(a5),d0
    addq.w      #1,d0
    and.w       #UNDO_BUFFER_SIZE-1,d0
    move.w      d0,SnapshotHead(a5)

    ; Increment count up to UNDO_BUFFER_SIZE
    move.w      SnapshotCount(a5),d0
    cmp.w       #UNDO_BUFFER_SIZE,d0
    beq         .done
    addq.w      #1,d0
    move.w      d0,SnapshotCount(a5)
.done
    POPALL
    rts


;==============================================================================
; UndoMove  -  Restore the game state from one slot before the current head
;
; Requires SnapshotCount >= 2 (initial slot + at least one move).
; If count < 2, does nothing (already at the initial level state).
;
; Algorithm:
;   count -= 1
;   head  = (head - 1) & mask         ; undo: head now points to last-written slot
;   restore from slot[(head - 1) & mask]  ; the slot before that = pre-move state
;
; After restore:
;   - GameMap is restored; actors have X, Y, Status restored, animation fields zeroed
;   - ActionStatus = ACTION_IDLE; in-flight animation counts cleared
;   - The game has restored its own state via GameSnapshotRestoreHook
;   - ActorList is rebuilt via RebuildActorList; display is recomposited in place
;
; On entry: a5 = Variables base, a6 = CUSTOM
; Destroys: nothing (PUSHALL / POPALL)
;==============================================================================

UndoMove:
    PUSHALL

    ; Require at least 2 snapshots (initial + 1 move)
    move.w      SnapshotCount(a5),d0
    cmp.w       #2,d0
    blt         .exit

    ; Decrement count
    subq.w      #1,d0
    move.w      d0,SnapshotCount(a5)

    ; Move head back one slot (now points to the slot we are discarding)
    move.w      SnapshotHead(a5),d0
    subq.w      #1,d0
    and.w       #UNDO_BUFFER_SIZE-1,d0
    move.w      d0,SnapshotHead(a5)

    ; Restore from the slot one before that (= the state before the last move)
    subq.w      #1,d0
    and.w       #UNDO_BUFFER_SIZE-1,d0
    mulu        #Snap_Sizeof,d0
    lea         SnapshotBuffer,a0
    add.l       d0,a0                      ; a0 -> snapshot to restore

    ; 1. Erase the player, the game's entities, and every live actor from the
    ;    current frame so nothing ghosts after the restore
    move.l      a0,-(sp)
    lea         Player(a5),a4
    bsr         TilemapErasePlayer
    bsr         GameUndoEraseHook

    move.w      TotalActorCount(a5),d7
    beq.s       .erase_actors_done
    subq.w      #1,d7
    lea         Actors(a5),a3
.erase_actors_loop:
    tst.w       Actor_Status(a3)
    beq.s       .next_erase_actor       ; dead actors were erased when killed
    bsr         ClearActor              ; erase in-tile/Prev position if mid-move/fall
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile   ; erase settled tile position
.next_erase_actor:
    add.w       #Actor_Sizeof,a3
    dbra        d7,.erase_actors_loop
.erase_actors_done:
    bsr         ClearDirtyTiles
    move.l      (sp)+,a0

    ; 2. Restore GameMap: CurrentMapSize(a5) bytes (longword-aligned)
    lea         Snap_Map(a0),a2
    lea         GameMap(a5),a1
    move.w      CurrentMapSize(a5),d7
    lsr.w       #2,d7                   ; longwords count
    subq.w      #1,d7
    bmi.s       .maprestoredone
.maprestore
    move.l      (a2)+,(a1)+
    dbra        d7,.maprestore
.maprestoredone

    ; Restore Actors: Snap_ActorCount(a0) slots
    move.w      Snap_ActorCount(a0),d7
    beq.s       .actordone
    subq.w      #1,d7
    lea         Snap_Actors(a0),a2
    lea         Actors(a5),a1

.actorrestore
    move.w      (a2)+,Actor_X(a1)
    move.w      (a2)+,Actor_Y(a1)
    move.w      (a2)+,Actor_Status(a1)
    move.w      (a2)+,Actor_Type(a1)
    move.w      (a2)+,Actor_SpriteOffset(a1)
    move.w      (a2)+,Actor_Static(a1)
    tst.w       Actor_Status(a1)
    beq         .dead_actor                ; slot inactive: skip field setup

    move.w      Actor_X(a1),Actor_PrevX(a1)
    move.w      Actor_Y(a1),Actor_PrevY(a1)
    clr.w       Actor_XDec(a1)
    clr.w       Actor_YDec(a1)
    clr.w       Actor_HasFalled(a1)
    clr.w       Actor_ImpactTick(a1)
    clr.w       Actor_Delta(a1)
    clr.w       Actor_FallY(a1)
    move.w      #1,Actor_Dirty(a1)

    ; Recompute cached pixel positions from restored tile coordinates
    move.w      Actor_X(a1),d0
    lsl.w       #4,d0                      ; d0 = X * 16
    move.w      d0,Actor_PixelX(a1)

    move.w      Actor_Y(a1),d0
    lsl.w       #4,d0                      ; d0 = Y * 16
    move.w      d0,Actor_PixelY(a1)

.dead_actor
    add.w       #Actor_Sizeof,a1
    dbra        d7,.actorrestore
.actordone

    ; Reset engine volatile state
    clr.w       ActionStatus(a5)
    clr.w       FallenActorsCount(a5)
    clr.w       LevelComplete(a5)
    clr.w       LevelCompleteHold(a5)

    ; Restore the water level, drying out rows in NonDisplayScreen & DisplayScreen if rewound
    move.w      WaterPixelY(a5),d0      ; current WaterPixelY before undo
    move.w      Snap_WaterPixelY(a0),d1 ; restored WaterPixelY from snapshot
    move.w      d1,WaterPixelY(a5)      ; update WaterPixelY first so TilemapStreamTileRow sees restored height
    move.l      a0,-(sp)
    bsr         TilemapRewindWater
    move.l      (sp)+,a0
    move.w      Snap_WaterCurrentRow(a0),WaterCurrentRow(a5)
    move.w      Snap_WaterSubTick(a0),WaterSubTick(a5)
    move.w      Snap_PlayerSubmerged(a0),PlayerSubmerged(a5)

    ; Game-owned state (player, pools, timers, ...)
    move.l      a0,-(sp)
    bsr         GameSnapshotRestoreHook
    move.l      (sp)+,a0

    ; 3. Snap camera to restored player, updating TilemapScreenOffset & streaming any newly revealed rows
    bsr         TilemapSnapCamera

    ;    Rebuild ActorList from restored Actor statuses, then redraw all live push blocks / crates
    ;    (CopySaveToStatic is intentionally omitted because all pre-undo entity footprints
    ;     were individually erased above, preventing a full-screen background flash)
    bsr         RebuildActorList
    bsr         TilemapDrawPushBlocks

    ; 4. Immediately recomposite the player and the game's entities so DisplayScreen
    ;    is fully rendered in VBlank and nothing ever disappears
    lea         Player(a5),a4
    bsr         TilemapDrawPlayer
    bsr         TilemapSubmergePlayer
    bsr         GameUndoRedrawHook

    ; Clear overruns incurred during full-screen background redraw
    clr.w       VBlankOverrunCount(a5)

.exit
    POPALL
    rts


;==============================================================================
; RebuildActorList  -  Rebuild ActorList and ActorCount from the Actors[] pool
;
; After UndoMove directly restores Actor_Status fields, the ActorList pointer
; array may be inconsistent (dead actors previously removed by CleanActors, or
; restored actors that never appear).  This routine rebuilds it from scratch.
;
; Scans all TotalActorCount (up to MAX_ACTIVE_CRATES) slots in Actors[], adding live actors (Status != 0) to
; ActorList, then sorts by Y via SortActors.
;
; On entry: a5 = Variables base
; Destroys: d6/d7/a0/a3 (safe to call inside PUSHALL / POPALL context)
;==============================================================================

RebuildActorList:
    lea         ActorList(a5),a0           ; a0 = write cursor (register, not memory)
    moveq       #0,d6                      ; d6 = live count

    move.w      TotalActorCount(a5),d7
    beq.s       .rebuild_done
    subq.w      #1,d7
    lea         Actors(a5),a3

.scan
    tst.w       Actor_Status(a3)
    beq         .skip

    move.l      a3,(a0)+                   ; append pointer to ActorList
    addq.w      #1,d6

.skip
    add.w       #Actor_Sizeof,a3
    dbra        d7,.scan

.rebuild_done
    move.l      a0,ActorSlotPtr(a5)        ; write cursor once after scan
    move.w      d6,ActorCount(a5)

    bsr         SortActors
    rts
