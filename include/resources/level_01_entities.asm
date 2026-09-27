;==============================================================================
; Auto-generated Level Metadata for Level_01
; Generated from: Level_01.tmx
;==============================================================================

Level_01_MapWidth:        dc.w    20
Level_01_MapHeight:       dc.w    42
Level_01_MapSize:         dc.w    840
Level_01_TileWidth:       dc.w    16
Level_01_TileHeight:      dc.w    16
Level_01_LayerCount:      dc.w    4

;------------------------------------------------------------------------------
; Tilemap Layer Binaries
;------------------------------------------------------------------------------
Level_01_BackgroundMap:
    incbin     "assets/Levels/Level_01-background.map"
    even

Level_01_SceneryMap = Level_01_BackgroundMap

Level_01_PlatformMap:
    incbin     "assets/Levels/Level_01-platform.map"
    even

Level_01_LadderMap:
    incbin     "assets/Levels/Level_01-ladder.map"
    even

Level_01_ForegroundMap:
    incbin     "assets/Levels/Level_01-foreground.map"
    even

Level_01_WaterMap:
    incbin     "assets/Levels/Level_01-water.map"
    even

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
    incbin     "assets/Levels/Level_01.map"
    even

;------------------------------------------------------------------------------
; 1D GameMap Binary (20 cols x 42 rows = 840 bytes)
; Format: 1 byte per tile, containing BLOCK_xxx values
;------------------------------------------------------------------------------
Level_01_GameMap:
    incbin     "assets/Levels/Level_01-gamemap.bin"
    even

;------------------------------------------------------------------------------
; Player Starting Coordinates
;------------------------------------------------------------------------------
Level_01_PlayerStartX:    dc.w    32
Level_01_PlayerStartY:    dc.w    624
Level_01_PlayerCol:       dc.w    2
Level_01_PlayerRow:       dc.w    39
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
Level_01_EnemyCount:      dc.w    6
Level_01_EnemyList:
    dc.w    5, 7, 10, 112, 160, 32, 160, 1   ; Enemy 1
    dc.w    2, 13, 15, 208, 240, 144, 208, 1   ; Enemy 2
    dc.w    1, 14, 18, 224, 288, 208, 272, 1   ; Enemy 3
    dc.w    2, 8, 30, 128, 480, 64, 144, 1   ; Enemy 4
    dc.w    5, 2, 34, 32, 544, 32, 64, 1   ; Enemy 5
    dc.w    1, 14, 39, 224, 624, 208, 288, 1   ; Enemy 6
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Animal Friends Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), Res1 (w), Res2 (w), Res3 (w)
;   Type: 1=BUNNY, 2=PUPPY, 3=KITTEN, 4=DUCKLING, 5=CHICK
;------------------------------------------------------------------------------
Level_01_FriendCount:     dc.w    12
Level_01_FriendList:
    dc.w    3, 15, 2, 240, 32, 0, 0, 0   ; Friend 1: DUCKLING
    dc.w    3, 2, 10, 32, 160, 0, 0, 0   ; Friend 2: DUCKLING
    dc.w    3, 18, 10, 288, 160, 0, 0, 0   ; Friend 3: DUCKLING
    dc.w    3, 2, 18, 32, 288, 0, 0, 0   ; Friend 4: DUCKLING
    dc.w    3, 9, 22, 144, 352, 0, 0, 0   ; Friend 5: DUCKLING
    dc.w    3, 1, 26, 16, 416, 0, 0, 0   ; Friend 6: DUCKLING
    dc.w    3, 19, 26, 304, 416, 0, 0, 0   ; Friend 7: DUCKLING
    dc.w    3, 16, 27, 256, 432, 0, 0, 0   ; Friend 8: DUCKLING
    dc.w    3, 5, 34, 80, 544, 0, 0, 0   ; Friend 9: DUCKLING
    dc.w    3, 15, 34, 240, 544, 0, 0, 0   ; Friend 10: DUCKLING
    dc.w    3, 0, 39, 0, 624, 0, 0, 0   ; Friend 11: DUCKLING
    dc.w    3, 18, 39, 288, 624, 0, 0, 0   ; Friend 12: DUCKLING
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Pushable / Movable Blocks Table
; Format: Col (w), Row (w), SpriteIndex (w), Reserved (w)
;------------------------------------------------------------------------------
Level_01_BlockCount:      dc.w    3
Level_01_BlockList:
    dc.w    13, 10, 37, 0   ; Block 1: CRATE_1
    dc.w    5, 26, 37, 0   ; Block 2: CRATE_2
    dc.w    5, 30, 37, 0   ; Block 3: CRATE_3
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Ladder Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_01_LadderCount:     dc.w    8
Level_01_LadderList:
    dc.w    3, 3, 27, 34   ; Ladder 1 (x=48, y=432, w=16, h=128)
    dc.w    5, 5, 3, 10   ; Ladder 2 (x=80, y=48, w=16, h=128)
    dc.w    5, 5, 35, 39   ; Ladder 3 (x=80, y=560, w=16, h=80)
    dc.w    6, 6, 23, 26   ; Ladder 4 (x=96, y=368, w=16, h=64)
    dc.w    8, 8, 16, 18   ; Ladder 5 (x=128, y=256, w=16, h=48)
    dc.w    10, 10, 19, 22   ; Ladder 6 (x=160, y=304, w=16, h=64)
    dc.w    13, 13, 39, 39   ; Ladder 7 (x=208, y=624, w=16, h=16)
    dc.w    17, 17, 11, 18   ; Ladder 8 (x=272, y=176, w=16, h=128)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Solid Platform Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_01_SolidCount:      dc.w    41
Level_01_SolidList:
    dc.w    3, 4, 3, 3   ; Solid 1 (x=48, y=48, w=32, h=16)
    dc.w    6, 16, 3, 3   ; Solid 2 (x=96, y=48, w=176, h=16)
    dc.w    14, 14, 8, 8   ; Solid 3 (x=224, y=128, w=16, h=16)
    dc.w    2, 10, 11, 11   ; Solid 4 (x=32, y=176, w=144, h=16)
    dc.w    12, 16, 11, 11   ; Solid 5 (x=192, y=176, w=80, h=16)
    dc.w    18, 18, 11, 11   ; Solid 6 (x=288, y=176, w=16, h=16)
    dc.w    2, 16, 12, 12   ; Solid 7 (x=32, y=192, w=240, h=16)
    dc.w    18, 18, 12, 12   ; Solid 8 (x=288, y=192, w=16, h=16)
    dc.w    5, 7, 16, 16   ; Solid 9 (x=80, y=256, w=48, h=16)
    dc.w    9, 13, 16, 16   ; Solid 10 (x=144, y=256, w=80, h=16)
    dc.w    1, 5, 19, 19   ; Solid 11 (x=16, y=304, w=80, h=16)
    dc.w    7, 9, 19, 19   ; Solid 12 (x=112, y=304, w=48, h=16)
    dc.w    11, 11, 19, 19   ; Solid 13 (x=176, y=304, w=16, h=16)
    dc.w    13, 17, 19, 19   ; Solid 14 (x=208, y=304, w=80, h=16)
    dc.w    5, 5, 23, 23   ; Solid 15 (x=80, y=368, w=16, h=16)
    dc.w    7, 10, 23, 23   ; Solid 16 (x=112, y=368, w=64, h=16)
    dc.w    1, 2, 27, 27   ; Solid 17 (x=16, y=432, w=32, h=16)
    dc.w    4, 7, 27, 27   ; Solid 18 (x=64, y=432, w=64, h=16)
    dc.w    12, 15, 27, 27   ; Solid 19 (x=192, y=432, w=64, h=16)
    dc.w    18, 19, 27, 27   ; Solid 20 (x=288, y=432, w=32, h=16)
    dc.w    1, 2, 28, 28   ; Solid 21 (x=16, y=448, w=32, h=16)
    dc.w    4, 7, 28, 28   ; Solid 22 (x=64, y=448, w=64, h=16)
    dc.w    12, 16, 28, 28   ; Solid 23 (x=192, y=448, w=80, h=16)
    dc.w    18, 19, 28, 28   ; Solid 24 (x=288, y=448, w=32, h=16)
    dc.w    2, 2, 31, 31   ; Solid 25 (x=32, y=496, w=16, h=16)
    dc.w    4, 9, 31, 31   ; Solid 26 (x=64, y=496, w=96, h=16)
    dc.w    14, 18, 31, 31   ; Solid 27 (x=224, y=496, w=80, h=16)
    dc.w    2, 4, 35, 35   ; Solid 28 (x=32, y=560, w=48, h=16)
    dc.w    6, 13, 35, 35   ; Solid 29 (x=96, y=560, w=128, h=16)
    dc.w    15, 17, 35, 35   ; Solid 30 (x=240, y=560, w=48, h=16)
    dc.w    19, 19, 35, 35   ; Solid 31 (x=304, y=560, w=16, h=16)
    dc.w    2, 4, 36, 36   ; Solid 32 (x=32, y=576, w=48, h=16)
    dc.w    6, 7, 36, 36   ; Solid 33 (x=96, y=576, w=32, h=16)
    dc.w    11, 17, 36, 36   ; Solid 34 (x=176, y=576, w=112, h=16)
    dc.w    19, 19, 36, 36   ; Solid 35 (x=304, y=576, w=16, h=16)
    dc.w    10, 12, 39, 39   ; Solid 36 (x=160, y=624, w=48, h=16)
    dc.w    0, 0, 40, 40   ; Solid 37 (x=0, y=640, w=16, h=16)
    dc.w    2, 9, 40, 40   ; Solid 38 (x=32, y=640, w=128, h=16)
    dc.w    13, 19, 40, 40   ; Solid 39 (x=208, y=640, w=112, h=16)
    dc.w    0, 9, 41, 41   ; Solid 40 (x=0, y=656, w=160, h=16)
    dc.w    13, 19, 41, 41   ; Solid 41 (x=208, y=656, w=112, h=16)
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
Level_01_BridgeCount:     dc.w    1
Level_01_BridgeList:
    dc.w    144, 176, 35, 0   ; Bridge (x=144, y=560, w=32, h=16)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Oxygen Refills Table
; Format: Col (w), Row (w), PixelX (w), PixelY (w), TileId (w), Reserved (3 words)
;------------------------------------------------------------------------------
Level_01_OxygenCount:     dc.w    2
Level_01_OxygenList:
    dc.w    18, 30, 288, 480, 95, 0, 0, 0   ; Oxygen Refill 1
    dc.w    12, 38, 192, 608, 95, 0, 0, 0   ; Oxygen Refill 2
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Tile Physical Attributes Table (256 bytes)
; Maps tile indices to collision flags: 0=Empty, 1=Solid, 2=Ladder, 3=Hazard, 4=Passthrough
;------------------------------------------------------------------------------
Level_01_TileAttributesTable:
    ; Index 00: Empty space
    dc.b    ATTR_EMPTY
    dc.b    ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID
    dc.b    ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_LADDER, ATTR_LADDER, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
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
    dc.b    "CANOPY RESCUE",0
    even

Level_01_SubTitleStr:
    dc.b    "RESCUE ALL ANIMAL FRIENDS",0
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
    dc.w    20, 42                      ; Map width, height in tiles
    dc.l    Level_01_BackgroundMap      ; Background layer binary pointer (0 if none)
    dc.l    Level_01_PlatformMap        ; Platform layer binary pointer (0 if none)
    dc.l    Level_01_LadderMap          ; Ladder layer binary pointer (0 if none)
    dc.l    Level_01_ForegroundMap      ; Foreground layer binary pointer (0 if none)
    dc.l    Level_01_WaterMap           ; Water layer binary pointer (0 if none)
    dc.w    4, 0                        ; Number of ordered tile layers, reserved
    dc.l    Level_01_LayerList          ; Ordered layer list pointer (TMX order)
    dc.l    Level_01_GameMap            ; 1D collision GameMap binary pointer

    ; --- Camera Bounds & Margins ---
    dc.w    0, 448                      ; MinCameraY, MaxCameraY
    dc.w    448                         ; InitialCameraY
    dc.w    16, 176                     ; CamMarginTop, CamMarginBottom

    ; --- Player Starts ---
    dc.w    2, 39, 1                    ; Player 1: Col, Row, Facing (+1=Right, -1=Left)
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

