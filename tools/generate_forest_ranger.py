#!/usr/bin/env python3
"""
tools/generate_forest_ranger.py
-------------------------------
Generates the authentic Amiga OCS 16-color 24-frame player master spritesheet
for Briar, the Forest Ranger & Woodland Rescuer.

Format:
  Dimensions: 128x144 RGBA PNG (6 rows x 4 columns of 32x24 cells)
  Active art: 24x24 pixels centered/aligned with 8px transparent padding (x=0..23 active, x=24..31 empty)
  Palette: Strict 16-color Commodore Amiga OCS playfield palette
"""

import sys
import os
from pathlib import Path
from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# 16-color authentic Amiga OCS palette (matches export_level.py & PAL_8BIT)
PALETTE_OCS = [
    (0, 0, 0),        # 0: Transparent ($0000)
    (1, 11, 14),      # 1: 0x1BE Vibrant Cyan (eye glint)
    (3, 3, 2),        # 2: 0x332 Dark outline
    (15, 15, 15),     # 3: 0xFFF White highlight / stag horn tip
    (2, 7, 4),        # 4: 0x274 Forest Green (tunic & hood)
    (1, 9, 3),        # 5: 0x193 Grass Green (hood highlight & foliage trim)
    (15, 9, 1),       # 6: 0xF91 Vibrant Orange (braid highlight sheen)
    (2, 5, 12),       # 7: 0x25C Deep Blue
    (15, 12, 2),      # 8: 0xFC2 Vibrant Gold (brooch clasp & belt buckle)
    (13, 10, 6),      # 9: 0xDA6 Light Wood / Antler (elderwood stave shaft)
    (11, 7, 4),       # 10: 0xB74 Stone / Earth / Leather (boots & utility belt)
    (8, 1, 3),        # 11: 0x813 Rich Maroon (braid shadow & boot trim)
    (13, 1, 2),       # 12: 0xD12 Vibrant Crimson (auburn hair / braid)
    (8, 9, 11),       # 13: 0x89B Slate Grey (quiver strap & leggings)
    (1, 7, 7),        # 14: 0x177 Vibrant Teal
    (12, 10, 8),      # 15: 0xCA8 Peach Skin
]

PAL_8BIT = [(r * 17, g * 17, b * 17) for r, g, b in PALETTE_OCS]

# ASCII character to RGBA mapping
COLOR_MAP = {
    '.': (0, 0, 0, 0),
    'X': (*PAL_8BIT[2], 255),   # Dark Outline 0x332
    'C': (*PAL_8BIT[1], 255),   # Cyan Eye Glint 0x1BE
    'H': (*PAL_8BIT[3], 255),   # White Stag Horn Tip 0xFFF
    'G': (*PAL_8BIT[4], 255),   # Forest Green Hood/Tunic 0x274
    'L': (*PAL_8BIT[5], 255),   # Grass Green Fold/Trim 0x193
    'O': (*PAL_8BIT[6], 255),   # Amber Braid Highlight 0xF91
    'Y': (*PAL_8BIT[8], 255),   # Gold Brooch/Buckle 0xFC2
    'W': (*PAL_8BIT[9], 255),   # Elderwood Stave Shaft 0xDA6
    'B': (*PAL_8BIT[10], 255),  # Leather Boots/Belt 0xB74
    'M': (*PAL_8BIT[11], 255),  # Deep Maroon Shadow 0x813
    'R': (*PAL_8BIT[12], 255),  # Crimson Auburn Braid 0xD12
    'S': (*PAL_8BIT[13], 255),  # Slate Strap/Shadow 0x89B
    'P': (*PAL_8BIT[15], 255),  # Peach Skin 0xCA8
}

# ==============================================================================
# 24 SPRITE FRAMES (6 ROWS x 4 FRAMES)
# ==============================================================================

# ROW 0: IDLE (Right) - 4 Frames
# Briar standing alert in forest grove, elderwood stag crook in hand, cowl draped
ROW_0_IDLE = [
    # Frame 0: Natural idle stance, alert eyes, stave grounded
    [
        "..............XX........",
        "...........XXXGGX.......",
        "..........XGGLLGGX......",
        ".....XHXXXGLLLLLGX......",
        "...XHWXXXGGLLGGGXX......",
        "..XHWX.XGGLXXGGXXX......",
        "..XHWX.XXPXBBBPX........",
        "...XWWXXPXXPPPPPX.......",
        "....XWXBXCPXPPPPXX......",
        "....XXBXXPXXXXYYXX......",
        ".....XBXXXXXXGXX........",
        ".....XRRRXBGGGGX........",
        ".....XRROXGGLGGGX.......",
        ".....XRMXPXGGGGBX.......",
        ".....XRMXXPXXYYBX.......",
        "......XMMXXBXXXXX.......",
        ".......XXBBBBBBBXX......",
        "........XBBXXBBX........",
        "........XMMXXMMX........",
        "........XBBXXBBX........",
        "........XXXXXXXX........",
        "........XBBXXBBX........",
        "........XMMXXMMX........",
        "........XXXXXXX.........",
    ],
    # Frame 1: Slight breath in, eye sparkle, cloak trim rustles
    [
        ".............XX.........",
        "...........XXXGGX.......",
        "..........XGGLLGGX......",
        "..XXXXHX.XGLLLLLGX......",
        ".XHWX...XGGLLGGGXX......",
        ".XHWX..XXGGLXXGGXXX.....",
        "..XWWX.XXPXBBBPX........",
        "...XWXXXPXXPPPPPX.......",
        "...XXXXBXCPXPPPPXX......",
        ".....XBXXPXXXXYYXX......",
        ".....XBXXXXXXGXX........",
        ".....XRRRXBGGGGX........",
        ".....XRROXGGLGGGX.......",
        ".....XRMXPXGGGGBX.......",
        ".....XRMXXPXXYYBX.......",
        "......XMMXXBXXXXX.......",
        ".......XXBBBBBBBXX......",
        "........XBBXXBBX........",
        "........XMMXXMMX........",
        "........XBBXXBBX........",
        "........XXXXXXXX........",
        "........XBBXXBBX........",
        "........XMMXXMMX........",
        "........XXXXXXX.........",
    ],
    # Frame 2: Deep inhale peak, braid sways slightly, stag crook glints
    [
        "........................",
        "..............XX........",
        "...........XXXGGX.......",
        "..........XGGLLGGX......",
        ".....XHXXXGLLLLLGX......",
        "...XHWXXXGGLLGGGXX......",
        "..XHWX.XGGLXXGGXXX......",
        "..XHWX.XXPXBBBPX........",
        "...XWWXXPXXPPPPPX.......",
        "....XWXBXCPXPPPPXX......",
        "....XXBXXPXXXXYYXX......",
        ".....XRRRXXXXXGXX.......",
        ".....XRROXXBGGGGX.......",
        ".....XRMXPXGGLGGX.......",
        ".....XRMXXPXGGGGBX......",
        "......XMMXXPXXYYBX......",
        ".......XXBBBBBBBXX......",
        "........XBBXXBBX........",
        "........XMMXXMMX........",
        "........XBBXXBBX........",
        "........XXXXXXXX........",
        "........XBBXXBBX........",
        "........XMMXXMMX........",
        "........XXXXXXX.........",
    ],
    # Frame 3: Exhale settling back to rest pose
    [
        "........................",
        "........................",
        "..............XX........",
        "...........XXXGGX.......",
        "..........XGGLLGGX......",
        ".....XHXXXGLLLLLGX......",
        "...XHWXXXGGLLGGGXX......",
        "..XHWX.XGGLXXGGXXX......",
        "..XHWX.XXPXBBBPX........",
        "...XWWXXPXXPPPPPX.......",
        "....XWXBXCPXPPPPXX......",
        "....XXBXXPXXXXYYXX......",
        ".....XBXXXXXXGXX........",
        ".....XRRRXBGGGGX........",
        ".....XRROXGGLGGGX.......",
        ".....XRMXPXGGGGBX.......",
        ".....XRMXXPXXYYBX.......",
        "......XMMXXBXXXXXX......",
        ".......XXBBBBBBBXX......",
        "........XBBXXBBX........",
        "........XMMXXMMX........",
        "........XBBXXBBX........",
        "........XXXXXXXX........",
        "........XXXXXXX.........",
    ],
]

# ROW 1: WALK / RUN (Right) - 4 Frames
# Nimble woodland sprint, green cloak trailing, elderwood crook swinging forward
ROW_1_WALK = [
    # Frame 4: Right foot contact forward, left leg trailing, stave driving
    [
        "..............XX........",
        "...........XXXGGX.......",
        "..........XGGLLGGX......",
        ".....XHXXXGLLLLLGX......",
        "...XHWXXXGGLLGGGXX......",
        "..XHWX.XGGLXXGGXXX......",
        "..XWWXX.XPXBBBPX........",
        "...XWXXXPXXPPPPPX.......",
        "...XXXXBXCPXPPPPXXXX....",
        ".....XBXXPXXXXYYXBBX....",
        ".....XBXXXXXXGXXBBX.....",
        ".....XRRRXBGGGGXXXX.....",
        ".....XRROXGGLGGX........",
        ".....XRMXPXGGGBX........",
        "......XMMXXBBXXXX.......",
        ".......XXBBBBBBX........",
        ".......XBBXXBBBX........",
        ".......XMMX.XMMX........",
        ".......XBBX.XBBX........",
        ".......XXXX.XXXX........",
        "......XMMX...XMMX.......",
        "......XBBX...XBBX.......",
        "......XXXX...XXXX.......",
        "........................",
    ],
    # Frame 5: Passing 1 - Right leg planted, left knee driving forward, body rises
    [
        "..............XX........",
        "...........XXXGGX.......",
        "..........XGGLLGGX......",
        "..XXXXHX..GLLLLLGX......",
        ".XHWX..XXGGLLGGGXX......",
        ".XHWX..XGGLXXGGXXX......",
        "..XWWX.XXPXBBBPX........",
        "...XWX.XPXXPPPPPX.......",
        "...XX.XXBXCPXPPPPXX.....",
        ".....XXBXXPXXXXYYXX.....",
        ".....XBXXXXXXGXX........",
        ".....XRRRXBGGGGX........",
        ".....XRROXGGLGGGX.......",
        ".....XRMXPXGGGGBX.......",
        ".....XRMXXPXGYYBX.......",
        "......XMMXXBXXXXX.......",
        ".......XXBBBBBBBXX......",
        "........XBBXXBBX........",
        "........XMMXXMMX........",
        "........XBBXXBBX........",
        "........XXXX.XXXX.......",
        "........XBBX.XBBX.......",
        "........XXXX.XXXX.......",
        "........................",
    ],
    # Frame 6: Left foot contact forward, right leg trailing push-off
    [
        "..............XX........",
        "...........XXXGGX.......",
        "..........XGGLLGGX......",
        ".....XHXXXGLLLLLGX......",
        "...XHWXXXGGLLGGGXX......",
        "..XHWX.XGGLXXGGXXX......",
        "..XWWX.XXPXBBBPX........",
        "...XWX.XPXXPPPPPX.......",
        "....XXXXBXCPXPPPPXX.....",
        ".....XXBXXPXXXXYYXX.....",
        ".....XBXXXXXXGXX........",
        ".....XRRRXBGGGGX........",
        ".....XRROXGGLGGGX.......",
        ".....XRMXPXGGGGBXX......",
        ".....XRMXXPXGYYBXBX.....",
        "......XMMXXBBXXXXXX.....",
        ".......XXBBBBBBBXX......",
        ".......XBBX..XBBX.......",
        ".......XMMX..XMMX.......",
        ".......XBBX..XBBX.......",
        ".......XXXX..XXXX.......",
        "......XMMX....XMMX......",
        "......XBBX....XBBX......",
        "......XXXX....XXXX......",
    ],
    # Frame 7: Passing 2 - Left leg planted, right leg swings through
    [
        "..............XX........",
        "...........XXXGGX.......",
        ".........XXGGLLGGX......",
        ".....XHXXXGLLLLLGX......",
        "...XHWXXXGGLLGGGXX......",
        "..XHWX.XGGLXXGGXXX......",
        "..XWWXX.XPXBBBPX........",
        "...XWXXXPXXPPPPPX.......",
        "....XXBXXCPXPPPPXX......",
        ".....XBXXPXXXXYYXX......",
        ".....XBXXXXXXGXXXX......",
        ".....XRRRXBGGGGXXBX.....",
        ".....XRROXGGLGGXXXX.....",
        ".....XRMXPXGGGBX........",
        "......XMMXXBBXXXX.......",
        ".......XXBBBBBBX........",
        ".......XBBXXBBBX........",
        ".......XMMX.XMMX........",
        ".......XBBX.XBBX........",
        ".......XXXX.XXXX........",
        "........XMMX.XMMX.......",
        "........XBBX.XBBX.......",
        "........XXXX.XXXX.......",
        "........................",
    ],
]

# ROW 2: ATTACK / HOOK STRIKE (Right) - 4 Frames
# Wind-up, forward lunge thrusting stag crook out to x=23, follow-through, retract
ROW_2_ATTACK = [
    # Frame 8: Windup - Pulling stave back two-handed overhead, leaning back
    [
        "........................",
        ".....X..................",
        "....XHX.................",
        "....XWX.................",
        ".....XWX................",
        ".....XWX...XX...........",
        ".....XWX.XXXGGX.........",
        ".....XWXXGGLLGGX........",
        ".XHX.XXWXGLLLLLGX.......",
        "XHWXXXWXGGLLGGGXX.......",
        "XHWXXWXGGLXXGGXXX.......",
        ".XWWXXWX.XPXBBBPX.......",
        ".XWXBXXWXXPXXPPPPPX.....",
        ".XXBXXXBXCPXPPPPXX......",
        "..XBXXPXXPXXXXYYXX......",
        "..XRRRXXXXXXXGXX........",
        "..XRROXBGGGGXXXX........",
        "..XRMXPXGGLGGXBX........",
        "..XRMXXPXGGGGBXX........",
        "...XMMXXBXXXXXX.........",
        ".....XXBBBBBBX..........",
        "......XBBXXBBX..........",
        "......XMMXXMMX..........",
        "......XXXXXXXX..........",
    ],
    # Frame 9: Mid strike - Lunge forward, swinging stave level
    [
        "........................",
        ".............XXXXX......",
        "............XHHHHHX.....",
        "............XWXXXWX.....",
        ".........XX.XWX..X......",
        "......XXXGGXXWX.........",
        ".....XGGLLGGXWX.........",
        "..XHXGLLLLLGXWX.........",
        "XHWXGGLLGGGXXWX.........",
        "XHWXGGLXXGGXXXWX........",
        "XWWXXPXBBBPX.XWX........",
        ".XWXXPXXPPPPPXWX........",
        "XXXXCPXPPPPXXXWX........",
        "XBXXXPXXXXYYXXWX........",
        "XBXXXXXXXGXX.XWX........",
        "XRRRXBGGGGX..XWX........",
        "XRROXGGLGGGXCXWX........",
        "XRMXPXGGGGBXXWX.........",
        "XRMXXPXGYYBXXXX.........",
        ".XMMXXBBXXXX............",
        "...XXBBBBBBX............",
        "....XBBXXBBX............",
        "....XMMXXMMX............",
        "....XXXXXXXX............",
    ],
    # Frame 10: Full horizontal strike extension - Stag horn crook reaches x=23!
    [
        "........................",
        "........................",
        "..................XXXXX.",
        ".................XHHHHHX",
        "...........XX....XWXXXWX",
        "........XXXGGX...XWX..X.",
        ".......XGGLLGGX..XWX....",
        "...XHXXGLLLLLGX..XWX....",
        ".XHWXGGLLGGGXX..XWX.....",
        "XHWXGGLXXGGXXX..XWX.....",
        "XWWXXPXBBBPX...XWX......",
        ".XWXXPXXPPPPPX.XWX......",
        ".XXXXCPXPPPPXXXXWX......",
        "..XBXXPXXXXYYXXWX.......",
        "..XBXXXXXXGXX.XWX.......",
        "..XRRRXBGGGGXXXWX.......",
        "..XRROXGGLGGGXCXWX......",
        "..XRMXPXGGGGBXXWX.......",
        "..XRMXXPXGYYBXXX........",
        "...XMMXXBBXXXX..........",
        ".....XXBBBBBBX..........",
        "......XBBXXBBX..........",
        "......XMMXXMMX..........",
        "......XXXXXXXX..........",
    ],
    # Frame 11: Retract & recovery - Hooked crate / enemy recoil recovery
    [
        "........................",
        "........................",
        "........................",
        "........................",
        "..................XXXXX.",
        ".........XX......XHHHHHX",
        "......XXXGGX....XWXXXXWX",
        "...XHXXGGLLGGX..XWX...X.",
        ".XHWXGLLLLLGX..XWX......",
        "XHWXGGLLGGGXX..XWX......",
        "XWWXGGLXXGGXX.XWX.......",
        ".XWXXPXBBBPX..XWX.......",
        "XXXXXPXXPPPPPXWX........",
        "XBXXCPXPPPPXXWX.........",
        "XBXXXPXXXXYYXXWX........",
        "XRRRXXXXXXGXX.XWX.......",
        "XRROXBGGGGX...XWX.......",
        "XRMXPXGGLGGGXCXWX.......",
        "XRMXXPXGGGGBXXXX........",
        ".XMMXXBBXXXX............",
        "...XXBBBBBBX............",
        "....XBBXXBBX............",
        "....XMMXXMMX............",
        "....XXXXXXXX............",
    ],
]

# ROW 3: DEATH / COLLAPSE (Right) - 4 Frames
# Stumble back on fatal blow, buckle to knees, collapse forward onto ground
ROW_3_DEATH = [
    # Frame 12: Stunned stagger back, stave slipping forward
    [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        ".............XX.........",
        "...........XXXGGX.......",
        "..........XGGLLGGX......",
        ".....XHXXXGLLLLLGX......",
        "...XHWXXXGGLLGGGXX......",
        "..XHWX.XGGLXXGGXXX......",
        "..XWWXX.XPXBBBPX........",
        "...XWXXXPXXPPPPPX.......",
        "...XXXXBXCPXPPPPXX......",
        ".....XBXXPXXXXYYXX......",
        ".....XBXXXXXXGXX........",
        ".....XRRRXBGGGGX........",
        ".....XRROXGGLGGGX.......",
        ".....XRMXPXGGGGBX.......",
        "......XMMXXBBXXXX.......",
        ".......XXBBBBBBX........",
        "........XBBXXBBX........",
        "........XMMXXMMX........",
        "........XXXXXXXX........",
    ],
    # Frame 13: Knees buckling, dropping down, hood sliding back
    [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "..............XX........",
        "...........XXXGGX.......",
        "..........XGGLLGGX......",
        ".....XHXXXGLLLLLGX......",
        "...XHWXXXGGLLGGGXX......",
        "..XHWX.XGGLXXGGXXX......",
        "..XWWXX.XPXBBBPX........",
        "...XWXXXPXXPPPPPX.......",
        "...XXXXBXCPXPPPPXX......",
        ".....XBXXPXXXXYYXX......",
        ".....XRRRXXXXGXX........",
        ".....XRROXBGGGGX........",
        ".....XRMXPXGGLGGX.......",
        "......XMMXXBGGGBX.......",
        ".......XXBBBBBBXX.......",
        ".......XBBX..XBBX.......",
        ".......XMMX..XMMX.......",
        ".......XXXX..XXXX.......",
    ],
    # Frame 14: Collapsing forward onto hands and knees
    [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "...............XX..XX...",
        ".............XXGGXXGGX..",
        "...........XXGGLLGGGGX..",
        "........XHXXGLLLLLGXGX..",
        ".....XHWX..XXGGLLGGXXX..",
        "....XHWX..XXPXBBBPX.....",
        "...XWWX.XXXPXXPPPPPX....",
        "..XWX..XXBXCPXPPPPXX....",
        "..XX..XXRRRXXXXXXGXX....",
        "......XRROXBGGGGXXXX....",
        "......XRMXPXGGLGGXBX....",
        "......XRMXXPXGGGGBXX....",
        "....XXXXMMXXBBXXXXXX....",
        "....XBBXXBBBBBBX........",
        "....XMMXXBBXXBBX........",
        "....XXXXXXXXXXXXXXXX....",
    ],
    # Frame 15: Collapsed flat on forest floor, braid and cloak draped peacefully
    [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "......XXXX...XXX........",
        "....XXRRRRXXXGGGGXXXGGX.",
        "...XXXRRXXGGGGLLGGGGXHHX",
        "...XXXRMXBGGGGLLLLXXHHHX",
        "...XXXXMXPXRRBXGGGGXXXX.",
        "...XBXXXPXRRPPBBGGGGX...",
        "....XXXXXXRPPPPBGXGGX...",
        "...XBXMXMXXXPPPBBXXXGX..",
        "...XXXMXMMXXXXXXXXXGX...",
        ".....XXXXXX.....XXX.....",
    ],
]

# ROW 4: LADDER CLIMB (Rear View) - 4 Frames
# Rear-view climb, green cowl mantle, auburn braid down back, ranger pouch
ROW_4_LADDER = [
    # Frame 16: Neutral ladder grasp (both hands on rungs, centered)
    [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "...........XXX..........",
        "..........XGGGLLX.......",
        "........XXGGLLLLLX......",
        ".......XXGGLGGGGXXX.....",
        ".......XGGXCXGXXXX......",
        ".......XXXGGLXXX........",
        ".......XXXRROXXX........",
        ".......XXXRRRXXXX.......",
        ".......XPXXRXXXPX.......",
        "........XPXXXXXPX.......",
        ".......XBXXXXXXX........",
        "......XPXBXXXXBX........",
        "......XPXXBBBBXX........",
        ".......XXXXRRXXPX.......",
        "........XXXXXXBXX.......",
        ".........XXRRXXX........",
        ".........XBXXXX.........",
        "..........XXXBX.........",
        ".............X..........",
    ],
    # Frame 17: Reach left hand up, right foot steps up rung
    [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "..........XXX...........",
        ".........XGGGLLX........",
        "........XGGLLLLLX.......",
        ".......XXGGLGGGGXX......",
        ".......XGXCXGXXXXX......",
        ".......XXXGGLXXXX.......",
        ".......XXXXRROXXX.......",
        ".......XXXXRRRXXX.......",
        ".......XPXXXRXXPX.......",
        "........XPXXXXXPX.......",
        "........XXXXXXXX........",
        "......XXXBXXXXBXX.......",
        "......XPXXBBBBXXPX......",
        "......XXXXXRRXXXX.......",
        "........XXXXXXBX........",
        ".........XXRRXXX........",
        ".........XXXXXX.........",
        ".........XBXXBX.........",
        "..........X..X..........",
    ],
    # Frame 18: Neutral climb hold (cycle midpoint)
    [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "...........XXX..........",
        "..........XGGGLLX.......",
        "........XXGGLLLLLX......",
        ".......XXGGLGGGGXXX.....",
        ".......XGGXCXGXXXX......",
        ".......XXXGGLXXX........",
        ".......XXXRROXXX........",
        ".......XXXRRRXXXX.......",
        ".......XPXXRXXXPX.......",
        "........XPXXXXXPX.......",
        ".......XBXXXXXXX........",
        "......XPXBXXXXBX........",
        "......XPXXBBBBXX........",
        ".......XXXXRRXXPX.......",
        "........XXXXXXBXX.......",
        ".........XXRRXXX........",
        ".........XBXXXX.........",
        "..........XXXBX.........",
        ".............X..........",
    ],
    # Frame 19: Reach right hand up, left foot steps up rung
    [
        "........................",
        "........................",
        "........................",
        "........................",
        "........................",
        "..........XXX...........",
        ".........XLLGGGX........",
        "........XLLLLLGXX.......",
        ".......XXGGGGGLGGXX.....",
        ".......XXXXXGXCXGXX.....",
        "........XXXXLGGXXXX.....",
        "........XXXORRXXXXX.....",
        ".......XXXXRRRXXXXX.....",
        ".......XPXXRXXXXPX......",
        "........XXXXXXPXX.......",
        "........XXXXXXXXBX......",
        "........XBXXXXBXPX......",
        "........XXBBBBXXPX......",
        ".......XPXXRRXXXX.......",
        ".......XXBXXXXXX........",
        "........XXXRRXX.........",
        ".........XXXXBX.........",
        ".........XBXXX..........",
        "..........X.............",
    ],
]

# ROW 5: FALLING / IN-AIR FLIP (Right) - 4 Frames
# Airborne leap & descent, cloak billowing upward, stave ready, tucking for landing
ROW_5_FALLING = [
    # Frame 20: Apex leap / rising flail - Cloak billowing, stave angled
    [
        "..XX....................",
        "..XHHX..................",
        "..XXWHX.................",
        "....XWWX................",
        "......XCXGGGGGGX........",
        "........XXXGGXXX........",
        "........XGGLLGGX........",
        ".......XGXGLLGXGX.......",
        ".......XXGGLGGXGX.......",
        ".......XGGXXXBXXX.......",
        ".......XXBBBBBBXX.......",
        ".......XXPPPPPPXXXXX....",
        "........XPPPPPPXXBBX....",
        "........XXXPPRRXXBBX....",
        "........XXXXXRXXXXXX....",
        "........XRRRRXXXXX......",
        ".....XXXXRRRRXXXX.......",
        ".....XPPXXXRRRXX........",
        ".....XPBXXXXXXXX........",
        "......XXXXRRXXRX........",
        "........XXXXXXXX........",
        "........XXXXXXXX........",
        ".......XBXXXXXXBX.......",
        ".......XXX....XXX.......",
    ],
    # Frame 21: Full descent flail - Wind catching cloak upward
    [
        "........................",
        "........................",
        "..XXX...................",
        "..XHHX..................",
        "...XWHX.......XX........",
        "....XWWX...XXXGGX.......",
        "......XCX.XGGLLGGX......",
        "........XXGLLLLLGX......",
        ".......XXGGLLGGGXX......",
        ".......XGGLXXGGXXX......",
        "......XXXPXBBBPX........",
        ".....XXXXXXPPPPPX.......",
        ".....XBXXCXCPPPPXXXX....",
        ".....XXPPXXXXGGLXXBBX...",
        ".....XXPBXXXXGLGXXBBX...",
        ".....XBXXGGGGXXXXX......",
        ".....XBXXGGGGXXX........",
        ".....XXXXXXRRRXX........",
        "......XXXXXXXXXX........",
        ".......XXXRRXXRX........",
        "........XXXXXXXX........",
        "........XXXXXBXX........",
        "........XBXXXXX.........",
        "........XXX.............",
    ],
    # Frame 22: Flail variation - Airborne balance recovery
    [
        "....................XX..",
        "..................XHHX..",
        ".................XHWXX..",
        "................XWWX....",
        "..........XXXXXXCX......",
        ".........XXGGXXX........",
        "........XGGLLGGX........",
        ".......XGGXGLLGXG.......",
        ".......XGXGGGLGXX.......",
        ".......XXXBXXXGGX.......",
        ".......XXBBBBBBXX.......",
        "....XXXXXPPPPPPXX.......",
        "....XBBXXPPPPPPX........",
        "....XBBXXRRPPXXX........",
        "....XXXXXXRXXXXX........",
        "......XXXXXRRRRX........",
        ".......XXXXRRRRXXXX.....",
        "........XXRRRXXXPPX.....",
        "........XXXXXXXXBPX.....",
        "........XRXXRRXXXX......",
        "........XXXXXXXX........",
        "........XXXXXXXX........",
        ".......XBXXXXXXBX.......",
        ".......XXX....XXX.......",
    ],
    # Frame 23: Impact preparation - Tucking legs to absorb landing
    [
        "........................",
        "........................",
        "..XXX...................",
        "..XHHX..................",
        "...XWHX.......XX........",
        "....XWWX...XXXGGX.......",
        "......XCX.XGGLLGGX......",
        "........XXGLLLLLGX......",
        ".......XXGGLLGGGXX......",
        ".......XGGLXXGGXXX......",
        "......XXXPXBBBPX........",
        ".....XXXXXXPPPPPX.......",
        ".....XBXXCXCPPPPXXXX....",
        ".....XXPPXXXXGGLXXBBX...",
        ".....XXPBXXXXGLGXXBBX...",
        ".....XBXXGGGGXXXXX......",
        ".....XBXXGGGGXXX........",
        ".....XXXXXXRRRXX........",
        "......XXXXXXXXXX........",
        ".......XXXRRXXRX........",
        "........XXXXXXXX........",
        "........XXXXXBXX........",
        "........XBXXXXX.........",
        "........XXX.............",
    ],
]

ALL_ROWS = [
    ROW_0_IDLE,
    ROW_1_WALK,
    ROW_2_ATTACK,
    ROW_3_DEATH,
    ROW_4_LADDER,
    ROW_5_FALLING,
]


def build_master_spritesheet() -> Image.Image:
    """Builds the 128x144 RGBA master spritesheet (6 rows x 4 cols of 32x24 cells)."""
    sheet = Image.new("RGBA", (128, 144), (0, 0, 0, 0))
    for row_idx, row_frames in enumerate(ALL_ROWS):
        for col_idx, frame_grid in enumerate(row_frames):
            base_x = col_idx * 32
            base_y = row_idx * 24
            for y, row_str in enumerate(frame_grid):
                for x, ch in enumerate(row_str):
                    rgba = COLOR_MAP.get(ch, (0, 0, 0, 0))
                    if rgba[3] > 0:
                        sheet.putpixel((base_x + x, base_y + y), rgba)
    return sheet


def generate_animation_gifs(out_dir: Path):
    """Generate separate animated preview GIFs for each of the 6 movement states."""
    out_dir.mkdir(parents=True, exist_ok=True)
    scale = 4
    fps_durations = [140, 110, 120, 180, 130, 130]
    names = ["idle", "walk", "attack", "death", "ladder", "falling"]

    for row_idx, (row_frames, name, dur) in enumerate(zip(ALL_ROWS, names, fps_durations)):
        gif_frames = []
        for frame_grid in row_frames:
            im = Image.new("RGBA", (24, 24), (20, 24, 32, 255))
            for y, row_str in enumerate(frame_grid):
                for x, ch in enumerate(row_str):
                    rgba = COLOR_MAP.get(ch, (0, 0, 0, 0))
                    if rgba[3] > 0:
                        im.putpixel((x, y), rgba)
            # Upscale 4x with nearest-neighbor crispness
            scaled = im.resize((24 * scale, 24 * scale), Image.NEAREST)
            gif_frames.append(scaled)

        gif_path = out_dir / f"forest_ranger_{name}.gif"
        gif_frames[0].save(
            gif_path,
            save_all=True,
            append_images=gif_frames[1:],
            duration=dur,
            loop=0,
            optimize=False,
        )
        print(f"  [+] Saved GIF: {gif_path.name}")


def main():
    print("=== Generating Forest Ranger ('Briar') Spritesheet ===")
    master_png = PROJECT_ROOT / "assets/graphics/player/player_master_female_128x144.png"
    preview_dir = PROJECT_ROOT / "assets/graphics/player/ranger_previews"

    sheet = build_master_spritesheet()
    master_png.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(master_png)
    print(f"[OK] Master PNG written to: {master_png} ({sheet.size[0]}x{sheet.size[1]})")

    print("[*] Generating animated GIFs for each movement state...")
    generate_animation_gifs(preview_dir)
    print("=== Complete! ===")


if __name__ == "__main__":
    main()
