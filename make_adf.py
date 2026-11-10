#!/usr/bin/env python3
"""
make_adf.py - Build a bootable floppy image of the current game.

Usage:
  python make_adf.py              build adfs/game.adf for the game the root main.asm includes
  python make_adf.py --game NAME  build it for games/NAME instead

The disk holds a release build of the game (built by build.py into
build/adf/main, with no debug information), its Workbench icon if there is
one, and an S/Startup-Sequence that runs it. So the same image:
  * boots on its own from DF0:, and
  * appears as a disk icon in DF1: next to a Workbench disk in DF0:.

VS Code runs this after every build (the "build + ADF" task), so
adfs/game.adf always matches the code. It needs amitools for xdftool
(pip install amitools); without it, it prints a note and exits cleanly, so
the build still succeeds.
"""

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ADF = ROOT / "adfs" / "game.adf"


def current_game():
    """The game the root main.asm includes (games/<name>/main.asm)."""
    text = (ROOT / "main.asm").read_text(encoding="utf-8", errors="replace")
    for line in text.splitlines():
        code = line.split(";")[0]
        m = re.search(r'include\s+"games/([^/"]+)/main\.asm"', code, re.I)
        if m:
            return m.group(1)
    return "duck_rescue"


def volume_name(game):
    return " ".join(part.capitalize() for part in game.split("_"))


def main():
    parser = argparse.ArgumentParser(description="Build a bootable ADF of the current game")
    parser.add_argument("--game", default=None, help="Game under games/ (default: the one main.asm includes)")
    args = parser.parse_args()
    game = args.game or current_game()

    try:
        import amitools.tools.xdftool  # noqa: F401
    except ImportError:
        print("make_adf: amitools is not installed, so no ADF was made (pip install amitools)")
        return 0

    exe = ROOT / "build" / "adf" / "main"
    res = subprocess.run([sys.executable, str(ROOT / "build.py"), "--game", game, "--out", str(exe)])
    if res.returncode != 0:
        return res.returncode

    icon = ROOT / "uae" / "dh0" / ("main.info" if game == "duck_rescue" else f"{game}.info")

    with tempfile.TemporaryDirectory() as tmp:
        startup = Path(tmp) / "Startup-Sequence"
        startup.write_bytes(b"main\n")
        ADF.parent.mkdir(parents=True, exist_ok=True)
        if ADF.exists():
            ADF.unlink()
        cmd = [sys.executable, "-m", "amitools.tools.xdftool", str(ADF),
               "format", volume_name(game), "ofs",
               "+", "boot", "install",
               "+", "write", str(exe), "main",
               "+", "makedir", "S",
               "+", "write", str(startup), "S/Startup-Sequence"]
        if icon.exists():
            cmd += ["+", "write", str(icon), "main.info"]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            print(res.stdout + res.stderr, file=sys.stderr)
            print(f"make_adf: xdftool failed with exit code {res.returncode}", file=sys.stderr)
            return res.returncode

    size = exe.stat().st_size
    print(f"== ADF: {ADF} ({volume_name(game)}, main {size:,} bytes"
          f"{', with icon' if icon.exists() else ''}) ==")
    return 0


if __name__ == "__main__":
    sys.exit(main())
