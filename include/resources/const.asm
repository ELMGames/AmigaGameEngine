;==============================================================================
; AMIGA GAME ENGINE
; const.asm  -  Global Constants
;==============================================================================
;
; All compile-time constants are defined here.  Nothing in this file emits
; any code or data bytes; it is purely symbol definitions (equates).
;
; Naming convention:
;   FOO_BAR   = a plain value
;   FOOB_X    = bit NUMBER  (B = Bit, for use with BTST/BSET/BCLR)
;   FOOF_X    = bit MASK    (F = Flag, i.e. 1<<bit, for use with AND/OR)
;
; Register conventions used throughout the codebase:
;   a5 = Variables structure base pointer (set once, never changed)
;   a6 = $dff000  CUSTOM chip base       (set once, never changed)
;   a4 = current Player structure pointer
;   a3 = current Actor  structure pointer
;
;==============================================================================


; Hardware register base addresses and offsets
CIAA_BASE           = $bfe001
CIAB_BASE           = $bfd000
DENISEID            = $07e          ; Denise ID register offset ($dff07e)
DENISE_ECS_MIN      = $0004         ; minimum revision ID for ECS/AGA Denise

;------------------------------------------------------------------------------
; DMA control word written to DMACON to enable all subsystems we need.
;
; The Amiga custom chip Agnus controls Direct Memory Access for all subsystems.
; Writing to DMACON with bit 15 (SETCLR) set enables the listed channels.
; All channels must be individually enabled AND the MASTER bit must be set.
;
; DMAF_SETCLR  bit 15 - enable the bits that follow (vs. clear them)
; DMAF_MASTER  bit  9 - master DMA enable gate (mandatory)
; DMAF_RASTER  bit  8 - Bitplane (raster scan) DMA
; DMAF_COPPER  bit  7 - Copper coprocessor DMA
; DMAF_BLITTER bit  6 - Blitter DMA
; DMAF_SPRITE  bit  5 - Hardware sprite DMA
;
; The ! operator in DEVPAC/ASM-ONE is bitwise OR evaluated at assembly time.
;------------------------------------------------------------------------------
BASE_DMA            = DMAF_SETCLR|DMAF_MASTER|DMAF_RASTER|DMAF_COPPER|DMAF_BLITTER!DMAF_SPRITE


;------------------------------------------------------------------------------
; Maximum number of actor slots allocated in the actor pool.
; One slot per map cell is the theoretical maximum (if every cell held an actor).
; MAP_SIZE is defined below.
;------------------------------------------------------------------------------
MAX_ACTORS          = MAP_SIZE


;------------------------------------------------------------------------------
; Display Window registers  (DIWSTRT / DIWSTOP)
;
; The Amiga display window tells Denise which part of the raster scan to make
; visible.  Outside the window, Denise outputs the background colour (COLOR00).
;
; DIWSTRT  = (V_start[7:0] << 8) | H_start[7:0]
; DIWSTOP  = (V_stop[7:0]  << 8) | H_stop[7:0]
;
; Horizontal values are in colour-clock units (one colour clock = 2 lo-res pixels).
; $81 is the standard PAL/NTSC left-edge value.  Subtracting 16 shifts the window
; 16 colour clocks to the left to accommodate the sprite positioning offset used
; in ShowSprite (sprites need extra room on the left side).
;
; Vertical values are raster line numbers.
; Line $2c (44) is the standard top of the display area.
;------------------------------------------------------------------------------
WINDOW_X_START      = $81       ; horizontal display start (colour-clocks)
WINDOW_X_STOP       = $c1          ; horizontal display stop
WINDOW_Y_START      = $2c          ; vertical display start  (raster line 44)

; Vertical display stop: DIWSTOP holds only the LOW 8 bits of the stop line
; (values < $80 are interpreted as line 256+V by the hardware).  Derive it
; from the real stop line so the expression stays correct if SCREEN_HEIGHT
; ever changes:  (44 + 216) & $ff = 260 & $ff = $04.
WINDOW_Y_STOP       = (WINDOW_Y_START+SCREEN_HEIGHT)&$ff


;------------------------------------------------------------------------------
; Player BOB sheet frame offsets.
;
; The player BOB graphics (player_bobs_64x576.raw / .msk) is an interleaved array
; of 96 frames (4-bitplane, 16x24). These constants are frame-index offsets added
; to the player's base BobOffset to select the correct animation cel.
;
; Layout (Player 1 / Cole base = 0, Player 2 / Price base = 48):
;   +0  .. +3    idle right (4 frames)
;   +4  .. +11   walk right (8 frames)
;   +12 .. +15   carry right (4 frames)
;   +16 .. +19   on-ladder climbing (4 frames, rear view)
;   +16          ladder idle frame (static neutral pose when idle on ladder)
;   +20 .. +23   push frames
;   +24 .. +27   slide / dash frames
;   +28 .. +31   falling (4 frames)
;   +32 .. +35   idle left (4 frames)
;   +36 .. +43   walk left (8 frames)
;   +44 .. +47   fall left (4 frames)
;   PLAYER_LEFT_OFFSET added for left-facing versions (32)
;------------------------------------------------------------------------------
PLAYER_LEFT_OFFSET   = 32   ; frame offset for left-facing versions
PLAYER_LADDER_OFFSET = 16   ; frame offset for on-ladder frames
PLAYER_LADDER_IDLE   = 16   ; single frame used when idle/frozen on ladder
PLAYER_FALL_OFFSET   = 28   ; frame offset for falling animation
PLAYER_WALK_OFFSET   = 4    ; frame offset for walking animation

; Backward-compatibility aliases:
PLAYER_SPRITE_LEFT_OFFSET   = PLAYER_LEFT_OFFSET
PLAYER_SPRITE_LADDER_OFFSET = PLAYER_LADDER_OFFSET
PLAYER_SPRITE_LADDER_IDLE   = PLAYER_LADDER_IDLE
PLAYER_SPRITE_FALL_OFFSET   = PLAYER_FALL_OFFSET
PLAYER_SPRITE_WALK_OFFSET   = PLAYER_WALK_OFFSET

;------------------------------------------------------------------------------
; Landing impact smoke animation
;
; When an actor finishes a fall, a 4-frame smoke animation (SPRITE_SMOKE_A..D)
; is blitted over the actor's landed tile for IMPACT_FRAME_TICKS VBlanks per
; frame (16 VBlanks total at 50 Hz ≈ 320 ms).
;
; Sprite sheet indices 98..101 are the smoke cloud frames in sprites.bin
; (row 8, columns 2..5 of the 12×12 grid).
;
; IMPACT_TOTAL_TICKS = IMPACT_FRAME_TICKS * IMPACT_FRAMES = 16
;   Actor_ImpactTick counts 1..IMPACT_TOTAL_TICKS while animating; 0 = idle.
;------------------------------------------------------------------------------
SPRITE_SMOKE_A      = 35    ; smoke puff frame 0 (row 8, col 2)
SPRITE_SMOKE_B      = 36    ; smoke puff frame 1 (row 8, col 3)
SPRITE_SMOKE_C      = 37    ; smoke puff frame 2 (row 8, col 4)
SPRITE_SMOKE_D      = 38    ; smoke puff frame 3 (row 8, col 5)
IMPACT_FRAMES       = 4     ; number of smoke animation frames
IMPACT_FRAME_TICKS  = 4     ; VBlanks displayed per frame
IMPACT_TOTAL_TICKS  = IMPACT_FRAME_TICKS*IMPACT_FRAMES   ; 16 total VBlanks


;------------------------------------------------------------------------------
; Sine / easing table parameters.
;
; sin.bin contains a full-period sine table of SINE_ANGLES signed 16-bit words.
; Values span -$7fff to +$7fff  (i.e. -32767 to +32767).
;
; To look up the sine of an angle (in the range 0..SINE_ANGLES-1):
;   index = angle_in_degrees * SINE_ANGLES / 360
;   value = word at  Sinus + index*2
;
; SINE_x constants are pre-computed table indices for common angles,
; avoiding division at run time.
;
; The quadratic.bin / quartic.bin tables use the same index range and are used
; for easing curves (smooth acceleration / deceleration during movement).
;------------------------------------------------------------------------------
SINE_ANGLES         = (SinusEnd-Sinus)/2    ; total entries in sine table
SINE_RANGE          = $7fff                 ; maximum table value (32767)
SINE_0              = 0                     ; table index for   0 degrees
SINE_1              = SINE_ANGLES/360       ; table index for   1 degree
SINE_45             = SINE_ANGLES/8         ; table index for  45 degrees
SINE_90             = SINE_ANGLES/4         ; table index for  90 degrees
SINE_180            = SINE_90*2             ; table index for 180 degrees
SINE_270            = SINE_90*3             ; table index for 270 degrees


;------------------------------------------------------------------------------
; Number of animated star objects on the loading screen.
;------------------------------------------------------------------------------
LOADING_STAR_COUNT    = 4


;------------------------------------------------------------------------------
; Undo / rewind buffer size.
;
; UNDO_BUFFER_SIZE snapshots are kept in a circular buffer in Fast RAM.
; Must be a power of 2 (AND mask used for circular wrap).
; The buffer holds the initial level state plus UNDO_BUFFER_SIZE-1 move states,
; so the player can rewind up to UNDO_BUFFER_SIZE-1 moves.
;------------------------------------------------------------------------------
UNDO_BUFFER_SIZE    = 8         ; power of 2; 7 undoable moves + initial state


;------------------------------------------------------------------------------
; Pre-combined display window register values written into the copper list.
; Constructed from the individual X/Y constants above.
;------------------------------------------------------------------------------
WINDOW_START        = (WINDOW_Y_START<<8)|WINDOW_X_START
WINDOW_STOP         = (WINDOW_Y_STOP<<8)|WINDOW_X_STOP


;------------------------------------------------------------------------------
; NTSC display window overrides (patched into cpTest at runtime by DetectNTSC).
;
; On NTSC (~242 visible lines, 20..261) the 216-line game display is shifted upwards
; by 16 pixels relative to PAL (starting at line 28 instead of line 44) to align
; with the copper background and visible display area:
;   Y start = line 28 ($1C) -> 8-line top margin from the ~line-20 visible edge.
;   Y stop  = line 244 ($F4) -> (28 + 216 = 244)
; Horizontal extents (WINDOW_X_START / WINDOW_X_STOP) are unchanged.
;
; Only cpTest (game screen) needs patching; cpLoading stops at line 244 which
; already fits within the NTSC visible area without adjustment.
;------------------------------------------------------------------------------
NTSC_WINDOW_Y_START = $1c
NTSC_WINDOW_START   = (NTSC_WINDOW_Y_START<<8)|WINDOW_X_START   ; $1c81
NTSC_WINDOW_STOP    = ($f4<<8)|WINDOW_X_STOP                     ; $f4c1 (line 244)


;------------------------------------------------------------------------------
; Bitplane DMA fetch window  (DDFSTRT / DDFSTOP)
;
; These registers tell Agnus on each raster line when to start and stop reading
; bitplane data from Chip RAM to feed Denise.
;
; Values are in units of colour-clocks / 2  (i.e. every 4 pixels in lo-res).
; FETCH_START = $30 is standard for a screen starting at colour-clock $81.
; FETCH_STOP  = $d0 is the standard stop for a 336-pixel wide screen.
;
; If these are wrong, you will see the display shift horizontally or have
; missing pixels on the left/right edges.
;------------------------------------------------------------------------------
; Bitplane DMA fetch window  (DDFSTRT / DDFSTOP)
;
; For standard 320px lo-res screen starting at colour-clock $81:
; FETCH_START = $38
; FETCH_STOP  = $d0
;------------------------------------------------------------------------------
FETCH_START         = $38          ; bitplane DMA fetch start ($38 for 320px)
FETCH_STOP          = $d0          ; bitplane DMA fetch stop


;------------------------------------------------------------------------------
; Screen / bitplane geometry.
;
; The game uses a 5-bitplane interleaved screen stored in Chip RAM.
; 5 bitplanes = 2^5 = 32 colours.
;
; Screen: 320 x 192 (20 columns x 8 rows of 16x24 tiles).
;
; SCREEN_STRIDE  - byte offset between rows in interleaved layout:
;                  = SCREEN_DEPTH * SCREEN_WIDTH_BYTE = 5 * 40 = 200 bytes
;
; SCREEN_MOD    - modulo written to BPL1MOD / BPL2MOD in copper list:
;                  = (SCREEN_DEPTH - 1) * SCREEN_WIDTH_BYTE = 4 * 40 = 160
;------------------------------------------------------------------------------
SCREEN_WIDTH        = TILE_WIDTH*WALL_PAPER_WIDTH       ; 16 * 20 = 320 pixels
SCREEN_WIDTH_BYTE   = SCREEN_WIDTH/8                    ; 320/8   =  40 bytes/row
SCREEN_HEIGHT       = TILE_HEIGHT*WALL_PAPER_HEIGHT     ; 24 *  9 = 216 pixels
SCREEN_DEPTH        = 5                                 ; bitplanes -> 32 colours
SCREEN_MOD          = SCREEN_WIDTH_BYTE*(SCREEN_DEPTH-1); 40 * 4  = 160
SCREEN_SIZE         = SCREEN_WIDTH_BYTE*SCREEN_HEIGHT*SCREEN_DEPTH ; 40*216*5 = 43200 bytes
SCREEN_STRIDE       = SCREEN_DEPTH*SCREEN_WIDTH_BYTE    ; 5 * 40  = 200 bytes
SCREEN_COLORS       = 32                                ; palette entries

;------------------------------------------------------------------------------
; Blitter constants for tile, shadow and button blits.
;
; TILE_BLT_MOD  - destination modulo for a full-screen tile blit.
;                 = SCREEN_WIDTH_BYTE - 4 = 40 - 4 = 36
;
; TILE_BLT_SIZE - BLTSIZE register value for a tile blit.
;                 = (24*5 << 6) | 2  = (120 << 6) | 2
;------------------------------------------------------------------------------

SHADOW_BLT_MOD      = SCREEN_STRIDE-4                  ; single-plane shadow modulo
SHADOW_BLT_SIZE     = ((24)<<6)+2                      ; 24 rows, 2 words wide

TILE_BLT_MOD        = SCREEN_WIDTH_BYTE-4              ; tile modulo (full screen) = 36
TILE_BLT_SIZE       = ((24*SCREEN_DEPTH)<<6)+2         ; 120 rows (5 planes), 2 words

;------------------------------------------------------------------------------
; Wallpaper (background tile grid) dimensions.
;
; WALL_PAPER_WIDTH / HEIGHT defines the full tile grid including the solid
; border cells around the playable area.  Total = 20 x 8 = 160 cells.
;
; GAME_MAP_SIZE adds one extra row (the ceiling) above WALL_PAPER_HEIGHT,
; used to hold the permanent solid top border row of tiles.
;------------------------------------------------------------------------------
WALL_PAPER_WIDTH    = 20           ; 18 playable cols + 2 side border cols = 20 (320px)
WALL_PAPER_HEIGHT   = 9            ; 8 playable rows + 1 bottom border row = 9 (216px)
WALL_PAPER_SIZE     = WALL_PAPER_WIDTH*WALL_PAPER_HEIGHT    ; 180 cells
GAME_MAP_SIZE       = WALL_PAPER_WIDTH*(WALL_PAPER_HEIGHT+1); 200 cells (inc. ceiling)

; Maximum level map dimensions supported by dynamic GameMap buffer
MAX_MAP_WIDTH       = 20
MAX_MAP_HEIGHT      = 64           ; supports up to 64 rows (Level 1 is 42 rows)
MAX_GAME_MAP_SIZE   = MAX_MAP_WIDTH*MAX_MAP_HEIGHT ; 1280 bytes
TILE_GRID_HEIGHT    = 16           ; 16px tile height in TMX grid


;------------------------------------------------------------------------------
; Button and level counter blitter constants.
;
; Buttons are 19 rows tall (vs 24 for tiles), 4 bytes wide per plane row.
; Level counter is also 19 rows but 6 bytes wide (wider for the digit display).
;
; BUTTON_BLT_SIZE  = (19 rows * 5 planes << 6) | 2 words
; BUTTON2_BLT_SIZE = (19 rows * 5 planes << 6) | 3 words  (wider: 6 bytes)
;------------------------------------------------------------------------------

BUTTON_BLT_MOD      = SCREEN_WIDTH_BYTE-4          ; button modulo (4-byte row)
BUTTON_BLT_SIZE     = ((19*SCREEN_DEPTH)<<6)+2     ; 95 rows, 2 words

BUTTON2_BLT_MOD     = SCREEN_WIDTH_BYTE-6          ; level counter modulo (6-byte row)
BUTTON2_BLT_SIZE    = ((19*SCREEN_DEPTH)<<6)+3     ; 95 rows, 3 words

LEVEL_COUNT_STRIDE  = LEVEL_COUNT_WIDTH_BYTE*SCREEN_DEPTH  ; bytes between level counter rows
LEVEL_COUNT_START   = (LEVEL_COUNT_STRIDE*5)+3     ; byte offset to start of digit area within counter
LEVEL_COUNT_WIDTH_BYTE = 6                         ; bytes per row of the level counter graphic
LEVEL_FONT_WIDTH_BYTE  = 10                        ; bytes per row of the level font
LEVEL_FONT_STRIDE      = 10*SCREEN_DEPTH           ; bytes between level font rows (5 planes)

;------------------------------------------------------------------------------
; Logical game map dimensions.
;
; The playable area inside the solid border is MAP_WIDTH x MAP_HEIGHT = 18 x 8.
; Level data files contain exactly MAP_SIZE = 144 bytes per level.
; Full wallpaper grid is 20 x 9 (18+2 cols x 8+1 rows = 320 x 216 pixels).
;------------------------------------------------------------------------------
MAP_WIDTH           = 18           ; playable tile columns (18)
MAP_HEIGHT          = 8            ; playable tile rows (8)
MAP_SIZE            = MAP_WIDTH*MAP_HEIGHT  ; 144 bytes per level

SORT_COUNT_BYTES    = MAX_MAP_HEIGHT*2  ; 64 Y-rows x 1 word each = 128 bytes (counting sort stack frame)


;------------------------------------------------------------------------------
; Block type identifiers (stored in GameMap / WallpaperWork arrays).
;
; Each byte in the map arrays holds one of these values.
; The InitObject dispatcher in actors.asm uses BLOCK_xxx to choose the correct
; actor initialisation routine.
; PlayerTryMove uses BLOCK_xxx to decide what the player can do when attempting
; to enter that cell (move, push, kill, climb, etc.).
;------------------------------------------------------------------------------
BLOCK_EMPTY         = 0    ; open space - player and actors may enter freely
BLOCK_LADDER        = 1    ; ladder column - player can climb up/down
BLOCK_ENEMYFALL     = 2    ; enemy subject to gravity (falls if unsupported)
BLOCK_PUSH          = 3    ; pushable block - player slides it horizontally
BLOCK_DIRT          = 4    ; breakable dirt - player destroys it on contact
BLOCK_SOLID         = 5    ; impassable wall - nothing passes through
BLOCK_ENEMYFLOAT    = 6    ; floating enemy - not affected by gravity
BLOCK_PLAYERSTART   = 7    ; Player start position marker in level data
BLOCK_PLAYERLADDER  = 9    ; map cell occupied by Player while on a ladder

; Backward compatibility aliases:
;BLOCK_MILLIESTART   = BLOCK_PLAYERSTART
;BLOCK_MILLIELADDER  = BLOCK_PLAYERLADDER

; --- Alien Containment additions (Phase D signature mechanics) ---
BLOCK_COCOON        = 11   ; pushable alien cocoon - hatches into BLOCK_ENEMYFALL
                           ; when its Actor_HatchTick expires (UpdateCocoons);
                           ; counts as an uncontained organism for CheckLevelDone
BLOCK_ACID          = 12   ; static acid pool - impassable to players; any actor
                           ; that falls or is pushed INTO the cell dissolves
                           ; (cloud burst); the cell reverts to BLOCK_ACID after


;------------------------------------------------------------------------------
; Cocoon hatch timing (UpdateCocoons, actors.asm).
;
; COCOON_HATCH_FRAMES is authored in PAL frames and armed through
; ScalePALFrames at actor init, so the real-time duration matches on NTSC.
; The stage thresholds below are compared against the LIVE (already scaled)
; countdown, so stages last slightly longer on NTSC - acceptable, cosmetic.
;
;   tick > STAGE2:  calm     - TILE_COCOON_A held
;   tick > STAGE3:  stirring - A/B alternated every 32 frames
;   tick <= STAGE3: frantic  - A/B alternated every  8 frames
;------------------------------------------------------------------------------
COCOON_HATCH_FRAMES = 1200 ; ~24 s on PAL from level start to hatch
COCOON_STAGE2       = 500  ; frames remaining when the cocoon starts stirring
COCOON_STAGE3       = 200  ; frames remaining when the pulsing turns frantic

;------------------------------------------------------------------------------
; Rainbow Tilemap Engine constants (tilemap.asm)
;------------------------------------------------------------------------------
TILEMAP_TILE_WIDTH       = 16      ; width of each tile in pixels
TILEMAP_TILE_HEIGHT      = 16      ; height of each tile in pixels
TILEMAP_TILE_PLANES      = 4       ; 4 bitplanes (16 colours)
TILEMAP_TILE_BYTES       = TILEMAP_TILE_WIDTH/8   ; 2 bytes per row per bitplane
TILEMAP_TILES_PER_ROW    = 11      ; 11 tiles across four-seasons sheet (176px)
TILEMAP_SHEET_BYTES      = TILEMAP_TILES_PER_ROW*TILEMAP_TILE_BYTES ; 22 bytes per bitplane row

TILEMAP_VIEW_COLS        = 20      ; 20 columns across visible screen (320px)
TILEMAP_VIEW_ROWS        = 13      ; 13 rows visible for 200px (13 * 16 = 208px, clipped at 200)
TILEMAP_BUFFER_ROWS      = 14      ; 14 rows rendered in screen buffer for smooth vertical scroll (224px)
TILEMAP_VIEW_TILES       = TILEMAP_VIEW_COLS*TILEMAP_VIEW_ROWS   ; 260 tiles per 13-row viewport
TILEMAP_BUFFER_TILES     = TILEMAP_VIEW_COLS*TILEMAP_BUFFER_ROWS ; 280 tiles per 14-row buffer

TILEMAP_MAP_WIDTH        = 20      ; level 1 width in tiles
TILEMAP_MAP_HEIGHT       = 42      ; level 1 height in tiles (672px tall)
TILEMAP_MAP_TILES        = TILEMAP_MAP_WIDTH*TILEMAP_MAP_HEIGHT ; 20 * 42 = 840 tiles
TILEMAP_MAX_ROW_OFFSET   = TILEMAP_MAP_HEIGHT-TILEMAP_VIEW_ROWS ; 42 - 13 = 29 maximum start row
TILEMAP_SCREEN_MOD       = SCREEN_WIDTH_BYTE*(TILEMAP_TILE_PLANES-1) ; 40 * 3 = 120 modulo for 4 bitplanes
TILEMAP_LINE_STRIDE      = SCREEN_WIDTH_BYTE*TILEMAP_TILE_PLANES     ; 40 * 4 = 160 bytes per raster scanline
TILEMAP_ROW_STRIDE       = TILEMAP_TILE_HEIGHT*TILEMAP_LINE_STRIDE   ; 16 * 160 = 2560 bytes per tile row

; Water rising mechanics constants (tilemap.asm)
WATER_START_ROW          = 40      ; initial water top row (0-based)
WATER_START_PIXEL_Y      = WATER_START_ROW*TILEMAP_TILE_HEIGHT ; 40 * 16 = 640 initial water surface scanline
WATER_RISE_FRAMES        = 500     ; frames between full tile rises (10 seconds at 50Hz PAL)
WATER_TILE_SURFACE       = 104     ; tile index for animated water surface (TSX id 104, GID 105)
WATER_TILE_DEEP          = 115     ; tile index for deep water (TSX id 115, GID 116)
WATER_STEP_PIXELS        = 1       ; pixels to advance per step (1 or 2 pixels)
WATER_WAVE_HEIGHT        = 5       ; number of pixel rows moving together as the wave graphic

; Camera deadzone margin thresholds (in pixels relative to CameraPixelY)
CAM_MARGIN_TOP           = 1*TILEMAP_TILE_HEIGHT       ; 1 row below top of screen = 16 pixels
CAM_MARGIN_BOTTOM        = (TILEMAP_VIEW_ROWS-2)*TILEMAP_TILE_HEIGHT ; 1 row above bottom of screen (row 11) = 176 pixels

; Level screen buffer holding the entire level: 43 rows (688 scanlines = 110,080 bytes)
LEVEL_SCREEN_ROWS        = 43
LEVEL_SCREEN_HEIGHT      = LEVEL_SCREEN_ROWS*TILEMAP_TILE_HEIGHT ; 43 * 16 = 688 scanlines
LEVEL_SCREEN_SIZE        = LEVEL_SCREEN_HEIGHT*TILEMAP_LINE_STRIDE ; 688 * 160 = 110,080 bytes

; Tile physical attributes (stored in TileAttributesTable in tilemap.asm)
ATTR_EMPTY               = 0       ; open space / air
ATTR_SOLID               = 1       ; solid platform / wall (walkable top / blocking)
ATTR_LADDER              = 2       ; climbable ladder
ATTR_HAZARD              = 3       ; hazard / death / acid
ATTR_PASSTHROUGH         = 4       ; one-way platform (can jump up through)

; Enemy Type Identifiers (from enemies-spritesheet.png)
ENEMY_1_SLIME_CYAN       = 1       ; Cyan Bouncing Slime (Ground Patrol)
ENEMY_2_SLIME_RED        = 2       ; Red Magma Slime (Ground Patrol)
ENEMY_3_WASP_FLY         = 3       ; Flying Wasp / Bee (Air Patrol)
ENEMY_4_BAT_RED          = 4       ; Red Gargoyle Bat (Air / Dive Patrol)
ENEMY_5_CYCLOPS_GREEN    = 5       ; Green Horned Cyclops (Ground Patrol)
ENEMY_6_OCTO_PURPLE      = 6       ; Purple Floating Octo-pod (Air Float)
ENEMY_7_SNAIL_SHELL      = 7       ; Armored Snail (Ground Patrol)
ENEMY_8_GHOST_BLUE       = 8       ; Blue Drip Ghost / Spore (Air Float)

ENEMY_SHEET_BYTES        = 8       ; 64px wide / 8 = 8 bytes per bitplane row
ENEMY_FRAME_WIDTH        = 16      ; 16px wide
ENEMY_FRAME_HEIGHT       = 16      ; 16px high
ENEMY_FRAMES_PER_ANIM    = 4       ; 4 animation frames per enemy type
ENEMY_ROW_STRIDE         = ENEMY_FRAME_HEIGHT*ENEMY_SHEET_BYTES*TILEMAP_TILE_PLANES ; 16 * 8 * 4 = 512 bytes per enemy type (4 frames)

; Player Blitter Object (BOB) geometry equates
PLAYER_WIDTH          = 16    ; player frame width in pixels
PLAYER_HEIGHT         = 24    ; player frame height in pixels
PLAYER_PLANES         = 4     ; 4 bitplanes
PLAYER_SHEET_WIDTH        = 64    ; sheet width in pixels
PLAYER_SHEET_BYTES        = 8     ; 64 / 8 = 8 bytes per plane
PLAYER_ROW_STRIDE         = PLAYER_SHEET_BYTES*PLAYER_PLANES ; 32 bytes per row
PLAYER_FRAME_STRIDE       = PLAYER_ROW_STRIDE*PLAYER_HEIGHT  ; 768 bytes per frame row (4 frames)

; Runtime Active Enemy Structure Offsets (in Variables block)
MAX_ACTIVE_ENEMIES       = 16
ei_Type                  = 0       ; Enemy Type (1..8, 0 = inactive)
ei_X                     = 2       ; Current X pixel position (0..319)
ei_Y                     = 4       ; Current Y pixel position (0..671)
ei_Direction             = 6       ; Direction (+1 = right, -1 = left)
ei_Speed                 = 8       ; Speed (pixels per frame)
ei_PatrolMinX            = 10      ; Left patrol boundary (pixel X)
ei_PatrolMaxX            = 12      ; Right patrol boundary (pixel X)
ei_AnimFrame             = 14      ; Current animation frame (0..3)
ei_PrevX                 = 16      ; Previous drawn X pixel position
ei_PrevY                 = 18      ; Previous drawn Y pixel position
ei_Drawn                 = 20      ; 1 if previously drawn and needs erase, 0 otherwise
ei_PAD                   = 22      ; word align
ei_SIZEOF                = 24



;------------------------------------------------------------------------------
; Tile dimensions.
;
; Tiles are displayed at 16x24 pixels but stored in 32-pixel-wide bitplane rows
; (TILE_WIDTHF = 32) so each row is exactly one longword wide per bitplane.
;
; TILE_SIZE  = total bytes for one tile across all SCREEN_DEPTH bitplanes:
;              (32/8) bytes/row * SCREEN_DEPTH planes * TILE_HEIGHT rows
;              = 4 * 5 * 24 = 480 bytes
;
; SHADOW_SIZE = bytes for one shadow graphic (single bitplane, 32 wide, 24 tall):
;              (32/8) * 24 = 96 bytes
;------------------------------------------------------------------------------
TILE_WIDTH          = 16           ; displayed pixel width
TILE_HEIGHT         = 24           ; displayed pixel height
TILE_WIDTHF         = 32           ; stored pixel width (rounded up to longword)
TILE_SIZE           = (TILE_WIDTHF/8)*SCREEN_DEPTH*TILE_HEIGHT  ; 480 bytes per tile
SHADOW_SIZE         = (TILE_WIDTHF/8)*TILE_HEIGHT               ;  96 bytes per shadow


;------------------------------------------------------------------------------
; Tile grid coverage of the screen (for loop bounds in rendering routines).
;------------------------------------------------------------------------------
TILE_SCREEN_WIDTH   = SCREEN_WIDTH/TILE_WIDTH   ; 320/16 = 20 columns
TILE_SCREEN_HEIGHT  = SCREEN_HEIGHT/TILE_HEIGHT ; 216/24 =  9 rows


;------------------------------------------------------------------------------
; Hardware sprite structure size (bytes).
;
; Each Amiga hardware sprite structure in memory contains:
;   Word 0  - SPRxPOS : V_START[7:0] and H_START[8:1]
;   Word 1  - SPRxCTL : V_STOP[7:0], attach bit, H_START LSB, V_START/STOP bit 8
;   Rows 1..TILE_HEIGHT  - 2 words of pixel data per row (4 bytes each)
;   2 words of zeros to terminate the sprite
;
; Total = 4 (header) + (TILE_HEIGHT * 4) (data) + 4 (terminator) = 104 bytes.
;
; The player uses TWO joined hardware sprites (one attached pair SPR0+SPR1)
; to achieve a 16-pixel-wide, 16-colour (15-colour + transparent) sprite image
; using COLOR16-31.
; SPR0 provides bitplanes 0 & 1, and SPR1 (attached) provides bitplanes 2 & 3.
; Channels SPR2, SPR3, SPR4, and SPR5 are completely free.
;------------------------------------------------------------------------------
SPRITE_SIZE         = 4+(TILE_HEIGHT*4)+4       ; 104 bytes per sprite structure

; Hardware sprite channel assignment:
;   SPR0+1  player character (attached pair 0 — 16 colours from COLOR16-31)
;   SPR2    free (NullSprite)
;   SPR3    free (NullSprite)
;   SPR4    free (NullSprite)
;   SPR5    free (NullSprite)
;   SPR6    air bubble (solo, non-attached; uses COLOR29-31 on tileset-3 levels)
;   SPR7    free (NullSprite — SPR6+7 never attached to avoid OCS colour bleed)
;
; SPR6 is behind SPR0-1 (higher number = lower priority), so the bubble
; appears behind the player sprite when they overlap.
;
; Color note: SPR6 solo uses COLOR29-31.  BubbleInit patches COLOR29-31 to
; bubble colours on tileset-3 levels.  The player palette (COLOR16-31) is
; restored by SetLevelAssets on every level load before BubbleInit runs.
HW_FRAME_SIZE       = 2*SPRITE_SIZE             ; 208 bytes per frame (player_hwsprites.bin)
REALSPRITES_FRAMES  = 96                        ; 48 frames * 2 characters (Molly=0..47, Millie=48..95)
PLAYERHWSPRITES_SIZE = REALSPRITES_FRAMES*HW_FRAME_SIZE  ; 19,968 bytes
FACE_SIZE           = 2560                      ; one face graphic (millie.raw / molly.raw)

; Byte offsets into the cpSprites copper list block (8 bytes per channel pair: PTH+PTL).
SPRITE_CH_SIZE      = 8                         ; bytes per sprite channel entry in copper list
SPRITE_00_OFFSET    = 0*SPRITE_CH_SIZE          ; SPR0PTH/L  - player attached pair 0 (even: planes 0&1)
SPRITE_01_OFFSET    = 1*SPRITE_CH_SIZE          ; SPR1PTH/L  - player attached pair 0 (odd: planes 2&3)
SPRITE_02_OFFSET    = 2*SPRITE_CH_SIZE          ; SPR2PTH/L  - free (NullSprite)
SPRITE_03_OFFSET    = 3*SPRITE_CH_SIZE          ; SPR3PTH/L  - free (NullSprite)
SPRITE_04_OFFSET    = 4*SPRITE_CH_SIZE          ; SPR4PTH/L  - free (NullSprite)
SPRITE_05_OFFSET    = 5*SPRITE_CH_SIZE          ; SPR5PTH/L  - free (NullSprite)
SPRITE_06_OFFSET    = 6*SPRITE_CH_SIZE          ; SPR6PTH/L  - bubble (solo, non-attached)
SPRITE_07_OFFSET    = 7*SPRITE_CH_SIZE          ; SPR7PTH/L  - free (NullSprite)


;------------------------------------------------------------------------------
; Default starting level (0-based index into levels.bin).
;------------------------------------------------------------------------------
START_LEVEL         = 0


;------------------------------------------------------------------------------
; Tile indices into the current loaded tileset (TileSet buffer in Chip RAM).
;
; WallPaperWalls / WallpaperMakeLadders write these values into WallpaperWork
; and WallpaperLadders respectively.  DrawTile / PasteTile then use them to
; select the correct 480-byte block from TileSet to blit to the screen.
;
; Wall tiles (0-8):
;   Single-cell walls, runs with left/right end-caps, 6 interior variants.
; Push tile  (9):    the pushable crate graphic.
; Ladder tiles (10-15):
;   Combinations of: top-cap vs. free-top, middle, bottom-cap.
; Dirt tiles (16-19):
;   4 variants depending on left/right neighbours (for seamless joins).
; Enemy tiles (20-27):
;   4 animation frames each for the falling and floating enemy types.
; Background tile (28):
;   Plain background, used wherever there is no solid wall or game object.
;------------------------------------------------------------------------------
TILE_WALLSINGLE     = 0    ; isolated single wall block
TILE_WALLLEFT       = 1    ; left end-cap of a horizontal wall run
TILE_WALLA          = 2    ; wall interior: random variant A
TILE_WALLB          = 3    ; wall interior: random variant B
TILE_WALLC          = 4    ; wall interior: random variant C
TILE_WALLD          = 5    ; wall interior: random variant D
TILE_WALLE          = 6    ; wall interior: random variant E
TILE_WALLF          = 7    ; wall interior: random variant F
TILE_WALLRIGHT      = 8    ; right end-cap of a horizontal wall run
TILE_PUSH           = 9    ; pushable block
TILE_LADDERA        = 10   ; ladder top, solid above  (resting on ceiling)
TILE_LADDERB        = 11   ; ladder top, free above
TILE_LADDERC        = 12   ; ladder middle section
TILE_LADDERD        = 13   ; ladder bottom section
TILE_LADDERE        = 14   ; ladder bottom, free top
TILE_LADDERF        = 15   ; ladder single-cell, free top
TILE_DIRTA          = 16   ; dirt, no neighbours
TILE_DIRTB          = 17   ; dirt, right neighbour present
TILE_DIRTC          = 18   ; dirt, left neighbour present
TILE_DIRTD          = 19   ; dirt, both neighbours (centre of a run)
TILE_ENEMYFALLA     = 20   ; falling enemy, frame 0
TILE_ENEMYFALLB     = 21   ; falling enemy, frame 1
TILE_ENEMYFALLC     = 22   ; falling enemy, frame 2
TILE_ENEMYFALLD     = 23   ; falling enemy, frame 3
TILE_ENEMYFLOATA    = 24   ; floating enemy, frame 0
TILE_ENEMYFLOATB    = 25   ; floating enemy, frame 1
TILE_ENEMYFLOATC    = 26   ; floating enemy, frame 2
TILE_ENEMYFLOATD    = 27   ; floating enemy, frame 3
TILE_BACK           = 28   ; empty background cell

; --- Alien Containment additions (Phase D) ---
TILE_ACID           = 29   ; acid pool (static background tile, BLOCK_ACID cells)
TILE_COCOON_A       = 30   ; cocoon, calm frame
TILE_COCOON_B       = 31   ; cocoon, pulsing frame


;------------------------------------------------------------------------------
; Sprite-set and tile-set sizes.
;
; Legacy 24x24 actor sprite sheet (actor_sprites.bin) removed.
;
; TILESET_COUNT = total tile types in the loaded tile set:
;   (8*3) = 24 wall types across 3 groups  +  5 additional special tiles
;   + 3 Alien Containment tiles (TILE_ACID, TILE_COCOON_A/B) = full 8x4 sheet.
;   This matches the layout of the tiles_N.pak compressed assets
;   (regenerated via tools/tiles_pipeline.py - see tools/README.md).
;------------------------------------------------------------------------------
SPRITESET_COUNT     = 55                            ; 55 sprite frames
SPRITESET_SIZE      = TILE_SIZE*SPRITESET_COUNT     ; 55 * 480 = 26,400 bytes
TILESET_COUNT       = (8*3)+8                       ; 32 tile types
TILESET_SIZE        = TILE_SIZE*TILESET_COUNT       ; 32 * 480 = 15,360 bytes


;------------------------------------------------------------------------------
; Raw CIA keyboard scan-codes for function keys F1-F10.
;
; The CIA-A chip receives serial data from the keyboard controller.
; After de-serialising, the scan-code byte is bit-rotated and inverted by the
; interrupt handler (see keyboard.asm) to give these 7-bit values.
; They are stored as non-zero bytes in the Keys[] array (indexed by scan-code).
; A non-zero entry means the key is currently pressed.
;
; F1 = $50, F2 = $51 ... F10 = $59
; Used by LevelTest in main.asm to navigate levels during development.
;------------------------------------------------------------------------------
KEY_SPACE           = $40
KEY_BACKSPACE       = $41
KEY_RETURN          = $44
KEY_ESC             = $45
KEY_LEFT            = $4f
KEY_RIGHT           = $4e
KEY_UP              = $4c
KEY_DOWN            = $4d
KEY_A               = $20
KEY_S               = $21
KEY_D               = $22
SLOW_MODE_HOLD_DELAY = 8    ; frames of hold before full-speed advance (~160ms at 50Hz)
KEY_F1              = $50
KEY_F2              = $51
KEY_F3              = $52
KEY_F4              = $53
KEY_F5              = $54
KEY_F6              = $55
KEY_F7              = $56
KEY_F8              = $57
KEY_F9              = $58
KEY_F10             = $59

;------------------------------------------------------------------------------
; Raster CPU-timing bar (debug profiler)
;
; When DebugMode is non-zero, VBlankTick writes DEBUG_RASTER_COLOR to
; COLOR00 at the start of game work and $0000 at the end.  The resulting
; coloured band on screen shows how many raster lines of CPU time each frame
; costs.  A taller bar = more CPU work.  Toggle with F5 during gameplay.
;
; The copper list resets COLOR00 to the correct palette value at the start of
; the next frame, so there is no permanent colour corruption.
;------------------------------------------------------------------------------
DEBUG_RASTER_COLOR  = $f00   ; bright red CPU-busy indicator


;------------------------------------------------------------------------------
; Control input bit definitions.
;
; ReadControls (controls.asm) packs the current digital input state into a
; single byte:
;
;   bit 4 = Fire / Space  -> switch the active player
;   bit 3 = Right
;   bit 2 = Left
;   bit 1 = Down
;   bit 0 = Up
;
; ControlsTrigger  = bits set on the frame a key was FIRST pressed (edge detect)
; ControlsHold     = bits set whenever a key IS held down
;
; CONTROLB_x  = bit position (use with BTST #CONTROLB_x,reg)
; CONTROLF_x  = bit mask     (use with AND.B #CONTROLF_x,reg then TST)
;------------------------------------------------------------------------------
CONTROLB_UP         = 0
CONTROLB_DOWN       = 1
CONTROLB_LEFT       = 2
CONTROLB_RIGHT      = 3
CONTROLB_FIRE       = 4

CONTROLF_UP         = 1<<0  ; $01
CONTROLF_DOWN       = 1<<1  ; $02
CONTROLF_LEFT       = 1<<2  ; $04
CONTROLF_RIGHT      = 1<<3  ; $08
CONTROLF_FIRE       = 1<<4  ; $10


;------------------------------------------------------------------------------
; Game action state-machine values  (stored in ActionStatus).
;
; Each value selects a handler in the JMPINDEX dispatch table at PlayerLogic.
; Only one action can be active at a time; it runs every VBlank until complete,
; then returns to ACTION_IDLE.
;
; ACTION_IDLE        - polling for player input each frame
; ACTION_MOVE        - smooth tile-to-tile movement animation (24 pixel steps)
; ACTION_FALL        - player and actors falling under gravity (eased)
; ACTION_PLAYERPUSH  - animating a pushed block sliding to its new position
;------------------------------------------------------------------------------
ACTION_IDLE         = 0
ACTION_MOVE         = 1
ACTION_FALL         = 2
ACTION_PLAYERPUSH   = 3
ACTION_INTRO        = 4     ; level intro star animation
ACTION_SWITCH       = 5     ; player switch star animation (same body as ACTION_INTRO)


;------------------------------------------------------------------------------
; Enemy tile animation
;
; TILE_ENEMYFALL and TILE_ENEMYFLOAT each have 4 animation frames (A..D).
; AnimateEnemies cycles through them at ENEMY_ANIM_TICKS VBlanks per frame,
; giving ≈3fps on 50Hz PAL hardware.  MUST be a power of 2 (bit-mask test used).
;   frame_index = (TickCounter >> 4) & 3
;------------------------------------------------------------------------------
ENEMY_ANIM_TICKS    = 16    ; VBlanks per enemy animation frame (power of 2)


;------------------------------------------------------------------------------
; Level intro star animation
;
; At the start of each level a large blue star (SPRITE_STAR_LARGE_BLUE) travels from
; the corner of the screen diagonally opposite to Molly's start position toward
; that start position, leaving a trail of small white stars (SPRITE_STAR_SMALL)
; that fade out after INTRO_TRAIL_LIFE VBlanks.
;
; Movement is tile-by-tile, one step every INTRO_STEP_TICKS VBlanks at full speed.
; The star eases out over the last 5 tiles using a Fibonacci-ratio deceleration
; curve (2→3→5→8→13→20 frames/tile) so motion starts fast and settles smoothly.
; Trail pool (INTRO_TRAIL_MAX slots) must hold all concurrent particles:
; INTRO_TRAIL_LIFE / INTRO_STEP_TICKS = 40 / 2 = 20 active at full speed.
;
; Sprite sheet (sprites.bin, 12×12 grid, index = row*12 + col):
;   SPRITE_STAR_LARGE_BLUE       row 11, col 11  = 11*12 + 11 = 143
;   SPRITE_STAR_SMALL        row 11, col  9  = 11*12 +  9 = 141
;   SPRITE_STAR_LARGE_YELLOW row 11, col 10  = 11*12 + 10 = 142
;
; StarLargeTile(a5) selects which large star is drawn:
;   switching Molly->Millie : SPRITE_STAR_LARGE_BLUE       (blue)
;   switching Millie->Molly : SPRITE_STAR_LARGE_YELLOW (yellow)
;   level intro             : SPRITE_STAR_LARGE_BLUE       (blue)
;------------------------------------------------------------------------------
SPRITE_STAR_LARGE_BLUE       = 54   ; large blue   star  (row 11, col 11)
SPRITE_STAR_LARGE_YELLOW = 55   ; large yellow star  (row 11, col 10)
SPRITE_STAR_SMALL        = 53   ; small white  star  (row 11, col  9)
INTRO_STEP_TICKS    = 2     ; VBlanks per step at full speed (fast launch phase)
INTRO_TRAIL_LIFE    = 40    ; VBlanks each trail particle remains visible
INTRO_TRAIL_MAX     = 24    ; trail pool size (>= INTRO_TRAIL_LIFE/INTRO_STEP_TICKS = 20)
INTRO_HOLD_TICKS    = 60    ; VBlanks the large star holds at the target (~1.2s PAL)
SWITCH_HOLD_TICKS   = 20    ; VBlanks the large star holds during player-switch (~0.4s PAL)
INTRO_TICKS_D5      = 3     ; VBlanks/step at 5 tiles from target
INTRO_TICKS_D4      = 5     ; VBlanks/step at 4 tiles from target
INTRO_TICKS_D3      = 8     ; VBlanks/step at 3 tiles from target
INTRO_MID_TICKS     = 13    ; VBlanks/step at 2 tiles from target
INTRO_NEAR_TICKS    = 20    ; VBlanks/step at 1 tile from target (and overshoot return)


;------------------------------------------------------------------------------
; Enemy death cloud animation
;
; When an enemy is killed by the player, a 7-frame cloud animation plays at
; the enemy's tile position.
;
; Sprite sheet (sprites.bin, 12×12 grid, index = row*12 + col):
;   row 11, cols 0..6 → indices 132..138
;
; CLOUD_TOTAL_TICKS = CLOUD_FRAME_TICKS * CLOUD_FRAMES = 56 VBlanks (~1120ms PAL)
;   Actor_CloudTick counts 1..CLOUD_TOTAL_TICKS while animating; 0 = idle.
;   CLOUD_FRAME_TICKS must be a power of 2; LOG2_CLOUD_FRAME_TICKS = log2(CLOUD_FRAME_TICKS).
;------------------------------------------------------------------------------
SPRITE_CLOUD_A          = 46   ; cloud frame 0  (row 11, col 0)
SPRITE_CLOUD_B          = 47   ; cloud frame 1  (row 11, col 1)
SPRITE_CLOUD_C          = 48   ; cloud frame 2  (row 11, col 2)
SPRITE_CLOUD_D          = 49   ; cloud frame 3  (row 11, col 3)
SPRITE_CLOUD_E          = 50   ; cloud frame 4  (row 11, col 4)
SPRITE_CLOUD_F          = 51   ; cloud frame 5  (row 11, col 5)
SPRITE_CLOUD_G          = 52   ; cloud frame 6  (row 11, col 6)
CLOUD_FRAMES            = 7
CLOUD_FRAME_TICKS       = 8
LOG2_CLOUD_FRAME_TICKS  = 3
CLOUD_TOTAL_TICKS       = CLOUD_FRAME_TICKS*CLOUD_FRAMES   ; 56

;------------------------------------------------------------------------------
; Dirt block destruction animation
;
; When a dirt block is destroyed by the player, a 6-frame crumble animation
; plays at the tile position.
;
; Sprite sheet (sprites.bin, 12×12 grid, index = row*12 + col):
;   row 10, cols 0..5 → indices 120..125
;
; DIRT_TOTAL_TICKS = DIRT_FRAME_TICKS * DIRT_FRAMES = 48 VBlanks (~960ms PAL)
;   Actor_DirtTick counts 1..DIRT_TOTAL_TICKS while animating; 0 = idle.
;   DIRT_FRAME_TICKS must be a power of 2; LOG2_DIRT_FRAME_TICKS = log2(DIRT_FRAME_TICKS).
;------------------------------------------------------------------------------
SPRITE_DIRT_A           = 39   ; dirt break frame 0  (row 9, col 0)
SPRITE_DIRT_B           = 40   ; dirt break frame 1  (row 9, col 1)
SPRITE_DIRT_C           = 41   ; dirt break frame 2  (row 9, col 2)
SPRITE_DIRT_D           = 42   ; dirt break frame 3  (row 9, col 3)
SPRITE_DIRT_E           = 43   ; dirt break frame 4  (row 9, col 4)
SPRITE_DIRT_F           = 44   ; dirt break frame 5  (row 9, col 5)
SPRITE_DIRT_G           = 45   ; dirt break frame 6  (row 9, col 6)
DIRT_FRAMES             = 7
DIRT_FRAME_TICKS        = 8
LOG2_DIRT_FRAME_TICKS   = 3
DIRT_TOTAL_TICKS        = DIRT_FRAME_TICKS*DIRT_FRAMES      ; 56

;------------------------------------------------------------------------------
; Level wipe transition
;
; At the end of each level a screen-wipe effect progressively blacks out every
; tile before the next level loads.  The pattern is chosen at random from
; NUM_WIPE_PATTERNS effects each time.
;
; WipeOppositeTable (in mapstuff.asm) maps each pattern index to its
; directional inverse so a future reveal animation can use the matching effect.
;
; LEVEL_WIPE        - GameStatus value while the wipe is running (state 3)
; LEVEL_HOLD        - GameStatus value while the all-black hold is active (state 4)
; LEVEL_REVEAL      - GameStatus value while the tile-by-tile reveal plays (state 5)
; NUM_WIPE_PATTERNS - distinct wipe effects; MUST be a power of 2
; WIPE_SPEED        - tiles blitted black per VBlank
;                     126 tiles / 2 = 63 frames ≈ 1.26 s at 50 Hz PAL
; WIPE_HOLD_TICKS   - extra frames to hold all-black before loading next level
; WIPE_CENTER_X/Y   - tile coords of the screen centre for radial patterns
; WIPE_MAX_DIST     - max Chebyshev distance from (7,4) in the 14×9 grid
;
; Pattern indices  (also used as WipeOppositeTable indices):
;   WIPE_TOP_BOTTOM  (0) - row by row, top → bottom
;   WIPE_BOTTOM_TOP  (1) - row by row, bottom → top
;   WIPE_LEFT_RIGHT  (2) - column by column, left → right
;   WIPE_RIGHT_LEFT  (3) - column by column, right → left
;   WIPE_DIAG_TLBR   (4) - diagonal stripes, top-left → bottom-right
;   WIPE_DIAG_BRTL   (5) - diagonal stripes, bottom-right → top-left
;   WIPE_CENTER_OUT  (6) - from centre tile outward (Chebyshev distance)
;   WIPE_CENTER_IN   (7) - from edges inward to centre
;------------------------------------------------------------------------------
GAME_INIT           = 0     ; GameStatus: initialze status when Game loads
GAME_LOADING          = 1     ; GameStatus: display loading screen
GAME_RUN            = 2     ; GameStatus: level is setup, and ready/playing'

LEVEL_INIT          = 3     ; GameStatus: initializing a new level (loading data, etc.) 
LEVEL_WIPE          = 4     ; GameStatus: wipe in progress (tiles blitted black)
LEVEL_HOLD          = 5     ; GameStatus: hold all-black while next level loads
LEVEL_REVEAL        = 6     ; GameStatus: reverse-wipe reveal of the new level

LEVEL_COMPLETE_SETUP = 7    ; GameStatus: level-complete screen one-shot init
LEVEL_COMPLETE_RUN   = 8    ; GameStatus: level-complete screen input handler

TITLE_SETUP          = 9    ; GameStatus: title screen one-shot init
TITLE_RUN            = 10   ; GameStatus: title screen per-frame handler

INSTR_SETUP1         = 11   ; GameStatus: instructions page 1 one-shot init
INSTR_RUN1           = 12   ; GameStatus: instructions page 1 input handler
INSTR_SETUP2         = 13   ; GameStatus: instructions page 2 one-shot init
INSTR_RUN2           = 14   ; GameStatus: instructions page 2 input handler

GAME_COMPLETE_SETUP  = 15   ; GameStatus: game complete screen one-shot init
GAME_COMPLETE_RUN    = 16   ; GameStatus: game complete screen per-frame handler

NUM_WIPE_PATTERNS   = 8     ; must be a power of 2 (AND mask used for selection)
WIPE_SPEED          = 4     ; tiles blitted per VBlank (63 frames ≈ 1.26s PAL)
WIPE_HOLD_TICKS             = 20    ; frames to hold black before loading next level (~0.4s)
LEVEL_COMPLETE_HOLD_TICKS   = 40    ; frames to pause on the finished level before the wipe starts (~0.8s PAL)

; Level-transition banner hold durations (LevelBannerShow, levelutils.asm).
; Both are PAL-authored and armed through ScalePALFrames at use.
LEVEL_BANNER_HOLD_TICKS     = 130   ; hold when only the level name+lesson show (~2.6s PAL)
CHAPTER_BANNER_HOLD_TICKS   = 170   ; hold when a chapter title also shows (~3.4s PAL)

WIPE_CENTER_X       = 7     ; centre tile column (0-based, 14-column grid)
WIPE_CENTER_Y       = 4     ; centre tile row    (0-based,  9-row   grid)
WIPE_MAX_DIST       = 7     ; max Chebyshev distance from (7,4) in 14×9 grid

WIPE_TOP_BOTTOM     = 0
WIPE_BOTTOM_TOP     = 1
WIPE_LEFT_RIGHT     = 2
WIPE_RIGHT_LEFT     = 3
WIPE_DIAG_TLBR      = 4
WIPE_DIAG_BRTL      = 5
WIPE_CENTER_OUT     = 6
WIPE_CENTER_IN      = 7

;------------------------------------------------------------------------------
; Air bubble hardware sprite effect (SPR6, tileset-3 underwater levels)
;
; An animated air bubble rises from the active player's head each
; BUBBLE_IDLE_TICKS frames on levels that use tile set 3 (chapters 6 & 8).
;
; SPR6 is used solo (non-attached).  Palette entries it drives:
;   COLOR29 = BUBBLE_COLOR_OUTLINE  -- dark blue-green outline
;   COLOR30 = BUBBLE_COLOR_BODY     -- mid blue fill
;   COLOR31 = BUBBLE_COLOR_HILIGHT  -- bright blue highlight
; These are patched into cpPal by BubbleInit when AssetSet == 3 and
; zeroed (black) for every other tileset.
;
; BubbleSprites (data_chip incbin) holds BUBBLE_FRAMES × BUBBLE_FRAME_SIZE bytes.
; Frame 0 = large bubble; frame 3 = small/near-pop.  Frame index = elapsed >> 3.
;
; Wobble table (8 signed-byte entries) gives ±2px horizontal oscillation.
;------------------------------------------------------------------------------
BUBBLE_PHASE_IDLE       = 0     ; BubblePhase: waiting for next bubble
BUBBLE_PHASE_RISE       = 1     ; BubblePhase: bubble is rising
BUBBLE_FRAMES           = 4     ; number of animation frames (large..small)
BUBBLE_ROWS             = 16    ; sprite height in raster rows
BUBBLE_FRAME_SIZE       = 4+(BUBBLE_ROWS*4)+4   ; 72 bytes: header+rows+terminator
BUBBLE_RISE_TICKS       = 32    ; frames of rise animation (~0.64s PAL)
BUBBLE_IDLE_TICKS       = 80    ; frames between bubbles (~1.6s PAL)
BUBBLE_X_OFFSET         = 4     ; base X: centres 16px bubble on 24px player
BUBBLE_FACING_OFFSET    = 8     ; ±8px shift when player faces left/right (0 on ladder)
BUBBLE_Y_OFFSET         = 2     ; pixels from player tile top edge (near head)
BUBBLE_COLOR_OUTLINE    = $0046 ; COLOR29: dark blue-green (outline)
BUBBLE_COLOR_BODY       = $068C ; COLOR30: mid blue (fill)
BUBBLE_COLOR_HILIGHT    = $0BDF ; COLOR31: light blue (highlight)

;------------------------------------------------------------------------------
; Font selector
;
; Change ActiveFont to RetroFontData to use the dot-matrix LED-display style.
; FontData and RetroFontData are both defined in copperlists.asm.
; All text-blitting routines (CHAR_BLTOneChar, CHAR_BLTGreenChar, CHAR_BLTOneChar)
; reference ActiveFont so a single change here switches the whole UI.
;------------------------------------------------------------------------------
ActiveFont          EQU FontData    ; alternatives: RetroFontData
;ActiveFont          EQU RetroFontData    ; alternatives: RetroFontData

;------------------------------------------------------------------------------
; Game complete screen scrolling starfield (states GAME_COMPLETE_SETUP / GAME_COMPLETE_RUN)
;
; 64 stars in three depth layers (by star index):
;   stars  0-23  speed 1 px/frame  1x1 pixel    far / twinkle
;   stars 24-47  speed 2 px/frame  2x2 pixels   mid-field
;   stars 48-63  speed 4 px/frame  3x1 h-streak foreground (motion-blur look)
;
; Slow stars twinkle: drawing is skipped when (starY & 7) == (GCFrameTick & 7),
; giving each star a 1-in-8 frame dropout at a unique phase.  At 50 Hz this is
; imperceptible as flicker but makes the background feel organically alive.
;
; X and Y both initialised from the Galois LFSR (re-rolled into range) so the
; field is fully populated across the whole screen from the first frame.
;------------------------------------------------------------------------------
GC_NUM_STARS         = 64   ; total star pool (24+24+16)
GC_STAR_MAX_X        = 319  ; max valid pixel X (320-pixel screen)
GC_STAR_MAX_Y        = 184  ; max valid row Y (leave bottom rows clear for text)
GC_STAR_RESPAWN_X    = 319  ; X value on right-edge respawn
GC_STAR_RAND_INIT    = $ACE1 ; nonzero 16-bit Galois LFSR seed
GC_PRESIM_FRAMES     = 320  ; frames pre-simulated in setup so field looks "warmed up"
                            ; 336 = slowest star's full crossing time, ensuring every
                            ; slow star respawns at least once with a fresh LFSR Y


;------------------------------------------------------------------------------
; Palette Fade Subsystem constants (palette_fade.asm)
;
; FADE_SPEED_FAST   - 1 frame per colour step: full fade in ~15 frames (PAL)
;                     Good for abrupt but smooth cuts between states.
; FADE_SPEED_NORMAL - 2 frames per step: full fade in ~30 frames (~0.6s PAL)
;                     Standard transition between title/game/loading states.
; FADE_SPEED_SLOW   - 4 frames per step: full fade in ~60 frames (~1.2s PAL)
;                     Atmospheric; use for game-complete or dramatic moments.
;
; FADE_MAX_STEPS    - maximum steps needed to move any nibble 0->$F or $F->0.
;                     Always 15 (4-bit colour depth).
;
; FADE_OUT / FADE_IN - direction constants stored in PalFadeDir.
;------------------------------------------------------------------------------
FADE_SPEED_FAST      = 1    ; frames between colour steps (fastest)
FADE_SPEED_NORMAL    = 2    ; frames between colour steps (default)
FADE_SPEED_SLOW      = 4    ; frames between colour steps (slowest)
FADE_MAX_STEPS       = 15   ; OCS palette has 4-bit channels (0..$F)
FADE_OUT             = 0    ; direction flag: fade toward black
FADE_IN              = 1    ; direction flag: fade toward target palette

;------------------------------------------------------------------------------
; Player Survival & Oxygen Subsystem constants
;------------------------------------------------------------------------------
DEFAULT_LIVES        = 3    ; starting player lives
OXYGEN_MAX           = 400  ; 8.0 seconds of breath at 50 Hz PAL (400 frames)
OXYGEN_REFILL_RATE   = 4    ; breath replenished per frame when surfaced (+4 -> ~2.0s full)
OXYGEN_CRITICAL      = 100  ; breath critical threshold (last 2.0s / 25%)
PLAYER_HEAD_Y_OFFSET = 10   ; offset from player top scanline to mouth line (accounts for hair)
