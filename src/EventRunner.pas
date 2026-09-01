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

  ## Progress[1..4] are SCRATCH, and Progress[3] is the dialogue answer

  Event_Begin clears exactly those four bytes every time a script starts. They
  are an event's local variables: no shipped record SETS one, and clearing them
  on entry is what stops one event seeing the last one's.

  What they are FOR is legible in the data, and this once read "nothing in the
  692 records reads or writes them", which was wrong. 86 alternatives guard on
  a scratch flag, and all 86 guard on flag 3 specifically. Every one of them
  has a dialogue step earlier in its own program whose line ends in \w - the
  yes/no prompt. So Progress[3] is where the player's ANSWER goes, and a
  guarded step is the yes branch. The Devil Statue is the whole idea in one
  record, identical in all 43 stages that have one:

      0000-03-0000/0003-13/0003-03-0001

  ask, save if yes, say so if yes. --selftest-runner drives it both ways.

  Flags 1 and 2 really are untouched by the shipped data. What writes them is
  sub-op 6, which no event uses - a cut comparison feature whose plumbing is
  all still here. Flag 4 is written by nothing at all. }

unit EventRunner;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Classes, PlayerState, GameState, EventScripts, EventCommands,
  Entities;

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
    { Is a message box already up? 0x00455210's sub-op 3 guards on the MESSAGE
      MODE at 0x0046CF28, not on ScreenPhase - see the arm below. }
    function MessageBusy: Boolean; virtual;
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
        0x0046CE7C  which event            0x0046D028  the delay it began with
        0x0046D218  the cursor within a step
        0x0046D334  the STEP INDEX. EventScript_AdvanceStep increments it and
                    compares it against DynArrayHigh(steps), and Event_Begin
                    seeds it to -1 so the first increment lands on 0. It was
                    recorded as "the save slot cursor", which it is not.
        0x0046CC14  ScreenPhase - the SAME global the pause menu, the game-over
                    screen, the ending and the message box step through. This
                    unit kept a separate `Waiting` field for it, so a step
                    boundary cleared one copy and every other screen read the
                    other. AdvanceStep clears it as its FIRST statement. }
  TEventRunner = class
  public
    Steps: array of string;
    StepIndex: Integer;
    EventId: Integer;
    Arg: Integer;
    Cursor: Integer;

    { 0x00454EF4. Starts the script on an event record, unless one is already
      running - the guard is the game state itself, not a flag. }
    procedure TickDelay(Events: TEventScript; var P: TPlayerState;
                        var AGameState: Integer);
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

    { 0x00454790. Walked every frame: spawns what has come near the camera,
      retires what a flag has closed off, and starts opcode-4 events outright.
      The camera tile is passed in rather than read from the tilemap object,
      because that is the one thing here the original reaches for through a
      component this reconstruction does not have. }
    { World is optional only so the older tests need not all be rewritten; the
      game always passes it, and without it the disable path can only kill. }
    procedure SpawnNearCamera(Events: TEventScript; Pool: TEntityPool;
                              const L: TLayerInfo;
                              CamTileX, CamTileY: Integer;
                              var P: TPlayerState; var AGameState: Integer;
                              World: TEntityWorld = nil);
  end;

const
  { The spawn window, in tiles around the camera's top-left. The screen is
    10 x 7.5 tiles and the margin is 2 on every side, so the tests are
        CamTile - 2  <  tile  <  CamTile + 12      (10 + 2)
        CamTile - 2  <  tile  <  CamTile + 9.5     (7.5 + 2)
    which is where Camera.pas's VIEW_TILES_* came from in the first place -
    the two functions agree without either having been written from the
    other. The vertical bound is fractional in the original and is kept so. }
  SPAWN_WINDOW_X = 12;
  SPAWN_WINDOW_Y = 9.5;

  { An entity is dropped in the MIDDLE of its tile: half a tile, in 1/32 px. }
  SPAWN_TILE_CENTRE = $200;
  EVENT_BEGIN_FROM_SPAWN = 4;

  { Type 20 gets its extent forced to a whole tile on spawn. It is one of the
    three types with no sprite, so it has no art to take a size from - and
    with no extent it would have no hitbox either. }
  SPAWN_FORCED_EXTENT_TYPE = 20;
  SPAWN_FORCED_EXTENT = 32;

{ The guard on an alternative: its first four characters are a progress flag
  index. Exposed because both AdvanceStep and the tests want it, and because
  StrToInt on a malformed one would raise where the original would not. }
function AlternativeFlag(const Alt: string): Integer;

{ The music sub-op's two flag columns and the literals they are compared
  against, from 0x004559F1 and 0x00455A5E. }
const
  MUSIC_STORE_COLUMN = 15;
  MUSIC_STORE_YES    = '1';
  MUSIC_LOOP_COLUMN  = 13;
  MUSIC_LOOP_ONCE    = '0';

{ One character at a fixed column - see the implementation. }
function StepChar(const Step: string; Position: Integer): Char;

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

{ One character at a FIXED COLUMN, which is how the original reads the two
  music flags - Copy(Step, 13, 1) and Copy(Step, 15, 1), not a dash-separated
  field. Positions are 1-based, as Copy's are. }
function StepChar(const Step: string; Position: Integer): Char;
begin
  if (Position >= 1) and (Position <= Length(Step)) then
    Result := Step[Position]
  else
    Result := #0;
end;

procedure TEventHost.ShowLine(Index: Integer); begin end;
function TEventHost.MessageBusy: Boolean; begin Result := False; end;
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
  AGameState := GS_STATE_140;
  { 0x00454EF4 clears the shared sub-phase here, and it has to: the message
    box's \k and \w arms both open with `if ScreenPhase = 0 then` one-shots
    that reset their animation, and the game-over screen and the ending step
    through the same counter. Starting a script without clearing it leaves
    whatever the last screen left behind. }
  ScreenPhase := 0;

  AdvanceStep(P, AGameState);
end;

{ The delay 0x0046D028 holds, counted down once a frame by 0x00464D30:

      if ((d028 != 0) && (--d028 == 0) && (DynArrayHigh(EventTable) >= 0))
          for i := 0 to high:
              if (EventTable[i].opcode == 4) Event_Begin(i, 0);

  So the argument Event_Begin is called with is a DELAY, and when it runs out
  every opcode-4 event fires again. Events_SpawnNearCamera starts each puzzle
  checker with Event_Begin(i, 4), so a checker re-runs four frames later - which
  is how a puzzle that is not yet solved keeps testing itself.

  Arg was being STORED and never counted, and the field comment above already
  said what it was for. Re-entry is safe because StartEvent refuses while the
  state is 140, exactly as Event_Begin's own guard does, so at most one of them
  takes. }
procedure TEventRunner.TickDelay(Events: TEventScript; var P: TPlayerState;
                                 var AGameState: Integer);
var
  I: Integer;
begin
  if Arg = 0 then
    Exit;
  Dec(Arg);
  if (Arg <> 0) or (Events = nil) then
    Exit;
  for I := 0 to Events.Count - 1 do
    if Events[I].Opcode = EVOP_ALWAYS then
      StartEvent(Events, I, 0, P, AGameState);
end;

procedure TEventRunner.AdvanceStep(var P: TPlayerState;
                                   var AGameState: Integer);
var
  List: TStringList;
  I, Flag: Integer;
begin
  ScreenPhase := 0;
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
  Op, I, Flag, Want, Count, Start: Integer;
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
        ScreenPhase is the little state machine that spans those frames. }
      begin
        if ScreenPhase = 0 then
        begin
          ScreenPhase := 1;
          Host.StartFade(True);
        end;
        if (ScreenPhase = 1) and (not Host.FadeBusy) then
        begin
          Host.StartFade(False);
          Host.LoadStage(StepArg(Step, Op, 0), StepArg(Step, Op, 1),
                         StepArg(Step, Op, 2), StepArg(Step, Op, 3),
                         StepArg(Step, Op, 4));
          AGameState := GS_STAGE_BEGIN;
          ScreenPhase := 0;
        end;
      end;

    1:
      { The same fade, then a warp within the stage rather than a load. }
      begin
        if ScreenPhase = 0 then
        begin
          ScreenPhase := 1;
          Host.StartFade(True);
        end;
        if (ScreenPhase = 1) and (not Host.FadeBusy) then
        begin
          Host.StartFade(False);
          Host.WarpPlayer(StepArg(Step, Op, 0), StepArg(Step, Op, 1),
                          StepArg(Step, Op, 2), StepArg(Step, Op, 3));
          AGameState := GS_PLAY;
          ScreenPhase := 0;
        end;
      end;

    SUBOP_DIALOGUE:
      { RAISE IT ONCE, and the guard is the MESSAGE MODE - not ScreenPhase.
        0x00455210's arm is

            case 3:
              if (*PTR_DAT_0046cf28 == 0)          <- the message mode
                  *PTR_DAT_0046cf28 = 1;
                  *PTR_DAT_0046cc98 = 1;           page start
                  *PTR_DAT_0046cf24 = 1;           reveal cursor
                  ...set the text...

        This used ScreenPhase as its one-shot, and ScreenPhase is shared with
        the pause menu, the game-over screen and - fatally - the message box's
        own \k page turn, which clears it exactly as the original does. So
        turning a page re-armed the guard, and EventScript_Execute runs EVERY
        FRAME in state 140: page 1 was re-raised forever and the rest of the
        message was unreachable. Reported on tk013's two-page 'Your Fire has
        increased!'.

        The box itself decides when it is done and calls AdvanceStep. }
      if not Host.MessageBusy then
        Host.ShowLine(StepArg(Step, Op, 0));

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
        { The two flags, at columns 15 and 13, compared against the one-
          character literals at 0x00456000 and 0x0045600C - which are '1' and
          '0'. This used to pass True unconditionally and ignore both, with a
          comment describing what it was not doing.

              column 15 = '1'   also store the track as the stage's music
              column 13 = '0'   play it ONCE; anything else loops }
        if StepChar(Step, MUSIC_STORE_COLUMN) = MUSIC_STORE_YES then
          P.MusicTrack := StepArg(Step, Op, 0);
        Host.PlayMusic(StepArg(Step, Op, 0),
                       StepChar(Step, MUSIC_LOOP_COLUMN) <> MUSIC_LOOP_ONCE);
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
      { arg 1 is a count and that many items follow, six characters apart:
        one character saying whether the flag must be SET or CLEAR, then four
        digits of flag index. Every one must match for arg 0's flag to be set.

        This is the whole of the nine puzzle checkers - hit the switches, the
        door opens - and the '0' form is a switch that must be left alone.

        The two leading fields go through ArgPosition like every other
        argument. That was not true when this was first written: ArgPosition
        returned False for sub-op 15, so the count came back 0, the loop never
        ran, and the test vacuously passed - it set flag 0, which is already 1
        and always will be. Nothing observable happened, which is exactly the
        kind of defect a test that only checks "no crash" cannot see. }
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
      { NO AdvanceStep - and that is the whole point of this opcode.

        Sub-op 0x50 in EventScript_Execute @ 0x00455210 spans
        0x00455E5A..0x00455FC6 and contains no call to EventScript_AdvanceStep
        @ 0x0045509C. Ghidra's xrefs to that address list every call site in
        the function - 00455246, 004557DC, 0045581E, 00455889, 004558E0,
        00455917, 00455964, 004559BF, 00455B00, 00455BEC, 00455C8E, 00455DA5,
        00455E04, 00455E50, 00455FC8 - and the two nearest bracket the arm
        without entering it: 00455E50 is before it and 00455FC8 belongs to
        sub-op 99.

        Every other opcode hands the script on. This one TAKES OVER. Because
        the step index never moves, the arm is re-entered every frame while
        the state is GS_STATE_140 - GameSession.TickScript calls Execute
        unconditionally in that state - and it walks itself through three
        phases, ending in GS_ENDING rather than in the script at all. Nothing
        is left to advance to.

        Host.SoulGet holds those phases (TDialogueBox.SoulGet), in the
        original's 1-0-2 test order.

        THE BUG THIS FIXES: an AdvanceStep used to sit here, so the script
        moved on during the very first frame. SoulGet ran phase 0 - sound
        0x10, playlist entry 11 not looping, and the orb destroyed - and was
        then never called again. Phases 1 and 2 never ran, so there was no
        fade-out, no GS_ENDING and no credits; the fanfare played, the orb
        vanished, and the game carried on as normal. }
      Host.SoulGet;

    SUBOP_NOP:
      AdvanceStep(P, AGameState);

  else
    { An unknown sub-opcode does nothing at all in the original - no advance,
      no error - which hangs the script where it stands. Reproduced rather than
      recovered from: inventing a recovery would hide data that should never
      occur, and no shipped program contains one. --selftest-runner drives
      every shipped program to completion, which is what says so. }
    ;
  end;
end;

{ ParamA's letter decides which fields the placement carries, and where each
  one sits. The positions come from EventCommands.SpawnArgPosition, which was
  read out of this same function - so this applies them rather than restating
  them. }
procedure ApplySpawnArgs(Pool: TEntityPool; Slot: Integer;
                         const ParamA: string; var P: TPlayerState);
var
  Kind: Char;
  Start, Len, A0, A1, A2: Integer;

  function Arg(Index: Integer): Integer;
  begin
    Result := 0;
    if not SpawnArgPosition(Kind, Index, Start, Len) then
      Exit;
    if not TryStrToInt(Trim(Copy(ParamA, Start, Len)), Result) then
      Result := 0;
  end;

begin
  if Length(ParamA) < 6 then
    Exit;
  Kind := ParamA[6];

  case Kind of
    '*': ;    { carries nothing at all - 379 of the shipped placements }

    '/':
      begin
        { Gated: the state is only applied when a progress flag is already
          set, which is how one placement covers a before and an after. }
        A0 := Arg(0);
        A1 := Arg(1);
        if (A0 >= 0) and (A0 < PROGRESS_LENGTH) and (P.Progress[A0] = 1) then
          Pool.SetField(Slot, EF_STATE, A1);
      end;

    'A':
      Pool.SetField(Slot, EF_VARIANT, Arg(0));

    'M':
      begin
        A0 := Arg(0);
        A1 := Arg(1);
        A2 := Arg(2);
        Pool.SetField(Slot, EF_STATE, A0);
        Pool.SetField(Slot, EF_BLOCK_A + 1, A1);
        { The heading is given in eighths of the 64-step turn. }
        Pool.SetField(Slot, EF_FACING, A2 shl 3);
      end;

    'R':
      begin
        A0 := Arg(0);
        A1 := Arg(1);
        Pool.SetField(Slot, EF_FACING, A0);
        Pool.SetField(Slot, EF_BLOCK_A + 1, A1);
      end;

    'J':
      begin
        { A nudge, in whole pixels off the tile centre. }
        A0 := Arg(0);
        A1 := Arg(1);
        Pool.SetField(Slot, EF_POS_X, Pool.Field(Slot, EF_POS_X) + A0 * 32);
        Pool.SetField(Slot, EF_POS_Y, Pool.Field(Slot, EF_POS_Y) + A1 * 32);
      end;

  else
    { The original has a seventh form here, reading seven fields at 6, 11, 16, 21,
      26, 31 and 36 - variant, both extents and all four box percentages. No
      shipped placement reaches it: every one of the 692 records carries one of
      the six letters above. Left unimplemented deliberately, and this comment
      is the record of why rather than an oversight. }
    ;
  end;
end;

procedure TEventRunner.SpawnNearCamera(Events: TEventScript; Pool: TEntityPool;
                                       const L: TLayerInfo;
                                       CamTileX, CamTileY: Integer;
                                       var P: TPlayerState;
                                       var AGameState: Integer;
                                       World: TEntityWorld = nil);
var
  I, Slot, TypeId, CamPxX, CamPxY: Integer;
  Rec: TEventRecord;
  InWindow: Boolean;
begin
  if (Pool = nil) or (Events = nil) or (L.TileW = 0) or (L.TileH = 0) then
    Exit;

  CamPxX := PixelOf(L.OriginX);
  CamPxY := PixelOf(L.OriginY);

  for I := 0 to Events.Count - 1 do
  begin
    Rec := Events[I];

    { Opcode 4 ignores the window entirely - the puzzle checkers are always
      live, which is why they can sit at tile (1, 1) and still work. }
    InWindow := ((CamTileX - SPAWN_MARGIN_TILES < Rec.TileX)
                 and (Rec.TileX < CamTileX + SPAWN_WINDOW_X)
                 and (CamTileY - SPAWN_MARGIN_TILES < Rec.TileY)
                 and (Rec.TileY < CamTileY + SPAWN_WINDOW_Y))
                or (Rec.Opcode = EVOP_ALWAYS);

    if not InWindow then
    begin
      { Out of range and holding no entity: clear the in-window mark so it can
        spawn again next time round. If it still has an entity the mark stays,
        which is what stops it spawning a second one. }
      if not Rec.Active then
        Events.SetInWindow(I, False);
      Continue;
    end;

    { The required flag. }
    if (Rec.NeedsFlag <> 0)
       and ((Rec.NeedsFlag >= PROGRESS_LENGTH) or (P.Progress[Rec.NeedsFlag] = 0)) then
      Continue;

    { The forbidding flag - and this is the "gone for good" path, not a skip. }
    if (Rec.BlockedBy <> 0) and (Rec.BlockedBy < PROGRESS_LENGTH)
       and (P.Progress[Rec.BlockedBy] = 1) then
    begin
      Events.Disable(I);
      { ENTITY_DESTROY, NOT A KILL. The original's disable branch ends

            if (*(char *)(tbl + 5 + i*0x24) == 1)
                Entity_Destroy(pool + slot * 0x104, 0);

        and the difference is the whole bug: Kill clears EF_ALIVE and nothing
        else, so the sprite stays in the pool, still visible. Entity_UpdateAll
        skips dead entities, so that sprite is never repositioned again - it
        stays at the SCREEN coordinates it last had and appears to follow the
        player around the room. Reported for a door that had just been
        unlocked, which is exactly when this branch fires: the door's
        BlockedBy flag goes up and the event is disabled forever.

        The same distinction left the power-up orb on screen. }
      if Rec.Active then
      begin
        if World <> nil then
          World.DestroyEntity(Pool.Entity(Rec.EntitySlot)^, False)
        else
          Pool.Kill(Rec.EntitySlot);
      end;
      Continue;
    end;

    { Already marked, or already holding an entity: nothing to do. }
    if Rec.InWindow or Rec.Active then
      Continue;

    TypeId := 0;
    if Length(Rec.ParamA) >= 4 then
      if not TryStrToInt(Copy(Rec.ParamA, 1, 4), TypeId) then
        TypeId := 0;

    Slot := Pool.Spawn(EKIND_MINOR, TypeId,
                       (Rec.TileX * L.TileW - CamPxX) * 32 + SPAWN_TILE_CENTRE,
                       (Rec.TileY * L.TileH - CamPxY) * 32 + SPAWN_TILE_CENTRE);
    if Slot = SLOT_NONE then
      Continue;

    Events.SetInWindow(I, True);
    Events.SetEntity(I, Slot);

    { A type with no sprite has no art to size itself from, so it is given a
      whole tile. }
    if Pool.Field(Slot, EF_TYPE) = SPAWN_FORCED_EXTENT_TYPE then
    begin
      Pool.SetField(Slot, EF_EXTENT_X, SPAWN_FORCED_EXTENT);
      Pool.SetField(Slot, EF_EXTENT_Y, SPAWN_FORCED_EXTENT);
    end;

    { The entity remembers which record placed it - this is what lets
      Entity_Destroy and the touch handlers find their event again. }
    Pool.SetField(Slot, EF_EVENT_ID, I);

    ApplySpawnArgs(Pool, Slot, Rec.ParamA, P);

    { A puzzle checker runs the moment it is placed. }
    if Rec.Opcode = EVOP_ALWAYS then
      StartEvent(Events, I, EVENT_BEGIN_FROM_SPAWN, P, AGameState);
  end;
end;

end.