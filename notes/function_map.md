# Function Map — Akuji the Demon

What each recovered function does, and **why we believe it**. Rewritten from
scratch; the previous version was written early, guessed names from the Win32
API each function called, and got several badly wrong.

## How to read this

`notes/game_functions.txt` is the machine-generated list of every game-layer
function and its current Ghidra name. It is the address authority and
`tools/coverage.py` reads it. **This file is the meaning authority** — what the
function does and what the evidence is.

Every entry carries its evidence. The grades are about *how it was established*,
not how confident anyone feels:

| | meaning |
|---|---|
| **read** | the decompiled body was read and the behaviour follows from it |
| **corroborated** | as above, plus something unrelated agrees — an asset name, a data-file invariant, the game's own dialogue |
| **inferred** | from callers, callees or data patterns; the body has not been read |

Anything not listed here is either a bare `FUN_` in the database or a
`EntityUpdate_TypeNN` whose body has not been read yet. There is no `❌` row:
absence is the absence mark.

## The address-range rule still holds, with one correction

| Range | Contents |
|---|---|
| `0x402000`–`0x408fff` | Delphi RTL |
| `0x417000`–`0x425fff` | VCL (`Graphics`, `Controls`) |
| `0x439000`–`0x443fff` | VCL (`Forms`) |
| `0x444000`–`0x454eff` | third-party DirectX/audio components |
| `0x454ef4`+ | **the game** |

`coverage.py` uses `0x455000` as the boundary, which is very slightly wrong:
`Event_Begin` sits at `0x454EF4`, just below it, and is unambiguously game code.
Nothing else is known to fall in the gap, so the tool's count is off by at most
that one function.

---

## Entry and form

| Address | Name | Grade | Notes |
|---|---|---|---|
| `0x46716C` | `entry` | read | the `.dpr` block: `Initialize`, `Title := 'Akuji the Demon'`, `CreateForm`, `Run`. `0x4671AC` is only the `CreateForm` call inside it |
| `0x465584` | `TFrm_main_DDDD1Init` | read | loads settings, opens audio, installs `Application.OnIdle` |
| `0x4665C8` | `TFrm_main_FormKeyDown` | read | Escape while paused **quits**; Ctrl+R soft-resets to the title |
| `0x466644` | `TFrm_main_FormDestroy` | read | **writes `system.dat` back** — it is the settings writer, not just teardown |
| `0x464D30` | `TFrm_main_AppIdle` | read | the frame loop; sets `Done := False` so `TApplication` never waits |

All four handlers are reachable only through the form's RTTI, so they have no
call xrefs and auto-analysis never created them. Two had to be made by hand.

## Game state machine

`p_GameState` at `0x46D06C`, in steps of 10.

| Value | Handler | Grade | Meaning |
|---|---|---|---|
| 10 | `Title_Init` `0x46214C` | read | |
| 20 | `Title_MainMenu` `0x462330` | read | menu, options, gallery |
| 30 | `Stage_Begin` `0x462210` | inferred | entered by event sub-op 0 after a stage load |
| 40 | `Game_StartOrLoad` `0x462F40` | read | reads `save.dat` straight into `p_PlayerState` |
| 60 | — | corroborated | **normal gameplay**. A finished event script returns here |
| 100 | `GameOver_Update` `0x461A44` | corroborated | **game over**: draws surface slot 3 (`gameover.bmp`) and plays MIDI 2 (`midi\gameover`), then waits and returns to the title |
| 130 | `PauseMenu_Update` `0x461EE4` | read | saves the prior state to `0x46CBBC` |
| 140 | `EventScript_Execute` `0x455210` | read | the event-script runner |
| 150 | `FUN_00463624` | inferred | entered by event sub-op 80 (`soulget`) |
| 999 | — | read | quit: nils `OnIdle` |

`Opening_Update` `0x463154` and `TitleMenu_Update` `0x456038` are dispatched
separately on their own flags.

## Asset loading

| Address | Name | Grade | Reads |
|---|---|---|---|
| `0x4669F8` | `Load_StageTable` | read | `data\stage.dat` |
| `0x465A1C` | `Load_Stage_Assets` | read | drives the four below, then `Terrain_Configure` |
| `0x465E9C` | `Load_Surface_Textures` | read | `data\surf%.03d.dat` |
| `0x4660B8` | `Load_Sprite_Sheets` | read | `data\spr%.03d.dat` |
| `0x466340` | `Load_Map` | corroborated | `map\%.03d.map`. Every file is exactly `24 + w*h*2` bytes |
| `0x465B50` | `Load_Event_Scripts` | corroborated | **both** `ev%.03d.dat` and `tk%.03d.dat` |
| `0x4645B0` | `Terrain_Configure` | read | sets the **solid-tile threshold** per terrain, and builds an animated background for terrains 1–4 |

> **Two names here were wrong in the old map.** `0x466340` was
> `Load_Tile_Data` "reads `data\tk\`" — both halves false. `0x4645B0` was
> `Configure_Stage_Params`, which hid that its third argument is the terrain id.

## Event scripts

| Address | Name | Grade | Notes |
|---|---|---|---|
| `0x454EF4` | `Event_Begin` | read | `StringReplace(ParamB, '/', ',')` then `CommaText`; enters state 140 |
| `0x45509C` | `EventScript_AdvanceStep` | read | `StringReplace(step, '.', ',')`; picks **one** alternative by scanning backwards for a set progress flag |
| `0x455210` | `EventScript_Execute` | read | the interpreter — all 15 sub-opcodes |

> **`0x45509C` was `SaveGame_Select_Slot` in the old map.** It has nothing to do
> with save slots. That name survived a long time because it was never checked.

The separators are tier-1: both are one-character `AnsiString` literals read out
of the binary at `0x455098`/`0x45508C` and `0x45520C`/`0x455200`. The
interpreter reads **fixed character positions**, not dash-separated fields,
which is why every number in the data is zero-padded.

## Entities — structure

| Address | Name | Grade | Notes |
|---|---|---|---|
| `0x4608BC` | `Entity_UpdateAll` | read | the dispatcher: switches on `EF_TYPE` into 80 handlers. Walks **256** slots although the pool is 289 |
| `0x4610C4` | `Entity_Spawn` | read | three ranges: slot 0 player, `1..$20` actors, `$21..$120` rest. Copies the type row into the entity |
| `0x461400` | `Entity_Destroy` | corroborated | opcode-5 events set `Progress[StrToInt(Copy(ParamB,1,4))]`, matching the block at offset 10 |
| `0x4615A8` | `Entity_UpdateDying` | corroborated | called from **30 sites**, more than anything else. Class 2's death plays sound 34 = `bom03.wav` |
| `0x4617FC` | `Entity_MaybeDropItem` | read | `Random($100) > $B3` — a 76/256 drop, of which `> $F5` is a rarer variant |
| `0x461874` | `Entity_SpawnDebris` | corroborated | five particles; the impact sound comes from `stage.dat` csv 15 (terrain 3 → `water01`, 4 → `water02`) |
| `0x461738` | `Entity_SteerToPlayer` | read | homes on slot 0 read straight off the array base — this is what proved slot 0 is the player |

## Entities — collision and geometry

| Address | Name | Grade | Notes |
|---|---|---|---|
| `0x457150` | `Entity_TileEdgeDistX` | corroborated | how far it may move; used by the falling-item handler to land flush |
| `0x457228` | `Entity_TileEdgeDistY` | corroborated | exact X/Y mirror — six fields at `+4`, and `LayerInfo +0/+10` vs `+4/+14` |
| `0x457300` | `Entity_TileCollideX` | read | tile index hit moving that far, vs the terrain threshold |
| `0x4574DC` | `Entity_TileCollideY` | read | the mirror; also the tile-lookup argument order swaps |
| `0x457F98` | `Entity_BoxesOverlap` | read | entity-vs-entity AABB, using the `+0xA8/+0xAC` insets |
| `0x4580BC` | `Entity_IsOffScreen` | corroborated | compares against `0x140 × 0xF0` — the DFM's 320×240 |
| `0x457880` | `Entity_PlayerTouch` | read | builds the player's box and this entity's; starts event opcodes 0 and 1 |
| `0x457AB4` | `Entity_TakeProjectileHits` | corroborated | scans slots `1..$20`; plays sound 17 = `hit01.wav` when the target survives. **This is what proved `+0x90` is hit points, not hit-stun** |

**Two different inset pairs**: `+0xA0/+0xA4` for tile collision,
`+0xA8/+0xAC` for entity-vs-entity. Conflating them would be silent and wrong.

## Entities — per-type handlers

`EntityUpdate_TypeNN` for 48 types, created by
`ghidra_scripts/CreateEntityUpdateHandlers.java`. **The name asserts only that
`Entity_UpdateAll` reaches it from the arm for type NN** — nothing about the
body. Those whose bodies have been read carry a suffix:

| Address | Name | Grade | Notes |
|---|---|---|---|
| `0x4585A8` | `Player_Update` | corroborated | type 1. The dash is a double tap in a 30-frame window, and `tk001.dat` says "Press the arrow key twice to perform a Dash move". Every sound matches its name |
| `0x45A5D4` | `EntityUpdate_Type32_Emitter` | read | invisible spawner; config in block A, state in block B |
| `0x45A698` | `EntityUpdate_Type33_Explosion` | corroborated | six particles using **both** direction tables at the same index |
| `0x45A7BC` | `EntityUpdate_Type36_FallingItem` | read | gravity 8 capped at `$200`, then snap-to-edge on landing |

Types 0, 18 and 20 have **no** handler. 18 and 20 are two of the three type-table
rows whose column 0 is `-1` (no sprite object); the third, type 32, updates while
drawing nothing.

## HUD and input

| Address | Name | Grade | Notes |
|---|---|---|---|
| `0x461BA8` | `HUD_Draw` | read | life icons animate on a 4-frame cycle; the counter targets are a 12-entry table |
| `0x466E4C` | `Input_ConfirmPressed` | inferred | named from use, body not read |
| `0x4653C8` | `GameState_Reset` | inferred | called on stage entry and game over |

## Verified RTL helpers

Below the game layer, but needed to read anything. These are established:

| Address | Name |
|---|---|
| `0x4026D8` | `Delphi_GetMem` |
| `0x4026F0` | `Delphi_FreeMem` |
| `0x402DA4` | `Delphi_TObject_Free` |
| `0x406A50` | `Delphi_FillChar` |
| `0x403CF8` | `Delphi_AnsiString_Assign` |
| `0x403E60` | `Delphi_AnsiString_AddRef` |
| `0x407F64` | `Delphi_IntToStr` |
| `0x407FF8` | `Delphi_FileOpen` |
| `0x40805C` | `Delphi_FileRead` |
| `0x402AC4` | `Delphi_Random` — takes the range, returns `0..n-1` |
| `0x451354` | rectangle intersection (component layer) |
| `0x45114C` | sign/compare helper (component layer) |

## Named globals

| Address | Name |
|---|---|
| `0x46D06C` | `p_GameState` |
| `0x46CC58` | `p_InputState` |
| `0x46CEA8` | `p_KeyMap` |
| `0x46D0E8` | `p_Settings` |
| `0x46D1E0` | `p_LastFrameTime` |
| `0x46CB68` | `p_Entities` — the 289-slot pool |
| `0x46D364` | the 81-entry type table |
| `0x46CC44` | **solid-tile threshold**, set per terrain |
| `0x46CEE4` | → `0x468B14`, the direction table (X) |
| `0x46CE34` | → `0x468C14`, the direction table (Y) |
| `0x46CD44` | the weapon table, 16-byte records |
| `0x46D144` | `p_LayerInfo` — `+0x10` tileW, `+0x14` tileH, `+0x18` mapW, `+0x1C` mapH |
| `0x46D344` | `p_Surfaces`, 32 slots |
| `0x46CDEC` | `p_TileMaps`, per layer |

## Lessons this file exists to preserve

1. **Never name a function after the Win32 API it calls.** That produced 19
   "confirmed" names that were all Borland library code, including a whole
   "Game Loop" section that was `TApplication`'s tooltip implementation.
2. **Check the address range first.** A game-sounding name below `0x454EF4` is
   wrong until proven otherwise.
3. **Borland emits frameless functions.** No `55 8B EC`, so Ghidra's Function
   Start Search cannot find them and re-running auto-analysis never will. 48 of
   the entity handlers were invisible this way.
4. **Adjacent fields get conflated.** `EF_TOUCH_KIND` and `EF_CLASS` at `+0xC8`
   and `+0xCC`; the two inset pairs; `$24` meaning hit points on a target and
   damage on a projectile.
5. **A name is a claim.** `Load_Tile_Data`, `SaveGame_Select_Slot` and
   `Configure_Stage_Params` all read plausibly and all were wrong. Each cost
   real time before it was caught.
