;==============================================================================
; AMIGA GAME ENGINE
; actor_physics.asm  -  Crate push, gravity and landing
;==============================================================================
;
; Tile-grid physics for the actors in actors.asm (crates, falling and floating
; blocks). Everything here works on GameMap and the ActorList; the game only
; decides when to call it and what the effects look like:
;
;   PlayerGetNextBlock - block type in the cell the player is about to enter
;   PlayerPushBlock    - start a push if the cell beyond the block is free
;   PlayerMoveActor    - move the block one tile and start ACTION_PUSH
;   ActorFallAll       - find every unsupported actor and start its fall
;   ActorFall          - fall distance for one actor; commits it to GameMap
;   ActionFallActors   - animate the falls and the landing effect each frame
;   PlayerKillActor    - remove the actor in the player's next cell
;   RestoreVacatedTile - put back the ladder or platform under a vacated cell
;
; The game animates the push itself (ActionPush in Duck Rescue) and
; supplies these hooks and routines (engine/ENGINE_CONTRACT.md):
;   GamePushMoveHook    - start the player's move into the vacated cell
;   GameActorImpactHook - draw landing-effect frame d2 at pixel (d0,d1)
;   AudioPlayCratePush, AudioPlayCrateImpact
;
; Register convention:
;   a4 = current (active) player structure
;   a3 = current actor structure
;   a5 = Variables base
;   a6 = $dff000 (CUSTOM chip base)
;==============================================================================


;==============================================================================
; ActionFallActors  -  Animate all actors that are currently in a fall
;
; Iterates the FallenActors list (populated by ActorFallAll) and for each
; actor with Actor_HasFalled set:
;   1. RestoreBackgroundTile x2 - restore the two tiles the sprite spans
;   2. Increment Actor_YDec (accelerating: YDec/2 + 1 per frame)
;   3. DrawActor        - redraw at new sub-pixel position
;   4. When Actor_YDec reaches Actor_FallY: clear fall fields and, if the
;      fall was IMPACT_MIN_ROWS rows or more, set Actor_ImpactTick = 1 to
;      start the landing effect in the impact section below.
;
; For each actor with Actor_ImpactTick > 0 (smoke animation in progress):
;   1. RestoreBackgroundTile + ActorDrawStatic - restore tile and redraw actor
;   2. GameActorImpactHook - the game draws its landing-effect frame
;   3. Increment Actor_ImpactTick; when it exceeds IMPACT_TOTAL_TICKS,
;      restore tile, redraw actor cleanly, clear Actor_ImpactTick.
;
; GameActorImpactHook must preserve d6-d7/a2-a3 (this loop's state).
;
; Out: d6 = number of actors still active (falling OR impact animating)
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
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
    ; The fall erases and redraws during the game logic, outside the
    ; top-down draw pass. Near the top of the view the beam can be on those
    ; lines right now, so wait for it to clear them first: the two tiles the
    ; crate spans and the next step down (48 lines from the top tile).
    move.w      Actor_YDec(a3),d0
    lsr.w       #4,d0
    add.w       Actor_PrevY(a3),d0      ; tile row of the crate's top
    lsl.w       #4,d0                   ; world Y of that row
    sub.w       TilemapCameraY(a5),d0   ; screen Y
    add.w       SpriteYOffset(a5),d0    ; raster line
    move.w      d0,d1
    add.w       #3*TILEMAP_TILE_HEIGHT-1,d1
    bsr         WaitBeamClearOfLines

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
    bsr         AudioPlayCrateImpact
    cmp.w       #IMPACT_MIN_ROWS*TILEMAP_TILE_HEIGHT,Actor_FallY(a3)
    blo         .next                   ; short drop: no landing effect
    move.w      #1,Actor_ImpactTick(a3) ; start the landing effect (falls through below)

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

    ; 3. Effect frame index (0..IMPACT_FRAMES-1)
    moveq       #0,d2
    move.w      Actor_ImpactTick(a3),d2
    subq.w      #1,d2
    divu        #IMPACT_FRAME_TICKS,d2  ; d2.w = frame index

    ; 4. Pixel position of actor's landed tile
    move.w      Actor_X(a3),d0
    lsl.w       #4,d0                   ; pixel X
    move.w      Actor_Y(a3),d1
    lsl.w       #4,d1                   ; pixel Y

    ; 5. The game draws its landing-effect frame over the actor
    bsr         GameActorImpactHook

    ; Smoke must stay on top of actor: cancel the dirty mark set by RestoreBackgroundTile above.
    ; FlushDirtyTiles checks each entry before acting: a 0 byte skips the redraw, leaving
    ; the composited smoke intact.  ActorDrawStatic sources transparent pixels from NonDisplayScreen
    ; which would erase the smoke if the redraw were allowed to proceed.
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    move.w      d1,d2
    mulu        #MAP_WIDTH,d2
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
; PlayerPushBlock  -  Attempt to push a block
;
; Only allowed for horizontal movement (DirectionX = +/-1, DirectionY = 0).
; Checks the cell BEYOND the push block (two cells ahead): empty allows a
; normal push. Anything else blocks the push silently.
;
; On entry:
;   a0 = GameMap base pointer (from PlayerGetNextBlock)
;   d0 = map offset of the PUSH block's cell
;
; Destroys: d0-d2 (preserves everything else, including a5/a6)
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
; PlayerMoveActor  -  Initiate a block-push animation
;
; Searches ActorList for the actor at (Player_X + DirectionX, Player_Y).
; When found:
;   - Advances the actor's X by DirectionX (moves it one tile)
;   - Updates GameMap: clears the old cell, writes the actor's type to the new cell
;   - Sets Actor_Delta = 0 (easing accumulator reset)
;   - Sets ActionStatus = ACTION_PUSH
;   - Stores the actor pointer in PushedActor for ActionPush to use
;   - Clears actor animation state (XDec, YDec, DirectionY, ActionCounter)
;
; Also calls GamePushMoveHook so the player walks into the block's old cell.
;
; Destroys: d0-d2/d7/a0-a3 (preserves everything else, including a5/a6)
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
    move.w      #1,Actor_HasMoved(a3)  ; mark the actor as having moved (for ActionPush)

    ; Update GameMap: clear old cell, set new cell
    mulu        #MAP_WIDTH,d1
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
    bsr         GamePushMoveHook
    move.w      #ACTION_PUSH,ActionStatus(a5)  ; enter push state (overrides whatever the hook set)

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
;
; Destroys: d0-d5/d7/a1-a3 (preserves everything else, including a5/a6)
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
    mulu        #MAP_WIDTH,d0
    add.w       Actor_X(a3),d0
    move.w      d0,d1                 ; d1 = current map offset

    moveq       #0,d3                 ; fall distance (tiles)

.findfloor:
    move.b      MAP_WIDTH(a0,d1.w),d2  ; d2 = cell below
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
    add.w       #MAP_WIDTH,d1  ; advance map offset one row
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
; Note: CleanActors must be called separately to compact the ActorList.
;
; Destroys: d0-d2/d7/a0-a3 (preserves everything else, including a5/a6)
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

    clr.w       Actor_Status(a3)        ; mark as dead

    ; Clear the actor's cell in GameMap
    mulu        #MAP_WIDTH,d1
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
;
; Destroys: d0-d2/a0 (preserves everything else, including a5/a6)
;==============================================================================

PlayerGetNextBlock:
    ; Check target column bounds: 0 <= X + DirX < MAP_WIDTH
    move.w      Player_X(a4),d0
    add.w       Player_DirectionX(a4),d0
    bmi.s       .blocked
    cmp.w       #MAP_WIDTH,d0
    bge.s       .blocked

    ; Check target row bounds: 0 <= Y + DirY < CurrentMapHeight(a5)
    move.w      Player_Y(a4),d1
    add.w       Player_DirectionY(a4),d1
    bmi.s       .blocked
    cmp.w       CurrentMapHeight(a5),d1
    bge.s       .blocked

    ; Calculate byte offset: (Y + DirY) * MAP_WIDTH + (X + DirX)
    mulu        #MAP_WIDTH,d1
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
; In:  d0.w = tile map offset (Row * MAP_WIDTH + Col)
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
