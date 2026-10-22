
;==============================================================================
; AMIGA GAME ENGINE
; titlescreen.asm  -  Title Screen (states TITLE_SETUP and TITLE_RUN)
;==============================================================================
;
; Shown after the loading screen completes and when RETURN TO TITLE is selected.
; The loading screen is never revisited after startup.
;
; Rendering uses DisplayScreen (320x200, 5-plane interleaved, LOADING_ROW_BYTES
; stride) with the cpTitle copper list.
;
;   Planes 0-3  Duck Rescue title banner (TitleDuckRaw, 192x96, 16 colours) blitted
;               once by TitleSetup. Colours 1-15 come from TitleDuckPal;
;               colour index 0 is transparent and reveals the aurora sky effect.
;   Plane 4     All-planes writes from CHAR_BLTString produce color 31 (white)
;               in the menu options and password area below the banner.
;
;==============================================================================

;------------------------------------------------------------------------------
; Logo geometry  (TitleDuckRaw: 192x96 pixels, 4 bitplanes, centered at x=64)
;
; The 320px screen leaves 128px of margin; centering gives x=64px (word-aligned,
; blitter destinations must be even byte addresses: 64/16 = 4 words = 8 bytes from left).
; Rows 20-115 land cleanly above the menu text starting at y=132.
;------------------------------------------------------------------------------
TITLE_LOGO_X        = 64             ; pixel x of logo left edge (word-aligned: 64/16=4 words)
TITLE_LOGO_Y        = 20             ; pixel y of logo top (rows 20-115, above the text)
TITLE_LOGO_W        = 192            ; logo width in pixels
TITLE_LOGO_H        = 96             ; logo height in pixels
TITLE_LOGO_W_BYTES  = TITLE_LOGO_W/8 ; 24 bytes per source row
TITLE_LOGO_W_WORDS  = TITLE_LOGO_W_BYTES/2   ; 12 words per source row
TITLE_LOGO_PLANES   = 4              ; bitplanes in TitleDuckRaw (16 colours)
TITLE_LOGO_PLANE_SIZE = TITLE_LOGO_W_BYTES*TITLE_LOGO_H  ; 2304 bytes per source plane

; Blitter destination byte offset of the logo's plane-0 top-left corner.
; Plane P of row Y starts at:  Y * LOADING_ROW_BYTES + P * LOADING_WIDTH_BYTE
TITLE_LOGO_OFF      = TITLE_LOGO_Y*LOADING_ROW_BYTES+TITLE_LOGO_X/8 ; 20*200 + 8 = 4008

; Blitter dest modulo (source rows are 24 bytes; interleaved screen rows 200 bytes):
TITLE_LOGO_DMOD     = LOADING_ROW_BYTES-TITLE_LOGO_W_BYTES     ; 200-24 = 176

;------------------------------------------------------------------------------
; Star animation  (32x32 sprites, byte-aligned x positions)
;------------------------------------------------------------------------------
TITLE_NUM_STARS     = 4              ; star objects
TITLE_STAR_W        = 16             ; star width in pixels (= 2 bytes)
TITLE_STAR_H        = 16             ; star height in pixels
TITLE_STAR_BYTES    = 2              ; bytes/row in star16.raw (16 px / 8 = 2)
TITLE_STAR_WORDS    = 1              ; TITLE_STAR_BYTES / 2
TITLE_STAR_MAX_X    = 38             ; max byte x-offset (star fully fits: 38+2=40)
TITLE_STAR_SPEED    = 6              ; frames between 1-byte (8 pixel) x advance

; Clear destination modulo: skip from end of star (2 bytes) to next plane-0 row.
TITLE_STAR_DMOD     = LOADING_ROW_BYTES-TITLE_STAR_BYTES        ; 200-2 = 198

;------------------------------------------------------------------------------
; Aurora background effect (cpTitleSky in copperlists.asm)
;
; Two sine waves sampled down the screen drive the background colour per
; 2-scanline band: wave 1 -> blue channel, wave 2 (scaled x0.75) -> green.
; The waves drift in opposite directions at different speeds, so their
; interference pattern never repeats exactly — deep blue / teal / cyan
; curtains that continuously morph.  All values are derived from SINE_ANGLES
; (2048 entries) so the effect is independent of the sine table size.
;------------------------------------------------------------------------------
SKY_ENTRIES         = 68                    ; colour bands (2 scanlines each, rows 0-135)
SINE_TABLE_BYTES    = SINE_ANGLES*2         ; byte size of the Sinus table
SKY_FREQ1           = SINE_ANGLES/56        ; wave 1: ~1.2 wavelengths down the screen
SKY_FREQ2           = SINE_ANGLES/34        ; wave 2: ~2 wavelengths down the screen
SKY_SPEED1          = SINE_ANGLES/256       ; wave 1 drift: full cycle ~5.1s (downward)
SKY_SPEED2          = SINE_ANGLES/160       ; wave 2 drift: full cycle ~3.4s (upward)

;------------------------------------------------------------------------------
; Text layout  (8x8 font, 320-wide screen, LOADING_ROW_BYTES = 200)
;
;   y=132  "ENTER PASSWORD: "  (green cursor + user input; always editable)
;   y=148  "[>] PLAY LEVEL <NNN> XXXXXX"  (level password shown inline)
;   y=160  "[>] CREDITS"
;   y=172  "[>] INSTRUCTIONS"
;
; TITLE_X_CURSOR = 7 byte (pixel 56) — cursor character position
; TITLE_X_TEXT   = 8 byte (pixel 64) — text start position
;------------------------------------------------------------------------------
TITLE_Y_PASS    = 132
TITLE_Y_MENU0   = 148
TITLE_Y_MENU1   = 160
TITLE_Y_MENU2   = 172
TITLE_Y_DEBUG   = 184

TITLE_X_CURSOR      = 7              ; cursor '>' byte column (1 left of text)
TITLE_X_TEXT        = 8              ; password text byte column
TITLE_X_MENU_INDENT = 4             ; extra bytes (32 pixels) indent for menu block
TITLE_X_DEBUG       = 30            ; byte column for "DEBUG MODE" label (bottom-right)

;------------------------------------------------------------------------------
; Password input constants
;------------------------------------------------------------------------------
TITLE_PASS_MAX      = 6             ; maximum password characters (6 nibbles = 24-bit level id)
TITLE_CURSOR_SPEED  = 25            ; frames per cursor blink toggle (~2 blinks/second at 50fps)


TITLE_OFF_PASS      = TITLE_Y_PASS*LOADING_ROW_BYTES+TITLE_X_TEXT
TITLE_OFF_DEBUG     = TITLE_Y_DEBUG*LOADING_ROW_BYTES+TITLE_X_DEBUG
TITLE_OFF_CURSOR0   = TITLE_Y_MENU0*LOADING_ROW_BYTES+(TITLE_X_CURSOR+TITLE_X_MENU_INDENT)
TITLE_OFF_MENU0     = TITLE_Y_MENU0*LOADING_ROW_BYTES+(TITLE_X_TEXT+TITLE_X_MENU_INDENT)
TITLE_OFF_CURSOR1   = TITLE_Y_MENU1*LOADING_ROW_BYTES+(TITLE_X_CURSOR+TITLE_X_MENU_INDENT)
TITLE_OFF_MENU1     = TITLE_Y_MENU1*LOADING_ROW_BYTES+(TITLE_X_TEXT+TITLE_X_MENU_INDENT)
TITLE_OFF_CURSOR2   = TITLE_Y_MENU2*LOADING_ROW_BYTES+(TITLE_X_CURSOR+TITLE_X_MENU_INDENT)
TITLE_OFF_MENU2     = TITLE_Y_MENU2*LOADING_ROW_BYTES+(TITLE_X_TEXT+TITLE_X_MENU_INDENT)

; Password 6 chars start 16 bytes after TITLE_OFF_PASS  (after "ENTER PASSWORD: "):
TITLE_OFF_PASS_CHARS = TITLE_OFF_PASS+16

; Level number 3 chars start 12 bytes after TITLE_OFF_MENU0 (after "PLAY LEVEL <"):
TITLE_OFF_LEVEL_NUM  = TITLE_OFF_MENU0+12
; Password 6 chars start 5 bytes after TITLE_OFF_LEVEL_NUM (after "NNN> "):
TITLE_OFF_PLAY_PASS  = TITLE_OFF_LEVEL_NUM+5



;==============================================================================
; TitleSetup  -  One-shot initialisation for the title screen (state TITLE_SETUP)
;
; Sequence:
;   1. Stop music.
;   2. Clear DisplayScreen (320x200 interleaved = 40000 bytes).
;   3. Patch cpTitlePlanes / cpTitleSprites; install cpTitle copper list.
;   4. Patch cpTitlePal colours 1-15 from TitleDuckPal; stage and blit the 4-bitplane
;      title banner (TitleDuckRaw) into screen planes 0-3.
;   5. WAITBLIT; draw static text via CPU writes.
;   6. Initialise animation counters.
;   7. Set GameStatus = TITLE_RUN.
;==============================================================================

TitleSetup:
    PUSHALL

    ; Revert to standard campaign when entering Title screen
    clr.w       CustomLevelLoaded(a5)
    clr.l       CustomLevelDef(a5)

    bsr         AudioStopMod

    ; The loading->title transition dissolves DisplayScreen to black via the tile
    ; wipe (loading.asm) BEFORE this runs, so the cpLoading->cpTitle switch below
    ; happens on an all-black frame and is invisible — no DMA blanking needed here.
    ; (The ESC/level->title path is already a calm, beam-aligned switch.)

    ; 2. Clear DisplayScreen (320x200 interleaved = 40000 bytes)
    lea         DisplayScreen,a0
    move.l      #LOADING_ROW_BYTES*LOADING_HEIGHT,d7
    bsr         TurboClear

    ; 3a. Patch cpTitlePlanes with DisplayScreen bitplane addresses.
    ;     The five planes stride by LOADING_WIDTH_BYTE (42) between them.
    lea         cpTitlePlanes,a0
    move.l      #DisplayScreen,d0
    move.l      #LOADING_WIDTH_BYTE,d1
    moveq       #SCREEN_DEPTH,d7
    bsr         CopperSetPtrs           ; shared copper pointer patcher (tools.asm)

    ; 3b. Patch cpTitleSprites — all 8 channels to NullSprite (stride 0)
    lea         cpTitleSprites,a0
    move.l      #NullSprite,d0
    moveq       #0,d1
    moveq       #8,d7
    bsr         CopperSetPtrs

    ; 3c. Install cpTitle and (re-)assert full DMA
    move.l      #cpTitle,COP1LC(a6)
    move.w      #0,COPJMP1(a6)
  ;  move.w      #BASE_DMA,DMACON(a6)

    ; 4a. Patch cpTitlePal colours 1-15 from the Duck Rescue logo palette (TitleDuckPal).
    ;     Colour 0 stays untouched: logo index 0 is transparent and COLOR00
    ;     is driven per-band by the aurora background effect (cpTitleSky).
    lea         TitleDuckPal+2,a0       ; skip palette entry 0
    lea         cpTitlePal+4+2,a1       ; COLOR01 value word (entry stride 4)
    moveq       #15-1,d7
.lpal
    move.w      (a0)+,(a1)
    addq.l      #4,a1
    dbra        d7,.lpal

    ; 4b. Stage and blit the 4-bitplane Duck Rescue title logo into screen planes 0-3 at
    ;     (TITLE_LOGO_X, TITLE_LOGO_Y).  TitleDuckRaw is in Fast RAM; stage into
    ;     NonDisplayScreen (Chip RAM) which is idle during title display.
    lea         TitleDuckRaw,a0
    lea         NonDisplayScreen,a1
    move.w      #(TITLE_LOGO_PLANE_SIZE*TITLE_LOGO_PLANES/4)-1,d0
.ts_stage_logo:
    move.l      (a0)+,(a1)+
    dbra        d0,.ts_stage_logo

    WAITBLIT
    move.l      #$09F00000,BLTCON0(a6)  ; D=A, no shift, BLTCON1=0
    move.l      #-1,BLTAFWM(a6)         ; full first+last word masks
    move.w      #0,BLTAMOD(a6)          ; source rows are packed 24 bytes
    move.w      #TITLE_LOGO_DMOD,BLTDMOD(a6)

    move.l      #NonDisplayScreen,d0    ; staged in Chip RAM
    lea         DisplayScreen+TITLE_LOGO_OFF,a1   ; a1 = current dest plane
    moveq       #TITLE_LOGO_PLANES-1,d7
.lblit:
    WAITBLIT
    move.l      d0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(TITLE_LOGO_H<<6)|TITLE_LOGO_W_WORDS,BLTSIZE(a6)
    add.l       #TITLE_LOGO_PLANE_SIZE,d0         ; next source plane
    add.l       #LOADING_WIDTH_BYTE,a1            ; next interleaved screen plane
    dbra        d7,.lblit

    ; 5. WAITBLIT before CPU text writes
    WAITBLIT

    ; 4c. Stage TitleScreenMusicMod (46,414 bytes) from Fast RAM into NonDisplayScreen+10000 (Chip RAM).
    ;     NonDisplayScreen is completely idle during the title screen; music is played via PTPlayer
    ;     and stopped by AudioStopMod when entering gameplay. Saves 46,414 bytes of permanent Chip RAM!
    lea         TitleScreenMusicMod,a0
    lea         NonDisplayScreen+10000,a1
    move.w      #((TitleScreenMusicModEnd-TitleScreenMusicMod)/4)-1,d0
.ts_stage_music:
    move.l      (a0)+,(a1)+
    dbra        d0,.ts_stage_music
    move.w      (a0)+,(a1)+                 ; copy trailing word

    ; Snapshot current level and generate password (displayed only in debug mode)
    move.w      LevelId(a5),TitleLevelNum(a5)
    move.w      LevelId(a5),d0
    cmp.w       MaxUnlockedLevel(a5),d0
    ble         .ts_no_max
    move.w      d0,MaxUnlockedLevel(a5)
.ts_no_max
    bsr         LC_GenPassword          ; fill LCPasswordBuf for the current level

    ; Draw "PLAY LEVEL <"
    lea         .str_play,a0
    lea         DisplayScreen+TITLE_OFF_MENU0,a1
    bsr         CHAR_BLTString
    ; Draw level number (1-based)
    moveq       #0,d0
    move.w      TitleLevelNum(a5),d0
    addq.w      #1,d0
    bsr         CHAR_BLTNum3
    ; Draw closing ">"; then " " + password only if level > 1
    move.b      #'>',d2
    bsr         CHAR_BLTOneChar
    tst.w       TitleLevelNum(a5)
    beq         .ts_no_play_pass
    move.b      #' ',d2
    bsr         CHAR_BLTOneChar
    lea         LCPasswordBuf(a5),a0
    bsr         CHAR_BLTString
.ts_no_play_pass

    ; Draw "CREDITS" and "INSTRUCTIONS"
    lea         .str_credits,a0
    lea         DisplayScreen+TITLE_OFF_MENU1,a1
    bsr         CHAR_BLTString

    lea         .str_instr,a0
    lea         DisplayScreen+TITLE_OFF_MENU2,a1
    bsr         CHAR_BLTString

    ; Draw initial cursor (item 0 selected)
    clr.w       TitleMenuSel(a5)
    bsr         CHAR_DrawCursor

    ; Always draw "ENTER PASSWORD: " label (present in both normal and debug modes)
    lea         .str_pass,a0
    lea         DisplayScreen+TITLE_OFF_PASS,a1
    bsr         CHAR_BLTString

    ; Initialise password input state
    moveq       #0,d0
    lea         TitlePassBuf(a5),a0
    move.l      d0,(a0)+               ; clear bytes 0-3
    move.l      d0,(a0)                ; clear bytes 4-7
    clr.w       TitlePassLen(a5)
    move.w      #TITLE_CURSOR_SPEED,TitleCursorTick(a5)
    move.w      #1,TitleCursorOn(a5)

    bsr         CHAR_DrawPassInput

    ; Seed the aurora background so the first displayed frame is not black.
    ; SkyPhase1/2 are NOT reset here — they start at 0 from BSS on first entry
    ; and are preserved across title/instructions transitions thereafter.
    bsr         TS_UpdateSky

    ; Start title music (heatwave_cruise.mod, loops until we leave the title)
    bsr         AudioPlayTitleMusic

    ; If debug mode was already active, show debug info now
    tst.w       DebugMode(a5)
    beq         .no_debug
    bsr         CHAR_DrawDebugInfo
.no_debug

    ; Palette fade-in (commented out):
;    lea         cpTitlePal,a0
;    moveq       #SCREEN_COLORS,d7
;    bsr         PaletteFadeCapture      ; PalFadeWork = the just-patched target colours
;    lea         cpTitlePal,a0
;    lea         PalFadeWork,a1
;    move.w      #FADE_SPEED_NORMAL,d0
;    bsr         PaletteFadeIn           ; PalFadeTarget=a1[] (copied before PalFadeWork is zeroed)
;    bsr         PaletteFadeTick         ; force the immediate black write

    ; 8. Advance to TITLE_RUN
    clr.w       VBlankOverrunCount(a5) ; clear multi-frame setup overruns
    move.w      #TITLE_RUN,GameStatus(a5)

    POPALL
    rts

.str_play       dc.b    "PLAY LEVEL <",0
.str_credits    dc.b    "CREDITS",0
.str_instr      dc.b    "INSTRUCTIONS",0
.str_pass       dc.b    "ENTER PASSWORD: ",0
    even


;==============================================================================
; TitleRun  -  Per-frame handler for the title screen (state TITLE_RUN)
;
; Each frame:
;   0. If TitleSetup armed a PaletteFadeIn (PalFadeActive), tick it.
;   1. UpdateControls.
;   2. TS_TickEffects: advance the aurora background effect one frame
;      (TS_UpdateSky rewrites the cpTitleSky copper colours).
;   3. Input: UP/DOWN moves cursor; LEFT/RIGHT changes level (item 0 only);
;             FIRE/RETURN executes selection.
;==============================================================================

TitleRun:
    PUSHALL

    ; Advance the fade-in armed by TitleSetup, if still running (commented out).
;    tst.w       PalFadeActive(a5)
;    beq         .no_fade_tick
;    bsr         PaletteFadeTick
;.no_fade_tick

    bsr         UpdateControls

    ;--------------------------------------------------------------------------
    ; Aurora background effect (shared with instructions screens)
    ;--------------------------------------------------------------------------
    bsr         TS_TickEffects

    ;--------------------------------------------------------------------------
    ; Input handling
    ;--------------------------------------------------------------------------

    ; ESC: quit the game and return to the OS (MainLoop tears everything down)
    lea         Keys,a0
    tst.b       KEY_ESC(a0)
    beq         .no_quit
    clr.b       KEY_ESC(a0)
    move.w      #1,QuitFlag(a5)
.no_quit

    ; F5: enter/exit debug mode (shows password + level nav; raster bar controlled by F3 in game)
    lea         Keys,a0
    tst.b       KEY_F5(a0)
    beq         .no_f5
    clr.b       KEY_F5(a0)
    tst.w       DebugMode(a5)
    beq         .f5_enable
    clr.w       DebugMode(a5)
    bsr         TS_ClearDebugInfo
    bra         .no_f5
.f5_enable
    move.w      #1,DebugMode(a5)
    bsr         CHAR_DrawDebugInfo
.no_f5

    ;--------------------------------------------------------------------------
    ; Non-debug password input (cursor blink + keyboard A-P)
    ;--------------------------------------------------------------------------
    tst.w       DebugMode(a5)
    bne         .no_passinput

    ; Cursor blink countdown
    subq.w      #1,TitleCursorTick(a5)
    bne         .cursor_done
    move.w      #TITLE_CURSOR_SPEED,TitleCursorTick(a5)
    cmp.w       #TITLE_PASS_MAX,TitlePassLen(a5)
    beq         .cursor_done           ; no cursor when field is full
    tst.w       TitleCursorOn(a5)
    bne         .cursor_off
    move.w      #1,TitleCursorOn(a5)
    move.b      #$FF,d2                ; solid block = cursor on
    bra         .cursor_blit
.cursor_off
    clr.w       TitleCursorOn(a5)
    move.b      #$00,d2                ; blank = cursor off
.cursor_blit
    moveq       #0,d0
    move.w      TitlePassLen(a5),d0
    lea         DisplayScreen+TITLE_OFF_PASS_CHARS,a1
    adda.w      d0,a1
    bsr         CHAR_DrawBlockChar
.cursor_done

    ; Backspace: remove last entered character
    lea         Keys,a0
    tst.b       KEY_BACKSPACE(a0)
    beq         .no_backspace
    clr.b       KEY_BACKSPACE(a0)
    tst.w       TitlePassLen(a5)
    beq         .no_backspace
    cmp.w       #TITLE_PASS_MAX,TitlePassLen(a5)
    beq         .bs_no_cursor          ; field was full; cursor was not shown
    moveq       #0,d0
    move.w      TitlePassLen(a5),d0
    lea         DisplayScreen+TITLE_OFF_PASS_CHARS,a1
    adda.w      d0,a1
    move.b      #' ',d2
    bsr         CHAR_BLTOneChar          ; erase cursor at current position
.bs_no_cursor
    subq.w      #1,TitlePassLen(a5)
    move.w      #1,TitleCursorOn(a5)
    move.w      #TITLE_CURSOR_SPEED,TitleCursorTick(a5)
    bsr         CHAR_DrawPassInput
.no_backspace

    ; A-P key input: scan keyboard; only one key processed per frame
    cmp.w       #TITLE_PASS_MAX,TitlePassLen(a5)
    beq         .no_passinput
    lea         TitleKeyMap,a2
.keymap_loop
    moveq       #0,d3
    move.b      (a2)+,d3               ; Amiga raw keycode (zero-extended)
    cmp.b       #$FF,d3
    beq         .no_passinput          ; end of table: no matching key pressed
    move.b      (a2)+,d4               ; ASCII character for this key
    lea         Keys,a0
    tst.b       (a0,d3.w)
    beq         .keymap_loop           ; not pressed, try next entry
    clr.b       (a0,d3.w)             ; consume the key
    moveq       #0,d0
    move.w      TitlePassLen(a5),d0
    lea         TitlePassBuf(a5),a0
    move.b      d4,(a0,d0.w)          ; store character in buffer
    addq.w      #1,TitlePassLen(a5)
    cmp.w       #TITLE_PASS_MAX,TitlePassLen(a5)
    bne         .key_draw_cursor
    bsr         CHAR_DrawPassInput
    bsr         TS_TryDecodePassword
    bra         .no_passinput
.key_draw_cursor
    move.w      #1,TitleCursorOn(a5)
    move.w      #TITLE_CURSOR_SPEED,TitleCursorTick(a5)
    bsr         CHAR_DrawPassInput

.no_passinput

    move.b      ControlsTrigger(a5),d0

    ; UP: move cursor toward item 0
    btst        #CONTROLB_UP,d0
    beq         .no_up
    tst.w       TitleMenuSel(a5)
    beq         .no_up
    subq.w      #1,TitleMenuSel(a5)
    bsr         CHAR_DrawCursor
.no_up

    ; DOWN: move cursor toward item 2
    btst        #CONTROLB_DOWN,d0
    beq         .no_down
    cmp.w       #2,TitleMenuSel(a5)
    beq         .no_down
    addq.w      #1,TitleMenuSel(a5)
    bsr         CHAR_DrawCursor
.no_down

    ; LEFT: decrease level number (item 0 only)
    btst        #CONTROLB_LEFT,d0
    beq         .no_left
    tst.w       TitleMenuSel(a5)
    bne         .no_left
    move.w      TitleLevelNum(a5),d1
    beq         .no_left                        ; already level 1 (LevelId 0)
    subq.w      #1,d1
    move.w      d1,TitleLevelNum(a5)
    bsr         TS_UpdateLevelDisplay
.no_left

    ; RIGHT: increase level number (item 0 only)
    btst        #CONTROLB_RIGHT,d0
    beq         .no_right
    tst.w       TitleMenuSel(a5)
    bne         .no_right
    move.w      TitleLevelNum(a5),d1
    tst.w       DebugMode(a5)
    bne         .right_cap_debug
    cmp.w       MaxUnlockedLevel(a5),d1
    bge         .no_right
    bra         .right_do
.right_cap_debug
    cmp.w       #LEVEL_TABLE_COUNT-1,d1
    bge         .no_right
.right_do
    addq.w      #1,d1
    move.w      d1,TitleLevelNum(a5)
    bsr         TS_UpdateLevelDisplay
.no_right

    ; FIRE or RETURN: execute current menu selection
    btst        #CONTROLB_FIRE,d0
    bne         .do_fire
    lea         Keys,a0
    tst.b       KEY_RETURN(a0)
    beq         .no_fire
    clr.b       KEY_RETURN(a0)
.do_fire
    move.w      TitleMenuSel(a5),d1
    tst.w       d1
    beq         .do_play                ; item 0 = PLAY LEVEL
    cmp.w       #1,d1
    beq         .do_credits             ; item 1 = CREDITS
    cmp.w       #2,d1
    beq         .do_instr               ; item 2 = INSTRUCTIONS
    bra         .no_fire

.do_credits
    move.w      #CREDITS_SETUP,GameStatus(a5)
    bra         .done

.do_instr
    move.w      #INSTR_SETUP1,GameStatus(a5)
    bra         .done

.do_play
    ; PLAY LEVEL — start game at TitleLevelNum via the standard wipe transition.
    ; Route through LEVEL_INIT so the blitter wipe dissolves the title screen;
    ; the game copper + palette are installed at the end of the wipe (LEVEL_HOLD)
    ; while the screen is uniform, so the copper swap is invisible.
    bsr         AudioStopMod
    bsr         TS_FlattenSky           ; kill the aurora so the wipe dissolves to black
    move.w      TitleLevelNum(a5),LevelId(a5)
    move.w      #1,EnterGameCopper(a5)  ; defer game-copper switch to end of wipe
    clr.w       SlowMode(a5)            ; unconditionally start in RUN mode
    clr.w       SlowModeHold(a5)
    clr.w       PrevKeyS(a5)
    clr.w       GamePaused(a5)
    clr.w       DebugOverlayActive(a5)
    clr.w       PrevDebugDrawn(a5)
    lea         Keys,a0
    clr.b       KEY_S(a0)
    clr.b       KEY_A(a0)
    clr.b       KEY_D(a0)
    clr.b       KEY_P(a0)
    move.w      #LEVEL_INIT,GameStatus(a5)
    bra         .done

.no_fire
.done
    POPALL
    rts


;==============================================================================
; CHAR_DrawCursor  -  Draw '>' at selected menu item, ' ' at the other three
;
; Reads TitleMenuSel(a5): 0=PLAY LEVEL, 1=CREDITS, 2=INSTRUCTIONS.
; Writes to the cursor column (TITLE_X_CURSOR) for each of the four rows.
;==============================================================================

CHAR_DrawCursor:
    PUSHALL

    ; Erase all three cursors first
    move.b      #' ',d2
    lea         DisplayScreen+TITLE_OFF_CURSOR0,a1
    bsr         CHAR_BLTOneChar
    lea         DisplayScreen+TITLE_OFF_CURSOR1,a1
    bsr         CHAR_BLTOneChar
    lea         DisplayScreen+TITLE_OFF_CURSOR2,a1
    bsr         CHAR_BLTOneChar

    ; Draw '>' at selected item
    move.w      TitleMenuSel(a5),d1
    move.b      #'>',d2
    lea         DisplayScreen+TITLE_OFF_CURSOR0,a1
    tst.w       d1
    beq         .draw
    lea         DisplayScreen+TITLE_OFF_CURSOR1,a1
    cmp.w       #1,d1
    beq         .draw
    lea         DisplayScreen+TITLE_OFF_CURSOR2,a1
.draw
    bsr         CHAR_BLTGreenChar

    POPALL
    rts



;==============================================================================
; TS_UpdateLevelDisplay  -  Redraw level number and password in place
;
; Called when TitleLevelNum changes (LEFT/RIGHT arrow on PLAY LEVEL).
; Overwrites the 3-digit level number and 6-char password by writing new
; character bytes to all 5 screen planes (CHAR_BLTOneChar style).
;==============================================================================

TS_UpdateLevelDisplay:
    PUSHALL

    ; Redraw 3-digit level number at TITLE_OFF_LEVEL_NUM (after "PLAY LEVEL <")
    moveq       #0,d0
    move.w      TitleLevelNum(a5),d0
    addq.w      #1,d0                  ; 1-based display
    lea         DisplayScreen+TITLE_OFF_LEVEL_NUM,a1
    bsr         CHAR_BLTNum3

    ; Regenerate password for the new level (keep LCPasswordBuf current)
    move.w      LevelId(a5),-(sp)
    move.w      TitleLevelNum(a5),LevelId(a5)
    bsr         LC_GenPassword
    move.w      (sp)+,LevelId(a5)

    ; Redraw password slot on PLAY LEVEL line (7 chars: space + 6-char password).
    ; Level 1 (TitleLevelNum=0) has no password — clear the slot instead.
    lea         DisplayScreen+TITLE_OFF_PLAY_PASS-1,a1  ; -1 = space before password
    tst.w       TitleLevelNum(a5)
    beq         .uld_clr_pass
    move.b      #' ',d2
    bsr         CHAR_BLTOneChar
    lea         LCPasswordBuf(a5),a0
    bsr         CHAR_BLTString
    bra         .uld_pass_done
.uld_clr_pass
    move.b      #' ',d2
    moveq       #7-1,d7
.uld_clr_loop
    bsr         CHAR_BLTOneChar
    dbra        d7,.uld_clr_loop
.uld_pass_done

    ; Refresh ENTER PASSWORD field (debug: show password; normal: restore cursor/input)
    tst.w       DebugMode(a5)
    bne         .uld_debug_pass
    bsr         CHAR_DrawPassInput
    bra         .no_pass_draw
.uld_debug_pass
    lea         LCPasswordBuf(a5),a0
    lea         DisplayScreen+TITLE_OFF_PASS_CHARS,a1
    bsr         CHAR_BLTString
.no_pass_draw

    POPALL
    rts


;==============================================================================
; CHAR_DrawDebugInfo  -  Draw password line and "DEBUG MODE" label (debug on)
;
; Called when debug mode is toggled on (F5) and from TitleSetup if debug was
; already active.  Draws the "ENTER PASSWORD: " label + 6-char password at
; TITLE_OFF_PASS, and "DEBUG MODE" at TITLE_OFF_DEBUG (bottom-right).
;==============================================================================

CHAR_DrawDebugInfo:
    PUSHALL

    ; Show generated password for current level (overwrites user input area)
    lea         LCPasswordBuf(a5),a0
    lea         DisplayScreen+TITLE_OFF_PASS_CHARS,a1
    bsr         CHAR_BLTString

    ; Draw "DEBUG MODE" label in bottom-right corner
    lea         .str_debug,a0
    lea         DisplayScreen+TITLE_OFF_DEBUG,a1
    bsr         CHAR_BLTString

    POPALL
    rts

.str_debug  dc.b    "DEBUG MODE",0
    even


;==============================================================================
; TS_ClearDebugInfo  -  Restore input view and erase "DEBUG MODE" label (debug off)
;
; Calls CHAR_DrawPassInput to restore the TitlePassBuf/cursor view in the password
; area, then blanks the 10-char "DEBUG MODE" label at TITLE_OFF_DEBUG.
;==============================================================================

TS_ClearDebugInfo:
    PUSHALL

    ; Restore the non-debug password input view (TitlePassBuf chars + cursor)
    bsr         CHAR_DrawPassInput

    ; Erase the "DEBUG MODE" label
    lea         DisplayScreen+TITLE_OFF_DEBUG,a1
    move.b      #' ',d2
    moveq       #10-1,d7
.clr_debug
    bsr         CHAR_BLTOneChar
    dbra        d7,.clr_debug

    POPALL
    rts


; Character blit routines (CHAR_BLTString, CHAR_BLTOneChar, CHAR_BLTGreenChar, etc.)
; are in char_bltroutines.asm — included in main.asm before this file.

;==============================================================================
; TS_TryDecodePassword  -  Validate TitlePassBuf as a 6-char A-P password
;
; Called when TitlePassLen reaches TITLE_PASS_MAX (6).  Passes the buffer to
; LC_DecodePassword; if valid, updates TitleLevelNum and refreshes the level
; number display via TS_UpdateLevelDisplay.
;
; Does not use PUSHALL: intended to be called from within TitleRun's PUSHALL
; context.  Saves/restores a0 around LC_DecodePassword; d0 carries return value.
;==============================================================================

TS_TryDecodePassword:
    move.l      a0,-(sp)
    lea         TitlePassBuf(a5),a0
    move.b      #0,TITLE_PASS_MAX(a0)       ; null-terminate at offset 6
    bsr         LC_DecodePassword            ; a0=buf; d0.w = LevelId or $FFFF
    move.l      (sp)+,a0
    cmp.w       #$FFFF,d0
    beq         .ttdp_done
    move.w      d0,TitleLevelNum(a5)
    cmp.w       MaxUnlockedLevel(a5),d0
    ble         .ttdp_show
    move.w      d0,MaxUnlockedLevel(a5)
.ttdp_show
    bsr         TS_UpdateLevelDisplay
.ttdp_done
    rts


;==============================================================================
; CHAR_DrawPassInput  -  Redraw the password input field (TitlePassBuf + cursor)
;
; Called by TS_ClearDebugInfo to restore the non-debug view after debug is
; toggled off.  Clears 7 chars at TITLE_OFF_PASS_CHARS, redraws TitlePassLen
; entered characters, then draws '_' if TitleCursorOn and field is not full.
;==============================================================================

CHAR_DrawPassInput:
    PUSHALL

    ; Clear 7 characters (max 6 input chars + 1 cursor slot)
    lea         DisplayScreen+TITLE_OFF_PASS_CHARS,a1
    move.b      #' ',d2
    moveq       #7-1,d7
.dpi_clr
    bsr         CHAR_BLTOneChar
    dbra        d7,.dpi_clr

    ; Redraw entered characters; a1 ends up at the cursor slot
    lea         TitlePassBuf(a5),a0
    lea         DisplayScreen+TITLE_OFF_PASS_CHARS,a1
    moveq       #0,d7
    move.w      TitlePassLen(a5),d7
    beq         .dpi_cursor
    subq.w      #1,d7
.dpi_char
    move.b      (a0)+,d2
    bsr         CHAR_BLTGreenChar        ; redraw in green
    dbra        d7,.dpi_char

.dpi_cursor
    cmp.w       #TITLE_PASS_MAX,TitlePassLen(a5)
    beq         .dpi_done
    tst.w       TitleCursorOn(a5)
    beq         .dpi_done
    move.b      #$FF,d2
    bsr         CHAR_DrawBlockChar

.dpi_done
    POPALL
    rts


;==============================================================================
; TS_TickEffects  -  Advance the title screen background effect one frame
;
; Called every frame from TitleRun, InstrPage1Run and InstrPage2Run so that the
; visual effects continue seamlessly across title and instructions screens.
;==============================================================================

TS_TickEffects:
    bsr         TS_UpdateSky
    rts


;==============================================================================
; TS_UpdateSky  -  Recompute the aurora background copper colours (per frame)
;
; For each of the SKY_ENTRIES 2-scanline bands (rows 0-135):
;   blue  = Sinus[phase1 + band*SKY_FREQ1] >> 12 + 8        (0..15)
;   green = (Sinus[phase2 + band*SKY_FREQ2] >> 12 + 8) *3/4 (0..11)
; Both channels are dimmed by SkyDimTab near the bottom so the effect fades
; to black before the password/menu text area (rows 136+), then the $0GB
; colour word is written into the cpTitleSky copper entry.
;
; phase1 drifts forward and phase2 backward each frame (different speeds), so
; the two waves slide through each other and the pattern continuously morphs.
; Phases are byte offsets into Sinus, kept in [0, SINE_TABLE_BYTES).
;==============================================================================

TS_UpdateSky:
    PUSHM       d0-d4/d7/a0-a2

    ; Advance wave 1 phase (downward drift)
    move.w      SkyPhase1(a5),d1
    add.w       #SKY_SPEED1*2,d1
    cmp.w       #SINE_TABLE_BYTES,d1
    blt.s       .p1_ok
    sub.w       #SINE_TABLE_BYTES,d1
.p1_ok
    move.w      d1,SkyPhase1(a5)

    ; Advance wave 2 phase (upward drift)
    move.w      SkyPhase2(a5),d2
    sub.w       #SKY_SPEED2*2,d2
    bpl.s       .p2_ok
    add.w       #SINE_TABLE_BYTES,d2
.p2_ok
    move.w      d2,SkyPhase2(a5)

    lea         Sinus,a0
    lea         SkyDimTab,a2
    lea         cpTitleSky+6,a1        ; first COLOR00 value word (entry stride 8)
    moveq       #SKY_ENTRIES-1,d7
.sky_loop
    ; Blue channel from wave 1: sine ±$7fff >> 12 = -8..7, +8 = 0..15
    move.w      (a0,d1.w),d0
    asr.w       #8,d0
    asr.w       #4,d0
    addq.w      #8,d0
    ; Green channel from wave 2, scaled x0.75 (0..11) for a teal-biased mix
    move.w      (a0,d2.w),d3
    asr.w       #8,d3
    asr.w       #4,d3
    addq.w      #8,d3
    move.w      d3,d4
    add.w       d3,d3
    add.w       d4,d3                  ; d3 = g*3
    asr.w       #2,d3                  ; d3 = g*3/4 (0..11)
    ; Dim both channels toward black near the text area (clamp at 0)
    moveq       #0,d4
    move.b      (a2)+,d4
    sub.w       d4,d0
    bpl.s       .b_ok
    moveq       #0,d0
.b_ok
    sub.w       d4,d3
    bpl.s       .g_ok
    moveq       #0,d3
.g_ok
    ; Compose $0GB and write into the copper entry
    lsl.w       #4,d3
    or.w        d3,d0
    move.w      d0,(a1)
    addq.l      #8,a1
    ; Step both wave phases by their per-band frequency (with wraparound)
    add.w       #SKY_FREQ1*2,d1
    cmp.w       #SINE_TABLE_BYTES,d1
    blt.s       .f1_ok
    sub.w       #SINE_TABLE_BYTES,d1
.f1_ok
    add.w       #SKY_FREQ2*2,d2
    cmp.w       #SINE_TABLE_BYTES,d2
    blt.s       .f2_ok
    sub.w       #SINE_TABLE_BYTES,d2
.f2_ok
    dbra        d7,.sky_loop

    POPM        d0-d4/d7/a0-a2
    rts


;==============================================================================
; TS_FlattenSky  -  Kill the aurora effect (all sky bands -> black)
;
; Called when leaving the title for gameplay so the level-transition wipe
; dissolves the logo and menu text against a flat black background instead of
; the moving aurora.  Writes $000 into the COLOR00 value word of every one of
; the SKY_ENTRIES cpTitleSky bands (value word at +6, entry stride 8); the
; static text-area entry that follows is already black.  Not restored here —
; TS_UpdateSky (called from TitleSetup) rebuilds the aurora on any return to
; the title.  Destroys d7/a1.
;==============================================================================

TS_FlattenSky:
    lea         cpTitleSky+6,a1        ; first COLOR00 value word (entry stride 8)
    moveq       #SKY_ENTRIES-1,d7
.loop
    move.w      #$000,(a1)
    addq.l      #8,a1
    dbra        d7,.loop
    rts


;------------------------------------------------------------------------------
; SkyDimTab  -  per-band brightness reduction (SKY_ENTRIES bytes)
;
; Zero for the top 56 bands; the last 12 bands (rows 112-135) subtract an
; increasing amount from both colour channels so the aurora fades smoothly
; into the black text area below row 136.  16 kills any channel value (max 15).
;------------------------------------------------------------------------------
SkyDimTab:
    dcb.b   SKY_ENTRIES-12,0
    dc.b    1,2,3,4,5,6,8,10,12,14,16,16
    even


;------------------------------------------------------------------------------
; TitleKeyMap  -  Amiga raw keycode -> ASCII character table for password input
;
; Pairs of (keycode, ascii_char) for letters A-P (the password alphabet used
; by LC_DecodePassword: nibbles 0-15 encoded as 'A'-'P').
; Terminated by a single $FF byte (no paired ASCII byte after the terminator).
;------------------------------------------------------------------------------

TitleKeyMap:
    dc.b    $20,'A'
    dc.b    $35,'B'
    dc.b    $33,'C'
    dc.b    $22,'D'
    dc.b    $12,'E'
    dc.b    $23,'F'
    dc.b    $24,'G'
    dc.b    $25,'H'
    dc.b    $17,'I'
    dc.b    $26,'J'
    dc.b    $27,'K'
    dc.b    $28,'L'
    dc.b    $37,'M'
    dc.b    $36,'N'
    dc.b    $18,'O'
    dc.b    $19,'P'
    dc.b    $FF
    even
