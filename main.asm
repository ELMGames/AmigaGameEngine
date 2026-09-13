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
    bsr        SystemSave          ; blank OS display, Forbid, snapshot vectors/enables


;==============================================================================
; Restart  -  Hardware initialisation and main loop
;
; Resets the Amiga custom chip environment to a known blank state, switches to
; the game's own stack, calls Init to set up game data structures, installs
; the VBlank interrupt, then runs the game from MainLoop.
;
; Frame model: VBlankTick (the level-3 ISR) only counts frames â€” ALL game
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

    ; Raster profiler: DebugMode=2 (F5 then F3) marks CPU time with a colour
    ; bar â€” red normally, yellow once any frame has overrun its VBlank budget.
    cmp.w      #2,DebugMode(a5)
    bne.s      .no_bar_start
    move.w     #DEBUG_RASTER_COLOR,d0
    tst.w      VBlankOverrunCount(a5)
    beq.s      .bar_normal
    move.w     #$ff0,d0
.bar_normal
    move.w     d0,COLOR00(a6)
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
    move.l     SavedOSStack,sp
    movem.l    (sp)+,d2-d7/a2-a6
    moveq      #0,d0               ; CLI return code: OK
    rts

;==============================================================================
; Init  -  Minimal game initialisation
;
; Initialises the game-state variable and installs the keyboard handler.
; Additional copper / sprite / level setup is currently commented out; those
; operations are now driven by the GameStatus state machine (LoadingSetup ->
; GameInit path) rather than being done unconditionally at startup.
;
; Called from Restart before the VBlank interrupt is enabled.
; a5 and a6 must already be loaded.
;==============================================================================

Init:
    move.w     #GAME_INIT,GameStatus(a5)
    clr.w      SlowMode(a5)
    clr.w      SlowModeHold(a5)
    clr.w      PrevKeyS(a5)
    clr.w      DebugOverlayActive(a5)
    lea        Keys,a0
    clr.b      KEY_S(a0)
    clr.b      KEY_A(a0)
    clr.b      KEY_D(a0)
    bsr        DetectNTSC          ; detect PAL/NTSC first; sets IsPAL(a5) for AudioInit
    bsr        DetectOCS           ; detect OCS vs ECS chipset; disables VBlank tracking in OCS mode
    bsr        AudioInit           ; install CIA-B music interrupt; reads IsPAL(a5) for CIA timing
    bsr        KeyboardInit

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
    move.w     #$0f00,$dff180      ; COLOR00 = solid red â€” visible on any display mode
    bra.s      FaultTrap

;==============================================================================
; DetectNTSC  -  Detect NTSC vs PAL and patch the game copper list if NTSC
;
; Method: wait for the vertical beam to enter the "line >= 256" region (VPOSR
; bit 0 set), then record the highest value reached by VHPOSR bits 15:8 (the
; low 8 bits of the beam counter) before VBlank resets it.
;
;   PAL : max value â‰ˆ $38 (line 312 = $138, low byte = $38)
;   NTSC: max value â‰ˆ $06 (line 262 = $106, low byte = $06)
;   Threshold $20 (line 288).  Below threshold â†’ NTSC.
;
; On NTSC: patches cpGameDIW+2 (DIWSTRT value) and cpGameDIW+6 (DIWSTOP value)
; to centre the 216-line game display in the NTSC visible area.
; cpLoading is left untouched â€” its 200-line display (lines 44-244) already
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
    blt         .dn_done                ; value dropped (VBlank wrap) â†’ stop
    move.w      d0,d1                   ; update max
    btst        #0,VPOSR+1(a6)
    bne         .dn_spin                ; continue while bit 8 still set
.dn_done

    ; d1 = max low-byte value while line was >= 256
    ; PAL: ~$38 (line 312). NTSC: ~$06 (line 262). Threshold: $20 (line 288).
    move.w      #WINDOW_Y_START,SpriteYOffset(a5)   ; default: PAL raster origin for SpriteCoord
    move.w      #1,IsPAL(a5)            ; default: PAL
    cmp.w       #$20,d1
    bge         .dn_pal                 ; >= $20 â†’ line reached 288+, must be PAL

    ; NTSC detected: recentre the 216-line game display (Y start=$1C, stop low=$F4)
    move.w      #NTSC_WINDOW_START,cpGameDIW+2   ; patch DIWSTRT value
    move.w      #NTSC_WINDOW_STOP,cpGameDIW+6    ; patch DIWSTOP value
    move.w      #NTSC_WINDOW_Y_START,SpriteYOffset(a5)  ; patch sprite raster origin for NTSC
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
; enabled â€” if you add a copper interrupt later, VBlankTick must also
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
; and counts the frame â€” ALL game logic runs in MainLoop.  Music replay is
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
;      frame overrun (debug telemetry, shown as a yellow raster bar).
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

    include    "system.asm"
    include    "keyboard.asm"
    include    "tools.asm"
    include    "levelutils.asm"
    include    "screenutils.asm"
    include    "tilemap.asm"
    include    "actors.asm"
    include    "zx0_faster.asm"
    include    "spritetools.asm"
    include    "player.asm"
    include    "undo.asm"
    include    "vhs_rewind.asm"
    include    "controls.asm"
    include    "loading.asm"
    include    "levelcomplete.asm"
    include    "char_bltroutines.asm"
    include    "bigfont.asm"
    include    "titlescreen.asm"
    include    "instructions.asm"
    include    "gamecomplete.asm"
    include    "gamestatus.asm"
    include    "audio.asm"
    include    "ptplayer/ptplayer.asm"

;==============================================================================
; Fast RAM data section  (data_fast)
;
; Read-only tables and compressed asset pointers that do not need to be in
; Chip RAM.  Fast RAM is significantly faster to access than Chip RAM on
; expanded Amigas, so lookup tables, level data, and palette data live here.
;
; Contents:
;   Quartic / Quadratic / Sinus  - pre-computed easing / sine tables (binary)
;   assets.asm                   - tile asset tables and ZX0-compressed tile data
;   SpritePal                    - hardware sprite palette (sprites.pal)
;   TilesPal0..4                 - per-chapter tile palettes (tiles_N.pal)
;   LevelData                    - all 100 levels packed as raw 88-byte maps
;   WallpaperBaseTop/Base        - default wallpaper border tile templates
;   LevelCountRaw                - level counter UI source graphic (ui_4.bin)
;==============================================================================

    section    data_fast,data

;------------------------------------------------------------------------------
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
;   SpritePal   - hardware sprite palette (COLOR16-31)
;------------------------------------------------------------------------------
SpritePal:
    incbin     "assets/graphics/sprites/sprites.pal"

CopperSkyTable:
    incbin     "assets/graphics/copper/copper_sky.bin"
    even

    include    "level_01_entities.asm"

;------------------------------------------------------------------------------
; Master Level Table (Pointers to Level Definitions)
LEVEL_TABLE_COUNT = 1

LevelTable:
    dc.l       Level_01_Def
    dc.l       0                       ; null terminator

;------------------------------------------------------------------------------
; Level counter UI source graphic and digit font.
; REMOVED: UI buttons removed from template. Files moved to TEMP/assets/.
; CUSTOMISE: To restore, move ui_4.bin and levelfont.bin back from TEMP/
; and replace these stubs with the original incbin lines.
;------------------------------------------------------------------------------
LevelCountRaw:
    dc.b    0   ; stub - ui_4.bin moved to TEMP/assets/graphics/ui/
    even
LevelFont:
    dc.b    0   ; stub - levelfont.bin moved to TEMP/assets/font/
    even

;------------------------------------------------------------------------------
; Michroma proportional "hero text" font (placard/warning screens, e.g. the
; PURGE flash effect) â€” CPU-read only (bigfont.asm), so Fast RAM like the
; other fonts above. See assets/font/generate_michroma_font.py for how this
; was rasterised and include/resources/bigfont.asm for the blit routines.
;------------------------------------------------------------------------------
    include    "michroma_font_data.asm"

;------------------------------------------------------------------------------
; ZX0-compressed player hardware sprites; decompressed into the PlayerHWSprites
; chip buffer by CopyOverlayAssets (loading.asm) after the loading screen.
;------------------------------------------------------------------------------
PlayerHWSprites_FastMem:
    incbin     "assets/graphics/sprites/player_hwsprites.zx0"
    even

;==============================================================================
; Post-loading overlay source data  (Fast RAM: ZX0-compressed; not chip-DMA)
;==============================================================================
    section    data_overlay_src,data

;==============================================================================
; Chip RAM data section  (data_chip)
;
; All data that must be in Chip RAM because it is accessed by the DMA hardware
; (Copper, Blitter, Agnus sprite DMA, audio DMA):
;
;   copperlists.asm  - cpTest and cpLoading copper list programs
;   LoadingRaw         - raw interleaved bitplane data for the loading screen logo
;   LoadingPal         - loading screen palette (with extra star colour entries)
;==============================================================================

    section    data_chip,data_c

    include    "copperlists.asm"

;------------------------------------------------------------------------------
; Title screen logo (blitter source â€” must be Chip RAM).
; Placed BEFORE the loading-screen overlay region so it survives after loading.
;
; TitleLogoRaw: 288x64, 3 bitplanes stored plane-by-plane (36 bytes/row,
;               2304 bytes/plane, 6912 bytes total).
; TitleLogoPal: 8 big-endian $0RGB colour words; colour 0 = transparent.
; Both generated by tools/convert_assets.py from AGE_title.png.
;------------------------------------------------------------------------------
TitleLogoRaw:
    incbin     "assets/graphics/title/AGE_title.raw"
TitleLogoPal:
    incbin     "assets/graphics/title/AGE_title.pal"

;------------------------------------------------------------------------------
; Title screen music (Paula sample DMA â€” must be Chip RAM).
; Also placed BEFORE the overlay region so it remains available every time
; the title screen is revisited.  Started by AudioPlayTitleMusic from
; TitleSetup; PTPlayer loops the module endlessly until AudioStopMod is
; called when leaving the title screen.
;------------------------------------------------------------------------------
TitleScreenMusicMod:
    incbin     "assets/music/supremacy_title.mod"
    even

;------------------------------------------------------------------------------
; Gameplay graphics and music (blitter / Paula DMA â€” must be Chip RAM).
; Placed BEFORE the loading-screen overlay region: all of this is needed for
; the rest of the session once gameplay starts.
;
;   LevelMod     - gameplay music module (AudioPlayLevelMusic, Phase B)
;------------------------------------------------------------------------------
LevelMod:
    incbin     "assets/music/10kdub.mod"
    even

GameTilesRaw:
    incbin     "assets/graphics/tiles/FourSeasons.tiles_176x256.raw"
    even

GameTilesMsk:
    incbin     "assets/graphics/tiles/FourSeasons.tiles_176x256.msk"
    even

EnemySpritesRaw:
    incbin     "assets/graphics/enemies/enemies_64x128.raw"
    even

EnemySpritesMsk:
    incbin     "assets/graphics/enemies/enemies_64x128.msk"
    even

PlayerRaw:
    incbin     "assets/graphics/sprites/player_bobs_64x576.raw"
    even

PlayerMsk:
    incbin     "assets/graphics/sprites/player_bobs_64x576.msk"
    even

; (The game complete screen reuses TitleLogoRaw/TitleLogoPal above â€” no
; dedicated logo assets; see GC_LOGO_OFF in gamecomplete.asm.)

;------------------------------------------------------------------------------
; Loading screen overlay region  (chip RAM that MAY be reused after loading)
;
; LoadingPal, LoadingRawZ, and the ZX tape-load audio (zxsfx.asm) are only
; needed while the loading screen is on display.  Once LoadingRun transitions
; to TITLE_SETUP this region can be overwritten with in-game assets (see
; CopyOverlayAssets in loading.asm for the hook â€” a stub in the template).
;
; Ordering guarantee: everything needed AFTER the loading screen
; (TitleLogoRaw/Pal, TitleScreenMusicMod) is placed BEFORE this region, so
; the title screen keeps working no matter what the overlay is reused for.
;------------------------------------------------------------------------------
LoadingPal:
    incbin     "assets/graphics/title/template.pal"

LoadingRawZ:
    incbin     "assets/graphics/title/template.zx0"
   even                        ; ZX0 size may be odd

    include "zxsfx.asm"

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

AllFast:

Variables:
    ds.b       Variables_sizeof

Keys:
    ds.b       256          ; one byte per scan-code (0-255); max written index is 127
                            ; (KeyboardInterrupt masks with AND.W #$7F so no OOB access)

SnapshotBuffer:
    ds.b       Snap_sizeof*UNDO_BUFFER_SIZE

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

TileSet:
    ds.b       TILE_SIZE           ; minimal tile scratch buffer (480 bytes)
TileMask:
    ds.b       TILE_SIZE           ; minimal tile mask scratch buffer (480 bytes)
PlayerHWSprites:
;   ds.b       PLAYERHWSPRITES_SIZE ; Deprecated - player converted to BOB in data_chip

ScreenMemEnd:
    ds.b       200

AllChipEnd: