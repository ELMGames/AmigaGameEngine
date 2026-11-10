"""
test_level_lint.py - the level exporter's layout checks (Chapter 28, rule 1).

  1. Each ladder rule fires on a small map built to break it.
  2. The shipped levels export with no layout warnings.

Run from the repo root:  python -m unittest discover tests
"""

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

REPO_ROOT = Path(__file__).resolve().parent.parent
TOOLS = REPO_ROOT / "games" / "duck_rescue" / "tools"
sys.path.insert(0, str(TOOLS))
import export_level as ex  # noqa: E402

W = H = 5


def lint(ladders, platforms, extra_solid=()):
    """Run the lint on a 5x5 map: platforms and extra cells solid, ladders on top."""
    gamemap = [ex.BLOCK_EMPTY] * (W * H)
    for idx in set(platforms) | set(extra_solid):
        gamemap[idx] = ex.BLOCK_SOLID
    for idx in ladders:
        gamemap[idx] = ex.BLOCK_LADDER
    lv = SimpleNamespace(width=W, height=H, gamemap=gamemap,
                         ladder_cells=set(ladders), platform_cells=set(platforms))
    return ex._lint_layout(lv)


def cell(col, row):
    return row * W + col


FLOOR = [cell(c, 4) for c in range(W)]
WALKWAY = [cell(c, 1) for c in (0, 1, 3, 4)]       # gap at column 2 for the ladder


class LevelLintTests(unittest.TestCase):
    def test_good_ladder_has_no_warnings(self):
        ladder = [cell(2, r) for r in (1, 2, 3)]       # top in the walkway gap, bottom above the floor
        self.assertEqual(lint(ladder, FLOOR + WALKWAY), [])

    def test_ladder_over_floor_is_reported(self):
        ladder = [cell(2, r) for r in (1, 2, 3, 4)]    # runs into the floor row
        warnings = lint(ladder, FLOOR + WALKWAY)
        self.assertTrue(any("rule 1b" in w for w in warnings), warnings)

    def test_ladder_ending_in_mid_air_is_reported(self):
        ladder = [cell(2, r) for r in (1, 2)]          # stops above an empty cell
        warnings = lint(ladder, FLOOR + WALKWAY)
        self.assertTrue(any("rule 1c" in w for w in warnings), warnings)

    def test_ladder_top_without_walkway_is_reported(self):
        ladder = [cell(2, r) for r in (1, 2, 3)]       # no solid tile beside the top rung
        warnings = lint(ladder, FLOOR)
        self.assertTrue(any("rule 1a" in w for w in warnings), warnings)

    def test_shipped_levels_have_no_layout_warnings(self):
        levels = sorted((REPO_ROOT / "games" / "duck_rescue" / "assets" / "levels").glob("Level_*/*.tmx"))
        self.assertTrue(levels)
        for tmx in levels:
            lv = SimpleNamespace(tmx_file=str(tmx), out_dir=None, asm_out=None, prefix=None, package_out=None)
            ex._parse_header(lv)
            ex._parse_tile_layers(lv)
            ex._parse_object_layers(lv)
            ex._build_gamemap(lv)
            self.assertEqual(ex._lint_layout(lv), [], tmx.name)


if __name__ == "__main__":
    unittest.main()
