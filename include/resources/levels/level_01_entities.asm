;==============================================================================
; Auto-generated Level Metadata for Level_01
; Generated from: Level_01.tmx
;==============================================================================

Level_01_MapWidth:        dc.w    20
Level_01_MapHeight:       dc.w    13
Level_01_MapSize:         dc.w    260
Level_01_TileWidth:       dc.w    16
Level_01_TileHeight:      dc.w    16
Level_01_LayerCount:      dc.w    4

;------------------------------------------------------------------------------
; Tilemap Layer Binaries
;------------------------------------------------------------------------------
Level_01_BackgroundMap:
    incbin     "assets/levels/Level_01/Level_01-background.map"
    even

Level_01_SceneryMap = Level_01_BackgroundMap

Level_01_PlatformMap:
    incbin     "assets/levels/Level_01/Level_01-platform.map"
    even

Level_01_LadderMap:
    incbin     "assets/levels/Level_01/Level_01-ladder.map"
    even

Level_01_ForegroundMap:
    incbin     "assets/levels/Level_01/Level_01-foreground.map"
    even

Level_01_WaterMap = 0

;------------------------------------------------------------------------------
; Ordered Tilemap Layer Table (Blit Reference Source for NonDisplayScreen)
; Format: Pointers to each layer's binary map, terminated by 0
; Order: 1. Scenery/Background, 2. Platforms, 3. Ladders, 4. Foreground
;------------------------------------------------------------------------------
Level_01_LayerList:
    dc.l    Level_01_BackgroundMap
    dc.l    Level_01_PlatformMap
    dc.l    Level_01_LadderMap
    dc.l    Level_01_ForegroundMap
    dc.l    0                           ; Null termination

Level_01_CompositeMap:
    incbin     "assets/levels/Level_01/Level_01.map"
    even

;------------------------------------------------------------------------------
; 1D GameMap Binary (20 cols x 13 rows = 260 bytes)
; Format: 1 byte per tile, containing BLOCK_xxx values
;------------------------------------------------------------------------------
Level_01_GameMap:
    incbin     "assets/levels/Level_01/Level_01-gamemap.bin"
    even

;------------------------------------------------------------------------------
; Player Starting Coordinates
;------------------------------------------------------------------------------
Level_01_PlayerStartX:    dc.w    32
Level_01_PlayerStartY:    dc.w    160
Level_01_PlayerCol:       dc.w    2
Level_01_PlayerRow:       dc.w    10
Level_01_PlayerXDec:      dc.w    8
Level_01_PlayerDir:       dc.w    1       ; -1=Left, +1=Right

;------------------------------------------------------------------------------
; Player 2 Starting Coordinates (0 if solo)
;------------------------------------------------------------------------------
Level_01_Player2StartX:   dc.w    0
Level_01_Player2StartY:   dc.w    0
Level_01_Player2Col:      dc.w    0
Level_01_Player2Row:      dc.w    0
Level_01_Player2XDec:     dc.w    0
Level_01_Player2Dir:      dc.w    0       ; -1=Left, +1=Right (0=Solo)

;------------------------------------------------------------------------------
; Enemy Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), PatrolMinX (w), PatrolMaxX (w), Speed (w)
;------------------------------------------------------------------------------
Level_01_EnemyCount:      dc.w    1
Level_01_EnemyList:
    dc.w    2, 2, 4, 32, 64, 0, 80, 2   ; Enemy 1
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Animal Friends Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), Res1 (w), Res2 (w), Res3 (w)
;   Type: 1=BUNNY, 2=PUPPY, 3=KITTEN, 4=DUCKLING, 5=CHICK
;------------------------------------------------------------------------------
Level_01_FriendCount:     dc.w    1
Level_01_FriendList:
    dc.w    3, 17, 10, 272, 160, 0, 0, 0   ; Friend 1: DUCKLING
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Pushable / Movable Blocks Table
; Format: Col (w), Row (w), SpriteIndex (w), Reserved (w)
;------------------------------------------------------------------------------
Level_01_BlockCount:      dc.w    0
Level_01_BlockList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Ladder Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_01_LadderCount:     dc.w    0
Level_01_LadderList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Solid Platform Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_01_SolidCount:      dc.w    2
Level_01_SolidList:
    dc.w    0, 19, 11, 11   ; Solid 1 (x=0, y=176, w=320, h=16)
    dc.w    0, 19, 12, 12   ; Solid 2 (x=0, y=192, w=320, h=16)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Triggers & Level Event Zones
; Format: TriggerID (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_01_TriggerCount:    dc.w    0
Level_01_TriggerList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Hazard Zones
; Format: Damage (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_01_HazardCount:     dc.w    0
Level_01_HazardList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Bridge Zones
; Format: LeftX (w), RightX (w), PlatformRow (w), Reserved (w)
;------------------------------------------------------------------------------
Level_01_BridgeCount:     dc.w    0
Level_01_BridgeList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Oxygen Refills Table
; Format: Col (w), Row (w), PixelX (w), PixelY (w), TileId (w), Reserved (3 words)
;------------------------------------------------------------------------------
Level_01_OxygenCount:     dc.w    0
Level_01_OxygenList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Tile Physical Attributes Table (256 bytes)
; Maps tile indices to collision flags: 0=Empty, 1=Solid, 2=Ladder, 3=Hazard, 4=Passthrough
;------------------------------------------------------------------------------
Level_01_TileAttributesTable:
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
Level_01_Palette:
    dc.w    $0000, $01be, $0332, $0fff, $0274, $0193, $0f91, $025c
    dc.w    $0fc2, $0da6, $0b74, $0813, $0d12, $089b, $0177, $0ca8
    even

;------------------------------------------------------------------------------
; Level Text Strings
;------------------------------------------------------------------------------
Level_01_TitleStr:
    dc.b    "ORCHARD GROVE",0
    even

Level_01_SubTitleStr:
    dc.b    "FIRST STEPS IN DUCK RESCUE",0
    even
Level_01_HintStr = Level_01_SubTitleStr

;==============================================================================
; Level Descriptor Definition
; Conforms to LevelDef record structure in include/resources/struct.asm
;==============================================================================
Level_01_Def:
    ; --- Visuals & Audio ---
    dc.l    GameTilesRaw                ; Tileset graphics pointer
    dc.l    GameTilesMsk                ; Tileset mask pointer
    dc.l    Level_01_Palette            ; Palette pointer (16 RGB words)
    dc.l    LevelMod                    ; BGM ProTracker MOD pointer

    ; --- Geometry & Binary Maps ---
    dc.w    20, 13                      ; Map width, height in tiles
    dc.l    Level_01_BackgroundMap      ; Background layer binary pointer (0 if none)
    dc.l    Level_01_PlatformMap        ; Platform layer binary pointer (0 if none)
    dc.l    Level_01_LadderMap          ; Ladder layer binary pointer (0 if none)
    dc.l    Level_01_ForegroundMap      ; Foreground layer binary pointer (0 if none)
    dc.l    0                           ; Water layer binary pointer (0 if none)
    dc.w    4, 0                        ; Number of ordered tile layers, reserved
    dc.l    Level_01_LayerList          ; Ordered layer list pointer (TMX order)
    dc.l    Level_01_GameMap            ; 1D collision GameMap binary pointer

    ; --- Camera Bounds & Margins ---
    dc.w    0, 0                        ; MinCameraY, MaxCameraY
    dc.w    0                           ; InitialCameraY
    dc.w    16, 176                     ; CamMarginTop, CamMarginBottom

    ; --- Player Starts ---
    dc.w    2, 10, 1                    ; Player 1: Col, Row, Facing (+1=Right, -1=Left)
    dc.w    0, 0, 0                     ; Player 2: Col, Row, Facing (0=None/Solo)

    ; --- Entity & Object Lists ---
    dc.l    Level_01_EnemyList          ; Enemy spawn table
    dc.l    Level_01_FriendList         ; Animal friends spawn table
    dc.l    Level_01_BlockList          ; Pushable blocks table
    dc.l    Level_01_LadderList         ; Ladder zones table
    dc.l    Level_01_SolidList          ; Solid platform zones table
    dc.l    Level_01_TriggerList        ; Triggers / switches table
    dc.l    Level_01_HazardList         ; Hazard zones table
    dc.l    Level_01_BridgeList         ; Bridge zones table
    dc.l    Level_01_OxygenList         ; Oxygen refills table

    ; --- Banner Text & Access Code ---
    dc.l    Level_01_TitleStr           ; Null-terminated title string
    dc.l    Level_01_SubTitleStr        ; Null-terminated subtitle string
    dc.b    "ACORN1",0,0                ; 6-char access password + padding
    even

