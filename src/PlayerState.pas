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
