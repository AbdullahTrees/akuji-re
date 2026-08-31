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
| throwaway locals | a single letter, as in a for-loop | `i`, `t`, `r`, `h` |

A local that is a loop counter, a scratch temporary or a condition flag gets a
single letter. **But check that it really is one first.** Ending_Update's slot
was briefly `t` and holds two REAL values - the text fill colour and, in phase
5, the rank index - so it is `FillOrRank`, a compound that says which is which
at each site. A single letter on a slot that carries meaning hides the meaning;
that is the opposite failure to naming a merged slot `SavedVX`, and both are
wrong.

A local that is a loop counter, a scratch temporary or a condition flag gets a
single letter. Spending a descriptive name on one is worse than useless: it
implies the value means something across the function when it does not, which
is the same mistake `SavedVX` made in Player_Update. `i` for a counter, `t` for
a slot that carries two unrelated values, `r` for a random draw.

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

## The pass corrected the Pascal too

`TGameSettings +0x2C` was `Unknown2C` on both sides while the declaration's own
trailing comment already read "gallery unlock flags". Reading Title_MainMenu
with the settings record typed made it obvious - the field is indexed by
GallerySel and drawn as ON or OFF - and Ending.pas copies Progress[1186..1192]
into it. It is `GalleryUnlocked` in both projects now, renamed with approval
because TGameSettings is a frozen MATCHES row.

Worth noting which direction that went: the Ghidra pass has mostly been the
reconstruction teaching Ghidra, and this is the first case of it going the
other way. It is also the only kind of agreement between the two that means
anything - see the warning at the top.

## Type the global CELLS, not just the records

The single largest source of leftover noise was not names at all. Every
`p_Name` cell holds the ADDRESS of something, and until the cell itself is
typed, every read and write casts:

    *(int *)p_ScreenPhase = 0;          becomes   *p_ScreenPhase = 0;
    *(undefined4 *)Credits = 0;         becomes   *Credits = NULL;

That appears in nearly every function that touches a global. ApplyAkujiTypes
now types 26 int cells, 6 byte flags and 7 object-pointer cells alongside the
records and tables.

Note the pointee depth: an int cell takes `int` (the cell becomes `int *`), and
an OBJECT cell takes a pointer (the cell becomes a pointer to a pointer),
because the thing it addresses is itself a handle. Getting that wrong gives a
type Ghidra silently refuses - `set_local_variable_type` reported "Type not
found directly: void **" and left the variable untyped, which is worth knowing
because it does not fail loudly.

## When naming is not the problem

Ending_Update stayed hard to follow after everything in it was named, and the
reason was structural, not lexical:

- **The phases are not in order.** The code tests p_ScreenPhase as
  0, 2, 3, 4, 5, else - so phase 1, the slide show and the largest part of the
  function, is the unlabelled `else` at the BOTTOM, which is the last place a
  reader looks.
- **999 is a sentinel, not a count.** It appears in both the slide and the
  timer and means "waiting on a fade".
- **Two globals are on loan.** p_OpeningSlide and p_OpeningTimer belong to the
  opening; this screen borrows them.
- **A value arrives from nowhere.** `Percent = System_RoundToInt64()` has no
  visible argument because the number is on the x87 stack.

None of that is fixable by renaming. The plate comment now walks the phases in
EXECUTION order and says each of those things, which is the only form the
answer can take.

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

**Where a struct comes from decides how you recover it.** Two structs turned
up in the input unit within an hour and they needed opposite methods:

  * TJoyState is a WINDOWS structure. No amount of staring at the binary gives
    you rgbButtons' "high-order bit means down" or the POV's "hundredths of a
    degree, -1 for centre" - those are documented facts about DIJOYSTATE, and
    reading them off MSDN corrected a layout that had been inferred wrongly
    from offsets alone. When a struct is filled by a Win32 call, go and read
    the API.

  * The 40-entry KeyBind tables are the AUTHOR'S OWN, and are fully derivable
    from the binary. DirectInput_Init clears them with a nested loop running
    `while (iVar2 != 0x28)` over two tables - the count stated outright - and
    Input_SetKeyBinding's 0xA0 stride, the 0x78 + 0xA0 = 0x118 and
    0x118 + 0xA0 = 0x1B8 tiling, and Input_IsVirtualDown's 0x27 indices all
    agree with it.

    The same function then writes the DEFAULTS, which decode the eight
    direction indices without any reasoning about axis folding at all:
    KeyBind1[0x20..0x23] are the arrow keys and KeyBind2[0x20..0x27] are
    numpad 8 2 4 6 7 9 1 3 - the four cardinals then the four corners, in
    that order.

  * A THIRD case sits between the two: COM vtable slots. These need the
    HEADER, and the header is on this machine -
    /c/msys64/mingw64/include/dinput.h. Count STDMETHOD declarations inside
    the DECLARE_INTERFACE_ block, four bytes each, including the three
    inherited IUnknown entries. Verified there:

      IDirectInputA         +0x0C CreateDevice  +0x10 EnumDevices
      IDirectInputDevice2A  +0x08 Release       +0x1C Acquire
                            +0x20 Unacquire     +0x24 GetDeviceState
                            +0x2C SetDataFormat +0x34 SetCooperativeLevel
                            +0x64 Poll

    MSDN's interface pages CANNOT do this - they list members alphabetically.
    I fetched one intending to confirm slot order and it confirms nothing of
    the kind; the numbers above were recalled and only later checked against
    the real header. Recalled is not sourced, and the note said "from
    dinput.h" before anyone had opened dinput.h.

    Reading the header also fixed the interface NAME. The entry point is
    DirectInputCreateA, which is the pre-8 API returning LPDIRECTINPUTA, so
    this game uses IDirectInputA / IDirectInputDevice2A - not the
    IDirectInput8 pair the comments originally claimed. The slots coincide
    across the shared prefix, so nothing downstream was wrong.

The tell is whose code fills the memory. A block a Win32 function writes needs
the API; a block only this program writes can be pinned from strides, bounds
and the addresses either side of it.

**The default controls, recovered end to end.** DirectInput_Init writes the
bind tables; DDDD1Init seeds Settings.KeyMap to 0, 1, 2, 3; AppIdle reads
Button[i] as Input_IsKeyDown(Dev, KeyMap[i]). Those KeyMap values are BIND
INDICES, so the chain resolves to:

    Button 0   Z  or Space      Button 2   C
    Button 1   X  or Escape     Button 3   A
    directions arrow keys, or numpad 8/2/4/6 with 7/9/1/3 for the diagonals

Every scan code checked against dinput.h's DIK_ defines rather than recalled.
It corroborates two readings made elsewhere without any of this: AppIdle's
pause hotkey is Button[2], and type 65 waits on the rising edge of Button[1] -
which this says are C and X.

**The input block is a Win32 DIJOYSTATE, and the game reads two of its
twelve axes.** Dev+0x1B8 is the structure
IDirectInputDevice8::GetDeviceState fills under the c_dfDIJoystick format:
lX, lY, lZ, lRx, lRy, lRz, rglSlider[2], rgdwPOV[4], rgbButtons[32] - 80
bytes. The binary states that size rather than implying it: Input_PollDevice
zeroes the block with FillChar(Dev + 0x1B8, 0x50).

Getting this from the documented structure rather than from the offsets fixed
a mistake. A first pass read the eight sign-reduced ints and four raw ones as
the whole thing and put a 256-byte key array after them; in fact the array at
0x1E8 is rgbButtons[32], INSIDE the joystate. Two documented details then stop
being magic numbers: Input_IsKeyDown's `> 0x7F` is MSDN's "the high-order bit
is set if the button is down", and the POVs are copied raw because a POV is a
direction in hundredths of a degree with -1 as centre, so signing one would
turn centre into "left".

The eight axes go through Input_Sign (0x00454630), which returns -1, 0 or +1.
A dead zone DOES exist - Input_ApplyDeadZone, keyed on
TInputDevice.RangePercent - but no instruction writes that field and the form
sets only DebugOption on TDDIDEX, so it is an identity. (An earlier version of
this entry said there was no dead zone in the path at all. There is one; it is
switched off.)

AppIdle, the only caller, reads Out[0] and Out[1] - sign(lX) and sign(lY) -
and nothing else. Sliders and hats are dead weight. This game is played on two
digital axes, and the keyboard path fakes them by driving lX/lY to the
+-0x7FFF extremes a fully deflected stick would report.

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
- **Entity_BoxesOverlap returns a boolean Ghidra dropped.** It was typed void
  while Rect_Overlap's result sits in AL, so every caller looked like it was
  ignoring the answer. The asymmetry inside it is real and deliberate: box A
  is built unscaled, box B scaled by ScaleX/ScaleY - which is exactly what
  Entities.pas does with EntityBox(A, 1, 1) against EntityBox(B, ScaleX,
  ScaleY).
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

**`set_function_prototype` RENAMES the function.** The identifier inside the
prototype string becomes the function's name. That makes a wrong address
doubly destructive: it retypes AND renames whatever is there, and the damage
is silent because the call reports success.

This has now happened TWICE, the second time after the first was written up
here:

  * 2026-08-31 - `Camera_ApplyMoveY`'s prototype set on 0x0044d31c from
    memory, which is the sprite depth-bucket draw.
  * later the same day - `Input_ReadAxes`'s prototype set on 0x004546e8,
    which is a unit-init stub. The real Input_ReadAxes is 0x00454648. The
    result was two functions in the symbol tree both called Input_ReadAxes,
    which is how the user spotted it, and a long comment about a 12-int
    device snapshot sitting on a function that increments a counter.

**Look the address up FIRST** - `grep` the name in
`exports/functions/_index.txt`, or call `search_functions_by_name` and read
the address back. Both incidents were one lookup away from not happening.

**And check for duplicates afterwards.** `search_functions_by_name` on the
name you just used should return exactly one address. If it returns two, one
of them is a function you have just destroyed the name of.

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

## Named in the second pass

Functions: TileMap_TileAt, TileMap_SetTile, TileMap_Create, TileMap_Draw,
SpritePool_SortByDepth, SpritePool_DrawBucket, Fader_Tick, Fader_StartFade,
BgAnime_Tick, Credits_Create, Credits_Tick, Surface_AppendEntry,
Game_OnOffText, Game_RGB, Sound_Channel, Sound_SetVolume, Input_IsKeyDown,
Input_ReadAxes, EntityUpdate_Type76, Delphi_Trim, Delphi_Format,
Delphi_MakeRect, Delphi_StrClr, Delphi_StrArrayClr, Delphi_StrLen,
Delphi_StrAsg, Delphi_ClassCreate, Delphi_DynArraySetLength, Delphi_Random.

Also Delphi_StrCatN, TileMap_Create, Delphi_DynArraySetLength.

Globals: p_TileBuffer, p_EntityTypes, p_SpriteList, p_IconAnim, p_LifeIconX,
p_StageGoalTable, p_MessageTable, p_MessageText, p_PromptFrameX,
p_AnswerIndex, p_HitSoundTable, p_BgAnime, p_EndingSurface, p_TileBuffer,
p_EntitiesLive, p_EntitiesDrawn, p_LevelNames, p_LevelVariants, p_KeyNames,
p_OmakeNames, p_RankNames, p_EndingTexts, p_EndingTextIds,
p_EndingImageIds, p_EndingSlideSeconds, p_SprGround, p_SprAir, p_SprGlide,
p_SprAirDash, p_SprDeath, p_SprKnockback, LastProbeTileX, LastProbeTileY.

Comments carrying what a name cannot: Player_Update (the merged Scratch
slot), Entity_UpdateAll (the sprite record offsets and the state guards),
Entity_Spawn (the slot ranges and the two ten-int clears), Entity_Destroy
(why it must free the sprite), Entity_PlayerTouch (the uninitialised
return), Entity_TakeProjectileHits (the mid-record pointer's index map),
Entity_SolidCollideY (branchless abs, scan ranges), Entity_TileCollideY
(what Scrolling selects), EventScript_Execute (the opcode map),
Ending_Update (the six phases and the unlock thresholds), Load_StageTable
(the column gap), TFrm_main_AppIdle (the frame order), TList_Get (what its
return type rests on).

## Scope: the game's own code

Delphi RTL and VCL internals are NOT worth naming beyond the handful that
appear inside game functions and were making them unreadable - Delphi_Format,
Delphi_Trim, Delphi_MakeRect, Delphi_StrClr and friends. Everything else the
RTL does is FPC's job in the reconstruction and nobody will read it here. The
effort belongs on 0x454790..0x4671FF and the game helpers clustered around
0x451xxx.

## Block A and block B: why the field names carry a slot number

The twenty ints of block A (+0x20) and block B (+0x48) have no fixed meaning.
Every entity type reads them as it likes and the player, slot 0, is just one
more reader. The Pascal copes by declaring a separate constant set per type
over the same offsets - PF_AIR_LATCH, EMIT_EVERY and EF_BLOCK_A + 1 are all
$09 - but a Ghidra struct gets exactly one name per offset.

The first pass named them all from the player's use, because Player_Update is
where most of the reads are. That was a mistake, and type 21 is what exposed
it: the handler tests `E->AirLatch < E->BlockB_AnimTimer` where AirLatch is an
oscillation half-period and has nothing to do with being airborne. A reader
who trusts the name mis-reads the function.

So the block fields now carry the SLOT first and the player's use second:
A1_AirLatch, A3_FallFrames, B0_AnimTimer, B4_JumpProbe. The prefix is the part
that is always true. Seeing `E->A1_AirLatch` in a handler should prompt "what
does THIS type keep in A[1]" rather than an answer.

Do not tidy the prefixes away. State, A9_Dying, B0's timer, B1/B2's child refs
and B3_Shots do hold across types, and they keep the prefix anyway so the
block layout stays legible.

## The CompareStr trap - read the instructions, not the listing

Every string comparison in this binary decompiles WRONG, in the same way, and
it is the single most dangerous artifact in the project.

Delphi compiles `if S = T then` as a call to the RTL helper @LStrCmp followed
by a `jne`. The helper reports its answer in the FLAGS, not in EAX. Ghidra
models it as an ordinary function whose result is discarded, so the following
branch has no visible condition - and the decompiler fills that hole with
WHATEVER BOOLEAN IT HAS LYING AROUND, usually one computed dozens of lines
earlier for something unrelated.

The shape to recognise:

    Delphi_CompareStr(a, b);        <- result apparently thrown away
    if ((bool)uVar9) { ... }        <- uVar9 assigned far above, from nothing
                                       to do with strings

Read that as `if a = b then { ... }`. Some sites are even more obviously
broken - MessageBox_Update has `bVar10 = true; Delphi_CompareStr(...); if
(!bVar10)`, which as written is dead code and is in fact a live branch.

26 functions in the binary call CompareStr and discard the result. FOUR are
ours: TFrm_main_DDDD1Init, EventScript_Execute, Events_SpawnNearCamera and
MessageBox_Update. All four were checked against the instructions and all four
are already correct in src/, but two of them only because an earlier session
hit the same trap and fixed it - EventRunner's music arm still carries the
comment "this used to pass True unconditionally and ignore both".

What the four actually test, so nobody has to re-derive it:

  DDDD1Init          [disp] fullscreen = 'on'          (case-SENSITIVE)
  EventScript_Execute  column 15 = '1' -> store track
                       column 13 = '0' -> play once, else loop (both branches
                       call Kbgm_FadePlay; only the loop argument differs)
  Events_SpawnNearCamera  ParamA[6] against '/', 'A', 'M', 'R', 'J', '*' -
                       six consecutive string constants at 0x00454EB4..0x00454EF0
  MessageBox_Update    the markers \w \e \k \n and the full-width
                       space 0x81 0x40

If a fifth site ever turns up, disassemble it. `objdump -D -b binary -m i386
--adjust-vma=0x400C00 --start-address=0x... akuji_ver101/akuji.exe` is enough:
look for `call` immediately followed by a conditional jump.

## Independent agreements, which are the only ones that count

Thirty-two so far, all written into src/*.pas from the disassembly BEFORE this
pass and none of them typed into Ghidra:

- Ending.pas: gallery flags from Progress[1186..1192]; the code reads
  Progress[+0x4A2]. Same for RANK_PCT 50/70/90 and RANK_TIME 1800.
- Stages.pas: csv[0..7] to rec[0..7] then csv[8..15] to rec[11..18], with
  rec[8..10] runtime scratch - exactly the gap Load_StageTable has.
- Entities.pas: the two tile-probe globals are "NOT outputs: nothing outside
  these two functions" - which is what LastProbeTileX/Y turn out to be.
- Entities.pas: EntitiesOverlap builds box A unscaled and box B scaled, which
  is precisely what Entity_BoxesOverlap does.
- Entities.pas: CompareNZ is "Compare's twin, and NOT the same function - it
  has no zero", fourteen bytes apart, and names Type 77 as the caller that
  needs it. Both true.

- EntityHandlers.pas: types 9 and 13 are the only two that also run in
  GS_PLAY_ALT - both handlers test state 0x3C or 100 and no other does.
- EntityHandlers.pas: type 13 has "POS_Y += VEL_Y on two separate lines - so
  debris falls at double the rate". It does, in states 1, 2 and 3.
- EntityHandlers.pas: type 11 "tops the death timer back up whenever it
  reaches zero, so this never actually dies of it". The handler does exactly
  that, and type 12 - written up as "the same loop one tick slower, WITHOUT
  the timer" - indeed lacks the top-up. The distinction was recorded before
  either function was decompiled here.
- EntityHandlers.pas: type 14's ITEM_VARIANTS = 2 and ITEM_FRAMES = 4, from
  the table-extent argument alone. The handler indexes
  `Variant * 0x10 + Frame * 4`, a row stride of exactly four ints.
- EntityHandlers.pas: type 14's ITEM_SETTLE_DROP = 0xA0 fires once on the
  State 0 -> 1 edge. Confirmed to the constant.
- EntityHandlers.pas: type 15 is "two states in sequence, in two separate ifs
  - so the frame that sets state 2 also runs the state-2 arm". It is, and the
  placement data explains WHY state 2 needs to be its own entry point: all 8
  shipped placements carry a '/' ParamA that sets EF_STATE := 2 when the
  progress flag is set, so a revisited switch spawns already thrown.
- EntityHandlers.pas: type 16 "computes GameState - GS_PLAY into EAX and
  returns, which nothing reads". The decompile is literally
  `return *p_GameState + -0x3c;`. This one is the strongest of the set: a dead
  result is invisible in behaviour, so nothing but reading the disassembly
  could have produced the claim.
- EntityHandlers.pas: type 29 "animates at two speeds: ten ticks a frame
  normally, four when the player's box overlaps its own, tested at three times
  width and one times height. It also drops itself 2 pixels on its very first
  frame." All four numbers hold, the drop being PosY += 0x40 at
  POSITION_SHIFT 5.
- EntityHandlers.pas: type 28 "does nothing at all unless its variant is 0 -
  both the sprite and the animation are inside that test". Both are.
- EntityHandlers.pas: type 24's frame counter "is compared against ZERO, so it
  resets on the very frame it is incremented and the two frames alternate
  every frame - vestigial rather than a speed control". The decompile bumps
  B0_AnimTimer and tests `0 <`. Its EF_FACING-as-phase reading holds too, as
  does the 16-entry flat table beside variant 8's 2-entry one.
- EntityHandlers.pas: type 22 is "one sprite, and it can die - the only
  difference from the sign is the Entity_UpdateDying call, whose result this
  one also discards". Three lines, exactly that.
- EntityHandlers.pas: type 26 is "the rising GET a collected pickup leaves,
  its VARIANT saying which message to show". It rises 0x10 a frame and indexes
  its table by Variant.
- EntityHandlers.pas: the emitter's four block-A slots - EMIT_EVERY A[1],
  EMIT_TOTAL A[2], EMIT_RADIUS A[3], EMIT_SOUND_EVERY A[4] - and the note that
  "the exhaustion test is A[2] < B[1] AFTER the increment, so an emitter
  configured for N spawns N + 1 times". Type 32 reads exactly those four and
  has exactly that off-by-one. Entity_UpdateDying's two seedings, 8/2/1/2 and
  4/32/4/1, are the two callers.
- EntityHandlers.pas: type 6's "sprite ROW comes from block A[1], which
  EntityUpdate_Type33_Explosion sets when it spawns one". Type 33 writes
  A1_AirLatch = 0 on each of its six sparks - the claim names the caller from
  inside the callee, which needed both functions read.
- EntityHandlers.pas: type 33's "two speeds are drawn separately, so the
  spread is an ellipse rather than a circle". Two independent Delphi_Random(3)
  draws, one per axis.
- EntityHandlers.pas: type 37 "divides AND takes the remainder, leaving the
  quotient in EAX as a dead result". The decompile has `iVar1 = iVar2 / 5`
  beside `Flag1c = iVar2 % 5`, and every one of the eight T37_ constants
  matches to the value.
- EntityHandlers.pas: type 36's "collision query and the move happen either
  way, landed or not" - gravity is inside the State test, the probe and the
  move are outside it.
- EntityHandlers.pas: type 31 is "a floating attacker. Six states, three
  difficulty tables, and a child entity that drives the transition this
  handler cannot make itself." All three counts hold, and the missing
  transition is exactly state 3 - type 31 writes state 3 and has no arm for
  it. Type 35 is the child, and it writes state 4 back onto its owner.
- EntityHandlers.pas: the same shape turns up again in type 38, whose missing
  arm is state 4 and whose child is type 39. Neither was known when the
  type 31 note was written.
- GmMain.pas: system.ini is read from beside the EXE with [disp] fullscreen
  and [device] input, both overriding system.dat, and fullscreen "only stands
  when system.ini is missing". All of that holds, and the section/ident split
  is confirmed twice over - once from ReadString's register convention and
  once from the SHIPPED system.ini, which is data rather than code.
- EventRunner.pas: the music sub-op stores the track when column 15 is '1'
  and loops unless column 13 is '0'. The binary has an if/else where BOTH
  arms call Kbgm_FadePlay and only the loop argument differs, which is exactly
  what the Pascal's single call with a computed loop flag collapses to.
- EventRunner.pas: ParamA's six letters '*', '/', 'A', 'M', 'R', 'J', and the
  note that "every one of the 692 records carries one of the six letters".
  There are exactly six string constants, consecutive, at 0x00454EB4.
- EventRunner.pas: the spawn window is `Cam - 2 < tile < Cam + 12` on X and
  `Cam - 2 < tile < Cam + 9.5` on Y, "fractional in the original and kept so".
  The Y bound really is float - two x87 constants, 7.5 and 2.0, added at run
  time - and X really is an integer 12. 7.5 is 240/32, the screen height in
  tiles, which is why only that axis needed floating point.
- EventRunner.pas: the unimplemented seventh ParamA form "reads seven fields
  at 6, 11, 16, 21, 26, 31 and 36 - variant, both extents and all four box
  percentages". That arm exists, buried under the CompareStr artifact as a
  six-deep `if (!bVar9)` nest, and reads exactly those seven offsets.
- EntityHandlers.pas: type 21's EF_STATE is an axis with exactly two values
  and EF_FACING is "a speed here and not a heading". The handler adds Facing
  to a coordinate and negates it on a timer, and the placement data's arg 0 is
  flush at 0..1 - twelve records, no third value.

That direction is evidence. The reverse - Ghidra agreeing with names typed
into it - is not. See the warning at the top.

## The handler tail: what actually remains

Measured across the 77 EntityUpdate_Type* handlers: 186 distinct unnamed
globals and 187 distinct locals, so roughly 2.4 of each per handler.

The structs already did the heavy lifting - a typical handler now reads
`E->State`, `E->VelX`, `p_EntityPool[slot].Facing` throughout, and what is
left is its OWN tables: a sprite table indexed by animation frame, and one or
two difficulty-keyed tables of speeds or delays. Those carry the meaning, so
they are the half worth naming; the leftover iVarN are short-lived scratch
whose role is obvious from the line they appear on.

18 of the 77 already carry a substantial comment from earlier sessions, but
those cite the TABLE address (0x46Cxxx) while what needs naming is the
POINTER CELL (0x0046Dxxx) that holds it, so they cannot be mined
mechanically - each still needs its handler read.

Done so far: 2..16, 21..30, 31..56, 58, 59, 60..65, 77, 79. Named by role
where the role is established: the item, switch, sign, save point, key items,
GET popup, emitter, explosion, launch pad, hopper, slammer, crumbling
platform, chaser, spitter, bouncer, lunger, patrolling turret, homer, the
three bosses and their fireballs, the proximity bloom, the diver, the fleer,
the ceiling dropper, the gunner.

ALL 77 handlers with an arm are now named, tabled and commented.

STILL TO DO: type 1 (the player, which is large and is the last one), plus
Events_SpawnNearCamera's remaining locals, Load_Sprite_Sheets and DDDD1Init.

Recurring shapes worth knowing before reading a new one:

- Facing is a signed SPEED in types 21, 30, 41 and 50, and a PHASE or
  oscillator in types 24, 42, 49, 52, 54, 58 and 65. It is an actual heading
  in only a minority of handlers.
- A handler with a state it writes but has no arm for is waiting on a CHILD:
  types 31 (state 3, child 35), 38 (state 4, child 39), 50 (states 3 and 4,
  child 39).
- `(x >> 5 ^ x >> 0x1f) - (x >> 0x1f)` after a `+ 0x1f` is abs(dx) in tiles -
  the wake test in types 46, 49 and 59.
- A difficulty table entry of -1 disables the thing it counts: types 42 and
  56 both guard with `-1 <`.
- Pacing a timer off the entity's OWN current HP is common, not rare: types
  31, 42, 52, 54 and 73 all do it, with different arithmetic each time
  (Hp * 10, Hp / 0x28, Hp / 2, Hp >> 2, and a plain multiply). Wounding such
  an enemy makes it act SOONER.

  CORRECTED. This line first said "only types 52 and 54". That superlative
  came from a type 54 comment written by an earlier session and was repeated
  here without being checked; type 73 falsified it two handlers later. Any
  "only N does X" claim in this file is worth re-testing whenever a new
  handler is read - three such claims have now been wrong.
- Only types 40 and 65 read the input state (re-checked against every handler
  through 80, unlike the HP claim above).
- A child that writes a state back onto its owner is the game's main
  composition device, not a special case: types 35, 39, 68, 74, 75 and 78 all
  do it, and types 31, 38, 50, 73 and 77 all depend on one. Type 35 and type
  75 are near-duplicates of each other, and type 73 uses one of each.
- One type serving two or three unrelated things by Variant or State is
  common: 55 (fireball/trail), 66 (anchor/satellite), 68 (hazard/prize),
  70 (walker/stander), 72 (faller/flyer/trail), 74 (muzzle/shot), 80.

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
