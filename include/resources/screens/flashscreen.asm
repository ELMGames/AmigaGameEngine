;==============================================================================
; AMIGA GAME ENGINE
; flashscreen.asm  -  Engine Intro Splash / Flash Screen (states 19 and 20)
;==============================================================================
;
; Shown immediately on startup before the ZX Spectrum tape loading sequence.
; Displays the Amiga Game Engine banner (TitleLogoRaw / TitleLogoPal, 288x64)
; centered on screen with a black background, accompanied by a regal trumpet
; fanfare sound effect (sfx_intro_fanfare).
;
; Duration: ~2.2 seconds (FLASH_DURATION = 110 PAL frames, scaled for NTSC).
; Skippable at any time with Joystick FIRE, Space, Return, or ESC.
;
; On completion or skip: transitions to GAME_INIT (state 0 -> LoadingSetup).
;==============================================================================

FLASH_LOGO_W        = 288            ; logo width in pixels
FLASH_LOGO_H        = 64             ; logo height in pixels
FLASH_LOGO_W_BYTES  = FLASH_LOGO_W/8 ; 36 bytes per source row
FLASH_LOGO_W_WORDS  = FLASH_LOGO_W_BYTES/2   ; 18 words per source row
FLASH_LOGO_PLANES   = 3              ; bitplanes in TitleLogoRaw (8 colours)
FLASH_LOGO_PLANE_SIZE = FLASH_LOGO_W_BYTES*FLASH_LOGO_H  ; 36 * 64 = 2304 bytes per source plane

FLASH_LOGO_OFF      = FLASH_LOGO_Y*LOADING_ROW_BYTES+FLASH_LOGO_X/8 ; 68*200+2 = 13602
FLASH_LOGO_DMOD     = LOADING_ROW_BYTES-FLASH_LOGO_W_BYTES         ; 200-36 = 164

;==============================================================================
; FlashScreenSetup  -  One-shot initialisation for Flash Screen (state 19)
;==============================================================================

FlashScreenSetup:
    PUSHALL

    ; 1. Silence any prior audio
    bsr         AudioStopMod

    ; 2. Clear DisplayScreen (320x200 interleaved = 40,000 bytes)
    lea         DisplayScreen,a0
    move.l      #LOADING_ROW_BYTES*LOADING_HEIGHT,d7
    bsr         TurboClear

    ; 3a. Patch cpFlashPlanes with DisplayScreen bitplane addresses (5 planes, 40 bytes stride)
    lea         cpFlashPlanes,a0
    move.l      #DisplayScreen,d0
    move.l      #LOADING_WIDTH_BYTE,d1
    moveq       #SCREEN_DEPTH,d7
    bsr         CopperSetPtrs

    ; 3b. Patch cpFlashSprites — all 8 channels to NullSprite
    lea         cpFlashSprites,a0
    move.l      #NullSprite,d0
    moveq       #0,d1
    moveq       #8,d7
    bsr         CopperSetPtrs

    ; 3c. Install cpFlash copper list
    move.l      #cpFlash,COP1LC(a6)
    move.w      #0,COPJMP1(a6)

    ; 4. Patch cpFlashPal colours 1-7 from TitleLogoPal (entry 0 is transparent / black background)
    clr.w       cpFlashPal+2            ; COLOR00 = $0000 (black)
    lea         TitleLogoPal+2,a0       ; skip palette entry 0
    lea         cpFlashPal+4+2,a1       ; COLOR01 value word (stride 4)
    moveq       #7-1,d7
.fpal:
    move.w      (a0)+,(a1)
    addq.l      #4,a1
    dbra        d7,.fpal

    ; 4b. Stage SfxIntroFanfare_Raw and TitleLogoRaw into NonDisplayScreen (Chip RAM)
    ; SfxIntroFanfare_Raw (16,540 bytes) staged at NonDisplayScreen+0
    lea         SfxIntroFanfare_Raw,a0
    lea         NonDisplayScreen,a1
    move.w      #((SfxIntroFanfare_RawEnd-SfxIntroFanfare_Raw)/4)-1,d0
.sfx_copy:
    move.l      (a0)+,(a1)+
    dbra        d0,.sfx_copy
    lea         NonDisplayScreen,a0
    move.l      a0,SfxIntroFanfare      ; patch sfx_ptr to staged Chip RAM address

    ; TitleLogoRaw (6,912 bytes) staged at NonDisplayScreen+16544
    lea         TitleLogoRaw,a0
    lea         NonDisplayScreen+16544,a1
    move.w      #(FLASH_LOGO_PLANE_SIZE*FLASH_LOGO_PLANES/4)-1,d0
.logo_copy:
    move.l      (a0)+,(a1)+
    dbra        d0,.logo_copy

    ; 5. Blit the 3-bitplane Amiga Game Engine logo into screen planes 0-2 at (FLASH_LOGO_X, FLASH_LOGO_Y)
    WAITBLIT
    move.l      #$09F00000,BLTCON0(a6)  ; D=A, no shift, BLTCON1=0
    move.l      #-1,BLTAFWM(a6)         ; full mask
    move.w      #0,BLTAMOD(a6)          ; packed 36 bytes/row
    move.w      #FLASH_LOGO_DMOD,BLTDMOD(a6)

    move.l      #NonDisplayScreen+16544,d0 ; staged in Chip RAM
    lea         DisplayScreen+FLASH_LOGO_OFF,a1 ; current dest plane
    moveq       #FLASH_LOGO_PLANES-1,d7
.fblit:
    WAITBLIT
    move.l      d0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(FLASH_LOGO_H<<6)|FLASH_LOGO_W_WORDS,BLTSIZE(a6)
    add.l       #FLASH_LOGO_PLANE_SIZE,d0
    add.l       #LOADING_WIDTH_BYTE,a1
    dbra        d7,.fblit

    ; 6. Play regal trumpet fanfare SFX via PTPlayer
    bsr         AudioPlayIntroFanfare

    ; 7. Arm display countdown timer (~2.2s, scaled for NTSC)
    move.w      #FLASH_DURATION,d0
    bsr         ScalePALFrames
    move.w      d0,FlashScreenTimer(a5)

    ; 8. Advance to FLASH_RUN (state 20)
    move.w      #FLASH_RUN,GameStatus(a5)

    POPALL
    rts


;==============================================================================
; FlashScreenRun  -  Per-frame handler for Flash Screen (state 20)
;==============================================================================

FlashScreenRun:
    PUSHALL

    bsr         UpdateControls

    ; 1. Check if player pressed FIRE, Space, Return, or ESC to skip
    move.w      ControlsTrigger(a5),d0
    btst        #CONTROLB_FIRE,d0
    bne.s       .flash_skip

    lea         Keys,a0
    tst.b       KEY_SPACE(a0)
    bne.s       .flash_skip_space
    tst.b       KEY_RETURN(a0)
    bne.s       .flash_skip_return
    tst.b       KEY_ESC(a0)
    bne.s       .flash_skip_esc

    ; 2. Count down timer
    subq.w      #1,FlashScreenTimer(a5)
    bgt.s       .flash_stay

.flash_done:
    ; Timer expired or skipped -> transition
    tst.w       CustomLevelLoaded(a5)
    beq.s       .normal_load
    bsr         AudioStopMod            ; silence fanfare audio before game copper takeover
    move.w      #0,LevelId(a5)
    move.w      #1,EnterGameCopper(a5)  ; defer game copper switch to LEVEL_HOLD
    move.w      #1,WipeHoldTick(a5)     ; arm instant reveal setup
    move.w      #LEVEL_HOLD,GameStatus(a5)
    POPALL
    rts

.normal_load:
    move.w      #GAME_INIT,GameStatus(a5)
    POPALL
    rts

.flash_skip_space:
    clr.b       KEY_SPACE(a0)
    bra.s       .flash_done

.flash_skip_return:
    clr.b       KEY_RETURN(a0)
    bra.s       .flash_done

.flash_skip_esc:
    clr.b       KEY_ESC(a0)
    bra.s       .flash_done

.flash_skip:
    bra.s       .flash_done

.flash_stay:
    POPALL
    rts
