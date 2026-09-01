{ The millisecond clock. Its own unit because the frame limiter and the MIDI
  thread both need one and sit on opposite sides of the layering.

  timeGetTime, NOT GetTickCount64. It is what the binary calls, and
  GetTickCount64 is Vista and later so a Delphi 6 build could not have linked
  it - but mainly it is the wrong clock. GetTickCount64 never steps finer than
  the ~15.6 ms system tick, which made the 16 ms limiter wait two ticks (40 fps
  against the original's 62) and quantised every MIDI event.

  BeginMsClock IS NOT OPTIONAL. One setting governs both timeGetTime's
  resolution and Sleep's granularity: without timeBeginPeriod(1) a Sleep(1)
  takes ~15.6 ms and the frame rate caps near 42 however good the clock is. }

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
