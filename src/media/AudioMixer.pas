{ Fixed-slot software mixer for sound effects. Each effect has one monophonic
  voice, so replaying it restarts that voice while different effects mix
  freely. Mono sources are emitted as signed 16-bit stereo at MIX_RATE. }

unit AudioMixer;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, WaveFile, SoundTable;

const
  MIX_CHANNELS = 2;   { output is stereo; sources are all mono }

  { Convert the 0..10 setting with the game's 4.5 dB attenuation step:

        DirectSoundBuffer.SetVolume((10 - v) * -0x1C2)

    DirectSound volume is measured in hundredths of a decibel, with zero at
    full volume. The lowest setting is therefore -45 dB, not silence. }
  VOLUME_STEP_MB = -450;
  VOLUME_MAX     = 10;

type
  TMixVoice = record
    Playing: Boolean;
    Loop: Boolean;
    Pos: Integer;       { sample index into the slot's wave }
  end;

  TAudioMixer = class
  private
    FWaves: array[0..SOUND_COUNT - 1] of TWaveData;
    FVoices: array[0..SOUND_COUNT - 1] of TMixVoice;
    FLock: TCriticalSection;
    FGain: Integer;     { 0..65536 fixed point, 65536 = unity }
    FVolume: Integer;   { the 0..10 setting, as stored }
    procedure SetVolume(Value: Integer);
  public
    constructor Create;
    destructor Destroy; override;

    { Loads every name in SoundTable relative to AGameDir. Returns how many
      loaded; missing files leave their slot silent rather than raising. }
    function LoadAll(const AGameDir: string): Integer;

    function IsLoaded(Index: Integer): Boolean;
    function Loaded: Integer;

    { ARestart controls whether an active voice rewinds before playback. }
    procedure Play(Index: Integer; ALoop: Boolean = False;
                   ARestart: Boolean = True);
    procedure Stop(Index: Integer);
    procedure StopAll;
    function IsPlaying(Index: Integer): Boolean;

    { Called from the audio device thread. Dest holds Frames * MIX_CHANNELS
      samples and is overwritten, not added to. }
    procedure MixInto(Dest: PSmallInt; Frames: Integer);

    { The 0..10 scale stored in data\system.dat. }
    property Volume: Integer read FVolume write SetVolume;
  end;

{ Convert the volume setting to a 16.16 amplitude gain. }
function VolumeToGain(Volume: Integer): Integer;

implementation

uses
  Math;

function VolumeToGain(Volume: Integer): Integer;
var
  MilliBels: Integer;
begin
  if Volume >= VOLUME_MAX then
    Exit(65536);
  if Volume < 0 then
    Volume := 0;
  MilliBels := (VOLUME_MAX - Volume) * VOLUME_STEP_MB;
  { gain = 10 ^ (mB / 2000); mB is hundredths of a dB and amplitude ratio is
    10 ^ (dB / 20). }
  Result := Round(65536.0 * Power(10.0, MilliBels / 2000.0));
end;

constructor TAudioMixer.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FVolume := VOLUME_MAX;
  FGain := 65536;
end;

destructor TAudioMixer.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TAudioMixer.SetVolume(Value: Integer);
begin
  { The options screen clamps to 0..10 before storing; clamp here too so a
    corrupt system.dat cannot produce a silent or overdriven mixer. }
  if Value < 0 then Value := 0;
  if Value > VOLUME_MAX then Value := VOLUME_MAX;
  FLock.Acquire;
  try
    FVolume := Value;
    FGain := VolumeToGain(Value);
  finally
    FLock.Release;
  end;
end;

{ Load one monophonic voice for every sound slot. Slot and sound indices are
  intentionally identical. }
function TAudioMixer.LoadAll(const AGameDir: string): Integer;
var
  SoundIndex: Integer;
begin
  Result := 0;
  for SoundIndex := 0 to SOUND_COUNT - 1 do
    if LoadWave(SoundPath(AGameDir, SoundIndex), FWaves[SoundIndex]) then
      Inc(Result);
end;

function TAudioMixer.IsLoaded(Index: Integer): Boolean;
begin
  Result := (Index >= 0) and (Index < SOUND_COUNT) and
            (Length(FWaves[Index].Samples) > 0);
end;

function TAudioMixer.Loaded: Integer;
var
  SoundIndex: Integer;
begin
  Result := 0;
  for SoundIndex := 0 to SOUND_COUNT - 1 do
    if Length(FWaves[SoundIndex].Samples) > 0 then
      Inc(Result);
end;

procedure TAudioMixer.Play(Index: Integer; ALoop: Boolean; ARestart: Boolean);
begin
  if not IsLoaded(Index) then
    Exit;
  FLock.Acquire;
  try
    { Rewind rather than layer - see the header. Without ARestart a voice that
      is already sounding keeps its position, which is what DirectSound's Play
      does on a buffer that never stopped. }
    if ARestart or (not FVoices[Index].Playing) then
      FVoices[Index].Pos := 0;
    FVoices[Index].Loop := ALoop;
    FVoices[Index].Playing := True;
  finally
    FLock.Release;
  end;
end;

procedure TAudioMixer.Stop(Index: Integer);
begin
  if (Index < 0) or (Index >= SOUND_COUNT) then
    Exit;
  FLock.Acquire;
  try
    FVoices[Index].Playing := False;
    FVoices[Index].Pos := 0;
  finally
    FLock.Release;
  end;
end;

procedure TAudioMixer.StopAll;
var
  SoundIndex: Integer;
begin
  FLock.Acquire;
  try
    for SoundIndex := 0 to SOUND_COUNT - 1 do
    begin
      FVoices[SoundIndex].Playing := False;
      FVoices[SoundIndex].Pos := 0;
    end;
  finally
    FLock.Release;
  end;
end;

function TAudioMixer.IsPlaying(Index: Integer): Boolean;
begin
  Result := (Index >= 0) and (Index < SOUND_COUNT) and FVoices[Index].Playing;
end;

procedure TAudioMixer.MixInto(Dest: PSmallInt; Frames: Integer);
var
  Accumulator: array of Integer;
  SoundIndex, FrameIndex, SampleCount, FramesToMix, Gain, V: Integer;
  Samples: TSampleArray;
begin
  if Frames <= 0 then
    Exit;

  { Accumulate in 32 bits so that several loud effects at once cannot wrap;
    clamp once at the end. Mixing straight into the 16-bit buffer is the
    classic way to get crackle on a busy frame. }
  SetLength(Accumulator, Frames);
  FillChar(Accumulator[0], Frames * SizeOf(Integer), 0);

  FLock.Acquire;
  try
    Gain := FGain;
    for SoundIndex := 0 to SOUND_COUNT - 1 do
    begin
      if not FVoices[SoundIndex].Playing then
        Continue;
      Samples := FWaves[SoundIndex].Samples;
      SampleCount := Length(Samples);
      if SampleCount = 0 then
      begin
        FVoices[SoundIndex].Playing := False;
        Continue;
      end;

      FrameIndex := 0;
      while FrameIndex < Frames do
      begin
        FramesToMix := SampleCount - FVoices[SoundIndex].Pos;
        if FramesToMix > Frames - FrameIndex then
          FramesToMix := Frames - FrameIndex;
        if FramesToMix <= 0 then
          Break;
        for V := 0 to FramesToMix - 1 do
          Inc(Accumulator[FrameIndex + V],
              Samples[FVoices[SoundIndex].Pos + V]);
        Inc(FrameIndex, FramesToMix);
        Inc(FVoices[SoundIndex].Pos, FramesToMix);
        if FVoices[SoundIndex].Pos >= SampleCount then
        begin
          if FVoices[SoundIndex].Loop then
            FVoices[SoundIndex].Pos := 0
          else
          begin
            FVoices[SoundIndex].Playing := False;
            Break;
          end;
        end;
      end;
    end;
  finally
    FLock.Release;
  end;

  for FrameIndex := 0 to Frames - 1 do
  begin
    V := (Accumulator[FrameIndex] * Gain) div 65536;
    if V > 32767 then
      V := 32767
    else if V < -32768 then
      V := -32768;
    { Mono source duplicated to both output channels. }
    Dest[FrameIndex * MIX_CHANNELS] := V;
    Dest[FrameIndex * MIX_CHANNELS + 1] := V;
  end;
end;

end.
