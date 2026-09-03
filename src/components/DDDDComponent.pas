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
    { Streaming calls this once the .lfm has been applied - the original's
      component fired its OnInit at the equivalent point. }
    procedure Loaded; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Called once the form is up. Fires OnInit. }
    procedure Initialize;

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
    { Applied by Present; exposed for tests. }
    procedure ApplyFade;
    procedure TickFade;
    function FadeBusy: Boolean;
    { How far the level moves per frame. The original's +0x10. }
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
  { Nothing zeroes this on the original's side either - the callers that care
    write it, and the rest inherit whatever the last one set. Seeded with the
    step the slide show and every ordinary transition use. }
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
  { DRAW, THEN ADVANCE - Fader_Tick @ 0x0044DC70 does both, in that order,
    inside one `busy` test.

    Advancing first loses the last frame of the fade. On the step that crosses
    the end the flag clears and nothing is painted, so the frame shows the
    scene UN-FADED - and whatever was waiting on the fade only reacts on the
    frame after that, which is long enough to see the old room before a
    transition completes. }
  if not FFadeBusy then
    Exit;
  if FFadeMode <> 0 then
    Exit;
  ApplyFade;
  { The bounds are STRICT and the level is not clamped - 0x0044DC70 tests
    `> 0x78` and `< 0`, so the counter runs one step past the end before the
    fade stops being busy. Clamping it would end the fade a frame early. }
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

{ THE FADE IS A BOX WIPE, not a dissolve. 0x0044DC70 is the per-frame half and
  it draws four black rectangles closing in from the edges:

      Rect(0,   0,   level,       240)          the left band
      Rect(320, 0,   320 - level, 240)          the right band
      Rect(0,   0,   320,         level)        the top band
      Rect(0,   240, 320,         240 - level)  the bottom band

  so as the counter runs 0 to 0x78 the picture is squeezed shut from all four
  sides at once, and at 120 the top and bottom bands meet exactly - 240 is
  twice 120. The horizontal pair never meets, which does not matter because
  the vertical pair has already covered the screen.

  This was implemented as a brightness ramp first, which reached the same black
  by a route the original does not take and looked nothing like it on the way.
  The mistake was inferring the picture from the counter instead of reading the
  function that draws it.

  The BUSY flag clears on `level > 0x78` and `level < 0` - strictly outside -
  so the counter overshoots by one step before the fade is declared finished.
  Reproduced. }
procedure TDDDD.ApplyFade;
var
  Level, Width, Height: Integer;
begin
  { The painter alone. TickFade owns the guards, because the original's
    single Fader_Tick draws and advances inside one `busy` and mode-0 test -
    an idle fader paints nothing whatever its level says. }
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
  { The original branches on a fullscreen flag at +0x3C: DirectDraw Flip when
    set, otherwise Blt. Windowed is the shipped configuration (system.ini
    fullscreen=off), so that is the path to build.

    IT BLITS TO THE CLIENT RECT, NOT TO THE ORIGIN. TDDDD_Present @ 0x00449D00
    takes the form's rect, translates it to screen coordinates with
    ClientToScreen, and hands DirectDraw that as the destination against a
    source of the whole surface - and a Blt whose rects differ in size
    STRETCHES. So the picture fills whatever the window has become, which is
    why maximising the original scales it (and distorts it - there is no
    aspect correction anywhere in the call).

    At the shipped 320x240 the two are the same blit. }
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
