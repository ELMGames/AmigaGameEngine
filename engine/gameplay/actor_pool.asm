;==============================================================================
; AMIGA GAME ENGINE - ENTITY POOLING & SORTING SUBSYSTEM
; actor_pool.asm  -  Actor Lifecycle, O(n) Counting Sort, and Dirty Batching
;==============================================================================

; MAX_MAP_HEIGHT, SORT_COUNT_BYTES and MAX_ACTIVE_CRATES come from engine_const.i.

;==============================================================================
; GetActorSlot  -  Allocate and initialise the next free actor slot
;
; In:  d1.w = tile column, d2.w = tile row, d3.w = actor type
;      a0   = GameMap pointer (preserved across the call)
; Out: a3  -> the new Actor (X/Y, PrevX/PrevY, Type, PixelX/PixelY set;
;             Status = 1, Dirty = 1, CanFall = 0); ActorCount incremented and
;             the pointer appended to ActorList via ActorSlotPtr.
;
; Halts in ActorPoolOverflow (red screen) when the pool is full.
;
; Destroys: d0/d5/a3 (preserves everything else, including a5/a6)
;==============================================================================

GetActorSlot:
    move.w      ActorCount(a5),d5          ; d5 = current count (= index of new slot)
    IFD MAX_ACTORS
    cmp.w       #MAX_ACTORS,d5             ; pool full?
    ELSE
    cmp.w       #MAX_ACTIVE_CRATES,d5      ; pool full?
    ENDC
    bcc         ActorPoolOverflow         ; if count >= max, fatal error

    addq.w      #1,ActorCount(a5)          ; increment actor count

    ; Calculate address of new slot: &Actors + d5 * Actor_Sizeof
    lea         Actors(a5),a3
    mulu        #Actor_Sizeof,d5
    add.l       d5,a3                      ; a3 -> new actor structure

    ; Initialise core fields
    move.w      d1,Actor_X(a3)             ; tile column
    move.w      d2,Actor_Y(a3)             ; tile row
    move.w      d1,Actor_PrevX(a3)         ; initial prev column = current column
    move.w      d2,Actor_PrevY(a3)         ; initial prev row = current row
    move.w      d3,Actor_Type(a3)          ; block type

    ; Cache pixel positions
    move.w      d1,d0
    IFD TILE_GRID_SIZE
    mulu.w      #TILE_GRID_SIZE,d0
    ELSE
    lsl.w       #4,d0                      ; d0 = X * 16
    ENDC
    move.w      d0,Actor_PixelX(a3)

    move.w      d2,d0
    IFD TILE_GRID_SIZE
    mulu.w      #TILE_GRID_SIZE,d0
    ELSE
    lsl.w       #4,d0                      ; d0 = Y * 16
    ENDC
    move.w      d0,Actor_PixelY(a3)

    move.w      #1,Actor_Status(a3)        ; status = alive
    move.w      #1,Actor_Dirty(a3)         ; needs initial draw
    clr.w       Actor_CanFall(a3)          ; default: not subject to gravity

    ; Add pointer to sorted actor list
    PUSH        a0                         ; preserve GameMap pointer
    move.l      ActorSlotPtr(a5),a0        ; a0 -> next free slot in ActorList
    move.l      a3,(a0)+                   ; store actor pointer and advance
    move.l      a0,ActorSlotPtr(a5)        ; update write cursor
    POP         a0                         ; restore GameMap pointer
    rts


;==============================================================================
; ActorPoolOverflow  -  Fatal error: actor pool has been exhausted
;
; Should never be reached in normal play (MAX_ACTIVE_CRATES = 16,
; peak campaign crate count across Levels 1-6 is 2 in Levels 3 & 4).
; Paints COLOR00 solid red and prints a diagnostic string to DisplayScreen,
; then halts.
;
; Destroys: d2/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

ActorPoolOverflow:
    move.w      #$0f00,CUSTOM+COLOR00      ; solid red (absolute address; a6 may be stale)
    lea         DisplayScreen+(4*LOADING_ROW_BYTES)+2,a1
    lea         .msg,a0
    bsr         CharBltString
.halt
    bra.s       .halt
.msg
    dc.b        "ACTOR OVERFLOW",0
    even


;==============================================================================
; DrawStaticActors  -  Blit all active actors into DisplayScreen
;
; Iterates ActorList (live actors only, Y-sorted) and calls PasteTile to
; blit each actor's sprite tile onto DisplayScreen at its current pixel
; position.  Actors with Actor_Dirty=0 are skipped (tile already correct).
;
; "Static" actors (push blocks) are drawn here during level init and
; remain until explicitly cleared by RestoreBackgroundTile.
; Moving actors (enemies) are also blitted here when they arrive at a new tile.
;
; On entry:
;   a5 = Variables base
;   a6 = CUSTOM (needed by PasteTile's WAITBLIT macro)
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
;==============================================================================

DrawStaticActors:
    move.w      ActorCount(a5),d7
    bne.s       .go
    rts

.go:
    subq.w      #1,d7
    lea         ActorList(a5),a2

.loop:
    move.l      (a2)+,a3                   ; a3 -> actor struct (live, via ActorList)
    tst.w       Actor_Status(a3)
    beq.s       .next
    tst.w       Actor_Dirty(a3)
    beq.s       .next

    bsr         ActorDrawStatic

.next:
    dbra        d7,.loop
    rts


;==============================================================================
; MarkAllActorsDirty  -  Mark every live actor as needing redraw
;
; Sets Actor_Dirty=1 for all slots 0..ActorCount-1.  Call before DrawStaticActors
; whenever the display may have been partially cleared (e.g. after a star-trail
; cleanup or after screen-buffer restoration) so that DrawStaticActors redraws
; everything rather than skipping actors it thinks are already displayed.
;
; Destroys: d7/a2-a3 (preserves everything else, including a5/a6)
;==============================================================================

MarkAllActorsDirty:
    move.w      ActorCount(a5),d7
    beq         .done
    subq.w      #1,d7
    lea         ActorList(a5),a2
.loop
    move.l      (a2)+,a3
    move.w      #1,Actor_Dirty(a3)
    dbra        d7,.loop
.done
    rts


;==============================================================================
; ActorsSavePos  -  Save each actor's current position as its previous position
;
; Called at the start of each action frame (from ActionIdle).  Copies Actor_X
; to Actor_PrevX and Actor_Y to Actor_PrevY for all live actors, and clears
; Actor_HasMoved so that movement detection is fresh for this frame.
;
; Uses the sorted ActorList for iteration (consistent order with rendering).
;
; Destroys: d7/a2-a3 (preserves everything else, including a5/a6)
;==============================================================================

ActorsSavePos:
    move.w      ActorCount(a5),d7
    bne.s       .go
    rts

.go:
    subq.w      #1,d7
    lea         ActorList(a5),a2           ; a2 -> sorted pointer array

.loop:
    move.l      (a2)+,a3                   ; a3 -> next actor struct (via sorted list)
    tst.w       Actor_HasFalled(a3)        ; mid-fall? preserve PrevY as the fall origin!
    bne.s       .skip_fall
    tst.w       Actor_ImpactTick(a3)       ; impact smoke active? preserve PrevY!
    bne.s       .skip_fall

    move.w      Actor_X(a3),Actor_PrevX(a3)    ; save X
    move.w      Actor_Y(a3),Actor_PrevY(a3)    ; save Y
    clr.w       Actor_HasMoved(a3)             ; clear moved flag
.skip_fall:
    dbra        d7,.loop
    rts




;==============================================================================
; ClearMovedActors  -  Erase moved actors from their previous tile positions
;
; Any actor that has Actor_HasMoved set (was repositioned this frame) needs to
; be erased from its old screen position before being redrawn at the new one.
; This is done by blitting the corresponding tile from NonDisplayScreen over the
; old position in DisplayScreen.
;
; Destroys: d0-d2/d7/a0-a3 (preserves everything else, including a5/a6)
;==============================================================================

ClearMovedActors:
    move.w      ActorCount(a5),d7
    bne         .go
    rts

.go
    subq.w      #1,d7
    lea         ActorList(a5),a2

.loop
    move.l      (a2)+,a3                   ; a3 -> actor struct (live, via ActorList)
    tst.w       Actor_HasMoved(a3)
    beq         .next

    move.w      Actor_PrevX(a3),d0
    move.w      Actor_PrevY(a3),d1
    bsr         RestoreBackgroundTile
    move.w      #1,Actor_Dirty(a3)         ; flag for redraw by DrawStaticActors

.next
    dbra        d7,.loop
    rts


;==============================================================================
; CleanActors  -  Remove dead actors from the ActorList and update ActorCount
;
; After players destroy actors (PlayerKillActor), their
; Actor_Status is set to 0.  This routine compacts the ActorList by removing
; those zero-status pointers and updating ActorCount to the new live count.
;
; Uses a two-pointer approach: reads from a0, writes to a1 (both start at
; the same ActorList base; a1 only advances for live actors).
;
; Destroys: d6-d7/a0-a1/a3 (preserves everything else, including a5/a6)
;==============================================================================

CleanActors:
    move.w      ActorCount(a5),d7
    subq.w      #1,d7
    bmi         .exit                      ; no actors at all - nothing to do

    moveq       #0,d6                      ; d6 = new live actor count
    lea         ActorList(a5),a0           ; read pointer
    move.l      a0,a1                      ; write pointer (compacted list)

.loop
    move.l      (a0)+,a3                   ; a3 -> next actor
    tst.w       Actor_Status(a3)           ; alive?
    beq         .next                      ; dead - skip (don't copy to output)

    move.l      a3,(a1)+                   ; copy live actor pointer to compacted list
    addq.w      #1,d6                      ; increment live count

.next
    dbra        d7,.loop

    move.w      d6,ActorCount(a5)          ; update count to reflect removals

.exit
    rts


;==============================================================================
; SortActors  -  O(n) counting sort of ActorList by Y position (descending)
;
; Sorts ActorList so actors with larger Y (bottom of screen) appear earlier
; and are iterated first.  This matches ActorFallAll's requirement: process
; bottom rows before top rows so a falling actor clears its GameMap cell
; before the actor above it is checked in the same pass.
;
; Y values are bounded to 0..MAX_MAP_HEIGHT-1, giving MAX_MAP_HEIGHT
; buckets.  Three passes over ActorList (O(n)) replace the old O(n²) bubble
; sort.  Scratch space: MAX_MAP_HEIGHT-word count/offset array on the stack + ActorSortBuf
; in the Variables block.
;
; ActorSlotPtr is NOT used as the end sentinel (CleanActors does not update
; it); the loop count is derived from ActorCount.
;
; Destroys: d0-d1/d6-d7/a0-a3 (preserves everything else, including a5/a6)
;==============================================================================

SortActors:
    move.w      ActorCount(a5),d7
    subq.w      #1,d7
    bmi         .exit                      ; 0 actors

    ; Allocate count[0..MAX_MAP_HEIGHT-1] on stack (SORT_COUNT_BYTES) and zero it
    lea         -SORT_COUNT_BYTES(sp),sp
    movea.l     sp,a1                      ; a1 = &count[0]
    movea.l     a1,a0
    move.w      #MAX_MAP_HEIGHT-1,d6
.zero
    clr.w       (a0)+
    dbra        d6,.zero

    ; Pass 1: tally actors per Y row
    lea         ActorList(a5),a0
    move.w      d7,d6
.count_pass
    move.l      (a0)+,a3
    move.w      Actor_Y(a3),d0
    add.w       d0,d0                      ; d0 = word byte-offset into count[]
    addq.w      #1,(a1,d0.w)              ; count[Y]++
    dbra        d6,.count_pass

    ; Pass 2: prefix sum descending - count[] becomes starting slot-index per Y.
    ; Iterate from Y=MAX_MAP_HEIGHT-1 down to Y=0 so the highest Y values occupy the first slots.
    lea         (MAX_MAP_HEIGHT-1)*2(a1),a0  ; a0 -> count[MAX_MAP_HEIGHT-1]
    moveq       #0,d0                      ; running total
    move.w      #MAX_MAP_HEIGHT-1,d6
.prefix
    move.w      (a0),d1                    ; d1 = count[Y]
    move.w      d0,(a0)                    ; offset[Y] = running total
    subq.l      #2,a0                      ; step backward to count[Y-1]
    add.w       d1,d0                      ; running total += count[Y]
    dbra        d6,.prefix

    ; Pass 3: scatter actors into ActorSortBuf at their Y-group slot
    lea         ActorSortBuf(a5),a2        ; a2 = scratch buffer base
    lea         ActorList(a5),a0
    move.w      d7,d6
.scatter
    move.l      (a0)+,a3
    move.w      Actor_Y(a3),d0
    add.w       d0,d0                      ; word byte-offset into offset[]
    move.w      (a1,d0.w),d1              ; d1.w = current slot index for Y
    addq.w      #1,(a1,d0.w)              ; offset[Y]++
    lsl.w       #2,d1                      ; slot index -> byte offset (×4)
    move.l      a3,(a2,d1.w)             ; ActorSortBuf[offset] = actor ptr
    dbra        d6,.scatter

    ; Copy ActorSortBuf -> ActorList
    lea         ActorList(a5),a0
    lea         ActorSortBuf(a5),a2
    move.w      d7,d6
.copy
    move.l      (a2)+,(a0)+
    dbra        d6,.copy

    lea         SORT_COUNT_BYTES(sp),sp    ; release stack count[]

.exit
    rts


;==============================================================================
; AnimateEnemies  -  Cycle enemy tile animation frames (called every VBlank)
;
; Enemies (BLOCK_ENEMYFALL and BLOCK_ENEMYFLOAT) have four tile frames each
; (A..D).  This routine advances the displayed frame every ENEMY_ANIM_TICKS
; VBlanks (16 ticks ≈ 3fps on PAL 50Hz).  ENEMY_ANIM_TICKS must be a power
; of 2; the boundary is detected with a single AND rather than divu.
;
; All living enemies animate in sync using:
;   frame_index = (TickCounter >> 4) & 3
;
; Actors that are currently falling (Actor_HasFalled) or playing an impact
; smoke animation (Actor_ImpactTick) are skipped — their rendering is owned
; by ActionFallActors for that period.
;
; Per animated actor:
;   1. Update Actor_SpriteOffset to the new frame tile index.
;   2. RestoreBackgroundTile  - restore background from NonDisplayScreen.
;   3. ActorDrawStatic        - blit new tile into DisplayScreen.
;      (PasteTile now saves/restores a2 internally; no wrapper PUSHM needed.)
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
;==============================================================================

AnimateEnemies:
    IFD HAS_TILEMAP_CAMERA
    move.w      TickCounter(a5),d0
    move.w      d0,d1
    and.w       #ENEMY_ANIM_TICKS-1,d0     ; d0 = tick mod ENEMY_ANIM_TICKS (power-of-2 mask)
    bne         .exit                       ; not an animation tick boundary this frame
    lsr.w       #4,d1                       ; d1 = tick / ENEMY_ANIM_TICKS (tick >> 4)
    and.w       #3,d1                       ; frame index 0..3
    move.w      d1,d5                       ; d5 = frame index (preserved across loop)

    move.w      ActorCount(a5),d7
    subq.w      #1,d7
    bmi         .exit
    lea         ActorList(a5),a2            ; a2 -> sorted actor pointer array

.loop
    move.l      (a2)+,a3                    ; a3 -> actor struct (live, via ActorList)
    tst.w       Actor_HasFalled(a3)
    bne         .next                       ; falling: ActionFallActors owns rendering
    tst.w       Actor_ImpactTick(a3)
    bne         .next                       ; impact smoke active: skip

    move.w      Actor_Type(a3),d1
    cmp.w       #BLOCK_ENEMYFALL,d1
    beq         .fall_frame
    cmp.w       #BLOCK_ENEMYFLOAT,d1
    bne         .next

    move.w      d5,d2
    add.w       #TILE_ENEMYFLOATA,d2
    bra         .do_update

.fall_frame
    move.w      d5,d2
    add.w       #TILE_ENEMYFALLA,d2

.do_update
    move.w      d2,Actor_SpriteOffset(a3)

    ; Viewport Y culling: skip blitting tile if off-screen
    move.w      Actor_Y(a3),d1
    move.w      TilemapScreenOffset(a5),d0
    subq.w      #1,d0
    cmp.w       d0,d1
    blt.s       .next
    add.w       #15,d0
    cmp.w       d0,d1
    bgt.s       .next

    move.w      Actor_X(a3),d0
    bsr         RestoreBackgroundTile
    bsr         ActorDrawStatic

.next
    dbra        d7,.loop

.exit
    rts
    ELSE
    rts
    ENDC
