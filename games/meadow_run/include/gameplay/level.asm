;==============================================================================
; MEADOW RUN - THE LEVEL
; level.asm  -  Starting a level, the countdown, the ducklings
;==============================================================================


;==============================================================================
; LevelStart  -  (Re)start the level from its LevelDef and draw the view
;
; The platform layer and the collision map are copied to RAM, because
; collecting a duckling changes them; the background and foreground layers are
; used where they were assembled.
;==============================================================================

LevelStart:
    move.w     #DMAF_RASTER,DMACON(a6) ; hide the drawing: COLOR00 only

    move.l     #Level_01_Def,LevelDefPtr(a5)
    move.l     LevelDefPtr(a5),a2

    movea.l    LevelDef_Platform(a2),a0 ; live copies of the platform layer...
    lea        LevelMid(a5),a1
    move.w     #HS_MAP_ROWS*HS_MAP_COLS/2-1,d7
.copy_mid:
    move.l     (a0)+,(a1)+
    dbra       d7,.copy_mid
    movea.l    LevelDef_GameMap(a2),a0 ; ...and of the collision map
    lea        LevelGame(a5),a1
    move.w     #HS_MAP_ROWS*HS_MAP_COLS/4-1,d7
.copy_game:
    move.l     (a0)+,(a1)+
    dbra       d7,.copy_game

    move.l     LevelDef_Background(a2),HsMapBack(a5)
    lea        LevelMid(a5),a0
    move.l     a0,HsMapMid(a5)
    move.l     LevelDef_Foreground(a2),HsMapFront(a5)
    move.w     #DUCK_TILE,HsAnimFirst(a5)  ; every duckling moves together
    move.w     #DUCK_FRAMES,HsAnimFrames(a5)
    clr.w      HsAnimPhase(a5)
    move.w     #DUCK_FRAME_TICKS,DuckTick(a5)

    move.w     LevelDef_TimeLimit(a2),TimeLeft(a5)
    move.w     #TICKS_PER_SECOND,TimeTicks(a5)
    clr.w      DuckCount(a5)
    clr.w      NewBest(a5)
    move.w     #DUCK_COLOUR,GameCopperDuckColour+2
    clr.w      TimeUp(a5)
    clr.w      GoalTimer(a5)
    clr.w      PlrDrawn(a5)
    move.w     #1,HudDirty(a5)

    bsr        PlayerReset
    move.w     PlrX(a5),d0
    sub.w      #HS_VIEW_WIDTH/2-8,d0
    bsr        HsInit                  ; draws the view around the camera
    bsr        PlayerDraw
    bsr        HudUpdate
    move.w     #1,LevelReady(a5)
    move.w     #DMAF_SETCLR|DMAF_RASTER,DMACON(a6)
    rts

;==============================================================================
; CollectDuck  -  Take the duckling under a world pixel
;
; Clears the cell in the live platform layer and the collision map, redraws
; it (HsRedrawCell), and counts it.
;
; In:       d0.w = world X, d1.w = world Y of a point inside the duckling's cell
; Destroys: d2, a0 (preserves d0/d1)
;==============================================================================

CollectDuck:
    movem.l    d0-d1,-(sp)
    lsr.w      #4,d0                   ; column
    lsr.w      #4,d1                   ; row
    move.w     d1,d2
    lsl.w      #7,d2                   ; row * 128 (HS_MAP_COLS)
    add.w      d0,d2
    lea        LevelGame(a5),a0
    move.b     #CLASS_EMPTY,(a0,d2.w)
    add.w      d2,d2
    lea        LevelMid(a5),a0
    clr.w      (a0,d2.w)
    bsr        HsRedrawCell
    addq.w     #1,DuckCount(a5)
    move.w     #1,HudDirty(a5)
    PLAYSFX    SfxDuck
    movem.l    (sp)+,d0-d1
    rts

;==============================================================================
; LevelTick  -  The countdown and the ducklings' animation, once per playing frame
;
; The countdown is to Meadow Run what the rising water is to Duck Rescue:
; the pressure. Reaching zero ends the run; the death pause that follows
; restarts the whole level (TimeUp). The timer counts logic ticks, so it
; runs at the same real speed on PAL and NTSC (Section 19.3).
;==============================================================================

LevelTick:
    ; --- Countdown -----------------------------------------------------
    IFD AUTOPLAY_NO_TIMEOUT
    bra.s      .no_second              ; test builds: hold the clock
    ENDC
    subq.w     #1,TimeTicks(a5)
    bne.s      .no_second
    move.w     #TICKS_PER_SECOND,TimeTicks(a5)
    move.w     #1,HudDirty(a5)
    subq.w     #1,TimeLeft(a5)
    bne.s      .no_second
    move.w     #1,TimeUp(a5)           ; out of time
    move.w     #DEAD_FRAMES,PlrDeadTimer(a5)
    PLAYSFX    SfxDie
.no_second:

    ; --- The last seconds: the timer flashes red twice a second ----------
    move.w     #TIMER_COLOUR,d0
    cmp.w      #TIMER_WARNING,TimeLeft(a5)
    bgt.s      .colour
    cmp.w      #TICKS_PER_SECOND/2,TimeTicks(a5)
    blt.s      .colour
    move.w     #TIMER_WARN_COLOUR,d0
.colour:
    move.w     d0,GameCopperTimerColour+2

    ; --- Ducklings step to their next frame every DUCK_FRAME_TICKS frames -
    subq.w     #1,DuckTick(a5)
    bne.s      .done
    move.w     #DUCK_FRAME_TICKS,DuckTick(a5)
    move.w     HsAnimPhase(a5),d0
    addq.w     #1,d0
    cmp.w      #DUCK_FRAMES,d0
    blt.s      .phase
    moveq      #0,d0
.phase:
    bsr        HsAnimate               ; redraws the ducklings near the camera
.done:
    rts

;==============================================================================
; GoalFlash  -  During the pause at the signpost: flash the duckling counter
;               if this run brought the most ducklings yet (NewBest)
;
; The aim of Meadow Run is to reach the signpost in time with as many
; ducklings as possible; PlayerLogic's .goal keeps the best in BestDucks.
; COLOR21 colours both the icon and the count, so both flash, every 8 frames.
;
; Destroys: d0
;==============================================================================

GoalFlash:
    move.w     #DUCK_COLOUR,d0
    tst.w      NewBest(a5)
    beq.s      .set
    btst       #3,GoalTimer+1(a5)      ; the timer's bit 3: 8 frames on, 8 off
    beq.s      .set
    move.w     #BEST_FLASH_COLOUR,d0
.set:
    move.w     d0,GameCopperDuckColour+2
    rts
