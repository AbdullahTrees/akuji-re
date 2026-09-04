{ Owns one running game's entity pool, player state, camera, event state, and
  script runner. Rendering and audio are borrowed services and may be absent
  for logic-only execution. The player occupies slot 0 and is updated by the
  normal entity dispatcher. }

unit GameSession;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Entities, EntityHandlers, Player, Camera, PlayerState,
  GameState, Stages, TileMaps, EventScripts, EventCommands, EventRunner,
  Sprites, SpritePool, BgAnime;

type
  { A TTileSource over a loaded map. A session with no map reports empty
    terrain everywhere. }
  TMapTileSource = class(TTileSource)
  public
    Map: TTileMap;
    function TileAt(TileX, TileY: Integer): Integer; override;
  end;

  TSessionNotify = procedure of object;

  TGameSession = class;

  { Connects entity-handler services to the owning session. }
  TGameWorld = class(TEntityWorld)
  private
    FSession: TGameSession;
  public
    constructor Create(ASession: TGameSession);
    function Spawn(Kind, TypeId, X, Y: Integer): Integer; override;
    procedure SetSpawnField(Slot, IntIndex, Value: Integer); override;
    procedure PlaySound(Id: Integer); override;
    procedure StopMusic; override;

    { The event system, which Entity_Destroy and the touch handlers reach
      through the world rather than directly. }
    function EventOpcode(EventId: Integer): Integer; override;
    function EventProgressIndex(EventId: Integer): Integer; override;
    procedure BeginEvent(EventId, Arg: Integer); override;
    procedure ClearEventEntity(EventId: Integer); override;
    procedure SetProgress(Index: Integer); override;
    procedure SetEventOpcode(EventId, Opcode: Integer); override;
    function PlayerDifficulty: Integer; override;

    { The input the push-against opcodes test. }
    function AxisX: Integer; override;
    function AxisY: Integer; override;
    function ConfirmPressed: Boolean; override;
  end;

  { Where a session sends sound. Nil-safe by being a class with no-op
    defaults, so a session with no audio is a configuration and not a crash. }
  TSessionAudio = class
  public
    procedure PlayEffect(Id: Integer); virtual;
    procedure PlayMusic(Track: Integer; Loop: Boolean); virtual;
    procedure StopMusic; virtual;
  end;

  { One running game. Owns the pool, the event table and the interpreter;
    borrows the map, the stage table and the sprite sink. }
  TGameSession = class
  private
    FWorld: TGameWorld;
    FPool: TEntityPool;
    FEvents: TEventScript;
    FRunner: TEventRunner;
    FTiles: TMapTileSource;
    FEventHost: TEventHost;
    FAudio: TSessionAudio;
    FOwnAudio: Boolean;
    FGameDir: string;
    FStages: TStageTable;
    FStageIndex: Integer;
    FSprites: TSpritePool;
    FBgAnime: TBgAnime;
    FOnStartFade: TSessionNotify;
    FOnResetHost: TSessionNotify;
    function GetLayer: TLayerInfo;
  public
    { Borrowed, not owned. }
    Map: TTileMap;

    { Shared directly with the form and event hosts. }
    Player: TPlayerState;
    Input: TInputState;

    constructor Create(const AGameDir: string; AStages: TStageTable;
                       AMap: TTileMap);
    destructor Destroy; override;

    { Configure terrain and events, position the camera, and spawn the player. }
    procedure LoadStageAssets(StageIndex: Integer);
    procedure BeginStage(StageIndex: Integer; var AGameState: Integer);

    { One frame of logic. }
    { The entity update is outside state dispatch and runs every frame. }

    { Clears the scroll delta. Called at the top of every frame in every
      state - if it only ran in the states that scroll, a pause would carry
      the last play frame's delta and every entity would drift once per
      paused frame. }
    procedure BeginFrame;
    { Pre-update event spawning and script execution for states 60 and 140. }
    procedure TickPre(var AGameState: Integer);
    { The entity update itself. EVERY state, every frame. }
    procedure TickEntities(var AGameState: Integer);
    { Runs BeginFrame, TickPre, and TickEntities in order. }
    procedure Frame(var AGameState: Integer);

    { Deliberately outside Frame: the application ticks background animation
      outside state dispatch, so a background keeps moving
      through a dialogue box and a pause, where no game logic steps at all.
      Putting it in Frame would have frozen the walls whenever anything
      interrupted play. }
    procedure TickBackground;

    { The camera tile the spawn walk needs, derived from the layer origin the
      same way Events_SpawnNearCamera does it. }
    function CamTileX: Integer;
    function CamTileY: Integer;

    { The camera, in pixels. There is no settable Layer: see the note on the
      Layer property. }
    procedure SetCamera(PixelX, PixelY: Integer);

    { Read-only view of the world layer used by collision and scrolling. }
    property Layer: TLayerInfo read GetLayer;

    { The sprite pool. Not presentation: an entity's extents are read off its
      sprite every frame, so this is where every collision size comes from.
      Give it a frame table with SetFrames before beginning a stage. }
    { The animated background tiles, when the terrain declares any. Nil for
      terrains 5..9, which is a configuration and not a missing piece -
      Terrain_Configure builds one only for 1..4. }
    property BgAnim: TBgAnime read FBgAnime;
    { Bound by the form to start the stage fade-in. }
    property OnStartFade: TSessionNotify read FOnStartFade write FOnStartFade;
    { GameState_Reset also clears the message box and the overlay, which the
      form owns. }
    property OnResetHost: TSessionNotify read FOnResetHost write FOnResetHost;

    property Sprites: TSpritePool read FSprites;
    procedure SetFrames(AFrames: TSpriteSet);

    { Reset shared runtime state before a new game, continue, or game-over
      restart. Mode has two special values:

        mode 0   also zeroes Settings.CurrentStage, so the run restarts at
                 the first stage. Every other mode leaves the stage alone.
        mode 2   SKIPS the camera reset, so a caller that has already placed
                 the view keeps it.

      It clears layer origins and deltas but retains tile geometry. Progress
      flags 4000..4500 are per-run scratch; lower flags belong to the save. }
    procedure ResetState(Mode: Integer);

    property World: TGameWorld read FWorld;
    property Pool: TEntityPool read FPool;
    property Events: TEventScript read FEvents;
    property Runner: TEventRunner read FRunner;
    property StageIndex: Integer read FStageIndex;
    property Audio: TSessionAudio read FAudio write FAudio;
    property EventHost: TEventHost read FEventHost write FEventHost;
  end;

implementation

function TMapTileSource.TileAt(TileX, TileY: Integer): Integer;
begin
  if Map = nil then
    Exit(TILE_NONE);
  Result := Map.TileAtRaw(TileX, TileY);
end;

procedure TSessionAudio.PlayEffect(Id: Integer);
begin
end;

procedure TSessionAudio.PlayMusic(Track: Integer; Loop: Boolean);
begin
end;

procedure TSessionAudio.StopMusic;
begin
end;

{ --- TGameWorld ---------------------------------------------------------- }

constructor TGameWorld.Create(ASession: TGameSession);
begin
  inherited Create;
  FSession := ASession;
end;

function TGameWorld.Spawn(Kind, TypeId, X, Y: Integer): Integer;
begin
  if FSession.Pool = nil then
    Exit(SLOT_NONE);
  Result := FSession.Pool.Spawn(Kind, TypeId, X, Y);
end;

procedure TGameWorld.SetSpawnField(Slot, IntIndex, Value: Integer);
begin
  { A failed spawn has no slot to receive initialization fields. }
  if (FSession.Pool = nil) or (Slot = SLOT_NONE) then
    Exit;
  FSession.Pool.SetField(Slot, IntIndex, Value);
end;

procedure TGameWorld.StopMusic;
begin
  if FSession.Audio <> nil then
    FSession.Audio.StopMusic;
end;

procedure TGameWorld.PlaySound(Id: Integer);
begin
  if FSession.Audio <> nil then
    FSession.Audio.PlayEffect(Id);
end;

function TGameWorld.EventOpcode(EventId: Integer): Integer;
begin
  if (FSession.Events = nil) or (EventId < 0)
     or (EventId >= FSession.Events.Count) then
    Exit(EVOP_DISABLED);
  Result := FSession.Events[EventId].Opcode;
end;

function TGameWorld.EventProgressIndex(EventId: Integer): Integer;
begin
  Result := -1;
  if (FSession.Events = nil) or (EventId < 0)
     or (EventId >= FSession.Events.Count) then
    Exit;
  Result := ProgressIndexOf(FSession.Events[EventId].ParamB);
end;

procedure TGameWorld.BeginEvent(EventId, Arg: Integer);
var
  CurrentGameState: Integer;
begin
  if (FSession.Runner = nil) or (FSession.Events = nil) then
    Exit;
  { Entity destruction can start an event mid-frame, so update the shared game
    state around the runner call. }
  CurrentGameState := GameStateValue;
  FSession.Runner.StartEvent(FSession.Events, EventId, Arg, FSession.Player,
    CurrentGameState);
  GameStateValue := CurrentGameState;
end;

procedure TGameWorld.ClearEventEntity(EventId: Integer);
begin
  if (FSession.Events = nil) or (EventId < 0)
     or (EventId >= FSession.Events.Count) then
    Exit;
  { Keep the in-window mark set to prevent an immediate replacement spawn. }
  FSession.Events.SetActive(EventId, False);
end;

procedure TGameWorld.SetProgress(Index: Integer);
begin
  if (Index >= 0) and (Index < PROGRESS_LENGTH) then
    FSession.Player.Progress[Index] := 1;
end;

function TGameWorld.PlayerDifficulty: Integer;
begin
  Result := FSession.Player.Difficulty;
end;

procedure TGameWorld.SetEventOpcode(EventId, Opcode: Integer);
begin
  if (FSession.Events = nil) or (EventId < 0)
     or (EventId >= FSession.Events.Count) then
    Exit;
  FSession.Events.SetOpcode(EventId, Opcode);
end;

function TGameWorld.AxisX: Integer;
begin
  Result := FSession.Input.AxisX;
end;

function TGameWorld.AxisY: Integer;
begin
  Result := FSession.Input.AxisY;
end;

function TGameWorld.ConfirmPressed: Boolean;
begin
  { ConfirmPressed accepts either action button on its press edge. }
  Result := GameState.ConfirmPressed(FSession.Input);
end;

{ --- TGameSession -------------------------------------------------------- }

constructor TGameSession.Create(const AGameDir: string; AStages: TStageTable;
                                AMap: TTileMap);
begin
  inherited Create;
  FGameDir := AGameDir;
  FStages := AStages;
  Map := AMap;
  FStageIndex := -1;

  FPool := TEntityPool.Create;
  FSprites := TSpritePool.Create;
  FPool.Sprites := FSprites;
  FEvents := TEventScript.Create;
  FRunner := TEventRunner.Create;
  FTiles := TMapTileSource.Create;
  FEventHost := TEventHost.Create;
  FAudio := TSessionAudio.Create;
  FOwnAudio := True;

  FWorld := TGameWorld.Create(Self);
  FWorld.Pool := FPool;
  FWorld.Tiles := FTiles;
  FWorld.Sprites := FSprites;

  InitNewGame(Player, 0);
  FillChar(FWorld.Layer, SizeOf(FWorld.Layer), 0);
  FillChar(Input, SizeOf(Input), 0);
end;

destructor TGameSession.Destroy;
begin
  FWorld.Free;
  if FOwnAudio then
    FAudio.Free;
  FEventHost.Free;
  FBgAnime.Free;
  FTiles.Free;
  FRunner.Free;
  FEvents.Free;
  FPool.Free;
  FSprites.Free;
  inherited Destroy;
end;

procedure TGameSession.ResetState(Mode: Integer);
var
  I: Integer;
  E: PEntity;
begin
  if Mode = 0 then
    Settings.CurrentStage := 0;

  { The shared sub-phase - the game-over screen, the opening and the message
    box all step through it - and the two menu cursors. }
  ScreenPhase := 0;
  TitleSubMode := 0;
  MenuIndex := 0;

  if FSprites <> nil then
    FSprites.Clear;

  ScreenShakeOn := False;
  ScreenShakeTimer := 0;

  if Mode <> 2 then
  begin
    { Origin and delta only. Tile geometry survives, which is why a reset
      does not need the map reloaded. }
    FWorld.Layer.OriginX := 0;
    FWorld.Layer.OriginY := 0;
    FWorld.Layer.DeltaX := 0;
    FWorld.Layer.DeltaY := 0;
  end;

  if FPool <> nil then
    for I := 0 to ENTITY_UPDATE_COUNT - 1 do
    begin
      E := FPool.Entity(I);
      E^.Raw[EF_ALIVE] := 0;
      E^.Raw[EF_EVENT_ID] := -1;
      E^.Raw[EF_SPRITE] := SPRITE_NONE;
    end;

  { The scratch tail of the progress block - see the note on the
    declaration. }
  for I := PROGRESS_SCRATCH_FIRST to PROGRESS_LENGTH - 1 do
    Player.Progress[I] := 0;

  if FEvents <> nil then
    for I := 0 to FEvents.Count - 1 do
    begin
      FEvents.SetInWindow(I, False);
      FEvents.SetActive(I, False);
    end;

  { Clear all interpreter state, including the opcode-4 retry delay, so work
    armed in one room cannot fire in the next. }
  if FRunner <> nil then
  begin
    FRunner.EventId := 0;
    FRunner.StepIndex := 0;
    FRunner.Arg := 0;
    FRunner.Cursor := 0;
  end;

  { Message-box and overlay state belong to the form. }
  if Assigned(FOnResetHost) then
    FOnResetHost;

end;

procedure TGameSession.SetFrames(AFrames: TSpriteSet);
begin
  FSprites.Frames := AFrames;
end;

function TGameSession.GetLayer: TLayerInfo;
begin
  Result := FWorld.Layer;
end;

procedure TGameSession.SetCamera(PixelX, PixelY: Integer);
begin
  FWorld.Layer.OriginX := (PixelX shl POSITION_SHIFT) + POSITION_BIAS;
  FWorld.Layer.OriginY := (PixelY shl POSITION_SHIFT) + POSITION_BIAS;
end;

{ DIVERGENCE DIV-012: derive spawn tiles from the live layer origin. }
{ Return the camera tile derived from the current layer origin. }
function TGameSession.CamTileX: Integer;
begin
  if FWorld.Layer.TileW = 0 then
    Exit(0);
  Result := PixelOf(FWorld.Layer.OriginX) div FWorld.Layer.TileW;
end;

function TGameSession.CamTileY: Integer;
begin
  if FWorld.Layer.TileH = 0 then
    Exit(0);
  Result := PixelOf(FWorld.Layer.OriginY) div FWorld.Layer.TileH;
end;

procedure TGameSession.LoadStageAssets(StageIndex: Integer);
var
  TerrainId: Integer;
  SolidThreshold: Integer;
  KillTile: Integer;
  TerrainAnim: TTerrainAnim;
begin
  { Select the stage, configure terrain, and load its event script. BeginStage
    handles runtime placement separately. }
  FStageIndex := StageIndex;

  { Configure collision thresholds before anything spawns. }
  TerrainId := 0;
  if (FStages <> nil) and (StageIndex >= 0) and (StageIndex < FStages.Count) then
    TerrainId := FStages.TerrainId[StageIndex];
  SolidThreshold := FWorld.SolidThreshold;
  KillTile := KILL_TILE;
  TerrainConfigure(TerrainId, SolidThreshold, KillTile, TerrainAnim);
  FWorld.SolidThreshold := SolidThreshold;
  FWorld.KillTile := KillTile;
  FWorld.TerrainId := TerrainId;

  { Animation tracks belong to the terrain and are rebuilt per stage. }
  FreeAndNil(FBgAnime);
  if TerrainAnim.TrackCount > 0 then
    FBgAnime := TBgAnime.Create(Map, TerrainAnim);

  FEvents.Load(FGameDir, StageIndex);

  FTiles.Map := Map;
  if Map <> nil then
  begin
    FWorld.Layer.TileW := Map.TileWidth;
    FWorld.Layer.TileH := Map.TileHeight;
    FWorld.Layer.MapTilesX := Map.MapWidth;
    FWorld.Layer.MapTilesY := Map.MapHeight;
  end;
end;

procedure TGameSession.BeginStage(StageIndex: Integer;
                                  var AGameState: Integer);
var
  Slot: Integer;
begin
  if Assigned(FOnStartFade) then
    FOnStartFade;
  ResetState(1);
  ScreenPhase := 0;
  AGameState := GS_PLAY;
  TitleSubMode := 0;

  SetCamera(Player.ScrollX, Player.ScrollY);

  Slot := FPool.Spawn(PLAYER_SPAWN_KIND, PLAYER_SPAWN_TYPE,
                      Player.SpawnX shl POSITION_SHIFT,
                      Player.SpawnY shl POSITION_SHIFT);
  if Slot <> SLOT_NONE then
    FPool.SetField(Slot, EF_FACING, Player.SpawnFacing);
end;

procedure TGameSession.TickBackground;
begin
  if FBgAnime <> nil then
    FBgAnime.Tick;
end;

procedure TGameSession.BeginFrame;
begin
  { Deltas carry world-space entities with a scrolling view for one frame only.
    Clear them before the next frame so that motion does not repeat. }
  FWorld.Layer.DeltaX := 0;
  FWorld.Layer.DeltaY := 0;
end;

procedure TGameSession.TickPre(var AGameState: Integer);
begin
  FRunner.SpawnNearCamera(FEvents, FPool, FWorld.Layer, CamTileX, CamTileY,
                          Player, AGameState, FWorld);

  { Execute scripts before entity updates, including while dialogue is active. }
  if AGameState = GS_STATE_140 then
    FRunner.Execute(FEventHost, FEvents, Player, AGameState);
end;

procedure TGameSession.TickEntities(var AGameState: Integer);
begin
  EntityUpdateAll(FPool, FWorld, FSprites, Player, FWorld.Layer, Input,
                  AGameState);
end;

procedure TGameSession.Frame(var AGameState: Integer);
begin
  BeginFrame;
  TickPre(AGameState);
  TickEntities(AGameState);
end;

end.
