# Akuji the Demon source

This directory contains the Free Pascal/Lazarus implementation of the game.
Pascal unit names remain flat; the folders group units by responsibility and
are included through the project search path.

## Build and verification

Build `akuji.lpi` with Lazarus, or run the complete repository gate from the
repository root:

    tools/check.sh

The executable is a GUI application. Self-test modes write their results to
`selftest.log` beside the executable instead of printing to a console.

The v1.0 executable is the runtime-fidelity baseline. Changes to executable
code or initialized data must be intentional and checked with
`tools/samebinary.py --where`. Consult `../notes/audited.md` before changing a
game routine: verified routines are protected by `tools/audited.py`, and entity
handler changes also require the `handler_live` differential suite.

## Source layout

| Path | Responsibility |
|---|---|
| `akuji.lpr` | application entry point - chooses between a self-test and the game |
| `screens/` | main form, menus, dialogue, opening, and ending |
| `gameplay/` | game state, session flow, player, entities, camera, and stages |
| `events/` | event data, command decoding, and script execution |
| `render/` | fonts, surfaces, sprites, tile maps, and background animation |
| `media/` | archive loading, sound effects, PCM output, and MIDI |
| `components/` | Lazarus component wrappers and design-time registration |
| `selftests/` | the executable's self-test modes, one unit per subject |
| `MsClock.pas` | shared millisecond clock for frames and MIDI timing |
| `UnitInit.pas` | unit initialization table compatibility |

`akuji_components.lpk` installs the custom components needed by the Lazarus
form designer. `screens/GmMain.pas` and `screens/GmMain.lfm` must remain
together because the form unit loads its resource with `{$R *.lfm}`.

`selftests/SelfTests.pas` owns the command-line switches. They are listed once,
in `SELFTEST_MODES`, and both the program's "is this a self-test?" test and the
dispatcher read that list - so adding a mode cannot leave the program
recognising a switch it has no branch for, or the reverse. A test unit's name
must not match a routine it exports, because the unit name shadows it at the
call site: that is why they are `StageTests.SelfTestStages` and not
`SelfTestStages.SelfTestStages`.

## Important data contracts

- `gameplay/PlayerState.pas` maps directly to `data/save.dat`; changing its
  packed record layout breaks existing saves.
- `tools/entity_names.csv` is the authority for identified entity names.
- `screens/GmMain.lfm` is the working form resource. Compare designer rewrites
  with `../notes/Frm_main.dfm` before accepting them.
- `media/AudioOut.pas` and `media/MidiOut.pas` use Windows devices and provide
  silent fallbacks on other platforms.
- `tools/layout_lock.py` reads `selftests/LayoutTests.pas`, and
  `notes/implemented_map.tsv` names the routine implementing each game
  address. Moving a routine between units means updating both.

Repository archaeology and verification details belong under `../notes/` and
`../tools/`; source comments should explain current behavior, invariants, and
non-obvious design constraints.
