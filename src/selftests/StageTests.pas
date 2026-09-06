{ Self-tests for the stage table and the terrain animation it drives. }

unit StageTests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, TypInfo,
  QdaArchive, SoundTable, WaveFile, AudioMixer, AudioOut, MidiFile, KbgmPlayer,
  Directions, Entities, EventScripts, EventCommands, PlayerState, GameState,
  Stages, Camera, TileMaps, Player, EntityHandlers, EventRunner, GameSession,
  SpritePool, Sprites, Dialogue, BgAnime, UnitInit, Title, Ending, Opening,
  GameFont, DDDDComponent, Surfaces;

function SelfTestStages(Log: TStrings): Integer;

implementation

{ ---------------------------------------------------------------------------
  --selftest-stages : the stage table.

  Most of stage.dat's 16 columns are constant across all 66 rows, so the useful
  thing to check is not "does it load" but "do the relationships still hold" -
  csv0 = csv1, csv2 = row number, csv15 = csv0 except at row 58, and the seven
  dead columns still dead. Those are what Stages.pas's header claims, and this
  is what stops the claims rotting.

  It also checks the flush fit that makes the row-number reading credible: 65
  map files for rows 1..65, with row 0 the placeholder.
  --------------------------------------------------------------------------- }

{ The animated tiles Terrain_Configure declares, checked against the literals
  in the function itself.

  Every one of the thirty frames is written into the binary TWICE over: once
  as the tile id the track belongs to and its position in a run, and once as
  the source pixel coordinates the drawing needs. TERRAIN_ANIM stores only the
  ids; this recomputes the coordinates through TileMaps' TileSrcX/TileSrcY and
  requires all sixty numbers to come back.

  That makes it a real check in two directions at once. It pins the table, and
  it pins the div/mod AXIS ORDER, which TileMaps.pas had believed on the
  strength of the drawing code alone and flagged as the line to revisit if
  tiles ever came out transposed. Under the obvious x/y reading not one of the
  six tracks lands on its own tile. }
function TestTerrainAnim(Log: TStrings): Integer;
const
  { Read straight off 0x004645B0, in the order the arms declare them:
    terrain, then track, then frame. Each pair is (srcY, srcX) - the two
    values pushed to MyBgAnime_AddFrame @ 0x0044E25C, whose third argument is
    8 every time. Y comes first, as it does in Load_Map. }
  LITERALS: array[0..29, 0..1] of Integer = (
    { terrain 1, tile 7  } ($00, $E0), ($00, $100), ($00, $120), ($00, $100),
    { terrain 1, tile 17 } ($20, $E0), ($20, $100), ($20, $120), ($20, $100),
    { terrain 2, tile 75 } ($E0, $A0), ($E0, $C0),  ($E0, $E0),  ($E0, $100),
                           ($E0, $120),
    { terrain 3, tile 17 } ($20, $E0), ($20, $100), ($20, $120), ($20, $100),
    { terrain 3, tile 7  } ($00, $E0), ($00, $100), ($00, $120), ($00, $100),
    { terrain 4, tile 15 } ($20, $A0), ($20, $C0),  ($20, $E0),  ($20, $100),
                           ($20, $120),
    { terrain 4, tile 63 } ($C0, $60), ($C0, $80),  ($C0, $A0),  ($C0, $80)
  );
  SHEET_COLS = 10;
  TILE_PX    = 32;

  { Expected values are independent of the table under test, so swapping table
    entries cannot make both sides of the assertion change together. }
  BIN_THRESHOLD: array[1..9] of Integer =
    ($32, $32, $3C, $32, $46, $3C, $3C, $3C, $50);
  BIN_KILL: array[1..9] of Integer =
    ($1D, $1D, $1D, $1D, $1D, $1D, $1D, $1D, 1000);
var
  Terr, Track, Frame, N, Tracks, Frames, Obvious, Thr, Kill, Bad: Integer;
  A: TTerrainAnim;
  Id, GotX, GotY: Integer;
begin
  Bad := 0;
  N := 0;
  Tracks := 0;
  Frames := 0;
  Log.Add('');
  Log.Add('--- Terrain_Configure''s animated tiles ---');

  for Terr := 1 to TERRAIN_MAX do
  begin
    A := TERRAIN_ANIM[Terr];
    Inc(Tracks, A.TrackCount);
    for Track := 0 to A.TrackCount - 1 do
    begin
      { A track's first frame is always its own tile - the animation starts
        from the picture that is already there. Six of six. }
      if A.Tracks[Track].Frames[0] <> A.Tracks[Track].TileId then
      begin
        Log.Add(Format('FAILED: terrain %d track %d animates tile %d but'
          + ' starts on %d', [Terr, Track, A.Tracks[Track].TileId,
                              A.Tracks[Track].Frames[0]]));
        Inc(Bad);
      end;

      for Frame := 0 to A.Tracks[Track].FrameCount - 1 do
      begin
        Inc(Frames);
        if N > High(LITERALS) then
        begin
          Log.Add('FAILED: more frames in the table than the function declares');
          Inc(Bad);
          Break;
        end;
        Id   := A.Tracks[Track].Frames[Frame];
        GotX := TileSrcX(Id, TILE_PX, SHEET_COLS);
        GotY := TileSrcY(Id, TILE_PX, SHEET_COLS);
        { LITERALS[N][0] is the FIRST pushed value, which is srcY. }
        if (GotY <> LITERALS[N][0]) or (GotX <> LITERALS[N][1]) then
        begin
          Log.Add(Format('FAILED: terrain %d track %d frame %d is tile %d ->'
            + ' (x %d, y %d), but 0x004645B0 pushes (y %d, x %d)',
            [Terr, Track, Frame, Id, GotX, GotY,
             LITERALS[N][0], LITERALS[N][1]]));
          Inc(Bad);
        end;
        Inc(N);
      end;
    end;
  end;

  Log.Add(Format('tracks: %d   frames: %d   coordinate pairs compared: %d',
    [Tracks, Frames, N]));

  { Pinned so that a table which quietly lost its contents could not pass by
    comparing nothing. Seven tracks over four terrains - 2, 1, 2, 2 - and
    thirty frames is what the function has. }
  if (Tracks <> 7) or (N <> 30) then
  begin
    Log.Add(Format('FAILED: expected 7 tracks and 30 frames, got %d and %d',
      [Tracks, N]));
    Inc(Bad);
  end;

  { The transposed reading may agree only for diagonal sheet coordinates,
    where div and mod necessarily produce the same value. }
  N := 0;
  Obvious := 0;
  for Terr := 1 to TERRAIN_MAX do
  begin
    A := TERRAIN_ANIM[Terr];
    for Track := 0 to A.TrackCount - 1 do
      for Frame := 0 to A.Tracks[Track].FrameCount - 1 do
      begin
        Id := A.Tracks[Track].Frames[Frame];
        { The transposed reading: srcY from mod, srcX from div. }
        if ((Id mod SHEET_COLS) * TILE_PX = LITERALS[N][0])
           and ((Id div SHEET_COLS) * TILE_PX = LITERALS[N][1]) then
        begin
          Inc(Obvious);
          if (Id div SHEET_COLS) <> (Id mod SHEET_COLS) then
          begin
            Log.Add(Format('FAILED: tile %d is off the diagonal yet both axis'
              + ' readings place it at (%d, %d)',
              [Id, LITERALS[N][0], LITERALS[N][1]]));
            Inc(Bad);
          end;
        end;
        Inc(N);
      end;
  end;
  Log.Add(Format('the row-major reading places all %d; the transposed one'
    + ' places %d, and only on the diagonal', [N, Obvious]));

  { --- the switch itself --------------------------------------------- }
  for Terr := 1 to TERRAIN_MAX do
  begin
    Thr := -1;
    Kill := -1;
    TerrainConfigure(Terr, Thr, Kill, A);
    if (Thr <> BIN_THRESHOLD[Terr]) or (Kill <> BIN_KILL[Terr]) then
    begin
      Log.Add(Format('FAILED: terrain %d configured (%d, %d), but 0x004645B0'
        + ' writes (%d, %d)',
        [Terr, Thr, Kill, BIN_THRESHOLD[Terr], BIN_KILL[Terr]]));
      Inc(Bad);
    end;
    { The kill tile has to be a tile you can walk INTO or nothing could ever
      touch it - so it must be below the threshold - except for terrain 9,
      whose kill tile is deliberately outside the id space altogether. }
    if (Kill < TILESET_IDS) and (Kill >= Thr) then
    begin
      Log.Add(Format('FAILED: terrain %d''s kill tile %d is at or above its'
        + ' solid threshold %d, so it could never be entered',
        [Terr, Kill, Thr]));
      Inc(Bad);
    end;
    if (Terr >= 5) and (A.TrackCount <> 0) then
    begin
      Log.Add(Format('FAILED: terrain %d built %d animated tiles; only 1..4 do',
        [Terr, A.TrackCount]));
      Inc(Bad);
    end;
  end;

  { The default arm writes nothing at all. That is the behaviour, not an
    oversight: a terrain id outside 1..9 falls through the jump table and the
    two globals keep whatever the last stage put there. }
  Thr := 12345;
  Kill := 6789;
  TerrainConfigure(0, Thr, Kill, A);
  if (Thr <> 12345) or (Kill <> 6789) or (A.TrackCount <> 0) then
  begin
    Log.Add(Format('FAILED: terrain 0 changed the configuration to (%d, %d)'
      + ' with %d tracks; the default arm writes nothing',
      [Thr, Kill, A.TrackCount]));
    Inc(Bad);
  end;
  TerrainConfigure(TERRAIN_MAX + 1, Thr, Kill, A);
  if (Thr <> 12345) or (Kill <> 6789) then
  begin
    Log.Add('FAILED: a terrain id past the end wrote to the globals');
    Inc(Bad);
  end;
  if Obvious <> 1 then
  begin
    Log.Add(Format('FAILED: expected exactly one diagonal frame (tile 77),'
      + ' found %d', [Obvious]));
    Inc(Bad);
  end;

  Result := Bad;
end;

function SelfTestStages(Log: TStrings): Integer;
var
  GameDir: string;
  T: TStageTable;
  R: TStageRecord;
  M: TTileMap;
  I, C, N, MaxTile, With29, Safe29, Terr, Tile, TX, TY, Bad: Integer;
  Has29: Boolean;
  SurfEqSpr, MapEqRow, ThemeEqSurf, MapsPresent, Terrain3, Terrain4: Integer;
  LayerBad: Integer;
  DeadOK: Boolean;
  Anomalies: string;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');

  T := TStageTable.Create;
  try
    N := T.Load(GameDir);
    Log.Add(Format('rows loaded: %d', [N]));
    if N <> 66 then
    begin
      Log.Add('FAILED: expected 66 rows - wrong game directory?');
      Log.Add('');
      Log.Add('FAILED');
      Exit(1);
    end;

    SurfEqSpr := 0; MapEqRow := 0; ThemeEqSurf := 0; MapsPresent := 0;
    Terrain3 := 0; Terrain4 := 0; LayerBad := 0;
    DeadOK := True;
    Anomalies := '';

    for I := 0 to N - 1 do
    begin
      R := T[I];
      if R.Raw[0] = R.Raw[1] then Inc(SurfEqSpr);
      { rec[5] is the tileset surface slot for layer 0, and Load_Stage_Assets
        passes it to Terrain_Configure as well. Layers 1 and 2 are unused, so
        their map index AND their tileset are both -1 - the two triples have to
        agree or the reading of csv 5..7 as tilesets is wrong. }
      for C := 1 to STAGE_LAYERS - 1 do
        if (R.Raw[2 + C] = LAYER_NONE) <> (R.Raw[STAGE_TILESET + C] = LAYER_NONE) then
        begin
          Log.Add(Format('  row %d layer %d: map %d but tileset %d - they disagree',
            [I, C, R.Raw[2 + C], R.Raw[STAGE_TILESET + C]]));
          Inc(LayerBad);
        end;
      if (I > 0) and (R.Raw[STAGE_TILESET] <> 6) then
      begin
        Log.Add(Format('  row %d: layer 0 tileset is %d, expected surface slot 6',
          [I, R.Raw[STAGE_TILESET]]));
        Inc(LayerBad);
      end;

      if R.Raw[18] = 3 then Inc(Terrain3);
      if R.Raw[18] = 4 then Inc(Terrain4);
      if R.Raw[18] = R.Raw[0] then Inc(ThemeEqSurf)
      else
        Anomalies := Anomalies + Format(' row %d (art %d, theme %d)',
          [I, R.Raw[0], R.Raw[18]]);

      if I = 0 then
      begin
        { The placeholder row: no map, and csv5 is -1 rather than 6. }
        if (R.Raw[2] = LAYER_NONE) and (R.Raw[5] = LAYER_NONE) then
          Inc(MapEqRow);
      end
      else
      begin
        if R.Raw[2] = I then Inc(MapEqRow);
        if FileExists(IncludeTrailingPathDelimiter(GameDir) + 'map' + PathDelim +
                      Format('%.3d.map', [R.Raw[2]])) then
          Inc(MapsPresent);
      end;

      { csv 8..14 land in rec[11..17] and are zero throughout. }
      for C := 11 to 17 do
        if R.Raw[C] <> 0 then
          DeadOK := False;

      { csv 3,4,6,7 are -1 throughout. }
      if (R.Raw[3] <> LAYER_NONE) or (R.Raw[4] <> LAYER_NONE) or
         (R.Raw[6] <> LAYER_NONE) or (R.Raw[7] <> LAYER_NONE) then
        DeadOK := False;
    end;

    Log.Add(Format('csv0 = csv1 (art set is one field):     %d of %d', [SurfEqSpr, N]));
    Log.Add(Format('csv2 = row number (row 0 = no map):     %d of %d', [MapEqRow, N]));
    Log.Add(Format('map file present for rows 1..65:        %d of %d', [MapsPresent, N - 1]));
    Log.Add(Format('csv15 = csv0:                           %d of %d', [ThemeEqSurf, N]));
    { The two terrain values Entity_SpawnDebris actually branches on. If these
      counts move, the reading of csv 15 as a terrain id needs revisiting. }
    Log.Add(Format('terrain 3 (water01) / terrain 4 (water02): %d / %d stages',
      [Terrain3, Terrain4]));
    Log.Add(Format('csv 5..7 tilesets agree with csv 2..4 maps:  %d violations',
      [LayerBad]));
    Inc(Result, LayerBad);
    if Anomalies <> '' then
      Log.Add('  differing:' + Anomalies);
    Log.Add(Format('csv3/4/6/7 all -1 and csv8..14 all 0:   %s',
      [BoolToStr(DeadOK, 'yes', 'NO')]));
    Log.Add('');

    if SurfEqSpr <> N then
    begin
      Log.Add('FAILED: surface set and sprite set are not always equal');
      Inc(Result);
    end;
    if MapEqRow <> N then
    begin
      Log.Add('FAILED: csv2 is not the row number');
      Inc(Result);
    end;
    if MapsPresent <> N - 1 then
    begin
      Log.Add(Format('FAILED: %d of %d map files missing',
        [N - 1 - MapsPresent, N - 1]));
      Inc(Result);
    end;
    { 65 of 66, the exception being row 58. Pinned exactly: if this ever became
      66 the field would be redundant, and if it dropped further the reading of
      it as a near-shadow of the art set would be wrong. }
    if (Terrain3 <> 10) or (Terrain4 <> 13) then
    begin
      Log.Add(Format('FAILED: expected 10 stages of terrain 3 and 13 of terrain 4,'
        + ' got %d and %d', [Terrain3, Terrain4]));
      Inc(Result);
    end;
    if ThemeEqSurf <> 65 then
    begin
      Log.Add(Format('FAILED: expected csv15 to equal csv0 on exactly 65 rows, got %d',
        [ThemeEqSurf]));
      Inc(Result);
    end;
    if not DeadOK then
    begin
      Log.Add('FAILED: a column documented as constant is not');
      Inc(Result);
    end;

  { --- The terrain tables, against every shipped map ------------------------

    Terrain_Configure sets two globals per terrain: the solid-tile threshold
    and the kill tile. Three things follow, and all three are properties of the
    DATA, so they can fail:

      * every tile id in every map is inside the tileset, 0..99 - which is what
        makes the terrain-9 kill tile of 1000 mean "no instant death" rather
        than "tile 1000"
      * 29 is below every threshold, so the kill tile is always walk-into. It
        has to be, or nothing could reach it
      * tile 29 appears in exactly 7 maps, and the one where it is NOT lethal
        is the one terrain-9 stage }
  Bad := 0; MaxTile := -1; With29 := 0; Safe29 := 0;
  M := TTileMap.Create;
  try
    for I := 1 to 65 do
    begin
      if not M.Load(GameDir, I) then
        Continue;
      Has29 := False;
      for TY := 0 to M.MapHeight - 1 do
        for TX := 0 to M.MapWidth - 1 do
        begin
          Tile := M[TX, TY];
          if Tile > MaxTile then MaxTile := Tile;
          if Tile >= M.SheetCols * M.SheetRows then
          begin
            Inc(Bad);
            if Bad <= 3 then
              Log.Add(Format('  map %.3d: tile %d at %d,%d is outside the %dx%d sheet',
                [I, Tile, TX, TY, M.SheetCols, M.SheetRows]));
          end;
          if Tile = KILL_TILE then Has29 := True;
        end;
      if Has29 then
      begin
        Inc(With29);
        Terr := T[I].Raw[18];
        if (Terr >= 0) and (Terr <= TERRAIN_MAX) and
           (TERRAIN_KILL_TILE[Terr] <> KILL_TILE) then
          Inc(Safe29);
      end;
    end;
  finally
    M.Free;
  end;

  Log.Add('');
  Log.Add(Format('largest tile id in any map: %d  (tilesets are %d tiles)',
    [MaxTile, TILESET_IDS]));
  Log.Add(Format('tiles outside their own tileset:        %d', [Bad]));
  Log.Add(Format('maps containing the kill tile %d:       %d, of which %d are'
    + ' in a terrain where it is harmless', [KILL_TILE, With29, Safe29]));
  Inc(Result, Bad);

  if MaxTile >= KILL_TILE_NONE then
  begin
    Log.Add(Format('FAILED: a tile id of %d exists, so terrain 9''s kill tile'
      + ' of %d is not out of range after all', [MaxTile, KILL_TILE_NONE]));
    Inc(Result);
  end;
  for I := 1 to TERRAIN_MAX do
    if KILL_TILE >= TERRAIN_SOLID_THRESHOLD[I] then
    begin
      Log.Add(Format('FAILED: terrain %d makes tile %d solid, so nothing could'
        + ' ever walk into it', [I, KILL_TILE]));
      Inc(Result);
    end;
  if (With29 <> 7) or (Safe29 <> 1) then
  begin
    Log.Add(Format('FAILED: expected the kill tile in 7 maps with exactly 1'
      + ' harmless, got %d and %d', [With29, Safe29]));
    Inc(Result);
  end;

  finally
    T.Free;
  end;

  Inc(Result, TestTerrainAnim(Log));

  if Result = 0 then
    Log.Add('OK - every documented relationship in Stages.pas still holds')
  else
    Log.Add('FAILED - Stages.pas describes the data wrongly');
end;

end.
