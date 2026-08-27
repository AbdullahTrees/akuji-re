{ TDDDD - display surface component.

  STUB. Does nothing yet. Its only job right now is to exist with the exact
  published interface GmMain.lfm expects, so the form can load and the project
  can build.

  The original was a third-party Delphi DirectDraw component. This is NOT a
  reconstruction of it - it is a fresh implementation of the same published
  interface, backed by LCL (later SDL2). Only the properties and events the game
  actually uses are needed; those are exactly what the form resource lists. }

unit DDDDComponent;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, Forms;

type
  TDDDDDebugOptionItem = (ddoHaltOnError);
  TDDDDDebugOption = set of TDDDDDebugOptionItem;

  { Members unknown - the form sets D3DOptions = [], and Use3D = False, so the
    original's Direct3D path was never enabled. See CLAUDE.md section 6. }
  TD3DOptionItem = (d3doReserved);
  TD3DOptions = set of TD3DOptionItem;

  TDDDD = class(TComponent)
  private
    FDebugOption: TDDDDDebugOption;
    FInitialScreenWidth: Integer;
    FInitialScreenHeight: Integer;
    FBackColor: TColor;
    FDisableScreenSaver: Boolean;
    FUse3D: Boolean;
    FD3DOptions: TD3DOptions;
    FVsyncAtWindowed: Boolean;
    FOnInit: TNotifyEvent;
    FSurface: TBitmap;
    function GetSurfaceCanvas: TCanvas;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Called once the form is up. Fires OnInit. }
    procedure Initialize;

    { --- interface recovered from the original, not invented ---
      TDDDD_Clear      0x00449E78  fills the back buffer with BackColor (+0x4C)
      TDDDD_Present    0x00449D00  fullscreen: DirectDraw Flip
                                   windowed:   Blt back buffer to window origin
      TDDDD_DrawSprite 0x00448918  (surface, x, y, transparent, srcRect)
      The frame loop calls Clear at step 4 and Present at step 8. }

    procedure Clear;
    procedure Present;
    procedure DrawSprite(Src: TBitmap; X, Y: Integer; const SrcRect: TRect;
                         Transparent: Boolean = True);

    { Everything the game draws goes here. Backed by a TBitmap for now, which
      is why LCL-first works: the game already draws through TCanvas. }
    property Surface: TBitmap read FSurface;
    property Canvas: TCanvas read GetSurfaceCanvas;
  published
    property DebugOption: TDDDDDebugOption read FDebugOption write FDebugOption;
    property InitialScreenWidth: Integer read FInitialScreenWidth write FInitialScreenWidth;
    property InitialScreenHeight: Integer read FInitialScreenHeight write FInitialScreenHeight;
    property BackColor: TColor read FBackColor write FBackColor;
    property DisableScreenSaver: Boolean read FDisableScreenSaver write FDisableScreenSaver;
    property Use3D: Boolean read FUse3D write FUse3D;
    property D3DOptions: TD3DOptions read FD3DOptions write FD3DOptions;
    property VsyncAtWindowed: Boolean read FVsyncAtWindowed write FVsyncAtWindowed;
    property OnInit: TNotifyEvent read FOnInit write FOnInit;
  end;

implementation

constructor TDDDD.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FInitialScreenWidth := 320;
  FInitialScreenHeight := 240;
  FBackColor := 0;
  FSurface := TBitmap.Create;
end;

destructor TDDDD.Destroy;
begin
  FSurface.Free;
  inherited Destroy;
end;

function TDDDD.GetSurfaceCanvas: TCanvas;
begin
  Result := FSurface.Canvas;
end;

procedure TDDDD.Initialize;
begin
  { Property values arrive from the .lfm before this runs, so the size is the
    original's 320x240. }
  FSurface.SetSize(FInitialScreenWidth, FInitialScreenHeight);
  FSurface.Canvas.Brush.Color := FBackColor;
  FSurface.Canvas.FillRect(0, 0, FInitialScreenWidth, FInitialScreenHeight);
  if Assigned(FOnInit) then
    FOnInit(Self);
end;

procedure TDDDD.Clear;
begin
  FSurface.Canvas.Brush.Color := FBackColor;
  FSurface.Canvas.FillRect(0, 0, FSurface.Width, FSurface.Height);
end;

procedure TDDDD.Present;
begin
  { The original branched on a fullscreen flag at +0x3C: DirectDraw Flip when
    set, otherwise Blt to the window's screen origin. Windowed is the shipped
    configuration (system.ini fullscreen=off), so that is the path to build. }
  if Owner is TWinControl then
    TCustomForm(Owner).Canvas.Draw(0, 0, FSurface);
end;

procedure TDDDD.DrawSprite(Src: TBitmap; X, Y: Integer; const SrcRect: TRect;
  Transparent: Boolean);
begin
  Src.Transparent := Transparent;
  FSurface.Canvas.CopyRect(
    Rect(X, Y, X + (SrcRect.Right - SrcRect.Left),
               Y + (SrcRect.Bottom - SrcRect.Top)),
    Src.Canvas, SrcRect);
end;

initialization
  { Required: the .lfm reader resolves components by class name via GetClass. }
  RegisterClass(TDDDD);

end.
