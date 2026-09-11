# ALIEN CONTAINMENT: REACTOR BREACH
## Comprehensive Game Concept & Design Specification

**Target Platform:** Commodore Amiga 500 (OCS/ECS, 1 MB RAM, 68000 CPU @ 7.09/7.16 MHz)  
**Display Format:** PAL (320×200 visible viewport, 320×672 continuous vertical level canvas, 4 bitplanes / 16 colors)  
**Map Geometry:** 20 columns × 42 rows (16×16 px tiles, 672 scanlines total)  
**Engine Baseline:** Amiga 68000 Assembly Engine (Interleaved Bitplanes, Copper Splits, Blitter Cookie-Cut, Hardware Sprites)

---

## 1. High Concept & Setting

### The One-Sentence Pitch
Trapped at the bottom of a subterranean research reactor following a catastrophic containment cascade, an unarmed maintenance technician must out-climb a rising tide of radioactive coolant, outsmart lethal bio-mutants, and activate emergency overrides to escape through the extraction airlock at the summit.

### Backstory
Deep beneath the surface of the **Prometheus Research Facility**, a core meltdown has triggered an emergency containment purge. Coolant lines have ruptured, flooding the lowest tier with glowing, corrosive radiation. The facility's captive biological specimens—mutated by radiation into aggressive pests—have breached their containment pods and now infest every service shaft.

The automated safety protocols have locked all evacuation hatches until sector override switches are manually engaged. Armed with no weapons, you must use agility, spatial awareness, maintenance ladders, and heavy waste drums to climb through the 42-row facility tower before the rising coolant overtakes you.

---

## 2. Core Gameplay Pillars

```
   ================== ROW 00 - 03: EXTRACTION AIRLOCK ==================
   [AIRLOCK HATCH] ─── Locked until all Sector Switches are active ───► EXIT!
                                   ▲
   ================== ROW 04 - 15: MAINTENANCE DUCTS ===================
   - Fast Aerial Mutants (Wasps/Bats) patrol across open ladder climbs
   - Emergency Override Switch #2 in a narrow side duct
   - 1-Tile Hazard Gaps over exposed electrical wiring
                                   ▲
   ================== ROW 16 - 28: CARGO & WASTE TIER ==================
   - Heavy Waste Drums sitting on high catwalks
   - Ground Crawlers (Slimes/Snails) patrol the main walkways
   - Push drums off edges to crush crawlers and clear the path
   - Emergency Override Switch #1
                                   ▲
   ================== ROW 29 - 41: REACTOR CORE (BREACH) ===============
   - Player Spawn at Row 32 (x=24, y=512)
   - Immediate ascent: initial ladders and crumbling platforms
   - ═══════════════════════════════════════════════════════════════════
     ▲ ▲ ▲ RISING RADIOACTIVE COOLANT FLOOD (Rises from Row 41) ▲ ▲ ▲
     Copper scanline palette split: green toxic acid water rising upward!
```

---

### Pillar 1: 1-Tile Hazard Jump ("Ledge Hop")
To bridge the gap between deterministic puzzle mechanics and responsive platforming action, the player possesses a **1-tile horizontal hop**:

- **Controls:** Press **`Fire + Direction`** (or `Fire` while walking left/right).
- **Physics & Arc:** 
  - The player leaps horizontally by **16 pixels (1 tile)** in a crisp, fast trajectory (12–16 frames).
  - While at the apex of the hop, the player's collision with floor hazards (`BLOCK_ACID`, toxic waste, live floor cables) is suspended.
  - If the target cell is a solid platform, the player lands smoothly.
  - If the target cell is empty air (e.g. over a pit), the player cleanly transitions into standard gravity fall (`ActionFalling`).
  - If the target cell is a solid wall or closed barrier, the hop is obstructed and denied.
- **Game Design Role:** Allows crossing single-tile radioactive puddles or hopping across small gaps without sacrificing the precision of the underlying grid-based puzzle engine.

---

### Pillar 2: The Rising Radiation Flood (The Diegetic Timer)
Rather than an artificial digital countdown clock, urgency is driven by a visible, physical environmental hazard:

- **Mechanics:**
  - A 16-bit variable `RadiationY` is initialized to the floor of the shaft (Row 41, $Y=656$).
  - Every $N$ frames (configurable per sector; default = 1 pixel every 6 frames, allowing ~60–80 seconds to clear the 672px shaft), `RadiationY` decrements, creeping upward toward Row 0.
  - If `PlayerY >= RadiationY`, the player’s hazard suit is breached, triggering an instant death sequence and rewinding to the stage start.
- **The Amiga Copper Visual:**
  - The Copper coprocessor calculates the relative scanline:  
    $$\text{ScreenSplitY} = \text{RadiationY} - \text{TilemapCameraY}$$
  - If $\text{ScreenSplitY}$ falls within the visible screen ($0 \le \text{ScreenSplitY} < 200$), the Copper list inserts a horizontal color split:
    - **Above the line:** Standard facility interior and gradient sky.
    - **Below the line:** Background color `COLOR00` and tile bitplane registers shift to a **pulsing, murky neon-green / amber toxic glow**.
  - As the player climbs higher and looks down, the toxic flood is visibly seen rising through the steel platforms!

---

### Pillar 3: Pushable Waste Drums & Environmental Physics
Without firearms or ranged weapons, the player's offensive capability relies on environmental manipulation:

- **Pushing Drums (`BLOCK_PUSH`):**
  - Walking into a waste drum pushes it horizontally into adjacent empty tiles.
  - Drums slide with full sub-tile interpolation until reaching an obstruction or ledge.
- **Gravity & Crushing:**
  - Pushing a drum off a platform activates `InitFallingBlock`. The drum accelerates downward under gravity.
  - If a falling drum lands on an active enemy (`BLOCK_ENEMYFALL` / `ActiveEnemies`), the creature is crushed, triggering a death puff animation (`ActionCloudActors`) and freeing the corridor.
- **Plugging Leaks:**
  - Pushing a drum into a pool of hazardous acid (`BLOCK_ACID`) neutralizes the pool and seals it into a safe, walkable bridge.

---

### Pillar 4: Enemy Lethality & Threat Hierarchy
Enemies are active physical threats patrolling dedicated corridors and air ducts:

- **Collision Detection:**
  - Every frame in `TilemapUpdateEnemies`, a bounding-box overlap test checks the player's hardware sprite coordinates $(X, Y)$ against all active blitted creatures.
  - Contact results in an immediate suit rupture and level rewind/death.
- **Creature Categories:**
  1. **Ground Crawlers (Cyan & Red Slimes, Armored Snails):**
     - Patrol along horizontal catwalks.
     - Must be bypassed by timing movements, jumped over using the 1-tile hop, or crushed from above with waste drums.
  2. **Aerial Flyers (Wasps, Bats, Octo-pods):**
     - Hover and patrol horizontally across open ladder shafts.
     - Create tense climbing timing puzzles: the player must pause on a ladder rung or slide down to let the flyer pass overhead.

---

### Pillar 5: Emergency Override Switches
To prevent players from simply rushing straight up the primary ladder shaft, progress requires active exploration:

- **Placement:** Placed in side rooms, dead-end ducts, and guarded catwalks.
- **Interaction:**
  - Stepping onto a switch or terminal tile triggers an immediate audio chime / siren response.
  - The visual tile updates dynamically (e.g. flashing red indicator flips to steady green).
  - The sector counter `SwitchesRemaining` decrements.
  - When `SwitchesRemaining == 0`, a facility-wide alarm rings: **"CORE CONTAINMENT OVERRIDE ENGAGED — EXTRACTION HATCH UNLOCKED"**.

---

### Pillar 6: The Extraction Hatch & Level Progression
The pinnacle of each level is the top-tier evacuation point:

- **Sealed State (Switches Remaining > 0):**
  - The hatch at Row 1–2 is represented by a locked blast door graphic (`LOCKED`).
  - Attempting to enter while locked displays a brief warning text or rejection buzz.
- **Unsealed State (Switches Remaining = 0):**
  - The blast door retracts into an open airlock hatch.
- **Exit Trigger:**
  - Walking into the open airlock triggers `LEVEL_COMPLETE_SETUP`:
    1. Player sprite walks into the hatch / fades out.
    2. Victory fanfare plays via PTPlayer.
    3. Level Complete stats screen displays: Time Elapsed, Moves Made, Radiation Margin (how close the flood came).
    4. 6-character access password revealed for Level 2.
    5. Seamless transition into the next, more complex sector.

---

## 3. Control Scheme

| Action | Joystick (Port 2) | Keyboard Mapping | Engine Mechanics |
| :--- | :--- | :--- | :--- |
| **Walk Left / Right** | Left / Right | Left / Right Arrows | Continuous tile step (16px interpolation) |
| **Climb Up / Down** | Up / Down | Up / Down Arrows | Ladder alignment check (`BLOCK_LADDER`) |
| **1-Tile Hazard Hop** | **Fire + Left / Right** | **Space + Left / Right** | Horizontal 16px leap over floor hazards |
| **Push Drum** | Walk against Drum | Walk against Drum | Pushes `BLOCK_PUSH` into adjacent empty cell |
| **Activate Switch** | Walk over Switch | Walk over Switch | Instant terminal trigger on tile entry |
| **Undo / Rewind** | (Assigned Key) | **Backspace / 'U'** | Reverses last moves with VHS glitch effect |
| **Abort / Quit** | — | **ESC** | Immediate clean return to Title Menu |

---

## 4. Technical Architecture on Amiga 500

### 1. Memory & Section Allocation
- **Code & Logic (`main,code`):** Fits within standard 512 KB Fast/Chip memory envelope.
- **Screen Buffers (`mem_chip`):**
  - `DisplayScreen` (active bitplane buffer) and `NonDisplayScreen` (restoration background).
  - Full 43-row height (688 scanlines × 160 bytes = 110,080 bytes per buffer).
- **Asset Interleaving (`data_chip`):**
  - `GameTilesRaw` / `Msk`: 176×256 px tileset (11 tiles per row, 4 bitplanes interleaved).
  - `EnemySpritesRaw` / `Msk`: 64×128 px enemy sprite sheet (4 frames per creature, cookie-cut blitted).
  - Hardware Sprites (`PlayerHWSprites`): Two attached 16-color sprites (SPR0 & SPR1) for 0% CPU blit overhead on player animation.

### 2. The Blitter & Copper Pipeline
```
[VBlank Interrupt (50 Hz PAL)]
       │
       ▼
[GameRun (gamestatus.asm)]
       ├── 1. UpdateControls: Read Joystick & Keyboard
       ├── 2. PlayerLogic: Process Walking, Ladders, Falling, or 1-Tile Hop
       ├── 3. TilemapUpdateCamera: Smooth scroll CameraY to follow PlayerMapPixelY
       ├── 4. RadiationTick: Increment RadiationY; check Player collision
       ├── 5. TilemapUpdateEnemies: Patrol enemies, check Player collision, blit sub-pixel
       ├── 6. Switch & Exit Check: Detect switch overlap; trigger hatch unseal
       └── 7. TilemapUpdateCopperSky: Update Copper sky gradient + Radiation Flood split
```

---

## 5. Level 1 Blueprint: "Sector 01 — Coolant Breach"

### Layout & Metric Map
- **Dimensions:** 20 columns wide (320 px), 42 rows tall (672 px).
- **Starting Position:** Column 1, Row 32 ($X=24, Y=512$).
- **Flood Origin:** Row 41 ($Y=656$), rising at 1 px per 6 frames.
- **Switches Required:** 2 Emergency Override Terminals.

### Sector Progression & Puzzles
1. **Tier 1 — The Escape (Rows 32–41):**
   - Player spawns as the siren sounds. 
   - A single-tile toxic pool blocks the right corridor $\rightarrow$ teaches the **1-Tile Hazard Hop**.
   - Immediate ladder climb to escape the initial coolant surge.
2. **Tier 2 — The Cargo Deck (Rows 18–31):**
   - Two Cyan Slimes patrol a long catwalk.
   - A heavy Waste Drum sits on an upper platform.
   - Pushing the drum off the ledge crushes Slime #1 and plugs a drain leak.
   - Side alcove houses **Override Switch #1**.
3. **Tier 3 — The Conduit Shafts (Rows 05–17):**
   - Long vertical ladder climbs intersected by flying Wasps.
   - Requires pausing on ladder rungs to avoid crossing flight paths.
   - Branching right duct contains **Override Switch #2**.
   - Triggering Switch #2 chimes: **"AIRLOCK UNLOCKED"**.
4. **Tier 4 — The Airlock Summit (Rows 00–04):**
   - Final sprint past a high-speed Snail patrol.
   - Reach the open Airlock at Row 1 $\rightarrow$ **Sector Cleared!**

---

## 6. Implementation Roadmap

| Milestone | Target Systems | Key Source Files |
| :--- | :--- | :--- |
| **Milestone 1** | **Player-Enemy Collision & Lethality** | [`gamestatus.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/gamestatus.asm), [`tilemap.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/tilemap.asm) |
| **Milestone 2** | **1-Tile Hazard Jump (`Fire + Dir`)** | [`player.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/player.asm) |
| **Milestone 3** | **Rising Radiation Flood & Copper Split** | [`tilemap.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/tilemap.asm), [`variables.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/variables.asm) |
| **Milestone 4** | **Override Switches & Airlock Hatch** | [`export_level.py`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/tools/export_level.py), [`levelcomplete.asm`](file:///C:/Users/shani/OneDrive/Documents/GitHub/AlienContainment/include/resources/levelcomplete.asm) |
| **Milestone 5** | **Level 1 Authoring & Polish** | `assets/Levels/Level_01.tmx`, `four-seasons-tileset.png` |
