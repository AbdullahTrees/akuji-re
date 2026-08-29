# The divergence ledger

Every place the reconstruction knowingly does something the original does not.

## Why this file exists

The project's governing rule is that the Pascal must match the binary, and that
a bug in the binary is reproduced rather than fixed. The rule is only as good as
our ability to *check* it, and until this file existed there was no check: three
divergences carried a comment saying so, the rest were a sentence of prose
somewhere in an 8,000-line unit, and nothing failed if a fourth appeared.

That is the failure mode this guards against. Not dishonesty - drift. A bug
shows up in game code, the cause is in a component we stubbed, and the cheap fix
is a line of game code that makes the symptom go away. That line is invented
logic, it is indistinguishable from a translation once the comment ages out of
memory, and it is exactly what the ledger is for.

## The taxonomy

Every difference between our behaviour and the binary's is one of four things,
and only the first is a defect to fix in game code.

| | | |
|---|---|---|
| **A** | **Mistranslation** | We read the disassembly wrong. NEVER appears here - it gets fixed, against the disassembly, with a test. If you are tempted to add a category A entry, you are about to invent logic. |
| **B** | **Missing component** | Game code is faithful; it stands on something we have not built yet (the DirectDraw/DirectInput layer, the fader, the sprite engine). Temporary. Every B entry MUST carry an exit condition. |
| **C** | **Toolchain** | Forced by FPC / Win64 / LCL / SDL2, or is test scaffolding. Permanent, and must be behaviour-neutral for game logic. |
| **D** | **Deliberate refusal** | The original does something we will not reproduce - reading uninitialised memory, running off the end of a table. Permanent, behaviour-AFFECTING, and the rarest. Each needs an argument for why the divergent path is unreachable in normal play. |

A category B fix touches the component. A category A fix touches game code.
Getting that backwards is the one mistake this project cannot absorb.

## Format

Source sites carry a marker comment `DIVERGENCE DIV-nnn` so `tools/divergences.py`
can pair them up. The gate fails if a marker has no entry, an entry has no
marker, or an id is duplicated.

An entry may be marked `sites: none` when the divergence is a whole absent file
rather than a line, but it must then say what stands in for it.

---

## DIV-001 - frame pacing sleeps instead of spinning
- category: C
- sites: src/GmMain.pas
- original: 0x00464D30 TFrm_main_AppIdle
- The original sets `Done := False` unconditionally and spin-waits on
  `timeGetTime` until more than 15 ms has passed, pegging a core at 100%.
  We sleep 1 ms and leave `Done` true when there is time to spare.
- behaviour: NEUTRAL for game logic. Both shapes run exactly one update per
  elapsed-time gate and neither frame-skips, so the *sequence* of updates is
  identical; only wall-clock pacing and CPU burn differ. This is what makes
  deterministic input replay sound - see notes/verification.md.

## DIV-002 - menus are driven from the keyboard in FormKeyDown
- category: B
- sites: src/GmMain.pas
- original: no equivalent. The original reads movement and buttons from the Joy
  component inside the frame loop, through one of three DirectInput paths
  selected by Settings+0x34.
- We set FMoveX / FMoveY / FConfirm directly from VK_ codes so the menus can be
  operated at all.
- behaviour: AFFECTING - this is input arriving through a path the original does
  not have.
- exit: delete the marked block, and the paired FormKeyUp block, once Joy polls
  for real.

## DIV-003 - Entity spawn refuses an unknown Kind
- category: D
- sites: src/Entities.pas
- original: 0x0045A1B0 TEntityPool spawn
- For Kind outside 0..2 the original never initialises its two range registers
  and scans the slot array from whatever happened to be in them. We return
  SLOT_NONE.
- behaviour: AFFECTING in principle. Reproducing it faithfully means reading
  uninitialised memory, which is not reproducible - the values are whatever the
  previous call left in those registers, so there is no single behaviour to
  copy. Refusing is the only deterministic option.
- unreachable: every call site in the binary passes a literal 0, 1 or 2.

## DIV-004 - OpeningPictureFor bounds-checks the slide
- category: D
- sites: src/Opening.pas
- original: 0x00463154 Opening_Update
- The original indexes the picture table at 0x00468F14 with `slide - 1` and does
  not check the range. We return -1 outside 1..10.
- behaviour: NEUTRAL in practice - Update clamps Slide to 1..10 before anything
  reads it, so the guard never fires.

## DIV-005 - no fader is modelled
- category: B
- sites: src/GmMain.pas
- original: 0x0044DC48, called with the object at 0x0046CB6C, +0x10 set.
- The screen-fade callbacks are empty. Both end screens and the opening ask for
  a fade and get nothing, so they step straight through the phase that waits on
  it.
- behaviour: AFFECTING - phase timing on the opening, ending and game-over
  screens.
- exit: implement the fade in the SDL2 presentation layer and drive FadeBusy
  from it.

## DIV-006 - the entity dispatcher has an else arm
- category: C
- sites: src/EntityHandlers.pas
- original: 0x0045B0E4, a jump table, which by construction has no default.
- We add `else Inc(EntitiesUnhandled)`. It is test scaffolding: it is what lets
  --selftest assert that every type id the table claims to handle reaches an
  arm, and that the ids it does not claim reach none.
- behaviour: NEUTRAL. The counter is write-only outside the self-test, and no
  arm's behaviour changes.

## DIV-007 - the self-test dispatch in the program block
- category: C
- sites: src/akuji.lpr
- original: 0x0046716C entry, which has four statements and no argument handling.
- We check argv before `Application.Initialize`, so a test run never creates a
  window.
- behaviour: NEUTRAL. Without a recognised switch, control falls through to the
  original's four statements unchanged.

## DIV-008 - the DirectDraw component is a stub
- category: B
- sites: none - the whole of src/DDDDComponent.pas stands in for it.
- original: the TDDDD class, 0x00449xxx.
- The unit exists with the right shape and does nothing. Drawing, surfaces and
  the sprite engine are absent, which is why AppIdle steps 6 and 7 are unwritten.
- behaviour: AFFECTING - everything visual.
- exit: the SDL2 presentation layer.

## DIV-009 - title screen backgrounds and editing are absent
- category: B
- sites: src/Title.pas
- original: 0x00462xxx Title_MainMenu and the options rows.
- Option value editing and key rebinding are stubbed, and the menu backgrounds
  p_Surfaces[1] and [2] are not loaded.
- behaviour: AFFECTING - the options screen cannot change anything.
- exit: surface loading in the SDL2 layer, plus raw button polling for rebinding.

## DIV-010 - type 25 clamps EF_VARIANT instead of running off its table
- category: D
- sites: src/EntityHandlers.pas
- original: 0x0045A4F0 EntityUpdate_Type25, table at 0x0046BE08
- The original indexes a three-entry sprite table by EF_VARIANT and does not
  check it. Out of range it reads whatever DATA follows, which is the next
  type's sprite table - the emulator confirms variant 3 gives 83, variant 4
  gives 99, variant 7 gives 84 and variant -1 gives 481, and every one of those
  matches the bytes at 0x0046BE08 read at that offset. We clamp to 0..2.
- behaviour: AFFECTING outside 0..2 and identical inside it.
- unreachable: all 160 type-25 records in the 65 shipped stages carry ParamA 0,
  1 or 2 - `tools/entity_usage.py <gamedir> --type 25` reports the range as
  flush with the table - and type 25's handler never writes EF_VARIANT, so a
  spawned one keeps the value it was placed with.
- why not reproduce it: the values it reads are deterministic static DATA, not
  uninitialised memory, so unlike DIV-003 they COULD be copied. They are not,
  because writing them into an array called ITEM25_SPRITES would assert that
  the table is sixteen entries long when it is three, and the project has
  already been bitten once by inferring a table's length from the values that
  happen to follow it. The three entries are the table; the rest is the next
  one. What is reproduced instead is the FACT of the overrun, in the emudiff
  case set, where it is exercised and printed on every run.
