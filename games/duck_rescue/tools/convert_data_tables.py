#!/usr/bin/env python3
"""
tools/convert_data_tables.py
----------------------------
Builds the binary lookup tables in assets/data/ from their readable sources:

  - assets/data/sin.txt        -> sin.bin        (Sinus, 2048 signed words)
  - assets/data/quadratic.txt  -> quadratic.bin  (Quadratic, 2048 signed words)

Every *.txt file in assets/data/ is converted the same way, so a new table
only needs a new .txt file and an incbin in main.asm.

Source format:
  - ';' starts a comment; everything after it on a line is ignored.
  - Values are decimal integers (a leading '$' marks hex), separated by
    spaces or commas, any number per line.
  - Each value becomes one big-endian 16-bit word, so it must lie in
    -32768..65535 (negative values are stored as two's complement).
  - A comment line '; entries: N' is required. The build fails if the file
    holds a different number of values, because the engine derives sizes
    such as SINE_ANGLES ((SinusEnd-Sinus)/2) from the table length.

Output: <name>.bin next to the source, rewritten on every run.
"""

import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "assets" / "data"

ENTRIES_RE = re.compile(r";\s*entries\s*:\s*(\d+)", re.IGNORECASE)


def parse_table(path: Path) -> list[int]:
    expected = None
    values: list[int] = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if expected is None:
            m = ENTRIES_RE.search(line)
            if m:
                expected = int(m.group(1))
        code = line.split(";", 1)[0]
        for tok in re.split(r"[\s,]+", code.strip()):
            if not tok:
                continue
            try:
                v = int(tok[1:], 16) if tok.startswith("$") else int(tok, 10)
            except ValueError:
                raise ValueError(f"{path.name}:{lineno}: '{tok}' is not a number")
            if not -32768 <= v <= 65535:
                raise ValueError(f"{path.name}:{lineno}: {v} does not fit in a 16-bit word")
            values.append(v)
    if expected is None:
        raise ValueError(f"{path.name}: missing '; entries: N' header line")
    if len(values) != expected:
        raise ValueError(f"{path.name}: header says {expected} entries but the file has {len(values)}")
    return values


def to_words(values: list[int]) -> bytes:
    return b"".join((v & 0xFFFF).to_bytes(2, "big") for v in values)


def main():
    print("=== Converting Data Tables ===")
    sources = sorted(DATA_DIR.glob("*.txt"))
    if not sources:
        raise FileNotFoundError(f"no .txt tables found in {DATA_DIR}")
    for src in sources:
        data = to_words(parse_table(src))
        out = src.with_suffix(".bin")
        out.write_bytes(data)  # always written, so the golden tests see it as a pipeline output
        print(f"[*] {src.name} -> {out.name} ({len(data)} bytes)")
    print("=== Data Tables Conversion Complete! ===")


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from tool_cli import run_tool
    run_tool(main, __doc__)
