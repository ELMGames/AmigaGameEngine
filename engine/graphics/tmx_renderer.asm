;==============================================================================
; AMIGA GAME ENGINE
; tmx_renderer.asm  -  Multi-Layer 2D TMX Platform Tile Blitter & Camera Viewport
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
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
    clr.w         PausePaletteActive(a5)
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
    clr.w         VBlankOverrunCount(a5) ; clear multi-frame TilemapInit blitting overruns

    rts

;==============================================================================
; TilemapInit  -  Initialize the tilemap engine for the current level
;
; Uses the camera LevelInit set (TilemapCameraY), uploads the level's
; 16-colour palette into the Copper list, builds the ring buffer around the
; camera in both screen buffers, and sets up the rising water.
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

    ; --- Clear the ring buffer in NonDisplayScreen ---
    ; RING_BUFFER_ALLOC_SIZE = 81,920 bytes: 512 lines (16 rows + 16 mirror rows) * 160
    move.l      #RING_BUFFER_ALLOC_SIZE,d7
    lea         NonDisplayScreen,a0
    bsr         TurboClear

    ; Clear water state before initial ring buffer build so stale water is not applied
    move.w      #-1,WaterPixelY(a5)
    move.w      #-1,WaterCurrentRow(a5)

    ; --- Rebuild / Populate 16 rows of Ring Buffer centered on initial camera ---
    bsr         TilemapRebuildRingBuffer

    ; Initialize rising water layer state, scanlines, and timer
    bsr         TilemapInitWater

    ; Set initial camera position, ring buffer viewport, bitplanes, and Copper sky/water list
    lea         Player(a5),a4
    move.w      TilemapCameraY(a5),d1
    bsr         TilemapApplyCameraY

    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapRebuildRingBuffer  -  Populate 16 Rows of Ring Buffer Centered on Camera
;
; In: TilemapCameraY(a5) = current camera Y
; Destroys: d0-d7, a0-a4
;==============================================================================

TilemapRebuildRingBuffer:
    PUSHM       d0-d7/a0-a4
    move.l      #-1,RowMirrorSrc(a5)    ; redrawing both halves: nothing left waiting
    move.w      TilemapCameraY(a5),RowStreamPrevCamY(a5)

    ; Clear 32-row continuous buffer in NonDisplayScreen (81,920 bytes)
    move.l      #RING_BUFFER_ALLOC_SIZE,d7
    lea         NonDisplayScreen,a0
    bsr         TurboClear

    ; Populate 16 rows of Ring Buffer centered on current camera
    move.w      TilemapCameraY(a5),d0
    lsr.w       #4,d0                   ; d0 = InitialCamRow (CameraY / 16)
    move.w      d0,RingBufferTopRow(a5)
    add.w       #RING_BUFFER_ROWS-1,d0
    move.w      d0,RingBufferBotRow(a5)

    ; Render initial 16 tile rows (RingBufferTopRow .. RingBufferBotRow) into NonDisplayScreen (rows 0..15)
    lea         NonDisplayScreen,a0
    bsr         TilemapDrawInitialRingBuffer

    ; Mirror Rows 0..15 into Rows 16..31 in NonDisplayScreen (40,960 bytes: two 512-line blits)
    WAITBLIT
    move.w      #MINTERM_COPY,BLTCON0(a6)      ; D = A direct copy
    move.w      #0,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)  ; no edge masking
    move.w      #0,BLTAMOD(a6)
    move.w      #0,BLTDMOD(a6)

    ; Mirror Blit 1: 512 lines (20,480 bytes)
    lea         NonDisplayScreen,a0
    lea         (a0),a1
    adda.l      #16*TILEMAP_ROW_STRIDE,a1
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(512<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    ; Mirror Blit 2: 512 lines (20,480 bytes)
    adda.l      #512*SCREEN_WIDTH_BYTE,a0
    adda.l      #512*SCREEN_WIDTH_BYTE,a1
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(512<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    ; Fast 4-pass Blitter cloning of all 32 rows from NonDisplayScreen to DisplayScreen (81,920 bytes)
    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1

    ; Clone Pass 1: 512 lines (20,480 bytes)
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(512<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    ; Clone Pass 2: 512 lines (20,480 bytes)
    adda.l      #512*SCREEN_WIDTH_BYTE,a0
    adda.l      #512*SCREEN_WIDTH_BYTE,a1
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(512<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    ; Clone Pass 3: 512 lines (20,480 bytes)
    adda.l      #512*SCREEN_WIDTH_BYTE,a0
    adda.l      #512*SCREEN_WIDTH_BYTE,a1
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(512<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    ; Clone Pass 4: 512 lines (20,480 bytes)
    adda.l      #512*SCREEN_WIDTH_BYTE,a0
    adda.l      #512*SCREEN_WIDTH_BYTE,a1
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(512<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    ; Reapply waterline and submerged rows if water is active in this level
    bsr         TilemapRenderWaterInBuffer

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
    ; Row 0..50 screen stride offsets (Row * 2560 bytes)
    dc.l    0, 2560, 5120, 7680, 10240, 12800, 15360, 17920
    dc.l    20480, 23040, 25600, 28160, 30720, 33280, 35840, 38400
    dc.l    40960, 43520, 46080, 48640, 51200, 53760, 56320, 58880
    dc.l    61440, 64000, 66560, 69120, 71680, 74240, 76800, 79360
    dc.l    81920, 84480, 87040, 89600, 92160, 94720, 97280, 99840
    dc.l    102400, 104960, 107520, 110080, 112640, 115200, 117760, 120320
    dc.l    122880, 125440, 128000

    even

;==============================================================================
; TilemapDrawLayerRows  -  Blit rows StartRow..EndRow of a layer map into the ring buffer
;
; Each non-zero tile word is cookie-cut blitted (mask from the tileset .msk,
; image from the .raw) into the 16-row toroidal ring buffer at the row's
; buffer slot (StartRow & 15). The tileset comes from CurrentLevelDef, or
; GameTilesRaw/GameTilesMsk when no LevelDef is active. Tile index 0 is
; transparent and skipped. Blitter control registers are set once outside
; the tile loop.
;
; In:  a0 = destination screen buffer base (Chip RAM)
;      a2 = layer map (8-byte header + tile words)
;      d0.w = StartRow, d1.w = EndRow (inclusive, 0..41)
;
; Destroys: d0/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

TilemapDrawLayerRows:
    PUSHM       d2-d7/a2-a4
    move.l      a0,a1                   ; a1 = destination screen buffer base
    move.w      d0,d2
    andi.w      #RING_BUFFER_ROW_MASK,d2 ; BufferRow = StartRow & 15
    add.w       d2,d2
    add.w       d2,d2                   ; d2 = BufferRow * 4 (longword index)
    lea         TileRowStrideTable,a3
    adda.l      (a3,d2.w),a1           ; a1 = destination row pointer in ring buffer

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
    move.w      #MINTERM_COOKIE_CUT,BLTCON0(a6)
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
    lea         TileSheetOffsetTable,a4 ; a4 = tile offset table, loaded once

.tile_loop:
    ; Read tile index from map data (Big-Endian word: $00XX)
    move.w      (a0)+,d0
    beq.s       .skip_empty_tile        ; tile index 0 is transparent/empty

    ; Look up the tile's byte offset in the tileset
    add.w       d0,d0
    move.w      (a4,d0.w),d0
    ext.l       d0

    WAITBLIT
    move.l      a2,d2
    add.l       d0,d2
    move.l      d2,BLTAPT(a6)           ; Mask (Channel A)
    move.l      a3,d2
    add.l       d0,d2
    move.l      d2,BLTBPT(a6)           ; Source tile (Channel B)
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
; TilemapDrawLayerRows_DirectCopy  -  Fast Direct Copy (D=A) for Layer 0 (Scenery)
;
; Uses a 2-channel Blitter copy (A->D) instead of the 4-channel cookie-cut.
; Only for the first layer drawn onto a cleared buffer: the tiles' transparent
; pixels are colour 0, so copying them gives exactly what the cookie-cut gives
; over a cleared row, without reading a mask (A) or the background (C).
; 128 bus cycles per 16x16 tile instead of 256.
;
; In:  a0 = destination screen buffer base (Chip RAM)
;      a2 = layer map (8-byte header + tile words)
;      d0.w = StartRow, d1.w = EndRow (inclusive, 0..41)
; Destroys: d0/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

TilemapDrawLayerRows_DirectCopy:
    PUSHM       d2-d7/a2-a4
    move.l      a0,a1                   ; a1 = destination screen buffer base
    move.w      d0,d2
    andi.w      #RING_BUFFER_ROW_MASK,d2 ; BufferRow = StartRow & 15
    add.w       d2,d2
    add.w       d2,d2                   ; d2 = BufferRow * 4 (longword index)
    lea         TileRowStrideTable,a3
    adda.l      (a3,d2.w),a1           ; a1 = destination row pointer in ring buffer

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
    bmi         .done_layer_rows_dc
    clr.w       d4                      ; d4 = column counter (0..19)

    ; Configure 2-channel direct copy (A -> D)
    WAITBLIT
    move.w      #MINTERM_COPY,BLTCON0(a6) ; $09F0: channels A and D, D = A
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)  ; no edge masking
    move.w      #TILEMAP_SHEET_BYTES-TILEMAP_TILE_BYTES,BLTAMOD(a6)
    move.w      #SCREEN_WIDTH_BYTE-TILEMAP_TILE_BYTES,BLTDMOD(a6)

    ; Resolve tileset raw pointer once outside loop
    move.l      CurrentLevelDef(a5),d2
    beq.s       .td_legacy_ts_dc
    movea.l     d2,a3
    movea.l     LevelDef_TilesetRaw(a3),a3 ; a3 = tileset raw base
    bra.s       .td_ts_ready_dc
.td_legacy_ts_dc:
    lea         GameTilesRaw,a3
.td_ts_ready_dc:
    lea         TileSheetOffsetTable,a4 ; a4 = tile offset table, loaded once

.tile_loop_dc:
    ; Read the tile index from the map (one word per cell)
    move.w      (a0)+,d0
    beq.s       .skip_empty_tile_dc     ; tile index 0 is transparent/empty

    ; Look up the tile's byte offset in the tileset
    add.w       d0,d0
    move.w      (a4,d0.w),d0
    ext.l       d0

    WAITBLIT
    move.l      a3,d2
    add.l       d0,d2
    move.l      d2,BLTAPT(a6)           ; Source tile raw (Channel A)
    move.l      a1,BLTDPT(a6)           ; Destination screen (Channel D)

    ; Blit Size: 16 rows * 4 bitplanes = 64 rows, 1 word wide (16px)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|(TILEMAP_TILE_BYTES/2),BLTSIZE(a6)

.skip_empty_tile_dc:
    ; Advance destination pointer by 2 bytes (one 16px tile width)
    addq.l      #TILEMAP_TILE_BYTES,a1

    ; Check column counter
    addq.w      #1,d4
    cmp.w       #TILEMAP_VIEW_COLS,d4
    bne.s       .next_tile_dc

    ; End of row: reset column counter and advance destination pointer
    clr.w       d4
    add.l       #(TILEMAP_TILE_HEIGHT*SCREEN_WIDTH_BYTE*TILEMAP_TILE_PLANES)-SCREEN_WIDTH_BYTE,a1

.next_tile_dc:
    dbra        d5,.tile_loop_dc

.done_layer_rows_dc:
    POPM        d2-d7/a2-a4
    rts


;==============================================================================
; TilemapInitWater  -  Initialize water layer height and countdown timer
;
; Initializes WaterCurrentRow to WATER_START_ROW (40) and loads WaterTimer
; with WATER_RISE_FRAMES (10 seconds).
; Copies LevelDef_WaterMap into LiveWaterMap working buffer.
;
; Destroys: d0-d2, a0-a1 (preserves a5, a6)
;==============================================================================

TilemapBlitTileRow:
    PUSHM       d0-d5/a1-a4

    ; Calculate destination row start address:
    ; Row byte stride = 16 scanlines * 160 bytes = 2560 bytes
    andi.w      #RING_BUFFER_ROW_MASK,d1
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
    move.w      #MINTERM_COOKIE_CUT,BLTCON0(a6)
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

;==============================================================================
; TilemapBlitSingleTile  -  Cookie-cut blit a single 16x16 tile into screen buffer
;
; In:  d0.w = tile index in tileset
;      a1   = destination screen buffer address (Chip RAM)
; Destroys: d0 (preserves all other registers)
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

    ; Destination screen address: ((row & 15) * 2560) + (col * 2)
    move.w      d2,d1
    andi.w      #RING_BUFFER_ROW_MASK,d1
    add.w       d1,d1
    add.w       d1,d1                   ; row * 4
    lea         TileRowStrideTable,a0
    move.l      (a0,d1.w),d1            ; BufferRow * 2560
    moveq       #0,d0
    move.w      d3,d0
    add.w       d0,d0                   ; col * 2
    add.l       d0,d1                   ; screen offset

    lea         DisplayScreen,a1
    adda.l      d1,a1                   ; a1 = dest pointer in DisplayScreen

    WAITBLIT
    move.w      #MINTERM_COOKIE_CUT,BLTCON0(a6)      ; cookie-cut minterm $CA
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

    ; Mirror to Row + 16 in DisplayScreen so both halves of the 32-row buffer match
    adda.l      #16*TILEMAP_ROW_STRIDE,a1
    WAITBLIT
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
;   d1.w = Y pixel coordinate (world Y, 0..CurrentMapHeight*16-1)
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
;
; Destroys: none (preserves all registers)
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

    ; Check if visible window is within current ring buffer [RingBufferTopRow .. RingBufferBotRow]
    ; If RingBufferBotRow is 0, ring buffer is not initialized yet (will be initialized in TilemapInit)
    tst.w       RingBufferBotRow(a5)
    beq.s       .snap_exit

    ; Stream any newly revealed rows incrementally (only rebuilds if jump >= 16 rows)
    bsr         TilemapCheckRowStream

.snap_exit:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapCentredCameraY  -  Camera Y that centres the player in the view
;
; In:  a4 = player struct
; Out: d1.w = PlayerPixelY - CAM_CENTRE_OFFSET, clamped to
;             [LevelMinCameraY .. LevelMaxCameraY]
; Destroys: none other than d1
;==============================================================================

TilemapCentredCameraY:
    move.w      Player_Y(a4),d1
    lsl.w       #4,d1
    add.w       Player_YDec(a4),d1      ; d1 = PlayerPixelY
    sub.w       #CAM_CENTRE_OFFSET,d1
    cmp.w       LevelMinCameraY(a5),d1
    bge.s       .tccy_min_ok
    move.w      LevelMinCameraY(a5),d1
.tccy_min_ok:
    cmp.w       LevelMaxCameraY(a5),d1
    ble.s       .tccy_max_ok
    move.w      LevelMaxCameraY(a5),d1
.tccy_max_ok:
    rts


;==============================================================================
; TilemapCentreCamera  -  Centre the camera on the player and redraw the view
;
; For a jump to anywhere in the level (respawn). Moves the camera so the
; player is centred (TilemapCentredCameraY), rebuilds the ring buffer around
; the new position in both screen buffers (the rebuild also re-applies the
; current water level). Repointing the bitplanes alone is not
; enough: rows the old view never streamed would show stale buffer contents.
; The caller redraws crates and other static entities afterwards.
;
; In:  a4 = player struct
; Destroys: none (preserves all registers)
;==============================================================================

TilemapCentreCamera:
    PUSHM       d0-d7/a0-a4
    bsr         TilemapCentredCameraY   ; d1 = new camera Y
    bsr         TilemapApplyCameraY     ; store it and repoint the bitplanes
    bsr         TilemapRebuildRingBuffer ; draw the rows and water around it, both buffers
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
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapUpdateCamera:
    PUSHM       d0-d7/a0-a4
    bsr         TilemapFlushRowMirror      ; other half of last frame's new row
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
    ; d2 = TargetCameraY (clamped to LevelMin/MaxCameraY), d1 = current CameraPixelY (d1 > d2)
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
    ; d2 = TargetCameraY (clamped to LevelMin/MaxCameraY), d1 = current CameraPixelY (d1 < d2)
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
    bsr         TilemapCheckRowStream

.cam_exit:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapApplyCameraY  -  Apply New Camera Pixel Position
;
; In:  d1 = new CameraPixelY (clamped here to LevelMinCameraY..LevelMaxCameraY)
;      a4 = active player struct pointer
;
; Destroys: d0-d2/d7/a0 (preserves everything else, including a5/a6)
;==============================================================================

TilemapApplyCameraY:
    ; Clamp CameraPixelY to [LevelMinCameraY .. LevelMaxCameraY]
    cmp.w       LevelMinCameraY(a5),d1
    bge.s       .tacy_min_ok
    move.w      LevelMinCameraY(a5),d1
.tacy_min_ok:
    cmp.w       LevelMaxCameraY(a5),d1
    ble.s       .tacy_max_ok
    move.w      LevelMaxCameraY(a5),d1
.tacy_max_ok:
    ; Store new CameraPixelY
    move.w      d1,TilemapCameraY(a5)

    ; Precompute active viewport spatial culling bounds:
    move.w      d1,d0
    sub.w       #32,d0
    move.w      d0,CameraCullTopY(a5)
    move.w      d1,d0
    add.w       #248,d0
    move.w      d0,CameraCullBottomY(a5)

    ; -------------------------------------------------------------------------
    ; Continuous Viewport Buffer: Bitplane Repointing
    ; -------------------------------------------------------------------------
    ; BufferCamY = CameraPixelY & RING_BUFFER_MASK (0..255)
    move.w      d1,d0
    andi.w      #RING_BUFFER_MASK,d0    ; d0 = 0..255
    move.w      d0,RingBufferCamY(a5)

    ; Top-of-screen bitplanes in cpPlanes: DisplayScreen + (BufferCamY * 160)
    mulu.w      #TILEMAP_LINE_STRIDE,d0
    add.l       #DisplayScreen,d0
    lea         cpPlanes,a0
    move.l      #SCREEN_WIDTH_BYTE,d1
    moveq       #TILEMAP_TILE_PLANES,d7
    bsr         CopperSetPtrs

    ; Maintain TilemapScreenOffset and TilemapFineY
    move.w      TilemapCameraY(a5),d2
    lsr.w       #4,d2
    move.w      d2,TilemapScreenOffset(a5)
    move.w      d2,TilemapCurrentOffset(a5)
    move.w      TilemapCameraY(a5),d2
    and.w       #15,d2
    move.w      d2,TilemapFineY(a5)

    ; Refresh player BOB animation frame for new camera offset
    move.w      PlayerFrame(a5),d0
    bsr         GameShowPlayerHook

    ; Rebuild the Copper sky gradient for the new camera
    bsr         TilemapUpdateCopperSky
    rts


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
; PauseDesaturateColor  -  Helper: Desaturate (50%) and darken (50%) an OCS color
;
; In:   d0.w = $0RGB color (4 bits per channel)
; Out:  d0.w = desaturated and darkened $0RGB color
; Destroys: d1, d2, d3
;==============================================================================


;==============================================================================
; TilemapDrawInitialRingBuffer  -  Draw 16 Rows into Ring Buffer at Level Start
;
; Draws tile rows from RingBufferTopRow to RingBufferBotRow into NonDisplayScreen.
; In: a0 = buffer pointer (NonDisplayScreen)
; Preserves: all registers
;==============================================================================

TilemapDrawInitialRingBuffer:
    PUSHM       d2-d7/a2-a4
    move.w      RingBufferTopRow(a5),d6 ; d6 = start row
    move.w      #RING_BUFFER_ROWS-1,d7  ; loop 16 rows

.init_row_loop:
    cmp.w       CurrentMapHeight(a5),d6
    bge.s       .init_row_next          ; beyond bottom of map
    tst.w       d6
    blt.s       .init_row_next          ; above top of map

    move.w      d6,d0                   ; d0 = WorldRow
    move.l      a0,-(sp)
    bsr         TilemapRenderOneRowAllLayers ; renders WorldRow into (WorldRow & 15)
    move.l      (sp)+,a0

.init_row_next:
    addq.w      #1,d6
    dbra        d7,.init_row_loop
    POPM        d2-d7/a2-a4
    rts

;==============================================================================
; TilemapRenderOneRowAllLayers  -  Render all layers for a single tile row
;
; In: d0.w = MapRow (0..CurrentMapHeight-1)
;     a0   = buffer base (NonDisplayScreen)
; Preserves: all registers (d0-d7, a0-a4)
;==============================================================================

TilemapRenderOneRowAllLayers:
    PUSHM       d2-d7/a2-a4
    move.w      d0,d5                   ; d5 = MapRow
    movea.l     a0,a3                   ; a3 = buffer base

    move.l      CurrentLevelDef(a5),d1
    beq         .legacy_one_row
    movea.l     d1,a2

    move.w      LevelDef_LayerCount(a2),d7
    beq.s       .fallback_one_row
    move.l      LevelDef_LayerList(a2),d6
    beq.s       .fallback_one_row

    clr.w       d4                      ; d4 = layer index (0 = Background)
    subq.w      #1,d7
.layer_one_loop:
    movea.l     d6,a1
    move.l      (a1)+,d1                ; layer map pointer
    move.l      a1,d6
    tst.l       d1
    beq.s       .skip_one_layer

    movea.l     d1,a2                   ; layer map pointer
    movea.l     a3,a0                   ; buffer base
    move.w      d5,d0                   ; StartRow = MapRow
    move.w      d5,d1                   ; EndRow = MapRow
    tst.w       d4
    bne.s       .not_bg_one
    bsr         TilemapDrawLayerRows_DirectCopy ; Layer 0: fast 2-channel D=A copy
    bra.s       .skip_one_layer
.not_bg_one:
    bsr         TilemapDrawLayerRows

.skip_one_layer:
    addq.w      #1,d4
    dbra        d7,.layer_one_loop
    POPM        d2-d7/a2-a4
    rts

.fallback_one_row:
    ; Background
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_BackgroundMap(a2),d1
    beq.s       .no_bg_1
    movea.l     d1,a2
    movea.l     a3,a0
    move.w      d5,d0
    move.w      d5,d1
    bsr         TilemapDrawLayerRows_DirectCopy
.no_bg_1:
    ; Platform
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_PlatformMap(a2),d1
    beq.s       .no_plat_1
    movea.l     d1,a2
    movea.l     a3,a0
    move.w      d5,d0
    move.w      d5,d1
    bsr         TilemapDrawLayerRows
.no_plat_1:
    ; Ladder
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_LadderMap(a2),d1
    beq.s       .no_ladder_1
    movea.l     d1,a2
    movea.l     a3,a0
    move.w      d5,d0
    move.w      d5,d1
    bsr         TilemapDrawLayerRows
.no_ladder_1:
    ; Foreground
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_ForegroundMap(a2),d1
    beq.s       .no_fg_1
    movea.l     d1,a2
    movea.l     a3,a0
    move.w      d5,d0
    move.w      d5,d1
    bsr         TilemapDrawLayerRows
.no_fg_1:
    ; Water
    movea.l     CurrentLevelDef(a5),a2
    move.l      LevelDef_WaterMap(a2),d1
    beq.s       .no_water_1
    movea.l     d1,a2
    movea.l     a3,a0
    move.w      d5,d0
    move.w      d5,d1
    bsr         TilemapDrawLayerRows
.no_water_1:
    POPM        d2-d7/a2-a4
    rts

.legacy_one_row:
    lea         LevelDefaultPlatformMap,a2
    movea.l     a3,a0
    move.w      d5,d0
    move.w      d5,d1
    bsr         TilemapDrawLayerRows
    POPM        d2-d7/a2-a4
    rts

;==============================================================================
; TilemapCheckRowStream  -  On-the-fly Tile Row Streaming for Infinite Maps
;
; Checks if vertical camera scrolling crossed a 16-pixel tile boundary.
; If so, streams newly revealed tile rows into NonDisplayScreen and DisplayScreen.
; Handles multi-row scrolling and teleports seamlessly.
;
; The 216-line window spans 15 tile rows whenever CameraY & 15 is 9 or more,
; so the 16-row ring has room for one row of lookahead, not one at each end.
; The lookahead row is kept only in the direction the camera is moving. With
; a lookahead at both ends, the up and down checks would each evict the
; other's row and stream two rows on every such frame.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapCheckRowStream:
    PUSHM       d0-d7/a0-a4
    bsr         TilemapFlushRowMirror   ; finish any row still waiting

    ; Which way did the camera move since the last check?
    move.w      TilemapCameraY(a5),d7
    move.w      d7,d0
    sub.w       RowStreamPrevCamY(a5),d7 ; d7 = dy: < 0 up, > 0 down
    move.w      d0,RowStreamPrevCamY(a5)

    ; 1. Did camera scroll UP into a new tile row?
.tcrs_loop_up:
    move.w      TilemapCameraY(a5),d0
    tst.w       d7
    bpl.s       .tcrs_up_ok             ; not moving up: no lookahead above
    sub.w       #16,d0                  ; moving up: 1-row lookahead above camera
    bpl.s       .tcrs_up_ok
    clr.w       d0
.tcrs_up_ok:
    lsr.w       #4,d0                   ; d0 = TargetTopRow
    cmp.w       RingBufferTopRow(a5),d0
    bge.s       .tcrs_check_down        ; no more up streaming needed

    ; Check if camera teleported by more than buffer size (>= 16 rows)
    move.w      RingBufferTopRow(a5),d1
    sub.w       d0,d1                   ; d1 = rows moved up
    cmp.w       #RING_BUFFER_ROWS,d1
    bge.s       .tcrs_rebuild           ; jumped too far -> full rebuild

    ; Stream previous row: RingBufferTopRow - 1
    ; Update RingBufferTopRow/BotRow first so TilemapApplyWaveScanline inside
    ; TilemapStreamTileRow sees the new row as inside the active ring buffer!
    move.w      RingBufferTopRow(a5),d0
    subq.w      #1,d0
    blt.s       .tcrs_check_down        ; above top of map
    subq.w      #1,RingBufferTopRow(a5)
    subq.w      #1,RingBufferBotRow(a5)
    bsr         TilemapStreamTileRowVisible
    bra.s       .tcrs_loop_up

.tcrs_check_down:
    ; 2. Did camera scroll DOWN into a new tile row?
.tcrs_loop_down:
    move.w      TilemapCameraY(a5),d0
    add.w       #SCREEN_HEIGHT-1,d0     ; last visible line
    tst.w       d7
    ble.s       .tcrs_dn_ok             ; not moving down: no lookahead below
    add.w       #16,d0                  ; moving down: 1-row lookahead below camera
.tcrs_dn_ok:
    lsr.w       #4,d0                   ; d0 = TargetBotRow
    cmp.w       RingBufferBotRow(a5),d0
    ble.s       .tcrs_exit              ; no more down streaming needed

    ; Check if camera teleported by more than buffer size (>= 16 rows)
    move.w      d0,d1
    sub.w       RingBufferBotRow(a5),d1 ; d1 = rows moved down
    cmp.w       #RING_BUFFER_ROWS,d1
    bge.s       .tcrs_rebuild           ; jumped too far -> full rebuild

    ; Stream next row: RingBufferBotRow + 1
    ; Update RingBufferTopRow/BotRow first so TilemapApplyWaveScanline inside
    ; TilemapStreamTileRow sees the new row as inside the active ring buffer!
    move.w      RingBufferBotRow(a5),d0
    addq.w      #1,d0
    cmp.w       CurrentMapHeight(a5),d0
    bge.s       .tcrs_exit              ; beyond bottom of map
    addq.w      #1,RingBufferTopRow(a5)
    addq.w      #1,RingBufferBotRow(a5)
    bsr         TilemapStreamTileRowVisible
    bra.s       .tcrs_loop_down

.tcrs_rebuild:
    bsr         TilemapRebuildRingBuffer ; redraws the rows and re-applies the water

.tcrs_exit:
    POPM        d0-d7/a0-a4
    rts

;==============================================================================
; TilemapStreamTileRow  -  Render & Blit a Single Tile Row into Ring Buffer
;
; Draws the row into all four copies (both halves of both screens) before it
; returns. Used where the caller needs the finished row at once, such as the
; water rewind. Scrolling uses TilemapStreamTileRowVisible instead.
;
; In: d0.w = MapRow (0..CurrentMapHeight-1)
; Destroys: none (preserves all registers)
;==============================================================================

TilemapStreamTileRow:
    bsr         TilemapStreamTileRowVisible
    bra         TilemapFlushRowMirror   ; finish the other half now

;==============================================================================
; TilemapStreamTileRowVisible  -  Stream a row into the half on screen
;
; The display window starts at buffer line (CameraY & 255) and never wraps,
; so each map row is read from one half only: the base half (rows 0..15) or
; the mirror half (rows 16..31). This routine draws the row into that half of
; NonDisplayScreen, applies the water to that one copy, and copies it to the
; same half of DisplayScreen. The two copies for the other half are queued in
; RowMirrorSrc/RowMirrorDst and blitted by TilemapFlushRowMirror on the next
; frame, which spreads the work of a new row over two frames.
;
; The other half can only come into view when the camera crosses a multiple
; of 256 pixels, which takes at least a frame, and the flush runs at the start
; of every camera update, so the deferred copy is always in place in time.
;
; In: d0.w = MapRow (0..CurrentMapHeight-1)
; Destroys: none (preserves all registers)
;==============================================================================

TilemapStreamTileRowVisible:
    PUSHM       d0-d7/a0-a4
    bsr         TilemapFlushRowMirror   ; only one row can be waiting
    move.w      #DMAF_SETCLR|DMAF_BLITHOG,DMACON(a6) ; blitter priority on

    move.w      d0,d4                   ; d4 = MapRow (0..CurrentMapHeight-1)
    RASTER_BAND DEBUG_RASTER_STREAM_DRAW ; profiler: blue

    ; Which half is on screen for this row? Its line in the window is
    ; MapRow * 16 - (CameraY & ~255): 256 or more means the mirror half.
    moveq       #0,d5                   ; d5 = offset of the half drawn now
    move.w      d4,d0
    lsl.w       #4,d0                   ; d0 = row's world Y
    move.w      TilemapCameraY(a5),d1
    andi.w      #$ff00,d1               ; CameraY & ~RING_BUFFER_MASK
    sub.w       d1,d0
    cmp.w       #RING_BUFFER_HEIGHT,d0
    blt.s       .base_half
    move.l      #16*TILEMAP_ROW_STRIDE,d5
.base_half:
    lea         NonDisplayScreen,a3
    adda.l      d5,a3                   ; a3 = half of NonDisplayScreen to draw into

    move.w      d4,d7
    andi.w      #RING_BUFFER_ROW_MASK,d7 ; d7 = BufferRow (0..15)
    mulu.w      #TILEMAP_ROW_STRIDE,d7  ; d7.l = BufferRow * 2560 bytes

    ; 1. Clear this 1 tile row (2,560 bytes) using hardware Blitter
    lea         (a3,d7.l),a0
    WAITBLIT
    move.w      #$0100,BLTCON0(a6)      ; Channel D only (DEST/USED), minterm = 0 (zero fill)
    clr.w       BLTCON1(a6)
    clr.w       BLTDMOD(a6)
    move.l      a0,BLTDPT(a6)
    ; 16 scanlines * 4 bitplanes = 64 lines of 20 words = 2560 bytes
    move.w      #((16*TILEMAP_TILE_PLANES)<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    ; 2. Render all layer tiles for MapRow into that half of NonDisplayScreen
    movea.l     a3,a0
    move.w      d4,d0                   ; d0 = MapRow
    bsr         TilemapRenderOneRowAllLayers
    WAITBLIT                            ; the CPU writes the water next

    ; 3. Apply water to this one copy if the row is submerged under WaterPixelY
    move.w      WaterPixelY(a5),d2
    bmi.s       .no_row_water
    move.w      d4,d0
    lsl.w       #4,d0                   ; d0 = row start scanline
    move.w      d0,d3
    add.w       #15,d3                  ; d3 = row end scanline
    cmp.w       d2,d3
    blt.s       .no_row_water           ; entire row above water
    RASTER_BAND DEBUG_RASTER_STREAM_WATER ; profiler: white

    ; Row has submerged scanlines! Loop from max(row_start, WaterPixelY) to row_end
    cmp.w       d2,d0
    bge.s       .water_scan_loop
    move.w      d2,d0                   ; clamp start to WaterPixelY

.water_scan_loop:
    cmp.w       d3,d0
    bgt.s       .no_row_water
    move.w      d0,d6
    sub.w       d2,d6                   ; d6 = offset from WaterPixelY
    cmp.w       #4,d6
    ble.s       .apply_scan
    moveq       #4,d6                   ; d6 >= 4 -> solid blue fill
.apply_scan:
    movea.l     a3,a0
    bsr         TilemapApplyWaveScanlineTo
    addq.w      #1,d0
    bra.s       .water_scan_loop

.no_row_water:
    RASTER_BAND DEBUG_RASTER_STREAM_COPY ; profiler: magenta
    ; 4. Copy the row (2,560 bytes) to the same half of DisplayScreen
    lea         (a3,d7.l),a0
    lea         DisplayScreen,a1
    adda.l      d5,a1
    adda.l      d7,a1

    WAITBLIT
    move.w      #MINTERM_COPY,BLTCON0(a6)      ; D = A copy
    move.w      #0,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #0,BLTDMOD(a6)
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    ; 16 scanlines * 4 bitplanes = 64 lines of 20 words
    move.w      #((16*TILEMAP_TILE_PLANES)<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    ; 5. Queue the copies for the other half
    move.l      d5,d0
    add.l       d7,d0
    move.l      d0,RowMirrorSrc(a5)     ; row as drawn
    move.l      #16*TILEMAP_ROW_STRIDE,d0
    sub.l       d5,d0                   ; the other half
    add.l       d7,d0
    move.l      d0,RowMirrorDst(a5)

    move.w      #DMAF_BLITHOG,DMACON(a6) ; blitter priority off
    bsr         SetRasterLogicColor     ; back to green (or red)
    POPM        d0-d7/a0-a4
    rts

;==============================================================================
; TilemapFlushRowMirror  -  Copy a streamed row into the other half
;
; If TilemapStreamTileRowVisible left a row waiting, copies it from the half
; it was drawn in to the other half of both screens: NonDisplayScreen to
; NonDisplayScreen, and NonDisplayScreen to DisplayScreen. The other half is
; off screen, so DisplayScreen gets the clean row with nothing drawn over it.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapFlushRowMirror:
    tst.l       RowMirrorSrc(a5)
    bmi         .none                   ; -1: nothing waiting
    PUSHM       d0/a0-a1
    RASTER_BAND DEBUG_RASTER_STREAM_MIRROR ; profiler: cyan
    move.w      #DMAF_SETCLR|DMAF_BLITHOG,DMACON(a6) ; blitter priority on

    lea         NonDisplayScreen,a0
    adda.l      RowMirrorSrc(a5),a0     ; a0 -> row as drawn
    move.l      RowMirrorDst(a5),d0     ; d0 = other half's offset

    ; NonDisplayScreen -> other half of NonDisplayScreen
    lea         NonDisplayScreen,a1
    adda.l      d0,a1
    WAITBLIT
    move.w      #MINTERM_COPY,BLTCON0(a6)      ; D = A copy
    move.w      #0,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #0,BLTDMOD(a6)
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #((16*TILEMAP_TILE_PLANES)<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)

    ; NonDisplayScreen -> other half of DisplayScreen
    lea         DisplayScreen,a1
    adda.l      d0,a1
    WAITBLIT
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #((16*TILEMAP_TILE_PLANES)<<6)|(SCREEN_WIDTH_BYTE/2),BLTSIZE(a6)
    WAITBLIT

    move.l      #-1,RowMirrorSrc(a5)
    move.w      #DMAF_BLITHOG,DMACON(a6) ; blitter priority off
    bsr         SetRasterLogicColor     ; back to green (or red)
    POPM        d0/a0-a1
.none:
    rts
