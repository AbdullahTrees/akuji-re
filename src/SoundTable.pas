{ SoundTable - the game's sound-effect table, recovered from the binary.

  The 57 file names live in the executable as a statically initialised
  array[0..56] of AnsiString at VA 0x00468D50, referenced by the unit
  finalisation at 0x00452543 as _FinalizeArray(0x468D50, AnsiString, $39).
  That $39 is 57, which is how the length is known exactly rather than guessed.

  Three independent facts agree, so this table is not a hypothesis:

    - the array terminates cleanly after 57 entries; entry 57 is 'Z', the start
      of the separate key-name table used by the options screen
    - the wav/ directory holds exactly 57 files
    - the two name sets are equal - nothing in the table is missing from disk,
      nothing on disk is missing from the table

  It also explains the form resource. DDSD1.ChannelCount = 57 is not "57 voices
  of polyphony"; it is one DirectSound buffer per effect, one per name below.
  Re-triggering an effect that is still sounding restarts it rather than layering
  a second copy, and the mixer reproduces that.

  Index order is the array's own order, which is arbitrary - it is neither
  alphabetical nor grouped, so it must be preserved verbatim. The constants are
  named after the files and carry no interpretation; what any given effect is
  used for is not known until the code that triggers it is translated. }

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
  { Verbatim, in the original's order. Paths use a backslash exactly as the
    binary stores them; SoundPath below converts for the host platform. }
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
  Rel: string;
begin
  if (Index < 0) or (Index >= SOUND_COUNT) then
    Exit('');
  Rel := SoundNames[Index];
  { On Windows the stored separator is already correct, and the compiler
    folds the comparison away and warns about unreachable code - so make the
    platform split explicit rather than leaving a dead runtime branch. }
{$IFNDEF WINDOWS}
  Rel := StringReplace(Rel, '\', PathDelim, [rfReplaceAll]);
{$ENDIF}
  Result := IncludeTrailingPathDelimiter(AGameDir) + Rel;
end;

end.
