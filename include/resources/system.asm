
;==============================================================================
; AMIGA GAME ENGINE
; system.asm  -  OS Takeover and Restore
;==============================================================================
;
; Minimal "kill the OS politely" module.  The game takes over the machine at
; the hardware level (own copper list, own interrupt vectors, all DMA), but
; snapshots enough state on the way in that it can hand the machine back to
; AmigaOS and return cleanly to the CLI — invaluable during development on
; real hardware and emulators.
;
;   SystemSave     - call ONCE at program entry, while the OS is still alive.
;                    Opens graphics.library, blanks the OS display (LoadView),
;                    takes the blitter, forbids task switching, and snapshots
;                    INTENA / DMACON and every interrupt vector the game
;                    overwrites.
;
;   SystemRestore  - call ONCE on the way out (QuitToOS in main.asm).
;                    Disables all game DMA/interrupts, restores the saved
;                    vectors and enable masks, restarts the OS copper list,
;                    re-enables multitasking and puts the OS display back.
;
; Library calls use raw, ABI-stable LVO offsets (defined below) so this file
; has no dependency on the NDK includes.
;
; CPU note: handles 68010+ relocated VBR via GetVBR and flushes CPU caches on
; 68020+ machines via ClearCPUCache.
;
;==============================================================================

; exec.library LVOs
_LVOSupervisor      = -30
_LVOForbid          = -132
_LVOPermit          = -138
_LVOCloseLibrary    = -414
_LVOOpenLibrary     = -552
_LVOCacheClearU     = -636

AFF_68010           = 0
AFF_68020           = 1

; graphics.library LVOs and GfxBase field offsets
_LVOLoadView        = -222
_LVOWaitTOF         = -270
_LVOOwnBlitter      = -456
_LVODisownBlitter   = -462
gb_ActiView         = 34
gb_copinit          = 38


;==============================================================================
; GetVBR  -  Get Vector Base Register address (returns A0 = VBR base)
;
; On 68000, VBR is always 0. On 68010+, reads VBR via Supervisor mode.
; Preserves all registers except A0.
;==============================================================================

GetVBR:
    movem.l     d0-d7/a1-a6,-(sp)
    suba.l      a0,a0                   ; default A0 = 0 (68000)
    move.l      4.w,a6                  ; ExecBase
    btst        #AFF_68010,296(a6)      ; AttnFlags bit 0 (68010+)
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
; Safe to call on any CPU; executes CacheClearU if running on a 68020+.
; Preserves all registers.
;==============================================================================

ClearCPUCache:
    movem.l     d0-d1/a0-a1/a6,-(sp)
    move.l      4.w,a6
    btst        #AFF_68020,296(a6)      ; AttnFlags bit 1 (68020+)
    beq.s       .no_cache
    jsr         _LVOCacheClearU(a6)
.no_cache:
    movem.l     (sp)+,d0-d1/a0-a1/a6
    rts


;==============================================================================
; SystemSave  -  Take over the machine (call while the OS is still running)
;
; Must be called before Init installs any handlers, so the snapshots capture
; the ORIGINAL OS values.  Runs on the OS-provided stack.
; Destroys d0-d1/a0-a1/a6 (Main does not need them preserved at entry).
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

    ; Stop task switching for the duration of the game
    move.l      4.w,a6
    jsr         _LVOForbid(a6)
.no_gfx

    ; Snapshot the hardware enable masks
    lea         $dff000,a0
    move.w      INTENAR(a0),SavedINTENA
    move.w      DMACONR(a0),SavedDMACON

    ; Snapshot every vector the game overwrites (Init / KeyboardInit /
    ; StartVBlank). Handles 68010+ relocated VBR.
    bsr         GetVBR                  ; returns a0 = VBR base (0 on 68000)
    move.l      a0,VBRBase              ; store VBR base address

    move.l      $8(a0),SavedVec08       ; bus error
    move.l      $c(a0),SavedVec0C       ; address error
    move.l      $10(a0),SavedVec10      ; illegal instruction
    move.l      $14(a0),SavedVec14      ; zero divide
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
; Destroys d0-d1/a0-a1/a6.
;==============================================================================

SystemRestore:
    ; Silence everything the game had running
    lea         $dff000,a0
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
    move.l      SavedVec68,$68(a0)
    move.l      SavedVec6C,$6c(a0)
    move.l      SavedVec80,$80(a0)

    bsr         ClearCPUCache           ; flush CPU caches before returning to OS

    move.l      GfxBase,d0
    beq.s       .no_gfx

    ; Restart the OS boot copper list so the display hardware is sane
    move.l      d0,a6
    lea         $dff000,a0              ; reload custom chip base (a0 was VBRBase)
    move.l      gb_copinit(a6),COP1LC(a0)
    move.w      #0,COPJMP1(a0)

    ; Re-enable the DMA channels and interrupts the OS had active
    move.w      SavedDMACON,d0
    or.w        #$8200,d0               ; SETCLR + MASTER
    move.w      d0,DMACON(a0)
    move.w      SavedINTENA,d0
    or.w        #$c000,d0               ; SETCLR + INTEN
    move.w      d0,INTENA(a0)

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


;------------------------------------------------------------------------------
; Saved OS state (written once by SystemSave, read once by SystemRestore).
; SavedOSStack is written by Main before any takeover happens.
;------------------------------------------------------------------------------
VBRBase:        dc.l    0               ; VBR base address (0 on 68000, relocated on 68010+)
SavedOSStack:   dc.l    0               ; CLI stack pointer at program entry
GfxBase:        dc.l    0               ; graphics.library base (0 = not open)
SavedView:      dc.l    0               ; view active when the game started
SavedINTENA:    dc.w    0               ; INTENAR snapshot
SavedDMACON:    dc.w    0               ; DMACONR snapshot
SavedVec08:     dc.l    0               ; original exception/interrupt vectors
SavedVec0C:     dc.l    0
SavedVec10:     dc.l    0
SavedVec14:     dc.l    0
SavedVec68:     dc.l    0
SavedVec6C:     dc.l    0
SavedVec80:     dc.l    0

