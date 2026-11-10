;==============================================================================
; DUCK RESCUE - GAME CONSTANTS
; const.asm  -  Game-Specific Gameplay, Entity and Asset Constants
;==============================================================================
;
; This file defines game-specific parameters for Duck Rescue.
; Core Amiga hardware registers, display geometry, engine states, and tilemap
; parameters are defined in the reusable engine framework (engine_const.i).
;==============================================================================

    include    "engine_const.i"
    include    "entity_struct.i"      ; Enemy_/Friend_/Pickup_ structs and sheet geometry

;------------------------------------------------------------------------------
; Player Character BOB Frame Offsets & Timing (Mia)
;
; The player BOB sheet (player_bobs_female_128x144.raw / .msk) contains 24 frames
; (4 bitplanes, 24x24 active pixels within 32px cell storage).
; Left-facing frames are generated dynamically in Chip RAM at boot.
;
; Layout (24 frames total, 6 rows x 4 frames):
;   Row 0: frames  0..3  = Idle right
;   Row 1: frames  4..7  = Walk right
;   Row 2: frames  8..11 = Attack right (cane swing)
;   Row 3: frames 12..15 = Death right (collapse)
;   Row 4: frames 16..19 = On-ladder climbing (rear view)
;   Row 5: frames 20..23 = Falling (flailing)
;------------------------------------------------------------------------------
PLAYER_IDLE_OFFSET        = 0    ; frame offset for idle right (0..3)
PLAYER_WALK_OFFSET        = 4    ; frame offset for walking right (4..7)
PLAYER_ATTACK_OFFSET      = 8    ; frame offset for cane strike right (8..11)
PLAYER_DEATH_OFFSET       = 12   ; frame offset for death/collapse animation (12..15)
PLAYER_LADDER_OFFSET      = 16   ; frame offset for on-ladder frames (16..19)
PLAYER_LADDER_IDLE        = 16   ; single frame used when idle/frozen on ladder
PLAYER_FALL_OFFSET        = 20   ; frame offset for falling animation (20..23)

ATTACK_DURATION           = 12   ; total frames of attack swing (~240ms)
ATTACK_HIT_TICK           = 9    ; tick when forward strike connects with hitbox
PLAYER_DEATH_DURATION     = 48   ; frames of collapse death animation (~960ms)

ENEMY_STUN_DURATION       = 200  ; stun duration: ~4.0 seconds (200 frames PAL)
ENEMY_RECOVERY_FLASH_TICKS= 75   ; final ~1.5 seconds warning: rapid white flash

PLAYER_LEFT_OFFSET        = 0    ; base frame offset for the left-facing (mirrored) sprite sheet

;------------------------------------------------------------------------------
; Water rising mechanics constants
;------------------------------------------------------------------------------
WATER_START_ROW           = 41    ; initial water top row (0-based)
WATER_START_PIXEL_Y       = WATER_START_ROW*TILEMAP_TILE_HEIGHT ; 41 * 16 = 656
WATER_RISE_FRAMES         = 500   ; frames between full tile rises (10s PAL)
WATER_TILE_SURFACE        = 47    ; tile index for animated water surface
WATER_TILE_DEEP           = 48    ; tile index for deep water
WATER_STEP_PIXELS         = 1     ; pixels to advance per step
WATER_WAVE_HEIGHT         = 5     ; number of pixel rows moving together

;------------------------------------------------------------------------------
; Enemy Type Identifiers & Geometry
;------------------------------------------------------------------------------
ENEMY_1_MUSHROOM_HOP      = 1     ; Mushroom Sporeling (Ground Patrol)
ENEMY_2_HORNET_FLY        = 2     ; Buzzing Hornet (Air Patrol)
ENEMY_3_HEDGEHOG_SCUTTLE  = 3     ; Spiky Hedgehog (Ground Patrol)

; Landing smoke puff (landing_puff.asm): 7 frames of 16x16, 4 per 64px sheet row
SMOKE_FRAME_HEIGHT        = 16
SMOKE_ROW_STRIDE          = SMOKE_FRAME_HEIGHT*ACTOR_BOB_SHEET_BYTES*TILEMAP_TILE_PLANES ; 512 bytes

; Dizzy Stars Blitter Object geometry equates (for stunned enemies)
DIZZY_STARS_FRAME_WIDTH   = 16
DIZZY_STARS_FRAME_HEIGHT  = 16
DIZZY_STARS_FRAMES        = 4
DIZZY_STARS_SHEET_BYTES   = 8
DIZZY_STARS_SIZE          = DIZZY_STARS_FRAME_HEIGHT*DIZZY_STARS_SHEET_BYTES*TILEMAP_TILE_PLANES ; 512 bytes

;------------------------------------------------------------------------------
; Player Blitter Object (BOB) geometry equates
;------------------------------------------------------------------------------
PLAYER_WIDTH              = 24    ; player frame width in pixels
PLAYER_HEIGHT             = 24    ; player frame height in pixels
PLAYER_PLANES             = 4     ; 4 bitplanes
PLAYER_TOTAL_FRAMES       = 24    ; 24 sprites in total (6 rows x 4 frames)
PLAYER_SHEET_WIDTH        = 128   ; sheet width in pixels (4 cels x 32px cell storage)
PLAYER_SHEET_BYTES        = 16    ; 128 / 8 = 16 bytes per plane
PLAYER_ROW_STRIDE         = PLAYER_SHEET_BYTES*PLAYER_PLANES ; 64 bytes per row
PLAYER_FRAME_STRIDE       = PLAYER_ROW_STRIDE*PLAYER_HEIGHT  ; 1536 bytes per frame row
PLAYER_BOB_TOTAL_BYTES    = PLAYER_FRAME_STRIDE*6            ; 9216 bytes
PLAYER_INVINCIBLE_DURATION= 100   ; 2.0s PAL post-respawn invulnerability timer

; Pool size (Enemy_* struct: engine/include/entity_struct.i)
MAX_ACTIVE_ENEMIES        = 16

;------------------------------------------------------------------------------
; Animal Friend Types (16x16 cels, 4 frames; Friend_* struct in entity_struct.i)
;------------------------------------------------------------------------------
FRIEND_DOG1               = 1     ; Dog 1 (Tan Dog / Shiba, Row 0)
FRIEND_DOG2               = 2     ; Dog 2 (White Dog / Puppy, Row 1)
FRIEND_DUCKLING           = 3     ; Duckling (Row 2)

; Legacy aliases
FRIEND_BUNNY              = 1
FRIEND_PUPPY              = 2
FRIEND_LION               = 2
FRIEND_KITTEN             = 1
FRIEND_CHICK              = 3

MAX_ACTIVE_FRIENDS        = 16    ; Maximum simultaneously tracked friends

;------------------------------------------------------------------------------
; Oxygen Refill Pickup Constants
;------------------------------------------------------------------------------
MAX_ACTIVE_PICKUPS         = 8     ; Maximum simultaneously tracked oxygen refills
TILE_OXYGEN_REFILL        = 95    ; Default tile index in world tileset

;------------------------------------------------------------------------------
; Air bubble hardware sprite colors (SPR6, hud_sprites.asm)
;------------------------------------------------------------------------------
BUBBLE_COLOR_OUTLINE      = $0046 ; COLOR29: dark blue-green (outline)
BUBBLE_COLOR_BODY         = $068C ; COLOR30: mid blue (fill)
BUBBLE_COLOR_HILIGHT      = $0BDF ; COLOR31: light blue (highlight)

;------------------------------------------------------------------------------
; Font selector
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; Player Survival & Oxygen Subsystem constants
;------------------------------------------------------------------------------
DEFAULT_LIVES             = 3     ; starting player lives
OXYGEN_MAX                = 400   ; 8.0 seconds of breath at 50 Hz PAL (400 frames)
OXYGEN_REFILL_RATE        = 4     ; breath replenished per frame when surfaced
OXYGEN_CRITICAL           = 100   ; breath critical threshold (last 2.0s / 25%)
PLAYER_HEAD_Y_OFFSET      = 10    ; offset from player top scanline to mouth line
