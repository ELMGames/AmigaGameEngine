;==============================================================================
; AMIGA GAME ENGINE
; customlevel.asm  -  Pre-Boot AmigaDOS Custom Level Loader (test.lvl)
;==============================================================================
;
; Allows users to design levels in Tiled (.tmx), export them to a single
; standalone binary package (.lvl), and test them immediately with the shipped
; game binary without re-assembling or re-linking.
;
; Mechanics:
;   1. Invoked from Main before SystemSave takes over custom hardware.
;      At this point, AmigaDOS and exec.library are 100% active.
;   2. Parses CLI argument string (if any), otherwise defaults to "test.lvl".
;   3. Attempts to open the file via dos.library Open(..., MODE_OLDFILE).
;   4. If present:
;      - Allocates 32 KB buffer via Exec AllocMem(..., MEMF_PUBLIC)
;      - Reads the level package via dos.library Read(...)
;      - Validates magic header ('ALVL')
;      - Rebases internal relative offsets into absolute memory pointers
;      - Sets CustomLevelLoaded(a5) = 1 and CustomLevelDef(a5) = pointer
;   5. Closes file and dos.library, then returns to mainline.
;   6. On game exit (QuitToOS), any allocated buffer is freed via FreeMem.
;
;==============================================================================

_LVOAllocMem           = -198
_LVOFreeMem            = -210

_LVOOpen               = -30
_LVOClose              = -36
_LVORead               = -42

MODE_OLDFILE           = 1005
MEMF_PUBLIC            = 1
MAX_CUSTOM_LEVEL_SIZE  = 32768

;==============================================================================
; CheckCustomLevel
;
; Inputs:
;   d0 = CLI arg string length
;   a0 = CLI arg string pointer
;
; Preserves: all registers
;==============================================================================

CheckCustomLevel:
    movem.l    d0-d7/a0-a6,-(sp)

    lea        Variables,a5
    clr.w      CustomLevelLoaded(a5)
    clr.l      CustomLevelDef(a5)
    clr.l      CustomLevelAllocPtr(a5)
    clr.l      CustomLevelAllocSize(a5)

    ; 1. Check CLI arguments in a0/d0
    lea        CustomLevel_DefaultName(pc),a2
    tst.l      d0
    ble.s      .have_filename
    cmp.l      #1,d0
    ble.s      .have_filename

    ; Skip leading spaces / tabs
.skip_ws:
    move.b     (a0)+,d1
    subq.l     #1,d0
    beq.s      .have_filename
    cmp.b      #' ',d1
    beq.s      .skip_ws
    cmp.b      #9,d1                     ; tab
    beq.s      .skip_ws
    cmp.b      #10,d1                    ; newline
    beq.s      .have_filename
    cmp.b      #0,d1
    beq.s      .have_filename

    ; Copy filename characters into CustomFileName buffer
    lea        CustomFileName(pc),a1
    move.b     d1,(a1)+
.copy_char:
    tst.l      d0
    ble.s      .done_char
    move.b     (a0)+,d1
    subq.l     #1,d0
    cmp.b      #' ',d1
    beq.s      .done_char
    cmp.b      #10,d1                    ; newline
    beq.s      .done_char
    cmp.b      #0,d1
    beq.s      .done_char
    move.b     d1,(a1)+
    bra.s      .copy_char
.done_char:
    clr.b      (a1)
    lea        CustomFileName(pc),a2

.have_filename:
    ; 2. Open dos.library
    move.l     4.w,a6                    ; ExecBase
    lea        CustomLevel_DosName(pc),a1
    moveq      #0,d0
    jsr        _LVOOpenLibrary(a6)
    tst.l      d0
    beq        .exit
    move.l     d0,DOSBase_Save
    movea.l    d0,a6                     ; a6 = DOSBase

    ; 3. Try to open the file
    move.l     a2,d1                     ; name
    move.l     #MODE_OLDFILE,d2
    jsr        _LVOOpen(a6)
    tst.l      d0
    beq        .close_dos                ; file does not exist -> exit cleanly
    move.l     d0,d7                     ; d7 = fileHandle

    ; 4. Allocate buffer (32 KB) via Exec AllocMem
    move.l     4.w,a6                  ; a6 = ExecBase
    move.l     #MAX_CUSTOM_LEVEL_SIZE,d0
    move.l     #MEMF_PUBLIC,d1
    jsr        _LVOAllocMem(a6)
    movea.l    DOSBase_Save(pc),a6     ; restore a6 = DOSBase
    tst.l      d0
    beq.s      .close_file             ; out of memory
    move.l     d0,a4                   ; a4 = buffer pointer

    ; 5. Read file into buffer
    move.l     d7,d1                   ; fileHandle
    move.l     a4,d2                   ; buffer
    move.l     #MAX_CUSTOM_LEVEL_SIZE,d3 ; length
    jsr        _LVORead(a6)
    tst.l      d0
    ble.s      .free_and_close         ; read failed

    ; 6. Validate magic identifier ('ALVL' = $414C564C)
    cmpi.l     #$414C564C,(a4)
    bne.s      .free_and_close

    ; 7. Rebase internal relative offsets
    move.l     a4,a0                   ; a0 = file buffer base
    bsr        RebaseCustomLevel

    ; Mark custom level loaded
    lea        Variables,a5
    move.w     #1,CustomLevelLoaded(a5)
    lea        8(a4),a1
    move.l     a1,CustomLevelDef(a5)
    move.l     a4,CustomLevelAllocPtr(a5)
    move.l     #MAX_CUSTOM_LEVEL_SIZE,CustomLevelAllocSize(a5)

    ; Close file handle
    move.l     d7,d1
    jsr        _LVOClose(a6)
    bra.s      .close_dos

.free_and_close:
    move.l     4.w,a6                  ; a6 = ExecBase
    move.l     a4,a1
    move.l     #MAX_CUSTOM_LEVEL_SIZE,d0
    jsr        _LVOFreeMem(a6)
    movea.l    DOSBase_Save(pc),a6     ; restore a6 = DOSBase

.close_file:
    move.l     d7,d1
    jsr        _LVOClose(a6)

.close_dos:
    move.l     4.w,a6                  ; a6 = ExecBase
    move.l     DOSBase_Save(pc),a1
    jsr        _LVOCloseLibrary(a6)

.exit:
    movem.l    (sp)+,d0-d7/a0-a6
    rts


;==============================================================================
; RebaseCustomLevel  -  Convert file relative offsets to absolute RAM pointers
;
; In:
;   a0 = pointer to loaded .lvl buffer start
; Destroys:
;   a1, a2, d0, d7
;==============================================================================

RebaseCustomLevel:
    lea        8(a0),a1                  ; a1 -> LevelDef record
    move.l     a0,d7                     ; d7 = buffer base for 68000 ADD.L Dn,<ea>

    ; Visuals: if 0, substitute engine defaults
    tst.l      LevelDef_TilesetRaw(a1)
    bne.s      .has_custom_tileset
    move.l     #GameTilesRaw,LevelDef_TilesetRaw(a1)
    move.l     #GameTilesMsk,LevelDef_TilesetMsk(a1)
    bra.s      .tileset_done
.has_custom_tileset:
    add.l      d7,LevelDef_TilesetRaw(a1)
    add.l      d7,LevelDef_TilesetMsk(a1)
.tileset_done:

    tst.l      LevelDef_Palette(a1)
    bne.s      .has_custom_pal
    move.l     #Level_01_Palette,LevelDef_Palette(a1)
    bra.s      .pal_done
.has_custom_pal:
    add.l      d7,LevelDef_Palette(a1)
.pal_done:

    tst.l      LevelDef_Music(a1)
    bne.s      .has_custom_music
    move.l     #LevelMod,LevelDef_Music(a1)
    bra.s      .music_done
.has_custom_music:
    add.l      d7,LevelDef_Music(a1)
.music_done:

    ; Rebase standard map and entity pointer fields
    lea        .rebase_field_offsets(pc),a2
.rebase_loop:
    move.w     (a2)+,d0
    bmi.s      .rebase_done
    tst.l      (a1,d0.w)
    beq.s      .rebase_loop
    add.l      d7,(a1,d0.w)
    bra.s      .rebase_loop

.rebase_done:
    ; Rebase LayerList elements
    move.l     LevelDef_LayerList(a1),d0
    beq.s      .layer_list_done
    movea.l    d0,a2
.layer_elem_loop:
    tst.l      (a2)
    beq.s      .layer_list_done
    add.l      d7,(a2)+
    bra.s      .layer_elem_loop

.layer_list_done:
    rts

.rebase_field_offsets:
    dc.w       LevelDef_BackgroundMap
    dc.w       LevelDef_PlatformMap
    dc.w       LevelDef_LadderMap
    dc.w       LevelDef_ForegroundMap
    dc.w       LevelDef_WaterMap
    dc.w       LevelDef_LayerList
    dc.w       LevelDef_GameMap
    dc.w       LevelDef_EnemyList
    dc.w       LevelDef_FriendList
    dc.w       LevelDef_BlockList
    dc.w       LevelDef_LadderList
    dc.w       LevelDef_SolidList
    dc.w       LevelDef_TriggerList
    dc.w       LevelDef_HazardList
    dc.w       LevelDef_BridgeList
    dc.w       LevelDef_OxygenList
    dc.w       LevelDef_TitleStr
    dc.w       LevelDef_SubTitleStr
    dc.w       -1

; Static strings and storage for custom level loader
CustomLevel_DosName:
    dc.b       "dos.library",0
CustomLevel_DefaultName:
    dc.b       "test.lvl",0
    even

DOSBase_Save:
    dc.l       0

CustomFileName:
    ds.b       128
    even

