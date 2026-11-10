;==============================================================================
; AMIGA GAME ENGINE
; bob_mirror.asm  -  Fast Runtime Blitter BOB Horizontal Mirroring & Bit-Reversal
;
; Destroys: none (preserves all registers)
;==============================================================================

PlayerInitFlippedSprites:
    PUSHM       d0-d7/a0-a3

    ; -------------------------------------------------------------------------
    ; 0. Set Active Player Pointers to Chip RAM Right-Facing Buffers
    ; -------------------------------------------------------------------------
    lea         PlayerRightRaw,a0
    lea         PlayerRightMsk,a1
    lea         PlayerRightWhiteRaw,a3
    move.l      a0,PlayerGfxPtr(a5)
    move.l      a1,PlayerMskPtr(a5)
    move.l      a3,PlayerWhitePtr(a5)

    ; -------------------------------------------------------------------------
    ; 1. Allocate Temporary 256-Byte Bit-Reversal Table on Stack
    ; -------------------------------------------------------------------------
    ; The stack pointer is decremented by 256 bytes. This scratch table exists
    ; only during boot initialisation, avoiding 256 bytes of static ROM/RAM.
    lea         -256(sp),sp
    movea.l     sp,a2                   ; a2 = BitReverseTable pointer

    ; -------------------------------------------------------------------------
    ; 2. Generate 256-Entry Bit-Reversal Lookup Table
    ; -------------------------------------------------------------------------
    ; For each byte value d0 (0..255), shifts out bit-by-bit into carry (LSR.B)
    ; and rotates into d1 (ROXL.B) from the opposite side, reversing all 8 bits.
    clr.w       d0
.pifs_table_gen:
    clr.b       d1
    move.b      d0,d2
    lsr.b       #1,d2                   ; bit 0 -> carry
    roxl.b      #1,d1                   ; carry -> bit 0 (shifts left into bit 7)
    lsr.b       #1,d2                   ; bit 1 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 2 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 3 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 4 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 5 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 6 -> carry
    roxl.b      #1,d1
    lsr.b       #1,d2                   ; bit 7 -> carry
    roxl.b      #1,d1
    move.b      d1,(a2,d0.w)            ; store reversed byte in lookup table
    addq.b      #1,d0                   ; next byte value
    bne.s       .pifs_table_gen         ; loop until d0 wraps back to 0 (256 iterations)

    ; -------------------------------------------------------------------------
    ; 3. Horizontally Flip All Three Selected Player Asset Streams into Left Buffers
    ; -------------------------------------------------------------------------
    ; Stream 1: Blitter Mask (PlayerMskPtr -> PlayerLeftMsk in Chip RAM)
    movea.l     PlayerMskPtr(a5),a0
    lea         PlayerLeftMsk,a1
    bsr.s       .pifs_flip_stream

    ; Stream 2: 4-Bitplane Raw Graphic (PlayerGfxPtr -> PlayerLeftRaw in Chip RAM)
    movea.l     PlayerGfxPtr(a5),a0
    lea         PlayerLeftRaw,a1
    bsr.s       .pifs_flip_stream

    ; Stream 3: White Silhouette Graphic (PlayerWhitePtr -> PlayerLeftWhiteRaw)
    movea.l     PlayerWhitePtr(a5),a0
    lea         PlayerLeftWhiteRaw,a1
    bsr.s       .pifs_flip_stream

    ; Deallocate stack table and restore caller registers
    lea         256(sp),sp
    POPM        d0-d7/a0-a3
    rts

.pifs_flip_stream:
    ; -------------------------------------------------------------------------
    ; 4. Cel Byte Re-ordering & Horizontal Bit-Reversal Engine
    ; -------------------------------------------------------------------------
    ; Player BOB sheet geometry:
    ;   - 144 scanlines tall * 4 bitplanes = 576 plane scanlines total
    ;   - Each plane scanline is 16 bytes wide (4 cels * 4 bytes per cel)
    ;   - In each 32px (4-byte) storage cel:
    ;       Byte 0: pixels 0..7
    ;       Byte 1: pixels 8..15
    ;       Byte 2: pixels 16..23  (24px active graphics end here)
    ;       Byte 3: pixels 24..31 (unused padding, always 0)
    ;
    ; To flip a 24-pixel cel horizontally across its active area:
    ;   New Byte 0 = reverse_bits(Old Byte 2)
    ;   New Byte 1 = reverse_bits(Old Byte 1)
    ;   New Byte 2 = reverse_bits(Old Byte 0)
    ;   New Byte 3 = 0 (retains 8-pixel padding)
    move.w      #(144*PLAYER_PLANES)-1,d7 ; d7 = 575 (576 plane scanlines)
.pifs_line_loop:
    moveq       #4-1,d6                 ; 4 cels of 32px per plane line (16 bytes)
.pifs_cel_loop:
    moveq       #0,d0
    moveq       #0,d1
    moveq       #0,d2
    move.b      (a0)+,d0                ; Old Byte 0 (pixels 0..7)
    move.b      (a0)+,d1                ; Old Byte 1 (pixels 8..15)
    move.b      (a0)+,d2                ; Old Byte 2 (pixels 16..23)
    addq.l      #1,a0                   ; Skip Old Byte 3 (padding)

    ; Look up reversed bytes and store in swapped order:
    move.b      (a2,d2.w),(a1)+         ; New Byte 0 = reverse(Old Byte 2)
    move.b      (a2,d1.w),(a1)+         ; New Byte 1 = reverse(Old Byte 1)
    move.b      (a2,d0.w),(a1)+         ; New Byte 2 = reverse(Old Byte 0)
    clr.b       (a1)+                   ; New Byte 3 = 0 (padding)
    dbra        d6,.pifs_cel_loop
    dbra        d7,.pifs_line_loop
    rts



