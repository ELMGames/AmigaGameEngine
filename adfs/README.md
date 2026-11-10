# Floppy disk images

| File | Where it comes from | Used by |
|---|---|---|
| `game.adf` | Made by `tools/make_adf.py` after each build (the `build + ADF` task) | `DF1:` in the Workbench profile; also boots on its own from `DF0:`, or from a Gotek |
| `amiga-os-134-workbench.adf` | Your own Workbench 1.3 disk image | `DF0:` in the Workbench profile |

`game.adf` holds a stripped release build of the current game (the one the root
`main.asm` includes), its Workbench icon and an `S/Startup-Sequence` that runs
it. Rebuild it on its own with `python tools/make_adf.py`.

**Never commit a Workbench disk.** Like the Kickstart ROMs in `roms/`, it is
copyrighted, so Git ignores everything in this folder except this README. Legal
sources include Cloanto's Amiga Forever, or an image of your own original disk.
