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
    ; clr.w         DebugOverlayActive(a5) ; debug overlay disabled
    ; clr.w         PrevDebugDrawn(a5)
    lea           Keys,a0
    clr.b         KEY_S(a0)
    clr.b         KEY_A(a0)
    clr.b         KEY_D(a0)
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

    ; Initialize on-screen debug overlay state (disabled)
    ; clr.w       DebugOverlayActive(a5)
    clr.w       SlowMode(a5)           ; unconditionally start in RUN mode
    clr.w       SlowModeHold(a5)
    clr.w       PrevKeyS(a5)
    ; move.w      TilemapCameraY(a5),PrevDebugCameraY(a5)
    ; clr.w       PrevDebugDrawn(a5)

    ; Load 16-color palette from LevelDef into copper palette (COLOR00..COLOR15)
    bsr         TilemapSetPalette

    ; Clear NonDisplayScreen before initial draw
    lea         NonDisplayScreen,a0
    move.l      #LEVEL_SCREEN_SIZE,d7
    bsr         TurboClear

    ; Blit the full 42-row level into NonDisplayScreen (pristine background)
    lea         NonDisplayScreen,a0
    bsr         TilemapDrawViewport

    ; Clear DisplayScreen before initial draw
    lea         DisplayScreen,a0
    move.l      #LEVEL_SCREEN_SIZE,d7
    bsr         TurboClear

    ; Blit the full 42-row level into DisplayScreen (active screen)
    lea         DisplayScreen,a0
    bsr         TilemapDrawViewport

    ; Set initial cpPlanes bitplane pointers to bottom of level (CameraPixelY)
    ; Byte offset in DisplayScreen = CameraPixelY * 160
    move.w      TilemapCameraY(a5),d0
    mulu.w      #TILEMAP_LINE_STRIDE,d0
    add.l       #DisplayScreen,d0
    lea         cpPlanes,a0
    move.l      #SCREEN_WIDTH_BYTE,d1
    moveq       #TILEMAP_TILE_PLANES,d7
    bsr         CopperSetPtrs

    ; Initialize Copper sky gradient at initial camera position
    bsr         TilemapUpdateCopperSky

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
    lea         GameTilesRaw+22528,a0
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
    beq.s       .legacy_layers
    movea.l     d0,a2

    ; Check if ordered layer list is available
    move.w      LevelDef_LayerCount(a2),d7
    beq.s       .fallback_layers
    move.l      LevelDef_LayerList(a2),d6
    beq.s       .fallback_layers

    ; --- Render all tilemap layers in TMX document order ---
    subq.w      #1,d7                   ; DBRA loop counter

.layer_loop:
    movea.l     d6,a1                   ; a1 = current pointer in LayerList
    move.l      (a1)+,d0                ; d0 = layer binary map pointer
    move.l      a1,d6                   ; advance LayerList pointer
    beq.s       .skip_layer             ; skip null map pointer

    movea.l     d0,a2                   ; a2 = map pointer for TilemapDrawLayer
    move.l      (sp),a0                 ; a0 = destination screen buffer base
    bsr.s       TilemapDrawLayer

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
    bsr.s       TilemapDrawLayer
.no_bg:

    ; --- Pass 2: Render Platform Elements Layer (cookie-cut over background) ---
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_PlatformMap(a2),d0
    beq.s       .no_plat
    movea.l     d0,a2
    move.l      (sp),a0
    bsr.s       TilemapDrawLayer
.no_plat:

    ; --- Pass 2.25: Render Ladder Layer (cookie-cut over platforms) ---
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_LadderMap(a2),d0
    beq.s       .no_ladder
    movea.l     d0,a2
    move.l      (sp),a0
    bsr.s       TilemapDrawLayer
.no_ladder:

    ; --- Pass 2.5: Render Foreground Elements Layer (cookie-cut over platforms & ladders) ---
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_ForegroundMap(a2),d0
    beq.s       .no_fg
    movea.l     d0,a2
    move.l      (sp),a0
    bsr.s       TilemapDrawLayer
.no_fg:

    ; --- Pass 3: Render Water Layer (if defined in LevelDef) ---
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_WaterMap(a2),d0
    beq.s       .no_water
    movea.l     d0,a2
    move.l      (sp),a0
    bsr.s       TilemapDrawLayer
.no_water:
    move.l      (sp)+,a0                ; pop saved destination pointer
    rts

.legacy_layers:
    ; --- Render Platform Elements Layer ---
    lea         Level_01_PlatformMap,a2
    move.l      (sp)+,a0
    bsr.s       TilemapDrawLayer
    rts

TilemapDrawLayer:
    clr.w       d0                      ; StartRow = 0
    move.w      #LEVEL_SCREEN_ROWS-1,d1 ; EndRow = 41
    ; fallthrough to TilemapDrawLayerRows

TilemapDrawLayerRows:
    move.l      a0,a1                   ; a1 = destination screen buffer base
    move.w      d0,d2
    mulu.w      #TILEMAP_ROW_STRIDE,d2  ; d2 = StartRow * 2560
    adda.l      d2,a1                   ; a1 = destination row pointer

    move.l      a2,a0                   ; a0 = map pointer base
    addq.l      #8,a0                   ; skip 8-byte width/height header
    move.w      d0,d2
    mulu.w      #TILEMAP_VIEW_COLS*2,d2 ; d2 = StartRow * 40
    adda.l      d2,a0                   ; a0 = map row pointer

    ; Render all requested rows ((EndRow - StartRow + 1) * 20 tiles)
    move.w      d1,d5
    sub.w       d0,d5
    addq.w      #1,d5
    mulu.w      #TILEMAP_VIEW_COLS,d5   ; total tiles
    subq.w      #1,d5                   ; for dbra
    bmi         .done_layer_rows
    clr.w       d4                      ; d4 = column counter (0..19)

.tile_loop:
    ; Read tile index from map data (Little-Endian word: $XX00)
    moveq       #0,d0                   ; ensure high word of d0 is clean for 32-bit DIVU.W
    move.w      (a0)+,d0
    lsr.w       #8,d0                   ; convert to clean Big-Endian ($00XX)
    beq         .skip_empty_tile        ; tile index 0 is transparent/empty

    ; Calculate row and column within the 176px wide tileset image
    ; Tileset has 11 tiles per row (176 / 16)
    divu.w      #TILEMAP_TILES_PER_ROW,d0
    clr.l       d1
    move.w      d0,d1                   ; d1.w = tileset row
    swap        d0                      ; d0.w = tileset column

    ; Byte offset in interleaved tileset:
    ; Row offset = row * (TILE_HEIGHT * BYTES_PER_ROW * PLANES) = row * (16 * 40 * 4) = row * 2560
    ; Col offset = col * (TILE_WIDTH / 8) = col * 2
    mulu.w      #TILEMAP_TILE_HEIGHT*TILEMAP_SHEET_BYTES*TILEMAP_TILE_PLANES,d1
    mulu.w      #TILEMAP_TILE_BYTES,d0

    move.l      CurrentLevelDef(a5),d2
    beq.s       .legacy_tileset
    movea.l     d2,a3
    movea.l     LevelDef_TilesetMsk(a3),a3
    movea.l     d2,a4
    movea.l     LevelDef_TilesetRaw(a4),a4
    bra.s       .tileset_ready
.legacy_tileset:
    lea         GameTilesMsk,a3      ; a3 = tile mask pointer
    lea         GameTilesRaw,a4      ; a4 = source tile graphic pointer
.tileset_ready:
    add.l       d1,a3
    add.l       d0,a3
    add.l       d1,a4
    add.l       d0,a4

    ; Wait for Blitter before writing registers
    WAITBLIT

    ; Cookie-cut minterm $CA: D = (A & B) | (~A & C)
    ; USEA | USEB | USEC | USED = $0F00, LF = $CA -> BLTCON0 = $0FCA
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)  ; no edge masking (word-aligned 16px tile)

    ; Channel Modulos:
    ; Source sheet modulo = 40 - 2 = 38 bytes
    ; Dest screen modulo  = 40 - 2 = 38 bytes
    move.w      #TILEMAP_SHEET_BYTES-TILEMAP_TILE_BYTES,BLTAMOD(a6)
    move.w      #TILEMAP_SHEET_BYTES-TILEMAP_TILE_BYTES,BLTBMOD(a6)
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTCMOD(a6)
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTDMOD(a6)

    ; Channel Pointers
    move.l      a3,BLTAPT(a6)           ; Mask (Channel A)
    move.l      a4,BLTBPT(a6)           ; Source tile (Channel B)
    move.l      a1,BLTCPT(a6)           ; Destination screen (Channel C)
    move.l      a1,BLTDPT(a6)           ; Destination screen (Channel D)

    ; Blit Size: 16 rows * 4 bitplanes = 64 rows, 1 word wide (16px)
    ; BLTSIZE = (64 << 6) | 1 = $1001
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

    WAITBLIT                            ; ensure last blit completes
.done_layer_rows:
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
    PUSHM       d0-d2/a0-a1

    ; Check if LevelDef defines a water layer
    move.l      CurrentLevelDef(a5),d0
    beq.s       .no_water
    movea.l     d0,a0
    move.l      LevelDef_WaterMap(a0),d0
    beq.s       .no_water

    ; Copy binary water map into LiveWaterMap working buffer
    ; Size is 8-byte header + 840 words = 1688 bytes = 844 words
    movea.l     d0,a0
    lea         LiveWaterMap(a5),a1
    move.w      #(8+TILEMAP_MAP_TILES*2)/2-1,d2
.copy_map:
    move.w      (a0)+,(a1)+
    dbra        d2,.copy_map

    ; Initialize top of water row and exact vertical pixel scanline
    move.w      #WATER_START_ROW,WaterCurrentRow(a5)
    move.w      #WATER_START_PIXEL_Y,WaterPixelY(a5)
    clr.w       WaterSubTick(a5)

    ; Calculate 10-second period in frames (500 frames PAL, 600 frames NTSC)
    move.w      #WATER_RISE_FRAMES,d0
    bsr         ScalePALFrames
    move.w      d0,WaterRisePeriod(a5)
    bra.s       .done

.no_water:
    move.w      #-1,WaterCurrentRow(a5)
    move.w      #-1,WaterPixelY(a5)
    clr.w       WaterSubTick(a5)
    clr.w       WaterRisePeriod(a5)

.done:
    ; Initialize sprite priority: sprites in front of playfield (dry)
    move.w      #$0024,cpBPLCON2+2
    move.w      #$0024,BPLCON2(a6)

    POPM        d0-d2/a0-a1
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
    mulu.w      #TILEMAP_ROW_STRIDE,d1
    add.l       d1,a0
    movea.l     a0,a1                   ; a1 = destination row pointer

    ; Calculate source tile graphics and mask offsets
    ; Tileset has 11 tiles per row (176 / 16)
    ext.l       d0
    divu.w      #TILEMAP_TILES_PER_ROW,d0
    clr.l       d1
    move.w      d0,d1                   ; d1.w = tileset row
    swap        d0                      ; d0.w = tileset column

    ; Byte offset in interleaved tileset:
    ; Row offset = row * 1408 (16 * 22 * 4)
    ; Col offset = col * 2
    mulu.w      #TILEMAP_TILE_HEIGHT*TILEMAP_SHEET_BYTES*TILEMAP_TILE_PLANES,d1
    mulu.w      #TILEMAP_TILE_BYTES,d0
    add.l       d1,d0                   ; d0 = total byte offset in tileset

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

    WAITBLIT                            ; wait for final blit to complete
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

    ; Advance fractional frame accumulator by 16 each frame
    ; Overall rate: 16 pixels every 10 seconds (500 PAL frames).
    ; Threshold = WaterRisePeriod * WATER_STEP_PIXELS
    move.w      WaterSubTick(a5),d0
    add.w       #16,d0
    move.w      WaterRisePeriod(a5),d1
    IFNE        WATER_STEP_PIXELS-1
    mulu.w      #WATER_STEP_PIXELS,d1
    ENDC
    cmp.w       d1,d0
    blt         .store_subtick

    ; Period elapsed for step!
    sub.w       d1,d0
    move.w      d0,WaterSubTick(a5)

    PUSHM       d0-d7/a0-a2

    ; Decrement water scanline by WATER_STEP_PIXELS (advances upwards)
    subq.w      #WATER_STEP_PIXELS,WaterPixelY(a5)
    move.w      WaterPixelY(a5),d0      ; d0 = new top scanline of water

    ; Draw the moving wave graphic: first 5 pixel rows (rows 0..4)
    ; Scanline Y + 0: Wave Line 0 (crest tips)
    move.w      d0,-(sp)
    moveq       #0,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; Scanline Y + 1: Wave Line 1 (foam & highlight)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #1,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; Scanline Y + 2: Wave Line 2 (full contour)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #2,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; Scanline Y + 3: Wave Line 3 (base highlight)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #3,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; Scanline Y + 4: Wave Line 4 (solid blue water body)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #4,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; Overwrite the prior location lines with solid blue tile
    ; (replaces prior position of the wave with solid blue water)
    moveq       #WATER_STEP_PIXELS-1,d5
.fill_prior_lines:
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #4,d6                   ; line type 4 = solid blue fill
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0
    dbra        d5,.fill_prior_lines

    ; Check if water crossed into a new tile row
    move.w      WaterPixelY(a5),d1
    lsr.w       #4,d1                   ; d1 = current row (WaterPixelY >> 4)
    cmp.w       WaterCurrentRow(a5),d1
    beq.s       .pop_exit               ; still within same tile row

    ; We crossed into a new tile row!
    move.w      d1,WaterCurrentRow(a5)

    ; Update LiveWaterMap: row d1 becomes tile 104, row d1+1 becomes tile 115
    lea         LiveWaterMap(a5),a0
    addq.l      #8,a0                   ; skip 8-byte header
    move.w      d1,d2
    mulu.w      #TILEMAP_MAP_WIDTH*2,d2
    lea         (a0,d2.w),a1            ; a1 -> row d1 in LiveWaterMap

    move.w      #TILEMAP_MAP_WIDTH-1,d3
    move.w      #(WATER_TILE_SURFACE<<8),d4 ; $6800
.fill_surface:
    move.w      d4,(a1)+
    dbra        d3,.fill_surface

    move.w      #TILEMAP_MAP_WIDTH-1,d3
    move.w      #(WATER_TILE_DEEP<<8),d4    ; $7300
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
    PUSHM       d0-d7/a0-a4

    move.w      d0,d5                   ; d5 = StartRow
    move.w      d1,d4                   ; d4 = EndRow
    move.l      a0,-(sp)                ; save destination buffer base

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
    beq.s       .skip_layer

    movea.l     d0,a2                   ; a2 = map pointer
    move.l      (sp),a0                 ; a0 = destination buffer
    move.w      d5,d0                   ; StartRow
    move.w      d4,d1                   ; EndRow
    bsr         TilemapDrawLayerRows

.skip_layer:
    dbra        d7,.layer_loop

    addq.l      #4,sp                   ; pop saved destination buffer
    POPM        d0-d7/a0-a4
    rts

.fallback_layers:
    move.l      LevelDef_BackgroundMap(a2),d0
    beq.s       .no_bg
    movea.l     d0,a2
    move.l      (sp),a0
    move.w      d5,d0
    move.w      d4,d1
    bsr         TilemapDrawLayerRows
.no_bg:
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_PlatformMap(a2),d0
    beq.s       .no_plat
    movea.l     d0,a2
    move.l      (sp),a0
    move.w      d5,d0
    move.w      d4,d1
    bsr         TilemapDrawLayerRows
.no_plat:

    ; --- Pass 2.25: Render Ladder Layer ---
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_LadderMap(a2),d0
    beq.s       .no_ladder
    movea.l     d0,a2
    move.l      (sp),a0
    move.w      d5,d0
    move.w      d4,d1
    bsr         TilemapDrawLayerRows
.no_ladder:

    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_ForegroundMap(a2),d0
    beq.s       .no_fg
    movea.l     d0,a2
    move.l      (sp),a0
    move.w      d5,d0
    move.w      d4,d1
    bsr         TilemapDrawLayerRows
.no_fg:
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_WaterMap(a2),d0
    beq.s       .no_water
    movea.l     d0,a2
    move.l      (sp),a0
    move.w      d5,d0
    move.w      d4,d1
    bsr         TilemapDrawLayerRows
.no_water:
    addq.l      #4,sp
    POPM        d0-d7/a0-a4
    rts

.legacy_layers:
    lea         Level_01_PlatformMap,a2
    move.l      (sp)+,a0
    move.w      d5,d0
    move.w      d4,d1
    bsr         TilemapDrawLayerRows
    POPM        d0-d7/a0-a4
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
    cmp.w       #LEVEL_SCREEN_ROWS-1,d3
    ble.s       .end_ok
    move.w      #LEVEL_SCREEN_ROWS-1,d3
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
    cmp.w       #TILEMAP_MAP_HEIGHT,d6
    bge.s       .rewind_done
    lea         LiveWaterMap(a5),a1
    addq.l      #8,a1
    move.w      d6,d4
    mulu.w      #TILEMAP_MAP_WIDTH*2,d4
    adda.w      d4,a1

    move.w      #TILEMAP_MAP_WIDTH-1,d7
    move.w      #(WATER_TILE_SURFACE<<8),d4
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
    WAITBLIT                            ; ensure last erase blit finishes
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
    ; (CameraY - 24 <= ei_Y <= CameraY + 224)
    move.w      ei_Y(a4),d1
    move.w      TilemapCameraY(a5),d2
    sub.w       #24,d2
    cmp.w       d2,d1
    blt.s       .enemy_offscreen
    add.w       #248,d2                 ; CameraY + 224
    cmp.w       d2,d1
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
    WAITBLIT                            ; ensure last blit finishes
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
    cmp.w       #TILEMAP_MAP_HEIGHT,d1
    bge         .rte_exit

    PUSHM       d0-d7/a0-a4

    move.w      d0,d6                   ; d6 = target Col
    move.w      d1,d7                   ; d7 = target Row

    ; -------------------------------------------------------------------------
    ; 1. Check Settled Push Blocks (Crates & Cocoons)
    ; -------------------------------------------------------------------------
    move.w      ActorCount(a5),d5
    beq.s       .rte_check_oxygen
    subq.w      #1,d5
    lea         ActorList(a5),a2
.rte_crate_loop:
    move.l      (a2)+,a3
    tst.w       Actor_Status(a3)
    beq.s       .rte_next_crate
    move.w      Actor_Type(a3),d4
    cmp.w       #BLOCK_PUSH,d4
    beq.s       .rte_is_crate
    cmp.w       #BLOCK_COCOON,d4
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

    ; Match! Blit crate/cocoon with cookie-cutter mask ($0FCA)
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
; In: a4 = ActiveEnemy pointer
; Destroys: d0-d5, a0-a3
;==============================================================================

TilemapDrawEnemySubPixel:
    move.w      ei_X(a4),d0             ; 0..319
    move.w      ei_Y(a4),d1             ; 0..671

    ; Horizontal bounds check: skip if X < 0 or X > 320 - 16
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

    ; Calculate source frame pointer in EnemySpritesRaw / EnemySpritesMsk:
    ; Source offset = (Type - 1) * ENEMY_ROW_STRIDE (512) + (AnimFrame * 2)
    move.w      ei_Type(a4),d2
    subq.w      #1,d2                   ; 0..7
    mulu.w      #ENEMY_ROW_STRIDE,d2
    moveq       #0,d3
    move.w      ei_AnimFrame(a4),d3
    add.w       d3,d3                   ; d3 = AnimFrame * 2 bytes
    add.l       d3,d2

    lea         EnemySpritesMsk,a0
    ; Check if stunned and in recovery warning window (<= 75 frames = 1.5s)
    move.w      ei_StunTimer(a4),d4
    beq.s       .use_normal_raw
    cmp.w       #ENEMY_RECOVERY_FLASH_TICKS,d4
    bgt.s       .use_normal_raw
    ; Final 1.5 seconds: flash rapidly between normal palette and pure white ($0FFF)
    btst        #2,d4                   ; alternate every 4 frames
    beq.s       .use_normal_raw
    lea         EnemySpritesWhiteRaw,a1
    bra.s       .source_ready
.use_normal_raw:
    lea         EnemySpritesRaw,a1
.source_ready:
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

    move.w      #ENEMY_SHEET_BYTES-4,BLTAMOD(a6) ; 8 - 4 = 4
    move.w      #ENEMY_SHEET_BYTES-4,BLTBMOD(a6) ; 8 - 4 = 4
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6) ; 40 - 4 = 36
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6) ; 40 - 4 = 36

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Screen background
    move.l      a2,BLTDPT(a6)           ; Screen result

    move.w      #(ENEMY_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|2,BLTSIZE(a6) ; 64 lines x 2 words
    bra.s       .record_drawn

.blit_aligned:
    ; -------------------------------------------------------------------------
    ; Word-Aligned Blit (1 word wide, 16px output):
    ; BLTCON0 = $0FCA, BLTCON1 = $0000
    ; BLTAFWM = $FFFF, BLTALWM = $FFFF
    ; A/B Modulo = 8 - 2 = 6 bytes
    ; C/D Modulo = 40 - 2 = 38 bytes
    ; -------------------------------------------------------------------------
    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)

    move.w      #ENEMY_SHEET_BYTES-2,BLTAMOD(a6) ; 8 - 2 = 6
    move.w      #ENEMY_SHEET_BYTES-2,BLTBMOD(a6) ; 8 - 2 = 6
    move.w      #SCREEN_WIDTH_BYTE-2,BLTCMOD(a6) ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6) ; 40 - 2 = 38

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Screen background
    move.l      a2,BLTDPT(a6)           ; Screen result

    move.w      #(ENEMY_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|1,BLTSIZE(a6) ; 64 lines x 1 word

.record_drawn:
    move.w      d0,ei_PrevX(a4)
    move.w      d1,ei_PrevY(a4)
    move.w      #1,ei_Drawn(a4)

    ; If stunned, draw spinning dizzy stars
    tst.w       ei_StunTimer(a4)
    beq.s       .check_submerge
    bsr         TilemapDrawDizzyStars

.check_submerge:
    ; Submerge enemy in DisplayScreen if water has reached it
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
    clr.w       ei_Drawn(a4)
    rts


;==============================================================================
; TilemapDrawDizzyStars  -  Blit animated dizzy stars over stunned enemy
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
    lsr.w       #2,d3
    andi.w      #3,d3                   ; 0..3
    add.w       d3,d3                   ; d3 = Frame * 2 bytes offset

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
    move.l      #$ffff0000,BLTAFWM(a6)

    move.w      #DIZZY_STARS_SHEET_BYTES-4,BLTAMOD(a6) ; 8 - 4 = 4
    move.w      #DIZZY_STARS_SHEET_BYTES-4,BLTBMOD(a6) ; 8 - 4 = 4
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6)       ; 40 - 4 = 36
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6)       ; 40 - 4 = 36

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

    move.w      #DIZZY_STARS_SHEET_BYTES-2,BLTAMOD(a6) ; 8 - 2 = 6
    move.w      #DIZZY_STARS_SHEET_BYTES-2,BLTBMOD(a6) ; 8 - 2 = 6
    move.w      #SCREEN_WIDTH_BYTE-2,BLTCMOD(a6)       ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6)       ; 40 - 2 = 38

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
    WAITBLIT                            ; ensure last erase blit finishes
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
    WAITBLIT                            ; ensure last erase blit finishes
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
    ; (CameraY - 24 <= fi_Y <= CameraY + 224)
    move.w      fi_Y(a4),d1
    move.w      TilemapCameraY(a5),d2
    sub.w       #24,d2
    cmp.w       d2,d1
    blt.s       .friend_offscreen
    add.w       #248,d2                 ; CameraY + 224
    cmp.w       d2,d1
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
    WAITBLIT                            ; ensure last blit finishes
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

    ; Check if X was word-aligned (2 words) or shifted (3 words)
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
; Re-blits any settled push blocks (crates/cocoons), moving push blocks,
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
    ; 1. Check Push Blocks (Crates & Cocoons)
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
    beq.s       .rpo_is_crate
    cmp.w       #BLOCK_COCOON,d0
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

    ; Match! Blit settled crate/cocoon
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
; In:  a4 = pointer to active Player struct
;      a5 = Variables base
;      a6 = CUSTOM chip base ($dff000)
; Destroys: d0-d7, a0-a4
;==============================================================================

TilemapDrawPlayer:
    tst.w       Player_Status(a4)
    beq         .culled                 ; inactive player, do not draw

    ; 1. Calculate World Pixel X: Player_X * 16 + Player_XDec
    move.w      Player_X(a4),d0
    lsl.w       #4,d0
    add.w       Player_XDec(a4),d0      ; d0 = World X (0..319)
    subq.w      #4,d0                   ; center 24px BOB over 16px tile
    bpl.s       .x_not_neg
    moveq       #0,d0
.x_not_neg:

    ; 2. Calculate World Pixel Y: Player_Y * 16 + Player_YDec - 8 (lift 8px)
    move.w      Player_Y(a4),d1
    lsl.w       #4,d1
    add.w       Player_YDec(a4),d1
    subq.w      #8,d1                   ; d1 = World Y (top of 24px sprite)

    ; Adjust Y for bridge sag if walking across a bridge
    move.w      d1,-(sp)                ; preserve World Y
    move.w      d0,d1                   ; d1 = World X for GetBridgeYOffset
    bsr         GetBridgeYOffset        ; returns downward offset in d3
    move.w      (sp)+,d1                ; restore World Y
    add.w       d3,d1                   ; apply bridge sag

    ; 3. Viewport Culling & Bounds Checks
    cmp.w       #0,d0
    blt         .culled
    cmp.w       #320-24,d0
    bgt         .culled
    cmp.w       #0,d1
    blt         .culled
    cmp.w       #LEVEL_SCREEN_HEIGHT-PLAYER_HEIGHT,d1
    bgt         .culled

    ; Camera viewport culling: CameraY - 24 <= Y <= CameraY + 224
    move.w      TilemapCameraY(a5),d2
    sub.w       #PLAYER_HEIGHT,d2
    cmp.w       d2,d1
    blt         .culled
    add.w       #216+PLAYER_HEIGHT+24,d2
    cmp.w       d2,d1
    bgt         .culled

    ; 4. Calculate Source Frame Pointer in PlayerRaw / PlayerMsk
    ; Frame index = Player_BobOffset + PlayerFrame
    move.w      Player_BobOffset(a4),d2
    add.w       PlayerFrame(a5),d2   ; d2 = frame index (0..95)

    ; Row = d2 >> 2 (div 4), Col = d2 & 3
    moveq       #0,d3
    move.w      d2,d3
    lsr.w       #2,d3                   ; d3 = frame row (0..23)
    mulu.w      #PLAYER_FRAME_STRIDE,d3 ; d3 = row byte offset (Row * 24 * 64 = Row * 1536)

    moveq       #0,d4
    move.w      d2,d4
    andi.w      #3,d4                   ; d4 = col (0..3)
    lsl.w       #2,d4                   ; d4 = col * 4 bytes (32px cel = 4 bytes per plane)
    add.l       d4,d3                   ; d3 = total source byte offset

    ; Check if facing left (and not on ladder - ladder is rear view):
    tst.w       Player_OnLadder(a4)
    bne.s       .draw_right
    tst.w       Player_Facing(a4)
    bpl.s       .draw_right

    ; --- Facing Left: use flipped sprites in Chip RAM ---
    lea         PlayerLeftMsk,a0
    tst.w       PlayerInvincibleTimer(a5)
    beq.s       .left_normal
    btst        #2,TickCounter+1(a5)    ; flash every 4 frames
    beq.s       .left_normal
    lea         PlayerLeftWhiteRaw,a1   ; white flash silhouette
    bra.s       .ptrs_ready
.left_normal:
    lea         PlayerLeftRaw,a1
    bra.s       .ptrs_ready

.draw_right:
    lea         PlayerMsk,a0
    ; Check if flashing white on respawn (invulnerability active)
    tst.w       PlayerInvincibleTimer(a5)
    beq.s       .right_normal
    btst        #2,TickCounter+1(a5)    ; flash every 4 frames
    beq.s       .right_normal
    lea         PlayerWhiteRaw,a1       ; white flash silhouette!
    bra.s       .ptrs_ready
.right_normal:
    lea         PlayerRaw,a1
.ptrs_ready:
    adda.l      d3,a0                   ; a0 = mask source
    adda.l      d3,a1                   ; a1 = raw graphic source

    ; 5. Calculate Destination Screen Address
    ; Dest offset = (Y * 160) + ((X / 16) * 2)
    move.w      d1,d2
    mulu.w      #TILEMAP_LINE_STRIDE,d2
    moveq       #0,d3
    move.w      d0,d3
    lsr.w       #4,d3
    add.w       d3,d3                   ; byte column
    add.l       d3,d2

    lea         DisplayScreen,a2
    adda.l      d2,a2                   ; a2 = destination in DisplayScreen

    ; 6. Check Barrel Shift (X & 15)
    move.w      d0,d3
    andi.w      #15,d3                  ; shift = 0..15
    beq.s       .blit_aligned

    ; --- 3-Word Shifted Blit (48px span) ---
    lsl.w       #8,d3
    lsl.w       #4,d3                   ; d3 = Shift << 12
    move.w      d3,d4
    ori.w       #$0fca,d3               ; d3 = BLTCON0 (USEA|B|C|D, minterm $CA)

    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      d4,BLTCON1(a6)
    move.l      #$ffff0000,BLTAFWM(a6)  ; mask out adjacent frame bleed

    move.w      #PLAYER_SHEET_BYTES-6,BLTAMOD(a6) ; 16 - 6 = 10
    move.w      #PLAYER_SHEET_BYTES-6,BLTBMOD(a6) ; 16 - 6 = 10
    move.w      #SCREEN_WIDTH_BYTE-6,BLTCMOD(a6)  ; 40 - 6 = 34
    move.w      #SCREEN_WIDTH_BYTE-6,BLTDMOD(a6)  ; 40 - 6 = 34

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Background
    move.l      a2,BLTDPT(a6)           ; Destination

    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|3,BLTSIZE(a6) ; 96 rows x 3 words
    bra.s       .record_drawn

.blit_aligned:
    ; --- 2-Word Aligned Blit (32px span) ---
    WAITBLIT
    move.w      #$0fca,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)

    move.w      #PLAYER_SHEET_BYTES-4,BLTAMOD(a6) ; 16 - 4 = 12
    move.w      #PLAYER_SHEET_BYTES-4,BLTBMOD(a6) ; 16 - 4 = 12
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6)  ; 40 - 4 = 36
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6)  ; 40 - 4 = 36

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Background
    move.l      a2,BLTDPT(a6)           ; Destination

    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|2,BLTSIZE(a6) ; 96 rows x 2 words

.record_drawn:

    move.w      d0,Player_PrevX(a4)
    move.w      d1,Player_PrevY(a4)
    move.w      #1,Player_PrevDrawn(a4)

    ; 7. Foreground Layer Stamp (in front of Player BOB)
    ; Check if any foreground tiles in LevelDef_ForegroundMap overlap player bounding box
    bsr         TilemapStampForegroundOverPlayer

    ; 8. Water Submersion Check
    move.w      WaterPixelY(a5),d2      ; d2 = WaterPixelY
    bmi.s       .exit                   ; if no water (< 0), dry
    movea.l     a2,a0                   ; a0 = destination in DisplayScreen
    move.w      #PLAYER_HEIGHT,d7       ; 24 scanlines
    bsr         TilemapSubmergeActor

.exit:
    rts

.culled:
    clr.w       Player_PrevDrawn(a4)
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
    cmp.w       #TILEMAP_MAP_HEIGHT-1,d5
    ble.s       .row_ok
    move.w      #TILEMAP_MAP_HEIGHT-1,d5
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

    ; Loop col by col: cur_col in d3 from d6 to d7
    move.w      d6,d3
.fg_col_loop:
    cmp.w       d7,d3
    bgt.s       .next_fg_row

    ; Calculate map tile offset: (row * 20 + col) * 2
    move.w      d2,d0
    mulu.w      #TILEMAP_VIEW_COLS,d0
    add.w       d3,d0
    add.w       d0,d0                   ; byte offset in ForegroundMap
    move.w      0(a2,d0.w),d0           ; read Little-Endian word
    lsr.w       #8,d0                   ; clean Big-Endian tile index (0..255)
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

    ; Calculate source tile graphics and mask offsets
    ; Tileset has 11 tiles per row (176 / 16)
    ext.l       d0
    divu.w      #TILEMAP_TILES_PER_ROW,d0
    clr.l       d1
    move.w      d0,d1                   ; d1.w = tileset row
    swap        d0                      ; d0.w = tileset column

    ; Source offset = (row * 1408) + (col * 2)
    mulu.w      #TILEMAP_TILE_HEIGHT*TILEMAP_SHEET_BYTES*TILEMAP_TILE_PLANES,d1
    mulu.w      #TILEMAP_TILE_BYTES,d0
    add.l       d1,d0                   ; d0 = total byte offset in tileset

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
    mulu.w      #TILEMAP_ROW_STRIDE,d1  ; row * 2560
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

    ; Bounds check Y (0..671)
    cmp.w       #0,d1
    blt.s       .out_of_bounds_solid
    cmp.w       #672,d1
    bge.s       .out_of_bounds_solid

    ; Tile Column = X / 16
    lsr.w       #4,d0                   ; d0.w = tile column (0..19)

    ; Tile Row = Y / 16
    lsr.w       #4,d1                   ; d1.w = tile row (0..41)

    ; Map index = (Row * 20 + Column) * 2
    mulu.w      #TILEMAP_MAP_WIDTH,d1
    add.w       d0,d1
    add.w       d1,d1                   ; multiply by 2 (word entries)
    addq.w      #8,d1                   ; skip 8-byte header

    lea         Level_01_CompositeMap,a0
    move.w      (a0,d1.w),d0            ; read Little-Endian tile word
    lsr.w       #8,d0                   ; convert to Big-Endian tile index ($00..$FF)

    ; Look up attribute in TileAttributesTable
    lea         TileAttributesTable,a0
    move.b      (a0,d0.w),d0            ; d0.b = attribute
    rts

.out_of_bounds_solid:
    moveq       #ATTR_SOLID,d0
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
; TilemapUpdateCopperSky  -  Update Copper Sky Gradient with 1/2 Parallax Speed
;
; Computes SkyY = TilemapCameraY >> 1 (0..232), then copies 216 words from
; CopperSkyTable[SkyY .. SkyY+215] into the cpGameSky Copper list entries.
;
; Each cpGameSky entry is 8 bytes:
;   +0: WAIT (line, $07), $fffe
;   +4: MOVE COLOR00, data (word operand at +6)
;
; Destroys: d0, d7, a0, a1
;==============================================================================

TilemapUpdateCopperSky:
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
;   ATTR_HAZARD      = 3 (hazard / spikes / acid)
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
; (Disabled to eliminate blitter erase overhead and entity clobbering)
;==============================================================================

TilemapEraseDebugOverlay:
    rts


;==============================================================================
; TilemapDrawDebugOverlay  -  Render debug statistics HUD on DisplayScreen
; (Disabled to eliminate runtime overhead)
;==============================================================================

TilemapDrawDebugOverlay:
    rts


; (DebugDrawLine and formatting routines removed)

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

    ; Viewport Y culling: CameraY - 16 <= Y <= CameraY + 224
    move.w      TilemapCameraY(a5),d2
    sub.w       #16,d2
    cmp.w       d2,d1
    blt         .da_skip
    add.w       #240,d2                 ; CameraY - 16 + 240 = CameraY + 224
    cmp.w       d2,d1
    bgt         .da_skip

    ; Calculate source tile graphics and mask offsets from tileset
    move.w      Actor_SpriteOffset(a3),d2 ; d2 = tile index (e.g. 37)
    ext.l       d2
    divu.w      #TILEMAP_TILES_PER_ROW,d2 ; 11 tiles per row
    clr.l       d3
    move.w      d2,d3                  ; d3.w = tileset row
    swap        d2                     ; d2.w = tileset col

    ; Source offset = (row * 1408) + (col * 2)
    mulu.w      #TILEMAP_TILE_HEIGHT*TILEMAP_SHEET_BYTES*TILEMAP_TILE_PLANES,d3
    mulu.w      #TILEMAP_TILE_BYTES,d2
    add.l       d3,d2                  ; d2 = byte offset in tileset

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
    WAITBLIT
    POPM        d0-d7/a0-a4
    rts

;==============================================================================
; PasteTile  -  Blit a tile from TileSet onto a screen buffer with masking
;
; On entry:
;   d0 = X pixel position
;   d1 = Y pixel position
;   d2 = tile index (0..TILESET_COUNT-1)
;   a1 = pointer to screen buffer (NonDisplayScreen or DisplayScreen)
;   a5 = Variables base (for TilesetPtr)
;   a6 = $dff000
;==============================================================================

PasteTile:
    PUSHM         d0-d2/a2

    move.l        TilesetPtr(a5),a0      ; source: tile set
    lea           TileMask,a2            ; mask source

    mulu          #TILE_SIZE,d2
    add.w         d2,a0                  ; a0 -> selected tile graphic
    add.w         d2,a2                  ; a2 -> selected tile mask

    ; Destination address in screen buffer
    mulu          #SCREEN_STRIDE,d1
    move.w        d0,d2
    asr.w         #3,d2                  ; byte column = X / 8
    add.w         d2,d1
    add.l         d1,a1                  ; a1 -> destination pixel

    ; Shift: X mod 16
    and.w         #$f,d0
    ror.w         #4,d0                  ; pack into BLTCON0 shift field
    move.w        d0,d1
    or.w          #$fca,d0               ; minterm $fca = masked copy

    WAITBLIT
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #-1,BLTAFWM(a6)        ; all bits valid in A
    move.l        a2,BLTAPT(a6)          ; A = tile mask
    move.l        a0,BLTBPT(a6)          ; B = tile graphic
    move.l        a1,BLTCPT(a6)          ; C = current screen content
    move.l        a1,BLTDPT(a6)          ; D = output
    move.w        #0,BLTAMOD(a6)         ; source (tile) modulo: 0 (tight packing)
    move.w        #0,BLTBMOD(a6)
    move.w        #TILE_BLT_MOD,BLTCMOD(a6)  ; screen modulo
    move.w        #TILE_BLT_MOD,BLTDMOD(a6)
    move.w        #TILE_BLT_SIZE,BLTSIZE(a6)

    POPM          d0-d2/a2
    rts

