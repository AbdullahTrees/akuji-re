{ Shared millisecond clock for frame limiting and MIDI sequencing. On Windows,
  BeginMsClock and EndMsClock must bracket use so both timeGetTime and Sleep
  operate at one-millisecond timer resolution. }

unit MsClock;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils
{$IFDEF WINDOWS}
  , Windows, MMSystem
{$ENDIF}
  ;

{ A 32-bit millisecond count. DWord subtraction handles wraparound. }
function MsNow: DWord;

{ Windows reference-counts the timer period process-wide, so these must be
  called in pairs. }
procedure BeginMsClock;
procedure EndMsClock;

implementation

function MsNow: DWord;
begin
{$IFDEF WINDOWS}
  Result := timeGetTime;
{$ELSE}
  { Elsewhere the millisecond clock has no such granularity problem, and there
    is no timer period to raise. }
  Result := DWord(GetTickCount64);
{$ENDIF}
end;

procedure BeginMsClock;
begin
{$IFDEF WINDOWS}
  timeBeginPeriod(1);
{$ENDIF}
end;

procedure EndMsClock;
begin
{$IFDEF WINDOWS}
  timeEndPeriod(1);
{$ENDIF}
end;

end.
