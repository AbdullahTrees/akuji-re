# tools/

Everything here exists to make a claim about `akuji.exe` checkable. The project
cannot produce a byte-identical rebuild — different compiler, different RTL,
64-bit target — so correctness is established by other means, and these are the
means. `CLAUDE.md` sections 14 and 14a explain the reasoning; this is the index.

## The gate

    tools/check.sh [game dir]

One command: build, every self-test, the reference implementations, a records
check and a negative control. Exits non-zero if anything fails, so use it as
`tools/check.sh && git commit`. It is one command on purpose — two failures on
this project came from shell chains rather than from code, including a run piped
through `tail` that reported the pipe's exit status and made a failing self-test
look green.

## Second readers

Every binary format is implemented twice, once in Pascal and once in Python from
the same evidence, and the two are diffed. Agreement between two independent
readers is the strongest evidence available here.

| tool | pairs with |
|---|---|
| `extract_qda.py` | `QdaArchive.pas` — 44/44 entries byte-identical |
| `decode_wav_ref.py` | `WaveFile.pas` — 57/57 effects byte-identical |
| `parse_midi_ref.py` | `MidiFile.pas` — 15/15 tracks, checksummed on the *merged* event stream, so the track merge is checked too |
| `analyse_events.py` | `EventCommands.pas` — independent splitters agreeing line for line |

## Mutation testing

    tools/mutate.sh tools/mutations/entities.txt [game dir]

Applies a deliberate defect, rebuilds, and requires the gate to notice. **A test
that cannot fail is worse than none**, and on this project that has happened six
separate ways:

* a self-test that passed having loaded **zero** events
* an `Assert` the compiler removed entirely — FPC drops assertions without `-Sa`
* a check whose reference was built from the constant under test
* one the compiler folded to a constant and warned "unreachable code" about
* one that verified a table's values using **that table's own length**
* one that watched for an effect the code stopped producing either way, so
  deleting the guard it was testing changed nothing observable — observe
  something that happens *before* the guard

Mutations are records of `name / file / --- / old / ---> / new` separated by
`===`. Every guard in the script is scar tissue from a run that went wrong — a
lock, a timeout, a verified restore, stray-process cleanup — and the header
explains each one.

**Calibrate with a negative control.** A comment-only change must SURVIVE;
without that, "everything was killed" can just mean everything failed to build.

## Analysis

Reach for these before repeating the mistake that produced them.

### `table_bounds.py` — where does this const array end?

    python tools/table_bounds.py <exe> --region 0x46B800 0x46C400
    python tools/table_bounds.py <exe> --ptr 0x46CBA0 --readers

Reading N values out of a binary and finding they match proves the **values**,
never N — and a check that computes N from the constant it is verifying can
never fail. A sprite table here was recorded as 16 rows and is 2, and the
self-test passed either way.

The extent needs a fact from outside the table. Delphi lays typed constants out
consecutively and reaches each through its own pointer global, so a table ends
where the next begins. Corroborate two further ways: count the **readers** of
the pointer (one reader means no other caller can need more rows), and check the
table is flush with its **use** — an argument range of exactly 0..N-1 against an
N-entry table agrees from both directions.

Beware the near miss. Two adjacent tables, both plausible, is exactly how the
16-versus-2 error happened: the evidence for 16 was real and belonged to the
next table along.

### `entity_usage.py` — what does the shipped data actually place?

    python tools/entity_usage.py <gamedir>
    python tools/entity_usage.py <gamedir> --type 25
    python tools/entity_usage.py <gamedir> --paramb

Prioritises the remaining handlers by how much of the game they buy — type 25 is
placed 160 times across all 65 stages, most types once or twice — and supplies
the "flush with its use" half of a table-length argument.

`--paramb` groups by script instead of by type, which is how the save point was
identified: type 27 appears exactly once in each of 43 stages, always opcode 1,
with a ParamB byte-identical in all 43.

It also finds types that are placed but have **no handler arm**, which is how
"type 20 is an inert marker" stopped being a guess.

### `x87_sim.py` — what would the original's FPU have produced?

    python tools/x87_sim.py check      the integer model vs the simulation
    python tools/x87_sim.py table      regenerate the golden table, as Pascal
    python tools/x87_sim.py compare    80-bit vs 64-bit vs exact

Delphi runs the x87 at **64-bit significands**. FPC on x86-64 has no such type —
`Extended` is an alias for `Double` — so integer arithmetic the original did
through the FPU cannot be reproduced with floats at all on that target. Here the
80-bit and 64-bit answers differ in 118 of 103,525 cases, three of them reachable
from the shipped data.

The fix is to model the rounding in integers. This is the reference that says the
model is right, written a deliberately different way — exact rationals, explicit
rounding to a p-bit significand — so that agreeing with it means something.

The useful general result: **every disagreement with exact arithmetic is a tie**,
the exact value landing on x.5. Away from one, the FPU's ~1e-19 relative error
cannot reach the rounding boundary. Handle the ties and the rest is division.

## Bookkeeping

| tool | what it does |
|---|---|
| `coverage.py` | how much of the game layer has a Pascal counterpart. Deliberately matches only the `0x` address form, so `HANDLER_ADDR`'s table of 78 addresses does not inflate it — a table of addresses is a to-do list, not a translation |
| `check_function_map.py` | keeps `notes/function_map.md` and the name database from disagreeing |
