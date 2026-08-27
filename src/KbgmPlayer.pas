{ TKbgmPlayer - background music (MIDI).

  STUB. See DDDDComponent.pas for the rationale.

  The original wrapped Kbgm32.dll, a third-party MIDI engine shipped alongside
  the game (13 exported functions: Open/Close/Play/Stop/Free/LoadFile/Init/
  GetInfo/SetVolume/SendSysx/FadeIn/FadeOut/SetRepeat).

  AutoLoadMidis comes straight from the form resource and is the real playlist -
  it also reveals game structure: two main areas, two bosses, five endings. }

unit KbgmPlayer;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

type
  TKbgmPlayer = class(TComponent)
  private
    FAutoLoadMidis: TStrings;
    FCurrent: Integer;
    procedure SetAutoLoadMidis(Value: TStrings);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Index into AutoLoadMidis. }
    procedure Play(Index: Integer; Loop: Boolean = True);
    procedure Stop;
    procedure FadeOut(MilliSeconds: Integer);
    procedure FadeIn(Index: Integer; MilliSeconds: Integer);
    procedure SetVolume(Volume: Integer);

    property Current: Integer read FCurrent;
  published
    property AutoLoadMidis: TStrings read FAutoLoadMidis write SetAutoLoadMidis;
  end;

implementation

constructor TKbgmPlayer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FAutoLoadMidis := TStringList.Create;
  FCurrent := -1;
end;

destructor TKbgmPlayer.Destroy;
begin
  FAutoLoadMidis.Free;
  inherited Destroy;
end;

procedure TKbgmPlayer.SetAutoLoadMidis(Value: TStrings);
begin
  FAutoLoadMidis.Assign(Value);
end;

procedure TKbgmPlayer.Play(Index: Integer; Loop: Boolean);
begin
  FCurrent := Index;
  { TODO: the original sent SysEx via KBGMSendSysx - see CLAUDE.md section 13
    on why a modern synth may not respond identically. }
end;

procedure TKbgmPlayer.Stop;
begin
  FCurrent := -1;
end;

procedure TKbgmPlayer.FadeOut(MilliSeconds: Integer);
begin
  { TODO }
end;

procedure TKbgmPlayer.FadeIn(Index: Integer; MilliSeconds: Integer);
begin
  { TODO }
end;

procedure TKbgmPlayer.SetVolume(Volume: Integer);
begin
  { TODO }
end;

initialization
  RegisterClass(TKbgmPlayer);

end.
