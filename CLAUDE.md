# Akuji the Demon — Project Brief

Reconstructing the source of a Japanese doujin game, released around 2001, from
`akuji.exe`. The original source was never released. The output is **the**
source, rebuilt in Object Pascal — cross-platform because Free Pascal is, not via
any porting layer.

Read sections 1–4 before touching anything.

> ## BEFORE YOU EDIT ANY PASCAL FUNCTION
>
> **Check `notes/audited.md` first.** It has three tables - game-layer
> functions, the component layer, and binary layouts (records whose offsets
> must match) - and the STATUS column is the answer:
>
>     grep -i '<address or name>' notes/audited.md
>
> * `MATCHES` or `FIXED` — **FROZEN. Do not edit it.** Name it, quote the
>   disassembly that proves the defect, and **ask the user. Approval is
>   required before the edit**, per change. See section 3a.
> * `EMUDIFF` — an entity handler. Edit it, then re-run
>   `python tools/emudiff.py handler_live`.
> * `PARTIAL` — part of it was compared and the row says which. The
>   compared part is frozen; ask before changing it.
> * `UNVERIFIED` — free to change. This is most of them, and it is not a
>   defect list.
>
> The component layer counts. It is code we replace wholesale, so its behaviour
> is ours to get right - the sprite draw order was inverted there for weeks and
> no game-layer function could have explained it.
>
> This check comes BEFORE the edit, not after. `tools/audited.py` will catch a
> frozen function that changed, but by then the work is done and has to be
> unpicked — and the point of the rule is that the verification is more
> expensive than the edit that destroys it.

---

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

## 3a-1. MATCHES MEANS ONE-TO-ONE. BOTH DIRECTIONS.

**A function is only MATCHES or FIXED when its behaviour and the binary's are
equivalent - everything the original does is implemented, AND nothing the
original does not do is present.** Never mark a row without having checked both
directions.

The second half is the one that gets skipped, and it is not hypothetical.
`Stage_Begin` was marked FIXED on the strength of "all thirteen statements
accounted for" - which was true, and still wrong, because the Pascal ALSO
configured the terrain, rebuilt the background animator and loaded the event
scripts. None of those is one of Stage_Begin's statements; all three belong to
`Load_Stage_Assets`, and the xrefs say so plainly. The row claimed equivalence
and had only established containment.

So an audit is two passes, and a row states both:

* **forward** - walk the original's statements and find each one in the Pascal.
  Say how many there are, so the count can be checked.
* **backward** - walk the PASCAL and account for every statement in it. Each
  one is either a statement of the original, a declared divergence, or
  scaffolding that has no effect. Anything else means the row is not MATCHES.

Extra behaviour is as much a defect as missing behaviour. It is worse in one
way: missing behaviour shows up as something not happening, which someone
eventually notices, while extra behaviour hides inside a function that looks
correct and is marked verified.

`tools/audited.py` requires every frozen row to carry an explicit `EXTRAS:`
clause naming what the backward pass found, or `EXTRAS: none`. A row that has
not made that statement cannot be frozen.

## 3a. AN AUDITED FUNCTION IS FROZEN

**`notes/audited.md` has one row for every game-layer function - all 149 - and
the STATUS column says what evidence exists for it. A function whose status is
MATCHES or FIXED has been read against a fresh decompile, and no other piece of
work may change it.**

This is not a style preference. Those functions went through two passes: a
first one that too often wrote the SPECIFICATION into Pascal - a comment
describing what the binary does, beside code that did something else - and a
second that read the disassembly, implemented the behaviour for real, and
tested it. That second pass is expensive and it is the only reason the entries
are trustworthy. A later change made in passing, to fix something else, silently
throws it away: the row still says the function was verified, and it no longer
describes the code.

So the rule, and it has no expiry:

* **Do not touch an audited function as collateral.** If a fix somewhere else
  seems to need one changed, the fix is in the wrong place until proven
  otherwise. Change the caller, the host, the component - not the audited body.
* **If an audited function really does have a bug, say so and STOP.** Name the
  function, quote the disassembly that proves the defect, explain what is wrong,
  and *ask*. **User approval is required before the edit.** Not "flag it and
  proceed", not "fix it and mention it in the commit" - approval first.
* Approval is per change. It does not carry to the next one.
* After an approved change the function must be **re-audited against a fresh
  decompile** and its row updated to say what was re-checked. It does not stay
  verified because it was verified once.

Comments and formatting inside an audited function are NOT frozen - behaviour
is. Improving a comment needs no approval.

### How to check, every time

Before touching any function in `src/`:

    grep -i 'DrawHud' notes/audited.md        # or the 0x00... address

The STATUS column decides. MATCHES and FIXED are frozen; EMUDIFF means re-run
the differential sweep afterwards; UNVERIFIED is free. `notes/audited.md` is one
row per function over the whole 149, so "it is not in the list" is not an
answer — every game-layer function is in it.

`tools/audited.py` enforces this rather than trusting anyone to remember it. It
fingerprints every frozen implementation with comments stripped and whitespace
normalised, so prose and layout stay free while a changed statement fails the
gate. `notes/audited.lock` holds the hashes and
`python tools/audited.py --bless` rewrites it - blessing IS the approval
gesture, so it is never run without the user having said yes.

## 3a-0. Working rule: the comments are a specification, not a record

**Read the comments first, then verify them against the disassembly, then check
the code beside them actually does what they say.**

This project's comments are dense with decoded fact - offsets, orders,
constants, the reason a number is 19 rather than 16. They were written by
someone reading the binary carefully. That makes them the best starting point
for any change, and it makes them dangerous in one specific way:

**A comment describing behaviour is not evidence the behaviour is implemented.**

Four bugs in a single day were exactly this, and every one had the right answer
written down beside code that did something else:

| the comment said | the code did |
|---|---|
| `SpawnX := tileX * TileW + 16`, with the +19 asymmetry explained | nothing - `LoadStage` was an empty inherited method |
| "two single-character flags decide whether it loops" | passed `True` unconditionally |
| `FIndex // p_MenuIndex 0x0046CF88, shared with the pause menu` | a private field, shared with nothing |
| "GameState := 100, the game-over screen. The caller owns that." | `Exit`, and no caller owned it |

So the order is: **read the comment, disassemble the function it names, check
the two agree, then check the code agrees with both.** A comment that states an
address is an invitation to open that address, not a substitute for having done
so.

The tell is a comment written in the passive or the future - "the caller owns
that", "left to the host", "decides whether" - sitting next to code with no
corresponding statement. Treat that as an unfinished line, not a finished one.

## 3a-2. Comments answer WHY. The code answers WHAT.

Section 3a-0 says the comments are a specification. That does not license
essays. A long comment is a second implementation written in prose: it drifts
out of step with the code, and unlike code nothing checks it.

That has already happened here repeatedly - each of these was believed until
something contradicted it:

| the comment claimed | the truth |
|---|---|
| "only types 52 and 54 pace off their own HP" | five do: 31, 42, 52, 54, 73 |
| type 14's clamp is safe, "range 0..15, table of 16 rows" | those are TYPE 24's dimensions |
| `Event_Begin` sizes the array twice, "the first is redundant" | there is one SetLength; the COUNT call is doubled |
| type 6's sprite row "is set by its spawner" | named the wrong spawner |

**The rules.**

1. Do not narrate control flow. If a block needs explaining, first try naming
   things so it explains itself.
2. Prefer a named constant to a comment about a literal. "An essay followed by
   magic numbers" is the failure this catches.
3. Before writing a derivation down, ask whether anyone needs it. Usually only
   the FACT matters - `SolidThreshold is 0x32 for terrain 1` earns its place;
   the paragraph reconstructing how that was found does not.
4. When the working-out genuinely must survive, put ALL of it in `notes/` and
   leave the FINDING in the code with a one-line pointer. Not a summary of the
   journey - the conclusion.

**Keep:** a measured constant, why an apparent bug is deliberate, a hazard
invisible at the call site, a contract another file depends on. Addresses are
NOT on this list - see section 3a-3.

**Deleting is the second choice, not the first.** A comment pass is not a
comment CULL. Read each comment and ask *is this discernible from the code?*

- **Yes** - delete it. `Camera.pas`'s header restated the dead-zone bounds that
  `DEADZONE_LEFT/RIGHT/TOP/BOTTOM` already name twenty lines below.
- **No** - the comment is there because the code is not saying it. **Change the
  code.** Name the constant, rename the variable, extract the helper. Only when
  that genuinely cannot carry the fact (a measurement, a hazard, a contract) does
  it stay as prose. `Entities.pas` described the type table's 18 columns in 23
  lines because `Entity_Spawn` read them as `T.Raw[0]`, `T.Raw[3 + I]`; naming
  the columns deleted the table and improved the code in one move.

Deleting an undiscernible comment does not tidy the file, it loses the fact.

`tools/audited.py` strips `{ }`, `(* *)` and `//` before fingerprinting, so pure
prose edits cannot trip the freeze gate. Edits that change code CAN - check
`notes/audited.md` first, and run `tools/check.sh` either way.

## 3a-3. SOURCE COMMENTS EXPLAIN THE GAME, NOT THE RECOVERY

**A comment in `src/` explains how the game works. It does not explain how the
decompilation went, where a fact came from, or why a translation choice was
made.** Someone reading `src/` is reading a game's source code. They are not
reading a lab notebook, and the two have been mixed together throughout.

So these do NOT belong in `src/`:

* **Addresses.** `Player_Update @ 0x004585A8`, `p_LastFrameTime 0x0046D1E0`,
  `see 0x00450F14`. The address of the routine this one was translated from is
  a fact about the recovery.
* **Disassembly.** Quoted instructions, register names, `MOV EAX,[0x0046cc14]`.
* **Provenance and derivation.** "read off the trace, not from the code",
  "which is the whole reason they could be identified", "transcribed from the
  disassembly", "the original's own once-a-second sample".
* **The journey.** "which has caught me out", "missing all three was a
  softlock", "believed until X contradicted it", how many passes it took.
* **Ghidra.** What it named something, what it got wrong, what was pushed into
  it.

The finding survives; the archaeology goes with it. Rewrite, do not just
delete - section 3a-2 still governs, and `Deleting an undiscernible comment
does not tidy the file, it loses the fact` is still true. The rewrite states
the fact as a property of the game:

| instead of | write |
|---|---|
| `Overlay_Update @ 0x004568D0 stops the music and starts playlist entry 4` | `The panel is dismissed only when the music stops, so its fanfare must be started or the looping stage BGM leaves it up forever.` |
| `the fullscreen compare is case-SENSITIVE (@LStrCmp at 0x004656D8)` | `The [disp] fullscreen compare is case-sensitive.` |
| `0x00464D30 counts the event delay down HERE, between the two blocks` | `The event delay is counted down between the two state dispatches; the arms are mutually exclusive, so no frame runs both.` |

### The exception, and it needs asking about

Some recovery facts ARE load-bearing for reading the source. Those stay, phrased
as statements about the code rather than about the binary:

* **Hazards where the obvious code is wrong.** `SoftwareVsync` must be the
  shared global, not a form field, or the options toggle is inert. The frame
  clock's `DWord` arithmetic is deliberate - the clock wraps every 49 days and
  the subtraction wraps with it. `Assert` is compiled out without `-Sa`, which
  this project does not pass, so startup layout checks must be `if ... raise`.
* **Invariants no single call site shows.** The fade must not advance while
  paused. Entity-to-entity collision uses the hitbox inset and tile collision
  uses the box offset; swapping them is silent.
* **Naming caveats.** `WALLKICK`, `AIRDASH` and `GLIDE` are named for what
  `Player.pas` does with each flag, not for the game's own words. The indices
  are certain; the labels are a reading.
* **Contracts across files.** `TPlayerState`'s packed layout IS `data/save.dat`.
  The `// +0xNNN` field annotations are each backed by a runtime assertion, and
  `tools/layout_lock.py` checks that they are.
* **`DIVERGENCE DIV-nnn` markers**, which `tools/divergences.py` gates.

**Adding to that list needs the user asked first.** It is an exception, and an
exception that anyone may widen on their own judgement is not one.

### Where the addresses went

`notes/implemented_map.tsv` maps every game-layer address to the routine in
`src/` that implements it, and `tools/implemented.py` reads it. That mapping
used to live in the source, as an address inside the comment block immediately
above each declaration - which is why removing those comments took the gate
from 149 to 14 while everything still built and every self-test still passed.
It is a file now, so reformatting `src/` cannot reach it.

**When you translate a new function, add its row there.** That is where the
address goes; it does not go above the declaration.

## 3b. Working rule: write the code as you read the disassembly

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

## 3d. GHIDRA'S NAMES ARE OUR NAMES. THEY ARE NOT EVIDENCE.

On 2026-08-31 the reconstruction's names, structs and prototypes were pushed
INTO the Ghidra project. So the decompilation now uses our field names because
we typed them there, not because anything confirmed them.

**Never cite a Ghidra symbol as evidence for the Pascal.** `E->BlockA_State`
agreeing with `EF_STATE` is not corroboration, it is an echo. Evidence is the
raw disassembly, the bytes, or a differential test - the same standard as
before. notes/ghidra_naming.md grades which names were read off behaviour and
which were imported on trust.

## 3c. NEVER LEAVE A MUTANT BINARY ON DISK

`src/akuji.exe` is the file the user plays. A mutation check builds a
DELIBERATELY BROKEN game into it, and every second between that build and the
rebuild-after-restore is a second the user can launch it.

That is not hypothetical. On 2026-08-31 a session was played against a mutant
whose `TPlayerState` had `Lives` and `MaxLives` swapped, and the bug report -
no music, no game-over screen - sent me hunting through the music engine, the
playlist, the save file and the game-over wiring. All of it was fine. The
binary was not.

So: **restore and rebuild in the SAME command as the mutation run**, never in
the next one. Chain it - `mutate && build && run; restore && build` - so no
turn boundary, no tool result, and no user message can land in between. If a
mutation run is interrupted, rebuild before doing anything else.

And when a bug report arrives, check `src/akuji.exe` is newer than the sources
and the tree is clean BEFORE reading any code. It is one command and it would
have saved the whole hunt.

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

---

## Where everything else is

This file is RULES. Facts and machinery live beside it, so that the rules stay
short enough to be read:

| | |
|---|---|
| `notes/audited.md` | one row per game function: status, evidence, and whether you may edit it. **Check before touching any Pascal.** |
| `notes/reference.md` | the decoded formats, tables and structures - assets, the entity system, the event language, settings, audio, the frame loop |
| `notes/verification.md` | the tooling, the verification tiers, and what the differential sweep has found |
| `notes/status.md` | where the work stands and what is left |
| `notes/divergences.md` | every knowing difference from the binary |
| `notes/function_map.md` | detailed per-function annotations |
| `notes/implemented_map.tsv` | which Pascal routine implements each game-layer address. **Add a row when you translate a function** - see 3a-3 |
