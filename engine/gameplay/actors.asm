HAS_TILEMAP_CAMERA = 1

;==============================================================================
; AMIGA GAME ENGINE
; actors.asm  -  Actor Initialisation, Management and Drawing
;==============================================================================
;
; In this engine, an "actor" is a pushable crate / interactive block (BLOCK_PUSH)
; that occupies a tile cell, can be slid by the player, and falls under gravity.
; (Enemies, friends, and pickups use their own pools, in entities.asm).
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
; GameMap (MAP_WIDTH x CurrentMapHeight cells) and
; calls InitObject for non-empty, non-solid cells.
;
; After all actors are created, SortActors is called to order the ActorList
; by Y position so DrawStaticActors renders them back-to-front.
;
; Entry:  a5 = Variables base
; Exit:   ActorCount(a5) = number of initialised actors
;         ActorList(a5)  = sorted array of actor pointers
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
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
    cmp.w       #MAP_WIDTH,d1       ; end of row?
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
;
; Destroys: none (preserves all registers)
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
;
; Destroys: none (preserves all registers)
;==============================================================================

InitDummy:
    rts




;==============================================================================
; InitEnemyFloat  -  Create a floating enemy actor (not affected by gravity)
;
; Floating enemies begin at frame TILE_ENEMYFLOATA and are animated elsewhere.
; Actor_CanFall is NOT set (default 0 from GetActorSlot clear).
;
; Destroys: d0/d5/a3 (preserves everything else, including a5/a6)
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
;
; Destroys: d0/d5/a3 (preserves everything else, including a5/a6)
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
;
; Destroys: d0/d4-d5/a3-a4 (preserves everything else, including a5/a6)
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
;
; Destroys: d0/d3/a4 (preserves everything else, including a5/a6)
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


    include    "actor_pool.asm"


; TilemapDrawPushBlocks  -  Draw all active, settled push blocks
;
; Called every frame in GameRun before friends and the player are drawn.
; Only settled push blocks (HasMoved=0, HasFalled=0) are drawn here;
; moving blocks are animated by ActionPush / ActionFallActors.
;
; In:  a5 = Variables base
;      a6 = CUSTOM base
; Preserves: a5, a6
;==============================================================================

TilemapDrawPushBlocks:
    PUSHM       d0-d7/a0-a4

    move.w      ActorCount(a5),d7
    beq         .dpb_exit
    subq.w      #1,d7
    lea         ActorList(a5),a2

.dpb_loop:
    move.l      (a2)+,a3
    tst.w       Actor_Status(a3)
    beq.s       .dpb_next
    cmp.w       #BLOCK_PUSH,Actor_Type(a3)
    bne.s       .dpb_next
    tst.w       Actor_HasFalled(a3)
    bne.s       .dpb_next
    tst.w       Actor_ImpactTick(a3)
    bne.s       .dpb_next

    ; Viewport Y culling: check if crate is within active display rows
    ; (TilemapScreenOffset - 1 <= Actor_Y <= TilemapScreenOffset + 14)
    move.w      Actor_Y(a3),d1
    move.w      TilemapScreenOffset(a5),d2
    subq.w      #1,d2
    cmp.w       d2,d1
    blt.s       .dpb_next
    add.w       #15,d2
    cmp.w       d2,d1
    bgt.s       .dpb_next

    ; Check if crate is currently moving (being pushed)
    tst.w       Actor_HasMoved(a3)
    beq.s       .dpb_check_dirty

    ; Moving push block: draw with its pixel offset within the tile
    bsr         DrawActor
    bra.s       .dpb_next

.dpb_check_dirty:
    tst.b       VhsStateActive        ; during rewind, always redraw push blocks
    bne.s       .dpb_do_draw
    tst.w       Actor_Dirty(a3)        ; skip already-drawn stationary push blocks
    beq.s       .dpb_next

.dpb_do_draw:
    ; Draw settled push block at Actor_X, Actor_Y (stamps foreground & checks water)
    bsr         ActorDrawStatic

.dpb_next:
    dbra        d7,.dpb_loop

.dpb_exit:
    POPM        d0-d7/a0-a4
    rts

;==============================================================================
; Actor tile drawing / erasing primitives (shared by actor_pool, dirty_tiles, undo)
;==============================================================================

;==============================================================================
; RedrawActorAtTile  -  Redraw the settled actor occupying a given tile, if any
;
; Scans ActorList for a live, settled (not mid-fall) actor whose tile
; position matches (d0, d1) and redraws it via ActorDrawStatic. Used after
; a tile's background has been restored (e.g. RestoreBackgroundTile) to
; re-composite any actor that was sitting on that tile, since restoring the
; background alone would otherwise erase it.
;
; Entry: d0 = tile X (0..MAP_WIDTH-1), d1 = tile Y (0..CurrentMapHeight-1)
; Preserves: all registers (PUSHM/POPM d0-d2/d7/a0-a3).
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
    tst.w       Actor_HasFalled(a3)         ; skip mid-fall actors (drawn mid-fall by ActionFallActors)
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
; ActorDrawStatic  -  Draw an actor at its current tile position
;
; Blits the actor's sprite tile into DisplayScreen at its tile-aligned position.
; Used to redraw an actor after it has landed at a new position.
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
;==============================================================================

ActorDrawStatic:
    move.w      d7,-(sp)
    move.w      Actor_SpriteOffset(a3),d0
    move.w      Actor_Y(a3),d2
    move.w      Actor_X(a3),d3
    bsr         TilemapBlitSingleTile

    ; Re-stamp foreground over settled actor tile
    move.w      Actor_X(a3),d0
    lsl.w       #4,d0
    move.w      Actor_Y(a3),d1
    lsl.w       #4,d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox

    ; Submerge check
    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         TilemapSubmergeTile

.ads_skip:
    clr.w       Actor_Dirty(a3)            ; tile is now correctly displayed
    move.w      (sp)+,d7
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
;
; Destroys: none (preserves all registers)
;==============================================================================

RestoreBackgroundTile:
    PUSHM       d0-d2/a0-a1

    ; Bounds check col and row
    tst.w       d0
    bmi         .rbt_skip
    cmp.w       CurrentMapWidth(a5),d0
    bge         .rbt_skip
    tst.w       d1
    bmi         .rbt_skip
    cmp.w       CurrentMapHeight(a5),d1
    bge         .rbt_skip

    ; Screen offset = ((row & 15) * 2560) + (col * 2)
    move.w      d1,d2
    andi.w      #RING_BUFFER_ROW_MASK,d2
    mulu.w      #TILEMAP_ROW_STRIDE,d2  ; row * 2560
    moveq       #0,d1
    move.w      d0,d1
    add.w       d1,d1                   ; col * 2
    add.l       d1,d2

    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1
    adda.l      d2,a0
    adda.l      d2,a1

    WAITBLIT
    move.w      #MINTERM_COPY,BLTCON0(a6)      ; D = A (copy pristine tile from NonDisplayScreen)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)  ; word-aligned 16px tile
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTAMOD(a6) ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTDMOD(a6) ; 40 - 2 = 38
    move.l      a0,BLTAPT(a6)           ; source (NonDisplayScreen)
    move.l      a1,BLTDPT(a6)           ; dest (DisplayScreen)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|(TILEMAP_TILE_BYTES/2),BLTSIZE(a6) ; 64 lines x 1 word

    ; Mirror restore to Row + 16 in DisplayScreen
    adda.l      #16*TILEMAP_ROW_STRIDE,a0
    adda.l      #16*TILEMAP_ROW_STRIDE,a1
    WAITBLIT
    move.l      a0,BLTAPT(a6)           ; source (NonDisplayScreen + 16 rows)
    move.l      a1,BLTDPT(a6)           ; dest (DisplayScreen + 16 rows)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|(TILEMAP_TILE_BYTES/2),BLTSIZE(a6) ; 64 lines x 1 word

    POPM        d0-d2/a0-a1
    bsr         TilemapSubmergeTile    ; apply water effect if restored tile is underwater
    bsr         MarkTileDirty          ; auto-flag for end-of-frame actor/frozen-player redraw
    rts

.rbt_skip:
    POPM        d0-d2/a0-a1
    bsr         MarkTileDirty          ; auto-flag for end-of-frame actor/frozen-player redraw
    rts


;==============================================================================
; ClearActor  -  Erase a moving actor from DisplayScreen
;
; Uses PrevX/PrevY tile position PLUS XDec/YDec sub-tile offsets to compute
; the exact WorldX and WorldY, then restores from NonDisplayScreen.
;
; On entry:
;   a3 = actor structure pointer
;   a5, a6 as usual
;
; Destroys: none (preserves all registers)
;==============================================================================

ClearActor:
    PUSHM       d0-d3/a0-a1

    ; Compute WorldX = PrevX * 16 + XDec
    move.w      Actor_PrevX(a3),d0
    lsl.w       #4,d0
    add.w       Actor_XDec(a3),d0

    ; Compute WorldY = PrevY * 16 + YDec
    move.w      Actor_PrevY(a3),d1
    lsl.w       #4,d1
    add.w       Actor_YDec(a3),d1

    bsr         TilemapErase16x16Actor

    POPM        d0-d3/a0-a1
    rts
