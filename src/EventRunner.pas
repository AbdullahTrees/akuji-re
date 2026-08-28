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

    { 0x00454790. Walked every frame: spawns what has come near the camera,
      retires what a flag has closed off, and starts opcode-4 events outright.
      The camera tile is passed in rather than read from the tilemap object,
      because that is the one thing here the original reaches for through a
      component this reconstruction does not have. }
    procedure SpawnNearCamera(Events: TEventScript; Pool: TEntityPool;
                              const L: TLayerInfo;
                              CamTileX, CamTileY: Integer;
                              var P: TPlayerState; var AGameState: Integer);
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
      begin
        Host.SoulGet;
        AdvanceStep(P, AGameState);
      end;

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
                                       var AGameState: Integer);
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
      if Rec.Active then
        Pool.Kill(Rec.EntitySlot);
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