# Status: akuji.exe → Object Pascal

Written 2026-08-30, when the target changed from "a Free Pascal program that
plays like the original" to **"a Borland Delphi 6 x86 project that compiles to a
near-replica of akuji.exe"**. Modernisation is deferred.

Every number here is produced by a tool in `tools/`, not estimated.

---

## 1. Where the work actually stands

| | | |
|---|---|---|
| game-layer functions with executable Pascal | **149 / 149** | `implemented.py` |
| entity handlers differentially verified against the binary | **296 cases, 0 disagree** | `emudiff.py` |
| const tables pinned to the image by VALUE | **187** | `--selftest-entities` |
| table lengths corroborated from OUTSIDE the table | **171 / 180** | `table_extents.py` |
| behavioural self-tests | **13** | `check.sh` |
| tool checks in the gate | **8** | `check.sh` |
| knowingly-declared divergences | **11** (4 B, 3 C, 4 D) | `divergences.py` |

**The translation is essentially done and the arithmetic is verified.** Every
entity handler but the player agrees with akuji.exe's own machine code, run
under Ghidra's emulator, across four states each.

### What that number does NOT cover

Three things, and the third is the one that has been costing days.

1. **Type 1, the player, is excluded** from the sweep and unexplained — it ends
   at `EF_STATE` 10 in the original and 2 here. Placing its context did not
   move it.
2. **Six handlers fault** in the emulator (15, 32, 40, 54, 66, 69), calling
   through a component pointer nobody placed. That is the technique's real
   boundary.
3. **Coverage cannot see WIRING**, and wiring is where nearly every remaining
   bug lives. See below.

---

## 2. The dominant defect class: correct code that nothing calls

Every bug found on 29–30 August was one of these. Not a mistranslation — a
faithful translation that was never connected to anything.

| what was broken | the unwired thing |
|---|---|
| the opening cutscene never appeared | `TStartHost.Opening` — base returns False |
| stage 1 played in silence | `TStartHost.PlayMusic` — empty |
| event sounds and music silent | `TSessionAudio.PlayEffect` / `PlayMusic` — empty |
| the dash could never fire | `InputEndOfFrame` — never called, step 7 |
| walking out of a room reloaded it | `TEventHost.LoadStage` — empty |
| room transitions do not animate | `TEventHost.StartFade` / `FadeBusy` — empty |
| the power-up orb kept being drawn | `Kill` where the original destroys |

**`TEventHost` still has 8 of 13 methods unimplemented**: `SetTile`,
`SaveGame`, `SoulGet`, `StartFade`, `FadeBusy`, `PlayMusic`,
`DestroyEventEntity`, `SetEventEntityState`.

So: **saving does not work, the ending cannot be reached, puzzle tiles do not
move, and screen fades do not happen** — not because they are undecoded, but
because a virtual with a do-nothing default was never overridden.

### Why this went unnoticed for so long

`implemented.py` asks "does this function have executable Pascal with its
address recorded". `TEventHost.LoadStage` **has a body** — an empty one — so it
counted. All thirteen behavioural self-tests passed through every bug in the
table above, because they drive units directly and never exercise the form's
wiring.

`tools/frame_shape.py` exists for exactly this and now guards eight specific
wirings, but it guards them **by name**, one at a time, after each is found.
It cannot find the next one.

### A worked example, because it is the honest shape of the problem

The stage-load arithmetic — `SpawnX := tileX * TileW + 16`,
`SpawnY := tileY * TileH + 19`, the cameras flush — was decoded correctly,
written into `PlayerState.pas` with named constants, given a comment explaining
why 19 is deliberate and not a rounding of 16, **and given a self-test asserting
the two constants differ**.

Nothing used it. The producer (`LoadStage`) was an empty inherited method; the
consumer (`Stage_Begin`) was implemented. Until 30 August the only reference to
`SPAWN_CENTRE_X` outside its own declaration was the test.

That is not a case of writing notes instead of code. It is a case of
implementing the half that the coverage metric could see.

---

## 3. What the new target changes

Delphi 6 is a much better fit than FPC/Win64, and two of the project's standing
compromises disappear outright.

### It removes the x87 problem entirely

`ScaleByPercent` is modelled in 64-bit integers with an exact-rational
reference (`x87_sim.py`) **because FPC on x86-64 has no 80-bit type**. Delphi 6
on x86 has `Extended`, and the same FPU. That divergence can be deleted and
replaced with the arithmetic the original actually performs.

The two ending-percentage deviations (counters 212 and 236 reading a point low)
would then fall out naturally instead of being a table of special cases.

### It removes the widening hazards

A 32-bit build makes the original's arithmetic native. Two bugs this week came
from 64-bit creep — `PixelOf` was correct only by an accidental Int64 promotion,
and the debug FPS counter's `Int64` cast defeated a 49-day wrap. On x86 those
questions do not arise.

### It makes the comparison far stronger

Today `emudiff` compares a 32-bit original against a 64-bit reconstruction
through a p-code emulator. A Delphi 6 x86 build shares the original's word size,
calling convention (`__register`), RTL shape and compiler lineage — Delphi 3
built the original. Instruction-level comparison of generated code becomes
possible rather than aspirational.

### And we already hold the form

`notes/Frm_main.dfm` is the original's own `TPF0` resource, decoded. Delphi
wants a `.dfm`; we have the real one rather than a translation of it.

---

## 4. What blocks the Delphi 6 build

`tools/delphi6_audit.py`, run 2026-08-30: **135 hard blockers** across 39 files.
Every one is a construct Delphi 6 rejects outright, not a warning.

| | count | replacement |
|---|---|---|
| `Exit(value)` | 79 | `Result := x; Exit;` — Delphi 2009+ |
| `{$MODE DELPHI}` | 38 | delete; Delphi has no modes |
| `TBytes` | 6 | `array of Byte` — Delphi 2007+ |
| `StrictDelimiter` | 3 | split by hand — Delphi 2006+ |
| Lazarus units | 3 | the VCL equivalent |
| FPC-only types | 2 | `Int64` / `Integer` |
| FPC intrinsics (`SarLongint`) | 2 | write the arithmetic out |
| `GetTickCount64` | 2 | `timeGetTime`, which is what the original uses |

**That is a floor, not a ceiling.** It is the mechanical part. The real work is
not in the list:

1. **The component layer.** `DDDDComponent`, `DDIDComponent`, `DDSDComponent`
   and `KbgmPlayer` stand in for a third-party DirectX/audio suite. `DDDD` is
   still a declared stub (DIV-008). Under Delphi 6 the honest options are to
   reimplement them against DirectX 7-era headers, or to obtain the original
   component suite. `kbgm32.dll` ships beside the game and is already being
   read for behaviour — the fade length came out of it.
2. **The form resource.** `src/GmMain.lfm` is Lazarus. `notes/Frm_main.dfm` is
   the original. They must be reconciled, and the `.dfm` is the authority.
3. **The RTL boundary.** LCL `Graphics`/`Controls`/`Forms` map onto the VCL by
   name but not always by behaviour; `TCanvas.TextOut` and `TBitmap` loading
   are the ones this project leans on hardest.
4. **The test code.** ~8,000 of `akuji.lpr`'s 8,800 lines are self-tests
   compiled into the shipped binary. See the TODO in CLAUDE.md §1a: they belong
   in a separate `akujitest.lpr` so the game binary contains only the game.

---

## 5. Issues that need resolving, in the order they block progress

1. **The 8 remaining `TEventHost` no-ops.** Saving, the ending, puzzle tiles
   and fades. This is what stops the game being playable to completion, and it
   is the same one-line-per-method fix that unblocked room transitions.
2. **A structural check for unwired hosts.** `frame_shape.py` guards known
   wirings by name. What is needed is the general form: *every* virtual with an
   empty default, and whether anything overrides it. That would have caught all
   seven of §2 at once, before they reached the player.
3. **Type 1's `EF_STATE` 10.** The one differential disagreement left.
4. **The 6 faulting handlers.** Their calls land in the `Kbgm32`/component
   import thunks, which are now resolvable — this may be reachable after all.
5. **The Delphi 6 port itself**, once the game is playable end to end. Doing it
   before then means debugging two things at once.
6. **`ScreenPhase` 1**, the hole in `Ending.pas`, still unobserved because no
   traced session has reached the ending.

---

## 6. What is genuinely solid

Worth stating, because the list above is all problems.

* Every asset format is decoded and implemented twice — Pascal and Python —
  and diffed: 44/44 QDA entries, 57/57 sounds, 15/15 MIDI tracks byte-identical.
* The event mini-language is decoded end to end, both halves, with two
  independent parsers agreeing over 988 arguments.
* All 78 entity handlers translated, and 296 differential cases agree with the
  original's own machine code.
* The frame loop's shape, the state machine's meanings and the opening's
  timings are confirmed against a 20,304-frame capture of the running game.
* `tools/check.sh` is one command and gates all of it, including a negative
  control that must fail.
