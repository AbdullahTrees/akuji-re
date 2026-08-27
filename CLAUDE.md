# Akuji the Demon — Project Brief

Reconstructing the source of a 1998 Japanese doujin game from `akuji.exe`. The
original source was never released. The output is **the** source, rebuilt in
Object Pascal — cross-platform because Free Pascal is, not via any porting layer.

Read sections 1–4 before touching anything.

---

## 1. Status

**The rebuilt source builds and runs.** `lazbuild akuji.lpi` in `src/` produces a
working 320x240 window titled "Akuji the Demon". The recovered form loads and all
four component classes resolve, with working sound and music. The game
loop, title menu, save loading and tilemap rendering run; entity logic does not.

Toolchain: Lazarus at `E:\lazarus`, FPC 3.2.2, targets Win64.
Build: `E:\lazarus\lazbuild.exe akuji.lpi`

**Audio works**: 57 effects and 15 MIDI tracks, both readers cross-checked
against independent Python implementations (section 13).

**Next:** the entity system - the ~0x104-byte record, the state 60/100/140
update path, collision, the player controller. The event scripts' *grammar* is
solved (section 8); finding the interpreter is what would give the sub-opcodes
their meaning, and it is likely near the state 100/140 handlers.

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
entry (0x46716c)              the .dpr program block
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
| 60 | `FUN_00454790`, `FUN_00461ba8` — **normal gameplay**; a finished event script returns here |
| 100 | `GameOver_Update` (`0x461a44`), `FUN_00461ba8` — **game over** |
| 130 | `FUN_00461ee4` — **pause**; saves prior state to `0x46cbbc` |
| 140 | `FUN_00454790`, `FUN_00455210`, `FUN_00461ba8` — **event-script runner**; `0x455210` is the interpreter and is NOT yet disassembled |
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
| `+0x08`..`+0x14` | 0,1,2,3 | **key map, FOUR ints** - `FormDestroy` copies `p_KeyMap[0..3]` here. The shipped file holds the identity mapping |
| `+0x18`..`+0x1B` | 1,0,0,0 | four flag bytes, each named by the global `FormDestroy` copies it from: `+0x18` `p_SoftwareVsync` `0x46CE60`, `+0x19` `p_WaitOn` `0x46D2E4`, `+0x1A` `p_FullScreenOn` `0x46D268`, `+0x1B` `p_DebugLog` `0x46CDB8` |
| `+0x24` | 10 | **volume**, clamped 0..10; applied to all 57 channels as `(10 - v) * -0x1C2` |
| `+0x28` | 0 | **omake (extras) selection**, clamped 0..6 |
| `+0x2C`..`+0x32` | 0 | **omake unlock flags**, one byte per extra |
| `+0x34` | 1 | input device; overwritten from `system.ini [device] input` |

`system.ini` is read via an INI object at `Self+0x2E0`. `InstanceSize` is `0x2E8`,
so `+0x2E0`/`+0x2E4` are the form's only non-component fields.

**`FormDestroy` (`0x00466644`) writes this file back on exit** - it is the
settings writer, not just a teardown. It gathers the loose globals into the
record, writes all 56 bytes over `data\system.dat`, and mirrors the fullscreen
flag into `system.ini`'s `[disp]` section as `on`/`off`. It also dumps
`debug.log` when `+0x1B` is set; that is not reproduced.

Because the game now writes this file, a wrong field mapping would corrupt real
settings on first exit. `--selftest-settings <gamedir> <scratchdir>` does a
load/save round trip into a scratch directory and requires it to be byte-exact.
It currently is, and it never touches the game directory.

## 8. Assets — mostly solved

**Most of the asset formats are plain text CSV**, not binary. The files are flat
in `data/`, not in subdirectories (an earlier note claimed `data\spr\` etc.;
that was wrong).

| File | Format | Content |
|---|---|---|
| `stage.dat` | CSV | 66 rows x **16 fields**, filling a **19-int** record (stride `0x4C`). Columns 8..15 land at `rec[11..18]`; `rec[8..10]` are runtime scratch. Mostly constant - see below |
| `spr000..009.dat` | CSV | **7 fields**: surfaceIdx, frameW, frameH, cols, rows, originX, originY — expands to cols*rows frames, numbered sequentially across the file |
| `surf000..009.dat` | CSV | **3 fields**: bitmap name, width, height — 32 slots, bitmaps pulled from `bmp.qda`. Slot 0 is the font, 1 the title background, 2 the options background |
| `ev000..065.dat` | CSV | **solved** - 7 fields, 692 lines over 66 files, none irregular. `Load_Event_Scripts` `0x465B50` scatters them into a 0x24-byte record: csv 0 to +0x00 opcode, 1 to +0x1C, 2 to +0x20, 3 to +0x10, 4 to +0x14, 5 to +0x0C str, 6 to +0x18 str. It also loads `tk*.dat` |
| `tk000..065.dat` | text | **game dialogue**, with escape codes `
` newline, `\e` end, `\k` wait-for-key, `\w`. Not tile data |
| `system.dat` | binary | the 56-byte settings struct, section 7 |
| `save.dat` | binary | **the player state struct, raw** — `FileRead(h, p_PlayerState, 0x11E4)`; 0x11E4 = 4580 = the file size exactly. No header, no checksum, no version |
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

### CAUTION: `SaveGame_Select_Slot` was a bad name

`0x45509C` was called `SaveGame_Select_Slot`. It has nothing to do with save
slots: it advances an event script to its next step and picks which alternative
runs from the progress flags. Renamed `EventScript_AdvanceStep`. Like
`Load_Tile_Data` below it came from the original unverified pass, so treat every
remaining name from that pass as a hypothesis rather than a fact.

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
(`GameFont.pas`), `ev*.dat` and `tk*.dat` (`EventScripts.pas`), the 57 sound
names and 15 MIDI names (`SoundTable.pas`, the form resource), the 81-entry
entity type table and the 64-step direction table (`Entities.pas`,
`Directions.pas`).

### The event mini-language - shape solved, meaning open

`ParamA` and `ParamB` are not values, they are little programs.
`src/EventCommands.pas` parses them; `tools/analyse_events.py` is the second
reader.

**The separators are tier-1** - inferred from the data first, then confirmed in
the code:

| where | what it does |
|---|---|
| `Event_Begin` `0x454EF4` | `StringReplace(ParamB, '/', ',')` then `CommaText` |
| `EventScript_AdvanceStep` `0x45509C` | `StringReplace(step, '.', ',')` then `CommaText` |

Both were read out of the binary as one-character `AnsiString` literals
(refcount `-1`) at `0x455098`/`0x45508C` and `0x45520C`/`0x455200`. The
sub-opcode *meanings* are still open - they live in `0x455210`, which is not
disassembled - so those stay numbered.

    ParamA   <4-digit type>-<letter>[-arg...]    type 14..80, letters * A / M R J
    ParamB   step / step                         steps run in order
             alt . alt                           exactly ONE alternative runs
             <guard>-<subop>[-arg...]            guard = a progress-flag index

`ParamB`'s shape is fixed by the opcode, with no exceptions in 692 records:
opcodes 0/1/4/6/7 carry a program (307), opcode 5 a bare id (154), opcode 9 a
bare id or `*` (231). Every sub-opcode has a fixed arity except 15, which
carries its own length. Arities: 0->5, 3->1, 4->1, 5->1, 7->0, 8->0, 9->1,
10->0, 12->3, 13->0, 15->variable, 16->1, 17->1, 80->0, 99->0.

Two sub-opcodes have outside support. **3 is dialogue** - its argument indexes
the stage's own `tk*.dat`, and all 149 references land in range. **15 is a
list** - arg[1] is a count and exactly that many items follow, true for all 13.

#### The leading number is a guard, not a target

`EventScript_AdvanceStep` picks which alternative runs:

```
for i := Count - 1 downto 0 do
  if Progress[StrToInt(Copy(item[i], 1, 4))] = 1 then
    begin  step := item[i];  break  end
  else
    step := ''
```

Alternatives are scanned **backwards**, so the *last* one whose flag is set
wins, and exactly one runs or none. They are written general-first because flag
0 is set in the shipped save and no event ever writes it - so `0000-` always
matches and acts as the default, placed first precisely because the scan reaches
it last. All 23 distinct guards fall inside the 4501-byte progress block.

23 of the 24 multi-alternative steps follow that convention. The exception,
`0008-80.0000-12-007-1-1`, has them reversed so `0008-80` can never run - an
authoring slip in the original data, reproduced rather than corrected.

**This corrected an earlier reading.** `.` was first documented here as
separating commands that all run. It does not; it separates alternatives of
which one is chosen. `TEventStep.Alternatives` is named to keep that straight.

`ParamA`'s type is bounded 14..80 against `ENTITY_TYPES`' 81 entries, flush at
the top; 0..13 are never placed by a stage, which fits them being spawned by
code. Its **kind letter is an arity marker**, the same role the sub-opcode
plays: `*` 0 args, `A` 1, `/` `J` `R` 2, `M` 3, with no exceptions in 692
records. The letter belongs to the placement, not the type - six types (14, 38,
40, 43, 62, 65) appear both ways, and every one of them mixes only `*` with
`A`, i.e. the same entity placed with or without a parameter.

**Gotcha: `-` is both separator and minus.** In `0030-M-0-0128--4` the last
field is `-4`. A plain split loses the sign, and nothing else in the checks
notices - arity and range still pass. `--selftest-script` pins the count of
negative arguments at 22 for exactly this reason.

### `stage.dat` - surveyed, and mostly constant

Only four of the sixteen columns vary at all. This describes the shipped data,
not the loader - a constant column is unexercised, not proven unused, and
`Load_Stage_Assets` still copies all 16.

| csv | rec | over all 66 rows |
|---|---|---|
| 0 | `[0]` | surface set 0..9, matches `surf000..009.dat` |
| 1 | `[1]` | sprite set 0..9, **equal to csv 0 on every row** |
| 2 | `[2]` | map index - **equals the row number** on rows 1..65; row 0 is `-1` |
| 3,4,6,7 | | `-1` on every row |
| 5 | `[5]` | `6` on every row but row 0, which is `-1` |
| 8..14 | `[11..17]` | `0` on every row - seven dead columns |
| 15 | `[18]` | 0..9, **equal to csv 0 on 65 of 66 rows** |

So a stage has one art set, not two; `rec[2..4]` are three layer slots of which
only the first is ever used; and there are exactly 65 map files for rows 1..65,
with row 0 the "no stage" placeholder - the same flush fit that validated the
sound table.

**csv 15 is a real separate field, and it is not the music.** It differs from
csv 0 on exactly one row - 58, art set 7, csv 15 = 6 - and value 7 appears in
csv 0 only there. The obvious guess is a MIDI index, and `AutoLoadMidis` rules
it out: index 4 is `itemget`, a jingle, yet 13 rows carry csv 15 = 4, and
10..14 are never used. Recorded so the guess is not repeated.

`--selftest-stages` pins all of the above, including the single row-58
exception.

Still open: what the sub-opcodes mean, what csv 5 and csv 15 select, and the
entity type table's 18 columns (`+1C`, `+40`, `+44` are zero for all 81 types). The
progress-flag block is no longer a mystery: an opcode-5 event sets
`Progress[StrToInt(Copy(ParamB, 1, 4))] := 1`, one byte per flag, all 154 resolve
inside the block, and csv 2 holds that same number - the two agree 154/154.
`tk*.dat` is the dialogue those events refer to; its escape codes are identified.

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
- **MIDI.** Resolved - see section 13. The only SysEx is a GM Reset plus two
  Roland GS writes, all in `init.mid`; nothing per-note. Windows plays through
  the system mapper; other platforms need a soft synth behind `MidiOut`.
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

## 11a. Gotcha: unit names can shadow LazUtils and break LCL

A unit called `Maps.pas` broke the build with

    lclintf.ppu: Fatal: Can't find unit LCLIntf used by Themes

which points at LCL, not at the new unit. LazUtils ships its own `Maps` unit
(`TMap`), LCL's `Themes` -> `LCLIntf` chain uses it, and a project unit of the
same name shadows it. Renamed to `TileMaps`.

Two things worth knowing: the error names an LCL unit rather than yours, and
after renaming you must `rm -rf src/lib` — the stale `.ppu` keeps the failure
alive and makes the fix look ineffective. Check new unit names against LazUtils
and LCL before adding them.

## 12. Tooling

Ghidra 12.0.4 + GhidraMCP on `127.0.0.1:8081/sse` (`.mcp.json` at `devel/source`).
Binds at session start — **if it drops, restart the session; it will not
reconnect.** The MCP server can read, rename and retype, but **cannot create or
disassemble functions** — that is GUI-only.

**Reading self-test results.** `akuji.exe` is a GUI-subsystem binary, so the
self-tests write `src/selftest.log` and print nothing to stdout. Check the log
*and* the process exit code - and do not pipe the run through `tail`, because
then `$?` is the pipe's status, not the program's. That mistake made a failing
`--selftest` look green.

Raw disassembly without Ghidra:
`objdump -D -b pei-i386 -M intel --start-address=0x... akuji.exe`
(msys2 at `/c/msys64/mingw64/bin`). Ghidra scripts can be compile-checked with
`javac` against the install's jars.

## 13. Audio - solved and implemented

Both name tables are static `array of AnsiString` in DATA, reached through a
global pointer. Lengths come from the unit finalisation at `0x00452543`, which
calls `_FinalizeArray(base, AnsiString, count)` - so they are read off, not
counted by hand:

| Global ptr | Array | Count | Contents |
|---|---|---|---|
| `p_SoundNames` `0x0046D0EC` | `0x00468D50` | 57 (`$39`) | the effect files |
| `p_MidiNames` `0x0046D154` | `0x00468D14` | 15 (`$0F`) | the playlist |

**`ChannelCount = 57` is not polyphony.** It is one DirectSound buffer per
effect - 57 names, 57 files in `wav/`, the two sets equal with nothing left over
either way. Slot number and sound number are the same thing.

`TDDSD_Play` (`0x00450FD8`) takes `(Self, Index, Restart)` in EAX/EDX/CL and
rewinds when `CL = 1`. **All 104 call sites pass 1**, so effects always retrigger
and never layer. `TKbgmPlayer`'s methods take the *name*, not an index - the play
method refcounts an AnsiString in EDX.

`Title_Init` (`0x0046214C`) is fully traced, including the volume sweep
`for i := 0 to $38 do SetVolume(-(10 - Settings[$24]) * $1C2)` - the DirectSound
attenuation curve, full at 10 and -45 dB at 0. Its `Font_Define` arguments match
`GameFont.pas` exactly, which independently confirms those constants.

Formats: every effect is PCM mono, 8 or 16 bit, at 11025 or 22050 Hz - so
mixing at 22050 needs no fractional resampling. Every MIDI file is format 1 at
48 ticks per quarter. `main01.mid` and `end05.mid` are byte-identical.

Implemented as `SoundTable` / `WaveFile` / `AudioMixer` / `AudioOut` and
`MidiFile` / `MidiOut` / `KbgmPlayer`. Only the two `*Out` units are
platform-specific. Call map: `notes/audio_map.md`.

## 14. How this is verified

A byte-identical rebuild is impossible - different compiler, different RTL,
64-bit target - so correctness is established three other ways, in descending
order of strength:

1. **Two independent readers agreeing.** Every binary format is implemented
   twice, once in Pascal and once in Python from the same evidence, and diffed:
   44/44 QDA entries byte-identical, 57/57 effects byte-identical after
   decoding, 15/15 MIDI tracks matching on a checksum of the *merged* event
   stream (which also validates the track merge, not just the chunk walk).
   The event mini-language is checked the same way: `--selftest-script` and
   `tools/analyse_events.py` are independent splitters that agree line for line
   on every count.
   Run `--selftest`, `--selftest-audio`, `--selftest-midi`, `--selftest-script`,
   then the matching `tools/*_ref.py` / `analyse_events.py`.
   `--selftest-stages` is a different kind of check - it has no second reader,
   and instead pins the relationships `stage.dat` exhibits (csv0 = csv1,
   csv2 = row number, csv15 = csv0 on exactly 65 rows) so that documented
   claims about the data cannot quietly rot.
2. **Self-validating structure.** The QDA directory plus the sum of its entry
   sizes equals the file length exactly; every `.map` is exactly
   `24 + w*h*2` bytes; `save.dat` is exactly `SizeOf(TPlayerState)`, asserted at
   startup; the sound-name array terminates cleanly right where the key-name
   array begins; every event sub-opcode has a fixed argument count and sub-op 15
   carries its own length, over 518 commands with no exceptions.
3. **Cross-corroboration between unrelated parts of the binary.** The form
   resource's `ChannelCount = 57` matches the name array length and the file
   count. `Title_Init`'s `Font_Define` arguments match constants derived
   separately from the font sheet. The DFM's `AutoLoadMidis` matches the static
   name array entry for entry.

What this does **not** cover is game logic behaviour - entity movement,
collision, scoring. Establishing that needs differential tracing against the
running original, which has not been set up. A cheap way in when it matters:
`kbgm32.dll` is an ordinary DLL with 13 named exports, so a logging proxy would
give exact ground truth for the music layer. It needs a 32-bit toolchain, which
this machine does not currently have.
