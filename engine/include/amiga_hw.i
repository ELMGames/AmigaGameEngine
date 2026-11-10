;==============================================================================
; AMIGA GAME ENGINE
; amiga_hw.i  -  Amiga custom chip and CIA hardware definitions
;==============================================================================
;
; Register offsets and bit positions for the OCS, ECS and AGA chipsets, written
; for this engine from the Amiga Hardware Reference Manual. Custom registers
; are offsets from CUSTOM, normally reached as NAME(a6).
;
; For the complete official AmigaOS headers, see the NDK from Hyperion
; Entertainment. This engine does not need them.
;==============================================================================

;------------------------------------------------------------------------------
; Base address and Copper list terminator
;------------------------------------------------------------------------------
CUSTOM            = $DFF000       ; custom chip register base
COPPER_HALT       = $FFFFFFFE     ; WAIT that never completes: ends a Copper list

;------------------------------------------------------------------------------
; Read registers, beam counters and ports
;------------------------------------------------------------------------------
BLTDDAT           = $000      ; Blitter destination early read
DMACONR           = $002      ; DMA control and Blitter status (read)
VPOSR             = $004      ; LOF, Agnus ID and beam V8 (read)
VHPOSR            = $006      ; beam V7-V0 and H8-H1 (read)
DSKDATR           = $008      ; disk data early read
JOY0DAT           = $00A      ; port 1 mouse/joystick counters
JOY1DAT           = $00C      ; port 2 mouse/joystick counters
CLXDAT            = $00E      ; collision data (read clears)
ADKCONR           = $010      ; audio/disk control (read)
POT0DAT           = $012      ; port 1 pot counters
POT1DAT           = $014      ; port 2 pot counters
POTINP            = $016      ; pot pin data (read)
SERDATR           = $018      ; serial data and status (read)
DSKBYTR           = $01A      ; disk byte and status (read)
INTENAR           = $01C      ; interrupt enable bits (read)
INTREQR           = $01E      ; interrupt request bits (read)

;------------------------------------------------------------------------------
; Disk, refresh, beam write, serial and strobes
;------------------------------------------------------------------------------
DSKPT             = $020
DSKPTH            = $020
DSKPTL            = $022
DSKLEN            = $024
DSKDAT            = $026
REFPTR            = $028
VPOSW             = $02A
VHPOSW            = $02C
COPCON            = $02E
SERDAT            = $030
SERPER            = $032
POTGO             = $034
JOYTEST           = $036
STREQU            = $038
STRVBL            = $03A
STRHOR            = $03C
STRLONG           = $03E

;------------------------------------------------------------------------------
; Blitter
;------------------------------------------------------------------------------
BLTCON0           = $040
BLTCON1           = $042
BLTAFWM           = $044
BLTALWM           = $046
BLTCPT            = $048
BLTCPTH           = $048
BLTCPTL           = $04A
BLTBPT            = $04C
BLTBPTH           = $04C
BLTBPTL           = $04E
BLTAPT            = $050
BLTAPTH           = $050
BLTAPTL           = $052
BLTDPT            = $054
BLTDPTH           = $054
BLTDPTL           = $056
BLTSIZE           = $058      ; writing this starts the blit
BLTCON0L          = $05A      ; ECS
BLTSIZV           = $05C      ; ECS
BLTSIZH           = $05E      ; ECS: writing this starts the blit
BLTCMOD           = $060
BLTBMOD           = $062
BLTAMOD           = $064
BLTDMOD           = $066
BLTCDAT           = $070
BLTBDAT           = $072
BLTADAT           = $074

;------------------------------------------------------------------------------
; Copper, display window and control
;------------------------------------------------------------------------------
DENISEID          = $07C      ; ECS/AGA chip ID (read)
DSKSYNC           = $07E
COP1LC            = $080
COP1LCH           = $080
COP1LCL           = $082
COP2LC            = $084
COP2LCH           = $084
COP2LCL           = $086
COPJMP1           = $088      ; strobe
COPJMP2           = $08A      ; strobe
COPINS            = $08C
DIWSTRT           = $08E
DIWSTOP           = $090
DDFSTRT           = $092
DDFSTOP           = $094
DMACON            = $096      ; DMA control (write)
CLXCON            = $098
INTENA            = $09A      ; interrupt enable (write)
INTREQ            = $09C      ; interrupt request (write)
ADKCON            = $09E      ; audio/disk control (write)

;------------------------------------------------------------------------------
; Audio channels
;------------------------------------------------------------------------------
AUD0LC            = $0A0
AUD0LCH           = $0A0
AUD0LCL           = $0A2
AUD0LEN           = $0A4
AUD0PER           = $0A6
AUD0VOL           = $0A8
AUD0DAT           = $0AA
AUD1LC            = $0B0
AUD1LCH           = $0B0
AUD1LCL           = $0B2
AUD1LEN           = $0B4
AUD1PER           = $0B6
AUD1VOL           = $0B8
AUD1DAT           = $0BA
AUD2LC            = $0C0
AUD2LCH           = $0C0
AUD2LCL           = $0C2
AUD2LEN           = $0C4
AUD2PER           = $0C6
AUD2VOL           = $0C8
AUD2DAT           = $0CA
AUD3LC            = $0D0
AUD3LCH           = $0D0
AUD3LCL           = $0D2
AUD3LEN           = $0D4
AUD3PER           = $0D6
AUD3VOL           = $0D8
AUD3DAT           = $0DA

;------------------------------------------------------------------------------
; Bitplanes
;------------------------------------------------------------------------------
BPL1PT            = $0E0
BPL1PTH           = $0E0
BPL1PTL           = $0E2
BPL2PT            = $0E4
BPL2PTH           = $0E4
BPL2PTL           = $0E6
BPL3PT            = $0E8
BPL3PTH           = $0E8
BPL3PTL           = $0EA
BPL4PT            = $0EC
BPL4PTH           = $0EC
BPL4PTL           = $0EE
BPL5PT            = $0F0
BPL5PTH           = $0F0
BPL5PTL           = $0F2
BPL6PT            = $0F4
BPL6PTH           = $0F4
BPL6PTL           = $0F6
BPL7PT            = $0F8      ; AGA
BPL7PTH           = $0F8
BPL7PTL           = $0FA
BPL8PT            = $0FC      ; AGA
BPL8PTH           = $0FC
BPL8PTL           = $0FE
BPLCON0           = $100
BPLCON1           = $102
BPLCON2           = $104
BPLCON3           = $106      ; ECS/AGA
BPL1MOD           = $108      ; odd planes
BPL2MOD           = $10A      ; even planes
BPLCON4           = $10C      ; AGA
CLXCON2           = $10E      ; AGA
BPL1DAT           = $110
BPL2DAT           = $112
BPL3DAT           = $114
BPL4DAT           = $116
BPL5DAT           = $118
BPL6DAT           = $11A
BPL7DAT           = $11C
BPL8DAT           = $11E

;------------------------------------------------------------------------------
; Sprites
;------------------------------------------------------------------------------
SPR0PT            = $120
SPR0PTH           = $120
SPR0PTL           = $122
SPR1PT            = $124
SPR1PTH           = $124
SPR1PTL           = $126
SPR2PT            = $128
SPR2PTH           = $128
SPR2PTL           = $12A
SPR3PT            = $12C
SPR3PTH           = $12C
SPR3PTL           = $12E
SPR4PT            = $130
SPR4PTH           = $130
SPR4PTL           = $132
SPR5PT            = $134
SPR5PTH           = $134
SPR5PTL           = $136
SPR6PT            = $138
SPR6PTH           = $138
SPR6PTL           = $13A
SPR7PT            = $13C
SPR7PTH           = $13C
SPR7PTL           = $13E
SPR0POS           = $140
SPR0CTL           = $142
SPR0DATA          = $144
SPR0DATB          = $146
SPR1POS           = $148
SPR1CTL           = $14A
SPR1DATA          = $14C
SPR1DATB          = $14E
SPR2POS           = $150
SPR2CTL           = $152
SPR2DATA          = $154
SPR2DATB          = $156
SPR3POS           = $158
SPR3CTL           = $15A
SPR3DATA          = $15C
SPR3DATB          = $15E
SPR4POS           = $160
SPR4CTL           = $162
SPR4DATA          = $164
SPR4DATB          = $166
SPR5POS           = $168
SPR5CTL           = $16A
SPR5DATA          = $16C
SPR5DATB          = $16E
SPR6POS           = $170
SPR6CTL           = $172
SPR6DATA          = $174
SPR6DATB          = $176
SPR7POS           = $178
SPR7CTL           = $17A
SPR7DATA          = $17C
SPR7DATB          = $17E

;------------------------------------------------------------------------------
; Colour registers
;------------------------------------------------------------------------------
COLOR00           = $180
COLOR01           = $182
COLOR02           = $184
COLOR03           = $186
COLOR04           = $188
COLOR05           = $18A
COLOR06           = $18C
COLOR07           = $18E
COLOR08           = $190
COLOR09           = $192
COLOR10           = $194
COLOR11           = $196
COLOR12           = $198
COLOR13           = $19A
COLOR14           = $19C
COLOR15           = $19E
COLOR16           = $1A0
COLOR17           = $1A2
COLOR18           = $1A4
COLOR19           = $1A6
COLOR20           = $1A8
COLOR21           = $1AA
COLOR22           = $1AC
COLOR23           = $1AE
COLOR24           = $1B0
COLOR25           = $1B2
COLOR26           = $1B4
COLOR27           = $1B6
COLOR28           = $1B8
COLOR29           = $1BA
COLOR30           = $1BC
COLOR31           = $1BE

;------------------------------------------------------------------------------
; ECS and AGA beam and fetch control
;------------------------------------------------------------------------------
HTOTAL            = $1C0
HSSTOP            = $1C2
HBSTRT            = $1C4
HBSTOP            = $1C6
VTOTAL            = $1C8
VSSTOP            = $1CA
VBSTRT            = $1CC
VBSTOP            = $1CE
BEAMCON0          = $1DC
HSSTRT            = $1DE
VSSTRT            = $1E0
HCENTER           = $1E2
DIWHIGH           = $1E4
FMODE             = $1FC

;------------------------------------------------------------------------------
; Lower-case names used by the keyboard handler
;------------------------------------------------------------------------------
intreq            = $09C
intreqr           = $01E
vhposr            = $006

;------------------------------------------------------------------------------
; DMACON and DMACONR bits
;------------------------------------------------------------------------------
DMAB_SETCLR       = $0F
DMAF_SETCLR       = $8000
DMAB_BLTDONE      = $0E
DMAF_BLTDONE      = $4000
DMAB_BLTNZERO     = $0D
DMAF_BLTNZERO     = $2000
DMAB_BLITHOG      = $0A
DMAF_BLITHOG      = $0400
DMAB_MASTER       = $09
DMAF_MASTER       = $0200
DMAB_RASTER       = $08
DMAF_RASTER       = $0100
DMAB_COPPER       = $07
DMAF_COPPER       = $0080
DMAB_BLITTER      = $06
DMAF_BLITTER      = $0040
DMAB_SPRITE       = $05
DMAF_SPRITE       = $0020
DMAB_DISK         = $04
DMAF_DISK         = $0010
DMAB_AUD3         = $03
DMAF_AUD3         = $0008
DMAB_AUD2         = $02
DMAF_AUD2         = $0004
DMAB_AUD1         = $01
DMAF_AUD1         = $0002
DMAB_AUD0         = $00
DMAF_AUD0         = $0001
DMAF_AUDIO        = $000F     ; all four audio channels
DMAF_ALL          = $01FF     ; every DMA channel

;------------------------------------------------------------------------------
; INTENA and INTREQ bits
;------------------------------------------------------------------------------
INTB_SETCLR       = $0F
INTF_SETCLR       = $8000
INTB_INTEN        = $0E
INTF_INTEN        = $4000
INTB_EXTER        = $0D
INTF_EXTER        = $2000
INTB_DSKSYNC      = $0C
INTF_DSKSYNC      = $1000
INTB_RBF          = $0B
INTF_RBF          = $0800
INTB_AUD3         = $0A
INTF_AUD3         = $0400
INTB_AUD2         = $09
INTF_AUD2         = $0200
INTB_AUD1         = $08
INTF_AUD1         = $0100
INTB_AUD0         = $07
INTF_AUD0         = $0080
INTB_BLIT         = $06
INTF_BLIT         = $0040
INTB_VERTB        = $05
INTF_VERTB        = $0020
INTB_COPER        = $04
INTF_COPER        = $0010
INTB_PORTS        = $03
INTF_PORTS        = $0008
INTB_SOFTINT      = $02
INTF_SOFTINT      = $0004
INTB_DSKBLK       = $01
INTF_DSKBLK       = $0002
INTB_TBE          = $00
INTF_TBE          = $0001

;------------------------------------------------------------------------------
; CIA registers: offsets from $BFE001 (CIA-A) or $BFD000 (CIA-B)
;------------------------------------------------------------------------------
ciapra            = $0000
ciaprb            = $0100
ciaddra           = $0200
ciaddrb           = $0300
ciatalo           = $0400
ciatahi           = $0500
ciatblo           = $0600
ciatbhi           = $0700
ciatodlow         = $0800
ciatodmid         = $0900
ciatodhi          = $0A00
ciasdr            = $0C00
ciaicr            = $0D00
ciacra            = $0E00
ciacrb            = $0F00

;------------------------------------------------------------------------------
; CIA interrupt control and timer control bits
;------------------------------------------------------------------------------
CIAICRB_TA        = $00
CIAICRF_TA        = $01
CIAICRB_TB        = $01
CIAICRF_TB        = $02
CIAICRB_ALRM      = $02
CIAICRF_ALRM      = $04
CIAICRB_SP        = $03
CIAICRF_SP        = $08
CIAICRB_FLG       = $04
CIAICRF_FLG       = $10
CIAICRB_IR        = $07
CIAICRF_IR        = $80
CIAICRB_SETCLR    = $07
CIAICRF_SETCLR    = $80
CIACRAB_START     = $00
CIACRAF_START     = $01
CIACRAB_PBON      = $01
CIACRAF_PBON      = $02
CIACRAB_OUTMODE   = $02
CIACRAF_OUTMODE   = $04
CIACRAB_RUNMODE   = $03
CIACRAF_RUNMODE   = $08
CIACRAB_LOAD      = $04
CIACRAF_LOAD      = $10
CIACRAB_INMODE    = $05
CIACRAF_INMODE    = $20
CIACRAB_SPMODE    = $06
CIACRAF_SPMODE    = $40
CIACRAB_TODIN     = $07
CIACRAF_TODIN     = $80
CIACRBB_START     = $00
CIACRBF_START     = $01
CIACRBB_PBON      = $01
CIACRBF_PBON      = $02
CIACRBB_OUTMODE   = $02
CIACRBF_OUTMODE   = $04
CIACRBB_RUNMODE   = $03
CIACRBF_RUNMODE   = $08
CIACRBB_LOAD      = $04
CIACRBF_LOAD      = $10
CIACRBB_INMODE0   = $05
CIACRBF_INMODE0   = $20
CIACRBB_INMODE1   = $06
CIACRBF_INMODE1   = $40
CIACRBB_ALARM     = $07
CIACRBF_ALARM     = $80
