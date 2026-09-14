
;==============================================================================
; AMIGA GAME ENGINE
; variables.asm  -  Global Variable Block (RS layout in Fast RAM)
;==============================================================================
;
; This file defines the layout of the "Variables" block allocated in Fast RAM
; (section mem_fast, bss).  It uses RS directives so that the same symbol names
; work as both structure offsets AND as absolute addresses (since "Variables" is
; a real label at assembly time, and each RS name ends up being used as an
; offset from A5 which is permanently loaded with the Variables address).
;
; Convention:  a5 = Variables base pointer throughout the entire program.
;              All fields are accessed as  FieldName(a5).
;
; RSRESET is used once at the top; each rs.x directive advances the RS counter
; and assigns the current count to the label.  rs.w 0 at the end captures
; the total byte count in Variables_sizeof, which is used to reserve the BSS
; block with  "Variables: ds.b Variables_sizeof".
;
;==============================================================================

                      rsreset

;------------------------------------------------------------------------------
; Level management
;------------------------------------------------------------------------------
LevelId:              rs.w    1   ; current level number (0-based index into levels.bin)
CurrentLevelDef:      rs.l    1   ; pointer to active Level_NN_Def descriptor (from LevelTable)
LevelPtr:             rs.l    1   ; pointer to current level's raw data in LevelData
CurrentMapWidth:      rs.w    1   ; width of current level map in tiles (e.g. 20)
CurrentMapHeight:     rs.w    1   ; height of current level map in tiles (e.g. 42)
CurrentMapSize:       rs.w    1   ; total cells in current level map (e.g. 840)

;------------------------------------------------------------------------------
; Tile grid maps
;
; GameMapCeiling - the solid top border row (WALL_PAPER_WIDTH bytes).
;                  Always all BLOCK_SOLID; never modified at runtime.
; GameMap        - the live game map (WALL_PAPER_SIZE bytes = 14*9 = 126 bytes).
;                  Starts as a copy of the level data expanded into the border
;                  frame.  Modified during play as players/actors move and
;                  blocks are destroyed or pushed.
; WallpaperCheat - a hidden extra row of TILE_BACK bytes at the bottom edge,
;                  used to give the renderer a clean termination row.
; WallpaperWork  - the tile-type map used by DrawWalls to select wall graphics.
;                  Derived from GameMap by WallPaperWalls; each byte holds a
;                  TILE_xxx value rather than a BLOCK_xxx value.
;------------------------------------------------------------------------------
GameMapCeiling:       rs.b    WALL_PAPER_WIDTH    ; top border row (20 bytes)
GameMap:              rs.b    MAX_GAME_MAP_SIZE   ; live game map  (up to 1280 bytes)
WallpaperCheat:       rs.b    WALL_PAPER_WIDTH    ; bottom dummy row (20 bytes)
WallpaperWork:        rs.b    MAX_GAME_MAP_SIZE   ; rendered wall tile types
                      rs.w    0                   ; alignment pad to longword boundary (RandomSeed must be longword-aligned for blitter)
RandomSeed:           rs.l    1   ; LFSR random number seed (seeded from LevelId)
                      rs.w    0                   ; alignment pad to longword boundary (TilesetPtr must be longword-aligned for blitter reads)

;------------------------------------------------------------------------------
; Asset management
;------------------------------------------------------------------------------
TilesetPtr:           rs.l    1   ; pointer to the decompressed TileSet in Chip RAM
AssetSet:             rs.w    1   ; current tileset variant index (0-4, from LevelAssetSet)

;------------------------------------------------------------------------------
; Game flow
;------------------------------------------------------------------------------
MoveId:               rs.w    1   ; incremented each time a player makes a move

;------------------------------------------------------------------------------
; Player records
;
; Player - the actual Player structure data (Player_Sizeof bytes).
;------------------------------------------------------------------------------
Player:               rs.b    Player_Sizeof   ; Player structure data
;Millie                = Player    ; backward compatibility alias

;------------------------------------------------------------------------------
; Game state machine
;------------------------------------------------------------------------------
GameStatus:           rs.w    1   ; current state index — see the GAME_/LEVEL_/TITLE_/
                                  ; INSTR_/GAME_COMPLETE_ constants in const.asm and
                                  ; the dispatch table in gamestatus.asm
QuitFlag:             rs.w    1   ; non-zero = MainLoop exits to the OS (ESC on title)

;------------------------------------------------------------------------------
; Hardware sprite pointers
;
; 8 longword pointers, one per hardware sprite channel (SPR0..SPR7).
; Updated each VBlank by ShowSprite and then copied into the copper list
; sprite pointer entries (cpSprites) so that Agnus fetches the correct data.
; Sprites 0/1 = left half of player, 2/3 = right half.  Sprites 4-7 unused.
;------------------------------------------------------------------------------
SpritePtrs:           rs.l    8   ; 8 sprite data pointers
SpriteYOffset:        rs.w    1   ; raster line of display top: WINDOW_Y_START (PAL) or NTSC_WINDOW_Y_START
IsPAL:                rs.w    1   ; 1 = PAL system, 0 = NTSC — set once by DetectNTSC, read by AudioInit and VHS_Init

;------------------------------------------------------------------------------
; Actor pool
;
; ActorCount - number of active actors currently in the pool (updated by
;              CleanActors after kills).
; Actors     - the flat actor structure array.  Actor_Sizeof bytes per slot,
;              MAX_ACTORS slots = MAP_SIZE = 88 slots maximum.
;              Always accessed via the sorted ActorList pointer array.
;------------------------------------------------------------------------------
ActorCount:           rs.w    1   ; number of live actors
Actors:               rs.b    Actor_Sizeof*MAX_ACTORS  ; actor pool (88 * Actor_Sizeof bytes)

;------------------------------------------------------------------------------
; Timing and input
;------------------------------------------------------------------------------
TickCounter:          rs.w    1   ; VBlank counter, incremented every frame (~50Hz PAL)
FramePending:         rs.w    1   ; incremented by VBlankTick, consumed by MainLoop (frame gate)
VBlankOverrunCount:   rs.w    1   ; frames where MainLoop exceeded one VBlank (debug telemetry)
IsOCS:                rs.w    1   ; 1 = OCS chipset (Original), 0 = ECS/AGA; set by DetectOCS,
                                  ; available for chipset-specific code paths
ControlsTrigger:      rs.b    1   ; one-shot bits: set on the frame a key was first pressed
ControlsHold:         rs.b    1   ; continuous bits: set for every frame a key is held
Joy2FireHold:         rs.w    1   ; joy2 fire hold counter (0=idle, 1..N=frames held, N=threshold=fired)

;------------------------------------------------------------------------------
; Per-frame movement flags
;------------------------------------------------------------------------------
PlayerMoved:          rs.w    1   ; non-zero if the active player moved this frame
PlayerCount:          rs.w    1   ; number of player characters initialised for this level

;------------------------------------------------------------------------------
; Level completion / action status
;------------------------------------------------------------------------------
LevelComplete:        rs.w    1   ; set to 1 when all enemies are destroyed
LevelCompleteHold:    rs.w    1   ; countdown to 0 before transition starts; 0 = not yet triggered
LevelCompleteWipe:    rs.w    1   ; non-zero = wipe leads to LEVEL_COMPLETE_SETUP, not LEVEL_REVEAL
EnterGameCopper:      rs.w    1   ; non-zero = entering gameplay from a foreign copper (title / level-
                                  ; complete): at the end of the wipe (LEVEL_HOLD) install the game
                                  ; copper + palette while the screen is black, so the swap is invisible
ActionStatus:         rs.w    1   ; current action state: ACTION_IDLE/MOVE/FALL/PLAYERPUSH

;------------------------------------------------------------------------------
; Push-block action state
;
; PushedActor   - pointer to the actor struct of the block being pushed.
;                 Valid only while ActionStatus = ACTION_PLAYERPUSH.
; ActionCounter - frame counter for the current push animation.
;------------------------------------------------------------------------------
PushedActor:          rs.l    1   ; pointer to the actor being pushed
ActionCounter:        rs.w    1   ; push animation frame counter (0..PUSH_STEPS-1)

LoadingLoadStep:        rs.w    1   ; ZX screen-load step counter (0..ZX_STEPS_TOTAL)
LoadingWashLine:        rs.w    1   ; colour-wash scan line (0..LOADING_HEIGHT); advances each frame
LoadingBarPhase:        rs.w    1   ; pilot-bar crawl phase (0..ZX_PILOT_HEIGHT*2-1), +1 per frame
LoadingIntroTick:       rs.w    1   ; screenname intro countdown (SCREENNAME_FRAMES..0; 0 = done)
LoadingGapTick:         rs.w    1   ; inter-block tape-silence countdown (header -> data gap)
LoadingMenuTick:        rs.w    1   ; post-wash pause countdown before title transition (MENU_PAUSE_FRAMES..0)
LoadingWipeActive:      rs.w    1   ; non-zero once the loading->title dissolve wipe has begun (loading.asm)
DebugMode:        rs.w    1   ; 0=off  1=debug mode (F5)  2=debug+raster bar (F3)

;------------------------------------------------------------------------------
; DrawTile blit queue (used by DrawWalls during level load)
;
; DrawTileQueued pushes (BLTAPT, BLTDPT) pairs here instead of touching the
; blitter.  FlushDrawTileQueue then writes the constant registers once and
; streams the entries with WAITBLIT only between each BLTSIZE write, allowing
; the CPU to pre-fetch the next entry from Fast RAM while the current blit runs.
;
; BlitQueueCount entries max = WALL_PAPER_SIZE (126 tiles per level).
;------------------------------------------------------------------------------
BlitQueueCount:       rs.w    1                  ; number of pending queue entries
BlitQueuePad:         rs.w    1                  ; alignment pad (keeps BlitQueuePtr longword-aligned)
BlitQueuePtr:         rs.l    1                  ; write cursor into BlitQueueData (advanced 12 bytes per push)
BlitQueueData:        rs.b    WALL_PAPER_SIZE*12 ; (BLTCON0<<16|BLTCON1, BLTAPT, BLTDPT) — 12 bytes each


;------------------------------------------------------------------------------
; Fallen actor list
;
; FallenActors      - array of actor pointers for actors that are currently
;                     in a fall animation (Actor_HasFalled set).  Filled by
;                     ActorFallAll, processed by ActionFallActors each frame.
; FallenActorsCount - number of valid entries in FallenActors.
;------------------------------------------------------------------------------
FallenActors:         rs.l    MAP_SIZE    ; up to 88 pointers (one per map cell)
FallenActorsCount:    rs.w    1           ; number of currently-falling actors

;------------------------------------------------------------------------------
; Pre-computed blitter clear masks
;
; ClearMasks holds 16 longword mask values (one per possible X sub-tile pixel
; offset 0..15) used by ClearActor to cleanly erase an actor from DisplayScreen.
; Built at startup by CreateClearMasks.
; Indexed as:  (a2, d1.w*4)  where d1 = d0 AND $f  (pixel offset mod 16).
;------------------------------------------------------------------------------
ClearMasks:           rs.l    TILE_WIDTH  ; 24 longs (only 16 used; TILE_WIDTH = 24)

;------------------------------------------------------------------------------
; Sorted actor pointer list
;
; ActorSlotPtr - write pointer into ActorList, advanced as actors are allocated
;                by GetActorSlot.  Reset to &ActorList at the start of each level.
; ActorList    - array of longword pointers to active Actor structures, sorted
;                by Y position (largest Y first) by SortActors so that actors
;                closer to the bottom are drawn last (i.e. on top).
;------------------------------------------------------------------------------
ActorSlotPtr:         rs.l    1           ; current write pointer into ActorList
ActorList:            rs.l    MAP_SIZE    ; sorted actor pointer array (88 entries max)

;------------------------------------------------------------------------------
; Star animation state (shared by level intro and player-switch transition)
;
; StarOriginX/Y   - current tile position of the large travelling star
; StarTargetX/Y   - initial travel destination: one tile past the player tile
;                   (the overshoot position).  After the star arrives there it
;                   is redirected to StarOvershootX for the slow return.
; StarOvershootX  - real target X (player / frozen-player tile); the final hold
;                   destination.  StarTargetX is set past this at setup time.
; StarOvershot    - 0 = heading to overshoot tile; 1 = returning to real target
; IntroTick       - countdown to next step (INTRO_STEP_TICKS..1; step at 0)
; IntroDone       - 0 = travelling, hold_ticks..1 = holding at target, triggers end at 1
; IntroWriteIdx   - next slot index to write in the circular trail pool
; StarAnimContext  - 0 = level intro (ACTION_INTRO), 1 = player switch (ACTION_SWITCH)
; IntroTrailX/Y   - tile position of each trail particle (INTRO_TRAIL_MAX slots)
; IntroTrailLife  - remaining life of each trail particle (0 = inactive)
;------------------------------------------------------------------------------
StarOriginX:          rs.w    1
StarOriginY:          rs.w    1
StarTargetX:          rs.w    1
StarTargetY:          rs.w    1
StarOvershootX:       rs.w    1
StarOvershot:         rs.w    1
IntroTick:            rs.w    1
IntroDone:            rs.w    1
IntroWriteIdx:        rs.w    1
StarAnimContext:      rs.w    1
StarLargeTile:        rs.w    1   ; compact tile index for the large star (SPRITE_STAR_LARGE_BLUEor _YELLOW)
IntroTrailX:          rs.w    INTRO_TRAIL_MAX
IntroTrailY:          rs.w    INTRO_TRAIL_MAX
IntroTrailLife:       rs.w    INTRO_TRAIL_MAX


;------------------------------------------------------------------------------
; Cloud death animation actor list
;
; CloudActors      - array of actor pointers for actors currently playing a
;                   cloud death animation (Actor_CloudTick > 0).  Filled by
;                   PlayerKillActor; processed by ActionCloudActors each frame.
; CloudActorsCount - number of valid entries in CloudActors (never compacted;
;                   entries with CloudTick=0 are skipped by the processor).
;------------------------------------------------------------------------------
CloudActors:          rs.l    MAP_SIZE    ; up to 88 cloud animation actor pointers
CloudActorsCount:     rs.w    1           ; number of actors ever added (reset at level load)

;------------------------------------------------------------------------------
; Dirt break animation actor list
;
; DirtActors      - array of actor pointers for actors currently playing a
;                  dirt break animation (Actor_DirtTick > 0).  Filled by
;                  PlayerKillActor; processed by ActionDirtActors each frame.
; DirtActorsCount - number of valid entries in DirtActors (never compacted;
;                  entries with DirtTick=0 are skipped by the processor).
;------------------------------------------------------------------------------
DirtActors:           rs.l    MAP_SIZE    ; up to 88 dirt animation actor pointers
DirtActorsCount:      rs.w    1           ; number of actors ever added (reset at level load)

;------------------------------------------------------------------------------
; Acid dissolve flag (Alien Containment mechanic)
;
; Set by the acid-landing check in ActionFallActors when one or more actors
; dissolved this frame; consumed after the fall loop to run a single
; CleanActors + SortActors pass (dead actors must leave ActorList promptly or
; AnimateEnemies would keep redrawing a dissolved organism).
;------------------------------------------------------------------------------
AcidDissolved:        rs.w    1           ; non-zero = dissolve happened this frame

;------------------------------------------------------------------------------
; Per-tile dirty flags  (14 x 9 = WALL_PAPER_SIZE bytes, one per tile cell)
;
; DirtyTiles      - flat byte array; 1 = tile needs redraw, 0 = clean.
;                   Set by MarkTileDirty (via RestoreBackgroundTile auto-dirty).
;                   Cleared per-entry by FlushDirtyTiles; fully zeroed by ClearDirtyTiles.
; DirtyTileCount  - number of live entries in DirtyTileList this frame.
;                   Reset to 0 by FlushDirtyTiles and ClearDirtyTiles.
; DirtyTileList   - compact word array of dirty tile coordinates.
;                   Each word = (tile_X << 8) | tile_Y.
;                   Deduplicated: MarkTileDirty only appends if DirtyTiles[i] was 0.
;                   Max WALL_PAPER_SIZE entries (one per tile).
;------------------------------------------------------------------------------
DirtyTiles:           rs.b    MAX_GAME_MAP_SIZE ; dirty flags (0=clean, 1=needs redraw)
                      rs.w    0                 ; alignment pad to even boundary (DirtyTileCount must be word-aligned)
DirtyTileCount:       rs.w    1                 ; number of live entries in DirtyTileList
DirtyTileList:        rs.w    MAX_GAME_MAP_SIZE ; compact dirty list: (X<<8)|Y per entry

;------------------------------------------------------------------------------
; Level wipe transition state
;
; WipePattern    - chosen effect index (0..NUM_WIPE_PATTERNS-1)
; WipeTilesDone  - tiles blitted black so far; incremented by WIPE_SPEED each frame
; WipeHoldTick   - hold countdown after all tiles done; DrawMap fires when 0
; WipeTileX/Y    - WALL_PAPER_SIZE-byte arrays of tile coords in wipe order
;                  filled by LevelSetup before GameStatus becomes LEVEL_WIPE
;------------------------------------------------------------------------------
WipePattern:          rs.w    1
WipeTilesDone:        rs.w    1
WipeHoldTick:         rs.w    1
WipeTileX:            rs.b    WALL_PAPER_SIZE
WipeTileY:            rs.b    WALL_PAPER_SIZE
                      rs.w    0                 ; alignment pad to even boundary (SnapshotHead must be word-aligned)

;------------------------------------------------------------------------------
; Undo / rewind snapshot buffer
;
; SnapshotHead  - index of next slot to write (0..UNDO_BUFFER_SIZE-1)
; SnapshotCount - number of valid snapshots currently held (0..UNDO_BUFFER_SIZE)
; SnapshotBuffer - flat array of UNDO_BUFFER_SIZE Snap_sizeof-byte records
;                  Indexed as: SnapshotBuffer + head * Snap_sizeof
;------------------------------------------------------------------------------
SnapshotHead:         rs.w    1
SnapshotCount:        rs.w    1
                      rs.w    0                 ; alignment pad to longword boundary (ActorSortBuf must be longword-aligned for copying)

;------------------------------------------------------------------------------
; Actor sort scratch buffer
;
; ActorSortBuf - temporary longword array used exclusively by SortActors during
;                the scatter pass of the Y-counting sort.  Holds up to MAX_ACTORS
;                actor pointers while the sorted result is being built, then the
;                caller copies them back to ActorList.  Not valid between calls.
;------------------------------------------------------------------------------
ActorSortBuf:         rs.l    MAP_SIZE    ; MAP_SIZE = MAX_ACTORS = 88 longwords (352 bytes)

;------------------------------------------------------------------------------
; Level complete screen state
;
; LevelCompleteSel  - current menu selection (0 = PLAY NEXT LEVEL, 1 = RETURN TO TITLE)
; LCPasswordBuf     - 6-character password string (null-terminated) for next level
;------------------------------------------------------------------------------
LevelCompleteSel:     rs.w    1           ; 0=PLAY NEXT LEVEL, 1=RETURN TO TITLE
LCPasswordBuf:        rs.b    8           ; 6-char password + null + 1 alignment pad
LCShimmerTick:        rs.w    1           ; countdown to next banner gradient rotation step

; Title screen variables (states TITLE_SETUP / TITLE_RUN)
TitleStarX:           rs.b    4           ; 4 star x byte offsets (0..TITLE_STAR_MAX_X)
TitleStarY:           rs.b    4           ; 4 star y row offsets (0..TITLE_LOGO_H-32)
TitleStarTick:        rs.w    1           ; frame countdown for star movement
TitleMenuSel:         rs.w    1           ; selected menu item (0=PLAY, 1=CREDITS, 2=PLAYER, 3=INSTR)
SelectedPlayer:       rs.w    1           ; selected player character (0=Dr. Price, 1=Sgt. Cole)
TitleLevelNum:        rs.w    1           ; level number shown/selected on title screen
MaxUnlockedLevel:     rs.w    1           ; highest 0-based level unlocked this session
TitlePassBuf:         rs.b    8           ; 6-char user-entered password + null + 1 alignment pad
TitlePassLen:         rs.w    1           ; number of characters entered (0-6)
TitleCursorTick:      rs.w    1           ; countdown to cursor blink toggle (TITLE_CURSOR_SPEED..1)
TitleCursorOn:        rs.w    1           ; 1 = cursor visible, 0 = hidden
SkyPhase1:            rs.w    1           ; aurora wave 1 phase (byte offset into Sinus, blue channel)
SkyPhase2:            rs.w    1           ; aurora wave 2 phase (byte offset into Sinus, green channel)

;------------------------------------------------------------------------------
; Text rendering state
;------------------------------------------------------------------------------
FontBold:             rs.w    1           ; non-zero = bold smear in CHAR_BLT* routines

;------------------------------------------------------------------------------
; Michroma "hero text" flash state (bigfont.asm — e.g. the PURGE placard).
; One flashing string armed at a time; PurgeFlashString = 0 means disarmed.
;------------------------------------------------------------------------------
PurgeFlashTimer:      rs.w    1           ; frames remaining until next toggle
PurgeFlashPeriod:     rs.w    1           ; frames between toggles (ScalePALFrames'd)
PurgeFlashOn:         rs.w    1           ; non-zero = currently drawn (visible)
PurgeFlashAddr:       rs.l    1           ; screen address of the string's first glyph
PurgeFlashString:     rs.l    1           ; armed string pointer, 0 = disarmed

;------------------------------------------------------------------------------
; Air bubble animation state (tileset-3 underwater levels only)
;
; BubblePhase   - BUBBLE_PHASE_IDLE (0) or BUBBLE_PHASE_RISE (1)
; BubbleCounter - idle: frames remaining until next bubble starts
;                 rising: frames elapsed since bubble began (0..BUBBLE_RISE_TICKS-1)
; BubbleBaseX   - display-window X pixel of player head when bubble was spawned
; BubbleBaseY   - display-window Y pixel of player head when bubble was spawned
;
; Current bubble X = BubbleBaseX + WobbleTable[BubbleCounter & 7]
; Current bubble Y = BubbleBaseY - BubbleCounter
; Current frame    = min(BubbleCounter >> 3, BUBBLE_FRAMES-1)
;------------------------------------------------------------------------------
BubblePhase:          rs.w    1           ; BUBBLE_PHASE_IDLE / BUBBLE_PHASE_RISE
BubbleCounter:        rs.w    1           ; idle countdown or rise elapsed ticks
BubbleBaseX:          rs.w    1           ; spawn X in display-window pixels
BubbleBaseY:          rs.w    1           ; spawn Y in display-window pixels

;------------------------------------------------------------------------------
; Game complete screen scrolling starfield (states GAME_COMPLETE_SETUP / GAME_COMPLETE_RUN)
;
; GCStarX / GCStarY - pixel positions as unsigned words (0..GC_STAR_MAX_X/Y).
;   Values > GC_STAR_MAX_X/Y (including underflow-wrap to 65535) = off-screen.
;   Layer speeds: stars 0-23 speed 1, 24-47 speed 2, 48-63 speed 4 (right-to-left).
; GCStarRand  - 16-bit Galois LFSR state (shared for X and Y respawn generation).
; GCFrameTick - frame counter; low 3 bits select the twinkle phase for slow stars.
;------------------------------------------------------------------------------
GCStarX:              rs.w    GC_NUM_STARS    ; pixel X positions (word, unsigned)
GCStarY:              rs.w    GC_NUM_STARS    ; pixel Y positions (word, unsigned)
GCStarRand:           rs.w    1               ; Galois LFSR state
GCFrameTick:          rs.w    1               ; frame counter for twinkle phase

;------------------------------------------------------------------------------
; Tilemap Engine state (tilemap.asm)
;------------------------------------------------------------------------------
TilemapCameraY:       rs.w    1               ; camera vertical position in pixels (0..472)
TilemapScreenOffset:  rs.w    1               ; visible tile row start offset (0..29)
TilemapCurrentOffset: rs.w    1               ; currently drawn tile row offset
TilemapFineY:         rs.w    1               ; fine vertical pixel scroll (0..15)
PlayerFrame:       rs.w    1               ; current active player BOB animation frame offset (0..47)
PlayerSpriteFrame     = PlayerFrame        ; alias for backward compatibility
LevelMinCameraY:      rs.w    1               ; minimum camera scroll Y in pixels (e.g. 0)
LevelMaxCameraY:      rs.w    1               ; maximum camera scroll Y in pixels (e.g. 464)
LevelCamMarginTop:    rs.w    1               ; camera upper deadzone margin (e.g. 16)
LevelCamMarginBottom: rs.w    1               ; camera lower deadzone margin (e.g. 176)
ActiveEnemyCount:     rs.w    1               ; number of active enemies (0..MAX_ACTIVE_ENEMIES)
ActiveEnemies:        rs.b    ei_SIZEOF*MAX_ACTIVE_ENEMIES ; runtime enemy instances array

; Debug on-screen text overlay state
DebugOverlayActive:   rs.w    1               ; 0=off, 1=on (toggled by 'D' key or F5)
SlowMode:             rs.w    1               ; 0=normal speed, 1=slow mode (step on 'A' key, toggled by 'S')
SlowModeHold:         rs.w    1               ; frame counter for 'A' key hold detection
PrevKeyS:             rs.w    1               ; previous frame 'S' key state (edge detector)
PrevDebugCameraY:     rs.w    1               ; camera Y where previous debug text was drawn
PrevDebugDrawn:       rs.w    1               ; 1 if debug text was drawn last frame (needs erase)
DebugLineBuf:         rs.b    64              ; text formatting buffer
                      even

; Water rising subsystem state
WaterPixelY:          rs.w    1               ; exact vertical scanline of water surface (0..671)
WaterCurrentRow:      rs.w    1               ; row of top of water (WaterPixelY >> 4)
WaterSubTick:         rs.w    1               ; fractional frame accumulator for 1-pixel steps
WaterRisePeriod:      rs.w    1               ; scaled PAL/NTSC 10-second period (500 or 600)
LiveWaterMap:         rs.b    8+TILEMAP_MAP_TILES*2 ; runtime editable copy of water binary map
                      even



Variables_sizeof:     rs.w    0           ; total size of the Variables block in bytes
