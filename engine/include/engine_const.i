;==============================================================================
; AMIGA GAME ENGINE
; engine_const.i  -  Core Engine Compile-Time Constants & Hardware Equates
;==============================================================================
;
; Purely symbol definitions (equates) for custom chipset hardware, display
; geometry, tilemap parameters, input scancodes, state machine IDs, and audio.
;
; Naming convention:
;   FOO_BAR   = a plain value
;   FOOB_X    = bit NUMBER  (B = Bit, for use with BTST/BSET/BCLR)
;   FOOF_X    = bit MASK    (F = Flag, i.e. 1<<bit, for use with AND/OR)
;
; Register conventions:
;   a5 = Variables structure base pointer (held constant)
;   a6 = CUSTOM chip base        (held constant)
;   a4 = current Player structure pointer
;   a3 = current Actor structure pointer
;==============================================================================

    IFND _ENGINE_CONST_I
_ENGINE_CONST_I SET 1

;------------------------------------------------------------------------------
; Hardware register base addresses and offsets
;------------------------------------------------------------------------------
CIAA_BASE           = $bfe001
CIAB_BASE           = $bfd000
DENISE_ID_ECS       = $00FC
DENISE_ID_AGA       = $00F8
; DENISE OCS doesn't have a register, and hence the value read is whatever is on the bus (so if not AGA, and not ECS, then it's OCS)

;------------------------------------------------------------------------------
; DMA control word written to DMACON to enable all required subsystems
;------------------------------------------------------------------------------
BASE_DMA            = DMAF_SETCLR|DMAF_MASTER|DMAF_RASTER|DMAF_COPPER|DMAF_BLITTER|DMAF_SPRITE

;------------------------------------------------------------------------------
; Blitter minterm values for BLTCON0 (low byte/nibbles; USEA|USEB|USEC|USED
; channel-enable bits are already included in each value below).
;
; MINTERM_COOKIE_CUT - D = (A AND B) OR (NOT A AND C).  A = mask, B = graphic,
;                       C = screen background, D = screen.  Where the mask is
;                       1 the graphic wins; where 0 the background passes
;                       through untouched.  This is the engine's standard
;                       transparent/"cookie-cut" sprite and tile blit.
;
; MINTERM_COPY       - D = A (direct copy, no masking).  Used for plain
;                       background-tile blits and BOB erase (restoring a
;                       pristine background tile with no transparency).
;
; A per-tile/per-sprite shift amount (X mod 16) is packed into bits 15:12 by
; ORing/ROR-ing it in on top of these values; see bob_compositor.asm and
; tile_renderer.asm for the shift-packing call sites.
;------------------------------------------------------------------------------
MINTERM_COOKIE_CUT  = $0fca
MINTERM_COPY        = $09f0

;------------------------------------------------------------------------------
; Subsystem Pool Limits
;------------------------------------------------------------------------------
MAX_ACTIVE_CRATES   = 16            ; maximum pushable crate / interactive block slots
UNDO_BUFFER_SIZE    = 16            ; 16 snapshots in circular rewind buffer
SNAP_ACTOR_WORDS    = 6                  ; words saved per actor slot (X, Y, Status, Type, SpriteOffset, Static)
ENEMY_ANIM_TICKS    = 16    ; VBlanks per enemy animation frame

;------------------------------------------------------------------------------
; Actor effect timing (actor_physics.asm)
;
; Ticks of the landing effect after a fall (Actor_ImpactTick, drawn by
; GameActorImpactHook). It only follows a fall of IMPACT_MIN_ROWS rows or
; more, and while it runs the actor cannot be pushed.
;------------------------------------------------------------------------------
IMPACT_FRAMES       = 7             ; landing effect frames
IMPACT_FRAME_TICKS  = 3             ; VBlanks per landing effect frame
IMPACT_TOTAL_TICKS  = IMPACT_FRAME_TICKS*IMPACT_FRAMES ; 21 VBlanks
IMPACT_MIN_ROWS     = 3             ; shortest fall (in tile rows) that raises a landing effect
LOADING_STAR_COUNT  = 4             ; animated star objects on loading screen

;------------------------------------------------------------------------------
; Screen / bitplane geometry (5-bitplane interleaved lo-res display)
;------------------------------------------------------------------------------
SCREEN_WIDTH        = 320                               ; 320 pixels
SCREEN_WIDTH_BYTE   = SCREEN_WIDTH/8                    ; 40 bytes/row
SCREEN_HEIGHT       = 216                               ; 216 pixels visible viewport
SCREEN_DEPTH        = 5                                 ; bitplanes -> 32 colours
SCREEN_MOD          = SCREEN_WIDTH_BYTE*(SCREEN_DEPTH-1); 40 * 4 = 160
SCREEN_SIZE         = SCREEN_WIDTH_BYTE*SCREEN_HEIGHT*SCREEN_DEPTH ; 40*216*5 = 43200 bytes
SCREEN_STRIDE       = SCREEN_DEPTH*SCREEN_WIDTH_BYTE    ; 5 * 40 = 200 bytes
SCREEN_COLORS       = 32                                ; palette entries

;------------------------------------------------------------------------------
; Display Window registers (DIWSTRT / DIWSTOP)
;------------------------------------------------------------------------------
WINDOW_X_START      = $81                               ; horizontal display start (lo-res pixels)
WINDOW_X_STOP       = $c1                               ; horizontal display stop (pixel $1c1)
WINDOW_Y_START      = $2c                               ; vertical display start (raster line 44)
WINDOW_Y_STOP       = (WINDOW_Y_START+SCREEN_HEIGHT)&$ff ; vertical display stop
WINDOW_START        = (WINDOW_Y_START<<8)|WINDOW_X_START
WINDOW_STOP         = (WINDOW_Y_STOP<<8)|WINDOW_X_STOP

; NTSC display window overrides
NTSC_WINDOW_Y_START = $1c
NTSC_WINDOW_START   = (NTSC_WINDOW_Y_START<<8)|WINDOW_X_START ; $1c81
NTSC_WINDOW_STOP    = ($f4<<8)|WINDOW_X_STOP                  ; $f4c1 (line 244)

; Bitplane DMA fetch window (DDFSTRT / DDFSTOP)
FETCH_START         = $38                               ; bitplane DMA fetch start ($38 for 320px)
FETCH_STOP          = $d0                               ; bitplane DMA fetch stop

;------------------------------------------------------------------------------
; Blitter constants for transition tile blits and UI
;------------------------------------------------------------------------------
TILE_BLT_MOD        = SCREEN_WIDTH_BYTE-4               ; tile modulo (full screen) = 36
TILE_BLT_SIZE       = ((24*SCREEN_DEPTH)<<6)+2          ; 120 rows (5 planes), 2 words

BUTTON_BLT_MOD      = SCREEN_WIDTH_BYTE-4               ; button modulo (4-byte row)
BUTTON_BLT_SIZE     = ((19*SCREEN_DEPTH)<<6)+2          ; 95 rows, 2 words

BUTTON2_BLT_MOD     = SCREEN_WIDTH_BYTE-6               ; level counter modulo (6-byte row)
BUTTON2_BLT_SIZE    = ((19*SCREEN_DEPTH)<<6)+3          ; 95 rows, 3 words

LEVEL_COUNT_STRIDE  = LEVEL_COUNT_WIDTH_BYTE*SCREEN_DEPTH ; bytes between level counter rows
LEVEL_COUNT_START   = (LEVEL_COUNT_STRIDE*5)+3          ; byte offset to start of digit area
LEVEL_COUNT_WIDTH_BYTE = 6                              ; bytes per row of the level counter graphic
LEVEL_FONT_WIDTH_BYTE  = 10                             ; bytes per row of the level font
LEVEL_FONT_STRIDE      = 10*SCREEN_DEPTH                ; bytes between level font rows (5 planes)

;------------------------------------------------------------------------------
; Logical game map and tile grid dimensions
;------------------------------------------------------------------------------
MAP_WIDTH           = 20            ; GameMap row stride: every level is 20 cells (320 px) wide
DEFAULT_MAP_ROWS    = 9             ; map height LevelInit sets before the LevelDef gives the real one
DEFAULT_MAP_SIZE    = MAP_WIDTH*DEFAULT_MAP_ROWS ; 180 cells

; Screen-wipe grid: 16x24-pixel blocks covering the 320x216 window
WIPE_GRID_COLS      = 20            ; 20 x 16 px = 320 px
WIPE_GRID_ROWS      = 9             ; 9 x 24 px = 216 px
WIPE_GRID_SIZE      = WIPE_GRID_COLS*WIPE_GRID_ROWS ; 180 blocks

MAX_MAP_WIDTH       = 20
MAX_MAP_HEIGHT      = 64            ; supports up to 64 rows
MAX_GAME_MAP_SIZE   = MAX_MAP_WIDTH*MAX_MAP_HEIGHT ; 1280 bytes
TILE_GRID_HEIGHT    = 16            ; 16px tile height in TMX grid
TILE_WIDTH          = 16            ; displayed pixel width (16px)

SORT_COUNT_BYTES    = MAX_MAP_HEIGHT*2 ; 64 Y-rows x 1 word each = 128 bytes

;------------------------------------------------------------------------------
; Block type identifiers (stored in GameMap / WallpaperWork arrays)
;------------------------------------------------------------------------------
BLOCK_EMPTY         = 0             ; open space - player and actors may enter freely
BLOCK_LADDER        = 1             ; ladder column - player can climb up/down
BLOCK_ENEMYFALL     = 2             ; enemy subject to gravity (falls if unsupported)
BLOCK_PUSH          = 3             ; pushable block - player slides it horizontally
BLOCK_SOLID         = 5             ; impassable wall - nothing passes through
BLOCK_ENEMYFLOAT    = 6             ; floating enemy - not affected by gravity
BLOCK_PLAYERSTART   = 7             ; Player start position marker in level data
BLOCK_PLAYERLADDER  = 9             ; map cell occupied by Player while on a ladder

;------------------------------------------------------------------------------
; Rainbow Tilemap Engine constants
;------------------------------------------------------------------------------
TILEMAP_TILE_WIDTH       = 16       ; width of each tile in pixels
TILEMAP_TILE_HEIGHT      = 16       ; height of each tile in pixels
TILEMAP_TILE_PLANES      = 4        ; 4 bitplanes (16 colours)
TILEMAP_TILE_BYTES       = TILEMAP_TILE_WIDTH/8 ; 2 bytes per row per bitplane
TILEMAP_TILES_PER_ROW    = 11       ; 11 tiles across tileset sheet (176px)
TILEMAP_SHEET_BYTES      = TILEMAP_TILES_PER_ROW*TILEMAP_TILE_BYTES ; 22 bytes per bitplane row

TILEMAP_VIEW_COLS        = 20       ; 20 columns across visible screen (320px)
TILEMAP_VIEW_ROWS        = 13       ; 13 rows visible for 200px (13 * 16 = 208px)
TILEMAP_BUFFER_ROWS      = 14       ; 14 rows rendered in screen buffer for smooth vertical scroll (224px)
TILEMAP_VIEW_TILES       = TILEMAP_VIEW_COLS*TILEMAP_VIEW_ROWS   ; 260 tiles per 13-row viewport
TILEMAP_BUFFER_TILES     = TILEMAP_VIEW_COLS*TILEMAP_BUFFER_ROWS ; 280 tiles per 14-row buffer

TILEMAP_MAP_WIDTH        = 20       ; default width in tiles
TILEMAP_MAP_HEIGHT       = 42       ; default fallback height in tiles
TILEMAP_MAP_TILES        = TILEMAP_MAP_WIDTH*TILEMAP_MAP_HEIGHT ; total tiles
TILEMAP_MAX_ROW_OFFSET   = TILEMAP_MAP_HEIGHT-TILEMAP_VIEW_ROWS ; maximum view row offset
TILEMAP_SCREEN_MOD       = SCREEN_WIDTH_BYTE*(TILEMAP_TILE_PLANES-1) ; 40 * 3 = 120 modulo for 4 bitplanes
TILEMAP_LINE_STRIDE      = SCREEN_WIDTH_BYTE*TILEMAP_TILE_PLANES     ; 40 * 4 = 160 bytes per raster scanline
TILEMAP_ROW_STRIDE       = TILEMAP_TILE_HEIGHT*TILEMAP_LINE_STRIDE   ; 16 * 160 = 2560 bytes per tile row

CAM_MARGIN_TOP           = 1*TILEMAP_TILE_HEIGHT                     ; 1 row below top = 16 pixels
CAM_MARGIN_BOTTOM        = (TILEMAP_VIEW_ROWS-2)*TILEMAP_TILE_HEIGHT ; 1 row above bottom = 176 pixels
CAM_CENTRE_OFFSET        = 100      ; level start / respawn: player's row top sits 100px below the view top

;------------------------------------------------------------------------------
; Vertical Ring Buffer Constants (see docs/RING_BUFFER_GUIDE.pdf)
;
; A level can be up to MAX_SCREEN_ROWS (50) tile rows tall, but each screen
; buffer holds only the 16 rows around the camera, in a ring, plus an exact
; copy of those 16 rows directly below them (the mirror half):
;
;  Level Map in Fast RAM           Screen buffer in Chip RAM (512 lines)
;  +-------------------+           +----------------------------+ Line 0
;  | Row 0             |           | Buffer rows 0..15          |
;  | Row 1             |    ==>    |   (map row R -> R & 15)    |
;  | ...               |           +----------------------------+ Line 256
;  | Row N (<= 50 rows)|           | Mirror rows 16..31         |
;  +-------------------+           |   (copy of rows 0..15)     |
;                                  +----------------------------+ Line 511
;
; Coordinate wrapping is a mask because 256 is a power of 2:
;   Buffer_Y   = World_Y & RING_BUFFER_MASK      (primary copy; +256 = mirror)
;   Buffer_Row = Map_Row & RING_BUFFER_ROW_MASK
;
; The display reads 216 contiguous lines from DisplayScreen + (CamY & 255) * 160.
; The start is at most line 255, so the window ends by line 470 and never
; wraps: no mid-screen Copper split, and no object is ever drawn in two
; pieces. Lines past 255 are read from the mirror half.
;
; Memory footprint:
;   50-row linear buffer: 128,000 bytes * 2 screens = 256,000 bytes (~250 KB)
;   32-row ring + mirror:  81,920 bytes * 2 screens = 163,840 bytes (~160 KB)
;   Chip RAM saved: 92,160 bytes (~90 KB)
;------------------------------------------------------------------------------
RING_BUFFER_ROWS          = 16       ; 16 tile rows in circular ring
RING_BUFFER_HEIGHT        = RING_BUFFER_ROWS*TILEMAP_TILE_HEIGHT ; 256 scanlines ($100)
RING_BUFFER_MASK          = RING_BUFFER_HEIGHT-1                 ; $ff (255) for fast coordinate modulo
RING_BUFFER_ROW_MASK      = RING_BUFFER_ROWS-1                   ; $0f (15) for fast tile row modulo

; 32-Row Continuous Viewport Buffer (16 primary rows + 16 mirror rows)
; Bitplane DMA streams 216 contiguous scanlines from DisplayScreen + (BufferCamY * 160).
; Eliminates mid-screen Copper splits and actor slicing completely.
RING_BUFFER_MIRROR_ROWS   = 16       ; 16 mirrored rows (exact duplicate of rows 0..15)
RING_BUFFER_TOTAL_ROWS    = RING_BUFFER_ROWS+RING_BUFFER_MIRROR_ROWS ; 32 rows
RING_BUFFER_ALLOC_LINES   = RING_BUFFER_TOTAL_ROWS*TILEMAP_TILE_HEIGHT ; 512 scanlines
RING_BUFFER_ALLOC_SIZE    = RING_BUFFER_ALLOC_LINES*TILEMAP_LINE_STRIDE ; 512 * 160 = 81,920 bytes

MIN_SCREEN_ROWS          = 13
MAX_SCREEN_ROWS          = 50
LEVEL_SCREEN_ROWS        = RING_BUFFER_TOTAL_ROWS
LEVEL_SCREEN_HEIGHT      = MAX_SCREEN_ROWS*TILEMAP_TILE_HEIGHT ; 800 scanlines (world level max height)
LEVEL_SCREEN_SIZE        = RING_BUFFER_ALLOC_SIZE ; 81,920 bytes

; LEVEL_TABLE_COUNT (the number of built-in levels) is defined by the game,
; next to its LevelTable, from the table's own length (ENGINE_CONTRACT.md).
START_LEVEL              = 0

; Tile physical attributes (stored in TileAttributesTable)
ATTR_EMPTY               = 0        ; open space / air
ATTR_SOLID               = 1        ; solid platform / wall (walkable top / blocking)
ATTR_LADDER              = 2        ; climbable ladder
ATTR_HAZARD              = 3        ; hazard / death / spikes
ATTR_PASSTHROUGH         = 4        ; one-way platform (can jump up through)

; Tile indices for dynamic actor blocks (tileset-compact)
TILE_PUSH                = 18       ; pushable crate
TILE_ENEMYFALLA          = 20       ; falling enemy, frame 0
TILE_ENEMYFALLB          = 21       ; falling enemy, frame 1
TILE_ENEMYFALLC          = 22       ; falling enemy, frame 2
TILE_ENEMYFALLD          = 23       ; falling enemy, frame 3
TILE_ENEMYFLOATA         = 24       ; floating enemy, frame 0
TILE_ENEMYFLOATB         = 25       ; floating enemy, frame 1
TILE_ENEMYFLOATC         = 26       ; floating enemy, frame 2
TILE_ENEMYFLOATD         = 27       ; floating enemy, frame 3

;------------------------------------------------------------------------------
; Hardware sprite channel offsets into cpSprites copper list
;------------------------------------------------------------------------------
SPRITE_CH_SIZE           = 8                         ; bytes per sprite channel entry
SPRITE_00_OFFSET         = 0*SPRITE_CH_SIZE          ; SPR0
SPRITE_01_OFFSET         = 1*SPRITE_CH_SIZE          ; SPR1
SPRITE_02_OFFSET         = 2*SPRITE_CH_SIZE          ; SPR2
SPRITE_03_OFFSET         = 3*SPRITE_CH_SIZE          ; SPR3
SPRITE_04_OFFSET         = 4*SPRITE_CH_SIZE          ; SPR4
SPRITE_05_OFFSET         = 5*SPRITE_CH_SIZE          ; SPR5
SPRITE_06_OFFSET         = 6*SPRITE_CH_SIZE          ; SPR6
SPRITE_07_OFFSET         = 7*SPRITE_CH_SIZE          ; SPR7

; Audio equates (PTPlayer SfxStructure)
SFX_DEFAULT_PERIOD       = 322                       ; PAL 3546895 / 11025 Hz
SFX_AUTO_CHANNEL         = -1                        ; auto-allocate least busy audio channel

; SFX priority tiers (sfx_pri field, 1..127; higher wins channel-steal contention
; in PTPlayer's _mt_playfx — see games/duck_rescue/include/game_sfx.asm). Named per distinct
; value in use so effects that must stay tied (e.g. both fanfares) share one
; constant instead of two literals that could silently drift apart.
SFX_PRI_AMBIENT          = 25                        ; background ambient (air bubbles)
SFX_PRI_SUBTLE           = 30                        ; subtle rumble (crate push)
SFX_PRI_NORMAL           = 40                        ; everyday action (an attack swing)
SFX_PRI_IMPACT           = 65                        ; impact thump (crate landing)
SFX_PRI_PICKUP           = 70                        ; collectible pickup
SFX_PRI_ACTION           = 80                        ; combat action (enemy stun)
SFX_PRI_PLAYER_ACTION    = 85                        ; distinct player action (rewind)
SFX_PRI_CHIME            = 95                        ; cheerful chime (a friend collected)
SFX_PRI_CRITICAL         = 110                       ; very high priority (player death)
SFX_PRI_FANFARE          = 120                       ; highest priority (level complete / game over)

;------------------------------------------------------------------------------
; Raw CIA keyboard scan-codes
;------------------------------------------------------------------------------
KEY_SPACE                = $40
KEY_BACKSPACE            = $41
KEY_RETURN               = $44
KEY_ESC                  = $45
KEY_LEFT                 = $4f
KEY_RIGHT                = $4e
KEY_UP                   = $4c
KEY_DOWN                 = $4d
KEY_A                    = $20
KEY_S                    = $21
KEY_D                    = $22
KEY_P                    = $19
SLOW_MODE_HOLD_DELAY     = 8                         ; frames of hold before full-speed advance
KEY_F1                   = $50
KEY_F2                   = $51
KEY_F3                   = $52
KEY_F4                   = $53
KEY_F5                   = $54
KEY_F6                   = $55
KEY_F7                   = $56
KEY_F8                   = $57
KEY_F9                   = $58
KEY_F10                  = $59

; Digital control inputs
CONTROLB_UP              = 0
CONTROLB_DOWN            = 1
CONTROLB_LEFT            = 2
CONTROLB_RIGHT           = 3
CONTROLB_FIRE            = 4

CONTROLF_UP              = 1<<0  ; $01
CONTROLF_DOWN            = 1<<1  ; $02
CONTROLF_LEFT            = 1<<2  ; $04
CONTROLF_RIGHT           = 1<<3  ; $08
CONTROLF_FIRE            = 1<<4  ; $10

;------------------------------------------------------------------------------
; Raster CPU-timing bar (debug profiler)
;------------------------------------------------------------------------------
DEBUG_RASTER_VBLANK      = $ff0  ; yellow VBlank priority blit indicator
DEBUG_RASTER_COLOR       = $0f0  ; green CPU-busy indicator
DEBUG_RASTER_OVERRUN     = $f00  ; red CPU-overrun indicator

; Bands drawn while a new tile row streams in (RASTER_BAND, tmx_renderer.asm).
; Each band's height is that step's cost in scanlines.
DEBUG_RASTER_STREAM_DRAW   = $00f ; blue: clear the row and draw its tiles
DEBUG_RASTER_STREAM_WATER  = $fff ; white: apply the water to the row
DEBUG_RASTER_STREAM_COPY   = $f0f ; magenta: copy the row to DisplayScreen
DEBUG_RASTER_STREAM_MIRROR = $0ff ; cyan: next frame, copy it to the other half

;------------------------------------------------------------------------------
; Action state machine values (ActionStatus)
;------------------------------------------------------------------------------
ACTION_IDLE              = 0
ACTION_MOVE              = 1
ACTION_FALL              = 2
ACTION_PUSH              = 3
ACTION_ATTACK            = 4     ; attack animation
ACTION_DEATH             = 5     ; player death/collapse animation

;------------------------------------------------------------------------------
; Engine GameStatus identifiers
;------------------------------------------------------------------------------
GAME_INIT                = 0     ; initialize status when Game loads
GAME_LOADING             = 1     ; display loading screen
GAME_RUN                 = 2     ; level is setup, and playing

LEVEL_INIT               = 3     ; initializing a new level
LEVEL_WIPE               = 4     ; wipe in progress (tiles blitted black)
LEVEL_HOLD               = 5     ; hold all-black while next level loads
LEVEL_REVEAL             = 6     ; reverse-wipe reveal of new level

LEVEL_COMPLETE_SETUP     = 7     ; level-complete screen one-shot init
LEVEL_COMPLETE_RUN       = 8     ; level-complete screen input handler

TITLE_SETUP              = 9     ; title screen one-shot init
TITLE_RUN                = 10    ; title screen per-frame handler

INSTR_SETUP1             = 11    ; instructions page 1 one-shot init
INSTR_RUN1               = 12    ; instructions page 1 input handler
INSTR_SETUP2             = 13    ; instructions page 2 one-shot init
INSTR_RUN2               = 14    ; instructions page 2 input handler
INSTR_SETUP3             = 15    ; instructions page 3 one-shot init
INSTR_RUN3               = 16    ; instructions page 3 input handler
INSTR_SETUP4             = 25    ; instructions page 4 one-shot init
INSTR_RUN4               = 26    ; instructions page 4 input handler

CREDITS_SETUP            = 17    ; credits screen one-shot init
CREDITS_RUN              = 18    ; credits screen input handler

GAME_COMPLETE_SETUP      = 19    ; game complete screen one-shot init
GAME_COMPLETE_RUN        = 20    ; game complete screen per-frame handler

GAME_OVER_SETUP          = 21    ; game over screen one-shot init
GAME_OVER_RUN            = 22    ; game over screen per-frame handler
GAME_OVER_DURATION       = 200   ; 4.0 seconds (200 frames @ 50 Hz PAL)

FLASH_SETUP              = 23    ; flash/splash intro screen one-shot init
FLASH_RUN                = 24    ; flash/splash intro screen per-frame handler
FLASH_DURATION           = 110   ; ~2.2 seconds (110 frames @ 50 Hz PAL)
FLASH_LOGO_X             = 16    ; pixel X of banner left edge
FLASH_LOGO_Y             = 68    ; pixel Y of banner top

;------------------------------------------------------------------------------
; Screen wipes & transitions
;------------------------------------------------------------------------------
NUM_WIPE_PATTERNS        = 8     ; must be a power of 2
WIPE_SPEED               = 4     ; tiles blitted per VBlank
WIPE_HOLD_TICKS          = 20    ; frames to hold black before next level
LEVEL_COMPLETE_HOLD_TICKS = 70   ; frames to pause on finished level for fanfare
LEVEL_BANNER_HOLD_TICKS  = 130   ; hold when level name shows (~2.6s PAL)
CHAPTER_BANNER_HOLD_TICKS = 170  ; hold when chapter title shows (~3.4s PAL)

WIPE_CENTER_X            = 9
WIPE_CENTER_Y            = 4
WIPE_MAX_DIST            = 10

WIPE_TOP_BOTTOM          = 0
WIPE_BOTTOM_TOP          = 1
WIPE_LEFT_RIGHT          = 2
WIPE_RIGHT_LEFT          = 3
WIPE_DIAG_TLBR           = 4
WIPE_DIAG_BRTL           = 5
WIPE_CENTER_OUT          = 6
WIPE_CENTER_IN           = 7

;------------------------------------------------------------------------------
; Palette Fade Subsystem
;------------------------------------------------------------------------------
FADE_SPEED_FAST          = 1     ; frames between colour steps (fastest)
FADE_SPEED_NORMAL        = 2     ; frames between colour steps (default)
FADE_SPEED_SLOW          = 4     ; frames between colour steps (slowest)
FADE_MAX_STEPS           = 15    ; OCS palette has 4-bit channels (0..$F)
FADE_OUT                 = 0     ; direction flag: fade toward black
FADE_IN                  = 1     ; direction flag: fade toward target palette

;------------------------------------------------------------------------------
; Game Complete scrolling starfield
;------------------------------------------------------------------------------
GC_NUM_STARS             = 64    ; total star pool
GC_STAR_MIN_Y            = 23    ; min valid row Y
GC_STAR_MAX_X            = 319   ; max valid pixel X
GC_STAR_MAX_Y            = 184   ; max valid row Y
GC_STAR_RESPAWN_X        = 319   ; X value on right-edge respawn
GC_STAR_RAND_INIT        = $ACE1 ; nonzero 16-bit Galois LFSR seed
GC_PRESIM_FRAMES         = 320   ; frames pre-simulated in setup

;------------------------------------------------------------------------------
; Sine / easing table parameters
;------------------------------------------------------------------------------
SINE_ANGLES              = (SinusEnd-Sinus)/2 ; total entries in sine table
SINE_RANGE               = $7fff              ; maximum table value (32767)
SINE_0                   = 0                  ; table index for 0 degrees
SINE_1                   = SINE_ANGLES/360    ; table index for 1 degree
SINE_45                  = SINE_ANGLES/8      ; table index for 45 degrees
SINE_90                  = SINE_ANGLES/4      ; table index for 90 degrees
SINE_180                 = SINE_90*2          ; table index for 180 degrees
SINE_270                 = SINE_90*3          ; table index for 270 degrees

    ENDC ; _ENGINE_CONST_I
