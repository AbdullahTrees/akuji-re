{ Stages - data\stage.dat, loaded by Load_StageTable @ 0x004669F8 and read
  back by Load_Stage_Assets @ 0x00465A1C.

  66 CSV lines of 16 integers each fill a 19-int record, stride 0x4C. THE
  MAPPING IS NOT ONE-TO-ONE and must be preserved, because Load_Stage_Assets
  indexes the RECORD:

      csv[0..7]  -> rec[0..7]        csv[8..15] -> rec[11..18]

  rec[8..10] are never written from the file; they are runtime scratch.

      rec[0]     surface set   -> data\surf%.03d.dat
      rec[1]     sprite set    -> data\spr%.03d.dat
      rec[2..4]  map layers    -> map\%.03d.map, -1 for none
      rec[5..7]  TILESET slot within the loaded surface set, per layer
      rec[18]    terrain id    -> thresholds and kill tile, below

  In the shipped data rec[3..4], rec[6..7] are -1 and rec[11..17] are 0 on
  every row - unexercised by this game, not proven unused by the code, which
  copies all 16 regardless.

  Terrains 1..4 also build an animated-tile set; 5..9 do not. TERRAIN_ANIM
  stores only the tile ids, and --selftest-stages recomputes each frame's
  source rect and compares it against the sixty literals in Terrain_Configure
  @ 0x004645B0.

  Column census, track contents and derivation: notes/stage_table.md }

unit Stages;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

const
  STAGE_FIELDS  = 16;   { columns in stage.dat }
  STAGE_RECORD  = 19;   { ints per record, stride 0x4C }
  STAGE_LAYERS  = 3;    { rec[2..4] maps, rec[5..7] their tilesets }
  STAGE_SURFACE_SET = 0;
  STAGE_SPRITE_SET  = 1;
  STAGE_MAP         = 2;    { rec[2 + layer] }
  STAGE_TILESET = 5;    { rec[5 + layer] }
  STAGE_TERRAIN = 18;
  STAGE_FILE_GAP_START = 8;
  STAGE_FILE_GAP_SIZE  = 3;

  { From Terrain_Configure @ 0x004645B0. Index is the terrain id 1..9; entry 0
    is the placeholder row, which the original leaves alone. }
  TERRAIN_MAX = 9;
  TERRAIN_SOLID_THRESHOLD: array[0..TERRAIN_MAX] of Integer =
    (0, $32, $32, $3C, $32, $46, $3C, $3C, $3C, $50);
  TERRAIN_KILL_TILE: array[0..TERRAIN_MAX] of Integer =
    (0, 29, 29, 29, 29, 29, 29, 29, 29, 1000);

  { The two globals Terrain_Configure writes, adjacent in BSS - which is what
    "right beside the threshold" above means literally. }
  ADDR_SOLID_THRESHOLD = $00484EF4;
  ADDR_KILL_TILE       = $00484EF8;

  { Every frame of every track holds for the same number of ticks. }
  TERRAIN_ANIM_TICKS  = 8;
  TERRAIN_ANIM_TRACKS = 2;    { the most any terrain declares }
  TERRAIN_ANIM_FRAMES = 5;    { the most any track declares }

  { 10 x 10 tilesets throughout, so a valid id is 0..99. }
  TILESET_IDS  = 100;
  KILL_TILE    = 29;
  KILL_TILE_NONE = 1000;   { outside the id space - terrain 9 }
  LAYER_NONE    = -1;

type
  { One animated tile: the id whose picture is replaced, and the ids its
    picture is taken from in turn. }
  TTileAnimation = record
    TileId:     Integer;
    FrameCount: Integer;
    Frames:     array[0..TERRAIN_ANIM_FRAMES - 1] of Integer;
  end;

  TTerrainAnim = record
    TrackCount: Integer;
    Tracks:     array[0..TERRAIN_ANIM_TRACKS - 1] of TTileAnimation;
  end;

  TStageRecord = record
    Raw: array[0..STAGE_RECORD - 1] of Integer;
  end;

  TStageTable = class
  private
    FRecords: array of TStageRecord;
    function GetCount: Integer;
    function GetRecord(Index: Integer): TStageRecord;
    function GetSurfaceSet(Index: Integer): Integer;
    function GetSpriteSet(Index: Integer): Integer;
    function GetLayer(StageIndex, Layer: Integer): Integer;
    function GetTerrainId(Index: Integer): Integer;
    function GetTileset(StageIndex, Layer: Integer): Integer;
  public
    function Load(const ADataDir: string): Integer;

    property Count: Integer read GetCount;
    property Records[Index: Integer]: TStageRecord read GetRecord; default;

    { The three fields whose meaning is established from the code. }
    property SurfaceSet[Index: Integer]: Integer read GetSurfaceSet;
    property SpriteSet[Index: Integer]: Integer read GetSpriteSet;
    property Layer[StageIndex, LayerIndex: Integer]: Integer read GetLayer;

    { csv 15 / rec[18]: the terrain id. Load_Stage_Assets hands it to
      Terrain_Configure, which uses it to set the solid-tile threshold, and
      Entity_SpawnDebris reads it to choose the impact sound. Equals
      SurfaceSet everywhere except stage 58. }
    property TerrainId[Index: Integer]: Integer read GetTerrainId;

    { rec[5 + layer] - the surface slot holding that layer's tiles. }
    property Tileset[StageIndex, Layer: Integer]: Integer read GetTileset;
  end;

const
  { Verbatim from the nine arms of Terrain_Configure @ 0x004645B0, as tile ids.
    Index 0 is the placeholder row and terrains 5..9 declare nothing. }
  TERRAIN_ANIM: array[0..TERRAIN_MAX] of TTerrainAnim = (
    { 0 } (TrackCount: 0; Tracks: ((TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0)),
                                   (TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0)))),
    { 1 } (TrackCount: 2; Tracks: ((TileId:  7; FrameCount: 4; Frames: ( 7, 8, 9, 8,0)),
                                   (TileId: 17; FrameCount: 4; Frames: (17,18,19,18,0)))),
    { 2 } (TrackCount: 1; Tracks: ((TileId: 75; FrameCount: 5; Frames: (75,76,77,78,79)),
                                   (TileId:  0; FrameCount: 0; Frames: (0,0,0,0,0)))),
    { 3 } (TrackCount: 2; Tracks: ((TileId: 17; FrameCount: 4; Frames: (17,18,19,18,0)),
                                   (TileId:  7; FrameCount: 4; Frames: ( 7, 8, 9, 8,0)))),
    { 4 } (TrackCount: 2; Tracks: ((TileId: 15; FrameCount: 5; Frames: (15,16,17,18,19)),
                                   (TileId: 63; FrameCount: 4; Frames: (63,64,65,64,0)))),
    { 5 } (TrackCount: 0; Tracks: ((TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0)),
                                   (TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0)))),
    { 6 } (TrackCount: 0; Tracks: ((TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0)),
                                   (TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0)))),
    { 7 } (TrackCount: 0; Tracks: ((TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0)),
                                   (TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0)))),
    { 8 } (TrackCount: 0; Tracks: ((TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0)),
                                   (TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0)))),
    { 9 } (TrackCount: 0; Tracks: ((TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0)),
                                   (TileId: 0; FrameCount: 0; Frames: (0,0,0,0,0))))
  );

{ 0x004645B0. What Load_Stage_Assets calls once a stage's assets are in, with
  the terrain id from rec[18].

  It is a nine-arm switch and every arm does the same two things - write the
  solid threshold and the kill tile into two adjacent BSS globals - after which
  four of them also build the animated tiles. An id outside 1..9 falls through
  the jump table's default and writes NOTHING, leaving whatever the last stage
  set; that is reproduced rather than guarded, because a default is what the
  original has and the stage table never produces one.

  The globals become parameters here, and they are `var` rather than `out` on
  purpose: the default arm's whole behaviour is that they KEEP their previous
  values, and an `out` parameter is free to be cleared on entry. The original
  reaches them through pointer indirections because Delphi puts unit variables
  behind them; there is nothing to model in that. What the animator does with its tracks
  belongs to TMYBGANIME, which is component-layer and not reconstructed - so
  the tracks are handed back rather than built into an object that would only
  be a stub. }
procedure TerrainConfigure(TerrainId: Integer;
                           var SolidThreshold, KillTile: Integer;
                           out Anim: TTerrainAnim);


implementation

procedure TerrainConfigure(TerrainId: Integer;
                           var SolidThreshold, KillTile: Integer;
                           out Anim: TTerrainAnim);
begin
  { The switch's default arm. Both globals keep their previous values and no
    animator is built - which is also why every caller must pass the ones it
    already has rather than expecting them initialised. }
  if (TerrainId < 1) or (TerrainId > TERRAIN_MAX) then
  begin
    Anim := TERRAIN_ANIM[0];
    Exit;
  end;

  SolidThreshold := TERRAIN_SOLID_THRESHOLD[TerrainId];
  KillTile       := TERRAIN_KILL_TILE[TerrainId];
  Anim           := TERRAIN_ANIM[TerrainId];
end;

function TStageTable.GetCount: Integer;
begin
  Result := Length(FRecords);
end;

function TStageTable.GetRecord(Index: Integer): TStageRecord;
var
  FieldIndex: Integer;
begin
  if (Index < 0) or (Index >= Length(FRecords)) then
  begin
    for FieldIndex := 0 to STAGE_RECORD - 1 do
      Result.Raw[FieldIndex] := 0;
    Exit;
  end;
  Result := FRecords[Index];
end;

function TStageTable.GetSurfaceSet(Index: Integer): Integer;
begin
  Result := GetRecord(Index).Raw[STAGE_SURFACE_SET];
end;

function TStageTable.GetSpriteSet(Index: Integer): Integer;
begin
  Result := GetRecord(Index).Raw[STAGE_SPRITE_SET];
end;

function TStageTable.GetLayer(StageIndex, Layer: Integer): Integer;
begin
  if (Layer < 0) or (Layer >= STAGE_LAYERS) then
    Exit(LAYER_NONE);
  Result := GetRecord(StageIndex).Raw[STAGE_MAP + Layer];
end;

function TStageTable.GetTileset(StageIndex, Layer: Integer): Integer;
begin
  if (Layer < 0) or (Layer >= STAGE_LAYERS) then
    Exit(LAYER_NONE);
  Result := GetRecord(StageIndex).Raw[STAGE_TILESET + Layer];
end;

function TStageTable.GetTerrainId(Index: Integer): Integer;
begin
  Result := GetRecord(Index).Raw[STAGE_TERRAIN];
end;

{ Load_StageTable @ 0x004669F8. }
function TStageTable.Load(const ADataDir: string): Integer;
var
  Lines, Fields: TStringList;
  FileName: string;
  LineIndex, FieldIndex, RecordField: Integer;
  Stage: TStageRecord;
begin
  SetLength(FRecords, 0);
  FileName := IncludeTrailingPathDelimiter(ADataDir) + 'data' + PathDelim +
              'stage.dat';
  if not FileExists(FileName) then
    Exit(0);

  Lines := TStringList.Create;
  Fields := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    for LineIndex := 0 to Lines.Count - 1 do
    begin
      if Trim(Lines[LineIndex]) = '' then
        Continue;
      Fields.CommaText := Lines[LineIndex];
      if Fields.Count < STAGE_FIELDS then
        Continue;

      FillChar(Stage, SizeOf(Stage), 0);
      for FieldIndex := 0 to STAGE_FIELDS - 1 do
      begin
        { The original's gap: columns 8..15 land at 11..18, leaving 8..10 as
          runtime scratch. }
        if FieldIndex <= STAGE_FILE_GAP_START - 1 then
          RecordField := FieldIndex
        else
          RecordField := FieldIndex + STAGE_FILE_GAP_SIZE;
        Stage.Raw[RecordField] := StrToIntDef(Trim(Fields[FieldIndex]), 0);
      end;

      SetLength(FRecords, Length(FRecords) + 1);
      FRecords[High(FRecords)] := Stage;
    end;
  finally
    Fields.Free;
    Lines.Free;
  end;
  Result := Length(FRecords);
end;

end.
