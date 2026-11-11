;==============================================================================
; MEADOW RUN - BOOT SPLASH
; splash.asm  -  The Amiga Game Engine banner and fanfare, before the level
;==============================================================================
;
; The same splash Duck Rescue shows at boot (engine/screens/flashscreen.asm):
; the 288 x 64 Amiga Game Engine logo, centred on black, with the trumpet
; fanfare. Duck Rescue's version is a state of its game-state machine and
; works on that game's screen buffers; Meadow Run has no state machine, so
; this one is a countdown that GameStatusRun runs before the level.
;
;   SplashInit  at boot (GameInitHook): draw the logo, show SplashCopper
;   SplashRun   each frame while SplashTimer > 0: the fanfare on the first
;               frame, then wait about 2.2 seconds, or for fire, Space or
;               Return, and hand over to GameCopper
;
; The logo is drawn into HsDisplayBuf, as 3 interleaved planes of 40 bytes;
; the level overwrites it when LevelStart draws the first view.
;==============================================================================

SPLASH_FRAMES       = 110               ; ~2.2 s, as Duck Rescue (logic ticks)
SPLASH_PLANES       = 3                 ; AGE_title.raw: 8 colours
SPLASH_LINE_BYTES   = SPLASH_PLANES*SCREEN_WIDTH_BYTE ; 120: one interleaved line
SPLASH_MOD          = SPLASH_LINE_BYTES-SCREEN_WIDTH_BYTE ; 80
SPLASH_LOGO_W_BYTES = 288/8             ; 36
SPLASH_LOGO_H       = 64
SPLASH_LOGO_PLANE   = SPLASH_LOGO_W_BYTES*SPLASH_LOGO_H ; 2,304: the file is planar
SPLASH_LOGO_Y       = (SCREEN_HEIGHT-SPLASH_LOGO_H)/2   ; 76: centred
SPLASH_LOGO_OFF     = SPLASH_LOGO_Y*SPLASH_LINE_BYTES+(320-288)/16 ; 2 bytes in

;==============================================================================
; SplashInit  -  Draw the logo and install SplashCopper
;
; Called from GameInitHook, with DMA still off, so the CPU copies the logo:
; it runs once, and the file is planar (one whole plane after another)
; while the screen is interleaved.
;
; Destroys: d0-d7, a0-a2
;==============================================================================

SplashInit:
    lea        HsDisplayBuf,a0
    move.l     #SPLASH_LINE_BYTES*SCREEN_HEIGHT,d7
    bsr        TurboClear

    lea        SplashLogo,a0           ; plane 0, then 1, then 2
    lea        HsDisplayBuf+SPLASH_LOGO_OFF,a2
    moveq      #SPLASH_PLANES-1,d7
.plane:
    move.l     a2,a1
    moveq      #SPLASH_LOGO_H-1,d6
.line:
    moveq      #SPLASH_LOGO_W_BYTES/4-1,d5
.long:
    move.l     (a0)+,(a1)+
    dbra       d5,.long
    lea        SPLASH_LINE_BYTES-SPLASH_LOGO_W_BYTES(a1),a1
    dbra       d6,.line
    lea        SCREEN_WIDTH_BYTE(a2),a2 ; the next plane of the same line
    dbra       d7,.plane

    lea        SplashCopperPlanes,a0
    move.l     #HsDisplayBuf,d0
    moveq      #SPLASH_PLANES-1,d7
.ptr:
    PLANE_TO_COPPER d0,a0
    addq.l     #8,a0
    add.l      #SCREEN_WIDTH_BYTE,d0
    dbra       d7,.ptr

    lea        SplashCopperSprites,a0  ; no sprites: every pointer -> NullSprite
    moveq      #8-1,d7
.spr:
    move.l     #NullSprite,d0
    PLANE_TO_COPPER d0,a0
    addq.l     #8,a0
    dbra       d7,.spr

    lea        SplashPalette+2,a0      ; colours 1-7 (colour 0 stays black)
    lea        SplashCopperPal+4+2,a1
    moveq      #7-1,d7
.pal:
    move.w     (a0)+,(a1)
    addq.l     #4,a1
    dbra       d7,.pal

    move.l     #SplashCopper,COP1LC(a6)
    move.w     #0,COPJMP1(a6)
    move.w     #SPLASH_FRAMES,SplashTimer(a5)
    rts

;==============================================================================
; SplashRun  -  One frame of the splash
;
; The fanfare starts on the first frame rather than in SplashInit, because
; audio DMA is still off while GameInitHook runs. When the splash ends the
; fanfare is cut, and COP1LC is pointed at GameCopper: the Copper picks it
; up at the next vertical blank, and on that frame LevelStart draws the level.
;==============================================================================

SplashRun:
    cmp.w      #SPLASH_FRAMES,SplashTimer(a5)
    bne.s      .playing
    PLAYSFX    SfxFanfare
.playing:
    bsr        UpdateControls
    btst       #CONTROLB_FIRE,ControlsTrigger(a5)
    bne.s      .skip
    lea        Keys,a0
    tst.b      KEY_SPACE(a0)
    bne.s      .skip
    tst.b      KEY_RETURN(a0)
    bne.s      .skip
    subq.w     #1,SplashTimer(a5)
    bne.s      .stay
.done:
    clr.w      SplashTimer(a5)
    bsr        AudioStopMod            ; cut the fanfare if it is still playing
    move.l     #GameCopper,COP1LC(a6)
.stay:
    rts

.skip:
    lea        Keys,a0                 ; don't let the key that skipped jump too
    clr.b      KEY_SPACE(a0)
    clr.b      KEY_RETURN(a0)
    bra.s      .done
