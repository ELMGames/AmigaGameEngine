;==============================================================================
; AMIGA GAME ENGINE
; entities.asm  -  Patrol enemies, animated friends and tile pickups
;==============================================================================
;
; Three entity pools that sit on top of the tilemap, alongside the crates in
; actors.asm:
;
;   ActiveEnemies  - patrol between two X bounds, animate, can be stunned
;   ActiveFriends  - animate in place until collected (Friend_Collected)
;   ActivePickups   - static tile pickups until collected (Pickup_Collected)
;
; The pools are filled from the LevelDef spawn lists by LevelInitEnemies,
; LevelInitFriends and LevelInitPickups (call them from GameLevelInitHook), and
; drawn with the shared BOB cores in bob_compositor.asm (TilemapEraseActorBOB,
; TilemapDrawActorSubPixelBOB, TilemapStampForegroundOverBox).
;
; What the game supplies (engine/ENGINE_CONTRACT.md):
;   entity_struct.i / entity_variables.i included, and the MAX_ACTIVE_* sizes
;   EnemySpritesMsk/Raw, FriendSpritesMsk/Raw  - sheet bindings (16x16, 4 per row)
;   GameEnemySheetHook   - may swap the enemy sheet (a flash frame, a palette)
;   GameEnemyOverlayHook - draws over a freshly blitted enemy (a stun effect)
;
; Collision and what collecting means are left to the game: it sets
; Friend_Collected / Pickup_Collected / Enemy_StunTimer, and these routines
; erase, skip or freeze the entity accordingly.
;
; Register convention: a4 = current entity, a5 = Variables base,
;                      a6 = CUSTOM chip base
;==============================================================================

;==============================================================================
; LevelInitEnemies  -  Initialize ActiveEnemies array from current LevelDef
;
; Reads spawn records from LevelDef_EnemyList (or LevelDefaultEnemyList) and
; fills ActiveEnemies in RAM.  Each spawn record contains:
;   dc.w Type, Col, Row, SpawnX, SpawnY, PatrolMinX, PatrolMaxX, Speed
;
; Sets ActiveEnemyCount and clears drawn state.
;
; Destroys: none (preserves all registers)
;==============================================================================

LevelInitEnemies:
    PUSHM       d0-d7/a0-a3
    clr.w       ActiveEnemyCount(a5)

    ; Clear entire ActiveEnemies buffer
    lea         ActiveEnemies(a5),a1
    move.w      #(Enemy_Sizeof*MAX_ACTIVE_ENEMIES)/2-1,d7
.clear_loop:
    clr.w       (a1)+
    dbra        d7,.clear_loop

    ; Locate LevelDef EnemyList
    move.l      CurrentLevelDef(a5),d0
    beq.s       .legacy_enemy_list
    movea.l     d0,a0
    move.l      LevelDef_EnemyList(a0),d0
    beq         .done_init_enemies
    movea.l     d0,a0
    bra.s       .start_populating

.legacy_enemy_list:
    lea         LevelDefaultEnemyList,a0

.start_populating:
    lea         ActiveEnemies(a5),a1
    clr.w       d6                      ; d6 = count

.populate_loop:
    move.w      (a0)+,d0                ; Type (1..8, or $ffff end marker)
    cmp.w       #$ffff,d0
    beq         .finish_init
    cmp.w       #MAX_ACTIVE_ENEMIES,d6
    bge         .finish_init            ; table full

    move.w      (a0)+,d1                ; Col
    move.w      (a0)+,d2                ; Row
    move.w      (a0)+,d3                ; SpawnX
    move.w      (a0)+,d4                ; SpawnY
    move.w      (a0)+,d5                ; PatrolMinX
    move.w      (a0)+,d7                ; PatrolMaxX
    move.w      (a0)+,d1                ; Speed

    ; Sanity clamp patrol bounds to valid horizontal range [0 .. 288]
    cmp.w       #0,d5
    bge.s       .min_ok
    moveq       #0,d5
.min_ok:
    cmp.w       #288,d7
    ble.s       .max_ok
    move.w      #288,d7
.max_ok:
    cmp.w       d7,d5
    ble.s       .bounds_ordered
    exg         d5,d7
.bounds_ordered:

    ; Clamp initial SpawnX within [PatrolMinX .. PatrolMaxX]
    cmp.w       d5,d3
    bge.s       .spawn_not_too_low
    move.w      d5,d3
.spawn_not_too_low:
    cmp.w       d7,d3
    ble.s       .spawn_in_range
    move.w      d7,d3
.spawn_in_range:

    ; Store in ActiveEnemy instance (a1)
    move.w      d0,Enemy_Type(a1)
    move.w      d3,Enemy_X(a1)
    move.w      d4,Enemy_Y(a1)
    move.w      #1,Enemy_Direction(a1)     ; start moving right (+1)
    move.w      d1,Enemy_Speed(a1)
    move.w      d5,Enemy_PatrolMinX(a1)
    move.w      d7,Enemy_PatrolMaxX(a1)
    clr.w       Enemy_AnimFrame(a1)
    clr.w       Enemy_PrevX(a1)
    clr.w       Enemy_PrevY(a1)
    clr.w       Enemy_Drawn(a1)

    lea         Enemy_Sizeof(a1),a1
    addq.w      #1,d6
    bra.s       .populate_loop

.finish_init:
    move.w      d6,ActiveEnemyCount(a5)

.done_init_enemies:
    POPM        d0-d7/a0-a3
    rts


;==============================================================================
; LevelInitFriends  -  Initialize ActiveFriends array from current LevelDef
;
; Reads spawn records from LevelDef_FriendList and fills ActiveFriends in RAM.
; Each spawn record contains:
;   dc.w Type, Col, Row, SpawnX, SpawnY, Res1, Res2, Res3 (16 bytes per record)
; List terminated by $FFFF.
;
; Sets ActiveFriendCount and clears drawn state.
;
; Destroys: none (preserves all registers)
;==============================================================================

LevelInitFriends:
    PUSHM       d0-d7/a0-a3
    clr.w       ActiveFriendCount(a5)
    clr.w       FriendsCollectedCount(a5)

    ; Clear entire ActiveFriends buffer
    lea         ActiveFriends(a5),a1
    move.w      #(Friend_Sizeof*MAX_ACTIVE_FRIENDS)/2-1,d7
.clear_friend_loop:
    clr.w       (a1)+
    dbra        d7,.clear_friend_loop

    ; Locate LevelDef FriendList
    move.l      CurrentLevelDef(a5),d0
    beq.s       .done_init_friends
    movea.l     d0,a0
    move.l      LevelDef_FriendList(a0),d0
    beq.s       .done_init_friends
    movea.l     d0,a0                   ; a0 = FriendList source

    lea         ActiveFriends(a5),a1    ; a1 = ActiveFriends destination
    clr.w       d6                      ; d6 = count

.populate_friend_loop:
    move.w      (a0)+,d0                ; Type (1..4, or $ffff end marker)
    cmp.w       #$ffff,d0
    beq.s       .finish_friend_init
    cmp.w       #MAX_ACTIVE_FRIENDS,d6
    bge.s       .finish_friend_init     ; table full

    move.w      (a0)+,d1                ; Col
    move.w      (a0)+,d2                ; Row
    move.w      (a0)+,d3                ; SpawnX
    move.w      (a0)+,d4                ; SpawnY
    addq.l      #6,a0                   ; skip Res1, Res2, Res3 (6 bytes)

    ; Store in ActiveFriend instance (a1)
    move.w      d0,Friend_Type(a1)
    move.w      d3,Friend_X(a1)
    move.w      d4,Friend_Y(a1)
    clr.w       Friend_AnimFrame(a1)
    move.w      d6,d5
    lsl.w       #2,d5                   ; stagger initial anim timer (0, 4, 8, 12...)
    move.w      d5,Friend_AnimTimer(a1)
    clr.w       Friend_Collected(a1)
    clr.w       Friend_PrevX(a1)
    clr.w       Friend_PrevY(a1)
    clr.w       Friend_Drawn(a1)

    lea         Friend_Sizeof(a1),a1
    addq.w      #1,d6
    bra.s       .populate_friend_loop

.finish_friend_init:
    move.w      d6,ActiveFriendCount(a5)

.done_init_friends:
    POPM        d0-d7/a0-a3
    rts


;==============================================================================
; LevelInitPickups  -  Initialize ActivePickups array from current LevelDef
;
; Reads spawn records from LevelDef_PickupList and fills ActivePickups in RAM.
; Each spawn record contains:
;   Col (w), Row (w), PixelX (w), PixelY (w), TileId (w), Res1 (w), Res2 (w), Res3 (w)
; Format ends with $ffff word marker.
;
; Sets ActivePickupCount and clears drawn / collected state.
;
; Destroys: none (preserves all registers)
;==============================================================================

LevelInitPickups:
    PUSHM       d0-d7/a0-a3
    clr.w       ActivePickupCount(a5)

    ; Clear entire ActivePickups buffer
    lea         ActivePickups(a5),a1
    move.w      #(Pickup_Sizeof*MAX_ACTIVE_PICKUPS)/2-1,d7
.clear_pickup_loop:
    clr.w       (a1)+
    dbra        d7,.clear_pickup_loop

    ; Locate LevelDef PickupList
    move.l      CurrentLevelDef(a5),d0
    beq.s       .done_init_pickups
    movea.l     d0,a0
    move.l      LevelDef_PickupList(a0),d0
    beq.s       .done_init_pickups
    movea.l     d0,a0                   ; a0 = PickupList source

    lea         ActivePickups(a5),a1     ; a1 = ActivePickups destination
    clr.w       d6                      ; d6 = count

.populate_pickup_loop:
    move.w      (a0)+,d1                ; Col (or $ffff end marker)
    cmp.w       #$ffff,d1
    beq.s       .finish_pickup_init
    cmp.w       #MAX_ACTIVE_PICKUPS,d6
    bge.s       .finish_pickup_init     ; table full

    move.w      (a0)+,d2                ; Row
    move.w      (a0)+,d3                ; PixelX
    move.w      (a0)+,d4                ; PixelY
    move.w      (a0)+,d0                ; TileId (e.g. 95)
    addq.l      #6,a0                   ; skip Res1, Res2, Res3 (6 bytes)

    ; Store in ActivePickups instance (a1)
    move.w      d1,Pickup_Col(a1)
    move.w      d2,Pickup_Row(a1)
    move.w      d3,Pickup_X(a1)
    move.w      d4,Pickup_Y(a1)
    clr.w       Pickup_Collected(a1)
    clr.w       Pickup_Drawn(a1)
    move.w      d0,Pickup_TileId(a1)

    lea         Pickup_Sizeof(a1),a1
    addq.w      #1,d6
    bra.s       .populate_pickup_loop

.finish_pickup_init:
    move.w      d6,ActivePickupCount(a5)

.done_init_pickups:
    POPM        d0-d7/a0-a3
    rts

;==============================================================================
; TilemapEraseEnemies  -  Erase every drawn enemy (undo, level teardown)
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapEraseEnemies:
    PUSHM       d0-d7/a0-a4

    move.w      ActiveEnemyCount(a5),d7
    beq.s       .done_erase_enemies
    subq.w      #1,d7
    lea         ActiveEnemies(a5),a4    ; a4 = current ActiveEnemy pointer

.erase_loop:
    tst.w       Enemy_Drawn(a4)
    beq.s       .next_erase
    bsr         TilemapEraseEnemy
    clr.w       Enemy_Drawn(a4)
.next_erase:
    lea         Enemy_Sizeof(a4),a4
    dbra        d7,.erase_loop

.done_erase_enemies:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapUpdateEnemies  -  Per-frame dynamic enemy update & sub-pixel blit
;
; Sequence:
;   1. Update patrol movement: Enemy_X += Enemy_Direction * Enemy_Speed
;      Bounce against [Enemy_PatrolMinX .. Enemy_PatrolMaxX] and invert direction.
;   2. Advance animation frame every 8 frames (0..3).
;   3. If within visible camera window, blit using sub-pixel barrel shifter (BLTCON0 shift).
;      Uses cookie-cutter mask ($0FCA) to draw cleanly over background and player!
;
; Note: Erasing previous enemy footprints is handled by TilemapEraseEnemies
; at the start of the frame BEFORE TilemapDrawPlayer.
;
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

; The update walks EnemyDrawOrder, so enemies are moved and drawn top of
; the screen first: each one gets the longest possible head start on the
; beam. GameRunFrame calls TilemapUpdateEnemiesInRange once per slice of the
; screen, top to bottom, with the player drawn between slices.

TilemapUpdateTopEnemies:
    move.w      #-32768,d0              ; top rows only (ScreenY < ENTITY_TOP_TIER_Y)
    move.w      #ENTITY_TOP_TIER_Y,d1
    bra.s       TilemapUpdateEnemiesInRange


; Entry point: lower rows only (ScreenY >= ENTITY_TOP_TIER_Y), chasing the beam
; Destroys: none (preserves all registers)
TilemapUpdateLowerEnemies:
    move.w      #ENTITY_TOP_TIER_Y,d0   ; lower rows only
    move.w      #32767,d1
    bra.s       TilemapUpdateEnemiesInRange


; Entry point: all rows
; Destroys: none (preserves all registers)
TilemapUpdateEnemies:
    move.w      #-32768,d0
    move.w      #32767,d1

    ; fall through to TilemapUpdateEnemiesInRange

;==============================================================================
; TilemapUpdateEnemiesInRange  -  Move and draw the enemies in a screen-Y slice
;
; In:  d0.w = first screen Y of the slice (inclusive)
;      d1.w = end screen Y of the slice (exclusive)
;      Screen Y = Enemy_Y - TilemapCameraY. Enemies are processed top first.
; Destroys: none (preserves all registers)
;==============================================================================

TilemapUpdateEnemiesInRange:
    PUSHM       d0-d7/a0-a4
    bsr         SortEnemyDrawOrder
    move.w      d1,-(sp)                ; 6(sp) = slice end (exclusive)
    move.w      d0,-(sp)                ; 4(sp) = slice start
    pea         EnemyDrawOrder(a5)      ; 0(sp) = next entry in the sorted list

    move.w      EnemyDrawCount(a5),d7
    beq         .done_update_enemies
    subq.w      #1,d7

.update_draw_loop:
    move.l      (sp),a0
    move.l      (a0)+,a4                ; a4 = next enemy, top of the screen first
    move.l      a0,(sp)
    tst.w       Enemy_Type(a4)
    beq         .next_update_draw

    ; -------------------------------------------------------------------------
    ; Slice filter: only enemies whose screen Y is in [start, end)
    ; -------------------------------------------------------------------------
    move.w      Enemy_Y(a4),d1
    sub.w       TilemapCameraY(a5),d1   ; d1 = Screen Y
    cmp.w       4(sp),d1
    blt         .next_update_draw       ; above this slice
    cmp.w       6(sp),d1
    bge         .next_update_draw       ; below this slice

.filter_match:

    ; Check if stunned (the game sets Enemy_StunTimer): halt in tracks and keep the pose
    tst.w       Enemy_StunTimer(a4)
    beq.s       .not_stunned
    subq.w      #1,Enemy_StunTimer(a4)     ; tick down stun duration
    bra.s       .check_enemy_vis        ; skip movement and frame advance

.not_stunned:
    ; Step 1: Update Movement & Patrol Turnaround
    move.w      Enemy_Direction(a4),d0     ; +1 or -1
    muls.w      Enemy_Speed(a4),d0         ; delta X
    add.w       d0,Enemy_X(a4)

    ; Check Right Bound (PatrolMaxX)
    move.w      Enemy_X(a4),d1
    cmp.w       Enemy_PatrolMaxX(a4),d1
    blt.s       .check_left_bound
    move.w      Enemy_PatrolMaxX(a4),Enemy_X(a4)
    move.w      #-1,Enemy_Direction(a4)    ; turn left
    bra.s       .update_anim

.check_left_bound:
    cmp.w       Enemy_PatrolMinX(a4),d1
    bgt.s       .update_anim
    move.w      Enemy_PatrolMinX(a4),Enemy_X(a4)
    move.w      #1,Enemy_Direction(a4)     ; turn right

.update_anim:
    ; Step 3: Animate Frame (every 8 frames)
    move.w      TickCounter(a5),d0
    andi.w      #7,d0
    bne.s       .check_enemy_vis
    addq.w      #1,Enemy_AnimFrame(a4)
    andi.w      #3,Enemy_AnimFrame(a4)

.check_enemy_vis:
    ; Viewport Y culling: check if enemy is in active display rows
    move.w      Enemy_Y(a4),d1
    cmp.w       CameraCullTopY(a5),d1
    blt.s       .enemy_offscreen
    cmp.w       CameraCullBottomY(a5),d1
    ble.s       .draw_current_enemy

.enemy_offscreen:
    ; Enemy is offscreen: if still drawn from previous camera position, erase once
    tst.w       Enemy_Drawn(a4)
    beq         .next_update_draw
    bsr         TilemapEraseEnemy
    clr.w       Enemy_Drawn(a4)
    bra         .next_update_draw

.draw_current_enemy:
    ; Erase previous enemy footprint immediately before drawing new frame
    tst.w       Enemy_Drawn(a4)
    beq.s       .check_entities_new
    bsr         TilemapEraseEnemy
    clr.w       Enemy_Drawn(a4)

    ; Re-blit any entity objects (push block, friend, pickup) overlapping previous or new tiles
    move.w      Enemy_Y(a4),d1
    lsr.w       #4,d1                   ; d1 = Row

    ; start_col = min(Enemy_PrevX, Enemy_X) >> 4
    move.w      Enemy_PrevX(a4),d2
    cmp.w       Enemy_X(a4),d2
    ble.s       .col_min_ok
    move.w      Enemy_X(a4),d2
.col_min_ok:
    lsr.w       #4,d2                   ; d2 = start_col

    ; end_col = max(Enemy_PrevX + 15, Enemy_X + 15) >> 4
    move.w      Enemy_PrevX(a4),d3
    cmp.w       Enemy_X(a4),d3
    bge.s       .col_max_ok
    move.w      Enemy_X(a4),d3
.col_max_ok:
    add.w       #15,d3
    lsr.w       #4,d3                   ; d3 = end_col

.restore_entity_loop:
    cmp.w       d3,d2
    bgt.s       .check_player_overlap
    move.w      d2,d0                   ; d0 = Col
    bsr         TilemapRestoreTileEntities
    addq.w      #1,d2
    bra.s       .restore_entity_loop

.check_entities_new:
    ; Enemy was not drawn last frame, check current position only
    move.w      Enemy_Y(a4),d1
    lsr.w       #4,d1                   ; d1 = Row
    move.w      Enemy_X(a4),d2
    lsr.w       #4,d2                   ; d2 = start_col
    move.w      Enemy_X(a4),d3
    add.w       #15,d3
    lsr.w       #4,d3                   ; d3 = end_col
    bra.s       .restore_entity_loop

.check_player_overlap:
    ; If this enemy's footprint overlaps the player BOB, re-blit the player
    ; so the player is intact underneath before the enemy cookie-cuts on top!
    lea         Player(a5),a2
    tst.w       Player_Status(a2)
    beq.s       .do_draw_enemy
    tst.w       Player_PrevDrawn(a2)
    beq.s       .do_draw_enemy

    ; Check X overlap: (ex_left <= px_right) and (ex_right >= px_left)
    move.w      Player_PrevX(a2),d0     ; px_left
    move.w      d0,d1
    add.w       #PLAYER_WIDTH-1,d1      ; px_right = px_left + 23

    ; ex_left = min(Enemy_X, Enemy_PrevX)
    move.w      Enemy_X(a4),d2
    cmp.w       Enemy_PrevX(a4),d2
    ble.s       .ex_left_ok
    move.w      Enemy_PrevX(a4),d2
.ex_left_ok:
    cmp.w       d1,d2                   ; ex_left > px_right?
    bgt.s       .do_draw_enemy

    ; ex_right = max(Enemy_X, Enemy_PrevX) + 15
    move.w      Enemy_X(a4),d3
    cmp.w       Enemy_PrevX(a4),d3
    bge.s       .ex_right_ok
    move.w      Enemy_PrevX(a4),d3
.ex_right_ok:
    add.w       #15,d3                  ; ex_right
    cmp.w       d0,d3                   ; ex_right < px_left?
    blt.s       .do_draw_enemy

    ; Check Y overlap: (ey_top <= py_bottom) and (ey_bottom >= py_top)
    move.w      Player_PrevY(a2),d0     ; py_top
    move.w      d0,d1
    add.w       #PLAYER_HEIGHT-1,d1     ; py_bottom = py_top + 23

    move.w      Enemy_Y(a4),d2             ; ey_top
    cmp.w       d1,d2                   ; ey_top > py_bottom?
    bgt.s       .do_draw_enemy

    move.w      d2,d3
    add.w       #15,d3                  ; ey_bottom
    cmp.w       d0,d3                   ; ey_bottom < py_top?
    blt.s       .do_draw_enemy

    ; Overlap detected! Re-blit player with cookie-cutter mask ($0FCA)
    movem.l     d7/a4,-(sp)             ; preserve enemy loop counter d7 and enemy pointer a4
    movea.l     a2,a4                   ; a4 -> Player struct
    bsr         TilemapDrawPlayer       ; re-draw player cleanly
    bsr         TilemapSubmergePlayer   ; apply water tinting if submerged
    movem.l     (sp)+,d7/a4             ; restore enemy pointer and loop counter

.do_draw_enemy:
    ; Step 4: Draw Enemy with Sub-Pixel Shifter (if in visible viewport)
    bsr         TilemapDrawEnemySubPixel

.next_update_draw:
    dbra        d7,.update_draw_loop

.done_update_enemies:
    addq.l      #8,sp                   ; drop the list pointer and slice bounds
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; SortEnemyDrawOrder  -  Keep EnemyDrawOrder sorted by Enemy_Y (top first)
;
; EnemyDrawOrder holds a pointer to every ActiveEnemies slot. It is refilled
; in slot order when the enemy count changes (level start, undo), then kept
; sorted with an insertion sort. Enemies patrol sideways, so their Y rarely
; changes and the list is almost always already in order: one comparison per
; enemy. The sort is stable, so enemies on the same row keep slot order.
;
; Destroys: none (preserves all registers)
;==============================================================================

SortEnemyDrawOrder:
    PUSHM       d0-d3/a0-a2
    move.w      ActiveEnemyCount(a5),d0
    cmp.w       EnemyDrawCount(a5),d0
    beq.s       .sedo_sort
    move.w      d0,EnemyDrawCount(a5)   ; count changed: refill in slot order
    beq.s       .sedo_done
    subq.w      #1,d0
    lea         ActiveEnemies(a5),a1
    lea         EnemyDrawOrder(a5),a0
.sedo_fill:
    move.l      a1,(a0)+
    lea         Enemy_Sizeof(a1),a1
    dbra        d0,.sedo_fill

.sedo_sort:
    move.w      EnemyDrawCount(a5),d0
    cmp.w       #2,d0
    blt.s       .sedo_done
    lea         EnemyDrawOrder(a5),a0
    moveq       #1,d1                   ; d1 = i
.sedo_outer:
    move.w      d1,d2
    lsl.w       #2,d2                   ; d2 = offset of entry i
    move.l      (a0,d2.w),a1            ; a1 = key enemy
    move.w      Enemy_Y(a1),d3          ; d3 = key Y
.sedo_inner:
    subq.w      #4,d2                   ; d2 = offset of entry j (j = i-1 downwards)
    bmi.s       .sedo_insert
    move.l      (a0,d2.w),a2
    cmp.w       Enemy_Y(a2),d3
    bge.s       .sedo_insert            ; key Y >= entry j: insert after it (stable)
    move.l      a2,4(a0,d2.w)           ; shift entry j down one place
    bra.s       .sedo_inner
.sedo_insert:
    move.l      a1,4(a0,d2.w)
    addq.w      #1,d1
    cmp.w       d0,d1
    blt.s       .sedo_outer
.sedo_done:
    POPM        d0-d3/a0-a2
    rts


;==============================================================================
; TilemapRedrawEnemiesOverPlayer  -  Put enemies back in front of the player's stamps
;
; GameRunFrame draws the enemies straight after the player's erase and blit,
; and the player's stamps after them. The ladder-scenery stamp re-blits the
; scenery tiles beside a ladder so the player climbs behind them, which would
; also cover an enemy standing in one of those tiles. This redraws (draw only,
; same position) every enemy whose box overlaps the area the stamps touch:
; the player's box widened by one tile each side, from its erased to its
; drawn position.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapRedrawEnemiesOverPlayer:
    PUSHM       d0-d7/a0-a4
    lea         Player(a5),a2
    tst.w       Player_PrevDrawn(a2)
    beq         .treop_exit

    move.w      Player_PrevX(a2),d4
    sub.w       #16,d4                  ; d4 = left edge (one tile to the left)
    move.w      d4,d5
    add.w       #16+PLAYER_WIDTH+16,d5  ; d5 = right edge, exclusive (one tile to the right)
    move.w      Player_PrevY(a2),d6     ; d6 = top
    move.w      d6,d3                   ; d3 = bottom, exclusive (below)
    move.w      Player_ErasedY(a5),d0
    cmp.w       d6,d0
    bge.s       .treop_top_ok
    move.w      d0,d6
.treop_top_ok:
    cmp.w       d3,d0
    ble.s       .treop_bot_ok
    move.w      d0,d3
.treop_bot_ok:
    add.w       #PLAYER_HEIGHT,d3

    move.w      EnemyDrawCount(a5),d7
    beq.s       .treop_exit
    subq.w      #1,d7
    lea         EnemyDrawOrder(a5),a3
.treop_loop:
    move.l      (a3)+,a4
    tst.w       Enemy_Type(a4)
    beq.s       .treop_next
    tst.w       Enemy_Drawn(a4)         ; only enemies drawn this frame
    beq.s       .treop_next
    move.w      Enemy_X(a4),d0
    move.w      d0,d1
    add.w       #ENEMY_FRAME_WIDTH,d1
    cmp.w       d4,d1
    ble.s       .treop_next             ; enemy right edge <= area left
    cmp.w       d5,d0
    bge.s       .treop_next             ; enemy left edge >= area right
    move.w      Enemy_Y(a4),d0
    move.w      d0,d1
    add.w       #ENEMY_FRAME_HEIGHT,d1
    cmp.w       d6,d1
    ble.s       .treop_next             ; enemy bottom <= area top
    cmp.w       d3,d0
    bge.s       .treop_next             ; enemy top >= area bottom
    movem.l     d3-d7/a3,-(sp)
    bsr         TilemapDrawEnemySubPixel ; same position: puts it back in front
    movem.l     (sp)+,d3-d7/a3
.treop_next:
    dbra        d7,.treop_loop
.treop_exit:
    POPM        d0-d7/a0-a4
    rts

;==============================================================================
; TilemapRedrawDrawnEnemies  -  Draw every on-screen enemy again, without moving it
;
; Used by GameRedrawHeldFrame, where no enemy update runs.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapRedrawDrawnEnemies:
    PUSHM       d0-d7/a0-a4
    move.w      EnemyDrawCount(a5),d7
    beq.s       .trde_exit
    subq.w      #1,d7
    lea         EnemyDrawOrder(a5),a3
.trde_loop:
    move.l      (a3)+,a4
    tst.w       Enemy_Type(a4)
    beq.s       .trde_next
    tst.w       Enemy_Drawn(a4)
    beq.s       .trde_next
    movem.l     d7/a3,-(sp)
    bsr         TilemapDrawEnemySubPixel
    movem.l     (sp)+,d7/a3
.trde_next:
    dbra        d7,.trde_loop
.trde_exit:
    POPM        d0-d7/a0-a4
    rts



;==============================================================================
; TilemapRestoreTileEntities  -  Re-blit the crate, pickup or friend on one tile
;
; Called by the enemy update for each tile column an enemy's erase touched, so
; a settled crate, an uncollected pickup or a friend sharing that tile is put
; back before the enemy is drawn over it.
;
; In:  d0.w = Col (0..19)
;      d1.w = Row (0..41)
;      a5   = Variables base
;      a6   = CUSTOM
; Preserves: all registers
;==============================================================================
TilemapRestoreTileEntities:
    cmp.w       #0,d0
    blt         .rte_exit
    cmp.w       #TILEMAP_VIEW_COLS,d0
    bge         .rte_exit
    cmp.w       #0,d1
    blt         .rte_exit
    cmp.w       CurrentMapHeight(a5),d1
    bge         .rte_exit

    PUSHM       d0-d7/a0-a4

    ; Early out: if no actors, pickups, or friends in the level, exit immediately
    move.w      ActorCount(a5),d5
    or.w        ActivePickupCount(a5),d5
    or.w        ActiveFriendCount(a5),d5
    beq         .rte_done

    move.w      d0,d6                   ; d6 = target Col
    move.w      d1,d7                   ; d7 = target Row

    ; -------------------------------------------------------------------------
    ; 1. Check Settled Push Blocks (Crates)
    ; -------------------------------------------------------------------------
    move.w      ActorCount(a5),d5
    beq         .rte_check_pickup

    ; Early-out GameMap guard: if player is not actively pushing, check GameMap cell
    cmp.w       #ACTION_PUSH,ActionStatus(a5)
    beq.s       .rte_scan_crates

    ; Fast cell offset: (Row * 20) + Col
    move.w      d7,d0
    lsl.w       #4,d0                   ; Row * 16
    move.w      d7,d1
    lsl.w       #2,d1                   ; Row * 4
    add.w       d1,d0                   ; Row * 20
    add.w       d6,d0                   ; Row * 20 + Col
    lea         GameMap(a5),a0
    move.b      (a0,d0.w),d0
    cmp.b       #BLOCK_PUSH,d0
    bne.s       .rte_check_pickup       ; cell has no push block!

.rte_scan_crates:
    subq.w      #1,d5
    lea         ActorList(a5),a2
.rte_crate_loop:
    move.l      (a2)+,a3
    tst.w       Actor_Status(a3)
    beq.s       .rte_next_crate
    move.w      Actor_Type(a3),d4
    cmp.w       #BLOCK_PUSH,d4
    bne.s       .rte_next_crate
.rte_is_crate:
    tst.w       Actor_HasFalled(a3)
    bne.s       .rte_next_crate

    tst.w       Actor_HasMoved(a3)
    beq.s       .rte_crate_static

    ; Moving crate (being pushed):
    cmp.w       Actor_Y(a3),d7
    bne.s       .rte_next_crate
    cmp.w       Actor_X(a3),d6
    beq.s       .rte_draw_moving_crate
    cmp.w       Actor_PrevX(a3),d6
    bne.s       .rte_next_crate

.rte_draw_moving_crate:
    bsr         DrawActor
    bra.s       .rte_check_pickup

.rte_crate_static:
    cmp.w       Actor_X(a3),d6
    bne.s       .rte_next_crate
    cmp.w       Actor_Y(a3),d7
    bne.s       .rte_next_crate

    ; Match! Blit crate with cookie-cutter mask ($0FCA)
    move.w      Actor_SpriteOffset(a3),d0
    move.w      d7,d2                   ; Row
    move.w      d6,d3                   ; Col
    bsr         TilemapBlitSingleTile
    move.w      d6,d0
    lsl.w       #4,d0
    move.w      d7,d1
    lsl.w       #4,d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox
    move.w      d6,d0
    move.w      d7,d1
    bsr         TilemapSubmergeTile
    bra.s       .rte_check_pickup       ; continue checking other layers

.rte_next_crate:
    dbra        d5,.rte_crate_loop

    ; -------------------------------------------------------------------------
    ; 2. Check Pickups
    ; -------------------------------------------------------------------------
.rte_check_pickup:
    move.w      ActivePickupCount(a5),d5
    beq.s       .rte_check_friends
    subq.w      #1,d5
    lea         ActivePickups(a5),a4
.rte_pickup_loop:
    tst.w       Pickup_Collected(a4)
    bne.s       .rte_next_pickup
    cmp.w       Pickup_Col(a4),d6
    bne.s       .rte_next_pickup
    cmp.w       Pickup_Row(a4),d7
    bne.s       .rte_next_pickup

    ; Match! Blit pickup with cookie-cutter mask ($0FCA)
    move.w      Pickup_TileId(a4),d0
    move.w      d7,d2                   ; Row
    move.w      d6,d3                   ; Col
    bsr         TilemapBlitSingleTile
    move.w      #1,Pickup_Drawn(a4)
    move.w      d6,d0
    lsl.w       #4,d0
    move.w      d7,d1
    lsl.w       #4,d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox
    move.w      d6,d0
    move.w      d7,d1
    bsr         TilemapSubmergeTile
    bra.s       .rte_check_friends

.rte_next_pickup:
    lea         Pickup_Sizeof(a4),a4
    dbra        d5,.rte_pickup_loop

    ; -------------------------------------------------------------------------
    ; 3. Check Friends
    ; -------------------------------------------------------------------------
.rte_check_friends:
    move.w      ActiveFriendCount(a5),d5
    beq.s       .rte_done
    subq.w      #1,d5
    lea         ActiveFriends(a5),a4
.rte_friend_loop:
    tst.w       Friend_Type(a4)
    beq.s       .rte_next_friend
    tst.w       Friend_Collected(a4)
    bne.s       .rte_next_friend

    ; Check if friend tile matches (d6, d7)
    move.w      Friend_X(a4),d0
    lsr.w       #4,d0
    cmp.w       d0,d6
    bne.s       .rte_next_friend
    move.w      Friend_Y(a4),d1
    lsr.w       #4,d1
    cmp.w       d1,d7
    bne.s       .rte_next_friend

    ; Match! Blit friend with cookie-cutter mask ($0FCA)
    bsr         TilemapDrawFriendSubPixel
    move.w      #1,Friend_Drawn(a4)
    bra.s       .rte_done

.rte_next_friend:
    lea         Friend_Sizeof(a4),a4
    dbra        d5,.rte_friend_loop

.rte_done:
    POPM        d0-d7/a0-a4

.rte_exit:
    rts


;==============================================================================
; TilemapEraseEnemy  -  Restore pristine background under previous enemy blit
;
; In: a4 = ActiveEnemy pointer
; Destroys: d0-d5, a0-a2
;==============================================================================

TilemapEraseEnemy:
    move.w      Enemy_PrevX(a4),d0
    move.w      Enemy_PrevY(a4),d1
    moveq       #ENEMY_FRAME_HEIGHT,d5
    bra         TilemapEraseActorBOB


;==============================================================================
; TilemapDrawEnemySubPixel  -  Draw an enemy via the shared sub-pixel BOB core
;
; Resolves the enemy's mask/raw source frame (GameEnemySheetHook may swap
; the sheet), delegates the blit to TilemapDrawActorSubPixelBOB, then lets
; GameEnemyOverlayHook draw on top and applies the water submersion tint.
;
; In:  a4 = ActiveEnemy pointer
;      a5 = Variables base
;      a6 = CUSTOM chip base
; Destroys: d0-d5, a0-a3
;==============================================================================

TilemapDrawEnemySubPixel:
    move.w      Enemy_X(a4),d0             ; 0..319
    move.w      Enemy_Y(a4),d1             ; 0..671

    ; Source frame pointer: enemy sprite sheet layout:
    ;   - 8 enemy types (Enemy_Type 1..8) stacked vertically
    ;   - 4 animation frames per type (Enemy_AnimFrame 0..3) across each row
    ;   Source offset = (Type - 1) * ENEMY_ROW_STRIDE + (AnimFrame * 2 bytes)
    move.w      Enemy_Type(a4),d2
    subq.w      #1,d2                   ; 0..7
    mulu.w      #ENEMY_ROW_STRIDE,d2
    moveq       #0,d3
    move.w      Enemy_AnimFrame(a4),d3
    add.w       d3,d3                   ; d3 = AnimFrame * 2 bytes (word column in sheet)
    add.l       d3,d2

    lea         EnemySpritesMsk,a0      ; a0 = base of cookie-cutter mask sheet
    lea         EnemySpritesRaw,a1      ; a1 = base of colour sheet
    bsr         GameEnemySheetHook      ; game may point a1 at another sheet (may use d3-d4)
    adda.l      d2,a0                   ; a0 = mask frame source pointer
    adda.l      d2,a1                   ; a1 = raw graphic frame source pointer

    moveq       #ENEMY_FRAME_HEIGHT,d5
    bsr         TilemapDrawActorSubPixelBOB
    tst.w       d4
    bne         .culled_enemy

    ; Record previous coordinates so TilemapEraseEnemy can cleanly restore background next frame
    move.w      d0,Enemy_PrevX(a4)
    move.w      d1,Enemy_PrevY(a4)
    move.w      #1,Enemy_Drawn(a4)

    ; Game overlay (a stun effect, a highlight): a2 = destination of the
    ; enemy box in DisplayScreen, d0 = world X; preserves all registers
    bsr         GameEnemyOverlayHook

    ; Water Submersion Check: tint enemy in DisplayScreen if rising
    ; floodwaters have reached its scanlines.
    move.w      WaterPixelY(a5),d2      ; d2 = WaterPixelY
    bmi.s       .exit_draw              ; if no water (< 0), done
    movea.l     a2,a0                   ; a0 = destination in DisplayScreen
    move.w      d7,-(sp)                ; preserve loop counter
    move.w      #ENEMY_FRAME_HEIGHT,d7  ; 16 scanlines
    bsr         TilemapSubmergeActor
    move.w      (sp)+,d7

.exit_draw:
    rts

.culled_enemy:
    clr.w       Enemy_Drawn(a4)            ; flag as off-screen (skip erase)
    rts


;==============================================================================
; TilemapErasePickups  -  Restore pristine background under drawn pickups
;
; In:  a5 = Variables base
;      a6 = CUSTOM chip base
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

TilemapErasePickups:
    PUSHM       d0-d7/a0-a4

    move.w      ActivePickupCount(a5),d7
    beq.s       .done_erase_pickups
    subq.w      #1,d7
    lea         ActivePickups(a5),a4    ; a4 = current ActivePickups pointer

.erase_loop:
    tst.w       Pickup_Drawn(a4)
    beq.s       .next_erase
    move.w      Pickup_X(a4),d0
    move.w      Pickup_Y(a4),d1
    bsr         TilemapErase16x16Actor
    clr.w       Pickup_Drawn(a4)
.next_erase:
    lea         Pickup_Sizeof(a4),a4
    dbra        d7,.erase_loop

.done_erase_pickups:
    POPM        d0-d7/a0-a4
    rts

;==============================================================================
; TilemapEraseFriends  -  Erase every drawn friend
;
; Walks ActiveFriends and calls TilemapEraseFriend for each entry whose
; Friend_Drawn flag is set, clearing the flag.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapEraseFriends:
    PUSHM       d0-d7/a0-a4

    move.w      ActiveFriendCount(a5),d7
    beq.s       .done_erase_friends
    subq.w      #1,d7
    lea         ActiveFriends(a5),a4    ; a4 = current ActiveFriend pointer

.erase_loop:
    tst.w       Friend_Drawn(a4)
    beq.s       .next_erase
    bsr         TilemapEraseFriend
    clr.w       Friend_Drawn(a4)
.next_erase:
    lea         Friend_Sizeof(a4),a4
    dbra        d7,.erase_loop

.done_erase_friends:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapEraseFriend  -  Restore pristine background under previous friend blit
;
; In: a4 = ActiveFriend pointer
; Destroys: d0-d5, a0-a2
;==============================================================================

TilemapEraseFriend:
    move.w      Friend_PrevX(a4),d0
    move.w      Friend_PrevY(a4),d1
    moveq       #FRIEND_FRAME_HEIGHT,d5
    bra         TilemapEraseActorBOB


;==============================================================================
; TilemapUpdateFriends  -  Per-frame dynamic friend animation & blit
;
; Sequence:
;   1. Advance animation timer and cycle jumping frames (0..3).
;   2. If friend has not been collected and is within visible camera window,
;      blit using sub-pixel shifter and cookie-cutter mask ($0FCA).
;
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

TilemapUpdateFriends:
    PUSHM       d0-d7/a0-a4

    move.w      ActiveFriendCount(a5),d7
    beq         .done_update_friends
    subq.w      #1,d7
    lea         ActiveFriends(a5),a4

.update_draw_loop:
    tst.w       Friend_Type(a4)
    beq         .next_update_draw

    tst.w       Friend_Collected(a4)
    beq.s       .not_collected

    ; Collected: if still drawn on screen, erase once from DisplayScreen
    tst.w       Friend_Drawn(a4)
    beq.s       .next_update_draw
    bsr         TilemapEraseFriend
    clr.w       Friend_Drawn(a4)
    bra.s       .next_update_draw

.not_collected:
    ; Viewport Y culling: check if friend is in active display rows
    move.w      Friend_Y(a4),d1
    cmp.w       CameraCullTopY(a5),d1
    blt.s       .friend_offscreen
    cmp.w       CameraCullBottomY(a5),d1
    ble.s       .friend_on_screen

.friend_offscreen:
    ; Offscreen: if still drawn on screen from previous viewport, erase once
    tst.w       Friend_Drawn(a4)
    beq.s       .next_update_draw
    bsr         TilemapEraseFriend
    clr.w       Friend_Drawn(a4)
    bra.s       .next_update_draw

.friend_on_screen:
    ; Step 1: Advance Jumping Animation (every FRIEND_ANIM_SPEED frames)
    addq.w      #1,Friend_AnimTimer(a4)
    cmp.w       #FRIEND_ANIM_SPEED,Friend_AnimTimer(a4)
    blt.s       .check_drawn
    clr.w       Friend_AnimTimer(a4)
    addq.w      #1,Friend_AnimFrame(a4)
    andi.w      #3,Friend_AnimFrame(a4)
    ; Animation frame changed: erase old frame before drawing new frame
    tst.w       Friend_Drawn(a4)
    beq.s       .draw_current_friend
    bsr         TilemapEraseFriend
    clr.w       Friend_Drawn(a4)
    bra.s       .draw_current_friend

.check_drawn:
    ; Animation frame unchanged: if already sitting on DisplayScreen, skip!
    tst.w       Friend_Drawn(a4)
    bne.s       .next_update_draw

.draw_current_friend:
    bsr         TilemapDrawFriendSubPixel

.next_update_draw:
    lea         Friend_Sizeof(a4),a4
    dbra        d7,.update_draw_loop

.done_update_friends:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapDrawFriendSubPixel  -  Draw a friend via the shared sub-pixel BOB core
;
; Resolves the friend's mask/raw source frame, delegates the blit to
; TilemapDrawActorSubPixelBOB, then layers the foreground-tile stamp and
; water submersion tint on top.
;
; In: a4 = ActiveFriend pointer
; Destroys: d0-d5, a0-a3 (preserves d7)
;==============================================================================

TilemapDrawFriendSubPixel:
    move.w      Friend_X(a4),d0             ; 0..319
    move.w      Friend_Y(a4),d1             ; 0..671

    ; Source frame pointer in FriendSpritesRaw / FriendSpritesMsk:
    ; Source offset = (Type - 1) * FRIEND_ROW_STRIDE (512) + (AnimFrame * 2)
    move.w      Friend_Type(a4),d2
    subq.w      #1,d2                   ; 0-based sheet row
    mulu.w      #FRIEND_ROW_STRIDE,d2
    moveq       #0,d3
    move.w      Friend_AnimFrame(a4),d3
    add.w       d3,d3                   ; d3 = AnimFrame * 2 bytes
    add.l       d3,d2

    lea         FriendSpritesMsk,a0
    lea         FriendSpritesRaw,a1
    adda.l      d2,a0                   ; a0 = mask frame source
    adda.l      d2,a1                   ; a1 = raw graphic frame source

    moveq       #FRIEND_FRAME_HEIGHT,d5
    bsr         TilemapDrawActorSubPixelBOB
    tst.w       d4
    bne         .culled_friend

    move.w      d0,Friend_PrevX(a4)
    move.w      d1,Friend_PrevY(a4)
    move.w      #1,Friend_Drawn(a4)

    ; Foreground Layer Stamp (in front of Friend BOB)
    ; Check if any foreground tiles in LevelDef_ForegroundMap overlap friend bounding box
    bsr         TilemapStampForegroundOverFriend

    ; Submerge friend in DisplayScreen if water has reached it
    move.w      WaterPixelY(a5),d2      ; d2 = WaterPixelY
    bmi.s       .exit_draw              ; if no water (< 0), done
    movea.l     a2,a0                   ; a0 = destination in DisplayScreen
    move.w      d7,-(sp)                ; preserve caller's loop counter
    move.w      #FRIEND_FRAME_HEIGHT,d7 ; 16 scanlines
    bsr         TilemapSubmergeActor
    move.w      (sp)+,d7

.exit_draw:
    rts

.culled_friend:
    clr.w       Friend_Drawn(a4)
    rts


;==============================================================================
; TilemapRestorePlayerOverlaps  -  Re-blit entities wiped by player's wide erase
;
; Called in Early VBlank immediately after TilemapDrawPlayer.
; Re-blits any settled push blocks (crates), moving push blocks,
; pickups, or friends that occupied the background tiles
; restored by TilemapErasePlayer.
;
; In:  a5 = Variables base
;      a6 = CUSTOM chip base
; Preserves: all caller registers
;==============================================================================

TilemapRestorePlayerOverlaps:
    tst.w       Player_ErasedFlag(a5)
    beq         .rpo_exit

    clr.w       Player_ErasedFlag(a5)

    PUSHM       d2-d7/a2-a4
    subq.l      #8,sp                   ; allocate 8 bytes on stack for bounding box

    ; Calculate erased tile bounding box:
    ; (sp)   = start_col
    ; 2(sp)  = end_col
    ; 4(sp)  = start_row
    ; 6(sp)  = end_row

    move.w      Player_ErasedX(a5),d0
    lsr.w       #4,d0
    bpl.s       .scol_ok
    moveq       #0,d0
.scol_ok:
    move.w      d0,(sp)                 ; (sp) = start_col

    move.w      Player_ErasedX(a5),d0
    add.w       Player_ErasedSpan(a5),d0
    subq.w      #1,d0
    lsr.w       #4,d0                   ; end_col
    cmp.w       #TILEMAP_VIEW_COLS-1,d0
    ble.s       .ecol_ok
    move.w      #TILEMAP_VIEW_COLS-1,d0
.ecol_ok:
    move.w      d0,2(sp)                ; 2(sp) = end_col

    move.w      Player_ErasedY(a5),d1
    lsr.w       #4,d1                   ; start_row
    bpl.s       .srow_ok
    moveq       #0,d1
.srow_ok:
    move.w      d1,4(sp)                ; 4(sp) = start_row

    move.w      Player_ErasedY(a5),d1
    add.w       #PLAYER_HEIGHT-1,d1
    lsr.w       #4,d1                   ; end_row
    move.w      CurrentMapHeight(a5),d0
    subq.w      #1,d0                   ; d0 = last row of this level
    cmp.w       d0,d1
    ble.s       .erow_ok
    move.w      d0,d1
.erow_ok:
    move.w      d1,6(sp)                ; 6(sp) = end_row

    moveq       #0,d7                   ; d7 = flag (1 if any entity was restored)

    ; -------------------------------------------------------------------------
    ; 1. Check Push Blocks (Crates)
    ; -------------------------------------------------------------------------
    move.w      ActorCount(a5),d6
    beq         .rpo_check_pickup
    subq.w      #1,d6
    lea         ActorList(a5),a2
.rpo_crate_loop:
    move.l      (a2)+,a3
    tst.w       Actor_Status(a3)
    beq         .rpo_next_crate
    move.w      Actor_Type(a3),d0
    cmp.w       #BLOCK_PUSH,d0
    bne         .rpo_next_crate
.rpo_is_crate:
    tst.w       Actor_HasFalled(a3)
    bne         .rpo_falling_crate

    tst.w       Actor_HasMoved(a3)
    beq.s       .rpo_crate_static

    ; Moving crate (being pushed):
    move.w      Actor_Y(a3),d1
    cmp.w       4(sp),d1                ; < start_row?
    blt         .rpo_next_crate
    cmp.w       6(sp),d1                ; > end_row?
    bgt         .rpo_next_crate

    move.w      Actor_X(a3),d0
    cmp.w       (sp),d0                 ; >= start_col?
    blt.s       .rpo_check_prev_x
    cmp.w       2(sp),d0                ; <= end_col?
    ble.s       .rpo_draw_moving_crate
.rpo_check_prev_x:
    move.w      Actor_PrevX(a3),d0
    cmp.w       (sp),d0
    blt         .rpo_next_crate
    cmp.w       2(sp),d0
    bgt         .rpo_next_crate

.rpo_draw_moving_crate:
    bsr         DrawActor
    moveq       #1,d7
    bra         .rpo_next_crate

.rpo_falling_crate:
    ; Falling crate: drawn at PrevY*16 + YDec (YDec can pass whole tiles),
    ; covering one row, or two when not tile-aligned. If the player's erase
    ; touched it, redraw it now at that position; ActionFallActors moves it
    ; on later in the frame.
    move.w      Actor_YDec(a3),d1
    lsr.w       #4,d1
    add.w       Actor_PrevY(a3),d1      ; d1 = top row of the drawn crate
    cmp.w       6(sp),d1                ; top row > end_row?
    bgt         .rpo_next_crate
    move.w      Actor_YDec(a3),d0
    and.w       #15,d0
    beq.s       .rpo_fall_one_row
    addq.w      #1,d1                   ; spans the row below as well
.rpo_fall_one_row:
    cmp.w       4(sp),d1                ; bottom row < start_row?
    blt         .rpo_next_crate
    move.w      Actor_X(a3),d0
    cmp.w       (sp),d0                 ; < start_col?
    blt         .rpo_next_crate
    cmp.w       2(sp),d0                ; > end_col?
    bgt         .rpo_next_crate
    bra         .rpo_draw_moving_crate

.rpo_crate_static:
    move.w      Actor_Y(a3),d1
    cmp.w       4(sp),d1
    blt         .rpo_next_crate
    cmp.w       6(sp),d1
    bgt         .rpo_next_crate

    move.w      Actor_X(a3),d0
    cmp.w       (sp),d0
    blt         .rpo_next_crate
    cmp.w       2(sp),d0
    bgt         .rpo_next_crate

    ; Match! Blit settled crate
    move.w      Actor_SpriteOffset(a3),d0
    move.w      Actor_Y(a3),d2
    move.w      Actor_X(a3),d3
    bsr         TilemapBlitSingleTile

    move.w      Actor_X(a3),d0
    lsl.w       #4,d0
    move.w      Actor_Y(a3),d1
    lsl.w       #4,d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         TilemapSubmergeTile
    moveq       #1,d7

.rpo_next_crate:
    dbra        d6,.rpo_crate_loop

    ; -------------------------------------------------------------------------
    ; 2. Check Pickups
    ; -------------------------------------------------------------------------
.rpo_check_pickup:
    move.w      ActivePickupCount(a5),d6
    beq         .rpo_check_friends
    subq.w      #1,d6
    lea         ActivePickups(a5),a4
.rpo_pickup_loop:
    tst.w       Pickup_Collected(a4)
    bne         .rpo_next_pickup

    move.w      Pickup_Row(a4),d1
    cmp.w       4(sp),d1
    blt         .rpo_next_pickup
    cmp.w       6(sp),d1
    bgt         .rpo_next_pickup

    move.w      Pickup_Col(a4),d0
    cmp.w       (sp),d0
    blt         .rpo_next_pickup
    cmp.w       2(sp),d0
    bgt         .rpo_next_pickup

    ; Match! Blit pickup
    move.w      Pickup_TileId(a4),d0
    move.w      Pickup_Row(a4),d2
    move.w      Pickup_Col(a4),d3
    bsr         TilemapBlitSingleTile
    move.w      #1,Pickup_Drawn(a4)

    move.w      Pickup_X(a4),d0
    move.w      Pickup_Y(a4),d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox
    move.w      Pickup_Col(a4),d0
    move.w      Pickup_Row(a4),d1
    bsr         TilemapSubmergeTile
    moveq       #1,d7

.rpo_next_pickup:
    lea         Pickup_Sizeof(a4),a4
    dbra        d6,.rpo_pickup_loop

    ; -------------------------------------------------------------------------
    ; 3. Check Friends
    ; -------------------------------------------------------------------------
.rpo_check_friends:
    move.w      ActiveFriendCount(a5),d6
    beq         .rpo_done
    subq.w      #1,d6
    lea         ActiveFriends(a5),a4
.rpo_friend_loop:
    tst.w       Friend_Type(a4)
    beq         .rpo_next_friend
    tst.w       Friend_Collected(a4)
    bne         .rpo_next_friend

    move.w      Friend_Y(a4),d1
    lsr.w       #4,d1
    cmp.w       4(sp),d1
    blt         .rpo_next_friend
    cmp.w       6(sp),d1
    bgt         .rpo_next_friend

    move.w      Friend_X(a4),d0
    lsr.w       #4,d0
    cmp.w       (sp),d0
    blt         .rpo_next_friend
    cmp.w       2(sp),d0
    bgt         .rpo_next_friend

    ; Match! Blit friend
    bsr         TilemapDrawFriendSubPixel
    move.w      #1,Friend_Drawn(a4)
    moveq       #1,d7

.rpo_next_friend:
    lea         Friend_Sizeof(a4),a4
    dbra        d6,.rpo_friend_loop

.rpo_done:
    addq.l      #8,sp                   ; deallocate local stack bounding box
    POPM        d2-d7/a2-a4
.rpo_exit:
    rts


;==============================================================================
; TilemapStampForegroundOverFriend  -  Re-blit foreground tiles overlapping friend
;
; In:  d0.w = Friend World X (0..319)
;      d1.w = Friend World Y (0..671)
;      a5   = Variables base
;      a6   = CUSTOM
; Preserves: all caller registers (pushes d0-d7/a0-a4 in TilemapStampForegroundOverBox)
;==============================================================================
TilemapStampForegroundOverFriend:
    move.w      #FRIEND_FRAME_WIDTH,d2
    move.w      #FRIEND_FRAME_HEIGHT,d3
    bra         TilemapStampForegroundOverBox  ; bob_compositor.asm


;==============================================================================
; TilemapDrawPickups  -  Draw every uncollected pickup onto DisplayScreen
;
; Pickups are static, so each is blitted once when it comes into view and
; erased once when collected (Pickup_Drawn tracks which).
;
; In:  a5 = Variables base
;      a6 = CUSTOM chip base ($dff000)
; Preserves: a5, a6
;==============================================================================

TilemapDrawPickups:
    PUSHM       d0-d7/a0-a4

    move.w      ActivePickupCount(a5),d7
    beq         .done_draw_pickups
    subq.w      #1,d7
    lea         ActivePickups(a5),a4

.draw_loop:
    tst.w       Pickup_Collected(a4)
    beq.s       .not_collected

    ; Collected: if still drawn on DisplayScreen, erase it once
    tst.w       Pickup_Drawn(a4)
    beq         .next_draw
    move.w      Pickup_X(a4),d0
    move.w      Pickup_Y(a4),d1
    bsr         TilemapErase16x16Actor
    clr.w       Pickup_Drawn(a4)
    bra         .next_draw

.not_collected:
    ; Viewport Y culling: check if the pickup is within active display rows
    ; (TilemapScreenOffset - 1 <= Pickup_Row <= TilemapScreenOffset + 14)
    move.w      Pickup_Row(a4),d1
    move.w      TilemapScreenOffset(a5),d2
    subq.w      #1,d2
    cmp.w       d2,d1
    blt         .next_draw
    add.w       #15,d2
    cmp.w       d2,d1
    bgt         .next_draw

    ; Not collected & on-screen: if already drawn, skip (do not waste blits on static pickup)
    tst.w       Pickup_Drawn(a4)
    bne         .next_draw

    ; Blit tile at Pickup_Row, Pickup_Col
    move.w      Pickup_TileId(a4),d0
    move.w      Pickup_Row(a4),d2
    move.w      Pickup_Col(a4),d3
    bsr         TilemapBlitSingleTile
    move.w      #1,Pickup_Drawn(a4)

    ; Re-stamp foreground over the pickup tile
    move.w      Pickup_X(a4),d0
    move.w      Pickup_Y(a4),d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox

    ; Check water submersion (dither / wave if submerged)
    move.w      Pickup_Col(a4),d0
    move.w      Pickup_Row(a4),d1
    bsr         TilemapSubmergeTile

.next_draw:
    lea         Pickup_Sizeof(a4),a4
    dbra        d7,.draw_loop

.done_draw_pickups:
    POPM        d0-d7/a0-a4
    rts
