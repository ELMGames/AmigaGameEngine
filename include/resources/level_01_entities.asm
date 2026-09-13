;==============================================================================
; Auto-generated Level Metadata for Level_01
; Generated from: Level_01.tmx
;==============================================================================

Level_01_MapWidth:        dc.w    20
Level_01_MapHeight:       dc.w    42
Level_01_MapSize:         dc.w    840
Level_01_TileWidth:       dc.w    16
Level_01_TileHeight:      dc.w    16
Level_01_LayerCount:      dc.w    3

;------------------------------------------------------------------------------
; Tilemap Layer Binaries
;------------------------------------------------------------------------------
Level_01_BackgroundMap:
    incbin     "assets/Levels/Level_01-background.map"
    even

Level_01_ForegroundMap:
    incbin     "assets/Levels/Level_01-foreground.map"
    even

Level_01_WaterMap:
    incbin     "assets/Levels/Level_01-water.map"
    even

Level_01_PlatformMap = 0

;------------------------------------------------------------------------------
; Ordered Tilemap Layer Table (in TMX document order)
; Format: Pointers to each layer's binary map, terminated by 0
;------------------------------------------------------------------------------
Level_01_LayerList:
    dc.l    Level_01_BackgroundMap
    dc.l    Level_01_ForegroundMap
    dc.l    Level_01_WaterMap
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
Level_01_PlayerStartX:    dc.w    8
Level_01_PlayerStartY:    dc.w    624
Level_01_PlayerCol:       dc.w    0
Level_01_PlayerRow:       dc.w    38
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
Level_01_EnemyCount:      dc.w    2
Level_01_EnemyList:
    dc.w    3, 17, 37, 280, 592, 160, 288, 2   ; Enemy 1
    dc.w    6, 17, 33, 280, 528, 176, 288, 1   ; Enemy 2
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Ladder Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_01_LadderCount:     dc.w    7
Level_01_LadderList:
    dc.w    10, 10, 31, 33   ; Ladder 1 (x=160, y=496, w=16, h=48)
    dc.w    13, 13, 34, 37   ; Ladder 2 (x=208, y=544, w=16, h=64)
    dc.w    11, 11, 25, 30   ; Ladder 3 (x=176, y=400, w=16, h=96)
    dc.w    9, 9, 38, 38   ; Ladder 4 (x=144, y=608, w=16, h=16)
    dc.w    15, 15, 14, 24   ; Ladder 5 (x=240, y=224, w=16, h=176)
    dc.w    6, 6, 2, 8   ; Ladder 6 (x=96, y=32, w=16, h=112)
    dc.w    10, 10, 9, 13   ; Ladder 7 (x=160, y=144, w=16, h=80)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Solid Platform Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_01_SolidCount:      dc.w    12
Level_01_SolidList:
    dc.w    0, 6, 39, 39   ; Solid 1 (x=0, y=624, w=112, h=16)
    dc.w    10, 14, 38, 38   ; Solid 2 (x=160, y=608, w=80, h=16)
    dc.w    1, 11, 31, 31   ; Solid 3 (x=16, y=496, w=176, h=16)
    dc.w    10, 18, 34, 34   ; Solid 4 (x=160, y=544, w=144, h=16)
    dc.w    9, 16, 25, 25   ; Solid 5 (x=144, y=400, w=128, h=16)
    dc.w    7, 9, 39, 39   ; Solid 6 (x=112, y=624, w=48, h=16)
    dc.w    0, 8, 21, 21   ; Solid 7 (x=0, y=336, w=144, h=16)
    dc.w    8, 16, 14, 14   ; Solid 8 (x=128, y=224, w=144, h=16)
    dc.w    6, 11, 9, 9   ; Solid 9 (x=96, y=144, w=96, h=16)
    dc.w    5, 12, 2, 2   ; Solid 10 (x=80, y=32, w=128, h=16)
    dc.w    15, 17, 38, 38   ; Solid 11 (x=240, y=608, w=48, h=16)
    dc.w    18, 19, 38, 38   ; Solid 12 (x=288, y=608, w=32, h=16)
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
Level_01_BridgeCount:     dc.w    2
Level_01_BridgeList:
    dc.w    112, 160, 39, 0   ; Bridge (x=112, y=624, w=48, h=16)
    dc.w    240, 288, 38, 0   ; Bridge (x=240, y=608, w=48, h=16)
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
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
    dc.b    ATTR_EMPTY, ATTR_LADDER, ATTR_LADDER, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY, ATTR_EMPTY
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
    dc.b    "LEVEL 01",0
    even

Level_01_SubTitleStr:
    dc.b    "USE LADDERS TO ESCAPE",0
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
    dc.l    0                           ; Platform layer binary pointer (0 if none)
    dc.l    Level_01_ForegroundMap      ; Foreground layer binary pointer (0 if none)
    dc.l    Level_01_WaterMap           ; Water layer binary pointer (0 if none)
    dc.w    3, 0                        ; Number of ordered tile layers, reserved
    dc.l    Level_01_LayerList          ; Ordered layer list pointer (TMX order)
    dc.l    Level_01_GameMap            ; 1D collision GameMap binary pointer

    ; --- Camera Bounds & Margins ---
    dc.w    0, 464                      ; MinCameraY, MaxCameraY
    dc.w    432                         ; InitialCameraY
    dc.w    16, 176                     ; CamMarginTop, CamMarginBottom

    ; --- Player Starts ---
    dc.w    0, 38, 1                    ; Player 1: Col, Row, Facing (+1=Right, -1=Left)
    dc.w    0, 0, 0                     ; Player 2: Col, Row, Facing (0=None/Solo)

    ; --- Entity & Object Lists ---
    dc.l    Level_01_EnemyList          ; Enemy spawn table
    dc.l    Level_01_LadderList         ; Ladder zones table
    dc.l    Level_01_SolidList          ; Solid platform zones table
    dc.l    Level_01_TriggerList        ; Triggers / switches table
    dc.l    Level_01_HazardList         ; Hazard zones table
    dc.l    Level_01_BridgeList         ; Bridge zones table

    ; --- Banner Text & Access Code ---
    dc.l    Level_01_TitleStr           ; Null-terminated title string
    dc.l    Level_01_SubTitleStr        ; Null-terminated subtitle string
    dc.b    "ACORN1",0,0                ; 6-char access password + padding
    even

