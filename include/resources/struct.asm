
;==============================================================================
; AMIGA GAME ENGINE
; struct.asm  -  Data Structure Definitions
;==============================================================================
;
; Defines the field offsets for all record types used by the game, using the
; DEVPAC/ASM-ONE RS (Record Size) directives:
;
;   RSRESET        - reset the RS counter to 0
;   label: rs.w 1  - allocate 1 word (2 bytes), label = current offset, advance by 2
;   label: rs.b 1  - allocate 1 byte, label = current offset, advance by 1
;   label: rs.l 1  - allocate 1 longword (4 bytes)
;   label: rs.w 0  - allocate nothing; label captures the current total size
;
; Usage:  given a base address in register A4, field FOO is at FOO(a4).
; All word fields are naturally word-aligned.
;
;==============================================================================


;==============================================================================
; Player structure  (Player_Sizeof bytes)
;
; Holds the complete state of the single player character.
; Lives in the Variables block as: Player: rs.b Player_Sizeof.
; a4 is the convention register for a pointer to the player struct.
;
; Field descriptions:
;   Player_Status       - 0 = inactive, 1 = active/controlled
;   Player_X / Y        - current tile-grid position (0-based column / row)
;   Player_XDec / YDec  - sub-tile pixel offset used during ACTION_MOVE and
;                         ACTION_FALL to animate smooth movement between tiles
;   Player_ActionCount  - countdown frames remaining in the current action
;   Player_PrevX / Y    - position at the start of the last move, used to
;                         clear the player's previous screen location
;   Player_NextX / Y    - destination tile for the current move or fall action
;   Player_BobOffset    - base frame index in PlayerRaw/Msk for this character
;                         (0 = Cole, 48 = Price)
;   Player_FrozenBobBase - base frame index for frozen pose (ladder or standing)
;   Player_AnimFrame    - current animation frame counter (0..7 walk, 0..3 idle)
;   Player_Facing       - direction the character faces:
;                         positive (e.g. +1) = right, negative (-1) = left
;   Player_OnLadder     - non-zero when the player is currently on a ladder
;   Player_LadderFreezeId - frame used to draw the static image on ladder
;   Player_DirectionX   - horizontal movement intent: -1, 0 or +1
;   Player_DirectionY   - vertical movement intent:   -1, 0 or +1
;   Player_Fallen       - non-zero while the player is in a fall animation
;   Player_ActionFrame  - sub-frame counter used by the fall easing calculation
;   Player_BlockId      - BLOCK_PLAYERSTART - the map cell
;                         value used to mark the player's presence in GameMap
;   Player_LadderId     - BLOCK_PLAYERLADDER - the map
;                         cell value used while the player is on a ladder
;==============================================================================

                          RSRESET
Player_Status:            rs.w    1   ; 0=inactive, 1=active
Player_X:                 rs.w    1   ; tile column (0..WALL_PAPER_WIDTH-1)
Player_Y:                 rs.w    1   ; tile row    (0..WALL_PAPER_HEIGHT-1)
Player_XDec:              rs.w    1   ; sub-tile horizontal pixel offset (+/-)
Player_YDec:              rs.w    1   ; sub-tile vertical   pixel offset (+/-)
Player_ActionCount:       rs.w    1   ; frames remaining in current move (24 per tile)
Player_PrevX:             rs.w    1   ; screen pixel X at start of last move (for BOB erase)
Player_PrevY:             rs.w    1   ; screen pixel Y at start of last move (for BOB erase)
Player_PrevDrawn:         rs.w    1   ; non-zero if player was blitted last frame
Player_NextX:             rs.w    1   ; destination tile column for current action
Player_NextY:             rs.w    1   ; destination tile row    for current action
Player_BobOffset:         rs.w    1   ; base BOB frame index (0=Cole, 48=Price)
Player_FrozenBobBase:     rs.w    1   ; base BOB frame index for frozen pose
Player_SpriteOffset       = Player_BobOffset       ; alias for compatibility
Player_FrozenSpriteBase   = Player_FrozenBobBase   ; alias for compatibility
Player_AnimFrame:         rs.w    1   ; current animation frame (wraps per-action)
Player_Facing:            rs.w    1   ; +1 = facing right, -1 = facing left
Player_OnLadder:          rs.w    1   ; 0 = on ground,  non-zero = on ladder
Player_LadderFreezeId:    rs.w    1   ; sprite frame for frozen-on-ladder display
Player_DirectionX:        rs.w    1   ; intended X move: -1=left, 0=none, +1=right
Player_DirectionY:        rs.w    1   ; intended Y move: -1=up,   0=none, +1=down
Player_Fallen:            rs.w    1   ; non-zero while fall animation is active
Player_ActionFrame:       rs.w    1   ; easing sub-frame index for fall animation
Player_BlockId:           rs.b    1   ; BLOCK_PLAYERSTART
Player_LadderId:          rs.b    1   ; BLOCK_PLAYERLADDER
Player_PixelX:            rs.w    1   ; cached pixel X = Player_X * 24 (updated on every tile commit)
Player_PixelY:            rs.w    1   ; cached pixel Y = Player_Y * 24 (updated on every tile commit)
Player_Sizeof:            rs.w    0   ; total structure size in bytes (for ds.b alloc)


;==============================================================================
; Actor structure  (Actor_Sizeof bytes)
;
; Holds the state of one game object / enemy instance.  The actor pool lives
; in the Variables block as  Actors: ds.b Actor_Sizeof*MAX_ACTORS.
; a3 is the convention register for a pointer to the current actor struct.
;
; The ActorList array holds longword pointers to active actor structures,
; kept sorted by Y position (DrawStaticActors uses this order).
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

                          RSRESET
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
Actor_CloudTick:          rs.w    1   ; cloud death tick: 0=idle, 1..CLOUD_TOTAL_TICKS=animating
Actor_DirtTick:           rs.w    1   ; dirt break tick:  0=idle, 1..DIRT_TOTAL_TICKS=animating
Actor_Dirty:              rs.w    1   ; 1 = needs redraw via DrawStaticActors; 0 = already drawn
Actor_PixelX:             rs.w    1   ; cached pixel X = Actor_X * 24 (kept in sync with Actor_X)
Actor_PixelY:             rs.w    1   ; cached pixel Y = Actor_Y * 24 (kept in sync with Actor_Y)
Actor_IsPlayer:           rs.w    1   ; 1 = proxy for the frozen player; draw via DrawPlayerFrozen
Actor_HatchTick:          rs.w    1   ; cocoon hatch countdown in frames; 0 = not a
                                      ; ticking cocoon (UpdateCocoons, actors.asm)
Actor_Sizeof:             rs.w    0   ; total structure size in bytes


;==============================================================================
; Clean record  (Clean_Sizeof bytes)
;
; A small descriptor used when scheduling a screen area to be "cleaned"
; (restored from NonDisplayScreen to DisplayScreen) after an actor has moved away.
; Currently used by the blitter clear routines.
;
;   Clean_ScreenOffset - byte offset from the start of the screen buffer
;                        to the top-left pixel of the tile to clear
;   Clean_BlitSize     - BLTSIZE register value for this blit operation
;   Clean_BlitMod      - blitter modulo for this operation
;==============================================================================

;==============================================================================
; Snapshot structure  (Snap_sizeof bytes)
;
; One snapshot captures the minimal game state needed to fully rewind one move:
;   - Both players: tile X/Y, status, facing, and on-ladder flag
;   - The full GameMap (WALL_PAPER_SIZE bytes) - records dirt/push/enemy positions
;   - All actor slots: X, Y, Status, Type, SpriteOffset, Static, HatchTick
;     (7 words each).  Type/SpriteOffset/Static/HatchTick are snapshotted
;     because a hatching cocoon MUTATES them at runtime (BLOCK_COCOON ->
;     BLOCK_ENEMYFALL); rewinding across the hatch boundary must restore the
;     cocoon exactly.  (Actor_CanFall/IsPlayer never change - not saved.)
;
; MAX_ACTORS (= MAP_SIZE = 88) slots are always saved, dead or alive,
; so the slot index within Actors[] is preserved across save/restore.
;
; Snap_sizeof bytes per snapshot; UNDO_BUFFER_SIZE snapshots in SnapshotBuffer.
;==============================================================================

SNAP_ACTOR_WORDS = 7                  ; words saved per actor slot (see above)

                          RSRESET
Snap_PlayerX:             rs.w    1   ; Player tile column
Snap_PlayerY:             rs.w    1   ; Player tile row
Snap_PlayerStatus:        rs.w    1   ; Player Player_Status (0/1)
Snap_PlayerFacing:        rs.w    1   ; Player Player_Facing (+1/-1)
Snap_PlayerOnLadder:      rs.w    1   ; Player Player_OnLadder (0/nonzero)
Snap_Map:                 rs.b    MAX_GAME_MAP_SIZE  ; GameMap copy (1280 bytes)
Snap_Actors:              rs.b    MAX_ACTORS*SNAP_ACTOR_WORDS*2  ; 88 x 14 bytes (1,232 bytes)
Snap_sizeof:              rs.w    0   ; total snapshot size in bytes

; Backward compatibility aliases:
;Snap_MillieX              = Snap_PlayerX
;Snap_MillieY              = Snap_PlayerY
;Snap_MillieStatus         = Snap_PlayerStatus
;Snap_MillieFacing         = Snap_PlayerFacing
;Snap_MillieOnLadder       = Snap_PlayerOnLadder


                          RSRESET
Clean_ScreenOffset:       rs.w    1   ; byte offset into screen buffer
Clean_BlitSize:           rs.w    1   ; BLTSIZE value for the clear blit
Clean_BlitMod:            rs.w    1   ; blitter modulo for the clear blit
Clean_Sizeof:             rs.w    0   ; total structure size in bytes


;==============================================================================
; Level Definition Structure (LevelDef_Sizeof bytes)
;
; Unified level descriptor generated per level by tools/export_level.py.
; Referenced by LevelTable and level transition / setup routines.
;==============================================================================

                          RSRESET
; --- Visuals & Audio ---
LevelDef_TilesetRaw:      rs.l    1   ; Pointer to interleaved 4-bpl tileset raw bitmap
LevelDef_TilesetMsk:      rs.l    1   ; Pointer to 1-bpl tileset blitter mask
LevelDef_Palette:         rs.l    1   ; Pointer to 16-word RGB444 palette
LevelDef_Music:           rs.l    1   ; Pointer to ProTracker 4-channel MOD module

; --- Geometry & Binary Maps ---
LevelDef_Width:           rs.w    1   ; Map width in tiles
LevelDef_Height:          rs.w    1   ; Map height in tiles
LevelDef_BackgroundMap:   rs.l    1   ; Pointer to background layer binary .map (0 if none)
LevelDef_PlatformMap:     rs.l    1   ; Pointer to platform layer binary .map (0 if none)
LevelDef_ForegroundMap:   rs.l    1   ; Pointer to foreground layer binary .map (0 if none)
LevelDef_WaterMap:        rs.l    1   ; Pointer to water layer binary .map (0 if none)
LevelDef_LayerCount:      rs.w    1   ; Number of ordered tile layers
LevelDef_Reserved:        rs.w    1   ; Reserved for alignment / future flags
LevelDef_LayerList:       rs.l    1   ; Pointer to ordered array of layer binary .map pointers
LevelDef_GameMap:         rs.l    1   ; Pointer to 1D GameMap collision binary

; --- Camera Bounds & Margins ---
LevelDef_MinCameraY:      rs.w    1   ; Minimum camera scroll offset (usually 0)
LevelDef_MaxCameraY:      rs.w    1   ; Maximum camera scroll offset (e.g. 464)
LevelDef_InitialCameraY:  rs.w    1   ; Starting camera scroll offset (e.g. 464)
LevelDef_CamMarginTop:    rs.w    1   ; Upper deadzone margin in screen pixels (16)
LevelDef_CamMarginBottom: rs.w    1   ; Lower deadzone margin in screen pixels (176)

; --- Player Starts ---
LevelDef_P1Col:           rs.w    1   ; Player 1 start column
LevelDef_P1Row:           rs.w    1   ; Player 1 start row
LevelDef_P1Facing:        rs.w    1   ; Player 1 facing (+1=Right, -1=Left)
LevelDef_P2Col:           rs.w    1   ; Player 2 start column (0 if solo)
LevelDef_P2Row:           rs.w    1   ; Player 2 start row
LevelDef_P2Facing:        rs.w    1   ; Player 2 facing

; --- Entity & Object Lists ---
LevelDef_EnemyList:       rs.l    1   ; Pointer to enemy spawn list
LevelDef_LadderList:      rs.l    1   ; Pointer to ladder bounding box list
LevelDef_SolidList:       rs.l    1   ; Pointer to solid platform list
LevelDef_TriggerList:     rs.l    1   ; Pointer to trigger/exit zones list
LevelDef_HazardList:      rs.l    1   ; Pointer to hazard zones list
LevelDef_BridgeList:      rs.l    1   ; Pointer to bridge zones list

; --- Banner Text & Access Code ---
LevelDef_TitleStr:        rs.l    1   ; Pointer to null-terminated title string
LevelDef_SubTitleStr:     rs.l    1   ; Pointer to null-terminated subtitle string
LevelDef_HintStr          = LevelDef_SubTitleStr ; Backward-compatibility alias
LevelDef_AccessCode:      rs.b    8   ; 6-char level access password + 2 null/pad bytes
LevelDef_Sizeof:          rs.w    0   ; Total structure size

