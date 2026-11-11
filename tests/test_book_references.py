"""Book reference drift tests.

Verifies that every repository file path and every `<!-- src: path -->` marker
in the book manuscript names a file that exists. The book deliberately cites
files without line numbers, so the repository can change freely; a test also
fails if a `file:line` citation or a ranged src marker creeps back in.

It also checks the manuscript against itself: every `§X.Y` / `Section X.Y`
names a section that exists, no text points at removed material (Part VI,
Chapters 36-38, Appendix L/M), and every `<!-- src -->` listing still matches
its source file line for line (comments and whitespace aside).

The manuscript lives outside this repository. Set AMIGA_BOOK_DIR to its
`book/` directory; by default the sibling checkout
`../AmigaBooks/Book1_GameEngine/book` is used, then `book/book` inside this
repository.
"""

from __future__ import annotations

import os
import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def _find_book_dir() -> Path:
    env = os.environ.get("AMIGA_BOOK_DIR")
    if env:
        return Path(env)
    sibling = REPO_ROOT.parent / "AmigaBooks" / "Book1_GameEngine" / "book"
    if sibling.is_dir():
        return sibling
    return REPO_ROOT / "book" / "book"


BOOK_DIR = _find_book_dir()

# Matches `<!-- src: path -->`; group 2 catches a forbidden `:start-end` suffix
SRC_MARKER_RE = re.compile(r"<!--\s*src:\s*([A-Za-z0-9_./-]+?)(:\d+(?:-\d+)?)?\s*-->")

# Matches repo-relative paths anywhere in text, links, or code comments
REPO_PATH_RE = re.compile(
    r"(?<![A-Za-z0-9_./-])"
    r"((?:engine|games|tools|docs)/[A-Za-z0-9_./-]+\.(?:asm|i|py|md|json|ps1|h|pdf)|build\.py|MAKING_A_GAME\.md)"
)

# Any source file name followed by a line number (`gamestatus.asm:563`, `engine_const.i:57-60`)
LINE_CITATION_RE = re.compile(
    r"(?<![A-Za-z0-9_./-])[A-Za-z0-9_./-]+\.(?:asm|i|py|json|ps1|h):\d+"
)

# Intentional historical/hypothetical or placeholder paths mentioned in prose
ALLOWED_MISSING_PATHS = {
    "games/my_new_game/main.asm",
    "games/my_game/main.asm",
    "tools/generate_levels.py",
}


def _book_files() -> list[Path]:
    """Manuscript chapters and appendices (archived material and build output excluded)."""
    skip = {"archive", "build"}
    return sorted(p for p in BOOK_DIR.rglob("*.md") if not skip & set(p.relative_to(BOOK_DIR).parts))


def _norm(line: str) -> str:
    return re.sub(r"\s+", " ", line.split(";")[0]).strip().lower()


# The manuscript is kept out of the repository, so CI runs without it.
@unittest.skipUnless(BOOK_DIR.is_dir(), f"book manuscript not present at {BOOK_DIR}")
class BookReferenceTests(unittest.TestCase):
    """Ensure every file the book names exists, and no line numbers are cited."""

    def test_all_cited_repo_paths_exist(self) -> None:
        errors: list[str] = []
        md_files = _book_files()
        self.assertGreater(len(md_files), 40, "Expected at least 40 book markdown files")

        for md_path in md_files:
            rel_md = md_path.relative_to(BOOK_DIR).as_posix()
            text = md_path.read_text(encoding="utf-8", errors="replace")
            for lineno, line in enumerate(text.splitlines(), start=1):
                for match in REPO_PATH_RE.finditer(line):
                    raw_path = match.group(1)
                    if "XX" in raw_path or "xx" in raw_path or raw_path in ALLOWED_MISSING_PATHS:
                        continue
                    if not (REPO_ROOT / raw_path).exists():
                        errors.append(f"{rel_md}:{lineno}: cited path does not exist: {raw_path}")

        if errors:
            self.fail("Stale repository references in book:\n  " + "\n  ".join(errors))

    def test_src_markers_name_existing_files(self) -> None:
        errors: list[str] = []
        for md_path in _book_files():
            rel_md = md_path.relative_to(BOOK_DIR).as_posix()
            for lineno, line in enumerate(
                md_path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
            ):
                m = SRC_MARKER_RE.search(line)
                if not m:
                    continue
                if m.group(2):
                    errors.append(f"{rel_md}:{lineno}: src marker carries line numbers: {m.group(0)}")
                if not (REPO_ROOT / m.group(1)).is_file():
                    errors.append(f"{rel_md}:{lineno}: src marker file not found: {m.group(1)}")

        if errors:
            self.fail("Source marker problems in book:\n  " + "\n  ".join(errors))

    def test_no_line_number_citations(self) -> None:
        errors: list[str] = []
        for md_path in _book_files():
            rel_md = md_path.relative_to(BOOK_DIR).as_posix()
            for lineno, line in enumerate(
                md_path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
            ):
                for m in LINE_CITATION_RE.finditer(line):
                    errors.append(f"{rel_md}:{lineno}: cite the file without a line number: {m.group(0)}")

        if errors:
            self.fail("Line-number citations in book:\n  " + "\n  ".join(errors))

    def test_section_references_exist(self) -> None:
        """Every §X.Y / Section X.Y names a numbered heading in the manuscript."""
        files = _book_files()
        heads = set()
        for md_path in files:
            for m in re.finditer(r"^#{2,4} ((?:\d+|[A-K])\.\d+(?:\.\d+)?) ", md_path.read_text(encoding="utf-8"), re.M):
                heads.add(m.group(1))
        ref_re = re.compile(r"(?:§|Sections? )\s?((?:\d+|[A-K])\.\d+(?:\.\d+)?)(?:\s?(?:–|-|to|and)\s?((?:\d+|[A-K])\.\d+(?:\.\d+)?))?")
        errors: list[str] = []
        for md_path in files:
            for lineno, line in enumerate(md_path.read_text(encoding="utf-8").splitlines(), start=1):
                if line.startswith("#"):
                    continue
                for m in ref_re.finditer(line):
                    for sec in m.groups():
                        if sec and sec not in heads:
                            errors.append(f"{md_path.relative_to(BOOK_DIR).as_posix()}:{lineno}: no section {sec}")
        if errors:
            self.fail("References to missing sections:\n  " + "\n  ".join(errors))

    def test_no_references_to_removed_material(self) -> None:
        bad = re.compile(r"Part VI\b|Chapters? 3[7-9]\b|Appendix [LM]\b|Appendix I and|Appendices [A-K] and M\b")
        errors: list[str] = []
        for md_path in _book_files():
            for lineno, line in enumerate(md_path.read_text(encoding="utf-8").splitlines(), start=1):
                if bad.search(line):
                    errors.append(f"{md_path.relative_to(BOOK_DIR).as_posix()}:{lineno}: {line.strip()[:80]}")
        if errors:
            self.fail("References to removed chapters/appendices:\n  " + "\n  ".join(errors))

    def test_src_listings_match_source(self) -> None:
        """Each `<!-- src -->` listing's code lines appear, in order, in the named file."""
        errors: list[str] = []
        for md_path in _book_files():
            lines = md_path.read_text(encoding="utf-8").splitlines()
            for i, line in enumerate(lines):
                m = SRC_MARKER_RE.search(line)
                if not m or not (REPO_ROOT / m.group(1)).is_file():
                    continue
                j = i + 1
                while j < len(lines) and not lines[j].lstrip().startswith("```"):
                    j += 1
                k = j + 1
                block = []
                while k < len(lines) and not lines[k].lstrip().startswith("```"):
                    block.append(lines[k])
                    k += 1
                src = [_norm(x) for x in (REPO_ROOT / m.group(1)).read_text(encoding="utf-8", errors="replace").splitlines()]
                pos = 0
                for x in block:
                    n = _norm(x)
                    if not n or n.startswith("..."):
                        continue
                    try:
                        pos = src.index(n, pos) + 1
                    except ValueError:
                        errors.append(f"{md_path.relative_to(BOOK_DIR).as_posix()}:{i + 1}: line not in {m.group(1)}: {x.strip()[:60]}")
                        break
        if errors:
            self.fail("Listings out of sync with source:\n  " + "\n  ".join(errors))

    def test_cross_chapter_figure_consistency(self) -> None:
        """Verify key metrics and asset sizes stay consistent across chapters."""
        ch09 = (BOOK_DIR / "part3-anatomy-of-a-bare-metal-game" / "08-memory-layout-and-sections.md").read_text(encoding="utf-8")
        ch16 = (BOOK_DIR / "part3-anatomy-of-a-bare-metal-game" / "15-sound.md").read_text(encoding="utf-8")
        ch24 = (BOOK_DIR / "part4-debugging-performance-shipping" / "23-release-checklist.md").read_text(encoding="utf-8")
        ch25 = (BOOK_DIR / "part5-game-effects" / "24-boot-to-title-loading-screens.md").read_text(encoding="utf-8")
        ch26 = (BOOK_DIR / "part5-game-effects" / "25-title-screens-and-copper-effects.md").read_text(encoding="utf-8")
        ch33 = (BOOK_DIR / "part5-game-effects" / "32-defeating-the-512kb-barrier-dynamic-overlays-and-memory-topology.md").read_text(encoding="utf-8")

        # Title module size is 45.3 KB (46,414 bytes / 1024), never 65.4 KB.
        # Its home is Section 32.4; Chapters 8 and 15 refer there instead of repeating it.
        self.assertIn("45.3 KB", ch33)
        for text in (ch09, ch16, ch33):
            self.assertNotIn("65.4 KB", text)

        # Loading screen ZX0 compressed size is 19,634 bytes (40,000 uncompressed)
        self.assertIn("19,634", ch25)
        self.assertIn("19,634", ch33)
        self.assertNotIn("14,820", ch25)

        # Bootblock diagram should not have double-escaped backslash
        self.assertNotIn(r"DOS\\0", ch24)
        self.assertIn(r"DOS\0", ch24)

        # Password keys are A-P in prose
        self.assertIn("`A` through `P`", ch26)


if __name__ == "__main__":
    unittest.main()
