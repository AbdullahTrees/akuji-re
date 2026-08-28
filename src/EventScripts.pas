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
      csv 1 -> +0x1C int      REQUIRED progress flag  (0 = no condition)
      csv 2 -> +0x20 int      FORBIDDING progress flag (0 = no condition)
      csv 3 -> +0x10 int      tile X
      csv 4 -> +0x14 int      tile Y
      csv 5 -> +0x0C string   ParamA - what to place, see EventCommands.pas
      csv 6 -> +0x18 string   ParamB

  The loader never writes +0x04, +0x05 or +0x08; all three are runtime state,
  and Events_SpawnNearCamera @ 0x00454790 shows what they are:

      +0x04  byte, "inside the camera window"; cleared again when it leaves
      +0x05  byte, "an entity for this event exists right now"
      +0x08  int, the entity slot that entity occupies

  So the record is bigger than the file's content by exactly its bookkeeping.

  ## The two condition fields

  Every frame, Events_SpawnNearCamera walks the whole table and spawns anything
  inside a window of the camera - the visible 10 x 7.5 tiles plus two tiles of
  margin on every side. Before it spawns, it applies csv 1 and csv 2:

      if (csv1 = 0) or (Progress[csv1] <> 0) then      // required
        if (csv2 = 0) or (Progress[csv2] <> 1) then    // forbidding
          spawn it
        else
          disable the event PERMANENTLY - opcode := -1, tile := (-32, -32) -
          and destroy its entity if one is out

  That is the whole "this is gone for good now" mechanism, and it explains a
  pattern that had been noticed in the data without an explanation: for all 154
  opcode-5 records, the flag the event SETS is its own csv 2. Pick the item up,
  the flag goes to 1, and the event disables itself the next time the camera
  comes near. One field, read two ways, agreeing 154 times out of 154.

  csv 1 is the same idea inverted, and it is how the game does DIFFICULTY.
  Game_StartOrLoad publishes the difficulty as one of Progress[10], Progress[5]
  and Progress[6] for levels 0, 1 and 2 - and 5, 40 and 23 records respectively
  require exactly those flags. Nothing else in the game reads them, and no
  event script guards on them, which is why they looked dead until this
  function was read.

  Validated against the shipped data: all 692 lines across all 66 ev files have
  exactly seven fields, with no exceptions and nothing needing a fallback.

  ## Opcodes

  Seven distinct values appear in the shipped data:

      0 x18    1 x249    4 x9    5 x154    6 x5    7 x26    9 x231

  Opcodes 2 and 3 exist in the CODE and appear nowhere in the data. Both
  Entity_SolidCollideX and Entity_SolidCollideY, having found that the player
  is pressing against a solid, look up that solid's event and start it if the
  opcode is 2 (while holding the axis into it) or 3 (while pressing confirm).
  A "push against this to trigger it" pair that shipped unused.

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
      4   ALWAYS ACTIVE. Events_SpawnNearCamera spawns it regardless of where
          the camera is - the window test is bypassed for opcode 4 - and then
          calls Event_Begin on it immediately, every frame, until something
          stops it.

          All nine in the shipped data sit at tile (1,1) as entity type 20
          with csv 1 clear and csv 2 set, and all nine SET THEIR OWN CSV 2 - so
          a solved puzzle retires its own checker. Nine of nine on that.

          EIGHT of them are also the same program: test a list of flags with
          sub-op 15, and on success set the flag, wait 10 frames, play sound 32
          and disable with sub-op 7. This once read "nine of nine, no
          exceptions" and that was wrong; --selftest-runner found it by
          driving each one. Stage 58's is

              4,0000,1158,0001,0001,0020-*,1157-04-1158/1158-09-0032

          with no list, no wait and no sub-op 7. It leaves by the other route:
          setting 1158 makes the next spawn sweep disable the record, because
          1158 is its own csv 2. So there are two ways for a checker to retire
          and both end at the same place.

          Type 20 is also the one type Events_SpawnNearCamera special-cases,
          forcing its box to 32x32.

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

      9   A COLLECTIBLE. Nothing branches on the opcode itself; what reads
          this record's ParamB is the TOUCH HANDLER of the entity it places.
          Entity_PlayerTouch switches on EF_TOUCH_KIND, and kinds 2 and 5 both
          do the same thing opcode 5 does - Progress[Copy(ParamB,1,4)] := 1 -
          on top of their own effect:

            kind 2  a pickup. Entity int 6 (which ParamA's 'A' letter sets)
                    picks the value: 0 adds 1 to the counter, 1 adds 10. When
                    the counter reaches the target for the current
                    TargetIndex, TargetIndex and MaxLives both go up and Lives
                    is refilled - this is the Mana Stone that tk001.dat talks
                    about, read out of the code rather than inferred from the
                    save.
            kind 5  a full heal: Lives := MaxLives, sound 0x14.

          The partition is exact and has no exceptions. All 231 opcode-9
          records split 127 with an id and 104 with '*', and

            * every one of the 127 places a type whose touch kind is 2 or 5
              (122 and 5 respectively)
            * every one of the 104 places a type whose touch kind is 0, 1, 3,
              6 or 7 - never 2 or 5

          which is what it has to look like: StrToInt('*') would raise. And as
          with opcode 5, the id equals the record's own csv 2 in all 127 cases,
          so collecting the thing is what stops it coming back.

  Every opcode is now accounted for. }

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
        FEvents[N].NeedsFlag := StrToIntDef(Trim(Fields[1]), 0);
        FEvents[N].BlockedBy := StrToIntDef(Trim(Fields[2]), 0);
        FEvents[N].TileX := StrToIntDef(Trim(Fields[3]), 0);
        FEvents[N].TileY := StrToIntDef(Trim(Fields[4]), 0);
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
