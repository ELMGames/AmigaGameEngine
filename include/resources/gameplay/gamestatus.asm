
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
;       then resets lives and returns to TITLE_SETUP.
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
;   3. Set ScreenMemEnd sentinel to -1
;   4. Enable DMA (BASE_DMA)
;   5. Set LevelId = START_LEVEL and call DrawMap to render the opening level
;==============================================================================

GameInit:
    bsr        GameCopperInit

    lea        DisplayScreen,a0        ; clear loading screen bitmap before game copper takes over
    move.l     #SCREEN_SIZE,d7
    bsr        TurboClear

    move.l     #cpGame,COP1LC(a6)
    move.w     #0,COPJMP1(a6)
    bsr        VHS_Init            ; set VHS distortion region scanlines (PAL/NTSC)

    move.l     #-1,ScreenMemEnd
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
;==============================================================================

GameCopperInit:
    bsr        ClearSprites            ; point all 8 sprite channels at NullSprite

    lea        cpPlanes,a0
    move.l     #DisplayScreen,d0
    move.l     #SCREEN_WIDTH_BYTE,d1
    moveq      #TILEMAP_TILE_PLANES,d7
    bsr        CopperSetPtrs           ; patch BPL1-4 pointers (shared, tools.asm)

    ; Load level palette into copper list (COLOR00-15 from Level_01_Palette, COLOR16-31 from SpritePal)
    lea        Level_01_Palette,a0
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

    bsr        InitHUDSprites          ; initialize hardware sprite HUD & palettes
    rts

;==============================================================================
; GameStatusRun  -  Dispatch to the current game state handler
;
; Called from MainLoop once per frame (gated by FramePending).
; a5 must be loaded with the Variables base before calling.
; a6 must be $dff000 (CUSTOM chip base).
;
; A corrupt GameStatus would jump through garbage offsets into random memory;
; the bounds check below turns that failure mode into the solid red
; FaultTrap screen instead (2 instructions — cheap enough to keep always on).
;
; No arguments.  Tail-calls the appropriate state handler via JMPINDEX.
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
;==============================================================================

StateIdle:
    rts


;==============================================================================
; GameRun  -  Main gameplay frame handler (called every VBlank in state 2)
;
; Architecture & Frame Timeline:
; -----------------------------------------------------------------------------
; The Amiga raster beam executes at 50Hz (PAL: 312 total scanlines, 216 visible,
; scanlines 0..43 represent the Vertical Blanking Interval).
;
; To achieve perfectly smooth, tear-free rendering without double-buffering latency,
; GameRun partitions every video frame into two strict phases:
;
;   Phase 1: Blitter Raster Rendering Pipeline (True VBlank, Scanlines 0..25)
;     - Beam Race Prevention: In top-of-screen rows (lines 44..108), the PAL beam
;       reaches display memory very quickly after VBlank. Player BOB erasure and
;       re-drawing are executed FIRST (lines 0..20) while the electron gun is still
;       blanked, completely preventing visible flicker or scanline tearing!
;     - Player Footprint Pipeline:
;         1. TilemapErasePlayer: restores clean background from NonDisplayScreen
;         2. TilemapDrawPlayer: blits player BOB with cookie-cutter mask ($0FCA)
;         3. TilemapRestorePlayerOverlaps: re-blits entities caught in player's erase span
;         4. TilemapSubmergePlayer: applies water tinting to player BOB if submerged
;     - Priority Summit Enemies:
;         * TilemapUpdateTopEnemies: update & blit priority enemies in Rows 0..2 (<48)
;     - Profiler Transition: SetRasterLogicColor transitions raster bar from Yellow to Green
;
;   Phase 2: Game Logic & Beam Chasing (Active Raster, Scanlines 25..311)
;     - Beam Chasing Dynamic Enemies:
;         * TilemapUpdateLowerEnemies: update & blit lower enemies in Rows 3+ (>=48)
;     - CPU Game Logic & Collision:
;         * UpdateControls: read keyboard/joystick into trigger/hold bitmasks
;         * PlayerLogic: advance active Player action state machine (walk, jump, fall, swim)
;         * PlayerCheckFriends: collision check against duckling companions
;         * PlayerCheckOxygen: collision check against oxygen refill tanks
;         * PlayerCheckEnemies: 2D AABB bounding-box collision check against hazards
;         * TilemapUpdateCamera: dynamically scroll camera if player moves up/down
;         * TilemapUpdateWater: advance rising water layer (16px per 10 seconds)
;         * PlayerUpdateOxygen: calculate submersion, oxygen depletion & safe ground
;         * UpdateHUDSprites: update Lives, Oxygen, and Bubble hardware sprite pointers
;
; In: a5 = Variables base, a6 = CUSTOM ($dff000)
; Destroys: d0-d7, a0-a4 (preserves a5, a6)
;==============================================================================

GameRun:
    bsr         LevelTest
    cmp.w       #GAME_RUN,GameStatus(a5)
    bne         .skip

    ; ---------------------------------------------------------------------
    ; ESC Fade-to-Black Progression
    ; ---------------------------------------------------------------------
    tst.w       QuitFadeActive(a5)
    beq.s       .no_quit_fade

    bsr         PaletteFadeTick         ; returns d0=1 once cpPal has reached black
    tst.w       d0
    beq         .skip                   ; freeze player/actors while fading

    ; Screen is 100% black: clean up and transition
    clr.w       QuitFadeActive(a5)
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
;    move.w      #0,LevelId(a5)
    move.w      #TITLE_SETUP,GameStatus(a5)
    bra         .skip
.no_quit_fade:

    ; -------------------------------------------------------------------------
    ; ESC Key: Trigger Fade Out to Title Screen
    ; -------------------------------------------------------------------------
    lea         Keys,a0
    tst.b       KEY_ESC(a0)
    beq.s       .no_esc
    clr.b       KEY_ESC(a0)
    clr.b       KEY_P(a0)

    ; Start fade-to-black instead of abrupt jump
    bsr         TilemapDisableCopperSky ; halt sky gradient so background fades with palette
    lea         cpPal,a0
    move.w      #FADE_SPEED_SLOW,d0   ; ~0.64s smooth linear fade
    bsr         PaletteFadeOut
    move.w      #1,QuitFadeActive(a5)
    bra         .skip
.no_esc:

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
    tst.w       GamePaused(a5)
    beq.s       .not_paused
    ; Paused: skip all gameplay updates and render pipeline
    bra         .skip
.not_paused:

    ; Clear any VBlank overruns accumulated during the unwind / restore frame
    tst.b       VHS_JustFinished
    beq.s       .no_post_unwind
    clr.b       VHS_JustFinished
    clr.w       VBlankOverrunCount(a5)  ; clean 0 overruns post unwind
.no_post_unwind:

    ; Restore previous frame's VHS noise bar & streaks before rendering starts
    tst.b       VHS_NoiseDrawn
    beq.s       .no_vhs_restore
    bsr         VHS_RestoreScreen
.no_vhs_restore:

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
    bra         .check_debug_keys

.slow_mode_ok:
    ; -------------------------------------------------------------------------
    ; 1. Blitter Raster Pipeline: Player BOB (True VBlank, Scanlines 0..20)
    ; -------------------------------------------------------------------------
    ; Blitting the player FIRST at the very start of VBlank ensures that
    ; PlayerErase, PlayerDraw, and Foreground Tile Stamping complete while the
    ; electron gun is still in vertical blanking (scanlines 0..25), completely
    ; eliminating scanline race tearing and foreground occlusion flicker!
    lea         Player(a5),a4        ; a4 -> player structure
    bsr         TilemapErasePlayer   ; restore pristine background at player's previous footprint
    bsr         TilemapDrawPlayer    ; draw player BOB with PlayerMsk ($0FCA cookie-cutter) + foreground stamp
    bsr         TilemapRestorePlayerOverlaps ; restore any adjacent entities wiped by player erase
    bsr         TilemapSubmergePlayer ; apply water tinting to player BOB
    bsr         TilemapUpdateTopEnemies ; update & blit priority enemies in Rows 0..2 (ScreenY < 48)
    bsr         SetRasterLogicColor  ; All VBlank priority blits complete -> switch from Yellow to Green/Red
    bsr         TilemapUpdateLowerEnemies ; chase beam: update & blit lower enemies in Rows 3+ (ScreenY >= 48)

    ; -------------------------------------------------------------------------
    ; 2. CPU-Side Game Logic & Collision Phase (Active Raster, Scanlines 20..100)
    ; -------------------------------------------------------------------------
    bsr         UpdateControls       ; read keyboard/joystick, compute trigger/hold bytes
    bsr         PlayerLogic          ; advance player action state machine for this frame
    bsr         PlayerCheckFriends   ; check collision between player and animal friends
    bsr         PlayerCheckOxygen    ; check collision between player and oxygen refills
    bsr         PlayerCheckEnemies   ; check collision between player and active enemies
    bsr         TilemapUpdateCamera  ; dynamically scroll camera if player moves up/down
    tst.w       SlowMode(a5)
    beq.s       .no_slow_cam_erase
    bsr         TilemapEraseDebugOverlay ; erase old debug text if camera moved in slow mode
.no_slow_cam_erase:
    bsr         TilemapUpdateWater   ; advance rising water layer (16px per 10 seconds)
    bsr         PlayerUpdateOxygen   ; update submersion, oxygen depletion/refill & safe ground
    bsr         UpdateHUDSprites     ; update Lives, Oxygen, and Bubble hardware sprites

    ; -------------------------------------------------------------------------
    ; 4. Particle Systems & Ambient Effects
    ; -------------------------------------------------------------------------
    bsr         ActionCloudActors    ; animate any pending enemy death cloud puff animations
    bsr         AnimateEnemies       ; cycle ENEMYFALL/ENEMYFLOAT tile frames (2fps)

    ; -------------------------------------------------------------------------
    ; 5. Static Layer & In-World Objects
    ; -------------------------------------------------------------------------
    bsr         ActionFallActors     ; animate falling push blocks / actors & landing smoke
    bsr         TilemapDrawPushBlocks ; render movable crates / push blocks
    bsr         TilemapDrawOxygen    ; render collectible oxygen canisters
    bsr         TilemapUpdateFriends ; update dynamic animal friends animation & blit

    ; -------------------------------------------------------------------------
    ; 6. Settle Dirty Tiles
    ; -------------------------------------------------------------------------
    bsr         FlushDirtyTiles      ; redraw settled actors/frozen player at dirty tile cells

    tst.w       SlowMode(a5)
    beq.s       .no_slow_hud
    bsr         TilemapDrawDebugOverlay ; draw green debug HUD on top of active stepped frame
.no_slow_hud:

    ; -------------------------------------------------------------------------
    ; 7. Post-Processing: VHS Rewind Special Effect
    ; -------------------------------------------------------------------------
    tst.b       VHS_StateActive
    beq.s       .no_vhs
    bsr         VHS_DoFrame          ; palette noise + scanline jitter; self-stops
    tst.w       d0                   ; 0 = effect just finished this frame
    bne.s       .no_vhs
    clr.w       VBlankOverrunCount(a5)  ; clear post-unwind overruns
.no_vhs:

.check_debug_keys:
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
    bra         .skip
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
    bra         .skip
.no_f2:
    ; F4: jump directly to game complete screen (debug mode only)
    lea         Keys,a0
    tst.b       KEY_F4(a0)
    beq.s       .no_f4
    clr.b       KEY_F4(a0)
    tst.w       DebugMode(a5)       ; F4 only in debug mode (F5 to enable)
    beq.s       .no_f4
    move.w      #GAME_COMPLETE_SETUP,GameStatus(a5)
    bra         .skip
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

.skip:
    rts

