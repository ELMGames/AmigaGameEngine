;==============================================================================
; DUCK RESCUE - GLOBAL VARIABLES
; variables.asm  -  Game Variable Block Layout in Fast RAM (RS layout)
;==============================================================================
;
; Extends the core AmigaGameEngine variable layout (engine_variables.i) with
; game-specific entity, player, companion, and water state.
;
; Convention:
;   a5 = Variables base pointer throughout the entire program.
;   All fields are accessed as FieldName(a5).
;==============================================================================

    include    "engine_variables.i"

;------------------------------------------------------------------------------
; Player Character State (Mia)
;------------------------------------------------------------------------------
Player:               rs.b    Player_Sizeof   ; Player structure data
PlayerMoved:          rs.w    1               ; non-zero if player moved this frame
PlayerCount:          rs.w    1               ; number of player characters initialised
PlayerFrame:          rs.w    1               ; active player BOB animation frame offset (0..23)
PlayerGfxPtr:         rs.l    1               ; pointer to active player right graphic
PlayerMskPtr:         rs.l    1               ; pointer to active player right mask
PlayerWhitePtr:       rs.l    1               ; pointer to active player white silhouette

;------------------------------------------------------------------------------
; Dynamic Enemy, Companion & Pickup Pools
;------------------------------------------------------------------------------
    include    "entity_variables.i"   ; ActiveEnemies, ActiveFriends, ActivePickups pools


;------------------------------------------------------------------------------
; Player survival & oxygen subsystem state
;------------------------------------------------------------------------------
PlayerLives:          rs.w    1               ; player remaining lives
PlayerOxygen:         rs.w    1               ; oxygen breath counter (0..OXYGEN_MAX)
OxygenKitInventory:   rs.w    1               ; 1 = oxygen kit bottle in inventory
OxygenKitActive:      rs.w    1               ; 1 = enhanced oxygen active
PlayerSafeX:          rs.w    1               ; tile X of last dry ground
PlayerSafeY:          rs.w    1               ; tile Y of last dry ground
PlayerSafePixelX:     rs.w    1               ; pixel X of last dry ground
PlayerSafePixelY:     rs.w    1               ; pixel Y of last dry ground
PlayerDrowning:       rs.w    1               ; 1 if drowning sequence is active
PlayerDrownTimer:     rs.w    1               ; timer for drowning animation/respawn
PlayerAttackTimer:    rs.w    1               ; timer for cane attack swing animation/hitbox
PlayerDeathTimer:     rs.w    1               ; timer for player collapse death animation
PlayerInvincibleTimer: rs.w   1               ; post-respawn invulnerability timer
PlayerPuffTick:       rs.w    1               ; landing puff tick (0 = none, 1..IMPACT_TOTAL_TICKS)
PlayerPuffX:          rs.w    1               ; landing puff tile column
PlayerPuffY:          rs.w    1               ; landing puff tile row
                      even


;------------------------------------------------------------------------------
; Wide-footprint character erase parameters (used by TilemapRestorePlayerOverlaps)
;------------------------------------------------------------------------------
Player_ErasedX:       rs.w    1               ; world pixel X of erased player footprint
Player_ErasedY:       rs.w    1               ; world pixel Y of erased player footprint
Player_ErasedSpan:    rs.w    1               ; horizontal pixel width of erase blit
Player_ErasedFlag:    rs.w    1               ; 1 if player was erased this frame
                      even

Variables_Sizeof:     rs.w    0               ; total size of Variables block in bytes
