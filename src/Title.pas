{ Title - the title screen and options, translated from Title_MainMenu
  @ 0x00462330.

  One function in the original, with three sub-modes on TitleSubMode: the main
  menu (NEW GAME / CONTINUE / OPTION / EXIT), the ten-row options screen, and
  the omake viewer. See TSM_* below.

  Every string, coordinate and range is from the decompilation, in the
  original's 320x240 space, drawn through the game's own font sheet.

  DIVERGENCE DIV-009: option value editing and key rebinding are stubbed -
  they need raw button polling rather than an axis. }

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

  { The three BUTTON ASSIGN rows draw a key NAME, not the index. 0x00462330
    indexes the table at 0x00468E44 through the cell at 0x0046D214 by
    KeyMap[n], and appends ' KEY'. Twelve entries, and they are the keys
    DirectInput_Init binds. }
  KEY_NAMES: array[0..11] of string =
    ('Z', 'X', 'C', 'A', 'S', 'D', '1', '2', '3', '4', '5', '6');

  { The GALLERY row draws a name from the table at 0x0046906C - through the
    cell at 0x0046D010, indexed by Settings+0x28 - in variant 2, and then a
    SECOND string at x 0x108 saying whether that slot is unlocked:

        if (p_Settings[sel + 0x2C] == 1)  DrawText(0x108, 0xB8, variant 0, 'ON')
        else                              DrawText(0x108, 0xB8, variant 2, 'OFF')

    so the marker's colour carries the state as much as the word does. }
  OMAKE_NAMES: array[0..6] of string =
    ('NO1', 'NO2', 'NO3', 'NO4', 'NO5', 'NO6', 'NO7');
  OMAKE_MARK_X = $108;

  { The POINTER CELLS the four tables are reached through - see the test that
    diffs the constants above against the image. }
  OPT_LEVEL_NAME_CELL    = $0046D1A0;
  OPT_LEVEL_VARIANT_CELL = $0046D348;
  OPT_KEY_NAME_CELL      = $0046D214;
  OPT_OMAKE_NAME_CELL    = $0046D010;

  { Ranges the original clamps to }
  { The GAME LEVEL row draws a NAME, not a number, and 0x00462330 indexes both
    tables by Settings+4 - so HARD is drawn in a different colour from the
    other two. Strings at 0x00469054, variants at 0x00469060. }
  LEVEL_NAMES: array[0..2] of string = ('EASY', 'NORMAL', 'HARD');
  LEVEL_VARIANTS: array[0..2] of Integer = (0, 0, 1);

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
  TNotifyProc = procedure of object;
  { 0x00462BE9 builds 'omake%.02d.bmp' and hands it to Ending_ShowPicture. }
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
    { 0x00462330, Title_MainMenu. Three sub-modes in one function: the menu,
      the options screen, and the gallery viewer. Returns True when the caller
      should leave the title screen; the new GameStateValue has already been
      set. }
    function Update(MoveY, MoveX: Integer; Confirm: Boolean): Boolean;
    procedure Draw(C: TCanvas; F: TGameFont;
                   BgMenu, BgOptions, Gallery: TBitmap);

    function GetIndex: Integer;
    function GetSubMode: Integer;
    { p_TitleSubMode @ 0x0046CEF8 - ONE variable, and this property is now a
      window onto it rather than a second copy. See GameState.pas. }
    property SubMode: Integer read GetSubMode;
  public
    { p_MenuIndex, the shared global - see GameState.pas. }
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

  { GameOver_Update @ 0x00461A44 - the shortest of the three screens that step
    through GameState.ScreenPhase. What it needs from outside is callbacks, so
    the unit stays clear of the component layer. }
  TFadeEvent = procedure(FadeIn: Boolean) of object;
  TMusicEvent = procedure(Track: Integer) of object;
  TRestartEvent = procedure of object;
  { Asked, not told. GameOver_Update calls FUN_00450FD0 for the answer at the
    point it uses it, so this has to be a query and not a value handed in. }
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
    { Returns True while the screen should be drawn, which is phase 2 only.

      MUSIC IS NOT A PARAMETER but a callback, because phase 1 starts the
      game-over midi in the SAME call that phase 2 asks whether music is
      playing. An answer handed in is from before that midi started, and a
      death that silenced the stage track first then leaves phase 2 at once
      and never shows the screen.

      Confirm and FadeBusy stay parameters: both are pure reads of state
      nothing in this call changes. }
    function Update(FadeBusy, Confirm: Boolean;
                    var AGameState: Integer): Boolean;

    property OnFade: TFadeEvent read FOnFade write FOnFade;
    property OnMusic: TMusicEvent read FOnMusic write FOnMusic;
    property OnRestart: TRestartEvent read FOnRestart write FOnRestart;
    property OnMusicPlaying: TQueryEvent
      read FOnMusicPlaying write FOnMusicPlaying;
  end;


const
  { --- PauseMenu_Update @ 0x00461EE4 --------------------------------------

    Three choices, and it BLACKS THE SCREEN OUT first - colour 0 over the whole
    320x240 - so the paused game is not visible behind the menu. Six lines, all
    centred.

    Button 2 resumes, restoring the menu index FormKeyDown stashed on the way
    in rather than leaving the pause cursor where it was. The original also
    writes the input record's own latches to swallow the press so the resumed
    game does not see it; that side effect is why Update takes the input var.

    The cursor moves only when Inp.Moving is FALSE. That is not "while
    standing still": InputEndOfFrame runs AFTER the state handlers, so during
    one Moving still holds the PREVIOUS frame's value, and testing it clear
    is a D-pad edge - one step per press, no auto-repeat. }
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
    { 0x00461EE4, PauseMenu_Update. Returns True if the menu is still up.
      Inp is var because the original writes its latches. The write-up is in
      the const block above; the address is repeated here because that is
      where tools/implemented.py looks. }
    function Update(var Inp: TInputState; var AGameState: Integer): Boolean;
    procedure Draw(C: TCanvas; F: TGameFont; ScreenW, ScreenH: Integer);
  end;

{ Where the pause menu's cursor sound goes. GmMain hooks it up. }
procedure SetPauseSound(E: TSoundEvent);

implementation

{ --- TPauseMenu ---------------------------------------------------------- }

{ The original calls MainForm.DDSD1.Play straight; this is the same hook the
  title screen uses so the unit stays off the component layer. }
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
    { NO EXIT HERE. Every arm of the original's confirm ends in
      `JMP 0x00462024`, which is the CANCEL test - not the epilogue at
      0x004620C7 - so a confirm falls through to the cancel test and then to
      the movement block. Two consequences, both the original's: a confirm and
      a cancel in the same frame let the cancel win and put the state back,
      and the cursor still moves on that frame.

      The cancel arm below DOES leave, and that is not an inconsistency:
      0x00462061 jumps to the epilogue, because the movement block is its
      `else`. }
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
  I, Y: Integer;
begin
  { Colour 0 over the whole screen - the paused game is NOT visible. }
  C.Brush.Color := clBlack;
  C.FillRect(0, 0, ScreenW, ScreenH);
  if F = nil then Exit;

  F.TextOutCentered(C, PAUSE_ROW_Y[0], 'CONTINUE', ScreenW, 2);
  F.TextOutCentered(C, PAUSE_ROW_Y[1], 'RESET', ScreenW, 2);
  F.TextOutCentered(C, PAUSE_ROW_Y[2], 'EXIT', ScreenW, 2);

  I := MenuIndex;
  if (I < 0) or (I > PAUSE_ITEMS - 1) then I := 0;
  Y := (I * PAUSE_CURSOR_MUL + PAUSE_CURSOR_ADD) * PAUSE_CURSOR_SCALE;
  F.TextOutCentered(C, Y, '<         >', ScreenW, 1);

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
    { GameState_Reset(mode 0) plus the asset reload and the font rebuild - one
      callback, because the host owns all three. The font rebuild is not
      redundant: the asset reload replaces surface slot 0, which IS the font
      sheet, so the glyph table has to be built again on top of it. }
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
        { The original does SEVEN things here, and this used to do two.
          GameState_Reset(mode 0) comes first, then the state, then the
          sub-mode records which of NEW GAME / CONTINUE was chosen, then the
          cursor, and then the OPENING's slide and timer are both zeroed -
          which is what makes the cutscene start from its first slide rather
          than wherever a previous run left it.

          THE INDEX IS READ INTO A TEMPORARY FIRST, and that ordering is the
          whole fix for "CONTINUE starts a new game". The original does:

              uVar3 = *p_MenuIndex;         <- saved BEFORE the reset
              GameState_Reset(form, 0);
              *p_GameState    = 0x28;
              *p_TitleSubMode = uVar3;      <- the saved copy, not a reload

          because GameState_Reset ZEROES p_MenuIndex. Reading the index after
          the reset always yields 0, which is NEW GAME, whichever row the
          cursor was on. This code read it afterwards and so could never
          record a continue. It became reachable when MenuIndex stopped being
          a private field and became the shared global the original has - the
          merge was right, and this ordering is the rest of that same fact. }
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
      { No sound. EXIT is the one choice the original does not acknowledge. }
      GameStateValue := GS_QUIT;
  end;
end;

procedure TTitleScreen.OptionsConfirm;
var
  Sel: Integer;
begin
  { Row 8 shows a gallery image if that slot is unlocked, and REFUSES with
    SND_NG if it is not - which is the only place in the menus that says no.
    The unlock bytes are system.dat +0x2C..+0x32, and Ending.pas is what
    fills them in. }
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

  { Row 9 leaves, and the original returns to the menu with the cursor on
    OPTION - index 2, not 0. }
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

{ 0x004629A0, the options arm's switch. Two things here were missing and both
  are audible or visible to the player.

  EVERY ROW ACKNOWLEDGES A CHANGE, and the sound is not the same on all of
  them. The original plays SND_OK on the level, the three toggles and the
  volume, and SND_PI - the quieter cursor blip - on the gallery row. It sounds
  only when the value actually MOVED: the clamp works by zeroing the delta
  first and then testing it, so a press against either end of a range is
  silent. The toggles have no range, so they always sound.

  THE VOLUME TAKES EFFECT IMMEDIATELY. The original follows the volume write
  with the same 57-channel sweep Title_Init does -

      for i := 0 to $38 do SetVolume(chan[i], (10 - vol) * -0x1C2)

  so the next sound you hear is at the new level. Storing the number and
  waiting for the next Title_Init meant the slider moved and nothing changed. }
procedure TTitleScreen.AdjustValue(Delta: Integer);
begin
  if Delta = 0 then Exit;
  { Each row clamps to the range the original enforces; out-of-range moves are
    swallowed rather than clipped, matching its "if out of range then delta:=0". }
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
          { 0x0046245A: the cursor blip fires on any non-zero vertical input,
            BEFORE the index is wrapped, so it sounds even on the move that
            wraps around the ends. }
          PlaySound(SND_PI);
          MenuIndex := MenuIndex + MoveY;
          if MenuIndex < 0 then MenuIndex := High(MENU_ITEMS);
          if MenuIndex > High(MENU_ITEMS) then MenuIndex := 0;
        end;
        if Confirm then
        begin
          { The sound belongs to the BRANCH, not to the confirm. EXIT is
            silent in the original - only NEW GAME, CONTINUE and OPTION play
            SND_OK - and playing it here made all four alike. }
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
  I: Integer;
begin
  { The original blits p_Surfaces[1] for the menu and p_Surfaces[2] for options
    full-screen first. Colour variants match the original's param_5: 2 for menu
    items, 1 for the cursor, 0 for the credit line. }
  { The gallery draws ONE sprite and no text, so it is handled before the font
    guard - the original's third arm is a Rect and a single TDDDD_DrawSprite,
    with no Game_DrawText anywhere in it. Sitting below the guard meant it
    never ran when the font had not been built. }
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
        for I := Low(MENU_ITEMS) to High(MENU_ITEMS) do
          F.TextOut(C, MENU_X, (I * 2 + $11) * 8, MENU_ITEMS[I], 2);
        F.TextOut(C, MENU_CURSOR_X, (MenuIndex * 2 + $11) * 8, '>', 1);
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
        F.TextOut(C, OPT_CURSOR_X, (MenuIndex * 2 + 7) * 8, OPT_CURSOR, 1);
      end;
  end;
end;

end.
