"""
test_engine_contract.py - structural checks on the engine/game contract.

  1. Reachability: every engine source file is included by at least one
     game's build. A file nobody includes is dead code (the 2026-10 sweep
     found 4,586 such lines once; this keeps them from coming back).
  2. Hook contract: every Game*Hook and AudioPlay* routine the engine
     calls is defined by every game whose build includes the caller.
  3. No game names in engine code: engine routines never branch to a
     symbol that only a game defines, other than the hooks above.
  4. Clean entry point: nothing included before engine_main.asm emits
     bytes. AmigaDOS runs the first hunk, so a stray table or routine in
     a constants/struct include becomes the program entry (a 2026-10
     crash at launch came from exactly that).
  5. No file falls off its end: the last byte-emitting statement of every
     included code file is rts/bra/jmp or data. A routine that relied on
     falling through to the next routine breaks silently when one of them
     moves to another file (the 2026-10 missing-sky bug: a moved routine ran
     into TilemapDisableCopperSky, the first routine of the next include).

Run from the repo root:  python -m unittest discover tests
"""

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asm_includes import (REPO_ROOT, called_symbols, defined_symbols, emitting_statements,  # noqa: E402
                          falls_off_end, include_graph, includes_before)

ENGINE = REPO_ROOT / "engine"
GAMES = [p for p in (REPO_ROOT / "games").iterdir() if (p / "main.asm").is_file()]
# Vendored code and the OS system includes (anchored to engine/ so a game's own include/graphics is not skipped).
THIRD_PARTY = ("ptplayer", "engine/include/exec", "engine/include/graphics", "engine/include/hardware")
# Routines the engine may call that a game supplies: the Game*Hook set, the AudioPlay*
# routines, and GameStatusRun (the per-frame entry; engine/gameplay/gamestatus.asm
# provides it when included, otherwise the game does, as games/starter does).
HOOK_PATTERN = r"Game[A-Za-z0-9]+Hook|AudioPlay[A-Za-z0-9]+|GameStatusRun"
# Engine files intentionally not built by any current game. Each needs a reason.
KEPT_UNBUILT = {
    "engine/graphics/tile_renderer.asm": "DrawSprite kept for the next game; its TILE_* contract is documented in ENGINE_CONTRACT.md section 9",
}


def engine_sources():
    for p in ENGINE.rglob("*"):
        if p.suffix in (".asm", ".i") and not any(t in p.as_posix() for t in THIRD_PARTY):
            yield p.resolve()


class EngineContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.graphs = {g.name: include_graph(g / "main.asm") for g in GAMES}
        cls.reached = set().union(*cls.graphs.values())

    def test_every_engine_file_is_built_by_some_game(self):
        unreached = sorted(p.relative_to(REPO_ROOT).as_posix() for p in engine_sources()
                           if p not in self.reached and p.relative_to(REPO_ROOT).as_posix() not in KEPT_UNBUILT)
        self.assertEqual(unreached, [], "engine files no game includes (dead code? add to KEPT_UNBUILT with a reason):\n  " + "\n  ".join(unreached))

    def test_each_game_defines_every_hook_its_build_calls(self):
        missing = []
        for game, files in self.graphs.items():
            engine_files = [f for f in files if ENGINE in f.parents]
            game_files = [f for f in files if ENGINE not in f.parents]
            needed = called_symbols(engine_files, HOOK_PATTERN)
            have = defined_symbols(game_files) | defined_symbols(engine_files)   # gamestatus.asm supplies GameStatusRun
            for hook, callers in sorted(needed.items()):
                if hook not in have:
                    where = ", ".join(sorted(c.name for c in callers))
                    missing.append(f"{game}: {hook} (called from {where})")
        self.assertEqual(missing, [], "hooks called by the engine but not defined by the game:\n  " + "\n  ".join(missing))

    def test_engine_calls_only_engine_routines_and_hooks(self):
        offenders = []
        for game, files in self.graphs.items():
            engine_files = [f for f in files if ENGINE in f.parents]
            game_files = [f for f in files if ENGINE not in f.parents]
            engine_defs = defined_symbols(engine_files)
            game_defs = defined_symbols(game_files)
            calls = called_symbols(engine_files, r"[A-Za-z_][A-Za-z0-9_]*")
            for name, callers in sorted(calls.items()):
                if name in game_defs and name not in engine_defs and not re.fullmatch(HOOK_PATTERN, name):
                    offenders.append(f"{game}: {name} <- {', '.join(sorted(c.name for c in callers))}")
        self.assertEqual(offenders, [], "engine code branching to game-only routines (add a hook instead):\n  " + "\n  ".join(offenders))

    def test_no_include_file_falls_off_its_end(self):
        offenders = []
        for f in sorted(self.reached):
            if f.name == "main.asm" or any(t in f.as_posix() for t in THIRD_PARTY):
                continue
            hit = falls_off_end(f)
            if hit:
                offenders.append(f"{f.relative_to(REPO_ROOT).as_posix()}:{hit[0]} ends with '{hit[1]}'")
        self.assertEqual(offenders, [], "included files whose last code statement is not rts/bra/jmp (control "
                                        "runs into the next include; end the routine explicitly):\n  " + "\n  ".join(offenders))

    def test_nothing_emits_bytes_before_the_entry_point(self):
        offenders = []
        for g in GAMES:
            files = includes_before(g / "main.asm", "engine_main.asm")
            self.assertTrue(files, f"{g.name}: no includes found before engine_main.asm")
            for f, line, op in emitting_statements(files):
                offenders.append(f"{g.name}: {f.relative_to(REPO_ROOT).as_posix()}:{line} ({op})")
        self.assertEqual(offenders, [], "code or data emitted before engine_main.asm would become the program "
                                        "entry point; move it after that include (game_hooks.asm or a data section):\n  "
                                        + "\n  ".join(offenders))


if __name__ == "__main__":
    unittest.main()
