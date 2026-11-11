;==============================================================================
; AMIGA GAME ENGINE
; engine_main.asm  -  Engine Lifecycle Framework & Execution Bootstrap
;==============================================================================
;
; This module provides the standard bare-metal Amiga application lifecycle:
;
;   1. Main        - Program entry point from AmigaDOS CLI / Workbench.
;                    Saves registers, snapshots CLI stack, captures OS context,
;                    and executes SystemSave.
;   2. Restart     - Resets custom chip registers to neutral baseline ($7fff),
;                    switches CPU to dedicated GameStack, calls EngineInit,
;                    installs vertical-blank interrupt via StartVBlank, and
;                    enters MainLoop.
;   3. MainLoop    - Decoupled frame execution model: synchronizes on
;                    FramePending signal from VBlankTick, provides raster-line
;                    CPU profiler instrumentation, calls GameStatusRun each
;                    frame, and loops until QuitFlag is non-zero.
;   4. QuitToOS    - Clean teardown: silences interrupts, stops music playback
;                    and CIA-B timers, restores OS system vectors and copper
;                    via SystemRestore, restores CLI stack, and exits to AmigaDOS
;                    with return code 0.
;   5. EngineInit  - Resets frame state flags, performs automatic hardware
;                    detection (PAL/NTSC, ECS/OCS), attaches keyboard scanner,
;                    installs 68000 fault interception traps, and calls the
;                    game-specific bootstrap hook: GameInitHook.
;
; Callbacks required from the game layer:
;   GameInitHook   - Called once during EngineInit to set up initial game state
;   GameStatusRun  - Called once per frame by MainLoop to execute the active state
;
; Equates / symbols expected from the configuration headers:
;   Variables, GameStackTop, SavedOSStack, CUSTOM
;   DEBUG_RASTER_VBLANK (defaults to $0ff0)
;   DEBUG_RASTER_COLOR (defaults to $00f0)
;   DEBUG_RASTER_OVERRUN (defaults to $0f00)
;
;==============================================================================

    section    main,code
    even

;==============================================================================
; Main  -  Program entry point (invoked from CLI / Workbench)
;
; Saves the OS context (all registers + stack pointer, including Kickstart 1.3
; BCPL frame registers a1/a2/a5/a6), takes over custom silicon cleanly via
; SystemSave (system.asm), then falls into Restart.
; Pressing ESC on the title screen cleanly hands control back via QuitToOS.
;
; Destroys: d0 (preserves d1-d7/a0-a6)
;==============================================================================

Main:
    movem.l    d1-d7/a0-a6,-(sp)   ; save OS/BCPL registers (restored by QuitToOS)
    move.l     sp,SavedOSStack     ; CLI stack, restored on exit
    bsr        WorkbenchStartup    ; Workbench launch: collect the startup message
    IFD CUSTOM_LEVEL_PROBE
    bsr        CheckCustomLevel    ; probe test.lvl or CLI argument before OS teardown
    ENDC
    bsr        SystemSave          ; blank OS display, Forbid, snapshot vectors/enables

;==============================================================================
; Restart  -  Hardware initialisation and main loop entry
;
; Resets custom chip registers, switches to the game's dedicated GameStack,
; initialises subsystems, installs the VBlank interrupt, and enters MainLoop.
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
;==============================================================================

Restart:
    lea        CUSTOM,a6
    lea        Variables,a5
    lea        GameStackTop,sp     ; independent from CLI stack allocation
    move.w     #$7fff,DMACON(a6)
    move.w     #$7fff,ADKCON(a6)
    move.w     #$7fff,INTENA(a6)
    move.w     #$7fff,INTREQ(a6)
    bsr        StopDriveMotors     ; the boot floppy's motor may still be running

    bsr        EngineInit
    bsr        StartVBlank

;==============================================================================
; MainLoop  -  Decoupled mainline frame loop
;
; Waits for FramePending signal from VBlankTick, then runs one frame of logic.
; Long operations (decompression, level loading) span frames without starving
; interrupts or re-entering game state code.
;
; Destroys: d0-d1/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

MainLoop:
.waitframe:
    tst.w      FramePending(a5)    ; set by VBlankTick once per video frame
    beq.s      .waitframe
    clr.w      FramePending(a5)    ; consume frame gate
    move.w     #1,FrameBusy(a5)    ; a VBlank from here on means this frame is late

    ; Raster profiler: DebugMode=2 (F5 then F3)
    cmp.w      #2,DebugMode(a5)
    bne.s      .no_bar_start
    move.w     #DEBUG_RASTER_VBLANK,d0
    tst.w      VBlankOverrunCount(a5)
    beq.s      .bar_normal
    move.w     #DEBUG_RASTER_OVERRUN,d0 ; alert on frame overrun
.bar_normal:
    move.w     d0,COLOR00(a6)
.no_bar_start:

    bsr        GameStatusRun       ; execute one frame of the active game state

    cmp.w      #2,DebugMode(a5)
    bne.s      .no_bar_end
    move.w     #$0000,COLOR00(a6)  ; copper resets COLOR00 at next frame start
.no_bar_end:

    clr.w      FrameBusy(a5)       ; frame finished
    tst.w      FramePending(a5)    ; did a VBlank fire while it ran?
    bne.s      .frame_late
    clr.w      VBlankOverrunCount(a5) ; on time: bar returns to normal
.frame_late:

    tst.w      QuitFlag(a5)        ; set by TitleRun on ESC
    beq.s      MainLoop

;==============================================================================
; QuitToOS  -  Clean teardown and return to AmigaDOS CLI
;
; Reached from MainLoop when QuitFlag is set. Stops music, uninstalls the
; PTPlayer CIA-B interrupt, restores the full OS state (SystemRestore), then
; returns to the original caller on the original stack with return code 0.
;
; Destroys: d0 (preserves d1-d7/a0-a6)
;==============================================================================

QuitToOS:
    move.w     #$7fff,INTENA(a6)   ; silence interrupts before teardown
    bsr        AudioStopMod
    bsr        AudioRemove         ; uninstall PTPlayer CIA-B interrupt
    bsr        KeyboardRemove      ; give CIA-A timer B back to the OS
    bsr        SystemRestore       ; restore OS copper, DMA, INTENA, vectors

    IFD CUSTOM_LEVEL_PROBE
    ; Free custom level buffer if one was allocated via AllocMem
    tst.l      CustomLevelAllocPtr(a5)
    beq.s      .no_custom_mem
    move.l     4.w,a6              ; ExecBase
    move.l     CustomLevelAllocPtr(a5),a1
    move.l     CustomLevelAllocSize(a5),d0
    jsr        _LVOFreeMem(a6)     ; defined in customlevel.asm
.no_custom_mem:
    ENDC

    move.l     SavedOSStack,sp
    bsr        WorkbenchReply      ; Workbench launch: return the startup message
    movem.l    (sp)+,d1-d7/a0-a6
    moveq      #0,d0               ; CLI return code: OK
    rts

;==============================================================================
; EngineInit  -  Engine bootstrap and hardware environment initialisation
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
;==============================================================================

EngineInit:
    clr.w      QuitFlag(a5)
    clr.w      FramePending(a5)
    clr.w      FrameBusy(a5)
    clr.w      NtscSkipPhase(a5)
    clr.w      VBlankOverrunCount(a5)

    bsr        DetectNTSC          ; detect PAL/NTSC first; sets IsPAL(a5)
    bsr        DetectOCS           ; detect OCS vs ECS chipset
    bsr        AudioInit           ; install CIA-B music interrupt
    bsr        KeyboardInit        ; attach CIA-A keyboard handler
    bsr        InstallFaultTraps   ; 68000 exception vector interception

    ; Call game-specific initialization hook
    bsr        GameInitHook
    rts

;==============================================================================
; SetRasterLogicColor  -  Transition raster bar from Yellow to Green/Red
;
; Destroys: d0 (preserves everything else, including a5/a6)
;==============================================================================

SetRasterLogicColor:
    cmp.w      #2,DebugMode(a5)
    bne.s      .exit
    move.w     d0,-(sp)
    move.w     #DEBUG_RASTER_COLOR,d0
    tst.w      VBlankOverrunCount(a5)
    beq.s      .ok
    move.w     #DEBUG_RASTER_OVERRUN,d0
.ok:
    move.w     d0,COLOR00(a6)
    move.w     (sp)+,d0
.exit:
    rts
