
;==============================================================================
; AMIGA GAME ENGINE
; gamestatus.asm  -  Top-Level Game State Machine
;==============================================================================
;
; The game runs as a simple state machine.  MainLoop (main.asm) calls
; GameStatusRun once per video frame, which dispatches to the handler for
; the current state.
;
; States (stored in GameStatus(a5) as a word index):
;
;   0 - LoadingSetup  (defined in loading.asm)
;       One-shot initialisation of the loading screen: installs the loading
;       copper list, decompresses the loading image, arms the ZX tape-load
;       animation phases, then advances GameStatus to LoadingRun (1).
;
;   1 - LoadingRun    (defined in loading.asm)
;       Runs every frame while the loading screen is displayed.  Drives the
;       ZX tape phases (header, silent gap, row-by-row data reveal, colour
;       wash) and then transitions automatically to TITLE_SETUP.  F6 skips.
;
;   2 - GameRun     (defined below)
;       Main gameplay loop, called every VBlank.
;       Checks F1/F2 for level navigation (debug), reads player controls,
;       and calls PlayerLogic to advance the active player action state machine.
;
;    3 - LEVEL_INIT  (dispatches to LevelTransitionRun in levelutils.asm)
;        One-shot per-level initialisation.  Called when a new level is loaded
;        and ready to play, but before the wipe effect starts.  Sets up the
;        wipe pattern and tile order, then advances GameStatus to LEVEL_WIPE (4).

;   4 - LEVEL_WIPE  (dispatches to LevelTransitionRun in levelutils.asm)
;       Per-frame handler while the end-of-level wipe is running.
;       Blits WIPE_SPEED tiles black per frame until all 126 tiles are done,
;       then advances to LEVEL_HOLD (4).
;
;   5 - LEVEL_HOLD  (dispatches to LevelTransitionRun in levelutils.asm)
;       Holds the all-black screen while the next level is built into NonDisplayScreen.
;       Counts down WipeHoldTick, then calls LevelRevealSetup and advances to
;       LEVEL_REVEAL (5).
;
;   6 - LEVEL_REVEAL  (dispatches to LevelTransitionRun in levelutils.asm)
;       Per-frame handler for the level-entry reverse-wipe reveal.
;       Restores WIPE_SPEED tiles from NonDisplayScreen to DisplayScreen per frame,
;       then draws actors and returns to GameRun (2).
;
;   7 - LEVEL_COMPLETE_SETUP  (defined in levelcomplete.asm)
;       One-shot: clears DisplayScreen, installs cpLevelComplete copper list,
;       blits portraits, draws text and password, inits menu selection.
;       Advances GameStatus to LEVEL_COMPLETE_RUN (8).
;
;   8 - LEVEL_COMPLETE_RUN  (defined in levelcomplete.asm)
;       Per-frame: reads UP/DOWN/FIRE/Return to move cursor and confirm.
;       PLAY NEXT LEVEL: increments LevelId, sets GameStatus = LEVEL_INIT (3).
;       RETURN TO TITLE: sets GameStatus = GAME_INIT (0).
;
;   9 - TITLE_SETUP  (defined in titlescreen.asm)
;       One-shot title screen init: installs cpTitle, draws the three menu
;       options (PLAY LEVEL / CREDITS / INSTRUCTIONS), then advances to
;       TITLE_RUN (10).  Reached automatically from LoadingRun.
;
;  10 - TITLE_RUN  (defined in titlescreen.asm)
;       Per-frame title screen handler: menu navigation and copper effects.
;
;  11-16 - Instructions pages 1, 2, and 3 (instructions.asm)
;
;  17-18 - Credits screen (credits.asm)
;
;  19-20 - Game Complete screen (gamecomplete.asm)
;
;  21 - GAME_OVER_SETUP (defined in gameover.asm)
;       One-shot initialisation: installs cpGameOver, clears screen, arms
;       two-line flashing hero text ("GAME" / "OVER"), starts 4-second timer.
;
;  22 - GAME_OVER_RUN (defined in gameover.asm)
;       Per-frame handler: ticks flashing hero text, counts down 4 seconds,
;       then returns to TITLE_SETUP.
;
;  23 - FLASH_SETUP (defined in flashscreen.asm)
;       One-shot initialisation: installs cpFlash, clears screen, blits
;       centered Amiga Game Engine banner, starts trumpet fanfare SFX.
;
;  24 - FLASH_RUN (defined in flashscreen.asm)
;       Per-frame handler: holds banner display for ~2.2s, allows skipping,
;       then transitions to GAME_INIT (LoadingSetup).
;
; The JMPINDEX macro (macros.asm) converts the GameStatus word into a
; PC-relative jump through the word-offset table at .i.
;
;==============================================================================

;==============================================================================
; GameInit  -  Full game screen initialisation (called from LoadingSetup or
;                  directly when entering gameplay state)
;
; Sets up the game copper list, generates the hardware sprite mask data,
; installs the game copper list into Agnus, enables DMA, sets the starting
; level, and draws the first map.
;
; Sequence:
;   1. GameCopperInit  - build cpPlanes / cpPal copper entries for DisplayScreen
;   2. Install cpGame copper list and start Copper (COPJMP1)
;   3. Enable DMA (BASE_DMA)
;   4. Set LevelId = START_LEVEL and call DrawMap to render the opening level
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
;==============================================================================

GameInit:
    bsr        GameCopperInit

    lea        DisplayScreen,a0        ; clear loading screen bitmap before game copper takes over
    move.l     #SCREEN_SIZE,d7
    bsr        TurboClear

    move.l     #cpGame,COP1LC(a6)
    move.w     #0,COPJMP1(a6)
    bsr        VhsInit            ; set VHS distortion region scanlines (PAL/NTSC)

 ;   move.w     #BASE_DMA,DMACON(a6)
    rts

;==============================================================================
; GameCopperInit  -  Patch the game copper list with screen and palette data
;
; Called from GameInit before the copper list is activated.  Fills in the
; runtime-variable fields of cpGame that the assembler left as zeros:
;
;   cpPlanes  - writes the physical addresses of DisplayScreen's five bitplanes
;               into the BPL1PTH/L .. BPL5PTH/L copper MOVE pairs.
;
;   cpPal     - copies the 32 halfword colour values from TilesPal0 (the
;               default tile palette) into the COLOR00..COLOR31 copper entries.
;
; Also calls ClearSprites to zero all 8 sprite copper entries (SPR0..SPR7
; pointed at NullSprite).
;
; Uses PLANE_TO_COPPER macro to split each 32-bit address into the two 16-bit
; copper words at +2 and +6 of each BPLxPTH/L pair.
;
; Destroys: d0-d7/a0-a1/a4 (preserves everything else, including a5/a6)
;==============================================================================

GameCopperInit:
    bsr        ClearSprites            ; point all 8 sprite channels at NullSprite

    lea        cpPlanes,a0
    move.l     #DisplayScreen,d0
    move.l     #SCREEN_WIDTH_BYTE,d1
    moveq      #TILEMAP_TILE_PLANES,d7
    bsr        CopperSetPtrs           ; patch BPL1-4 pointers (shared, tools.asm)

    ; Load level palette into copper list (COLOR00-15 from LevelDefaultPalette, COLOR16-31 from SpritePal)
    lea        LevelDefaultPalette,a0
    lea        cpPal,a1
    moveq      #16-1,d7
.cloop1
    move.w     (a0)+,2(a1)
    addq.l     #4,a1
    dbra       d7,.cloop1

    lea        SpritePal,a0
    moveq      #16-1,d7
.cloop2
    move.w     (a0)+,2(a1)
    addq.l     #4,a1
    dbra       d7,.cloop2

    bsr        GameSetupHook           ; game-side setup (e.g. HUD sprites & palettes)
    rts

;==============================================================================
; GameStatusRun  -  Dispatch to the current game state handler
;
; Called from MainLoop once per frame (gated by FramePending).
; a5 must be loaded with the Variables base before calling.
; a6 must be CUSTOM (CUSTOM chip base).
;
; A corrupt GameStatus would jump through garbage offsets into random memory;
; the bounds check below turns that failure mode into the solid red
; FaultTrap screen instead (2 instructions — cheap enough to keep always on).
;
; No arguments.  Tail-calls the appropriate state handler via JMPINDEX.
;
; Destroys: d0 (preserves everything else, including a5/a6)
;==============================================================================

GameStatusRun:
    ; Non-priority blit states transition immediately to logic color (Green/Red)
    cmp.w       #GAME_RUN,GameStatus(a5)
    beq.s       .dispatch
    cmp.w       #GAME_COMPLETE_RUN,GameStatus(a5)
    beq.s       .dispatch
    bsr         SetRasterLogicColor
.dispatch:
    move.w      GameStatus(a5),d0    ; load current state index
    cmp.w       #(.i_end-.i)/2,d0    ; index beyond the dispatch table?
    bcc         FaultTrap            ; corrupt state -> red screen, not a wild jump
    JMPINDEX    d0                   ; computed jump through offset table below

.i  ; jump-offset table - one signed word per state
    dc.w        LoadingSetup-.i           ; state 0 -> LoadingSetup          (in loading.asm)
    dc.w        LoadingRun-.i             ; state 1 -> LoadingRun            (in loading.asm)
    dc.w        GameRun-.i              ; state 2 -> GameRun             (below)
    dc.w        LevelTransitionRun-.i   ; state 3 -> LEVEL_INIT phase    (in levelutils.asm)
    dc.w        LevelTransitionRun-.i   ; state 4 -> LEVEL_WIPE phase    (in levelutils.asm)
    dc.w        LevelTransitionRun-.i   ; state 5 -> LEVEL_HOLD phase    (in levelutils.asm)
    dc.w        LevelTransitionRun-.i   ; state 6 -> LEVEL_REVEAL phase  (in levelutils.asm)
    dc.w        LevelCompleteSetup-.i   ; state 7 -> LEVEL_COMPLETE_SETUP (in levelcomplete.asm)
    dc.w        LevelCompleteRun-.i     ; state 8 -> LEVEL_COMPLETE_RUN  (in levelcomplete.asm)
    dc.w        TitleSetup-.i           ; state 9 -> TITLE_SETUP          (in titlescreen.asm)
    dc.w        TitleRun-.i             ; state 10 -> TITLE_RUN           (in titlescreen.asm)
    dc.w        InstrPage1Setup-.i      ; state 11 -> INSTR_SETUP1        (in instructions.asm)
    dc.w        InstrPage1Run-.i        ; state 12 -> INSTR_RUN1          (in instructions.asm)
    dc.w        InstrPage2Setup-.i      ; state 13 -> INSTR_SETUP2        (in instructions.asm)
    dc.w        InstrPage2Run-.i        ; state 14 -> INSTR_RUN2          (in instructions.asm)
    dc.w        InstrPage3Setup-.i      ; state 15 -> INSTR_SETUP3        (in instructions.asm)
    dc.w        InstrPage3Run-.i        ; state 16 -> INSTR_RUN3          (in instructions.asm)
    dc.w        CreditsSetup-.i         ; state 17 -> CREDITS_SETUP       (in credits.asm)
    dc.w        CreditsRun-.i           ; state 18 -> CREDITS_RUN         (in credits.asm)
    dc.w        GameCompleteSetup-.i    ; state 19 -> GAME_COMPLETE_SETUP (in gamecomplete.asm)
    dc.w        GameCompleteRun-.i      ; state 20 -> GAME_COMPLETE_RUN   (in gamecomplete.asm)
    dc.w        GameOverSetup-.i        ; state 21 -> GAME_OVER_SETUP     (in gameover.asm)
    dc.w        GameOverRun-.i          ; state 22 -> GAME_OVER_RUN       (in gameover.asm)
    dc.w        FlashScreenSetup-.i     ; state 23 -> FLASH_SETUP         (in flashscreen.asm)
    dc.w        FlashScreenRun-.i       ; state 24 -> FLASH_RUN           (in flashscreen.asm)
    dc.w        InstrPage4Setup-.i      ; state 25 -> INSTR_SETUP4        (in instructions.asm)
    dc.w        InstrPage4Run-.i        ; state 26 -> INSTR_RUN4          (in instructions.asm)
.i_end  ; end of live table - (.i_end-.i)/2 = state count for the bounds check


;==============================================================================
; StateIdle  -  Placeholder handler for dispatch-table states whose subsystem
; is not part of the current build (currently unused — kept for wiring new
; states before their handlers exist).  Does nothing; the game stays in the
; current state.
;
; Destroys: none (preserves all registers)
;==============================================================================

StateIdle:
    rts


;==============================================================================
; GameRun  -  Main gameplay frame handler (called every VBlank in state 2)
;
; Architecture & Frame Timeline:
; -----------------------------------------------------------------------------
; The display is single-buffered, so every redraw (erase, then draw) is
; visible as it happens: it must finish before the beam reaches its lines.
; Each frame is split into two phases (see GameRunFrame):
;
;   Phase 1 (raster bar yellow): the priority work, the objects in the top
;     rows (screen Y < ENTITY_TOP_TIER_Y), top of the screen first, with the
;     player's core (erase, blit, tint) before them when it is up there too.
;     SetRasterLogicColor then turns the bar green.
;
;   Phase 2 (green): the remaining objects in screen order, GameDrawHook, then
;     the logic:
;         * UpdateControls: read keyboard/joystick into trigger/hold bitmasks
;         * GameLogicHook: player state machine, pickups, collisions
;         * TilemapUpdateCamera: scroll the camera (takes effect next frame)
;         * TilemapUpdateWater: advance the rising water
;         * GamePostLogicHook, GameActorPhaseHook, GameDrawEntitiesHook: game-side
;           updates interleaved with the engine's actor animation and push-block draw
;
; The full draw order and the rules that keep it tear-free are in
; docs/BLIT_ORDER_GUIDE.pdf. Read it before adding or moving any blit.
;
; In: a5 = Variables base, a6 = CUSTOM
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

GameRun:
    bsr         LevelTest
    cmp.w       #GAME_RUN,GameStatus(a5)
    bne         .skip
    bsr         GameRunQuitFade         ; ESC: fade to black, then back to the title
    tst.w       d0
    bne         .skip
    bsr         GameRunPauseKey         ; P: toggle pause banner
    tst.w       d0
    bne         .skip

    ; Clear any VBlank overruns accumulated during the unwind / restore frame
    tst.b       VhsJustFinished
    beq.s       .no_post_unwind
    clr.b       VhsJustFinished
    clr.w       VBlankOverrunCount(a5)  ; clean 0 overruns post unwind
.no_post_unwind:
    bsr         GameRunSlowMode         ; S / A: frame-step debugger
    tst.w       d0
    bne         .check_debug_keys
    bsr         GameRunRewind           ; F9 / VHS rewind, runs inside VBlank
    tst.w       d0
    bne         .check_debug_keys
    bsr         GameRunFrame            ; the per-frame blit + logic pipeline
.check_debug_keys:
    bsr         GameRunDebugKeys        ; F1-F5, D: developer keys
.skip:
    rts



;==============================================================================
; GameRunQuitFade  -  ESC key and the fade-to-black back to the title screen
;
; Out: d0 = 1 to skip the rest of the frame (fading or just started), 0 to continue
;
; In:  a5 = Variables base, a6 = CUSTOM chip base
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

GameRunQuitFade:

    ; ---------------------------------------------------------------------
    ; ESC Fade-to-Black Progression
    ; ---------------------------------------------------------------------
    tst.w       QuitFadeActive(a5)
    beq.s       .no_quit_fade

    bsr         PaletteFadeTick         ; returns d0=1 once cpPal has reached black
    tst.w       SkyFadeMode(a5)
    beq.s       .qf_sky_done
    bsr         TilemapUpdateCopperSky  ; dim the sky by the same step (preserves d0)
.qf_sky_done:
    tst.w       d0
    beq         .skip_frame             ; freeze player/actors while fading
    cmp.w       #FADE_MAX_STEPS,PalFadeStep(a5)
    blo         .skip_frame             ; palette black, brighter sky colours still dimming

    ; Screen is 100% black: clean up and transition
    clr.w       QuitFadeActive(a5)
    clr.w       SkyFadeMode(a5)
    bsr         AudioStopMod            ; silence music on black screen
    clr.w       CustomLevelLoaded(a5)
    clr.l       CustomLevelDef(a5)
    clr.w       SlowMode(a5)
    tst.w       GamePaused(a5)
    beq.s       .esc_not_paused
    bsr         TilemapErasePauseBanner
    clr.w       GamePaused(a5)
.esc_not_paused:
    lea         Keys,a0
    clr.b       KEY_P(a0)
    clr.w       DebugOverlayActive(a5)
    clr.w       PrevDebugDrawn(a5)
    move.w      #TITLE_SETUP,GameStatus(a5)
    bra         .skip_frame
.no_quit_fade:

    ; -------------------------------------------------------------------------
    ; ESC Key: Trigger Fade Out to Title Screen
    ; -------------------------------------------------------------------------
    lea         Keys,a0
    tst.b       KEY_ESC(a0)
    beq.s       .no_esc
    clr.b       KEY_ESC(a0)
    clr.b       KEY_P(a0)

    ; Start fade-to-black instead of abrupt jump. The sky fades with the palette,
    ; unless the game is paused: the pause has desaturated cpGameSky in place, so
    ; the sky is dropped instead of being rebuilt from CopperSkyTable.
    tst.w       GamePaused(a5)
    beq.s       .esc_sky_fade
    bsr         TilemapDisableCopperSky
    bra.s       .esc_palette_fade
.esc_sky_fade:
    move.w      #SKY_FADE_OUT,SkyFadeMode(a5)
.esc_palette_fade:
    lea         cpPal,a0
    move.w      #FADE_SPEED_SLOW,d0   ; 15 steps x 4 frames = ~1.2s (PAL)
    bsr         PaletteFadeOut
    move.w      #1,QuitFadeActive(a5)
    bra         .skip_frame
.no_esc:
    moveq       #0,d0                   ; continue the frame
    rts
.skip_frame:
    moveq       #1,d0                   ; caller skips the rest of the frame
    rts

;==============================================================================
; GameRunPauseKey  -  P key: toggle the pause banner
;
; Out: d0 = 1 while paused (caller skips the frame), 0 when running
;
; In:  a5 = Variables base, a6 = CUSTOM chip base
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

GameRunPauseKey:

    ; -------------------------------------------------------------------------
    ; 'P' Key: Toggle PAUSE / UNPAUSE
    ; -------------------------------------------------------------------------
    lea         Keys,a0
    tst.b       KEY_P(a0)
    beq.s       .no_key_p
    clr.b       KEY_P(a0)              ; consume key press immediately
    eori.w      #1,GamePaused(a5)      ; toggle pause state
    beq.s       .p_toggled_off
    ; Toggled ON: draw pause banner
    bsr         TilemapDrawPauseBanner
    bra.s       .no_key_p
.p_toggled_off:
    ; Toggled OFF: erase pause banner cleanly
    bsr         TilemapErasePauseBanner
    clr.w       VBlankOverrunCount(a5)  ; clear unpause redraw overruns
.no_key_p:

    ; Check if game is paused
    moveq       #0,d0
    tst.w       GamePaused(a5)
    beq.s       .running
    moveq       #1,d0                   ; paused: caller skips the frame
.running:
    rts

;==============================================================================
; GameRunSlowMode  -  S toggles slow mode; A steps one frame or runs while held
;
; Out: d0 = 1 when the frame is held (overlay drawn), 0 to run the frame
;
; In:  a5 = Variables base, a6 = CUSTOM chip base
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

GameRunSlowMode:

    ; -------------------------------------------------------------------------
    ; 'S' Key: Toggle SLOW MODE / Frame Step Debugger
    ; -------------------------------------------------------------------------
    lea         Keys,a0
    tst.b       KEY_S(a0)
    beq.s       .no_key_s
    clr.b       KEY_S(a0)              ; consume key press immediately
    eori.w      #1,SlowMode(a5)        ; toggle SlowMode flag
    beq.s       .s_toggled_off         ; toggled off -> normal mode
    ; Toggled ON: enter SLOW MODE
    clr.w       SlowModeHold(a5)
    move.w      #1,DebugOverlayActive(a5) ; enable debug overlay in Slow Mode
    bra.s       .no_key_s
.s_toggled_off:
    ; Toggled OFF: exit SLOW MODE
    clr.w       SlowModeHold(a5)
    clr.w       DebugOverlayActive(a5) ; disable debug overlay
    bsr         TilemapEraseDebugOverlay ; cleanly restore background on exit
.no_key_s:

    ; Check if SLOW MODE is active
    tst.w       SlowMode(a5)
    beq.s       .slow_mode_ok          ; normal mode: run frame normally

    ; In SLOW MODE:
    ;   - Tap 'A' (press & release): advance by exactly one frame iteration
    ;   - Hold 'A' (press & hold): advance at full speed continuously
    lea         Keys,a0
    tst.b       KEY_A(a0)
    bne.s       .a_down

    ; 'A' is NOT pressed: reset hold counter and pause execution
    clr.w       SlowModeHold(a5)
    bra.s       .slow_paused

.a_down:
    move.w      SlowModeHold(a5),d0
    cmp.w       #SLOW_MODE_HOLD_DELAY,d0
    bge.s       .slow_mode_ok          ; held >= SLOW_MODE_HOLD_DELAY: advance at full speed!
    addq.w      #1,SlowModeHold(a5)    ; increment hold counter
    tst.w       d0
    beq.s       .slow_mode_ok          ; d0 == 0: initial press -> advance 1 iteration!
                                       ; 1..delay-1: fall through to pause while waiting for hold delay

.slow_paused:
    ; Paused in SLOW MODE: keep debug overlay drawn and fresh with MODE:SLOW
    bsr         SetRasterLogicColor
    bsr         TilemapDrawDebugOverlay
    bra         .hold_frame

.slow_mode_ok:
    moveq       #0,d0                   ; run the frame
    rts
.hold_frame:
    moveq       #1,d0                   ; frame held: caller goes straight to the debug keys
    rts

;==============================================================================
; GameRunRewind  -  F9 / VHS rewind trigger and per-frame effect update (inside VBlank)
;
; Out: d0 = 1 when the rewind consumed this frame, 0 to run the normal frame
;
; In:  a5 = Variables base, a6 = CUSTOM chip base
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

GameRunRewind:
    ; -------------------------------------------------------------------------
    ; 0. VHS Rewind Trigger & Frame Update: Run exclusively in VBlank (Scanlines 0..15)!
    ; -------------------------------------------------------------------------
    ; Checking KEY_F9 and running VhsDoFrame right at the start of VBlank guarantees
    ; that UndoMove (entity erase + redraw) and VhsStartEffect / VhsDoFrame finish
    ; BEFORE the CRT raster beam reaches WINDOW_Y_START (line 44), and prevents
    ; post-PlayerLogic routines from overwriting the VHS rewind frame!
    tst.b       VhsStateActive
    beq.s       .check_initial_f9

    ; Allow rapid consecutive F9 presses while the rewind effect is already running
    lea         Keys,a0
    tst.b       KEY_F9(a0)
    beq.s       .vhs_step_frame
    clr.b       KEY_F9(a0)
    cmp.w       #2,SnapshotCount(a5)
    blt.s       .vhs_step_frame
    bsr         VhsStopEffect          ; cleanly restore screen & palette before next undo
    bsr         UndoMove                ; snap back one more checkpoint
    bsr         VhsStartEffect         ; start fresh rewind effect & draw Frame 0
    bsr         AudioPlayRewind
    bra         .handled

.vhs_step_frame:
    bsr         VhsDoFrame             ; update snow bar, 3 streaks, 'REW  <<', & copper tears in VBlank
    tst.w       d0                      ; 0 = effect just finished & restored clean screen
    bne        .exit_check_debug_keys       ; still running -> freeze scene & keep effect 100% solid!
    clr.w       VBlankOverrunCount(a5)  ; effect just finished -> resume normal gameplay!
    bra         .run_frame

.check_initial_f9:
    ; Check initial F9 press at the very start of VBlank when player is idle and not drowning
    bsr         GameUndoAllowedHook     ; d0 = 0 when the game permits a rewind now
    tst.w       d0
    bne.s        .exit_normal_gameplay_frame
    cmp.w       #ACTION_IDLE,ActionStatus(a5)
    bne.s        .exit_normal_gameplay_frame
    lea         Keys,a0
    tst.b       KEY_F9(a0)
    beq.s        .exit_normal_gameplay_frame
    clr.b       KEY_F9(a0)
    cmp.w       #2,SnapshotCount(a5)
    blt.s        .exit_normal_gameplay_frame
    bsr         UndoMove
    bsr         VhsStartEffect
    bsr         AudioPlayRewind
    bra         .handled
.exit_check_debug_keys:
    bra         .handled
.exit_normal_gameplay_frame:
    bra         .run_frame
.run_frame:
    moveq       #0,d0                   ; no rewind this frame
    rts
.handled:
    moveq       #1,d0                   ; rewind consumed the frame
    rts

;==============================================================================
; GameRunFrame  -  One normal gameplay frame: VBlank blits, controls, logic, actors, dirty tiles
;
; In:  a5 = Variables base, a6 = CUSTOM chip base
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

GameRunFrame:

    ; Draw order matters: see docs/BLIT_ORDER_GUIDE.pdf before changing it.
    ;
    ; Beam-raced drawing. The game's moving entities (GameDrawPriorityHook)
    ; are drawn top of the screen first, in two slices: the top rows
    ; (screen Y < ENTITY_TOP_TIER_Y) are the priority work, and the raster
    ; bar stays yellow until they are done, then turns green.
    ;
    ; In whichever phase the player belongs to, its core (erase, BOB blit and
    ; water tint) runs first, so the entities drawn after it stay in front of
    ; the player and its erase can never wipe one. Its slower extras (stamps,
    ; overlap repair) run after the entities, so they never hold an entity
    ; back from the beam. The player belongs to the priority phase
    ; when its key (PlayerDrawKeyY) is in the top rows: then a top-row entity
    ; could overlap it and must be drawn after its erase.
    move.w      #DMAF_SETCLR|DMAF_BLITHOG,DMACON(a6) ; Phase 1: blitter priority on
    bsr         PlayerDrawKeyY       ; d0 = player's key screen Y
    move.w      d0,-(sp)             ; (sp) = P
    cmp.w       #ENTITY_TOP_TIER_Y,d0
    bge.s       .p1_entities
    bsr         GameRunDrawPlayerCore ; Phase 1, player in the top rows: core first
.p1_entities:
    move.w      #-32768,d0
    move.w      #ENTITY_TOP_TIER_Y,d1
    bsr         GameDrawPriorityHook ; top-row entities, top first
    cmp.w       #ENTITY_TOP_TIER_Y,(sp)
    bge.s       .p1_done
    bsr         GameRunDrawPlayerExtras ; then the player's extras
.p1_done:
    move.w      #DMAF_BLITHOG,DMACON(a6) ; Phase 1 done: blitter priority off
    bsr         SetRasterLogicColor  ; priority work done -> switch from Yellow to Green/Red

    cmp.w       #ENTITY_TOP_TIER_Y,(sp)
    blt.s       .p2_entities
    bsr         GameRunDrawPlayerCore ; Phase 2, player lower down: core first
.p2_entities:
    move.w      #ENTITY_TOP_TIER_Y,d0
    move.w      #32767,d1
    bsr         GameDrawPriorityHook ; remaining entities, top first
    cmp.w       #ENTITY_TOP_TIER_Y,(sp)+
    blt.s       .p2_done
    bsr         GameRunDrawPlayerExtras ; then the player's extras
.p2_done:
    bsr         GameDrawHook         ; game blits the rest, chasing the beam

    ; -------------------------------------------------------------------------
    ; 1. CPU-Side Game Logic & Collision Phase (Active Raster, Scanlines 20..100)
    ; -------------------------------------------------------------------------
    bsr         UpdateControls       ; read keyboard/joystick, compute trigger/hold bytes
    bsr         GameLogicHook        ; player state machine, pickups and collisions
    bsr         TilemapUpdateCamera  ; dynamically scroll camera if player moves up/down
    tst.w       SlowMode(a5)
    beq.s       .no_slow_cam_erase
    bsr         TilemapEraseDebugOverlay ; erase old debug text if camera moved in slow mode
.no_slow_cam_erase:
    bsr         TilemapUpdateWater   ; advance rising water layer (16px per 10 seconds)
    bsr         GamePostLogicHook    ; game state that depends on camera/water (HUD, survival timers)

    ; -------------------------------------------------------------------------
    ; 2. Particle Systems & Ambient Effects
    ; -------------------------------------------------------------------------
    bsr         AnimateEnemies       ; cycle ENEMYFALL/ENEMYFLOAT tile frames (2fps)

    ; -------------------------------------------------------------------------
    ; 3. Static Layer & In-World Objects
    ; -------------------------------------------------------------------------
    bsr         GameActorPhaseHook   ; game-driven actor animation (falling crates, impact smoke)
    bsr         TilemapDrawPushBlocks ; render movable crates / push blocks
    bsr         GameDrawEntitiesHook ; game draws its remaining dynamic entities

    ; -------------------------------------------------------------------------
    ; 4. Settle Dirty Tiles
    ; -------------------------------------------------------------------------
    bsr         FlushDirtyTiles      ; redraw settled actors/frozen player at dirty tile cells

    tst.w       SlowMode(a5)
    beq.s       .no_slow_hud
    bsr         TilemapDrawDebugOverlay ; draw green debug HUD on top of active stepped frame
.no_slow_hud:
    rts

;==============================================================================
; GameRunDrawPlayerCore  -  Erase, redraw and water-tint the player BOB
;
; The tint belongs with the blit: if the beam reached the player between the
; two, that frame would show it dry. It costs one compare when the player is
; out of the water.
;
; Destroys: d0-d7/a0-a4 (preserves a5/a6)
;==============================================================================

GameRunDrawPlayerCore:
    lea         Player(a5),a4
    bsr         TilemapErasePlayer   ; restore pristine background at player's previous footprint
    lea         Player(a5),a4
    bsr         TilemapDrawPlayerCore ; draw player BOB with PlayerMsk ($0FCA cookie-cutter)
    lea         Player(a5),a4
    bsr         TilemapSubmergePlayer ; apply water tinting straight away
    rts


;==============================================================================
; GameRunDrawPlayerExtras  -  Stamps and overlap repair
;
; The slower half of the player's draw, run after the beam-raced entities.
;
; Destroys: d0-d7/a0-a4 (preserves a5/a6)
;==============================================================================

GameRunDrawPlayerExtras:
    lea         Player(a5),a4
    bsr         TilemapStampOverPlayer ; foreground / ladder scenery in front of the player
    bsr         GameRestoreOverlapsHook ; game re-draws its entities caught in the player erase span
    rts


;==============================================================================
; GameRedrawHeldFrame  -  Redraw the scene without advancing the game
;
; A frame held in Slow Mode draws nothing, so when D turns the HUD off, this
; puts back everything the erase wiped. It uses GameRunFrame's draw order.
;
; Destroys: d0-d7/a0-a4 (preserves a5/a6)
;==============================================================================

GameRedrawHeldFrame:
    bsr         GameRunDrawPlayerCore
    bsr         TilemapRedrawDrawnEnemies
    bsr         GameRunDrawPlayerExtras
    bsr         TilemapDrawPushBlocks
    bsr         GameDrawEntitiesHook
    bsr         FlushDirtyTiles
    rts


;==============================================================================
; PlayerDrawKeyY  -  Which phase the player's draw belongs to
;
; The player is erased from its old footprint and drawn at its new one, so
; the key is whichever starts higher on screen, moved up a further 15 lines
; (entities are 16 lines tall). When the key is above ENTITY_TOP_TIER_Y, a
; top-row entity could overlap the player, so the player's core must run in
; the priority phase, before those entities are drawn. Screen Y is world Y -
; TilemapCameraY.
;
; Out: d0.w = key screen Y
; Destroys: d1 (preserves everything else)
;==============================================================================

PlayerDrawKeyY:
    move.l      a4,-(sp)
    lea         Player(a5),a4
    move.w      Player_Y(a4),d0
    lsl.w       #4,d0
    add.w       Player_YDec(a4),d0
    subq.w      #8,d0                   ; d0 = new BOB top (world Y), as TilemapDrawPlayer
    tst.w       Player_PrevDrawn(a4)
    beq.s       .pdky_have_top
    move.w      Player_PrevY(a4),d1     ; old footprint top (world Y)
    cmp.w       d0,d1
    bge.s       .pdky_have_top
    move.w      d1,d0                   ; the higher of the two
.pdky_have_top:
    sub.w       TilemapCameraY(a5),d0   ; screen Y
    sub.w       #15,d0                  ; entities that could overlap sort after the player
    move.l      (sp)+,a4
    rts


;==============================================================================
; GameRunDebugKeys  -  F1/F2 level warp, F4 game complete, F5 debug mode, D overlay, F3 raster bar
;
; In:  a5 = Variables base, a6 = CUSTOM chip base
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

GameRunDebugKeys:

    ; F1: warp to previous level (debug mode only)
    lea         Keys,a0
    tst.b       KEY_F1(a0)
    beq.s       .no_f1
    clr.b       KEY_F1(a0)
    tst.w       DebugMode(a5)
    beq.s       .no_f1
    tst.w       LevelId(a5)
    beq.s       .no_f1
    subq.w      #1,LevelId(a5)
    bsr         AudioStopMod
    move.w      #LEVEL_INIT,GameStatus(a5)
    rts
.no_f1:

    ; F2: warp to next level (debug mode only)
    lea         Keys,a0
    tst.b       KEY_F2(a0)
    beq.s       .no_f2
    clr.b       KEY_F2(a0)
    tst.w       DebugMode(a5)
    beq.s       .no_f2
    cmp.w       #LEVEL_TABLE_COUNT-1,LevelId(a5)
    beq.s       .no_f2
    addq.w      #1,LevelId(a5)
    bsr         AudioStopMod
    move.w      #LEVEL_INIT,GameStatus(a5)
    rts
.no_f2:
    ; F4: jump directly to game complete screen (debug mode only)
    lea         Keys,a0
    tst.b       KEY_F4(a0)
    beq.s       .no_f4
    clr.b       KEY_F4(a0)
    tst.w       DebugMode(a5)       ; F4 only in debug mode (F5 to enable)
    beq.s       .no_f4
    move.w      #GAME_COMPLETE_SETUP,GameStatus(a5)
    rts
.no_f4:

    ; F5: enter/exit debug mode (enables F1/F2/F4; raster bar separately via F3)
    lea         Keys,a0
    tst.b       KEY_F5(a0)
    beq.s       .no_f5
    clr.b       KEY_F5(a0)
    tst.w       DebugMode(a5)
    beq.s       .f5_enable
    cmp.w       #2,DebugMode(a5)    ; was raster bar active?
    bne.s       .f5_no_bar
    bsr         TilemapEnableCopperSky ; restore copper sky gradient
.f5_no_bar:
    clr.w       DebugMode(a5)       ; was on (any value): exit debug mode + clear bar
    ; clr.w       DebugOverlayActive(a5) ; disable debug text overlay
    bra.s       .no_f5
.f5_enable:
    move.w      #1,DebugMode(a5)    ; enter debug mode (no raster bar yet)
    ; move.w      #1,DebugOverlayActive(a5) ; enable debug text overlay
.no_f5:

    ; 'D': debug text overlay (Slow Mode only)
    lea         Keys,a0
    tst.b       KEY_D(a0)
    beq.s       .no_key_d
    clr.b       KEY_D(a0)
    tst.w       SlowMode(a5)
    beq.s       .no_key_d           ; Option A: only active in Slow Mode
    eori.w      #1,DebugOverlayActive(a5)
    bne.s       .d_turned_on
    bsr         TilemapEraseDebugOverlay ; toggled off: erase HUD
    bsr         GameRedrawHeldFrame      ; put back what the erase wiped
    bra.s       .no_key_d
.d_turned_on:
    bsr         TilemapDrawDebugOverlay  ; toggled on: draw HUD
.no_key_d:

    ; F3: toggle raster CPU-timing bar (debug mode must be active via F5 first)
    lea         Keys,a0
    tst.b       KEY_F3(a0)
    beq.s       .no_f3
    clr.b       KEY_F3(a0)
    tst.w       DebugMode(a5)       ; bar only available in debug mode
    beq.s       .no_f3
    cmp.w       #2,DebugMode(a5)
    beq.s       .f3_bar_off
    move.w      #2,DebugMode(a5)    ; enable raster bar
    clr.w       VBlankOverrunCount(a5)  ; reset overrun count so profiler starts fresh
    bsr         TilemapDisableCopperSky ; halt copper before sky gradient so bar is visible
    bra.s       .no_f3
.f3_bar_off:
    move.w      #1,DebugMode(a5)    ; disable raster bar (stay in debug mode)
    bsr         TilemapEnableCopperSky  ; restore copper sky gradient
.no_f3:

    rts
