# Akuji the Demon — source

The game's source code, reconstructed from `akuji.exe`. The original was never
released; every file here is either recovered verbatim from the binary or
rebuilt from its decompilation.

Targets Free Pascal / Lazarus, so it builds for Windows, Linux, macOS and ARM
from this one tree. That is a property of the language, not a porting layer.

    E:\lazarus\lazbuild.exe akuji.lpi

    ../tools/check.sh          # build + every check, one command

`check.sh` is the commit gate — use it as `tools/check.sh && git commit`. It
exits non-zero if anything fails, which a hand-written shell chain has twice
failed to do here.

The individual modes, if you want one:

    akuji.exe --selftest <bmp.qda> [outdir]         # archive reader
    akuji.exe --selftest-audio <gamedir> [pcmdir]   # all 57 effects
    akuji.exe --selftest-midi <gamedir>             # all 15 tracks
    akuji.exe --selftest-dir <gamedir>              # directions, entity record
    akuji.exe --selftest-events <gamedir>           # ev*.dat / tk*.dat
    akuji.exe --selftest-script <gamedir>           # the event mini-language
    akuji.exe --selftest-stages <gamedir>           # stage.dat relationships
    akuji.exe --selftest-player <gamedir>           # camera, helpers, player
    akuji.exe --selftest-trace <gamedir>            # the controller, frame by frame
    akuji.exe --selftest-settings <gamedir> <scratch>

`akuji.exe` is a GUI-subsystem binary, so these print nothing to stdout — each
writes `selftest.log`. Read the log **and** the unpiped exit code; piping the
run through `tail` gives you the pipe's status, not the program's. The
`tools/*_ref.py` scripts re-derive the same numbers independently and diff
against it.

## Layout

Deliberately flat. FPC units are flat-namespaced — a subdirectory would not
create `graphics.Sprites`, it would still be `Sprites`, so folders buy filing
without encapsulation and cost a search-path entry. Unit names are globally
unique whatever directory they sit in: `Maps.pas` collided with LazUtils' own
`Maps` unit and had to become `TileMaps`, and nesting it would not have helped.
The original Delphi project was one directory too.

Revisit past roughly 40 units, and use dotted unit names (`Akuji.Graphics.Font`)
rather than directories — that is the Pascal-native answer.

## Entry point

| File | Provenance |
|---|---|
| `akuji.lpr` | reconstructed from `entry` @ `0x004671AC` |
| `akuji.lpi` | project file; hand-written, not IDE-generated |
| `GmMain.lfm` | **recovered verbatim** from the binary's TPF0 form resource |
| `GmMain.pas` | `TFrm_main` — frame loop, state dispatch, stage loading |

## Component layer

Replacements for the third-party DirectX suite the original linked against.
Not reconstructions of it — fresh implementations of the same published
interface, which `GmMain.lfm` documents.

| File | Class | State |
|---|---|---|
| `DDDDComponent.pas` | `TDDDD` | `Clear`/`Present`/`DrawSprite` implemented over LCL |
| `DDIDComponent.pas` | `TDDIDEX` | stub — key state only, no rebinding |
| `DDSDComponent.pas` | `TDDSD` | 57 effects, mixed and played |
| `KbgmPlayer.pas` | `TKbgmPlayer` | MIDI sequencer, 15 track playlist |
| `AkujiReg.pas` | — | design-time registration, packaged by `akuji_components.lpk` |

## Data layer — all formats solved and cross-checked

| File | Reads | From |
|---|---|---|
| `QdaArchive.pas` | `bmp.qda` (QDA0, 44 uncompressed BMPs) | `0x00449E78` era code |
| `Surfaces.pas` | `data\surf%.03d.dat` | `Load_Surface_Textures` `0x465E9C` |
| `Sprites.pas` | `data\spr%.03d.dat` | `Load_Sprite_Sheets` `0x4660B8` |
| `Stages.pas` | `data\stage.dat` | `Load_StageTable` `0x4669F8` |
| `TileMaps.pas` | `map\%.03d.map` | `Load_Map` `0x466340` |
| `PlayerState.pas` | `data\save.dat` | `Game_StartOrLoad` `0x462F40` |
| `GameFont.pas` | the 9x9 sheet | `Font_Define` `0x4511A0`, `Game_DrawText` `0x4511EC` |
| `EventScripts.pas` | `data\ev*.dat`, `data\tk*.dat` | `Load_Event_Scripts` `0x465B50` |
| `EventCommands.pas` | the mini-language inside those records | `EventScript_Execute` `0x455210` |

## Audio layer

Portable except for the two device units. The original mixed in hardware via
one DirectSound buffer per effect; here the mixing is done in software so the
only platform-specific code is the output device.

| File | Role | Portable |
|---|---|---|
| `SoundTable.pas` | the 57 effect names, from the array at `0x00468D50` | yes |
| `WaveFile.pas` | RIFF reader (original used winmm `mmio*`) | yes |
| `AudioMixer.pas` | one voice per effect slot, the original's volume curve | yes |
| `AudioOut.pas` | output device - `waveOut` on Windows, null elsewhere | **no** |
| `MidiFile.pas` | SMF reader, tracks merged and timed | yes |
| `MidiOut.pas` | MIDI device - winmm on Windows, null elsewhere | **no** |

Adding Linux or macOS sound means implementing `AudioOut` and `MidiOut` and
nothing else. See `../notes/audio_map.md` for the recovered call map.

## Game layer

| File | Origin |
|---|---|
| `GameState.pas` | state constants, `TGameSettings`, input record |
| `Title.pas` | `Title_MainMenu` `0x462330` — menu, options, gallery |
| `Entities.pas` | the pool, the 81-entry type table, the record layout |
| `Directions.pas` | the 64-step angle system, both tables confirmed |
| `PlayerState.pas` | `save.dat`, and the player controller's state machine |
| `Camera.pas` | the scrolling dead zone and the map-edge clamp |
| `Player.pas` | **the player controller, as running code** - the first behaviour |

`Entities.pas` and `PlayerState.pas` carry long header comments recording what
each field means and what the evidence for it was. That is deliberate: the
entity record has 65 integer slots and several are reused for different things
by role — `$24` is hit points on a target and damage on a projectile, `$1C` is
a timer with three separate uses. Read the headers before naming anything new.

## Not yet written

The entity behaviours themselves — roughly 100 per-type update handlers, plus
scrolling and the three special-move routines `Player_Update` delegates to. The
*structure* around them is decoded: the dispatcher, the record, collision,
death, damage, and the player's own state machine. See `../CLAUDE.md` section
8a.

Event opcodes 4 and 9 also remain, and the entity type table has 18 columns of
which only two are decoded outright (the destination of all 18 is known).

## Rules

- `../notes/Frm_main.dfm` is the archival form extraction. Do not edit it.
- `GmMain.lfm` is recovered data. If the Lazarus form designer rewrites it,
  diff against the archival copy.
- `PlayerState.TPlayerState` must stay exactly 4580 bytes — `save.dat` is a raw
  image of it with no header or version field. The unit asserts this at startup.
- Check new unit names against LazUtils and LCL before adding them.
