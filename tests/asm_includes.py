"""
asm_includes.py - resolve a game's assembly include graph the way vasm does.

Used by test_engine_contract.py (reachability and hook checks). Parses the
`incdir` list from a game's main.asm, then follows every `include "x"` line
recursively, resolving each name against the current file's directory and
then the incdir list in order. Conditional assembly is ignored: a file
named inside IFD/IFND is still counted as reachable, which is the right
answer for "is this file part of the build at all".
"""

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
INCDIR_RE = re.compile(r'^\s*incdir\s+"([^"]+)"', re.I)
INCLUDE_RE = re.compile(r'^\s*include\s+"([^"]+)"', re.I)
CALL_RE = re.compile(r"^\s*(?:bsr|jsr|bra|jmp)(?:\.[sw])?\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
DEF_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)(?::|\s+(?:=|equ)\s)", re.M | re.I)


def strip_comments(text):
    return "\n".join(line.split(";", 1)[0] for line in text.splitlines())


def _resolve(name, current_dir, incdirs):
    candidates = [current_dir / name] + [d / name for d in incdirs]
    for c in candidates:
        if c.is_file():
            return c.resolve()
    return None


def include_graph(main_asm):
    """Return the set of absolute Paths reachable from main_asm via include directives."""
    main_asm = Path(main_asm).resolve()
    text = strip_comments(main_asm.read_text(encoding="utf-8", errors="replace"))
    incdirs = [(REPO_ROOT / m.group(1)).resolve() for m in map(INCDIR_RE.match, text.splitlines()) if m]
    seen, stack = set(), [main_asm]
    while stack:
        f = stack.pop()
        if f in seen:
            continue
        seen.add(f)
        body = strip_comments(f.read_text(encoding="utf-8", errors="replace"))
        for line in body.splitlines():
            m = INCLUDE_RE.match(line)
            if m:
                target = _resolve(m.group(1), f.parent, incdirs)
                if target and target not in seen:
                    stack.append(target)
    return seen


def defined_symbols(files):
    """Global labels and equates defined across the given files."""
    names = set()
    for f in files:
        names |= set(DEF_RE.findall(strip_comments(f.read_text(encoding="utf-8", errors="replace"))))
    return names


def called_symbols(files, pattern):
    """Symbols matching `pattern` that appear as branch/call targets in the given files."""
    rx = re.compile(pattern)
    out = {}
    for f in files:
        for name in CALL_RE.findall(strip_comments(f.read_text(encoding="utf-8", errors="replace"))):
            if rx.fullmatch(name):
                out.setdefault(name, set()).add(f)
    return out


def includes_before(main_asm, stop_name):
    """Files included (recursively, in order) before main_asm includes `stop_name`."""
    main_asm = Path(main_asm).resolve()
    text = strip_comments(main_asm.read_text(encoding="utf-8", errors="replace"))
    incdirs = [(REPO_ROOT / m.group(1)).resolve() for m in map(INCDIR_RE.match, text.splitlines()) if m]
    out, seen = [], set()

    def walk(f, top):
        for line in strip_comments(f.read_text(encoding="utf-8", errors="replace")).splitlines():
            m = INCLUDE_RE.match(line)
            if not m:
                continue
            if top and Path(m.group(1)).name == stop_name:
                return True
            target = _resolve(m.group(1), f.parent, incdirs)
            if target and target not in seen:
                seen.add(target)
                out.append(target)
                walk(target, False)
        return False

    walk(main_asm, True)
    return out


# Statements that never emit bytes: symbol/offset definitions, conditionals, macro
# definitions, alignment of nothing, and assembler bookkeeping.
SILENT_DIRECTIVES = {
    "=", "equ", "equr", "set", "rs", "rsreset", "rsset", "reg",
    "include", "incdir", "if", "ifd", "ifnd", "ifeq", "ifne", "ifgt", "ifge", "iflt", "ifle",
    "ifc", "ifnc", "ifb", "ifnb", "else", "elseif", "endc", "endif", "macro", "endm",
    "even", "cnop", "fail", "xref", "xdef", "public", "opt", "idnt", "list", "nolist",
}
_STMT_RE = re.compile(r"^([^\s:=]+):?\s*(=?)\s*(.*)$")


def _statement_op(code):
    """(label, op) for one comment-stripped source line; op is lower-case without a size suffix."""
    if not code.strip() or code.lstrip().startswith("*"):
        return None, None
    if code[0].isspace():
        label, rest = None, code.strip()
    else:
        m = _STMT_RE.match(code)
        label, rest = m.group(1), (m.group(2) + " " + m.group(3)).strip()
    if not rest:
        return label, None
    op = rest.split()[0].lower()
    return label, re.sub(r"\.[bwlsq]$", "", op)


def emitting_statements(files):
    """[(file, line, op)] for statements in `files` that would emit code or data bytes.

    Macro bodies are not emitted at definition time, so they are collected and
    judged by what they contain: a macro is silent when every statement in its
    body is a silent directive or another silent macro (fixed point).
    """
    macros, top = {}, []
    for f in files:
        body = None
        for i, line in enumerate(strip_comments(f.read_text(encoding="utf-8", errors="replace")).splitlines(), 1):
            label, op = _statement_op(line)
            if op == "macro":
                name = (label or line.split()[1]).lower()
                body = macros.setdefault(name, [])
                continue
            if op == "endm":
                body = None
                continue
            if op is None:
                continue
            (body if body is not None else top).append((f, i, op) if body is None else op)
    silent = set(SILENT_DIRECTIVES)
    changed = True
    while changed:
        changed = False
        for name, ops in macros.items():
            if name not in silent and all(op in silent for op in ops):
                silent.add(name)
                changed = True
    return [(f, i, op) for f, i, op in top if op not in silent]


# An include file must not end in the middle of a routine: control would run into
# whatever file main.asm includes next. The last byte-emitting statement must be
# an unconditional transfer or data.
TERMINAL_OPS = {"rts", "rte", "rtr", "bra", "jmp"}
DATA_OPS = {"dc", "dcb", "ds", "incbin", "blk", "even", "cnop"}


def last_emitting_statement(path):
    """(line, op) of the last statement in `path` that emits bytes, ignoring macro bodies; (None, None) if none."""
    last = (None, None)
    in_macro = False
    for i, line in enumerate(strip_comments(path.read_text(encoding="utf-8", errors="replace")).splitlines(), 1):
        label, op = _statement_op(line)
        if op == "macro":
            in_macro = True
            continue
        if op == "endm":
            in_macro = False
            continue
        if in_macro or op is None or op in SILENT_DIRECTIVES or op == "section":
            continue
        last = (i, op)
    return last


def falls_off_end(path):
    """Return (line, op) when the file's last emitting statement is code that is not a transfer."""
    line, op = last_emitting_statement(path)
    if op is None or op in TERMINAL_OPS or op in DATA_OPS:
        return None
    return line, op
