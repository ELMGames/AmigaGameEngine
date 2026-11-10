
;==============================================================================
; AMIGA GAME ENGINE
; audio.asm  -  Generic PTPlayer Lifecycle Driver (engine-level, game-agnostic)
;==============================================================================
;
; Wraps PTPlayer (ptplayer.asm, v6.4 by Frank Wille). PTPlayer uses the CIA-B
; Timer-A interrupt for automatic music replay and CIA-B Timer-B for audio
; DMA enable / loop-pointer setup. CIA-A is used by the keyboard handler —
; there is no conflict between the two.
;
; Required by the engine lifecycle itself (engine_main.asm calls AudioInit
; from EngineInit, and AudioStopMod/AudioRemove from QuitToOS) — so every
; game includes this file, even one with no music or SFX of its own.
;
;   AudioInit         - call once at program start (installs CIA-B ISR)
;   AudioPlayMod      - call with a0 = MOD pointer to start a new piece
;   AudioStopMod      - stop all music/SFX immediately
;   AudioRemove       - uninstall the CIA-B ISR (call once, on exit)
;
; Game-specific convenience wrappers (AudioPlayLevelMusic, AudioPlayCratePush,
; etc.) do NOT belong here — they reference game-specific MOD/SFX data by
; name, which would make this file fail to assemble for a game that
; doesn't define that data. the game's wrappers live in
; games/duck_rescue/include/game_audio.asm instead; a new game should add
; its own equivalent file rather than extending this one.
;
; ZX tape-load SFX (loading screen) are also routed through PTPlayer via
; _mt_loopfx / _mt_stopfx on channel 0. This means no direct Paula writes
; exist anywhere in the codebase — all audio goes through PTPlayer's ISR.
;
; All routines expect:
;   a6 = CUSTOM  (custom chip base — global register convention)
;   a5 = Variables base pointer  (not directly used here but held by callers)
;==============================================================================


;==============================================================================
; AudioInit  -  Install CIA-B interrupt and initialise PTPlayer (call once)
;
; Called from Init (main.asm) before StartVBlank enables interrupts.
; _mt_install registers the CIA-B Timer-A ISR.  No music plays until
; _mt_init is called and _mt_Enable is set non-zero.
;
; _mt_install arguments:
;   a6 = CUSTOM
;   a0 = Vector Base Register address — 0 for 68000 (no VBR)
;   d0 = PAL flag — 1 selects PAL CIA timing (3.546895 MHz), 0 selects NTSC (3.579545 MHz)
;
; IsPAL(a5) must be set before calling (DetectNTSC runs before AudioInit in Init).
;
; PTPlayer's variables sit at the very end of the code hunk. The linker trims
; trailing zeros from a hunk, so they may not be in the file at all. Don't rely
; on that memory starting at zero: clear them here, as _mt_playfx reads mt_mod
; even before any module has been started.
;
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================
AudioInit:
    lea         mt_data,a0
    move.w      #_mt_SongEnd-mt_data,d0 ; byte count - 1, for dbra
.clear:
    clr.b       (a0)+
    dbra        d0,.clear

    move.l      VBRBase,a0          ; VBR base address (0 on 68000, relocated on 68010+)
    move.w      IsPAL(a5),d0        ; 1 = PAL CIA timing, 0 = NTSC CIA timing
    jsr         _mt_install
    rts


;==============================================================================
; AudioPlayMod  -  Initialise and start a MOD module
;
; On entry:
;   a0 = pointer to MOD file data in Chip RAM
;   a6 = CUSTOM
;
; Calls _mt_init to reset the player to the start of the new module, then
; sets _mt_Enable to begin replay via the CIA-B Timer-A ISR.
; Samples are assumed to follow the pattern data (standard MOD layout, a1=NULL).
;
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================
AudioPlayMod:
    moveq       #0,d0               ; d0 = 0  (start at song position 0)
    sub.l       a1,a1               ; a1 = NULL (samples embedded after patterns)
    jsr         _mt_init
    move.b      #1,_mt_Enable       ; start replay
    rts


;==============================================================================
; AudioRemove  -  Uninstall the PTPlayer CIA-B interrupt (call once, on exit)
;
; Calls _mt_remove which restores the CIA-B timer state and the level-6
; interrupt vector that _mt_install saved.  Must be called before handing
; the machine back to the OS (QuitToOS in main.asm).
;
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================
AudioRemove:
    jsr         _mt_remove
    rts


;==============================================================================
; AudioStopMod  -  Stop all music and sound effects immediately
;
; Calls _mt_end which: sets all Paula channel volumes to 0, disables audio
; DMA, clears _mt_Enable, and resets all internal channel state.
; Safe to call when nothing is playing.  After this, SFX can still be
; triggered via _mt_loopfx / _mt_playfx (the CIA-B ISR remains active and
; calls mt_sfxonly when _mt_Enable is 0).
;
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================
AudioStopMod:
    jsr         _mt_end
    rts

