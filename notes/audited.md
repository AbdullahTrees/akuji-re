# What is verified, and what may be changed

Three tables, because there are three kinds of thing we reimplement and each
has a different population. In all of them the STATUS is the whole answer: it
says what evidence exists, and therefore whether the thing may be edited.

| status | evidence | may I change it? |
|---|---|---|
| `MATCHES` | ONE-TO-ONE with the binary, checked BOTH ways: every statement of the original is present, and every statement of the Pascal is accounted for. The row carries an `EXTRAS:` clause saying what the backward pass found | **No.** Frozen - CLAUDE.md section 3a. Name it, quote the disassembly, ask first |
| `FIXED` | the same two-way standard; a difference was found and corrected. Also carries `EXTRAS:` | **No.** Frozen, same rule |
| `PARTIAL` | some of it compared, and the row says which | The compared part is frozen; ask before changing it |

| `EMUDIFF` | an entity handler, verified by RUNNING the original's own machine code - 296 cases, 0 disagree | Yes, then re-run `python tools/emudiff.py handler_live` |
| `UNVERIFIED` | none | Yes, freely |

**Every FIXED row was downgraded to PARTIAL on 2026-08-30.** `Stage_Begin` was
marked FIXED after four of its thirteen statements had been compared - the audit
had been a hunt for one specific bug, not the line-by-line read the status
claims - and it was still missing its fade, its `GameState_Reset(form, 1)` and
its `ScreenPhase := 0`. A row earns FIXED back only after a pass that accounts
for every statement.

## The note column is a RESIDUE, not a transcript

This file is a tally: what has been checked, and therefore what may be edited.
It is not where an audit is written down. The reasoning belongs on the Pascal
itself, which CLAUDE.md 3a-0 already makes the spec, and the C it was read
against is in `exports/functions/`. Both outlive a paragraph here, and the
comment sits where the next person to edit the code will actually see it.

So a note carries only what the tally needs:

- **what was found** - a defect fixed, or a residual still there
- **what we knowingly differ on** - the `EXTRAS:` clause, which `tools/audited.py`
  requires on every MATCHES and FIXED row so the backward pass cannot be skipped
- **`BACKWARD OUTSTANDING`** - forward pass done, nobody has yet walked the
  Pascal for statements the ORIGINAL does not have. It was 16 copies of the same
  paragraph until 2026-08-31; it is a marker, and this is its one definition.

Enumerating the forward pass - every offset, table and immediate - is what the
source comments are for. Rows that did it here were cut on 2026-08-31, from
46.5KB to 30KB, with anything not already in the Pascal moved there first.

**UNVERIFIED is not a defect list.** The game is broadly playable, so most of it
is probably fine. It is unproven rather than suspect. The point of listing it is
that when a bug points at one, nobody wastes time assuming it was checked.

`tools/audited.py` reads these tables, fingerprints every frozen implementation
into `notes/audited.lock` with comments stripped, and fails the gate if one
changes. `--list` filters by status.

## 1. Game-layer functions

The population is `notes/game_functions.txt` - all 149 between 0x454790 and
0x4671FF - and every one has a row. "It is not in the list" is never an answer.

| addr | function | status | implementation | what was compared |
|---|---|---|---|---|
| 0x00454790 | `Events_SpawnNearCamera` | PARTIAL | `EventRunner.pas TEventRunner.SpawnNearCamera` | Forward 2026-08-30. FIXED: the disable branch called Pool.Kill where the original calls Entity_Destroy - xref 0x004548E3 - so the sprite was orphaned and held its last SCREEN position: the unlocked door that followed the player. Residuals: DIV-012, the camera tile taken from the layer origin; and the seventh ParamA form, which no shipped record reaches. BACKWARD OUTSTANDING. |
| 0x00454ef4 | `Event_Begin` | PARTIAL | `EventRunner.pas TEventRunner.StartEvent` | Forward 2026-08-30. Residual: it also zeroes the message mode 0x0046CF28, which this runner cannot reach - Host is a parameter of Execute, not a field. Unobservable: a box exists only during state 140 and this refuses to run then. BACKWARD OUTSTANDING. |
| 0x0045509c | `EventScript_AdvanceStep` | PARTIAL | `EventRunner.pas TEventRunner.AdvanceStep` | AUDITED 2026-08-30, statement for statement: ScreenPhase := 0 FIRST, then increment the step index, then run off the end to state 0x3C if it passes DynArrayHigh(steps); otherwise Cursor := 0, split the step on '.' into CommaText, and scan the alternatives BACKWARDS - the last one whose progress flag is set wins and is written back, and every one that does not match clears the step, so a step with no matching alternative is left empty and does nothing. BACKWARD OUTSTANDING |
| 0x00455210 | `EventScript_Execute` | PARTIAL | `EventRunner.pas TEventRunner.Execute` | sub-op 3's arm audited 2026-08-30 after an infinite-loop report. It guards on the MESSAGE MODE at 0x0046CF28 - `if (*PTR_DAT_0046cf28 == 0)` then set it to 1 along with the page start 0x0046CC98 and the reveal cursor 0x0046CF24 - NOT on ScreenPhase. Ours used ScreenPhase, which the \k page turn clears, so Execute re-raised page 1 every frame. Also confirmed here: sub-op 10 guards on the OVERLAY flag 0x0046CD00, sub-ops 4/5/6/7/8/9/11/13/14/15/16 all end in AdvanceStep, sub-op 17 counts 0x0046D218 up to its argument, and sub-op 99 advances immediately. The rest of the function is not yet compared statement by statement |
| 0x00456038 | `MessageBox_Update` | PARTIAL | `Dialogue.pas TDialogueBox.Update` | Forward 2026-08-30, all four modes. FIXED: mode 2's advance also clears ScreenPhase (0x0046CC14). The drawing half is TDialogueBox.Draw, frozen under 0x004568D0. BACKWARD OUTSTANDING. |
| 0x00456698 | `PowerUp_Show` | PARTIAL | `Dialogue.pas TDialogueBox.SubMode` | RE-AUDITED 2026-08-30 in order: effect 0x10, remember-music, playlist 4 unlooped, overlay active and mode 1, the grant chain of INDEPENDENT ifs with two conditional, and Entity_Destroy. The panel sentence is real - the literals at 0x004568B0 and 0x004568BC read '  ' and ' was recovered! '. Two argued differences: the surface is created and loaded per-use in the original and once at startup here, and the three overlay strings are cleared there where FPanelText is simply assigned here. BACKWARD OUTSTANDING |
| 0x004568d0 | `Overlay_Update` | PARTIAL | `Dialogue.pas TDialogueBox.Draw` | RE-AUDITED 2026-08-30. The mode-1 panel and the close path match: the centred line at (0x140 - len*6) >> 1 at y 0xD8, the four colours, and closing on the music stopping - resume, clear, AdvanceStep, in that order. The mode-0 three-line box is NOT reproduced and is UNREACHABLE: xrefs to 0x0046CDA0 show only PowerUp_Show writing it (always 1) and GameState_Reset writing 0, and Overlay_Update runs only while 0x0046CD00 is set, which only PowerUp_Show sets. So mode is always 1 when it runs. BACKWARD OUTSTANDING |
| 0x00456b14 | `UnitInit_00484FA0` | MATCHES | `UnitInit.pas UnitInitialize` | Not game logic: a compiler-emitted Delphi UNIT INITIALIZATION stub, whose entire body is Inc on one counter, with its finalization Dec at +0x30. Identified from the zero-terminated table of (finalization, initialization) pairs ending at 0x00467164, immediately before entry; fifteen of its entries point into the game's range and all fifteen are byte-for-byte the same shape. The counters at 0x00484FA0..0x00484FF0 are WRITE-ONLY - every reference to each is one of those two read-modify-write instructions, so an xref listing shows two reads per counter and nothing consumes them - which is why these have no observable behaviour. --selftest-entities re-derives the whole table out of akuji.exe, so the claim is checked rather than asserted. EXTRAS: one procedure taking an index instead of fifteen near-identical ones, an array instead of fifteen separate globals, and no exception frame - the original's is the compiler's, wraps nothing, and has no effect to reproduce. |
| 0x00456b4c | `Entity_SolidCollideX` | UNVERIFIED |  |  |
| 0x00456e0c | `Entity_SolidCollideY` | UNVERIFIED |  |  |
| 0x00457150 | `Entity_TileEdgeDistX` | UNVERIFIED |  |  |
| 0x00457228 | `Entity_TileEdgeDistY` | UNVERIFIED |  |  |
| 0x00457300 | `Entity_TileCollideX` | UNVERIFIED |  |  |
| 0x004574dc | `Entity_TileCollideY` | UNVERIFIED |  |  |
| 0x004576b4 | `Entity_CheckKillTiles` | UNVERIFIED |  |  |
| 0x00457880 | `Entity_PlayerTouch` | UNVERIFIED |  |  |
| 0x00457ab4 | `Entity_TakeProjectileHits` | UNVERIFIED |  |  |
| 0x00457f98 | `Entity_BoxesOverlap` | UNVERIFIED |  |  |
| 0x004580bc | `Entity_IsOffScreen` | UNVERIFIED |  |  |
| 0x00458138 | `FUN_00458138` | UNVERIFIED |  |  |
| 0x00458274 | `Entity_TouchPickup` | UNVERIFIED |  |  |
| 0x00458404 | `FUN_00458404` | UNVERIFIED |  |  |
| 0x00458490 | `Entity_TouchHeal` | UNVERIFIED |  |  |
| 0x004585a8 | `Player_Update` | UNVERIFIED |  |  |
| 0x004593b0 | `Player_UpdateGlide` | UNVERIFIED |  |  |
| 0x00459624 | `Player_UpdateAirDash` | UNVERIFIED |  |  |
| 0x00459828 | `Player_UpdateKnockback` | FIXED | `Player.pas UpdateKnockback` | Both ways 2026-08-31. FIXED: the music stop at the moment the last life goes - FUN_00450CBC, between the three souls and sound 0x0C - was missing, so the stage track ran on over the death and into the game-over screen. Covered in the trace suite; TFlatWorld.StopMusic had been an empty override, which is why nothing caught it. EXTRAS: an early Exit inverting the landing if; the entity and world passed to ApplyMoveY so the kill check runs, which Camera_ApplyMoveY does unconditionally; named constants. |
| 0x00459a0c | `EntityUpdate_Type2` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x00459c1c | `Camera_ShouldScrollX` | UNVERIFIED |  |  |
| 0x00459cd8 | `Camera_ShouldScrollY` | UNVERIFIED |  |  |
| 0x00459d9c | `Camera_ApplyMoveX` | UNVERIFIED |  |  |
| 0x00459e08 | `Camera_ApplyMoveY` | UNVERIFIED |  |  |
| 0x00459e7c | `UnitInit_00484FBC` | MATCHES | `UnitInit.pas UnitInitialize` | Not game logic: a compiler-emitted Delphi UNIT INITIALIZATION stub, whose entire body is Inc on one counter, with its finalization Dec at +0x30. Identified from the zero-terminated table of (finalization, initialization) pairs ending at 0x00467164, immediately before entry; fifteen of its entries point into the game's range and all fifteen are byte-for-byte the same shape. The counters at 0x00484FA0..0x00484FF0 are WRITE-ONLY - every reference to each is one of those two read-modify-write instructions, so an xref listing shows two reads per counter and nothing consumes them - which is why these have no observable behaviour. --selftest-entities re-derives the whole table out of akuji.exe, so the claim is checked rather than asserted. EXTRAS: one procedure taking an index instead of fifteen near-identical ones, an array instead of fifteen separate globals, and no exception frame - the original's is the compiler's, wraps nothing, and has no effect to reproduce. |
| 0x00459eb4 | `EntityUpdate_Type03` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x00459f1c | `EntityUpdate_Type04` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x00459f6c | `EntityUpdate_Type05` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a020 | `EntityUpdate_Type06` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a08c | `EntityUpdate_Type07` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a0e4 | `EntityUpdate_Type08` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a120 | `EntityUpdate_Type09` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a184 | `EntityUpdate_Type10` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a1c0 | `EntityUpdate_Type11` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a20c | `EntityUpdate_Type12` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a24c | `EntityUpdate_Type13` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a3e0 | `EntityUpdate_Type14` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a43c | `EntityUpdate_Type24` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a4f0 | `EntityUpdate_Type25` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a50c | `EntityUpdate_Type26` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a540 | `EntityUpdate_Type27` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a580 | `EntityUpdate_Type28` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a5d4 | `EntityUpdate_Type32_Emitter` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a698 | `EntityUpdate_Type33_Explosion` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a7bc | `EntityUpdate_Type36_FallingItem` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a848 | `EntityUpdate_Type37` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a944 | `EntityUpdate_Type16` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a95c | `EntityUpdate_Type15` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a9d0 | `EntityUpdate_Type19` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045a9d4 | `EntityUpdate_Type17` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045aa10 | `EntityUpdate_Type21` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045aa60 | `EntityUpdate_Type22` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045aa78 | `EntityUpdate_Type23_Torch` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045ab64 | `EntityUpdate_Type29` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045abd8 | `EntityUpdate_Type30` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045ac94 | `EntityUpdate_Type31` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045af2c | `EntityUpdate_Type34` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045afa8 | `EntityUpdate_Type35` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045b0cc | `EntityUpdate_Type38` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045b260 | `EntityUpdate_Type39` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045b3b4 | `UnitInit_00484FC4` | MATCHES | `UnitInit.pas UnitInitialize` | Not game logic: a compiler-emitted Delphi UNIT INITIALIZATION stub, whose entire body is Inc on one counter, with its finalization Dec at +0x30. Identified from the zero-terminated table of (finalization, initialization) pairs ending at 0x00467164, immediately before entry; fifteen of its entries point into the game's range and all fifteen are byte-for-byte the same shape. The counters at 0x00484FA0..0x00484FF0 are WRITE-ONLY - every reference to each is one of those two read-modify-write instructions, so an xref listing shows two reads per counter and nothing consumes them - which is why these have no observable behaviour. --selftest-entities re-derives the whole table out of akuji.exe, so the claim is checked rather than asserted. EXTRAS: one procedure taking an index instead of fifteen near-identical ones, an array instead of fifteen separate globals, and no exception frame - the original's is the compiler's, wraps nothing, and has no effect to reproduce. |
| 0x0045b3ec | `EntityUpdate_Type40` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045b62c | `EntityUpdate_Type41` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045b7c4 | `EntityUpdate_Type42` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045bbd8 | `EntityUpdate_Type43` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045bc00 | `EntityUpdate_Type44` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045bc8c | `UnitInit_00484FC8` | MATCHES | `UnitInit.pas UnitInitialize` | Not game logic: a compiler-emitted Delphi UNIT INITIALIZATION stub, whose entire body is Inc on one counter, with its finalization Dec at +0x30. Identified from the zero-terminated table of (finalization, initialization) pairs ending at 0x00467164, immediately before entry; fifteen of its entries point into the game's range and all fifteen are byte-for-byte the same shape. The counters at 0x00484FA0..0x00484FF0 are WRITE-ONLY - every reference to each is one of those two read-modify-write instructions, so an xref listing shows two reads per counter and nothing consumes them - which is why these have no observable behaviour. --selftest-entities re-derives the whole table out of akuji.exe, so the claim is checked rather than asserted. EXTRAS: one procedure taking an index instead of fifteen near-identical ones, an array instead of fifteen separate globals, and no exception frame - the original's is the compiler's, wraps nothing, and has no effect to reproduce. |
| 0x0045bcc4 | `EntityUpdate_Type45` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045bd9c | `EntityUpdate_Type46` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045bf58 | `EntityUpdate_Type47` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045c0f4 | `EntityUpdate_Type48` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045c250 | `EntityUpdate_Type49` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045c430 | `EntityUpdate_Type50` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045c608 | `EntityUpdate_Type51` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045c678 | `EntityUpdate_Type52_Boss` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045ca28 | `EntityUpdate_Type53` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045cad8 | `EntityUpdate_Type54_Boss2` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045cc98 | `EntityUpdate_Type55_Fireball` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045ce78 | `EntityUpdate_Type56` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045d00c | `EntityUpdate_Type57_ByVariant` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045d598 | `EntityUpdate_Type58` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045d670 | `EntityUpdate_Type59` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045d7d8 | `EntityUpdate_Type60_Walker` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045da28 | `EntityUpdate_Type61_Fleer` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045dc84 | `EntityUpdate_Type62_Walker` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045ddf4 | `EntityUpdate_Type63` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045e030 | `EntityUpdate_Type64` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045e25c | `EntityUpdate_Type65` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045e4ec | `EntityUpdate_Type66_AnchorAndSatellite` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045e714 | `EntityUpdate_Type67_EggLayer` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045ea40 | `EntityUpdate_Type68` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045eb1c | `EntityUpdate_Type69_Pushable` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045ec4c | `EntityUpdate_Type70` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045ed50 | `UnitInit_00484FD4` | MATCHES | `UnitInit.pas UnitInitialize` | Not game logic: a compiler-emitted Delphi UNIT INITIALIZATION stub, whose entire body is Inc on one counter, with its finalization Dec at +0x30. Identified from the zero-terminated table of (finalization, initialization) pairs ending at 0x00467164, immediately before entry; fifteen of its entries point into the game's range and all fifteen are byte-for-byte the same shape. The counters at 0x00484FA0..0x00484FF0 are WRITE-ONLY - every reference to each is one of those two read-modify-write instructions, so an xref listing shows two reads per counter and nothing consumes them - which is why these have no observable behaviour. --selftest-entities re-derives the whole table out of akuji.exe, so the claim is checked rather than asserted. EXTRAS: one procedure taking an index instead of fifteen near-identical ones, an array instead of fifteen separate globals, and no exception frame - the original's is the compiler's, wraps nothing, and has no effect to reproduce. |
| 0x0045ed88 | `EntityUpdate_Type71` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045efc8 | `EntityUpdate_Type72` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045f218 | `FUN_0045f218` | UNVERIFIED |  |  |
| 0x0045f498 | `EntityUpdate_Type74` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045f668 | `EntityUpdate_Type75` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045f744 | `FUN_0045f744` | UNVERIFIED |  |  |
| 0x0045f824 | `UnitInit_00484FD8` | MATCHES | `UnitInit.pas UnitInitialize` | Not game logic: a compiler-emitted Delphi UNIT INITIALIZATION stub, whose entire body is Inc on one counter, with its finalization Dec at +0x30. Identified from the zero-terminated table of (finalization, initialization) pairs ending at 0x00467164, immediately before entry; fifteen of its entries point into the game's range and all fifteen are byte-for-byte the same shape. The counters at 0x00484FA0..0x00484FF0 are WRITE-ONLY - every reference to each is one of those two read-modify-write instructions, so an xref listing shows two reads per counter and nothing consumes them - which is why these have no observable behaviour. --selftest-entities re-derives the whole table out of akuji.exe, so the claim is checked rather than asserted. EXTRAS: one procedure taking an index instead of fifteen near-identical ones, an array instead of fifteen separate globals, and no exception frame - the original's is the compiler's, wraps nothing, and has no effect to reproduce. |
| 0x0045f85c | `EntityUpdate_Type77` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0046023c | `EntityUpdate_Type78` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x004603b4 | `EntityUpdate_Type79` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x004607e8 | `EntityUpdate_Type80` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x00460884 | `UnitInit_00484FDC` | MATCHES | `UnitInit.pas UnitInitialize` | Not game logic: a compiler-emitted Delphi UNIT INITIALIZATION stub, whose entire body is Inc on one counter, with its finalization Dec at +0x30. Identified from the zero-terminated table of (finalization, initialization) pairs ending at 0x00467164, immediately before entry; fifteen of its entries point into the game's range and all fifteen are byte-for-byte the same shape. The counters at 0x00484FA0..0x00484FF0 are WRITE-ONLY - every reference to each is one of those two read-modify-write instructions, so an xref listing shows two reads per counter and nothing consumes them - which is why these have no observable behaviour. --selftest-entities re-derives the whole table out of akuji.exe, so the claim is checked rather than asserted. EXTRAS: one procedure taking an index instead of fifteen near-identical ones, an array instead of fifteen separate globals, and no exception frame - the original's is the compiler's, wraps nothing, and has no effect to reproduce. |
| 0x004608bc | `Entity_UpdateAll` | UNVERIFIED |  |  |
| 0x004610c4 | `Entity_Spawn` | UNVERIFIED |  |  |
| 0x00461400 | `Entity_Destroy` | UNVERIFIED |  |  |
| 0x004615a8 | `Entity_UpdateDying` | UNVERIFIED |  |  |
| 0x00461738 | `Entity_SteerToPlayer` | UNVERIFIED |  |  |
| 0x004617fc | `Entity_MaybeDropItem` | UNVERIFIED |  |  |
| 0x00461874 | `Entity_SpawnDebris` | UNVERIFIED |  |  |
| 0x00461a0c | `UnitInit_00484FE0` | MATCHES | `UnitInit.pas UnitInitialize` | Not game logic: a compiler-emitted Delphi UNIT INITIALIZATION stub, whose entire body is Inc on one counter, with its finalization Dec at +0x30. Identified from the zero-terminated table of (finalization, initialization) pairs ending at 0x00467164, immediately before entry; fifteen of its entries point into the game's range and all fifteen are byte-for-byte the same shape. The counters at 0x00484FA0..0x00484FF0 are WRITE-ONLY - every reference to each is one of those two read-modify-write instructions, so an xref listing shows two reads per counter and nothing consumes them - which is why these have no observable behaviour. --selftest-entities re-derives the whole table out of akuji.exe, so the claim is checked rather than asserted. EXTRAS: one procedure taking an index instead of fifteen near-identical ones, an array instead of fifteen separate globals, and no exception frame - the original's is the compiler's, wraps nothing, and has no effect to reproduce. |
| 0x00461a44 | `GameOver_Update` | FIXED | `Title.pas TGameOverScreen.Update` | Both ways 2026-08-31. FIXED: FUN_00450FD0 is asked INSIDE phase 2, after phase 1 has started the midi in the same call; MusicPlaying had been a parameter, so a death that stopped the stage track first dismissed the screen in the frame it appeared. EXTRAS: a Boolean Result standing for the two inline draws; Assigned guards on four callbacks; FadeBusy and Confirm as parameters; two named constants. |
| 0x00461ba8 | `HUD_Draw` | PARTIAL | `GmMain.pas TFrm_main.DrawHud` | Forward 2026-08-30, statement by statement; the layout and the tables are documented on DrawHud. BACKWARD OUTSTANDING. |
| 0x00461ee4 | `PauseMenu_Update` | PARTIAL | `Title.pas TPauseMenu.Update` | Forward 2026-08-30 against the raw disassembly. FIXED: every confirm arm jumps to the CANCEL test at 0x00462024 rather than the epilogue, so a confirm falls through - the cursor still moves that frame and a same-frame cancel wins. The drawing half is not covered by this fingerprint. BACKWARD OUTSTANDING. |
| 0x0046214c | `Title_Init` | PARTIAL | `GmMain.pas TFrm_main.TitleInit` | RE-AUDITED 2026-08-30. NINE statements, all accounted: GameState_Reset(0), Load_Stage_Assets(0), Font_Define, midi 0 unlooped, ScreenPhase := 0, TitleSubMode := 0, state := 0x14, the one-off 0x168 ms sleep behind its flag, and the 57-channel volume sweep. Font_Define has no separate call here because LoadStage rebuilds the font whenever it loads a surface set, and stage row 0 carries surface set 0 - not -1 - so the reload does happen. BACKWARD OUTSTANDING |
| 0x00462210 | `Stage_Begin` | FIXED | `GameSession.pas TGameSession.BeginStage` | Forward 2026-08-31: all thirteen statements. EXTRAS: none, after removing four. The terrain configuration, background animator, event load and tilemap wiring are Load_Stage_Assets' - the xrefs give Terrain_Configure and Load_Event_Scripts one caller each and it is not this function - and moved to LoadStageAssets; the pool, sprite and layer-delta clears were redundant with ResetState(1). Discarding the kill tile Terrain_Configure returns is what made water non-lethal. |
| 0x00462330 | `Title_MainMenu` | PARTIAL | `Title.pas TTitleScreen.Update` | Ordering fixed 2026-08-31. Title_MainMenu draws first and reads input second; DispatchPost had it inverted, so CONTINUE - which stores the menu index into the OVERLOADED p_TitleSubMode to carry the choice into state 40 - drew the options screen for one frame, and the menu cursor moved a frame early. Guarded in tools/frame_shape.py. BACKWARD OUTSTANDING for the OPTIONS and OMAKE arms. |
| 0x00462f40 | `Game_StartOrLoad` | PARTIAL | `PlayerState.pas GameStartOrLoad` | Forward 2026-08-30 against the raw disassembly. FIXED: statement 2, ScreenPhase := 0 at 00462F5F, was missing. BACKWARD OUTSTANDING. |
| 0x00463154 | `Opening_Update` | UNVERIFIED |  |  |
| 0x00463624 | `Ending_Update` | UNVERIFIED |  |  |
| 0x00464484 | `Ending_ShowPicture` | UNVERIFIED |  |  |
| 0x004645b0 | `Terrain_Configure` | UNVERIFIED |  |  |
| 0x00464d30 | `TFrm_main_AppIdle` | PARTIAL | `GmMain.pas TFrm_main.AppIdle` | Forward 2026-08-30. FIXED: the screen shake was set and never applied; it now displaces every live sprite by -off and the background scroll by +off. Residual: WaitOn gates a pre-Present component call with no counterpart here, DIV-008. BACKWARD OUTSTANDING. |
| 0x004653c8 | `GameState_Reset` | PARTIAL | `GameSession.pas TGameSession.ResetState` | Both ways 2026-08-31. FIXED: 0x0046D334 was never cleared - it is the script StepIndex, not the save-slot cursor this row used to call it. REMOVED: SavedMenuIndex := 0, which has no counterpart. Outstanding: 0x0046D29C unmodelled, GameState_Reset being its only reference in the whole binary; three layers cleared where this engine has one; two frees of surfaces this build never allocates per use - 0x0046D1F0 the power-up panel, 0x0046CEA4 the ending scratch surface. |
| 0x00465584 | `TFrm_main_DDDD1Init` | UNVERIFIED |  |  |
| 0x00465a1c | `Load_Stage_Assets` | UNVERIFIED |  |  |
| 0x00465b50 | `Load_Event_Scripts` | UNVERIFIED |  |  |
| 0x00465e9c | `Load_Surface_Textures` | UNVERIFIED |  |  |
| 0x004660b8 | `Load_Sprite_Sheets` | UNVERIFIED |  |  |
| 0x00466340 | `Load_Map` | UNVERIFIED |  |  |
| 0x004665c8 | `TFrm_main_FormKeyDown` | PARTIAL | `GmMain.pas TFrm_main.FormKeyDown` | RE-AUDITED 2026-08-30. TWO blocks, both present: VK_ESCAPE quits when already paused and otherwise stashes MenuIndex and GameState then sets 0x82; and Key 'R' with the shift byte compared for EQUALITY against DAT_00466640, which reads 4 in the image - ssCtrl - so Ctrl+Shift+R deliberately does not fire, which `Shift = [ssCtrl]` reproduces. The DIV-002 movement flags are an addition, declared in the ledger. BACKWARD OUTSTANDING |
| 0x00466644 | `TFrm_main_FormDestroy` | UNVERIFIED |  |  |
| 0x00466888 | `Debug_DrawOverlay` | UNVERIFIED |  |  |
| 0x004669f8 | `Load_StageTable` | UNVERIFIED |  |  |
| 0x00466c78 | `Display_SetFullScreen` | UNVERIFIED |  |  |
| 0x00466dfc | `Sounds_LoadAll` | UNVERIFIED |  |  |
| 0x00466e4c | `Input_ConfirmPressed` | MATCHES | `GameState.pas ConfirmPressed` | Both ways 2026-08-31; the reasoning now lives on ConfirmPressed. EXTRAS: the input arrives as a const parameter where the original reads the p_InputState global, and a Boolean where it returns 1 or 0. |
| 0x0046716c | `entry` | UNVERIFIED |  |  |

## 2. The component layer

The third-party DirectX and audio suite, which this project replaces wholesale
rather than skipping - so its behaviour is ours to get right, and the sprite
draw order proved it can be wrong in ways the game layer cannot explain.

**This population is NOT complete.** There is no authority file for it; these
are the addresses our own source cites, which is a lower bound on what we
depend on and not a census of the suite. A component function absent from this
table means nobody has needed it yet, not that it does not exist.

| addr | function | status | implementation | what was compared |
|---|---|---|---|---|
| 0x00448918 | `FUN_00448918` | UNVERIFIED |  |  |
| 0x00449d00 | `TDDDD_Present` | UNVERIFIED |  |  |
| 0x00449e78 | `TDDDD begin frame` | UNVERIFIED |  |  |
| 0x0044cf1c | `FUN_0044CF1C` | UNVERIFIED |  |  |
| 0x0044cf68 | `FUN_0044CF68` | UNVERIFIED |  |  |
| 0x0044d1e0 | `sprite depth sort` | PARTIAL | `SpritePool.pas TSpritePool.DrawOrder` | buckets every VISIBLE sprite by depth (+0x34), walking the pool from the LAST slot down; AppIdle then draws buckets 1..7 ascending, so low depth ends up behind, and bucket 0 is never drawn. BACKWARD OUTSTANDING |
| 0x0044d31c | `draw one depth bucket` | PARTIAL |  | walks a bucket FORWARDS for its stored count, so combined with the backwards fill the LOWEST slot number is drawn last and appears in front. BACKWARD OUTSTANDING |
| 0x0044dae0 | `TileMap_DefineTile` | PARTIAL | `TileMaps.pas TTileMap.DefineTile` | Backward pass 2026-08-31; the reasoning now lives on TTileMap.DefineTile. Writes only the rect of the original's three per-tile writes - the surface is fixed per tilemap and the +0x14 byte is a literal 1 at both call sites. EXTRA: a bounds check the original has not; it masks the id with 0xffff and writes regardless. |
| 0x0044db3c | `FUN_0044DB3C` | UNVERIFIED |  |  |
| 0x0044db5c | `TileMap_Get` | UNVERIFIED |  |  |
| 0x0044dc48 | `fader start` | MATCHES | `DDDDComponent.pas TDDDD.StartFade` | RE-AUDITED BOTH WAYS 2026-08-30 from exports/functions/FUN_0044dc48.c. FORWARD: five statements, same order - level (+8) to 0, mode (+4) to the argument, out (+0xc) to the argument, busy (+0xd) to 1, then the single asymmetry: if mode is 0 AND out is 0 the level is reloaded to 0x78, so a fade IN starts full and runs down while a fade OUT starts at 0 and runs up. FADE_FULL is $78, matching. The original re-reads the two fields it has just stored rather than the parameters, which cannot differ. BACKWARD: the Pascal has five statements and no more. EXTRAS: the fields are named and typed - FadeOut is a Boolean where the original stores a byte, and the guard reads not FadeOut rather than comparing that byte to zero. |
| 0x0044dc70 | `fader tick` | UNVERIFIED |  |  |
| 0x0044de3c | `box frame draw` | UNVERIFIED |  |  |
| 0x0044e1aa | `FUN_0044E1AA` | UNVERIFIED |  |  |
| 0x0044e1b8 | `FUN_0044E1B8` | UNVERIFIED |  |  |
| 0x0044e224 | `FUN_0044E224` | UNVERIFIED |  |  |
| 0x0044e25c | `FUN_0044E25C` | UNVERIFIED |  |  |
| 0x0044e2c0 | `FUN_0044E2C0` | UNVERIFIED |  |  |
| 0x00450cbc | `music stop with fade` | UNVERIFIED |  |  |
| 0x00450edc | `kbgm remember` | UNVERIFIED |  |  |
| 0x00450ef0 | `kbgm resume` | UNVERIFIED |  |  |
| 0x00450f14 | `kbgm play, hard stop` | UNVERIFIED |  |  |
| 0x00450f74 | `kbgm play, fade` | UNVERIFIED |  |  |
| 0x00450fd0 | `kbgm IsPlaying` | UNVERIFIED |  |  |
| 0x00450fd8 | `TDDSD_Play` | UNVERIFIED |  |  |
| 0x00451004 | `FUN_00451004` | UNVERIFIED |  |  |
| 0x00451028 | `FUN_00451028` | UNVERIFIED |  |  |
| 0x0045114c | `FUN_0045114C` | UNVERIFIED |  |  |
| 0x00451164 | `FUN_00451164` | UNVERIFIED |  |  |
| 0x0045117c | `FUN_0045117C` | UNVERIFIED |  |  |
| 0x004511a0 | `FUN_004511A0` | UNVERIFIED |  |  |
| 0x004511ec | `FUN_004511EC` | UNVERIFIED |  |  |
| 0x00451354 | `FUN_00451354` | UNVERIFIED |  |  |
| 0x004513e0 | `FUN_004513E0` | UNVERIFIED |  |  |
| 0x00452543 | `FUN_00452543` | UNVERIFIED |  |  |
| 0x00453bdc | `FUN_00453BDC` | UNVERIFIED |  |  |

## 3. Binary layouts

Records whose field offsets or size must match the original's memory. These rot
silently and expensively: `TPlayerState` once sat a byte short for several
commits and every integer in `save.dat` read a byte early, because the
`Assert` that would have caught it was in an `initialization` section and FPC
compiles assertions out without `-Sa`.

### What confirms a layout

Two independent things, and neither alone is enough:

1. **The size is pinned from OUTSIDE the record** - the stride in
   `base + index * 0x104`, the byte count of a file read, a table entry size.
   Never by adding up our own fields, which proves only that we can add.
2. **Every field offset is witnessed** by at least one reference in the
   disassembly. That is what a `// +0xNNN` on a declaration means; it is a
   claim about evidence, not a note to the reader.

A size check alone cannot do it: `Lives` and `MaxLives` swapped is a record of
exactly the right length that misreads every save.

### What locks it down

- `--selftest-layouts` asserts all four sizes and all 46 witnessed offsets at
  runtime, computed as `PtrUInt(@R.Field) - PtrUInt(@R)`.
- `tools/layout_lock.py` checks that suite is COMPLETE - annotate a field and
  forget the assertion, or assert an offset the declaration no longer claims,
  and the gate fails. Without it the suite is a snapshot, not a lock.
- **Nothing here may be an `Assert`.** This project does not pass `-Sa`, so
  assertions are compiled out. Three size guards were `Assert`s in
  `initialization` sections and had never run once - proved on 2026-08-31 by
  falsifying `SizeOf(TEntity)` to 999 and watching the suite pass. All three
  are ordinary comparisons now, and a falsified one exits 217 rather than 0.

`PARTIAL` still means the record is only partly WITNESSED - a 65-int entity
record is not placed field by field in one sitting. It no longer means
unlocked: every offset the declarations do claim is asserted.

| record | unit | status | what was compared |
|---|---|---|---|
| `TPlayerState` | PlayerState.pas | PARTIAL | the fields Game_StartOrLoad and HUD_Draw touch: Head[4..7] abilities, Progress from +10, SavedStage +0x11A0, SpawnX/Y +0x11A4/+0x11A8, Lives +0x11B4, MaxLives +0x11B8, ElapsedSec +0x11BC, Counter +0x11C4, Weapon +0x11CC, JumpStrength +0x11D0, MusicTrack +0x11D4, TargetIndex +0x11DC, Difficulty +0x11E0. The SIZE is pinned independently: save.dat is exactly 0x11E4 bytes and startup checks it Locked: all 20 witnessed offsets asserted by --selftest-layouts. |
| `TInputState` | GameState.pas | MATCHES | All twelve fields, every one an offset read out of AppIdle, ending at AnyPressed +0x34 - complete, not sampled. Locked by --selftest-layouts. EXTRAS: none - no field here that the original lacks. Note the size is NOT pinned from outside and cannot be: the original keeps this as a global block, not a file image or a strided array element, so only the offsets carry evidence and only the offsets are asserted. |
| `TGameSettings` | GameState.pas | MATCHES | 56 bytes, pinned from outside because data/system.dat is a raw image of the record, and all fourteen witnessed fields placed from DDDD1Init and FormDestroy. Locked by --selftest-layouts; its size guard was a dead Assert until 2026-08-31. EXTRAS: one - Pad33, an explicit padding byte carrying +0x33, which nothing has been seen to touch and which exists only to put InputDevice at +0x34. Unknown1E and Unknown2C are placeholder NAMES for real unidentified bytes, not additions. |
| `TEntity` | Entities.pas | PARTIAL | stride 0x104 and the fields the audited functions touch - EF_SPRITE +0x10, EF_VARIANT +0x18, EF_STATE +0x20, EF_DEPTH, EF_EVENT_ID +0xB8. Not every one of the 65 ints has been placed Locked: SizeOf and the 65-int Raw stride asserted by --selftest-layouts. |
| `TEventRecord` | EventScripts.pas | UNVERIFIED |  |
| `TEntityType` | Entities.pas | UNVERIFIED |  |
| `TLayerInfo` | Entities.pas | UNVERIFIED |  |
| `TQdaEntry` | QdaArchive.pas | UNVERIFIED |  |
| `TWeapon` | Player.pas | UNVERIFIED |  |

## Supporting routines identified while auditing

RTL routines below the component layer, identified because an audited function
called them and the answer mattered. We do not reimplement these - FPC's own
RTL provides them - so they carry no status.

| addr | what it is | how it was settled |
|---|---|---|
| 0x00407D44 | `Trim` | skips bytes < 0x21 from the front, drops them from the back, Copies the middle |

## Audited before this table existed

Recorded in notes/verification.md rather than here, and listed so the gap is
visible: `Player_Update` (3 defects found) and `Entities.pas`'s `Entity_Spawn`,
`Entity_TileEdgeDistX/Y` and `Entity_UpdateDying`. They are not marked frozen
because that audit predates this table and its detail was never written down in
the form these rows use.
