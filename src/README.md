# Akuji the Demon — source

The game's source code, reconstructed from `akuji.exe`. The original was never
released; every file here is either recovered verbatim from the binary or
rebuilt from its decompilation.

Targets Free Pascal / Lazarus, so it builds for Windows, Linux, macOS and ARM
from this one tree. That is a property of the language, not a porting layer.

    E:\lazarus\lazbuild.exe akuji.lpi
    akuji.exe --selftest <path-to-bmp.qda> [outdir]   # verify the archive reader

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
| `DDSDComponent.pas` | `TDDSD` | stub — no audio |
| `KbgmPlayer.pas` | `TKbgmPlayer` | stub — no MIDI |
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

## Game layer

| File | Origin |
|---|---|
| `GameState.pas` | state constants, `TGameSettings`, input record |
| `Title.pas` | `Title_MainMenu` `0x462330` — menu, options, gallery |

## Not yet written

Entity system, player controller, collision, scrolling, the state 60/100/140
update path, audio, and event-script command semantics. That is the bulk of the
remaining work — see `../CLAUDE.md` sections 2 and 6.

## Rules

- `../notes/Frm_main.dfm` is the archival form extraction. Do not edit it.
- `GmMain.lfm` is recovered data. If the Lazarus form designer rewrites it,
  diff against the archival copy.
- `PlayerState.TPlayerState` must stay exactly 4580 bytes — `save.dat` is a raw
  image of it with no header or version field. The unit asserts this at startup.
- Check new unit names against LazUtils and LCL before adding them.
