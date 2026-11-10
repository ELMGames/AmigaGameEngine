;==============================================================================
; AMIGA GAME ENGINE - STARTER GAME
; main.asm  -  Minimal entry point demonstrating the engine lifecycle
;==============================================================================
;
; The smallest game that boots on AmigaGameEngine and puts something on
; screen: takes over the system, paints a Copper gradient behind the
; display, flashes HELLO / WORLD in the engine's big font (the routines
; Duck Rescue's GAME OVER screen uses), and quits cleanly back to AmigaDOS
; when ESC is pressed. No sprites, no tilemap, no audio playback, no
; gameplay - see docs/MAKING_A_GAME_GUIDE.pdf for what to add next, and
; engine/ENGINE_CONTRACT.md for exactly why each piece below is required.
;
; Global register conventions (held constant after Init):
;   a5 = Variables base pointer  (Fast RAM BSS block)
;   a6 = $dff000  CUSTOM chip base
;==============================================================================

    ; Include directories (resolved from repo root, since build.py chdirs there)
    incdir     "games/starter"
    incdir     "games/starter/include"
    incdir     "games/starter/include/core"
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

    include    "macros.asm"
    include    "variables.asm"


;------------------------------------------------------------------------------
; Screen layout
;
; StarterScreen is the engine's standard screen: 320x216, 5 bitplanes,
; interleaved (each 200-byte row holds one 40-byte line of every plane).
; engine/graphics/bigfont.asm addresses the screen through the LOADING_* and
; CHAR_PLANE* names below; Duck Rescue gets them from engine/screens/
; loading.asm and engine/graphics/char_bltroutines.asm. If you include
; char_bltroutines.asm later, delete the four CHAR_PLANE lines here.
;------------------------------------------------------------------------------
LOADING_WIDTH_BYTE  = SCREEN_WIDTH_BYTE         ; 40 bytes per line of one plane
LOADING_ROW_BYTES   = SCREEN_STRIDE             ; 200 bytes per interleaved row
CHAR_PLANE1         = SCREEN_WIDTH_BYTE         ; offset of plane 1 within a row
CHAR_PLANE2         = SCREEN_WIDTH_BYTE*2
CHAR_PLANE3         = SCREEN_WIDTH_BYTE*3
CHAR_PLANE4         = SCREEN_WIDTH_BYTE*4

HELLO_ROW           = 60                        ; screen line of HELLO's top edge
WORLD_ROW           = 116                       ; screen line of WORLD's top edge

; The Copper's WAIT compares only the low 8 bits of the line number, so a
; gradient that stays above raster line 256 needs no wrap-around WAIT. On
; PAL that is the first 212 lines of the display; the last four keep the
; final colour.
GRADIENT_LINES      = $100-WINDOW_Y_START       ; 212 Copper entries, one per line

;==============================================================================
; Code section
;==============================================================================

;==============================================================================
; Engine Lifecycle Framework (AmigaGameEngine)
; Provides: Main, Restart, MainLoop, QuitToOS, EngineInit, SetRasterLogicColor
;==============================================================================

    include    "engine_main.asm"
    include    "game_hooks.asm"     ; Game*Hook stubs (see engine/ENGINE_CONTRACT.md)

;==============================================================================
; GameInitHook  -  Required engine callback, runs once at boot (EngineInit)
;
; Points the Copper list at the screen, builds the background gradient,
; installs the list, and draws HELLO / WORLD (which also arms the flash).
; DMA is still off here: StartVBlank turns the display on afterwards.
; A real game typically also seeds its own state here (level index, lives,
; initial screen) - see games/duck_rescue/main.asm.
;
; In:       a5 = Variables base, a6 = CUSTOM chip base
; Out:      none
; Destroys: d0-d7, a0-a4
;==============================================================================

GameInitHook:
    clr.w      QuitFlag(a5)

    ; Bitplane pointers: 5 planes, 40 bytes apart within each interleaved row
    lea        StarterCopperPlanes,a0
    move.l     #StarterScreen,d0
    moveq      #SCREEN_WIDTH_BYTE,d1
    moveq      #SCREEN_DEPTH,d7
    bsr        CopperSetPtrs

    bsr        StarterBuildGradient

    move.l     #StarterCopperList,COP1LC(a6)
    move.w     #0,COPJMP1(a6)
    bsr        ClearSprites        ; point all 8 cpSprites entries at NullSprite

    ; HELLO / WORLD, centred, flashing ~0.5 s on / ~0.5 s off (bigfont.asm)
    lea        .str_hello,a0
    move.w     #HELLO_ROW,d1
    lea        .str_world,a3
    move.w     #WORLD_ROW,d3
    lea        StarterScreen,a2
    bsr        MichromaFlashInit2
    rts

.str_hello  dc.b    "HELLO",0
.str_world  dc.b    "WORLD",0
    even

;==============================================================================
; GameStatusRun  -  Required engine callback, runs once per frame (MainLoop)
;
; The engine calls this by bare name every frame - see
; engine/system/engine_main.asm's MainLoop. This starter's entire "game
; logic" is: toggle the flashing text when its timer runs out, and if ESC
; is held, set QuitFlag so MainLoop exits to QuitToOS.
; A real game replaces this with a state dispatcher (see
; engine/gameplay/gamestatus.asm for Duck Rescue's 24-state version) -
; nothing about the engine requires that shape, this one frame of logic
; is equally valid.
;
; In:       a5 = Variables base
; Out:      none
; Destroys: d0-d7, a0-a4 (via MichromaFlashTick)
;==============================================================================

GameStatusRun:
    bsr        MichromaFlashTick   ; draws or erases HELLO / WORLD every 25 frames

    lea        Keys,a0
    tst.b      KEY_ESC(a0)         ; Keys[] is indexed by scan-code; KEY_ESC = $45
    beq.s      .no_quit
    move.w     #1,QuitFlag(a5)
.no_quit:
    rts

;==============================================================================
; StarterBuildGradient  -  Fill StarterGradient with one Copper entry per line
;
; Each entry is a WAIT for the start of a display line followed by a MOVE
; to COLOR00, so the background colour changes on every line with no CPU
; time spent once the frame is running. The colours blend linearly
; between the keys in StarterGradientKeys, one 4-bit channel at a time
; (OCS colours are $0RGB, 4 bits per channel).
;
; The first line is SpriteYOffset(a5), the display's top raster line,
; which DetectNTSC sets for PAL or NTSC before GameInitHook runs.
;
; Destroys: d0-d7/a0-a1
;==============================================================================

StarterBuildGradient:
    lea        StarterGradient,a0
    lea        StarterGradientKeys,a1
    move.w     SpriteYOffset(a5),d5    ; d5 = raster line of the next entry
.segment:
    move.w     (a1)+,d6                ; d6 = this key's line
    move.w     (a1)+,d4                ; d4 = this key's colour
    move.w     (a1),d7                 ; d7 = next key's line (-1 = no more keys)
    bmi.s      .last
    sub.w      d6,d7                   ; d7 = lines in this segment
    moveq      #0,d3                   ; d3 = line within the segment
.line:
    bsr.s      .blend                  ; d0 = colour for line d3 of d7
    bsr.s      .entry
    addq.w     #1,d3
    cmp.w      d7,d3
    blt.s      .line
    bra.s      .segment
.last:
    move.w     d4,d0                   ; the final line takes the last key's colour
    bsr.s      .entry
    rts

; Write one entry for raster line d5 with colour d0, then advance d5
.entry:
    move.w     d5,d1
    lsl.w      #8,d1                   ; WAIT: line in the high byte
    or.w       #$0007,d1               ;       horizontal position 7 (left border)
    move.w     d1,(a0)+
    move.w     #$fffe,(a0)+            ;       compare all line and position bits
    move.w     #COLOR00,(a0)+          ; MOVE: COLOR00 = d0
    move.w     d0,(a0)+
    addq.w     #1,d5
    rts

; d0 = this key's colour (d4) blended towards the next key's (2(a1)),
; d3/d7 of the way: each channel is a + (b - a) * d3 / d7
.blend:
    moveq      #0,d0
    moveq      #8,d2                   ; channel shift: red 8, green 4, blue 0
.channel:
    move.w     d4,d1
    lsr.w      d2,d1
    and.w      #$f,d1                  ; d1 = a (this key's channel)
    move.w     2(a1),d6
    lsr.w      d2,d6
    and.w      #$f,d6                  ; d6 = b (next key's channel)
    sub.w      d1,d6
    muls       d3,d6
    divs       d7,d6                   ; d6.w = (b - a) * d3 / d7
    add.w      d6,d1
    lsl.w      d2,d1
    or.w       d1,d0
    subq.w     #4,d2
    bpl.s      .channel
    rts

;------------------------------------------------------------------------------
; StarterGradientKeys  -  (line, colour) pairs, top to bottom; -1 ends.
; Lines count from the top of the display; the last key must sit on line
; GRADIENT_LINES-1. A night-to-sunset sky: navy, violet, magenta, orange.
;------------------------------------------------------------------------------
StarterGradientKeys:
    dc.w       0,$0003                 ; deep navy
    dc.w       70,$0218                ; violet
    dc.w       130,$0a27               ; magenta
    dc.w       175,$0f63               ; orange
    dc.w       GRADIENT_LINES-1,$0fb4  ; gold (horizon)
    dc.w       -1

;==============================================================================
; Subsystem includes
;
; Only what EngineInit's lifecycle actually calls: SystemSave/SystemRestore/
; StartVBlank/DetectNTSC/DetectOCS/InstallFaultTraps (system.asm),
; KeyboardInit (keyboard.asm), and AudioInit (audio.asm, which calls
; PTPlayer's _mt_install - so ptplayer.asm is required even though this
; starter never plays a sound). Plus what HELLO / WORLD needs:
; CopperSetPtrs (tools.asm), the big-font routines
; (bigfont.asm) and the starter's own copy of their font (hero_font_data.asm,
; made by tools/make_hero_font.py).
;==============================================================================

    include    "system.asm"
    include    "keyboard.asm"
    include    "audio.asm"
    include    "ptplayer.asm"
    include    "tools.asm"
    include    "bigfont.asm"
    include    "hero_font_data.asm"

;==============================================================================
; Chip RAM data section  (data_chip)
;==============================================================================

    section    data_chip,data_c

;------------------------------------------------------------------------------
; StarterCopperList  -  Display setup, bitplanes, sprites, colours, gradient.
;
; cpGameDIW and cpSprites are not just convention - engine/system/system.asm's
; DetectNTSC and ClearSprites patch these two labels by name (DIWSTRT/DIWSTOP
; for PAL/NTSC geometry, all 8 sprite pointer pairs respectively). Any game
; that includes system.asm must provide both, with this exact sub-block
; shape, or linking fails with an unresolved symbol. The starter keeps its
; own names for the blocks and binds the engine's names to them with the two
; equates below. See engine/graphics/copperlists.asm's cpGame for Duck
; Rescue's (much larger) real equivalent.
;------------------------------------------------------------------------------
cpGameDIW           = StarterCopperDIW      ; contract name -> this list's DIW block
cpSprites           = StarterCopperSprites  ; contract name -> this list's sprite block

StarterCopperList:
    dc.w       $01fc,$0000             ; FMODE: OCS-compatible fetch mode (AGA)
    dc.w       $0106,$0c00             ; BPLCON3: AGA colour bank 0 (ignored on OCS)
    dc.w       $010c,$0011             ; BPLCON4: AGA sprite colours = COLOR16-31
StarterCopperDIW:
    dc.w       DIWSTRT,WINDOW_START    ; display window top-left (patched for NTSC)
    dc.w       DIWSTOP,WINDOW_STOP     ; display window bottom-right (patched for NTSC)
    dc.w       DDFSTRT,FETCH_START     ; bitplane fetch for a 320-pixel line
    dc.w       DDFSTOP,FETCH_STOP
    dc.w       BPLCON0,$5200           ; 5 bitplanes, colour on, lo-res
    dc.w       BPLCON1,$0000           ; no horizontal scroll
    dc.w       BPLCON2,$0024           ; sprites in front of the playfield
    dc.w       BPL1MOD,SCREEN_MOD      ; skip the other 4 planes' lines (160)
    dc.w       BPL2MOD,SCREEN_MOD
StarterCopperPlanes:
    dc.w    BPL1PTH,0               ; bitplane 1 high (patched)
    dc.w    BPL1PTL,0               ; bitplane 1 low  (patched)
    dc.w    BPL2PTH,0               ; bitplane 2 high (patched)
    dc.w    BPL2PTL,0               ; bitplane 2 low  (patched)
    dc.w    BPL3PTH,0               ; bitplane 3 high (patched)
    dc.w    BPL3PTL,0               ; bitplane 3 low  (patched)
    dc.w    BPL4PTH,0               ; bitplane 4 high (patched)
    dc.w    BPL4PTL,0               ; bitplane 4 low  (patched)
    dc.w    BPL5PTH,0               ; bitplane 5 high (patched)
    dc.w    BPL5PTL,0               ; bitplane 5 low  (patched)
StarterCopperSprites:
    dc.w    SPR0PTH,0               ; sprite 0 high (-> NullSprite)
    dc.w    SPR0PTL,0               ; sprite 0 low
    dc.w    SPR1PTH,0               ; sprite 1 high (-> NullSprite)
    dc.w    SPR1PTL,0               ; sprite 1 low
    dc.w    SPR2PTH,0               ; sprite 2 high (-> NullSprite)
    dc.w    SPR2PTL,0               ; sprite 2 low
    dc.w    SPR3PTH,0               ; sprite 3 high (-> NullSprite)
    dc.w    SPR3PTL,0               ; sprite 3 low
    dc.w    SPR4PTH,0               ; sprite 4 high (-> NullSprite)
    dc.w    SPR4PTL,0               ; sprite 4 low
    dc.w    SPR5PTH,0               ; sprite 5 high (-> NullSprite)
    dc.w    SPR5PTL,0               ; sprite 5 low
    dc.w    SPR6PTH,0               ; sprite 6 high (-> NullSprite)
    dc.w    SPR6PTL,0               ; sprite 6 low
    dc.w    SPR7PTH,0               ; sprite 7 high (-> NullSprite)
    dc.w    SPR7PTL,0               ; sprite 7 low

    dc.w       COLOR00,$0003           ; top border: the gradient's first colour
    dc.w       COLOR31,$0fff           ; text: big-font glyphs set all 5 planes
StarterGradient:
    dcb.w      GRADIENT_LINES*4,0      ; WAIT + MOVE COLOR00 per line (StarterBuildGradient)
    dc.w       $ffff,$fffe             ; end of copper list (wait forever)

;------------------------------------------------------------------------------
; Sinus  -  engine/include/engine_const.i computes SINE_ANGLES as
; (SinusEnd-Sinus)/2 unconditionally, so every game must provide a Sinus
; table even if (like this starter) it never uses sine-based motion. Duck
; Rescue's is a real precomputed 4,096-byte table (assets/data/sin.bin);
; this is a placeholder sized only to satisfy that equate.
;------------------------------------------------------------------------------
Sinus:
    dc.w       0,0,0,0
SinusEnd:

;==============================================================================
; Fast RAM BSS section  (mem_fast)
;==============================================================================

    section    mem_fast,bss

Variables:
    ds.b       Variables_Sizeof

Keys:
    ds.b       256              ; scan-code buffer; written by keyboard.asm's interrupt

GameStack:
    ds.b       4096
GameStackTop:

;==============================================================================
; Chip RAM BSS section  (mem_chip)
;==============================================================================

    section    mem_chip,bss_c

FaultScreen:                    ; the fault screen may overwrite this buffer
StarterScreen:
    ds.b       SCREEN_SIZE      ; 320x216, 5 interleaved planes (zero-filled: all colour 0)

NullSprite:
    ds.l       2                ; unused hardware sprite channels point here (zero-filled BSS)