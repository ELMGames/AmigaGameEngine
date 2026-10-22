;==============================================================================
; GAME ENGINE - AMIGA ASSEMBLY
; main.asm  -  Program Entry Point and Core Framework
;==============================================================================
;
; This is the top-level assembly file.  It:
;   1. Includes all headers (register/bit definitions, macros, variables, consts).
;   2. Defines the code section containing the program entry point (Main),
;      the VBlank interrupt handler (VBlankTick), and several utility routines
;      used across the game.
;   3. INCLUDEs all subsystem source files (keyboard, map, actors, player, etc.)
;      so the entire game assembles as a single translation unit.
;   4. Defines the data and BSS sections that lay out the game's static data,
;      compressed assets, Chip RAM buffers, and variable storage.
;
; Global register conventions (held constant after Init):
;   a5 = Variables base pointer  (Fast RAM BSS block)
;   a6 = $dff000  CUSTOM chip base
;   a4 = Player structure pointer (lea Player(a5),a4)
;   a3 = current Actor  structure pointer (set by actor routines)
;
;==============================================================================

    INCDIR     "include"
    INCDIR     "include/resources"
    INCDIR     "include/resources/core"
    INCDIR     "include/resources/audio"
    INCDIR     "include/resources/gameplay"
    INCDIR     "include/resources/graphics"
    INCDIR     "include/resources/levels"
    INCDIR     "include/resources/screens"
    INCDIR     "include/resources/system"

    INCLUDE    "hw.i"
    INCLUDE    "funcdef.i"

    include    "macros.asm"
    include    "variables.asm"

    include    "intbits.i"
    include    "dmabits.i"
    include    "const.asm"
    include    "struct.asm"

;==============================================================================
; Code section
;==============================================================================

    section    main,code

;==============================================================================
; Main  -  Program entry point (started from the CLI / Workbench)
;
; Saves the OS return context (callee-saved registers + stack pointer), takes
; over the machine via SystemSave (system.asm), then falls into Restart.
; The game can hand the machine back and return to the CLI: press ESC on the
; title screen (QuitToOS below).
;==============================================================================

Main:
    movem.l    d2-d7/a2-a6,-(sp)   ; callee-saved registers (restored by QuitToOS)
    move.l     sp,SavedOSStack     ; CLI stack, restored on exit
    bsr        CheckCustomLevel    ; probe test.lvl or CLI argument before OS teardown
    bsr        SystemSave          ; blank OS display, Forbid, snapshot vectors/enables


;==============================================================================
; Restart  -  Hardware initialisation and main loop
;
; Resets the Amiga custom chip environment to a known blank state, switches to
; the game's own stack, calls Init to set up game data structures, installs
; the VBlank interrupt, then runs the game from MainLoop.
;
; Frame model: VBlankTick (the level-3 ISR) only counts frames — ALL game
; logic runs here in the mainline, once per FramePending signal.  Long
; operations (asset decompression, screen setup) are therefore safe: they
; simply span several frames without blocking the keyboard or music
; interrupts, and the missed frames show up in VBlankOverrunCount.
;
; Sequence:
;   1. Load a6 = CUSTOM ($dff000), a5 = Variables base; switch to GameStack.
;   2. Disable all DMA, audio DMA key, interrupts, and clear all pending
;      interrupt requests (write $7fff to DMACON/ADKCON/INTENA/INTREQ).
;   3. Call Init  - initialise keyboard, game state, fault handlers, etc.
;   4. Call StartVBlank  - install VBlankTick at $6c and enable VERTB.
;   5. MainLoop: wait for a VBlank, run one frame of GameStatusRun, repeat
;      until QuitFlag is set, then exit to the OS via QuitToOS.
;==============================================================================

Restart:
    lea        CUSTOM,a6
    lea        Variables,a5
    lea        GameStackTop,sp     ; own stack: independent of the CLI stack size
    move.w     #$7fff,DMACON(a6)
    move.w     #$7fff,ADKCON(a6)
    move.w     #$7fff,INTENA(a6)
    move.w     #$7fff,INTREQ(a6)

    bsr        Init
    bsr        StartVBlank

MainLoop:
.waitframe

    tst.w      FramePending(a5)    ; set by VBlankTick once per video frame
    beq.s      .waitframe
    clr.w      FramePending(a5)    ; consume it (missed frames are skipped, not queued)

    ; Raster profiler: DebugMode=2 (F5 then F3) profiles the frame in phases:
    ;   - Yellow ($FF0): VBlank priority blits (must complete before scanline 44)
    ;   - Green  ($0F0): Active game logic & secondary blits (switched via SetRasterLogicColor)
    ;   - Red    ($F00): Frame overrun alert
    cmp.w      #2,DebugMode(a5)
    bne.s      .no_bar_start
    move.w     #DEBUG_RASTER_VBLANK,COLOR00(a6)
.no_bar_start

    bsr        GameStatusRun       ; one frame of the current game state

    cmp.w      #2,DebugMode(a5)
    bne.s      .no_bar_end
    move.w     #$0000,COLOR00(a6)  ; copper resets COLOR00 at next frame start
.no_bar_end

    tst.w      QuitFlag(a5)        ; set by TitleRun on ESC
    beq.s      MainLoop


;==============================================================================
; QuitToOS  -  Tear down the game and return cleanly to the CLI
;
; Reached from MainLoop when QuitFlag is set.  Stops music, uninstalls the
; PTPlayer CIA-B interrupt, restores the full OS state (SystemRestore), then
; returns to the original caller on the original stack with return code 0.
;==============================================================================

QuitToOS:
    move.w     #$7fff,INTENA(a6)   ; silence our interrupts before teardown
    bsr        AudioStopMod
    bsr        AudioRemove         ; uninstall the PTPlayer CIA-B interrupt
    bsr        SystemRestore       ; vectors, copper, DMA/INTENA, OS view

    ; Free custom level buffer if one was allocated via AllocMem
    tst.l      CustomLevelAllocPtr(a5)
    beq.s      .no_custom_mem
    move.l     4.w,a6              ; ExecBase
    move.l     CustomLevelAllocPtr(a5),a1
    move.l     CustomLevelAllocSize(a5),d0
    jsr        -$D2(a6)            ; _LVOFreeMem
.no_custom_mem:

    move.l     SavedOSStack,sp
    movem.l    (sp)+,d2-d7/a2-a6
    moveq      #0,d0               ; CLI return code: OK
    rts

;==============================================================================
; SetRasterLogicColor  -  Transition raster bar from Yellow to Green/Red
;
; Called when upfront VBlank priority blits (player, duck) complete.
; Switches COLOR00 from DEBUG_RASTER_VBLANK ($FF0) to DEBUG_RASTER_COLOR ($0F0),
; or DEBUG_RASTER_OVERRUN ($F00) if an overrun occurred.
; Preserves all registers.
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

;==============================================================================
; Init  -  Engine bootstrap and hardware environment initialisation
;
; Prepares initial game state variables, detects PAL vs NTSC video raster timing,
; detects OCS vs ECS/AGA Denise chipset revisions, initialises PTPlayer audio
; drivers, attaches the CIA-A keyboard interrupt, generates flipped player BOBs
; in Chip RAM, and installs fault trap vectors for robust crash debugging.
;
; Subsequent screen transitions (splash banner -> ZX loading -> title menu ->
; gameplay) are driven dynamically by the GameStatus FSM in gamestatus.asm.
;
; Called from Restart before the VBlank interrupt is enabled.
; On entry:
;   a5 = Variables base pointer
;   a6 = CUSTOM chip base ($dff000)
;==============================================================================

Init:
    move.w     #0,LevelId(a5)
    move.w     #FLASH_SETUP,GameStatus(a5)
    clr.w      SlowMode(a5)
    clr.w      SlowModeHold(a5)
    clr.w      PrevKeyS(a5)
    clr.w      DebugOverlayActive(a5)
    clr.w      PrevDebugDrawn(a5)
    move.w     #DEFAULT_LIVES,PlayerLives(a5)
    lea        Keys,a0
    clr.b      KEY_S(a0)
    clr.b      KEY_A(a0)
    clr.b      KEY_D(a0)
    bsr        DetectNTSC          ; detect PAL/NTSC first; sets IsPAL(a5) for AudioInit
    bsr        DetectOCS           ; detect OCS vs ECS chipset; disables VBlank tracking in OCS mode
    bsr        AudioInit           ; install CIA-B music interrupt; reads IsPAL(a5) for CIA timing
    bsr        KeyboardInit
    bsr        PlayerInitFlippedSprites ; pre-generate left-facing player BOBs in Chip RAM

    ; Install minimal handlers for the four most common 68000 hardware faults
    ; plus TRAP #0.  Converts silent random crashes into a solid red screen at
    ; $dff180 (COLOR00).  The originals were saved by SystemSave and are put
    ; back by SystemRestore on exit.  Handles 68010+ relocated VBR.
    move.l     VBRBase,a1
    lea        FaultTrap,a0
    move.l     a0,$8(a1)           ; bus error          (vector 2)
    move.l     a0,$c(a1)           ; address error      (vector 3)
    move.l     a0,$10(a1)          ; illegal instruction (vector 4)
    move.l     a0,$14(a1)          ; zero divide        (vector 5)
    move.l     a0,$80(a1)          ; TRAP #0            (vector 32)
    rts


;==============================================================================
; FaultTrap  -  Minimal 68000 hardware exception handler
;
; Catches bus error ($8), address error ($C), illegal instruction ($10),
; and zero divide ($14).  Uses the absolute custom-chip address rather than
; a6 (which may be corrupt or stale at exception time) and halts.
;==============================================================================

FaultTrap:
    move.w     #$0f00,$dff180      ; COLOR00 = solid red — visible on any display mode
    bra.s      FaultTrap

;==============================================================================
; DetectNTSC  -  Detect NTSC vs PAL and patch the game copper list if NTSC
;
; Method: wait for the vertical beam to enter the "line >= 256" region (VPOSR
; bit 0 set), then record the highest value reached by VHPOSR bits 15:8 (the
; low 8 bits of the beam counter) before VBlank resets it.
;
;   PAL : max value ~ $38 (line 312 = $138, low byte = $38)
;   NTSC: max value ~ $06 (line 262 = $106, low byte = $06)
;   Threshold $20 (line 288).  Below threshold -> NTSC.
;
; On NTSC: patches cpGameDIW+2 (DIWSTRT value) and cpGameDIW+6 (DIWSTOP value)
; to centre the 216-line game display in the NTSC visible area.
; cpLoading is left untouched — its 200-line display (lines 44-244) already
; fits within the NTSC visible range.
;
; Note: cpVHSDistort scanline WAITs are not adjusted here; VHS distortion
; visual timing will be slightly off on NTSC, but does not affect gameplay.
;
; Called from Init before StartVBlank.  a5/a6 must already be loaded.
; Destroys: d0, d1 (no caller registers to preserve at this point).
;==============================================================================

DetectNTSC:
    ; Step 1: wait until beam < 256 (VPOSR low byte bit 0 = 0)
.dn_wait_low
    btst        #0,VPOSR+1(a6)
    bne         .dn_wait_low

    ; Step 2: wait until beam >= 256 (VPOSR low byte bit 0 = 1)
.dn_wait_high
    btst        #0,VPOSR+1(a6)
    beq         .dn_wait_high

    ; Step 3: spin while beam >= 256, tracking max VHPOSR high byte
    moveq       #0,d1                   ; d1 = running maximum
.dn_spin
    move.w      VHPOSR(a6),d0
    lsr.w       #8,d0                   ; d0.w = beam bits 7..0 (low byte of V counter)
    cmp.w       d1,d0
    blt         .dn_done                ; value dropped (VBlank wrap) -> stop
    move.w      d0,d1                   ; update max
    btst        #0,VPOSR+1(a6)
    bne         .dn_spin                ; continue while bit 8 still set
.dn_done

    ; d1 = max low-byte value while line was >= 256
    ; PAL: ~$38 (line 312). NTSC: ~$06 (line 262). Threshold: $20 (line 288).
    move.w      #WINDOW_Y_START,SpriteYOffset(a5)   ; default: PAL raster origin for HUD / bubble sprites
    move.w      #1,IsPAL(a5)            ; default: PAL
    cmp.w       #$20,d1
    bge         .dn_pal                 ; >= $20 -> line reached 288+, must be PAL

    ; NTSC detected: recentre the 216-line game display (Y start=$1C, stop low=$F4)
    move.w      #NTSC_WINDOW_START,cpGameDIW+2   ; patch DIWSTRT value
    move.w      #NTSC_WINDOW_STOP,cpGameDIW+6    ; patch DIWSTOP value
    move.w      #NTSC_WINDOW_Y_START,SpriteYOffset(a5)  ; patch sprite raster origin for NTSC (HUD / bubble sprites)
    clr.w       IsPAL(a5)               ; NTSC: clear PAL flag

    ; Shift copper background (cpGameSky) 16 scanlines earlier for NTSC:
    ; 216 scanlines starting at line 28 ($1C) through line 243 ($F3).
    ; No line-255 crossing WAIT needed on NTSC (all lines < 255).
    lea         cpGameSky,a0
    move.w      #NTSC_WINDOW_Y_START,d0 ; start line = 28 ($1C)
    move.w      #216-1,d7               ; 216 scanlines
.dn_sky_loop:
    move.w      d0,d1
    lsl.w       #8,d1
    or.w        #$07,d1                 ; d1 = (line << 8) | $07
    move.w      d1,(a0)+                ; write WAIT line
    move.w      #$fffe,(a0)+            ; write WAIT mask
    move.w      #COLOR00,(a0)+          ; write MOVE COLOR00
    clr.w       (a0)+                   ; color placeholder ($0000)
    addq.w      #1,d0                   ; next scanline
    dbra        d7,.dn_sky_loop

    ; Reset background to black at line 244 ($F4 = 28 + 216)
    move.w      d0,d1                   ; d0 = 244 ($F4)
    lsl.w       #8,d1
    or.w        #$07,d1
    move.w      d1,(a0)+                ; WAIT (line 244, $07)
    move.w      #$fffe,(a0)+
    move.w      #COLOR00,(a0)+
    clr.w       (a0)+                   ; black ($0000)

    ; End of copper list marker (padded to match original PAL size so cpVHSDistort is preserved)
    move.l      #COPPER_HALT,(a0)+
    move.l      #COPPER_HALT,(a0)+
    move.l      #COPPER_HALT,(a0)+

.dn_pal:
    rts

;==============================================================================
; DetectOCS  -  Detect OCS vs ECS chipset via DENISEID register
;
; Reads the Denise identification register at $dff07e to determine chipset:
;   OCS Denise:   ID bits (low nybble) = $00-$03
;   ECS Denise:   ID bits (low nybble) = $F, $E, etc.
;   AGA Denise:   Will also be detected as ECS (no special handling needed)
;
; Sets IsOCS(a5) = 1 for OCS, 0 for ECS/AGA.
;
; NOTE: VBlank overrun tracking (SPR6) is disabled in OCS mode due to
; hardware compatibility issue where the VBlank code interferes with sprite
; 6 rendering, causing visual artifacts (teal vertical line).
;
; Called from Init after DetectNTSC.  Destroys: d0.
;==============================================================================

DetectOCS:
    move.w      DENISEID(a6),d0         ; Read DENISEID register
    andi.w      #$000f,d0               ; Mask low nybble (chip revision)

    ; OCS Denise has low nybble of $00-$03
    ; ECS/AGA Denise has different values (typically $F, $E, etc.)
    cmp.w       #DENISE_ECS_MIN,d0      ; Compare against $04 (first non-OCS value)
    bge         .is_ecs_aga             ; >= $04 means ECS or AGA

    ; OCS detected
    move.w      #1,IsOCS(a5)
    rts

.is_ecs_aga
    ; ECS or AGA detected
    clr.w       IsOCS(a5)
    rts
  
;==============================================================================
; StartVBlank  -  Install VBlankTick and enable the vertical-blank interrupt
;
; Writes the address of VBlankTick into the level-3 autovector ($6c) and
; enables the master interrupt gate (INTF_INTEN) plus the vertical-blank
; interrupt (INTF_VERTB).  No other level-3 source (Copper, blitter) is
; enabled — if you add a copper interrupt later, VBlankTick must also
; acknowledge INTF_COPER or the machine will hang in an interrupt storm.
;
; After this call MainLoop consumes one FramePending per video frame.
;==============================================================================

StartVBlank:
    move.w      #BASE_DMA,DMACON(a6)   ; enable Copper + Blitter + Bitplane + Sprite DMA

    move.l      VBRBase,a0
    move.l      #VBlankTick,$6c(a0)
    move.w      #INTF_SETCLR|INTF_INTEN|INTF_VERTB,INTENA(a6)
    nop                                ; flush CPU write pipeline for 68040/060
    nop
    tst.w       DMACONR(a6)            ; force custom chip bus cycle completion
    rts

;==============================================================================
; VBlankTick  -  Level-3 vertical-blank interrupt service routine
;
; Fires once per video frame (~50 Hz PAL / ~60 Hz NTSC) via the level-3
; autovector at $6c.  Deliberately tiny: it only acknowledges the interrupt
; and counts the frame — ALL game logic runs in MainLoop.  Music replay is
; driven separately by PTPlayer's CIA-B interrupt (level 6).
;
; Sequence:
;   1. Save d0, a5, a6 (a5/a6 MUST be saved because TurboClear and other routines
;      may use them as registers; any interrupt modifying them without save/restore
;      corrupts memory clearing loops and leaks pointer values into screen buffers).
;   2. Read INTREQR; exit if this is not a VERTB request (spurious).
;   3. Acknowledge VERTB by writing the bit to INTREQ (twice — some A4000
;      chipset revisions need two writes to clear reliably).
;   4. Increment TickCounter (free-running frame counter for animations).
;   5. If MainLoop has not yet consumed the previous FramePending, count a
;      frame overrun (debug telemetry, turns F3 raster bar red).
;   6. Increment FramePending to release MainLoop for the next frame.
;==============================================================================

VBlankTick:
    movem.l    d0/a5-a6,-(sp)
    lea        CUSTOM,a6
    lea        Variables,a5

    move.w     INTREQR(a6),d0
    and.w      #INTF_VERTB,d0
    beq        .exit

    move.w     d0,INTREQ(a6)
    move.w     d0,INTREQ(a6)                        ; twice to avoid a4k hw bug

    ; NTSC speed normalisation: the game is authored for 50 Hz PAL (all
    ; movement speeds, animation rates and timers are "per logic tick").
    ; NTSC fires 60 VBlanks/s, so we withhold the logic tick on every 6th
    ; VBlank: 60 * 5/6 = 50 ticks/s, identical game speed to PAL.  On the
    ; skipped VBlank the display simply holds the previous frame.
    tst.w      IsPAL(a5)
    bne.s      .tick                                ; PAL: every VBlank is a tick
    addq.w     #1,NtscSkipPhase(a5)
    cmp.w      #6,NtscSkipPhase(a5)
    blt.s      .tick
    clr.w      NtscSkipPhase(a5)
    bra.s      .exit                                ; 6th NTSC VBlank: no logic tick
.tick
    addq.w     #1,TickCounter(a5)

    tst.w      FramePending(a5)    ; previous frame still unconsumed?
    beq        .no_overrun
    addq.w     #1,VBlankOverrunCount(a5)   ; mainline exceeded one frame budget
.no_overrun
    addq.w     #1,FramePending(a5) ; release MainLoop for one frame of logic

.exit
    movem.l    (sp)+,d0/a5-a6
    rte

;==============================================================================
; Subsystem includes
;
; All game subsystems are assembled as a single translation unit by INCLUDEing
; them here.  They share the same section (main,code) and can call each other
; directly without any linking step.
;==============================================================================

; --- System & Hardware Drivers ---
    include    "system/system.asm"
    include    "system/keyboard.asm"
    include    "system/tools.asm"
    include    "system/controls.asm"
    include    "system/zx0_faster.asm"

; --- Graphics & Blitter Routines ---
    include    "graphics/screenutils.asm"
    include    "graphics/spritetools.asm"
    include    "graphics/hud_sprites.asm"
    include    "graphics/char_bltroutines.asm"
    include    "graphics/bigfont.asm"

; --- Core Gameplay & Entities ---
    include    "gameplay/levelutils.asm"
    include    "gameplay/tilemap.asm"
    include    "gameplay/actors.asm"
    include    "gameplay/player.asm"
    include    "gameplay/undo.asm"
    include    "gameplay/vhs_rewind.asm"
    include    "gameplay/gamestatus.asm"
    include    "gameplay/customlevel.asm"

; --- Game Screens & States ---
    include    "screens/loading.asm"
    include    "screens/levelcomplete.asm"
    include    "screens/titlescreen.asm"
    include    "screens/instructions.asm"
    include    "screens/credits.asm"
    include    "screens/gamecomplete.asm"
    include    "screens/gameover.asm"
    include    "screens/flashscreen.asm"

; --- Audio Subsystems ---
    include    "audio/audio.asm"
    include    "ptplayer/ptplayer.asm"

;==============================================================================
; Fast RAM data section  (data_fast)
;
; Read-only tables and asset data that do not need to be in Chip RAM.
; Fast RAM is significantly faster to access than Chip RAM on expanded Amigas,
; so lookup tables, level definitions, and palette data live here.
;
; Contents:
;   Quadratic / Sinus            - pre-computed easing / sine tables (binary)
;   PlayerPal / SpritePal        - hardware sprite / player palette (player.pal)
;   CopperSkyTable               - copper background gradient line tables
;   Level Definitions            - multi-layer TMX definitions (level_01_entities.asm..level_06_entities.asm)
;   LevelTable                   - pointer table pointing to each LevelDef
;   Michroma font                - proportional font data for placards/banners
;==============================================================================

    section    data_fast,data

;------------------------------------------------------------------------------
; Easing / animation tables  (pre-computed, accessed by index each frame)
;
; Quadratic- quadratic ease curve, used for fall animation
; Sinus    - full-period sine table (SINE_ANGLES entries of signed 16-bit words)
;            SinusEnd marks the end so SINE_ANGLES can be derived at assemble time
;------------------------------------------------------------------------------

Quadratic:
    incbin     "assets/data/quadratic.bin"
Sinus:
    incbin     "assets/data/sin.bin"
SinusEnd:

;------------------------------------------------------------------------------
; Palettes (read by the CPU only — Fast RAM is fine)
;   PlayerPal / SpritePal - hardware sprite / player palette (COLOR16-31)
;------------------------------------------------------------------------------
PlayerPal:
SpritePal:
    incbin     "assets/graphics/player/player.pal"

CopperSkyTable:
    incbin     "assets/graphics/copper/copper_sky.bin"
    even

    include    "levels/level_01_entities.asm"
    include    "levels/level_02_entities.asm"
    include    "levels/level_03_entities.asm"
    include    "levels/level_04_entities.asm"
    include    "levels/level_05_entities.asm"
    include    "levels/level_06_entities.asm"

;------------------------------------------------------------------------------
; Master Level Table (Pointers to Level Definitions)
;
; Contains 32-bit pointers to each level's LevelDef structure, terminated by 0.
; LevelInit accesses this table via LevelIndex(a5) * 4 to unpack the level's
; tile layers (Background, Platform, Ladder, Water, Foreground), camera bounds,
; player spawn coordinates, enemy patrol routes, animal friends, and oxygen kits.
; LEVEL_TABLE_COUNT is defined in const.asm.
;------------------------------------------------------------------------------
LevelTable:
    dc.l       Level_01_Def
    dc.l       Level_02_Def
    dc.l       Level_03_Def
    dc.l       Level_04_Def
    dc.l       Level_05_Def
    dc.l       Level_06_Def
    dc.l       0                       ; null terminator

;------------------------------------------------------------------------------
; Michroma proportional "hero text" font (placard/warning screens, e.g. the
; GAME OVER / PURGE flash effects) — CPU-read only (bigfont.asm), so Fast RAM like
; the other fonts above. See assets/font/generate_michroma_font.py for how this
; was rasterised and include/resources/bigfont.asm for the blit routines.
;------------------------------------------------------------------------------
    include    "graphics/michroma_font_data.asm"


;------------------------------------------------------------------------------
; Loading screen assets & tape audio (Fast RAM — CPU read / staged into Chip RAM)
;
; LoadingPal, LoadingRawZ, and tape audio PCM samples (zxsfx.asm) are offloaded
; to Fast RAM.  During boot loading setup, LoadingStageAudio dynamically stages
; the PCM samples into unused space in NonDisplayScreen (+40000) for Paula DMA.
; This saves ~53.7 KB of permanent Chip RAM.
;------------------------------------------------------------------------------
LoadingPal:
    incbin     "assets/graphics/title/template.pal"
    even

LoadingRawZ:
    incbin     "assets/graphics/title/template.zx0"
    even

    include    "audio/zxsfx.asm"

;------------------------------------------------------------------------------
; Intro splash screen assets & fanfare audio (Fast RAM — staged into Chip RAM at boot)
;------------------------------------------------------------------------------
TitleLogoRaw:
    incbin     "assets/graphics/title/AGE_title.raw"
    even

TitleLogoPal:
    incbin     "assets/graphics/title/AGE_title.pal"
    even

SfxIntroFanfare:
    dc.l    0                           ; sfx_ptr dynamically patched by FlashScreenSetup
    dc.w    (SfxIntroFanfare_RawEnd-SfxIntroFanfare_Raw)/2
    dc.w    SFX_DEFAULT_PERIOD
    dc.w    64                          ; full volume intro splash trumpet fanfare
    dc.b    SFX_AUTO_CHANNEL
    dc.b    127                         ; absolute highest priority intro fanfare

SfxIntroFanfare_Raw:
    incbin      "assets/fx/sfx_intro_fanfare.raw"
    even
SfxIntroFanfare_RawEnd:

;------------------------------------------------------------------------------
; Menu screen title banner & victory duckling (Fast RAM — staged into Chip RAM)
;------------------------------------------------------------------------------
TitleDuckRaw:
    incbin     "assets/graphics/title/duck_rescue_title.raw"
    even

TitleDuckPal:
    incbin     "assets/graphics/title/duck_rescue_title.pal"
    even

GCDucklingRaw:
    incbin     "assets/graphics/title/duckling_complete.raw"
    even

;------------------------------------------------------------------------------
; Level-complete player headshots & palettes (Fast RAM — staged into Chip RAM)
;------------------------------------------------------------------------------
HeadshotMiaRaw:
    incbin      "assets/graphics/headshots/headshot_mia_128x64.raw"
    even

HeadshotMiaPal:
    incbin      "assets/graphics/headshots/headshot_mia.pal"
    even

;------------------------------------------------------------------------------
; Title screen music (Fast RAM — staged into NonDisplayScreen+10000 at boot/title)
; Staged dynamically by TitleSetup into NonDisplayScreen in Chip RAM, then
; played via PTPlayer. Stopped by AudioStopMod when entering gameplay.
; Saves 46,414 bytes of permanent Chip RAM!
;------------------------------------------------------------------------------
TitleScreenMusicMod:
    incbin     "assets/music/heatwave_cruise.mod"
    even
TitleScreenMusicModEnd:

;==============================================================================
; Chip RAM data section  (data_chip)
;
; All data that must be in Chip RAM because it is accessed by the DMA hardware
; (Copper, Blitter, Agnus sprite DMA, audio DMA):
;
;   copperlists.asm     - cpGame and cpLoading copper list programs
;   LevelMod            - gameplay music module
;   gamesfx.asm         - in-game sound effect waveforms
;   GameTiles*          - tilemap graphics & mask
;   EnemySprites*       - enemy sprites & masks
;   DizzyStars*         - dizzy star sprites & mask
;   AnimalSprites*      - animal friend sprites & mask
;==============================================================================

    section    data_chip,data_c

    include    "graphics/copperlists.asm"

;------------------------------------------------------------------------------
; Gameplay graphics and music (blitter / Paula DMA â€” must be Chip RAM).
; Placed BEFORE the loading-screen overlay region: all of this is needed for
; the rest of the session once gameplay starts.
;
;   LevelMod     - gameplay music module (AudioPlayLevelMusic, Phase B)
;------------------------------------------------------------------------------
GameCompleteMod:
    incbin     "assets/music/10kdub.mod"
    even

LevelMod:
    incbin     "assets/music/xlr8.mod"
    even

;------------------------------------------------------------------------------
; In-Game Sound Effects (Paula sample DMA — must be Chip RAM).
;------------------------------------------------------------------------------
    include    "audio/gamesfx.asm"
    even

GameTilesRaw:
    incbin     "assets/graphics/tiles/tileset-compact_176x80.raw"
    even

GameTilesMsk:
    incbin     "assets/graphics/tiles/tileset-compact_176x80.msk"
    even

EnemySpritesRaw:
    incbin     "assets/graphics/enemies/enemies_64x48.raw"
    even

EnemySpritesWhiteRaw:
    incbin     "assets/graphics/enemies/enemies_64x48_white.raw"
    even

EnemySpritesMsk:
    incbin     "assets/graphics/enemies/enemies_64x48.msk"
    even


DizzyStarsRaw:
    incbin     "assets/graphics/enemies/dizzy_stars_64x16.raw"
    even

DizzyStarsMsk:
    incbin     "assets/graphics/enemies/dizzy_stars_64x16.msk"
    even

AnimalSpritesRaw:
    incbin     "assets/graphics/animals/animals_64x48.raw"
    even

AnimalSpritesMsk:
    incbin     "assets/graphics/animals/animals_64x48.msk"
    even

;------------------------------------------------------------------------------
; Player Character BOB Master Sheets (Chip RAM — Blitter DMA source)
;
; Mia's right-facing master graphics (24 frames, 16 colours, 4 bitplanes).
; Pre-loaded into Chip RAM so the Blitter can read them directly without
; runtime copying.
; Total: 3 * 9,216 = 27,648 bytes.
;------------------------------------------------------------------------------
PlayerRightRaw:
PlayerMiaRaw:
    incbin     "assets/graphics/player/player_bobs_female_128x144.raw"
    even

PlayerRightMsk:
PlayerMiaMsk:
    incbin     "assets/graphics/player/player_bobs_female_128x144.msk"
    even

PlayerRightWhiteRaw:
PlayerMiaWhiteRaw:
    incbin     "assets/graphics/player/player_bobs_female_128x144_white.raw"
    even



; (The game complete screen uses GCDucklingRaw and TitleDuckPal above;
; see gamecomplete.asm.)



;==============================================================================
; Fast RAM BSS section  (mem_fast)
;
; Uninitialised working memory allocated in Fast RAM (cleared by TurboClear
; before gameplay begins).  Fast RAM gives the CPU faster access than Chip RAM
; for the data it accesses every frame.
;
;   Variables  - the global Variables block (layout defined in variables.asm),
;                permanently addressed via a5 throughout the game.
;   Keys       - 256-byte keyboard state buffer (KeyboardInterrupt writes here).
;                Followed by 200 bytes of padding to safely handle any out-of-
;                range scan-codes without corrupting adjacent data.
;==============================================================================

    section    mem_fast,bss
    even

AllFast:

Variables:
    ds.b       Variables_sizeof
    even

Keys:
    ds.b       256          ; one byte per scan-code (0-255); max written index is 127
                            ; (KeyboardInterrupt masks with AND.W #$7F so no OOB access)

SnapshotBuffer:
    ds.b       Snap_sizeof*UNDO_BUFFER_SIZE
    even

GameStack:
    ds.b       4096         ; the game's own stack (Restart switches to it, so the
                            ; game never depends on the CLI's configured stack size)
GameStackTop:

AllFastEnd:

;==============================================================================
; Chip RAM BSS section  (mem_chip)
;
; Uninitialised working buffers that must be in Chip RAM because they are read
; or written by the Blitter, Copper, or sprite DMA every frame.
;
;   NullSprite      - two zero longwords (terminated empty sprite structure).
;                     All unused sprite channels are pointed here so Agnus
;                     fetches nothing and outputs transparent pixels.
;   DisplayScreen   - the composited game frame.  DrawWalls, DrawPlayersAndActors,
;                     and BlitStar32 all write here; copper bitplane pointers
;                     point here so this is what appears on screen.
;   NonDisplayScreen - a clean copy of the background (walls + ladders + shadows
;                     only, no actors).  ClearActor restores DisplayScreen by
;                     copying from NonDisplayScreen.
;   ScreenMemEnd    - 200-byte guard region after the last screen buffer.
;                     Initialised to -1 as a sentinel; any overrun that writes
;                     here is detectable in a debugger.
;==============================================================================

    section    mem_chip,bss_c
AllChip:

NullSprite:
    ds.l       2                   ; SPRxPOS/SPRxCTL = 0,0 (sprite disabled).
                                   ; MUST reserve real space: a zero-length
                                   ; block would alias DisplayScreen and feed
                                   ; image data to the sprite DMA as control
                                   ; words, producing garbage sprites.

DisplayScreen:
    ds.b       LEVEL_SCREEN_SIZE

NonDisplayScreen:
    ds.b       LEVEL_SCREEN_SIZE


;------------------------------------------------------------------------------
; Left-facing flipped player BOB buffers (generated at boot by PlayerInitFlippedSprites)
;
; To minimise disk footprint and asset duplication, only right-facing player
; BOB frames are stored on disk (player_bobs_female_128x144.raw, .msk, and _white.raw).
; At boot, PlayerInitFlippedSprites performs a horizontal mirror on all 24 frames
; (6 rows of 4 cels, 32px cell storage containing 24px active graphics) into
; these Chip RAM buffers.  The blitter routines index these buffers directly
; when Player_Facing(a4) < 0 (facing left).
; Total per buffer: 6 rows * 1536 bytes/row = 9,216 bytes.
;------------------------------------------------------------------------------
PlayerLeftRaw:
    ds.b       PLAYER_BOB_TOTAL_BYTES ; 9,216 bytes
PlayerLeftMsk:
    ds.b       PLAYER_BOB_TOTAL_BYTES ; 9,216 bytes
PlayerLeftWhiteRaw:
    ds.b       PLAYER_BOB_TOTAL_BYTES ; 9,216 bytes

ScreenMemEnd:
    ds.b       200

AllChipEnd: