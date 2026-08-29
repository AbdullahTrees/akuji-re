{ TDDDD - display surface component.

  STUB - DIVERGENCE DIV-008. Does nothing yet. Its only job right now is to
  exist with the exact
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

const
  { 0x78 and the step every caller writes to self+0x10 before starting one.
    120 at 4 a frame is thirty frames. }
  FADE_FULL = $78;
  FADE_STEP = 4;

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
    { The fade's four fields, at the original's own offsets. }
    FFadeLevel: Integer;      { +0x08 }
    FFadeMode: Integer;       { +0x04 }
    FFadeOut: Boolean;        { +0x0C }
    FFadeBusy: Boolean;       { +0x0D }
    function GetSurfaceCanvas: TCanvas;
  protected
    { Streaming calls this once the .lfm has been applied - the original's
      component fired its OnInit at the equivalent point. }
    procedure Loaded; override;
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

    { THE SCREEN FADE, from the object at 0x0046CB6C. It belongs to the display
      layer in the original too, which is why it is here rather than in the
      game units.

      0x0044DC48 is the whole of starting one:

          self+0x08 := 0            the counter
          self+0x04 := Mode         0 at every call site
          self+0x0C := Direction    1 fades OUT, 0 fades IN
          self+0x0D := 1            busy
          if Mode = 0 and Direction = 0 then self+0x08 := 0x78

      so a fade-in starts the counter at 120 and runs down, a fade-out starts
      at 0 and runs up. Every caller sets self+0x10 := 4 first, which is the
      step, so a fade is 120/4 = THIRTY FRAMES - half a second at the
      original's 62 fps.

      FadeBusy is self+0x0D, and the event interpreter's stage-load and warp
      both wait on it: fade out, wait, then load. With it stuck at False the
      wait passed on the frame it started and transitions happened instantly. }
    procedure StartFade(Mode: Integer; FadeOut: Boolean);
    procedure TickFade;
    function FadeBusy: Boolean;
    { 0 = clear, FADE_FULL = black. What a real fader would draw. }
    property FadeLevel: Integer read FFadeLevel;
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

procedure TDDDD.Loaded;
begin
  inherited Loaded;
  Initialize;
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

procedure TDDDD.StartFade(Mode: Integer; FadeOut: Boolean);
begin
  FFadeLevel := 0;
  FFadeMode := Mode;
  FFadeOut := FadeOut;
  FFadeBusy := True;
  { The one asymmetry: a fade IN starts full and runs down. }
  if (Mode = 0) and (not FadeOut) then
    FFadeLevel := FADE_FULL;
end;

procedure TDDDD.TickFade;
begin
  if not FFadeBusy then
    Exit;
  if FFadeOut then
  begin
    Inc(FFadeLevel, FADE_STEP);
    if FFadeLevel >= FADE_FULL then
    begin
      FFadeLevel := FADE_FULL;
      FFadeBusy := False;
    end;
  end
  else
  begin
    Dec(FFadeLevel, FADE_STEP);
    if FFadeLevel <= 0 then
    begin
      FFadeLevel := 0;
      FFadeBusy := False;
    end;
  end;
end;

function TDDDD.FadeBusy: Boolean;
begin
  Result := FFadeBusy;
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
  if (Owner is TCustomForm) and TCustomForm(Owner).HandleAllocated then
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
