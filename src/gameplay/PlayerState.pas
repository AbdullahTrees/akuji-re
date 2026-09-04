{ Persistent player state. data\save.dat is the raw 0x11E4-byte record with no
  header, checksum, or version, so field layout is a strict file contract.

  Offsets 10..0x119F are per-world progress flags, ONE BYTE each - not bits -
  indexed by the first four characters of an event's ParamB. Destroying an
  opcode-5 event sets its corresponding progress byte:

      Progress[StrToInt(Copy(event.ParamB, 1, 4))] := 1

  All event progress indices must remain within this byte array. }

unit PlayerState;

{$MODE DELPHI}{$H+}

interface

uses
  KbgmPlayer,
  Classes, SysUtils, GameState;

{ Constants and save fields used by the player controller in Player.pas. }

const
  { The player uses lower gravity than loose objects in Entities. }
  PLAYER_GRAVITY      = 4;
  PLAYER_TERMINAL     = $200;   { same cap as everything else }

  PLAYER_WALK_SHIFT   = 5;      { velocity = direction shl this }
  PLAYER_DASH_SHIFT   = 6;      { twice walking speed }
  DASH_TAP_WINDOW     = 30;     { frames to press the same direction again }
  DASH_STATE_FRAMES   = 8;

  CHARGE_FULL_FRAMES  = 60;     { when the charge sound fires }
  CHARGE_SPARK_EVERY  = 8;      { a spark entity every N frames while charging }

  FALL_FRAMES_CAP     = $5A;    { landing severity counts up to this }
  FALL_HARD_THRESHOLD = 11;     { cap div 3 compared against this }

  { The play clock the HUD shows. PlayerState +0x11C0 counts frames and rolls
    into +0x11BC every 60, so +0x11BC is seconds. }
  TICKS_PER_SECOND    = 60;

  { Player state machine, EF_STATE on the player entity. }
  PS_GROUND   = 0;
  PS_DASH     = 1;
  PS_AIRBORNE = 2;
  PS_LANDING  = 3;
  PS_WALLKICK = 4;
  PS_ATTACK   = 5;
  PS_SPECIAL1 = 6;
  PS_SPECIAL2 = 7;
  PS_SPECIAL3 = 8;
  PS_DYING    = 9;
  PS_FELL     = 10;

  { --- The three delegated states ----------------------------------------- }
  GLIDE_GRAVITY     = 2;        { against PLAYER_GRAVITY = 4 }
  GLIDE_LIFT        = $20;      { subtracted from vy on a fresh jump press }
  GLIDE_ACCEL       = 4;        { per frame, from the horizontal axis }
  GLIDE_MAX_SPEED   = $40;
  GLIDE_FRAME_RISE  = 4;        { frames per animation step while rising }
  GLIDE_FRAME_FALL  = 8;        { ... and while falling }
  AIRDASH_SPEED     = 3;        { shift applied to the direction table entry }
  AIRDASH_FRICTION  = 8;        { bled off per frame; no gravity at all }
  AIRDASH_INVULN    = $E10;     { written to EF_TIMER and EF_DEATH_TIMER }
  AIRDASH_PHASE_KIND = $5C;     { EF_VULN_KIND you pass THROUGH while dashing }
  AIRDASH_RECOVER   = 15;       { landing frames }
  KNOCKBACK_RECOVER = 30;
  DEATH_SOULS       = 3;        { spawned at headings 0, 0x14, 0x28 }
  DEATH_SOUL_STEP   = $14;

  { Ability flags in Head[4..7], indexed by pickup variant:

        variant 4  'Dash    '     -> Head[4]
        variant 5  'Jump++      ' -> Head[5]
        variant 6  'Cloud   '     -> Head[6]
        variant 7  'Bat   '       -> Head[7]

    Functional names describe Player.pas behavior even where the displayed
    pickup label differs. }
  { Pickup variants carried by ParamA kind 'A'. }
  PICKUP_FIRE       = 0;
  PICKUP_FIRE_PLUS  = 1;
  PICKUP_CHARGE     = 2;
  PICKUP_JUMP_PLUS  = 3;

  { What TPlayerState.Weapon holds. Player.pas indexes WEAPONS by it. }
  WEAPON_NONE       = 0;
  WEAPON_FIRE       = 1;
  WEAPON_FIRE_PLUS  = 2;
  WEAPON_CHARGE     = 3;

  ABILITY_DASH      = 4;
  ABILITY_WALLKICK  = 5;
  ABILITY_AIRDASH   = 6;
  ABILITY_GLIDE     = 7;

  POWERUP_JUMP_STRENGTH = $84;   { variant 3 }
  POWERUP_COUNT = 8;
  POWERUP_NAMES: array[0..POWERUP_COUNT - 1] of string = (
    'Fire    ', 'Fire+     ', 'Charge  ', 'Jump+     ',
    'Dash    ', 'Jump++      ', 'Cloud   ', 'Bat   ');
  { Power-up presentation stops stage music, plays this sound and one-shot MIDI,
    then closes when the fanfare ends. }
  POWERUP_SOUND = $10;
  POWERUP_MIDI  = 4;      { AutoLoadMidis[4] }

  POWERUP_PREFIX = '  ';
  POWERUP_SUFFIX = ' was recovered! ';

  { Player sprite tables, right-facing then left-facing. }
  SPR_GROUND: array[0..1, 0..4] of Integer =
    ((10, 11, 12, 57, 58), (0, 1, 2, 55, 56));
  SPR_AIR: array[0..1, 0..4] of Integer =
    ((15, 14, 16, 17, 19), (5, 4, 6, 7, 9));
  SPR_GLIDE: array[0..1, 0..3] of Integer =
    ((47, 48, 49, 48), (44, 45, 46, 45));
  SPR_AIRDASH: array[0..1, 0..1] of Integer =
    ((116, 117), (114, 115));
  { Knockback has one static sprite per facing. }
  SPR_KNOCKBACK: array[0..1] of Integer = (13, 3);
  SPR_DEATH: array[0..1] of Integer = (18, 8);

  { The offset between the two facings of the base character set. }
  SPRITE_FACING_STRIDE = 10;

const
  PLAYER_STATE_SIZE = $11E4;   { 4580 - the whole of save.dat }
  PROGRESS_START    = 10;      { Game_StartOrLoad clears 0x1195 bytes from here }
  PROGRESS_LENGTH   = $1195;
  { GameState_Reset clears Progress[4000..4500]; lower entries persist. }
  PROGRESS_SCRATCH_FIRST = 4000;

  DEFAULT_LIVES     = 3;
  DEFAULT_SPAWN_X   = $60;     { 96 pixels = tile 3, flush }
  DEFAULT_SPAWN_Y   = $73;     { 115 pixels = tile 3 + 19 }
  DEFAULT_SCROLL_Y  = $1C0;    { 448 pixels = tile 14 }

  { Added to a tile-numbered spawn destination. X centres across the tile; Y
    does NOT centre down - 19 puts the player's origin at its feet, and
    Game_StartOrLoad's own default carries the same 19 (115 = 3 * 32 + 19), so
    it is deliberate. The camera's scroll takes no offset on either axis. }
  SPAWN_CENTRE_X  = 16;
  SPAWN_FOOT_Y    = 19;
  DEFAULT_EVENT_COUNTER = 300;
  DEFAULT_JUMP_STRENGTH = $68;     { 104 }

const
  { Mana Stone goals used by pickup progression and the HUD.
    The progression is 20, 50, 70, 130, 160, 400 and then 999 - which no counter
    reaches - so index 6 is in effect a cap at six life upgrades.

    The remaining five entries have no known selector and are retained as game
    data. }
  MANA_TARGET_COUNT = 12;
  MANA_TARGETS: array[0..MANA_TARGET_COUNT - 1] of Integer =
    (20, 50, 70, 130, 160, 400, 999, 30, 90, 270, 999, 0);

type
  { Raw save-file layout. Unknown bytes remain unnamed rather than being given
    speculative meanings. }
  TPlayerState = packed record
    Head:        array[0..PROGRESS_START - 1] of Byte;   // +0x0000
    Progress:    array[0..PROGRESS_LENGTH - 1] of Byte;  // +0x000A  world flags
    { Required one-byte gap before the aligned integer fields. }
    Pad119F:     Byte;      // +0x119F
    SavedStage:  Integer;   // +0x11A0  copied into Settings.CurrentStage on load
    { Spawn coordinates are whole pixels; StageBegin converts them to the
      entity's 1/32-pixel representation. }
    SpawnX:      Integer;   // +0x11A4  pixels
    SpawnY:      Integer;   // +0x11A8  pixels
    ScrollX:     Integer;   // +0x11AC
    ScrollY:     Integer;   // +0x11B0
    Lives:       Integer;   // +0x11B4  HUD life icons, clamped to 0..MaxLives
    MaxLives:    Integer;   // +0x11B8  grows as Mana Stones are collected
    ElapsedSec:  Integer;   // +0x11BC  HUD timer, rendered h:mm:ss
    Field11C0:   Integer;   // +0x11C0
    Counter:     Integer;   // +0x11C4  HUD "%3d/%-3d" left-hand value
    EventCounter: Integer;  // +0x11C8  init 300. Event sub-op 11 adds a signed
                            //          amount to it and sub-op 6 compares it
                            //          against a threshold, writing the result
                            //          into Progress[1] and Progress[2]. Both
                            //          sub-ops are implemented and NEITHER is
                            //          used by any shipped event - a cut
                            //          feature, kept because the code is there.
    Weapon:      Integer;   // +0x11CC  index into Player.WEAPONS
    JumpStrength: Integer;  // +0x11D0  init 0x68; negated into vy on jump
    MusicTrack:  Integer;   // +0x11D4  index into the KbgmPlayer playlist
    SpawnFacing: Integer;   // +0x11D8  Player_Update copies EF_FACING here
                            //          every frame; Event sub-op 1 gives a
                            //          freshly spawned player facing 0x10
    TargetIndex: Integer;   // +0x11DC  index into MANA_TARGETS
    Difficulty:  Integer;   // +0x11E0  copy of Settings.GameLevel
  end;

  { Mutable player-state reference used by systems such as dialogue prompts. }
  PPlayerState = ^TPlayerState;

procedure InitNewGame(var P: TPlayerState; GameLevel: Integer);
procedure ApplySessionFlags(var P: TPlayerState; GameLevel: Integer);
function LoadSave(var P: TPlayerState; const FileName: string): Boolean;
function SaveTo(const P: TPlayerState; const FileName: string): Boolean;

{ Return MANA_TARGETS[Index], or an unreachable target for an invalid index. }
function ManaTarget(Index: Integer): Integer;

{ Grant the power-up selected by an event entity's variant.

  The two weapon guards are why this is a chain of independent ifs and not a
  case: picking up Fire after Charge must not demote you. They are not the
  same function either - PICKUP_FIRE_PLUS refuses only WEAPON_CHARGE, so
  Fire+ over Fire+ does re-apply.

  Presentation - the panel, the fanfare, destroying the entity - is the
  caller's. This is only the state change. }
procedure PowerUpGrant(var P: TPlayerState; Variant: Integer);

{ Return the pickup's padded display name. }
function PowerUpName(Variant: Integer): string;

type
  TStartMode = (smNewGame, smContinue);

  { External services used while starting or loading a game. }
  TStartHost = class
  public
    function Opening: Boolean; virtual;
    { Loop controls the new track. FadeSeconds controls how the previous track
      stops: new games fade for two seconds, while continue stops immediately. }
    procedure PlayMusic(Track: Integer; Loop: Boolean; FadeSeconds: Integer); virtual;
  end;

const
  START_STAGE       = 1;      { Settings.CurrentStage for a new game }
  START_MUSIC_TRACK = 1;      { and the playlist entry that goes with it }

  { The two persistent unlocks, and where they land. }
  PROGRESS_EXTRA_DOOR_1 = 1185;
  PROGRESS_EXTRA_DOOR_2 = 1194;

  { Progress[7..9] are zeroed EXPLICITLY, on top of the bulk clear that has
    already zeroed them, and before the load rather than after it. The
    redundancy is the tell that they mean something - 7 and 8 are both used as
    alternative guards in the shipped scripts - and the placement is the
    difference that matters: unlike the session flags, a CONTINUE keeps
    whatever the save holds for them. }
  PROGRESS_NEWGAME_FIRST = 7;
  PROGRESS_NEWGAME_LAST  = 9;

{ Start a new game or continue from data\save.dat. A new game waits for the
  opening; continue overlays saved state on initialized defaults.

  Order carries the meaning. Defaults are written before the load, so an
  unreadable save leaves valid defaults. Session flags are applied after it,
  which makes
  difficulty a session fact rather than a saved one.

  Compatibility behavior: when archives are disabled, settings difficulty is
  copied a second time after loading and replaces the saved difficulty.

  Presentation - Opening, PlayMusic - is the caller's. }
function GameStartOrLoad(var P: TPlayerState; var ASettings: TGameSettings;
                         Mode: TStartMode; Host: TStartHost;
                         UseArchive: Boolean;
                         const SaveFileName: string;
                         var AGameState: Integer): Boolean;

implementation

{ Apply these after the optional save load, so they affect a
  continued game as well as a new one - they are session facts, not saved ones.

  Progress[0] is forced to 1 unconditionally, which is why every event
  alternative guarded on flag 0000 is the always-true default: the guard can
  never be false, and the scan that picks an alternative runs backwards, so the
  0000 one is written first precisely because it is reached last.

  Difficulty is published as a progress flag too, so scripts could branch on
  it. No shipped event guards on 5, 6 or 10 - the mechanism exists and is
  unused, like EventCounter above. }
procedure ApplySessionFlags(var P: TPlayerState; GameLevel: Integer);
begin
  P.Progress[0] := 1;
  P.Progress[5] := 0;
  P.Progress[6] := 0;
  P.Progress[10] := 0;
  case GameLevel of
    0: P.Progress[10] := 1;
    1: P.Progress[5]  := 1;
    2: P.Progress[6]  := 1;
  end;
end;

procedure InitNewGame(var P: TPlayerState; GameLevel: Integer);
begin
  FillChar(P, SizeOf(P), 0);
  P.Lives      := DEFAULT_LIVES;
  P.MaxLives   := DEFAULT_LIVES;
  P.SpawnX := DEFAULT_SPAWN_X;
  P.SpawnY := DEFAULT_SPAWN_Y;
  P.ScrollX    := 0;
  P.ScrollY    := DEFAULT_SCROLL_Y;
  P.EventCounter := DEFAULT_EVENT_COUNTER;
  P.JumpStrength := DEFAULT_JUMP_STRENGTH;
  { All movement abilities start locked. }
  P.Head[ABILITY_DASH]     := 0;
  P.Head[ABILITY_WALLKICK] := 0;
  P.Head[ABILITY_AIRDASH]  := 0;
  P.Head[ABILITY_GLIDE]    := 0;
  ApplySessionFlags(P, GameLevel);
  P.MusicTrack := 1;
  P.Difficulty := GameLevel;
end;

function LoadSave(var P: TPlayerState; const FileName: string): Boolean;
var
  Stream: TFileStream;
begin
  Result := False;
  if not FileExists(FileName) then
    Exit;
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    { Refuse a short file rather than leaving part of the state uninitialized. }
    if Stream.Size < PLAYER_STATE_SIZE then
      Exit;
    Stream.ReadBuffer(P, PLAYER_STATE_SIZE);
    Result := True;
  finally
    Stream.Free;
  end;
end;

function SaveTo(const P: TPlayerState; const FileName: string): Boolean;
var
  Stream: TFileStream;
begin
  Result := False;
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(P, PLAYER_STATE_SIZE);
    Result := True;
  finally
    Stream.Free;
  end;
end;

function ManaTarget(Index: Integer): Integer;
begin
  if (Index < 0) or (Index >= MANA_TARGET_COUNT) then
    Exit(MaxInt);
  Result := MANA_TARGETS[Index];
end;

function PowerUpName(Variant: Integer): string;
begin
  if (Variant < 0) or (Variant >= POWERUP_COUNT) then
    Exit('');
  Result := POWERUP_NAMES[Variant];
end;

procedure PowerUpGrant(var P: TPlayerState; Variant: Integer);
begin
  { Independent conditions prevent weaker weapon pickups from demoting a
    stronger weapon. }
  if (Variant = PICKUP_FIRE) and (P.Weapon = WEAPON_NONE) then
    P.Weapon := WEAPON_FIRE;
  if (Variant = PICKUP_FIRE_PLUS) and (P.Weapon <> WEAPON_CHARGE) then
    P.Weapon := WEAPON_FIRE_PLUS;
  if Variant = PICKUP_CHARGE then
    P.Weapon := WEAPON_CHARGE;
  if Variant = PICKUP_JUMP_PLUS then
    P.JumpStrength := POWERUP_JUMP_STRENGTH;
  if (Variant >= ABILITY_DASH) and (Variant <= ABILITY_GLIDE) then
    P.Head[Variant] := 1;
end;

function TStartHost.Opening: Boolean;
begin
  Result := False;
end;

procedure TStartHost.PlayMusic(Track: Integer; Loop: Boolean; FadeSeconds: Integer);
begin
end;

function GameStartOrLoad(var P: TPlayerState; var ASettings: TGameSettings;
                         Mode: TStartMode; Host: TStartHost;
                         UseArchive: Boolean;
                         const SaveFileName: string;
                         var AGameState: Integer): Boolean;
var
  I: Integer;
begin
  { The cutscene gates only the new-game path, and while it runs NOTHING below
    happens - not even the game state changes. }
  if (Mode = smNewGame) and Host.Opening then
    Exit(False);

  Result := True;
  { Start from a clean screen phase and enter stage initialization. }
  ScreenPhase := 0;
  AGameState := GS_STAGE_BEGIN;

  InitNewGame(P, ASettings.GameLevel);

  { Copied in before the load, so they apply to a continued game too. }
  if ASettings.ExtraDoor1 = 1 then
    P.Progress[PROGRESS_EXTRA_DOOR_1] := 1;
  if ASettings.ExtraDoor2 = 1 then
    P.Progress[PROGRESS_EXTRA_DOOR_2] := 1;

  for I := PROGRESS_NEWGAME_FIRST to PROGRESS_NEWGAME_LAST do
    P.Progress[I] := 0;

  ASettings.CurrentStage := START_STAGE;

  { Start and remember the initial stage track. }
  if Mode = smNewGame then
    Host.PlayMusic(START_MUSIC_TRACK, True, KBGM_STOP_FADE_NEWGAME);
  P.MusicTrack := START_MUSIC_TRACK;

  if Mode = smContinue then
  begin
    { A missing or invalid save leaves the initialized defaults intact. }
    if LoadSave(P, SaveFileName) then
      ASettings.CurrentStage := P.SavedStage;
    Host.PlayMusic(P.MusicTrack, True, KBGM_STOP_HARD);
  end;

  { After the load, so difficulty is a session fact and not a saved one. }
  ApplySessionFlags(P, P.Difficulty);

  { Loose-file mode takes difficulty from current settings after loading. }
  if not UseArchive then
  begin
    P.Difficulty := ASettings.GameLevel;
    ApplySessionFlags(P, P.Difficulty);
  end;
end;

initialization
  { Keep this runtime check active even when compiler assertions are disabled. }
  if SizeOf(TPlayerState) <> PLAYER_STATE_SIZE then
    raise Exception.CreateFmt(
      'TPlayerState is %d bytes; save.dat is %d and the layout must match',
      [SizeOf(TPlayerState), PLAYER_STATE_SIZE]);

end.
