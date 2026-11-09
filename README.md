# pc-cga-desolate

Port of **Desolate** to the IBM PC (8088 CPU, CGA adapter, 128K RAM), from the ZX Spectrum port
[spectrum-desolate](https://github.com/nzeemin/spectrum-desolate), which is itself a port of the
TI-83 Plus game by Patrick Prendergast (tr1p1ea).

The game is a DOS `.COM` file (about 38 KB), written in 8088 assembler for NASM.

## Screen

- CGA mode 4, 320x200, 4 colors (cyan/magenta/white palette; black background).
- The 192x128 game screen is centered in a 224x144 themed area, with the big DESOLATE sign above it.
- Light theme: black on white. Dark theme: cyan on black (story, credits).
- Damage flash: the screen background turns red for a moment.
- **P** cycles four palettes: cyan/magenta/white (bright, dim) and green/red/brown (bright, dim).

## Controls

| Key | Action |
|---|---|
| Arrow keys | Move, menu selection |
| Space, Enter | Look / shoot, select |
| S | Switch look / shoot mode |
| I | Inventory |
| Esc, Tab | Close pop-ups |
| M | Menu |
| P | Change palette |

On an XT keyboard the arrow keys are the numeric keypad ones.

## Build

Needs `tools\nasm.exe` (NASM) and Python 3.

```
!build.cmd
```

- `desolate.com` - the game for DOS.
- `x-martypc\media\floppies\desolate.img` - a self-booting 360K floppy with a test build that reboots on exit.

`!run-martypc.cmd` starts the [MartyPC](https://github.com/dbalsom/martypc) emulator (in `x-martypc`) with that
floppy and a floppy-only IBM 5160 machine (`x-martypc\martypc-desolate.toml`).

Debug switches are at the top of `desolcoda.asm`: `PLATFORM_TEST` (platform test screen instead of the game),
`DEBUG_NEXT_ROOM` (Esc/Tab = next room and weapon, E = ending, A = all items and door codes),
`CHEAT_SHOW_ROOM_NUMBER`.

## Source

The Spectrum code structure and labels are kept, so the code can be compared line by line.

| File | Contents |
|---|---|
| `desolcoda.asm` | Platform layer (video, keyboard, sound, text, themes, sign) and the main file |
| `desolcodb.asm` | Game code |
| `desoldata.asm`, `desoltils.asm`, `desolfont.asm`, `desolstrs.asm` | Rooms, variables, tiles, font and strings, converted from the Spectrum sources (two strings changed for the PC keys: `SE0A3`, `SE0A7`) |
| `tools\mkboot.py`, `tools\boot.asm` | Make the self-booting test floppy |
| `PLAN.md` | Porting notes and status |

Z80 to 8088 registers: A=AL, BC=CX, DE=DX, HL=BX, IX=SI (DI is a scratch pointer).
The shadow screen stays 1 bit per pixel as on the Spectrum; only the final copy expands it to CGA.

## Differences from the Spectrum version

- PC keys; the Info screen text is new.
- Delays run on the 60 Hz display refresh instead of busy loops.
- Quit from the menu leaves the program: back to DOS, or on the test floppy (no DOS) it stops with a short message.
- Key presses are remembered between polls, so short taps are not lost.

## License

MIT, as the Spectrum port. Thanks to tr1p1ea for the original game.
