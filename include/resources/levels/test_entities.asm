;==============================================================================
; Auto-generated Level Metadata for test
; Generated from: test.tmx
;==============================================================================

test_MapWidth:        dc.w    20
test_MapHeight:       dc.w    13
test_MapSize:         dc.w    260
test_TileWidth:       dc.w    16
test_TileHeight:      dc.w    16
test_LayerCount:      dc.w    4

;------------------------------------------------------------------------------
; Tilemap Layer Binaries
;------------------------------------------------------------------------------
test_BackgroundMap:
    incbin     "assets/levels/Test/test-background.map"
    even

test_SceneryMap = test_BackgroundMap

test_PlatformMap:
    incbin     "assets/levels/Test/test-platform.map"
    even

test_LadderMap:
    incbin     "assets/levels/Test/test-ladder.map"
    even

test_ForegroundMap:
    incbin     "assets/levels/Test/test-foreground.map"
    even

test_WaterMap = 0

;------------------------------------------------------------------------------
; Ordered Tilemap Layer Table (Blit Reference Source for NonDisplayScreen)
; Format: Pointers to each layer's binary map, terminated by 0
; Order: 1. Scenery/Background, 2. Platforms, 3. Ladders, 4. Foreground
;------------------------------------------------------------------------------
test_LayerList:
    dc.l    test_BackgroundMap
    dc.l    test_PlatformMap
    dc.l    test_LadderMap
    dc.l    test_ForegroundMap
    dc.l    0                           ; Null termination

test_CompositeMap:
    incbin     "assets/levels/Test/test.map"
    even

;------------------------------------------------------------------------------
; 1D GameMap Binary (20 cols x 13 rows = 260 bytes)
; Format: 1 byte per tile, containing BLOCK_xxx values
;------------------------------------------------------------------------------
test_GameMap:
    incbin     "assets/levels/Test/test-gamemap.bin"
    even

;------------------------------------------------------------------------------
; Player Starting Coordinates
;------------------------------------------------------------------------------
test_PlayerStartX:    dc.w    32
test_PlayerStartY:    dc.w    160
test_PlayerCol:       dc.w    2
test_PlayerRow:       dc.w    10
test_PlayerXDec:      dc.w    8
test_PlayerDir:       dc.w    1       ; -1=Left, +1=Right

;------------------------------------------------------------------------------
; Player 2 Starting Coordinates (0 if solo)
;------------------------------------------------------------------------------
test_Player2StartX:   dc.w    0
test_Player2StartY:   dc.w    0
test_Player2Col:      dc.w    0
test_Player2Row:      dc.w    0
test_Player2XDec:     dc.w    0
test_Player2Dir:      dc.w    0       ; -1=Left, +1=Right (0=Solo)

;------------------------------------------------------------------------------
; Enemy Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), PatrolMinX (w), PatrolMaxX (w), Speed (w)
;------------------------------------------------------------------------------
test_EnemyCount:      dc.w    0
test_EnemyList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Animal Friends Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), Res1 (w), Res2 (w), Res3 (w)
;   Type: 1=BUNNY, 2=PUPPY, 3=KITTEN, 4=DUCKLING, 5=CHICK
;------------------------------------------------------------------------------
test_FriendCount:     dc.w    1
test_FriendList:
    dc.w    3, 17, 10, 272, 160, 0, 0, 0   ; Friend 1: DUCKLING
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Pushable / Movable Blocks Table
; Format: Col (w), Row (w), SpriteIndex (w), Reserved (w)
;------------------------------------------------------------------------------
test_BlockCount:      dc.w    0
test_BlockList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Ladder Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
test_LadderCount:     dc.w    1
test_LadderList:
    dc.w    13, 13, 3, 10   ; Ladder 1 (x=208, y=48, w=16, h=128)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Solid Platform Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
test_SolidCount:      dc.w    4
test_SolidList:
    dc.w    8, 12, 3, 3   ; Solid 1 (x=128, y=48, w=80, h=16)
    dc.w    14, 17, 3, 3   ; Solid 2 (x=224, y=48, w=64, h=16)
    dc.w    0, 19, 11, 11   ; Solid 3 (x=0, y=176, w=320, h=16)
    dc.w    0, 19, 12, 12   ; Solid 4 (x=0, y=192, w=320, h=16)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Triggers & Level Event Zones
; Format: TriggerID (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
test_TriggerCount:    dc.w    0
test_TriggerList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Hazard Zones
; Format: Damage (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
test_HazardCount:     dc.w    0
test_HazardList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Bridge Zones
; Format: LeftX (w), RightX (w), PlatformRow (w), Reserved (w)
;------------------------------------------------------------------------------
test_BridgeCount:     dc.w    0
test_BridgeList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Oxygen Refills Table
; Format: Col (w), Row (w), PixelX (w), PixelY (w), TileId (w), Reserved (3 words)
;------------------------------------------------------------------------------
test_OxygenCount:     dc.w    0
test_OxygenList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Tile Physical Attributes Table (256 bytes)
; Maps tile indices to collision flags: 0=Empty, 1=Solid, 2=Ladder, 3=Hazard, 4=Passthrough
;------------------------------------------------------------------------------
test_TileAttributesTable:
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
test_Palette:
    dc.w    $0000, $01be, $0332, $0fff, $0274, $0193, $0f91, $025c
    dc.w    $0fc2, $0da6, $0b74, $0813, $0d12, $089b, $0177, $0ca8
    even

;------------------------------------------------------------------------------
; Level Text Strings
;------------------------------------------------------------------------------
test_TitleStr:
    dc.b    "ORCHARD GROVE",0
    even

test_SubTitleStr:
    dc.b    "FIRST STEPS IN DUCK RESCUE",0
    even
test_HintStr = test_SubTitleStr

;==============================================================================
; Level Descriptor Definition
; Conforms to LevelDef record structure in include/resources/struct.asm
;==============================================================================
test_Def:
    ; --- Visuals & Audio ---
    dc.l    GameTilesRaw                ; Tileset graphics pointer
    dc.l    GameTilesMsk                ; Tileset mask pointer
    dc.l    test_Palette                ; Palette pointer (16 RGB words)
    dc.l    LevelMod                    ; BGM ProTracker MOD pointer

    ; --- Geometry & Binary Maps ---
    dc.w    20, 13                      ; Map width, height in tiles
    dc.l    test_BackgroundMap          ; Background layer binary pointer (0 if none)
    dc.l    test_PlatformMap            ; Platform layer binary pointer (0 if none)
    dc.l    test_LadderMap              ; Ladder layer binary pointer (0 if none)
    dc.l    test_ForegroundMap          ; Foreground layer binary pointer (0 if none)
    dc.l    0                           ; Water layer binary pointer (0 if none)
    dc.w    4, 0                        ; Number of ordered tile layers, reserved
    dc.l    test_LayerList              ; Ordered layer list pointer (TMX order)
    dc.l    test_GameMap                ; 1D collision GameMap binary pointer

    ; --- Camera Bounds & Margins ---
    dc.w    0, 0                        ; MinCameraY, MaxCameraY
    dc.w    0                           ; InitialCameraY
    dc.w    16, 176                     ; CamMarginTop, CamMarginBottom

    ; --- Player Starts ---
    dc.w    2, 10, 1                    ; Player 1: Col, Row, Facing (+1=Right, -1=Left)
    dc.w    0, 0, 0                     ; Player 2: Col, Row, Facing (0=None/Solo)

    ; --- Entity & Object Lists ---
    dc.l    test_EnemyList              ; Enemy spawn table
    dc.l    test_FriendList             ; Animal friends spawn table
    dc.l    test_BlockList              ; Pushable blocks table
    dc.l    test_LadderList             ; Ladder zones table
    dc.l    test_SolidList              ; Solid platform zones table
    dc.l    test_TriggerList            ; Triggers / switches table
    dc.l    test_HazardList             ; Hazard zones table
    dc.l    test_BridgeList             ; Bridge zones table
    dc.l    test_OxygenList             ; Oxygen refills table

    ; --- Banner Text & Access Code ---
    dc.l    test_TitleStr               ; Null-terminated title string
    dc.l    test_SubTitleStr            ; Null-terminated subtitle string
    dc.b    "ACORN1",0,0                ; 6-char access password + padding
    even

