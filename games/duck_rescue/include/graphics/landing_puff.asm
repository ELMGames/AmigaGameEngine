;==============================================================================
; DUCK RESCUE
; landing_puff.asm  -  Dust puff when a crate or Mia lands after a long drop
;==============================================================================
;
; A 7-frame, 16x16 smoke puff (SmokeSprites, assets/graphics/effects/
; smoke_64x32.*) drawn over the tile something has just landed on. It plays
; for IMPACT_TOTAL_TICKS frames, and only after a fall of IMPACT_MIN_ROWS
; rows or more (engine_const.i), so stepping off a single ledge stays quiet.
;
;   DrawSmokeFrame  - blit one puff frame (GameActorImpactHook: crates)
;   PlayerPuffRun   - one tick of Mia's puff, from GameDrawHook
;   PlayerPuffCancel- wipe a running puff (undo, level start)
;
; Crate puffs are timed by the engine (Actor_ImpactTick, actor_physics.asm),
; which restores and redraws the crate before calling the hook. Mia's puff is
; timed here, by PlayerPuffTick, which ActionPlayerFall starts on landing.
;
; Register convention: a4 = player structure, a5 = Variables base,
;                      a6 = CUSTOM chip base
;==============================================================================

;==============================================================================
; DrawSmokeFrame  -  Blit one smoke puff frame over a tile
;
; The sheet holds four frames per 64-pixel row, like every engine BOB sheet:
; frame f is at row f/4, word column f&3.
;
; In:  d0.w = world pixel X, d1.w = world pixel Y (top-left of the tile)
;      d2.w = frame (0..IMPACT_FRAMES-1; the high word is ignored)
; Destroys: none (preserves all registers)
;==============================================================================

DrawSmokeFrame:
    PUSHM       d0-d7/a0-a4
    moveq       #0,d4
    move.w      d2,d4                   ; d4 = frame
    moveq       #0,d3
    move.w      d4,d3
    lsr.w       #2,d3                   ; sheet row
    mulu.w      #SMOKE_ROW_STRIDE,d3    ; row byte offset
    andi.w      #3,d4
    add.w       d4,d4                   ; word column within the row
    add.l       d4,d3                   ; d3 = byte offset of the frame

    lea         SmokeSpritesMsk,a0
    lea         SmokeSpritesRaw,a1
    adda.l      d3,a0
    adda.l      d3,a1
    moveq       #SMOKE_FRAME_HEIGHT,d5
    bsr         TilemapDrawActorBOB ; a2 = destination, d4 = 0 if drawn
    tst.w       d4
    bne.s       .done                   ; off screen

    move.w      WaterPixelY(a5),d2      ; tint the puff if the flood has reached it
    bmi.s       .done
    movea.l     a2,a0
    move.w      #SMOKE_FRAME_HEIGHT,d7
    bsr         TilemapSubmergeActor

.done:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; PlayerPuffRun  -  Advance Mia's landing puff by one tick
;
; Runs from GameDrawHook, before the frame's logic, so Mia is still where the
; frame's first TilemapDrawPlayer put her. Each tick restores the puff tile,
; redraws Mia over it (the restore takes her feet with it), then draws the
; next puff frame in front of her. After the last frame only the restore and
; redraw run, which leaves the tile clean.
;
; Destroys: none (preserves all registers)
;==============================================================================

PlayerPuffRun:
    tst.w       PlayerPuffTick(a5)
    beq.s       .exit
    PUSHM       d0-d7/a0-a4

    move.w      PlayerPuffX(a5),d0
    move.w      PlayerPuffY(a5),d1
    bsr         RestoreBackgroundTile   ; wipe the previous frame
    lea         Player(a5),a4
    bsr         TilemapDrawPlayer       ; put Mia back over the restored tile
    bsr         TilemapSubmergePlayer

    moveq       #0,d2
    move.w      PlayerPuffTick(a5),d2
    subq.w      #1,d2
    divu        #IMPACT_FRAME_TICKS,d2  ; d2.w = frame
    cmp.w       #IMPACT_FRAMES,d2
    bhs.s       .finished

    move.w      PlayerPuffX(a5),d0
    lsl.w       #4,d0
    move.w      PlayerPuffY(a5),d1
    lsl.w       #4,d1
    bsr         DrawSmokeFrame
    addq.w      #1,PlayerPuffTick(a5)
    bra.s       .done

.finished:
    clr.w       PlayerPuffTick(a5)

.done:
    POPM        d0-d7/a0-a4
.exit:
    rts


;==============================================================================
; PlayerPuffCancel  -  Stop Mia's puff and wipe whatever frame is on screen
;
; Destroys: none (preserves all registers)
;==============================================================================

PlayerPuffCancel:
    tst.w       PlayerPuffTick(a5)
    beq.s       .exit
    clr.w       PlayerPuffTick(a5)
    PUSHM       d0-d1
    move.w      PlayerPuffX(a5),d0
    move.w      PlayerPuffY(a5),d1
    bsr         RestoreBackgroundTile
    POPM        d0-d1
.exit:
    rts
