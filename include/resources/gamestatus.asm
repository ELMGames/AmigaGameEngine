
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
;    3 - LEVEL_INIT  (dispatches to LevelTransitionRun in mapstuff.asm)
;        One-shot per-level initialisation.  Called when a new level is loaded
;        and ready to play, but before the wipe effect starts.  Sets up the
;        wipe pattern and tile order, then advances GameStatus to LEVEL_WIPE (4).

;   4 - LEVEL_WIPE  (dispatches to LevelTransitionRun in mapstuff.asm)
;       Per-frame handler while the end-of-level wipe is running.
;       Blits WIPE_SPEED tiles black per frame until all 126 tiles are done,
;       then advances to LEVEL_HOLD (4).
;
;   5 - LEVEL_HOLD  (dispatches to LevelTransitionRun in mapstuff.asm)
;       Holds the all-black screen while the next level is built into NonDisplayScreen.
;       Counts down WipeHoldTick, then calls LevelRevealSetup and advances to
;       LEVEL_REVEAL (5).
;
;   6 - LEVEL_REVEAL  (dispatches to LevelTransitionRun in mapstuff.asm)
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
;   States 11-16 (instructions / game complete) are not yet in the live table;
;   reaching them (e.g. completing level 100) hits the bounds check ->
;   FaultTrap until they are enabled in Phase B (see docs/AC_STEP_BY_STEP.md).
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
;   2. Install cpTest copper list and start Copper (COPJMP1)
;   3. Set ScreenMemEnd sentinel to -1
;   4. Enable DMA (BASE_DMA)
;   5. Set LevelId = START_LEVEL and call DrawMap to render the opening level
;==============================================================================

GameInit:
    bsr        GameCopperInit

    lea        DisplayScreen,a0        ; clear loading screen bitmap before game copper takes over
    move.l     #SCREEN_SIZE,d7
    bsr        TurboClear

    move.l     #cpTest,COP1LC(a6)
    move.w     #0,COPJMP1(a6)
    bsr        VHS_Init            ; set VHS distortion region scanlines (PAL/NTSC)

    move.l     #-1,ScreenMemEnd
 ;   move.w     #BASE_DMA,DMACON(a6)
    rts

;==============================================================================
; GameCopperInit  -  Patch the game copper list with screen and palette data
;
; Called from GameInit before the copper list is activated.  Fills in the
; runtime-variable fields of cpTest that the assembler left as zeros:
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
    move.w      GameStatus(a5),d0    ; load current state index
    cmp.w       #(.i_end-.i)/2,d0    ; index beyond the dispatch table?
    bcc         FaultTrap            ; corrupt state -> red screen, not a wild jump
    JMPINDEX    d0                   ; computed jump through offset table below

.i  ; jump-offset table - one signed word per state
    dc.w        LoadingSetup-.i           ; state 0 -> LoadingSetup          (in loading.asm)
    dc.w        LoadingRun-.i             ; state 1 -> LoadingRun            (in loading.asm)
    dc.w        GameRun-.i              ; state 2 -> GameRun             (below)
    dc.w        LevelTransitionRun-.i   ; state 3 -> LEVEL_INIT phase    (in mapstuff.asm)
    dc.w        LevelTransitionRun-.i   ; state 4 -> LEVEL_WIPE phase    (in mapstuff.asm)
    dc.w        LevelTransitionRun-.i   ; state 5 -> LEVEL_HOLD phase    (in mapstuff.asm)
    dc.w        LevelTransitionRun-.i   ; state 6 -> LEVEL_REVEAL phase  (in mapstuff.asm)
    dc.w        LevelCompleteSetup-.i   ; state 7 -> LEVEL_COMPLETE_SETUP (in levelcomplete.asm)
    dc.w        LevelCompleteRun-.i     ; state 8 -> LEVEL_COMPLETE_RUN  (in levelcomplete.asm)
    dc.w        TitleSetup-.i           ; state 9 -> TITLE_SETUP          (in titlescreen.asm)
    dc.w        TitleRun-.i             ; state 10 -> TITLE_RUN           (in titlescreen.asm)
    dc.w        InstrPage1Setup-.i      ; state 11 -> INSTR_SETUP1        (in instructions.asm)
    dc.w        InstrPage1Run-.i        ; state 12 -> INSTR_RUN1          (in instructions.asm)
    dc.w        InstrPage2Setup-.i      ; state 13 -> INSTR_SETUP2        (in instructions.asm)
    dc.w        InstrPage2Run-.i        ; state 14 -> INSTR_RUN2          (in instructions.asm)
    dc.w        GameCompleteSetup-.i    ; state 15 -> GAME_COMPLETE_SETUP (in gamecomplete.asm)
    dc.w        GameCompleteRun-.i      ; state 16 -> GAME_COMPLETE_RUN   (in gamecomplete.asm)
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
; Sequence each frame:
;   1. LevelTest      - check if LevelComplete flag is set or F1/F2 pressed;
;                       if LevelComplete, sets GameStatus to LEVEL_INIT (3) to start the transition.
;   2. UpdateControls - sample keyboard, update ControlsHold / ControlsTrigger.
;   3. PlayerLogic    - run the player's action state machine one step.
;                       The player pointer is loaded via lea Player(a5),a4
;                       into a4 before calling.
;   4. ActionCloudActors - animate enemy death cloud puff animations.
;   5. AnimateEnemies - cycle ENEMYFALL/ENEMYFLOAT tile frames at 2fps.
;
; Note: Player BOB frame selection is handled inside PlayerLogic / ActionPlayerFall
; via ShowPlayer, and rendered onto DisplayScreen in TilemapDrawPlayer.
;==============================================================================

GameRun:
    bsr         LevelTest            ; advance level if complete or F1/F2 pressed
    cmp.w       #GAME_RUN,GameStatus(a5) ; are we in GAME_RUN mode?
    bne         .skip                ; no (ie LEVEL_WIPE/HOLD/REVEAL): skip game logic

    ; ESC fade-to-black (commented out):
;    tst.w       QuitFadeActive(a5)
;    beq         .no_quit_fade
;    bsr         PaletteFadeTick         ; d0=1 once cpPal has reached black
;    tst.w       d0
;    beq         .skip
;    clr.w       QuitFadeActive(a5)
;    move.w      #TITLE_SETUP,GameStatus(a5)
;    bra         .skip
;.no_quit_fade

    ; ESC: stop music and return to title screen immediately
    lea         Keys,a0
    tst.b       KEY_ESC(a0)
    beq.s       .no_esc
    clr.b       KEY_ESC(a0)
    bsr         AudioStopMod
    move.w      #TITLE_SETUP,GameStatus(a5)
    bra         .skip
.no_esc:

    ; 'S': toggle SLOW MODE on/off
    lea         Keys,a0
    tst.b       KEY_S(a0)
    beq.s       .no_key_s
    clr.b       KEY_S(a0)              ; consume key press immediately
    eori.w      #1,SlowMode(a5)
    beq.s       .s_toggled_off         ; toggled off -> normal mode
    ; Toggled ON: enter SLOW MODE & enable debug overlay to show MODE:SLOW
    move.w      #1,DebugOverlayActive(a5)
    clr.w       SlowModeHold(a5)
    bra.s       .no_key_s
.s_toggled_off:
    ; Toggled OFF: exit SLOW MODE, disable debug overlay & erase it from screen
    clr.w       DebugOverlayActive(a5)
    bsr         TilemapEraseDebugOverlay
    clr.w       SlowModeHold(a5)
.no_key_s:

    ; Check if SLOW MODE is active
    tst.w       SlowMode(a5)
    beq.s       .slow_mode_ok          ; normal mode: run frame normally

    ; In SLOW MODE:
    ; - Tap 'A' (press & release): advance by one iteration
    ; - Hold 'A' (press & hold): advance at full speed continuously
    lea         Keys,a0
    tst.b       KEY_A(a0)
    bne.s       .a_down

    ; 'A' is NOT pressed: reset hold counter and pause
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
    bsr         TilemapDrawDebugOverlay
    bra         .check_debug_keys

.slow_mode_ok:
    bsr         UpdateControls       ; read keyboard, compute trigger/hold bytes

    bsr         ActionDirtActors     ; draw dirt crumble first so falling actors render on top

    ; Erase player and active enemies from last frame's position using pristine NonDisplayScreen
    lea         Player(a5),a4        ; a4 -> player structure
    bsr         TilemapErasePlayer
    bsr         TilemapEraseEnemies  ; erase all dynamic enemies before ANY new drawing happens

    bsr         PlayerLogic          ; run player action state machine for this frame
    bsr         TilemapUpdateCamera  ; dynamically scroll camera if player moves up/down
    bsr         TilemapEraseDebugOverlay ; erase old debug text if camera moved or overlay disabled
    bsr         TilemapUpdateWater   ; advance rising water layer every 10 seconds

    ; Draw player BOB on top of background platforms/ladders (with foreground & water depth)
    lea         Player(a5),a4        ; a4 -> player structure
    bsr         TilemapDrawPlayer

    bsr         ActionCloudActors    ; animate any pending enemy death cloud animations
    bsr         AnimateEnemies       ; cycle ENEMYFALL/ENEMYFLOAT tile frames (2fps)
    bsr         TilemapUpdateEnemies ; update dynamic enemy patrol movement, animation & blit
    bsr         UpdateCocoons        ; tick cocoon hatch countdowns + pulse animation

    bsr         FlushDirtyTiles      ; redraw settled actors/frozen player at all tiles marked dirty this frame

    bsr         TilemapDrawDebugOverlay ; draw green debug HUD on top of active frame

    ; VHS rewind effect: tick while active (started by the undo in ActionIdle)
    tst.b       VHS_StateActive
    beq.s       .no_vhs
    bsr         VHS_DoFrame          ; palette noise + scanline jitter; self-stops
.no_vhs:

.check_debug_keys:
    ; F4: jump directly to game complete screen (debug mode only)
    lea         Keys,a0
    tst.b       KEY_F4(a0)
    beq.s       .no_f4
    clr.b       KEY_F4(a0)
    tst.w       DebugMode(a5)       ; F4 only in debug mode (F5 to enable)
    beq.s       .no_f4
    move.w      #GAME_COMPLETE_SETUP,GameStatus(a5)
    bra.s       .skip
.no_f4:

    ; F5: enter/exit debug mode (enables F1/F2/F4; raster bar separately via F3)
    lea         Keys,a0
    tst.b       KEY_F5(a0)
    beq.s       .no_f5
    clr.b       KEY_F5(a0)
    tst.w       DebugMode(a5)
    beq.s       .f5_enable
    clr.w       DebugMode(a5)       ; was on (any value): exit debug mode + clear bar
    clr.w       DebugOverlayActive(a5) ; disable debug text overlay
    bra.s       .no_f5
.f5_enable:
    move.w      #1,DebugMode(a5)    ; enter debug mode (no raster bar yet)
    move.w      #1,DebugOverlayActive(a5) ; enable debug text overlay
.no_f5:

    ; 'D': toggle on-screen debug text overlay directly
    lea         Keys,a0
    tst.b       KEY_D(a0)
    beq.s       .no_key_d
    clr.b       KEY_D(a0)
    eori.w      #1,DebugOverlayActive(a5)
    bne.s       .no_key_d
    bsr         TilemapEraseDebugOverlay
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
    bra.s       .no_f3
.f3_bar_off:
    move.w      #1,DebugMode(a5)    ; disable raster bar (stay in debug mode)
.no_f3:

.skip:
    rts

