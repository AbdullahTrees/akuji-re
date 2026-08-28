{ EventRunner - the event script machinery, as running code.

  EventScripts.pas reads the table and EventCommands.pas parses the little
  language. Neither of them RUNS anything: until now the interpreter existed
  only as prose. This is the machinery itself, translated one function at a
  time from:

      0x00454EF4  Event_Begin              start a script
      0x0045509C  EventScript_AdvanceStep  move to the next step
      0x00455210  EventScript_Execute      run the current one, per frame
      0x00454790  Events_SpawnNearCamera   decide what exists at all

  ## The shape of it

  A record's ParamB is a program. Event_Begin splits it on '/' into STEPS and
  hands the first to AdvanceStep. Each step is split on '.' into ALTERNATIVES,
  and exactly one of those runs - the LAST one whose guard flag is set, because
  the scan goes backwards. That is why a `0000-` alternative is written first:
  flag 0 is always set, so it is the default the scan reaches last.

  While a script runs the game sits in GS_STATE_140 rather than GS_PLAY, and
  Event_Begin refuses to start a second one while it is there. Running off the
  end of the steps puts the game back into GS_PLAY.

  ## Progress[1..4] are SCRATCH

  Event_Begin clears exactly those four bytes every time a script starts. They
  are not world flags: nothing in the 692 shipped records reads or writes them,
  as a sweep of the data confirms. What writes them is the interpreter - sub-op
  6 puts a comparison result into Progress[1] and Progress[2] - and what reads
  them is the alternative guard above. So they are an event's local variables,
  and clearing them on entry is what stops one event seeing the last one's.

  Both sub-ops that use them are, as PlayerState.pas records, unused by any
  shipped event. A cut feature whose plumbing is all still here. }

unit EventRunner;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Classes, PlayerState, GameState, EventScripts, EventCommands;

type
  { The interpreter's state. In the original these are six loose globals; they
    are gathered here because they are one thing, and because a test wants to
    make one without disturbing the game's.

        0x0046D24C  the steps array        0x0046D334  which step
        0x0046CE7C  which event            0x0046D028  the argument it began with
        0x0046D218  the cursor within a step
        0x0046CC14  the wait state, cleared on every step boundary }
  TEventRunner = class
  public
    Steps: array of string;
    StepIndex: Integer;
    EventId: Integer;
    Arg: Integer;
    Cursor: Integer;
    Waiting: Integer;

    { 0x00454EF4. Starts the script on an event record, unless one is already
      running - the guard is the game state itself, not a flag. }
    procedure StartEvent(Events: TEventScript; AEventId, AArg: Integer;
                         var P: TPlayerState; var AGameState: Integer);

    { 0x0045509C. Move to the next step and pick its alternative. Running off
      the end returns the game to GS_PLAY. }
    procedure AdvanceStep(var P: TPlayerState; var AGameState: Integer);

    { The alternative chosen for the current step, or '' when none was. }
    function CurrentStep: string;
    function Finished: Boolean;
  end;

{ The guard on an alternative: its first four characters are a progress flag
  index. Exposed because both AdvanceStep and the tests want it, and because
  StrToInt on a malformed one would raise where the original would not. }
function AlternativeFlag(const Alt: string): Integer;

implementation

function AlternativeFlag(const Alt: string): Integer;
begin
  { The original does StrToInt(Copy(alt, 1, 4)) and would raise on anything
    that is not four digits. Every shipped alternative is zero-padded, so this
    only differs on data the game would itself have crashed on. }
  Result := -1;
  if Length(Alt) < 4 then
    Exit;
  if not TryStrToInt(Copy(Alt, 1, 4), Result) then
    Result := -1;
end;

function TEventRunner.CurrentStep: string;
begin
  if (StepIndex < 0) or (StepIndex > High(Steps)) then
    Exit('');
  Result := Steps[StepIndex];
end;

function TEventRunner.Finished: Boolean;
begin
  Result := StepIndex > High(Steps);
end;

procedure TEventRunner.StartEvent(Events: TEventScript;
                                  AEventId, AArg: Integer;
                                  var P: TPlayerState; var AGameState: Integer);
var
  List: TStringList;
  I: Integer;
  Rec: TEventRecord;
begin
  { One script at a time. The state IS the lock. }
  if AGameState = GS_STATE_140 then
    Exit;

  Rec := Events.Events[AEventId];

  List := TStringList.Create;
  try
    List.CommaText := StringReplace(Rec.ParamB, '/', ',', [rfReplaceAll]);
    SetLength(Steps, List.Count);
    for I := 0 to List.Count - 1 do
      Steps[I] := List[I];
  finally
    List.Free;
  end;

  { An event's local variables, wiped so it cannot see the last one's. }
  for I := 1 to 4 do
    P.Progress[I] := 0;

  StepIndex := -1;          { AdvanceStep increments before using it }
  EventId := AEventId;
  Arg := AArg;
  Cursor := 0;
  Waiting := 0;
  AGameState := GS_STATE_140;

  AdvanceStep(P, AGameState);
end;

procedure TEventRunner.AdvanceStep(var P: TPlayerState;
                                   var AGameState: Integer);
var
  List: TStringList;
  I, Flag: Integer;
begin
  Waiting := 0;
  Inc(StepIndex);

  if StepIndex > High(Steps) then
  begin
    AGameState := GS_PLAY;
    Exit;
  end;

  Cursor := 0;
  List := TStringList.Create;
  try
    List.CommaText := StringReplace(Steps[StepIndex], '.', ',', [rfReplaceAll]);

    { BACKWARDS. The last alternative whose flag is set wins, which is why the
      always-true `0000-` default is written first - the scan reaches it last.
      If none matches the step is left empty and does nothing. }
    for I := List.Count - 1 downto 0 do
    begin
      Flag := AlternativeFlag(List[I]);
      if (Flag >= 0) and (Flag < PROGRESS_LENGTH)
         and (P.Progress[Flag] = 1) then
      begin
        Steps[StepIndex] := List[I];
        Exit;
      end;
      Steps[StepIndex] := '';
    end;
  finally
    List.Free;
  end;
end;

end.
