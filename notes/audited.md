# Every game-layer function, and what is known about it

One row per function, and the STATUS is the whole answer: it says what evidence
exists, and therefore whether the function may be edited.

| status | evidence | may I change it? |
|---|---|---|
| `MATCHES` | read line by line against a fresh decompile; no difference found | **No.** Frozen - CLAUDE.md section 3a. Name it, quote the disassembly, ask first |
| `FIXED` | read the same way; a difference was found and corrected | **No.** Frozen, same rule |
| `EMUDIFF` | an entity handler, verified by RUNNING the original's own machine code under Ghidra's emulator - 296 cases, 0 disagree | Yes, but re-run `python tools/emudiff.py handler_live` afterwards |
| `UNVERIFIED` | none. Nobody has established what it does | Yes, freely |

**UNVERIFIED is not a defect list.** The game is broadly playable, so most of
those are probably fine. They are unproven rather than suspect. The point of
listing them is that when a bug points at one, nobody wastes time assuming it
was already verified.

`EMUDIFF` is not a weaker `MATCHES`. For arithmetic it is the stronger evidence,
because it runs the original instead of reading it. The two answer different
questions, which is why the entity layer and the flow layer are checked
differently.

The population is `notes/game_functions.txt`, the address authority - 149
functions between 0x454790 and 0x4671FF. `tools/audited.py` reads THIS table,
fingerprints every frozen implementation into `notes/audited.lock`, and fails
the gate if one changes. `python tools/audited.py --list` filters by status.

| addr | function | status | implementation | what was compared |
|---|---|---|---|---|
| 0x00454790 | `Events_SpawnNearCamera` | FIXED | `EventRunner.pas TEventRunner.SpawnNearCamera` | window bounds (-2 < tile < +12 and the two float constants summing to 9.5), both flag tests, the disable-forever branch, spawn kind, the forced extent for type 20, the event back-link at +0xB8, all six ParamA letter branches. One real difference: the camera TILE comes from the tile component's own scroll, not the layer origin - filed as DIV-012 rather than faked in game code |
| 0x00454ef4 | `Event_Begin` | FIXED | `EventRunner.pas TEventRunner.StartEvent` | the state-140 re-entry guard, the `/`-to-`,` split, and the Progress[1..4] wipe all matched. Two things were missing: it clears the shared ScreenPhase, without which the message box's \k and \w one-shots see whatever the last screen left; and its second argument is a DELAY stored at 0x0046D028 which 0x00464D30 counts down, re-firing every opcode-4 checker at zero. The runner stored that argument and never counted it, with a field comment naming the address |
| 0x0045509c | `EventScript_AdvanceStep` | UNVERIFIED |  |  |
| 0x00455210 | `EventScript_Execute` | UNVERIFIED |  |  |
| 0x00456038 | `MessageBox_Update` | FIXED | `Dialogue.pas TDialogueBox.Update` | all four modes. The typewriter did not exist - the page was split into finished lines the moment it was taken; the yes/no prompt read the vertical axis where the original reads AxisX; and neither the \k prompt icon nor the yes/no hand was drawn |
| 0x00456698 | `PowerUp_Show` | MATCHES | `Dialogue.pas TDialogueBox.SubMode` | effect 0x10, remember-music then playlist entry 4 unlooped, overlay active + mode 1, and the grant chain - which is a run of INDEPENDENT ifs, two of them conditional (variant 0 only when Weapon is 0, variant 1 unless Weapon is 3), not a case. The panel sentence is real: the two literals at 0x004568B0 and 0x004568BC read `'  '` and `' was recovered! '` in the image |
| 0x004568d0 | `Overlay_Update` | MATCHES | `Dialogue.pas TDialogueBox.Draw` | both modes. The panel's blit and its centred line at `(0x140 - len*6) >> 1, 0xD8`; the box's `0x79` split to `0x88`/`0`, the frame at x 0x30 and three lines at x 0x3C, 16 apart; and all four colours - fill `$FFE6C8` and outline `$735400` for the box, `$FFFFFF` and `$FF0000` for the panel. The close check sits OUTSIDE both modes: when the music stops it resumes the track, clears the overlay and calls EventScript_AdvanceStep, which is what resumes the script. One behaviour-neutral difference: the original frees and reloads the panel surface each time, we load it once |
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
| 0x00461a44 | `GameOver_Update` | FIXED | `Title.pas TGameOverScreen.Update` | all three phases, the midi index, surface slot 3, and leaving on the music ending or a confirm. The phase logic matched; the caller passed a hard-coded False for FadeBusy, so both dissolves were skipped |
| 0x00461ba8 | `HUD_Draw` | FIXED | `GmMain.pas TFrm_main.DrawHud` | the '@ ' prefix, the 12-entry goal table at 0x00468EC4, the h:mm:ss split, the 4-step life animation (19 38 57 38), both clamps, and the lit/unlit icon loops. All matched; the one difference was the missing `Trim` around the padded counter format |
| 0x00461ee4 | `PauseMenu_Update` | MATCHES | `Title.pas TPauseMenu.Update` | the ScreenPhase one-shot that zeroes the cursor on entry, all three confirm targets, the cancel restoring SavedMenuIndex, the 0..2 wrap, and all six strings including the `<         >` cursor and both hint lines with their exact spacing |
| 0x0046214c | `Title_Init` | MATCHES | `GmMain.pas TFrm_main.TitleInit` | GameState_Reset, asset load, Font_Define, midi 0 one-shot, ScreenPhase and TitleSubMode cleared, state to 0x14, the one-off sleep, the 57-channel volume sweep |
| 0x00462210 | `Stage_Begin` | FIXED | `GameSession.pas TGameSession.BeginStage` | layer origin from ScrollX/Y, the player spawn, the fade start (FUN_0044DC48 with 0x78/4 - it is the room fade, not a scroll reset), and the explicit `p_TitleSubMode = 0`, which ours did not do. That omission sent the title screen to its OPTIONS page after a continue |
| 0x00462330 | `Title_MainMenu` | FIXED | `Title.pas TTitleScreen.Update` | menu arm and options arm. Two defects: the cursor is read into a temporary BEFORE GameState_Reset zeroes it (ours read it after, so CONTINUE could never record itself), and the options rows play SND_OK / SND_PI per row and re-apply the volume across all 57 channels immediately |
| 0x00462f40 | `Game_StartOrLoad` | MATCHES | `PlayerState.pas GameStartOrLoad` | statement order, every default written UNDER the load rather than over it, SavedStage at +0x11A0 into Settings.CurrentStage, the new-game-only music call, and the dead second difficulty write behind `!UseArchive` |
| 0x00463154 | `Opening_Update` | UNVERIFIED |  |  |
| 0x00463624 | `Ending_Update` | UNVERIFIED |  |  |
| 0x00464484 | `Ending_ShowPicture` | UNVERIFIED |  |  |
| 0x004645b0 | `Terrain_Configure` | UNVERIFIED |  |  |
| 0x00464d30 | `TFrm_main_AppIdle` | FIXED | `GmMain.pas TFrm_main.AppIdle` | the whole frame loop. Three differences: the fader is frozen while paused, the loop has its OWN pause entry on button 2 that we had not implemented at all, and AnyPressed (+0x34, three buttons) was declared and never written |
| 0x004653c8 | `GameState_Reset` | UNVERIFIED |  |  |
| 0x00465584 | `TFrm_main_DDDD1Init` | UNVERIFIED |  |  |
| 0x00465a1c | `Load_Stage_Assets` | UNVERIFIED |  |  |
| 0x00465b50 | `Load_Event_Scripts` | UNVERIFIED |  |  |
| 0x00465e9c | `Load_Surface_Textures` | UNVERIFIED |  |  |
| 0x004660b8 | `Load_Sprite_Sheets` | UNVERIFIED |  |  |
| 0x00466340 | `Load_Map` | UNVERIFIED |  |  |
| 0x004665c8 | `TFrm_main_FormKeyDown` | MATCHES | `GmMain.pas TFrm_main.FormKeyDown` | VK_ESCAPE quitting when already paused and otherwise stashing and pausing; Ctrl+R to state 10 with an equality test on the shift state |
| 0x00466644 | `TFrm_main_FormDestroy` | UNVERIFIED |  |  |
| 0x00466888 | `Debug_DrawOverlay` | UNVERIFIED |  |  |
| 0x004669f8 | `Load_StageTable` | UNVERIFIED |  |  |
| 0x00466c78 | `Display_SetFullScreen` | UNVERIFIED |  |  |
| 0x00466dfc | `Sounds_LoadAll` | UNVERIFIED |  |  |
| 0x00466e4c | `Input_ConfirmPressed` | MATCHES | `GameState.pas ConfirmPressed` | button 0 unlatched OR button 1 unlatched - exactly our ConfirmPressed, including the asymmetry that only button 0 is latched by the pause menu's confirm |
| 0x0046716c | `entry` | UNVERIFIED |  |  |

## Supporting routines identified while auditing

Not part of the 149 - these are RTL and component routines below 0x454790,
identified because an audited function called them and the answer mattered.

| addr | what it is | how it was settled |
|---|---|---|
| 0x00407D44 | `Trim` | skips bytes < 0x21 from the front, drops them from the back, Copies the middle |
| 0x0044DC48 | the fader's start | writes +4/+0xC/+0xD and sets +8 to 0x78 only when both arguments are 0 - the fade-IN asymmetry `TDDDD.StartFade` reproduces |
| 0x0044DAE0 | `TileMap_DefineTile` | pins the tile component's layout: TileW at +0x6028, TileH at +0x602C, so +0x6034/+0x6038 are its ScrollX/ScrollY |

## Audited before this table existed

Recorded in CLAUDE.md section 14a rather than here, and listed so the gap is
visible: `Player_Update` (3 defects found) and `Entities.pas`'s `Entity_Spawn`,
`Entity_TileEdgeDistX/Y` and `Entity_UpdateDying`. They are not marked frozen
above because that audit predates this table and its detail was never written
down in the form the other rows use.
