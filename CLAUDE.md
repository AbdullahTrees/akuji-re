# Akuji the Demon — Project Brief

Reconstructing the source of a 1998 Japanese doujin game from `akuji.exe`. The
original source was never released. The output is **the** source, rebuilt in
Object Pascal — cross-platform because Free Pascal is, not via any porting layer.

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
