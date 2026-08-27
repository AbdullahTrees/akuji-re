{ AudioOut - the audio output device.

  This is the one part of the sound layer that cannot be portable, so it is the
  only part that is behind an IFDEF. Everything else - the RIFF reader, the
  mixer, the sound table, the MIDI sequencer - is plain Pascal and compiles
  anywhere.

  Windows uses waveOut from winmm. Not DirectSound, which is what the original
  used: DirectSound is deprecated, is emulated on top of WASAPI on anything
  modern, and buys nothing here now that mixing happens in AudioMixer. waveOut
  is emulated the same way, ships with every Windows, and needs no SDK.

  On other platforms the device is a null sink: the game runs, the mixer runs,
  nothing is heard. That is deliberate - a stub here keeps the tree building on
  Linux and macOS today, and adding ALSA/PulseAudio/CoreAudio (or one SDL2
  backend covering all three) means implementing Open/Close/Feed below and
  nothing else.

  Output is pulled by a dedicated thread rather than pushed from the frame loop.
  The game's frame loop is not real-time enough to feed audio - it can stall on
  a stage load, and a stalled feed is an audible dropout. }

unit AudioOut;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, WaveFile, AudioMixer;

const
  { 256 frames at 22050 Hz is 11.6 ms a block; four blocks in flight is about
    46 ms of latency. Low enough that a jump sound still feels attached to the
    jump, high enough not to underrun on a busy frame. }
  OUT_FRAMES_PER_BLOCK = 256;
  OUT_BLOCK_COUNT      = 4;

type
  TAudioOut = class
  private
    FMixer: TAudioMixer;
    FActive: Boolean;
    FThread: TThread;
    FLastError: string;
  public
    constructor Create(AMixer: TAudioMixer);
    destructor Destroy; override;

    { Opens the device and starts the feed thread. Returns False and sets
      LastError if no device is available; the game must stay playable in that
      case, so callers should not treat it as fatal. }
    function Start: Boolean;
    procedure Stop;

    property Active: Boolean read FActive;
    property LastError: string read FLastError;
  end;

implementation

{$IFDEF WINDOWS}
uses
  Windows, MMSystem;
{$ENDIF}

{$IFDEF WINDOWS}
type
  TWaveOutThread = class(TThread)
  private
    FMixer: TAudioMixer;
    FHandle: HWAVEOUT;
    FEvent: THandle;
    FHeaders: array[0..OUT_BLOCK_COUNT - 1] of TWAVEHDR;
    FBuffers: array[0..OUT_BLOCK_COUNT - 1] of PSmallInt;
    FPrepared: Boolean;
    function OpenDevice(out AError: string): Boolean;
    procedure CloseDevice;
    procedure FillAndQueue(Index: Integer);
  protected
    procedure Execute; override;
  public
    constructor Create(AMixer: TAudioMixer);
    destructor Destroy; override;
    function Open(out AError: string): Boolean;
  end;

const
  BLOCK_BYTES = OUT_FRAMES_PER_BLOCK * MIX_CHANNELS * SizeOf(SmallInt);

constructor TWaveOutThread.Create(AMixer: TAudioMixer);
begin
  FMixer := AMixer;
  FHandle := 0;
  FEvent := 0;
  FPrepared := False;
  inherited Create(True);   { suspended; Open must succeed first }
  FreeOnTerminate := False;
end;

destructor TWaveOutThread.Destroy;
begin
  CloseDevice;
  inherited Destroy;
end;

function TWaveOutThread.Open(out AError: string): Boolean;
begin
  Result := OpenDevice(AError);
end;

function TWaveOutThread.OpenDevice(out AError: string): Boolean;
var
  Fmt: TWAVEFORMATEX;
  I: Integer;
  Res: MMRESULT;
begin
  Result := False;
  AError := '';

  FEvent := CreateEvent(nil, False, False, nil);
  if FEvent = 0 then
  begin
    AError := 'CreateEvent failed';
    Exit;
  end;

  FillChar(Fmt, SizeOf(Fmt), 0);
  Fmt.wFormatTag := WAVE_FORMAT_PCM;
  Fmt.nChannels := MIX_CHANNELS;
  Fmt.nSamplesPerSec := MIX_RATE;
  Fmt.wBitsPerSample := 16;
  Fmt.nBlockAlign := MIX_CHANNELS * 2;
  Fmt.nAvgBytesPerSec := MIX_RATE * Fmt.nBlockAlign;
  Fmt.cbSize := 0;

  Res := waveOutOpen(@FHandle, WAVE_MAPPER, @Fmt, DWORD_PTR(FEvent), 0,
                     CALLBACK_EVENT);
  if Res <> MMSYSERR_NOERROR then
  begin
    AError := Format('waveOutOpen failed (%d)', [Res]);
    CloseHandle(FEvent);
    FEvent := 0;
    Exit;
  end;

  for I := 0 to OUT_BLOCK_COUNT - 1 do
  begin
    GetMem(FBuffers[I], BLOCK_BYTES);
    FillChar(FBuffers[I]^, BLOCK_BYTES, 0);
    FillChar(FHeaders[I], SizeOf(TWAVEHDR), 0);
    FHeaders[I].lpData := PChar(FBuffers[I]);
    FHeaders[I].dwBufferLength := BLOCK_BYTES;
    waveOutPrepareHeader(FHandle, @FHeaders[I], SizeOf(TWAVEHDR));
    { Mark done so the feed loop treats every block as free on the first pass. }
    FHeaders[I].dwFlags := FHeaders[I].dwFlags or WHDR_DONE;
  end;
  FPrepared := True;
  Result := True;
end;

procedure TWaveOutThread.CloseDevice;
var
  I: Integer;
begin
  if FHandle <> 0 then
  begin
    { Reset marks every queued block done, which is what lets
      waveOutUnprepareHeader succeed - unpreparing a still-queued header fails
      with WAVERR_STILLPLAYING and leaks the buffer. }
    waveOutReset(FHandle);
    if FPrepared then
      for I := 0 to OUT_BLOCK_COUNT - 1 do
        waveOutUnprepareHeader(FHandle, @FHeaders[I], SizeOf(TWAVEHDR));
    waveOutClose(FHandle);
    FHandle := 0;
  end;
  FPrepared := False;
  for I := 0 to OUT_BLOCK_COUNT - 1 do
    if FBuffers[I] <> nil then
    begin
      FreeMem(FBuffers[I]);
      FBuffers[I] := nil;
    end;
  if FEvent <> 0 then
  begin
    CloseHandle(FEvent);
    FEvent := 0;
  end;
end;

procedure TWaveOutThread.FillAndQueue(Index: Integer);
begin
  FMixer.MixInto(FBuffers[Index], OUT_FRAMES_PER_BLOCK);
  FHeaders[Index].dwFlags := FHeaders[Index].dwFlags and not WHDR_DONE;
  FHeaders[Index].dwBufferLength := BLOCK_BYTES;
  waveOutWrite(FHandle, @FHeaders[Index], SizeOf(TWAVEHDR));
end;

procedure TWaveOutThread.Execute;
var
  I: Integer;
  Queued: Boolean;
begin
  while not Terminated do
  begin
    Queued := False;
    for I := 0 to OUT_BLOCK_COUNT - 1 do
      if (FHeaders[I].dwFlags and WHDR_DONE) <> 0 then
      begin
        FillAndQueue(I);
        Queued := True;
      end;

    { The driver signals the event as each block completes. The timeout is a
      backstop: some mappers do not signal reliably when every block is still
      in flight, and waking anyway costs nothing. }
    if not Queued then
      WaitForSingleObject(FEvent, 20);
  end;
end;
{$ENDIF}

constructor TAudioOut.Create(AMixer: TAudioMixer);
begin
  inherited Create;
  FMixer := AMixer;
end;

destructor TAudioOut.Destroy;
begin
  Stop;
  inherited Destroy;
end;

function TAudioOut.Start: Boolean;
{$IFDEF WINDOWS}
var
  T: TWaveOutThread;
  Err: string;
{$ENDIF}
begin
  Result := False;
  if FActive then
    Exit(True);
  if FMixer = nil then
  begin
    FLastError := 'no mixer';
    Exit;
  end;

{$IFDEF WINDOWS}
  T := TWaveOutThread.Create(FMixer);
  if not T.Open(Err) then
  begin
    FLastError := Err;
    T.Free;
    Exit;
  end;
  FThread := T;
  T.Start;
  FActive := True;
  FLastError := '';
  Result := True;
{$ELSE}
  { Null sink - see the unit header. }
  FLastError := 'no audio backend for this platform yet';
{$ENDIF}
end;

procedure TAudioOut.Stop;
begin
  if FThread <> nil then
  begin
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  FActive := False;
end;

end.
