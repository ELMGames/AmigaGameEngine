;==============================================================================
; dirty_tiles.asm  -  Universal 2D Dirty-Tile Queue & Background Blitter Restoration
; AmigaGameEngine Core Reusable Performance Subsystem
; Amiga 68000 Assembly / OCS-ECS Chipset
;
; Provides O(dirty) blitter restoration and actor compositing:
;   - MarkTileDirty: Deduplicated O(1) registration into compact DirtyTileList
;   - FlushDirtyTiles: High-speed O(dirty) iteration and redraw dispatch
;   - ClearDirtyTiles: Bulk reset at level initialization
;   - RestoreTileBackground: Hardware blitter transfer from NonDisplayScreen
;     to DisplayScreen with automatic dirty queue registration
;
; PUBLIC API:
;   MarkTileDirty
;   ClearDirtyTiles
;   FlushDirtyTiles
;   RestoreTileBackground
;
; All routines preserve a5 (Variables) and a6 (CUSTOM).
;==============================================================================

    IFND WALL_PAPER_WIDTH
WALL_PAPER_WIDTH    = 14
    ENDC
    IFND WALL_PAPER_HEIGHT
WALL_PAPER_HEIGHT   = 9
    ENDC
    IFND WALL_PAPER_SIZE
WALL_PAPER_SIZE     = (WALL_PAPER_WIDTH*WALL_PAPER_HEIGHT)
    ENDC
    IFND TILE_WIDTH
TILE_WIDTH          = 24
    ENDC
    IFND TILE_HEIGHT
TILE_HEIGHT         = 24
    ENDC
    IFND SCREEN_STRIDE
    IFD TILEMAP_LINE_STRIDE
SCREEN_STRIDE       = TILEMAP_LINE_STRIDE
    ELSE
SCREEN_STRIDE       = 160
    ENDC
    ENDC

    section  main,code
    even

;==============================================================================
; MarkTileDirty  -  Flag a tile cell for end-of-frame redraw
;
; Entry: d0 = tile X (0..WALL_PAPER_WIDTH-1), d1 = tile Y (0..WALL_PAPER_HEIGHT-1)
; Preserves: all registers
;==============================================================================

MarkTileDirty:
    movem.l     d0-d2/a0-a1,-(sp)
    move.w      d1,d2
    mulu.w      #WALL_PAPER_WIDTH,d2
    add.w       d0,d2                      ; d2 = flat index
    lea         DirtyTiles(a5),a0
    tst.b       (a0,d2.w)                  ; already dirty this frame?
    bne.s       .mtd_done
    move.b      #1,(a0,d2.w)               ; mark dirty
    move.w      DirtyTileCount(a5),d2
    lsl.w       #1,d2                      ; byte offset = count * 2
    lea         DirtyTileList(a5),a1
    lsl.w       #8,d0                      ; d0.hi = tile X
    or.b        d1,d0                      ; d0.lo = tile Y
    move.w      d0,(a1,d2.w)               ; append packed word
    addq.w      #1,DirtyTileCount(a5)
.mtd_done:
    movem.l     (sp)+,d0-d2/a0-a1
    rts

;==============================================================================
; ClearDirtyTiles  -  Zero all dirty flags and reset queue count
;
; Destroys: none (preserves all registers)
;==============================================================================

ClearDirtyTiles:
    movem.l     d7/a0,-(sp)
    clr.w       DirtyTileCount(a5)
    lea         DirtyTiles(a5),a0
    move.w      #WALL_PAPER_SIZE-1,d7
.cdt_loop:
    clr.b       (a0)+
    dbra        d7,.cdt_loop
    movem.l     (sp)+,d7/a0
    rts

;==============================================================================
; FlushDirtyTiles  -  Iterate dirty tile queue and dispatch redraw callback
;
; Callback: RedrawActorAtTile (in d0=tile X, d1=tile Y)
;
; Destroys: d3-d6/a2-a4 (preserves everything else, including a5/a6)
;==============================================================================

FlushDirtyTiles:
    movem.l     d0-d2/d7/a0-a1,-(sp)

    move.w      DirtyTileCount(a5),d7
    beq.s       .fdt_exit
    clr.w       DirtyTileCount(a5)
    subq.w      #1,d7
    lea         DirtyTiles(a5),a0
    lea         DirtyTileList(a5),a1

.fdt_loop:
    move.w      (a1)+,d0                   ; packed (X<<8)|Y
    move.w      d0,d1
    and.w       #$ff,d1                    ; d1 = tile Y
    lsr.w       #8,d0                      ; d0 = tile X
    move.w      d1,d2
    mulu.w      #WALL_PAPER_WIDTH,d2
    add.w       d0,d2
    tst.b       (a0,d2.w)                  ; still dirty?
    beq.s       .fdt_next
    clr.b       (a0,d2.w)
    bsr         RedrawActorAtTile          ; dispatch game actor/proxy redraw
.fdt_next:
    dbra        d7,.fdt_loop

.fdt_exit:
    ; Optional companion avatar frozen sprite hook if present
    IFD FLUSH_COMPANION_HOOK
    bsr         FLUSH_COMPANION_HOOK
    ENDC

    movem.l     (sp)+,d0-d2/d7/a0-a1
    rts

;==============================================================================
; RestoreTileBackground  -  Blit tile from NonDisplayScreen to DisplayScreen
;
; On entry:
;   d0 = tile X
;   d1 = tile Y
;   a5 = Variables base
;   a6 = CUSTOM
;
; Destroys: none (preserves all registers)
;==============================================================================

RestoreTileBackground:
    movem.l     d0-d2/a0-a1,-(sp)
    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1

    move.w      d0,d2
    mulu.w      #TILE_WIDTH,d0
    mulu.w      #TILE_HEIGHT,d1
    andi.w      #RING_BUFFER_MASK,d1

    mulu.w      #SCREEN_STRIDE,d1
    move.w      d0,d2
    asr.w       #3,d2
    add.w       d2,d1
    add.l       d1,a0
    add.l       d1,a1

    move.l      #$ffffff00,d1
    and.w       #$f,d0
    beq.s       .rtb_left
    move.l      #$00ffffff,d1

.rtb_left:
    WAITBLIT
    move.l      #$7ca<<16,BLTCON0(a6)
    move.l      d1,BLTAFWM(a6)
    move.w      #-1,BLTADAT(a6)
    move.l      a0,BLTBPT(a6)
    move.l      a1,BLTCPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #TILE_BLT_MOD,BLTBMOD(a6)
    move.w      #TILE_BLT_MOD,BLTCMOD(a6)
    move.w      #TILE_BLT_MOD,BLTDMOD(a6)
    move.w      #TILE_BLT_SIZE,BLTSIZE(a6)

    movem.l     (sp)+,d0-d2/a0-a1
    bsr         MarkTileDirty
    rts
