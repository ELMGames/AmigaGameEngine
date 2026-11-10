"""
test_variable_addressing.py - every Variables field must be reached through a5.

The fields of the Variables block are declared with `rs`, so each name is an
offset (PalFadeWork = $1980), not an address. Written without a base register,
`lea PalFadeWork,a0` assembles to an absolute address in low Chip RAM that the
game does not own, and silently reads and writes the operating system's memory.
vasm accepts it without a warning, so this test looks for it: every reference to
a Variables field in engine or game code must be `Field(a5)` (or `Field+n(a5)`).
"""

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

VARIABLE_FILES = [
    "engine/include/engine_variables.i",
    "engine/include/entity_variables.i",
    "games/duck_rescue/include/core/variables.asm",
    "games/starter/include/core/variables.asm",
]

RS_FIELD_RE = re.compile(r"^\s*([A-Za-z_]\w*):?\s+rs\.[bwl]\b")
INSTRUCTION_RE = re.compile(r"^\s+[A-Za-z]")
DIRECTIVE_RE = re.compile(r"^\s+(rs|rsreset|dc|ds|dcb|equ|set|include|incbin|section|macro|endm|if|ifd|ifnd|else|endc)\b", re.I)


def variable_fields():
    names = set()
    for rel in VARIABLE_FILES:
        path = REPO_ROOT / rel
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            m = RS_FIELD_RE.match(line)
            if m:
                names.add(m.group(1))
    return names


class VariableAddressingTests(unittest.TestCase):
    def test_fields_are_a5_relative(self):
        names = variable_fields()
        self.assertTrue(names, "no Variables fields found")
        alternation = "|".join(sorted((re.escape(n) for n in names), key=len, reverse=True))
        field_re = re.compile(r"(?<![\w.])(" + alternation + r")\b")
        errors = []
        sources = list((REPO_ROOT / "engine").rglob("*.asm")) + list((REPO_ROOT / "games").rglob("*.asm"))
        for path in sources:
            for lineno, line in enumerate(path.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
                code = line.split(";", 1)[0]
                if not INSTRUCTION_RE.match(code) or DIRECTIVE_RE.match(code):
                    continue
                for m in field_re.finditer(code):
                    rest = code[m.end():]
                    if re.match(r"\s*(\(|[+\-*/]\s*[\w$]+\s*\()", rest):
                        continue  # Field(a5) or Field+2(a5)
                    errors.append(f"{path.relative_to(REPO_ROOT)}:{lineno}: {code.strip()}")
        if errors:
            self.fail("Variables fields used as absolute addresses (add (a5)):\n  " + "\n  ".join(errors))


if __name__ == "__main__":
    unittest.main()
