# Enemy Types & Tiled Level Editor Guide

This guide documents the available enemy sprite types, their behavior profiles, and instructions for placing and configuring them within **Tiled** maps for *Alien Containment*.

---

## 1. Available Enemy Types

All enemy sprites are 16×16 pixels with 4 animation frames each, rendered using 4-bitplane (16-colour) interleaved bitplanes and cookie-cut masked blits.

| Enemy ID (`type`) | Assembly Constant | Creature Description | Typical Movement Profile |
| :---: | :--- | :--- | :--- |
| **`1`** | `ENEMY_1_SLIME_CYAN` | Cyan Bouncing Slime | Ground Patrol |
| **`2`** | `ENEMY_2_SLIME_RED` | Red Magma Slime | Ground Patrol |
| **`3`** | `ENEMY_3_WASP_FLY` | Flying Wasp / Bee | Air Patrol / Hover |
| **`4`** | `ENEMY_4_BAT_RED` | Red Gargoyle Bat | Air Patrol / Swoop |
| **`5`** | `ENEMY_5_CYCLOPS_GREEN` | Green Horned Cyclops | Ground Patrol |
| **`6`** | `ENEMY_6_OCTO_PURPLE` | Purple Floating Octo-pod | Air Float / Drift |
| **`7`** | `ENEMY_7_SNAIL_SHELL` | Armored Snail | Slow Ground Patrol |
| **`8`** | `ENEMY_8_GHOST_BLUE` | Blue Spore / Ghost | Air Float / Oscillation |

---

## 2. Placing Enemies in Tiled

### Object Layer
Place enemies in the **`elements`** Object Layer as a **Point** or **Rectangle** object.

### Standard Object Fields
- **Class / Type**: `ENEMY` *(the exporter also recognizes `patrol`, `flyer`, `crawler`)*
- **Name**: Any descriptive label (e.g. `ENEMY`, `CyanSlime_01`, `Wasp_A`)
- **Position (X, Y)**: Pixel coordinates where the enemy will spawn.

### Custom Properties (Properties Panel)

Add the following custom properties to each enemy object in Tiled:

| Property Name | Type | Allowed Values | Default | Description |
| :--- | :---: | :---: | :---: | :--- |
| **`type`** | `int` | `1` .. `8` | `1` | Selects which enemy creature sprite sheet row to blit. |
| **`speed`** | `int` | `1` .. `4` | `1` | Movement speed in pixels per frame. |
| **`patrol_min_x`** | `int` | `0` .. `320` | `X - 64` | Minimum horizontal pixel boundary for patrol turnaround. |
| **`patrol_max_x`** | `int` | `0` .. `320` | `X + 64` | Maximum horizontal pixel boundary for patrol turnaround. |

---

## 3. TMX XML Example

Below is an example object entry from `assets/Levels/Level_01.tmx`:

```xml
<object id="3" name="ENEMY" type="ENEMY" x="280" y="624">
  <properties>
    <property name="patrol_max_x" type="int" value="240"/>
    <property name="patrol_min_x" type="int" value="96"/>
    <property name="speed" type="int" value="1"/>
    <property name="type" type="int" value="1"/>
  </properties>
  <point/>
</object>
```

---

## 4. Build & Export Pipeline

When you run `.\build.ps1`, the level exporter (`tools/export_level.py`) parses the `elements` layer and generates the assembly spawn tables in `include/resources/<level>_entities.asm`:

```m68k
; Enemy Spawn Table
Level_01_EnemyCount:      dc.w    1
Level_01_EnemyList:
    ; Structure per enemy:
    ;   dc.w  Type, Col, Row, PixelX, PixelY, PatrolMinX, PatrolMaxX, Speed
    dc.w    1, 17, 39, 280, 624, 96, 240, 1   ; Enemy 1
```

The viewport blitter in `include/resources/tilemap.asm` (`TilemapDrawEnemies`) reads this table and automatically blits the appropriate animated enemy graphics on top of the platform tile layer.
