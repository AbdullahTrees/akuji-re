{ MsClock - the millisecond clock the original uses, and only that.

  WHY THIS IS ITS OWN UNIT

  Two places need a real millisecond clock and they sit on opposite sides of
  the layering: the frame limiter, which is the game's, and the MIDI playback
  thread, which is the component's. Neither should have to reach through the
  other to get at a timer, so the timer lives on its own down here.

  WHY NOT GetTickCount64

  It is the wrong clock and it has now caused two separate bugs.

  On Windows it only advances on the system timer tick. Measured on this
  machine, its step sizes are 15, 16, 16, 15, 16 ms - it never moves in
  smaller increments than that, whatever you ask it. timeGetTime, with the
  multimedia timer period raised, steps 1 ms flat.

    * the FRAME LIMITER proceeds when the elapsed time reaches 16 ms, so an
      elapsed of 15 failed and the frame waited for the next tick some 31 ms
      away. 40 fps measured, against the original's 62.
    * the MIDI THREAD schedules note events off the same clock. At 48 ticks
      per quarter and 120 BPM a tick is about 10.4 ms, which is SHORTER than
      one step of this clock - so every event was being quantised to a 15.6 ms
      boundary and the music came out wrong rather than merely late.

  The original calls timeGetTime. That is the whole justification: not that it
  is more precise, but that it is what the binary does. It is also the only
  one of the two that exists on the target the original was built for -
  GetTickCount64 is Vista and later, so a Delphi 6 build for XP could not link
  against it at all.

  BeginMsClock IS NOT OPTIONAL, and it is the half that is easy to miss.
  timeGetTime's resolution and Sleep's granularity are the same setting. Without
  timeBeginPeriod(1) a Sleep(1) takes about 15.6 ms, which caps the frame rate
  near 42 even with a perfect clock, and makes the sleep-instead-of-spin
  divergence (DIV-001) unworkable. Raising the period is process-wide, so
  EndMsClock gives it back on the way out. }

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
