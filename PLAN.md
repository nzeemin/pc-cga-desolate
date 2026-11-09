# Desolate: ZX Spectrum -> PC (8088, CGA) port plan

Source: `D:\Work\MyProjects\spectrum-desolate` (Z80, pasmo/sjasmplus syntax).
Target: DOS `.COM`, NASM (`tools/nasm.exe -f bin`), 8088, CGA mode 4 (320x200x2bpp), 128K RAM. Test in MartyPC (`x-martypc`).

## Decisions
- Video: mode 4, palette 1 high intensity = black / cyan / magenta / white.
- Gameplay: 192x128 1bpp shadow screen kept as-is (24 bytes/line), centered; "DESOLATE" sign above.
- Theme (ZX attributes `ScreenThemeNite/Lite`) = ink/paper colour pair. Nite: cyan on black. Lite: black on white.
- Palette option in menu (e.g. dim palette 1 / palette 0) = port 3D9h bits, no code impact.
- Sound: one short PC-speaker beep (look/shoot) via PIT ch.2 + port 61h.
- Input: INT 9 hook keeps key-state table; replaces `ReadKeyboard` matrix scan. Cursor keys, Space/Enter fire, Esc/Tab exit, I inventory, look/shoot toggle key, menu key. No saves.
- Code structure/labels kept (`LB0A2` etc.), same file split: `desolcoda` (platform + main), `desolcodb` (game), `desoldata`, `desolfont`, `desolstrs`, `desoltils`. Main file includes the rest, like the original.

## Key technical choices
- Shadow screen stays 1bpp, MSB-left, same as Spectrum. All drawing code (tiles, masked sprites, font, shifts, XOR) ports nearly 1:1.
- Only `ShowShadowScreen` changes: per source byte, look up a 16-bit word (bit -> 2-bit pixel pair) from a 512-byte table, `stosw` to CGA. 48 bytes/line, 128 lines, interlaced (even lines B800:0000, odd B800:2000, 80 bytes/line). Table built at runtime from ink/paper colours, so theme switch = rebuild table. Estimated full blit ~40 ms at 4.77 MHz.
- Tile/font/room/string data: little-endian DB/DW, no endian or format change. Only syntax conversion (`$FF`->`0FFh`, `DEFB/DEFW/DEFS`, `IF/ENDIF`, `INCLUDE`, `ORG`, `EQU`). Script: `tools/z80data2nasm.py`.
- Z80->8088 register map (final, see header of `desolcoda.asm`): A=AL, B=CH, C=CL (BC=CX), D=DH, E=DL (DE=DX), H=BH, L=BL (HL=BX), IX=SI, DI=scratch pointer, BP=spare. Watch: x86 INC/DEC r16 change flags (Z80 do not); `DJNZ`->`dec ch / jnz`; `LDIR`->`rep movsb`; `CP`/`SUB` carry polarity same; `RLCA/RRCA/SLA/SRL/RL/RR` map 1:1; `ADD HL,rr` sets only carry on Z80.
- No self-modifying code, no HALT-timing, no ROM calls except beeper (`ROM_BEEPER`), border (`out $FE`: injury flash = CGA border/background colour, port 3D9h).
- Z80 code size 37 KB total, fits one 64K COM segment (CS=DS=ES=SS). Shadow screen 3 KB in-image. No compression needed.
- Timing: game is polling-driven; add vsync-based (port 3DAh) or PIT-tick delay only where animations need pacing.

## Phases
0. Scaffolding: `build.cmd` (nasm -> `desolate.com`), MartyPC run script, README.
1. Data conversion script + build check: assembled data slices byte-identical to Spectrum `desolcode.bin`.
2. Platform layer (`desolcoda`): INT 9 keys, `GetScreenAddr`, `ShowShadowScreen` + expand table, `ClearScreenBlock`, `DrawChar/String/Number`, `DrawTileMasked`, random, beep, theme, palette, DESOLATE sign, DOS exit.
3. Game code (`desolcodb`, ~3.6k lines), in order, each stage runnable: tile blitters (`L9E..`) -> titles/menu -> info/credits -> new game, story -> room draw, player move, shoot/look -> doors/codes -> inventory -> enemies/damage -> endings.
4. Verify per stage: compare against Spectrum emulator screenshots (Fuse, `!run-fuse.cmd`), same inputs.
5. Polish: palette menu option, speed tuning, real-XT check, README.

## Resolved
- Themed 224x144 area: background white (Lite) / black (Nite); playfield 192x128 centered in it. Theme = ink/paper pair on whole area.
- DESOLATE sign: tiles drawn into the shadow screen, blitted inverted above the playfield.
- Running in MartyPC (verified, phase 0 done): `!build.cmd` builds `desolate.com` (with `-DNODOS`: exit = reboot) and `tools/mkboot.py` wraps it into self-booting `x-martypc/media/floppies/desolate.img` (boot sector `tools/boot.asm` loads COM to 1000:0100, no DOS). `!run-martypc.cmd` starts MartyPC with `-m fd:0:media/floppies/desolate.img`. `--run-bin` and `mount/floppy` autofloppy do not work (no BIOS / folder scan empty). Mount path needs the `media/floppies/` prefix.
- Final shipping `.COM` for DOS: build without `-DNODOS` (exit via DOS).

## Status
- Phase 0 done. Phase 1 done (data identical, `tools/verify_data.py`).
- Phase 2 done: platform layer in `desolcoda.asm` verified in MartyPC (text, numbers, themes, keys, beep). `PLATFORM_TEST` EQU 1 runs the test screen; set 0 to include `desolcodb.asm` and run the game.
- Keys: arrows 4/1/2/3, Space=5 (look/shoot), Enter=9, Esc/Tab=7, I=6, S=8 (switch look/shoot), M=0Fh (menu).
- Open for phase 3: Enter (9) vs fire (5) in menu/game; DESOLATE sign; `ClearShadowScreen` already moved to desolcoda (skip in desolcodb).
- Stage 1 (tile/sprite blitters L9E5F, L9EAD, L9EDE, ReflectByte) done, verified pixel-exact against a Python reference render of the test screen. Test screen: Enter on the platform test screen.
- Method note: for screens, a Python reference renderer of the original algorithm compared with a MartyPC screenshot is a good check.
- Stage 2 (titles, menu, Info, Credits, LBEDE text, delays on 60 Hz vsync) done and confirmed by user. PC changes: Quit exits program; controls text in pcstrs.asm; Credits waits key-up first. New/Continue menu items are stubs (NotPortedYet).
- Stage 3 (New Game, story screens, LAB28 popup, LB9D6) done and confirmed. Overwrite prompt text in pcstrs.asm (M instead of G). L9DDD is a stub (NotPortedYet) until stage 4.
- Stage 4 (main loop L9DDD, room draw, player, movement, health, look/shoot switch, death screen) done and confirmed. Stubs left: LB76B LB551 LB653 LB72E LB74C LB07B LB08D (stage 5), LAAAF (debug: next room), LB0A2 inventory (stage 6). SetBorderColor added (CGA background color).
- Stage 5 (aliens, bullets, damage, death, LAAAF look dispatch) done and confirmed; damage flash red via Spectrum->CGA color map. DEBUG_NEXT_ROOM=1 (Esc/Tab = next room + weapon) and CHEAT_SHOW_ROOM_NUMBER=1 are temporary; turn off after stage 6. Look targets LAB3F LABA4 LABBE LAC05 LAC54 LACE3 LBC8B are stubs.
- Stage 6a (look targets: doors, door lock, bodies, items, weapon; LA0F1G = Enter as fire) done and confirmed. Remaining stubs: LBC8B terminals, LB0A2 inventory.
- Stage 6b (inventory, item use, terminals, ending LBD85, LBC3C) translated. Confirmed by user: inventory view, descriptions, Power Drill on Generator. Not yet confirmed: other items, terminals, ending (debug E key), credits end. Debug keys (DEBUG_NEXT_ROOM=1): Esc/Tab next room + weapon, E ending, A all items/codes; CHEAT_SHOW_ROOM_NUMBER=1. Remaining: turn debug off, DOS .COM build without NODOS, palette option, DESOLATE sign, README, real-XT speed check.
- Cleanup done: debug flags off, DOS desolate.com + test floppy build, sign copied like Vector CopyTitleSign (3 tile rows, 30 lines from line 8, white on black, y=6), P palette key (3 palettes), key latch for taps, README. Untested: DOS run (no DOS image used), real XT speed, remaining item/terminal paths.
- pcstrs.asm removed: the two PC key strings (SE0A3, SE0A7) are edited in desolstrs.asm; tools/verify_data.py removed (data port done).
- tools/z80data2nasm.py removed (data conversion finished).
