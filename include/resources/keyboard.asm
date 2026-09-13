
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
;      standard Amiga key-code, stores it in the Keys[] buffer, then handshakes
;      by briefly setting CIA-A control register to output mode and back.
;
; The Keys[] buffer is 256 bytes (one byte per possible key-code).
; A non-zero byte means that key is currently pressed.
; The keyboard interrupt sets Keys[code] = $ff (key down) or $00 (key up)
; based on bit 7 of the received byte (0=make/press, 1=break/release).
;
;==============================================================================
    incdir  "include"
    include    "hardware/cia.i"     ; CIA register offsets and bit definitions


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
;   - Clears any pending PORTS interrupt in INTREQ
;   - Enables the PORTS interrupt in INTENA
;
; Handles 68010+ relocated VBR via VBRBase (set by SystemSave).
; Preserves all registers.
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

    ; Enable CIA-A serial-port interrupt so we get a signal on each key event.
    ; CIAICRF_SETCLR = bit 7 = 1 (set mode).  CIAICRF_SP = bit 3 (serial port).
    ; Writing this to CIAICR enables the SP interrupt source.
    move.b     #CIAICRF_SETCLR|CIAICRF_SP,(ciaicr+$bfe001)

    tst.b      (ciaicr+$bfe001)       ; dummy read to acknowledge/clear any pending interrupt
    tst.b      (ciasdr+$bfe001)       ; dummy read to clear serial data register

    ; Set CIA-A serial port to INPUT mode (receive keyboard data).
    ; CIACRAF_SPMODE = bit 6 of CIACRA.  Clear it for input.
    and.b      #~(CIACRAF_SPMODE),(ciacra+$bfe001)

    ; Clear any stale PORTS interrupt request in the custom chip.
    move.w     #INTF_PORTS,(intreq+$dff000)

    ; Install our handler and enable the PORTS interrupt channel.
    move.l     #KeyboardInterrupt,$68(a0)
    move.w     #INTF_SETCLR|INTF_INTEN|INTF_PORTS,(intena+$dff000)

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
; After reading, the handler must perform a hardware handshake to tell the
; keyboard controller it can send the next code.  This is done by briefly
; setting the CIA-A serial port to OUTPUT mode (3 raster-line delay) then
; back to INPUT mode.
;
; Finally, the PORTS interrupt is cleared in INTREQ and the chain patch
; location is NOPped (KeyboardPatchPtr can be modified to chain to another
; handler if needed).
;
; Preserves: d0-d1, a0-a2  (saved on stack).
;==============================================================================

KeyboardInterrupt:
    movem.l    d0-d1/a0-a2,-(a7)     ; save working registers

    ; --- Check that this is really a CIA-A SP interrupt, not another level-2 source ---
    lea        $dff000,a0             ; custom chip base
    move.w     intreqr(a0),d0         ; read interrupt request flags
    btst       #INTB_PORTS,d0         ; is the PORTS bit set?
    beq        .end                   ; spurious interrupt â€” not from CIA-A, bail out

    lea        $bfe001,a1             ; CIA-A base address
    move.b     ciaicr(a1),d0          ; read and clear CIA-A interrupt flags
    btst       #CIAICRB_SP,d0         ; was it the serial-port interrupt?
    beq        .end                   ; no (timer or other CIA source), bail out

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

    ; --- Start hardware handshake: pull SP line low ---
    ; Tell keyboard we got the byte.  Set SPMODE bit (output mode) in CIACRA.
    ; CIA-A will drive the SP line low, acknowledging the byte.
    or.b       #(CIACRAF_SPMODE),ciacra(a1)

    ; --- Hardware handshake: wait ~3 raster lines then release ---
    ; The keyboard controller needs to see the SP line held low for at least
    ; 75 microseconds before it will accept the next key-code.
    ; We spin for 3 raster-line changes (each line = ~64 us at PAL timing).
    moveq      #3-1,d1                ; loop 3 times
.wait1
    move.b     vhposr(a0),d0          ; read current raster position (V/H low byte)
.wait2
    cmp.b      vhposr(a0),d0          ; wait until raster position changes (one line passed)
    beq        .wait2
    dbf        d1,.wait1

    ; Release handshake: set CIA-A back to input mode
    and.b      #~(CIACRAF_SPMODE),ciacra(a1)  ; clear SPMODE -> serial input again

.end
    ; Clear the PORTS interrupt request flag in the custom chip
    move.w     #INTF_PORTS,intreq(a0)
    tst.w      intreqr(a0)            ; dummy read to ensure write has propagated (bus timing)

    ; KeyboardPatchPtr: three NOPs that can be overwritten at runtime to chain
    ; this interrupt handler to another level-2 handler if required.
KeyboardPatchPtr:
    nop
    nop
    nop

    movem.l    (a7)+,d0-d1/a0-a2
    rte                                ; return from interrupt

