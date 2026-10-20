;==============================================================================
; Auto-generated Level Metadata for Level_06
; Generated from: Level_06.tmx
;==============================================================================

Level_06_MapWidth:        dc.w    20
Level_06_MapHeight:       dc.w    26
Level_06_MapSize:         dc.w    520
Level_06_TileWidth:       dc.w    16
Level_06_TileHeight:      dc.w    16
Level_06_LayerCount:      dc.w    4

;------------------------------------------------------------------------------
; Tilemap Layer Binaries
;------------------------------------------------------------------------------
Level_06_BackgroundMap:
    incbin     "assets/levels/Level_06/Level_06-background.map"
    even

Level_06_SceneryMap = Level_06_BackgroundMap

Level_06_PlatformMap:
    incbin     "assets/levels/Level_06/Level_06-platform.map"
    even

Level_06_LadderMap:
    incbin     "assets/levels/Level_06/Level_06-ladder.map"
    even

Level_06_ForegroundMap:
    incbin     "assets/levels/Level_06/Level_06-foreground.map"
    even

Level_06_WaterMap:
    incbin     "assets/levels/Level_06/Level_06-water.map"
    even

;------------------------------------------------------------------------------
; Ordered Tilemap Layer Table (Blit Reference Source for NonDisplayScreen)
; Format: Pointers to each layer's binary map, terminated by 0
; Order: 1. Scenery/Background, 2. Platforms, 3. Ladders, 4. Foreground
;------------------------------------------------------------------------------
Level_06_LayerList:
    dc.l    Level_06_BackgroundMap
    dc.l    Level_06_PlatformMap
    dc.l    Level_06_LadderMap
    dc.l    Level_06_ForegroundMap
    dc.l    0                           ; Null termination

Level_06_CompositeMap:
    incbin     "assets/levels/Level_06/Level_06.map"
    even

;------------------------------------------------------------------------------
; 1D GameMap Binary (20 cols x 26 rows = 520 bytes)
; Format: 1 byte per tile, containing BLOCK_xxx values
;------------------------------------------------------------------------------
Level_06_GameMap:
    incbin     "assets/levels/Level_06/Level_06-gamemap.bin"
    even

;------------------------------------------------------------------------------
; Player Starting Coordinates
;------------------------------------------------------------------------------
Level_06_PlayerStartX:    dc.w    16
Level_06_PlayerStartY:    dc.w    368
Level_06_PlayerCol:       dc.w    1
Level_06_PlayerRow:       dc.w    23
Level_06_PlayerXDec:      dc.w    8
Level_06_PlayerDir:       dc.w    1       ; -1=Left, +1=Right

;------------------------------------------------------------------------------
; Player 2 Starting Coordinates (0 if solo)
;------------------------------------------------------------------------------
Level_06_Player2StartX:   dc.w    0
Level_06_Player2StartY:   dc.w    0
Level_06_Player2Col:      dc.w    0
Level_06_Player2Row:      dc.w    0
Level_06_Player2XDec:     dc.w    0
Level_06_Player2Dir:      dc.w    0       ; -1=Left, +1=Right (0=Solo)

;------------------------------------------------------------------------------
; Enemy Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), PatrolMinX (w), PatrolMaxX (w), Speed (w)
;------------------------------------------------------------------------------
Level_06_EnemyCount:      dc.w    3
Level_06_EnemyList:
    dc.w    2, 7, 10, 112, 160, 32, 112, 1   ; Enemy 1
    dc.w    7, 13, 15, 208, 240, 96, 240, 1   ; Enemy 2
    dc.w    3, 14, 22, 224, 352, 176, 272, 2   ; Enemy 3
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Animal Friends Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), Res1 (w), Res2 (w), Res3 (w)
;   Type: 1=BUNNY, 2=PUPPY, 3=KITTEN, 4=DUCKLING, 5=CHICK
;------------------------------------------------------------------------------
Level_06_FriendCount:     dc.w    5
Level_06_FriendList:
    dc.w    3, 3, 4, 48, 64, 0, 0, 0   ; Friend 1: DUCKLING
    dc.w    3, 18, 5, 288, 80, 0, 0, 0   ; Friend 2: DUCKLING
    dc.w    3, 18, 15, 288, 240, 0, 0, 0   ; Friend 3: DUCKLING
    dc.w    3, 2, 19, 32, 304, 0, 0, 0   ; Friend 4: DUCKLING
    dc.w    3, 18, 23, 288, 368, 0, 0, 0   ; Friend 5: DUCKLING
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Pushable / Movable Blocks Table
; Format: Col (w), Row (w), SpriteIndex (w), Reserved (w)
;------------------------------------------------------------------------------
Level_06_BlockCount:      dc.w    1
Level_06_BlockList:
    dc.w    5, 19, 18, 0   ; Block 1: CRATE_1
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Ladder Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_06_LadderCount:     dc.w    5
Level_06_LadderList:
    dc.w    3, 3, 20, 23   ; Ladder 1 (x=48, y=320, w=16, h=64)
    dc.w    5, 5, 5, 10   ; Ladder 2 (x=80, y=80, w=16, h=96)
    dc.w    8, 8, 11, 15   ; Ladder 3 (x=128, y=176, w=16, h=80)
    dc.w    15, 15, 6, 10   ; Ladder 4 (x=240, y=96, w=16, h=80)
    dc.w    16, 16, 11, 23   ; Ladder 5 (x=256, y=176, w=16, h=208)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Solid Platform Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_06_SolidCount:      dc.w    14
Level_06_SolidList:
    dc.w    2, 4, 5, 5   ; Solid 1 (x=32, y=80, w=48, h=16)
    dc.w    6, 9, 5, 5   ; Solid 2 (x=96, y=80, w=64, h=16)
    dc.w    13, 14, 6, 6   ; Solid 3 (x=208, y=96, w=32, h=16)
    dc.w    16, 18, 6, 6   ; Solid 4 (x=256, y=96, w=48, h=16)
    dc.w    2, 7, 11, 11   ; Solid 5 (x=32, y=176, w=96, h=16)
    dc.w    9, 11, 11, 11   ; Solid 6 (x=144, y=176, w=48, h=16)
    dc.w    15, 15, 11, 11   ; Solid 7 (x=240, y=176, w=16, h=16)
    dc.w    6, 15, 16, 16   ; Solid 8 (x=96, y=256, w=160, h=16)
    dc.w    17, 18, 16, 16   ; Solid 9 (x=272, y=256, w=32, h=16)
    dc.w    2, 2, 20, 20   ; Solid 10 (x=32, y=320, w=16, h=16)
    dc.w    4, 6, 20, 20   ; Solid 11 (x=64, y=320, w=48, h=16)
    dc.w    0, 6, 24, 24   ; Solid 12 (x=0, y=384, w=112, h=16)
    dc.w    8, 19, 24, 24   ; Solid 13 (x=128, y=384, w=192, h=16)
    dc.w    7, 7, 25, 25   ; Solid 14 (x=112, y=400, w=16, h=16)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Triggers & Level Event Zones
; Format: TriggerID (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_06_TriggerCount:    dc.w    0
Level_06_TriggerList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Hazard Zones
; Format: Damage (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_06_HazardCount:     dc.w    0
Level_06_HazardList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Bridge Zones
; Format: LeftX (w), RightX (w), PlatformRow (w), Reserved (w)
;------------------------------------------------------------------------------
Level_06_BridgeCount:     dc.w    0
Level_06_BridgeList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Oxygen Refills Table
; Format: Col (w), Row (w), PixelX (w), PixelY (w), TileId (w), Reserved (3 words)
;------------------------------------------------------------------------------
Level_06_OxygenCount:     dc.w    2
Level_06_OxygenList:
    dc.w    10, 15, 160, 240, 46, 0, 0, 0   ; Oxygen Refill 1
    dc.w    11, 23, 176, 368, 46, 0, 0, 0   ; Oxygen Refill 2
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Tile Physical Attributes Table (256 bytes)
; Maps tile indices to collision flags: 0=Empty, 1=Solid, 2=Ladder, 3=Hazard, 4=Passthrough
;------------------------------------------------------------------------------
Level_06_TileAttributesTable:
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
Level_06_Palette:
    dc.w    $0000, $01be, $0332, $0fff, $0274, $0193, $0f91, $025c
    dc.w    $0fc2, $0da6, $0b74, $0813, $0d12, $089b, $0177, $0ca8
    even

;------------------------------------------------------------------------------
; Level Text Strings
;------------------------------------------------------------------------------
Level_06_TitleStr:
    dc.b    "MOSS-VEILED CISTERN",0
    even

Level_06_SubTitleStr:
    dc.b    "OUTRUN THE RISING TIDE",0
    even
Level_06_HintStr = Level_06_SubTitleStr

;==============================================================================
; Level Descriptor Definition
; Conforms to LevelDef record structure in include/resources/struct.asm
;==============================================================================
Level_06_Def:
    ; --- Visuals & Audio ---
    dc.l    GameTilesRaw                ; Tileset graphics pointer
    dc.l    GameTilesMsk                ; Tileset mask pointer
    dc.l    Level_06_Palette            ; Palette pointer (16 RGB words)
    dc.l    LevelMod                    ; BGM ProTracker MOD pointer

    ; --- Geometry & Binary Maps ---
    dc.w    20, 26                      ; Map width, height in tiles
    dc.l    Level_06_BackgroundMap      ; Background layer binary pointer (0 if none)
    dc.l    Level_06_PlatformMap        ; Platform layer binary pointer (0 if none)
    dc.l    Level_06_LadderMap          ; Ladder layer binary pointer (0 if none)
    dc.l    Level_06_ForegroundMap      ; Foreground layer binary pointer (0 if none)
    dc.l    Level_06_WaterMap           ; Water layer binary pointer (0 if none)
    dc.w    4, 0                        ; Number of ordered tile layers, reserved
    dc.l    Level_06_LayerList          ; Ordered layer list pointer (TMX order)
    dc.l    Level_06_GameMap            ; 1D collision GameMap binary pointer

    ; --- Camera Bounds & Margins ---
    dc.w    0, 216                      ; MinCameraY, MaxCameraY
    dc.w    216                         ; InitialCameraY
    dc.w    16, 176                     ; CamMarginTop, CamMarginBottom

    ; --- Player Starts ---
    dc.w    1, 23, 1                    ; Player 1: Col, Row, Facing (+1=Right, -1=Left)
    dc.w    0, 0, 0                     ; Player 2: Col, Row, Facing (0=None/Solo)

    ; --- Entity & Object Lists ---
    dc.l    Level_06_EnemyList          ; Enemy spawn table
    dc.l    Level_06_FriendList         ; Animal friends spawn table
    dc.l    Level_06_BlockList          ; Pushable blocks table
    dc.l    Level_06_LadderList         ; Ladder zones table
    dc.l    Level_06_SolidList          ; Solid platform zones table
    dc.l    Level_06_TriggerList        ; Triggers / switches table
    dc.l    Level_06_HazardList         ; Hazard zones table
    dc.l    Level_06_BridgeList         ; Bridge zones table
    dc.l    Level_06_OxygenList         ; Oxygen refills table

    ; --- Banner Text & Access Code ---
    dc.l    Level_06_TitleStr           ; Null-terminated title string
    dc.l    Level_06_SubTitleStr        ; Null-terminated subtitle string
    dc.b    "ACORN6",0,0                ; 6-char access password + padding
    even

