
;==============================================================================
; AMIGA GAME ENGINE
; palette_fade.asm  -  Copper-Based Palette Fade Subsystem
;==============================================================================
;
; Provides seamless palette fade-in and fade-out transitions between game
; states.  The Copper drives palette hardware registers (COLOR00-COLOR31)
; every frame; this module manipulates a live working-copy palette in Fast RAM
; and writes it to the active copper list's cpPal / cpLoadingPal block once
; per frame.  Each component (R, G, B) of each colour is stepped one 4-bit
; level per FADE_SPEED frames, ensuring a smooth linear fade independent of
; frame rate variance.
;
; -----------------------------------------------------------------------
; Usage pattern (setup/run pair matching the established game template style):
;
;   ; Fade out to black before a state transition:
;       lea     cpPal,a0            ; or cpLoadingPal for title/loading
;       lea     PalFadeWork,a1
;       moveq   #SCREEN_COLORS,d0
;       bsr     PaletteFadeCapture  ; copy current copper palette into working buf
;       move.w  #FADE_OUT,PalFadeDir(a5)
;       move.w  #1,PalFadeActive(a5)
;       clr.w   PalFadeStep(a5)
;
;   ; Called once per frame from the state's Run handler:
;       tst.w   PalFadeActive(a5)
;       beq.s   .no_fade
;       bsr     PaletteFadeTick     ; returns Z=1 in d0 when fade is complete
;       tst.w   d0
;       beq.s   .no_fade
;       ; fade complete -> transition to next state
;       move.w  #NEXT_STATE,GameStatus(a5)
;   .no_fade
;
; -----------------------------------------------------------------------
;
; Registers used internally: d0-d2, a0-a1  (all saved / restored with PUSHM)
;
; Global prerequisites (always satisfied by the game template framework):
;   a5  = Variables base pointer
;   a6  = $dff000 CUSTOM chip base
;
;==============================================================================


;==============================================================================
; PaletteFadeCapture  -  Snapshot a copper palette block into PalFadeWork
;
; Copies the 32 data words from a copper palette block (the +2-byte data word
; of every { register, data } pair) into the flat PalFadeWork buffer in Fast
; RAM.  Call this once before starting a fade so PaletteFadeTick works from
; the current live colours, not zeros.
;
; Arguments:
;   a0  = pointer to first copper MOVE entry of the palette block
;         (e.g. cpPal or cpLoadingPal — points at the COLORxx word, not data)
;   d7  = number of colour entries to copy (use SCREEN_COLORS = 32)
;
; Preserves: all registers (PUSHM/POPM)
;==============================================================================

PaletteFadeCapture:
    PUSHM       d7/a0/a1
    lea         PalFadeWork,a1
.cap_loop
    move.w      2(a0),(a1)+         ; copy the colour data word (offset +2 in each pair)
    addq.l      #4,a0               ; advance to next { reg, data } copper entry (4 bytes)
    subq.w      #1,d7
    bne.s       .cap_loop
    POPM        d7/a0/a1
    rts


;==============================================================================
; PaletteFadeSetTarget  -  Copy a source palette into PalFadeTarget
;
; Use before a fade-in (FADE_IN direction) to specify what colours to fade
; towards.  For a fade-out (FADE_OUT) this call is not required: the target
; is implicitly all-black ($000).
;
; Arguments:
;   a0  = pointer to flat 16-bit colour array (SCREEN_COLORS words)
;   d7  = number of colour entries (use SCREEN_COLORS = 32)
;
; Preserves: all registers
;==============================================================================

PaletteFadeSetTarget:
    PUSHM       d7/a0/a1
    lea         PalFadeTarget,a1
.tgt_loop
    move.w      (a0)+,(a1)+
    subq.w      #1,d7
    bne.s       .tgt_loop
    POPM        d7/a0/a1
    rts


;==============================================================================
; PaletteFadeTick  -  Advance the palette fade by one frame
;
; Must be called once per frame while PalFadeActive(a5) is non-zero.
; Each call decrements (fade-out) or increments (fade-in) every 4-bit R/G/B
; component of every colour in PalFadeWork by one step, subject to the speed
; throttle (PalFadeSpeed counts down to 0 before a step fires).
;
; After stepping, the updated palette is written into the active copper list
; palette block so the Copper picks it up on the very next frame with zero
; CPU tearing.
;
; Arguments:  (none — all state read from Variables block at a5)
;
; Returns:
;   d0.w  = 0   fade in progress
;   d0.w  = 1   fade complete (PalFadeActive is cleared; caller should
;                              proceed with the state transition)
;
; Modifies: d0  (all others preserved via PUSHM/POPM)
;==============================================================================

PaletteFadeTick:
    PUSHM       d1-d4/d7/a0-a2

    ; --- Speed throttle: only step every PalFadeSpeed frames ----------------
    subq.w      #1,PalFadeSpeedCount(a5)
    bgt         .no_step                ; count > 0: still waiting, skip step
    move.w      PalFadeSpeed(a5),PalFadeSpeedCount(a5) ; reload counter
    ; --- Time for a colour step -- fall through ------------------------------

    ; --- Step all 32 colours -------------------------------------------------
    ; For each colour: separate R, G, B nibbles, move each one step toward
    ; the corresponding nibble in PalFadeTarget ($000 for FADE_OUT).
    ;
    ; Amiga OCS colour word layout: $0RGB  (bits 11:8=R, 7:4=G, 3:0=B)
    ;
    ; Strategy (fully on the 68000, no multiply/divide):
    ;   1. Read PalFadeWork colour and PalFadeTarget colour.
    ;   2. For each nibble: if work > target, decrement; if work < target, increment.
    ;   3. Write back to PalFadeWork.

    lea         PalFadeWork,a0
    lea         PalFadeTarget,a1
    moveq       #SCREEN_COLORS-1,d7     ; loop counter (d2/d3 used as scratch by FADE_STEP_*)

.step_loop
    move.w      (a0),d0                 ; current working colour ($0RGB)
    move.w      (a1)+,d1                ; target colour

    ; Step each channel toward the target one nibble at a time
    FADE_STEP_RED   d0,d1               ; bits 11:8
    FADE_STEP_GREEN d0,d1               ; bits 7:4
    FADE_STEP_BLUE  d0,d1               ; bits 3:0

    move.w      d0,(a0)+                ; write updated colour back
    dbra        d7,.step_loop

    ; Increment the step counter
    addq.w      #1,PalFadeStep(a5)

.no_step
    ; --- Write PalFadeWork into the active copper palette block --------------
    lea         PalFadeWork,a0
    move.l      PalFadeCopper(a5),a1    ; caller set this to cpPal or cpLoadingPal
    moveq       #SCREEN_COLORS-1,d2
.write_loop
    move.w      (a0)+,2(a1)             ; write into +2 data word of each copper MOVE pair
    addq.l      #4,a1
    dbra        d2,.write_loop

    ; --- Check for completion ------------------------------------------------
    ; The fade is done when PalFadeWork equals PalFadeTarget for all 32 entries.
    lea         PalFadeWork,a0
    lea         PalFadeTarget,a1
    moveq       #SCREEN_COLORS-1,d2
.check_loop
    move.w      (a0)+,d0
    cmp.w       (a1)+,d0
    bne.s       .not_done               ; mismatch — still fading
    dbra        d2,.check_loop

    ; All colours reached target — fade is complete
    clr.w       PalFadeActive(a5)
    moveq       #1,d0                   ; return 1 = done
    bra.s       .exit

.not_done
    moveq       #0,d0                   ; return 0 = still in progress

.exit
    POPM        d1-d4/d7/a0-a2
    rts


;==============================================================================
; PaletteFadeOut  -  Convenience routine: start a fade-to-black
;
; Captures the current copper palette and starts fading it to all-black.
; The caller should poll PaletteFadeTick each frame until it returns 1,
; then perform the state transition.
;
; Arguments:
;   a0  = pointer to the active copper palette block (cpPal or cpLoadingPal)
;   d0  = speed (1 = fastest — one step per frame; 2 = half speed, etc.)
;         Use FADE_SPEED_NORMAL, FADE_SPEED_SLOW, or FADE_SPEED_FAST constants.
;
; Preserves: all registers
;==============================================================================

PaletteFadeOut:
    PUSHM       d7/a0/a1

    ; Set the target to all-black ($000 for all 32 entries)
    lea         PalFadeTarget,a1
    moveq       #SCREEN_COLORS-1,d7
.clr_target
    clr.w       (a1)+
    dbra        d7,.clr_target

    ; Capture the current copper palette as the starting point
    move.l      a0,PalFadeCopper(a5)    ; remember which copper block to update
    moveq       #SCREEN_COLORS,d7
    bsr         PaletteFadeCapture      ; a0 still points at copper block

    ; Arm the fade engine
    move.w      d0,PalFadeSpeed(a5)
    move.w      d0,PalFadeSpeedCount(a5)
    clr.w       PalFadeStep(a5)
    move.w      #1,PalFadeActive(a5)

    POPM        d7/a0/a1
    rts


;==============================================================================
; PaletteFadeIn  -  Convenience routine: fade from black into a target palette
;
; Zeroes PalFadeWork (start from black) and fades up to the palette supplied
; in a1.  Useful for revealing a new state after cutting to black.
;
; Arguments:
;   a0  = pointer to the active copper palette block (cpPal or cpLoadingPal)
;   a1  = pointer to a flat array of SCREEN_COLORS 16-bit target colours
;   d0  = speed (same units as PaletteFadeOut)
;
; Preserves: all registers
;==============================================================================

PaletteFadeIn:
    PUSHM       d7/a0/a1

    ; Set the target palette
    move.l      a0,PalFadeCopper(a5)
    move.l      a1,a0                   ; PaletteFadeSetTarget reads its source from a0
    moveq       #SCREEN_COLORS,d7
    bsr         PaletteFadeSetTarget    ; copies a1[] -> PalFadeTarget

    ; Zero the working palette so we start from black
    lea         PalFadeWork,a0
    moveq       #SCREEN_COLORS-1,d7
.zero_loop
    clr.w       (a0)+
    dbra        d7,.zero_loop

    ; Also zero the copper palette block so frame 0 starts 100% black (no flash)
    move.l      PalFadeCopper(a5),a0
    moveq       #SCREEN_COLORS-1,d7
.zero_copper
    clr.w       2(a0)
    addq.l      #4,a0
    dbra        d7,.zero_copper

    ; Arm the fade engine
    move.w      d0,PalFadeSpeed(a5)
    move.w      d0,PalFadeSpeedCount(a5)
    clr.w       PalFadeStep(a5)
    move.w      #1,PalFadeActive(a5)

    POPM        d7/a0/a1
    rts


;==============================================================================
; PaletteFadeStop  -  Immediately stop any running fade without transitioning
;
; Clears PalFadeActive.  The copper palette is left at whatever intermediate
; state it was in — useful for emergency aborts (e.g. ESC during a fade).
;
; Preserves: all registers
;==============================================================================

PaletteFadeStop:
    clr.w       PalFadeActive(a5)
    rts

