;==============================================================================
; DUCK RESCUE
; game_hooks.asm  -  Every Game*Hook the engine calls, implemented for Duck Rescue
;==============================================================================
;
; The engine never names a Duck Rescue routine directly. Instead it calls the
; hooks below at fixed points of its frame, level and undo pipelines (see
; engine/ENGINE_CONTRACT.md, section "Hooks"). A hook is either a small
; routine here or a binding equate that points the hook name at an existing
; game routine.
;
; Register convention: a5 = Variables base, a6 = CUSTOM chip base.
; Unless stated otherwise a hook may clobber d0-d7/a0-a4.
;==============================================================================

;------------------------------------------------------------------------------
; Setup / level lifecycle
;------------------------------------------------------------------------------

; GameSetupHook  -  once per game start, after the engine's own setup
; Destroys: d0-d6/a0-a1/a4 (preserves everything else, including a5/a6)
GameSetupHook:
    bsr         InitHUDSprites          ; hardware sprite HUD & palettes
    rts

; GameLevelInitHook  -  end of LevelInit, after geometry is loaded and the
; player is positioned. Resets per-level survival state and fills the pools.
; Destroys: d0-d7/a0-a1 (preserves everything else, including a5/a6)
GameLevelInitHook:
    move.w      #OXYGEN_MAX,PlayerOxygen(a5)
    clr.w       PlayerSubmerged(a5)
    clr.w       PlayerDrowning(a5)
    clr.w       PlayerDrownTimer(a5)
    clr.w       OxygenKitInventory(a5)
    clr.w       OxygenKitActive(a5)
    tst.w       PlayerLives(a5)
    bne.s       .lives_ok
    move.w      #DEFAULT_LIVES,PlayerLives(a5)
.lives_ok:
    lea         Player(a5),a0
    move.w      Player_X(a0),PlayerSafeX(a5)        ; last dry ground = spawn tile
    move.w      Player_Y(a0),PlayerSafeY(a5)
    move.w      Player_PixelX(a0),PlayerSafePixelX(a5)
    move.w      Player_PixelY(a0),PlayerSafePixelY(a5)
    bsr         LevelInitEnemies        ; populate ActiveEnemies from LevelDef
    bsr         LevelInitFriends        ; populate ActiveFriends from LevelDef
    bsr         LevelInitPickups         ; populate ActivePickups from LevelDef
    clr.w       PlayerPuffTick(a5)      ; no landing puff carried into a new level
    rts

; GameShowPlayerHook  -  draw the player at its current position (level reveal)
GameShowPlayerHook          = ShowPlayer

; GameLevelDoneHook  -  d3 = 0 when the level objective is met
GameLevelDoneHook           = CheckLevelDone

;------------------------------------------------------------------------------
; Per-frame (GameRun) hooks, in call order
;------------------------------------------------------------------------------

; GameUndoAllowedHook  -  d0 = 0 if a rewind may start this frame
; Destroys: d0 (preserves everything else, including a5/a6)
GameUndoAllowedHook:
    move.w      PlayerDrowning(a5),d0   ; no rewinding out of a drowning sequence
    rts

; GameRestoreOverlapsHook  -  after the player's stamps: re-blit entities the
; player's erase touched, then put any enemy beside the player back in front
; of the stamped scenery (the enemies were drawn before the stamps).
GameRestoreOverlapsHook:
    bsr         TilemapRestorePlayerOverlaps
    bra         TilemapRedrawEnemiesOverPlayer

; GameDrawPriorityHook  -  move and draw the beam-raced entities in one slice
; of the screen (d0.w = first screen Y, d1.w = end screen Y, exclusive). The
; engine calls it for every slice, top to bottom, so enemies are drawn in
; screen order around the player.
GameDrawPriorityHook        = TilemapUpdateEnemiesInRange

; GameDrawHook  -  remaining blits, chasing the beam. Mia's landing puff runs
; here, before the logic moves her, so it redraws her where she was drawn.
; Destroys: none (preserves all registers)
GameDrawHook:
    bsr         PlayerPuffRun           ; (enemies are drawn by GameDrawPriorityHook, in screen order)
    rts

; GameLogicHook  -  after UpdateControls
; Destroys: d0-d5/d7/a0-a1/a4 (preserves everything else, including a5/a6)
GameLogicHook:
    bsr         PlayerLogic             ; player action state machine
    bsr         PlayerCheckFriends      ; rescue collisions
    bsr         PlayerCheckOxygen       ; oxygen pickup collisions
    bsr         PlayerCheckEnemies      ; enemy / hazard collisions
    rts

; GamePostLogicHook  -  after TilemapUpdateCamera / TilemapUpdateWater
; Destroys: d0-d5/d7/a0-a4 (preserves everything else, including a5/a6)
GamePostLogicHook:
    bsr         PlayerUpdateOxygen      ; submersion, oxygen depletion, safe ground
    bsr         UpdateHUDSprites        ; lives, oxygen kit, friends-left sprites
    rts

; GameActorPhaseHook  -  after AnimateEnemies, before TilemapDrawPushBlocks
GameActorPhaseHook          = ActionFallActors

; GameDrawEntitiesHook  -  after TilemapDrawPushBlocks, before FlushDirtyTiles
; Destroys: d0-d3/d7/a4 (preserves everything else, including a5/a6)
GameDrawEntitiesHook:
    bsr         TilemapDrawPickups       ; oxygen canisters
    bsr         TilemapUpdateFriends    ; animal friends
    rts

;------------------------------------------------------------------------------
; Pause / debug
;------------------------------------------------------------------------------

; GameUnpauseHook  -  pause banner or debug HUD erased: invalidate anything that must redraw
; Destroys: none (preserves all registers)
GameUnpauseHook:
    PUSHM       d7/a4
    move.w      ActivePickupCount(a5),d7
    beq.s       .no_oxy
    subq.w      #1,d7
    lea         ActivePickups(a5),a4
.oxy_loop:
    clr.w       Pickup_Drawn(a4)
    lea         Pickup_Sizeof(a4),a4
    dbra        d7,.oxy_loop
.no_oxy:
    move.w      ActiveFriendCount(a5),d7
    beq.s       .no_friends
    subq.w      #1,d7
    lea         ActiveFriends(a5),a4
.friend_loop:
    clr.w       Friend_Drawn(a4)
    lea         Friend_Sizeof(a4),a4
    dbra        d7,.friend_loop
.no_friends:
    POPM        d7/a4
    rts

; GameDebugCountHook  -  d0.w = entity count shown on the debug overlay
; Destroys: d0 (preserves everything else, including a5/a6)
GameDebugCountHook:
    move.w      ActiveEnemyCount(a5),d0
    rts

;------------------------------------------------------------------------------
; Entities and crates (engine/gameplay/entities.asm, actor_physics.asm)
;------------------------------------------------------------------------------

; GameEnemySheetHook  -  a1 = colour sheet for the enemy at a4 (stun strobe)
GameEnemySheetHook          = EnemyStunFlashSheet

; GameEnemyOverlayHook  -  draw over the enemy just blitted at a2 (dizzy stars)
GameEnemyOverlayHook        = EnemyDrawStunStars

; GamePushMoveHook  -  walk the player into the cell the pushed crate left
GamePushMoveHook            = PlayerDoMove

; GameActorImpactHook  -  draw frame d2 of a crate's landing puff at pixel (d0,d1)
GameActorImpactHook         = DrawSmokeFrame


;------------------------------------------------------------------------------
; Undo / rewind (engine/gameplay/undo.asm). a0 = snapshot slot where stated;
; the engine preserves a0 around every call.
;------------------------------------------------------------------------------

; GameSnapshotSaveHook  -  copy game state into the slot at a0
; Destroys: none (preserves all registers)
GameSnapshotSaveHook:
    PUSHM       d7/a1-a2
    ; Player (5 words)
    lea         Player(a5),a1
    move.w      Player_X(a1),Snap_PlayerX(a0)
    move.w      Player_Y(a1),Snap_PlayerY(a0)
    move.w      Player_Status(a1),Snap_PlayerStatus(a0)
    move.w      Player_Facing(a1),Snap_PlayerFacing(a0)
    move.w      Player_OnLadder(a1),Snap_PlayerOnLadder(a0)

    ; Oxygen and safe-ground state (7 words)
    move.w      PlayerOxygen(a5),Snap_PlayerOxygen(a0)
    move.w      OxygenKitInventory(a5),Snap_OxygenKitInventory(a0)
    move.w      OxygenKitActive(a5),Snap_OxygenKitActive(a0)
    move.w      PlayerSafeX(a5),Snap_PlayerSafeX(a0)
    move.w      PlayerSafeY(a5),Snap_PlayerSafeY(a0)
    move.w      PlayerSafePixelX(a5),Snap_PlayerSafePixelX(a0)
    move.w      PlayerSafePixelY(a5),Snap_PlayerSafePixelY(a0)

    ; Dynamic enemies
    move.w      ActiveEnemyCount(a5),Snap_ActiveEnemyCount(a0)
    UNDO_COPY_ARRAY  ActiveEnemies(a5),Snap_ActiveEnemies(a0),Enemy_Sizeof,MAX_ACTIVE_ENEMIES

    ; Animal friends
    move.w      ActiveFriendCount(a5),Snap_ActiveFriendCount(a0)
    move.w      FriendsCollectedCount(a5),Snap_FriendsCollectedCount(a0)
    UNDO_COPY_ARRAY  ActiveFriends(a5),Snap_ActiveFriends(a0),Friend_Sizeof,MAX_ACTIVE_FRIENDS

    ; Oxygen refills
    move.w      ActivePickupCount(a5),Snap_ActivePickupCount(a0)
    UNDO_COPY_ARRAY  ActivePickups(a5),Snap_ActivePickups(a0),Pickup_Sizeof,MAX_ACTIVE_PICKUPS
    POPM        d7/a1-a2
    rts

; GameUndoEraseHook  -  erase the game's entities before the restore
; Destroys: d0-d1/d7/a4 (preserves everything else, including a5/a6)
GameUndoEraseHook:
    bsr         PlayerPuffCancel
    bsr         TilemapEraseEnemies
    bsr         TilemapEraseFriends
    bsr         TilemapErasePickups
    rts

; GameSnapshotRestoreHook  -  copy game state back out of the slot at a0
; Destroys: none (preserves all registers)
GameSnapshotRestoreHook:
    PUSHM       d0-d7/a1-a4
    ; Player
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
    move.w      d0,Player_WorldX(a1)       ; refresh world X cache
    moveq       #0,d0
    move.w      Player_Y(a1),d0
    lsl.w       #4,d0
    move.w      d0,Player_PixelY(a1)       ; refresh pixel Y cache
    subq.w      #8,d0
    move.w      d0,Player_WorldY(a1)       ; refresh world Y cache (PixelY - 8)

    ; Refresh PlayerFrame to match restored ladder/ground idle state
    moveq       #PLAYER_IDLE_OFFSET,d0
    tst.w       Player_OnLadder(a1)
    beq.s       .set_restored_frame
    moveq       #PLAYER_LADDER_IDLE,d0
.set_restored_frame:
    move.w      d0,PlayerFrame(a5)

    ; Volatile game state
    clr.w       PlayerMoved(a5)
    clr.w       PlayerDrowning(a5)
    clr.w       PlayerDrownTimer(a5)
    clr.w       PlayerDeathTimer(a5)
    clr.w       PlayerAttackTimer(a5)

    ; Oxygen and safe-ground state
    move.w      Snap_PlayerOxygen(a0),PlayerOxygen(a5)
    move.w      Snap_OxygenKitInventory(a0),OxygenKitInventory(a5)
    move.w      Snap_OxygenKitActive(a0),OxygenKitActive(a5)
    move.w      Snap_PlayerSafeX(a0),PlayerSafeX(a5)
    move.w      Snap_PlayerSafeY(a0),PlayerSafeY(a5)
    move.w      Snap_PlayerSafePixelX(a0),PlayerSafePixelX(a5)
    move.w      Snap_PlayerSafePixelY(a0),PlayerSafePixelY(a5)

    ; Dynamic enemies
    move.w      Snap_ActiveEnemyCount(a0),ActiveEnemyCount(a5)
    UNDO_COPY_ARRAY  Snap_ActiveEnemies(a0),ActiveEnemies(a5),Enemy_Sizeof,MAX_ACTIVE_ENEMIES
    UNDO_CLEAN_PREV  ActiveEnemies(a5),MAX_ACTIVE_ENEMIES,Enemy_

    ; Animal friends
    move.w      Snap_ActiveFriendCount(a0),ActiveFriendCount(a5)
    move.w      Snap_FriendsCollectedCount(a0),FriendsCollectedCount(a5)
    UNDO_COPY_ARRAY  Snap_ActiveFriends(a0),ActiveFriends(a5),Friend_Sizeof,MAX_ACTIVE_FRIENDS
    UNDO_CLEAN_PREV  ActiveFriends(a5),MAX_ACTIVE_FRIENDS,Friend_

    ; Oxygen refills (no Prev* fields: clear Drawn flags inline)
    move.w      Snap_ActivePickupCount(a0),ActivePickupCount(a5)
    UNDO_COPY_ARRAY  Snap_ActivePickups(a0),ActivePickups(a5),Pickup_Sizeof,MAX_ACTIVE_PICKUPS
    lea         ActivePickups(a5),a1
    move.w      #MAX_ACTIVE_PICKUPS-1,d7
.oxygen_clean_loop
    clr.w       Pickup_Drawn(a1)
    lea         Pickup_Sizeof(a1),a1
    dbra        d7,.oxygen_clean_loop
    POPM        d0-d7/a1-a4
    rts

; GameUndoRedrawHook  -  recomposite the game's entities and HUD after the restore
; Destroys: d0-d5/d7/a0-a2/a4 (preserves everything else, including a5/a6)
GameUndoRedrawHook:
    bsr         TilemapUpdateEnemies
    bsr         TilemapUpdateFriends
    bsr         TilemapDrawPickups
    bsr         UpdateHUDSprites
    rts

;------------------------------------------------------------------------------
; Data bindings (tables the engine reads)
;
; These emit bytes, so they must sit here in the code section. Anything an
; include emits before engine_main.asm lands in front of Main and becomes the
; program entry point (tests/test_engine_contract.py guards this).
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; GameLevelDefPointerFields  -  LevelDef pointer fields the custom-level loader
; must rebase after loading a .lvl file (engine/gameplay/customlevel.asm).
; Word offsets into LevelDef, -1 terminated.
;------------------------------------------------------------------------------
; Destroys: none (preserves all registers)
GameLevelDefPointerFields:
    dc.w       LevelDef_EnemyList
    dc.w       LevelDef_FriendList
    dc.w       LevelDef_BlockList
    dc.w       LevelDef_LadderList
    dc.w       LevelDef_SolidList
    dc.w       LevelDef_TriggerList
    dc.w       LevelDef_HazardList
    dc.w       LevelDef_BridgeList
    dc.w       LevelDef_PickupList
    dc.w       LevelDef_TitleStr
    dc.w       LevelDef_SubTitleStr
    dc.w       -1
