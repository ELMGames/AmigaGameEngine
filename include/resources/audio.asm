
;==============================================================================
; AMIGA GAME ENGINE
; audio.asm  -  Music and Sound Effect Management (PTPlayer wrapper)
;==============================================================================
;
; Wraps PTPlayer (ptplayer.asm, v6.4 by Frank Wille) for this game's needs.
; PTPlayer uses the CIA-B Timer-A interrupt for automatic music replay and
; CIA-B Timer-B for audio DMA enable / loop-pointer setup.  CIA-A is used
; by the keyboard handler — there is no conflict between the two.
;
; Usage pattern per screen:
;   AudioInit         - call once at program start (installs CIA-B ISR)
;   AudioPlayMod      - call with a0 = MOD pointer to start a new piece
;   AudioStopMod      - call to silence music before a screen transition
;   AudioPlayLevelMusic / AudioPlayTitleMusic - convenience wrappers
;
; ZX tape-load SFX (loading screen) are also routed through PTPlayer via
; _mt_loopfx / _mt_stopfx on channel 0.  This means no direct Paula writes
; exist anywhere in the codebase — all audio goes through PTPlayer's ISR.
;
; All routines expect:
;   a6 = $dff000  (CUSTOM chip base — global register convention)
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
;   a6 = CUSTOM ($dff000)
;   a0 = Vector Base Register address — 0 for 68000 (no VBR)
;   d0 = PAL flag — 1 selects PAL CIA timing (3.546895 MHz), 0 selects NTSC (3.579545 MHz)
;
; IsPAL(a5) must be set before calling (DetectNTSC runs before AudioInit in Init).
;==============================================================================
AudioInit:
    move.l      VBRBase,a0          ; VBR base address (0 on 68000, relocated on 68010+)
    move.w      IsPAL(a5),d0        ; 1 = PAL CIA timing, 0 = NTSC CIA timing
    jsr         _mt_install
    rts


;==============================================================================
; AudioPlayMod  -  Initialise and start a MOD module
;
; On entry:
;   a0 = pointer to MOD file data in Chip RAM
;   a6 = CUSTOM ($dff000)
;
; Calls _mt_init to reset the player to the start of the new module, then
; sets _mt_Enable to begin replay via the CIA-B Timer-A ISR.
; Samples are assumed to follow the pattern data (standard MOD layout, a1=NULL).
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
;==============================================================================
AudioStopMod:
    jsr         _mt_end
    rts


;==============================================================================
; AudioPlayLevelMusic  -  Start the level gameplay music
;
; Loads the level MOD (LevelMod, defined in main.asm data_chip section) and
; calls AudioPlayMod.  Called at the end of LEVEL_REVEAL when gameplay starts.
;
; Future: select from a per-chapter MOD table using AssetSet(a5) to give
; each of the 5 tile-set chapters its own piece.
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


;==============================================================================
; AudioPlayTitleMusic  -  Start the title screen music
;
; Plays TitleScreenMusicMod (supremacy_title.mod), which is permanently in
; chip RAM (before the overlay region).  PTPlayer replays the module in an
; endless loop — it keeps playing until AudioStopMod is called when leaving
; the title screen.  Safe to call when returning to title after gameplay.
;==============================================================================
AudioPlayTitleMusic:
    lea         TitleScreenMusicMod,a0
    bsr         AudioPlayMod
    rts
