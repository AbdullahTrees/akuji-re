# Akuji the Demon — source reconstruction

Rebuilding the source of **Akuji the Demon**, a Japanese doujin action-platformer
for Windows, written in Borland Delphi and released around 2001. Its source was
never published; this repository reconstructs it from `akuji.exe`, in Object
Pascal.

The output *is* the source: it compiles with Free Pascal and Lazarus, and it is
cross-platform because Free Pascal is — not through a porting layer. There is no
SDL layer and no C.

## Where it stands

| | | measured by |
|---|---|---|
| game-layer functions with executable Pascal | **149 / 149** | `tools/implemented.py` |
| the full differential suite against the original's machine code | **1168 cases, 0 disagree** | `tools/emudiff.py` |
| entity handlers, live differential sweep | 296 cases, 0 disagree | `emudiff.py handler_live` |
| behavioural self-test modes in the gate | 14 | `tools/check.sh` |
| functions read-audited and frozen | 34 | `tools/audited.py` |
| functions never verified — unproven, not suspect | 47 | `tools/audited.py --list` |
| knowing differences from the binary | 15 | `tools/divergences.py` |
| reconstructed Pascal | ~32,000 lines across 50 units | |

The game is completable from start to finish. "149 / 149" means every game-layer
function has code rather than a description of code; it does **not** mean every
one has been verified. `notes/audited.md` carries one row per function saying
exactly what evidence exists for it, and 47 of those rows say "none yet".

## Layout

```
akuji-re/
├── CLAUDE.md          the working rules - read before changing anything
├── src/               the reconstruction (Object Pascal, builds to akuji.exe)
│   ├── akuji.lpr          entry point
│   ├── screens/           main form, menus, dialogue, opening, ending
│   ├── gameplay/          state, session, player, entities, camera, stages
│   ├── events/            event data, command decoding, script execution
│   ├── render/            fonts, surfaces, sprites, tile maps, backgrounds
│   ├── media/             archives, sound effects, PCM output, MIDI
│   ├── components/        replacements for the third-party DirectX suite
│   └── selftests/         the executable's self-test modes
├── tools/             verification and analysis; check.sh is the gate
├── notes/             the decoded formats, the audit ledger, the findings
├── ghidra_scripts/    Ghidra scripts, incl. the differential emulator
├── ghidra/            the Ghidra project database (Git LFS)
└── tests/fixtures/    a real shipped save file, tracked on purpose
```

## Building

Requires **Lazarus 4.8** with **Free Pascal 3.2.2** and the LCL package.

```bash
lazbuild src/akuji.lpi          # produces src/akuji.exe
```

The game data is **not** in this repository — you need your own copy of the
game. Point the tools at its directory (the one containing `data/`).

## Verifying

One command runs the build, the self-tests and every static check:

```bash
tools/check.sh "/path/to/game directory"
```

It is a commit gate on purpose: a single command, so a broken build cannot slip
through a shell chain. It covers 14 self-test modes, the reference decoders, the
audit ledger, the divergence register, record layouts, table extents, the frame
loop's shape, and a negative control that must fail.

The differential suite is separate because it drives Ghidra headless for
minutes:

```bash
python tools/emudiff.py          # all case sets
python tools/emudiff.py handler_live
```

It executes the **original's own machine code** under Ghidra's emulator and
requires the reconstruction to agree, case by case. Ghidra 12.0.4 is the version
in use.

## Reading order

`CLAUDE.md` first — it is rules, not reference, and it is short. Then:

| | |
|---|---|
| `notes/audited.md` | one row per game function: status, evidence, and whether you may edit it |
| `notes/reference.md` | the decoded formats, tables and structures |
| `notes/status.md` | where the work stands and what is left |
| `notes/verification.md` | the tooling and what the differential sweep has found |
| `notes/divergences.md` | every knowing difference from the binary |
| `notes/function_map.md` | per-function annotations and the evidence for each name |

## Open items

* **The v1.0 binary baseline is stale.** `tools/samebinary.py` fails and
  `check.sh` is red because of it. Splitting the self-tests out of `akuji.lpr`
  moved `.text`; no game function changed length and the differential suite gives
  identical results before and after, but the baseline is deliberately **not**
  re-recorded until the game has been played. See `notes/status.md`.
* **47 game functions are unverified.** Not suspect — unproven.

## Data files

Flat `data\` directory: `tk###.dat` tile maps and `ev###.dat` event scripts (66
each), `surf##.dat` and `spr##.dat` (10 each), plus `system.dat`, `stage.dat`
and `save.dat`. Sound effects are `.wav` under `data\wav\`, music is `.mid`,
and bitmaps come from the `bmp.qda` archive.

`src/gameplay/PlayerState.pas` maps directly onto `save.dat`; changing its packed
record breaks existing saves.

## License

A reverse-engineering project for preservation and study. **Akuji the Demon** is
copyright its respective owners. No game data or original binary is distributed
here.
