{ GameState - the game's global state, recovered from TFrm_main_AppIdle.

  Every constant and field offset here came from the decompilation; the names are
  ours where the original's were not recoverable. Addresses are given so anything
  here can be re-checked against the binary.

  This unit is a reconstruction, not a verbatim recovery like GmMain.lfm. Treat
  the field layouts as "best current understanding" and correct them as more of
  the game is translated. }

unit GameState;

{$MODE DELPHI}{$H+}

interface

const
  { p_GameState @ 0x0046D06C. The frame loop dispatches on this; values step
    by 10. Handlers are named where identified. }
  GS_TITLE_INIT  = 10;    // Title_Init            0x0046214C  boot into title
  GS_TITLE_MENU  = 20;    // Title_MainMenu        0x00462330  NEW GAME/CONTINUE/OPTION/EXIT
  GS_STAGE_BEGIN = 30;    // Stage_Begin           0x00462210 -> sets GS_PLAY
  GS_PLAYER_INIT = 40;    // Game_Init_PlayerState 0x00462F40
  GS_PLAY        = 60;    // FUN_00454790 + HUD_Draw
  GS_PLAY_ALT    = 100;   // FUN_00461A44 + HUD_Draw
  GS_PAUSE       = 130;   // PauseMenu_Update      0x00461EE4
  GS_STATE_140   = 140;   // FUN_00454790, FUN_00455210, HUD_Draw
  { CORRECTED. This was recorded as Opening_Update @ 0x00463154, an intro
    cutscene. It is neither. AppIdle's arm for 150 calls 0x00463624, which is
    the ENDING - the results screen the soulget sub-op sends you to - and
    0x00463154's only caller is Game_StartOrLoad, so it is part of starting a
    game and not a state handler at all. }
  GS_ENDING      = 150;   // Ending_Update         0x00463624  results screen
  GS_QUIT        = 999;   // clears OnIdle, terminates

  { PauseMenu_Update selection, p_PauseMenuIndex @ 0x0046CF88 }
  { 0x00464D30's shake: Random(0x10) - 8, so -8..+7 inclusive, recomputed on
    every frame the shake is on. }
  SHAKE_RANGE  = $10;
  SHAKE_CENTRE = 8;

  PAUSE_CONTINUE = 0;     // restores p_SavedGameState
  PAUSE_RESTART  = 1;     // -> GS_TITLE_INIT
  PAUSE_QUIT     = 2;     // -> GS_QUIT

  { Title_Init sleeps this long the first time it runs and never again -
    0x0046CFE8 is the flag that remembers. }
  TITLE_INIT_SLEEP_MS = $168;   { 360 ms }

  SCREEN_W = 320;
  SCREEN_H = 240;

  { The original spin-waited on timeGetTime until >15 ms had passed. Same
    target rate, but the rebuild must sleep rather than burn a core. }
  { The original spins while `timeGetTime - LastFrameTime <= 15`, so it
    proceeds at 16 and up. This threshold was never the problem - the
    CLOCK was. See FrameClockMs. }
  FRAME_MS = 16;
  { What --selftest-player will tolerate from FrameClockMs. Chosen to
    separate a 1 ms clock from a 15.6 ms one, not to be tight. }
  FRAME_CLOCK_MAX_STEP_MS = 5;

type
  { p_InputState @ 0x0046CC58. Offsets in comments are from the original;
    the interpretation of +0x08..+0x18 is provisional. }
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
  { data\system.dat, 56 bytes. Field meanings recovered from Title_Init,
    DDDD1Init and the options screen. Offsets are the original's. }
  TGameSettings = record
    CurrentStage: Integer;   // +0x00  Stage_Begin passes this to Load_Stage_Assets
    GameLevel: Integer;      // +0x04  0..2
    { FOUR entries, not three. FormDestroy @ 0x00466644 copies p_KeyMap[0..3]
      into +0x08, +0x0C, +0x10 and +0x14, so the old 'Field14' was the fourth
      key slot. The shipped file holds 0,1,2,3 - the identity mapping. }
    KeyMap: array[0..3] of Integer;  // +0x08..+0x14
    { FormDestroy names each of these by the global it copies from. }
    SoftwareVsyncFlag: Byte; // +0x18  <- p_SoftwareVsync 0x0046CE60
    WaitOnFlag: Byte;        // +0x19  <- p_WaitOn        0x0046D2E4
    FullScreenFlag: Byte;    // +0x1A  <- p_FullScreenOn  0x0046D268
    DebugLogFlag: Byte;      // +0x1B  <- p_DebugLog      0x0046CDB8
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

{ Every p_* address below names a POINTER CELL, not the variable: the original
  loads the cell and dereferences it (0x00459EE5 is the clearest instance), and
  none of the seven is ever stored to. The meanings are right; the addresses are
  one indirection short, so a trace or snapshot that reads them gets a pointer
  and reports it as a value. What the pointers point INTO is not established.
  They are left as they are because Ghidra and every other note use them.
  Census and trace in notes/trace_findings.md. }

var
  { Globals matching the original's, named after the p_* labels in Ghidra. }
  Settings: TGameSettings;                  // p_Settings        cell 0x0046D0E8
  FullScreenOn: Boolean = False;            // p_FullScreenOn    cell 0x0046D268
  WaitOn: Boolean = False;                  // p_WaitOn          cell 0x0046D2E4
  SoftwareVsync: Boolean = True;            // p_SoftwareVsync   cell 0x0046CE60
  DebugLog: Boolean = False;                // p_DebugLog        cell 0x0046CDB8
  GameStateValue: Integer = GS_TITLE_INIT;  // p_GameState       cell 0x0046D06C
  SavedGameState: Integer = 0;              // p_SavedGameState  cell 0x0046CBBC

  { The screen shake, from TFrm_main_AppIdle @ 0x00464F8A. A fresh random
    displacement every frame rather than an oscillation, applied once to the
    whole sprite pass. Only the final boss's ground slam sets it. }
  ScreenShakeOn: Boolean = False;           //                   0x00484EE9
  ScreenShakeTimer: Integer = 0;            //                   0x00484EEC
  { 0x0046CF88 is ONE global shared by the title menu and the pause menu -
    Title_MainMenu clamps it to 0..3 and PauseMenu_Update reuses it. That is why
    FormKeyDown stashes it before entering pause and zeroes it. }
  { 0x0046CC14. ONE sub-phase counter shared by every screen that has to
    wait for a fade: the game-over screen steps 0 -> 1 -> 2 through it, the
    opening sequence runs its whole six-beat sequence on it, and the message
    box uses it as a wait flag. EventRunner.pas already described it from the
    interpreter's side. GameState_Reset zeroes it. }
  ScreenPhase: Integer = 0;                 //                   0x0046CC14
  { 0x0046CEF8. Which of NEW GAME / CONTINUE the title menu chose, and reset
    to 0 by the game-over screen on its way back to the title. }
  TitleSubMode: Integer = 0;                // p_TitleSubMode    cell 0x0046CEF8
  { ONE variable, shared by the title menu, the options screen and the pause
    menu - so moving the cursor in one moves it in the others. }
  MenuIndex: Integer = 0;                   // p_MenuIndex       cell 0x0046CF88
  SavedMenuIndex: Integer = 0;              // p_SavedMenuIndex  cell 0x0046D2C0
  Input: TInputState;                       // p_InputState      cell 0x0046CC58
  { p_KeyMap 0x0046CEA8. DDDD1Init copies Settings.KeyMap into this on the way
    in and FormDestroy copies it back on the way out, so the two are the same
    four numbers held twice - which is why changing a key in the options
    screen edits THIS and the file only picks it up at exit. }
  KeyMap: array[0..3] of Integer;

{ 0x00466E4C. "Confirm" is EITHER of the first two buttons, and it is an
  EDGE, not a level:

      (Button[0] and not ButtonLatch[0]) or (Button[1] and not ButtonLatch[1])

  Both halves matter and the reconstruction had neither. TGameWorld's
  ConfirmPressed returned Button[0] alone, as a level - so event opcode 3, the
  press-confirm trigger, would have fired on every frame the key was held and
  would have ignored the attack button entirely. }
function ConfirmPressed(const Inp: TInputState): Boolean;

{ Convenience for the pause path, which the original open-codes. }
{ The tail of TFrm_main_AppIdle @ 0x00464D30, which is where the input record's
  DERIVED fields are maintained. It runs AFTER the state handlers, so the latch
  a handler reads holds the PREVIOUS frame's button state - which is what makes
  "Button and not ButtonLatch" a rising edge.

  It also ages the double-tap window. Player_Update opens that window; this
  closes it, and clears the remembered direction when it expires. Splitting it
  this way is the original's, not a convenience: the controller and the poller
  each own half of the record. }
procedure InputEndOfFrame(var Inp: TInputState; const Down: array of Boolean);

procedure EnterPause;
procedure LeavePause;

{ data\system.dat, from DDDD1Init (which reads it over a set of defaults) and
  FormDestroy @ 0x00466644 (which writes it back on exit).

  The file is a raw 56-byte image of TGameSettings, so the record must stay
  exactly that size - asserted at startup, the same guard TPlayerState uses.

  SaveSettings gathers the loose globals back into the record first, in the
  original's order, because those are what the options screen actually edits. }
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

{ The order is the original's, from FormKeyDown @ 0x004665C8: the menu index is
  saved and cleared BEFORE the game state is saved. }
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

{ Input_ConfirmPressed @ 0x00466E4C. The whole body is one disjunction:

      (in[0x1c] = 1 and in[0x20] = 0) or (in[0x1d] = 1 and in[0x21] = 0)

  Button sits at +0x1C and ButtonLatch at +0x20, so those four bytes are
  Button[0]/Latch[0] and Button[1]/Latch[1]. It is an EDGE, on EITHER of two
  buttons - both halves were once wrong at the same time, a level instead of an
  edge and only one button.

  IT WRITES NOTHING. No latch is consumed, which is what lets GameOver_Update
  take the answer as an eagerly-evaluated argument without differing from the
  original, which calls this lazily as the second half of a C or-else. }
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
    { The original reads 0x38 unconditionally. Refuse a short file rather than
      leaving the tail of the record holding whatever was there before - the
      same guard LoadSave makes for save.dat. }
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
    { The original opens for write, falls back to create, and ignores failure
      either way - a read-only game directory must not stop it shutting down. }
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
  { data\system.dat is a raw image of this record, so a layout slip makes
    every setting after the slip garbage.

    NOT Assert - FPC compiles those out without -Sa, which this project does
    not pass, so the Assert that stood here had never run. See Entities.pas. }
  if SizeOf(TGameSettings) <> $38 then
    raise Exception.CreateFmt('TGameSettings is %d bytes; data/system.dat is '
      + 'a raw image of it and must be 56', [SizeOf(TGameSettings)]);

end.
