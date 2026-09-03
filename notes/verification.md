# How this project proves things

The tooling, the verification tiers, and the scoreboard of what differential
testing has actually found. Split out of CLAUDE.md for length.

The rules live in CLAUDE.md; this is the reasoning behind them.

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

### Analysis tools in `tools/`

Three of these came out of specific mistakes and are worth reaching for before
repeating the mistake:

| tool | what it answers |
|---|---|
| `table_bounds.py` | **where does this const array END?** Partitions a region by the pointer globals that address it, since Delphi lays typed constants out consecutively. `--ptr X --readers` also counts code references — one reader means no other caller can need more rows. Written after a table was recorded at 16 rows and turned out to be 2 |
| `entity_usage.py` | **which types does the shipped data actually place, and with what arguments?** Prioritises the remaining handlers by how much of the game they buy, and cross-checks table lengths: an argument range of exactly 0..N-1 against an N-entry table agrees from both directions. `--paramb` groups by script, which is what identified the save point |
| `x87_sim.py` | **what would the original's FPU have produced?** Exact rational simulation of an x87 sequence at 64-bit significands. FPC on x86-64 has no 80-bit type, so some integer arithmetic done through the FPU cannot be reproduced with floats at all and has to be modelled in integers; this is the reference that says the model is right, and regenerates the golden table the self-test asserts |
| `table_extents.py` | **is this table the right LENGTH?** The 181 value-pins cannot tell you: the count they check with comes from the array being checked, so a short table pins short and passes. This bounds each by the address of the next. 171 of 180 are now flush, meaning their length is corroborated from outside themselves |
| `divergences.py` | pairs every `DIVERGENCE DIV-nnn` marker against `notes/divergences.md` and fails on a mismatch. Makes "we did not invent logic" a property of the repo rather than of my memory |
| `frame_shape.py` | the frame loop's ARRANGEMENT, and the form wiring no behavioural test can see. Both bugs it guards were correct units with nothing connecting them |
| `make_trace.py` | generates the Frida script that traces the running original — tier 0b above |
| `javac_check.sh` | compiles the Ghidra scripts against the install's jars in a second, instead of finding a typo two minutes into a headless run |
| `bindiff.py` | diffs the 2003 and 2020 builds. No instruction byte differs, so every oddity in either is the author's |
| `mutate.sh` | section 14 — the mutation harness |
| `coverage.py` | how much of the game layer is MENTIONED anywhere in `src/` |
| `implemented.py` | how much of it actually EXECUTES - the number that counts. `--all` lists the untouched, `--described` the ones that are still only prose |

Raw disassembly without Ghidra:
`objdump -D -b pei-i386 -M intel --start-address=0x... akuji.exe`
(msys2 at `/c/msys64/mingw64/bin`). Ghidra scripts can be compile-checked with
`javac` against the install's jars.

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

### Tier 0b: running the GAME — `tools/make_trace.py`

Stronger still, and the only tier that can answer questions about *sequence*:
attach Frida to the original and watch it play.

    python tools/make_trace.py --group frame --group state --group entity
    cd "<gamedir>" && frida -f akuji.exe -l akuji_trace.js

The script is GENERATED from `notes/game_functions.txt`, the address authority
— sixty hand-copied addresses would be a second drifting copy of the database,
and a trace with one wrong address is worse than none because it still looks
like evidence. Groups keep the volume usable; `frame` emits a marker so two
logs can be lined up.

**Everything this project knew came from reading, and reading cannot see
arrangement.** One 20,304-frame session produced: the two-dispatch frame loop
(section 6), the meaning of state 140, that `Entity_PlayerTouch` runs only in
state 60, that the `p_*` globals are pointer cells, that the opening's slide
timings are exactly right, and — because the counts are exact rather than
approximate — arithmetic that confirms itself:

    Player_Update 14667;  20304 - 14667 = 5637 = title 910 + opening 4726 + 1

Findings live in `notes/trace_findings.md`. Still unobserved: `ScreenPhase` 1,
the phase `Ending.pas` records as a hole, because no session has reached the
ending.

### The divergence ledger — `notes/divergences.md`

The governing rule is that the Pascal matches the binary and the binary's bugs
are reproduced rather than fixed. That rule was **unenforceable** until this
existed: three divergences carried a comment, the rest were prose buried in
8,000-line units, and nothing failed if a fourth appeared. Reading for them
turned up nine.

Every knowing difference is one of four kinds, and the kind decides where a fix
is allowed to go:

| | | |
|---|---|---|
| **A** | mistranslation | fix in game code, against the disassembly. NEVER appears in the ledger — it gets fixed |
| **B** | missing component | fix in the COMPONENT, never in game code. Must name an exit condition |
| **C** | toolchain | permanent, must be behaviour-neutral |
| **D** | deliberate refusal | permanent, behaviour-affecting, argued |

**B is where the danger is**: the symptom shows up in game code while the cause
is elsewhere, so the cheap fix is a line of invented logic that makes the
symptom go away. That line is indistinguishable from a translation once the
reasoning ages out of memory.

`tools/divergences.py` pairs each `DIVERGENCE DIV-nnn` marker against its entry
and fails on an unlabelled marker, a lost marker, a marker in an unlisted file,
a B with no exit, or anything filed as A. A `f.div=<n>` case in `--emudiff`
**inverts**: differing is expected and AGREEING fails, because that means the
ledger describes something no longer true.

It cannot find an UNdeclared divergence. Only differential execution can.

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
* A test double **redeclared a field that already existed on its base class**.
  The double's `Spawn` used its own `Pool` and the code under test used the
  base's, which was nil — so every cross-entity effect silently did nothing
  while the test could still see a perfectly good pool. It looked like a defect
  in the code for three rounds of debugging. **A double must not shadow the
  state the code under test reads**, and a double that overrides the method
  under test only tests the double.
* Naming a method `Destroy` shadows `TObject.Destroy`; FPC warns
  "an inherited method is hidden by ...". Renamed to `DestroyEntity`. That was
  not the bug above, but it made the bug much harder to see.

**Force a full rebuild (`lazbuild -B`) when mutation testing.** An incremental
build can leave you running the old binary, which makes a live mutation look
survived — or a restored file look still broken.

### Tier 0: running the original — `tools/emudiff.py`

There is now a stronger tier than any of the three above, and it should be the
first thing reached for on game logic: **execute akuji.exe's own machine code
and diff it against the reconstruction.**

    python tools/emudiff.py [case-set ...]

`ghidra_scripts/EmuDiff.java` calls a function in the original under Delphi's
`__register` convention and reports EAX; `akuji.exe --emudiff` reads the results
back, recomputes each case in Pascal, and requires agreement. The spec and the
results are **one file** — the emulator echoes each input line with its answer
appended — so the two halves cannot drift apart and a failing case can be re-run
from its own line.

**This was recorded for a long time as blocked on a 32-bit toolchain, and that
was wrong.** What needs one is a logging *proxy DLL*, because a 32-bit process
can only load 32-bit DLLs. *Executing* 32-bit code needs no 32-bit compiler:
Ghidra ships a p-code emulator and `analyzeHeadless` runs scripts with no GUI.
The mistake cost real verification strength — check whether a blocker is the
technique or one *instance* of it.

**It reaches the whole entity layer.** The record used to say this technique
was confined to "leaf routines and arithmetic, which is where the risk is" —
a guess that had never been tested, and on the strength of it the 8,832 lines
of entity handlers were written off. All 78 run to completion here, on live
entities in four states each, without a fault.

`get=ADDR:LEN` is what made that possible. EAX is the whole answer for a leaf
function; an entity handler returns nothing meaningful and its answer is the
entity it MUTATED, so the emulator reads memory back and the Pascal side
compares 260 bytes and names the differing field.

**A FAULT IS NOT WHAT MOST BAD ACCESSES DO.** The `emu_sanity` set writes
through a wild pointer and reads through one, and BOTH RETURN — only executing
unmapped memory stops the emulator. So an unmapped read yields zero silently
and a handler reaching an unplaced global takes a plausible branch with nothing
to announce it. "0 faulted" means the handlers COMPLETE, not that they ran
against sane state.

`--poison-diff` turns that silence into a signal: fill the globals region with
`0x00`, then `0xA5`, and diff. A case whose answer moves depended on memory
nobody placed. Over the live sweep, **4 of 312 moved, all type 69** — so 308
read only what their case placed and are trustworthy.

Current: **300 cases, 14 disagree, 4 declared divergences confirmed**, plus
530 across the original arithmetic sets. Mutation-checked: dropping the `-1`
from the right-edge arm makes 96 of 384 disagree.

For later, not needed now: akuji.exe is i386, ImageBase `0x00400000`, no ASLR,
relocs intact, so a 32-bit host could map its sections at the preferred base and
call functions natively — real globals, real x87. Worth doing only if a function
this project needs turns out to fault under emulation, or if p-code's x87 model
proves untrustworthy.

## 14a. Behaviour, and how far it is checked

`src/gameplay/Player.pas` translates `Player_Update` and its three delegated states. It
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

## 14b. What the differential sweep has found

Kept as a scoreboard because the ratio is the point: **half of what the sweep
reported was mine, not the code's**, and the tell was the same both times —
several unrelated types failing identically.

Real defects, found by running the original:

* **the frame loop was in the wrong shape** — section 6. Three bugs in one:
  the entity update inside the dispatch, `EventScript_Execute` after it
  instead of before, and the session stopping entirely while a box was up.
* **type 49 added `0x40000000` to its Y position.** `Step shr 2` where the
  original has `div 4`. Delphi emits `if v<0 then v+=3; v sar 2` for a signed
  `div 4`; transcribing that codegen literally puts `shr` in the Pascal, and
  FPC's `shr` on an Integer is LOGICAL.
* **the cutscene never ran and the dash orb softlocked** — both wiring, both
  in `frame_shape.py` now.

Harness errors that LOOKED like defects:

* **five handlers "failed" on `EF_CHILD_A`.** `Entity_SteerToPlayer` takes a
  slot number and works on `FSlots[Slot]`; the harness ran handlers on a
  standalone record, so our correct `Steer` updated the wrong entity. The
  original hands each handler a pointer INTO the pool, so there is no
  distinction to get wrong.
* **247 of 312 "failed" at first.** Our handlers take `AGameState` as a
  parameter; the original READS it through the pointer at `0x0046D06C`. The
  emulator left both cells unmapped, so the original ran at state 0 while the
  Pascal was handed 60 — two different code paths presented as a comparison.

And one misdiagnosis worth keeping, because the reasoning was the trap:
`PixelOf` has the same `shr` shape as type 49 and is **not** broken.
`SizeOf(Raw - POSITION_ROUND) = 8` — the untyped constant makes FPC widen the
expression to Int64, so the shift happens in 64 bits and truncates back, which
is indistinguishable from an arithmetic shift. Right answer, for a reason
invisible at the call site. It is `div` now because being right by accident is
not the same as being right, and a typed constant or a hoisted temporary would
silently remove the accident.

### Commit each function the moment it is green

**One function, one commit.** Not at the end of a batch, not "once the next one
is done too" — the moment it builds and its test passes. Everything below is a
consequence of not doing that.

**Never use ANY git command to restore a source file.** Not
`git checkout -- <path>`, not `git checkout-index`, not `git restore`. The rule
was written naming `git checkout` and has now been broken a third time by
reaching for a *different* git command in a mutation-test script -
`git checkout-index -f` restored GmMain.pas from the index, where none of that
session's work was staged. The rule is about the CLASS, not the spelling.

It is unrecoverable. If a revert
is genuinely wanted, `git stash push` keeps a copy. `git checkout` has now
destroyed uncommitted work here **twice**, and both times this file already
said not to use it — so the rule was never the problem, the habit was. The
second time it wiped an unfinished `DelphiRandom` and `SpawnDebris`, recoverable
only because the patch script that generated them happened to still exist. That
was luck.

The point is not that recovery worked. It is that **committed work cannot be
lost this way at all**, which makes the whole failure mode unreachable rather
than survivable.

**Restore mutations by copying a file, never with `git checkout`.** Twice now
that has misfired the other way too: once it reverted a whole file of
uncommitted work, and once it silently did nothing because the file was
untracked, leaving the mutation live in a run that then reported PASSED.

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

**A SPEC MUST NAME ITS SELF-TEST.** `mutate.sh` defaults to
`--selftest-entities`, which touches neither the menus, the message box nor the
session. Run `menus.txt` under that default and all six of its mutations report
SURVIVED - six real defects, every one of them caught, by a test that was
simply never run. "Survived" reads as "your test is worthless", which is the
most expensive way to be wrong here. Each spec file therefore carries

    # selftest: --selftest-session

on a line of its own, and the harness prints which one it used. An explicit
`SELFTEST=` in the environment still wins.

Calibrate it with a negative control — a comment-only change must SURVIVE.
Without that, "everything was killed" can just mean everything failed to build.
