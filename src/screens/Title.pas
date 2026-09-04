{ Title menu, options, gallery, pause menu, and game-over screen. }

unit Title;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, GameState, GameFont, SoundTable;

const
  { Title-screen sub-modes. }
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

  { The cursor is a BRACKET PAIR around the row, not a single mark: eight
    spaces wide, so starting eight pixels left of MENU_X puts the '<' before
    the row's first glyph and the '>' after its last. }
  MENU_CURSOR = '<        >';

  { Game_DrawText's fourth argument is the CENTRED flag, and this is the one
    line on the screen that passes 1 - the menu rows centre themselves inside
    their eight characters instead. }
  CREDIT_TEXT = 'CREATED BY E.HASHIMOTO';
  CREDIT_Y = $D8;
  TITLE_SCREEN_W = $140;

  { Options rows. Labels x=0x28, values x=0xE8,
    rows at y = 0x38 + row*0x10; cursor y = (index*2 + 7) * 8 }
  OPT_LABEL_X  = $28;
  OPT_VALUE_X  = $E8;
  OPT_CURSOR_X = $E0;
  OPT_ROW_EXIT = 9;
  OPT_TITLE    = '- OPTION -';
  OPT_TITLE_Y  = $20;
  OPT_CURSOR   = '<       >';    { brackets the value column }

  { Labels in cursor order. }
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

  { Names shown for the twelve bindable keys. }
  KEY_NAMES: array[0..11] of string =
    ('Z', 'X', 'C', 'A', 'S', 'D', '1', '2', '3', '4', '5', '6');

  { Gallery slot names; the ON/OFF marker uses a distinct colour variant. }
  OMAKE_NAMES: array[0..6] of string =
    ('NO1', 'NO2', 'NO3', 'NO4', 'NO5', 'NO6', 'NO7');
  OMAKE_MARK_X = $108;

  { Reference addresses used by table-validation self-tests. }
  OPT_LEVEL_NAME_CELL    = $0046D1A0;
  OPT_LEVEL_VARIANT_CELL = $0046D348;
  OPT_KEY_NAME_CELL      = $0046D214;
  OPT_OMAKE_NAME_CELL    = $0046D010;

  { Editable option ranges. }
  { HARD uses a distinct colour variant. }
  LEVEL_NAMES: array[0..2] of string = ('EASY', 'NORMAL', 'HARD');
  LEVEL_VARIANTS: array[0..2] of Integer = (0, 0, 1);

  LEVEL_MIN = 0;  LEVEL_MAX = 2;    // p_Settings+0x04
  VOLUME_MIN = 0; VOLUME_MAX = 10;  // p_Settings+0x24
  OMAKE_MIN = 0;  OMAKE_MAX = 6;    // p_Settings+0x28

type
  { Option rows in cursor order. Rows 2..4 are rebindable keys. }
  TOptionRow = (orLevel, orToggle1, orKey0, orKey1, orKey2,
                orToggle2, orFrameLimit, orVolume, orOmake, orExit);

  { Callbacks keep this unit independent of the component layer. }
  TSoundEvent = procedure(Index: Integer) of object;
  TNotifyProc = procedure of object;
  { Opens the selected gallery image. }
  TGalleryEvent = procedure(Slot: Integer) of object;

  TTitleScreen = class
  private
    FOnSound: TSoundEvent;
    FOnResetState: TNotifyProc;
    FOnResetOpening: TNotifyProc;
    FOnVolume: TNotifyProc;
    FOnGallery: TGalleryEvent;
    procedure PlaySound(Index: Integer);
    procedure MenuConfirm;
    procedure OptionsConfirm;
    procedure DrawValues(C: TCanvas; F: TGameFont);
    procedure AdjustValue(Delta: Integer);
  public
    constructor Create;
    procedure Reset;
    { Returns True when the caller should leave the title screen. }
    function Update(MoveY, MoveX: Integer; Confirm: Boolean): Boolean;
    procedure Draw(C: TCanvas; F: TGameFont;
                   BgMenu, BgOptions, Gallery: TBitmap);

    function GetIndex: Integer;
    function GetSubMode: Integer;
    { Exposes the shared title sub-mode from GameState. }
    property SubMode: Integer read GetSubMode;
  public
    { Exposes the shared menu cursor from GameState. }
    property Index: Integer read GetIndex;
    property OnSound: TSoundEvent read FOnSound write FOnSound;
    { GameState_Reset(mode 0), and the opening's two counters. Callbacks
      because neither belongs to this unit. }
    property OnResetState: TNotifyProc read FOnResetState write FOnResetState;
    property OnResetOpening: TNotifyProc read FOnResetOpening
                                         write FOnResetOpening;
    property OnGallery: TGalleryEvent read FOnGallery write FOnGallery;
    { The 57-channel volume sweep, which belongs to the sound device rather
      than to this unit. }
    property OnVolume: TNotifyProc read FOnVolume write FOnVolume;
  end;

  { External operations used by the game-over screen. }
  TFadeEvent = procedure(FadeIn: Boolean) of object;
  TMusicEvent = procedure(Track: Integer) of object;
  TRestartEvent = procedure of object;
  { Queries music state at the point it is needed. }
  TQueryEvent = function: Boolean of object;

const
  GAMEOVER_MIDI = 2;        { AutoLoadMidis[2] is midi\gameover }
  GAMEOVER_SURFACE = 3;     { the full-screen image }

type
  TGameOverScreen = class
  private
    FOnFade: TFadeEvent;
    FOnMusic: TMusicEvent;
    FOnRestart: TRestartEvent;
    FOnMusicPlaying: TQueryEvent;
  public
    { Returns True while phase 2 should be drawn. Music state is queried after
      phase 1 has started the game-over track. }
    function Update(FadeBusy, Confirm: Boolean;
                    var AGameState: Integer): Boolean;

    property OnFade: TFadeEvent read FOnFade write FOnFade;
    property OnMusic: TMusicEvent read FOnMusic write FOnMusic;
    property OnRestart: TRestartEvent read FOnRestart write FOnRestart;
    property OnMusicPlaying: TQueryEvent
      read FOnMusicPlaying write FOnMusicPlaying;
  end;


const
  { The pause menu covers the game with black. Update receives mutable input
    so it can consume the button used to leave the menu. Moving still contains
    the previous frame's value, providing one cursor step per press. }
  PAUSE_ITEMS = 3;
  PAUSE_ROW_Y: array[0..PAUSE_ITEMS - 1] of Integer = ($50, $60, $70);
  PAUSE_CURSOR_MUL = 2;     { (index * 2 + 10) * 8 lands on the rows above }
  PAUSE_CURSOR_ADD = 10;
  PAUSE_CURSOR_SCALE = 8;
  PAUSE_HINT1_Y = $90;
  PAUSE_HINT2_Y = $A0;
  PAUSE_CANCEL_BUTTON = 2;
  PAUSE_SND_MOVE = 0;

type
  TPauseMenu = class
  public
    { Returns True while the pause menu remains active. }
    function Update(var Inp: TInputState; var AGameState: Integer): Boolean;
    procedure Draw(C: TCanvas; F: TGameFont; ScreenW, ScreenH: Integer);
  end;

{ Where the pause menu's cursor sound goes. GmMain hooks it up. }
procedure SetPauseSound(E: TSoundEvent);

implementation

{ --- TPauseMenu ---------------------------------------------------------- }

{ Shared sound hook for pause-menu feedback. }
var
  PauseSound: TSoundEvent = nil;

procedure SetPauseSound(E: TSoundEvent);
begin
  PauseSound := E;
end;

procedure PlayPauseSound(Index: Integer);
begin
  if Assigned(PauseSound) then
    PauseSound(Index);
end;

function TPauseMenu.Update(var Inp: TInputState;
                           var AGameState: Integer): Boolean;
begin
  Result := True;

  if ScreenPhase = 0 then
  begin
    ScreenPhase := 1;
    MenuIndex := 0;
  end;

  if ConfirmPressed(Inp) then
  begin
    { Swallow the press so the resumed game does not also see it. }
    Inp.ButtonLatch[0] := True;
    case MenuIndex of
      PAUSE_CONTINUE: AGameState := SavedGameState;
      PAUSE_RESTART:  AGameState := GS_TITLE_INIT;
      PAUSE_QUIT:     AGameState := GS_QUIT;
    end;
    Result := False;
    { Confirm deliberately falls through: cancel may override it in the same
      frame, and cursor movement still runs. }
  end;

  if Inp.Button[PAUSE_CANCEL_BUTTON]
     and not Inp.ButtonLatch[PAUSE_CANCEL_BUTTON] then
  begin
    Inp.ButtonLatch[PAUSE_CANCEL_BUTTON] := True;
    { The index FormKeyDown stashed, not the pause cursor. }
    MenuIndex := SavedMenuIndex;
    AGameState := SavedGameState;
    Result := False;
    Exit;
  end;

  { Moving still holds LAST frame's value here, so this is a fresh press. }
  if not Inp.Moving then
  begin
    if Inp.AxisY <> 0 then
      PlayPauseSound(PAUSE_SND_MOVE);
    Inc(MenuIndex, Inp.AxisY);
    if MenuIndex < 0 then
      MenuIndex := PAUSE_ITEMS - 1;
    if MenuIndex > PAUSE_ITEMS - 1 then
      MenuIndex := 0;
  end;
end;

procedure TPauseMenu.Draw(C: TCanvas; F: TGameFont; ScreenW, ScreenH: Integer);
var
  SelectedIndex, CursorY: Integer;
begin
  { Colour 0 over the whole screen - the paused game is NOT visible. }
  C.Brush.Color := clBlack;
  C.FillRect(0, 0, ScreenW, ScreenH);
  if F = nil then Exit;

  F.TextOutCentered(C, PAUSE_ROW_Y[0], 'CONTINUE', ScreenW, 2);
  F.TextOutCentered(C, PAUSE_ROW_Y[1], 'RESET', ScreenW, 2);
  F.TextOutCentered(C, PAUSE_ROW_Y[2], 'EXIT', ScreenW, 2);

  SelectedIndex := MenuIndex;
  if (SelectedIndex < 0) or (SelectedIndex > PAUSE_ITEMS - 1) then
    SelectedIndex := 0;
  CursorY := (SelectedIndex * PAUSE_CURSOR_MUL + PAUSE_CURSOR_ADD)
    * PAUSE_CURSOR_SCALE;
  F.TextOutCentered(C, CursorY, '<         >', ScreenW, 1);

  F.TextOutCentered(C, PAUSE_HINT1_Y, 'CTRL+R ... RESET', ScreenW, 1);
  F.TextOutCentered(C, PAUSE_HINT2_Y, '   ESC ... EXIT ', ScreenW, 1);
end;


{ --- TGameOverScreen ----------------------------------------------------- }

function TGameOverScreen.Update(FadeBusy, Confirm: Boolean;
                                var AGameState: Integer): Boolean;
var
  MusicPlaying: Boolean;
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
    { Restart also rebuilds the font because reloading assets replaces its
      source surface. }
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
    { Held for exactly as long as the tune, unless you cut it short. Asked
      HERE, after phase 1 has started that tune - see the note on Update. }
    MusicPlaying := Assigned(FOnMusicPlaying) and FOnMusicPlaying();
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

function TTitleScreen.GetIndex: Integer;
begin
  Result := MenuIndex;
end;

function TTitleScreen.GetSubMode: Integer;
begin
  Result := TitleSubMode;
end;

procedure TTitleScreen.Reset;
begin
  TitleSubMode := TSM_MENU;
  MenuIndex := 0;
end;

procedure TTitleScreen.PlaySound(Index: Integer);
begin
  if Assigned(FOnSound) then
    FOnSound(Index);
end;

procedure TTitleScreen.MenuConfirm;
var
  Chosen: Integer;
begin
  case MenuIndex of
    0, 1:
      begin
        { Preserve the selection because resetting game state clears MenuIndex.
          Resetting the opening also restarts its cutscene. }
        PlaySound(SND_OK);
        Chosen := MenuIndex;
        if Assigned(FOnResetState) then
          FOnResetState;
        GameStateValue := GS_PLAYER_INIT;
        ScreenPhase := 0;
        TitleSubMode := Chosen;
        MenuIndex := 0;
        if Assigned(FOnResetOpening) then
          FOnResetOpening;
      end;
    2:
      begin
        PlaySound(SND_OK);
        MenuIndex := 0;
        TitleSubMode := TSM_OPTIONS;
      end;
    3:
      { Exit is intentionally silent. }
      GameStateValue := GS_QUIT;
  end;
end;

procedure TTitleScreen.OptionsConfirm;
var
  Sel: Integer;
begin
  { Row 8 opens an unlocked gallery slot and plays a rejection sound otherwise. }
  if MenuIndex = Ord(orOmake) then
  begin
    Sel := Settings.GallerySel;
    if (Sel >= 0) and (Sel <= High(Settings.GalleryUnlocked))
       and (Settings.GalleryUnlocked[Sel] = 1) then
    begin
      if Assigned(FOnGallery) then
        FOnGallery(Sel);
      PlaySound(SND_OK);
      TitleSubMode := TSM_OMAKE;
    end
    else
      PlaySound(SND_NG);
    Exit;
  end;

  { Return to the main menu with OPTION selected. }
  if MenuIndex = OPT_ROW_EXIT then
  begin
    PlaySound(SND_OK);
    TitleSubMode := TSM_MENU;
    MenuIndex := 2;
  end;
end;

procedure TTitleScreen.DrawValues(C: TCanvas; F: TGameFont);

  procedure Val(Row: Integer; const S: string; Variant_: Integer = 0);
  begin
    F.TextOut(C, OPT_VALUE_X, $38 + Row * $10, S, Variant_);
  end;

  { Out-of-range is drawn as the raw index rather than crashing - the settings
    file is a 56-byte blob the player can corrupt. }
  function KeyName(Index: Integer): string;
  begin
    if (Index >= Low(KEY_NAMES)) and (Index <= High(KEY_NAMES)) then
      Result := KEY_NAMES[Index] + KEY_SUFFIX
    else
      Result := IntToStr(Index) + KEY_SUFFIX;
  end;

  function OnOff(B: Boolean): string;
  begin
    if B then Result := TEXT_ON else Result := TEXT_OFF;
  end;

begin
  if (Settings.GameLevel >= LEVEL_MIN) and (Settings.GameLevel <= LEVEL_MAX) then
    Val(0, LEVEL_NAMES[Settings.GameLevel],
        LEVEL_VARIANTS[Settings.GameLevel]);
  Val(1, OnOff(FullScreenOn));
  Val(2, KeyName(Settings.KeyMap[0]));
  Val(3, KeyName(Settings.KeyMap[1]));
  Val(4, KeyName(Settings.KeyMap[2]));
  Val(5, OnOff(WaitOn));
  Val(6, OnOff(SoftwareVsync));
  Val(7, Format('%3d%%', [Settings.Volume * 10]));
  if (Settings.GallerySel >= OMAKE_MIN) and (Settings.GallerySel <= OMAKE_MAX) then
  begin
    Val(8, OMAKE_NAMES[Settings.GallerySel], 2);
    { The unlock marker, at its own x and with its own variant. }
    if Settings.GalleryUnlocked[Settings.GallerySel] = 1 then
      F.TextOut(C, OMAKE_MARK_X, $38 + 8 * $10, TEXT_ON, 0)
    else
      F.TextOut(C, OMAKE_MARK_X, $38 + 8 * $10, TEXT_OFF, 2);
  end;
end;

{ Adjusts the selected option. Bounded values are silent at their limits;
  gallery selection uses SND_PI and other changes use SND_OK. }
procedure TTitleScreen.AdjustValue(Delta: Integer);
begin
  if Delta = 0 then Exit;
  { Out-of-range adjustments are ignored rather than clipped. }
  case TOptionRow(MenuIndex) of
    orLevel:
      if (Settings.GameLevel + Delta >= LEVEL_MIN) and
         (Settings.GameLevel + Delta <= LEVEL_MAX) then
      begin
        PlaySound(SND_OK);
        Inc(Settings.GameLevel, Delta);
      end;
    orToggle1:
      begin
        PlaySound(SND_OK);
        FullScreenOn := not FullScreenOn;
      end;
    orToggle2:
      begin
        PlaySound(SND_OK);
        WaitOn := not WaitOn;
      end;
    orFrameLimit:
      begin
        PlaySound(SND_OK);
        SoftwareVsync := not SoftwareVsync;
      end;
    orVolume:
      if (Settings.Volume + Delta >= VOLUME_MIN) and
         (Settings.Volume + Delta <= VOLUME_MAX) then
      begin
        PlaySound(SND_OK);
        Inc(Settings.Volume, Delta);
        { The sweep, immediately - see the header. }
        if Assigned(FOnVolume) then
          FOnVolume;
      end;
    orOmake:
      if (Settings.GallerySel + Delta >= OMAKE_MIN) and
         (Settings.GallerySel + Delta <= OMAKE_MAX) then
      begin
        { SND_PI here, not SND_OK - the gallery row is the one exception. }
        PlaySound(SND_PI);
        Inc(Settings.GallerySel, Delta);
      end;
  end;
end;

function TTitleScreen.Update(MoveY, MoveX: Integer; Confirm: Boolean): Boolean;
var
  Limit: Integer;
begin
  Result := False;

  case TitleSubMode of
    TSM_MENU:
      begin
        if MoveY <> 0 then
        begin
          { Cursor movement sounds before wrapping at either end. }
          PlaySound(SND_PI);
          MenuIndex := MenuIndex + MoveY;
          if MenuIndex < 0 then MenuIndex := High(MENU_ITEMS);
          if MenuIndex > High(MENU_ITEMS) then MenuIndex := 0;
        end;
        if Confirm then
        begin
          { Each branch chooses its own confirmation sound; exit stays silent. }
          MenuConfirm;
          Result := GameStateValue <> GS_TITLE_MENU;
        end;
      end;

    TSM_OPTIONS:
      begin
        AdjustValue(MoveX);
        { DIVERGENCE DIV-009: key rebinding is unavailable. }
        { Key rebinding still requires raw button polling and is not handled by
          this directional-input interface. }
        if MoveY <> 0 then
        begin
          PlaySound(SND_PI);
          Limit := Ord(High(TOptionRow));
          MenuIndex := MenuIndex + MoveY;
          if MenuIndex < 0 then MenuIndex := Limit;
          if MenuIndex > Limit then MenuIndex := 0;
        end;
        if Confirm then
          { Same again: rows 0..7 are silent on confirm, row 8 plays SND_OK
            or SND_NG depending on whether that gallery slot is unlocked, and
            row 9 plays SND_OK. }
          OptionsConfirm;
      end;

    TSM_OMAKE:
      if Confirm then
      begin
        TitleSubMode := TSM_OPTIONS;
        MenuIndex := Ord(orOmake);
      end;
  end;
end;

procedure TTitleScreen.Draw(C: TCanvas; F: TGameFont;
                            BgMenu, BgOptions, Gallery: TBitmap);
var
  ItemIndex: Integer;
begin
  { The gallery has no text, so it can draw without an initialized font. }
  if TitleSubMode = TSM_OMAKE then
  begin
    if Gallery <> nil then
      C.Draw(0, 0, Gallery);
    Exit;
  end;

  if F = nil then Exit;

  case TitleSubMode of
    TSM_MENU:
      begin
        if BgMenu <> nil then
          C.Draw(0, 0, BgMenu);
        for ItemIndex := Low(MENU_ITEMS) to High(MENU_ITEMS) do
          F.TextOut(C, MENU_X, (ItemIndex * 2 + $11) * 8,
                    MENU_ITEMS[ItemIndex], 2);
        F.TextOut(C, MENU_CURSOR_X, (MenuIndex * 2 + $11) * 8, MENU_CURSOR, 1);
        F.TextOutCentered(C, CREDIT_Y, CREDIT_TEXT, TITLE_SCREEN_W, 0);
      end;

    TSM_OPTIONS:
      begin
        if BgOptions <> nil then
          C.Draw(0, 0, BgOptions);
        { The heading is centered like the credit line. }
        F.TextOutCentered(C, OPT_TITLE_Y, OPT_TITLE, TITLE_SCREEN_W, 2);
        for ItemIndex := Low(OPT_LABELS) to High(OPT_LABELS) do
          { EXIT occupies the value column rather than the label column. }
          if ItemIndex = OPT_ROW_EXIT then
            F.TextOut(C, OPT_VALUE_X, 200, OPT_LABELS[ItemIndex], 2)
          else
            F.TextOut(C, OPT_LABEL_X, $38 + ItemIndex * $10,
                      OPT_LABELS[ItemIndex], 2);
        DrawValues(C, F);
        F.TextOut(C, OPT_CURSOR_X, (MenuIndex * 2 + 7) * 8, OPT_CURSOR, 1);
      end;
  end;
end;

end.
