;==============================================================================
; AMIGA GAME ENGINE
; loading.asm  -  Loading Screen Setup and Animation
;==============================================================================
;
; Handles game states 0 (LoadingSetup) and 1 (LoadingRun).
;
; The loading screen uses a full-screen DisplayScreen buffer (5-plane interleaved,
; 320x200 pixels).  The ZX Spectrum tape-load animation reveals the image row by row,
; followed by a top-to-bottom colour wash via a copper WAIT that advances each frame.
;
;==============================================================================

;------------------------------------------------------------------------------
; Loading screen geometry constants (320x200)
;------------------------------------------------------------------------------
    IFND LOADING_WIDTH
LOADING_WIDTH             = 320                           ; pixel width (standard 320px Amiga lo-res)
    ENDC
    IFND LOADING_WIDTH_BYTE
LOADING_WIDTH_BYTE        = LOADING_WIDTH/8               ; bytes per row per plane = 40
    ENDC
    IFND LOADING_DEPTH
LOADING_DEPTH             = 5                             ; bitplanes = 32 colours
    ENDC
    IFND LOADING_HEIGHT
LOADING_HEIGHT            = 200                           ; pixel height
    ENDC
    IFND LOADING_WINDOW_START
LOADING_WINDOW_START      = (WINDOW_Y_START<<8)|$81       ; DIWSTRT: V=44, H=$81
    ENDC
    IFND LOADING_WINDOW_STOP
LOADING_WINDOW_STOP       = ($F4<<8)|WINDOW_X_STOP        ; DIWSTOP: V=244, H=$C1 (200 lines)
    ENDC
    IFND LOADING_FETCH_START
LOADING_FETCH_START       = $38                           ; $38 - standard for H=$81, 320px
    ENDC
    IFND LOADING_FETCH_STOP
LOADING_FETCH_STOP        = FETCH_STOP                    ; $D0
    ENDC
    IFND LOADING_MOD
LOADING_MOD               = LOADING_WIDTH_BYTE*(LOADING_DEPTH-1)   ; BPLxMOD = 40*4 = 160
    ENDC
    IFND LOADING_ROW_BYTES
LOADING_ROW_BYTES         = LOADING_DEPTH*LOADING_WIDTH_BYTE        ; bytes per interleaved row = 200
    ENDC
    IFND ZX_LOAD_SPEED
ZX_LOAD_SPEED           = 2             ; frames per ZX step (must be power of 2)
    ENDC
    IFND ZX_SECTION_ROWS
ZX_SECTION_ROWS         = 64            ; rows per ZX section (top/mid/bottom)
    ENDC
    IFND ZX_TAIL_ROWS
ZX_TAIL_ROWS            = LOADING_HEIGHT-(ZX_SECTION_ROWS*3)   ; extra rows beyond 3 sections = 8
    ENDC
    IFND ZX_STEPS_TOTAL
ZX_STEPS_TOTAL          = ZX_SECTION_ROWS*3+ZX_TAIL_ROWS      ; total animation steps = 200
    ENDC
    IFND ZX_WASH_FRAMES
ZX_WASH_FRAMES          = 59            ; colour wash length = zx_audio_colors (9434 bytes)
    ENDC

; ZX Spectrum-style border stripes.
; The top border (rasters 0..39) AND a short bottom strip (rasters $F4..$FE;
; the full-height part 2 covering rasters 256-287 is currently commented out)
; are rebuilt EVERY frame by LoadingUpdateBorderBars into the
; cpLoadingBorderBars / cpLoadingBotBars1 copper blocks.  Each entry is a
; full-width WAIT + COLOR00 pair — the colour holds across the whole scanline
; until the next entry, exactly like a real Spectrum border:
;
;   pilot tone:        red/cyan bars, ZX_PILOT_HEIGHT lines each, crawling one
;                      line per frame (the steady leader tone before a block)
;   header burst:      a brief yellow/blue flicker — the header's own data bytes
;   inter-block gap:   tape silence — audio stopped, border static black
;   data load:         yellow/blue bars with random 1-4 line heights,
;                      regenerated every frame (the data-block flicker)
;
; ZX_NUM_BORDER_BARS entries cover the 40-line top border; entries left over
; in a frame are parked at the region end, where a static terminator entry
; sets COLOR00 back to black anyway.
    IFND ZX_BORDER_A
ZX_BORDER_A             = $00f          ; data stripes: bright blue
    ENDC
    IFND ZX_BORDER_B
ZX_BORDER_B             = $ff0          ; data stripes: bright yellow
    ENDC
    IFND ZX_PILOT_A
ZX_PILOT_A              = $f00          ; pilot stripes: bright red
    ENDC
    IFND ZX_PILOT_B
ZX_PILOT_B              = $0ff          ; pilot stripes: bright cyan
    ENDC
    IFND ZX_BORDER_DONE
ZX_BORDER_DONE          = $000          ; black (static border after load completes)
    ENDC
    IFND ZX_NUM_BORDER_BARS
ZX_NUM_BORDER_BARS      = 24            ; copper entries in cpLoadingBorderBars (top)
    ENDC
    IFND ZX_BAR_FIRST_LINE
ZX_BAR_FIRST_LINE       = 1             ; first patchable raster line of the top border
    ENDC
    IFND ZX_TOP_END
ZX_TOP_END              = 40            ; top bars cover rasters 0-39; a static
    ENDC
    IFND ZX_PILOT_HEIGHT
ZX_PILOT_HEIGHT         = 4             ; scanlines per pilot bar (must be a power of 2)
    ENDC
ZX_NUM_BOT1_BARS        = 6             ; bottom entries for raster lines 245-254
ZX_NUM_BOT2_BARS        = 14            ; bottom entries for raster lines 256-287
ZX_BOT_FIRST_LINE       = $F4           ; bottom border starts where the image ends
ZX_BOT1_END             = $FF           ; part 1 ends at the 8-bit raster wrap
; The bottom border is exactly as tall as the top one (WINDOW_Y_START = 44
; lines): rasters 244..287.  A static terminator entry in the copper list
; (after cpLoadingBotBars2) sets COLOR00 back to black at this line.
ZX_BOT_END              = (ZX_BOT_FIRST_LINE+WINDOW_Y_START)-256   ; V byte $20 = raster 288
; Tape phases before the data block.  The lengths (logic ticks, the same real
; time on PAL and NTSC) come from the original tape recording, so the border bars
; and the audio change on the same frame.  LoadingTapePhase holds the current
; phase and LoadingIntroTick the frames left in it.
TAPE_PILOT1             = 0             ; header leader: pilot tone, red/cyan bars
TAPE_HEADER             = 1             ; header data burst: yellow/blue flicker
TAPE_GAP                = 2             ; tape silence: no audio, black border
TAPE_PILOT2             = 3             ; data-block leader: pilot tone again
TAPE_DATA               = 4             ; data block: row reveal (no timer)
ZX_PILOT1_FRAMES        = 63            ; header pilot tone
ZX_HEADER_DATA_FRAMES   = 5             ; header data burst (zx_audio_header, 800 bytes)
ZX_GAP_FRAMES           = 49            ; tape silence between header and data block
ZX_PILOT2_FRAMES        = 51            ; data-block pilot tone

; Pause between colour-wash completion and title screen transition.
; In logic ticks, so the real-time duration is the same on PAL and NTSC.
MENU_PAUSE_FRAMES    = 75                           ; ~1.5 seconds

; ZX tape-load audio: Paula channel 0 direct PCM playback
; All samples are 8-bit signed mono at 8000 Hz.
; Every sample is played with _mt_loopfx and stopped (or replaced) by LoadingRun
; at the end of its phase.  At 8000 Hz one PAL frame is 160 samples.
; PAL: AUD0PER = 3,546,895 / 8000 = 443
ZX_AUDIO_PERIOD         = 443           ; Paula period for 8000 Hz playback (PAL)
ZX_AUDIO_VOL            = 40            ; Paula channel 0 volume (0-64)

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
;   4. Enable DMA (BASE_DMA).
;   5. Advance GameStatus to LoadingRun (1).
;   6. Decompress LoadingRawZ (ZX0-compressed loading image) into NonDisplayScreen,
;      which serves as the decompression staging buffer (unused at this phase).
;      This runs in the mainline (MainLoop), so taking several frames is
;      harmless — interrupts (keyboard, music) keep running throughout.
;      LoadingCopyRow and LoadingSkipAnimation then copy rows from NonDisplayScreen
;      into DisplayScreen as the ZX animation reveals the image progressively.
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
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

 ;   move.w      #BASE_DMA,DMACON(a6)   ; enable Copper + Blitter + Bitplane + Sprite DMA

    addq.w      #GAME_LOADING,GameStatus(a5)      ; advance to state 1 (LoadingRun)

    ; Decompress ZX0 title graphic into NonDisplayScreen (40,000-byte image into the 81,920-byte buffer).
    lea        LoadingRawZ,a0
    lea        NonDisplayScreen,a1
    bsr        zx0_decompress

    bsr        LoadingStageAudio      ; stage tape audio into NonDisplayScreen+40000

    ; Reset ZX load step counter and border-bar state.  RandomSeed drives the
    ; data-phase bar heights and must be non-zero (a Galois LFSR sticks at 0).
    clr.w       LoadingLoadStep(a5)
    clr.w       LoadingBarPhase(a5)
    move.l      #$B4BCD35C,RandomSeed(a5)
    clr.w       LoadingMenuTick(a5)                       ; post-wash pause not yet armed

    ; Start the tape at its first phase: the header's pilot tone.  The first
    ; LoadingRun frame draws the matching red/cyan bars.
    move.w      #TAPE_PILOT1,LoadingTapePhase(a5)
    move.w      #ZX_PILOT1_FRAMES,d0
    move.w      d0,LoadingIntroTick(a5)                   ; frames left in this phase
    lea         ZxSfxPilot,a0
    bsr         LoadingPlayLoop

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
;
; Destroys: d0-d1/d7/a0 (preserves everything else, including a5/a6)
;==============================================================================

LoadingCopperSetup:
;    bsr         ClearSprites           ; hide all hardware sprites

    ; Patch bitplane pointers in the loading copper list.  The five planes of
    ; DisplayScreen are interleaved LOADING_WIDTH_BYTE (40) bytes apart.
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
;   TAPE_PILOT1  header pilot tone      red/cyan bars       (pilot loop)
;   TAPE_HEADER  header data burst      yellow/blue flicker (header burst)
;   TAPE_GAP     tape silence           static black border (no audio)
;   TAPE_PILOT2  data-block pilot tone  red/cyan bars       (pilot loop)
;   TAPE_DATA    row reveal             yellow/blue flicker (data loop)
;   colour wash  top-to-bottom colour   yellow/blue flicker (colour sample)
;
; Each phase switches its audio and its border bars on the same frame, and
; the border stripes run exactly while tape audio is playing.
;
; F6 at any point skips the remaining animation and jumps straight to the
; title screen (LoadingSkipAnimation).
;
; Destroys: d0-d7/a0-a4 (preserves everything else, including a5/a6)
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
    ; Tape phases before the data block.  A phase whose countdown reached zero
    ; on the previous frame is replaced here, before this frame's bars are
    ; drawn, so the new audio and the new bars start on the same frame.
    cmp.w       #TAPE_DATA,LoadingTapePhase(a5)
    bcc.s       .loadphase
    tst.w       LoadingIntroTick(a5)
    bne.s       .tape_frame
    bsr         LoadingTapeNextPhase    ; next phase: audio, timer, border state
    cmp.w       #TAPE_DATA,LoadingTapePhase(a5)
    bcc.s       .loadphase              ; data block starts this frame

.tape_frame
    move.w      LoadingTapePhase(a5),d0
    cmp.w       #TAPE_GAP,d0
    beq.s       .tape_tick              ; silence: border stays black
    cmp.w       #TAPE_HEADER,d0
    beq.s       .tape_burst
    move.w      #ZX_PILOT_A,d2          ; pilot tone: red
    move.w      #ZX_PILOT_B,d3          ; cyan
    moveq       #0,d4                   ; mode 0: even bars, slow crawl
    bra.s       .tape_bars
.tape_burst
    move.w      #ZX_BORDER_B,d2         ; header data: yellow
    move.w      #ZX_BORDER_A,d3         ; blue
    moveq       #1,d4                   ; mode 1: random flickering bars
.tape_bars
    bsr         LoadingUpdateBorderBars
.tape_tick
    subq.w      #1,LoadingIntroTick(a5)
    rts

.loadphase
    ; Data block: ZX screen-load animation with the data-block border, yellow/
    ; blue bars with random heights re-rolled every frame (the ZX data flicker).
    ; LoadingIntroTick counts the frames of this phase so the first row is
    ; revealed on the same frame the data audio starts.
    move.w      LoadingLoadStep(a5),d0
    cmp.w       #ZX_STEPS_TOTAL,d0
    bcc         .washphase

    move.w      #ZX_BORDER_B,d2         ; yellow
    move.w      #ZX_BORDER_A,d3         ; blue
    moveq       #1,d4                   ; mode 1: random flickering bars
    bsr         LoadingUpdateBorderBars

    move.w      LoadingIntroTick(a5),d0
    addq.w      #1,LoadingIntroTick(a5)
    and.w       #ZX_LOAD_SPEED-1,d0   ; step every ZX_LOAD_SPEED frames, from the first
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
    lea         ZxSfxColorLoad,a0         ; first wash frame: start colour-load audio
    bsr         LoadingPlayLoop
.wash_run
    move.w      #ZX_BORDER_B,d2           ; audio playing -> bars stay on
    move.w      #ZX_BORDER_A,d3
    moveq       #1,d4
    bsr         LoadingUpdateBorderBars
    bsr         LoadingWashRun            ; advance WAIT Y in cpLoadingWash
    rts

.loaddone
    IFD LOADING_NO_TITLE_WIPE
    move.w      LoadingMenuTick(a5),d0
    beq.s       .idle
    subq.w      #1,d0
    move.w      d0,LoadingMenuTick(a5)
    bne.s       .idle
    IFD LOADING_OVERLAY_HOOK
    jsr         LOADING_OVERLAY_HOOK
    ENDC
    move.w      #TITLE_SETUP,GameStatus(a5)
    rts
    ELSE
    ; Once the dissolve wipe has begun, keep blitting it to black each frame,
    ; then hand off to the title (see LoadingBeginTitleWipe / LoadingWipeStep).
    tst.w       LoadingWipeActive(a5)
    bne.s       .wipe_out
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
    beq.s       .idle                       ; still dissolving - stay in the loading state
    clr.w       LoadingWipeActive(a5)
    IFD LOADING_OVERLAY_HOOK
    jsr         LOADING_OVERLAY_HOOK
    ENDC
    bsr         TitleSetup
    ENDC
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
; In:  d2.w = Color A, d3.w = Color B, d4.w = mode flag
; Out: none
; Destroys: none (preserves all registers)
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
;
; Destroys: none (preserves all registers)
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
;
; Destroys: none (preserves all registers)
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
; NonDisplayScreen holds the decompressed title graphic (placed there by LoadingSetup).
; NonDisplayScreen and DisplayScreen share the same 40-byte-per-plane-per-row layout,
; so the byte offset and copy length are identical for source and destination.
;
; In:  d3.w = row index to copy
; Out: none
; Destroys: d1, a0, a1 (caller must preserve via PUSHALL)
;==============================================================================

LoadingCopyRow:
    move.w  d3,d1
    muls    #LOADING_ROW_BYTES,d1    ; d1 = byte offset for this row
    lea     NonDisplayScreen,a0
    add.l   d1,a0                  ; a0 -> source row in NonDisplayScreen (decompressed)
    lea     DisplayScreen,a1
    add.l   d1,a1                  ; a1 -> destination row in DisplayScreen
    move.w  #LOADING_ROW_BYTES/2-1,d1  ; 100 words = 200 bytes (5 planes x 40 bytes)
.copy
    move.w  (a0)+,(a1)+
    dbra    d1,.copy
    rts


;==============================================================================
; LoadingSwapPalette  -  Replace B&W copper palette with full-colour LoadingPal
;
; Called once by LoadingLoadStepRun when ZX animation finishes.
; Writes all 32 LoadingPal entries into the cpLoadingPal copper list section.
;
; Destroys: d0/d7/a0-a1 (preserves everything else, including a5/a6)
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

    ; Initialise colour wash: WAIT Y at top of display, line and frame counters at 0
    clr.w   LoadingWashLine(a5)
    clr.w   LoadingIntroTick(a5)          ; wash frame counter (LoadingWashRun)
    lea     cpLoadingWash,a0
    move.b  #WINDOW_Y_START,(a0)   ; patch WAIT Y to first visible raster line
    rts


;==============================================================================
; LoadingWashRun  -  Advance the copper-based colour wash by one frame
;
; The wash takes exactly ZX_WASH_FRAMES frames, the length of the colour-load
; sample, so the sound ends on the frame the wash completes.  Frame n of the
; wash (1..ZX_WASH_FRAMES) shows colour down to line n*LOADING_HEIGHT/ZX_WASH_FRAMES.
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
;
; Destroys: d0/a0 (preserves everything else, including a5/a6)
;==============================================================================

LoadingWashRun:
    addq.w  #1,LoadingIntroTick(a5)       ; wash frame 1..ZX_WASH_FRAMES
    moveq   #0,d0
    move.w  LoadingIntroTick(a5),d0
    mulu    #LOADING_HEIGHT,d0
    divu    #ZX_WASH_FRAMES,d0            ; d0.w = colour line for this frame
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
    move.w  d0,LoadingMenuTick(a5)              ; arm post-wash pause before title transition
    rts

;==============================================================================
; LoadingStageAudio  -  Stage the ZX loader PCM samples into Chip RAM
;
; The tape samples (21,104 bytes) live in Fast RAM (zxsfx.asm in data_fast) to
; save Chip RAM.  During LoadingSetup this routine copies the contiguous block
; (ZxAudioDataLoad_SFXBase .. ZxAudioPilot_PCMEnd) into NonDisplayScreen at
; LOADING_AUDIO_STAGE_OFFSET, just past the 40,000-byte decompressed loading
; image, and patches the sfx_ptr of each ZxSfx structure to its staged copy.
; Image plus audio take 61,104 of NonDisplayScreen's 81,920 bytes.  When
; gameplay begins, NonDisplayScreen is reused for tile rendering.  Assembled
; out (plain rts) when LOADING_AUDIO_IN_CHIP is defined.
;
; Destroys: none (preserves all registers)
;==============================================================================

LOADING_AUDIO_STAGE_OFFSET = LOADING_ROW_BYTES*LOADING_HEIGHT   ; 40,000 bytes
LOADING_AUDIO_BYTES        = ZxAudioPilot_PCMEnd-ZxAudioDataLoad_SFXBase

; (zxsfx.asm checks at assembly time that the samples fit in NonDisplayScreen.)

LoadingStageAudio:
    IFND LOADING_AUDIO_IN_CHIP
    PUSHALL

    ; Copy the contiguous PCM block (every sample is an even length) word by word
    lea     ZxAudioDataLoad_SFXBase,a0
    lea     NonDisplayScreen+LOADING_AUDIO_STAGE_OFFSET,a1
    move.w  #(LOADING_AUDIO_BYTES/2)-1,d0
.lsa_copy:
    move.w  (a0)+,(a1)+
    dbra    d0,.lsa_copy

    ; Patch sfx_ptr in each ZxSfx structure to its staged Chip RAM address
    lea     NonDisplayScreen+LOADING_AUDIO_STAGE_OFFSET,a0
    move.l  a0,ZxSfxDataLoad
    add.l   #(ZxAudioColorLoad_SFXBase-ZxAudioDataLoad_SFXBase),a0
    move.l  a0,ZxSfxColorLoad
    add.l   #(ZxAudioHeader_SFXBase-ZxAudioColorLoad_SFXBase),a0
    move.l  a0,ZxSfxHeader
    add.l   #(ZxAudioPilot_SFXBase-ZxAudioHeader_SFXBase),a0
    move.l  a0,ZxSfxPilot

    POPALL
    ENDC
    rts


;==============================================================================
; LoadingTapeNextPhase  -  Move the tape sequence on to its next phase
;
; Called from LoadingRun on the frame after the current phase's countdown
; (LoadingIntroTick) reached zero.  Starts the new phase's audio and arms its
; countdown, so the audio and the border bars LoadingRun draws next change on
; the same frame.  Entering TAPE_DATA starts the data-block audio and clears
; LoadingIntroTick, which the data phase then uses to pace the row reveal.
;
; Destroys: d0/a0 (preserves everything else, including a5/a6)
;==============================================================================

LoadingTapeNextPhase:
    addq.w  #1,LoadingTapePhase(a5)
    move.w  LoadingTapePhase(a5),d0

    cmp.w   #TAPE_HEADER,d0
    bne.s   .not_header
    lea     ZxSfxHeader,a0                ; header data burst
    move.w  #ZX_HEADER_DATA_FRAMES,d0
    bra.s   .arm

.not_header
    cmp.w   #TAPE_GAP,d0
    bne.s   .not_gap
    bsr     LoadingAudioStop              ; tape silence
    bsr     LoadingBorderBarsOff          ; no audio, no bars
    move.w  #ZX_GAP_FRAMES,d0
    move.w  d0,LoadingIntroTick(a5)
    rts

.not_gap
    cmp.w   #TAPE_PILOT2,d0
    bne.s   .data
    lea     ZxSfxPilot,a0                 ; data-block leader tone
    move.w  #ZX_PILOT2_FRAMES,d0
    bra.s   .arm

.data
    clr.w   LoadingIntroTick(a5)          ; data phase frame counter
    lea     ZxSfxDataLoad,a0
    bra.s   LoadingPlayLoop

.arm
    move.w  d0,LoadingIntroTick(a5)
    ; fall through


;==============================================================================
; LoadingPlayLoop  -  Start a ZX tape sample looping on channel 0
;
; a0 = ZxSfx structure (zxsfx.asm).  _mt_loopfx replaces whatever is playing
; on channel 0, so no stop is needed between phases.  PTPlayer acts on the
; request at its next timer tick, within one frame.  Requires AudioInit.
;
; Destroys: none (preserves all registers)
;==============================================================================

LoadingPlayLoop:
    PUSHALL
    jsr     _mt_loopfx
    POPALL
    rts


;==============================================================================
; LoadingAudioStop  -  Stop the ZX audio SFX on channel 0
;
; Calls _mt_stopfx which immediately idles channel 0 on the leading zero-word
; of the sample buffer.  Called at the end of each ZX title audio phase.
;
; Destroys: none (preserves all registers)
;==============================================================================

LoadingAudioStop:
    PUSHALL
    moveq   #0,d0               ; channel 0
    jsr     _mt_stopfx
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
;
; Destroys: none (preserves all registers)
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

    IFD LOADING_NO_TITLE_WIPE
    IFD LOADING_OVERLAY_HOOK
    jsr     LOADING_OVERLAY_HOOK
    ENDC
    move.w  #TITLE_SETUP,GameStatus(a5)
    ELSE
    bsr     LoadingBeginTitleWipe   ; overlay decompress + arm the dissolve-to-black wipe
    ENDC

    POPALL
    rts


;==============================================================================
; LoadingBeginTitleWipe  -  Arm the dissolve-to-black wipe into the title screen
;
; Called once when the loading screen finishes (normal completion or F6 skip),
; instead of jumping straight to TITLE_SETUP.  Fills the tile wipe order and
; resets the tile counter, then flags the wipe active.  From the next frame
; LoadingRun (.wipe_out) blits WIPE_SPEED black tiles until the whole
; DisplayScreen is black, at which point TitleSetup builds the title over the
; black frame — so the cpLoading->cpTitle switch is invisible.  This reuses the
; level-transition wipe machinery (WipeFillTopBottom / WipeBlitBlack in
; screenutils.asm), which is the transition we already know renders cleanly.
;
; Destroys: none (preserves all registers)
;==============================================================================

LoadingBeginTitleWipe:
    PUSHALL
    bsr     WipePickRandomColor     ; pick random color theme for transition blocks
    bsr     WipeFillTopBottom       ; fill WipeTileX/Y with a top-to-bottom tile order
    clr.w   WipeTilesDone(a5)       ; no tiles blitted yet
    move.w  #1,LoadingWipeActive(a5)
    POPALL
    rts


;==============================================================================
; LoadingWipeStep  -  Dissolve one WIPE_SPEED batch of tiles to black
;
; Blits up to WIPE_SPEED 24x24 tiles black on DisplayScreen this frame, in the
; order held in WipeTileX/Y, advancing WipeTilesDone.  Reuses WipeBlitBlack
; (screenutils.asm) exactly as the level wipe does.
;
; OUT: d0.w = 0 while tiles remain, 1 once the whole screen is black.
; All other registers preserved.
;
; Destroys: d0 (preserves everything else, including a5/a6)
;==============================================================================

LoadingWipeStep:
    PUSHM   d1-d7/a0-a1
    move.w  WipeTilesDone(a5),d7
    cmp.w   #WIPE_GRID_SIZE,d7
    bge.s   .pause_hold

    moveq   #WIPE_SPEED-1,d6
.loop
    cmp.w   #WIPE_GRID_SIZE,d7
    bge     .batch_done
    moveq   #0,d0
    lea     WipeTileX(a5),a0
    move.b  (a0,d7.w),d0            ; tile X (0..19)
    moveq   #0,d1
    lea     WipeTileY(a5),a0
    move.b  (a0,d7.w),d1            ; tile Y (0..8)
    bsr     WipeBlitBlack           ; draw colored transition block
    addq.w  #1,d7
    dbra    d6,.loop

.batch_done
    move.w  d7,WipeTilesDone(a5)
    moveq   #0,d0                   ; more tiles (or pause) remain
    bra.s   .exit

.pause_hold
    ; Hold full wipe screen for 15 frames before moving on
    cmp.w   #WIPE_GRID_SIZE+15,d7
    bge.s   .done
    addq.w  #1,WipeTilesDone(a5)
    moveq   #0,d0
    bra.s   .exit

.done
    moveq   #1,d0                   ; wipe + 15-frame pause complete
.exit
    POPM    d1-d7/a0-a1
    rts

