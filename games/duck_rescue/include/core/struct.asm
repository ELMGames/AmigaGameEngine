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
;                         (0 = Mia)
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

                          rsreset
Player_Status:            rs.w    1   ; 0=inactive, 1=active
Player_X:                 rs.w    1   ; tile column (0..WALL_PAPER_WIDTH-1)
Player_Y:                 rs.w    1   ; tile row    (0..WALL_PAPER_HEIGHT-1)
Player_XDec:              rs.w    1   ; sub-tile horizontal pixel offset (+/-)
Player_YDec:              rs.w    1   ; sub-tile vertical   pixel offset (+/-)
Player_ActionCount:       rs.w    1   ; frames remaining in current move (16 per tile)
Player_PrevX:             rs.w    1   ; screen pixel X at start of last move (for BOB erase)
Player_PrevY:             rs.w    1   ; screen pixel Y at start of last move (for BOB erase)
Player_PrevDrawn:         rs.w    1   ; non-zero if player was blitted last frame
Player_NextX:             rs.w    1   ; destination tile column for current action
Player_NextY:             rs.w    1   ; destination tile row    for current action
Player_BobOffset:         rs.w    1   ; base BOB frame index (0=Mia)
Player_FrozenBobBase:     rs.w    1   ; base BOB frame index for frozen pose
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
Player_PixelX:            rs.w    1   ; cached pixel X = Player_X * 16 (updated on every tile commit)
Player_PixelY:            rs.w    1   ; cached pixel Y = Player_Y * 16 (updated on every tile commit)
Player_WorldX:            rs.w    1   ; cached world pixel X = Player_X * 16 + Player_XDec
Player_WorldY:            rs.w    1   ; cached world pixel Y = Player_Y * 16 + Player_YDec - 8
Player_Sizeof:            rs.w    0   ; total structure size in bytes (for ds.b alloc)


;==============================================================================
; Actor structure  (Actor_Sizeof bytes)
;
; In this engine, an "actor" is a pushable crate / interactive block (BLOCK_PUSH)
; that occupies a tile cell, can be slid by the player, and falls under gravity.
; Generic actor structure definition is maintained in engine/include/actor_struct.i.
;==============================================================================

    include "actor_struct.i"



;==============================================================================
; Snapshot structure  (Snap_Sizeof bytes)
;
; One snapshot captures the minimal game state needed to fully rewind one move:
;   - Player (Mia): tile X/Y, status, facing, and on-ladder flag
;   - The full GameMap (MAX_GAME_MAP_SIZE bytes) - records push crate/obstacle positions
;   - All crate actor slots: X, Y, Status, Type, SpriteOffset, Static
;     (6 words each).  (Actor_CanFall/IsPlayer never change - not saved.)
;
; MAX_ACTIVE_CRATES (= 16) slots are always saved, dead or alive,
; so the slot index within Actors[] is preserved across save/restore.
;
; Snap_Sizeof bytes per snapshot; UNDO_BUFFER_SIZE snapshots in SnapshotBuffer.
;==============================================================================


    include    "engine_snapshot.i"
Snap_PlayerX:             rs.w    1   ; Player tile column
Snap_PlayerY:             rs.w    1   ; Player tile row
Snap_PlayerStatus:        rs.w    1   ; Player Player_Status (0/1)
Snap_PlayerFacing:        rs.w    1   ; Player Player_Facing (+1/-1)
Snap_PlayerOnLadder:      rs.w    1   ; Player Player_OnLadder (0/nonzero)
Snap_PlayerOxygen:        rs.w    1   ; oxygen breath counter (0..OXYGEN_MAX)
Snap_OxygenKitInventory:  rs.w    1   ; 1 = oxygen kit bottle in inventory
Snap_OxygenKitActive:     rs.w    1   ; 1 = enhanced dark-blue oxygen active
Snap_PlayerSafeX:         rs.w    1   ; tile X of last dry ground
Snap_PlayerSafeY:         rs.w    1   ; tile Y of last dry ground
Snap_PlayerSafePixelX:    rs.w    1   ; pixel X of last dry ground
Snap_PlayerSafePixelY:    rs.w    1   ; pixel Y of last dry ground
Snap_ActiveEnemyCount:    rs.w    1   ; active dynamic enemies count (0..MAX_ACTIVE_ENEMIES)
Snap_ActiveEnemies:       rs.b    Enemy_Sizeof*MAX_ACTIVE_ENEMIES ; 16 * 24 = 384 bytes
Snap_ActiveFriendCount:   rs.w    1   ; active animal friends count (0..MAX_ACTIVE_FRIENDS)
Snap_FriendsCollectedCount: rs.w    1   ; number of rescued friends
Snap_ActiveFriends:       rs.b    Friend_Sizeof*MAX_ACTIVE_FRIENDS ; 8 * 20 = 160 bytes
Snap_ActivePickupCount:   rs.w    1   ; active oxygen refills count (0..MAX_ACTIVE_PICKUPS)
Snap_ActivePickups:        rs.b    Pickup_Sizeof*MAX_ACTIVE_PICKUPS  ; 8 * 16 = 128 bytes
Snap_Sizeof:              rs.w    0   ; total snapshot size in bytes


;==============================================================================
; Level Definition Structure (LevelDef_Sizeof bytes)
;
; Unified level descriptor generated per level by tools/export_level.py.
; Referenced by LevelTable and level transition / setup routines.
;==============================================================================

                          rsreset
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
LevelDef_LadderMap:       rs.l    1   ; Pointer to ladder layer binary .map (0 if none)
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
LevelDef_P2Col:           rs.w    1   ; Player 2 start column (reserved for co-op; 0 for solo Mia)
LevelDef_P2Row:           rs.w    1   ; Player 2 start row
LevelDef_P2Facing:        rs.w    1   ; Player 2 facing

; --- Entity & Object Lists ---
LevelDef_EnemyList:       rs.l    1   ; Pointer to enemy spawn list
LevelDef_FriendList:      rs.l    1   ; Pointer to animal friends spawn list
LevelDef_BlockList:       rs.l    1   ; Pointer to pushable blocks list
LevelDef_LadderList:      rs.l    1   ; Pointer to ladder bounding box list
LevelDef_SolidList:       rs.l    1   ; Pointer to solid platform list
LevelDef_TriggerList:     rs.l    1   ; Pointer to trigger/exit zones list
LevelDef_HazardList:      rs.l    1   ; Pointer to hazard zones list
LevelDef_BridgeList:      rs.l    1   ; Pointer to bridge zones list
LevelDef_PickupList:      rs.l    1   ; Pointer to oxygen refills list

; --- Banner Text & Access Code ---
LevelDef_TitleStr:        rs.l    1   ; Pointer to null-terminated title string
LevelDef_SubTitleStr:     rs.l    1   ; Pointer to null-terminated subtitle string
LevelDef_AccessCode:      rs.b    8   ; 6-char level access password + 2 null/pad bytes
LevelDef_Sizeof:          rs.w    0   ; Total structure size
