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
  GmMain in 'GmMain.pas' {Frm_main},
  QdaArchive, Classes, SysUtils;

{ $R *.res  -- re-enable once Lazarus generates akuji.res (icon/manifest) }

{ --selftest <qda> [outdir] : verify the archive reader against real data and
  exit. Writes selftest.log beside the executable, because this is a GUI-
  subsystem binary with no console attached - WriteLn goes nowhere. }
function SelfTest: Integer;
var
  A: TQdaArchive;
  I: Integer;
  Raw: TMemoryStream;
  Log: TStringList;
  OutDir: string;
begin
  Result := 0;
  Log := TStringList.Create;
  try
    try
      OutDir := '';
      if ParamCount >= 3 then
        OutDir := IncludeTrailingPathDelimiter(ParamStr(3));

      A := TQdaArchive.Create(ParamStr(2));
      try
        Log.Add(Format('archive: %s', [ParamStr(2)]));
        Log.Add(Format('entries: %d', [A.Count]));
        for I := 0 to A.Count - 1 do
        begin
          Log.Add(Format('%-18s off=%-9d size=%d',
            [A.Entries[I].Name, A.Entries[I].Offset, A.Entries[I].Size]));
          if OutDir <> '' then
          begin
            Raw := TMemoryStream.Create;
            try
              A.LoadRaw(I, Raw);
              Raw.SaveToFile(OutDir + A.Entries[I].Name);
            finally
              Raw.Free;
            end;
          end;
        end;
        Log.Add('OK');
      finally
        A.Free;
      end;
    except
      on E: Exception do
      begin
        Log.Add(Format('FAILED: %s: %s', [E.ClassName, E.Message]));
        Result := 1;
      end;
    end;
  finally
    Log.SaveToFile(ExtractFilePath(ParamStr(0)) + 'selftest.log');
    Log.Free;
  end;
end;

begin
  if ParamStr(1) = '--selftest' then
  begin
    ExitCode := SelfTest;
    Exit;
  end;

  Application.Initialize;
  Application.Title := 'Akuji the Demon';
  Application.CreateForm(TFrm_main, Frm_main);
  Application.Run;
end.
