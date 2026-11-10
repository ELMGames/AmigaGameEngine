;==============================================================================
; AMIGA GAME ENGINE - SPRITE-SHEET TILE BLIT (reference / future-use)
; tile_renderer.asm
;==============================================================================
;
; Not included by the game's build. Duck Rescue draws its one sprite effect,
; the landing dust puff, through GameActorImpactHook with the shared BOB core
; in bob_compositor.asm instead.
; Kept here deliberately for a future game to build on.
;
; This file used to also contain a second, independent implementation of
; the level-wipe transition (LevelTransitionRun/LevelSetup/LevelRevealSetup),
; tile/wall/ladder/shadow blitting (DrawTile, DrawWalls, DrawLadders,
; DrawShadows, PasteTile), and UI button/level-counter rendering
; (DrawButton, DrawLevelCounter) — all duplicate, superseded by the live
; versions in engine/gameplay/levelutils.asm, engine/graphics/tmx_renderer.asm,
; and engine/graphics/screenutils.asm. That dead content was removed; only
; DrawSprite — which has no live equivalent — remains.
;
; IMPORTANT — DrawSprite is currently INCOMPLETE, not just unwired. It
; references four symbols that do not exist anywhere in this codebase, past
; or present:
;   TILE_SIZE          - byte size of one ActorSprites[] entry (undefined)
;   TILE_HEIGHT         - row count of one ActorSprites[] entry (undefined;
;                         from the comments below this is a 24x24 sprite,
;                         NOT the tilemap's 16px TILEMAP_TILE_HEIGHT)
;   ActorSprites        - Chip RAM sprite-sheet buffer (never declared)
;   SpriteMaskScratch    - 480-byte Chip RAM scratch buffer (never declared)
; A game that wants to use this must define all four (plus populate
; ActorSprites with real graphics data) before this will assemble. The
; minterm/BLTCON mechanics and TILE_BLT_MOD/TILE_BLT_SIZE constants it also
; uses are unaffected — those already exist in engine/include/engine_const.i.
;==============================================================================

;==============================================================================
; DrawSprite  -  Blit a sprite tile from ActorSprites[] onto DisplayScreen with masking
;
; Similar to PasteTile but reads from ActorSprites (actor sprite sheet) rather than
; TileSet.  The blitter mask is computed on-the-fly into SpriteMaskScratch (480
; bytes chip RAM) rather than sourced from a pre-built 26 KB buffer.
;
; On entry:
;   d0 = pixel X position
;   d1 = pixel Y position
;   d2 = tile index in sprite sheet
;
; The blit uses minterm $fca (A&B | ~A&C): mask selects between sprite (B)
; and background (C), producing transparent blitting.
;
; d3 and d4 are used as loop scratch so d0=X, d1=Y, d2=byte_offset survive the
; mask computation without a stack peek.
;
; Handles thin (shift 0-8: 2 words) and fat (shift 9-15: 3 words) cases:
;   Thin  (shift 0-8):  24px fits in 2 output words; modulos 0 / TILE_BLT_MOD
;   Fat   (shift >= 9): sprite overflows into 3rd word; modulos -2 / TILE_BLT_MOD-2
;
; Destroys: a0-a1 (preserves d0-d7, a2-a6)
;==============================================================================

DrawSprite:
    PUSHM         d0-d4/a2              ; save d0=X, d1=Y, d2=tile_idx; d3,d4 scratch

    mulu          #TILE_SIZE,d2         ; d2 = byte offset into ActorSprites (d0=X, d1=Y untouched)
    lea           ActorSprites,a0
    add.l         d2,a0                 ; a0 -> start of tile data

    ; WAITBLIT before writing SpriteMaskScratch — the previous blit may still
    ; be reading it.  Doing this here (before the CPU mask loop) also ensures
    ; the blitter is idle when we later write the hardware registers.
    WAITBLIT

    ; Compute blitter mask for this tile into SpriteMaskScratch (CPU loop).
    ; Each of the TILE_HEIGHT rows: OR the 5 plane longwords -> replicate x 5.
    ; d3 = loop counter, d4 = mask accumulator.  d0=X, d1=Y, d2=byte_offset untouched.
    lea           SpriteMaskScratch,a2
    moveq         #TILE_HEIGHT-1,d3
.computemask
    move.l        (a0)+,d4
    or.l          (a0)+,d4
    or.l          (a0)+,d4
    or.l          (a0)+,d4
    or.l          (a0)+,d4              ; d4 = mask row: 1 wherever any plane is non-zero
    move.l        d4,(a2)+
    move.l        d4,(a2)+
    move.l        d4,(a2)+
    move.l        d4,(a2)+
    move.l        d4,(a2)+
    dbra          d3,.computemask

    ; d0=X, d1=Y, d2=byte_offset all preserved through the loop — no stack peek needed.
    lea           ActorSprites,a0
    add.l         d2,a0                 ; a0 -> sprite tile (reuse saved byte offset)
    lea           SpriteMaskScratch,a2  ; a2 -> freshly computed mask (from start)
    lea           DisplayScreen,a1

    ; Calculate destination address in DisplayScreen
    mulu          #SCREEN_STRIDE,d1     ; row offset (all planes)
    move.w        d0,d2
    asr.w         #3,d2                 ; byte column = X / 8
    add.w         d2,d1
    add.l         d1,a1                 ; a1 -> pixel row start in screen

    ; Calculate blitter shift amount (X mod 16); WAITBLIT already done above
    and.w         #$f,d0                ; d0 = X AND 15  (0 = aligned, 1-15 = shifted)
    ror.w         #4,d0                 ; pack shift into bits 15:12 for BLTCON0
    move.w        d0,d1
    or.w          #MINTERM_COOKIE_CUT,d0              ; d0 = BLTCON0: shift + minterm A&B|~A&C
    cmp.w         #$9000,d1             ; shift 0-8: 24px fits in 2 words; shift 9-15: needs 3
    bcs           .twowords             ; shift < 9: 2-word blit

    ; Fat blit (3 words wide: shift >= 9, sprite overflows into 3rd output word)
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #$ffff0000,BLTAFWM(a6)
    move.l        a2,BLTAPT(a6)         ; A = mask (SpriteMaskScratch)
    move.l        a0,BLTBPT(a6)         ; B = sprite data
    move.l        a1,BLTCPT(a6)         ; C = destination (background)
    move.l        a1,BLTDPT(a6)         ; D = destination (output)
    move.w        #-2,BLTAMOD(a6)
    move.w        #-2,BLTBMOD(a6)
    move.w        #TILE_BLT_MOD-2,BLTCMOD(a6)
    move.w        #TILE_BLT_MOD-2,BLTDMOD(a6)
    move.w        #TILE_BLT_SIZE+1,BLTSIZE(a6)
    bra           .done

.twowords
    ; Thin blit (2 words wide: shift 0-8, 24px fits without overflowing into a 3rd word)
    ; BLTAFWM/BLTALWM = $ffff/$ffff: allow all bits in both words.
    ; Left 8 sprite pixels are in bits 15-8 of word 0 (confirmed empirically);
    ; right 8 sprite pixels are in bits 7-0 of word 1.  Both words must be fully
    ; unmasked to render the complete 24-pixel sprite.  The sprite sheet guarantees
    ; zero data in the stored-but-not-displayed 8th byte per row (TILE_WIDTHF=32
    ; stored, 24 displayed), so BLTAFWM=-1 is safe here as it is in PasteTile.
    move.w        d0,BLTCON0(a6)
    move.w        d1,BLTCON1(a6)
    move.l        #$ffffffff,BLTAFWM(a6)
    move.l        a2,BLTAPT(a6)         ; A = mask (SpriteMaskScratch)
    move.l        a0,BLTBPT(a6)         ; B = sprite data
    move.l        a1,BLTCPT(a6)         ; C = destination (background)
    move.l        a1,BLTDPT(a6)         ; D = destination (output)
    move.w        #0,BLTAMOD(a6)
    move.w        #0,BLTBMOD(a6)
    move.w        #TILE_BLT_MOD,BLTCMOD(a6)
    move.w        #TILE_BLT_MOD,BLTDMOD(a6)
    move.w        #TILE_BLT_SIZE,BLTSIZE(a6)

.done
    POPM          d0-d4/a2
    rts
