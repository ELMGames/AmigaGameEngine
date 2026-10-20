#!/usr/bin/env python3
"""
build.py - Assemble and link the game from the command line (no VS Code needed).

Usage:
  python build.py                 build ../uae/dh0/main (same output as the VS Code task)
  python build.py --assets        regenerate converted assets first (tools/convert_assets.py)
  python build.py --out my.exe    build to a different output path
  python build.py --tool-dir <dir> use vasm/vlink from a specific directory

Toolchain resolution order:
  1. --tool-dir argument
  2. AMIGA_TOOLCHAIN environment variable
  3. vasmm68k_mot on PATH
  4. the amiga-assembly VS Code extension's bundled binaries
"""

import argparse
import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path


def find_toolchain(tool_dir_arg=None):
    if tool_dir_arg and os.path.isdir(tool_dir_arg):
        return Path(tool_dir_arg)

    env_toolchain = os.environ.get("AMIGA_TOOLCHAIN")
    if env_toolchain and os.path.isdir(env_toolchain):
        return Path(env_toolchain)

    on_path = shutil.which("vasmm68k_mot") or shutil.which("vasmm68k_mot.exe")
    if on_path:
        return Path(on_path).parent

    user_profile = os.environ.get("USERPROFILE") or os.path.expanduser("~")
    pattern = os.path.join(
        user_profile,
        ".vscode",
        "extensions",
        "prb28.amiga-assembly-*",
        "resources",
        "bin",
        "win32" if sys.platform == "win32" else "*",
    )
    matches = glob.glob(pattern)
    if matches:
        matches.sort()
        return Path(matches[-1])

    return None


def run_script(script_path, desc):
    if os.path.exists(script_path):
        print(f"== {desc} ==")
        res = subprocess.run([sys.executable, script_path])
        if res.returncode != 0:
            print(f"Error: {desc} failed with exit code {res.returncode}", file=sys.stderr)
            sys.exit(res.returncode)


def main():
    parser = argparse.ArgumentParser(description="Assemble and link Amiga game")
    parser.add_argument("--assets", action="store_true", help="Regenerate converted assets first")
    parser.add_argument("--out", default="../uae/dh0/main", help="Output path (default: ../uae/dh0/main)")
    parser.add_argument("--tool-dir", default=None, help="Directory containing vasmm68k_mot and vlink")

    args = parser.parse_args()

    project_root = Path(__file__).resolve().parent
    os.chdir(project_root)

    tool_dir = find_toolchain(args.tool_dir)
    exe_suffix = ".exe" if sys.platform == "win32" else ""
    vasm = (tool_dir / f"vasmm68k_mot{exe_suffix}") if tool_dir else None
    vlink = (tool_dir / f"vlink{exe_suffix}") if tool_dir else None

    if not vasm or not vasm.exists():
        print(
            "Error: vasm not found. Pass --tool-dir, set AMIGA_TOOLCHAIN, or install the amiga-assembly VS Code extension.",
            file=sys.stderr,
        )
        sys.exit(1)

    if args.assets:
        run_script("tools/convert_assets.py", "Converting assets")
        run_script("tools/convert_duck_banner.py", "Converting Duck Rescue Banner")
        run_script("tools/generate_sfx.py", "Generating Sound Effects")

    run_script("tools/export_level.py", "Exporting Tiled Levels")
    run_script("tools/convert_player_bob.py", "Converting Player BOB Assets")
    run_script("tools/convert_animals.py", "Converting Animal Friend Assets")
    run_script("tools/convert_enemies.py", "Converting Enemy Assets")
    run_script("tools/convert_headshots.py", "Converting Headshot Assets")

    build_dir = project_root / "build"
    build_dir.mkdir(parents=True, exist_ok=True)

    print("== Assembling main.asm ==")
    asm_cmd = [
        str(vasm),
        "-m68000",
        "-Fhunk",
        "-linedebug",
        "-ignore-mult-inc",
        "-nowarn=2047",
        "-nowarn=2069",
        "-o",
        "build/main.o",
        "main.asm",
    ]
    res = subprocess.run(asm_cmd)
    if res.returncode != 0:
        print(f"Error: Assembly failed with exit code {res.returncode}", file=sys.stderr)
        sys.exit(res.returncode)

    out_path = Path(args.out)
    if not out_path.is_absolute():
        out_path = (project_root / out_path).resolve()

    out_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"== Linking {args.out} ==")
    link_cmd = [
        str(vlink),
        "-bamigahunk",
        "-Bstatic",
        "-s",
        "-o",
        str(out_path),
        "build/main.o",
    ]
    res = subprocess.run(link_cmd)
    if res.returncode != 0:
        print(f"Error: Link failed with exit code {res.returncode}", file=sys.stderr)
        sys.exit(res.returncode)

    workspace_dh0 = (project_root / "uae/dh0/main").resolve()
    parent_dh0 = (project_root.parent / "uae/dh0/main").resolve()

    if out_path.exists():
        if workspace_dh0.parent.exists() and out_path != workspace_dh0:
            shutil.copy2(str(out_path), str(workspace_dh0))
            print(f"== Synced to {workspace_dh0} ==")
        if parent_dh0.parent.exists() and out_path != parent_dh0:
            shutil.copy2(str(out_path), str(parent_dh0))
            print(f"== Synced to {parent_dh0} ==")

    print(f"== OK: {args.out} ==")


if __name__ == "__main__":
    main()

