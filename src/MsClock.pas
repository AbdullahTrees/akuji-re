{ MsClock - the millisecond clock, and only that.

  Its own unit because the frame limiter and the MIDI thread both need a real
  timer and sit on opposite sides of the layering.

  timeGetTime, NOT GetTickCount64, for two reasons. It is what the binary
  calls; and GetTickCount64 is Vista and later, so the Delphi 6 build this is
  reconstructing could not have linked it.

  It is also the wrong clock, which cost two bugs: GetTickCount64 never steps
  finer than the ~15.6 ms system tick, so the 16 ms frame limiter routinely
  waited two ticks (40 fps against the original's 62), and MIDI events at
  ~10.4 ms a tick were all quantised to that boundary.

  BeginMsClock IS NOT OPTIONAL. timeGetTime's resolution and Sleep's
  granularity are the same setting: without timeBeginPeriod(1) a Sleep(1)
  takes ~15.6 ms, which caps the frame rate near 42 whatever the clock does
  and makes DIV-001 unworkable. The period is process-wide, so the calls are
  reference-counted and must be paired. }

unit MsClock;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils
{$IFDEF WINDOWS}
  , Windows, MMSystem
{$ENDIF}
  ;

{ Milliseconds, 32-bit and wrapping every 49 days exactly as the original's
  does. Callers subtract in DWord so the wrap cancels. }
function MsNow: DWord;

{ Raise and release the multimedia timer period. Reference-counted by Windows,
  so these must be paired. }
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
