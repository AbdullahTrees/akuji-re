{ Self-tests for the entity dispatcher and the per-type handlers. }

unit EntityTests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, TypInfo,
  QdaArchive, SoundTable, WaveFile, AudioMixer, AudioOut, MidiFile, KbgmPlayer,
  Directions, Entities, EventScripts, EventCommands, PlayerState, GameState,
  Stages, Camera, TileMaps, Player, EntityHandlers, EventRunner, GameSession,
  SpritePool, Sprites, Dialogue, BgAnime, UnitInit, Title, Ending, Opening,
  GameFont, DDDDComponent, Surfaces;

{ ---------------------------------------------------------------------------
  --selftest-entities <gamedir> : Entity_UpdateAll.

  Three checks, and the first is the one that matters.

  1. HANDLER_ADDR against the BINARY. The switch is not a chain of compares -
     the compiler emitted `JMP [EAX*4 + 0x00460924]`, so akuji.exe carries an
     81-entry jump table naming every arm. This reads that table, follows each
     arm to its CALL, and compares the 78 resulting addresses against the ones
     transcribed into EntityHandlers.pas. A slip in any of 78 hand-copied
     addresses would be invisible any other way, and "types 0, 18 and 20 have no
     arm" stops being a claim and becomes a measurement: they are exactly the
     entries pointing at the default target.

  2. ScaleByPercent against exact arithmetic, with the exceptions named.

     Away from a tie - Half * Percent = 50 (mod 100) - the FPU's error is far
     too small to move the answer, so exact integer arithmetic is the reference.
     At a tie it decides, and it does not always land on round-half-even: over
     half-extents 0..1024 and percentages 0..100 it deviates in exactly SIXTY
     places, which X87_DEVIATIONS lists by value. Both the values and the COUNT
     are asserted, so an implementation that deviates anywhere else fails even
     if it gets these sixty right.

  3. The loop's own behaviour, driven through counting stubs. Entity_PlayerTouch
     and Entity_TakeProjectileHits are not translated yet, and the dispatcher
     calls them through nil-able procedure variables precisely so that a test
     can put counters there - which is what pins the slot boundary, the type-68
     special case and the mid-loop abandon without needing either function.
  --------------------------------------------------------------------------- }

type
  { A TTileSource over a shipped map, so the collision arithmetic can be swept
    against real data rather than against a fixture built to suit it. }
  TMapTiles = class(TTileSource)
  public
    Map: TTileMap;
    function TileAt(TileX, TileY: Integer): Integer; override;
  end;

  { And one over a grid the test writes, for the cases a real map has no reason
    to contain. Probes records every lookup so the SWEEP can be checked, not
    just its answer. }
  TGridTiles = class(TTileSource)
  public
    W, H: Integer;
    Cells: array[0..63, 0..63] of Integer;
    Probes: string;
    function TileAt(TileX, TileY: Integer): Integer; override;
  end;

  TStubSprites = class(TSpriteSink)
  public
    Vis:  array[0..15] of Boolean;
    Anim: array[0..15] of Integer;
    SW, SH: array[0..15] of Integer;   { what Width/Height will report }
    PX, PY, PZ: array[0..15] of Integer;
    procedure SetVisible(Handle: Integer; Visible: Boolean); override;
    function  GetVisible(Handle: Integer): Boolean; override;
    procedure SetAnim(Handle, AnimId: Integer); override;
    function  Width(Handle: Integer): Integer; override;
    function  Height(Handle: Integer): Integer; override;
    procedure SetPos(Handle, X, Y: Integer); override;
    procedure SetDepth(Handle, Depth: Integer); override;
  end;

  TCountingWorld = class(TEntityWorld)
  public
    Killed: Integer;
    Sounds: Integer;
    LastSound: Integer;
    ProgressSet: string;
    FlagFor: Integer;
    { NOTE: Pool is NOT redeclared here. It lives on TEntityWorld, and
      declaring it again shadowed the base field - the double's Spawn used
      one and Entity_Destroy used the other, which was nil, so every
      cross-entity effect silently did nothing while the test still saw a
      pool. It does NOT override SpawnDebris or RandomBelow either: a double
      that overrides the thing under test only tests the double. }
    function TileAtX(const E: TEntity; Delta: Integer; Scrolling: Boolean;
                     DeltaY: Integer = 0): Integer; override;
    function TileAtY(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer; override;
    function EdgeDistX(const E: TEntity; Delta: Integer): Integer; override;
    function EdgeDistY(const E: TEntity; Delta: Integer): Integer; override;
    function Spawn(Kind, TypeId, X, Y: Integer): Integer; override;
    procedure DestroyEntity(var E: TEntity; DropLoot: Boolean); override;
    procedure SetSpawnField(Slot, IntIndex, Value: Integer); override;
    procedure PlaySound(Id: Integer); override;
    procedure StopMusic; override;
    function EventProgressIndex(EventId: Integer): Integer; override;
    procedure SetProgress(Index: Integer); override;
  end;

function SelfTestEntities(Log: TStringList): Integer;

implementation

uses
  TestSupport;

function TMapTiles.TileAt(TileX, TileY: Integer): Integer;
begin
  Result := Map.TileAtRaw(TileX, TileY);
end;

function TGridTiles.TileAt(TileX, TileY: Integer): Integer;
begin
  Probes := Probes + Format('%d,%d ', [TileX, TileY]);
  if (TileX < 0) or (TileY < 0) or (TileX >= W) or (TileY >= H) then
    Exit(0);
  Result := Cells[TileX][TileY];
end;

procedure TStubSprites.SetVisible(Handle: Integer; Visible: Boolean);
begin Vis[Handle] := Visible; end;
function TStubSprites.GetVisible(Handle: Integer): Boolean;
begin Result := Vis[Handle]; end;
procedure TStubSprites.SetAnim(Handle, AnimId: Integer);
begin Anim[Handle] := AnimId; end;
function TStubSprites.Width(Handle: Integer): Integer;
begin Result := SW[Handle]; end;
function TStubSprites.Height(Handle: Integer): Integer;
begin Result := SH[Handle]; end;
procedure TStubSprites.SetPos(Handle, X, Y: Integer);
begin PX[Handle] := X; PY[Handle] := Y; end;
procedure TStubSprites.SetDepth(Handle, Depth: Integer);
begin PZ[Handle] := Depth; end;

function TCountingWorld.TileAtX(const E: TEntity; Delta: Integer;
                                   Scrolling: Boolean; DeltaY: Integer): Integer;
begin Result := 0; end;
function TCountingWorld.TileAtY(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer;
begin Result := 0; end;
function TCountingWorld.EdgeDistX(const E: TEntity; Delta: Integer): Integer;
begin Result := 0; end;
function TCountingWorld.EdgeDistY(const E: TEntity; Delta: Integer): Integer;
begin Result := 0; end;
function TCountingWorld.Spawn(Kind, TypeId, X, Y: Integer): Integer;
begin
  if Pool = nil then
    Exit(SLOT_NONE);
  Result := Pool.Spawn(Kind, TypeId, X, Y);
end;
procedure TCountingWorld.DestroyEntity(var E: TEntity; DropLoot: Boolean);
begin
  Inc(Killed);
  inherited DestroyEntity(E, DropLoot);
end;
procedure TCountingWorld.SetSpawnField(Slot, IntIndex, Value: Integer);
begin
  if Pool <> nil then
    Pool.SetField(Slot, IntIndex, Value);
end;
procedure TCountingWorld.StopMusic;
begin end;

procedure TCountingWorld.PlaySound(Id: Integer);
begin
  Inc(Sounds);
  LastSound := Id;
end;

function TCountingWorld.EventProgressIndex(EventId: Integer): Integer;
begin
  { Stands in for looking ParamB up in the event table. -1 means "no event",
    which is what the base class says when nothing is wired. }
  if EventId < 0 then
    Exit(-1);
  Result := FlagFor;
end;

procedure TCountingWorld.SetProgress(Index: Integer);
begin
  ProgressSet := ProgressSet + Format('%d ', [Index]);
end;
var
  { The dispatcher's two hooks are plain procedures, so their bookkeeping has to
    be global. TouchAbortAt is how the mid-loop abandon is provoked: the touch
    on that slot changes the game state, exactly as a touch that starts an event
    script would. }
  TouchCount, HitCount: Integer;
  TouchSlots: string;
  TouchAbortAt: Integer;
  EntityTestState: Integer;

procedure CountTouch(var E, Player: TEntity; var P: TPlayerState;
                     var Inp: TInputState; World: TEntityWorld);
begin
  Inc(TouchCount);
  TouchSlots := TouchSlots + Format('%d ', [E.Raw[EF_SLOT]]);
  if E.Raw[EF_SLOT] = TouchAbortAt then
    EntityTestState := GS_TITLE_INIT;
end;

procedure CountHit(var E: TEntity; World: TEntityWorld);
begin
  Inc(HitCount);
end;

{ (Half * Percent) / 100 rounded half to even, done in integers so that it
  cannot share a rounding mistake with the code under test. }
function ExactPercent(Half, Percent: Integer): Integer;
var
  N, Q, R: Int64;
begin
  N := Int64(Half) * Percent;
  Q := N div 100;
  R := N mod 100;
  if R > 50 then
    Inc(Q)
  else if R = 50 then
    if Odd(Q) then Inc(Q);
  Result := Integer(Q);
end;

const
  { (half, percent, result) at every point where the x87 sequence disagrees with
    exact round-half-even, over half-extents 0..1024 and percentages 0..100 -
    the whole domain, not just the twelve percentages the shipped table happens
    to use. Sixty places out of 103,525.

    These come from an exact rational simulation of FDIV/FMULP/FISTP at 64-bit
    significands, written separately from the Pascal. That is what makes this a
    check rather than a restatement of the code under test.

    They cluster: every one is a tie, half * percent = 50 (mod 100), and the
    runs restart at powers of two, which is the ulp structure showing through.
    Sweeping the FULL percentage range rather than the shipped twelve is
    deliberate - a mutation that mishandles the exactly-half-an-ulp case is
    invisible at the shipped percentages and shows up at 65. }
  X87_DEVIATIONS: array[0..59, 0..2] of Integer = (
    (  50,  59,   29), (  75,  42,   31), (  95,  30,   29),
    ( 150,  21,   31), ( 150,  53,   79), ( 175,  30,   53),
    ( 190,  15,   29), ( 190,  65,  123), ( 195,  30,   59),
    ( 325,  18,   59), ( 325,  66,  215), ( 325,  78,  253),
    ( 335,  30,  101), ( 350,  15,   53), ( 350,  53,  185),
    ( 350,  65,  227), ( 355,  30,  107), ( 375,  30,  113),
    ( 375,  54,  203), ( 390,  15,   59), ( 390,  65,  253),
    ( 395,  30,  119), ( 415,  30,  125), ( 475,  26,  123),
    ( 550,  53,  291), ( 625,  18,  113), ( 625,  66,  413),
    ( 625,  78,  487), ( 650,   9,   59), ( 650,  33,  215),
    ( 650,  39,  253), ( 650,  59,  383), ( 655,  30,  197),
    ( 670,  15,  101), ( 670,  65,  435), ( 675,  30,  203),
    ( 695,  30,  209), ( 710,  15,  107), ( 710,  65,  461),
    ( 715,  30,  215), ( 725,  66,  479), ( 735,  30,  221),
    ( 750,  15,  113), ( 750,  27,  203), ( 750,  53,  397),
    ( 750,  65,  487), ( 755,  30,  227), ( 775,  30,  233),
    ( 775,  54,  419), ( 790,  15,  119), ( 795,  30,  239),
    ( 815,  30,  245), ( 830,  15,  125), ( 835,  30,  251),
    ( 850,  59,  501), ( 875,  26,  227), ( 875,  54,  473),
    ( 950,  13,  123), ( 950,  53,  503), ( 975,  26,  253));

{ --- 4. Entity_TileCollideX/Y @ 0x00457300 / 0x004574DC ------------------

  The first check is the one that matters and it uses SHIPPED DATA. An entity
  small enough to sit inside one tile is placed at the centre of every tile of a
  real map in turn, and asked what it would hit moving one sub-pixel right. The
  answer must be that tile when the map says it is solid and TILE_NONE when it
  does not - for all of them.

  That sweep is what pins the index arithmetic, and the -128 in particular. The
  tile index is built from two separately-rounded pixel conversions and then
  biased by 128 tiles, and 128 is only right because BOTH the layer origin and
  the entity position carry POSITION_BIAS. Get that wrong by one and the whole
  map misaligns; get the rounding wrong and it misaligns near the edges only.
  Neither could hide behind a hand-built fixture. }
{ Entity_CheckKillTiles @ 0x004576B4.

  Unlike Entity_TileCollide*, which sweep a one-dimensional span along one
  edge, this walks the entity's whole tile RECTANGLE. TGridTiles records every
  lookup, so the shape of the sweep is checked and not merely its answer -
  which is the difference between "it found the tile" and "it looked where the
  original looks". }
function TestKillTiles(Log: TStringList): Integer;
const
  KILL = KILL_TILE;   { terrains 1..8; Stages.pas has the table }
var
  Grid: TGridTiles;
  L: TLayerInfo;
  E: TEntity;
  Bad: Integer;

  procedure PlaceAt(PxX, PxY, ExtX, ExtY: Integer);
  begin
    FillChar(E, SizeOf(E), 0);
    E.Raw[EF_POS_X]    := (PxX shl POSITION_SHIFT) + POSITION_BIAS;
    E.Raw[EF_POS_Y]    := (PxY shl POSITION_SHIFT) + POSITION_BIAS;
    E.Raw[EF_EXTENT_X] := ExtX;
    E.Raw[EF_EXTENT_Y] := ExtY;
  end;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('FAILED: ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- Entity_CheckKillTiles ---');

  FillChar(L, SizeOf(L), 0);
  L.OriginX := POSITION_BIAS;
  L.OriginY := POSITION_BIAS;
  L.TileW := 32;
  L.TileH := 32;

  { The 0x80 the original subtracts from both tile coordinates is not a magic
    number: the layer origin and the entity position EACH carry POSITION_BIAS,
    which is 2048 pixels, and 2048 / 32 is 64 tiles. Two of them is 128. So
    TILE_BIAS_TILES is a consequence of the bias appearing twice in the sum,
    and if the bias ever changed this would have to change with it. }
  Want(TILE_BIAS_TILES = 2 * ((POSITION_BIAS shr POSITION_SHIFT) div 32),
       Format('TILE_BIAS_TILES is %d but two lots of the origin bias is %d',
              [TILE_BIAS_TILES,
               2 * ((POSITION_BIAS shr POSITION_SHIFT) div 32)]));

  Grid := TGridTiles.Create;
  try
    Grid.W := 20;
    Grid.H := 15;

    { --- the tile under a small entity ---------------------------------- }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    E.Raw[EF_STATE] := 3;
    E.Raw[EF_BLOCK_B] := 77;
    Grid.Probes := '';
    EntityCheckKillTiles(E, L, Grid, KILL);
    { 10 written out, not KILL_TILE_STATE. An expectation phrased in terms of
      the constant it is checking moves with it and cannot fail - which this
      one did not, until a mutation set KILL_TILE_STATE to 11 and walked
      straight past. Fourth time on this project; tools/README.md keeps count. }
    Want(E.Raw[EF_STATE] = 10,
         Format('standing on the kill tile left the state at %d, want 10',
                [E.Raw[EF_STATE]]));
    Want(E.Raw[EF_BLOCK_B] = 0,
         Format('the state counter was left at %d, want 0',
                [E.Raw[EF_BLOCK_B]]));
    Log.Add(Format('small entity on a kill tile: probed [%s]',
      [Trim(Grid.Probes)]));

    { --- an ordinary tile does nothing ---------------------------------- }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := KILL - 1;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    E.Raw[EF_STATE] := 3;
    E.Raw[EF_BLOCK_B] := 77;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Want(E.Raw[EF_STATE] = 3, 'a tile one below the kill tile killed anyway');
    Want(E.Raw[EF_BLOCK_B] = 77, 'a near miss still cleared the counter');

    { --- the WHOLE box is swept, both axes ------------------------------ }
    { A 20 x 40 entity centred in tile (5,5) spans columns 4..5 and rows 4..6.
      Tile Collide would only sweep one edge; this must reach all six. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 20, 40);
    Grid.Probes := '';
    EntityCheckKillTiles(E, L, Grid, KILL);
    Log.Add(Format('20x40 entity at tile (5,5): probed [%s]',
      [Trim(Grid.Probes)]));
    Want(Trim(Grid.Probes) = '5,4 5,5 5,6',
         'the swept rectangle is not columns 5..5 by rows 4..6');

    { An entity exactly one tile tall fills its row and NO more. The -1 on the
      trailing edge is the only thing keeping it out of the next one, and it
      shows up only when the bottom edge lands exactly on a tile boundary -
      every other fixture here divides the same way with or without it. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][6] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 32);
    Grid.Probes := '';
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Log.Add(Format('exactly one tile tall: probed [%s]', [Trim(Grid.Probes)]));
    Want(Trim(Grid.Probes) = '5,5',
         'a box flush with the tile boundary spilled into the next row');
    Want(E.Raw[EF_STATE] = 3,
         'a box flush with the tile boundary was killed by the row below it');

    { EF_BOX_OFS_* is an INSET: added on the leading edge and subtracted on
      the trailing one, so it pulls both sides in. Adding it on both would
      slide the box instead, and with the offset at 0 - as it is in every
      fixture above - the two are the same thing. Give it a real value. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][4] := KILL;
    Grid.Cells[5][6] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 96);      { spans rows 4..6 }
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Want(E.Raw[EF_STATE] = 10, 'a 96-tall entity did not reach rows 4 and 6');

    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 96);
    E.Raw[EF_BOX_OFS_Y] := 32;                     { pulls both ends in a tile }
    Grid.Probes := '';
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Log.Add(Format('96 tall with a 32 inset: probed [%s]', [Trim(Grid.Probes)]));
    Want(Trim(Grid.Probes) = '5,5',
         'the inset did not pull BOTH ends of the box in');
    Want(E.Raw[EF_STATE] = 3,
         'the inset box still reached the kill tiles above and below it');

    { A kill tile at the bottom of that box is found... }
    Grid.Cells[5][6] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 20, 40);
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Want(E.Raw[EF_STATE] = KILL_TILE_STATE,
         'a kill tile at the entity''s feet was missed');

    { ...and one row further down is outside it and must not be. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][7] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 20, 40);
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Want(E.Raw[EF_STATE] = 3, 'the sweep reached a row below the box');

    { A wide entity reaches sideways too, which is what makes this a
      rectangle rather than a column. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[6][5] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 80, 2);
    Grid.Probes := '';
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Log.Add(Format('80-wide entity at tile (5,5): probed [%s]',
      [Trim(Grid.Probes)]));
    Want(E.Raw[EF_STATE] = KILL_TILE_STATE,
         'a kill tile beside a wide entity was missed');

    { --- the low sixteen bits, and only those --------------------------- }
    { The original compares MOVZX EAX,AX against the global, so a tile whose
      low word is the kill tile matches however high the rest is. No shipped
      map has such a word; the masking is reproduced because it is there. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := $10000 + KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Want(E.Raw[EF_STATE] = KILL_TILE_STATE,
         'the comparison is not masked to sixteen bits');

    { And terrain 9's kill tile, 1000, is outside the id space every tileset
      can produce - which is what makes that terrain survivable. Asked here
      the only way a fixture can: a map that does not contain it. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := 99;          { the largest id any 10x10 tileset has }
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL_TILE_NONE);
    Want(E.Raw[EF_STATE] = 3,
         'the highest tile id a tileset can hold matched terrain 9''s kill tile');
  finally
    Grid.Free;
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('OK - the whole box is swept, nothing outside it is, '
      + 'and the match is masked');
end;

{ Types 8 and 26 - the two effects that destroy themselves.

  These are worth their own check because their failure mode is silence. An
  effect whose handler is missing does not crash or look obviously wrong: it
  just never dies, and the screen slowly fills with immortal entities wearing
  sprite 0. Nothing in the dispatcher can notice. So what is asserted here is
  that each one DOES reach its Entity_Destroy, and on which frame. }
function TestEffectHandlers(Log: TStringList): Integer;
var
  W: TCountingWorld;
  E: TEntity;
  I, Bad, Died, Frames: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

  procedure Fresh(TypeId: Integer);
  begin
    FillChar(E, SizeOf(E), 0);
    E.Raw[EF_ALIVE] := 1;
    E.Raw[EF_TYPE] := TypeId;
    E.Raw[EF_SPRITE] := SPRITE_NONE;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- the self-destructing effects ---');
  W := TCountingWorld.Create;
  try
    { --- type 8: four frames, five ticks each --------------------------- }
    Fresh(8);
    Died := -1;
    for I := 1 to 60 do
    begin
      if E.Raw[EF_ALIVE] <> 0 then
        EntityUpdate_Type08(E, GS_PLAY, W);
      if (Died < 0) and (E.Raw[EF_ALIVE] = 0) then
        Died := I;
    end;
    Log.Add(Format('type 8 lived %d frames', [Died]));
    { Four frames of five ticks is 20, and the destroy lands ON the twentieth
      rather than after it: the check follows the increment inside the same
      call, so the tick that carries the counter past the last index also
      destroys the entity. There is no extra frame. }
    Want(Died = 20,
         Format('type 8 died on frame %d, want 20 - four frames of five '
           + 'ticks, with the destroy on the last of them', [Died]));

    { Its sprite comes from the frame counter, so it must have walked the
      whole table rather than sitting on one. }
    Fresh(8);
    EntityUpdate_Type08(E, GS_PLAY, W);
    Want(E.Raw[EF_ANIM_ID] = 50, 'type 8 does not start on sprite 50');
    for I := 1 to 5 do
      EntityUpdate_Type08(E, GS_PLAY, W);
    Want(E.Raw[EF_ANIM_ID] = 51,
         Format('after five ticks type 8 is on sprite %d, want 51',
                [E.Raw[EF_ANIM_ID]]));

    { Outside play it freezes: the sprite is still written, the timer is not. }
    Fresh(8);
    for I := 1 to 60 do
      EntityUpdate_Type08(E, GS_STATE_140, W);
    Want(E.Raw[EF_ALIVE] <> 0, 'type 8 died during an event script');
    Want(E.Raw[EF_ANIM_ID] = 50, 'type 8 animated during an event script');

    { --- the whole family, by the property that matters ---------------- }
    { An effect that never reaches its Entity_Destroy is invisible to every
      other check and fills the screen over minutes. So each one is driven to
      exhaustion and required to end - or, for the three that deliberately do
      not, required to STILL BE ALIVE. Getting that backwards is exactly the
      bug this catches, in either direction. }
    for I := 3 to 13 do
    begin
      if I = 8 then
        Continue;                { covered in detail above }
      Fresh(I);
      E.Raw[EF_VEL_X] := 32;     { types 3 and 6 need a direction to animate }
      Died := -1;
      for Frames := 1 to 400 do
      begin
        if E.Raw[EF_ALIVE] = 0 then
          Break;
        case I of
          3:  EntityUpdate_Type03(E, GS_PLAY, W);
          4:  EntityUpdate_Type04(E, GS_PLAY, W);
          5:  EntityUpdate_Type05(E, GS_PLAY, W);
          6:  EntityUpdate_Type06(E, GS_PLAY, W);
          7:  EntityUpdate_Type07(E, GS_PLAY, W);
          9:  EntityUpdate_Type09(E, GS_PLAY);
          10: EntityUpdate_Type10(E, GS_PLAY, W);
          11: EntityUpdate_Type11(E, GS_PLAY);
          12: EntityUpdate_Type12(E, GS_PLAY);
          13: EntityUpdate_Type13(E, GS_PLAY, W);
        end;
        if (Died < 0) and (E.Raw[EF_ALIVE] = 0) then
          Died := Frames;
      end;
      { 9, 11 and 12 have no Entity_Destroy at all - they are culled
        off-screen instead, which is a different mechanism. }
      if (I = 9) or (I = 11) or (I = 12) then
        Want(Died < 0,
             Format('type %d ended itself on frame %d; it has no '
               + 'Entity_Destroy and should be culled instead', [I, Died]))
      else
        Want(Died > 0,
             Format('type %d never ended in 400 frames - it would stay on '
               + 'screen for ever wearing sprite %d',
               [I, E.Raw[EF_ANIM_ID]]));
      if Died > 0 then
        Log.Add(Format('  type %2d ended on frame %d', [I, Died]));
    end;

    { --- type 26: rises, then goes --------------------------------------- }
    Fresh(26);
    E.Raw[EF_POS_Y] := POSITION_BIAS;
    Died := -1;
    for I := 1 to 60 do
    begin
      if E.Raw[EF_ALIVE] <> 0 then
        EntityUpdate_Type26(E, GS_PLAY, W);
      if (Died < 0) and (E.Raw[EF_ALIVE] = 0) then
        Died := I;
    end;
    Log.Add(Format('type 26 lived %d frames and rose %d sub-pixels',
      [Died, POSITION_BIAS - E.Raw[EF_POS_Y]]));
    Want(Died = 31,
         Format('type 26 died on frame %d, want 31 - the count must EXCEED 30',
                [Died]));
    { It rose on every frame it was alive, 16 sub-pixels each. }
    Want(POSITION_BIAS - E.Raw[EF_POS_Y] = 31 * $10,
         Format('type 26 rose %d sub-pixels, want %d',
                [POSITION_BIAS - E.Raw[EF_POS_Y], 31 * $10]));

    { The variant is the whole difference between the two messages, and
      Entity_TouchPickup is what sets it - 0 for an ordinary stone, 1 when the
      stone completed a target. }
    Fresh(26);
    EntityUpdate_Type26(E, GS_PLAY, W);
    Want(E.Raw[EF_ANIM_ID] = 83,
         Format('variant 0 shows sprite %d, want 83', [E.Raw[EF_ANIM_ID]]));
    Fresh(26);
    E.Raw[EF_VARIANT] := 1;
    EntityUpdate_Type26(E, GS_PLAY, W);
    Want(E.Raw[EF_ANIM_ID] = 99,
         Format('variant 1 shows sprite %d, want 99', [E.Raw[EF_ANIM_ID]]));
  finally
    W.Free;
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('OK - both effects reach their Entity_Destroy');
end;

function TestTileCollide(Log: TStringList; const GameDir: string): Integer;
const
  SOLID = 50;
var
  Map: TTileMap;
  Tiles: TMapTiles;
  Grid: TGridTiles;
  L, L2: TLayerInfo;
  E: TEntity;
  TX, TY, Got, Want, Bad, Solids, Diff, A, B: Integer;
  ProbeA, ProbeB: string;

  procedure PlaceAt(PxX, PxY, ExtX, ExtY: Integer);
  begin
    FillChar(E, SizeOf(E), 0);
    E.Raw[EF_POS_X]    := (PxX shl POSITION_SHIFT) + POSITION_BIAS;
    E.Raw[EF_POS_Y]    := (PxY shl POSITION_SHIFT) + POSITION_BIAS;
    E.Raw[EF_EXTENT_X] := ExtX;
    E.Raw[EF_EXTENT_Y] := ExtY;
  end;

begin
  Result := 0;
  Log.Add('');
  Log.Add('--- Entity_TileCollideX/Y ---');

  FillChar(L, SizeOf(L), 0);
  L.OriginX := POSITION_BIAS;
  L.OriginY := POSITION_BIAS;
  L.TileW := 32;
  L.TileH := 32;

  { --- 4a. every tile of a shipped map ---------------------------------- }
  Map := TTileMap.Create;
  Tiles := TMapTiles.Create;
  try
    Tiles.Map := Map;
    if not Map.Load(GameDir, 1) then
    begin
      Log.Add('FAILED: could not load map 001');
      Inc(Result);
    end
    else if (Map.TileWidth <> 32) or (Map.TileHeight <> 32) then
    begin
      Log.Add(Format('FAILED: map 001 is %dx%d tiles, the arithmetic assumes 32',
        [Map.TileWidth, Map.TileHeight]));
      Inc(Result);
    end
    else
    begin
      Bad := 0;
      Solids := 0;
      for TY := 0 to Map.MapHeight - 1 do
        for TX := 0 to Map.MapWidth - 1 do
        begin
          PlaceAt(TX * 32 + 16, TY * 32 + 16, 2, 2);
          Want := Map.TileAtRaw(TX, TY);
          if Want >= SOLID then
            Inc(Solids)
          else
            Want := TILE_NONE;
          Got := EntityTileCollideX(E, L, Tiles, SOLID, 1, 0, False);
          if Got <> Want then
          begin
            if Bad < 5 then
              Log.Add(Format('  tile (%d,%d): got %d, map says %d',
                [TX, TY, Got, Want]));
            Inc(Bad);
          end;
          { and the Y mirror, moving down, must agree tile for tile }
          if EntityTileCollideY(E, L, Tiles, SOLID, 1, 0, False) <> Want then
          begin
            Inc(Bad);
            if Bad < 8 then
              Log.Add(Format('  tile (%d,%d): Y disagrees with X', [TX, TY]));
          end;
        end;
      Log.Add(Format('map 001, %dx%d tiles (%d of them solid): %d wrong',
        [Map.MapWidth, Map.MapHeight, Solids, Bad]));
      Inc(Result, Bad);
      if Solids = 0 then
      begin
        Log.Add('FAILED: no solid tiles in map 001 - the sweep proved nothing');
        Inc(Result);
      end;
    end;
  finally
    Tiles.Free;
    Map.Free;
  end;

  { --- 4b. the things a real map cannot show ----------------------------- }
  Grid := TGridTiles.Create;
  try
    Grid.W := 20;
    Grid.H := 15;

    { A standing entity is never blocked - the whole body is inside if Delta
      <> 0, which is why Player_Update can ask about EF_VEL_X unconditionally. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := 60;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    if EntityTileCollideX(E, L, Grid, SOLID, 0, 0, False) <> TILE_NONE then
    begin
      Log.Add('FAILED: a zero delta reported a collision');
      Inc(Result);
    end;

    { The leading edge sweeps the WHOLE cross-axis span. A 40-tall entity
      centred in tile row 5 spans rows 4..6, so a wall at its feet stops it. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][6] := 61;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 20, 40);
    Grid.Probes := '';
    Got := EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    Log.Add(Format('40-tall entity, wall at its feet: got %d, probed [%s]',
      [Got, Trim(Grid.Probes)]));
    if Got <> 61 then
    begin
      Log.Add('FAILED: the sweep did not reach the bottom of the box');
      Inc(Result);
    end;
    if Trim(Grid.Probes) <> '5,4 5,5 5,6' then
    begin
      Log.Add('FAILED: the swept span should be rows 4..6 of column 5');
      Inc(Result);
    end;

    { One row further down is outside the box and must not be seen. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][7] := 61;
    if EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False) <> TILE_NONE then
    begin
      Log.Add('FAILED: the sweep reached past the bottom of the box');
      Inc(Result);
    end;

    { Left and right edges are not symmetric: the right one carries a -1
      because it is the last pixel inside the box. Centre 183 puts the right
      edge in tile 6 and the left edge in tile 5. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[6][5] := 62;
    PlaceAt(183, 5 * 32 + 16, 20, 2);
    A := EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    B := EntityTileCollideX(E, L, Grid, SOLID, -1, 0, False);
    Log.Add(Format('edges at centre 183: moving right %d, moving left %d',
      [A, B]));
    if (A <> 62) or (B <> TILE_NONE) then
    begin
      Log.Add('FAILED: the two edges should straddle the tile boundary here');
      Inc(Result);
    end;

    { Scrolling decides which pixel conversion carries the 1/32 remainder.
      Compare probed columns across tile boundaries, where that one-pixel
      rounding difference is observable. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    for TX := 0 to 19 do
      Grid.Cells[TX][5] := 63;
    Diff := 0;
    for TX := 160 to 223 do
    begin
      PlaceAt(TX, 5 * 32 + 16, 20, 2);
      E.Raw[EF_POS_X] := E.Raw[EF_POS_X] + 20;   { fraction on the entity }
      L.OriginX := POSITION_BIAS;                { and none on the layer }
      Grid.Probes := '';
      EntityTileCollideX(E, L, Grid, SOLID, 20, 0, False);
      ProbeA := Trim(Grid.Probes);
      Grid.Probes := '';
      EntityTileCollideX(E, L, Grid, SOLID, 20, 0, True);
      ProbeB := Trim(Grid.Probes);
      if ProbeA <> ProbeB then
      begin
        Inc(Diff);
        if Diff = 1 then
          Log.Add(Format('  at centre %d: not scrolling probes %s, scrolling '
            + 'probes %s', [TX, ProbeA, ProbeB]));
      end;
      { Pin the direction of the distinction: with a 20/32 entity remainder,
        moving the entity reaches tile 6 while moving the layer stays in 5. }
      if TX = 182 then
      begin
        if ProbeA <> '6,5' then
        begin
          Log.Add(Format('FAILED: not scrolling should probe 6,5, got %s',
            [ProbeA]));
          Inc(Result);
        end;
        if ProbeB <> '5,5' then
        begin
          Log.Add(Format('FAILED: scrolling should probe 5,5, got %s',
            [ProbeB]));
          Inc(Result);
        end;
      end;
    end;
    L.OriginX := POSITION_BIAS;
    Log.Add(Format('scrolling flag across two tiles of travel: changes the '
      + 'column in %d of 64 positions', [Diff]));
    if Diff = 0 then
    begin
      Log.Add('FAILED: the scrolling flag never mattered - it should, by '
        + 'rounding');
      Inc(Result);
    end;
    if Diff > 8 then
    begin
      Log.Add('FAILED: it should shift a boundary, not change the answer '
        + 'everywhere');
      Inc(Result);
    end;

    { Centre 182 places the inclusive right edge on pixel 191, exposing the
      required -1 before the tile conversion. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[6][5] := 64;
    PlaceAt(182, 5 * 32 + 16, 20, 2);
    Got := EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    Log.Add(Format('right edge flush with tile 5''s last pixel: %d', [Got]));
    if Got <> TILE_NONE then
    begin
      Log.Add('FAILED: the right edge should still be inside tile 5');
      Inc(Result);
    end;

    { A tile EXACTLY at the threshold is solid - the test is >=, not >. Nothing
      else in this file uses a tile equal to the threshold, so a mutation to >
      survived. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := SOLID;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    Got := EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    if Got <> SOLID then
    begin
      Log.Add(Format('FAILED: a tile equal to the threshold must be solid, '
        + 'got %d', [Got]));
      Inc(Result);
    end;

    { The cross-axis span converts each term to pixels SEPARATELY. Summing
      first differs only by the carry of the two 1/32 fractions, and only
      matters where that carry crosses a tile edge - which needs the entity on
      a tile boundary AND both fractions set. At pixel Y 160 with 20/32 on each,
      the correct reading spans rows 4..5 and the summed one only row 5. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    PlaceAt(176, 160, 2, 2);
    E.Raw[EF_POS_Y] := E.Raw[EF_POS_Y] + 20;
    L.OriginY := POSITION_BIAS + 20;
    Grid.Probes := '';
    EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    L.OriginY := POSITION_BIAS;
    Log.Add(Format('cross-axis span with fractions on both: [%s]',
      [Trim(Grid.Probes)]));
    if Trim(Grid.Probes) <> '5,4 5,5' then
    begin
      Log.Add('FAILED: each term must be rounded to pixels on its own');
      Inc(Result);
    end;

    { The Y sweep divides its own axis by TileH. Every shipped map is 32x32, so
      swapping it for TileW is invisible against real data; this uses a
      synthetic 32x16 layer purely to tell the two apart. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    L2 := L;
    L2.TileH := 16;
    PlaceAt(176, 176, 2, 2);
    Grid.Probes := '';
    EntityTileCollideY(E, L2, Grid, SOLID, 1, 0, False);
    Log.Add(Format('Y sweep on a 32x16 layer probes [%s]', [Trim(Grid.Probes)]));
    if Trim(Grid.Probes) <> '5,139' then
    begin
      Log.Add('FAILED: the Y sweep must divide its own axis by TileH');
      Inc(Result);
    end;

    { The map wraps horizontally, because TileMap_Get has no bounds check.
      Column -1 is the previous row's last column. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    PlaceAt(-1 * 32 + 16, 5 * 32 + 16, 2, 2);
    Grid.Probes := '';
    EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    Log.Add(Format('an entity off the left edge probes [%s]',
      [Trim(Grid.Probes)]));
    if Trim(Grid.Probes) <> '-1,5' then
    begin
      Log.Add('FAILED: off-map lookups should be passed through, not clamped');
      Inc(Result);
    end;

    { And the wrap itself, which lives in TTileMap.TileAtRaw rather than in the
      collision code - the grid stub above never exercises it, which is why a
      mutation that clamped instead of wrapping survived. Column -1 of row N is
      the last column of row N-1, because the original indexes
      Data[X + Y * Width] with no check at all. }
    Map := TTileMap.Create;
    try
      if Map.Load(GameDir, 1) then
      begin
        Bad := 0;
        Solids := 0;
        for TY := 1 to Map.MapHeight - 1 do
        begin
          if Map.TileAtRaw(-1, TY) <> Map.TileAtRaw(Map.MapWidth - 1, TY - 1) then
            Inc(Bad);
          if Map.TileAtRaw(Map.MapWidth, TY - 1) <> Map.TileAtRaw(0, TY) then
            Inc(Bad);
          if Map.TileAtRaw(-1, TY) <> 0 then
            Inc(Solids);
        end;
        Log.Add(Format('horizontal wrap over %d rows: %d wrong, %d of them '
          + 'non-zero', [Map.MapHeight - 1, Bad, Solids]));
        Inc(Result, Bad);
        if Solids = 0 then
        begin
          Log.Add('FAILED: every wrapped lookup was 0 - a clamp would pass too');
          Inc(Result);
        end;
      end;
    finally
      Map.Free;
    end;

  finally
    Grid.Free;
  end;
end;

{ --- 5. handler table contents and extents -------------------------------

  Each pointer target establishes a table's start, and the next target
  establishes its storage extent. Pin() verifies that extent separately from
  the number of entries reachable by the handler, then checks that the declared
  values are a prefix of the executable's table. }
function TestSpriteTables(Log: TStringList; const GameDir: string): Integer;
const
  { Pointer globals and table bodies occupy these executable regions. }
  { The CODE section, for the write-only scan below. }
  CODE_LO = $00401000;  CODE_HI = $00468000;
  PTRS_LO = $0046C400;  PTRS_HI = $0046D400;
  { Include the sound table as well as the handler-table run. }
  { The run of table bodies does not stop at 0x0046C400 - bodies and pointer
    globals interleave above it, and type 57's hatch table is at 0x0046C460.
    Widening the body window only ADDS starts above every base already pinned,
    so it cannot change an extent that already passed. }
  BODY_LO = $00468000;  BODY_HI = $0046D400;
var
  Exe: TMemoryStream;
  ExeName: string;
  Buf: array of Cardinal;
  Starts: array of Cardinal;
  I, J, K, Bad, Got, Swept, N: Integer;
  Code: array of Byte;
  Op, Op2: array[0..1] of Byte;
  Init, Ctr, Held: Cardinal;
  V, Next: Cardinal;

  { The smallest table start strictly greater than Base. }
  function Successor(Base: Cardinal): Cardinal;
  var
    N: Integer;
  begin
    Result := High(Cardinal);
    for N := 0 to High(Starts) do
      if (Starts[N] > Base) and (Starts[N] < Result) then
        Result := Starts[N];
  end;

  { Ints is the stored extent. WantCount is the reachable prefix. }
  procedure Pin(const Name: string; Base: Cardinal; Ints: Integer;
                Want: PInteger; WantCount: Integer);
  var
    Vals: array of Integer;
    N: Integer;
    IsStart: Boolean;
  begin
    Inc(Swept);
    IsStart := False;
    for N := 0 to High(Starts) do
      if Starts[N] = Base then IsStart := True;
    if not IsStart then
    begin
      Log.Add(Format('  %s: 0x%.6X is not the target of any pointer global, '
        + 'so nothing pins its front', [Name, Base]));
      Inc(Bad);
      Exit;
    end;

    if Successor(Base) <> Base + Cardinal(Ints) * 4 then
    begin
      Log.Add(Format('  %s: claims %d ints, but the next table starts at '
        + '0x%.6X, not 0x%.6X',
        [Name, Ints, Successor(Base), Base + Cardinal(Ints) * 4]));
      Inc(Bad);
      Exit;
    end;

    if WantCount > Ints then
    begin
      Log.Add(Format('  %s: %d values recorded but the table holds only %d',
        [Name, WantCount, Ints]));
      Inc(Bad);
      Exit;
    end;

    SetLength(Vals, Ints);
    Exe.Position := Int64(Base) - DATA_VA_BIAS;
    Exe.ReadBuffer(Vals[0], Ints * SizeOf(Integer));
    for N := 0 to WantCount - 1 do
      if Vals[N] <> PInteger(PtrUInt(Want) + PtrUInt(N * SizeOf(Integer)))^ then
      begin
        Log.Add(Format('  %s: entry %d is %d in the exe, %d here',
          [Name, N, Vals[N],
           PInteger(PtrUInt(Want) + PtrUInt(N * SizeOf(Integer)))^]));
        Inc(Bad);
      end;
  end;

  { A table whose handler reads only element 0, recorded as a scalar. }
  procedure PinOne(const Name: string; Base: Cardinal; Ints, Want: Integer);
  begin
    Pin(Name, Base, Ints, @Want, 1);
  end;

  procedure CheckTable(const Name: string; Ptr, Base: Cardinal; Ints: Integer);
  var
    Held, Want: Cardinal;
  begin
    Exe.Position := Int64(Ptr) - DATA_VA_BIAS;
    Exe.ReadBuffer(Held, SizeOf(Held));
    if Held <> Base then
    begin
      Log.Add(Format('  %s: [0x%.6X] holds 0x%.6X, not 0x%.6X',
        [Name, Ptr, Held, Base]));
      Inc(Bad);
    end;
    Want := Base + Cardinal(Ints) * 4;
    if Successor(Base) <> Want then
    begin
      Log.Add(Format('  %s: claims %d ints, but the next table starts at '
        + '0x%.6X, not 0x%.6X', [Name, Ints, Successor(Base), Want]));
      Inc(Bad);
    end;
  end;

begin
  Result := 0;
  Log.Add('');
  Log.Add('--- the sprite tables at 0x0046BDA0 and their extents ---');

  Exe := TMemoryStream.Create;
  try
    ExeName := OriginalExe(GameDir);
    if not FileExists(ExeName) then
    begin
      Log.Add('FAILED: akuji.exe is not in the game directory');
      Exit(1);
    end;
    Exe.LoadFromFile(ExeName);

    { Every pointer global into the region, read out of the binary. }
    SetLength(Buf, (PTRS_HI - PTRS_LO) div 4);
    Exe.Position := Int64(PTRS_LO) - DATA_VA_BIAS;
    Exe.ReadBuffer(Buf[0], Length(Buf) * SizeOf(Cardinal));
    SetLength(Starts, 0);
    for I := 0 to High(Buf) do
    begin
      V := Buf[I];
      if (V < BODY_LO) or (V >= BODY_HI) then
        Continue;
      K := -1;
      for J := 0 to High(Starts) do
        if Starts[J] = V then K := J;
      if K < 0 then
      begin
        SetLength(Starts, Length(Starts) + 1);
        Starts[High(Starts)] := V;
      end;
    end;
    Log.Add(Format('%d distinct table starts between 0x%.6X and 0x%.6X',
      [Length(Starts), BODY_LO, BODY_HI]));
    if Length(Starts) < 20 then
    begin
      Log.Add('FAILED: too few table starts found - the scan window is wrong '
        + 'and every extent below would pass vacuously');
      Inc(Result);
    end;

    Bad := 0;
    CheckTable('type 14', MANA_SPRITE_TABLE_PTR, MANA_SPRITE_TABLE_ADDR,
               MANA_VARIANTS * MANA_FRAMES);
    CheckTable('type 24', ITEM24_TABLE_PTR, ITEM24_TABLE_ADDR, ITEM24_VARIANTS);
    CheckTable('type 24 beat', ITEM24_BEAT_PTR, ITEM24_BEAT_ADDR,
               ITEM24_BEAT_FRAMES);
    CheckTable('type 25', ITEM25_TABLE_PTR, ITEM25_TABLE_ADDR, ITEM25_VARIANTS);
    CheckTable('type 27', SAVE_POINT_PTR, SAVE_POINT_ADDR, SAVE_POINT_FRAMES);
    Log.Add(Format('four tables, pointer and extent: %d wrong', [Bad]));
    Inc(Result, Bad);

    { --- every table any handler records an address for -------------------
      Generated once from the binary and kept by hand since. A new handler
      adds its line here; a table with no line here is a table whose length
      nothing checks. }
    Bad := 0;
    Swept := 0;
    Pin('type 14 sprites', MANA_SPRITE_TABLE_ADDR, 8, @MANA_SPRITES[0][0], 8);
    Pin('type 24 sprites', ITEM24_TABLE_ADDR, 16, @ITEM24_SPRITES[0], 16);
    Pin('type 24 beat', ITEM24_BEAT_ADDR, 2, @ITEM24_BEAT_SPRITES[0], 2);
    Pin('type 25 sprites', ITEM25_TABLE_ADDR, 3, @ITEM25_SPRITES[0], 3);
    Pin('type 27 sprites', SAVE_POINT_ADDR, 2, @SAVE_POINT_SPRITES[0], 2);
    Pin('drop sprites', DROP_TABLE_ADDR, 2, @DROP_SPRITES[0], 2);
    Pin('type 2 sprites', T2_TABLE_ADDR, 12, @T2_SPRITES[0][0], 12);
    Pin('type 3 sprites', T3_TABLE_ADDR, 6, @T3_SPRITES[0][0], 6);
    Pin('type 4 sprites', T4_TABLE_ADDR, 2, @T4_SPRITES[0], 2);
    Pin('type 5 sprites', T5_TABLE_ADDR, 4, @T5_SPRITES[0], 4);
    Pin('type 6 sprites', T6_TABLE_ADDR, 8, @T6_SPRITES[0][0], 8);
    Pin('type 7 sprites', T7_TABLE_ADDR, 8, @T7_SPRITES[0][0], 8);
    Pin('type 8 sprites', TYPE8_TABLE_ADDR, 4, @TYPE8_SPRITES[0], 4);
    PinOne('type 9 sprite', T9_TABLE_ADDR, 1, T9_SPRITE);
    Pin('type 10 sprites', T10_TABLE_ADDR, 6, @T10_SPRITES[0], 6);
    Pin('type 11 sprites', T11_TABLE_ADDR, 4, @T11_SPRITES[0], 4);
    Pin('type 12 sprites', T12_TABLE_ADDR, 4, @T12_SPRITES[0], 4);
    Pin('type 13 splash', T13_SPLASH_TABLE_ADDR, 3, @T13_SPLASH_SPRITES[0], 3);
    Pin('type 13 shard 3', T13_SHARD3_TABLE_ADDR, 12,
        @T13_SHARD3_SPRITES[0], 12);
    PinOne('type 13 state 2', T13_STATE2_TABLE_ADDR, 2, T13_STATE2_SPRITE);
    Pin('type 13 shard 4', T13_SHARD4_TABLE_ADDR, 12,
        @T13_SHARD4_SPRITES[0], 12);
    PinOne('type 13 state 3', T13_STATE3_TABLE_ADDR, 5, T13_STATE3_SPRITE);
    Pin('type 15 sprites', T15_TABLE_ADDR, 2, @T15_SPRITES[0], 2);
    PinOne('type 16 sign', SIGN_SPRITE_ADDR, 1, SIGN_SPRITE);
    PinOne('type 21 sprite', T21_TABLE_ADDR, 1, T21_SPRITE);
    PinOne('type 22 sprite', TYPE22_SPRITE_ADDR, 1, TYPE22_SPRITE);
    PinOne('type 23 sprite', T23_TABLE_ADDR, 1, T23_SPRITE);
    Pin('type 26 sprites', TYPE26_TABLE_ADDR, 4, @TYPE26_SPRITES[0], 4);
    Pin('type 28 sprites', T28_TABLE_ADDR, 4, @T28_SPRITES[0], 4);
    Pin('type 29 sprites', T29_TABLE_ADDR, 4, @T29_SPRITES[0], 4);
    Pin('type 30 sprites', T30_TABLE_ADDR, 4, @T30_SPRITES[0][0], 4);
    Pin('type 31 sprites', T31_TABLE_ADDR, 5, @T31_SPRITES[0], 5);
    Pin('type 31 hp bonus', T31_HP_BONUS_ADDR, 3, @T31_HP_BONUS[0], 3);
    Pin('type 31 wait', T31_WAIT_ADDR, 3, @T31_WAIT[0], 3);
    Pin('type 31 rate', T31_RATE_ADDR, 3, @T31_RATE[0], 3);
    Pin('type 33 sprites', BOOM_TABLE_ADDR, 6, @BOOM_SPRITES[0], 6);
    Pin('type 34 sprites', T34_TABLE_ADDR, 5, @T34_SPRITES[0], 5);
    Pin('type 34 rate', T34_RATE_ADDR, 3, @T34_RATE[0], 3);
    Pin('type 35 sprites', T35_TABLE_ADDR, 8, @T35_SPRITES[0], 8);
    { six ints, five reachable - the sixth is behind a mod 5 }
    Pin('type 37 sprites', T37_TABLE_ADDR, 6, @T37_SPRITES[0], T37_FRAMES);
    Pin('type 38 sprites', T38_TABLE_ADDR, 8, @T38_SPRITES[0][0], 8);
    Pin('type 38 wait', T38_WAIT_ADDR, 3, @T38_WAIT[0], 3);
    Pin('type 39 sprites', T39_TABLE_ADDR, 10, @T39_SPRITES[0], 10);
    Pin('type 39 speed', T39_SPEED_ADDR, 3, @T39_SPEED[0], 3);
    Pin('type 39 wind', T39_WIND_ADDR, 3, @T39_WIND[0], 3);
    Pin('type 40 sprites', T40_TABLE_ADDR, 8, @T40_SPRITES[0][0], 8);
    Pin('type 40 cooldown', T40_COOLDOWN_ADDR, 3, @T40_COOLDOWN[0], 3);
    Pin('type 41 sprites', T41_TABLE_ADDR, 6, @T41_SPRITES[0], 6);
    Pin('type 41 wait', T41_WAIT_ADDR, 3, @T41_WAIT[0], 3);
    Pin('type 42 rise len', T42_RISE_LEN_ADDR, 3, @T42_RISE_LEN[0], 3);
    Pin('type 42 recover', T42_RECOVER_ADDR, 3, @T42_RECOVER[0], 3);
    Pin('type 42 shots', T42_SHOTS_ADDR, 3, @T42_SHOTS[0], 3);
    Pin('type 42 hp bonus', T42_HP_BONUS_ADDR, 3, @T42_HP_BONUS[0], 3);
    Pin('type 42 sprites', T42_TABLE_ADDR, 7, @T42_SPRITES[0], 7);
    Pin('type 42 angles', T42_ANGLES_ADDR, 6, @T42_ANGLES[0], 6);
    Pin('type 43 sprites', T43_TABLE_ADDR, 4, @T43_SPRITES[0], 4);
    Pin('type 44 sprites', T44_TABLE_ADDR, 8, @T44_SPRITES[0], 8);
    Pin('type 45 sprites', T45_TABLE_ADDR, 5, @T45_SPRITES[0], 5);
    Pin('type 45 tough', T45_TOUGH_ADDR, 3, @T45_TOUGH[0], 3);
    Pin('type 46 sprites', T46_TABLE_ADDR, 5, @T46_SPRITES[0], 5);
    Pin('type 46 range', T46_RANGE_ADDR, 3, @T46_RANGE[0], 3);
    Pin('type 46 turn', T46_TURN_ADDR, 3, @T46_TURN[0], 3);
    Pin('type 46 speed', T46_SPEED_ADDR, 3, @T46_SPEED[0], 3);
    Pin('type 47 sprites', T47_TABLE_ADDR, 5, @T47_SPRITES[0], 5);
    Pin('type 47 wait', T47_WAIT_ADDR, 3, @T47_WAIT[0], 3);
    Pin('type 47 rest', T47_REST_ADDR, 3, @T47_REST[0], 3);
    { four ints, two reachable - the spawn loop counts down from 2 }
    Pin('type 47 angles', T47_ANGLES_ADDR, 4, @T47_ANGLES[0], 2);
    Pin('type 48 sprites', T48_TABLE_ADDR, 4, @T48_SPRITES[0], 4);
    Pin('type 49 sprites', T49_TABLE_ADDR, 4, @T49_SPRITES[0], 4);
    Pin('type 49 range', T49_RANGE_ADDR, 3, @T49_RANGE[0], 3);
    Pin('type 49 rest', T49_REST_ADDR, 3, @T49_REST[0], 3);
    Pin('type 50 sprites', T50_TABLE_ADDR, 6, @T50_SPRITES[0], 6);
    Pin('type 50 patrol', T50_PATROL_ADDR, 3, @T50_PATROL[0], 3);
    Pin('type 50 hold', T50_HOLD_ADDR, 3, @T50_HOLD[0], 3);
    Pin('type 51 sprites', T51_TABLE_ADDR, 4, @T51_SPRITES[0], 4);
    Pin('type 52 hp', T52_HP_ADDR, 3, @T52_HP[0], 3);
    Pin('type 52 count', T52_COUNT_ADDR, 3, @T52_COUNT[0], 3);
    Pin('type 52 speed', T52_SPEED_ADDR, 3, @T52_SPEED[0], 3);
    Pin('type 52 timing', T52_TIMING_ADDR, 3, @T52_TIMING[0], 3);
    Pin('type 52 sprites', T52_TABLE_ADDR, 8, @T52_SPRITES[0][0], 8);
    Pin('type 53 sprites', T53_TABLE_ADDR, 10, @T53_SPRITES[0][0], 10);
    Pin('type 54 sprites', T54_TABLE_ADDR, 2, @T54_SPRITES[0], 2);
    Pin('type 54 hp', T54_HP_ADDR, 3, @T54_HP[0], 3);
    Pin('type 54 hops', T54_HOP_ADDR, 8, @T54_HOP[0][0], 8);
    Pin('type 55 fly sprites', T55_FLY_TABLE_ADDR, 8, @T55_FLY_SPRITES[0], 8);
    Pin('type 55 trail sprites', T55_TRAIL_TABLE_ADDR, 7,
        @T55_TRAIL_SPRITES[0], 7);
    Pin('type 56 sprites', T56_TABLE_ADDR, 3, @T56_SPRITES[0], 3);
    Pin('type 56 skew', T56_SKEW_ADDR, 3, @T56_SKEW[0], 3);
    Pin('type 56 count', T56_COUNT_ADDR, 3, @T56_COUNT[0], 3);
    Pin('type 56 speed', T56_SPEED_ADDR, 3, @T56_SPEED[0], 3);
    { three ints - frame 2 is the dormant sprite, 0 and 1 the awake pair }
    Pin('type 57 v0 sprites', T57_V0_TABLE_ADDR, 4, @T57_V0_SPRITES[0], 4);
    Pin('type 57 v1 sprites', T57_V1_TABLE_ADDR, 8, @T57_V1_SPRITES[0], 8);
    Pin('type 57 v2 sprites', T57_V2_TABLE_ADDR, 8, @T57_V2_SPRITES[0], 8);
    Pin('type 57 v3 sprites', T57_V3_TABLE_ADDR, 3, @T57_V3_SPRITES[0], 3);
    Pin('type 57 hatch', T57_V3_HATCH_ADDR, 3, @T57_V3_HATCH[0], 3);
    Pin('type 58 sprites', T58_TABLE_ADDR, 3, @T58_SPRITES[0], 3);
    Pin('type 59 sprites', T59_TABLE_ADDR, 6, @T59_SPRITES[0], 6);
    Pin('type 59 speed', T59_SPEED_ADDR, 3, @T59_SPEED[0], 3);
    Pin('type 60 sprites', T60_TABLE_ADDR, 8, @T60_SPRITES[0][0], 8);
    Pin('type 60 speed', T60_SPEED_ADDR, 3, @T60_SPEED[0], 3);
    Pin('type 60 rage', T60_RAGE_ADDR, 3, @T60_RAGE[0], 3);
    Pin('type 60 turn', T60_TURN_ADDR, 3, @T60_TURN[0], 3);
    Pin('type 61 sprites', T61_TABLE_ADDR, 4, @T61_SPRITES[0], 4);
    Pin('type 61 speed', T61_SPEED_ADDR, 3, @T61_SPEED[0], 3);
    Pin('type 62 sprites', T62_TABLE_ADDR, 4, @T62_SPRITES[0][0], 4);
    Pin('type 62 speed', T62_SPEED_ADDR, 3, @T62_SPEED[0], 3);
    Pin('type 63 sprites', T63_TABLE_ADDR, 8, @T63_SPRITES[0][0], 8);
    Pin('type 63 shot speed', T63_SHOT_SPD_ADDR, 3, @T63_SHOT_SPD[0], 3);
    Pin('type 63 fire at', T63_FIRE_AT_ADDR, 3, @T63_FIRE_AT[0], 3);
    Pin('type 63 recover', T63_RECOVER_ADDR, 3, @T63_RECOVER[0], 3);
    Pin('type 63 cooldown', T63_COOLDOWN_ADDR, 3, @T63_COOLDOWN[0], 3);
    Pin('type 64 sprites', T64_TABLE_ADDR, 2, @T64_SPRITES[0], 2);
    Pin('type 64 wait', T64_WAIT_ADDR, 3, @T64_WAIT[0], 3);
    Pin('type 64 rest', T64_REST_ADDR, 3, @T64_REST[0], 3);
    Pin('type 64 rise', T64_RISE_ADDR, 3, @T64_RISE[0], 3);
    Pin('type 65 sprites', T65_TABLE_ADDR, 2, @T65_SPRITES[0], 2);
    Pin('type 65 hops', T65_HOP_ADDR, 2, @T65_HOP[0], 2);
    Pin('type 66 anchor sprites', T66_V0_TABLE_ADDR, 3, @T66_V0_SPRITES[0], 3);
    Pin('type 66 satellite sprites', T66_V1_TABLE_ADDR, 2,
        @T66_V1_SPRITES[0], 2);
    Pin('type 67 sprites', T67_TABLE_ADDR, 5, @T67_SPRITES[0], 5);
    Pin('type 67 cooldown', T67_COOLDOWN_ADDR, 3, @T67_COOLDOWN[0], 3);
    Pin('type 67 range', T67_RANGE_ADDR, 3, @T67_RANGE[0], 3);
    Pin('type 68 sprites', T68_TABLE_ADDR, 8, @T68_SPRITES[0], 8);
    Pin('type 68 insets', T68_INSET_ADDR, 8, @T68_INSET[0], 8);
    Pin('type 69 sprites', T69_TABLE_ADDR, 4, @T69_SPRITES[0], 4);
    Pin('type 70 v0 sprites', T70_V0_TABLE_ADDR, 5, @T70_V0_SPRITES[0], 5);
    Pin('type 70 v1 sprites', T70_V1_TABLE_ADDR, 5, @T70_V1_SPRITES[0], 5);
    Pin('type 71 sprites', T71_TABLE_ADDR, 12, @T71_SPRITES[0][0], 12);
    Pin('type 71 walk', T71_WALK_ADDR, 3, @T71_WALK[0], 3);
    Pin('type 71 rest', T71_REST_ADDR, 3, @T71_REST[0], 3);
    Pin('type 72 faller sprites', T72_V0_TABLE_ADDR, 8, @T72_V0_SPRITES[0], 8);
    Pin('type 72 flyer sprites', T72_V1_TABLE_ADDR, 16, @T72_V1_SPRITES[0], 16);
    Pin('type 72 speed', T72_SPEED_ADDR, 3, @T72_SPEED[0], 3);
    Pin('type 72 trail rate', T72_TRAIL_ADDR, 3, @T72_TRAIL[0], 3);
    Pin('type 72 trail sprites', T72_V2_TABLE_ADDR, 4, @T72_V2_SPRITES[0], 4);
    Pin('type 73 sprites', T73_TABLE_ADDR, 5, @T73_SPRITES[0], 5);
    Pin('type 73 wait', T73_WAIT_ADDR, 3, @T73_WAIT[0], 3);
    Pin('type 73 charge', T73_CHARGE_ADDR, 3, @T73_CHARGE[0], 3);
    Pin('type 74 charge sprites', T74_V0_TABLE_ADDR, 5, @T74_V0_SPRITES[0], 5);
    Pin('type 74 shot sprites', T74_V1_TABLE_ADDR, 4, @T74_V1_SPRITES[0], 4);
    Pin('type 74 skew', T74_SKEW_ADDR, 3, @T74_SKEW[0], 3);
    Pin('type 74 count', T74_COUNT_ADDR, 3, @T74_COUNT[0], 3);
    Pin('type 74 speed', T74_SPEED_ADDR, 3, @T74_SPEED[0], 3);
    Pin('type 75 sprites', T75_TABLE_ADDR, 8, @T75_SPRITES[0], 8);
    Pin('type 76 sprites', T76_TABLE_ADDR, 2, @T76_SPRITES[0], 2);
    Pin('type 76 period', T76_PERIOD_ADDR, 3, @T76_PERIOD[0], 3);
    Pin('type 76 speed', T76_SPEED_ADDR, 3, @T76_SPEED[0], 3);
    { The final boss. Each phase's sprite row is exactly as wide as the
      highest frame that phase's own script can reach - the check below
      re-derives that from the action table, so the two readings have to keep
      agreeing. }
    Pin('type 77 phase 0-1', T77_P01_TABLE_ADDR, 20, @T77_P01_SPRITES[0][0], 20);
    Pin('type 77 phase 2', T77_P2_TABLE_ADDR, 28, @T77_P2_SPRITES[0][0], 28);
    Pin('type 77 phase 3', T77_P3_TABLE_ADDR, 26, @T77_P3_SPRITES[0][0], 26);
    Pin('type 77 phase 4', T77_P4_TABLE_ADDR, 12, @T77_P4_SPRITES[0][0], 12);
    Pin('type 77 phase 5', T77_P5_TABLE_ADDR, 16, @T77_P5_SPRITES[0][0], 16);
    Pin('type 77 phase 6', T77_P6_TABLE_ADDR, 2, @T77_P6_SPRITES[0], 2);
    Pin('type 77 hp', T77_HP_ADDR, 18, @T77_HP[0][0], 18);
    Pin('type 77 burst vx', T77_BURST_VX_ADDR, 6, @T77_BURST_VX[0], 6);
    Pin('type 77 burst vy', T77_BURST_VY_ADDR, 6, @T77_BURST_VY[0], 6);
    Pin('type 77 burst count', T77_BURST_ADDR, 3, @T77_BURST[0], 3);
    Pin('type 77 slam', T77_SLAM_ADDR, 4, @T77_SLAM[0], 4);
    Pin('type 77 lob', T77_SHOT_ADDR, 3, @T77_SHOT[0], 3);
    Pin('type 77 step', T77_STEP_ADDR, 36, @T77_STEP[0][0], 36);
    Pin('type 77 action', T77_ACTION_ADDR, 36, @T77_ACTION[0][0], 36);
    Pin('type 77 divisor', T77_DIVISOR_ADDR, 3, @T77_DIVISOR[0], 3);
    Pin('type 77 slam divisor', T77_SLAM_DIV_ADDR, 3, @T77_SLAM_DIV[0], 3);
    Pin('type 77 lob divisor', T77_SHOT_DIV_ADDR, 3, @T77_SHOT_DIV[0], 3);
    Pin('type 77 lob speed', T77_LOB_SPEED_ADDR, 3, @T77_LOB_SPEED[0], 3);
    Pin('type 78 idle sprite', T78_IDLE_TABLE_ADDR, 2, @T78_IDLE_SPRITES[0], 2);
    Pin('type 78 idle x', T78_IDLE_X_ADDR, 2, @T78_IDLE_X[0], 2);
    Pin('type 78 slam sprites', T78_SLAM_TABLE_ADDR, 8,
        @T78_SLAM_SPRITES[0][0], 8);
    Pin('type 78 slam x', T78_SLAM_X_ADDR, 8, @T78_SLAM_X[0][0], 8);
    Pin('type 78 slam y', T78_SLAM_Y_ADDR, 4, @T78_SLAM_Y[0], 4);
    Pin('type 78 lob sprites', T78_LOB_TABLE_ADDR, 6, @T78_LOB_SPRITES[0][0], 6);
    Pin('type 78 lob x', T78_LOB_X_ADDR, 6, @T78_LOB_X[0][0], 6);
    Pin('type 78 lob y', T78_LOB_Y_ADDR, 3, @T78_LOB_Y[0], 3);
    Pin('type 79 v0 sprites', T79_V0_TABLE_ADDR, 2, @T79_V0_SPRITES[0], 2);
    Pin('type 79 v0 x', T79_V0_X_ADDR, 2, @T79_V0_X[0], 2);
    Pin('type 79 v1 sprites', T79_V1_TABLE_ADDR, 2, @T79_V1_SPRITES[0], 2);
    Pin('type 79 v1 x', T79_V1_X_ADDR, 2, @T79_V1_X[0], 2);
    Pin('type 79 v1 y', T79_V1_Y_ADDR, 1, @T79_V1_Y[0], 1);
    Pin('type 79 v2 sprites', T79_V2_TABLE_ADDR, 2, @T79_V2_SPRITES[0], 2);
    Pin('type 79 v2 x', T79_V2_X_ADDR, 2, @T79_V2_X[0], 2);
    Pin('type 79 v2 y', T79_V2_Y_ADDR, 1, @T79_V2_Y[0], 1);
    Pin('type 79 v3 sprites', T79_V3_TABLE_ADDR, 4, @T79_V3_SPRITES[0][0], 4);
    Pin('type 79 v4 sprites', T79_V4_TABLE_ADDR, 4, @T79_V4_SPRITES[0], 4);
    Pin('type 79 v5 sprites', T79_V5_TABLE_ADDR, 6, @T79_V5_SPRITES[0], 6);
    Pin('type 80 v0 sprites', T80_V0_TABLE_ADDR, 3, @T80_V0_SPRITES[0], 3);
    Pin('type 80 v1 sprites', T80_V1_TABLE_ADDR, 4, @T80_V1_SPRITES[0], 4);
    Pin('hit sounds', HIT_SOUND_ADDR, 4, @HIT_SOUNDS[0], HIT_SOUND_COUNT);
    Log.Add(Format('the whole sweep - %d tables, extent and values: %d wrong',
      [Swept, Bad]));
    Inc(Result, Bad);

    { Validate the fifteen compiler-emitted unit initialization/finalization
      pairs and their write-only counters against the reference image. }
    Bad := 0;
    if not FileExists(ExeName) then Inc(Bad);
    SetLength(Code, CODE_HI - CODE_LO);
    Exe.Position := Int64(CODE_LO) - CODE_VA_BIAS;
    Exe.ReadBuffer(Code[0], Length(Code));
    for I := 0 to UNIT_INIT_COUNT - 1 do
    begin
      Init := UNIT_INIT_ADDR[I];
      Ctr  := UNIT_INIT_COUNTER[I];

      { the initialization half: `inc dword ptr [counter]` at +0x11 }
      Exe.Position := Int64(Init) + $11 - CODE_VA_BIAS;
      Exe.ReadBuffer(Op, 2);
      Exe.ReadBuffer(Held, 4);
      if (Op[0] <> $FF) or (Op[1] <> $05) or (Held <> Ctr) then
      begin
        Log.Add(Format('  unit %d at 0x%.6X: not an inc of 0x%.6X',
          [I, Init, Ctr]));
        Inc(Bad);
      end;

      { the finalization half: `sub dword ptr [counter], 1` then `ret` }
      Exe.Position := Int64(Init) + UNIT_INIT_STUB_GAP - CODE_VA_BIAS;
      Exe.ReadBuffer(Op, 2);
      Exe.ReadBuffer(Held, 4);
      Exe.ReadBuffer(Op2, 2);
      if (Op[0] <> $83) or (Op[1] <> $2D) or (Held <> Ctr)
         or (Op2[0] <> $01) or (Op2[1] <> $C3) then
      begin
        Log.Add(Format('  unit %d at 0x%.6X: finalization is not a dec of '
          + '0x%.6X followed by ret', [I, Init + UNIT_INIT_STUB_GAP, Ctr]));
        Inc(Bad);
      end;

      { and the counter is WRITE-ONLY: its address appears in the code
        section exactly twice, which is those two instructions and nothing
        else. This is the claim that makes the stubs safe to ignore. }
      N := 0;
      for J := 0 to Length(Code) - 4 do
        if PCardinal(@Code[J])^ = Ctr then Inc(N);
      if N <> 2 then
      begin
        Log.Add(Format('  counter 0x%.6X is referenced %d times in the code '
          + 'section, not 2 - something reads it', [Ctr, N]));
        Inc(Bad);
      end;
    end;

    { the table itself ends where UnitInit.pas says, and its last entry is a
      pair like all the others }
    Exe.Position := Int64(UNIT_INIT_TABLE_END) - CODE_VA_BIAS;
    Exe.ReadBuffer(Held, 4);
    if Held <> 0 then
    begin
      Log.Add(Format('  the init table does not terminate at 0x%.6X',
        [UNIT_INIT_TABLE_END]));
      Inc(Bad);
    end;
    Exe.Position := Int64(UNIT_INIT_TABLE_END) - 8 - CODE_VA_BIAS;
    Exe.ReadBuffer(Held, 4);
    Exe.ReadBuffer(V, 4);
    if (Held - V <> UNIT_INIT_STUB_GAP)
       or (V <> UNIT_INIT_ADDR[UNIT_INIT_COUNT - 1]) then
    begin
      Log.Add('  the last table entry is not the last recorded unit');
      Inc(Bad);
    end;

    if Bad = 0 then
      Log.Add(Format('%d unit init/finalize pairs, all one shape, every '
        + 'counter write-only', [UNIT_INIT_COUNT]));
    Inc(Result, Bad);

    { --- the final boss's rows are as wide as its script needs -------------
      Two facts pinned independently: the sprite row widths come from the
      binary's pointer layout, and the reachable frames come from the action
      table's own values. Nothing connects them except the claim in
      EntityHandlers.pas that each phase's row is exactly as wide as the
      highest frame that phase's script can reach. That is checked here.

      HIGHEST_FRAME_OF maps each action to the top frame it can produce; the
      state-1 idle contributes 1 to every phase. Phase 0 is exempt because it
      SHARES phase 1's table and therefore has slack. }
    Bad := 0;
    for I := 0 to T77_PHASES - 1 do
    begin
      Got := 1;                          { the idle animation, frames 0..1 }
      for J := 0 to T77_STEPS - 1 do
      begin
        case T77_ACTION[I][J] of
          0, 2: K := 1;
          3, 7: K := 5;
          4:    K := 9;
          5:    K := 12;
          6:    K := 13;
          8:    K := 7;
        else
          K := -1;
          Log.Add(Format('  type 77 phase %d step %d: unknown action %d',
            [I, J, T77_ACTION[I][J]]));
          Inc(Bad);
        end;
        if K > Got then Got := K;
      end;

      case I of
        0: N := High(T77_P01_SPRITES[0]);
        1: N := High(T77_P01_SPRITES[0]);
        2: N := High(T77_P2_SPRITES[0]);
        3: N := High(T77_P3_SPRITES[0]);
        4: N := High(T77_P4_SPRITES[0]);
      else N := High(T77_P5_SPRITES[0]);
      end;

      if I = 0 then
      begin
        if Got > N then
        begin
          Log.Add(Format('  type 77 phase 0 reaches frame %d, past the %d it '
            + 'shares with phase 1', [Got, N]));
          Inc(Bad);
        end;
      end
      else if Got <> N then
      begin
        Log.Add(Format('  type 77 phase %d reaches frame %d but its row ends '
          + 'at %d', [I, Got, N]));
        Inc(Bad);
      end;
    end;
    if Bad = 0 then
      Log.Add('type 77: five of six phase rows end exactly where the script '
        + 'stops reaching, and phase 0 fits inside phase 1''s');
    Inc(Result, Bad);

    { --- claims of the form "these two tables hold the same numbers" ------
      Each table above is pinned to its own address, so these do not re-check
      the values. What they check is the RELATIONSHIP, which is stated in
      prose in EntityHandlers.pas and would otherwise rot silently if either
      side were ever corrected. }
    Bad := 0;
    for I := 0 to 2 do
    begin
      if T52_HP[I] <> T54_HP[I] then Inc(Bad);
      if T56_SKEW[I]  <> T74_SKEW[I]  then Inc(Bad);
      if T56_COUNT[I] <> T74_COUNT[I] then Inc(Bad);
      if T56_SPEED[I] <> T74_SPEED[I] then Inc(Bad);
    end;
    if Bad <> 0 then
      Log.Add(Format('FAILED: %d duplicated-table claims no longer hold', [Bad]))
    else
      Log.Add('the two boss hp tables and the two fan tables still agree');
    Inc(Result, Bad);

    { A sweep that checked nothing would also report zero wrong. }
    if Swept < 80 then
    begin
      Log.Add('FAILED: the sweep is too small to be the whole set');
      Inc(Result);
    end;


    { And the values, now that the lengths mean something. }
    Bad := 0;
    SetLength(Buf, 64);
    Exe.Position := Int64(ITEM24_TABLE_ADDR) - DATA_VA_BIAS;
    Exe.ReadBuffer(Buf[0], ITEM24_VARIANTS * SizeOf(Cardinal));
    for I := 0 to ITEM24_VARIANTS - 1 do
      if Integer(Buf[I]) <> ITEM24_SPRITES[I] then Inc(Bad);
    Exe.Position := Int64(ITEM24_BEAT_ADDR) - DATA_VA_BIAS;
    Exe.ReadBuffer(Buf[0], ITEM24_BEAT_FRAMES * SizeOf(Cardinal));
    for I := 0 to ITEM24_BEAT_FRAMES - 1 do
      if Integer(Buf[I]) <> ITEM24_BEAT_SPRITES[I] then Inc(Bad);
    Exe.Position := Int64(ITEM25_TABLE_ADDR) - DATA_VA_BIAS;
    Exe.ReadBuffer(Buf[0], ITEM25_VARIANTS * SizeOf(Cardinal));
    for I := 0 to ITEM25_VARIANTS - 1 do
      if Integer(Buf[I]) <> ITEM25_SPRITES[I] then Inc(Bad);
    Log.Add(Format('type 24 and 25 table values: %d wrong', [Bad]));
    Inc(Result, Bad);

    { Variant 8's single sprite in the flat table is the first frame of its
      two-frame one. Two tables written independently agreeing on that is what
      says variant 8 really is the entry the special case is about. }
    if ITEM24_SPRITES[ITEM24_BEAT_VARIANT] <> ITEM24_BEAT_SPRITES[0] then
    begin
      Log.Add('FAILED: variant 8 disagrees with its own animation table');
      Inc(Result);
    end;
  finally
    Exe.Free;
  end;
end;

{ --- 6. types 24 and 25 -------------------------------------------------- }
function TestItemHandlers(Log: TStringList): Integer;
var
  W: TCountingWorld;
  E: TEntity;
  I, StartY, MinY, MaxY, Beats: Integer;
  Frames: string;

  procedure Fresh(Variant: Integer);
  begin
    FillChar(E, SizeOf(E), 0);
    E.Raw[EF_ALIVE]   := 1;
    E.Raw[EF_VARIANT] := Variant;
    E.Raw[EF_POS_X]   := POSITION_BIAS;
    E.Raw[EF_POS_Y]   := POSITION_BIAS;
    W.Sounds := 0;
    W.LastSound := -1;
  end;

begin
  Result := 0;
  Log.Add('');
  Log.Add('--- types 24 and 25 ---');
  W := TCountingWorld.Create;
  try
    { Type 25 is scenery: one table lookup, and nothing else may move. }
    for I := 0 to ITEM25_VARIANTS - 1 do
    begin
      Fresh(I);
      EntityUpdate_Type25_Door(E);
      if E.Raw[EF_ANIM_ID] <> ITEM25_SPRITES[I] then
      begin
        Log.Add(Format('FAILED: type 25 variant %d gave sprite %d, want %d',
          [I, E.Raw[EF_ANIM_ID], ITEM25_SPRITES[I]]));
        Inc(Result);
      end;
      if (E.Raw[EF_POS_X] <> POSITION_BIAS)
      or (E.Raw[EF_POS_Y] <> POSITION_BIAS)
      or (E.Raw[EF_FACING] <> 0) or (E.Raw[EF_TIMER] <> 0) then
      begin
        Log.Add('FAILED: type 25 changed something other than its sprite');
        Inc(Result);
      end;
    end;
    Log.Add(Format('type 25: %d variants, sprite only', [ITEM25_VARIANTS]));

    { Type 27 alternates two frames every nine, and freezes outside play. }
    Fresh(0);
    Frames := '';
    for I := 1 to 20 do
    begin
      EntityUpdate_Type27_AkujiStatue(E, GS_PLAY);
      Frames := Frames + Format('%d', [E.Raw[EF_FLAG1C]]);
    end;
    Log.Add(Format('type 27 over 20 frames: %s', [Frames]));
    if Frames <> '00000000111111111000' then
    begin
      Log.Add('FAILED: the save point should flip every 9 frames');
      Inc(Result);
    end;
    Fresh(0);
    for I := 1 to 20 do
      EntityUpdate_Type27_AkujiStatue(E, GS_PAUSE);
    if (E.Raw[EF_FLAG1C] <> 0) or (E.Raw[EF_BLOCK_B] <> 0) then
    begin
      Log.Add('FAILED: the save point animated while the game was not in play');
      Inc(Result);
    end;
    if E.Raw[EF_ANIM_ID] <> SAVE_POINT_SPRITES[0] then
    begin
      Log.Add('FAILED: the save point should still set its sprite outside play');
      Inc(Result);
    end;

    { Type 24 bobs, and the bob CLOSES. DIR_COS sums to zero over its 64
      entries, so 64 frames of DirVelY must return the entity to exactly where
      it started - a property of the direction table, not of this handler, which
      is what makes it worth asserting. }
    Fresh(0);
    StartY := E.Raw[EF_POS_Y];
    MinY := StartY;
    MaxY := StartY;
    for I := 1 to DIR_COUNT do
    begin
      EntityUpdate_Type24_PowerOrb(E, GS_PLAY, W);
      if E.Raw[EF_POS_Y] < MinY then MinY := E.Raw[EF_POS_Y];
      if E.Raw[EF_POS_Y] > MaxY then MaxY := E.Raw[EF_POS_Y];
    end;
    Log.Add(Format('type 24 after a full 64-frame bob: net y %d, travelled %d '
      + 'sub-pixels (%d px), facing %d',
      [E.Raw[EF_POS_Y] - StartY, MaxY - MinY,
       (MaxY - MinY) div 32, E.Raw[EF_FACING]]));
    if E.Raw[EF_POS_Y] <> StartY then
    begin
      Log.Add('FAILED: a whole period of the bob should net to zero');
      Inc(Result);
    end;
    if E.Raw[EF_FACING] <> 0 then
    begin
      Log.Add('FAILED: the phase should have wrapped back to 0');
      Inc(Result);
    end;
    { The net-to-zero above is only interesting if it moved in between. It does
      NOT move on the first frame - DirVelY(0) is DIR_COS[16], the sine's zero
      crossing - so this looks at the whole excursion rather than one step. }
    if MaxY - MinY = 0 then
    begin
      Log.Add('FAILED: the bob never moved at all');
      Inc(Result);
    end;

    { Outside GS_PLAY it sets its sprite and freezes. }
    Fresh(0);
    EntityUpdate_Type24_PowerOrb(E, GS_PAUSE, W);
    if (E.Raw[EF_POS_Y] <> POSITION_BIAS) or (E.Raw[EF_FACING] <> 0) then
    begin
      Log.Add('FAILED: type 24 bobbed while the game was not in play');
      Inc(Result);
    end;
    if E.Raw[EF_ANIM_ID] <> ITEM24_SPRITES[0] then
    begin
      Log.Add('FAILED: type 24 should still set its sprite outside play');
      Inc(Result);
    end;

    { An ordinary variant is silent and does not animate. }
    Fresh(0);
    for I := 1 to 200 do
      EntityUpdate_Type24_PowerOrb(E, GS_PLAY, W);
    if W.Sounds <> 0 then
    begin
      Log.Add(Format('FAILED: variant 0 played %d sound(s)', [W.Sounds]));
      Inc(Result);
    end;
    if E.Raw[EF_FLAG1C] <> 0 then
    begin
      Log.Add('FAILED: variant 0 should not advance a frame');
      Inc(Result);
    end;

    { Variant 8 alternates EVERY frame - its counter is compared against zero,
      so it resets on the frame it is incremented - and beats every 61. }
    Fresh(ITEM24_BEAT_VARIANT);
    Frames := '';
    for I := 1 to 6 do
    begin
      EntityUpdate_Type24_PowerOrb(E, GS_PLAY, W);
      Frames := Frames + Format('%d ', [E.Raw[EF_ANIM_ID]]);
    end;
    Log.Add(Format('type 24 variant 8, six frames: %s', [Trim(Frames)]));
    if Trim(Frames) <> '480 481 480 481 480 481' then
    begin
      Log.Add('FAILED: variant 8 should alternate every single frame');
      Inc(Result);
    end;

    Fresh(ITEM24_BEAT_VARIANT);
    for I := 1 to 610 do
      EntityUpdate_Type24_PowerOrb(E, GS_PLAY, W);
    Beats := W.Sounds;
    Log.Add(Format('type 24 variant 8 over 610 frames: %d heartbeat(s), '
      + 'last sound %d (%s)', [Beats, W.LastSound,
      SoundNames[W.LastSound]]));
    if Beats <> 10 then
    begin
      Log.Add('FAILED: want 10 beats - one every 61 frames');
      Inc(Result);
    end;
    if W.LastSound <> SND_KODOU then
    begin
      Log.Add('FAILED: the beat should be kodou.wav');
      Inc(Result);
    end;
  finally
    W.Free;
  end;
end;

{ --- Entity_TouchPickup / Entity_TouchHeal @ 0x00458274 / 0x00458490 -----

  The Mana Stone's own arithmetic. The interesting boundary is that the
  counter goes up BEFORE the target is compared, so a stone that lands you
  exactly on the target counts as reaching it - which is the difference
  between < and <= and is worth a case of its own. }
function TestTouchHandlers(Log: TStringList): Integer;
var
  W: TCountingWorld;
  Pool: TEntityPool;
  P: TPlayerState;
  Slot, Fx: Integer;

  procedure Fresh(Variant, Counter, TargetIdx: Integer);
  begin
    Pool.Clear;
    FillChar(P, SizeOf(P), 0);
    P.Counter := Counter;
    P.TargetIndex := TargetIdx;
    P.Lives := 1;
    P.MaxLives := 3;
    Slot := Pool.Spawn(EKIND_MINOR, 5, 0, 0);
    Pool.SetField(Slot, EF_VARIANT, Variant);
    Pool.SetField(Slot, EF_SPRITE, SPRITE_NONE);
    Pool.SetField(Slot, EF_EVENT_ID, 7);
    W.Sounds := 0;
    W.LastSound := -1;
    W.ProgressSet := '';
    W.FlagFor := 42;
  end;

  function EffectVariant: Integer;
  var
    I: Integer;
  begin
    Result := -1;
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = PICKUP_EFFECT_TYPE) then
        Exit(Pool.Field(I, EF_VARIANT));
  end;

begin
  Result := 0;
  Log.Add('');
  Log.Add('--- Entity_TouchPickup / Entity_TouchHeal ---');
  Pool := TEntityPool.Create;
  W := TCountingWorld.Create;
  try
    W.Pool := Pool;

    { A small stone is worth one, a large one ten, and neither reaches the
      first goal of 20 from zero. }
    Fresh(0, 0, 0);
    EntityTouchPickup(Pool.Entity(Slot)^, P, W);
    Fx := EffectVariant;
    Log.Add(Format('small stone: counter %d, sound %d (%s), effect variant %d, '
      + 'flags [%s]', [P.Counter, W.LastSound, SoundNames[W.LastSound], Fx,
      Trim(W.ProgressSet)]));
    if P.Counter <> MANA_SMALL then
    begin
      Log.Add('FAILED: a variant 0 stone is worth one');
      Inc(Result);
    end;
    if W.LastSound <> SND_GET01 then
    begin
      Log.Add('FAILED: a small stone is get01');
      Inc(Result);
    end;
    if Fx <> PICKUP_FX_NORMAL then
    begin
      Log.Add('FAILED: the effect should be the plain one');
      Inc(Result);
    end;
    if Trim(W.ProgressSet) <> '42' then
    begin
      Log.Add('FAILED: the event''s progress flag should be set');
      Inc(Result);
    end;
    if P.MaxLives <> 3 then
    begin
      Log.Add('FAILED: no level-up was due');
      Inc(Result);
    end;

    Fresh(1, 0, 0);
    EntityTouchPickup(Pool.Entity(Slot)^, P, W);
    if (P.Counter <> MANA_LARGE) or (W.LastSound <> SND_GET02) then
    begin
      Log.Add('FAILED: a variant 1 stone is worth ten, and is get02');
      Inc(Result);
    end;

    { EXACTLY reaching the target counts, because the counter is raised
      before the comparison. One below it does not. }
    Fresh(0, MANA_TARGETS[0] - 1, 0);
    EntityTouchPickup(Pool.Entity(Slot)^, P, W);
    Log.Add(Format('stone landing exactly on goal %d: lives %d/%d, target now '
      + '%d, sound %s, effect %d',
      [MANA_TARGETS[0], P.Lives, P.MaxLives, P.TargetIndex,
       SoundNames[W.LastSound], EffectVariant]));
    if (P.TargetIndex <> 1) or (P.MaxLives <> 4) or (P.Lives <> 4) then
    begin
      Log.Add('FAILED: reaching the goal raises the maximum and refills');
      Inc(Result);
    end;
    if W.LastSound <> SND_POWER02 then
    begin
      Log.Add('FAILED: a level-up is power02');
      Inc(Result);
    end;
    if EffectVariant <> PICKUP_FX_LEVELUP then
    begin
      Log.Add('FAILED: the effect should be the level-up one');
      Inc(Result);
    end;

    Fresh(0, MANA_TARGETS[0] - 2, 0);
    EntityTouchPickup(Pool.Entity(Slot)^, P, W);
    if P.TargetIndex <> 0 then
    begin
      Log.Add('FAILED: one short of the goal is not reaching it');
      Inc(Result);
    end;

    { The heal refills and does nothing else to the maximum. }
    Fresh(0, 5, 0);
    EntityTouchHeal(Pool.Entity(Slot)^, P, W);
    Log.Add(Format('heal: lives %d/%d, counter %d, sound %s, effect %d',
      [P.Lives, P.MaxLives, P.Counter, SoundNames[W.LastSound],
       EffectVariant]));
    if (P.Lives <> 3) or (P.MaxLives <> 3) then
    begin
      Log.Add('FAILED: a heal refills to the maximum and does not raise it');
      Inc(Result);
    end;
    if P.Counter <> 5 then
    begin
      Log.Add('FAILED: a heal is not a mana stone');
      Inc(Result);
    end;
    if (W.LastSound <> SND_KACHI02) or (EffectVariant <> PICKUP_FX_HEAL) then
    begin
      Log.Add('FAILED: the heal has its own sound and effect variant');
      Inc(Result);
    end;

    { Past the end of the goal table nothing can be reached. }
    if ManaTarget(MANA_TARGET_COUNT) <> MaxInt then
    begin
      Log.Add('FAILED: past the table the goal must be unreachable');
      Inc(Result);
    end;
  finally
    W.Free;
    Pool.Free;
  end;
end;

{ --- Entity_SolidCollideX/Y @ 0x00456B4C / 0x00456E0C --------------------

  Three asymmetries between the two sweeps are the whole point of testing
  these, and each has a case below:

    softness is PER AXIS - kind 1 is soft in X, kind 2 is soft in Y
    the Y sweep has NO zero-delta guard, so resting on a platform still
      reports a collision
    landing on top writes PushX as well as PushY, which is what carries a
      rider along with a moving platform

  Positions are placed one pixel apart on purpose: the push is then exactly
  one pixel in 1/32 units, which is a number that can be predicted by hand
  rather than read off the implementation. }
function TestSolidCollide(Log: TStringList): Integer;
const
  EXT = 20;
var
  W: TCountingWorld;
  Pool: TEntityPool;
  Subject, Solid: Integer;

  procedure Place(Slot, PxX, PxY, SolidKind: Integer);
  begin
    Pool.SetField(Slot, EF_POS_X, POSITION_BIAS + PxX * 32);
    Pool.SetField(Slot, EF_POS_Y, POSITION_BIAS + PxY * 32);
    Pool.SetField(Slot, EF_EXTENT_X, EXT);
    Pool.SetField(Slot, EF_EXTENT_Y, EXT);
    Pool.SetField(Slot, EF_HITBOX_INSET_X, 0);
    Pool.SetField(Slot, EF_HITBOX_INSET_Y, 0);
    Pool.SetField(Slot, EF_SOLID, SolidKind);
    Pool.SetField(Slot, EF_EVENT_ID, -1);
  end;

  procedure Reset(SolidKind: Integer);
  begin
    Pool.Clear;
    Subject := Pool.Spawn(EKIND_SINGLE, 1, 0, 0);      { slot 0 }
    Solid := Pool.Spawn(EKIND_MINOR, 2, 0, 0);
    Place(Subject, 100, 100, 0);
    Place(Solid, 120, 120, SolidKind);
    W.PushX := 0;
    W.PushY := 0;
    W.OnTopOfSolid := False;
  end;

begin
  Result := 0;
  Log.Add('');
  Log.Add('--- Entity_SolidCollideX/Y ---');
  Pool := TEntityPool.Create;
  W := TCountingWorld.Create;
  try
    W.Pool := Pool;

    { Moving one pixel into a solid one pixel away pushes back one pixel. }
    Reset(3);
    Place(Solid, 120, 100, 3);
    if not W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: a solid one pixel away should block');
      Inc(Result);
    end;
    Log.Add(Format('blocked moving right: PushX %d (1/32 px)', [W.PushX]));
    if W.PushX <> -32 then
    begin
      Log.Add('FAILED: want a one-pixel push back, -32');
      Inc(Result);
    end;

    { A zero X delta does nothing. Position 119 starts with overlapping boxes;
      position 120 would only make them touch and would not exercise the guard. }
    Reset(3);
    Place(Solid, 119, 100, 3);
    if W.SolidCollideX(Pool.Entity(Subject)^, 0, False) then
    begin
      Log.Add('FAILED: the X sweep should ignore a zero delta');
      Inc(Result);
    end;
    if not W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: ... but a non-zero delta must still see that solid');
      Inc(Result);
    end;

    { The Y sweep has no such guard, which is how resting on a
      platform keeps reporting one.

      Position 119 ensures the boxes overlap before movement; at 120 they only
      touch, and RectOverlap correctly reports no overlap. }
    Reset(3);
    Place(Solid, 100, 119, 3);
    if not W.SolidCollideY(Pool.Entity(Subject)^, 0, False) then
    begin
      Log.Add('FAILED: the Y sweep must still act on a zero delta');
      Inc(Result);
    end;

    { Landing on top: within tolerance it marks the ride and carries the
      rider along with the platform AND with this frame's scroll. }
    Reset(3);
    Place(Solid, 100, 120, 3);
    W.Layer.DeltaX := 64;                { two pixels of scroll }
    W.SolidCollideY(Pool.Entity(Subject)^, 32, False);
    Log.Add(Format('landed: onTop %d, ridden %d, PushY %d, PushX %d',
      [Ord(W.OnTopOfSolid), Pool.Field(Solid, EF_RIDDEN), W.PushY, W.PushX]));
    if not W.OnTopOfSolid then
    begin
      Log.Add('FAILED: within 8 pixels of the top should count as on top');
      Inc(Result);
    end;
    if Pool.Field(Solid, EF_RIDDEN) <> 1 then
    begin
      Log.Add('FAILED: the platform should be marked ridden');
      Inc(Result);
    end;
    if W.PushY <> -32 then
    begin
      Log.Add('FAILED: want a one-pixel vertical push, -32');
      Inc(Result);
    end;
    if W.PushX <> 64 then
    begin
      Log.Add('FAILED: riding should carry the layer delta into PushX');
      Inc(Result);
    end;
    W.Layer.DeltaX := 0;

    { The on-top tolerance is EXCLUSIVE. Placed so the gap is exactly 8, which
      is the only distance that tells < from <=; every other case in this file
      sits at a gap of 1 and cannot see the difference. }
    Reset(3);
    Place(Solid, 100, 113, 3);
    W.SolidCollideY(Pool.Entity(Subject)^, 32, False);
    Log.Add(Format('gap of exactly %d: onTop %d (want 0)',
      [SOLID_TOP_TOLERANCE, Ord(W.OnTopOfSolid)]));
    if W.OnTopOfSolid then
    begin
      Log.Add('FAILED: a gap of exactly 8 is NOT on top - the test is < 8');
      Inc(Result);
    end;
    Reset(3);
    Place(Solid, 100, 114, 3);
    W.SolidCollideY(Pool.Entity(Subject)^, 32, False);
    if not W.OnTopOfSolid then
    begin
      Log.Add('FAILED: a gap of 7 IS on top');
      Inc(Result);
    end;

    { Softness is per axis. Kind 1 is soft in X and solid in Y; kind 2 the
      other way round. Nothing here is soft when SkipSoft is off. }
    Reset(SOLID_SOFT_IN_X);
    Place(Solid, 120, 100, SOLID_SOFT_IN_X);
    if W.SolidCollideX(Pool.Entity(Subject)^, 32, True) then
    begin
      Log.Add('FAILED: kind 1 should be soft in X');
      Inc(Result);
    end;
    if not W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: kind 1 still blocks X when SkipSoft is off');
      Inc(Result);
    end;

    Reset(SOLID_SOFT_IN_Y);
    Place(Solid, 100, 120, SOLID_SOFT_IN_Y);
    if W.SolidCollideY(Pool.Entity(Subject)^, 32, True) then
    begin
      Log.Add('FAILED: kind 2 should be soft in Y');
      Inc(Result);
    end;
    if not W.SolidCollideY(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: kind 2 still blocks Y when SkipSoft is off');
      Inc(Result);
    end;

    { And the pair is genuinely crossed over: kind 1 is NOT soft in Y. }
    Reset(SOLID_SOFT_IN_X);
    Place(Solid, 100, 120, SOLID_SOFT_IN_X);
    if not W.SolidCollideY(Pool.Entity(Subject)^, 32, True) then
    begin
      Log.Add('FAILED: kind 1 is soft in X only, not in Y');
      Inc(Result);
    end;

    { The air dash phases through EF_VULN_KIND $5C - the same fact
      Player_UpdateAirDash was written from. }
    Reset(3);
    Place(Solid, 120, 100, 3);
    Pool.SetField(Solid, EF_VULN_KIND, SOLID_PHASE_VULN);
    Pool.SetField(Subject, EF_STATE, SOLID_STATE_AIRDASH);
    if W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: the air dash should phase through vuln kind $5C');
      Inc(Result);
    end;
    Pool.SetField(Subject, EF_STATE, 0);
    if not W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: any other state is blocked by it');
      Inc(Result);
    end;

    { An entity never blocks itself. }
    Pool.Clear;
    Subject := Pool.Spawn(EKIND_MINOR, 2, 0, 0);
    Place(Subject, 100, 100, 3);
    if W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: an entity blocked itself');
      Inc(Result);
    end;
  finally
    W.Free;
    Pool.Free;
  end;
end;

{ --- Entity_Destroy @ 0x00461400 -----------------------------------------
  Verify projectile ownership bookkeeping, child destruction, sprite release,
  and event-state cleanup. }
function TestDestroy(Log: TStringList): Integer;
var
  W: TCountingWorld;
  Pool: TEntityPool;
  Owner, Shot, Parent, Kid, N, I: Integer;
begin
  Result := 0;
  Log.Add('');
  Log.Add('--- Entity_Destroy ---');
  Pool := TEntityPool.Create;
  W := TCountingWorld.Create;
  try
    W.Pool := Pool;

    { A projectile gives its owner a shot back. }
    Owner := Pool.Spawn(EKIND_ACTOR, 1, 0, 0);
    Pool.SetField(Owner, EF_SHOTS, 2);
    Shot := Pool.Spawn(EKIND_MINOR, 2, 0, 0);
    Pool.SetField(Shot, EF_CLASS, DESTROY_CLASS_PROJECTILE);
    Pool.SetField(Shot, EF_OWNER, Owner);
    Pool.SetField(Shot, EF_SPRITE, SPRITE_NONE);
    Pool.SetField(Shot, EF_EVENT_ID, -1);
    W.DestroyEntity(Pool.Entity(Shot)^, False);
    Log.Add(Format('projectile destroyed: owner shots 2 -> %d, slot alive %d',
      [Pool.Field(Owner, EF_SHOTS), Pool.Field(Shot, EF_ALIVE)]));
    if Pool.Field(Owner, EF_SHOTS) <> 1 then
    begin
      Log.Add('FAILED: a dying projectile should return a shot to its owner');
      Inc(Result);
    end;
    if Pool.Field(Shot, EF_ALIVE) <> 0 then
    begin
      Log.Add('FAILED: the slot should be free');
      Inc(Result);
    end;

    { A parent takes its two children with it, and they take no loot. }
    Pool.Clear;
    Parent := Pool.Spawn(EKIND_MINOR, 3, 0, 0);
    Pool.SetField(Parent, EF_CLASS, DESTROY_CLASS_PARENT);
    Pool.SetField(Parent, EF_SPRITE, SPRITE_NONE);
    Pool.SetField(Parent, EF_EVENT_ID, -1);
    for I := 0 to 1 do
    begin
      Kid := Pool.Spawn(EKIND_MINOR, 4, 0, 0);
      Pool.SetField(Kid, EF_SPRITE, SPRITE_NONE);
      Pool.SetField(Kid, EF_EVENT_ID, -1);
      Pool.SetField(Parent, EF_CHILD_A + I, Kid);
    end;
    W.Killed := 0;
    W.DestroyEntity(Pool.Entity(Parent)^, False);
    N := 0;
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] then Inc(N);
    Log.Add(Format('parent destroyed: %d destroy call(s), %d slot(s) left alive',
      [W.Killed, N]));
    if N <> 0 then
    begin
      Log.Add('FAILED: the children should have gone with the parent');
      Inc(Result);
    end;

    { The no-drop flag. Column 8 non-zero means never drop, and the roll is
      not even taken - which is observable because the RNG does not advance. }
    Pool.Clear;
    Parent := Pool.Spawn(EKIND_MINOR, 5, 0, 0);
    Pool.SetField(Parent, EF_SPRITE, SPRITE_NONE);
    Pool.SetField(Parent, EF_EVENT_ID, -1);
    Pool.SetField(Parent, EF_NO_DROP, 1);
    RandomSeed := 4242;
    W.DestroyEntity(Pool.Entity(Parent)^, True);
    if RandomSeed <> 4242 then
    begin
      Log.Add('FAILED: a no-drop entity should not even roll');
      Inc(Result);
    end;
    N := 0;
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = DROP_TYPE) then Inc(N);
    if N <> 0 then
    begin
      Log.Add('FAILED: a no-drop entity dropped something');
      Inc(Result);
    end;

    { And with the flag clear it does roll - over enough tries the drop rate
      should land near the 76-in-256 the threshold implies. }
    N := 0;
    RandomSeed := 1;
    for I := 1 to 2000 do
    begin
      Pool.Clear;
      Parent := Pool.Spawn(EKIND_MINOR, 5, 0, 0);
      Pool.SetField(Parent, EF_SPRITE, SPRITE_NONE);
      Pool.SetField(Parent, EF_EVENT_ID, -1);
      W.DestroyEntity(Pool.Entity(Parent)^, True);
      if Pool.LiveCount > 0 then
        Inc(N);
    end;
    Log.Add(Format('drop rate over 2000 kills: %d (%.1f%%), threshold implies '
      + '%.1f%%', [N, N / 20.0, (DROP_ROLL - 1 - DROP_THRESHOLD) / 2.56]));
    if (N < 500) or (N > 700) then
    begin
      Log.Add('FAILED: the drop rate is nowhere near 76 in 256');
      Inc(Result);
    end;
  finally
    W.Free;
    Pool.Free;
  end;
end;

{ --- Entity_SpawnDebris @ 0x00461874 -------------------------------------
  DirectSound prevents whole-routine emulation, so this checks the arithmetic
  while the underlying Delphi RNG remains differential-tested. }
function TestSpawnDebris(Log: TStringList): Integer;
var
  W: TCountingWorld;
  Pool: TEntityPool;
  E: TEntity;
  I, N, Slot: Integer;
  Lifts, Kinds, Frames: string;
begin
  Result := 0;
  Log.Add('');
  Log.Add('--- Entity_SpawnDebris ---');
  Pool := TEntityPool.Create;
  W := TCountingWorld.Create;
  try
    W.Pool := Pool;
    W.TerrainId := TERRAIN_WATER_A;
    W.Layer.DeltaX := 64;
    W.Layer.DeltaY := -32;

    FillChar(E, SizeOf(E), 0);
    E.Raw[EF_POS_X] := POSITION_BIAS + 100 * 32;
    E.Raw[EF_POS_Y] := POSITION_BIAS + 50 * 32;

    RandomSeed := 12345;
    W.Sounds := 0;
    W.SpawnDebris(E, DEBRIS_SPLASH);

    N := 0;
    Lifts := '';
    Kinds := '';
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = EF_DEBRIS_TYPE) then
      begin
        Inc(N);
        Lifts := Lifts + Format('%d ', [Pool.Field(I, EF_VEL_Y)]);
        Kinds := Kinds + Format('%d ', [Pool.Field(I, EF_STATE)]);
      end;
    Log.Add(Format('kind 0 on water terrain: %d particles, sound %d (%s)',
      [N, W.LastSound, SoundNames[W.LastSound]]));
    Log.Add(Format('  lifts %s / states %s', [Trim(Lifts), Trim(Kinds)]));

    if N <> EF_DEBRIS_SPEEDS then
    begin
      Log.Add(Format('FAILED: the burst is always %d particles, got %d',
        [EF_DEBRIS_SPEEDS, N]));
      Inc(Result);
    end;
    if Trim(Lifts) <> '-32 -40 -48 -56 -64' then
    begin
      Log.Add('FAILED: the fan should be (i + 4) * -8');
      Inc(Result);
    end;
    if Trim(Kinds) <> '1 1 1 1 1' then
    begin
      Log.Add('FAILED: every particle should carry Kind + 1 in EF_STATE');
      Inc(Result);
    end;
    if (W.Sounds <> 1) or (W.LastSound <> SND_WATER01) then
    begin
      Log.Add('FAILED: terrain 3 should splash - water01, once');
      Inc(Result);
    end;

    { Terrain that is not water says nothing at all for kind 0. }
    Pool.Clear;
    W.TerrainId := 1;
    W.Sounds := 0;
    W.SpawnDebris(E, DEBRIS_SPLASH);
    if W.Sounds <> 0 then
    begin
      Log.Add('FAILED: only terrains 3 and 4 make a noise on kind 0');
      Inc(Result);
    end;

    { Kind 2 numbers its particles' frames in order; kind 1 randomises them. }
    Pool.Clear;
    W.Sounds := 0;
    W.SpawnDebris(E, DEBRIS_SHATTER);
    Frames := '';
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = EF_DEBRIS_TYPE) then
        Frames := Frames + Format('%d ', [Pool.Field(I, EF_FLAG1C)]);
    Log.Add(Format('kind 2 frames: %s, sound %d (%s)',
      [Trim(Frames), W.LastSound, SoundNames[W.LastSound]]));
    if Trim(Frames) <> '0 1 2 3 4' then
    begin
      Log.Add('FAILED: a shatter should fan through its frames in order');
      Inc(Result);
    end;
    if W.LastSound <> SND_BOM04 then
    begin
      Log.Add('FAILED: kind 2 is bom04');
      Inc(Result);
    end;

    { The layer delta is taken back out of the spawn position, so a particle
      does not get scrolled twice on the frame it is born. }
    Pool.Clear;
    W.SpawnDebris(E, DEBRIS_SHATTER);
    Slot := -1;
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = EF_DEBRIS_TYPE) then
      begin
        Slot := I;
        Break;
      end;
    if Slot >= 0 then
    begin
      Log.Add(Format('spawn x %d (parent %d, layer delta %d)',
        [Pool.Field(Slot, EF_POS_X) - POSITION_BIAS,
         E.Raw[EF_POS_X] - POSITION_BIAS, W.Layer.DeltaX]));
      if Pool.Field(Slot, EF_POS_X) - POSITION_BIAS
         <> (E.Raw[EF_POS_X] - POSITION_BIAS) - W.Layer.DeltaX then
      begin
        Log.Add('FAILED: the layer delta should be subtracted at spawn');
        Inc(Result);
      end;
    end;

    { And the scatter is reproducible, because the RNG is. }
    Pool.Clear;
    RandomSeed := 999;
    W.SpawnDebris(E, DEBRIS_IMPACT);
    Lifts := '';
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = EF_DEBRIS_TYPE) then
        Lifts := Lifts + Format('%d ', [Pool.Field(I, EF_VEL_X)]);
    Pool.Clear;
    RandomSeed := 999;
    W.SpawnDebris(E, DEBRIS_IMPACT);
    Kinds := '';
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = EF_DEBRIS_TYPE) then
        Kinds := Kinds + Format('%d ', [Pool.Field(I, EF_VEL_X)]);
    Log.Add(Format('same seed, same scatter: [%s]', [Trim(Lifts)]));
    if Lifts <> Kinds then
    begin
      Log.Add('FAILED: the same seed must give the same burst');
      Inc(Result);
    end;
    if Trim(Lifts) = '0 0 0 0 0' then
    begin
      Log.Add('FAILED: every particle got zero horizontal speed');
      Inc(Result);
    end;
  finally
    W.Free;
    Pool.Free;
  end;
end;


{ Reported: falling in water kills the player but no game-over screen ever
  appears, while dying any other way shows one.

  PS_FELL is reached only from Entity_CheckKillTiles, and it counts
  PF_ANIM_TIMER up to DEATH_HOLD before setting the state to 100. Driving
  PlayerUpdate alone already reaches game over, so if this fails the fault is
  in the frame around it, not the death arm: this runs the real
  Entity_UpdateAll loop, over a layer that is kill tile everywhere. }
function TestDrownReachesGameOver(Log: TStringList): Integer;
var
  Pool: TEntityPool;
  W: TCountingWorld;
  S: TStubSprites;
  Grid: TGridTiles;
  P: TPlayerState;
  L: TLayerInfo;
  Inp: TInputState;
  E: PEntity;
  State, Frames, X, Y, Bad, FirstState: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('FAILED: ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- drowning reaches the game-over screen ---');

  Pool := TEntityPool.Create;
  W := TCountingWorld.Create;
  S := TStubSprites.Create;
  Grid := TGridTiles.Create;
  try
    W.Pool := Pool;
    W.Tiles := Grid;
    W.KillTile := KILL_TILE;
    Grid.W := 64;
    Grid.H := 64;
    for X := 0 to 63 do
      for Y := 0 to 63 do
        Grid.Cells[X, Y] := KILL_TILE;

    FillChar(L, SizeOf(L), 0);
    L.OriginX := POSITION_BIAS;
    L.OriginY := POSITION_BIAS;
    L.TileW := 32;
    L.TileH := 32;
    FillChar(P, SizeOf(P), 0);
    FillChar(Inp, SizeOf(Inp), 0);

    E := Pool.Entity(0);
    FillChar(E^, SizeOf(TEntity), 0);
    E^.Raw[EF_SLOT]   := 0;
    E^.Raw[EF_ALIVE]  := 1;
    E^.Raw[EF_TYPE]   := 1;
    E^.Raw[EF_SPRITE] := SPRITE_NONE;
    E^.Raw[EF_BYTE94] := 1;
    { A REAL extent. With both extents left at zero the swept box is empty -
      Bottom lands one below Top because of the -1 - and the check returns
      having probed no tile at all, which is what the original does too. A
      test built that way cannot fail. The player sprite is 32x32. }
    E^.Raw[EF_EXTENT_X] := 32;
    E^.Raw[EF_EXTENT_Y] := 32;
    E^.Raw[EF_POS_X]  := (64 shl POSITION_SHIFT) + POSITION_BIAS;
    E^.Raw[EF_POS_Y]  := (64 shl POSITION_SHIFT) + POSITION_BIAS;

    { One frame first: the kill check has to fire at all before the countdown
      means anything. }
    { The GLOBAL, not a local. EnterGameOver writes GameStateValue directly,
      and GmMain threads that same global through TickEntities - so a local
      here would never see the write and the loop below could not end. }
    GameStateValue := GS_PLAY;
    Grid.Probes := '';
    EntityUpdateAll(Pool, W, S, P, L, Inp, GameStateValue);
    FirstState := E^.Raw[PF_STATE];
    { The grid records every probe, so an empty sweep is caught rather than
      passing for a miss. }
    Want(Grid.Probes <> '',
         'the kill check swept no tile at all - with both extents zero the '
         + 'box is empty and this test cannot fail');
    Want(FirstState = PS_FELL,
         Format('after one frame over kill tiles the player state is %d, '
           + 'want PS_FELL (%d) - the kill check never fired, so nothing '
           + 'below is being tested', [FirstState, PS_FELL]));

    Frames := 1;
    while (GameStateValue = GS_PLAY) and (Frames < 400) do
    begin
      EntityUpdateAll(Pool, W, S, P, L, Inp, GameStateValue);
      Inc(Frames);
    end;
    State := GameStateValue;

    Want(State = GS_PLAY_ALT,
         Format('after %d frames the game state is %d, want GS_PLAY_ALT (%d). '
           + 'Player state %d, death timer %d of %d, alive %d - drowning '
           + 'never reaches the game-over screen',
           [Frames, State, GS_PLAY_ALT, E^.Raw[PF_STATE],
            E^.Raw[PF_ANIM_TIMER], DEATH_HOLD, E^.Raw[EF_ALIVE]]));
  finally
    Grid.Free;
    S.Free;
    W.Free;
    Pool.Free;
  end;

  if Bad = 0 then
    Log.Add('drowning: kill tile -> PS_FELL -> game over');
  Result := Bad;
end;

function SelfTestEntities(Log: TStringList): Integer;
var
  GameDir, ExeName: string;
  Exe: TMemoryStream;
  Table: array[0..ENTITY_TYPE_COUNT - 1] of Cardinal;
  Arm: array[0..15] of Byte;
  I, J, Bad, Rel, Target, NoArm, Half, Pct, Got, Want, Ties: Integer;
  Pool: TEntityPool;
  W: TCountingWorld;
  S: TStubSprites;
  P: TPlayerState;
  L: TLayerInfo;
  Inp: TInputState;
  E: PEntity;

  procedure Place(Slot, TypeId, Sprite, PxX, PxY: Integer);
  var
    Q: PEntity;
  begin
    Q := Pool.Entity(Slot);
    FillChar(Q^, SizeOf(TEntity), 0);
    Q^.Raw[EF_SLOT]   := Slot;
    Q^.Raw[EF_ALIVE]  := 1;
    Q^.Raw[EF_TYPE]   := TypeId;
    Q^.Raw[EF_SPRITE] := Sprite;
    Q^.Raw[EF_BYTE94] := 1;
    Q^.Raw[EF_POS_X]  := (PxX shl POSITION_SHIFT) + POSITION_BIAS;
    Q^.Raw[EF_POS_Y]  := (PxY shl POSITION_SHIFT) + POSITION_BIAS;
  end;

  procedure Run(AState: Integer);
  begin
    EntityTestState := AState;
    TouchCount := 0;
    HitCount := 0;
    TouchSlots := '';
    EntityUpdateAll(Pool, W, S, P, L, Inp, EntityTestState);
  end;

begin
  Result := 0;
  GameDir := ParamStr(2);
  if GameDir = '' then
    GameDir := ExtractFilePath(ParamStr(0));

  Log.Add('=== Entity_UpdateAll @ 0x004608BC ===');
  Log.Add('');

  { --- 1. the switch, read out of akuji.exe ------------------------------ }
  Bad := 0;
  NoArm := 0;
  Exe := TMemoryStream.Create;
  try
    ExeName := OriginalExe(GameDir);
    if not FileExists(ExeName) then
    begin
      Log.Add('FAILED: akuji.exe is not in the game directory');
      Inc(Result);
    end
    else
    begin
      Exe.LoadFromFile(ExeName);
      Exe.Position := HANDLER_JUMP_TABLE - CODE_VA_BIAS;
      Exe.ReadBuffer(Table[0], ENTITY_TYPE_COUNT * SizeOf(Cardinal));

      for I := 0 to ENTITY_TYPE_COUNT - 1 do
      begin
        if Table[I] = HANDLER_NO_ARM_TARGET then
        begin
          Inc(NoArm);
          if HANDLER_ADDR[I] <> HANDLER_NONE then
          begin
            Log.Add(Format('  type %d: exe says no arm, table names 0x%.6X',
              [I, HANDLER_ADDR[I]]));
            Inc(Bad);
          end;
          Continue;
        end;

        { Every arm is `MOV EAX,EBX` then `CALL rel32`, except the two that pass
          no entity at all and start with the CALL. }
        Exe.Position := Int64(Table[I]) - CODE_VA_BIAS;
        Exe.ReadBuffer(Arm[0], SizeOf(Arm));
        J := -1;
        if Arm[0] = $E8 then J := 0
        else if (Arm[0] = $8B) and (Arm[1] = $C3) and (Arm[2] = $E8) then J := 2;
        if J < 0 then
        begin
          Log.Add(Format('  type %d: arm at 0x%.6X is not MOV/CALL', [I, Table[I]]));
          Inc(Bad);
          Continue;
        end;
        Rel := PInteger(@Arm[J + 1])^;
        Target := Integer(Table[I]) + J + 5 + Rel;
        if Cardinal(Target) <> HANDLER_ADDR[I] then
        begin
          Log.Add(Format('  type %d: exe 0x%.6X, table 0x%.6X',
            [I, Target, HANDLER_ADDR[I]]));
          Inc(Bad);
        end;
      end;

      Log.Add(Format('jump table at 0x%.6X: %d arms, %d types with none, %d wrong',
        [HANDLER_JUMP_TABLE, ENTITY_TYPE_COUNT - NoArm, NoArm, Bad]));
      Inc(Result, Bad);

      if NoArm <> 3 then
      begin
        Log.Add(Format('FAILED: expected 3 types with no arm, found %d', [NoArm]));
        Inc(Result);
      end;
    end;
  finally
    Exe.Free;
  end;

  { --- 2. ScaleByPercent over its whole domain --------------------------- }
  Bad := 0;
  Got := 0;
  Ties := 0;
  for Half := 0 to 1024 do
    for Pct := 0 to 100 do
    begin
      if (Half * Pct) mod 100 = 50 then
        Inc(Ties);
      Want := ExactPercent(Half, Pct);
      for J := 0 to High(X87_DEVIATIONS) do
        if (X87_DEVIATIONS[J][0] = Half) and (X87_DEVIATIONS[J][1] = Pct) then
        begin
          Want := X87_DEVIATIONS[J][2];
          Break;
        end;
      if ScaleByPercent(Half, Pct) <> Want then
      begin
        if Bad < 5 then
          Log.Add(Format('  half %d pct %d: got %d, x87 %d',
            [Half, Pct, ScaleByPercent(Half, Pct), Want]));
        Inc(Bad);
      end;
      if ScaleByPercent(Half, Pct) <> ExactPercent(Half, Pct) then
        Inc(Got);
    end;
  Log.Add('');
  Log.Add(Format('ScaleByPercent over 1025 x 101 cases (%d of them ties): '
    + '%d wrong', [Ties, Bad]));
  Log.Add(Format('  places where the x87 beats round-half-even: %d, want %d',
    [Got, Length(X87_DEVIATIONS)]));
  Inc(Result, Bad);
  if Got <> Length(X87_DEVIATIONS) then
  begin
    Log.Add('FAILED: the set of x87 deviations is not the one the simulation found');
    Inc(Result);
  end;

  { --- 3. the loop ------------------------------------------------------- }
  Pool := TEntityPool.Create;
  W := TCountingWorld.Create;
  S := TStubSprites.Create;
  try
    FillChar(P, SizeOf(P), 0);
    FillChar(Inp, SizeOf(Inp), 0);
    FillChar(L, SizeOf(L), 0);
    L.TileW := 32; L.TileH := 32; L.MapTilesX := 20; L.MapTilesY := 15;
    EntityPlayerTouch := @CountTouch;
    EntityTakeProjectileHits := @CountHit;
    TouchAbortAt := -1;
    W.Pool := Pool;

    { (a) the scroll is carried, unless the type is screen-space. }
    Pool.Clear;
    L.DeltaX := 64; L.DeltaY := -32;
    Place($21, 3, SPRITE_NONE, 100, 100);
    Place($22, 3, SPRITE_NONE, 100, 100);
    Pool.Entity($22)^.Raw[EF_SCREEN_SPACE] := 1;
    Run(GS_PLAY);
    Log.Add('');
    Log.Add(Format('scroll carry: world x %d y %d, screen-space x %d y %d',
      [EntityPixelX(Pool.Entity($21)^), EntityPixelY(Pool.Entity($21)^),
       EntityPixelX(Pool.Entity($22)^), EntityPixelY(Pool.Entity($22)^)]));
    if (EntityPixelX(Pool.Entity($21)^) <> 102)
    or (EntityPixelY(Pool.Entity($21)^) <> 99) then
    begin
      Log.Add('FAILED: a world entity did not follow the scroll');
      Inc(Result);
    end;
    if (EntityPixelX(Pool.Entity($22)^) <> 100)
    or (EntityPixelY(Pool.Entity($22)^) <> 100) then
    begin
      Log.Add('FAILED: a screen-space entity followed the scroll');
      Inc(Result);
    end;
    L.DeltaX := 0; L.DeltaY := 0;

    { --- every executable jump-table arm has a Pascal case ----------------
      Drive one entity of every type through EntityUpdateAll. The three types
      without executable arms must take the explicit fall-through path. }
    Bad := 0;
    for I := 0 to ENTITY_TYPE_COUNT - 1 do
    begin
      Pool.Clear;
      Place($21, I, SPRITE_NONE, 160, 120);
      EntitiesUnhandled := 0;
      Run(GS_PLAY);
      if (Table[I] <> HANDLER_NO_ARM_TARGET) and (EntitiesUnhandled <> 0) then
      begin
        Log.Add(Format('  type %d has an arm at 0x%.6X but no case',
          [I, Table[I]]));
        Inc(Bad);
      end;
      if (Table[I] = HANDLER_NO_ARM_TARGET) and (EntitiesUnhandled = 0) then
      begin
        Log.Add(Format('  type %d has no arm but the case handled it', [I]));
        Inc(Bad);
      end;
    end;
    Log.Add('');
    if Bad = 0 then
      Log.Add(Format('all %d armed types reach a case, and the %d unarmed '
        + 'ones fall through', [ENTITY_TYPE_COUNT - NoArm, NoArm]))
    else
      Log.Add(Format('FAILED: %d types disagree with the jump table', [Bad]));
    Inc(Result, Bad);
    Pool.Clear;

    { The dispatcher's arms actually reach the handlers they name. Every other
      check of types 24 and 25 calls them DIRECTLY, so a case arm wired to the
      wrong handler goes unnoticed - and one did, until this was added: pointing
      type 25's arm at EntityUpdate_Type14_ManaStone survived the whole suite. }
    Pool.Clear;
    Place($21, 25, SPRITE_NONE, 160, 120);
    Pool.Entity($21)^.Raw[EF_VARIANT] := 2;
    Place($22, 24, SPRITE_NONE, 160, 120);
    Pool.Entity($22)^.Raw[EF_VARIANT] := 3;
    Place($23, 27, SPRITE_NONE, 160, 120);
    Run(GS_PLAY);
    Log.Add('');
    Log.Add(Format('dispatch: type 25 var 2 -> sprite %d (want %d), '
      + 'type 24 var 3 -> sprite %d (want %d)',
      [Pool.Entity($21)^.Raw[EF_ANIM_ID], ITEM25_SPRITES[2],
       Pool.Entity($22)^.Raw[EF_ANIM_ID], ITEM24_SPRITES[3]]));
    if Pool.Entity($21)^.Raw[EF_ANIM_ID] <> ITEM25_SPRITES[2] then
    begin
      Log.Add('FAILED: the type 25 arm did not reach EntityUpdate_Type25_Door');
      Inc(Result);
    end;
    if Pool.Entity($22)^.Raw[EF_ANIM_ID] <> ITEM24_SPRITES[3] then
    begin
      Log.Add('FAILED: the type 24 arm did not reach EntityUpdate_Type24_PowerOrb');
      Inc(Result);
    end;
    if Pool.Entity($23)^.Raw[EF_ANIM_ID] <> SAVE_POINT_SPRITES[0] then
    begin
      Log.Add('FAILED: the type 27 arm did not reach EntityUpdate_Type27_AkujiStatue');
      Inc(Result);
    end;

    { (b) the sprite is placed by its top-left, the entity is its centre. }
    Pool.Clear;
    S.SW[1] := 20; S.SH[1] := 11;
    Place($21, 3, 1, 160, 120);
    Pool.Entity($21)^.Raw[EF_DEPTH] := 3;
    Run(GS_PLAY);
    E := Pool.Entity($21);
    Log.Add(Format('sprite: pos (%d,%d) extent %dx%d depth %d',
      [S.PX[1], S.PY[1], E^.Raw[EF_EXTENT_X], E^.Raw[EF_EXTENT_Y], S.PZ[1]]));
    if (S.PX[1] <> 150) or (S.PY[1] <> 115) then
    begin
      Log.Add('FAILED: sprite not centred on the entity (want 150,115)');
      Inc(Result);
    end;
    if (E^.Raw[EF_EXTENT_X] <> 20) or (E^.Raw[EF_EXTENT_Y] <> 11) then
    begin
      Log.Add('FAILED: extents did not come from the sprite');
      Inc(Result);
    end;
    if S.PZ[1] <> 3 then
    begin
      Log.Add('FAILED: explicit depth not passed through');
      Inc(Result);
    end;

    { and the -1 depth, which no shipped type uses but the code still has. }
    Pool.Clear;
    Place($21, 3, 1, 160, 120);
    Pool.Entity($21)^.Raw[EF_DEPTH] := DEPTH_BY_SCREEN_Y;
    Run(GS_PLAY);
    if S.PZ[1] <> S.PY[1] then
    begin
      Log.Add(Format('FAILED: depth -1 should sort by screen Y (%d, got %d)',
        [S.PY[1], S.PZ[1]]));
      Inc(Result);
    end;

    { (c) the death timer is also the flicker, and it hides on ODD frames. }
    Pool.Clear;
    Place($21, 3, 1, 160, 120);
    Pool.Entity($21)^.Raw[EF_DEATH_TIMER] := 5;
    Run(GS_PLAY);
    if S.Vis[1] then
    begin
      Log.Add('FAILED: visible on an odd death-timer frame');
      Inc(Result);
    end;
    Pool.Entity($21)^.Raw[EF_DEATH_TIMER] := 6;
    Run(GS_PLAY);
    if not S.Vis[1] then
    begin
      Log.Add('FAILED: hidden on an even death-timer frame');
      Inc(Result);
    end;

    { (d) timers tick in play, and freeze in the pause menu and in state 140. }
    Pool.Clear;
    Place($21, 3, SPRITE_NONE, 160, 120);
    Pool.Entity($21)^.Raw[EF_TIMER] := 10;
    Pool.Entity($21)^.Raw[EF_DEATH_TIMER] := 10;
    Run(GS_PLAY);
    Run(GS_PAUSE);
    Run(GS_STATE_140);
    E := Pool.Entity($21);
    Log.Add(Format('timers after play/pause/140: timer %d death %d',
      [E^.Raw[EF_TIMER], E^.Raw[EF_DEATH_TIMER]]));
    if (E^.Raw[EF_TIMER] <> 9) or (E^.Raw[EF_DEATH_TIMER] <> 9) then
    begin
      Log.Add('FAILED: only the GS_PLAY frame should have ticked the timers');
      Inc(Result);
    end;

    { (e) the touch boundary: SLOT_MINOR_FIRST, not one either side of it. }
    Pool.Clear;
    Place(SLOT_ACTOR_LAST, 3, SPRITE_NONE, 160, 120);
    Place(SLOT_MINOR_FIRST, 3, SPRITE_NONE, 160, 120);
    Run(GS_PLAY);
    Log.Add('');
    Log.Add(Format('touch: %d call(s) from slots [%s], %d projectile pass(es)',
      [TouchCount, Trim(TouchSlots), HitCount]));
    if (TouchCount <> 1) or (HitCount <> 1)
    or (Trim(TouchSlots) <> IntToStr(SLOT_MINOR_FIRST)) then
    begin
      Log.Add(Format('FAILED: only slot %d should be touch-tested',
        [SLOT_MINOR_FIRST]));
      Inc(Result);
    end;

    { (f) type 68 in state 3: touched once down in the actor slots, and TWICE
      up in the minor slots, because the special case does not exclude them. }
    Pool.Clear;
    Place(5, TYPE_TOUCH_IN_STATE_3, SPRITE_NONE, 160, 120);
    Pool.Entity(5)^.Raw[EF_STATE] := 3;
    Run(GS_PLAY);
    Log.Add(Format('type 68 state 3 in an actor slot: %d touch(es)', [TouchCount]));
    if TouchCount <> 1 then
    begin
      Log.Add('FAILED: type 68 in state 3 should be touched once here');
      Inc(Result);
    end;

    Pool.Clear;
    Place($30, TYPE_TOUCH_IN_STATE_3, SPRITE_NONE, 160, 120);
    Pool.Entity($30)^.Raw[EF_STATE] := 3;
    Run(GS_PLAY);
    Log.Add(Format('type 68 state 3 in a minor slot: %d touch(es)', [TouchCount]));
    if TouchCount <> 2 then
    begin
      Log.Add('FAILED: type 68 in state 3 should be touched twice in a minor slot');
      Inc(Result);
    end;

    { and state 2 gets nothing extra. }
    Pool.Clear;
    Place(5, TYPE_TOUCH_IN_STATE_3, SPRITE_NONE, 160, 120);
    Pool.Entity(5)^.Raw[EF_STATE] := 2;
    Run(GS_PLAY);
    if TouchCount <> 0 then
    begin
      Log.Add('FAILED: type 68 outside state 3 should not be touched here');
      Inc(Result);
    end;

    { (g) A touch that changes game state abandons the frame. Later timers must
      remain unchanged; the touch log alone cannot distinguish this from the
      ordinary non-play-state guard. }
    Pool.Clear;
    for I := $21 to $25 do
    begin
      Place(I, 3, SPRITE_NONE, 160, 120);
      Pool.Entity(I)^.Raw[EF_TIMER] := 100;
    end;
    TouchAbortAt := $22;
    Run(GS_PLAY);
    TouchAbortAt := -1;
    Log.Add('');
    Log.Add(Format('abandon on state change: touched [%s], timers %d %d %d %d %d',
      [Trim(TouchSlots), Pool.Entity($21)^.Raw[EF_TIMER],
       Pool.Entity($22)^.Raw[EF_TIMER], Pool.Entity($23)^.Raw[EF_TIMER],
       Pool.Entity($24)^.Raw[EF_TIMER], Pool.Entity($25)^.Raw[EF_TIMER]]));
    if Trim(TouchSlots) <> '33 34' then
    begin
      Log.Add('FAILED: the loop should stop touching after the state changed');
      Inc(Result);
    end;
    for I := $23 to $25 do
      if Pool.Entity(I)^.Raw[EF_TIMER] <> 100 then
      begin
        Log.Add(Format('FAILED: slot %d was still updated after the abandon', [I]));
        Inc(Result);
      end;

    { (h) the pool is 289 slots and the loop walks 256 of them. An entity above
      the line is spawnable and is never updated - reproduced, not corrected. }
    Pool.Clear;
    L.DeltaX := 320;
    Place(ENTITY_UPDATE_COUNT, 3, SPRITE_NONE, 100, 100);
    Place(ENTITY_UPDATE_COUNT - 1, 3, SPRITE_NONE, 100, 100);
    Run(GS_PLAY);
    L.DeltaX := 0;
    Log.Add(Format('slot %d moved to %d, slot %d stayed at %d',
      [ENTITY_UPDATE_COUNT - 1, EntityPixelX(Pool.Entity(ENTITY_UPDATE_COUNT - 1)^),
       ENTITY_UPDATE_COUNT, EntityPixelX(Pool.Entity(ENTITY_UPDATE_COUNT)^)]));
    if EntityPixelX(Pool.Entity(ENTITY_UPDATE_COUNT)^) <> 100 then
    begin
      Log.Add('FAILED: a slot above the loop bound was updated');
      Inc(Result);
    end;
    if EntityPixelX(Pool.Entity(ENTITY_UPDATE_COUNT - 1)^) = 100 then
    begin
      Log.Add('FAILED: the last slot inside the bound was NOT updated');
      Inc(Result);
    end;
    if EntitiesLive <> 1 then
    begin
      Log.Add(Format('FAILED: EntitiesLive counted %d, want 1', [EntitiesLive]));
      Inc(Result);
    end;

    { (i) culling, and only for the types that ask for it. }
    Pool.Clear;
    W.Killed := 0;
    Place($21, 3, SPRITE_NONE, 5000, 120);
    Place($22, 3, SPRITE_NONE, 5000, 120);
    Pool.Entity($21)^.Raw[EF_CULL_OFFSCREEN] := 1;
    Run(GS_PLAY);
    Log.Add('');
    Log.Add(Format('off-screen cull: %d destroyed, culling entity alive=%d, '
      + 'other alive=%d', [W.Killed, Pool.Entity($21)^.Raw[EF_ALIVE],
      Pool.Entity($22)^.Raw[EF_ALIVE]]));
    if (W.Killed <> 1) or (Pool.Entity($22)^.Raw[EF_ALIVE] <> 1) then
    begin
      Log.Add('FAILED: exactly the EF_CULL_OFFSCREEN entity should be destroyed');
      Inc(Result);
    end;

    { (j) the box fields are rebuilt every frame from the sprite, and only in
      GS_PLAY. Type 1's row is 30/20/30/30, so a 40-wide sprite gives 6. }
    Pool.Clear;
    S.SW[2] := 40; S.SH[2] := 40;
    Place($21, 3, 2, 160, 120);
    E := Pool.Entity($21);
    E^.Raw[EF_BOX_PCT_X]   := 30;
    E^.Raw[EF_BOX_PCT_Y]   := 20;
    E^.Raw[EF_INSET_PCT_X] := 30;
    E^.Raw[EF_INSET_PCT_Y] := 30;
    Run(GS_PLAY);
    Log.Add(Format('boxes from a 40x40 sprite at 30/20/30/30: %d %d %d %d',
      [E^.Raw[EF_BOX_OFS_X], E^.Raw[EF_BOX_OFS_Y],
       E^.Raw[EF_HITBOX_INSET_X], E^.Raw[EF_HITBOX_INSET_Y]]));
    if (E^.Raw[EF_BOX_OFS_X] <> 6) or (E^.Raw[EF_BOX_OFS_Y] <> 4)
    or (E^.Raw[EF_HITBOX_INSET_X] <> 6) or (E^.Raw[EF_HITBOX_INSET_Y] <> 6) then
    begin
      Log.Add('FAILED: want 6 4 6 6');
      Inc(Result);
    end;

    E^.Raw[EF_BOX_OFS_X] := -1;
    Run(GS_PAUSE);
    if E^.Raw[EF_BOX_OFS_X] <> -1 then
    begin
      Log.Add('FAILED: the boxes were rebuilt outside GS_PLAY');
      Inc(Result);
    end;

  finally
    { Put the real one back, not nil - it is the default now. }
    EntityPlayerTouch := @PlayerTouch;
    EntityTakeProjectileHits := nil;
    S.Free;
    W.Free;
    Pool.Free;
  end;

  Inc(Result, TestSpawnDebris(Log));
  Inc(Result, TestDestroy(Log));
  Inc(Result, TestSolidCollide(Log));
  Inc(Result, TestTouchHandlers(Log));
  Inc(Result, TestTileCollide(Log, GameDir));
  Inc(Result, TestKillTiles(Log));
  Inc(Result, TestDrownReachesGameOver(Log));
  Inc(Result, TestSpriteTables(Log, GameDir));
  Inc(Result, TestItemHandlers(Log));
  Inc(Result, TestEffectHandlers(Log));

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - the dispatcher matches the switch in the binary and behaves '
      + 'as read')
  else
    Log.Add('FAILED');
end;

end.
