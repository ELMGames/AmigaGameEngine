
;==============================================================================
; AMIGA GAME ENGINE
; player_fsm.asm  -  Player Action State Machine & Movement Dispatch
;==============================================================================
;
; Part of the player module (one of player_fsm/_combat/_water.asm; all follow the
; shared register convention). This file holds the top-level ActionStatus
; dispatcher and every state it can transition to/through, plus the
; move-resolution helpers that decide what a target tile does to a move:
;
;   ShowPlayer         - set active animation frame index (0..23)
;   PlayerLogic        - top-level dispatcher for ActionStatus
;   ActionIdle         - idle state: poll joystick/keys, trigger moves/attacks
;   ActionMove         - smooth tile-to-tile movement (16 pixel steps)
;   ActionFall / ActionPlayerFall - player falling with quadratic easing
;   ActionPush   - push-block animation (sinusoidal easing)
;   ActionDeath        - collapse animation before respawning
;   PlayerCheckControls, PlayerFrozen, PlayerInactive, PlayerIdle
;                      - dispatch to active or inactive control handler
;   PlayerShowIdleAnim / PlayerShowWalkAnim - BOB animation while standing/moving
;   PlayerTryMove, PlayerNotMove, PlayerMoveEmpty, PlayerMoveLadder,
;   PlayerKillEnemy    - test target cell geometry and choose correct action
;   PlayerDoMove       - commit a standard move (set ActionStatus = ACTION_MOVE)
;   PlayerMoveLogic    - update GameMap and triggers after move completes
;   PlayerFallLogic    - test if active player has lost footing and should fall
;   CheckLevelDone     - test rescue/exit conditions for level completion
;
; Register convention:
;   a4 = current (active) player structure
;   a3 = current actor structure
;   a5 = Variables base
;   a6 = $dff000 (CUSTOM chip base)
;==============================================================================

;==============================================================================
; ShowPlayer  -  Set the active animation frame for the player BOB
;
; Sets PlayerFrame with the selected animation cel offset (0..23).
; The player BOB is blitted in TilemapDrawPlayer (tilemap.asm) onto the
; display screen interleaved bitplanes with foreground & water depth layering.
;
; On entry:
;   d0 = BOB animation frame index (0..23)
;   a4 = pointer to player structure
;   a5 = Variables base pointer
;   a6 = $dff000 (CUSTOM chip base)
;
; Destroys: none (preserves all registers)
;==============================================================================

ShowPlayer:
    tst.w     Player_Status(a4)          ; is this player active?
    bne.s     .go                        ; yes - cache frame
    rts

.go:
    move.w    d0,PlayerFrame(a5)      ; cache active BOB animation frame (0..47)
    rts

; Alias for backward compatibility:


;==============================================================================
; PlayerLogic  -  Top-level player action dispatcher
;
; Called every VBlank from GameRun.  Reads ActionStatus and jumps to the
; appropriate handler for the current game action.
;
; ActionStatus values (from const.asm):
;   0 = ACTION_IDLE        -> ActionIdle
;   1 = ACTION_MOVE        -> ActionMove
;   2 = ACTION_FALL        -> ActionFall
;   3 = ACTION_PUSH        -> ActionPush
;   4 = ACTION_ATTACK      -> ActionAttack
;   5 = ACTION_DEATH       -> ActionDeath
;
; Only one action runs at a time.  Each action handler is responsible for
; resetting ActionStatus to ACTION_IDLE when it completes.
;
; Destroys: d0-d2/a4 (preserves everything else, including a5/a6)
;==============================================================================

PlayerLogic:
    ; Decrement post-respawn invulnerability timer
    tst.w       PlayerInvincibleTimer(a5)
    beq.s       .not_invincible
    subq.w      #1,PlayerInvincibleTimer(a5)
.not_invincible:
    move.w      ActionStatus(a5),d0     ; load current action state
    bsr.s       .dispatch

    ; Cache Player World coordinates once per frame for collision and camera routines
    lea         Player(a5),a4
    move.w      Player_X(a4),d0
    lsl.w       #4,d0
    add.w       Player_XDec(a4),d0
    move.w      d0,Player_WorldX(a4)

    move.w      Player_Y(a4),d1
    lsl.w       #4,d1
    add.w       Player_YDec(a4),d1
    subq.w      #8,d1
    move.w      d1,Player_WorldY(a4)
    rts

.dispatch:
    JMPINDEX    d0                      ; dispatch through jump table

.i  ; jump offset table
    dc.w        ActionIdle-.i           ; state 0: idle
    dc.w        ActionMove-.i           ; state 1: moving
    dc.w        ActionFall-.i           ; state 2: falling
    dc.w        ActionPush-.i           ; state 3: push animation
    dc.w        ActionAttack-.i         ; state 4: cane strike attack animation
    dc.w        ActionDeath-.i          ; state 5: player collapse death animation



;==============================================================================
; ActionFall  -  Player fall animation handler (ACTION_FALL state)
;
; Called once per frame while the active player is in free-fall (Player_Fallen=1).
; Advances the active player's fall animation and downward acceleration.
;
; When the player reaches the landing platform (Player_Fallen = 0):
;   1. Transition ActionStatus back to ACTION_IDLE so input immediately resumes.
;   2. Record an undo snapshot now that player movement has settled.
;
; Note: Falling actors/crates are processed independently by ActionFallActors
; in GameRun every frame, decoupling actor gravity from active player controls.
;
; Destroys: d0-d2 (preserves everything else, including a5/a6)
;==============================================================================

ActionFall:
    bsr         ActionPlayerFall        ; advance active player fall; clears Player_Fallen when done

    ; Check if active player fall is complete
    tst.w       Player_Fallen(a4)
    bne.s       .notyet
    move.w      #ACTION_IDLE,ActionStatus(a5)
    bsr         TakeSnapshot

.notyet:
    rts

;==============================================================================
; ActionPush  -  One frame of the crate push animation
;
; Erases the pushed actor, eases its sub-pixel X along the Quadratic table
; (trough to peak over PUSH_STEPS frames, signed by Actor_DirectionX),
; advances the player's walk animation, then redraws player and crate so
; the crate sits over the player's hands. After PUSH_STEPS frames both snap
; to the new tile: PlayerMoveLogic/PlayerFallLogic commit the player,
; ActorFallAll starts any actor falls, and unless the player is now falling
; the state returns to ACTION_IDLE and a snapshot is taken.
;
; In:  a4 = Player, PushedActor(a5) -> the actor being pushed
;      a5 = Variables base, a6 = CUSTOM chip base
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
;==============================================================================

PUSH_STEPS  = 16                                ; frames for a full one-tile push
PUSH_DELTA  = (SINE_ANGLES<<16)/2/PUSH_STEPS    ; angle step: PUSH_STEPS frames = half a period

ActionPush:
    move.l      PushedActor(a5),a3     ; a3 -> the block being pushed

    ; The push erases and redraws the crate (and redraws the player) during
    ; the game logic, outside the top-down draw pass. Near the top of the
    ; view the beam can be on those lines right now, which would show the
    ; crate erased but not yet redrawn, so wait for the beam to clear them:
    ; the player's top (crate Y - 8) to the crate's bottom (crate Y + 15).
    move.w      Actor_PrevY(a3),d0
    lsl.w       #4,d0
    add.w       Actor_YDec(a3),d0
    subq.w      #8,d0                   ; player BOB top (world Y)
    sub.w       TilemapCameraY(a5),d0   ; screen Y
    add.w       SpriteYOffset(a5),d0    ; raster line
    move.w      d0,d1
    add.w       #PLAYER_HEIGHT-1,d1     ; to the crate bottom
    bsr         WaitBeamClearOfLines

    ; Erase block from current drawn position
    bsr         ClearActor

    ; Advance the fixed-point angle accumulator
    lea         Quadratic,a0
    sub.l       #PUSH_DELTA,Actor_Delta(a3)  ; decrement angle (half-period, trough to peak)

    ; Sample the quadratic easing curve at the current angle
    moveq       #0,d0
    move.w      Actor_Delta(a3),d0    ; current angle (high word of fixed-point delta)
    add.w       #SINE_270,d0          ; start at the 270-degree (trough) point
    and.w       #SINE_ANGLES-1,d0     ; wrap to table bounds
    add.w       d0,d0                 ; word index (table entries are words)
    move.w      (a0,d0.w),d0          ; d0 = quadratic value (-SINE_RANGE..+SINE_RANGE)

    ; Scale: map quadratic value to 0..16 pixel range
    muls        #(TILE_WIDTH/2),d0    ; scale by 8 (half of 16-pixel tile width)
    divs        #SINE_RANGE,d0        ; normalise to -8..+8
    add.w       #(TILE_WIDTH/2),d0    ; shift to 0..16 range

    ; Apply direction sign
    tst.w       Actor_DirectionX(a3)
    bpl.s       .positive
    neg.w       d0                    ; negative direction: negate offset

.positive:
    move.w      d0,Actor_XDec(a3)    ; store computed sub-pixel X offset

    ; Advance player sub-pixel position & walk animation
    move.w      Player_DirectionX(a4),d0
    add.w       d0,Player_XDec(a4)
    bsr         PlayerShowWalkAnim

    ; Re-draw player BOB: restores player pixels wiped out by ClearActor
    ; and updates player to current sub-pixel walking position!
    lea         Player(a5),a4
    bsr         TilemapDrawPlayer
    bsr         TilemapSubmergePlayer

    ; Redraw block at its new sub-pixel position on top of the player's hands
    move.l      PushedActor(a5),a3
    bsr         DrawActor
    lea         Player(a5),a4

    ; Advance frame counter; check for push completion
    addq.w      #1,ActionCounter(a5)
    cmp.w       #PUSH_STEPS,ActionCounter(a5)
    bne         .exit                 ; not done yet

    ; Push animation complete
    clr.w       Actor_XDec(a3)       ; clear sub-pixel offset (snap to final position)
    move.w      Actor_X(a3),Actor_PrevX(a3)   ; update previous position record
    clr.w       Actor_HasMoved(a3)
    move.w      #1,Actor_Dirty(a3)     ; flag settled actor for redraw

    clr.w       Player_XDec(a4)
    clr.w       Player_YDec(a4)
    bsr         PlayerMoveLogic       ; commit player to vacated tile
    bsr         PlayerFallLogic       ; check if the player itself should now fall

    ; Check if actors (including pushed crate) should now fall asynchronously
    bsr         ActorFallAll          ; initiate any actor falls; d5 = count

    ; Only lock player into ACTION_FALL if the PLAYER itself is falling!
    ; Falling crates/actors are updated asynchronously by ActionFallActors.
    cmp.w       #ACTION_FALL,ActionStatus(a5)
    beq.s       .exit                 ; player is falling: stay in ACTION_FALL, defer snapshot

    ; Player is standing on solid ground: return to IDLE immediately and snapshot
    move.w      #ACTION_IDLE,ActionStatus(a5)
    bsr         TakeSnapshot

.exit:
    rts


;==============================================================================
; ActionPlayerFall  -  Advance the active player's fall animation one frame
;
; Called from ActionFall each VBlank while Player_Fallen is set.
;
; The fall distance (in pixels) is (Player_NextY - Player_Y) * 16 (LSL.W #4).
; Player_ActionFrame acts as a velocity counter: it increments by 1 each frame
; and is added to Player_YDec, giving constant acceleration (quadratic distance
; growth).  The fall ends when Player_YDec reaches the total fall distance.
;
; On completion:
;   - Player_Fallen is cleared
;   - Player_YDec is cleared (player snaps to final position)
;   - Player_Y is set to Player_NextY
;
; While falling, the walk/fall animation cycles through PLAYER_FALL_OFFSET
; frames at 3-frame intervals.
;
; Destroys: d0-d2 (preserves everything else, including a5/a6)
;==============================================================================

ActionPlayerFall:
    tst.w       Player_Fallen(a4)      ; is the player currently in a fall?
    beq         .exit

    ; Calculate total fall distance in pixels: (NextY - Y) * 16
    move.w      Player_NextY(a4),d1
    sub.w       Player_Y(a4),d1
    lsl.w       #4,d1                  ; d1 = total fall distance in pixels (fall_tiles * 16)

    ; Accelerating fall: ActionFrame is the velocity (pixels/frame).
    ; Increment velocity first, then accumulate into YDec (position).
    addq.w      #1,Player_ActionFrame(a4)  ; velocity += 1 pixel/frame each frame
    move.w      Player_ActionFrame(a4),d2
    add.w       d2,Player_YDec(a4)         ; position += velocity
    move.w      Player_YDec(a4),d2         ; d2 = current pixel offset

    ; Clamp to total fall distance (handle overshoot from large velocity step)
    cmp.w       d1,d2
    blo         .inrange
    move.w      d1,d2                      ; clamp at maximum
    move.w      d1,Player_YDec(a4)

.inrange
    ; Check if we have reached the end of the fall
    cmp.w       d1,d2
    bne         .show                  ; not yet at the destination

    ; Fall complete: a long drop raises a dust puff (landing_puff.asm)
    cmp.w       #IMPACT_MIN_ROWS*TILEMAP_TILE_HEIGHT,d1
    blo.s       .no_puff
    move.w      #1,PlayerPuffTick(a5)
    move.w      Player_X(a4),PlayerPuffX(a5)
    move.w      Player_NextY(a4),PlayerPuffY(a5)
.no_puff:

    ; Snap to final position
    clr.w       Player_Fallen(a4)
    clr.w       Player_YDec(a4)
    move.w      Player_NextY(a4),Player_Y(a4)  ; commit final tile position
    move.w      Player_Y(a4),d1
    lsl.w       #4,d1
    move.w      d1,Player_PixelY(a4)           ; refresh pixel Y cache (Y * 16)

.show
    ; Animate fall BOB: cycle frames at 1/3 speed
    move.w      TickCounter(a5),d0
    divu        #3,d0                  ; one animation step every 3 frames
    swap        d0                     ; remainder -> d0 low word
    tst         d0
    bne         .noadd                 ; only advance animation on remainder == 0

    addq.w      #1,Player_AnimFrame(a4)
    and.w       #3,Player_AnimFrame(a4) ; cycle 0..3

.noadd
    move.w      Player_AnimFrame(a4),d0
    add.w       #PLAYER_FALL_OFFSET,d0     ; select fall animation frame
    bsr         ShowPlayer

.exit
    rts


;==============================================================================
; ActionMove  -  Smooth tile-to-tile movement animation (ACTION_MOVE state)
;
; Each frame:
;   1. Advance Player_XDec by DirectionX and Player_YDec by DirectionY.
;      (DirectionX/Y is -1, 0, or +1, giving 1 pixel per frame of movement)
;   2. Show the walk animation sprite.
;   3. Decrement Player_ActionCount.  Movement takes 16 frames (1 frame per pixel).
;   4. When ActionCount reaches 0, the move is complete:
;      - Clear ActionStatus to IDLE
;      - Clear XDec/YDec (snap to exact tile position)
;      - Call PlayerMoveLogic to update GameMap (move the player in the map)
;      - Call PlayerFallLogic to check if the player should now fall
;      - Call ActorFallAll to detect any actors whose support was removed (falling asynchronously)
;      - If the player itself is falling, enter ACTION_FALL; else snapshot and remain IDLE
;
; Destroys: d0-d5/d7/a0-a3 (preserves everything else, including a5/a6)
;==============================================================================

ActionMove:
    ; -------------------------------------------------------------------------
    ; Responsive Attack Interrupt:
    ; If player presses Fire/Space during movement (off-ladder), immediately
    ; interrupt walk and strike!
    ; -------------------------------------------------------------------------
    tst.w       Player_OnLadder(a4)
    bne.s       .no_move_attack
    btst        #CONTROLB_FIRE,ControlsTrigger(a5)
    beq.s       .no_move_attack

    ; Player pressed Fire while moving: snap to nearest tile and attack!
    cmp.w       #TILE_WIDTH/2,Player_ActionCount(a4)
    ble.s       .complete_and_attack

    ; Moved <= 7 pixels: snap back to starting tile
    clr.w       Player_XDec(a4)
    clr.w       Player_YDec(a4)
    clr.w       Player_ActionCount(a4)
    clr.w       PlayerMoved(a5)
    move.w      Player_X(a4),Player_NextX(a4)
    move.w      Player_Y(a4),Player_NextY(a4)
    clr.w       Player_DirectionX(a4)
    clr.w       Player_DirectionY(a4)
    bra         PlayerStartAttack

.complete_and_attack:
    ; Moved >= 8 pixels: complete move to destination tile
    clr.w       Player_XDec(a4)
    clr.w       Player_YDec(a4)
    clr.w       Player_ActionCount(a4)
    clr.w       Player_DirectionX(a4)
    clr.w       Player_DirectionY(a4)
    bsr         PlayerMoveLogic
    bsr         PlayerFallLogic
    cmp.w       #ACTION_FALL,ActionStatus(a5)
    beq.s       .exit
    bra         PlayerStartAttack

.no_move_attack:
    ; Advance sub-pixel position by the movement direction (1 pixel per frame)
    move.w      Player_XDec(a4),d0
    add.w       Player_DirectionX(a4),d0
    move.w      d0,Player_XDec(a4)

    move.w      Player_YDec(a4),d0
    add.w       Player_DirectionY(a4),d0
    move.w      d0,Player_YDec(a4)

    bsr         PlayerShowWalkAnim     ; update sprite for walking animation

    subq.w      #1,Player_ActionCount(a4)  ; one frame closer to destination
    bne         .exit                   ; still moving

    ; --- Move complete (ActionCount hit 0) ---
    clr.w       ActionStatus(a5)       ; return to IDLE
    clr.w       Player_XDec(a4)        ; snap to tile boundary
    clr.w       Player_YDec(a4)

    bsr         PlayerMoveLogic        ; update GameMap: clear old cell, fill new cell
    bsr         PlayerFallLogic        ; check if the player itself should now fall

    ; Check if any actors lost support and should fall asynchronously
    bsr         ActorFallAll           ; d5 = actors now falling

    ; If the player itself is falling (set by PlayerFallLogic), stay in ACTION_FALL
    ; and defer snapshot until landing. Otherwise return to IDLE and snapshot now.
    cmp.w       #ACTION_FALL,ActionStatus(a5)
    beq.s       .exit
    bsr         TakeSnapshot

.exit:
    rts


;==============================================================================
; ActionIdle  -  Idle state: poll input and trigger player actions
;
; Called every VBlank when ActionStatus = ACTION_IDLE.
; Sequence:
;   1. Check UNDO (F9).
;   2. Clear PlayerMoved (fresh movement detection for this frame).
;   3. ActorsSavePos - snapshot current actor positions as "previous".
;   4. PlayerCheckControls - read input and (possibly) start a new action.
;
; Level completion is checked every frame in LevelTest (main.asm) regardless
; of action state, so it is not checked here.
;
; Destroys: d0-d1/d4-d7/a0-a4 (preserves everything else, including a5/a6)
;==============================================================================

ActionIdle:
    tst.w       PlayerDrowning(a5)
    bne.s       .exit                   ; controls locked while drowning!

    ; F9 undo: handled at the start of VBlank in GameRun (fallback check if called directly)
    lea         Keys,a0
    tst.b       KEY_F9(a0)              ; F9 held down?
    beq.s       .nof9                   ; no: check other inputs
    clr.b       KEY_F9(a0)              ; clear key latch immediately
    cmp.w       #2,SnapshotCount(a5)    ; at least one move in the undo stack?
    blt         .f9_done                ; nothing to undo: clear key, skip both
    bsr         UndoMove
    bsr         VhsStartEffect
    bsr         AudioPlayRewind
.f9_done
    rts
.nof9
    ; Check attack key: Spacebar / Joy Fire / Down + Fire
    btst        #CONTROLB_FIRE,ControlsTrigger(a5)
    bne         PlayerStartAttack

    clr.w       PlayerMoved(a5)        ; clear "did player move this frame" flag
    bsr         ActorsSavePos          ; save all actor positions for delta detection

    bsr         PlayerCheckControls    ; process directional input; may set ActionStatus
.exit
    rts


;==============================================================================
; CheckLevelDone  -  Scan GameMap for remaining enemies
;
; Walks the entire GameMap (CurrentMapSize cells) looking for any cell that
; contains BLOCK_ENEMYFALL or BLOCK_ENEMYFLOAT.  If found,
; sets d3 = 1.  If none are found, d3 = 0 (level complete).
;
; Out:  d3 = 0 if no enemies remain (level done), 1 if enemies still present
;
; Destroys: d0/d3/d7/a0 (preserves everything else, including a5/a6)
;==============================================================================

CheckLevelDone:
    ; If level has animal friends, completion requires rescuing all friends
    tst.w       ActiveFriendCount(a5)
    beq.s       .check_legacy_enemies

    move.w      FriendsCollectedCount(a5),d0
    cmp.w       ActiveFriendCount(a5),d0
    blt.s       .notdone
    moveq       #0,d3                   ; all friends rescued -> Level Complete!
    rts

.check_legacy_enemies:
    tst.w       ActiveEnemyCount(a5)
    bne.s       .notdone

    lea         GameMap(a5),a0
    move.w      CurrentMapSize(a5),d7
    subq.w      #1,d7
    moveq       #0,d3                   ; assume no enemies (done = true)

.loop
    move.b      (a0)+,d0               ; load next map cell
    cmp.b       #BLOCK_ENEMYFALL,d0
    beq.s       .notdone               ; found a falling enemy -> not done
    cmp.b       #BLOCK_ENEMYFLOAT,d0
    bne.s       .next                  ; not an enemy -> continue

.notdone
    moveq       #1,d3                  ; enemy found -> level not complete
    rts

.next
    dbra        d7,.loop
    rts                                ; d3 = 0: no enemies remain


;==============================================================================
; PlayerMoveLogic  -  Update GameMap after the active player completes a move
;
; Called when ACTION_MOVE completes (ActionCount hits 0).
; Only runs if PlayerMoved is non-zero (set by PlayerDoMove).
;
; Updates GameMap:
;   - New cell (NextX, NextY): if it was a plain BLOCK_LADDER, set it to
;     Player_LadderId (occupying a ladder cell).  Otherwise set to Player_BlockId.
;   - Old cell (X, Y): if it was a player's ladder ID, restore to BLOCK_LADDER.
;     Otherwise set to BLOCK_EMPTY.
;   - Update Player_X/Y to Player_NextX/Y.
;
; Destroys: d0-d4/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

PlayerMoveLogic:
    tst.w       PlayerMoved(a5)
    beq         .nomove                ; PlayerMoved = 0 -> no update needed

    lea         GameMap(a5),a0

    ; Calculate map offsets for current and next positions
    move.w      Player_Y(a4),d0
    mulu        #MAP_WIDTH,d0
    add.w       Player_X(a4),d0        ; d0 = current cell offset

    move.w      Player_NextY(a4),d1
    mulu        #MAP_WIDTH,d1
    add.w       Player_NextX(a4),d1    ; d1 = next cell offset

    move.b      (a0,d0.w),d2           ; d2 = current cell type
    move.b      (a0,d1.w),d3           ; d3 = next cell type

    ; Write player's block ID into the next cell.
    ; If the next cell is a ladder variant, use the player's ladder ID instead
    ; and mark Player_OnLadder. Otherwise clear Player_OnLadder.
    move.b      Player_BlockId(a4),d4
    clr.w       Player_OnLadder(a4)    ; assume entering non-ladder cell
    cmp.b       #BLOCK_LADDER,d3
    beq.s       .is_ladder_next
    cmp.b       #BLOCK_PLAYERLADDER,d3
    beq.s       .is_ladder_next
    cmp.b       Player_LadderId(a4),d3
    bne.s       .notladdernext
.is_ladder_next:
    move.b      Player_LadderId(a4),d4  ; use ladder-specific ID (BLOCK_PLAYERLADDER)
    move.w      #1,Player_OnLadder(a4)  ; player is now occupying a ladder cell

.notladdernext
    move.b      d4,(a0,d1.w)           ; write player presence into next cell

    ; Clear the old cell: restore BLOCK_LADDER if cell has ladder, else BLOCK_EMPTY
    bsr         RestoreVacatedTile

    ; Commit tile-grid position and refresh pixel cache
    move.w      Player_NextX(a4),d0
    move.w      d0,Player_X(a4)
    mulu        #TILE_WIDTH,d0
    move.w      d0,Player_PixelX(a4)       ; cache X * 16
    move.w      Player_NextY(a4),d0
    move.w      d0,Player_Y(a4)
    lsl.w       #4,d0
    move.w      d0,Player_PixelY(a4)       ; cache Y * 16

.nomove
    rts




;==============================================================================
; PlayerFallLogic  -  Check if the active player should now fall
;
; Called after PlayerMoveLogic (when a move is complete).
; If the player did not move this frame, no fall check is needed.
;
; Checks the cell directly below the player's NEW position.  If empty and
; the player is not on a ladder, initiates a fall.
;
; Fall setup:
;   - Scan downward from current cell until a non-empty cell is found.
;   - Set Player_NextY to the tile just above that cell.
;   - Update GameMap: clear current cell, mark landing cell.
;   - Set Player_Fallen = 1, ActionStatus = ACTION_FALL.
;   - Reset animation frame counters.
;
; Destroys: d0-d4/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

PlayerFallLogic:
    tst.w       PlayerMoved(a5)
    beq         .exit                 ; no move this frame -> no fall check

    lea         GameMap(a5),a0

    ; Calculate map offset for current position (post-move)
    move.w      Player_Y(a4),d0
    mulu        #MAP_WIDTH,d0
    add.w       Player_X(a4),d0
    move.w      d0,d1

    ; Is the player currently on a ladder? If so, no fall.
    move.b      (a0,d1.w),d2
    cmp.b       #BLOCK_LADDER,d2
    beq         .exit
    cmp.b       #BLOCK_PLAYERLADDER,d2
    beq         .exit
    cmp.b       Player_LadderId(a4),d2
    beq         .exit

    ; Scan downward for the floor
    moveq       #0,d3                 ; fall distance in tiles
    move.w      Player_Y(a4),d4       ; d4 = current row

.findfloor
    addq.w      #1,d4                 ; row below
    cmp.w       CurrentMapHeight(a5),d4
    bge         .found                ; reached bottom of map
    move.b      MAP_WIDTH(a0,d1.w),d2 ; cell below
    beq.s       .air_below            ; empty air: keep falling
    cmp.b       #BLOCK_PLAYERSTART,d2
    beq.s       .air_below            ; player spawn marker: air, keep falling
    bra         .found                ; solid/ladder: found landing
.air_below:
    addq.w      #1,d3
    add.w       #MAP_WIDTH,d1
    bra         .findfloor

.found
    tst.w       d3
    beq         .exit                 ; floor directly below - no fall

    ; Set up fall parameters
    add.w       Player_Y(a4),d3       ; d3 = landing row (current Y + fall tiles)
    move.w      d3,Player_NextY(a4)   ; store landing tile Y
    move.w      Player_X(a4),Player_NextX(a4)  ; X unchanged during a vertical fall

    ; Update GameMap: clear current cell (restore ladder if applicable), mark landing cell
    bsr         RestoreVacatedTile
    move.b      Player_BlockId(a4),(a0,d1.w)

    ; Activate fall animation
    move.w      #1,Player_Fallen(a4)          ; player is now falling
    move.w      #ACTION_FALL,ActionStatus(a5) ; switch to fall state
    clr.w       Player_AnimFrame(a4)          ; reset animation frame
    clr.w       Player_ActionFrame(a4)        ; reset easing frame counter

.exit
    rts


;==============================================================================
; PlayerCheckControls  -  Dispatch to idle/frozen/inactive control handler
;
; Player is the player character (status=1).
;
; Uses JMPINDEX on Player_Status:
;   0 -> PlayerInactive  (character not yet placed)
;   1 -> PlayerIdle      (active, processes input)
;   2 -> PlayerFrozen    (frozen, ignores input)
;
; Destroys: d0 (preserves everything else, including a5/a6)
;==============================================================================

PlayerCheckControls:
    move.w      Player_Status(a4),d0  ; 0=inactive, 1=active, 2=frozen
    JMPINDEX    d0

.i
    dc.w        PlayerInactive-.i
    dc.w        PlayerIdle-.i
    dc.w        PlayerFrozen-.i


;==============================================================================
; PlayerFrozen  -  Frozen player does nothing
;
; Destroys: none (preserves all registers)
;==============================================================================

PlayerFrozen:
    rts


;==============================================================================
; PlayerInactive  -  Inactive player (not yet placed in level) does nothing
;
; Destroys: none (preserves all registers)
;==============================================================================

PlayerInactive:
    rts


;==============================================================================
; PlayerIdle  -  Process player input when idle and active
;
; Reads ControlsTrigger to detect newly-pressed direction keys.
; Priority order: RIGHT, LEFT, DOWN, UP.
; Only one direction is acted upon per frame (first match wins).
;
; Special UP handling: UP only triggers a move if the player is currently
; on a ladder cell (Player_LadderId check).  You cannot walk upward through air.
;
; If a direction is found, calls PlayerTryMove to determine what action to take.
; Also calls PlayerShowIdleAnim to animate the sprite while standing still.
;
; Destroys: d0-d2/a0 (preserves everything else, including a5/a6)
;==============================================================================

PlayerIdle:
    move.b      ControlsHold(a5),d0  ; d0 = newly-pressed keys this frame

    ; Clear both directions so left/right branches don't inherit a stale DirectionY
    ; from the previous frame (e.g. a ladder climb that has since ended).
    clr.w       Player_DirectionX(a4)
    clr.w       Player_DirectionY(a4)

    ; If on a ladder, prioritize vertical ladder controls!
    tst.w       Player_OnLadder(a4)
    bne.s       .ladder_input

    ; --- Ground / Platform controls ---
    btst        #CONTROLB_RIGHT,d0
    beq.s       .check_left
    cmp.w       #MAP_WIDTH-1,Player_X(a4) ; already in column 19?
    bge.s       .check_left                      ; yes -> clamp right (cannot move right)
    move.w      #1,Player_DirectionX(a4)
    bra         .move                            ; right pressed -> move right

.check_left
    btst        #CONTROLB_LEFT,d0
    beq.s       .check_vertical
    tst.w       Player_X(a4)                     ; already in column 0?
    ble.s       .check_vertical                  ; yes -> clamp left (cannot move left)
    move.w      #-1,Player_DirectionX(a4)
    bra         .move                            ; left pressed -> move left

.check_vertical
    clr.w       Player_DirectionX(a4)       ; no horizontal movement

    move.w      #1,Player_DirectionY(a4)    ; assume down
    btst        #CONTROLB_DOWN,d0
    bne         .move                       ; down pressed -> move down

    move.w      #-1,Player_DirectionY(a4)   ; assume up
    btst        #CONTROLB_UP,d0
    beq         .nomove                     ; up not pressed

    ; Up pressed: only allowed if currently on a ladder
    move.w      Player_Y(a4),d1
    mulu        #MAP_WIDTH,d1
    add.w       Player_X(a4),d1            ; d1 = map offset of current cell

    lea         GameMap(a5),a0
    move.b      (a0,d1.w),d1               ; d1 = cell type at current position
    cmp.b       #BLOCK_LADDER,d1
    beq         .move
    cmp.b       #BLOCK_PLAYERLADDER,d1
    beq         .move
    cmp.b       Player_LadderId(a4),d1
    beq         .move                      ; on ladder -> allow upward movement
    bra         .nomove

.ladder_input
    ; Ladder controls: check DOWN and UP first so diagonal/accidental inputs don't override climbing
    btst        #CONTROLB_DOWN,d0
    beq.s       .ladder_check_up
    move.w      #1,Player_DirectionY(a4)
    bra         .move

.ladder_check_up
    btst        #CONTROLB_UP,d0
    beq.s       .ladder_check_right
    move.w      #-1,Player_DirectionY(a4)
    bra         .move

.ladder_check_right
    btst        #CONTROLB_RIGHT,d0
    beq.s       .ladder_check_left
    cmp.w       #MAP_WIDTH-1,Player_X(a4)
    bge.s       .ladder_check_left
    move.w      #1,Player_DirectionX(a4)
    bra         .move

.ladder_check_left
    btst        #CONTROLB_LEFT,d0
    beq.s       .nomove
    tst.w       Player_X(a4)
    ble.s       .nomove
    move.w      #-1,Player_DirectionX(a4)
    bra         .move

.nomove
    clr.w       Player_DirectionX(a4)      ; cancel direction
    clr.w       Player_DirectionY(a4)
    bsr         PlayerShowIdleAnim         ; standing still: update idle animation
    rts

.move
    bsr         PlayerTryMove              ; try to move in the chosen direction
    tst.w       PlayerMoved(a5)            ; did the move succeed?
    beq.s       .move_blocked              ; no (blocked) -> show idle animation
    tst.w       Player_DirectionX(a4)      ; horizontal move?
    beq.s       .exit
    move.w      Player_DirectionX(a4),Player_Facing(a4) ; update facing only on actual horizontal move
.exit
    rts

.move_blocked
    bsr         PlayerShowIdleAnim         ; blocked: update idle animation
    rts


;==============================================================================
; PlayerShowIdleAnim  -  Animate the player BOB while standing still
;
; Called from PlayerIdle once per frame.  Advances the animation frame every
; 5 VBlanks (TickCounter mod 5 = 0) for a slower idle cycle.
;
; Selects the appropriate animation frame based on:
;   - If on a ladder: PLAYER_LADDER_IDLE (single frame, no cycling)
;   - If off ladder, facing right: walk cycle frame + PLAYER_WALK_OFFSET
;   - If off ladder, facing left: walk cycle frame + PLAYER_LEFT_OFFSET
;
; Also updates Player_OnLadder based on the player's current map cell.
;
; Destroys: d0-d2/a0 (preserves everything else, including a5/a6)
;==============================================================================

PlayerShowIdleAnim:
    ; Check if on a ladder FIRST
    move.w      Player_Y(a4),d1
    mulu        #MAP_WIDTH,d1
    add.w       Player_X(a4),d1       ; map offset

    lea         GameMap(a5),a0
    move.b      (a0,d1.w),d1          ; d1 = cell type at current position

    moveq       #0,d2
    cmp.b       #BLOCK_LADDER,d1
    beq.s       .is_ladder
    cmp.b       #BLOCK_PLAYERLADDER,d1
    beq.s       .is_ladder
    cmp.b       Player_LadderId(a4),d1
    beq.s       .is_ladder
    bra.s       .not_ladder

.is_ladder:
    moveq       #1,d2

.not_ladder:
    move.w      d2,Player_OnLadder(a4)  ; update on-ladder status
    beq.s       .off_ladder

    ; On ladder: ALWAYS show ladder idle pose (rear view)
    ; Never show left or right facing while on a ladder!
    moveq       #PLAYER_LADDER_IDLE,d0
    bsr         ShowPlayer
    rts

.off_ladder:
    ; Off ladder: advance animation every 5 frames
    move.w      TickCounter(a5),d0
    divu        #5,d0
    swap        d0                    ; remainder -> d0 low word
    tst.w       d0
    bne.s       .show_ground          ; not advancing this frame, but always refresh sprite

    ; Not on ladder: cycle walk animation frames 0..3
    move.w      Player_AnimFrame(a4),d0
    addq.w      #1,d0
    and.w       #3,d0
    move.w      d0,Player_AnimFrame(a4)

.show_ground:
    move.w      Player_AnimFrame(a4),d0
    and.w       #3,d0
    add.w       #PLAYER_IDLE_OFFSET,d0
    bsr         ShowPlayer            ; display the selected animation frame
    rts


;==============================================================================
; PlayerShowWalkAnim  -  Animate the player BOB while moving
;
; Called from ActionMove every frame.  Advances the animation cycle every
; other frame (TickCounter AND 1) for walk animation.
;
; Walk animation uses 4 frames (0..3) for off-ladder, 4 frames (0..3) for
; on-ladder climbing.
; Facing-left versions are flipped dynamically in TilemapDrawPlayer.
;
; Destroys: d0 (preserves everything else, including a5/a6)
;==============================================================================

PlayerShowWalkAnim:
    ; If moving vertically, we are DEFINITELY on a ladder!
    tst.w       Player_DirectionY(a4)
    bne.s       .ontladder

    ; Moving horizontally: we are walking (even if stepping off ladder)
    clr.w       Player_OnLadder(a4)
    bra.s       .advance_anim

.ontladder:
    move.w      #1,Player_OnLadder(a4)

.advance_anim:
    ; Only advance animation every other frame
    move.w      TickCounter(a5),d0
    and.w       #1,d0
    bne.s       .show                 ; odd frame: show but don't advance

    ; Advance walk animation (even frames only, 0..3)
    move.w      Player_AnimFrame(a4),d0
    addq.w      #1,d0
    and.w       #3,d0                 ; cycle 0..3 for both walk and ladder
    move.w      d0,Player_AnimFrame(a4)

.show:
    move.w      Player_AnimFrame(a4),d0
    and.w       #3,d0

    ; Determine if on ladder or walking
    tst.w       Player_OnLadder(a4)
    beq.s       .walking

    ; On ladder: use ladder offset (16)
    add.w       #PLAYER_LADDER_OFFSET,d0
    bsr         ShowPlayer
    rts

.walking:
    ; Off ladder: use walk offset (4)
    add.w       #PLAYER_WALK_OFFSET,d0
    bsr         ShowPlayer
    rts

;==============================================================================
; PlayerTryMove  -  Determine what action the player can take
;
; Based on Player_DirectionX/Y and the block type in the next cell,
; dispatches to the appropriate response routine.
;
; Calls PlayerGetNextBlock to read the block type at (X+DirX, Y+DirY).
; Then JMPINDEX on that block type to choose the action.
;
; Block type -> action dispatch:
;   BLOCK_EMPTY       -> PlayerMoveEmpty (walk into empty space or off ladder)
;   BLOCK_LADDER      -> PlayerDoMove   (walk onto/off ladder)
;   BLOCK_ENEMYFALL   -> PlayerKillEnemy (kill the enemy)
;   BLOCK_PUSH        -> PlayerPushBlock (check if the block can be pushed)
;   (unused slot 4)   -> PlayerNotMove  (wall: blocked)
;   BLOCK_SOLID       -> PlayerNotMove   (blocked by wall)
;   BLOCK_ENEMYFLOAT  -> PlayerKillEnemy (kill the floating enemy)
;   BLOCK_PLAYERSTART -> PlayerMoveEmpty (allow moving into player start / empty floor cells)
;   BLOCK_PLAYERLADDER-> PlayerMoveLadder (move along while on ladder)
;
; Destroys: d0-d2/a0 (preserves everything else, including a5/a6)
;==============================================================================

PlayerTryMove:
    move.w      Player_DirectionX(a4),d1
    bsr         PlayerGetNextBlock    ; d2 = block type of next cell, a0 = GameMap, d0 = offset

    JMPINDEX    d2                    ; jump based on next cell's block type

.i
    dc.w        PlayerMoveEmpty-.i    ; BLOCK_EMPTY       = 0
    dc.w        PlayerDoMove-.i       ; BLOCK_LADDER      = 1
    dc.w        PlayerKillEnemy-.i    ; BLOCK_ENEMYFALL   = 2
    dc.w        PlayerPushBlock-.i    ; BLOCK_PUSH        = 3
    dc.w        PlayerNotMove-.i      ; (unused)          = 4
    dc.w        PlayerNotMove-.i      ; BLOCK_SOLID       = 5
    dc.w        PlayerKillEnemy-.i    ; BLOCK_ENEMYFLOAT  = 6
    dc.w        PlayerMoveEmpty-.i    ; BLOCK_PLAYERSTART = 7  (empty/walkable in single player)
    dc.w        PlayerNotMove-.i      ; (unused)          = 8
    dc.w        PlayerMoveLadder-.i   ; BLOCK_PLAYERLADDER= 9
    rts


;==============================================================================
; PlayerNotMove  -  Blocked move (wall or other player's cell)
; Does nothing; the player simply cannot enter that cell.
;
; Destroys: none (preserves all registers)
;==============================================================================

PlayerNotMove:
    rts


;==============================================================================
; PlayerMoveEmpty  -  Move into an empty cell (BLOCK_EMPTY)
;
; Horizontal movement (walking) is always allowed into empty cells.
; Vertical movement (climbing up/down into empty space) is ONLY allowed if the
; player is currently occupying a ladder cell (e.g. climbing off the top rung
; onto a platform floor, or stepping down off a ladder into air to fall).
; Moving UP into empty air from a non-ladder cell is strictly blocked.
;
; Destroys: d1 (preserves everything else, including a5/a6)
;==============================================================================

PlayerMoveEmpty:
    tst.w       Player_DirectionY(a4)
    beq         PlayerDoMove          ; horizontal movement (DirectionY = 0) -> always allowed

    ; Moving vertically (UP or DOWN) into BLOCK_EMPTY:
    ; Only allowed if the player is currently on a ladder.
    move.w      Player_Y(a4),d1
    mulu        #MAP_WIDTH,d1
    add.w       Player_X(a4),d1       ; d1 = map offset of current cell
    move.b      (a0,d1.w),d1          ; d1 = cell type at current position
    cmp.b       #BLOCK_LADDER,d1
    beq         PlayerDoMove
    cmp.b       #BLOCK_PLAYERLADDER,d1
    beq         PlayerDoMove
    cmp.b       Player_LadderId(a4),d1
    beq         PlayerDoMove
    rts                               ; blocked: cannot move vertically into empty space


;==============================================================================
; PlayerMoveLadder  -  Move into a cell containing a ladder marker
;
; Moves along ladder cell if horizontal or valid vertical motion.
;
; Destroys: d0-d1 (preserves everything else, including a5/a6)
;==============================================================================

PlayerMoveLadder:
    bsr         PlayerDoMove
    rts


;==============================================================================
; PlayerKillEnemy  -  Walk into and destroy an enemy
;
; Enemies can only be killed by horizontal movement.
; Killing also triggers CleanActors (compact the actor list) and SortActors
; (re-sort by Y for correct draw order).
;
; Destroys: d0-d2/d6-d7/a0-a3 (preserves everything else, including a5/a6)
;==============================================================================

PlayerKillEnemy:
    tst.w       Player_DirectionY(a4)  ; vertical movement?
    bne         .nokill                ; yes - can't kill enemies from above/below
    bsr         PlayerDoMove
    bsr         PlayerKillActor
    bsr         CleanActors            ; compact actor list (remove dead slots)
    bsr         SortActors             ; re-sort by Y for correct rendering order
.nokill
    rts


;==============================================================================
; PlayerDoMove  -  Commit a tile-to-tile move
;
; Sets up all state for a standard 24-step movement animation:
;   - PlayerMoved = 1 (signals PlayerMoveLogic to update GameMap)
;   - Player_NextX/Y = target tile
;   - ActionStatus = ACTION_MOVE
;   - Player_ActionCount = 24 (one frame per pixel)
;   - Clear XDec/YDec (start sub-pixel at 0)
;
; Destroys: d0-d1 (preserves everything else, including a5/a6)
;==============================================================================

PlayerDoMove:
    move.w      #1,PlayerMoved(a5)    ; flag that the player is moving this frame

    ; Calculate destination tile
    move.w      Player_DirectionX(a4),d0
    add.w       Player_X(a4),d0       ; d0 = target X tile
    bpl.s       .x_not_neg
    moveq       #0,d0                 ; clamp at 0
.x_not_neg
    cmp.w       #MAP_WIDTH-1,d0
    ble.s       .x_not_past_right
    move.w      #MAP_WIDTH-1,d0 ; clamp at 19
.x_not_past_right
    move.w      Player_DirectionY(a4),d1
    add.w       Player_Y(a4),d1       ; d1 = target Y tile

    move.w      d0,Player_NextX(a4)   ; store target X
    move.w      d1,Player_NextY(a4)   ; store target Y

    move.w      #ACTION_MOVE,ActionStatus(a5)  ; switch to MOVE state
    move.w      #TILE_WIDTH,Player_ActionCount(a4) ; 16 frames = 1 pixel/frame for 16px tile

    clr.w       Player_XDec(a4)       ; start sub-pixel offsets at 0
    clr.w       Player_YDec(a4)

    ; If moving vertically on a ladder, immediately ensure ladder state and clamped animation frame
    tst.w       Player_DirectionY(a4)
    beq.s       .exit_domove
    move.w      #1,Player_OnLadder(a4)
    and.w       #3,Player_AnimFrame(a4)
.exit_domove:
    bsr         PlayerShowWalkAnim
    rts


;==============================================================================
; ActionDeath  -  Player collapse / death animation handler (ACTION_DEATH)
;
; Cycles through the 4-cel collapse animation (Row 3, frames 12..15) then respawns.
;
; Destroys: d0-d4/d7/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

ActionDeath:
    subq.w      #1,PlayerDeathTimer(a5)
    ble.s       .death_complete         ; countdown ended: proceed to respawn

    move.w      PlayerDeathTimer(a5),d1

    ; Divide 48-frame death timer into 4 distinct animation cels (12 frames each):
    ;   Ticks 48..37: Cel 0 (frame 12: hit reaction / staggered)
    ;   Ticks 36..25: Cel 1 (frame 13: knees buckling)
    ;   Ticks 24..13: Cel 2 (frame 14: pitching forward onto ground)
    ;   Ticks 12..1 : Cel 3 (frame 15: collapsed flat on floor)
    moveq       #3,d0
    cmp.w       #12,d1
    ble.s       .show_death
    moveq       #2,d0
    cmp.w       #24,d1
    ble.s       .show_death
    moveq       #1,d0
    cmp.w       #36,d1
    ble.s       .show_death
    moveq       #0,d0

.show_death:
    add.w       #PLAYER_DEATH_OFFSET,d0 ; add Row 3 base frame offset (12)
    bsr         ShowPlayer
    rts

.death_complete:
    clr.w       PlayerDeathTimer(a5)
    bsr         PlayerRespawn           ; deduce life and restore to safe dry platform
    rts

