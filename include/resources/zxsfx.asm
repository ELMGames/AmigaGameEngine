;------------------------------------------------------------------------------
; ZX tape-load SFX  (loading screen only; safe to overwrite with TileSet/TileMask)
;
; 8-bit signed mono PCM audio samples for the three phases of the loading screen.
; Played via PTPlayer _mt_loopfx on channel 0.  The leading dc.w 0 in each is the
; idle-loop word PTPlayer uses after _mt_stopfx is called.
;------------------------------------------------------------------------------

ZxAudioDataLoad_SFXBase:
    dc.w    0                       ; PTPlayer idle-loop word (must be zero)
ZxAudioDataLoad_PCM:
    incbin  "assets/fx/zx_audio_data.wav"
ZxAudioDataLoad_PCMEnd:

ZxAudioColorLoad_SFXBase:
    dc.w    0
ZxAudioColorLoad_PCM:
    incbin  "assets/fx/zx_audio_colors.wav"
ZxAudioColorLoad_PCMEnd:

ZxAudioScreenName_SFXBase:
    dc.w    0
ZxAudioScreenName_PCM:
    incbin  "assets/fx/zx_audio_screenname.wav"
ZxAudioScreenName_PCMEnd:

;------------------------------------------------------------------------------
; ZX title-screen SFX structures  (PTPlayer SfxStructure, 12 bytes each)
;
; Passed to _mt_loopfx / _mt_stopfx in loading.asm.  SfxStructures live in
; Fast RAM (CPU-only access).  The sfx_ptr field points into the Chip RAM
; data_chip section where each sample has a leading dc.w 0 idle-loop word.
;
; Layout:  dc.l sfx_ptr  (Chip RAM ptr to sample, zero-word first)
;          dc.w sfx_len  (total words including the leading zero-word)
;          dc.w sfx_per  (Paula period: PAL 3546895/8000 Hz = 443)
;          dc.w sfx_vol  (0-64; unaffected by music master volume)
;          dc.b sfx_cha  (0-3 explicit channel; _mt_loopfx requires explicit)
;          dc.b sfx_pri  (1-127; ignored by _mt_loopfx, field must be present)
;------------------------------------------------------------------------------
ZxSfxScreenName:
    dc.l    ZxAudioScreenName_SFXBase
    dc.w    (ZxAudioScreenName_PCMEnd-ZxAudioScreenName_SFXBase)/2
    dc.w    ZX_AUDIO_PERIOD
    dc.w    ZX_AUDIO_VOL
    dc.b    0               ; channel 0 (matches original direct-Paula channel)
    dc.b    64              ; priority (ignored by loopfx, present for layout)

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