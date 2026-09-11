
;==============================================================================
; AMIGA GAME ENGINE
; undo.asm  -  Move Rewind / Undo System
;==============================================================================
;
; Circular snapshot buffer allowing the player to rewind up to
; UNDO_BUFFER_SIZE-1 completed moves.  F9 restores the previous state.
;
; Buffer model (head = next slot to write, 0-based ring):
;   TakeSnapshot : write slot[head], head = (head+1) & mask, count = min(count+1, SIZE)
;   UndoMove     : need count>=2; count--; head=(head-1)&mask; restore slot[(head-1)&mask]
;
; The initial level snapshot (taken by InitUndoBuffer) counts as slot 0, so
; a single F9 press always restores the level to its just-loaded state.
;
; Exported routines:
;   InitUndoBuffer  - reset buffer, capture initial level state
;   TakeSnapshot    - save current state to next slot (call after each settled move)
;   UndoMove        - restore state from one slot back (call on F9)
;   RebuildActorList - rebuild ActorList + ActorCount from Actors[] after undo
;==============================================================================


;==============================================================================
; InitUndoBuffer  -  Reset the snapshot buffer and capture the initial level state
;
; Called from LevelRevealSetup after DrawMap has built the level.
; Ensures the first F9 press restores to the freshly-loaded level.
;
; On entry: a5 = Variables base
;==============================================================================

InitUndoBuffer:
    clr.w       SnapshotHead(a5)
    clr.w       SnapshotCount(a5)
    bsr         TakeSnapshot           ; slot 0 = initial level state
    rts


;==============================================================================
; TakeSnapshot  -  Save current game state to the next circular buffer slot
;
; Saves: Millie and Molly (X/Y/Status/Facing/OnLadder), the full GameMap
; (WALL_PAPER_SIZE bytes), and per-slot Actor X/Y/Status for all MAX_ACTORS slots.
;
; Only call when the game is fully settled (ActionStatus = ACTION_IDLE and
; no fall animation pending), so the saved state is consistent.
;
; On entry: a5 = Variables base
; Destroys: nothing (PUSHALL / POPALL)
;==============================================================================

TakeSnapshot:
    PUSHALL

    ; Compute destination slot address: SnapshotBuffer + head * Snap_sizeof
    moveq       #0,d0
    move.w      SnapshotHead(a5),d0
    mulu        #Snap_sizeof,d0            ; 32-bit result; max = 7*674 = 4718, fits in low word
    lea         SnapshotBuffer,a0
    add.l       d0,a0                      ; a0 -> snapshot slot to write

    ; Save Millie (5 words)
    lea         Millie(a5),a1
    move.w      Player_X(a1),Snap_MillieX(a0)
    move.w      Player_Y(a1),Snap_MillieY(a0)
    move.w      Player_Status(a1),Snap_MillieStatus(a0)
    move.w      Player_Facing(a1),Snap_MillieFacing(a0)
    move.w      Player_OnLadder(a1),Snap_MillieOnLadder(a0)

    ; Save Molly (5 words)
    lea         Molly(a5),a1
    move.w      Player_X(a1),Snap_MollyX(a0)
    move.w      Player_Y(a1),Snap_MollyY(a0)
    move.w      Player_Status(a1),Snap_MollyStatus(a0)
    move.w      Player_Facing(a1),Snap_MollyFacing(a0)
    move.w      Player_OnLadder(a1),Snap_MollyOnLadder(a0)

    ; Save GameMap: MAX_GAME_MAP_SIZE bytes
    lea         Snap_Map(a0),a2
    lea         GameMap(a5),a1
    move.w      #(MAX_GAME_MAP_SIZE/4)-1,d7
.mapsave
    move.l      (a1)+,(a2)+
    dbra        d7,.mapsave

    ; Save actor records: SNAP_ACTOR_WORDS words per slot.
    ; Type/SpriteOffset/Static/HatchTick are included because a hatching
    ; cocoon mutates them (see the Snapshot structure comment in struct.asm).
    lea         Snap_Actors(a0),a2
    lea         Actors(a5),a1
    move.w      #MAX_ACTORS-1,d7
.actorsave
    move.w      Actor_X(a1),(a2)+
    move.w      Actor_Y(a1),(a2)+
    move.w      Actor_Status(a1),(a2)+
    move.w      Actor_Type(a1),(a2)+
    move.w      Actor_SpriteOffset(a1),(a2)+
    move.w      Actor_Static(a1),(a2)+
    move.w      Actor_HatchTick(a1),(a2)+
    add.w       #Actor_Sizeof,a1
    dbra        d7,.actorsave

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
;   - Both players have their tile positions, status, facing, and ladder flag restored
;   - GameMap is restored
;   - All actors have X, Y, Status restored; animation fields zeroed
;   - ActorList is rebuilt via RebuildActorList
;   - PlayerPtrs is updated to reflect the restored active player
;   - Display is redrawn: NonDisplayScreen -> DisplayScreen, then DrawStaticActors
;   - ActionStatus = ACTION_IDLE; in-flight animation counts cleared
;
; On entry: a5 = Variables base, a6 = $dff000 (CUSTOM)
; Destroys: nothing (PUSHALL / POPALL)
;==============================================================================

UndoMove:
    PUSHALL

    ; Require at least 2 snapshots (initial + 1 move)
    move.w      SnapshotCount(a5),d0
    cmp.w       #2,d0
    blt         .exit

    ; Fire background DMA copy immediately so it overlaps all CPU restore work below.
    ; CopySaveToStatic is blitter B→D (NonDisplayScreen -> DisplayScreen, 45360 bytes).
    ; It fires and returns; all subsequent blitter calls start with WAITBLIT.
    bsr         CopySaveToStatic

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
    mulu        #Snap_sizeof,d0
    lea         SnapshotBuffer,a0
    add.l       d0,a0                      ; a0 -> snapshot to restore

    ; Restore Millie
    lea         Millie(a5),a1
    move.w      Snap_MillieX(a0),Player_X(a1)
    move.w      Snap_MillieY(a0),Player_Y(a1)
    move.w      Snap_MillieStatus(a0),Player_Status(a1)
    move.w      Snap_MillieFacing(a0),Player_Facing(a1)
    move.w      Snap_MillieOnLadder(a0),Player_OnLadder(a1)
    clr.w       Player_XDec(a1)
    clr.w       Player_YDec(a1)
    clr.w       Player_Fallen(a1)
    clr.w       Player_ActionCount(a1)
    clr.w       Player_ActionFrame(a1)
    clr.w       Player_AnimFrame(a1)
    moveq       #0,d0
    move.w      Player_X(a1),d0
    mulu        #TILE_WIDTH,d0
    move.w      d0,Player_PixelX(a1)       ; refresh pixel X cache
    moveq       #0,d0
    move.w      Player_Y(a1),d0
    lsl.w       #4,d0
    move.w      d0,Player_PixelY(a1)       ; refresh pixel Y cache

    ; Restore Molly
    lea         Molly(a5),a1
    move.w      Snap_MollyX(a0),Player_X(a1)
    move.w      Snap_MollyY(a0),Player_Y(a1)
    move.w      Snap_MollyStatus(a0),Player_Status(a1)
    move.w      Snap_MollyFacing(a0),Player_Facing(a1)
    move.w      Snap_MollyOnLadder(a0),Player_OnLadder(a1)
    clr.w       Player_XDec(a1)
    clr.w       Player_YDec(a1)
    clr.w       Player_Fallen(a1)
    clr.w       Player_ActionCount(a1)
    clr.w       Player_ActionFrame(a1)
    clr.w       Player_AnimFrame(a1)
    moveq       #0,d0
    move.w      Player_X(a1),d0
    mulu        #TILE_WIDTH,d0
    move.w      d0,Player_PixelX(a1)       ; refresh pixel X cache
    moveq       #0,d0
    move.w      Player_Y(a1),d0
    lsl.w       #4,d0
    move.w      d0,Player_PixelY(a1)       ; refresh pixel Y cache

    ; Restore GameMap: MAX_GAME_MAP_SIZE bytes
    lea         Snap_Map(a0),a2
    lea         GameMap(a5),a1
    move.w      #(MAX_GAME_MAP_SIZE/4)-1,d7
.maprestore
    move.l      (a2)+,(a1)+
    dbra        d7,.maprestore

    ; Restore Actors: MAX_ACTORS slots
    lea         Snap_Actors(a0),a2
    lea         Actors(a5),a1
    move.w      #MAX_ACTORS-1,d7

.actorrestore
    move.w      (a2)+,Actor_X(a1)
    move.w      (a2)+,Actor_Y(a1)
    move.w      (a2)+,Actor_Status(a1)
    move.w      (a2)+,Actor_Type(a1)
    move.w      (a2)+,Actor_SpriteOffset(a1)
    move.w      (a2)+,Actor_Static(a1)
    move.w      (a2)+,Actor_HatchTick(a1)
    tst.w       Actor_Status(a1)
    beq         .dead_actor                ; slot inactive: skip field setup

    move.w      Actor_X(a1),Actor_PrevX(a1)
    move.w      Actor_Y(a1),Actor_PrevY(a1)
    clr.w       Actor_XDec(a1)
    clr.w       Actor_YDec(a1)
    clr.w       Actor_HasFalled(a1)
    clr.w       Actor_ImpactTick(a1)
    clr.w       Actor_CloudTick(a1)
    clr.w       Actor_DirtTick(a1)
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

    ; Reset volatile game state
    clr.w       ActionStatus(a5)
    clr.w       PlayerMoved(a5)
    clr.w       FallenActorsCount(a5)
    clr.w       CloudActorsCount(a5)
    clr.w       DirtActorsCount(a5)
    clr.w       LevelComplete(a5)
    clr.w       LevelCompleteHold(a5)

    ; Restore PlayerPtrs: [0] = Status=1 (active), [1] = the other player
    lea         Millie(a5),a1
    lea         Molly(a5),a2
    cmp.w       #1,Player_Status(a1)
    beq         .millie_active
    move.l      a2,PlayerPtrs(a5)          ; Molly is active
    move.l      a1,PlayerPtrs+4(a5)
    bra         .ptrs_done
.millie_active
    move.l      a1,PlayerPtrs(a5)          ; Millie is active
    move.l      a2,PlayerPtrs+4(a5)
.ptrs_done

    ; Rebuild ActorList from restored Actor statuses, then draw all live actors.
    ; DrawStaticActors iterates ActorList and redraws all actors with Dirty=1.
    ; WAITBLIT inside PasteFrozenSprite guarantees CopySaveToStatic DMA completes first.
    bsr         RebuildActorList
    bsr         DrawStaticActors
    bsr         TilemapSnapCamera

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
; Scans all MAX_ACTORS slots in Actors[], adding live actors (Status != 0) to
; ActorList, then sorts by Y via SortActors.
;
; On entry: a5 = Variables base
; Destroys: d6/d7/a0/a3 (safe to call inside PUSHALL / POPALL context)
;==============================================================================

RebuildActorList:
    lea         ActorList(a5),a0           ; a0 = write cursor (register, not memory)
    moveq       #0,d6                      ; d6 = live count

    lea         Actors(a5),a3
    move.w      #MAX_ACTORS-1,d7

.scan
    tst.w       Actor_Status(a3)
    beq         .skip

    move.l      a3,(a0)+                   ; append pointer to ActorList
    addq.w      #1,d6

.skip
    add.w       #Actor_Sizeof,a3
    dbra        d7,.scan

    move.l      a0,ActorSlotPtr(a5)        ; write cursor once after scan
    move.w      d6,ActorCount(a5)

    bsr         SortActors
    rts


