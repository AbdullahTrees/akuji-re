# What is verified, and what may be changed

Three tables, because there are three kinds of thing we reimplement and each
has a different population. In all of them the STATUS is the whole answer: it
says what evidence exists, and therefore whether the thing may be edited.

| status | evidence | may I change it? |
|---|---|---|
| `MATCHES` | read line by line against a fresh decompile; no difference found | **No.** Frozen - CLAUDE.md section 3a. Name it, quote the disassembly, ask first |
| `FIXED` | read the same way; a difference was found and corrected | **No.** Frozen, same rule |
| `PARTIAL` | some of it compared, and the row says which | The compared part is frozen; ask before changing it |

**Every FIXED row was downgraded to PARTIAL on 2026-08-30.** `Stage_Begin`
was marked FIXED after four of its thirteen statements had been compared -
the audit had been a hunt for one specific bug, not the line-by-line read
the status claims - and it was still missing its fade, its
`GameState_Reset(form, 1)` and its `ScreenPhase := 0`. The other rows were
audited the same way, so they carry the same doubt. A row earns FIXED back
only after a statement-by-statement pass that says how many statements the
original has and accounts for each one.
| `EMUDIFF` | an entity handler, verified by RUNNING the original's own machine code - 296 cases, 0 disagree | Yes, then re-run `python tools/emudiff.py handler_live` |
| `UNVERIFIED` | none | Yes, freely |

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
| 0x00454790 | `Events_SpawnNearCamera` | PARTIAL | `EventRunner.pas TEventRunner.SpawnNearCamera` | window bounds (-2 < tile < +12 and the two float constants summing to 9.5), both flag tests, the disable-forever branch, spawn kind, the forced extent for type 20, the event back-link at +0xB8, all six ParamA letter branches. One real difference: the camera TILE comes from the tile component's own scroll, not the layer origin - filed as DIV-012 rather than faked in game code |
| 0x00454ef4 | `Event_Begin` | MATCHES | `EventRunner.pas TEventRunner.StartEvent` | RE-AUDITED 2026-08-30. The state-140 re-entry guard, the '/'-to-',' split and CommaText, the Progress[1..4] wipe, StepIndex := -1 (0x0046D334, which AdvanceStep increments before use - it was mislabelled 'the save slot cursor'), EventId, the delay Arg, Cursor := 0, state := 0x8C, ScreenPhase := 0, and the closing AdvanceStep. ONE residual: it also zeroes the message mode 0x0046CF28, which this runner cannot reach - Host is a parameter of Execute, not a field, so clearing it would change StartEvent's signature and every caller. Unobservable: a box exists only during state 140 and this refuses to run then |
| 0x0045509c | `EventScript_AdvanceStep` | MATCHES | `EventRunner.pas TEventRunner.AdvanceStep` | AUDITED 2026-08-30, statement for statement: ScreenPhase := 0 FIRST, then increment the step index, then run off the end to state 0x3C if it passes DynArrayHigh(steps); otherwise Cursor := 0, split the step on '.' into CommaText, and scan the alternatives BACKWARDS - the last one whose progress flag is set wins and is written back, and every one that does not match clears the step, so a step with no matching alternative is left empty and does nothing |
| 0x00455210 | `EventScript_Execute` | UNVERIFIED |  |  |
| 0x00456038 | `MessageBox_Update` | PARTIAL | `Dialogue.pas TDialogueBox.Update` | all four modes. The typewriter did not exist - the page was split into finished lines the moment it was taken; the yes/no prompt read the vertical axis where the original reads AxisX; and neither the \k prompt icon nor the yes/no hand was drawn |
| 0x00456698 | `PowerUp_Show` | MATCHES | `Dialogue.pas TDialogueBox.SubMode` | RE-AUDITED 2026-08-30 in order: effect 0x10, remember-music, playlist 4 unlooped, overlay active and mode 1, the grant chain of INDEPENDENT ifs with two conditional, and Entity_Destroy. The panel sentence is real - the literals at 0x004568B0 and 0x004568BC read '  ' and ' was recovered! '. Two argued differences: the surface is created and loaded per-use in the original and once at startup here, and the three overlay strings are cleared there where FPanelText is simply assigned here |
| 0x004568d0 | `Overlay_Update` | MATCHES | `Dialogue.pas TDialogueBox.Draw` | RE-AUDITED 2026-08-30. The mode-1 panel and the close path match: the centred line at (0x140 - len*6) >> 1 at y 0xD8, the four colours, and closing on the music stopping - resume, clear, AdvanceStep, in that order. The mode-0 three-line box is NOT reproduced and is UNREACHABLE: xrefs to 0x0046CDA0 show only PowerUp_Show writing it (always 1) and GameState_Reset writing 0, and Overlay_Update runs only while 0x0046CD00 is set, which only PowerUp_Show sets. So mode is always 1 when it runs |
| 0x00456b14 | `FUN_00456b14` | UNVERIFIED |  |  |
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
| 0x00459828 | `Player_UpdateKnockback` | UNVERIFIED |  |  |
| 0x00459a0c | `EntityUpdate_Type2` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x00459c1c | `Camera_ShouldScrollX` | UNVERIFIED |  |  |
| 0x00459cd8 | `Camera_ShouldScrollY` | UNVERIFIED |  |  |
| 0x00459d9c | `Camera_ApplyMoveX` | UNVERIFIED |  |  |
| 0x00459e08 | `Camera_ApplyMoveY` | UNVERIFIED |  |  |
| 0x00459e7c | `FUN_00459e7c` | UNVERIFIED |  |  |
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
| 0x0045b3b4 | `FUN_0045b3b4` | UNVERIFIED |  |  |
| 0x0045b3ec | `EntityUpdate_Type40` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045b62c | `EntityUpdate_Type41` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045b7c4 | `EntityUpdate_Type42` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045bbd8 | `EntityUpdate_Type43` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045bc00 | `EntityUpdate_Type44` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045bc8c | `FUN_0045bc8c` | UNVERIFIED |  |  |
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
| 0x0045ed50 | `FUN_0045ed50` | UNVERIFIED |  |  |
| 0x0045ed88 | `EntityUpdate_Type71` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045efc8 | `EntityUpdate_Type72` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045f218 | `FUN_0045f218` | UNVERIFIED |  |  |
| 0x0045f498 | `EntityUpdate_Type74` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045f668 | `EntityUpdate_Type75` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0045f744 | `FUN_0045f744` | UNVERIFIED |  |  |
| 0x0045f824 | `FUN_0045f824` | UNVERIFIED |  |  |
| 0x0045f85c | `EntityUpdate_Type77` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x0046023c | `EntityUpdate_Type78` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x004603b4 | `EntityUpdate_Type79` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x004607e8 | `EntityUpdate_Type80` | EMUDIFF |  | run against the original under Ghidra emulation, 296 cases 0 disagree |
| 0x00460884 | `FUN_00460884` | UNVERIFIED |  |  |
| 0x004608bc | `Entity_UpdateAll` | UNVERIFIED |  |  |
| 0x004610c4 | `Entity_Spawn` | UNVERIFIED |  |  |
| 0x00461400 | `Entity_Destroy` | UNVERIFIED |  |  |
| 0x004615a8 | `Entity_UpdateDying` | UNVERIFIED |  |  |
| 0x00461738 | `Entity_SteerToPlayer` | UNVERIFIED |  |  |
| 0x004617fc | `Entity_MaybeDropItem` | UNVERIFIED |  |  |
| 0x00461874 | `Entity_SpawnDebris` | UNVERIFIED |  |  |
| 0x00461a0c | `FUN_00461a0c` | UNVERIFIED |  |  |
| 0x00461a44 | `GameOver_Update` | MATCHES | `Title.pas TGameOverScreen.Update` | RE-AUDITED statement by statement 2026-08-30. Phase 0: ScreenPhase := 1, fader step 4 - FADE_STEP already is - and StartFade(0, fade-OUT). Phase 1, gated on the fader's +0x0D going clear: GameState_Reset(0), Load_Stage_Assets(0) and Font_Define - all three behind GameOverRestart, which reloads stage 0 and so rebuilds the font - then ScreenPhase := 2, TitleSubMode := 0, state := 100, midi index 2 unlooped, and StartFade the other way. Phase 2: draw surface slot 3 full screen, and leave to state 10 on the music stopping OR a confirm |
| 0x00461ba8 | `HUD_Draw` | PARTIAL | `GmMain.pas TFrm_main.DrawHud` | the '@ ' prefix, the 12-entry goal table at 0x00468EC4, the h:mm:ss split, the 4-step life animation (19 38 57 38), both clamps, and the lit/unlit icon loops. All matched; the one difference was the missing `Trim` around the padded counter format |
| 0x00461ee4 | `PauseMenu_Update` | MATCHES | `Title.pas TPauseMenu.Update` | RE-AUDITED against the raw disassembly 2026-08-30 and the defect fixed. Every confirm arm ends in JMP 0x00462024 - the CANCEL test, not the epilogue at 0x004620C7 - so the confirm now falls through: the cursor still moves on that frame, and a cancel in the same frame wins because it writes the state afterwards. The cancel arm DOES leave, via JMP 0x004620C7 at 0x00462061, because the movement block is its else. Also matching: the ScreenPhase one-shot that zeroes the cursor, the three confirm targets, the 0..2 wrap, and all six strings. The drawing half is TPauseMenu.Draw and is not covered by this row's fingerprint |
| 0x0046214c | `Title_Init` | MATCHES | `GmMain.pas TFrm_main.TitleInit` | RE-AUDITED 2026-08-30. NINE statements, all accounted: GameState_Reset(0), Load_Stage_Assets(0), Font_Define, midi 0 unlooped, ScreenPhase := 0, TitleSubMode := 0, state := 0x14, the one-off 0x168 ms sleep behind its flag, and the 57-channel volume sweep. Font_Define has no separate call here because LoadStage rebuilds the font whenever it loads a surface set, and stage row 0 carries surface set 0 - not -1 - so the reload does happen |
| 0x00462210 | `Stage_Begin` | FIXED | `GameSession.pas TGameSession.BeginStage` | ALL THIRTEEN statements accounted for, 2026-08-30. (1)+(2) fader step 4 - FADE_STEP already is 4 - then StartFade(0, fade-in), via OnStartFade because the component is the form's; (3) GameState_Reset(form, 1); (4) ScreenPhase := 0; (5) GameState := 0x3C; (6) TitleSubMode := 0; (7)(8)(9) Load_Stage_Assets, Font_Define and the box sheet, which are the form's LoadStage and run before this - independent of the reset, which touches only the pool, the layer and the progress block; (10)(11) layer origin = ScrollX/Y * 0x20 + 0x10000; (12) Entity_Spawn(0, 1, SpawnX shl 5, SpawnY shl 5); (13) the spawned entity's +0x88 facing from PlayerState+0x11D8. 1-4 were missing and cost the room-transition fade and every respawning monster |
| 0x00462330 | `Title_MainMenu` | PARTIAL | `Title.pas TTitleScreen.Update` | menu arm and options arm. Two defects: the cursor is read into a temporary BEFORE GameState_Reset zeroes it (ours read it after, so CONTINUE could never record itself), and the options rows play SND_OK / SND_PI per row and re-apply the volume across all 57 channels immediately |
| 0x00462f40 | `Game_StartOrLoad` | MATCHES | `PlayerState.pas GameStartOrLoad` | RE-AUDITED against the raw disassembly 2026-08-30 and the defect fixed. Statement 2 is 00462F5F..00462F66, ScreenPhase := 0, between the opening gate and the 0x1E state write, and it was missing. Also matching: the gate itself (submode 0 AND Opening_Update returning 1 returns early), every default written UNDER the load, the 0x1195-byte progress clear from +10, the two extra-door bytes, Progress[7..9], CurrentStage := 1, the spawn defaults 0x60/0x73/0/0x1C0, the new-game-only fade-play of playlist 1, MusicTrack := 1, the save read of 0x11E4 bytes with SavedStage +0x11A0 into CurrentStage, Progress[0] := 1 with 10/5/6 cleared, and the dead second difficulty write behind !UseArchive |
| 0x00463154 | `Opening_Update` | UNVERIFIED |  |  |
| 0x00463624 | `Ending_Update` | UNVERIFIED |  |  |
| 0x00464484 | `Ending_ShowPicture` | UNVERIFIED |  |  |
| 0x004645b0 | `Terrain_Configure` | UNVERIFIED |  |  |
| 0x00464d30 | `TFrm_main_AppIdle` | PARTIAL | `GmMain.pas TFrm_main.AppIdle` | the whole frame loop. Three differences: the fader is frozen while paused, the loop has its OWN pause entry on button 2 that we had not implemented at all, and AnyPressed (+0x34, three buttons) was declared and never written |
| 0x004653c8 | `GameState_Reset` | FIXED | `GameSession.pas TGameSession.ResetState` | read statement by statement 2026-08-30. Matching: the mode-0 CurrentStage clear, ScreenPhase, TitleSubMode, MenuIndex, the two shake globals, the mode<>2 layer clear, the per-entity ALIVE/EVENT_ID=-1/SPRITE=-1 reset over 256 slots, the event InWindow/Active clear, and the progress scratch wipe - 0x1F5 = 501 bytes from PlayerState+0xFAA, exactly Progress[4000..4500]. ADDED: the interpreter's EventId 0x46CE7C, Arg 0x46D028 and Cursor 0x46D218, and the message box and overlay clears 0x46CC98/0x46CF24/0x46CF28/0x46CD00/0x46CDA0 through OnResetHost. Residual and argued in the body: 0x46D29C and the save cursor 0x46D334 have no counterpart; the original walks THREE layers and zeroes each tile component's scroll, but no shipped stage row uses layers 1 or 2 - all 66 have -1 in csv 3 and 4 - so it is unobservable; the panel surface free has nothing to free because this build loads it once |
| 0x00465584 | `TFrm_main_DDDD1Init` | UNVERIFIED |  |  |
| 0x00465a1c | `Load_Stage_Assets` | UNVERIFIED |  |  |
| 0x00465b50 | `Load_Event_Scripts` | UNVERIFIED |  |  |
| 0x00465e9c | `Load_Surface_Textures` | UNVERIFIED |  |  |
| 0x004660b8 | `Load_Sprite_Sheets` | UNVERIFIED |  |  |
| 0x00466340 | `Load_Map` | UNVERIFIED |  |  |
| 0x004665c8 | `TFrm_main_FormKeyDown` | MATCHES | `GmMain.pas TFrm_main.FormKeyDown` | RE-AUDITED 2026-08-30. TWO blocks, both present: VK_ESCAPE quits when already paused and otherwise stashes MenuIndex and GameState then sets 0x82; and Key 'R' with the shift byte compared for EQUALITY against DAT_00466640, which reads 4 in the image - ssCtrl - so Ctrl+Shift+R deliberately does not fire, which `Shift = [ssCtrl]` reproduces. The DIV-002 movement flags are an addition, declared in the ledger |
| 0x00466644 | `TFrm_main_FormDestroy` | UNVERIFIED |  |  |
| 0x00466888 | `Debug_DrawOverlay` | UNVERIFIED |  |  |
| 0x004669f8 | `Load_StageTable` | UNVERIFIED |  |  |
| 0x00466c78 | `Display_SetFullScreen` | UNVERIFIED |  |  |
| 0x00466dfc | `Sounds_LoadAll` | UNVERIFIED |  |  |
| 0x00466e4c | `Input_ConfirmPressed` | MATCHES | `GameState.pas ConfirmPressed` | RE-AUDITED statement by statement 2026-08-30. ONE statement: (btn0 at +0x1C set AND latch0 at +0x20 clear) OR (btn1 at +0x1D AND latch1 at +0x21). Ours is that expression exactly, including the asymmetry that the pause confirm latches only button 0 |
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
| 0x0044d1e0 | `sprite depth sort` | MATCHES | `SpritePool.pas TSpritePool.DrawOrder` | buckets every VISIBLE sprite by depth (+0x34), walking the pool from the LAST slot down; AppIdle then draws buckets 1..7 ascending, so low depth ends up behind, and bucket 0 is never drawn |
| 0x0044d31c | `draw one depth bucket` | MATCHES |  | walks a bucket FORWARDS for its stored count, so combined with the backwards fill the LOWEST slot number is drawn last and appears in front |
| 0x0044dae0 | `TileMap_DefineTile` | MATCHES |  | argument order is (Self, TileIndex, Surface, Transparent, SrcY, SrcX) - Y BEFORE X - and it pins the object layout: TileW at +0x6028, TileH at +0x602C, so +0x6034/+0x6038 are ScrollX/ScrollY |
| 0x0044db3c | `FUN_0044DB3C` | UNVERIFIED |  |  |
| 0x0044db5c | `TileMap_Get` | UNVERIFIED |  |  |
| 0x0044dc48 | `fader start` | MATCHES | `DDDDComponent.pas TDDDD.StartFade` | writes +4/+0xC/+0xD and sets the level +8 to 0x78 only when BOTH arguments are 0, which is the fade-IN asymmetry StartFade reproduces |
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

`PARTIAL` is honest here rather than aspirational - a 65-int entity record is
not placed field by field in one sitting, and the row says which parts were.

| record | unit | status | what was compared |
|---|---|---|---|
| `TPlayerState` | PlayerState.pas | PARTIAL | the fields Game_StartOrLoad and HUD_Draw touch: Head[4..7] abilities, Progress from +10, SavedStage +0x11A0, SpawnX/Y +0x11A4/+0x11A8, Lives +0x11B4, MaxLives +0x11B8, ElapsedSec +0x11BC, Counter +0x11C4, Weapon +0x11CC, JumpStrength +0x11D0, MusicTrack +0x11D4, TargetIndex +0x11DC, Difficulty +0x11E0. The SIZE is pinned independently: save.dat is exactly 0x11E4 bytes and startup checks it |
| `TInputState` | GameState.pas | MATCHES | every offset read out of AppIdle: AxisX +0, AxisY +4, HeldX/Y +8/+0xC, Moving +0x10, RepeatTimer +0x14, HoldTimer +0x18, buttons +0x1C..0x1F, latches +0x20..0x23, repeats +0x24, AnyPressed +0x34 |
| `TGameSettings` | GameState.pas | MATCHES | 56 bytes, and every field placed from DDDD1Init and FormDestroy: stage +0, level +4, keymap +8..+0x14, the four flag bytes +0x18..+0x1B, volume +0x24, gallery +0x28, unlocks +0x2C..0x32, device +0x34. Round-tripped byte-exact by --selftest-settings |
| `TEntity` | Entities.pas | PARTIAL | stride 0x104 and the fields the audited functions touch - EF_SPRITE +0x10, EF_VARIANT +0x18, EF_STATE +0x20, EF_DEPTH, EF_EVENT_ID +0xB8. Not every one of the 65 ints has been placed |
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

Recorded in CLAUDE.md section 14a rather than here, and listed so the gap is
visible: `Player_Update` (3 defects found) and `Entities.pas`'s `Entity_Spawn`,
`Entity_TileEdgeDistX/Y` and `Entity_UpdateDying`. They are not marked frozen
because that audit predates this table and its detail was never written down in
the form these rows use.
