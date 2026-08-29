{ Title - the title screen and options, translated from Title_MainMenu
  @ 0x00462330.

  The original is one function with three sub-modes selected by p_TitleSubMode
  (0x0046CEF8):

    0  main menu    NEW GAME / CONTINUE / OPTION / EXIT
    1  options      10 rows, including three rebindable keys
    2  omake viewer a full-screen unlocked extra image

  Every string, coordinate and range below is taken from the decompilation.
  Coordinates are in the original's 320x240 space.

  Rendering goes through the game's own bitmap font (GameFont.pas), the same
  font9x9-01.bmp sheet the original used, so metrics and colours match.

  Still stubbed: option value editing (MoveX) and key rebinding, which needs raw
  button polling rather than an axis. The menu backgrounds (p_Surfaces[1] and
  [2]) are not loaded yet. }

unit Title;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, GameState, GameFont, SoundTable;

const
  { Sub-modes, p_TitleSubMode @ 0x0046CEF8 }
  TSM_MENU    = 0;
  TSM_OPTIONS = 1;
  TSM_OMAKE   = 2;

  { Main menu. x=0xEE, rows at y = (index*2 + 0x11) * 8 }
  MENU_X      = $EE;
  MENU_CURSOR_X = $E6;
  MENU_ITEMS: array[0..3] of string = (
    'NEW GAME',      // -> GS_PLAYER_INIT, sub-mode records new(0)/continue(1)
    'CONTINUE',
    ' OPTION ',      // -> TSM_OPTIONS
    '  EXIT  ');     // -> GS_QUIT

  CREDIT_TEXT = 'CREATED BY E.HASHIMOTO';   { 0x00462DC4, drawn at (0, 0xD8) }

  { Options rows. Labels x=0x28, values x=0xE8,
    rows at y = 0x38 + row*0x10; cursor y = (index*2 + 7) * 8 }
  OPT_LABEL_X  = $28;
  OPT_VALUE_X  = $E8;
  OPT_CURSOR_X = $E0;
  OPT_ROW_EXIT = 9;
  OPT_TITLE    = '- OPTION -';
  OPT_CURSOR   = '<       >';    { brackets the value column }

  { Row labels, verbatim from 0x00462E0C onward. }
  OPT_LABELS: array[0..9] of string = (
    'GAME LEVEL',
    'FULL SCREEN',
    'JUMP  BUTTON ASSIGN',
    'FIRE  BUTTON ASSIGN',
    'PAUSE BUTTON ASSIGN',
    'WAIT',
    'SOFTWARE VSYNC',      { this is the timeGetTime spin-wait, player-toggleable }
    'SE VOLUME',
    'GALLERY',
    'EXIT');

  TEXT_ON   = 'ON';
  TEXT_OFF  = 'OFF';
  KEY_SUFFIX = ' KEY';

  { Ranges the original clamps to }
  LEVEL_MIN = 0;  LEVEL_MAX = 2;    // p_Settings+0x04
  VOLUME_MIN = 0; VOLUME_MAX = 10;  // p_Settings+0x24
  OMAKE_MIN = 0;  OMAKE_MAX = 6;    // p_Settings+0x28

type
  { The rows the option cursor moves through, in order. Rows 2..4 are the
    rebindable keys - the original detects any of 16 buttons and swaps if the
    chosen button is already bound elsewhere. }
  TOptionRow = (orLevel, orToggle1, orKey0, orKey1, orKey2,
                orToggle2, orFrameLimit, orVolume, orOmake, orExit);

  { Fired where the original calls DDSD1.Play. Kept as a callback so this unit
    stays independent of the component layer; GmMain hooks it up. }
  TSoundEvent = procedure(Index: Integer) of object;

  TTitleScreen = class
  private
    FSubMode: Integer;
    FIndex: Integer;          // p_MenuIndex 0x0046CF88, shared with the pause menu
    FOnSound: TSoundEvent;
    procedure PlaySound(Index: Integer);
    procedure MenuConfirm;
    procedure OptionsConfirm;
    procedure DrawValues(C: TCanvas; F: TGameFont);
    procedure AdjustValue(Delta: Integer);
  public
    constructor Create;
    procedure Reset;
    { Returns True when the caller should leave the title screen; the new
      GameStateValue has already been set. }
    function Update(MoveY, MoveX: Integer; Confirm: Boolean): Boolean;
    procedure Draw(C: TCanvas; F: TGameFont; BgMenu, BgOptions: TBitmap);

    property SubMode: Integer read FSubMode;
    property Index: Integer read FIndex;
    property OnSound: TSoundEvent read FOnSound write FOnSound;
  end;

  { --- GameOver_Update @ 0x00461A44 --------------------------------------

    The game-over screen, and the shortest of the three screens that step
    through GameState.ScreenPhase:

      0  ask the fader to fade OUT, and move on at once
      1  wait for the fader to go idle, then tear the run down -
         GameState_Reset(mode 0), reload the stage assets, re-register the
         font, clear the title sub-mode, put the state machine on 100, start
         `midi\gameover`, and fade back IN
      2  draw the full-screen image from surface slot 3 and wait

    What ends it is `the music has stopped OR confirm was pressed`. So the
    screen holds for exactly as long as the game-over tune, unless you cut it
    short - and then it goes to GS_TITLE_INIT, not back to the game.

    Re-registering the font in phase 1 is not redundant: Load_Stage_Assets
    reloads surface slot 0, which is the font sheet, so the glyph table has
    to be rebuilt on top of it. Three other places in the original do the
    same for the same reason (see GameFont.pas).

    The four things it needs from outside are callbacks, the way the title
    screen's sound is, so the unit stays clear of the component layer. }
  TFadeEvent = procedure(FadeIn: Boolean) of object;
  TMusicEvent = procedure(Track: Integer) of object;
  TRestartEvent = procedure of object;

const
  GAMEOVER_MIDI = 2;        { AutoLoadMidis[2] is midi\gameover }
  GAMEOVER_SURFACE = 3;     { the full-screen image }

type
  TGameOverScreen = class
  private
    FOnFade: TFadeEvent;
    FOnMusic: TMusicEvent;
    FOnRestart: TRestartEvent;
  public
    { Returns True while the screen should be drawn, which is phase 2 only.
      FadeBusy and MusicPlaying are asked of the host every frame because the
      original asks its two components every frame. }
    function Update(FadeBusy, MusicPlaying, Confirm: Boolean;
                    var AGameState: Integer): Boolean;

    property OnFade: TFadeEvent read FOnFade write FOnFade;
    property OnMusic: TMusicEvent read FOnMusic write FOnMusic;
    property OnRestart: TRestartEvent read FOnRestart write FOnRestart;
  end;

implementation

{ --- TGameOverScreen ----------------------------------------------------- }

function TGameOverScreen.Update(FadeBusy, MusicPlaying, Confirm: Boolean;
                                var AGameState: Integer): Boolean;
begin
  Result := False;

  if ScreenPhase = 0 then
  begin
    ScreenPhase := 1;
    if Assigned(FOnFade) then
      FOnFade(False);
  end
  else if (ScreenPhase = 1) and not FadeBusy then
  begin
    { GameState_Reset(mode 0) plus the asset reload and the font rebuild -
      one callback, because the host owns all three. }
    if Assigned(FOnRestart) then
      FOnRestart;
    ScreenPhase := 2;
    TitleSubMode := 0;
    AGameState := GS_PLAY_ALT;
    if Assigned(FOnMusic) then
      FOnMusic(GAMEOVER_MIDI);
    if Assigned(FOnFade) then
      FOnFade(True);
  end;

  if ScreenPhase = 2 then
  begin
    Result := True;
    { Held for exactly as long as the tune, unless you cut it short. }
    if (not MusicPlaying) or Confirm then
    begin
      ScreenPhase := 0;
      AGameState := GS_TITLE_INIT;
    end;
  end;
end;

constructor TTitleScreen.Create;
begin
  inherited Create;
  Reset;
end;

procedure TTitleScreen.Reset;
begin
  FSubMode := TSM_MENU;
  FIndex := 0;
end;

procedure TTitleScreen.PlaySound(Index: Integer);
begin
  if Assigned(FOnSound) then
    FOnSound(Index);
end;

procedure TTitleScreen.MenuConfirm;
begin
  case FIndex of
    0, 1:
      begin
        { Original: GameState_Reset, p_GameState := 0x28, sub-mode records
          which of NEW GAME / CONTINUE was chosen. }
        GameStateValue := GS_PLAYER_INIT;
        FSubMode := FIndex;
        FIndex := 0;
      end;
    2:
      begin
        FIndex := 0;
        FSubMode := TSM_OPTIONS;
      end;
    3:
      GameStateValue := GS_QUIT;
  end;
end;

procedure TTitleScreen.OptionsConfirm;
begin
  { Row 8 shows an omake image if that slot is unlocked; row 9 leaves. The
    original returns to the menu with the cursor on OPTION (index 2). }
  if FIndex = OPT_ROW_EXIT then
  begin
    FSubMode := TSM_MENU;
    FIndex := 2;
  end;
  { TODO row 8: omake viewer, needs p_Settings+0x2C unlock flags }
end;

procedure TTitleScreen.DrawValues(C: TCanvas; F: TGameFont);

  procedure Val(Row: Integer; const S: string; Variant_: Integer = 0);
  begin
    F.TextOut(C, OPT_VALUE_X, $38 + Row * $10, S, Variant_);
  end;

  function OnOff(B: Boolean): string;
  begin
    if B then Result := TEXT_ON else Result := TEXT_OFF;
  end;

begin
  Val(0, IntToStr(Settings.GameLevel), 2);
  Val(1, OnOff(FullScreenOn));
  Val(2, IntToStr(Settings.KeyMap[0]) + KEY_SUFFIX);
  Val(3, IntToStr(Settings.KeyMap[1]) + KEY_SUFFIX);
  Val(4, IntToStr(Settings.KeyMap[2]) + KEY_SUFFIX);
  Val(5, OnOff(WaitOn));
  Val(6, OnOff(SoftwareVsync));
  Val(7, Format('%3d%%', [Settings.Volume * 10]));
  Val(8, IntToStr(Settings.GallerySel), 2);
end;

procedure TTitleScreen.AdjustValue(Delta: Integer);
begin
  if Delta = 0 then Exit;
  { Each row clamps to the range the original enforces; out-of-range moves are
    swallowed rather than clipped, matching its "if out of range then delta:=0". }
  case TOptionRow(FIndex) of
    orLevel:
      if (Settings.GameLevel + Delta >= LEVEL_MIN) and
         (Settings.GameLevel + Delta <= LEVEL_MAX) then
        Inc(Settings.GameLevel, Delta);
    orToggle1:    FullScreenOn := not FullScreenOn;
    orToggle2:    WaitOn := not WaitOn;
    orFrameLimit: SoftwareVsync := not SoftwareVsync;
    orVolume:
      if (Settings.Volume + Delta >= VOLUME_MIN) and
         (Settings.Volume + Delta <= VOLUME_MAX) then
        Inc(Settings.Volume, Delta);
    orOmake:
      if (Settings.GallerySel + Delta >= OMAKE_MIN) and
         (Settings.GallerySel + Delta <= OMAKE_MAX) then
        Inc(Settings.GallerySel, Delta);
  end;
end;

function TTitleScreen.Update(MoveY, MoveX: Integer; Confirm: Boolean): Boolean;
var
  Limit: Integer;
begin
  Result := False;

  case FSubMode of
    TSM_MENU:
      begin
        if MoveY <> 0 then
        begin
          { 0x0046245A: the cursor blip fires on any non-zero vertical input,
            BEFORE the index is wrapped, so it sounds even on the move that
            wraps around the ends. }
          PlaySound(SND_PI);
          FIndex := FIndex + MoveY;
          if FIndex < 0 then FIndex := High(MENU_ITEMS);
          if FIndex > High(MENU_ITEMS) then FIndex := 0;
        end;
        if Confirm then
        begin
          { 0x004624D7 and 0x0046253A - both branches of the confirm. }
          PlaySound(SND_OK);
          MenuConfirm;
          Result := GameStateValue <> GS_TITLE_MENU;
        end;
      end;

    TSM_OPTIONS:
      begin
        AdjustValue(MoveX);
        { Key rebinding on rows 2..4 still needs raw button polling rather than
          an axis - the original scans 16 buttons and swaps if already bound. }
        if MoveY <> 0 then
        begin
          { INFERRED, not individually traced: the options screen has its own
            call sites using the same two indices in the same roles
            (0x0046290F, 0x00462B1A for SND_PI; 0x00462996 onward for SND_OK),
            but which branch each sits on has not been read out. }
          PlaySound(SND_PI);
          Limit := Ord(High(TOptionRow));
          FIndex := FIndex + MoveY;
          if FIndex < 0 then FIndex := Limit;
          if FIndex > Limit then FIndex := 0;
        end;
        if Confirm then
        begin
          PlaySound(SND_OK);
          OptionsConfirm;
        end;
      end;

    TSM_OMAKE:
      if Confirm then
      begin
        FSubMode := TSM_OPTIONS;
        FIndex := Ord(orOmake);
      end;
  end;
end;

procedure TTitleScreen.Draw(C: TCanvas; F: TGameFont; BgMenu, BgOptions: TBitmap);
var
  I: Integer;
begin
  { The original blits p_Surfaces[1] for the menu and p_Surfaces[2] for options
    full-screen first. Colour variants match the original's param_5: 2 for menu
    items, 1 for the cursor, 0 for the credit line. }
  if F = nil then Exit;

  case FSubMode of
    TSM_MENU:
      begin
        if BgMenu <> nil then
          C.Draw(0, 0, BgMenu);
        for I := Low(MENU_ITEMS) to High(MENU_ITEMS) do
          F.TextOut(C, MENU_X, (I * 2 + $11) * 8, MENU_ITEMS[I], 2);
        F.TextOut(C, MENU_CURSOR_X, (FIndex * 2 + $11) * 8, '>', 1);
        F.TextOut(C, 0, $D8, CREDIT_TEXT, 0);
      end;

    TSM_OPTIONS:
      begin
        if BgOptions <> nil then
          C.Draw(0, 0, BgOptions);
        F.TextOut(C, 0, $20, OPT_TITLE, 2);
        for I := Low(OPT_LABELS) to High(OPT_LABELS) do
          { EXIT is drawn on the right at (0xE8, 200) in the original, not in
            the label column with the rest. }
          if I = OPT_ROW_EXIT then
            F.TextOut(C, OPT_VALUE_X, 200, OPT_LABELS[I], 2)
          else
            F.TextOut(C, OPT_LABEL_X, $38 + I * $10, OPT_LABELS[I], 2);
        DrawValues(C, F);
        F.TextOut(C, OPT_CURSOR_X, (FIndex * 2 + 7) * 8, OPT_CURSOR, 1);
      end;
  end;
end;

end.
