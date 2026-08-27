{ MidiOut - the MIDI output device.

  Along with AudioOut this is one of only two platform-specific units in the
  sound layer; the file reader and the sequencer above it are plain Pascal.

  Windows sends to the system MIDI mapper through winmm, which is what the
  original reached indirectly: Kbgm32.dll drove the mapper too, so the same
  synth ends up making the sound. On Windows that is the built-in wavetable
  (Microsoft GS Wavetable Synth), the same GM device family the music was
  written for.

  Elsewhere this is a null device. Making other platforms audible means either
  a soft synth (FluidSynth with a GM soundfont) or ALSA sequencer output, and
  either one plugs in behind this same three-call interface - Send, SendSysEx,
  Reset. Nothing above this unit needs to change. }

unit MidiOut;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

const
  MIDI_CHANNELS = 16;

  { Controller numbers used by the player above. }
  CC_VOLUME       = 7;
  CC_ALL_SOUND_OFF = 120;
  CC_ALL_NOTES_OFF = 123;

type
  TMidiOutDevice = class
  private
    FActive: Boolean;
    FLastError: string;
{$IFDEF WINDOWS}
    FHandle: THandle;
{$ENDIF}
  public
    destructor Destroy; override;

    function Open: Boolean;
    procedure Close;

    { Short message, packed status | data1 shl 8 | data2 shl 16. }
    procedure Send(Msg: LongWord);
    procedure SendSysEx(const B: TBytes);

    { Silences every channel. Needed on stop and on track change: notes held by
      a Note On whose Note Off is never reached would otherwise sustain
      forever, which is the classic stuck-note on a MIDI player. }
    procedure Reset;

    property Active: Boolean read FActive;
    property LastError: string read FLastError;
  end;

implementation

{$IFDEF WINDOWS}
uses
  Windows, MMSystem;
{$ENDIF}

destructor TMidiOutDevice.Destroy;
begin
  Close;
  inherited Destroy;
end;

function TMidiOutDevice.Open: Boolean;
{$IFDEF WINDOWS}
var
  Res: MMRESULT;
{$ENDIF}
begin
  Result := False;
  if FActive then
    Exit(True);
{$IFDEF WINDOWS}
  Res := midiOutOpen(@FHandle, MIDI_MAPPER, 0, 0, 0);
  if Res <> MMSYSERR_NOERROR then
  begin
    FLastError := Format('midiOutOpen failed (%d)', [Res]);
    Exit;
  end;
  FActive := True;
  FLastError := '';
  Result := True;
{$ELSE}
  FLastError := 'no MIDI backend for this platform yet';
{$ENDIF}
end;

procedure TMidiOutDevice.Close;
begin
{$IFDEF WINDOWS}
  if FActive then
  begin
    Reset;
    midiOutClose(FHandle);
    FHandle := 0;
  end;
{$ENDIF}
  FActive := False;
end;

procedure TMidiOutDevice.Send(Msg: LongWord);
begin
{$IFDEF WINDOWS}
  if FActive then
    midiOutShortMsg(FHandle, Msg);
{$ENDIF}
end;

procedure TMidiOutDevice.SendSysEx(const B: TBytes);
{$IFDEF WINDOWS}
var
  Hdr: TMIDIHDR;
  Buf: PChar;
  Waited: Integer;
{$ENDIF}
begin
{$IFDEF WINDOWS}
  if (not FActive) or (Length(B) = 0) then
    Exit;

  { The driver reads the buffer asynchronously, so it must stay alive and
    prepared until MHDR_DONE comes back. The game sends exactly three SysEx
    messages, all in init.mid at startup, so a bounded wait here costs nothing
    and is far simpler than a completion callback. }
  GetMem(Buf, Length(B));
  try
    Move(B[0], Buf^, Length(B));
    FillChar(Hdr, SizeOf(Hdr), 0);
    Hdr.lpData := Buf;
    Hdr.dwBufferLength := Length(B);
    if midiOutPrepareHeader(FHandle, @Hdr, SizeOf(Hdr)) <> MMSYSERR_NOERROR then
      Exit;
    if midiOutLongMsg(FHandle, @Hdr, SizeOf(Hdr)) = MMSYSERR_NOERROR then
    begin
      Waited := 0;
      while ((Hdr.dwFlags and MHDR_DONE) = 0) and (Waited < 500) do
      begin
        Sleep(1);
        Inc(Waited);
      end;
    end;
    midiOutUnprepareHeader(FHandle, @Hdr, SizeOf(Hdr));
  finally
    FreeMem(Buf);
  end;
{$ENDIF}
end;

procedure TMidiOutDevice.Reset;
var
  Ch: Integer;
begin
  if not FActive then
    Exit;
  { midiOutReset sends Note Off to every note on every channel, but some
    drivers leave sustain pedal and sounding voices alone, so follow it with
    the two standard panic controllers. }
{$IFDEF WINDOWS}
  midiOutReset(FHandle);
{$ENDIF}
  for Ch := 0 to MIDI_CHANNELS - 1 do
  begin
    Send(LongWord($B0 or Ch) or (LongWord(CC_ALL_SOUND_OFF) shl 8));
    Send(LongWord($B0 or Ch) or (LongWord(CC_ALL_NOTES_OFF) shl 8));
  end;
end;

end.
