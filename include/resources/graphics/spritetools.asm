
;==============================================================================
; AMIGA GAME ENGINE
; spritetools.asm  -  Hardware Sprite Display Utilities
;==============================================================================
;
; Hardware Sprite Architecture:
;   The player character is rendered as a Blitter Object (BOB) into the playfield
;   bitplanes. Hardware sprites are reserved for the HUD overlay badges and
;   dynamic underwater air bubbles (see hud_sprites.asm).
;
; Channel allocation:
;   SPR0    Player Lives Badge (solo, 16px wide, 9 scanlines, COLOR17-19)
;   SPR1    Free (NullSprite)
;   SPR2    Oxygen Kit Inventory Bottle (solo, 16px wide, 13 scanlines, COLOR21-23)
;   SPR3    Friends Remaining Badge (solo, 16px wide, 9 scanlines, COLOR21-23)
;   SPR4    Oxygen / Lung Fluid Gauge (solo, 16px wide, 28 scanlines, COLOR25-27)
;   SPR5    Free (NullSprite)
;   SPR6    Dynamic In-World Air Bubble (solo, 16x8 pixels, COLOR29-31)
;   SPR7    Free (NullSprite)
;
;==============================================================================

;==============================================================================
; ClearSprites  -  Point all 8 hardware sprite channels at NullSprite
;
; Writes the address of NullSprite (two zero longwords = a terminated, empty
; sprite structure) into all eight SPRxPTH/L copper list entries in cpSprites.
; This hides all hardware sprites from the display.
;
; Called by GameCopperInit at startup and whenever no sprite should be shown.
;
; NullSprite is a dc.l 0,0 in bss_c (Chip RAM) - Agnus needs to fetch it,
; so it must be in Chip RAM.  The terminator pattern (two zero words) tells
; Agnus to stop fetching sprite data immediately on the first line.
;==============================================================================

ClearSprites:
    lea        cpSprites,a0
    move.l     #NullSprite,d0
    moveq      #8-1,d7
.loop
    move.w     d0,6(a0)
    swap       d0
    move.w     d0,2(a0)
    swap       d0
    add.l      #8,a0
    dbra       d7,.loop
    rts

