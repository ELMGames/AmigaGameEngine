
;==============================================================================
; AMIGA GAME ENGINE
; tools.asm  -  Low-Level Utility Routines
;==============================================================================


;==============================================================================
; CopperSetPtrs  -  Write a run of 32-bit addresses into copper pointer entries
;
; Every screen setup routine needs to patch bitplane (BPLxPTH/L) or sprite
; (SPRxPTH/L) pointer pairs in a copper list.  This is the single shared
; implementation — the entry layout is always:
;   { MOVE #regH, hi_word } { MOVE #regL, lo_word }   (8 bytes per entry)
;
; Arguments:
;   a0 = first copper pointer entry to patch
;   d0 = 32-bit address to write into the first entry
;   d1 = byte stride added to the address per entry
;        (bitplanes: plane width in bytes; sprites all -> NullSprite: 0)
;   d7 = number of entries to patch
;
; Preserves all registers.
;==============================================================================

CopperSetPtrs:
    PUSHM      d0/d7/a0
.csp_loop
    PLANE_TO_COPPER d0,a0          ; write hi word to +2, lo word to +6
    addq.l     #8,a0               ; next copper pointer entry
    add.l      d1,d0               ; next address
    subq.w     #1,d7
    bne.s      .csp_loop
    POPM       d0/d7/a0
    rts


;==============================================================================
; ScalePALFrames  -  Convert a PAL frame count to the current video standard
;
; Durations in this codebase are authored in PAL frames (50 Hz).  On NTSC
; (60 Hz) the same frame count would run ~20% short, so timers that represent
; real-time durations should be armed through this routine.
;
;   In:  d0.w = duration in PAL frames
;   Out: d0.w = equivalent frame count for the detected video standard
;               (unchanged on PAL; multiplied by 6/5 on NTSC)
;
; Requires a5 = Variables (reads IsPAL, set by DetectNTSC).
;==============================================================================

ScalePALFrames:
    tst.w      IsPAL(a5)
    bne.s      .pal
    mulu       #6,d0
    divu       #5,d0
.pal
    rts


;==============================================================================
; TurboClear  -  Fast memory clear using MOVEM
;
; Clears a block of memory to zero as quickly as possible on the 68000 by
; using MOVEM to write 13 registers (52 bytes) per loop iteration.  This is
; significantly faster than a simple CLR.B / DBRA loop because MOVEM amortises
; the instruction fetch overhead across many stores.
;
; The technique works by pre-loading a0-a6 and d0-d6 with zero, then using
; MOVEM.L Rn,-(a0) (pre-decrement store) to write them all in one instruction.
; We clear the buffer backwards (from the end) so that a0 ends up pointing
; at the start - convenient for the caller.
;
; Arguments:
;   a0 = pointer to the START of the block to clear
;   d7 = number of BYTES to clear
;
; Destroys:  a0-a6, d0-d7  (all registers used, then restored by PUSHALL/POPALL)
; Note:  This routine uses PUSHALL / POPALL for register preservation.
;
; Algorithm:
;   1. Advance a0 to point just PAST the end of the buffer:  a0 += d7
;   2. Divide d7 by 52 to get the number of full MOVEM blocks.
;      DIVU #52,d7  -> d7.lo = quotient (blocks), d7.hi = remainder (bytes)
;   3. If quotient > 0, clear it via the pre-decrement MOVEM loop.
;   4. The remainder (0..43 bytes) is extracted from d7.hi (SWAP) and cleared
;      one byte at a time with CLR.B / DBRA.
;
; Why 44 bytes per iteration?
;   MOVEM.L a1-a4/d0-d6,-(a0) stores 11 longwords = 44 bytes in one instruction.
;   a1,a2,a3,a4 = 4 address registers (all zeroed)
;   d0,d1,d2,d3,d4,d5,d6 = 7 data registers (all zeroed)
;   = 11 registers * 4 bytes = 44 bytes per MOVEM
;   a5 (Variables) and a6 (CUSTOM) are NEVER touched or used as zero registers,
;   preventing any possible register leakage or corruption across interrupts.
;==============================================================================

TurboClear:
    PUSHALL                        ; save all registers (a0-a6, d0-d7)

    add.l      d7,a0              ; advance a0 to one byte PAST the end of buffer

    divu       #44,d7             ; d7.lo = number of 44-byte blocks, d7.hi = remainder
    subq.w     #1,d7              ; adjust for DBRA  (DBRA loops until -1, not 0)
    bmi        .remain            ; skip main loop if fewer than 44 bytes total

    ; Zero all the registers we will store (a1-a4, d0-d6)
    sub.l      a1,a1              ; a1 = 0
    sub.l      a2,a2              ; a2 = 0
    sub.l      a3,a3              ; a3 = 0
    sub.l      a4,a4              ; a4 = 0
    moveq      #0,d0              ; d0 = 0
    moveq      #0,d1              ; d1 = 0
    moveq      #0,d2              ; d2 = 0
    moveq      #0,d3              ; d3 = 0
    moveq      #0,d4              ; d4 = 0
    moveq      #0,d5              ; d5 = 0
    moveq      #0,d6              ; d6 = 0

.loop1
    movem.l    a1-a4/d0-d6,-(a0) ; store 11 zero longs (44 bytes) pre-decrement
    dbra       d7,.loop1          ; repeat for each full block

.remain
    ; Handle the remainder bytes (0..43) stored in the HIGH word of d7.
    ; After DIVU, d7 = { remainder[15:0], quotient[15:0] }.
    ; CLR.W d7 zeroes the quotient word, leaving remainder in the high word.
    ; SWAP d7 puts the remainder in the low word for DBRA.
    clr.w      d7                 ; zero the quotient word (low word after DIVU)
    swap       d7                 ; bring remainder to low word
    subq.w     #1,d7              ; adjust for DBRA
    bcs        .done              ; no remainder bytes, we are finished

.loop2
    clr.b      -(a0)              ; clear one byte (pre-decrement from end of buffer)
    dbra       d7,.loop2          ; repeat for each remainder byte

.done
    POPALL                        ; restore all registers
    rts
