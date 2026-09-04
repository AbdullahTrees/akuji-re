{ Sound-effects component used by the main form. Each of its 57 channels maps
  directly to one SoundTable slot and one monophonic mixer voice. }

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
      wav leaves one slot silent and is not an error. Audio device failure is
      also non-fatal. }
    function Open(const AGameDir: string): Boolean;
    procedure Close;

    { Restart defaults to rewinding an already active voice. }
    procedure Play(Index: Integer; Restart: Boolean = True);
    procedure PlayLooped(Index: Integer);
    procedure Stop(Index: Integer);
    procedure StopAll;
    function IsPlaying(Index: Integer): Boolean;

    { How many sound slots loaded and whether the output device is active. }
    property LoadedCount: Integer read FLoadedCount;
    property Opened: Boolean read FOpened;

    { The 0..10 scale stored in data\system.dat. }
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
