{ Keyboard input component named `Joy` on the main form. LCL virtual keys are
  mapped to the game's movement, action, and auxiliary buttons. }

unit DDIDComponent;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, LCLType;

type
  TDDIDDebugOptionItem = (dioHaltOnError);
  TDDIDDebugOption = set of TDDIDDebugOptionItem;

  { Logical buttons consumed by the game. }
  TAkujiButton = (abUp, abDown, abLeft, abRight,
                  abAction1, abAction2, abAction3,
                  abAux1, abAux2, abAux3,
                  abJump);
  TAkujiButtons = set of TAkujiButton;

  TDDIDEX = class(TComponent)
  private
    FDebugOption: TDDIDDebugOption;
    FDown: TAkujiButtons;
  public
    { The LCL event handlers already maintain current state, so polling has no
      additional work in this backend. }
    procedure Update;

    function IsDown(Button: TAkujiButton): Boolean;

    { Called from the form's OnKeyDown/OnKeyUp. }
    procedure KeyDown(Key: Word);
    procedure KeyUp(Key: Word);

    property Down: TAkujiButtons read FDown;
  published
    property DebugOption: TDDIDDebugOption read FDebugOption write FDebugOption;
  end;

implementation

procedure TDDIDEX.Update;
begin
  { State is updated synchronously by KeyDown and KeyUp. }
end;

function TDDIDEX.IsDown(Button: TAkujiButton): Boolean;
begin
  Result := Button in FDown;
end;

{ One physical key to one logical button, or nothing. }
function ButtonOf(Key: Word; out Button: TAkujiButton): Boolean;
begin
  Result := True;
  case Key of
    VK_UP,    VK_NUMPAD8: Button := abUp;
    VK_DOWN,  VK_NUMPAD2: Button := abDown;
    VK_LEFT,  VK_NUMPAD4: Button := abLeft;
    VK_RIGHT, VK_NUMPAD6: Button := abRight;
    { Action 1 is also used for jump and menu confirmation. }
    VK_Z, VK_SPACE:       Button := abAction1;
    VK_X:                 Button := abAction2;
    VK_C:                 Button := abAction3;
    VK_A:                 Button := abAux1;
    VK_S:                 Button := abAux2;
    VK_D:                 Button := abAux3;
  else
    Result := False;
  end;
end;

procedure TDDIDEX.KeyDown(Key: Word);
var
  Button: TAkujiButton;
begin
  if ButtonOf(Key, Button) then
    Include(FDown, Button);
end;

procedure TDDIDEX.KeyUp(Key: Word);
var
  Button: TAkujiButton;
begin
  if ButtonOf(Key, Button) then
    Exclude(FDown, Button);
end;

initialization
  RegisterClass(TDDIDEX);

end.
