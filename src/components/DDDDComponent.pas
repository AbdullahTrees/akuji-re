{ LCL implementation of the display component used by the main form. It owns
  the back buffer and handles clearing, drawing, presentation, and fades. }

unit DDDDComponent;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Controls, Forms;

const
  { 0x78 and the step every caller writes to self+0x10 before starting one.
    120 at 4 a frame is thirty frames. }
  FADE_FULL = $78;
  { Callers may override the step for different fade speeds. }
  FADE_STEP = 4;
  { 0x78 / 4 = 30 steps to cover, plus the one that pushes the level
    strictly outside and ends the fade. }
  FADE_TICKS = FADE_FULL div FADE_STEP + 1;

type
  TDDDDDebugOptionItem = (ddoHaltOnError);
  TDDDDDebugOption = set of TDDDDDebugOptionItem;

  { The game does not enable the component's 3D path. }
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
    { Fade state offsets retained for layout verification. }
    FFadeLevel: Integer;      { +0x08 }
    FFadeStep: Integer;       { +0x10, written by the caller before a fade }
    FFadeMode: Integer;       { +0x04 }
    FFadeOut: Boolean;        { +0x0C }
    FFadeBusy: Boolean;       { +0x0D }
    function GetSurfaceCanvas: TCanvas;
  protected
    { Streaming calls this after the .lfm properties have been applied. }
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Called once the form is up. Fires OnInit. }
    procedure Initialize;

    procedure Clear;
    procedure Present;

    { Fade-in counts from black to clear; fade-out counts from clear to black.
      Stage changes wait for FadeBusy to clear before loading the destination. }
    procedure StartFade(Mode: Integer; FadeOut: Boolean);
    { Applied by Present; exposed for tests. }
    procedure ApplyFade;
    procedure TickFade;
    function FadeBusy: Boolean;
    { How far the fade level moves per frame. }
    property FadeStep: Integer read FFadeStep write FFadeStep;

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
  { Callers may replace this; ordinary transitions use the default step. }
  FFadeStep := FADE_STEP;
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
  { Property values arrive from the .lfm before this runs. }
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
  { Draw before advancing so the terminal fade frame remains visible while
    clients are still waiting for FadeBusy to clear. }
  if not FFadeBusy then
    Exit;
  if FFadeMode <> 0 then
    Exit;
  ApplyFade;
  { Strict bounds keep the fade busy through its endpoint; it finishes after
    the counter steps outside the visible range. }
  if FFadeOut then
  begin
    Inc(FFadeLevel, FFadeStep);
    if FFadeLevel > FADE_FULL then
      FFadeBusy := False;
  end
  else
  begin
    Dec(FFadeLevel, FFadeStep);
    if FFadeLevel < 0 then
      FFadeBusy := False;
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

{ The fade is a box wipe: four black rectangles close in from the edges.

      Rect(0,   0,   level,       240)          the left band
      Rect(320, 0,   320 - level, 240)          the right band
      Rect(0,   0,   320,         level)        the top band
      Rect(0,   240, 320,         240 - level)  the bottom band

  At level 120 the vertical bands meet and cover the 240-pixel display. }
procedure TDDDD.ApplyFade;
var
  Level, Width, Height: Integer;
begin
  { TickFade owns the state guards; this routine only paints the current level. }
  { Nothing to paint on until the surface has been sized - the fade self-test
    drives a bare component with no screen behind it. }
  if (FSurface = nil) or (FSurface.Width = 0) or (FSurface.Height = 0) then
    Exit;
  Level := FFadeLevel;
  if Level <= 0 then
    Exit;
  Width := FSurface.Width;
  Height := FSurface.Height;
  FSurface.Canvas.Brush.Color := clBlack;
  FSurface.Canvas.FillRect(0, 0, Level, Height);              { left }
  FSurface.Canvas.FillRect(Width - Level, 0, Width, Height);  { right }
  FSurface.Canvas.FillRect(0, 0, Width, Level);                { top }
  FSurface.Canvas.FillRect(0, Height - Level, Width, Height);  { bottom }
end;

procedure TDDDD.Present;
begin
  { Stretch the fixed-size back buffer over the entire client area. Aspect
    ratio is not preserved when the window is resized. }
  if (Owner is TCustomForm) and TCustomForm(Owner).HandleAllocated then
    TCustomForm(Owner).Canvas.StretchDraw(
      TCustomForm(Owner).ClientRect, FSurface);
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
