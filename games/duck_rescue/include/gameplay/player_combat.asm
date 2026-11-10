
;==============================================================================
; AMIGA GAME ENGINE
; player_combat.asm  -  Cane Attack & Enemy Collision
;==============================================================================
;
; Part of the player module (one of player_fsm/_combat/_water.asm; all follow the
; shared register convention).
;
;   PlayerStartAttack  - initiate cane swing attack animation
;   ActionAttack       - cane swing animation, multi-frame active hitbox FSM
;   PlayerCheckAttackHit - test cane strike hitbox against all active enemies;
;                         stuns enemies with dizzy stars for ENEMY_STUN_DURATION
;   PlayerCheckEnemies - test player body against enemies; safe passage through
;                         stunned enemies, lethal contact triggers death/collapse
;
; Register convention:
;   a4 = current (active) player structure
;   a5 = Variables base
;   a6 = $dff000 (CUSTOM chip base)
;==============================================================================


;==============================================================================
; PlayerStartAttack  -  Initiate cane swing attack animation
;
; In: a4 = Player struct pointer
;     a5 = Variables base
;
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
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
;
; Destroys: d0-d5/d7/a0-a1 (preserves everything else, including a5/a6)
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
; In:       a4 = Player struct pointer
;           a5 = Variables base
; Out:      none
; Destroys: none (preserves all registers)
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
    tst.w       Enemy_Type(a1)
    beq.s       .next_enemy_hit             ; inactive slot: skip

    ; If enemy is already stunned, do not re-trigger or extend stun timer
    tst.w       Enemy_StunTimer(a1)
    bne.s       .next_enemy_hit

    ; Viewport / tier vertical overlap early-out (Y test first):
    ; Overlap test Y: (Cane Top < Enemy Bottom) AND (Cane Bottom > Enemy Top)
    move.w      Enemy_Y(a1),d0                 ; Enemy Top
    move.w      d0,d1
    add.w       #16,d1                      ; Enemy Bottom = Enemy_Y + 16

    cmp.w       d1,d4
    bge.s       .next_enemy_hit             ; Cane Top >= Enemy Bottom -> no overlap
    cmp.w       d0,d5
    ble.s       .next_enemy_hit             ; Cane Bottom <= Enemy Top -> no overlap

    ; Enemy is within vertical cane sweep: test horizontal overlap
    ; Enemy bounding box: [Enemy_X .. Enemy_X + 16]
    move.w      Enemy_X(a1),d0                 ; Enemy Left
    move.w      d0,d1
    add.w       #16,d1                      ; Enemy Right = Enemy_X + 16

    ; Overlap test X: (Cane Left < Enemy Right) AND (Cane Right > Enemy Left)
    cmp.w       d1,d2
    bge.s       .next_enemy_hit             ; Cane Left >= Enemy Right -> no overlap
    cmp.w       d0,d3
    ble.s       .next_enemy_hit             ; Cane Right <= Enemy Left -> no overlap

    ; -------------------------------------------------------------------------
    ; Cane connected: stun the enemy
    ; -------------------------------------------------------------------------
    ; Sets stun timer to 200 frames (~4.0s PAL).
    ; While stunned, TilemapDrawEnemies renders orbiting dizzy stars,
    ; and PlayerCheckEnemies deactivates lethal collision (safe passage).
    move.w      #ENEMY_STUN_DURATION,Enemy_StunTimer(a1)
    bsr         AudioPlayEnemyStun

.next_enemy_hit:
    lea         Enemy_Sizeof(a1),a1            ; advance to next active enemy slot
    dbra        d7,.enemy_hit_loop

.done_attack_hit:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; PlayerCheckEnemies  -  Test player collision against all active enemies
;
; - If enemy is stunned (Enemy_StunTimer > 0): safe passage (ignored, no damage)
; - If enemy is active (Enemy_StunTimer == 0): lethal contact
;   Triggers ACTION_DEATH collapse animation and loss of life.
;
; In:       a5 = Variables base
; Out:      none
; Destroys: none (preserves all registers)
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
    tst.w       Enemy_Type(a1)
    beq.s       .next_contact

    ; Safe passage: a stunned enemy cannot hurt the player.
    ; Player can walk right through the enemy while dizzy stars orbit overhead.
    tst.w       Enemy_StunTimer(a1)
    bne.s       .next_contact

    ; Coarse vertical overlap early-out (rejects enemies on different scanline tiers):
    move.w      Enemy_Y(a1),d0
    add.w       #14,d0                      ; Enemy Bottom = Enemy_Y + 14
    cmp.w       d4,d0
    ble.s       .next_contact               ; Enemy Bottom <= Player Top: skip
    sub.w       #12,d0                      ; Enemy Top = Enemy_Y + 2
    cmp.w       d5,d0
    bge.s       .next_contact               ; Enemy Top >= Player Bottom: skip

    ; Active enemy in vertical range: test horizontal overlap
    move.w      Enemy_X(a1),d0
    addq.w      #2,d0                       ; Enemy Left  = Enemy_X + 2
    move.w      Enemy_X(a1),d1
    add.w       #14,d1                      ; Enemy Right = Enemy_X + 14

    cmp.w       d1,d2
    bge.s       .next_contact               ; Player Left >= Enemy Right
    cmp.w       d0,d3
    ble.s       .next_contact               ; Player Right <= Enemy Left

    ; -------------------------------------------------------------------------
    ; Lethal contact: start the player's death sequence
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
    lea         Enemy_Sizeof(a1),a1
    dbra        d7,.enemy_contact_loop

.done_check_enemies:
    movem.l     (sp)+,d2-d7/a1/a4
    rts
