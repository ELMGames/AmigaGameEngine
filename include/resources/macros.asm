
;==============================================================================
; AMIGA GAME ENGINE
; macros.asm  -  Assembly Macros
;==============================================================================
;
; All macros used throughout the codebase are defined here.
; This file is INCLUDEd near the top of main.asm before any code is assembled.
;
; DEVPAC/ASM-ONE macro syntax:
;   MACRO name ... ENDM        - defines the macro body
;   \1, \2, ...                - positional arguments
;   .\@                        - unique local label suffix (expanded per invocation)
;
; Register convention (for context when reading macro bodies):
;   a5 = Variables base pointer   a6 = $dff000 (CUSTOM chip registers)
;   a4 = current player struct    a3 = current actor struct
;   d7 = general loop counter     sp = system stack pointer
;
;==============================================================================


;==============================================================================
; Stack save/restore macros
;
; The 68000 has no PUSH/POP instructions; these macros simulate them using
; MOVEM and pre-decrement / post-increment addressing.
;
; PUSH / POP      - save / restore a single register (as a longword)
; PUSHM / POPM    - save / restore a register list (MOVEM syntax: d0-d2/a0/a1)
; PUSHMOST        - save d0-a4 (all data regs and most address regs); used by
;                   subroutines that must preserve the caller's context but do
;                   not need to preserve a5/a6 (which are global constants).
; POPMOST         - matching restore for PUSHMOST
; PUSHALL         - save everything (d0-a6); used in interrupt handlers where
;                   ANY register could be in use by the interrupted code.
; POPALL          - matching restore for PUSHALL
;
; Stack grows downward: MOVEM Rn,-(sp) decrements sp THEN stores (pre-dec).
;                        MOVEM (sp)+,Rn loads THEN increments (post-inc).
;==============================================================================

PUSH               MACRO
                   move.l     \1,-(sp)
                   ENDM

POP                MACRO
                   move.l     (sp)+,\1
                   ENDM

PUSHM              MACRO
                   movem.l    \1,-(sp)
                   ENDM

POPM               MACRO
                   movem.l    (sp)+,\1
                   ENDM

PUSHMOST           MACRO
                   movem.l    d0-a4,-(sp)   ; save d0-d7, a0-a4 (11 regs = 44 bytes)
                   ENDM

POPMOST            MACRO
                   movem.l    (sp)+,d0-a4
                   ENDM

PUSHALL            MACRO
                   movem.l    d0-a6,-(sp)   ; save all 15 regs (d0-d7, a0-a6 = 60 bytes)
                   ENDM

POPALL             MACRO
                   movem.l    (sp)+,d0-a6
                   ENDM


;==============================================================================
; JMPINDEX  -  Indexed jump dispatch (computed GOTO / switch-case)
;
; Implements a jump table using PC-relative word offsets.  Used wherever the
; code branches on a small integer state value (action state, block type, etc.).
;
; Argument:  \1 = a DATA register containing the 0-based index (word).
;            The index register is destroyed (doubled in place).
;
; Usage pattern (example from PlayerLogic):
;
;   move.w  ActionStatus(a5),d0
;   JMPINDEX d0
; .i
;   dc.w    HandlerA-.i      ; index 0
;   dc.w    HandlerB-.i      ; index 1
;   dc.w    HandlerC-.i      ; index 2
;
; How it works:
;   1. Double the index (word size = 2 bytes per entry).
;   2. Read the signed word offset from the table (PC-relative).
;   3. Add that offset to the PC (which already points at the table base .i)
;      and jump there.
;
; The generated code sequence is:
;   ADD.W  d0,d0              ; index *= 2  (byte offset into word table)
;   MOVE.W .jmplist(pc,d0.w),d0   ; read signed 16-bit offset
;   JMP    .jmplist(pc,d0.w)      ; jump to handler
; .jmplist:
;   dc.w ...
;
; IMPORTANT: The label ".\@jmplist" is unique per invocation (.\@ = unique suffix)
;            so multiple JMPINDEX macros in the same source file do not clash.
;==============================================================================

JMPINDEX           MACRO
                   add.w      \1,\1                       ; index * 2 (word entries)
                   move.w     .\@jmplist(pc,\1.w),\1      ; load signed word offset
                   jmp        .\@jmplist(pc,\1.w)         ; jump through offset
.\@jmplist
                   ENDM


;==============================================================================
; RANDOMWORD  -  16-bit pseudo-random number generator
;
; Generates a new 16-bit pseudo-random value in the upper word of d0.
; Uses a simple multiply-add LFSR/LCG hybrid seeded from RandomSeed(a5).
;
; Algorithm:
;   seed = (seed_hi * $9D3D) + seed       (treating seed as two 16-bit halves)
;   result = upper 16 bits of new seed
;
; Destroys: d0 (result in upper word, lower word = 0 after SWAP/CLR)
; Preserves: d1 (saved/restored on stack)
; Requires:  a5 = Variables base pointer
;
; After the macro, d0 contains the 16-bit random value in its LOW word
; (due to the SWAP at the end).
;==============================================================================

RANDOMWORD         MACRO
                   move.l     d1,-(sp)           ; preserve d1
                   move.l     RandomSeed(a5),d0  ; load current 32-bit seed
                   move.l     d0,d1
                   swap.w     d0                 ; d0 = high word of seed
                   mulu.w     #$9D3D,d1          ; multiply low word by magic constant
                   add.l      d1,d0              ; add to produce new seed
                   move.l     d0,RandomSeed(a5)  ; store new seed
                   clr.w      d0                 ; clear low word
                   swap.w     d0                 ; d0.w = random value (was high word)
                   move.l     (sp)+,d1           ; restore d1
                   ENDM


;==============================================================================
; PLANE_TO_COPPER  -  Write a 32-bit address into a copper list bitplane entry
;
; The Copper stores 32-bit addresses split across two consecutive instruction
; pairs.  Each pair is  { MOVE #reg, hi_word } { MOVE #reg+4, lo_word }.
; In memory this looks like:
;   +0  reg_number (word)        <- written by Copper
;   +2  high 16 bits of address  <- this is what we write to +2(\2)
;   +4  reg_number+4 (word)
;   +6  low  16 bits of address  <- this is what we write to +6(\2)
;
; Arguments:
;   \1 = data register holding the 32-bit address (address is preserved via SWAP)
;   \2 = address register pointing to the copper list plane entry (e.g. cpPlanes)
;
; The SWAP / SWAP trick: SWAP gives us the two halves in sequence without
; needing a second register.  After the macro, \1 is unchanged (swapped twice).
;==============================================================================

PLANE_TO_COPPER    MACRO
                   move.w     \1,6(\2)    ; write low  16 bits to copper entry low  word
                   swap       \1          ; bring high 16 bits to lower word
                   move.w     \1,2(\2)    ; write high 16 bits to copper entry high word
                   swap       \1          ; restore \1 to original value
                   ENDM


;==============================================================================
; Blitter wait macros  (WAITBLIT / WAITBLITN)
;
; The Amiga blitter is an autonomous DMA device.  The CPU must not access
; blitter registers while a blit is in progress or data corruption will result.
;
; Wait sequence:
;   1. Dummy-read DMACONR — the first read after BLTSIZE is unreliable on some
;      OCS chipsets, so we discard it and then read the real status.
;   2. Test DMACONR bit 14 (BLTDONE): 1 = busy, 0 = idle.
;   3. Spin until the bit clears.
;
; BLITHOG (DMAF_BLITHOG = $0400) is intentionally NOT set here.  Setting it
; gives the blitter near-exclusive chip-bus access, which starves Paula's audio
; DMA and causes music to drop out during every blitter operation.  Without
; BLITHOG the blitter and audio share the bus normally; blits take marginally
; longer but audio remains uninterrupted.
;
; WAITBLIT and WAITBLITN are functionally identical; the two names allow
; a distinction between "wait before starting a new blit" (WAITBLIT) and
; "wait before using blitter output data" (WAITBLITN) if needed.
;==============================================================================

WAITBLIT           MACRO
                   tst.w      DMACONR(a6)                   ; Flush bus write pipeline & sync Agnus
.\@                btst       #6,DMACONR(a6)                ; Test DMACONR bit 6 (blitter busy)
                   bne.b      .\@                           ; Loop while busy
                   ENDM

WAITBLITN          MACRO
                   tst.w      DMACONR(a6)                   ; Flush bus write pipeline & sync Agnus
.\@                btst       #6,DMACONR(a6)                ; Test DMACONR bit 6 (blitter busy)
                   bne.b      .\@                           ; Loop while busy
                   ENDM


;==============================================================================
; ROTATE_LONG  -  Rotate an array of longwords in-place (cyclic rotation right)
;
; Performs an in-place cyclic rotation of \2 longwords starting at address
; register \1.  The first element is moved to the end and everything else
; shifts one position towards the front.
;
; Uses MOVEM for bulk register-based copy (much faster than a loop on 68000).
; Separate cases are generated for each supported count (2 through 7) at
; assembly time via IFEQs - these expand to inline code with no loop overhead.
;
; Argument:
;   \1 = address register pointing to the array base
;   \2 = number of longwords in the array (2..7, evaluated at assembly time)
;
; Note: \1 is modified during the operation and then restored.
; The IFEQs are mutually exclusive (only one will be true for a given \2).
;
; Example with \2=3 (array of 3 longs: [A, B, C]):
;   d7 = A  (save last element first, which is at offset (\2-1)*4)
;   MOVEM loads [A, B] from (\1)+  -> advances \1 by 8
;   Add 4 to \1 (skip one slot for insert)
;   MOVEM stores [A, B] at -(\1)   -> [_, A, B] with \1 back to original+8
;   Store d7 (=A) at -(\1)         -> [A, A, B]  <- wrong, let me re-read...
;
; Actually: saves the LAST element ((\2-1)*4(\1)), shifts remaining elements
; forward by one slot (toward higher addresses), then puts the saved element
; at the beginning.  Result: [last, first, second, ...] i.e. rotate-right.
;==============================================================================

ROTATE_LONG        MACRO

                   ifeq       \2-7
                   move.l     (\2-1)*4(\1),d7
                   movem.l    (\1)+,d0/d1/d2/d3/d4/d5
                   addq.l     #4,\1
                   movem.l    d0/d1/d2/d3/d4/d5,-(\1)
                   move.l     d7,-(\1)
                   endif

                   ifeq       \2-6
                   move.l     (\2-1)*4(\1),d7
                   movem.l    (\1)+,d0/d1/d2/d3/d4
                   addq.l     #4,\1
                   movem.l    d0/d1/d2/d3/d4,-(\1)
                   move.l     d7,-(\1)
                   endif

                   ifeq       \2-5
                   move.l     (\2-1)*4(\1),d7
                   movem.l    (\1)+,d0/d1/d2/d3
                   addq.l     #4,\1
                   movem.l    d0/d1/d2/d3,-(\1)
                   move.l     d7,-(\1)
                   endif

                   ifeq       \2-4
                   move.l     (\2-1)*4(\1),d7
                   movem.l    (\1)+,d0/d1/d2
                   addq.l     #4,\1
                   movem.l    d0/d1/d2,-(\1)
                   move.l     d7,-(\1)
                   endif

                   ifeq       \2-3
                   move.l     (\2-1)*4(\1),d7
                   movem.l    (\1)+,d0/d1
                   addq.l     #4,\1
                   movem.l    d0/d1,-(\1)
                   move.l     d7,-(\1)
                   endif

                   ifeq       \2-2
                   movem.l    (\1)+,d0/d1    ; load both longs, advance \1
                   exg        d0,d1          ; swap them
                   movem.l    d0/d1,-(\1)    ; store back (now rotated)
                   endif

                   ENDM


;==============================================================================
; KeyTest  -  Test a key and set a bit in d0
;
; Used exclusively inside ReadControls to build the control byte.
;
; Arguments:
;   \1 = keyboard scan-code (byte offset into Keys[] array; a0 = Keys base)
;   \2 = bit number to set in d0 if the key is pressed
;
; If Keys[\1] is non-zero (key held), bit \2 of d0 is set via BSET.
; d0 accumulates all pressed keys across multiple KeyTest expansions.
;
; The local label .\@notpressed gets a unique suffix per call to prevent
; multiple instances in the same routine from clashing.
;==============================================================================

KeyTest            MACRO
                   tst.b      (\1,a0)            ; is Keys[scan_code] non-zero?
                   beq.b      .\@notpressed       ; branch if key not pressed
                   bset       #\2,d0              ; set corresponding control bit
.\@notpressed
                   ENDM


;==============================================================================
; TODECIMAL  -  Convert a binary integer to packed BCD digits in a register
;
; Converts the value in \1 to \2+1 decimal digits stored packed (4 bits each)
; in the LOW word of \3.  Used by DrawLevelCounter to extract digit values
; for font rendering.
;
; Arguments:
;   \1 = source value register (DESTROYED - divided repeatedly)
;   \2 = number of digits - 1  (e.g. 3 for a 4-digit number, passed to MOVEQ)
;   \3 = destination register  (receives packed BCD result)
;
; Algorithm (per digit, repeated \2+1 times):
;   DIVU #10, \1   -> quotient in upper word, remainder (digit) in lower word
;   SWAP \1        -> bring remainder to lower word
;   OR.B \1, \3    -> OR the digit into the low byte of \3
;   CLR.W \1       -> zero the remainder word
;   SWAP \1        -> restore quotient for next iteration
;   ROR.W #4, \3   -> shift \3 right 4 bits (make room for next digit)
;
; After the loop, \3 contains the digits arranged with the most-significant
; digit in the highest nibble of the word.
;==============================================================================

TODECIMAL          MACRO
                   moveq      #\2,d7             ; loop counter = digit count - 1
                   moveq      #0,\3              ; clear destination
.\@loop            divu       #10,\1             ; \1.hi = remainder (next digit), \1.lo = quotient
                   swap       \1                 ; bring remainder to low word
                   or.b       \1,\3              ; OR digit into low byte of result
                   clr.w      \1                 ; clear remainder
                   swap       \1                 ; restore quotient
                   ror.w      #4,\3              ; shift result right one nibble
                   dbra       d7,.\@loop
                   ENDM


;==============================================================================
; DECIMAL2  -  Extract two decimal digits from a value
;
; Simpler two-digit variant: extracts the tens digit into the high byte of \2
; and the units digit into the low byte.
;
; Arguments:
;   \1 = source value (DESTROYED)
;   \2 = destination register (two digit values packed as { tens, units })
;==============================================================================

DECIMAL2           MACRO
                   moveq      #0,\2              ; clear destination
                   divu       #10,\1             ; divide by 10
                   swap       \1                 ; remainder = units digit
                   move.w     \1,\2              ; store units in low word of \2
                   swap       \2                 ; move units to high word
                   clr.w      \1                 ; clear remainder
                   swap       \1                 ; restore quotient (= tens digit)
                   divu       #10,\1             ; divide again
                   swap       \1                 ; remainder = tens digit
                   move.w     \1,\2              ; store tens in low word of \2
                   ENDM


;==============================================================================
; LVLFNT  -  Blit one row of a font digit onto the level counter graphic
;
; Used inside a loop in DrawLevelCounter to composite a decimal digit from
; LevelFont onto the LevelCountTemp working buffer.
;
; The level counter UI element shows the current level number.  Each digit is
; read from LevelFont (a 5-plane bitmap font, LEVEL_FONT_WIDTH_BYTE bytes wide)
; and OR-masked onto the corresponding position in LevelCountTemp.
;
; Arguments:
;   \1 = bitplane index (0..4)
;
; Register context assumed:
;   a0  = pointer to current row/plane of LevelCountTemp (destination)
;   a2  = pointer to current row of LevelFont (source digit)
;   d5  = pre-computed NOT of the font mask (all 5 planes OR-ed, then inverted)
;         used to clear the target area before OR-ing in the new digit pixel
;   d2  = scratch for the composite operation
;
; Each invocation handles one bitplane row:
;   1. Load the byte from LevelCountTemp plane \1 (offset = LEVEL_COUNT_WIDTH_BYTE*\1)
;   2. AND with d5 (the inverted mask) to clear bits where the digit will go
;   3. OR in the corresponding byte from LevelFont plane \1
;   4. Store back to LevelCountTemp
;==============================================================================

LVLFNT             MACRO
                   move.b     LEVEL_COUNT_WIDTH_BYTE*\1(a0),d2   ; load target byte
                   and.b      d5,d2                               ; clear digit area (mask)
                   or.b       LEVEL_FONT_WIDTH_BYTE*\1(a2),d2    ; OR in font pixel
                   move.b     d2,LEVEL_COUNT_WIDTH_BYTE*\1(a0)   ; write back
                   ENDM


;==============================================================================
; FADE_STEP_RED / FADE_STEP_GREEN / FADE_STEP_BLUE
; Step one 4-bit colour channel toward its target value.
;
; Amiga OCS colour word format: $0RGB
;   bits 11:8 = Red,  bits 7:4 = Green,  bits 3:0 = Blue
;
; Three separate macros are used instead of a single parametric macro because
; vasm 1.9 rejects immediate shift counts of 8 (even for .L size operations)
; when running in strict 68000 mode with -m68000.  Each macro handles its
; channel without passing the shift amount as an argument:
;
;   FADE_STEP_RED   -- uses SWAP to bring bits 19:16 (of a longword) to bits
;                      3:0 without any large immediate shift.
;   FADE_STEP_GREEN -- uses LSR.L #4 (always valid: count 1..7 accepted).
;   FADE_STEP_BLUE  -- operates directly on bits 3:0, no shift needed.
;
; Arguments for all three:
;   \1  = data register holding the current colour word ($0RGB) — modified in place
;   \2  = data register holding the target  colour word ($0RGB) — read-only
;
; Scratch registers used: d2, d3, d4  (caller must preserve these via PUSHM).
;==============================================================================

; --- Red nibble (bits 11:8) -------------------------------------------------
; Strategy: zero-extend both words to longword, shift right by 8 using two
; LSR.L #4 calls (4+4=8), isolate nibble, step, rebuild.
FADE_STEP_RED      MACRO
                   moveq      #0,d2
                   move.w     \1,d2               ; d2 = 0000_0RGB (longword)
                   lsr.l      #4,d2               ; d2 = 0000_00RG -> wait, need bits 11:8
                   lsr.l      #4,d2               ; two x 4 = shift 8: d2.b = R nibble
                   and.w      #$000f,d2           ; d2 = current Red nibble

                   moveq      #0,d3
                   move.w     \2,d3
                   lsr.l      #4,d3
                   lsr.l      #4,d3
                   and.w      #$000f,d3           ; d3 = target Red nibble

                   cmp.w      d3,d2
                   beq        .\@skip
                   blt        .\@inc
                   subq.w     #1,d2
                   bra        .\@write
.\@inc             addq.w     #1,d2
.\@write           ; Rebuild: clear bits 11:8 of \1 then OR updated nibble back
                   move.w     \1,d3
                   and.w      #$f0ff,d3           ; clear Red nibble
                   lsl.l      #4,d2
                   lsl.l      #4,d2               ; d2 = nibble << 8 (two x 4)
                   or.w       d2,d3
                   move.w     d3,\1
.\@skip
                   ENDM

; --- Green nibble (bits 7:4) ------------------------------------------------
FADE_STEP_GREEN    MACRO
                   moveq      #0,d2
                   move.w     \1,d2
                   lsr.l      #4,d2               ; d2.b = Green nibble in bits 3:0
                   and.w      #$000f,d2

                   moveq      #0,d3
                   move.w     \2,d3
                   lsr.l      #4,d3
                   and.w      #$000f,d3

                   cmp.w      d3,d2
                   beq        .\@skip
                   blt        .\@inc
                   subq.w     #1,d2
                   bra        .\@write
.\@inc             addq.w     #1,d2
.\@write           move.w     \1,d3
                   and.w      #$ff0f,d3           ; clear Green nibble
                   lsl.l      #4,d2               ; shift nibble into bits 7:4
                   or.w       d2,d3
                   move.w     d3,\1
.\@skip
                   ENDM

; --- Blue nibble (bits 3:0) -------------------------------------------------
FADE_STEP_BLUE     MACRO
                   move.w     \1,d2
                   and.w      #$000f,d2           ; d2 = current Blue nibble

                   move.w     \2,d3
                   and.w      #$000f,d3           ; d3 = target Blue nibble

                   cmp.w      d3,d2
                   beq        .\@skip
                   blt        .\@inc
                   subq.w     #1,d2
                   bra        .\@write
.\@inc             addq.w     #1,d2
.\@write           move.w     \1,d3
                   and.w      #$fff0,d3           ; clear Blue nibble
                   or.w       d2,d3
                   move.w     d3,\1
.\@skip
                   ENDM
