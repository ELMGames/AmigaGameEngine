;==============================================================================
; DUCK RESCUE - GAME-SPECIFIC MUSIC & SFX WRAPPERS
; game_audio.asm
;==============================================================================
;
; Convenience wrappers over engine/audio/audio.asm's generic AudioPlayMod and
; ptplayer.asm's _mt_playfx, naming Duck Rescue's own MOD/SFX data (LevelMod,
; SfxCane, etc. — defined in main.asm's data_chip section and
; games/duck_rescue/include/game_sfx.asm). Split out from audio.asm because that file is
; required by every game's build (the engine lifecycle calls AudioInit/
; AudioStopMod/AudioRemove directly) and must assemble even for a game with
; no music or SFX of its own — see that file's header comment.
;
; A new game should write its own equivalent of this file naming its own
; MOD/SFX data, rather than adding to this one or to audio.asm.
;
; All routines expect:
;   a6 = $dff000  (CUSTOM chip base — global register convention)
;   a5 = Variables base pointer
;==============================================================================

;------------------------------------------------------------------------------
; END_AUDIO_STAGE - where the end-screen audio is staged in NonDisplayScreen.
; The game-complete screen keeps its duckling at NonDisplayScreen+0, so the
; audio goes clear of it. Both end screens stop audio before they leave.
;------------------------------------------------------------------------------
END_AUDIO_STAGE = 8192

;==============================================================================
; AudioPlayLevelMusic  -  Start the level gameplay music
;
; Loads the level MOD (LevelMod, defined in main.asm data_chip section) and
; calls AudioPlayMod.  Called at the end of LEVEL_REVEAL when gameplay starts.
;
; Future: select from a per-chapter MOD table using AssetSet(a5) to give
; each of the 5 tile-set chapters its own piece.
;
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================
AudioPlayLevelMusic:
    move.l      CurrentLevelDef(a5),d0
    beq.s       .fallback
    movea.l     d0,a0
    move.l      LevelDef_Music(a0),d0
    beq.s       .fallback
    movea.l     d0,a0
    bsr         AudioPlayMod
    rts

.fallback:
    lea         LevelMod,a0
    bsr         AudioPlayMod
    rts


; Game complete screen music (GameCompleteMod)
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayGameCompleteMusic:
    lea         GameCompleteMod,a0
    lea         NonDisplayScreen+END_AUDIO_STAGE,a1
    move.w      #(GameCompleteModEnd-GameCompleteMod)/2-1,d0
.copy:
    move.w      (a0)+,(a1)+             ; stage the module into Chip RAM
    dbra        d0,.copy
    lea         NonDisplayScreen+END_AUDIO_STAGE,a0
    bsr         AudioPlayMod
    rts


;==============================================================================
; AudioPlayTitleMusic  -  Start the title screen music
;
; Plays TitleScreenMusicMod (heatwave_cruise.mod), which is dynamically staged into
; NonDisplayScreen+10000 (Chip RAM) by TitleSetup. PTPlayer loops the module endlessly
; until AudioStopMod is called when leaving the title screen.
;
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================
AudioPlayTitleMusic:
    lea         NonDisplayScreen+10000,a0
    bsr         AudioPlayMod
    rts


;==============================================================================
; In-Game Sound Effect Playback Routines (PTPlayer _mt_playfx)
;
; All routines preserve ALL caller registers (d0-d7 / a0-a6) via the PLAYSFX
; macro (engine/core/macros.asm), which saves/restores d0-d1/a0 around the
; _mt_playfx call. PTPlayer inserts the sound effect into the least active
; audio channel without interrupting the music on the other channels — see
; _mt_playfx's channel-stealing/lookahead logic in ptplayer.asm for how the
; channel is actually chosen and how priority (sfx_pri in game_sfx.asm) breaks
; contention.
;==============================================================================

; Cane attack whoosh / swing
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayCane:
    PLAYSFX     SfxCane
    rts

; Crate landing impact / heavy floor thud
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayCrateImpact:
    PLAYSFX     SfxCrateImpact
    rts

; Cane hit on enemy / dizzy stars stun
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayEnemyStun:
    PLAYSFX     SfxEnemyStun
    rts

; Duckling / animal friend rescue chime
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayDuckRescue:
    PLAYSFX     SfxDuckRescue
    rts

; Oxygen canister pickup bubble chime
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayOxygen:
    PLAYSFX     SfxOxygen
    rts

; Crate push / floor friction scraping
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayCratePush:
    PLAYSFX     SfxCratePush
    rts

; Player death / fatal hit or drowning collapse
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayPlayerDie:
    PLAYSFX     SfxPlayerDie
    rts

; Underwater air bubble spawn bloop
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayAirBubble:
    PLAYSFX     SfxAirBubble
    rts

; Triumphant level complete fanfare
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayLevelComplete:
    PLAYSFX     SfxLevelComplete
    rts

; Klaxon game over sound effect
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayGameOver:
    lea         SfxGameOver_Raw,a0
    lea         NonDisplayScreen+END_AUDIO_STAGE,a1
    move.w      #(SfxGameOver_RawEnd-SfxGameOver_Raw)/2-1,d0
.copy:
    move.w      (a0)+,(a1)+             ; stage the sample into Chip RAM
    dbra        d0,.copy
    move.l      #NonDisplayScreen+END_AUDIO_STAGE,SfxGameOver
    PLAYSFX     SfxGameOver
    rts

; Level intro banner fanfare
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayIntroFanfare:
    PLAYSFX     SfxIntroFanfare
    rts

; VHS tape rewind / move unwind sound effect
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
AudioPlayRewind:
    PLAYSFX     SfxRewind
    rts
