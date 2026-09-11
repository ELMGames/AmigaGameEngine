
;==============================================================================
; AMIGA GAME ENGINE
; copperlists.asm  -  Copper List Data
;==============================================================================
;
; The Copper (co-processor) is a programmable list processor built into the
; Agnus chip.  It runs in sync with the video beam, executing a sequence of
; instructions from a list in Chip RAM.  The CPU programs the Copper by writing
; the list address to COP1LC and strobing COPJMP1.
;
; Copper instruction format (two words):
;   MOVE instruction:  { register_address, data_value }
;     - register_address bit 0 = 0 identifies it as a MOVE
;     - Writes data_value to the named custom chip register
;
;   WAIT instruction:  { vp<<8 | hp, ve<<8 | he | $0001 }
;     - bit 0 = 1 identifies it as WAIT (or SKIP)
;     - Copper stalls until the beam reaches or passes (vp, hp)
;
;   COPPER_HALT (dc.l $fffffffe) - special WAIT that is never satisfied,
;     stopping the Copper at the end of the list.
;
; This file defines two copper lists:
;   cpTest  - game screen (5-plane, 32-colour, full screen)
;   cpLoading - loading screen (5-plane, 32-colour, wider format for star effect)
;
; Both lists are in the data_chip section (Chip RAM) because the Copper
; can only DMA-fetch from Chip RAM.
;
; Labelled sub-sections allow GameCopperInit / LoadingCopperSetup to patch in
; the correct bitplane pointers and palette values at runtime:
;   cpPlanes / cpLoadingPlanes    - bitplane pointer MOVE pairs (BPL1PTH/L etc.)
;   cpSprites / cpLoadingSprites  - sprite pointer MOVE pairs   (SPR0PTH/L etc.)
;   cpPal / cpLoadingPal          - palette MOVE pairs          (COLOR00..COLOR31)
;
;==============================================================================


;==============================================================================
; cpTest  -  Game screen copper list
;
; Sets up the display for the main gameplay screen:
;   - Slow fetch mode ($01fc = FMODE register, value $0000 = OCS compatible)
;   - Display window (DIWSTRT / DIWSTOP) = game screen boundaries
;   - Bitplane DMA fetch window (DDFSTRT / DDFSTOP)
;   - BPLCON0 = $5200  : 5 bitplanes (bits 14:12 = 101), colour enable (bit 9)
;   - BPLCON1 = $0000  : no horizontal scroll
;   - BPLCON2 = $0024  : sprites 0-3 above playfield, sprite priority
;   - BPL1MOD / BPL2MOD = SCREEN_MOD  : interleave modulo for 5-plane layout
;   - 5 pairs of BPLxPTH/L for bitplane addresses (patched at runtime)
;   - 8 pairs of SPRxPTH/L for sprite addresses   (patched at runtime)
;   - 32 COLOR register writes                    (patched at runtime)
;   - Two COPPER_HALT longwords to stop the Copper
;
; BPLCON0 = $5200 breakdown:
;   bits 14:12 = 101 -> 5 bitplanes (BPU field)
;   bit  9     = 1   -> colour enable
;   bits 8:0   = 000 -> lo-res, non-interlaced, no EHB/HAM
;
; BPLCON2 = $0024:
;   bits 5:3 = 100 -> sprites 0-3 win over odd playfield where they overlap
;   bits 2:0 = 100 -> sprites 0-3 win over even playfield
;
;==============================================================================

cpTest:
    dc.w    $01fc,$0000             ; FMODE: OCS-compatible slow fetch mode (must be first)

; cpGameDIW - DIWSTRT/DIWSTOP pair patched by DetectNTSC for NTSC machines.
cpGameDIW:
    dc.w    DIWSTRT,WINDOW_START    ; display window top-left  ($2c71 PAL / patched NTSC)
    dc.w    DIWSTOP,WINDOW_STOP     ; display window bottom-right ($04c1 PAL / patched NTSC)
    dc.w    DDFSTRT,FETCH_START     ; bitplane DMA fetch start  ($30)
    dc.w    DDFSTOP,FETCH_STOP      ; bitplane DMA fetch stop   ($d0)

    dc.w    BPLCON0,$4200           ; 4 bitplanes, colour enable, lo-res
    dc.w    BPLCON1,$0000           ; no horizontal bitplane scroll
cpBPLCON2:
    dc.w    BPLCON2,$0024           ; sprite/playfield priority control (patched live by player water logic)
    dc.w    BPL1MOD,TILEMAP_SCREEN_MOD ; odd-plane modulo  (skip 3 planes between rows = 120 bytes)
    dc.w    BPL2MOD,TILEMAP_SCREEN_MOD ; even-plane modulo (same value for non-interlaced)

; cpPlanes  - patched by GameCopperInit to point at DisplayScreen bitplanes.
; Each plane occupies SCREEN_WIDTH_BYTE bytes per row.  The five planes are
; stored consecutively: plane0 row0, plane1 row0 ... plane4 row0, plane0 row1 ...
; (interleaved layout as required by the SCREEN_MOD modulo scheme).
cpPlanes:
    dc.w    BPL1PTH,0               ; bitplane 1 address high word (patched)
    dc.w    BPL1PTL,0               ; bitplane 1 address low  word (patched)
    dc.w    BPL2PTH,0               ; bitplane 2 address high word (patched)
    dc.w    BPL2PTL,0               ; bitplane 2 address low  word (patched)
    dc.w    BPL3PTH,0               ; bitplane 3 address high word (patched)
    dc.w    BPL3PTL,0               ; bitplane 3 address low  word (patched)
    dc.w    BPL4PTH,0               ; bitplane 4 address high word (patched)
    dc.w    BPL4PTL,0               ; bitplane 4 address low  word (patched)
    dc.w    BPL5PTH,0               ; bitplane 5 address high word (patched)
    dc.w    BPL5PTL,0               ; bitplane 5 address low  word (patched)

; cpSprites  - patched each frame by ShowSprite / ClearSprites.
; On the OCS/ECS Amiga there are 8 hardware sprite channels (SPR0..SPR7).
;   SPR0-1  player character (attached pair, 16px wide, 16 colours)
;   SPR2-5  free / unused (NullSprite)
;   SPR6    air bubble (solo, on water levels)
;   SPR7    free / unused (NullSprite)
cpSprites:
    dc.w    SPR0PTH,0               ; sprite 0 data pointer high (patched -> Player SPR0)
    dc.w    SPR0PTL,0               ; sprite 0 data pointer low  (patched -> Player SPR0)
    dc.w    SPR1PTH,0               ; sprite 1 data pointer high (patched -> Player SPR1)
    dc.w    SPR1PTL,0               ; sprite 1 data pointer low  (patched -> Player SPR1)
    dc.w    SPR2PTH,0               ; sprite 2 data pointer high (NullSprite)
    dc.w    SPR2PTL,0               ; sprite 2 data pointer low  (NullSprite)
    dc.w    SPR3PTH,0               ; sprite 3 data pointer high (NullSprite)
    dc.w    SPR3PTL,0               ; sprite 3 data pointer low  (NullSprite)
    dc.w    SPR4PTH,0               ; sprite 4 data pointer high (NullSprite)
    dc.w    SPR4PTL,0               ; sprite 4 data pointer low  (NullSprite)
    dc.w    SPR5PTH,0               ; sprite 5 data pointer high (NullSprite)
    dc.w    SPR5PTL,0               ; sprite 5 data pointer low  (NullSprite)
    dc.w    SPR6PTH,0               ; sprite 6 data pointer high (NullSprite / Bubble)
    dc.w    SPR6PTL,0               ; sprite 6 data pointer low  (NullSprite / Bubble)
    dc.w    SPR7PTH,0               ; sprite 7 data pointer high (NullSprite)
    dc.w    SPR7PTL,0               ; sprite 7 data pointer low  (NullSprite)

; cpPal  - 32 palette entries, patched by SetLevelAssets / GameCopperInit.
; COLOR00 (index 0) is the background colour, also used for transparent sprite pixels.
; Colors 0-15  = tile/background palette (from tiles_N.pal)
; Colors 16-31 = sprite / actor palette  (from sprites.pal)
; Initial value $00f (blue) is a placeholder visible only before the real palette is loaded.
cpPal:
    dc.w    COLOR00,$00f            ; colour  0: background (placeholder blue)
    dc.w    COLOR01,0               ; colour  1 (patched)
    dc.w    COLOR02,0               ; colour  2 (patched)
    dc.w    COLOR03,0               ; colour  3 (patched)
    dc.w    COLOR04,0               ; colour  4 (patched)
    dc.w    COLOR05,0               ; colour  5 (patched)
    dc.w    COLOR06,0               ; colour  6 (patched)
    dc.w    COLOR07,0               ; colour  7 (patched)
    dc.w    COLOR08,0               ; colour  8 (patched)
    dc.w    COLOR09,0               ; colour  9 (patched)
    dc.w    COLOR10,0               ; colour 10 (patched)
    dc.w    COLOR11,0               ; colour 11 (patched)
    dc.w    COLOR12,0               ; colour 12 (patched)
    dc.w    COLOR13,0               ; colour 13 (patched)
    dc.w    COLOR14,0               ; colour 14 (patched)
    dc.w    COLOR15,0               ; colour 15 (patched)
    dc.w    COLOR16,0               ; colour 16 - sprite palette start (patched)
    dc.w    COLOR17,0               ; colour 17 (patched)
    dc.w    COLOR18,0               ; colour 18 (patched)
    dc.w    COLOR19,0               ; colour 19 (patched)
    dc.w    COLOR20,0               ; colour 20 (patched)
    dc.w    COLOR21,0               ; colour 21 (patched)
    dc.w    COLOR22,0               ; colour 22 (patched)
    dc.w    COLOR23,0               ; colour 23 (patched)
    dc.w    COLOR24,0               ; colour 24 (patched)
    dc.w    COLOR25,0               ; colour 25 (patched)
    dc.w    COLOR26,0               ; colour 26 (patched)
    dc.w    COLOR27,0               ; colour 27 (patched)
    dc.w    COLOR28,0               ; colour 28 (patched)
    dc.w    COLOR29,0               ; colour 29 (patched)
    dc.w    COLOR30,0               ; colour 30 (patched)
    dc.w    COLOR31,0               ; colour 31 (patched)

; cpGameSky - 216-scanline copper sky gradient with 1/2 vertical parallax
; Covers PAL lines $2c..$103 (lines 44..259 = 216 scanlines).
; Each scanline entry: WAIT (line, pos), MOVE COLOR00, color
cpGameSky:
sky_line set $2c
    rept 212
    dc.w (sky_line<<8)|$07,$fffe, COLOR00,$0000
sky_line set sky_line+1
    endr

    ; Cross line-255 boundary (V bit 8): all subsequent WAITs compare against line-256
    dc.w $ffdf,$fffe

sky_line set $00
    rept 4
    dc.w (sky_line<<8)|$07,$fffe, COLOR00,$0000
sky_line set sky_line+1
    endr

    ; Switch back to black background at line 200+44+16 = 260 ($104 -> VPOS $04)
    dc.w $0407,$fffe, COLOR00,$0000

    dc.l    COPPER_HALT             ; end-of-list marker 1 ($fffffffe)
    dc.l    COPPER_HALT             ; end-of-list marker 2 (belt-and-braces)

; cpVHSDistort - VHS tracking-error scanline distortion slots (inactive, past COPPER_HALT)
cpVHSDistort:
    ds.w    12                      ; 3 slots x 4 words = 12 words



;==============================================================================
; cpLoading  -  Title screen copper list
;
; Identical structure to cpTest but uses a wider screen geometry to accommodate
; the loading screen which is larger than the game screen (extra pixels for the
; scrolling star effect on plane 4).
;
; Loading screen is LOADING_SCREEN_WIDTH x LOADING_SCREEN_HEIGHT pixels.
; BPL1MOD / BPL2MOD = LOADING_SCREEN_MOD (wider than game screen).
;
; The star graphics are blitted onto bitplane 4 of DisplayScreen by BlitStar32.
; The title logo is copied to bitplanes 0-2 of DisplayScreen by LoadingSetup.
; Bitplane 3 is unused (background = colour 0 = black).
;==============================================================================

cpLoading:
    dc.w    $01fc,$0000             ; FMODE: OCS-compatible slow fetch mode

    dc.w    DIWSTRT,LOADING_WINDOW_START  ; 336px display window (H=$71 = WINDOW_X_START)
    dc.w    DIWSTOP,LOADING_WINDOW_STOP   ; 200-line display (V=244)
    dc.w    DDFSTRT,LOADING_FETCH_START   ; fetch 42 bytes = 336px per plane per line (= FETCH_START)
    dc.w    DDFSTOP,LOADING_FETCH_STOP

    dc.w    BPLCON0,$5200           ; 5 bitplanes, colour enable, lo-res
    dc.w    BPLCON1,$0000           ; no horizontal scroll
    dc.w    BPLCON2,$0024           ; sprite/playfield priority
    dc.w    BPL1MOD,LOADING_MOD          ; interleaved 5-plane modulo: 42*4 = 168 = SCREEN_MOD
    dc.w    BPL2MOD,LOADING_MOD

; cpLoadingPlanes  - patched by LoadingCopperSetup.
; Bitplane pointers stride by LOADING_WIDTH_BYTE (42) = SCREEN_WIDTH_BYTE.
cpLoadingPlanes:
    dc.w    BPL1PTH,0               ; title bitplane 1 high (patched)
    dc.w    BPL1PTL,0               ; title bitplane 1 low  (patched)
    dc.w    BPL2PTH,0               ; title bitplane 2 high (patched)
    dc.w    BPL2PTL,0               ; title bitplane 2 low  (patched)
    dc.w    BPL3PTH,0               ; title bitplane 3 high (patched)
    dc.w    BPL3PTL,0               ; title bitplane 3 low  (patched)
    dc.w    BPL4PTH,0               ; title bitplane 4 high (patched)
    dc.w    BPL4PTL,0               ; title bitplane 4 low  (patched)
    dc.w    BPL5PTH,0               ; title bitplane 5 high (patched)
    dc.w    BPL5PTL,0               ; title bitplane 5 low  (patched)

; cpLoadingSprites  - all 8 sprites pointed at NullSprite on the loading screen.
; (No hardware sprites used on title; the star animation uses the blitter.)
cpLoadingSprites:
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

; cpLoadingPal  - loading screen palette, set at the start of every frame.
; COLOR00 here is the ZX border colour at the very top of the frame (lines 0
; up to the first cpLoadingBorderBars entry); LoadingUpdateBorderBars patches
; it every frame to the first stripe's colour so the pattern is seamless.
; After loading it is set to ZX_BORDER_DONE by LoadingSwapPalette.
; Colours 1-31 are the greyscale loading ramp; replaced by LoadingSwapPalette.
cpLoadingPal:
cpLoadingBorderTop:
    dc.w    COLOR00,$000            ; colour  0: border top (patched per frame by LoadingUpdateBorderBars)
    dc.w    COLOR01,$111            ; colour  1
    dc.w    COLOR02,$222            ; colour  2
    dc.w    COLOR03,$333            ; colour  3
    dc.w    COLOR04,$444            ; colour  4
    dc.w    COLOR05,$555            ; colour  5
    dc.w    COLOR06,$666            ; colour  6
    dc.w    COLOR07,$777            ; colour  7
    dc.w    COLOR08,$888            ; colour  8
    dc.w    COLOR09,$999            ; colour  9
    dc.w    COLOR10,$aaa            ; colour 10
    dc.w    COLOR11,$bbb            ; colour 11
    dc.w    COLOR12,$ccc            ; colour 12
    dc.w    COLOR13,$ddd            ; colour 13
    dc.w    COLOR14,$eee            ; colour 14
    dc.w    COLOR15,$fff            ; colour 15
    dc.w    COLOR16,$111            ; colour 16
    dc.w    COLOR17,$222            ; colour 17
    dc.w    COLOR18,$333            ; colour 18
    dc.w    COLOR19,$444            ; colour 19
    dc.w    COLOR20,$555            ; colour 20
    dc.w    COLOR21,$666            ; colour 21
    dc.w    COLOR22,$777            ; colour 22
    dc.w    COLOR23,$888            ; colour 23
    dc.w    COLOR24,$999            ; colour 24
    dc.w    COLOR25,$aaa            ; colour 25
    dc.w    COLOR26,$bbb            ; colour 26
    dc.w    COLOR27,$ccc            ; colour 27
    dc.w    COLOR28,$ddd            ; colour 28
    dc.w    COLOR29,$eee            ; colour 29
    dc.w    COLOR30,$fff            ; colour 30
    dc.w    COLOR31,$fff            ; colour 31

; cpLoadingBorderBars - full-width ZX border stripes for the top border
; (rasters 0..ZX_TOP_END-1).  ZX_NUM_BORDER_BARS WAIT+COLOR00 entries,
; rebuilt EVERY frame by LoadingUpdateBorderBars (loading.asm): even red/cyan
; pilot-tone bars during the screenname intro, random-height yellow/blue bars
; during the data load.  Each entry holds its colour across the full scanline
; width until the next entry fires (there are no "off" entries).
; Initial state: parked at the region end (invisible) — the first LoadingRun
; frame patches in the real pattern.
cpLoadingBorderBars:
    REPT    ZX_NUM_BORDER_BARS
    dc.w    (ZX_TOP_END<<8)|$07,$FFFE
    dc.w    COLOR00,$000
    ENDR

; Top border terminator: whatever the last bar was, COLOR00 returns to black
; at raster ZX_TOP_END (40), before the image area starts at raster 44
; (static entry — never patched).
    dc.w    (ZX_TOP_END<<8)|$07,$FFFE
    dc.w    COLOR00,$000

; cpLoadingImageStart - fired at the first line of the title display area.
; Switches COLOR00 from the border colour to the title image background so that
; unset pixels inside the 320x200 window appear black, not the border colour.
; The WAIT Y byte ($2C) matches LOADING_WINDOW_START vertical = WINDOW_Y_START.
cpLoadingImageStart:
    dc.w    $2C07,$FFFE             ; WAIT line 44 (start of title display area)
cpLoadingImageBg:
    dc.w    COLOR00,$000            ; title image background (black)

; cpLoadingWash - colour reveal effect: greyscale palette applied at a scan line
; that moves from the top to the bottom of the screen each frame, so the full
; colour (from cpLoadingPal) is revealed progressively top-to-bottom.
;
; The WAIT Y byte (high byte of first word) is patched each frame by LoadingWashRun.
;
; Park positions matter because the bottom border bars follow this block:
;   During the load phases the wash is parked at $F3 (just above cpLoadingImageEnd)
;   — harmless, because it writes the greyscale ramp over the identical greyscale
;   values in cpLoadingPal, and it keeps every following WAIT in raster order so
;   the bottom border stripes fire correctly.
;   After the wash completes it is parked at $FF; that stalls the bottom blocks
;   until line 255, but by then they are parked black anyway (LoadingBorderBarsOff).
; Set to WINDOW_Y_START by LoadingSwapPalette when the ZX load completes, then
; advanced downward each frame.
cpLoadingWash:
    dc.w    $f307,$fffe             ; WAIT Y=$F3 (parked above the bottom border)
    dc.w    COLOR00,$000            ; greyscale palette — mirrors cpLoadingPal initial values
    dc.w    COLOR01,$111
    dc.w    COLOR02,$222
    dc.w    COLOR03,$333
    dc.w    COLOR04,$444
    dc.w    COLOR05,$555
    dc.w    COLOR06,$666
    dc.w    COLOR07,$777
    dc.w    COLOR08,$888
    dc.w    COLOR09,$999
    dc.w    COLOR10,$aaa
    dc.w    COLOR11,$bbb
    dc.w    COLOR12,$ccc
    dc.w    COLOR13,$ddd
    dc.w    COLOR14,$eee
    dc.w    COLOR15,$fff
    dc.w    COLOR16,$111
    dc.w    COLOR17,$222
    dc.w    COLOR18,$333
    dc.w    COLOR19,$444
    dc.w    COLOR20,$555
    dc.w    COLOR21,$666
    dc.w    COLOR22,$777
    dc.w    COLOR23,$888
    dc.w    COLOR24,$999
    dc.w    COLOR25,$aaa
    dc.w    COLOR26,$bbb
    dc.w    COLOR27,$ccc
    dc.w    COLOR28,$ddd
    dc.w    COLOR29,$eee
    dc.w    COLOR30,$fff
    dc.w    COLOR31,$fff

; cpLoadingImageEnd - fired at the first line past the image area (line $F4 = 244).
; Its COLOR00 doubles as the FIRST bottom-border bar: LoadingUpdateBorderBars
; patches cpLoadingBorderBot every frame, exactly like cpLoadingBorderTop.
cpLoadingImageEnd:
    dc.w    $F407,$FFFE             ; WAIT line 244 (first line after the 336x200 image)
cpLoadingBorderBot:
    dc.w    COLOR00,$000            ; bottom border bar 0 (patched per frame)

; cpLoadingBotBars1 - bottom-border stripes for raster lines 245-254.
; Same full-width WAIT+COLOR00 scheme as cpLoadingBorderBars; rebuilt every
; frame by LoadingUpdateBorderBars.  Initial state: parked at line 255, black.
cpLoadingBotBars1:
    REPT    ZX_NUM_BOT1_BARS
    dc.w    $FF07,$FFFE
    dc.w    COLOR00,$000
    ENDR

; cpLoadingBotBars2 - bottom-border stripes for raster lines 256-287.
; DISABLED: commented out so the bottom border is just the short strip covered
; by cpLoadingBotBars1 (rasters 244-254).  To bring the full-height bottom
; border back, uncomment this block AND the part-2 emission/parking sections
; in LoadingUpdateBorderBars / LoadingBorderBarsOff (loading.asm), and move
; the black terminator below back to (ZX_BOT_END<<8)|$07.
;    dc.w    $FFDF,$FFFE             ; cross the line-255 boundary (V bit 8): all
;                                    ; following WAITs compare against line-256
;cpLoadingBotBars2:
;    REPT    ZX_NUM_BOT2_BARS
;    dc.w    (ZX_BOT_END<<8)|$07,$FFFE
;    dc.w    COLOR00,$000
;    ENDR

; Bottom border terminator: whatever the last bar was, COLOR00 returns to
; black at raster 255 (static entry — never patched).
    dc.w    $FF07,$FFFE
    dc.w    COLOR00,$000

    dc.l    COPPER_HALT             ; end-of-list marker 1 ($fffffffe)
    dc.l    COPPER_HALT             ; end-of-list marker 2 (belt-and-braces)

;==============================================================================
; cpLevelComplete  -  Level-complete screen copper list
;
; Same geometry as cpTest (336×216, 5-plane interleaved).
; Adds two WAIT pairs to change COLOR00 to brown for the password banner area:
;   Banner on:  raster line $90 = 144 (pixel row 100 = WINDOW_Y_START+100)
;   Banner off: raster line $C0 = 192 (pixel row 148 = WINDOW_Y_START+148)
;
; Runtime patching in LevelCompleteSetup:
;   cpLCPlanes  - DisplayScreen bitplane addresses (same as cpTest)
;   cpLCSprites - all 8 sprite channels → NullSprite
;
; Palette notes:
;   COLOR00 = $000 black, copper overrides to LC_BANNER_COLOR at banner rows.
;   COLOR31 = $FFF white — text is drawn with all 5 planes set (index 31).
;   Colors 1-30 are portrait/artwork colors; adjust to match portrait assets.
;==============================================================================


cpLevelComplete:
    dc.w    $01fc,$0000             ; FMODE: OCS slow fetch
    dc.w    DIWSTRT,WINDOW_START
    dc.w    DIWSTOP,WINDOW_STOP
    dc.w    DDFSTRT,FETCH_START
    dc.w    DDFSTOP,FETCH_STOP
    dc.w    BPLCON0,$5200
    dc.w    BPLCON1,$0000
    dc.w    BPLCON2,$0024
    dc.w    BPL1MOD,SCREEN_MOD
    dc.w    BPL2MOD,SCREEN_MOD
cpLCPlanes:
    dc.w    BPL1PTH,0               ; patched by LevelCompleteSetup
    dc.w    BPL1PTL,0
    dc.w    BPL2PTH,0
    dc.w    BPL2PTL,0
    dc.w    BPL3PTH,0
    dc.w    BPL3PTL,0
    dc.w    BPL4PTH,0
    dc.w    BPL4PTL,0
    dc.w    BPL5PTH,0
    dc.w    BPL5PTL,0
cpLCSprites:
    dc.w    SPR0PTH,0               ; patched to NullSprite
    dc.w    SPR0PTL,0
    dc.w    SPR1PTH,0
    dc.w    SPR1PTL,0
    dc.w    SPR2PTH,0
    dc.w    SPR2PTL,0
    dc.w    SPR3PTH,0
    dc.w    SPR3PTL,0
    dc.w    SPR4PTH,0
    dc.w    SPR4PTL,0
    dc.w    SPR5PTH,0
    dc.w    SPR5PTL,0
    dc.w    SPR6PTH,0
    dc.w    SPR6PTL,0
    dc.w    SPR7PTH,0
    dc.w    SPR7PTL,0
cpLCPal:
    dc.w    COLOR00,$000            ; black background (copper overrides at banner)
    dc.w    COLOR01,$001
    dc.w    COLOR02,$112
    dc.w    COLOR03,$223
    dc.w    COLOR04,$334
    dc.w    COLOR05,$456
    dc.w    COLOR06,$678
    dc.w    COLOR07,$89A
    dc.w    COLOR08,$ABC
    dc.w    COLOR09,$CDD
    dc.w    COLOR10,$EEF
    dc.w    COLOR11,$023
    dc.w    COLOR12,$045
    dc.w    COLOR13,$078
    dc.w    COLOR14,$0AC
    dc.w    COLOR15,$7EF
    dc.w    COLOR16,$221
    dc.w    COLOR17,$442
    dc.w    COLOR18,$663
    dc.w    COLOR19,$885
    dc.w    COLOR20,$AA7
    dc.w    COLOR21,$410
    dc.w    COLOR22,$732
    dc.w    COLOR23,$A53
    dc.w    COLOR24,$D74
    dc.w    COLOR25,$FA6
    dc.w    COLOR26,$D33
    dc.w    COLOR27,$3B5
    dc.w    COLOR28,$557
    dc.w    COLOR29,$99B
    dc.w    COLOR30,$FE9
    dc.w    COLOR31,$FFF            ; white — all planes set; used for all text
; Banner gradient: 12 colour steps across 48 scanlines (4 lines each).
; cpLCBanner label used by LC_ShimmerBanner to rotate colour words each frame.
; Colour word for step i sits at cpLCBanner + 6 + i*8.
cpLCBanner:
    dc.w    $9007,$FFFE             ; WAIT raster $90 (pixel row 100 — banner top)
    dc.w    COLOR00,$0210           ; step  0: darkest edge
    dc.w    $9407,$FFFE             ; WAIT raster $94 (pixel row 104)
    dc.w    COLOR00,$0321           ; step  1
    dc.w    $9807,$FFFE             ; WAIT raster $98 (pixel row 108)
    dc.w    COLOR00,$0432           ; step  2
    dc.w    $9C07,$FFFE             ; WAIT raster $9C (pixel row 112)
    dc.w    COLOR00,$0543           ; step  3
    dc.w    $A007,$FFFE             ; WAIT raster $A0 (pixel row 116)
    dc.w    COLOR00,$0764           ; step  4
    dc.w    $A407,$FFFE             ; WAIT raster $A4 (pixel row 120)
    dc.w    COLOR00,$0974           ; step  5
    dc.w    $A807,$FFFE             ; WAIT raster $A8 (pixel row 124)
    dc.w    COLOR00,$0A74           ; step  6: bright amber peak
    dc.w    $AC07,$FFFE             ; WAIT raster $AC (pixel row 128)
    dc.w    COLOR00,$0974           ; step  7
    dc.w    $B007,$FFFE             ; WAIT raster $B0 (pixel row 132)
    dc.w    COLOR00,$0764           ; step  8
    dc.w    $B407,$FFFE             ; WAIT raster $B4 (pixel row 136)
    dc.w    COLOR00,$0543           ; step  9
    dc.w    $B807,$FFFE             ; WAIT raster $B8 (pixel row 140)
    dc.w    COLOR00,$0432           ; step 10
    dc.w    $BC07,$FFFE             ; WAIT raster $BC (pixel row 144)
    dc.w    COLOR00,$0321           ; step 11: darkest edge
    dc.w    $C007,$FFFE             ; WAIT raster $C0 (pixel row 148 — banner bottom)
    dc.w    COLOR00,$0000           ; restore black
    dc.l    COPPER_HALT
    dc.l    COPPER_HALT

; Level-complete screen font glyphs (8×8 pixels, 1 bitplane, ASCII 32-127)
; 96 characters × 8 bytes = 768 bytes
; Glyph for char c is at FontData + (c-32)*8
FontData:
    incbin  "assets/font/font.bin"

; Level-complete portrait images:
; Millie and Molly face graphics removed (freed 5,120 bytes Chip RAM).
MilliePic:
MollyPic:

;==============================================================================
; cpTitle  -  Title screen copper list (states TITLE_SETUP / TITLE_RUN)
;
; Same 336x200 display geometry as cpLoading.  Bitplanes 0-2 carry the
; 8-colour title logo (TitleLogoRaw, blitted by TitleSetup); planes 3-4
; carry the menu text characters.
;
; Colour index mapping (5-plane, bit0=BPL1 … bit4=BPL5):
;   COLOR00    = background / overscan (driven per-band by the aurora effect,
;                see cpTitleSky below and TS_UpdateSky in titlescreen.asm)
;   COLOR01-07 = title logo palette (patched from TitleLogoPal by TitleSetup;
;                colour 0 of the logo is transparent = background)
;   COLOR08-23 = $000 (unused - black)
;   COLOR24    = $00C0 green text  (planes 3+4)
;   COLOR26    = $0EE0 yellow text (planes 1+3+4)
;   COLOR28    = $0C00 red text    (planes 2+3+4)
;   COLOR31    = $0FFF white text  (all 5 planes set by CHAR_BLTOneChar)
;==============================================================================

cpTitle:
    dc.w    $01fc,$0000             ; FMODE: OCS-compatible slow fetch mode

    dc.w    DIWSTRT,LOADING_WINDOW_START  ; 336px display window (H=$71 = WINDOW_X_START)
    dc.w    DIWSTOP,LOADING_WINDOW_STOP   ; 200-line display (V=244)
    dc.w    DDFSTRT,LOADING_FETCH_START   ; fetch 42 bytes = 336px per plane per line (= FETCH_START)
    dc.w    DDFSTOP,LOADING_FETCH_STOP

    dc.w    BPLCON0,$5200           ; 5 bitplanes, colour enable, lo-res
    dc.w    BPLCON1,$0000           ; no horizontal scroll
    dc.w    BPLCON2,$0024           ; sprite/playfield priority
    dc.w    BPL1MOD,LOADING_MOD     ; interleaved 5-plane modulo
    dc.w    BPL2MOD,LOADING_MOD

; cpTitlePlanes - patched by TitleSetup with DisplayScreen bitplane addresses.
cpTitlePlanes:
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

; cpTitleSprites - all 8 sprites pointed at NullSprite (no hardware sprites used).
cpTitleSprites:
    dc.w    SPR0PTH,0
    dc.w    SPR0PTL,0
    dc.w    SPR1PTH,0
    dc.w    SPR1PTL,0
    dc.w    SPR2PTH,0
    dc.w    SPR2PTL,0
    dc.w    SPR3PTH,0
    dc.w    SPR3PTL,0
    dc.w    SPR4PTH,0
    dc.w    SPR4PTL,0
    dc.w    SPR5PTH,0
    dc.w    SPR5PTL,0
    dc.w    SPR6PTH,0
    dc.w    SPR6PTL,0
    dc.w    SPR7PTH,0
    dc.w    SPR7PTL,0

; cpTitlePal - title screen palette.
; COLOR01-07 are patched from TitleLogoPal by TitleSetup (title logo colours).
cpTitlePal:
    dc.w    COLOR00,$0000           ; 00: background / overscan (cpTitleSky overrides per band)
    dc.w    COLOR01,$0000           ; 01: logo colour 1 (patched)
    dc.w    COLOR02,$0000           ; 02: logo colour 2 (patched)
    dc.w    COLOR03,$0000           ; 03: logo colour 3 (patched)
    dc.w    COLOR04,$0000           ; 04: logo colour 4 (patched)
    dc.w    COLOR05,$0000           ; 05: logo colour 5 (patched)
    dc.w    COLOR06,$0000           ; 06: logo colour 6 (patched)
    dc.w    COLOR07,$0000           ; 07: logo colour 7 (patched)
    dc.w    COLOR08,$0000           ; 08-30: unused = black
    dc.w    COLOR09,$0000
    dc.w    COLOR10,$0000
    dc.w    COLOR11,$0000
    dc.w    COLOR12,$0000
    dc.w    COLOR13,$0000
    dc.w    COLOR14,$0000
    dc.w    COLOR15,$0000
    dc.w    COLOR16,$0000
    dc.w    COLOR17,$0000
    dc.w    COLOR18,$0000
    dc.w    COLOR19,$0000
    dc.w    COLOR20,$0000
    dc.w    COLOR21,$0000
    dc.w    COLOR22,$0000
    dc.w    COLOR23,$0000
    dc.w    COLOR24,$00C0           ; 24: green text  (P3+P4 set)
    dc.w    COLOR25,$0000
    dc.w    COLOR26,$0EE0           ; 26: yellow text (P1+P3+P4 set)
    dc.w    COLOR27,$0000
    dc.w    COLOR28,$0C00           ; 28: red text    (P2+P3+P4 set)
    dc.w    COLOR29,$0000
    dc.w    COLOR30,$0000
    dc.w    COLOR31,$0FFF           ; 31: white text (all 5 planes set by CHAR_BLTOneChar)

; cpTitleSky  -  per-band COLOR00 entries for the aurora background effect.
;
; SKY_ENTRIES (68) WAIT+MOVE pairs, one per 2 scanlines, covering rows 0-135
; (rasters $2C-$B2) — everything above the password/menu text.  The colour
; words (byte +6 of each 8-byte entry) are rewritten every frame by
; TS_UpdateSky in titlescreen.asm: two counter-drifting sine waves drive the
; blue and green channels, giving smoothly morphing aurora curtains.
; Only COLOR00 is written — colours 1-7 belong to the title logo and
; colours 24/26/28/31 to the menu text.
SKY_ROW SET $2C
cpTitleSky:
    REPT    68
    dc.w    (SKY_ROW<<8)|$07,$FFFE
    dc.w    COLOR00,$0000           ; patched every frame by TS_UpdateSky
SKY_ROW SET SKY_ROW+2
    ENDR

; Text area (rows 136-199): static black background so the password line and
; menu options stay maximally readable.  TS_UpdateSky's dim table fades the
; last aurora bands to black, so there is no visible seam at this boundary.
    dc.w    $B407,$FFFE
    dc.w    COLOR00,$0000
    dc.l    COPPER_HALT
    dc.l    COPPER_HALT

;==============================================================================
; cpGameComplete  -  Game complete screen copper list (states 15 / 16)
;
; Same 336×200 geometry as cpTitle (LOADING_xxx constants).  Stars in plane 0
; appear white outside the logo (COLOR01=$0FFF) and cream inside (COLOR03=$0DC7).
;
; Colour mapping (5 bitplanes; bit0=BPL1 … bit4=BPL5):
;   COLOR00 = $0000  background = black
;   COLOR01 = $0FFF  BPL1 only: star outside logo = white
;   COLOR02 = $05BB  BPL2 only: logo interior = teal
;   COLOR03 = $0DC7  BPL1+BPL2: star inside logo = cream
;   COLOR04 = $0222  BPL3 only: logo outline = dark grey
;   COLOR05 = $0222  BPL1+BPL3: star on logo outline
;   COLOR06 = $0222  BPL2+BPL3: interior+outline
;   COLOR07 = $0222  BPL1+BPL2+BPL3: star+interior+outline
;   COLOR24 = $00C0  BPL4+BPL5: green text
;   COLOR28 = $0C00  BPL3+BPL4+BPL5: pink/red text
;   COLOR31 = $0FFF  all planes: white text
;==============================================================================

cpGameComplete:
    dc.w    $01fc,$0000             ; FMODE: OCS-compatible slow fetch mode

    dc.w    DIWSTRT,LOADING_WINDOW_START  ; 336px display window (H=$71)
    dc.w    DIWSTOP,LOADING_WINDOW_STOP   ; 200-line display
    dc.w    DDFSTRT,LOADING_FETCH_START
    dc.w    DDFSTOP,LOADING_FETCH_STOP

    dc.w    BPLCON0,$5200           ; 5 bitplanes, colour enable, lo-res
    dc.w    BPLCON1,$0000           ; no horizontal scroll
    dc.w    BPLCON2,$0024           ; sprite/playfield priority
    dc.w    BPL1MOD,LOADING_MOD
    dc.w    BPL2MOD,LOADING_MOD

; cpGCPlanes - patched by GameCompleteSetup with DisplayScreen bitplane addresses.
cpGCPlanes:
    dc.w    BPL1PTH,0
    dc.w    BPL1PTL,0
    dc.w    BPL2PTH,0
    dc.w    BPL2PTL,0
    dc.w    BPL3PTH,0
    dc.w    BPL3PTL,0
    dc.w    BPL4PTH,0
    dc.w    BPL4PTL,0
    dc.w    BPL5PTH,0
    dc.w    BPL5PTL,0

; cpGCSprites - all 8 sprites pointed at NullSprite (no hardware sprites used).
cpGCSprites:
    dc.w    SPR0PTH,0
    dc.w    SPR0PTL,0
    dc.w    SPR1PTH,0
    dc.w    SPR1PTL,0
    dc.w    SPR2PTH,0
    dc.w    SPR2PTL,0
    dc.w    SPR3PTH,0
    dc.w    SPR3PTL,0
    dc.w    SPR4PTH,0
    dc.w    SPR4PTL,0
    dc.w    SPR5PTH,0
    dc.w    SPR5PTL,0
    dc.w    SPR6PTH,0
    dc.w    SPR6PTL,0
    dc.w    SPR7PTH,0
    dc.w    SPR7PTL,0

; cpGCPal - game complete screen palette.
cpGCPal:
    dc.w    COLOR00,$0000           ; 00: background = black
    dc.w    COLOR01,$0FFF           ; 01: star outside logo = white
    dc.w    COLOR02,$05BB           ; 02: logo interior = teal
    dc.w    COLOR03,$0DC7           ; 03: star inside logo = cream
    dc.w    COLOR04,$0222           ; 04: logo outline = dark grey
    dc.w    COLOR05,$0222           ; 05: star on logo outline
    dc.w    COLOR06,$0222           ; 06: logo interior + outline
    dc.w    COLOR07,$0222           ; 07: star + logo interior + outline
    dc.w    COLOR08,$0000
    dc.w    COLOR09,$0000
    dc.w    COLOR10,$0000
    dc.w    COLOR11,$0000
    dc.w    COLOR12,$0000
    dc.w    COLOR13,$0000
    dc.w    COLOR14,$0000
    dc.w    COLOR15,$0000
    dc.w    COLOR16,$0000
    dc.w    COLOR17,$0000
    dc.w    COLOR18,$0000
    dc.w    COLOR19,$0000
    dc.w    COLOR20,$0000
    dc.w    COLOR21,$0000
    dc.w    COLOR22,$0000
    dc.w    COLOR23,$0000
    dc.w    COLOR24,$00C0           ; 24: green text  (BPL4+BPL5 set)
    dc.w    COLOR25,$0000
    dc.w    COLOR26,$0000
    dc.w    COLOR27,$0000
    dc.w    COLOR28,$0C00           ; 28: pink/red text (BPL3+BPL4+BPL5 set)
    dc.w    COLOR29,$0000
    dc.w    COLOR30,$0000
    dc.w    COLOR31,$0FFF           ; 31: white text (all planes set)

; Per-scanline COLOR01 entries written at runtime by GameCompleteSetup.
; 185 WAIT+MOVE pairs (display Y=0..GC_STAR_MAX_Y) + COPPER_HALT×2.
; Stars appear white/yellow/red/blue based on their Y position.
cpGCDynColors:
    ds.w    (GC_STAR_MAX_Y+1)*2+4

