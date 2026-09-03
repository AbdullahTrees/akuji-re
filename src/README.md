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
| `akuji.lpr` | application entry point and executable self-tests |
| `screens/` | main form, menus, dialogue, opening, and ending |
| `gameplay/` | game state, session flow, player, entities, camera, and stages |
| `events/` | event data, command decoding, and script execution |
| `render/` | fonts, surfaces, sprites, tile maps, and background animation |
| `media/` | archive loading, sound effects, PCM output, and MIDI |
| `components/` | Lazarus component wrappers and design-time registration |
| `MsClock.pas` | shared millisecond clock for frames and MIDI timing |
| `UnitInit.pas` | unit initialization table compatibility |

`akuji_components.lpk` installs the custom components needed by the Lazarus
form designer. `screens/GmMain.pas` and `screens/GmMain.lfm` must remain
together because the form unit loads its resource with `{$R *.lfm}`.

## Important data contracts

- `gameplay/PlayerState.pas` maps directly to `data/save.dat`; changing its
  packed record layout breaks existing saves.
- `tools/entity_names.csv` is the authority for identified entity names.
- `screens/GmMain.lfm` is the working form resource. Compare designer rewrites
  with `../notes/Frm_main.dfm` before accepting them.
- `media/AudioOut.pas` and `media/MidiOut.pas` use Windows devices and provide
  silent fallbacks on other platforms.

Repository archaeology and verification details belong under `../notes/` and
`../tools/`; source comments should explain current behavior, invariants, and
non-obvious design constraints.
