# Ending_Update @ 0x00463624 - the six phases, and where phase 1 hides

## The bug this was written after

After the last orb the reconstruction reached `GS_ENDING` and froze. `Ending.pas`
said *"Phase 1 is a HOLE - nothing in the original leaves it"*, and that was
wrong: the function tests its phase in the order **0, 2, 3, 4, 5, else**, so
**phase 1 is the unlabelled `else` at the bottom** - and it is the whole slide
show. Reading the function top to bottom, phase 1 genuinely looks unreachable.

A second consequence: `GS_ENDING` was calling `DrawScene`, so the HUD and mana
counter were painted over a stage that no longer existed.

## The phases

| phase | what it is |
|---|---|
| 0 | arm: stop the music, zero the slide and timer, go to 1 |
| **1** | **the slide show** - the `else` arm at the bottom |
| 2 | the scrolling credits: `Credits_Create`, seventeen `Surface_AppendEntry` regions, midi 14, `Credits_Tick` until the object's +0x32C done flag |
| 3 | four stills, one a second, each a wider crop of the same sprite |
| 4 | hold the last still 600 frames, fade the music, wait for it to stop |
| 5 | the results screen, and the only place persistent unlocks are written |

Only phases 0, 1 and the phase-5 arithmetic are reconstructed. Phases 2, 3 and
4 are presentation over the DirectDraw component this project replaces.

## Phase 1, the slide show

Six slides. `Slide` is 1-based, so every table is indexed `Slide * 4 - 4`.

| slide | image | secs | text |
|---|---|---|---|
| 1 | ed001 | 8 | `    Light covered Akuji as` / `    he broke the last seal... ` |
| 2 | ed002 | 8 | ` He's transforming back!` |
| 3 | ed003 | 2 | `What's going on?!?` |
| 4 | ed003 | 8 \* | `His horns are all that grew..!` |
| 5 | *none* | 4 | `  Akuji learned a lesson. ` |
| 6 | ed004 | 8 \* | `Disgusted, he decides to  ` / `not cause mischief anymore. ` |

\* Slides 4 and 6 never count down - the decrement is skipped for exactly those
two - and end when their own track does. That is why they are started
**unlooped** where slide 1's is looped. Midi 10 at slide 1, `Kbgm_StopOrFade` at
slide 3, midi 12 at slide 4, midi 13 at slide 6.

An image id of -1 means the slide is text only: the panel surface is freed and
no new one created, so slide 5 shows its words over whatever the fade left.

Past slide 6 it pins `Slide` at 6, parks **999** in the timer as a "waiting on a
fade" sentinel rather than a count, and fades out. The `timer == 999` branch at
the TOP of the else-arm then frees the panel, stops the music and moves to
phase 2.

## The tables

All four are reached through pointer cells, like everything else in this binary.

| cell | table | size |
|---|---|---|
| `0046D018` | `00468FDC` → `EndingImageIds` | 6 ints |
| `0046D038` | `00468FF4` → `EndingTextIds` | 6 ints, indexes `EndingTexts` |
| `0046D260` | `0046900C` → `EndingSlideSeconds` | 6 ints, ×0x3C for frames |
| `0046CEDC` | `00469024` → `EndingTexts` | 12 string pointers |

**Both extents are pinned from outside the table**, which is the rule
`tools/table_bounds.py` exists to enforce:

* `EndingSlideSeconds`' seventh int reads as a string pointer, not a duration.
* `EndingTexts`' twelfth entry is `'EASY'` at `0x00452308` - the level names
  `Title_MainMenu` draws, which `Title.pas` already recorded independently.

## Drawing

Picture at `(0x28, 8)` at `0xF0 x 0xB4` (240x180). Two rows of
`Game_DrawTextOutlined` at x `0x38`, y `200` and `0xD8`, filled with
`Game_RGB(0xFF, 0xDF, 0xA3)` over an outline of `Game_RGB(0x7E, 0x5B, 0x35)`.

## One read past a table

`Slide` is incremented to 7 and `EndingSlideSeconds[6]` is loaded and multiplied
by 0x3C *before* the `> 6` test overwrites the result with the sentinel, so the
overrun value is never used. DIV-011's class; guarded here rather than
reproduced.
