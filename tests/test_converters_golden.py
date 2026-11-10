"""
test_converters_golden.py - golden-file tests for the Python asset converters.

Run from the repo root:
    python -m unittest discover tests
or, with pytest installed:
    python -m pytest tests

Two checks:
  1. Running the pipeline in a scratch copy of games/duck_rescue/ produces
     exactly the files, with exactly the contents, recorded in
     tests/golden/duck_rescue_converters.json.
  2. The converted assets committed in the repository match that same golden
     file, so a checkout is never out of sync with its converters.

To accept an intentional converter or source-art change, regenerate the
golden file with:  python tests/update_golden.py
"""

import unittest
from pathlib import Path

from golden_support import (
    DEFAULT_GAME, REPO_ROOT, describe_diff, golden_path, load_golden, run_pipeline, sha256_of,
)


class ConverterGoldenTests(unittest.TestCase):
    game = DEFAULT_GAME

    @classmethod
    def setUpClass(cls):
        if not golden_path(cls.game).exists():
            raise unittest.SkipTest(
                f"no golden file at {golden_path(cls.game)}; run python tests/update_golden.py"
            )
        cls.golden = load_golden(cls.game)
        cls.actual = run_pipeline(cls.game)

    def test_pipeline_produces_golden_outputs(self):
        self.assertEqual(
            self.golden, self.actual,
            "\n" + describe_diff(self.golden, self.actual),
        )

    def test_committed_assets_match_golden(self):
        game_dir = REPO_ROOT / "games" / self.game
        stale = []
        for rel, sha in self.golden.items():
            committed = game_dir / Path(rel)
            if not committed.exists():
                stale.append(f"{rel} (missing from repository)")
            elif sha256_of(committed) != sha:
                stale.append(rel)
        self.assertEqual(
            stale, [],
            "Committed assets differ from converter output; rebuild with "
            "`python tools/build.py --assets` and commit the result:\n  " + "\n  ".join(stale),
        )


if __name__ == "__main__":
    unittest.main()
