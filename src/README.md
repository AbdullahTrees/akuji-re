# Akuji the Demon — source

This is the game's source code, reconstructed from `akuji.exe`. The original was
never released; every file here is either recovered verbatim from the binary or
rebuilt from its decompilation.

It targets Free Pascal / Lazarus, so it builds for Windows, Linux, macOS, and ARM
from this one tree. That is a property of the language, not a porting layer —
there is no "original version" and "ported version", just this.

| File | Status | Provenance |
|---|---|---|
| `akuji.lpr` | **done** | reconstructed from `entry` @ `0x004671ac` |
| `GmMain.lfm` | **done** | decoded verbatim from the binary's TPF0 form resource |
| `GmMain.pas` | *empty* | ~83 methods to rebuild from the decompilation — the real work |
| `DDDDComponent.pas` | *empty* | `TDDDD` — display surface, replaces the DirectDraw component |
| `DDSDComponent.pas` | *empty* | `TDDSD` — sound, 57 channels |
| `DDIDComponent.pas` | *empty* | `TDDIDEX` — input |
| `KbgmPlayer.pas` | *empty* | `TKbgmPlayer` — MIDI playback |

## Recovered identifiers

These are the originals, taken from RTTI and the form resource. Use them.

- unit `GmMain`, class `TFrm_main`, instance `Frm_main` (86 published properties)
- handlers `FormDestroy`, `FormKeyDown`, `DDDD1Init`
- components `DDDD1`, `Joy`, `KbgmPlayer1`, `DDSD1`
- 320x240, windowed, `Position = poDesktopCenter`

## Notes

The four component units are **not** reconstructions of the third-party DirectX
suite the original linked against. They are fresh implementations of the same
published interface, backed by LCL (later SDL2). The form resource documents
which properties and events the game actually depends on.

`GmMain.lfm` will not load until those four classes exist and are registered —
the LFM loader instantiates components by class name.

The pristine extraction of the form resource is at `../notes/Frm_main.dfm`.
Do not edit it; it is evidence, not a build input.
