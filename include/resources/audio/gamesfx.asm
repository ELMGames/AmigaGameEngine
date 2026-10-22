;==============================================================================
; AMIGA GAME ENGINE
; gamesfx.asm  -  In-Game Sound Effect Data & Structures (Chip RAM)
;==============================================================================
;
; SfxStructures (12 bytes) and 8-bit signed mono PCM audio samples for in-game
; sound effects, played via PTPlayer's _mt_playfx feature.
;
; Must reside in Chip RAM (included within section data_chip in main.asm) so
; that Paula audio DMA can read the sample waveforms directly.
;
; SfxStructure Layout:
;   dc.l  sfx_ptr  - Chip RAM address of sample (first word is dc.w 0 idle loop)
;   dc.w  sfx_len  - Length in words (including leading zero word)
;   dc.w  sfx_per  - Paula playback period (322 for 11025 Hz PAL)
;   dc.w  sfx_vol  - Playback volume (0..64)
;   dc.b  sfx_cha  - Replay channel (-1 = best automatic channel selection)
;   dc.b  sfx_pri  - Priority (1..127)
;==============================================================================

;------------------------------------------------------------------------------
; Sound Effect Structures (12 bytes each, referenced by audio.asm)
;------------------------------------------------------------------------------

    even
SfxCane:
    dc.l    SfxCane_Raw
    dc.w    (SfxCane_RawEnd-SfxCane_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    55                          ; volume (0..64)
    dc.b    SFX_AUTO_CHANNEL            ; auto channel
    dc.b    40                          ; priority

SfxCrateImpact:
    dc.l    SfxCrateImpact_Raw
    dc.w    (SfxCrateImpact_RawEnd-SfxCrateImpact_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    64                          ; full volume thump
    dc.b    SFX_AUTO_CHANNEL
    dc.b    65

SfxEnemyStun:
    dc.l    SfxEnemyStun_Raw
    dc.w    (SfxEnemyStun_RawEnd-SfxEnemyStun_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    64                          ; full volume dizzy boing/sparkle
    dc.b    SFX_AUTO_CHANNEL
    dc.b    80

SfxDuckRescue:
    dc.l    SfxDuckRescue_Raw
    dc.w    (SfxDuckRescue_RawEnd-SfxDuckRescue_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    64                          ; full volume cheerful chime
    dc.b    SFX_AUTO_CHANNEL
    dc.b    95

SfxOxygen:
    dc.l    SfxOxygen_Raw
    dc.w    (SfxOxygen_RawEnd-SfxOxygen_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    60                          ; volume
    dc.b    SFX_AUTO_CHANNEL
    dc.b    70

SfxCratePush:
    dc.l    SfxCratePush_Raw
    dc.w    (SfxCratePush_RawEnd-SfxCratePush_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    48                          ; subtle friction rumble
    dc.b    SFX_AUTO_CHANNEL
    dc.b    30

SfxPlayerDie:
    dc.l    SfxPlayerDie_Raw
    dc.w    (SfxPlayerDie_RawEnd-SfxPlayerDie_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    64                          ; full volume death impact + arpeggio
    dc.b    SFX_AUTO_CHANNEL
    dc.b    110                         ; very high priority

SfxAirBubble:
    dc.l    SfxAirBubble_Raw
    dc.w    (SfxAirBubble_RawEnd-SfxAirBubble_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    45                          ; gentle aquatic bubble pop
    dc.b    SFX_AUTO_CHANNEL
    dc.b    25                          ; low priority background ambient

SfxLevelComplete:
    dc.l    SfxLevelComplete_Raw
    dc.w    (SfxLevelComplete_RawEnd-SfxLevelComplete_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    64                          ; full volume triumphant fanfare
    dc.b    SFX_AUTO_CHANNEL
    dc.b    120                         ; highest priority victory fanfare

SfxGameOver:
    dc.l    SfxGameOver_Raw
    dc.w    (SfxGameOver_RawEnd-SfxGameOver_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    64                          ; full volume
    dc.b    SFX_AUTO_CHANNEL
    dc.b    120                         ; highest priority

SfxRewind:
    dc.l    SfxRewind_Raw
    dc.w    (SfxRewind_RawEnd-SfxRewind_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    64                          ; full volume
    dc.b    SFX_AUTO_CHANNEL
    dc.b    85                          ; priority (distinct player action)



;------------------------------------------------------------------------------
; Raw 8-Bit Signed PCM Audio Data (Chip RAM)
; Each file begins with dc.w 0 for the PTPlayer idle-loop requirement.
;------------------------------------------------------------------------------

    even
SfxCane_Raw:
    incbin      "assets/fx/sfx_cane.raw"
    even
SfxCane_RawEnd:

SfxCrateImpact_Raw:
    incbin      "assets/fx/sfx_crate_impact.raw"
    even
SfxCrateImpact_RawEnd:

SfxEnemyStun_Raw:
    incbin      "assets/fx/sfx_enemy_stun.raw"
    even
SfxEnemyStun_RawEnd:

SfxDuckRescue_Raw:
    incbin      "assets/fx/sfx_duck_rescue.raw"
    even
SfxDuckRescue_RawEnd:

SfxOxygen_Raw:
    incbin      "assets/fx/sfx_oxygen.raw"
    even
SfxOxygen_RawEnd:

SfxCratePush_Raw:
    incbin      "assets/fx/sfx_crate_push.raw"
    even
SfxCratePush_RawEnd:

SfxPlayerDie_Raw:
    incbin      "assets/fx/sfx_player_die.raw"
    even
SfxPlayerDie_RawEnd:

SfxAirBubble_Raw:
    incbin      "assets/fx/sfx_air_bubble.raw"
    even
SfxAirBubble_RawEnd:

SfxLevelComplete_Raw:
    incbin      "assets/fx/sfx_level_complete.raw"
    even
SfxLevelComplete_RawEnd:

SfxGameOver_Raw:
    incbin      "assets/fx/sfx_game_over.raw"
    even
SfxGameOver_RawEnd:

SfxRewind_Raw:
    incbin      "assets/fx/sfx_rewind.raw"
    even
SfxRewind_RawEnd:

