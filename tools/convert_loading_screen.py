"""
convert_loading_screen.py
--------------------------
Step 1 of the loading screen pipeline.

Resizes any PNG to 336x200, preserving the transparency layer so that
transparent pixels map to palette index 0 (the Amiga background colour,
set by the copper list). The remaining 31 palette slots are used for the
visible artwork.

On the Amiga there is no true per-pixel transparency in bitplane graphics.
Instead, colour index 0 is conventionally used as the "transparent" or
background colour — whatever the copper sets COLOR00 to will show through
those pixels. This script honours that convention:

    Transparent pixels (alpha < ALPHA_THRESHOLD) --> palette index 0
    Visible pixels                                --> palette indices 1-31

Output: loading_screen_32col.png  (palette-mode PNG for amigeconv)

Usage:
    python tools/convert_loading_screen.py [input.png] [output.png]

    Default input:  loading_screen.png  (project root)
    Default output: loading_screen_32col.png

Full pipeline (run from project root):
    python tools/convert_loading_screen.py
    .\\tools\\amigeconv.exe -f bitplane -l -d 5 loading_screen_32col.png assets/graphics/title/template.raw
    .\\tools\\amigeconv.exe -f palette -p pal4 -c 32 loading_screen_32col.png assets/graphics/title/template.pal
    Remove-Item assets/graphics/title/template.zx0 -ErrorAction SilentlyContinue
    .\\tools\\zx0.exe assets/graphics/title/template.raw assets/graphics/title/template.zx0
    .\\build.ps1 -ToolDir <path-to-vasm>

See LOADING_SCREEN_GUIDE.md for full details.
"""

import sys
import os
import warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)
from PIL import Image

# ---- CONFIG (edit these as needed) -----------------------------------------
INPUT_PNG       = sys.argv[1] if len(sys.argv) > 1 else "loading_screen.png"
OUTPUT_PNG      = sys.argv[2] if len(sys.argv) > 2 else "loading_screen_32col.png"
W, H            = 320, 200          # Amiga loading screen target size (320px standard lo-res)
ALPHA_THRESHOLD = 128               # pixels with alpha < this become index 0
DITHER          = Image.Dither.NONE # NONE = sharp edges; FLOYDSTEINBERG for photos
# Colour that palette index 0 will represent (shown for transparent pixels).
# On the Amiga this is overridden at runtime by the copper list's COLOR00.
# Set to the dominant background colour of your artwork for best preview.
INDEX0_COLOR    = (0, 0, 0)        # black = typical Amiga background default
# ----------------------------------------------------------------------------


def fit_to_canvas(src_rgba, w, h):
    """
    Scale src to fit within (w x h), maintaining aspect ratio.
    Returns an RGBA image of exactly (w, h) with transparent padding.
    """
    scale = min(w / src_rgba.width, h / src_rgba.height)
    new_w = round(src_rgba.width  * scale)
    new_h = round(src_rgba.height * scale)
    resized = src_rgba.resize((new_w, new_h), Image.LANCZOS)
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))   # fully transparent
    x_off = (w - new_w) // 2
    y_off = (h - new_h) // 2
    canvas.paste(resized, (x_off, y_off))
    print(f"Scaled {src_rgba.size} -> {new_w}x{new_h}, "
          f"offset ({x_off}, {y_off}) in {w}x{h} canvas")
    return canvas


def quantise_preserving_transparency(rgba_img, max_colors=32,
                                     alpha_threshold=128, dither=Image.Dither.NONE):
    """
    Quantise an RGBA image to at most max_colors palette entries.

    Palette index 0 is reserved for transparent pixels.
    Visible pixels are quantised to indices 1..(max_colors-1).

    Returns a palette-mode ('P') Image where index 0 = transparent.
    """
    # Split into alpha mask and visible-pixel RGB
    r, g, b, a = rgba_img.split()
    alpha_data = list(a.getdata())

    # Build an RGB image containing only the visible pixels,
    # replacing transparent areas with INDEX0_COLOR so they don't
    # pollute the palette.
    visible_rgb = Image.new("RGB", rgba_img.size, INDEX0_COLOR)
    visible_rgb.paste(rgba_img.convert("RGB"),
                      mask=a.point(lambda v: 255 if v >= alpha_threshold else 0))

    # Quantise to (max_colors - 1) colours, leaving slot 0 free.
    n_visible_colors = max_colors - 1
    quantised = visible_rgb.quantize(
        colors=n_visible_colors,
        method=Image.Quantize.MEDIANCUT,
        dither=dither
    )

    # Shift all existing palette indices up by 1 to free index 0.
    pixel_data = [idx + 1 for idx in quantised.getdata()]

    # Mark transparent pixels as index 0.
    for i, alpha in enumerate(alpha_data):
        if alpha < alpha_threshold:
            pixel_data[i] = 0

    # Build the new palette: index 0 = INDEX0_COLOR, indices 1..N = quantised.
    old_pal = quantised.getpalette()          # 256*3 flat RGB list
    new_pal = list(INDEX0_COLOR) + old_pal[:n_visible_colors * 3]
    # Pad to 256 entries (required by Pillow palette mode)
    new_pal += [0] * (256 * 3 - len(new_pal))

    # Assemble the final palette-mode image.
    out = Image.new("P", rgba_img.size)
    out.putpalette(new_pal)
    out.putdata(pixel_data)
    return out


def main():
    if not os.path.exists(INPUT_PNG):
        print(f"ERROR: Input file not found: {INPUT_PNG}")
        sys.exit(1)

    print(f"Input:   {INPUT_PNG}")
    src = Image.open(INPUT_PNG).convert("RGBA")
    print(f"Source:  {src.size[0]}x{src.size[1]}  mode=RGBA")

    # Check if source actually has any transparency
    alpha_vals = set(src.split()[3].getdata())
    has_transparency = min(alpha_vals) < ALPHA_THRESHOLD
    print(f"Has transparency: {has_transparency}  "
          f"(alpha range: {min(alpha_vals)}-{max(alpha_vals)}, "
          f"threshold={ALPHA_THRESHOLD})")

    # Fit to 336x200 canvas, maintaining RGBA (transparent padding)
    canvas = fit_to_canvas(src, W, H)

    # Quantise to 32 colours, preserving transparency as index 0
    quantised = quantise_preserving_transparency(
        canvas,
        max_colors=32,
        alpha_threshold=ALPHA_THRESHOLD,
        dither=DITHER
    )

    # Report
    used_indices = set(quantised.getdata())
    transparent_pixels = sum(1 for i in quantised.getdata() if i == 0)
    print(f"Palette indices used: {len(used_indices)}/32  "
          f"(index 0 = {transparent_pixels} transparent pixels)")
    print(f"  Index 0: transparent / background  -> {INDEX0_COLOR}")
    pal = quantised.getpalette()
    for idx in sorted(used_indices):
        if idx == 0:
            continue
        r, g, b = pal[idx*3], pal[idx*3+1], pal[idx*3+2]
        print(f"  Index {idx:2d}: RGB({r:3d},{g:3d},{b:3d})")

    quantised.save(OUTPUT_PNG)
    print(f"\nOutput:  {OUTPUT_PNG}")
    print()
    print("Next steps (run from project root):")
    print(f"  .\\tools\\amigeconv.exe -f bitplane -l -d 5 {OUTPUT_PNG} assets/graphics/title/template.raw")
    print(f"  .\\tools\\amigeconv.exe -f palette -p pal4 -c 32 {OUTPUT_PNG} assets/graphics/title/template.pal")
    print( "  Remove-Item assets/graphics/title/template.zx0 -ErrorAction SilentlyContinue")
    print( "  .\\tools\\zx0.exe assets/graphics/title/template.raw assets/graphics/title/template.zx0")


if __name__ == "__main__":
    main()
