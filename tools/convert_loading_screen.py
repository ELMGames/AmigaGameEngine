#!/usr/bin/env python3
"""
tools/convert_loading_screen.py
--------------------------------
Converts a source PNG image into the Amiga 5-bitplane interleaved raw screen,
extracts the 32-color palette, and compresses it with ZX0 for the tape loading screen.

Outputs:
  - assets/graphics/title/template.pal (64 bytes: 32 colors in 12-bit $0RGB)
  - assets/graphics/title/template.zx0 (ZX0 compressed 5-bitplane interleaved raw: 320x200x5 = 40,000 bytes)

Usage:
  python tools/convert_loading_screen.py [input_image.png]
Default input:
  assets/graphics/title/loadingscreen.png
"""

import sys
import os
import subprocess
from pathlib import Path
from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent
TITLE_DIR = PROJECT_ROOT / "assets" / "graphics" / "title"
DEFAULT_INPUT = TITLE_DIR / "loadingscreen.png"
AMIGECONV = PROJECT_ROOT / "tools" / "amigeconv.exe"
ZX0_EXE = PROJECT_ROOT / "tools" / "zx0.exe"

W, H = 320, 200  # Amiga OCS lo-res standard screen dimensions


def convert_loading_screen(src_path: Path):
    if not src_path.exists():
        print(f"Error: Source image '{src_path}' not found!")
        sys.exit(1)

    print(f"[*] Processing Loading Screen: {src_path.name}")
    src = Image.open(src_path).convert("RGB")
    print(f"    Source resolution: {src.size[0]}x{src.size[1]}")

    # 1. Ensure exactly 320x200 canvas
    if src.size == (W, H):
        canvas = src
        print(f"    Native 320x200 resolution detected (no scaling needed)")
    else:
        scale = min(W / src.width, H / src.height)
        new_w = round(src.width * scale)
        new_h = round(src.height * scale)
        resized = src.resize((new_w, new_h), Image.Resampling.LANCZOS)
        canvas = Image.new("RGB", (W, H), (0, 0, 0))
        x_off = (W - new_w) // 2
        y_off = (H - new_h) // 2
        canvas.paste(resized, (x_off, y_off))
        print(f"    Scaled to {new_w}x{new_h}, centered at ({x_off}, {y_off}) in {W}x{H} canvas")

    # 2. Build 32-color Amiga OCS palette with Color 0 = Black ($000) and Color 31 = White ($FFF)
    # This prevents white highlights (teeth, eyes, letter glints) from falling on Color 0 (transparent border/bg)
    print("    Quantizing with Color 0 = Black ($000) and Color 31 = Pure White ($FFF)...")
    q30 = canvas.quantize(colors=30, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    raw_pal = q30.getpalette()[:30*3]
    c30 = [(raw_pal[i*3], raw_pal[i*3+1], raw_pal[i*3+2]) for i in range(30)]

    def to_amiga(rgb):
        r = round(rgb[0] * 15 / 255)
        g = round(rgb[1] * 15 / 255)
        b = round(rgb[2] * 15 / 255)
        return (r * 17, g * 17, b * 17)

    seen = set([(0, 0, 0), (255, 255, 255)])
    unique_mid = []
    for c in c30:
        ac = to_amiga(c)
        if ac not in seen:
            seen.add(ac)
            unique_mid.append(ac)

    # Ensure exactly 30 middle colors (pad with specular highlights or amber if needed)
    fallback_colors = [(255, 238, 136), (255, 204, 153), (17, 187, 238), (255, 153, 17)]
    for fb in fallback_colors:
        if len(unique_mid) >= 30:
            break
        afb = to_amiga(fb)
        if afb not in seen:
            seen.add(afb)
            unique_mid.append(afb)

    # Sort middle colors strictly by luminance ascending
    unique_mid.sort(key=lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2])

    # Construct final 32-color palette:
    # Index 0:  (0, 0, 0)       -> $0000 Black (COLOR00 border & backdrop)
    # Index 1..30: Mid tones sorted dark-to-bright
    # Index 31: (255, 255, 255) -> $0FFF Pure White (teeth, eyes, sparkles)
    pal_32 = [(0, 0, 0)] + unique_mid[:30] + [(255, 255, 255)]

    flat_pal = []
    for c in pal_32:
        flat_pal.extend(c)
    flat_pal.extend([0] * (256 * 3 - len(flat_pal)))

    # Create indexed 32-color image
    quantised = Image.new("P", (W, H))
    quantised.putpalette(flat_pal)

    for y in range(H):
        for x in range(W):
            r, g, b = canvas.getpixel((x, y))[:3]
            # Exact semantic assignments for critical extremes:
            if r > 240 and g > 240 and b > 230:
                quantised.putpixel((x, y), 31)   # Pure White
            elif max(r, g, b) < 16:
                quantised.putpixel((x, y), 0)    # Background Black
            else:
                best_d = 999999999
                best_i = 1
                for i in range(1, 32):
                    pr, pg, pb = pal_32[i]
                    # Perceptual weighted Euclidean distance
                    d = (r - pr)**2 * 2 + (g - pg)**2 * 4 + (b - pb)**2 * 3
                    if d < best_d:
                        best_d = d
                        best_i = i
                quantised.putpixel((x, y), best_i)

    intermediate_png = TITLE_DIR / "_temp_loading_32col.png"
    quantised.save(intermediate_png)
    print(f"    Indexed image generated with non-transparent white: {intermediate_png.name}")

    preview_path = TITLE_DIR / "loadingscreen_converted_preview.png"
    quantised.convert("RGB").save(preview_path)
    print(f"    Saved visual preview: {preview_path.name}")

    raw_path = TITLE_DIR / "template.raw"
    pal_path = TITLE_DIR / "template.pal"
    zx0_path = TITLE_DIR / "template.zx0"

    try:
        # 3. amigeconv: 5-bitplane interleaved raw
        print("    [1/3] Running amigeconv for 5-bitplane interleaved raw...")
        cmd_raw = [str(AMIGECONV), "-f", "bitplane", "-l", "-d", "5", str(intermediate_png), str(raw_path)]
        res_raw = subprocess.run(cmd_raw, capture_output=True, text=True)
        if res_raw.returncode != 0:
            print(f"Error in amigeconv (raw): {res_raw.stderr}")
            sys.exit(1)
        print(f"    Created: {raw_path.name} ({raw_path.stat().st_size} bytes - expected 40,000)")

        # 4. amigeconv: 32-color 12-bit palette
        print("    [2/3] Running amigeconv for 32-color pal4 palette...")
        cmd_pal = [str(AMIGECONV), "-f", "palette", "-p", "pal4", "-c", "32", str(intermediate_png), str(pal_path)]
        res_pal = subprocess.run(cmd_pal, capture_output=True, text=True)
        if res_pal.returncode != 0:
            print(f"Error in amigeconv (palette): {res_pal.stderr}")
            sys.exit(1)
        print(f"    Created: {pal_path.name} ({pal_path.stat().st_size} bytes - expected 64)")

        # 5. zx0 compression
        print("    [3/3] Running zx0 compressor...")
        cmd_zx0 = [str(ZX0_EXE), "-f", str(raw_path), str(zx0_path)]
        res_zx0 = subprocess.run(cmd_zx0, capture_output=True, text=True)
        if res_zx0.returncode != 0:
            print(f"Error in zx0: {res_zx0.stderr}")
            sys.exit(1)
        print(f"    Created: {zx0_path.name} ({zx0_path.stat().st_size} bytes)")

    finally:
        # Cleanup temporary files
        if intermediate_png.exists():
            intermediate_png.unlink()
        if raw_path.exists():
            raw_path.unlink()

    print("\n>>> Loading screen successfully converted and compressed for Amiga! <<<")


def main():
    input_file = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_INPUT
    convert_loading_screen(input_file)


if __name__ == "__main__":
    main()
