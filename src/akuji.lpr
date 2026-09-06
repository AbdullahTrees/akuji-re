{ Akuji the Demon application entry point.

  Self-test modes exit before the application initializes; everything they run
  lives in selftests/. }

program akuji;

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces,   // LCL widgetset - must come first
  Forms,
  GmMain in 'screens\GmMain.pas' {Frm_main},
  SelfTests;

{ $R *.res  -- re-enable once Lazarus generates akuji.res (icon/manifest) }

{ DIVERGENCE DIV-007: self-test modes exit before application initialization;
  normal startup creates the main form and enters its idle-driven game loop. }
begin
  if IsSelfTestMode then
  begin
    ExitCode := RunSelfTest;
    Exit;
  end;

  Application.Initialize;
  Application.Title := 'Akuji the Demon';
  Application.CreateForm(TFrm_main, Frm_main);
  Application.Run;
end.
