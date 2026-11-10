
;==============================================================================
; AMIGA GAME ENGINE
; player_water.asm  -  Oxygen, Drowning, Respawn & Rescue Pickups
;==============================================================================
;
; Part of the player module (one of player_fsm/_physics/_combat/_water.asm; all follow the
; shared register convention).
;
;   PlayerUpdateOxygen - per-frame submersion detection, lung drain / refill,
;                         drowning death trigger, and safe dry platform tracking
;   PlayerRespawn      - decrement lives, relocate to safe dry platform, center
;                         camera, and activate temporary post-respawn invulnerability
;   FindDryPlatformAboveWater - upward search of GameMap for solid dry ground
;   PlayerCheckFriends - test collision to rescue animal friends
;   PlayerCheckOxygen  - collect oxygen refills (inventory or immediate underwater use)
;
; Register convention:
;   a4 = current (active) player structure
;   a5 = Variables base
;   a6 = $dff000 (CUSTOM chip base)
;==============================================================================


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
;
; Destroys: d0-d4/d7/a0-a1 (preserves everything else, including a5/a6)
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
    ; 6. Recentre the Camera on the Respawned Player and Redraw the View
    ; -------------------------------------------------------------------------
    ; The safe platform can be far from where the player died, so the view
    ; may jump many rows. TilemapCentreCamera rebuilds every visible row and
    ; the water; crates and pickups are then drawn back on top. Enemies and
    ; friends redraw themselves on the next frame.
    movem.l     d5-d6/a2-a4,-(sp)
    bsr         TilemapCentreCamera

    ; The rebuild drew tiles only. Settled crates are redrawn only when marked
    ; dirty, and pickups only when not yet drawn, so flag them all first.
    move.w      ActorCount(a5),d7
    beq.s       .no_crates
    subq.w      #1,d7
    lea         ActorList(a5),a0
.dirty_crates:
    move.l      (a0)+,a1
    move.w      #1,Actor_Dirty(a1)
    dbra        d7,.dirty_crates
.no_crates:
    move.w      ActivePickupCount(a5),d7
    beq.s       .no_pickups
    subq.w      #1,d7
    lea         ActivePickups(a5),a0
.undrawn_pickups:
    clr.w       Pickup_Drawn(a0)
    lea         Pickup_Sizeof(a0),a0
    dbra        d7,.undrawn_pickups
.no_pickups:
    bsr         TilemapDrawPushBlocks
    bsr         TilemapDrawPickups
    movem.l     (sp)+,d5-d6/a2-a4
    clr.w       Player_PrevDrawn(a4)    ; the old footprint belongs to the previous view
    clr.w       VBlankOverrunCount(a5)  ; the multi-frame redraw is not a gameplay overrun
    rts


;==============================================================================
; FindDryPlatformAboveWater  -  Search GameMap upwards for a safe dry platform
;
; Scans GameMap from the row immediately above the water line upwards toward
; row 1. When a BLOCK_SOLID or platform tile with air above it is found,
; updates PlayerSafeX/Y/PixelX/PixelY.
;
; Destroys: none (preserves all registers)
;==============================================================================

FindDryPlatformAboveWater:
    PUSHM       d0-d4/a0
    move.w      WaterPixelY(a5),d0
    ble.s       .fail                   ; water at top of screen or inactive

    ; Start searching from the row just above the water line:
    ; Row = (WaterPixelY - 16) >> 4
    sub.w       #16,d0
    lsr.w       #4,d0                   ; d0 = candidate row index
    move.w      CurrentMapHeight(a5),d1
    subq.w      #2,d1                   ; d1 = last row with a row below it
    cmp.w       d1,d0
    ble.s       .row_clamp
    move.w      d1,d0
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
;   1. Mark friend as rescued (Friend_Collected = 1)
;   2. Increment FriendsCollectedCount(a5)
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
    tst.w       Friend_Type(a1)
    beq.s       .next_friend
    tst.w       Friend_Collected(a1)
    bne.s       .next_friend            ; already rescued

    ; Check Vertical Overlap first (coarse vertical early-out): abs(PlayerY - FriendY) < 18
    move.w      d1,d3
    sub.w       Friend_Y(a1),d3
    bpl.s       .y_pos
    neg.w       d3
.y_pos:
    cmp.w       #18,d3
    bge.s       .next_friend            ; no vertical overlap

    ; Check Horizontal Overlap: abs(PlayerX - FriendX) < 14
    move.w      d0,d2
    sub.w       Friend_X(a1),d2
    bpl.s       .x_pos
    neg.w       d2
.x_pos:
    cmp.w       #14,d2
    bge.s       .next_friend            ; no horizontal overlap

    ; --- Rescued! ---
    move.w      #1,Friend_Collected(a1)
    addq.w      #1,FriendsCollectedCount(a5)
    bsr         AudioPlayDuckRescue

.next_friend:
    lea         Friend_Sizeof(a1),a1
    dbra        d5,.friend_loop

.done_check_friends:
    movem.l     (sp)+,d2-d5/a1/a4
    rts


;==============================================================================
; PlayerCheckOxygen  -  Check player overlap with uncollected oxygen pickups
;
; If the player's bounding box overlaps an uncollected oxygen refill:
;   1. Mark bottle as collected (Pickup_Collected = 1)
;   2. Refill PlayerOxygen(a5) to OXYGEN_MAX (400)
;   3. Clear PlayerDrowning(a5) and PlayerDrownTimer(a5)
;
; In:  a5 = Variables base
; Destroys: none (preserves all registers)
;==============================================================================

PlayerCheckOxygen:
    movem.l     d2-d5/a1/a4,-(sp)

    move.w      ActivePickupCount(a5),d5
    beq.s       .done_check_oxygen
    subq.w      #1,d5

    lea         Player(a5),a4
    tst.w       Player_Status(a4)
    beq.s       .done_check_oxygen

    ; Load cached Player World coordinates
    move.w      Player_WorldX(a4),d0
    move.w      Player_WorldY(a4),d1

    lea         ActivePickups(a5),a1     ; a1 = ActivePickups pointer

.ox_loop:
    tst.w       Pickup_Collected(a1)
    bne.s       .next_ox                ; already collected

    ; Check Vertical Overlap first (coarse vertical early-out): abs(PlayerY - Pickup_Y) < 18
    move.w      d1,d3
    sub.w       Pickup_Y(a1),d3
    bpl.s       .y_pos
    neg.w       d3
.y_pos:
    cmp.w       #18,d3
    bge.s       .next_ox                ; no vertical overlap

    ; Check Horizontal Overlap: abs(PlayerX - Pickup_X) < 16
    move.w      d0,d2
    sub.w       Pickup_X(a1),d2
    bpl.s       .x_pos
    neg.w       d2
.x_pos:
    cmp.w       #16,d2
    bge.s       .next_ox                ; no horizontal overlap

    ; --- Oxygen Refill Picked Up! ---
    move.w      #1,Pickup_Collected(a1)
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
    lea         Pickup_Sizeof(a1),a1
    dbra        d5,.ox_loop

.done_check_oxygen:
    movem.l     (sp)+,d2-d5/a1/a4
    rts
