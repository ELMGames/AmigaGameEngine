;==============================================================================
; AMIGA GAME ENGINE
; bob_compositor.asm  -  2D BOB Compositor & Background Restorer
;==============================================================================
;==============================================================================
; TilemapEraseActorBOB  -  Shared erase core for 16x16 enemy/friend BOBs
;
; Shared by TilemapEraseEnemy and TilemapEraseFriend, which are identical
; apart from which struct's Prev*/SIZEOF fields they read (different struct
; layouts, so field access can't be shared directly) and which FrameHeight
; constant they use (numerically identical today, but passed at runtime
; rather than assumed, so the two stay independently correct if one ever
; changes). Restores pristine background from NonDisplayScreen under the
; actor's previous blit position, then re-applies water submersion tinting
; if the restored area is still underwater.
;
; In:  d0 = PrevX, d1 = PrevY
;      d5 = FrameHeight in pixels (e.g. ENEMY_FRAME_HEIGHT / FRIEND_FRAME_HEIGHT)
;      a5 = Variables base, a6 = CUSTOM chip base
; Destroys: d2-d5, a0-a2 (a4, a6, d6, d7 preserved; d0, d1 preserved)
;==============================================================================

TilemapEraseActorBOB:
    ; Screen byte offset in continuous buffer
    move.w      RingBufferCamY(a5),d2
    add.w       d1,d2
    sub.w       TilemapCameraY(a5),d2   ; d2 = BufferScanline
    bmi         .tea_exit_culled
    move.w      d5,d3
    neg.w       d3
    add.w       #RING_BUFFER_ALLOC_LINES,d3 ; d3 = RING_BUFFER_ALLOC_LINES - FrameHeight
    cmp.w       d3,d2
    bgt         .tea_exit_culled

    move.w      d2,d3
    LINE_OFFSET d3,d4               ; d3 = line * 160
    moveq       #0,d4
    move.w      d0,d4
    lsr.w       #4,d4
    add.w       d4,d4                   ; byte column
    add.l       d4,d3                   ; d3 = total byte offset

    lea         NonDisplayScreen,a0
    lea         DisplayScreen,a1
    adda.l      d3,a0                   ; source (pristine background)
    adda.l      d3,a1                   ; dest (active display)

    ; Check if X is word-aligned (d0 & 15 == 0) -> 1 word wide, else 2 words wide
    move.w      d0,d3
    and.w       #15,d3
    beq.s       .erase_1word_actorbob

    ; 2-word wide restore (32px span across bitplanes)
    WAITBLIT
    move.w      #MINTERM_COPY,BLTCON0(a6)      ; D = A (direct copy)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-4,BLTAMOD(a6) ; 40 - 4 = 36 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6) ; 40 - 4 = 36 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      d5,d4
    mulu.w      #TILEMAP_TILE_PLANES,d4
    lsl.w       #6,d4
    or.w        #2,d4
    move.w      d4,BLTSIZE(a6)          ; FrameHeight*4 lines x 2 words
    bra.s       .check_submerge_actorbob

.erase_1word_actorbob:
    WAITBLIT
    move.w      #MINTERM_COPY,BLTCON0(a6)      ; D = A
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-2,BLTAMOD(a6) ; 40 - 2 = 38 bytes
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6) ; 40 - 2 = 38 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      d5,d4
    mulu.w      #TILEMAP_TILE_PLANES,d4
    lsl.w       #6,d4
    or.w        #1,d4
    move.w      d4,BLTSIZE(a6)          ; FrameHeight*4 lines x 1 word

.check_submerge_actorbob:
    move.w      WaterPixelY(a5),d2
    bmi.s       .tea_exit_culled
    move.w      d1,d3
    add.w       d5,d3
    subq.w      #1,d3
    cmp.w       d2,d3
    blt.s       .tea_exit_culled
    WAITBLIT
    movea.l     a1,a0
    move.w      d7,-(sp)
    move.w      d5,d7
    bsr         TilemapSubmergeActor
    move.w      (sp)+,d7
.tea_exit_culled:
    rts


;==============================================================================
; TilemapDrawActorBOB  -  Shared cookie-cut blit core for
;                                 16x16 enemy/friend BOBs
;
; Shared by TilemapDrawEnemy and TilemapDrawFriend. Each
; wrapper resolves its own per-type source frame pointers (the enemy wrapper
; additionally picks the stun-flash white-silhouette source here) before
; calling, then performs its own per-type post-blit step (dizzy stars for
; enemies, the foreground stamp for friends) and records Prev*/Drawn into
; its own struct afterward, since enemy and friend structs have different
; field layouts and can't be addressed generically here.
;
;   - Pixel-accurate horizontal positioning via blitter barrel shifter (BLTCON0/1 shift bits)
;   - Camera viewport culling (8px headroom beyond the 216-scanline window)
;   - Cookie-cutter minterm $0FCA masking over screen background
;
; In:  d0 = X (0..319)        d1 = Y
;      d5 = FrameHeight in pixels (e.g. ENEMY_FRAME_HEIGHT / FRIEND_FRAME_HEIGHT)
;      a0 = mask source pointer, pre-offset to the correct frame
;      a1 = raw graphic source pointer, pre-offset to the correct frame
;      a5 = Variables base, a6 = CUSTOM chip base
;
; Out: d4 = 0 if a blit was performed (a2 = dest address in DisplayScreen,
;           for the caller's own submerge check; d0, d1 unchanged)
;      d4 = 1 if culled (nothing blitted; caller should clear its own
;           *_Drawn flag and return without further work)
;
; Destroys: d2-d5, a0-a3 (a4, a6, d6, d7 preserved; d0, d1 preserved)
;==============================================================================

TilemapDrawActorBOB:
    ; Horizontal bounds check: clamp to valid display columns (0 .. 320 - 16)
    cmp.w       #0,d0
    blt         .culled_actorbob
    cmp.w       #320-16,d0
    bgt         .culled_actorbob

    ; Top bounds check: Y < 0 is off-map; viewport culling handles dynamic height
    cmp.w       #0,d1
    blt         .culled_actorbob

    ; Viewport Y culling: CameraY - 24 <= Y <= CameraY + 224 (8px headroom
    ; above/below the 216-line viewport so a 16px actor is fully off-screen
    ; before being removed)
    move.w      TilemapCameraY(a5),d2
    sub.w       #24,d2
    cmp.w       d2,d1
    blt         .culled_actorbob
    add.w       #248,d2
    cmp.w       d2,d1
    bgt         .culled_actorbob

    ; Destination address calculation in continuous ring buffer
    move.w      RingBufferCamY(a5),d2
    add.w       d1,d2
    sub.w       TilemapCameraY(a5),d2   ; d2 = BufferScanline
    bmi         .culled_actorbob
    move.w      d5,d3
    neg.w       d3
    add.w       #RING_BUFFER_ALLOC_LINES,d3 ; d3 = RING_BUFFER_ALLOC_LINES - FrameHeight
    cmp.w       d3,d2
    bgt         .culled_actorbob
    LINE_OFFSET d2,d3               ; d2 = line * 160
    moveq       #0,d3
    move.w      d0,d3
    lsr.w       #4,d3
    add.w       d3,d3                   ; byte column
    add.l       d3,d2

    lea         DisplayScreen,a2
    adda.l      d2,a2                   ; a2 = dest address in DisplayScreen

    ; Blitter Execution: Minterm $0FCA Cookie-Cutter
    ; D = (A AND B) OR ((NOT A) AND C)
    ;   Channel A: Mask    Channel B: Graphic
    ;   Channel C: Screen background    Channel D: Screen output
    ; Barrel shifter: Shift = X & 15.
    move.w      d0,d3
    andi.w      #15,d3                  ; d3 = shift (0..15)
    beq.s       .blit_aligned_actorbob

    ; --- Shifted Blit (2 words wide, 32px output span) ---
    ; BLTAFWM = $FFFF, BLTALWM = $0000: masks Word 2 of Channel A to 0 before
    ; the shifter, so no bits from adjacent sprite sheet frames leak in,
    ; while Word 1's shifted bits pass through to Word 2 cleanly.
    BLTSHIFT12  d3                   ; d3 = Shift << 12
    move.w      d3,d4
    ori.w       #MINTERM_COOKIE_CUT,d3               ; d3 = BLTCON0

    WAITBLIT
    move.w      d3,BLTCON0(a6)
    move.w      d4,BLTCON1(a6)
    move.l      #$ffff0000,BLTAFWM(a6)  ; BLTAFWM = $ffff, BLTALWM = $0000

    move.w      #ACTOR_BOB_SHEET_BYTES-4,BLTAMOD(a6) ; 8 - 4 = 4 bytes
    move.w      #ACTOR_BOB_SHEET_BYTES-4,BLTBMOD(a6) ; 8 - 4 = 4 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTCMOD(a6)     ; 40 - 4 = 36 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6)     ; 40 - 4 = 36 bytes

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Screen background
    move.l      a2,BLTDPT(a6)           ; Screen result

    move.w      d5,d4
    mulu.w      #TILEMAP_TILE_PLANES,d4
    lsl.w       #6,d4
    or.w        #2,d4
    move.w      d4,BLTSIZE(a6)          ; FrameHeight*4 lines, width = 2 words
    bra.s       .drawn_actorbob

.blit_aligned_actorbob:
    ; --- Word-Aligned Blit (1 word wide, 16px output span) ---
    ; Shift = 0: exactly 1 word fits on 16-pixel tile boundary.
    WAITBLIT
    move.w      #MINTERM_COOKIE_CUT,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)

    move.w      #ACTOR_BOB_SHEET_BYTES-2,BLTAMOD(a6) ; 8 - 2 = 6 bytes
    move.w      #ACTOR_BOB_SHEET_BYTES-2,BLTBMOD(a6) ; 8 - 2 = 6 bytes
    move.w      #SCREEN_WIDTH_BYTE-2,BLTCMOD(a6)     ; 40 - 2 = 38 bytes
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6)     ; 40 - 2 = 38 bytes

    move.l      a0,BLTAPT(a6)           ; Mask
    move.l      a1,BLTBPT(a6)           ; Graphic
    move.l      a2,BLTCPT(a6)           ; Screen background
    move.l      a2,BLTDPT(a6)           ; Screen result

    move.w      d5,d4
    mulu.w      #TILEMAP_TILE_PLANES,d4
    lsl.w       #6,d4
    or.w        #1,d4
    move.w      d4,BLTSIZE(a6)          ; FrameHeight*4 lines, width = 1 word

.drawn_actorbob:
    moveq       #0,d4
    rts

.culled_actorbob:
    moveq       #1,d4
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
;      a6 = CUSTOM chip base
; Destroys: d0-d2, a0-a1
;==============================================================================

TilemapErasePlayer:
    tst.w       Player_PrevDrawn(a4)
    beq         .no_erase               ; nothing drawn last frame, skip

    clr.w       Player_PrevDrawn(a4)    ; reset drawn flag

    PUSHM       d2-d3/d7/a0-a1

    move.w      Player_PrevX(a4),d0
    move.w      Player_PrevY(a4),d1

    ; Save erased box parameters for TilemapRestorePlayerOverlaps
    move.w      d0,Player_ErasedX(a5)
    move.w      d1,Player_ErasedY(a5)
    move.w      #1,Player_ErasedFlag(a5)

    ; Screen byte offset in continuous buffer = (PrevBufferScanline * 160) + ((X / 16) * 2)
    move.w      PrevPlayerCameraY(a5),d2
    andi.w      #RING_BUFFER_MASK,d2    ; d2 = PrevBufferCamY
    add.w       d1,d2
    sub.w       PrevPlayerCameraY(a5),d2 ; d2 = PrevBufferScanline
    bmi         .no_erase
    cmp.w       #RING_BUFFER_ALLOC_LINES-PLAYER_HEIGHT,d2
    bgt         .no_erase
    LINE_OFFSET d2,d3               ; d2 = line * 160
    moveq       #0,d3
    move.w      d0,d3
    lsr.w       #4,d3                   ; d3 = X / 16
    add.w       d3,d3                   ; d3 = (X / 16) * 2
    add.l       d3,d2
    move.l      d2,d1                   ; d1 = screen byte offset

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
    move.w      #MINTERM_COPY,BLTCON0(a6)      ; D = A (direct copy)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-6,BLTAMOD(a6) ; 40 - 6 = 34 bytes
    move.w      #SCREEN_WIDTH_BYTE-6,BLTDMOD(a6) ; 40 - 6 = 34 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|3,BLTSIZE(a6) ; 96 rows x 3 words
    bra.s       .check_submerge

.erase_2word:
    ; --- 2-Word Wide Restore (32px aligned) ---
    move.w      #32,Player_ErasedSpan(a5)
    WAITBLIT
    move.w      #MINTERM_COPY,BLTCON0(a6)      ; D = A
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-4,BLTAMOD(a6) ; 40 - 4 = 36 bytes
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6) ; 40 - 4 = 36 bytes
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(PLAYER_HEIGHT*PLAYER_PLANES<<6)|2,BLTSIZE(a6) ; 96 rows x 2 words

.check_submerge:
    ; Check if restored background needs water dither/wave effect
    move.w      WaterPixelY(a5),d2
    bmi.s       .erase_done             ; water inactive (< 0)

    move.w      Player_ErasedY(a5),d1   ; top Y of erased box
    move.w      d1,d3
    add.w       #PLAYER_HEIGHT-1,d3     ; bottom Y of erased box
    cmp.w       d2,d3
    blt.s       .erase_done             ; bottom Y < WaterPixelY -> completely dry

    WAITBLIT                            ; wait for background restore blit to finish
    movea.l     a1,a0                   ; a0 = destination DisplayScreen pointer (at ErasedY and word column)
    move.w      Player_ErasedX(a5),d0
    ; d1 = Player_ErasedY(a5)
    ; d2 = WaterPixelY(a5)
    move.w      #PLAYER_HEIGHT,d7
    bsr         TilemapSubmergeActor

.erase_done:
    POPM        d2-d3/d7/a0-a1
    rts

.no_erase:
    clr.w       Player_ErasedFlag(a5)
    rts


;==============================================================================
; TilemapDrawPlayer  -  Blit player BOB onto DisplayScreen with foreground & water depth
;
; Blits the 24x24 pixel player BOB onto the 4-bitplane interleaved DisplayScreen.
; Handles:
;   - Pixel-accurate horizontal positioning and 8px vertical lift (centering 24px BOB on 16px tile)
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
;      a6 = CUSTOM chip base
; Destroys: d0-d7, a0-a4
;
; TilemapDrawPlayer = TilemapDrawPlayerCore (the BOB blit, two blits with the
; erase) followed by TilemapStampOverPlayer (foreground and ladder-scenery
; stamps). GameRunFrame calls the two halves separately so the enemies can be
; drawn between them, straight after the fast core.
;==============================================================================

TilemapDrawPlayer:
    bsr         TilemapDrawPlayerCore
    lea         Player(a5),a4           ; (the core destroys a4)

    ; fall through to TilemapStampOverPlayer

;==============================================================================
; TilemapStampOverPlayer  -  Foreground and ladder-scenery stamps over the player
;
; Re-blits the foreground tiles, and on a ladder the flanking scenery tiles,
; that overlap the player BOB drawn by TilemapDrawPlayerCore this frame.
;
; In:  a4 = pointer to active Player struct
; Destroys: d0-d3 (preserves everything else)
;==============================================================================

TilemapStampOverPlayer:
    tst.w       Player_PrevDrawn(a4)
    beq.s       .tsop_exit              ; not drawn (culled): nothing to stamp over
    move.w      Player_PrevX(a4),d0     ; where the core drew the BOB
    move.w      Player_PrevY(a4),d1
    bsr         TilemapStampForegroundOverPlayer
    bsr         TilemapStampSceneryOverLadder
.tsop_exit:
    rts


;==============================================================================
; TilemapDrawPlayerCore  -  Blit the player BOB (no stamps)
;
; In/Destroys: as TilemapDrawPlayer.
;==============================================================================

TilemapDrawPlayerCore:
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
    add.w       Player_XDec(a4),d0      ; add pixel offset within the tile (0..15)
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
    add.w       Player_YDec(a4),d1      ; add vertical pixel offset within the tile
    subq.w      #8,d1                   ; lift 8px: d1 = World Y (top scanline of 24px BOB)

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
    ; Screen byte offset in continuous buffer = (BufferScanline * 160) + ((X / 16) * 2)
    move.w      RingBufferCamY(a5),d2
    add.w       d1,d2
    sub.w       TilemapCameraY(a5),d2   ; d2 = BufferScanline (0..511)
    bmi         .culled
    cmp.w       #RING_BUFFER_ALLOC_LINES-PLAYER_HEIGHT,d2
    bgt         .culled
    LINE_OFFSET d2,d3               ; d2 = line * 160
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
    ;   Shift = World_X & 15 (pixel offset within the word).
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
    BLTSHIFT12  d3                   ; d3 = Shift << 12
    move.w      d3,d4                   ; d4 = BLTCON1 value
    ori.w       #MINTERM_COOKIE_CUT,d3               ; d3 = BLTCON0 value (USEA|USEB|USEC|USED, minterm $CA)

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
    BLTSHIFT12  d3                   ; d3 = Shift << 12
    move.w      d3,d4
    ori.w       #MINTERM_COOKIE_CUT,d3               ; BLTCON0

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
    move.w      #MINTERM_COOKIE_CUT,BLTCON0(a6)
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
    move.w      TilemapCameraY(a5),PrevPlayerCameraY(a5)
    move.w      #1,Player_PrevDrawn(a4)

    ; Steps 7 (foreground stamp) and 8 (ladder scenery stamp) are in
    ; TilemapStampOverPlayer, run after the enemies by GameRunFrame.

.exit:
    rts

.culled:
    clr.w       Player_PrevDrawn(a4)    ; flag as not drawn (no erase needed next frame)
    rts


;==============================================================================
; TilemapStampForegroundOverPlayer  -  Re-blit foreground tiles overlapping player
;
; In:  d0.w = Player World X (0..319)
;      d1.w = Player World Y (0..799)
;      a5   = Variables base
;      a6   = CUSTOM
; Destroys: d2-d3 (set to the player box size before the fall-through;
;           TilemapStampForegroundOverBox preserves everything else)
;==============================================================================
TilemapStampForegroundOverPlayer:
    move.w      #PLAYER_WIDTH,d2
    move.w      #PLAYER_HEIGHT,d3
    ; fall through to TilemapStampForegroundOverBox

;==============================================================================
; TilemapStampForegroundOverBox  -  Re-blit foreground tiles overlapping actor box
;
; In:  d0.w = Actor World X (0..319)
;      d1.w = Actor World Y (0..799)
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

    ; Calculate start/end rows: d1 = Y (0..799)
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
    move.w      d3,d0                   ; col
    move.w      d2,d1                   ; row
    bsr         TilemapSubmergeTile     ; ensure underwater foreground retains dither!

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
; TilemapStampSceneryOverLadder  -  Re-blit & submerge scenery adjacent to ladder
;
; When the player is climbing a ladder, her 24px wide BOB extends 4px left and 4px right
; beyond the 16px ladder column, overlapping adjacent scenery elements (e.g.
; bushes, mushrooms, foliage) defined in LevelDef_BackgroundMap (Layer 0).
; This routine queries LevelDef_BackgroundMap for tiles flanking the ladder shaft,
; re-blits them with cookie-cutter transparency ($0FCA) so the player is rendered behind
; the scenery, and calls TilemapSubmergeTile so underwater scenery retains its
; active water dither.
;
; In:  a4 = pointer to active Player struct
;      a5 = Variables base
;      a6 = CUSTOM
; Preserves: all caller registers (pushes d0-d7/a0-a4)
;==============================================================================
TilemapStampSceneryOverLadder:
    rts                                 ; disabled: scenery is background, ladders/player are in front
    PUSHM       d0-d7/a0-a4

    ; Only active when player is on a ladder (or vacating a ladder cell)
    tst.w       Player_OnLadder(a4)
    bne.s       .ladder_active

    ; Fallback check: is current map cell a ladder in LevelDef_LadderMap?
    move.l      CurrentLevelDef(a5),d0
    beq         .tss_exit
    movea.l     d0,a0
    move.l      LevelDef_LadderMap(a0),d0
    beq         .tss_exit
    movea.l     d0,a0
    addq.l      #8,a0                   ; skip 8-byte width/height header
    move.w      Player_Y(a4),d0
    mulu.w      #20,d0
    add.w       Player_X(a4),d0
    add.w       d0,d0                   ; word offset
    tst.w       (a0,d0.w)
    beq         .tss_exit               ; not on a ladder, exit

.ladder_active:
    move.l      CurrentLevelDef(a5),d0
    beq         .tss_exit
    movea.l     d0,a0
    move.l      LevelDef_BackgroundMap(a0),d0
    beq         .tss_exit
    movea.l     d0,a2                   ; a2 = Background/Scenery map pointer
    addq.l      #8,a2                   ; skip 8-byte header

    ; Ladder column = Player_X(a4)
    move.w      Player_X(a4),d7         ; d7 = ladder center column (e.g. 10)

    ; Calculate start and end rows across player footprint:
    ; Spans min(WorldY, Player_ErasedY) to max(WorldY, Player_ErasedY) + 23
    move.w      Player_Y(a4),d4
    lsl.w       #4,d4
    add.w       Player_YDec(a4),d4
    subq.w      #8,d4                   ; d4 = current WorldY
    tst.w       Player_ErasedFlag(a5)
    beq.s       .use_cur_y
    move.w      Player_ErasedY(a5),d0
    cmp.w       d0,d4
    ble.s       .use_cur_y
    move.w      d0,d4                   ; d4 = min top Y
.use_cur_y:
    bpl.s       .top_y_ok
    moveq       #0,d4
.top_y_ok:
    lsr.w       #4,d4                   ; d4 = start row (0..CurrentMapHeight-1)

    ; End row = (max bottom Y) >> 4
    move.w      Player_Y(a4),d5
    lsl.w       #4,d5
    add.w       Player_YDec(a4),d5
    add.w       #PLAYER_HEIGHT-1-8,d5   ; current bottom Y
    tst.w       Player_ErasedFlag(a5)
    beq.s       .use_cur_bottom
    move.w      Player_ErasedY(a5),d0
    add.w       #PLAYER_HEIGHT-1,d0
    cmp.w       d0,d5
    bge.s       .use_cur_bottom
    move.w      d0,d5                   ; d5 = max bottom Y
.use_cur_bottom:
    lsr.w       #4,d5                   ; d5 = end row

    ; Clamp rows to valid map bounds
    move.w      CurrentMapHeight(a5),d0
    subq.w      #1,d0
    cmp.w       d0,d5
    ble.s       .erow_ok
    move.w      d0,d5
.erow_ok:
    cmp.w       d5,d4
    bgt.s       .tss_exit

    ; Row loop from d4 to d5
    move.w      d4,d2                   ; d2 = cur_row
.row_loop:
    cmp.w       d5,d2
    bgt.s       .tss_exit

    ; Row offset in BackgroundMap: row * 40 bytes
    move.w      d2,d0
    lsl.w       #5,d0                   ; row * 32
    move.w      d2,d1
    lsl.w       #3,d1                   ; row * 8
    add.w       d1,d0                   ; row * 40
    lea         (a2,d0.w),a1            ; a1 = pointer to row in BackgroundMap

    ; 1. Check Col - 1 (Left adjacent column, e.g. Col 9)
    move.w      d7,d3
    subq.w      #1,d3
    bmi.s       .check_right
    move.w      d3,d0
    add.w       d0,d0                   ; col * 2
    move.w      (a1,d0.w),d0            ; read tile index
    beq.s       .check_right
    ; Tile found! Blit and submerge
    bsr         TilemapBlitSingleTile
    move.w      d3,d0                   ; col
    move.w      d2,d1                   ; row
    bsr         TilemapSubmergeTile

.check_right:
    ; 2. Check Col + 1 (Right adjacent column 1, e.g. Col 11)
    move.w      d7,d3
    addq.w      #1,d3
    cmp.w       CurrentMapWidth(a5),d3
    bge.s       .next_row
    move.w      d3,d0
    add.w       d0,d0
    move.w      (a1,d0.w),d0
    beq.s       .check_right2
    bsr         TilemapBlitSingleTile
    move.w      d3,d0                   ; col
    move.w      d2,d1                   ; row
    bsr         TilemapSubmergeTile

.check_right2:
    ; 3. Check Col + 2 (Right adjacent column 2, e.g. Col 12)
    move.w      d7,d3
    addq.w      #2,d3
    cmp.w       CurrentMapWidth(a5),d3
    bge.s       .next_row
    move.w      d3,d0
    add.w       d0,d0
    move.w      (a1,d0.w),d0
    beq.s       .next_row
    bsr         TilemapBlitSingleTile
    move.w      d3,d0                   ; col
    move.w      d2,d1                   ; row
    bsr         TilemapSubmergeTile

.next_row:
    addq.w      #1,d2
    bra.s       .row_loop

.tss_exit:
    POPM        d0-d7/a0-a4
    rts


; TilemapErase16x16Actor  -  Restore 16x16 actor area from NonDisplayScreen
;
; Arguments:
;   d0.w = World X (0..319)
;   d1.w = World Y (0..799)
;   a5   = Variables base
;   a6   = CUSTOM base
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

    ; Screen byte offset in 4-plane interleaved = (Y * 160) + ((X / 16) * 2)
    move.w      d1,d2
    andi.w      #RING_BUFFER_MASK,d2
    LINE_OFFSET d2,d3               ; d2 = line * 160
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
    move.w      #MINTERM_COPY,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-4,BLTAMOD(a6) ; 40 - 4 = 36
    move.w      #SCREEN_WIDTH_BYTE-4,BLTDMOD(a6) ; 40 - 4 = 36
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|2,BLTSIZE(a6)
    adda.l      #16*TILEMAP_ROW_STRIDE,a0
    adda.l      #16*TILEMAP_ROW_STRIDE,a1
    WAITBLIT
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|2,BLTSIZE(a6)
    bra.s       .tea_exit

.tea_1word:
    WAITBLIT
    move.w      #MINTERM_COPY,BLTCON0(a6)
    move.w      #$0000,BLTCON1(a6)
    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #SCREEN_WIDTH_BYTE-2,BLTAMOD(a6) ; 40 - 2 = 38
    move.w      #SCREEN_WIDTH_BYTE-2,BLTDMOD(a6) ; 40 - 2 = 38
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(TILEMAP_TILE_HEIGHT*TILEMAP_TILE_PLANES<<6)|1,BLTSIZE(a6)
    adda.l      #16*TILEMAP_ROW_STRIDE,a0
    adda.l      #16*TILEMAP_ROW_STRIDE,a1
    WAITBLIT
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
;   a6 = CUSTOM
;
; Destroys: none (preserves all registers)
;==============================================================================

DrawActor:
    PUSHM       d0-d7/a0-a4

    ; Calculate World X and Y
    move.w      Actor_PrevX(a3),d0
    lsl.w       #4,d0
    add.w       Actor_XDec(a3),d0      ; d0 = World X (0..319)

    move.w      Actor_PrevY(a3),d1
    lsl.w       #4,d1
    add.w       Actor_YDec(a3),d1      ; d1 = World Y (0..799)

    ; Absolute bounds check
    cmp.w       #0,d0
    blt         .da_skip
    cmp.w       #320-16,d0
    bgt         .da_skip
    cmp.w       #0,d1
    blt         .da_skip

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

    ; Destination screen address in DisplayScreen: (BufferScanline * 160) + ((X / 16) * 2)
    move.w      RingBufferCamY(a5),d2
    add.w       d1,d2
    sub.w       TilemapCameraY(a5),d2   ; d2 = BufferScanline
    bmi         .da_skip
    cmp.w       #RING_BUFFER_ALLOC_LINES-16,d2
    bgt         .da_skip
    LINE_OFFSET d2,d3               ; d2 = line * 160
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
    BLTSHIFT12  d3                  ; d3 = Shift << 12
    move.w      d3,d4
    ori.w       #MINTERM_COOKIE_CUT,d3              ; BLTCON0

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
    move.w      #MINTERM_COOKIE_CUT,BLTCON0(a6)
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
    bmi         .da_skip
    movea.l     a2,a0                  ; a0 = dest pointer in DisplayScreen
    move.w      #16,d7                 ; 16 scanlines
    bsr         TilemapSubmergeActor

.da_skip:
    POPM        d0-d7/a0-a4
    rts


;==============================================================================
; TilemapDrawPushBlocks  -  Draw all active, settled push blocks
;
; Called every frame in GameRun before friends and the player are drawn.
; Only settled push blocks (HasMoved=0, HasFalled=0) are drawn here;
; moving blocks are animated by ActionPush / ActionFallActors.
;
; In:  a5 = Variables base
;      a6 = CUSTOM base
; Preserves: a5, a6
;==============================================================================
