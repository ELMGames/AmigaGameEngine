;==============================================================================
; AMIGA GAME ENGINE
; engine_variables.i  -  Core Engine Fast RAM Variables Layout (RS block)
;==============================================================================
;
; This file defines the standard layout of core engine variables in Fast RAM.
; Accessed via a5 base pointer (e.g. FieldName(a5)).
;
; Game projects include this file and append game-specific entity state
; (such as Player, ActiveEnemies, Water variables) in variables.asm before
; closing with Variables_Sizeof.
;==============================================================================

    IFND _ENGINE_VARIABLES_I
_ENGINE_VARIABLES_I SET 1

    include    "engine_const.i"
    include    "actor_struct.i"

                      rsreset

;------------------------------------------------------------------------------
; Level management
;------------------------------------------------------------------------------
LevelId:              rs.w    1   ; current level number (0-based index)
CurrentLevelDef:      rs.l    1   ; pointer to active LevelDef descriptor
CustomLevelLoaded:    rs.w    1   ; 1 if external test.lvl / custom level was loaded
CustomLevelDef:       rs.l    1   ; pointer to loaded custom LevelDef
CustomLevelAllocPtr:  rs.l    1   ; pointer to AllocMem buffer for cleanup on quit
CustomLevelAllocSize: rs.l    1   ; byte size of AllocMem buffer
CurrentMapWidth:      rs.w    1   ; width of current level map in tiles
CurrentMapHeight:     rs.w    1   ; height of current level map in tiles
CurrentMapSize:       rs.w    1   ; total cells in current level map (width * height)

;------------------------------------------------------------------------------
; Tile grid maps
;------------------------------------------------------------------------------
GameMap:              rs.b    MAX_GAME_MAP_SIZE   ; live game map (up to 1280 bytes)
                      rs.w    0                   ; alignment pad to longword boundary
RandomSeed:           rs.l    1   ; PRNG state: RANDOMWORD, and the loading screen's LFSR

;------------------------------------------------------------------------------
; Game flow & State machine
;------------------------------------------------------------------------------
MoveId:               rs.w    1   ; incremented each time a player makes a move
GameStatus:           rs.w    1   ; current state index (GAME_/LEVEL_/TITLE_/etc.)
QuitFlag:             rs.w    1   ; non-zero = MainLoop exits to OS

;------------------------------------------------------------------------------
; Hardware sprite pointers
;------------------------------------------------------------------------------
SpritePtrs:           rs.l    8   ; 8 sprite data pointers
SpriteYOffset:        rs.w    1   ; raster line of display top
IsPAL:                rs.w    1   ; 1 = PAL system, 0 = NTSC

;------------------------------------------------------------------------------
; Crate / Interactive Block Actor pool
;------------------------------------------------------------------------------
ActorCount:           rs.w    1   ; number of live crate actors
TotalActorCount:      rs.w    1   ; total allocated actor slots in level
Actors:               rs.b    Actor_Sizeof*MAX_ACTIVE_CRATES ; crate actor pool

;------------------------------------------------------------------------------
; Timing, chipset, and input
;------------------------------------------------------------------------------
TickCounter:          rs.w    1   ; logic-tick counter (50 Hz on PAL/NTSC)
NtscSkipPhase:        rs.w    1   ; NTSC VBlank phase 0..5 (60->50 Hz)
FramePending:         rs.w    1   ; frame gate
FrameBusy:            rs.w    1   ; 1 while MainLoop is running a frame
VBlankOverrunCount:   rs.w    1   ; VBlanks that fired mid-frame; cleared by the next on-time frame
IsOCS:                rs.w    1   ; 1 = OCS chipset, 0 = ECS/AGA
ControlsTrigger:      rs.b    1   ; one-shot trigger bits
ControlsHold:         rs.b    1   ; continuous hold bits
Joy2FireHold:         rs.w    1   ; joy2 fire hold counter

;------------------------------------------------------------------------------
; Level completion / action status
;------------------------------------------------------------------------------
LevelComplete:        rs.w    1   ; set to 1 when level goals met
LevelCompleteHold:    rs.w    1   ; countdown to 0 before transition starts
LevelCompleteWipe:    rs.w    1   ; non-zero = wipe leads to LEVEL_COMPLETE_SETUP
EnterGameCopper:      rs.w    1   ; non-zero = entering gameplay from a foreign copper
ActionStatus:         rs.w    1   ; current action state: ACTION_IDLE/MOVE/FALL/etc.

;------------------------------------------------------------------------------
; Push-block action state
;------------------------------------------------------------------------------
PushedActor:          rs.l    1   ; pointer to the actor being pushed
ActionCounter:        rs.w    1   ; push animation frame counter

;------------------------------------------------------------------------------
; Loading screen state
;------------------------------------------------------------------------------
LoadingLoadStep:      rs.w    1   ; ZX screen-load step counter
LoadingWashLine:      rs.w    1   ; colour-wash scan line
LoadingBarPhase:      rs.w    1   ; pilot-bar crawl phase
LoadingIntroTick:     rs.w    1   ; frames left in tape phase; data/wash frame counter
LoadingTapePhase:     rs.w    1   ; current tape phase (TAPE_PILOT1..TAPE_DATA)
LoadingMenuTick:      rs.w    1   ; post-wash pause countdown
LoadingWipeActive:    rs.w    1   ; non-zero once wipe begins
DebugMode:            rs.w    1   ; 0=off 1=debug (F5) 2=debug+raster bar (F3)

;------------------------------------------------------------------------------
; Fallen and sorted actor lists
;------------------------------------------------------------------------------
FallenActors:         rs.l    MAX_ACTIVE_CRATES ; pointers for falling blocks
FallenActorsCount:    rs.w    1                 ; number of currently-falling actors
ActorSlotPtr:         rs.l    1                 ; current write pointer into ActorList
ActorList:            rs.l    MAX_ACTIVE_CRATES ; sorted actor pointer array

;------------------------------------------------------------------------------
; Per-tile dirty flags
;------------------------------------------------------------------------------
                      rs.w    0                 ; ensure word alignment
DirtyTiles:           rs.b    MAX_GAME_MAP_SIZE ; dirty flags (0=clean, 1=needs redraw)
                      rs.w    0                 ; alignment pad
DirtyTileCount:       rs.w    1                 ; number of live entries in DirtyTileList
DirtyTileList:        rs.w    MAX_GAME_MAP_SIZE ; compact dirty list: (X<<8)|Y

;------------------------------------------------------------------------------
; Level wipe transition state
;------------------------------------------------------------------------------
WipePattern:          rs.w    1
WipeTilesDone:        rs.w    1
WipeHoldTick:         rs.w    1
WipeTileX:            rs.b    WIPE_GRID_SIZE
WipeTileY:            rs.b    WIPE_GRID_SIZE
                      rs.w    0                 ; alignment pad

;------------------------------------------------------------------------------
; Palette Fade Subsystem State
;------------------------------------------------------------------------------
PalFadeActive:        rs.w    1                 ; 1 if fade in progress, 0 if idle
PalFadeSpeed:         rs.w    1                 ; frame period between channel steps
PalFadeSpeedCount:    rs.w    1                 ; frame countdown timer
PalFadeStep:          rs.w    1                 ; total steps executed
PalFadeCopper:        rs.l    1                 ; pointer to active Copper list palette block
QuitFadeActive:       rs.w    1                 ; 1 if ESC quit-to-title fade is active
SkyFadeMode:          rs.w    1                 ; SKY_FADE_OFF/IN/OUT: sky follows the palette fade
PalFadeWork:          rs.w    32                ; working copy of 32 colors
PalFadeTarget:        rs.w    32                ; target copy of 32 colors

;------------------------------------------------------------------------------
; Undo / rewind snapshot buffer metadata & scratch
;------------------------------------------------------------------------------
SnapshotHead:         rs.w    1
SnapshotCount:        rs.w    1
                      rs.w    0                 ; alignment pad
ActorSortBuf:         rs.l    MAX_ACTIVE_CRATES ; 16 longwords scratch buffer

;------------------------------------------------------------------------------
; Level complete & Title screen state
;------------------------------------------------------------------------------
LevelCompleteSel:     rs.w    1                 ; 0=PLAY NEXT LEVEL, 1=RETURN TO TITLE
LevelCompletePasswordBuf:        rs.b    8                 ; 6-char password + null + pad
LevelCompleteShimmerTick:        rs.w    1                 ; countdown to gradient rotation
TitleMenuSel:         rs.w    1                 ; selected menu item
TitleLevelNum:        rs.w    1                 ; level number shown/selected
MaxUnlockedLevel:     rs.w    1                 ; highest level unlocked
TitlePassBuf:         rs.b    8                 ; 6-char password + null + pad
TitlePassLen:         rs.w    1                 ; characters entered
TitleCursorTick:      rs.w    1                 ; cursor blink toggle
TitleCursorOn:        rs.w    1                 ; 1 = visible, 0 = hidden
SkyPhase1:            rs.w    1                 ; aurora wave 1 phase
SkyPhase2:            rs.w    1                 ; aurora wave 2 phase

;------------------------------------------------------------------------------
; Text rendering & hero text flash state
;------------------------------------------------------------------------------
FontBold:             rs.w    1                 ; non-zero = bold smear
PurgeFlashTimer:      rs.w    1                 ; frames remaining
PurgeFlashPeriod:     rs.w    1                 ; frames between toggles
PurgeFlashOn:         rs.w    1                 ; non-zero = visible
PurgeFlashAddr:       rs.l    1                 ; screen address of glyph
PurgeFlashString:     rs.l    1                 ; armed string pointer
PurgeFlashAddr2:      rs.l    1                 ; line 2 screen address
PurgeFlashString2:    rs.l    1                 ; armed string 2 pointer
GameOverTimer:        rs.w    1                 ; countdown timer for GAME OVER
FlashScreenTimer:     rs.w    1                 ; countdown timer for flash screen

;------------------------------------------------------------------------------
; Game complete scrolling starfield
;------------------------------------------------------------------------------
GameCompleteStarX:              rs.w    GC_NUM_STARS      ; pixel X positions
GameCompleteStarY:              rs.w    GC_NUM_STARS      ; pixel Y positions
GameCompleteStarRand:           rs.w    1                 ; Galois LFSR state
GameCompleteFrameTick:          rs.w    1                 ; frame counter
GameCompleteHeroPrevY:          rs.w    1                 ; previous companion Y for erase
GameCompleteFadeActive:         rs.w    1                 ; 1 if fade out active
GameCompleteFadeStep:           rs.w    1                 ; throttle countdown

;------------------------------------------------------------------------------
; Tilemap Engine & Camera State
;------------------------------------------------------------------------------
TilemapCameraY:       rs.w    1                 ; camera vertical position in pixels
TilemapScreenOffset:  rs.w    1                 ; visible tile row start offset
TilemapCurrentOffset: rs.w    1                 ; currently drawn tile row offset
TilemapFineY:         rs.w    1                 ; fine vertical pixel scroll
LevelMinCameraY:      rs.w    1                 ; minimum camera scroll Y
LevelMaxCameraY:      rs.w    1                 ; maximum camera scroll Y
LevelCamMarginTop:    rs.w    1                 ; camera upper deadzone margin
LevelCamMarginBottom: rs.w    1                 ; camera lower deadzone margin
CameraCullTopY:       rs.w    1                 ; camera upper culling boundary
CameraCullBottomY:    rs.w    1                 ; camera lower culling boundary

; Ring buffer circular scrolling state
RingBufferCamY:       rs.w    1                 ; buffer scanline Y (TilemapCameraY & 255)
RingBufferTopRow:     rs.w    1                 ; level map tile row currently at top of ring buffer
RingBufferBotRow:     rs.w    1                 ; level map tile row currently at bottom of ring buffer
PrevPlayerCameraY:    rs.w    1                 ; camera Y when player BOB was blitted last frame
RowMirrorSrc:         rs.l    1                 ; streamed row waiting for its other-half copies: buffer offset, -1 = none
RowMirrorDst:         rs.l    1                 ; buffer offset of the other half's copy of that row
RowStreamPrevCamY:    rs.w    1                 ; camera Y at the last row-stream check (gives the scroll direction)

;------------------------------------------------------------------------------
; Debug overlay & pause state
;------------------------------------------------------------------------------
DebugOverlayActive:   rs.w    1                 ; 0=off, 1=on (toggled by 'D' or F5)
SlowMode:             rs.w    1                 ; 0=normal, 1=slow mode
SlowModeHold:         rs.w    1                 ; frame counter for 'A' hold
GamePaused:           rs.w    1                 ; 0=running, 1=paused
PrevPauseCameraY:     rs.w    1                 ; camera Y where pause banner was drawn
PauseSavedPal:       rs.w    32                ; snapshot of 32 colors
PausePaletteActive:  rs.w    1                 ; 1 if dimmed palette is active
PrevKeyS:             rs.w    1                 ; previous 'S' key state
PrevDebugCameraY:     rs.w    1                 ; camera Y of previous debug text
PrevDebugDrawn:       rs.w    1                 ; 1 if debug text was drawn
DebugLineBuf:         rs.b    64                ; text formatting buffer
                      even

;------------------------------------------------------------------------------
; Rising water effect state (engine/effects/water_effects.asm)
;------------------------------------------------------------------------------
WaterPixelY:          rs.w    1                 ; vertical scanline of water surface (-1 = no water)
WaterCurrentRow:      rs.w    1                 ; tile row of the water surface (WaterPixelY >> 4)
WaterSubTick:         rs.w    1                 ; fractional frame accumulator
WaterRisePeriod:      rs.w    1                 ; scaled PAL/NTSC rise period in frames
PlayerSubmerged:      rs.w    1                 ; 1 if the player head is underwater (set by the game)
LiveWaterMap:         rs.b    8+MAX_GAME_MAP_SIZE*2 ; runtime copy of the water layer map: 8-byte header
                                                ; + one word per cell, sized for the tallest map
                                                ; (MAX_MAP_HEIGHT rows) like GameMap. Sizing it from
                                                ; TILEMAP_MAP_TILES (42 rows) let a 43-row level
                                                ; overwrite the bubble state and the Player record.
                      even

;------------------------------------------------------------------------------
; Air bubble effect state (engine/effects/bubble_sprite.asm, SPR6)
;------------------------------------------------------------------------------
BubbleActive:         rs.w    1                 ; 0 = inactive, 1 = rising
BubbleWorldX:         rs.w    1                 ; world pixel X of bubble
BubbleWorldY:         rs.w    1                 ; world pixel Y of bubble
BubbleTimer:          rs.w    1                 ; spawn countdown timer
                      even

    ENDC ; _ENGINE_VARIABLES_I
