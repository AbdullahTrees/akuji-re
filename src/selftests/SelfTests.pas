{ Chooses and runs a self-test mode, and writes its log.

  The modes are listed once, in SELFTEST_MODES, so that adding one cannot leave
  the program recognising a switch it has no branch for or the reverse. }

unit SelfTests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

{ True when the command line asks for a self-test rather than the game. }
function IsSelfTestMode: Boolean;

{ Runs the mode named on the command line. Returns the process exit code. }
function RunSelfTest: Integer;

implementation

uses
  MediaTests, DataTests, StageTests, PlayerTests, TraceTests,
  LayoutTests, EntityTests, RunnerTests, SessionTests,
  EmuDiffTests;

const
  SELFTEST_MODES: array[0..17] of string = (
    '--selftest',
    '--selftest-audio',
    '--selftest-midi',
    '--playtest',
    '--mixdump',
    '--selftest-dir',
    '--selftest-mapprobe',
    '--selftest-events',
    '--selftest-settings',
    '--selftest-script',
    '--selftest-stages',
    '--selftest-player',
    '--selftest-trace',
    '--selftest-entities',
    '--selftest-layouts',
    '--selftest-runner',
    '--selftest-session',
    '--emudiff');

function IsSelfTestMode: Boolean;
var
  I: Integer;
begin
  for I := Low(SELFTEST_MODES) to High(SELFTEST_MODES) do
    if ParamStr(1) = SELFTEST_MODES[I] then
      Exit(True);
  Result := False;
end;

function RunSelfTest: Integer;
var
  Log: TStringList;
begin
  Result := 0;
  Log := TStringList.Create;
  try
    try
      if ParamStr(1) = '--selftest-audio' then
        Result := SelfTestAudio(Log)
      else if ParamStr(1) = '--selftest-midi' then
        Result := SelfTestMidi(Log)
      else if ParamStr(1) = '--playtest' then
        Result := PlayTest(Log)
      else if ParamStr(1) = '--mixdump' then
        Result := MixDump(Log)
      else if ParamStr(1) = '--selftest-dir' then
        Result := SelfTestDirections(Log)
      else if ParamStr(1) = '--selftest-mapprobe' then
        Result := SelfTestMapProbe(Log)
      else if ParamStr(1) = '--selftest-events' then
        Result := SelfTestEvents(Log)
      else if ParamStr(1) = '--selftest-settings' then
        Result := SelfTestSettings(Log)
      else if ParamStr(1) = '--selftest-script' then
        Result := SelfTestScript(Log)
      else if ParamStr(1) = '--selftest-stages' then
        Result := SelfTestStages(Log)
      else if ParamStr(1) = '--selftest-player' then
        Result := SelfTestPlayer(Log)
      else if ParamStr(1) = '--selftest-trace' then
        Result := SelfTestTrace(Log)
      else if ParamStr(1) = '--selftest-entities' then
        Result := SelfTestEntities(Log)
      else if ParamStr(1) = '--selftest-layouts' then
        Result := SelfTestLayouts(Log)
      else if ParamStr(1) = '--selftest-runner' then
        Result := SelfTestRunner(Log)
      else if ParamStr(1) = '--selftest-session' then
        Result := SelfTestSession(Log)
      else if ParamStr(1) = '--emudiff' then
        Result := EmuDiff(Log)
      else
        Result := SelfTestArchive(Log);
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

end.
