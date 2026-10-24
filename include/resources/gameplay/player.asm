
;==============================================================================
; AMIGA GAME ENGINE
; player.asm  -  Player Logic, Movement, Animation and Actor Interaction
;==============================================================================
;
; This file implements the player action state machine, movement physics,
; weapon attacks, collision detection, and survival mechanics:
;
; Core FSM & Movement:
;   PlayerLogic        - top-level dispatcher for ActionStatus
;   ActionIdle         - idle state: poll joystick/keys, trigger moves/attacks
;   ActionMove         - smooth tile-to-tile movement (16 pixel steps)
;   ActionFall         - player falling with quadratic easing
;   ActionPlayerPush   - push-block animation (sinusoidal easing)
;   ActionAttack       - cane swing animation, multi-frame active hitbox FSM
;   ActionDeath        - collapse animation before respawning
;   PlayerCheckControls- dispatch to active or inactive control handler
;   PlayerIdle         - process player directional input and attack triggers
;   PlayerShowIdleAnim - animate the player BOB when standing still
;   PlayerShowWalkAnim - animate the player BOB while moving
;   PlayerTryMove      - test target cell geometry and choose correct action
;   PlayerDoMove       - commit a standard move (set ActionStatus = ACTION_MOVE)
;   PlayerMoveActor    - push movable blocks in direction of travel
;   PlayerMoveLogic    - update GameMap and triggers after move completes
;   PlayerFallLogic    - test if active player has lost footing and should fall
;
; Combat, Enemies & Pickups:
;   PlayerStartAttack  - initiate cane swing attack animation
;   PlayerCheckAttackHit - test cane strike hitbox against all active enemies;
;                         stuns enemies with dizzy stars for ENEMY_STUN_DURATION
;   PlayerCheckEnemies - test player body against enemies; safe passage through
;                         stunned enemies, lethal contact triggers death/collapse
;   PlayerCheckFriends - test collision to rescue animal friends
;   PlayerCheckOxygen  - collect oxygen refills (inventory or immediate underwater use)
;
; Water & Survival:
;   PlayerUpdateOxygen - per-frame submersion detection, lung drain / refill,
;                         drowning death trigger, and safe dry platform tracking
;   PlayerRespawn      - decrement lives, relocate to safe dry platform, center
;                         camera, and activate temporary post-respawn invulnerability
;   FindDryPlatformAboveWater - upward search of GameMap for solid dry ground
;
; Graphics & BOB Management:
;   DrawPlayers        - update active player BOB frame
;   DrawPlayer         - select player BOB animation frame
;   ShowPlayer         - set active animation frame index (0..23)
;   PlayerInitFlippedSprites - mirror 24-frame player BOB sheet horizontally at
;                         boot into Chip RAM buffers (PlayerLeftRaw/Msk/White)
;
; Register convention:
;   a4 = current (active) player structure
;   a3 = current actor structure
;   a5 = Variables base
;   a6 = $dff000 (CUSTOM chip base)
;
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
;==============================================================================

ShowPlayer:
    tst.w     Player_Status(a4)          ; is this player active?
    bne.s     .go                        ; yes - cache frame
    rts

.go:
    move.w    d0,PlayerFrame(a5)      ; cache active BOB animation frame (0..47)
    rts

; Alias for backward compatibility:
ShowSprite = ShowPlayer


;==============================================================================
; GetBridgeYOffset
;
; Checks if the player is currently standing or walking on a bridge surface.
; If so, calculates a downward Y offset (in pixels) based on the player's
; horizontal position across the bridge to simulate the physical sag/drop.
;
; On entry:
;   d1 = player's world pixel X (Player_X * 16 + Player_XDec)
;   a4 = pointer to current player struct
;   a5 = Variables base
;
; On exit:
;   d3 = downward Y offset in pixels (0 if not on bridge)
;   Preserves: all registers except d3
;==============================================================================

GetBridgeYOffset:
    moveq     #0,d3                      ; default offset = 0

    ; If player is on a ladder or falling, do not apply bridge sag
    tst.w     Player_OnLadder(a4)
    bne.s     .done
    tst.w     Player_Fallen(a4)
    bne.s     .done

    ; If player is moving vertically (e.g. ladder or falling sub-pixel), skip
    tst.w     Player_YDec(a4)
    bne.s     .done

    ; Check if CurrentLevelDef is loaded
    move.l    CurrentLevelDef(a5),d3
    beq.s     .zero_offset
    movea.l   d3,a0

    ; Check if LevelDef_BridgeList is valid
    move.l    LevelDef_BridgeList(a0),d3
    beq.s     .zero_offset
    movea.l   d3,a1                      ; a1 -> BridgeList records
    moveq     #0,d3                      ; reset d3 to default 0

    ; Preserve scratch registers used during list iteration
    movem.l   d4/d6/a0,-(sp)

    ; Compute player's feet row = Player_Y(a4) + 1
    move.w    Player_Y(a4),d4
    addq.w    #1,d4                      ; d4 = platform row the player stands on

.bridge_loop:
    move.w    (a1),d6                    ; d6 = LeftX (or $ffff end marker)
    cmp.w     #$ffff,d6
    beq.s     .restore_and_done

    ; Check platform row match (offset +4: LeftX(w), RightX(w), PlatformRow(w), Reserved(w))
    cmp.w     4(a1),d4
    bne.s     .next_bridge

    ; Check horizontal bounds: LeftX <= PlayerPixelX < RightX
    cmp.w     d6,d1                      ; compare PlayerPixelX with LeftX
    blt.s     .next_bridge               ; PlayerPixelX < LeftX -> outside
    cmp.w     2(a1),d1                   ; compare PlayerPixelX with RightX
    bge.s     .next_bridge               ; PlayerPixelX >= RightX -> outside

    ; Player is on this bridge! Compute relative X across bridge:
    ; RelX = PlayerPixelX - LeftX
    move.w    d1,d3
    sub.w     d6,d3                      ; d3 = RelX (0..47)
    cmp.w     #48,d3
    bhs.s     .restore_zero              ; safety clamp: if >= 48, offset = 0

    lea       BridgeYOffsetTable(pc),a0
    move.b    (a0,d3.w),d3               ; d3 = offset byte from table
    ext.w     d3                         ; extend to word
    bra.s     .restore_and_done

.restore_zero:
    moveq     #0,d3
    bra.s     .restore_and_done

.next_bridge:
    addq.l    #8,a1                      ; advance to next bridge record (8 bytes)
    bra.s     .bridge_loop

.restore_and_done:
    movem.l   (sp)+,d4/d6/a0
    rts

.zero_offset:
    moveq     #0,d3
.done:
    rts


; 48-byte lookup table for 3-tile bridge sag (16px * 3 = 48px)
; Log 1 (0..7):     0px offset (flush with left platform)
; Log 2 (8..15):    1px offset (sloping down)
; Log 3-4 (16..32): 2px offset (center sag - 2 pixels lower in middle)
; Log 5 (33..39):   1px offset (sloping up)
; Log 6 (40..47):   0px offset (flush with right platform)
BridgeYOffsetTable:
    dc.b    0, 0, 0, 0, 0, 0, 0, 0     ; px 0..7   (Log 1)
    dc.b    1, 1, 1, 1, 1, 1, 1, 1     ; px 8..15  (Log 2)
    dc.b    2, 2, 2, 2, 2, 2, 2, 2     ; px 16..23 (Log 3)
    dc.b    2, 2, 2, 2, 2, 2, 2, 2     ; px 24..31 (Log 4)
    dc.b    2                          ; px 32     (transition pixel)
    dc.b    1, 1, 1, 1, 1, 1, 1        ; px 33..39 (Log 5)
    dc.b    0, 0, 0, 0, 0, 0, 0, 0     ; px 40..47 (Log 6)
    even


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
;   3 = ACTION_PLAYERPUSH  -> ActionPlayerPush
;   4 = ACTION_INTRO       -> ActionIntro  (level intro star animation)
;   5 = ACTION_SWITCH      -> ActionIntro  (player switch star animation; same body)
;
; Only one action runs at a time.  Each action handler is responsible for
; resetting ActionStatus to ACTION_IDLE when it completes.
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
    dc.w        ActionPlayerPush-.i     ; state 3: push animation
    dc.w        ActionIdle-.i           ; state 4: legacy intro (now idle)
    dc.w        ActionIdle-.i           ; state 5: legacy switch (now idle)
    dc.w        ActionAttack-.i         ; state 6: cane strike attack animation
    dc.w        ActionDeath-.i          ; state 7: player collapse death animation



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
; ActionFallActors  -  Animate all actors that are currently in a fall
;
; Iterates the FallenActors list (populated by ActorFallAll) and for each
; actor with Actor_HasFalled set:
;   1. RestoreBackgroundTile x2 - restore the two tiles the sprite spans
;   2. Increment Actor_YDec (accelerating: YDec/2 + 1 per frame)
;   3. DrawActor        - redraw at new sub-pixel position
;   4. When Actor_YDec reaches Actor_FallY: clear fall fields, set
;      Actor_ImpactTick = 1 to start the landing smoke animation, then
;      fall through into the impact section below.
;
; For each actor with Actor_ImpactTick > 0 (smoke animation in progress):
;   1. RestoreBackgroundTile + ActorDrawStatic - restore tile and redraw actor
;   2. DrawSprite - overlay the current smoke frame (SPRITE_SMOKE_A..D)
;   3. Increment Actor_ImpactTick; when it exceeds IMPACT_TOTAL_TICKS,
;      restore tile, redraw actor cleanly, clear Actor_ImpactTick.
;
; a2 (FallenActors list pointer) is preserved across all draw calls that
; corrupt it (PasteTile and DrawSprite both set a2 to their mask pointer).
;
; Out: d6 = number of actors still active (falling OR impact animating)
;==============================================================================

ActionFallActors:
    moveq       #0,d6                   ; d6 = running count of still-falling actors

    move.w      FallenActorsCount(a5),d7
    subq.w      #1,d7
    bmi         .exit                   ; no fallen actors

    lea         FallenActors(a5),a2     ; a2 -> array of pointers to falling actors

.loop
    move.l      (a2)+,a3                ; a3 -> actor struct

    tst.w       Actor_HasFalled(a3)     ; is this actor still falling?
    beq         .check_impact           ; no fall - check for pending impact animation

    addq.w      #1,d6                   ; count: one more actor still active

    ; ROOT CAUSE: ClearActor erases a 24-row window at PrevY*24+YDec, then
    ; DrawActor immediately redraws PrevY*24+(YDec+delta).  When delta is
    ; small (1,2,4... on early frames) 20-23 of the 24 cleared rows are
    ; repainted in the same frame, so every tile in the fall path appears
    ; unchanged for many frames — a persistent ghost.
    ;
    ; FIX: the sprite is 24 pixels tall and can span at most two tiles.
    ; Restore both tiles from NonDisplayScreen before every draw.  This gives
    ; a clean slate regardless of velocity, eliminating ghosts in the original
    ; tile and in every intermediate tile throughout the entire fall.
    ; Erase actor from previous sub-pixel position
    bsr         ClearActor

    moveq       #0,d0
    move.w      Actor_YDec(a3),d0
    lsr.w       #4,d0                    ; d0.w = floor(YDec/16) = whole tiles fallen
    move.w      Actor_PrevX(a3),d1      ; save tile X (preserved by RestoreBackgroundTile)
    move.w      Actor_PrevY(a3),d2      ; save base tile Y
    add.w       d0,d2                    ; d2 = tile Y of sprite top
    move.w      d1,d0                    ; d0 = tile X
    move.w      d2,d1                    ; d1 = tile Y (top)
    bsr         RestoreBackgroundTile    ; wipe tile containing sprite top
    addq.w      #1,d1                    ; tile immediately below = sprite bottom
    move.w      Actor_PrevX(a3),d0
    bsr         RestoreBackgroundTile    ; wipe tile containing sprite bottom

    ; Accelerating fall: velocity = YDec/2 + 1 (grows as fall distance increases)
    move.w      Actor_YDec(a3),d0
    lsr.w       #1,d0                   ; d0 = current distance / 2
    addq.w      #1,d0                   ; minimum 1 pixel/frame
    add.w       d0,Actor_YDec(a3)       ; advance fall position

    ; Clamp to target before drawing: prevents the sprite bleeding into the tile
    ; below the landing row when a large velocity step overshoots Actor_FallY.
    move.w      Actor_YDec(a3),d0
    cmp.w       Actor_FallY(a3),d0
    blo         .draw
    move.w      Actor_FallY(a3),Actor_YDec(a3)

.draw
    bsr         DrawActor               ; redraw at new (clamped) sub-pixel position

    ; Has the fall reached its target?
    move.w      Actor_YDec(a3),d0
    cmp.w       Actor_FallY(a3),d0     ; compare with target distance
    blo         .next                   ; still falling (unsigned less-than)

    ; Fall complete: clean up
    clr.w       Actor_YDec(a3)         ; reset sub-tile offset
    clr.w       Actor_HasFalled(a3)    ; mark fall as done
    move.w      #1,Actor_Dirty(a3)     ; flag settled actor for redraw
    move.w      Actor_Y(a3),Actor_PrevY(a3) ; update PrevY to match landed tile row
    move.w      #1,Actor_ImpactTick(a3) ; start smoke effect (falls through below)
    bsr         AudioPlayCrateImpact

.check_impact
    tst.w       Actor_ImpactTick(a3)   ; impact animation pending?
    beq         .next                   ; no - nothing to do

    addq.w      #1,d6                   ; impact in progress: keep ACTION_FALL alive

    ; Compute current smoke animation frame index (0..IMPACT_FRAMES-1)
    moveq       #0,d0
    move.w      Actor_ImpactTick(a3),d0
    subq.w      #1,d0                   ; 0-based tick (0..IMPACT_TOTAL_TICKS-1)
    divu        #IMPACT_FRAME_TICKS,d0  ; d0.w = frame index (0,1,2,3)

    ; Check if all smoke frames have played
    cmp.w       #IMPACT_FRAMES,d0
    bcc         .impact_done            ; frame >= 4: animation complete

    ; --- Draw smoke frame ---
    ; 1. Restore background from NonDisplayScreen (clears previous smoke frame)
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile

    ; 2. Redraw actor with transparency (NonDisplayScreen now clean underneath)
    bsr         ActorDrawStatic

    ; 3. Compute smoke sprite index: SPRITE_SMOKE_A + frame_index
    moveq       #0,d2
    move.w      Actor_ImpactTick(a3),d2
    subq.w      #1,d2
    divu        #IMPACT_FRAME_TICKS,d2  ; d2.w = frame index
    add.w       #SPRITE_SMOKE_A,d2      ; d2 = sprite sheet index

    ; 4. Pixel position of actor's landed tile
    move.w      Actor_X(a3),d0
    mulu        #24,d0                  ; pixel X
    move.w      Actor_Y(a3),d1
    mulu        #24,d1                  ; pixel Y

    ; 5. Blit smoke frame over actor (transparent overlay using SpriteMask)
    bsr         DrawSprite

    ; Smoke must stay on top of actor: cancel the dirty mark set by RestoreBackgroundTile above.
    ; FlushDirtyTiles checks each entry before acting: a 0 byte skips the redraw, leaving
    ; the composited smoke intact.  ActorDrawStatic sources transparent pixels from NonDisplayScreen
    ; which would erase the smoke if the redraw were allowed to proceed.
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    move.w      d1,d2
    mulu        #WALL_PAPER_WIDTH,d2
    add.w       d0,d2
    lea         DirtyTiles(a5),a0
    clr.b       (a0,d2.w)

    addq.w      #1,Actor_ImpactTick(a3) ; advance to next tick
    bra         .next

.impact_done
    ; All smoke frames shown: restore clean state (actor visible, no smoke)
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile        ; clear last smoke frame
    bsr         ActorDrawStatic         ; redraw actor cleanly
    clr.w       Actor_ImpactTick(a3)    ; mark animation complete

.next
    dbra        d7,.loop

.exit:
    tst.w       d6                      ; return d6 (0 = all falls and impacts done)
    bne.s       .still_active
    clr.w       FallenActorsCount(a5)   ; all falls and impacts settled: reset list count
.still_active:
    rts


;==============================================================================
; ActionPlayerPush  -  Animate a block being pushed (ACTION_PLAYERPUSH state)
;
; Called once per frame while a block is being pushed.  Uses a quadratic easing
; curve (Quadratic table, assets/quadratic.bin) to produce a smooth
; acceleration/deceleration motion for the pushed block.
;
; PUSH_STEPS  = 12 animation frames for a full push (24 pixel travel)
; PUSH_DELTA  = angular increment per frame in the Quadratic table index space
;              = (SINE_ANGLES << 16) / 2 / PUSH_STEPS
;              (maps PUSH_STEPS frames to a half-period of the quadratic curve)
;
; Per frame:
;   1. ClearActor   - erase the block from its current drawn position
;   2. Advance Actor_Delta by PUSH_DELTA (fixed-point angle accumulator)
;   3. Read Actor_Delta low word, add SINE_270 offset (start at the trough),
;      mask to SINE_RANGE-1, read Quadratic[index].
;   4. Scale the quadratic value: pixel_offset = quad * 12 / SINE_RANGE + 12
;      (gives 0..24 pixel range over the half-period, centred at 12)
;   5. Apply direction: if DirectionX is negative, negate offset.
;   6. Store as Actor_XDec.
;   7. DrawActor    - redraw at new position.
;   8. When ActionCounter reaches PUSH_STEPS (16), finalise the push:
;      clear XDec, update PrevX = X, commit player into vacated tile,
;      call PlayerFallLogic and ActorFallAll.
;      If the player itself falls, enter ACTION_FALL; otherwise return
;      immediately to ACTION_IDLE and take snapshot (actors fall asynchronously).
;==============================================================================

PUSH_STEPS  = 16
PUSH_DELTA  = (SINE_ANGLES<<16)/2/PUSH_STEPS

ActionPlayerPush:
    move.l      PushedActor(a5),a3     ; a3 -> the block being pushed

    ; Erase block from current drawn position
    bsr         ClearActor

    ; Advance the fixed-point angle accumulator
    lea         Quadratic,a0
    sub.l       #PUSH_DELTA,Actor_Delta(a3)  ; decrement angle (half-period, trough to peak)

    ; Sample the quadratic easing curve at the current angle
    moveq       #0,d0
    move.w      Actor_Delta(a3),d0    ; current angle (low word of fixed-point delta)
    add.w       #SINE_270,d0          ; start at the 270-degree (trough) point
    and.w       #SINE_RANGE-1,d0      ; wrap to table bounds
    add.w       d0,d0                 ; word index (table entries are words)
    move.w      (a0,d0.w),d0          ; d0 = quadratic value (-SINE_RANGE..+SINE_RANGE)

    ; Scale: map quadratic value to 0..16 pixel range
    muls        #(TILE_WIDTH/2),d0    ; scale by 8 (half of 16-pixel tile width)
    divs        #SINE_RANGE,d0        ; normalise to -8..+8
    add.w       #(TILE_WIDTH/2),d0    ; shift to 0..16 range

    ; Apply direction sign
    move.w      Actor_DirectionX(a3),d4
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

    ; Fall complete: snap to final position
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
; MarkTileDirty  -  Flag a tile cell for end-of-frame actor/player redraw
;
; Appends (X<<8)|Y to DirtyTileList and sets DirtyTiles[flat] = 1.
; Deduplicated: tiles already in the list are skipped (DirtyTiles[flat] != 0).
; FlushDirtyTiles iterates DirtyTileList (O(dirty count), not O(126)).
;
; Entry: d0 = tile X (0..WALL_PAPER_WIDTH-1), d1 = tile Y (0..WALL_PAPER_HEIGHT-1)
; Preserves: all registers (PUSHM/POPM d0-d2/a0-a1).
;==============================================================================

MarkTileDirty:
    PUSHM       d0-d2/a0-a1
    move.w      d1,d2
    mulu        #WALL_PAPER_WIDTH,d2       ; d2 = Y * 14
    add.w       d0,d2                      ; d2 = flat index into DirtyTiles
    lea         DirtyTiles(a5),a0
    tst.b       (a0,d2.w)                  ; already dirty this frame?
    bne         .done                       ; yes: already in DirtyTileList
    move.b      #1,(a0,d2.w)              ; mark dirty
    move.w      DirtyTileCount(a5),d2
    lsl.w       #1,d2                      ; byte offset = count * 2
    lea         DirtyTileList(a5),a1
    lsl.w       #8,d0                      ; d0.hi = tile X (0..13 fits in 1 byte)
    or.b        d1,d0                      ; d0.lo = tile Y (0..8); full word = (X<<8)|Y
    move.w      d0,(a1,d2.w)              ; append packed entry to list
    addq.w      #1,DirtyTileCount(a5)
.done
    POPM        d0-d2/a0-a1
    rts


;==============================================================================
; FlushDirtyTiles  -  Redraw settled actors and frozen player at all dirty tiles
;
; Iterates DirtyTileList (O(dirty count), not O(126)) built by MarkTileDirty.
; For each entry: unpack (X<<8)|Y, clear DirtyTiles[flat], call RedrawActorAtTile.
; Resets DirtyTileCount to 0 so the list is empty for the next frame.
;
; Entry: a5 = Variables, a6 = CUSTOM.
; Preserves: all registers (PUSHM/POPM).
;==============================================================================

FlushDirtyTiles:
    PUSHM       d0-d2/d7/a0-a1

    move.w      DirtyTileCount(a5),d7      ; d7 = number of dirty entries this frame
    beq         .exit
    clr.w       DirtyTileCount(a5)         ; reset for next frame
    subq.w      #1,d7
    lea         DirtyTiles(a5),a0
    lea         DirtyTileList(a5),a1

.fdt_loop
    move.w      (a1)+,d0                   ; d0 = packed (X<<8)|Y
    move.w      d0,d1
    and.w       #$ff,d1                    ; d1 = tile Y
    lsr.w       #8,d0                      ; d0 = tile X
    move.w      d1,d2
    mulu        #WALL_PAPER_WIDTH,d2
    add.w       d0,d2
    tst.b       (a0,d2.w)                  ; still dirty? (0 = cancelled by smoke/star overlay)
    beq         .fdt_next                   ; skip: caller already composited this tile
    clr.b       (a0,d2.w)                  ; clear dirty flag
    bsr         RedrawActorAtTile          ; redraws settled actor at (d0,d1) if any;
                                           ;   frozen player included via Actor_IsPlayer proxy
.fdt_next
    dbra        d7,.fdt_loop

.exit
    POPM        d0-d2/d7/a0-a1
    rts




;==============================================================================
; ClearDirtyTiles  -  Zero all dirty flags (called at level start from DrawMap)
;==============================================================================

ClearDirtyTiles:
    PUSHM       d0-d1/a0
    clr.w       DirtyTileCount(a5)         ; reset compact list count
    lea         DirtyTiles(a5),a0
    moveq       #0,d0
    move.w      #(MAX_GAME_MAP_SIZE/32)-1,d1 ; 1280 / 32 = 40 iterations
.cdt_loop:
    move.l      d0,(a0)+
    move.l      d0,(a0)+
    move.l      d0,(a0)+
    move.l      d0,(a0)+
    move.l      d0,(a0)+
    move.l      d0,(a0)+
    move.l      d0,(a0)+
    move.l      d0,(a0)+
    dbra        d1,.cdt_loop
    POPM        d0-d1/a0
    rts


;==============================================================================
; RedrawActorAtTile  -  Redraw any live actor at the given tile position
;
; Called after RestoreBackgroundTile during the star animation so that actors
; whose tiles are restored by trail cleanup or the large-star erase do not
; disappear from the screen mid-animation.
;
; Entry: d0 = tile X, d1 = tile Y
; Preserves: all registers (PUSHM d0-d2/d7/a0-a3).
;==============================================================================

RedrawActorAtTile:
    PUSHM       d0-d2/d7/a0-a3
    move.w      ActorCount(a5),d7
    beq         .exit
    subq.w      #1,d7
    lea         ActorList(a5),a2            ; iterate ActorList (live actors only)
.scan
    move.l      (a2)+,a3                    ; a3 -> actor struct
    tst.w       Actor_Status(a3)            ; skip dead actors (killed but CleanActors not yet run)
    beq         .next
    tst.w       Actor_HasFalled(a3)         ; skip mid-fall actors (drawn sub-pixel by ActionFallActors)
    bne         .next
    cmp.w       Actor_X(a3),d0
    bne         .next
    cmp.w       Actor_Y(a3),d1
    bne         .next
    bsr         ActorDrawStatic             ; redraws actor tile onto DisplayScreen
    bra         .exit
.next
    dbra        d7,.scan
.exit
    POPM        d0-d2/d7/a0-a3
    rts


;==============================================================================
; ActionCloudActors  -  Animate all active cloud death animations


;==============================================================================
; ActionCloudActors  -  Animate all active cloud death animations
;
; Called every frame from GameRun, independent of the main action state.
; Iterates CloudActors[0..CloudActorsCount-1]; actors with CloudTick=0 are
; skipped (already done).
;
; Cloud frames are blitted to DisplayScreen via DrawSprite.  The player
; hardware sprite (SPR0-3) sits in front of the bitplane, so the cloud
; always appears behind the player - this is an accepted visual limitation.
;
; For each actor with Actor_CloudTick > 0:
;   1. Compute frame index = (Actor_CloudTick - 1) / CLOUD_FRAME_TICKS
;   2. If frame >= CLOUD_FRAMES: RestoreBackgroundTile, clear Actor_CloudTick.
;   3. Otherwise: RestoreBackgroundTile, DrawSprite(cloud frame), increment tick.
;
; Registers: a2=CloudActors pointer, a3=actor struct, d7=loop counter
;==============================================================================

ActionCloudActors:
    move.w      CloudActorsCount(a5),d7
    subq.w      #1,d7
    bmi         .exit                   ; no cloud actors registered

    lea         CloudActors(a5),a2      ; a2 -> cloud actor pointer array

.loop
    move.l      (a2)+,a3                ; a3 -> actor struct

    tst.w       Actor_CloudTick(a3)     ; animation active?
    beq         .next                   ; tick=0: already done, skip

    ; Compute frame index: (tick - 1) >> LOG2_CLOUD_FRAME_TICKS
    moveq       #0,d0
    move.w      Actor_CloudTick(a3),d0
    subq.w      #1,d0                   ; 0-based tick (0..CLOUD_TOTAL_TICKS-1)
    lsr.w       #LOG2_CLOUD_FRAME_TICKS,d0  ; d0.w = frame index (0..CLOUD_FRAMES-1+)

    cmp.w       #CLOUD_FRAMES,d0
    bcc         .cloud_done             ; frame >= CLOUD_FRAMES: all frames shown

    ; Save frame index before RestoreBackgroundTile clobbers d0
    move.w      d0,d3                   ; d3 = frame index

    ; --- Erase previous cloud frame ---
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile

    ; Build sprite index from saved frame (d3 free again after d2 set)
    move.w      d3,d2
    add.w       #SPRITE_CLOUD_A,d2      ; absolute sprite sheet index

    ; Pixel X = Actor_X * 16, Pixel Y = Actor_Y * 24
    move.w      Actor_X(a3),d0
    lsl.w       #4,d0

    move.w      Actor_Y(a3),d1
    move.w      d1,d3
    lsl.w       #4,d1
    lsl.w       #3,d3
    add.w       d3,d1

    bsr         DrawSprite

    addq.w      #1,Actor_CloudTick(a3)
    bra         .next

.cloud_done
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile   ; erase final cloud frame
    clr.w       Actor_CloudTick(a3)

.next
    dbra        d7,.loop

.exit
    rts


;==============================================================================
; ActionMove  -  Smooth tile-to-tile movement animation (ACTION_MOVE state)
;
; Each frame:
;   1. Advance Player_XDec by DirectionX and Player_YDec by DirectionY.
;      (DirectionX/Y is -1, 0, or +1, giving 1 pixel per frame of movement)
;   2. Show the walk animation sprite.
;   3. Decrement Player_ActionCount.  Movement takes 24 frames (1 frame per pixel).
;   4. When ActionCount reaches 0, the move is complete:
;      - Clear ActionStatus to IDLE
;      - Clear XDec/YDec (snap to exact tile position)
;      - Call PlayerMoveLogic to update GameMap (move the player in the map)
;      - Call PlayerFallLogic to check if the player should now fall
;      - Call ActorFallAll to detect any actors whose support was removed (falling asynchronously)
;      - If the player itself is falling, enter ACTION_FALL; else snapshot and remain IDLE
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
;==============================================================================

ActionIdle:
    tst.w       PlayerDrowning(a5)
    bne.s       .exit                   ; controls locked while drowning!

    ; F9 undo: check if key is held and cooldown has expired
    lea         Keys,a0
    tst.b       KEY_F9(a0)              ; F9 held down?
    beq.s       .nof9                   ; no: check other inputs
    clr.b       KEY_F9(a0)              ; clear key latch immediately
    cmp.w       #2,SnapshotCount(a5)    ; at least one move in the undo stack?
    blt         .f9_done                ; nothing to undo: clear key, skip both
    bsr         UndoMove
    bsr         VHS_StartEffect
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
; Walks the entire GameMap (WALL_PAPER_SIZE cells) looking for any cell that
; contains BLOCK_ENEMYFALL or BLOCK_ENEMYFLOAT.  If found,
; sets d3 = 1.  If none are found, d3 = 0 (level complete).
;
; Out:  d3 = 0 if no enemies remain (level done), 1 if enemies still present
;==============================================================================

CheckLevelDone:
    ; If level has animal friends, completion requires rescuing all friends
    tst.w       ActiveFriendCount(a5)
    beq.s       .check_legacy_enemies

    move.w      FriendsRescuedCount(a5),d0
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
;==============================================================================

PlayerMoveLogic:
    tst.w       PlayerMoved(a5)
    beq         .nomove                ; PlayerMoved = 0 -> no update needed

    lea         GameMap(a5),a0

    ; Calculate map offsets for current and next positions
    move.w      Player_Y(a4),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Player_X(a4),d0        ; d0 = current cell offset

    move.w      Player_NextY(a4),d1
    mulu        #WALL_PAPER_WIDTH,d1
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
;==============================================================================

PlayerFallLogic:
    tst.w       PlayerMoved(a5)
    beq         .exit                 ; no move this frame -> no fall check

    lea         GameMap(a5),a0

    ; Calculate map offset for current position (post-move)
    move.w      Player_Y(a4),d0
    mulu        #WALL_PAPER_WIDTH,d0
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
    move.b      WALL_PAPER_WIDTH(a0,d1.w),d2 ; cell below
    beq.s       .air_below            ; empty air: keep falling
    cmp.b       #BLOCK_PLAYERSTART,d2
    beq.s       .air_below            ; player spawn marker: air, keep falling
    bra         .found                ; solid/ladder: found landing
.air_below:
    addq.w      #1,d3
    add.w       #WALL_PAPER_WIDTH,d1
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
;==============================================================================

PlayerFrozen:
    rts


;==============================================================================
; PlayerInactive  -  Inactive player (not yet placed in level) does nothing
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
    cmp.w       #WALL_PAPER_WIDTH-1,Player_X(a4) ; already in column 19?
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
    mulu        #WALL_PAPER_WIDTH,d1
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
    cmp.w       #WALL_PAPER_WIDTH-1,Player_X(a4)
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
;==============================================================================

PlayerShowIdleAnim:
    ; Check if on a ladder FIRST
    move.w      Player_Y(a4),d1
    mulu        #WALL_PAPER_WIDTH,d1
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
; PlayerPushBlock  -  Attempt to push a block
;
; Only allowed for horizontal movement (DirectionX = +/-1, DirectionY = 0).
; Checks the cell BEYOND the push block (two cells ahead): empty allows a
; normal push. Anything else blocks the push silently.
;
; On entry:
;   a0 = GameMap base pointer (from PlayerGetNextBlock)
;   d0 = map offset of the PUSH block's cell
;==============================================================================

PlayerPushBlock:
    ; Only allowed for horizontal movement (DirectionX = +/-1, DirectionY = 0)
    tst.w       Player_DirectionY(a4)
    bne.s       .push_blocked
    tst.w       Player_DirectionX(a4)
    beq.s       .push_blocked

    ; Check if cell BEYOND the push block is within the same row (0 <= X + 2*DirX < CurrentMapWidth)
    move.w      Player_X(a4),d1
    add.w       Player_DirectionX(a4),d1  ; push block column
    add.w       Player_DirectionX(a4),d1  ; beyond push block column
    bmi.s       .push_blocked
    cmp.w       CurrentMapWidth(a5),d1
    bge.s       .push_blocked

    add.w       Player_DirectionX(a4),d0  ; advance to cell BEYOND the push block
    move.b      (a0,d0.w),d2              ; d2 = block type beyond
    beq         PlayerMoveActor           ; empty -> initiate push
    cmp.b       #BLOCK_PLAYERSTART,d2
    beq         PlayerMoveActor           ; player start / empty floor -> initiate push
    cmp.b       #BLOCK_LADDER,d2
    beq         PlayerMoveActor           ; ladder opening -> push it into the shaft
.push_blocked:
    rts                                   ; anything else -> blocked


;==============================================================================
; PlayerNotMove  -  Blocked move (wall or other player's cell)
; Does nothing; the player simply cannot enter that cell.
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
;==============================================================================

PlayerMoveEmpty:
    tst.w       Player_DirectionY(a4)
    beq         PlayerDoMove          ; horizontal movement (DirectionY = 0) -> always allowed

    ; Moving vertically (UP or DOWN) into BLOCK_EMPTY:
    ; Only allowed if the player is currently on a ladder.
    move.w      Player_Y(a4),d1
    mulu        #WALL_PAPER_WIDTH,d1
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
;==============================================================================

PlayerDoMove:
    move.w      #1,PlayerMoved(a5)    ; flag that the player is moving this frame

    ; Calculate destination tile
    move.w      Player_DirectionX(a4),d0
    add.w       Player_X(a4),d0       ; d0 = target X tile
    bpl.s       .x_not_neg
    moveq       #0,d0                 ; clamp at 0
.x_not_neg
    cmp.w       #WALL_PAPER_WIDTH-1,d0
    ble.s       .x_not_past_right
    move.w      #WALL_PAPER_WIDTH-1,d0 ; clamp at 19
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
; PlayerMoveActor  -  Initiate a block-push animation
;
; Searches ActorList for the actor at (Player_X + DirectionX, Player_Y).
; When found:
;   - Advances the actor's X by DirectionX (moves it one tile)
;   - Updates GameMap: clears the old cell, writes the actor's type to the new cell
;   - Sets Actor_Delta = 0 (easing accumulator reset)
;   - Sets ActionStatus = ACTION_PLAYERPUSH
;   - Stores the actor pointer in PushedActor for ActionPlayerPush to use
;   - Clears actor animation state (XDec, YDec, DirectionY, ActionCounter)
;
; Also initiates PlayerDoMove so the player walks into the block's old cell.
;==============================================================================

PlayerMoveActor:
    move.w      ActorCount(a5),d7
    beq         .exit                 ; no actors - nothing to push
    subq.w      #1,d7

    ; Calculate the position of the block to push (one tile ahead)
    move.w      Player_X(a4),d0
    move.w      Player_Y(a4),d1
    add.w       Player_DirectionX(a4),d0  ; d0 = X of the block

    lea         ActorList(a5),a2       ; a2 -> sorted actor pointer list

.loop
    move.l      (a2)+,a3              ; a3 -> next actor
    tst.w       Actor_Status(a3)      ; alive?
    beq         .next
    tst.w       Actor_HasFalled(a3)   ; currently falling? cannot push mid-air!
    bne         .next
    tst.w       Actor_ImpactTick(a3)  ; landing smoke active? cannot push until settled!
    bne         .next
    cmp.w       Actor_X(a3),d0        ; X matches?
    bne         .next
    cmp.w       Actor_Y(a3),d1        ; Y matches?
    bne         .next

    ; Found the block: advance its tile X position
    move.w      Player_DirectionX(a4),d2
    add.w       d2,Actor_X(a3)        ; actor X += direction
    move.w      #1,Actor_HasMoved(a3)  ; mark the actor as having moved (for ActionPlayerPush)

    ; Update GameMap: clear old cell, set new cell
    mulu        #WALL_PAPER_WIDTH,d1
    add.w       d1,d0                 ; d0 = map offset of old cell
    add.w       d0,d2                 ; d2 = map offset of new cell
    lea         GameMap(a5),a0
    move.b      (a0,d0.w),(a0,d2.w)   ; copy block type to new cell
    bsr         RestoreVacatedTile    ; restore old cell: BLOCK_LADDER if ladder, else BLOCK_EMPTY

    ; Update cached pixel X for the new tile position (16px tile stride)
    move.w      Actor_X(a3),d0
    lsl.w       #4,d0
    move.w      d0,Actor_PixelX(a3)

    ; Initialise push animation
    clr.l       Actor_Delta(a3)       ; reset easing accumulator
    move.l      a3,PushedActor(a5)   ; remember which actor is being pushed
    bsr         AudioPlayCratePush

    clr.w       Actor_XDec(a3)
    clr.w       Actor_YDec(a3)
    move.w      Player_DirectionX(a4),Actor_DirectionX(a3)  ; set push direction
    clr.w       Actor_DirectionY(a3)
    clr.w       ActionCounter(a5)    ; reset push frame counter in Variables

    ; Initiate player walk into the cell vacated by the block
    bsr         PlayerDoMove
    move.w      #ACTION_PLAYERPUSH,ActionStatus(a5)  ; enter push state (override ACTION_MOVE from PlayerDoMove)

    bra.s       .exit                 ; found the block - done

.next:
    dbra        d7,.loop

.exit:
    rts


;==============================================================================
; ActorFallAll  -  Check all eligible actors for falls and initiate them
;
; Iterates all live actors with Actor_CanFall = 1.
; For each such actor, calls ActorFall to check if it should fall.
; If ActorFall sets Actor_HasFalled (d3 != 0 on return), the actor is added
; to the FallenActors list for ActionFallActors to process each frame.
;
; Out:
;   d5 = total number of actors that will now fall (0 = no falls)
;   FallenActorsCount(a5) = d5
;==============================================================================

ActorFallAll:
    ; 1. Compact and preserve any actors currently falling or in impact animation
    moveq       #0,d5                 ; d5 = count of active falling actors
    move.w      FallenActorsCount(a5),d7
    beq.s       .no_existing
    subq.w      #1,d7
    lea         FallenActors(a5),a0   ; read cursor
    lea         FallenActors(a5),a1   ; write cursor
.compact_loop:
    move.l      (a0)+,a3
    tst.w       Actor_HasFalled(a3)
    bne.s       .keep
    tst.w       Actor_ImpactTick(a3)
    beq.s       .discard
.keep:
    move.l      a3,(a1)+
    addq.w      #1,d5
.discard:
    dbra        d7,.compact_loop

.no_existing:
    ; 2. Scan ActorList for any newly unsupported actors
    move.w      ActorCount(a5),d7
    beq.s       .done
    subq.w      #1,d7

    lea         ActorList(a5),a0       ; a0 -> sorted actor pointer array
    lea         FallenActors(a5),a2    ; a2 -> base of FallenActors
    move.w      d5,d0
    lsl.w       #2,d0                  ; byte offset = count * 4
    adda.l      d0,a2                  ; a2 -> write cursor (after preserved entries)

.loop:
    move.l      (a0)+,a3              ; a3 -> next actor
    tst.w       Actor_Status(a3)      ; alive?
    beq.s       .nofall
    tst.w       Actor_CanFall(a3)     ; subject to gravity?
    beq.s       .nofall
    tst.w       Actor_HasFalled(a3)    ; already falling? skip
    bne.s       .nofall
    tst.w       Actor_ImpactTick(a3)   ; already in impact animation? skip
    bne.s       .nofall

    PUSH        a0                    ; preserve list read pointer (ActorFall uses a0)
    bsr         ActorFall             ; check/initiate fall; d3 = 0 if no fall, non-zero if falling
    POP         a0

    tst.w       d3
    beq.s       .nofall               ; actor did not fall

    addq.w      #1,d5                 ; increment falling count
    move.l      a3,(a2)+              ; add actor to FallenActors list

.nofall:
    dbra        d7,.loop

.done:
    move.w      d5,FallenActorsCount(a5)  ; store count for ActionFallActors
    rts


;==============================================================================
; ActorFallAllAppend  -  Second-pass fall check after the frozen player moves
;
; Called after ActorFallAll + PlayerFallLogicFrozen when the frozen player has
; just started falling.  ActorFallAll ran before the frozen player's map cell
; was cleared, so any actor sitting on top of the frozen player was seen as
; supported and skipped.  This routine re-scans the actor list and appends any
; newly unsupported actors to the existing FallenActors list.
;
; Actors already falling (Actor_HasFalled = 1) are skipped.
;
; Out:
;   d5 = new total FallenActorsCount (existing + newly found falls)
;   FallenActorsCount(a5) updated
;==============================================================================

ActorFallAllAppend:
    move.w      FallenActorsCount(a5),d5   ; start from existing count
    move.w      ActorCount(a5),d7
    bne         .go
    rts

.go
    lea         ActorList(a5),a0            ; a0 -> sorted actor pointer array
    lea         FallenActors(a5),a2         ; a2 -> base of fallen actor pointer array
    move.w      d5,d0
    lsl.w       #2,d0                       ; byte offset = existing count * 4
    add.l       d0,a2                       ; a2 -> first free slot after existing entries
    subq.w      #1,d7

.loop
    move.l      (a0)+,a3
    tst.w       Actor_Status(a3)
    beq         .nofall
    tst.w       Actor_CanFall(a3)
    beq         .nofall
    tst.w       Actor_HasFalled(a3)         ; already falling this frame — skip
    bne         .nofall
    PUSH        a0
    bsr         ActorFall                   ; d3 != 0 if actor fell; updates GameMap + Actor fields
    POP         a0
    tst.w       d3
    beq         .nofall
    addq.w      #1,d5
    move.l      a3,(a2)+                    ; append to FallenActors
.nofall
    dbra        d7,.loop

    move.w      d5,FallenActorsCount(a5)
    rts


;==============================================================================
; ActorDrawStatic  -  Draw an actor at its current tile position
;
; Blits the actor's sprite tile into DisplayScreen at its tile-aligned position.
; Used to redraw an actor after it has landed at a new position.
;==============================================================================

ActorDrawStatic:
    move.w      d7,-(sp)
    move.w      Actor_SpriteOffset(a3),d0
    move.w      Actor_Y(a3),d2
    move.w      Actor_X(a3),d3
    bsr         TilemapBlitSingleTile

    ; Re-stamp foreground over settled actor tile
    move.w      Actor_X(a3),d0
    lsl.w       #4,d0
    move.w      Actor_Y(a3),d1
    lsl.w       #4,d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox

    ; Submerge check
    move.w      WaterPixelY(a5),d2
    bmi.s       .ads_skip
    move.w      d1,d4
    mulu.w      #TILEMAP_LINE_STRIDE,d4
    moveq       #0,d5
    move.w      d0,d5
    lsr.w       #4,d5
    add.w       d5,d5
    add.l       d5,d4
    lea         DisplayScreen,a0
    adda.l      d4,a0
    move.w      #16,d7
    move.w      WaterPixelY(a5),d2
    bsr         TilemapSubmergeActor

.ads_skip:
    clr.w       Actor_Dirty(a3)            ; tile is now correctly displayed
    move.w      (sp)+,d7
    rts


;==============================================================================
; ActorFall  -  Check if an actor should fall and set it up if so
;
; Scans the cells below the actor's current position in GameMap until a
; non-empty cell is found.  The count of empty cells is the fall distance.
; Ladders are treated as open shafts through which actors fall.
;
; If the actor is directly supported (cell below non-empty), no fall occurs
; and d3 = 0 on return.
;
; If the actor should fall:
;   - Actor_Y is advanced by the fall tile count
;   - Actor_FallY is set to (fall_tiles * 16) pixels (target for YDec)
;   - Actor_HasFalled = 1
;   - GameMap is updated: old cell cleared, new cell gets the actor type
;   - d3 = non-zero
;
; On entry:  a3 = actor struct pointer
; Destroys:  a0, d0, d1, d2, d3, d4
;==============================================================================

ActorFall:
    lea         GameMap(a5),a0

    ; Calculate map offset for actor's current position
    move.w      Actor_Y(a3),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Actor_X(a3),d0
    move.w      d0,d1                 ; d1 = current map offset

    moveq       #0,d3                 ; fall distance (tiles)

.findfloor:
    move.b      WALL_PAPER_WIDTH(a0,d1.w),d2  ; d2 = cell below
    beq.s       .fallrow              ; empty: keep scanning down
    cmp.b       #BLOCK_LADDER,d2      ; ladder shaft: fall through!
    beq.s       .fallrow
    cmp.b       #BLOCK_PLAYERLADDER,d2 ; ladder with player on it: also fall through!
    beq.s       .fallrow
    cmp.b       #BLOCK_PLAYERSTART,d2  ; player cell: fall through!
    beq.s       .fallrow
    bra.s       .found                ; real support: rest on top of it

.fallrow:
    addq.w      #1,d3                 ; fall one more row
    add.w       #WALL_PAPER_WIDTH,d1  ; advance map offset one row
    bra.s       .findfloor

.found:
    tst.w       d3
    beq.s       .exit                 ; no fall (floor is directly below)

    ; Lock PrevY to current Y before advancing Y to landing row
    move.w      Actor_Y(a3),Actor_PrevY(a3)
    clr.w       Actor_YDec(a3)
    clr.w       Actor_Dirty(a3)

    ; Commit the fall
    add.w       d3,Actor_Y(a3)        ; advance actor Y by fall distance
    move.w      d3,d4
    lsl.w       #4,d4                 ; convert tiles to 16px pixels
    move.w      d4,Actor_FallY(a3)    ; set pixel target for fall animation
    move.w      #1,Actor_HasFalled(a3) ; mark as falling
    move.b      (a0,d0.w),(a0,d1.w)   ; copy actor type from old to new map cell
    bsr         RestoreVacatedTile    ; restore old cell: BLOCK_LADDER if ladder, else BLOCK_EMPTY

    ; Update cached pixel Y for the new tile position
    move.w      Actor_Y(a3),d0
    lsl.w       #4,d0                 ; d0 = Actor_Y * 16
    move.w      d0,Actor_PixelY(a3)

.exit:
    rts


;==============================================================================
; PlayerKillActor  -  Find and kill an actor at the player's next position
;
; Searches ActorList for a live actor at (Player_NextX, Player_NextY).
; When found: sets Actor_Status = 0 (dead), clears the GameMap cell,
; and calls RestoreBackgroundTile to erase it from DisplayScreen.
;
; Also erases it from DisplayScreen by calling RestoreBackgroundTile.
;
; Note: CleanActors must be called separately to compact the ActorList.
;==============================================================================

PlayerKillActor:
    move.w      ActorCount(a5),d7
    beq         .exit                 ; no actors
    subq.w      #1,d7

    ; Target position = where the player is moving to
    move.w      Player_NextX(a4),d0
    move.w      Player_NextY(a4),d1

    lea         ActorList(a5),a2

.loop
    move.l      (a2)+,a3
    tst.w       Actor_Status(a3)
    beq         .next
    cmp.w       Actor_X(a3),d0        ; X matches?
    bne         .next
    cmp.w       Actor_Y(a3),d1        ; Y matches?
    bne         .next

    ; Register type-specific death animation
    move.w      Actor_Type(a3),d2
    cmp.w       #BLOCK_ENEMYFALL,d2
    beq.s       .setup_cloud
    cmp.w       #BLOCK_ENEMYFLOAT,d2
    bne.s       .skip_effects

.setup_cloud:
    ; Add to CloudActors list (bounds-checked; max MAX_ACTIVE_CRATES entries)
    move.w      CloudActorsCount(a5),d2
    cmp.w       #MAX_ACTIVE_CRATES,d2
    bge.s       .skip_effects           ; safety: pool full
    lea         CloudActors(a5),a0
    lsl.w       #2,d2                   ; byte offset = index * 4
    move.l      a3,(a0,d2.w)            ; CloudActors[count] = a3
    addq.w      #1,CloudActorsCount(a5)
    move.w      #1,Actor_CloudTick(a3)  ; start cloud animation on tick 1

.skip_effects
    clr.w       Actor_Status(a3)        ; mark as dead

    ; Clear the actor's cell in GameMap
    mulu        #WALL_PAPER_WIDTH,d1
    add.w       d1,d0
    lea         GameMap(a5),a0
    bsr         RestoreVacatedTile           ; restore ladder if cell has ladder, else empty

    ; Erase from screen
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile        ; erase tile from DisplayScreen
    bra         .exit

.next
    dbra        d7,.loop

.exit
    rts


;==============================================================================
; RestoreBackgroundTile  -  Erase a tile-aligned block from DisplayScreen
;
; Copies the tile from NonDisplayScreen -> DisplayScreen, then calls MarkTileDirty
; so any settled actor or frozen player at (d0,d1) is redrawn by FlushDirtyTiles at
; end of frame.  This makes draw order self-correcting without manual dirty calls.
;
; Exception: callers that composite a sprite OVER a live actor (e.g. impact smoke,
; star trail) must clear DirtyTiles(a5,flat_index) to 0 after DrawSprite.
; FlushDirtyTiles checks each entry before acting: a 0 byte cancels the redraw.
;
; On entry:
;   d0 = tile X  (multiplied by 24 to get pixels inside)
;   d1 = tile Y
;   a5, a6 as usual
;==============================================================================

RestoreBackgroundTile:
    PUSHM       d0-d2/a0-a1

    ; Bounds check col and row
    tst.w       d0
    bmi.s       .rbt_skip
    cmp.w       CurrentMapWidth(a5),d0
    bge.s       .rbt_skip
    tst.w       d1
    bmi.s       .rbt_skip
    cmp.w       CurrentMapHeight(a5),d1
    bge.s       .rbt_skip

    ; Screen offset = (row * 2560) + (col * 2)
    move.w      d1,d2
    mulu.w      #TILEMAP_ROW_STRIDE,d2  ; row * 2560
    moveq       #0,d1
    move.w      d0,d1
    add.w       d1,d1                   ; col * 2
    add.l       d1,d2

    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1
    adda.l      d2,a0
    adda.l      d2,a1

    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)      ; D = A (copy pristine tile from NonDisplayScreen)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)  ; word-aligned 16px tile
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTAMOD(a6) ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTDMOD(a6) ; 40 - 2 = 38
    move.l      a0,BLTAPT(a6)           ; source (NonDisplayScreen)
    move.l      a1,BLTDPT(a6)           ; dest (DisplayScreen)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|(TILEMAP_TILE_BYTES/2),BLTSIZE(a6) ; 64 lines x 1 word

    POPM        d0-d2/a0-a1
    bsr         TilemapSubmergeTile    ; apply water effect if restored tile is underwater
    bsr         MarkTileDirty          ; auto-flag for end-of-frame actor/frozen-player redraw
    rts

.rbt_skip:
    POPM        d0-d2/a0-a1
    bsr         MarkTileDirty          ; auto-flag for end-of-frame actor/frozen-player redraw
    rts


;==============================================================================
; ClearActor  -  Erase a moving actor from DisplayScreen
;
; Uses PrevX/PrevY tile position PLUS XDec/YDec sub-tile offsets to compute
; the exact WorldX and WorldY, then restores from NonDisplayScreen.
;
; On entry:
;   a3 = actor structure pointer
;   a5, a6 as usual
;==============================================================================

ClearActor:
    PUSHM       d0-d3/a0-a1

    ; Compute WorldX = PrevX * 16 + XDec
    move.w      Actor_PrevX(a3),d0
    lsl.w       #4,d0
    add.w       Actor_XDec(a3),d0

    ; Compute WorldY = PrevY * 16 + YDec
    move.w      Actor_PrevY(a3),d1
    lsl.w       #4,d1
    add.w       Actor_YDec(a3),d1

    bsr         TilemapErase16x16Actor

    POPM        d0-d3/a0-a1
    rts


;==============================================================================
; PlayerGetNextBlock  -  Return the block type at the cell the player will enter
;
; Calculates the map offset of (Player_X + DirectionX, Player_Y + DirectionY)
; and reads the block type from GameMap.
;
; On entry:
;   a4 = player struct pointer
;   a5 = Variables base
;
; On exit:
;   d0 = map offset (byte offset into GameMap)
;   d2 = block type at the next cell  (BLOCK_xxx)
;   a0 = GameMap base pointer  (callers use this for further checks)
;
; Note: DirectionX and DirectionY reflect the player's intended move direction.
;       One of them should be 0 and the other +/-1 for a valid move.
;==============================================================================

PlayerGetNextBlock:
    ; Check target column bounds: 0 <= X + DirX < WALL_PAPER_WIDTH
    move.w      Player_X(a4),d0
    add.w       Player_DirectionX(a4),d0
    bmi.s       .blocked
    cmp.w       #WALL_PAPER_WIDTH,d0
    bge.s       .blocked

    ; Check target row bounds: 0 <= Y + DirY < CurrentMapHeight(a5)
    move.w      Player_Y(a4),d1
    add.w       Player_DirectionY(a4),d1
    bmi.s       .blocked
    cmp.w       CurrentMapHeight(a5),d1
    bge.s       .blocked

    ; Calculate byte offset: (Y + DirY) * WALL_PAPER_WIDTH + (X + DirX)
    mulu        #WALL_PAPER_WIDTH,d1
    add.w       d1,d0                      ; d0 = byte offset into GameMap

    lea         GameMap(a5),a0
    moveq       #0,d2
    move.b      (a0,d0.w),d2              ; read block type at target cell
    rts

.blocked:
    lea         GameMap(a5),a0
    moveq       #BLOCK_SOLID,d2            ; out of bounds = solid block
    moveq       #0,d0                      ; safe offset
    rts


;==============================================================================
; RestoreVacatedTile  -  Restore GameMap cell to BLOCK_LADDER, BLOCK_SOLID, or BLOCK_EMPTY
;
; Called when an actor (push block, falling actor, killed actor) or player
; vacates a tile cell in GameMap.
;
; Checks LevelDef_LadderMap: if the cell has a ladder tile in the ladder layer,
; writes BLOCK_LADDER (1).
; Checks LevelDef_PlatformMap: if the cell has a platform tile in the platform layer,
; writes BLOCK_SOLID (5).
; Otherwise writes BLOCK_EMPTY (0).
;
; In:  d0.w = tile map offset (Row * WALL_PAPER_WIDTH + Col)
;      a0   = GameMap(a5) base pointer
; Preserves: d0, d2-d7, a0, a2-a6
; Destroys: d1, a1
;==============================================================================

RestoreVacatedTile:
    cmp.w       #0,d0
    blt.s       .rvt_exit
    cmp.w       CurrentMapSize(a5),d0
    bge.s       .rvt_exit

    move.l      CurrentLevelDef(a5),d1
    beq.s       .rvt_empty
    movea.l     d1,a1

    ; 1. Check ladder layer: if ladder tile present -> restore BLOCK_LADDER
    move.l      LevelDef_LadderMap(a1),d1
    beq.s       .rvt_check_platform
    movea.l     d1,a1
    move.w      d0,d1
    add.w       d1,d1                   ; d1 = offset * 2 (16-bit word entries)
    addq.w      #8,d1                   ; skip 8-byte width/height header
    tst.w       (a1,d1.w)               ; ladder layer has a tile at this cell?
    beq.s       .rvt_check_platform
    move.b      #BLOCK_LADDER,(a0,d0.w) ; cell has ladder -> restore BLOCK_LADDER!
    rts

.rvt_check_platform:
    ; 2. Check platform layer: if platform tile present -> restore BLOCK_SOLID
    move.l      CurrentLevelDef(a5),d1
    beq.s       .rvt_empty
    movea.l     d1,a1
    move.l      LevelDef_PlatformMap(a1),d1
    beq.s       .rvt_empty
    movea.l     d1,a1
    move.w      d0,d1
    add.w       d1,d1                   ; d1 = offset * 2 (16-bit word entries)
    addq.w      #8,d1                   ; skip 8-byte width/height header
    tst.w       (a1,d1.w)               ; platform layer has a tile at this cell?
    beq.s       .rvt_empty
    move.b      #BLOCK_SOLID,(a0,d0.w)  ; cell has platform -> restore BLOCK_SOLID!
    rts

.rvt_empty:
    clr.b       (a0,d0.w)               ; neither ladder nor platform -> restore BLOCK_EMPTY

.rvt_exit:
    rts


;==============================================================================
; PlayerUpdateOxygen  -  Update player submersion, oxygen level, and safe ground
;
; Called every active frame from GameRun (gamestatus.asm) right after
; TilemapUpdateWater.
;
; Submersion Rule:
;   Player World Y top = (Player_Y * 16) + Player_YDec - 8
;   Player Head Y      = World Y top + PLAYER_HEAD_Y_OFFSET (10)
;   If WaterPixelY >= 0 and Head Y >= WaterPixelY:
;     Player is submerged:
;       - Set PlayerSubmerged = 1
;       - Drain PlayerOxygen (-1 per frame)
;       - If PlayerOxygen <= 0: mark PlayerDrowning = 1
;   Else:
;     Player is surfaced:
;       - Set PlayerSubmerged = 0
;       - Clear PlayerDrowning = 0
;       - Replenish PlayerOxygen (+OXYGEN_REFILL_RATE per frame up to OXYGEN_MAX)
;
; Safe Platform Rule:
;   If Player is standing idle (ACTION_IDLE), tile-aligned, not on a ladder,
;   not falling, and feet are above water (Feet Y < WaterPixelY):
;     Update PlayerSafeX, PlayerSafeY, PlayerSafePixelX, PlayerSafePixelY.
;
; Preserves:
;   a5, a6
; Destroys:
;   d0-d3, a4
;==============================================================================

PlayerUpdateOxygen:
    lea         Player(a5),a4
    tst.w       Player_Status(a4)
    beq         .exit                   ; player not active

    ; If player is already dying (ACTION_DEATH), skip oxygen updates during death animation
    cmp.w       #ACTION_DEATH,ActionStatus(a5)
    beq         .exit

    ; -------------------------------------------------------------------------
    ; 1. Submersion Detection & Scanline Calculation
    ; -------------------------------------------------------------------------
    ; Calculate the player's top scanline in World coordinates:
    ;   Top Y = (Player_Y * 16) + Player_YDec - 8
    move.w      Player_Y(a4),d0
    lsl.w       #4,d0
    add.w       Player_YDec(a4),d0
    subq.w      #8,d0                   ; d0 = World Y top of player (24px BOB)

    ; Add mouth/snorkel line offset (PLAYER_HEAD_Y_OFFSET = 10 scanlines down).
    ; Submersion occurs only when the water level reaches the player's mouth,
    ; allowing the player to safely wade in knee- or chest-deep water.
    move.w      d0,d1
    add.w       #PLAYER_HEAD_Y_OFFSET,d1 ; d1 = Player Head/Mouth World Y

    move.w      WaterPixelY(a5),d2      ; d2 = WaterPixelY (0..671, or < 0 if no water)
    bmi         .dry                    ; if no water (< 0), completely dry

    cmp.w       d2,d1                   ; Head Y >= WaterPixelY?
    blt         .dry                    ; Head Y < WaterPixelY -> Head is above water (surfaced)!

    ; -------------------------------------------------------------------------
    ; Player Head is Underwater: Submerged State
    ; -------------------------------------------------------------------------
    move.w      #1,PlayerSubmerged(a5)

    ; Check if player holds an unconsumed Oxygen Kit in inventory:
    ; Automatically consumes kit upon water entry, granting instant 100% air
    ; and activating half-speed lung depletion (extended breath capacity).
    tst.w       OxygenKitInventory(a5)
    beq.s       .no_kit_activate
    clr.w       OxygenKitInventory(a5)  ; remove from inventory (hides HUD badge sprite)
    move.w      #1,OxygenKitActive(a5)  ; activate enhanced dark-blue oxygen mode
    move.w      #OXYGEN_MAX,PlayerOxygen(a5) ; refill lungs to 100% full breath
.no_kit_activate:

    ; Deplete lung capacity: -1 per frame normally (8.0s at 50Hz).
    ; If OxygenKitActive, depletion runs at half-speed (skipping odd frames).
    move.w      PlayerOxygen(a5),d3
    ble.s       .drown_trigger          ; breath depleted (<= 0) -> drown!

    tst.w       OxygenKitActive(a5)
    beq.s       .drain_normal

    ; Half-speed depletion: decrement only on even frames (TickCounter bit 0 == 0)
    move.w      TickCounter(a5),d0
    btst        #0,d0
    bne.s       .check_safe_ground      ; odd frame: skip decrement (doubles survival time)
.drain_normal:
    subq.w      #1,d3
    move.w      d3,PlayerOxygen(a5)
    bgt.s       .check_safe_ground      ; breath remains: continue checking safe ground

.drown_trigger:
    clr.w       PlayerOxygen(a5)        ; clamp gauge at 0
    ; -------------------------------------------------------------------------
    ; Out of Air! Trigger Player Drowning Sequence
    ; -------------------------------------------------------------------------
    ; Switches FSM to ACTION_DEATH, resets input/ladder flags, and clears
    ; oxygen kit states so the death sequence plays before respawning.
    move.w      #ACTION_DEATH,ActionStatus(a5)
    move.w      #PLAYER_DEATH_DURATION,PlayerDeathTimer(a5)
    bsr         AudioPlayPlayerDie
    clr.w       Player_DirectionX(a4)
    clr.w       Player_DirectionY(a4)
    clr.w       Player_ActionCount(a4)
    clr.w       Player_OnLadder(a4)
    clr.w       Player_Fallen(a4)
    clr.w       PlayerDrowning(a5)
    clr.w       PlayerDrownTimer(a5)
    clr.w       OxygenKitInventory(a5)
    clr.w       OxygenKitActive(a5)
    move.w      #PLAYER_DEATH_OFFSET,d0
    bsr         ShowPlayer
    bra.s       .exit

.dry:
    ; -------------------------------------------------------------------------
    ; Player Head is Above Water: Surfaced State
    ; -------------------------------------------------------------------------
    clr.w       PlayerSubmerged(a5)
    clr.w       PlayerDrowning(a5)
    clr.w       OxygenKitActive(a5)     ; reset oxygen kit enhancement once resurfaced

    ; Rapidly replenish oxygen (+OXYGEN_REFILL_RATE = 4 units per frame)
    ; Breath recovers fully in ~2.0 seconds at 50Hz.
    move.w      PlayerOxygen(a5),d3
    cmp.w       #OXYGEN_MAX,d3
    bge.s       .oxy_full
    addq.w      #OXYGEN_REFILL_RATE,d3
    cmp.w       #OXYGEN_MAX,d3
    ble.s       .save_oxy
    move.w      #OXYGEN_MAX,d3          ; clamp to max
.save_oxy:
    move.w      d3,PlayerOxygen(a5)
.oxy_full:

    ; -------------------------------------------------------------------------
    ; 2. Track Safe Dry Platform Coordinates
    ; -------------------------------------------------------------------------
    ; Only record a safe respawn platform when the player is fully stationary:
    ;   - In ACTION_IDLE state
    ;   - Not climbing a ladder
    ;   - Not mid-fall
    ;   - Aligned to tile grid (sub-pixel offsets XDec == 0, YDec == 0)
    ;   - Feet are strictly above current water scanline (Feet Y < WaterPixelY)
.check_safe_ground:
    cmp.w       #ACTION_IDLE,ActionStatus(a5)
    bne.s       .exit
    tst.w       Player_OnLadder(a4)
    bne.s       .exit
    tst.w       Player_Fallen(a4)
    bne.s       .exit
    tst.w       Player_XDec(a4)
    bne.s       .exit
    tst.w       Player_YDec(a4)
    bne.s       .exit

    ; Player feet scanline = (Player_Y * 16) + 15
    move.w      Player_Y(a4),d1
    lsl.w       #4,d1
    add.w       #15,d1                  ; d1 = feet scanline Y

    move.w      WaterPixelY(a5),d2
    bmi.s       .save_safe              ; no water in level -> safely dry!
    cmp.w       d2,d1                   ; feet Y >= WaterPixelY?
    bge.s       .exit                   ; feet submerged in water -> do not record as safe platform!

.save_safe:
    ; Update last known safe dry platform coordinates
    move.w      Player_X(a4),PlayerSafeX(a5)
    move.w      Player_Y(a4),PlayerSafeY(a5)
    move.w      Player_PixelX(a4),PlayerSafePixelX(a5)
    move.w      Player_PixelY(a4),PlayerSafePixelY(a5)

.exit:
    rts


;==============================================================================
; PlayerRespawn  -  Handle loss of life and reposition to safe dry platform
;
; In:  a4 = Player struct pointer
;      a5 = Variables base
;==============================================================================

PlayerRespawn:
    ; -------------------------------------------------------------------------
    ; 1. Deduct Life & Check Game Over
    ; -------------------------------------------------------------------------
    subq.w      #1,PlayerLives(a5)
    bgt.s       .has_lives

    ; Out of lives: trigger GAME OVER sequence (flashing placard -> title menu)
    clr.w       PlayerLives(a5)
    move.w      #GAME_OVER_SETUP,GameStatus(a5)
    rts

.has_lives:
    ; -------------------------------------------------------------------------
    ; 2. Erase Player Presence from GameMap at Old Coordinates
    ; -------------------------------------------------------------------------
    ; If player died while falling or sliding between cells, BOTH the current
    ; cell and the destination cell (Player_NextX/Y) might be marked in GameMap.
    ; Calling RestoreVacatedTile cleans both cells, preventing phantom solid blocks.
    lea         GameMap(a5),a0

    ; Clear old source cell (Player_X, Player_Y)
    move.w      Player_Y(a4),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Player_X(a4),d0
    bsr         RestoreVacatedTile

    ; Clear old destination cell (Player_NextX, Player_NextY)
    move.w      Player_NextY(a4),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Player_NextX(a4),d0
    bsr         RestoreVacatedTile

.check_safe_dry:
    ; -------------------------------------------------------------------------
    ; 3. Verify If Stored Safe Platform Is Still Above Water
    ; -------------------------------------------------------------------------
    ; Water rises continuously; the recorded safe platform might now be underwater!
    move.w      PlayerSafeY(a5),d0
    lsl.w       #4,d0
    add.w       #15,d0                  ; d0 = feet scanline Y of safe platform
    move.w      WaterPixelY(a5),d1
    bmi.s       .safe_ok                ; no water in level -> safely dry
    cmp.w       d1,d0
    blt.s       .safe_ok                ; feet Y < WaterPixelY -> safe platform is still dry!

    ; Safe platform has been overtaken by rising water!
    ; Perform dynamic upward search of GameMap to find dry solid ground above water:
    bsr         FindDryPlatformAboveWater

.safe_ok:
    ; -------------------------------------------------------------------------
    ; 4. Relocate Player to Safe Platform & Reset Dynamics
    ; -------------------------------------------------------------------------
    move.w      PlayerSafeX(a5),Player_X(a4)
    move.w      PlayerSafeY(a5),Player_Y(a4)
    move.w      PlayerSafeX(a5),Player_NextX(a4)
    move.w      PlayerSafeY(a5),Player_NextY(a4)
    move.w      PlayerSafePixelX(a5),Player_PixelX(a4)
    move.w      PlayerSafePixelY(a5),Player_PixelY(a4)
    clr.w       Player_XDec(a4)         ; tile-aligned
    clr.w       Player_YDec(a4)
    clr.w       Player_OnLadder(a4)     ; not on ladder
    clr.w       Player_Fallen(a4)       ; stationary on ground
    clr.w       Player_ActionCount(a4)
    clr.w       Player_DirectionX(a4)
    clr.w       Player_DirectionY(a4)
    move.w      #ACTION_IDLE,ActionStatus(a5) ; return FSM to idle
    move.w      Player_BobOffset(a4),PlayerFrame(a5)
    clr.w       Player_AnimFrame(a4)

    ; Mark player presence at new tile position in GameMap
    lea         GameMap(a5),a0
    move.w      Player_Y(a4),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Player_X(a4),d0
    move.b      Player_BlockId(a4),(a0,d0.w)

    ; -------------------------------------------------------------------------
    ; 5. Reset Survival & Invulnerability State
    ; -------------------------------------------------------------------------
    move.w      #OXYGEN_MAX,PlayerOxygen(a5) ; 100% full breath
    clr.w       PlayerSubmerged(a5)
    clr.w       PlayerDrowning(a5)
    clr.w       PlayerDrownTimer(a5)
    clr.w       OxygenKitInventory(a5)  ; lose unconsumed kit on death
    clr.w       OxygenKitActive(a5)
    move.w      #PLAYER_INVINCIBLE_DURATION,PlayerInvincibleTimer(a5) ; 2.0s immunity

    ; -------------------------------------------------------------------------
    ; 6. Recenter Camera Viewport on Respawned Player
    ; -------------------------------------------------------------------------
    ; Place player in vertical center of 200px visible area: (Player_Y * 16) - 100
    move.w      Player_Y(a4),d1
    lsl.w       #4,d1
    sub.w       #100,d1                 ; center vertically
    cmp.w       LevelMinCameraY(a5),d1
    bge.s       .cam_min
    move.w      LevelMinCameraY(a5),d1  ; clamp to top limit
.cam_min:
    cmp.w       LevelMaxCameraY(a5),d1
    ble.s       .cam_max
    move.w      LevelMaxCameraY(a5),d1  ; clamp to bottom limit
.cam_max:
    bsr         TilemapApplyCameraY     ; apply new camera position immediately
    rts


;==============================================================================
; FindDryPlatformAboveWater  -  Search GameMap upwards for a safe dry platform
;
; Scans GameMap from the row immediately above the water line upwards toward
; row 1. When a BLOCK_SOLID or platform tile with air above it is found,
; updates PlayerSafeX/Y/PixelX/PixelY.
;==============================================================================

FindDryPlatformAboveWater:
    PUSHM       d0-d4/a0
    move.w      WaterPixelY(a5),d0
    ble.s       .fail                   ; water at top of screen or inactive

    ; Start searching from the row just above the water line:
    ; Row = (WaterPixelY - 16) >> 4
    sub.w       #16,d0
    lsr.w       #4,d0                   ; d0 = candidate row index
    cmp.w       #TILEMAP_MAP_HEIGHT-1,d0
    ble.s       .row_clamp
    move.w      #TILEMAP_MAP_HEIGHT-2,d0
.row_clamp:

.row_search_loop:
    tst.w       d0
    ble.s       .fail                   ; reached top of map with no dry platforms found

    ; Search columns 0..TILEMAP_VIEW_COLS-1 in candidate row
    moveq       #0,d1                   ; d1 = column index
.col_search_loop:
    cmp.w       #TILEMAP_VIEW_COLS,d1
    bge.s       .next_row

    ; Check if (col, row) is solid in GameMap
    move.w      d0,d2
    mulu.w      #WALL_PAPER_WIDTH,d2
    add.w       d1,d2
    lea         GameMap(a5),a0
    cmp.b       #BLOCK_SOLID,(a0,d2.w)
    bne.s       .next_col               ; not solid ground: continue search

    ; Found solid ground tile! Check if cell directly above (row - 1) is empty/air
    move.w      d0,d3
    subq.w      #1,d3
    mulu.w      #WALL_PAPER_WIDTH,d3
    add.w       d1,d3
    move.b      (a0,d3.w),d4
    beq.s       .dry_air_ok             ; cell above is open air (0) -> valid standing spot!
    cmp.b       #BLOCK_PLAYERSTART,d4
    beq.s       .dry_air_ok             ; player spawn marker -> also valid!
    bra.s       .next_col               ; cell above is blocked by wall/actor

.dry_air_ok:
    ; Found dry platform! Store coordinates in PlayerSafe fields
    move.w      d1,PlayerSafeX(a5)
    move.w      d0,d4
    subq.w      #1,d4                   ; standing position is 1 row above floor
    move.w      d4,PlayerSafeY(a5)
    lsl.w       #4,d1
    move.w      d1,PlayerSafePixelX(a5)
    lsl.w       #4,d4
    move.w      d4,PlayerSafePixelY(a5)
    POPM        d0-d4/a0
    rts

.next_col:
    addq.w      #1,d1
    bra.s       .col_search_loop

.next_row:
    subq.w      #1,d0
    bra.s       .row_search_loop

.fail:
    POPM        d0-d4/a0
    rts


;==============================================================================
; PlayerCheckFriends  -  Test collision between player and animal friends
;
; If the player's bounding box overlaps an unrescued friend:
;   1. Mark friend as rescued (fi_Rescued = 1)
;   2. Increment FriendsRescuedCount(a5)
;
; In:  a5 = Variables base
; Destroys: none (preserves all registers)
;==============================================================================

PlayerCheckFriends:
    movem.l     d2-d5/a1/a4,-(sp)

    move.w      ActiveFriendCount(a5),d5
    beq.s       .done_check_friends
    subq.w      #1,d5

    lea         Player(a5),a4
    tst.w       Player_Status(a4)
    beq.s       .done_check_friends

    ; Load cached Player World coordinates
    move.w      Player_WorldX(a4),d0
    move.w      Player_WorldY(a4),d1

    lea         ActiveFriends(a5),a1    ; a1 = ActiveFriend pointer

.friend_loop:
    tst.w       fi_Type(a1)
    beq.s       .next_friend
    tst.w       fi_Rescued(a1)
    bne.s       .next_friend            ; already rescued

    ; Check Vertical Overlap first (coarse vertical early-out): abs(PlayerY - FriendY) < 18
    move.w      d1,d3
    sub.w       fi_Y(a1),d3
    bpl.s       .y_pos
    neg.w       d3
.y_pos:
    cmp.w       #18,d3
    bge.s       .next_friend            ; no vertical overlap

    ; Check Horizontal Overlap: abs(PlayerX - FriendX) < 14
    move.w      d0,d2
    sub.w       fi_X(a1),d2
    bpl.s       .x_pos
    neg.w       d2
.x_pos:
    cmp.w       #14,d2
    bge.s       .next_friend            ; no horizontal overlap

    ; --- Rescued! ---
    move.w      #1,fi_Rescued(a1)
    addq.w      #1,FriendsRescuedCount(a5)
    bsr         AudioPlayDuckRescue

.next_friend:
    lea         fi_SIZEOF(a1),a1
    dbra        d5,.friend_loop

.done_check_friends:
    movem.l     (sp)+,d2-d5/a1/a4
    rts


;==============================================================================
; PlayerCheckOxygen  -  Check player overlap with uncollected oxygen pickups
;
; If the player's bounding box overlaps an uncollected oxygen refill:
;   1. Mark bottle as collected (ox_Collected = 1)
;   2. Refill PlayerOxygen(a5) to OXYGEN_MAX (400)
;   3. Clear PlayerDrowning(a5) and PlayerDrownTimer(a5)
;
; In:  a5 = Variables base
; Destroys: none (preserves all registers)
;==============================================================================

PlayerCheckOxygen:
    movem.l     d2-d5/a1/a4,-(sp)

    move.w      ActiveOxygenCount(a5),d5
    beq.s       .done_check_oxygen
    subq.w      #1,d5

    lea         Player(a5),a4
    tst.w       Player_Status(a4)
    beq.s       .done_check_oxygen

    ; Load cached Player World coordinates
    move.w      Player_WorldX(a4),d0
    move.w      Player_WorldY(a4),d1

    lea         ActiveOxygen(a5),a1     ; a1 = ActiveOxygen pointer

.ox_loop:
    tst.w       ox_Collected(a1)
    bne.s       .next_ox                ; already collected

    ; Check Vertical Overlap first (coarse vertical early-out): abs(PlayerY - ox_Y) < 18
    move.w      d1,d3
    sub.w       ox_Y(a1),d3
    bpl.s       .y_pos
    neg.w       d3
.y_pos:
    cmp.w       #18,d3
    bge.s       .next_ox                ; no vertical overlap

    ; Check Horizontal Overlap: abs(PlayerX - ox_X) < 16
    move.w      d0,d2
    sub.w       ox_X(a1),d2
    bpl.s       .x_pos
    neg.w       d2
.x_pos:
    cmp.w       #16,d2
    bge.s       .next_ox                ; no horizontal overlap

    ; --- Oxygen Refill Picked Up! ---
    move.w      #1,ox_Collected(a1)
    move.w      #OXYGEN_MAX,PlayerOxygen(a5)
    clr.w       PlayerDrowning(a5)
    clr.w       PlayerDrownTimer(a5)
    bsr         AudioPlayOxygen

    ; If player is currently submerged / underwater, activate immediately
    tst.w       PlayerSubmerged(a5)
    bne.s       .ox_underwater

    ; Outside water: store in inventory (shows hardware sprite)
    move.w      #1,OxygenKitInventory(a5)
    clr.w       OxygenKitActive(a5)
    bra.s       .next_ox

.ox_underwater:
    ; Underwater: activate enhanced dark-blue oxygen immediately at 100%
    clr.w       OxygenKitInventory(a5)
    move.w      #1,OxygenKitActive(a5)

.next_ox:
    lea         ox_SIZEOF(a1),a1
    dbra        d5,.ox_loop

.done_check_oxygen:
    movem.l     (sp)+,d2-d5/a1/a4
    rts


;==============================================================================
; PlayerStartAttack  -  Initiate cane swing attack animation
;
; In: a4 = Player struct pointer
;     a5 = Variables base
;==============================================================================

PlayerStartAttack:
    move.w      #ACTION_ATTACK,ActionStatus(a5)
    move.w      #ATTACK_DURATION,PlayerAttackTimer(a5)
    bsr         AudioPlayCane

    ; Select initial wind-up cel (Frame 0: overhead cane)
    move.w      #PLAYER_ATTACK_OFFSET,d0        ; base attack (8)
    bsr         ShowPlayer
    rts


;==============================================================================
; ActionAttack  -  Cane swing animation & hitbox state handler (ACTION_ATTACK)
;
; Timing:
;   ATTACK_DURATION = 12 VBlanks (~240ms at 50Hz)
;   Ticks 11..10 (2 frames): Wind-up overhead (Cel 0, frame 8)
;   Ticks  9..5  (5 frames): Full strike forward (Cel 1, frame 9) [Active hit check]
;   Ticks  4..2  (3 frames): Follow-through downward arc (Cel 2, frame 10) [Active hit check]
;   Tick   1     (1 frame):  Recovery / return cane (Cel 3, frame 11)
;   Tick   0:                Returns to ACTION_IDLE
;
; Responsive chaining: if Fire is pressed during ticks 2..1, immediately
; starts a fresh attack swing without pausing in ACTION_IDLE.
;==============================================================================

ActionAttack:
    ; -------------------------------------------------------------------------
    ; 1. Combo Chaining Check (Cancel Recovery into Fresh Attack)
    ; -------------------------------------------------------------------------
    ; During the last 2 frames of the swing (ticks 2..1), check if player pressed
    ; Fire again. If so, restart the attack immediately for responsive melee combos.
    move.w      PlayerAttackTimer(a5),d1
    cmp.w       #2,d1
    bgt.s       .no_chain
    btst        #CONTROLB_FIRE,ControlsTrigger(a5)
    bne         PlayerStartAttack       ; re-trigger fresh swing immediately
.no_chain:

    ; -------------------------------------------------------------------------
    ; 2. Advance Attack Animation Timer
    ; -------------------------------------------------------------------------
    subq.w      #1,PlayerAttackTimer(a5)
    ble.s       .attack_done            ; timer reached 0 -> finish attack

    move.w      PlayerAttackTimer(a5),d1

    ; -------------------------------------------------------------------------
    ; 3. Select Animation Cel & Dispatch Active Hitbox
    ; -------------------------------------------------------------------------
    cmp.w       #10,d1
    bge.s       .windup                 ; ticks 11..10: Cel 0 (overhead wind-up)

    cmp.w       #5,d1
    bge.s       .strike                 ; ticks 9..5: Cel 1 (extended strike)

    cmp.w       #2,d1
    bge.s       .followthrough          ; ticks 4..2: Cel 2 (downward arc follow-through)

.recovery:
    ; Tick 1: Cel 3 (pulling cane back to neutral)
    moveq       #3,d0
    bra.s       .show

.followthrough:
    ; Cel 2: downward arc sweeping through floor level.
    ; Hitbox remains active during this phase to hit low/bouncing enemies.
    bsr         PlayerCheckAttackHit
    moveq       #2,d0
    bra.s       .show

.strike:
    ; Cel 1: full forward reach of cane hook.
    ; Test hitbox on every frame of forward extension (ticks 9..5).
    bsr         PlayerCheckAttackHit
    moveq       #1,d0
    bra.s       .show

.windup:
    ; Cel 0: raising cane overhead
    moveq       #0,d0

.show:
    ; Map cel index (0..3) to master sheet BOB frame (Row 2, base offset 8)
    add.w       #PLAYER_ATTACK_OFFSET,d0
    bsr         ShowPlayer
    rts

.attack_done:
    ; Attack finished: restore idle state and standing animation
    move.w      #ACTION_IDLE,ActionStatus(a5)
    clr.w       PlayerAttackTimer(a5)
    bsr         PlayerShowIdleAnim
    rts


;==============================================================================
; PlayerCheckAttackHit  -  Test cane hitbox against all active enemies
;
; Cane reaches reliably in front of the player's 24px body.
; If hitbox overlaps an enemy, that enemy is stunned for ENEMY_STUN_DURATION (200).
;
; In:  a4 = Player struct pointer
;      a5 = Variables base
; Preserves all registers.
;==============================================================================

PlayerCheckAttackHit:
    PUSHM       d0-d7/a0-a4

    ; Early-out if no active enemies currently tracked in the level
    move.w      ActiveEnemyCount(a5),d7
    beq         .done_attack_hit
    subq.w      #1,d7

    ; Load cached Player World coordinates (top-left pixel of 24x24 body)
    move.w      Player_WorldX(a4),d0
    move.w      Player_WorldY(a4),d1

    ; -------------------------------------------------------------------------
    ; 1. Calculate Directional Cane Hitbox Horizontal Bounds [d2 .. d3]
    ; -------------------------------------------------------------------------
    ; Facing determines whether the cane hook extends forwards right or left:
    ;   Right facing (+1): X+4 to X+21 (stuns at distance 20, covering up to 9px gap)
    ;   Left facing  (-1): X-5 to X+12 (stuns at distance 20, covering up to 9px gap)
    tst.w       Player_Facing(a4)
    bmi.s       .hitbox_left

    ; Facing Right:
    move.w      d0,d2
    addq.w      #4,d2                       ; Cane Left  = WorldX + 4
    move.w      d0,d3
    add.w       #21,d3                      ; Cane Right = WorldX + 21
    bra.s       .hitbox_y

.hitbox_left:
    ; Facing Left:
    move.w      d0,d2
    subq.w      #5,d2                       ; Cane Left  = WorldX - 5
    move.w      d0,d3
    add.w       #12,d3                      ; Cane Right = WorldX + 12

.hitbox_y:
    ; -------------------------------------------------------------------------
    ; 2. Calculate Vertical Bounds [d4 .. d5]: WorldY + 2 to WorldY + 24
    ; -------------------------------------------------------------------------
    ; Covers shoulder height down to floor level (matches cane sprite arc)
    move.w      d1,d4
    addq.w      #2,d4                       ; Cane Top    = WorldY + 2
    move.w      d1,d5
    add.w       #24,d5                      ; Cane Bottom = WorldY + 24

    lea         ActiveEnemies(a5),a1

    ; -------------------------------------------------------------------------
    ; 3. Loop Through Active Enemies & Perform 2D AABB Overlap Test
    ; -------------------------------------------------------------------------
.enemy_hit_loop:
    tst.w       ei_Type(a1)
    beq.s       .next_enemy_hit             ; inactive slot: skip

    ; If enemy is already stunned, do not re-trigger or extend stun timer
    tst.w       ei_StunTimer(a1)
    bne.s       .next_enemy_hit

    ; Viewport / tier vertical overlap early-out (Y test first):
    ; Overlap test Y: (Cane Top < Enemy Bottom) AND (Cane Bottom > Enemy Top)
    move.w      ei_Y(a1),d0                 ; Enemy Top
    move.w      d0,d1
    add.w       #16,d1                      ; Enemy Bottom = ei_Y + 16

    cmp.w       d1,d4
    bge.s       .next_enemy_hit             ; Cane Top >= Enemy Bottom -> no overlap
    cmp.w       d0,d5
    ble.s       .next_enemy_hit             ; Cane Bottom <= Enemy Top -> no overlap

    ; Enemy is within vertical cane sweep: test horizontal overlap
    ; Enemy bounding box: [ei_X .. ei_X + 16]
    move.w      ei_X(a1),d0                 ; Enemy Left
    move.w      d0,d1
    add.w       #16,d1                      ; Enemy Right = ei_X + 16

    ; Overlap test X: (Cane Left < Enemy Right) AND (Cane Right > Enemy Left)
    cmp.w       d1,d2
    bge.s       .next_enemy_hit             ; Cane Left >= Enemy Right -> no overlap
    cmp.w       d0,d3
    ble.s       .next_enemy_hit             ; Cane Right <= Enemy Left -> no overlap

    ; -------------------------------------------------------------------------
    ; Cane Connected! Stun the Enemy
    ; -------------------------------------------------------------------------
    ; Sets stun timer to 200 frames (~4.0s PAL).
    ; While stunned, TilemapDrawEnemies renders orbiting dizzy stars,
    ; and PlayerCheckEnemies deactivates lethal collision (safe passage).
    move.w      #ENEMY_STUN_DURATION,ei_StunTimer(a1)
    bsr         AudioPlayEnemyStun

.next_enemy_hit:
    lea         ei_SIZEOF(a1),a1            ; advance to next active enemy slot
    dbra        d7,.enemy_hit_loop

.done_attack_hit:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; PlayerCheckEnemies  -  Test player collision against all active enemies
;
; - If enemy is stunned (ei_StunTimer > 0): SAFE PASSAGE! (ignored, no damage)
; - If enemy is active (ei_StunTimer == 0): LETHAL CONTACT!
;   Triggers ACTION_DEATH collapse animation and loss of life.
;
; In: a5 = Variables base
; Preserves all registers.
;==============================================================================

PlayerCheckEnemies:
    movem.l     d2-d7/a1/a4,-(sp)

    ; Do not check lethal contact if already dying or inactive
    cmp.w       #ACTION_DEATH,ActionStatus(a5)
    beq         .done_check_enemies

    ; Invulnerable on respawn: complete immunity from all enemy damage
    tst.w       PlayerInvincibleTimer(a5)
    bne         .done_check_enemies

    move.w      ActiveEnemyCount(a5),d7
    beq         .done_check_enemies
    subq.w      #1,d7

    lea         Player(a5),a4
    tst.w       Player_Status(a4)
    beq         .done_check_enemies

    ; Load cached Player World coordinates
    move.w      Player_WorldX(a4),d0
    move.w      Player_WorldY(a4),d1

    ; -------------------------------------------------------------------------
    ; 1. Define Snug Player Vulnerability Hitbox
    ; -------------------------------------------------------------------------
    ; Inset from outer 24x24 BOB edges so collisions feel fair and forgiving:
    ;   Left = WorldX + 2, Right = WorldX + 14  (12px wide body)
    ;   Top  = WorldY + 4, Bottom = WorldY + 22 (18px tall body)
    move.w      d0,d2
    addq.w      #2,d2                       ; d2 = Player Left
    move.w      d0,d3
    add.w       #14,d3                      ; d3 = Player Right

    move.w      d1,d4
    addq.w      #4,d4                       ; d4 = Player Top
    move.w      d1,d5
    add.w       #22,d5                      ; d5 = Player Bottom

    lea         ActiveEnemies(a5),a1

    ; -------------------------------------------------------------------------
    ; 2. Iterate Enemies & Test Overlap
    ; -------------------------------------------------------------------------
.enemy_contact_loop:
    tst.w       ei_Type(a1)
    beq.s       .next_contact

    ; Safe passage: if stunned, lethal collision is deactivated!
    ; Player can walk right through the enemy while dizzy stars orbit overhead.
    tst.w       ei_StunTimer(a1)
    bne.s       .next_contact

    ; Coarse vertical overlap early-out (rejects enemies on different scanline tiers):
    move.w      ei_Y(a1),d0
    add.w       #14,d0                      ; Enemy Bottom = ei_Y + 14
    cmp.w       d4,d0
    ble.s       .next_contact               ; Enemy Bottom <= Player Top: skip!
    sub.w       #12,d0                      ; Enemy Top = ei_Y + 2
    cmp.w       d5,d0
    bge.s       .next_contact               ; Enemy Top >= Player Bottom: skip!

    ; Active enemy in vertical range: test horizontal overlap
    move.w      ei_X(a1),d0
    addq.w      #2,d0                       ; Enemy Left  = ei_X + 2
    move.w      ei_X(a1),d1
    add.w       #14,d1                      ; Enemy Right = ei_X + 14

    cmp.w       d1,d2
    bge.s       .next_contact               ; Player Left >= Enemy Right
    cmp.w       d0,d3
    ble.s       .next_contact               ; Player Right <= Enemy Left

    ; -------------------------------------------------------------------------
    ; Lethal Contact! Trigger Player Death Sequence
    ; -------------------------------------------------------------------------
    move.w      #ACTION_DEATH,ActionStatus(a5)
    move.w      #PLAYER_DEATH_DURATION,PlayerDeathTimer(a5) ; 48 frames (~960ms)
    bsr         AudioPlayPlayerDie
    clr.w       Player_DirectionX(a4)
    clr.w       Player_DirectionY(a4)
    clr.w       Player_ActionCount(a4)
    move.w      #PLAYER_DEATH_OFFSET,d0     ; Frame 12 (first death cel)
    bsr         ShowPlayer
    bra.s       .done_check_enemies

.next_contact:
    lea         ei_SIZEOF(a1),a1
    dbra        d7,.enemy_contact_loop

.done_check_enemies:
    movem.l     (sp)+,d2-d7/a1/a4
    rts


;==============================================================================
; ActionDeath  -  Player collapse / death animation handler (ACTION_DEATH)
;
; Cycles through the 4-cel collapse animation (Row 3, frames 12..15) then respawns.
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


;==============================================================================
; PlayerInitFlippedSprites  -  Initialize player sprite buffers
;
; Mia's right-facing master graphics are pre-loaded directly in Chip RAM
; (PlayerRightRaw, PlayerRightMsk, PlayerRightWhiteRaw).
;
; This routine:
;   1. Initializes active right-facing player stream pointers.
;   2. Horizontally mirrors the 24 frames into Chip RAM buffers
;      PlayerLeftRaw, PlayerLeftMsk, and PlayerLeftWhiteRaw.
;
; In:  none (runs at boot)
; Destroys: d0-d7, a0-a3
;==============================================================================

PlayerInitFlippedSprites:
    PUSHM       d0-d7/a0-a3

    ; -------------------------------------------------------------------------
    ; 0. Set Active Player Pointers to Chip RAM Right-Facing Buffers
    ; -------------------------------------------------------------------------
    lea         PlayerRightRaw,a0
    lea         PlayerRightMsk,a1
    lea         PlayerRightWhiteRaw,a3
    move.l      a0,PlayerGfxPtr(a5)
    move.l      a1,PlayerMskPtr(a5)
    move.l      a3,PlayerWhitePtr(a5)

    ; -------------------------------------------------------------------------
    ; 1. Allocate Temporary 256-Byte Bit-Reversal Table on Stack
    ; -------------------------------------------------------------------------
    ; The stack pointer is decremented by 256 bytes. This scratch table exists
    ; only during boot initialisation, avoiding 256 bytes of static ROM/RAM.
    lea         -256(sp),sp
    movea.l     sp,a2                   ; a2 = BitReverseTable pointer

    ; -------------------------------------------------------------------------
    ; 2. Generate 256-Entry Bit-Reversal Lookup Table
    ; -------------------------------------------------------------------------
    ; For each byte value d0 (0..255), shifts out bit-by-bit into carry (LSR.B)
    ; and rotates into d1 (ROXL.B) from the opposite side, reversing all 8 bits.
    clr.w       d0
.pifs_table_gen:
    clr.b       d1
    move.b      d0,d2
    lsr.b       #1,d2                   ; bit 0 -> carry
    roxl.b      #1,d1                   ; carry -> bit 0 (shifts left into bit 7)
    lsr.b       #1,d2                   ; bit 1 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 2 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 3 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 4 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 5 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 6 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 7 -> carry
    roxl.b      #1,d1
    move.b      d1,(a2,d0.w)            ; store reversed byte in lookup table
    addq.b      #1,d0                   ; next byte value
    bne.s       .pifs_table_gen         ; loop until d0 wraps back to 0 (256 iterations)

    ; -------------------------------------------------------------------------
    ; 3. Horizontally Flip All Three Selected Player Asset Streams into Left Buffers
    ; -------------------------------------------------------------------------
    ; Stream 1: Blitter Mask (PlayerMskPtr -> PlayerLeftMsk in Chip RAM)
    movea.l     PlayerMskPtr(a5),a0
    lea         PlayerLeftMsk,a1
    bsr.s       .pifs_flip_stream

    ; Stream 2: 4-Bitplane Raw Graphic (PlayerGfxPtr -> PlayerLeftRaw in Chip RAM)
    movea.l     PlayerGfxPtr(a5),a0
    lea         PlayerLeftRaw,a1
    bsr.s       .pifs_flip_stream

    ; Stream 3: White Silhouette Graphic (PlayerWhitePtr -> PlayerLeftWhiteRaw)
    movea.l     PlayerWhitePtr(a5),a0
    lea         PlayerLeftWhiteRaw,a1
    bsr.s       .pifs_flip_stream

    ; Deallocate stack table and restore caller registers
    lea         256(sp),sp
    POPM        d0-d7/a0-a3
    rts

.pifs_flip_stream:
    ; -------------------------------------------------------------------------
    ; 4. Cel Byte Re-ordering & Horizontal Bit-Reversal Engine
    ; -------------------------------------------------------------------------
    ; Player BOB sheet geometry:
    ;   - 144 scanlines tall * 4 bitplanes = 576 plane scanlines total
    ;   - Each plane scanline is 16 bytes wide (4 cels * 4 bytes per cel)
    ;   - In each 32px (4-byte) storage cel:
    ;       Byte 0: pixels 0..7
    ;       Byte 1: pixels 8..15
    ;       Byte 2: pixels 16..23  (24px active graphics end here)
    ;       Byte 3: pixels 24..31 (unused padding, always 0)
    ;
    ; To flip a 24-pixel cel horizontally across its active area:
    ;   New Byte 0 = reverse_bits(Old Byte 2)
    ;   New Byte 1 = reverse_bits(Old Byte 1)
    ;   New Byte 2 = reverse_bits(Old Byte 0)
    ;   New Byte 3 = 0 (retains 8-pixel padding)
    move.w      #(144*PLAYER_PLANES)-1,d7 ; d7 = 575 (576 plane scanlines)
.pifs_line_loop:
    moveq       #4-1,d6                 ; 4 cels of 32px per plane line (16 bytes)
.pifs_cel_loop:
    moveq       #0,d0
    moveq       #0,d1
    moveq       #0,d2
    move.b      (a0)+,d0                ; Old Byte 0 (pixels 0..7)
    move.b      (a0)+,d1                ; Old Byte 1 (pixels 8..15)
    move.b      (a0)+,d2                ; Old Byte 2 (pixels 16..23)
    addq.l      #1,a0                   ; Skip Old Byte 3 (padding)

    ; Look up reversed bytes and store in swapped order:
    move.b      (a2,d2.w),(a1)+         ; New Byte 0 = reverse(Old Byte 2)
    move.b      (a2,d1.w),(a1)+         ; New Byte 1 = reverse(Old Byte 1)
    move.b      (a2,d0.w),(a1)+         ; New Byte 2 = reverse(Old Byte 0)
    clr.b       (a1)+                   ; New Byte 3 = 0 (padding)
    dbra        d6,.pifs_cel_loop
    dbra        d7,.pifs_line_loop
    rts



