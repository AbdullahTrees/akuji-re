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
       3     [3]    -1 on every row
       4     [4]    -1 on every row
       5     [5]    6 on every row but row 0, which is -1
       6     [6]    -1 on every row
       7     [7]    -1 on every row
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

  Only rec[2] has its meaning from the code (Load_Stage_Assets builds the map
  filename from it). rec[0] and rec[1] are from the code too. Everything else
  above is a property of the data. }

unit Stages;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

const
  STAGE_FIELDS  = 16;   { columns in stage.dat }
  STAGE_RECORD  = 19;   { ints per record, stride 0x4C }
  STAGE_LAYERS  = 3;    { rec[2..4] }
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
  public
    function Load(const ADataDir: string): Integer;

    property Count: Integer read GetCount;
    property Records[Index: Integer]: TStageRecord read GetRecord; default;

    { The three fields whose meaning is established from the code. }
    property SurfaceSet[Index: Integer]: Integer read GetSurfaceSet;
    property SpriteSet[Index: Integer]: Integer read GetSpriteSet;
    property Layer[StageIndex, LayerIndex: Integer]: Integer read GetLayer;

    { csv 15 / rec[18]: the terrain id Entity_SpawnDebris reads to choose the
      impact sound. Equals SurfaceSet everywhere except stage 58. }
    property TerrainId[Index: Integer]: Integer read GetTerrainId;
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

function TStageTable.GetTerrainId(Index: Integer): Integer;
begin
  Result := GetRecord(Index).Raw[18];
end;

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
