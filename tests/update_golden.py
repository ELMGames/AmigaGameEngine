#!/usr/bin/env python3
"""
update_golden.py - regenerate tests/golden/<game>_converters.json.

Runs the asset pipeline in a scratch copy of games/<game>/ and records a
SHA-256 for every file it produces. Run this after an intentional change to
a converter or to source art, then review the diff of the golden file in
git before committing it.

Usage:
    python tests/update_golden.py            # duck_rescue
    python tests/update_golden.py --game X   # another game under games/
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from golden_support import DEFAULT_GAME, describe_diff, golden_path, load_golden, run_pipeline, save_golden


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--game", default=DEFAULT_GAME, help="game directory under games/ (default: duck_rescue)")
    parser.add_argument("--executables", action="store_true",
                        help="instead of converter outputs, rebuild every game and record the executable hashes")
    args = parser.parse_args()

    if args.executables:
        import json
        from test_build_golden import GOLDEN, current_hashes
        hashes = current_hashes()
        GOLDEN.parent.mkdir(parents=True, exist_ok=True)
        with open(GOLDEN, "w", encoding="utf-8", newline="\n") as f:
            json.dump(hashes, f, indent=2)
            f.write("\n")
        for game, h in hashes.items():
            print(f"{game}: {h}")
        print(f"Recorded {len(hashes)} executable hashes in {GOLDEN}")
        return

    previous = load_golden(args.game) if golden_path(args.game).exists() else {}
    outputs = run_pipeline(args.game)
    save_golden(outputs, args.game)

    print(f"Recorded {len(outputs)} output files in {golden_path(args.game)}")
    if previous:
        diff = describe_diff(previous, outputs)
        print(diff.rsplit("\n", 1)[0] if diff else "No change from the previous golden file.")


if __name__ == "__main__":
    main()
