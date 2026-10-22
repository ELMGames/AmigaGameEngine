
;==============================================================================
; AMIGA GAME ENGINE
; levelutils.asm  -  Level Rendering, TMX Level Loading and Map Initialisation
;==============================================================================
;
; Handles loading, unpacking, and entity population for multi-layer TMX levels:
;
; Level Initialisation:
;   LevelInit        - unpack LevelDef from LevelTable, load 1D GameMap,
;                      configure dynamic camera bounds, player spawn coordinates,
;                      and populate active entity tables (enemies, friends, oxygen).
;   LevelInitEnemies - unpack LevelDef_Enemies table into ActiveEnemies pool
;   LevelInitFriends - unpack LevelDef_Friends table into ActiveFriends pool
;   LevelInitOxygen  - unpack LevelDef_Oxygen table into ActiveOxygen pool
;   WallPaperWalls   - convert BLOCK_SOLID cells into wall tile variants
;   InitGameObjects  - scan map cells to create interactive push/hazard actors
;
; Blitter Architecture:
;   The Amiga Blitter coprocessor performs high-speed DMA-driven block copies and
;   masked bitplane transfers. Tile and BOB rendering uses hardware WAITBLIT
;   synchronisation.
;
;   Standard transparent blit minterm ($fca = A*B + ~A*C):
;     A = mask channel (opaque pixels = 1)
;     B = source graphic (tile/BOB data)
;     C = background destination (existing playfield pixels)
;     D = blitter output (written back to screen bitplanes)
;
; Register convention:
;   a6 = $dff000 (CUSTOM)
;   a5 = Variables base
;
;==============================================================================

;==============================================================================
; LevelInit  -  Initialise all state for a new level from LevelDef
;
; Sequence:
;   1. Reset player state, movement registers, and initial facing (facing right).
;   2. Reset oxygen level (OXYGEN_MAX), submersion/drowning flags, and ensure
;      valid player lives counter (DEFAULT_LIVES).
;   3. Seed random number generator with LevelId ($BABEFEED) for deterministic
;      tile pattern variation.
;   4. Clear particle animation pools (CloudActorsCount, DirtActorsCount).
;   5. Look up active LevelDef pointer from LevelTable[LevelId].
;   6. Unpack map dimensions, camera bounds (LevelMinCameraY..LevelMaxCameraY),
;      deadzone margins, and initial camera scroll position.
;   7. Copy 1D GameMap binary from LevelDef_GameMap into working GameMap buffer.
;   8. Initialize Player spawn position (P1Col, P1Row), world coordinates,
;      and seed safe dry platform coordinates (PlayerSafeX/Y).
;   9. Populate dynamic level entities:
;      - LevelInitEnemies (patrol bounds, speeds, types)
;      - LevelInitFriends (animal friend coordinates, types)
;      - LevelInitOxygen  (oxygen kit refills)
;  10. Convert solid blocks and instantiate interactive objects.
;==============================================================================

LevelInit:
    ; NonDisplayScreen clearing is handled dynamically by TilemapInitScreen
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
    clr.w         Player_ErasedFlag(a5)  ; Clear wide footprint erase flag
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

    ; Reset oxygen and submersion state
    move.w        #OXYGEN_MAX,PlayerOxygen(a5)
    clr.w         PlayerSubmerged(a5)
    clr.w         PlayerDrowning(a5)
    clr.w         PlayerDrownTimer(a5)
    clr.w         OxygenKitInventory(a5)
    clr.w         OxygenKitActive(a5)
    tst.w         PlayerLives(a5)
    bne.s         .lives_ok
    move.w        #DEFAULT_LIVES,PlayerLives(a5)
.lives_ok:

    ; Seed the PRNG from the level ID so randomisation is reproducible.
    ; The magic constant $BABEFEED gives a good initial spread.
    move.l        #$BABEFEED,d0
    move.b        LevelId+1(a5),d0       ; mix in low byte of level ID
    move.l        d0,RandomSeed(a5)      ; store as new seed

    clr.w         CloudActorsCount(a5)   ; reset cloud animation list for new level
    clr.w         DirtActorsCount(a5)    ; reset dirt animation list for new level
    clr.w         FallenActorsCount(a5)  ; reset falling actors list for new level

    ; -------------------------------------------------------------------------
    ; 1. Establish Map Geometry & Default Camera Boundaries
    ; -------------------------------------------------------------------------
    move.w        #WALL_PAPER_WIDTH,CurrentMapWidth(a5)
    move.w        #WALL_PAPER_HEIGHT,CurrentMapHeight(a5)
    move.w        #WALL_PAPER_SIZE,CurrentMapSize(a5)

    clr.l         CurrentLevelDef(a5)    ; default: no custom LevelDef active
    move.w        #0,LevelMinCameraY(a5) ; default min vertical camera scroll
    move.w        #464,LevelMaxCameraY(a5) ; default max vertical camera scroll
    move.w        #CAM_MARGIN_TOP,LevelCamMarginTop(a5)       ; deadzone top (16px)
    move.w        #CAM_MARGIN_BOTTOM,LevelCamMarginBottom(a5) ; deadzone bottom (176px)

    ; -------------------------------------------------------------------------
    ; 2. Look Up LevelDef from Master LevelTable or Custom Level
    ; -------------------------------------------------------------------------
    tst.w         CustomLevelLoaded(a5)
    beq.s         .normal_level_lookup
    movea.l       CustomLevelDef(a5),a2  ; use custom loaded LevelDef descriptor
    bra.s         .leveldef_ready

.normal_level_lookup:
    ; LevelId(a5) is a 0-based level index (0 = Level_01, 1 = Level_02, etc.).
    ; Table entries are 32-bit pointers (4 bytes each -> LSL.W #2, d0).
    move.w        LevelId(a5),d0
    cmp.w         #LEVEL_TABLE_COUNT,d0
    bge           .not_custom_level      ; past table count -> fallback to legacy maps
    lsl.w         #2,d0                  ; d0 = LevelId * 4 (byte offset in pointer table)
    lea           LevelTable,a2
    movea.l       (a2,d0.w),a2           ; a2 = pointer to active Level_NN_Def structure
    cmpa.w        #0,a2
    beq           .not_custom_level      ; null entry -> fallback to legacy maps

.leveldef_ready:
    move.l        a2,CurrentLevelDef(a5) ; cache active LevelDef pointer for runtime access

    ; -------------------------------------------------------------------------
    ; 3. Unpack Map Dimensions & Total Cell Count
    ; -------------------------------------------------------------------------
    move.w        LevelDef_Width(a2),d0
    move.w        d0,CurrentMapWidth(a5)      ; columns across map (e.g. 20)
    move.w        LevelDef_Height(a2),d1
    move.w        d1,CurrentMapHeight(a5)     ; rows down map (e.g. 42)
    mulu.w        d0,d1                       ; Total cells = Width * Height
    move.w        d1,CurrentMapSize(a5)       ; e.g. 20 * 42 = 840 bytes

    ; -------------------------------------------------------------------------
    ; 4. Configure Dynamic Vertical Camera Bounds & Deadzones
    ; -------------------------------------------------------------------------
    ; Each level defines its own scroll range so shorter maps don't overscroll
    ; and tall multi-screen maps (e.g. 672px) can scroll smoothly.
    move.w        LevelDef_MinCameraY(a2),LevelMinCameraY(a5)
    move.w        LevelDef_MaxCameraY(a2),LevelMaxCameraY(a5)
    move.w        LevelDef_CamMarginTop(a2),LevelCamMarginTop(a5)
    move.w        LevelDef_CamMarginBottom(a2),LevelCamMarginBottom(a5)
    move.w        LevelDef_InitialCameraY(a2),TilemapCameraY(a5) ; starting camera Y

    ; -------------------------------------------------------------------------
    ; 5. Populate 1D Collision Map (GameMap) from Level Binary
    ; -------------------------------------------------------------------------
    ; LevelDef_GameMap points to raw byte array defining collision and interactive
    ; cells: 0=empty/air, 1=solid, 2=ladder, 3=hazard, 4=passthrough, etc.
    movea.l       LevelDef_GameMap(a2),a0     ; source binary stream
    lea           GameMap(a5),a1              ; working GameMap buffer in RAM
    move.w        CurrentMapSize(a5),d0
    subq.w        #1,d0                       ; d0 = loop count for DBRA (cells - 1)
.copy_gamemap:
    move.b        (a0)+,(a1)+
    dbra          d0,.copy_gamemap

    ; -------------------------------------------------------------------------
    ; 6. Initialize Player Spawn Position & World Coordinates
    ; -------------------------------------------------------------------------
    lea           Player(a5),a0
    move.w        #1,Player_Status(a0)        ; mark player active
    move.w        LevelDef_P1Col(a2),d0
    move.w        d0,Player_X(a0)             ; tile grid column (0..19)
    lsl.w         #4,d0                       ; pixel X = Col * 16
    move.w        d0,Player_PixelX(a0)        ; cache pixel X
    clr.w         Player_XDec(a0)             ; tile-aligned (sub-tile offset 0)

    move.w        LevelDef_P1Row(a2),d0
    move.w        d0,Player_Y(a0)             ; tile grid row (0..41)
    lsl.w         #4,d0                       ; pixel Y = Row * 16
    move.w        d0,Player_PixelY(a0)        ; cache pixel Y
    clr.w         Player_YDec(a0)             ; tile-aligned (sub-tile offset 0)

    ; Calculate World X/Y for rendering:
    ; Player BOB is 24x24 pixels, while grid tiles are 16x16 pixels.
    ; Lifting World Y by 8 pixels aligns player's feet with tile baseline.
    move.w        Player_PixelX(a0),Player_WorldX(a0)
    move.w        d0,d1
    subq.w        #8,d1                       ; World Y = Pixel Y - 8
    move.w        d1,Player_WorldY(a0)
    move.w        LevelDef_P1Facing(a2),Player_Facing(a0) ; initial facing direction (+1 right, -1 left)

    ; -------------------------------------------------------------------------
    ; 7. Seed Initial Safe Dry Platform Coordinates
    ; -------------------------------------------------------------------------
    ; Stored so that upon drowning or dying, PlayerRespawn can instantly restore
    ; the player to the most recent dry, safe ground.
    move.w        Player_X(a0),PlayerSafeX(a5)
    move.w        Player_Y(a0),PlayerSafeY(a5)
    move.w        Player_PixelX(a0),PlayerSafePixelX(a5)
    move.w        Player_PixelY(a0),PlayerSafePixelY(a5)

    ; -------------------------------------------------------------------------
    ; 8. Setup Animation & Grid Collision Block IDs
    ; -------------------------------------------------------------------------
    clr.w         Player_BobOffset(a0)        ; base frame offset (0)
    move.w        #20,Player_FrozenBobBase(a0)
    move.w        #PLAYER_LADDER_IDLE,Player_LadderFreezeId(a0)
    move.b        #BLOCK_PLAYERSTART,Player_BlockId(a0)   ; block ID written to GameMap
    move.b        #BLOCK_PLAYERLADDER,Player_LadderId(a0) ; block ID when on ladder
.not_custom_level:

    bsr           InitGameObjects        ; create actors for all game objects in map
    bsr           LevelInitEnemies       ; populate ActiveEnemies table from LevelDef
    bsr           LevelInitFriends       ; populate ActiveFriends table from LevelDef
    bsr           LevelInitOxygen        ; populate ActiveOxygen table from LevelDef
    bsr           PlayerInitFlippedSprites ; ensure active character pointers & flipped buffers are set
    rts

;==============================================================================
; LevelIntroSetup  -  Initialise camera and player state for level start
;
; Called when entering gameplay.  Snaps the camera to the player start position,
; displays the active player BOB frame, and transitions immediately to ACTION_IDLE.
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
    clr.w       GamePaused(a5)
    clr.w       Pause_PaletteActive(a5)
    clr.w       DebugOverlayActive(a5)
    clr.w       PrevDebugDrawn(a5)
    clr.w       VBlankOverrunCount(a5)  ; start level with clean 0 overruns
    lea         Keys,a0
    clr.b       KEY_S(a0)
    clr.b       KEY_A(a0)
    clr.b       KEY_D(a0)
    clr.b       KEY_P(a0)

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
    ; All tiles blitted black - install cpBanner so the banner text is drawn
    ; onto a clean black display with dedicated high-contrast palette
    bsr         BannerCopperInit
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

    ; Allow skipping banner hold if Fire or Return/Space is pressed
    tst.w       LevelCompleteWipe(a5)
    bne.s       .no_skip
    lea         Keys,a0
    tst.b       KEY_RETURN(a0)
    bne.s       .do_skip
    tst.b       KEY_SPACE(a0)
    bne.s       .do_skip
    btst        #7,$bfe001              ; CIAAPRA bit 7: Fire button (active low = 0)
    bne.s       .no_skip
.do_skip:
    clr.b       KEY_RETURN(a0)
    clr.b       KEY_SPACE(a0)
    moveq       #1,d0                   ; trigger immediate transition next tick
.no_skip:
    subq.w      #1,d0
    move.w      d0,WipeHoldTick(a5)
    rts

.hold_done
    ; Hold complete - check whether to show the level-complete screen or reveal a new level
    tst.w       LevelCompleteWipe(a5)
    beq         .normal_reveal
    clr.w       LevelCompleteWipe(a5)
    tst.w       CustomLevelLoaded(a5)
    beq.s       .normal_lc
    ; Custom test level completed -> clear custom level flags and return to title
    clr.w       CustomLevelLoaded(a5)
    clr.l       CustomLevelDef(a5)
    move.w      #0,LevelId(a5)
    move.w      #TITLE_SETUP,GameStatus(a5)
    rts
.normal_lc:
    move.w      #LEVEL_COMPLETE_SETUP,GameStatus(a5)
    rts

.normal_reveal
    ; Transition from cpBanner (or foreign copper) to cpGame:
    ; Build the level, load tileset palette into cpPal, install cpGame
    clr.w       EnterGameCopper(a5)
    bsr         GameCopperInit          ; patch cpGame bitplane ptrs + default pal, hide sprites
    bsr         LevelRevealSetup        ; build level; TilemapInit draws DisplayScreen & loads palette into cpPal
   ; bsr         VHS_Init                ; arm VHS distortion region (PAL/NTSC)
    move.l      #-1,ScreenMemEnd        ; re-arm the screen overrun sentinel
    move.l      #cpGame,COP1LC(a6)      ; switch to the fully-prepared game copper
    move.w      #0,COPJMP1(a6)
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
    clr.w       VBlankOverrunCount(a5)  ; clear multi-frame level load/reveal overruns before entering GAME_RUN!

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
; BannerCopperInit  -  Install and activate cpBanner for intro text
;
; Patches cpBannerPlanes with DisplayScreen bitplane addresses (5 planes,
; stride 40, interleaved), masks all 8 sprites to NullSprite, and points
; COP1LC to cpBanner with an immediate strobe to COPJMP1.
;==============================================================================

BannerCopperInit:
    PUSHM       d0-d1/d7/a0
    lea         cpBannerPlanes,a0
    move.l      #DisplayScreen,d0
    move.l      #SCREEN_WIDTH_BYTE,d1
    moveq       #5,d7
    bsr         CopperSetPtrs

    lea         cpBannerSprites,a0
    move.l      #NullSprite,d0
    moveq       #0,d1
    moveq       #8,d7
    bsr         CopperSetPtrs

    move.l      #cpBanner,COP1LC(a6)
    move.w      #0,COPJMP1(a6)
    POPM        d0-d1/d7/a0
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
; Text data is read directly from CurrentLevelDef(a5): LevelDef_TitleStr
; (rendered in yellow Michroma/8x8 font) and LevelDef_SubTitleStr (rendered in green HUD font).
; Levels without title strings fall through to the default short wipe hold.
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
; Centres against the 40-character-wide screen (320px / 8px per glyph);
; strings longer than 40 characters are left-aligned (clipped) instead.
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
    moveq       #SCREEN_WIDTH_BYTE,d2   ; 40 columns (320px / 8px per char)
    sub.w       d0,d2
    bpl         .dcl_fits
    moveq       #0,d2                   ; too long for the screen: left-align
.dcl_fits
    asr.w       #1,d2                   ; d2 = centred byte column

    mulu        #SCREEN_STRIDE,d1       ; d1 = byte row offset (5 * 40 = 200 bytes)
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
;   1. Resolve CurrentLevelDef early so LevelBannerShow has the correct LevelDef.
;   2. Reset WipeTilesDone = 0.
;   3. Pick a random wipe pattern using RANDOMWORD and store in WipePattern.
;   4. Call the appropriate WipeFill routine to build WipeTileX/Y arrays.
;   5. Hide all hardware sprites (ClearSprites).
;
; On entry: a5 = Variables base, a6 = CUSTOM.
;==============================================================================

LevelSetup:
    PUSHALL

    ; -------------------------------------------------------------------------
    ; 0. Resolve CurrentLevelDef early
    ; Guarantees LevelBannerShow has the correct LevelDef descriptor for
    ; Level 1, Level 2, and all subsequent levels during the wipe and hold!
    ; -------------------------------------------------------------------------
    tst.w       CustomLevelLoaded(a5)
    beq.s       .setup_normal_def
    move.l      CustomLevelDef(a5),CurrentLevelDef(a5)
    bra.s       .setup_def_done

.setup_normal_def:
    move.w      LevelId(a5),d0
    cmp.w       #LEVEL_TABLE_COUNT,d0
    bge.s       .setup_no_def
    lsl.w       #2,d0
    lea         LevelTable,a0
    move.l      (a0,d0.w),CurrentLevelDef(a5)
    bra.s       .setup_def_done

.setup_no_def:
    clr.l       CurrentLevelDef(a5)
.setup_def_done:

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


;==============================================================================
; LevelInitFriends  -  Initialize ActiveFriends array from current LevelDef
;
; Reads spawn records from LevelDef_FriendList and fills ActiveFriends in RAM.
; Each spawn record contains:
;   dc.w Type, Col, Row, SpawnX, SpawnY, Res1, Res2, Res3 (16 bytes per record)
; List terminated by $FFFF.
;
; Sets ActiveFriendCount and clears drawn state.
;==============================================================================

LevelInitFriends:
    PUSHM       d0-d7/a0-a3
    clr.w       ActiveFriendCount(a5)
    clr.w       FriendsRescuedCount(a5)

    ; Clear entire ActiveFriends buffer
    lea         ActiveFriends(a5),a1
    move.w      #(fi_SIZEOF*MAX_ACTIVE_FRIENDS)/2-1,d7
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
    move.w      d0,fi_Type(a1)
    move.w      d3,fi_X(a1)
    move.w      d4,fi_Y(a1)
    clr.w       fi_AnimFrame(a1)
    move.w      d6,d5
    lsl.w       #2,d5                   ; stagger initial anim timer (0, 4, 8, 12...)
    move.w      d5,fi_AnimTimer(a1)
    clr.w       fi_Rescued(a1)
    clr.w       fi_PrevX(a1)
    clr.w       fi_PrevY(a1)
    clr.w       fi_Drawn(a1)

    lea         fi_SIZEOF(a1),a1
    addq.w      #1,d6
    bra.s       .populate_friend_loop

.finish_friend_init:
    move.w      d6,ActiveFriendCount(a5)

.done_init_friends:
    POPM        d0-d7/a0-a3
    rts


;==============================================================================
; LevelInitOxygen  -  Initialize ActiveOxygen array from current LevelDef
;
; Reads spawn records from LevelDef_OxygenList and fills ActiveOxygen in RAM.
; Each spawn record contains:
;   Col (w), Row (w), PixelX (w), PixelY (w), TileId (w), Res1 (w), Res2 (w), Res3 (w)
; Format ends with $ffff word marker.
;
; Sets ActiveOxygenCount and clears drawn / collected state.
;==============================================================================

LevelInitOxygen:
    PUSHM       d0-d7/a0-a3
    clr.w       ActiveOxygenCount(a5)

    ; Clear entire ActiveOxygen buffer
    lea         ActiveOxygen(a5),a1
    move.w      #(ox_SIZEOF*MAX_ACTIVE_OXYGEN)/2-1,d7
.clear_oxygen_loop:
    clr.w       (a1)+
    dbra        d7,.clear_oxygen_loop

    ; Locate LevelDef OxygenList
    move.l      CurrentLevelDef(a5),d0
    beq.s       .done_init_oxygen
    movea.l     d0,a0
    move.l      LevelDef_OxygenList(a0),d0
    beq.s       .done_init_oxygen
    movea.l     d0,a0                   ; a0 = OxygenList source

    lea         ActiveOxygen(a5),a1     ; a1 = ActiveOxygen destination
    clr.w       d6                      ; d6 = count

.populate_oxygen_loop:
    move.w      (a0)+,d1                ; Col (or $ffff end marker)
    cmp.w       #$ffff,d1
    beq.s       .finish_oxygen_init
    cmp.w       #MAX_ACTIVE_OXYGEN,d6
    bge.s       .finish_oxygen_init     ; table full

    move.w      (a0)+,d2                ; Row
    move.w      (a0)+,d3                ; PixelX
    move.w      (a0)+,d4                ; PixelY
    move.w      (a0)+,d0                ; TileId (e.g. 95)
    addq.l      #6,a0                   ; skip Res1, Res2, Res3 (6 bytes)

    ; Store in ActiveOxygen instance (a1)
    move.w      d1,ox_Col(a1)
    move.w      d2,ox_Row(a1)
    move.w      d3,ox_X(a1)
    move.w      d4,ox_Y(a1)
    clr.w       ox_Collected(a1)
    clr.w       ox_Drawn(a1)
    move.w      d0,ox_TileId(a1)

    lea         ox_SIZEOF(a1),a1
    addq.w      #1,d6
    bra.s       .populate_oxygen_loop

.finish_oxygen_init:
    move.w      d6,ActiveOxygenCount(a5)

.done_init_oxygen:
    POPM        d0-d7/a0-a3
    rts



