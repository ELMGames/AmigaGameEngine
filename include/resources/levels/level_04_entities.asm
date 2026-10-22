;==============================================================================
; Auto-generated Level Metadata for Level_04
; Generated from: Level_04.tmx
;==============================================================================

Level_04_MapWidth:        dc.w    20
Level_04_MapHeight:       dc.w    13
Level_04_MapSize:         dc.w    260
Level_04_TileWidth:       dc.w    16
Level_04_TileHeight:      dc.w    16
Level_04_LayerCount:      dc.w    4

;------------------------------------------------------------------------------
; Tilemap Layer Binaries
;------------------------------------------------------------------------------
Level_04_BackgroundMap:
    incbin     "assets/levels/Level_04/Level_04-background.map"
    even

Level_04_SceneryMap = Level_04_BackgroundMap

Level_04_PlatformMap:
    incbin     "assets/levels/Level_04/Level_04-platform.map"
    even

Level_04_LadderMap:
    incbin     "assets/levels/Level_04/Level_04-ladder.map"
    even

Level_04_ForegroundMap:
    incbin     "assets/levels/Level_04/Level_04-foreground.map"
    even

Level_04_WaterMap = 0

;------------------------------------------------------------------------------
; Ordered Tilemap Layer Table (Blit Reference Source for NonDisplayScreen)
; Format: Pointers to each layer's binary map, terminated by 0
; Order: 1. Scenery/Background, 2. Platforms, 3. Ladders, 4. Foreground
;------------------------------------------------------------------------------
Level_04_LayerList:
    dc.l    Level_04_BackgroundMap
    dc.l    Level_04_PlatformMap
    dc.l    Level_04_LadderMap
    dc.l    Level_04_ForegroundMap
    dc.l    0                           ; Null termination

Level_04_CompositeMap:
    incbin     "assets/levels/Level_04/Level_04.map"
    even

;------------------------------------------------------------------------------
; 1D GameMap Binary (20 cols x 13 rows = 260 bytes)
; Format: 1 byte per tile, containing BLOCK_xxx values
;------------------------------------------------------------------------------
Level_04_GameMap:
    incbin     "assets/levels/Level_04/Level_04-gamemap.bin"
    even

;------------------------------------------------------------------------------
; Player Starting Coordinates
;------------------------------------------------------------------------------
Level_04_PlayerStartX:    dc.w    16
Level_04_PlayerStartY:    dc.w    160
Level_04_PlayerCol:       dc.w    1
Level_04_PlayerRow:       dc.w    10
Level_04_PlayerXDec:      dc.w    8
Level_04_PlayerDir:       dc.w    1       ; -1=Left, +1=Right

;------------------------------------------------------------------------------
; Player 2 Starting Coordinates (0 if solo)
;------------------------------------------------------------------------------
Level_04_Player2StartX:   dc.w    0
Level_04_Player2StartY:   dc.w    0
Level_04_Player2Col:      dc.w    0
Level_04_Player2Row:      dc.w    0
Level_04_Player2XDec:     dc.w    0
Level_04_Player2Dir:      dc.w    0       ; -1=Left, +1=Right (0=Solo)

;------------------------------------------------------------------------------
; Enemy Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), PatrolMinX (w), PatrolMaxX (w), Speed (w)
;------------------------------------------------------------------------------
Level_04_EnemyCount:      dc.w    3
Level_04_EnemyList:
    dc.w    1, 8, 2, 128, 32, 128, 144, 1   ; Enemy 1
    dc.w    3, 3, 5, 48, 80, 48, 80, 1   ; Enemy 2
    dc.w    2, 10, 9, 160, 144, 112, 208, 2   ; Enemy 3
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Animal Friends Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), Res1 (w), Res2 (w), Res3 (w)
;   Type: 1=BUNNY, 2=PUPPY, 3=KITTEN, 4=DUCKLING, 5=CHICK
;------------------------------------------------------------------------------
Level_04_FriendCount:     dc.w    2
Level_04_FriendList:
    dc.w    3, 17, 5, 272, 80, 0, 0, 0   ; Friend 1: DUCKLING
    dc.w    3, 11, 7, 176, 112, 0, 0, 0   ; Friend 2: DUCKLING
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Pushable / Movable Blocks Table
; Format: Col (w), Row (w), SpriteIndex (w), Reserved (w)
;------------------------------------------------------------------------------
Level_04_BlockCount:      dc.w    2
Level_04_BlockList:
    dc.w    5, 2, 18, 0   ; Block 1: CRATE_1
    dc.w    8, 5, 18, 0   ; Block 2: CRATE_2
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Ladder Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_04_LadderCount:     dc.w    3
Level_04_LadderList:
    dc.w    6, 6, 6, 10   ; Ladder 1 (x=96, y=96, w=16, h=80)
    dc.w    7, 7, 3, 5   ; Ladder 2 (x=112, y=48, w=16, h=48)
    dc.w    16, 16, 6, 10   ; Ladder 3 (x=256, y=96, w=16, h=80)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Solid Platform Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_04_SolidCount:      dc.w    10
Level_04_SolidList:
    dc.w    5, 6, 3, 3   ; Solid 1 (x=80, y=48, w=32, h=16)
    dc.w    8, 8, 3, 3   ; Solid 2 (x=128, y=48, w=16, h=16)
    dc.w    3, 5, 6, 6   ; Solid 3 (x=48, y=96, w=48, h=16)
    dc.w    7, 8, 6, 6   ; Solid 4 (x=112, y=96, w=32, h=16)
    dc.w    13, 15, 6, 6   ; Solid 5 (x=208, y=96, w=48, h=16)
    dc.w    17, 17, 6, 6   ; Solid 6 (x=272, y=96, w=16, h=16)
    dc.w    11, 12, 8, 8   ; Solid 7 (x=176, y=128, w=32, h=16)
    dc.w    0, 8, 11, 11   ; Solid 8 (x=0, y=176, w=144, h=16)
    dc.w    11, 19, 11, 11   ; Solid 9 (x=176, y=176, w=144, h=16)
    dc.w    0, 19, 12, 12   ; Solid 10 (x=0, y=192, w=320, h=16)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Triggers & Level Event Zones
; Format: TriggerID (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_04_TriggerCount:    dc.w    0
Level_04_TriggerList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Hazard Zones
; Format: Damage (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_04_HazardCount:     dc.w    0
Level_04_HazardList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Bridge Zones
; Format: LeftX (w), RightX (w), PlatformRow (w), Reserved (w)
;------------------------------------------------------------------------------
Level_04_BridgeCount:     dc.w    0
Level_04_BridgeList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Oxygen Refills Table
; Format: Col (w), Row (w), PixelX (w), PixelY (w), TileId (w), Reserved (3 words)
;------------------------------------------------------------------------------
Level_04_OxygenCount:     dc.w    0
Level_04_OxygenList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Tile Physical Attributes Table (256 bytes)
; Maps tile indices to collision flags: 0=Empty, 1=Solid, 2=Ladder, 3=Hazard, 4=Passthrough
;------------------------------------------------------------------------------
Level_04_TileAttributesTable:
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
Level_04_Palette:
    dc.w    $0000, $01be, $0332, $0fff, $0274, $0193, $0f91, $025c
    dc.w    $0fc2, $0da6, $0b74, $0813, $0d12, $089b, $0177, $0ca8
    even

;------------------------------------------------------------------------------
; Level Text Strings
;------------------------------------------------------------------------------
Level_04_TitleStr:
    dc.b    "SUNSTONE ZIGGURAT",0
    even

Level_04_SubTitleStr:
    dc.b    "TEMPLE OF THE STEPPED TERRACE",0
    even
Level_04_HintStr = Level_04_SubTitleStr

;==============================================================================
; Level Descriptor Definition
; Conforms to LevelDef record structure in include/resources/struct.asm
;==============================================================================
Level_04_Def:
    ; --- Visuals & Audio ---
    dc.l    GameTilesRaw                ; Tileset graphics pointer
    dc.l    GameTilesMsk                ; Tileset mask pointer
    dc.l    Level_04_Palette            ; Palette pointer (16 RGB words)
    dc.l    LevelMod                    ; BGM ProTracker MOD pointer

    ; --- Geometry & Binary Maps ---
    dc.w    20, 13                      ; Map width, height in tiles
    dc.l    Level_04_BackgroundMap      ; Background layer binary pointer (0 if none)
    dc.l    Level_04_PlatformMap        ; Platform layer binary pointer (0 if none)
    dc.l    Level_04_LadderMap          ; Ladder layer binary pointer (0 if none)
    dc.l    Level_04_ForegroundMap      ; Foreground layer binary pointer (0 if none)
    dc.l    0                           ; Water layer binary pointer (0 if none)
    dc.w    4, 0                        ; Number of ordered tile layers, reserved
    dc.l    Level_04_LayerList          ; Ordered layer list pointer (TMX order)
    dc.l    Level_04_GameMap            ; 1D collision GameMap binary pointer

    ; --- Camera Bounds & Margins ---
    dc.w    0, 0                        ; MinCameraY, MaxCameraY
    dc.w    0                           ; InitialCameraY
    dc.w    16, 176                     ; CamMarginTop, CamMarginBottom

    ; --- Player Starts ---
    dc.w    1, 10, 1                    ; Player 1: Col, Row, Facing (+1=Right, -1=Left)
    dc.w    0, 0, 0                     ; Player 2: Col, Row, Facing (0=None/Solo)

    ; --- Entity & Object Lists ---
    dc.l    Level_04_EnemyList          ; Enemy spawn table
    dc.l    Level_04_FriendList         ; Animal friends spawn table
    dc.l    Level_04_BlockList          ; Pushable blocks table
    dc.l    Level_04_LadderList         ; Ladder zones table
    dc.l    Level_04_SolidList          ; Solid platform zones table
    dc.l    Level_04_TriggerList        ; Triggers / switches table
    dc.l    Level_04_HazardList         ; Hazard zones table
    dc.l    Level_04_BridgeList         ; Bridge zones table
    dc.l    Level_04_OxygenList         ; Oxygen refills table

    ; --- Banner Text & Access Code ---
    dc.l    Level_04_TitleStr           ; Null-terminated title string
    dc.l    Level_04_SubTitleStr        ; Null-terminated subtitle string
    dc.b    "ACORN4",0,0                ; 6-char access password + padding
    even

