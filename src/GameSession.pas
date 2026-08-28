{ GameSession - the running game, as one object.

  Everything up to now has been translated in isolation and tested in
  isolation. The entity system, the player controller, the camera and the
  event interpreter all work and NONE of them had a caller: GmMain.pas did not
  even reference the units. This is what connects them, and it is the first
  place any of it is asked to fit together.

  ## Why an object rather than the form

  The original keeps all of this in globals - the pool at 0x0046CB68, the
  layer array at 0x0046D144, the event table, the interpreter's six variables,
  the player state at 0x0046CFF0. Gathering them into one object is the same
  move already made for TEventRunner, and for the same reason: they are one
  thing, and a test wants to make one without disturbing the game's.

  It also means the WIRING is testable. A form is not; a session is. That
  matters more here than anywhere else, because every self-test so far has
  checked a function against its own fixture, and none of them could catch two
  correct functions being connected wrongly.

  ## What is real and what is a hook

  Real: the pool, the tile source over a shipped map, the entity dispatcher,
  the player controller, the camera, the event table and the interpreter.

  Hooks: sound, sprites and the screen. TGameSession takes them as objects it
  does not own, and nil is a legitimate configuration - a session with no
  sprite pool still runs every frame of logic, which is exactly what the
  self-test needs.

  ## The frame

  Frame() is the order TFrm_main_AppIdle runs in, minus the presentation:

      Events_SpawnNearCamera    what has come near the camera exists
      Entity_UpdateAll          every live slot, including the player
      the event interpreter     if a script is running

  The player is slot 0 and is updated by the dispatcher like everything else,
  so there is no separate call for it. That is the original's shape and it is
  why EKIND_SINGLE has exactly one slot. }

unit GameSession;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Entities, EntityHandlers, Player, Camera, PlayerState,
  GameState, Stages, TileMaps, EventScripts, EventCommands, EventRunner,
  Sprites, SpritePool;

type
  { A TTileSource over a loaded map. The map may be nil - a session with no
    terrain answers TILE_NONE everywhere, which is what the flat-room tests
    want. }
  TMapTileSource = class(TTileSource)
  public
    Map: TTileMap;
    function TileAt(TileX, TileY: Integer): Integer; override;
  end;

  TGameSession = class;

  { The world the entity handlers see. Its abstract members - Spawn,
    SetSpawnField, PlaySound - are the three genuine injection points, and
    they are the reason TEntityWorld was left abstract rather than being given
    a default that would have hidden a missing wire. }
  TGameWorld = class(TEntityWorld)
  private
    FSession: TGameSession;
  public
    constructor Create(ASession: TGameSession);
    function Spawn(Kind, TypeId, X, Y: Integer): Integer; override;
    procedure SetSpawnField(Slot, IntIndex, Value: Integer); override;
    procedure PlaySound(Id: Integer); override;

    { The event system, which Entity_Destroy and the touch handlers reach
      through the world rather than directly. }
    function EventOpcode(EventId: Integer): Integer; override;
    function EventProgressIndex(EventId: Integer): Integer; override;
    procedure BeginEvent(EventId, Arg: Integer); override;
    procedure ClearEventEntity(EventId: Integer); override;
    procedure SetProgress(Index: Integer); override;

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
    function GetLayer: TLayerInfo;
  public
    { Borrowed, not owned. }
    Map: TTileMap;

    { The state the original keeps in globals. Public because the form reads
      them straight, exactly as the original does. }
    Player: TPlayerState;
    Input: TInputState;

    constructor Create(const AGameDir: string; AStages: TStageTable;
                       AMap: TTileMap);
    destructor Destroy; override;

    { Stage_Begin's reconstructible half: configure the terrain, load the
      stage's events, place the camera and spawn the player. The ASSETS are
      the caller's business - the form has the surfaces. }
    procedure BeginStage(StageIndex: Integer; var AGameState: Integer);

    { One frame of logic. }
    procedure Frame(var AGameState: Integer);

    { The camera tile the spawn walk needs, derived from the layer origin the
      same way Events_SpawnNearCamera does it. }
    function CamTileX: Integer;
    function CamTileY: Integer;

    { The camera, in pixels. There is no settable Layer: see the note on the
      Layer property. }
    procedure SetCamera(PixelX, PixelY: Integer);

    { THE layer - not a copy. TEntityWorld owns the storage because that is
      what every collision query reads, and the session hands the same field
      to EntityUpdateAll as its var parameter, so a scroll applied during a
      frame is applied to the thing the next query will read.

      This was a field on the session first, synced to the world's copy at the
      top of each frame and back at the bottom. The write-back overwrote every
      scroll the frame had just applied, so the camera never moved, the
      player's tile row never changed, and nothing in the map was ever solid -
      the player fell through the world forever. Every unit test still passed,
      because each function was correct; only running a frame could show it.
      One storage location, structurally, is the fix. }
    property Layer: TLayerInfo read GetLayer;

    { The sprite pool. Not presentation: an entity's extents are read off its
      sprite every frame, so this is where every collision size comes from.
      Give it a frame table with SetFrames before beginning a stage. }
    property Sprites: TSpritePool read FSprites;
    procedure SetFrames(AFrames: TSpriteSet);

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
  { Entity_Spawn's callers write straight through to the new slot, and a
    failed spawn returns SLOT_NONE - which the original then writes to
    anyway. Refusing is the one divergence, because reproducing it means
    writing outside the array. }
  if (FSession.Pool = nil) or (Slot = SLOT_NONE) then
    Exit;
  FSession.Pool.SetField(Slot, IntIndex, Value);
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
  GS: Integer;
begin
  if (FSession.Runner = nil) or (FSession.Events = nil) then
    Exit;
  { Entity_Destroy reaches this in the middle of a frame and the game state is
    what Event_Begin locks on, so it has to be the real one. }
  GS := GameStateValue;
  FSession.Runner.StartEvent(FSession.Events, EventId, Arg, FSession.Player, GS);
  GameStateValue := GS;
end;

procedure TGameWorld.ClearEventEntity(EventId: Integer);
begin
  if (FSession.Events = nil) or (EventId < 0)
     or (EventId >= FSession.Events.Count) then
    Exit;
  { The has-entity mark goes down; the in-window mark stays up, which is what
    stops an immediate replacement. See Events_SpawnNearCamera. }
  FSession.Events.SetActive(EventId, False);
end;

procedure TGameWorld.SetProgress(Index: Integer);
begin
  if (Index >= 0) and (Index < PROGRESS_LENGTH) then
    FSession.Player.Progress[Index] := 1;
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
  Result := FSession.Input.Button[0];
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
  FTiles.Free;
  FRunner.Free;
  FEvents.Free;
  FPool.Free;
  FSprites.Free;
  inherited Destroy;
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

procedure TGameSession.BeginStage(StageIndex: Integer;
                                  var AGameState: Integer);
var
  Slot, Terrain, Thr, Kill: Integer;
  Anim: TTerrainAnim;
begin
  FStageIndex := StageIndex;

  { Terrain_Configure. The threshold and the kill tile are what every
    collision query in the frame reads, so they have to be set before
    anything is spawned. }
  Terrain := 0;
  if (FStages <> nil) and (StageIndex >= 0) and (StageIndex < FStages.Count) then
    Terrain := FStages.TerrainId[StageIndex];
  Thr := FWorld.SolidThreshold;
  Kill := KILL_TILE;
  TerrainConfigure(Terrain, Thr, Kill, Anim);
  FWorld.SolidThreshold := Thr;
  FWorld.TerrainId := Terrain;

  FEvents.Load(FGameDir, StageIndex);

  FTiles.Map := Map;
  if Map <> nil then
  begin
    FWorld.Layer.TileW := Map.TileWidth;
    FWorld.Layer.TileH := Map.TileHeight;
    FWorld.Layer.MapTilesX := Map.MapWidth;
    FWorld.Layer.MapTilesY := Map.MapHeight;
  end;

  { Stage_Begin's own three steps. }
  SetCamera(Player.ScrollX, Player.ScrollY);
  FWorld.Layer.DeltaX := 0;
  FWorld.Layer.DeltaY := 0;

  FPool.Clear;
  FSprites.Clear;
  Slot := FPool.Spawn(PLAYER_SPAWN_KIND, PLAYER_SPAWN_TYPE,
                      Player.SpawnX shl POSITION_SHIFT,
                      Player.SpawnY shl POSITION_SHIFT);
  if Slot <> SLOT_NONE then
    FPool.SetField(Slot, EF_FACING, Player.SpawnFacing);

  AGameState := GS_PLAY;
end;

procedure TGameSession.Frame(var AGameState: Integer);
begin
  { FWorld.Layer is passed straight through as the var parameter, so a scroll
    applied inside the frame is applied to the same storage the collision
    queries read. There is no second copy to keep in step. }
  FRunner.SpawnNearCamera(FEvents, FPool, FWorld.Layer, CamTileX, CamTileY,
                          Player, AGameState);

  EntityUpdateAll(FPool, FWorld, FSprites, Player, FWorld.Layer, Input,
                  AGameState);

  { A script runs only while the game is in its own state, which is what
    stops the player moving during a conversation. }
  if AGameState = GS_STATE_140 then
    FRunner.Execute(FEventHost, FEvents, Player, AGameState);
end;

end.
