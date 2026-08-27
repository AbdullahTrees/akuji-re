{ TDDIDEX - input component (named "Joy" on the form).

  STUB. See DDDDComponent.pas for the rationale.

  The original wrapped DirectInput. The game's actual key mapping was recovered
  from DirectInput_Init (0x00453bdc) and is recorded in CLAUDE.md section 10 -
  Z/X/C actions, A/S/D secondary, 1-0 item select, space jump, arrows and numpad
  for movement. Wire those up here when filling this in; the form also has its
  own FormKeyDown handler. }

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

procedure TDDIDEX.KeyDown(Key: Word);
begin
  { TODO: map VK_* to TAkujiButton per CLAUDE.md section 10. }
end;

procedure TDDIDEX.KeyUp(Key: Word);
begin
  { TODO: as above. }
end;

initialization
  RegisterClass(TDDIDEX);

end.
