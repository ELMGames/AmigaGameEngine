"""
test_build_golden.py - pin the built executables of every game.

The vasm/vlink hunk output is fully reproducible for a given toolchain
version, so each game's executable is recorded as a SHA-256 in
tests/golden/executables.json. Any assembly change that alters generated
code fails this test until the hash is regenerated deliberately with
    python tests/update_golden.py --executables
(after the new build has been played in an emulator).

Skipped when the toolchain is not available (build.find_toolchain() is None).
"""

import json
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from golden_support import GOLDEN_DIR, REPO_ROOT, sha256_of  # noqa: E402

sys.path.insert(0, str(REPO_ROOT))
import build  # noqa: E402

GOLDEN = GOLDEN_DIR / "executables.json"
GAMES = {"starter": "uae/dh0/starter", "duck_rescue": "uae/dh0/main"}


def build_game(game):
    """Build one game with build.py; return the output path. Raises on failure."""
    out = REPO_ROOT / GAMES[game]
    if out.exists():
        out.unlink()
    res = subprocess.run([sys.executable, str(REPO_ROOT / "build.py"), "--game", game, "--out", GAMES[game]],
                         cwd=REPO_ROOT, capture_output=True, text=True)
    if res.returncode != 0 or "== OK:" not in res.stdout or not out.exists():
        raise RuntimeError(f"build of {game} failed:\n{res.stdout[-2000:]}\n{res.stderr[-2000:]}")
    return out


def current_hashes():
    return {game: sha256_of(build_game(game)) for game in GAMES}


class BuildGoldenTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if build.find_toolchain() is None:
            raise unittest.SkipTest("vasm/vlink not found; set AMIGA_TOOLCHAIN to run the build tests")
        if not GOLDEN.exists():
            raise unittest.SkipTest(f"no {GOLDEN}; run python tests/update_golden.py --executables")
        with open(GOLDEN, encoding="utf-8") as f:
            cls.expected = json.load(f)
        cls.actual = current_hashes()

    def test_executables_match_golden(self):
        diffs = [f"{g}: expected {self.expected.get(g, '?')[:16]}… got {h[:16]}…"
                 for g, h in self.actual.items() if self.expected.get(g) != h]
        self.assertEqual(diffs, [], "executable changed; if intended and emulator-verified, run "
                                    "python tests/update_golden.py --executables\n  " + "\n  ".join(diffs))


if __name__ == "__main__":
    unittest.main()
