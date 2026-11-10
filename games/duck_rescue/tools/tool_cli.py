"""
tool_cli.py - one entry point wrapper for every asset converter.

    from tool_cli import run_tool
    if __name__ == "__main__":
        run_tool(main, __doc__, options=[("--preview", "also write a PNG contact sheet")])

run_tool() gives every script a `--help` that prints the module docstring
and its options, leaves sys.argv untouched for scripts that scan it
themselves, and turns the errors a converter can realistically hit
(missing input file, bad palette JSON, malformed image or TMX) into one
line on stderr and exit status 1 instead of a traceback.
"""

import argparse
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

EXPECTED_ERRORS = (FileNotFoundError, IsADirectoryError, PermissionError, ValueError,
                   KeyError, struct.error, ET.ParseError)


def run_tool(entry, doc=None, options=(), positional=()):
    """Run `entry()` as a command-line tool.

    options:    [(flag, help)] documented in --help; the script still reads them from sys.argv.
    positional: [(name, help)] likewise.
    """
    parser = argparse.ArgumentParser(description=(doc or "").strip(), formatter_class=argparse.RawDescriptionHelpFormatter)
    for flag, help_text in options:
        parser.add_argument(flag, action="store_true", help=help_text)
    for name, help_text in positional:
        parser.add_argument(name, nargs="?", help=help_text)
    parser.parse_known_args()                      # only --help acts; the script keeps reading sys.argv
    tool = Path(sys.argv[0]).name
    try:
        entry()
    except EXPECTED_ERRORS as e:
        detail = e.filename if isinstance(e, OSError) and e.filename else e
        sys.exit(f"error: {tool}: {type(e).__name__}: {detail}")
    except ModuleNotFoundError as e:
        sys.exit(f"error: {tool}: missing dependency {e.name}; run: pip install Pillow")


def require_file(path, what="input"):
    """Return Path(path) or exit with a clear message if it does not exist."""
    p = Path(path)
    if not p.is_file():
        raise FileNotFoundError(f"{what} not found: {p}")
    return p
