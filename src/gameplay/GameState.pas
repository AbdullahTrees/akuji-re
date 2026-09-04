{ Shared game state, input state, settings, and frame timing. }

unit GameState;

{$MODE DELPHI}{$H+}

interface

const
  { The frame loop dispatches on these numeric states. }
  GS_TITLE_INIT  = 10;
  GS_TITLE_MENU  = 20;
  GS_STAGE_BEGIN = 30;
  GS_PLAYER_INIT = 40;
  GS_PLAY        = 60;
  GS_PLAY_ALT    = 100;
  GS_PAUSE       = 130;
  GS_STATE_140   = 140;
  GS_ENDING      = 150;
  GS_QUIT        = 999;   // clears OnIdle, terminates

  { Screen shake uses Random(16) - 8, producing -8..+7 each frame. }
  SHAKE_RANGE  = $10;
  SHAKE_CENTRE = 8;

  PAUSE_CONTINUE = 0;     // restores p_SavedGameState
  PAUSE_RESTART  = 1;     // -> GS_TITLE_INIT
  PAUSE_QUIT     = 2;     // -> GS_QUIT

  { One-time delay before the title screen first appears. }
  TITLE_INIT_SLEEP_MS = $168;   { 360 ms }

  SCREEN_W = 320;
  SCREEN_H = 240;

  { The frame loop advances when at least 16 ms have elapsed. }
  FRAME_MS = 16;
  { Maximum acceptable clock granularity for frame pacing. }
  FRAME_CLOCK_MAX_STEP_MS = 5;

type
  { Input state and frame-to-frame edge-detection fields. }
  TInputState = record
    AxisX: Integer;                        // +0x00
    AxisY: Integer;                        // +0x04
    HeldX: Integer;                        // +0x08  cleared when HoldTimer hits 0
    HeldY: Integer;                        // +0x0C
    Moving: Boolean;                       // +0x10  set when either axis <> 0
    AxisYNegative: Boolean;                // +0x11
    RepeatTimer: Integer;                  // +0x14  counts down
    HoldTimer: Integer;                    // +0x18  counts down
    Button: array[0..3] of Boolean;        // +0x1C  polled via KeyMap
    ButtonLatch: array[0..3] of Boolean;   // +0x20  edge-detect latch
    ButtonRepeat: array[0..3] of Integer;  // +0x24  per-button repeat counter
    AnyPressed: Boolean;                   // +0x34  any button newly pressed
  end;

type
  { The 56-byte data\system.dat layout. }
  TGameSettings = record
    CurrentStage: Integer;   // +0x00  Stage_Begin passes this to Load_Stage_Assets
    GameLevel: Integer;      // +0x04  0..2
    { Four logical-button mappings; defaults form the identity mapping. }
    KeyMap: array[0..3] of Integer;  // +0x08..+0x14
    SoftwareVsyncFlag: Byte; // +0x18
    WaitOnFlag: Byte;        // +0x19
    FullScreenFlag: Byte;    // +0x1A
    DebugLogFlag: Byte;      // +0x1B
    { Two persistent unlock flags, each gating one half of a locked-door pair
      (ev001 tile 24,7 and ev065 tile 10,7) into the game's last map. While the
      flag is clear a variant-2 type-25 door stands there doing nothing; set,
      that record retires and a variant-0 door appears carrying "load stage 65".

      Game_StartOrLoad copies them INTO the progress block at the start of every
      game and never back, which is why no event sets 1185 or 1194 - nothing in
      the game can. They live in system.dat, not save.dat, so they survive a new
      game: extras unlocks rather than progress. }
    ExtraDoor1: Byte;                // +0x1C  -> Progress[1185]
    ExtraDoor2: Byte;                // +0x1D  -> Progress[1194]
    Unknown1E: array[0..5] of Byte;  // +0x1E..+0x23
    Volume: Integer;         // +0x24  0..10, SE VOLUME
    GallerySel: Integer;     // +0x28  0..6
    { One flag per omake entry: Title_MainMenu indexes it by GallerySel, and
      Ending.pas fills it from Progress[1186..1192] when a run ends. }
    GalleryUnlocked: array[0..6] of Byte;  // +0x2C..+0x32
    Pad33: Byte;
    InputDevice: Integer;    // +0x34  from system.ini [device] input
  end;

var
  { Shared runtime globals. }
  Settings: TGameSettings;
  FullScreenOn: Boolean = False;
  WaitOn: Boolean = False;
  SoftwareVsync: Boolean = True;
  DebugLog: Boolean = False;
  GameStateValue: Integer = GS_TITLE_INIT;
  SavedGameState: Integer = 0;

  { Screen shake applies a fresh random displacement to the whole sprite pass
    each frame. Only the final boss's ground slam enables it. }
  ScreenShakeOn: Boolean = False;
  ScreenShakeTimer: Integer = 0;
  { One sub-phase counter shared by every screen that has to
    wait for a fade: the game-over screen steps 0 -> 1 -> 2 through it, the
    opening sequence runs its whole six-beat sequence on it, and the message
    box uses it as a wait flag. EventRunner.pas already described it from the
    interpreter's side. GameState_Reset zeroes it. }
  ScreenPhase: Integer = 0;
  { Which of NEW GAME / CONTINUE the title menu chose. }
  TitleSubMode: Integer = 0;
  { ONE variable, shared by the title menu, the options screen and the pause
    menu - so moving the cursor in one moves it in the others. }
  MenuIndex: Integer = 0;
  SavedMenuIndex: Integer = 0;
  Input: TInputState;
  { Runtime key mappings are copied from settings at startup and written back
    when settings are saved. }
  KeyMap: array[0..3] of Integer;

{ Confirm is the rising edge of either of the first two buttons:

      (Button[0] and not ButtonLatch[0]) or (Button[1] and not ButtonLatch[1])

  Both buttons participate in the rising-edge test. }
function ConfirmPressed(const Inp: TInputState): Boolean;

{ Maintain derived input fields after state handlers, so the latch
  a handler reads holds the PREVIOUS frame's button state - which is what makes
  "Button and not ButtonLatch" a rising edge.

  It also ages the double-tap window. Player_Update opens that window; this
  closes it and clears the remembered direction when it expires. }
procedure InputEndOfFrame(var Inp: TInputState; const Down: array of Boolean);

procedure EnterPause;
procedure LeavePause;

{ data\system.dat is a raw 56-byte image of TGameSettings, so the record must stay
  exactly that size - asserted at startup, the same guard TPlayerState uses.

  SaveSettings gathers the runtime globals back into the record first because
  those are what the options screen edits. }
function LoadSettings(const AGameDir: string): Boolean;
function SaveSettings(const AGameDir: string): Boolean;
procedure SettingsToGlobals;
procedure GlobalsToSettings;

{ The frame clock. MsClock.pas carries the reasoning and the
  measurements; these are here so the game layer does not have to
  name a component-level unit at every call site. }
function FrameClockMs: DWord;
procedure BeginFrameClock;
procedure EndFrameClock;

implementation

uses
  Classes, SysUtils, MsClock;

procedure InputEndOfFrame(var Inp: TInputState; const Down: array of Boolean);
var
  ButtonIndex: Integer;
begin
  if (Inp.AxisX = 0) and (Inp.AxisY = 0) then
  begin
    Inp.Moving := False;
    Inp.RepeatTimer := 0;
  end;
  Inp.AxisYNegative := Inp.AxisY < 0;
  if (Inp.AxisX <> 0) or (Inp.AxisY <> 0) then
    Inp.Moving := True;
  if Inp.RepeatTimer > 0 then Dec(Inp.RepeatTimer);
  if Inp.HoldTimer > 0 then Dec(Inp.HoldTimer);
  if Inp.HoldTimer = 0 then
  begin
    Inp.HeldX := 0;
    Inp.HeldY := 0;
  end;
  for ButtonIndex := 0 to 3 do
  begin
    if (ButtonIndex <= High(Down)) and Down[ButtonIndex] then
      Inp.ButtonLatch[ButtonIndex] := True
    else
    begin
      Inp.ButtonLatch[ButtonIndex] := False;
      Inp.ButtonRepeat[ButtonIndex] := 0;
    end;
    if Inp.ButtonRepeat[ButtonIndex] > 0 then
      Dec(Inp.ButtonRepeat[ButtonIndex]);
  end;
end;

function ConfirmPressed(const Inp: TInputState): Boolean;
begin
  Result := (Inp.Button[0] and not Inp.ButtonLatch[0])
         or (Inp.Button[1] and not Inp.ButtonLatch[1]);
end;

procedure EnterPause;
begin
  SavedMenuIndex := MenuIndex;
  MenuIndex := 0;
  SavedGameState := GameStateValue;
  GameStateValue := GS_PAUSE;
end;

function SettingsFileName(const AGameDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AGameDir) + 'data' + PathDelim +
            'system.dat';
end;

procedure SettingsToGlobals;
begin
  SoftwareVsync := Settings.SoftwareVsyncFlag <> 0;
  WaitOn        := Settings.WaitOnFlag <> 0;
  FullScreenOn  := Settings.FullScreenFlag <> 0;
  DebugLog      := Settings.DebugLogFlag <> 0;
end;

procedure GlobalsToSettings;
begin
  Settings.SoftwareVsyncFlag := Ord(SoftwareVsync);
  Settings.WaitOnFlag        := Ord(WaitOn);
  Settings.FullScreenFlag    := Ord(FullScreenOn);
  Settings.DebugLogFlag      := Ord(DebugLog);
end;

function LoadSettings(const AGameDir: string): Boolean;
var
  Stream: TFileStream;
  FileName: string;
begin
  Result := False;
  FileName := SettingsFileName(AGameDir);
  if not FileExists(FileName) then
    Exit;
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    { Refuse a short file rather than leaving part of the record uninitialized. }
    if Stream.Size < SizeOf(TGameSettings) then
      Exit;
    Stream.ReadBuffer(Settings, SizeOf(TGameSettings));
    Result := True;
  finally
    Stream.Free;
  end;
  if Result then
    SettingsToGlobals;
end;

function SaveSettings(const AGameDir: string): Boolean;
var
  Stream: TFileStream;
begin
  GlobalsToSettings;
  Result := False;
  try
    Stream := TFileStream.Create(SettingsFileName(AGameDir), fmCreate);
    try
      Stream.WriteBuffer(Settings, SizeOf(TGameSettings));
      Result := True;
    finally
      Stream.Free;
    end;
  except
    { A read-only game directory must not prevent shutdown. }
    on E: Exception do
      Result := False;
  end;
end;

procedure LeavePause;
begin
  GameStateValue := SavedGameState;
end;

function FrameClockMs: DWord;
begin
  Result := MsNow;
end;

procedure BeginFrameClock;
begin
  BeginMsClock;
end;

procedure EndFrameClock;
begin
  EndMsClock;
end;

initialization
  { This must remain a runtime check because disabling assertions must not make
    save-file layout errors silent. }
  if SizeOf(TGameSettings) <> $38 then
    raise Exception.CreateFmt('TGameSettings is %d bytes; data/system.dat is '
      + 'a raw image of it and must be 56', [SizeOf(TGameSettings)]);

end.
