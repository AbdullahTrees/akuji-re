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
  GS_OPENING     = 150;   // Opening_Update        0x00463154  intro cutscene
  GS_QUIT        = 999;   // clears OnIdle, terminates

  { PauseMenu_Update selection, p_PauseMenuIndex @ 0x0046CF88 }
  PAUSE_CONTINUE = 0;     // restores p_SavedGameState
  PAUSE_RESTART  = 1;     // -> GS_TITLE_INIT
  PAUSE_QUIT     = 2;     // -> GS_QUIT

  SCREEN_W = 320;
  SCREEN_H = 240;

  { The original spin-waited on timeGetTime until >15 ms had passed. Same
    target rate, but the rebuild must sleep rather than burn a core. }
  FRAME_MS = 16;

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
    Field00: Integer;        // +0x00  unknown
    GameLevel: Integer;      // +0x04  0..2
    KeyMap: array[0..2] of Integer;  // +0x08..+0x10  jump, fire, pause
    Field14: Integer;        // +0x14  (third key slot end / unknown)
    Flags: array[0..3] of Byte;      // +0x18..+0x1B, +0x1A = fullscreen
    Unknown1C: array[0..7] of Byte;  // +0x1C..+0x23
    Volume: Integer;         // +0x24  0..10, SE VOLUME
    GallerySel: Integer;     // +0x28  0..6
    Unknown2C: array[0..6] of Byte;  // +0x2C..+0x32  gallery unlock flags
    Pad33: Byte;
    InputDevice: Integer;    // +0x34  from system.ini [device] input
  end;

var
  { Globals matching the original's. Names follow the p_* labels now in Ghidra. }
  Settings: TGameSettings;                  // p_Settings        0x0046D0E8
  FullScreenOn: Boolean = False;            // p_FullScreenOn    0x0046D268
  WaitOn: Boolean = False;                  // p_WaitOn          0x0046D2E4
  SoftwareVsync: Boolean = True;            // p_SoftwareVsync   0x0046CE60
  GameStateValue: Integer = GS_TITLE_INIT;  // p_GameState       0x0046D06C
  SavedGameState: Integer = 0;              // p_SavedGameState  0x0046CBBC
  PauseMenuIndex: Integer = 0;              // p_PauseMenuIndex  0x0046CF88
  Input: TInputState;                       // p_InputState      0x0046CC58

{ Convenience for the pause path, which the original open-codes. }
procedure EnterPause;
procedure LeavePause;

implementation

procedure EnterPause;
begin
  SavedGameState := GameStateValue;
  GameStateValue := GS_PAUSE;
end;

procedure LeavePause;
begin
  GameStateValue := SavedGameState;
end;

end.
