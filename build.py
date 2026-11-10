#!/usr/bin/env python3
"""
build.py - Assemble and link the Amiga Game Engine and example game.

Usage:
  python build.py                 build uae/dh0/main (default: Duck Rescue)
  python build.py --assets        regenerate converted assets first
  python build.py --game <name>   select game under games/ (default: duck_rescue)
  python build.py --out my.exe    build to a custom output path
  python build.py --tool-dir <dir> use vasm/vlink from a specific directory
  python build.py --check         run the test suite first, build only if it passes
  python build.py --explain       on failure, list missing symbols and where Duck Rescue defines them

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

# The asset pipeline, in run order. Each entry: (script under games/<game>/tools,
# description, assets_only). assets_only scripts run only with --assets; the
# rest run on every build. tests/golden_support.py imports this list so the
# golden-file tests exercise exactly what the build does.
ASSET_PIPELINE = [
    ("convert_assets.py", "Converting assets", True),
    ("convert_duck_banner.py", "Converting Duck Rescue Banner", True),
    ("generate_sfx.py", "Generating Sound Effects", True),
    ("convert_data_tables.py", "Converting Data Tables", False),
    ("export_level.py", "Exporting Tiled Levels", False),
    ("convert_player_bob.py", "Converting Player BOB Assets", False),
    ("convert_animals.py", "Converting Animal Friend Assets", False),
    ("convert_enemies.py", "Converting Enemy Assets", False),
    ("convert_effects.py", "Converting Effect Assets", False),
    ("convert_headshots.py", "Converting Headshot Assets", False),
]


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
        {"win32": "win32", "darwin": "darwin"}.get(sys.platform, "linux"),
    )
    matches = glob.glob(pattern)
    if matches:
        matches.sort()
        return Path(matches[-1])

    return None


def explain_failure(project_root, game_dir, output):
    """Turn assembler/linker errors into a list of missing contract symbols.

    vlink reports each unresolved symbol; vasm reports a non-constant expression
    with its file and line. For every symbol involved, say which engine file
    needs it and where games/duck_rescue defines it, so a new game can copy the
    definition instead of guessing (see engine/ENGINE_CONTRACT.md).
    """
    import re
    DIRECTIVES = {"IFND", "IFD", "IFEQ", "IFNE", "IFGT", "IFGE", "IFLT", "IFLE", "ELSE", "ENDC", "ENDIF", "MACRO", "ENDM", "REPT", "ENDR", "EQU", "SET", "RS", "RSRESET", "RSSET", "SECTION", "EVEN", "CNOP"}
    sys.path.insert(0, str(project_root / "tests"))
    try:
        from asm_includes import DEF_RE, include_graph, strip_comments
    except ImportError:
        print("(--explain needs tests/asm_includes.py)", file=sys.stderr)
        return
    graph = include_graph(game_dir / "main.asm")
    defined = set()
    for f in graph:
        defined |= set(DEF_RE.findall(strip_comments(f.read_text(encoding="utf-8", errors="replace"))))
    missing = set(re.findall(r"undefined symbol\s+([A-Za-z_][A-Za-z0-9_]*)", output))
    ident = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
    for m in re.finditer(r"line (\d+) of \"([^\"]+)\"", output):
        path = project_root / m.group(2).replace("\\", "/")
        if path.is_file():
            line = path.read_text(encoding="utf-8", errors="replace").splitlines()[int(m.group(1)) - 1]
            code = line.split(";")[0]
            if re.match(r"\s*(include|incdir|incbin)\b", code, re.I):
                continue                                    # the error was inside an included file
            for name in ident.findall(code):
                if name in defined or re.fullmatch(r"[ad][0-7]|sp|pc|[a-z]+(\.[bwls])?|\d+", name):
                    continue
                if name.upper() == name and name in DIRECTIVES:
                    continue
                missing.add(name)
    if not missing:
        return
    where = {}
    for root, hint in ((project_root / "engine", "engine defines it: include "), (project_root / "games" / "duck_rescue", "Duck Rescue: ")):
        for f in sorted(root.rglob("*")):
            if f.suffix not in (".asm", ".i") or "ptplayer" in f.parts:
                continue
            for i, l in enumerate(f.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                m = DEF_RE.match(l)
                if m and m.group(1) in missing and m.group(1) not in where:
                    where[m.group(1)] = f"{hint}{f.relative_to(project_root).as_posix()}:{i}"
    users = {}
    for f in graph:
        if (project_root / "engine") not in f.parents:
            continue
        body = strip_comments(f.read_text(encoding="utf-8", errors="replace"))
        for name in missing:
            if re.search(r"\b" + re.escape(name) + r"\b", body):
                users.setdefault(name, []).append(f.name)
    print()
    print(f"== {len(missing)} missing symbol(s): what needs them, and where to get them ==")
    w = max(len(n) for n in missing)
    uw = max(len(", ".join(sorted(set(users.get(n, ["?"]))))) for n in missing)
    for name in sorted(missing):
        by = ", ".join(sorted(set(users.get(name, ["?"]))))
        print(f"  {name:<{w}}  needed by {by:<{uw}}  {where.get(name, 'see engine/ENGINE_CONTRACT.md')}")
    print("  Engine-defined: include that engine file. Duck Rescue-defined: copy the definition into your")
    print("  game's const/struct/variables file, or bind it (Name = YourSymbol). See engine/ENGINE_CONTRACT.md.")


def run_script(script_path, desc, cwd=None):
    if os.path.exists(script_path):
        print(f"== {desc} ==")
        sys.stdout.flush()
        res = subprocess.run([sys.executable, str(script_path)], cwd=cwd)
        if res.returncode != 0:
            print(f"Error: {desc} failed with exit code {res.returncode}", file=sys.stderr)
            sys.exit(res.returncode)


def main():
    parser = argparse.ArgumentParser(description="Assemble and link Amiga game")
    parser.add_argument("--assets", action="store_true", help="Regenerate converted assets first")
    parser.add_argument("--game", default="duck_rescue", help="Game to build in games/ (default: duck_rescue)")
    parser.add_argument("--out", default="uae/dh0/main", help="Output path (default: uae/dh0/main)")
    parser.add_argument("--tool-dir", default=None, help="Directory containing vasmm68k_mot and vlink")
    parser.add_argument("--check", action="store_true", help="Run the test suite (tests/) before assembling")
    parser.add_argument("--explain", action="store_true",
                        help="On a failed build, list every missing symbol with the engine file that needs it and where Duck Rescue defines it")

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

    if args.check:
        print("== Running tests ==")
        sys.stdout.flush()
        res = subprocess.run([sys.executable, "-m", "unittest", "discover", "tests"], cwd=project_root)
        if res.returncode != 0:
            print("Error: tests failed; not building", file=sys.stderr)
            sys.exit(res.returncode)

    game_dir = project_root / "games" / args.game
    if not game_dir.exists():
        print(f"Error: Game directory not found: {game_dir}", file=sys.stderr)
        sys.exit(1)

    game_tools = game_dir / "tools"

    for script, desc, assets_only in ASSET_PIPELINE:
        if assets_only and not args.assets:
            continue
        run_script(game_tools / script, desc, cwd=game_dir)

    build_dir = project_root / "build"
    build_dir.mkdir(parents=True, exist_ok=True)

    entry_asm = f"games/{args.game}/main.asm" if (game_dir / "main.asm").exists() else "main.asm"
    print(f"== Assembling {entry_asm} ({args.game}) ==")
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
        entry_asm,
    ]
    sys.stdout.flush()
    res = subprocess.run(asm_cmd, capture_output=True, text=True)
    print(res.stdout, end="")
    print(res.stderr, end="", file=sys.stderr)
    if res.returncode != 0:
        print(f"Error: Assembly failed with exit code {res.returncode}", file=sys.stderr)
        if args.explain:
            explain_failure(project_root, game_dir, res.stdout + res.stderr)
        sys.exit(res.returncode)

    out_target = args.out if (args.out != "uae/dh0/main" or args.game == "duck_rescue") else f"uae/dh0/{args.game}"
    out_path = Path(out_target)
    if not out_path.is_absolute():
        out_path = (project_root / out_path).resolve()

    out_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"== Linking {out_path} ==")
    link_cmd = [
        str(vlink),
        "-bamigahunk",
        "-Bstatic",
        "-s",
        "-o",
        str(out_path),
        "build/main.o",
    ]
    sys.stdout.flush()
    res = subprocess.run(link_cmd, capture_output=True, text=True)
    print(res.stdout, end="")
    print(res.stderr, end="", file=sys.stderr)
    if res.returncode != 0:
        print(f"Error: Link failed with exit code {res.returncode}", file=sys.stderr)
        if args.explain:
            explain_failure(project_root, game_dir, res.stdout + res.stderr)
        sys.exit(res.returncode)

    print(f"== OK: {out_path} ==")


if __name__ == "__main__":
    main()
