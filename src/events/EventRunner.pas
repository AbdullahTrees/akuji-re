{ Event-script execution. EventScripts loads stage records and EventCommands
  parses their mini-language. A record's ParamB is split on '/' into steps and
  hands the first to AdvanceStep. Each step is split on '.' into ALTERNATIVES,
  and exactly one runs - the LAST one whose guard flag is set, because the scan
  goes backwards. That is why a `0000-` alternative is written first: flag 0 is
  always set, so it is the default the scan reaches last.

  While a script runs the game sits in GS_STATE_140 rather than GS_PLAY, and
  Event_Begin refuses to start a second one while it is there. Running off the
  end of the steps puts the game back into GS_PLAY.

  Progress[1..4] are per-event scratch flags cleared when a script starts.
  Dialogue answers use flags 3 (yes) and 4 (no). }

unit EventRunner;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Classes, PlayerState, GameState, EventScripts, EventCommands,
  Entities;

type
  { Presentation and world operations supplied by the game session. A no-op
    host remains valid for logic-only execution. }
  TEventHost = class
  public
    { sub-op 3 - a line from the stage's tk file }
    procedure ShowLine(Index: Integer); virtual;
    { Whether a dialogue box is already active. }
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

  { Interpreter state. The step index is seeded to -1, so the first increment lands
    on 0. There is deliberately NO wait flag here: the interpreter waits on
    GameState.ScreenPhase, the same global the pause menu, the game-over
    screen, the ending and the message box step through, and AdvanceStep
    clears it as its first statement. A private copy would leave every other
    screen reading the other one. }
  TEventRunner = class
  public
    Steps: array of string;
    StepIndex: Integer;
    EventId: Integer;
    Arg: Integer;
    Cursor: Integer;

    { Start a script unless another one is already running. }
    procedure TickDelay(Events: TEventScript; var P: TPlayerState;
                        var AGameState: Integer);
    procedure StartEvent(Events: TEventScript; AEventId, AArg: Integer;
                         var P: TPlayerState; var AGameState: Integer);

    { Move to the next step and select its alternative. Running off the end
      returns the game to GS_PLAY. }
    procedure AdvanceStep(var P: TPlayerState; var AGameState: Integer);

    { Execute one frame of the current step. Most sub-opcodes advance
      immediately; fades, dialogue, waits, and the ending span frames. }
    procedure Execute(Host: TEventHost; Events: TEventScript;
                      var P: TPlayerState; var AGameState: Integer);

    { The alternative chosen for the current step, or '' when none was. }
    function CurrentStep: string;
    function Finished: Boolean;

    { The sub-opcode of the current step, or -1 when there is none. }
    function CurrentSubOp: Integer;

    { Walked every frame: spawns what has come near the camera,
      retires what a flag has closed off, and starts opcode-4 events outright.
      The camera tile is supplied by the session because the event runner does
      not own the display-layer origin. }
    { World is optional for logic-only callers; without it the disable path can
      retire the event but cannot destroy its entity. }
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
    matching Camera.pas's viewport dimensions. }
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

{ Parse the four-character progress-flag guard at the start of an alternative. }
function AlternativeFlag(const Alt: string): Integer;

{ Fixed columns used by the music sub-opcode. }
const
  MUSIC_STORE_COLUMN = 15;
  MUSIC_STORE_YES    = '1';
  MUSIC_LOOP_COLUMN  = 13;
  MUSIC_LOOP_ONCE    = '0';

{ One character at a fixed column - see the implementation. }
function StepChar(const Step: string; Position: Integer): Char;

implementation

{ Every argument occupies a fixed position, so shipped values are zero-padded.
  EventCommands is the single source for those positions. }
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

{ Read one character from a fixed one-based column. Music flags are not parsed
  as dash-separated fields. }
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
  { Shipped alternatives use a zero-padded four-digit guard. Malformed input
    is rejected instead of raising a conversion exception. }
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
  { Clear the shared sub-phase because the message box's \k and \w arms both
    open with `if ScreenPhase = 0 then` one-shots
    that reset their animation, and the game-over screen and the ending step
    through the same counter. Starting a script without clearing it leaves
    whatever the last screen left behind. }
  ScreenPhase := 0;

  AdvanceStep(P, AGameState);
end;

{ Arg is a frame delay. When it expires, every opcode-4 event may run again.
  SpawnNearCamera starts each puzzle
  checker with Event_Begin(i, 4), so a checker re-runs four frames later - which
  is how a puzzle that is not yet solved keeps testing itself.

  Re-entry is safe because StartEvent permits only one active script. }
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

    { Scan backwards. The last alternative whose flag is set wins, so the
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
      { Raise the dialogue once, guarded by message state rather than
        ScreenPhase. Execute runs every frame in state 140,
        and the message box's own \k page turn clears ScreenPhase, so a guard
        on that re-raises page 1 forever and the rest of the message is
        unreachable. The box decides when it is done and calls AdvanceStep. }
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
        { Columns 15 and 13 select whether the track is remembered and whether
          playback loops:

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
        argument. A count that comes back 0 makes the test pass VACUOUSLY and
        set flag 0, which is already 1 - so a failure here is silent. }
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
      { Do not advance: this opcode takes over the script. Because the step
        index never moves, Execute re-enters this arm every
        frame in GS_STATE_140, and Host.SoulGet walks itself through three
        phases into GS_ENDING. There is nothing to advance TO. Advance here and
        SoulGet runs phase 0 once - fanfare, orb destroyed - and is never called
        again: no fade, no credits, and the game just carries on. }
      Host.SoulGet;

    SUBOP_NOP:
      AdvanceStep(P, AGameState);

  else
    { Unknown sub-opcodes neither advance nor raise; shipped scripts contain
      none. }
    ;
  end;
end;

{ ParamA's kind letter selects its fields. SpawnArgPosition centralizes their
  fixed-column locations. }
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
    { Shipped placements use only the six kinds above; ignore unknown kinds. }
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
      { ENTITY_DESTROY, NOT Kill. Kill clears EF_ALIVE and nothing else, so
        the sprite stays in the pool still visible - and Entity_UpdateAll
        skips dead entities, so it is never repositioned again and sits at
        the SCREEN coordinates it last had, appearing to follow the player
        around the room. This branch fires the moment a door is unlocked. }
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
