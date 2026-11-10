# Companion Guides

Short technical guides that go with the book *Building an AMIGA Game Engine*. Each is a Markdown source with a matching PDF for reading or printing.

| Guide | PDF | What it covers | Book |
|---|---|---|---|
| Making a Game | [PDF](MAKING_A_GAME_GUIDE.pdf) | From the starter to your own game: entry points, `Variables`, hooks, subsystems, tests | Ch 5, 35 |
| Blit Order Guide | [PDF](BLIT_ORDER_GUIDE.pdf) | The frame's draw order and the rules that keep a single-buffered display tear-free | Ch 13, 21 |
| Ring Buffer Guide | [PDF](RING_BUFFER_GUIDE.pdf) | The 512-line scrolling buffer, its mirror half, streaming, the camera, addressing rules | Ch 27 |
| Asset Pipeline Guide | [PDF](ASSET_PIPELINE_GUIDE.pdf) | Every converter, the formats the hardware reads, Chip versus Fast RAM, golden tests | Ch 28, 33 |
| Coding Conventions | [PDF](CODING_CONVENTIONS_GUIDE.pdf) | Naming, layout, routine headers, registers and flags, engine and game boundaries | Ch 5, 18 |
| Single Translation Units | [PDF](SINGLE_TRANSLATION_UNITS_GUIDE.pdf) | Why the engine assembles in one pass instead of linking objects | Ch 5, 8 |
| Launch Profiles Guide | [PDF](VSCODE_LAUNCH_PROFILES_GUIDE.pdf) | The eight launch profiles: six WinUAE machines (including AROS, no ROM needed), Workbench with the game in DF1:, and FS-UAE for macOS and Linux; the build task and the ADF step | Ch 4, 23 |

`engine/ENGINE_CONTRACT.md` is the reference table behind the Making a Game guide.

## Rebuilding the PDFs

The Markdown file is the source. After editing one, rebuild its PDF and commit both:

```powershell
./docs/build_docs_pdf.ps1                         # every guide
./docs/build_docs_pdf.ps1 -Name RING_BUFFER_GUIDE # one guide
```

This needs Pandoc and XeLaTeX (MiKTeX on Windows), the same tools that build the book. Styling is in `tools/guide-header.tex`.
