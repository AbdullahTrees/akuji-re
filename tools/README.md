# tools/

Every tool in this directory, what it is for, and whether anything depends on
it. **This table is the index — if you add a tool, add a row.** The previous
version of this file documented 16 of 34 tools and omitted 8 of the 11 the gate
runs, which made it impossible to tell load-bearing from archaeological.

Each tool's own docstring says *why it exists*; this says *when you would reach
for it*.

---

## The gate — `bash tools/check.sh`

Run before every commit. These are wired into it, and a red one blocks.

| tool | what it refuses to let through |
|---|---|
| `audited.py` | a frozen function whose body changed. Fingerprints with comments stripped, so prose stays free. `--bless` rewrites the lock, and **blessing IS the approval gesture** |
| `divergences.py` | a ledger entry with no marker in `src/`, or a marker with no entry |
| `implemented.py` | a game function with prose but no executable Pascal |
| `layout_lock.py` | a witnessed field offset that nothing asserts at runtime |
| `shadow_globals.py` | one address claimed by two different variables |
| `table_extents.py` | a recorded table whose length is not pinned from OUTSIDE it |
| `const_immediates.py` | a handler constant that does not appear in that handler's code |
| `frame_shape.py` | a frame loop that has lost its shape, or unwired form plumbing |
| `check_function_map.py` | `function_map.md` drifting from `game_functions.txt` |
| `x87_sim.py` | `ScaleByPercent` disagreeing with an exact rational model of the FPU |
| `javac_check.sh` | a Ghidra script that no longer compiles |

## Proving the reconstruction against the original

| tool | when |
|---|---|
| `emudiff.py` | **the strongest evidence available.** Runs the ORIGINAL's machine code under Ghidra emulation and requires the Pascal to agree. `handler_live` is the entity-handler sweep — 296 cases. Re-run after touching any `EMUDIFF` row |
| `samebinary.py` | **the v1.0 constraint.** Did `.text` move? `--where` names the functions. See `notes/v1.0_handover.md` |
| `bindiff.py` | did any INSTRUCTION change between two builds of `akuji.exe` |
| `mutate.sh` | break the game deliberately and check the tests notice. **Read CLAUDE.md §3c first — never leave a mutant binary on disk** |
| `make_trace.py` | generate a Frida script to trace the ORIGINAL while it runs |

## Reading the game's data

Reference implementations, kept separate from `src/` so that a decoder and its
check cannot drift into agreeing with each other by accident.

| tool | reads |
|---|---|
| `extract_qda.py` | `bmp.qda`, the sprite and picture archive |
| `decode_wav_ref.py` | the sound effects |
| `parse_midi_ref.py` | the MIDI playlist |
| `analyse_events.py` | the event mini-language in `ev*.dat` |
| `entity_usage.py` | what the shipped stages place, and with what arguments — **the fastest way to bound a variant's range** |

## Answering a question

Reach for these while working, not on a schedule.

| tool | question |
|---|---|
| `table_bounds.py` | where does *this* const array end? (`table_extents.py` is the gate version: are they *all* pinned?) |
| `coverage.py` | is every game function at least *mentioned* in `src/`? |
| `implemented.py` | …and does it have code, rather than a comment? |
| `delphi6_audit.py` | what would stop this compiling under Borland Delphi 6? |
| `x87_sim.py` | what would the original's 80-bit FPU have produced? |

## Entity identification

| tool | |
|---|---|
| `zoo.py` | rebuild stage 1 as a zoo: one of every entity a sprite set can draw, each in a cage with a sign. `--install <dir> <set>` / `--restore <dir>` |
| `apply_entity_names.py` | push `entity_names.csv` into the Pascal and print the Ghidra renames |
| `entity_names.csv` | **the source of truth for entity names.** Edit this, then run the above |

## Baselines (data, not tools)

| file | |
|---|---|
| `v1.0_sections.json` | sha256 of v1.0's real sections |
| `v1.0_functions.json` | sha256 per function body, for `samebinary.py --where` |
| `../notes/audited.lock` | the freeze fingerprints |

---

## Two traps worth knowing before you use these

**A hand-run mutation can silently not rebuild.** `mutate.sh` writes a broken
game into `src/akuji.exe`. If the restore does not rebuild in the *same*
command, the next person to launch the game plays the mutant — and the bug
report will send you hunting through code that is fine. Chain it:
`mutate && build && run; restore && build`. CLAUDE.md §3c.

**A tool agreeing with itself proves nothing.** The reference readers exist
because a decoder checked against its own assumptions always passes. When a
reader and `src/` disagree, the binary decides — not whichever one is easier to
change.
