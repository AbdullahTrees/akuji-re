{ Player controller. Tilemap, entity, sound, and camera services are accessed
  through TPlayerWorld. PF_* names describe the player's use of shared entity
  slots; PF_LANDED and EF_RIDDEN share a slot with type-specific meanings. }

unit Player;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Entities, PlayerState, Camera, GameState;

const
  { --- The player's own use of block A and block B ------------------------- }
  PF_STATE        = $08;   { = EF_STATE }
  PF_AIR_LATCH    = $09;   { set on leaving the ground, cleared on landing }
  PF_LANDED       = $0A;   { landing one-shot; same slot as EF_RIDDEN }
  PF_FALL_FRAMES  = $0B;   { frames of downward motion, capped }
  PF_STATE_BEFORE = $0C;   { state to resume after the landing recovery }
  PF_RIDING       = $0D;   { standing on a moving solid }
  PF_RIDE_REF     = $0E;   { that solid's X last frame }
  PF_LAND_FRAMES  = $0F;   { forced recovery length, overriding the fall one }
  PF_JUMP_HELD    = $10;   { while set, releasing jump does not cut it short }
  PF_ANIM_TIMER   = $12;   { = EF_BLOCK_B[0] }
  PF_AIR_VX       = $13;   { horizontal speed carried into the air }
  PF_CHARGE       = $14;   { frames the attack button has been held }
  PF_SHOTS        = $15;   { projectiles of ours currently alive }
  PF_JUMP_PROBE   = $16;   { one-frame vertical probe offset for solids }
  PF_DASH_FRAMES  = $17;   { dash countdown }
  PF_HAS_JUMPED   = $18;   { set by a jump, cleared on landing }
  PF_PEND_VX      = $2C;   { velocity handed over by a moving solid }
  PF_PEND_VY      = $2D;
  PF_ANIM_FRAME   = $07;   { = EF_FLAG1C; walk cycle sub-frame 0..2 }
  PF_ANIM_ID      = $05;   { the sprite id drawn this frame }
  PF_OWNER        = $01;   { on a projectile: the slot that fired it }
  PF_PROJ_LIFE    = $14;   { on a projectile: its lifetime, from the weapon
                             table. Byte +0x50. Same slot as PF_CHARGE on the
                             player - block B is per-type, as always. }

  { Sound-effect slots. }
  SND_JUMP        = 3;    SND_LAND_HARD  = 4;
  SND_ATTACK      = 5;    SND_CHARGE_FULL = 6;
  SND_CHARGED     = 7;    SND_LAND_SOFT  = 8;
  { Glide and air-dash sounds play on both entering and leaving their state. }
  SND_GLIDE       = 9;    SND_AIRDASH    = 10;
  { Both death states hold for 121 frames before the game-over screen. }
  DEATH_HOLD      = $79;
  SND_DEATH       = 12;   SND_DASH_START = 21;

  { Four weapons. Only weapon 3 supports charging. }
  WEAPON_COUNT = 4;
type
  TWeapon = record
    MaxShots: Integer;   { how many of ours may be alive at once }
    Speed:    Integer;   { multiplied by the direction table entry }
    ProjState: Integer;  { written to the projectile's EF_STATE }
    Lifetime: Integer;
  end;
const
  WEAPONS: array[0..WEAPON_COUNT - 1] of TWeapon = (
    (MaxShots: 0; Speed: 0; ProjState: 0; Lifetime: 0),
    (MaxShots: 1; Speed: 3; ProjState: 0; Lifetime: 20),
    (MaxShots: 2; Speed: 4; ProjState: 1; Lifetime: 40),
    (MaxShots: 2; Speed: 4; ProjState: 1; Lifetime: 60));
  CHARGE_WEAPON = 3;

type
  { The player controller's view of the world is the shared TEntityWorld - see
    Entities.pas. Kept as an alias because every handler needs the same surface
    and there is nothing player-specific in it. }
  TPlayerWorld = Entities.TEntityWorld;

type
  { Form and display services required by StageBegin. }
  TStageHost = class
  public
    procedure PrepareDisplay; virtual;
    procedure ResetInput; virtual;
    procedure LoadStageAssets(StageIndex: Integer); virtual;
    { Define the bitmap font described by GameFont.pas. }
    procedure DefineFont; virtual;
    procedure SetBackgroundSurface; virtual;
  end;

const
  { Entity_Spawn's kind and type for the player. Slot 0, always. }
  PLAYER_SPAWN_KIND = EKIND_SINGLE;
  PLAYER_SPAWN_TYPE = 1;

{ Initialize a stage and enter GS_PLAY.

  The order is kept: assets load BEFORE the layer origin is written and the
  player spawned, because loading replaces the tilemaps and surfaces the
  other two depend on.

  The layer origin and spawn position are pixels shifted into 1/32 units. }
procedure StageBegin(Pool: TEntityPool; var L: TLayerInfo;
                     var P: TPlayerState; Host: TStageHost;
                     StageIndex: Integer; var AGameState: Integer);

{ One frame. E is the player entity, P the save state (abilities, weapon, jump
  strength, lives), L the layer the camera lives in.
  Inp is writable because the controller owns the double-tap window. }
procedure PlayerUpdate(var E: TEntity; var P: TPlayerState;
                       var L: TLayerInfo; var Inp: TInputState;
                       World: TPlayerWorld; AGameState: Integer);

implementation

uses
  Directions;

{ Specialized movement states delegate their collision and camera work. }

{ Shared movement runs each axis through solid, tile, and camera handling. }
procedure TStageHost.PrepareDisplay; begin end;
procedure TStageHost.ResetInput; begin end;
procedure TStageHost.LoadStageAssets(StageIndex: Integer); begin end;
procedure TStageHost.DefineFont; begin end;
procedure TStageHost.SetBackgroundSurface; begin end;

procedure StageBegin(Pool: TEntityPool; var L: TLayerInfo;
                     var P: TPlayerState; Host: TStageHost;
                     StageIndex: Integer; var AGameState: Integer);
var
  Slot: Integer;
begin
  Host.PrepareDisplay;
  Host.ResetInput;

  AGameState := GS_PLAY;

  { The assets first: everything below reads what they replace. }
  Host.LoadStageAssets(StageIndex);
  Host.DefineFont;
  Host.SetBackgroundSurface;

  L.OriginX := (P.ScrollX shl POSITION_SHIFT) + POSITION_BIAS;
  L.OriginY := (P.ScrollY shl POSITION_SHIFT) + POSITION_BIAS;

  if Pool = nil then
    Exit;
  Slot := Pool.Spawn(PLAYER_SPAWN_KIND, PLAYER_SPAWN_TYPE,
                     P.SpawnX shl POSITION_SHIFT,
                     P.SpawnY shl POSITION_SHIFT);
  if Slot <> SLOT_NONE then
    Pool.SetField(Slot, EF_FACING, P.SpawnFacing);
end;

procedure MoveAndCollide(var E: TEntity; var L: TLayerInfo;
                         World: TPlayerWorld; out HitX, HitY: Boolean);
var
  ScrollX, ScrollY, BlockedX, BlockedY: Boolean;
  SolidX, SolidY: Boolean;
begin
  ScrollX := ShouldScrollX(L, EntityPixelX(E), E.Raw[EF_VEL_X]);
  SolidX := World.SolidCollideX(E, E.Raw[EF_VEL_X], False);
  BlockedX := SolidX;
  if SolidX then
    E.Raw[EF_VEL_X] := World.PushX;
  if World.TileAtX(E, E.Raw[EF_VEL_X], ScrollX) >= World.SolidThreshold then
  begin
    E.Raw[EF_VEL_X] := World.EdgeDistX(E, E.Raw[EF_VEL_X]);
    BlockedX := True;
  end;
  ApplyMoveX(L, E.Raw[EF_POS_X], E.Raw[EF_VEL_X], ScrollX, BlockedX);

  ScrollY := ShouldScrollY(L, EntityPixelY(E), E.Raw[EF_VEL_Y]);
  SolidY := World.SolidCollideY(E, E.Raw[EF_VEL_Y], False);
  BlockedY := SolidY;
  if SolidY then
    E.Raw[EF_VEL_Y] := World.PushY;
  if World.TileAtY(E, E.Raw[EF_VEL_Y], ScrollY) >= World.SolidThreshold then
  begin
    E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
    BlockedY := True;
  end;
  ApplyMoveY(L, E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y], ScrollY, BlockedY,
             @E, World);

  HitX := BlockedX;
  HitY := BlockedY;
end;

{ Facing is stored as an angle; 0 is right and $20 is left, and the sprite
  tables index it with Facing shr 5. }
procedure FaceByVelocity(var E: TEntity);
begin
  if E.Raw[EF_VEL_X] < 0 then E.Raw[EF_FACING] := $20;
  if E.Raw[EF_VEL_X] > 0 then E.Raw[EF_FACING] := 0;
end;

function FacingIndex(const E: TEntity): Integer;
var
  Facing: Integer;
begin
  Facing := E.Raw[EF_FACING];
  if Facing < 0 then
    Facing := Facing + 31;
  Result := Facing shr 5;
end;

procedure UpdateGlide(var E: TEntity; var P: TPlayerState; var L: TLayerInfo;
                      const Inp: TInputState; World: TPlayerWorld);
var
  HitX, HitY: Boolean;
  Step: Integer;
begin
  E.Raw[EF_VEL_X] := E.Raw[EF_VEL_X] + Inp.AxisX * GLIDE_ACCEL;
  if E.Raw[EF_VEL_X] > GLIDE_MAX_SPEED then
    E.Raw[EF_VEL_X] := GLIDE_MAX_SPEED;
  if E.Raw[EF_VEL_X] < -GLIDE_MAX_SPEED then
    E.Raw[EF_VEL_X] := -GLIDE_MAX_SPEED;

  E.Raw[EF_VEL_Y] := E.Raw[EF_VEL_Y] + GLIDE_GRAVITY;
  { The vertical limits affect horizontal velocity, shaping glide braking at
    the top and bottom of the arc. }
  if E.Raw[EF_VEL_Y] > PLAYER_TERMINAL then
    E.Raw[EF_VEL_X] := PLAYER_TERMINAL;
  if E.Raw[EF_VEL_Y] < -$100 then
    E.Raw[EF_VEL_X] := -$100;

  if Inp.Button[0] and not Inp.ButtonLatch[0] then
    E.Raw[EF_VEL_Y] := E.Raw[EF_VEL_Y] - GLIDE_LIFT;

  FaceByVelocity(E);
  E.Raw[PF_ANIM_ID] := SPR_GLIDE[FacingIndex(E)][E.Raw[PF_ANIM_FRAME] and 3];

  Inc(E.Raw[PF_ANIM_TIMER]);
  if E.Raw[EF_VEL_Y] < 0 then
    Step := GLIDE_FRAME_RISE
  else
    Step := GLIDE_FRAME_FALL;
  if E.Raw[PF_ANIM_TIMER] > Step then
  begin
    E.Raw[PF_ANIM_TIMER] := 0;
    Inc(E.Raw[PF_ANIM_FRAME]);
    if E.Raw[PF_ANIM_FRAME] > 3 then
      E.Raw[PF_ANIM_FRAME] := 0;
  end;

  MoveAndCollide(E, L, World, HitX, HitY);

  if HitX or HitY then
  begin
    World.Spawn(2, 8, E.Raw[EF_POS_X] - POSITION_BIAS, E.Raw[EF_POS_Y] - POSITION_BIAS);
    World.PlaySound(SND_GLIDE);
    E.Raw[PF_STATE] := PS_GROUND;
    E.Raw[PF_STATE_BEFORE] := 0;
    E.Raw[PF_RIDING] := 0;
    E.Raw[PF_ANIM_TIMER] := 0;
    E.Raw[PF_AIR_VX] := 0;
    E.Raw[EF_VEL_X] := 0;
    E.Raw[EF_VEL_Y] := 0;
  end;
end;

procedure UpdateAirDash(var E: TEntity; var P: TPlayerState; var L: TLayerInfo;
                        World: TPlayerWorld);
var
  HitX, HitY: Boolean;
begin
  { No gravity term at all - this is the only movement state without one. }
  ApproachZero(E.Raw[EF_VEL_X], AIRDASH_FRICTION);
  FaceByVelocity(E);
  E.Raw[PF_ANIM_ID] := SPR_AIRDASH[FacingIndex(E)][E.Raw[PF_ANIM_FRAME] and 1];

  Inc(E.Raw[PF_ANIM_TIMER]);
  if E.Raw[PF_ANIM_TIMER] > 3 then
  begin
    E.Raw[PF_ANIM_TIMER] := 0;
    Inc(E.Raw[PF_ANIM_FRAME]);
    if E.Raw[PF_ANIM_FRAME] > 1 then
      E.Raw[PF_ANIM_FRAME] := 0;
  end;

  MoveAndCollide(E, L, World, HitX, HitY);

  if HitX or HitY or (E.Raw[EF_VEL_X] = 0) then
  begin
    World.Spawn(2, 8, E.Raw[EF_POS_X] - POSITION_BIAS, E.Raw[EF_POS_Y] - POSITION_BIAS);
    World.PlaySound(SND_AIRDASH);
    E.Raw[PF_STATE] := PS_LANDING;
    E.Raw[PF_STATE_BEFORE] := 0;
    E.Raw[PF_RIDING] := 0;
    E.Raw[PF_LAND_FRAMES] := AIRDASH_RECOVER;
    E.Raw[PF_ANIM_TIMER] := 0;
    E.Raw[PF_AIR_VX] := 0;
    E.Raw[EF_VEL_X] := 0;
    E.Raw[EF_VEL_Y] := 0;
    E.Raw[EF_DEATH_TIMER] := 0;
    E.Raw[EF_TIMER] := 0;
  end;
end;

procedure UpdateKnockback(var E: TEntity; var P: TPlayerState; var L: TLayerInfo;
                          World: TPlayerWorld);
var
  ScrollX, ScrollY, Landed, BlockedX, BlockedY: Boolean;
  I, Slot: Integer;
begin
  { One sprite per facing; this state has no animation at all. }
  E.Raw[PF_ANIM_ID] := SPR_KNOCKBACK[FacingIndex(E)];

  ScrollX := ShouldScrollX(L, EntityPixelX(E), E.Raw[EF_VEL_X]);
  BlockedX := World.TileAtX(E, E.Raw[EF_VEL_X], ScrollX) >= World.SolidThreshold;
  if BlockedX then
    E.Raw[EF_VEL_X] := World.EdgeDistX(E, E.Raw[EF_VEL_X]);
  ApplyMoveX(L, E.Raw[EF_POS_X], E.Raw[EF_VEL_X], ScrollX, BlockedX);

  { GRAVITY, not PLAYER_GRAVITY - knocked back you fall like loose scenery. }
  E.Raw[EF_VEL_Y] := E.Raw[EF_VEL_Y] + GRAVITY;
  if E.Raw[EF_VEL_Y] > PLAYER_TERMINAL then
    E.Raw[EF_VEL_Y] := PLAYER_TERMINAL;

  ScrollY := ShouldScrollY(L, EntityPixelY(E), E.Raw[EF_VEL_Y]);
  Landed := (World.TileAtY(E, $20, ScrollY) >= World.SolidThreshold) and
            (E.Raw[EF_VEL_Y] >= 0);
  BlockedY := World.TileAtY(E, E.Raw[EF_VEL_Y], ScrollY) >= World.SolidThreshold;
  if BlockedY then
    E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
  ApplyMoveY(L, E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y], ScrollY, BlockedY,
             @E, World);

  if not Landed then
    Exit;

  E.Raw[PF_STATE] := PS_LANDING;
  E.Raw[PF_LANDED] := 0;
  E.Raw[PF_FALL_FRAMES] := 0;
  E.Raw[PF_STATE_BEFORE] := 0;
  E.Raw[PF_LAND_FRAMES] := KNOCKBACK_RECOVER;
  E.Raw[PF_ANIM_TIMER] := 0;
  E.Raw[PF_AIR_VX] := 0;
  E.Raw[EF_VEL_X] := 0;

  if P.Lives <> 0 then
    Exit;

  { Out of lives: three souls leave at headings 0, $14 and $28. }
  for I := 0 to DEATH_SOULS - 1 do
  begin
    Slot := World.Spawn(2, 9, E.Raw[EF_POS_X] - POSITION_BIAS,
                        E.Raw[EF_POS_Y] - POSITION_BIAS - $200);
    World.SetSpawnField(Slot, EF_FACING, I * DEATH_SOUL_STEP);
  end;
  { Stop stage music before playing the death effect. }
  World.StopMusic;
  World.PlaySound(SND_DEATH);
  E.Raw[PF_STATE] := PS_DYING;
  E.Raw[PF_ANIM_FRAME] := 0;
  E.Raw[EF_DEATH_TIMER] := 0;
  E.Raw[EF_TIMER] := $E10;
end;

{ ---------------------------------------------------------------------------
  Player_Update itself.
  --------------------------------------------------------------------------- }

{ Both death states finish by entering the game-over screen:

      if (++timer < 0x79) return;
      p_GameState   := 100;    the game-over screen
      p_ScreenPhase := 0;

  GameStateValue and ScreenPhase are shared globals rather than the by-value
  AGameState parameter. }
procedure EnterGameOver;
begin
  GameStateValue := GS_PLAY_ALT;
  ScreenPhase := 0;
end;

procedure PlayerUpdate(var E: TEntity; var P: TPlayerState;
                       var L: TLayerInfo; var Inp: TInputState;
                       World: TPlayerWorld; AGameState: Integer);
var
  SavedVelocityX, SpawnedSlot, WorkValue, WeaponIndex: Integer;
  ScrollX, ScrollY, BlockedX, BlockedY: Boolean;
  JumpEdge, AttackEdge: Boolean;
begin
  { The play clock runs before the gameplay-state guard. }
  Inc(P.Field11C0);
  if P.Field11C0 > 59 then
  begin
    P.Field11C0 := 0;
    Inc(P.ElapsedSec);
  end;

  { The play clock runs in every state; controller behavior runs only in play. }
  if AGameState <> GS_PLAY then
    Exit;

  P.SpawnFacing := E.Raw[EF_FACING];

  JumpEdge   := Inp.Button[0] and not Inp.ButtonLatch[0];
  AttackEdge := Inp.Button[1] and not Inp.ButtonLatch[1];

  case E.Raw[PF_STATE] of
    PS_GROUND:
      begin
        { The dash is a double tap: a direction opens a 30-frame window, and
          the same direction again inside it - with the ability unlocked -
          starts the dash. }
        if (not Inp.Moving) and (Inp.AxisX <> 0) then
        begin
          if (Inp.HoldTimer = 0) or (Inp.AxisX <> Inp.HeldX) or
             (P.Head[ABILITY_DASH] <> 1) then
          begin
            Inp.HeldX := Inp.AxisX;
            Inp.HoldTimer := DASH_TAP_WINDOW;
          end
          else
          begin
            World.PlaySound(SND_DASH_START);
            E.Raw[PF_STATE] := PS_DASH;
          end;
        end;
        E.Raw[EF_VEL_X] := Inp.AxisX shl PLAYER_WALK_SHIFT;
      end;

    PS_DASH:
      begin
        E.Raw[EF_VEL_X] := Inp.AxisX shl PLAYER_DASH_SHIFT;
        if (Inp.AxisX <> 0) or (E.Raw[PF_DASH_FRAMES] = 0) then
          E.Raw[PF_DASH_FRAMES] := DASH_STATE_FRAMES;
        if E.Raw[PF_DASH_FRAMES] <> 0 then
          Dec(E.Raw[PF_DASH_FRAMES]);
        if E.Raw[PF_DASH_FRAMES] = 1 then
        begin
          E.Raw[PF_STATE] := PS_GROUND;
          E.Raw[PF_DASH_FRAMES] := 0;
          E.Raw[EF_VEL_X] := 0;
        end;
      end;

    PS_AIRBORNE:
      begin
        E.Raw[EF_VEL_X] := E.Raw[PF_AIR_VX];

        { Up with no horizontal input, having jumped, with the glide unlocked. }
        if (Inp.AxisX = 0) and (Inp.AxisY < 0) and (E.Raw[PF_HAS_JUMPED] = 1) and
           (P.Head[ABILITY_GLIDE] = 1) then
        begin
          World.PlaySound(SND_GLIDE);
          World.Spawn(2, 8, E.Raw[EF_POS_X] - POSITION_BIAS,
                      E.Raw[EF_POS_Y] - POSITION_BIAS);
          E.Raw[PF_STATE] := PS_SPECIAL1;
          E.Raw[PF_ANIM_TIMER] := 0;
          E.Raw[PF_HAS_JUMPED] := 0;
          E.Raw[PF_ANIM_FRAME] := 0;
          E.Raw[EF_VEL_X] := 0;
          E.Raw[EF_VEL_Y] := 0;
        end;

        { Down, same conditions, with the air dash unlocked. }
        if (Inp.AxisX = 0) and (Inp.AxisY > 0) and (E.Raw[PF_HAS_JUMPED] = 1) and
           (P.Head[ABILITY_AIRDASH] = 1) then
        begin
          World.PlaySound(SND_AIRDASH);
          World.Spawn(2, 8, E.Raw[EF_POS_X] - POSITION_BIAS,
                      E.Raw[EF_POS_Y] - POSITION_BIAS);
          E.Raw[EF_DEATH_TIMER] := AIRDASH_INVULN;
          E.Raw[EF_TIMER] := AIRDASH_INVULN;
          E.Raw[PF_STATE] := PS_SPECIAL2;
          E.Raw[PF_ANIM_TIMER] := 0;
          E.Raw[PF_HAS_JUMPED] := 0;
          E.Raw[PF_ANIM_FRAME] := 0;
          E.Raw[EF_VEL_X] := DirVelX(E.Raw[EF_FACING]) shl AIRDASH_SPEED;
          E.Raw[EF_VEL_Y] := 0;
        end;
      end;

    PS_DYING:
      begin
        E.Raw[PF_ANIM_ID] := SPR_DEATH[FacingIndex(E)];
        Inc(E.Raw[PF_ANIM_TIMER]);
        if E.Raw[PF_ANIM_TIMER] < DEATH_HOLD then
          Exit;
        EnterGameOver;
        Exit;
      end;

    PS_FELL:
      begin
        if E.Raw[PF_ANIM_TIMER] = 0 then
        begin
          World.SpawnDebris(E, 0);
          { Falling silences the stage track before playing the death sound;
            an on-screen death leaves the music running. }
          World.StopMusic;
          World.PlaySound(SND_DEATH);
        end;
        E.Raw[EF_POS_X] := 0;
        E.Raw[EF_POS_Y] := 0;
        Inc(E.Raw[PF_ANIM_TIMER]);
        if E.Raw[PF_ANIM_TIMER] < DEATH_HOLD then
          Exit;
        EnterGameOver;
        Exit;
      end;
  end;

  if E.Raw[PF_STATE] = PS_SPECIAL1 then
  begin
    UpdateGlide(E, P, L, Inp, World);
    Exit;
  end;
  if E.Raw[PF_STATE] = PS_SPECIAL2 then
  begin
    UpdateAirDash(E, P, L, World);
    Exit;
  end;
  if E.Raw[PF_STATE] = PS_SPECIAL3 then
  begin
    UpdateKnockback(E, P, L, World);
    Exit;
  end;

  { --- The ordinary path -------------------------------------------------- }

  if E.Raw[PF_STATE] < PS_AIRBORNE then
    E.Raw[PF_RIDE_REF] := E.Raw[PF_RIDE_REF] - E.Raw[EF_VEL_X];

  SavedVelocityX := E.Raw[EF_VEL_X];
  if E.Raw[PF_PEND_VX] <> 0 then
  begin
    E.Raw[EF_VEL_X] := E.Raw[PF_PEND_VX];
    E.Raw[PF_PEND_VX] := 0;
  end;
  if E.Raw[PF_PEND_VY] <> 0 then
  begin
    E.Raw[EF_VEL_Y] := E.Raw[PF_PEND_VY];
    E.Raw[PF_PEND_VY] := 0;
  end;

  { While riding a solid the facing follows the INPUT, not the velocity -
    otherwise the platform's motion would keep turning the player around. }
  if E.Raw[PF_RIDING] = 1 then
  begin
    if Inp.AxisX < 0 then E.Raw[EF_FACING] := $20;
    if Inp.AxisX > 0 then E.Raw[EF_FACING] := 0;
  end
  else
    FaceByVelocity(E);

  if E.Raw[PF_STATE] < PS_AIRBORNE then
  begin
    if ((E.Raw[EF_VEL_X] = 0) or (E.Raw[PF_RIDING] <> 0)) and
       ((Inp.AxisX = 0) or (E.Raw[PF_RIDING] <> 1)) then
      E.Raw[PF_ANIM_FRAME] := 0
    else
    begin
      Inc(E.Raw[PF_ANIM_TIMER]);
      { Ground animation advances every 10 frames and dash animation every 6. }
      if E.Raw[PF_ANIM_TIMER] > E.Raw[PF_STATE] * -4 + 10 then
      begin
        E.Raw[PF_ANIM_TIMER] := 1;
        Inc(E.Raw[PF_ANIM_FRAME]);
        if E.Raw[PF_ANIM_FRAME] > 2 then
          E.Raw[PF_ANIM_FRAME] := 1;
      end;
    end;
    E.Raw[PF_ANIM_ID] :=
      SPR_GROUND[FacingIndex(E)][E.Raw[PF_STATE] * 2 + E.Raw[PF_ANIM_FRAME]];
  end;

  if E.Raw[PF_STATE] = PS_AIRBORNE then
  begin
    if E.Raw[EF_VEL_Y] < 0 then
      E.Raw[PF_ANIM_ID] := SPR_AIR[FacingIndex(E)][0]
    else
      E.Raw[PF_ANIM_ID] := SPR_AIR[FacingIndex(E)][1];
  end;

  if E.Raw[PF_STATE] = PS_LANDING then
  begin
    E.Raw[PF_ANIM_ID] := SPR_AIR[FacingIndex(E)][2];
    Dec(E.Raw[PF_ANIM_TIMER]);
    if E.Raw[PF_ANIM_TIMER] < 1 then
    begin
      E.Raw[PF_ANIM_TIMER] := 0;
      E.Raw[PF_STATE] := E.Raw[PF_STATE_BEFORE];
      if E.Raw[PF_STATE_BEFORE] > 1 then
        E.Raw[PF_STATE] := PS_GROUND;
      E.Raw[PF_ANIM_FRAME] := 0;
    end;
  end;

  if E.Raw[PF_STATE] = PS_WALLKICK then
  begin
    E.Raw[PF_ANIM_ID] := SPR_AIR[FacingIndex(E)][3];
    Inc(E.Raw[PF_ANIM_TIMER]);
    if E.Raw[PF_ANIM_TIMER] > 4 then
    begin
      E.Raw[PF_ANIM_TIMER] := 0;
      E.Raw[PF_STATE] := PS_AIRBORNE;
      E.Raw[PF_AIR_VX] := -E.Raw[PF_AIR_VX];
      World.PlaySound(SND_JUMP);
      E.Raw[EF_VEL_Y] := -$90;
      World.Spawn(2, 4, E.Raw[EF_POS_X] - POSITION_BIAS,
                  E.Raw[EF_POS_Y] - POSITION_BIAS);
    end;
  end;

  if E.Raw[PF_STATE] = PS_ATTACK then
  begin
    if E.Raw[PF_ANIM_TIMER] < 10 then
      E.Raw[PF_ANIM_ID] := SPR_AIR[FacingIndex(E)][4]
    else
      E.Raw[PF_ANIM_ID] := SPR_GROUND[FacingIndex(E)][0];
    Inc(E.Raw[PF_ANIM_TIMER]);
    if E.Raw[PF_ANIM_TIMER] > 15 then
    begin
      E.Raw[PF_ANIM_TIMER] := 0;
      E.Raw[PF_STATE] := PS_GROUND;
    end;
  end;

  { --- X --- }
  ScrollX := ShouldScrollX(L, EntityPixelX(E), E.Raw[EF_VEL_X]);
  if World.SolidCollideX(E, E.Raw[EF_VEL_X], True) then
    E.Raw[EF_VEL_X] := 0;
  BlockedX := False;
  if World.TileAtX(E, E.Raw[EF_VEL_X], ScrollX) >= World.SolidThreshold then
  begin
    E.Raw[EF_VEL_X] := World.EdgeDistX(E, E.Raw[EF_VEL_X]);
    BlockedX := True;
    { Pressed into a wall, in the air, with the wall kick unlocked. }
    if JumpEdge and (E.Raw[EF_VEL_Y] <> 0) and (P.Head[ABILITY_WALLKICK] = 1) then
    begin
      E.Raw[PF_STATE] := PS_WALLKICK;
      E.Raw[PF_ANIM_TIMER] := 0;
      E.Raw[PF_HAS_JUMPED] := 1;
    end;
  end;
  ApplyMoveX(L, E.Raw[EF_POS_X], E.Raw[EF_VEL_X], ScrollX, BlockedX);

  { Releasing jump while rising cuts it short. }
  if (not Inp.Button[0]) and (E.Raw[EF_VEL_Y] < 0) and (E.Raw[PF_JUMP_HELD] = 0) then
    E.Raw[EF_VEL_Y] := 0;

  { --- Y --- }
  ScrollY := ShouldScrollY(L, EntityPixelY(E), E.Raw[EF_VEL_Y]);
  World.SolidCollideY(E, E.Raw[PF_JUMP_PROBE] + $20, True);
  if E.Raw[PF_JUMP_PROBE] <> 0 then
    E.Raw[PF_JUMP_PROBE] := 0;

  if (World.TileAtY(E, $20, ScrollY) < World.SolidThreshold) and
     (not World.OnTopOfSolid) then
  begin
    { --- airborne --- }
    E.Raw[PF_PEND_VX] := 0;
    E.Raw[PF_PEND_VY] := 0;
    if E.Raw[EF_VEL_Y] < 1 then
      E.Raw[PF_FALL_FRAMES] := 0
    else
      Inc(E.Raw[PF_FALL_FRAMES]);
    if E.Raw[PF_FALL_FRAMES] > FALL_FRAMES_CAP then
      E.Raw[PF_FALL_FRAMES] := FALL_FRAMES_CAP;
    if E.Raw[PF_RIDING] = 1 then
      E.Raw[EF_VEL_X] := SavedVelocityX;
    E.Raw[PF_LANDED] := 0;
    E.Raw[PF_RIDING] := 0;
    if E.Raw[PF_AIR_LATCH] = 0 then
    begin
      E.Raw[PF_STATE_BEFORE] := E.Raw[PF_STATE];
      if E.Raw[EF_VEL_Y] < 0 then
        E.Raw[PF_AIR_VX] := SavedVelocityX
      else
        E.Raw[PF_AIR_VX] := 0;
      E.Raw[PF_AIR_LATCH] := 1;
    end;
    if (E.Raw[PF_STATE] <> PS_WALLKICK) and (E.Raw[PF_STATE] <> PS_ATTACK) then
      E.Raw[PF_STATE] := PS_AIRBORNE;
    E.Raw[EF_VEL_Y] := E.Raw[EF_VEL_Y] + PLAYER_GRAVITY;
    if E.Raw[EF_VEL_Y] > PLAYER_TERMINAL then
      E.Raw[EF_VEL_Y] := PLAYER_TERMINAL;
  end
  else
  begin
    { --- grounded --- }
    E.Raw[PF_AIR_LATCH] := 0;
    E.Raw[PF_JUMP_HELD] := 0;
    E.Raw[PF_HAS_JUMPED] := 0;
    if E.Raw[PF_LANDED] = 0 then
    begin
      E.Raw[PF_LANDED] := 1;
      WorkValue := E.Raw[PF_FALL_FRAMES] div 3;
      if WorkValue < FALL_HARD_THRESHOLD then
      begin
        if not World.Fading then
          World.PlaySound(SND_LAND_SOFT);
      end
      else
      begin
        World.PlaySound(SND_LAND_HARD);
        SpawnedSlot := World.Spawn(2, 3,
          E.Raw[EF_POS_X] - POSITION_BIAS - $100,
          E.Raw[EF_POS_Y] - POSITION_BIAS + $80);
        World.SetSpawnField(SpawnedSlot, EF_VEL_X, -$20);
        SpawnedSlot := World.Spawn(2, 3,
          E.Raw[EF_POS_X] - POSITION_BIAS + $100,
          E.Raw[EF_POS_Y] - POSITION_BIAS + $80);
        World.SetSpawnField(SpawnedSlot, EF_VEL_X, $20);
      end;
      E.Raw[PF_STATE] := PS_LANDING;
      E.Raw[PF_ANIM_TIMER] := WorkValue;
      if E.Raw[PF_LAND_FRAMES] <> 0 then
      begin
        E.Raw[PF_ANIM_TIMER] := E.Raw[PF_LAND_FRAMES];
        E.Raw[PF_LAND_FRAMES] := 0;
      end;
      E.Raw[EF_VEL_X] := 0;
      E.Raw[EF_VEL_Y] := 0;
    end;

    { Step onto a moving solid, then follow it. }
    if World.OnTopOfSolid and (E.Raw[PF_RIDING] = 0) and
       (E.Raw[EF_VEL_Y] >= 0) and (World.PushY < 0) then
    begin
      E.Raw[PF_RIDING] := 1;
      E.Raw[PF_RIDE_REF] := World.PushX;
    end;
    if World.OnTopOfSolid and (E.Raw[PF_RIDING] = 1) then
    begin
      E.Raw[PF_PEND_VX] := World.PushX - E.Raw[PF_RIDE_REF];
      E.Raw[EF_VEL_Y] := World.PushY + $40;
      ScrollY := ShouldScrollY(L, EntityPixelY(E), E.Raw[EF_VEL_Y]);
    end;

    if JumpEdge and (E.Raw[PF_STATE] < PS_AIRBORNE) then
    begin
      E.Raw[PF_JUMP_PROBE] := -$100;
      E.Raw[PF_HAS_JUMPED] := 1;
      E.Raw[EF_VEL_Y] := -P.JumpStrength;
      World.PlaySound(SND_JUMP);
      World.Spawn(2, 4, E.Raw[EF_POS_X] - POSITION_BIAS,
                  E.Raw[EF_POS_Y] - POSITION_BIAS);
    end;
  end;

  BlockedY := False;
  if World.TileAtY(E, E.Raw[EF_VEL_Y], ScrollY) >= World.SolidThreshold then
  begin
    if E.Raw[EF_VEL_Y] < 0 then
      World.PlaySound(SND_LAND_HARD);      { head hit the ceiling }
    E.Raw[EF_VEL_Y] := World.EdgeDistY(E, E.Raw[EF_VEL_Y]);
    BlockedY := True;
  end;
  ApplyMoveY(L, E.Raw[EF_POS_Y], E.Raw[EF_VEL_Y], ScrollY, BlockedY,
             @E, World);

  { --- attacking ---------------------------------------------------------- }
  WeaponIndex := P.Weapon;
  if (WeaponIndex < 0) or (WeaponIndex >= WEAPON_COUNT) then
    WeaponIndex := 0;

  { Only the designated charge weapon accumulates charge frames. }
  if Inp.Button[1] and (E.Raw[PF_STATE] <> PS_LANDING) and
     (E.Raw[PF_STATE] <> PS_ATTACK) and (P.Weapon = CHARGE_WEAPON) and
     (E.Raw[PF_SHOTS] < WEAPONS[WeaponIndex].MaxShots) then
  begin
    Inc(E.Raw[PF_CHARGE]);
    if E.Raw[PF_CHARGE] = CHARGE_FULL_FRAMES then
      World.PlaySound(SND_CHARGE_FULL);
    if (E.Raw[PF_CHARGE] mod CHARGE_SPARK_EVERY = 0) and
       (E.Raw[PF_CHARGE] < CHARGE_FULL_FRAMES) then
    begin
      SpawnedSlot := World.Spawn(2, 5,
        E.Raw[EF_POS_X] - POSITION_BIAS,
        E.Raw[EF_POS_Y] - POSITION_BIAS);
      World.SetSpawnField(SpawnedSlot, PF_OWNER, E.Raw[EF_SLOT]);
      WorkValue := World.RandomBelow(DIR_COUNT);
      World.SetSpawnField(SpawnedSlot, EF_FACING, WorkValue);
      World.SetSpawnField(SpawnedSlot, EF_VEL_X, DirVelX(WorkValue) shl 5);
      World.SetSpawnField(SpawnedSlot, EF_VEL_Y, DirVelY(WorkValue) shl 5);
    end;
  end;

  if (not Inp.Button[1]) and (E.Raw[PF_CHARGE] > 0) then
  begin
    if E.Raw[PF_CHARGE] >= CHARGE_FULL_FRAMES then
    begin
      Inc(E.Raw[PF_SHOTS]);
      World.PlaySound(SND_CHARGED);
      E.Raw[PF_STATE] := PS_ATTACK;
      E.Raw[PF_ANIM_TIMER] := 0;
      if E.Raw[EF_VEL_Y] = 0 then
        E.Raw[EF_VEL_X] := 0;
      SpawnedSlot := World.Spawn(1, 2,
        DirVelX(E.Raw[EF_FACING]) * $18 + E.Raw[EF_POS_X] - POSITION_BIAS,
        E.Raw[EF_POS_Y] - POSITION_BIAS - $60);
      World.SetSpawnField(SpawnedSlot, PF_OWNER, E.Raw[EF_SLOT]);
      World.SetSpawnField(SpawnedSlot, EF_VEL_X,
        DirVelX(E.Raw[EF_FACING]) div 4);
      World.SetSpawnField(SpawnedSlot, EF_STATE, 2);
      World.SetSpawnField(SpawnedSlot, PF_PROJ_LIFE,
        WEAPONS[WeaponIndex].Lifetime);
      World.SetSpawnField(SpawnedSlot, EF_HP, 8);
      World.SetSpawnField(SpawnedSlot, EF_BOX_PCT_X, $1E);
      World.SetSpawnField(SpawnedSlot, EF_BOX_PCT_Y, $1E);
      World.SetSpawnField(SpawnedSlot, EF_INSET_PCT_X, $1E);
      World.SetSpawnField(SpawnedSlot, EF_INSET_PCT_Y, $1E);
    end;
    E.Raw[PF_CHARGE] := 0;
  end;

  if AttackEdge and (E.Raw[PF_STATE] <> PS_LANDING) and
     (E.Raw[PF_STATE] <> PS_ATTACK) and
     (E.Raw[PF_SHOTS] < WEAPONS[WeaponIndex].MaxShots) then
  begin
    Inc(E.Raw[PF_SHOTS]);
    World.PlaySound(SND_ATTACK);
    E.Raw[PF_STATE] := PS_ATTACK;
    E.Raw[PF_ANIM_TIMER] := 0;
    if E.Raw[EF_VEL_Y] = 0 then
      E.Raw[EF_VEL_X] := 0;
    SpawnedSlot := World.Spawn(1, 2,
      DirVelX(E.Raw[EF_FACING]) * $C + E.Raw[EF_POS_X] - POSITION_BIAS,
      E.Raw[EF_POS_Y] - POSITION_BIAS - $60);
    World.SetSpawnField(SpawnedSlot, PF_OWNER, E.Raw[EF_SLOT]);
    World.SetSpawnField(SpawnedSlot, EF_VEL_X,
      WEAPONS[WeaponIndex].Speed * DirVelX(E.Raw[EF_FACING]));
    World.SetSpawnField(SpawnedSlot, EF_STATE, WEAPONS[WeaponIndex].ProjState);
    World.SetSpawnField(SpawnedSlot, PF_PROJ_LIFE,
      WEAPONS[WeaponIndex].Lifetime);
    if P.Weapon > 1 then
      World.SetSpawnField(SpawnedSlot, EF_HP, 2)
    else
      World.SetSpawnField(SpawnedSlot, EF_HP, 1);
  end;
end;

end.
