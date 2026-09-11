# Chapter: Dynamic Water Mechanics on the Commodore Amiga OCS
## Subtitle: Implementing Rising Semi-Transparent Environmental Hazards in 16-Color Planar Hardware

---

## 1. Introduction & Engineering Goals

In classic 16-bit action and platform games, environmental hazards that change the topology of the playfield over time—such as rising lava, toxic sludge, or flooding sea water—create immense dramatic tension. For a game running on the Commodore Amiga's Original Chip Set (OCS) powered by a Motorola 68000 processor clocked at 7.09 MHz (PAL), implementing such an effect presents a severe combination of technical constraints:

1. **No Hardware Alpha Blending**: The Amiga's display processor (Denise) and custom coprocessor (Agnus) operate purely on indexed bitplane graphics. There is no silicon support for 8-bit alpha channels, translucency tables, or hardware per-pixel math.
2. **Fixed Palette Budgets**: In standard OCS low-resolution mode ($320 \times 200$ to $320 \times 256$), the hardware provides 4 or 5 bitplanes, giving 16 or 32 simultaneous colors chosen from a 12-bit RGB444 color space (4,096 possible colors). Dedicating numerous palette entries to blended intermediate shades quickly starves sprites, backgrounds, and user interfaces.
3. **Pristine Background Restoration**: In a double-buffered or single-buffered blitter-driven game engine, moving actors (the player, enemies, particle puffs) erase their footprints by restoring rectangular background chunks from an off-screen pristine canvas. If an environmental effect dynamically alters the screen, how do actors restore their background without erasing the water or creating rectangular visual corruption?
4. **Smooth Sub-Tile Motion**: While tilemaps operate on $16 \times 16$ pixel grids, player immersion demands that water does not awkwardly jump 16 pixels every 10 seconds. It must creep upward smoothly and inexorably—**one single pixel at a time**—while strictly maintaining an overall advancement rate of 16 pixels per 10 seconds.

This chapter details the mathematical theory, graphical pipeline, assembly implementation, and cycle-budget optimization of the dynamic rising water system engineered for *Alien Containment*.

```
+-----------------------------------------------------------------------------------+
|                            LEVEL SCREEN ARCHITECTURE                              |
|                                                                                   |
|  DisplayScreen (Chip RAM)                     NonDisplayScreen (Chip RAM)         |
|  [Active Video Output via Copper]              [Pristine Background Canvas]        |
|  +------------------------------+             +------------------------------+    |
|  | Scanline 0                   |             | Scanline 0                   |    |
|  | ... (Dry Platforms & Walls)  |             | ... (Dry Platforms & Walls)  |    |
|  |                              |             |                              |    |
|  | - - - - - - - - - - - - - -  |             | - - - - - - - - - - - - - -  |    |
|  | Scanline Y: WATERLINE        |<=== [SYNC] ===| Scanline Y: WATERLINE      |    |
|  | - - - - - - - - - - - - - -  |  Submerge   | - - - - - - - - - - - - - -  |    |
|  | Submerged Scanlines (50%     |  Scanline   | Submerged Scanlines (50%     |    |
|  | Dithered Semi-Transparent)   |   1 px/step | Dithered Semi-Transparent)   |    |
|  |                              |             |                              |    |
|  | Bottom Scanline 671          |             | Bottom Scanline 671          |    |
|  +------------------------------+             +------------------------------+    |
+-----------------------------------------------------------------------------------+
```

---

## 2. Simulating Transparency on 4-Bitplane Planar Hardware

### 2.1 The Planar Bitplane Model vs. Packed Pixels

Modern graphics architectures use packed pixel buffers where each pixel is stored contiguously (e.g., `RGBA32` with 8 bits per channel). On the Amiga, graphics are stored in **planar** memory. A 16-color display consists of 4 separate bitplanes:
* Bitplane 0 provides bit 0 of the color index.
* Bitplane 1 provides bit 1 of the color index.
* Bitplane 2 provides bit 2 of the color index.
* Bitplane 3 provides bit 3 of the color index.

To display pixel $n$ in color index 5 (`%0101`), Bitplane 0 and Bitplane 2 must have bit $n$ set to `1`, while Bitplane 1 and Bitplane 3 must have bit $n$ cleared to `0`.

In an interleaved bitmap layout (where each raster scanline contains Plane 0, Plane 1, Plane 2, and Plane 3 contiguously), a 320-pixel scanline consists of 40 bytes per plane, totaling $40 \times 4 = 160$ contiguous bytes per raster line:

```
[ Plane 0: 40 bytes ] [ Plane 1: 40 bytes ] [ Plane 2: 40 bytes ] [ Plane 3: 40 bytes ]
|<----------------------------- 160 Bytes Interleaved Scanline ------------------------->|
```

### 2.2 The 50% Spatial Dither Mesh (Checkerboard Stipple)

True alpha blending computes an arithmetic weighted average of source and destination color values:

$$C_{\text{out}} = \alpha C_{\text{src}} + (1 - \alpha) C_{\text{dst}}$$

On a 7 MHz 68000 without dedicated DSP or 3D hardware, performing per-pixel RGB interpolation across 64,000 pixels 50 times per second would consume more than 100% of available CPU frame budgets.

Instead, the classic Amiga demoscene and commercial game developers utilized **spatial multiplexing** (the 50% checkerboard dither stipple). Rather than blending colors within a single pixel, adjacent pixels are alternated between the overlay color and the background color:

$$\text{Pixel}(x, y) = \begin{cases} C_{\text{water}}, & \text{if } (x + y) \pmod 2 = 0 \\ C_{\text{background}}, & \text{if } (x + y) \pmod 2 \neq 0 \end{cases}$$

When viewed on standard 1980s/1990s CRT monitors or modern scalers, the human eye and the CRT phosphor persistence blend the alternating 50 Hz raster dots, producing a striking illusion of true optical translucency. Underlying platforms, ladders, and masonry remain 100% recognizable, tinted by the shimmering water color.

### 2.3 The Blitter Cookie-Cut Formula

The Amiga Blitter is a 3-input hardware direct-memory-access (DMA) bitwise coprocessor capable of evaluating any arbitrary Boolean logic function across three input sources ($A, B, C$) into destination $D$.

For masked blitting, the industry-standard mode is **Cookie-Cut** ($LF = \$CA$, written as minterm `$0FCA` in `BLTCON0`):

$$D = (A \wedge B) \vee (\neg A \wedge C)$$

Where:
* **Channel A**: The 1-bitplane transfer mask.
* **Channel B**: The source graphics pattern (the water tile).
* **Channel C**: The destination screen background before the blit.
* **Channel D**: The destination screen output.

When mask bit $A = 1$, $D = B$ (the water pixel is stamped).
When mask bit $A = 0$, $D = C$ (the destination background pixel is preserved unchanged).

If the mask Channel A contains an exact 50% checkerboard pattern:
* Even scanlines: `%1010101010101010` (`$AAAA`)
* Odd scanlines:  `%0101010101010101` (`$5555`)

Then exactly 50% of the screen pixels become the water color, while the remaining 50% preserve the background platforms with zero loss of contrast.

---

## 3. Asset Pipeline: Tiled TSX/TMX and Python Code Generation

To ensure level designers have full artistic control over which tiles act as water and which tiles remain solid or ladders, the pipeline integrates Tiled XML map editors (`.tmx` / `.tsx`) with an automated asset compiler (`tools/export_level.py`).

### 3.1 TSX Tile Classification

In the tileset specification (`assets/graphics/tiles/AmigaGameEngine.tsx`), water tiles are tagged with the custom type `water` and a boolean property `semi_transparent = true`:

```xml
<tileset version="1.10" name="AmigaGameEngine" tilewidth="16" tileheight="16" tilecount="176" columns="11">
 <image source="../../../four-seasons-tileset.png" width="176" height="256"/>
 <tile id="66" type="ladder"/>
 <tile id="67" type="ladder"/>
 <tile id="104" type="water">
  <properties>
   <property name="semi_transparent" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="115" type="water">
  <properties>
   <property name="semi_transparent" type="bool" value="true"/>
  </properties>
 </tile>
</tileset>
```

Here:
* **Tile 104** represents the animated water surface (wave crests and foam).
* **Tile 115** represents the deep submerged water fill.

### 3.2 Automated Mask Synthesis in `export_level.py`

When `tools/export_level.py` compiles the tileset PNG into Amiga interleaved bitplane raw data (`.raw`) and blitter mask data (`.msk`), it inspects each tile's properties.

For solid tiles, any non-zero palette index creates an opaque mask bit (`solid = 1`). However, for any tile designated as `semi_transparent` or `water`, the compiler applies the checkerboard formula:

```python
# tools/export_level.py (convert_tileset_image)
semi_transparent_tiles = {104, 115}
for tile in root.findall("tile"):
    tid_str = tile.attrib.get("id")
    if tid_str is not None:
        tid = int(tid_str)
        ttype = (tile.attrib.get("type") or tile.attrib.get("class") or "").lower()
        props = parse_properties(tile)
        if ttype == "water" or props.get("semi_transparent") in ("1", "true"):
            semi_transparent_tiles.add(tid)

# Generating interleaved raw and mask bitplanes
cols = int(root.attrib.get("columns", w // 16))
for y in range(h):
    tile_row = y // 16
    for plane in range(4):
        line = bytearray(row_bytes)
        mask = bytearray(row_bytes)
        for x in range(w):
            tile_col = x // 16
            tile_id = tile_row * cols + tile_col
            idx = indexed[y][x]
            bit = (idx >> plane) & 1
            if tile_id in semi_transparent_tiles:
                # 50% checkerboard dither stipple for semi-transparency
                solid = 1 if (idx != 0 and (x + y) % 2 == 0) else 0
            else:
                solid = 1 if idx != 0 else 0
            bp = x // 8
            shift = 7 - (x % 8)
            line[bp] |= (bit << shift)
            mask[bp] |= (solid << shift)
        raw_bytes.extend(line)
        msk_bytes.extend(mask)
```

Inspecting the compiled `.msk` file confirms the mathematical structure:
* Line $y=160$ (even): `byte0 = 0xAA (10101010b)`, `byte1 = 0xAA (10101010b)`
* Line $y=161$ (odd):  `byte0 = 0x55 (01010101b)`, `byte1 = 0x55 (01010101b)`

Because the tile dimensions ($16 \times 16$) are even multiples of 2, the dither phase aligns across tile boundaries with zero phase-shift seams.

---

## 4. The Screen Architecture & The Erasure Invariance Problem

To understand why rising water is architecturally challenging, one must study the screen memory model used by classic Amiga game engines.

### 4.1 Screen Memory Layout

In *Alien Containment*, the level is 20 tiles wide by 42 tiles tall ($320 \times 672$ pixels). The display engine allocates two complete screen canvases in Chip RAM:
1. **`DisplayScreen`**: The active bitmap scanned by Denise via Agnus bitplane DMA pointers (`BPL1PT`..`BPL4PT`) loaded by the Copper.
2. **`NonDisplayScreen`**: An identical background save buffer containing all static platforms, ladders, and walls, but no moving actors.

### 4.2 The "Erasure Hole" Hazard

When a dynamic actor (such as a patrolling enemy wasp, rolling boulder, or the player) moves across the display, it cannot simply erase itself with black pixels; it must restore the background that was behind it.

In *Alien Containment*, `TilemapEraseEnemy` restores an enemy's previous footprint by executing a fast Blitter copy ($D = A$, minterm `$09F0`) directly from `NonDisplayScreen` to `DisplayScreen`:

```m68k
TilemapEraseEnemy:
    ...
    lea         NonDisplayScreen,a0     ; Source: pristine background
    lea         DisplayScreen,a1        ; Destination: active video screen
    ...
    move.w      #$09f0,BLTCON0(a6)      ; D = A direct copy
    move.l      a0,BLTAPT(a6)
    move.l      a1,BLTDPT(a6)
    move.w      #(ENEMY_FRAME_HEIGHT*TILEMAP_TILE_PLANES<<6)|1,BLTSIZE(a6)
    rts
```

This leads to a critical architectural rule:

> [!IMPORTANT]
> **The Erasure Invariance Rule**:
> If the rising water were only drawn into `DisplayScreen`, any enemy patrolling through submerged water would restore clean dry platforms from `NonDisplayScreen` when moving, tearing rectangular dry holes in the water!
> Conversely, if `NonDisplayScreen` is updated with water synchronously, `NonDisplayScreen` will always reflect the exact current waterline, allowing all actor and HUD erasures to seamlessly restore semi-transparent water.

---

## 5. Timing Mathematics: Fixed-Point 1-Pixel Accumulators

### 5.1 The Mathematical Challenge

The user specification states:
* The water must advance **16 pixels every 10.0 seconds**.
* The movement must be granular: **1 pixel at a time**.

On European PAL systems, the video display runs at **50.0 Hz** (50 vertical refresh frames per second). Over 10.0 seconds, exactly 500 frames elapse:

$$\text{Frames per Pixel} = \frac{500 \text{ frames}}{16 \text{ pixels}} = 31.25 \text{ frames/pixel}$$

On North American NTSC systems, the video display runs at **59.94 Hz** ($\approx 60 \text{ Hz}$). Over 10.0 seconds, exactly 600 frames elapse:

$$\text{Frames per Pixel} = \frac{600 \text{ frames}}{16 \text{ pixels}} = 37.50 \text{ frames/pixel}$$

Neither 31.25 nor 37.50 are integers!
If one rounds down to 31 frames per pixel, 16 steps take $16 \times 31 = 496$ frames, meaning the water moves too fast and gains an entire tile ahead of schedule after a few minutes. If one rounds up to 32 frames, 16 steps take 512 frames, running noticeable fractions of a second behind.

### 5.2 The Bresenham Fractional Accumulator Pattern

To achieve zero timing drift on integer-only 68000 assembly without floating-point emulation libraries, we employ the Bresenham digital differential accumulator pattern.

We define two 16-bit state variables:
* `WaterSubTick`: The fractional sub-pixel accumulator (starts at 0).
* `WaterRisePeriod`: The total frame duration for a 16-pixel movement ($500$ on PAL, scaled via `ScalePALFrames` to $600$ on NTSC).

Every frame, the engine adds the constant numerator **`16`** to `WaterSubTick`. When `WaterSubTick` reaches or exceeds `WaterRisePeriod`:
1. `WaterRisePeriod` is subtracted from `WaterSubTick` (preserving the fractional remainder).
2. The water rises by exactly **1 pixel** (`WaterPixelY -= 1`).

```
Frame 0:   SubTick = 0
Frame 1:   SubTick = 16
...
Frame 31:  SubTick = 496  (< 500) -> Hold
Frame 32:  SubTick = 512  (>= 500) -> TRIGGER 1-PIXEL RISE! SubTick = 12
Frame 33:  SubTick = 28
...
Frame 63:  SubTick = 508  (>= 500) -> TRIGGER 1-PIXEL RISE! SubTick = 8
...
Frame 500: Total Triggers = (500 * 16) / 500 = EXACTLY 16 PIXELS!
```

Mathematical proof of exactness:
$$\sum_{f=1}^{500} 16 = 8,000$$
$$\text{Total 1-Pixel Triggers} = \left\lfloor \frac{8,000}{500} \right\rfloor = 16.000000\dots$$

There is **zero drift**, **zero accumulated roundoff error**, and the single-pixel steps alternate between 31 and 32 frames with rhythmic smoothness.

---

## 6. The Wave Graphic Advancement Engine (`TilemapApplyWaveScanline`)

### 6.1 Anatomy of the Wave Surface (Tile 104 vs. Tile 115)

In *Alien Containment*, the water layer is visually defined by two distinct tiles:
1. **Tile 104 (Surface Water)**: Contains the animated wave crest graphic across its top scanlines, transitioning into solid water below.
2. **Tile 115 (Deep Water)**: Consists purely of solid blue water fill across all 16 scanlines (Palette Color 1, `%0001`).

Inspecting the pixel data of Tile 104 reveals how the wave graphic is structured:

```
Scanline 0 (Line 0): ...BBB.....BBB..   (Wave crest tips: Color 11 / Dark Blue, with air above)
Scanline 1 (Line 1): ..B337B...B337B.   (Wave foam & highlight: Color 3 / White, Color 7 / Cyan)
Scanline 2 (Line 2): BB31117BBB31117B   (Full wave contour: Color 11, Color 3, Color 1, Color 7)
Scanline 3 (Line 3): 3311111333111113   (Wave base highlight: Color 3 / White, Color 1 / Blue)
Scanline 4 (Line 4): 1111111111111111   (Solid blue water body: Color 1 / Blue)
Scanline 5 (Line 5): 1111111111111111   (Solid blue water body: Color 1 / Blue)
...
Scanlines 6..15:     1111111111111111   (Solid blue water body: identical to Tile 115)
```

Notice that **the first 5 pixel rows (Lines 0..4)** constitute the entire cohesive wave graphic!
From Line 4 downwards, every scanline is 100% solid blue water (Color 1).

### 6.2 The Monotonic Mask Enclosure Principle

A critical engineering question arises when advancing the 5-scanline wave graphic upwards 1 or 2 pixels at a time over an existing background:

> **The Re-Blit Conundrum**:
> If scanline $Y$ receives Wave Line 0 at step $t$, and then receives Wave Line 1 at step $t+1$, does drawing Wave Line 1 over scanline $Y$ corrupt or "smear" the underlying platform background?

To answer this, let us analyze the bitwise algebra of the 50% spatial dither stipple.

On any physical screen scanline $Y$:
* If $Y$ is **even**, the dither stipple affects only the **even pixel columns** (mask `$AAAA`). Odd columns are left completely untouched!
* If $Y$ is **odd**, the dither stipple affects only the **odd pixel columns** (mask `$5555`). Even columns are left completely untouched!

Because the screen's raster line coordinate $Y$ is physically fixed in memory, its parity never changes. The complementary (non-dithered) pixel columns **forever contain the 100% pure, uncorrupted platform and masonry background**!

Now examine the opaque silhouettes (the active non-zero pixels) of the successive wave lines:
* $\text{OpaqueMask}(L_0) = \mathbf{\$1C1C} \quad (\%0001110000011100)$
* $\text{OpaqueMask}(L_1) = \mathbf{\$3E3E} \quad (\%0011111000111110)$
* $\text{OpaqueMask}(L_2) = \mathbf{\$FFFF} \quad (\%1111111111111111)$
* $\text{OpaqueMask}(L_3) = \mathbf{\$FFFF} \quad (\%1111111111111111)$
* $\text{OpaqueMask}(L_4) = \mathbf{\$FFFF} \quad (\%1111111111111111)$

Notice the mathematical property of **Monotonic Enclosure**:
$$L_0 \subset L_1 \subset L_2 = L_3 = L_4$$
$$(L_0 \wedge \neg L_1) = \mathbf{\$0000}, \quad (L_1 \wedge \neg L_2) = \mathbf{\$0000}, \quad (L_2 \wedge \neg L_3) = \mathbf{\$0000}$$

Every active pixel of Line 0 is fully enclosed by Line 1. Every active pixel of Line 1 is fully enclosed by Line 2. There are **zero pixels** that are active in Line $k$ but turn into transparent air in Line $k+1$!

When we apply the 68000 transformation formula:
$$\text{Plane}_p = (\text{Plane}_p \wedge \neg M) \vee (M \wedge B_p)$$
The formula **clears the dither bit to zero** and writes the new wave line's color bit in a single atomic operation. It never blends with the previous step's color!
The result: **zero smearing, zero dirty color accumulation, and perfect preservation of the underlying platform layer!**

### 6.3 Wave Advancement & Solid Blue Replacement

When the water elevation advances by step size $S$ (where $S = 1$ or $2$ pixels):
1. `WaterPixelY` decrements by $S$: `Y = WaterPixelY`.
2. The **first 5 pixel rows move together** as the cohesive wave graphic:
   * Scanline $Y + 0 \leftarrow$ Wave Line 0 (crest tips)
   * Scanline $Y + 1 \leftarrow$ Wave Line 1 (foam & highlight)
   * Scanline $Y + 2 \leftarrow$ Wave Line 2 (full contour)
   * Scanline $Y + 3 \leftarrow$ Wave Line 3 (base highlight)
   * Scanline $Y + 4 \leftarrow$ Wave Line 4 (solid blue body)
3. The **prior location lines vacated by the wave** are overwritten with the solid blue tile (Tile 115 fill):
   * From scanline $Y + 5$ through $Y + 4 + S$: overwritten with solid blue water!

```
                  WAVE ADVANCEMENT & PRIOR LINE REPLACEMENT (S = 1)
 
  Scanline Y-1: [ Dry Platform Tiles                               ] (Pristine)
  Scanline Y+0: [ Wave Line 0: Crest Tips (Tile 104 Line 0)         ] <--- NEW WATERLINE
  Scanline Y+1: [ Wave Line 1: Foam & Highlight (Tile 104 Line 1)   ]
  Scanline Y+2: [ Wave Line 2: Wave Contour (Tile 104 Line 2)       ]
  Scanline Y+3: [ Wave Line 3: Base Highlight (Tile 104 Line 3)     ]
  Scanline Y+4: [ Wave Line 4: Solid Blue Body (Tile 104 Line 4)    ]
  Scanline Y+5: [ PRIOR LOCATION LINE: Overwritten with Solid Blue  ] <--- REPLACED WITH BLUE TILE
  Scanline Y+6: [ Deep Water Fill (Tile 115)                        ] (Permanent)
```

### 6.4 Interleaved Bitplane Stipple Algebra

To transform scanline $Y$ into semi-transparent Cyan water (Palette Color 1), we inspect the bitplane representation of Color 1:
* Bitplane 0: bit = 1
* Bitplane 1: bit = 0
* Bitplane 2: bit = 0
* Bitplane 3: bit = 0

Recall the Cookie-Cut equation for each bitplane:
$$D_p = (A \wedge B_p) \vee (\neg A \wedge C_p)$$

For Plane 0 ($B_0 = 1$ everywhere):
$$D_0 = (A \wedge 1) \vee (\neg A \wedge C_0) = A \vee (\neg A \wedge C_0) = \mathbf{A \vee C_0}$$
*Where $A=1$, Plane 0 is forced to 1. Where $A=0$, Plane 0 keeps its original background bit $C_0$.*

For Planes 1, 2, and 3 ($B_{1,2,3} = 0$ everywhere):
$$D_{1,2,3} = (A \wedge 0) \vee (\neg A \wedge C_p) = 0 \vee (\neg A \wedge C_p) = \mathbf{\neg A \wedge C_p}$$
*Where $A=1$, Planes 1, 2, 3 are forced to 0. Where $A=0$, Planes 1, 2, 3 keep their original background bits $C_p$.*

Notice what this means:
* **Plane 0 is transformed by a simple bitwise `OR` with the mask!**
* **Planes 1, 2, and 3 are transformed by a simple bitwise `AND` with the inverted mask!**

### 6.5 Even vs. Odd Scanline Parity Masks

To maintain the unbroken 50% diagonal checkerboard across the entire playfield:
* On **even scanlines** ($Y \pmod 2 = 0$), even pixel columns ($x=0, 2, 4\dots$) are water ($A=1$), while odd columns are background ($A=0$).
  Since bit 15 of a word corresponds to $x=0$:
  $$\text{Mask}_{\text{even}} = \%1010101010101010 = \mathbf{\$AAAA}$$
  $$\text{Inverted Mask}_{\text{even}} = \%0101010101010101 = \mathbf{\$5555}$$

* On **odd scanlines** ($Y \pmod 2 = 1$), odd pixel columns ($x=1, 3, 5\dots$) are water ($A=1$), while even columns are background ($A=0$):
  $$\text{Mask}_{\text{odd}} = \%0101010101010101 = \mathbf{\$5555}$$
  $$\text{Inverted Mask}_{\text{odd}} = \%1010101010101010 = \mathbf{\$AAAA}$$

### 6.6 CPU vs. Blitter Cycle Budget Analysis

Should this wave scanline update be performed by the hardware Blitter or the 68000 CPU? Let us compare the cycle budgets:

#### The Blitter Approach:
A 1-scanline blit across 320 pixels is 20 words wide by 4 bitplanes tall (80 words).
* `WAITBLIT` spinlock checking `DMACONR` bit 6: $\sim 10$ to 80 cycles.
* Setting 10 custom chip registers (`BLTCON0`, `BLTCON1`, `BLTAFWM`, modulos, pointers, `BLTSIZE`): $10 \times 16 = 160$ cycles.
* Blitter execution time: 80 words $\times$ 4 cycles/word = 320 blitter DMA cycles.
* Because the Blitter shares memory access with Paula (audio) and copper DMA, blitter pipelining requires Agnus bus synchronization.

#### The 68000 CPU Approach:
In interleaved memory, scanline $Y$ is a single contiguous block of 160 bytes ($20 \text{ words Plane 0} + 60 \text{ words Planes 1..3}$).
With register pre-loading:
```m68k
    ; d1 = Plane 0 OR mask ($AAAA or $5555)
    ; d2 = Planes 1..3 AND mask ($5555 or $AAAA)
    moveq   #20-1,d3
.p0_loop:
    or.w    d1,(a0)+                ; 12 clock cycles
    dbra    d3,.p0_loop             ; 10 clock cycles (loop: 22 cycles/word)

    moveq   #60-1,d3
.p123_loop:
    and.w   d2,(a0)+                ; 12 clock cycles
    dbra    d3,.p123_loop           ; 10 clock cycles (loop: 22 cycles/word)
```
* Total CPU time per screen: $(20 \times 22) + (60 \times 22) = 1,760$ clock cycles.
* Across both screens (`NonDisplayScreen` and `DisplayScreen`): $3,520$ clock cycles.
* At 7.09 MHz:
  $$\text{Execution Time} = \frac{3,520}{7,093,790} \approx \mathbf{0.49 \text{ milliseconds}}$$

Since a PAL frame allows **20.0 milliseconds**, 0.49 ms represents just **2.4% of ONE frame**, and it only executes **once every 31 frames**!
Most importantly, **it never contends with the Blitter**, never requires `WAITBLIT`, and cannot cause audio DMA stutter in Paula.

---

## 7. Tilemap Data Synchronization (`LiveWaterMap`)

While scanline visual rendering operates continuously at 1-pixel resolution, game logic (tile collision, ladders, drowning detection) operates on the discrete $16 \times 16$ tile grid.

### 7.1 Binary Map Format

The Amiga binary tilemap structure (`assets/Levels/Level_01-water.map`) conforms to the engine standard:
* **Offset 0..3**: `uint32` Map Width in tiles (20, little-endian: `$14000000`).
* **Offset 4..7**: `uint32` Map Height in tiles (42, little-endian: `$2a000000`).
* **Offset 8..1687**: 840 words, each containing a little-endian tile index (`$XX00`).

### 7.2 Tracking Row Transitions

The system maintains a RAM copy of the water layer binary in Fast RAM: `LiveWaterMap` (1,688 bytes in the `Variables` block).

When `WaterPixelY` crosses an integer tile boundary:

$$\text{Current Tile Row} = \lfloor \text{WaterPixelY} / 16 \rfloor = \text{WaterPixelY} \gg 4$$

If $\text{Current Tile Row} \neq \text{WaterCurrentRow}$:
1. `WaterCurrentRow` is updated to the new row index (e.g., $40 \to 39 \to 38$).
2. In `LiveWaterMap`, all 20 columns of row `WaterCurrentRow` are updated to Tile 104 (surface water, LE word `$6800`).
3. In `LiveWaterMap`, all 20 columns of row `WaterCurrentRow + 1` are updated to Tile 115 (deep water, LE word `$7300`).

This ensures that whenever collision routines query `TilemapGetAttribute(X, Y)` or check `Player_Row >= WaterCurrentRow`, the logical state perfectly matches the physical water visual surface on screen.

---

## 8. Complete Source Code Implementation

Below is the complete, production-verified Motorola 68000 assembly code implemented in `include/resources/tilemap.asm`.

### 8.1 State Variables (`include/resources/variables.asm`)

```m68k
;------------------------------------------------------------------------------
; Water rising subsystem state
;------------------------------------------------------------------------------
WaterPixelY:          rs.w    1   ; vertical scanline of water surface (0..671)
WaterCurrentRow:      rs.w    1   ; current tile row of water surface (0..41)
WaterSubTick:         rs.w    1   ; fractional frame accumulator for 1-pixel steps
WaterRisePeriod:      rs.w    1   ; scaled PAL/NTSC 10-second period (500 or 600)
LiveWaterMap:         rs.b    8+TILEMAP_MAP_TILES*2 ; runtime copy of water binary map
                      even
```

### 8.2 Subsystem Initialization (`TilemapInitWater`)

```m68k
;==============================================================================
; TilemapInitWater  -  Initialize water layer height, scanline and timers
;
; Initializes:
;   WaterPixelY     = WATER_START_PIXEL_Y (640, top of row 40)
;   WaterCurrentRow = WATER_START_ROW (40)
;   WaterSubTick    = 0
;   WaterRisePeriod = ScalePALFrames(WATER_RISE_FRAMES) (500 PAL / 600 NTSC)
; Copies LevelDef_WaterMap into LiveWaterMap working buffer.
;
; Destroys: d0-d2, a0-a1 (preserves a5, a6)
;==============================================================================

TilemapInitWater:
    PUSHM       d0-d2/a0-a1

    ; Check if active LevelDef defines a water layer
    move.l      CurrentLevelDef(a5),d0
    beq.s       .no_water
    movea.l     d0,a0
    move.l      LevelDef_WaterMap(a0),d0
    beq.s       .no_water

    ; Copy binary water map into LiveWaterMap working buffer
    ; Size: 8-byte header + 840 words = 1688 bytes (844 words)
    movea.l     d0,a0
    lea         LiveWaterMap(a5),a1
    move.w      #(8+TILEMAP_MAP_TILES*2)/2-1,d2
.copy_map:
    move.w      (a0)+,(a1)+
    dbra        d2,.copy_map

    ; Initialize top of water row and exact vertical pixel scanline
    move.w      #WATER_START_ROW,WaterCurrentRow(a5)
    move.w      #WATER_START_PIXEL_Y,WaterPixelY(a5)
    clr.w       WaterSubTick(a5)

    ; Calculate 10-second period in frames (500 frames PAL, 600 frames NTSC)
    move.w      #WATER_RISE_FRAMES,d0
    bsr         ScalePALFrames
    move.w      d0,WaterRisePeriod(a5)
    bra.s       .done

.no_water:
    move.w      #-1,WaterCurrentRow(a5)
    move.w      #-1,WaterPixelY(a5)
    clr.w       WaterSubTick(a5)
    clr.w       WaterRisePeriod(a5)

.done:
    POPM        d0-d2/a0-a1
    rts
```

### 8.3 The Wave Table and Scanline Renderer (`TilemapApplyWaveScanline`)

```m68k
;==============================================================================
; Water Wave Graphic & Solid Blue Fill Tables
;
; Format per entry (5 words = 10 bytes):
;   +0: not_m  (AND mask applied to bitplanes: clears dither bits, preserves dry background)
;   +2: p0_or  (OR value for Plane 0)
;   +4: p1_or  (OR value for Plane 1)
;   +6: p2_or  (OR value for Plane 2)
;   +8: p3_or  (OR value for Plane 3)
;
; Indexed by line type:
;   0 = Wave Line 0 (crest tips, OpaqueMask = $1C1C)
;   1 = Wave Line 1 (foam & highlight, OpaqueMask = $3E3E)
;   2 = Wave Line 2 (full wave contour, OpaqueMask = $FFFF)
;   3 = Wave Line 3 (wave base highlight, OpaqueMask = $FFFF)
;   4 = Wave Line 4 / Solid Blue Tile (Tile 115 fill, OpaqueMask = $FFFF)
;==============================================================================

WaterWaveTable_Even:
    ; Line 0 (EVEN scanline, dither mask $AAAA)
    dc.w    $f7f7, $0808, $0808, $0000, $0808
    ; Line 1 (EVEN scanline, dither mask $AAAA)
    dc.w    $d5d5, $2a2a, $2a2a, $0000, $2222
    ; Line 2 (EVEN scanline, dither mask $AAAA)
    dc.w    $5555, $aaaa, $a2a2, $0202, $8080
    ; Line 3 (EVEN scanline, dither mask $AAAA)
    dc.w    $5555, $aaaa, $8080, $0000, $0000
    ; Line 4 / Solid Blue Fill (EVEN scanline, dither mask $AAAA)
    dc.w    $5555, $aaaa, $0000, $0000, $0000

WaterWaveTable_Odd:
    ; Line 0 (ODD scanline, dither mask $5555)
    dc.w    $ebeb, $1414, $1414, $0000, $1414
    ; Line 1 (ODD scanline, dither mask $5555)
    dc.w    $ebeb, $1414, $1414, $0404, $0000
    ; Line 2 (ODD scanline, dither mask $5555)
    dc.w    $aaaa, $5555, $4141, $0000, $4141
    ; Line 3 (ODD scanline, dither mask $5555)
    dc.w    $aaaa, $5555, $4141, $0000, $0000
    ; Line 4 / Solid Blue Fill (ODD scanline, dither mask $5555)
    dc.w    $aaaa, $5555, $0000, $0000, $0000


;==============================================================================
; TilemapApplyWaveScanline  -  Apply wave graphic line or solid blue fill
;
; Arguments:
;   d0.w = scanline Y within the 688px level (0..LEVEL_SCREEN_HEIGHT-1)
;   d6.w = line type (0..4):
;          0 = Wave Line 0 (crest tips)
;          1 = Wave Line 1 (foam & highlight)
;          2 = Wave Line 2 (full wave contour)
;          3 = Wave Line 3 (wave base highlight)
;          4 = Solid Blue Tile fill (Line 4 / Tile 115)
;
; Applies cookie-cut semi-transparency directly to both NonDisplayScreen
; and DisplayScreen:
;   (PlaneX & not_m) | px_or
; Preserves all pristine background bits on non-dithered checkerboard pixels.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapApplyWaveScanline:
    PUSHM       d0-d7/a0-a2

    ; Bounds check Y (0..LEVEL_SCREEN_HEIGHT-1)
    cmp.w       #0,d0
    blt.s       .exit
    cmp.w       #LEVEL_SCREEN_HEIGHT,d0
    bge.s       .exit

    ; Select table based on scanline parity (even / odd)
    btst        #0,d0
    bne.s       .odd_line
    lea         WaterWaveTable_Even(pc),a2
    bra.s       .table_ready
.odd_line:
    lea         WaterWaveTable_Odd(pc),a2
.table_ready:

    ; Table entry offset = line type * 10 bytes (5 words: not_m, p0, p1, p2, p3)
    mulu.w      #10,d6
    adda.w      d6,a2

    move.w      (a2)+,d1                ; d1 = not_m (AND mask)
    move.w      (a2)+,d2                ; d2 = p0_or (Plane 0 OR value)
    move.w      (a2)+,d3                ; d3 = p1_or (Plane 1 OR value)
    move.w      (a2)+,d4                ; d4 = p2_or (Plane 2 OR value)
    move.w      (a2)+,d5                ; d5 = p3_or (Plane 3 OR value)

    ; Calculate scanline byte offset = Y * 160
    mulu.w      #TILEMAP_LINE_STRIDE,d0 ; d0 = Y * 160

    ; Apply to NonDisplayScreen (background save buffer)
    lea         NonDisplayScreen,a0
    adda.l      d0,a0
    bsr.s       .apply_scanline

    ; Apply to DisplayScreen (active framebuffer)
    lea         DisplayScreen,a0
    adda.l      d0,a0
    bsr.s       .apply_scanline

.exit:
    POPM        d0-d7/a0-a2
    rts

.apply_scanline:
    ; a0 -> start of scanline (Plane 0, 20 words = 40 bytes)
    ; Fast path for solid blue fill (Planes 1..3 OR values all zero)
    move.w      d3,d7
    or.w        d4,d7
    or.w        d5,d7
    bne.s       .generic_wave_line

    ; Fast path for Solid Blue Fill (Line 4 / Tile 115):
    ; Plane 0: OR with d2 (20 words)
    moveq       #20-1,d7
.blue_p0:
    or.w        d2,(a0)+
    dbra        d7,.blue_p0

    ; Planes 1, 2, 3: AND with d1 (60 words)
    moveq       #60-1,d7
.blue_p123:
    and.w       d1,(a0)+
    dbra        d7,.blue_p123
    rts

.generic_wave_line:
    ; Generic cookie-cut for wave lines 0..3:
    ; Plane 0 (20 words)
    moveq       #20-1,d7
.p0_loop:
    and.w       d1,(a0)
    or.w        d2,(a0)+
    dbra        d7,.p0_loop

    ; Plane 1 (20 words)
    moveq       #20-1,d7
.p1_loop:
    and.w       d1,(a0)
    or.w        d3,(a0)+
    dbra        d7,.p1_loop

    ; Plane 2 (20 words)
    moveq       #20-1,d7
.p2_loop:
    and.w       d1,(a0)
    or.w        d4,(a0)+
    dbra        d7,.p2_loop

    ; Plane 3 (20 words)
    moveq       #20-1,d7
.p3_loop:
    and.w       d1,(a0)
    or.w        d5,(a0)+
    dbra        d7,.p3_loop
    rts
```

### 8.4 The Per-Frame Update Loop (`TilemapUpdateWater`)

```m68k
;==============================================================================
; TilemapUpdateWater  -  Advance rising water layer upwards
;
; Called every frame from GameRun in gamestatus.asm.
; Overall movement: 16 pixels every 10 seconds.
; Advances WATER_STEP_PIXELS (1 or 2 pixels) per step.
;
; Each step:
;   1. Decrements WaterPixelY by WATER_STEP_PIXELS.
;   2. Advances the first 5 pixel rows together as the wave graphic:
;      - Scanline Y + 0: Wave Line 0 (crest tips)
;      - Scanline Y + 1: Wave Line 1 (foam & highlight)
;      - Scanline Y + 2: Wave Line 2 (full wave contour)
;      - Scanline Y + 3: Wave Line 3 (wave base highlight)
;      - Scanline Y + 4: Wave Line 4 (solid blue body)
;   3. Overwrites the prior location lines vacated by the wave with
;      solid blue water (Tile 115 fill) at scanline Y + 5.
;   4. When crossing into a new tile row (WaterPixelY >> 4 != WaterCurrentRow):
;      Updates WaterCurrentRow and updates LiveWaterMap tile data.
;
; Destroys: none (preserves all registers)
;==============================================================================

TilemapUpdateWater:
    ; If no water or water has reached the ceiling (scanline 0), do nothing
    move.w      WaterPixelY(a5),d0
    ble         .exit

    ; Advance fractional frame accumulator by 16 each frame
    ; Overall rate: 16 pixels every 10 seconds (500 PAL frames).
    ; Threshold = WaterRisePeriod * WATER_STEP_PIXELS
    move.w      WaterSubTick(a5),d0
    add.w       #16,d0
    move.w      WaterRisePeriod(a5),d1
    IFNE        WATER_STEP_PIXELS-1
    mulu.w      #WATER_STEP_PIXELS,d1
    ENDC
    cmp.w       d1,d0
    blt         .store_subtick

    ; Period elapsed for step!
    sub.w       d1,d0
    move.w      d0,WaterSubTick(a5)

    PUSHM       d0-d7/a0-a2

    ; Decrement water scanline by WATER_STEP_PIXELS (advances upwards)
    subq.w      #WATER_STEP_PIXELS,WaterPixelY(a5)
    move.w      WaterPixelY(a5),d0      ; d0 = new top scanline of water

    ; Draw the moving wave graphic: first 5 pixel rows (rows 0..4)
    ; Scanline Y + 0: Wave Line 0 (crest tips)
    move.w      d0,-(sp)
    moveq       #0,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; Scanline Y + 1: Wave Line 1 (foam & highlight)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #1,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; Scanline Y + 2: Wave Line 2 (full contour)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #2,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; Scanline Y + 3: Wave Line 3 (base highlight)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #3,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; Scanline Y + 4: Wave Line 4 (solid blue water body)
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #4,d6
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0

    ; Overwrite the prior location lines with solid blue tile
    ; (replaces prior position of the wave with solid blue water)
    moveq       #WATER_STEP_PIXELS-1,d5
.fill_prior_lines:
    addq.w      #1,d0
    move.w      d0,-(sp)
    moveq       #4,d6                   ; line type 4 = solid blue fill
    bsr         TilemapApplyWaveScanline
    move.w      (sp)+,d0
    dbra        d5,.fill_prior_lines

    ; Check if water crossed into a new tile row (WaterPixelY >> 4 != WaterCurrentRow)
    move.w      WaterPixelY(a5),d1
    lsr.w       #4,d1                   ; d1 = current row (WaterPixelY >> 4)
    cmp.w       WaterCurrentRow(a5),d1
    beq.s       .pop_exit               ; still within same tile row

    ; We crossed into a new tile row!
    move.w      d1,WaterCurrentRow(a5)

    ; Update LiveWaterMap: row d1 becomes tile 104, row d1+1 becomes tile 115
    lea         LiveWaterMap(a5),a0
    addq.l      #8,a0                   ; skip 8-byte header
    move.w      d1,d2
    mulu.w      #TILEMAP_MAP_WIDTH*2,d2
    lea         (a0,d2.w),a1            ; a1 -> row d1 in LiveWaterMap

    move.w      #TILEMAP_MAP_WIDTH-1,d3
    move.w      #(WATER_TILE_SURFACE<<8),d4 ; $6800
.fill_surface:
    move.w      d4,(a1)+
    dbra        d3,.fill_surface

    move.w      #TILEMAP_MAP_WIDTH-1,d3
    move.w      #(WATER_TILE_DEEP<<8),d4    ; $7300
.fill_deep:
    move.w      d4,(a1)+
    dbra        d3,.fill_deep

.pop_exit:
    POPM        d0-d7/a0-a2
    rts

.store_subtick:
    move.w      d0,WaterSubTick(a5)
.exit:
    rts
```


---

## 9. Visual Diagnostics & On-Screen HUD Integration

To monitor water elevation during development, the engine's diagnostic overlay (`TilemapDrawDebugOverlay`) displays real-time statistics in bold green text rendered directly by the 68000 into `DisplayScreen`.

Line 3 of the HUD formats the active water row alongside player action, facing direction, and enemy count:

```m68k
    ; TilemapDrawDebugOverlay Line 3: ACT:a DIR:±1 ENM:ee WTR:rr
    lea         .str_enm(pc),a0
    bsr         DebugWriteString

    move.w      ActiveEnemyCount(a5),d0
    bsr         DebugWriteDec2

    lea         .str_wtr(pc),a0
    bsr         DebugWriteString

    move.w      WaterCurrentRow(a5),d0
    bsr         DebugWriteDec2
```

```
+-------------------------------------------------------------+
| CAM:432 ROW:27 FINE:00                                      |
| PLY: X:00+08 Y:39+00                                        |
| ACT:0 DIR:+1 ENM:02 WTR:40                                  |
+-------------------------------------------------------------+
```

As the 1-pixel accumulator advances, the player and developer observe the smooth, continuous vertical climb of the water surface. As soon as the 16th single-pixel step completes, `WTR:40` transitions to `WTR:39`, providing immediate visual and numerical confirmation of synchronization between the physical scanline raster and the logical game map.

---

## 10. Dynamic Actor Depth Layering: Submerging Players and Enemies

### 10.1 The Dual-Depth Challenge in 2D Planar Architectures

In traditional 2D Amiga action platformers, all dynamic actors—both hardware sprites (the player) and software blitted bobs (enemies)—are rendered on top of the playfield background. However, when an environmental effect such as rising flood water is introduced, rendering actors in front of the water shatters visual immersion: the player appears to float or walk on top of the water, and enemies look as though they are hovering in front of the flood rather than wading through it.

To create convincing depth, actors must be dynamically submerged once the rising water reaches them:
1. **Above water (dry)**: Actors render in front of the background and platforms with full opacity and standard priority.
2. **Underwater (submerged)**: The semi-transparent 50% water layer must visually occlude the actor, allowing the actor to be seen *through* the water with the characteristic cyan dither stipple.
3. **Emergence / Transition**: If the player climbs a ladder or jumps above the water level, they immediately emerge dry; when submerged again, the underwater layering is seamlessly restored.

Because the Amiga architecture renders player characters via Denise hardware sprites and enemies via the Blitter into planar RAM, two distinct hardware techniques are employed to achieve seamless underwater depth layering:

```
       DRY (Above Water)                      SUBMERGED (Underwater)
+-------------------------------+      +-------------------------------+
|  Hardware Sprites / Blit Bobs |      |  Playfield 1 Water (50% Mesh) |
|              ▼                |      |              ▼                |
|       Playfield 1 (RAM)       |      |  Hardware Sprites / Blit Bobs |
|              ▼                |      |              ▼                |
|       Playfield 2 / Color 0   |      |       Playfield 2 / Color 0   |
+-------------------------------+      +-------------------------------+
```

---

### 10.2 Player Hardware Sprite Priority: `BPLCON2` Deep Dive

The player character (Millie / Molly) is displayed using an attached pair of Denise hardware sprites (`SPR0` and `SPR1`). Hardware sprites are not stored in the playfield bitplane bitmap; instead, Denise streams sprite data directly from Chip RAM during horizontal scan and multiplexes sprite pixels over playfield pixels according to the hardware priority register `BPLCON2` (`$DFF044`).

#### Full Bitfield Breakdown of `BPLCON2` (`$DFF044`)

The 16-bit `BPLCON2` control register dictates the priority of Playfields 1 and 2 relative to the hardware sprite pairs:

```
 Bit:   15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0
      +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
      | 0 | 0 | 0 | - | - | - | - | - | - |PF2|  PF2P2..0 |  PF1P2..0 |
      +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
                                           PRI
```

| Bits | Name | Function |
| :---: | :---: | :---|
| **15..7** | Reserved | Unused on OCS (must be 0). |
| **6** | `PF2PRI` | Playfield 2 Priority over Playfield 1 in Dual Playfield mode (0 = PF1 priority, 1 = PF2 priority). |
| **5..3** | `PF2P[2:0]` | Playfield 2 Priority relative to hardware sprites (`000` = PF2 in front of all sprites, `100` = sprites in front of PF2). |
| **2..0** | `PF1P[2:0]` | Playfield 1 Priority relative to hardware sprites (`000` = PF1 in front of all sprites, `100` = sprites in front of PF1). |

#### The Sprite Priority Chain (`PF1P[2:0]`)

Denise evaluates sprite pairs (`SP01`, `SP23`, `SP45`, `SP67`) against Playfield 1 according to the 3-bit code in `PF1P`:

| `PF1P[2:0]` | Binary | Priority Ordering (Front to Back) |
| :---: | :---: | :---|
| `000` (0) | `%000` | **Playfield 1** $\to$ `SP01` $\to$ `SP23` $\to$ `SP45` $\to$ `SP67` |
| `001` (1) | `%001` | `SP01` $\to$ **Playfield 1** $\to$ `SP23` $\to$ `SP45` $\to$ `SP67` |
| `010` (2) | `%010` | `SP01` $\to$ `SP23` $\to$ **Playfield 1** $\to$ `SP45` $\to$ `SP67` |
| `011` (3) | `%011` | `SP01` $\to$ `SP23` $\to$ `SP45` $\to$ **Playfield 1** $\to$ `SP67` |
| `100` (4) | `%100` | `SP01` $\to$ `SP23` $\to$ `SP45` $\to$ `SP67` $\to$ **Playfield 1** |

#### Operational Settings: Dry vs. Submerged

By setting bits 5:3 (`PF2P`) and 2:0 (`PF1P`), we define the two operational modes:

| Mode | `BPLCON2` Value (Hex) | `BPLCON2` Value (Binary) | Visual Behavior |
| :---| :---: | :---: | :---|
| **Dry (Above Water)** | **`$0024`** | `%0000 0000 0010 0100` | `PF1P = %100`, `PF2P = %100`. All sprites (including player `SP01`) render **in front** of Playfield 1. The player walks cleanly on top of platforms. |
| **Submerged (Underwater)** | **`$0000`** | `%0000 0000 0000 0000` | `PF1P = %000`, `PF2P = %000`. Playfield 1 renders **in front** of all sprites (`SP01`). Water tiles occlude the player sprite. |

#### Why Optical Semi-Transparency Works with Hardware Sprites

When `BPLCON2 = $0000`, Playfield 1 is drawn in front of the player sprite. Normally, this would hide the sprite entirely. However, the water layer on Playfield 1 uses a **50% checkerboard dither stipple**:
- **Even pixels (`(x + y) % 2 == 0`)**: Playfield 1 contains Color 1 (Cyan water). Because this pixel is opaque (non-zero), Playfield 1 displays its cyan pixel in front of the player sprite.
- **Odd pixels (`(x + y) % 2 != 0`)**: Playfield 1 contains Color 0 (transparent background). Because Playfield 1 is transparent at this pixel, the hardware sprite underneath shows through unhindered!

Denise multiplexes these interleaved pixels at the electron beam rate (7.09 MHz in PAL). The human eye blends this 50/50 alternating mesh at 50 Hz, producing the optical illusion that the player is submerged under a translucent body of water with zero CPU or blitter bandwidth!

#### Copper List Integration and the Dual-Write Pattern

The Copper list (`cpGame` in `copperlists.asm`) contains a static instruction that reloads `BPLCON2` at the top of every frame:

```m68k
    ; include/resources/copperlists.asm
    dc.w    BPLCON0,$4200           ; 4 bitplanes, colour enable, lo-res
    dc.w    BPLCON1,$0000           ; no horizontal bitplane scroll
cpBPLCON2:
    dc.w    BPLCON2,$0024           ; sprite/playfield priority control (patched live)
    dc.w    BPL1MOD,TILEMAP_SCREEN_MOD
```

To update sprite priority safely without raster tearing or Copper race conditions, a **Dual-Write Pattern** is used:
1. **Write to `cpBPLCON2+2`**: Updates the immediate operand in the Copper instruction, guaranteeing that subsequent VBlanks preserve this state.
2. **Write to `BPLCON2(a6)`**: Immediately updates the live custom chip register in Denise, taking effect on the current scanline without waiting for the next VBlank.

---

### 10.3 Player Spatial Math: Sub-Tile Tracking and Submersion Bounds

Determining when the player is submerged requires sub-pixel coordinate tracking. In *Alien Containment*:
- Tile grid dimensions: 16x16 pixels (`TILE_WIDTH = 16`, `TILE_HEIGHT = 16`).
- Hardware sprite dimensions: 16x24 pixels (attached `SPR0` + `SPR1`).
- Sprite vertical alignment: The 24-pixel sprite is lifted 8 pixels (`subq.w #8, d2`) so that the character's feet rest squarely on top of the 16-pixel tile platform.

```
                  Player Sprite (24px high)
                  +-----------------------+  <- Sprite Top: (Y * 16) + YDec - 8
                  |        Head           |
                  |        Torso          |  <- Tile Row Y boundary
                  |        Legs           |
                  +=======================+  <- Platform Surface / Foot Anchor:
                                                (Y * 16) + YDec + 15
```

#### The Foot Anchor Formula

To prevent false submersion (e.g. water touching the player's head while their feet are standing on dry land, or water being 1 pixel below the platform), the player's current tile row is evaluated at their **foot contact line**:

$$\text{PixelY}_{\text{feet}} = (\text{Player\_Y} \times 16) + \text{Player\_YDec} + 15$$

$$\text{TileRow}_{\text{feet}} = \text{PixelY}_{\text{feet}} \gg 4$$

Where:
- `Player_Y(a4)`: Current base tile row (0..41).
- `Player_YDec(a4)`: Sub-tile decimal pixel offset ($-15 \dots +15$) accrued during ladder climbing, jumping, falling, or bridge sag.
- `+15`: Offsets from the top of the tile to the bottom-most pixel row of the platform.
- `>> 4`: Integer division by 16 to derive the discrete tile row occupied by the feet.

#### Dynamic Priority Switching in `ShowSprite` (`player.asm`)

```m68k
    ; --- Update player sprite priority relative to water ---
    ; If water level has reached the row that the player sprite is on:
    ; Place player sprite behind water (BPLCON2 = $0000: Playfield 1 in front of sprites).
    ; Otherwise, player is dry (BPLCON2 = $0024: sprites in front of playfield).
    move.w    WaterCurrentRow(a5),d0
    bmi.s     .sprite_dry                ; if no water (< 0), dry

    ; Calculate player's current tile row from feet position: (Y*16 + YDec + 15) >> 4
    move.w    Player_Y(a4),d1
    lsl.w     #4,d1                      ; d1 = Player_Y * 16
    add.w     Player_YDec(a4),d1         ; d1 = Player_Y * 16 + Player_YDec
    add.w     #15,d1                     ; d1 = Player_Y * 16 + Player_YDec + 15 (foot pixel)
    lsr.w     #4,d1                      ; d1 = current tile row of player's feet
    cmp.w     d1,d0                      ; compare WaterCurrentRow with player's foot row
    bgt.s     .sprite_dry                ; water row > player row (water is below player)

    ; Water has reached the player's row: sprite behind water
    move.w    #$0000,cpBPLCON2+2
    move.w    #$0000,BPLCON2(a6)
    rts

.sprite_dry:
    move.w    #$0024,cpBPLCON2+2
    move.w    #$0024,BPLCON2(a6)
    rts
```

#### Resurfacing Transitions

When the player climbs a ladder out of the water:
1. `Player_YDec` decreases frame-by-frame as the player ascends.
2. As soon as $\text{TileRow}_{\text{feet}} < \text{WaterCurrentRow}$, `cmp.w d1, d0` detects that `WaterCurrentRow > player_row`.
3. The routine branches immediately to `.sprite_dry`, restoring `BPLCON2 = $0024`. The player emerges from the flood instantly with crisp, full opacity.

---

### 10.4 Enemy Planar Blitter Submersion: Settings & Configurations

Unlike the player, enemies are software bobs blitted directly into `DisplayScreen` across 4 interleaved bitplanes. Hardware registers like `BPLCON2` cannot alter depth between graphics blitted into the same bitmap.

Furthermore, dynamic enemies move every frame. Modifying the background tiles directly would cause moving enemies to smear the water across the playfield.

#### The Triple-Buffer Restoration Pipeline

The engine solves this by combining the Blitter background restoration pipeline with a fast CPU post-blit stipple:

```
[Frame Start]
      │
      ├─► 1. TilemapEraseEnemy:
      │      Restores pristine background from NonDisplayScreen -> DisplayScreen.
      │      (NonDisplayScreen already contains the rising water wavefront).
      │
      ├─► 2. TilemapDrawEnemySubPixel:
      │      Cookie-cut blits enemy graphic into DisplayScreen via minterm $CA.
      │
      └─► 3. Enemy Submersion Check:
             If WaterPixelY <= EnemyBottomY:
                 Apply 50% cyan dither stipple over the enemy in DisplayScreen!
```

#### Blitter Register Configurations for Enemy Drawing

In `TilemapDrawEnemySubPixel` (`tilemap.asm`), enemies are rendered using the Amiga Blitter:

| Register | Word-Aligned Blit (16px wide) | Shifted Blit (32px wide) | Description |
| :---| :---: | :---: | :---|
| **`BLTCON0`** | `$0FCA` | `(Shift << 12) \| $0FCA` | Channels A, B, C, D enabled (`$0F00`). Minterm `$CA` ($D = A \cdot B + \bar{A} \cdot C$). Shift applies to Channel A (Mask) and Channel B (Graphic). |
| **`BLTCON1`** | `$0000` | `(Shift << 12)` | Channel B shift matches Channel A shift. |
| **`BLTAFWM`** | `$FFFF` | `$FFFF` | First Word Mask: all 16 bits active. |
| **`BLTALWM`** | `$FFFF` | `$0000` | Last Word Mask: masks out adjacent frame data on 32px shifted blits. |
| **`BLTAMOD`** | `$0006` (8 - 2) | `$0004` (8 - 4) | Modulo for Mask sheet (64px sheet width = 8 bytes). |
| **`BLTBMOD`** | `$0006` (8 - 2) | `$0004` (8 - 4) | Modulo for Graphic sheet (64px sheet width = 8 bytes). |
| **`BLTCMOD`** | `$0026` (40 - 2) | `$0024` (40 - 4) | Modulo for Screen background (320px screen width = 40 bytes). |
| **`BLTDMOD`** | `$0026` (40 - 2) | `$0024` (40 - 4) | Modulo for Screen destination (320px screen width = 40 bytes). |
| **`BLTSIZE`** | `(64 << 6) \| 1` | `(64 << 6) \| 2` | 64 plane-rows (16 scanlines $\times$ 4 bitplanes) $\times$ 1 or 2 words. |

#### Blitter Register Configurations for Background Restoration

In `TilemapEraseEnemy` (`tilemap.asm`), the previous frame's enemy footprint is erased by copying pristine background data from `NonDisplayScreen` to `DisplayScreen`:

| Register | Erase Aligned (1 Word) | Erase Shifted (2 Words) | Description |
| :---| :---: | :---: | :---|
| **`BLTCON0`** | `$09F0` | `$09F0` | Channels A and D enabled (`$0900`). Minterm `$F0` ($D = A$, direct copy). |
| **`BLTCON1`** | `$0000` | `$0000` | No shift, ascending blit. |
| **`BLTAFWM` / `LWM`**| `$FFFF` / `$FFFF` | `$FFFF` / `$FFFF` | Full word copies without masking. |
| **`BLTAMOD` / `DMOD`**| `$0026` (40 - 2) | `$0024` (40 - 4) | Screen modulo (320px screen = 40 bytes). |
| **`BLTSIZE`** | `(64 << 6) \| 1` | `(64 << 6) \| 2` | 64 plane-rows $\times$ 1 or 2 words. |

---

### 10.5 Post-Blit CPU Stipple Algorithm & Planar Bitwise Logic

Once the enemy is blitted into `DisplayScreen`, if `WaterPixelY <= enemy_bottom_y`, the enemy must be submerged. Rather than setting up another Blitter pass (which would incur substantial register setup overhead and DMA arbitration latency for a small 16x16 or 32x16 area), the 68000 CPU performs the stippling directly in fewer than 300 clock cycles.

#### Planar Interleaved Memory Layout

The display buffer uses an interleaved 4-bitplane structure with a stride of 160 bytes per scanline:

$$\text{Scanline Address} = \text{ScreenBase} + (Y \times 160) + \left(\left\lfloor \frac{X}{16} \right\rfloor \times 2\right)$$

Within that scanline:
- **Plane 0**: `0(a0)`
- **Plane 1**: `40(a0)`
- **Plane 2**: `80(a0)`
- **Plane 3**: `120(a0)`

#### Bitwise Stipple Formulation

In the game's 16-color palette, **Color 1** is Water Cyan:
$$\text{Color 1} = \text{Plane 0} = 1, \quad \text{Plane 1} = 0, \quad \text{Plane 2} = 0, \quad \text{Plane 3} = 0$$

To stipple the enemy with water without destroying their underlying shape:
- On 50% of the pixels, force the color to **Color 1** (Water).
- On the other 50% of the pixels, **preserve** the enemy's original colors.

Matching the global background tile phase $(x + y) \pmod 2 == 0$:

##### 1. Even Scanlines ($Y \pmod 2 = 0$)
On even scanlines, water appears at even pixel positions ($x = 0, 2, 4, 6 \dots$).
- In a 16-bit word, even pixel bit positions correspond to mask `$AAAA` (`%1010 1010 1010 1010`).
- Odd pixel bit positions correspond to mask `$5555` (`%0101 0101 0101 0101`).

```m68k
    or.w    #$aaaa,(a0)      ; Plane 0: force even pixels to 1 (water color bit)
    and.w   #$5555,40(a0)    ; Plane 1: force even pixels to 0, preserve odd pixels
    and.w   #$5555,80(a0)    ; Plane 2: force even pixels to 0, preserve odd pixels
    and.w   #$5555,120(a0)   ; Plane 3: force even pixels to 0, preserve odd pixels
```

**Truth Table for Even Scanlines**:
| Pixel Type | Bit in Mask | Plane 0 Action | Planes 1..3 Action | Resulting Pixel Color |
| :---: | :---: | :---: | :---: | :---|
| **Even Pixel ($x=0,2\dots$)** | `$AAAA` bit = 1 | `OR 1` $\to 1$ | `AND 0` $\to 0$ | `%0001` = **Color 1 (Cyan Water)** |
| **Odd Pixel ($x=1,3\dots$)** | `$5555` bit = 1 | `OR 0` $\to$ Unchanged | `AND 1` $\to$ Unchanged | **Original Enemy Color Preserved** |

##### 2. Odd Scanlines ($Y \pmod 2 = 1$)
On odd scanlines, water appears at odd pixel positions ($x = 1, 3, 5, 7 \dots$).
- Even pixel bit positions correspond to mask `$AAAA`.
- Odd pixel bit positions correspond to mask `$5555`.

```m68k
    or.w    #$5555,(a0)      ; Plane 0: force odd pixels to 1 (water color bit)
    and.w   #$aaaa,40(a0)    ; Plane 1: force odd pixels to 0, preserve even pixels
    and.w   #$aaaa,80(a0)    ; Plane 2: force odd pixels to 0, preserve even pixels
    and.w   #$aaaa,120(a0)   ; Plane 3: force odd pixels to 0, preserve even pixels
```

**Truth Table for Odd Scanlines**:
| Pixel Type | Bit in Mask | Plane 0 Action | Planes 1..3 Action | Resulting Pixel Color |
| :---: | :---: | :---: | :---: | :---|
| **Odd Pixel ($x=1,3\dots$)** | `$5555` bit = 1 | `OR 1` $\to 1$ | `AND 0` $\to 0$ | `%0001` = **Color 1 (Cyan Water)** |
| **Even Pixel ($x=0,2\dots$)** | `$AAAA` bit = 1 | `OR 0` $\to$ Unchanged | `AND 1` $\to$ Unchanged | **Original Enemy Color Preserved** |

#### Scanline Threshold Clipping

In `TilemapDrawEnemySubPixel` (`tilemap.asm`), the loop tracks the exact scanline $Y$:

```m68k
    move.w      WaterPixelY(a5),d2      ; d2 = WaterPixelY
    bmi         .exit_draw              ; if no water (< 0), done
    move.w      d1,d3                   ; d3 = enemy Y
    add.w       #ENEMY_FRAME_HEIGHT-1,d3 ; d3 = enemy bottom scanline
    cmp.w       d2,d3                   ; compare bottom scanline with WaterPixelY
    blt         .exit_draw              ; if bottom scanline < WaterPixelY, completely dry!

    ; Water has reached this enemy: submerge enemy in DisplayScreen!
    WAITBLIT                            ; wait for blitter to finish drawing enemy
    move.w      d7,-(sp)                ; preserve caller's loop counter

    ; Check if 1 word wide (aligned) or 2 words wide (shifted)
    move.w      d0,d3
    andi.w      #15,d3
    bne.s       .submerge_2words

    ; --- 1 Word Wide (16px aligned blit) ---
    move.w      #ENEMY_FRAME_HEIGHT-1,d7 ; 16 scanlines
    movea.l     a2,a0                   ; a0 = scanline pointer in DisplayScreen
.loop_1w:
    cmp.w       d2,d1                   ; is scanline Y >= WaterPixelY?
    blt.s       .next_line_1w           ; if not, dry scanline!

    btst        #0,d1
    bne.s       .odd_1w
    ; EVEN scanline: Plane 0 OR $AAAA, Planes 1..3 AND $5555
    or.w        #$aaaa,(a0)
    and.w       #$5555,40(a0)
    and.w       #$5555,80(a0)
    and.w       #$5555,120(a0)
    bra.s       .next_line_1w

.odd_1w:
    ; ODD scanline: Plane 0 OR $5555, Planes 1..3 AND $AAAA
    or.w        #$5555,(a0)
    and.w       #$aaaa,40(a0)
    and.w       #$aaaa,80(a0)
    and.w       #$aaaa,120(a0)

.next_line_1w:
    addq.w      #1,d1                   ; next scanline Y
    lea         TILEMAP_LINE_STRIDE(a0),a0 ; next scanline in DisplayScreen (+160)
    dbra        d7,.loop_1w
    bra.s       .pop_submerge
```

For shifted 32-pixel enemies (`.submerge_2words`), the stipple applies across both words: `(a0)` and `2(a0)`, `40(a0)` and `42(a0)`, `80(a0)` and `82(a0)`, `120(a0)` and `122(a0)`.

This scanline-by-scanline check guarantees:
1. **Sub-Pixel Depth Boundary**: If an enemy is waist-deep in water, only the submerged scanlines receive the stipple. The dry upper half remains crisp and unmodified.
2. **Zero Spatial Distortion**: Because the stipple uses the global $(x + y) \pmod 2 == 0$ phase, the water pattern on the enemy aligns seamlessly with the water on the surrounding background tiles, creating a single, continuous water surface.
3. **No Smearing or Ghosting**: Because the post-blit stipple modifies **only** `DisplayScreen`, when `TilemapEraseEnemy` restores the clean background from `NonDisplayScreen` next frame, the stippled enemy is completely erased, leaving the background water completely pristine!

---

### 10.6 Hardware Configuration Summary Reference Table

| Target | Subsystem | Dry State (Above Water) | Submerged State (Underwater) | Register / Address |
| :---| :---: | :---: | :---: | :---|
| **Player Sprite** | Denise Priority | `BPLCON2 = $0024`<br>(`PF1P = %100`) | `BPLCON2 = $0000`<br>(`PF1P = %000`) | `BPLCON2` (`$DFF044`) & `cpBPLCON2+2` |
| **Player Evaluation** | CPU / Foot Line | $\text{TileRow}_{\text{feet}} < \text{WaterCurrentRow}$ | $\text{TileRow}_{\text{feet}} \ge \text{WaterCurrentRow}$ | `Player_Y(a4)`, `Player_YDec(a4)`, `WaterCurrentRow(a5)` |
| **Enemy Bobs** | Blitter Render | Minterm `$CA` (`$0FCA`) | Minterm `$CA` (`$0FCA`) | `BLTCON0` (`$DFF040`), `BLTCON1` (`$DFF042`) |
| **Enemy Submersion** | CPU Stipple | Skipped (`ei_Y + 15 < WaterPixelY`) | Even: `OR #$AAAA`, `AND #$5555`<br>Odd: `OR #$5555`, `AND #$AAAA` | Direct writes to `DisplayScreen` planes 0..3 |
| **Enemy Erase** | Blitter Restore | Minterm `$F0` (`$09F0`) | Minterm `$F0` (`$09F0`) | `BLTAPT` $\to$ `NonDisplayScreen`, `BLTDPT` $\to$ `DisplayScreen` |


---

## 11. Summary & Key Takeaways for Retro Developers

1. **Hardware Limitations Breed Creative Solutions**: When a platform lacks true alpha blending, spatial dither stippling provides an optical equivalent that requires zero arithmetic overhead during gameplay.
2. **The Monotonic Mask Enclosure Principle**: When shifting a multi-scanline graphic (like a 5-pixel wave) across planar memory with spatial dither, ensure each advancing line's silhouette is a subset of subsequent lines ($L_0 \subset L_1 \subset L_2$). This guarantees that the formula `(Plane & not_m) | px_or` atomically clears and replaces the dither bits without ever touching the complementary dry background bits, eliminating smearing and removing any need for expensive Chip RAM backup screens.
3. **Overwrite Prior Locations with Fill Tiles**: When advancing an environmental boundary, treating the front boundary (the first 5 pixel rows) as a cohesive unit and immediately overwriting the vacated lines behind it with the background fill tile (the solid blue water) creates a natural, fluid wavefront that seamlessly transitions into deep water.
4. **Integer Accumulators Eliminate Drift**: When mapping fractional intervals (e.g. 16 pixels per 500 frames = 31.25 frames/pixel), avoid fixed float divisions. Adding the numerator to an accumulator each frame and subtracting the denominator upon overflow guarantees jitter-free, frame-perfect synchronization across both PAL and NTSC video standards.
5. **Know When to Use the CPU Over the Coprocessor**: The Amiga Blitter is magnificent for block memory transfers and shifted sprite cookies, but for short, contiguous word loops (such as 6 scanlines), a tight 68000 loop with register pre-loading avoids blitter setup overhead, custom chip register writes, and DMA bus arbitration, running in under 20,000 cycles (~0.1% CPU load) with total predictability.
6. **Dual Depth Paradigms for Sprites vs. Bobs**:
   - For hardware sprites, utilize custom chip priority registers (`BPLCON2 = $0000` submerged vs `$0024` dry). The transparent bits of the dithered playfield allow the sprite underneath to show through with zero CPU or blitter bandwidth.
   - For planar blit bobs, apply an in-phase checkerboard stipple directly onto the destination bitplanes after blitting, relying on clean background restoration buffers (`NonDisplayScreen`) to erase the actor next frame without smearing the water.

