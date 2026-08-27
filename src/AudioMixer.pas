{ AudioMixer - software mixer for the sound effects.

  The original had no mixer: it created one DirectSound secondary buffer per
  effect and let the hardware mix them. That is why the form resource says
  ChannelCount = 57 and why the name table holds exactly 57 entries - the
  "channels" ARE the effects, one buffer each. See SoundTable.pas.

  Two behaviours follow from that design, and both are reproduced here rather
  than improved on, because they are audible:

    - An effect is monophonic with itself. Playing a sound that is already
      sounding rewinds it (DirectSound Play on a buffer whose position is not
      zero, after SetCurrentPosition(0)) instead of layering a second copy.
      Rapid fire therefore machine-guns rather than turning into mush.
    - Different effects mix freely, up to all 57 at once.

  So there is exactly one voice per slot and no voice allocation to do. The
  mixer is a fixed array walked once per output block.

  Output is signed 16-bit stereo at MIX_RATE. Sources are mono, so both output
  channels get the same value - the original had no panning; TDDSDWave3D exists
  in the component suite's RTTI but the game never sets Use3D and never
  positions a sound. }

unit AudioMixer;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, WaveFile, SoundTable;

const
  MIX_CHANNELS = 2;   { output is stereo; sources are all mono }

  { The original applies the settings volume to every channel as

        DirectSoundBuffer.SetVolume((10 - v) * -0x1C2)

    DirectSound volume is attenuation in hundredths of a decibel, 0 = full and
    -10000 = silence. -0x1C2 is -450, so each step down the 0..10 scale costs
    4.5 dB and v=0 lands at -45 dB rather than true silence. Reproduced exactly
    in VolumeToGain below - a plain linear 0..10 fader would sound quite
    different at the low end. }
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
      loaded; missing files leave their slot silent rather than raising, which
      is what the original did too. }
    function LoadAll(const AGameDir: string): Integer;

    function IsLoaded(Index: Integer): Boolean;
    function Loaded: Integer;

    { ARestart mirrors the CL argument of TDDSD_Play @ 0x00450FD8:

          if CL = 1 then begin GetBuffer(Index); Rewind end;
          GetBuffer(Index); Play;

      i.e. CL=1 rewinds before playing and CL=0 resumes a buffer that is
      already sounding. Every one of the game's 104 call sites passes 1, so
      True is the default and the False path is here for completeness rather
      than because anything uses it. }
    procedure Play(Index: Integer; ALoop: Boolean = False;
                   ARestart: Boolean = True);
    procedure Stop(Index: Integer);
    procedure StopAll;
    function IsPlaying(Index: Integer): Boolean;

    { Called from the audio device thread. Dest holds Frames * MIX_CHANNELS
      samples and is overwritten, not added to. }
    procedure MixInto(Dest: PSmallInt; Frames: Integer);

    { The 0..10 scale from data\system.dat +0x24. Clamped like the original. }
    property Volume: Integer read FVolume write SetVolume;
  end;

{ Exposed for testing: the original's attenuation curve as a 16.16 gain. }
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

function TAudioMixer.LoadAll(const AGameDir: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to SOUND_COUNT - 1 do
    if LoadWave(SoundPath(AGameDir, I), FWaves[I]) then
      Inc(Result);
end;

function TAudioMixer.IsLoaded(Index: Integer): Boolean;
begin
  Result := (Index >= 0) and (Index < SOUND_COUNT) and
            (Length(FWaves[Index].Samples) > 0);
end;

function TAudioMixer.Loaded: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to SOUND_COUNT - 1 do
    if Length(FWaves[I].Samples) > 0 then
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
  I: Integer;
begin
  FLock.Acquire;
  try
    for I := 0 to SOUND_COUNT - 1 do
    begin
      FVoices[I].Playing := False;
      FVoices[I].Pos := 0;
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
  Acc: array of Integer;
  I, F, N, Take, Gain, V: Integer;
  Src: TSampleArray;
begin
  if Frames <= 0 then
    Exit;

  { Accumulate in 32 bits so that several loud effects at once cannot wrap;
    clamp once at the end. Mixing straight into the 16-bit buffer is the
    classic way to get crackle on a busy frame. }
  SetLength(Acc, Frames);
  FillChar(Acc[0], Frames * SizeOf(Integer), 0);

  FLock.Acquire;
  try
    Gain := FGain;
    for I := 0 to SOUND_COUNT - 1 do
    begin
      if not FVoices[I].Playing then
        Continue;
      Src := FWaves[I].Samples;
      N := Length(Src);
      if N = 0 then
      begin
        FVoices[I].Playing := False;
        Continue;
      end;

      F := 0;
      while F < Frames do
      begin
        Take := N - FVoices[I].Pos;
        if Take > Frames - F then
          Take := Frames - F;
        if Take <= 0 then
          Break;
        for V := 0 to Take - 1 do
          Inc(Acc[F + V], Src[FVoices[I].Pos + V]);
        Inc(F, Take);
        Inc(FVoices[I].Pos, Take);
        if FVoices[I].Pos >= N then
        begin
          if FVoices[I].Loop then
            FVoices[I].Pos := 0
          else
          begin
            FVoices[I].Playing := False;
            Break;
          end;
        end;
      end;
    end;
  finally
    FLock.Release;
  end;

  for F := 0 to Frames - 1 do
  begin
    V := (Acc[F] * Gain) div 65536;
    if V > 32767 then
      V := 32767
    else if V < -32768 then
      V := -32768;
    { Mono source duplicated to both output channels. }
    Dest[F * MIX_CHANNELS] := V;
    Dest[F * MIX_CHANNELS + 1] := V;
  end;
end;

end.
