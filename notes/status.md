# Status: akuji.exe → Object Pascal

Target: **a Borland Delphi 6 x86 project that compiles to a near-replica of
akuji.exe.** Modernisation is deferred. Rewritten 2026-08-30, replacing a
version written the same morning that had already gone stale in three places -
it still claimed eight `TEventHost` methods were unimplemented after all
thirteen were done.

Every number here comes from a tool in `tools/`, not from memory.

## Where it stands

| | | |
|---|---|---|
| game-layer functions with executable Pascal | 149 / 149 | `implemented.py` |
| entity handlers differentially verified against the binary | 296 cases, 0 disagree | `emudiff.py handler_live` |
| the FULL differential suite | 1168 cases, 0 disagree, 4 divergences confirmed | `emudiff.py` |
| game functions tracked, one row each | 149 | `audited.md` |
| ... read-audited and FROZEN | 34 across all three tables (9 MATCHES, 3 FIXED in the game table) | `audited.py` |
| ... EMUDIFF - entity handlers, machine-checked | 75 | `audited.py` |
| ... UNVERIFIED - unproven, not suspect | 47 | `audited.py --list` |
| const tables pinned to the image by VALUE | 187 | `--selftest-entities` |
| table lengths corroborated from OUTSIDE the table | 171 / 180 | `table_extents.py` |
| behavioural self-test modes | 14 | `check.sh` |
| stages in the gate, incl. a negative control | 15 | `check.sh` |
| declared divergences | 15 (7 B, 4 C, 4 D) | `divergences.py` |
| recorded mutations | 136 across 5 spec files | `mutate.sh` |
| Delphi 6 hard blockers | 207 | `delphi6_audit.py` |

`tools/check.sh` runs all of it plus a negative control and exits non-zero on
any failure. `--emudiff` is not in it - it drives Ghidra headless for minutes -
so run `python tools/emudiff.py handler_live` by hand after touching a handler.

## OPEN: the v1.0 baseline is stale and deliberately not re-recorded

`tools/samebinary.py` fails. `.text .data .rdata .pdata` all moved when the
self-tests were split out of `akuji.lpr` into `src/selftests/`. The tool is now
part of `tools/check.sh`, so the gate is red until this is closed.

**Do not run `--record` to clear it.** Recording adopts whatever the build
currently does as the definition of correct, including a regression. The user
has asked to play the game first, on the grounds that automated tests do not
establish real-world behaviour. That decision stands until they say otherwise.

The evidence gathered so far, for whoever picks this up:

| question | answer |
|---|---|
| was the baseline already stale? | no - the tree before this work builds to `7 sections match` |
| game functions in both builds | 515 |
| ... byte-identical | 190 |
| ... same LENGTH, bytes differ | 325 |
| ... **length changed** | **0** |
| `emudiff` full suite, before vs after | identical: 1076 cases, same 94 disagreements, same 13 faults |
| `emudiff handler_live` | 296 cases, 0 disagree, both builds |
| `IsSelfTestMode` vs the old 18-way chain | mode sets 18 = 18, dispatcher 17 = 17 |

Zero length changes across 515 functions is what a pure relocation move looks
like: `samebinary` hashes raw body bytes, and those include relative call and
data displacements, so moving anything rewrites nearly every function that
calls something. It is strong evidence and it is not proof - a changed constant
of the same width would look identical to it. What backs the behavioural claim
is the self-tests and `emudiff`, not the byte analysis.

## How correctness is established

1. **Running the original's own code.** `emudiff` executes akuji.exe's machine
   code under Ghidra's emulator and diffs it against the reconstruction. This
   covers the entity layer completely.
2. **Reading the original.** `notes/audited.md` lists every flow-layer function
   read line by line against a decompile, and what was compared. `emudiff`
   cannot reach this layer - it touches the form, the component suite and Win32.
3. **Two independent readers.** Every binary format is implemented twice, in
   Pascal and Python, and diffed: 44/44 QDA entries, 57/57 sounds, 15/15 MIDI
   tracks, 988 script arguments.
4. **Running the game.** A 20,304-frame Frida capture fixed the frame loop's
   shape, the state machine's meanings and the opening's timings.

## The defect class that costs the most

**Correct code that nothing calls, and comments that describe behaviour the
code does not implement.** Every bug reported from play has been one of these,
not a mistranslation. `implemented.py` counts an empty inherited body as
implemented, and the behavioural self-tests drive units directly, so neither
can see it. Recent examples: the cursor read after the reset that zeroes it
(CONTINUE always started a new game), keyboard flags cleared inside one state's
arm (pause RESET became title CONTINUE), a hard-coded `False` for FadeBusy
beside a comment saying no fader existed (both game-over dissolves skipped).

The countermeasures are source-shape tools, because no behavioural test can see
this: `frame_shape.py` for the frame loop and form wiring, `shadow_globals.py`
for one global declared twice, `audited.py` for the ledger.

## What is left, in the order I would do it

1. **Play-test the current build.** Every real bug this month came from
   playing, not from tooling. There are many unverified fixes in the tree.
2. **Finish the flow audit** - 11 functions, listed at the foot of
   `notes/audited.md`. Highest yield per hour on the evidence so far.
3. **Verify `runner.txt` and `startup.txt`** (62 mutations). They carry no
   `# selftest:` header and so run under the harness default, which is what
   made `menus.txt` report six real defects as SURVIVED.
4. ~~**Split out the self-tests.**~~ Done. `akuji.lpr` is 32 lines; the
   harness is twelve units under `src/selftests/`. They are still compiled
   into the shipped binary (DIV-007).
5. **The Delphi 6 port.** 135 mechanical blockers, plus the two things no regex
   sees: the component layer standing in for a DirectX suite, and the Lazarus
   `.lfm` where Delphi wants the `.dfm` we already hold decoded.

   The port is also what unblocks **DIV-013, deleting our MIDI engine**.
   `kbgm32.dll` is PE32 i386 and this build is PE32+ x86-64, so a 64-bit
   process cannot load it and the music had to be reimplemented -
   `KbgmPlayer.pas`, `MidiFile.pas` and `MidiOut.pas`, 1100 lines standing in
   for a DLL call. Delphi 6 x86 is 32-bit, so the plan there is to write
   `KbgmPlayer.pas` out and declare the thirteen KBGM exports
   `external 'kbgm32.dll'` directly. The published interface already matches
   them one for one. It matters beyond fidelity: the game-over screen leaves
   when the music stops, so today its length is decided by our engine's idea
   of a track rather than the DLL's.

Long tail: type 1's `EF_STATE` 10 (the one differential disagreement), six
handlers that fault in the emulator by calling through an unplaced component
pointer, `ScreenPhase` 1 in `Ending.pas` (unobserved - no session has reached
the ending), DIV-009 key rebinding, DIV-012 the spawn window's camera tile.

## Why Delphi 6 is the right target

It shares the original's word size, calling convention (`__register`), RTL shape
and compiler lineage - Delphi 3 built akuji.exe. Two standing compromises
disappear: `Extended` exists, so `ScaleByPercent` can do the arithmetic the
original does instead of modelling it in 64-bit integers; and a 32-bit build
removes the widening hazards that made `PixelOf` correct only by an accidental
Int64 promotion. We also already hold the original's own form resource,
decoded, at `notes/Frm_main.dfm`.
