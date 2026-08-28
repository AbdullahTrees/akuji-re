{ Stages - the stage table, translated from Load_StageTable @ 0x004669F8
  and read back by Load_Stage_Assets @ 0x00465A1C.

  data\stage.dat is CSV, 66 lines of 16 integer fields (one per map, plus
  index 0). Each line fills a 19-int record - stride 0x4C, matching the
  multiplier Load_Stage_Assets uses.

  The field-to-slot mapping is NOT one-to-one. Load_StageTable writes:

      csv[0..7]  -> rec[0..7]
      csv[8..15] -> rec[11..18]

  so rec[8], rec[9] and rec[10] are never written from the file - they are
  runtime scratch. That gap is why 16 columns fill a 19-int record, and it must
  be preserved: Load_Stage_Assets indexes the record, not the CSV.

  Confirmed meanings, from how Load_Stage_Assets uses the record:

      rec[0]     surface set   -> data\surf%.03d.dat
      rec[1]     sprite set    -> data\spr%.03d.dat
      rec[2..4]  map layers    -> map\%.03d.map, -1 meaning "no layer"

  ## What the 16 columns actually carry

  Surveying all 66 rows collapses most of the "unknown columns" question. What
  follows describes the SHIPPED DATA, not the loader: a column that is constant
  here is not proven unused by the code, only unexercised by this game's stages.
  Load_Stage_Assets still copies all 16.

      csv    rec    contents over all 66 rows
      ---    ---    ------------------------------------------------------
       0     [0]    surface set, 0..9 - matches surf000..009.dat
       1     [1]    sprite set, 0..9  - matches spr000..009.dat
       2     [2]    map index. EQUALS THE ROW NUMBER on rows 1..65, and
                    map.map..065.map is exactly that set. Row 0 is -1
       3     [3]    map index for layer 1 - -1 on every row, so unused
       4     [4]    map index for layer 2 - -1 on every row, so unused
       5     [5]    TILESET surface slot for layer 0. 6 on every row but row 0
       6     [6]    tileset slot for layer 1 - -1, unused
       7     [7]    tileset slot for layer 2 - -1, unused
       8..14 [11..17]  0 on every row - seven dead columns
      15     [18]   TERRAIN id - picks the debris impact sound; equals
                    csv 0 on 65 of 66 rows

  Three findings worth keeping:

  **csv 0 and csv 1 are equal on every row.** Surface set and sprite set are
  never chosen independently, so a stage has one art set, not two.

  **csv 2 is redundant with the row number.** Rows 1..65 have rec[2] = index,
  and there are exactly 65 map files. Row 0 carries -1 and no map: it is the
  placeholder for "no stage", which is why STAGE_FIELDS covers 66 rows for 65
  levels. This is the same kind of flush fit that validated the sound table.

  **csv 15 selects the TERRAIN IMPACT SOUND.** Entity_SpawnDebris @ 0x00461874
  reads it as rec[18] off this table, indexed by the current stage, and picks
  which sound the debris burst plays:

      rec[18] = 3  ->  sound 31, water01.wav
      rec[18] = 4  ->  sound 40, water02.wav
      anything else -> silent for that debris kind

  Ten stages carry 3 and thirteen carry 4, and both groups use the matching art
  set. So it is a terrain or area id that happens to track the art set, not a
  copy of it.

  That also explains the one row where the two differ - row 58, art set 7 but
  terrain 6. It looks like area 7 and sounds like area 6. Value 7 appears in
  csv 0 only on that row and never in csv 15 at all.

  It is NOT the music, which was the obvious first guess. The form resource's
  AutoLoadMidis settles that: index 4 there is 'itemget', a short jingle, yet 13
  rows carry csv 15 = 4, and indices 10..14 are never used. Recorded so the
  guess is not made again.

  ## csv 5..7 are the tilesets, paralleling csv 2..4

  Load_Stage_Assets @ 0x00465A1C loops the three layers and calls

      Load_Map(form, rec[2 + layer], layer, rec[5 + layer])

  and Load_Map uses that fourth argument as p_Surfaces[it] - the layer's
  TILESET. So the two triples are parallel: rec[2..4] say WHICH map each layer
  loads and rec[5..7] say which surface holds its tiles. Only layer 0 is ever
  used, which is why the other four are -1 throughout.

  rec[5] is 6 on every real row, and surface slot 6 is bg001.bmp, bg003.bmp,
  bg004.bmp ... in each art set - the background sheet. Row 0 carries -1 and
  its art set has nothing in slot 6, which is consistent.

  ## Where the terrain id goes

  The same function ends with

      Terrain_Configure(TileMaps[0], Surfaces[rec[5]], rec[18])

  so rec[18] - csv 15 - is passed straight in as the terrain id, confirming
  that reading from a second direction. Terrain_Configure @ 0x004645B0 switches
  on it 1..9 and sets the SOLID TILE THRESHOLD, the value Entity_TileCollideX/Y
  compare each tile index against:

      terrain 1, 2, 4     threshold $32
      terrain 3, 6, 7, 8  threshold $3C
      terrain 5           threshold $46
      terrain 9           threshold $50

  Terrain 0 has no case and leaves the threshold alone; only row 0, the
  placeholder, carries it. So the terrain id does not merely pick a sound - it
  decides which tiles are solid.

  It also picks the KILL TILE. Terrain_Configure writes a second global right
  beside the threshold, and Entity_CheckKillTiles @ 0x004576B4 - which every
  vertical movement step calls - scans the whole of an entity's tile box for
  it. One match sets EF_STATE to 10, the fall-death state.

      terrain 1..8   kill tile 29
      terrain 9      kill tile 1000

  Every tileset in the game is 10 x 10, and the largest tile id in any of the
  65 maps is 99, so 1000 can never match: terrain 9 has no instant death. That
  is not an inference about intent - 1000 is simply outside the id space, and
  --selftest-stages checks that it still is.

  Two more things hold across the shipped data and are checked there:

    * 29 is below every threshold (the smallest is $32 = 50), so the kill tile
      is always a tile you can walk INTO. It has to be, or nothing could ever
      touch it.
    * tile 29 appears in only 7 of the 65 maps, and the single map where it
      appears without being lethal is the single terrain-9 stage.

  Terrains 1..4 additionally build an animated background entity; 5..9 do not.

  With that, every column of stage.dat is accounted for. rec[0], rec[1],
  rec[2..4], rec[5..7] and rec[18] all have their meaning from the code;
  rec[11..17] are zero throughout and nothing reads them. }

unit Stages;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

const
  STAGE_FIELDS  = 16;   { columns in stage.dat }
  STAGE_RECORD  = 19;   { ints per record, stride 0x4C }
  STAGE_LAYERS  = 3;    { rec[2..4] maps, rec[5..7] their tilesets }
  STAGE_TILESET = 5;    { rec[5 + layer] }

  { From Terrain_Configure @ 0x004645B0. Index is the terrain id 1..9; entry 0
    is the placeholder row, which the original leaves alone. }
  TERRAIN_MAX = 9;
  TERRAIN_SOLID_THRESHOLD: array[0..TERRAIN_MAX] of Integer =
    (0, $32, $32, $3C, $32, $46, $3C, $3C, $3C, $50);
  TERRAIN_KILL_TILE: array[0..TERRAIN_MAX] of Integer =
    (0, 29, 29, 29, 29, 29, 29, 29, 29, 1000);

  { 10 x 10 tilesets throughout, so a valid id is 0..99. }
  TILESET_IDS  = 100;
  KILL_TILE    = 29;
  KILL_TILE_NONE = 1000;   { outside the id space - terrain 9 }
  LAYER_NONE    = -1;

type
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

implementation

function TStageTable.GetCount: Integer;
begin
  Result := Length(FRecords);
end;

function TStageTable.GetRecord(Index: Integer): TStageRecord;
var
  I: Integer;
begin
  if (Index < 0) or (Index >= Length(FRecords)) then
  begin
    for I := 0 to STAGE_RECORD - 1 do
      Result.Raw[I] := 0;
    Exit;
  end;
  Result := FRecords[Index];
end;

function TStageTable.GetSurfaceSet(Index: Integer): Integer;
begin
  Result := GetRecord(Index).Raw[0];
end;

function TStageTable.GetSpriteSet(Index: Integer): Integer;
begin
  Result := GetRecord(Index).Raw[1];
end;

function TStageTable.GetLayer(StageIndex, Layer: Integer): Integer;
begin
  if (Layer < 0) or (Layer >= STAGE_LAYERS) then
    Exit(LAYER_NONE);
  Result := GetRecord(StageIndex).Raw[2 + Layer];
end;

function TStageTable.GetTileset(StageIndex, Layer: Integer): Integer;
begin
  if (Layer < 0) or (Layer >= STAGE_LAYERS) then
    Exit(LAYER_NONE);
  Result := GetRecord(StageIndex).Raw[STAGE_TILESET + Layer];
end;

function TStageTable.GetTerrainId(Index: Integer): Integer;
begin
  Result := GetRecord(Index).Raw[18];
end;

{ Load_StageTable @ 0x004669F8. }
function TStageTable.Load(const ADataDir: string): Integer;
var
  Lines, Fields: TStringList;
  FileName: string;
  L, F, Slot: Integer;
  Rec: TStageRecord;
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
    for L := 0 to Lines.Count - 1 do
    begin
      if Trim(Lines[L]) = '' then
        Continue;
      Fields.CommaText := Lines[L];
      if Fields.Count < STAGE_FIELDS then
        Continue;

      FillChar(Rec, SizeOf(Rec), 0);
      for F := 0 to STAGE_FIELDS - 1 do
      begin
        { The original's gap: columns 8..15 land at 11..18, leaving 8..10 as
          runtime scratch. }
        if F <= 7 then
          Slot := F
        else
          Slot := F + 3;
        Rec.Raw[Slot] := StrToIntDef(Trim(Fields[F]), 0);
      end;

      SetLength(FRecords, Length(FRecords) + 1);
      FRecords[High(FRecords)] := Rec;
    end;
  finally
    Fields.Free;
    Lines.Free;
  end;
  Result := Length(FRecords);
end;

end.
