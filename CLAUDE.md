# Akuji the Demon — Project Brief

Reconstructing the source of a 1998 Japanese doujin game from `akuji.exe`. The
original source was never released. The output is **the** source, rebuilt in
Object Pascal — cross-platform because Free Pascal is, not via any porting layer.

Read sections 1–4 before touching anything.

---

## 1. Status

**The rebuilt source builds and runs.** `lazbuild akuji.lpi` in `src/` produces a
working 320x240 window titled "Akuji the Demon". The recovered form loads and all
four component classes resolve. No game logic yet.

Toolchain: Lazarus at `E:\lazarus`, FPC 3.2.2, targets Win64.
Build: `E:\lazarus\lazbuild.exe akuji.lpi`

**Next:** translate the state handlers (section 6) into `GmMain.pas`.

## 2. The three layers — most important section

The binary is not "game code plus Windows APIs". Only the innermost is Akuji's:

| Layer | Marker classes | ~Fns | Do |
|---|---|---|---|
| Borland RTL + VCL | `TObject`, `TCanvas`, `TForm`, `TApplication` | ~1597 | **Skip** — FPC RTL + LCL replace it |
| Third-party DirectX suite | `TDDDD`, `TDDSD`, `TDDIDEX`, `TKbgmPlayer` | ~191 | **Replace wholesale** |
| **Akuji** | **`TFrm_main`** + units | **~83** | **Write this** |

### Address-range rule

Delphi links its own units first, so library code sits low:

| Range | Contents |
|---|---|
| `0x402000`–`0x408fff` | Delphi RTL (`System.pas`) |
| `0x417000`–`0x425fff` | VCL (`Graphics.pas`, `Controls.pas`) |
| `0x439000`–`0x443fff` | VCL (`Forms.pas`) |
| `0x444000`–`0x455000` | Third-party DirectX components |
| `0x455000`+ | **The game** |

**A game-sounding name below `0x444000` is wrong until proven otherwise.**

## 3. Naming rules

The costliest mistake here was **naming functions after the Win32 API they call**.
That produced 19 "confirmed" names that were all Borland library code — an entire
"Game Loop" section that was really `TApplication`'s tooltip implementation, and
`VCL_Message_Loop` (`0x004038f4`), which contains no message pump at all and is
`System._Halt0`, the shutdown path.

1. Check the address range first.
2. Name from the **cluster**, not the callee — read callers and callees.
3. Never mark confirmed without cross-function evidence. "Likely" is honest.
4. Before keeping an auto-created struct, check whether a standard type fits. One
   here turned out to be `tagPOINT`, which already existed.

### Ghidra mislabels this binary constantly

Functions reachable only through RTTI or a VMT slot have **no call xrefs**, so
auto-analysis guesses, and guesses wrong. `0x465584` was typed as a `longdouble`;
the RTTI record at `0x464D10` was disassembled as code, and its runaway decoding
swallowed the entry byte of the function at `0x464D30`.

To fix one: `G` → address, `C` (clear), `D` (disassemble), `F` (create function).
Clear mis-decoded bytes *before* the entry too. Assume more are still hidden.

## 4. How Pascal is recovered

Ghidra cannot emit Pascal; there is no transpiler. Translation is manual, but:

**The form design is recovered verbatim.** Delphi embeds it as a `TPF0` resource.
Decoded to `notes/Frm_main.dfm` (archival) and `src/GmMain.lfm` (working). It gave
up real identifiers — use them:

- unit `GmMain`, class `TFrm_main` (86 published props, 744-byte instance),
  instance `Frm_main`
- handlers `FormDestroy`, `FormKeyDown`, `DDDD1Init`
- components `DDDD1` (`+0x2D0`), `Joy` (`+0x2D4`), `KbgmPlayer1` (`+0x2D8`),
  `DDSD1` (`+0x2DC`) — offsets confirmed against the RTTI field table
- 320x240, windowed, `Use3D = False`

**Idioms map mechanically:**

| Decompiled | Pascal |
|---|---|
| `Delphi_AnsiString_Assign(&a, b)` | `a := b;` |
| `Delphi_AnsiString_AddRef` / decref | *delete* — the compiler emits these |
| `FS:[0]` frame + `LAB_xxx` handler | `try...finally` |
| `(**(code **)(*obj + 0x2C))(obj, ...)` | `obj.SomeMethod(...)` |
| `Delphi_TObject_Free(x)` | `x.Free;` |
| `param_1` on a method | `Self` |
| byte-sized bit ops on a small range | a `set of` |

**Verified RTL helpers** (evidence-backed, trust these): `Delphi_GetMem`
`004026d8`, `Delphi_FreeMem` `004026f0`, `Delphi_TObject_Free` `00402da4`,
`Delphi_FillChar` `00406a50`, `Delphi_AnsiString_Assign` `00403cf8`,
`Delphi_AnsiString_AddRef` `00403e60`, `Delphi_IntToStr` `00407f64`,
`Delphi_FileOpen` `00407ff8`, `Delphi_FileRead` `0040805c`.

## 5. Program structure — fully mapped

```
entry (0x4671ac)              the .dpr program block
  Application.Initialize
  Application.Title := 'Akuji the Demon'
  Application.CreateForm(TFrm_main, Frm_main)
  Application.Run          -> TApplication_Run (0x44298c)
                                repeat HandleMessage until Terminated
                                  -> TApplication_Idle (0x442f8c)
                                       -> FOnIdle == TFrm_main_AppIdle
```

`TFrm_main` **overrides no virtual methods** — its VMT is identical to `TForm`'s.
The game has exactly three published entry points:

| Address | Method |
|---|---|
| `0x00465584` | `TFrm_main_DDDD1Init` — init |
| `0x004665C8` | `FormKeyDown` — first test is VK_ESCAPE |
| `0x00466644` | `FormDestroy` |

`DDDD1Init` loads settings, then installs the loop:
`Application.FOnIdle := TFrm_main_AppIdle` (`+0xD8` code, `+0xDC` data).

## 6. The frame loop — `TFrm_main_AppIdle` @ `0x00464D30`

Sets `Done := False`, so `TApplication_Idle` skips `WaitMessage` and re-enters
immediately. That busy loop is the game's frame tick. Per frame:

1. `Done := False`
2. poll `Joy` — 3 device paths, chosen by `Settings+0x34` (`system.ini [device] input`)
3. poll 4 buttons via `p_KeyMap` into `p_InputState+0x1C`
4. `FUN_00449e78(DDDD1)` — begin frame
5. **state dispatch** (below)
6. sprite/entity update — `FUN_0044d758`, `FUN_0044d1e0`, `FUN_0044d31c` x8 layers
7. button edge-detection and repeat timers
8. `FUN_00449d00(DDDD1)` — present
9. frame limiter

### State machine — `p_GameState` (`0x0046d06c`), steps of 10

| Value | Handler |
|---|---|
| 10 | `Stage_Init` (`0x46214c`) |
| 20 | `Title_MainMenu` (`0x462330`) |
| 30 | `FUN_00462210` |
| 40 | `Game_Init_PlayerState` (`0x462f40`) |
| 60 | `FUN_00454790`, `FUN_00461ba8` |
| 100 | `FUN_00461a44`, `FUN_00461ba8` |
| 130 | `FUN_00461ee4` — **pause**; saves prior state to `0x46cbbc` |
| 140 | `FUN_00454790`, `FUN_00455210`, `FUN_00461ba8` |
| 150 | `FUN_00463624` |
| 999 | **quit** — nils `FOnIdle`, calls `FUN_00442a40` |

Also dispatched: `TitleMenu_Update` when `0x46cf28 <> 0`, `FUN_004568d0` when
`0x46cd00 <> 0`.

### Frame limiter — replace this

```
while (timeGetTime() - LastFrameTime <= 15) { }   // busy-wait
LastFrameTime := timeGetTime();
```

~60 FPS via spin-wait, gated by a flag at `0x46ce60`. Combined with
`Done := False` this **pegs a CPU core at 100%**. Use a real sleep in the rebuild.

### Named globals

`p_GameState` `0x46d06c`, `p_InputState` `0x46cc58`, `p_KeyMap` `0x46cea8`,
`p_Settings` `0x46d0e8`, `p_LastFrameTime` `0x46d1e0`.

## 7. Settings — `data\system.dat`, 56 bytes

`DDDD1Init` writes defaults into `p_Settings`, then `FileRead(h, p_Settings, 0x38)`
overwrites them.

| Offset | Default | Meaning |
|---|---|---|
| `+0x04` | 0 | **game level / difficulty**, clamped 0..2 by the options screen |
| `+0x08`..`+0x14` | 1,2,3 | **key map** — copied to `p_KeyMap`; rows 2..4 of the options screen rebind these |
| `+0x18`..`+0x1B` | 1,0,1,0 | flags; `+0x1A` = fullscreen |
| `+0x24` | 10 | **volume**, clamped 0..10; applied to all 57 channels as `(10 - v) * -0x1C2` |
| `+0x28` | 0 | **omake (extras) selection**, clamped 0..6 |
| `+0x2C`..`+0x32` | 0 | **omake unlock flags**, one byte per extra |
| `+0x34` | 1 | input device; overwritten from `system.ini [device] input` |

`system.ini` is read via an INI object at `Self+0x2E0`. `InstanceSize` is `0x2E8`,
so `+0x2E0`/`+0x2E4` are the form's only non-component fields.

## 8. Assets — mostly solved

**Most of the asset formats are plain text CSV**, not binary. The files are flat
in `data/`, not in subdirectories (an earlier note claimed `data\spr\` etc.;
that was wrong).

| File | Format | Content |
|---|---|---|
| `stage.dat` | CSV | `0,	0,	-1,-1,-1,	...` — per-stage integer rows |
| `spr000..009.dat` | CSV | **7 fields**: surfaceIdx, frameW, frameH, cols, rows, originX, originY — expands to cols*rows frames, numbered sequentially across the file |
| `surf000..009.dat` | CSV | **3 fields**: bitmap name, width, height — 32 slots, bitmaps pulled from `bmp.qda`. Slot 0 is the font, 1 the title background, 2 the options background |
| `ev000..065.dat` | CSV | `9,0000,1001,0019,0008,0014-*,1001` — event scripts |
| `tk000..065.dat` | text | **game dialogue**, with escape codes `
` newline, `\e` end, `\k` wait-for-key, `\w`. Not tile data |
| `system.dat` | binary | the 56-byte settings struct, section 7 |
| `save.dat` | binary | 4580 bytes — **not yet decoded** |
| `bmp.qda` | QDA0 archive | 9.1 MB, 44 uncompressed 24-bit BMPs |

### QDA0 archive — solved and implemented

```
0x00   4      zero
0x04   4      magic "QDA0"
0x08   4      entry count (44)
0x0C   244    zero padding to 0x100
0x100  n*268  directory
...           data, in directory order

entry (268 bytes):
  +0x00  4    absolute offset
  +0x04  4    size
  +0x08  4    size again (room for compression; unused here)
  +0x0C  256  NUL-terminated name
```

Self-validating: directory size plus the sum of all entry sizes equals the file
length exactly. Contents are plain uncompressed 24-bit BMPs at assorted sizes
(320x240, 320x320, 240x180, 288x54, ...), so `TBitmap` loads them directly.

**Implemented as `src/QdaArchive.pas`**, verified byte-identical against the
reference extractor `tools/extract_qda.py` across all 44 entries
(`akuji.exe --selftest <qda> <outdir>`, writes `selftest.log`).

**Names are case-inconsistent** — the archive holds `title.BMP` and `sys.BMP`
while the `.dat` metadata says `title.bmp`. Lookups must be case-insensitive;
matching exactly silently fails on roughly a third of the archive.

### `map/*.map` — level tilemaps, solved

Loaded by `Load_Map` `0x466340` as `map\%.03d.map`. 65 files, **all validate**:

```
int32  MapWidth, MapHeight      tiles
int32  TileWidth, TileHeight    pixels
int32  SheetCols, SheetRows     tileset layout
uint16 [MapWidth * MapHeight]   tile indices, row-major
```

`001.map` is 30x24 tiles of 32x32 = a 960x768 level from a 10x10 tileset.
Size is always exactly `24 + MapWidth*MapHeight*2`.

Globals: `p_TileMaps` `0x46cdec` (per-layer tilemap objects), `p_LayerInfo`
`0x46d144` (0x20-byte records: `+0x10` tileW, `+0x14` tileH, `+0x18` mapW,
`+0x1C` mapH), `p_Surfaces` `0x46d344` (32 slots), `p_UseArchive` `0x46ccb4`
(set to 1 by `DDDD1Init`, selects `bmp.qda` over loose files).

### CAUTION: `Load_Tile_Data` was a bad name

`0x466340` was listed as `Load_Tile_Data` reading `data	k\`. Both halves were
wrong: it reads `map\*.map`, and `tk*.dat` is dialogue text. The name came from
the original unverified pass and was believed on sight during this session,
costing a wrong hypothesis and a failed validation run.

The `Load_*` names in section 8's table are from that same pass. **Verify the
filename each one actually builds before trusting it** — the string literals sit
right next to the `%.03d` format in the disassembly.

### Remaining asset work

Solved and implemented in Pascal: `bmp.qda` (`QdaArchive.pas`), `map/*.map`,
`surf*.dat` (`Surfaces.pas`), `spr*.dat` (`Sprites.pas`), the 9x9 font
(`GameFont.pas`).

Still open: `save.dat` (4580 bytes, binary), `stage.dat` column meanings, and
`ev*.dat` event-script opcodes. `tk*.dat` is dialogue text whose escape codes
(`
`, `\e`, `\k`, `\w`) are identified but whose consumer is not yet traced.

## 9. Input map (from `DirectInput_Init` `0x453bdc`)

| DIK | Keys | Function |
|---|---|---|
| `0x2C`–`0x2E` | Z, X, C | actions |
| `0x1E`–`0x20` | A, S, D | secondary |
| `0x02`–`0x0B` | 1–0 | item select |
| `0x39` | Space | jump |
| `0xC8`–`0xCD` | arrows | movement |
| `0x47`–`0x51` | numpad | alt movement |

## 10. Hazards that survive the rewrite

- **8-bit palettes.** Original uses `SelectPalette`/`RealizePalette`. Modern
  drivers have no hardware palettes. Convert indexed surfaces to RGBA at load.
- **Frame timing.** See section 6 — replace the spin-wait.
- **MIDI.** `Kbgm32.dll` drives the system MIDI mapper with SysEx. Options: a
  Pascal MIDI library, FluidSynth, or pre-render the 15 tracks to OGG.
- **Write paths.** Original writes beside the exe and to
  `HKCU\Software\Borland\Delphi\RTL`. Use a per-user config dir.
- **Shift-JIS.** The game is Japanese in origin; data-file text is not UTF-8.

## 11. Decisions

**Free Pascal + Lazarus LCL**, SDL2 later only if measured. Not C++: that would
mean reimplementing the Delphi runtime *and* translating at once, with no working
reference to check against. The deleted `SDL_port_plan.md` (recoverable at
`77f415b`) listed nine compiler/ABI problems for a C++ rewrite — **targeting
Pascal removes eight**, because in Pascal they are language features. The project
is private, so the "C++ has more contributors" argument was weighed and rejected.

D3DRM is a non-issue: `Direct3DRMCreate` is a static import belonging to the
DirectX component layer, not the game, and the form sets `Use3D = False`. It
leaves with the layer.

Other notes: `notes/function_map.md` (detailed annotations), `notes/Frm_main.dfm`
(archival, do not edit), `src/README.md` (file-by-file status).

## 12. Tooling

Ghidra 12.0.4 + GhidraMCP on `127.0.0.1:8081/sse` (`.mcp.json` at `devel/source`).
Binds at session start — **if it drops, restart the session; it will not
reconnect.** The MCP server can read, rename and retype, but **cannot create or
disassemble functions** — that is GUI-only.

Raw disassembly without Ghidra:
`objdump -D -b pei-i386 -M intel --start-address=0x... akuji.exe`
(msys2 at `/c/msys64/mingw64/bin`). Ghidra scripts can be compile-checked with
`javac` against the install's jars.
