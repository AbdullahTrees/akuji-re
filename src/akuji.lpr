{ Akuji the Demon - Free Pascal / Lazarus source port.

  This file is a faithful reconstruction of the original Delphi .dpr program
  block, recovered from `entry` at 0x004671ac in akuji.exe:

      Delphi_RTL_Init(&LAB_00466ee4);
      TApplication_Initialize();
      TApplication_SetTitle(Application, "Akuji the Demon");
      TApplication_CreateForm(Application, PTR_PTR_00464b54, MainForm);
      TApplication_Run(Application);
      Delphi_Halt0();

  The unit name GmMain was recovered from the class RTTI (TTypeData.UnitName
  for TFrm_main). See CLAUDE.md section 5. }

program akuji;

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces,   // LCL widgetset - must come first
  Forms,
  GmMain in 'GmMain.pas' {Frm_main};

{$R *.res}

begin
  Application.Initialize;
  Application.Title := 'Akuji the Demon';
  Application.CreateForm(TFrm_main, Frm_main);
  Application.Run;
end.
