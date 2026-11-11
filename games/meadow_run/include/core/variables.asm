;==============================================================================
; MEADOW RUN - GLOBAL VARIABLES
; variables.asm  -  Game variable block layout (RS layout, reached through a5)
;==============================================================================
;
; Engine fields first, then the horizontal scroller's, then the game's own,
; all on one rsreset chain (ENGINE_CONTRACT.md section 2). const.asm must be
; included first: hscroll_variables.i reads HS_MAP_ROWS and HS_MAP_COLS.
;==============================================================================

    include    "engine_variables.i"
    include    "hscroll_variables.i"   ; HsCameraX, HsMapBack, ... (hscroll.asm)

; Needed by engine/graphics/bob_mirror.asm (PlayerInitFlippedSprites)
PlayerGfxPtr:         rs.l    1               ; right-facing graphic
PlayerMskPtr:         rs.l    1               ; right-facing mask
PlayerWhitePtr:       rs.l    1               ; (unused here: no white flash)

; Mia
PlrX:                 rs.w    1               ; world X of her 16-pixel body box
PlrY16:               rs.w    1               ; world Y of her sprite's top, x16
PlrVY:                rs.w    1               ; vertical speed, 1/16 pixel per frame
PlrOnGround:          rs.w    1               ; 1 while standing on something solid
PlrFacing:            rs.w    1               ; 0 = right, 1 = left
PlrAnim:              rs.w    1               ; frame counter for the animation
PlrRunning:           rs.w    1               ; 1 while she walks left or right
PlrDrawn:             rs.w    1               ; 1 if a BOB is on screen to erase
PlrDrawX:             rs.w    1               ; world X the BOB was drawn at
PlrDrawY:             rs.w    1               ; world Y the BOB was drawn at
PlrDeadTimer:         rs.w    1               ; frames left in the death pause
JumpPrev:             rs.w    1               ; jump input last frame (for the edge)

; The level
LevelDefPtr:          rs.l    1               ; the LevelDef being played
LevelReady:           rs.w    1               ; 0 until the level has been drawn
GoalTimer:            rs.w    1               ; frames left in the level-complete pause
TimeUp:               rs.w    1               ; 1: the death pause ends in a restart
TimeLeft:             rs.w    1               ; seconds left on the countdown
TimeTicks:            rs.w    1               ; logic ticks left in this second
DuckCount:            rs.w    1               ; ducklings collected this run
DuckTick:             rs.w    1               ; frames to the ducklings' next animation step
BestDucks:            rs.w    1               ; most ducklings brought to the signpost
NewBest:              rs.w    1               ; 1: this run set BestDucks (GoalFlash)
SplashTimer:          rs.w    1               ; frames left of the boot splash (splash.asm)
HudDirty:             rs.w    1               ; 1: the HUD digits need redrawing
LevelMid:             rs.w    HS_MAP_ROWS*HS_MAP_COLS ; platform layer, live (ducklings disappear)
LevelGame:            rs.b    HS_MAP_ROWS*HS_MAP_COLS ; collision map, live

    IFD MEADOW_AUTOPLAY
AutoplayStep:         rs.w    1               ; test builds: entry of AutoplayScript
AutoplayFrame:        rs.w    1               ; test builds: frames into that entry
    ENDC

Variables_Sizeof:     rs.w    0               ; total size of the Variables block
