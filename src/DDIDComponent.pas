{ TDDIDEX - input component (named "Joy" on the form).

  The original wrapped DirectInput and read raw DIK scancodes. Those were
  recovered from DirectInput_Init @ 0x00453BDC and are in CLAUDE.md section 9:

      0x2C..0x2E   Z X C       actions
      0x1E..0x20   A S D       secondary
      0x02..0x0B   1..0        item select
      0x39         space       jump
      0xC8..0xCD   arrows      movement
      0x47..0x51   numpad      alt movement

  This maps the LCL virtual keys for the same physical keys, which is not the
  same table - LCL gives VK_* and DirectInput gives scancodes - but it is the
  same KEYBOARD. Where the two can disagree is layout: a scancode is a
  position and a VK is a letter, so on a non-QWERTY keyboard the original's
  'Z' and this 'Z' are different physical keys. Recorded rather than solved.

  Only what the game reads is mapped. The item-select digits have no reader
  yet, so they are left out rather than guessed at. }

unit DDIDComponent;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, LCLType;

type
  TDDIDDebugOptionItem = (dioHaltOnError);
  TDDIDDebugOption = set of TDDIDDebugOptionItem;

  { Logical buttons, from the recovered scancode map. Names are ours - the
    original's enum names are not known. }
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
    { Poll current state. No-op until wired to LCL key events. }
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
  { TODO: nothing to do while state is driven by KeyDown/KeyUp. }
end;

function TDDIDEX.IsDown(Button: TAkujiButton): Boolean;
begin
  Result := Button in FDown;
end;

{ One physical key to one logical button, or nothing. }
function ButtonOf(Key: Word; out B: TAkujiButton): Boolean;
begin
  Result := True;
  case Key of
    VK_UP,    VK_NUMPAD8: B := abUp;
    VK_DOWN,  VK_NUMPAD2: B := abDown;
    VK_LEFT,  VK_NUMPAD4: B := abLeft;
    VK_RIGHT, VK_NUMPAD6: B := abRight;
    { Z is the original's confirm and its first action; the game reads button
      0 for both jump and confirm, so space maps to the same one. }
    VK_Z, VK_SPACE:       B := abAction1;
    VK_X:                 B := abAction2;
    VK_C:                 B := abAction3;
    VK_A:                 B := abAux1;
    VK_S:                 B := abAux2;
    VK_D:                 B := abAux3;
  else
    Result := False;
  end;
end;

procedure TDDIDEX.KeyDown(Key: Word);
var
  B: TAkujiButton;
begin
  if ButtonOf(Key, B) then
    Include(FDown, B);
end;

procedure TDDIDEX.KeyUp(Key: Word);
var
  B: TAkujiButton;
begin
  if ButtonOf(Key, B) then
    Exclude(FDown, B);
end;

initialization
  RegisterClass(TDDIDEX);

end.
