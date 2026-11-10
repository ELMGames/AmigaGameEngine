;==============================================================================
; AMIGA GAME ENGINE
; debug_hud.asm  -  In-Game Real-Time Diagnostic HUD Overlay & Numeric Blitter
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapEraseDebugOverlay:
    tst.w       PrevDebugDrawn(a5)
    beq         .done

    ; If overlay is still active and camera has NOT moved, do NOT erase!
    tst.w       DebugOverlayActive(a5)
    beq.s       .do_erase

    move.w      TilemapCameraY(a5),d0
    cmp.w       PrevDebugCameraY(a5),d0
    beq         .done

.do_erase:
    clr.w       PrevDebugDrawn(a5)

    PUSHM       d0/d7/a0-a3/a6
    lea         CUSTOM,a6
    WAITBLIT

    ; Calculate start byte offset in 512-line buffer: ((PrevDebugCameraY & 255) + 2) * 160
    move.w      PrevDebugCameraY(a5),d0
    andi.w      #255,d0
    addq.w      #2,d0
    mulu.w      #TILEMAP_LINE_STRIDE,d0

    lea         NonDisplayScreen,a0
    add.l       d0,a0
    lea         DisplayScreen,a1
    add.l       d0,a1

    move.l      #$ffffffff,BLTAFWM(a6)
    move.w      #0,BLTAMOD(a6)
    move.w      #0,BLTDMOD(a6)
    move.w      #0,BLTCON1(a6)
    move.w      #MINTERM_COPY,BLTCON0(a6)          ; A -> D copy (minterm $F0)
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(120<<6)|20,BLTSIZE(a6)    ; 120 plane-rows x 20 words = 30 scanlines x 160 bytes
    WAITBLIT

    bsr         MarkAllActorsDirty          ; the strip also wiped anything drawn in it
    bsr         GameUnpauseHook             ; the game invalidates its own entities

    POPM        d0/d7/a0-a3/a6
.done:
    rts


;==============================================================================
; TilemapDrawDebugOverlay  -  Render debug statistics HUD on DisplayScreen
;
; Displays 3 lines of green text near the top of the visible viewport:
;   Line 1: CAM:yyy ROW:rr FINE:ff MODE:SLOW
;   Line 2: PLY: X:cc+xx Y:rr+yy
;   Line 3: ACT:a DIR:±1 ENM:ee WTR:ww
;
; Colors:
;   Color 5 ($0193 grass green) for text characters
;   Color 0 ($0000 black) for background within each character cell
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapDrawDebugOverlay:
    tst.w       DebugOverlayActive(a5)
    beq         .exit

    PUSHM       d0-d7/a0-a4

    ; Record current camera position for erase when scrolling/toggled off
    move.w      TilemapCameraY(a5),d6
    move.w      d6,PrevDebugCameraY(a5)
    andi.w      #255,d6                     ; d6 = 0..255 (buffer-relative line)
    move.w      #1,PrevDebugDrawn(a5)

    lea         Player(a5),a4               ; a4 -> player struct
    tst.w       Player_Status(a4)
    beq         .pop_exit

    ; -------------------------------------------------------------
    ; Line 1: CAM:yyy ROW:rr FINE:ff MODE:SLOW (24 chars padded)
    ; -------------------------------------------------------------
    lea         DebugLineBuf(a5),a1
    lea         .str_cam(pc),a0
    bsr         DebugWriteString

    move.w      TilemapCameraY(a5),d0
    bsr         DebugWriteDec3

    lea         .str_row(pc),a0
    bsr         DebugWriteString

    move.w      TilemapScreenOffset(a5),d0
    bsr         DebugWriteDec2

    lea         .str_fine(pc),a0
    bsr         DebugWriteString

    move.w      TilemapFineY(a5),d0
    bsr         DebugWriteDec2

    lea         .str_mode(pc),a0
    bsr         DebugWriteString

    tst.w       SlowMode(a5)
    bne.s       .mode_slow
    lea         .str_mode_run(pc),a0
    bra.s       .mode_done
.mode_slow:
    lea         .str_mode_slow(pc),a0
.mode_done:
    bsr         DebugWriteString

    clr.b       (a1)                        ; null terminate

    ; Draw Line 1 at CameraY + 2, X column 1
    lea         DebugLineBuf(a5),a0
    move.w      d6,d0
    addq.w      #2,d0
    moveq       #1,d1
    bsr         DebugDrawLine

    ; -------------------------------------------------------------
    ; Line 2: PLY: X:cc+xx Y:rr+yy    (24 chars padded)
    ; -------------------------------------------------------------
    lea         DebugLineBuf(a5),a1
    lea         .str_ply_x(pc),a0
    bsr         DebugWriteString

    move.w      Player_X(a4),d0
    bsr         DebugWriteDec2

    move.w      Player_XDec(a4),d0
    bsr         DebugWriteSigned2

    lea         .str_ply_y(pc),a0
    bsr         DebugWriteString

    move.w      Player_Y(a4),d0
    bsr         DebugWriteDec2

    move.w      Player_YDec(a4),d0
    bsr         DebugWriteSigned2

    clr.b       (a1)                        ; null terminate

    ; Draw Line 2 at CameraY + 11, X column 1
    lea         DebugLineBuf(a5),a0
    move.w      d6,d0
    add.w       #11,d0
    moveq       #1,d1
    bsr         DebugDrawLine

    ; -------------------------------------------------------------
    ; Line 3: ACT:a DIR:±1 ENM:ee WTR:ww (24 chars padded)
    ; -------------------------------------------------------------
    lea         DebugLineBuf(a5),a1
    lea         .str_act(pc),a0
    bsr         DebugWriteString

    move.w      ActionStatus(a5),d0
    bsr         DebugWriteDec1

    lea         .str_dir(pc),a0
    bsr         DebugWriteString

    move.w      Player_Facing(a4),d0
    tst.w       d0
    bpl.s       .dir_right
    move.b      #'-',(a1)+
    move.b      #'1',(a1)+
    bra.s       .dir_done
.dir_right:
    move.b      #'+',(a1)+
    move.b      #'1',(a1)+
.dir_done:

    lea         .str_enm(pc),a0
    bsr         DebugWriteString

    bsr         GameDebugCountHook          ; d0.w = game-chosen entity count
    bsr         DebugWriteDec2

    lea         .str_wtr(pc),a0
    bsr         DebugWriteString

    move.w      WaterCurrentRow(a5),d0
    bsr         DebugWriteDec2

    clr.b       (a1)                        ; null terminate

    ; Draw Line 3 at CameraY + 20, X column 1
    lea         DebugLineBuf(a5),a0
    move.w      d6,d0
    add.w       #20,d0
    moveq       #1,d1
    bsr         DebugDrawLine

.pop_exit:
    POPM        d0-d7/a0-a4
.exit:
    rts

.str_cam:       dc.b    "CAM:",0
.str_row:       dc.b    " ROW:",0
.str_fine:      dc.b    " FINE:",0
.str_ply_x:     dc.b    "PLY: X:",0
.str_ply_y:     dc.b    " Y:",0
.str_act:       dc.b    "ACT:",0
.str_dir:       dc.b    " DIR:",0
.str_enm:       dc.b    " ENM:",0
.str_wtr:       dc.b    " WTR:",0
.str_mode:      dc.b    " MODE:",0
.str_mode_run:  dc.b    "RUN ",0
.str_mode_slow: dc.b    "SLOW",0
    even


;==============================================================================
; DebugDrawLine  -  Render an ASCII string onto DisplayScreen in bold green text
;
; Arguments:
;   a0 = pointer to null-terminated ASCII string
;   d0.w = scanline Y within DisplayScreen (0..687)
;   d1.w = byte column X within row (0..39)
;
; Renders 8x8 font glyphs with horizontal smear for bold readability.
; Characters are drawn into Bitplane 0 and Bitplane 2 (Color index 5: grass green)
; while Bitplane 1 and Bitplane 3 are cleared to 0 (ensuring pure Color 5 over
; any background pixel).
;
; Destroys: none (preserves all registers)
;==============================================================================

DebugDrawLine:
    PUSHM       d0-d5/d7/a0-a4

    andi.w      #511,d0
    mulu.w      #TILEMAP_LINE_STRIDE,d0     ; d0.l = 32-bit unsigned offset
    lea         DisplayScreen,a1
    add.l       d0,a1
    ext.l       d1
    add.l       d1,a1                       ; a1 = target byte in DisplayScreen (Plane 0)
    lea         FontData,a2                 ; a2 = base of FontData

.char_loop:
    move.b      (a0)+,d2
    beq.s       .done

    ; Bounds check character (only ASCII 32..127 in font)
    cmp.b       #32,d2
    bge.s       .char_ge32
    moveq       #32,d2
.char_ge32:
    cmp.b       #127,d2
    ble.s       .char_ok
    moveq       #32,d2
.char_ok:
    sub.b       #32,d2
    and.w       #$00ff,d2
    lsl.w       #3,d2                       ; d2 = (char - 32) * 8
    lea         (a2,d2.w),a4                ; a4 -> 8 bytes of glyph

    ; Render 8 scanlines for this character
    movea.l     a1,a3                       ; a3 = Plane 0 for current row
    moveq       #8-1,d7
.row_loop:
    move.b      (a4)+,d3
    move.b      d3,d4
    lsr.b       #1,d4
    or.b        d4,d3                       ; bold smear

    move.b      d3,(a3)                     ; Plane 0 = glyph (Color 5 bit 0)
    clr.b       40(a3)                      ; Plane 1 = 0     (Color 5 bit 1)
    move.b      d3,80(a3)                   ; Plane 2 = glyph (Color 5 bit 2)
    clr.b       120(a3)                     ; Plane 3 = 0     (Color 5 bit 3)

    lea         160(a3),a3                  ; advance to next scanline (+160 bytes)
    dbra        d7,.row_loop

    addq.l      #1,a1                       ; next byte column (+8 pixels)
    bra.s       .char_loop

.done:
    POPM        d0-d5/d7/a0-a4
    rts


;==============================================================================
; Debug number formatting routines
;
; Destroys: d0/a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

DebugWriteString:
.str_loop:
    move.b      (a0)+,d0
    beq.s       .str_done
    move.b      d0,(a1)+
    bra.s       .str_loop
.str_done:
    rts

;==============================================================================
; DebugWriteDec3  -  Append d0.w as three decimal digits (000-999) to the buffer at a1
;
; In:  d0.w = value, a1 -> write cursor in DebugLineBuf
; Out: a1 advanced past the characters written
;
; Destroys: d0/a1 (preserves everything else, including a5/a6)
;==============================================================================

DebugWriteDec3:
    PUSHM       d1-d2
    and.l       #$ffff,d0
    divu.w      #100,d0                     ; d0.w = hundreds, upper word = remainder
    add.b       #'0',d0
    move.b      d0,(a1)+
    swap        d0
    and.l       #$ffff,d0
    divu.w      #10,d0                      ; d0.w = tens, upper word = units
    add.b       #'0',d0
    move.b      d0,(a1)+
    swap        d0
    add.b       #'0',d0
    move.b      d0,(a1)+
    POPM        d1-d2
    rts

;==============================================================================
; DebugWriteDec2  -  Append d0.w as two decimal digits (00-99) to the buffer at a1
;
; In:  d0.w = value, a1 -> write cursor in DebugLineBuf
; Out: a1 advanced past the characters written
;
; Destroys: d0/a1 (preserves everything else, including a5/a6)
;==============================================================================

DebugWriteDec2:
    PUSHM       d1
    and.l       #$ffff,d0
    divu.w      #10,d0                      ; d0.w = tens, upper word = units
    add.b       #'0',d0
    move.b      d0,(a1)+
    swap        d0
    add.b       #'0',d0
    move.b      d0,(a1)+
    POPM        d1
    rts

;==============================================================================
; DebugWriteDec1  -  Append the low nibble of d0 as one character ('0'..'?') to the buffer at a1
;
; In:  d0.w = value, a1 -> write cursor in DebugLineBuf
; Out: a1 advanced past the characters written
;
; Destroys: d0/a1 (preserves everything else, including a5/a6)
;==============================================================================

DebugWriteDec1:
    and.w       #15,d0
    add.b       #'0',d0
    move.b      d0,(a1)+
    rts

;==============================================================================
; DebugWriteSigned2  -  Append a sign ('+'/'-') then |d0.w| as two decimal digits to the buffer at a1
;
; In:  d0.w = value, a1 -> write cursor in DebugLineBuf
; Out: a1 advanced past the characters written
;
; Destroys: d0/a1 (preserves everything else, including a5/a6)
;==============================================================================

DebugWriteSigned2:
    tst.w       d0
    bpl.s       .pos
    move.b      #'-',(a1)+
    neg.w       d0
    bra.s       DebugWriteDec2
.pos:
    move.b      #'+',(a1)+
    bra.s       DebugWriteDec2

