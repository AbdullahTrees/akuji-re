{ The 57 sound-effect slots and their file names. Slot order is part of the
  gameplay data contract and must remain unchanged. }

unit SoundTable;

{$MODE DELPHI}{$H+}

interface

const
  SOUND_COUNT = 57;   { = DDSD1.ChannelCount in the form resource }

  SND_PI      =  0;
  SND_OK      =  1;
  SND_NG      =  2;
  SND_JUMP    =  3;
  SND_YUKA01  =  4;
  SND_SHOT01  =  5;
  SND_POWER01 =  6;
  SND_SHOT02  =  7;
  SND_YUKA02  =  8;
  SND_PON01   =  9;
  SND_PON02   = 10;
  SND_VOICE01 = 11;
  SND_VOICE02 = 12;
  SND_KAKUNIN = 13;
  SND_KACHI01 = 14;
  SND_KIN01   = 15;
  SND_GET01   = 16;
  SND_HIT01   = 17;
  SND_BOM01   = 18;
  SND_POWER02 = 19;
  SND_KACHI02 = 20;
  SND_PUU01   = 21;
  SND_BOM02   = 22;
  SND_SHOT03  = 23;
  SND_OPEN01  = 24;
  SND_SHOT04  = 25;
  SND_JUMP02  = 26;
  SND_YUKA03  = 27;
  SND_PUU02   = 28;
  SND_VOICE03 = 29;
  SND_SHOT05  = 30;
  SND_WATER01 = 31;
  SND_OPEN02  = 32;
  SND_JUMP03  = 33;
  SND_BOM03   = 34;
  SND_VOICE04 = 35;
  SND_VOICE05 = 36;
  SND_POWER03 = 37;
  SND_SHOT06  = 38;
  SND_KACHI03 = 39;
  SND_WATER02 = 40;
  SND_VOICE06 = 41;
  SND_YUKA04  = 42;
  SND_SHOT07  = 43;
  SND_BELL    = 44;
  SND_PI02    = 45;
  SND_SHOT08  = 46;
  SND_MOVE01  = 47;
  SND_BOM04   = 48;
  SND_BOM05   = 49;
  SND_SHOT09  = 50;
  SND_KACHI04 = 51;
  SND_SHOT10  = 52;
  SND_RUN     = 53;
  SND_KODOU   = 54;
  SND_VOICE07 = 55;
  SND_GET02   = 56;

type
  TSoundNames = array[0..SOUND_COUNT - 1] of string;

const
  { Paths retain their Windows separators; SoundPath converts them when needed
    on another platform. }
  SoundNames: TSoundNames = (
    'wav\pi.wav', 'wav\ok.wav',
    'wav\ng.wav', 'wav\jump.wav',
    'wav\yuka01.wav', 'wav\shot01.wav',
    'wav\power01.wav', 'wav\shot02.wav',
    'wav\yuka02.wav', 'wav\pon01.wav',
    'wav\pon02.wav', 'wav\voice01.wav',
    'wav\voice02.wav', 'wav\kakunin.wav',
    'wav\kachi01.wav', 'wav\kin01.wav',
    'wav\get01.wav', 'wav\hit01.wav',
    'wav\bom01.wav', 'wav\power02.wav',
    'wav\kachi02.wav', 'wav\puu01.wav',
    'wav\bom02.wav', 'wav\shot03.wav',
    'wav\open01.wav', 'wav\shot04.wav',
    'wav\jump02.wav', 'wav\yuka03.wav',
    'wav\puu02.wav', 'wav\voice03.wav',
    'wav\shot05.wav', 'wav\water01.wav',
    'wav\open02.wav', 'wav\jump03.wav',
    'wav\bom03.wav', 'wav\voice04.wav',
    'wav\voice05.wav', 'wav\power03.wav',
    'wav\shot06.wav', 'wav\kachi03.wav',
    'wav\water02.wav', 'wav\voice06.wav',
    'wav\yuka04.wav', 'wav\shot07.wav',
    'wav\bell.wav', 'wav\pi02.wav',
    'wav\shot08.wav', 'wav\move01.wav',
    'wav\bom04.wav', 'wav\bom05.wav',
    'wav\shot09.wav', 'wav\kachi04.wav',
    'wav\shot10.wav', 'wav\run.wav',
    'wav\kodou.wav', 'wav\voice07.wav',
    'wav\get02.wav'
  );

{ The stored names are Windows-relative ('wav\pi.wav'). This joins one to a
  game directory and fixes the separator, so the same table works on a host
  where PathDelim is '/'. }
function SoundPath(const AGameDir: string; Index: Integer): string;

implementation

uses
  SysUtils;

function SoundPath(const AGameDir: string; Index: Integer): string;
var
  RelativePath: string;
begin
  if (Index < 0) or (Index >= SOUND_COUNT) then
    Exit('');
  RelativePath := SoundNames[Index];
  { On Windows the stored separator is already correct, and the compiler
    folds the comparison away and warns about unreachable code - so make the
    platform split explicit rather than leaving a dead runtime branch. }
{$IFNDEF WINDOWS}
  RelativePath := StringReplace(RelativePath, '\', PathDelim, [rfReplaceAll]);
{$ENDIF}
  Result := IncludeTrailingPathDelimiter(AGameDir) + RelativePath;
end;

end.
