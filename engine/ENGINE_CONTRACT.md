# Engine/Game Contract

What `engine/` expects a game to supply, and what it calls into. There is no
formal interface mechanism here — this is 68000 assembly assembled as one
translation unit, so "the contract" is just "which symbols must exist
somewhere in the include chain before assembly will succeed." This document
is that list, written down once instead of discovered by grepping for
unresolved-symbol errors.

See `docs/MAKING_A_GAME_GUIDE.pdf` for the step-by-step guide to building a
new game on top of this. This document is the reference once you're past
the first build.

## 1. The register convention (non-negotiable)

Held constant for the entire program after `Restart` in `engine_main.asm`:

| Register | Holds | Set by |
|---|---|---|
| `a5` | Base pointer into the `Variables` block (Fast RAM) | `Restart` (`engine_main.asm`) |
| `a6` | `$dff000`, the custom chip registers | `Restart` (`engine_main.asm`) |
| `a4` | Current player struct pointer | Game code, per-call (`lea Player(a5),a4`) |
| `a3` | Current actor struct pointer | Engine/game code, per-call |

Every engine routine that touches game state assumes `a5`/`a6` are already
set this way. A game's `main.asm` does not set these itself — it's handled
once in the engine's own `Restart`.

## 2. The `Variables` block: two owners, one `rsreset` chain

There is one Fast RAM struct, built by chaining two `rsreset` blocks:

1. `engine/include/engine_variables.i` — the engine's own baseline fields
   (`LevelId`, `CurrentMapSize`, `GameMap`, `RandomSeed`, and others under
   its own section headers). **A game must not redefine these.**
2. `games/duck_rescue/include/core/variables.asm` — `INCLUDE`s
   `engine_variables.i` first, then appends game-specific fields
   (`Player`, `PlayerOxygen`, ...) on the *same* `rsreset` chain before
   the block closes with `Variables_Sizeof`. A game that uses
   `engine/gameplay/entities.asm` also `INCLUDE`s `entity_variables.i`
   on that chain, which adds the `ActiveEnemies`/`ActiveFriends`/
   `ActivePickups` pools.

**A new game's `variables.asm` must follow this exact pattern**: `INCLUDE
"engine_variables.i"` first, then append your own fields, then close the
block. Skipping step 1, or starting a fresh `rsreset`, silently destroys
every engine field's offset.

Engine effects own their own state: the rising-water and air-bubble fields
(`WaterPixelY`, `LiveWaterMap`, `BubbleActive`, ...) live in
`engine_variables.i`, so including `water_effects.asm` or
`bubble_sprite.asm` needs no game-side fields (the bubble does need the
constant `PLAYER_HEAD_Y_OFFSET`: without it, `bubble_sprite.asm` assembles to
nothing). What the engine still reads
from the game is the `Player` struct (section 3) and the contract constants
(section 5). **If a build fails with an unresolved `(a5)` field, grep the
engine file that names it; it is one of those two.**

## 3. Structs: ownership is split, not uniform

| Struct | Owner | Defined in |
|---|---|---|
| `Player_*` | **Game** | `games/duck_rescue/include/core/struct.asm` |
| `Actor_*` (crates/push-blocks) | **Engine** | `engine/include/actor_struct.i` |
| `Enemy_*` (patrol enemies) | **Engine** | `engine/include/entity_struct.i` |
| `Friend_*` (animated collectables) | **Engine** | `engine/include/entity_struct.i` |
| `Pickup_*` (tile pickups) | **Engine** | `engine/include/entity_struct.i` |
| `Snap_*` (undo snapshot) | **Game** | `games/duck_rescue/include/core/struct.asm` |

The engine-owned structs are used as-is. `Actor_*` comes with `actors.asm`
and `actor_physics.asm`; `Enemy_*`/`Friend_*`/`Pickup_*` come with
`engine/gameplay/entities.asm`, together with the sheet geometry
(16x16 frames, four to a 64-pixel row). A game that includes
`entities.asm` includes `entity_struct.i` from its constants file, after
`engine_const.i`. The names are generic: a `Pickup_*` is any static tile
the player collects, and a friend is any animated collectable, set aside
once the game sets `Friend_Collected`. What collecting one means (Duck
Rescue's oxygen refills and rescued ducklings) is the game's business.

`Player_*` is **game-defined**, and the engine reads it: `bob_compositor.asm`,
`actors.asm` (`InitPlayer`), `actor_physics.asm` (push, next cell) and
`entities.asm` (re-drawing the player under an enemy) use the field names
Duck Rescue defines in `struct.asm`, so a new game copies that struct as its
starting point.

`Snap_*` (the undo/rewind snapshot) has no automatic relationship to the
structs it mirrors — it's a hand-written parallel struct that must be kept
in sync by hand whenever `Player_*`/`Actor_*`/`Enemy_*`/`Friend_*`/`Pickup_*` change.
There is no generator for this; see `engine/gameplay/undo.asm`'s
`TakeSnapshot`/`UndoMove` for what it actually copies.

Each struct also needs a matching `*_Sizeof` constant (`Enemy_Sizeof`,
`Player_Sizeof`, `Variables_Sizeof`, ...) computed from its own field list.
Naming rules for all of these are in `docs/CODING_CONVENTIONS_GUIDE.pdf`.

## 4. Pool-size constants: also split

| Constant | Owner | Defined in |
|---|---|---|
| `MAX_ACTIVE_ENEMIES` | **Game** | `const.asm` |
| `MAX_ACTIVE_FRIENDS` | **Game** | `const.asm` |
| `MAX_ACTIVE_PICKUPS` | **Game** | `const.asm` |
| `MAX_ACTIVE_CRATES` | **Engine** (has a default) | `engine/include/engine_const.i` |

A game that includes `entities.asm` must define the first three, since
`entity_variables.i` sizes the pools from them (set one to a small number
if the game has none of that kind of entity). A game that does not include
`entities.asm` needs none of them. `MAX_ACTIVE_CRATES`
already has an engine default and only needs overriding if you want a
different pool size.

A game with built-in levels also defines `LEVEL_TABLE_COUNT`, the number of
entries in its `LevelTable`. Work it out from the table itself, so that
adding a level never means editing an engine file:

```asm
LevelTable:
    dc.l       Level_01_Def
    dc.l       Level_02_Def
LevelTableEnd:
    dc.l       0                       ; null terminator
LEVEL_TABLE_COUNT = (LevelTableEnd-LevelTable)/4
```

`gamestatus.asm`, `levelutils.asm`, `levelcomplete.asm` and `titlescreen.asm`
read it for the level warp keys, the title-screen selector and the
end-of-campaign check.

## 5. Entry points: exactly two

`engine_main.asm`'s own header comment names them explicitly
("Callbacks required from the game layer"):

- **`GameInitHook`** — called once from `EngineInit` (`bsr GameInitHook`,
  `engine_main.asm:181`). Set up whatever initial state your game needs.
- **`GameStatusRun`** — called **every frame** from `MainLoop`
  (`bsr GameStatusRun`, `engine_main.asm:112`). This is your entire
  per-frame game logic entry point. Duck Rescue's version
  (`engine/gameplay/gamestatus.asm`) is a 27-state dispatcher covering
  loading/title/gameplay/credits/game-over/etc., but nothing requires
  that — **a minimal game can write a `GameStatusRun` that's a handful of
  lines** (check a key, maybe flip a border colour, `rts`) without
  pulling in any of the screens/ files Duck Rescue uses. `QuitFlag(a5)`
  must be set from *somewhere* in your `GameStatusRun` for `MainLoop` to
  ever exit back to `QuitToOS` (Duck Rescue's title screen sets it on
  ESC; a minimal game can test the ESC scancode directly).

There is no registration table and no default for either — omit one and
assembly fails with an unresolved symbol, not a clean error message.

Everything else is **structural, not callback-based**: a game integrates by
choosing which engine `.asm` files to `include` from its own `main.asm`,
in what order (see `docs/MAKING_A_GAME_GUIDE.pdf` §7 for why order matters), rather than
the engine calling into a set of named game functions.

## 6. Two more things every game must provide, discovered by actually building a minimal one

Static analysis of `(a5)` field references (sections 2-4) doesn't catch
everything — these two surfaced only when building `games/starter/`
from scratch and following vasm's own errors:

- **A `Sinus`/`SinusEnd` labelled table.** `engine/include/engine_const.i`
  unconditionally computes `SINE_ANGLES = (SinusEnd-Sinus)/2` — this is
  evaluated for every game, even one that never uses sine-based motion,
  because it's a plain equate in an always-included file. Duck Rescue's is
  a real 4,096-byte precomputed table (`assets/data/sin.bin`);
  `games/starter/main.asm` provides a tiny placeholder purely to satisfy
  the equate.
- **`cpGameDIW` and `cpSprites` Copper sub-block labels, with a specific
  shape.** `engine/system/system.asm`'s `DetectNTSC` patches
  `cpGameDIW+2`/`cpGameDIW+6` (expects two `MOVE DIWSTRT,x` / `MOVE
  DIWSTOP,x` word-pairs back to back), and `ClearSprites` writes all 8
  sprite pointers into `cpSprites` (expects 16 `MOVE SPRxPTH/L,x` word-pairs
  back to back). Both are called unconditionally if you `include
  "system.asm"` (required — see section 5). See `games/starter/main.asm`'s
  `StarterCopperList` for the minimal shape that satisfies both, or
  `engine/graphics/copperlists.asm`'s `cpGame` for Duck Rescue's full one.

**The general lesson** (worth remembering before trusting this document
as exhaustive): grep-based contract discovery finds direct `(a5)` field
reads reliably, but misses equate-chain dependencies and byte-offset
patches into labelled data. If you hit an unresolved-symbol error this
document doesn't mention, that's this category — not a sign you did
something wrong.

## 7. BSS allocations your `main.asm` must declare

The engine defines the *layout* of several buffers (via `rsreset` structs
and constants) but does not allocate their actual memory — that happens in
the game's own `main.asm`, in its `mem_fast,bss` and `mem_chip,bss_c`
sections. Engine code reads/writes these by bare label name, so if your
`main.asm` doesn't declare them, you get an unresolved-symbol error at
assembly time, not a runtime crash. At minimum:

| Label | Section | Referenced by |
|---|---|---|
| `Variables` | `mem_fast` | everything — `lea Variables,a5` in `Restart` |
| `GameStack` / `GameStackTop` | `mem_fast` | `Restart` (`lea GameStackTop,sp`) |
| `Keys` | `mem_fast` | `engine/system/keyboard.asm`, `controls.asm` (256-byte scan-code buffer) |
| `NullSprite` | `mem_chip` | `engine/system/system.asm`'s `StartVBlank`/sprite setup (unused hardware sprite channels point here) |
| `FaultScreen` | Chip RAM, at least 20,608 bytes (`FAULT_SCREEN_BYTES`) | `engine/system/system.asm`'s `FaultTrap` draws the fault screen here. Point it at an existing screen buffer (`FaultScreen = DisplayScreen`); it is only overwritten after a crash |

(`CUSTOM` and `SavedOSStack` are the exception — both are already provided:
`CUSTOM` by `engine/include/amiga_hw.i`, `SavedOSStack` by
`engine/system/system.asm`.)

A game can be started from the CLI or from a Workbench icon. `Main` and
`QuitToOS` handle the Workbench startup message, so a game needs no code for it.
Give your game a `.info` file to launch it from Workbench.

If you `include` graphics subsystems (`tmx_renderer.asm`, `bob_compositor.asm`,
etc.) you'll also need `DisplayScreen`/`NonDisplayScreen` sized for your own
screen resolution — see `games/duck_rescue/main.asm`'s Chip BSS sections
(`mem_chip`, `chip_display`, `chip_backdrop`) for the full pattern this is based on. There's no shorter authoritative
list than reading that section once.

## 8. INCDIR: how a game points the engine at itself

`games/duck_rescue/main.asm` (lines 26–59) declares two parallel sets of
`INCDIR` paths:

- Lines 26–41 assume the assembler's working directory is the **repo
  root** — this is the set actually used, since `build.py` does
  `os.chdir(project_root)` to the repo root before invoking `vasm`.
- Lines 44–59 are a fallback for cwd = `games/duck_rescue/` itself
  (relative `"."`, `"../../engine"`, etc.) — kept for manual/alternate
  invocation, not exercised by the current `build.py`.

A second game needs its own copy of both blocks, with `"games/duck_rescue"`
(and its subdirectories) replaced by `"games/<your_game>"`. `build.py`
already supports this via `--game <your_game>`, which assembles
`games/<your_game>/main.asm` as the entry point.

## 9. Known-incomplete reference code

`engine/graphics/tile_renderer.asm`'s `DrawSprite` is real, documented
code that is **not included** by Duck Rescue and **references four
symbols that don't exist anywhere in this codebase**: `TILE_SIZE`,
`TILE_HEIGHT`, `ActorSprites`, `SpriteMaskScratch`. It's kept as a
starting point for a future game, not a drop-in feature — read its header
comment before `include`ing it.

## 10. Hooks: how the engine calls into the game

The engine never names a game routine. At fixed points it calls the
`Game*Hook` routines below, which every game must define (a routine, or a
binding equate `GameLogicHook = MyRoutine`). `games/starter/include/
game_hooks.asm` has them all as empty stubs; `games/duck_rescue/include/
game_hooks.asm` is the worked example. Unless stated, a hook may clobber
`d0-d7/a0-a4`; `a5`/`a6` hold the usual bases.

| Hook | Called from | When | Contract |
|---|---|---|---|
| `GameInitHook` | `engine_main.asm` | once at boot, inside `EngineInit` | install your first Copper list, seed state |
| `GameSetupHook` | `gamestatus.asm` | once per game start, after engine setup | e.g. HUD sprites |
| `GameLevelInitHook` | `levelutils.asm` `LevelInit` | geometry loaded, player positioned | reset per-level state, fill entity pools |
| `GameShowPlayerHook` | `levelutils.asm`, `tmx_renderer.asm` | level reveal | draw the player at its position |
| `GameLevelDoneHook` | `levelcomplete.asm` `LevelTest` | every frame | `d3 = 0` when the objective is met |
| `GameUndoAllowedHook` | `gamestatus.asm` | F9 pressed while idle | `d0 = 0` to allow the rewind |
| `GameRestoreOverlapsHook` | `gamestatus.asm` | in the player's extras, after its stamps (after the entities of the player's phase) | re-blit entities the player erase touched, and redraw any the stamps covered |
| `GameDrawPriorityHook` | `gamestatus.asm` | twice per frame: the top rows (in VBlank, after the player's erase and blit if it is up there), then the rest (`d0.w` = first screen Y, `d1.w` = end, exclusive) | move and draw the game's beam-raced entities in that slice; slices above `ENTITY_TOP_TIER_Y` are the priority work. Draw order rules: `docs/BLIT_ORDER_GUIDE.pdf` |
| `GameDrawHook` | `gamestatus.asm` | after `SetRasterLogicColor` | remaining blits, chasing the beam |
| `GameLogicHook` | `gamestatus.asm` | after `UpdateControls` | player state machine, collisions |
| `GamePostLogicHook` | `gamestatus.asm` | after `TilemapUpdateCamera`/`TilemapUpdateWater` | HUD, survival timers, particles |
| `GameActorPhaseHook` | `gamestatus.asm` | after `AnimateEnemies`, before `TilemapDrawPushBlocks` | game-driven actor animation |
| `GameDrawEntitiesHook` | `gamestatus.asm` | after `TilemapDrawPushBlocks`, before `FlushDirtyTiles` | draw remaining entities |
| `GameUnpauseHook` | `pause_system.asm`, `debug_hud.asm` | pause banner or debug HUD erased | invalidate anything that must redraw |
| `GameDebugCountHook` | `debug_hud.asm` | overlay refresh | `d0.w` = count to show |
| `GameSnapshotSaveHook` | `undo.asm` `TakeSnapshot` | after map/actors/water saved | copy game state into slot `a0` |
| `GameUndoEraseHook` | `undo.asm` `UndoMove` | after `TilemapErasePlayer` | erase the game's on-screen entities |
| `GameSnapshotRestoreHook` | `undo.asm` `UndoMove` | after map/actors/water restored | copy game state out of slot `a0` |
| `GameUndoRedrawHook` | `undo.asm` `UndoMove` | after player redrawn | redraw entities and HUD |
| `GameEnemySheetHook` | `entities.asm` `TilemapDrawEnemy` | every enemy blit | `a1` = colour sheet base (in: `EnemySpritesRaw`); may use `d3-d4` only |
| `GameEnemyOverlayHook` | `entities.asm` `TilemapDrawEnemy` | after the enemy blit | draw over the enemy box at `a2` (`d0` = world X); preserve all registers |
| `GamePushMoveHook` | `actor_physics.asm` `PlayerMoveActor` | a crate starts moving | start the player's move into the vacated cell; the engine then sets `ACTION_PUSH` |
| `GameActorImpactHook` | `actor_physics.asm` `ActionFallActors` | each landing-effect tick | draw frame `d2.w` at pixel (`d0`,`d1`); preserve `d6-d7/a2-a3` |

The engine preserves `a0` around the three undo hooks that receive it.

**Frame entry.** `engine_main.asm` calls `GameStatusRun` every frame. Include
`engine/gameplay/gamestatus.asm` to get the engine's state-machine dispatcher,
or define your own (as `games/starter/main.asm` does).

**Audio contract routines.** Engine screens call `AudioPlayTitleMusic`,
`AudioPlayLevelMusic`, `AudioPlayLevelComplete`, `AudioPlayGameCompleteMusic`,
`AudioPlayGameOver`, `AudioPlayIntroFanfare`, `AudioPlayRewind` and
`AudioPlayAirBubble`; `actor_physics.asm` adds `AudioPlayCratePush` and
`AudioPlayCrateImpact`. Define each (an `rts` is fine); see
`games/duck_rescue/include/game_audio.asm`.

**Data bindings.** A few engine fallbacks name data the game supplies:
`LevelDefaultPalette`, `LevelDefaultPlatformMap`, `LevelDefaultEnemyList`,
`LevelDefaultMusic` (used when no `LevelDef` is active), `TitleHeroRaw`/
`TitleHeroPal`, `GameCompleteHeroRaw`, `LevelCompletePortraitRaw`/`Pal`,
`TitleLogoRaw`/`Pal`, `LoadingRawZ`/`LoadingPal`, `GameInstructionsHeadings`/`GameInstructionsText`
(four heading and ten line pointers for the gameplay page of the instructions screen),
`GameLevelDefPointerFields` (word offsets of the game's own LevelDef pointer
fields, -1 terminated, rebased by the custom-level loader), and, for
`entities.asm`, the Chip RAM sheets `EnemySpritesMsk`/`EnemySpritesRaw` and
`FriendSpritesMsk`/`FriendSpritesRaw`. The entity spawners read
`LevelDef_EnemyList`, `LevelDef_FriendList` and `LevelDef_PickupList` from the
game's LevelDef (records described in `entities.asm`).
Bind them in `main.asm` next to the data (`LevelDefaultPalette = Level_01_Palette`).
A binding that emits bytes (such as the `GameLevelDefPointerFields` table) must be
placed after the `engine_main.asm` include, in the code or a data section: anything an
include emits before it lands in front of `Main` and becomes the program entry point.

**Snapshot struct.** `engine/include/engine_snapshot.i` opens the `Snap_*`
struct with the fields the engine serialises (map, actors, water). Your
struct file includes it first, appends what your save/restore hooks copy,
and closes with `Snap_Sizeof`. `SnapshotBuffer` holds `UNDO_BUFFER_SIZE`
slots of that size.
