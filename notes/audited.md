# Functions checked against the disassembly

One row per function whose Pascal has been read side by side with a fresh
decompile of the original. **This is not the coverage list.**
`tools/implemented.py` says 149/149 functions have executable Pascal; that
question is "does code exist", and this one is "does the code do what the
binary does". Every entry below names what was compared, because "audited" with
no detail is the same kind of claim this file exists to replace.

`--emudiff` already answers this for the 78 entity handlers by running the
original's own machine code: 296 cases, 0 disagree. What it cannot reach is the
FLOW layer - the frame loop, the state machine, the menus and the message box -
because those touch the form, the component suite and the Win32 API. That layer
is what this file tracks, and it is where every bug reported from play has been.

Status values:
  MATCHES  read line by line, no difference found
  FIXED    a difference was found and the Pascal was corrected
  PARTIAL  some arms compared, others not yet - the detail says which

## The flow layer

| addr | function | status | what was compared, and what it cost |
|---|---|---|---|
| 0x00454790 | `Events_SpawnNearCamera` | FIXED | window bounds (-2 < tile < +12 and the two float constants summing to 9.5), both flag tests, the disable-forever branch, spawn kind, the forced extent for type 20, the event back-link at +0xB8, all six ParamA letter branches. One real difference: the camera TILE comes from the tile component's own scroll, not the layer origin - filed as DIV-012 rather than faked in game code |
| 0x00462210 | `Stage_Begin` | FIXED | layer origin from ScrollX/Y, the player spawn, the fade start (FUN_0044DC48 with 0x78/4 - it is the room fade, not a scroll reset), and the explicit `p_TitleSubMode = 0`, which ours did not do. That omission sent the title screen to its OPTIONS page after a continue |
| 0x00462330 | `Title_MainMenu` | FIXED | menu arm and options arm. Two defects: the cursor is read into a temporary BEFORE GameState_Reset zeroes it (ours read it after, so CONTINUE could never record itself), and the options rows play SND_OK / SND_PI per row and re-apply the volume across all 57 channels immediately |
| 0x0046214C | `Title_Init` | MATCHES | GameState_Reset, asset load, Font_Define, midi 0 one-shot, ScreenPhase and TitleSubMode cleared, state to 0x14, the one-off sleep, the 57-channel volume sweep |
| 0x00461EE4 | `PauseMenu_Update` | MATCHES | the ScreenPhase one-shot that zeroes the cursor on entry, all three confirm targets, the cancel restoring SavedMenuIndex, the 0..2 wrap, and all six strings including the `<         >` cursor and both hint lines with their exact spacing |
| 0x004665C8 | `FormKeyDown` | MATCHES | VK_ESCAPE quitting when already paused and otherwise stashing and pausing; Ctrl+R to state 10 with an equality test on the shift state |
| 0x00466E4C | `Input_ConfirmPressed` | MATCHES | `(btn0 && !latch0) || (btn1 && !latch1)` - exactly our ConfirmPressed, including latching only button 0 |
| 0x00464D30 | `AppIdle` | FIXED | the whole frame loop. Three differences: the fader is frozen while paused, the loop has its OWN pause entry on button 2 that we had not implemented at all, and AnyPressed (+0x34, three buttons) was declared and never written |
| 0x00462F40 | `Game_StartOrLoad` | MATCHES | statement order, every default written UNDER the load rather than over it, SavedStage at +0x11A0 into Settings.CurrentStage, the new-game-only music call, and the dead second difficulty write behind `!UseArchive` |
| 0x00456038 | `MessageBox_Update` | FIXED | all four modes. The typewriter did not exist - the page was split into finished lines the moment it was taken; the yes/no prompt read the vertical axis where the original reads AxisX; and neither the \k prompt icon nor the yes/no hand was drawn |
| 0x00461BA8 | `HUD_Draw` | FIXED | the '@ ' prefix, the 12-entry goal table at 0x00468EC4, the h:mm:ss split, the 4-step life animation (19 38 57 38), both clamps, and the lit/unlit icon loops. All matched; the one difference was the missing `Trim` around the padded counter format |
| 0x00461A44 | `GameOver_Update` | FIXED | all three phases, the midi index, surface slot 3, and leaving on the music ending or a confirm. The phase logic matched; the caller passed a hard-coded False for FadeBusy, so both dissolves were skipped |
| 0x004568D0 | `Overlay_Update` | MATCHES | both modes. The panel's blit and its centred line at `(0x140 - len*6) >> 1, 0xD8`; the box's `0x79` split to `0x88`/`0`, the frame at x 0x30 and three lines at x 0x3C, 16 apart; and all four colours - fill `$FFE6C8` and outline `$735400` for the box, `$FFFFFF` and `$FF0000` for the panel. The close check sits OUTSIDE both modes: when the music stops it resumes the track, clears the overlay and calls EventScript_AdvanceStep, which is what resumes the script. One behaviour-neutral difference: the original frees and reloads the panel surface each time, we load it once |
| 0x00456698 | `PowerUp_Show` | MATCHES | effect 0x10, remember-music then playlist entry 4 unlooped, overlay active + mode 1, and the grant chain - which is a run of INDEPENDENT ifs, two of them conditional (variant 0 only when Weapon is 0, variant 1 unless Weapon is 3), not a case. The panel sentence is real: the two literals at 0x004568B0 and 0x004568BC read `'  '` and `' was recovered! '` in the image |
| 0x00454EF4 | `Event_Begin` | FIXED | the state-140 re-entry guard, the `/`-to-`,` split, and the Progress[1..4] wipe all matched. Two things were missing: it clears the shared ScreenPhase, without which the message box's \k and \w one-shots see whatever the last screen left; and its second argument is a DELAY stored at 0x0046D028 which 0x00464D30 counts down, re-firing every opcode-4 checker at zero. The runner stored that argument and never counted it, with a field comment naming the address |

## Supporting routines identified while auditing

| addr | what it is | how it was settled |
|---|---|---|
| 0x00407D44 | `Trim` | skips bytes < 0x21 from the front, drops them from the back, Copies the middle |
| 0x0044DC48 | the fader's start | writes +4/+0xC/+0xD and sets +8 to 0x78 only when both arguments are 0 - which is the fade-IN asymmetry TDDDD.StartFade reproduces |
| 0x0044DAE0 | `TileMap_DefineTile` | pins the tile component's layout: TileW at +0x6028, TileH at +0x602C, so +0x6034/+0x6038 are its ScrollX/ScrollY |

## Frozen implementations

Every row above is FROZEN - see CLAUDE.md section 3a. `tools/audited.py`
fingerprints the Pascal named here, with comments stripped and whitespace
normalised, so a changed statement fails the gate while prose and layout stay
free. A deliberate, user-approved change is blessed with
`python tools/audited.py --bless`.

Some originals share one Pascal routine (the message box and the overlay are
one class here) and some audited entries are RTL or component routines with no
counterpart to freeze; both are expected.

    0x00454790  EventRunner.pas   TEventRunner.SpawnNearCamera
    0x00462210  GameSession.pas   TGameSession.BeginStage
    0x00462330  Title.pas         TTitleScreen.Update
    0x0046214C  GmMain.pas        TFrm_main.TitleInit
    0x00461EE4  Title.pas         TPauseMenu.Update
    0x004665C8  GmMain.pas        TFrm_main.FormKeyDown
    0x00466E4C  GameState.pas     ConfirmPressed
    0x00464D30  GmMain.pas        TFrm_main.AppIdle
    0x00462F40  PlayerState.pas   GameStartOrLoad
    0x00456038  Dialogue.pas      TDialogueBox.Update
    0x00461BA8  GmMain.pas        TFrm_main.DrawHud
    0x00461A44  Title.pas         TGameOverScreen.Update
    0x004568D0  Dialogue.pas      TDialogueBox.Draw
    0x00456698  Dialogue.pas      TDialogueBox.SubMode
    0x00454EF4  EventRunner.pas   TEventRunner.StartEvent

## The other 134

The three states are not a ranking, and the middle one is not a weaker version
of the first:

| state | count | what it means |
|---|---|---|
| FROZEN | 15 | read line by line against a fresh decompile, and locked - CLAUDE.md section 3a |
| EMUDIFF | 75 | an entity handler, verified by RUNNING the original's own machine code under Ghidra's emulator and diffing the result: 296 cases, 0 disagree. Machine-checked rather than read, which for arithmetic is the stronger evidence |
| UNCHECKED | 59 | neither. Free to change, and nobody has established what they do |

`python tools/audited.py --list` prints the unchecked ones (or `--frozen` /
`--emudiff`). The list is DERIVED from `notes/game_functions.txt`, the address
authority, so it cannot drift the way a hand-written "what is left" section
does - this file carried one, and it named eight functions when the real
number was fifty-nine.

**UNCHECKED is not a defect list.** The game is broadly playable, so most of
those 59 are probably fine. They are unproven rather than suspect, and the
point of tracking them is that when a bug points at one, nobody wastes time
assuming it was already verified - and nobody needs approval to change it.

## Audited before this file existed

Recorded in CLAUDE.md section 14a rather than here, and listed so the gap is
visible: `Player_Update` (3 defects found) and `Entities.pas`'s
`Entity_Spawn`, `Entity_TileEdgeDistX/Y` and `Entity_UpdateDying`.
