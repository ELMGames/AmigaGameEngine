;==============================================================================
; MEADOW RUN - CONSTANTS
; const.asm  -  Map size, physics, timer, HUD and tile constants
;==============================================================================

;------------------------------------------------------------------------------
; Map and tile sheet: read by engine/include/hscroll_variables.i, so this file
; is included before variables.asm
;------------------------------------------------------------------------------
HS_MAP_ROWS         = 14                ; 224 lines: the 216-line window and 8 spare
HS_MAP_COLS         = 128               ; 2,048 pixels: six and a half screens
HS_SHEET_COLS       = 11                ; meadow_tiles.png: 11 x 6 tiles
HS_SHEET_ROW_BYTES  = 22                ; 176 pixels / 8

;------------------------------------------------------------------------------
; Tiles (positions in meadow_tiles.png, counted from 0)
;------------------------------------------------------------------------------
DUCK_TILE           = 55                ; first of the duckling's 4 animation frames
DUCK_FRAMES         = 4
DUCK_FRAME_TICKS    = 8                 ; frames per step: Duck Rescue's 150 ms

;------------------------------------------------------------------------------
; Collision classes: the bytes of a level's -gamemap.bin (export_level.py)
;------------------------------------------------------------------------------
CLASS_EMPTY         = 0
CLASS_SOLID         = 1
CLASS_DUCK          = 2
CLASS_HAZARD        = 3
CLASS_GOAL          = 4

;------------------------------------------------------------------------------
; Mia (Duck Rescue's sprite sheet: 6 rows of 4 frames, 32 x 24 cells)
;------------------------------------------------------------------------------
PLAYER_PLANES       = 4                 ; for engine/graphics/bob_mirror.asm
MIA_SHEET_BYTES     = 16                ; bytes in one plane-row of the sheet
MIA_FRAME_ROW       = MIA_SHEET_BYTES*4*24 ; 1,536 bytes: one row of 4 frames
MIA_HEIGHT          = 24
MIA_CELL_WORDS      = 2                 ; 32-pixel cells (24 pixels drawn)

RUN_SPEED           = 2                 ; pixels per frame
JUMP_SPEED          = 104               ; 1/16 px per frame: a 56-pixel jump
GRAVITY             = 6                 ; 1/16 px per frame, per frame
MAX_FALL            = 96                ; 6 pixels per frame
DEAD_FRAMES         = 60                ; pause after falling in the water
GOAL_FRAMES         = 100               ; pause at the signpost

;------------------------------------------------------------------------------
; The countdown: Meadow Run's pressure, as rising water is Duck Rescue's
;------------------------------------------------------------------------------
TICKS_PER_SECOND    = 50                ; logic ticks: 50 on PAL and NTSC alike
TIMER_WARNING       = 10                ; seconds left when the timer flashes

;------------------------------------------------------------------------------
; HUD sprites (screen positions in pixels, from the window's top-left)
;------------------------------------------------------------------------------
HUD_TIMER_X         = 16                ; SPR0: seconds left, two digits
HUD_TIMER_Y         = 6
HUD_DUCK_X          = 264               ; SPR2: the duckling icon
HUD_DUCK_Y          = 2
HUD_COUNT_X         = 282               ; SPR3: ducklings collected, two digits
HUD_COUNT_Y         = 6
HUD_DIGIT_LINES     = 8
TIMER_COLOUR        = $fff              ; COLOR17: white...
TIMER_WARN_COLOUR   = $f22              ; ...flashing red in the last 10 seconds
DUCK_COLOUR         = $fc2              ; COLOR21: the duckling icon and count...
BEST_FLASH_COLOUR   = $fff              ; ...flashing white after a new best
