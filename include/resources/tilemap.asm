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
    clr.w       PlayerSpriteFrame(a5)

    ; Initialize on-screen debug overlay state (enabled by default)
    move.w      #1,DebugOverlayActive(a5)
    move.w      TilemapCameraY(a5),PrevDebugCameraY(a5)
    clr.w       PrevDebugDrawn(a5)

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
    move.l      a0,a1                   ; a1 = destination screen buffer
    move.l      a2,a0                   ; a0 = map pointer

    addq.l      #8,a0                   ; skip 8-byte width/height header

    ; Render all 42 rows (840 tiles) of the level map
    move.w      #TILEMAP_MAP_TILES-1,d5 ; 840-1 = 839 tiles (all 42 rows)
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

    ; Update player sprite priority if water has reached the player's row
    move.l      PlayerPtrs(a5),d0
    beq.s       .pop_exit
    movea.l     d0,a0
    cmp.w       Player_Y(a0),d1
    bgt.s       .pop_exit               ; water row d1 > player row (still below)
    move.w      #$0000,cpBPLCON2+2
    move.w      #$0000,BPLCON2(a6)

.pop_exit:
    POPM        d0-d7/a0-a2
    rts

.store_subtick:
    move.w      d0,WaterSubTick(a5)
.exit:
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
; TilemapUpdateEnemies  -  Per-frame dynamic enemy update & sub-pixel blit
;
; Sequence:
;   1. For each active enemy that was drawn previously (ei_Drawn != 0):
;      Erase previous footprint by restoring pristine rectangle from NonDisplayScreen.
;   2. Update patrol movement: ei_X += ei_Direction * ei_Speed
;      Bounce against [ei_PatrolMinX .. ei_PatrolMaxX] and invert direction.
;   3. Advance animation frame every 8 frames (0..3).
;   4. If within visible camera window, blit using sub-pixel barrel shifter (BLTCON0 shift).
;
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

TilemapUpdateEnemies:
    PUSHM       d0-d7/a0-a4

    move.w      ActiveEnemyCount(a5),d7
    beq         .done_update_enemies
    subq.w      #1,d7
    lea         ActiveEnemies(a5),a4    ; a4 = current ActiveEnemy pointer

    ; -------------------------------------------------------------------------
    ; Pass 1: Erase Previous Position from DisplayScreen (all drawn enemies)
    ; -------------------------------------------------------------------------
.erase_loop:
    tst.w       ei_Type(a4)
    beq.s       .next_erase
    tst.w       ei_Drawn(a4)
    beq.s       .next_erase
    bsr         TilemapEraseEnemy
    clr.w       ei_Drawn(a4)
.next_erase:
    lea         ei_SIZEOF(a4),a4
    dbra        d7,.erase_loop

    ; -------------------------------------------------------------------------
    ; Pass 2: Update Movement, Patrol Bounds, Animation & Draw
    ; -------------------------------------------------------------------------
    move.w      ActiveEnemyCount(a5),d7
    subq.w      #1,d7
    lea         ActiveEnemies(a5),a4

.update_draw_loop:
    tst.w       ei_Type(a4)
    beq         .next_update_draw

    ; Step 2: Update Movement & Patrol Turnaround
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
    bne.s       .draw_current_enemy
    addq.w      #1,ei_AnimFrame(a4)
    andi.w      #3,ei_AnimFrame(a4)

.draw_current_enemy:
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
    move.w      ei_AnimFrame(a4),d3
    add.w       d3,d3                   ; d3 = AnimFrame * 2 bytes
    add.l       d3,d2

    lea         EnemySpritesMsk,a0
    lea         EnemySpritesRaw,a1
    adda.l      d2,a0                   ; a0 = mask frame source
    adda.l      d2,a1                   ; a1 = raw graphic frame source

    ; Calculate destination screen address:
    ; Dest offset = (Y * 160) + ((X / 16) * 2)
    move.w      d1,d2
    mulu.w      #TILEMAP_LINE_STRIDE,d2
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

    ; Check if water level has reached the row that this enemy is on
    move.w      WaterPixelY(a5),d2      ; d2 = WaterPixelY
    bmi         .exit_draw              ; if no water (< 0), done
    move.w      d1,d3                   ; d3 = enemy Y
    add.w       #ENEMY_FRAME_HEIGHT-1,d3 ; d3 = enemy bottom scanline
    cmp.w       d2,d3                   ; compare bottom scanline with WaterPixelY
    blt         .exit_draw              ; if bottom scanline < WaterPixelY, completely dry!

    ; Water has reached this enemy: submerge enemy in DisplayScreen!
    WAITBLIT                            ; wait for blitter to finish drawing enemy

    move.w      d7,-(sp)                ; preserve caller's loop counter

    ; Check if 1 word wide (aligned) or 2 words wide (shifted)
    move.w      d0,d3
    andi.w      #15,d3
    bne.s       .submerge_2words

    ; --- 1 Word Wide (16px aligned blit) ---
    move.w      #ENEMY_FRAME_HEIGHT-1,d7 ; 16 scanlines
    movea.l     a2,a0                   ; a0 = scanline pointer in DisplayScreen
.loop_1w:
    cmp.w       d2,d1                   ; is scanline Y >= WaterPixelY?
    blt.s       .next_line_1w           ; if not, dry scanline!

    btst        #0,d1
    bne.s       .odd_1w
    ; EVEN scanline: Plane 0 OR $AAAA, Planes 1..3 AND $5555
    or.w        #$aaaa,(a0)
    and.w       #$5555,40(a0)
    and.w       #$5555,80(a0)
    and.w       #$5555,120(a0)
    bra.s       .next_line_1w

.odd_1w:
    ; ODD scanline: Plane 0 OR $5555, Planes 1..3 AND $AAAA
    or.w        #$5555,(a0)
    and.w       #$aaaa,40(a0)
    and.w       #$aaaa,80(a0)
    and.w       #$aaaa,120(a0)

.next_line_1w:
    addq.w      #1,d1                   ; next scanline Y
    lea         TILEMAP_LINE_STRIDE(a0),a0 ; next scanline in DisplayScreen (+160)
    dbra        d7,.loop_1w
    bra.s       .pop_submerge

.submerge_2words:
    ; --- 2 Words Wide (shifted blit) ---
    move.w      #ENEMY_FRAME_HEIGHT-1,d7 ; 16 scanlines
    movea.l     a2,a0                   ; a0 = scanline pointer in DisplayScreen
.loop_2w:
    cmp.w       d2,d1                   ; is scanline Y >= WaterPixelY?
    blt.s       .next_line_2w

    btst        #0,d1
    bne.s       .odd_2w
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

.odd_2w:
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

.pop_submerge:
    move.w      (sp)+,d7

.exit_draw:
    rts

.culled_enemy:
    clr.w       ei_Drawn(a4)
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
    move.l      PlayerPtrs(a5),a4          ; a4 -> active player struct
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
    bra.s       .snap_exit

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
    move.l      PlayerPtrs(a5),a4          ; a4 -> active player struct
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

    ; Refresh player hardware sprite positioning for new camera offset
    ; using the currently active animation frame (preserved across fall, ladder, walk)
    move.w      PlayerSpriteFrame(a5),d0
    bsr         ShowSprite

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
;
; Uses a blitter copy from NonDisplayScreen (pristine background) to
; DisplayScreen (active display) over the 30 scanlines where debug text was
; rendered in the previous frame.
;
; Called at the very beginning of GameRun before actor/camera updates.
;
; Destroys: none (preserves all registers)
;==============================================================================

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

    move.w      #$ffff,BLTAFWM(a6)
    move.w      #$ffff,BLTALWM(a6)
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
;   Line 1: CAM:yyy ROW:rr FINE:ff
;   Line 2: PLY: X:cc+xx Y:rr+yy
;   Line 3: ACT:a DIR:±1 ENM:ee
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

    move.l      PlayerPtrs(a5),d0
    beq         .pop_exit
    movea.l     d0,a4                       ; a4 -> active player struct

    ; -------------------------------------------------------------
    ; Line 1: CAM:yyy ROW:rr FINE:ff  (24 chars padded)
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

    move.b      #' ',(a1)+
    move.b      #' ',(a1)+
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

    move.b      #' ',(a1)+
    move.b      #' ',(a1)+
    move.b      #' ',(a1)+
    move.b      #' ',(a1)+
    clr.b       (a1)                        ; null terminate

    ; Draw Line 2 at CameraY + 11, X column 1
    lea         DebugLineBuf(a5),a0
    move.w      d6,d0
    add.w       #11,d0
    moveq       #1,d1
    bsr         DebugDrawLine

    ; -------------------------------------------------------------
    ; Line 3: ACT:a DIR:±1 ENM:ee     (24 chars padded)
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

    move.b      #' ',(a1)+
    move.b      #' ',(a1)+
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

.str_cam:   dc.b    "CAM:",0
.str_row:   dc.b    " ROW:",0
.str_fine:  dc.b    " FINE:",0
.str_ply_x: dc.b    "PLY: X:",0
.str_ply_y: dc.b    " Y:",0
.str_act:   dc.b    "ACT:",0
.str_dir:   dc.b    " DIR:",0
.str_enm:   dc.b    " ENM:",0
.str_wtr:   dc.b    " WTR:",0
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
; Plane 0 = glyph, Plane 1 = 0, Plane 2 = glyph, Plane 3 = 0 (Color 5 = $0193).
; Non-glyph pixels in cell are 0 (Color 0 = $0000 black).
;
; Destroys: none (preserves all registers)
;==============================================================================

DebugDrawLine:
    PUSHM       d0-d5/d7/a0-a3

    ; Base pointer in DisplayScreen: (Y * 160) + X + DisplayScreen
    mulu.w      #TILEMAP_LINE_STRIDE,d0     ; d0.l = 32-bit unsigned offset
    add.l       #DisplayScreen,d0
    ext.l       d1
    add.l       d1,d0
    movea.l     d0,a1                       ; a1 = target byte in DisplayScreen (Plane 0)

.char_loop:
    move.b      (a0)+,d2
    beq.s       .done

    ; Sanitize ASCII character (clamp 32..127)
    cmp.b       #32,d2
    bge.s       .chk_max
    moveq       #32,d2
.chk_max:
    cmp.b       #127,d2
    ble.s       .char_ok
    moveq       #32,d2
.char_ok:
    sub.b       #32,d2
    and.w       #$00ff,d2
    lsl.w       #3,d2                       ; d2 = (char - 32) * 8
    lea         FontData,a2
    adda.w      d2,a2                       ; a2 -> 8 bytes of glyph

    ; Render 8 scanlines for this character
    movea.l     a1,a3                       ; a3 = Plane 0 for current row
    moveq       #8-1,d7
.row_loop:
    move.b      (a2)+,d3
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
    POPM        d0-d5/d7/a0-a3
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
; DrawActor  -  Blit a moving actor tile onto DisplayScreen with shift-aware mask
;
; Used for actors that are mid-movement (XDec or YDec non-zero).  The actor's
; pixel position is computed from PrevX/Y + XDec/YDec (smooth animation position).
;
; On entry:
;   a3 = actor structure pointer (for PrevX, PrevY, XDec, YDec, SpriteOffset)
;   a5 = Variables base (for TilesetPtr)
;   a6 = $dff000
;==============================================================================

DrawActor:
    PUSHMOST

    ; Calculate pixel position from previous tile + sub-tile decimal offset
    move.w        Actor_PrevX(a3),d0
    lsl.w         #4,d0
    add.w         Actor_XDec(a3),d0      ; d0 = X pixels (tile position + animation offset)

    move.w        Actor_PrevY(a3),d1
    sub.w         TilemapScreenOffset(a5),d1 ; relative row in visible viewport
    bmi           .da_skip
    cmp.w         #TILEMAP_VIEW_ROWS,d1
    bge           .da_skip

    lsl.w         #4,d1                  ; pixel Y = rel_row * 16
    add.w         Actor_YDec(a3),d1      ; d1 = Y pixels

    lea           DisplayScreen,a1        ; destination: static display buffer
    move.w        Actor_SpriteOffset(a3),d2  ; d2 = tile index

    ; Source pointers
    move.l        TilesetPtr(a5),a0
    lea           TileMask,a2

    mulu          #TILE_SIZE,d2
    add.w         d2,a0                  ; a0 -> tile graphic data
    add.w         d2,a2                  ; a2 -> tile mask data

    ; Destination address in DisplayScreen
    mulu          #SCREEN_STRIDE,d1
    move.w        d0,d2
    asr.w         #3,d2                  ; byte column
    add.w         d2,d1
    add.l         d1,a1

    ; Calculate shift: X mod 16
    and.w         #$f,d0

    cmp.w         #9,d0                  ; compare shift with 9
    bcs           .thin                  ; shift < 9: thin (2-word) blit

    ; --- Fat blit (shift >= 9): sprite overflows into 3 words ---
    ror.w         #4,d0                  ; pack shift into BLTCON0 shift field
    move.w        d0,d1
    or.w          #$fca,d0               ; minterm $fca = A&B | ~A&C

    WAITBLIT
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #$ffff0000,BLTAFWM(a6) ; mask: first word only, skip last (guard)
    move.l        a2,BLTAPT(a6)
    move.l        a0,BLTBPT(a6)
    move.l        a1,BLTCPT(a6)
    move.l        a1,BLTDPT(a6)
    move.w        #-2,BLTAMOD(a6)        ; source mod: -2 (3-word blit source width = 6)
    move.w        #-2,BLTBMOD(a6)
    move.w        #TILE_BLT_MOD-2,BLTCMOD(a6)
    move.w        #TILE_BLT_MOD-2,BLTDMOD(a6)
    move.w        #TILE_BLT_SIZE+1,BLTSIZE(a6) ; +1 word for the third word

    POPMOST
    rts

.thin
    ; --- Thin blit (shift 0-8): sprite fits in 2 words ---
    ror.w         #4,d0
    move.w        d0,d1
    or.w          #$fca,d0

    WAITBLIT
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #$ffffff00,BLTAFWM(a6) ; first word all valid; last word: zero padding byte
    move.l        a2,BLTAPT(a6)
    move.l        a0,BLTBPT(a6)
    move.l        a1,BLTCPT(a6)
    move.l        a1,BLTDPT(a6)
    move.w        #0,BLTAMOD(a6)
    move.w        #0,BLTBMOD(a6)
    move.w        #TILE_BLT_MOD,BLTCMOD(a6)
    move.w        #TILE_BLT_MOD,BLTDMOD(a6)
    move.w        #TILE_BLT_SIZE,BLTSIZE(a6)

.da_skip:
    POPMOST
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

