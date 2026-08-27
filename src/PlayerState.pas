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
      6   a special move, delegated to 0x004593B0
      7   a second special move, delegated to 0x00459624
      8   a third, delegated to 0x00459828
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

  Both are limited by a weapon table at 0x0046CD44, indexed by the current
  weapon in PlayerState +0x11CC, with 16-byte records:

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

  WEAPON_RECORD_BYTES = $10;    { the table at 0x0046CD44 }

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
    Field11C8:   Integer;   // +0x11C8  init 300
    Field11CC:   Integer;   // +0x11CC
    Field11D0:   Integer;   // +0x11D0  init 0x68
    MusicTrack:  Integer;   // +0x11D4  index into the KbgmPlayer playlist
    Field11D8:   Integer;   // +0x11D8  passed to the spawned player entity
    TargetIndex: Integer;   // +0x11DC  index into HUD_Draw's 12-int goal
                            //          table at 0x00468EC4, NOT the goal itself
    Difficulty:  Integer;   // +0x11E0  copy of Settings.GameLevel
  end;

procedure InitNewGame(var P: TPlayerState; GameLevel: Integer);
function LoadSave(var P: TPlayerState; const FileName: string): Boolean;
function SaveTo(const P: TPlayerState; const FileName: string): Boolean;

implementation

procedure InitNewGame(var P: TPlayerState; GameLevel: Integer);
begin
  FillChar(P, SizeOf(P), 0);
  P.Lives      := DEFAULT_LIVES;
  P.MaxLives   := DEFAULT_LIVES;
  P.SpawnTileX := DEFAULT_SPAWN_X;
  P.SpawnTileY := DEFAULT_SPAWN_Y;
  P.ScrollX    := 0;
  P.ScrollY    := DEFAULT_SCROLL_Y;
  P.Field11C8  := DEFAULT_FIELD11C8;
  P.Field11D0  := DEFAULT_FIELD11D0;
  P.MusicTrack := 1;
  P.Difficulty := GameLevel;
  { The original also sets a handful of single bytes in Head (4..7, 0xF, 0x10,
    0x11..0x13, 0x14) and byte 10 of Progress, plus a difficulty-selected flag
    among 0x14 / 0x0F / 0x10. Those are not reproduced until their meanings are
    known - guessing here would corrupt saves. }
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
    rather than quietly writing a wrong-sized file. }
  Assert(SizeOf(TPlayerState) = PLAYER_STATE_SIZE,
         'TPlayerState must be exactly 4580 bytes to match save.dat');

end.
