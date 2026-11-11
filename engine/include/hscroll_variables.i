;==============================================================================
; AMIGA GAME ENGINE
; hscroll_variables.i  -  Constants and variables of the horizontal scroller
;==============================================================================
;
; A game that includes engine/graphics/hscroll.asm includes this file from
; its own variables.asm, after engine_variables.i, on the same rs chain.
; Before that, the game defines the size of its map and its tile sheet:
;
;   HS_MAP_ROWS         tile rows in the map (the screen buffer's height)
;   HS_MAP_COLS         tile columns in the map (the level's width)
;   HS_SHEET_COLS       tiles per row of the tile sheet
;   HS_SHEET_ROW_BYTES  bytes in one plane-row of the sheet (its width / 8)
;
; The screen buffer layout (see hscroll.asm for why it works):
;
;   world word w of scanline y, plane p, lives at
;       buffer + y * HS_LINE_STRIDE + p * HS_ROW_BYTES + 2 * (w + 2)
;
; Maps are HS_MAP_COLS x HS_MAP_ROWS words, row by row, one tile index per
; cell: the cell data of the exporter's .map files, after their 8-byte
; header. Tile indices count across the sheet from 0; 0 is empty.
;
; Each plane-row is 23 words, two more than the 21 words fetched for a
; scrolling display, so the 23 columns kept drawn (the 21 in view and one
; spare on each side) never share memory with each other.
;==============================================================================

HS_PLANES           = 4                             ; 16 colours, interleaved
HS_ROW_BYTES        = 46                            ; 23 words per plane-row
HS_LINE_STRIDE      = HS_ROW_BYTES*HS_PLANES        ; 184 bytes per scanline
HS_LINES            = HS_MAP_ROWS*16                ; scanlines in the buffer
HS_FETCH_BYTES      = 42                            ; 21 words fetched per plane-row
HS_MODULO           = HS_LINE_STRIDE-HS_FETCH_BYTES ; 142: BPL1MOD/BPL2MOD
HS_FETCH_START      = $30                           ; DDFSTRT one word early, for BPLCON1
HS_VIEW_WIDTH       = 320                           ; pixels in view
HS_DRAWN_COLS       = 23                            ; columns kept drawn: view + 2 spares
HS_BUF_SIZE         = HS_LINES*HS_LINE_STRIDE+2*HS_MAP_COLS+16 ; one screen buffer
HS_MAX_TILES        = 128                           ; tile indices 0..127

HsCameraX:          rs.w    1   ; world X of the view's left edge, in pixels
HsMaxCameraX:       rs.w    1   ; largest camera X: map width - 320
HsFirstWord:        rs.w    1   ; world word column of the first word fetched
HsDrawnLeft:        rs.w    1   ; first world column drawn in both buffers
HsDrawnRight:       rs.w    1   ; last world column drawn in both buffers
HsMapBack:          rs.l    1   ; background layer: a word per cell, 0 = empty (copied)
HsMapMid:           rs.l    1   ; platform layer: cookie-cut over it (0 = no layer)
HsMapFront:         rs.l    1   ; foreground layer: cookie-cut last, and over BOBs
HsAnimFirst:        rs.w    1   ; first tile of an animated run (e.g. a duckling)
HsAnimFrames:       rs.w    1   ; frames in the run, 0 = no animation
HsAnimPhase:        rs.w    1   ; frame shown now: every tile of the run draws as
                                ; HsAnimFirst + HsAnimPhase
HsTileOffsets:      rs.w    HS_MAX_TILES ; byte offset of each tile in HsTileSheet
