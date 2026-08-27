{ TDDSD - sound effects component.

  STUB. See DDDDComponent.pas for the rationale.

  The original wrapped DirectSound. Note ChannelCount = 57 in the form resource -
  the game mixes up to 57 simultaneous effects, which is worth knowing before
  picking a replacement audio backend.

  Sound data is read with the winmm mmio* RIFF calls (mmioOpen/Descend/Read/
  Ascend/Close) from the wav\ directory. }

unit DDSDComponent;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

type
  TDDSDDebugOptionItem = (dsoHaltOnError);
  TDDSDDebugOption = set of TDDSDDebugOptionItem;

  TDDSD = class(TComponent)
  private
    FDebugOption: TDDSDDebugOption;
    FChannelCount: Integer;
  public
    constructor Create(AOwner: TComponent); override;

    { Load a .wav into a slot. No-op for now. }
    procedure LoadWave(Index: Integer; const FileName: string);

    { Play a loaded effect. The game calls this via MainForm field +0x2DC. }
    procedure Play(Index: Integer);
    procedure Stop(Index: Integer);
    procedure SetVolume(Index: Integer; Volume: Integer);
  published
    property DebugOption: TDDSDDebugOption read FDebugOption write FDebugOption;
    property ChannelCount: Integer read FChannelCount write FChannelCount;
  end;

implementation

constructor TDDSD.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChannelCount := 57;
end;

procedure TDDSD.LoadWave(Index: Integer; const FileName: string);
begin
  { TODO }
end;

procedure TDDSD.Play(Index: Integer);
begin
  { TODO }
end;

procedure TDDSD.Stop(Index: Integer);
begin
  { TODO }
end;

procedure TDDSD.SetVolume(Index: Integer; Volume: Integer);
begin
  { TODO }
end;

initialization
  RegisterClass(TDDSD);

end.
