{ GmMain - Akuji the Demon, main form.

  Unit name, class name, instance name and the three event handlers below are
  all RECOVERED, not invented:
    - unit GmMain          from TTypeData.UnitName in the TFrm_main class RTTI
    - TFrm_main            from the same RTTI (86 published properties)
    - Frm_main             from the form resource
    - FormDestroy, FormKeyDown, DDDD1Init   from the form resource

  Everything below the component declarations is still to be rebuilt: roughly
  83 methods, translated from the decompilation. See CLAUDE.md sections 3 and 5.

  The published field names (DDDD1, Joy, KbgmPlayer1, DDSD1) MUST match
  GmMain.lfm exactly - the .lfm reader binds components to fields by name. }

unit GmMain;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, LCLType,
  DDDDComponent, DDIDComponent, DDSDComponent, KbgmPlayer;

type
  TFrm_main = class(TForm)
    DDDD1: TDDDD;
    Joy: TDDIDEX;
    KbgmPlayer1: TKbgmPlayer;
    DDSD1: TDDSD;
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DDDD1Init(Sender: TObject);
  private
    { TODO: the game's state lives here. The original's MainForm object had
      +0x2D0 (graphics/font) and +0x2DC (audio) among ~86 published properties. }
  public
  end;

var
  Frm_main: TFrm_main;

implementation

{$R *.lfm}

procedure TFrm_main.DDDD1Init(Sender: TObject);
begin
  { Original: DDDD1Init. Fires once the display surface is ready.
    TODO: asset loading and initial game state. }
end;

procedure TFrm_main.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  Joy.KeyDown(Key);
end;

procedure TFrm_main.FormDestroy(Sender: TObject);
begin
  { Original: FormDestroy. TODO: teardown. }
end;

end.
