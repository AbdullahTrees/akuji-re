# Feeding the reconstruction back into Ghidra

The decompilation produced the Pascal; the Pascal then explained things the
decompilation never knew. This file records that being pushed back, so the
Ghidra project matures instead of staying at the state it was first read in.

Everything here was applied through the Ghidra MCP against
`ghidra/Akuji_AIdecompAttempt`. **Ghidra must be saved** (File > Save) for any
of it to survive; the MCP edits the open project, it does not commit it.

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

## Functions renamed

    00456b14 .. 00461a0c   UnitInit_<counter>   the eight Delphi unit
                           initialization stubs Ghidra had defined, which is
                           exactly the eight that reached the backlog. See
                           UnitInit.pas.
    0045114c  Compare              returns 0, -1 if B < A, +1 if A < B
    00402ac4  Delphi_Random
    0044d31c  SpritePool_DrawBucket

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
    Delphi_Random(N)

`Entity_SolidCollideX/Y` takes the entity AND a slot, and the body works off
the SLOT - the entity argument is unused. Named `E` anyway, because that is
what every caller passes.

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
