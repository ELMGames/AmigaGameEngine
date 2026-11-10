;------------------------------------------------------------------------------
; ZX tape-load SFX  (loading screen only; safe to overwrite with TileSet/TileMask)
;
; 8-bit signed mono PCM audio samples (headerless .raw files, 8000 Hz) for the
; phases of the loading screen.  Played via PTPlayer _mt_loopfx on
; channel 0.  The leading dc.w 0 in each is the idle-loop word PTPlayer uses
; after _mt_stopfx is called.
;
; Every sample loops, so each one only needs to be long enough to sound right
; when repeated; LoadingRun decides how many frames each phase lasts:
;
;   pilot   382 bytes  ~38 cycles of the ~800 Hz pilot tone, cut at rising zero
;                      crossings so the loop is seamless (both pilot phases)
;   header  800 bytes  the header block's data burst (5 PAL frames)
;   data  10480 bytes  data-block bits, looped for the whole row reveal
;   colors 9434 bytes  attribute-block bits (59 PAL frames), one pass per wash
;
; The silence between the header and the data block is not stored at all:
; LoadingRun stops the channel for ZX_GAP_FRAMES instead.
;------------------------------------------------------------------------------
; Destroys: none (preserves all registers)

ZxAudioDataLoad_SFXBase:
    dc.w    0                       ; PTPlayer idle-loop word (must be zero)
ZxAudioDataLoad_PCM:
    incbin  "assets/fx/zx_audio_data.raw"
    even
ZxAudioDataLoad_PCMEnd:

ZxAudioColorLoad_SFXBase:
    dc.w    0
ZxAudioColorLoad_PCM:
    incbin  "assets/fx/zx_audio_colors.raw"
    even
ZxAudioColorLoad_PCMEnd:

ZxAudioHeader_SFXBase:
    dc.w    0
ZxAudioHeader_PCM:
    incbin  "assets/fx/zx_audio_header.raw"
    even
ZxAudioHeader_PCMEnd:

ZxAudioPilot_SFXBase:
    dc.w    0
ZxAudioPilot_PCM:
    incbin  "assets/fx/zx_audio_pilot.raw"
    even
ZxAudioPilot_PCMEnd:

; LoadingStageAudio copies all four samples into NonDisplayScreen just past the
; 40,000-byte loading image; stop the build if they would run past its end.
    IFND LOADING_AUDIO_IN_CHIP
    IFGT LOADING_AUDIO_STAGE_OFFSET+(ZxAudioPilot_PCMEnd-ZxAudioDataLoad_SFXBase)-LEVEL_SCREEN_SIZE
    FAIL "ZX tape audio does not fit in NonDisplayScreen after the loading image"
    ENDC
    ENDC

;------------------------------------------------------------------------------
; ZX title-screen SFX structures  (PTPlayer SfxStructure, 12 bytes each)
;
; Passed to _mt_loopfx / _mt_stopfx in loading.asm.  SfxStructures live in
; Fast RAM (CPU-only access).  The sfx_ptr field is dynamically patched by
; LoadingStageAudio to point into NonDisplayScreen+40000 in Chip RAM where each
; sample is staged with a leading dc.w 0 idle-loop word.
;
; Layout:  dc.l sfx_ptr  (Chip RAM ptr to sample, zero-word first)
;          dc.w sfx_len  (total words including the leading zero-word)
;          dc.w sfx_per  (Paula period: PAL 3546895/8000 Hz = 443)
;          dc.w sfx_vol  (0-64; unaffected by music master volume)
;          dc.b sfx_cha  (0-3 explicit channel; _mt_loopfx requires explicit)
;          dc.b sfx_pri  (1-127; ignored by _mt_loopfx, field must be present)
;------------------------------------------------------------------------------
; Destroys: none (preserves all registers)
ZxSfxPilot:
    dc.l    ZxAudioPilot_SFXBase
    dc.w    (ZxAudioPilot_PCMEnd-ZxAudioPilot_SFXBase)/2
    dc.w    ZX_AUDIO_PERIOD
    dc.w    ZX_AUDIO_VOL
    dc.b    0               ; channel 0 (matches original direct-Paula channel)
    dc.b    64              ; priority (ignored by loopfx, present for layout)

ZxSfxHeader:
    dc.l    ZxAudioHeader_SFXBase
    dc.w    (ZxAudioHeader_PCMEnd-ZxAudioHeader_SFXBase)/2
    dc.w    ZX_AUDIO_PERIOD
    dc.w    ZX_AUDIO_VOL
    dc.b    0
    dc.b    64

ZxSfxDataLoad:
    dc.l    ZxAudioDataLoad_SFXBase
    dc.w    (ZxAudioDataLoad_PCMEnd-ZxAudioDataLoad_SFXBase)/2
    dc.w    ZX_AUDIO_PERIOD
    dc.w    ZX_AUDIO_VOL
    dc.b    0
    dc.b    64

ZxSfxColorLoad:
    dc.l    ZxAudioColorLoad_SFXBase
    dc.w    (ZxAudioColorLoad_PCMEnd-ZxAudioColorLoad_SFXBase)/2
    dc.w    ZX_AUDIO_PERIOD
    dc.w    ZX_AUDIO_VOL
    dc.b    0
    dc.b    64
