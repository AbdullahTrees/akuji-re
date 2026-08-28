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
  { What the interpreter needs from the rest of the game.

    Six of the eighteen sub-opcodes do presentation rather than logic - they
    fade the screen, show a line of dialogue, change the music, load a stage.
    Those are hooks. The other twelve are self-contained arithmetic on the
    player state and the event table, and they are implemented outright.

    Splitting it that way is deliberate: it keeps the CONTROL FLOW, which is
    the part that was only prose, testable without a renderer. A host that
    does nothing is a legitimate configuration - the script still steps
    through, sets its flags and reaches its end. }
  TEventHost = class
  public
    { sub-op 3 - a line from the stage's tk file }
    procedure ShowLine(Index: Integer); virtual;
    { sub-op 9 / 12 }
    procedure PlaySound(Id: Integer); virtual;
    procedure PlayMusic(Track: Integer; Loop: Boolean); virtual;
    { sub-op 14 - writes straight into layer 0's tilemap }
    procedure SetTile(X, Y, Tile: Integer); virtual;
    { sub-ops 8 and 16, on whatever entity this event placed }
    procedure DestroyEventEntity(EventId: Integer); virtual;
    procedure SetEventEntityState(EventId, Value: Integer); virtual;
    { sub-ops 0, 1 and 80, which change the game state wholesale }
    procedure LoadStage(Stage, PlayerTileX, PlayerTileY,
                        CamTileX, CamTileY: Integer); virtual;
    procedure WarpPlayer(PlayerTileX, PlayerTileY,
                         CamTileX, CamTileY: Integer); virtual;
    procedure SoulGet; virtual;
    procedure SubMode; virtual;
    { sub-op 13 }
    procedure SaveGame(var P: TPlayerState); virtual;
    { The screen fade the stage-changing ops wait on. Busy while it runs. }
    procedure StartFade(Out_: Boolean); virtual;
    function FadeBusy: Boolean; virtual;
  end;

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

    { 0x00455210. One frame of the current step. Most sub-opcodes finish in
      one call and advance; the waiting ones do not. }
    procedure Execute(Host: TEventHost; Events: TEventScript;
                      var P: TPlayerState; var AGameState: Integer);

    { The alternative chosen for the current step, or '' when none was. }
    function CurrentStep: string;
    function Finished: Boolean;

    { The sub-opcode of the current step, or -1 when there is none. }
    function CurrentSubOp: Integer;
  end;

{ The guard on an alternative: its first four characters are a progress flag
  index. Exposed because both AdvanceStep and the tests want it, and because
  StrToInt on a malformed one would raise where the original would not. }
function AlternativeFlag(const Alt: string): Integer;

implementation

{ Every argument in a step sits at a fixed position - which is why every
  number in the shipped data is zero-padded - and EventCommands already
  carries those positions, checked against 988 arguments with no
  disagreements. Reusing them here rather than restating the offsets is the
  point: one table, two readers. }
function StepArg(const Step: string; SubOp, Index: Integer): Integer;
var
  Start, Len: Integer;
begin
  Result := 0;
  if not ArgPosition(SubOp, Index, Start, Len) then
    Exit;
  if not TryStrToInt(Trim(Copy(Step, Start, Len)), Result) then
    Result := 0;
end;

procedure TEventHost.ShowLine(Index: Integer); begin end;
procedure TEventHost.PlaySound(Id: Integer); begin end;
procedure TEventHost.PlayMusic(Track: Integer; Loop: Boolean); begin end;
procedure TEventHost.SetTile(X, Y, Tile: Integer); begin end;
procedure TEventHost.DestroyEventEntity(EventId: Integer); begin end;
procedure TEventHost.SetEventEntityState(EventId, Value: Integer); begin end;
procedure TEventHost.LoadStage(Stage, PlayerTileX, PlayerTileY,
                               CamTileX, CamTileY: Integer); begin end;
procedure TEventHost.WarpPlayer(PlayerTileX, PlayerTileY,
                                CamTileX, CamTileY: Integer); begin end;
procedure TEventHost.SoulGet; begin end;
procedure TEventHost.SubMode; begin end;
procedure TEventHost.SaveGame(var P: TPlayerState); begin end;
procedure TEventHost.StartFade(Out_: Boolean); begin end;
function TEventHost.FadeBusy: Boolean; begin Result := False; end;

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

function TEventRunner.CurrentSubOp: Integer;
var
  Step: string;
begin
  Result := -1;
  Step := CurrentStep;
  if Length(Step) < 7 then
    Exit;
  { positions 6..7, which is why the sub-opcode is always two digits }
  if not TryStrToInt(Copy(Step, 6, 2), Result) then
    Result := -1;
end;

procedure TEventRunner.Execute(Host: TEventHost; Events: TEventScript;
                               var P: TPlayerState; var AGameState: Integer);
var
  Step: string;
  Op, I, N, Flag, Want, Count, Start, Len: Integer;
  Ok: Boolean;
begin
  Step := CurrentStep;

  { An empty step is one whose alternatives all failed their guard. It does
    nothing and moves on, which is how a guarded branch with no default is
    skipped. }
  if Step = '' then
  begin
    AdvanceStep(P, AGameState);
    Exit;
  end;

  Op := CurrentSubOp;
  case Op of

    SUBOP_LOAD_STAGE:
      { Fade out, and only once the fade has finished does the stage change.
        Waiting is the little state machine that spans those frames. }
      begin
        if Waiting = 0 then
        begin
          Waiting := 1;
          Host.StartFade(True);
        end;
        if (Waiting = 1) and (not Host.FadeBusy) then
        begin
          Host.StartFade(False);
          Host.LoadStage(StepArg(Step, Op, 0), StepArg(Step, Op, 1),
                         StepArg(Step, Op, 2), StepArg(Step, Op, 3),
                         StepArg(Step, Op, 4));
          AGameState := GS_STAGE_BEGIN;
          Waiting := 0;
        end;
      end;

    1:
      { The same fade, then a warp within the stage rather than a load. }
      begin
        if Waiting = 0 then
        begin
          Waiting := 1;
          Host.StartFade(True);
        end;
        if (Waiting = 1) and (not Host.FadeBusy) then
        begin
          Host.StartFade(False);
          Host.WarpPlayer(StepArg(Step, Op, 0), StepArg(Step, Op, 1),
                          StepArg(Step, Op, 2), StepArg(Step, Op, 3));
          AGameState := GS_PLAY;
          Waiting := 0;
        end;
      end;

    SUBOP_DIALOGUE:
      { Shown once; the dialogue box itself decides when it is done, and it
        is what calls AdvanceStep afterwards. }
      if Waiting = 0 then
      begin
        Waiting := 1;
        Host.ShowLine(StepArg(Step, Op, 0));
      end;

    SUBOP_SET_FLAG:
      begin
        Flag := StepArg(Step, Op, 0);
        if (Flag >= 0) and (Flag < PROGRESS_LENGTH) then
          P.Progress[Flag] := 1;
        AdvanceStep(P, AGameState);
      end;

    SUBOP_CLEAR_FLAG:
      begin
        Flag := StepArg(Step, Op, 0);
        if (Flag >= 0) and (Flag < PROGRESS_LENGTH) then
          P.Progress[Flag] := 0;
        AdvanceStep(P, AGameState);
      end;

    6:
      { Compare the event counter against a threshold and write the answer
        into the two scratch flags. Unused by any shipped event. }
      begin
        Want := StepArg(Step, Op, 0);
        if P.EventCounter < Want then
        begin
          P.Progress[1] := 0;
          P.Progress[2] := 1;
        end
        else
        begin
          P.Progress[1] := 1;
          P.Progress[2] := 0;
        end;
        AdvanceStep(P, AGameState);
      end;

    SUBOP_DISABLE_EVENT:
      { The same "gone for good" the spawn walk uses: opcode -1 and the tile
        moved off the map. }
      begin
        Events.Disable(EventId);
        AdvanceStep(P, AGameState);
      end;

    SUBOP_DESTROY:
      begin
        Host.DestroyEventEntity(EventId);
        AdvanceStep(P, AGameState);
      end;

    SUBOP_PLAY_SOUND:
      begin
        Host.PlaySound(StepArg(Step, Op, 0));
        AdvanceStep(P, AGameState);
      end;

    SUBOP_SUBMODE:
      Host.SubMode;

    11:
      begin
        Inc(P.EventCounter, StepArg(Step, Op, 0));
        AdvanceStep(P, AGameState);
      end;

    SUBOP_PLAY_MUSIC:
      begin
        { Two single-character flags decide whether the track index is also
          stored as the stage's music and whether it loops. }
        Host.PlayMusic(StepArg(Step, Op, 0), True);
        AdvanceStep(P, AGameState);
      end;

    SUBOP_SAVE:
      begin
        Host.SaveGame(P);
        AdvanceStep(P, AGameState);
      end;

    14:
      begin
        Host.SetTile(StepArg(Step, Op, 0), StepArg(Step, Op, 1),
                     StepArg(Step, Op, 2));
        AdvanceStep(P, AGameState);
      end;

    SUBOP_TEST_FLAGS:
      { arg 1 is a count and that many (op, flag) pairs follow, six characters
        each. Every one must match for the target flag to be set. }
      begin
        Count := StepArg(Step, Op, 1);
        Ok := True;
        for I := 1 to Count do
        begin
          Start := (I - 1) * 6 + 17;
          Want := Ord(Trim(Copy(Step, Start, 1)) <> '0');
          Flag := 0;
          if not TryStrToInt(Trim(Copy(Step, Start + 1, 4)), Flag) then
            Flag := 0;
          if (Flag < 0) or (Flag >= PROGRESS_LENGTH)
             or (P.Progress[Flag] <> Want) then
          begin
            Ok := False;
            Break;
          end;
        end;
        if Ok then
        begin
          Flag := StepArg(Step, Op, 0);
          if (Flag >= 0) and (Flag < PROGRESS_LENGTH) then
            P.Progress[Flag] := 1;
        end;
        AdvanceStep(P, AGameState);
      end;

    SUBOP_ENTITY_FIELD:
      begin
        Host.SetEventEntityState(EventId, StepArg(Step, Op, 0));
        AdvanceStep(P, AGameState);
      end;

    SUBOP_WAIT:
      { The only op that spans frames on its own. The cursor counts up and the
        step ends when it PASSES the argument, so a wait of N takes N + 1. }
      begin
        Inc(Cursor);
        if StepArg(Step, Op, 0) < Cursor then
          AdvanceStep(P, AGameState);
      end;

    SUBOP_SOUL_GET:
      begin
        Host.SoulGet;
        AdvanceStep(P, AGameState);
      end;

    SUBOP_NOP:
      AdvanceStep(P, AGameState);

  else
    { An unknown sub-opcode does nothing at all in the original - no advance,
      no error - which would hang the script. Reproduced, because inventing a
      recovery would hide data that should never occur. }
    N := 0;
    if N <> 0 then
      AdvanceStep(P, AGameState);
  end;
end;

end.