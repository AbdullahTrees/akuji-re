{ Entities - the entity pool, its record layout, and the static type table.

  All of this is recovered from Entity_Spawn @ 0x004610C4, which is the only
  place an entity is created, plus the callers that fill in the fields it
  leaves at zero.

  ## The pool

  One flat array at p_Entities (0x0046CB68 -> 0x0046EB58), stride 0x104 bytes
  = 65 ints. The spawn function picks a free slot by scanning a RANGE chosen by
  its first argument, so the array is partitioned:

      kind 0 -> slot 0 only
      kind 1 -> slots 1 .. 0x20      (32 slots)
      kind 2 -> slots 0x21 .. 0x120  (256 slots)

  289 slots in total. Kind 0 owning exactly one slot is why slot 0 is taken to
  be the player; nothing else read so far names it, so that is an inference,
  not a decode.

  A slot is free when the byte at +0x08 is zero. Spawn returns the slot index,
  or -1 when the range is full - so a full pool silently drops the spawn, which
  is worth remembering when something fails to appear.

  ## Positions are BIASED, not fixed point

  Spawn stores param + $10000 into +0x78 and +0x7C, which looks like 16.16
  fixed point until you read a caller. FUN_004617FC passes

      Entity_Spawn(2, $24, e^[$78] - $10000, e^[$7C] - $10000)

  - it subtracts exactly what spawn adds back. So $10000 is a constant bias on
  the stored value and cancels out completely; the logical coordinate is plain
  integer pixels. The bias keeps the stored field positive for negative
  coordinates, which lets truncating division by a tile size behave the same on
  both sides of the origin.

  ## The type table

  81 entries of 18 ints at 0x0046909C, statically initialised in DATA rather
  than loaded from a file - which is why there is no entity data file in data/.
  The count is not a guess: entry 81 would start at 0x0046A764, and that is
  where the DirectX interface GUIDs begin.

  Column +0x1C is zero in all 81 rows and is never read by the spawn function;
  it is padding. Everything else is copied into the new entity. What the
  columns MEAN is mostly not established - only the ones traced to a use are
  named below, and the rest are deliberately left as raw indices rather than
  given speculative names. }

unit Entities;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

const
  ENTITY_INTS   = $41;      { 65 ints = 0x104 bytes, the array stride }
  ENTITY_BYTES  = $104;

  { Slot partitioning, from the three-way branch at the top of Entity_Spawn. }
  EKIND_SINGLE  = 0;        { slot 0 only - the player }
  EKIND_ACTOR   = 1;        { slots 1..0x20 }
  EKIND_MINOR   = 2;        { slots 0x21..0x120 }

  SLOT_SINGLE_FIRST = $00;  SLOT_SINGLE_LAST = $00;
  SLOT_ACTOR_FIRST  = $01;  SLOT_ACTOR_LAST  = $20;
  SLOT_MINOR_FIRST  = $21;  SLOT_MINOR_LAST  = $120;
  ENTITY_COUNT      = SLOT_MINOR_LAST + 1;   { 289 }

  SLOT_NONE = -1;           { Entity_Spawn's failure return }

  { See the header. Cancels out; it is not a scale factor. }
  POSITION_BIAS = $10000;

  { Field positions as INT indices into TEntity.Raw. Named only where the use
    is established; the rest keep their index. }
  EF_SLOT        = $00;   { the slot's own number }
  EF_ALIVE       = $02;   { byte; zero means the slot is free }
  EF_TYPE        = $03;   { index into ENTITY_TYPES }
  EF_SPRITE      = $04;   { sprite-pool handle, -1 when the type has no sprite }
  EF_FLAG1C      = $07;   { set to 0 or 1 by FUN_004617FC }
  EF_BLOCK_A     = $08;   { 10 ints, zeroed on spawn }
  EF_BLOCK_B     = $12;   { 10 ints, zeroed on spawn - contiguous with A }
  EF_TIMER       = $1C;   { FUN_004617FC seeds this with 30 }
  EF_POS_X       = $1E;   { biased; use PosX }
  EF_POS_Y       = $1F;
  EF_VEL_X       = $20;   { zeroed on spawn, written as -96 by FUN_004617FC }
  EF_VEL_Y       = $21;
  EF_TYPEF_08    = $23;   { <- type table +0x08 }
  EF_TYPEF_04    = $24;   { <- type table +0x04 }
  EF_BYTE94      = $25;   { byte, set to 1 on spawn }
  EF_MINUS1_B8   = $2E;   { set to -1 on spawn }
  EF_TYPEF_0C    = $32;   { <- type table +0x0C .. +0x18 land at $32..$35 }
  EF_TYPEF_20    = $37;   { <- type table +0x20 .. +0x44 land at $37..$40 }

  ENTITY_TYPE_COUNT  = 81;
  ENTITY_TYPE_FIELDS = 18;

type
  { Kept as a raw int array for the same reason TStageRecord is: the layout is
    known exactly but most field meanings are not, and inventing names for them
    would make guesses look like decodes. }
  TEntity = record
    Raw: array[0..ENTITY_INTS - 1] of Integer;
  end;
  PEntity = ^TEntity;

  TEntityType = record
    Raw: array[0..ENTITY_TYPE_FIELDS - 1] of Integer;
  end;

  TEntityPool = class
  private
    FSlots: array[0..ENTITY_COUNT - 1] of TEntity;
    function GetAlive(Index: Integer): Boolean;
  public
    procedure Clear;

    { Entity_Spawn @ 0x004610C4. X and Y are logical pixels; the bias is
      applied here. Returns the slot index, or SLOT_NONE if the kind's range is
      full - the original drops the spawn in that case and so does this. }
    function Spawn(Kind, TypeId, X, Y: Integer): Integer;
    procedure Kill(Slot: Integer);

    function PosX(Slot: Integer): Integer;
    function PosY(Slot: Integer): Integer;
    procedure SetPos(Slot, X, Y: Integer);
    function Field(Slot, IntIndex: Integer): Integer;
    procedure SetField(Slot, IntIndex, Value: Integer);

    function LiveCount: Integer;

    property Alive[Index: Integer]: Boolean read GetAlive;
  end;

const
  { Verbatim from 0x0046909C. Columns are, in order:
      +00 +04 +08 +0C +10 +14 +18 +1C +20 +24 +28 +2C +30 +34 +38 +3C +40 +44
    +00 is -1 for the three types that need no sprite object. }
  ENTITY_TYPES: array[0..ENTITY_TYPE_COUNT - 1] of TEntityType = (
    {  0 } (Raw: (    0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  1 } (Raw: (    0,     0,     4,     0,     0,     1,     0,     0,     0,     0,     0,    30,    20,    30,    30,     0,     0,     0)),
    {  2 } (Raw: (    0,     0,     5,     0,     4,     0,     0,     0,     0,     0,     1,    60,    60,    60,    60,     0,     0,     0)),
    {  3 } (Raw: (    0,     0,     5,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  4 } (Raw: (    0,     0,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  5 } (Raw: (    0,     0,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  6 } (Raw: (    0,     0,     5,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  7 } (Raw: (    0,     0,     5,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  8 } (Raw: (    0,     0,     6,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    {  9 } (Raw: (    0,     0,     7,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 10 } (Raw: (    0,     0,     6,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 11 } (Raw: (    0,     0,     6,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 12 } (Raw: (    0,     0,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 13 } (Raw: (    0,     0,     8,     0,     0,     1,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0)),
    { 14 } (Raw: (    0,     0,     1,     2,     0,     0,     0,     0,     0,     0,     0,     0,     0,    70,    70,     0,     0,     0)),
    { 15 } (Raw: (    0,     0,     1,     3,     0,     0,     0,     0,     0,     0,     1,     0,     0,    30,    30,     0,     0,     0)),
    { 16 } (Raw: (    0,     0,     1,     3,     0,     0,     0,     0,     0,     0,     1,     0,     0,    30,    30,     0,     0,     0)),
    { 17 } (Raw: (    0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     1,     0,     0)),
    { 18 } (Raw: (   -1,     0,     0,     3,     0,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0)),
    { 19 } (Raw: (    0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     1,     0,     0)),
    { 20 } (Raw: (   -1,     0,     0,     0,     0,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0)),
    { 21 } (Raw: (    0,     0,     2,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,    30,     0,     1,     0,     0)),
    { 22 } (Raw: (    0,     1,     2,     1,     0,     0,     2,     0,     0,     0,     1,     0,     0,    50,    50,     0,     0,     0)),
    { 23 } (Raw: (    0,     1,     1,     0,     5,     0,     2,     0,     0,     1,     1,     0,     0,    50,    30,     0,     0,     0)),
    { 24 } (Raw: (    0,     0,     2,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,    70,    70,     0,     0,     0)),
    { 25 } (Raw: (    0,     0,     1,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,    70,    70,     0,     0,     0)),
    { 26 } (Raw: (    0,     0,     6,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 27 } (Raw: (    0,     0,     2,     3,     0,     0,     0,     0,     0,     0,     0,     0,     0,    30,    30,     0,     0,     0)),
    { 28 } (Raw: (    0,     0,     2,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 29 } (Raw: (    0,     1,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 30 } (Raw: (    0,     2,     3,     1,     1,     0,     1,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 31 } (Raw: (    0,    30,     3,     1,     2,     0,     1,     0,     1,     0,     0,     0,     0,    30,    80,     0,     0,     0)),
    { 32 } (Raw: (   -1,     0,     6,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 33 } (Raw: (    0,     0,     6,     0,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 34 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     1,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 35 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 36 } (Raw: (    0,     0,     4,     4,     0,     0,     0,     0,     0,     0,     0,    30,    30,    70,    70,     0,     0,     0)),
    { 37 } (Raw: (    0,     0,     2,     5,     0,     0,     0,     0,     0,     0,     0,     0,     0,    70,    70,     0,     0,     0)),
    { 38 } (Raw: (    0,     4,     3,     1,     1,     0,     1,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 39 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     0,     0,     0,    50,    50,    50,    50,     0,     0,     0)),
    { 40 } (Raw: (    0,     1,     3,     6,     1,     0,     0,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 41 } (Raw: (    0,     2,     3,     1,     1,     0,     1,     0,     0,     0,     0,    50,    10,    60,    60,     0,     0,     0)),
    { 42 } (Raw: (    0,    70,     3,     1,     2,     0,     1,     0,     1,     0,     0,    20,    33,    40,    40,     0,     0,     0)),
    { 43 } (Raw: (    0,     4,     3,     0,     6,     0,     0,     0,     1,     0,     1,     0,     0,     0,     0,     2,     0,     0)),
    { 44 } (Raw: (    0,     1,     4,     1,     6,     0,     1,     0,     1,     0,     1,     0,     0,    80,    80,     0,     0,     0)),
    { 45 } (Raw: (    0,     0,     2,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,    30,     0,     1,     0,     0)),
    { 46 } (Raw: (    0,     2,     3,     1,     1,     0,     1,     0,     0,     0,     0,    60,    60,    60,    60,     0,     0,     0)),
    { 47 } (Raw: (    0,     6,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 48 } (Raw: (    0,     1,     2,     1,     1,     0,     1,     0,     1,     0,     1,    40,    40,    40,    40,     0,     0,     0)),
    { 49 } (Raw: (    0,     3,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 50 } (Raw: (    0,     4,     3,     1,     1,     0,     2,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 51 } (Raw: (    0,     1,     3,     1,     1,     0,     0,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 52 } (Raw: (    0,   120,     3,     1,     2,     0,     1,     0,     1,     0,     0,    20,    80,    50,    20,     0,     0,     0)),
    { 53 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     0,     0,     0,    50,    50,    50,    50,     0,     0,     0)),
    { 54 } (Raw: (    0,    80,     3,     1,     2,     0,     1,     0,     1,     0,     0,     0,     0,    60,    40,     0,     0,     0)),
    { 55 } (Raw: (    0,     1,     4,     1,     1,     0,     6,     0,     1,     2,     1,     0,     0,    80,    80,     0,     0,     0)),
    { 56 } (Raw: (    0,   100,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 57 } (Raw: (    0,     1,     3,     1,     1,     0,     0,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 58 } (Raw: (    0,     1,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 59 } (Raw: (    0,     1,     3,     1,     1,     0,     1,     0,     0,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 60 } (Raw: (    0,    13,     3,     1,     1,     0,     1,     0,     0,     0,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 61 } (Raw: (    0,     1,     3,     0,     1,     0,     2,     0,     0,     0,     1,     0,     0,    80,    80,     0,     0,     0)),
    { 62 } (Raw: (    0,     4,     4,     1,     1,     0,     1,     0,     0,     0,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 63 } (Raw: (    0,     4,     4,     1,     1,     0,     1,     0,     0,     0,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 64 } (Raw: (    0,     1,     2,     7,     0,     0,     2,     0,     0,     0,     0,     0,     0,    50,    50,     0,     0,     0)),
    { 65 } (Raw: (    0,     2,     3,     1,     1,     0,     1,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 66 } (Raw: (    0,     1,     3,     7,     0,     0,     2,     0,     0,     0,     0,     0,     0,    50,    50,     0,     0,     0)),
    { 67 } (Raw: (    0,     4,     4,     1,     1,     0,     1,     0,     0,     0,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 68 } (Raw: (    0,     1,     3,     0,     7,     0,     0,     0,     1,     0,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 69 } (Raw: (    0,     1,     2,     0,     0,     0,     5,     0,     0,     3,     0,     0,     0,    50,    50,     0,     0,     0)),
    { 70 } (Raw: (    0,   100,     3,     1,     1,     0,     4,     0,     0,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 71 } (Raw: (    0,     4,     4,     1,     1,     0,     7,     0,     0,     2,     0,    40,    40,    60,    60,     0,     0,     0)),
    { 72 } (Raw: (    0,     1,     3,     1,     1,     0,     0,     0,     1,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 73 } (Raw: (    0,    80,     3,     1,     2,     0,     1,     0,     1,     0,     0,     0,     0,    30,    75,     0,     0,     0)),
    { 74 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     1,     0,     1,     0,     0,    60,    60,     0,     0,     0)),
    { 75 } (Raw: (    0,     0,     4,     1,     0,     0,     0,     0,     1,     0,     0,     0,     0,     0,     0,     0,     0,     0)),
    { 76 } (Raw: (    0,     1,     2,     7,     0,     0,     2,     0,     0,     0,     0,     0,     0,    50,    50,     0,     0,     0)),
    { 77 } (Raw: (    0,  1000,     3,     1,     2,     0,     1,     0,     1,     0,     0,     5,     5,    60,    60,     0,     0,     0)),
    { 78 } (Raw: (    0,     4,     2,     1,     1,     0,     2,     0,     1,     0,     0,     0,     0,    60,    60,     0,     0,     0)),
    { 79 } (Raw: (    0,     4,     4,     1,     1,     0,     0,     0,     1,     0,     0,     0,     0,    50,    50,     0,     0,     0)),
    { 80 } (Raw: (    0,     0,     2,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0,     0))
  );

{ Bounds-checked accessor; an out-of-range id yields an all-zero record rather
  than reading past the table, which the original would happily do. }
function EntityType(Id: Integer): TEntityType;

implementation

function EntityType(Id: Integer): TEntityType;
var
  I: Integer;
begin
  if (Id < 0) or (Id >= ENTITY_TYPE_COUNT) then
  begin
    for I := 0 to ENTITY_TYPE_FIELDS - 1 do
      Result.Raw[I] := 0;
    Exit;
  end;
  Result := ENTITY_TYPES[Id];
end;

procedure TEntityPool.Clear;
begin
  FillChar(FSlots, SizeOf(FSlots), 0);
end;

function TEntityPool.GetAlive(Index: Integer): Boolean;
begin
  Result := (Index >= 0) and (Index < ENTITY_COUNT) and
            (FSlots[Index].Raw[EF_ALIVE] <> 0);
end;

function TEntityPool.Field(Slot, IntIndex: Integer): Integer;
begin
  if (Slot < 0) or (Slot >= ENTITY_COUNT) or
     (IntIndex < 0) or (IntIndex >= ENTITY_INTS) then
    Exit(0);
  Result := FSlots[Slot].Raw[IntIndex];
end;

procedure TEntityPool.SetField(Slot, IntIndex, Value: Integer);
begin
  if (Slot < 0) or (Slot >= ENTITY_COUNT) or
     (IntIndex < 0) or (IntIndex >= ENTITY_INTS) then
    Exit;
  FSlots[Slot].Raw[IntIndex] := Value;
end;

function TEntityPool.PosX(Slot: Integer): Integer;
begin
  Result := Field(Slot, EF_POS_X) - POSITION_BIAS;
end;

function TEntityPool.PosY(Slot: Integer): Integer;
begin
  Result := Field(Slot, EF_POS_Y) - POSITION_BIAS;
end;

procedure TEntityPool.SetPos(Slot, X, Y: Integer);
begin
  SetField(Slot, EF_POS_X, X + POSITION_BIAS);
  SetField(Slot, EF_POS_Y, Y + POSITION_BIAS);
end;

function TEntityPool.LiveCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to ENTITY_COUNT - 1 do
    if FSlots[I].Raw[EF_ALIVE] <> 0 then
      Inc(Result);
end;

procedure TEntityPool.Kill(Slot: Integer);
begin
  SetField(Slot, EF_ALIVE, 0);
end;

function TEntityPool.Spawn(Kind, TypeId, X, Y: Integer): Integer;
var
  First, Last, Slot, I: Integer;
  T: TEntityType;
  E: PEntity;
begin
  Result := SLOT_NONE;

  case Kind of
    EKIND_SINGLE: begin First := SLOT_SINGLE_FIRST; Last := SLOT_SINGLE_LAST; end;
    EKIND_ACTOR:  begin First := SLOT_ACTOR_FIRST;  Last := SLOT_ACTOR_LAST;  end;
    EKIND_MINOR:  begin First := SLOT_MINOR_FIRST;  Last := SLOT_MINOR_LAST;  end;
  else
    { The original leaves its range registers uninitialised for any other value
      and scans from whatever happened to be in them. Refusing is the one place
      this deliberately does NOT reproduce the original, because reproducing it
      means reading uninitialised memory. }
    Exit;
  end;

  Slot := -1;
  for I := First to Last do
    if FSlots[I].Raw[EF_ALIVE] = 0 then
    begin
      Slot := I;
      Break;
    end;
  if Slot < 0 then
    Exit;                       { range full - the spawn is dropped }

  E := @FSlots[Slot];
  E^.Raw[EF_SLOT]  := Slot;
  E^.Raw[1]        := 0;
  E^.Raw[EF_ALIVE] := 1;
  E^.Raw[EF_TYPE]  := TypeId;

  { Two loops of ten in the original, over a contiguous 20-int span - so the
    real record almost certainly has two array[0..9] fields here. }
  for I := 0 to 9 do
  begin
    E^.Raw[EF_BLOCK_A + I] := 0;
    E^.Raw[EF_BLOCK_B + I] := 0;
  end;

  E^.Raw[5] := 0;
  E^.Raw[6] := 0;
  E^.Raw[7] := 0;
  E^.Raw[EF_SPRITE]    := -1;
  E^.Raw[EF_MINUS1_B8] := -1;
  E^.Raw[EF_POS_X]     := X + POSITION_BIAS;
  E^.Raw[EF_POS_Y]     := Y + POSITION_BIAS;
  E^.Raw[EF_VEL_X]     := 0;
  E^.Raw[EF_VEL_Y]     := 0;
  E^.Raw[EF_TYPEF_08]  := 1;
  E^.Raw[EF_TYPEF_04]  := 1;
  E^.Raw[$22]          := 0;
  E^.Raw[EF_BYTE94]    := 1;
  E^.Raw[EF_TIMER]     := 0;
  E^.Raw[$1D]          := 0;
  E^.Raw[$2C]          := 0;
  E^.Raw[$2D]          := 0;
  E^.Raw[$26]          := 0;
  E^.Raw[$27]          := 0;

  { Then the type table is copied over those defaults. }
  T := EntityType(TypeId);
  E^.Raw[5]           := T.Raw[0];
  E^.Raw[EF_TYPEF_04] := T.Raw[1];
  E^.Raw[EF_TYPEF_08] := T.Raw[2];
  for I := 0 to 3 do
    E^.Raw[EF_TYPEF_0C + I] := T.Raw[3 + I];
  { Table index 7 (+0x1C) is skipped - padding, zero in all 81 rows. }
  for I := 0 to 9 do
    E^.Raw[EF_TYPEF_20 + I] := T.Raw[8 + I];

  { The original allocates a sprite-pool object here unless the type's first
    column is -1, and FAILS THE WHOLE SPAWN if the 256-object pool is full,
    clearing the alive flag again. That pool belongs to the DirectX component
    layer and is not modelled yet, so the allocation is skipped and the slot is
    kept - a divergence that matters only once sprites are drawn from it. }

  Result := Slot;
end;

end.
