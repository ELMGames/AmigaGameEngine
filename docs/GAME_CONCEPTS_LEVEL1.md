# Reactor Breach: Level 1 Updates & Technical Implementation Specification

**Document Version:** 1.0  
**Target Platform:** Commodore Amiga 500 (OCS/ECS, 512 KB Chip + 512 KB Fast/Slow RAM, Motorola 68000 @ 7.09 MHz)  
**Output Executable:** `../uae/dh0/main`  

---

## 1. Executive Summary

This document details the source code changes across five major subsystem updates implementing the **Reactor Breach** vertical escape game loop and Level 1 blueprint as specified in [`GAME_CONCEPT.md`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/GAME_CONCEPT.md).

The five updates span player agility, real-time Copper hardware effects, creature lethality, non-linear environmental objectives, and level toolchain authoring:
1. **Update 1: 1-Tile Hazard Jump (`ACTION_JUMP`)** — Directional leap over hazards (`BLOCK_ACID`, gaps).
2. **Update 2: Rising Toxic Coolant Flood & Dynamic Copper Split** — Vertical mission timer with zero-CPU raster split.
3. **Update 3: Enemy Collision Lethality & Jump Apex Evasion** — Active patrol collision with airborne evasion.
4. **Update 4: Sector Override Switches, Airlock Exit Hatch & Lifecycle** — Interactive triggers, state mask, and victory sequence.
5. **Update 5: Exporter Pipeline & Level 1 Blueprint Authoring** — TMX extraction and Level 1 assembly generation.

---

## 2. Update 1: 1-Tile Hazard Jump (`ACTION_JUMP`)

### Objective
Enable the player to execute a 1-tile leap across hazardous floor hazards (`BLOCK_ACID`, 1-tile pits, or floor gaps) using `Fire + Left/Right` (or `Fire` facing direction) while stationary on solid ground.

### Source Changes

#### 1. [`include/resources/const.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/const.asm#L684)
Added state constant `ACTION_JUMP = 6`:
```assembly
ACTION_IDLE         = 0
ACTION_MOVE         = 1
ACTION_FALL         = 2
ACTION_PLAYERPUSH   = 3
ACTION_INTRO        = 4     ; level intro star animation
ACTION_SWITCH       = 5     ; player switch star animation
ACTION_JUMP         = 6     ; 1-tile hazard hop (Reactor Breach)
```

#### 2. [`include/resources/variables.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/variables.asm#L446-L448)
Allocated jumping runtime registers in BSS:
```assembly
PlayerIsJumping:      rs.w    1               ; 1 = jump in progress, 0 = normal
PlayerJumpStep:       rs.w    1               ; current frame step in jump (0..15)
PlayerJumpDir:        rs.w    1               ; jump direction (+1 or -1)
```

#### 3. [`include/resources/player.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/player.asm#L225)
Added `ActionJump-.i` to the `PlayerLogic` jump table:
```assembly
PlayerLogic:
    move.w      ActionStatus(a5),d0     ; load current action state
    JMPINDEX    d0                      ; dispatch through jump table

.i  ; jump offset table
    dc.w        ActionIdle-.i           ; state 0: idle
    dc.w        ActionMove-.i           ; state 1: moving
    dc.w        ActionFall-.i           ; state 2: falling
    dc.w        ActionPlayerPush-.i     ; state 3: push animation
    dc.w        ActionIntro-.i          ; state 4: level intro star animation
    dc.w        ActionIntro-.i          ; state 5: player switch star animation
    dc.w        ActionJump-.i           ; state 6: 1-tile hazard jump (Reactor Breach)
```

#### 4. [`include/resources/player.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/player.asm#L1701-L1728)
Intercepted `Fire` button press in `ActionIdle` to trigger jump logic:
```assembly
    btst        #CONTROLB_FIRE,ControlsTrigger(a5)  ; FIRE button just pressed?
    beq.s       .no_fire

    ; Check if Left or Right is being held for 1-tile hazard jump
    btst        #CONTROLB_LEFT,ControlsHold(a5)
    bne.s       .jump_left
    btst        #CONTROLB_RIGHT,ControlsHold(a5)
    bne.s       .jump_right

    ; If neither is held, check player's facing direction:
    move.w      Player_Facing(a4),d0
    tst.w       d0
    bmi.s       .jump_left
    bgt.s       .jump_right

    ; If single player level or no direction, switch active player
    bra         PlayerSwitch

.jump_left:
    moveq       #-1,d0
    bsr         PlayerTryJump
    rts

.jump_right:
    moveq       #1,d0
    bsr         PlayerTryJump
    rts
```

#### 5. [`include/resources/player.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/player.asm#L1745-L1865)
Implemented `PlayerTryJump` (validation & commitment) and `ActionJump` (16-frame parabolic motion & landing):
```assembly
;==============================================================================
; PlayerTryJump  -  Attempt a 1-tile horizontal hazard jump
;
; In:  d0 = jump direction (-1 = left, +1 = right)
;      a4 = active player structure pointer
;==============================================================================

PlayerTryJump:
    ; Cannot jump while on a ladder
    move.w      Player_Y(a4),d1
    mulu.w      CurrentMapWidth(a5),d1
    add.w       Player_X(a4),d1         ; d1 = current cell offset
    lea         GameMap(a5),a0
    move.b      (a0,d1.w),d2
    cmp.b       #BLOCK_LADDER,d2
    beq         .jump_blocked
    cmp.b       #BLOCK_MILLIELADDER,d2
    beq         .jump_blocked
    cmp.b       #BLOCK_MOLLYLADDER,d2
    beq         .jump_blocked

    ; Calculate target column = Player_X + 2 * Direction
    move.w      Player_X(a4),d1
    add.w       d0,d1
    add.w       d0,d1                   ; d1 = target column
    bmi         .jump_blocked
    cmp.w       CurrentMapWidth(a5),d1
    bge         .jump_blocked

    ; Calculate intermediate column = Player_X + Direction
    move.w      Player_X(a4),d2
    add.w       d0,d2

    ; Check if intermediate or target cells are solid walls / obstacles
    move.w      Player_Y(a4),d3
    mulu.w      CurrentMapWidth(a5),d3

    move.w      d3,d4
    add.w       d2,d4                   ; intermediate cell offset
    cmp.b       #BLOCK_SOLID,(a0,d4.w)
    beq         .jump_blocked           ; cannot jump through a solid wall!
    cmp.b       #BLOCK_PUSH,(a0,d4.w)
    beq         .jump_blocked           ; cannot jump through a push block!
    cmp.b       #BLOCK_DIRT,(a0,d4.w)
    beq         .jump_blocked
    cmp.b       #BLOCK_COCOON,(a0,d4.w)
    beq         .jump_blocked

    move.w      d3,d4
    add.w       d1,d4                   ; target cell offset
    cmp.b       #BLOCK_SOLID,(a0,d4.w)
    beq         .jump_blocked           ; cannot land inside a solid wall!
    cmp.b       #BLOCK_PUSH,(a0,d4.w)
    beq         .jump_blocked           ; cannot land inside a push block!
    cmp.b       #BLOCK_DIRT,(a0,d4.w)
    beq         .jump_blocked
    cmp.b       #BLOCK_COCOON,(a0,d4.w)
    beq         .jump_blocked
    cmp.b       #BLOCK_ACID,(a0,d4.w)
    beq         .jump_blocked           ; cannot land inside an acid pool!

    ; --- Jump Approved! ---
    move.w      #1,PlayerMoved(a5)
    move.w      #1,PlayerIsJumping(a5)
    clr.w       PlayerJumpStep(a5)
    move.w      d0,PlayerJumpDir(a5)
    move.w      d0,Player_Facing(a4)
    move.w      d0,Player_DirectionX(a4)
    clr.w       Player_DirectionY(a4)

    move.w      d1,Player_NextX(a4)     ; target X
    move.w      Player_Y(a4),Player_NextY(a4) ; target Y (same row)

    move.w      #ACTION_JUMP,ActionStatus(a5)
    move.w      #16,Player_ActionCount(a4) ; 16 frames of jump

    clr.w       Player_XDec(a4)
    clr.w       Player_YDec(a4)
    rts

.jump_blocked:
    rts


;==============================================================================
; ActionJump  -  1-Tile Horizontal Hazard Jump (ACTION_JUMP state)
;
; Moves 32 pixels horizontally across 16 frames (2 pixels per frame).
; Applies parabolic arc to Player_YDec from JumpArcTable (0 -> -8 -> 0).
;==============================================================================

ActionJump:
    ; Frame step 0..15
    move.w      PlayerJumpStep(a5),d0
    addq.w      #1,PlayerJumpStep(a5)

    ; Horizontal translation: 2 pixels per frame in PlayerJumpDir
    move.w      PlayerJumpDir(a5),d1
    add.w       d1,d1                   ; d1 = 2 * dir (+2 or -2)
    add.w       d1,Player_XDec(a4)

    ; Parabolic vertical arc from table
    lea         JumpArcTable,a0
    move.w      d0,d2
    add.w       d2,d2                   ; word offset
    move.w      (a0,d2.w),Player_YDec(a4)

    ; Update sprite animation
    bsr         PlayerShowWalkAnim

    subq.w      #1,Player_ActionCount(a4)
    bne.s       .exit                   ; still in mid-air!

    ; --- Jump Complete (Landed!) ---
    clr.w       ActionStatus(a5)        ; return to IDLE
    clr.w       PlayerIsJumping(a5)
    clr.w       Player_XDec(a4)
    clr.w       Player_YDec(a4)

    ; Update GameMap: clear old tile, write to target tile
    bsr         PlayerMoveLogic
    bsr         PlayerFallLogic         ; check if landing cell has no floor -> fall!
    bsr         ActorFallAll

    tst.w       ActionStatus(a5)
    bne.s       .exit
    bsr         TakeSnapshot            ; snapshot undo state

.exit:
    rts

JumpArcTable:
    dc.w    0, -2, -4, -6, -7, -8, -8, -8, -8, -8, -7, -6, -4, -2, -1, 0
```

---

## 3. Update 2: Rising Toxic Coolant Flood & Dynamic Copper Split

### Objective
Create a visual and lethal rising environmental flood that acts as the mission timer. The flood rises up the screen and rewrites Amiga background palette registers in real-time via the Copper raster list.

### Source Changes

#### 1. [`include/resources/const.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/const.asm#L689)
Defined speed constant:
```assembly
RADIATION_DEFAULT_SPEED = 6     ; frames per pixel rise (lower = faster)
```

#### 2. [`include/resources/variables.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/variables.asm#L436-L439)
Allocated radiation state variables:
```assembly
RadiationY:           rs.w    1               ; radiation flood line in world pixels (0..672)
RadiationTimer:       rs.w    1               ; frame tick countdown to next rise step
RadiationActive:      rs.w    1               ; 1 = active, 0 = disabled
RadiationSpeed:       rs.w    1               ; frames per pixel rise
```

#### 3. [`include/resources/tilemap.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/tilemap.asm#L845-L918)
Hooked into `TilemapUpdateCopperSky` and added `TilemapApplyRadiationCopper`:
```assembly
    ; Apply rising radiation flood split if active
    bsr         TilemapApplyRadiationCopper
    rts

;==============================================================================
; TilemapApplyRadiationCopper  -  Real-time Copper Split for Rising Coolant Flood
;
; Computes screen scanline: FloodLine = RadiationY - TilemapCameraY.
; If FloodLine < 216, rewrites cpGameSky entries from FloodLine to 215 with
; a glowing, pulsing radioactive green coolant gradient and surface foam.
;==============================================================================

TilemapApplyRadiationCopper:
    tst.w       RadiationActive(a5)
    beq.s       .done

    move.w      RadiationY(a5),d0
    sub.w       TilemapCameraY(a5),d0   ; d0 = screen scanline of flood surface (0..215)
    cmp.w       #216,d0
    bge.s       .done                   ; flood is below bottom of visible screen

    ; Clamp start line at 0 (if entire screen is submerged)
    move.w      d0,d1                   ; d1 = start line
    bpl.s       .d1_ok
    clr.w       d1
.d1_ok:

    ; Pulse phase based on TickCounter (0..7)
    move.w      TickCounter(a5),d2
    lsr.w       #2,d2
    andi.w      #7,d2

    lea         cpGameSky+6,a1
    lea         RadiationGlowTable,a2
    move.w      d1,d3                   ; current line

.line_loop:
    cmp.w       #216,d3
    bge.s       .done

    ; Calculate pointer offset in cpGameSky
    move.w      d3,d4
    lsl.w       #3,d4                   ; d4 = line * 8
    cmp.w       #212,d3
    blt.s       .no_wait_adjust
    addq.w      #4,d4                   ; skip $FFDF crossing WAIT
.no_wait_adjust:

    ; Color selection:
    ; If this is the exact surface line (d3 == d0), draw frothing surface foam!
    cmp.w       d0,d3
    bne.s       .submerged_line
    move.w      #$05fa,(a1,d4.w)        ; bright cyan/white radioactive foam
    bra.s       .next_line

.submerged_line:
    ; Submerged scanline: pick glowing green from table based on (d3 + phase) & 7
    move.w      d3,d5
    add.w       d2,d5
    andi.w      #7,d5
    add.w       d5,d5                   ; word index
    move.w      (a2,d5.w),(a1,d4.w)

.next_line:
    addq.w      #1,d3
    bra.s       .line_loop

.done:
    rts

RadiationGlowTable:
    dc.w    $0140, $0251, $0362, $0473, $0382, $0271, $0160, $0150
```

#### 4. [`include/resources/gamestatus.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/gamestatus.asm#L259-L351)
Integrated `RadiationTick` in `GameRun` and implemented suit breach collision:
```assembly
; In GameRun:
    bsr         RadiationTick        ; update rising radiation flood and check player breach

;==============================================================================
; RadiationTick  -  Update rising coolant flood & check player breach
;==============================================================================

RadiationTick:
    tst.w       RadiationActive(a5)
    beq.s       .done

    ; Increment frame counter
    addq.w      #1,RadiationTimer(a5)
    move.w      RadiationSpeed(a5),d0
    cmp.w       RadiationTimer(a5),d0
    bgt.s       .check_player
    clr.w       RadiationTimer(a5)

    ; Radiation rises! Decrement world Y
    subq.w      #1,RadiationY(a5)
    bgt.s       .check_player
    clr.w       RadiationY(a5)          ; clamp at top

.check_player:
    ; Calculate Player World Y feet position:
    ; PlayerFeetY = Player_Y * 16 + Player_YDec + 12
    move.l      PlayerPtrs(a5),a4
    move.w      Player_Y(a4),d0
    lsl.w       #4,d0
    add.w       Player_YDec(a4),d0
    add.w       #12,d0                  ; player's feet
    cmp.w       RadiationY(a5),d0
    blt.s       .done                   ; above radiation -> safe!

    ; Radiation breached suit!
    bsr         PlayerDie

.done:
    rts
```

---

## 4. Update 3: Enemy Lethality & Jump Apex Evasion

### Objective
Ensure patrolling organisms are lethal on touch, triggering suit breach and level reset, while allowing skilled players to leap over creatures by bypassing collision detection when at the apex of a jump.

### Source Changes

#### 1. [`include/resources/gamestatus.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/gamestatus.asm#L260)
Called `CheckPlayerEnemyCollisions` in `GameRun`:
```assembly
    bsr         CheckPlayerEnemyCollisions ; check player sprite vs active enemy patrols
```

#### 2. [`include/resources/gamestatus.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/gamestatus.asm#L357-L414)
Implemented `CheckPlayerEnemyCollisions` with 12px bounding-box test and apex exemption:
```assembly
;==============================================================================
; CheckPlayerEnemyCollisions  -  Bounding-box check between player and enemies
;==============================================================================

CheckPlayerEnemyCollisions:
    move.w      ActiveEnemyCount(a5),d7
    beq.s       .done
    subq.w      #1,d7

    ; If player is jumping at apex, bypass ground enemy collision
    tst.w       PlayerIsJumping(a5)
    beq.s       .get_player_pos
    move.w      PlayerJumpStep(a5),d0
    cmp.w       #4,d0
    blt.s       .get_player_pos
    cmp.w       #12,d0
    ble.s       .done                   ; airborne at apex: clear of ground hazards!

.get_player_pos:
    move.l      PlayerPtrs(a5),a4
    move.w      Player_X(a4),d0
    lsl.w       #4,d0
    add.w       Player_XDec(a4),d0      ; d0 = PlayerWorldX

    move.w      Player_Y(a4),d1
    lsl.w       #4,d1
    add.w       Player_YDec(a4),d1      ; d1 = PlayerWorldY

    lea         ActiveEnemies(a5),a0
.loop:
    tst.w       ei_Type(a0)
    beq.s       .next

    ; Test dx = abs(PlayerWorldX - ei_X)
    move.w      d0,d2
    sub.w       ei_X(a0),d2
    bpl.s       .dx_pos
    neg.w       d2
.dx_pos:
    cmp.w       #12,d2
    bge.s       .next

    ; Test dy = abs(PlayerWorldY - ei_Y)
    move.w      d1,d3
    sub.w       ei_Y(a0),d3
    bpl.s       .dy_pos
    neg.w       d3
.dy_pos:
    cmp.w       #12,d3
    bge.s       .next

    ; Creature contact!
    bsr         PlayerDie
    bra.s       .done

.next:
    lea         ei_SIZEOF(a0),a0
    dbra        d7,.loop

.done:
    rts
```

#### 3. [`include/resources/gamestatus.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/gamestatus.asm#L495-L500)
Implemented `PlayerDie` routine with VHS tape distortion rewind:
```assembly
;==============================================================================
; PlayerDie  -  Handle player suit breach / death
;==============================================================================

PlayerDie:
    bsr         VHS_StartEffect
    move.w      #LEVEL_INIT,GameStatus(a5)
    rts
```

---

## 5. Update 4: Sector Override Switches, Airlock Hatch & Lifecycle

### Objective
Provide multi-objective level progression: the player must seek and activate sector switches during the vertical climb to unseal the extraction airlock hatch at the top.

### Source Changes

#### 1. [`include/resources/const.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/const.asm#L687-L688)
Defined trigger IDs:
```assembly
TRIGGER_TYPE_EXIT       = 99    ; Level exit airlock / hatch
TRIGGER_TYPE_SWITCH     = 1     ; Base switch trigger ID
```

#### 2. [`include/resources/variables.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/variables.asm#L440-L445)
Allocated objective tracking state in BSS:
```assembly
SwitchesTotal:        rs.w    1               ; total switches in level
SwitchesRemaining:    rs.w    1               ; unactivated switches remaining
SwitchesActivatedMask: rs.w   1               ; bitmask of activated switch IDs
ExitHatchOpen:        rs.w    1               ; 1 = unlocked, 0 = sealed
ExitHatchCol:         rs.w    1               ; exit hatch tile X
ExitHatchRow:         rs.w    1               ; exit hatch tile Y
```

#### 3. [`include/resources/levelutils.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/levelutils.asm#L207)
Hooked `LevelInitReactorBreach` in `LevelInit`:
```assembly
    bsr           InitGameObjects        ; create actors for all game objects in map
    bsr           LevelInitEnemies       ; populate ActiveEnemies table from LevelDef
    bsr           LevelInitReactorBreach ; initialize rising radiation, switches, hatch
```

#### 4. [`include/resources/levelutils.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/levelutils.asm#L1453-L1533)
Implemented `LevelInitReactorBreach` to dynamically scan `LevelDef_TriggerList`:
```assembly
;==============================================================================
; LevelInitReactorBreach  -  Initialize rising radiation and switch/hatch state
;==============================================================================

LevelInitReactorBreach:
    PUSHM       d0-d4/a0-a2

    ; Initialize jumping state
    clr.w       PlayerIsJumping(a5)
    clr.w       PlayerJumpStep(a5)
    clr.w       PlayerJumpDir(a5)

    ; Calculate initial RadiationY at bottom of map
    move.w      CurrentMapHeight(a5),d0
    lsl.w       #4,d0                   ; d0 = map height in pixels (e.g. 672)
    move.w      d0,RadiationY(a5)
    clr.w       RadiationTimer(a5)
    move.w      #RADIATION_DEFAULT_SPEED,RadiationSpeed(a5)
    move.w      #1,RadiationActive(a5)

    ; Clear switch activation bitmask & state
    clr.w       SwitchesActivatedMask(a5)
    clr.w       SwitchesTotal(a5)
    clr.w       SwitchesRemaining(a5)
    clr.w       ExitHatchOpen(a5)
    clr.w       ExitHatchCol(a5)
    clr.w       ExitHatchRow(a5)

    ; Check if CurrentLevelDef has TriggerList
    move.l      CurrentLevelDef(a5),d0
    beq.s       .no_triggers
    movea.l     d0,a2
    move.l      LevelDef_TriggerList(a2),d0
    beq.s       .no_triggers
    movea.l     d0,a0                   ; a0 -> TriggerList

    clr.w       d1                      ; d1 = switch count

.scan_loop:
    move.w      (a0)+,d2                ; Trigger ID
    cmp.w       #$ffff,d2
    beq.s       .scan_done

    move.w      (a0)+,d3                ; Left
    move.w      (a0)+,d4                ; Top
    addq.l      #4,a0                   ; skip Right and Bottom

    cmp.w       #TRIGGER_TYPE_EXIT,d2
    beq.s       .found_exit

    ; It's a switch
    addq.w      #1,d1
    bra.s       .scan_loop

.found_exit:
    ; Record exit hatch tile coordinates
    lsr.w       #4,d3                   ; Left / 16 = Col
    lsr.w       #4,d4                   ; Top / 16 = Row
    move.w      d3,ExitHatchCol(a5)
    move.w      d4,ExitHatchRow(a5)
    bra.s       .scan_loop

.scan_done:
    move.w      d1,SwitchesTotal(a5)
    move.w      d1,SwitchesRemaining(a5)
    bne.s       .done                   ; switches exist, hatch remains sealed

.no_triggers:
    ; No switches in this level: hatch starts open
    move.w      #1,ExitHatchOpen(a5)

.done:
    POPM        d0-d4/a0-a2
    rts
```

#### 5. [`include/resources/gamestatus.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/gamestatus.asm#L420-L490)
Implemented `CheckTriggers` with non-destructive bitmask tracking:
```assembly
;==============================================================================
; CheckTriggers  -  Check override switches and airlock exit hatch
;==============================================================================

CheckTriggers:
    move.l      CurrentLevelDef(a5),d0
    beq         .done
    movea.l     d0,a2
    move.l      LevelDef_TriggerList(a2),d0
    beq         .done
    movea.l     d0,a0                   ; a0 -> TriggerList

    ; Calculate Player center point
    move.l      PlayerPtrs(a5),a4
    move.w      Player_X(a4),d0
    lsl.w       #4,d0
    add.w       Player_XDec(a4),d0
    addq.w      #8,d0                   ; d0 = PlayerCenterX

    move.w      Player_Y(a4),d1
    lsl.w       #4,d1
    add.w       Player_YDec(a4),d1
    addq.w      #8,d1                   ; d1 = PlayerCenterY

.loop:
    move.w      (a0)+,d2                ; d2 = Trigger ID
    cmp.w       #$ffff,d2
    beq.s       .done

    move.w      (a0)+,d3                ; Left
    move.w      (a0)+,d4                ; Top
    move.w      (a0)+,d5                ; Right
    move.w      (a0)+,d6                ; Bottom

    cmp.w       d3,d0
    blt.s       .loop
    cmp.w       d5,d0
    bgt.s       .loop
    cmp.w       d4,d1
    blt.s       .loop
    cmp.w       d6,d1
    bgt.s       .loop

    ; Player inside trigger box!
    cmp.w       #TRIGGER_TYPE_EXIT,d2
    beq.s       .is_exit

    ; It's an Override Switch!
    ; Check if this switch was already flipped (using bitmask)
    move.w      SwitchesActivatedMask(a5),d7
    btst        d2,d7
    bne.s       .loop                   ; already flipped!

    bset        d2,d7
    move.w      d7,SwitchesActivatedMask(a5)
    subq.w      #1,SwitchesRemaining(a5)
    bgt.s       .switch_chime

    ; All switches active! Airlock unsealed!
    clr.w       SwitchesRemaining(a5)
    move.w      #1,ExitHatchOpen(a5)
    move.w      #$0fff,cpPal+2          ; power flash

.switch_chime:
    bra.s       .loop

.is_exit:
    tst.w       ExitHatchOpen(a5)
    beq.s       .loop                   ; hatch is still sealed!

    ; Airlock reached! Complete Level!
    move.w      #LEVEL_COMPLETE_SETUP,GameStatus(a5)

.done:
    rts
```

---

## 6. Update 5: Exporter Pipeline & Level 1 Blueprint Authoring

### Objective
Update the level compilation script [`tools/export_level.py`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/tools/export_level.py) to automatically recognize switches and exit hatches from TMX maps, and author Level 1 in [`assets/Levels/Level_01.tmx`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/assets/Levels/Level_01.tmx).

### Source Changes

#### 1. [`tools/export_level.py`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/tools/export_level.py#L630-L652)
Updated object parsing in TMX extractor:
```python
            # Identify Triggers (Switches, Exit Airlock, Doors)
            elif (
                "trigger" in tag or "exit" in tag or "door" in tag or "boss" in tag or
                "hatch" in tag or "switch" in tag or "terminal" in tag or "console" in tag or
                "trigger" in name_lower or "exit" in name_lower or "hatch" in name_lower or
                "switch" in name_lower or "terminal" in name_lower or "console" in name_lower
            ):
                is_exit = ("exit" in tag or "exit" in name_lower or "hatch" in tag or "hatch" in name_lower)
                if is_exit:
                    default_id = 99  # TRIGGER_TYPE_EXIT
                else:
                    # Sequential switch ID: 1, 2, ...
                    default_id = len([t for t in triggers if t["id"] != 99]) + 1

                trig_id = int(props.get("trigger_id", props.get("id", default_id)))
                target = props.get("target", "")
                tw = max(16.0, w)
                th = max(16.0, h)
                triggers.append({
                    "id": trig_id,
                    "left": int(round(x)),
                    "top": int(round(y)),
                    "right": int(round(x + tw)),
                    "bottom": int(round(y + th)),
                    "target": target
                })
                kind = "Exit Hatch" if trig_id == 99 else f"Switch #{trig_id}"
                print(f"      -> Trigger ({kind}): id={trig_id} bounds=({x},{y})-({x+tw},{y+th}) target='{target}'")
```

#### 2. [`assets/Levels/Level_01.tmx`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/assets/Levels/Level_01.tmx#L70-L100)
Authored Level 1 vertical ascent elements:
```xml
  <!-- Spawn on Row 32 / Stand on Row 31 -->
  <object id="2" name="PLAYER" type="PLAYER" x="24" y="512">
   <properties><property name="direction" type="int" value="1"/></properties>
   <point/>
  </object>

  <!-- Left Platform (Cols 1..3, Row 32) -->
  <object id="9" name="PLATFORM_LEFT" type="SOLID" x="16" y="512" width="48" height="16"/>

  <!-- 1-Tile Toxic Hazard / Gap to Jump (Col 4, Row 32) -->
  <object id="30" name="TOXIC_SPILL" type="ACID" x="64" y="512" width="16" height="16"/>

  <!-- Right Platform (Cols 5..11, Row 32) -->
  <object id="8" name="PLATFORM_RIGHT" type="SOLID" x="80" y="512" width="112" height="16"/>

  <!-- Pushable Drum (Col 7, Row 31) -->
  <object id="31" name="PUSH_DRUM" type="PUSH" x="112" y="496" width="16" height="16"/>

  <!-- Lower Sector Override Switch 1 (Platform 17, Row 24 / Y=384) -->
  <object id="32" name="SWITCH_1" type="SWITCH" x="144" y="384" width="16" height="16"/>

  <!-- Upper Sector Override Switch 2 (Platform 23, Row 8 / Y=128) -->
  <object id="33" name="SWITCH_2" type="SWITCH" x="176" y="128" width="16" height="16"/>

  <!-- Evacuation Airlock Hatch (Summit Platform 27, Row 1 / Y=16) -->
  <object id="34" name="EXIT_HATCH" type="EXIT" x="176" y="16" width="32" height="16"/>
```

#### Generated Output: [`include/resources/level_01_entities.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/level_01_entities.asm#L98-L117)
```assembly
;------------------------------------------------------------------------------
; Triggers & Level Event Zones
; Format: TriggerID (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_01_TriggerCount:    dc.w    3
Level_01_TriggerList:
    dc.w    1, 144, 384, 160, 400
    dc.w    2, 176, 128, 192, 144
    dc.w    99, 176, 16, 208, 32
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Hazard Zones
; Format: Damage (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_01_HazardCount:     dc.w    1
Level_01_HazardList:
    dc.w    1, 64, 512, 80, 528
    dc.w    $ffff                       ; End of list marker
```

---

## 7. Master File Summary

| File | Subsystem | Changes Summary |
|---|---|---|
| [`include/resources/const.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/const.asm) | Constants | Added `ACTION_JUMP`, `TRIGGER_TYPE_EXIT`, `TRIGGER_TYPE_SWITCH`, `RADIATION_DEFAULT_SPEED`. |
| [`include/resources/variables.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/variables.asm) | BSS / RAM | Added `RadiationY/Timer/Active/Speed`, `SwitchesTotal/Remaining/Mask`, `ExitHatchOpen/Col/Row`, `PlayerIsJumping/Step/Dir`. |
| [`include/resources/player.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/player.asm) | Player Engine | Added `ActionJump` dispatch to `PlayerLogic`, `Fire` input intercept, `PlayerTryJump` validation, and 16-frame parabolic `ActionJump`. |
| [`include/resources/tilemap.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/tilemap.asm) | Copper & Visuals | Implemented `TilemapApplyRadiationCopper`, dynamic scanline recalculation, green coolant gradient, and cyan froth line. |
| [`include/resources/gamestatus.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/gamestatus.asm) | Game Loop | Added `RadiationTick`, `CheckPlayerEnemyCollisions`, `CheckTriggers` with bitmask flip, and `PlayerDie` VHS rewind restart. |
| [`include/resources/levelutils.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/levelutils.asm) | Level Engine | Added `LevelInitReactorBreach` call and definition (radiation reset to $Y=672$, trigger list scan, hatch init). |
| [`tools/export_level.py`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/tools/export_level.py) | Exporter Tool | Added classification of switches (IDs 1..N), exit hatches (ID 99), and minimum $16\times 16$ trigger bounds. |
| [`assets/Levels/Level_01.tmx`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/assets/Levels/Level_01.tmx) | Level Data | Authored Level 1 with 1-tile toxic waste gap, push drum, 2 sector switches, and airlock exit hatch. |

---

## 8. Build Verification

Build command:
```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

Verification output:
```
== Exporting Tiled Levels ==
[*] Processing Tiled TMX: Level_01.tmx
      -> Hazard: dmg=1 bounds=(64.0,512.0)-(80.0,528.0)
      -> Push Block: Cols [7..7], Rows [31..31]
      -> Trigger (Switch #1): id=1 bounds=(144.0,384.0)-(160.0,400.0)
      -> Trigger (Switch #2): id=2 bounds=(176.0,128.0)-(192.0,144.0)
      -> Trigger (Exit Hatch): id=99 bounds=(176.0,16.0)-(208.0,32.0)
[*] Done! Level Level_01 successfully exported.
== Assembling main.asm ==
main(acrx2):	       40102 bytes
mem_fast(aurw1):	       54300 bytes
data_fast(adrw2):	       39632 bytes
data_overlay_src(adrw1):	           0 bytes
data_chip(adrw2):	      231104 bytes
mem_chip(aurw1):	      273156 bytes
== Linking ../uae/dh0/main ==
== OK: ../uae/dh0/main ==
```
Final linked Amiga binary created: `../uae/dh0/main` (553,928 bytes).
