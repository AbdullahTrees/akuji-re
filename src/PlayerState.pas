{ PlayerState - the game's save state, translated from Game_StartOrLoad
  @ 0x00462F40.

  data\save.dat IS this struct, written raw:

      Delphi_FileRead(handle, p_PlayerState, 0x11E4)

  0x11E4 = 4580, and the shipped save.dat is exactly 4580 bytes. There is no
  header, no checksum and no versioning - the file is a memory image, so the
  layout below has to match byte for byte or saves break.

  Decoding the shipped save gives a coherent mid-game state: stage 13, lives 2
  of a maximum 4, 9:10 elapsed. Max lives having grown past the initial 3
  matches the in-game dialogue in tk001.dat about Mana Stones increasing LIFE,
  which is independent corroboration that these offsets are right.

  Most of the struct - offsets 10 through 0x119F, which Game_StartOrLoad clears
  as a single 0x1195-byte block - is per-world progress flags. Two known ones
  are 0x4AB and 0x4B4, set from settings bytes +0x1C and +0x1D.

  HOW THE FLAGS ARE SET is decoded. Entity_Destroy @ 0x00461400, on an entity
  carrying an event whose opcode is 5, does

      Progress[StrToInt(Copy(event.ParamB, 1, 4))] := 1

  - one BYTE per flag, not one bit, indexed by the first four characters of the
  event's second string parameter. See EventScripts.pas.

  That reading is corroborated by the data rather than only by the code: all
  154 opcode-5 events across the 66 shipped event files resolve to an index
  inside this block, which a wrong interpretation of the parameter would not
  do. Run `akuji.exe --selftest-events <gamedir>`. }

unit PlayerState;

{$MODE DELPHI}{$H+}

interface


uses
  Classes, SysUtils;

{ ===========================================================================
  The player controller - Player_Update @ 0x004585A8, the type 1 handler.

  Ghidra could not find this one: it is frameless, so Function Start Search
  never matched it, and it had to be created explicitly. It is the single
  largest piece of game behaviour in the binary.

  ## The state machine

  The state lives in the entity's EF_STATE (block A[0]) and drives everything:

      0   on the ground, walking or standing
      1   dashing
      2   airborne
      3   landing recovery
      4   wall kick
      5   attacking
      6   gliding      - Player_UpdateGlide     0x004593B0
      7   air dashing  - Player_UpdateAirDash   0x00459624
      8   knocked back - Player_UpdateKnockback 0x00459828
      9   dying - after 0x79 frames, GameState := 100 (game over)
     10   dying by falling - spawns debris, then the same

  States 9 and 10 both end at GameState 100, which is the game-over screen
  recovered earlier from a completely different direction.

  ## The dash is a double tap, and the game says so

  In state 0, pressing a direction stores it and opens a 30-frame window. Press
  the SAME direction again inside that window, with the ability flag at
  PlayerState[4] set, and the state becomes 1 with sound 21 - puu01.wav.

  tk001.dat, the game's own tutorial text, reads:

      "Press the arrow key twice to perform a Dash move."

  Three independent sources agreeing - the code, the sound table, and the
  script the game shows the player - is about as good as evidence gets here.

  Dashing moves at dir shl 6 against dir shl 5 walking, so exactly double.

  ## The three delegated states, and the four abilities

  States 6, 7 and 8 are handled by their own functions rather than inline. All
  three were frameless and had to be created by hand.

  6 - GLIDE, entered from the air by pressing UP with no horizontal input,
      after having jumped. Gravity is 2 instead of 4, holding jump adds -0x20
      of lift each frame, and steering is +-4 per frame capped at +-0x40 - a
      quarter of walking speed. A four-frame wing flap, A-B-C-B. Touching
      anything ends it: effect, sound 9, back to state 0.

  7 - AIR DASH, entered from the air by pressing DOWN, same conditions. It has
      NO gravity term at all - it is purely horizontal, launched at the facing
      direction times 8 and bled off by 8 per frame until it stops. It also
      sets both EF_TIMER and EF_DEATH_TIMER to 0xE10, and Entity_SolidCollideX
      and ...Y both skip solids whose EF_VULN_KIND is 0x5C while the mover is
      in state 7: you pass through those while dashing. Ends on contact or when
      the speed reaches zero: effect, sound 10, state 3 with a 15-frame
      recovery.

  8 - KNOCKBACK. No input is read at all and there is no animation, just one
      sprite per facing. It falls at the ordinary GRAVITY of 8 - faster than
      the player's own 4 - and on landing goes to state 3 with a 30-frame
      recovery. If Lives has reached 0 by then it instead spawns three souls at
      headings 0, 0x14 and 0x28, plays sound 12 and enters state 9.

  Each of 6 and 7 is gated on an ABILITY BYTE, and so are the dash and the wall
  kick. Game_StartOrLoad sets all four to zero on a new game; nothing else in
  the binary writes them, so they are set by the event scripts as the game is
  played.

      Head[4]  double-tap dash      state 1
      Head[5]  wall kick            state 4
      Head[6]  air dash             state 7
      Head[7]  glide                state 6

  The shipped mid-game save has Head[4] = 1 and Head[5..7] = 0, which is what a
  progression that teaches the dash first should look like - and tk001.dat, the
  game's own tutorial text, teaches exactly the dash. Three sources agreeing.

  ## Every sound matches its name

  Not one of these was chosen to fit; they are what the handler passes, and the
  names come from the array recovered during the audio work:

      jump                 3   jump.wav
      land, hard           4   yuka01.wav      (yuka is Japanese for floor)
      attack               5   shot01.wav
      charge reaches full  6   power01.wav
      charged shot         7   shot02.wav
      land, soft           8   yuka02.wav
      dash starts         21   puu01.wav
      death               12   voice02.wav

  The hard/soft landing split is on fall distance: the handler counts frames of
  downward motion in block A[3], capped at 0x5A, and divides by 3. Under 11 it
  plays the soft sound; at or over, the hard one plus two type-3 dust entities
  thrown left and right.

  ## Attacking

  Two attacks share state 5, chosen by how long the button is held:

    tapped   sound 5, one type 2 projectile
    held     a counter climbs to 60; sound 6 fires at exactly 60, and every 8th
             frame before that spawns a type 5 spark. Releasing after 60 plays
             sound 7 and fires a faster projectile.

  ## The sprite tables

  Every state picks its sprite out of a table indexed by (Facing shr 5), i.e.
  0 for right and 1 for left. The six tables are CONTIGUOUS in the image, in
  state order, with no gaps:

      0x0046BB9C   5 per side   ground and dash    states 0, 1
      0x0046BBC4   5 per side   rise, fall, land, wall kick, attack
      0x0046BBEC   4 per side   glide              state 6
      0x0046BC0C   2 per side   air dash           state 7
      0x0046BC1C   1 per side   knockback          state 8
      0x0046BC24   1 per side   death              state 9
      0x0046BC2C   end

  Each table's width is exactly the frame count its handler cycles through, and
  every table ends precisely where the next begins. Getting any stride wrong
  would break that fit somewhere along the chain.

  In the first two tables the right-facing sprite is always the left-facing one
  PLUS TEN - 10/0, 11/1, 15/5, 19/9 and so on - so sprites 0..9 are one facing
  of the base character and 10..19 the other. That relation is what fixes the
  index order as right-then-left rather than the reverse, and it is checked by
  --selftest-player.

  Both attacks are limited by a weapon table, reached through the pointer at
  0x0046CD44 and living at 0x00468E84, indexed by the current weapon in
  PlayerState +0x11CC, with 16-byte records:

      +0x00  how many of this shot may exist at once
      +0x04  speed, multiplied by the direction table entry
      +0x08  the value written to the projectile's block A[0]
      +0x0C  the projectile's lifetime

  =========================================================================== }

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
  GLIDE_LIFT        = $20;      { subtracted from vy while jump is held }
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
  ABILITY_DASH      = 4;
  ABILITY_WALLKICK  = 5;
  ABILITY_AIRDASH   = 6;
  ABILITY_GLIDE     = 7;

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
  SPR_KNOCKBACK: array[0..1] of Integer = (13, 3);
  SPR_DEATH: array[0..1] of Integer = (18, 8);

  { The offset between the two facings of the base character set. }
  SPRITE_FACING_STRIDE = 10;

const
  PLAYER_STATE_SIZE = $11E4;   { 4580 - the whole of save.dat }
  PROGRESS_START    = 10;      { Game_StartOrLoad clears 0x1195 bytes from here }
  PROGRESS_LENGTH   = $1195;

  DEFAULT_LIVES     = 3;
  DEFAULT_SPAWN_X   = $60;     { 96 }
  DEFAULT_SPAWN_Y   = $73;     { 115 }
  DEFAULT_SCROLL_Y  = $1C0;    { 448 }
  DEFAULT_FIELD11C8 = 300;
  DEFAULT_FIELD11D0 = $68;     { 104 }

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
    SpawnTileX:  Integer;   // +0x11A4
    SpawnTileY:  Integer;   // +0x11A8
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

procedure InitNewGame(var P: TPlayerState; GameLevel: Integer);
procedure ApplySessionFlags(var P: TPlayerState; GameLevel: Integer);
function LoadSave(var P: TPlayerState; const FileName: string): Boolean;
function SaveTo(const P: TPlayerState; const FileName: string): Boolean;

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
  P.SpawnTileX := DEFAULT_SPAWN_X;
  P.SpawnTileY := DEFAULT_SPAWN_Y;
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
  S: TFileStream;
begin
  Result := False;
  if not FileExists(FileName) then
    Exit;
  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    { The original reads 0x11E4 unconditionally. Refuse a short file rather
      than leaving the tail of the struct holding whatever was there before. }
    if S.Size < PLAYER_STATE_SIZE then
      Exit;
    S.ReadBuffer(P, PLAYER_STATE_SIZE);
    Result := True;
  finally
    S.Free;
  end;
end;

function SaveTo(const P: TPlayerState; const FileName: string): Boolean;
var
  S: TFileStream;
begin
  Result := False;
  S := TFileStream.Create(FileName, fmCreate);
  try
    S.WriteBuffer(P, PLAYER_STATE_SIZE);
    Result := True;
  finally
    S.Free;
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
