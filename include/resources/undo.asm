
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
; Saves: Player (X/Y/Status/Facing/OnLadder), the full GameMap
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

    ; Save Player (5 words)
    lea         Player(a5),a1
    move.w      Player_X(a1),Snap_PlayerX(a0)
    move.w      Player_Y(a1),Snap_PlayerY(a0)
    move.w      Player_Status(a1),Snap_PlayerStatus(a0)
    move.w      Player_Facing(a1),Snap_PlayerFacing(a0)
    move.w      Player_OnLadder(a1),Snap_PlayerOnLadder(a0)

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

    ; Save Water and Oxygen state (11 words)
    move.w      WaterPixelY(a5),Snap_WaterPixelY(a0)
    move.w      WaterCurrentRow(a5),Snap_WaterCurrentRow(a0)
    move.w      WaterSubTick(a5),Snap_WaterSubTick(a0)
    move.w      PlayerOxygen(a5),Snap_PlayerOxygen(a0)
    move.w      PlayerSubmerged(a5),Snap_PlayerSubmerged(a0)
    move.w      OxygenKitInventory(a5),Snap_OxygenKitInventory(a0)
    move.w      OxygenKitActive(a5),Snap_OxygenKitActive(a0)
    move.w      PlayerSafeX(a5),Snap_PlayerSafeX(a0)
    move.w      PlayerSafeY(a5),Snap_PlayerSafeY(a0)
    move.w      PlayerSafePixelX(a5),Snap_PlayerSafePixelX(a0)
    move.w      PlayerSafePixelY(a5),Snap_PlayerSafePixelY(a0)

    ; Save Dynamic Enemies
    move.w      ActiveEnemyCount(a5),Snap_ActiveEnemyCount(a0)
    lea         Snap_ActiveEnemies(a0),a2
    lea         ActiveEnemies(a5),a1
    move.w      #(ei_SIZEOF*MAX_ACTIVE_ENEMIES/4)-1,d7
.enemysave
    move.l      (a1)+,(a2)+
    dbra        d7,.enemysave

    ; Save Dynamic Friends
    move.w      ActiveFriendCount(a5),Snap_ActiveFriendCount(a0)
    move.w      FriendsRescuedCount(a5),Snap_FriendsRescuedCount(a0)
    lea         Snap_ActiveFriends(a0),a2
    lea         ActiveFriends(a5),a1
    move.w      #(fi_SIZEOF*MAX_ACTIVE_FRIENDS/4)-1,d7
.friendsave
    move.l      (a1)+,(a2)+
    dbra        d7,.friendsave

    ; Save Dynamic Oxygen Refills
    move.w      ActiveOxygenCount(a5),Snap_ActiveOxygenCount(a0)
    lea         Snap_ActiveOxygen(a0),a2
    lea         ActiveOxygen(a5),a1
    move.w      #(ox_SIZEOF*MAX_ACTIVE_OXYGEN/4)-1,d7
.oxygensave
    move.l      (a1)+,(a2)+
    dbra        d7,.oxygensave

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
;   - Player has tile positions, status, facing, and ladder flag restored
;   - GameMap is restored
;   - All actors have X, Y, Status restored; animation fields zeroed
;   - ActorList is rebuilt via RebuildActorList
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

    ; Erase player, active enemies, and friends from current frame's position
    lea         Player(a5),a4
    bsr         TilemapErasePlayer
    bsr         TilemapEraseEnemies
    bsr         TilemapEraseFriends
    bsr         TilemapEraseOxygen

    ; Restore Player
    lea         Player(a5),a1
    move.w      Snap_PlayerX(a0),Player_X(a1)
    move.w      Snap_PlayerY(a0),Player_Y(a1)
    move.w      Snap_PlayerStatus(a0),Player_Status(a1)
    move.w      Snap_PlayerFacing(a0),Player_Facing(a1)
    move.w      Snap_PlayerOnLadder(a0),Player_OnLadder(a1)
    clr.w       Player_XDec(a1)
    clr.w       Player_YDec(a1)
    clr.w       Player_Fallen(a1)
    clr.w       Player_ActionCount(a1)
    clr.w       Player_ActionFrame(a1)
    clr.w       Player_AnimFrame(a1)
    moveq       #0,d0
    move.w      Player_X(a1),d0
    lsl.w       #4,d0
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
    clr.w       PlayerDrowning(a5)
    clr.w       PlayerDrownTimer(a5)
    clr.w       PlayerDeathTimer(a5)
    clr.w       PlayerAttackTimer(a5)

    ; Restore water level and dry out rows in NonDisplayScreen if rewound
    move.w      WaterPixelY(a5),d0      ; current WaterPixelY before undo
    move.w      Snap_WaterPixelY(a0),d1 ; restored WaterPixelY from snapshot
    bsr         TilemapRewindWater

    move.w      Snap_WaterPixelY(a0),WaterPixelY(a5)
    move.w      Snap_WaterCurrentRow(a0),WaterCurrentRow(a5)
    move.w      Snap_WaterSubTick(a0),WaterSubTick(a5)
    move.w      Snap_PlayerOxygen(a0),PlayerOxygen(a5)
    move.w      Snap_PlayerSubmerged(a0),PlayerSubmerged(a5)
    move.w      Snap_OxygenKitInventory(a0),OxygenKitInventory(a5)
    move.w      Snap_OxygenKitActive(a0),OxygenKitActive(a5)
    move.w      Snap_PlayerSafeX(a0),PlayerSafeX(a5)
    move.w      Snap_PlayerSafeY(a0),PlayerSafeY(a5)
    move.w      Snap_PlayerSafePixelX(a0),PlayerSafePixelX(a5)
    move.w      Snap_PlayerSafePixelY(a0),PlayerSafePixelY(a5)

    ; Restore Dynamic Enemies
    move.w      Snap_ActiveEnemyCount(a0),ActiveEnemyCount(a5)
    lea         Snap_ActiveEnemies(a0),a1
    lea         ActiveEnemies(a5),a2
    move.w      #(ei_SIZEOF*MAX_ACTIVE_ENEMIES/4)-1,d7
.enemyrestore
    move.l      (a1)+,(a2)+
    dbra        d7,.enemyrestore

    ; Reset drawn flags on restored enemies
    lea         ActiveEnemies(a5),a1
    move.w      #MAX_ACTIVE_ENEMIES-1,d7
.enemy_clean_loop
    clr.w       ei_Drawn(a1)
    move.w      ei_X(a1),ei_PrevX(a1)
    move.w      ei_Y(a1),ei_PrevY(a1)
    lea         ei_SIZEOF(a1),a1
    dbra        d7,.enemy_clean_loop

    ; Restore Dynamic Friends
    move.w      Snap_ActiveFriendCount(a0),ActiveFriendCount(a5)
    move.w      Snap_FriendsRescuedCount(a0),FriendsRescuedCount(a5)
    lea         Snap_ActiveFriends(a0),a1
    lea         ActiveFriends(a5),a2
    move.w      #(fi_SIZEOF*MAX_ACTIVE_FRIENDS/4)-1,d7
.friendrestore
    move.l      (a1)+,(a2)+
    dbra        d7,.friendrestore

    lea         ActiveFriends(a5),a1
    move.w      #MAX_ACTIVE_FRIENDS-1,d7
.friend_clean_loop
    clr.w       fi_Drawn(a1)
    move.w      fi_X(a1),fi_PrevX(a1)
    move.w      fi_Y(a1),fi_PrevY(a1)
    lea         fi_SIZEOF(a1),a1
    dbra        d7,.friend_clean_loop

    ; Restore Dynamic Oxygen Refills
    move.w      Snap_ActiveOxygenCount(a0),ActiveOxygenCount(a5)
    lea         Snap_ActiveOxygen(a0),a1
    lea         ActiveOxygen(a5),a2
    move.w      #(ox_SIZEOF*MAX_ACTIVE_OXYGEN/4)-1,d7
.oxygenrestore
    move.l      (a1)+,(a2)+
    dbra        d7,.oxygenrestore

    lea         ActiveOxygen(a5),a1
    move.w      #MAX_ACTIVE_OXYGEN-1,d7
.oxygen_clean_loop
    clr.w       ox_Drawn(a1)
    lea         ox_SIZEOF(a1),a1
    dbra        d7,.oxygen_clean_loop

    ; 1. Snap camera to restored player, updating TilemapScreenOffset (TILE Y offset) & copper bitplanes
    bsr         TilemapSnapCamera

    ; 2. Redraw the gamemap background from NonDisplayScreen at the current TILE Y offset
    bsr         CopySaveToStatic

    ; 3. Rebuild ActorList from restored Actor statuses, then redraw all live static actors
    bsr         RebuildActorList
    bsr         MarkAllActorsDirty
    bsr         DrawStaticActors

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


