
;==============================================================================
; AMIGA GAME ENGINE
; actors.asm  -  Actor Initialisation, Management and Drawing
;==============================================================================
;
; An "actor" is any game object that occupies a tile cell and can move, be
; killed, or animate.  This includes:
;   - Enemy falling  (BLOCK_ENEMYFALL  = gravity-affected enemy)
;   - Enemy floating (BLOCK_ENEMYFLOAT = gravity-immune enemy)
;   - Pushable block (BLOCK_PUSH       = can be slid by the player)
;   - Dirt block     (BLOCK_DIRT       = player can walk through / destroy)
;   - Millie / Molly (player characters - special initialisation path)
;
; Actor data lives in the flat Actors[] array (Actor_Sizeof bytes per slot).
; The ActorList[] array holds pointers into Actors[], sorted by Y position
; (largest Y drawn last = appears on top).
;
; Register convention:
;   a3 = pointer to the current actor structure
;   a5 = Variables base pointer
;
;==============================================================================

;==============================================================================
; CreateClearMasks  -  Pre-compute the 16 blitter first-word masks for ClearActor
;
; The blitter's BLTAFWM (first word mask) must vary with the sub-tile pixel
; offset of an actor so that only the correct bits are cleared when erasing
; a 24-pixel-wide tile from a 16-bit-aligned screen buffer.
;
; This routine builds the 16 possible masks (one per pixel offset 0..15) and
; stores them in ClearMasks(a5) as a table of 16 longwords.
;
; Algorithm:
;   Start mask = $ffffff00  (24 bits set, covering a 24-wide tile in 32 bits)
;   Each iteration: shift right 1 bit (LSR.L), and if the carry caused the MSB
;   to drop out (BCC), set bit 31 to $8000 (LSB of the WORD above).
;   This produces masks offset by 0..15 bit positions.
;
; Called once at game startup (from Init / GameInit).
;==============================================================================

CreateClearMasks:
    moveq      #16-1,d7
    lea        ClearMasks(a5),a0
    move.l     #$ffffff00,d0
.loop
    move.l     d0,(a0)+
    lsr.l      #1,d0
    bcc        .under
    move.w     #$8000,d0
.under
    dbra       d7,.loop
    rts  

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

    ; Reset the actor pointer list write cursor to the start of ActorList
    lea         ActorList(a5),a0
    move.l      a0,ActorSlotPtr(a5)

    ; Zero the entire actor pool before use
    lea         Actors(a5),a0              ; start of Actors[], not ActorList
    move.l      #Actor_Sizeof*MAX_ACTORS,d7
    bsr         TurboClear                 ; clear Actor_Sizeof * MAX_ACTORS bytes

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
;   BLOCK_DIRT       (4) -> InitDirt
;   BLOCK_SOLID      (5) -> InitDummy
;   BLOCK_ENEMYFLOAT (6) -> InitEnemyFloat
;   BLOCK_MILLIESTART(7) -> InitMillie
;   BLOCK_MOLLYSTART (8) -> InitMolly
;   BLOCK_COCOON    (11) -> InitCocoon
;   BLOCK_ACID      (12) -> InitDummy  (static map hazard, no actor)
;==============================================================================

InitObject:
    JMPINDEX    d0                         ; computed jump on block type

.i  ; offset table
    dc.w        InitDummy-.i               ; BLOCK_EMPTY       = 0
    dc.w        InitDummy-.i               ; BLOCK_LADDER      = 1
    dc.w        InitEnemyFall-.i           ; BLOCK_ENEMYFALL   = 2
    dc.w        InitPushBlock-.i           ; BLOCK_PUSH        = 3
    dc.w        InitDirt-.i                ; BLOCK_DIRT        = 4
    dc.w        InitDummy-.i               ; BLOCK_SOLID       = 5
    dc.w        InitEnemyFloat-.i          ; BLOCK_ENEMYFLOAT  = 6
    dc.w        InitMillie-.i              ; BLOCK_MILLIESTART = 7
    dc.w        InitMolly-.i               ; BLOCK_MOLLYSTART  = 8
    dc.w        InitDummy-.i               ; BLOCK_MILLIELADDER= 9  (never in level data)
    dc.w        InitDummy-.i               ; BLOCK_MOLLYLADDER = 10 (never in level data)
    dc.w        InitCocoon-.i              ; BLOCK_COCOON      = 11
    dc.w        InitDummy-.i               ; BLOCK_ACID        = 12 (static hazard)


;==============================================================================
; InitDummy  -  No-op initialiser for block types that need no actor
;==============================================================================

InitDummy:
    rts


;==============================================================================
; InitDirt  -  Create an actor for a dirt block
;
; Dirt blocks come in 4 graphical variants depending on whether the blocks
; immediately to the left and right are also dirt (for seamless joins):
;
;   Tile variant lookup table at .add:
;     index 0 (no neighbours)   -> TILE_DIRTA + 0  = TILE_DIRTA
;     index 1 (right neighbour) -> TILE_DIRTA + 1  = TILE_DIRTB
;     index 2 (left neighbour)  -> TILE_DIRTA + 3  = TILE_DIRTD  (NOTE: .add[2]=3)
;     index 3 (both neighbours) -> TILE_DIRTA + 2  = TILE_DIRTC  (NOTE: .add[3]=2)
;
; The adjacency check uses (a0) for the CURRENT cell (after GetActorSlot advances a0)
; and offsets from the original map pointer for neighbours.  Relies on a0 still
; pointing to the current cell in GameMap at call time.
;
; Actor_Static is set to 1 - dirt blocks are drawn once into DisplayScreen
; and never animated (no need to update them each frame).
;==============================================================================

InitDirt:
    bsr         GetActorSlot               ; allocate a slot; a3 -> new actor, a0 unchanged

    ; Determine which dirt variant tile to use based on neighbours
    moveq       #0,d0
    cmp.b       #BLOCK_DIRT,(a0)           ; is the cell AFTER current also dirt (right neighbour)?
    bne         .notright
    bset        #0,d0                      ; bit 0 set = right neighbour present
.notright
    cmp.b       #BLOCK_DIRT,-2(a0)         ; is the cell TWO before current also dirt (left neighbour)?
                                           ; (a0 was advanced past the current cell by GetActorSlot)
    bne         .notleft
    bset        #1,d0                      ; bit 1 set = left neighbour present
.notleft
    ; Look up tile variant: .add maps (right|left) flags to tile index offset
    move.b      .add(pc,d0.w),d0           ; d0 = tile offset (0, 1, 2 or 3)
    add.w       #TILE_DIRTA,d0             ; d0 = final tile index
    move.w      d0,Actor_SpriteOffset(a3)  ; store tile to draw
    move.w      #1,Actor_Static(a3)        ; dirt is static (drawn once, not animated)
    rts

.add
    dc.b        0,1,3,2     ; index = (leftBit<<1 | rightBit) -> tile offset within DIRTA..DIRTD


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
    move.w      #TILE_PUSH,Actor_SpriteOffset(a3)          ; push block sprite
    move.w      #1,Actor_CanFall(a3)       ; push blocks fall under gravity
    move.w      #1,Actor_Static(a3)        ; static appearance (not animated)
    rts


;==============================================================================
; InitCocoon  -  Create an alien cocoon actor (Alien Containment mechanic)
;
; A cocoon behaves like a push block (pushable, falls under gravity) until its
; hatch countdown expires, at which point UpdateCocoons converts it into a
; live BLOCK_ENEMYFALL organism in place.
;
; The countdown is authored in PAL frames (COCOON_HATCH_FRAMES) and armed
; through ScalePALFrames so the real-time duration matches on NTSC.
; GetActorSlot preserves d1/d2 (X/Y); ScalePALFrames only touches d0.
;==============================================================================

InitCocoon:
    bsr         GetActorSlot
    move.w      #TILE_COCOON_A,Actor_SpriteOffset(a3)      ; calm cocoon tile
    move.w      #1,Actor_CanFall(a3)       ; falls under gravity (like a crate)
    move.w      #1,Actor_Static(a3)        ; drawn statically; UpdateCocoons animates
    PUSH        d0
    move.w      #COCOON_HATCH_FRAMES,d0
    bsr         ScalePALFrames             ; NTSC: stretch to match real time
    move.w      d0,Actor_HatchTick(a3)
    POP         d0
    rts


;==============================================================================
; InitMillie  -  Initialise the Millie player character
;
; Sets Millie's sprite base offset to 48 (Millie's frames come after Molly's
; in the PlayerHWSprites data), configures her map block IDs, then calls InitPlayer.
;
; Player_SpriteOffset = 48 means all sprite frame lookups for Millie are
; offset by 48 frames relative to the start of PlayerHWSprites.
; Player_LadderFreezeId = 97 is the frame index used when Millie is frozen
; on a ladder (the idle-on-ladder graphic for Millie).
;==============================================================================

InitMillie:
    lea         Millie(a5),a4              ; a4 -> Millie player structure
    move.w      #48,Player_SpriteOffset(a4)        ; Millie's sprite base = frame 48
    move.w      #31,Player_FrozenSpriteBase(a4)       ; Millie's frozen sprite (right-facing)
    move.w      #34,Player_LadderFreezeId(a4)      ; ladder freeze frame index
    move.b      #BLOCK_MILLIESTART,Player_BlockId(a4)    ; map cell type for Millie's presence
    move.b      #BLOCK_MILLIELADDER,Player_LadderId(a4)  ; map cell type when on ladder
    bsr         InitPlayer
    rts


;==============================================================================
; InitMolly  -  Initialise the Molly player character
;
; Sets Molly's sprite base offset to 0 (Molly's frames are first in PlayerHWSprites),
; configures her map block IDs, then calls InitPlayer.
;==============================================================================

InitMolly:
    lea         Molly(a5),a4               ; a4 -> Molly player structure
    move.w      #0,Player_SpriteOffset(a4)         ; Molly's sprite base = frame 0
    move.w      #29,Player_FrozenSpriteBase(a4)       ; Molly's frozen sprite (right-facing)
    move.w      #33,Player_LadderFreezeId(a4)      ; ladder freeze frame index
    move.b      #BLOCK_MOLLYSTART,Player_BlockId(a4)    ; map cell type for Molly's presence
    move.b      #BLOCK_MOLLYLADDER,Player_LadderId(a4)  ; map cell type when on ladder
    bsr         InitPlayer
    rts


;==============================================================================
; InitPlayer  -  Common player initialisation (called by InitMillie / InitMolly)
;
; Increments the PlayerCount, sets the player's starting tile position from
; d1 (X) and d2 (Y), marks the player as active (Status=1), and sets the
; initial facing direction to right (+1).
;
; Sub-tile pixel offsets (XDec/YDec) are cleared to 0 (aligned on a tile).
;
; Note: PlayerPtrs are NOT set here.  LevelInit wires Millie->slot 0 and
; Molly->slot 1 before InitGameObjects runs, then normalizes the pointers
; afterward based on which players are actually present in the level:
; slot 0 always ends up with the active player (Status=1).
;
; On entry:
;   a4 = player structure pointer (set by InitMillie / InitMolly)
;   d1 = starting tile X
;   d2 = starting tile Y
;==============================================================================

InitPlayer:
    addq.w      #1,PlayerCount(a5)         ; count this player as initialised
    clr.w       Player_OnLadder(a4)        ; start on ground (not on ladder)
    move.w      d1,Player_X(a4)            ; set starting tile column
    move.w      d2,Player_Y(a4)            ; set starting tile row
    move.w      #1,Player_DirectionX(a4)   ; initial facing: right
    clr.w       Player_XDec(a4)            ; no sub-tile X offset
    clr.w       Player_YDec(a4)            ; no sub-tile Y offset
    moveq       #0,d0
    move.w      d1,d0
    mulu        #TILE_WIDTH,d0
    move.w      d0,Player_PixelX(a4)       ; seed pixel cache: X * 24
    moveq       #0,d0
    move.w      d2,d0
    mulu        #TILE_WIDTH,d0
    move.w      d0,Player_PixelY(a4)       ; seed pixel cache: Y * 24

    ; Set player status: first player is active (1), second is frozen (2)
    cmp.w       #1,PlayerCount(a5)         ; is this the first player?
    beq         .first_player
    move.w      #2,Player_Status(a4)       ; status = 2 (frozen, waiting for switch)
    bra         .init_done
.first_player
    move.w      #1,Player_Status(a4)       ; status = 1 (active, controlled by player)
.init_done
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
; Crashes to FUCK if the actor pool is full (should never happen with
; MAX_ACTORS = MAP_SIZE = 88 slots for 88 map cells).
;==============================================================================

GetActorSlot:
    move.w      ActorCount(a5),d5          ; d5 = current count (= index of new slot)
    cmp.w       #MAX_ACTORS,d5             ; pool full?
    bcc         ACTOR_POOL_OVERFLOW         ; if count >= MAX_ACTORS, fatal error

    addq.w      #1,ActorCount(a5)          ; increment actor count

    ; Calculate address of new slot: &Actors + d5 * Actor_Sizeof
    lea         Actors(a5),a3
    mulu        #Actor_Sizeof,d5
    add.l       d5,a3                      ; a3 -> new actor structure

    ; Initialise core fields
    move.w      d1,Actor_X(a3)             ; tile column
    move.w      d2,Actor_Y(a3)             ; tile row
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
; Should never be reached in normal play (MAX_ACTORS = MAP_SIZE = 88,
; and no level can contain more actors than it has map cells).
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
; "Static" actors (dirt, push blocks) are drawn here during level init and
; remain until explicitly cleared by RestoreBackgroundTile.
; Moving actors (enemies) are also blitted here when they arrive at a new tile.
;
; On entry:
;   a5 = Variables base
;   a6 = $dff000 (needed by PasteTile's WAITBLIT macro)
;==============================================================================

DrawStaticActors:
    move.w      ActorCount(a5),d7
    bne         .go
    rts

.go
    PUSHM       a4                         ; a4 used for TileMask (a2=ActorList in use)
    subq.w      #1,d7
    lea         ActorList(a5),a2

    ; Write constant blitter registers once for the entire actor batch.
    ; PasteTile always uses BLTAFWM=-1, BLTAMOD=0, BLTBMOD=0,
    ; BLTCMOD/BLTDMOD=TILE_BLT_MOD.  These don't change between actors.
    WAITBLIT
    move.l      #-1,BLTAFWM(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #0,BLTBMOD(a6)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)

.loop
    move.l      (a2)+,a3                   ; a3 -> actor struct (live, via ActorList)
    tst.w       Actor_Dirty(a3)
    beq         .next

.normal_blit
    ; Pre-compute blit parameters (CPU work overlaps previous blit's DMA)
    move.l      TilesetPtr(a5),a0
    lea         TileMask,a4

    moveq       #0,d0
    move.w      Actor_SpriteOffset(a3),d0
    mulu        #TILE_SIZE,d0
    add.l       d0,a0                      ; a0 -> tile graphic
    add.l       d0,a4                      ; a4 -> tile mask

    ; Load pixel X and calculate viewport-relative pixel Y
    move.w      Actor_X(a3),d0
    lsl.w       #4,d0                      ; d0 = pixel X
    move.w      Actor_Y(a3),d1
    sub.w       TilemapScreenOffset(a5),d1 ; relative row in visible viewport
    bmi.s       .actor_offscreen           ; above viewport -> skip
    cmp.w       #TILEMAP_VIEW_ROWS,d1
    bge.s       .actor_offscreen           ; below viewport -> skip
    lsl.w       #4,d1                      ; d1 = pixel Y = rel_row * 16

    ; Destination address
    lea         DisplayScreen,a1
    mulu        #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2                      ; byte column = pixel_X / 8
    add.w       d2,d1
    add.l       d1,a1                      ; a1 -> dest pixel

    ; BLTCON0/BLTCON1: X mod 16 packed into shift field
    and.w       #$f,d0
    ror.w       #4,d0
    move.w      d0,d2
    or.w        #$fca,d0                   ; minterm $fca = masked copy

    WAITBLIT
    move.w      d0,BLTCON0(a6)
    move.w      d2,BLTCON1(a6)
    move.l      a4,BLTAPT(a6)              ; A = tile mask
    move.l      a0,BLTBPT(a6)              ; B = tile graphic
    move.l      a1,BLTCPT(a6)              ; C/D = screen dest
    move.l      a1,BLTDPT(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6) ; start blit

    clr.w       Actor_Dirty(a3)

.actor_offscreen
.next
    dbra        d7,.loop
    POPM        a4
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
    bne         .go
    rts

.go
    subq.w      #1,d7
    lea         ActorList(a5),a2           ; a2 -> sorted pointer array

.loop
    move.l      (a2)+,a3                   ; a3 -> next actor struct (via sorted list)
    move.w      Actor_X(a3),Actor_PrevX(a3)    ; save X
    move.w      Actor_Y(a3),Actor_PrevY(a3)    ; save Y
    clr.w       Actor_HasMoved(a3)             ; clear moved flag
    dbra        d7,.loop
    rts


; ClearFrozenPlayer  ->  frozenplayer.asm


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
; After players kill actors (PlayerKillActor / PlayerKillDirt), their
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
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile
    bsr         ActorDrawStatic

.next
    dbra        d7,.loop

.exit
    rts


;==============================================================================
; UpdateCocoons  -  Tick every cocoon's hatch countdown (called every frame)
;
; Called from GameRun (gamestatus.asm) right after AnimateEnemies.
;
; For each live BLOCK_COCOON actor that is at rest (not falling, not playing
; the landing smoke, not the block currently being pushed):
;
;   1. Decrement Actor_HatchTick.  On reaching zero, HATCH:
;        - GameMap cell (X,Y): BLOCK_COCOON -> BLOCK_ENEMYFALL
;        - Actor_Type -> BLOCK_ENEMYFALL, sprite -> TILE_ENEMYFALLA,
;          Actor_Static -> 0 (AnimateEnemies takes over animation)
;        - redraw the tile.  From this frame the hatchling is a normal
;          organism: side-contact contains it, acid dissolves it, and
;          CheckLevelDone counts it via the map value.
;   2. Otherwise drive the pulse animation from the remaining time:
;        > COCOON_STAGE2 frames left: calm      (TILE_COCOON_A held)
;        > COCOON_STAGE3 frames left: stirring  (A/B swap every 32 frames)
;        else:                        frantic   (A/B swap every  8 frames)
;      The tile is only redrawn when the frame actually changes.
;
; Rewind safety: Actor_HatchTick/Type/SpriteOffset/Static are all part of the
; undo snapshot (struct.asm), so rewinding across a hatch restores the cocoon.
;==============================================================================

UpdateCocoons:
    move.w      ActorCount(a5),d7
    subq.w      #1,d7
    bmi         .exit
    lea         ActorList(a5),a2            ; a2 -> sorted actor pointer array

.loop
    move.l      (a2)+,a3                    ; a3 -> actor struct (live)
    cmp.w       #BLOCK_COCOON,Actor_Type(a3)
    bne         .next
    tst.w       Actor_HasFalled(a3)
    bne         .next                       ; mid-fall: leave it alone
    tst.w       Actor_ImpactTick(a3)
    bne         .next                       ; landing smoke: leave it alone
    cmp.w       #ACTION_PLAYERPUSH,ActionStatus(a5)
    bne         .settled
    cmp.l       PushedActor(a5),a3
    beq         .next                       ; this cocoon is being pushed right now
.settled

    move.w      Actor_HatchTick(a3),d0
    subq.w      #1,d0
    move.w      d0,Actor_HatchTick(a3)
    beq         .hatch

    ; --- pulse animation stage from remaining frames ---
    move.w      #TILE_COCOON_A,d2
    cmp.w       #COCOON_STAGE2,d0
    bgt         .apply                      ; calm: hold frame A
    move.w      TickCounter(a5),d1
    cmp.w       #COCOON_STAGE3,d0
    bgt         .stirring
    and.w       #8,d1                       ; frantic: swap every 8 frames
    bra         .pulse
.stirring
    and.w       #32,d1                      ; stirring: swap every 32 frames
.pulse
    beq         .apply
    move.w      #TILE_COCOON_B,d2
.apply
    cmp.w       Actor_SpriteOffset(a3),d2
    beq         .next                       ; frame unchanged: no redraw
    move.w      d2,Actor_SpriteOffset(a3)
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile
    bsr         ActorDrawStatic
    bra         .next

.hatch
    ; Convert the cocoon into a live falling organism, in place.
    move.w      Actor_Y(a3),d0
    mulu        #WALL_PAPER_WIDTH,d0
    add.w       Actor_X(a3),d0
    lea         GameMap(a5),a0
    move.b      #BLOCK_ENEMYFALL,(a0,d0.w)  ; map now holds a live organism
    move.w      #BLOCK_ENEMYFALL,Actor_Type(a3)
    move.w      #TILE_ENEMYFALLA,Actor_SpriteOffset(a3)
    clr.w       Actor_Static(a3)            ; AnimateEnemies animates it now
    move.w      #1,Actor_Dirty(a3)
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         RestoreBackgroundTile
    bsr         ActorDrawStatic

.next
    dbra        d7,.loop

.exit
    rts
