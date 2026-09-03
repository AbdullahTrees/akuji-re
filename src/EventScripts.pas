{ EventScripts - the per-stage event table and its dialogue, from
  Load_Event_Scripts @ 0x00465B50, the only reader of either file:

      data\ev%.03d.dat   the event table, CSV
      data\tk%.03d.dat   the dialogue, one line per string

  THE FIELD ORDER IN THE FILE IS NOT THE ORDER IN THE RECORD. The loader
  scatters 7 CSV fields into a 0x24-byte record:

      csv 0 -> +0x00 opcode          csv 3 -> +0x10 tile X
      csv 1 -> +0x1C required flag   csv 4 -> +0x14 tile Y
      csv 2 -> +0x20 forbidding flag csv 5 -> +0x0C ParamA
                                     csv 6 -> +0x18 ParamB

  +0x04, +0x05 and +0x08 are never written from the file. They are the
  bookkeeping Events_SpawnNearCamera keeps: in-window, entity-exists, and the
  slot it occupies.

  THE CONDITION FIELDS gate the spawn, and the forbidding one is destructive:

      required   csv1 = 0 or Progress[csv1] <> 0
      forbidding csv2 = 0 or Progress[csv2] <> 1
                 otherwise the event is retired PERMANENTLY - opcode := -1,
                 tile := (-32,-32) - and its entity destroyed

  Opcodes: 0 touch, 1 touch plus a button and only while EF_VEL_Y is 0,
  4 always active (the window test is bypassed and Event_Begin runs every
  frame), 5 sets Progress[first four characters of ParamB], 7 calls
  Event_Begin, 9 collectible. 2 and 3 exist only in the code - the
  solid-collide pair start them when the player pushes into a solid - and
  appear in no shipped stage.

  Census and derivation: notes/event_table.md }

unit EventScripts;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

const
  EVENT_RECORD_BYTES = $24;   { the original's stride }
  EVENT_CSV_FIELDS   = 7;

  { The only two opcodes whose behaviour has been read out of the binary. }
  EVOP_TOUCH        = 0;   { starts on overlap }
  EVOP_TOUCH_BUTTON = 1;   { starts on overlap while standing, with a button }
  EVOP_SET_PROGRESS = 5;
  EVOP_ON_HIT       = 6;   { starts when a projectile hits the entity }
  EVOP_CALL_454EF4  = 7;   { starts unconditionally from Entity_Destroy }
  EVOP_ALWAYS       = 4;   { spawned and run every frame, ignoring the camera }
  EVOP_PUSH_AXIS    = 2;   { unused: push into the solid holding a direction }
  EVOP_PUSH_CONFIRM = 3;   { unused: push into the solid and press confirm }

  { What Events_SpawnNearCamera writes into a disabled event. }
  EVOP_DISABLED     = -1;
  EVENT_DISABLED_TILE = -32;

  { The spawn window, in tiles around the camera's top-left tile. The screen
    is 10 x 7.5 tiles and the margin is 2 on every side; the vertical bound is
    a float in the original for the same reason it is in Camera.pas. }
  SPAWN_MARGIN_TILES = 2;

type
  TEventRecord = record
    Opcode:  Integer;   { csv 0 -> +0x00 }
    InWindow: Boolean;  { +0x04, runtime only; set while inside the camera
                          window, cleared again once it leaves WITHOUT an
                          entity out. Those two bytes are separate on purpose:
                          the mark stops a second spawn, the entity byte stops
                          the mark being cleared underneath one. }
    Active:  Boolean;   { +0x05, runtime only; "an entity for this exists".
                          Entity_Destroy clears it }
    EntitySlot: Integer;{ +0x08, which slot that entity is in }
    ParamA:  string;    { csv 5 -> +0x0C }
    TileX:   Integer;   { csv 3 -> +0x10 }
    TileY:   Integer;   { csv 4 -> +0x14 }
    ParamB:  string;    { csv 6 -> +0x18 }
    NeedsFlag: Integer; { csv 1 -> +0x1C, spawn only if this flag is set }
    BlockedBy: Integer; { csv 2 -> +0x20, dead for good once this flag is set }
  end;

  TEventScript = class
  private
    FEvents: array of TEventRecord;
    FLines: TStringList;
    function GetCount: Integer;
    function GetEvent(Index: Integer): TEventRecord;
    function GetLineCount: Integer;
    function GetLine(Index: Integer): string;
  public
    constructor Create;
    destructor Destroy; override;

    { Loads both files for one stage. Returns the number of events; a missing
      ev file yields zero and leaves the dialogue empty, which is what the
      original effectively does too. }
    function Load(const ADataDir: string; StageIndex: Integer): Integer;

    procedure SetActive(Index: Integer; Value: Boolean);
    { EntityUpdate_Type15_Switch's throw. Distinct from Disable, which also
      moves the record off the map: a thrown switch keeps its tile and entity. }
    procedure SetOpcode(Index, Value: Integer);
    procedure SetInWindow(Index: Integer; Value: Boolean);
    procedure SetEntity(Index, Slot: Integer);

    { Kill an event for GOOD. Both Events_SpawnNearCamera and the
      interpreter's sub-op 7 do exactly this: opcode to -1 and the tile moved
      to (-32, -32), which is off every shipped map. Nothing ever undoes it -
      the record is dead until the stage reloads. }
    procedure Disable(Index: Integer);

    property Count: Integer read GetCount;
    property Events[Index: Integer]: TEventRecord read GetEvent; default;

    { data\tk*.dat, one entry per line. }
    property LineCount: Integer read GetLineCount;
    property Lines[Index: Integer]: string read GetLine;
  end;

{ The progress-flag index an opcode-5 event sets, from Entity_Destroy:

      Copy(ParamB, 1, 4) -> StrToInt -> PlayerState.Progress[result] := 1

  Returns -1 when ParamB does not begin with four digits. The original does not
  check, and would raise an EConvertError - refusing here is deliberate, since
  a bad index would otherwise write into an arbitrary spot of the save. }
function ProgressIndexOf(const ParamB: string): Integer;

implementation

constructor TEventScript.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
end;

destructor TEventScript.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

function TEventScript.GetCount: Integer;
begin
  Result := Length(FEvents);
end;

function TEventScript.GetEvent(Index: Integer): TEventRecord;
begin
  if (Index < 0) or (Index >= Length(FEvents)) then
  begin
    Result.Opcode := -1;
    Result.Active := False;
    Result.ParamA := '';
    Result.TileX := 0;
    Result.TileY := 0;
    Result.ParamB := '';
    Result.NeedsFlag := 0;
    Result.BlockedBy := 0;
    Exit;
  end;
  Result := FEvents[Index];
end;

procedure TEventScript.SetInWindow(Index: Integer; Value: Boolean);
begin
  if (Index >= 0) and (Index < Length(FEvents)) then
    FEvents[Index].InWindow := Value;
end;

procedure TEventScript.SetEntity(Index, Slot: Integer);
begin
  if (Index >= 0) and (Index < Length(FEvents)) then
  begin
    FEvents[Index].EntitySlot := Slot;
    FEvents[Index].Active := True;
  end;
end;

procedure TEventScript.Disable(Index: Integer);
begin
  if (Index < 0) or (Index >= Length(FEvents)) then
    Exit;
  FEvents[Index].Opcode := EVOP_DISABLED;
  FEvents[Index].TileX := EVENT_DISABLED_TILE;
  FEvents[Index].TileY := EVENT_DISABLED_TILE;
end;

procedure TEventScript.SetOpcode(Index, Value: Integer);
begin
  if (Index >= 0) and (Index < Length(FEvents)) then
    FEvents[Index].Opcode := Value;
end;

procedure TEventScript.SetActive(Index: Integer; Value: Boolean);
begin
  if (Index >= 0) and (Index < Length(FEvents)) then
    FEvents[Index].Active := Value;
end;

function TEventScript.GetLineCount: Integer;
begin
  Result := FLines.Count;
end;

function TEventScript.GetLine(Index: Integer): string;
begin
  if (Index < 0) or (Index >= FLines.Count) then
    Exit('');
  Result := FLines[Index];
end;

{ Load_Event_Scripts @ 0x00465B50. It loads BOTH files - the event table
  and the dialogue - which is why one routine covers both. }
function TEventScript.Load(const ADataDir: string; StageIndex: Integer): Integer;
var
  SourceLines, Fields: TStringList;
  DataPath, FileName: string;
  LineIndex, EventCount: Integer;
begin
  SetLength(FEvents, 0);
  FLines.Clear;
  DataPath := IncludeTrailingPathDelimiter(ADataDir) + 'data' + PathDelim;

  SourceLines := TStringList.Create;
  Fields := TStringList.Create;
  try
    FileName := DataPath + Format('ev%.3d.dat', [StageIndex]);
    if FileExists(FileName) then
    begin
      SourceLines.LoadFromFile(FileName);
      EventCount := 0;
      SetLength(FEvents, SourceLines.Count);
      for LineIndex := 0 to SourceLines.Count - 1 do
      begin
        if Trim(SourceLines[LineIndex]) = '' then
          Continue;
        { The original sets .CommaText, exactly as the other CSV loaders do. }
        Fields.CommaText := SourceLines[LineIndex];
        if Fields.Count < EVENT_CSV_FIELDS then
          Continue;

        FEvents[EventCount].Opcode  := StrToIntDef(Trim(Fields[0]), 0);
        FEvents[EventCount].NeedsFlag := StrToIntDef(Trim(Fields[1]), 0);
        FEvents[EventCount].BlockedBy := StrToIntDef(Trim(Fields[2]), 0);
        FEvents[EventCount].TileX := StrToIntDef(Trim(Fields[3]), 0);
        FEvents[EventCount].TileY := StrToIntDef(Trim(Fields[4]), 0);
        FEvents[EventCount].ParamA  := Fields[5];
        FEvents[EventCount].ParamB  := Fields[6];
        FEvents[EventCount].Active  := False;
        Inc(EventCount);
      end;
      SetLength(FEvents, EventCount);
    end;

    { The dialogue file is read straight into a string list - the original
      copies one string per line with no parsing at all. Its escape codes
      (\n, \e, \k, \w) are the consumer's problem, not the loader's. }
    FileName := DataPath + Format('tk%.3d.dat', [StageIndex]);
    if FileExists(FileName) then
      FLines.LoadFromFile(FileName);
  finally
    Fields.Free;
    SourceLines.Free;
  end;

  Result := Length(FEvents);
end;

function ProgressIndexOf(const ParamB: string): Integer;
var
  Prefix: string;
  CharacterIndex: Integer;
begin
  Result := -1;
  if Length(ParamB) < 4 then
    Exit;
  Prefix := Copy(ParamB, 1, 4);
  for CharacterIndex := 1 to 4 do
    if not (Prefix[CharacterIndex] in ['0'..'9']) then
      Exit;
  Result := StrToIntDef(Prefix, -1);
end;

end.
