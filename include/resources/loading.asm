;==============================================================================
; AMIGA GAME ENGINE
; loading.asm  -  Loading Screen Setup and Animation
;==============================================================================
;
; Handles game states 0 (LoadingSetup) and 1 (LoadingRun).
;
; The loading screen uses a full-screen DisplayScreen buffer (5-plane interleaved,
; 336x200 pixels).  The ZX Spectrum tape-load animation reveals the image row by row,
; followed by a top-to-bottom colour wash via a copper WAIT that advances each frame.
;
;==============================================================================

;------------------------------------------------------------------------------
; Loading screen geometry constants (320x200)
;------------------------------------------------------------------------------
LOADING_WIDTH             = 320                           ; pixel width (standard 320px Amiga lo-res)
LOADING_WIDTH_BYTE        = LOADING_WIDTH/8               ; bytes per row per plane = 40
LOADING_DEPTH             = 5                             ; bitplanes = 32 colours
LOADING_HEIGHT            = 200                           ; pixel height

; Title screen display window: 320px wide, standard H=$81 left edge (no sprite shift needed)
LOADING_WINDOW_START      = (WINDOW_Y_START<<8)|$81       ; DIWSTRT: V=44, H=$81
LOADING_WINDOW_STOP       = ($F4<<8)|WINDOW_X_STOP        ; DIWSTOP: V=244, H=$C1 (200 lines)

; Title DDF: 320px — DDFSTRT=$38 is standard for a display starting at H=$81
; Fetches 20 words = 40 bytes per plane per line.
LOADING_FETCH_START       = $38                           ; $38 — standard for H=$81, 320px
LOADING_FETCH_STOP        = FETCH_STOP                    ; $D0

; ZX Spectrum screen-load animation parameters
; With 320px DDF (40 bytes fetched = 40 bytes stride), LOADING_MOD = (DEPTH-1)*40 = 160.
; Raw file is 320/8*200*5 = 40000 bytes. LoadingCopyRow copies LOADING_ROW_BYTES per row.
LOADING_MOD               = LOADING_WIDTH_BYTE*(LOADING_DEPTH-1)   ; BPLxMOD = 40*4 = 160
LOADING_ROW_BYTES         = LOADING_DEPTH*LOADING_WIDTH_BYTE        ; bytes per interleaved row = 200
ZX_LOAD_SPEED           = 2             ; frames per ZX step (must be power of 2)
ZX_SECTION_ROWS         = 64            ; rows per ZX section (top/mid/bottom)
ZX_TAIL_ROWS            = LOADING_HEIGHT-(ZX_SECTION_ROWS*3)   ; extra rows beyond 3 sections = 8
ZX_STEPS_TOTAL          = ZX_SECTION_ROWS*3+ZX_TAIL_ROWS      ; total animation steps = 200
ZX_WASH_SPEED           = 3             ; scan lines advanced per frame during colour wash

; ZX Spectrum-style border stripes.
; The top border (rasters 0..39) AND a short bottom strip (rasters $F4..$FE;
; the full-height part 2 covering rasters 256-287 is currently commented out)
; are rebuilt EVERY frame by LoadingUpdateBorderBars into the
; cpLoadingBorderBars / cpLoadingBotBars1 copper blocks.  Each entry is a
; full-width WAIT + COLOR00 pair — the colour holds across the whole scanline
; until the next entry, exactly like a real Spectrum border:
;
;   header (intro):    red/cyan pilot-tone bars, ZX_PILOT_HEIGHT lines each,
;                      crawling one line per frame (the steady leader tone);
;                      the last ZX_HEADER_DATA_FRAMES flicker as a brief
;                      yellow/blue burst — the header's own data bytes
;   inter-block gap:   tape silence — audio stopped, border static black
;   data load:         yellow/blue bars with random 1-4 line heights,
;                      regenerated every frame (the data-block flicker)
;
; ZX_NUM_BORDER_BARS entries cover the 40-line top border; entries left over
; in a frame are parked at the region end, where a static terminator entry
; sets COLOR00 back to black anyway.
ZX_BORDER_A             = $00f          ; data stripes: bright blue
ZX_BORDER_B             = $ff0          ; data stripes: bright yellow
ZX_PILOT_A              = $f00          ; pilot stripes: bright red
ZX_PILOT_B              = $0ff          ; pilot stripes: bright cyan
ZX_BORDER_DONE          = $000          ; black (static border after load completes)
ZX_NUM_BORDER_BARS      = 24            ; copper entries in cpLoadingBorderBars (top)
ZX_BAR_FIRST_LINE       = 1             ; first patchable raster line of the top border
ZX_TOP_END              = 40            ; top bars cover rasters 0-39; a static
                                        ; terminator blacks COLOR00 at raster 40
ZX_PILOT_HEIGHT         = 4             ; scanlines per pilot bar (must be a power of 2)
ZX_NUM_BOT1_BARS        = 6             ; bottom entries for raster lines 245-254
ZX_NUM_BOT2_BARS        = 14            ; bottom entries for raster lines 256-287
ZX_BOT_FIRST_LINE       = $F4           ; bottom border starts where the image ends
ZX_BOT1_END             = $FF           ; part 1 ends at the 8-bit raster wrap
; The bottom border is exactly as tall as the top one (WINDOW_Y_START = 44
; lines): rasters 244..287.  A static terminator entry in the copper list
; (after cpLoadingBotBars2) sets COLOR00 back to black at this line.
ZX_BOT_END              = (ZX_BOT_FIRST_LINE+WINDOW_Y_START)-256   ; V byte $20 = raster 288
ZX_HEADER_DATA_FRAMES   = 12            ; intro tail shown as the header's data burst
ZX_GAP_FRAMES           = 50            ; tape silence between header and data (~1s;
                                        ; PAL frames, armed through ScalePALFrames)

; Pause between colour-wash completion and title screen transition.
; Authored in PAL frames; armed through ScalePALFrames so the real-time
; duration is the same on NTSC.
MENU_PAUSE_FRAMES    = 75                           ; ~1.5 seconds

; ZX tape-load audio: Paula channel 0 direct PCM playback
; All samples are 8-bit signed mono at 8000 Hz.
; Paula DMA auto-loops unless set up for one-shot (see LoadingScreenNameAudioStart).
; PAL: AUD0PER = 3,546,895 / 8000 = 443
ZX_AUDIO_PERIOD         = 443           ; Paula period for 8000 Hz playback (PAL)
ZX_AUDIO_VOL            = 40            ; Paula channel 0 volume (0-64)
; Screenname intro duration: zx_audio_screenname.wav = 26936 bytes at 8000Hz = 169 PAL frames.
; ceil(26936 / (8000/50)) = ceil(26936 / 160) = 169
SCREENNAME_FRAMES       = 180           ; VBlanks to wait while screenname audio plays

;==============================================================================
; LoadingSetup  -  Initialise the loading screen (game state 0)
;
; One-shot initialisation called once when GameStatus transitions to 0.
; After setup, immediately advances GameStatus to 1 (LoadingRun).
;
; Actions performed:
;   1. Clear DisplayScreen to black BEFORE the display is enabled, so no
;      leftover memory contents flash up as noise (the ZX animation then
;      reveals the image row by row into the blank screen).
;   2. Call LoadingCopperSetup to configure the title copper list with correct
;      bitplane pointers and palette.
;   3. Point the Copper at the title copper list (cpLoading) and restart it.
;   4. Set ScreenMemEnd to -1 (signals that the screen memory is valid).
;   5. Enable DMA (BASE_DMA).
;   6. Advance GameStatus to LoadingRun (1).
;   7. Decompress LoadingRawZ (ZX0-compressed loading image) into NonDisplayScreen,
;      which serves as the decompression staging buffer (unused at this phase).
;      This runs in the mainline (MainLoop), so taking several frames is
;      harmless — interrupts (keyboard, music) keep running throughout.
;      LoadingCopyRow and LoadingSkipAnimation then copy rows from NonDisplayScreen
;      into DisplayScreen as the ZX animation reveals the image progressively.
;
;==============================================================================

LoadingSetup:
    bsr         AudioStopMod           ; stop any prior music / SFX before title begins

    ; Clear DisplayScreen BEFORE the display is switched on.  The buffer may
    ; hold garbage (uninitialised memory / leftovers from a previous run) and
    ; the multi-frame decompression below would otherwise show it as noise.
    ; The ZX load animation then reveals the image into the blank screen.
    lea         DisplayScreen,a0
    move.l      #SCREEN_SIZE,d7
    bsr         TurboClear

    bsr         LoadingCopperSetup       ; set up loading copper list: planes, palette, sprites

    ; Switch Copper to the loading list
    move.l      #cpLoading,COP1LC(a6)    ; load loading copper list address into Copper 1
    move.w      #0,COPJMP1(a6)         ; strobe COPJMP1: Copper re-reads COP1LC and starts

    move.l      #-1,ScreenMemEnd       ; mark screen memory as initialised
 ;   move.w      #BASE_DMA,DMACON(a6)   ; enable Copper + Blitter + Bitplane + Sprite DMA

    addq.w      #GAME_LOADING,GameStatus(a5)      ; advance to state 1 (LoadingRun)

    ; Decompress ZX0 title graphic into NonDisplayScreen (42 KB staging buffer).
    lea        LoadingRawZ,a0
    lea        NonDisplayScreen,a1
    bsr        zx0_decompress

    ; Reset ZX load step counter and border-bar state.  RandomSeed drives the
    ; data-phase bar heights and must be non-zero (a Galois LFSR sticks at 0).
    clr.w       LoadingLoadStep(a5)
    clr.w       LoadingBarPhase(a5)
    clr.w       LoadingGapTick(a5)
    move.l      #$B4BCD35C,RandomSeed(a5)
    move.w      #SCREENNAME_FRAMES,d0
    bsr         ScalePALFrames                            ; keep real-time length on NTSC
    move.w      d0,LoadingIntroTick(a5)                   ; arm intro countdown
    clr.w       LoadingMenuTick(a5)                       ; post-wash pause not yet armed

    bsr         LoadingScreenNameAudioStart   ; play screenname audio once before load begins

    rts


;==============================================================================
; LoadingCopperSetup  -  Configure the loading screen copper list
;
; Patches cpLoadingPlanes with the addresses of DisplayScreen's five bitplanes
; (using LOADING_SCREEN_WIDTH_BYTE stride between planes), and copies the title
; palette from LoadingPal (32 entries) into cpLoadingPal.
;
; Also calls ClearSprites to point all 8 copper sprite entries at NullSprite
; (no hardware sprites used on the loading screen).
;==============================================================================

LoadingCopperSetup:
;    bsr         ClearSprites           ; hide all hardware sprites

    ; Patch bitplane pointers in the loading copper list.  The five planes of
    ; DisplayScreen are interleaved LOADING_WIDTH_BYTE (42) bytes apart.
    lea         cpLoadingPlanes,a0
    move.l      #DisplayScreen,d0
    move.l      #LOADING_WIDTH_BYTE,d1
    moveq       #SCREEN_DEPTH,d7
    bsr         CopperSetPtrs           ; shared copper pointer patcher (tools.asm)

    ; Palette is already B&W in cpLoadingPal; LoadingSwapPalette writes real colours
    ; when the ZX animation completes.

    rts


;==============================================================================
; LoadingRun  -  Loading screen per-frame handler (game state 1)
;
; Called once per frame while the loading screen is active.  Drives the ZX
; tape-load sequence, then a short pause, then transitions automatically to
; TITLE_SETUP:
;
;   0.  header      pilot bars + brief data burst   (screenname audio)
;   0.5 gap         tape silence, static border     (no audio, no bars)
;   1.  data load   row reveal, flickering bars     (data-load audio)
;   2.  colour wash top-to-bottom colour reveal     (colour audio, bars on)
;
; The border stripes run exactly while tape audio is playing and are parked
; (static black) whenever it is not.
;
; F6 at any point skips the remaining animation and jumps straight to the
; title screen (LoadingSkipAnimation).
;==============================================================================

LoadingRun:
    move.w      LoadingWashLine(a5),d0
    cmp.w       #LOADING_HEIGHT,d0
    bcc         .loaddone              ; wash complete — count down then go to title

    ; Still animating: F6 skips to end
    lea         Keys,a0
    tst.b       KEY_F6(a0)
    beq         .nostart
    clr.b       KEY_F6(a0)
    bsr         LoadingSkipAnimation
    rts

.nostart
    ; Phase 0: header block (screenname audio) — red/cyan pilot-tone bars,
    ; ending in a brief yellow/blue burst: the header's own data bytes.
    ; The border stripes only ever run while tape audio is playing.
    move.w      LoadingIntroTick(a5),d0
    beq.s       .dataphase               ; header done -> data phase audio

    cmp.w       #ZX_HEADER_DATA_FRAMES,d0
    bls.s       .intro_data             ; last few frames: header data burst
    move.w      #ZX_PILOT_A,d2          ; red
    move.w      #ZX_PILOT_B,d3          ; cyan
    moveq       #0,d4                   ; mode 0: even bars, slow crawl
    bra.s       .intro_bars
.intro_data
    move.w      #ZX_BORDER_B,d2         ; yellow
    move.w      #ZX_BORDER_A,d3         ; blue
    moveq       #1,d4                   ; mode 1: random flickering bars
.intro_bars
    bsr         LoadingUpdateBorderBars
    subq.w      #1,LoadingIntroTick(a5)
    bne.s       .intro_rts
    ; Header finished: tape goes silent — stop the audio, blank the border,
    ; and arm the inter-block gap (no audio = no bars)
;    bsr         LoadingAudioStop
;    bsr         LoadingBorderBarsOff
 ;   move.w      #ZX_GAP_FRAMES,d0
 ;   bsr         ScalePALFrames
    move.w      d0,LoadingGapTick(a5)
    beq.s       .loadphase
.intro_rts
    rts

.dataphase
    ; Phase 0.5: inter-block gap — tape silence, static black border
    move.w      LoadingGapTick(a5),d0
    beq.s       .loadphase              ; gap over (or never armed): load data
    subq.w      #1,LoadingGapTick(a5)
;    bne.s       .gap_rts
    bsr         LoadingAudioStart       ; gap elapsed: data-block audio begins
.gap_rts
    rts

.loadphase
    ; Phase 1: ZX screen-load animation — data-block border: yellow/blue bars
    ; with random heights, re-rolled every frame (the ZX data flicker)
    move.w      LoadingLoadStep(a5),d0
    cmp.w       #ZX_STEPS_TOTAL,d0
    bcc         .washphase

    move.w      #ZX_BORDER_B,d2         ; yellow
    move.w      #ZX_BORDER_A,d3         ; blue
    moveq       #1,d4                   ; mode 1: random flickering bars
    bsr         LoadingUpdateBorderBars

    move.w      TickCounter(a5),d0
    and.w       #ZX_LOAD_SPEED-1,d0   ; step every ZX_LOAD_SPEED frames
    bne         .animbar
    bsr         LoadingLoadStepRun       ; reveals rows + calls LoadingSwapPalette when done

.animbar
    rts

.washphase
    ; Phase 2: colour wash — full colour sweeps top-to-bottom via copper WAIT.
    ; The colour-load audio is still playing (the attributes are part of the
    ; data block on a real ZX), so the data-flicker border keeps running.
    move.w      LoadingWashLine(a5),d0
    cmp.w       #LOADING_HEIGHT,d0
    bcc         .loaddone

    tst.w       d0
    bne.s       .wash_run
    bsr         LoadingColorAudioStart    ; first wash frame: start colour-load audio
.wash_run
    move.w      #ZX_BORDER_B,d2           ; audio playing -> bars stay on
    move.w      #ZX_BORDER_A,d3
    moveq       #1,d4
    bsr         LoadingUpdateBorderBars
    bsr         LoadingWashRun            ; advance WAIT Y in cpLoadingWash
    rts

.loaddone
    ; Once the dissolve wipe has begun, keep blitting it to black each frame,
    ; then hand off to the title (see LoadingBeginTitleWipe / LoadingWipeStep).
    tst.w       LoadingWipeActive(a5)
    bne.s       .wipe_out
    ; Post-wash pause, then START the dissolve-to-black wipe (not a direct jump
    ; to TITLE_SETUP).  Dissolving to black first means the cpLoading->cpTitle
    ; copper switch inside TitleSetup lands on an all-black frame, so it is
    ; invisible — the same proven trick the level wipe uses for foreign-copper
    ; entry (LevelTransitionRun .normal_reveal).
    move.w      LoadingMenuTick(a5),d0
    beq.s       .idle                       ; already transitioned (should not normally re-enter)
    subq.w      #1,d0
    move.w      d0,LoadingMenuTick(a5)
    bne.s       .idle                       ; still counting down
    bsr         LoadingBeginTitleWipe       ; decompress overlay + arm the tile wipe
    rts

.wipe_out
    bsr         LoadingWipeStep             ; blit WIPE_SPEED black tiles this frame
    tst.w       d0
    beq.s       .idle                       ; still dissolving — stay in the loading state
    ; DisplayScreen is now fully black: build the title over it.  TitleSetup
    ; installs cpTitle on this black frame (invisible swap) and sets TITLE_RUN.
    clr.w       LoadingWipeActive(a5)
    bsr         TitleSetup
.idle
    rts

;==============================================================================
; LoadingUpdateBorderBars  -  Rebuild the full-width ZX border stripes (per frame)
;
; Regenerates the three border copper blocks — cpLoadingBorderBars (top,
; rasters 1..$2B), cpLoadingBotBars1 ($F5..$FE) and cpLoadingBotBars2
; (256..295) — to mimic a real ZX Spectrum border during tape loading.  Each
; entry is a WAIT + COLOR00 pair with no "off" entry, so every stripe spans
; the full width of the screen.
;
; On entry:
;   d2 = stripe colour A ($0RGB)
;   d3 = stripe colour B ($0RGB)
;   d4 = mode: 0 = pilot tone — even ZX_PILOT_HEIGHT-line bars crawling one
;                               line per frame (LoadingBarPhase)
;              1 = data block — bar heights re-rolled from the LFSR every
;                               frame (1-4 lines): the classic data flicker
;
; The frame-top colour (cpLoadingBorderTop) and the first bottom bar
; (cpLoadingBorderBot, firing at the image end line $F4) are patched to the
; first bar colour of their region so the patterns are seamless.  Entries
; left over once a region is filled are parked at the region end with the
; ongoing bar colour (an invisible write).
;
; Preserves all registers.
;==============================================================================

LoadingUpdateBorderBars:
    PUSHM   d0-d7/a1

    ; Pilot mode: advance the crawl phase once per frame
    tst.w   d4
    bne.s   .no_phase
    move.w  LoadingBarPhase(a5),d5
    addq.w  #1,d5
    and.w   #(ZX_PILOT_HEIGHT*2)-1,d5  ; wrap at one A+B period
    move.w  d5,LoadingBarPhase(a5)
.no_phase

    move.w  d2,-(sp)                   ; pristine colour A (each region restarts
    move.w  d3,-(sp)                   ; from the unswapped pair)

    ; ---- top border: rasters ZX_BAR_FIRST_LINE .. ZX_TOP_END-1 -----------
    bsr     .region_first              ; d1 = first bar height (may swap d2/d3)
    move.w  d2,cpLoadingBorderTop+2    ; frame top = first bar colour
    lea     cpLoadingBorderBars,a1
    move.w  #ZX_BAR_FIRST_LINE,d0
    move.w  #ZX_TOP_END,d6
    move.w  #ZX_NUM_BORDER_BARS,d7
    bsr     .emit_region

    ; ---- bottom border part 1: rasters $F4 .. $FE ------------------------
    move.w  (sp),d3
    move.w  2(sp),d2
    bsr     .region_first
    move.w  d2,cpLoadingBorderBot+2    ; bar 0 fires at $F4 via cpLoadingImageEnd
    exg     d2,d3
    move.w  #ZX_BOT_FIRST_LINE,d0
    add.w   d1,d0                      ; first block entry = second bar boundary
    bsr     .next_height
    lea     cpLoadingBotBars1,a1
    move.w  #ZX_BOT1_END,d6
    move.w  #ZX_NUM_BOT1_BARS,d7
    bsr     .emit_region

    ; ---- bottom border part 2: rasters 256 .. 287 -------------------------
    ; DISABLED: the bottom border currently ends at raster 254 (short strip).
    ; Re-enable together with the cpLoadingBotBars2 block in copperlists.asm.
 ;   move.w  (sp),d3
 ;   move.w  2(sp),d2
 ;   bsr     .region_first
 ;   lea     cpLoadingBotBars2,a1
 ;   moveq   #0,d0                      ; V byte 0 = raster line 256
 ;   move.w  #ZX_BOT_END,d6
 ;   move.w  #ZX_NUM_BOT2_BARS,d7
 ;   bsr     .emit_region

    addq.l  #4,sp
    POPM    d0-d7/a1
    rts

    ;--------------------------------------------------------------------------
    ; .region_first — height of a region's first bar (and colour phase select)
    ; Pilot: derived from LoadingBarPhase so the bars crawl; swaps d2/d3 when
    ; the phase is in the second half of the A+B period.  Data: LFSR roll.
    ;--------------------------------------------------------------------------
.region_first
    tst.w   d4
    bne.s   .rand_height               ; data mode: d1 = 1..4 (tail call)
    move.w  LoadingBarPhase(a5),d5
    cmp.w   #ZX_PILOT_HEIGHT,d5
    blt.s   .rf_no_swap
    exg     d2,d3                      ; second half of period: start on colour B
.rf_no_swap
    move.w  d5,d1
    and.w   #ZX_PILOT_HEIGHT-1,d1
    neg.w   d1
    add.w   #ZX_PILOT_HEIGHT,d1        ; first bar: HEIGHT - (phase mod HEIGHT)
    rts

    ;--------------------------------------------------------------------------
    ; .next_height — height of a follow-on bar (pilot: fixed; data: LFSR)
    ;--------------------------------------------------------------------------
.next_height
    tst.w   d4
    bne.s   .rand_height               ; data mode (tail call)
    moveq   #ZX_PILOT_HEIGHT,d1
    rts

    ;--------------------------------------------------------------------------
    ; .emit_region — fill one copper block with alternating bars
    ;   a1 = first entry, d0 = start line (V byte), d6 = region end (exclusive),
    ;   d7 = entry count, d1 = first bar height, d2/d3 = colours (alternated)
    ; Leftover entries are parked at the region end line with the ongoing bar
    ; colour, which makes the parked writes invisible.
    ;--------------------------------------------------------------------------
.emit_region
    move.b  d0,(a1)                    ; WAIT Y = bar start (full width: no off entry)
    move.w  d2,6(a1)                   ; stripe colour
    exg     d2,d3                      ; alternate colours for the next bar
    addq.l  #8,a1
    add.w   d1,d0                      ; next bar boundary
    subq.w  #1,d7
    beq.s   .er_done                   ; block full: last bar runs to the region end
    cmp.w   d6,d0
    bcc.s   .er_park                   ; region filled: park the leftover entries
    bsr     .next_height
    bra.s   .emit_region

.er_park
    move.b  d6,(a1)                    ; park at the region end line...
    move.w  d3,6(a1)                   ; ...rewriting the ongoing colour (invisible)
    addq.l  #8,a1
    subq.w  #1,d7
    bne.s   .er_park
.er_done
    rts

    ;--------------------------------------------------------------------------
    ; .rand_height — roll the next data-mode bar height (1..4 scanlines)
    ;--------------------------------------------------------------------------
.rand_height
    move.l  RandomSeed(a5),d5
    lsr.l   #1,d5
    bcc.s   .rh_no_fb
    eor.l   #$B4BCD35C,d5              ; Galois LFSR feedback polynomial
.rh_no_fb
    move.l  d5,RandomSeed(a5)
    moveq   #3,d1
    and.w   d5,d1
    addq.w  #1,d1                      ; d1 = 1..4 scanlines
    rts


;==============================================================================
; LoadingBorderBarsOff  -  Park all border stripe blocks (border goes black)
;
; Blacks cpLoadingBorderTop/Bot and parks every entry of the three bar blocks
; at its region end with a black colour — the parked writes fire harmlessly
; outside the pattern.  Called when the tape audio stops (inter-block gap,
; end of the colour wash, LoadingSwapPalette).
;==============================================================================

LoadingBorderBarsOff:
    PUSHM   d0/d7/a0
    move.w  #ZX_BORDER_DONE,cpLoadingBorderTop+2
    move.w  #ZX_BORDER_DONE,cpLoadingBorderBot+2
    lea     cpLoadingBorderBars,a0
    move.w  #ZX_NUM_BORDER_BARS,d7
    moveq   #ZX_TOP_END,d0
    bsr.s   .park_block
    lea     cpLoadingBotBars1,a0
    move.w  #ZX_NUM_BOT1_BARS,d7
    move.w  #ZX_BOT1_END,d0
    bsr.s   .park_block
 ;   lea     cpLoadingBotBars2,a0
 ;   move.w  #ZX_NUM_BOT2_BARS,d7
 ;   move.w  #ZX_BOT_END,d0
 ;   bsr.s   .park_block
    POPM    d0/d7/a0
    rts

.park_block
    move.b  d0,(a0)
    move.w  #ZX_BORDER_DONE,6(a0)
    addq.l  #8,a0
    subq.w  #1,d7
    bne.s   .park_block
    rts


;==============================================================================
; LoadingLoadStepRun  -  Advance the ZX Spectrum screen-load by one step
;
; Steps 0-63 (main): reveal 3 rows simultaneously (top/mid/bot sections).
; Steps 64-71 (tail): reveal rows 192-199 one at a time.
; When all ZX_STEPS_TOTAL steps are done, calls LoadingSwapPalette.
;
; ZX row order per step s (0..63):
;   block          = s >> 3
;   pass           = s & 7
;   in_section_row = pass*8 + block
;   top row = in_section_row
;   mid row = 64  + in_section_row
;   bot row = 128 + in_section_row
;==============================================================================

LoadingLoadStepRun:
    PUSHALL

    move.w  LoadingLoadStep(a5),d0

    cmp.w   #ZX_SECTION_ROWS*3,d0
    bcc     .tail

    ; Main ZX steps (0..191): one section at a time, ZX row order within each.
    ; ZX_SECTION_ROWS=64 (power of 2), so:
    ;   section        = step >> 6           (0=top, 1=mid, 2=bot)
    ;   step_in_section= step & 63           (0..63)
    ;   block          = step_in_section >> 3
    ;   pass           = step_in_section & 7
    ;   in_section_row = pass*8 + block      (ZX attribute-block order)
    ;   absolute_row   = section*64 + in_section_row
    move.w  d0,d1
    lsr.w   #6,d1                   ; d1 = section (0/1/2)
    move.w  d0,d2
    and.w   #ZX_SECTION_ROWS-1,d2  ; d2 = step within section (0..63)

    move.w  d2,d3
    lsr.w   #3,d3                   ; d3 = block
    move.w  d2,d4
    and.w   #7,d4                   ; d4 = pass
    lsl.w   #3,d4                   ; d4 = pass * 8
    add.w   d3,d4                   ; d4 = in_section_row

    lsl.w   #6,d1                   ; d1 = section * 64
    add.w   d1,d4                   ; d4 = absolute row (0..191)

    move.w  d4,d3
    bsr     LoadingCopyRow
    bra     .advance

.tail
    ; Tail steps (192..199): step number equals row number directly
    move.w  d0,d3
    bsr     LoadingCopyRow

.advance
    addq.w  #1,LoadingLoadStep(a5)
    move.w  LoadingLoadStep(a5),d0
    cmp.w   #ZX_STEPS_TOTAL,d0
    bcs     .notdone
    bsr     LoadingSwapPalette        ; all rows loaded: switch to full colour

.notdone
    POPALL
    rts


;==============================================================================
; LoadingCopyRow  -  Copy one interleaved row from NonDisplayScreen into DisplayScreen
;
; On entry: d3.w = row number (0..LOADING_HEIGHT-1)
; Trashes:  d1, a0, a1  (caller must preserve via PUSHALL)
;
; NonDisplayScreen holds the decompressed title graphic (placed there by LoadingSetup).
; NonDisplayScreen and DisplayScreen share the same 40-byte-per-plane-per-row layout,
; so the byte offset and copy length are identical for source and destination.
;==============================================================================

LoadingCopyRow:
    move.w  d3,d1
    muls    #LOADING_ROW_BYTES,d1    ; d1 = byte offset for this row
    lea     NonDisplayScreen,a0
    add.l   d1,a0                  ; a0 -> source row in NonDisplayScreen (decompressed)
    lea     DisplayScreen,a1
    add.l   d1,a1                  ; a1 -> destination row in DisplayScreen
    move.w  #LOADING_ROW_BYTES/2-1,d1  ; 105 words = 210 bytes (not divisible by 4)
.copy
    move.w  (a0)+,(a1)+
    dbra    d1,.copy
    rts


;==============================================================================
; LoadingSwapPalette  -  Replace B&W copper palette with full-colour LoadingPal
;
; Called once by LoadingLoadStepRun when ZX animation finishes.
; Writes all 32 LoadingPal entries into the cpLoadingPal copper list section.
;==============================================================================

LoadingSwapPalette:
    bsr     LoadingAudioStop          ; data-load complete — silence channel 0 before palette swap

    ; Write full colour palette into cpLoadingPal (fires at top of every frame).
    ; This writes LoadingPal[0] into cpLoadingBorderTop (COLOR00), which we then
    ; override with the static border colour below.
    lea     LoadingPal,a0
    lea     cpLoadingPal,a1
    moveq   #32-1,d7
.pal
    move.w  (a0)+,2(a1)
    addq.l  #4,a1
    dbra    d7,.pal

    ; Park the border stripe blocks and black the border colours — the wash
    ; phase re-enables the bars each frame while its audio plays.
    bsr     LoadingBorderBarsOff

    ; Initialise colour wash: WAIT Y at top of display, counter at 0
    clr.w   LoadingWashLine(a5)
    lea     cpLoadingWash,a0
    move.b  #WINDOW_Y_START,(a0)   ; patch WAIT Y to first visible raster line
    rts


;==============================================================================
; LoadingWashRun  -  Advance the copper-based colour wash by ZX_WASH_SPEED lines
;
; The copper list has two palette sections:
;   cpLoadingPal  - full colour, fires at the start of every frame
;   cpLoadingWash - greyscale,  fires at a scan line that moves down each frame
;
; Lines above the WAIT in cpLoadingWash show the full colour palette.
; Lines at and below the WAIT revert to greyscale.
; As LoadingWashLine advances from 0 to LOADING_HEIGHT, the colour region grows
; from zero lines to the full screen, revealing the image top-to-bottom.
;
; When LoadingWashLine reaches LOADING_HEIGHT, the WAIT is pushed off-screen ($FF)
; so the greyscale palette is never applied and the whole frame shows colour.
;==============================================================================

LoadingWashRun:
    move.w  LoadingWashLine(a5),d0
    add.w   #ZX_WASH_SPEED,d0
    move.w  d0,LoadingWashLine(a5)

    lea     cpLoadingWash,a0
    cmp.w   #LOADING_HEIGHT,d0
    bcc     .done

    ; Patch WAIT Y: raster line = WINDOW_Y_START + LoadingWashLine
    add.b   #WINDOW_Y_START,d0    ; byte add: max = $2C+198 = $F2, no overflow
    move.b  d0,(a0)               ; write new Y into high byte of WAIT word
    rts

.done
    move.b  #$ff,(a0)                           ; push WAIT off-screen: full frame shows colour
    bsr     LoadingAudioStop                    ; silence ZX colour-wash SFX
    bsr     LoadingBorderBarsOff                ; audio stopped -> border goes static black
    move.w  #MENU_PAUSE_FRAMES,d0
    bsr     ScalePALFrames                      ; keep real-time length on NTSC
    move.w  d0,LoadingMenuTick(a5)              ; arm post-wash pause before title transition
    rts

;==============================================================================
; LoadingScreenNameAudioStart  -  Play screenname intro audio via PTPlayer SFX
;
; Starts ZxAudioScreenName_PCM as a looped SFX on channel 0 using _mt_loopfx.
; The channel loops until LoadingAudioStop calls _mt_stopfx after SCREENNAME_FRAMES.
; Using _mt_loopfx means the stop is always clean regardless of where in the
; sample the tick fires — no reliance on tick/sample-length alignment.
;
; Called once from LoadingSetup.  Requires AudioInit to have been called first.
;==============================================================================

LoadingScreenNameAudioStart:
    PUSHALL
    lea     ZxSfxScreenName,a0
    jsr     _mt_loopfx
    POPALL
    rts


;==============================================================================
; LoadingAudioStart  -  Begin ZX tape-load audio via PTPlayer SFX
;
; Starts ZxAudioDataLoad_PCM as a looped SFX on channel 0.  _mt_loopfx
; replaces any previously looping effect on the same channel, so no explicit
; stop is needed between the screenname and data-load phases.
;
; Called from LoadingRun when LoadingIntroTick expires (end of screenname intro).
;==============================================================================

LoadingAudioStart:
    PUSHALL
    lea     ZxSfxDataLoad,a0
    jsr     _mt_loopfx
    POPALL
    rts


;==============================================================================
; LoadingAudioStop  -  Stop the ZX audio SFX on channel 0
;
; Calls _mt_stopfx which immediately idles channel 0 on the leading zero-word
; of the sample buffer.  Called at the end of each ZX title audio phase.
;==============================================================================

LoadingAudioStop:
    PUSHALL
    moveq   #0,d0               ; channel 0
    jsr     _mt_stopfx
    POPALL
    rts


;==============================================================================
; LoadingColorAudioStart  -  Begin colour-wash audio via PTPlayer SFX
;
; Starts ZxAudioColorLoad_PCM as a looped SFX on channel 0.  _mt_loopfx
; replaces the data-load SFX directly without needing an explicit stop first.
;
; Called from LoadingSwapPalette as the screen-load animation finishes.
;==============================================================================

LoadingColorAudioStart:
    PUSHALL
    lea     ZxSfxColorLoad,a0
    jsr     _mt_loopfx
    POPALL
    rts



;==============================================================================
; LoadingSkipAnimation  -  Instantly complete ZX load + wash, go to title screen
;
; Called when F6 is pressed during any animation phase (intro/load/wash).
; Copies the full LoadingRaw image to DisplayScreen, switches to the full-colour
; palette (via LoadingSwapPalette), marks the wash as done, then arms the
; dissolve-to-black wipe into the title (LoadingBeginTitleWipe) instead of
; jumping straight to TITLE_SETUP.  Skipping therefore takes the identical
; clean transition as waiting — the loading image dissolves to black and the
; title is built over the black frame.
;==============================================================================

LoadingSkipAnimation:
    PUSHALL

    bsr     LoadingAudioStop

    clr.w   LoadingIntroTick(a5)
    move.w  #ZX_STEPS_TOTAL,LoadingLoadStep(a5)

    lea     NonDisplayScreen,a0
    lea     DisplayScreen,a1
    move.w  #(LOADING_ROW_BYTES*LOADING_HEIGHT/4)-1,d0
.copy
    move.l  (a0)+,(a1)+
    dbra    d0,.copy

    bsr     LoadingSwapPalette

    move.w  #LOADING_HEIGHT,LoadingWashLine(a5)   ; mark wash complete: LoadingRun routes to .loaddone
    lea     cpLoadingWash,a0
    move.b  #$ff,(a0)

    bsr     LoadingBeginTitleWipe   ; overlay decompress + arm the dissolve-to-black wipe

    POPALL
    rts


;==============================================================================
; CopyOverlayAssets  -  Decompress post-loading assets into Chip RAM
;
; Decompresses the player hardware sprites from their ZX0-compressed Fast RAM
; source into the PlayerHWSprites chip buffer.  Runs in the mainline, so the
; multi-frame decompression is harmless (interrupts keep running).
;
; Called from both LoadingRun transition paths immediately before TITLE_SETUP.
;==============================================================================

CopyOverlayAssets:
    ; Player converted to Blitter Object (BOB) stored directly in Chip RAM (PlayerRaw/Msk).
    ; No hardware sprite decompression needed.
    rts


;==============================================================================
; LoadingBeginTitleWipe  -  Arm the dissolve-to-black wipe into the title screen
;
; Called once when the loading screen finishes (normal completion or F6 skip),
; instead of jumping straight to TITLE_SETUP.  Decompresses the post-loading
; overlay assets (while the image is still up), fills the tile wipe order and
; resets the tile counter, then flags the wipe active.  From the next frame
; LoadingRun (.wipe_out) blits WIPE_SPEED black tiles until the whole
; DisplayScreen is black, at which point TitleSetup builds the title over the
; black frame — so the cpLoading->cpTitle switch is invisible.  This reuses the
; level-transition wipe machinery (WipeFillTopBottom / WipeBlitBlack in
; mapstuff.asm), which is the transition we already know renders cleanly.
;==============================================================================

LoadingBeginTitleWipe:
    PUSHALL
    bsr     CopyOverlayAssets       ; decompress player sprites before the screen goes black
    bsr     WipeFillTopBottom       ; fill WipeTileX/Y with a top-to-bottom tile order
    clr.w   WipeTilesDone(a5)       ; no tiles blitted black yet
    move.w  #1,LoadingWipeActive(a5)
    POPALL
    rts


;==============================================================================
; LoadingWipeStep  -  Dissolve one WIPE_SPEED batch of tiles to black
;
; Blits up to WIPE_SPEED 24x24 tiles black on DisplayScreen this frame, in the
; order held in WipeTileX/Y, advancing WipeTilesDone.  Reuses WipeBlitBlack
; (mapstuff.asm) exactly as the level wipe does.
;
; OUT: d0.w = 0 while tiles remain, 1 once the whole screen is black.
; All other registers preserved.
;==============================================================================

LoadingWipeStep:
    PUSHM   d1-d7/a0-a1
    move.w  WipeTilesDone(a5),d7
    cmp.w   #WALL_PAPER_SIZE,d7
    bge     .done

    moveq   #WIPE_SPEED-1,d6
.loop
    cmp.w   #WALL_PAPER_SIZE,d7
    bge     .batch_done
    moveq   #0,d0
    lea     WipeTileX(a5),a0
    move.b  (a0,d7.w),d0            ; tile X (0..13)
    moveq   #0,d1
    lea     WipeTileY(a5),a0
    move.b  (a0,d7.w),d1            ; tile Y (0..8)
    bsr     WipeBlitBlack           ; zero-fill this 24x24 tile (black)
    addq.w  #1,d7
    dbra    d6,.loop

.batch_done
    move.w  d7,WipeTilesDone(a5)
    cmp.w   #WALL_PAPER_SIZE,d7
    bge     .done
    moveq   #0,d0                   ; more tiles remain
    bra.s   .exit
.done
    moveq   #1,d0                   ; screen fully black
.exit
    POPM    d1-d7/a0-a1
    rts

