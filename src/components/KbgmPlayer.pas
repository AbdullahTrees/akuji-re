{ Background-music component used by the main form. AutoLoadMidis is the
  extensionless 15-track playlist; ResolvePath appends `.mid`. Playlist entry
  zero is a MIDI initialization sequence rather than a song. }

unit KbgmPlayer;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, MsClock, MidiFile, MidiOut;

const
  { KBGMFadeOut's own arithmetic: twenty volume steps, one every arg*50 ms. }
  KBGM_FADE_MS_PER_SECOND = 1000;
  { 0x00450CBC's two callers. }
  KBGM_STOP_HARD = 0;
  KBGM_STOP_FADE_NEWGAME = 2;

  { The default GM channel volume, used until the song sets its own CC7. }
  DEFAULT_CHANNEL_VOLUME = 100;

  KBGM_VOLUME_MAX = 10;

type
  TKbgmThread = class;

  TKbgmPlayer = class(TComponent)
  private
    FAutoLoadMidis: TStrings;
    FGameDir: string;
    FDevice: TMidiOutDevice;
    FThread: TKbgmThread;
    FCurrent: Integer;
    FVolume: Integer;
    { 0x0046EAA4 - the track to come back to after an interruption. }
    FRemembered: string;
    FOpened: Boolean;
    procedure SetAutoLoadMidis(Value: TStrings);
    procedure SetVolumeProp(Value: Integer);
    function ResolvePath(const Name: string): string;
    function IndexOfName(const Name: string): Integer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Opens the MIDI device. Returns False if there is none; music is never
      fatal, so callers should carry on regardless. }
    function Open(const AGameDir: string): Boolean;
    procedure Close;

    { PlayName is the primary entry point; Play resolves an AutoLoadMidis
      index. Playing the active track is ignored rather than restarted -
      restarting the area theme every time the stage loader re-asserts it would
      be audible. }
    { THE SECOND ARGUMENT IS A FADE LENGTH IN SECONDS, not a mode.

      The game stops the current track through 0x00450CBC, which takes it in
      EDX and branches: below 1 it calls KBGMStop and reinitialises, otherwise
      it calls KBGMFadeOut and passes the value straight through. Two callers,
      two values - a CONTINUE stops hard with 0, a NEW GAME fades with 2.

      The unit comes out of Kbgm32.dll itself, which is shipped beside the exe.
      KBGMFadeOut (ordinal 3, RVA 0x2095) sets up a volume ramp from 100 down
      in steps of 5 - twenty steps - and computes its timer interval as
      arg * 125 * 8 / 20, which is arg * 50 milliseconds. Twenty steps of
      arg * 50 ms is arg * 1000 ms, so the argument is SECONDS and the new
      game's 2 is a two-second fade. }
    procedure PlayName(const Name: string; Loop: Boolean = True);
    procedure Play(Index: Integer; Loop: Boolean = True;
                   FadeSeconds: Integer = 0);
    { 0x00450CBC. Zero stops dead, anything else fades over that many seconds. }
    procedure StopOrFade(FadeSeconds: Integer);

    { 0x00450EDC and 0x00450EF0 - the pair that survives an interruption.

      PowerUp_Show calls the first before starting its fanfare: it copies the
      current track's NAME into a global at 0x0046EAA4, nothing more. It is not
      a stop, which is what it looked like until it was read.

      Overlay_Update calls the second when the fanfare finishes - a hard stop,
      then the remembered name again, LOOPING. That is how the stage music
      comes back after a power-up. Without it the fanfare simply replaces the
      music and the stage stays silent for good. }
    procedure RememberCurrent;
    procedure ResumeRemembered;
    procedure Stop;
    procedure FadeOut(MilliSeconds: Integer);
    procedure FadeIn(Index: Integer; MilliSeconds: Integer);
    procedure SetVolume(Volume: Integer);

    function IsPlaying: Boolean;
    function TrackName(Index: Integer): string;

    property Current: Integer read FCurrent;
    property Opened: Boolean read FOpened;

    { 0..10. The settings struct holds one volume byte at +0x24 which is known
      to drive the sound effects; whether the options screen drives music from
      the same byte or a second one has not been traced yet, so this is kept on
      the same scale and left for the caller to decide. }
    property Volume: Integer read FVolume write SetVolumeProp;
  published
    property AutoLoadMidis: TStrings read FAutoLoadMidis write SetAutoLoadMidis;
  end;

  { The sequencer. Runs off the frame loop entirely: the game can stall for a
    stage load without the music stuttering. }
  TKbgmThread = class(TThread)
  private
    FDevice: TMidiOutDevice;
    FLock: TCriticalSection;
    FFile: TMidiFile;

    FPlaying: Boolean;
    FLoop: Boolean;
    FIndex: Integer;
    FCursor: Integer;
    FStartMs: DWord;

    FMasterGain: Integer;      { 0..1024 }
    FFadeFrom, FFadeTo: Integer;
    FFadeStartMs: DWord;
    FFadeMs: Integer;
    FFading: Boolean;
    FStopAfterFade: Boolean;

    FChannelVolume: array[0..MIDI_CHANNELS - 1] of Byte;
    FDirtyVolume: Boolean;

    procedure ApplyChannelVolumes;
    procedure DispatchDue(ElapsedUs: Int64);
    procedure RewindLocked;
  protected
    procedure Execute; override;
  public
    constructor Create(ADevice: TMidiOutDevice);
    destructor Destroy; override;

    procedure StartTrack(const FileName: string; AIndex: Integer;
                         ALoop: Boolean; AFadeInMs: Integer);
    procedure StopTrack;
    procedure BeginFadeOut(MilliSeconds: Integer);
    procedure SetGain(Gain: Integer);
    function CurrentIndex: Integer;
    function Running: Boolean;
  end;

implementation

{ ---------------------------------------------------------------------------
  TKbgmThread
  --------------------------------------------------------------------------- }

constructor TKbgmThread.Create(ADevice: TMidiOutDevice);
var
  Channel: Integer;
begin
  FDevice := ADevice;
  FLock := TCriticalSection.Create;
  FFile := TMidiFile.Create;
  FIndex := -1;
  FMasterGain := 1024;
  for Channel := 0 to MIDI_CHANNELS - 1 do
    FChannelVolume[Channel] := DEFAULT_CHANNEL_VOLUME;
  inherited Create(False);
  FreeOnTerminate := False;
end;

destructor TKbgmThread.Destroy;
begin
  FFile.Free;
  FLock.Free;
  inherited Destroy;
end;

{ Master volume is applied by scaling each channel's CC7 rather than by any
  device-level call: midiOutSetVolume is optional in the driver model and is a
  no-op on the Microsoft synth, so a player that relies on it appears to ignore
  the volume setting entirely. Scaling CC7 always works. }
procedure TKbgmThread.ApplyChannelVolumes;
var
  Channel, ChannelGain: Integer;
begin
  for Channel := 0 to MIDI_CHANNELS - 1 do
  begin
    ChannelGain := (Integer(FChannelVolume[Channel]) * FMasterGain) div 1024;
    if ChannelGain > 127 then ChannelGain := 127;
    if ChannelGain < 0 then ChannelGain := 0;
    FDevice.Send(LongWord($B0 or Channel) or (LongWord(CC_VOLUME) shl 8) or
                 (LongWord(ChannelGain) shl 16));
  end;
end;

procedure TKbgmThread.RewindLocked;
var
  Channel: Integer;
begin
  FCursor := 0;
  FStartMs := MsNow;
  for Channel := 0 to MIDI_CHANNELS - 1 do
    FChannelVolume[Channel] := DEFAULT_CHANNEL_VOLUME;
  FDirtyVolume := True;
end;

procedure TKbgmThread.DispatchDue(ElapsedUs: Int64);
var
  MidiEvent: TMidiEvent;
  Status, Channel, ControllerNumber, ControllerValue, ScaledValue: Integer;
  Message: LongWord;
begin
  while (FCursor < FFile.Count) and (FFile[FCursor].TimeUs <= ElapsedUs) do
  begin
    MidiEvent := FFile[FCursor];
    Inc(FCursor);

    case MidiEvent.Kind of
      mekShort:
        begin
          Message := MidiEvent.Msg;
          Status := Message and $FF;
          Channel := Status and $0F;

          { Intercept CC7 so the song's own volume automation composes with the
            master gain instead of overwriting it. Without this, any track that
            sets channel volume mid-song jumps back to full. }
          if ((Status and $F0) = $B0) then
          begin
            ControllerNumber := (Message shr 8) and $7F;
            ControllerValue := (Message shr 16) and $7F;
            if ControllerNumber = CC_VOLUME then
            begin
              FChannelVolume[Channel] := ControllerValue;
              ScaledValue := (ControllerValue * FMasterGain) div 1024;
              if ScaledValue > 127 then ScaledValue := 127;
              Message := LongWord(Status) or (LongWord(CC_VOLUME) shl 8) or
                         (LongWord(ScaledValue) shl 16);
            end;
          end;

          FDevice.Send(Message);
        end;
      mekSysEx:
        FDevice.SendSysEx(MidiEvent.Blob);
      mekTempo, mekEndOfTrack:
        ;   { tempo is already folded into TimeUs by MidiFile.ComputeTimes }
    end;
  end;
end;

procedure TKbgmThread.Execute;
var
  NowMs: DWord;
  ElapsedUs: Int64;
  Done, Fading: Boolean;
  FadeProgress: Integer;
begin
  while not Terminated do
  begin
    FLock.Acquire;
    try
      if FPlaying then
      begin
        NowMs := MsNow;

        { Fade ramp. Recomputed every tick and pushed to the channels, which is
          cheap - 16 short messages every few milliseconds. }
        Fading := FFading;
        if Fading then
        begin
          if FFadeMs <= 0 then
            FadeProgress := 1024
          else
          begin
            FadeProgress :=
              Integer((Int64(NowMs - FFadeStartMs) * 1024) div FFadeMs);
            if FadeProgress > 1024 then FadeProgress := 1024;
            if FadeProgress < 0 then FadeProgress := 0;
          end;
          FMasterGain := FFadeFrom
                         + ((FFadeTo - FFadeFrom) * FadeProgress) div 1024;
          FDirtyVolume := True;
          if FadeProgress >= 1024 then
          begin
            FFading := False;
            if FStopAfterFade then
            begin
              FPlaying := False;
              FStopAfterFade := False;
              FIndex := -1;
              FDevice.Reset;
            end;
          end;
        end;

        { The fade may have just ended the track, so re-test rather than
          carrying on into the dispatch with FPlaying already false. }
        if FPlaying then
        begin
          if FDirtyVolume then
          begin
            ApplyChannelVolumes;
            FDirtyVolume := False;
          end;

          ElapsedUs := Int64(NowMs - FStartMs) * 1000;
          DispatchDue(ElapsedUs);

          Done := FCursor >= FFile.Count;
          if Done then
          begin
            if FLoop and (FFile.Count > 0) then
            begin
              { Silence everything before restarting: a note whose Note Off
                sits past the last event we dispatched would sustain across the
                loop point. }
              FDevice.Reset;
              RewindLocked;
            end
            else
            begin
              FPlaying := False;
              FIndex := -1;
              FDevice.Reset;
            end;
          end;
        end;
      end;
    finally
      FLock.Release;
    end;

    { 2 ms is well inside one MIDI tick at this music's tempo - 48 ticks per
      quarter at 120 bpm is about 10 ms a tick - so quantising to it is
      inaudible, and it keeps the thread near idle. }
    Sleep(2);
  end;

  FDevice.Reset;
end;

procedure TKbgmThread.StartTrack(const FileName: string; AIndex: Integer;
  ALoop: Boolean; AFadeInMs: Integer);
begin
  FLock.Acquire;
  try
    FDevice.Reset;
    FPlaying := False;
    if not FFile.LoadFromFile(FileName) then
    begin
      FIndex := -1;
      Exit;
    end;
    FIndex := AIndex;
    FLoop := ALoop;
    RewindLocked;
    FStopAfterFade := False;
    if AFadeInMs > 0 then
    begin
      FFadeFrom := 0;
      FFadeTo := 1024;
      FFadeMs := AFadeInMs;
      FFadeStartMs := MsNow;
      FFading := True;
      FMasterGain := 0;
    end
    else
    begin
      FFading := False;
      FMasterGain := 1024;
    end;
    FDirtyVolume := True;
    FPlaying := True;
  finally
    FLock.Release;
  end;
end;

procedure TKbgmThread.StopTrack;
begin
  FLock.Acquire;
  try
    FPlaying := False;
    FFading := False;
    FStopAfterFade := False;
    FIndex := -1;
    FDevice.Reset;
  finally
    FLock.Release;
  end;
end;

procedure TKbgmThread.BeginFadeOut(MilliSeconds: Integer);
begin
  FLock.Acquire;
  try
    if not FPlaying then
      Exit;
    FFadeFrom := FMasterGain;
    FFadeTo := 0;
    FFadeMs := MilliSeconds;
    FFadeStartMs := MsNow;
    FFading := True;
    FStopAfterFade := True;
  finally
    FLock.Release;
  end;
end;

procedure TKbgmThread.SetGain(Gain: Integer);
begin
  FLock.Acquire;
  try
    if Gain < 0 then Gain := 0;
    if Gain > 1024 then Gain := 1024;
    { A fade owns the gain while it runs; overwriting it here would make the
      fade jump. }
    if not FFading then
    begin
      FMasterGain := Gain;
      FDirtyVolume := True;
    end;
  finally
    FLock.Release;
  end;
end;

function TKbgmThread.CurrentIndex: Integer;
begin
  FLock.Acquire;
  try
    Result := FIndex;
  finally
    FLock.Release;
  end;
end;

function TKbgmThread.Running: Boolean;
begin
  FLock.Acquire;
  try
    Result := FPlaying;
  finally
    FLock.Release;
  end;
end;

{ ---------------------------------------------------------------------------
  TKbgmPlayer
  --------------------------------------------------------------------------- }

constructor TKbgmPlayer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAutoLoadMidis := TStringList.Create;
  FCurrent := -1;
  FVolume := KBGM_VOLUME_MAX;
  FDevice := TMidiOutDevice.Create;
end;

destructor TKbgmPlayer.Destroy;
begin
  Close;
  FreeAndNil(FDevice);
  FAutoLoadMidis.Free;
  inherited Destroy;
end;

procedure TKbgmPlayer.SetAutoLoadMidis(Value: TStrings);
begin
  FAutoLoadMidis.Assign(Value);
end;

function TKbgmPlayer.TrackName(Index: Integer): string;
begin
  if (Index < 0) or (Index >= FAutoLoadMidis.Count) then
    Exit('');
  Result := FAutoLoadMidis[Index];
end;

function TKbgmPlayer.ResolvePath(const Name: string): string;
var
  RelativePath: string;
begin
  Result := '';
  if Name = '' then
    Exit;
  RelativePath := Name;
{$IFNDEF WINDOWS}
  RelativePath := StringReplace(RelativePath, '\', PathDelim, [rfReplaceAll]);
{$ENDIF}
  { The playlist stores no extension - the original appended it, and the
    literal '.mid' is still in the binary at file offset 0x0004F700. }
  if ExtractFileExt(RelativePath) = '' then
    RelativePath := RelativePath + '.mid';
  Result := IncludeTrailingPathDelimiter(FGameDir) + RelativePath;
end;

function TKbgmPlayer.IndexOfName(const Name: string): Integer;
var
  TrackIndex: Integer;
begin
  for TrackIndex := 0 to FAutoLoadMidis.Count - 1 do
    if SameText(FAutoLoadMidis[TrackIndex], Name) then
      Exit(TrackIndex);
  Result := -1;
end;

function TKbgmPlayer.Open(const AGameDir: string): Boolean;
begin
  FGameDir := AGameDir;
  Result := FDevice.Open;
  FOpened := Result;
  if not Result then
    Exit;
  FThread := TKbgmThread.Create(FDevice);
  FThread.SetGain((FVolume * 1024) div KBGM_VOLUME_MAX);
end;

procedure TKbgmPlayer.Close;
begin
  if FThread <> nil then
  begin
    FThread.StopTrack;
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  if FDevice <> nil then
    FDevice.Close;
  FCurrent := -1;
  FOpened := False;
end;

procedure TKbgmPlayer.RememberCurrent;
begin
  { DAT_0046EAA4 := self.CurrentTrackName. A name, not a position: the track
    restarts from the top when it comes back, which is what the original does. }
  if (FCurrent >= 0) and (FCurrent < FAutoLoadMidis.Count) then
    FRemembered := FAutoLoadMidis[FCurrent]
  else
    FRemembered := '';
end;

procedure TKbgmPlayer.ResumeRemembered;
begin
  if FRemembered = '' then
    Exit;
  StopOrFade(KBGM_STOP_HARD);
  { Looping - the third argument at 0x00450EF0 is 1. }
  PlayName(FRemembered, True);
end;

procedure TKbgmPlayer.StopOrFade(FadeSeconds: Integer);
begin
  if FadeSeconds < 1 then
    Stop
  else
    FadeOut(FadeSeconds * KBGM_FADE_MS_PER_SECOND);
end;

procedure TKbgmPlayer.PlayName(const Name: string; Loop: Boolean);
var
  TrackPath: string;
  TrackIndex: Integer;
begin
  if FThread = nil then
    Exit;
  TrackIndex := IndexOfName(Name);
  { Restart even when the requested track is already active. }
  TrackPath := ResolvePath(Name);
  if TrackPath = '' then
    Exit;
  FThread.StartTrack(TrackPath, TrackIndex, Loop, 0);
  FCurrent := FThread.CurrentIndex;
end;

procedure TKbgmPlayer.Play(Index: Integer; Loop: Boolean;
                           FadeSeconds: Integer);
begin
  if (Index < 0) or (Index >= FAutoLoadMidis.Count) then
    Exit;
  { Stop first, then play - the shape of both 0x00450F14 (fade 0) and
    0x00450F74 (fade 2). The default is 0 because that is what every caller
    except the new game uses. }
  StopOrFade(FadeSeconds);
  PlayName(FAutoLoadMidis[Index], Loop);
end;

procedure TKbgmPlayer.Stop;
begin
  if FThread <> nil then
    FThread.StopTrack;
  FCurrent := -1;
end;

procedure TKbgmPlayer.FadeOut(MilliSeconds: Integer);
begin
  if FThread <> nil then
    FThread.BeginFadeOut(MilliSeconds);
  FCurrent := -1;
end;

procedure TKbgmPlayer.FadeIn(Index: Integer; MilliSeconds: Integer);
var
  TrackPath: string;
begin
  if FThread = nil then
    Exit;
  if (Index < 0) or (Index >= FAutoLoadMidis.Count) then
    Exit;
  TrackPath := ResolvePath(FAutoLoadMidis[Index]);
  if TrackPath = '' then
    Exit;
  FThread.StartTrack(TrackPath, Index, True, MilliSeconds);
  FCurrent := FThread.CurrentIndex;
end;

procedure TKbgmPlayer.SetVolume(Volume: Integer);
begin
  SetVolumeProp(Volume);
end;

procedure TKbgmPlayer.SetVolumeProp(Value: Integer);
begin
  if Value < 0 then Value := 0;
  if Value > KBGM_VOLUME_MAX then Value := KBGM_VOLUME_MAX;
  FVolume := Value;
  if FThread <> nil then
    FThread.SetGain((FVolume * 1024) div KBGM_VOLUME_MAX);
end;

function TKbgmPlayer.IsPlaying: Boolean;
begin
  Result := (FThread <> nil) and FThread.Running;
end;

initialization
  RegisterClass(TKbgmPlayer);

end.
