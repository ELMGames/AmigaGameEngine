#!/usr/bin/env python3
"""check_level.py - prove that Meadow Run's level can be finished.

Reads a level's exported collision map (Level_XX-gamemap.bin) and player
start (include/levels/level_xx_entities.asm) and plays it
with the same integer physics as PlayerLogic in main.asm (2 px a frame
across, jump speed 104/16 px, gravity 6/16 px a frame, feet tested one line
below the sprite, a 3-point wall test at the body's leading edge). A simple
controller runs right and jumps when there is a pit or a wall just ahead.

It reports the frame Mia reaches the signpost, or where she drowned or got
stuck, and fails if she cannot make it inside the level's time limit. If the level changes, run it again before testing in the emulator:

    python games/meadow_run/tools/check_level.py
    python games/meadow_run/tools/check_level.py --script   # also print the
                                                            # key presses (last level)

Keep the constants below in step with main.asm.
"""
import re
import sys
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]
LEVELS = GAME / "assets" / "levels"

MAP_COLS, MAP_ROWS = 128, 14
LINES = MAP_ROWS * 16
RUN_SPEED, JUMP_SPEED, GRAVITY, MAX_FALL = 2, 104, 6, 96

EMPTY, SOLID, DUCK, HAZARD, GOAL = range(5)    # const.asm CLASS_*


def load_level(name):
    data = (LEVELS / name / f"{name}-gamemap.bin").read_bytes()
    if len(data) != MAP_COLS * MAP_ROWS:
        sys.exit(f"{name}-gamemap.bin is not {MAP_COLS} x {MAP_ROWS}")
    grid = [list(data[r * MAP_COLS:(r + 1) * MAP_COLS]) for r in range(MAP_ROWS)]
    asm = (GAME / "include" / "levels" / f"{name.lower()}_entities.asm").read_text()
    words = [int(v) for v in re.findall(r"dc\.w\s+(\d+)", asm)]
    start_x, start_y, time_limit = words[0], words[1], words[2]
    return grid, start_x, start_y, time_limit


def play(grid, start_x, start_y, max_frames=5000):
    def tile(x, y):                      # TileClassAt
        if x < 0 or x >= MAP_COLS * 16:
            return SOLID
        if y < 0 or y >= LINES:
            return EMPTY
        return grid[y >> 4][x >> 4]

    x, y16, vy, ground, jump_prev = start_x, start_y * 16, 0, False, True
    presses, ducks = [], 0

    def solid_under(px, line):            # FeetOrHeadSolid
        return tile(px + 3, line) == SOLID or tile(px + 12, line) == SOLID

    for frame in range(max_frames):
        y = y16 >> 4
        pit = ground and any(tile(x + dx, y + 24) != SOLID for dx in (16, 20, 24))
        wall = any(tile(x + 13 + dx, y + yy) == SOLID for dx in (2, 4, 6) for yy in (4, 13, 22))
        jump = ground and (pit or wall) and not jump_prev
        presses.append(1 | (2 if jump else 0))       # bit 0 right, bit 1 jump

        nx = x + RUN_SPEED                           # run
        if not any(tile(nx + 13, y + 4 + 9 * i) == SOLID for i in range(3)) \
                and 4 <= nx <= MAP_COLS * 16 - 20:
            x = nx
        if jump and not jump_prev and ground:        # jump
            vy, ground = -JUMP_SPEED, False
        jump_prev = jump

        vy = min(vy + GRAVITY, MAX_FALL)             # gravity
        ny16 = y16 + vy
        ny = ny16 >> 4
        if vy >= 0 and solid_under(x, ny + 24):
            y16, vy, ground = (((ny + 24) & ~15) - 24) * 16, 0, True
        elif vy < 0 and solid_under(x, ny + 4):
            y16, vy, ground = ((((ny + 4) >> 4) + 1) * 16 - 4) * 16, 0, False
        else:
            y16, ground = ny16, False

        y = y16 >> 4
        if y >= LINES:
            return None, f"fell off the map at frame {frame}, x={x}", presses
        for py in (y + 12, y + 20):                  # what she touches
            t = tile(x + 8, py)
            if t == HAZARD:
                return None, f"drowned at frame {frame}, x={x} (column {x // 16})", presses
            if t == DUCK:
                grid[py >> 4][(x + 8) >> 4] = EMPTY
                ducks += 1
            if t == GOAL:
                return frame, (f"reached the signpost at frame {frame} "
                               f"({frame / 50:.1f} s), {ducks} ducklings on the way"), presses
    return None, f"stuck: no signpost after {max_frames} frames, x={x}", presses


def main():
    ok = True
    for level in sorted(LEVELS.glob("Level_*")):
        grid, sx, sy, limit = load_level(level.name)
        frame, result, presses = play(grid, sx, sy)
        if frame is not None and frame > limit * 50:
            result += f" - but the time limit is {limit} s"
            frame = None
        print(f"{level.name}: {'OK' if frame is not None else 'FAIL'}: {result}")
        ok = ok and frame is not None
    if "--script" not in sys.argv:
        sys.exit(0 if ok else 1)
    if "--script" in sys.argv:
        runs, last, count = [], None, 0
        for p in presses:
            if p == last:
                count += 1
            else:
                if last is not None:
                    runs.append((count, last))
                last, count = p, 1
        runs.append((count, last))
        print("AutoplayScript:")
        for n, b in runs:
            print(f"    dc.w    {n},{b}")
        print("    dc.w    0,0")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
