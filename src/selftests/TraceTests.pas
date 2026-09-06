{ Drives the player controller through deterministic movement, ability,
  collision, state and audio scenarios in a flat test world. }

unit TraceTests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, TypInfo,
  QdaArchive, SoundTable, WaveFile, AudioMixer, AudioOut, MidiFile, KbgmPlayer,
  Directions, Entities, EventScripts, EventCommands, PlayerState, GameState,
  Stages, Camera, TileMaps, Player, EntityHandlers, EventRunner, GameSession,
  SpritePool, Sprites, Dialogue, BgAnime, UnitInit, Title, Ending, Opening,
  GameFont, DDDDComponent, Surfaces;

function SelfTestTrace(Log: TStrings): Integer;

implementation

{ --selftest-trace runs the player controller through deterministic movement,
  ability, collision, state, and audio scenarios in a flat test world. }

type
  TFlatWorld = class(TPlayerWorld)
  public
    FloorY, WallX, Nonce: Integer;
    Sounds: string;
    Spawns: Integer;
    { Count music stops so death transitions remain observable. }
    MusicStops: Integer;
    function TileAtX(const E: TEntity; Delta: Integer; Scrolling: Boolean;
                     DeltaY: Integer = 0): Integer; override;
    function TileAtY(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer; override;
    function EdgeDistX(const E: TEntity; Delta: Integer): Integer; override;
    function EdgeDistY(const E: TEntity; Delta: Integer): Integer; override;
    function Spawn(Kind, TypeId, X, Y: Integer): Integer; override;
    { Not used by the trace, but left abstract it would be a runtime
      abstract-method error the first time a handler destroyed something. }
    procedure DestroyEntity(var E: TEntity; DropLoot: Boolean); override;
    procedure SetSpawnField(Slot, IntIndex, Value: Integer); override;
    procedure SpawnDebris(const E: TEntity; Kind: Integer); override;
    procedure PlaySound(Id: Integer); override;
    procedure StopMusic; override;
    function RandomBelow(N: Integer): Integer; override;
  end;

procedure TFlatWorld.DestroyEntity(var E: TEntity; DropLoot: Boolean);
begin
  E.Raw[EF_ALIVE] := 0;
end;

function TFlatWorld.TileAtX(const E: TEntity; Delta: Integer;
                               Scrolling: Boolean; DeltaY: Integer): Integer;
begin
  if EntityPixelX(E) + Delta div 32 >= WallX then
    Result := SolidThreshold
  else
    Result := 0;
end;

function TFlatWorld.TileAtY(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer;
begin
  if EntityPixelY(E) + Delta div 32 >= FloorY then
    Result := SolidThreshold
  else
    Result := 0;
end;

function TFlatWorld.EdgeDistX(const E: TEntity; Delta: Integer): Integer;
begin
  Result := (WallX - 1 - EntityPixelX(E)) * 32;
  if Result < 0 then Result := 0;
  if Result > Delta then Result := Delta;
end;

function TFlatWorld.EdgeDistY(const E: TEntity; Delta: Integer): Integer;
begin
  Result := (FloorY - 1 - EntityPixelY(E)) * 32;
  if Result < 0 then Result := 0;
  if Result > Delta then Result := Delta;
end;

{ With no pool attached, the inherited solid-collision methods find no solids. }
function TFlatWorld.Spawn(Kind, TypeId, X, Y: Integer): Integer;
begin
  Inc(Spawns);
  Result := 0;
end;

procedure TFlatWorld.SetSpawnField(Slot, IntIndex, Value: Integer);
begin
end;

procedure TFlatWorld.SpawnDebris(const E: TEntity; Kind: Integer);
begin
  Inc(Spawns);
end;

procedure TFlatWorld.StopMusic;
begin
  Inc(MusicStops);
end;

procedure TFlatWorld.PlaySound(Id: Integer);
begin
  Sounds := Sounds + IntToStr(Id) + ' ';
end;

function TFlatWorld.RandomBelow(N: Integer): Integer;
begin
  { Not Random: the trace has to be reproducible. }
  Nonce := (Nonce + 7) mod N;
  Result := Nonce;
end;

function SelfTestTrace(Log: TStrings): Integer;
var
  W: TFlatWorld;
  E: TEntity;
  P: TPlayerState;
  L: TLayerInfo;
  Inp: TInputState;
  Down: array[0..3] of Boolean;
  I, F, StartX, Apex, ApexFrame, Landed, DashVX, StopFrame: Integer;
  Trace, Trace2: string;

  procedure StepIn(AGameState, AxisX, AxisY: Integer; Jump, Attack: Boolean);
  begin
    Inp.AxisX := AxisX;
    Inp.AxisY := AxisY;
    Inp.Button[0] := Jump;
    Inp.Button[1] := Attack;
    Down[0] := Jump; Down[1] := Attack; Down[2] := False; Down[3] := False;
    PlayerUpdate(E, P, L, Inp, W, AGameState);
    InputEndOfFrame(Inp, Down);
  end;

  procedure Step(AxisX, AxisY: Integer; Jump, Attack: Boolean);
  begin
    StepIn(GS_PLAY, AxisX, AxisY, Jump, Attack);
  end;

  { Settle for three frames so the initial landing transition completes before
    a scenario supplies input. }
  procedure Reset;
  var
    K: Integer;
  begin
    FillChar(E, SizeOf(E), 0);
    FillChar(Inp, SizeOf(Inp), 0);
    E.Raw[EF_ALIVE] := 1;
    E.Raw[EF_TYPE] := 1;
    E.Raw[EF_EXTENT_X] := 16;
    E.Raw[EF_EXTENT_Y] := 16;
    E.Raw[EF_POS_X] := POSITION_BIAS + 100 * 32;
    E.Raw[EF_POS_Y] := POSITION_BIAS + 199 * 32;
    E.Raw[PF_STATE] := PS_GROUND;
    for K := 1 to 3 do
      Step(0, 0, False, False);
    W.Sounds := '';
    W.Spawns := 0;
  end;

  { Reset settles for three frames and then clears Sounds, which is right for
    every other test here and wrong for this one: the sound it clears is the
    one being measured. This places the player the same way and stops. }
  procedure PlaceOnFloor;
  begin
    FillChar(E, SizeOf(E), 0);
    FillChar(Inp, SizeOf(Inp), 0);
    E.Raw[EF_ALIVE] := 1;
    E.Raw[EF_TYPE] := 1;
    E.Raw[EF_EXTENT_X] := 16;
    E.Raw[EF_EXTENT_Y] := 16;
    E.Raw[EF_POS_X] := POSITION_BIAS + 100 * 32;
    E.Raw[EF_POS_Y] := POSITION_BIAS + 199 * 32;
    E.Raw[PF_STATE] := PS_GROUND;
    W.Sounds := '';
    W.Spawns := 0;
  end;

begin
  Result := 0;
  W := TFlatWorld.Create;
  try
    W.FloorY := 200;
    W.WallX := 300;
    W.SolidThreshold := $32;
    W.Fading := False;

    FillChar(P, SizeOf(P), 0);
    P.JumpStrength := DEFAULT_JUMP_STRENGTH;      { 0x68 = 104 }
    P.MaxLives := 3;
    P.Lives := 3;
    P.Weapon := 0;

    { A 10-by-7 room disables camera scrolling, keeping the flat world's floor
      and walls in the same coordinate space as the player. Scenario 5a widens
      the map when it specifically tests scrolling. }
    FillChar(L, SizeOf(L), 0);
    L.TileW := 32; L.TileH := 32;
    L.MapTilesX := 10; L.MapTilesY := 7;
    { Biased, like every layer the game builds - see the note in the camera
      section above. With a bare 0 the vertical clamp reads the origin as
      2048 pixels ABOVE the map and lets the view move instead of the entity,
      so a jump never comes down. }
    L.OriginX := POSITION_BIAS;
    L.OriginY := POSITION_BIAS;

    { --- 1. standing still ------------------------------------------------ }
    Reset;
    for I := 1 to 20 do Step(0, 0, False, False);
    Log.Add(Format('idle 20 frames:   state %d, x %d, y %d, vy %d',
      [E.Raw[PF_STATE], EntityPixelX(E), EntityPixelY(E), E.Raw[EF_VEL_Y]]));
    if (E.Raw[EF_VEL_Y] <> 0) or (EntityPixelX(E) <> 100) then
    begin
      Log.Add('FAILED: standing still does not stand still');
      Inc(Result);
    end;

    { --- 2. walking: AxisX shl 5 is 32 sub-pixels, exactly one pixel ------- }
    Reset;
    StartX := EntityPixelX(E);
    for I := 1 to 10 do Step(1, 0, False, False);
    Log.Add(Format('walk right 10:    x %d -> %d  (expected +10)',
      [StartX, EntityPixelX(E)]));
    if EntityPixelX(E) - StartX <> 10 then
    begin
      Log.Add(Format('FAILED: walking moved %d pixels in 10 frames, expected 10',
        [EntityPixelX(E) - StartX]));
      Inc(Result);
    end;

    { --- 3. the double tap ------------------------------------------------- }
    Reset;
    Step(1, 0, False, False);          { first tap opens the window }
    Step(0, 0, False, False);
    Step(1, 0, False, False);          { second tap, but the ability is LOCKED }
    Step(1, 0, False, False);
    Log.Add(Format('double tap, ability locked:   state %d (expected %d)',
      [E.Raw[PF_STATE], PS_GROUND]));
    if E.Raw[PF_STATE] <> PS_GROUND then
    begin
      Log.Add('FAILED: dashed without the ability unlocked');
      Inc(Result);
    end;

    Reset;
    P.Head[ABILITY_DASH] := 1;
    Step(1, 0, False, False);
    Step(0, 0, False, False);
    Step(1, 0, False, False);          { the dash STARTS here ... }
    Step(1, 0, False, False);          { ... and reaches its speed here }
    DashVX := E.Raw[EF_VEL_X];
    Log.Add(Format('double tap, ability unlocked: state %d, vx %d (expected %d, %d)',
      [E.Raw[PF_STATE], DashVX, PS_DASH, 1 shl PLAYER_DASH_SHIFT]));
    if (E.Raw[PF_STATE] <> PS_DASH) or (DashVX <> 1 shl PLAYER_DASH_SHIFT) then
    begin
      Log.Add('FAILED: the double tap did not start a dash at twice walking speed');
      Inc(Result);
    end;
    P.Head[ABILITY_DASH] := 0;

    { --- 4. a jump, from the constants -------------------------------------
      Leaves at -JumpStrength and gains PLAYER_GRAVITY a frame, so it is still
      rising for JumpStrength div PLAYER_GRAVITY frames. }
    Reset;
    Apex := 999; ApexFrame := 0; Landed := 0; StopFrame := 0;
    Trace := ''; Trace2 := '';
    for F := 1 to 90 do
    begin
      Step(0, 0, F <= 40, False);      { hold jump for 40 frames }
      if EntityPixelY(E) < Apex then
      begin
        Apex := EntityPixelY(E);
        ApexFrame := F;
      end;
      if (StopFrame = 0) and (E.Raw[EF_VEL_Y] >= 0) then
        StopFrame := F;
      if (Landed = 0) and (F > 3) and (E.Raw[PF_STATE] = PS_LANDING) then
        Landed := F;
      if F <= 6 then
        Trace := Trace + Format('%d:%d/%d ', [F, EntityPixelY(E), E.Raw[EF_VEL_Y]]);
      if (F >= 50) and (F <= 56) then
        Trace2 := Trace2 + Format('%d:%d/%d/s%d ',
          [F, EntityPixelY(E), E.Raw[EF_VEL_Y], E.Raw[PF_STATE]]);
    end;
    Log.Add('jump trace y/vy:  ' + Trace);
    Log.Add('landing 50..56:   ' + Trace2);
    Log.Add(Format('jump:             apex %d px up, vy hit 0 at frame %d,'
      + ' landed frame %d', [199 - Apex, StopFrame, Landed]));
    Log.Add(Format('  sounds:         %s', [W.Sounds]));
    { Assert the apex using velocity: sub-pixel movement lets the displayed
      position reach its minimum before velocity crosses zero. }
    { JumpStrength div PLAYER_GRAVITY frames of gravity, PLUS the launch frame.
      The jump impulse is applied in the GROUNDED branch, and gravity only in
      the airborne one, so the launch frame receives no gravity. Hence 26 + 1. }
    if StopFrame <> P.JumpStrength div PLAYER_GRAVITY + 1 then
    begin
      Log.Add(Format('FAILED: vy reached 0 at frame %d, but -%d rising at +%d'
        + ' a frame, plus the launch frame, takes %d',
        [StopFrame, P.JumpStrength, PLAYER_GRAVITY,
         P.JumpStrength div PLAYER_GRAVITY + 1]));
      Inc(Result);
    end;
    if Landed = 0 then
    begin
      Log.Add('FAILED: the jump never landed');
      Inc(Result);
    end;
    if Pos(IntToStr(SND_JUMP) + ' ', W.Sounds) <> 1 then
    begin
      Log.Add('FAILED: the jump did not play the jump sound first');
      Inc(Result);
    end;

    { --- 5a. the dead zone stops the player, not the world -----------------
      On a big map, walking right past pixel 177 scrolls the layer instead of
      moving the entity, so the player's own position stops there. That is the
      expected camera behavior. }
    L.MapTilesX := 1000;
    L.OriginX := POSITION_BIAS;
    Reset;
    for I := 1 to 400 do Step(1, 0, False, False);
    Log.Add(Format('walk right on a big map: x %d, layer origin %d px'
      + '  (dead zone at %d)',
      [EntityPixelX(E), PixelOf(L.OriginX), Camera.DEADZONE_RIGHT]));
    if EntityPixelX(E) <> Camera.DEADZONE_RIGHT then
    begin
      Log.Add(Format('FAILED: expected the player to stop at the dead zone'
        + ' edge %d, got %d', [Camera.DEADZONE_RIGHT, EntityPixelX(E)]));
      Inc(Result);
    end;
    if PixelOf(L.OriginX) <= 0 then
    begin
      Log.Add('FAILED: the player stopped but the layer never scrolled');
      Inc(Result);
    end;

    { --- 5b. and on a map too small to scroll, it reaches the wall --------- }
    L.MapTilesX := 10;
    L.OriginX := POSITION_BIAS;
    Reset;
    for I := 1 to 400 do Step(1, 0, False, False);
    Log.Add(Format('walk into the wall:      x %d (wall at %d)',
      [EntityPixelX(E), W.WallX]));
    if EntityPixelX(E) >= W.WallX then
    begin
      Log.Add('FAILED: walked through the wall');
      Inc(Result);
    end;
    if EntityPixelX(E) <> W.WallX - 1 then
    begin
      Log.Add(Format('FAILED: stopped at %d, not flush against the wall at %d',
        [EntityPixelX(E), W.WallX - 1]));
      Inc(Result);
    end;
    { --- 6. glide entry and compatibility behavior --------------------------
      Entering needs Up, no horizontal input, having jumped, and the ability.
      Once active, the vertical clamp writes horizontal velocity for executable
      compatibility; see Player.pas. }
    Reset;
    P.Head[ABILITY_GLIDE] := 1;
    Step(0, 0, True, False);                    { jump }
    for I := 1 to 4 do Step(0, 0, True, False);
    Step(0, -1, False, False);                  { Up in the air }
    Log.Add(Format('glide entry:      state %d (expected %d)',
      [E.Raw[PF_STATE], PS_SPECIAL1]));
    if E.Raw[PF_STATE] <> PS_SPECIAL1 then
    begin
      Log.Add('FAILED: Up in the air with the glide unlocked did not glide');
      Inc(Result);
    end;

    { The same input WITHOUT the ability must do nothing - otherwise the
      ability gate is not being read at all. }
    Reset;
    P.Head[ABILITY_GLIDE] := 0;
    Step(0, 0, True, False);
    for I := 1 to 4 do Step(0, 0, True, False);
    Step(0, -1, False, False);
    Log.Add(Format('glide entry, locked: state %d (expected %d)',
      [E.Raw[PF_STATE], PS_AIRBORNE]));
    if E.Raw[PF_STATE] = PS_SPECIAL1 then
    begin
      Log.Add('FAILED: glided without the ability unlocked');
      Inc(Result);
    end;

    { --- 7. the GS_PLAY guard -------------------------------------------
      Outside active play, the clock advances but player behavior does not. }
    Reset;
    StartX := EntityPixelX(E);
    F := P.ElapsedSec * 60 + P.Field11C0;
    for I := 1 to 120 do
      StepIn(GS_PAUSE, 1, 0, True, True);
    Log.Add('');
    Log.Add(Format('120 frames while paused: x %d (was %d), state %d, clock +%d',
      [EntityPixelX(E), StartX, E.Raw[PF_STATE],
       (P.ElapsedSec * 60 + P.Field11C0) - F]));
    if EntityPixelX(E) <> StartX then
    begin
      Log.Add('FAILED: the player moved while the game was not in play');
      Inc(Result);
    end;
    if (P.ElapsedSec * 60 + P.Field11C0) - F <> 120 then
    begin
      Log.Add('FAILED: the play clock did not run while paused - it should');
      Inc(Result);
    end;

    { --- dying on screen stops the stage music ---------------------------
      Player_UpdateKnockback, at the moment the last life goes:

          spawn three type-9 souls at 0, 0x14, 0x28
          FUN_00450CBC(music, 0)      <- the stage track stops
          PlaySound(0x0C)
          state := 9

      The music stop must occur once when the last life is lost. }
    P.Lives := 0;
    PlaceOnFloor;
    E.Raw[PF_STATE] := PS_SPECIAL3;      { knockback }
    W.MusicStops := 0;
    Step(0, 0, False, False);
    if E.Raw[PF_STATE] <> PS_DYING then
    begin
      Log.Add(Format('FAILED: knockback with no lives left ended in state %d, '
        + 'want PS_DYING (%d) - the death never happened, so the music check '
        + 'below proves nothing', [E.Raw[PF_STATE], PS_DYING]));
      Inc(Result);
    end;
    if W.MusicStops <> 1 then
    begin
      Log.Add(Format('FAILED: dying on screen stopped the music %d times, '
        + 'want 1 - the stage track plays on over the death',
        [W.MusicStops]));
      Inc(Result);
    end;

    { and with a life still in hand it is an ordinary landing, music intact. }
    P.Lives := 1;
    PlaceOnFloor;
    E.Raw[PF_STATE] := PS_SPECIAL3;
    W.MusicStops := 0;
    Step(0, 0, False, False);
    if W.MusicStops <> 0 then
    begin
      Log.Add(Format('FAILED: surviving a knockback stopped the music %d '
        + 'times - only the last life does', [W.MusicStops]));
      Inc(Result);
    end;
    P.Lives := 3;

    { --- a landing while the screen fades is SILENT ---------------------
      This is the door-transition case. Reset's own comment says it: an
      entity placed on the ground has PF_LANDED = 0, so its first update
      runs the whole just-landed sequence, sound included. A warp places the
      player exactly that way, and it waits on the fader, so the original's
      guard - fader +0x0D - is what keeps a room change quiet. }
    W.Fading := False;
    PlaceOnFloor;
    Step(0, 0, False, False);
    if W.Sounds <> IntToStr(SND_LAND_SOFT) + ' ' then
    begin
      Log.Add(Format('FAILED: landing not fading played [%s], want [%d] - '
        + 'the control case is broken, so the fading case below proves '
        + 'nothing', [W.Sounds, SND_LAND_SOFT]));
      Inc(Result);
    end;

    W.Fading := True;
    PlaceOnFloor;
    Step(0, 0, False, False);
    if W.Sounds <> '' then
    begin
      Log.Add(Format('FAILED: landing while the fader is busy played [%s] - '
        + 'every door transition makes a falling sound the original does '
        + 'not', [W.Sounds]));
      Inc(Result);
    end;

    { and the HARD landing has no such guard - it sounds through the fade. }
    W.Fading := True;
    PlaceOnFloor;
    E.Raw[PF_FALL_FRAMES] := FALL_HARD_THRESHOLD * 3;
    Step(0, 0, False, False);
    if Pos(IntToStr(SND_LAND_HARD), W.Sounds) = 0 then
    begin
      Log.Add(Format('FAILED: the hard landing was silenced too, playing '
        + '[%s] - only the soft one is guarded', [W.Sounds]));
      Inc(Result);
    end;
    W.Fading := False;

  finally
    W.Free;
  end;

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - the controller behaves as its own constants predict')
  else
    Log.Add('FAILED');
end;

end.
