# Millie & Molly Codebase Reference Guide

> [!NOTE]
> **Single Player Migration Completed**:
> The engine has been converted to single-player mode. The second player structure (`Molly`) has been removed, and references to `Millie` have been renamed to `Player`:
> - `BLOCK_MILLIESTART` $\rightarrow$ `BLOCK_PLAYERSTART` (7)
> - `BLOCK_MILLIELADDER` $\rightarrow$ `BLOCK_PLAYERLADDER` (9)
> - `InitMillie` $\rightarrow$ `InitPlayer`
> - `Millie` struct $\rightarrow$ `Player: rs.b Player_Sizeof` (in `variables.asm`)
> - `Snap_Millie*` $\rightarrow$ `Snap_Player*` (in `struct.asm` and `undo.asm`)
> - Backward-compatibility aliases (`BLOCK_MILLIESTART = BLOCK_PLAYERSTART`, `InitMillie = InitPlayer`, `Millie = Player`, `Snap_Millie* = Snap_Player*`) are maintained.

This document catalogs every reference to **`MILLIE`** and **`MOLLY`** across the Amiga Game Engine codebase.

Originally derived from the *Millie & Molly* puzzle-platformer architecture, these identifiers represent the two playable character slots:
- **Player 1 / Millie Slot**: Dr. Price (BOB base frame offset 48, start block `BLOCK_MILLIESTART`, ladder cell `BLOCK_MILLIELADDER`).
- **Player 2 / Molly Slot**: Sgt. Cole (BOB base frame offset 0, start block `BLOCK_MOLLYSTART`, ladder cell `BLOCK_MOLLYLADDER`).

---

## 1. Architectural Summary

| Category | Identifier / Symbol | Description | File Location |
| :--- | :--- | :--- | :--- |
| **Map Identifiers** | `BLOCK_MILLIESTART = 7` | Tile ID for Player 1 spawn position in `GameMap` | [`include/resources/const.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/const.asm#L344) |
| | `BLOCK_MOLLYSTART = 8` | Tile ID for Player 2 spawn position in `GameMap` | [`include/resources/const.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/const.asm#L345) |
| | `BLOCK_MILLIELADDER = 9` | Tile ID marking a ladder cell occupied by Player 1 | [`include/resources/const.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/const.asm#L346) |
| | `BLOCK_MOLLYLADDER = 10` | Tile ID marking a ladder cell occupied by Player 2 | [`include/resources/const.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/const.asm#L347) |
| **State Structs** | `Millie` | 44-byte `Player` structure for Player 1 | [`include/resources/variables.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/variables.asm#L82) |
| | `Molly` | 44-byte `Player` structure for Player 2 | [`include/resources/variables.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/variables.asm#L83) |
| **Undo Snapshots** | `Snap_Millie*` (5 words) | X, Y, Status, Facing, OnLadder snapshot for Millie | [`include/resources/struct.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/struct.asm#L181-L185) |
| | `Snap_Molly*` (5 words) | X, Y, Status, Facing, OnLadder snapshot for Molly | [`include/resources/struct.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/struct.asm#L186-L190) |
| **Initializers** | `InitMillie` | Initializes Millie struct with frame 48, ladder freeze 34 | [`include/resources/actors.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/actors.asm#L285) |
| | `InitMolly` | Initializes Molly struct with frame 0, ladder freeze 33 | [`include/resources/actors.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/actors.asm#L303) |
| **Portraits / UI** | `LC_OFF_MILLIE` | Level complete portrait screen offset for Player 1 | [`include/resources/levelcomplete.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/levelcomplete.asm#L58) |
| | `LC_OFF_MOLLY` | Level complete portrait screen offset for Player 2 | [`include/resources/levelcomplete.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/levelcomplete.asm#L59) |
| | `MilliePic`, `MollyPic` | Portrait binary asset labels (stubbed in Chip RAM) | [`include/resources/copperlists.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/copperlists.asm#L548-L549) |

---

## 2. Core Assembly References by File

### [`include/resources/variables.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/variables.asm)
Allocates the memory structures for both player instances in the fast variables block:
- **L77-L79**: Header comment explaining structure usage and frame offsets:
  ```asm
  ; Millie / Molly - the actual Player structure data (Player_Sizeof bytes each).
  ;   Millie/Price uses BOB frames starting at offset 48 in PlayerRaw/Msk.
  ;   Molly/Cole   uses BOB frames starting at offset  0 in PlayerRaw/Msk.
  ```
- **L82**: `Millie:               rs.b    Player_Sizeof   ; Millie's player structure`
- **L83**: `Molly:                rs.b    Player_Sizeof   ; Molly's  player structure`

---

### [`include/resources/struct.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/struct.asm)
Defines structure field equates and undo buffer layouts:
- **L25-L26**: Comment: `; Holds the complete state of one player character (Millie or Molly)... Two of these live in the Variables block: Millie and Molly.`
- **L53**: Comment: `; Player_BlockId - BLOCK_MILLIESTART or BLOCK_MOLLYSTART...`
- **L55**: Comment: `; Player_LadderId - BLOCK_MILLIELADDER or BLOCK_MOLLYLADDER...`
- **L83**: `Player_BlockId:           rs.b    1   ; BLOCK_MILLIESTART or BLOCK_MOLLYSTART`
- **L84**: `Player_LadderId:          rs.b    1   ; BLOCK_MILLIELADDER or BLOCK_MOLLYLADDER`
- **L181-L185**: Snapshot fields for Millie:
  - `Snap_MillieX:             rs.w    1   ; Millie tile column`
  - `Snap_MillieY:             rs.w    1   ; Millie tile row`
  - `Snap_MillieStatus:        rs.w    1   ; Millie Player_Status (0/1/2)`
  - `Snap_MillieFacing:        rs.w    1   ; Millie Player_Facing (+1/-1)`
  - `Snap_MillieOnLadder:      rs.w    1   ; Millie Player_OnLadder (0/nonzero)`
- **L186-L190**: Snapshot fields for Molly:
  - `Snap_MollyX:              rs.w    1   ; Molly tile column`
  - `Snap_MollyY:              rs.w    1   ; Molly tile row`
  - `Snap_MollyStatus:         rs.w    1   ; Molly Player_Status`
  - `Snap_MollyFacing:         rs.w    1   ; Molly Player_Facing`
  - `Snap_MollyOnLadder:       rs.w    1   ; Molly Player_OnLadder`

---

### [`include/resources/const.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/const.asm)
Defines constants, tile block IDs, and sprite/portrait equates:
- **L344**: `BLOCK_MILLIESTART   = 7    ; Millie start position marker in level data`
- **L345**: `BLOCK_MOLLYSTART    = 8    ; Molly start position marker in level data`
- **L346**: `BLOCK_MILLIELADDER  = 9    ; map cell occupied by Millie while on a ladder`
- **L347**: `BLOCK_MOLLYLADDER   = 10   ; map cell occupied by Molly while on a ladder`
- **L528**: `REALSPRITES_FRAMES  = 96   ; 48 frames * 2 characters (Molly=0..47, Millie=48..95)`
- **L530**: `FACE_SIZE           = 2560 ; one face graphic (millie.raw / molly.raw)`
- **L734**: Comment: `; diagonally opposite to Molly's start position toward`
- **L750-L751**: Comment:
  ```asm
  ;   switching Molly->Millie : SPRITE_STAR_LARGE_BLUE       (blue)
  ;   switching Millie->Molly : SPRITE_STAR_LARGE_YELLOW     (yellow)
  ```

---

### [`include/resources/actors.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/actors.asm)
Handles actor initialization and object table dispatching:
- **L13**: Comment: `; - Millie / Molly (player characters - special initialisation path)`
- **L128-L129**: Comment: `; BLOCK_MILLIESTART(7) -> InitMillie`, `; BLOCK_MOLLYSTART (8) -> InitMolly`
- **L145-L148**: Object dispatch table entries:
  ```asm
  dc.w        InitMillie-.i              ; BLOCK_MILLIESTART = 7
  dc.w        InitMolly-.i               ; BLOCK_MOLLYSTART  = 8
  dc.w        InitDummy-.i               ; BLOCK_MILLIELADDER= 9  (never in level data)
  dc.w        InitDummy-.i               ; BLOCK_MOLLYLADDER = 10 (never in level data)
  ```
- **L274-L293**: `InitMillie` routine:
  ```asm
  InitMillie:
      lea         Millie(a5),a4              ; a4 -> Millie player structure
      move.w      #48,Player_BobOffset(a4)        ; Millie's BOB base = frame 48
      move.w      #31,Player_FrozenBobBase(a4)    ; Millie's frozen BOB (right-facing)
      move.w      #34,Player_LadderFreezeId(a4)   ; ladder freeze frame index
      move.b      #BLOCK_MILLIESTART,Player_BlockId(a4)    ; map cell type for Millie's presence
      move.b      #BLOCK_MILLIELADDER,Player_LadderId(a4)  ; map cell type when on ladder
      bsr         InitPlayer
  ```
- **L297-L311**: `InitMolly` routine:
  ```asm
  InitMolly:
      lea         Molly(a5),a4               ; a4 -> Molly player structure
      move.w      #0,Player_BobOffset(a4)         ; Molly's BOB base = frame 0
      move.w      #29,Player_FrozenBobBase(a4)    ; Molly's frozen BOB (right-facing)
      move.w      #33,Player_LadderFreezeId(a4)   ; ladder freeze frame index
      move.b      #BLOCK_MOLLYSTART,Player_BlockId(a4)    ; map cell type for Molly's presence
      move.b      #BLOCK_MOLLYLADDER,Player_LadderId(a4)  ; map cell type when on ladder
      bsr         InitPlayer
  ```
- **L315, L323-L324, L329**: Comments in `InitPlayer` referencing `InitMillie` and `InitMolly`.

---

### [`include/resources/player.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/player.asm)
Player movement, collision logic, and ladder traversal:
- **L71, L96, L123**: Function comments specifying `a4 = pointer to Player structure (Millie or Molly)`.
- **L1642-L1644**: Ladder top exit checks:
  ```asm
  cmp.b       #BLOCK_MILLIELADDER,d3
  beq.s       .step_off_ok
  cmp.b       #BLOCK_MOLLYLADDER,d3
  beq.s       .step_off_ok
  ```
- **L1649**: `move.b Player_LadderId(a4),d4 ; use ladder-specific ID (MILLIELADDER/MOLLYLADDER)`
- **L1659-L1661**: Current ladder cell verification (`BLOCK_MILLIELADDER` / `BLOCK_MOLLYLADDER`).
- **L1721-L1723**: Ladder bottom boundary check (`cmp.b #BLOCK_MILLIELADDER,d2`, `cmp.b #BLOCK_MOLLYLADDER,d2`).
- **L1867-L1869**: Horizontal dismount check (`cmp.b #BLOCK_MILLIELADDER,d1`, `cmp.b #BLOCK_MOLLYLADDER,d1`).
- **L1946-L1948**: Idle pose check on ladder (`cmp.b #BLOCK_MILLIELADDER,d1`, `cmp.b #BLOCK_MOLLYLADDER,d1`).
- **L2084-L2087**: Movement collision dispatch table comments:
  ```asm
  ;   BLOCK_MILLIESTART -> PlayerNotMove   (can't walk into the other player's cell)
  ;   BLOCK_MOLLYSTART  -> PlayerNotMove
  ;   BLOCK_MILLIELADDER-> PlayerMoveLadder (move along while on ladder)
  ;   BLOCK_MOLLYLADDER -> PlayerMoveLadder
  ```
- **L2106-L2109**: Movement dispatch jump table entries:
  ```asm
  dc.w        PlayerNotMove-.i      ; BLOCK_MILLIESTART = 7
  dc.w        PlayerNotMove-.i      ; BLOCK_MOLLYSTART  = 8
  dc.w        PlayerMoveLadder-.i   ; BLOCK_MILLIELADDER= 9
  dc.w        PlayerMoveLadder-.i   ; BLOCK_MOLLYLADDER = 10
  ```
- **L2159**: Comment: `; If the next cell is BLOCK_MILLIELADDER or BLOCK_MOLLYLADDER (the other player...`

---

### [`include/resources/levelutils.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/levelutils.asm)
Level loading, pointer setup, and map tile scanning:
- **L39-L40**: Comment: `; 2. Clear Player_Status for both Millie and Molly... 3. Set PlayerPtrs: Millie -> [0], Molly -> [1]`
- **L58-L59**: `lea Millie(a5),a0`, `clr.w Player_Status(a0) ; Millie inactive`
- **L77**: `move.l a0,PlayerPtrs(a5) ; PlayerPtrs[0] -> Millie`
- **L79-L80**: `lea Molly(a5),a0`, `clr.w Player_Status(a0) ; Molly inactive`
- **L98**: `move.l a0,PlayerPtrs+4(a5) ; PlayerPtrs[1] -> Molly`
- **L162-L163**: Setup Player 1 from `LevelDef`:
  ```asm
  ; Setup Player 1 (Millie/Price) from LevelDef
  lea           Millie(a5),a0
  ```
- **L183-L184**: Assigning Player 1 block IDs:
  ```asm
  move.b        #BLOCK_MILLIESTART,Player_BlockId(a0)
  move.b        #BLOCK_MILLIELADDER,Player_LadderId(a0)
  ```
- **L190-L191**: Assigning Player 2 block IDs:
  ```asm
  move.b        #BLOCK_MOLLYSTART,Player_BlockId(a0)
  move.b        #BLOCK_MOLLYLADDER,Player_LadderId(a0)
  ```
- **L256**: Comment: `; BLOCK_MILLIESTART (7) or BLOCK_MOLLYSTART (8) it writes the tile column and...`
- **L275-L279**: Scan for Millie start:
  ```asm
  cmp.b       #BLOCK_MILLIESTART,d0
  bne         .check_molly
  ; Found Millie start — write tile coords to Millie struct
  lea         Millie(a5),a1
  ```
- **L284-L289**: Scan for Molly start:
  ```asm
  .check_molly
  cmp.b       #BLOCK_MOLLYSTART,d0
  ; Found Molly start — write tile coords to Molly struct
  lea         Molly(a5),a1
  ```
- **L534, L536**: Level intro ladder detection:
  ```asm
  cmp.b       #BLOCK_MILLIELADDER,d1
  beq.s       .lis_is_ladder
  cmp.b       #BLOCK_MOLLYLADDER,d1
  beq.s       .lis_is_ladder
  ```

---

### [`include/resources/undo.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/undo.asm)
Game state rewind and snapshot buffer:
- **L44**: Comment: `; Saves: Millie and Molly (X/Y/Status/Facing/OnLadder), the full GameMap`
- **L64-L70**: Saving Millie snapshot:
  ```asm
  ; Save Millie (5 words)
  lea         Millie(a5),a1
  move.w      Player_X(a1),Snap_MillieX(a0)
  move.w      Player_Y(a1),Snap_MillieY(a0)
  move.w      Player_Status(a1),Snap_MillieStatus(a0)
  move.w      Player_Facing(a1),Snap_MillieFacing(a0)
  move.w      Player_OnLadder(a1),Snap_MillieOnLadder(a0)
  ```
- **L72-L78**: Saving Molly snapshot:
  ```asm
  ; Save Molly (5 words)
  lea         Molly(a5),a1
  move.w      Player_X(a1),Snap_MollyX(a0)
  move.w      Player_Y(a1),Snap_MollyY(a0)
  move.w      Player_Status(a1),Snap_MollyStatus(a0)
  move.w      Player_Facing(a1),Snap_MollyFacing(a0)
  move.w      Player_OnLadder(a1),Snap_MollyOnLadder(a0)
  ```
- **L176-L182**: Restoring Millie snapshot:
  ```asm
  ; Restore Millie
  lea         Millie(a5),a1
  move.w      Snap_MillieX(a0),Player_X(a1)
  move.w      Snap_MillieY(a0),Player_Y(a1)
  move.w      Snap_MillieStatus(a0),Player_Status(a1)
  move.w      Snap_MillieFacing(a0),Player_Facing(a1)
  move.w      Snap_MillieOnLadder(a0),Player_OnLadder(a1)
  ```
- **L198-L204**: Restoring Molly snapshot:
  ```asm
  ; Restore Molly
  lea         Molly(a5),a1
  move.w      Snap_MollyX(a0),Player_X(a1)
  move.w      Snap_MollyY(a0),Player_Y(a1)
  move.w      Snap_MollyStatus(a0),Player_Status(a1)
  move.w      Snap_MollyFacing(a0),Player_Facing(a1)
  move.w      Snap_MollyOnLadder(a0),Player_OnLadder(a1)
  ```
- **L279-L287**: Restoring active player pointer:
  ```asm
  lea         Millie(a5),a1
  lea         Molly(a5),a2
  tst.w       Snap_ActivePlayer(a0)
  beq         .millie_active
  move.l      a2,PlayerPtrs(a5)          ; Molly is active
  bra.s       .active_done
  .millie_active
  move.l      a1,PlayerPtrs(a5)          ; Millie is active
  ```

---

### [`include/resources/levelcomplete.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/levelcomplete.asm)
Victory screen player portrait positioning:
- **L21**: Comment: `; Portraits (assets/millie_pic.raw, molly_pic.raw):`
- **L58-L59**: Screen X offset equates:
  ```asm
  LC_OFF_MILLIE  = LC_OFF_PORTRAIT+0     ; Player 1 portrait at byte X=0 (0..63 px)
  LC_OFF_MOLLY   = LC_OFF_PORTRAIT+32    ; Player 2 portrait at byte X=32 (256..319 px)
  ```
- **L192, L194**: Testing character status:
  ```asm
  tst.w       Millie+Player_Status(a5)
  tst.w       Molly+Player_Status(a5)
  ```
- **L198-L203, L216-L217, L223-L224**: Blitting portraits (`MilliePic`, `MollyPic`, `LC_OFF_MILLIE`, `LC_OFF_MOLLY`).

---

### [`include/resources/copperlists.asm`](file:///F:/GitHub/AmigaGameEngine/include/resources/copperlists.asm)
Legacy labels for portrait graphics:
- **L547-L549**:
  ```asm
  ; Millie and Molly face graphics removed (freed 5,120 bytes Chip RAM).
  MilliePic:
  MollyPic:
  ```

---

## 3. Tools & Build Scripts

### [`tools/export_level.py`](file:///F:/GitHub/AmigaGameEngine/tools/export_level.py)
Tiled TMX export utility:
- **L51-L52**: Constants for collision generation:
  ```python
  BLOCK_MILLIESTART = 7
  BLOCK_MOLLYSTART  = 8
  ```
- **L523-L533**: Parsing Tiled object tags and names for `"molly"` and `"millie"`:
  ```python
  if "molly" in tag or "molly" in name_lower or ...:
      player2_start = {...}
  elif "millie" in tag or "millie" in name_lower or ...:
      player_start = {...}
  ```
- **L767, L772**: Writing player spawn blocks into the binary 1D GameMap:
  ```python
  gamemap[player_start["row"] * width + player_start["col"]] = BLOCK_MILLIESTART
  gamemap[player2_start["row"] * width + player2_start["col"]] = BLOCK_MOLLYSTART
  ```

### [`tools/chip_ram_report.py`](file:///F:/GitHub/AmigaGameEngine/tools/chip_ram_report.py)
Memory analysis tool:
- **L3**: Script description: `chip_ram_report.py — Amiga Chip RAM usage summary for Millie & Molly.`
- **L48, L50**: File paths: `assets/graphics/title/336x200/millie_molly_336x200.zx0`, `millie_molly_336x200.pal`
- **L68**: Music tracker module: `assets/music/millie_&_molly.mod`
- **L92, L94**: Face graphics paths: `assets/graphics/face/millie.zx0`, `assets/graphics/face/molly.zx0`
- **L150, L151**: Memory map labels: `"MillieFace"`, `"MollyFace"`

### [`tools/convert_png_to_sprites.py`](file:///F:/GitHub/AmigaGameEngine/tools/convert_png_to_sprites.py)
- **L15-L17, L25-L27**: Tile table comments and lists for standing/ladder freeze frames (`Molly=33`, `Millie=34`).

### [`tools/draw_players.py`](file:///F:/GitHub/AmigaGameEngine/tools/draw_players.py)
- **L12-L13**: Comment: `sprite frames (48 per character; Cole base 0 [was Molly], Price base 48 [was Millie])`
- **L394**: Comment: `# 2. hardware sprites: Cole = base 0 (Molly slot), Price = base 48 (Millie)`

---

## 4. Documentation & Asset Notes

- **[`docs/CONVERT_TO_BOB.md`](file:///F:/GitHub/AmigaGameEngine/docs/CONVERT_TO_BOB.md#L222)**: Reference to base frame index `(Molly=0, Millie=48)`.
- **[`docs/GAME_CONCEPTS_LEVEL1.md`](file:///F:/GitHub/AmigaGameEngine/docs/GAME_CONCEPTS_LEVEL1.md#L117)**: Ladder collision code snippet (`cmp.b #BLOCK_MILLIELADDER,d2`, `cmp.b #BLOCK_MOLLYLADDER,d2`).
- **[`docs/WATER_IMPL.md`](file:///F:/GitHub/AmigaGameEngine/docs/WATER_IMPL.md#L893)**: Reference to player character `(Millie / Molly)`.
- **[`docs/assembly_file_summary.txt`](file:///F:/GitHub/AmigaGameEngine/docs/assembly_file_summary.txt#L13)**: Description of `copperlists.asm` containing portrait incbins `(MilliePic, MollyPic)`.
- **[`assets/graphics/sprites/player_hwsprites.txt`](file:///F:/GitHub/AmigaGameEngine/assets/graphics/sprites/player_hwsprites.txt#L3)**: Sprite layout specification for Millie and Molly frames.
