
;==============================================================================
; AMIGA GAME ENGINE
; levelutils.asm  -  Level Rendering and Map Initialisation
;==============================================================================
;
; Handles everything related to drawing the game level into the screen buffers:
;
;   Level initialisation:
;     LevelInit        - clear buffers, load assets, build all map arrays
;     SetLevelAssets   - decompress correct tile set, set palette
;     WallPaperLoadBase  - copy base/border template into wallpaper arrays
;     WallPaperLoadLevel - copy level data from LevelData into GameMap/WallpaperWork
;     WallPaperWalls     - build tile-type array (WallpaperWork) from GameMap
;
; Blitter background:
;   The 68000's internal speed is limited by its bus cycle time.  The Amiga's
;   custom Blitter chip performs DMA-driven block copies far faster.  All tile
;   rendering uses the Blitter with WAITBLIT between operations.
;
;   Blitter operation used for tiles (minterm $fca = A&B|~A&C):
;     A = mask  (TileMask or pre-computed)
;     B = tile  (TileSet data)
;     C = destination  (current screen content)
;     D = destination
;   Result: where mask A=1, D = tile (B); where mask A=0, D = background (C).
;   This achieves transparent blitting.
;
; Register convention:
;   a6 = $dff000 (CUSTOM)   a5 = Variables base
;
;==============================================================================

;==============================================================================
; LevelInit  -  Initialise all state for a new level
;
; Sequence:
;   1. TurboClear NonDisplayScreen (blank starting canvas)
;   2. Clear Player_Status (inactive until placed)
;   3. SetLevelAssets: decompress tile set, set palette
;   4. GenTileMask: build blitter masks from tile graphics
;   5. Seed the random number generator from LevelId (for deterministic wall variants)
;   6. WallPaperLoadBase: load border/template row into GameMapCeiling + WallpaperWork
;   7. WallPaperLoadLevel: copy level data from LevelData into GameMap + WallpaperWork
;   8. WallPaperWalls: convert GameMap BLOCK_SOLID cells into wall tile types
;   9. InitGameObjects: scan GameMap, create actor structs for all objects
;==============================================================================

LevelInit:
    ; Clear the save screen buffer (background)
    lea           NonDisplayScreen,a0
    move.l        #LEVEL_SCREEN_SIZE,d7
    bsr           TurboClear

    ; Clear player state until initialized from the level map
    lea           Player(a5),a0
    clr.w         Player_Status(a0)      ; Player inactive
    clr.w         Player_X(a0)           ; Clear tile position X
    clr.w         Player_Y(a0)           ; Clear tile position Y
    clr.w         Player_XDec(a0)        ; Clear sub-tile X offset
    clr.w         Player_YDec(a0)        ; Clear sub-tile Y offset
    clr.w         Player_PrevX(a0)       ; Clear previous X
    clr.w         Player_PrevY(a0)       ; Clear previous Y
    clr.w         Player_PrevDrawn(a0)   ; Clear previous drawn flag
    clr.w         Player_NextX(a0)       ; Clear destination X
    clr.w         Player_NextY(a0)       ; Clear destination Y
    clr.w         Player_ActionCount(a0) ; Clear action countdown
    clr.w         Player_AnimFrame(a0)   ; Clear animation frame
    move.w        #1,Player_Facing(a0)   ; Set facing to right
    clr.w         Player_OnLadder(a0)    ; Clear ladder state
    clr.w         Player_DirectionX(a0)  ; Clear directional input
    clr.w         Player_DirectionY(a0)  ; Clear directional input
    clr.w         Player_Fallen(a0)      ; Clear falling flag
    clr.w         Player_ActionFrame(a0) ; Clear action frame counter

    ; bsr           SetLevelAssets         ; legacy tile set decompression removed
    ; bsr           GenTileMask            ; legacy tile mask generation removed

    ; Seed the PRNG from the level ID so wall tile randomisation is reproducible.
    ; The magic constant $BABEFEED gives a good initial spread.
    move.l        #$BABEFEED,d0
    move.b        LevelId+1(a5),d0       ; mix in low byte of level ID
    move.l        d0,RandomSeed(a5)      ; store as new seed

    clr.w         CloudActorsCount(a5)   ; reset cloud animation list for new level
    clr.w         DirtActorsCount(a5)    ; reset dirt animation list for new level

    ; Legacy 88-byte level loading and border setup bypassed for Tiled .tmx levels
    ; bsr           WallPaperLoadBase
    ; bsr           WallPaperLoadLevel
    ; bsr           LevelInitPlayers

    move.w        #WALL_PAPER_WIDTH,CurrentMapWidth(a5)
    move.w        #WALL_PAPER_HEIGHT,CurrentMapHeight(a5)
    move.w        #WALL_PAPER_SIZE,CurrentMapSize(a5)

    clr.l         CurrentLevelDef(a5)    ; default: no custom LevelDef
    move.w        #0,LevelMinCameraY(a5) ; default min camera Y
    move.w        #464,LevelMaxCameraY(a5) ; default max camera Y
    move.w        #CAM_MARGIN_TOP,LevelCamMarginTop(a5)
    move.w        #CAM_MARGIN_BOTTOM,LevelCamMarginBottom(a5)

    ; Check if current LevelId has an entry in LevelTable:
    move.w        LevelId(a5),d0
    cmp.w         #LEVEL_TABLE_COUNT,d0
    bge           .not_custom_level      ; past table count -> use legacy maps
    lsl.w         #2,d0                  ; d0 = LevelId * 4
    lea           LevelTable,a2
    movea.l       (a2,d0.w),a2           ; a2 = pointer to Level_NN_Def
    cmpa.w        #0,a2
    beq           .not_custom_level      ; null entry -> use legacy maps
    move.l        a2,CurrentLevelDef(a5) ; store active LevelDef pointer

    ; Set map dimensions from LevelDef
    move.w        LevelDef_Width(a2),d0
    move.w        d0,CurrentMapWidth(a5)
    move.w        LevelDef_Height(a2),d1
    move.w        d1,CurrentMapHeight(a5)
    mulu.w        d0,d1
    move.w        d1,CurrentMapSize(a5)

    ; Load dynamic camera bounds and deadzone margins from LevelDef
    move.w        LevelDef_MinCameraY(a2),LevelMinCameraY(a5)
    move.w        LevelDef_MaxCameraY(a2),LevelMaxCameraY(a5)
    move.w        LevelDef_CamMarginTop(a2),LevelCamMarginTop(a5)
    move.w        LevelDef_CamMarginBottom(a2),LevelCamMarginBottom(a5)
    move.w        LevelDef_InitialCameraY(a2),TilemapCameraY(a5)

    ; Copy 1D GameMap binary (LevelDef_GameMap) into GameMap(a5)
    movea.l       LevelDef_GameMap(a2),a0
    lea           GameMap(a5),a1
    move.w        CurrentMapSize(a5),d0
    subq.w        #1,d0
.copy_gamemap:
    move.b        (a0)+,(a1)+
    dbra          d0,.copy_gamemap

    ; Setup Player from LevelDef
    lea           Player(a5),a0
    move.w        #1,Player_Status(a0)
    move.w        LevelDef_P1Col(a2),d0
    move.w        d0,Player_X(a0)
    lsl.w         #4,d0
    move.w        d0,Player_PixelX(a0)       ; cache X * 16
    clr.w         Player_XDec(a0)            ; tile-aligned
    move.w        LevelDef_P1Row(a2),d0
    move.w        d0,Player_Y(a0)
    lsl.w         #4,d0
    move.w        d0,Player_PixelY(a0)       ; cache Y * 16
    clr.w         Player_YDec(a0)
    move.w        LevelDef_P1Facing(a2),Player_Facing(a0)

    ; Apply BOB offset based on SelectedPlayer (0 = Price/frame 48, 1 = Cole/frame 0)
    move.w        #48,Player_BobOffset(a0)    ; default: Dr. Price
    move.w        #31,Player_FrozenBobBase(a0)
    move.w        #34,Player_LadderFreezeId(a0)
    move.b        #BLOCK_PLAYERSTART,Player_BlockId(a0)
    move.b        #BLOCK_PLAYERLADDER,Player_LadderId(a0)
    tst.w         SelectedPlayer(a5)
    beq.s         .not_custom_level
    clr.w         Player_BobOffset(a0)       ; Sgt. Cole
    move.w        #29,Player_FrozenBobBase(a0)
    move.w        #33,Player_LadderFreezeId(a0)
    move.b        #BLOCK_PLAYERSTART,Player_BlockId(a0)
    move.b        #BLOCK_PLAYERLADDER,Player_LadderId(a0)
.not_custom_level:

    bsr           WallPaperWalls         ; convert BLOCK_SOLID to wall tile graphics
    bsr           WallpaperMakeAcid      ; stamp TILE_ACID over BLOCK_ACID cells
    bsr           InitGameObjects        ; create actors for all game objects in map
    bsr           LevelInitEnemies       ; populate ActiveEnemies table from LevelDef
    rts

;==============================================================================
; SetLevelAssets  -  Load and activate the correct tile set for the current level
;
; 1. Look up the tile set index for LevelId in LevelAssetSet[].
; 2. Load the first 16 palette colours from the corresponding tiles_N.pal.
; 3. Load the second 16 palette colours from sprites.pal (actor sprites).
; 4. Decompress the corresponding tiles_N.pak into TileSet (Chip RAM buffer).
; 5. Store TilesetPtr pointing at TileSet.
;
; The copper list palette section (cpPal) is updated in two halves:
;   colours  0-15: from TilesPal0/1/2/3/4 (background / wall tiles)
;   colours 16-31: from SpritePal (actor / player sprites)
;
; Tile set palette files are SCREEN_COLORS*2 bytes each (32 words = 64 bytes).
; The two halves are each SCREEN_COLORS/2 = 16 entries.
;==============================================================================

SetLevelAssets:
    ; Legacy 16x24 tileset decompression removed — Tiled levels use LevelDef_TilesetRaw & Palette.
    rts

;==============================================================================
; WallPaperLoadLevel  -  Copy level data from LevelData into game maps
;
; Reads MAP_WIDTH x MAP_HEIGHT bytes from the level data file and places them
; into the interior cells of both WallpaperWork and GameMap (the live game map).
;
; The map data is MAP_WIDTH (11) columns wide, but WallpaperWork is
; WALL_PAPER_WIDTH (14) columns wide (with a 1-cell solid border on each side
; and one column for the right-side UI area).
;
; The +1 offset on the destination advances past the left border column so
; that map data is written into columns 1..11, leaving columns 0 and 12-13
; as the solid/background border.
;
; The outer loop iterates MAP_HEIGHT (8) rows.
; The inner loop copies MAP_WIDTH (11) bytes, then skips 3 bytes
; (WALL_PAPER_WIDTH - MAP_WIDTH - 1 = 14 - 11 - 1 = 2, but +1 offset = 3 skip)
; to step over the remaining columns to the next row start.
;
; After building WallpaperWork, the same data is also copied to GameMap
; (the live game map used for collision detection and actor tracking).
;==============================================================================

WallPaperLoadLevel:
    ; Legacy 88-byte level loading removed — Tiled .tmx levels load via LevelDef_GameMap.
    rts

;==============================================================================
; LevelInitPlayers  -  Scan GameMap for player start markers; set Player_X/Y
;
; Called from LevelInit immediately after WallPaperLoadLevel so that both
; player structures have correct tile coordinates before LevelIntroSetup reads
; them (and before InitGameObjects creates actor slots).
;
; Scans the full WALL_PAPER_WIDTH x WALL_PAPER_HEIGHT grid.  When it finds
; BLOCK_PLAYERSTART (7) it writes the tile column and row into Player_X / Player_Y.
;
; Preserves all registers (PUSHALL / POPALL).
;==============================================================================

LevelInitPlayers:
    PUSHALL

    lea         GameMap(a5),a0          ; a0 -> start of live game map (14x9 bytes)
    moveq       #0,d2                   ; d2 = current row (0..WALL_PAPER_HEIGHT-1)

.row_loop
    moveq       #0,d1                   ; d1 = current column (0..WALL_PAPER_WIDTH-1)

.col_loop
    moveq       #0,d0
    move.b      (a0)+,d0                ; d0 = block type at (d1, d2)

    cmp.b       #BLOCK_PLAYERSTART,d0
    bne.s       .next_col

    ; Found Player start — write tile coords to Player struct
    lea         Player(a5),a1
    move.w      d1,Player_X(a1)
    move.w      d2,Player_Y(a1)

.next_col
    addq.w      #1,d1
    cmp.w       #WALL_PAPER_WIDTH,d1
    blt         .col_loop

    addq.w      #1,d2
    cmp.w       #WALL_PAPER_HEIGHT,d2
    blt         .row_loop

    POPALL
    rts

;==============================================================================
; WallpaperMakeAcid  -  Stamp TILE_ACID into WallpaperWork for acid cells
;
; Must run AFTER WallPaperWalls (which rewrites every non-solid cell of
; WallpaperWork as TILE_BACK / wall tiles).
; GameMap still holds the original BLOCK values at this point, so scan it and
; overwrite the corresponding WallpaperWork cells.
;
; WallpaperWork keeps TILE_ACID for the whole level: it is the permanent
; "is this cell an acid pool" truth used by the dissolve checks in player.asm.
; (GameMap's BLOCK_ACID byte is temporarily replaced by an actor's type while
; that actor occupies the pool, and restored by ActorDissolveInAcid.)
;==============================================================================

WallpaperMakeAcid:
    lea           GameMap(a5),a0
    lea           WallpaperWork(a5),a1
    move.w        CurrentMapSize(a5),d7
    subq.w        #1,d7
.scan
    cmp.b         #BLOCK_ACID,(a0)+
    bne           .next
    move.b        #TILE_ACID,(a1)
.next
    addq.l        #1,a1
    dbra          d7,.scan
    rts


;==============================================================================
; WallPaperWalls  -  Convert BLOCK_SOLID cells into wall tile variants
;
; Scans WallpaperWork row by row (WALL_PAPER_HEIGHT rows, WALL_PAPER_WIDTH cols).
; Finds runs of consecutive BLOCK_SOLID cells and assigns the correct wall
; tile types (single, left-cap, interior variants, right-cap, background).
;
; Non-solid cells are replaced with TILE_BACK (28 = background tile) in place.
;
; For each row:
;   Track the start of a solid run in a1.
;   Count run length in d0.
;   On first solid cell: mark the cell before as TILE_BACK; record run start.
;   On end of run (non-solid or end of row): call WallDespatch.
;
; After processing, WallpaperWork contains TILE_xxx values instead of BLOCK_xxx.
;==============================================================================

WallPaperWalls:
    lea           WallpaperWork(a5),a0
    moveq         #WALL_PAPER_HEIGHT-1,d7

.lineloop
    move.l        a0,a1                  ; a1 -> start of current row

    moveq         #WALL_PAPER_WIDTH-1,d6
    moveq         #0,d0                  ; d0 = current wall run length

.nexttile
    cmp.b         #BLOCK_SOLID,(a0)+     ; is this cell solid? (advance a0 past it)
    beq           .iswall

    ; Non-solid cell: dispatch any in-progress wall run
    bsr           WallDespatch
    bra           .next

.iswall
    ; First solid cell of a new run?
    tst.w         d0
    bne           .skipptr

    ; Start of run: write TILE_BACK into the cell BEFORE the run starts
    ; (because a0 was advanced, a0-1 is the current solid cell; a1 is being
    ;  maintained as the "run start" pointer and advanced here too).
    move.b        #28,(a1)+              ; TILE_BACK before run
    move.l        a0,a1                  ; a1 -> first solid cell (a0 is now past it)
    subq.l        #1,a1

.skipptr
    addq.w        #1,d0                  ; extend run length
    tst.w         d6
    bne           .next
    bsr           WallDespatch           ; end of row - dispatch remaining run

.next
    dbra          d6,.nexttile
    dbra          d7,.lineloop
    rts


;==============================================================================
; WallDespatch  -  Assign wall tile types to a completed horizontal run
;
; On entry:
;   d0 = number of solid cells in the run (0 = nothing to do)
;   a1 = pointer to the first cell of the run in WallpaperWork
;   AssetSet(a5) = current tile set index (0 = patterned walls; others = fully random)
;
; For tile set 0 (structured walls):
;   d0 = 0: write TILE_BACK (background) and return
;   d0 = 1: write TILE_WALLSINGLE
;   d0 = 2: write TILE_WALLLEFT + TILE_WALLRIGHT
;   d0 > 2: write TILE_WALLLEFT, random interior variants (6 choices), TILE_WALLRIGHT
;
; For tile sets 1-4 (fully random):
;   Every cell gets a fully random tile from 0-8 (all wall types).
;
; After dispatching, d0 is reset to 0 (ready for next run).
;==============================================================================

WallDespatch:
    tst.w         d0
    beq           .zero                  ; run length 0 = background cell

    tst.w         AssetSet(a5)           ; tile set 0 = structured; others = random
    bne           .fullrandom

    ; Structured wall (tile set 0)
    cmp.w         #1,d0
    beq           .isone                 ; single-cell wall

    cmp.w         #2,d0
    bne           .long                  ; 3+ cells

    ; Two-cell wall
    move.b        #TILE_WALLLEFT,(a1)+   ; left cap
    move.b        #TILE_WALLRIGHT,(a1)+  ; right cap
    moveq         #0,d0
    rts

.long
    ; Three-or-more-cell wall
    subq.w        #2,d0                  ; d0 = number of interior cells
    move.b        #TILE_WALLLEFT,(a1)+   ; left end-cap

.fill
    PUSH          d0
    RANDOMWORD                           ; generate random value in d0
    moveq         #0,d2
    move.w        d0,d2
    POP           d0
    divu          #6,d2                  ; d2 = remainder (0-5) + quotient in high word
    swap          d2                     ; bring remainder to low word
    add.w         #TILE_WALLA,d2         ; map to one of 6 interior tile variants

    move.b        d2,(a1)+               ; write random interior tile
    subq.w        #1,d0
    bne           .fill

    move.b        #TILE_WALLRIGHT,(a1)+  ; right end-cap
    rts

.isone
    move.b        #TILE_WALLSINGLE,(a1)+ ; isolated single-cell wall
    moveq         #0,d0
    rts

.zero
    move.b        #TILE_BACK,(a1)+       ; background / empty
    rts

.fullrandom
    ; Fully random tile for each cell (tile sets 1-4)
    PUSH          d0
    RANDOMWORD
    moveq         #0,d2
    move.w        d0,d2
    POP           d0
    divu          #9,d2                  ; choose from 9 wall tile variants (0-8)
    swap          d2

    move.b        d2,(a1)+               ; write random tile
    subq.w        #1,d0
    bne           .fullrandom
    rts


;==============================================================================
; WallPaperLoadBase  -  Load the border/template into GameMapCeiling and WallpaperWork
;
; Copies the static border template:
;   WallpaperBaseTop -> GameMapCeiling (the solid ceiling row, WALL_PAPER_WIDTH bytes)
;   WallpaperBase    -> WallpaperWork  (the 9-row frame with solid left/right borders)
;
; Both source arrays are defined in the data_fast section of main.asm.
; WallpaperBaseTop is all BLOCK_SOLID (5) - the full-width top border.
; Fills WallpaperCheat (the hidden bottom dummy row) with TILE_BACK.
;==============================================================================

WallPaperLoadBase:
    ; Legacy border templates removed — Tiled .tmx levels define their own map geometry.
    rts

;==============================================================================
; LevelIntroSetup  -  Initialise the level-start star animation
;
; Called from DrawMap immediately after DrawInitialPlayers.  Sets StarOriginX/Y
; to the corner opposite the active player's start tile and StarTargetX/Y to
; that player's tile, then delegates common animation init to StarAnimBegin:
;
;   - Reads the active player's start tile from Player (Player_X/Y).
;   - Determines the opposite corner:
;       Player left  (X < 7)  → star starts from right edge (X = 13)
;       Player right (X >= 7) → star starts from left  edge (X =  0)
;       Player top   (Y < 5)  → star starts from bottom    (Y =  8)
;       Player bottom(Y >= 5) → star starts from top       (Y =  0)
;   - Hides all hardware sprites (ClearSprites).
;   - Calls StarAnimBegin (clears trail pool, draws initial star at origin).
;   - Sets ActionStatus = ACTION_INTRO.
;
; On entry:  a5, a6 as usual.
;==============================================================================

LevelIntroSetup:
    PUSHALL

    ; Ensure camera viewport is positioned for player start (immediate snap)
    bsr         TilemapSnapCamera

    ; Set up active player BOB
    lea         Player(a5),a4

    ; Check if start position is on a ladder
    move.w      Player_Y(a4),d1
    mulu        #WALL_PAPER_WIDTH,d1
    add.w       Player_X(a4),d1
    lea         GameMap(a5),a0
    move.b      (a0,d1.w),d1
    cmp.b       #BLOCK_LADDER,d1
    beq.s       .lis_is_ladder
    cmp.b       #BLOCK_PLAYERLADDER,d1
    beq.s       .lis_is_ladder
    cmp.b       Player_LadderId(a4),d1
    bne.s       .lis_check_ladder_state
.lis_is_ladder:
    move.w      #1,Player_OnLadder(a4)

.lis_check_ladder_state:
    moveq       #0,d0
    tst.w       Player_OnLadder(a4)
    bne         .lis_ladder
    tst.w       Player_Facing(a4)
    bpl         .lis_show
    move.w      #PLAYER_LEFT_OFFSET,d0
    bra         .lis_show
.lis_ladder
    move.w      #PLAYER_LADDER_IDLE,d0
.lis_show
    bsr         ShowPlayer

    ; Start gameplay immediately in IDLE state
    move.w      #ACTION_IDLE,ActionStatus(a5)
    clr.w       SlowMode(a5)
    clr.w       SlowModeHold(a5)
    clr.w       PrevKeyS(a5)
    clr.w       DebugOverlayActive(a5)
    lea         Keys,a0
    clr.b       KEY_S(a0)
    clr.b       KEY_A(a0)
    clr.b       KEY_D(a0)

    POPALL
    rts

;==============================================================================
; Level Wipe Transition  -  Screen wipe effect at end of each level
;
;
; LevelTransitionRun  - states 3/4/5/6 handler, called every VBlank from
;                       GameStatusRun.  Dispatches on GameStatus:
;                       LEVEL_INIT   : setup; first VBlank → LEVEL_WIPE.
;                       LEVEL_WIPE  : blits WIPE_SPEED tiles black per frame;
;                                     when done sets WipeHoldTick, → LEVEL_HOLD.
;                       LEVEL_HOLD  : counts down WipeHoldTick; calls
;                                     LevelRevealSetup when zero, → LEVEL_REVEAL.
;                       LEVEL_REVEAL: copies WIPE_SPEED tiles from NonDisplayScreen;
;                                     when done calls DrawStaticActors, → GameRun.
;
; LevelRevealSetup    - called from LevelTransitionRun when hold expires.
;                       Builds next level into NonDisplayScreen, reverses WipeTileX/Y,
;                       and advances to LEVEL_REVEAL (5).
;
; Fill routines   - each fills WipeTileX and WipeTileY with 126 tile coords
;                   (WALL_PAPER_SIZE = 14x9) in the desired visual order.
;
; WipeOppositeTable - byte lookup: given a pattern index, returns the index of
;                     its directional inverse for use by a future reveal effect.
;==============================================================================


;==============================================================================
; LevelTransitionRun  -  Per-frame level transition handler
;
; Called every VBlank from GameStatusRun for states 3, 4, and 5.
; Dispatches to the appropriate phase based on GameStatus.
; No player input is processed during any transition state.
;
; LEVEL_INIT (3) - first VBlank after LevelSetup
;
; LEVEL_WIPE (4) - blit WIPE_SPEED tiles black per frame until all done,
;                  then set WipeHoldTick and advance to LEVEL_HOLD (4).
;
; LEVEL_HOLD (5) - count down WipeHoldTick each frame; when zero call
;                  LevelRevealSetup which builds the new level and advances
;                  to LEVEL_REVEAL (5).
;
; LEVEL_REVEAL (6) - copy WIPE_SPEED tiles per frame from NonDisplayScreen to
;                    DisplayScreen (reverse-wipe).  When done, call
;                    DrawStaticActors and return to GameRun (2).
;==============================================================================

LevelTransitionRun:
    move.w      GameStatus(a5),d5       ; d5 = current transition state (3/4/5)
    cmp.w       #LEVEL_WIPE,d5
    beq         .wipe_phase
    cmp.w       #LEVEL_HOLD,d5
    beq         .hold_phase
    cmp.w       #LEVEL_REVEAL,d5
    beq         .reveal_phase

    ; -----------------------------------------------------------------------
    ; LEVEL_INIT phase: setup for level transition effect
    ; -----------------------------------------------------------------------
    bsr         LevelSetup
    move.w      #LEVEL_WIPE,GameStatus(a5)
    rts

.wipe_phase
    ; -----------------------------------------------------------------------
    ; LEVEL_WIPE phase: blit WIPE_SPEED tiles black this frame
    ; -----------------------------------------------------------------------
    move.w      WipeTilesDone(a5),d7
    cmp.w       #WALL_PAPER_SIZE,d7
    bge         .wipe_done

    moveq       #WIPE_SPEED-1,d6
.wipe_loop
    cmp.w       #WALL_PAPER_SIZE,d7
    bge         .wipe_blit_done

    clr.l       d0
    lea         WipeTileX(a5),a0
    move.b      (a0,d7.w),d0            ; d0 = tile X (0..13)
    clr.l       d1
    lea         WipeTileY(a5),a0
    move.b      (a0,d7.w),d1            ; d1 = tile Y (0..8)

    bsr         WipeBlitBlack           ; zero-fill this tile (black)

    addq.w      #1,d7
    dbra        d6,.wipe_loop

.wipe_blit_done
    move.w      d7,WipeTilesDone(a5)
    rts

.wipe_done
    ; If wiping after level completion, skip the intro banner and go straight
    ; to the level complete screen via minimal hold
    tst.w       LevelCompleteWipe(a5)
    beq         .show_banner
    move.w      #1,WipeHoldTick(a5)
    move.w      #LEVEL_HOLD,GameStatus(a5)
    rts

.show_banner
    ; All tiles blitted black - draw the chapter/level banner (if any) onto
    ; the now-blank DisplayScreen, then start the hold countdown (extended if
    ; a banner was drawn, so the player has time to read it), advance to
    ; LEVEL_HOLD.
    bsr         LevelBannerShow         ; d0 = suggested WipeHoldTick (PAL-scaled)
    move.w      d0,WipeHoldTick(a5)
    move.w      #LEVEL_HOLD,GameStatus(a5)
    rts

    ; -----------------------------------------------------------------------
    ; LEVEL_HOLD phase: count down hold ticks, then trigger reveal setup
    ; -----------------------------------------------------------------------
.hold_phase
    move.w      WipeHoldTick(a5),d0
    beq         .hold_done
    subq.w      #1,d0
    move.w      d0,WipeHoldTick(a5)
    rts

.hold_done
    ; Hold complete - check whether to show the level-complete screen or reveal a new level
    tst.w       LevelCompleteWipe(a5)
    beq         .normal_reveal
    clr.w       LevelCompleteWipe(a5)
    move.w      #LEVEL_COMPLETE_SETUP,GameStatus(a5)
    rts
.normal_reveal
    ; Foreign-copper entry (title screen / level-complete screen): the wipe has
    ; blanked the whole display to the outgoing screen's background.  Prepare the
    ; game copper (cpTest) WHILE the old copper is still showing that blank frame,
    ; then switch — so the swap (geometry + palette + banner-WAIT removal) is
    ; invisible.  No in-place clear of the live buffer: that was the noise source.
    tst.w       EnterGameCopper(a5)
    beq         .nr_reveal
    clr.w       EnterGameCopper(a5)
    bsr         GameCopperInit          ; patch cpTest bitplane ptrs + default pal, hide sprites
    bsr         LevelRevealSetup        ; build level; SetLevelAssets loads the real palette into cpPal
   ; bsr         VHS_Init                ; arm VHS distortion region (PAL/NTSC)
    move.l      #-1,ScreenMemEnd        ; re-arm the screen overrun sentinel
    move.l      #cpTest,COP1LC(a6)      ; switch to the fully-prepared game copper (black -> black)
    move.w      #0,COPJMP1(a6)
    move.w      #LEVEL_REVEAL,GameStatus(a5)
    rts

.nr_reveal
    ; Level-to-level: the game copper is already live; just build and reveal.
    bsr         LevelRevealSetup        ; primes WipeTileX/Y for reverse reveal
    move.w      #LEVEL_REVEAL,GameStatus(a5)
    rts

    ; -----------------------------------------------------------------------
    ; LEVEL_REVEAL phase: copy WIPE_SPEED tiles from NonDisplayScreen to DisplayScreen
    ; -----------------------------------------------------------------------
.reveal_phase
    ; Tiled levels have the full 42 rows pre-rendered into DisplayScreen by TilemapInit;
    ; skip the legacy 24x24 tile-by-tile reveal to avoid delays or buffer stomping.
    tst.l       CurrentLevelDef(a5)
    bne         .reveal_done

    move.w      WipeTilesDone(a5),d7
    cmp.w       #WALL_PAPER_SIZE,d7
    bge         .reveal_done

    moveq       #WIPE_SPEED-1,d6
.reveal_loop
    cmp.w       #WALL_PAPER_SIZE,d7
    bge         .reveal_blit_done

    clr.l       d0
    lea         WipeTileX(a5),a0
    move.b      (a0,d7.w),d0            ; d0 = tile X (0..13)
    clr.l       d1
    lea         WipeTileY(a5),a0
    move.b      (a0,d7.w),d1            ; d1 = tile Y (0..8)

    bsr         RestoreBackgroundTile        ; copy tile from NonDisplayScreen -> DisplayScreen

    addq.w      #1,d7
    dbra        d6,.reveal_loop

.reveal_blit_done
    move.w      d7,WipeTilesDone(a5)
    rts

.reveal_done
    ; All tiles revealed - restore actor tiles, initialize Level and resume gameplay
    bsr         DrawPlayersAndActors
    bsr         LevelIntroSetup
    bsr         AudioPlayLevelMusic     ; start MOD music as level becomes playable

    move.w      #GAME_RUN,GameStatus(a5)       ; return to GameRun (state 2)
    rts

;==============================================================================
; DrawPlayersAndActors  -  Draw static actors and initial players at level start
;==============================================================================

DrawPlayersAndActors:
    bsr           DrawStaticActors       ; blit actor tiles on top of DisplayScreen
    bsr           DrawInitialPlayers     ; draw both players at level start
    rts

;==============================================================================
; DrawInitialPlayers  -  Set up the active player BOB frame at level start
;
; Called from DrawMap after actors are drawn, immediately before LevelIntroSetup.
; Positions the active player (Status=1) via ShowPlayer.
;==============================================================================

DrawInitialPlayers:
    lea         Player(a5),a4
    cmp.w       #1,Player_Status(a4)
    bne         .init_done
    moveq       #0,d0
    bsr         ShowPlayer

.init_done
    rts

;==============================================================================
; LevelBannerShow  -  Draw the chapter title (if this is a chapter's first
; level) and the level's own name+lesson (if defined) onto DisplayScreen.
;
; Called once from LevelTransitionRun .wipe_done, at the exact moment the
; wipe has just finished blacking out the whole screen and before
; LevelRevealSetup rebuilds the next level into NonDisplayScreen only —
; DisplayScreen stays untouched for the entire LEVEL_HOLD countdown, so
; whatever is drawn here is what the player reads during the hold.
;
; Text data (ChapterLevelIdx/NamePtr, LevelNamePtr/LessonPtr1/Ptr2) is
; generated into leveltext.asm by tools/ac_levels.py's `gentext` command —
; the LEVELS/CHAPTERS tables in that script are the source of truth; never
; hand-edit leveltext.asm.  Levels without an entry (not yet AC-authored)
; get null pointers here and fall through to the short default hold.
;
; Out: d0.w = suggested WipeHoldTick value (PAL-frame-scaled) - long enough
;      to read whatever was drawn, or WIPE_HOLD_TICKS if nothing was shown.
;==============================================================================

LevelBannerShow:
    PUSHM       d1-d3/a0-a3
    moveq       #0,d3                   ; 0 = nothing shown, 1 = name, 2 = name+chapter

    ; Check if active level has a LevelDef with custom Title/Hint strings
    move.l      CurrentLevelDef(a5),d0
    beq.s       .lbs_legacy
    movea.l     d0,a2

    ; Draw LevelDef Title string if present
    move.l      LevelDef_TitleStr(a2),d0
    beq.s       .lbs_def_notitle
    movea.l     d0,a0
    tst.b       (a0)
    beq.s       .lbs_def_notitle
    move.w      #64,d1                  ; Y pixel row
    lea         CHAR_BLTStringYellow,a3
    bsr         DrawCenteredLine
    moveq       #2,d3                   ; banner shown
.lbs_def_notitle:

    ; Draw LevelDef SubTitle string if present
    move.l      LevelDef_SubTitleStr(a2),d0
    beq.s       .lbs_def_nohint
    movea.l     d0,a0
    tst.b       (a0)
    beq.s       .lbs_def_nohint
    move.w      #96,d1                  ; Y pixel row
    lea         CHAR_BLTStringHud,a3
    bsr         DrawCenteredLine
    tst.w       d3
    bne.s       .lbs_def_nohint
    moveq       #1,d3
.lbs_def_nohint:
    bra         .lbs_noname

.lbs_legacy:
    ; Legacy 10-level banner lookup removed (replaced by LevelDef title/subtitle above)
    bra         .lbs_noname

.lbs_noname
    ; --- Hold duration follows from what was actually shown ---
    moveq       #WIPE_HOLD_TICKS,d0
    tst.w       d3
    beq         .lbs_scale              ; nothing shown: default short hold
    cmp.w       #2,d3
    bne         .lbs_nameonly
    move.w      #CHAPTER_BANNER_HOLD_TICKS,d0
    bra         .lbs_scale
.lbs_nameonly
    move.w      #LEVEL_BANNER_HOLD_TICKS,d0
.lbs_scale
    bsr         ScalePALFrames          ; NTSC: stretch to match real time

    POPM        d1-d3/a0-a3
    rts


;==============================================================================
; DrawCenteredLine  -  Blit one horizontally-centred line of text
;
; On entry:
;   a0 = null-terminated string
;   d1.w = Y pixel row (0..SCREEN_HEIGHT-1)
;   a3 = string-blit routine to call (CHAR_BLTString family: a0=string,
;        a1=destination address; preserves a0, advances a1)
;
; Centres against the 42-character-wide screen (336px / 8px per glyph);
; strings longer than 42 characters are left-aligned (clipped) instead.
;
; Destroys: d0, d2 (d1 consumed for the row computation)
;==============================================================================

DrawCenteredLine:
    PUSHM       d0/d2/a1
    move.l      a0,a1                   ; a1 = scan pointer for the length count
    moveq       #0,d0
.dcl_len
    tst.b       (a1)+
    beq         .dcl_lendone
    addq.w      #1,d0
    bra         .dcl_len
.dcl_lendone
    moveq       #42,d2
    sub.w       d0,d2
    bpl         .dcl_fits
    moveq       #0,d2                   ; too long for the screen: left-align
.dcl_fits
    asr.w       #1,d2                   ; d2 = centred byte column

    mulu        #SCREEN_STRIDE,d1       ; d1 = byte row offset
    add.w       d2,d1
    lea         DisplayScreen,a1
    add.l       d1,a1                   ; a1 = destination address

    jsr         (a3)                    ; blit the line (a0 = string, unchanged)
    POPM        d0/d2/a1
    rts


;==============================================================================
; LevelSetup  -  Initialise and start the level transition
;
; Called from LevelTransitionRun for the LEVEL_INIT phase, immediately after LevelId is incremented.
;
; Actions:
;   1. Reset WipeTilesDone = 0.
;   2. Pick a random wipe pattern using RANDOMWORD and store in WipePattern.
;   3. Call the appropriate WipeFill routine to build WipeTileX/Y arrays.
;   4. Hide all hardware sprites (ClearSprites).
;
; On entry: a5 = Variables base, a6 = CUSTOM.
;==============================================================================

LevelSetup:
    PUSHALL

    ; Initialise wipe counter (WipeHoldTick is set when wipe completes)
    clr.w       WipeTilesDone(a5)

    ; Pick random pattern (0..NUM_WIPE_PATTERNS-1)
    RANDOMWORD                          ; d0.w = pseudo-random value
    and.w       #NUM_WIPE_PATTERNS-1,d0 ; mask to pattern range (power of 2)
    move.w      d0,WipePattern(a5)

    ; Dispatch to the appropriate fill routine via absolute pointer table
    lsl.w       #2,d0                   ; d0 = pattern * 4 (longword table index)
    lea         WipeFillTable(pc),a0
    move.l      (a0,d0.w),a0            ; a0 = fill routine address
    jsr         (a0)                    ; fill WipeTileX and WipeTileY arrays

    ; Hide all hardware sprites during level transition
    bsr         ClearSprites

    POPALL
    rts


;==============================================================================
; LevelRevealSetup  -  Build the new level and arm the reveal pass
;
; Called from LevelTransitionRun when the LEVEL_HOLD countdown reaches zero.
;
; Builds the new level's background into NonDisplayScreen only (CopySaveToStatic
; and DrawStaticActors are skipped so DisplayScreen stays black from the completed wipe).  Then reverses WipeTileX/Y to give the
; directional opposite traversal order for the reveal, resets WipeTilesDone,
; and advances GameStatus to LEVEL_REVEAL.
;
; On entry: a5 = Variables base, a6 = CUSTOM.
;==============================================================================

LevelRevealSetup:
    PUSHALL

    ; draw the new map into the NonDisplayScreen
    bsr         DrawMap

    ; Reset the undo buffer and take the initial level snapshot so the player
    ; can rewind back to this exact state with the first F9 press
    bsr         InitUndoBuffer

    ; Initialise tiles done back to 0
    clr.w       WipeTilesDone(a5)

    ; take the Wipe Pattern (used to clear the last level) to determine
    ; the Reveal pattern - ie the opposite effect
	moveq  #0,d0
	move.b WipePattern(a5),d0
	lea    WipeOppositeTable(pc),a0
	move.b (a0,d0.w),d0              ; d0 = opposite pattern index

    ; Dispatch to the appropriate fill routine via absolute pointer table
    lsl.w       #2,d0                   ; d0 = pattern * 4 (longword table index)
    lea         WipeFillTable(pc),a0
    move.l      (a0,d0.w),a0            ; a0 = fill routine address
    jsr         (a0)                    ; fill WipeTileX and WipeTileY arrays

    POPALL
    rts


;==============================================================================
; LevelInitEnemies  -  Initialize ActiveEnemies array from current LevelDef
;
; Reads spawn records from LevelDef_EnemyList (or Level_01_EnemyList) and
; fills ActiveEnemies in RAM.  Each spawn record contains:
;   dc.w Type, Col, Row, SpawnX, SpawnY, PatrolMinX, PatrolMaxX, Speed
;
; Sets ActiveEnemyCount and clears drawn state.
;==============================================================================

LevelInitEnemies:
    PUSHM       d0-d7/a0-a3
    clr.w       ActiveEnemyCount(a5)

    ; Clear entire ActiveEnemies buffer
    lea         ActiveEnemies(a5),a1
    move.w      #(ei_SIZEOF*MAX_ACTIVE_ENEMIES)/2-1,d7
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
    lea         Level_01_EnemyList,a0

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
    move.w      d0,ei_Type(a1)
    move.w      d3,ei_X(a1)
    move.w      d4,ei_Y(a1)
    move.w      #1,ei_Direction(a1)     ; start moving right (+1)
    move.w      d1,ei_Speed(a1)
    move.w      d5,ei_PatrolMinX(a1)
    move.w      d7,ei_PatrolMaxX(a1)
    clr.w       ei_AnimFrame(a1)
    clr.w       ei_PrevX(a1)
    clr.w       ei_PrevY(a1)
    clr.w       ei_Drawn(a1)

    lea         ei_SIZEOF(a1),a1
    addq.w      #1,d6
    bra.s       .populate_loop

.finish_init:
    move.w      d6,ActiveEnemyCount(a5)

.done_init_enemies:
    POPM        d0-d7/a0-a3
    rts

