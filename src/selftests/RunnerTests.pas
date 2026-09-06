{ Self-tests for the event-script interpreter. }

unit RunnerTests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, TypInfo,
  QdaArchive, SoundTable, WaveFile, AudioMixer, AudioOut, MidiFile, KbgmPlayer,
  Directions, Entities, EventScripts, EventCommands, PlayerState, GameState,
  Stages, Camera, TileMaps, Player, EntityHandlers, EventRunner, GameSession,
  SpritePool, Sprites, Dialogue, BgAnime, UnitInit, Title, Ending, Opening,
  GameFont, DDDDComponent, Surfaces;

function SelfTestRunner(Log: TStrings): Integer;

implementation

{ --selftest-runner executes event programs through a recording TEventHost so
  stepping, waits, branches, presentation calls, and saves remain observable.

  The standard save-point program is:

  All 43 stages that have one carry a byte-identical Devil Statue:

      1,0000,0000,tx,ty,0027-*,0000-03-0000/0003-13/0003-03-0001

  It shows line 0, conditionally saves, then conditionally shows line 1. Each
  matching tk file begins with:

      Will you save the game? \w

  where \w is the yes/no prompt. All 86 shipped alternatives that guard a
  scratch flag use Progress[3], the Yes result, after an earlier \w prompt.
  Flags 1, 2, and 4 are only written by unused sub-op 6.

  The converse holds 43 times out of 44. The exception is stage 4's

      1,0000,0000,0004,0006,0016-*,0000-03-0000

  a type-16 sign - the plain read-a-plaque entity, 62 of them in the game -
  whose one step shows line 0 of tk004. tk004 has three lines and the statue
  owns the first two, so this sign asks "Will you save the game?", takes an
  answer and stops. It is the only one of the 62 signs pointing at a \w line.
  Left alone: this reproduces the shipped data, it does not correct it.
  --------------------------------------------------------------------------- }

type
  { A host that writes down what it was asked to do, so the control flow can be
    asserted on rather than merely observed not to crash. }
  TTraceHost = class(TEventHost)
  public
    Trace: TStringList;
    { Whether a box is up. The real host answers this from FActive, and
      sub-op 3 guards on it exactly as 0x00455210 guards on 0x0046CF28 - so a
      stub that always says "no box" makes the arm re-raise every frame. }
    MsgUp: Boolean;
    Saves: Integer;
    Fading: Boolean;      { what FadeBusy answers }
    constructor Create;
    destructor Destroy; override;
    procedure ShowLine(Index: Integer); override;
    function MessageBusy: Boolean; override;
    procedure PlaySound(Id: Integer); override;
    procedure PlayMusic(Track: Integer; Loop: Boolean); override;
    procedure SetTile(X, Y, Tile: Integer); override;
    procedure DestroyEventEntity(EventId: Integer); override;
    procedure SetEventEntityState(EventId, Value: Integer); override;
    procedure LoadStage(Stage, PlayerTileX, PlayerTileY,
                        CamTileX, CamTileY: Integer); override;
    procedure WarpPlayer(PlayerTileX, PlayerTileY,
                         CamTileX, CamTileY: Integer); override;
    procedure SoulGet; override;
    procedure SubMode; override;
    procedure SaveGame(var P: TPlayerState); override;
    procedure StartFade(Out_: Boolean); override;
    function FadeBusy: Boolean; override;
  end;

constructor TTraceHost.Create;
begin
  inherited Create;
  Trace := TStringList.Create;
end;

destructor TTraceHost.Destroy;
begin
  Trace.Free;
  inherited Destroy;
end;

procedure TTraceHost.ShowLine(Index: Integer);
begin Trace.Add(Format('line %d', [Index])); MsgUp := True; end;
function TTraceHost.MessageBusy: Boolean;
begin Result := MsgUp; end;
procedure TTraceHost.PlaySound(Id: Integer);
begin Trace.Add(Format('sound %d', [Id])); end;
procedure TTraceHost.PlayMusic(Track: Integer; Loop: Boolean);
begin Trace.Add(Format('music %d', [Track])); end;
procedure TTraceHost.SetTile(X, Y, Tile: Integer);
begin Trace.Add(Format('tile %d,%d=%d', [X, Y, Tile])); end;
procedure TTraceHost.DestroyEventEntity(EventId: Integer);
begin Trace.Add(Format('destroy %d', [EventId])); end;
procedure TTraceHost.SetEventEntityState(EventId, Value: Integer);
begin Trace.Add(Format('state %d=%d', [EventId, Value])); end;
procedure TTraceHost.LoadStage(Stage, PlayerTileX, PlayerTileY,
                               CamTileX, CamTileY: Integer);
begin Trace.Add(Format('stage %d at %d,%d cam %d,%d',
  [Stage, PlayerTileX, PlayerTileY, CamTileX, CamTileY])); end;
procedure TTraceHost.WarpPlayer(PlayerTileX, PlayerTileY,
                                CamTileX, CamTileY: Integer);
begin Trace.Add(Format('warp %d,%d cam %d,%d',
  [PlayerTileX, PlayerTileY, CamTileX, CamTileY])); end;
procedure TTraceHost.SoulGet;
begin Trace.Add('soul'); end;
procedure TTraceHost.SubMode;
begin Trace.Add('submode'); end;
procedure TTraceHost.SaveGame(var P: TPlayerState);
begin Trace.Add('save'); Inc(Saves); end;
procedure TTraceHost.StartFade(Out_: Boolean);
begin Trace.Add(Format('fade %d', [Ord(Out_)])); end;
function TTraceHost.FadeBusy: Boolean;
begin Result := Fading; end;

{ A fresh player state with the session flags Game_StartOrLoad would have
  applied - Progress[0] := 1 above all, which every 0000- default depends on. }
procedure FreshPlayer(out P: TPlayerState);
begin
  InitNewGame(P, 0);
  ApplySessionFlags(P, 0);
end;

{ Find the first opcode-4 record in the given stage. -1 if none - most stages
  have none at all: the nine puzzle checkers live in stages 14, 20, 31, 37, 48,
  57, 58, 60 and 61. }
function FindChecker(S: TEventScript): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to S.Count - 1 do
    if S[I].Opcode = EVOP_ALWAYS then
      Exit(I);
end;

{ Find the record carrying a particular program. -1 if none. }
function FindByProgram(S: TEventScript; const Prog: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to S.Count - 1 do
    if S[I].ParamB = Prog then
      Exit(I);
end;

{ Run frames until the script leaves GS_STATE_140 or the budget runs out.

  The dialogue box and the sub-mode screen are what advance their own steps in
  the game - Execute only starts them - so this stands in for both, finishing
  each instantly. Everything else advances itself. Returns the frame count, or
  -1 if the budget was exhausted, which is the "this program hangs" answer.

  The stand-in fires only when the frame did not advance on its own, preventing
  a newly selected dialogue step from being skipped. }
function DriveToEnd(R: TEventRunner; Host: TEventHost; S: TEventScript;
                    var P: TPlayerState; var GS: Integer;
                    Budget: Integer): Integer;
var
  Frames, Was: Integer;
begin
  Frames := 0;
  while (GS = GS_STATE_140) and (Frames < Budget) do
  begin
    Was := R.StepIndex;
    R.Execute(Host, S, P, GS);
    Inc(Frames);
    if (R.StepIndex = Was)
       and ((R.CurrentSubOp = SUBOP_DIALOGUE)
            or (R.CurrentSubOp = SUBOP_SUBMODE)) then
    begin
      { The box or the panel is what advances a script, and closing it is also
        what lets the next sub-op 3 raise one - the arm guards on the message
        mode, as 0x00455210 does. Standing in for the player dismissing it. }
      if Host is TTraceHost then
        TTraceHost(Host).MsgUp := False;
      R.AdvanceStep(P, GS);
    end;
  end;
  if GS = GS_STATE_140 then
    Result := -1
  else
    Result := Frames;
end;

{ --- 1. the save point, both answers ------------------------------------- }

function TestSavePoint(Log: TStrings; const GameDir: string): Integer;
const
  STATUE = '0000-03-0000/0003-13/0003-03-0001';
var
  S: TEventScript;
  R: TEventRunner;
  H: TTraceHost;
  P: TPlayerState;
  GS, Idx, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then
    begin
      Log.Add('  ' + What);
      Inc(Bad);
    end;
  end;

begin
  Bad := 0;
  Log.Add('the Devil Statue, run end to end:');

  S := TEventScript.Create;
  R := TEventRunner.Create;
  H := TTraceHost.Create;
  try
    S.Load(GameDir, 2);
    Idx := FindByProgram(S, STATUE);
    if Idx < 0 then
    begin
      Log.Add('  FAILED: stage 2 has no save point - wrong game directory?');
      Result := 1;
      Exit;
    end;
    Want(S.Lines[0] = 'Will you save the game? \w',
         'line 0 of tk002 is not the save prompt: ' + S.Lines[0]);

    { --- the answer is NO --------------------------------------------- }
    FreshPlayer(P);
    { Set the scratch flag BEFORE starting, so that an Event_Begin which failed
      to clear it would run the yes branch and be caught here. }
    P.Progress[3] := 1;
    GS := GS_PLAY;
    R.StartEvent(S, Idx, 0, P, GS);

    Want(GS = GS_STATE_140, 'starting a script did not enter GS_STATE_140');
    Want(P.Progress[3] = 0, 'Event_Begin did not clear the scratch flag');
    Want(R.StepIndex = 0, Format('first step is %d, want 0', [R.StepIndex]));
    Want(R.CurrentStep = '0000-03-0000', 'first step chose ' + R.CurrentStep);
    Want(R.CurrentSubOp = SUBOP_DIALOGUE,
         Format('first sub-op is %d, want 3', [R.CurrentSubOp]));

    R.Execute(H, S, P, GS);
    Want(H.Trace.CommaText = '"line 0"',
         'the prompt was not shown once: ' + H.Trace.CommaText);
    Want(R.StepIndex = 0, 'the dialogue step advanced by itself');

    { A second frame while the box is up must not show it again. }
    R.Execute(H, S, P, GS);
    Want(H.Trace.Count = 1, 'the prompt was shown twice: ' + H.Trace.CommaText);

    { The box closes on NO, so flag 3 stays clear; the box is what advances -
      and closing it is what lets a later sub-op 3 raise one again. }
    H.MsgUp := False;
    R.AdvanceStep(P, GS);
    Want(R.StepIndex = 1, 'the dialogue did not advance to step 1');
    Want(R.CurrentStep = '', 'step 1 ran with flag 3 clear: ' + R.CurrentStep);

    Want(DriveToEnd(R, H, S, P, GS, 32) >= 0, 'the no branch did not finish');
    Want(GS = GS_PLAY, 'running off the end did not return to GS_PLAY');
    Want(R.Finished, 'the runner does not report itself finished');
    Want(H.Saves = 0, 'the game was SAVED after answering no');
    Want(H.Trace.Count = 1,
         'the no branch did more than show the prompt: ' + H.Trace.CommaText);

    { --- the answer is YES -------------------------------------------- }
    H.Trace.Clear;  H.MsgUp := False;   { a fresh scenario: no box up }
    H.Saves := 0;
    FreshPlayer(P);
    GS := GS_PLAY;
    R.StartEvent(S, Idx, 0, P, GS);
    R.Execute(H, S, P, GS);

    { The prompt's answer. It is the only thing that differs between the two
      runs, and it is one byte. }
    P.Progress[3] := 1;
    H.MsgUp := False;   { the box closing is what advances }
    R.AdvanceStep(P, GS);

    Want(R.CurrentStep = '0003-13', 'the yes branch chose ' + R.CurrentStep);
    Want(R.CurrentSubOp = SUBOP_SAVE,
         Format('step 1 sub-op is %d, want 13', [R.CurrentSubOp]));

    Want(DriveToEnd(R, H, S, P, GS, 32) >= 0, 'the yes branch did not finish');
    Want(GS = GS_PLAY, 'the yes branch did not return to GS_PLAY');
    Want(H.Saves = 1, Format('the game was saved %d times, want 1', [H.Saves]));
    Want(H.Trace.CommaText = '"line 0",save,"line 1"',
         'the yes branch trace is ' + H.Trace.CommaText);
  finally
    H.Free;
    R.Free;
    S.Free;
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - one byte of Progress[3] is the whole branch, both ways');
end;

{ --- 2. Event_Begin's bookkeeping ---------------------------------------- }

function TestEventBegin(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  P: TPlayerState;
  GS, I, A, B, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('Event_Begin:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  try
    S.Load(GameDir, 2);
    A := -1; B := -1;
    for I := 0 to S.Count - 1 do
      if ClassifyParamB(S[I].ParamB) = pbProgram then
        if A < 0 then A := I else if B < 0 then B := I;
    if (A < 0) or (B < 0) then
    begin
      Log.Add('  FAILED: stage 2 has fewer than two programs');
      Result := 1;
      Exit;
    end;

    { Exactly Progress[1..4] are cleared, and nothing else. Flag 0 is the
      always-true default and clearing it would break every 0000- guard in the
      game; the world flags around the scratch block must survive too. }
    FreshPlayer(P);
    for I := 0 to 12 do
      P.Progress[I] := 1;
    P.Progress[1006] := 1;
    GS := GS_PLAY;
    R.StartEvent(S, A, 7, P, GS);

    for I := 1 to 4 do
      Want(P.Progress[I] = 0,
           Format('Progress[%d] survived Event_Begin', [I]));
    Want(P.Progress[0] = 1, 'Event_Begin cleared Progress[0], the default guard');
    for I := 5 to 12 do
      Want(P.Progress[I] = 1,
           Format('Event_Begin cleared Progress[%d], outside the scratch block', [I]));
    Want(P.Progress[1006] = 1, 'Event_Begin cleared a world flag');
    Want(R.EventId = A, 'Event_Begin did not record which event it started');
    Want(R.Arg = 7, 'Event_Begin did not record its argument');

    { One script at a time - and the lock IS the game state, not a flag. A
      second start while GS_STATE_140 must leave the first one untouched. }
    R.StartEvent(S, B, 0, P, GS);
    Want(R.EventId = A,
         Format('a second script started over the first: event %d', [R.EventId]));

    { Out of GS_STATE_140 the same call goes through. That is what says the
      guard is the state rather than an accident of the data. }
    GS := GS_PLAY;
    R.StartEvent(S, B, 0, P, GS);
    Want(R.EventId = B, 'a script would not start from GS_PLAY');
  finally
    R.Free;
    S.Free;
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - the scratch block is cleared, the world is not, '
      + 'and the state is the lock');
end;

{ --- 3. the backwards alternative scan ----------------------------------- }

function TestBackwardsScan(Log: TStrings; const GameDir: string): Integer;
const
  { A real shipped sign in stage 1: line 1 normally, line 3 once flag 1006 is
    set. Both alternatives are satisfiable at once, since flag 0 is always set,
    so this is exactly the case that tells the two scan directions apart. }
  TWO_WAY = '0000-03-0001.1006-03-0003';
var
  S: TEventScript;
  R: TEventRunner;
  H: TTraceHost;
  P: TPlayerState;
  GS, Idx, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('the alternative scan:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  H := TTraceHost.Create;
  try
    S.Load(GameDir, 1);
    Idx := FindByProgram(S, TWO_WAY);
    if Idx < 0 then
    begin
      Log.Add('  FAILED: stage 1 no longer carries ' + TWO_WAY);
      Result := 1;
      Exit;
    end;

    FreshPlayer(P);
    GS := GS_PLAY;
    R.StartEvent(S, Idx, 0, P, GS);
    Want(R.CurrentStep = '0000-03-0001',
         'with 1006 clear the step chose ' + R.CurrentStep);
    R.Execute(H, S, P, GS);
    Want(H.Trace.CommaText = '"line 1"', 'showed ' + H.Trace.CommaText);

    H.Trace.Clear;  H.MsgUp := False;   { a fresh scenario: no box up }
    FreshPlayer(P);
    P.Progress[1006] := 1;
    GS := GS_PLAY;
    R.StartEvent(S, Idx, 0, P, GS);
    Want(R.CurrentStep = '1006-03-0003',
         'with 1006 set the step chose ' + R.CurrentStep
         + ' - a FORWARDS scan would take the 0000 default, which is why it is'
         + ' written first');
    R.Execute(H, S, P, GS);
    Want(H.Trace.CommaText = '"line 3"', 'showed ' + H.Trace.CommaText);

    { And a step none of whose guards hold does nothing and moves on. There is
      no such step in the shipped data with flag 0 always set, so it is built:
      clearing Progress[0] falsifies the default too. }
    FreshPlayer(P);
    P.Progress[0] := 0;
    GS := GS_PLAY;
    R.StartEvent(S, Idx, 0, P, GS);
    Want(R.CurrentStep = '',
         'a step with no satisfied guard chose ' + R.CurrentStep);
    H.Trace.Clear;  H.MsgUp := False;   { a fresh scenario: no box up }
    Want(DriveToEnd(R, H, S, P, GS, 16) >= 0, 'an empty step did not advance');
    Want(H.Trace.Count = 0, 'an empty step did something: ' + H.Trace.CommaText);
    Want(GS = GS_PLAY, 'an all-empty program did not return to GS_PLAY');
  finally
    H.Free;
    R.Free;
    S.Free;
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - the LAST satisfied alternative wins, and none is not an error');
end;

{ --- 4. the waiting sub-opcodes ------------------------------------------ }

function TestWaiting(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  H: TTraceHost;
  P: TPlayerState;
  GS, I, Idx, Frames, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('the ops that span frames:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  H := TTraceHost.Create;
  try
    { --- sub-op 17: a wait of N lasts N + 1 frames --------------------
      Stage 14's checker is the simplest: two switches, then the wait. }
    S.Load(GameDir, 14);
    Idx := FindChecker(S);
    if Idx < 0 then
    begin
      Log.Add('  FAILED: stage 14 has no opcode-4 checker');
      Result := 1;
      Exit;
    end;

    { Drive it to the wait step by hand: set the flags its list wants so the
      first step passes, then count frames on the second. }
    FreshPlayer(P);
    P.Progress[4000] := 1;
    P.Progress[4001] := 1;
    GS := GS_PLAY;
    R.StartEvent(S, Idx, EVENT_BEGIN_FROM_SPAWN, P, GS);
    R.Execute(H, S, P, GS);       { the flag list, which advances }

    if R.CurrentSubOp <> SUBOP_WAIT then
      Log.Add(Format('  the checker did not reach its wait: sub-op %d, step %s',
        [R.CurrentSubOp, R.CurrentStep]))
    else
    begin
      Frames := 0;
      while (R.CurrentSubOp = SUBOP_WAIT) and (Frames < 64) do
      begin
        R.Execute(H, S, P, GS);
        Inc(Frames);
      end;
      { The argument is 000010 and the cursor is compared AFTER it increments,
        so the step ends on the eleventh frame, not the tenth. }
      Want(Frames = 11,
           Format('a wait of 10 took %d frames, want 11', [Frames]));
    end;

    { --- sub-op 0: the fade gates the load ---------------------------- }
    H.Trace.Clear;  H.MsgUp := False;   { a fresh scenario: no box up }
    S.Load(GameDir, 2);
    Idx := -1;
    for I := 0 to S.Count - 1 do
      if (ClassifyParamB(S[I].ParamB) = pbProgram)
         and (Copy(S[I].ParamB, 6, 2) = '00') then
        Idx := I;
    if Idx < 0 then
      Log.Add('  FAILED: stage 2 has no program starting with a stage load')
    else
    begin
      FreshPlayer(P);
      GS := GS_PLAY;
      H.Fading := True;           { the fade is still running }
      R.StartEvent(S, Idx, 0, P, GS);
      R.Execute(H, S, P, GS);
      Want(H.Trace.CommaText = '"fade 1"',
           'the fade out was not started, or the load ran anyway: '
           + H.Trace.CommaText);
      Want(GS = GS_STATE_140, 'the stage loaded while the fade was still busy');
      R.Execute(H, S, P, GS);
      Want(H.Trace.Count = 1, 'the fade was started twice');

      H.Fading := False;          { the fade lands }
      R.Execute(H, S, P, GS);
      Want(GS = GS_STAGE_BEGIN,
           Format('after the fade the state is %d, want %d',
                  [GS, GS_STAGE_BEGIN]));
      Want(Pos('stage ', H.Trace.CommaText) > 0,
           'the stage was never loaded: ' + H.Trace.CommaText);
    end;
  finally
    H.Free;
    R.Free;
    S.Free;
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - the wait is inclusive and the fade really does gate the load');
end;

{ --- 5. the flag list, which is the whole of the nine puzzle checkers ----- }

function TestFlagList(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  H: TTraceHost;
  P: TPlayerState;
  Prog: TEventProgram;
  Cmd: TEventCommand;
  GS, I, J, Idx, Target, Count, Item, Checkers, Lists, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

  { Set every flag the list wants to the value it wants, except that item
    Except_ (or none, when it is -1) is set to the opposite. }
  procedure Arm(const C: TEventCommand; Except_: Integer);
  var
    K, Flag, Wanted: Integer;
  begin
    for K := 0 to C.Args[1] - 1 do
    begin
      Flag := C.Args[2 + K] mod 10000;
      Wanted := C.Args[2 + K] div 10000;
      if K = Except_ then
        Wanted := 1 - Wanted;
      P.Progress[Flag] := Wanted;
    end;
  end;

begin
  Bad := 0;
  Checkers := 0;
  Lists := 0;
  Log.Add('sub-op 15, the flag list:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  H := TTraceHost.Create;
  try
    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for Idx := 0 to S.Count - 1 do
      begin
        if S[Idx].Opcode <> EVOP_ALWAYS then
          Continue;
        Prog := ParseProgram(S[Idx].ParamB);
        if Length(Prog) = 0 then
          Continue;
        Inc(Checkers);
        Cmd := Prog[0].Alternatives[0];
        if Cmd.SubOp <> SUBOP_TEST_FLAGS then
        begin
          { Stage 58's checker is `1157-04-1158/1158-09-0032` - a plain set-flag
            behind a guard rather than a list. Drive it anyway: it is the only
            place in the shipped data where sub-op 4's effect is observable
            from a script alone, and without it a SET_FLAG that CLEARED its
            flag passed every check here. }
          if Cmd.SubOp = SUBOP_SET_FLAG then
          begin
            FreshPlayer(P);
            GS := GS_PLAY;
            R.StartEvent(S, Idx, EVENT_BEGIN_FROM_SPAWN, P, GS);
            R.Execute(H, S, P, GS);
            Want(P.Progress[Cmd.Args[0]] = 0,
                 Format('  stage %d: flag %d was set with guard %d clear',
                        [I, Cmd.Args[0], Cmd.Guard]));

            FreshPlayer(P);
            P.Progress[Cmd.Guard] := 1;
            GS := GS_PLAY;
            R.StartEvent(S, Idx, EVENT_BEGIN_FROM_SPAWN, P, GS);
            R.Execute(H, S, P, GS);
            Want(P.Progress[Cmd.Args[0]] = 1,
                 Format('  stage %d: guard %d set but flag %d did not go up',
                        [I, Cmd.Guard, Cmd.Args[0]]));

            { It sets its own forbidding flag - the property that does hold
              for all nine, and the one that retires this one. }
            Want(Cmd.Args[0] = S[Idx].BlockedBy,
                 Format('  stage %d: sets flag %d but its csv 2 is %d',
                        [I, Cmd.Args[0], S[Idx].BlockedBy]));
          end;
          Continue;
        end;
        Inc(Lists);
        Target := Cmd.Args[0];
        Count := Cmd.Args[1];

        { All conditions met: the target flag goes up. }
        FreshPlayer(P);
        Arm(Cmd, -1);
        GS := GS_PLAY;
        R.StartEvent(S, Idx, EVENT_BEGIN_FROM_SPAWN, P, GS);
        R.Execute(H, S, P, GS);
        Want(P.Progress[Target] = 1,
             Format('  stage %d: all %d conditions met but flag %d is clear',
                    [I, Count, Target]));

        { Any ONE condition wrong and it must not. Every item is tried, so an
          implementation that only read the first would fail here. }
        for J := 0 to Count - 1 do
        begin
          FreshPlayer(P);
          Arm(Cmd, J);
          GS := GS_PLAY;
          R.StartEvent(S, Idx, EVENT_BEGIN_FROM_SPAWN, P, GS);
          R.Execute(H, S, P, GS);
          Item := Cmd.Args[2 + J];
          Want(P.Progress[Target] = 0,
               Format('  stage %d: item %d (%.5d) wrong but flag %d went up',
                      [I, J, Item, Target]));
        end;
      end;
    end;
  finally
    H.Free;
    R.Free;
    S.Free;
  end;

  { The game contains nine opcode-4 records; eight carry flag lists. Stage 58
    instead retires through its own blocking flag. Pin both counts so an empty
    parser result cannot pass vacuously. }
  if (Checkers <> 9) or (Lists <> 8) then
  begin
    Log.Add(Format('  FAILED: %d opcode-4 checkers carrying %d flag lists,'
      + ' want 9 and 8', [Checkers, Lists]));
    Inc(Bad);
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - all 8 flag lists, and every one of their conditions,'
      + ' tested both ways');
end;

{ --- 6. every shipped program runs to completion ------------------------- }

function TestEveryProgram(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  H: TTraceHost;
  P: TPlayerState;
  GS, I, J, Frames, Programs, Hung, Lines, Bad: Integer;
begin
  Bad := 0;
  Programs := 0; Hung := 0; Lines := 0;
  S := TEventScript.Create;
  R := TEventRunner.Create;
  H := TTraceHost.Create;
  try
    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for J := 0 to S.Count - 1 do
      begin
        if ClassifyParamB(S[J].ParamB) <> pbProgram then
          Continue;
        Inc(Programs);
        H.Trace.Clear;  H.MsgUp := False;   { a fresh scenario: no box up }
        FreshPlayer(P);
        GS := GS_PLAY;
        R.StartEvent(S, J, 0, P, GS);
        { 4 steps at most, the longest wait is 11 frames, and every other op
          finishes in one. 64 is comfortable room and still catches a hang. }
        Frames := DriveToEnd(R, H, S, P, GS, 64);
        { Sub-op 80 deliberately never advances: it runs three phases and
          transfers control to GS_ENDING. TTraceHost records SoulGet but does
          not model that state machine, so a frame-limit result is expected. }
        if (Frames < 0) and (Pos('-80', S[J].ParamB) = 0) then
        begin
          Log.Add(Format('  stage %d event %d did not finish: %s  (stuck on %s)',
            [I, J, S[J].ParamB, R.CurrentStep]));
          Inc(Hung);
        end;
        Inc(Lines, H.Trace.Count);
      end;
    end;
  finally
    H.Free;
    R.Free;
    S.Free;
  end;

  Log.Add(Format('programs driven to completion: %d  (%d hung)',
    [Programs, Hung]));
  Log.Add(Format('host calls made:               %d', [Lines]));
  Inc(Bad, Hung);

  { --selftest-script counts 307 programs in the shipped data by an entirely
    separate route. Pinning it here is what stops this sweep from passing
    because it ran over nothing. }
  if Programs <> 307 then
  begin
    Log.Add(Format('  FAILED: expected 307 programs, got %d'
      + ' - wrong game directory?', [Programs]));
    Inc(Bad);
  end;
  if Lines = 0 then
  begin
    Log.Add('  FAILED: 307 programs and not one reached the host');
    Inc(Bad);
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - no shipped program hangs, and every one does something');
end;

{ --- 7. Events_SpawnNearCamera ------------------------------------------- }

function TestSpawnWindow(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  Pool: TEntityPool;
  P: TPlayerState;
  L: TLayerInfo;
  GS, I, Idx, Tx, Ty, Slot, Live, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

  { One sweep with the camera at the given tile; True if the record under test
    now holds an entity. The script is RELOADED each time, because its
    in-window and has-entity marks are what the sweep reads. }
  function SpawnsAt(CamX, CamY: Integer): Boolean;
  begin
    S.Load(GameDir, 2);
    Pool.Clear;
    GS := GS_PLAY;
    R.SpawnNearCamera(S, Pool, L, CamX, CamY, P, GS);
    Result := S[Idx].Active;
  end;

begin
  Bad := 0;
  Log.Add('Events_SpawnNearCamera:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  Pool := TEntityPool.Create;
  try
    FillChar(L, SizeOf(L), 0);
    L.TileW := 32;
    L.TileH := 32;
    L.MapTilesX := 128;
    L.MapTilesY := 128;
    L.OriginX := POSITION_BIAS;      { the camera at the map origin }
    L.OriginY := POSITION_BIAS;
    FreshPlayer(P);

    S.Load(GameDir, 2);
    { A record with no flag conditions, so only the window decides. }
    Idx := -1;
    for I := 0 to S.Count - 1 do
      if (S[I].NeedsFlag = 0) and (S[I].BlockedBy = 0)
         and (S[I].Opcode <> EVOP_ALWAYS) then
        Idx := I;
    if Idx < 0 then
    begin
      Log.Add('  FAILED: stage 2 has no unconditional record');
      Result := 1;
      Exit;
    end;
    Tx := S[Idx].TileX;
    Ty := S[Idx].TileY;

    { The window is CamTile - 2 < tile < CamTile + 12 across, so the camera may
      sit anywhere in Tx - 11 .. Tx + 1 and no further either way. Both edges
      are tested from BOTH sides, which is what pins a strict < against a <=. }
    Want(SpawnsAt(Tx - 11, Ty), 'did not spawn at the far edge of the window');
    Want(not SpawnsAt(Tx - 12, Ty), 'spawned one tile beyond the far edge');
    Want(SpawnsAt(Tx + 1, Ty), 'did not spawn at the near edge');
    Want(not SpawnsAt(Tx + 2, Ty), 'spawned one tile beyond the near edge');

    { Down the screen the window is shorter: 7.5 tiles plus the same margin.
      Note that the half tile is not observable here - tile < Cam + 9.5 and
      tile < Cam + 10 accept exactly the same integers - so this pins the
      integer boundary and nothing finer. }
    Want(SpawnsAt(Tx, Ty - 9), 'did not spawn at the bottom of the window');
    Want(not SpawnsAt(Tx, Ty - 10), 'spawned one tile below the window');
    Want(SpawnsAt(Tx, Ty + 1), 'did not spawn at the top of the window');
    Want(not SpawnsAt(Tx, Ty + 2), 'spawned one tile above the window');

    { In the window, the entity lands in the MIDDLE of its tile and remembers
      which record put it there.

      The 512 is written out rather than spelled SPAWN_TILE_CENTRE on purpose.
      Both were the constant to begin with, and mutation testing walked
      straight past a build with SPAWN_TILE_CENTRE set to 0: the assertion
      moved with the thing it was checking, so it could not fail. An
      expectation must be independent of what it is testing or it is only
      restating it. Same for the forced extent below. }
    SpawnsAt(Tx, Ty);
    Slot := S[Idx].EntitySlot;
    Want(Pool.Alive[Slot], 'the spawned slot is not alive');
    Want(Pool.PosX(Slot) = Tx * 32 * 32 + 512,
         Format('spawned at x=%d, want %d',
                [Pool.PosX(Slot), Tx * 32 * 32 + 512]));
    Want(Pool.PosY(Slot) = Ty * 32 * 32 + 512,
         Format('spawned at y=%d, want %d',
                [Pool.PosY(Slot), Ty * 32 * 32 + 512]));
    Want(Pool.Field(Slot, EF_EVENT_ID) = Idx,
         'the entity does not remember its event');

    { A second sweep must not duplicate any in-window entity. Check both the
      total live count and this record's retained slot. }
    Live := Pool.LiveCount;
    R.SpawnNearCamera(S, Pool, L, Tx, Ty, P, GS);
    Want(Pool.LiveCount = Live,
         Format('a second sweep took the pool from %d entities to %d',
                [Live, Pool.LiveCount]));
    Want(S[Idx].EntitySlot = Slot, 'a second sweep moved the entity');

    { Walk the camera away. The record still holds its entity, so the in-window
      mark must STAY - clearing it is what would let it spawn again. }
    R.SpawnNearCamera(S, Pool, L, Tx + 40, Ty, P, GS);
    Want(S[Idx].InWindow,
         'leaving the window cleared the mark while the entity was still out');

    { And now the case the two marks exist to tell apart. Kill the entity
      without moving the camera, exactly as Entity_Destroy would: the
      has-entity mark goes down but the in-window mark stays up, and the sweep
      must NOT place a replacement. Dropping the in-window test entirely
      survived every other check here, because a record that spawns
      successfully is left holding an entity anyway - this is the only state
      in which the two differ. }
    S.SetActive(Idx, False);
    Pool.Kill(Slot);
    Live := Pool.LiveCount;
    R.SpawnNearCamera(S, Pool, L, Tx, Ty, P, GS);
    Want(not S[Idx].Active,
         'an entity that died inside the window was replaced at once');
    Want(Pool.LiveCount = Live,
         Format('the sweep after a death took the pool from %d to %d',
                [Live, Pool.LiveCount]));

    { Leave the window with no entity and the mark clears, so it can come
      back next time. That is the other half of the same pair. }
    R.SpawnNearCamera(S, Pool, L, Tx + 40, Ty, P, GS);
    Want(not S[Idx].InWindow,
         'leaving the window with no entity did not clear the mark');
    R.SpawnNearCamera(S, Pool, L, Tx, Ty, P, GS);
    Want(S[Idx].Active, 'the record never came back after leaving the window');

    { --- the forbidding flag retires the record for good --------------- }
    S.Load(GameDir, 2);
    Pool.Clear;
    FreshPlayer(P);
    Idx := -1;
    for I := 0 to S.Count - 1 do
      if (S[I].BlockedBy <> 0) and (S[I].NeedsFlag = 0) then
        Idx := I;
    if Idx < 0 then
      Log.Add('  FAILED: stage 2 has no record with a forbidding flag')
    else
    begin
      Tx := S[Idx].TileX;
      Ty := S[Idx].TileY;
      GS := GS_PLAY;
      R.SpawnNearCamera(S, Pool, L, Tx, Ty, P, GS);
      Want(S[Idx].Active, 'a record with its flag clear did not spawn');
      Slot := S[Idx].EntitySlot;

      P.Progress[S[Idx].BlockedBy] := 1;
      R.SpawnNearCamera(S, Pool, L, Tx, Ty, P, GS);
      Want(S[Idx].Opcode = EVOP_DISABLED,
           'the forbidding flag did not disable the record');
      Want(S[Idx].TileX = EVENT_DISABLED_TILE,
           'the disabled record was not moved off the map');
      Want(not Pool.Alive[Slot], 'the disabled record kept its entity');
    end;

    { --- opcode 4 ignores the window entirely -------------------------- }
    S.Load(GameDir, 14);
    Pool.Clear;
    FreshPlayer(P);
    Idx := FindChecker(S);
    if Idx < 0 then
      Log.Add('  FAILED: stage 14 has no opcode-4 checker')
    else
    begin
      GS := GS_PLAY;
      { A camera nowhere near tile (1,1), where all nine checkers sit. }
      R.SpawnNearCamera(S, Pool, L, 90, 90, P, GS);
      Want(S[Idx].Active, 'an opcode-4 checker did not spawn out of the window');
      Want(GS = GS_STATE_140,
           'an opcode-4 checker was placed but its script did not start');
      Want(Pool.Field(S[Idx].EntitySlot, EF_EXTENT_X) = 32,
           Format('type 20 got extent x %d, want a whole tile',
                  [Pool.Field(S[Idx].EntitySlot, EF_EXTENT_X)]));
      Want(Pool.Field(S[Idx].EntitySlot, EF_EXTENT_Y) = 32,
           Format('type 20 got extent y %d, want a whole tile',
                  [Pool.Field(S[Idx].EntitySlot, EF_EXTENT_Y)]));
    end;
  finally
    Pool.Free;
    R.Free;
    S.Free;
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - both window edges, the placement, the duplicate guard '
      + 'and the retirement path');
end;

{ --- 8. ParamA's letter decides what the placement carries --------------- }

function TestSpawnArgs(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  Pool: TEntityPool;
  P: TPlayerState;
  L: TLayerInfo;
  Sp: TEventSpawn;
  GS, I, J, Idx, Slot, Seen, Bad: Integer;
  Letters: string;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Seen := 0;
  Letters := '';
  Log.Add('ParamA, applied on spawn:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  Pool := TEntityPool.Create;
  try
    FillChar(L, SizeOf(L), 0);
    L.TileW := 32; L.TileH := 32;
    L.MapTilesX := 128; L.MapTilesY := 128;
    L.OriginX := POSITION_BIAS; L.OriginY := POSITION_BIAS;

    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for J := 0 to S.Count - 1 do
      begin
        Sp := ParseSpawn(S[J].ParamA);
        if (not Sp.Valid) or (Sp.Kind = '*') or (Sp.Kind = '/') then
          Continue;
        if Pos(Sp.Kind, Letters) = 0 then
          Letters := Letters + Sp.Kind;

        { RELOAD, do not merely clear the pool. The in-window and has-entity
          marks live in the script, not the pool, so a script left over from
          the previous record's sweep reports every nearby record as already
          placed - and the test then reads a stale slot out of a pool that has
          just been emptied. That read 0 for every field and looked exactly
          like ApplySpawnArgs doing nothing at all. }
        S.Load(GameDir, I);
        Pool.Clear;
        FreshPlayer(P);
        GS := GS_PLAY;
        Idx := J;
        R.SpawnNearCamera(S, Pool, L, S[J].TileX, S[J].TileY, P, GS);
        if not S[Idx].Active then
          Continue;          { a flag condition kept it out; not this test }
        Slot := S[Idx].EntitySlot;
        Inc(Seen);

        case Sp.Kind of
          'A':
            Want(Pool.Field(Slot, EF_VARIANT) = Sp.Args[0],
                 Format('stage %d event %d: A gave variant %d, want %d',
                        [I, J, Pool.Field(Slot, EF_VARIANT), Sp.Args[0]]));
          'M':
            begin
              Want(Pool.Field(Slot, EF_STATE) = Sp.Args[0],
                   Format('stage %d event %d: M state %d, want %d',
                          [I, J, Pool.Field(Slot, EF_STATE), Sp.Args[0]]));
              { The heading is given in eighths of the 64-step turn. }
              Want(Pool.Field(Slot, EF_FACING) = Sp.Args[2] * 8,
                   Format('stage %d event %d: M facing %d, want %d',
                          [I, J, Pool.Field(Slot, EF_FACING), Sp.Args[2] * 8]));
            end;
          'R':
            Want(Pool.Field(Slot, EF_FACING) = Sp.Args[0],
                 Format('stage %d event %d: R facing %d, want %d',
                        [I, J, Pool.Field(Slot, EF_FACING), Sp.Args[0]]));
          'J':
            { A nudge in whole pixels off the tile centre. }
            Want(Pool.PosX(Slot)
                   = S[Idx].TileX * 32 * 32 + SPAWN_TILE_CENTRE + Sp.Args[0] * 32,
                 Format('stage %d event %d: J x %d, want %d',
                        [I, J, Pool.PosX(Slot),
                         S[Idx].TileX * 32 * 32 + SPAWN_TILE_CENTRE
                         + Sp.Args[0] * 32]));
        end;
      end;
    end;

    { The gated form separately, because it needs a flag set to do anything at
      all - and the point of it is that one placement covers a before and an
      after. }
    S.Load(GameDir, 0);
    Idx := -1;
    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for J := 0 to S.Count - 1 do
      begin
        Sp := ParseSpawn(S[J].ParamA);
        if Sp.Valid and (Sp.Kind = '/') and (S[J].NeedsFlag = 0)
           and (S[J].BlockedBy = 0) then
        begin
          Idx := J;
          Break;
        end;
      end;
      if Idx >= 0 then
        Break;
    end;
    if Idx < 0 then
      Log.Add('  FAILED: no unconditional gated placement anywhere')
    else
    begin
      Sp := ParseSpawn(S[Idx].ParamA);

      Pool.Clear;
      FreshPlayer(P);
      GS := GS_PLAY;
      R.SpawnNearCamera(S, Pool, L, S[Idx].TileX, S[Idx].TileY, P, GS);
      Slot := S[Idx].EntitySlot;
      Want(Pool.Field(Slot, EF_STATE) = 0,
           'the gated form applied its state with the flag clear');

      S.Load(GameDir, I);
      Pool.Clear;
      FreshPlayer(P);
      P.Progress[Sp.Args[0]] := 1;
      GS := GS_PLAY;
      R.SpawnNearCamera(S, Pool, L, S[Idx].TileX, S[Idx].TileY, P, GS);
      Slot := S[Idx].EntitySlot;
      Want(Pool.Field(Slot, EF_STATE) = Sp.Args[1],
           Format('the gated form gave state %d with flag %d set, want %d',
                  [Pool.Field(Slot, EF_STATE), Sp.Args[0], Sp.Args[1]]));
    end;
  finally
    Pool.Free;
    R.Free;
    S.Free;
  end;

  Log.Add(Format('placements checked: %d, kinds %s', [Seen, Letters]));
  if Seen < 200 then
  begin
    Log.Add(Format('  FAILED: only %d placements reached, want at least 200',
      [Seen]));
    Inc(Bad);
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - every letter puts its fields where the interpreter reads them');
end;

function SelfTestRunner(Log: TStrings): Integer;
var
  GameDir: string;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');

  Inc(Result, TestSavePoint(Log, GameDir));      Log.Add('');
  Inc(Result, TestEventBegin(Log, GameDir));     Log.Add('');
  Inc(Result, TestBackwardsScan(Log, GameDir));  Log.Add('');
  Inc(Result, TestWaiting(Log, GameDir));        Log.Add('');
  Inc(Result, TestFlagList(Log, GameDir));       Log.Add('');
  Inc(Result, TestSpawnWindow(Log, GameDir));    Log.Add('');
  Inc(Result, TestSpawnArgs(Log, GameDir));      Log.Add('');
  Inc(Result, TestEveryProgram(Log, GameDir));

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - the interpreter steps, branches, waits and spawns as read')
  else
    Log.Add('FAILED');
end;

end.
