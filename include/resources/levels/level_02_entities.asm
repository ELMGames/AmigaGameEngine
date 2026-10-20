;==============================================================================
; Auto-generated Level Metadata for Level_02
; Generated from: Level_02.tmx
;==============================================================================

Level_02_MapWidth:        dc.w    20
Level_02_MapHeight:       dc.w    13
Level_02_MapSize:         dc.w    260
Level_02_TileWidth:       dc.w    16
Level_02_TileHeight:      dc.w    16
Level_02_LayerCount:      dc.w    4

;------------------------------------------------------------------------------
; Tilemap Layer Binaries
;------------------------------------------------------------------------------
Level_02_BackgroundMap:
    incbin     "assets/levels/Level_02/Level_02-background.map"
    even

Level_02_SceneryMap = Level_02_BackgroundMap

Level_02_PlatformMap:
    incbin     "assets/levels/Level_02/Level_02-platform.map"
    even

Level_02_LadderMap:
    incbin     "assets/levels/Level_02/Level_02-ladder.map"
    even

Level_02_ForegroundMap:
    incbin     "assets/levels/Level_02/Level_02-foreground.map"
    even

Level_02_WaterMap = 0

;------------------------------------------------------------------------------
; Ordered Tilemap Layer Table (Blit Reference Source for NonDisplayScreen)
; Format: Pointers to each layer's binary map, terminated by 0
; Order: 1. Scenery/Background, 2. Platforms, 3. Ladders, 4. Foreground
;------------------------------------------------------------------------------
Level_02_LayerList:
    dc.l    Level_02_BackgroundMap
    dc.l    Level_02_PlatformMap
    dc.l    Level_02_LadderMap
    dc.l    Level_02_ForegroundMap
    dc.l    0                           ; Null termination

Level_02_CompositeMap:
    incbin     "assets/levels/Level_02/Level_02.map"
    even

;------------------------------------------------------------------------------
; 1D GameMap Binary (20 cols x 13 rows = 260 bytes)
; Format: 1 byte per tile, containing BLOCK_xxx values
;------------------------------------------------------------------------------
Level_02_GameMap:
    incbin     "assets/levels/Level_02/Level_02-gamemap.bin"
    even

;------------------------------------------------------------------------------
; Player Starting Coordinates
;------------------------------------------------------------------------------
Level_02_PlayerStartX:    dc.w    16
Level_02_PlayerStartY:    dc.w    160
Level_02_PlayerCol:       dc.w    1
Level_02_PlayerRow:       dc.w    10
Level_02_PlayerXDec:      dc.w    8
Level_02_PlayerDir:       dc.w    1       ; -1=Left, +1=Right

;------------------------------------------------------------------------------
; Player 2 Starting Coordinates (0 if solo)
;------------------------------------------------------------------------------
Level_02_Player2StartX:   dc.w    0
Level_02_Player2StartY:   dc.w    0
Level_02_Player2Col:      dc.w    0
Level_02_Player2Row:      dc.w    0
Level_02_Player2XDec:     dc.w    0
Level_02_Player2Dir:      dc.w    0       ; -1=Left, +1=Right (0=Solo)

;------------------------------------------------------------------------------
; Enemy Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), PatrolMinX (w), PatrolMaxX (w), Speed (w)
;------------------------------------------------------------------------------
Level_02_EnemyCount:      dc.w    0
Level_02_EnemyList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Animal Friends Spawn Table
; Format: Type (w), Col (w), Row (w), SpawnX (w), SpawnY (w), Res1 (w), Res2 (w), Res3 (w)
;   Type: 1=BUNNY, 2=PUPPY, 3=KITTEN, 4=DUCKLING, 5=CHICK
;------------------------------------------------------------------------------
Level_02_FriendCount:     dc.w    3
Level_02_FriendList:
    dc.w    3, 4, 2, 64, 32, 0, 0, 0   ; Friend 1: DUCKLING
    dc.w    3, 18, 5, 288, 80, 0, 0, 0   ; Friend 2: DUCKLING
    dc.w    3, 18, 10, 288, 160, 0, 0, 0   ; Friend 3: DUCKLING
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Pushable / Movable Blocks Table
; Format: Col (w), Row (w), SpriteIndex (w), Reserved (w)
;------------------------------------------------------------------------------
Level_02_BlockCount:      dc.w    0
Level_02_BlockList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Ladder Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_02_LadderCount:     dc.w    2
Level_02_LadderList:
    dc.w    6, 6, 3, 10   ; Ladder 1 (x=96, y=48, w=16, h=128)
    dc.w    16, 16, 6, 10   ; Ladder 2 (x=256, y=96, w=16, h=80)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Solid Platform Zones
; Format: ColStart (w), ColEnd (w), RowStart (w), RowEnd (w)
;------------------------------------------------------------------------------
Level_02_SolidCount:      dc.w    7
Level_02_SolidList:
    dc.w    3, 5, 3, 3   ; Solid 1 (x=48, y=48, w=48, h=16)
    dc.w    7, 10, 3, 3   ; Solid 2 (x=112, y=48, w=64, h=16)
    dc.w    4, 5, 6, 6   ; Solid 3 (x=64, y=96, w=32, h=16)
    dc.w    7, 15, 6, 6   ; Solid 4 (x=112, y=96, w=144, h=16)
    dc.w    17, 19, 6, 6   ; Solid 5 (x=272, y=96, w=48, h=16)
    dc.w    0, 19, 11, 11   ; Solid 6 (x=0, y=176, w=320, h=16)
    dc.w    0, 19, 12, 12   ; Solid 7 (x=0, y=192, w=320, h=16)
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Triggers & Level Event Zones
; Format: TriggerID (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_02_TriggerCount:    dc.w    0
Level_02_TriggerList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Hazard Zones
; Format: Damage (w), Left (w), Top (w), Right (w), Bottom (w)
;------------------------------------------------------------------------------
Level_02_HazardCount:     dc.w    0
Level_02_HazardList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Bridge Zones
; Format: LeftX (w), RightX (w), PlatformRow (w), Reserved (w)
;------------------------------------------------------------------------------
Level_02_BridgeCount:     dc.w    0
Level_02_BridgeList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Oxygen Refills Table
; Format: Col (w), Row (w), PixelX (w), PixelY (w), TileId (w), Reserved (3 words)
;------------------------------------------------------------------------------
Level_02_OxygenCount:     dc.w    0
Level_02_OxygenList:
    dc.w    $ffff                       ; End of list marker

;------------------------------------------------------------------------------
; Tile Physical Attributes Table (256 bytes)
; Maps tile indices to collision flags: 0=Empty, 1=Solid, 2=Ladder, 3=Hazard, 4=Passthrough
;------------------------------------------------------------------------------
Level_02_TileAttributesTable:
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
Level_02_Palette:
    dc.w    $0000, $01be, $0332, $0fff, $0274, $0193, $0f91, $025c
    dc.w    $0fc2, $0da6, $0b74, $0813, $0d12, $089b, $0177, $0ca8
    even

;------------------------------------------------------------------------------
; Level Text Strings
;------------------------------------------------------------------------------
Level_02_TitleStr:
    dc.b    "GIRDERS OF KONG",0
    even

Level_02_SubTitleStr:
    dc.b    "ASCENT OF THE RUSTED BEAMS",0
    even
Level_02_HintStr = Level_02_SubTitleStr

;==============================================================================
; Level Descriptor Definition
; Conforms to LevelDef record structure in include/resources/struct.asm
;==============================================================================
Level_02_Def:
    ; --- Visuals & Audio ---
    dc.l    GameTilesRaw                ; Tileset graphics pointer
    dc.l    GameTilesMsk                ; Tileset mask pointer
    dc.l    Level_02_Palette            ; Palette pointer (16 RGB words)
    dc.l    LevelMod                    ; BGM ProTracker MOD pointer

    ; --- Geometry & Binary Maps ---
    dc.w    20, 13                      ; Map width, height in tiles
    dc.l    Level_02_BackgroundMap      ; Background layer binary pointer (0 if none)
    dc.l    Level_02_PlatformMap        ; Platform layer binary pointer (0 if none)
    dc.l    Level_02_LadderMap          ; Ladder layer binary pointer (0 if none)
    dc.l    Level_02_ForegroundMap      ; Foreground layer binary pointer (0 if none)
    dc.l    0                           ; Water layer binary pointer (0 if none)
    dc.w    4, 0                        ; Number of ordered tile layers, reserved
    dc.l    Level_02_LayerList          ; Ordered layer list pointer (TMX order)
    dc.l    Level_02_GameMap            ; 1D collision GameMap binary pointer

    ; --- Camera Bounds & Margins ---
    dc.w    0, 0                        ; MinCameraY, MaxCameraY
    dc.w    0                           ; InitialCameraY
    dc.w    16, 176                     ; CamMarginTop, CamMarginBottom

    ; --- Player Starts ---
    dc.w    1, 10, 1                    ; Player 1: Col, Row, Facing (+1=Right, -1=Left)
    dc.w    0, 0, 0                     ; Player 2: Col, Row, Facing (0=None/Solo)

    ; --- Entity & Object Lists ---
    dc.l    Level_02_EnemyList          ; Enemy spawn table
    dc.l    Level_02_FriendList         ; Animal friends spawn table
    dc.l    Level_02_BlockList          ; Pushable blocks table
    dc.l    Level_02_LadderList         ; Ladder zones table
    dc.l    Level_02_SolidList          ; Solid platform zones table
    dc.l    Level_02_TriggerList        ; Triggers / switches table
    dc.l    Level_02_HazardList         ; Hazard zones table
    dc.l    Level_02_BridgeList         ; Bridge zones table
    dc.l    Level_02_OxygenList         ; Oxygen refills table

    ; --- Banner Text & Access Code ---
    dc.l    Level_02_TitleStr           ; Null-terminated title string
    dc.l    Level_02_SubTitleStr        ; Null-terminated subtitle string
    dc.b    "ACORN2",0,0                ; 6-char access password + padding
    even

