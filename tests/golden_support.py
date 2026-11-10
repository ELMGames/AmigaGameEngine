"""
golden_support.py - shared helpers for the asset-converter golden-file tests.

The Duck Rescue asset pipeline (the scripts listed in tools/build.py's
ASSET_PIPELINE) is deterministic: the same PNG/TMX/synth inputs always
produce the same raw/mask/palette/asm outputs. That makes it cheap to pin
every output file to a SHA-256 and detect any unintended change to a
converter.

run_pipeline() copies games/<game>/ to a scratch directory, runs every
pipeline script there exactly as build.py would (same order, same cwd), and
returns {relative path: sha256} for every file the scripts wrote (new or
rewritten, even if byte-identical). The repository itself is never written to.
"""

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GOLDEN_DIR = Path(__file__).resolve().parent / "golden"
DEFAULT_GAME = "duck_rescue"
IGNORED_DIRS = {"__pycache__"}

sys.path.insert(0, str(REPO_ROOT / "tools"))
from build import ASSET_PIPELINE  # noqa: E402  (single source of truth for the script list)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def snapshot(root):
    """{posix relative path: (mtime_ns, sha256)} for every regular file under root.

    The mtime is what identifies a file as *written* by the pipeline: the
    scratch copy already contains the committed outputs, so a converter that
    reproduces them byte-for-byte changes nothing but the timestamp.
    """
    result = {}
    for p in root.rglob("*"):
        if not p.is_file() or IGNORED_DIRS & set(p.relative_to(root).parts):
            continue
        result[p.relative_to(root).as_posix()] = (p.stat().st_mtime_ns, sha256_of(p))
    return result


def golden_path(game=DEFAULT_GAME):
    return GOLDEN_DIR / f"{game}_converters.json"


def load_golden(game=DEFAULT_GAME):
    with open(golden_path(game), encoding="utf-8") as f:
        return json.load(f)


def save_golden(outputs, game=DEFAULT_GAME):
    GOLDEN_DIR.mkdir(parents=True, exist_ok=True)
    with open(golden_path(game), "w", encoding="utf-8", newline="\n") as f:
        json.dump(dict(sorted(outputs.items())), f, indent=2)
        f.write("\n")


def run_pipeline(game=DEFAULT_GAME):
    """Run the whole asset pipeline in a scratch copy; return the files it produced."""
    source = REPO_ROOT / "games" / game
    if not source.is_dir():
        raise FileNotFoundError(f"no such game directory: {source}")

    with tempfile.TemporaryDirectory(prefix="golden_") as tmp:
        work = Path(tmp) / game
        shutil.copytree(source, work, ignore=shutil.ignore_patterns(*IGNORED_DIRS))
        before = snapshot(work)

        for script, _desc, _assets_only in ASSET_PIPELINE:
            script_path = work / "tools" / script
            if not script_path.exists():
                continue
            res = subprocess.run(
                [sys.executable, str(script_path)],
                cwd=work, capture_output=True, text=True,
            )
            if res.returncode != 0:
                raise RuntimeError(
                    f"{script} exited with {res.returncode}\n"
                    f"--- stdout ---\n{res.stdout}\n--- stderr ---\n{res.stderr}"
                )

        after = snapshot(work)

    return {rel: sha for rel, (mtime, sha) in after.items() if before.get(rel, (None, None))[0] != mtime}


def describe_diff(expected, actual):
    """Human-readable summary of how two {path: sha} dicts differ."""
    missing = sorted(set(expected) - set(actual))
    unexpected = sorted(set(actual) - set(expected))
    changed = sorted(p for p in set(expected) & set(actual) if expected[p] != actual[p])
    lines = []
    if missing:
        lines.append("Not produced any more:\n  " + "\n  ".join(missing))
    if unexpected:
        lines.append("New outputs not in golden file:\n  " + "\n  ".join(unexpected))
    if changed:
        lines.append("Contents changed:\n  " + "\n  ".join(changed))
    if lines:
        lines.append("If the change is intentional, run: python tests/update_golden.py")
    return "\n".join(lines)
