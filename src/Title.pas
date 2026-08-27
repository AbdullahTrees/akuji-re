{ Title - the title screen and options, translated from Title_MainMenu
  @ 0x00462330.

  The original is one function with three sub-modes selected by p_TitleSubMode
  (0x0046CEF8):

    0  main menu    NEW GAME / CONTINUE / OPTION / EXIT
    1  options      10 rows, including three rebindable keys
    2  omake viewer a full-screen unlocked extra image

  Every string, coordinate and range below is taken from the decompilation.
  Coordinates are in the original's 320x240 space.

  NOT YET FAITHFUL: the original renders through Game_DrawText (0x004511EC),
  a bitmap font from font9x9-01.bmp in bmp.qda. This uses LCL text so the menu
  is navigable now; swapping in the real font is a separate job and will change
  metrics. }

unit Title;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, GameState;

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

  TTitleScreen = class
  private
    FSubMode: Integer;
    FIndex: Integer;          // p_MenuIndex 0x0046CF88, shared with the pause menu
    procedure MenuConfirm;
    procedure OptionsConfirm;
  public
    constructor Create;
    procedure Reset;
    { Returns True when the caller should leave the title screen; the new
      GameStateValue has already been set. }
    function Update(MoveY, MoveX: Integer; Confirm: Boolean): Boolean;
    procedure Draw(C: TCanvas);

    property SubMode: Integer read FSubMode;
    property Index: Integer read FIndex;
  end;

implementation

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
          FIndex := FIndex + MoveY;
          if FIndex < 0 then FIndex := High(MENU_ITEMS);
          if FIndex > High(MENU_ITEMS) then FIndex := 0;
        end;
        if Confirm then
        begin
          MenuConfirm;
          Result := GameStateValue <> GS_TITLE_MENU;
        end;
      end;

    TSM_OPTIONS:
      begin
        { TODO: MoveX adjusts the row's value - level, volume, toggles, omake
          index - each clamped to the ranges above. Key rebinding on rows 2..4
          needs raw button polling, not an axis. }
        if MoveY <> 0 then
        begin
          Limit := Ord(High(TOptionRow));
          FIndex := FIndex + MoveY;
          if FIndex < 0 then FIndex := Limit;
          if FIndex > Limit then FIndex := 0;
        end;
        if Confirm then
          OptionsConfirm;
      end;

    TSM_OMAKE:
      if Confirm then
      begin
        FSubMode := TSM_OPTIONS;
        FIndex := Ord(orOmake);
      end;
  end;
end;

procedure TTitleScreen.Draw(C: TCanvas);
var
  I: Integer;
begin
  { Placeholder rendering. The original blits p_Surfaces[1] for the menu and
    p_Surfaces[2] for options as a full-screen 320x240 background first. }
  C.Font.Color := clWhite;
  C.Brush.Style := bsClear;

  case FSubMode of
    TSM_MENU:
      begin
        for I := Low(MENU_ITEMS) to High(MENU_ITEMS) do
          C.TextOut(MENU_X, (I * 2 + $11) * 8, MENU_ITEMS[I]);
        C.TextOut(MENU_CURSOR_X, (FIndex * 2 + $11) * 8, '>');
        C.TextOut(0, $D8, CREDIT_TEXT);
      end;

    TSM_OPTIONS:
      begin
        C.TextOut(0, $20, '- OPTION -');
        C.TextOut(OPT_CURSOR_X, (FIndex * 2 + 7) * 8, '>');
      end;
  end;
end;

end.
