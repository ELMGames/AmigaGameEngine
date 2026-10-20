;==============================================================================
; AMIGA GAME ENGINE
; tilemap.asm  -  Rainbow Tilemap Engine & Platform Collision Module
;==============================================================================
;
; This module provides:
;   1. TilemapInit          - Loads level tilemap, sets palette, sets camera position.
;   2. TilemapSetPalette    - Copies the 16-colour palette to cpPal / COLOR00-15.
;   3. TilemapDrawViewport  - Blits a 320x200 (20x13 tiles) viewport into a screen
;                             buffer using the Amiga Blitter in cookie-cut mode.
;   4. TilemapGetAttribute  - Returns the physical attribute (solid, ladder, etc.)
;                             for any pixel coordinate (X, Y) within the level.
;   5. TileAttributesTable  - 256-byte attribute map for all tile indices.
;
; Register convention:
;   a6 = $dff000 (CUSTOM)
;   a5 = Variables structure base pointer
;
;==============================================================================

    section main,code

;==============================================================================
; DrawMap  -  Master level draw entry point
;
; Resets player/level state, fully initialises and renders the current level
; into NonDisplayScreen, then copies it to DisplayScreen and both screen buffers.
;
; Call order:
;   LevelInit        - build maps, load assets, create actors
;   TilemapInit      - set camera, palette, clear NonDisplayScreen, blit viewport
;==============================================================================

DrawMap:
    clr.w         PlayerCount(a5)        ; reset player count before re-init
    clr.w         LevelComplete(a5)      ; clear level completion flag
    clr.w         LevelCompleteHold(a5)  ; reset hold countdown
    clr.w         ActionStatus(a5)       ; reset action state to IDLE
    clr.w         SlowMode(a5)           ; unconditionally start in RUN mode
    clr.w         SlowModeHold(a5)
    clr.w         PrevKeyS(a5)
    clr.w         DebugOverlayActive(a5) ; debug overlay starts disabled
    clr.w         GamePaused(a5)
    clr.w         Pause_PaletteActive(a5)
    clr.w         PrevDebugDrawn(a5)
    clr.w         VBlankOverrunCount(a5) ; clear overruns incurred during decompression/load
    lea           Keys,a0
    clr.b         KEY_S(a0)
    clr.b         KEY_A(a0)
    clr.b         KEY_D(a0)
    clr.b         KEY_P(a0)
    bsr           ClearDirtyTiles        ; ensure no stale dirty flags from previous level

    bsr           LevelInit              ; initialize map, player, actors, GameMap

    ; Rainbow Tilemap level initialization and rendering
    bsr           TilemapInit            ; set camera, palette, clear NonDisplayScreen, blit viewport

    rts

;==============================================================================
; TilemapInit  -  Initialize the tilemap engine for Level 1
;
; Sets initial camera offset to the bottom of the 672px tall level (row 29),
; uploads the 16-color tileset palette into the copper list palette entries,
; and draws the initial visible viewport into NonDisplayScreen.
;
; Destroys: d0-d7 / a0-a4 (preserves a5/a6)
;==============================================================================

TilemapInit:
    PUSHM       d0-d7/a0-a4

    ; Initialize camera position from TilemapCameraY (set by LevelInit from LevelDef_InitialCameraY)
    move.w      TilemapCameraY(a5),d0
    move.w      d0,d1
    lsr.w       #4,d1                   ; d1 = row offset (CameraY / 16)
    move.w      d1,TilemapScreenOffset(a5)
    move.w      d1,TilemapCurrentOffset(a5)
    and.w       #15,d0
    move.w      d0,TilemapFineY(a5)
    clr.w       PlayerFrame(a5)

    ; Initialize on-screen debug overlay state
    clr.w       DebugOverlayActive(a5)
    clr.w       SlowMode(a5)           ; unconditionally start in RUN mode
    clr.w       SlowModeHold(a5)
    clr.w       PrevKeyS(a5)
    move.w      TilemapCameraY(a5),PrevDebugCameraY(a5)
    clr.w       PrevDebugDrawn(a5)

    ; Load 16-color palette from LevelDef into copper palette (COLOR00..COLOR15)
    bsr         TilemapSetPalette

    ; Calculate dynamic screen lines and byte size based on CurrentMapHeight(a5)
    ; Add 1 extra tile row padding for all levels so the 216-scanline viewport
    ; can never overrun cleared memory below the bottom of any map.
    move.w      CurrentMapHeight(a5),d1
    addq.w      #1,d1                   ; allow 1 extra tile row padding (up to 43 rows = 688 scanlines)
    lsl.w       #6,d1                   ; d1 = scanlines (16 rows * 4 bitplanes = 64 lines per tile row)
    move.w      d1,d7
    mulu.w      #SCREEN_WIDTH_BYTE,d7   ; d7.l = total bytes (e.g. 896*40 = 35840, 2752*40 = 110080)

    ; Clear active rows + padding of NonDisplayScreen before initial draw
    lea         NonDisplayScreen,a0
    bsr         TurboClear

    ; Blit all level tile layers into NonDisplayScreen (pristine background)
    lea         NonDisplayScreen,a0
    bsr         TilemapDrawViewport

    ; Fast 1-pass Blitter cloning from NonDisplayScreen to DisplayScreen ($09f0, D = A)
    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1
    move.w      CurrentMapHeight(a5),d1
    addq.w      #1,d1                   ; clone active rows plus padding row
    lsl.w       #6,d1                   ; d1 = total scanlines to copy

    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)      ; D = A direct copy
    clr.w       BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)  ; no edge masking
    clr.w       BLTAMOD(a6)             ; full width, continuous scanlines
    clr.w       BLTDMOD(a6)

.clone_screen_loop:
    move.w      d1,d0
    cmp.w       #1024,d0
    ble.s       .clone_chunk
    move.w      #1024,d0
.clone_chunk:
    sub.w       d0,d1                   ; d1 = remaining scanlines
    WAITBLIT
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    lsl.w       #6,d0                   ; lines << 6
    ori.w       #SCREEN_WIDTH_BYTE/2,d0 ; 20 words wide
    move.w      d0,BLTSIZE(a6)
    adda.l      #1024*SCREEN_WIDTH_BYTE,a0
    adda.l      #1024*SCREEN_WIDTH_BYTE,a1
    tst.w       d1
    bgt.s       .clone_screen_loop
    WAITBLIT

    ; Set initial cpPlanes bitplane pointers to bottom of level (CameraPixelY)
    ; Byte offset in DisplayScreen = CameraPixelY * 160
    move.w      TilemapCameraY(a5),d0
    sub.w       #32,d0
    move.w      d0,CameraCullTopY(a5)
    move.w      TilemapCameraY(a5),d0
    add.w       #248,d0
    move.w      d0,CameraCullBottomY(a5)

    move.w      TilemapCameraY(a5),d0
    mulu.w      #TILEMAP_LINE_STRIDE,d0
    add.l       #DisplayScreen,d0
    lea         cpPlanes,a0
    move.l      #SCREEN_WIDTH_BYTE,d1
    moveq       #TILEMAP_TILE_PLANES,d7
    bsr         CopperSetPtrs

    ; Initialize Copper sky gradient (or maintain disabled state if F3 raster bar active)
    cmp.w       #2,DebugMode(a5)
    beq.s       .ti_sky_disabled
    bsr         TilemapEnableCopperSky
    bra.s       .ti_sky_done
.ti_sky_disabled:
    bsr         TilemapDisableCopperSky
.ti_sky_done:

    ; Initialize rising water layer state and timer
    bsr         TilemapInitWater

    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapSetPalette  -  Load 16-color tileset palette into Copper list
;
; Reads palette from CurrentLevelDef (or legacy GameTilesRaw+22528).
; Copies them into cpPal (COLOR00..COLOR15 copper MOVE entries).
;
; Destroys: d7, a0, a1
;==============================================================================

TilemapSetPalette:
    move.l      CurrentLevelDef(a5),d0
    beq.s       .legacy_palette
    movea.l     d0,a0
    movea.l     LevelDef_Palette(a0),a0     ; a0 = pointer to 16-word RGB palette in LevelDef
    bra.s       .copy_palette
.legacy_palette:
    lea         GameTilesRaw+7040,a0
.copy_palette:
    lea         cpPal,a1
    moveq       #16-1,d7
.pal_loop:
    move.w      (a0)+,2(a1)             ; write color word into copper MOVE instruction operand
    addq.l      #4,a1                   ; advance to next copper entry (dc.w COLORxx, val)
    dbra        d7,.pal_loop
    rts


;==============================================================================
; TilemapDrawViewport  -  Render visible 320x200 tilemap into target screen buffer
;
; Arguments:
;   a0 = destination screen buffer in Chip RAM (e.g. NonDisplayScreen)
;
; Uses the Amiga hardware Blitter in Cookie-Cut mode ($0FCA minterm):
;   Channel A = Mask (LevelDef_TilesetMsk)
;   Channel B = Source Tiles (LevelDef_TilesetRaw)
;   Channel C = Destination Screen (Background)
;   Channel D = Destination Screen (Result)
;
; Reads:
;   TilemapScreenOffset(a5) = 0-based starting tile row in the 42-row level map.
;
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

TilemapDrawViewport:
    move.l      a0,-(sp)                ; save destination pointer base

    move.l      CurrentLevelDef(a5),d0
    beq         .legacy_layers
    movea.l     d0,a2

    ; Check if ordered layer list is available
    move.w      LevelDef_LayerCount(a2),d7
    beq         .fallback_layers
    move.l      LevelDef_LayerList(a2),d6
    beq         .fallback_layers

    ; --- Render all tilemap layers in TMX document order ---
    subq.w      #1,d7                   ; DBRA loop counter

.layer_loop:
    movea.l     d6,a1                   ; a1 = current pointer in LayerList
    move.l      (a1)+,d0                ; d0 = layer binary map pointer
    move.l      a1,d6                   ; advance LayerList pointer
    tst.l       d0
    beq.s       .skip_layer             ; skip null map pointer

    movea.l     d0,a2                   ; a2 = map pointer for TilemapDrawLayer
    move.l      (sp),a0                 ; a0 = destination screen buffer base
    bsr         TilemapDrawLayer

.skip_layer:
    dbra        d7,.layer_loop

    move.l      (sp)+,a0                ; pop saved destination pointer
    rts

.fallback_layers:
    ; --- Pass 1: Render Background Layer (if defined in LevelDef) ---
    move.l      LevelDef_BackgroundMap(a2),d0
    beq.s       .no_bg
    movea.l     d0,a2
    move.l      (sp),a0
    bsr         TilemapDrawLayer
.no_bg:

    ; --- Pass 2: Render Platform Elements Layer (cookie-cut over background) ---
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_PlatformMap(a2),d0
    beq.s       .no_plat
    movea.l     d0,a2
    move.l      (sp),a0
    bsr         TilemapDrawLayer
.no_plat:

    ; --- Pass 2.25: Render Ladder Layer (cookie-cut over platforms) ---
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_LadderMap(a2),d0
    beq.s       .no_ladder
    movea.l     d0,a2
    move.l      (sp),a0
    bsr         TilemapDrawLayer
.no_ladder:

    ; --- Pass 2.5: Render Foreground Elements Layer (cookie-cut over platforms & ladders) ---
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_ForegroundMap(a2),d0
    beq.s       .no_fg
    movea.l     d0,a2
    move.l      (sp),a0
    bsr         TilemapDrawLayer
.no_fg:

    ; --- Pass 3: Render Water Layer (if defined in LevelDef) ---
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_WaterMap(a2),d0
    beq.s       .no_water
    movea.l     d0,a2
    move.l      (sp),a0
    bsr         TilemapDrawLayer
.no_water:
    move.l      (sp)+,a0                ; pop saved destination pointer
    rts

.legacy_layers:
    ; --- Render Platform Elements Layer ---
    lea         Level_01_PlatformMap,a2
    move.l      (sp)+,a0
    bsr         TilemapDrawLayer
    rts

;==============================================================================
; Performance Lookup Tables in Fast RAM (main,code)
;==============================================================================
    even
TileSheetOffsetTable:
    ; Row 0: tiles 0..10
    dc.w    0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20
    ; Row 1: tiles 11..21
    dc.w    1408, 1410, 1412, 1414, 1416, 1418, 1420, 1422, 1424, 1426, 1428
    ; Row 2: tiles 22..32
    dc.w    2816, 2818, 2820, 2822, 2824, 2826, 2828, 2830, 2832, 2834, 2836
    ; Row 3: tiles 33..43
    dc.w    4224, 4226, 4228, 4230, 4232, 4234, 4236, 4238, 4240, 4242, 4244
    ; Row 4: tiles 44..54
    dc.w    5632, 5634, 5636, 5638, 5640, 5642, 5644, 5646, 5648, 5650, 5652
    ; Safety padding (tiles 55..63)
    dcb.w   9, 0

    even
TileRowStrideTable:
    ; Row 0..41 screen stride offsets (Row * 2560 bytes)
    dc.l    0, 2560, 5120, 7680, 10240, 12800, 15360, 17920
    dc.l    20480, 23040, 25600, 28160, 30720, 33280, 35840, 38400
    dc.l    40960, 43520, 46080, 48640, 51200, 53760, 56320, 58880
    dc.l    61440, 64000, 66560, 69120, 71680, 74240, 76800, 79360
    dc.l    81920, 84480, 87040, 89600, 92160, 94720, 97280, 99840
    dc.l    102400, 104960

    even
MapRowOffsetTable:
    ; Row 0..41 grid offsets (Row * 20 tiles)
    dc.w    0, 20, 40, 60, 80, 100, 120, 140
    dc.w    160, 180, 200, 220, 240, 260, 280, 300
    dc.w    320, 340, 360, 380, 400, 420, 440, 460
    dc.w    480, 500, 520, 540, 560, 580, 600, 620
    dc.w    640, 660, 680, 700, 720, 740, 760, 780
    dc.w    800, 820

TilemapDrawLayer:
    clr.w       d0                      ; StartRow = 0
    move.w      CurrentMapHeight(a5),d1
    subq.w      #1,d1                   ; EndRow = CurrentMapHeight - 1
    blt.s       .empty_layer
    bsr.s       TilemapDrawLayerRows
.empty_layer:
    rts

TilemapDrawLayerRows:
    PUSHM       d2-d7/a2-a4
    move.l      a0,a1                   ; a1 = destination screen buffer base
    move.w      d0,d2
    add.w       d2,d2
    add.w       d2,d2                   ; d2 = StartRow * 4 (longword index)
    lea         TileRowStrideTable,a3
    adda.l      (a3,d2.w),a1           ; a1 = destination row pointer

    move.l      a2,a0                   ; a0 = map pointer base
    addq.l      #8,a0                   ; skip 8-byte width/height header
    move.w      d0,d2
    lsl.w       #3,d2                   ; StartRow * 8
    move.w      d0,d3
    lsl.w       #5,d3                   ; StartRow * 32
    add.w       d3,d2                   ; d2 = StartRow * 40
    adda.w      d2,a0                   ; a0 = map row pointer

    ; Render all requested rows ((EndRow - StartRow + 1) * 20 tiles)
    move.w      d1,d5
    sub.w       d0,d5
    addq.w      #1,d5
    move.w      d5,d2
    lsl.w       #2,d2                   ; rows * 4
    lsl.w       #4,d5                   ; rows * 16
    add.w       d2,d5                   ; d5 = rows * 20 total tiles
    subq.w      #1,d5                   ; for dbra
    bmi         .done_layer_rows
    clr.w       d4                      ; d4 = column counter (0..19)

    ; Lift invariant Blitter control registers outside the tile loop
    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)  ; no edge masking (word-aligned 16px tile)
    move.w      #TILEMAP_SHEET_BYTES-TILEMAP_TILE_BYTES,BLTAMOD(a6)
    move.w      #TILEMAP_SHEET_BYTES-TILEMAP_TILE_BYTES,BLTBMOD(a6)
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTCMOD(a6)
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTDMOD(a6)

    ; Resolve tileset base pointers once outside the tile loop
    move.l      CurrentLevelDef(a5),d2
    beq.s       .td_legacy_ts
    movea.l     d2,a3
    movea.l     LevelDef_TilesetMsk(a3),a2 ; a2 = tileset mask base
    movea.l     d2,a3
    movea.l     LevelDef_TilesetRaw(a3),a3 ; a3 = tileset raw base
    bra.s       .td_ts_ready
.td_legacy_ts:
    lea         GameTilesMsk,a2
    lea         GameTilesRaw,a3
.td_ts_ready:

.tile_loop:
    ; Read tile index from map data (Big-Endian word: $00XX)
    move.w      (a0)+,d0
    beq.s       .skip_empty_tile        ; tile index 0 is transparent/empty

    ; Fast lookup of source byte offset in tileset!
    add.w       d0,d0
    lea         TileSheetOffsetTable,a4
    move.w      (a4,d0.w),d0
    ext.l       d0

    WAITBLIT
    movea.l     a2,a4
    adda.l      d0,a4
    move.l      a4,BLTAPT(a6)           ; Mask (Channel A)
    movea.l     a3,a4
    adda.l      d0,a4
    move.l      a4,BLTBPT(a6)           ; Source tile (Channel B)
    move.l      a1,BLTCPT(a6)           ; Destination screen (Channel C)
    move.l      a1,BLTDPT(a6)           ; Destination screen (Channel D)

    ; Blit Size: 16 rows * 4 bitplanes = 64 rows, 1 word wide (16px)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|(TILEMAP_TILE_BYTES/2),BLTSIZE(a6)

.skip_empty_tile:
    ; Advance destination pointer by 2 bytes (one 16px tile width)
    addq.l      #TILEMAP_TILE_BYTES,a1

    ; Check column counter
    addq.w      #1,d4
    cmp.w       #TILEMAP_VIEW_COLS,d4
    bne.s       .next_tile

    ; End of row: reset column counter and advance destination pointer
    ; by the remaining scanlines of the interleaved row:
    ; Row stride in 4-plane interleaved = 16 rows * 40 bytes * 4 planes = 2560 bytes
    ; We already added 20 * 2 = 40 bytes across the columns, so add 2560 - 40 = 2520 bytes
    clr.w       d4
    add.l       #(TILEMAP_TILE_HEIGHT*SCREEN_WIDTH_BYTE*TILEMAP_TILE_PLANES)-SCREEN_WIDTH_BYTE,a1

.next_tile:
    dbra        d5,.tile_loop

.done_layer_rows:
    POPM        d2-d7/a2-a4
    rts


;==============================================================================
; TilemapInitWater  -  Initialize water layer height and countdown timer
;
; Initializes WaterCurrentRow to WATER_START_ROW (40) and loads WaterTimer
; with ScalePALFrames(WATER_RISE_FRAMES) (10 seconds).
; Copies LevelDef_WaterMap into LiveWaterMap working buffer.
;
; Destroys: d0-d2, a0-a1 (preserves a5, a6)
;==============================================================================

TilemapInitWater:
    PUSHM       d0-d7/a0-a4

    ; Check if LevelDef defines a water layer
    move.l      CurrentLevelDef(a5),d0
    beq         .no_water
    movea.l     d0,a0
    move.l      LevelDef_WaterMap(a0),d0
    beq         .no_water

    ; Copy binary water map into LiveWaterMap working buffer
    ; Size is 8-byte header (4 words) + CurrentMapSize words
    movea.l     d0,a0
    lea         LiveWaterMap(a5),a1
    move.w      CurrentMapSize(a5),d2
    addq.w      #4,d2                  ; 4 header words
    subq.w      #1,d2
.copy_map:
    move.w      (a0)+,(a1)+
    dbra        d2,.copy_map

    ; Initialize top of water row and exact vertical pixel scanline
    move.w      CurrentMapHeight(a5),d0
    subq.w      #1,d0
    move.w      d0,WaterCurrentRow(a5)
    lsl.w       #4,d0
    move.w      d0,WaterPixelY(a5)
    clr.w       WaterSubTick(a5)

    ; Calculate 10-second period in frames (500 frames PAL, 600 frames NTSC)
    move.w      #WATER_RISE_FRAMES,d0
    bsr         ScalePALFrames
    move.w      d0,WaterRisePeriod(a5)

    ; --- Render Initial Waterline & Submerged Body ---
    ; Draw 4-line wave profile across WaterPixelY, then fill all scanlines below
    ; down to the bottom of the map with solid blue water (Line 4 stipple).
    move.w      WaterPixelY(a5),d0
    moveq       #0,d6                   ; Wave Line 0 (crest tips)
    bsr         TilemapApplyWaveScanline
    addq.w      #1,d0
    moveq       #1,d6                   ; Wave Line 1 (foam & highlight)
    bsr         TilemapApplyWaveScanline
    addq.w      #1,d0
    moveq       #2,d6                   ; Wave Line 2 (full contour)
    bsr         TilemapApplyWaveScanline
    addq.w      #1,d0
    moveq       #3,d6                   ; Wave Line 3 (base highlight)
    bsr         TilemapApplyWaveScanline
    addq.w      #1,d0                   ; WaterPixelY + 4

    ; Fill all scanlines below wave down to bottom of map with solid blue
    move.w      CurrentMapHeight(a5),d4
    lsl.w       #4,d4
    subq.w      #1,d4                   ; d4 = (CurrentMapHeight * 16) - 1
    cmp.w       #LEVEL_SCREEN_HEIGHT-1,d4
    ble.s       .init_scan_end_ok
    move.w      #LEVEL_SCREEN_HEIGHT-1,d4
.init_scan_end_ok:

.init_fill_blue_loop:
    cmp.w       d4,d0
    bgt.s       .done
    moveq       #4,d6                   ; Line 4 (solid blue fill)
    bsr         TilemapApplyWaveScanline
    addq.w      #1,d0
    bra.s       .init_fill_blue_loop

.no_water:
    move.w      #-1,WaterCurrentRow(a5)
    move.w      #-1,WaterPixelY(a5)
    clr.w       WaterSubTick(a5)
    clr.w       WaterRisePeriod(a5)

.done:
    ; Initialize sprite priority: sprites in front of playfield (dry)
    move.w      #$0024,cpBPLCON2+2
    move.w      #$0024,BPLCON2(a6)

    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapBlitTileRow  -  Cookie-cut blit a full 20-tile row of a single tile
;
; Arguments:
;   d0.w = tile index (e.g. WATER_TILE_SURFACE or WATER_TILE_DEEP)
;   d1.w = map row index (0..41)
;   a0   = destination screen buffer base (NonDisplayScreen or DisplayScreen)
;
; Blits 20 columns across the row using the 50% dither mask in cookie-cut
; mode ($0FCA).
;
; Destroys: d0-d5, a1-a4 (preserves a5, a6)
;==============================================================================

TilemapBlitTileRow:
    PUSHM       d0-d5/a1-a4

    ; Calculate destination row start address:
    ; Row byte stride = 16 scanlines * 160 bytes = 2560 bytes
    add.w       d1,d1
    add.w       d1,d1                   ; d1 = row * 4 (longword index)
    lea         TileRowStrideTable,a1
    adda.l      (a1,d1.w),a0
    movea.l     a0,a1                   ; a1 = destination row pointer

    ; Fast lookup of source byte offset in tileset!
    add.w       d0,d0
    lea         TileSheetOffsetTable,a3
    move.w      (a3,d0.w),d0
    ext.l       d0                      ; d0 = total byte offset in tileset

    move.l      CurrentLevelDef(a5),d2
    beq.s       .legacy_tileset
    movea.l     d2,a3
    movea.l     LevelDef_TilesetMsk(a3),a3
    movea.l     d2,a4
    movea.l     LevelDef_TilesetRaw(a4),a4
    bra.s       .tileset_ready
.legacy_tileset:
    lea         GameTilesMsk,a3
    lea         GameTilesRaw,a4
.tileset_ready:
    add.l       d0,a3                   ; a3 = source mask pointer
    add.l       d0,a4                   ; a4 = source graphic pointer

    ; Wait for Blitter before configuring registers
    WAITBLIT

    ; Cookie-cut minterm $CA: D = (A & B) | (~A & C)
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)  ; no edge masking

    ; Source and destination modulos:
    ; Source sheet modulo = 22 - 2 = 20 bytes
    ; Dest screen modulo  = 40 - 2 = 38 bytes
    move.w      #TILEMAP_SHEET_BYTES-TILEMAP_TILE_BYTES,BLTAMOD(a6)
    move.w      #TILEMAP_SHEET_BYTES-TILEMAP_TILE_BYTES,BLTBMOD(a6)
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTCMOD(a6)
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTDMOD(a6)

    ; Blit 20 columns across the row
    moveq       #TILEMAP_VIEW_COLS-1,d5 ; 20 - 1 = 19
.col_loop:
    WAITBLIT
    move.l      a3,BLTAPT(a6)           ; Mask (Channel A)
    move.l      a4,BLTBPT(a6)           ; Source tile (Channel B)
    move.l      a1,BLTCPT(a6)           ; Destination screen (Channel C)
    move.l      a1,BLTDPT(a6)           ; Destination screen (Channel D)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|(TILEMAP_TILE_BYTES/2),BLTSIZE(a6)

    addq.l      #TILEMAP_TILE_BYTES,a1  ; advance to next column
    dbra        d5,.col_loop

    POPM        d0-d5/a1-a4
    rts


;==============================================================================
; TilemapUpdateWater  -  Advance rising water layer every 10 seconds
;
; Called every frame from GameRun in gamestatus.asm.
; Ticks WaterTimer countdown. Every 10 seconds (500 PAL frames):
;   1. Decrements WaterCurrentRow (advances water up by 1 tile row).
;   2. Updates LiveWaterMap: new top row becomes surface (tile 104),
;      previous top row becomes deep water (tile 115).
;   3. Blits the new surface row (tile 104) and deep row (tile 115) into
;      both NonDisplayScreen and DisplayScreen with 50% semi-transparency.
;
; Destroys: none (preserves all registers)
;==============================================================================

;==============================================================================
; Water Wave Graphic & Solid Blue Fill Tables
;
; Format per entry (5 words = 10 bytes):
;   +0: not_m  (AND mask applied to bitplanes: clears dither bits, preserves dry background)
;   +2: p0_or  (OR value for Plane 0)
;   +4: p1_or  (OR value for Plane 1)
;   +6: p2_or  (OR value for Plane 2)
;   +8: p3_or  (OR value for Plane 3)
;
; Indexed by line type:
;   0 = Wave Line 0 (crest tips, OpaqueMask = $1C1C)
;   1 = Wave Line 1 (foam & highlight, OpaqueMask = $3E3E)
;   2 = Wave Line 2 (full wave contour, OpaqueMask = $FFFF)
;   3 = Wave Line 3 (wave base highlight, OpaqueMask = $FFFF)
;   4 = Wave Line 4 / Solid Blue Tile (Tile 115 fill, OpaqueMask = $FFFF)
;==============================================================================

WaterWaveTable_Even:
    ; Line 0 (EVEN scanline, dither mask $AAAA)
    dc.w    $f7f7, $0808, $0808, $0000, $0808
    ; Line 1 (EVEN scanline, dither mask $AAAA)
    dc.w    $d5d5, $2a2a, $2a2a, $0000, $2222
    ; Line 2 (EVEN scanline, dither mask $AAAA)
    dc.w    $5555, $aaaa, $a2a2, $0202, $8080
    ; Line 3 (EVEN scanline, dither mask $AAAA)
    dc.w    $5555, $aaaa, $8080, $0000, $0000
    ; Line 4 / Solid Blue Fill (EVEN scanline, dither mask $AAAA)
    dc.w    $5555, $aaaa, $0000, $0000, $0000

WaterWaveTable_Odd:
    ; Line 0 (ODD scanline, dither mask $5555)
    dc.w    $ebeb, $1414, $1414, $0000, $1414
    ; Line 1 (ODD scanline, dither mask $5555)
    dc.w    $ebeb, $1414, $1414, $0404, $0000
    ; Line 2 (ODD scanline, dither mask $5555)
    dc.w    $aaaa, $5555, $4141, $0000, $4141
    ; Line 3 (ODD scanline, dither mask $5555)
    dc.w    $aaaa, $5555, $4141, $0000, $0000
    ; Line 4 / Solid Blue Fill (ODD scanline, dither mask $5555)
    dc.w    $aaaa, $5555, $0000, $0000, $0000


;==============================================================================
; TilemapApplyWaveScanline  -  Apply wave graphic line or solid blue fill
;
; Arguments:
;   d0.w = scanline Y within the 688px level (0..LEVEL_SCREEN_HEIGHT-1)
;   d6.w = line type (0..4):
;          0 = Wave Line 0 (crest tips)
;          1 = Wave Line 1 (foam & highlight)
;          2 = Wave Line 2 (full wave contour)
;          3 = Wave Line 3 (wave base highlight)
;          4 = Solid Blue Tile fill (Line 4 / Tile 115)
;
; Applies cookie-cut semi-transparency directly to both NonDisplayScreen
; and DisplayScreen:
;   (PlaneX & not_m) | px_or
; Preserves all pristine background bits on non-dithered checkerboard pixels.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapApplyWaveScanline:
    PUSHM       d0-d7/a0-a2

    ; Bounds check Y (0..LEVEL_SCREEN_HEIGHT-1)
    cmp.w       #0,d0
    blt.s       .exit
    cmp.w       #LEVEL_SCREEN_HEIGHT,d0
    bge.s       .exit

    ; Select table based on scanline parity (even / odd)
    btst        #0,d0
    bne.s       .odd_line
    lea         WaterWaveTable_Even(pc),a2
    bra.s       .table_ready
.odd_line:
    lea         WaterWaveTable_Odd(pc),a2
.table_ready:

    ; Table entry offset = line type * 10 bytes (5 words: not_m, p0, p1, p2, p3)
    mulu.w      #10,d6
    adda.w      d6,a2

    move.w      (a2)+,d1                ; d1 = not_m (AND mask)
    move.w      (a2)+,d2                ; d2 = p0_or (Plane 0 OR value)
    move.w      (a2)+,d3                ; d3 = p1_or (Plane 1 OR value)
    move.w      (a2)+,d4                ; d4 = p2_or (Plane 2 OR value)
    move.w      (a2)+,d5                ; d5 = p3_or (Plane 3 OR value)

    ; Calculate scanline byte offset = Y * 160
    mulu.w      #TILEMAP_LINE_STRIDE,d0 ; d0 = Y * 160

    ; Apply to NonDisplayScreen (background save buffer)
    lea         NonDisplayScreen,a0
    adda.l      d0,a0
    bsr.s       .apply_scanline

    ; Apply to DisplayScreen (active framebuffer)
    lea         DisplayScreen,a0
    adda.l      d0,a0
    bsr.s       .apply_scanline

.exit:
    POPM        d0-d7/a0-a2
    rts

.apply_scanline:
    ; a0 -> start of scanline (Plane 0, 20 words = 40 bytes)
    ; Fast path for solid blue fill (Planes 1..3 OR values all zero)
    move.w      d3,d7
    or.w        d4,d7
    or.w        d5,d7
    bne.s       .generic_wave_line

    ; Fast path for Solid Blue Fill (Line 4 / Tile 115):
    ; Plane 0: OR with d2 (20 words)
    moveq       #20-1,d7
.blue_p0:
    or.w        d2,(a0)+
    dbra        d7,.blue_p0

    ; Planes 1, 2, 3: AND with d1 (60 words)
    moveq       #60-1,d7
.blue_p123:
    and.w       d1,(a0)+
    dbra        d7,.blue_p123
    rts

.generic_wave_line:
    ; Generic cookie-cut for wave lines 0..3:
    ; Plane 0 (20 words)
    moveq       #20-1,d7
.p0_loop:
    and.w       d1,(a0)
    or.w        d2,(a0)+
    dbra        d7,.p0_loop

    ; Plane 1 (20 words)
    moveq       #20-1,d7
.p1_loop:
    and.w       d1,(a0)
    or.w        d3,(a0)+
    dbra        d7,.p1_loop

    ; Plane 2 (20 words)
    moveq       #20-1,d7
.p2_loop:
    and.w       d1,(a0)
    or.w        d4,(a0)+
    dbra        d7,.p2_loop

    ; Plane 3 (20 words)
    moveq       #20-1,d7
.p3_loop:
    and.w       d1,(a0)
    or.w        d5,(a0)+
    dbra        d7,.p3_loop
    rts


;==============================================================================
; TilemapSubmergeScanline  -  Convenience wrapper for Solid Blue Tile submersion
;
; Arguments:
;   d0.w = scanline Y within the 688px level (0..LEVEL_SCREEN_HEIGHT-1)
;==============================================================================

TilemapSubmergeScanline:
    PUSHM       d6
    moveq       #4,d6                   ; line type 4 = solid blue fill
    bsr         TilemapApplyWaveScanline
    POPM        d6
    rts


;==============================================================================
; TilemapSubmergeActor  -  Apply wave surface graphic or solid blue stipple
;
; Called by TilemapDrawPlayer and TilemapDrawEnemySubPixel to submerge an actor.
; For scanlines WaterPixelY + 0..3, applies the wave crest profile from
; WaterWaveTable_Even / WaterWaveTable_Odd so the wave flows seamlessly across
; the actor with no straight-line cutoff.
; For scanlines >= WaterPixelY + 4, applies 50% solid blue dither.
;
; In:
;   a0   = Pointer to destination Plane 0 in DisplayScreen (Y * 160 + col * 2)
;   d0.w = Actor X coordinate (to test alignment: andi.w #15)
;   d1.w = Actor top scanline Y
;   d2.w = WaterPixelY
;   d7.w = Actor height in scanlines (e.g. PLAYER_HEIGHT or ENEMY_FRAME_HEIGHT)
;
; Preserves:
;   All caller registers (pushes d0-d7/a0-a3)
;==============================================================================

TilemapSubmergeActor:
    PUSHM       d0-d7/a0-a3

    ; Check if water is active
    tst.w       d2                      ; WaterPixelY
    bmi         .exit                   ; if < 0, no water!

    ; Check if actor is completely above water
    move.w      d1,d3                   ; d3 = actor top Y
    add.w       d7,d3
    subq.w      #1,d3                   ; d3 = actor bottom Y
    cmp.w       d2,d3                   ; compare bottom Y with WaterPixelY
    blt         .exit                   ; if bottom < WaterPixelY, completely dry!

    WAITBLIT                            ; ensure blitter has finished drawing actor BOB

    ; Check actor type and shift width:
    cmp.w       #PLAYER_HEIGHT,d7
    beq.s       .player_submerge

    ; Enemy / 16px Actor:
    andi.w      #15,d0
    bne         .submerge_2words
    bra.s       .submerge_1word

.player_submerge:
    ; Player / 24px BOB:
    cmp.w       #288,d0
    bge         .submerge_2words
    andi.w      #15,d0
    bne         .submerge_3words
    bra         .submerge_2words

.submerge_1word:
    ; -------------------------------------------------------------------------
    ; 1-Word Aligned Submersion (16px span)
    ; -------------------------------------------------------------------------
    subq.w      #1,d7                   ; for dbra
.loop_1w:
    cmp.w       d2,d1                   ; scanline Y >= WaterPixelY?
    blt         .next_line_1w           ; if not, dry scanline!

    ; Calculate line offset from water top: d6 = d1 - d2
    move.w      d1,d6
    sub.w       d2,d6                   ; d6 = 0, 1, 2, 3, 4, ...
    cmp.w       #4,d6
    bge.s       .solid_blue_1w          ; d6 >= 4 -> solid blue water body

    ; Wave crest profile (d6 = 0..3):
    btst        #0,d1
    bne.s       .odd_table_1w
    lea         WaterWaveTable_Even(pc),a1
    bra.s       .table_ready_1w
.odd_table_1w:
    lea         WaterWaveTable_Odd(pc),a1
.table_ready_1w:
    ; Table entry offset = d6 * 10
    lsl.w       #1,d6                   ; d6 * 2
    move.w      d6,d3
    lsl.w       #2,d6                   ; d6 * 8
    add.w       d3,d6                   ; d6 * 10
    adda.w      d6,a1

    move.w      (a1)+,d3                ; d3 = not_m
    move.w      (a1)+,d4                ; d4 = p0_or
    move.w      (a1)+,d5                ; d5 = p1_or
    move.w      (a1)+,d6                ; d6 = p2_or

    ; Plane 0:
    and.w       d3,(a0)
    or.w        d4,(a0)
    ; Plane 1:
    and.w       d3,40(a0)
    or.w        d5,40(a0)
    ; Plane 2:
    and.w       d3,80(a0)
    or.w        d6,80(a0)
    ; Plane 3:
    move.w      (a1),d4                 ; d4 = p3_or
    and.w       d3,120(a0)
    or.w        d4,120(a0)
    bra.s       .next_line_1w

.solid_blue_1w:
    btst        #0,d1
    bne.s       .odd_solid_1w
    ; EVEN scanline: Plane 0 OR $AAAA, Planes 1..3 AND $5555
    or.w        #$aaaa,(a0)
    and.w       #$5555,40(a0)
    and.w       #$5555,80(a0)
    and.w       #$5555,120(a0)
    bra.s       .next_line_1w

.odd_solid_1w:
    ; ODD scanline: Plane 0 OR $5555, Planes 1..3 AND $AAAA
    or.w        #$5555,(a0)
    and.w       #$aaaa,40(a0)
    and.w       #$aaaa,80(a0)
    and.w       #$aaaa,120(a0)

.next_line_1w:
    addq.w      #1,d1                   ; next scanline Y
    lea         TILEMAP_LINE_STRIDE(a0),a0 ; next scanline in DisplayScreen (+160)
    dbra        d7,.loop_1w
    bra         .exit

    ; -------------------------------------------------------------------------
    ; 2-Word Shifted Submersion (32px span)
    ; -------------------------------------------------------------------------
.submerge_2words:
    subq.w      #1,d7                   ; for dbra
.loop_2w:
    cmp.w       d2,d1                   ; scanline Y >= WaterPixelY?
    blt         .next_line_2w

    move.w      d1,d6
    sub.w       d2,d6                   ; d6 = 0, 1, 2, 3, 4, ...
    cmp.w       #4,d6
    bge.s       .solid_blue_2w

    ; Wave crest profile (d6 = 0..3):
    btst        #0,d1
    bne.s       .odd_table_2w
    lea         WaterWaveTable_Even(pc),a1
    bra.s       .table_ready_2w
.odd_table_2w:
    lea         WaterWaveTable_Odd(pc),a1
.table_ready_2w:
    lsl.w       #1,d6                   ; d6 * 2
    move.w      d6,d3
    lsl.w       #2,d6                   ; d6 * 8
    add.w       d3,d6                   ; d6 * 10
    adda.w      d6,a1

    move.w      (a1)+,d3                ; d3 = not_m
    move.w      (a1)+,d4                ; d4 = p0_or
    move.w      (a1)+,d5                ; d5 = p1_or
    move.w      (a1)+,d6                ; d6 = p2_or

    ; Plane 0:
    and.w       d3,(a0)
    or.w        d4,(a0)
    and.w       d3,2(a0)
    or.w        d4,2(a0)
    ; Plane 1:
    and.w       d3,40(a0)
    or.w        d5,40(a0)
    and.w       d3,42(a0)
    or.w        d5,42(a0)
    ; Plane 2:
    and.w       d3,80(a0)
    or.w        d6,80(a0)
    and.w       d3,82(a0)
    or.w        d6,82(a0)
    ; Plane 3:
    move.w      (a1),d4                 ; d4 = p3_or
    and.w       d3,120(a0)
    or.w        d4,120(a0)
    and.w       d3,122(a0)
    or.w        d4,122(a0)
    bra.s       .next_line_2w

.solid_blue_2w:
    btst        #0,d1
    bne.s       .odd_solid_2w
    ; EVEN scanline
    or.w        #$aaaa,(a0)
    or.w        #$aaaa,2(a0)
    and.w       #$5555,40(a0)
    and.w       #$5555,42(a0)
    and.w       #$5555,80(a0)
    and.w       #$5555,82(a0)
    and.w       #$5555,120(a0)
    and.w       #$5555,122(a0)
    bra.s       .next_line_2w

.odd_solid_2w:
    ; ODD scanline
    or.w        #$5555,(a0)
    or.w        #$5555,2(a0)
    and.w       #$aaaa,40(a0)
    and.w       #$aaaa,42(a0)
    and.w       #$aaaa,80(a0)
    and.w       #$aaaa,82(a0)
    and.w       #$aaaa,120(a0)
    and.w       #$aaaa,122(a0)

.next_line_2w:
    addq.w      #1,d1
    lea         TILEMAP_LINE_STRIDE(a0),a0
    dbra        d7,.loop_2w
    bra         .exit

    ; -------------------------------------------------------------------------
    ; 3-Word Shifted Submersion (48px span for 24px Player BOB)
    ; -------------------------------------------------------------------------
.submerge_3words:
    subq.w      #1,d7                   ; for dbra
.loop_3w:
    cmp.w       d2,d1                   ; scanline Y >= WaterPixelY?
    blt         .next_line_3w

    move.w      d1,d6
    sub.w       d2,d6                   ; d6 = 0, 1, 2, 3, 4, ...
    cmp.w       #4,d6
    bge         .solid_blue_3w

    ; Wave crest profile (d6 = 0..3):
    btst        #0,d1
    bne.s       .odd_table_3w
    lea         WaterWaveTable_Even(pc),a1
    bra.s       .table_ready_3w
.odd_table_3w:
    lea         WaterWaveTable_Odd(pc),a1
.table_ready_3w:
    lsl.w       #1,d6                   ; d6 * 2
    move.w      d6,d3
    lsl.w       #2,d6                   ; d6 * 8
    add.w       d3,d6                   ; d6 * 10
    adda.w      d6,a1

    move.w      (a1)+,d3                ; d3 = not_m
    move.w      (a1)+,d4                ; d4 = p0_or
    move.w      (a1)+,d5                ; d5 = p1_or
    move.w      (a1)+,d6                ; d6 = p2_or

    ; Plane 0:
    and.w       d3,(a0)
    or.w        d4,(a0)
    and.w       d3,2(a0)
    or.w        d4,2(a0)
    and.w       d3,4(a0)
    or.w        d4,4(a0)
    ; Plane 1:
    and.w       d3,40(a0)
    or.w        d5,40(a0)
    and.w       d3,42(a0)
    or.w        d5,42(a0)
    and.w       d3,44(a0)
    or.w        d5,44(a0)
    ; Plane 2:
    and.w       d3,80(a0)
    or.w        d6,80(a0)
    and.w       d3,82(a0)
    or.w        d6,82(a0)
    and.w       d3,84(a0)
    or.w        d6,84(a0)
    ; Plane 3:
    move.w      (a1),d4                 ; d4 = p3_or
    and.w       d3,120(a0)
    or.w        d4,120(a0)
    and.w       d3,122(a0)
    or.w        d4,122(a0)
    and.w       d3,124(a0)
    or.w        d4,124(a0)
    bra         .next_line_3w

.solid_blue_3w:
    btst        #0,d1
    bne.s       .odd_solid_3w
    ; EVEN scanline
    or.w        #$aaaa,(a0)
    or.w        #$aaaa,2(a0)
    or.w        #$aaaa,4(a0)
    and.w       #$5555,40(a0)
    and.w       #$5555,42(a0)
    and.w       #$5555,44(a0)
    and.w       #$5555,80(a0)
    and.w       #$5555,82(a0)
    and.w       #$5555,84(a0)
    and.w       #$5555,120(a0)
    and.w       #$5555,122(a0)
    and.w       #$5555,124(a0)
    bra.s       .next_line_3w

.odd_solid_3w:
    ; ODD scanline
    or.w        #$5555,(a0)
    or.w        #$5555,2(a0)
    or.w        #$5555,4(a0)
    and.w       #$aaaa,40(a0)
    and.w       #$aaaa,42(a0)
    and.w       #$aaaa,44(a0)
    and.w       #$aaaa,80(a0)
    and.w       #$aaaa,82(a0)
    and.w       #$aaaa,84(a0)
    and.w       #$aaaa,120(a0)
    and.w       #$aaaa,122(a0)
    and.w       #$aaaa,124(a0)

.next_line_3w:
    addq.w      #1,d1
    lea         TILEMAP_LINE_STRIDE(a0),a0
    dbra        d7,.loop_3w

.exit:
    POPM        d0-d7/a0-a3
    rts


;==============================================================================
; TilemapUpdateWater  -  Advance rising water layer upwards
;
; Called every frame from GameRun in gamestatus.asm.
; Overall movement: 16 pixels every 10 seconds.
; Advances WATER_STEP_PIXELS (1 or 2 pixels) per step.
;
; Each step:
;   1. Decrements WaterPixelY by WATER_STEP_PIXELS.
;   2. Advances the first 5 pixel rows together as the wave graphic:
;      - Scanline Y + 0: Wave Line 0 (crest tips)
;      - Scanline Y + 1: Wave Line 1 (foam & highlight)
;      - Scanline Y + 2: Wave Line 2 (full wave contour)
;      - Scanline Y + 3: Wave Line 3 (wave base highlight)
;      - Scanline Y + 4: Wave Line 4 (solid blue body)
;   3. Overwrites the prior location lines vacated by the wave with
;      solid blue water (Tile 115 fill) at scanline Y + 5.
;   4. When crossing into a new tile row (WaterPixelY >> 4 != WaterCurrentRow):
;      Updates WaterCurrentRow and updates LiveWaterMap tile data.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapUpdateWater:
    ; If no water or water has reached the ceiling (scanline 0), do nothing
    move.w      WaterPixelY(a5),d0
    ble         .exit

    ; -------------------------------------------------------------------------
    ; 1. Advance Fractional Sub-Pixel Frame Accumulator
    ; -------------------------------------------------------------------------
    ; At 50Hz PAL, water rises at exactly 16 pixels per 10 seconds (500 frames).
    ; We add 16 to WaterSubTick every frame.
    ; When accumulator reaches WaterRisePeriod * WATER_STEP_PIXELS, one pixel step triggers.
    move.w      WaterSubTick(a5),d0
    add.w       #16,d0
    move.w      WaterRisePeriod(a5),d1
    IFNE        WATER_STEP_PIXELS-1
    mulu.w      #WATER_STEP_PIXELS,d1
    ENDC
    cmp.w       d1,d0
    blt         .store_subtick          ; period not yet reached: store remainder and exit

    ; Step interval elapsed! Subtract threshold and store fractional remainder
    sub.w       d1,d0
    move.w      d0,WaterSubTick(a5)

    PUSHM       d0-d7/a0-a2

    ; -------------------------------------------------------------------------
    ; 2. Advance Water Scanline Upwards
    ; -------------------------------------------------------------------------
    subq.w      #WATER_STEP_PIXELS,WaterPixelY(a5) ; decrement Y (advances up towards top of screen)
    move.w      WaterPixelY(a5),d0      ; d0 = new top scanline of water surface

    ; -------------------------------------------------------------------------
    ; 3. Render 5-Scanline Moving Wave Graphic onto Playfield
    ; -------------------------------------------------------------------------
    ; The animated waterline consists of 5 distinct wave profile rows:
    ;   Scanline Y + 0: Wave Line 0 (crest tips - semi-transparent highlights)
    move.w      d0,-(sp)
    moveq       #0,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ;   Scanline Y + 1: Wave Line 1 (foam & light cyan highlights)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #1,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ;   Scanline Y + 2: Wave Line 2 (full wave contour)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #2,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ;   Scanline Y + 3: Wave Line 3 (wave base transition)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #3,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ;   Scanline Y + 4: Wave Line 4 (solid blue water body)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #4,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; -------------------------------------------------------------------------
    ; 4. Backfill Lines Vacated by the Rising Wave
    ; -------------------------------------------------------------------------
    ; As the wave moves up by WATER_STEP_PIXELS, scanline Y+5 (and any subsequent
    ; step lines) are overwritten with solid blue water (type 4 fill) so no
    ; visual gaps or previous wave crests remain.
    moveq       #WATER_STEP_PIXELS-1,d5
.fill_prior_lines:
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #4,d6                   ; line type 4 = solid blue water fill
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0
    dbra        d5,.fill_prior_lines

    ; -------------------------------------------------------------------------
    ; 5. Tile Row Boundary Crossing Check
    ; -------------------------------------------------------------------------
    ; When WaterPixelY crosses a 16-pixel tile boundary (WaterPixelY >> 4 != WaterCurrentRow),
    ; update the live water tile layer in LiveWaterMap so tile-based collision,
    ; background rendering, and rewinding stay synchronized.
    move.w      WaterPixelY(a5),d1
    lsr.w       #4,d1                   ; d1 = current tile row (WaterPixelY >> 4)
    cmp.w       WaterCurrentRow(a5),d1
    beq.s       .pop_exit               ; still within same tile row: done!

    ; We crossed into a new tile row!
    move.w      d1,WaterCurrentRow(a5)

    ; Update LiveWaterMap: row d1 becomes surface water (tile 104),
    ; row d1+1 becomes deep water (tile 115).
    lea         LiveWaterMap(a5),a0
    addq.l      #8,a0                   ; skip 8-byte map header
    move.w      d1,d2
    mulu.w      #TILEMAP_MAP_WIDTH*2,d2
    lea         (a0,d2.w),a1            ; a1 -> row d1 in LiveWaterMap

    move.w      #TILEMAP_MAP_WIDTH-1,d3
    move.w      #WATER_TILE_SURFACE,d4  ; tile 104 (surface wave)
.fill_surface:
    move.w      d4,(a1)+
    dbra        d3,.fill_surface

    move.w      #TILEMAP_MAP_WIDTH-1,d3
    move.w      #WATER_TILE_DEEP,d4     ; tile 115 (deep solid water)
.fill_deep:
    move.w      d4,(a1)+
    dbra        d3,.fill_deep

.pop_exit:
    POPM        d0-d7/a0-a2
    rts

.store_subtick:
    move.w      d0,WaterSubTick(a5)
.exit:
    rts


;==============================================================================
; TilemapRedrawRows  -  Redraw all map layers for a specific row range
;
; In:
;   a0   = destination screen buffer base in Chip RAM (e.g. NonDisplayScreen)
;   d0.w = StartRow (0..41)
;   d1.w = EndRow (0..41)
;
; Preserves: all caller registers (pushes d0-d7/a0-a4)
;==============================================================================

TilemapRedrawRows:
    PUSHM       d2-d7/a0-a4

    move.w      d0,d2                   ; d2 = StartRow (preserved across calls)
    move.w      d1,d3                   ; d3 = EndRow   (preserved across calls)
    move.l      a0,a4                   ; a4 = destination buffer base (preserved)

    move.l      CurrentLevelDef(a5),d0
    beq         .legacy_layers
    movea.l     d0,a2

    move.w      LevelDef_LayerCount(a2),d7
    beq         .fallback_layers
    move.l      LevelDef_LayerList(a2),d6
    beq         .fallback_layers

    subq.w      #1,d7

.layer_loop:
    movea.l     d6,a1
    move.l      (a1)+,d0
    move.l      a1,d6
    tst.l       d0
    beq.s       .skip_layer

    movea.l     d0,a2                   ; a2 = map pointer
    move.l      a4,a0                   ; a0 = destination buffer
    move.w      d2,d0                   ; StartRow
    move.w      d3,d1                   ; EndRow
    bsr         TilemapDrawLayerRows

.skip_layer:
    dbra        d7,.layer_loop

    POPM        d2-d7/a0-a4
    rts

.fallback_layers:
    move.l      LevelDef_BackgroundMap(a2),d0
    beq.s       .no_bg
    movea.l     d0,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
.no_bg:
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_PlatformMap(a2),d0
    beq.s       .no_plat
    movea.l     d0,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
.no_plat:

    ; --- Pass 2.25: Render Ladder Layer ---
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_LadderMap(a2),d0
    beq.s       .no_ladder
    movea.l     d0,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
.no_ladder:

    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_ForegroundMap(a2),d0
    beq.s       .no_fg
    movea.l     d0,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
.no_fg:
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_WaterMap(a2),d0
    beq.s       .no_water
    movea.l     d0,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
.no_water:
    POPM        d2-d7/a0-a4
    rts

.legacy_layers:
    lea         Level_01_PlatformMap,a2
    move.l      a4,a0
    move.w      d2,d0
    move.w      d3,d1
    bsr         TilemapDrawLayerRows
    POPM        d2-d7/a0-a4
    rts


;==============================================================================
; TilemapRewindWater  -  Restore dried out screen rows and reapply wave graphic
;
; In:
;   d0.w = OldY (WaterPixelY before undo)
;   d1.w = RestoredY (Snap_WaterPixelY from snapshot)
;
; If RestoredY > OldY, water moved downwards (scanlines OldY..RestoredY dried out).
; Restores pristine background in NonDisplayScreen for affected tile rows,
; reapplies wave crest at RestoredY and solid blue underneath, and cleans LiveWaterMap.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapRewindWater:
    PUSHM       d0-d7/a0-a4

    ; If no water in level (RestoredY < 0 or OldY < 0), exit
    tst.w       d1
    bmi         .rewind_done
    tst.w       d0
    bmi         .rewind_done

    ; If water did not rise (RestoredY <= OldY), no rows dried out
    cmp.w       d0,d1
    ble         .rewind_done

    move.w      d1,d5                   ; d5 = RestoredY (preserve across calls)

    ; StartRow = OldY >> 4
    move.w      d0,d2
    lsr.w       #4,d2
    bpl.s       .start_ok
    moveq       #0,d2
.start_ok:

    ; EndRow = (RestoredY + 4) >> 4
    move.w      d5,d3
    addq.w      #4,d3
    lsr.w       #4,d3
    move.w      CurrentMapHeight(a5),d1
    subq.w      #1,d1
    cmp.w       d1,d3
    ble.s       .end_ok
    move.w      d1,d3
.end_ok:

    cmp.w       d2,d3
    blt         .rewind_done

    ; Step 1: Zero-fill rows d2..d3 in NonDisplayScreen
    move.w      d2,d4
    mulu.w      #TILEMAP_ROW_STRIDE,d4  ; StartRow * 2560
    lea         NonDisplayScreen,a0
    adda.l      d4,a0

    move.w      d3,d7
    sub.w       d2,d7
    addq.w      #1,d7
    mulu.w      #TILEMAP_ROW_STRIDE,d7  ; (EndRow - StartRow + 1) * 2560
    bsr         TurboClear

    ; Step 2: Redraw all map layers in NonDisplayScreen for rows d2..d3
    lea         NonDisplayScreen,a0
    move.w      d2,d0                   ; StartRow
    move.w      d3,d1                   ; EndRow
    bsr         TilemapRedrawRows

    ; Step 3: Reapply wave at RestoredY (d5) down to bottom of EndRow (d3)
    move.w      d5,d0                   ; scanline RestoredY
    moveq       #0,d6                   ; Wave Line 0 (crest tips)
    bsr         TilemapApplyWaveScanline

    addq.w      #1,d0
    moveq       #1,d6                   ; Wave Line 1 (foam)
    bsr         TilemapApplyWaveScanline

    addq.w      #1,d0
    moveq       #2,d6                   ; Wave Line 2 (contour)
    bsr         TilemapApplyWaveScanline

    addq.w      #1,d0
    moveq       #3,d6                   ; Wave Line 3 (base highlight)
    bsr         TilemapApplyWaveScanline

    addq.w      #1,d0                   ; RestoredY + 4

    ; Calculate EndScanline = (EndRow + 1) * 16 - 1
    move.w      d3,d4
    addq.w      #1,d4
    lsl.w       #4,d4
    subq.w      #1,d4
    cmp.w       #LEVEL_SCREEN_HEIGHT-1,d4
    ble.s       .scan_end_ok
    move.w      #LEVEL_SCREEN_HEIGHT-1,d4
.scan_end_ok:

.fill_blue_loop:
    cmp.w       d4,d0
    bgt.s       .fill_blue_done
    moveq       #4,d6                   ; Line 4 (solid blue)
    bsr         TilemapApplyWaveScanline
    addq.w      #1,d0
    bra.s       .fill_blue_loop
.fill_blue_done:

    ; Step 4: Synchronize LiveWaterMap
    move.w      d5,d6                   ; RestoredY
    lsr.w       #4,d6                   ; d6 = RestoredRow
    cmp.w       d2,d6                   ; RestoredRow vs StartRow
    ble.s       .set_restored_surface

    ; Clear rows d2 up to d6 - 1
    lea         LiveWaterMap(a5),a1
    addq.l      #8,a1
    move.w      d2,d4
    mulu.w      #TILEMAP_MAP_WIDTH*2,d4
    adda.w      d4,a1

    move.w      d6,d7
    sub.w       d2,d7
    mulu.w      #TILEMAP_MAP_WIDTH,d7   ; total words
    subq.w      #1,d7
.clr_map_words:
    clr.w       (a1)+
    dbra        d7,.clr_map_words

.set_restored_surface:
    cmp.w       CurrentMapHeight(a5),d6
    bge.s       .rewind_done
    lea         LiveWaterMap(a5),a1
    addq.l      #8,a1
    move.w      d6,d4
    mulu.w      #TILEMAP_MAP_WIDTH*2,d4
    adda.w      d4,a1

    move.w      #TILEMAP_MAP_WIDTH-1,d7
    move.w      #WATER_TILE_SURFACE,d4
.set_surface_words:
    move.w      d4,(a1)+
    dbra        d7,.set_surface_words

.rewind_done:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapDrawEnemies  -  Blit all enemies over the screen buffer
;
; Arguments:
;   a0 = destination screen buffer base in Chip RAM
;
; Reads enemy definitions from LevelDef_EnemyList (or Level_01_EnemyList)
; and blits each enemy into its tile position on top of the background & platforms.
;==============================================================================

;==============================================================================
; TilemapEraseEnemies  -  Restore pristine background under all previous enemy blits
;
; Must be called at the start of each frame alongside TilemapErasePlayer,
; BEFORE any BOBs (player or enemy) are drawn.  This ensures that erasing an
; enemy never wipes out a player that was already drawn onto DisplayScreen.
;
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

TilemapEraseEnemies:
    PUSHM       d0-d7/a0-a4

    move.w      ActiveEnemyCount(a5),d7
    beq.s       .done_erase_enemies
    subq.w      #1,d7
    lea         ActiveEnemies(a5),a4    ; a4 = current ActiveEnemy pointer

.erase_loop:
    tst.w       ei_Drawn(a4)
    beq.s       .next_erase
    bsr         TilemapEraseEnemy
    clr.w       ei_Drawn(a4)
.next_erase:
    lea         ei_SIZEOF(a4),a4
    dbra        d7,.erase_loop

.done_erase_enemies:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapUpdateEnemies  -  Per-frame dynamic enemy update & sub-pixel blit
;
; Sequence:
;   1. Update patrol movement: ei_X += ei_Direction * ei_Speed
;      Bounce against [ei_PatrolMinX .. ei_PatrolMaxX] and invert direction.
;   2. Advance animation frame every 8 frames (0..3).
;   3. If within visible camera window, blit using sub-pixel barrel shifter (BLTCON0 shift).
;      Uses cookie-cutter mask ($0FCA) to draw cleanly over background and player!
;
; Note: Erasing previous enemy footprints is handled by TilemapEraseEnemies
; at the start of the frame BEFORE TilemapDrawPlayer.
;
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

TilemapUpdateEnemies:
    PUSHM       d0-d7/a0-a4

    move.w      ActiveEnemyCount(a5),d7
    beq         .done_update_enemies
    subq.w      #1,d7
    lea         ActiveEnemies(a5),a4

.update_draw_loop:
    tst.w       ei_Type(a4)
    beq         .next_update_draw

    ; Check if stunned: halt in tracks and maintain current pose
    tst.w       ei_StunTimer(a4)
    beq.s       .not_stunned
    subq.w      #1,ei_StunTimer(a4)     ; tick down stun duration
    bra.s       .check_enemy_vis        ; skip movement and frame advance

.not_stunned:
    ; Step 1: Update Movement & Patrol Turnaround
    move.w      ei_Direction(a4),d0     ; +1 or -1
    muls.w      ei_Speed(a4),d0         ; delta X
    add.w       d0,ei_X(a4)

    ; Check Right Bound (PatrolMaxX)
    move.w      ei_X(a4),d1
    cmp.w       ei_PatrolMaxX(a4),d1
    blt.s       .check_left_bound
    move.w      ei_PatrolMaxX(a4),ei_X(a4)
    move.w      #-1,ei_Direction(a4)    ; turn left
    bra.s       .update_anim

.check_left_bound:
    cmp.w       ei_PatrolMinX(a4),d1
    bgt.s       .update_anim
    move.w      ei_PatrolMinX(a4),ei_X(a4)
    move.w      #1,ei_Direction(a4)     ; turn right

.update_anim:
    ; Step 3: Animate Frame (every 8 frames)
    move.w      TickCounter(a5),d0
    andi.w      #7,d0
    bne.s       .check_enemy_vis
    addq.w      #1,ei_AnimFrame(a4)
    andi.w      #3,ei_AnimFrame(a4)

.check_enemy_vis:
    ; Viewport Y culling: check if enemy is in active display rows
    move.w      ei_Y(a4),d1
    cmp.w       CameraCullTopY(a5),d1
    blt.s       .enemy_offscreen
    cmp.w       CameraCullBottomY(a5),d1
    ble.s       .draw_current_enemy

.enemy_offscreen:
    ; Enemy is offscreen: if still drawn from previous camera position, erase once
    tst.w       ei_Drawn(a4)
    beq         .next_update_draw
    bsr         TilemapEraseEnemy
    clr.w       ei_Drawn(a4)
    bra         .next_update_draw

.draw_current_enemy:
    ; Erase previous enemy footprint immediately before drawing new frame
    tst.w       ei_Drawn(a4)
    beq.s       .check_entities_new
    bsr         TilemapEraseEnemy
    clr.w       ei_Drawn(a4)

    ; Re-blit any entity objects (push block, friend, oxygen) overlapping previous or new tiles
    move.w      ei_Y(a4),d1
    lsr.w       #4,d1                   ; d1 = Row

    ; start_col = min(ei_PrevX, ei_X) >> 4
    move.w      ei_PrevX(a4),d2
    cmp.w       ei_X(a4),d2
    ble.s       .col_min_ok
    move.w      ei_X(a4),d2
.col_min_ok:
    lsr.w       #4,d2                   ; d2 = start_col

    ; end_col = max(ei_PrevX + 15, ei_X + 15) >> 4
    move.w      ei_PrevX(a4),d3
    cmp.w       ei_X(a4),d3
    bge.s       .col_max_ok
    move.w      ei_X(a4),d3
.col_max_ok:
    add.w       #15,d3
    lsr.w       #4,d3                   ; d3 = end_col

.restore_entity_loop:
    cmp.w       d3,d2
    bgt.s       .check_player_overlap
    move.w      d2,d0                   ; d0 = Col
    bsr         TilemapRestoreTileEntities
    addq.w      #1,d2
    bra.s       .restore_entity_loop

.check_entities_new:
    ; Enemy was not drawn last frame, check current position only
    move.w      ei_Y(a4),d1
    lsr.w       #4,d1                   ; d1 = Row
    move.w      ei_X(a4),d2
    lsr.w       #4,d2                   ; d2 = start_col
    move.w      ei_X(a4),d3
    add.w       #15,d3
    lsr.w       #4,d3                   ; d3 = end_col
    bra.s       .restore_entity_loop

.check_player_overlap:
    ; If this enemy's footprint overlaps the player BOB, re-blit the player
    ; so the player is intact underneath before the enemy cookie-cuts on top!
    lea         Player(a5),a2
    tst.w       Player_Status(a2)
    beq.s       .do_draw_enemy
    tst.w       Player_PrevDrawn(a2)
    beq.s       .do_draw_enemy

    ; Check X overlap: (ex_left <= px_right) and (ex_right >= px_left)
    move.w      Player_PrevX(a2),d0     ; px_left
    move.w      d0,d1
    add.w       #23,d1                  ; px_right = px_left + 23

    ; ex_left = min(ei_X, ei_PrevX)
    move.w      ei_X(a4),d2
    cmp.w       ei_PrevX(a4),d2
    ble.s       .ex_left_ok
    move.w      ei_PrevX(a4),d2
.ex_left_ok:
    cmp.w       d1,d2                   ; ex_left > px_right?
    bgt.s       .do_draw_enemy

    ; ex_right = max(ei_X, ei_PrevX) + 15
    move.w      ei_X(a4),d3
    cmp.w       ei_PrevX(a4),d3
    bge.s       .ex_right_ok
    move.w      ei_PrevX(a4),d3
.ex_right_ok:
    add.w       #15,d3                  ; ex_right
    cmp.w       d0,d3                   ; ex_right < px_left?
    blt.s       .do_draw_enemy

    ; Check Y overlap: (ey_top <= py_bottom) and (ey_bottom >= py_top)
    move.w      Player_PrevY(a2),d0     ; py_top
    move.w      d0,d1
    add.w       #23,d1                  ; py_bottom = py_top + 23

    move.w      ei_Y(a4),d2             ; ey_top
    cmp.w       d1,d2                   ; ey_top > py_bottom?
    bgt.s       .do_draw_enemy

    move.w      d2,d3
    add.w       #15,d3                  ; ey_bottom
    cmp.w       d0,d3                   ; ey_bottom < py_top?
    blt.s       .do_draw_enemy

    ; Overlap detected! Re-blit player with cookie-cutter mask ($0FCA)
    movem.l     d7/a4,-(sp)             ; preserve enemy loop counter d7 and enemy pointer a4
    movea.l     a2,a4                   ; a4 -> Player struct
    bsr         TilemapDrawPlayer       ; re-draw player cleanly
    movem.l     (sp)+,d7/a4             ; restore enemy pointer and loop counter

.do_draw_enemy:
    ; Step 4: Draw Enemy with Sub-Pixel Shifter (if in visible viewport)
    bsr         TilemapDrawEnemySubPixel

.next_update_draw:
    lea         ei_SIZEOF(a4),a4
    dbra        d7,.update_draw_loop

.done_update_enemies:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapSubmergeTile  -  Apply water submersion to a 16x16 tile if submerged
;
; In:  d0.w = Col (0..19)
;      d1.w = Row (0..41)
;      a5   = Variables base
;      a6   = CUSTOM ($dff000)
; Preserves: all caller registers (pushes d0-d7/a0-a3 if water active)
;==============================================================================
TilemapSubmergeTile:
    PUSHM       d0-d7/a0-a3

    move.w      WaterPixelY(a5),d2
    bmi.s       .tst_dry
    move.w      d1,d4
    lsl.w       #4,d4                   ; d4 = pixel Y (top of tile)
    move.w      d4,d3
    add.w       #15,d3                  ; d3 = bottom pixel Y of tile
    cmp.w       d2,d3
    blt.s       .tst_dry                ; bottom < WaterPixelY -> completely dry

    move.w      d0,d5
    lsl.w       #4,d5                   ; d5 = pixel X (col * 16)
    move.w      d5,d0                   ; d0 = pixel X (aligned)
    move.w      d4,d1                   ; d1 = pixel Y

    move.w      d1,d6
    mulu.w      #TILEMAP_LINE_STRIDE,d6
    move.w      d0,d5
    lsr.w       #4,d5
    add.w       d5,d5                   ; byte column
    add.l       d5,d6
    lea         DisplayScreen,a0
    adda.l      d6,a0                   ; a0 = dest pointer in DisplayScreen

    move.w      #16,d7                  ; 16 scanlines
    bsr         TilemapSubmergeActor

.tst_dry:
    POPM        d0-d7/a0-a3
    rts


;==============================================================================
; TilemapRestoreTileEntities  -  Re-blit any entity object overlapping (Col, Row)
;
; When an actor (such as an enemy) erases its footprint using NonDisplayScreen,
; any entity object (push block crate, animal friend, oxygen refill) sharing
; that tile has its pixels wiped back to pristine background.
; This routine checks if (Col, Row) hosts an entity object and re-blits it
; using its cookie-cutter MASK into DisplayScreen before the enemy is drawn.
;
; Arguments:
;   d0.w = Col (0..19)
;   d1.w = Row (0..41)
;   a5   = Variables base
;   a6   = CUSTOM ($dff000)
; Preserves: all registers (PUSHM / POPM d0-d7/a0-a4)
;==============================================================================
TilemapRestoreTileEntities:
    cmp.w       #0,d0
    blt         .rte_exit
    cmp.w       #TILEMAP_VIEW_COLS,d0
    bge         .rte_exit
    cmp.w       #0,d1
    blt         .rte_exit
    cmp.w       CurrentMapHeight(a5),d1
    bge         .rte_exit

    PUSHM       d0-d7/a0-a4

    ; Early out: if no actors, oxygen, or friends in the level, exit immediately
    move.w      ActorCount(a5),d5
    or.w        ActiveOxygenCount(a5),d5
    or.w        ActiveFriendCount(a5),d5
    beq         .rte_done

    move.w      d0,d6                   ; d6 = target Col
    move.w      d1,d7                   ; d7 = target Row

    ; -------------------------------------------------------------------------
    ; 1. Check Settled Push Blocks (Crates)
    ; -------------------------------------------------------------------------
    move.w      ActorCount(a5),d5
    beq         .rte_check_oxygen

    ; Early-out GameMap guard: if player is not actively pushing, check GameMap cell
    cmp.w       #ACTION_PLAYERPUSH,ActionStatus(a5)
    beq.s       .rte_scan_crates

    ; Fast cell offset: (Row * 20) + Col
    move.w      d7,d0
    lsl.w       #4,d0                   ; Row * 16
    move.w      d7,d1
    lsl.w       #2,d1                   ; Row * 4
    add.w       d1,d0                   ; Row * 20
    add.w       d6,d0                   ; Row * 20 + Col
    lea         GameMap(a5),a0
    move.b      (a0,d0.w),d0
    cmp.b       #BLOCK_PUSH,d0
    bne.s       .rte_check_oxygen       ; cell has no push block!

.rte_scan_crates:
    subq.w      #1,d5
    lea         ActorList(a5),a2
.rte_crate_loop:
    move.l      (a2)+,a3
    tst.w       Actor_Status(a3)
    beq.s       .rte_next_crate
    move.w      Actor_Type(a3),d4
    cmp.w       #BLOCK_PUSH,d4
    bne.s       .rte_next_crate
.rte_is_crate:
    tst.w       Actor_HasFalled(a3)
    bne.s       .rte_next_crate

    tst.w       Actor_HasMoved(a3)
    beq.s       .rte_crate_static

    ; Moving crate (being pushed):
    cmp.w       Actor_Y(a3),d7
    bne.s       .rte_next_crate
    cmp.w       Actor_X(a3),d6
    beq.s       .rte_draw_moving_crate
    cmp.w       Actor_PrevX(a3),d6
    bne.s       .rte_next_crate

.rte_draw_moving_crate:
    bsr         DrawActor
    bra.s       .rte_check_oxygen

.rte_crate_static:
    cmp.w       Actor_X(a3),d6
    bne.s       .rte_next_crate
    cmp.w       Actor_Y(a3),d7
    bne.s       .rte_next_crate

    ; Match! Blit crate with cookie-cutter mask ($0FCA)
    move.w      Actor_SpriteOffset(a3),d0
    move.w      d7,d2                   ; Row
    move.w      d6,d3                   ; Col
    bsr         TilemapBlitSingleTile
    move.w      d6,d0
    lsl.w       #4,d0
    move.w      d7,d1
    lsl.w       #4,d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox
    move.w      d6,d0
    move.w      d7,d1
    bsr         TilemapSubmergeTile
    bra.s       .rte_check_oxygen       ; continue checking other layers

.rte_next_crate:
    dbra        d5,.rte_crate_loop

    ; -------------------------------------------------------------------------
    ; 2. Check Oxygen Pickups
    ; -------------------------------------------------------------------------
.rte_check_oxygen:
    move.w      ActiveOxygenCount(a5),d5
    beq.s       .rte_check_friends
    subq.w      #1,d5
    lea         ActiveOxygen(a5),a4
.rte_oxygen_loop:
    tst.w       ox_Collected(a4)
    bne.s       .rte_next_oxygen
    cmp.w       ox_Col(a4),d6
    bne.s       .rte_next_oxygen
    cmp.w       ox_Row(a4),d7
    bne.s       .rte_next_oxygen

    ; Match! Blit oxygen bottle with cookie-cutter mask ($0FCA)
    move.w      ox_TileId(a4),d0
    move.w      d7,d2                   ; Row
    move.w      d6,d3                   ; Col
    bsr         TilemapBlitSingleTile
    move.w      #1,ox_Drawn(a4)
    move.w      d6,d0
    lsl.w       #4,d0
    move.w      d7,d1
    lsl.w       #4,d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox
    move.w      d6,d0
    move.w      d7,d1
    bsr         TilemapSubmergeTile
    bra.s       .rte_check_friends

.rte_next_oxygen:
    lea         ox_SIZEOF(a4),a4
    dbra        d5,.rte_oxygen_loop

    ; -------------------------------------------------------------------------
    ; 3. Check Animal Friends
    ; -------------------------------------------------------------------------
.rte_check_friends:
    move.w      ActiveFriendCount(a5),d5
    beq.s       .rte_done
    subq.w      #1,d5
    lea         ActiveFriends(a5),a4
.rte_friend_loop:
    tst.w       fi_Type(a4)
    beq.s       .rte_next_friend
    tst.w       fi_Rescued(a4)
    bne.s       .rte_next_friend

    ; Check if friend tile matches (d6, d7)
    move.w      fi_X(a4),d0
    lsr.w       #4,d0
    cmp.w       d0,d6
    bne.s       .rte_next_friend
    move.w      fi_Y(a4),d1
    lsr.w       #4,d1
    cmp.w       d1,d7
    bne.s       .rte_next_friend

    ; Match! Blit friend with cookie-cutter mask ($0FCA)
    bsr         TilemapDrawFriendSubPixel
    move.w      #1,fi_Drawn(a4)
    bra.s       .rte_done

.rte_next_friend:
    lea         fi_SIZEOF(a4),a4
    dbra        d5,.rte_friend_loop

.rte_done:
    POPM        d0-d7/a0-a4

.rte_exit:
    rts


;==============================================================================
; TilemapEraseEnemy  -  Restore pristine background under previous enemy blit
;
; In: a4 = ActiveEnemy pointer
; Destroys: d0-d4, a0-a2
;==============================================================================

TilemapEraseEnemy:
    move.w      ei_PrevX(a4),d0
    move.w      ei_PrevY(a4),d1

    ; Screen byte offset in 4-plane interleaved = (Y * 160) + ((X / 16) * 2)
    mulu.w      #TILEMAP_LINE_STRIDE,d1
    moveq       #0,d2
    move.w      d0,d2
    lsr.w       #4,d2
    add.w       d2,d2                   ; byte column
    add.l       d2,d1

    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1
    adda.l      d1,a0                   ; source (pristine background)
    adda.l      d1,a1                   ; dest (active display)

    ; Check if X is word-aligned (d0 & 15 == 0) -> 1 word wide, else 2 words wide
    and.w       #15,d0
    beq.s       .erase_1word

    ; 2-word wide restore (32px span across bitplanes)
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)      ; D = A (direct copy)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-4,BLTAMOD(a6) ; 40 - 4 = 36 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6) ; 40 - 4 = 36 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(ENEMY_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|2,BLTSIZE(a6) ; 64 lines x 2 words
    rts

.erase_1word:
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)      ; D = A
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-2,BLTAMOD(a6) ; 40 - 2 = 38 bytes
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6) ; 40 - 2 = 38 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(ENEMY_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|1,BLTSIZE(a6) ; 64 lines x 1 word
    rts


;==============================================================================
; TilemapDrawEnemySubPixel  -  Cookie-cut blit with sub-pixel horizontal shift
;
; Blits a 16x16 pixel enemy BOB onto DisplayScreen with:
;   - Sub-pixel horizontal positioning via blitter barrel shifter (BLTCON0/1 shift bits)
;   - Camera viewport culling (8px headroom beyond the 216-scanline window)
;   - Dynamic animation cel selection (4 frames per enemy type, 512 bytes per type row)
;   - Stun recovery warning strobe (white flash during final 1.5s / 75 frames of stun)
;   - Cookie-cutter minterm $0FCA masking over screen background
;   - Animated dizzy stars halo when stunned
;   - Dynamic water submersion tinting if reached by rising floodwaters
;
; In:  a4 = ActiveEnemy pointer
;      a5 = Variables base
;      a6 = CUSTOM chip base ($dff000)
; Destroys: d0-d5, a0-a3
;==============================================================================

TilemapDrawEnemySubPixel:
    move.w      ei_X(a4),d0             ; 0..319
    move.w      ei_Y(a4),d1             ; 0..671

    ; -------------------------------------------------------------------------
    ; 1. Bounding Box & Viewport Culling
    ; -------------------------------------------------------------------------
    ; Horizontal bounds check: clamp to valid display columns (0 .. 320 - 16)
    cmp.w       #0,d0
    blt         .culled_enemy
    cmp.w       #320-16,d0
    bgt         .culled_enemy

    ; Absolute Level Y bounds check: 0 <= Y <= LEVEL_SCREEN_HEIGHT - ENEMY_FRAME_HEIGHT (688 - 16 = 672)
    cmp.w       #0,d1
    blt         .culled_enemy
    cmp.w       #LEVEL_SCREEN_HEIGHT-ENEMY_FRAME_HEIGHT,d1
    bgt         .culled_enemy

    ; Viewport Y culling: CameraY - 24 <= Y <= CameraY + 224
    ; Extended by 8 pixels beyond the top (CameraY) and bottom (CameraY + 216) display edges
    ; so 16px enemies are completely off-screen before being removed.
    move.w      TilemapCameraY(a5),d2
    sub.w       #24,d2                  ; d2 = CameraY - 24 (8px headroom above 16px frame)
    cmp.w       d2,d1
    blt         .culled_enemy
    add.w       #248,d2                 ; d2 = (CameraY - 24) + 248 = CameraY + 224 (8px headroom below 216-line viewport)
    cmp.w       d2,d1
    bgt         .culled_enemy

    ; -------------------------------------------------------------------------
    ; 2. Source Frame Pointer Calculation
    ; -------------------------------------------------------------------------
    ; Enemy sprite sheet layout:
    ;   - 8 enemy types (ei_Type 1..8) stacked vertically
    ;   - 4 animation frames per type (ei_AnimFrame 0..3) across each row
    ;   - Each cel is 16px wide (2 bytes) x 16 scanlines x 4 bitplanes interleaved
    ;   - Cel size = 16 lines * (2 bytes * 4 planes = 8 bytes/line) = 128 bytes
    ;   - Row stride = 4 cels * 128 bytes = 512 bytes (ENEMY_ROW_STRIDE)
    ; Source offset = (Type - 1) * ENEMY_ROW_STRIDE + (AnimFrame * 2 bytes)
    move.w      ei_Type(a4),d2
    subq.w      #1,d2                   ; 0..7
    mulu.w      #ENEMY_ROW_STRIDE,d2
    moveq       #0,d3
    move.w      ei_AnimFrame(a4),d3
    add.w       d3,d3                   ; d3 = AnimFrame * 2 bytes (word column in sheet)
    add.l       d3,d2

    lea         EnemySpritesMsk,a0      ; a0 = base of cookie-cutter mask sheet

    ; -------------------------------------------------------------------------
    ; 3. Stun Recovery Visual Warning Flash
    ; -------------------------------------------------------------------------
    ; When cane-struck, ei_StunTimer is set to ENEMY_STUN_DURATION (200 ticks = 4.0s).
    ; During the final 1.5 seconds (ENEMY_RECOVERY_FLASH_TICKS = 75 ticks),
    ; rapid strobe between normal sprite colors and solid white silhouette (EnemySpritesWhiteRaw)
    ; warns the player that the enemy's stun state is expiring!
    move.w      ei_StunTimer(a4),d4
    beq.s       .use_normal_raw         ; not stunned -> normal graphic
    cmp.w       #ENEMY_RECOVERY_FLASH_TICKS,d4
    bgt.s       .use_normal_raw         ; still early in stun duration -> normal graphic
    ; Final 1.5 seconds: flash rapidly between normal palette and pure white ($0FFF)
    btst        #2,d4                   ; alternate every 4 frames (~12.5 Hz strobe)
    beq.s       .use_normal_raw
    lea         EnemySpritesWhiteRaw,a1 ; pure white silhouette buffer
    bra.s       .source_ready
.use_normal_raw:
    lea         EnemySpritesRaw,a1      ; standard colored enemy sprite sheet
.source_ready:
    adda.l      d2,a0                   ; a0 = mask frame source pointer
    adda.l      d2,a1                   ; a1 = raw graphic frame source pointer

    ; -------------------------------------------------------------------------
    ; 4. Destination Address Calculation
    ; -------------------------------------------------------------------------
    ; Interleaved DisplayScreen line stride = 160 bytes (4 planes * 40 bytes/plane).
    ; Dest offset = (Y * 160) + ((X >> 4) << 1)
    move.w      d1,d2
    mulu.w      #TILEMAP_LINE_STRIDE,d2
    moveq       #0,d3
    move.w      d0,d3
    lsr.w       #4,d3
    add.w       d3,d3                   ; byte column
    add.l       d3,d2

    lea         DisplayScreen,a2
    adda.l      d2,a2                   ; a2 = dest address in DisplayScreen

    ; -------------------------------------------------------------------------
    ; 5. Blitter Execution: Minterm $0FCA Cookie-Cutter
    ; -------------------------------------------------------------------------
    ; D = (A AND B) OR ((NOT A) AND C)
    ;   Channel A: Mask (EnemySpritesMsk)
    ;   Channel B: Graphic (EnemySpritesRaw / EnemySpritesWhiteRaw)
    ;   Channel C: Screen background
    ;   Channel D: Screen output
    ; Barrel shifter:
    ;   Shift = X & 15.
    move.w      d0,d3
    andi.w      #15,d3                  ; d3 = shift (0..15)
    beq.s       .blit_aligned

    ; --- Shifted Blit (2 words wide, 32px output span) ---
    ; BLTCON0 = (Shift << 12) | $0FCA (USEA|USEB|USEC|USED, minterm $CA)
    ; BLTCON1 = (Shift << 12)
    ; BLTAFWM = $FFFF, BLTALWM = $0000
    ; Setting BLTALWM to $0000 masks Word 2 of Channel A to 0 before the shifter,
    ; ensuring no bits from adjacent sprite sheet frames leak in, while Word 1's
    ; shifted bits pass through to Word 2 cleanly.
    ; A/B Modulo = 8 - 4 = 4 bytes (Source is 64px = 8 bytes wide)
    ; C/D Modulo = 40 - 4 = 36 bytes (Screen is 320px = 40 bytes wide)
    lsl.w       #8,d3
    lsl.w       #4,d3                   ; d3 = Shift << 12
    move.w      d3,d4
    ori.w       #$0fca,d3               ; d3 = BLTCON0

    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      d4,BLTCON1(a6)
    move.l      #$ffff0000,BLTAFWM(a6)  ; BLTAFWM = $ffff, BLTALWM = $0000

    move.w      #ENEMY_SHEET_BYTES-4,BLTAMOD(a6) ; 8 - 4 = 4 bytes
    move.w      #ENEMY_SHEET_BYTES-4,BLTBMOD(a6) ; 8 - 4 = 4 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6) ; 40 - 4 = 36 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6) ; 40 - 4 = 36 bytes

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Screen background
    move.l      a2,BLTDPT(a6)           ; Screen result

    ; Height = 16 scanlines * 4 bitplanes = 64 lines, Width = 2 words
    move.w      #(ENEMY_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|2,BLTSIZE(a6)
    bra.s       .record_drawn

.blit_aligned:
    ; -------------------------------------------------------------------------
    ; Word-Aligned Blit (1 word wide, 16px output span):
    ; Shift = 0: exactly 1 word fits on 16-pixel tile boundary.
    ; BLTCON0 = $0FCA, BLTCON1 = $0000
    ; BLTAFWM = $FFFF, BLTALWM = $FFFF
    ; A/B Modulo = 8 - 2 = 6 bytes
    ; C/D Modulo = 40 - 2 = 38 bytes
    ; -------------------------------------------------------------------------
    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)

    move.w      #ENEMY_SHEET_BYTES-2,BLTAMOD(a6) ; 8 - 2 = 6 bytes
    move.w      #ENEMY_SHEET_BYTES-2,BLTBMOD(a6) ; 8 - 2 = 6 bytes
    move.w      #SCREEN_WIDTH_BYTE-2,BLTCMOD(a6) ; 40 - 2 = 38 bytes
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6) ; 40 - 2 = 38 bytes

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Screen background
    move.l      a2,BLTDPT(a6)           ; Screen result

    ; Height = 64 lines, Width = 1 word
    move.w      #(ENEMY_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|1,BLTSIZE(a6)

.record_drawn:
    ; Record previous coordinates so TilemapEraseEnemy can cleanly restore background next frame
    move.w      d0,ei_PrevX(a4)
    move.w      d1,ei_PrevY(a4)
    move.w      #1,ei_Drawn(a4)

    ; -------------------------------------------------------------------------
    ; 6. Stun Dizzy Stars Overlay
    ; -------------------------------------------------------------------------
    ; If enemy is stunned, render an animated spinning halo of stars directly
    ; over the enemy's head.
    tst.w       ei_StunTimer(a4)
    beq.s       .check_submerge
    bsr         TilemapDrawDizzyStars

.check_submerge:
    ; -------------------------------------------------------------------------
    ; 7. Water Submersion Check
    ; -------------------------------------------------------------------------
    ; Submerge enemy in DisplayScreen if rising floodwaters have reached its scanlines.
    move.w      WaterPixelY(a5),d2      ; d2 = WaterPixelY
    bmi.s       .exit_draw              ; if no water (< 0), done
    movea.l     a2,a0                   ; a0 = destination in DisplayScreen
    move.w      d7,-(sp)                ; preserve loop counter
    move.w      #ENEMY_FRAME_HEIGHT,d7  ; 16 scanlines
    bsr         TilemapSubmergeActor
    move.w      (sp)+,d7

.exit_draw:
    rts

.culled_enemy:
    clr.w       ei_Drawn(a4)            ; flag as off-screen (skip erase)
    rts


;==============================================================================
; TilemapDrawDizzyStars  -  Blit animated dizzy stars over stunned enemy
;
; Renders a rotating halo of sparkling stars above an enemy when stunned by the
; player's cane attack.
;
; Animation:
;   - 4-frame rotating star sequence (0..3), cycling every 4 frames (12.5 Hz).
;   - Uses cookie-cutter mask (DizzyStarsMsk) over screen background.
;   - Handles sub-pixel horizontal shifting matching the enemy's exact X coordinate.
;
; In: a2 = dest pointer in DisplayScreen (base of 16x16 enemy box)
;     d0 = World X (ei_X)
; Preserves: a2, a4, a5, a6
; Destroys: d0-d5, a0-a1, a3
;==============================================================================

TilemapDrawDizzyStars:
    WAITBLIT                            ; ensure previous enemy blit has finished
    PUSHM       d0-d5/a0-a3

    ; Select dizzy stars frame (0..3, advances every 4 ticks)
    move.w      TickCounter(a5),d3
    lsr.w       #2,d3                   ; divide frame counter by 4
    andi.w      #3,d3                   ; cycle 0..3
    add.w       d3,d3                   ; d3 = Frame * 2 bytes offset (word column)

    lea         DizzyStarsMsk,a0
    lea         DizzyStarsRaw,a1
    adda.w      d3,a0                   ; Mask source
    adda.w      d3,a1                   ; Graphic source

    ; Check barrel shift (X & 15)
    move.w      d0,d3
    andi.w      #15,d3
    beq.s       .dizzy_aligned

    ; --- Shifted Blit (2 words wide, 32px span) ---
    lsl.w       #8,d3
    lsl.w       #4,d3                   ; d3 = Shift << 12
    move.w      d3,d4
    ori.w       #$0fca,d3               ; BLTCON0

    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      d4,BLTCON1(a6)
    move.l      #$ffff0000,BLTAFWM(a6)  ; mask out adjacent frame bleed

    move.w      #DIZZY_STARS_SHEET_BYTES-4,BLTAMOD(a6) ; 8 - 4 = 4 bytes
    move.w      #DIZZY_STARS_SHEET_BYTES-4,BLTBMOD(a6) ; 8 - 4 = 4 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6)       ; 40 - 4 = 36 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6)       ; 40 - 4 = 36 bytes

    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTBPT(a6)
    move.l      a2,BLTCPT(a6)
    move.l      a2,BLTDPT(a6)

    move.w      #(DIZZY_STARS_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|2,BLTSIZE(a6)
    bra.s       .dizzy_done

.dizzy_aligned:
    ; --- Aligned Blit (1 word wide, 16px span) ---
    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)

    move.w      #DIZZY_STARS_SHEET_BYTES-2,BLTAMOD(a6) ; 8 - 2 = 6 bytes
    move.w      #DIZZY_STARS_SHEET_BYTES-2,BLTBMOD(a6) ; 8 - 2 = 6 bytes
    move.w      #SCREEN_WIDTH_BYTE-2,BLTCMOD(a6)       ; 40 - 2 = 38 bytes
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6)       ; 40 - 2 = 38 bytes

    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTBPT(a6)
    move.l      a2,BLTCPT(a6)
    move.l      a2,BLTDPT(a6)

    move.w      #(DIZZY_STARS_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|1,BLTSIZE(a6)

.dizzy_done:
    POPM        d0-d5/a0-a3
    rts


;==============================================================================
; TilemapEraseFriends  -  Erase all previously drawn animal friends
;
; Must be called at the start of each frame before any new actors or player
; are drawn onto DisplayScreen.
;
; In:  a5 = Variables base
;      a6 = CUSTOM chip base ($dff000)
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

;==============================================================================
; TilemapEraseOxygen  -  Restore pristine background under drawn oxygen refills
;
; In:  a5 = Variables base
;      a6 = CUSTOM chip base ($dff000)
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

TilemapEraseOxygen:
    PUSHM       d0-d7/a0-a4

    move.w      ActiveOxygenCount(a5),d7
    beq.s       .done_erase_oxygen
    subq.w      #1,d7
    lea         ActiveOxygen(a5),a4    ; a4 = current ActiveOxygen pointer

.erase_loop:
    tst.w       ox_Drawn(a4)
    beq.s       .next_erase
    move.w      ox_X(a4),d0
    move.w      ox_Y(a4),d1
    bsr         TilemapErase16x16Actor
    clr.w       ox_Drawn(a4)
.next_erase:
    lea         ox_SIZEOF(a4),a4
    dbra        d7,.erase_loop

.done_erase_oxygen:
    POPM        d0-d7/a0-a4
    rts


TilemapEraseFriends:
    PUSHM       d0-d7/a0-a4

    move.w      ActiveFriendCount(a5),d7
    beq.s       .done_erase_friends
    subq.w      #1,d7
    lea         ActiveFriends(a5),a4    ; a4 = current ActiveFriend pointer

.erase_loop:
    tst.w       fi_Drawn(a4)
    beq.s       .next_erase
    bsr         TilemapEraseFriend
    clr.w       fi_Drawn(a4)
.next_erase:
    lea         fi_SIZEOF(a4),a4
    dbra        d7,.erase_loop

.done_erase_friends:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapEraseFriend  -  Restore pristine background under previous friend blit
;
; In: a4 = ActiveFriend pointer
; Destroys: d0-d4, a0-a2
;==============================================================================

TilemapEraseFriend:
    move.w      fi_PrevX(a4),d0
    move.w      fi_PrevY(a4),d1

    ; Screen byte offset in 4-plane interleaved = (Y * 160) + ((X / 16) * 2)
    mulu.w      #TILEMAP_LINE_STRIDE,d1
    moveq       #0,d2
    move.w      d0,d2
    lsr.w       #4,d2
    add.w       d2,d2                   ; byte column
    add.l       d2,d1

    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1
    adda.l      d1,a0                   ; source (pristine background)
    adda.l      d1,a1                   ; dest (active display)

    ; Check if X is word-aligned (d0 & 15 == 0) -> 1 word wide, else 2 words wide
    and.w       #15,d0
    beq.s       .erase_1word

    ; 2-word wide restore (32px span across bitplanes)
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)      ; D = A (direct copy)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-4,BLTAMOD(a6) ; 40 - 4 = 36 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6) ; 40 - 4 = 36 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(FRIEND_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|2,BLTSIZE(a6) ; 64 lines x 2 words
    rts

.erase_1word:
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)      ; D = A
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-2,BLTAMOD(a6) ; 40 - 2 = 38 bytes
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6) ; 40 - 2 = 38 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(FRIEND_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|1,BLTSIZE(a6) ; 64 lines x 1 word
    rts


;==============================================================================
; TilemapUpdateFriends  -  Per-frame dynamic friend animation & blit
;
; Sequence:
;   1. Advance animation timer and cycle jumping frames (0..3).
;   2. If friend has not been rescued and is within visible camera window,
;      blit using sub-pixel shifter and cookie-cutter mask ($0FCA).
;
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

TilemapUpdateFriends:
    PUSHM       d0-d7/a0-a4

    move.w      ActiveFriendCount(a5),d7
    beq         .done_update_friends
    subq.w      #1,d7
    lea         ActiveFriends(a5),a4

.update_draw_loop:
    tst.w       fi_Type(a4)
    beq         .next_update_draw

    tst.w       fi_Rescued(a4)
    beq.s       .not_rescued

    ; Rescued: if still drawn on screen, erase once from DisplayScreen
    tst.w       fi_Drawn(a4)
    beq.s       .next_update_draw
    bsr         TilemapEraseFriend
    clr.w       fi_Drawn(a4)
    bra.s       .next_update_draw

.not_rescued:
    ; Viewport Y culling: check if friend is in active display rows
    move.w      fi_Y(a4),d1
    cmp.w       CameraCullTopY(a5),d1
    blt.s       .friend_offscreen
    cmp.w       CameraCullBottomY(a5),d1
    ble.s       .friend_on_screen

.friend_offscreen:
    ; Offscreen: if still drawn on screen from previous viewport, erase once
    tst.w       fi_Drawn(a4)
    beq.s       .next_update_draw
    bsr         TilemapEraseFriend
    clr.w       fi_Drawn(a4)
    bra.s       .next_update_draw

.friend_on_screen:
    ; Step 1: Advance Jumping Animation (every FRIEND_ANIM_SPEED frames)
    addq.w      #1,fi_AnimTimer(a4)
    cmp.w       #FRIEND_ANIM_SPEED,fi_AnimTimer(a4)
    blt.s       .check_drawn
    clr.w       fi_AnimTimer(a4)
    addq.w      #1,fi_AnimFrame(a4)
    andi.w      #3,fi_AnimFrame(a4)
    ; Animation frame changed: erase old frame before drawing new frame
    tst.w       fi_Drawn(a4)
    beq.s       .draw_current_friend
    bsr         TilemapEraseFriend
    clr.w       fi_Drawn(a4)
    bra.s       .draw_current_friend

.check_drawn:
    ; Animation frame unchanged: if already sitting on DisplayScreen, skip!
    tst.w       fi_Drawn(a4)
    bne.s       .next_update_draw

.draw_current_friend:
    bsr         TilemapDrawFriendSubPixel

.next_update_draw:
    lea         fi_SIZEOF(a4),a4
    dbra        d7,.update_draw_loop

.done_update_friends:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapDrawFriendSubPixel  -  Cookie-cut blit for animal friend (16x16)
;
; In: a4 = ActiveFriend pointer
; Destroys: d0-d5, a0-a3 (preserves d7)
;==============================================================================

TilemapDrawFriendSubPixel:
    move.w      fi_X(a4),d0             ; 0..319
    move.w      fi_Y(a4),d1             ; 0..671

    ; Horizontal bounds check: skip if X < 0 or X > 320 - 16
    cmp.w       #0,d0
    blt         .culled_friend
    cmp.w       #320-16,d0
    bgt         .culled_friend

    ; Absolute Level Y bounds check: 0 <= Y <= LEVEL_SCREEN_HEIGHT - FRIEND_FRAME_HEIGHT (688 - 16 = 672)
    cmp.w       #0,d1
    blt         .culled_friend
    cmp.w       #LEVEL_SCREEN_HEIGHT-FRIEND_FRAME_HEIGHT,d1
    bgt         .culled_friend

    ; Viewport Y culling: CameraY - 24 <= Y <= CameraY + 224 (8px headroom for 16px frame)
    move.w      TilemapCameraY(a5),d2
    sub.w       #24,d2                  ; d2 = CameraY - 24
    cmp.w       d2,d1
    blt         .culled_friend
    add.w       #248,d2                 ; d2 = CameraY + 224
    cmp.w       d2,d1
    bgt         .culled_friend

    ; Calculate source frame pointer in AnimalSpritesRaw / AnimalSpritesMsk:
    ; Source offset = (Type - 1) * FRIEND_ROW_STRIDE (512) + (AnimFrame * 2)
    move.w      fi_Type(a4),d2
    subq.w      #1,d2                   ; 0..4 (5 friend types)
    mulu.w      #FRIEND_ROW_STRIDE,d2
    moveq       #0,d3
    move.w      fi_AnimFrame(a4),d3
    add.w       d3,d3                   ; d3 = AnimFrame * 2 bytes
    add.l       d3,d2

    lea         AnimalSpritesMsk,a0
    lea         AnimalSpritesRaw,a1
    adda.l      d2,a0                   ; a0 = mask frame source
    adda.l      d2,a1                   ; a1 = raw graphic frame source

    ; Calculate destination screen address:
    ; Dest offset = (Y * 160) + ((X / 16) * 2)
    move.w      d1,d2
    mulu.w      #TILEMAP_LINE_STRIDE,d2
    moveq       #0,d3
    move.w      d0,d3
    lsr.w       #4,d3
    add.w       d3,d3                   ; byte column
    add.l       d3,d2

    lea         DisplayScreen,a2
    adda.l      d2,a2                   ; a2 = dest address in DisplayScreen

    ; Check barrel shift (X & 15)
    move.w      d0,d3
    andi.w      #15,d3                  ; d3 = shift (0..15)
    beq.s       .blit_aligned

    ; Shifted Blit (2 words wide, 32px output):
    lsl.w       #8,d3
    lsl.w       #4,d3                   ; d3 = Shift << 12
    move.w      d3,d4
    ori.w       #$0fca,d3               ; d3 = BLTCON0

    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      d4,BLTCON1(a6)
    move.l      #$ffff0000,BLTAFWM(a6)  ; BLTAFWM = $ffff, BLTALWM = $0000

    move.w      #FRIEND_SHEET_BYTES-4,BLTAMOD(a6) ; 8 - 4 = 4
    move.w      #FRIEND_SHEET_BYTES-4,BLTBMOD(a6) ; 8 - 4 = 4
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6)  ; 40 - 4 = 36
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6)  ; 40 - 4 = 36

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Screen background
    move.l      a2,BLTDPT(a6)           ; Screen result

    move.w      #(FRIEND_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|2,BLTSIZE(a6) ; 64 lines x 2 words
    bra.s       .record_drawn

.blit_aligned:
    ; -------------------------------------------------------------------------
    ; Word-Aligned Blit (1 word wide, 16px output):
    ; -------------------------------------------------------------------------
    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)

    move.w      #FRIEND_SHEET_BYTES-2,BLTAMOD(a6) ; 8 - 2 = 6
    move.w      #FRIEND_SHEET_BYTES-2,BLTBMOD(a6) ; 8 - 2 = 6
    move.w      #SCREEN_WIDTH_BYTE-2,BLTCMOD(a6)  ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6)  ; 40 - 2 = 38

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Screen background
    move.l      a2,BLTDPT(a6)           ; Screen result

    move.w      #(FRIEND_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|1,BLTSIZE(a6) ; 64 lines x 1 word

.record_drawn:
    move.w      d0,fi_PrevX(a4)
    move.w      d1,fi_PrevY(a4)
    move.w      #1,fi_Drawn(a4)

    ; Foreground Layer Stamp (in front of Friend BOB)
    ; Check if any foreground tiles in LevelDef_ForegroundMap overlap friend bounding box
    bsr         TilemapStampForegroundOverFriend

    ; Submerge friend in DisplayScreen if water has reached it
    move.w      WaterPixelY(a5),d2      ; d2 = WaterPixelY
    bmi.s       .exit_draw              ; if no water (< 0), done
    movea.l     a2,a0                   ; a0 = destination in DisplayScreen
    move.w      d7,-(sp)                ; preserve caller's loop counter
    move.w      #FRIEND_FRAME_HEIGHT,d7 ; 16 scanlines
    bsr         TilemapSubmergeActor
    move.w      (sp)+,d7

.exit_draw:
    rts

.culled_friend:
    clr.w       fi_Drawn(a4)
    rts


;==============================================================================
; TilemapErasePlayer  -  Restore background under previous player blit
;
; Fast, atomic 1-blit background restore from NonDisplayScreen to DisplayScreen.
; Records erased footprint parameters into Player_ErasedX/Y/Span/Flag for
; TilemapRestorePlayerOverlaps, but does NOT perform any entity restorations
; or nested loops, ensuring TilemapDrawPlayer can execute immediately in Early VBlank.
;
; In:  a4 = pointer to active Player struct
;      a5 = Variables base
;      a6 = CUSTOM chip base ($dff000)
; Destroys: d0-d2, a0-a1
;==============================================================================

TilemapErasePlayer:
    tst.w       Player_PrevDrawn(a4)
    beq         .no_erase               ; nothing drawn last frame, skip

    clr.w       Player_PrevDrawn(a4)    ; reset drawn flag

    PUSHM       d2-d3/a0-a1

    move.w      Player_PrevX(a4),d0
    move.w      Player_PrevY(a4),d1

    ; Save erased box parameters for TilemapRestorePlayerOverlaps
    move.w      d0,Player_ErasedX(a5)
    move.w      d1,Player_ErasedY(a5)
    move.w      #1,Player_ErasedFlag(a5)

    ; Screen byte offset = (Y * 160) + ((X / 16) * 2)
    mulu.w      #TILEMAP_LINE_STRIDE,d1 ; d1 = Y * 160
    moveq       #0,d2
    move.w      d0,d2
    lsr.w       #4,d2
    add.w       d2,d2                   ; byte column
    add.l       d2,d1

    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1
    adda.l      d1,a0                   ; a0 = pristine background source
    adda.l      d1,a1                   ; a1 = display screen destination

    ; Check if X was word-aligned (2 words) or shifted (3 words).
    ; Right edge (X >= 288) uses 2-word blit to prevent wrapping past byte 39.
    cmp.w       #288,d0
    bge.s       .erase_2word
    and.w       #15,d0
    beq.s       .erase_2word

    ; --- 3-Word Wide Restore (48px shifted) ---
    move.w      #48,Player_ErasedSpan(a5)
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)      ; D = A (direct copy)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-6,BLTAMOD(a6) ; 40 - 6 = 34 bytes
    move.w      #SCREEN_WIDTH_BYTE-6,BLTDMOD(a6) ; 40 - 6 = 34 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|3,BLTSIZE(a6) ; 96 rows x 3 words

    POPM        d2-d3/a0-a1
    rts

.erase_2word:
    ; --- 2-Word Wide Restore (32px aligned) ---
    move.w      #32,Player_ErasedSpan(a5)
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)      ; D = A
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-4,BLTAMOD(a6) ; 40 - 4 = 36 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6) ; 40 - 4 = 36 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|2,BLTSIZE(a6) ; 96 rows x 2 words

    POPM        d2-d3/a0-a1
    rts

.no_erase:
    clr.w       Player_ErasedFlag(a5)
    rts


;==============================================================================
; TilemapRestorePlayerOverlaps  -  Re-blit entities wiped by player's wide erase
;
; Called in Early VBlank immediately after TilemapDrawPlayer.
; Re-blits any settled push blocks (crates), moving push blocks,
; oxygen refills, or animal friends that occupied the background tiles
; restored by TilemapErasePlayer.
;
; In:  a5 = Variables base
;      a6 = CUSTOM chip base ($dff000)
; Preserves: all caller registers
;==============================================================================

TilemapRestorePlayerOverlaps:
    tst.w       Player_ErasedFlag(a5)
    beq         .rpo_exit

    clr.w       Player_ErasedFlag(a5)

    PUSHM       d2-d7/a2-a4
    subq.l      #8,sp                   ; allocate 8 bytes on stack for bounding box

    ; Calculate erased tile bounding box:
    ; (sp)   = start_col
    ; 2(sp)  = end_col
    ; 4(sp)  = start_row
    ; 6(sp)  = end_row

    move.w      Player_ErasedX(a5),d0
    lsr.w       #4,d0
    bpl.s       .scol_ok
    moveq       #0,d0
.scol_ok:
    move.w      d0,(sp)                 ; (sp) = start_col

    move.w      Player_ErasedX(a5),d0
    add.w       Player_ErasedSpan(a5),d0
    subq.w      #1,d0
    lsr.w       #4,d0                   ; end_col
    cmp.w       #TILEMAP_VIEW_COLS-1,d0
    ble.s       .ecol_ok
    move.w      #TILEMAP_VIEW_COLS-1,d0
.ecol_ok:
    move.w      d0,2(sp)                ; 2(sp) = end_col

    move.w      Player_ErasedY(a5),d1
    lsr.w       #4,d1                   ; start_row
    bpl.s       .srow_ok
    moveq       #0,d1
.srow_ok:
    move.w      d1,4(sp)                ; 4(sp) = start_row

    move.w      Player_ErasedY(a5),d1
    add.w       #PLAYER_HEIGHT-1,d1
    lsr.w       #4,d1                   ; end_row
    cmp.w       #TILEMAP_MAP_HEIGHT-1,d1
    ble.s       .erow_ok
    move.w      #TILEMAP_MAP_HEIGHT-1,d1
.erow_ok:
    move.w      d1,6(sp)                ; 6(sp) = end_row

    moveq       #0,d7                   ; d7 = flag (1 if any entity was restored)

    ; -------------------------------------------------------------------------
    ; 1. Check Push Blocks (Crates)
    ; -------------------------------------------------------------------------
    move.w      ActorCount(a5),d6
    beq         .rpo_check_oxygen
    subq.w      #1,d6
    lea         ActorList(a5),a2
.rpo_crate_loop:
    move.l      (a2)+,a3
    tst.w       Actor_Status(a3)
    beq         .rpo_next_crate
    move.w      Actor_Type(a3),d0
    cmp.w       #BLOCK_PUSH,d0
    bne         .rpo_next_crate
.rpo_is_crate:
    tst.w       Actor_HasFalled(a3)
    bne         .rpo_next_crate

    tst.w       Actor_HasMoved(a3)
    beq.s       .rpo_crate_static

    ; Moving crate (being pushed):
    move.w      Actor_Y(a3),d1
    cmp.w       4(sp),d1                ; < start_row?
    blt         .rpo_next_crate
    cmp.w       6(sp),d1                ; > end_row?
    bgt         .rpo_next_crate

    move.w      Actor_X(a3),d0
    cmp.w       (sp),d0                 ; >= start_col?
    blt.s       .rpo_check_prev_x
    cmp.w       2(sp),d0                ; <= end_col?
    ble.s       .rpo_draw_moving_crate
.rpo_check_prev_x:
    move.w      Actor_PrevX(a3),d0
    cmp.w       (sp),d0
    blt         .rpo_next_crate
    cmp.w       2(sp),d0
    bgt         .rpo_next_crate

.rpo_draw_moving_crate:
    bsr         DrawActor
    moveq       #1,d7
    bra         .rpo_next_crate

.rpo_crate_static:
    move.w      Actor_Y(a3),d1
    cmp.w       4(sp),d1
    blt         .rpo_next_crate
    cmp.w       6(sp),d1
    bgt         .rpo_next_crate

    move.w      Actor_X(a3),d0
    cmp.w       (sp),d0
    blt         .rpo_next_crate
    cmp.w       2(sp),d0
    bgt         .rpo_next_crate

    ; Match! Blit settled crate
    move.w      Actor_SpriteOffset(a3),d0
    move.w      Actor_Y(a3),d2
    move.w      Actor_X(a3),d3
    bsr         TilemapBlitSingleTile

    move.w      Actor_X(a3),d0
    lsl.w       #4,d0
    move.w      Actor_Y(a3),d1
    lsl.w       #4,d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox

    move.w      Actor_X(a3),d0
    move.w      Actor_Y(a3),d1
    bsr         TilemapSubmergeTile

    moveq       #1,d7

.rpo_next_crate:
    dbra        d6,.rpo_crate_loop

    ; -------------------------------------------------------------------------
    ; 2. Check Oxygen Pickups
    ; -------------------------------------------------------------------------
.rpo_check_oxygen:
    move.w      ActiveOxygenCount(a5),d6
    beq         .rpo_check_friends
    subq.w      #1,d6
    lea         ActiveOxygen(a5),a4
.rpo_oxygen_loop:
    tst.w       ox_Collected(a4)
    bne         .rpo_next_oxygen

    move.w      ox_Row(a4),d1
    cmp.w       4(sp),d1
    blt         .rpo_next_oxygen
    cmp.w       6(sp),d1
    bgt         .rpo_next_oxygen

    move.w      ox_Col(a4),d0
    cmp.w       (sp),d0
    blt         .rpo_next_oxygen
    cmp.w       2(sp),d0
    bgt         .rpo_next_oxygen

    ; Match! Blit oxygen bottle
    move.w      ox_TileId(a4),d0
    move.w      ox_Row(a4),d2
    move.w      ox_Col(a4),d3
    bsr         TilemapBlitSingleTile
    move.w      #1,ox_Drawn(a4)

    move.w      ox_X(a4),d0
    move.w      ox_Y(a4),d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox

    move.w      ox_Col(a4),d0
    move.w      ox_Row(a4),d1
    bsr         TilemapSubmergeTile

    moveq       #1,d7

.rpo_next_oxygen:
    lea         ox_SIZEOF(a4),a4
    dbra        d6,.rpo_oxygen_loop

    ; -------------------------------------------------------------------------
    ; 3. Check Animal Friends
    ; -------------------------------------------------------------------------
.rpo_check_friends:
    move.w      ActiveFriendCount(a5),d6
    beq         .rpo_done
    subq.w      #1,d6
    lea         ActiveFriends(a5),a4
.rpo_friend_loop:
    tst.w       fi_Type(a4)
    beq         .rpo_next_friend
    tst.w       fi_Rescued(a4)
    bne         .rpo_next_friend

    move.w      fi_Y(a4),d1
    lsr.w       #4,d1
    cmp.w       4(sp),d1
    blt         .rpo_next_friend
    cmp.w       6(sp),d1
    bgt         .rpo_next_friend

    move.w      fi_X(a4),d0
    lsr.w       #4,d0
    cmp.w       (sp),d0
    blt         .rpo_next_friend
    cmp.w       2(sp),d0
    bgt         .rpo_next_friend

    ; Match! Blit animal friend
    bsr         TilemapDrawFriendSubPixel
    move.w      #1,fi_Drawn(a4)
    moveq       #1,d7

.rpo_next_friend:
    lea         fi_SIZEOF(a4),a4
    dbra        d6,.rpo_friend_loop

.rpo_done:
    addq.l      #8,sp                   ; deallocate local stack bounding box
    POPM        d2-d7/a2-a4
.rpo_exit:
    rts


;==============================================================================
; TilemapDrawPlayer  -  Blit player BOB onto DisplayScreen with foreground & water depth
;
; Blits the 24x24 pixel player BOB onto the 4-bitplane interleaved DisplayScreen.
; Handles:
;   - Sub-pixel horizontal positioning and 8px vertical lift (centering 24px BOB on 16px tile)
;   - Dynamic bridge sag adjustment based on horizontal span traversal
;   - Viewport vertical culling against dynamic TilemapCameraY
;   - Cel address calculation: 4 columns x 6 rows interleaved graphic sheet (1536 bytes/row)
;   - Directional sprite selection: right-facing from ROM/Fast, left-facing pre-flipped in Chip RAM
;   - Post-respawn invulnerability visual feedback (rapid flashing white silhouette)
;   - Blitter cookie-cutter minterm $0FCA with barrel shifting (0..15 bits)
;   - Safe boundary clipping (switching from 3-word to 2-word blit at right edge X >= 288)
;   - Foreground tile re-stamping for multi-layer visual occlusion
;   - Partial/full water submersion tinting
;
; In:  a4 = pointer to active Player struct
;      a5 = Variables base
;      a6 = CUSTOM chip base ($dff000)
; Destroys: d0-d7, a0-a4
;==============================================================================

TilemapDrawPlayer:
    tst.w       Player_Status(a4)
    beq         .culled                 ; inactive player, do not draw

    ; -------------------------------------------------------------------------
    ; 1. Calculate World Pixel X: Player_X * 16 + Player_XDec
    ; -------------------------------------------------------------------------
    ; Active player graphics are 24 pixels wide, while map grid cells are 16 pixels.
    ; Subtracting 4 pixels centers the 24px BOB symmetrically over the 16px tile,
    ; leaving equal 4-pixel margins on both sides.
    move.w      Player_X(a4),d0
    lsl.w       #4,d0                   ; d0 = Player_X * 16
    add.w       Player_XDec(a4),d0      ; add sub-pixel interpolation offset (0..15)
    subq.w      #4,d0                   ; center 24px BOB over 16px tile
    bpl.s       .x_not_neg
    moveq       #0,d0                   ; clamp left edge to 0
.x_not_neg:
    cmp.w       #320-PLAYER_WIDTH,d0    ; clamp right edge so BOB does not exceed screen width
    ble.s       .x_not_past_right
    move.w      #320-PLAYER_WIDTH,d0
.x_not_past_right:

    ; -------------------------------------------------------------------------
    ; 2. Calculate World Pixel Y: Player_Y * 16 + Player_YDec - 8
    ; -------------------------------------------------------------------------
    ; With a 24-pixel tall BOB on a 16-pixel tile, subtracting 8 pixels lifts the
    ; BOB's head upward by 8 scanlines, ensuring the player's feet rest exactly flush
    ; on top of the supporting tile platform.
    move.w      Player_Y(a4),d1
    lsl.w       #4,d1                   ; d1 = Player_Y * 16
    add.w       Player_YDec(a4),d1      ; add sub-pixel vertical offset
    subq.w      #8,d1                   ; lift 8px: d1 = World Y (top scanline of 24px BOB)

    ; Adjust Y for bridge sag if traversing an elastic suspension bridge
    move.w      d1,-(sp)                ; preserve World Y
    move.w      d0,d1                   ; d1 = World X passed to GetBridgeYOffset
    bsr         GetBridgeYOffset        ; calculates downward deflection in d3 based on span position
    move.w      (sp)+,d1                ; restore World Y
    add.w       d3,d1                   ; apply bridge sag deflection

    ; -------------------------------------------------------------------------
    ; 3. Viewport Culling & Bounds Checks
    ; -------------------------------------------------------------------------
    ; Reject BOB if outside physical horizontal limits or beyond level world height.
    cmp.w       #0,d0
    blt         .culled
    cmp.w       #320-24,d0
    bgt         .culled
    cmp.w       #0,d1
    blt         .culled
    cmp.w       #LEVEL_SCREEN_HEIGHT-PLAYER_HEIGHT,d1
    bgt         .culled

    ; Vertical camera viewport culling:
    ; Visible display window spans 216 scanlines at TilemapCameraY.
    ; Allow 24 pixels of headroom above and below so BOB enters and exits smoothly
    ; without sudden pop-in or pop-out artifacts:
    ;   Accept if: (TilemapCameraY - 24) <= World_Y <= (TilemapCameraY + 240)
    move.w      TilemapCameraY(a5),d2
    sub.w       #PLAYER_HEIGHT,d2       ; d2 = CameraY - 24
    cmp.w       d2,d1
    blt         .culled                 ; off-screen above viewport
    add.w       #216+PLAYER_HEIGHT+24,d2 ; d2 = CameraY + 240 (bottom threshold)
    cmp.w       d2,d1
    bgt         .culled                 ; off-screen below viewport

    ; -------------------------------------------------------------------------
    ; 4. Calculate Source Frame Pointer in PlayerRaw / PlayerMsk
    ; -------------------------------------------------------------------------
    ; Frame index = Player_BobOffset + PlayerFrame (range 0..23).
    ; Cels are laid out in a grid of 4 columns across rows.
    ; Each cel is 32 pixels wide (4 bytes per bitplane) x 24 scanlines x 4 bitplanes interleaved.
    ; Interleaved line stride = 16 bytes per scanline (4 bytes x 4 bitplanes).
    ; Full cel height = 24 scanlines.
    ; Row stride = 24 scanlines * 16 bytes/line = 1536 bytes (PLAYER_FRAME_STRIDE).
    move.w      Player_BobOffset(a4),d2
    add.w       PlayerFrame(a5),d2      ; d2 = active cel index (0..23)

    ; Decompose index into Row = (Index / 4) and Col = (Index % 4):
    moveq       #0,d3
    move.w      d2,d3
    lsr.w       #2,d3                   ; d3 = cel row (d2 >> 2)
    mulu.w      #PLAYER_FRAME_STRIDE,d3 ; d3 = row byte offset (Row * 1536 bytes)

    moveq       #0,d4
    move.w      d2,d4
    andi.w      #3,d4                   ; d4 = cel column (0..3)
    lsl.w       #2,d4                   ; d4 = col * 4 bytes (32px cel = 4 bytes per bitplane line)
    add.l       d4,d3                   ; d3 = total source byte offset into sprite sheet

    ; Check facing direction:
    ; Ladder climbing animation is a rear-view perspective (never horizontally mirrored).
    tst.w       Player_OnLadder(a4)
    bne.s       .draw_right             ; ladder poses always use right/neutral orientation
    tst.w       Player_Facing(a4)       ; -1 = facing left, +1 = facing right
    bpl.s       .draw_right

    ; --- Facing Left: read pre-flipped sprite buffers in Chip RAM ---
    ; Mirrors were pre-computed at engine boot by PlayerInitFlippedSprites.
    lea         PlayerLeftMsk,a0
    tst.w       PlayerInvincibleTimer(a5) ; invulnerability active after respawn?
    beq.s       .left_normal
    btst        #2,TickCounter+1(a5)      ; flash every 4 frames (~12.5 Hz strobe)
    beq.s       .left_normal
    lea         PlayerLeftWhiteRaw,a1     ; pure white silhouette for damage/respawn strobe
    bra.s       .ptrs_ready
.left_normal:
    lea         PlayerLeftRaw,a1
    bra.s       .ptrs_ready

.draw_right:
    ; --- Facing Right: read active player sprite sheet ---
    movea.l     PlayerMskPtr(a5),a0
    tst.w       PlayerInvincibleTimer(a5)
    beq.s       .right_normal
    btst        #2,TickCounter+1(a5)      ; flash every 4 frames
    beq.s       .right_normal
    movea.l     PlayerWhitePtr(a5),a1     ; pure white silhouette
    bra.s       .ptrs_ready
.right_normal:
    movea.l     PlayerGfxPtr(a5),a1
.ptrs_ready:
    adda.l      d3,a0                   ; a0 = mask source pointer
    adda.l      d3,a1                   ; a1 = raw graphic source pointer

    ; -------------------------------------------------------------------------
    ; 5. Calculate Destination Screen Address
    ; -------------------------------------------------------------------------
    ; DisplayScreen is interleaved across 4 bitplanes:
    ;   Line stride = 40 bytes/plane * 4 planes = 160 bytes per raster scanline.
    ;   Screen byte column = (X / 16) * 2 bytes (word-aligned start).
    ;   Dest offset = (World_Y * 160) + ((World_X >> 4) << 1)
    move.w      d1,d2
    mulu.w      #TILEMAP_LINE_STRIDE,d2 ; d2 = Y * 160
    moveq       #0,d3
    move.w      d0,d3
    lsr.w       #4,d3                   ; d3 = X / 16
    add.w       d3,d3                   ; d3 = (X / 16) * 2
    add.l       d3,d2

    lea         DisplayScreen,a2
    adda.l      d2,a2                   ; a2 = destination pointer in DisplayScreen

    ; -------------------------------------------------------------------------
    ; 6. Blitter Configuration & Cookie-Cutter Execution
    ; -------------------------------------------------------------------------
    ; Minterm $0FCA logic: D = (A AND B) OR ((NOT A) AND C)
    ;   Channel A: Mask (cookie-cutter silhouette; 1 = sprite pixel, 0 = transparent)
    ;   Channel B: Graphic (sprite color bitplanes)
    ;   Channel C: Background (existing screen graphics)
    ;   Channel D: Destination (screen output)
    ;
    ; Barrel shifter:
    ;   Shift = World_X & 15 (sub-pixel bit offset).
    ;   BLTCON0 bits 15:12 = Shift for Channel A
    ;   BLTCON1 bits 15:12 = Shift for Channel B
    move.w      d0,d3
    andi.w      #15,d3                  ; shift = 0..15 pixels
    beq         .blit_aligned

    ; If at right screen margin (World_X >= 288, byte column 36), the BOB sits
    ; close to the right edge (byte 39). A 3-word blit would write a 3rd word
    ; into byte column 40-41, corrupting the subsequent scanline/plane.
    ; Switch to a 2-word blit (32px wide) which safely clips to screen edge.
    cmp.w       #288,d0
    bge.s       .blit_shifted_2word

    ; --- 3-Word Shifted Blit (48px output span) ---
    ; For shifts 1..15, a 2-word cel (32px) shifts across a 3-word boundary.
    ; Setting BLTALWM to $0000 in BLTAFWM ($FFFF0000) prevents the barrel shifter
    ; from leaking bits of adjacent horizontal cels into the 3rd word.
    lsl.w       #8,d3
    lsl.w       #4,d3                   ; d3 = Shift << 12
    move.w      d3,d4                   ; d4 = BLTCON1 value
    ori.w       #$0fca,d3               ; d3 = BLTCON0 value (USEA|USEB|USEC|USED, minterm $CA)

    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      d4,BLTCON1(a6)
    move.l      #$ffff0000,BLTAFWM(a6)  ; AFWM=$FFFF, ALWM=$0000 (clip cel boundary bleed)

    ; Modulos: Sheet is 16 bytes/line, blitting 3 words (6 bytes) -> Modulo = 16 - 6 = 10
    ; Screen is 40 bytes/line, blitting 3 words (6 bytes) -> Modulo = 40 - 6 = 34
    move.w      #PLAYER_SHEET_BYTES-6,BLTAMOD(a6) ; 16 - 6 = 10 bytes
    move.w      #PLAYER_SHEET_BYTES-6,BLTBMOD(a6) ; 16 - 6 = 10 bytes
    move.w      #SCREEN_WIDTH_BYTE-6,BLTCMOD(a6)  ; 40 - 6 = 34 bytes
    move.w      #SCREEN_WIDTH_BYTE-6,BLTDMOD(a6)  ; 40 - 6 = 34 bytes

    move.l      a0,BLTAPT(a6)           ; Channel A: Mask source
    move.l      a1,BLTBPT(a6)           ; Channel B: Graphic source
    move.l      a2,BLTCPT(a6)           ; Channel C: Screen background
    move.l      a2,BLTDPT(a6)           ; Channel D: Screen output

    ; Height = 24 scanlines * 4 bitplanes = 96 rows, Width = 3 words
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|3,BLTSIZE(a6)
    bra         .record_drawn

.blit_shifted_2word:
    ; --- 2-Word Shifted Blit (32px output span for right edge X >= 288) ---
    lsl.w       #8,d3
    lsl.w       #4,d3                   ; d3 = Shift << 12
    move.w      d3,d4
    ori.w       #$0fca,d3               ; BLTCON0

    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      d4,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)  ; AFWM=$FFFF, ALWM=$FFFF

    ; Modulos: 2 words = 4 bytes
    move.w      #PLAYER_SHEET_BYTES-4,BLTAMOD(a6) ; 16 - 4 = 12 bytes
    move.w      #PLAYER_SHEET_BYTES-4,BLTBMOD(a6) ; 16 - 4 = 12 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6)  ; 40 - 4 = 36 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6)  ; 40 - 4 = 36 bytes

    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTBPT(a6)
    move.l      a2,BLTCPT(a6)
    move.l      a2,BLTDPT(a6)

    ; Height = 96 rows, Width = 2 words
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|2,BLTSIZE(a6)
    bra         .record_drawn

.blit_aligned:
    ; --- 2-Word Aligned Blit (Shift = 0, exactly on word boundary) ---
    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)

    move.w      #PLAYER_SHEET_BYTES-4,BLTAMOD(a6) ; 16 - 4 = 12 bytes
    move.w      #PLAYER_SHEET_BYTES-4,BLTBMOD(a6) ; 16 - 4 = 12 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6)  ; 40 - 4 = 36 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6)  ; 40 - 4 = 36 bytes

    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTBPT(a6)
    move.l      a2,BLTCPT(a6)
    move.l      a2,BLTDPT(a6)

    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|2,BLTSIZE(a6)

.record_drawn:
    ; Cache drawn coordinates so TilemapErasePlayer can accurately restore background next frame
    move.w      d0,Player_PrevX(a4)
    move.w      d1,Player_PrevY(a4)
    move.w      #1,Player_PrevDrawn(a4)

    ; -------------------------------------------------------------------------
    ; 7. Foreground Layer Stamp (in front of Player BOB)
    ; -------------------------------------------------------------------------
    ; Re-blit any foreground tiles from LevelDef_ForegroundMap that overlap the
    ; player's bounding box to achieve layered depth (player walks behind foliage/pillars).
    bsr         TilemapStampForegroundOverPlayer

    ; -------------------------------------------------------------------------
    ; 8. Water Submersion Check
    ; -------------------------------------------------------------------------
    ; If the rising water level intersects the player's 24 scanlines, apply
    ; translucent water tinting/dimming to the submerged portion.
    move.w      WaterPixelY(a5),d2      ; d2 = WaterPixelY
    bmi.s       .exit                   ; if water is inactive (< 0), skip
    movea.l     a2,a0                   ; a0 = destination in DisplayScreen
    move.w      #PLAYER_HEIGHT,d7       ; 24 scanlines
    bsr         TilemapSubmergeActor

.exit:
    rts

.culled:
    clr.w       Player_PrevDrawn(a4)    ; flag as not drawn (no erase needed next frame)
    rts


;==============================================================================
; TilemapStampForegroundOverPlayer  -  Re-blit foreground tiles overlapping player
;
; In:  d0.w = Player World X (0..319)
;      d1.w = Player World Y (0..671)
;      a5   = Variables base
;      a6   = CUSTOM ($dff000)
; Preserves: all caller registers (pushes d0-d7/a0-a4)
;==============================================================================
TilemapStampForegroundOverPlayer:
    move.w      #PLAYER_WIDTH,d2
    move.w      #PLAYER_HEIGHT,d3
    bra.s       TilemapStampForegroundOverBox

;==============================================================================
; TilemapStampForegroundOverFriend  -  Re-blit foreground tiles overlapping friend
;
; In:  d0.w = Friend World X (0..319)
;      d1.w = Friend World Y (0..671)
;      a5   = Variables base
;      a6   = CUSTOM ($dff000)
; Preserves: all caller registers (pushes d0-d7/a0-a4 in TilemapStampForegroundOverBox)
;==============================================================================
TilemapStampForegroundOverFriend:
    move.w      #FRIEND_FRAME_WIDTH,d2
    move.w      #FRIEND_FRAME_HEIGHT,d3
    ; fall through to TilemapStampForegroundOverBox

;==============================================================================
; TilemapStampForegroundOverBox  -  Re-blit foreground tiles overlapping actor box
;
; In:  d0.w = Actor World X (0..319)
;      d1.w = Actor World Y (0..671)
;      d2.w = Actor Width (pixels)
;      d3.w = Actor Height (pixels)
; Preserves: all caller registers (pushes d0-d7/a0-a4 at entry, restores at .done_fg)
;==============================================================================
TilemapStampForegroundOverBox:
    PUSHM       d0-d7/a0-a4
    ; Calculate start/end columns: d0 = X (0..319)
    move.w      d0,d6
    lsr.w       #4,d6                   ; d6 = start col = X / 16 (0..19)
    move.w      d0,d7
    add.w       d2,d7
    subq.w      #1,d7
    lsr.w       #4,d7                   ; d7 = end col = (X + Width - 1) / 16 (0..19)

    ; Calculate start/end rows: d1 = Y (0..671)
    move.w      d1,d4
    lsr.w       #4,d4                   ; d4 = start row = Y / 16 (0..41)
    move.w      d1,d5
    add.w       d3,d5
    subq.w      #1,d5
    lsr.w       #4,d5                   ; d5 = end row = (Y + Height - 1) / 16 (0..41)

    ; Clamp rows and cols to valid map grid
    tst.w       d6
    bpl.s       .col_start_ok
    moveq       #0,d6
.col_start_ok:
    cmp.w       #TILEMAP_VIEW_COLS-1,d7
    ble.s       .col_ok
    move.w      #TILEMAP_VIEW_COLS-1,d7
.col_ok:
    tst.w       d4
    bpl.s       .row_start_ok
    moveq       #0,d4
.row_start_ok:
    move.w      CurrentMapHeight(a5),d0
    subq.w      #1,d0
    cmp.w       d0,d5
    ble.s       .row_ok
    move.w      d0,d5
.row_ok:

    ; Validate bounds: start <= end
    cmp.w       d7,d6
    bgt.s       .done_fg
    cmp.w       d5,d4
    bgt.s       .done_fg

    move.l      CurrentLevelDef(a5),d2
    beq.s       .done_fg
    movea.l     d2,a0
    move.l      LevelDef_ForegroundMap(a0),d2
    beq.s       .done_fg
    movea.l     d2,a2                   ; a2 = ForegroundMap binary pointer
    addq.l      #8,a2                   ; skip 8-byte map header

    ; Loop row by row: cur_row in d2 from d4 to d5
    move.w      d4,d2
.fg_row_loop:
    cmp.w       d5,d2
    bgt.s       .done_fg

    ; Precompute row start pointer: a1 = a2 + (row * 40)
    ; row * 40 = (row << 5) + (row << 3)
    move.w      d2,d0
    lsl.w       #5,d0                   ; row * 32
    move.w      d2,d1
    lsl.w       #3,d1                   ; row * 8
    add.w       d1,d0                   ; row * 40
    lea         (a2,d0.w),a1            ; a1 = pointer to start of row in ForegroundMap

    ; Loop col by col: cur_col in d3 from d6 to d7
    move.w      d6,d3
.fg_col_loop:
    cmp.w       d7,d3
    bgt.s       .next_fg_row

    ; Calculate column byte offset: col * 2
    move.w      d3,d0
    add.w       d0,d0                   ; col * 2
    move.w      (a1,d0.w),d0            ; read Big-Endian tile index (0..255)
    beq.s       .next_fg_col            ; empty tile, skip

    ; Tile found! Blit single tile (d0 = tile index, d3 = col, d2 = row)
    bsr         TilemapBlitSingleTile

    ; If this tile is under water, re-apply water submersion!
    move.w      d3,d0                   ; col
    move.w      d2,d1                   ; row
    bsr         TilemapSubmergeTile

.next_fg_col:
    addq.w      #1,d3
    bra.s       .fg_col_loop

.next_fg_row:
    addq.w      #1,d2
    bra.s       .fg_row_loop

.done_fg:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapBlitSingleTile  -  Cookie-cut blit one 16x16 tile into DisplayScreen
;
; In:  d0.w = tile index (1-based from tileset, 0..255)
;      d2.w = tile row (0..41)
;      d3.w = tile column (0..19)
;      a5   = Variables base
;      a6   = CUSTOM base ($dff000)
; Preserves: d2, d3, d4-d7, a2, a5, a6
;==============================================================================
TilemapBlitSingleTile:
    PUSHM       d1-d3/a0-a4

    ; Fast lookup of source byte offset in tileset!
    add.w       d0,d0
    lea         TileSheetOffsetTable,a3
    move.w      (a3,d0.w),d0
    ext.l       d0

    move.l      CurrentLevelDef(a5),d1
    beq.s       .legacy_ts
    movea.l     d1,a3
    movea.l     LevelDef_TilesetMsk(a3),a3
    movea.l     d1,a4
    movea.l     LevelDef_TilesetRaw(a4),a4
    bra.s       .ts_ready
.legacy_ts:
    lea         GameTilesMsk,a3
    lea         GameTilesRaw,a4
.ts_ready:
    add.l       d0,a3                   ; a3 = source mask pointer
    add.l       d0,a4                   ; a4 = source graphic pointer

    ; Destination screen address: (row * 2560) + (col * 2)
    move.w      d2,d1
    add.w       d1,d1
    add.w       d1,d1                   ; row * 4
    lea         TileRowStrideTable,a0
    move.l      (a0,d1.w),d1            ; row * 2560
    moveq       #0,d0
    move.w      d3,d0
    add.w       d0,d0                   ; col * 2
    add.l       d0,d1                   ; screen offset

    lea         DisplayScreen,a1
    adda.l      d1,a1                   ; a1 = dest pointer in DisplayScreen

    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)      ; cookie-cut minterm $CA
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)

    move.w      #TILEMAP_SHEET_BYTES-TILEMAP_TILE_BYTES,BLTAMOD(a6) ; 22 - 2 = 20
    move.w      #TILEMAP_SHEET_BYTES-TILEMAP_TILE_BYTES,BLTBMOD(a6) ; 22 - 2 = 20
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTCMOD(a6)   ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTDMOD(a6)   ; 40 - 2 = 38

    move.l      a3,BLTAPT(a6)           ; Mask
    move.l      a4,BLTBPT(a6)           ; Graphic
    move.l      a1,BLTCPT(a6)           ; Background
    move.l      a1,BLTDPT(a6)           ; Destination

    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|(TILEMAP_TILE_BYTES/2),BLTSIZE(a6) ; 64 rows x 1 word

    POPM        d1-d3/a0-a4
    rts



;==============================================================================
; TilemapGetAttribute  -  Query collision / physical attribute at pixel (X, Y)
;
; Arguments:
;   d0.w = X pixel coordinate (0..319)
;   d1.w = Y pixel coordinate (0..671)
;
; Returns:
;   d0.b = Attribute byte (ATTR_EMPTY, ATTR_SOLID, ATTR_LADDER, ATTR_HAZARD)
;
; Destroys: d1, d2, a0
;==============================================================================

TilemapGetAttribute:
    ; Bounds check X (0..319)
    cmp.w       #0,d0
    blt.s       .out_of_bounds_solid
    cmp.w       #320,d0
    bge.s       .out_of_bounds_solid

    ; Bounds check Y (0 .. CurrentMapHeight*16 - 1)
    cmp.w       #0,d1
    blt.s       .out_of_bounds_solid
    move.w      CurrentMapHeight(a5),d2
    lsl.w       #4,d2                   ; d2 = CurrentMapHeight * 16 (dynamic level height!)
    cmp.w       d2,d1
    bge.s       .out_of_bounds_solid

    ; Tile Column = X / 16 (0..19)
    lsr.w       #4,d0

    ; Tile Row = Y / 16 (0 .. CurrentMapHeight-1)
    lsr.w       #4,d1

    ; Fast grid offset = Row * 20 + Col (using fast shift-and-add)
    move.w      d1,d2
    lsl.w       #2,d2                   ; Row * 4
    lsl.w       #4,d1                   ; Row * 16
    add.w       d2,d1                   ; Row * 20
    add.w       d0,d1                   ; Row * 20 + Col

    ; Direct physical query into 1D GameMap (eliminates double indirection & endian swaps)
    lea         GameMap(a5),a0
    move.b      (a0,d1.w),d0            ; d0.b = physical block attribute
    rts

.out_of_bounds_solid:
    moveq       #BLOCK_SOLID,d0
    rts


;==============================================================================
; TilemapSnapCamera  -  Immediately align camera viewport with player position
;
; Snaps CameraPixelY, TilemapScreenOffset, and TilemapFineY directly to match
; the active viewport window without smooth interpolation.
;   - If player is above top margin (PlayerPixelY < CameraPixelY + CAM_MARGIN_TOP):
;       snap CameraPixelY = max(0, PlayerPixelY - CAM_MARGIN_TOP)
;   - If player is below bottom margin (PlayerPixelY > CameraPixelY + CAM_MARGIN_BOTTOM):
;       snap CameraPixelY = min(MAX_CAM_Y, PlayerPixelY - CAM_MARGIN_BOTTOM)
;   - Otherwise player is within deadzone window: keep current camera position.
; Called at level intro and undo.
;==============================================================================

TilemapSnapCamera:
    PUSHM       d0-d7/a0-a4
    lea         Player(a5),a4              ; a4 -> player struct
    tst.w       Player_Status(a4)          ; is player active?
    beq         .snap_exit

    ; 1. Calculate player's actual map pixel Y: Player_Y * 16 + Player_YDec
    move.w      Player_Y(a4),d0
    lsl.w       #4,d0
    add.w       Player_YDec(a4),d0         ; d0 = PlayerPixelY

    move.w      TilemapCameraY(a5),d1      ; d1 = current CameraPixelY

    ; 2. Check top margin (PlayerPixelY - LevelCamMarginTop < CameraPixelY):
    move.w      d0,d2
    sub.w       LevelCamMarginTop(a5),d2   ; d2 = TargetY_Up = PlayerPixelY - MarginTop
    cmp.w       LevelMinCameraY(a5),d2
    bge.s       .snap_top_min_ok
    move.w      LevelMinCameraY(a5),d2     ; clamp min (top of map)
.snap_top_min_ok:
    cmp.w       d1,d2                      ; compare TargetY_Up with current CameraPixelY
    blt.s       .snap_apply                ; TargetY_Up < CameraPixelY -> snap up to d2

    ; 3. Check bottom margin (PlayerPixelY - LevelCamMarginBottom > CameraPixelY):
    move.w      d0,d2
    sub.w       LevelCamMarginBottom(a5),d2 ; d2 = TargetY_Down = PlayerPixelY - MarginBottom
    move.w      LevelMaxCameraY(a5),d3
    cmp.w       d3,d2
    ble.s       .snap_bot_max_ok
    move.w      d3,d2                      ; clamp max
.snap_bot_max_ok:
    cmp.w       d1,d2                      ; compare TargetY_Down with current CameraPixelY
    bgt.s       .snap_apply                ; TargetY_Down > CameraPixelY -> snap down to d2

    ; Player is already within visible window [CameraPixelY + 16 .. CameraPixelY + 176]
    move.w      d1,d2                      ; maintain current CameraPixelY

.snap_apply:
    move.w      d2,d1                      ; d1 = new snapped CameraPixelY
    bsr         TilemapApplyCameraY

.snap_exit:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapUpdateCamera  -  Smooth Vertical Camera Tracking & Deadzone Scrolling
;
; Vertical Deadzone Window:
;   - Upper threshold: 1 row below screen top (CameraPixelY + LevelCamMarginTop)
;   - Lower threshold: 1 row above screen bottom (CameraPixelY + LevelCamMarginBottom)
;
; Camera movement rules:
;   - Player above top threshold: scrolls UP to keep player at least 1 row from top
;   - Player below bottom threshold: scrolls DOWN to keep player at least 1 row from bottom
;   - Player between thresholds: camera remains stationary
;
; Advance speeds:
;   - Walking / climbing: 2 pixels per frame
;   - Falling: advances at the player's falling velocity (Player_ActionFrame)
;   - Idle: settles final 1-pixel parity difference
;==============================================================================

TilemapUpdateCamera:
    PUSHM       d0-d7/a0-a4
    lea         Player(a5),a4              ; a4 -> player struct
    tst.w       Player_Status(a4)          ; is player active?
    beq         .cam_exit                  ; no -> nothing to track

    ; 1. Calculate player's current actual map pixel Y:
    ;    PlayerPixelY = Player_Y * 16 + Player_YDec
    move.w      Player_Y(a4),d0
    lsl.w       #4,d0
    add.w       Player_YDec(a4),d0         ; d0 = PlayerPixelY

    move.w      TilemapCameraY(a5),d1      ; d1 = current CameraPixelY

    ; 2. Check if player pushes TOP margin (1 row below top = CameraPixelY + LevelCamMarginTop):
    ;    Scroll UP if TargetY_Up = PlayerPixelY - LevelCamMarginTop < CameraPixelY
    move.w      d0,d2
    sub.w       LevelCamMarginTop(a5),d2   ; d2 = TargetY_Up
    cmp.w       LevelMinCameraY(a5),d2
    bge.s       .top_min_ok
    move.w      LevelMinCameraY(a5),d2     ; clamp min (top of map)
.top_min_ok:
    cmp.w       d1,d2                      ; compare TargetY_Up with current CameraPixelY
    blt.s       .cam_move_up               ; TargetY_Up < CameraPixelY -> scroll UP!

    ; 3. Check if player pushes BOTTOM margin (1 row above bottom = CameraPixelY + LevelCamMarginBottom):
    ;    Scroll DOWN if TargetY_Down = PlayerPixelY - LevelCamMarginBottom > CameraPixelY
    move.w      d0,d2
    sub.w       LevelCamMarginBottom(a5),d2 ; d2 = TargetY_Down
    move.w      LevelMaxCameraY(a5),d3
    cmp.w       d3,d2
    ble.s       .bot_max_ok
    move.w      d3,d2                      ; clamp max
.bot_max_ok:
    cmp.w       d1,d2                      ; compare TargetY_Down with current CameraPixelY
    bgt.s       .cam_move_down             ; TargetY_Down > CameraPixelY -> scroll DOWN!

    ; Player is within vertical deadzone [CameraPixelY + 16 .. CameraPixelY + 176] -> no scroll
    bra.s       .cam_exit

.cam_move_up:
    ; d2 = TargetCameraY (clamped to 0..464), d1 = current CameraPixelY (d1 > d2)
    move.w      d2,d0                      ; d0 = TargetCameraY
    move.w      d1,d2
    sub.w       d0,d2                      ; d2 = diff = CameraY - TargetY
    cmp.w       #2,d2
    bge.s       .cam_up_2px
    ; diff == 1: if idle, settle the final 1 pixel
    cmp.w       #ACTION_IDLE,ActionStatus(a5)
    bne.s       .cam_exit
    subq.w      #1,d1
    bra.s       .cam_step_done
.cam_up_2px:
    subq.w      #2,d1
    bra.s       .cam_step_done

.cam_move_down:
    ; d2 = TargetCameraY (clamped to 0..464), d1 = current CameraPixelY (d1 < d2)
    move.w      d2,d0                      ; d0 = TargetCameraY
    tst.w       Player_Fallen(a4)
    beq.s       .cam_down_step

    ; Falling: advance by current falling velocity (Player_ActionFrame)
    move.w      Player_ActionFrame(a4),d2  ; d2 = fall velocity
    cmp.w       #1,d2
    bge.s       .cam_down_vel_ok
    moveq       #1,d2
.cam_down_vel_ok:
    add.w       d2,d1                      ; CameraPixelY += velocity
    cmp.w       d0,d1                      ; did we pass TargetY?
    ble.s       .cam_step_done
    move.w      d0,d1                      ; clamp to TargetY
    bra.s       .cam_step_done

.cam_down_step:
    ; Walking / climbing down: step by 2 pixels when difference >= 2
    move.w      d0,d2
    sub.w       d1,d2                      ; d2 = diff = TargetY - CameraY
    cmp.w       #2,d2
    bge.s       .cam_down_2px
    ; diff == 1: if idle, settle the final 1 pixel; if moving, wait for next pixel
    cmp.w       #ACTION_IDLE,ActionStatus(a5)
    bne.s       .cam_exit
    addq.w      #1,d1
    bra.s       .cam_step_done
.cam_down_2px:
    addq.w      #2,d1

.cam_step_done:
    bsr         TilemapApplyCameraY

.cam_exit:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapApplyCameraY  -  Apply New Camera Pixel Position
;
; In:  d1 = new CameraPixelY (0..464)
;      a4 = active player struct pointer
;==============================================================================

TilemapApplyCameraY:
    ; Store new CameraPixelY
    move.w      d1,TilemapCameraY(a5)

    ; Precompute active viewport spatial culling bounds:
    move.w      d1,d0
    sub.w       #32,d0
    move.w      d0,CameraCullTopY(a5)
    move.w      d1,d0
    add.w       #248,d0
    move.w      d0,CameraCullBottomY(a5)

    ; Calculate byte offset in DisplayScreen: CameraPixelY * 160 (TILEMAP_LINE_STRIDE)
    move.w      d1,d0
    mulu.w      #TILEMAP_LINE_STRIDE,d0
    add.l       #DisplayScreen,d0

    ; Update Copper bitplane pointers in cpPlanes
    lea         cpPlanes,a0
    move.l      #SCREEN_WIDTH_BYTE,d1
    moveq       #TILEMAP_TILE_PLANES,d7
    bsr         CopperSetPtrs

    ; Maintain TilemapScreenOffset and TilemapFineY for any external callers
    move.w      TilemapCameraY(a5),d2
    lsr.w       #4,d2
    move.w      d2,TilemapScreenOffset(a5)
    move.w      d2,TilemapCurrentOffset(a5)
    move.w      TilemapCameraY(a5),d2
    and.w       #15,d2
    move.w      d2,TilemapFineY(a5)

    ; Refresh player BOB animation frame for new camera offset
    ; using the currently active animation frame (preserved across fall, ladder, walk)
    move.w      PlayerFrame(a5),d0
    bsr         ShowPlayer

    ; Update Copper background sky gradient with 1/2 vertical parallax
    bsr         TilemapUpdateCopperSky
    rts


;==============================================================================
; TilemapDisableCopperSky  -  Halt Copper before sky gradient (for CPU raster bar)
;
; Replaces the first scanline WAIT in cpGameSky with COPPER_HALT ($fffffffe).
; The Copper halts immediately after writing the 32 palette colors, leaving
; COLOR00 black across the entire frame. This allows the CPU-timed raster bar
; in MainLoop (DebugMode=2) to be drawn cleanly without being overwritten
; by the 216-scanline copper sky gradient.
;
; Preserves all registers.
;==============================================================================

TilemapDisableCopperSky:
    move.l      #COPPER_HALT,cpGameSky
    rts

;==============================================================================
; TilemapEnableCopperSky  -  Restore Copper sky gradient and refresh colors
;
; Restores the first scanline WAIT in cpGameSky (PAL line 44 / NTSC line 28),
; then repopulates the scanline gradient colors for the current camera height.
;
; Preserves all registers.
;==============================================================================

TilemapEnableCopperSky:
    PUSHM       d0/d7/a0-a1
    tst.w       IsPAL(a5)
    beq.s       .tecs_ntsc
    move.w      #($2c<<8)|$07,cpGameSky
    move.w      #$fffe,cpGameSky+2
    bra.s       .tecs_restore
.tecs_ntsc:
    move.w      #(NTSC_WINDOW_Y_START<<8)|$07,cpGameSky
    move.w      #$fffe,cpGameSky+2
.tecs_restore:
    bsr         TilemapUpdateCopperSkyForce
    clr.w       COLOR00(a6)             ; ensure background color returns to black
    POPM        d0/d7/a0-a1
    rts

;==============================================================================
; TilemapUpdateCopperSky  -  Update Copper Sky Gradient with 1/2 Parallax Speed
;
; Computes SkyY = TilemapCameraY >> 1 (0..232), then copies 216 words from
; CopperSkyTable[SkyY .. SkyY+215] into the cpGameSky Copper list entries.
;
; If CPU raster profiler is active (DebugMode == 2), this is skipped to preserve
; the COPPER_HALT at cpGameSky.
;
; Each cpGameSky entry is 8 bytes:
;   +0: WAIT (line, $07), $fffe
;   +4: MOVE COLOR00, data (word operand at +6)
;
; Destroys: d0, d7, a0, a1
;==============================================================================

TilemapUpdateCopperSky:
    cmp.w       #2,DebugMode(a5)
    bne.s       TilemapUpdateCopperSkyForce
    rts

TilemapUpdateCopperSkyForce:
    move.w      TilemapCameraY(a5),d0
    lsr.w       #1,d0                   ; d0 = SkyY = CameraY / 2 (0..232) -> 1/2 parallax
    add.w       d0,d0                   ; d0 = byte offset (2 bytes per word)
    lea         CopperSkyTable,a0
    adda.w      d0,a0                   ; a0 -> 216-word slice for current camera height

    lea         cpGameSky+6,a1          ; a1 -> first COLOR00 operand in cpGameSky

    tst.w       IsPAL(a5)
    beq.s       .ntsc_sky

    ; --- PAL: 212 lines, skip 4-byte line-255 crossing wait, then 4 lines ---
    moveq       #(212/4)-1,d7           ; first 212 scanlines (lines 44..255) in 53 loops of 4
.sky_loop1:
    move.w      (a0)+,(a1)              ; scanline N
    move.w      (a0)+,8(a1)             ; scanline N+1
    move.w      (a0)+,16(a1)            ; scanline N+2
    move.w      (a0)+,24(a1)            ; scanline N+3
    lea         32(a1),a1               ; advance by 4 copper instructions (32 bytes)
    dbra        d7,.sky_loop1

    ; Skip the 4-byte line-255 crossing WAIT ($FFDF, $FFFE) to reach scanline 212 (line 256)
    addq.l      #4,a1
    move.w      (a0)+,(a1)              ; scanline 212 (line 256)
    move.w      (a0)+,8(a1)             ; scanline 213 (line 257)
    move.w      (a0)+,16(a1)            ; scanline 214 (line 258)
    move.w      (a0)+,24(a1)            ; scanline 215 (line 259)
    rts

.ntsc_sky:
    ; --- NTSC: all 216 scanlines (lines 28..243) are contiguous (no line-255 crossing) ---
    moveq       #(216/4)-1,d7           ; 216 scanlines in 54 loops of 4
.sky_loop_ntsc:
    move.w      (a0)+,(a1)              ; scanline N
    move.w      (a0)+,8(a1)             ; scanline N+1
    move.w      (a0)+,16(a1)            ; scanline N+2
    move.w      (a0)+,24(a1)            ; scanline N+3
    lea         32(a1),a1               ; advance by 4 copper instructions (32 bytes)
    dbra        d7,.sky_loop_ntsc
    rts



;==============================================================================
; TileAttributesTable  -  Physics & Collision Attribute Lookup Table
;
; Maps 256 tile indices to physical attributes:
;   ATTR_EMPTY       = 0 (air / free movement)
;   ATTR_SOLID       = 1 (solid platform / wall)
;   ATTR_LADDER      = 2 (climbable ladder)
;   ATTR_HAZARD      = 3 (hazard / spikes)
;   ATTR_PASSTHROUGH = 4 (jump-through platform)
;==============================================================================

TileAttributesTable:
    ; Index 0: Transparent empty space
    dc.b        ATTR_EMPTY              ; Tile 00

    ; Indices 1..15: Solid platforms & structural tiles
    dc.b        ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID ; 01-04
    dc.b        ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID ; 05-08
    dc.b        ATTR_SOLID, ATTR_SOLID, ATTR_SOLID, ATTR_SOLID ; 09-12
    dc.b        ATTR_SOLID, ATTR_SOLID, ATTR_SOLID             ; 13-15

    ; Indices 16..23: Ladders / Climbable vine ropes
    dc.b        ATTR_LADDER, ATTR_LADDER, ATTR_LADDER, ATTR_LADDER ; 16-19
    dc.b        ATTR_LADDER, ATTR_LADDER, ATTR_LADDER, ATTR_LADDER ; 20-23

    ; Indices 24..31: Hazards / spikes / water
    dc.b        ATTR_HAZARD, ATTR_HAZARD, ATTR_HAZARD, ATTR_HAZARD ; 24-27
    dc.b        ATTR_HAZARD, ATTR_HAZARD, ATTR_HAZARD, ATTR_HAZARD ; 28-31

    ; Indices 32..255: Default remaining tiles to solid / decor
    dcb.b       256-32, ATTR_SOLID

    even


;==============================================================================
; TilemapEraseDebugOverlay  -  Restore screen background where debug HUD was drawn
;
; Uses a blitter copy from NonDisplayScreen (pristine background) to
; DisplayScreen (active display) over the 30 scanlines where debug text was
; rendered in the previous frame.
;
; Called when exiting Slow Mode or when camera moves during Slow Mode frame steps.
;
; Destroys: none (preserves all registers)
;==============================================================================

;==============================================================================
; TilemapDrawPauseBanner  -  Render "** PAUSED **" banner centered on DisplayScreen
;
; Called when game is paused via 'P' key.
; Uses DebugDrawLine to stamp 8x8 font glyphs in bold green at viewport center.
;
; Destroys: none (preserves all registers)
;==============================================================================
;==============================================================================
; Pause_DesaturateColor  -  Helper: Desaturate (50%) and darken (50%) an OCS color
;
; In:   d0.w = $0RGB color (4 bits per channel)
; Out:  d0.w = desaturated and darkened $0RGB color
; Destroys: d1, d2, d3
;==============================================================================
Pause_DesaturateColor:
    ; Extract channels into d1=R, d2=G, d0=B
    move.w      d0,d1
    lsr.w       #8,d1
    andi.w      #$F,d1                  ; d1 = R (0..15)

    move.w      d0,d2
    lsr.w       #4,d2
    andi.w      #$F,d2                  ; d2 = G (0..15)

    andi.w      #$F,d0                  ; d0 = B (0..15)

    ; Calculate luminance: grey = (R + G + B) * 85 >> 8
    move.w      d1,d3
    add.w       d2,d3
    add.w       d0,d3                   ; d3 = R + G + B (0..45)
    mulu.w      #85,d3
    lsr.l       #8,d3
    andi.w      #$F,d3                  ; d3 = grey (0..14)

    ; 50% desaturation towards grey: new = (ch + grey) >> 1
    add.w       d3,d1
    lsr.w       #1,d1                   ; new R
    add.w       d3,d2
    lsr.w       #1,d2                   ; new G
    add.w       d3,d0
    lsr.w       #1,d0                   ; new B

    ; 50% darkening: new = new >> 1
    lsr.w       #1,d1
    lsr.w       #1,d2
    lsr.w       #1,d0

    ; Pack into d0: (R << 8) | (G << 4) | B
    lsl.w       #4,d2
    or.w        d2,d0                   ; d0 = (G << 4) | B
    lsl.w       #8,d1
    or.w        d1,d0                   ; d0 = (R << 8) | (G << 4) | B
    rts

;==============================================================================
; Pause_ApplyPalette  -  Snapshot cpPal, desaturate & darken Copper palette & sky
;
; Desaturates and darkens all 32 palette colors in cpPal (stride 4) and the
; 216 scanline colors in cpGameSky (stride 8). Keeps Color 5 at $04F4 (bright green)
; so the centered "** PAUSED **" text overlay stands out vividly.
;
; Preserves all registers.
;==============================================================================
Pause_ApplyPalette:
    PUSHM       d0-d3/d7/a0-a1

    tst.w       Pause_PaletteActive(a5)
    bne         .pa_done                ; already active: do not re-snapshot

    ; 1. Snapshot original 32 palette values from cpPal+2 into Pause_SavedPal
    lea         cpPal+2,a0              ; a0 -> first color operand in cpPal
    lea         Pause_SavedPal(a5),a1
    moveq       #32-1,d7
.pa_snap:
    move.w      (a0),(a1)+
    addq.l      #4,a0                   ; stride 4 bytes per copper MOVE
    dbra        d7,.pa_snap

    ; 2. Compute desaturated + darkened colors and write into cpPal
    lea         Pause_SavedPal(a5),a0
    lea         cpPal+2,a1
    moveq       #32-1,d7
.pa_desat:
    move.w      (a0)+,d0
    bsr         Pause_DesaturateColor
    move.w      d0,(a1)
    addq.l      #4,a1
    dbra        d7,.pa_desat

    ; 3. Pin COLOR14 (entry 14) to bright neon green for the pause text overlay
    ; Color 14 is unused by all map tiles, actors, and animal friends.
    ; Entry 14 value word = cpPal + (14 * 4) + 2 = cpPal + 58
    move.w      #$04f4,cpPal+(14*4)+2

    ; 4. Desaturate and darken cpGameSky scanline gradient entries
    lea         cpGameSky+6,a1          ; first COLOR00 operand in cpGameSky
    tst.w       IsPAL(a5)
    beq.s       .pa_sky_ntsc

    ; --- PAL: 212 lines, skip 4-byte wait at line 255, then 4 lines ---
    move.w      #212-1,d7
.pa_sky_pal1:
    move.w      (a1),d0
    bsr         Pause_DesaturateColor
    move.w      d0,(a1)
    addq.l      #8,a1                   ; stride 8 bytes (WAIT + MOVE COLOR00)
    dbra        d7,.pa_sky_pal1

    addq.l      #4,a1                   ; skip line-255 crossing WAIT ($FFDF, $FFFE)
    moveq       #4-1,d7
.pa_sky_pal2:
    move.w      (a1),d0
    bsr         Pause_DesaturateColor
    move.w      d0,(a1)
    addq.l      #8,a1
    dbra        d7,.pa_sky_pal2
    bra.s       .pa_sky_done

.pa_sky_ntsc:
    ; --- NTSC: 216 contiguous scanlines ---
    move.w      #216-1,d7
.pa_sky_ntsc_loop:
    move.w      (a1),d0
    bsr         Pause_DesaturateColor
    move.w      d0,(a1)
    addq.l      #8,a1
    dbra        d7,.pa_sky_ntsc_loop

.pa_sky_done:
    move.w      #1,Pause_PaletteActive(a5)

.pa_done:
    POPM        d0-d3/d7/a0-a1
    rts

;==============================================================================
; Pause_RestorePalette  -  Restore original palette to cpPal and refresh cpGameSky
;
; Preserves all registers.
;==============================================================================
Pause_RestorePalette:
    PUSHM       d0/d7/a0-a1

    tst.w       Pause_PaletteActive(a5)
    beq.s       .pr_done

    ; 1. Restore 32 colors to cpPal from Pause_SavedPal
    lea         Pause_SavedPal(a5),a0
    lea         cpPal+2,a1
    moveq       #32-1,d7
.pr_restore:
    move.w      (a0)+,(a1)
    addq.l      #4,a1
    dbra        d7,.pr_restore

    ; 2. Refresh Copper sky gradient from CopperSkyTable
    bsr         TilemapUpdateCopperSky

    clr.w       Pause_PaletteActive(a5)

.pr_done:
    POPM        d0/d7/a0-a1
    rts


;==============================================================================
; PauseDrawLine  -  Render pause banner text in Color 14 (unused by tiles)
;
; In:   d0.w = Screen Y coordinate
;       d1.w = Byte column (0..39)
;       a0   = Pointer to null-terminated string
;
; Writes glyph bits into Bitplanes 1, 2, and 3 (%1110 = Color 14), clearing Plane 0.
; Color 14 is completely unused by all map tiles, actors, and animal friends,
; ensuring zero tile color corruption when highlighted.
;==============================================================================
PauseDrawLine:
    PUSHM       d0-d5/d7/a0-a4

    ; Base pointer in DisplayScreen: (Y * 160) + X + DisplayScreen
    mulu.w      #TILEMAP_LINE_STRIDE,d0     ; d0.l = 32-bit unsigned offset
    lea         DisplayScreen,a1
    add.l       d0,a1
    ext.l       d1
    add.l       d1,a1                       ; a1 = target byte in DisplayScreen (Plane 0)
    lea         FontData,a2                 ; a2 = base of FontData

.char_loop:
    move.b      (a0)+,d2
    beq.s       .done

    ; Bounds check character (only ASCII 32..127 in font)
    cmp.b       #32,d2
    bge.s       .char_ge32
    moveq       #32,d2
.char_ge32:
    cmp.b       #127,d2
    ble.s       .char_ok
    moveq       #32,d2
.char_ok:
    sub.b       #32,d2
    and.w       #$00ff,d2
    lsl.w       #3,d2                       ; d2 = (char - 32) * 8
    lea         (a2,d2.w),a4                ; a4 -> 8 bytes of glyph

    ; Render 8 scanlines for this character
    movea.l     a1,a3                       ; a3 = Plane 0 for current row
    moveq       #8-1,d7
.row_loop:
    move.b      (a4)+,d3
    move.b      d3,d4
    lsr.b       #1,d4
    or.b        d4,d3                       ; bold smear

    clr.b       (a3)                        ; Plane 0 = 0     (Color 14 bit 0)
    move.b      d3,40(a3)                   ; Plane 1 = glyph (Color 14 bit 1)
    move.b      d3,80(a3)                   ; Plane 2 = glyph (Color 14 bit 2)
    move.b      d3,120(a3)                  ; Plane 3 = glyph (Color 14 bit 3)

    lea         160(a3),a3                  ; advance to next scanline (+160 bytes)
    dbra        d7,.row_loop

    addq.l      #1,a1                       ; next byte column (+8 pixels)
    bra.s       .char_loop

.done:
    POPM        d0-d5/d7/a0-a4
    rts


TilemapDrawPauseBanner:
    PUSHM       d0-d1/a0
    bsr         Pause_ApplyPalette
    move.w      TilemapCameraY(a5),d0
    add.w       #96,d0                      ; center of 200-line viewport (row 96)
    move.w      d0,PrevPauseCameraY(a5)     ; save exact scanline for erase on unpause
    moveq       #17,d1                      ; column 17: exactly centered for 6-char "PAUSED"
    lea         .str_paused(pc),a0
    bsr         PauseDrawLine
    POPM        d0-d1/a0
    rts

.str_paused:    dc.b    "PAUSED",0
                even


;==============================================================================
; TilemapErasePauseBanner  -  Restore screen background where pause banner was drawn
;
; Called when game is unpaused via 'P' key.
; Restores the 8-scanline background strip from NonDisplayScreen to DisplayScreen.
;
; Destroys: none (preserves all registers)
;==============================================================================
TilemapErasePauseBanner:
    PUSHM       d0-d7/a0-a4/a6
    lea         CUSTOM,a6
    WAITBLIT

    ; Calculate start byte offset: (PrevPauseCameraY * 160) + 16 (centered 4 words)
    move.w      PrevPauseCameraY(a5),d0
    mulu.w      #TILEMAP_LINE_STRIDE,d0
    add.l       #16,d0                      ; columns 16..23 (covers centered "PAUSED" at cols 17..22)

    lea         NonDisplayScreen,a0
    add.l       d0,a0
    lea         DisplayScreen,a1
    add.l       d0,a1

    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #32,BLTAMOD(a6)             ; 40 - 8 = 32
    move.w      #32,BLTDMOD(a6)             ; 40 - 8 = 32
    move.w      #0,BLTCON1(a6)
    move.w      #$09f0,BLTCON0(a6)          ; A -> D copy (minterm $F0)
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(32<<6)|4,BLTSIZE(a6)      ; 32 plane-rows x 4 words = 8 scanlines x 8 bytes
    WAITBLIT

    ; Restore full-color palette to cpPal & cpGameSky
    bsr         Pause_RestorePalette

    ; Mark all actors dirty and redraw push blocks / crates immediately
    bsr         MarkAllActorsDirty
    bsr         TilemapDrawPushBlocks

    ; Invalidate drawn state of oxygen pickups so they redraw on unpause
    move.w      ActiveOxygenCount(a5),d7
    beq.s       .no_oxy
    subq.w      #1,d7
    lea         ActiveOxygen(a5),a4
.oxy_loop:
    clr.w       ox_Drawn(a4)
    lea         ox_SIZEOF(a4),a4
    dbra        d7,.oxy_loop
.no_oxy:

    POPM        d0-d7/a0-a4/a6
    rts


TilemapEraseDebugOverlay:
    tst.w       PrevDebugDrawn(a5)
    beq         .done

    ; If overlay is still active and camera has NOT moved, do NOT erase!
    ; In a single-buffered display, erasing every frame causes severe flicker
    ; because the electron beam scans lines 2..30 while they are erased.
    tst.w       DebugOverlayActive(a5)
    beq.s       .do_erase

    move.w      TilemapCameraY(a5),d0
    cmp.w       PrevDebugCameraY(a5),d0
    beq         .done

.do_erase:
    clr.w       PrevDebugDrawn(a5)

    PUSHM       d0/a0-a1/a6
    lea         CUSTOM,a6
    WAITBLIT

    ; Calculate start byte offset: (PrevDebugCameraY + 2) * 160
    move.w      PrevDebugCameraY(a5),d0
    addq.w      #2,d0
    mulu.w      #TILEMAP_LINE_STRIDE,d0

    lea         NonDisplayScreen,a0
    add.l       d0,a0
    lea         DisplayScreen,a1
    add.l       d0,a1

    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #0,BLTDMOD(a6)
    move.w      #0,BLTCON1(a6)
    move.w      #$09f0,BLTCON0(a6)          ; A -> D copy (minterm $F0)
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(120<<6)|20,BLTSIZE(a6)    ; 120 plane-rows x 20 words = 30 scanlines x 160 bytes
    WAITBLIT

    POPM        d0/a0-a1/a6
.done:
    rts


;==============================================================================
; TilemapDrawDebugOverlay  -  Render debug statistics HUD on DisplayScreen
;
; Displays 3 lines of green text near the top of the visible viewport:
;   Line 1: CAM:yyy ROW:rr FINE:ff MODE:SLOW
;   Line 2: PLY: X:cc+xx Y:rr+yy
;   Line 3: ACT:a DIR:±1 ENM:ee WTR:ww
;
; Colors:
;   Color 5 ($0193 grass green) for text characters
;   Color 0 ($0000 black) for background within each character cell
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapDrawDebugOverlay:
    tst.w       DebugOverlayActive(a5)
    beq         .exit

    PUSHM       d0-d7/a0-a4

    ; Record current camera position for erase when scrolling/toggled off
    move.w      TilemapCameraY(a5),d6
    move.w      d6,PrevDebugCameraY(a5)
    move.w      #1,PrevDebugDrawn(a5)

    lea         Player(a5),a4               ; a4 -> player struct
    tst.w       Player_Status(a4)
    beq         .pop_exit

    ; -------------------------------------------------------------
    ; Line 1: CAM:yyy ROW:rr FINE:ff MODE:SLOW (24 chars padded)
    ; -------------------------------------------------------------
    lea         DebugLineBuf(a5),a1
    lea         .str_cam(pc),a0
    bsr         DebugWriteString

    move.w      TilemapCameraY(a5),d0
    bsr         DebugWriteDec3

    lea         .str_row(pc),a0
    bsr         DebugWriteString

    move.w      TilemapScreenOffset(a5),d0
    bsr         DebugWriteDec2

    lea         .str_fine(pc),a0
    bsr         DebugWriteString

    move.w      TilemapFineY(a5),d0
    bsr         DebugWriteDec2

    lea         .str_mode(pc),a0
    bsr         DebugWriteString

    tst.w       SlowMode(a5)
    bne.s       .mode_slow
    lea         .str_mode_run(pc),a0
    bra.s       .mode_done
.mode_slow:
    lea         .str_mode_slow(pc),a0
.mode_done:
    bsr         DebugWriteString

    clr.b       (a1)                        ; null terminate

    ; Draw Line 1 at CameraY + 2, X column 1
    lea         DebugLineBuf(a5),a0
    move.w      d6,d0
    addq.w      #2,d0
    moveq       #1,d1
    bsr         DebugDrawLine

    ; -------------------------------------------------------------
    ; Line 2: PLY: X:cc+xx Y:rr+yy    (24 chars padded)
    ; -------------------------------------------------------------
    lea         DebugLineBuf(a5),a1
    lea         .str_ply_x(pc),a0
    bsr         DebugWriteString

    move.w      Player_X(a4),d0
    bsr         DebugWriteDec2

    move.w      Player_XDec(a4),d0
    bsr         DebugWriteSigned2

    lea         .str_ply_y(pc),a0
    bsr         DebugWriteString

    move.w      Player_Y(a4),d0
    bsr         DebugWriteDec2

    move.w      Player_YDec(a4),d0
    bsr         DebugWriteSigned2

    clr.b       (a1)                        ; null terminate

    ; Draw Line 2 at CameraY + 11, X column 1
    lea         DebugLineBuf(a5),a0
    move.w      d6,d0
    add.w       #11,d0
    moveq       #1,d1
    bsr         DebugDrawLine

    ; -------------------------------------------------------------
    ; Line 3: ACT:a DIR:±1 ENM:ee WTR:ww (24 chars padded)
    ; -------------------------------------------------------------
    lea         DebugLineBuf(a5),a1
    lea         .str_act(pc),a0
    bsr         DebugWriteString

    move.w      ActionStatus(a5),d0
    bsr         DebugWriteDec1

    lea         .str_dir(pc),a0
    bsr         DebugWriteString

    move.w      Player_Facing(a4),d0
    tst.w       d0
    bpl.s       .dir_right
    move.b      #'-',(a1)+
    move.b      #'1',(a1)+
    bra.s       .dir_done
.dir_right:
    move.b      #'+',(a1)+
    move.b      #'1',(a1)+
.dir_done:

    lea         .str_enm(pc),a0
    bsr         DebugWriteString

    move.w      ActiveEnemyCount(a5),d0
    bsr         DebugWriteDec2

    lea         .str_wtr(pc),a0
    bsr         DebugWriteString

    move.w      WaterCurrentRow(a5),d0
    bsr         DebugWriteDec2

    clr.b       (a1)                        ; null terminate

    ; Draw Line 3 at CameraY + 20, X column 1
    lea         DebugLineBuf(a5),a0
    move.w      d6,d0
    add.w       #20,d0
    moveq       #1,d1
    bsr         DebugDrawLine

.pop_exit:
    POPM        d0-d7/a0-a4
.exit:
    rts

.str_cam:       dc.b    "CAM:",0
.str_row:       dc.b    " ROW:",0
.str_fine:      dc.b    " FINE:",0
.str_ply_x:     dc.b    "PLY: X:",0
.str_ply_y:     dc.b    " Y:",0
.str_act:       dc.b    "ACT:",0
.str_dir:       dc.b    " DIR:",0
.str_enm:       dc.b    " ENM:",0
.str_wtr:       dc.b    " WTR:",0
.str_mode:      dc.b    " MODE:",0
.str_mode_run:  dc.b    "RUN ",0
.str_mode_slow: dc.b    "SLOW",0
    even


;==============================================================================
; DebugDrawLine  -  Render an ASCII string onto DisplayScreen in bold green text
;
; Arguments:
;   a0 = pointer to null-terminated ASCII string
;   d0.w = scanline Y within DisplayScreen (0..687)
;   d1.w = byte column X within row (0..39)
;
; Renders 8x8 font glyphs with horizontal smear for bold readability.
; Characters are drawn into Bitplane 0 and Bitplane 2 (Color index 5: grass green)
; while Bitplane 1 and Bitplane 3 are cleared to 0 (ensuring pure Color 5 over
; any background pixel).
;
; Destroys: none (preserves all registers)
;==============================================================================

DebugDrawLine:
    PUSHM       d0-d5/d7/a0-a4

    ; Base pointer in DisplayScreen: (Y * 160) + X + DisplayScreen
    mulu.w      #TILEMAP_LINE_STRIDE,d0     ; d0.l = 32-bit unsigned offset
    lea         DisplayScreen,a1
    add.l       d0,a1
    ext.l       d1
    add.l       d1,a1                       ; a1 = target byte in DisplayScreen (Plane 0)
    lea         FontData,a2                 ; a2 = base of FontData

.char_loop:
    move.b      (a0)+,d2
    beq.s       .done

    ; Bounds check character (only ASCII 32..127 in font)
    cmp.b       #32,d2
    bge.s       .char_ge32
    moveq       #32,d2
.char_ge32:
    cmp.b       #127,d2
    ble.s       .char_ok
    moveq       #32,d2
.char_ok:
    sub.b       #32,d2
    and.w       #$00ff,d2
    lsl.w       #3,d2                       ; d2 = (char - 32) * 8
    lea         (a2,d2.w),a4                ; a4 -> 8 bytes of glyph

    ; Render 8 scanlines for this character
    movea.l     a1,a3                       ; a3 = Plane 0 for current row
    moveq       #8-1,d7
.row_loop:
    move.b      (a4)+,d3
    move.b      d3,d4
    lsr.b       #1,d4
    or.b        d4,d3                       ; bold smear

    move.b      d3,(a3)                     ; Plane 0 = glyph (Color 5 bit 0)
    clr.b       40(a3)                      ; Plane 1 = 0     (Color 5 bit 1)
    move.b      d3,80(a3)                   ; Plane 2 = glyph (Color 5 bit 2)
    clr.b       120(a3)                     ; Plane 3 = 0     (Color 5 bit 3)

    lea         160(a3),a3                  ; advance to next scanline (+160 bytes)
    dbra        d7,.row_loop

    addq.l      #1,a1                       ; next byte column (+8 pixels)
    bra.s       .char_loop

.done:
    POPM        d0-d5/d7/a0-a4
    rts


;==============================================================================
; Debug number formatting routines
;==============================================================================

DebugWriteString:
.str_loop:
    move.b      (a0)+,d0
    beq.s       .str_done
    move.b      d0,(a1)+
    bra.s       .str_loop
.str_done:
    rts

DebugWriteDec3:
    PUSHM       d1-d2
    and.l       #$ffff,d0
    divu.w      #100,d0                     ; d0.w = hundreds, upper word = remainder
    add.b       #'0',d0
    move.b      d0,(a1)+
    swap        d0
    and.l       #$ffff,d0
    divu.w      #10,d0                      ; d0.w = tens, upper word = units
    add.b       #'0',d0
    move.b      d0,(a1)+
    swap        d0
    add.b       #'0',d0
    move.b      d0,(a1)+
    POPM        d1-d2
    rts

DebugWriteDec2:
    PUSHM       d1
    and.l       #$ffff,d0
    divu.w      #10,d0                      ; d0.w = tens, upper word = units
    add.b       #'0',d0
    move.b      d0,(a1)+
    swap        d0
    add.b       #'0',d0
    move.b      d0,(a1)+
    POPM        d1
    rts

DebugWriteDec1:
    and.w       #15,d0
    add.b       #'0',d0
    move.b      d0,(a1)+
    rts

DebugWriteSigned2:
    tst.w       d0
    bpl.s       .pos
    move.b      #'-',(a1)+
    neg.w       d0
    bra.s       DebugWriteDec2
.pos:
    move.b      #'+',(a1)+
    bra.s       DebugWriteDec2

;==============================================================================
; DrawSprite  -  Legacy sprite blit routine (stubbed; actor_sprites.bin removed)
;==============================================================================

DrawSprite:
    rts

;==============================================================================
; TilemapErase16x16Actor  -  Restore 16x16 actor area from NonDisplayScreen
;
; Arguments:
;   d0.w = World X (0..319)
;   d1.w = World Y (0..671)
;   a5   = Variables base
;   a6   = CUSTOM base ($dff000)
; Preserves: all registers
;==============================================================================

TilemapErase16x16Actor:
    PUSHM       d0-d3/a0-a1

    ; Bounds check
    cmp.w       #0,d0
    blt         .tea_exit
    cmp.w       #320,d0
    bge         .tea_exit
    cmp.w       #0,d1
    blt         .tea_exit
    cmp.w       #672-16,d1
    bgt         .tea_exit

    ; Screen byte offset in 4-plane interleaved = (Y * 160) + ((X / 16) * 2)
    move.w      d1,d2
    mulu.w      #TILEMAP_LINE_STRIDE,d2
    moveq       #0,d3
    move.w      d0,d3
    lsr.w       #4,d3
    add.w       d3,d3
    add.l       d3,d2

    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1
    adda.l      d2,a0
    adda.l      d2,a1

    andi.w      #15,d0
    beq.s       .tea_1word

    ; 2 words wide (shifted, 32px span)
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-4,BLTAMOD(a6) ; 40 - 4 = 36
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6) ; 40 - 4 = 36
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|2,BLTSIZE(a6)
    bra.s       .tea_exit

.tea_1word:
    WAITBLIT
    move.w      #$09f0,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-2,BLTAMOD(a6) ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6) ; 40 - 2 = 38
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|1,BLTSIZE(a6)

.tea_exit:
    POPM        d0-d3/a0-a1
    rts


;==============================================================================
; DrawActor  -  Blit a moving actor tile onto DisplayScreen with shift-aware mask
;
; Used for actors that are mid-movement (XDec or YDec non-zero).
; Calculates WorldX = PrevX*16 + XDec, WorldY = PrevY*16 + YDec, and blits
; using the active level tileset raw and mask with cookie-cut minterm $0FCA.
; Also stamps foreground tiles and handles water submersion.
;
; On entry:
;   a3 = actor structure pointer
;   a5 = Variables base
;   a6 = $dff000
;==============================================================================

DrawActor:
    PUSHM       d0-d7/a0-a4

    ; Calculate World X and Y
    move.w      Actor_PrevX(a3),d0
    lsl.w       #4,d0
    add.w       Actor_XDec(a3),d0      ; d0 = World X (0..319)

    move.w      Actor_PrevY(a3),d1
    lsl.w       #4,d1
    add.w       Actor_YDec(a3),d1      ; d1 = World Y (0..671)

    ; Absolute bounds check
    cmp.w       #0,d0
    blt         .da_skip
    cmp.w       #320-16,d0
    bgt         .da_skip
    cmp.w       #0,d1
    blt         .da_skip
    cmp.w       #672-16,d1
    bgt         .da_skip

    ; Viewport Y culling: CameraCullTopY <= Y <= CameraCullBottomY
    cmp.w       CameraCullTopY(a5),d1
    blt         .da_skip
    cmp.w       CameraCullBottomY(a5),d1
    bgt         .da_skip

    ; Calculate source tile graphics and mask offsets from tileset using precomputed table
    lea         TileSheetOffsetTable,a0
    move.w      Actor_SpriteOffset(a3),d2 ; d2 = tile index (e.g. 37)
    and.w       #63,d2                    ; safety clamp
    add.w       d2,d2                     ; word offset
    move.w      (a0,d2.w),d2
    ext.l       d2                        ; d2 = byte offset in tileset

    move.l      CurrentLevelDef(a5),d3
    beq.s       .da_legacy_ts
    movea.l     d3,a0
    movea.l     LevelDef_TilesetMsk(a0),a0
    movea.l     d3,a1
    movea.l     LevelDef_TilesetRaw(a1),a1
    bra.s       .da_ts_ready
.da_legacy_ts:
    lea         GameTilesMsk,a0
    lea         GameTilesRaw,a1
.da_ts_ready:
    adda.l      d2,a0                  ; a0 = source mask pointer
    adda.l      d2,a1                  ; a1 = source graphic pointer

    ; Destination screen address in DisplayScreen: (Y * 160) + ((X / 16) * 2)
    move.w      d1,d2
    mulu.w      #TILEMAP_LINE_STRIDE,d2
    moveq       #0,d3
    move.w      d0,d3
    lsr.w       #4,d3
    add.w       d3,d3                  ; byte column
    add.l       d3,d2

    lea         DisplayScreen,a2
    adda.l      d2,a2                  ; a2 = dest pointer in DisplayScreen

    ; Check barrel shift (X & 15)
    move.w      d0,d3
    andi.w      #15,d3
    beq.s       .da_aligned

    ; Shifted Blit (2 words wide, 32px output)
    lsl.w       #8,d3
    lsl.w       #4,d3                  ; d3 = Shift << 12
    move.w      d3,d4
    ori.w       #$0fca,d3              ; BLTCON0

    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      d4,BLTCON1(a6)
    move.l      #$ffff0000,BLTAFWM(a6)

    move.w      #TILEMAP_SHEET_BYTES-4,BLTAMOD(a6) ; 22 - 4 = 18
    move.w      #TILEMAP_SHEET_BYTES-4,BLTBMOD(a6) ; 22 - 4 = 18
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6)   ; 40 - 4 = 36
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6)   ; 40 - 4 = 36

    move.l      a0,BLTAPT(a6)          ; Mask
    move.l      a1,BLTBPT(a6)          ; Graphic
    move.l      a2,BLTCPT(a6)          ; Background
    move.l      a2,BLTDPT(a6)          ; Destination

    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|2,BLTSIZE(a6) ; 64 lines x 2 words
    bra.s       .da_post_blit

.da_aligned:
    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)

    move.w      #TILEMAP_SHEET_BYTES-2,BLTAMOD(a6) ; 22 - 2 = 20
    move.w      #TILEMAP_SHEET_BYTES-2,BLTBMOD(a6) ; 22 - 2 = 20
    move.w      #SCREEN_WIDTH_BYTE-2,BLTCMOD(a6)   ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6)   ; 40 - 2 = 38

    move.l      a0,BLTAPT(a6)          ; Mask
    move.l      a1,BLTBPT(a6)          ; Graphic
    move.l      a2,BLTCPT(a6)          ; Background
    move.l      a2,BLTDPT(a6)          ; Destination

    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|1,BLTSIZE(a6) ; 64 lines x 1 word

.da_post_blit:
    ; Stamp foreground tiles overlapping this box
    move.w      #16,d2                 ; width
    move.w      #16,d3                 ; height
    bsr         TilemapStampForegroundOverBox

    ; Submerge in water if water has reached this actor
    move.w      WaterPixelY(a5),d2
    bmi.s       .da_skip
    movea.l     a2,a0                  ; a0 = dest pointer in DisplayScreen
    move.w      #16,d7                 ; 16 scanlines
    bsr         TilemapSubmergeActor

.da_skip:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapDrawPushBlocks  -  Draw all active, settled push blocks
;
; Called every frame in GameRun before animal friends and player are drawn.
; Only settled push blocks (HasMoved=0, HasFalled=0) are drawn here;
; moving blocks are animated by ActionPlayerPush / ActionFallActors.
;
; In:  a5 = Variables base
;      a6 = CUSTOM base ($dff000)
; Preserves: a5, a6
;==============================================================================

TilemapDrawPushBlocks:
    PUSHM       d0-d7/a0-a4

    move.w      ActorCount(a5),d7
    beq         .dpb_exit
    subq.w      #1,d7
    lea         ActorList(a5),a2

.dpb_loop:
    move.l      (a2)+,a3
    tst.w       Actor_Status(a3)
    beq.s       .dpb_next
    cmp.w       #BLOCK_PUSH,Actor_Type(a3)
    bne.s       .dpb_next
    tst.w       Actor_HasFalled(a3)
    bne.s       .dpb_next
    tst.w       Actor_ImpactTick(a3)
    bne.s       .dpb_next

    ; Viewport Y culling: check if crate is within active display rows
    ; (TilemapScreenOffset - 1 <= Actor_Y <= TilemapScreenOffset + 14)
    move.w      Actor_Y(a3),d1
    move.w      TilemapScreenOffset(a5),d2
    subq.w      #1,d2
    cmp.w       d2,d1
    blt.s       .dpb_next
    add.w       #15,d2
    cmp.w       d2,d1
    bgt.s       .dpb_next

    ; Check if crate is currently moving (being pushed)
    tst.w       Actor_HasMoved(a3)
    beq.s       .dpb_check_dirty

    ; Moving push block: draw with sub-pixel offset
    bsr         DrawActor
    bra.s       .dpb_next

.dpb_check_dirty:
    tst.w       Actor_Dirty(a3)        ; skip already-drawn stationary push blocks
    beq.s       .dpb_next

    ; Draw settled push block at Actor_X, Actor_Y (stamps foreground & checks water)
    bsr         ActorDrawStatic

.dpb_next:
    dbra        d7,.dpb_loop

.dpb_exit:
    POPM        d0-d7/a0-a4
    rts

;==============================================================================
; TilemapDrawOxygen  -  Draw all active uncollected oxygen refills onto DisplayScreen
;
; In:  a5 = Variables base
;      a6 = CUSTOM chip base ($dff000)
; Preserves: a5, a6
;==============================================================================

TilemapDrawOxygen:
    PUSHM       d0-d7/a0-a4

    move.w      ActiveOxygenCount(a5),d7
    beq         .done_draw_oxygen
    subq.w      #1,d7
    lea         ActiveOxygen(a5),a4

.draw_loop:
    tst.w       ox_Collected(a4)
    beq.s       .not_collected

    ; Collected: if still drawn on DisplayScreen, erase it once
    tst.w       ox_Drawn(a4)
    beq         .next_draw
    move.w      ox_X(a4),d0
    move.w      ox_Y(a4),d1
    bsr         TilemapErase16x16Actor
    clr.w       ox_Drawn(a4)
    bra         .next_draw

.not_collected:
    ; Viewport Y culling: check if oxygen pickup is within active display rows
    ; (TilemapScreenOffset - 1 <= ox_Row <= TilemapScreenOffset + 14)
    move.w      ox_Row(a4),d1
    move.w      TilemapScreenOffset(a5),d2
    subq.w      #1,d2
    cmp.w       d2,d1
    blt         .next_draw
    add.w       #15,d2
    cmp.w       d2,d1
    bgt         .next_draw

    ; Not collected & on-screen: if already drawn, skip (do not waste blits on static pickup)
    tst.w       ox_Drawn(a4)
    bne         .next_draw

    ; Blit tile at ox_Row, ox_Col
    move.w      ox_TileId(a4),d0
    move.w      ox_Row(a4),d2
    move.w      ox_Col(a4),d3
    bsr         TilemapBlitSingleTile
    move.w      #1,ox_Drawn(a4)

    ; Re-stamp foreground over oxygen tile
    move.w      ox_X(a4),d0
    move.w      ox_Y(a4),d1
    move.w      #16,d2
    move.w      #16,d3
    bsr         TilemapStampForegroundOverBox

    ; Check water submersion (dither / wave if submerged)
    move.w      WaterPixelY(a5),d2
    bmi.s       .next_draw
    move.w      ox_X(a4),d0
    move.w      ox_Y(a4),d1
    move.w      d1,d4
    mulu.w      #TILEMAP_LINE_STRIDE,d4
    moveq       #0,d5
    move.w      d0,d5
    lsr.w       #4,d5
    add.w       d5,d5
    add.l       d5,d4
    lea         DisplayScreen,a0
    adda.l      d4,a0
    move.w      d7,-(sp)               ; preserve loop counter
    move.w      #16,d7                 ; 16 scanlines height
    move.w      WaterPixelY(a5),d2
    bsr         TilemapSubmergeActor
    move.w      (sp)+,d7

.next_draw:
    lea         ox_SIZEOF(a4),a4
    dbra        d7,.draw_loop

.done_draw_oxygen:
    POPM        d0-d7/a0-a4
    rts

