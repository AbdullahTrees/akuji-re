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

  rec[2] matches the map file exactly - line 64 has rec[2] = 64, and 064.map
  exists. rec[5..7] and rec[11..18] are read but their meanings are not yet
  traced; rec[5] is 6 on every line but the first, which is -1. }

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
  public
    function Load(const ADataDir: string): Integer;

    property Count: Integer read GetCount;
    property Records[Index: Integer]: TStageRecord read GetRecord; default;

    { The three fields whose meaning is established. }
    property SurfaceSet[Index: Integer]: Integer read GetSurfaceSet;
    property SpriteSet[Index: Integer]: Integer read GetSpriteSet;
    property Layer[StageIndex, LayerIndex: Integer]: Integer read GetLayer;
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
