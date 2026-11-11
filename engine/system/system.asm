;==============================================================================
; AMIGA GAME ENGINE
; system.asm  -  OS Takeover, Hardware Detection, Interrupts & Fault Interception
;==============================================================================
;
; Minimal "kill the OS politely" module.  The game takes over the machine at
; the hardware level (own copper list, own interrupt vectors, all DMA), but
; snapshots enough state on the way in that it can hand the machine back to
; AmigaOS and return cleanly to the CLI — invaluable during development on
; real hardware and emulators.
;
; Core Engine Routines Provided:
;   SystemSave        - snapshot OS vectors, display, and DMA
;   SystemRestore     - restore OS copper, vectors, and multitasking
;   WorkbenchStartup  - collect the startup message on a Workbench launch
;   WorkbenchReply    - return that message on exit
;   InstallFaultTraps - point the fault vectors at the fault screen (VBR aware)
;   DetectNTSC        - detect PAL (50Hz) vs NTSC (60Hz), set IsPAL, patch cpGameDIW
;   DetectOCS         - detect OCS vs ECS/AGA Denise, set IsOCS
;   StartVBlank       - enable hardware DMA and vertical-blank interrupt
;   VBlankTick        - ISR counting ticks, 60Hz->50Hz NTSC sync, FramePending
;
; CPU note: handles 68010+ relocated VBR via GetVBR and flushes CPU caches on
; 68020+ machines via ClearCPUCache.
;
;==============================================================================

; exec.library LVOs
_LVOSupervisor      = -30
_LVOForbid          = -132
_LVOPermit          = -138
_LVOFindTask        = -294
_LVOGetMsg          = -372
_LVOReplyMsg        = -378
_LVOWaitPort        = -384
_LVOCloseLibrary    = -414
_LVOOpenLibrary     = -552
_LVOCacheClearU     = -636

; dos.library Process field offsets
pr_MsgPort          = 92                ; port Workbench sends its startup message to
pr_CLI              = 172               ; zero when started from Workbench

ExecVersion         = 20                ; LIB_VERSION (UWORD) in ExecBase
AttnFlags           = 296               ; UWORD in ExecBase
AFB_68010           = 0                 ; AttnFlags bit 0 (68010+)
AFB_68020           = 1                 ; AttnFlags bit 1 (68020+)
AFF_68010           = AFB_68010         ; compatibility alias
AFF_68020           = AFB_68020

; graphics.library LVOs and GfxBase field offsets
_LVOLoadView        = -222
_LVOWaitBlit        = -228
_LVOWaitTOF         = -270
_LVOOwnBlitter      = -456
_LVODisownBlitter   = -462
gb_ActiView         = 34
gb_copinit          = 38


;==============================================================================
; GetVBR  -  Get Vector Base Register address (returns A0 = VBR base)
;
; On 68000, VBR is always 0. On 68010+, reads VBR via Supervisor mode.
;
; In:       none
; Out:      a0 = VBR base address
; Destroys: a0 (preserves all other registers)
;==============================================================================

GetVBR:
    movem.l     d0-d7/a1-a6,-(sp)
    suba.l      a0,a0                   ; default A0 = 0 (68000)
    move.l      4.w,a6                  ; ExecBase
    move.w      AttnFlags(a6),d0        ; AttnFlags (UWORD at offset 296)
    btst        #AFB_68010,d0           ; bit 0 (68010+)
    beq.s       .is_68000
    lea         .get_vbr_super(pc),a5
    jsr         _LVOSupervisor(a6)      ; run in supervisor mode (returns A0 = VBR)
.is_68000:
    movem.l     (sp)+,d0-d7/a1-a6
    rts

.get_vbr_super:
    dc.w        $4e7a,$8801             ; movec vbr,a0
    rte


;==============================================================================
; ClearCPUCache  -  Clear 68020+ instruction and data caches
;
; Safe to call on any CPU; executes CacheClearU on a 68020+ under Kickstart 2.0+.
;
; In:       none
; Out:      none
; Destroys: none (preserves all registers)
;==============================================================================

ClearCPUCache:
    movem.l     d0-d1/a0-a1/a6,-(sp)
    move.l      4.w,a6
    move.w      AttnFlags(a6),d0        ; AttnFlags (UWORD at offset 296)
    btst        #AFB_68020,d0           ; bit 1 (68020+)
    beq.s       .no_cache
    cmp.w       #37,ExecVersion(a6)     ; CacheClearU needs exec V37+ (Kickstart 2.0)
    blo.s       .no_cache               ; Kickstart 1.x has no CacheClearU: skip it
    jsr         _LVOCacheClearU(a6)
.no_cache:
    movem.l     (sp)+,d0-d1/a0-a1/a6
    rts


;==============================================================================
; SystemSave  -  Take over the machine (call while the OS is still running)
;
; Must be called before Init installs any handlers, so the snapshots capture
; the ORIGINAL OS values.  Runs on the OS-provided stack.
;
; In:       none
; Out:      none
; Destroys: d0-d1, a0-a1, a6 (Main does not need them preserved at entry)
;==============================================================================

SystemSave:
    ; Open graphics.library (any version)
    move.l      4.w,a6                  ; ExecBase
    lea         .gfxname(pc),a1
    moveq       #0,d0
    jsr         _LVOOpenLibrary(a6)
    move.l      d0,GfxBase
    beq.s       .no_gfx                 ; paranoia: graphics.library is always present

    ; Blank the OS display and wait for it to actually leave the screen
    move.l      d0,a6
    move.l      gb_ActiView(a6),SavedView
    sub.l       a1,a1                   ; LoadView(NULL)
    jsr         _LVOLoadView(a6)
    jsr         _LVOWaitTOF(a6)
    jsr         _LVOWaitTOF(a6)         ; twice: covers interlaced long frame
    jsr         _LVOOwnBlitter(a6)
    jsr         _LVOWaitBlit(a6)        ; let any OS blit in progress finish

    ; Stop task switching for the duration of the game
    move.l      4.w,a6
    jsr         _LVOForbid(a6)
.no_gfx

    ; Snapshot the hardware enable masks
    lea         CUSTOM,a0
    move.w      INTENAR(a0),SavedINTENA
    move.w      DMACONR(a0),SavedDMACON
    move.w      ADKCONR(a0),SavedADKCON ; disk MFM/sync/precomp + audio modulation bits

    ; Snapshot every vector the game overwrites (Init / KeyboardInit /
    ; StartVBlank). Handles 68010+ relocated VBR.
    bsr         GetVBR                  ; returns a0 = VBR base (0 on 68000)
    move.l      a0,VBRBase              ; store VBR base address

    move.l      $8(a0),SavedVec08       ; bus error
    move.l      $c(a0),SavedVec0C       ; address error
    move.l      $10(a0),SavedVec10      ; illegal instruction
    move.l      $14(a0),SavedVec14      ; zero divide
    move.l      $20(a0),SavedVec20      ; privilege violation
    move.l      $28(a0),SavedVec28      ; line-A emulator
    move.l      $2c(a0),SavedVec2C      ; line-F emulator
    move.l      $68(a0),SavedVec68      ; level 2 (CIA-A / keyboard)
    move.l      $6c(a0),SavedVec6C      ; level 3 (VBlank)
    move.l      $80(a0),SavedVec80      ; TRAP #0
    rts

.gfxname
    dc.b        'graphics.library',0
    even


;==============================================================================
; SystemRestore  -  Hand the machine back to the OS (call once, on exit)
;
; Mirror image of SystemSave.  Interrupt vectors are restored BEFORE the OS
; interrupt enables, so no game handler can fire during the transition.
;
; In:       none
; Out:      none
; Destroys: d0-d1, a0-a1, a6
;==============================================================================

SystemRestore:
    ; Silence everything the game had running
    lea         CUSTOM,a0
    move.w      #$7fff,INTENA(a0)
    move.w      #$7fff,INTREQ(a0)
    move.w      #$7fff,INTREQ(a0)       ; twice: A4000 chipset quirk
    move.w      #$7fff,DMACON(a0)

    ; Restore the original vectors relative to VBR Base
    move.l      VBRBase,a0
    move.l      SavedVec08,$8(a0)
    move.l      SavedVec0C,$c(a0)
    move.l      SavedVec10,$10(a0)
    move.l      SavedVec14,$14(a0)
    move.l      SavedVec20,$20(a0)
    move.l      SavedVec28,$28(a0)
    move.l      SavedVec2C,$2c(a0)
    move.l      SavedVec68,$68(a0)
    move.l      SavedVec6C,$6c(a0)
    move.l      SavedVec80,$80(a0)

    bsr         ClearCPUCache           ; flush CPU caches before returning to OS

    move.l      GfxBase,d0
    beq.s       .no_gfx

    ; Restart the OS boot copper list so the display hardware is sane
    move.l      d0,a6
    lea         CUSTOM,a0              ; reload custom chip base (a0 was VBRBase)
    move.l      gb_copinit(a6),COP1LC(a0)
    move.w      #0,COPJMP1(a0)

    ; Re-enable the DMA channels and interrupts the OS had active
    move.w      SavedDMACON,d0
    or.w        #$8200,d0               ; SETCLR + MASTER
    move.w      d0,DMACON(a0)
    move.w      SavedINTENA,d0
    or.w        #$c000,d0               ; SETCLR + INTEN
    move.w      d0,INTENA(a0)
    move.w      #$7fff,ADKCON(a0)       ; Restart cleared ADKCON: put the OS value back
    move.w      SavedADKCON,d0
    or.w        #$8000,d0               ; SETCLR
    move.w      d0,ADKCON(a0)

    ; Resume multitasking, release the blitter, restore the OS view
    move.l      4.w,a6
    jsr         _LVOPermit(a6)
    move.l      GfxBase,a6
    jsr         _LVODisownBlitter(a6)
    move.l      SavedView,a1
    jsr         _LVOLoadView(a6)
    jsr         _LVOWaitTOF(a6)
    jsr         _LVOWaitTOF(a6)

    move.l      a6,a1
    move.l      4.w,a6
    jsr         _LVOCloseLibrary(a6)
.no_gfx
    rts


;==============================================================================
; WorkbenchStartup  -  Collect the startup message when launched from an icon
;
; Workbench sends a message to the new process and waits for a reply. Called
; first thing from Main, before any DOS call.
;
; In:  d0/a0 = CLI arguments
; Out: d0/a0 unchanged from the CLI; d0 = 0 (no arguments) from Workbench
; Destroys: d1/a1-a2/a6 (Main has saved them)
;==============================================================================

WorkbenchStartup:
    movem.l     d0/a0,-(sp)
    move.l      4.w,a6
    sub.l       a1,a1                   ; FindTask(NULL): this process
    jsr         _LVOFindTask(a6)
    move.l      d0,a2
    tst.l       pr_CLI(a2)              ; non-zero: started from the CLI
    bne.s       .cli
    lea         pr_MsgPort(a2),a0
    jsr         _LVOWaitPort(a6)
    lea         pr_MsgPort(a2),a0
    jsr         _LVOGetMsg(a6)
    move.l      d0,WBenchMsg
    clr.l       (sp)                    ; saved d0 = 0: no CLI arguments
.cli:
    movem.l     (sp)+,d0/a0
    rts


;==============================================================================
; WorkbenchReply  -  Return the startup message (call last, on the OS stack)
;
; Workbench unloads the program when it gets the reply, so Forbid keeps it away
; until the final rts has run. There is no Permit: multitasking resumes when
; the process ends.
;
; Destroys: d0-d1/a0-a1/a6 (Main's saved registers are restored afterwards)
;==============================================================================

WorkbenchReply:
    move.l      WBenchMsg,d0
    beq.s       .done                   ; CLI launch: nothing to reply to
    move.l      d0,a1
    move.l      4.w,a6
    jsr         _LVOForbid(a6)          ; stays on until this process ends
    jsr         _LVOReplyMsg(a6)
.done:
    rts


;==============================================================================
; InstallFaultTraps  -  Install minimal 68000 exception handlers
;
; Traps bus error ($8), address error ($C), illegal instruction ($10),
; zero divide ($14), privilege violation ($20), line-A ($28), line-F ($2C)
; and TRAP #0 ($80) to FaultTrap. A wild jump into data most often lands on
; a line-A/line-F or privileged opcode, so those three matter as much as $10.
; exec's Supervisor() (used by GetVBR and CacheClearU) relies on the OS
; privilege-violation handler: call it only before this runs or after
; SystemRestore has put the original vectors back.
; Uses VBRBase to correctly support 68010+ VBR relocation.
;
; Destroys: a0-a1 (preserves everything else, including a5/a6)
;==============================================================================

InstallFaultTraps:
    move.l      VBRBase,a1
    move.l      #FaultVec2,$8(a1)   ; bus error          (vector 2)
    move.l      #FaultVec3,$c(a1)   ; address error      (vector 3)
    move.l      #FaultVec4,$10(a1)  ; illegal instruction (vector 4)
    move.l      #FaultVec5,$14(a1)  ; zero divide        (vector 5)
    move.l      #FaultVec8,$20(a1)  ; privilege violation (vector 8)
    move.l      #FaultVec10,$28(a1) ; line-A emulator    (vector 10)
    move.l      #FaultVec11,$2c(a1) ; line-F emulator    (vector 11)
    move.l      #FaultVec32,$80(a1) ; TRAP #0            (vector 32)
    rts

;==============================================================================
; FaultTrap  -  Stop the machine and show the fault screen
;
; Each fault vector enters through its own two-instruction stub, which records
; the vector number, so the screen can name the exception. Code can also branch
; straight to FaultTrap, as GameStatusRun does for a corrupt state number. That
; is reported as vector 0, SOFTWARE STOP, with no exception frame to decode.
;
; The handler saves every register, silences interrupts, audio and sprites,
; then builds a two-plane display and its Copper list in FaultScreen, a game
; symbol for at least FAULT_SCREEN_BYTES of Chip RAM. It prints the exception,
; PC, SR, fault address, opcode and registers, and flashes FAULT until the
; Amiga is reset. The software path uses no privileged instruction, so it
; also works when entered from user mode.
;
; Never returns.
;==============================================================================

FAULT_PLANE         = 40*256                ; one 320x256 lo-res bitplane
FAULT_COPPER        = 2*FAULT_PLANE         ; the Copper list follows the planes
FAULT_SCREEN_BYTES  = FAULT_COPPER+128      ; Chip RAM a game must give FaultScreen
FAULT_NTSC_DIWSTRT  = $1681                 ; NTSC window: line 22 ...
FAULT_NTSC_DIWSTOP  = $01c1                 ; ... to line 257 ($101), 235 lines
FAULT_NTSC_SKIP     = 16*40                 ; NTSC: start the planes 16 empty lines in

FAULT_BLACK         = $0101                 ; background
FAULT_AMBER         = $0fa3                 ; report text
FAULT_RED           = $0f23                 ; FAULT, lit
FAULT_DIM           = $0301                 ; FAULT, dimmed

FAULT_HAVE_FRAME    = 0                     ; FaultHave bits: PC and SR known
FAULT_HAVE_ACCESS   = 1                     ; fault address known
FAULT_HAVE_OPCODE   = 2                     ; opcode known
FAULT_HAVE_USP      = 3                     ; user stack pointer known

FaultVec2:
    move.w      #2,FaultVector
    bra.s       FaultEnter
FaultVec3:
    move.w      #3,FaultVector
    bra.s       FaultEnter
FaultVec4:
    move.w      #4,FaultVector
    bra.s       FaultEnter
FaultVec5:
    move.w      #5,FaultVector
    bra.s       FaultEnter
FaultVec8:
    move.w      #8,FaultVector
    bra.s       FaultEnter
FaultVec10:
    move.w      #10,FaultVector
    bra.s       FaultEnter
FaultVec11:
    move.w      #11,FaultVector
    bra.s       FaultEnter
FaultVec32:
    move.w      #32,FaultVector
    bra.s       FaultEnter

FaultTrap:
    clr.w       FaultVector             ; software stop: no exception frame
FaultEnter:
    tst.w       FaultBusy               ; a fault inside this handler:
    bne         FaultHang               ; fall back to a plain red screen
    move.w      #1,FaultBusy
    movem.l     d0-d7/a0-a7,FaultRegs   ; every register as it was at the fault
    lea         FaultStackTop,sp        ; the fault may have been a bad stack
    lea         CUSTOM,a6
    move.w      #$7fff,INTENA(a6)       ; nothing may interrupt from here on
    move.w      #$7fff,DMACON(a6)       ; stop the Copper, Blitter, audio and sprites
    moveq       #0,d0
    lea         AUD0VOL(a6),a0
    moveq       #4-1,d1
.audio_off:
    move.w      d0,(a0)                 ; silence each audio channel
    lea         16(a0),a0
    dbra        d1,.audio_off
    lea         SPR0CTL(a6),a0
    moveq       #8-1,d1
.sprite_off:
    move.w      d0,(a0)                 ; disarm each sprite channel
    addq.l      #8,a0
    dbra        d1,.sprite_off

    ; Decode the exception frame. A software stop has none.
    clr.w       FaultHave
    move.w      FaultVector,d2
    beq         .decoded
    move        usp,a0                  ; entered by an exception: supervisor mode
    move.l      a0,FaultUSP
    bset        #FAULT_HAVE_USP,FaultHave+1
    bset        #FAULT_HAVE_FRAME,FaultHave+1
    move.l      FaultRegs+60,a0         ; the stack at the fault holds the frame
    move.l      4.w,a1                  ; ExecBase
    btst        #AFB_68010,AttnFlags+1(a1)
    bne.s       .short_frame            ; 68010+: SR, PC, format word
    cmp.w       #3,d2
    bhi.s       .short_frame            ; 68000 group 1 and 2: SR, PC
    ; 68000 bus or address error: status, fault address, opcode, SR, PC
    move.l      2(a0),FaultAccess
    move.w      6(a0),FaultOpcode
    move.w      8(a0),FaultSR
    move.l      10(a0),FaultPC
    bset        #FAULT_HAVE_ACCESS,FaultHave+1
    bset        #FAULT_HAVE_OPCODE,FaultHave+1
    bra.s       .decoded
.short_frame:
    move.w      (a0),FaultSR
    move.l      2(a0),FaultPC
    cmp.w       #3,d2
    bhi.s       .not_bus                ; only bus and address errors carry an address
    ; 68010 and later: the format code (top 4 bits of the word at +6) says
    ; where in the frame this CPU keeps the faulting address
    moveq       #0,d0
    move.b      6(a0),d0
    lsr.b       #4,d0                   ; d0 = frame format, 0..15
    lea         FaultAddressOffsets,a1
    move.b      (a1,d0.w),d0            ; d0 = offset of the address, 0 = none
    beq.s       .decoded
    move.l      (a0,d0.w),FaultAccess
    bset        #FAULT_HAVE_ACCESS,FaultHave+1
    bra.s       .decoded
.not_bus:
    cmp.w       #4,d2                   ; illegal, line-A and line-F: the PC
    beq.s       .read_opcode            ; points at the offending opcode
    cmp.w       #10,d2
    beq.s       .read_opcode
    cmp.w       #11,d2
    bne.s       .decoded
.read_opcode:
    move.l      FaultPC,d0
    btst        #0,d0
    bne.s       .decoded                ; odd PC: reading it would fault again
    move.l      d0,a1
    move.w      (a1),FaultOpcode
    bset        #FAULT_HAVE_OPCODE,FaultHave+1
.decoded:

    ; Clear the two planes, then build the Copper list after them
    lea         FaultScreen,a0
    moveq       #0,d0
    move.w      #FAULT_COPPER/4-1,d1
.clear:
    move.l      d0,(a0)+
    dbra        d1,.clear
    lea         FaultCopperTable(pc),a2
    move.w      #(FaultCopperTableEnd-FaultCopperTable)/2-1,d1
.copy:
    move.w      (a2)+,(a0)+
    dbra        d1,.copy
    move.l      #FaultScreen,d0
    tst.w       FaultNTSC               ; set by DetectNTSC: a5 may be bad here
    beq.s       .pal_window
    ; NTSC has 262 lines. The report uses screen lines 16 to 249 (the title
    ; to the reset line), so skip the 16 empty lines above it and show it in
    ; a window from line 22 to 257: beam lines 22 to 255 hold all of it
    move.w      #FAULT_NTSC_DIWSTRT,FaultScreen+FAULT_COPPER+14
    move.w      #FAULT_NTSC_DIWSTOP,FaultScreen+FAULT_COPPER+18
    add.l       #FAULT_NTSC_SKIP,d0
.pal_window:
    move.w      #BPL1PTH,(a0)+
    swap        d0
    move.w      d0,(a0)+
    move.w      #BPL1PTL,(a0)+
    swap        d0
    move.w      d0,(a0)+
    add.l       #FAULT_PLANE,d0
    move.w      #BPL2PTH,(a0)+
    swap        d0
    move.w      d0,(a0)+
    move.w      #BPL2PTL,(a0)+
    swap        d0
    move.w      d0,(a0)+
    move.w      #COLOR02,(a0)+
    move.l      a0,a5                   ; a5 -> COLOR02's value, flashed below
    move.w      #FAULT_RED,(a0)+
    move.w      #COLOR03,(a0)+
    move.w      #FAULT_RED,(a0)+
    move.l      #COPPER_HALT,(a0)

    ; The report
    lea         .t_title(pc),a0
    moveq       #1,d0
    moveq       #18,d1
    bsr         FaultPrint

    lea         FaultLine,a1            ; EXCEPTION  03  ADDRESS ERROR
    lea         .t_exception(pc),a0
    bsr         FaultCopy
    moveq       #0,d0
    move.w      FaultVector,d0
    divu        #10,d0
    add.b       #'0',d0
    move.b      d0,(a1)+
    swap        d0
    add.b       #'0',d0
    move.b      d0,(a1)+
    move.b      #' ',(a1)+
    move.b      #' ',(a1)+
    bsr         FaultName
    bsr         FaultCopy
    moveq       #36,d1
    bsr         FaultPrintLine

    lea         .t_pc(pc),a0
    move.l      FaultPC,d0
    moveq       #8,d2
    moveq       #FAULT_HAVE_FRAME,d3
    moveq       #48,d1
    bsr         FaultField
    lea         .t_sr(pc),a0
    move.w      FaultSR,d0
    moveq       #4,d2
    moveq       #FAULT_HAVE_FRAME,d3
    moveq       #60,d1
    bsr         FaultField
    lea         .t_access(pc),a0
    move.l      FaultAccess,d0
    moveq       #8,d2
    moveq       #FAULT_HAVE_ACCESS,d3
    moveq       #72,d1
    bsr         FaultField
    lea         .t_opcode(pc),a0
    move.w      FaultOpcode,d0
    moveq       #4,d2
    moveq       #FAULT_HAVE_OPCODE,d3
    moveq       #84,d1
    bsr         FaultField

    ; D0-D7 beside A0-A7
    lea         FaultRegs,a4
    moveq       #0,d5                   ; register number
    moveq       #100,d6                 ; screen line
.registers:
    lea         FaultLine,a1
    move.b      #'D',(a1)+
    move.b      d5,d0
    add.b       #'0',d0
    move.b      d0,(a1)+
    move.b      #' ',(a1)+
    move.l      (a4),d0
    moveq       #8,d2
    bsr         FaultHex
    moveq       #4-1,d1
.gap:
    move.b      #' ',(a1)+              ; byte writes: a1 may be odd here
    dbra        d1,.gap
    move.b      #'A',(a1)+
    move.b      d5,d0
    add.b       #'0',d0
    move.b      d0,(a1)+
    move.b      #' ',(a1)+
    move.l      32(a4),d0
    moveq       #8,d2
    bsr         FaultHex
    move.w      d6,d1
    bsr         FaultPrintLine
    addq.l      #4,a4
    add.w       #10,d6
    addq.w      #1,d5
    cmp.w       #8,d5
    blt.s       .registers

    lea         .t_usp(pc),a0
    move.l      FaultUSP,d0
    moveq       #8,d2
    moveq       #FAULT_HAVE_USP,d3
    move.w      #182,d1
    bsr         FaultField

    lea         .t_fault(pc),a0         ; FAULT, four times size, in plane 2
    lea         FaultScreen+FAULT_PLANE+200*40+10,a2
    bsr         FaultBig
    lea         .t_reset(pc),a0
    moveq       #7,d0
    move.w      #242,d1
    bsr         FaultPrint

    ; Show it, then flash FAULT about twice a second until reset
    move.l      #FaultScreen+FAULT_COPPER,COP1LC(a6)
    move.w      d0,COPJMP1(a6)          ; strobe: start the new list
    move.w      #DMAF_SETCLR|DMAF_MASTER|DMAF_RASTER|DMAF_COPPER,DMACON(a6)
    moveq       #0,d6
.flash:
    moveq       #25-1,d7
.frame:
    btst        #0,VPOSR+1(a6)          ; wait for the beam to pass line 255
    beq.s       .frame
.next:
    btst        #0,VPOSR+1(a6)          ; then for the top of the next frame
    bne.s       .next
    dbra        d7,.frame
    not.w       d6
    move.w      #FAULT_RED,d0
    tst.w       d6
    beq.s       .lit
    move.w      #FAULT_DIM,d0
.lit:
    move.w      d0,(a5)                 ; the Copper sets COLOR02 and COLOR03
    move.w      d0,4(a5)                ; from these words each frame
    bra.s       .flash

.t_title:       dc.b    "AMIGA GAME ENGINE  -  EXCEPTION REPORT",0
.t_exception:   dc.b    "EXCEPTION  ",0
.t_pc:          dc.b    "PC         ",0
.t_sr:          dc.b    "SR         ",0
.t_access:      dc.b    "ACCESS     ",0
.t_opcode:      dc.b    "OPCODE     ",0
.t_usp:         dc.b    "USP        ",0
.t_fault:       dc.b    "FAULT",0
.t_reset:       dc.b    "RESET THE AMIGA TO RESTART",0
                even

; A fault inside the fault handler lands here
FaultHang:
    move.w      #$0f00,CUSTOM+COLOR00   ; solid red: the fault screen itself failed
    bra.s       FaultHang

;------------------------------------------------------------------------------
; Fault screen helpers. They run only after a fault, on whatever stack was in
; use, and use a few words of it at most.
;------------------------------------------------------------------------------

;==============================================================================
; FaultName  -  Look up exception name string for FaultVector
;
; Out:      a0 = pointer to null-terminated name string
; Destroys: d0, a0
;==============================================================================

FaultName:
    lea         FaultNames(pc),a0
    move.w      FaultVector,d0
.find:
    cmp.w       (a0),d0
    beq.s       .found
    tst.w       (a0)
    bmi.s       .found                  ; end of table: unknown
    addq.l      #4,a0
    bra.s       .find
.found:
    move.w      2(a0),d0
    lea         FaultNames(pc),a0
    add.w       d0,a0
    rts

;==============================================================================
; FaultCopy  -  Copy null-terminated string without its terminator
;
; In:       a0 = source string pointer, a1 = destination buffer pointer
; Out:      a0 points after source null, a1 points to destination end
; Destroys: a0, a1
;==============================================================================

FaultCopy:
    move.b      (a0)+,(a1)+
    bne.s       FaultCopy
    subq.l      #1,a1
    rts

;==============================================================================
; FaultHex  -  Format d0 as hex digits
;
; In:       d0.l = value, d2.w = digit count, a1 = destination buffer
; Destroys: d0-d1, d4, a0-a1
;==============================================================================

FaultHex:
    move.w      d2,d1
    subq.w      #1,d1
    lsl.w       #2,d1
    move.l      d0,d4
.digit:
    move.l      d4,d0
    lsr.l       d1,d0
    and.w       #$f,d0
    lea         FaultDigits(pc),a0
    move.b      (a0,d0.w),(a1)+
    subq.w      #4,d1
    bpl.s       .digit
    rts

; FaultField  -  print label a0 then d0 as d2 hex digits, or dashes when
; FaultHave bit d3 is clear, at column 1 of screen line d1
FaultField:
    move.w      d1,-(sp)
    lea         FaultLine,a1
    move.l      d0,-(sp)
    bsr.s       FaultCopy
    move.l      (sp)+,d0
    btst        d3,FaultHave+1
    beq.s       .unknown
    bsr.s       FaultHex
    bra.s       .print
.unknown:
    move.b      #'-',(a1)+
    subq.w      #1,d2
    bne.s       .unknown
.print:
    move.w      (sp)+,d1
    ; fall through
; FaultPrintLine  -  terminate FaultLine at a1 and print it at column 1, line d1
FaultPrintLine:
    clr.b       (a1)
    lea         FaultLine,a0
    moveq       #1,d0
    ; fall through
;==============================================================================
; FaultPrint  -  Print string at column and screen line
;
; In:       a0 = string pointer, d0.w = column, d1.w = screen line
; Destroys: d0-d1, a0-a3
;==============================================================================

FaultPrint:
    lea         FaultScreen,a2
    mulu        #40,d1
    add.l       d1,a2
    add.w       d0,a2
.char:
    moveq       #0,d0
    move.b      (a0)+,d0
    beq.s       .done
    sub.b       #32,d0
    cmp.b       #63,d0
    bls.s       .glyph
    moveq       #0,d0                   ; outside the font: print a space
.glyph:
    lsl.w       #3,d0
    lea         FaultFont(pc),a1
    add.w       d0,a1
    move.l      a2,a3
    moveq       #8-1,d1
.row:
    move.b      (a1)+,(a3)
    lea         40(a3),a3
    dbra        d1,.row
    addq.l      #1,a2
    bra.s       .char
.done:
    rts

;==============================================================================
; FaultBig  -  Print string at 4x scale
;
; In:       a0 = string pointer, a2 = screen destination (even address)
; Destroys: d0-d6, a0-a3
;==============================================================================

FaultBig:
    moveq       #0,d0
    move.b      (a0)+,d0
    beq.s       .done
    sub.b       #32,d0
    lsl.w       #3,d0
    lea         FaultFont(pc),a1
    add.w       d0,a1
    move.l      a2,a3
    moveq       #8-1,d4
.row:
    move.b      (a1)+,d2
    moveq       #0,d3
    moveq       #8-1,d5
.bit:
    lsl.l       #4,d3                   ; each pixel becomes four
    add.b       d2,d2
    bcc.s       .clear
    or.b        #$0f,d3
.clear:
    dbra        d5,.bit
    move.l      d3,(a3)                 ; and each row becomes four
    move.l      d3,40(a3)
    move.l      d3,80(a3)
    move.l      d3,120(a3)
    lea         160(a3),a3
    dbra        d4,.row
    addq.l      #4,a2
    bra.s       FaultBig
.done:
    rts

FaultDigits:    dc.b    "0123456789ABCDEF"

; FaultAddressOffsets  -  for each 68010+ frame format, the offset of the
; faulting address in a bus or address error frame (0 = not in this format)
;   $2  68040/68060 address error           +$08
;   $4  68060 access error (FA)             +$08
;   $7  68040 access error (FA)             +$14
;   $8  68010 bus or address error          +$0A
;   $A  68020/68030 short bus cycle fault   +$10
;   $B  68020/68030 long bus cycle fault    +$10
FaultAddressOffsets:
    dc.b    0,0,$08,0,$08,0,0,$14,$0A,0,$10,$10,0,0,0,0

FaultNames:
    dc.w        0,.n0-FaultNames
    dc.w        2,.n2-FaultNames
    dc.w        3,.n3-FaultNames
    dc.w        4,.n4-FaultNames
    dc.w        5,.n5-FaultNames
    dc.w        8,.n8-FaultNames
    dc.w        10,.n10-FaultNames
    dc.w        11,.n11-FaultNames
    dc.w        32,.n32-FaultNames
    dc.w        -1,.nx-FaultNames
.n0:    dc.b    "SOFTWARE STOP",0
.n2:    dc.b    "BUS ERROR",0
.n3:    dc.b    "ADDRESS ERROR",0
.n4:    dc.b    "ILLEGAL INSTRUCTION",0
.n5:    dc.b    "ZERO DIVIDE",0
.n8:    dc.b    "PRIVILEGE VIOLATION",0
.n10:   dc.b    "LINE-A OPCODE",0
.n11:   dc.b    "LINE-F OPCODE",0
.n32:   dc.b    "TRAP 0",0
.nx:    dc.b    "UNKNOWN",0
        even

FaultCopperTable:
    dc.w        FMODE,0                 ; AGA: ordinary fetch
    dc.w        BPLCON3,$0c00
    dc.w        BPLCON4,0
    dc.w        DIWSTRT,$2c81           ; 320x256 PAL window
    dc.w        DIWSTOP,$2cc1
    dc.w        DDFSTRT,$0038
    dc.w        DDFSTOP,$00d0
    dc.w        BPLCON0,$2200           ; two planes, colour on
    dc.w        BPLCON1,0
    dc.w        BPLCON2,0
    dc.w        BPL1MOD,0
    dc.w        BPL2MOD,0
    dc.w        COLOR00,FAULT_BLACK
    dc.w        COLOR01,FAULT_AMBER
FaultCopperTableEnd:

; 8x8 glyphs for ASCII 32 to 95 (space to underscore): the engine's own copy,
; so the fault screen works whatever font a game uses
FaultFont:
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; ' '
    dc.b    $18,$18,$18,$18,$18,$00,$18,$18   ; '!'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; '"'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; '#'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; '$'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; '%'
    dc.b    $30,$48,$30,$4c,$42,$45,$3a,$00   ; '&'
    dc.b    $18,$18,$08,$00,$00,$00,$00,$00   ; "'"
    dc.b    $08,$10,$20,$20,$20,$20,$10,$08   ; '('
    dc.b    $10,$08,$04,$04,$04,$04,$08,$10   ; ')'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; '*'
    dc.b    $00,$18,$18,$7e,$18,$18,$00,$00   ; '+'
    dc.b    $00,$00,$00,$00,$18,$18,$08,$10   ; ','
    dc.b    $00,$00,$00,$7e,$00,$00,$00,$00   ; '-'
    dc.b    $00,$00,$00,$00,$00,$00,$18,$18   ; '.'
    dc.b    $02,$04,$08,$10,$20,$40,$00,$00   ; '/'
    dc.b    $3c,$42,$46,$4a,$52,$62,$42,$3c   ; '0'
    dc.b    $18,$38,$18,$18,$18,$18,$18,$7e   ; '1'
    dc.b    $3c,$42,$02,$04,$18,$20,$40,$7e   ; '2'
    dc.b    $3c,$42,$02,$1c,$02,$02,$42,$3c   ; '3'
    dc.b    $04,$0c,$14,$24,$44,$7e,$04,$04   ; '4'
    dc.b    $7e,$40,$40,$7c,$02,$02,$42,$3c   ; '5'
    dc.b    $1c,$20,$40,$7c,$42,$42,$42,$3c   ; '6'
    dc.b    $7e,$02,$04,$08,$10,$20,$20,$20   ; '7'
    dc.b    $3c,$42,$42,$3c,$42,$42,$42,$3c   ; '8'
    dc.b    $3c,$42,$42,$3e,$02,$04,$08,$30   ; '9'
    dc.b    $00,$18,$18,$00,$00,$18,$18,$00   ; ':'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; ';'
    dc.b    $02,$04,$08,$10,$10,$08,$04,$02   ; '<'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; '='
    dc.b    $40,$20,$10,$08,$08,$10,$20,$40   ; '>'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; '?'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; '@'
    dc.b    $18,$24,$42,$42,$7e,$42,$42,$42   ; 'A'
    dc.b    $7c,$42,$42,$7c,$42,$42,$42,$7c   ; 'B'
    dc.b    $3c,$42,$40,$40,$40,$40,$42,$3c   ; 'C'
    dc.b    $78,$44,$42,$42,$42,$42,$44,$78   ; 'D'
    dc.b    $7e,$40,$40,$7c,$40,$40,$40,$7e   ; 'E'
    dc.b    $7e,$40,$40,$7c,$40,$40,$40,$40   ; 'F'
    dc.b    $3c,$42,$40,$40,$4e,$42,$46,$3a   ; 'G'
    dc.b    $42,$42,$42,$7e,$42,$42,$42,$42   ; 'H'
    dc.b    $3e,$08,$08,$08,$08,$08,$08,$3e   ; 'I'
    dc.b    $1e,$04,$04,$04,$04,$04,$44,$38   ; 'J'
    dc.b    $42,$44,$48,$70,$48,$44,$42,$42   ; 'K'
    dc.b    $40,$40,$40,$40,$40,$40,$40,$7e   ; 'L'
    dc.b    $42,$66,$5a,$5a,$42,$42,$42,$42   ; 'M'
    dc.b    $42,$62,$52,$4a,$46,$42,$42,$42   ; 'N'
    dc.b    $3c,$42,$42,$42,$42,$42,$42,$3c   ; 'O'
    dc.b    $7c,$42,$42,$7c,$40,$40,$40,$40   ; 'P'
    dc.b    $3c,$42,$42,$42,$4a,$44,$3a,$00   ; 'Q'
    dc.b    $7c,$42,$42,$7c,$48,$44,$42,$42   ; 'R'
    dc.b    $3c,$42,$40,$3c,$02,$02,$42,$3c   ; 'S'
    dc.b    $7f,$08,$08,$08,$08,$08,$08,$08   ; 'T'
    dc.b    $42,$42,$42,$42,$42,$42,$42,$3c   ; 'U'
    dc.b    $42,$42,$42,$24,$24,$18,$18,$18   ; 'V'
    dc.b    $42,$42,$42,$5a,$5a,$66,$42,$42   ; 'W'
    dc.b    $42,$42,$24,$18,$18,$24,$42,$42   ; 'X'
    dc.b    $41,$41,$22,$14,$08,$08,$08,$08   ; 'Y'
    dc.b    $7e,$02,$04,$08,$10,$20,$40,$7e   ; 'Z'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; '['
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; backslash
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; ']'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; '^'
    dc.b    $00,$00,$00,$00,$00,$00,$00,$00   ; '_'

FaultBusy:      dc.w    0               ; set once the handler has started
FaultNTSC:      dc.w    0               ; set by DetectNTSC on a 60 Hz machine
FaultVector:    dc.w    0               ; 0 = software stop, else the vector number
FaultHave:      dc.w    0               ; FAULT_HAVE_* bits: which fields are known
FaultSR:        dc.w    0
FaultOpcode:    dc.w    0
FaultPC:        dc.l    0
FaultAccess:    dc.l    0
FaultUSP:       dc.l    0
FaultRegs:      ds.l    16              ; d0-d7, a0-a7 at the fault
FaultLine:      ds.b    48              ; one line of the report, built here
                even
FaultStack:     ds.b    256             ; the handler's own stack
FaultStackTop:

;==============================================================================
; DetectNTSC  -  Detect NTSC vs PAL and patch the game copper list if NTSC
;
; Method: wait until beam >= 256, then record highest VHPOSR low-byte.
; PAL threshold: $20 (line 288). Below threshold -> NTSC.
; Sets IsPAL(a5) and SpriteYOffset(a5). Patches cpGameDIW DIWSTRT/DIWSTOP.
; Returns d0 = 0 for PAL, 1 for NTSC.
; Destroys: d0, d1.
;==============================================================================

DetectNTSC:
    ; Step 1: wait until beam < 256 (VPOSR low byte bit 0 = 0)
.dn_wait_low:
    btst        #0,VPOSR+1(a6)
    bne.s       .dn_wait_low

    ; Step 2: wait until beam >= 256 (VPOSR low byte bit 0 = 1)
.dn_wait_high:
    btst        #0,VPOSR+1(a6)
    beq.s       .dn_wait_high

    ; Step 3: spin while beam >= 256, tracking max VHPOSR high byte
    moveq       #0,d1                   ; d1 = running maximum
.dn_spin:
    move.w      VHPOSR(a6),d0
    lsr.w       #8,d0                   ; d0.w = beam bits 7..0 (low byte of V counter)
    cmp.w       d1,d0
    blt.s       .dn_done                ; value dropped (VBlank wrap) -> stop
    move.w      d0,d1                   ; update max
    btst        #0,VPOSR+1(a6)
    bne.s       .dn_spin                ; continue while bit 8 still set
.dn_done:

    move.w      #WINDOW_Y_START,SpriteYOffset(a5)   ; default: PAL raster origin
    move.w      #1,IsPAL(a5)            ; default: PAL
    cmp.w       #$20,d1
    bge.s       .dn_pal                 ; >= $20 -> line reached 288+, must be PAL

    ; NTSC detected: recentre display
    move.w      #NTSC_WINDOW_START,cpGameDIW+2   ; patch DIWSTRT value
    move.w      #NTSC_WINDOW_STOP,cpGameDIW+6    ; patch DIWSTOP value
    move.w      #NTSC_WINDOW_Y_START,SpriteYOffset(a5)  ; patch sprite raster origin
    clr.w       IsPAL(a5)               ; NTSC: clear PAL flag
    move.w      #1,FaultNTSC            ; the fault screen cannot rely on a5
    moveq       #1,d0                   ; return 1 = NTSC
    rts

.dn_pal:
    moveq       #0,d0                   ; return 0 = PAL
    rts

;==============================================================================
; DetectOCS  -  Detect OCS vs ECS chipset via DENISEID register
;
; Reads DENISEID. Sets IsOCS(a5) = 1 (OCS) or 0 (ECS/AGA).
; Destroys: d0-d2.
;==============================================================================

DetectOCS:
    move.w      DENISEID(a6),d0
    andi.w      #$00ff,d0               ; ID lives in the low byte
    moveq       #31-1,d1                ; OCS has no register: reads float, so require a stable value
.stable:
    move.w      DENISEID(a6),d2
    andi.w      #$00ff,d2
    cmp.w       d0,d2
    bne.s       .is_ocs
    dbra        d1,.stable

    cmp.w       #DENISE_ID_ECS,d0       ; $FC = ECS Denise 8373
    beq.s       .is_ecs_aga
    cmp.w       #DENISE_ID_AGA,d0       ; $F8 = AGA Lisa
    beq.s       .is_ecs_aga
.is_ocs:
    move.w      #1,IsOCS(a5)
    rts
.is_ecs_aga:
    clr.w       IsOCS(a5)
    rts

;==============================================================================
; StartVBlank  -  Enable hardware DMA and vertical-blank interrupt
;
; Destroys: a0 (preserves everything else, including a5/a6)
;==============================================================================

StartVBlank:
    move.w      #BASE_DMA,DMACON(a6)   ; enable Copper + Blitter + Bitplane + Sprite DMA
    move.l      VBRBase,a0
    move.l      #VBlankTick,$6c(a0)
    move.w      #INTF_SETCLR|INTF_INTEN|INTF_VERTB,INTENA(a6) ; only sources VBlankTick acknowledges
    nop
    nop
    tst.w       DMACONR(a6)
    rts

;==============================================================================
; VBlankTick  -  Level-3 vertical-blank interrupt service routine
;
; Acknowledges VERTB, performs NTSC 60Hz->50Hz speed normalisation, increments
; TickCounter, tracks overruns, and increments FramePending to release MainLoop.
;
; Destroys: none (preserves all registers)
;==============================================================================

VBlankTick:
    movem.l     d0/a5-a6,-(sp)
    lea         CUSTOM,a6
    lea         Variables,a5

    move.w      INTREQR(a6),d0
    and.w       #INTF_VERTB,d0
    beq.s       .exit

    move.w      d0,INTREQ(a6)
    move.w      d0,INTREQ(a6)           ; twice to avoid A4000 hw bug

    ; NTSC speed normalisation (withhold tick on every 6th VBlank)
    tst.w       IsPAL(a5)
    bne.s       .tick
    addq.w      #1,NtscSkipPhase(a5)
    cmp.w       #6,NtscSkipPhase(a5)
    blt.s       .tick
    clr.w       NtscSkipPhase(a5)
    bra.s       .exit
.tick:
    addq.w      #1,TickCounter(a5)

    tst.w       FrameBusy(a5)           ; frame still running at this VBlank?
    beq.s       .no_overrun
    addq.w      #1,VBlankOverrunCount(a5)
.no_overrun:
    addq.w      #1,FramePending(a5)

.exit:
    movem.l     (sp)+,d0/a5-a6
    rte

;==============================================================================
; StopDriveMotors  -  Switch off the motors of all four floppy drives
;
; A game started from a floppy takes the machine over a moment after
; AmigaDOS finished loading it, while trackdisk.device's motor-off timer is
; still counting. With interrupts off that timer never fires, so without
; this the drive would spin, light on, for the whole game. Restart calls it
; once DMA and interrupts are off.
;
; A drive latches the motor line (CIA-B PRB bit 7, active low) on the edge
; where it is selected. So: deselect every drive with MTR high, select all
; four at once (each latches "motor off"), then deselect them again. The
; write that selects them also holds SIDE, DIR and STEP high (inactive), so
; no head moves.
;
; Destroys: a0
;==============================================================================

StopDriveMotors:
    lea         CIAB_BASE+$100,a0       ; $BFD100: CIA-B PRB, the drive lines
    move.b      #$ff,(a0)               ; MTR high (off), DF0-DF3 deselected
    move.b      #$87,(a0)               ; SEL0-SEL3 low: each drive latches MTR off
    move.b      #$ff,(a0)               ; deselect them all again
    rts

;==============================================================================
; ClearSprites  -  Point all 8 hardware sprite channels at NullSprite
;
; Writes the address of NullSprite (two zero longwords = a terminated, empty
; sprite structure) into all eight SPRxPTH/L copper list entries in cpSprites.
; This hides all hardware sprites from the display.
;
; Destroys: d0/d7/a0 (preserves everything else, including a5/a6)
;==============================================================================

ClearSprites:
    lea         cpSprites,a0
    move.l      #NullSprite,d0
    moveq       #8-1,d7
.loop:
    move.w      d0,6(a0)
    swap        d0
    move.w      d0,2(a0)
    swap        d0
    add.l       #8,a0
    dbra        d7,.loop
    rts


;------------------------------------------------------------------------------
; Saved OS state (written once by SystemSave, read once by SystemRestore).
; SavedOSStack is written by Main before any takeover happens.
;------------------------------------------------------------------------------
VBRBase:        dc.l    0               ; VBR base address (0 on 68000, relocated on 68010+)
SavedOSStack:   dc.l    0               ; CLI stack pointer at program entry
WBenchMsg:      dc.l    0               ; Workbench startup message (0 = CLI launch)
GfxBase:        dc.l    0               ; graphics.library base (0 = not open)
SavedView:      dc.l    0               ; view active when the game started
SavedINTENA:    dc.w    0               ; INTENAR snapshot
SavedDMACON:    dc.w    0               ; DMACONR snapshot
SavedADKCON:    dc.w    0               ; ADKCONR snapshot
SavedVec08:     dc.l    0               ; original exception/interrupt vectors
SavedVec0C:     dc.l    0
SavedVec10:     dc.l    0
SavedVec14:     dc.l    0
SavedVec20:     dc.l    0
SavedVec28:     dc.l    0
SavedVec2C:     dc.l    0
SavedVec68:     dc.l    0
SavedVec6C:     dc.l    0
SavedVec80:     dc.l    0