
;==============================================================================
; AMIGA GAME ENGINE
; keyboard.asm  -  CIA-A Keyboard Interrupt Handler
;==============================================================================
;
; The Amiga keyboard controller communicates with the computer via a serial
; protocol through CIA-A (Complex Interface Adapter at $BFE001).  Each key
; press or release generates an 8-bit scan-code sent serially on the SP (Serial
; Port) pin of CIA-A.
;
; Hardware flow:
;   1. Keyboard controller pulls SP line low (start bit).
;   2. 8 data bits are clocked in, MSB first, via the CIA-A SDR (Serial Data
;      Register, ciaSDR / CIASDR).
;   3. CIA-A sets the SP interrupt flag (CIAICRB_SP) in CIAICR.
;   4. This triggers a level-2 interrupt through CIA-A -> INT2 -> ports interrupt
;      ($68 = level 2 interrupt vector).  INTENA bit INTF_PORTS must be set.
;   5. The handler reads the scan-code, bit-inverts and rotates it to get the
;      standard Amiga key-code, stores it in the Keys[] buffer, then starts the
;      handshake: it switches the serial port to output, which pulls the data
;      line low, and starts CIA-A timer B as a ~90 us one-shot.
;   6. When timer B runs out it raises the same level-2 interrupt, and the
;      handler switches the serial port back to input, ending the handshake.
;      Nothing waits inside the interrupt.
;
; The Keys[] buffer is 256 bytes (one byte per possible key-code).
; A non-zero byte means that key is currently pressed.
; The keyboard interrupt sets Keys[code] = $ff (key down) or $00 (key up)
; based on bit 7 of the received byte (0=make/press, 1=break/release).
;
;==============================================================================


;==============================================================================
; KeyboardInit  -  Install the keyboard interrupt handler
;
; Sets up the CIA-A serial interrupt and installs KeyboardInterrupt at vector $68
; (the level-2 "ports" interrupt on the Amiga).
;
; Before installing, it:
;   - Zeroes the 256-byte Keys buffer to clear stale key states
;   - Clears any pending CIA-A interrupt by reading CIAICR
;   - Sets CIA-A to serial INPUT mode (CIACRAF_SPMODE = 0 in CIACRA)
;   - Saves CIA-A timer B (for KeyboardRemove) and sets it up as the
;     handshake's one-shot timer
;   - Clears any pending PORTS interrupt in INTREQ
;   - Enables the PORTS interrupt in INTENA
;
; Handles 68010+ relocated VBR via VBRBase (set by SystemSave).
;
; In:       none
; Out:      none
; Destroys: none (preserves all registers)
;==============================================================================

KeyboardInit:
    movem.l    d0-a6,-(a7)            ; save all regs (called from Init, must be clean)

    ; Clear the 256-byte key buffer so no stale down-states survive a reset
    lea        Keys,a0
    moveq      #64-1,d0               ; 64 longwords = 256 bytes
.clr_keys
    clr.l      (a0)+
    dbra       d0,.clr_keys

    ; Handles 68010+ relocated VBR (VBRBase set by SystemSave via GetVBR).
    move.l     VBRBase,a0             ; a0 = VBR base

    ; Save CIA-A timer B as the OS left it, then make it the handshake timer:
    ; one-shot, counting E-clock ticks, stopped. Only the low byte of the
    ; count is written here; the interrupt writes the high byte for each key,
    ; which in one-shot mode loads the count and starts the timer.
    lea        $bfe001,a1             ; CIA-A
    move.b     ciacrb(a1),KeySavedCRB
    move.b     ciatbhi(a1),KeySavedTB
    move.b     ciatblo(a1),KeySavedTB+1
    move.b     #CIACRBF_RUNMODE,ciacrb(a1)
    move.b     #KEY_HANDSHAKE_TICKS&$ff,ciatblo(a1)

    ; Enable the CIA-A serial-port interrupt (a key event) and the timer B
    ; interrupt (the handshake is over).  CIAICRF_SETCLR = bit 7 = 1 (set mode).
    move.b     #CIAICRF_SETCLR|CIAICRF_SP|CIAICRF_TB,(ciaicr+$bfe001)

    tst.b      (ciaicr+$bfe001)       ; dummy read to acknowledge/clear any pending interrupt
    tst.b      (ciasdr+$bfe001)       ; dummy read to clear serial data register

    ; Set CIA-A serial port to INPUT mode (receive keyboard data).
    ; CIACRAF_SPMODE = bit 6 of CIACRA.  Clear it for input.
    and.b      #~(CIACRAF_SPMODE),(ciacra+$bfe001)

    ; Clear any stale PORTS interrupt request in the custom chip.
    move.w     #INTF_PORTS,(CUSTOM+INTREQ)

    ; Install our handler and enable the PORTS interrupt channel.
    move.l     #KeyboardInterrupt,$68(a0)
    move.w     #INTF_SETCLR|INTF_INTEN|INTF_PORTS,(CUSTOM+INTENA)

    movem.l    (a7)+,d0-a6
    rts


;==============================================================================
; KeyboardInterrupt  -  Level-2 CIA-A keyboard interrupt service routine
;
; Fires on every key press or release.  Reads the raw scan-code from CIA-A,
; converts it to the standard Amiga key-code format, and stores it in Keys[].
;
; The raw byte received from the keyboard controller is:
;   bits 7:1 = scan-code (7 bits, MSB first)
;   bit  0   = make/break  (0 = key pressed, 1 = key released)
; The entire byte is transmitted with all bits inverted (active-low protocol).
;
; Conversion:
;   1. Read SDR (serial data register) - gives inverted bits, LSB first.
;   2. NOT d0  - un-invert all bits.
;   3. ROR.B #1  - rotate right 1 to move the make/break bit into bit 7,
;                  and shift the 7-bit scan-code into bits 6:0.
;   4. SPL d1  - d1 = $ff if result was positive (bit 7 = 0 = key down),
;                d1 = $00 if result was negative  (bit 7 = 1 = key up).
;   5. AND #$7f  - mask off the make/break bit to get clean 7-bit code.
;   6. Keys[code] = d1  (non-zero for pressed, zero for released).
;
; After reading, the handler must handshake to tell the keyboard controller it
; can send the next code: the data line must be held low for at least 85 us.
; The handler switches the serial port to OUTPUT mode, which pulls the line
; low, and starts CIA-A timer B as a one-shot of KEY_HANDSHAKE_TICKS E-clock
; ticks. When the timer runs out, the next pass through this handler sees the
; timer B flag and switches the port back to INPUT. The CIA-A ICR is read
; once, because reading it clears every flag: both sources are tested from
; that one read.
;
; Finally, the PORTS interrupt is cleared in INTREQ and the chain patch
; location is NOPped (KeyboardPatchPtr can be modified to chain to another
; handler if needed).
;
; Preserves: d0-d2, a0-a2  (saved on stack).
;==============================================================================

KEY_HANDSHAKE_TICKS = 64             ; ~90 us of E-clock (PAL 709 kHz, NTSC 716 kHz)

KeyboardInterrupt:
    movem.l    d0-d2/a0-a2,-(a7)     ; save working registers

    ; --- Check that this is really a CIA-A SP interrupt, not another level-2 source ---
    lea        CUSTOM,a0              ; custom chip base
    move.w     intreqr(a0),d0         ; read interrupt request flags
    btst       #INTB_PORTS,d0         ; is the PORTS bit set?
    beq        .end                   ; spurious interrupt, not from CIA-A, bail out

    lea        $bfe001,a1             ; CIA-A base address
    move.b     ciaicr(a1),d2          ; read once: this clears every CIA-A flag

    ; --- Timer B ran out: the handshake has lasted long enough ---
    btst       #CIAICRB_TB,d2
    beq.s      .no_release
    and.b      #~(CIACRAF_SPMODE),ciacra(a1)  ; serial input again: line released
.no_release

    btst       #CIAICRB_SP,d2         ; was a key code received?
    beq        .end                   ; no, done

    ; --- Read and convert scan-code ---
    moveq      #0,d0
    move.b     ciasdr(a1),d0          ; read raw inverted byte from serial register
    not.b      d0                     ; un-invert bits: now 0=idle, 1=active
    ror.b      #1,d0                  ; rotate make/break into bit 7, scan-code into 6:0

    ; Set d1 = $ff if key pressed (bit 7 was 0 before ROR -> sign positive -> SPL sets $ff),
    ; or  d1 = $00 if key released (bit 7 was 1 -> negative -> SPL clears to $00).
    spl        d1                     ; S(et on)PL(us): d1 = (N==0) ? $ff : $00

    ; Mask off the make/break bit to get a clean 7-bit scan-code (0..127)
    and.w      #$7f,d0

    ; Store the key state in the global Keys[] array (Fast RAM)
    lea        Keys,a2
    move.b     d1,(a2,d0.w)           ; Keys[scan_code] = $ff (down) or $00 (up)

    ; --- Start the handshake: pull the data line low, start the timer ---
    ; Serial output mode drives the line low, acknowledging the byte. Writing
    ; timer B's high byte loads the one-shot count and starts it; its
    ; interrupt, about 90 us later, releases the line (above).
    or.b       #(CIACRAF_SPMODE),ciacra(a1)
    move.b     #KEY_HANDSHAKE_TICKS>>8,ciatbhi(a1)

.end
    ; Clear the PORTS interrupt request flag in the custom chip
    move.w     #INTF_PORTS,intreq(a0)
    tst.w      intreqr(a0)            ; dummy read to ensure write has propagated (bus timing)

    ; KeyboardPatchPtr: three NOPs that can be overwritten at runtime to chain
    ; this interrupt handler to another level-2 handler if required.
; Destroys: none (preserves all registers)
KeyboardPatchPtr:
    nop
    nop
    nop

    movem.l    (a7)+,d0-d2/a0-a2
    rte                                ; return from interrupt


;==============================================================================
; KeyboardRemove  -  Give CIA-A timer B back as the OS left it
;
; Called from QuitToOS with interrupts off, before SystemRestore puts the OS
; level-2 vector back. Releases the data line in case a handshake was still
; running, then restores timer B's count and control register. The timer B
; interrupt enable is left on: the CIA's enable mask cannot be read, so its
; original state is unknown, and a stopped timer raises no interrupt.
;
; Destroys: none (preserves all registers)
;==============================================================================

KeyboardRemove:
    movem.l    d0/a1,-(a7)
    lea        $bfe001,a1
    and.b      #~(CIACRAF_SPMODE),ciacra(a1)  ; serial input: line released
    clr.b      ciacrb(a1)             ; stop timer B, continuous mode
    move.b     KeySavedTB+1,ciatblo(a1)
    move.b     KeySavedTB,ciatbhi(a1) ; stopped: this only sets the count
    move.b     KeySavedCRB,d0
    or.b       #CIACRBF_LOAD,d0       ; reload the count, then the OS's mode
    move.b     d0,ciacrb(a1)
    movem.l    (a7)+,d0/a1
    rts

KeySavedTB:     dc.w    0             ; CIA-A timer B count at takeover
KeySavedCRB:    dc.b    0             ; CIA-A control register B at takeover
                even

