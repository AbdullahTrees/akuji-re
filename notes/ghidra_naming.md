# Feeding the reconstruction back into Ghidra

The decompilation produced the Pascal; the Pascal then explained things the
decompilation never knew. This file records that being pushed back, so the
Ghidra project matures instead of staying at the state it was first read in.

Everything here was applied through the Ghidra MCP against
`ghidra/Akuji_AIdecompAttempt`. **Ghidra must be saved** (File > Save) for any
of it to survive; the MCP edits the open project, it does not commit it.

## THE NAMES ARE NOW CIRCULAR EVIDENCE. Read this first.

The goal is a decompilation that says what the BINARY does. These names came
from the Pascal, so where the Pascal was wrong the decompilation is now wrong
in the same direction - and worse, it looks corroborated.

**Ghidra agreeing with src/*.pas proves nothing about either.** It agrees
because the agreement was typed in on 2026-08-31. Anything that cites a field
or function name here as evidence for the reconstruction is arguing in a
circle. Only the disassembly, the raw bytes and a differential test are
evidence.

This is not theoretical. 0x0046D334 was recorded as "the save slot cursor" for
a long time before it was proved to be the script step index - if this pass had
run a week earlier, Ghidra would now assert p_SaveSlotCursor and the mistake
would have looked confirmed by two independent projects.

Names carry different weights, and it is worth knowing which is which:

- **Read off behaviour, safe.** Compare (returns -1/0/+1 on its two arguments),
  Angle_Between (the 64-step atan2), Delphi_StrLen, Game_RGB (r|g<<8|b<<16),
  Surface_AppendEntry (appends a 6-dword entry and bumps a count),
  SpritePool_DrawBucket, Delphi_MakeRect. These were confirmed by reading the
  function, not by matching a name.
- **Confirmed by a bug or an audit, safe.** p_EventStepIndex, p_ScreenPhase,
  p_KillTile, p_Fader, Kbgm_IsPlaying - each was established while fixing
  something that turned on getting it right.
- **Imported from the Pascal on trust, UNVERIFIED.** Most TEntity field names.
  They came from the EF_/PF_ constants, which were themselves read out of the
  disassembly when the reconstruction was built - so they are not invented, but
  no one re-checked them during this pass. The compound names (BlockA_State,
  ChildA_AirVx, Ridden_Landed) are the weakest: they exist because the entity
  and player constant sets disagree about that slot, and the name asserts both
  meanings hold always, which for a union-like field is not obviously true.
- **Honest gaps.** Field64, Field68, Field6C, FieldBC, FieldC0, FieldC4,
  FieldD8 - offsets our constants never named, left as offsets.

If a field name is load-bearing for a decision, re-derive it from the
disassembly before trusting it.

## Conventions

| kind | convention | example |
|---|---|---|
| pointer cell | `p_Name` - a global whose VALUE is the address of the thing | `p_ScreenPhase`, `p_EntityPool` |
| direct global | bare name, no prefix | `PushX`, `KillTile`, `SolidThreshold` |
| entity parameter | `E`, typed `int *` so `E[0x1f]` indexes the record in ints | `Camera_ApplyMoveY(int * E, ...)` |
| other parameters | the name our Pascal gives the same argument | `Delta`, `Scrolling`, `SkipSoft` |
| locals | the Pascal local's name where the roles line up | `Dx`, `Dy`, `Base`, `Step` |

`p_` for pointer cells is not decoration. The original reaches most of its
state through a pointer held in a fixed cell, so `p_LayerInfo` is the CELL and
`*(int *)(p_LayerInfo + 4)` is the field - naming the cell after the field it
points at would make every dereference read like a double indirection.

## Globals renamed

Verified against the disassembly in the sessions that fixed the corresponding
bugs, not guessed:

    0046cc14  p_ScreenPhase      the shared sub-phase - pause, game-over,
                                 opening and message box all step through it
    0046cb68  p_EntityPool       base of `slot * 0x104`
    0046cb6c  p_Fader            +0x0D is FadeBusy, +0x10 the step
    0046cc44  p_SolidThreshold   what a tile probe is compared against
    0046cf5c  p_KillTile         the tile index that kills on contact
    0046ce48  p_OnTopOfSolid     byte flag, set by the solid scan
    0046cd64  p_PushX            moving-solid displacement
    0046ccc8  p_PushY
    0046ce7c  p_EventId          the interpreter's four, cleared together by
    0046d028  p_EventArg         GameState_Reset
    0046d218  p_EventCursor
    0046d334  p_EventStepIndex   NOT a save-slot cursor - see audited.md
    0046d24c  p_EventSteps       the steps array it indexes
    0046d2c0  p_SavedMenuIndex
    0046cee4  p_DirX             facing tables, indexed by facing
    0046ce34  p_DirY
    0046cd44  p_WeaponTable      16-byte records, indexed by weapon
    00484fac  PushX              the variables themselves, not the cells
    00484fb0  PushY
    00484fb4  OnTopOfSolid
    00484ef4  SolidThreshold
    00484ef8  KillTile
    0046d154  p_MidiNames        the playlist; +8 is index 2, gameover
    0046d1f0  p_PanelSurface     the power-up panel picture
    0046d35c  p_SpriteList       the 256-entry TList GameState_Reset walks
    0046d314  p_ScreenShakeOn    byte
    0046ced0  p_ScreenShakeTimer
    0046cc98  p_MessagePageStart the message box's five, all cleared together
    0046cf24  p_MessageReveal    by GameState_Reset
    0046cf28  p_MessageMode
    0046cd00  p_OverlayActive
    0046cda0  p_OverlayMode
    0046cba4  p_RevealTimer
    0046d320  p_LifeIcon           +0 x, +4 frame, +8 timer
    0046d098  p_LifeIconX          the four x values 19, 38, 57, 38
    0046d2b4  p_StageGoalTable     12 entries, indexed by TargetIndex +0x11DC
    0046d094  p_OpeningSlideSeconds  per-slide duration, x0x3C for frames
    0046ce88  p_OpeningTextIds     indexes into p_TextTable

## Functions renamed

    00456b14 .. 00461a0c   UnitInit_<counter>   the eight Delphi unit
                           initialization stubs Ghidra had defined, which is
                           exactly the eight that reached the backlog. See
                           UnitInit.pas.
    0045114c  Compare              returns 0, -1 if B < A, +1 if A < B
    00402ac4  Delphi_Random
    0044d31c  SpritePool_DrawBucket
    00450cbc  Kbgm_StopOrFade      the six music wrappers. Kbgm_IsPlaying is
    00450f14  Kbgm_Play            the one the game-over screen waits on, and
    00450f74  Kbgm_FadePlay        it tail-calls a KBGMGetInfo predicate
    00450fd0  Kbgm_IsPlaying
    00450edc  Kbgm_RememberCurrent the power-up panel's save/restore pair
    00450ef0  Kbgm_ResumeRemembered
    0044dc48  Fader_StartFade
    00407d44  Delphi_Trim          the RTL helpers that appear everywhere;
    00408a30  Delphi_Format        Trim and Format are named in the HUD_Draw
    0040e9dc  Delphi_MakeRect      audit, MakeRect builds every draw rect
    00406aa8  Game_RGB             r, g, b -> TColor, which is BGR. Dialogue.pas
                                   documents it off the DrawTextOutlined sites

## Prototypes set

Parameter names come from the Pascal that reproduces the function. Arity was
read from the DEFINITION or a call site every time, never assumed:

    Angle_Between(X1, Y1, X2, Y2)          Compare(A, B)
    ApproachZero(V, Step)                  Rect_Overlap(A, B, ShrinkX, ShrinkY)
    Entity_IsOffScreen(E, Margin)          Camera_ShouldScrollX/Y(E)
    Camera_ApplyMoveX/Y(E, Scroll, Blocked)
    Entity_CheckKillTiles(E, LayerIndex)
    Entity_TileCollideX/Y(E, LayerIndex, Delta, DeltaY, Scrolling)
    Entity_SolidCollideX/Y(E, Slot, Delta, SkipSoft, AgainstPlayer)
    Entity_TileEdgeDistX/Y(E, Delta)       Entity_Spawn(Kind, TypeId, X, Y)
    Entity_Destroy(E, DropLoot)            Entity_SpawnDebris(E, Kind)
    Entity_MaybeDropItem(E)                EntityUpdate_Type09/25(E)
    Player_Update(E)                       Player_UpdateGlide/AirDash/Knockback(E)
    GameState_Reset(Form, Mode)            Event_Begin(EventId, Arg)
    Game_DrawText(FontIndex, X, Y, Centred, Variant, Text)
    TDDSD_PlaySound(Device, SoundId, Restart)
    Terrain_Configure(TileMap, Surface, TerrainId)
    Load_Stage_Assets(Form, StageRow)      Load_Surface_Textures(Form, SetIndex)
    Load_Sprite_Sheets(Form, SetIndex)     SpritePool_DrawBucket(Pool, Depth)
    Delphi_Random(N)                       Fader_StartFade(Fader, Mode, FadeOut)
    Kbgm_StopOrFade(Device, FadeSeconds)   Kbgm_Play/FadePlay(Device, Name, Loop)

## Locals named

    Angle_Between            Dx, Dy, Base, Step, I
    Rect_Overlap             BoxA, BoxB, Overlaps
    Entity_IsOffScreen       PixelX, PixelY, Off
    Camera_ShouldScrollY     PixelY, LayerPixelY
    Camera_ApplyMoveX/Y      OriginBefore, OriginAfter
    Entity_CheckKillTiles    Row, RowsLeft, Tile
    GameOver_Update          Rect, MusicPlaying, Confirm
    EventScript_AdvanceStep  FlagIndex, Alternatives, StepText, FlagText,
                             Chosen, Part, Index
    HUD_Draw                 Goal, CounterText, CounterTrimmed, CounterLine,
                             Hours, Minutes, Seconds, TimeText
    Opening_Update           Rect, BmpPath, QdaName, SlideImageId,
                             StillRunning, MusicPlaying
    Events_SpawnNearCamera   CamTileX, CamTileY - which is DIV-012 made
                             visible: the camera tile comes from the TILE
                             COMPONENT's scroll, not the layer origin

HUD_Draw's local_1c is deliberately unnamed: it is the counter for the
'%3d/%-3d' format AND the rect for every sprite draw afterwards. Same storage,
two jobs, so any name is wrong half the time.

## The 74 entity handlers

Every `EntityUpdate_TypeNN` takes exactly one argument and it is the entity.
All 74 single-argument handlers are now `(int * E)`, with the four that return
a value (Type16, 25, 34, 37) keeping `int`. Type17 and Type19 take none.

Entity_CheckKillTiles reuses its scratch ints - iVar3 is both the bottom row
and the column cursor - so only the three unambiguous ones were named. A wrong
name inside a loop is worse than iVar3.

`Entity_SolidCollideX/Y` takes the entity AND a slot, and the body works off
the SLOT - the entity argument is unused. Named `E` anyway, because that is
what every caller passes.

## Self, and what is NOT a method

This is Object Pascal, so a method's first parameter is `Self` in EAX and the
declared parameters start at EDX. Where that is what is happening, the
parameter is named `Self`: `TDDSD_PlaySound`, `Kbgm_Play`, `Kbgm_FadePlay`,
`Kbgm_StopOrFade`, `Fader_StartFade`, `GameState_Reset`, `Load_Stage_Assets`,
`Load_Surface_Textures`, `Load_Sprite_Sheets`, `SpritePool_DrawBucket`. Their
callers pass an instance out of a form field - `*(int *)(*(int *)MainForm +
0x2dc)` is the TDDSD - so `TDDSD_PlaySound(Self, SoundId, Restart)` is really
a two-argument method, and naming the first `Device` hid that.

**The entity handlers are NOT methods**, and it is worth writing down why,
because they look like they should be:

- NONE of the 76 `EntityUpdate_Type*` functions dispatch through a vtable on
  their argument. Not one.
- the argument is indexed at +0x14, +0x18, +0x1c, +0x20, +0x24, +0x48, +0x4c,
  +0x78, +0x7c, +0x88 - the TEntity field offsets, not an object's.
- callers pass `p_EntityPool + slot * 0x104`, an address INSIDE a flat record
  array. An array of objects would be an array of pointers.

So `TEntity` is a record and these are plain procedures over it. Their
parameter is `E`, typed `int *`, which makes the decompiler index it the way
our own constants do: `E[8]` IS `EF_STATE = $08`, `E[5]` is `EF_ANIM_ID`,
`E[0x1e]` is `EF_POS_X`. The two projects now read the same.

## One local can be several source variables

Player_Update's `Scratch` is the clearest case. Ghidra shows ONE slot; our
Pascal declares four locals there - SavedVX, Slot, Frames, W - and the compiler
merged them. Over the function that slot holds the saved VelX, then spawn slots
from Entity_Spawn, then tile-collide results, then p_DirX[Facing], then the
weapon index.

It was briefly named `SavedVX`, which is right for the first use and a false
claim about the other five. Renamed `Scratch`, with a decompiler comment at
0x004585A8 listing what it carries and where. **When a local is reused across
roles, name it neutrally and comment it** - a confident wrong name in five
places is worse than an honest vague one.

`Blocked` in the same function is packed rather than reused: bit 0 is the X
result and bit 8 the Y, which is why it reads back as `Blocked._1_1_`.

## Typing a generic function: TList_Get

The awkward case. `TList.Get` is a VCL method returning an untyped pointer, so
typing its return `TSprite *` looks like it asserts something false about a
generic container - and it would, if the assertion were about TList.

It is not. Every call site in the binary passes `p_SpriteList`: 20 of 20
across the whole export, and the two that look different are GameState_Reset
hoisting the same pointer into a local. So the type is a statement about how
THIS PROGRAM uses the function, which is exactly what a decompilation should
record.

Two things make that honest rather than convenient:

- it was **measured** before being applied, not assumed from the one function
  that happened to be open;
- a decompiler comment on the function says what the type rests on, so the
  next person can see it is wrong the moment a second list appears.

The alternative - typing the local at each call site - fails here anyway,
because Ghidra merges those locals with unrelated uses in the same function.

## Aliases are how the field names went wrong twice

Both mistakes in the struct came from the same blind spot: our constants name
some slots twice, and a first pass picked the wrong one.

- `EF_BLOCK_A = $08` is a RANGE MARKER, "10 ints, zeroed on spawn"; `EF_STATE`
  is the field. Same for `EF_TYPEF_0C`/`EF_TOUCH_KIND` and
  `EF_TYPEF_20`/`EF_NO_DROP`.
- `EF_DEPTH = EF_TYPEF_08` is an alias to another CONSTANT rather than to a
  literal, so a regex looking for `= $XX` never saw it. +0x8C was briefly
  `Typef08` when Entity_UpdateAll plainly uses it as the sprite depth, clamped
  1..0xF0 when it is not -1.

The rule that falls out: **the semantic name beats the table-column or
range-marker name**, and aliases have to be followed. `EF_TYPEF_04 = EF_HP`
runs the other way and was already right.

## Ghidra cannot always be made to help

Three shapes defeat typing, and the answer to each is a name plus a comment,
not a forced type:

- **Mid-record pointers.** Entity_TakeProjectileHits walks the pool with a
  pointer to each entity's State field - base + 0x20 - so `ShotState[-6]` is
  Alive and `ShotState - 8` is the record base. Typing it TEntity * would be
  wrong by 0x20. Named for where it points, with the index map in a comment.
- **Merged locals.** Player_Update's `Scratch` is four source variables in one
  slot. See above.
- **Phantom parameters.** Game_StartOrLoad, Ending_Update and Opening_Update
  were all typed as taking two arguments and take none; the "uses" were one
  passing the phantom to the next. That single wrong arity produced AppIdle's
  whole extraout_EDX chain. Fixing arity at the root cleared it - which is the
  cheap version of the calling-convention problem, and worth trying before
  reaching for conventions.

## Findings the typing pass turned up

Making the code readable made three things visible that were not before:

- **TEntityType's columns name themselves.** Entity_Spawn copies every column
  of the 0x48-byte type record into a named entity field, so the table's
  layout is evidence from the binary rather than a name carried over: AnimId,
  Hp, Depth, TouchKind, Class, ScreenSpace, VulnKind, +0x1C (never copied,
  so still unnamed), NoDrop, HitSound, CullOffscreen, BoxPctX/Y, InsetPctX/Y,
  Solid, TileOfsX/Y. It also confirms the "crossover" Entities.pas noted:
  column 1 goes to Hp and column 2 to Depth.
- **Entity_PlayerTouch returns an uninitialised byte.** local_34 is declared,
  never assigned, returned. Every caller ignores it, so nothing depends on the
  garbage - but it is not a "did it touch" boolean and must not be read as one.
- **Player_TakeDamage takes an int, not an entity.** It was in the script's
  entity list by mistake, and the wrong type surfaced immediately at the call
  site as `Player_TakeDamage((TEntity *)0x1)`. Entity_PlayerTouch calls it with
  1 for touch kind 1 and 2 for kind 7.

The last one is the pattern worth noting: a wrong type does not hide, it shows
up as an absurd cast at the first call site. Reading the callers after a typing
pass is how you check the pass.

## Two things that will bite the next person

**Ghidra renumbers `iVarN` after every rename.** Rename `iVar1` and the old
`iVar2` becomes `iVar1`. Renaming a list top to bottom silently retargets, so
either re-decompile between renames or rename `iVar1` repeatedly and check the
result. `local_XX` names are address-derived and stable.

**Look the address up in `exports/functions/_index.txt` FIRST.** On 2026-08-31
`Camera_ApplyMoveY`'s prototype was set on 0x0044d31c from memory - which is
the sprite depth-bucket draw - renaming and re-typing the wrong function. It
was caught by decompiling to check, and repaired. One grep would have
prevented it.

## Types: run ghidra_scripts/ApplyAkujiTypes.java

Naming alone leaves the decompilation unreadable, because an entity is an int
array: `E[8]` is a number, not a field. The script defines the two types the
reconstruction actually pins and applies them:

- **TEntity**, 65 ints, 260 bytes - the 0x104 stride the pool is indexed by.
  Field names come from the EF_ and PF_ constants; 59 of the 65 have one. The
  six that do not are `Field64`, `Field68`, `Field6C`, `FieldBC`, `FieldC0`,
  `FieldC4`, `FieldD8`, named for their offset rather than guessed at.
  Where a slot carries an entity AND a player meaning the name keeps both -
  `BlockB_AnimTimer` is the field Entity_CheckKillTiles clears and the death
  timer PS_DYING counts, one slot with two jobs.
- **TLayerInfo**, 8 ints, 32 bytes - OriginX, OriginY, DeltaX, DeltaY, TileW,
  TileH, MapTilesX, MapTilesY.
- **TPlayerState**, 0x11E4 - the whole of save.dat. Head[10], Progress[0x1195]
  and the twenty named ints from SavedStage +0x11A0 to Difficulty +0x11E0.
- **TInputState**, 0x38, and **TGameSettings**, 0x38 - both fully witnessed,
  and both MATCHES rows in audited.md.
- **TEventRecord**, 0x24 - the stride the event table is indexed by.

It also types the global pointer CELLS: p_LayerInfo, p_EntityPool,
p_PlayerState, p_InputState, p_Settings and p_EventTable. Typing p_EntityPool
is what turns `p_EntityPool + slot * 0x104` into an ordinary array index.

It also types **TLifeIcon** (X, Frame, Timer) and the global TABLE cells. That
last group is the difference between `*(int *)(p_Surfaces + 4)` and
`p_Surfaces[1]`: a `p_` cell holds an address, so giving the cell a pointee
type makes every use an index. Applied to the int tables - p_LifeIconX,
p_StageGoalTable, p_SprKnockback, p_DirX, p_DirY, p_OpeningSlideSeconds,
p_OpeningTextIds, p_OpeningImageIds - and to the pointer tables p_Surfaces,
p_TileMaps, p_MidiNames and p_TextTable.

EVERY NEW STRUCT GOES IN THIS SCRIPT as it is discovered, so a single run
brings the project up to date with whatever the reconstruction has learned.

It applies `TEntity *` to all 74 handlers and to the player, camera and entity
helpers, and types the `p_LayerInfo` cell. After it, `E[8]` reads as
`E->BlockA_State` and `*(int *)(p_LayerInfo + 0x14)` as `p_LayerInfo->TileH`.

Script Manager, find ApplyAkujiTypes, Run. Safe to re-run - types are replaced,
not duplicated. Verified with tools/javac_check.sh.

## A limitation worth knowing: calling conventions

The MCP cannot set one - `set_function_prototype` rejects any prototype
carrying `__fastcall`. This matters because Delphi's register convention passes
the first three arguments in EAX, EDX and ECX, and Ghidra's default model
expects the stack. The symptom is `in_ECX`, `extraout_EDX` and
`CONCAT31(param_2 >> 8, 0xdf)` at call sites: the decompiler inventing storage
to explain register traffic its prototype does not account for. Those are not
variables from the source, and neither are `uStack_40`/`puStack_3c` - that
triple is the Delphi try/finally SEH frame, whose only reader is the OS
unwinder. A script CAN set conventions; the right Ghidra convention name for
Borland register has not been confirmed, so nothing has been forced yet.

## What is left

- ~960 `DAT_`/`PTR_DAT_` symbols still unnamed. Only the ones whose meaning a
  bug or an audit actually established are named above; the rest would be
  guesses and a wrong name is worse than none.
- Local variables in the large functions - `Player_Update` and the event
  interpreter especially. Cheap per rename, but each needs a decompile to see
  the current numbering.
- `Font_Define`'s nine arguments. The call is
  `Font_Define(0, p_Surfaces, 0x20, 0x140, 8, 8, 9, 9, 0x5f)` and 0x5f is 95
  printable ASCII, but the roles of 0x20 and 0x140 were not confirmed, so it
  was left alone.
