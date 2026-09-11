#!/usr/bin/env python3
"""
draw_players.py
---------------
Procedural Price & Cole player sprites for Alien Containment.

Generates:
  1. assets/graphics/sprites/sprites.pal        - new colours 16-31 palette
     (effect-critical slots preserved in kind: black/white/greys for smoke &
     clouds, browns for dirt, blues for stars, amber for the yellow star).
  2. assets/graphics/sprites/player_hwsprites.bin + .zx0 - all 96 hardware
     sprite frames (48 per character; Cole base 0 [was Molly], Price base 48
     [was Millie]) in the engine layout: 416 bytes/frame = 4 x 104-byte
     channels in file order SPR2(left,bits0-1), SPR4(right,bits0-1),
     SPR3(left,bits2-3), SPR5(right,bits2-3); each channel = 4-byte header
     (rewritten at runtime by SpriteCoord) + 24 rows x 2 data words +
     4-byte terminator.  Pixel value v (1-15) displays SpritePal[v].
  3. Frozen-partner frames patched into actor_sprites.bin tiles 29-34
     (29/30 Cole frozen R/L, 31/32 Price frozen R/L, 33 Cole ladder freeze,
     34 Price ladder freeze) - figures inside a cyan stasis bracket, the AC
     re-read of M&M's ice block.  Tile format: 5-bpl row-interleaved,
     colour = index+16, 0 transparent.

Frame map per character (const.asm):
  0-3 idle R | 4-11 walk R | 16-19 ladder (19 = ladder idle) | 28-31 fall |
  32-35 idle L | 36-43 walk L | 12-15, 20-27, 44-47 unused (zero-filled).
Left-facing frames are horizontal mirrors.

After running:
  tools\\zx0.exe -f assets\\graphics\\sprites\\player_hwsprites.bin assets\\graphics\\sprites\\player_hwsprites.zx0
  python tools/zx0_verify.py assets\\graphics\\sprites\\player_hwsprites.zx0 assets\\graphics\\sprites\\player_hwsprites.bin
  ./build.ps1

Originals kept once as *.mm.  Deterministic output.
"""

import shutil
from pathlib import Path

from PIL import Image

SPR = Path('assets/graphics/sprites')
W, H = 24, 24            # visible cell (canvas is 32 wide; cols 24-31 empty)

# sprites.pal colours 16-31 ($0RGB).  Slots 1,3,6,7,8,9,10,11 keep their M&M
# role (effects reference them); 2,4,5 shift within-family; 12-15 (unused by
# effects) become Cole's olive kit and Price's dark steel.
PAL = [0x000,
       0x000,   # 1  black outline (effects)
       0xCDE,   # 2  Price suit shell   (clouds: cool white)
       0xFFF,   # 3  white              (effects)
       0x89A,   # 4  Price suit shade   (clouds: cool grey)
       0x0AC,   # 5  cyan visor / lamps (was 06A blue)
       0xFC4,   # 6  amber              (yellow star + Cole visor)
       0x643,   # 7  brown              (dirt)
       0xA60,   # 8  dark amber-brown   (dirt + Cole visor shade)
       0x888,   # 9  grey               (smoke + joints/boots)
       0x9DF,   # 10 ice blue           (star + stasis brackets)
       0x39F,   # 11 blue               (star)
       0x663,   # 12 Cole olive mid
       0x442,   # 13 Cole olive dark
       0x885,   # 14 Cole khaki light
       0x345]   # 15 Price dark steel (limbs, boots)
BLK, SHELL, WHT, SHADE, CYAN, AMBER = 1, 2, 3, 4, 5, 6
BRN, BRN2, GRY, ICE, BLU, OLV, OLVD, KHK, DKS = 7, 8, 9, 10, 11, 12, 13, 14, 15


class Cel:
    """24x24 index buffer with draw helpers.  (0,0) top-left, y=23 ground."""

    def __init__(self):
        self.g = [[0] * W for _ in range(H)]

    def px(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.g[y][x] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.px(x, y, c)

    def hline(self, x0, x1, y, c):
        self.rect(x0, y, x1, y, c)

    def vline(self, x, y0, y1, c):
        self.rect(x, y0, x, y1, c)

    def mirror(self):
        out = Cel()
        for y in range(H):
            for x in range(W):
                out.g[y][W - 1 - x] = self.g[y][x]
        return out


# ---------------------------------------------------------------------------
# Figure builders.  Poses parameterised by:
#   bob   - body raise in px (0/1)
#   la/lb - (foot_dx, lift) for the two legs, relative to their hip
#   aa/ab - arm swing dx for back arm / front arm
# All right-facing; visor on the +x side.
# ---------------------------------------------------------------------------

def leg(c, hipx, hipy, foot_dx, lift, col, boot):
    footy = 22 - lift
    steps = footy - hipy
    for i in range(steps + 1):
        x = hipx + (foot_dx * i) // max(1, steps)
        c.px(x, hipy + i, col)
        c.px(x + 1, hipy + i, col)
    fx = hipx + foot_dx
    c.px(fx, footy + 1, boot)
    c.px(fx + 1, footy + 1, boot)
    c.px(fx + 2, footy + 1, boot)


def arm(c, sx, sy, dx, col, hand):
    for i in range(5):
        x = sx + (dx * i) // 4
        c.px(x, sy + i, col)
    c.px(sx + dx, sy + 5, hand)


def knock(c, pts):
    """Clear pixels (corner rounding)."""
    for x, y in pts:
        if 0 <= x < W and 0 <= y < H:
            c.g[y][x] = 0


def price(bob=0, la=(0, 0), lb=(0, 0), aa=0, ab=0, spec=0):
    """Dr. Price: white EVA suit, cyan visor, backpack on the off side."""
    c = Cel()
    t = -bob
    # backpack (behind: left side when facing right)
    c.rect(6, 11 + t, 7, 16 + t, SHADE)
    c.vline(6, 11 + t, 16 + t, DKS)
    c.px(7, 12 + t, CYAN)
    # legs first (torso overlaps hips)
    leg(c, 10, 16 + t, la[0], la[1], DKS, GRY)
    leg(c, 13, 16 + t, lb[0], lb[1], DKS, GRY)
    # torso: shoulders wider than waist
    c.rect(8, 11 + t, 15, 13 + t, SHELL)
    c.rect(9, 14 + t, 15, 16 + t, SHELL)
    c.vline(15, 11 + t, 16 + t, SHADE)
    c.hline(9, 14, 16 + t, SHADE)
    c.hline(9, 14, 17 + t, DKS)              # belt
    c.px(14, 12 + t, CYAN)                   # chest lamp
    knock(c, [(8, 11 + t)])
    # arms (back arm over pack, front arm over torso)
    arm(c, 9, 12 + t, aa, SHADE, GRY)
    arm(c, 14, 12 + t, ab, SHELL, GRY)
    # collar seal
    c.hline(10, 14, 10 + t, DKS)
    # helmet: rounded dome
    c.rect(8, 2 + t, 16, 9 + t, SHELL)
    c.hline(10, 14, 1 + t, SHELL)
    knock(c, [(8, 2 + t), (16, 2 + t), (9, 1 + t), (15, 1 + t),
              (8, 9 + t), (16, 9 + t)])
    c.hline(9, 15, 9 + t, SHADE)
    c.vline(8, 4 + t, 7 + t, WHT)            # rim light
    c.hline(10, 13, 2 + t, WHT)              # crown light
    c.rect(12, 4 + t, 16, 7 + t, CYAN)       # visor wraps the leading edge
    c.px(16, 4 + t, SHELL)
    c.px(13 + spec, 5 + t, WHT)              # visor glint (animates)
    c.px(15, 7 + t, DKS)
    return c


def cole(bob=0, la=(0, 0), lb=(0, 0), aa=0, ab=0, spec=0):
    """Sgt. Cole: olive combat armour, amber visor slit, bulkier build."""
    c = Cel()
    t = -bob
    # legs
    leg(c, 9, 16 + t, la[0], la[1], OLVD, BLK)
    leg(c, 13, 16 + t, lb[0], lb[1], OLVD, BLK)
    # torso: broad pauldrons tapering to an armoured waist
    c.rect(7, 11 + t, 16, 13 + t, OLV)
    c.rect(8, 14 + t, 15, 16 + t, OLV)
    c.hline(7, 16, 11 + t, KHK)              # pauldron ridge
    c.vline(16, 11 + t, 13 + t, OLVD)
    c.vline(15, 14 + t, 16 + t, OLVD)
    c.hline(8, 15, 16 + t, OLVD)
    c.rect(10, 12 + t, 13, 15 + t, OLVD)     # tactical plate
    c.px(11, 13 + t, AMBER)                  # status LED
    knock(c, [(7, 13 + t), (16, 13 + t)])
    # arms
    arm(c, 8, 12 + t, aa, OLVD, OLVD)
    arm(c, 15, 12 + t, ab, OLV, OLVD)
    # neck guard
    c.hline(10, 14, 10 + t, OLVD)
    # helmet: squarer, brow ridge, amber slit
    c.rect(8, 2 + t, 16, 9 + t, OLV)
    knock(c, [(8, 2 + t), (16, 2 + t)])
    c.hline(9, 15, 2 + t, KHK)               # crown light
    c.hline(9, 16, 4 + t, KHK)               # brow ridge
    c.rect(12, 5 + t, 16, 6 + t, AMBER)      # visor slit wraps forward
    c.px(16, 6 + t, BRN2)
    c.px(13 + spec, 5 + t, WHT)              # slit glint
    c.rect(11, 8 + t, 15, 9 + t, OLVD)       # respirator
    c.hline(8, 16, 9 + t, OLVD)
    return c


def back_view(who, armA_up, bob):
    """Ladder climb: seen from behind, hands up on the rails."""
    c = Cel()
    t = -bob
    if who == 'price':
        limb = DKS
        c.rect(8, 2 + t, 16, 9 + t, SHELL)   # helmet back (no visor)
        knock(c, [(8, 2 + t), (16, 2 + t), (8, 9 + t), (16, 9 + t)])
        c.vline(8, 4 + t, 7 + t, WHT)
        c.rect(8, 11 + t, 15, 16 + t, SHADE)  # backpack dominates the back
        c.vline(8, 11 + t, 16 + t, DKS)
        c.vline(15, 11 + t, 16 + t, DKS)
        c.hline(9, 14, 13 + t, DKS)           # pack strap detail
        c.px(11, 12 + t, CYAN)
        c.hline(10, 13, 10 + t, DKS)          # collar
    else:
        limb = OLVD
        c.rect(8, 2 + t, 16, 9 + t, OLV)
        knock(c, [(8, 2 + t), (16, 2 + t)])
        c.hline(9, 15, 2 + t, KHK)
        c.rect(8, 11 + t, 15, 16 + t, OLV)
        c.hline(8, 15, 11 + t, KHK)
        c.rect(10, 12 + t, 13, 16 + t, OLVD)  # back plate
        c.hline(10, 13, 10 + t, OLVD)         # neck guard
    # arms: reach up to the rails, alternating (connected at the shoulders)
    ya = 3 if armA_up else 6
    yb = 6 if armA_up else 3
    c.rect(6, ya + t, 7, 11 + t, limb)
    c.px(6, ya - 1 + t, GRY)
    c.rect(16, yb + t, 17, 11 + t, limb)
    c.px(17, yb - 1 + t, GRY)
    # legs on the rungs, alternating
    lift_a = 1 if armA_up else 3
    lift_b = 3 if armA_up else 1
    c.rect(9, 18 + t, 10, 22 - lift_a, limb)
    c.rect(13, 18 + t, 14, 22 - lift_b, limb)
    c.hline(9, 10, 23 - lift_a, GRY if who == 'price' else BLK)
    c.hline(13, 14, 23 - lift_b, GRY if who == 'price' else BLK)
    return c


def fall_pose(who, f):
    """Falling: front view, arms thrown up, legs tucked; 4-frame flail."""
    sway = (0, 1, 0, -1)[f]
    tuck = (1, 2, 1, 2)[f]
    c = Cel()
    if who == 'price':
        body, shade, limb, visor = SHELL, SHADE, DKS, CYAN
    else:
        body, shade, limb, visor = OLV, OLVD, OLVD, AMBER
    # legs bent under
    c.rect(9 + sway, 17, 10 + sway, 21 - tuck, limb)
    c.rect(13 + sway, 17, 14 + sway, 22 - tuck, limb)
    c.hline(9 + sway, 10 + sway, 22 - tuck, GRY)
    c.hline(13 + sway, 14 + sway, 23 - tuck, GRY)
    # torso
    c.rect(8, 10, 15, 17, body)
    c.vline(15, 10, 17, shade)
    if who == 'cole':
        c.hline(8, 15, 10, KHK)
    # arms up and out
    for i in range(5):
        c.px(6 - i // 2 + sway, 10 - i, limb)
        c.px(17 + i // 2 + sway, 10 - i, limb)
    c.px(5 + sway, 5, GRY)
    c.px(18 + sway, 5, GRY)
    # helmet, visor facing out
    c.rect(8, 2, 16, 9, body)
    c.rect(10, 4, 14, 7, visor)
    c.px(11 + (f & 1), 5, WHT)
    if who == 'cole':
        c.hline(8, 16, 2, KHK)
    return c


# ---------------------------------------------------------------------------
# Animation tables
# ---------------------------------------------------------------------------

# 8-frame walk: legs half-cycle apart; arms counter-swing.
WALK_DX =   [3, 2, 0, -2, -3, -2, 0, 2]
WALK_LIFT = [0, 0, 1, 1, 0, 0, 2, 1]
WALK_BOB =  [0, 0, 1, 1, 0, 0, 1, 1]


def build_frames(figure):
    """48 right-facing/mirrored cels per character, indexed 0-47."""
    cels = [Cel() for _ in range(48)]
    # idle 0-3: at ease, visor glint wanders, tiny breath bob
    for f in range(4):
        cels[f] = figure(bob=(0, 0, 1, 0)[f], la=(0, 0), lb=(0, 0),
                         aa=0, ab=0, spec=(0, 1, 2, 1)[f])
    # walk 4-11
    for f in range(8):
        pa, pb = f, (f + 4) % 8
        cels[4 + f] = figure(bob=WALK_BOB[f],
                             la=(WALK_DX[pa], WALK_LIFT[pa]),
                             lb=(WALK_DX[pb], WALK_LIFT[pb]),
                             aa=WALK_DX[pb] // 2, ab=WALK_DX[pa] // 2,
                             spec=0)
    return cels


def assemble(who, figure):
    cels = build_frames(figure)
    frames = [Cel() for _ in range(48)]
    for f in range(12):
        frames[f] = cels[f]                       # idle + walk right
    for f in range(4):                            # ladder 16-19
        frames[16 + f] = back_view(who, armA_up=(f in (0, 1)),
                                   bob=(0, 1, 0, 1)[f])
    for f in range(4):                            # fall 28-31
        frames[28 + f] = fall_pose(who, f)
    for f in range(12):                           # left-facing mirrors
        frames[32 + f] = cels[f].mirror()
    return frames


# ---------------------------------------------------------------------------
# Encoders
# ---------------------------------------------------------------------------

def encode_hw_frame(cel):
    """Cel -> 416-byte hw frame: SPR2, SPR4, SPR3, SPR5 channel blocks."""
    out = bytearray()
    for shift in (0, 2):                          # even pair bits, odd pair bits
        for xbase in (0, 16):
            out += b'\x00\x00\x00\x00'            # header (runtime-written)
            for y in range(H):
                w0 = w1 = 0
                for x in range(16):
                    gx = xbase + x
                    v = (cel.g[y][gx] >> shift) & 3 if gx < W else 0
                    if v & 1:
                        w0 |= 0x8000 >> x
                    if v & 2:
                        w1 |= 0x8000 >> x
                out += w0.to_bytes(2, 'big') + w1.to_bytes(2, 'big')
            out += b'\x00\x00\x00\x00'            # terminator
    # file order is SPR2(left,e), SPR4(right,e), SPR3(left,o), SPR5(right,o):
    # the loop above yields exactly that order (shift-major, then half).
    assert len(out) == 416
    return bytes(out)


def encode_tile(cel):
    """Cel -> 480-byte 5-bpl interleaved tile; colour = index+16."""
    out = bytearray()
    for y in range(H):
        for p in range(5):
            w = 0
            for x in range(W):
                v = cel.g[y][x]
                if v and ((v + 16) >> p) & 1:
                    w |= 1 << (31 - x)
            out += w.to_bytes(4, 'big')
    assert len(out) == 480
    return bytes(out)


def stasis(cel):
    """Overlay the hold-position stasis brackets on a copy of a cel."""
    c = Cel()
    c.g = [row[:] for row in cel.g]
    for x0, y0, dx, dy in ((1, 0, 1, 1), (22, 0, -1, 1),
                           (1, 23, 1, -1), (22, 23, -1, -1)):
        for i in range(4):
            c.px(x0 + i * dx, y0, ICE)
            c.px(x0, y0 + i * dy, ICE)
    c.px(11, 0, ICE)                              # field emitter blips
    c.px(12, 23, ICE)
    return c


def backup(path):
    bak = path.with_suffix(path.suffix + '.mm')
    if path.exists() and not bak.exists():
        shutil.copyfile(path, bak)


def main():
    # 1. palette
    palfile = SPR / 'sprites.pal'
    backup(palfile)
    old = palfile.read_bytes()
    palfile.write_bytes(b''.join(w.to_bytes(2, 'big') for w in PAL) + old[32:])
    print(f'  {palfile}: Price/Cole palette written (effect slots preserved)')

    # 2. hardware sprites: Cole = base 0 (Molly slot), Price = base 48 (Millie)
    cole_frames = assemble('cole', cole)
    price_frames = assemble('price', price)
    hw = bytearray()
    for frames in (cole_frames, price_frames):
        for f in range(48):
            hw += encode_hw_frame(frames[f])
    hwfile = SPR / 'player_hwsprites.bin'
    backup(hwfile)
    hwfile.write_bytes(bytes(hw))
    print(f'  {hwfile}: {len(hw)} bytes (96 frames)')

    # 3. frozen frames into actor_sprites.bin (if present)
    asfile = SPR / 'actor_sprites.bin'
    if asfile.exists():
        backup(asfile)
        data = bytearray(asfile.read_bytes())
        patches = {
            29: stasis(cole_frames[0]),               # Cole frozen right
            30: stasis(cole_frames[32]),              # Cole frozen left
            31: stasis(price_frames[0]),              # Price frozen right
            32: stasis(price_frames[32]),             # Price frozen left
            33: stasis(back_view('cole', True, 0)),   # Cole ladder freeze
            34: stasis(back_view('price', True, 0)),  # Price ladder freeze
        }
        for t, cel in patches.items():
            data[t * 480:(t + 1) * 480] = encode_tile(cel)
        asfile.write_bytes(bytes(data))
        print(f'  {asfile}: frozen frames 29-34 patched (stasis brackets)')

    # 4. preview contact sheet (key frames, both characters)
    keys = [0, 1, 2, 3, 4, 6, 8, 10, 16, 17, 18, 19, 28, 29, 32, 36]
    cols = [((w >> 8 & 0xF) * 17, (w >> 4 & 0xF) * 17, (w & 0xF) * 17)
            for w in PAL]
    sheet = Image.new('RGB', (len(keys) * 26, 58), (35, 35, 42))
    for row, frames in enumerate((price_frames, cole_frames)):
        for i, f in enumerate(keys):
            for y in range(H):
                for x in range(W):
                    v = frames[f].g[y][x]
                    if v:
                        sheet.putpixel((i * 26 + x + 1, row * 28 + y + 2),
                                       cols[v])
    sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST) \
         .save(SPR / 'players_preview.png')
    print(f'  {SPR / "players_preview.png"}: frames {keys} (Price top, Cole bottom)')


if __name__ == '__main__':
    main()
