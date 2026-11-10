# Kickstart ROMs

Put your own Kickstart ROM files in this folder. Every launch profile in
`.vscode/launch.json` looks for its ROM here, so the profiles work unchanged on
Windows, macOS and Linux.

| File | Used by |
|---|---|
| `kick1.3.rom` | A500 profile (Kickstart 1.3) |
| `kick2.04.rom` | A500+ profile (Kickstart 2.04) |
| `kick2.05.rom` | A600 profile (Kickstart 2.05, the ROM the A600 shipped with) |
| `kick3.1.rom` | A1200 and A4000 profiles (Kickstart 3.1) |

The names must match exactly, including capitals on macOS and Linux.

The AROS profile uses WinUAE's built-in AROS ROM and needs no file here.

**Never commit a ROM.** Kickstart ROMs are copyrighted, so Git ignores
everything in this folder except this README. Legal sources include Cloanto's
Amiga Forever, Hyperion's AmigaOS 3.x releases, or a dump of your own Amiga's
ROM (Chapter 4 of the book).
