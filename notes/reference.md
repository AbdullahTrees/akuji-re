# Decoded reference

What the binary's formats, tables and structures turned out to be. Split out of
CLAUDE.md, which had grown to 1367 lines - long enough that its actual RULES
were being skimmed past. This file is lookup material: read it when you need a
specific fact, not before every change.

The rules live in CLAUDE.md. The per-function audit lives in notes/audited.md.

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
5. **state dispatch, first half**
6. **`Entity_UpdateAll` — UNCONDITIONAL, every state, every frame**
7. **state dispatch, second half**
8. sprite/entity update — `FUN_0044d758`, `FUN_0044d1e0`, `FUN_0044d31c` x8 layers
9. button edge-detection and repeat timers
10. `FUN_00449d00(DDDD1)` — present
11. frame limiter

### THERE ARE TWO DISPATCHES, WITH THE ENTITY UPDATE BETWEEN THEM

This was recorded for a long time as one dispatch with the entity update
inside the gameplay arm, and that is wrong. From a 20,304-frame Frida capture
(`notes/trace_findings.md`):

    Entity_UpdateAll        20304 calls / 20304 frames    every state
    Events_SpawnNearCamera  14560 = 12347 (state 60) + 2213 (state 140)
    EventScript_Execute      2213 = every frame of state 140

`Entity_UpdateAll` runs on the title screen, through the whole cutscene, and
on all 105 frames of a pause. It is gated **internally** by its state
argument, which is why every handler carries its own
`if AGameState <> GS_PLAY then Exit` — those exits were translated faithfully
without anyone noticing what they implied about the caller.

Frame 1 is the proof there are two dispatches: it runs `Title_Init`, then
`Entity_UpdateAll`, then `Title_MainMenu` — two different state arms in one
frame, which a single switch cannot do. `Title_Init` sets the state to 20 and
the second dispatch reads the new value.

| state | before the entity update | after |
|---|---|---|
| 10 | `Title_Init` | — |
| 20 | — | `Title_MainMenu` |
| 30 | `Stage_Begin` | — |
| 40 | — | `Game_StartOrLoad` -> `Opening_Update` |
| 60 | `Events_SpawnNearCamera` | `HUD_Draw` |
| 130 | — | `PauseMenu_Update` |
| 140 | `SpawnNearCamera`, `EventScript_Execute` | `MessageBox_Update` |

`tools/frame_shape.py` pins this arrangement and is in the gate. It is a
SOURCE-shape test on purpose: all thirteen behavioural self-tests passed both
before and after the fix, because they drive a session directly and never
touch the frame loop's structure.

### State machine — `p_GameState` (`0x0046d06c`), steps of 10

| Value | Handler |
|---|---|
| 10 | `Stage_Init` (`0x46214c`) |
| 20 | `Title_MainMenu` (`0x462330`) |
| 30 | `FUN_00462210` — entered by event sub-op 0 after a stage load |
| 40 | `Game_StartOrLoad` (`0x462f40`) — **and this is where the opening cutscene runs**, 4726 frames of it, called every frame until it ends |
| 60 | `FUN_00454790`, `FUN_00461ba8` — **normal gameplay**; a finished event script returns here |
| 100 | `GameOver_Update` (`0x461a44`), `FUN_00461ba8` — **game over** |
| 130 | `FUN_00461ee4` — **pause**; saves prior state to `0x46cbbc` |
| 140 | **the event-script state** — `EventScript_Execute`, `MessageBox_Update`, `Overlay_Update` and `PowerUp_Show` run here and in no other state. `Entity_PlayerTouch` does NOT, so touch detection is off for the whole of a conversation |
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

### Named globals — THESE ADDRESSES ARE POINTER CELLS

`p_GameState` `0x46d06c`, `p_InputState` `0x46cc58`, `p_KeyMap` `0x46cea8`,
`p_Settings` `0x46d0e8`, `p_LastFrameTime` `0x46d1e0`.

**The cell is not the variable.** Running the game showed `p_GameState`
holding `0x0047EF98`, unchanged across 862 frames of title menu where the
state had to be 20. The disassembly at `0x00459EE5` settles it:

    mov edx, DWORD PTR ds:0x46d06c    ; load
    mov edx, DWORD PTR [edx]          ; DEREFERENCE
    sub edx, 0x3c                     ; compare with 60, GS_PLAY

and `objdump` confirms the shape across the set — of seven cells traced, every
one is loaded many times and stored to **never**. A variable the game sets is
written somewhere; these are not. By contrast `RandSeed` at `0x0046E040`,
which belongs to the RTL rather than the game, has 2 stores and is a real
variable.

Following the pointer gives exactly the documented meanings, so the MEANINGS
are right and always were; the addresses name the wrong cell by one
indirection. Harmless to our behaviour — ours are real globals and these are
documentation — but anything that READS the original's memory (a trace, a
snapshot, an `--emudiff` `mem=`) must place both cells or it reads a pointer
and reports it as a value. What they point into has not been established.

## 7. Settings — `data\system.dat`, 56 bytes

`DDDD1Init` writes defaults into `p_Settings`, then `FileRead(h, p_Settings, 0x38)`
overwrites them.

| Offset | Default | Meaning |
|---|---|---|
| `+0x04` | 0 | **game level / difficulty**, clamped 0..2 by the options screen |
| `+0x08`..`+0x14` | 0,1,2,3 | **key map, FOUR ints** - `FormDestroy` copies `p_KeyMap[0..3]` here. The shipped file holds the identity mapping |
| `+0x18`..`+0x1B` | **1,0,1,0** | four flag bytes, each named by the global `FormDestroy` copies it from: `+0x18` `p_SoftwareVsync` `0x46CE60`, `+0x19` `p_WaitOn` `0x46D2E4`, `+0x1A` `p_FullScreenOn` `0x46D268`, `+0x1B` `p_DebugLog` `0x46CDB8`. This said 1,0,0,0 until `DDDD1Init` was read line by line: fullscreen defaults **on**. The default is then almost always overwritten, because the `system.ini` read below sets `+0x1A` unconditionally — 1 when `[disp] fullscreen` is exactly `on`, 0 otherwise — so it only survives when the INI is missing |
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
