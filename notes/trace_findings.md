# What running the game said

From a 20,304-frame session captured with `tools/make_trace.py`'s Frida script:
new game, the full opening unskipped, five rooms, three orbs, an enemy killed,
a save, a library book, pause, and a normal exit.

Everything below is from the running program. Where it agrees with the
reconstruction that is worth as much as where it disagrees — several of these
were guesses that had never been checked against anything.

## The state machine, confirmed and completed

| state | frames | what runs in it |
|---|---|---|
| 10 | 1 | `Title_Init`, all the loaders, `GameState_Reset` |
| 20 | 910 | `Title_MainMenu`, `Entity_UpdateAll` |
| 30 | 1 | `Stage_Begin`, `GameState_Reset` |
| 40 | 4726 | `Game_StartOrLoad`, `Opening_Update` |
| 60 | 12347 | play: touch, spawn, destroy, events, and the room loads |
| 130 | 105 | `PauseMenu_Update` |
| 140 | 2213 | `EventScript_Execute`, `MessageBox_Update`, `Overlay_Update`, `PowerUp_Show` |
| 999 | 1 | `TFrm_main_FormDestroy` |

Every constant in `GameState.pas` is confirmed. Two things it could not have
said:

**State 140 is the event-script state.** `EventScript_Execute`,
`EventScript_AdvanceStep`, `MessageBox_Update`, `Overlay_Update` and
`PowerUp_Show` run in 140 and in no other state. It was recorded as
"FUN_00454790, FUN_00455210, HUD_Draw" — the right functions, without the
meaning.

**`Entity_PlayerTouch` runs in state 60 and nowhere else.** 68,336 calls, all
in play. So touch detection is off for the whole of a conversation, which is
why an enemy cannot hurt you mid-dialogue. Nothing in the disassembly says that
locally; it falls out of where the call sits.

**Room changes go through state 30 within a single frame.** `Stage_Begin` is
always sampled at state 30, but only ONE frame ever *begins* in 30. So a room
transition sets 30, runs `Stage_Begin`, and is back at 60 before the frame
ends — which is why the frame-marker count and the call count disagree, and
why it looked at first like rooms loaded inline from state 60.

## The frame loop: `Entity_UpdateAll` is NOT in the state dispatch

    Entity_UpdateAll   20304 calls / 20304 frames

Exactly once per frame, every frame, in every state — including the title menu
and including all 105 frames of pause. It is called unconditionally from
`AppIdle` and gated *internally* by the state argument, which is why every
handler carries its own `if AGameState <> GS_PLAY then Exit`.

The reconstruction calls it from inside `DispatchState`, only in the play and
event arms, and not at all during pause. That is a structural divergence and a
real one.

The arithmetic corroborates:

    Player_Update      14667
    20304 - 14667  =    5637
    title 910 + opening 4726 + 1  =  5637

`Player_Update` is not a separate call at all — it is `Entity_UpdateAll`'s arm
for type 1, so it runs exactly when a player entity exists, which is every
frame after the first stage loads and none before.

## The opening, confirmed frame by frame

    slide 1..7    480 frames each     8 seconds
    slide 8       120 frames          2 seconds
    slide 9       480 frames          8 seconds
    slide 10      765 frames          NOT its timer

Every number in `Opening.pas`'s `OPENING_SECONDS` is right, including the short
slide 8. Slide 10 held 765 frames against a table entry of 8 seconds, which is
the reconstruction's other claim about it: past slide 10 the timer stops being
decremented and what advances it is `midi\open02` finishing.

`Game_StartOrLoad` and `Opening_Update` both show 4726 calls — identical, which
confirms the opening is driven from `Game_StartOrLoad` and is not a state
handler.

## Smaller confirmations

* `PowerUp_Show` ran 3 times for 3 orbs collected — dash, fire, hi-jump.
* The narration on screen is `OPENING_LINES[0..1]` verbatim.
* The library books are 7, which is `GALLERY_COUNT` in `Ending.pas`, reached
  through `Progress[1186..1192]`.

## Still open

The session never reached the ending, so `ScreenPhase` 1 — the phase
`Ending.pas` records as a hole nothing leaves — is still unobserved. It needs a
run that finishes the game, or one that reaches the ending some other way.
