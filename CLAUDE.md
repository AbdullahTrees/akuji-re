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

**The entity system is largely decoded** - the record, the dispatcher, the
collision path, the death and damage rules, and the player controller. See
section 15.

**The event system is now decoded end to end** - both halves of the mini-language
AND the placement machinery around it: what makes an event spawn, what makes it
stop existing for good, and how difficulty selects placements. Section 8b.

**Coverage** (`python tools/coverage.py`): 55 of 149 game-layer functions have
a Pascal counterpart, and 102 of the 149 carry real names. The denominator has
moved twice - 48 hidden handlers created (section 12), then the game-layer floor
corrected from `0x455000` to `0x454790`. The work did not grow either time.

**The player controller now RUNS.** `src/Player.pas` is the first piece of game
behaviour written as executing code rather than described in a comment - the
whole state machine including the glide, air dash and knockback. Section 14a.

**Before committing, run `tools/check.sh`.** One command: build, ten
self-tests, three reference implementations, a records check and a negative
control. It exits non-zero on any failure, so use it as
`tools/check.sh && git commit`.

**Next:** the 74 remaining entity-type handlers. Read and write each one
together - they are the same task, and `EntityHandlers.EntityUpdateAll` now
gives them somewhere to plug in. `HANDLER_ADDR` is the to-do list, and it comes
out of the binary's own jump table rather than being transcribed by hand.
The event system has no open questions left.

## 2. The three layers — most important section

The binary is not "game code plus Windows APIs". Only the innermost is Akuji's:

| Layer | Marker classes | ~Fns | Do |
|---|---|---|---|
| Borland RTL + VCL | `TObject`, `TCanvas`, `TForm`, `TApplication` | ~1597 | **Skip** — FPC RTL + LCL replace it |
| Third-party DirectX suite | `TDDDD`, `TDDSD`, `TDDIDEX`, `TKbgmPlayer` | ~191 | **Replace wholesale** |
| **Akuji** | **`TFrm_main`** + units | **139** | **Write this** |

### Address-range rule

Delphi links its own units first, so library code sits low:

| Range | Contents |
|---|---|
| `0x402000`–`0x408fff` | Delphi RTL (`System.pas`) |
| `0x417000`–`0x425fff` | VCL (`Graphics.pas`, `Controls.pas`) |
| `0x439000`–`0x443fff` | VCL (`Forms.pas`) |
| `0x444000`–`0x45478f` | Third-party DirectX components |
| `0x454790`+ | **The game** |

The floor has moved twice, both times because a function was read and turned out
to be the game's: `0x455000` -> `0x454EF4` (`Event_Begin`) -> `0x454790`
(`Events_SpawnNearCamera`). It is the lowest address **proved** to be game code,
not a proof about anything below it.

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

## 3a. Working rule: write the code as you read the disassembly

**Translate each function to Pascal in the same breath as decompiling it.** Do
not decompile a batch and write them up afterwards.

Decompiled detail decays fast. A batched write is reconstructed from memory or
from one's own summary notes rather than from the disassembly, and that is where
invented field names and quietly-dropped details come from. Measured on this
project: functions translated immediately came out clean; ones read early and
written hours later had lost their reasoning (an unexplained `-0x80`) and
regressed to raw offsets instead of the names already established for them.
Functions read in a *previous* session were worse - rebuilt entirely from notes.

Writing is also the error detector. `EF_HP`, the minus-sign field split and the
one-byte `TPlayerState` were all caught by writing the thing down and running
it, not by reading harder.

So: **decompile, translate, build, test, commit, next.** One function at a time.
The exception is a decode that genuinely needs several functions in view at once
- opcode 9 needed the touch handlers plus the shipped data together - and even
there, write each one before moving on rather than deferring all of them.

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
| 30 | `FUN_00462210` — entered by event sub-op 0 after a stage load |
| 40 | `Game_Init_PlayerState` (`0x462f40`) |
| 60 | `FUN_00454790`, `FUN_00461ba8` — **normal gameplay**; a finished event script returns here |
| 100 | `GameOver_Update` (`0x461a44`), `FUN_00461ba8` — **game over** |
| 130 | `FUN_00461ee4` — **pause**; saves prior state to `0x46cbbc` |
| 140 | `FUN_00454790`, `EventScript_Execute` (`0x455210`), `FUN_00461ba8` — **event-script runner** |
| 150 | `FUN_00463624` — entered by event sub-op 80 (`soulget`) |
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

### CAUTION: three names from the original pass were wrong

`SaveGame_Select_Slot` (`0x45509C`) has nothing to do with saves — it advances an
event script. `Load_Tile_Data` (`0x466340`) does not read `data\tk\` — it reads
`map\*.map`, and `tk*.dat` is dialogue. `Configure_Stage_Params` hid the terrain
id. All three read plausibly, all three were believed on sight, and each cost
real time. `notes/function_map.md` records what they actually are.

**Every remaining name from that pass is a hypothesis.** For the `Load_*` names
in section 8, verify the filename each one actually builds — the string literals
sit right next to the `%.03d` format in the disassembly.

### Remaining asset work

Solved and implemented in Pascal: `bmp.qda` (`QdaArchive.pas`), `map/*.map`,
`surf*.dat` (`Surfaces.pas`), `spr*.dat` (`Sprites.pas`), the 9x9 font
(`GameFont.pas`), `ev*.dat` and `tk*.dat` (`EventScripts.pas`), the 57 sound
names and 15 MIDI names (`SoundTable.pas`, the form resource), the 81-entry
entity type table and the 64-step direction table (`Entities.pas`,
`Directions.pas`).

### The event mini-language — solved

`ParamA` and `ParamB` in `ev*.dat` are not values, they are little programs.
**`src/EventCommands.pas` carries the full decode**; this is the shape.

    ParamA   <4-digit type>-<letter>[-arg...]   type 14..80; the letter is an
                                                arity marker: * 0, A 1,
                                                / J R 2, M 3
    ParamB   step / step                        steps run in order
             alt . alt                          exactly ONE alternative runs
             <guard>-<subop>[-arg...]           guard = a progress-flag index

Both separators are **tier-1**, read out of the binary as one-character
`AnsiString` literals: `Event_Begin` `0x454EF4` does
`StringReplace(ParamB, '/', ',')` and `EventScript_AdvanceStep` `0x45509C` does
`StringReplace(step, '.', ',')`, each followed by `CommaText`.

**The interpreter reads fixed positions, not dash-separated fields.**
`EventScript_Execute` `0x455210` pulls `Copy(alt, 6, 2)` for the sub-opcode and
arguments at 9, 14, 19, 24, 29 with per-opcode widths — which is why every
number in the data is zero-padded. `EventCommands.pas` splits on `-` anyway
because it is more legible and rejects malformed input; `--selftest-script`
verifies the two agree over **988 arguments, 0 disagreements**.

**Alternatives are guarded, and scanned backwards** — the *last* one whose
progress flag is set wins, or none runs. Flag 0 is set in the shipped save and
no event ever writes it, so a `0000-` alternative is the always-true default,
written first precisely because the scan reaches it last.

**Opcodes**: 0, 1, 6 and 7 are all just *triggers* for `Event_Begin` — on touch,
on touch-while-standing-with-a-button (the "walk up and press" case, 249 of
692), on being shot, and unconditionally from `Entity_Destroy`. 5 sets a
progress flag. **4 and 9 are still undecoded.**

**Sub-opcodes**: all 15 decoded from the interpreter — 3 dialogue, 4/5 set/clear
flag, 9 sound, 12 music, 13 save, 15 test-flags, 17 wait, 80 soul-get, 99 nop,
and others. Table in `EventCommands.pas`. Every argument count matches the arity
inferred from the data alone before the interpreter was found.

### `stage.dat` — solved

66 rows × 16 fields into a 19-int record (stride `0x4C`); csv 8..15 land at
`rec[11..18]`. Full detail in `src/Stages.pas`.

| csv | meaning |
|---|---|
| 0, 1 | surface set and sprite set — **equal on every row**, so one art set |
| 2,3,4 | map index per layer; **csv 2 equals the row number**, 3 and 4 unused |
| 5,6,7 | tileset surface slot per layer; slot 6 is `bg00N.bmp`, 6 and 7 unused |
| 8..14 | zero on every row; nothing reads them |
| 15 | **terrain id** |

Terrain does two things: `Terrain_Configure` `0x4645B0` uses it to set the
**solid-tile threshold** (`$32`/`$3C`/`$46`/`$50` by terrain), and
`Entity_SpawnDebris` uses it to pick the impact sound (3 → `water01`,
4 → `water02`). It equals csv 0 on 65 of 66 rows; row 58 looks like area 7 and
sounds like area 6. It is **not** the music — `AutoLoadMidis` index 4 is
`itemget`, a jingle, yet 13 rows carry 4.

Row 0 is the "no stage" placeholder: csv 2 and csv 5 are `-1` and there are
exactly 65 map files for rows 1..65.

## 8a. The entity system

`src/Entities.pas` carries the detail; this is the map.

### The pool

289 slots of `0x104` bytes, allocated in three ranges by `Entity_Spawn`
`0x4610C4`: slot 0 is the player, `1..$20` the actors, `$21..$120` everything
else. **But `Entity_UpdateAll` walks only 256 of them** and returns — slots
`$100..$120` can be spawned into and will never update, draw or cull.
`Entity_Spawn`'s sprite search also stops at 256, so they are vestigial. That is
in the original and is reproduced, not corrected.

### The dispatcher

`Entity_UpdateAll` `0x4608BC` switches on `EF_TYPE` into **78 handlers, one per
type** — that is what the whole `0x456000`–`0x45FFFF` block is. The compiler
emitted it as a **jump table at `0x460924`**, not a compare chain, so the binary
names every arm; `EntityHandlers.HANDLER_ADDR` transcribes all 78 and
`--selftest-entities` reads the table back out of `akuji.exe` and diffs them.
Types 0, 18 and 20 point at the default target — they have no arm at all. 18 and
20 are also two of the three rows whose type-table column 0 is `-1`, so they are
inert markers; the third, type 32, updates while drawing nothing.

Per live slot, in order: carry the layer scroll unless `EF_SCREEN_SPACE`; run
the handler; push visibility, animation, position and depth onto the sprite;
tick `EF_TIMER` and `EF_DEATH_TIMER`; rebuild the four box fields; then touch,
projectile and cull passes. **A touch that changes the game state abandons the
rest of the pool for that frame** — a real early `Exit`, and the only way any of
the four fresh reads of `GameState` can disagree with each other.

### The type table's 18 columns

`Entity_Spawn` copies the row into the new entity, so every column's
destination is known (see `Entities.pas`). Two are decoded outright, both
booleans: **column 5** → `EF_SCREEN_SPACE` (the layer scroll is added only when
0) and **column 10** → `EF_CULL_OFFSCREEN` (destroy once `IsOffScreen(e, 4)`).
**Column 7 is never copied at all** and is zero for all 81 types — dead, not
undiscovered.

**Columns 11–14 are PERCENTAGES.** `Entity_UpdateAll` rebuilds all four box
fields every play frame as `Round(half-extent × column / 100)` — so a type does
not carry a hitbox in pixels, it carries the *fraction of its own art* the box
covers, and the extents themselves are refreshed from the sprite's current
frame. What proves the reading is not the `100.0` divisor at `0x4610C0` but the
values: across all 81 rows those columns only hold `0 5 10 20 30 33 40 50 60 70
75 80`, and **33 and 75** are one third and three quarters.

**Column 2** → `EF_DEPTH`, the sprite's draw-order key. `-1` would mean "sort by
screen Y", but no shipped type is `-1` and no instruction writes one, so that
branch is present and never taken.

### Coordinates

Positions are biased by `0x10000` in **1/32 pixel** units. Converting to pixels
rounds **toward zero**: subtract the bias, but for negatives subtract
`bias - 31` first, because an arithmetic shift floors. Invisible in normal play,
visible only at screen edges — `--selftest-dir` pins it over 8001 values.

### Collision

| function | what it does |
|---|---|
| `Entity_TileCollideX/Y` `0x457300`/`0x4574DC` | the first solid tile the **leading edge** meets, swept across every tile the box spans on the other axis. A delta of **zero returns nothing** — a stationary entity is never blocked |
| `Entity_TileEdgeDistX/Y` `0x457150`/`0x457228` | how far it may actually move, to land flush |
| `Entity_BoxesOverlap` `0x457F98` | entity-vs-entity AABB |
| `Entity_IsOffScreen` `0x4580BC` | culling, margin × the entity's own extent |

An entity position is the **centre** of its sprite: `Entity_UpdateAll` places
the sprite at `position − half-extent` on both axes.

**Two different inset pairs**: `+0xA0/+0xA4` for tile collision, `+0xA8/+0xAC`
for entity-vs-entity. The solid-tile threshold is set per terrain by
`Terrain_Configure` — so terrain decides which tiles are solid.

Tile indices are biased by **128 tiles**, not 64, because the layer origin and
the entity position *both* carry `POSITION_BIAS` — 4096 pixels between them,
which is 128 tiles of 32. That is independent evidence for the layer origin's
bias, which until then rested only on the two rounding idioms looking alike.

The `Scrolling` argument is a **rounding** decision, not a semantic one: both
terms land in the same sum, and it only decides which of them carries the
1/32-pixel remainder. It changes the tile solely where that crosses a boundary.

`TileMap_Get` `0x44DB5C` has **no bounds check** — it is one line, and an X
outside the map indexes into the neighbouring row, so the map wraps horizontally
for anything that walks off the side.

Gravity is **8** per frame for loose objects, **4** for the player, both capped
at `$200`.

### Death and damage

`Entity_UpdateDying` `0x4615A8` is called from **30 sites** — the guard at the
top of every handler. `Entity_TakeProjectileHits` `0x457AB4` scans slots
`1..$20` for projectiles; a hit subtracts the projectile's `$24` from the
target's `$24` (**same slot, two roles** — hit points on a target, damage on a
projectile), sets `+0x70/+0x74` to 8 as invulnerability, and plays `hit01.wav`
if the target survives.

`EF_TOUCH_KIND` (`$32`, column 3) is what touching the player does;
`EF_CLASS` (`$33`, column 4) is how the entity dies. They sit adjacent at
`+0xC8`/`+0xCC` and are easy to conflate.

### The two 10-int blocks

`$08..$11` is mostly **parameters**, `$12..$1B` is **runtime counters** — except
`A[0]` (`EF_STATE`), which is per-type state, not a parameter.

### The player — `Player_Update` `0x4585A8`

State machine in `EF_STATE`: ground, dash, airborne, landing, wall kick, attack,
glide, air dash, knockback, and two death states (both ending at GameState 100).
The dash is a **double tap** inside a 30-frame window — `tk001.dat` says so in as
many words. Every sound it plays matches its name. Weapons come from a
16-byte-record table at `0x468E84` (via the pointer `0x46CD44`) indexed by
`PlayerState +0x11CC`. Full detail in `src/PlayerState.pas`.

Four moves are gated on **ability bytes** in the save's first ten bytes —
`Head[4..7]` are dash, wall kick, air dash and glide. `Game_StartOrLoad` writes
all four to zero on a new game, which is what identified them; the shipped
mid-game save has only `Head[4]` set, and `tk001.dat` teaches exactly the dash.

### Scrolling — there is no camera-follow code

Every movement step asks whether the entity is outside a dead zone in the middle
of the screen and heading further out; if so the move is applied to the LAYER and
the entity is put back. So the player's stored position simply stops changing
while the world scrolls, and anything assuming "position changed" means "the
player moved" is wrong. `src/Camera.pas`, checked against all 65 maps.

## 8b. Events: placement, conditions, and difficulty

`EventScript_Execute` runs the scripts; `Events_SpawnNearCamera` `0x454790`
decides what exists at all, and it turned four unknown CSV columns into a
complete system. Detail in `src/EventScripts.pas`; the shape is:

| csv | meaning |
|---|---|
| 1 | **required** progress flag — do not spawn unless it is set |
| 2 | **forbidding** progress flag — once set, disable this event forever |
| 3, 4 | tile X and Y |

"Disable forever" is literal: opcode := -1 and the tile moved to (-32, -32).

Two patterns make this a decode rather than a guess, and both are all-or-nothing
over the shipped data:

* all **154 of 154** opcode-5 events set a flag that is *their own csv 2* — pick
  the item up and the event switches itself off
* all **9 of 9** opcode-4 events are the same construction: always active,
  placed at tile (1,1) as type 20, running a sub-op 15 flag test that on success
  sets its own csv 2 and disables itself. Puzzle checkers.

**Difficulty** rides the same mechanism. `Game_StartOrLoad` publishes the level
as `Progress[10]` / `Progress[5]` / `Progress[6]` for 0 / 1 / 2, and 5 / 23 / 40
records require exactly those. No script ever guards on them, which is why they
looked dead until this function was read.

Opcodes **2 and 3** exist in the code — push against a solid holding a direction,
or pressing confirm — and appear in **no** shipped record.

**Opcode 9 is a collectible**, and nothing branches on the opcode: what reads its
ParamB is the *touch handler* of the entity it places. `EF_TOUCH_KIND` 2 and 5
both set `Progress[Copy(ParamB,1,4)]`, exactly as opcode 5 does. Kind 2 is the
**Mana Stone** — the counter climbs, and on reaching the target for the current
`TargetIndex` both `TargetIndex` and `MaxLives` go up and `Lives` refills, which
is what `tk001.dat` describes. Kind 5 is a full heal.

The partition is exact: of the 231 records, the 127 carrying an id are precisely
those placing a touch-kind 2 or 5 type, and the 104 carrying `*` are precisely
the rest. It has to be — `StrToInt('*')` would raise. **Every opcode is now
accounted for.**

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

### Ghidra cannot find Borland's frameless functions

48 of the 78 entity-type update handlers were invisible to auto-analysis, and
re-running it does not help. Borland omits `push ebp` / `mov ebp,esp` for
routines that need no stack frame, so those functions begin with things like
`8b 15` or `53 56 57` — **0 of the 48 started with `55 8B EC`**, which is the
pattern Function Start Search matches.

They are created by `ghidra_scripts/CreateEntityUpdateHandlers.java`, which
searches for nothing: the 48 addresses are hard-coded, read out of
`Entity_UpdateAll`'s switch one per case arm. That restraint is the point — the
alternative, a heuristic instruction finder, is what mangled the `'.'` literal
at `0x45520C` into `ADD byte ptr CS:[EAX],AL`.

**Expect more of these.** Any frameless routine reached only by a call Ghidra
has not followed will be missing the same way. Compile-check new scripts with
`javac` against the install's jars (`C:\Users\Abdullah\Documents\ghidra_12.0.4_PUBLIC`).

Auto-analysis is safe for names, incidentally: renames are `USER_DEFINED`, which
analyzers may not overwrite. Verified — all 15 `Entity_*` names survived a full
run. The risk is bad *disassembly*, so leave **Aggressive Instruction Finder**
off in a binary this full of string literals.

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
   `24 + w*h*2` bytes; `save.dat` is exactly `SizeOf(TPlayerState)`, checked at
   startup; the player's six sprite tables tile end to end from `0x46BB9C` to
   `0x46BC2C`, each width equal to the frame count its handler cycles; the sound-name array terminates cleanly right where the key-name
   array begins; every event sub-opcode has a fixed argument count and sub-op 15
   carries its own length, over 518 commands with no exceptions.
3. **Cross-corroboration between unrelated parts of the binary.** The form
   resource's `ChannelCount = 57` matches the name array length and the file
   count. `Title_Init`'s `Font_Define` arguments match constants derived
   separately from the font sheet. The DFM's `AutoLoadMidis` matches the static
   name array entry for entry.

### `tools/check.sh` is the gate

One command runs all of the above plus a negative control, and exits non-zero
if anything fails:

    tools/check.sh && git commit -m "..."

It exists because two failures this session came from shell chains, not from
the code: a run piped through `tail` reported the pipe's exit status and made a
failing `--selftest` look green, and a `;` between the build and the commit let
non-compiling source through. It also fixes the quoting centrally — the game
directory has spaces, and unquoted expansion has caused both false passes and
false failures here.

Mutation-test anything that claims to check something. A test that cannot fail
is worse than none. Four ways it has happened here, all found by mutation:

* `--selftest-events` once passed having loaded **zero** events.
* `Assert(SizeOf(TPlayerState) = $11E4)` in an `initialization` section never
  ran at all — **FPC compiles assertions out unless `-Sa` is passed**. The
  record sat a byte short for several commits, and every integer in `save.dat`
  read a byte early. Write checks as plain code, not as `Assert`.
* A dead-zone sweep compared `ShouldScrollX` against a reference built from
  `Camera.DEADZONE_RIGHT` — the same constant it was meant to be checking. It
  passed happily with that constant changed. **Reference values must be
  literals.**
* A sprite-table check compared constants against constants; the compiler folded
  it and warned "unreachable code" on every branch. It now reads the tables out
  of `akuji.exe`.
* Reading it out of `akuji.exe` was still not enough. The check read
  `ITEM_VARIANTS * ITEM_FRAMES` ints and compared them — so the **length it
  verified was the constant under test**, and the table was wrong by a factor of
  eight for several commits. Shrinking 16 rows to 2 just makes it read fewer
  values and pass again. **To pin a length you need a fact from outside the
  table**; here it is the next table's pointer, since the region is const arrays
  laid end to end.
* A check on an early `Exit` passed against a build with the `Exit` deleted,
  because the loop stopped doing the observable thing either way. **Observe
  something that happens *before* the guard you are testing.**

**Force a full rebuild (`lazbuild -B`) when mutation testing.** An incremental
build can leave you running the old binary, which makes a live mutation look
survived — or a restored file look still broken.

What this does **not** cover is game logic behaviour - entity movement,
collision, scoring. Establishing that needs differential tracing against the
running original, which has not been set up. A cheap way in when it matters:
`kbgm32.dll` is an ordinary DLL with 13 named exports, so a logging proxy would
give exact ground truth for the music layer. It needs a 32-bit toolchain, which
this machine does not currently have.

## 14a. Behaviour, and how far it is checked

`src/Player.pas` translates `Player_Update` and its three delegated states. It
reaches the tilemap, the entity pool, the sound device and the camera through
**`TPlayerWorld`**, an abstract class - which keeps the unit honest (what is
decoded is here; what is not is behind a method that says so) and makes the
controller deterministic enough to test.

`--selftest-trace` drives it over a scripted input sequence in a single-screen
room and checks the result against arithmetic done independently of the code:
walking is `AxisX shl 5` = exactly one pixel a frame, the dash `shl 6` exactly
two, a jump leaves at `-JumpStrength` and gains `PLAYER_GRAVITY` a frame. It
also checks the **ability gates actually gate** - the same input with the
ability locked must do nothing.

**This is not proof the reconstruction matches `akuji.exe`.** Only a
differential run can be that. What the trace does is fix the controller against
drift and *be the shape* the differential test needs: same start state, same
input script, a trace to diff.

Three things the first version of it got wrong, all worth knowing:

* **An entity placed on the ground lands on its first update.** `PF_LANDED`
  starts at 0, so frame 1 runs the whole just-landed sequence and zeroes the
  velocity. A jump pressed on frame 1 has its edge eaten. Settle before
  measuring.
* **A test world must be single-screen, or model tiles in world space.** On a
  large map the player hung in mid-air with its velocity climbing, because
  everything past the dead zone was being applied to the layer while the test's
  floor stayed in entity-pixel space. A 10x7-tile room makes both max-scroll
  values non-positive, so nothing scrolls.
* **The jump apex is a velocity fact, not a pixel one.** Velocity is 1/32
  pixel, so the pixel minimum arrives several frames before `vy` crosses zero.
  And it takes `JumpStrength div PLAYER_GRAVITY` **+ 1** frames, because the
  impulse is applied in the grounded branch and gravity only in the airborne
  one - the launch frame gets no gravity.

### Auditing code written under the old process

Everything written before section 3a's rule was adopted was written from
batched reads, so it has to be re-checked against a fresh decompile, function
by function. Risk is **not** uniform, and only two files carry most of it:

| | risk | why |
|---|---|---|
| asset units, `EventCommands`, `EventScripts`, `Stages`, the `PlayerState` record | low | each has an external check - byte-identical Python diffs, or all-or-nothing invariants over 692 records / 65 maps |
| `Camera.pas` | low | written immediately, and its clamp is checked against every map |
| **`Player.pas`**, **`Entities.pas`** | **high** | the behaviour code, which by definition has no data to check against |

The audit is: re-decompile, diff line by line, fix, and **add a test for each
fix** so the defect cannot come back silently.

`Player_Update` has been audited this way and it found three real defects, none
of which any existing check would have caught:

* `PF_OWNER` was `$04`. The original writes byte `+4`, which is int **1**;
  `$04` is byte `+0x10`, `EF_SPRITE`. Every projectile was recording its owner
  in the sprite handle.
* the projectile lifetime went to `EF_TIMER` (`$1C`, byte `+0x70`). The original
  writes byte `+0x50`, int **`$14`**.
* **the `GameState = 60` guard was missing entirely**, so the controller would
  have kept stepping behind a dialogue box or a pause menu.

That is a 3-defect yield on the first audited function, which is the measure of
how much the old process was costing.

`Entities.pas` has now been audited the same way and is finished:
`Entity_Spawn` was correct, `Entity_TileEdgeDistX/Y` was correct, and
`Entity_UpdateDying` was **correct but vague** — "spawns an effect entity" turned
out to be a type-32 emitter seeded with four different numbers per death class.

The audit is not only for behaviour code. `EntityHandlers.ITEM_SPRITES` was
recorded as **sixteen** rows of four and is **two**, and the evidence for sixteen
was real but attached to the wrong type — the shipped data does place something
with the `A` argument running 0..15, and it is **type 24**, whose table is a
different one 32 bytes further on. Type 14's own 122 placements all use `A = 1`.

The general lesson, now in section 14: a table's **extent** needs evidence from
outside the table. Here the region is a run of const arrays laid end to end, each
reached through its own pointer global with exactly one reader, so a table ends
where the next pointer begins — and two of the four are flush with their use in
both directions (type 24 is placed 16 times with `A` = 0..15, one of each; type
25 uses 0..2 and has 3 entries).

**Restore mutations by copying a file, never with `git checkout`.** Twice now
that has misfired: once it reverted a whole file of uncommitted work, and once
it silently did nothing because the file was untracked, leaving the mutation
live in a run that then reported PASSED.

### `tools/mutate.sh` — use it, do not hand-roll another one

Mutations live in `tools/mutations/*.txt` as `name / file / --- / old / ---> /
new` records. Every guard in the script is scar tissue:

* a **lock**, because two copies once ran concurrently, each restoring the
  other's mutation, leaving two live defects *and a backup that already
  contained one* — recovery meant resetting to HEAD and replaying the patch
  script that had generated the work
* a **timeout**, because `while Row <= Row` does not fail, it **hangs**, and the
  suite blocked for twenty minutes behind a stuck process that also held a lock
  on `akuji.exe` and made every later build fail with "Can't create object
  file", which looks like a compile error and is not
* a **verified restore** that aborts the run rather than letting a bad restore
  spread
* **stray-process cleanup** before every build

Calibrate it with a negative control — a comment-only change must SURVIVE.
Without that, "everything was killed" can just mean everything failed to build.
