from pathlib import Path
from PIL import Image, ImageDraw

PROJECT_ROOT = Path("F:/GitHub/AmigaGameEngine")
OUT_DIR = PROJECT_ROOT / "assets" / "graphics" / "animals"

DEFAULT_PALETTE_OCS = [
    (0, 0, 0),       # 0: Transparent ($0000)
    (1, 11, 14),     # 1: 0x1BE Vibrant Cyan
    (3, 3, 2),       # 2: 0x332 Dark Charcoal outline (X)
    (15, 15, 15),    # 3: 0xFFF Pure White (W)
    (2, 7, 4),       # 4: 0x274 Forest Green (K)
    (1, 9, 3),       # 5: 0x193 Grass Green (G)
    (15, 9, 1),      # 6: 0xF91 Vibrant Orange (O)
    (2, 5, 12),      # 7: 0x25C Deep Blue (D)
    (15, 12, 2),     # 8: 0xFC2 Vibrant Gold / Yellow (Y)
    (13, 10, 6),     # 9: 0xDA6 Warm Sand / Cream (C)
    (11, 7, 4),      # 10: 0xB74 Warm Earth Brown (B)
    (8, 1, 3),       # 11: 0x813 Rich Maroon (M)
    (13, 1, 2),      # 12: 0xD12 Vibrant Red (R)
    (8, 9, 11),      # 13: 0x89B Slate Grey/Blue (S)
    (1, 7, 7),       # 14: 0x177 Vibrant Teal (T)
    (12, 10, 8),     # 15: 0xCA8 Peach / Pink (P)
]

PAL_8BIT = [(r * 17, g * 17, b * 17) for r, g, b in DEFAULT_PALETTE_OCS]
PAL_FLAT = []
for r, g, b in PAL_8BIT:
    PAL_FLAT.extend([r, g, b])
PAL_FLAT.extend([0] * (768 - len(PAL_FLAT)))

LEGEND = {
    '.': 0,   # Transparent
    'X': 2,   # Charcoal outline
    'W': 3,   # Pure White
    'O': 6,   # Vibrant Orange
    'Y': 8,   # Vibrant Gold / Yellow
    'C': 9,   # Warm Sand / Cream
    'B': 10,  # Earth Brown
    'M': 11,  # Maroon
    'R': 12,  # Vibrant Red
    'S': 13,  # Slate Grey
    'T': 14,  # Vibrant Teal
    'P': 15,  # Peach / Pink
}

# ==============================================================================
# DOG 1 (D1 - Tan Dog based on d1_raw_16x16_f3.png)
# ==============================================================================
D1_FRAMES = [
    # F0: Stand Alert
    [
        "......X......X..",
        ".....XWX....XWX.",
        ".....XBWXXXXXBWX",
        ".....XBBXCCBXBXX",
        ".XX..XXBCCCCBXX.",
        "XBX..XXCCCCCCBX.",
        "XBX..XCWXCWXBCXX",
        "XXX..XXCCBCCBBXX",
        "XXX...XXCXXCBX..",
        "XBBXXXBXXBBXXXX.",
        ".XBBXCCXXXXXXX..",
        "..XXCWWCCCCXX...",
        "..XXCCCCCCCCX...",
        "..XBXXCCBXXCX...",
        "..XBXXXBXXXBX...",
        "..XXBXXXBXXXBX..",
    ],
    # F1: Head bob / Step (Ears & head dip 1px, tail wags inward)
    [
        "................",
        ".....XXX.....XX.",
        ".....XBWXXXXXBWX",
        ".....XWWXXXXXWBX",
        "..XX.XXXBCCBBXXX",
        ".XBX..XBCWPPCBX.",
        "XXBX.XBWBCCBCBX.",
        "XXX..XBCXCCXCCXX",
        "XXX..XXBCXXCCXXX",
        "XBX..XXXBBBBXXX.",
        "XXBXXBCBXXXXXX..",
        ".XXBBCWPCBBBXX..",
        "..XXPWCCCCCCBX..",
        "..XCCXBCBBBCBX..",
        "..XBXXXBXXXXBX..",
        "..XXBXXXBXXXBX..",
    ],
    # F2: Step forward / Tail curls high
    [
        ".XX..XXX.....XX.",
        "XBWX.XBWXXXXXBWX",
        "XBBX.XWWXXXXXWBX",
        ".XBX.XXXBCCBBXXX",
        ".XBX..XBCWPPCBX.",
        "XBXX.XBWBCCBCBX.",
        "XBX..XBCXCCXCCXX",
        "XXX..XXBCXXCCXXX",
        "XBX..XXXBBBBXX..",
        "XXBXXBCBXXXXXXX.",
        "..XBBCWPCBBBXX..",
        "..XXCWCCCCCCXX..",
        "..XBCBXCCBBCB...",
        "..XBXXXBXXXBX...",
        "..XXBXXXBXXXBX..",
        "...XXXXXXXXXX...",
    ],
    # F3: The User Favorite (d1_raw_16x16_f3.png faithfully transcribed!)
    [
        "......X......XX.",
        ".....XWX....XWXX",
        ".....XBWXXXXXBWX",
        ".....XBBXCCBXBXX",
        ".XX..XXBCCCCBXX.",
        "XBXX.XXCCCCCCBX.",
        "XBX..XCWXCWXBCXX",
        "XXX..XXCCBCCBBXX",
        "XXX...XXCXXCBXX.",
        "XBBXXXBXXBBXXXX.",
        ".XBBXCCXXXXXXX..",
        "..XXCWWCCCCXX...",
        "..XXCCCCCCCCX...",
        "..XBXXCCBXXCX...",
        "..XBXXXBXXXBX...",
        "..XXBXXXBXXXBX..",
    ],
]

# ==============================================================================
# DOG 2 (D2 - White Dog based on d2_raw_16x16_f3.png)
# ==============================================================================
D2_FRAMES = [
    # F0: Sitting happy, tail near rump
    [
        "....XX......XX..",
        "...XWX.....XWX..",
        "..XSWX....XXPWX.",
        "..XWWXXXXXXWPWX.",
        ".XWWWWWWWWWWWWSX",
        ".XWWXXWWWWXXWWSX",
        ".XWWXXWWWWXXWWXX",
        "..XWWWWXXWWWWX..",
        "..XSWWWXXWWWSX..",
        "...XXXXRRPXXX...",
        "..XWWWWWWWWWWX..",
        ".XSWWWWWWWWWWSX.",
        ".XWWWWWWWWWWWWXX",
        ".XWWXXWWXXWWXWWX",
        ".XWWXXWWXXWWXWWX",
        ".XXXXXXXXXXXXXX.",
    ],
    # F1: Tail wags to 45 degrees, head dips 1px, tongue wiggles
    [
        "................",
        "....XX......XX..",
        "...XWX.....XWX..",
        "..XSWX....XXPWX.",
        "..XWWXXXXXXWPWX.",
        ".XWWWWWWWWWWWWSX",
        ".XWWXXWWWWXXWWSX",
        ".XWWXXWWWWXXWWXX",
        "..XWWWWXXWWWWX..",
        "..XSWWWXXWWWSX..",
        "...XXXXPRPXXX.XX",
        "..XWWWWWWWWWWXWX",
        ".XSWWWWWWWWWWSWX",
        ".XWWXXWWXXWWX.WX",
        ".XWWXXWWXXWWX.XX",
        ".XXXXXXXXXXXX...",
    ],
    # F2: Tail horizontal full wag, mouth open happy
    [
        "....XX......XX..",
        "...XWX.....XWX..",
        "..XSWX....XXPWX.",
        "..XWWXXXXXXWPWX.",
        ".XWWWWWWWWWWWWSX",
        ".XWWXXWWWWXXWWSX",
        ".XWWXXWWWWXXWWXX",
        "..XWWWWXXWWWWX..",
        "..XSWWWXXWWWSX..",
        "...XXXXRRPXXX...",
        "..XWWWWWWWWWWXX.",
        ".XSWWWWWWWWWWSWW",
        ".XWWWWWWWWWWWWXX",
        ".XWWXXWWXXWWX...",
        ".XWWXXWWXXWWX...",
        ".XXXXXXXXXXXX...",
    ],
    # F3: The User Favorite (d2_raw_16x16_f3.png faithfully transcribed!)
    [
        "....XX......XX..",
        "...XWX.....XWX..",
        "..XSWX....XXPWX.",
        "..XWWXXXXXXWPWX.",
        ".XWWWWWWWWWWWWSX",
        ".XWWXXWWWWXXWWSX",
        ".XWWXXWWWWXXWWXX",
        "..XWWWWXXWWWWX..",
        "..XSWWWXXWWWSX..",
        "...XXXXRRPXXX...",
        "..XWWWWWWWWWWX..",
        ".XSWWWWWWWWWWSXX",
        ".XWWWWWWWWWWWWXX",
        ".XWWXXWWXXWWXWWX",
        ".XWWXXWWXXWWXWWX",
        ".XXXXXXXXXXXXXX.",
    ],
]

ALL_DOGS = [
    ("d1_tan_dog", "D1: Tan Dog (Reference f3)", D1_FRAMES),
    ("d2_white_dog", "D2: White Dog (Reference f3)", D2_FRAMES),
]

def build():
    for name, title, frames in ALL_DOGS:
        assert len(frames) == 4, f"{name} must have 4 frames"
        for f_idx, f in enumerate(frames):
            assert len(f) == 16, f"{name} F{f_idx} has {len(f)} rows"
            for r_idx, row in enumerate(f):
                assert len(row) == 16, f"{name} F{f_idx} R{r_idx} len={len(row)}: {row}"
    print("[+] Grid validation passed!")

    sheet = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    for row_idx, (_, _, frames) in enumerate(ALL_DOGS):
        fy = row_idx * 16
        for col_idx, frame in enumerate(frames):
            fx = col_idx * 16
            for y, line in enumerate(frame):
                for x, char in enumerate(line):
                    idx = LEGEND.get(char, 0)
                    if idx > 0:
                        r, g, b = PAL_8BIT[idx]
                        sheet.putpixel((fx + x, fy + y), (r, g, b, 255))

    out_sheet = OUT_DIR / "dogs_4frame_16x16.png"
    sheet.save(out_sheet)
    print(f"[+] Saved: {out_sheet}")

    scale = 8
    w, h = 64 * scale, 32 * scale
    left_m, top_m = 200, 36
    preview = Image.new("RGBA", (left_m + w + 20, top_m + h + 20), (28, 30, 42, 255))
    draw = ImageDraw.Draw(preview)

    scaled_sheet = sheet.resize((w, h), Image.Resampling.NEAREST)
    preview.paste(scaled_sheet, (left_m, top_m), scaled_sheet)

    for i in range(5):
        gx = left_m + i * 16 * scale
        draw.line([(gx, top_m), (gx, top_m + h)], fill=(70, 75, 95, 200), width=1)
    for i in range(3):
        gy = top_m + i * 16 * scale
        draw.line([(left_m, gy), (left_m + w, gy)], fill=(70, 75, 95, 200), width=1)

    headers = ["F0: Stand / Sit", "F1: Bob / Step", "F2: Extension", "F3: Return (User Fave)"]
    for i, title in enumerate(headers):
        draw.text((left_m + i * 16 * scale + 12, 12), title, fill=(220, 230, 245, 255))

    for row_idx, (_, title, _) in enumerate(ALL_DOGS):
        ry = top_m + row_idx * 16 * scale + 8 * scale - 6
        draw.text((12, ry), title, fill=(255, 215, 80, 255))

    preview_path = OUT_DIR / "dogs_4frame_preview_v2.png"
    preview.save(preview_path)
    print(f"[+] Saved: {preview_path}")

    durations = [180, 180, 180, 180]
    for name, title, frames in ALL_DOGS:
        gif_frames = []
        for frame in frames:
            im = Image.new("P", (16, 16), 0)
            im.putpalette(PAL_FLAT)
            for y, line in enumerate(frame):
                for x, char in enumerate(line):
                    idx = LEGEND.get(char, 0)
                    im.putpixel((x, y), idx)
            im_scaled = im.resize((128, 128), Image.Resampling.NEAREST)
            gif_frames.append(im_scaled)

        gif_path = OUT_DIR / f"{name}_anim.gif"
        gif_frames[0].save(
            gif_path,
            save_all=True,
            append_images=gif_frames[1:],
            duration=durations,
            loop=0,
            disposal=2,
            transparency=0,
        )
        print(f"[+] Saved: {gif_path}")

if __name__ == "__main__":
    build()
