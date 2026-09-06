{ Helpers shared by the self-test units: locating the reference executable
  and the bias between its data addresses and its file offsets. }

unit TestSupport;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, TypInfo,
  QdaArchive, SoundTable, WaveFile, AudioMixer, AudioOut, MidiFile, KbgmPlayer,
  Directions, Entities, EventScripts, EventCommands, PlayerState, GameState,
  Stages, Camera, TileMaps, Player, EntityHandlers, EventRunner, GameSession,
  SpritePool, Sprites, Dialogue, BgAnime, UnitInit, Title, Ending, Opening,
  GameFont, DDDDComponent, Surfaces;

const
  { A data address in the reference executable minus this is its file offset.
    The CODE section uses a different bias, $00400C00, which is why this one is
    named rather than inlined. }
  DATA_VA_BIAS       = $00401A00;

  { Where the player's sprite tables start, right-facing then left. }
  PLAYER_SPRITE_BASE = $0046BB9C;

{ The reference executable, or '' if it is not beside the game data. Its size
  and a known string are both checked, so a differential test cannot silently
  end up comparing this build against itself. }
function OriginalExe(const GameDir: string): string;

implementation

{ Locate the 502784-byte reference executable. Size and a known data string are
  checked so differential tests cannot accidentally compare the build with
  itself. }
function OriginalExe(const GameDir: string): string;
const
  ORIGINAL_BYTES = 502784;
var
  Dir: string;

  function LooksLikeOriginal(const FileName: string): Boolean;
  var
    Stream: TFileStream;
    Buffer: array[0..15] of Char;
  begin
    Result := False;
    if not FileExists(FileName) then
      Exit;
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      if Stream.Size <> ORIGINAL_BYTES then
        Exit;
      { 0x004568BC in the CODE section: VA - 0x400C00 is the file offset. }
      Stream.Position := $004568BC - $00400C00;
      Stream.ReadBuffer(Buffer, SizeOf(Buffer));
      Result := Buffer = ' was recovered! ';
    finally
      Stream.Free;
    end;
  end;

begin
  Dir := IncludeTrailingPathDelimiter(GameDir);
  Result := Dir + 'akuji_source.exe';
  if LooksLikeOriginal(Result) then
    Exit;
  Result := Dir + 'akuji.exe';
  if LooksLikeOriginal(Result) then
    Exit;
  Result := '';
end;

end.
