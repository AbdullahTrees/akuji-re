{ EventScripts - the per-stage event table and its dialogue.

  Translated from Load_Event_Scripts @ 0x00465B50, which despite the name loads
  TWO files per stage and is the only reader of either:

      data\ev%.03d.dat    the event table, CSV
      data\tk%.03d.dat    the dialogue, one line per string

  Both filename prefixes are literals in the binary at 0x00465E64 and
  0x00465E94. That settles an old mistake recorded in CLAUDE.md: tk*.dat was
  once guessed to be tile data, and it is not - it is the text these events
  refer to.

  ## The event record

  Each CSV line fills a 0x24-byte record. The field order in the file is NOT
  the field order in the record - the loader scatters them:

      csv 0 -> +0x00 int      opcode
      csv 1 -> +0x1C int
      csv 2 -> +0x20 int
      csv 3 -> +0x10 int
      csv 4 -> +0x14 int
      csv 5 -> +0x0C string
      csv 6 -> +0x18 string

  +0x04 and +0x08 are never written by the loader, and +0x05 is a runtime byte
  that Entity_Destroy clears - so the record is bigger than the file's content.

  Validated against the shipped data: all 692 lines across all 66 ev files have
  exactly seven fields, with no exceptions and nothing needing a fallback.

  ## Opcodes

  Seven distinct values appear in the shipped data:

      0 x18    1 x249    4 x9    5 x154    6 x5    7 x26    9 x231

  Two of them are decoded, both from Entity_Destroy @ 0x00461400:

      0   TRIGGERS ON TOUCH, unconditionally. Entity_PlayerTouch @ 0x00457880
          starts the event as soon as the player's hitbox overlaps the entity
          carrying it.
      1   TRIGGERS ON TOUCH PLUS A BUTTON. Same overlap test, but it also
          requires the player's EF_VEL_Y to be 0 - standing, not jumping - and
          an input condition. This is the "walk up to it and press a button"
          case, which is why it is by far the most common opcode: 249 of 692.
      5   sets a player progress flag. It takes the FIRST FOUR CHARACTERS of
          the +0x18 string, parses them as an integer, and writes 1 to
          PlayerState.Progress[that]. This is how the 0x1195-byte progress
          block is populated - see ProgressIndexOf below.
      7   calls Event_Begin(eventIndex, 4).

  Opcodes 0, 1 and 7 all reach the same place - Event_Begin @ 0x00454EF4 - so
  they are three ways of STARTING a script rather than three different actions.
  What the script then does is EventCommands.pas's business.

  That also explains the shape of the data: opcode 1 carries a program 249
  times, and sub-op 3 (dialogue) accounts for 149 of all sub-opcode uses. Signs
  and conversations are the bulk of the game's events.

      6   TRIGGERS ON BEING HIT. Entity_TakeProjectileHits @ 0x00457AB4 starts
          the event when a projectile connects with the entity carrying it.
          Only 5 events use it, which fits a boss-defeated or
          shoot-the-switch trigger rather than anything routine.

  So four of the seven opcodes are ways of starting a script, differing only in
  what triggers them: 0 on touch, 1 on touch plus a button, 6 on being shot,
  7 from Entity_Destroy.

  Opcodes 4 and 9 are still not decoded and are deliberately left unnamed. }

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

type
  TEventRecord = record
    Opcode:  Integer;   { csv 0 -> +0x00 }
    Active:  Boolean;   { +0x05, runtime only; Entity_Destroy clears it }
    ParamA:  string;    { csv 5 -> +0x0C }
    Field10: Integer;   { csv 3 -> +0x10 }
    Field14: Integer;   { csv 4 -> +0x14 }
    ParamB:  string;    { csv 6 -> +0x18 }
    Field1C: Integer;   { csv 1 -> +0x1C }
    Field20: Integer;   { csv 2 -> +0x20 }
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
    Result.Field10 := 0;
    Result.Field14 := 0;
    Result.ParamB := '';
    Result.Field1C := 0;
    Result.Field20 := 0;
    Exit;
  end;
  Result := FEvents[Index];
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

function TEventScript.Load(const ADataDir: string; StageIndex: Integer): Integer;
var
  Src, Fields: TStringList;
  Base, FileName: string;
  I, N: Integer;
begin
  SetLength(FEvents, 0);
  FLines.Clear;
  Base := IncludeTrailingPathDelimiter(ADataDir) + 'data' + PathDelim;

  Src := TStringList.Create;
  Fields := TStringList.Create;
  try
    FileName := Base + Format('ev%.3d.dat', [StageIndex]);
    if FileExists(FileName) then
    begin
      Src.LoadFromFile(FileName);
      N := 0;
      SetLength(FEvents, Src.Count);
      for I := 0 to Src.Count - 1 do
      begin
        if Trim(Src[I]) = '' then
          Continue;
        { The original sets .CommaText, exactly as the other CSV loaders do. }
        Fields.CommaText := Src[I];
        if Fields.Count < EVENT_CSV_FIELDS then
          Continue;

        FEvents[N].Opcode  := StrToIntDef(Trim(Fields[0]), 0);
        FEvents[N].Field1C := StrToIntDef(Trim(Fields[1]), 0);
        FEvents[N].Field20 := StrToIntDef(Trim(Fields[2]), 0);
        FEvents[N].Field10 := StrToIntDef(Trim(Fields[3]), 0);
        FEvents[N].Field14 := StrToIntDef(Trim(Fields[4]), 0);
        FEvents[N].ParamA  := Fields[5];
        FEvents[N].ParamB  := Fields[6];
        FEvents[N].Active  := False;
        Inc(N);
      end;
      SetLength(FEvents, N);
    end;

    { The dialogue file is read straight into a string list - the original
      copies one string per line with no parsing at all. Its escape codes
      (\n, \e, \k, \w) are the consumer's problem, not the loader's. }
    FileName := Base + Format('tk%.3d.dat', [StageIndex]);
    if FileExists(FileName) then
      FLines.LoadFromFile(FileName);
  finally
    Fields.Free;
    Src.Free;
  end;

  Result := Length(FEvents);
end;

function ProgressIndexOf(const ParamB: string): Integer;
var
  Head: string;
  I: Integer;
begin
  Result := -1;
  if Length(ParamB) < 4 then
    Exit;
  Head := Copy(ParamB, 1, 4);
  for I := 1 to 4 do
    if not (Head[I] in ['0'..'9']) then
      Exit;
  Result := StrToIntDef(Head, -1);
end;

end.
