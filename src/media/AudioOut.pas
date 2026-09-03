{ Platform audio output. Windows streams the software mixer through waveOut;
  other platforms use a silent sink. A dedicated thread keeps device feeding
  independent of frame stalls. }

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
  WaveFormat: TWAVEFORMATEX;
  BlockIndex: Integer;
  OpenResult: MMRESULT;
begin
  Result := False;
  AError := '';

  FEvent := CreateEvent(nil, False, False, nil);
  if FEvent = 0 then
  begin
    AError := 'CreateEvent failed';
    Exit;
  end;

  FillChar(WaveFormat, SizeOf(WaveFormat), 0);
  WaveFormat.wFormatTag := WAVE_FORMAT_PCM;
  WaveFormat.nChannels := MIX_CHANNELS;
  WaveFormat.nSamplesPerSec := MIX_RATE;
  WaveFormat.wBitsPerSample := 16;
  WaveFormat.nBlockAlign := MIX_CHANNELS * 2;
  WaveFormat.nAvgBytesPerSec := MIX_RATE * WaveFormat.nBlockAlign;
  WaveFormat.cbSize := 0;

  OpenResult := waveOutOpen(@FHandle, WAVE_MAPPER, @WaveFormat,
                            DWORD_PTR(FEvent), 0, CALLBACK_EVENT);
  if OpenResult <> MMSYSERR_NOERROR then
  begin
    AError := Format('waveOutOpen failed (%d)', [OpenResult]);
    CloseHandle(FEvent);
    FEvent := 0;
    Exit;
  end;

  for BlockIndex := 0 to OUT_BLOCK_COUNT - 1 do
  begin
    GetMem(FBuffers[BlockIndex], BLOCK_BYTES);
    FillChar(FBuffers[BlockIndex]^, BLOCK_BYTES, 0);
    FillChar(FHeaders[BlockIndex], SizeOf(TWAVEHDR), 0);
    FHeaders[BlockIndex].lpData := PChar(FBuffers[BlockIndex]);
    FHeaders[BlockIndex].dwBufferLength := BLOCK_BYTES;
    waveOutPrepareHeader(FHandle, @FHeaders[BlockIndex], SizeOf(TWAVEHDR));
    { Mark done so the feed loop treats every block as free on the first pass. }
    FHeaders[BlockIndex].dwFlags :=
      FHeaders[BlockIndex].dwFlags or WHDR_DONE;
  end;
  FPrepared := True;
  Result := True;
end;

procedure TWaveOutThread.CloseDevice;
var
  BlockIndex: Integer;
begin
  if FHandle <> 0 then
  begin
    { Reset marks every queued block done, which is what lets
      waveOutUnprepareHeader succeed - unpreparing a still-queued header fails
      with WAVERR_STILLPLAYING and leaks the buffer. }
    waveOutReset(FHandle);
    if FPrepared then
      for BlockIndex := 0 to OUT_BLOCK_COUNT - 1 do
        waveOutUnprepareHeader(FHandle, @FHeaders[BlockIndex],
                               SizeOf(TWAVEHDR));
    waveOutClose(FHandle);
    FHandle := 0;
  end;
  FPrepared := False;
  for BlockIndex := 0 to OUT_BLOCK_COUNT - 1 do
    if FBuffers[BlockIndex] <> nil then
    begin
      FreeMem(FBuffers[BlockIndex]);
      FBuffers[BlockIndex] := nil;
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
  BlockIndex: Integer;
  Queued: Boolean;
begin
  while not Terminated do
  begin
    Queued := False;
    for BlockIndex := 0 to OUT_BLOCK_COUNT - 1 do
      if (FHeaders[BlockIndex].dwFlags and WHDR_DONE) <> 0 then
      begin
        FillAndQueue(BlockIndex);
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
  OutputThread: TWaveOutThread;
  OpenError: string;
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
  OutputThread := TWaveOutThread.Create(FMixer);
  if not OutputThread.Open(OpenError) then
  begin
    FLastError := OpenError;
    OutputThread.Free;
    Exit;
  end;
  FThread := OutputThread;
  OutputThread.Start;
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
