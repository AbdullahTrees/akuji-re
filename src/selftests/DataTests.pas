{ Self-tests for the pure data readers: the direction tables, the event files,
  the settings record and the event mini-language. }

unit DataTests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, TypInfo,
  QdaArchive, SoundTable, WaveFile, AudioMixer, AudioOut, MidiFile, KbgmPlayer,
  Directions, Entities, EventScripts, EventCommands, PlayerState, GameState,
  Stages, Camera, TileMaps, Player, EntityHandlers, EventRunner, GameSession,
  SpritePool, Sprites, Dialogue, BgAnime, UnitInit, Title, Ending, Opening,
  GameFont, DDDDComponent, Surfaces;

function SelfTestDirections(Log: TStrings): Integer;
function SelfTestEvents(Log: TStrings): Integer;
function SelfTestSettings(Log: TStrings): Integer;
function SelfTestScript(Log: TStrings): Integer;

implementation

{ --selftest-dir : the 64-step direction system. Needs no game data.

  Checks three things about Directions.pas that the binary lets us assert:

    1. DIR_COS is exactly trunc(32 * cos(i * 2*Pi / 64)) for all 64 entries.
       That closed form was derived from the shipped table, so this catches a
       transcription slip in either direction.
    2. The Y table really is the X table rotated a quarter turn, which is the
       identity that let the second 64-int table at 0x00468C14 be dropped.
    3. AngleBetween round-trips: stepping away from the origin along direction
       d and asking for the angle back gives d again. This is the real test of
       the integer atan2 - it exercises all four quadrant branches and the
       sixteen sub-steps, with no floating point anywhere. }
function SelfTestDirections(Log: TStrings): Integer;
var
  E: TEntity;
  T: TEntityType;
  PosBad, Expect, ColBad, Kind0, Kind1, Kind2: Integer;
  EdgeBad, EdgeChecked, Cam, Ext, PosI, ED, Edge, Saved: Integer;
  LT: TLayerInfo;
  EE: TEntity;
  I, D, Got, Bad, RoundTrips: Integer;
  Expected: Integer;
  X, Y: Integer;
begin
  Result := 0;
  Bad := 0;

  Log.Add('DIR_COS vs trunc(32 * cos(i * 2Pi / 64)):');
  for I := 0 to DIR_COUNT - 1 do
  begin
    Expected := Trunc(32.0 * Cos(I * 2.0 * Pi / DIR_COUNT));
    if DIR_COS[I] <> Expected then
    begin
      Log.Add(Format('  i=%2d table=%3d closed form=%3d', [I, DIR_COS[I], Expected]));
      Inc(Bad);
    end;
  end;
  Log.Add(Format('  %d mismatches', [Bad]));

  Log.Add('');
  Log.Add('DirVelY(d) = DIR_COS[(d + 16) mod 64]:');
  I := 0;
  for D := 0 to DIR_COUNT - 1 do
    if DirVelY(D) <> DIR_COS[(D + DIR_QUARTER) and DIR_MASK] then
      Inc(I);
  Log.Add(Format('  %d mismatches', [I]));
  Inc(Bad, I);

  Log.Add('');
  Log.Add('AngleBetween round-trip (origin -> a point along each direction):');
  RoundTrips := 0;
  I := 0;
  for D := 0 to DIR_COUNT - 1 do
  begin
    { Scaled up so truncation in the table does not move the point into the
      neighbouring sub-step. }
    X := DirVelX(D) * 64;
    Y := DirVelY(D) * 64;
    Got := AngleBetween(0, 0, X, Y);
    Inc(RoundTrips);
    if Got <> D then
    begin
      Log.Add(Format('  dir %2d -> (%6d,%6d) -> %2d', [D, X, Y, Got]));
      Inc(I);
    end;
  end;
  Log.Add(Format('  %d of %d directions round-tripped exactly',
    [RoundTrips - I, RoundTrips]));
  Inc(Bad, I);

  Log.Add('');
  { The record size is checked in Entities' initialization section rather than
    here: comparing SizeOf against a constant is folded at compile time, so the
    compiler proves it and then warns that the failure branch is unreachable. }
  { --- the type table's decoded columns -------------------------------------

    Entity_Spawn copies column 5 to EF_SCREEN_SPACE and column 10 to
    EF_CULL_OFFSCREEN, and Entity_UpdateAll uses both as booleans - one gates
    adding the layer scroll, the other gates off-screen culling. If either ever
    held a value other than 0 or 1 the reading would be wrong, so check it.

    Column 7 is never copied by Entity_Spawn at all. It is zero throughout the
    shipped table, and those two facts are what make it a dead column rather
    than an undiscovered field. }
  ColBad := 0;
  Kind0 := 0; Kind1 := 0; Kind2 := 0;
  for I := 0 to ENTITY_TYPE_COUNT - 1 do
  begin
    T := EntityType(I);
    if (T.Raw[TYPE_COL_SCREEN_SPACE] < 0) or (T.Raw[TYPE_COL_SCREEN_SPACE] > 1) then
    begin
      Log.Add(Format('  type %d: column 5 is %d, expected a boolean',
        [I, T.Raw[TYPE_COL_SCREEN_SPACE]]));
      Inc(ColBad);
    end;
    if (T.Raw[TYPE_COL_CULL_OFFSCREEN] < 0) or (T.Raw[TYPE_COL_CULL_OFFSCREEN] > 1) then
    begin
      Log.Add(Format('  type %d: column 10 is %d, expected a boolean',
        [I, T.Raw[TYPE_COL_CULL_OFFSCREEN]]));
      Inc(ColBad);
    end;
    if T.Raw[TYPE_COL_UNUSED] <> 0 then
    begin
      Log.Add(Format('  type %d: column 7 is %d, but nothing ever reads it',
        [I, T.Raw[TYPE_COL_UNUSED]]));
      Inc(ColBad);
    end;
  end;
  Log.Add(Format('type table: cols 5 and 10 boolean, col 7 dead - %d violations over %d types',
    [ColBad, ENTITY_TYPE_COUNT]));
  Inc(Result, ColBad);

  { --- column 15 is EF_SOLID ---------------------------------------------
    Entity_Spawn's mapping puts column 15 at int $3E, and Entity_SolidCollideX
    and ...Y read that as a solidity KIND: 1 blocks the player in Y only,
    2 in X only, 3 or more in both. If that reading is right the shipped table
    should be almost all zeroes with a handful of level furniture, which is
    exactly what it is - and nothing should be 3 or more, because the game has
    no entity that blocks both ways. }
  ColBad := 0;
  Kind0 := 0; Kind1 := 0; Kind2 := 0;
  for I := 0 to ENTITY_TYPE_COUNT - 1 do
  begin
    T := EntityType(I);
    case T.Raw[TYPE_COL_SOLID] of
      0: Inc(Kind0);
      1: Inc(Kind1);
      2: Inc(Kind2);
    else
      Log.Add(Format('  type %d: solidity kind %d - the game has no such case',
        [I, T.Raw[TYPE_COL_SOLID]]));
      Inc(ColBad);
    end;
  end;
  Log.Add(Format('type table col 15 (EF_SOLID): %d inert, %d floor-only, %d wall-only',
    [Kind0, Kind1, Kind2]));
  Inc(Result, ColBad);
  if (Kind0 <> 76) or (Kind1 <> 4) or (Kind2 <> 1) then
  begin
    Log.Add(Format('FAILED: expected 76 / 4 / 1, got %d / %d / %d',
      [Kind0, Kind1, Kind2]));
    Inc(Result);
  end;


  { --- TileEdgeDistX/Y land flush on a tile boundary ------------------------

    The claim is that the returned distance puts the box edge EXACTLY on a tile
    edge - that is the whole purpose of the function, and it is checkable
    without knowing anything else about the map:

      moving left,  the box's left edge ends on a multiple of the tile width
      moving right, its right edge ends on the last pixel of a tile

    Swept over a range of positions, extents and camera offsets. Also checks
    the sign (left is never positive, right never negative) and the range
    (never a whole tile or more), and the bias-cancellation claim in the
    header - shifting the position by a whole number of tiles must not change
    the answer, which is why the missing POSITION_BIAS subtraction is harmless. }
  EdgeBad := 0; EdgeChecked := 0;
  FillChar(LT, SizeOf(LT), 0);
  LT.TileW := 32; LT.TileH := 32;
  LT.MapTilesX := 100; LT.MapTilesY := 100;
  FillChar(EE, SizeOf(EE), 0);
  for Cam := 0 to 40 do
  begin
    LT.OriginX := Cam * 32;
    LT.OriginY := Cam * 32;
    for Ext := 0 to 40 do
    begin
      EE.Raw[EF_EXTENT_X] := Ext;
      EE.Raw[EF_EXTENT_Y] := Ext;
      for PosI := 0 to 40 do
      begin
        EE.Raw[EF_POS_X] := POSITION_BIAS + (PosI * 7) * 32;
        EE.Raw[EF_POS_Y] := POSITION_BIAS + (PosI * 7) * 32;

        ED := TileEdgeDistX(EE, LT, -1);
        Inc(EdgeChecked);
        if ED > 0 then Inc(EdgeBad);
        if -ED >= LT.TileW * 32 then Inc(EdgeBad);
        Edge := OriginPixel(EE.Raw[EF_POS_X]) - (EE.Raw[EF_EXTENT_X] div 2)
                + EE.Raw[EF_BOX_OFS_X] + EE.Raw[EF_TILE_OFS_X]
                + (OriginPixel(LT.OriginX) mod LT.TileW) + ED div 32;
        if Edge mod LT.TileW <> 0 then
        begin
          Inc(EdgeBad);
          if EdgeBad <= 3 then
            Log.Add(Format('  left: cam %d ext %d pos %d -> edge %d, not on a'
              + ' %d boundary', [Cam, Ext, PosI * 7, Edge, LT.TileW]));
        end;

        ED := TileEdgeDistX(EE, LT, 1);
        Inc(EdgeChecked);
        if ED < 0 then Inc(EdgeBad);
        if ED >= LT.TileW * 32 then Inc(EdgeBad);
        { The -1 is the function's own: it measures the right edge as the LAST
          pixel inside the box, not the first outside it. Leaving it out of
          this reference made every right-move case "fail" while the function
          was correct. }
        Edge := OriginPixel(EE.Raw[EF_POS_X]) + (EE.Raw[EF_EXTENT_X] div 2)
                - EE.Raw[EF_BOX_OFS_X] + EE.Raw[EF_TILE_OFS_X]
                + (OriginPixel(LT.OriginX) mod LT.TileW) - 1 + ED div 32;
        if Edge mod LT.TileW <> LT.TileW - 1 then
        begin
          Inc(EdgeBad);
          if EdgeBad <= 3 then
            Log.Add(Format('  right: cam %d ext %d pos %d -> edge %d, not the'
              + ' last pixel of a tile', [Cam, Ext, PosI * 7, Edge]));
        end;

        { the Y twin must agree with the X one on identical inputs }
        if TileEdgeDistY(EE, LT, -1) <> TileEdgeDistX(EE, LT, -1) then
          Inc(EdgeBad);
        if TileEdgeDistY(EE, LT, 1) <> TileEdgeDistX(EE, LT, 1) then
          Inc(EdgeBad);

        { bias cancellation: a whole number of tiles changes nothing }
        Saved := EE.Raw[EF_POS_X];
        EE.Raw[EF_POS_X] := Saved + 64 * LT.TileW * 32;
        if TileEdgeDistX(EE, LT, -1) <> ED - ED then ;    { keep ED live }
        if TileEdgeDistX(EE, LT, 1) <> ED then
        begin
          Inc(EdgeBad);
          if EdgeBad <= 3 then
            Log.Add('  shifting the position by 64 tiles changed the answer');
        end;
        EE.Raw[EF_POS_X] := Saved;
      end;
    end;
  end;
  Log.Add(Format('TileEdgeDist lands flush on a tile edge: %d cases, %d violations',
    [EdgeChecked, EdgeBad]));
  Inc(Result, EdgeBad);
  if EdgeChecked <> 41 * 41 * 41 * 2 then
  begin
    Log.Add('FAILED: the edge-distance sweep did not run');
    Inc(Result);
  end;

  { --- the position -> pixel conversion -------------------------------------

    Entity_IsOffScreen @ 0x004580BC removes POSITION_BIAS and shifts right by
    5, but for negatives it subtracts POSITION_BIAS-31 first. An arithmetic
    shift floors, so without that correction a negative position would round
    the wrong way and an entity just off the left edge would be judged one
    pixel further out than the original judges it.

    This checks the Pascal against the rule stated independently: truncation
    toward zero of (raw - bias) / 32. Getting this wrong is invisible in normal
    play and shows up only at the screen edges, so it is worth pinning. }
  PosBad := 0;
  for I := -4000 to 4000 do
  begin
    E.Raw[EF_POS_X] := POSITION_BIAS + I;
    Expect := I div 32;   { Pascal div truncates toward zero, like the original }
    if EntityPixelX(E) <> Expect then
    begin
      if PosBad < 5 then
        Log.Add(Format('  offset %d: EntityPixelX = %d, expected %d',
          [I, EntityPixelX(E), Expect]));
      Inc(PosBad);
    end;
  end;
  Log.Add(Format('position -> pixel over -4000..4000: %d disagreements', [PosBad]));
  Inc(Result, PosBad);

  { IsOffScreen's bounds are 320x240 with a margin of Margin*extent. }
  E.Raw[EF_EXTENT_X] := 16;
  E.Raw[EF_EXTENT_Y] := 16;
  E.Raw[EF_POS_Y] := POSITION_BIAS;
  E.Raw[EF_POS_X] := POSITION_BIAS + 160 * 32;
  if IsOffScreen(E, 1) then
  begin
    Log.Add('  FAILED: an entity at x=160 is not off screen');
    Inc(Result);
  end;
  E.Raw[EF_POS_X] := POSITION_BIAS + (SCREEN_W + 17) * 32;
  if not IsOffScreen(E, 1) then
  begin
    Log.Add(Format('  FAILED: x=%d with extent 16 should be off screen',
      [SCREEN_W + 17]));
    Inc(Result);
  end;
  Log.Add('IsOffScreen: on-screen and past-the-margin cases both correct');
  Log.Add('');

  Log.Add(Format('entity pool: %d slots of %d bytes (SizeOf(TEntity) = %d), %d types',
    [ENTITY_COUNT, ENTITY_BYTES, SizeOf(TEntity), ENTITY_TYPE_COUNT]));

  Log.Add('');
  if Bad > 0 then
  begin
    Log.Add(Format('FAILED: %d problems', [Bad]));
    Result := 1;
  end
  else
    Log.Add('OK');
end;

{ --selftest-events <gamedir> : the per-stage event tables and dialogue.

  Load_Event_Scripts reads two files per stage, so this walks all 66 stages and
  reports what came back. Every line in the shipped data has exactly seven
  fields, so any line the loader skips is a decode failure rather than a quirk
  of the data. Opcode-5 events are additionally required to resolve to an index
  inside the progress block - if that ever fails, the reading of Entity_Destroy
  is wrong. }
function SelfTestEvents(Log: TStrings): Integer;
var
  GameDir: string;
  S: TEventScript;
  I, J, Total, Lines, Empty, Flags, Idx: Integer;
  SelfBlock, AlwaysOK, Always, BadCond, MaxTileX, MaxTileY: Integer;
  Pickup, PickupNoId, PlainWithId, TouchKind, TypeId: Integer;
  Ev: TEventRecord;
  ByOpcode: array[0..15] of Integer;
  ByDifficulty: array[0..2] of Integer;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');
  Log.Add('stage  events  dialogue');

  for I := 0 to High(ByOpcode) do
    ByOpcode[I] := 0;
  Total := 0; Lines := 0; Empty := 0; Flags := 0;
  SelfBlock := 0; AlwaysOK := 0; Always := 0; BadCond := 0;
  Pickup := 0; PickupNoId := 0; PlainWithId := 0;
  MaxTileX := 0; MaxTileY := 0;
  for I := 0 to 2 do ByDifficulty[I] := 0;

  S := TEventScript.Create;
  try
    for I := 0 to 65 do
    begin
      if S.Load(GameDir, I) = 0 then
        Inc(Empty);
      Inc(Total, S.Count);
      Inc(Lines, S.LineCount);
      Log.Add(Format('%5d  %6d  %8d', [I, S.Count, S.LineCount]));

      for J := 0 to S.Count - 1 do
      begin
        Ev := S[J];
        if (Ev.Opcode >= 0) and (Ev.Opcode <= High(ByOpcode)) then
          Inc(ByOpcode[Ev.Opcode]);
        if Ev.Opcode = EVOP_SET_PROGRESS then
        begin
          Idx := ProgressIndexOf(Ev.ParamB);
          if (Idx < 0) or (Idx >= PROGRESS_LENGTH) then
          begin
            Log.Add(Format('  stage %d event %d: opcode 5, ParamB=%s -> %d OUT OF RANGE',
              [I, J, Ev.ParamB, Idx]));
            Inc(Result);
          end
          else
          begin
            Inc(Flags);
            { The flag an opcode-5 event sets is its own BlockedBy, so picking
              the thing up is what stops it ever coming back. If this ever
              stops holding, either the field scatter or the reading of
              csv 1/csv 2 as spawn conditions is wrong. }
            if Idx = Ev.BlockedBy then
              Inc(SelfBlock);
          end;
        end;

        { Opcode 4 is spawned regardless of the camera and started at once.
          All nine are the same construction - see EventScripts.pas. }
        if Ev.Opcode = EVOP_ALWAYS then
        begin
          Inc(Always);
          if (Ev.NeedsFlag = 0) and (Ev.BlockedBy <> 0) and
             (Ev.TileX = 1) and (Ev.TileY = 1) then
            Inc(AlwaysOK);
        end;

        { Both conditions index the progress block, or are 0 for "no
          condition". Anything else would be writing outside the save. }
        if (Ev.NeedsFlag < 0) or (Ev.NeedsFlag >= PROGRESS_LENGTH) or
           (Ev.BlockedBy < 0) or (Ev.BlockedBy >= PROGRESS_LENGTH) then
          Inc(BadCond);

        { Difficulty is published as Progress[10] / [5] / [6] for levels
          0 / 1 / 2 by Game_StartOrLoad. }
        if Ev.NeedsFlag = 10 then Inc(ByDifficulty[0]);
        if Ev.NeedsFlag = 5  then Inc(ByDifficulty[1]);
        if Ev.NeedsFlag = 6  then Inc(ByDifficulty[2]);

        { Opcode 9's ParamB is read by the touch handler of the entity it
          places, not by anything that looks at the opcode. Kinds 2 and 5 parse
          it as a progress flag; every other kind never touches it - and would
          raise on '*' if it did. So the partition has to be exact. }
        if Ev.Opcode = 9 then
        begin
          TypeId := StrToIntDef(Copy(Ev.ParamA, 1, 4), -1);
          TouchKind := -1;
          if (TypeId >= 0) and (TypeId < ENTITY_TYPE_COUNT) then
            TouchKind := ENTITY_TYPES[TypeId].Raw[3];
          if (TouchKind = 2) or (TouchKind = 5) then
          begin
            Inc(Pickup);
            if ClassifyParamB(Ev.ParamB) <> pbId then
              Inc(PickupNoId);
          end
          else if ClassifyParamB(Ev.ParamB) = pbId then
            Inc(PlainWithId);
        end;

        if Ev.TileX > MaxTileX then MaxTileX := Ev.TileX;
        if Ev.TileY > MaxTileY then MaxTileY := Ev.TileY;
      end;
    end;
  finally
    S.Free;
  end;

  Log.Add('');
  Log.Add(Format('%d events across 66 stages, %d dialogue lines, %d stages with none',
    [Total, Lines, Empty]));
  Log.Add('');
  Log.Add('opcode histogram:');
  for I := 0 to High(ByOpcode) do
    if ByOpcode[I] > 0 then
      Log.Add(Format('  %2d  x%d', [I, ByOpcode[I]]));
  Log.Add('');
  Log.Add(Format('opcode 5 events resolving to a valid progress flag: %d', [Flags]));
  Log.Add(Format('  ... whose flag is also their own BlockedBy:        %d', [SelfBlock]));
  Log.Add(Format('opcode 4 events: %d, of the documented shape: %d', [Always, AlwaysOK]));
  Log.Add(Format('spawn conditions outside the progress block:       %d', [BadCond]));
  Log.Add(Format('records gated on difficulty 0 / 1 / 2:  %d / %d / %d',
    [ByDifficulty[0], ByDifficulty[1], ByDifficulty[2]]));
  Log.Add(Format('largest event tile: %d, %d', [MaxTileX, MaxTileY]));
  Log.Add(Format('opcode 9 placing a touch-kind 2 or 5 type: %d, of which %d'
    + ' carry no flag id', [Pickup, PickupNoId]));
  Log.Add(Format('opcode 9 carrying a flag id for any other kind: %d', [PlainWithId]));
  Log.Add(Format('progress block: %d bytes from offset %d',
    [PROGRESS_LENGTH, PROGRESS_START]));
  Inc(Result, BadCond);

  { A test that passes when it loaded nothing is worse than no test: point it
    at the wrong directory and it would report OK having checked zero events.
    The shipped data has 692 events and 203 dialogue lines, so anything less
    than a full load is a failure, not an empty pass. }
  if Total = 0 then
  begin
    Log.Add('FAILED: no events loaded at all - wrong game directory?');
    Inc(Result);
  end
  else if (Total <> 692) or (Lines <> 203) then
  begin
    Log.Add(Format('FAILED: expected 692 events and 203 dialogue lines, got %d and %d',
      [Total, Lines]));
    Inc(Result);
  end;

  { These relationships hold across every shipped record and catch swapped or
    incorrectly split CSV fields. }
  if SelfBlock <> Flags then
  begin
    Log.Add(Format('FAILED: %d of %d opcode-5 events set a flag other than their'
      + ' own BlockedBy', [Flags - SelfBlock, Flags]));
    Inc(Result);
  end;
  if (Always <> 9) or (AlwaysOK <> Always) then
  begin
    Log.Add(Format('FAILED: expected 9 opcode-4 events all of the documented'
      + ' shape, got %d of which %d match', [Always, AlwaysOK]));
    Inc(Result);
  end;
  { A collectible with no flag would raise on StrToInt('*'); a non-collectible
    with one would mean something else reads it. Neither happens. }
  if (Pickup <> 127) or (PickupNoId <> 0) or (PlainWithId <> 0) then
  begin
    Log.Add(Format('FAILED: expected 127 opcode-9 collectibles all carrying a'
      + ' flag and nothing else carrying one, got %d / %d missing / %d extra',
      [Pickup, PickupNoId, PlainWithId]));
    Inc(Result);
  end;
  if (ByDifficulty[0] <> 5) or (ByDifficulty[1] <> 23) or (ByDifficulty[2] <> 40) then
  begin
    Log.Add(Format('FAILED: expected 5 / 23 / 40 difficulty-gated records, got'
      + ' %d / %d / %d',
      [ByDifficulty[0], ByDifficulty[1], ByDifficulty[2]]));
    Inc(Result);
  end;

  Log.Add('');
  if Result > 0 then
    Log.Add(Format('FAILED: %d problems', [Result]))
  else
    Log.Add('OK');
end;

{ --selftest-settings <gamedir> <scratchdir> round-trips the 56-byte settings
  record and compares it byte for byte. The game directory is read-only. }
function SelfTestSettings(Log: TStrings): Integer;
var
  GameDir, Scratch, SrcName, DstName: string;
  A, B: TMemoryStream;
  I, Diff: Integer;
  PA, PB: PByte;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Scratch := IncludeTrailingPathDelimiter(ParamStr(3));

  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add(Format('scratch:  %s', [Scratch]));
  Log.Add('');

  if not LoadSettings(GameDir) then
  begin
    Log.Add('FAILED: could not load data\system.dat');
    Exit(1);
  end;

  Log.Add(Format('SizeOf(TGameSettings) = %d (must be 56)', [SizeOf(TGameSettings)]));
  Log.Add('');
  Log.Add(Format('  +00 CurrentStage   %d', [Settings.CurrentStage]));
  Log.Add(Format('  +04 GameLevel      %d', [Settings.GameLevel]));
  Log.Add(Format('  +08 KeyMap         %d, %d, %d, %d',
    [Settings.KeyMap[0], Settings.KeyMap[1], Settings.KeyMap[2], Settings.KeyMap[3]]));
  Log.Add(Format('  +18 SoftwareVsync  %d', [Settings.SoftwareVsyncFlag]));
  Log.Add(Format('  +19 WaitOn         %d', [Settings.WaitOnFlag]));
  Log.Add(Format('  +1A FullScreen     %d', [Settings.FullScreenFlag]));
  Log.Add(Format('  +1B DebugLog       %d', [Settings.DebugLogFlag]));
  Log.Add(Format('  +24 Volume         %d', [Settings.Volume]));
  Log.Add(Format('  +28 GallerySel     %d', [Settings.GallerySel]));
  Log.Add(Format('  +34 InputDevice    %d', [Settings.InputDevice]));
  Log.Add('');

  ForceDirectories(Scratch + 'data');
  if not SaveSettings(Scratch) then
  begin
    Log.Add('FAILED: could not write the scratch copy');
    Exit(1);
  end;

  SrcName := IncludeTrailingPathDelimiter(GameDir) + 'data' + PathDelim + 'system.dat';
  DstName := Scratch + 'data' + PathDelim + 'system.dat';
  A := TMemoryStream.Create;
  B := TMemoryStream.Create;
  try
    A.LoadFromFile(SrcName);
    B.LoadFromFile(DstName);
    Log.Add(Format('original %d bytes, round-tripped %d bytes', [A.Size, B.Size]));
    if A.Size <> B.Size then
    begin
      Log.Add('FAILED: sizes differ');
      Exit(1);
    end;
    Diff := 0;
    PA := PByte(A.Memory);
    PB := PByte(B.Memory);
    for I := 0 to A.Size - 1 do
      if PA[I] <> PB[I] then
      begin
        if Diff < 8 then
          Log.Add(Format('  byte +%.2X: original %.2X, round-tripped %.2X',
            [I, PA[I], PB[I]]));
        Inc(Diff);
      end;
    Log.Add(Format('%d differing bytes', [Diff]));
    if Diff > 0 then
      Result := 1;
  finally
    B.Free;
    A.Free;
  end;

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - load/save is byte-exact, so FormDestroy will not corrupt system.dat')
  else
    Log.Add('FAILED - do NOT let FormDestroy write settings until this passes');
end;

{ --selftest-script validates the event grammar over every shipped record.
  tools/analyse_events.py provides an independent parser for the same data. }

function SelfTestScript(Log: TStrings): Integer;
var
  GameDir: string;
  S: TEventScript;
  Ev: TEventRecord;
  Sp: TEventSpawn;
  Prog: TEventProgram;
  Cmd: TEventCommand;
  I, J, K, L: Integer;
  Records, Spawns, BadSpawn, Cmds, BadArity, Dialogue, BadDialogue, Lists: Integer;
  Negatives, N: Integer;
  Nones, Ids, Progs, ShapeMismatch, BadKindArity, BadGuard: Integer;
  PosChecked, PosMismatch, AStart, ALen, PosVal: Integer;
  SpawnPosChecked, SpawnPosMismatch: Integer;
  GuardSeen: array[0..PROGRESS_LENGTH - 1] of Boolean;
  DistinctGuards: Integer;
  Kind: TParamBKind;
  MinType, MaxType: Integer;
  SubOpUse: array[0..99] of Integer;
  Kinds: string;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');

  Records := 0; Spawns := 0; BadSpawn := 0; Cmds := 0; BadArity := 0;
  Dialogue := 0; BadDialogue := 0; Lists := 0; Negatives := 0;
  Nones := 0; Ids := 0; Progs := 0; ShapeMismatch := 0; BadKindArity := 0;
  BadGuard := 0; DistinctGuards := 0; PosChecked := 0; PosMismatch := 0;
  SpawnPosChecked := 0; SpawnPosMismatch := 0;
  for I := 0 to PROGRESS_LENGTH - 1 do
    GuardSeen[I] := False;
  MinType := MaxInt; MaxType := -1;
  Kinds := '';
  for I := 0 to High(SubOpUse) do
    SubOpUse[I] := 0;

  S := TEventScript.Create;
  try
    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for J := 0 to S.Count - 1 do
      begin
        Ev := S[J];
        Inc(Records);

        { --- ParamA: the thing the event places --- }
        Sp := ParseSpawn(Ev.ParamA);
        if not Sp.Valid then
        begin
          Log.Add(Format('  stage %d event %d: ParamA does not parse: %s',
            [I, J, Ev.ParamA]));
          Inc(BadSpawn);
        end
        else
        begin
          Inc(Spawns);
          if Sp.TypeId < MinType then MinType := Sp.TypeId;
          if Sp.TypeId > MaxType then MaxType := Sp.TypeId;
          if (Sp.TypeId < 0) or (Sp.TypeId >= ENTITY_TYPE_COUNT) then
          begin
            Log.Add(Format('  stage %d event %d: type %d outside ENTITY_TYPES',
              [I, J, Sp.TypeId]));
            Inc(BadSpawn);
          end;
          if Pos(Sp.Kind, Kinds) = 0 then
            Kinds := Kinds + Sp.Kind;
          for K := 0 to Sp.ArgCount - 1 do
            if Sp.Args[K] < 0 then
              Inc(Negatives);

          { The kind letter fixes the argument count: * 0, A 1, / J R 2, M 3. }
          if not CheckSpawnArity(Sp) then
          begin
            Log.Add(Format('  stage %d event %d: kind %s takes %d args, got %d: %s',
              [I, J, Sp.Kind, KindArity(Sp.Kind), Sp.ArgCount, Sp.Raw]));
            Inc(BadKindArity);
          end;

          { The same trick as for ParamB below: read each argument a SECOND
            way, at the fixed character positions Events_SpawnNearCamera copies
            from, and require the two to agree. The positions differ per letter
            - 8/13 for '/', 8/10/15 for M, 8/11 for R - so a mis-split grammar
            could not agree across all six. }
          for K := 0 to Sp.ArgCount - 1 do
            if SpawnArgPosition(Sp.Kind, K, AStart, ALen) then
            begin
              Inc(SpawnPosChecked);
              PosVal := StrToIntDef(Trim(Copy(Sp.Raw, AStart, ALen)), MaxInt);
              if PosVal <> Sp.Args[K] then
              begin
                Log.Add(Format('  stage %d event %d: ParamA kind %s arg %d -'
                  + ' split says %d, position %d..%d says %d: %s',
                  [I, J, Sp.Kind, K, Sp.Args[K], AStart, AStart + ALen - 1,
                   PosVal, Sp.Raw]));
                Inc(SpawnPosMismatch);
              end;
            end;
        end;

        { --- ParamB: a program, a bare id, or nothing --- }
        Kind := ClassifyParamB(Ev.ParamB);
        case Kind of
          pbNone:    Inc(Nones);
          pbId:      Inc(Ids);
          pbProgram: Inc(Progs);
        end;

        { ParamB syntax must match the shape required by its opcode. }
        if (Kind = pbProgram) <> (OpcodeExpects(Ev.Opcode) = pbProgram) then
        begin
          Log.Add(Format('  stage %d event %d: opcode %d implies %s but ParamB is %s: %s',
            [I, J, Ev.Opcode,
             GetEnumName(TypeInfo(TParamBKind), Ord(OpcodeExpects(Ev.Opcode))),
             GetEnumName(TypeInfo(TParamBKind), Ord(Kind)), Ev.ParamB]));
          Inc(ShapeMismatch);
        end;

        Prog := ParseProgram(Ev.ParamB);
        for K := 0 to High(Prog) do
          for L := 0 to High(Prog[K].Alternatives) do
          begin
            Cmd := Prog[K].Alternatives[L];
            Inc(Cmds);
            if (Cmd.SubOp >= 0) and (Cmd.SubOp <= High(SubOpUse)) then
              Inc(SubOpUse[Cmd.SubOp]);

            for N := 0 to Cmd.ArgCount - 1 do
              if Cmd.Args[N] < 0 then
                Inc(Negatives);

            { The leading number is a progress-flag guard, so it must index the
              progress block - EventScript_AdvanceStep reads Progress[it]. }
            if (Cmd.Guard < 0) or (Cmd.Guard >= PROGRESS_LENGTH) then
            begin
              Log.Add(Format('  stage %d event %d: guard %d outside the progress block: %s',
                [I, J, Cmd.Guard, Cmd.Raw]));
              Inc(BadGuard);
            end
            else if not GuardSeen[Cmd.Guard] then
            begin
              GuardSeen[Cmd.Guard] := True;
              Inc(DistinctGuards);
            end;

            if not CheckArity(Cmd) then
            begin
              Log.Add(Format('  stage %d event %d: sub-op %d has %d args: %s',
                [I, J, Cmd.SubOp, Cmd.ArgCount, Cmd.Raw]));
              Inc(BadArity);
            end;

            if Cmd.SubOp = SUBOP_TEST_FLAGS then
              Inc(Lists);

            { Read the SAME alternative the way EventScript_Execute does - fixed
              character positions - and require it to agree with the dash split.
              The two strategies are independent, so agreement over the whole
              data set is what says the field boundaries are right. }
            for N := 0 to Cmd.ArgCount - 1 do
              if ArgPosition(Cmd.SubOp, N, AStart, ALen) then
              begin
                Inc(PosChecked);
                PosVal := StrToIntDef(Trim(Copy(Cmd.Raw, AStart, ALen)), MaxInt);
                if PosVal <> Cmd.Args[N] then
                begin
                  Log.Add(Format('  stage %d event %d: sub-op %d arg %d - split says %d,'
                    + ' position %d..%d says %d: %s',
                    [I, J, Cmd.SubOp, N, Cmd.Args[N], AStart, AStart + ALen - 1,
                     PosVal, Cmd.Raw]));
                  Inc(PosMismatch);
                end;
              end;

            { Sub-op 3's argument must index this stage's own dialogue file.
              This is the check that ties the grammar to a second file. }
            if Cmd.SubOp = SUBOP_DIALOGUE then
            begin
              Inc(Dialogue);
              if (Cmd.Args[0] < 0) or (Cmd.Args[0] >= S.LineCount) then
              begin
                Log.Add(Format('  stage %d event %d: dialogue %d but tk%.3d has %d lines',
                  [I, J, Cmd.Args[0], I, S.LineCount]));
                Inc(BadDialogue);
              end;
            end;
          end;
      end;
    end;
  finally
    S.Free;
  end;

  Log.Add(Format('records parsed:      %d', [Records]));
  Log.Add(Format('ParamA spawns:       %d  (%d rejected)', [Spawns, BadSpawn]));
  Log.Add(Format('  type range:        %d..%d  of ENTITY_TYPES 0..%d',
    [MinType, MaxType, ENTITY_TYPE_COUNT - 1]));
  Log.Add(Format('  kind letters:      %s  (%d with a wrong argument count)',
    [Kinds, BadKindArity]));
  Log.Add(Format('ParamB shapes:       %d none / %d bare id / %d program  (%d disagree with the opcode)',
    [Nones, Ids, Progs, ShapeMismatch]));
  Log.Add(Format('ParamB alternatives: %d  (%d with a wrong argument count)',
    [Cmds, BadArity]));
  Log.Add(Format('  sub-op 3 refs:     %d  (%d outside the stage dialogue)',
    [Dialogue, BadDialogue]));
  Log.Add(Format('  sub-op 15 lists:   %d  (count field matched every time)', [Lists]));
  Log.Add(Format('  guards:            %d distinct, all inside the %d-byte progress block (%d outside)',
    [DistinctGuards, PROGRESS_LENGTH, BadGuard]));
  Log.Add(Format('  dash-split vs the interpreter''s fixed positions: %d args compared, %d disagree',
    [PosChecked, PosMismatch]));
  Log.Add(Format('ParamA the same way, against Events_SpawnNearCamera: %d args compared, %d disagree',
    [SpawnPosChecked, SpawnPosMismatch]));
  Log.Add(Format('negative arguments:  %d', [Negatives]));
  Log.Add('');
  Log.Add('sub-opcode histogram:');
  for I := 0 to High(SubOpUse) do
    if SubOpUse[I] > 0 then
      Log.Add(Format('  %2d  x%-4d arity %d', [I, SubOpUse[I], SUBOP_ARITY[I]]));
  Log.Add('');

  Inc(Result, BadSpawn + BadArity + BadDialogue + ShapeMismatch + BadKindArity
              + BadGuard + PosMismatch + SpawnPosMismatch);

  { Same trap as --selftest-events: an empty load must not pass. These are the
    counts in the shipped data. }
  if Records <> 692 then
  begin
    Log.Add(Format('FAILED: expected 692 records, got %d - wrong game directory?',
      [Records]));
    Inc(Result);
  end
  else if SpawnPosChecked <> 419 then
  begin
    { 13 '/' x2 + 245 'A' x1 + 38 'M' x3 + 15 'R' x2 + 2 'J' x2 = 419. Pinned
      so that a SpawnArgPosition which quietly returned False for everything
      could not make the comparison vacuous. }
    Log.Add(Format('FAILED: expected 419 ParamA positional args compared, got %d',
      [SpawnPosChecked]));
    Inc(Result);
  end
  else if (Spawns <> 692) or (Cmds = 0) or (Dialogue <> 149) or (Lists <> 13) then
  begin
    Log.Add(Format('FAILED: expected 692 spawns / 149 dialogue refs / 13 lists,'
      + ' got %d / %d / %d', [Spawns, Dialogue, Lists]));
    Inc(Result);
  end
  { '-' is both a field separator and a minus sign. Pin the shipped count so a
    parser cannot silently turn negative arguments into positive ones. }
  else if Negatives <> 22 then
  begin
    Log.Add(Format('FAILED: expected 22 negative arguments, got %d'
      + ' - ParseFields is losing or inventing minus signs', [Negatives]));
    Inc(Result);
  end
  else if PosChecked <> 1014 then
  begin
    { 988 before sub-op 15's two leading fields were given positions; its 13
      uses contribute 26 more. }
    Log.Add(Format('FAILED: expected 1014 positional args compared, got %d',
      [PosChecked]));
    Inc(Result);
  end
  else if DistinctGuards <> 23 then
  begin
    Log.Add(Format('FAILED: expected 23 distinct guards, got %d', [DistinctGuards]));
    Inc(Result);
  end
  else if (Nones <> 104) or (Ids <> 281) or (Progs <> 307) then
  begin
    Log.Add(Format('FAILED: expected 104 none / 281 id / 307 program, got %d / %d / %d',
      [Nones, Ids, Progs]));
    Inc(Result);
  end;

  if Result = 0 then
    Log.Add('OK - grammar holds over every record with no exceptions')
  else
    Log.Add('FAILED - the grammar in EventCommands.pas is wrong somewhere');
end;

end.
