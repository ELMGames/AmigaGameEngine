;==============================================================================
; DUCK RESCUE
; hud_sprite_data.asm  -  Hardware sprite images for the HUD (Chip RAM)
;==============================================================================
;
; Lives counter (SPR0, pulsing), oxygen kit inventory (SPR2) and animal-friend
; counter (SPR3) sprite images, plus the lookup tables hud_sprites.asm uses to
; patch cpSprites each frame. Included from main.asm immediately before the
; engine's bubble_sprite.asm so the Chip RAM layout matches the original build.
;==============================================================================

    section    data_chip,data_c

; -----------------------------------------------------------------------------
; Player Lives Sprites (SPR0, 16px wide x 9 scanlines)
;
; Animated Heartbeat HUD Indicator:
; Displays a polished arcade heart icon alongside the remaining lives count
; (0..3) using crisp white 5x5 font.
;
; Features a living cardiac rhythm animation:
;   - Frame 0 (Normal): 7x7 resting heart
;   - Frame 1 (Large):  8x8 expanded systolic pulse (larger)
;   - Frame 2 (Small):  6x5 contracted diastolic pulse (smaller)
;
; In-game rhythm:
;   - 2+ lives: Calm resting heartbeat (64 frames = ~1.28s, 47 bpm)
;   - 1 life:   Rapid urgent heartbeat (32 frames = ~0.64s, 94 bpm)
;   - 0 lives:  Flatline at resting frame 0 (no pulse)
;
; Colors (COLOR17..19):
;   Color 1 (Plane 0=1, Plane 1=0): Outline (Dark Maroon $0601)
;   Color 2 (Plane 0=0, Plane 1=1): Body (Vivid Arcade Red $0F22)
;   Color 3 (Plane 0=1, Plane 1=1): White Specular Glint & Number ($0FFF)
; -----------------------------------------------------------------------------

; --- Frame 0: Normal / Rest Heart (7x7) ---
SpriteLives_0:
SpriteLives_0_Norm:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3600,$0000
    dc.w    $593E,$363E
    dc.w    $6122,$3E22
    dc.w    $4122,$3E22
    dc.w    $2222,$1C22
    dc.w    $143E,$083E
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_1:
SpriteLives_1_Norm:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3600,$0000
    dc.w    $5908,$3608
    dc.w    $6118,$3E18
    dc.w    $4108,$3E08
    dc.w    $2208,$1C08
    dc.w    $143E,$083E
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_2:
SpriteLives_2_Norm:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3600,$0000
    dc.w    $593E,$363E
    dc.w    $6102,$3E02
    dc.w    $413E,$3E3E
    dc.w    $2220,$1C20
    dc.w    $143E,$083E
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_3:
SpriteLives_3_Norm:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3600,$0000
    dc.w    $593E,$363E
    dc.w    $6102,$3E02
    dc.w    $411C,$3E1C
    dc.w    $2202,$1C02
    dc.w    $143E,$083E
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

; --- Frame 1: Large / Expanded Pulse (8x8) ---
; Destroys: none (preserves all registers)
SpriteLives_0_Large:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $6600,$0000
    dc.w    $B93E,$763E
    dc.w    $E122,$7E22
    dc.w    $8122,$7E22
    dc.w    $4222,$3C22
    dc.w    $223E,$1C3E
    dc.w    $1400,$0800
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_1_Large:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $6600,$0000
    dc.w    $B908,$7608
    dc.w    $E118,$7E18
    dc.w    $8108,$7E08
    dc.w    $4208,$3C08
    dc.w    $223E,$1C3E
    dc.w    $1400,$0800
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_2_Large:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $6600,$0000
    dc.w    $B93E,$763E
    dc.w    $E102,$7E02
    dc.w    $813E,$7E3E
    dc.w    $4220,$3C20
    dc.w    $223E,$1C3E
    dc.w    $1400,$0800
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_3_Large:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $6600,$0000
    dc.w    $B93E,$763E
    dc.w    $E102,$7E02
    dc.w    $811C,$7E1C
    dc.w    $4202,$3C02
    dc.w    $223E,$1C3E
    dc.w    $1400,$0800
    dc.w    $0800,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

; --- Frame 2: Small / Contracted Pulse (6x5) ---
; Destroys: none (preserves all registers)
SpriteLives_0_Small:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $0000,$0000
    dc.w    $243E,$003E
    dc.w    $7A22,$2422
    dc.w    $4222,$3C22
    dc.w    $2422,$1822
    dc.w    $183E,$003E
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_1_Small:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $0000,$0000
    dc.w    $2408,$0008
    dc.w    $7A18,$2418
    dc.w    $4208,$3C08
    dc.w    $2408,$1808
    dc.w    $183E,$003E
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_2_Small:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $0000,$0000
    dc.w    $243E,$003E
    dc.w    $7A02,$2402
    dc.w    $423E,$3C3E
    dc.w    $2420,$1820
    dc.w    $183E,$003E
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteLives_3_Small:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $0000,$0000
    dc.w    $243E,$003E
    dc.w    $7A02,$2402
    dc.w    $421C,$3C1C
    dc.w    $2402,$1802
    dc.w    $183E,$003E
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

; --- Table of 12 sprite pointers: 3 anim frames x 4 life counts ---
; Destroys: none (preserves all registers)
SpriteLives_Table:
    ; Frame 0: Normal / Rest (7x7)
    dc.l    SpriteLives_0
    dc.l    SpriteLives_1
    dc.l    SpriteLives_2
    dc.l    SpriteLives_3

    ; Frame 1: Large / Expanded Pulse (8x8)
    dc.l    SpriteLives_0_Large
    dc.l    SpriteLives_1_Large
    dc.l    SpriteLives_2_Large
    dc.l    SpriteLives_3_Large

    ; Frame 2: Small / Contracted Pulse (6x5)
    dc.l    SpriteLives_0_Small
    dc.l    SpriteLives_1_Small
    dc.l    SpriteLives_2_Small
    dc.l    SpriteLives_3_Small


; -----------------------------------------------------------------------------
; Oxygen Kit Inventory Sprite (SPR2, 16px wide x 13 scanlines)
;
; Displayed to the right of the lives counter when an oxygen bottle is in inventory.
;
; Colors:
;   Color 1 (Plane 0=1, Plane 1=0): Outline (Navy $0024)
;   Color 2 (Plane 0=0, Plane 1=1): Body (Neon Cyan $02DF)
;   Color 3 (Plane 0=1, Plane 1=1): Cap, Valve & Highlight (White $0FFF)
; -----------------------------------------------------------------------------
; Destroys: none (preserves all registers)

SpriteOxygenKit:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $03C0,$0180                 ; Row 0: Valve knob (White with dark outline)
    dc.w    $0180,$0000                 ; Row 1: Valve neck (Dark outline)
    dc.w    $07E0,$0000                 ; Row 2: Bottle shoulder top (Dark outline)
    dc.w    $0C20,$07C0                 ; Row 3: Bottle shoulder curve (Cyan with White highlight)
    dc.w    $0E20,$07C0                 ; Row 4: Cylinder body 1
    dc.w    $0E20,$07C0                 ; Row 5: Cylinder body 2
    dc.w    $0E20,$07C0                 ; Row 6: Cylinder body 3
    dc.w    $0E20,$07C0                 ; Row 7: Cylinder body 4
    dc.w    $0E20,$07C0                 ; Row 8: Cylinder body 5
    dc.w    $0E20,$07C0                 ; Row 9: Cylinder body 6
    dc.w    $0C20,$07C0                 ; Row 10: Lower cylinder
    dc.w    $07E0,$0000                 ; Row 11: Base boot
    dc.w    $03C0,$0000                 ; Row 12: Base bottom outline
    dc.w    0,0                         ; terminator


; -----------------------------------------------------------------------------
; Friends Remaining Counter Sprites (SPR3, 16px wide x 9 scanlines)
;
; Displays a cute 7x7 baby hero badge icon alongside the remaining count
; (0..16) using the exact same 5x5 font and pure white ($0FFF) color as the
; player lives counter.
;
; Colors (shared with SPR2 Oxygen Kit via COLOR21..23):
;   Color 1 (Plane 0=1, Plane 1=0): Outline, Eye & Beak (Amber Orange $0E71)
;   Color 2 (Plane 0=0, Plane 1=1): Yellow Hero Body (Golden Yellow $0FD1)
;   Color 3 (Plane 0=1, Plane 1=1): White Wing Sparkle & Number (Crisp White $0FFF)
; -----------------------------------------------------------------------------
; Destroys: none (preserves all registers)

SpriteFriends_0:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E22,$2022
    dc.w    $C222,$3C22
    dc.w    $C222,$7C22
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_1:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $4808,$3008
    dc.w    $5E18,$2018
    dc.w    $C208,$3C08
    dc.w    $C208,$7C08
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_2:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E02,$2002
    dc.w    $C23E,$3C3E
    dc.w    $C220,$7C20
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_3:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E02,$2002
    dc.w    $C21C,$3C1C
    dc.w    $C202,$7C02
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_4:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $4822,$3022
    dc.w    $5E22,$2022
    dc.w    $C23E,$3C3E
    dc.w    $C202,$7C02
    dc.w    $4402,$3802
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_5:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E20,$2020
    dc.w    $C23E,$3C3E
    dc.w    $C202,$7C02
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_6:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E20,$2020
    dc.w    $C23E,$3C3E
    dc.w    $C222,$7C22
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_7:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E02,$2002
    dc.w    $C204,$3C04
    dc.w    $C208,$7C08
    dc.w    $4408,$3808
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_8:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E22,$2022
    dc.w    $C23E,$3C3E
    dc.w    $C222,$7C22
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_9:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $483E,$303E
    dc.w    $5E22,$2022
    dc.w    $C23E,$3C3E
    dc.w    $C202,$7C02
    dc.w    $443E,$383E
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_10:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48BE,$30BE
    dc.w    $5EA2,$20A2
    dc.w    $C2A2,$3CA2
    dc.w    $C2A2,$7CA2
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_11:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $4888,$3088
    dc.w    $5E98,$2098
    dc.w    $C288,$3C88
    dc.w    $C288,$7C88
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_12:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48BE,$30BE
    dc.w    $5E82,$2082
    dc.w    $C2BE,$3CBE
    dc.w    $C2A0,$7CA0
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_13:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48BE,$30BE
    dc.w    $5E82,$2082
    dc.w    $C29C,$3C9C
    dc.w    $C282,$7C82
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_14:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48A2,$30A2
    dc.w    $5EA2,$20A2
    dc.w    $C2BE,$3CBE
    dc.w    $C282,$7C82
    dc.w    $4482,$3882
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_15:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48BE,$30BE
    dc.w    $5EA0,$20A0
    dc.w    $C2BE,$3CBE
    dc.w    $C282,$7C82
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_16:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    dc.w    $3800,$0000
    dc.w    $48BE,$30BE
    dc.w    $5EA0,$20A0
    dc.w    $C2BE,$3CBE
    dc.w    $C2A2,$7CA2
    dc.w    $44BE,$38BE
    dc.w    $3800,$0000
    dc.w    $0000,$0000
    dc.w    $0000,$0000
    dc.w    0,0                         ; terminator

SpriteFriends_Table:
    dc.l    SpriteFriends_0
    dc.l    SpriteFriends_1
    dc.l    SpriteFriends_2
    dc.l    SpriteFriends_3
    dc.l    SpriteFriends_4
    dc.l    SpriteFriends_5
    dc.l    SpriteFriends_6
    dc.l    SpriteFriends_7
    dc.l    SpriteFriends_8
    dc.l    SpriteFriends_9
    dc.l    SpriteFriends_10
    dc.l    SpriteFriends_11
    dc.l    SpriteFriends_12
    dc.l    SpriteFriends_13
    dc.l    SpriteFriends_14
    dc.l    SpriteFriends_15
    dc.l    SpriteFriends_16

; -----------------------------------------------------------------------------
; Oxygen Gauge Sprite (SPR4, 16px wide x 28 scanlines)
;
; Colors:
;   Color 1 (Plane 0=1, Plane 1=0): White Text & Vial Borders ($0FFF)
;   Color 2 (Plane 0=0, Plane 1=1): Neon Cyan Oxygen Liquid ($02DF)
;   Color 3 (Plane 0=1, Plane 1=1): Deep Navy Empty Chamber ($0024)
; -----------------------------------------------------------------------------
; Destroys: none (preserves all registers)

SpriteOxy:
    dc.w    0,0                         ; header (patched by InitHUDSprites)
    ; Rows 0-4: 'O X Y' text (3x5 font, Color 1 White)
    dc.w    $3AA8,$0000
    dc.w    $2AA8,$0000
    dc.w    $2910,$0000
    dc.w    $2A90,$0000
    dc.w    $3A90,$0000
    ; Row 5: Blank separator gap
    dc.w    $0000,$0000
    ; Row 6: Vial top cap (shifted 1px left: cols 2..11)
    dc.w    $3FF0,$0000
    ; Rows 7-26: 20 liquid fill rows (Plane 1 statically $1FE0, Plane 0 updated dynamically)
    rept    20
    dc.w    $2010,$1FE0
    endr
    ; Row 27: Vial bottom cap
    dc.w    $3FF0,$0000
    dc.w    0,0                         ; terminator
    even

    section    main,code
