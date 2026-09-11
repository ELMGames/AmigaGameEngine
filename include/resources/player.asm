
;==============================================================================
; AMIGA GAME ENGINE
; player.asm  -  Player Logic, Movement, Animation and Actor Interaction
;==============================================================================
;
; This file implements the player action state machine and all gameplay logic:
;
;   PlayerLogic        - top-level dispatcher for ActionStatus
;   ActionIdle         - idle state: poll input, trigger moves
;   ActionMove         - smooth tile-to-tile movement (24 pixel steps)
;   ActionFall         - player falling with quadratic easing
;   ActionPlayerPush   - push-block animation (sinusoidal easing)
;   ActionFallActors   - animate actors that are falling simultaneously
;   PlayerCheckControls- dispatch to active/frozen/inactive sub-handlers
;   PlayerIdle         - process player input in idle state
;   PlayerShowIdleAnim - animate the player sprite when standing still
;   PlayerShowWalkAnim - animate the player sprite while moving
;   PlayerTryMove      - test the next cell and choose the correct action
;   PlayerDoMove       - commit a standard move (set ActionStatus = MOVE)
;   PlayerMoveActor    - find and push a block in the direction of movement
;   PlayerKillActor    - find and remove an enemy at the target cell
;   PlayerKillDirt     - remove a dirt block at the target cell
;   PlayerKillEnemy    - kill an enemy actor and clean actor list
;   PlayerMoveLogic    - update GameMap after a move completes
;   PlayerFallLogic    - check if the active player should now fall
;   PlayerFallLogicFrozen - check if the frozen player should fall
;   PlayerSwitch       - swap active and frozen player characters
;   DrawPlayerFrozen   - draw the frozen player in its idle/static pose
;   CheckLevelDone     - scan GameMap for remaining enemies
;   ActorFall          - find floor and initiate fall for one actor
;   ActorFallAll       - trigger falls for all eligible actors
;   ActorFallAllAppend - second-pass fall check after frozen player falls
;   ActorDrawStatic    - draw one actor at its current tile position
;   ClearPlayer        - erase the active player from DisplayScreen
;   RestoreBackgroundTile   - erase a tile-aligned block from DisplayScreen
;   ClearActor         - erase a (possibly shifted) actor from DisplayScreen
;   PlayerGetNextBlock - return the block type at the cell ahead of the player
;
; Register convention:
;   a4 = current (active) player structure
;   a3 = current actor structure
;   a5 = Variables base
;   a6 = $dff000 (CUSTOM chip base)
;
;==============================================================================

;==============================================================================
; DrawPlayers  -  Display both player characters each frame
;
; Millie: always rendered via hardware sprites (ShowSprite handles status
;         internally — ClearSprites if inactive, ShowSprite if active or frozen).
; Molly:  rendered via the blitter.
;         status=2 (frozen) -> DrawPlayerFrozen (static facing/ladder pose)
;         status=1 (active) -> DrawPlayer        (current animation frame)
;         status=0 (inactive) -> DrawPlayer      (early-exits, no blit)
;
; On entry: a5 = Variables base, a6 = CUSTOM base.
;==============================================================================

DrawPlayers:
    move.l     PlayerPtrs(a5),a4
    bsr        ShowSprite
    rts

;==============================================================================
; DrawPlayer  -  Blit one player's sprite to the screen (active animation frame)
;
; Converts the player's tile-grid position to pixel coordinates, selects the
; current animation frame from Player_SpriteOffset, and calls DrawSprite.
; Does nothing if Player_Status == 0 (player not yet placed in this level).
;
; On entry:
;   a4 = pointer to Player structure (Millie or Molly)
;   a5 = Variables base
;   a6 = CUSTOM base
;==============================================================================

DrawPlayer:
    tst.w      Player_Status(a4)
    beq        .exit
    move.w     Player_PixelX(a4),d0    ; cached: Player_X * 24
    move.w     Player_PixelY(a4),d1    ; cached: Player_Y * 24
    moveq      #0,d2
    add.w      Player_SpriteOffset(a4),d2
    bsr        DrawSprite
.exit
    rts

;==============================================================================
; ShowSprite  -  Display the player character using hardware sprites
;
; Calculates the pixel position from the player structure, selects the correct
; animation frame from PlayerHWSprites, writes the SPRxPOS/SPRxCTL header words
; via SpriteCoord, then patches the copper list sprite pointers.
;
; If the player is inactive (Player_Status = 0), all sprites are cleared
; by ClearSprites instead.
;
; On entry:
;   a4 = pointer to player structure (Millie or Molly)
;   a5 = Variables base pointer
;   a6 = $dff000 (CUSTOM chip base)
;
; Register usage:
;   d0 = sprite frame index (built from SpriteOffset + AnimFrame)
;   d1 = X pixel position
;   d2 = Y pixel position
;   d5 = attach/height word for SpriteCoord
;   a0 = pointer to current sprite structure in PlayerHWSprites
; Patches SpritePtrs+0..+4 (SPR0-1) and cpSprites+SPRITE_00_OFFSET..+SPRITE_01_OFFSET.
; Channels SPR2-5 remain free (NullSprite).
;==============================================================================

ShowSprite:
    tst.w     Player_Status(a4)          ; is this player active?
    bne       .go                        ; yes - proceed to display
    bsr       ClearSprites               ; no  - hide all sprites
    rts

.go
    move.w    d0,PlayerSpriteFrame(a5)   ; cache active hardware sprite frame offset

    ; Calculate pixel position from tile coordinates + sub-tile decimals
    moveq     #0,d1
    moveq     #0,d2
    move.w    Player_X(a4),d1            ; tile column
    move.w    Player_Y(a4),d2            ; tile row
    mulu      #TILE_WIDTH,d1             ; pixel X = tile_col * 16

    ; Adjust for continuous vertical camera viewport position
    lsl.w     #4,d2                      ; d2 = Player_Y * 16
    add.w     Player_YDec(a4),d2         ; d2 = Player_Y * 16 + Player_YDec (PlayerMapPixelY)
    sub.w     TilemapCameraY(a5),d2      ; d2 = PlayerMapPixelY - CameraPixelY
    subq.w    #8,d2                      ; lift sprite 8px: 24px sprite feet rest on 16px tile platform

    add.w     Player_XDec(a4),d1         ; add sub-tile X offset (animation interpolation)

    ; Adjust Y for bridge sag if walking across a bridge
    bsr       GetBridgeYOffset           ; returns Y pixel offset in d3
    add.w     d3,d2                      ; apply sag offset to screen Y position

    ; Select animation frame from sprite sheet
    ; d0 = SpriteOffset  (base for this character: Molly=0, Millie=48)
    ;     + AnimFrame offset for the current action
    add.w     Player_SpriteOffset(a4),d0

    ; Convert frame index to byte offset into PlayerHWSprites:
    ;   offset = frame_index * HW_FRAME_SIZE (208 bytes = 2 sprites of 104 bytes each)
    mulu      #HW_FRAME_SIZE,d0          ; d0 = byte offset to first sprite of this frame
    lea       PlayerHWSprites,a0         ; base of sprite data in Chip RAM
    add.l     d0,a0                      ; a0 -> SPR0 data for this frame

    ; --- SPR0 (even sprite: bitplanes 0 & 1) ---
    ; d5 = { attach_byte (hi), TILE_HEIGHT (lo) }; $80 in hi (ignored on even sprite)
    move.w    #$80,d5
    swap      d5
    move.w    #TILE_HEIGHT,d5            ; d5.hi = $0080, d5.lo = height (24)

    move.l    a0,SpritePtrs+0(a5)        ; store SPR0 pointer for copper list update
    bsr       SpriteCoord                ; write SPR0POS/SPR0CTL to sprite data header

    ; --- SPR1 (odd sprite: bitplanes 2 & 3 - attached to SPR0) ---
    add.w     #SPRITE_SIZE,a0            ; advance to SPR1 data (+104 bytes)

    move.w    #$80,d5                    ; attach bit ($80 in hi sets bit 7 in SPRxCTL)
    swap      d5
    move.w    #TILE_HEIGHT,d5

    move.l    a0,SpritePtrs+4(a5)        ; store SPR1 pointer (attached to SPR0)
    bsr       SpriteCoord                ; write SPR1 header (attach bit set!)

    ; --- Patch the copper list sprite pointer entries ---
    ; Copy SPR0-1 pointers from SpritePtrs(a5) into cpSprites so Agnus fetches
    ; the correct data.
    ; Pointer stored as: high 16 bits at +2, low 16 bits at +6 of each entry pair.
    lea       cpSprites+SPRITE_00_OFFSET,a0  ; a0 -> SPR0PTH copper entry
    lea       SpritePtrs+0(a5),a1            ; a1 -> SPR0 pointer (first of two)
    moveq     #2-1,d7                        ; loop: 2 sprites (SPR0, SPR1)

.loop
    move.l    (a1)+,d0                   ; d0 = sprite data pointer
    move.w    d0,6(a0)                   ; write low  16 bits to copper (SPRxPTL offset)
    swap      d0
    move.w    d0,2(a0)                   ; write high 16 bits to copper (SPRxPTH offset)
    add.l     #8,a0                      ; advance to next copper sprite entry (8 bytes each)
    dbra      d7,.loop

    ; --- Update player sprite priority relative to water ---
    ; If water level has reached the row that the player sprite is on:
    ; Place player sprite behind water (BPLCON2 = $0000: Playfield 1 in front of sprites).
    ; Otherwise, player is dry (BPLCON2 = $0024: sprites in front of playfield).
    move.w    WaterCurrentRow(a5),d0
    bmi.s     .sprite_dry                ; if no water (< 0), dry
    ; Calculate player's current tile row from feet position: (Y*16 + YDec + 15) >> 4
    move.w    Player_Y(a4),d1
    lsl.w     #4,d1
    add.w     Player_YDec(a4),d1
    add.w     #15,d1
    lsr.w     #4,d1                      ; d1 = current tile row of player's feet
    cmp.w     d1,d0
    bgt.s     .sprite_dry                ; water row > player row (water is below player)

    ; Water has reached the player's row: sprite behind water
    move.w    #$0000,cpBPLCON2+2
    move.w    #$0000,BPLCON2(a6)
    rts

.sprite_dry:
    move.w    #$0024,cpBPLCON2+2
    move.w    #$0024,BPLCON2(a6)
    rts


;==============================================================================
; GetBridgeYOffset
;
; Checks if the player is currently standing or walking on a bridge surface.
; If so, calculates a downward Y offset (in pixels) based on the player's
; horizontal position across the bridge to simulate the physical sag/drop.
;
; On entry:
;   d1 = player's world pixel X (Player_X * 16 + Player_XDec)
;   a4 = pointer to current player struct (Millie or Molly)
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
    move.w      ActionStatus(a5),d0     ; load current action state
    JMPINDEX    d0                      ; dispatch through jump table

.i  ; jump offset table
    dc.w        ActionIdle-.i           ; state 0: idle
    dc.w        ActionMove-.i           ; state 1: moving
    dc.w        ActionFall-.i           ; state 2: falling
    dc.w        ActionPlayerPush-.i     ; state 3: push animation
    dc.w        ActionIntro-.i          ; state 4: level intro star animation
    dc.w        ActionIntro-.i          ; state 5: player switch star animation (same body)



;==============================================================================
; ActionFall  -  Player and actor fall animation handler (ACTION_FALL state)
;
; Each frame while in the fall state:
;   1. ActionPlayerFall - advance the player's fall animation one step.
;   2. ActionFallActors - advance all falling actors one step.
;   3. Check if both are complete (d6 = 0 from ActionFallActors AND
;      Player_Fallen = 0 from ActionPlayerFall).
;      If complete: transition back to ACTION_IDLE.
;
; d6 is used as the "fall still in progress" flag: non-zero = still falling.
;==============================================================================

ActionFall:
    bsr         ActionPlayerFall        ; advance active player fall; clears Player_Fallen when done
    bsr         ActionFallActors        ; advance actor falls; d6 = actors still active

    ; Advance frozen player fall animation if mid-fall.
    add.w       Player_Fallen(a4),d6   ; include active player's fall flag
    tst.w       d6
    bne         .notyet
    move.w      #ACTION_IDLE,ActionStatus(a5)
    bsr         TakeSnapshot

.notyet
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
    moveq       #0,d0
    move.w      Actor_YDec(a3),d0
    divu        #24,d0                   ; d0.w = floor(YDec/24) = whole tiles fallen
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

    ; Landed in an acid pool?  WallpaperWork keeps TILE_ACID permanently
    ; (GameMap's acid byte is currently overwritten by the actor's own type,
    ; written there by ActorFall's map commit).
    move.w      Actor_Y(a3),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Actor_X(a3),d0
    lea         WallpaperWork(a5),a0
    cmp.b       #TILE_ACID,(a0,d0.w)
    bne         .no_acid
    bsr         ActorDissolveInAcid    ; cloud burst + status 0 + map -> BLOCK_ACID
    move.w      #1,AcidDissolved(a5)   ; post-loop: CleanActors + SortActors
    bra         .next                  ; no impact smoke for a dissolve

.no_acid
    move.w      #1,Actor_ImpactTick(a3) ; start smoke effect (falls through below)

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

    ; If any actor dissolved in acid this frame, purge it from ActorList now —
    ; a stale dead pointer would keep being animated by AnimateEnemies.
    ; CleanActors/SortActors destroy d6/d7; d6 is this routine's return value.
    tst.w       AcidDissolved(a5)
    beq         .exit
    clr.w       AcidDissolved(a5)
    PUSHM       d6
    bsr         CleanActors
    bsr         SortActors
    POPM        d6

.exit
    tst.w       d6                      ; return d6 (0 = all falls and impacts done)
    rts


;==============================================================================
; ActorDissolveInAcid  -  Destroy an actor that came to rest in an acid pool
;
; Called when a fall lands in acid (ActionFallActors) or a push delivers a
; block/cocoon into acid (ActionPlayerPush).  At entry the actor's GameMap
; cell holds the ACTOR's type (written by the normal fall/push map commit);
; the acid pool itself is identified via WallpaperWork's TILE_ACID.
;
;   1. Restore BLOCK_ACID into the GameMap cell (the pool persists).
;   2. Kill the actor and start the cloud burst ("containment burst") —
;      same registration as PlayerKillActor's cloud path.
;   3. Erase the actor's tile; the background shows the acid pool again.
;
; The CALLER must run CleanActors + SortActors afterwards (directly, or via
; the AcidDissolved flag in ActionFallActors' loop).
;
; On entry:  a3 = actor struct, a5 = Variables
; Destroys:  d0, d1, d2, a0
;==============================================================================

ActorDissolveInAcid:
    ; 1. Put the acid back into the live map
    move.w      Actor_Y(a3),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Actor_X(a3),d0
    lea         GameMap(a5),a0
    move.b      #BLOCK_ACID,(a0,d0.w)

    ; 2. Cloud burst registration (bounds-checked; max MAP_SIZE entries)
    move.w      CloudActorsCount(a5),d2
    cmp.w       #MAP_SIZE,d2
    bge         .no_cloud               ; safety: pool full
    lea         CloudActors(a5),a0
    lsl.w       #2,d2                   ; byte offset = index * 4
    move.l      a3,(a0,d2.w)
    addq.w      #1,CloudActorsCount(a5)
    move.w      #1,Actor_CloudTick(a3)  ; start cloud animation on tick 1
.no_cloud
    clr.w       Actor_Status(a3)        ; mark as dead

    ; 3. Erase the actor graphic; acid tile shows from NonDisplayScreen
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile
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
;   8. When ActionCounter reaches PUSH_STEPS (12), finalise the push:
;      clear XDec, update PrevX = X, call ActorFallAll.
;      If any actors are now falling, set ActionStatus = ACTION_FALL,
;      otherwise return to ACTION_IDLE.
;==============================================================================

PUSH_STEPS  = 12
PUSH_DELTA  = (SINE_ANGLES<<16)/2/PUSH_STEPS

ActionPlayerPush:
    move.l      PushedActor(a5),a3     ; a3 -> the block being pushed

    ; First, restore the background tile from NonDisplayScreen for the entire animation area
    move.w      Actor_PrevX(a3),d0      ; tile X coordinate
    move.w      Actor_PrevY(a3),d1      ; tile Y coordinate
    bsr         RestoreBackgroundTile        ; blit background from NonDisplayScreen to DisplayScreen

    bsr         ClearActor             ; erase block from current drawn position

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

    ; Scale: map quadratic value to 0..24 pixel range
    muls        #(TILE_WIDTH/2),d0    ; scale by 8 (half of 16-pixel tile width)
    divs        #SINE_RANGE,d0        ; normalise to -12..+12
    add.w       #(TILE_WIDTH/2),d0    ; shift to 0..16 range

    ; Apply direction sign
    move.w      Actor_DirectionX(a3),d4
    tst.w       Actor_DirectionX(a3)
    bpl         .positive
    neg.w       d0                    ; negative direction: negate offset

.positive
    move.w      d0,Actor_XDec(a3)    ; store computed sub-pixel X offset

    bsr         DrawActor             ; redraw block at new sub-pixel position

    ; Advance frame counter; check for push completion
    addq.w      #1,ActionCounter(a3)
    cmp.w       #PUSH_STEPS,ActionCounter(a3)
    bne         .exit                 ; not done yet

    ; Push animation complete
    clr.w       Actor_XDec(a3)       ; clear sub-pixel offset (snap to final position)
    move.w      Actor_X(a3),Actor_PrevX(a3)   ; update previous position record

    ; Pushed into an acid pool?  (WallpaperWork keeps TILE_ACID permanently;
    ; the GameMap cell currently holds the block's own type, written by
    ; PlayerMoveActor's map commit.)  Dissolve before the fall checks so the
    ; vacated cell cascades correctly.
    move.w      Actor_Y(a3),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Actor_X(a3),d0
    lea         WallpaperWork(a5),a0
    cmp.b       #TILE_ACID,(a0,d0.w)
    bne         .push_no_acid
    bsr         ActorDissolveInAcid    ; cloud burst + status 0 + map -> BLOCK_ACID
    bsr         CleanActors            ; purge the dead actor from ActorList
    bsr         SortActors
.push_no_acid

    ; Check if actors should now fall
    bsr         ActorFallAll           ; move any actors first; d5 = actors now falling
.fallcheck
    move.w      #ACTION_IDLE,d0
    tst.w       d5
    beq         .nofall
    move.w      #ACTION_FALL,d0

.nofall
    move.w      d0,ActionStatus(a5)
    ; If settling to IDLE (no fall), snapshot now; fall case deferred to ActionFall
    tst.w       d0
    bne         .exit
    bsr         TakeSnapshot

.exit
    rts


;==============================================================================
; ActionPlayerFall  -  Advance the active player's fall animation one frame
;
; Called from ActionFall each VBlank while Player_Fallen is set.
;
; The fall distance (in pixels) is (Player_NextY - Player_Y) * 24.
; Player_ActionFrame acts as a velocity counter: it increments by 1 each frame
; and is added to Player_YDec, giving constant acceleration (quadratic distance
; growth).  The fall ends when Player_YDec reaches the total fall distance.
;
; On completion:
;   - Player_Fallen is cleared
;   - Player_YDec is cleared (player snaps to final position)
;   - Player_Y is set to Player_NextY
;
; While falling, the walk/fall animation cycles through PLAYER_SPRITE_FALL_OFFSET
; frames at 3-frame intervals.
;==============================================================================

ActionPlayerFall:
    tst.w       Player_Fallen(a4)      ; is the player currently in a fall?
    beq         .exit

    ; Calculate total fall distance in pixels
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
    ; Animate fall sprite: cycle frames at 1/3 speed
    move.w      TickCounter(a5),d0
    divu        #3,d0                  ; one animation step every 3 frames
    swap        d0                     ; remainder -> d0 low word
    tst         d0
    bne         .noadd                 ; only advance animation on remainder == 0

    addq.w      #1,Player_AnimFrame(a4)
    and.w       #3,Player_AnimFrame(a4) ; cycle 0..3

.noadd
    move.w      Player_AnimFrame(a4),d0
    add.w       #PLAYER_SPRITE_FALL_OFFSET,d0  ; select fall animation frame
    bsr         ShowSprite

.exit
    rts


; ActionFrozenPlayerFall  ->  frozenplayer.asm


;==============================================================================
; ActionIntro  -  Star animation handler (ACTION_INTRO and ACTION_SWITCH states)
;
; Called every VBlank while ActionStatus = ACTION_INTRO or ACTION_SWITCH.
; StarAnimContext selects which completion behaviour fires when the hold expires:
;   0 (ACTION_INTRO)  - level start: show the player sprite, enter ACTION_IDLE.
;   1 (ACTION_SWITCH) - player swap: swap PlayerPtrs, clear the frozen graphic,
;                       show the new active player sprite, enter ACTION_IDLE.
;
; A large blue star steps one tile per INTRO_STEP_TICKS frames on a straight
; diagonal path from StarOriginX/Y toward StarTargetX/Y.  Each step:
;   - Stores one trail pool entry (tile X/Y) for background restoration.
;   - Blits 2-4 small white star sprites at random pixel offsets within the
;     tile area.  Offset range: ±8 pixels in both X and Y from the tile origin.
;     DrawSprite restores d0-d2 via POPM so consecutive calls reuse the same
;     pixel base; only the offsets differ.
;
; Trail particle life is INTRO_TRAIL_LIFE frames; RestoreBackgroundTile at the tile
; position restores the background when the particle expires.
;
; Registers in the step section:
;   d3 = base pixel X (StarOriginX*24), saved across DrawSprite calls
;   d4 = base pixel Y (StarOriginY*24), saved across DrawSprite calls
;   d5 = random word from RANDOMWORD
;==============================================================================

ActionIntro:
    ; --- 1. Age trail particles (runs every frame: during travel and hold) ---
    ;
    ; For each live slot: clear tile, decrement life, redraw if still alive.
    ; Small stars fade out on their natural schedule regardless of hold state.
    ; d6 = byte offset (index*2); d3 = tileX; d4 = tileY; d5 = life; d7 = counter
    ; RestoreBackgroundTile preserves d0-d2/a0-a1 via PUSHM/POPM.
    ; DrawSprite clobbers a0-a2 only (d0-d7, a3-a6 preserved via PUSHM/POPM).

    moveq       #INTRO_TRAIL_MAX-1,d7
.age_loop
    move.w      d7,d6
    lsl.w       #1,d6                   ; d6 = byte offset

    lea         IntroTrailLife(a5),a0
    lea         IntroTrailX(a5),a1
    lea         IntroTrailY(a5),a2

    move.w      (a0,d6.w),d5            ; d5 = life
    beq         .age_next               ; dead: skip

    move.w      (a1,d6.w),d3            ; d3 = tileX
    move.w      (a2,d6.w),d4            ; d4 = tileY

    subq.w      #1,d5                   ; decrement life
    move.w      d5,(a0,d6.w)
    beq         .age_expire             ; just expired: erase + restore

    ; Still alive: redraw star over current DisplayScreen — no erase needed.
    ; DrawSprite C=D=DisplayScreen preserves actor pixels via ~A&C passthrough.
    move.w      d3,d0
    mulu        #24,d0                  ; d0 = pixel X
    move.w      d4,d1
    mulu        #24,d1                  ; d1 = pixel Y
    move.w      #SPRITE_STAR_SMALL,d2
    bsr         DrawSprite              ; clobbers a0-a2; preserves d0-d7, a3-a6

    ; Cancel FlushDirtyTiles redraw: star is composited over actor using DisplayScreen as
    ; background (minterm $FCA); ActorDrawStatic sources from NonDisplayScreen and would
    ; erase the star.  Same cancellation pattern as the impact smoke path.
    move.w      d4,d2
    mulu        #WALL_PAPER_WIDTH,d2
    add.w       d3,d2                   ; flat index (d3=tileX, d4=tileY preserved by DrawSprite)
    lea         DirtyTiles(a5),a0
    clr.b       (a0,d2.w)
    bra         .age_next

.age_expire
    move.w      d3,d0
    move.w      d4,d1
    bsr         AtomicRestoreAndRedraw  ; erase star + restore background + composite actor

.age_next
    dbra        d7,.age_loop

    ; --- 2. Hold or travel? ---
    move.w      IntroDone(a5),d0
    bne         .holding

    ; --- TRAVELLING: check step time ---
    subq.w      #1,IntroTick(a5)
    bne         .no_step

    ; --- STEP ---
    move.w      #INTRO_STEP_TICKS,IntroTick(a5)

    ; a. Erase large star from current tile
    move.w      StarOriginX(a5),d0
    move.w      StarOriginY(a5),d1
    bsr         AtomicRestoreAndRedraw       ; single blit: erase + actor composite, no flicker gap

    ; b. Write one trail pool entry at current tile position
    move.w      IntroWriteIdx(a5),d3    ; d3 = slot index
    move.w      d3,d4
    lsl.w       #1,d4                   ; d4 = byte offset
    lea         IntroTrailX(a5),a0
    lea         IntroTrailY(a5),a1
    lea         IntroTrailLife(a5),a2
    move.w      StarOriginX(a5),d0
    move.w      d0,(a0,d4.w)            ; TrailX[d3] = StarX
    move.w      StarOriginY(a5),d1
    move.w      d1,(a1,d4.w)            ; TrailY[d3] = StarY
    move.w      #INTRO_TRAIL_LIFE,(a2,d4.w)
    ; Advance circular write index
    addq.w      #1,d3
    cmp.w       #INTRO_TRAIL_MAX,d3
    blt         .idx_ok
    moveq       #0,d3
.idx_ok
    move.w      d3,IntroWriteIdx(a5)

    ; c. Draw one small star at this tile's origin
    mulu        #24,d0                  ; d0 = StarX * 24  (tile pixel X)
    mulu        #24,d1                  ; d1 = StarY * 24  (tile pixel Y)
    move.w      #SPRITE_STAR_SMALL,d2
    bsr         DrawSprite

    ; Cancel the dirty flag that AtomicRestoreAndRedraw left via MarkTileDirty.
    ; Without this, FlushDirtyTiles re-runs DrawPlayerFrozen later in the same
    ; frame using C=D=DisplayScreen — which now contains the star drawn above —
    ; and its transparent-pixel passthrough locks the star ghost into the tile.
    ; The .age_loop alive path uses the same cancellation pattern.
    move.w      StarOriginY(a5),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       StarOriginX(a5),d0      ; d0 = flat tile index
    lea         DirtyTiles(a5),a0
    clr.b       (a0,d0.w)               ; suppress FlushDirtyTiles for this tile

    ; d. Move star one tile toward target
    move.w      StarOriginX(a5),d0
    move.w      StarTargetX(a5),d1
    cmp.w       d0,d1
    beq         .star_x_done
    bgt         .star_x_right
    subq.w      #1,d0
    bra         .star_x_done
.star_x_right
    addq.w      #1,d0
.star_x_done
    move.w      d0,StarOriginX(a5)

    move.w      StarOriginY(a5),d0
    move.w      StarTargetY(a5),d1
    cmp.w       d0,d1
    beq         .star_y_done
    bgt         .star_y_down
    subq.w      #1,d0
    bra         .star_y_done
.star_y_down
    addq.w      #1,d0
.star_y_done
    move.w      d0,StarOriginY(a5)

    ; Decelerate: ease-out curve based on Chebyshev distance to target.
    ; IntroTick was reset to INTRO_STEP_TICKS above; override within 5 tiles.
    ; Curve (frames/tile): full=2, d5=3, d4=5, d3=8, d2=13, d1=20 (Fibonacci ratios).
    move.w      StarTargetX(a5),d0
    sub.w       StarOriginX(a5),d0      ; d0 = TargetX - OriginX (signed)
    bge         .decel_dx_pos
    neg.w       d0                      ; abs(dx)
.decel_dx_pos
    move.w      StarTargetY(a5),d1
    sub.w       StarOriginY(a5),d1      ; d1 = TargetY - OriginY (signed)
    bge         .decel_dy_pos
    neg.w       d1                      ; abs(dy)
.decel_dy_pos
    cmp.w       d1,d0
    bge         .decel_chk              ; d0 already >= d1
    move.w      d1,d0                   ; d0 = max(|dx|,|dy|) = Chebyshev distance
.decel_chk
    cmp.w       #5,d0
    bgt         .decel_done             ; > 5 tiles: full speed
    cmp.w       #1,d0
    beq         .decel_1
    cmp.w       #2,d0
    beq         .decel_2
    cmp.w       #3,d0
    beq         .decel_3
    cmp.w       #4,d0
    beq         .decel_4
    move.w      #INTRO_TICKS_D5,IntroTick(a5)   ; 5 tiles: begin deceleration
    bra         .decel_done
.decel_4
    move.w      #INTRO_TICKS_D4,IntroTick(a5)   ; 4 tiles
    bra         .decel_done
.decel_3
    move.w      #INTRO_TICKS_D3,IntroTick(a5)   ; 3 tiles
    bra         .decel_done
.decel_2
    move.w      #INTRO_MID_TICKS,IntroTick(a5)  ; 2 tiles
    bra         .decel_done
.decel_1
    move.w      #INTRO_NEAR_TICKS,IntroTick(a5) ; 1 tile: slowest
.decel_done

    ; e. Check if arrived at current target (two-phase: overshoot then real target)
    move.w      StarOriginX(a5),d0
    cmp.w       StarTargetX(a5),d0
    bne         .draw_star
    move.w      StarOriginY(a5),d0
    cmp.w       StarTargetY(a5),d0
    bne         .draw_star

    ; Arrived: check which phase we are in
    tst.w       StarOvershot(a5)
    bne         .arrived_real           ; StarOvershot=1: at real target, start hold

    ; Phase 0 - overshoot redirect: level intro only (StarAnimContext=0)
    tst.w       StarAnimContext(a5)
    bne         .arrived_real           ; player switch: no overshoot, go straight to hold

    move.w      #1,StarOvershot(a5)
    move.w      StarOvershootX(a5),d0
    move.w      d0,StarTargetX(a5)      ; redirect to real target tile
    move.w      #INTRO_NEAR_TICKS,IntroTick(a5)  ; slow return pace
    bra         .draw_star

.arrived_real
    ; Phase 1 - second arrival (at real target = player tile): start hold countdown
    clr.w       StarOvershot(a5)
    tst.w       StarAnimContext(a5)
    bne         .switch_hold
    move.w      #INTRO_HOLD_TICKS,IntroDone(a5)
    bra         .draw_star
.switch_hold
    move.w      #SWITCH_HOLD_TICKS,IntroDone(a5)

.draw_star
    ; f. Draw large star at new/current position
    move.w      StarOriginX(a5),d0
    mulu        #TILE_WIDTH,d0
    move.w      StarOriginY(a5),d1
    mulu        #TILE_HEIGHT,d1
    move.w      StarLargeTile(a5),d2
    bsr         DrawSprite

.no_step
    rts

    ; --- HOLDING: large star stays at target; small trail stars age out normally ---
.holding
    ; Redraw large star each frame (trail aging above may have cleared its tile)
    move.w      StarOriginX(a5),d0
    mulu        #TILE_WIDTH,d0
    move.w      StarOriginY(a5),d1
    mulu        #TILE_HEIGHT,d1
    move.w      StarLargeTile(a5),d2
    bsr         DrawSprite

    subq.w      #1,IntroDone(a5)
    bne         .no_step                ; still holding: done for this frame

    ; Hold expired: erase large star and trail, then finish
    move.w      StarOriginX(a5),d0
    move.w      StarOriginY(a5),d1
    bsr         RestoreBackgroundTile        ; erase large star from DisplayScreen
    bsr         IntroClearAllTrail           ; clear any surviving trail particles
    bsr         MarkAllActorsDirty           ; trail may have erased any actor tile
    bsr         DrawStaticActors             ; restore actor tiles the trail cleared
.anim_complete
    move.l      PlayerPtrs(a5),a4
    ; Select the correct initial hardware-sprite frame for the newly-active player.
    ; Without this, d0=0 always shows the right-facing idle frame for one frame
    ; before the normal action loop corrects it.
    moveq       #0,d0
    tst.w       Player_OnLadder(a4)
    bne         .ac_ladder                  ; on ladder: use ladder idle frame
    tst.w       Player_Facing(a4)
    bpl         .ac_show                    ; positive = right: frame 0 is correct
    move.w      #PLAYER_SPRITE_LEFT_OFFSET,d0   ; facing left: use left-facing base
    bra         .ac_show
.ac_ladder
    move.w      #PLAYER_SPRITE_LADDER_IDLE,d0   ; idle-on-ladder frame
.ac_show
    bsr         ShowSprite
    move.w      #ACTION_IDLE,ActionStatus(a5)
    rts


;==============================================================================
; IntroClearAllTrail  -  RestoreBackgroundTile all active trail particles
;
; Called at intro completion to erase every still-visible trail star from
; DisplayScreen and mark each particle dead (Life = 0).
;==============================================================================

IntroClearAllTrail:
    lea         IntroTrailLife(a5),a0
    lea         IntroTrailX(a5),a1
    lea         IntroTrailY(a5),a2
    moveq       #INTRO_TRAIL_MAX-1,d7

.loop
    move.w      d7,d6
    lsl.w       #1,d6                   ; d6 = byte offset
    move.w      (a0,d6.w),d0            ; life
    beq         .next                   ; already dead
    move.w      (a1,d6.w),d0            ; tile X
    move.w      (a2,d6.w),d1            ; tile Y
    bsr         RestoreBackgroundTile        ; preserves d0-d2/a0-a1
    clr.w       (a0,d6.w)               ; mark dead

.next
    dbra        d7,.loop
    rts


;==============================================================================
; StarAnimBegin  -  Common initialisation for the star animation
;
; Called after the caller has set StarOriginX/Y, StarTargetX/Y, and
; StarAnimContext.  Resets IntroTick, IntroDone, IntroWriteIdx, clears the
; trail pool, and blits the large star at the origin position.
;
; Clobbers: none (PUSHALL/POPALL).
;==============================================================================

StarAnimBegin:
    PUSHALL
    move.w      #INTRO_STEP_TICKS,IntroTick(a5)
    clr.w       StarOvershot(a5)
    clr.w       IntroDone(a5)
    clr.w       IntroWriteIdx(a5)
    lea         IntroTrailLife(a5),a0
    moveq       #INTRO_TRAIL_MAX-1,d7
.clear_trail
    clr.w       (a0)+
    dbra        d7,.clear_trail
    move.w      StarOriginX(a5),d0
    mulu        #TILE_WIDTH,d0
    move.w      StarOriginY(a5),d1
    mulu        #TILE_HEIGHT,d1
    move.w      StarLargeTile(a5),d2
    bsr         DrawSprite
    POPALL
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


; SetupFrozenPlayerActor  ->  frozenplayer.asm


;==============================================================================
; ClearDirtyTiles  -  Zero all dirty flags (called at level start from DrawMap)
;==============================================================================

ClearDirtyTiles:
    PUSHM       d7/a0
    clr.w       DirtyTileCount(a5)         ; reset compact list count
    lea         DirtyTiles(a5),a0
    move.w      #MAX_GAME_MAP_SIZE-1,d7
.cdt_loop
    clr.b       (a0)+
    dbra        d7,.cdt_loop
    POPM        d7/a0
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
; AtomicRestoreAndRedraw  -  Single-blit erase + actor composite (no flicker)
;
; Drop-in replacement for:  bsr RestoreBackgroundTile / bsr RedrawActorAtTile
;
; For a live, non-falling, non-player actor at (d0,d1): one combined blit
;   A=TileMask, B=TileSet, C=NonDisplayScreen, D=DisplayScreen, minterm $FCA
;   D = (A&B) | (~A&C) — atomically restores background AND composites actor.
;   Zero blank window: no intermediate erased state, so actor never disappears.
;   Called only on particle expiry/step; living trail particles skip this and
;   call DrawSprite directly (actor pixels preserved by C=D=DisplayScreen passthrough).
;
; For a player actor, or when no actor is present, falls back to the original
; RestoreBackgroundTile + RedrawActorAtTile sequence.
;
; In all paths calls MarkTileDirty so FlushDirtyTiles re-composites as needed.
;
; Entry: d0 = tile X, d1 = tile Y
; Preserves: all registers.
;==============================================================================

AtomicRestoreAndRedraw:
    PUSHM       d0-d7/a0-a4

    ; Search ActorList for a live, non-falling actor at (d0,d1).
    ; Regular actors  → .aar_found  (single blit, C=NonDisplayScreen)
    ; Frozen player   → .frozen_aar (single blit, C=NonDisplayScreen, ActorSprites source)
    ; No actor found  → .fallback   (RestoreBackgroundTile only)
    move.w      ActorCount(a5),d7
    beq         .fallback
    subq.w      #1,d7
    lea         ActorList(a5),a2

.aar_scan
    move.l      (a2)+,a3
    tst.w       Actor_Status(a3)
    beq         .aar_next
    tst.w       Actor_HasFalled(a3)
    cmp.w       Actor_X(a3),d0
    bne         .aar_next
    cmp.w       Actor_Y(a3),d1
    bne         .aar_next
    bra         .aar_found

.aar_next
    dbra        d7,.aar_scan

.fallback
    ; No actor at this tile: restore background only.
    ; RestoreBackgroundTile calls MarkTileDirty internally.
    POPM        d0-d7/a0-a4
    bsr         RestoreBackgroundTile
    rts

.aar_found
    ; Single combined blit: A=TileMask, B=TileSet, C=NonDisplayScreen, D=DisplayScreen.
    ; Minterm $FCA: D=(A&B)|(~A&C) — composites actor tile over clean background atomically.
    ; Zero blank window: one blit, no intermediate erased state visible to the raster.
    ; BLTAFWM/BLTALWM use boundary-safe masks (same as RestoreBackgroundTile) so that
    ; bit positions where TileMask=0 (past the tile's 24px edge) are NOT written — this
    ; prevents overwriting the 8 pixels that belong to the frozen player's adjacent tile.

    ; --- Pixel coords: tileX*16, tileY*24 ---
    lsl.w       #4,d0                   ; d0 = pixel X (tileX * 16)
    move.w      d1,d2
    lsl.w       #4,d1
    lsl.w       #3,d2
    add.w       d2,d1                   ; d1 = pixel Y (tileY * 24)

    ; --- Screen byte offset ---
    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2
    add.w       d2,d1                   ; d1 = screen byte offset

    ; --- Shift → BLTCON0/BLTCON1 ---
    and.w       #$f,d0                  ; d0 = X mod 16 (0 or 8)
    ror.w       #4,d0                   ; shift into bits 15:12
    move.w      d0,d2                   ; d2 = BLTCON1
    or.w        #$0fca,d0              ; d0 = BLTCON0 (USEA/B/C/D=1, minterm $FCA)

    ; --- Tile pointers ---
    moveq       #0,d3
    move.w      Actor_SpriteOffset(a3),d3
    mulu        #TILE_SIZE,d3           ; d3 = tile byte offset
    lea         TileMask,a1
    add.l       d3,a1                   ; a1 = TileMask + tile_offset (A)
    move.l      TilesetPtr(a5),a2
    add.l       d3,a2                   ; a2 = TileSet + tile_offset  (B)

    ; --- Screen pointers ---
    lea         NonDisplayScreen,a3
    add.l       d1,a3                   ; a3 = NonDisplayScreen + offset (C)
    lea         DisplayScreen,a4
    add.l       d1,a4                   ; a4 = DisplayScreen + offset   (D)

    WAITBLIT
    move.w      d0,BLTCON0(a6)
    move.w      d2,BLTCON1(a6)
    ; Tile-boundary safe: always protect pixels outside the 24-pixel tile boundary.
    ; Since tiles are always called with tile coordinates (0..13), the pixel position
    ; depends on tile column: even columns (0,2,4...) have shift=0, odd columns (1,3,5...)
    ; have shift=8. But we want to protect overflow pixels consistently:
    ; pixels 0-23 of the tile should be written, pixels 24+ and before 0 should not.
    ; For a tile at any position, this means protecting word boundaries, not shift-based.
    ; Always use $ffffff00 to protect the right overflow (bits 7-0 of last word).
    move.l      #$ffffff00,BLTAFWM(a6)
    move.l      a1,BLTAPT(a6)
    move.l      a2,BLTBPT(a6)
    move.l      a3,BLTCPT(a6)
    move.l      a4,BLTDPT(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #0,BLTBMOD(a6)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)

    POPM        d0-d7/a0-a4
    bsr         MarkTileDirty
    rts


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
; ActionDirtActors  -  Animate all active dirt block break animations
;
; Called every frame from GameRun, independent of the main action state.
; Iterates DirtActors[0..DirtActorsCount-1]; actors with DirtTick=0 are
; skipped (already done).
;
; For each actor with Actor_DirtTick > 0:
;   1. Compute frame index = (Actor_DirtTick - 1) / DIRT_FRAME_TICKS
;   2. If frame >= DIRT_FRAMES: RestoreBackgroundTile, clear Actor_DirtTick.
;   3. Otherwise: RestoreBackgroundTile, DrawSprite(dirt frame), increment tick.
;
; Registers: a2=DirtActors pointer, a3=actor struct, d7=loop counter
;==============================================================================

ActionDirtActors:
    move.w      DirtActorsCount(a5),d7
    subq.w      #1,d7
    bmi         .exit                   ; no dirt actors registered

    lea         DirtActors(a5),a2       ; a2 -> dirt actor pointer array

.loop
    move.l      (a2)+,a3                ; a3 -> actor struct

    tst.w       Actor_DirtTick(a3)      ; animation active?
    beq         .next                   ; tick=0: already done, skip

    ; Compute frame index: (tick - 1) >> LOG2_DIRT_FRAME_TICKS
    moveq       #0,d0
    move.w      Actor_DirtTick(a3),d0
    subq.w      #1,d0                   ; 0-based tick (0..DIRT_TOTAL_TICKS-1)
    lsr.w       #LOG2_DIRT_FRAME_TICKS,d0  ; d0.w = frame index (0..DIRT_FRAMES-1+)

    cmp.w       #DIRT_FRAMES,d0
    bcc         .dirt_done              ; frame >= DIRT_FRAMES: all frames shown

    ; Save frame index before RestoreBackgroundTile clobbers d0
    move.w      d0,d3                   ; d3 = frame index

    ; --- Erase previous dirt frame ---
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile

    ; Build sprite index from saved frame (d3 free again after d2 set)
    move.w      d3,d2
    add.w       #SPRITE_DIRT_A,d2       ; absolute sprite sheet index

    ; Pixel X = Actor_X * 16, Pixel Y = Actor_Y * 24
    move.w      Actor_X(a3),d0
    lsl.w       #4,d0

    move.w      Actor_Y(a3),d1
    move.w      d1,d3
    lsl.w       #4,d1
    lsl.w       #3,d3
    add.w       d3,d1
    bsr         DrawSprite

    addq.w      #1,Actor_DirtTick(a3)
    bra         .next

.dirt_done
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile   ; erase final dirt frame; auto-dirty schedules actor redraw
    clr.w       Actor_DirtTick(a3)

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
;      - Call ActorFallAll to check if any actors should now fall
;      - If actors fell, set ActionStatus to ACTION_FALL
;==============================================================================

ActionMove:
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

    bsr         ActorFallAll           ; move any actors whose support was removed; d5 = count
.fallcheck
    tst.w       d5
    beq         .nofall

    move.w      #ACTION_FALL,ActionStatus(a5)

.nofall
    ; If ActionStatus is still IDLE (no player fall, no actor fall), the game has
    ; settled - snapshot now.  If ACTION_FALL is pending, defer to ActionFall.
    tst.w       ActionStatus(a5)
    bne         .exit
    bsr         TakeSnapshot

.exit
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
    ; F9 undo: check if key is held and cooldown has expired
    lea         Keys,a0
    tst.b       KEY_F9(a0)              ; F9 held down?
    beq.s       .nof9                   ; no: check other inputs
    clr.b       KEY_F9(a0)              ; clear key latch immediately
    cmp.w       #2,SnapshotCount(a5)    ; at least one move in the undo stack?
    blt         .f9_done                ; nothing to undo: clear key, skip both
    bsr         UndoMove
    bsr         VHS_StartEffect
.f9_done
    rts
.nof9
    clr.w       PlayerMoved(a5)        ; clear "did player move this frame" flag
    bsr         ActorsSavePos          ; save all actor positions for delta detection

    bsr         PlayerCheckControls    ; process directional input; may set ActionStatus
.exit
    rts


;==============================================================================
; PlayerSwitch  -  Disabled (single player mode)
;==============================================================================

PlayerSwitch:
    rts


; DrawPlayerFrozen  ->  frozenplayer.asm


;==============================================================================
; CheckLevelDone  -  Scan GameMap for remaining enemies
;
; Walks the entire GameMap (WALL_PAPER_SIZE cells) looking for any cell that
; contains BLOCK_ENEMYFALL, BLOCK_ENEMYFLOAT or BLOCK_COCOON.  If found,
; sets d3 = 1.  If none are found, d3 = 0 (level complete).
;
; Cocoons count as uncontained organisms: the sector cannot be sealed while
; one is waiting to hatch — contain the hatchling or dissolve it in acid.
;
; Out:  d3 = 0 if no enemies remain (level done), 1 if enemies still present
;==============================================================================

CheckLevelDone:
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
    cmp.b       #BLOCK_COCOON,d0
    beq.s       .notdone               ; unhatched cocoon -> not done
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
    ; If the next cell is a plain BLOCK_LADDER, use the ladder variant ID instead.
    move.b      Player_BlockId(a4),d4
    cmp.b       #BLOCK_LADDER,d3
    bne         .notladdernext
    move.b      Player_LadderId(a4),d4  ; use ladder-specific ID (MILLIELADDER/MOLLYLADDER)

.notladdernext
    move.b      d4,(a0,d1.w)           ; write player presence into next cell

    ; Clear the current cell.
    ; If it was a ladder ID, restore it to plain BLOCK_LADDER.
    move.b      #BLOCK_EMPTY,d4
    cmp.b       Player_LadderId(a4),d2
    bne         .notladderlast
    move.b      #BLOCK_LADDER,d4       ; restore the ladder

.notladderlast
    move.b      d4,(a0,d0.w)           ; write to old cell

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


; PlayerFallLogicFrozen  ->  frozenplayer.asm


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

    ; Is the player currently on a ladder (their cell = LadderId)?  If so, no fall.
    move.b      Player_LadderId(a4),d2
    cmp.b       (a0,d1.w),d2
    beq         .exit

    ; Scan downward for the floor
    moveq       #0,d3                 ; fall distance in tiles
    move.w      Player_Y(a4),d4       ; d4 = current row

.findfloor
    addq.w      #1,d4                 ; row below
    cmp.w       CurrentMapHeight(a5),d4
    bge         .found                ; reached bottom of map
    tst.b       WALL_PAPER_WIDTH(a0,d1.w)  ; cell below non-empty?
    bne         .found
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

    ; Update GameMap: clear current cell, mark landing cell
    clr.b       (a0,d0.w)
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
; PlayerPtrs[0] is the active player (status=1).
; PlayerPtrs[1] is the frozen player (status=2) or inactive (status=0).
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
    bsr         PlayerShowIdleAnim    ; update idle animation frame

    move.b      ControlsHold(a5),d0  ; d0 = newly-pressed keys this frame

    ; Clear both directions so left/right branches don't inherit a stale DirectionY
    ; from the previous frame (e.g. a ladder climb that has since ended).
    clr.w       Player_DirectionX(a4)
    clr.w       Player_DirectionY(a4)

    ; Check each direction; set DirectionX/Y and branch to .move if pressed
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
    cmp.b       Player_LadderId(a4),d1
    beq         .move                      ; on ladder -> allow upward movement

.nomove
    clr.w       Player_DirectionY(a4)      ; cancel direction
    rts

.move
    ; A direction was chosen: update facing only on horizontal moves (preserve facing across ladder climbs)
    tst.w       Player_DirectionX(a4)
    beq.s       .face_done
    move.w      Player_DirectionX(a4),Player_Facing(a4)
.face_done
    bsr         PlayerTryMove              ; try to move in the chosen direction

.exit
    rts


;==============================================================================
; PlayerShowIdleAnim  -  Animate the player sprite while standing still
;
; Called from PlayerIdle once per frame.  Advances the animation frame every
; 5 VBlanks (TickCounter mod 5 = 0) for a slower idle cycle.
;
; Selects the appropriate animation frame based on:
;   - If on a ladder: PLAYER_SPRITE_LADDER_IDLE (single frame, no cycling)
;   - If off ladder, facing right: walk cycle frame + PLAYER_SPRITE_WALK_OFFSET
;   - If off ladder, facing left: walk cycle frame + PLAYER_SPRITE_LEFT_OFFSET
;
; Also updates Player_OnLadder based on the player's current map cell.
;==============================================================================

PlayerShowIdleAnim:
    ; Only advance animation every 5 frames
    move.w      TickCounter(a5),d0
    divu        #5,d0
    swap        d0                    ; remainder -> d0 low word
    tst.w       d0
    beq         .anim                 ; remainder = 0 -> advance
    rts                               ; skip this frame

.anim
    ; Check if on a ladder
    move.w      Player_Y(a4),d1
    mulu        #WALL_PAPER_WIDTH,d1
    add.w       Player_X(a4),d1       ; map offset

    moveq       #PLAYER_SPRITE_LADDER_IDLE,d0   ; default: ladder idle frame

    moveq       #0,d2
    lea         GameMap(a5),a0
    move.b      (a0,d1.w),d1          ; d1 = cell type at current position
    cmp.b       Player_LadderId(a4),d1
    bne         .noladder1
    moveq       #1,d2                 ; d2 = 1 means on ladder

.noladder1
    move.w      d2,Player_OnLadder(a4)  ; update on-ladder status

    bne         .isright              ; on ladder: use PLAYER_SPRITE_LADDER_IDLE

    ; Not on ladder: cycle walk animation frames 0..3
    move.w      Player_AnimFrame(a4),d0
    addq.w      #1,d0
    and.w       #3,d0
    move.w      d0,Player_AnimFrame(a4)

    ; Check if we came off a ladder (Player_OnLadder was just set to 0)
    tst.w       Player_OnLadder(a4)
    beq         .noladder

    ; Was on ladder: use ladder frame offset
    add.w       #PLAYER_SPRITE_LADDER_OFFSET,d0
    bra         .isright

.noladder
    ; Off ladder: apply left/right facing offset
    tst.w       Player_Facing(a4)
    bpl         .isright              ; positive facing = right: frames 0..3 (idle-right)
    add.w       #PLAYER_SPRITE_LEFT_OFFSET,d0  ; left-facing: frames 32..35

.isright
    bsr         ShowSprite            ; display the selected animation frame
    rts


;==============================================================================
; PlayerShowWalkAnim  -  Animate the player sprite while moving
;
; Called from ActionMove every frame.  Advances the animation cycle every
; other frame (TickCounter AND 1) for walk animation.
;
; Walk animation uses 8 frames (0..7) for off-ladder, 4 frames (0..3) for
; on-ladder climbing.
;
; Frame selection:
;   On ladder:   AnimFrame (0..3) + PLAYER_SPRITE_LADDER_OFFSET
;   Off ladder, right: AnimFrame (0..7) + PLAYER_SPRITE_WALK_OFFSET
;   Off ladder, left:  (AnimFrame + PLAYER_SPRITE_LEFT_OFFSET) + PLAYER_SPRITE_WALK_OFFSET
;==============================================================================

PlayerShowWalkAnim:
    ; if Player_DirectionY is non-zero, we are definitely on a ladder (vertical movement only)
    tst.w       Player_DirectionY(a4)
    bne         .ontladder

    ; Update Player_OnLadder based on current cell type, since we can only be on a ladder if moving vertically onto it.
      move.w      Player_Y(a4),d1
      mulu        #WALL_PAPER_WIDTH,d1
      add.w       Player_X(a4),d1        ; d1 = current cell offset
      lea         GameMap(a5),a0
      move.b      (a0,d1.w),d2           ; d2 = current cell type
      moveq       #0,d3                  ; d3 = on ladder flag (default: walking)

      cmp.b       Player_LadderId(a4),d2 ; on a ladder cell?
      bne         .notlad

      ; On a ladder cell - check if we've reached the bottom and are stepping off
      move.b      WALL_PAPER_WIDTH(a0,d1.w),d4  ; d4 = cell type directly below
      cmp.b       #BLOCK_LADDER,d4 ; is cell below also a ladder?
      beq         .ontladder             ; yes - still climbing

      ; Switch to walking if we're moving horizontally away from the ladder (DirectionX non-zero).
      ; *and* there's no ladder left/right that we could climb onto

      tst.w       Player_DirectionX(a4)     ; moving left or right?
      beq         .ontladder                ; no - not moving horizontally, so still on the ladder

      ; check tile to the left/right of the Player
        add.w       Player_DirectionX(a4),d1        ; d1 = current cell offset
        move.b      (a0,d1.w),d2  ; d2 = cell type to the right
        cmp.b       #BLOCK_LADDER,d2
        bne         .notlad          

.ontladder
      moveq       #1,d3                  ; use climbing sprite

.notlad
      move.w      d3,Player_OnLadder(a4)

      ; Only advance animation every other frame
      move.w      TickCounter(a5),d0
      and.w       #1,d0
      bne         .show                 ; odd frame: show but don't advance

      ; Advance walk animation (even frames only)
      move.w      Player_AnimFrame(a4),d0
      addq.w      #1,d0

      ; Cycle limit depends on whether on ladder (0-3) or walking (0-7)
      tst.w       Player_OnLadder(a4)
      beq         .walkframes
      and.w       #3,d0                 ; ladder: cycle 0..3
      bra         .saveframe

.walkframes
      and.w       #7,d0                 ; walk: cycle 0..7
.saveframe
      move.w      d0,Player_AnimFrame(a4)

.show
      move.w      Player_AnimFrame(a4),d0

      ; Determine if on ladder or walking
      tst.w       Player_OnLadder(a4)
      beq         .walking

      ; On ladder: use ladder offset (doesn't change based on facing)
      add.w       #PLAYER_SPRITE_LADDER_OFFSET,d0
      bsr         ShowSprite
      rts

.walking
      ; Off ladder: use walk offset + facing adjustment
      move.w      #PLAYER_SPRITE_WALK_OFFSET,d1

      tst.w       Player_Facing(a4)
      bpl         .rightface
      add.w       #PLAYER_SPRITE_LEFT_OFFSET,d0  ; left-facing: offset the frame index

.rightface
      add.w       d1,d0                 ; add walk offset
      bsr         ShowSprite
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
;   BLOCK_EMPTY       -> PlayerDoMove   (walk into empty space)
;   BLOCK_LADDER      -> PlayerDoMove   (walk onto/off ladder)
;   BLOCK_ENEMYFALL   -> PlayerKillEnemy (kill the enemy)
;   BLOCK_PUSH        -> PlayerPushBlock (check if the block can be pushed)
;   BLOCK_DIRT        -> PlayerKillDirt  (walk through dirt, destroying it)
;   BLOCK_SOLID       -> PlayerNotMove   (blocked by wall)
;   BLOCK_ENEMYFLOAT  -> PlayerKillEnemy (kill the floating enemy)
;   BLOCK_MILLIESTART -> PlayerNotMove   (can't walk into the other player's cell)
;   BLOCK_MOLLYSTART  -> PlayerNotMove
;   BLOCK_MILLIELADDER-> PlayerMoveLadder (move along while on ladder)
;   BLOCK_MOLLYLADDER -> PlayerMoveLadder
;   BLOCK_COCOON      -> PlayerPushBlock (cocoons push like crates)
;   BLOCK_ACID        -> PlayerNotMove   (impassable to players)
;==============================================================================

PlayerTryMove:
    move.w      Player_DirectionX(a4),d1
    bsr         PlayerGetNextBlock    ; d2 = block type of next cell, a0 = GameMap, d0 = offset

    JMPINDEX    d2                    ; jump based on next cell's block type

.i
    dc.w        PlayerDoMove-.i       ; BLOCK_EMPTY       = 0
    dc.w        PlayerDoMove-.i       ; BLOCK_LADDER      = 1
    dc.w        PlayerKillEnemy-.i    ; BLOCK_ENEMYFALL   = 2
    dc.w        PlayerPushBlock-.i    ; BLOCK_PUSH        = 3
    dc.w        PlayerKillDirt-.i     ; BLOCK_DIRT        = 4
    dc.w        PlayerNotMove-.i      ; BLOCK_SOLID       = 5
    dc.w        PlayerKillEnemy-.i    ; BLOCK_ENEMYFLOAT  = 6
    dc.w        PlayerNotMove-.i      ; BLOCK_MILLIESTART = 7
    dc.w        PlayerNotMove-.i      ; BLOCK_MOLLYSTART  = 8
    dc.w        PlayerMoveLadder-.i   ; BLOCK_MILLIELADDER= 9
    dc.w        PlayerMoveLadder-.i   ; BLOCK_MOLLYLADDER = 10
    dc.w        PlayerPushBlock-.i    ; BLOCK_COCOON      = 11
    dc.w        PlayerNotMove-.i      ; BLOCK_ACID        = 12
    rts


;==============================================================================
; PlayerPushBlock  -  Attempt to push a block (or cocoon)
;
; Only allowed for horizontal movement (DirectionX = +/-1, DirectionY = 0).
; Checks the cell BEYOND the push block (two cells ahead): empty allows a
; normal push; an acid pool also allows the push — the block slides INTO the
; pool and dissolves when the push animation completes (ActionPlayerPush).
; Anything else blocks the push silently.
;
; On entry:
;   a0 = GameMap base pointer (from PlayerGetNextBlock)
;   d0 = map offset of the PUSH block's cell
;==============================================================================

PlayerPushBlock:
    ; Check if cell BEYOND the push block is within the same row (0 <= X + 2*DirX < WALL_PAPER_WIDTH)
    move.w      Player_X(a4),d1
    add.w       Player_DirectionX(a4),d1  ; push block column
    add.w       Player_DirectionX(a4),d1  ; beyond push block column
    bmi.s       .push_blocked
    cmp.w       #WALL_PAPER_WIDTH,d1
    bge.s       .push_blocked

    add.w       Player_DirectionX(a4),d0  ; advance to cell BEYOND the push block
    move.b      (a0,d0.w),d2              ; d2 = block type beyond
    beq         PlayerMoveActor           ; empty -> initiate push
    cmp.b       #BLOCK_ACID,d2
    beq         PlayerMoveActor           ; acid -> push it into the pool
.push_blocked:
    rts                                   ; anything else -> blocked


;==============================================================================
; PlayerNotMove  -  Blocked move (wall or other player's cell)
; Does nothing; the player simply cannot enter that cell.
;==============================================================================

PlayerNotMove:
    rts


;==============================================================================
; PlayerMoveLadder  -  Move into a cell containing the other player's ladder marker
;
; If the next cell is BLOCK_MILLIELADDER or BLOCK_MOLLYLADDER (the other player
; is on this ladder cell), the current player can still "share" the cell by
; executing a standard move.  This is a design decision: players can be on the
; same ladder segment simultaneously.
;==============================================================================

PlayerMoveLadder:
    tst.w       Player_DirectionY(a4)   ; moving vertically into frozen player's ladder cell?
    bne         PlayerNotMove           ; yes - blocked
    bsr         PlayerDoMove
    rts


;==============================================================================
; PlayerKillDirt  -  Walk into and destroy a dirt block
;
; Dirt can only be destroyed by horizontal movement (not by descending into it).
; If DirectionY is non-zero (moving vertically), the kill is blocked.
; Otherwise: move normally AND kill the actor occupying that cell.
;==============================================================================

PlayerKillDirt:
    tst.w       Player_DirectionY(a4)  ; vertical movement?
    bne         .nokill                ; yes - can't destroy dirt by moving down into it
    bsr         PlayerDoMove           ; standard move into the cell
    bsr         PlayerKillActor        ; remove the dirt actor and clear its screen tile
    bsr         CleanActors            ; compact actor list (remove dead slots)
    bsr         SortActors             ; re-sort by Y for correct rendering order
.nokill
    rts


;==============================================================================
; PlayerKillEnemy  -  Walk into and destroy an enemy
;
; Enemies can only be killed by horizontal movement (same rule as dirt).
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
    clr.b       (a0,d0.w)             ; clear old cell

    ; Update cached pixel X for the new tile position (d0/d2 now free)
    move.w      Actor_X(a3),d0
    move.w      d0,d2
    lsl.w       #4,d0
    lsl.w       #3,d2
    add.w       d2,d0
    move.w      d0,Actor_PixelX(a3)

    ; Initialise push animation
    clr.l       Actor_Delta(a3)       ; reset easing accumulator
    move.w      #ACTION_PLAYERPUSH,ActionStatus(a5)  ; enter push state
    move.l      a3,PushedActor(a5)   ; remember which actor is being pushed

    clr.w       Actor_XDec(a3)
    clr.w       Actor_YDec(a3)
    move.w      Player_DirectionX(a4),Actor_DirectionX(a3)  ; set push direction
    clr.w       Actor_DirectionY(a3)
    clr.w       ActionCounter(a3)    ; reset push frame counter

    bra         .exit                 ; found the block - done

.next
    add.w       #Actor_Sizeof,a3      ; advance to next actor
    dbra        d7,.loop

.exit
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
    moveq       #0,d5                 ; d5 = total actors now falling

    move.w      ActorCount(a5),d7
    bne         .go
    rts

.go
    lea         ActorList(a5),a0       ; a0 -> sorted actor pointer array
    lea         FallenActors(a5),a2    ; a2 -> fallen actor pointer array (write cursor)
    subq.w      #1,d7

.loop
    move.l      (a0)+,a3              ; a3 -> next actor
    tst.w       Actor_Status(a3)      ; alive?
    beq         .nofall
    tst.w       Actor_CanFall(a3)     ; subject to gravity?
    beq         .nofall

    PUSH        a0                    ; preserve list read pointer (ActorFall uses a0)
    bsr         ActorFall             ; check/initiate fall; d3 = 0 if no fall, non-zero if falling
    POP         a0

    tst.w       d3
    beq         .nofall               ; actor did not fall

    add.w       #1,d5                 ; increment falling count
    move.l      a3,(a2)+              ; add actor to FallenActors list

.nofall
    dbra        d7,.loop

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
    move.w      Actor_X(a3),d0
    lsl.w       #4,d0                      ; d0 = pixel X
    move.w      Actor_Y(a3),d1
    sub.w       TilemapScreenOffset(a5),d1 ; relative row in visible viewport
    bmi.s       .offscreen                 ; above top of viewport -> skip
    cmp.w       #TILEMAP_VIEW_ROWS,d1
    bge.s       .offscreen                 ; below bottom of viewport -> skip
    lsl.w       #4,d1                      ; pixel Y = rel_row * 16
    moveq       #0,d2
    move.w      Actor_SpriteOffset(a3),d2
    lea         DisplayScreen,a1
    bsr         PasteTile
.offscreen
    clr.w       Actor_Dirty(a3)            ; tile is now correctly displayed (or off-screen)
    rts


;==============================================================================
; ActorFall  -  Check if an actor should fall and set it up if so
;
; Scans the cells below the actor's current position in GameMap until a
; non-empty cell is found.  The count of empty cells is the fall distance.
;
; If the actor is directly supported (cell below non-empty), no fall occurs
; and d3 = 0 on return.
;
; If the actor should fall:
;   - Actor_Y is advanced by the fall tile count
;   - Actor_FallY is set to (fall_tiles * 24) pixels (target for YDec)
;   - Actor_HasFalled = 1
;   - GameMap is updated: old cell cleared, new cell gets the actor type
;   - d3 = non-zero
;
; An acid pool below does not support an actor: the fall extends one final
; row INTO the pool cell (the actor dissolves when the fall animation lands —
; see the acid check in ActionFallActors).
;
; On entry:  a3 = actor struct pointer
; Destroys:  a0, d0, d1, d2, d3
;==============================================================================

ActorFall:
    lea         GameMap(a5),a0

    ; Calculate map offset for actor's current position
    move.w      Actor_Y(a3),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Actor_X(a3),d0
    move.w      d0,d1                 ; d1 = current map offset

    moveq       #0,d3                 ; fall distance (tiles)

.findfloor
    move.b      WALL_PAPER_WIDTH(a0,d1.w),d2  ; d2 = cell below
    beq         .fallrow              ; empty: keep scanning down
    cmp.b       #BLOCK_ACID,d2
    bne         .found                ; real support: rest on top of it
    addq.w      #1,d3                 ; acid below: fall one final row INTO
    add.w       #WALL_PAPER_WIDTH,d1  ; the pool (dissolves on landing)
    bra         .found

.fallrow
    addq.w      #1,d3                 ; fall one more row
    add.w       #WALL_PAPER_WIDTH,d1  ; advance map offset one row
    bra         .findfloor

.found
    tst.w       d3
    beq         .exit                 ; no fall (floor is directly below)

    ; Commit the fall
    add.w       d3,Actor_Y(a3)        ; advance actor Y by fall distance
    mulu        #TILE_HEIGHT,d3       ; convert tiles to pixels (for YDec animation target)
    move.w      d3,Actor_FallY(a3)   ; set pixel target for fall animation
    move.w      #1,Actor_HasFalled(a3)    ; mark as falling
    move.b      (a0,d0.w),(a0,d1.w)  ; copy actor type from old to new map cell
    clr.b       (a0,d0.w)            ; clear old map cell

    ; Update cached pixel Y for the new tile position (d0/d1 now free)
    move.w      Actor_Y(a3),d0
    move.w      d0,d1
    lsl.w       #4,d0
    lsl.w       #3,d1
    add.w       d1,d0
    move.w      d0,Actor_PixelY(a3)

.exit
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
    cmp.w       #BLOCK_DIRT,d2
    beq         .setup_dirt
    cmp.w       #BLOCK_ENEMYFALL,d2
    beq         .setup_cloud
    cmp.w       #BLOCK_ENEMYFLOAT,d2
    bne         .skip_effects

.setup_dirt
    ; Add to DirtActors list (bounds-checked; max MAP_SIZE entries)
    move.w      DirtActorsCount(a5),d2
    cmp.w       #MAP_SIZE,d2
    bge         .skip_effects           ; safety: pool full
    lea         DirtActors(a5),a0
    lsl.w       #2,d2                   ; byte offset = index * 4
    move.l      a3,(a0,d2.w)            ; DirtActors[count] = a3
    addq.w      #1,DirtActorsCount(a5)
    move.w      #1,Actor_DirtTick(a3)   ; start dirt animation on tick 1
    bra         .skip_effects

.setup_cloud
    ; Add to CloudActors list (bounds-checked; max MAP_SIZE entries)
    move.w      CloudActorsCount(a5),d2
    cmp.w       #MAP_SIZE,d2
    bge         .skip_effects           ; safety: pool full
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
    clr.b       (a0,d0.w)

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
; ClearPlayer  -  Erase the active player from DisplayScreen
;
; Restores the 24x24 pixel area at the player's current tile position from
; NonDisplayScreen into DisplayScreen.  Used when switching from active to frozen.
;
; The blit uses minterm $7ca combined with a constant mask to select which
; words to write.  The mask depends on whether the player's X is on the left
; or right word boundary:
;   X AND $f = 0 (left-aligned): mask = $ffffff00 (write first 3 bytes of each word)
;   X AND $f != 0 (shifted):     mask = $00ffffff (write last 3 bytes)
;
; The blitter writes a constant $ffff (all ones) from BLTADAT, gated by the
; mask in BLTAFWM, combined with the source from NonDisplayScreen (B) and
; current DisplayScreen (C).
; Minterm $7ca = (~A&B&C) | (A&B) | (~A&~B&C) simplifies to: where mask=1 use B, else C.
; Effectively: copy NonDisplayScreen (B) to DisplayScreen (D) in the masked region.
;==============================================================================

ClearPlayer:
    PUSHALL
    lea         NonDisplayScreen,a0          ; source: clean background
    lea         DisplayScreen,a1        ; destination: current display buffer

    ; Calculate player pixel position
    move.w      Player_X(a4),d0
    move.w      Player_Y(a4),d1
    mulu        #24,d0
    mulu        #24,d1

    ; Calculate byte offset in screen buffers
    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2                  ; byte column
    add.w       d2,d1
    add.l       d1,a0                  ; a0 -> source position
    add.l       d1,a1                  ; a1 -> destination position

    ; Choose mask based on X alignment
    move.l      #$ffffff00,d1          ; default: left-aligned mask
    and.w       #$f,d0                 ; X mod 16
    beq         .left
    move.l      #$00ffffff,d1          ; shifted: right-aligned mask

.left
    WAITBLIT
    move.l      #$7ca<<16,BLTCON0(a6)  ; BLTCON0: minterm $7ca, no shift
    move.l      d1,BLTAFWM(a6)         ; first+last word mask
    move.w      #-1,BLTADAT(a6)        ; A data register = $ffff (constant ones)
    move.l      a0,BLTBPT(a6)          ; B = NonDisplayScreen (clean background)
    move.l      a1,BLTCPT(a6)          ; C = DisplayScreen (current display)
    move.l      a1,BLTDPT(a6)          ; D = DisplayScreen (output)
    move.w      #0,BLTAMOD(a6)         ; A is constant (no DMA, just BLTADAT)
    move.w      #TILE_BLT_MOD,BLTBMOD(a6)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)
    POPALL
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
    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1

    sub.w       TilemapScreenOffset(a5),d1 ; relative row in visible viewport
    bmi         .rbt_skip
    cmp.w       #TILEMAP_VIEW_ROWS,d1
    bge         .rbt_skip

    lsl.w       #4,d0                  ; pixel X = d0 * 16
    lsl.w       #4,d1                  ; pixel Y = rel_row * 16

    tst.l       CurrentLevelDef(a5)
    beq.s       .rbt_legacy

    ; --- 4-plane 16x16 Tiled engine ---
    mulu.w      #TILEMAP_LINE_STRIDE,d1 ; d1 = rel_row * 16 * 160
    move.w      d0,d2
    asr.w       #3,d2                   ; byte column = pixel_X / 8 = d0 * 2
    add.w       d2,d1
    add.l       d1,a0                   ; source in NonDisplayScreen
    add.l       d1,a1                   ; dest in DisplayScreen

    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)      ; D = A (copy pristine tile from NonDisplayScreen)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)  ; word-aligned 16px tile
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTAMOD(a6) ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTDMOD(a6) ; 40 - 2 = 38
    move.l      a0,BLTAPT(a6)           ; source (NonDisplayScreen)
    move.l      a1,BLTDPT(a6)           ; dest (DisplayScreen)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|(TILEMAP_TILE_BYTES/2),BLTSIZE(a6) ; 64 lines x 1 word
    bra.s       .rbt_skip

.rbt_legacy:
    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2
    add.w       d2,d1
    add.l       d1,a0
    add.l       d1,a1

    move.l      #$ffffff00,d1
    and.w       #$f,d0
    beq         .left
    move.l      #$00ffffff,d1

.left
    WAITBLIT
    move.l      #$7ca<<16,BLTCON0(a6)
    move.l      d1,BLTAFWM(a6)
    move.w      #-1,BLTADAT(a6)
    move.l      a0,BLTBPT(a6)
    move.l      a1,BLTCPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #TILE_BLT_MOD,BLTBMOD(a6)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)
.rbt_skip
    POPM        d0-d2/a0-a1
    bsr         MarkTileDirty          ; auto-flag for end-of-frame actor/frozen-player redraw
    rts


;==============================================================================
; ClearActor  -  Erase a (potentially sub-pixel-shifted) actor from DisplayScreen
;
; Unlike RestoreBackgroundTile which uses tile coordinates, ClearActor uses the
; actor's PrevX/PrevY tile position PLUS XDec/YDec sub-tile offsets to compute
; the exact pixel position.  This correctly erases an actor that is mid-animation.
;
; The mask applied to the blit depends on the X pixel offset modulo 16:
;   If offset >= 9: use the 3-word (fat) blit with first-word mask from ClearMasks
;   If offset <  9: use the 2-word (thin) blit with same mask but different modulos
;
; ClearMasks[d1*4] provides the pre-computed mask longword for each of the
; 16 possible sub-pixel X offsets.  The mask is used in BLTAFWM.
;
; After clearing, DrawActor redraws the actor at its new (advanced) position.
;
; On entry:
;   a3 = actor structure pointer
;   a5, a6 as usual
;==============================================================================

ClearActor:
    PUSHMOST

    ; Compute pixel position from previous tile + sub-pixel offsets
    move.w      Actor_PrevX(a3),d0
    lsl.w       #4,d0
    add.w       Actor_XDec(a3),d0     ; pixel X = PrevX*16 + XDec

    move.w      Actor_PrevY(a3),d1
    sub.w       TilemapScreenOffset(a5),d1 ; relative row in visible viewport
    bmi         .ca_skip
    cmp.w       #TILEMAP_VIEW_ROWS,d1
    bge         .ca_skip

    lsl.w       #4,d1                  ; pixel Y = rel_row * 16
    add.w       Actor_YDec(a3),d1     ; pixel Y = rel_row*16 + YDec

    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1

    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2
    add.w       d2,d1
    add.l       d1,a0
    add.l       d1,a1

    ; Look up the pre-computed mask for this X sub-pixel offset
    lea         ClearMasks(a5),a2
    and.w       #$f,d0                 ; d0 = X mod 16 (0..15)
    move.w      d0,d1
    add.w       d1,d1                  ; d1 = d0 * 2
    add.w       d1,d1                  ; d1 = d0 * 4 (longword index)
    move.l      (a2,d1.w),d1          ; d1 = mask longword for this shift

    cmp.w       #9,d0                  ; shift >= 9 -> fat (3-word) blit
    bcs         .left                  ; shift < 9  -> thin (2-word) blit

    ; Fat blit (shift >= 9): 3 words wide, adjusted modulos
    WAITBLIT
    move.l      #$7ca<<16,BLTCON0(a6)
    move.l      d1,BLTAFWM(a6)
    move.w      #-1,BLTADAT(a6)
    move.l      a0,BLTBPT(a6)
    move.l      a1,BLTCPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #TILE_BLT_MOD-2,BLTBMOD(a6) ; -2: 3 words per row vs 2
    move.w      #TILE_BLT_MOD-2,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD-2,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE+1,BLTSIZE(a6) ; +1 word for the extra column

    POPMOST
    rts

.left
    ; Thin blit (shift < 9): 2 words wide
    WAITBLIT
    move.l      #$7ca<<16,BLTCON0(a6)
    move.l      d1,BLTAFWM(a6)
    move.w      #-1,BLTADAT(a6)
    move.l      a0,BLTBPT(a6)
    move.l      a1,BLTCPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #TILE_BLT_MOD,BLTBMOD(a6)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)

.ca_skip
    POPMOST
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
