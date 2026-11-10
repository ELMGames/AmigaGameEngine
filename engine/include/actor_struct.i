;==============================================================================
; AMIGA GAME ENGINE
; actor_struct.i  -  Pushable Block / Physics Actor Data Structure
;==============================================================================

    IFND _ENGINE_ACTOR_STRUCT_I
_ENGINE_ACTOR_STRUCT_I SET 1

;==============================================================================
; Actor structure  (Actor_Sizeof bytes)
;
; In this engine, an "actor" is a pushable crate / interactive block (BLOCK_PUSH)
; that occupies a tile cell, can be slid by the player, and falls under gravity.
;
; Field descriptions:
;   Actor_Status      - 0 = dead/free slot, 1 = alive
;   Actor_X / Y       - current tile position in the game grid
;   Actor_PrevX / Y   - position at the start of the last move (for clear)
;   Actor_XDec / YDec - sub-tile pixel offset during animated push/fall
;   Actor_DirectionX  - horizontal movement direction: -1, 0 or +1
;   Actor_DirectionY  - vertical movement direction:   -1, 0 or +1
;   Actor_HasMoved    - set to 1 when the actor changed tile this frame
;   Actor_HasFalled   - set to 1 while the actor is falling
;   Actor_Type        - BLOCK_xxx type (used during init, may be repurposed)
;   Actor_SpriteOffset - tile index in TileSet to draw this actor
;   Actor_CanFall     - 1 if this actor is subject to gravity (EnemyFall, Push)
;   Actor_Static      - 1 if this actor is drawn statically (not animated)
;   Actor_Delta       - longword easing accumulator for push animation
;   Actor_FallY       - target YDec pixel value at which the fall animation ends
;==============================================================================

                          rsreset
Actor_Status:             rs.w    1   ; 0=dead, 1=alive
Actor_X:                  rs.w    1   ; tile column
Actor_Y:                  rs.w    1   ; tile row
Actor_PrevX:              rs.w    1   ; previous tile column (used by clear routines)
Actor_PrevY:              rs.w    1   ; previous tile row
Actor_XDec:               rs.w    1   ; sub-tile X pixel offset (push animation)
Actor_YDec:               rs.w    1   ; sub-tile Y pixel offset (fall animation)
Actor_DirectionX:         rs.w    1   ; horizontal direction: -1, 0 or +1
Actor_DirectionY:         rs.w    1   ; vertical direction:   -1, 0 or +1
Actor_HasMoved:           rs.w    1   ; flag: actor moved this frame
Actor_HasFalled:          rs.w    1   ; flag: actor is in a fall animation
Actor_Type:               rs.w    1   ; original BLOCK_xxx type from the map
Actor_SpriteOffset:       rs.w    1   ; tile index into TileSet for rendering
Actor_CanFall:            rs.w    1   ; 1 = subject to gravity
Actor_Static:             rs.w    1   ; 1 = drawn once into DisplayScreen (no update)
Actor_Delta:              rs.l    1   ; fixed-point easing accumulator (push anim)
Actor_FallY:              rs.w    1   ; pixel target for end of fall animation
Actor_ImpactTick:         rs.w    1   ; landing smoke tick: 0=idle, 1..IMPACT_TOTAL_TICKS=animating
Actor_Reserved1:          rs.w    1   ; reserved slot (preserves struct alignment & size)
Actor_Dirty:              rs.w    1   ; 1 = needs redraw via DrawStaticActors; 0 = already drawn
Actor_PixelX:             rs.w    1   ; cached pixel X = Actor_X * 16 (kept in sync with Actor_X)
Actor_PixelY:             rs.w    1   ; cached pixel Y = Actor_Y * 16 (kept in sync with Actor_Y)
Actor_IsPlayer:           rs.w    1   ; 1 = proxy for the frozen player; draw via DrawPlayerFrozen
Actor_Sizeof:             rs.w    0   ; total structure size in bytes

    ENDC ; _ENGINE_ACTOR_STRUCT_I
