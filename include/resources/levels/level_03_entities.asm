;==============================================================================
; Auto-generated Level Metadata for Level_03
; Generated from: Level_03.tmx
;==============================================================================

Level_03_MapWidth:        dc.w    20
Level_03_MapHeight:       dc.w    13
Level_03_MapSize:         dc.w    260
Level_03_TileWidth:       dc.w    16
Level_03_TileHeight:      dc.w    16
Level_03_LayerCount:      dc.w    4

;------------------------------------------------------------------------------
; Tilemap Layer Binaries
;------------------------------------------------------------------------------
Level_03_BackgroundMap:
    incbin     "assets/levels/Level_03/Level_03-background.map"
    even

Level_03_SceneryMap = Level_03_BackgroundMap

Level_03_PlatformMap:
    incbin     "assets/levels/Level_03/Level_03-platform.map"
    even

Level_03_LadderMap:
    incbin     "assets/levels/Level_03/Level_03-ladder.map"
    even

Level_03_ForegroundMap:
    incbin     "assets/levels/Level_03/Level_03-foreground.map"
    even

Level_03_WaterMap = 0

;------------------------------------------------------------------------------
; Ordered Tilemap Layer Table (Blit Reference Source for NonDisplayScreen)
; Format: Pointers to each layer's binary map, terminated by 0
; Order: 1. Scenery/Background, 2. Platforms, 3. Ladders, 4. Foreground
;------------------------------------------------------------------------------
Level_03_LayerList:
    dc.l    Level_03_BackgroundMap
    dc.l    Level_03_PlatformMap
    dc.l    Level_03_LadderMap
    dc.l    Level_03_ForegroundMap
    dc.l    0                           ; Null termination

Level_03_CompositeMap:
    incbin     "assets/levels/Level_03/Level_03.map"
    even

;------------------------------------------------------------------------------
; 1D GameMap Binary (20 cols x 13 rows = 260 bytes)
; Format: 1 byte per tile, containing BLOCK_xxx values
;------------------------------------------------------------------------------
Level_03_GameMap:
    incbin     "assets/levels/Level_03/Level_03-gamemap.bin"
    even

;------------------------------------------------------------------------------
; Player Starting Coordinates
;------------------------------------------------------------------------------
Level_03_PlayerStartX:    dc.w    16
Level_03_PlayerStartY:    dc.w    160
Level_03_PlayerCol:       dc.w    1
Level_03_PlayerRow:       dc.w    10
Level_03_PlayerXDec:      dc.w    8
Level_03_PlayerDir:       dc.w    1       ; -1=Left, +1=Right

;------------------------------------------------------------------------------
; Player 2 Starting Coordinates (0 if solo)
;------------------------------------------------------------------------------
Level_03_Player2StartX:   dc.w    0
Level_03_Player2StartY:   dc.w    0
Level_03_Player2Col:      dc.w    0
Level_03_Player2Row:      dc.w    0
Level_03_Player2XDec:     dc.w    0
Level_03_Player2Dir:      dc.w    0       ; -1=Left, +1=Right (0=Solo)

;------------------------------------------------------------------------------
; Enemy Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), PatrolMinX (w), PatrolMaxX (w), Speed (w)
;------------------------------------------------------------------------------
Level_03_EnemyCount:      dc.w    0
Level_03_EnemyList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Animal Friends Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), Res1 (w), Res2 (w), Res3 (w)
;   Type: 1=BUNNY, 2=PUPPY, 3=KITTEN, 4=DUCKLING, 5=CHICK
;------------------------------------------------------------------------------
Level_03_FriendCount:     dc.w    2
Level_03_FriendList:
    dc.w    3, 1, 6, 16, 96, 0, 0, 0   ; Friend 1: DUCKLING
    dc.w    3, 19, 10, 304, 160, 0, 0, 0   ; Friend 2: DUCKLING
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Pushable / Movable Blocks Table
; Format: Col (w), Row (w), SpriteIndex (w), Reserved (w)
;------------------------------------------------------------------------------
Level_03_BlockCount:      dc.w    2
Level_03_BlockList:
    dc.w    5, 6, 18, 0   ; Block 1: CRATE_1
    dc.w    13, 6, 18, 0   ; Block 2: CRATE_2
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Ladder Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_03_LadderCount:     dc.w    2
Level_03_LadderList:
    dc.w    3, 3, 7, 10   ; Ladder 1 (x=48, y=112, w=16, h=64)
    dc.w    11, 11, 7, 10   ; Ladder 2 (x=176, y=112, w=16, h=64)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Solid Platform Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_03_SolidCount:      dc.w    8
Level_03_SolidList:
    dc.w    1, 2, 7, 7   ; Solid 1 (x=16, y=112, w=32, h=16)
    dc.w    4, 6, 7, 7   ; Solid 2 (x=64, y=112, w=48, h=16)
    dc.w    9, 10, 7, 7   ; Solid 3 (x=144, y=112, w=32, h=16)
    dc.w    12, 14, 7, 7   ; Solid 4 (x=192, y=112, w=48, h=16)
    dc.w    0, 6, 11, 11   ; Solid 5 (x=0, y=176, w=112, h=16)
    dc.w    8, 14, 11, 11   ; Solid 6 (x=128, y=176, w=112, h=16)
    dc.w    16, 19, 11, 11   ; Solid 7 (x=256, y=176, w=64, h=16)
    dc.w    0, 19, 12, 12   ; Solid 8 (x=0, y=192, w=320, h=16)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Triggers & Level Event Zones
; Format: TriggerID (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_03_TriggerCount:    dc.w    0
Level_03_TriggerList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Hazard Zones
; Format: Damage (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_03_HazardCount:     dc.w    0
Level_03_HazardList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Bridge Zones
; Format: LeftX (w), RightX (w), PlatformRow (w), Reserved (w)
;------------------------------------------------------------------------------
Level_03_BridgeCount:     dc.w    0
Level_03_BridgeList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Oxygen Refills Table
; Format: Col (w), Row (w), PixelX (w), PixelY (w), TileId (w), Reserved (3 words)
;------------------------------------------------------------------------------
Level_03_OxygenCount:     dc.w    0
Level_03_OxygenList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Tile Physical Attributes Table (256 bytes)
; Maps tile indices to collision flags: 0=Empty, 1=Solid, 2=Ladder, 3=Hazard, 4=Passthrough
;------------------------------------------------------------------------------
Level_03_TileAttributesTable:
    ; Index 00: Empty space
    dc.b    ATTR_EMPTY
    dc.b    ATTR_LADDER, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID
    dc.b    ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    even

;------------------------------------------------------------------------------
; 16-Color OCS Level Palette
; Format: 16 words (RGB444: 0x0RGB)
;------------------------------------------------------------------------------
Level_03_Palette:
    dc.w    $0000, $01be, $0332, $0fff, $0274, $0193, $0f91, $025c
    dc.w    $0fc2, $0da6, $0b74, $0813, $0d12, $089b, $0177, $0ca8
    even

;------------------------------------------------------------------------------
; Level Text Strings
;------------------------------------------------------------------------------
Level_03_TitleStr:
    dc.b    "MARIO SEWER VAULT",0
    even

Level_03_SubTitleStr:
    dc.b    "TWIN BASIN CRATE PUZZLE",0
    even
Level_03_HintStr = Level_03_SubTitleStr

;==============================================================================
; Level Descriptor Definition
; Conforms to LevelDef record structure in include/resources/struct.asm
;==============================================================================
Level_03_Def:
    ; --- Visuals & Audio ---
    dc.l    GameTilesRaw                ; Tileset graphics pointer
    dc.l    GameTilesMsk                ; Tileset mask pointer
    dc.l    Level_03_Palette            ; Palette pointer (16 RGB words)
    dc.l    LevelMod                    ; BGM ProTracker MOD pointer

    ; --- Geometry & Binary Maps ---
    dc.w    20, 13                      ; Map width, height in tiles
    dc.l    Level_03_BackgroundMap      ; Background layer binary pointer (0 if none)
    dc.l    Level_03_PlatformMap        ; Platform layer binary pointer (0 if none)
    dc.l    Level_03_LadderMap          ; Ladder layer binary pointer (0 if none)
    dc.l    Level_03_ForegroundMap      ; Foreground layer binary pointer (0 if none)
    dc.l    0                           ; Water layer binary pointer (0 if none)
    dc.w    4, 0                        ; Number of ordered tile layers, reserved
    dc.l    Level_03_LayerList          ; Ordered layer list pointer (TMX order)
    dc.l    Level_03_GameMap            ; 1D collision GameMap binary pointer

    ; --- Camera Bounds & Margins ---
    dc.w    0, 0                        ; MinCameraY, MaxCameraY
    dc.w    0                           ; InitialCameraY
    dc.w    16, 176                     ; CamMarginTop, CamMarginBottom

    ; --- Player Starts ---
    dc.w    1, 10, 1                    ; Player 1: Col, Row, Facing (+1=Right, -1=Left)
    dc.w    0, 0, 0                     ; Player 2: Col, Row, Facing (0=None/Solo)

    ; --- Entity & Object Lists ---
    dc.l    Level_03_EnemyList          ; Enemy spawn table
    dc.l    Level_03_FriendList         ; Animal friends spawn table
    dc.l    Level_03_BlockList          ; Pushable blocks table
    dc.l    Level_03_LadderList         ; Ladder zones table
    dc.l    Level_03_SolidList          ; Solid platform zones table
    dc.l    Level_03_TriggerList        ; Triggers / switches table
    dc.l    Level_03_HazardList         ; Hazard zones table
    dc.l    Level_03_BridgeList         ; Bridge zones table
    dc.l    Level_03_OxygenList         ; Oxygen refills table

    ; --- Banner Text & Access Code ---
    dc.l    Level_03_TitleStr           ; Null-terminated title string
    dc.l    Level_03_SubTitleStr        ; Null-terminated subtitle string
    dc.b    "ACORN3",0,0                ; 6-char access password + padding
    even

