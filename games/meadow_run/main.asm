;==============================================================================
; AMIGA GAME ENGINE - MEADOW RUN
; main.asm  -  Entry point, frame loop, Copper list and memory sections
;==============================================================================
;
; A horizontally scrolling platformer. Mia runs right across a meadow 128
; tiles wide, jumping pits and crates, to the signpost at the far end before
; the countdown runs out, picking up as many of Duck Rescue's ducklings on
; the way as she can. Reaching the signpost with more ducklings than ever
; before sets a new best, and the counter flashes. Fall in the water and
; she starts again from the left, with the clock still running; run out of
; time and the level starts over.
;
; At boot it shows the Amiga Game Engine splash with its fanfare
; (splash.asm), as Duck Rescue does, before the level is drawn.
;
; Laid out like Duck Rescue:
;   assets/          tiles, Mia's sheet, sounds, the Tiled level
;   include/core     const.asm, struct.asm, variables.asm
;   include/gameplay player.asm, level.asm
;   include/graphics hud_sprites.asm, hud_sprite_data.asm (generated)
;   include/levels   level_01_entities.asm (generated from Level_01.tmx)
;   tools/           convert_tiles.py, export_level.py, check_level.py
;
; On top of games/starter/ it uses three engine modules:
;   engine/graphics/hscroll.asm     sideways scrolling, three tile layers, BOBs
;   engine/graphics/bob_mirror.asm  left-facing frames built at boot
;   engine/system/controls.asm      joystick and keyboard
; Chapter 36 walks through it.
;
; Controls: left/right to run, up, fire or Space to jump, ESC to quit.
;
; Global register conventions (held constant after Restart):
;   a5 = Variables base pointer  (Fast RAM BSS block)
;   a6 = $dff000  CUSTOM chip base
;==============================================================================

    incdir     "games/meadow_run"
    incdir     "games/meadow_run/include"
    incdir     "games/meadow_run/include/core"
    incdir     "games/meadow_run/include/gameplay"
    incdir     "games/meadow_run/include/graphics"
    incdir     "games/meadow_run/include/levels"
    incdir     "engine"
    incdir     "engine/include"
    incdir     "engine/core"
    incdir     "engine/audio"
    incdir     "engine/gameplay"
    incdir     "engine/graphics"
    incdir     "engine/screens"
    incdir     "engine/system"
    incdir     "engine/effects"
    incdir     "engine/audio/ptplayer"

    include    "amiga_hw.i"
    include    "const.asm"             ; first: hscroll_variables.i needs the map size
    include    "macros.asm"
    include    "struct.asm"
    include    "variables.asm"

;==============================================================================
; Code section
;==============================================================================

    include    "engine_main.asm"
    include    "game_hooks.asm"     ; Game*Hook stubs (none are called here)

;==============================================================================
; GameInitHook  -  Required engine callback, runs once at boot (EngineInit)
;
; DMA is still off here, so nothing is drawn yet: the level is drawn on the
; first frame, by GameStatusRun.
;
; In:       a5 = Variables base, a6 = CUSTOM chip base
; Destroys: d0-d7, a0-a4
;==============================================================================

GameInitHook:
    clr.w      QuitFlag(a5)
    clr.w      LevelReady(a5)

    ; Colours 1-15 from the tile sheet's palette (colour 0 is the sky)
    lea        TilePalette+2,a0
    lea        GameCopperPal+4+2,a1    ; COLOR01's data word
    moveq      #15-1,d7
.pal:
    move.w     (a0)+,(a1)
    addq.l     #4,a1
    dbra       d7,.pal

    bsr        PlayerInitFlippedSprites ; left-facing frames, by the CPU

    move.l     #GameCopper,COP1LC(a6)
    move.w     #0,COPJMP1(a6)
    bsr        ClearSprites            ; all 8 sprite pointers -> NullSprite
    bsr        HudInit                 ; then SPR0, SPR2, SPR3 -> the HUD
    bra        SplashInit              ; boot splash first: shows SplashCopper

;==============================================================================
; GameStatusRun  -  Required engine callback, runs once per frame (MainLoop)
;
; The splash runs first, until SplashTimer reaches 0. After that the
; order matters. The camera is set first, before the Copper reaches
; the bitplane pointers at line 27, so the new view is shown this frame.
; Then the ducklings animate and the HUD changes, and last frame's BOB is erased and
; this frame's drawn; Mia is in the lower half of the screen, well below the
; beam by then.
;==============================================================================

GameStatusRun:
    lea        Keys,a0
    tst.b      KEY_ESC(a0)
    beq.s      .no_quit
    move.w     #1,QuitFlag(a5)         ; MainLoop falls through to QuitToOS
    rts
.no_quit:
    tst.w      SplashTimer(a5)         ; boot splash still showing?
    bne        SplashRun
    tst.w      LevelReady(a5)
    bne.s      .ready
    bra        LevelStart              ; first frame: draw the level

.ready:
    bsr        UpdateControls

    tst.w      GoalTimer(a5)           ; at the signpost: wait, then play again
    beq.s      .no_goal
    bsr        GoalFlash               ; a new best: the counter flashes
    subq.w     #1,GoalTimer(a5)
    bne.s      .hold
    bra        LevelStart
.no_goal:
    tst.w      PlrDeadTimer(a5)        ; fell in, or out of time: wait, then...
    beq.s      .alive
    subq.w     #1,PlrDeadTimer(a5)
    bne.s      .hold
    tst.w      TimeUp(a5)
    bne        LevelStart              ; ...out of time: the level again
    bra        PlayerRespawn           ; ...fell in: back to the start
.alive:
    bsr        PlayerLogic
    bsr        CameraFollow            ; patches the Copper list before line 27
    bsr        LevelTick               ; countdown, duckling animation
    bsr        HudUpdate
    bsr        PlayerErase             ; last frame's BOB
    bsr        PlayerDraw              ; this frame's, foreground on top
.hold:
    rts

;==============================================================================
; Game code
;==============================================================================

    include    "player.asm"
    include    "level.asm"
    include    "hud_sprites.asm"
    include    "splash.asm"

;==============================================================================
; Engine subsystems
;==============================================================================

    include    "system.asm"
    include    "keyboard.asm"
    include    "controls.asm"
    include    "audio.asm"
    include    "ptplayer.asm"
    include    "tools.asm"
    include    "bob_mirror.asm"
    include    "hscroll.asm"

;==============================================================================
; Fast RAM data (data_fast): the level, sound effect records, the palette
;==============================================================================

    section    data_fast,data

    include    "level_01_entities.asm"  ; Level_01_Def and its maps

TilePalette:
    incbin     "games/meadow_run/assets/graphics/tiles/meadow_tiles.pal"

; The boot splash (splash.asm): Duck Rescue's Amiga Game Engine logo. The
; CPU copies it into the screen, so it can stay in Fast RAM.
SplashLogo:
    incbin     "games/meadow_run/assets/graphics/title/AGE_title.raw"
SplashPalette:
    incbin     "games/meadow_run/assets/graphics/title/AGE_title.pal"

SfxFanfare:                            ; the splash fanfare, as Duck Rescue
    dc.l       SfxFanfare_Raw
    dc.w       (SfxFanfare_RawEnd-SfxFanfare_Raw)/2
    dc.w       SFX_DEFAULT_PERIOD
    dc.w       64
    dc.b       SFX_AUTO_CHANNEL
    dc.b       127                     ; nothing interrupts it

SfxJump:
    dc.l       SfxJump_Raw
    dc.w       (SfxJump_RawEnd-SfxJump_Raw)/2
    dc.w       SFX_DEFAULT_PERIOD
    dc.w       48
    dc.b       SFX_AUTO_CHANNEL
    dc.b       SFX_PRI_NORMAL
SfxDuck:                               ; Duck Rescue's rescue chime
    dc.l       SfxDuck_Raw
    dc.w       (SfxDuck_RawEnd-SfxDuck_Raw)/2
    dc.w       SFX_DEFAULT_PERIOD
    dc.w       64
    dc.b       SFX_AUTO_CHANNEL
    dc.b       SFX_PRI_CHIME
SfxDie:
    dc.l       SfxDie_Raw
    dc.w       (SfxDie_RawEnd-SfxDie_Raw)/2
    dc.w       SFX_DEFAULT_PERIOD
    dc.w       64
    dc.b       SFX_AUTO_CHANNEL
    dc.b       SFX_PRI_CRITICAL
SfxGoal:
    dc.l       SfxGoal_Raw
    dc.w       (SfxGoal_RawEnd-SfxGoal_Raw)/2
    dc.w       SFX_DEFAULT_PERIOD
    dc.w       64
    dc.b       SFX_AUTO_CHANNEL
    dc.b       SFX_PRI_FANFARE

;------------------------------------------------------------------------------
; Sinus  -  engine_const.i derives SINE_ANGLES from this table, so every
; game must define it (ENGINE_CONTRACT.md); this game does not use it.
;------------------------------------------------------------------------------
Sinus:
    dc.w       0,0,0,0
SinusEnd:

;==============================================================================
; Chip RAM data: the Copper list and the HUD's duckling sprite
;==============================================================================

    section    data_chip,data_c

; The two Copper blocks the engine patches by name (DetectNTSC, ClearSprites)
cpGameDIW           = GameCopperDIW
cpSprites           = GameCopperSprites

SKY_BANDS           = 27                ; one colour every 8 lines, lines 44-252

GameCopper:
    dc.w       $01fc,$0000             ; FMODE: OCS fetch (AGA)
    dc.w       $0106,$0c00             ; BPLCON3: AGA colour bank 0
    dc.w       $010c,$0011             ; BPLCON4: AGA sprite colours = COLOR16-31
GameCopperDIW:
    dc.w       DIWSTRT,WINDOW_START    ; 320 x 216 window (patched for NTSC)
    dc.w       DIWSTOP,WINDOW_STOP
    dc.w       DDFSTRT,HS_FETCH_START  ; $30: one extra word for BPLCON1
    dc.w       DDFSTOP,FETCH_STOP      ; $d0
    dc.w       BPLCON0,$4200           ; 4 bitplanes, colour on
    dc.w       BPLCON2,$0024           ; sprites in front
    dc.w       BPL1MOD,HS_MODULO       ; 184 - 42 = 142
    dc.w       BPL2MOD,HS_MODULO
GameCopperSprites:
    dc.w       SPR0PTH,0,SPR0PTL,0
    dc.w       SPR1PTH,0,SPR1PTL,0
    dc.w       SPR2PTH,0,SPR2PTL,0
    dc.w       SPR3PTH,0,SPR3PTL,0
    dc.w       SPR4PTH,0,SPR4PTL,0
    dc.w       SPR5PTH,0,SPR5PTL,0
    dc.w       SPR6PTH,0,SPR6PTL,0
    dc.w       SPR7PTH,0,SPR7PTL,0
GameCopperPal:
    dc.w       COLOR00,$026,COLOR01,0,COLOR02,0,COLOR03,0
    dc.w       COLOR04,0,COLOR05,0,COLOR06,0,COLOR07,0
    dc.w       COLOR08,0,COLOR09,0,COLOR10,0,COLOR11,0
    dc.w       COLOR12,0,COLOR13,0,COLOR14,0,COLOR15,0
GameCopperTimerColour:
    dc.w       COLOR17,TIMER_COLOUR    ; SPR0: the countdown (patched by LevelTick)
GameCopperDuckColour:
    dc.w       COLOR21,DUCK_COLOUR     ; SPR2/3: gold (flashes: GoalFlash)
    dc.w       COLOR22,$f91            ;         orange
    dc.w       COLOR23,$332            ;         outline

    ; Line 27, above the window on PAL (line 44) and NTSC (line 28): the
    ; scroll registers are set here, after GameStatusRun has patched them
    dc.w       $1b07,$fffe
HsCopperScroll:
    dc.w       BPLCON1,0               ; fine scroll (HsSetCamera)
HsCopperPlanes:
    dc.w       BPL1PTH,0,BPL1PTL,0     ; coarse scroll (HsSetCamera)
    dc.w       BPL2PTH,0,BPL2PTL,0
    dc.w       BPL3PTH,0,BPL3PTL,0
    dc.w       BPL4PTH,0,BPL4PTL,0

    ; Sky: deep blue at the top to pale blue at the horizon
SKY_I   set    0
    rept       SKY_BANDS
    dc.w       ((WINDOW_Y_START+SKY_I*8)<<8)|$07,$fffe
    dc.w       COLOR00,((SKY_I*9/26)<<8)|((2+SKY_I*10/26)<<4)|(6+SKY_I*9/26)
SKY_I   set    SKY_I+1
    endr
    dc.w       $ffdf,$fffe             ; past line 255 (Section 9.2)
    dc.w       $0407,$fffe             ; line 260: below the PAL window
    dc.w       COLOR00,$000            ; black bottom border
    dc.w       $ffff,$fffe             ; end of list

    include    "hud_sprite_data.asm"   ; HudDigits, HudDuckSprite (generated)

; The boot splash: 3 planes of HsDisplayBuf, colours from AGE_title.pal
SplashCopper:
    dc.w       $01fc,$0000             ; FMODE: OCS fetch (AGA)
    dc.w       $0106,$0c00             ; BPLCON3: AGA colour bank 0
    dc.w       DIWSTRT,WINDOW_START
    dc.w       DIWSTOP,WINDOW_STOP
    dc.w       DDFSTRT,FETCH_START     ; $38: no fine scroll here
    dc.w       DDFSTOP,FETCH_STOP
    dc.w       BPLCON0,$3200           ; 3 bitplanes, colour on
    dc.w       BPLCON1,0
    dc.w       BPLCON2,$0024
    dc.w       BPL1MOD,SPLASH_MOD      ; 120 - 40 = 80
    dc.w       BPL2MOD,SPLASH_MOD
SplashCopperPlanes:
    dc.w       BPL1PTH,0,BPL1PTL,0     ; patched by SplashInit
    dc.w       BPL2PTH,0,BPL2PTL,0
    dc.w       BPL3PTH,0,BPL3PTL,0
SplashCopperSprites:
    dc.w       SPR0PTH,0,SPR0PTL,0     ; all -> NullSprite (SplashInit)
    dc.w       SPR1PTH,0,SPR1PTL,0
    dc.w       SPR2PTH,0,SPR2PTL,0
    dc.w       SPR3PTH,0,SPR3PTL,0
    dc.w       SPR4PTH,0,SPR4PTL,0
    dc.w       SPR5PTH,0,SPR5PTL,0
    dc.w       SPR6PTH,0,SPR6PTL,0
    dc.w       SPR7PTH,0,SPR7PTL,0
SplashCopperPal:
    dc.w       COLOR00,$000,COLOR01,0,COLOR02,0,COLOR03,0
    dc.w       COLOR04,0,COLOR05,0,COLOR06,0,COLOR07,0
    dc.w       $ffff,$fffe             ; end of list
    dc.w       $ffff                   ; non-zero end word (Section 32.6)

;==============================================================================
; Chip RAM data: graphics and samples
;==============================================================================

    section    chip_gfx,data_c

HsTileSheet:
    incbin     "games/meadow_run/assets/graphics/tiles/meadow_tiles_176x96.raw"
HsTileMask:
    incbin     "games/meadow_run/assets/graphics/tiles/meadow_tiles_176x96.msk"
PlayerRightRaw:
    incbin     "games/meadow_run/assets/graphics/player/player_bobs_female_128x144.raw"
PlayerRightMsk:
    incbin     "games/meadow_run/assets/graphics/player/player_bobs_female_128x144.msk"
PlayerRightWhiteRaw = PlayerRightRaw    ; bob_mirror.asm mirrors this too: no white set here

SfxJump_Raw:
    incbin     "games/meadow_run/assets/fx/sfx_jump.raw"
SfxJump_RawEnd:
    even
SfxDuck_Raw:
    incbin     "games/meadow_run/assets/fx/sfx_duck_rescue.raw"
SfxDuck_RawEnd:
    even
SfxDie_Raw:
    incbin     "games/meadow_run/assets/fx/sfx_player_die.raw"
SfxDie_RawEnd:
    even
SfxGoal_Raw:
    incbin     "games/meadow_run/assets/fx/sfx_level_complete.raw"
SfxGoal_RawEnd:
    even
SfxFanfare_Raw:
    incbin     "games/meadow_run/assets/fx/sfx_intro_fanfare.raw"
SfxFanfare_RawEnd:
    even
    dc.w       $ffff                   ; non-zero end word (Section 32.6)

;==============================================================================
; Fast RAM BSS
;==============================================================================

    section    mem_fast,bss

Variables:
    ds.b       Variables_Sizeof
Keys:
    ds.b       256                     ; scan-code table (keyboard.asm)
GameStack:
    ds.b       4096
GameStackTop:

;==============================================================================
; Chip RAM BSS: the two screen buffers, one section each (Section 32.6)
;==============================================================================

    section    chip_display,bss_c

FaultScreen:                           ; the fault screen may overwrite it
HsDisplayBuf:
    ds.b       HS_BUF_SIZE

    section    chip_backdrop,bss_c

HsCleanBuf:
    ds.b       HS_BUF_SIZE

    section    mem_chip,bss_c

PlayerLeftRaw:
    ds.b       MIA_FRAME_ROW*6
PlayerLeftMsk:
    ds.b       MIA_FRAME_ROW*6
PlayerLeftWhiteRaw = PlayerLeftRaw
HudTimerSprite:
    ds.w       2+HUD_DIGIT_LINES*2+2   ; control words, 8 lines, end words
HudCountSprite:
    ds.w       2+HUD_DIGIT_LINES*2+2
NullSprite:
    ds.l       2                       ; an empty sprite: POS/CTL = 0
