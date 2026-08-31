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

## DIV-005 - RETIRED. The fade is reproduced.
- category: C
- sites: none - kept as a record; the divergence no longer exists.
- original: 0x0044DC48 sets it up, 0x0044DC70 ticks and draws it.
- This entry said the fade was timed but not dissolved, and before that that no
  fader existed at all. Both are now wrong, and the entry is kept rather than
  deleted because what it got wrong is instructive.
- The original does NOT dissolve. It draws four black rectangles closing in
  from the edges, and the fill is a DirectDraw Blt with DDBLT_COLORFILL and
  colour 0 - `FUN_004488A0` builds a DDBLTFX with dwFillColor 0 and passes
  0x1000400, which is COLORFILL or WAIT. A black FillRect is the same
  operation.
- So the reproduction now matches on all four counts: the same four
  rectangles, the same colour, the same counter from 0 to 0x78 in steps of 4,
  and the same strictly-outside test that makes a fade 31 ticks rather than 30.
- behaviour: NONE remaining that has been identified.

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

## DIV-009 - the options screen cannot rebind keys
- category: B
- sites: src/Title.pas
- original: 0x00462330 Title_MainMenu, the `MenuIndex - 2U < 3` block.
- Rows 2, 3 and 4 are the three key bindings. The original polls the input
  device for any of 16 raw buttons - FUN_004546C4(Joy, i) for i in 0..15 - and
  on a hit SWAPS that button with whichever row is selected, so two rows can
  never hold the same key. This reconstruction displays the three bindings and
  cannot change them.
- behaviour: AFFECTING - the keys cannot be reassigned.
- exit: raw button polling in the input layer, which is what the swap needs.

  NARROWED 2026-08-30. This entry used to also claim that option VALUE editing
  was stubbed and that the menu backgrounds were not loaded. Both had since
  been implemented and the entry was never updated - the ledger had rotted in
  the one direction nothing checks, describing the reconstruction as worse than
  it is. AdjustValue covers all six editable rows, and GmMain hands Draw
  p_Surfaces[1] and [2], which LoadStage(0) loads. The per-row confirmation
  sounds and the immediate 57-channel volume sweep were the parts genuinely
  missing, and those are now implemented rather than declared.

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

## DIV-011 - handlers clamp table indices the original does not check
- category: D
- sites: src/EntityHandlers.pas
- original: types 2 (0x00459A0C), 7 (0x0045A08C), 14 (0x0045A3E0), 38 (0x0045B0CC)
- Each indexes a sprite table by EF_VARIANT or EF_STATE without a bounds test.
  Out of range the original reads on into whatever DATA follows, which is the
  next type's table. We clamp to the first row. DIV-010 is the same thing for
  type 25 and was found first; this is the class.
- behaviour: AFFECTING outside each table's declared range, identical inside.
- why not reproduce it: exactly as DIV-010. The values are deterministic static
  DATA and could be copied, but writing a neighbour's rows into a table asserts
  a length that tools/table_extents.py contradicts - and all four of these
  tables are FLUSH against the next one, so their declared extents are
  corroborated from outside and the overrun really is an overrun.
- HOW THIS DIFFERS FROM DIV-010, and it is the weaker entry: type 25's clamp is
  provably unreachable, because all 160 of its placements in the shipped stages
  carry ParamA 0, 1 or 2. These four types are SPAWNED AT RUNTIME and place no
  records, so `tools/entity_usage.py` cannot bound them and no equivalent proof
  exists. What sets their variant is whichever handler spawns them, and that has
  not been traced. So this records a real difference whose reachability is
  unknown, rather than one shown to be unreachable.
- there is a third option not taken: declare the sprite DATA region as one flat
  array and make each table a view into it at an offset. That would reproduce
  the overrun exactly, without inventing anything, because it models the memory
  layout rather than guessing at it. It is not done because it would dissolve
  the table boundaries this project spent a long time establishing - but it is
  the faithful answer if these clamps ever turn out to be reachable.


## DIV-012 - the spawn window reads the layer origin, not the tile component's scroll
- category: B
- sites: src/GameSession.pas
- original: 0x00454790 Events_SpawnNearCamera, first two statements.
- The original computes the camera tile from the TILE COMPONENT's own scroll
  and the LAYER's tile size, mixing two objects:

      camTileX = *(TileMaps + 0x6034) / *(LayerInfo + 0x10)
      camTileY = *(TileMaps + 0x6038) / *(LayerInfo + 0x14)

  0x6034/0x6038 are the component's ScrollX/ScrollY - the layout is pinned by
  TileMap_DefineTile @ 0x0044DAE0, which puts TileW at Self+0x6028 and TileH at
  Self+0x602C directly above them, above 1026 tile definitions of 0x18 bytes
  from Self+4. This reconstruction uses PixelOf(Layer.OriginX) div Layer.TileW
  for both.
- The two agree in the steady state, because the component's scroll is set from
  the layer while drawing. They differ in WHEN: the component's copy is written
  during the draw at AppIdle step 8, and the spawn walk runs at step 5, so the
  original spawns against the value the PREVIOUS frame's draw left behind. This
  reconstruction uses the current frame's camera.
  Stage_Begin @ 0x00462210 does not write the component scroll at all - it sets
  only the layer origin - so on the first frame in a new room the original's
  window is placed by whatever the last room's draw left there, and only the
  second frame is correct.
- behaviour: AFFECTING but small - a one-frame lag in when an entity enters or
  leaves the spawn window, and a first frame in each room whose window sits
  where the previous room's camera was.
- exit: the presentation layer owning a real tile component with its own scroll
  updated at draw time; then CamTileX/CamTileY read that field instead. It
  cannot be reproduced honestly in game code, because the value it wants is the
  component's, and faking the lag with a saved copy in the session would be
  invented logic standing in for a component that does not exist yet.

## DIV-013 - the music engine is reimplemented, not the DLL

- category: B
- sites: none - src/KbgmPlayer.pas (679 lines), src/MidiFile.pas (409) and
  src/MidiOut.pas stand in for the whole of it.
- original: Kbgm32.dll, a third-party MIDI engine shipped beside the game. The
  original wrapped it and the import table still names all thirteen exports:
  KBGMOpen, KBGMClose, KBGMInit, KBGMLoadFile, KBGMFree, KBGMPlay, KBGMStop,
  KBGMFadeIn, KBGMFadeOut, KBGMSetRepeat, KBGMSetVolume, KBGMSendSysx,
  KBGMGetInfo.
- Those names are the entire specification we have for it - there is no
  documentation and we have not disassembled the DLL - so the interface in
  KbgmPlayer.pas is shaped to them rather than invented. Underneath, MidiFile
  parses the files and MidiOut sends to the system MIDI mapper through winmm,
  where the original handed the file to KBGMLoadFile and never saw an event.
- WHY IT IS NOT SIMPLY IMPORTED, which is what one would expect: kbgm32.dll is
  PE32 i386 (machine 0x014C) and this build is PE32+ x86-64. A 64-bit process
  cannot load a 32-bit DLL, so on the current FPC/Win64 toolchain importing is
  impossible regardless of preference. That constraint disappears on the
  Delphi 6 x86 target, which is 32-bit.
- behaviour: AFFECTING, and not only audibly. GameOver_Update leaves its screen
  when the music stops - FUN_00450FD0 wraps KBGMGetInfo - so how long our
  engine thinks a track lasts decides how long the game-over screen is shown.
  Anything that gates on IsPlaying inherits our timing rather than the DLL's.
  Fades are ours too: KBGMFadeOut ramps 100 volume steps down over arg*50 ms
  by the DLL's own arithmetic, and we reproduce that shape, not its output.
- exit: THE PLAN IS TO DELETE THIS. On the Delphi 6 x86 build, write out
  KbgmPlayer.pas and declare the thirteen exports `external 'kbgm32.dll'`
  directly. The published interface already matches them one for one, so it is
  a replacement of bodies rather than a redesign, and it removes MidiFile and
  MidiOut from the music path with it. That is the faithful arrangement: the
  original did not own a MIDI engine, it called one.

## DIV-014 - the sound component is reimplemented, not the DirectSound one

- category: B
- sites: none - src/DDSDComponent.pas stands in for it, over SoundTable,
  WaveFile, AudioMixer and AudioOut.
- original: the third-party TDDSD DirectSound component, whose published
  interface GmMain.lfm documents. Only DebugOption and ChannelCount are
  streamed.
- ChannelCount is 57, the executable holds exactly 57 sound-effect names in a
  static array at 0x00468D50, and wav/ holds exactly 57 files - so a channel is
  one DirectSound buffer holding one effect, not a voice in a pool. Slot number
  and sound number are the same thing, which is why re-triggering a sound
  restarts it rather than layering. That much is reproduced. What is not is the
  device: the original used DirectSound buffers and winmm's mmio* readers,
  where this mixes in software and plays through waveOut.
- behaviour: NEUTRAL for game logic as far as anything traced - no game code
  reads sound state back, unlike the music, which the game-over screen waits
  on. Audibly different in mixing and latency.
- exit: the presentation layer owning a real DirectSound path, or on the
  Delphi 6 x86 target the original component itself if it can be obtained.

## DIV-015 - input reads LCL virtual keys, not DirectInput scancodes

- category: B
- sites: none - src/DDIDComponent.pas stands in for it. DIV-002 covers the
  separate matter of the menus being driven from FormKeyDown.
- original: the TDDIDEX component, named "Joy" on the form, wrapping
  DirectInput and reading raw DIK scancodes. The table was recovered from
  DirectInput_Init @ 0x00453BDC: 0x2C..0x2E for Z X C, 0x1E..0x20 for A S D,
  0x02..0x0B for the digits, 0x39 space, 0xC8..0xCD arrows, 0x47..0x51 numpad.
- We map LCL virtual keys for the same physical keys. It is the same keyboard
  but not the same table: a scancode is a POSITION and a VK is a LETTER.
- behaviour: AFFECTING only on a non-QWERTY layout, where the original's Z and
  ours are different physical keys. On QWERTY the two agree.
- exit: a presentation layer that reads scancodes, at which point the recovered
  DIK table is used directly and the mapping disappears. Also outstanding: the
  item-select digits have no reader yet and are deliberately left unmapped
  rather than guessed at.
