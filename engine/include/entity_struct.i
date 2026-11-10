;==============================================================================
; AMIGA GAME ENGINE
; entity_struct.i  -  Patrol enemy, friend and pickup structures and geometry
;==============================================================================
;
; Field offsets and sheet geometry for the entity pools that
; engine/gameplay/entities.asm spawns, moves, draws and erases. A game that
; includes entities.asm includes this file after engine_const.i (from its own
; constants file) and entity_variables.i in its Variables block, then defines
; the three pool sizes:
;
;   MAX_ACTIVE_ENEMIES, MAX_ACTIVE_FRIENDS, MAX_ACTIVE_PICKUPS
;
; Sprite sheets: every enemy and friend sheet is 64 pixels wide, holding four
; 16x16 animation frames per row and one row per entity type (Type 1 = row 0).
; The game binds the sheet labels (see ENGINE_CONTRACT.md, "Data bindings").
;==============================================================================

;------------------------------------------------------------------------------
; Shared sheet geometry
;
; TilemapDrawActorSubPixelBOB / TilemapEraseActorBOB (bob_compositor.asm) take
; the frame height at run time (d5); the sheet row width is fixed here because
; "four cels per row" is a sheet-authoring convention, not a per-entity trait.
;------------------------------------------------------------------------------
ACTOR_BOB_SHEET_BYTES     = 8     ; 64px sheet / 8 = 8 bytes per bitplane row

ENEMY_SHEET_BYTES         = ACTOR_BOB_SHEET_BYTES
ENEMY_FRAME_WIDTH         = 16    ; 16px wide
ENEMY_FRAME_HEIGHT        = 16    ; 16px high
ENEMY_FRAMES_PER_ANIM     = 4     ; 4 animation frames per enemy type
ENEMY_ROW_STRIDE          = ENEMY_FRAME_HEIGHT*ENEMY_SHEET_BYTES*TILEMAP_TILE_PLANES ; 512 bytes

FRIEND_SHEET_BYTES        = ACTOR_BOB_SHEET_BYTES
FRIEND_FRAME_WIDTH        = 16    ; Width of 1 friend sprite cel in pixels
FRIEND_FRAME_HEIGHT       = 16    ; Height of 1 friend sprite cel in pixels
FRIEND_ROW_STRIDE         = FRIEND_FRAME_HEIGHT*FRIEND_SHEET_BYTES*TILEMAP_TILE_PLANES ; 512 bytes
FRIEND_ANIM_SPEED         = 8     ; Frames per animation step

ENTITY_TOP_TIER_Y         = 48    ; screen Y splitting the VBlank tier (rows 0..2) from the beam-chasing tier

;------------------------------------------------------------------------------
; Patrol enemy (ActiveEnemies, MAX_ACTIVE_ENEMIES slots)
;------------------------------------------------------------------------------
Enemy_Type                = 0     ; Enemy Type (1..8, 0 = inactive)
Enemy_X                   = 2     ; Current X pixel position (0..319)
Enemy_Y                   = 4     ; Current Y pixel position (0..799)
Enemy_Direction           = 6     ; Direction (+1 = right, -1 = left)
Enemy_Speed               = 8     ; Speed (pixels per frame)
Enemy_PatrolMinX          = 10    ; Left patrol boundary (pixel X)
Enemy_PatrolMaxX          = 12    ; Right patrol boundary (pixel X)
Enemy_AnimFrame           = 14    ; Current animation frame (0..3)
Enemy_PrevX               = 16    ; Previous drawn X pixel position
Enemy_PrevY               = 18    ; Previous drawn Y pixel position
Enemy_Drawn               = 20    ; 1 if previously drawn and needs erase
Enemy_StunTimer           = 22    ; stun countdown (0 = patrolling, >0 = frozen in place)
Enemy_Sizeof              = 24

;------------------------------------------------------------------------------
; Friend: an animated collectable (ActiveFriends, MAX_ACTIVE_FRIENDS slots)
;------------------------------------------------------------------------------
Friend_Type               = 0     ; Friend Type (1..n, 0 = inactive)
Friend_X                  = 2     ; Current World X pixel position (0..319)
Friend_Y                  = 4     ; Current World Y pixel position (0..799)
Friend_AnimFrame          = 6     ; Current animation frame (0..3)
Friend_AnimTimer          = 8     ; Frame timer for the animation
Friend_Collected          = 10    ; 1 if collected, 0 if active
Friend_PrevX              = 12    ; Previous drawn X pixel position
Friend_PrevY              = 14    ; Previous drawn Y pixel position
Friend_Drawn              = 16    ; 1 if previously drawn and needs erase
Friend_Pad                = 18    ; word align
Friend_Sizeof             = 20

;------------------------------------------------------------------------------
; Tile pickup: a static collectable drawn from the tileset
; (ActivePickups, MAX_ACTIVE_PICKUPS slots)
;------------------------------------------------------------------------------
Pickup_Col                = 0     ; Tile Column (0..19)
Pickup_Row                = 2     ; Tile Row (0..41)
Pickup_X                  = 4     ; World X pixel position (Col * 16)
Pickup_Y                  = 6     ; World Y pixel position (Row * 16)
Pickup_Collected          = 8     ; 1 if collected, 0 if active
Pickup_Drawn              = 10    ; 1 if previously drawn and needs erase
Pickup_TileId             = 12    ; Tile index in the tileset
Pickup_Pad                = 14    ; word align
Pickup_Sizeof             = 16
