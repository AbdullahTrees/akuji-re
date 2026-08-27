{ GmMain - Akuji the Demon, main form.

  Unit name, class name, instance name and the three event handlers are all
  RECOVERED, not invented:
    unit GmMain    TTypeData.UnitName in the TFrm_main class RTTI
    TFrm_main      same RTTI (86 published properties, 744-byte instance)
    Frm_main       the form resource
    FormDestroy, FormKeyDown, DDDD1Init   the form resource

  The published field names (DDDD1, Joy, KbgmPlayer1, DDSD1) MUST match
  GmMain.lfm exactly - the .lfm reader binds components to fields by name.

  AppIdle is a translation of TFrm_main_AppIdle @ 0x00464D30. See CLAUDE.md
  section 6 for the frame breakdown it follows. }

unit GmMain;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, LCLType,
  DDDDComponent, DDIDComponent, DDSDComponent, KbgmPlayer, GameState,
  QdaArchive, Title, GameFont, Surfaces, Sprites, Stages, TileMaps, PlayerState;

type
  TFrm_main = class(TForm)
    DDDD1: TDDDD;
    Joy: TDDIDEX;
    KbgmPlayer1: TKbgmPlayer;
    DDSD1: TDDSD;
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DDDD1Init(Sender: TObject);
    procedure TitleSound(Index: Integer);
  private
    FLastFrame: QWord;     // p_LastFrameTime 0x0046D1E0
    FLimitFrames: Boolean; // flag at 0x0046CE60
    FArchive: TQdaArchive;
    FTitle: TBitmap;
    FTitleScreen: TTitleScreen;
    FFont: TGameFont;
    FSurfaces: TSurfaceSet;
    FSprites: TSpriteSet;
    FStages: TStageTable;
    FMap: TTileMap;
    FStageLoaded: Integer;
    FPlayer: TPlayerState;
    FDataDir: string;
    FMoveY: Integer;
    FMoveX: Integer;
    FConfirm: Boolean;
    function FindGameData: string;
    procedure LoadStage(StageIndex: Integer);
    procedure DrawHud;
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure PollInput;
    procedure DispatchState;
    procedure FormPaint(Sender: TObject);
  end;

var
  Frm_main: TFrm_main;

implementation

{$R *.lfm}

{ ---------------------------------------------------------------------------
  DDDD1Init - TFrm_main_DDDD1Init @ 0x00465584

  The original loaded data\system.dat over a set of defaults, read system.ini,
  initialised the subsystems, then installed the idle handler. Only the last
  step is translated so far.
  --------------------------------------------------------------------------- }
{ The original ran from the game directory, so its paths were relative. The
  rebuild lives in src/, so look in the obvious places rather than assuming. }
function TFrm_main.FindGameData: string;
const
  Candidates: array[0..2] of string = (
    '',
    '..' + PathDelim + 'English Translated Version 1.1 (D)' + PathDelim,
    '..' + PathDelim + '..' + PathDelim + 'English Translated Version 1.1 (D)' + PathDelim);
var
  Base, P: string;
  I: Integer;
begin
  Base := ExtractFilePath(ParamStr(0));
  for I := Low(Candidates) to High(Candidates) do
  begin
    P := Base + Candidates[I];
    if FileExists(P + 'bmp.qda') then
      Exit(P);
  end;
  Result := '';
end;

procedure TFrm_main.DDDD1Init(Sender: TObject);
var
  DataDir: string;
  Sheet: TBitmap;
begin
  { TODO: load data\system.dat (56-byte struct, CLAUDE.md section 7) }
  { TODO: read system.ini -> input device, fullscreen }
  { TODO: init input, sprite engine }

  DataDir := FindGameData;
  if DataDir <> '' then
  begin
    FDataDir := DataDir;
    FArchive := TQdaArchive.Create(DataDir + 'bmp.qda');

    { Original: Title_Init calls Load_Stage_Assets(MainForm, 0), which pulls
      surface set 0, then registers slot 0 as font 0. }
    FSurfaces := TSurfaceSet.Create(FArchive);
    FSurfaces.LoadSet(DataDir, 0);
    FSprites := TSpriteSet.Create;
    FSprites.LoadSet(DataDir, 0);

    { Original: Load_StageTable reads data\stage.dat once at startup, and
      Load_Stage_Assets then indexes it per stage. }
    FStages := TStageTable.Create;
    FStages.Load(DataDir);
    FMap := TTileMap.Create;
    FStageLoaded := -1;

    Sheet := FSurfaces[0];
    if Sheet <> nil then
      FFont := TGameFont.Create(Sheet);

    FTitle := FSurfaces[1];   { menu background - owned by FSurfaces }

    { Audio. The original opened DirectSound in the component's own init and
      loaded all 57 effects up front; nothing streams. Volume comes from
      system.dat +0x24 and defaults to 10 until that struct is read.

      A machine with no sound device must still play, so a failure here is
      recorded and ignored rather than raised. }
    DDSD1.Open(DataDir);
    DDSD1.Volume := 10;
    KbgmPlayer1.Open(DataDir);
  end;

  { Present() blits straight to the form canvas for speed, which is fine while
    the frame loop is running but leaves stale pixels wherever Windows repaints
    the window itself (resize, occlusion, restore). Handling OnPaint from the
    same offscreen surface covers those. Without this a partial repaint shows
    as a lighter rectangle in whatever region Windows invalidated. }
  OnPaint := FormPaint;
  DoubleBuffered := True;

  FTitleScreen := TTitleScreen.Create;
  { The original calls MainForm.DDSD1.Play straight from the title function;
    routing it through a callback keeps Title.pas off the component layer. }
  FTitleScreen.OnSound := TitleSound;
  FLimitFrames := True;
  FLastFrame := GetTickCount64;
  GameStateValue := GS_TITLE_INIT;

  { The original: Application.FOnIdle := TFrm_main_AppIdle (+0xD8/+0xDC). }
  Application.OnIdle := AppIdle;
end;

{ ---------------------------------------------------------------------------
  AppIdle - TFrm_main_AppIdle @ 0x00464D30, the frame loop.

  DELIBERATE DIVERGENCE: the original set Done := False unconditionally and then
  spin-waited on timeGetTime until >15 ms had elapsed, which pegs a CPU core at
  100%. Here the frame is paced with a real sleep and Done is left True when
  there is time to spare, so the process idles properly between frames. Same
  ~60 FPS target, none of the burn.
  --------------------------------------------------------------------------- }
procedure TFrm_main.AppIdle(Sender: TObject; var Done: Boolean);
var
  Now_, Elapsed: QWord;
begin
  Now_ := GetTickCount64;
  Elapsed := Now_ - FLastFrame;

  if FLimitFrames and (Elapsed < FRAME_MS) then
  begin
    Sleep(1);        { yield instead of spinning }
    Done := False;   { but come straight back }
    Exit;
  end;
  FLastFrame := Now_;

  PollInput;              { step 2-3 }
  DDDD1.Clear;            { step 4  - TDDDD_Clear    0x00449E78 }
  DispatchState;          { step 5 }
  { TODO step 6: sprite/entity update across 8 layers }
  { TODO step 7: button edge-detection and repeat timers }
  DDDD1.Present;          { step 8  - TDDDD_Present  0x00449D00 }

  Done := False;          { keep the loop running }
end;

{ Step 2-3: the original polled Joy through one of three device paths chosen by
  Settings+0x34, then read 4 buttons through p_KeyMap. Key state currently
  arrives from FormKeyDown instead. }
procedure TFrm_main.PollInput;
begin
  Joy.Update;
end;

{ Load_Stage_Assets @ 0x00465A1C. The record's rec[0] selects the surface set,
  rec[1] the sprite set, and rec[2..4] up to three map layers with -1 meaning
  none. The original skips a reload when the set is already current; the same
  guard is kept here via FStageLoaded. }
procedure TFrm_main.LoadStage(StageIndex: Integer);
var
  SurfSet, SprSet, MapId: Integer;
begin
  if StageIndex = FStageLoaded then Exit;
  if (FStages = nil) or (StageIndex < 0) or (StageIndex >= FStages.Count) then Exit;

  SurfSet := FStages.SurfaceSet[StageIndex];
  SprSet  := FStages.SpriteSet[StageIndex];
  MapId   := FStages.Layer[StageIndex, 0];

  if SurfSet >= 0 then
  begin
    FSurfaces.LoadSet(FDataDir, SurfSet);
    { The font lives in slot 0 of whichever set is current, so it is rebuilt
      when the set changes. }
    FreeAndNil(FFont);
    if FSurfaces[0] <> nil then
      FFont := TGameFont.Create(FSurfaces[0]);
  end;
  if SprSet >= 0 then
    FSprites.LoadSet(FDataDir, SprSet);
  if MapId <> LAYER_NONE then
    FMap.Load(FDataDir, MapId);

  FStageLoaded := StageIndex;
end;

{ HUD_Draw @ 0x00461BA8: a "%3d/%-3d" counter, an h:mm:ss timer, and a row of
  life icons - filled up to Lives, empty out to MaxLives. Icon graphics are not
  wired yet, so the count is shown as text. }
procedure TFrm_main.DrawHud;
var
  Secs: Integer;
begin
  if FFont = nil then Exit;
  Secs := FPlayer.ElapsedSec;
  FFont.TextOut(DDDD1.Canvas, 0, 8,
    Format('%3d/%-3d', [FPlayer.Counter, FPlayer.Field11DC]), 0);
  FFont.TextOut(DDDD1.Canvas, $F8, $E0,
    Format('%.2d:%.2d:%.2d', [Secs div 3600, (Secs div 60) mod 60, Secs mod 60]), 0);
  FFont.TextOut(DDDD1.Canvas, 8, $18,
    Format('LIFE %d/%d', [FPlayer.Lives, FPlayer.MaxLives]), 0);
end;

{ Sound requests from the title screen. See notes/audio_map.md for which index
  is which. }
procedure TFrm_main.TitleSound(Index: Integer);
begin
  DDSD1.Play(Index);
end;

{ Step 5: the state machine. Values and handler addresses in GameState.pas. }
procedure TFrm_main.DispatchState;
begin
  case GameStateValue of
    GS_TITLE_INIT:
      { Title_Init @ 0x0046214C. Now traced end to end:

          Load_Stage_Assets(Self, 0)              surface + sprite set 0
          Font_Define(0, Surfaces[0], $20, $140, 8, 8, 9, 9, $5F)
          KbgmPlayer1.Play(p_MidiNames[0], 0)     'midi\init'
          p_GameState := $14                      -> GS_TITLE_MENU
          for i := 0 to $38 do                    all 57 effect buffers
            DDSD1[i].SetVolume(-(10 - Settings[$24]) * $1C2)

        The asset load and the font definition already happen in DDDD1Init, so
        what is added here is the music and the volume sweep. The Font_Define
        arguments match GameFont.pas exactly - 32 columns, 9x9 cells, 8 pixel
        advance, last character $5F - which is independent confirmation of
        constants that were originally read out of the font sheet itself. }
      begin
        { Track 0 is init.mid: a GM Reset and two Roland GS writes, not music.
          The original passes ECX = 0 here, believed to be the repeat flag -
          a one-shot reset would not loop. }
        KbgmPlayer1.Play(0, False);
        DDSD1.Volume := Settings.Volume;

        if Assigned(FTitle) then
          DDDD1.Canvas.Draw(0, 0, FTitle);
        { Original Title_Init falls straight through to the menu. }
        GameStateValue := GS_TITLE_MENU;
      end;
    GS_TITLE_MENU:
      begin
        FTitleScreen.Update(FMoveY, FMoveX, FConfirm);
        FMoveY := 0;
        FMoveX := 0;
        FConfirm := False;
        FTitleScreen.Draw(DDDD1.Canvas, FFont, FSurfaces[1], FSurfaces[2]);
      end;
    GS_STAGE_BEGIN:
      begin
        { Original: GameState_Reset, Load_Stage_Assets(Settings.CurrentStage),
          spawn the player, then move to GS_PLAY. }
        LoadStage(Settings.CurrentStage);
        GameStateValue := GS_PLAY;
      end;
    GS_PLAYER_INIT:
      begin
        { Game_StartOrLoad 0x00462F40. Sub-mode 0 is NEW GAME, 1 is CONTINUE.
          The original also runs the opening cutscene here on a new game and
          only proceeds once it finishes; that is not translated yet. }
        if FTitleScreen.SubMode = 1 then
        begin
          if LoadSave(FPlayer, FDataDir + 'data' + PathDelim + 'save.dat') then
            Settings.CurrentStage := FPlayer.SavedStage
          else
            InitNewGame(FPlayer, Settings.GameLevel);
        end
        else
        begin
          InitNewGame(FPlayer, Settings.GameLevel);
          Settings.CurrentStage := 1;
        end;
        GameStateValue := GS_STAGE_BEGIN;
      end;
    GS_PLAY,
    GS_PLAY_ALT,
    GS_STATE_140:
      begin
        { TODO the real update. Rendering the map proves the stage pipeline:
          stage.dat -> surface set -> map layer -> tiles on screen. }
        { Scroll position comes from the player state, as in the original. }
        FMap.Draw(DDDD1.Canvas, FSurfaces, FStages.SurfaceSet[Settings.CurrentStage],
                  FPlayer.ScrollX, FPlayer.ScrollY, SCREEN_W, SCREEN_H);
        DrawHud;
      end;
    GS_PAUSE:       ;  { TODO PauseMenu_Update      0x00461EE4 }
    GS_OPENING:     ;  { TODO Opening_Update       0x00463154 }
    GS_QUIT:
      begin
        { Original nils FOnIdle then terminates - same shape. }
        Application.OnIdle := nil;
        Application.Terminate;
      end;
  end;
end;

procedure TFrm_main.FormPaint(Sender: TObject);
begin
  DDDD1.Present;
end;

{ FormKeyDown @ 0x004665C8. The original's first test is VK_ESCAPE. }
procedure TFrm_main.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    if GameStateValue = GS_PAUSE then
      LeavePause
    else
      EnterPause;
    Exit;
  end;
  case Key of
    VK_UP:                 FMoveY := -1;
    VK_DOWN:               FMoveY := 1;
    VK_LEFT:               FMoveX := -1;
    VK_RIGHT:              FMoveX := 1;
    VK_RETURN, VK_SPACE,
    VK_Z:                  FConfirm := True;   { Z is the original's confirm }
  end;
  Joy.KeyDown(Key);
end;

{ FormDestroy @ 0x00466644 }
procedure TFrm_main.FormDestroy(Sender: TObject);
begin
  Application.OnIdle := nil;
  FFont.Free;
  FTitleScreen.Free;
  FMap.Free;
  FStages.Free;
  FSprites.Free;
  FSurfaces.Free;   { owns FTitle }
  FArchive.Free;
  { Stop the audio device before the component tree is torn down - the feed
    thread holds a pointer to the mixer. }
  KbgmPlayer1.Close;
  DDSD1.Close;
  { TODO: teardown - the original released the sprite engine and surfaces }
end;

end.
