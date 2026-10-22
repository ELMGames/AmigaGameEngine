#!/usr/bin/env python3
"""
tools/generate_enemies.py
-------------------------
Generates 100% original, copyright-free 16x16 4-frame animated enemy spritesheets
for the Amiga Game Engine, with multiple thematic options:

Theme Options:
  1. "fantasy": Classic Retro Arcade / Fantasy
     - Row 0: Bouncing Slime (Ground Patrol / Crawler - squish & hop)
     - Row 1: Cave Bat / Gargoyle (Air Patrol / Flyer - 4-frame wing flap)
     - Row 2: Armored Beetle (Ground Patrol / Walker - legs & antennae)
  2. "mecha": Cyberpunk & Sci-Fi Drones
     - Row 0: Treadbot Sentry (Ground Patrol - rolling tread & visor pulse)
     - Row 1: Hover Eyebot (Air Patrol - floating bob & jet pulse)
     - Row 2: Walker Automaton (Ground Patrol - mechanical step & claw snap)
  3. "nature": Enchanted Forest / Woodland Critters
     - Row 0: Sporeling Mushroom (Ground Patrol - cap squash & hop)
     - Row 1: Buzzing Hornet (Air Patrol - high-speed wing flutter)
     - Row 2: Spiky Hedgehog (Ground Patrol - trotting paws & bristling quills)

Usage:
  python tools/generate_enemies.py --preview           Generate preview sheets & animated GIFs for all themes
  python tools/generate_enemies.py --install fantasy   Install fantasy theme into assets/graphics/enemies/
  python tools/generate_enemies.py --install mecha     Install mecha theme into assets/graphics/enemies/
  python tools/generate_enemies.py --install nature    Install nature theme into assets/graphics/enemies/
"""

import sys
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ENEMIES_DIR = PROJECT_ROOT / "assets" / "graphics" / "enemies"
PREVIEW_DIR = ENEMIES_DIR / "options_preview"

# In-game 16-color OCS palette
PALETTE_OCS = [
    (0, 0, 0),       # 0: Transparent ($0000)
    (1, 11, 14),     # 1: 0x1BE Vibrant Cyan
    (3, 3, 2),       # 2: 0x332 Dark Charcoal outline
    (15, 15, 15),    # 3: 0xFFF Pure White highlights
    (2, 7, 4),       # 4: 0x274 Forest Green
    (1, 9, 3),       # 5: 0x193 Grass Green
    (15, 9, 1),      # 6: 0xF91 Vibrant Orange
    (2, 5, 12),      # 7: 0x25C Deep Blue
    (15, 12, 2),     # 8: 0xFC2 Vibrant Gold / Yellow
    (13, 10, 6),     # 9: 0xDA6 Warm Sand / Cream
    (11, 7, 4),      # 10: 0xB74 Stone / Earth Brown
    (8, 1, 3),       # 11: 0x813 Rich Maroon
    (13, 1, 2),      # 12: 0xD12 Vibrant Red
    (8, 9, 11),      # 13: 0x89B Slate Grey/Blue
    (1, 7, 7),       # 14: 0x177 Vibrant Teal
    (12, 10, 8),     # 15: 0xCA8 Tan / Warm Peach
]

PAL_8BIT = [(r * 17, g * 17, b * 17) for r, g, b in PALETTE_OCS]

LEGEND = {
    '.': 0,   # Transparent
    'C': 1,   # Vibrant Cyan
    'X': 2,   # Dark Charcoal outline
    'W': 3,   # Pure White highlights
    'F': 4,   # Forest Green
    'G': 5,   # Grass Green
    'O': 6,   # Vibrant Orange
    'B': 7,   # Deep Blue
    'Y': 8,   # Vibrant Gold / Yellow
    'A': 9,   # Warm Sand / Cream
    'D': 10,  # Stone / Earth Brown
    'M': 11,  # Rich Maroon
    'R': 12,  # Vibrant Red
    'S': 13,  # Slate Grey/Blue
    'T': 14,  # Vibrant Teal
    'P': 15,  # Peach / Pink
}

# ==============================================================================
# THEME 1: CLASSIC RETRO FANTASY
# ==============================================================================
FANTASY_ENEMIES = {
    "name": "Classic Arcade Fantasy",
    "enemies": [
        {
            "name": "Bouncing Slime",
            "type": 1,
            "role": "Ground Patrol / Crawler",
            "frames": [
                # F0: Idle resting dome
                [
                    "................",
                    "................",
                    "................",
                    ".....XXXXXX.....",
                    "...XXCCCCCCXX...",
                    "..XCCCCCCCCCCX..",
                    ".XCCCWCCCWCCCCX.",
                    ".XCCCXCCCXCCCCX.",
                    "XCCCCCCCCCCCCCCX",
                    "XCCCCCCCCCCCCCCX",
                    "XCCCTCCCCCTCCCCX",
                    "XCCCCCCCCCCCCCCX",
                    "XTTTTTTTTTTTTTTX",
                    "XBBBBBBBBBBBBBBX",
                    ".XXXXXXXXXXXXXX.",
                    "................",
                ],
                # F1: Squish down (prep leap)
                [
                    "................",
                    "................",
                    "................",
                    "................",
                    "................",
                    "...XXXXXXXXXX...",
                    "..XCCCCCCCCCCX..",
                    ".XCCCWCCCWCCCCX.",
                    "XCCCCXCCCXCCCCCX",
                    "XCCCCCCCCCCCCCCX",
                    "XCCCCCCCCCCCCCCX",
                    "XCCCTCCCCCTCCCCX",
                    "XTTTTTTTTTTTTTTX",
                    "XBBBBBBBBBBBBBBX",
                    "XXXXXXXXXXXXXXXX",
                    "................",
                ],
                # F2: Leap stretch (elongated vertical oval, lifting off ground)
                [
                    "................",
                    "......XXXX......",
                    "....XXCCCCXX....",
                    "...XCCCCCCCCX...",
                    "..XCCCWCCCWCCX..",
                    "..XCCCXCCCXCCX..",
                    "..XCCCCCCCCCCX..",
                    "..XCCCCCCCCCCX..",
                    "..XCCCTCCCTCCX..",
                    "..XCCCCCCCCCCX..",
                    "..XTTTTTTTTTTX..",
                    "..XBBBBBBBBBBX..",
                    "...XXXXXXXXXX...",
                    "................",
                    "................",
                    "................",
                ],
                # F3: Landing rebound (round dome falling back)
                [
                    "................",
                    "................",
                    ".....XXXXXX.....",
                    "...XXCCCCCCXX...",
                    "..XCCCCCCCCCCX..",
                    ".XCCCWCCCWCCCCX.",
                    ".XCCCXCCCXCCCCX.",
                    "XCCCCCCCCCCCCCCX",
                    "XCCCCCCCCCCCCCCX",
                    "XCCCCCCCCCCCCCCX",
                    "XCCCTCCCCCTCCCCX",
                    "XTTTTTTTTTTTTTTX",
                    "XBBBBBBBBBBBBBBX",
                    ".XXXXXXXXXXXXXX.",
                    "................",
                    "................",
                ]
            ]
        },
        {
            "name": "Cave Bat",
            "type": 2,
            "role": "Air Patrol / Flyer",
            "frames": [
                # F0: Wings high
                [
                    ".XX........XX...",
                    "XMRX......XRMX..",
                    "XMRRX....XRRMX..",
                    ".XMRRX..XRRMX...",
                    "..XMRXXXXRRMX...",
                    "...XMRYYRMX.....",
                    "..XRRWYWWYRRX...",
                    "..XRRXYXXYRRX...",
                    "..XRRRWWWRRRX...",
                    "...XMMMMMMMX....",
                    "....XRRRRRX.....",
                    ".....XRMRX......",
                    ".....XXMXX......",
                    "......XXX.......",
                    "................",
                    "................",
                ],
                # F1: Wings mid-glide
                [
                    "................",
                    "................",
                    "XX..........XX..",
                    "XMRXX....XXRMX..",
                    ".XMRRXXXXRRMX...",
                    "..XMRRYYRMX.....",
                    "..XRRWYWWYRRX...",
                    "..XRRXYXXYRRX...",
                    "..XRRRWWWRRRX...",
                    "...XMMMMMMMX....",
                    "....XRRRRRX.....",
                    ".....XRMRX......",
                    ".....XXMXX......",
                    "......XXX.......",
                    "................",
                    "................",
                ],
                # F2: Wings fully down
                [
                    "................",
                    "................",
                    "................",
                    "................",
                    ".....XXXXXX.....",
                    "...XXMRYYRMX....",
                    "..XRRRWYWWYRRX..",
                    ".XMRRRXYXXYRRMX.",
                    "XMRRRRRWWWRRRRMX",
                    "XXMRRMMMMMMRRXX.",
                    "..XXRRRRRRRXX...",
                    "....XXRMRXX.....",
                    ".....XXMXX......",
                    "......XXX.......",
                    "................",
                    "................",
                ],
                # F3: Wings recovering up
                [
                    "................",
                    "................",
                    "XX..........XX..",
                    "XMRXX....XXRMX..",
                    ".XMRRXXXXRRMX...",
                    "..XMRRYYRMX.....",
                    "..XRRWYWWYRRX...",
                    "..XRRXYXXYRRX...",
                    "..XRRRWWWRRRX...",
                    "...XMMMMMMMX....",
                    "....XRRRRRX.....",
                    ".....XRMRX......",
                    ".....XXMXX......",
                    "......XXX.......",
                    "................",
                    "................",
                ]
            ]
        },
        {
            "name": "Armored Beetle",
            "type": 3,
            "role": "Armored Ground Walker",
            "frames": [
                # F0: Walking pose A (left leg forward)
                [
                    "....X......X....",
                    "...XF......FX...",
                    "....X......X....",
                    "....XXXXXXXX....",
                    "...XADDDDAAAX...",
                    "..XADDDDDDAAAX..",
                    ".XADDDDDDDDDAAX.",
                    ".XADDDODODDDAAX.",
                    ".XADDDXXXXDDAAX.",
                    ".XADDDDDDDDDAAX.",
                    ".XADDDDDDDDDAAX.",
                    "..XADDDDDAAAX...",
                    "...XXXXXXXXXX...",
                    "..X..X....X..X..",
                    ".X....X..X....X.",
                    "................",
                ],
                # F1: Stride mid
                [
                    "...X........X...",
                    "....XF....FX....",
                    "....XXXXXXXX....",
                    "...XADDDDAAAX...",
                    "..XADDDDDDAAAX..",
                    ".XADDDDDDDDDAAX.",
                    ".XADDDODODDDAAX.",
                    ".XADDDXXXXDDAAX.",
                    ".XADDDDDDDDDAAX.",
                    ".XADDDDDDDDDAAX.",
                    "..XADDDDDAAAX...",
                    "...XXXXXXXXXX...",
                    "....X.X..X.X....",
                    "....X.X..X.X....",
                    "...X..X..X..X...",
                    "................",
                ],
                # F2: Walking pose B (right leg forward)
                [
                    "....X......X....",
                    "...XF......FX...",
                    "....X......X....",
                    "....XXXXXXXX....",
                    "...XADDDDAAAX...",
                    "..XADDDDDDAAAX..",
                    ".XADDDDDDDDDAAX.",
                    ".XADDDODODDDAAX.",
                    ".XADDDXXXXDDAAX.",
                    ".XADDDDDDDDDAAX.",
                    ".XADDDDDDDDDAAX.",
                    "..XADDDDDAAAX...",
                    "...XXXXXXXXXX...",
                    "..X..X....X..X..",
                    ".X....X..X....X.",
                    "................",
                ],
                # F3: Stride mid
                [
                    "...X........X...",
                    "....XF....FX....",
                    "....XXXXXXXX....",
                    "...XADDDDAAAX...",
                    "..XADDDDDDAAAX..",
                    ".XADDDDDDDDDAAX.",
                    ".XADDDODODDDAAX.",
                    ".XADDDXXXXDDAAX.",
                    ".XADDDDDDDDDAAX.",
                    ".XADDDDDDDDDAAX.",
                    "..XADDDDDAAAX...",
                    "...XXXXXXXXXX...",
                    "....X.X..X.X....",
                    "....X.X..X.X....",
                    "...X..X..X..X...",
                    "................",
                ]
            ]
        }
    ]
}

# ==============================================================================
# THEME 2: CYBER MECHA & DRONES
# ==============================================================================
MECHA_ENEMIES = {
    "name": "Cyber Mecha & Sci-Fi Drones",
    "enemies": [
        {
            "name": "Treadbot Sentry",
            "type": 1,
            "role": "Ground Sentry / Rolling Bot",
            "frames": [
                # F0: Visor cyan, tread roll 0
                [
                    ".......XX.......",
                    ".......XWX......",
                    ".......XX.......",
                    "....XXXXXXXX....",
                    "...XSSSSSSSSX...",
                    "..XSSCCCCCCSSX..",
                    "..XSSCWCCWCSSX..",
                    "..XSSSSSSSSSSX..",
                    ".XSYYSSSYYSSSYX.",
                    ".XYYYYYYYYYYYYX.",
                    "XXXXXXXXXXXXXXXX",
                    "XSSXXSSXXSSXXSSX",
                    "XSXXXXXXXXXXXXSX",
                    "XSSXXSSXXSSXXSSX",
                    "XXXXXXXXXXXXXXXX",
                    "................",
                ],
                # F1: Visor pulse white, tread roll 1
                [
                    ".......XX.......",
                    ".......XOX......",
                    ".......XX.......",
                    "....XXXXXXXX....",
                    "...XSSSSSSSSX...",
                    "..XSSWWWWWWSSX..",
                    "..XSSWCCCCWCSSX.",
                    "..XSSSSSSSSSSX..",
                    ".XSYYSSSYYSSSYX.",
                    ".XYYYYYYYYYYYYX.",
                    "XXXXXXXXXXXXXXXX",
                    "XSXXSSXXSSXXSSXX",
                    "XSXXXXXXXXXXXXSX",
                    "XSXXSSXXSSXXSSXX",
                    "XXXXXXXXXXXXXXXX",
                    "................",
                ],
                # F2: Visor cyan, tread roll 2
                [
                    ".......XX.......",
                    ".......XWX......",
                    ".......XX.......",
                    "....XXXXXXXX....",
                    "...XSSSSSSSSX...",
                    "..XSSCCCCCCSSX..",
                    "..XSSCWCCWCSSX..",
                    "..XSSSSSSSSSSX..",
                    ".XSYYSSSYYSSSYX.",
                    ".XYYYYYYYYYYYYX.",
                    "XXXXXXXXXXXXXXXX",
                    "XXSSXXSSXXSSXXSS",
                    "XSXXXXXXXXXXXXSX",
                    "XXSSXXSSXXSSXXSS",
                    "XXXXXXXXXXXXXXXX",
                    "................",
                ],
                # F3: Visor pulse teal, tread roll 3
                [
                    ".......XX.......",
                    ".......XOX......",
                    ".......XX.......",
                    "....XXXXXXXX....",
                    "...XSSSSSSSSX...",
                    "..XSSTTTTTTSSX..",
                    "..XSSTWCCTWSSX..",
                    "..XSSSSSSSSSSX..",
                    ".XSYYSSSYYSSSYX.",
                    ".XYYYYYYYYYYYYX.",
                    "XXXXXXXXXXXXXXXX",
                    "XSSXXSSXXSSXXSSX",
                    "XSXXXXXXXXXXXXSX",
                    "XSSXXSSXXSSXXSSX",
                    "XXXXXXXXXXXXXXXX",
                    "................",
                ]
            ]
        },
        {
            "name": "Hover Eyebot",
            "type": 2,
            "role": "Air Patrol / Floating Drone",
            "frames": [
                # F0: Float mid, small flame
                [
                    "......XXXX......",
                    "....XXSSSSXX....",
                    "...XSSWWWWSSX...",
                    "..XSSWCCCCWSSX..",
                    ".XSSWCRRRRCWSSX.",
                    ".XSSWCRWWRCWSSX.",
                    ".XSSWCRRRRCWSSX.",
                    "..XSSWCCCCWSSX..",
                    "...XSSWWWWSSX...",
                    "....XXSSSSXX....",
                    ".....XXXXXX.....",
                    "......XOOX......",
                    "......XOOX......",
                    ".......XYX......",
                    "................",
                    "................",
                ],
                # F1: Float up 1px, flare flame
                [
                    "................",
                    "......XXXX......",
                    "....XXSSSSXX....",
                    "...XSSWWWWSSX...",
                    "..XSSWCCCCWSSX..",
                    ".XSSWCRRRRCWSSX.",
                    ".XSSWCRWWRCWSSX.",
                    ".XSSWCRRRRCWSSX.",
                    "..XSSWCCCCWSSX..",
                    "...XSSWWWWSSX...",
                    "....XXSSSSXX....",
                    ".....XXXXXX.....",
                    ".....XOOOOX.....",
                    "......XOOX......",
                    ".......XYX......",
                    "................",
                ],
                # F2: Float mid, small flame
                [
                    "......XXXX......",
                    "....XXSSSSXX....",
                    "...XSSWWWWSSX...",
                    "..XSSWCCCCWSSX..",
                    ".XSSWCRRRRCWSSX.",
                    ".XSSWCRWWRCWSSX.",
                    ".XSSWCRRRRCWSSX.",
                    "..XSSWCCCCWSSX..",
                    "...XSSWWWWSSX...",
                    "....XXSSSSXX....",
                    ".....XXXXXX.....",
                    "......XOOX......",
                    "......XOOX......",
                    ".......XYX......",
                    "................",
                    "................",
                ],
                # F3: Float down 1px, flicker flame
                [
                    "......XXXX......",
                    "....XXSSSSXX....",
                    "...XSSWWWWSSX...",
                    "..XSSWCCCCWSSX..",
                    ".XSSWCRRRRCWSSX.",
                    ".XSSWCRWWRCWSSX.",
                    ".XSSWCRRRRCWSSX.",
                    "..XSSWCCCCWSSX..",
                    "...XSSWWWWSSX...",
                    "....XXSSSSXX....",
                    ".....XXXXXX.....",
                    ".......XX.......",
                    "......XOOX......",
                    ".......XYX......",
                    "........X.......",
                    "................",
                ]
            ]
        },
        {
            "name": "Walker Automaton",
            "type": 3,
            "role": "Armored Ground Mecha",
            "frames": [
                # F0: Left step, claw open
                [
                    ".....XXXXXX.....",
                    "....XDDDDDDAX...",
                    "...XDDDRRRDDDX..",
                    "...XDDDRWRDDDX..",
                    "...XDDDRRRDDDX..",
                    "....XDDDDDDAX...",
                    ".XXXXXDDDDXXXXX.",
                    "XMX..XXXXXX..XMX",
                    "XMX..XSSSSX..XMX",
                    "XX...XSSSSX...XX",
                    ".....XMMMMX.....",
                    "....XMM..MMX....",
                    "...XMX....XMX...",
                    "..XMX......XMX..",
                    ".XMMX......XMMX.",
                    ".XXX........XXX.",
                ],
                # F1: Stride neutral, claw snap
                [
                    ".....XXXXXX.....",
                    "....XDDDDDDAX...",
                    "...XDDDRRRDDDX..",
                    "...XDDDRWRDDDX..",
                    "...XDDDRRRDDDX..",
                    "....XDDDDDDAX...",
                    "XXXXXXDDDDXXXXXX",
                    ".XMX.XXXXXX.XMX.",
                    ".XMX.XSSSSX.XMX.",
                    "..XX.XSSSSX.XX..",
                    ".....XMMMMX.....",
                    ".....XMMMMX.....",
                    "....XMM..MMX....",
                    "...XMX....XMX...",
                    "...XMX....XMX...",
                    "...XXX....XXX...",
                ],
                # F2: Right step, claw open
                [
                    ".....XXXXXX.....",
                    "....XDDDDDDAX...",
                    "...XDDDRRRDDDX..",
                    "...XDDDRWRDDDX..",
                    "...XDDDRRRDDDX..",
                    "....XDDDDDDAX...",
                    ".XXXXXDDDDXXXXX.",
                    "XMX..XXXXXX..XMX",
                    "XMX..XSSSSX..XMX",
                    "XX...XSSSSX...XX",
                    ".....XMMMMX.....",
                    "....XMM..MMX....",
                    "...XMX....XMX...",
                    "..XMX......XMX..",
                    ".XMMX......XMMX.",
                    ".XXX........XXX.",
                ],
                # F3: Stride neutral, claw snap
                [
                    ".....XXXXXX.....",
                    "....XDDDDDDAX...",
                    "...XDDDRRRDDDX..",
                    "...XDDDRWRDDDX..",
                    "...XDDDRRRDDDX..",
                    "....XDDDDDDAX...",
                    "XXXXXXDDDDXXXXXX",
                    ".XMX.XXXXXX.XMX.",
                    ".XMX.XSSSSX.XMX.",
                    "..XX.XSSSSX.XX..",
                    ".....XMMMMX.....",
                    ".....XMMMMX.....",
                    "....XMM..MMX....",
                    "...XMX....XMX...",
                    "...XMX....XMX...",
                    "...XXX....XXX...",
                ]
            ]
        }
    ]
}

# ==============================================================================
# THEME 3: ENCHANTED FOREST & NATURE CRITTERS (REFINED AMIGA OCS)
# ==============================================================================
NATURE_ENEMIES = {
    "name": "Enchanted Forest & Woodland",
    "enemies": [
        {
            "name": "Mushroom Sporeling",
            "type": 1,
            "role": "Ground Patrol / Bouncing Hopper",
            "frames": [
                # F0: Alert standing pose with sparkling eyes
                [
                    "......XXXX......",
                    "....XXRRRRXX....",
                    "...XRRWWRRRRX...",
                    "..XRRRWWWRRRRX..",
                    ".XRRWRRRRRWRRRX.",
                    ".XRWWWRRRWWWRRX.",
                    "XRRWWWRRRWWWRRRX",
                    "XMMMMMMMMMMMMMMX",
                    "XXXXXXXXXXXXXXXX",
                    "...XPXWXXPXWX...",
                    "...XPPPPPPPPX...",
                    "...XPPPMMMPPX...",
                    "....XPPPPPPX....",
                    "....XXXXXXXX....",
                    "...XAAAXXAAAX...",
                    "...XXXX..XXXX...",
                ],
                # F1: Deep squash anticipation (eyes squint closed, cap compresses)
                [
                    "................",
                    "................",
                    "................",
                    ".....XXXXXX.....",
                    "...XXRRRRRRXX...",
                    "..XRRWWRRWRRRX..",
                    ".XRWWWRRWWWRRRX.",
                    "XRRWWWRRWWWRRRRX",
                    "XMMMMMMMMMMMMMMX",
                    "XXXXXXXXXXXXXXXX",
                    "..XPXXPPPPXXPX..",
                    "..XPPPPPPPPPPX..",
                    "..XPPPMMMMMMPX..",
                    "...XXXXXXXXXX...",
                    "..XAAAAXXAAAAX..",
                    "..XXXXX..XXXXX..",
                ],
                # F2: Airborne leap (lifts 3px, feet dangle, spore glints puff)
                [
                    "...Y......Y.....",
                    "......XXXX......",
                    "....XXRRRRXX....",
                    "...XRRWWRRRRX...",
                    "..XRRRWWWRRRRX..",
                    ".XRRWRRRRRWRRRX.",
                    ".XRWWWRRRWWWRRX.",
                    "XRRWWWRRRWWWRRRX",
                    "XMMMMMMMMMMMMMMX",
                    "XXXXXXXXXXXXXXXX",
                    "...XPXWXXPXWX...",
                    "...XPPPPPPPPX...",
                    "....XPPPPPPX....",
                    "....XXXXXXXX....",
                    "....XAAXXAAX....",
                    "....XXXX.XXXX...",
                ],
                # F3: Rebound touchdown (cap flexes, eyes open)
                [
                    "................",
                    "......XXXX......",
                    "....XXRRRRXX....",
                    "...XRRWWRRRRX...",
                    "..XRRRWWWRRRRX..",
                    ".XRRWRRRRRWRRRX.",
                    ".XRWWWRRRWWWRRX.",
                    "XRRWWWRRRWWWRRRX",
                    "XMMMMMMMMMMMMMMX",
                    "XXXXXXXXXXXXXXXX",
                    "...XPXWXXPXWX...",
                    "...XPPPPPPPPX...",
                    "...XPPPMMMPPX...",
                    "....XPPPPPPX....",
                    "....XXXXXXXX....",
                    "...XAAAXXAAAX...",
                ]
            ]
        },
        {
            "name": "Buzzing Hornet",
            "type": 2,
            "role": "Air Patrol / Flyer",
            "frames": [
                # F0: Wings high (V-angle)
                [
                    ".XX........XX...",
                    "XCWX......XWCX..",
                    ".XCWX....XWCX...",
                    "..XCWXXXXWCX....",
                    "...XXGYYGXX.....",
                    "..XGWYYYYWGX....",
                    "..XGXXGGXXGX....",
                    ".XYYYYYYYYYYX...",
                    ".XXXXX..XXXXX...",
                    ".XYYYYYYYYYYX...",
                    "..XXXXXXXXXX....",
                    "..XYYYYYYYYX....",
                    "...XXXXXXXX.....",
                    ".....XOOX.......",
                    "......XX........",
                    "................",
                ],
                # F1: Wings mid downstroke flutter (cyan motion blur trail)
                [
                    "................",
                    ".XXXX....XXXX...",
                    "XCWWCXXXXCWWX...",
                    ".XCCXXXXXXCCX...",
                    "...XXGYYGXX.....",
                    "..XGWYYYYWGX....",
                    "..XGXXGGXXGX....",
                    ".XYYYYYYYYYYX...",
                    ".XXXXX..XXXXX...",
                    ".XYYYYYYYYYYX...",
                    "..XXXXXXXXXX....",
                    "..XYYYYYYYYX....",
                    "...XXXXXXXX.....",
                    ".....XOOX.......",
                    "......XX........",
                    "................",
                ],
                # F2: Wings fully down, stinger points forward
                [
                    "................",
                    "................",
                    "................",
                    "...XXGYYGXX.....",
                    "..XGWYYYYWGX....",
                    "..XGXXGGXXGX....",
                    ".XYYYYYYYYYYX...",
                    "XCWXX....XXWCX..",
                    "XCWWXXXXXXWWCX..",
                    ".XXXXX..XXXXX...",
                    ".XYYYYYYYYYYX...",
                    "..XXXXXXXXXX....",
                    "..XYYYYYYYYX....",
                    "...XXXXXXXX.....",
                    ".....XOOX.......",
                    "......XX........",
                ],
                # F3: Wings swept up (ascending recovery)
                [
                    "................",
                    ".XXXX....XXXX...",
                    "XCWWCXXXXCWWX...",
                    ".XCCXXXXXXCCX...",
                    "...XXGYYGXX.....",
                    "..XGWYYYYWGX....",
                    "..XGXXGGXXGX....",
                    ".XYYYYYYYYYYX...",
                    ".XXXXX..XXXXX...",
                    ".XYYYYYYYYYYX...",
                    "..XXXXXXXXXX....",
                    "..XYYYYYYYYX....",
                    "...XXXXXXXX.....",
                    ".....XOOX.......",
                    "......XX........",
                    "................",
                ]
            ]
        },
        {
            "name": "Spiky Hedgehog",
            "type": 3,
            "role": "Ground Patrol / Scuttler",
            "frames": [
                # F0: Neutral scuttle forward (quills arched, snout low)
                [
                    "................",
                    "......X..X..X...",
                    ".....XDX.XDX.X..",
                    "....XDDDXDDDXDX.",
                    "...XDDDDDDDDDX..",
                    "..XDDDAAADDDDDX.",
                    ".XDDDAAAAADDDDDX",
                    "XDDDDDDDDDDDDDDX",
                    "XDDDDDDDAPPPADDX",
                    "XDDDDDDAPWPPAPDX",
                    ".XDDDDDAPPXPPP..",
                    ".XDDDDDDAPPPAPX.",
                    "XDDDDDDDDDDDDDDX",
                    "XDDDDDDDDDDDDDDX",
                    "XXXXXXXXXXXXXXXX",
                    "................",
                ],
                # F1: Quill ripple up & snout lifts (sniffing while sliding)
                [
                    ".....X..X..X....",
                    "....XDX.XDX.X...",
                    "...XDDDXDDDXDX..",
                    "..XDDDDDDDDDX...",
                    ".XDDDAAADDDDDX..",
                    "XDDDAAAAADDDDDX.",
                    "XDDDDDDDDDDDDDDX",
                    "XDDDDDDDAPPPADDX",
                    "XDDDDDDAPWPPAPDX",
                    ".XDDDDDAPPXPPP..",
                    ".XDDDDDDAPPPAPX.",
                    "XDDDDDDDDDDDDDDX",
                    "XDDDDDDDDDDDDDDX",
                    "XXXXXXXXXXXXXXXX",
                    "................",
                    "................",
                ],
                # F2: Quills settle, snout dips forward (forward momentum)
                [
                    "................",
                    "......X..X..X...",
                    ".....XDX.XDX.X..",
                    "....XDDDXDDDXDX.",
                    "...XDDDAADDDDDX.",
                    "..XDDDAAAAADDDDX",
                    ".XDDDDDDDDDDDDDX",
                    "XDDDDDDDDDDDDDDX",
                    "XDDDDDDDAPPPADDX",
                    "XDDDDDDAPWPPAPDX",
                    ".XDDDDDAPPXPPP..",
                    ".XDDDDDDAPPPAPX.",
                    "XDDDDDDDDDDDDDDX",
                    "XDDDDDDDDDDDDDDX",
                    "XXXXXXXXXXXXXXXX",
                    "................",
                ],
                # F3: Body compresses slightly forward (thrust glide)
                [
                    "................",
                    ".......X..X..X..",
                    "......XDX.XDX.X.",
                    ".....XDDDXDDDXDX",
                    "....XDDDDDDDDDX.",
                    "...XDDDAAADDDDDX",
                    "..XDDDAAAAADDDDX",
                    ".XDDDDDDDDDDDDDX",
                    "XDDDDDDDAPPPADDX",
                    "XDDDDDDAPWPPAPDX",
                    ".XDDDDDAPPXPPP..",
                    ".XDDDDDDAPPPAPX.",
                    "XDDDDDDDDDDDDDDX",
                    "XDDDDDDDDDDDDDDX",
                    "XXXXXXXXXXXXXXXX",
                    "................",
                ]
            ]
        }
    ]
}

THEMES = {
    "fantasy": FANTASY_ENEMIES,
    "mecha": MECHA_ENEMIES,
    "nature": NATURE_ENEMIES,
}


def build_theme_sheet(theme_data) -> Image.Image:
    """Builds a 64x48 RGBA image containing exactly 3 enemies (3 rows x 16px)."""
    sheet = Image.new("RGBA", (64, 48), (0, 0, 0, 0))
    for row_idx, enemy in enumerate(theme_data["enemies"]):
        for col_idx, frame_grid in enumerate(enemy["frames"]):
            for y, row_str in enumerate(frame_grid):
                for x, ch in enumerate(row_str):
                    idx = LEGEND.get(ch, 0)
                    if idx > 0:
                        rgb = PAL_8BIT[idx]
                        px = col_idx * 16 + x
                        py = row_idx * 16 + y
                        sheet.putpixel((px, py), (rgb[0], rgb[1], rgb[2], 255))
    return sheet


def export_theme_previews(theme_key: str, theme_data: dict, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    sheet = build_theme_sheet(theme_data)

    # 1. Save 64x48 raw PNG
    sheet_png = out_dir / f"enemies_{theme_key}_64x48.png"
    sheet.save(sheet_png)

    # 2. Scaled Contact Sheet (8x scale with labels & grid)
    scale = 6
    w, h = 64, 48 # only the 3 populated rows
    crop_sheet = sheet.crop((0, 0, w, h))
    
    pad_left = 180
    pad_top = 36
    preview_img = Image.new("RGBA", (pad_left + w * scale + 24, pad_top + h * scale + 24), (20, 24, 34, 255))
    draw = ImageDraw.Draw(preview_img)

    # Title
    draw.text((16, 12), f"Option: {theme_data['name']}", fill=(255, 220, 100, 255))

    scaled_art = crop_sheet.resize((w * scale, h * scale), Image.Resampling.NEAREST)
    preview_img.paste(scaled_art, (pad_left, pad_top), scaled_art)

    # Grid
    for i in range(5):
        gx = pad_left + i * 16 * scale
        draw.line([(gx, pad_top), (gx, pad_top + h * scale)], fill=(60, 68, 90, 255), width=1)
    for i in range(4):
        gy = pad_top + i * 16 * scale
        draw.line([(pad_left, gy), (pad_left + w * scale, gy)], fill=(60, 68, 90, 255), width=1)

    # Frame Headers
    for i in range(4):
        draw.text((pad_left + i * 16 * scale + 18, 16), f"Frame {i}", fill=(180, 195, 220, 255))

    # Row Labels
    for i, enemy in enumerate(theme_data["enemies"]):
        ey = pad_top + i * 16 * scale + 24
        draw.text((16, ey), f"Type {enemy['type']}: {enemy['name']}", fill=(255, 255, 255, 255))
        draw.text((16, ey + 20), f"({enemy['role']})", fill=(140, 160, 190, 255))

    preview_path = out_dir / f"preview_{theme_key}.png"
    preview_img.save(preview_path)
    print(f"  [+] Preview Sheet: {preview_path.name}")

    # 3. Animated GIFs for each enemy (96x96, looping)
    for i, enemy in enumerate(theme_data["enemies"]):
        frames = []
        for col_idx in range(4):
            cel = crop_sheet.crop((col_idx * 16, i * 16, (col_idx + 1) * 16, (i + 1) * 16))
            cel_big = cel.resize((96, 96), Image.Resampling.NEAREST)
            # Paste onto dark contrast background for GIF
            bg = Image.new("RGBA", (96, 96), (24, 28, 40, 255))
            bg.paste(cel_big, (0, 0), cel_big)
            frames.append(bg)

        gif_path = out_dir / f"{theme_key}_enemy{enemy['type']}_{enemy['name'].lower().replace(' ', '_')}.gif"
        frames[0].save(
            gif_path,
            save_all=True,
            append_images=frames[1:],
            duration=160, # ~6.25 fps (matches Amiga ENEMY_ANIM_TICKS = 16 ticks)
            loop=0
        )
        print(f"  [+] Animated GIF: {gif_path.name}")


def install_theme(theme_key: str):
    if theme_key not in THEMES:
        print(f"Error: Unknown theme '{theme_key}'. Choose from: {list(THEMES.keys())}")
        return

    theme_data = THEMES[theme_key]
    print(f"\n[*] Installing theme '{theme_data['name']}' into game...")
    sheet = build_theme_sheet(theme_data)
    
    target_png = ENEMIES_DIR / "enemies_16x16.png"
    sheet.save(target_png)
    print(f"  [OK] Saved: {target_png}")

    # Re-run convert_enemies.py to regenerate raw bitplanes & masks
    print("[*] Running convert_enemies.py...")
    convert_script = PROJECT_ROOT / "tools" / "convert_enemies.py"
    res = subprocess.run([sys.executable, str(convert_script)])
    if res.returncode == 0:
        print(f"\n>>> Theme '{theme_data['name']}' successfully installed and converted for Amiga! <<<")
    else:
        print(f"\n[!] Error during conversion (exit code {res.returncode})")


def main():
    if "--install" in sys.argv:
        idx = sys.argv.index("--install")
        if idx + 1 < len(sys.argv):
            install_theme(sys.argv[idx + 1])
        else:
            print("Error: Missing theme name for --install (fantasy, mecha, nature)")
        return

    print("=== Generating Enemy Options & Previews ===")
    for key, data in THEMES.items():
        print(f"\nTheme: {data['name']}")
        export_theme_previews(key, data, PREVIEW_DIR)

    print("\nAll enemy options generated in:", PREVIEW_DIR)
    print("Run `python tools/generate_enemies.py --install <fantasy|mecha|nature>` to switch!")


if __name__ == "__main__":
    main()
