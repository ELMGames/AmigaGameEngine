;==============================================================================
; DUCK RESCUE
; entity_bobs.asm  -  Stunned-enemy visuals
;==============================================================================
;
; The enemy, friend and pickup pools are drawn by the engine
; (engine/gameplay/entities.asm). Duck Rescue adds two things when the
; player's cane stuns an enemy (Enemy_StunTimer, set in player_combat.asm):
;
;   EnemyStunFlashSheet - GameEnemySheetHook: strobe to the white silhouette
;                         sheet in the last ENEMY_RECOVERY_FLASH_TICKS
;   EnemyDrawStunStars  - GameEnemyOverlayHook: spinning stars over the head
;
; Register convention: a4 = current enemy, a5 = Variables base,
;                      a6 = CUSTOM chip base
;==============================================================================

;==============================================================================
; EnemyStunFlashSheet  -  Pick the colour sheet for a stunned enemy
;
; When cane-struck, Enemy_StunTimer is set to ENEMY_STUN_DURATION (200 ticks
; = 4.0s). During the final 1.5 seconds (ENEMY_RECOVERY_FLASH_TICKS = 75
; ticks) the enemy strobes between its normal colours and a solid white
; silhouette (EnemySpritesWhiteRaw) to warn that the stun is wearing off.
;
; In:  a4 = ActiveEnemy pointer, a1 = EnemySpritesRaw
; Out: a1 = colour sheet to draw from
; Destroys: d4 (preserves everything else, including a5/a6)
;==============================================================================

EnemyStunFlashSheet:
    move.w      Enemy_StunTimer(a4),d4
    beq.s       .normal                 ; not stunned -> normal graphic
    cmp.w       #ENEMY_RECOVERY_FLASH_TICKS,d4
    bgt.s       .normal                 ; still early in stun duration -> normal graphic
    btst        #2,d4                   ; alternate every 4 frames (~12.5 Hz strobe)
    beq.s       .normal
    lea         EnemySpritesWhiteRaw,a1 ; pure white silhouette buffer
.normal:
    rts


;==============================================================================
; EnemyDrawStunStars  -  Draw the dizzy stars over a stunned enemy
;
; In:  a2 = enemy box in DisplayScreen, d0 = world X, a4 = ActiveEnemy pointer
; Destroys: none (preserves all registers)
;==============================================================================

EnemyDrawStunStars:
    tst.w       Enemy_StunTimer(a4)
    bne         TilemapDrawDizzyStars
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
;   - Shifts horizontally to match the enemy's exact pixel X coordinate.
;
; In: a2 = dest pointer in DisplayScreen (base of 16x16 enemy box)
;     d0 = World X (Enemy_X)
; Destroys: none (preserves all registers)
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
    BLTSHIFT12  d3                   ; d3 = Shift << 12
    move.w      d3,d4
    ori.w       #MINTERM_COOKIE_CUT,d3               ; BLTCON0

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
    move.w      #MINTERM_COOKIE_CUT,BLTCON0(a6)
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
