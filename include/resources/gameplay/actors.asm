
;==============================================================================
; AMIGA GAME ENGINE
; actors.asm  -  Actor Initialisation, Management and Drawing
;==============================================================================
;
; In this engine, an "actor" is a pushable crate / interactive block (BLOCK_PUSH)
; that occupies a tile cell, can be slid by the player, and falls under gravity.
; (Enemies, animal friends, and oxygen bottles use dedicated sub-system pools).
;
; Actor data lives in the flat Actors[] array (Actor_Sizeof bytes per slot,
; MAX_ACTIVE_CRATES = 16 slots maximum).
; The ActorList[] array holds pointers into Actors[], sorted by Y position
; (largest Y drawn last = appears on top).
;
; Register convention:
;   a3 = pointer to the current actor structure
;   a5 = Variables base pointer
;
;==============================================================================

;==============================================================================
; InitGameObjects  -  Scan the game map and create an actor for each object
;
; Called by LevelInit after the maps are built.  Iterates over every cell of
; GameMap (WALL_PAPER_WIDTH x WALL_PAPER_HEIGHT = 14 x 9 = 126 cells) and
; calls InitObject for non-empty, non-solid cells.
;
; After all actors are created, SortActors is called to order the ActorList
; by Y position so DrawStaticActors renders them back-to-front.
;
; Entry:  a5 = Variables base
; Exit:   ActorCount(a5) = number of initialised actors
;         ActorList(a5)  = sorted array of actor pointers
;==============================================================================

InitGameObjects:
    clr.w       ActorCount(a5)             ; reset actor count to zero
    clr.w       TotalActorCount(a5)

    ; Reset the actor pointer list write cursor to the start of ActorList
    lea         ActorList(a5),a0
    move.l      a0,ActorSlotPtr(a5)

    ; Zero the entire actor pool before use
    lea         Actors(a5),a0              ; start of Actors[], not ActorList
    move.l      #Actor_Sizeof*MAX_ACTIVE_CRATES,d7
    bsr         TurboClear                 ; clear Actor_Sizeof * MAX_ACTIVE_CRATES bytes

    ; Walk the GameMap and initialise an actor for each cell
    lea         GameMap(a5),a0             ; a0 -> start of live game map
    moveq       #0,d1                      ; d1 = current X (column, 0-based)
    moveq       #0,d2                      ; d2 = current Y (row, 0-based)

.nextcell
    moveq       #0,d0
    move.b      (a0)+,d0                   ; d0 = block type at current cell
    move.w      d0,d3                      ; d3 = type again (InitObject uses both)
    bsr         InitObject                 ; create actor for this block type

    addq.w      #1,d1                      ; advance to next column
    cmp.w       #WALL_PAPER_WIDTH,d1       ; end of row?
    bne         .nextcell

    moveq       #0,d1                      ; reset column to 0
    addq.w      #1,d2                      ; advance to next row
    cmp.w       CurrentMapHeight(a5),d2    ; end of map?
    bne         .nextcell

    bsr         SortActors                 ; sort ActorList by Y for correct draw order
    move.w      ActorCount(a5),TotalActorCount(a5) ; record total actors created for level
    rts


;==============================================================================
; InitObject  -  Dispatch to the correct initialisation routine for a block type
;
; Uses JMPINDEX to jump to the appropriate Init routine based on the block type.
; Most block types create an actor; solid walls and empty spaces are ignored.
;
; On entry:
;   d0 = block type (BLOCK_xxx constant, 0-based)
;   d1 = X tile position
;   d2 = Y tile position
;   d3 = block type (duplicate, some inits use d3 to store Actor_Type)
;
; The dispatch table entries:
;   BLOCK_EMPTY      (0) -> InitDummy   (nothing to do)
;   BLOCK_LADDER     (1) -> InitDummy   (ladders are purely graphical, not actors)
;   BLOCK_ENEMYFALL  (2) -> InitEnemyFall
;   BLOCK_PUSH       (3) -> InitPushBlock
;   (unused slot)    (4) -> InitDummy
;   BLOCK_SOLID      (5) -> InitDummy
;   BLOCK_ENEMYFLOAT (6) -> InitEnemyFloat
;   BLOCK_PLAYERSTART(7) -> InitPlayer
;==============================================================================

InitObject:
    JMPINDEX    d0                         ; computed jump on block type

.i  ; offset table
    dc.w        InitDummy-.i               ; BLOCK_EMPTY       = 0
    dc.w        InitDummy-.i               ; BLOCK_LADDER      = 1
    dc.w        InitEnemyFall-.i           ; BLOCK_ENEMYFALL   = 2
    dc.w        InitPushBlock-.i           ; BLOCK_PUSH        = 3
    dc.w        InitDummy-.i               ; (unused)          = 4
    dc.w        InitDummy-.i               ; BLOCK_SOLID       = 5
    dc.w        InitEnemyFloat-.i          ; BLOCK_ENEMYFLOAT  = 6
    dc.w        InitPlayer-.i              ; BLOCK_PLAYERSTART = 7
    dc.w        InitDummy-.i               ; (unused)          = 8
    dc.w        InitDummy-.i               ; BLOCK_PLAYERLADDER= 9  (never in level data)


;==============================================================================
; InitDummy  -  No-op initialiser for block types that need no actor
;==============================================================================

InitDummy:
    rts




;==============================================================================
; InitEnemyFloat  -  Create a floating enemy actor (not affected by gravity)
;
; Floating enemies begin at frame TILE_ENEMYFLOATA and are animated elsewhere.
; Actor_CanFall is NOT set (default 0 from GetActorSlot clear).
;==============================================================================

InitEnemyFloat:
    bsr         GetActorSlot
    move.w      #TILE_ENEMYFLOATA,Actor_SpriteOffset(a3)   ; floating enemy sprite
    rts


;==============================================================================
; InitEnemyFall  -  Create a falling enemy actor (subject to gravity)
;
; Falling enemies use TILE_ENEMYFALLA as their base sprite and have
; Actor_CanFall = 1 so that ActorFallAll will process them.
;==============================================================================

InitEnemyFall:
    bsr         GetActorSlot
    move.w      #TILE_ENEMYFALLA,Actor_SpriteOffset(a3)    ; falling enemy sprite
    move.w      #1,Actor_CanFall(a3)       ; subject to gravity
    rts


;==============================================================================
; InitPushBlock  -  Create a pushable block actor
;
; Push blocks display as TILE_PUSH and are affected by gravity (they fall if
; unsupported after being pushed).  They are also static (drawn once per move).
;==============================================================================

InitPushBlock:
    bsr         GetActorSlot
    move.w      #TILE_PUSH,d0              ; default tile index (37)

    ; Check if CurrentLevelDef has LevelDef_BlockList:
    move.l      CurrentLevelDef(a5),d4
    beq.s       .use_sprite
    movea.l     d4,a4
    move.l      LevelDef_BlockList(a4),d4
    beq.s       .use_sprite
    movea.l     d4,a4                      ; a4 -> BlockList: Col (w), Row (w), Sprite (w), Res (w)

.scan_block_list:
    move.w      (a4),d4                    ; Col
    cmp.w       #$ffff,d4                  ; End of list?
    beq.s       .use_sprite
    cmp.w       Actor_X(a3),d4
    bne.s       .next_entry
    cmp.w       2(a4),d2                   ; Row matches? (d2 is Row in InitPushBlock)
    bne.s       .next_entry
    move.w      4(a4),d0                   ; Sprite index from BlockList!
    bra.s       .use_sprite

.next_entry:
    addq.l      #8,a4                      ; 8 bytes per record
    bra.s       .scan_block_list

.use_sprite:
    move.w      d0,Actor_SpriteOffset(a3)  ; push block sprite (e.g. 37 for crate)
    move.w      #1,Actor_CanFall(a3)       ; push blocks fall under gravity
    move.w      #1,Actor_Static(a3)        ; static appearance (not animated)
    rts



;==============================================================================
; InitPlayer  -  Initialise the player character
;
; Sets Player's BOB base offset, configures map block IDs, marks the player as
; configures map block IDs, marks the player as active (Status=1), and sets the
; starting tile position and facing direction.
;
; On entry:
;   d1 = starting tile X
;   d2 = starting tile Y
;   a5 = Variables base pointer
;==============================================================================

InitPlayer:
    lea         Player(a5),a4                   ; a4 -> Player structure
    clr.w       Player_BobOffset(a4)            ; 24-frame sheet (frames 0..23)
    move.w      #20,Player_FrozenBobBase(a4)    ; frozen BOB pose (fall frame 20)
    move.w      #PLAYER_LADDER_IDLE,Player_LadderFreezeId(a4)   ; ladder freeze frame index

.init_ids:
    move.b      #BLOCK_PLAYERSTART,Player_BlockId(a4)    ; map cell type for Player's presence
    move.b      #BLOCK_PLAYERLADDER,Player_LadderId(a4)  ; map cell type when on ladder
    move.w      #1,PlayerCount(a5)              ; count player as initialised
    clr.w       Player_OnLadder(a4)             ; start on ground (not on ladder)
    move.w      d1,Player_X(a4)                 ; set starting tile column
    move.w      d2,Player_Y(a4)                 ; set starting tile row
    move.w      #1,Player_DirectionX(a4)        ; initial facing: right
    clr.w       Player_XDec(a4)                 ; no sub-tile X offset
    clr.w       Player_YDec(a4)                 ; no sub-tile Y offset
    moveq       #0,d0
    move.w      d1,d0
    lsl.w       #4,d0
    move.w      d0,Player_PixelX(a4)            ; seed pixel cache: X * 16
    moveq       #0,d0
    move.w      d2,d0
    lsl.w       #4,d0
    move.w      d0,Player_PixelY(a4)            ; seed pixel cache: Y * 16
    move.w      Player_PixelX(a4),Player_WorldX(a4)
    move.w      d0,d3
    subq.w      #8,d3
    move.w      d3,Player_WorldY(a4)
    move.w      #1,Player_Status(a4)            ; status = 1 (active)
    rts


;==============================================================================
; GetActorSlot  -  Allocate a new actor structure from the pool
;
; Allocates the next free Actor slot, sets its initial position and type
; fields from d1 (X), d2 (Y), d3 (type), and adds it to the ActorList.
;
; The slot index is the current ActorCount value (before incrementing).
; Actor structures are stored sequentially: &Actors[0] + index * Actor_Sizeof.
;
; Also pushes the actor pointer into ActorList via ActorSlotPtr.
;
; On entry:
;   d1 = X tile position
;   d2 = Y tile position
;   d3 = block type (stored in Actor_Type)
;   a0 = current GameMap pointer (preserved and restored)
;
; On exit:
;   a3 = pointer to the newly allocated actor structure
;   ActorCount(a5) incremented by 1
;
; Handles actor allocation with overflow check against MAX_ACTIVE_CRATES (16 slots).
;==============================================================================

GetActorSlot:
    move.w      ActorCount(a5),d5          ; d5 = current count (= index of new slot)
    cmp.w       #MAX_ACTIVE_CRATES,d5      ; pool full?
    bcc         ACTOR_POOL_OVERFLOW         ; if count >= MAX_ACTIVE_CRATES, fatal error

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

    ; Cache pixel positions: X * 16 (TILE_WIDTH), Y * 16 (TILE_GRID_HEIGHT)
    move.w      d1,d0
    lsl.w       #4,d0                      ; d0 = X * 16
    move.w      d0,Actor_PixelX(a3)

    move.w      d2,d0
    lsl.w       #4,d0                      ; d0 = Y * 16
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
; ACTOR_POOL_OVERFLOW  -  Fatal error: actor pool has been exhausted
;
; Should never be reached in normal play (MAX_ACTIVE_CRATES = 16,
; peak campaign crate count across Levels 1-6 is 2 in Levels 3 & 4).
; Paints COLOR00 solid red and prints a diagnostic string to DisplayScreen,
; then halts.
;==============================================================================

ACTOR_POOL_OVERFLOW:
    move.w      #$0f00,$dff180             ; COLOR00 = solid red (absolute address; a6 may be stale)
    lea         DisplayScreen+(4*LOADING_ROW_BYTES)+2,a1
    lea         .msg,a0
    bsr         CHAR_BLTString
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
;   a6 = $dff000 (needed by PasteTile's WAITBLIT macro)
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
; Y values are bounded to 0..8 (WALL_PAPER_HEIGHT-1), giving exactly 9
; buckets.  Three passes over ActorList (O(n)) replace the old O(n²) bubble
; sort.  Scratch space: 9-word count/offset array on the stack + ActorSortBuf
; in the Variables block.
;
; ActorSlotPtr is NOT used as the end sentinel (CleanActors does not update
; it); the loop count is derived from ActorCount.
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
;==============================================================================

AnimateEnemies:
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
