{ TDDSD - sound effects component.

  Like TDDDD, this is not a reconstruction of the third-party DirectSound
  component the original linked against; it is a fresh implementation of the
  same published interface, which GmMain.lfm documents. Only DebugOption and
  ChannelCount are streamed, so those are all the published properties needed.

  What ChannelCount actually means was the useful find here. It is 57 in the
  form resource, and the executable holds exactly 57 sound-effect file names in
  a static array at 0x00468D50 (see SoundTable.pas), and wav/ holds exactly
  those 57 files. So a "channel" is one DirectSound buffer holding one effect -
  not a voice in a pool. Slot number and sound number are the same thing, which
  is why Play takes an index straight out of the table and why re-triggering a
  sound restarts it rather than layering.

  The audio path underneath:

      SoundTable  the 57 names, recovered
      WaveFile    RIFF reader (the original used winmm's mmio* calls)
      AudioMixer  software mixing, one voice per slot
      AudioOut    the device; waveOut on Windows, null elsewhere

  Everything except AudioOut is portable Pascal. }

unit DDSDComponent;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, SoundTable, AudioMixer, AudioOut;

type
  TDDSDDebugOptionItem = (dsoHaltOnError);
  TDDSDDebugOption = set of TDDSDDebugOptionItem;

  TDDSD = class(TComponent)
  private
    FDebugOption: TDDSDDebugOption;
    FChannelCount: Integer;
    FMixer: TAudioMixer;
    FOut: TAudioOut;
    FOpened: Boolean;
    FLoadedCount: Integer;
    FGameDir: string;
    function GetVolume: Integer;
    procedure SetVolume(Value: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Loads every effect named in SoundTable from AGameDir and opens the output
      device. Returns False only if the device could not be opened; a missing
      wav leaves one slot silent and is not an error, matching the original,
      which tolerated a partial wav directory rather than refusing to start.

      Audio is never fatal: if this returns False the game still runs. }
    function Open(const AGameDir: string): Boolean;
    procedure Close;

    { TDDSD_Play @ 0x00450FD8 takes (Self, Index, Restart) in EAX/EDX/CL. All
      104 call sites in the game pass Restart = 1, so that is the default. }
    procedure Play(Index: Integer; Restart: Boolean = True);
    procedure PlayLooped(Index: Integer);
    procedure Stop(Index: Integer);
    procedure StopAll;
    function IsPlaying(Index: Integer): Boolean;

    { How many of the 57 slots actually loaded, and whether the device is up -
      both reported by the self-test. }
    property LoadedCount: Integer read FLoadedCount;
    property Opened: Boolean read FOpened;

    { The 0..10 scale straight out of data\system.dat +0x24. The original's
      attenuation curve is reproduced in AudioMixer.VolumeToGain. }
    property Volume: Integer read GetVolume write SetVolume;
  published
    property DebugOption: TDDSDDebugOption read FDebugOption write FDebugOption;
    property ChannelCount: Integer read FChannelCount write FChannelCount;
  end;

implementation

constructor TDDSD.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { Overwritten by the .lfm, which also says 57. Defaulted so a TDDSD created
    in code behaves the same as the streamed one. }
  FChannelCount := SOUND_COUNT;
  FMixer := TAudioMixer.Create;
  FOut := TAudioOut.Create(FMixer);
end;

destructor TDDSD.Destroy;
begin
  Close;
  FreeAndNil(FOut);
  FreeAndNil(FMixer);
  inherited Destroy;
end;

function TDDSD.Open(const AGameDir: string): Boolean;
begin
  if FOpened then
    Close;
  FGameDir := AGameDir;
  FLoadedCount := FMixer.LoadAll(AGameDir);
  Result := FOut.Start;
  FOpened := Result;
end;

procedure TDDSD.Close;
begin
  if FMixer <> nil then
    FMixer.StopAll;
  if FOut <> nil then
    FOut.Stop;
  FOpened := False;
end;

procedure TDDSD.Play(Index: Integer; Restart: Boolean);
begin
  FMixer.Play(Index, False, Restart);
end;

procedure TDDSD.PlayLooped(Index: Integer);
begin
  FMixer.Play(Index, True);
end;

procedure TDDSD.Stop(Index: Integer);
begin
  FMixer.Stop(Index);
end;

procedure TDDSD.StopAll;
begin
  FMixer.StopAll;
end;

function TDDSD.IsPlaying(Index: Integer): Boolean;
begin
  Result := FMixer.IsPlaying(Index);
end;

function TDDSD.GetVolume: Integer;
begin
  Result := FMixer.Volume;
end;

procedure TDDSD.SetVolume(Value: Integer);
begin
  FMixer.Volume := Value;
end;

initialization
  RegisterClass(TDDSD);

end.
