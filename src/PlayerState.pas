{ PlayerState - the save state. data\save.dat IS this record written
  raw: FileRead(h, p_PlayerState, 0x11E4), no header, no checksum, no version,
  so the layout below must match byte for byte or saves break.

  Offsets 10..0x119F are per-world progress flags, ONE BYTE each - not bits -
  indexed by the first four characters of an event's ParamB. Entity_Destroy
  @ 0x00461400 sets them for an opcode-5 event:

      Progress[StrToInt(Copy(event.ParamB, 1, 4))] := 1

  Checked by `akuji.exe --selftest-events <gamedir>`: all 154 opcode-5 events
  in the shipped data resolve inside the block. }

unit PlayerState;

{$MODE DELPHI}{$H+}

interface

uses
  KbgmPlayer,
  Classes, SysUtils, GameState;

{ Player_Update @ 0x004585A8 lives in Player.pas; these are the constants and
  save fields it reads. Detail and derivation: notes/player_controller.md }

const
  { EF_STATE, block A[0], selects the player's behaviour. }
  PSTATE_GROUND    = 0;
  PSTATE_DASH      = 1;    { gated by ABILITY_DASH }
  PSTATE_AIR       = 2;
  PSTATE_LANDING   = 3;    { landing recovery }
  PSTATE_WALLKICK  = 4;    { gated by ABILITY_WALLKICK }
  PSTATE_ATTACK    = 5;
  PSTATE_GLIDE     = 6;    { gated by ABILITY_GLIDE;   Player_UpdateGlide      }
  PSTATE_AIRDASH   = 7;    { gated by ABILITY_AIRDASH; Player_UpdateAirDash    }
  PSTATE_KNOCKBACK = 8;    {                           Player_UpdateKnockback  }
  PSTATE_DYING     = 9;
  PSTATE_DYING_FALL = 10;  { both dying states end at GameState 100 }

const
  { All from Player_Update. The player falls slower than loose objects, which
    use GRAVITY = 8 in Entities.pas - this is a deliberate difference in the
    original, not a discrepancy. }
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

  WEAPON_RECORD_BYTES = $10;    { the table at 0x00468E84 }

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

  { --- Ability flags, in Head. Zeroed by Game_StartOrLoad on a new game. --- }
  { Head[4..7]. PowerUp_Show @ 0x00456698 is what sets them, one per pickup
    variant, and it also names them for the screen it shows - the table at
    0x00468EF4, reached through the pointer at 0x0046D1EC:

        variant 4  'Dash    '     -> Head[4]
        variant 5  'Jump++      ' -> Head[5]
        variant 6  'Cloud   '     -> Head[6]
        variant 7  'Bat   '       -> Head[7]

    CAUTION: WALLKICK, AIRDASH and GLIDE are named for what Player.pas does
    with each flag, not for the game's own words, and the two do not obviously
    agree - 'Jump++' reads like a second jump, 'Bat' like a form. The INDICES
    are certain; the labels are a reading. }
  { PowerUp_Show's pickup variants - the value ParamA's 'A' letter carries.
    4..7 are the Head abilities below. }
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

  POWERUP_JUMP_STRENGTH = $84;   { variant 3, up from DEFAULT_FIELD11D0 }
  POWERUP_COUNT = 8;
  POWERUP_NAMES: array[0..POWERUP_COUNT - 1] of string = (
    'Fire    ', 'Fire+     ', 'Charge  ', 'Jump+     ',
    'Dash    ', 'Jump++      ', 'Cloud   ', 'Bat   ');
  { The two literals the name is concatenated between, at 0x004568B0 and
    0x004568BC. The padding above is what puts the gap in the finished
    sentence. }
  { PowerUp_Show @ 0x00456698 plays effect 0x10, STOPS the music, and starts
    playlist entry 4 without looping. Overlay_Update then ends the panel when
    that track finishes - which is the only thing that dismisses it.

    Missing all three was a softlock. The panel's dismiss condition is "the
    music has stopped", and with no fanfare ever started it was being asked of
    the LOOPING stage BGM, which never stops. Collecting the dash orb put the
    game in a state nothing could leave. }
  POWERUP_SOUND = $10;
  POWERUP_MIDI  = 4;      { AutoLoadMidis[4] }

  POWERUP_PREFIX = '  ';
  POWERUP_SUFFIX = ' was recovered! ';

  { --- Sprite tables, 0x0046BB9C..0x0046BC2C, right-facing then left -------

    To read one of these out of akuji.exe, subtract DATA_VA_BIAS from the
    address: the DATA section is mapped at 0x00401A00 above its file offset.
    (CODE is 0x00400C00 - the two differ, which has caught me out.) }
  DATA_VA_BIAS       = $00401A00;
  PLAYER_SPRITE_BASE = $0046BB9C;
  SPR_GROUND: array[0..1, 0..4] of Integer =
    ((10, 11, 12, 57, 58), (0, 1, 2, 55, 56));
  SPR_AIR: array[0..1, 0..4] of Integer =
    ((15, 14, 16, 17, 19), (5, 4, 6, 7, 9));
  SPR_GLIDE: array[0..1, 0..3] of Integer =
    ((47, 48, 49, 48), (44, 45, 46, 45));
  SPR_AIRDASH: array[0..1, 0..1] of Integer =
    ((116, 117), (114, 115));
  { 0x0046D180, indexed by facing shr 5 - Player_UpdateKnockback's only
    sprite choice; the state has no animation at all. }
  SPR_KNOCKBACK: array[0..1] of Integer = (13, 3);
  SPR_DEATH: array[0..1] of Integer = (18, 8);

  { The offset between the two facings of the base character set. }
  SPRITE_FACING_STRIDE = 10;

const
  PLAYER_STATE_SIZE = $11E4;   { 4580 - the whole of save.dat }
  PROGRESS_START    = 10;      { Game_StartOrLoad clears 0x1195 bytes from here }
  PROGRESS_LENGTH   = $1195;
  { GameState_Reset @ 0x004653C8 clears 0x1F5 bytes from offset 0xFAA in the
    struct, which is Progress[4000..4500] - the TOP 501 flags and nothing
    below them. So the block is really two: 0..3999 are the save, and 4000 up
    are per-run scratch that any reset wipes. Nothing else in the
    reconstruction had noticed the split. }
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
  DEFAULT_FIELD11C8 = 300;
  DEFAULT_FIELD11D0 = $68;     { 104 }

const
  { --- The Mana Stone goals, at 0x00468EC4 through the pointer 0x0046D2B4 ---

    Twelve ints, and exactly TWO readers in the whole binary:
    Entity_TouchPickup, which compares Counter against MANA_TARGETS[TargetIndex]
    to decide whether this stone finishes a level, and HUD_Draw, which shows the
    same value as the right-hand half of its "%3d/%-3d". That second reader is
    what confirms TargetIndex indexes this table and not something else.

    The progression is 20, 50, 70, 130, 160, 400 and then 999 - which no counter
    reaches - so index 6 is in effect a cap at six life upgrades.

    What the remaining five are for is NOT settled. 30, 90, 270, 999, 0 reads
    like a second, shorter progression, but nothing found so far selects it, and
    the table's extent is confirmed at twelve by the next pointer along. Kept as
    data rather than explained away. }
  MANA_TARGET_COUNT = 12;
  MANA_TARGET_ADDR  = $00468EC4;
  MANA_TARGET_PTR   = $0046D2B4;
  MANA_TARGETS: array[0..MANA_TARGET_COUNT - 1] of Integer =
    (20, 50, 70, 130, 160, 400, 999, 30, 90, 270, 999, 0);

type
  { Laid out to match the original exactly; the file is a raw image of it.
    Named fields are those whose meaning is established from Game_StartOrLoad,
    HUD_Draw and Stage_Begin. Everything else is kept as raw bytes rather than
    given speculative names. }
  TPlayerState = packed record
    Head:        array[0..PROGRESS_START - 1] of Byte;   // +0x0000
    Progress:    array[0..PROGRESS_LENGTH - 1] of Byte;  // +0x000A  world flags
    { +0x119F. Game_StartOrLoad clears exactly 0x1195 bytes from +10, which
      ends at +0x119E, and the first integer is at +0x11A0 - so one byte in
      between belongs to neither. It has to be here or every integer after it
      reads a byte early. That is not a hypothetical: it WAS missing, the
      record came to 4579 bytes, and the shipped save decoded as stage 3328
      with 512 lives - every value exactly 256x too big, which is the
      signature of a one-byte shift. Caught by --selftest-player. }
    Pad119F:     Byte;      // +0x119F
    SavedStage:  Integer;   // +0x11A0  copied into Settings.CurrentStage on load
    { PIXELS, not tiles - these were called SpawnTileX/Y and that was wrong.
      Stage_Begin spawns the player at (SpawnX shl 5, SpawnY shl 5), and the
      shift is the 1/32-pixel conversion, so the field itself is whole pixels.
      Three other writers agree: the event warp converts a tile argument with
      tile * TileW + SPAWN_CENTRE_X, the respawn path converts a live position
      back with OriginPixel, and Game_StartOrLoad's defaults are 96 and 115 -
      115 being 3 * 32 + 19, which is a pixel offset inside tile 3 and not a
      tile number at all. }
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
    Weapon:      Integer;   // +0x11CC  index into the weapon table at 0x468E84
    JumpStrength: Integer;  // +0x11D0  init 0x68; negated into vy on jump
    MusicTrack:  Integer;   // +0x11D4  index into the KbgmPlayer playlist
    SpawnFacing: Integer;   // +0x11D8  Player_Update copies EF_FACING here
                            //          every frame; Event sub-op 1 gives a
                            //          freshly spawned player facing 0x10
    TargetIndex: Integer;   // +0x11DC  index into HUD_Draw's 12-int goal
                            //          table at 0x00468EC4, NOT the goal itself
    Difficulty:  Integer;   // +0x11E0  copy of Settings.GameLevel
  end;

  { The one player state, by reference. The original has a single global at
    0x0046CFF0 reached through a pointer; anything that needs to write it -
    the message box answering a prompt, for one - takes this. }
  PPlayerState = ^TPlayerState;

procedure InitNewGame(var P: TPlayerState; GameLevel: Integer);
procedure ApplySessionFlags(var P: TPlayerState; GameLevel: Integer);
function LoadSave(var P: TPlayerState; const FileName: string): Boolean;
function SaveTo(const P: TPlayerState; const FileName: string): Boolean;

{ MANA_TARGETS[Index]. The original indexes it unchecked; this returns
  something unreachable past the end instead of reading whatever follows the
  table. Reachable only if TargetIndex ever passes 11, which needs the counter
  to have passed 999 first. }
function ManaTarget(Index: Integer): Integer;

{ 0x00456698. The ability pickup - what sub-op 10 reaches, and what the
  full-screen "... was recovered!" panel announces. It grants by the event
  entity's variant; see PICKUP_* above.

  The two weapon guards are why this is a chain of independent ifs and not a
  case: picking up Fire after Charge must not demote you. They are not the
  same function either - PICKUP_FIRE_PLUS refuses only WEAPON_CHARGE, so
  Fire+ over Fire+ does re-apply.

  Presentation - the panel, the fanfare, destroying the entity - is the
  caller's. This is only the state change. }
procedure PowerUpGrant(var P: TPlayerState; Variant: Integer);

{ The pickup's display name, from the table at 0x00468EF4. }
function PowerUpName(Variant: Integer): string;

type
  TStartMode = (smNewGame, smContinue);

  { What Game_StartOrLoad needs from the parts of the game this does not
    reconstruct. Opening returns True while the cutscene is still running. }
  TStartHost = class
  public
    function Opening: Boolean; virtual;
    { The flag is LOOP, not restart - it is the third argument of the
      original's play call, which the opening passes 1 for `open01` and 0 for
      `open02`. Both callers here pass True because stage music loops.

      FadeSeconds is how the PREVIOUS track is stopped, and the two branches
      below genuinely differ: a new game goes through 0x00450F74 and fades over
      two seconds, a continue goes through 0x00450F14 and stops dead. The
      value is passed to KBGMFadeOut, which ramps the volume down over that
      many seconds - see KbgmPlayer.pas for where the unit comes from. }
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

{ 0x00462F40. NEW GAME and CONTINUE are one function, separated only by the
  title's sub-mode: 0 runs the opening first and returns every frame until it
  ends; 1 does everything below and THEN reads data\save.dat over the top.

  Order carries the meaning. Defaults are written before the load, so an
  unreadable save leaves a good new game - the original checks the open and
  not the read. Session flags are applied after it, which is what makes
  difficulty a session fact rather than a saved one.

  ANOMALY, reproduced: difficulty is copied from the settings twice, the
  second guarded by `not UseArchive`. On CONTINUE the load has replaced it in
  between, so the flag silently decides whether a loaded game keeps its saved
  difficulty. DDDD1Init sets UseArchive, so the second write is dead in the
  shipped game.

  Presentation - Opening, PlayMusic - is the caller's. }
function GameStartOrLoad(var P: TPlayerState; var ASettings: TGameSettings;
                         Mode: TStartMode; Host: TStartHost;
                         UseArchive: Boolean;
                         const SaveFileName: string;
                         var AGameState: Integer): Boolean;

implementation

{ Game_StartOrLoad runs these AFTER the optional save load, so they apply to a
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
  P.EventCounter := DEFAULT_FIELD11C8;
  P.JumpStrength := DEFAULT_FIELD11D0;
  { Game_StartOrLoad writes these four zeroes explicitly rather than relying on
    the clear, which is the whole reason they could be identified: all four
    abilities start LOCKED. }
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
    { The original reads 0x11E4 unconditionally. Refuse a short file rather
      than leaving the tail of the struct holding whatever was there before. }
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
  { The original's chain of independent ifs, not a case - two of them carry
    conditions a case would invite tidying away. }
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
  { Statement 2, and it sits between the opening gate and the state write:
      00462f5f  MOV EAX,[0x0046cc14]     ; ScreenPhase
      00462f66  MOV dword ptr [EAX],EDX  ; := 0
      00462f68  MOV EAX,[0x0046d06c]
      00462f6d  MOV dword ptr [EAX],0x1e ; GameState := 30
    Stage_Begin clears it again a frame later, so nothing observable read the
    stale value - but it was a missing statement in a row marked MATCHES. }
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

  { The new game's music starts before the track number is even stored - the
    original hard-codes playlist entry 1 here and only then writes it down. }
  if Mode = smNewGame then
    Host.PlayMusic(START_MUSIC_TRACK, True, KBGM_STOP_FADE_NEWGAME);
  P.MusicTrack := START_MUSIC_TRACK;

  if Mode = smContinue then
  begin
    { A save that will not open leaves the new game standing. The original
      ignores the READ's result too, which would leave a partly-overwritten
      record on a short file; LoadSave refuses one instead, and says so. }
    if LoadSave(P, SaveFileName) then
      ASettings.CurrentStage := P.SavedStage;
    Host.PlayMusic(P.MusicTrack, True, KBGM_STOP_HARD);
  end;

  { After the load, so difficulty is a session fact and not a saved one. }
  ApplySessionFlags(P, P.Difficulty);

  { The second difficulty write. See the header - it is unreachable in the
    shipped game because DDDD1Init sets UseArchive, and it is here because
    removing it would be a change rather than a translation. }
  if not UseArchive then
  begin
    P.Difficulty := ASettings.GameLevel;
    ApplySessionFlags(P, P.Difficulty);
  end;
end;

initialization
  { A layout error here silently corrupts every save, so fail loudly at start
    rather than quietly writing a wrong-sized file.

    This was an Assert, and an Assert is NOT a check: FPC compiles assertions
    out unless -Sa is passed, so it never ran once, and the record sat a byte
    short through several commits. Written as a plain test that is always
    compiled in. }
  if SizeOf(TPlayerState) <> PLAYER_STATE_SIZE then
    raise Exception.CreateFmt(
      'TPlayerState is %d bytes; save.dat is %d and the layout must match',
      [SizeOf(TPlayerState), PLAYER_STATE_SIZE]);

end.
