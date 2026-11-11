;==============================================================================
; MEADOW RUN - THE PLAYER
; player.asm  -  Mia: input, running, jumping, collisions, drawing
;==============================================================================


;==============================================================================
; PlayerReset  -  Mia at the level's start, standing still
;==============================================================================

PlayerReset:
    move.l     LevelDefPtr(a5),a0
    move.w     LevelDef_StartX(a0),PlrX(a5)
    move.w     LevelDef_StartY(a0),d0
    lsl.w      #4,d0
    move.w     d0,PlrY16(a5)
    clr.w      PlrVY(a5)
    clr.w      PlrOnGround(a5)
    clr.w      PlrFacing(a5)
    clr.w      PlrRunning(a5)
    clr.w      PlrDeadTimer(a5)
    move.w     #1,JumpPrev(a5)         ; a held jump key does not jump at once
    rts

;==============================================================================
; PlayerRespawn  -  Back to the start after falling in the water
;
; The countdown keeps running: falling in costs time, not the level.
;==============================================================================

PlayerRespawn:
    move.w     #DMAF_RASTER,DMACON(a6) ; the camera jumps: hide the redraw
    bsr        PlayerErase
    bsr        PlayerReset
    bsr        CameraFollow            ; redraws all 23 columns
    bsr        PlayerDraw
    move.w     #DMAF_SETCLR|DMAF_RASTER,DMACON(a6)
    rts

;==============================================================================
; CameraFollow  -  Centre the view on Mia (HsSetCamera clamps it to the map)
;==============================================================================

CameraFollow:
    move.w     PlrX(a5),d0
    sub.w      #HS_VIEW_WIDTH/2-8,d0
    bra        HsSetCamera

;==============================================================================
; PlayerLogic  -  Run, jump, fall, and what Mia touches
;
; Positions are whole pixels across and sixteenths of a pixel down
; (PlrY16), so the jump arc is smooth with integer maths only. Collisions
; read the level's collision map (LevelGame) at a few points of her
; 12 x 20 body box, which is inset in the 24 x 24 sprite (Section 29.4).
;
; Destroys: d0-d7, a0-a1
;==============================================================================

PlayerLogic:
    bsr        ReadPlayerInput         ; d5 = held directions, d3 = jump held

    ; --- Run --------------------------------------------------------------
    moveq      #0,d4                   ; d4 = horizontal step
    btst       #CONTROLB_LEFT,d5
    beq.s      .no_left
    moveq      #-RUN_SPEED,d4
    move.w     #1,PlrFacing(a5)
.no_left:
    btst       #CONTROLB_RIGHT,d5
    beq.s      .no_right
    moveq      #RUN_SPEED,d4
    clr.w      PlrFacing(a5)
.no_right:
    clr.w      PlrRunning(a5)
    tst.w      d4
    beq.s      .no_step
    move.w     #1,PlrRunning(a5)
    move.w     PlrX(a5),d6
    add.w      d4,d6                   ; d6 = new X
    move.w     d6,d0
    addq.w     #2,d0                   ; leading edge: left side of the body...
    tst.w      d4
    bmi.s      .edge
    add.w      #11,d0                  ; ...or its right side (X + 13)
.edge:
    move.w     PlrY16(a5),d1
    asr.w      #4,d1
    addq.w     #4,d1                   ; top of the body
    moveq      #3-1,d7                 ; test 3 points down that edge
.edge_loop:
    bsr        TileClassAt
    cmp.w      #CLASS_SOLID,d2
    beq.s      .no_step                ; a wall: stay put
    add.w      #9,d1
    dbra       d7,.edge_loop
    cmp.w      #4,d6                   ; and stay inside the map
    blt.s      .no_step
    cmp.w      #HS_MAP_COLS*16-20,d6
    bgt.s      .no_step
    move.w     d6,PlrX(a5)
.no_step:

    ; --- Jump, on the frame the button goes down ------------------------
    move.w     JumpPrev(a5),d2
    move.w     d3,JumpPrev(a5)
    tst.w      d3
    beq.s      .no_jump
    tst.w      d2                      ; held since last frame: not a new press
    bne.s      .no_jump
    tst.w      PlrOnGround(a5)
    beq.s      .no_jump
    move.w     #-JUMP_SPEED,PlrVY(a5)
    clr.w      PlrOnGround(a5)
    PLAYSFX    SfxJump
.no_jump:

    ; --- Gravity ------------------------------------------------------------
    move.w     PlrVY(a5),d3
    addq.w     #GRAVITY,d3
    cmp.w      #MAX_FALL,d3
    ble.s      .speed_ok
    move.w     #MAX_FALL,d3
.speed_ok:
    move.w     d3,PlrVY(a5)
    move.w     PlrY16(a5),d7
    add.w      d3,d7                   ; d7 = new Y x16
    move.w     d7,d6
    asr.w      #4,d6                   ; d6 = new Y in pixels
    tst.w      d3
    bmi.s      .rising

    ; Falling or standing: is there ground just under her feet?
    move.w     d6,d1
    add.w      #24,d1                  ; the line below the sprite
    bsr        FeetOrHeadSolid
    beq.s      .in_air
    and.w      #$fff0,d1               ; top of that tile
    sub.w      #24,d1                  ; stand on it
    lsl.w      #4,d1
    move.w     d1,PlrY16(a5)
    clr.w      PlrVY(a5)
    move.w     #1,PlrOnGround(a5)
    bra.s      .moved
.rising:
    move.w     d6,d1
    addq.w     #4,d1                   ; top of the body
    bsr        FeetOrHeadSolid
    beq.s      .in_air
    lsr.w      #4,d1                   ; bumped her head: just below that tile
    addq.w     #1,d1
    lsl.w      #4,d1
    subq.w     #4,d1
    lsl.w      #4,d1
    move.w     d1,PlrY16(a5)
    clr.w      PlrVY(a5)
    clr.w      PlrOnGround(a5)
    bra.s      .moved
.in_air:
    move.w     d7,PlrY16(a5)
    clr.w      PlrOnGround(a5)
.moved:

    ; --- What she touches: two points down the middle of her body -----------
    move.w     PlrY16(a5),d1
    asr.w      #4,d1
    cmp.w      #HS_LINES,d1            ; fell off the bottom of the map
    bge.s      .die
    add.w      #12,d1
    bsr.s      .touch
    add.w      #8,d1
    bsr.s      .touch
    rts

; One point: X + 8, Y = d1. Called with bsr, so a hit drops that return.
.touch:
    move.w     PlrX(a5),d0
    addq.w     #8,d0
    bsr        TileClassAt
    cmp.w      #CLASS_HAZARD,d2
    beq.s      .die_here
    cmp.w      #CLASS_GOAL,d2
    beq.s      .goal
    cmp.w      #CLASS_DUCK,d2
    bne.s      .touch_done
    bra        CollectDuck             ; returns to .touch's caller

.die_here:
    addq.l     #4,sp                   ; drop .touch's return: end PlayerLogic
.die:
    move.w     #DEAD_FRAMES,PlrDeadTimer(a5)
    PLAYSFX    SfxDie
.touch_done:
    rts

.goal:
    addq.l     #4,sp
    move.w     #GOAL_FRAMES,GoalTimer(a5)
    move.w     DuckCount(a5),d0        ; the most ducklings yet?
    cmp.w      BestDucks(a5),d0
    bls.s      .goal_sfx
    move.w     d0,BestDucks(a5)
    move.w     #1,NewBest(a5)          ; GoalFlash flashes the counter
.goal_sfx:
    PLAYSFX    SfxGoal
    rts

;------------------------------------------------------------------------------
; ReadPlayerInput  -  What the player is pressing
; Out: d5 = ControlsHold bits (CONTROLB_LEFT / _RIGHT ...)
;      d3 = 1 if a jump control is held: up, joystick fire or Space
; Destroys: a0
;------------------------------------------------------------------------------
ReadPlayerInput:
    IFD MEADOW_AUTOPLAY
    bra        AutoplayInput           ; test builds: scripted input instead
    ENDC
    move.b     ControlsHold(a5),d5
    moveq      #0,d3
    btst       #CONTROLB_UP,d5
    beq.s      .no_up
    moveq      #1,d3
.no_up:
    btst       #7,CIAA_BASE            ; joystick fire, active low
    bne.s      .no_fire
    moveq      #1,d3
.no_fire:
    lea        Keys,a0
    tst.b      KEY_SPACE(a0)
    beq.s      .no_space
    moveq      #1,d3
.no_space:
    rts

    IFD MEADOW_AUTOPLAY
;------------------------------------------------------------------------------
; AutoplayInput  -  Test builds only: replay AutoplayScript, one entry per
; run of frames (frame count, then bit 0 = right, bit 1 = jump, bit 2 =
; left). After the last entry, nothing is pressed. tools/check_level.py
; --script prints a script that finishes the level.
;------------------------------------------------------------------------------
AutoplayInput:
    moveq      #0,d5
    moveq      #0,d3
    lea        AutoplayScript,a0
    move.w     AutoplayStep(a5),d0
    lsl.w      #2,d0
    adda.w     d0,a0
    move.w     (a0)+,d0                ; frames in this entry (0 = end)
    beq.s      .done
    move.w     (a0),d1                 ; buttons
    btst       #0,d1
    beq.s      .no_r
    bset       #CONTROLB_RIGHT,d5
.no_r:
    btst       #2,d1
    beq.s      .no_l
    bset       #CONTROLB_LEFT,d5
.no_l:
    btst       #1,d1
    beq.s      .no_j
    moveq      #1,d3
.no_j:
    addq.w     #1,AutoplayFrame(a5)
    cmp.w      AutoplayFrame(a5),d0
    bgt.s      .done
    clr.w      AutoplayFrame(a5)
    addq.w     #1,AutoplayStep(a5)
.done:
    rts
    ENDC

;------------------------------------------------------------------------------
; FeetOrHeadSolid  -  Is line d1 solid under either side of her body?
; In: d1 = world Y to test. Tests X + 3 and X + 12.
; Out: Z clear (bne) if either point is solid. Preserves d1.
;------------------------------------------------------------------------------
FeetOrHeadSolid:
    move.w     PlrX(a5),d0
    addq.w     #3,d0
    bsr.s      TileClassAt
    cmp.w      #CLASS_SOLID,d2
    beq.s      .solid
    add.w      #9,d0
    bsr.s      TileClassAt
    cmp.w      #CLASS_SOLID,d2
    beq.s      .solid
    moveq      #0,d2                   ; Z set: nothing solid
    rts
.solid:
    moveq      #1,d2                   ; Z clear
    rts

;------------------------------------------------------------------------------
; TileClassAt  -  Collision class of the cell under a world pixel
; In: d0 = X, d1 = Y. Out: d2 = CLASS_*. Outside the map's sides is solid,
; above or below it is empty. Preserves everything else.
;------------------------------------------------------------------------------
TileClassAt:
    movem.l    d3/a0,-(sp)
    moveq      #CLASS_SOLID,d2
    tst.w      d0
    bmi.s      .done
    cmp.w      #HS_MAP_COLS*16,d0
    bge.s      .done
    moveq      #CLASS_EMPTY,d2
    tst.w      d1
    bmi.s      .done
    cmp.w      #HS_LINES,d1
    bge.s      .done
    move.w     d1,d2
    lsr.w      #4,d2
    lsl.w      #7,d2                   ; row * 128 (HS_MAP_COLS)
    move.w     d0,d3
    lsr.w      #4,d3
    add.w      d3,d2
    lea        LevelGame(a5),a0
    move.b     (a0,d2.w),d2
    ext.w      d2
.done:
    movem.l    (sp)+,d3/a0
    rts

;==============================================================================
; PlayerErase / PlayerDraw  -  Mia's BOB, through hscroll.asm
;
; PlayerDraw also stamps the foreground layer over her, so she passes
; behind bushes and stones (HsStampFront).
;==============================================================================

PlayerErase:
    tst.w      PlrDrawn(a5)
    beq.s      .done
    movem.l    d0-d4,-(sp)
    move.w     PlrDrawX(a5),d0
    move.w     PlrDrawY(a5),d1
    moveq      #MIA_HEIGHT,d2
    moveq      #MIA_CELL_WORDS,d4
    bsr        HsEraseBob
    clr.w      PlrDrawn(a5)
    movem.l    (sp)+,d0-d4
.done:
    rts

PlayerDraw:
    movem.l    d0-d4/a0-a1,-(sp)
    addq.w     #1,PlrAnim(a5)
    move.w     PlrAnim(a5),d1

    ; Pick a frame: row 0 idle, 1 walk, 3 death, 5 falling (Section 29.1)
    moveq      #13,d0                  ; collapsed
    tst.w      PlrDeadTimer(a5)
    bne.s      .frame
    moveq      #20,d0                  ; in the air: the flailing row
    lsr.w      #2,d1
    tst.w      PlrOnGround(a5)
    beq.s      .cycle
    moveq      #4,d0                   ; walking
    tst.w      PlrRunning(a5)
    bne.s      .cycle
    moveq      #0,d0                   ; standing: a slow idle cycle
    lsr.w      #2,d1
.cycle:
    and.w      #3,d1
    add.w      d1,d0
.frame:
    ; Frame f is at (f / 4) * one row of frames + (f & 3) * 4 bytes
    move.w     d0,d1
    and.w      #3,d1
    add.w      d1,d1
    add.w      d1,d1
    lsr.w      #2,d0
    mulu       #MIA_FRAME_ROW,d0
    add.w      d1,d0
    lea        PlayerRightRaw,a0
    lea        PlayerRightMsk,a1
    tst.w      PlrFacing(a5)
    beq.s      .right
    lea        PlayerLeftRaw,a0
    lea        PlayerLeftMsk,a1
.right:
    adda.w     d0,a0
    adda.w     d0,a1

    move.w     PlrX(a5),d0
    subq.w     #4,d0                   ; centre the 24-pixel sprite on the body
    move.w     PlrY16(a5),d1
    asr.w      #4,d1
    bmi.s      .off                    ; above the map
    cmp.w      #HS_LINES-MIA_HEIGHT,d1
    bgt.s      .off                    ; fallen below it
    moveq      #MIA_HEIGHT,d2
    moveq      #MIA_SHEET_BYTES,d3
    moveq      #MIA_CELL_WORDS,d4
    bsr        HsDrawBob
    move.w     d0,PlrDrawX(a5)
    move.w     d1,PlrDrawY(a5)
    move.w     #1,PlrDrawn(a5)
    moveq      #32,d2                  ; the cells her 24 x 24 sprite covers
    moveq      #MIA_HEIGHT,d3
    bsr        HsStampFront            ; foreground back on top
.off:
    movem.l    (sp)+,d0-d4/a0-a1
    rts
