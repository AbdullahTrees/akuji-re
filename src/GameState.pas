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
  GS_STAGE_INIT  = 10;    // Stage_Init            0x0046214C
  GS_STATE_20    = 20;    // FUN_00462330          unidentified
  GS_STAGE_BEGIN = 30;    // Stage_Begin           0x00462210 -> sets GS_PLAY
  GS_PLAYER_INIT = 40;    // Game_Init_PlayerState 0x00462F40
  GS_PLAY        = 60;    // FUN_00454790 + HUD_Draw
  GS_PLAY_ALT    = 100;   // FUN_00461A44 + HUD_Draw
  GS_PAUSE       = 130;   // PauseMenu_Update      0x00461EE4
  GS_STATE_140   = 140;   // FUN_00454790, FUN_00455210, HUD_Draw
  GS_STATE_150   = 150;   // FUN_00463624          unidentified
  GS_QUIT        = 999;   // clears OnIdle, terminates

  { PauseMenu_Update selection, p_PauseMenuIndex @ 0x0046CF88 }
  PAUSE_CONTINUE = 0;     // restores p_SavedGameState
  PAUSE_RESTART  = 1;     // -> GS_STAGE_INIT
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

var
  { Globals matching the original's. Names follow the p_* labels now in Ghidra. }
  GameStateValue: Integer = GS_STAGE_INIT;  // p_GameState       0x0046D06C
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
