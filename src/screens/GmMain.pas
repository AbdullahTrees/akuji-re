{ Main form and frame loop. Published component field names must match
  GmMain.lfm because resource streaming binds them by name. }

unit GmMain;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, LCLType,
  DDDDComponent, DDIDComponent, DDSDComponent, KbgmPlayer, GameState,
  IniFiles, QdaArchive, Title, Ending, Opening, GameFont, Surfaces, Sprites, Stages, TileMaps, PlayerState,
  Entities, GameSession, SpritePool, Dialogue;

type
  { Forward, so the host below can hold one. }
  TFrm_main = class;

  { Form-level adapters connect session services to streamed components. }
  TFormAudio = class(TSessionAudio)
  private
    FForm: TFrm_main;
  public
    constructor Create(AForm: TFrm_main);
    procedure PlayEffect(Id: Integer); override;
    procedure PlayMusic(Track: Integer; Loop: Boolean); override;
    procedure StopMusic; override;
  end;

  TFormStartHost = class(TStartHost)
  private
    FForm: TFrm_main;
  public
    constructor Create(AForm: TFrm_main);
    function Opening: Boolean; override;
    { Starts either the new-game track or the track stored in a save. }
    procedure PlayMusic(Track: Integer; Loop: Boolean;
                        FadeSeconds: Integer); override;
  end;

  TFrm_main = class(TForm)
    DDDD1: TDDDD;
    Joy: TDDIDEX;
    KbgmPlayer1: TKbgmPlayer;
    DDSD1: TDDSD;
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DDDD1Init(Sender: TObject);
    procedure TitleSound(Index: Integer);
  private
    FLastFrame: DWord;
    FShakeOffset: Integer; // this frame's Random(0x10) - 8
    FArchive: TQdaArchive;
    FTitle: TBitmap;
    FTitleScreen: TTitleScreen;
    FFont: TGameFont;
    FSurfaces: TSurfaceSet;
    FSprites: TSpriteSet;
    FStages: TStageTable;
    FMap: TTileMap;
    FStageLoaded: Integer;
    FStartHost: TStartHost;
    { Session event host; closing the message box advances the script. }
    FDialogue: TDialogueBox;
    { bmp\power.bmp, the panel's backdrop. Loaded once - PowerUp_Show builds
      the surface every time and frees it when the panel closes, which is a
      lifetime detail, not a behaviour. }
    FPowerBmp: TBitmap;
    FGameOver: TGameOverScreen;
    FPause: TPauseMenu;
    FOpening: TOpeningScreen;
    FTitleSlept: Boolean;
    FEnding: TEndingScreen;
    { Once-per-second debug frame-rate sample. }
    FDebugStamp: DWord;
    FDebugFrames: Integer;
    FDebugFps: Integer;
    FUseArchive: Boolean;
    FEndingBmp: TBitmap;
    FOpeningBmp: TBitmap;     { bmp\op%.3d.bmp, one slide at a time }
    FConfirmLatch: Boolean;
    { Owns the active player, entity pool, camera, and event state. }
    FSession: TGameSession;
    FDataDir: string;
    FMoveY: Integer;
    FMoveX: Integer;
    FConfirm: Boolean;
    { HUD life-icon animation, the three ints at PTR_DAT_0046D320. }
    FLifeAnimX: Integer;
    FLifeAnimIndex: Integer;
    FLifeAnimTimer: Integer;
    function FindGameData: string;
    procedure LoadStage(StageIndex: Integer);
    procedure DrawHud;
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure PollInput;
    procedure InputStep7;
    { The state dispatch is in two halves with the entity update between
      them - see the note in AppIdle. }
    procedure DispatchPre;
    procedure DispatchPost;
    procedure FormPaint(Sender: TObject);
    procedure DrawScene;
    procedure DrawDebugOverlay;
    procedure SetFullScreen(Enable: Boolean);
    procedure DrawGameOver;
    { The opening cutscene. Game_StartOrLoad calls Opening_Update every frame
      while the state is 40, and does nothing else until it finishes - which is
      why TStartHost.Opening gates the whole of GameStartOrLoad. }
    function OpeningStep: Boolean;
    procedure OpeningPicture(Id: Integer);
    procedure PlayMusicTrack(Track: Integer; Loop: Boolean;
                             FadeSeconds: Integer);
    { Starts a track immediately for cutscenes and power-up panels. }
    procedure PlayMusicCut(Track: Integer; Loop: Boolean);
    { Stops with a two-second fade before playing the next track. }
    procedure PlayMusicFading(Track: Integer; Loop: Boolean);
    { Save and restore the current music track. }
    procedure RememberMusicTrack;
    procedure ResumeMusicTrack;
    { Dialogue fade adapter for the display component. }
    procedure DialogueStartFade(FadeOut: Boolean);
    function DialogueFadeBusy: Boolean;
    function DialogueMusicBusy: Boolean;
    { Sub-op 80's last phase, which is all form-level work. }
    procedure DialogueSoulGetDone;
    procedure StopMusicTrack;
    procedure OpeningFade(FadeIn: Boolean);
    procedure EndingPicture(Index: Integer);
    procedure EndingPictureNamed(const Name: string);
    procedure DrawEndingCredits;
    procedure DrawEndingStill;
    procedure DrawEndingResults;
    function EndingConfirm: Boolean;
    procedure EndingFade(Step: Integer; FadeOut: Boolean);
    function EndingMusicPlaying: Boolean;
    function EndingFadeBusy: Boolean;
    procedure EndingStopMusicFade(FadeSeconds: Integer);
    procedure DrawEndingSlide;
    procedure EndingMusic(Track: Integer; Loop: Boolean);
    procedure SessionResetHost;
    procedure StageBeginFade;
    procedure TitleVolume;
    procedure TitleResetState;
    procedure TitleResetOpening;
    procedure TitleGallery(Slot: Integer);
    procedure TitleInit;
    procedure GameOverRestart;
    procedure GameOverFade(FadeIn: Boolean);
    procedure GameOverMusic(Track: Integer);
    function  GameOverMusicPlaying: Boolean;
    function  EntityWorldFading: Boolean;
  end;

var
  Frm_main: TFrm_main;

implementation

{$R *.lfm}

{ Finds game data beside the executable or in the packaged data directory. }
function TFrm_main.FindGameData: string;
const
  Candidates: array[0..2] of string = (
    '',
    '..' + PathDelim + 'English Translated Version 1.1 (D)' + PathDelim,
    '..' + PathDelim + '..' + PathDelim + 'English Translated Version 1.1 (D)' + PathDelim);
var
  BaseDirectory, CandidatePath: string;
  CandidateIndex: Integer;
begin
  BaseDirectory := ExtractFilePath(ParamStr(0));
  for CandidateIndex := Low(Candidates) to High(Candidates) do
  begin
    CandidatePath := BaseDirectory + Candidates[CandidateIndex];
    if FileExists(CandidatePath + 'bmp.qda') then
      Exit(CandidatePath);
  end;
  Result := '';
end;

{ Loads settings, assets, audio, screens, and frame-loop state.

  Two things worth knowing about the settings record:

    * +0x1A, fullscreen, DEFAULTS TO 1. It stands only when system.ini is
      missing - the INI read sets it unconditionally either way.
    * +0x28, the gallery selection, is zeroed AFTER the file is read, so it
      does not persist across a run even though it sits inside the 56 bytes
      written back.

  The title's one-time startup delay is armed after initialization. }
procedure TFrm_main.DDDD1Init(Sender: TObject);
var
  DataDir: string;
  Sheet: TBitmap;
  Ini: TIniFile;
  I: Integer;
begin
  DataDir := FindGameData;
  if DataDir <> '' then
  begin
    FDataDir := DataDir;

    { Missing or short settings data leaves the initialized defaults intact. }
    LoadSettings(DataDir);

    { system.ini overrides fullscreen and input-device settings. Compatibility
      requires two parsing details:

        * the fullscreen comparison is case-sensitive,
          so 'ON', 'On' and ' on ' all mean WINDOWED.
        * input uses StrToInt and raises for missing or malformed values.

      The shipped file parses the same either way. }
    { Use the resolved data directory consistently for packaged builds. }
    Ini := TIniFile.Create(DataDir + 'system.ini');
    try
      Settings.FullScreenFlag :=
        Ord(Ini.ReadString('disp', 'fullscreen', '') = 'on');
      Settings.InputDevice :=
        StrToInt(Ini.ReadString('device', 'input', ''));
    finally
      Ini.Free;
    end;
    { Zeroed after the read, so the gallery cursor never persists. }
    Settings.GallerySel := 0;
    SettingsToGlobals;

    { p_KeyMap gets its own copy of the four ints; FormDestroy copies them
      back on the way out. }
    for I := 0 to High(Settings.KeyMap) do
      KeyMap[I] := Settings.KeyMap[I];

    FArchive := TQdaArchive.Create(DataDir + 'bmp.qda');
    { p_UseArchive, set by DDDD1Init the same way. }
    FUseArchive := True;

    { Load title surfaces, sprites, and font assets. }
    FSurfaces := TSurfaceSet.Create(FArchive);
    FSurfaces.LoadSet(DataDir, 0);
    FSprites := TSpriteSet.Create;
    FSprites.LoadSet(DataDir, 0);

    { Load the stage table once; stage assets are selected from it later. }
    FStages := TStageTable.Create;
    FStages.Load(DataDir);
    FMap := TTileMap.Create;
    FStageLoaded := -1;

    { The running game. It borrows the stage table and the map; the form keeps
      owning both, and the surfaces and sprite sheets with them. }
    FSession := TGameSession.Create(DataDir, FStages, FMap);
    { Replace the no-op audio the session builds for itself. }
    FSession.Audio.Free;
    FSession.Audio := TFormAudio.Create(Self);
    { Game_StartOrLoad's presentation hooks. The concrete host connects the
      opening sequence and playlist operations to the form-owned components. }
    FStartHost := TFormStartHost.Create(Self);
    FDialogue := TDialogueBox.Create;
    FPowerBmp := FArchive.LoadBitmapByName('power.bmp');
    FSession.EventHost := FDialogue;

    Sheet := FSurfaces[0];
    if Sheet <> nil then
      FFont := TGameFont.Create(Sheet);

    FTitle := FSurfaces[1];   { menu background - owned by FSurfaces }

    { Effects are loaded up front. Audio initialization failures remain
      non-fatal so the game can run without a sound device. }
    DDSD1.Open(DataDir);
    DDSD1.Volume := Settings.Volume;
    KbgmPlayer1.Open(DataDir);
  end;

  { Present() blits straight to the form canvas for speed, which is fine while
    the frame loop is running but leaves stale pixels wherever Windows repaints
    the window itself (resize, occlusion, restore). Handling OnPaint from the
    same offscreen surface covers those. Without this a partial repaint shows
    as a lighter rectangle in whatever region Windows invalidated. }
  OnPaint := FormPaint;
  DoubleBuffered := True;

  { Apply the fullscreen setting after display initialization. }
  SetFullScreen(FullScreenOn);

  FTitleScreen := TTitleScreen.Create;
  FGameOver := TGameOverScreen.Create;
  FPause := TPauseMenu.Create;
  FOpening := TOpeningScreen.Create;
  SetPauseSound(TitleSound);
  FEnding := TEndingScreen.Create;
  FEnding.OnPicture := EndingPicture;
  FEnding.OnMusic := EndingMusic;
  FEnding.OnStopMusic := EndingStopMusicFade;
  FEnding.OnPictureNamed := EndingPictureNamed;
  FEnding.OnSound := TitleSound;
  FEnding.OnConfirm := EndingConfirm;
  FEnding.OnFade := EndingFade;
  FEnding.OnMusicPlaying := EndingMusicPlaying;
  FEnding.OnFadeBusy := EndingFadeBusy;
  { PowerUp_Show's fanfare. The panel closes when this track ends, so without
    it the overlay was waiting on the looping stage music - see Dialogue.pas. }
  FDialogue.OnSound := TitleSound;
  FDialogue.OnMusic := PlayMusicCut;
  FDialogue.OnRememberMusic := RememberMusicTrack;
  FDialogue.OnResumeMusic := ResumeMusicTrack;
  FDialogue.OnStartFade := DialogueStartFade;
  FDialogue.OnFadeBusy := DialogueFadeBusy;
  { Sub-op 12 goes through the FADE wrapper; the power-up fanfare cuts. }
  FDialogue.OnFadeMusic := PlayMusicFading;
  FDialogue.OnMusicBusy := DialogueMusicBusy;
  FDialogue.OnSoulGetDone := DialogueSoulGetDone;
  FOpening.OnPicture := OpeningPicture;
  FOpening.OnMusic := PlayMusicCut;
  FOpening.OnStopMusic := StopMusicTrack;
  FOpening.OnFade := OpeningFade;
  FGameOver.OnRestart := GameOverRestart;
  FGameOver.OnFade := GameOverFade;
  FGameOver.OnMusic := GameOverMusic;
  FGameOver.OnMusicPlaying := GameOverMusicPlaying;
  { Player_Update's soft-landing guard reads the fader. Wired here rather
    than copied into the world each frame - see TEntityWorld.Fading. }
  FSession.World.OnFading := EntityWorldFading;
  { Keep Title.pas independent of the component layer through callbacks. }
  FTitleScreen.OnSound := TitleSound;
  FTitleScreen.OnResetState := TitleResetState;
  FTitleScreen.OnResetOpening := TitleResetOpening;
  FTitleScreen.OnGallery := TitleGallery;
  FTitleScreen.OnVolume := TitleVolume;
  FSession.OnStartFade := StageBeginFade;
  FSession.OnResetHost := SessionResetHost;
  { Raise the multimedia timer period before the first frame: without it
    the Sleep(1) below takes about 15.6 ms and caps the rate anyway. }
  BeginFrameClock;
  FLastFrame := FrameClockMs;

  { Initialize global frame-loop state. }
  Randomize;
  FillChar(FSession.Input, SizeOf(FSession.Input), 0);
  EntitiesLive := 0;
  EntitiesDrawn := 0;
  GameStateValue := GS_TITLE_INIT;
  SavedGameState := 0;
  { Arm TitleInit's one-time delay. }
  FTitleSlept := False;

  Application.OnIdle := AppIdle;
end;

{ DIVERGENCE DIV-001: frame pacing yields between updates instead of spinning. }
{ Runs one frame when the frame clock reaches the target interval. Returning
  Done=True before then lets the application sleep between frames. }
procedure TFrm_main.AppIdle(Sender: TObject; var Done: Boolean);
var
  Now_, Elapsed: DWord;
begin
  { DWord subtraction intentionally handles the multimedia clock's wraparound. }
  Now_ := FrameClockMs;
  Elapsed := Now_ - FLastFrame;

  { SoftwareVsync is shared with the options screen and loaded from settings. }
  if SoftwareVsync and (Elapsed < FRAME_MS) then
  begin
    Sleep(1);        { yield instead of spinning }
    Done := False;   { but come straight back }
    Exit;
  end;
  FLastFrame := Now_;

  PollInput;              { step 2-3 }
  DDDD1.Clear;
  { The animated background tiles, once a frame and OUTSIDE the state
    dispatch - which is where AppIdle ticks them, so a wall keeps moving
    behind a dialogue box or a pause. }
  FSession.TickBackground;

  { State handling is split around entity updates so transitions made by the
    pre-dispatch are visible to the post-dispatch in the same frame. }
  FSession.BeginFrame;
  DispatchPre;
  { Event delays tick after script setup and before entity updates. }
  FSession.Runner.TickDelay(FSession.Events, FSession.Player, GameStateValue);
  { Player_Update's SOFT landing sound is suppressed while the screen fades.
    That matters at every door: the transition fades, the player is placed
    standing on the floor as it ends with PF_LANDED clear, and its first update
    would otherwise run the whole just-landed sequence. The hard landing sounds
    either way. }
  FSession.TickEntities(GameStateValue);

  { After Entity_UpdateAll, before anything is drawn. The offset is subtracted
    from every sprite here and ADDED to the tilemap's scroll Y further down, so
    map and sprites shift together. }
  FShakeOffset := 0;
  if ScreenShakeOn then
  begin
    Dec(ScreenShakeTimer);
    FShakeOffset := DelphiRandom(SHAKE_RANGE) - SHAKE_CENTRE;
    if ScreenShakeTimer < 1 then
      ScreenShakeOn := False;
    FSession.Sprites.ShiftY(-FShakeOffset);
  end;
  DispatchPost;
  { Fades pause with the game instead of completing behind the pause menu. }
  if GameStateValue <> GS_PAUSE then
    DDDD1.TickFade;

  { The cancel button enters pause except while paused or editing options. }
  if (GameStateValue <> GS_PAUSE)
     and not ((GameStateValue = GS_TITLE_MENU) and (TitleSubMode = TSM_OPTIONS))
     and FSession.Input.Button[PAUSE_CANCEL_BUTTON]
     and not FSession.Input.ButtonLatch[PAUSE_CANCEL_BUTTON] then
    EnterPause;

  { Clear one-frame keyboard fallback input after every state has consumed it. }
  FMoveY := 0;
  FMoveX := 0;
  FConfirm := False;

  { Update latches after dispatch so handlers see the previous frame's state. }
  InputStep7;
  DrawDebugOverlay;
  DDDD1.Present;

  Done := False;          { keep the loop running }
end;

{ Polls the configured controls. Opposing directions cancel to zero. }
{ POLLING ONLY. Everything else about the input belongs to the END of the
  frame, in InputEndOfFrame.

  Moving has to hold the PREVIOUS frame's value while the handlers run,
  because Player_Update's dash tests `Moving = 0 and AxisX <> 0` - set
  Moving from this frame's axes here and those two are contradictory, so
  the dash can never fire at all. The test is an EDGE: a direction is
  pressed now and was not last frame. }
procedure TFrm_main.PollInput;
begin
  Joy.Update;

  FSession.Input.AxisX := Ord(Joy.IsDown(abRight)) - Ord(Joy.IsDown(abLeft));
  FSession.Input.AxisY := Ord(Joy.IsDown(abDown)) - Ord(Joy.IsDown(abUp));

  { The confirm edge the message box needs, taken before Button[0] is
    overwritten below. }
  FConfirmLatch := FSession.Input.Button[0];

  FSession.Input.Button[0] := Joy.IsDown(abAction1);
  FSession.Input.Button[1] := Joy.IsDown(abAction2);
  FSession.Input.Button[2] := Joy.IsDown(abAction3);
  FSession.Input.Button[3] := Joy.IsDown(abAux1);

  { AnyPressed includes the first three action buttons. }
  FSession.Input.AnyPressed :=
       (FSession.Input.Button[0] and not FSession.Input.ButtonLatch[0])
    or (FSession.Input.Button[1] and not FSession.Input.ButtonLatch[1])
    or (FSession.Input.Button[2] and not FSession.Input.ButtonLatch[2]);
end;

{ Step 7: edge detection, the repeat timers and the double-tap window. AFTER
  the state handlers, so what they read is the previous frame's. }
procedure TFrm_main.InputStep7;
var
  Down: array[0..3] of Boolean;
begin
  Down[0] := Joy.IsDown(abAction1);
  Down[1] := Joy.IsDown(abAction2);
  Down[2] := Joy.IsDown(abAction3);
  Down[3] := Joy.IsDown(abAux1);
  InputEndOfFrame(FSession.Input, Down);
end;

{ Draws the map, sprites, HUD, dialogue, and top sprite layer in order. }
procedure TFrm_main.DrawScene;
begin
  { Draw with the layer's tileset slot, not the stage's surface-set id. }
  if (FMap <> nil) and (FStages <> nil) then
    FMap.Draw(DDDD1.Canvas, FSurfaces,
              FStages.Tileset[Settings.CurrentStage, 0],
              PixelOf(FSession.Layer.OriginX),
              PixelOf(FSession.Layer.OriginY) + FShakeOffset,
              SCREEN_W, SCREEN_H);
  { The panel covers everything, so it replaces the scene rather than sitting
    on it - PowerUp_Show blits a full 320x240 picture before Overlay_Update
    draws its line. }
  if FDialogue.Active and (FDialogue.Mode = omPanel) then
  begin
    if FPowerBmp <> nil then
      DDDD1.Canvas.Draw(0, 0, FPowerBmp);
    FDialogue.Draw(DDDD1.Canvas, FFont, 0);
    Exit;
  end;

  FSession.Sprites.DrawAll(DDDD1.Canvas, FSurfaces);
  DrawHud;
  FDialogue.Draw(DDDD1.Canvas, FFont,
                 PixelOf(FSession.Pool.Field(0, EF_POS_Y)));
  { Bucket 8 is reserved for sprites drawn above the HUD and dialogue. }
  FSession.Sprites.DrawTop(DDDD1.Canvas, FSurfaces);
end;

{ Loads the surface set, sprite set, and primary map named by a stage record.
  Repeated requests for the active stage are ignored. }
procedure TFrm_main.LoadStage(StageIndex: Integer);
var
  SurfaceSetId, SpriteSetId, MapId: Integer;
begin
  if StageIndex = FStageLoaded then Exit;
  if (FStages = nil) or (StageIndex < 0) or (StageIndex >= FStages.Count) then Exit;

  SurfaceSetId := FStages.SurfaceSet[StageIndex];
  SpriteSetId  := FStages.SpriteSet[StageIndex];
  MapId        := FStages.Layer[StageIndex, 0];

  if SurfaceSetId >= 0 then
  begin
    FSurfaces.LoadSet(FDataDir, SurfaceSetId);
    { The font lives in slot 0 of whichever set is current, so it is rebuilt
      when the set changes. }
    FreeAndNil(FFont);
    if FSurfaces[0] <> nil then
      FFont := TGameFont.Create(FSurfaces[0]);
  end;
  if SpriteSetId >= 0 then
    FSprites.LoadSet(FDataDir, SpriteSetId);
  if MapId <> LAYER_NONE then
    FMap.Load(FDataDir, MapId);

  FStageLoaded := StageIndex;
end;

{ Draws entity counts and a once-per-second frame-rate sample when DebugLog is
  enabled.

  The FPS line is a once-a-second SAMPLE, not an average: the frame count is
  latched and zeroed when a second has elapsed, so what is on screen is the
  previous second's total. }
procedure TFrm_main.DrawDebugOverlay;
var
  Now: DWord;
begin
  if not DebugLog then Exit;

  Now := FrameClockMs;
  { DWord, not Int64. Widening the subtraction defeats the wrap: the clock
    rolls over every 49 days and 32-bit arithmetic carries through it,
    where a 64-bit difference goes hugely negative and the counter stops
    updating. }
  if Now - FDebugStamp > 1000 then
  begin
    FDebugFps := FDebugFrames;
    FDebugFrames := 0;
    FDebugStamp := FrameClockMs;
  end;
  Inc(FDebugFrames);

  if FFont = nil then Exit;
  FFont.TextOut(DDDD1.Canvas, 0, 0,  'FPS:' + IntToStr(FDebugFps));
  FFont.TextOut(DDDD1.Canvas, 0, 8,  'OBJ:' + IntToStr(EntitiesLive));
  FFont.TextOut(DDDD1.Canvas, 0, 16, 'S P:' + IntToStr(EntitiesDrawn));
end;

{ Applies fullscreen or restores the fixed-size centered window. Archive mode
  intentionally leaves the border style unchanged when returning to a window. }
procedure TFrm_main.SetFullScreen(Enable: Boolean);
begin
  if Enable then
  begin
    FullScreenOn := True;
    BorderStyle := bsNone;
    WindowState := wsFullScreen;
    Screen.Cursor := crNone;
  end
  else
  begin
    FullScreenOn := False;
    WindowState := wsNormal;
    ClientWidth := SCREEN_W;
    ClientHeight := SCREEN_H;
    { Archive mode keeps the current border style. }
    if not FUseArchive then
      BorderStyle := bsSingle;
    Position := poScreenCenter;
    Screen.Cursor := crDefault;
  end;
end;

{ One frame of the cutscene. True while it is still running, which is what
  holds GameStartOrLoad at the door. Ten slides, 4726 frames in the trace. }
function TFrm_main.OpeningStep: Boolean;
begin
  { FadeBusy must be the live one: the last phase arms a fade and then holds
    at Opening's 999 sentinel until it lands. A constant False here falls
    through on the same frame and cuts straight to stage 1. }
  Result := FOpening.Update(ConfirmPressed(FSession.Input),
                            KbgmPlayer1.IsPlaying, DDDD1.FadeBusy);
  FOpening.Draw(DDDD1.Canvas, FFont, FOpeningBmp);
end;

procedure TFrm_main.OpeningPicture(Id: Integer);
begin
  FreeAndNil(FOpeningBmp);
  if FArchive <> nil then
    FOpeningBmp := FArchive.LoadBitmapByName(Format(OPENING_PICTURE_FMT, [Id]));
end;

procedure TFrm_main.PlayMusicTrack(Track: Integer; Loop: Boolean;
                                   FadeSeconds: Integer);
begin
  KbgmPlayer1.Play(Track, Loop, FadeSeconds);
end;

procedure TFrm_main.PlayMusicCut(Track: Integer; Loop: Boolean);
begin
  PlayMusicTrack(Track, Loop, KBGM_STOP_HARD);
end;

procedure TFrm_main.PlayMusicFading(Track: Integer; Loop: Boolean);
begin
  PlayMusicTrack(Track, Loop, KBGM_STOP_FADE_NEWGAME);
end;

procedure TFrm_main.RememberMusicTrack;
begin
  KbgmPlayer1.RememberCurrent;
end;

procedure TFrm_main.ResumeMusicTrack;
begin
  KbgmPlayer1.ResumeRemembered;
end;

procedure TFrm_main.DialogueStartFade(FadeOut: Boolean);
begin
  { Restore the normal fade step because the ending results screen uses a
    different persistent value. }
  DDDD1.FadeStep := FADE_STEP;
  DDDD1.StartFade(0, FadeOut);
end;

function TFrm_main.DialogueFadeBusy: Boolean;
begin
  Result := DDDD1.FadeBusy;
end;

function TFrm_main.DialogueMusicBusy: Boolean;
begin
  Result := KbgmPlayer1.IsPlaying;
end;

procedure TFrm_main.DialogueSoulGetDone;
begin
  { GameState_Reset(form, 0), the title asset load, and the font - then the
    ending, with the opening's two counters cleared so a later new game does
    not resume mid-cutscene. }
  FSession.ResetState(0);   { first, so a title reached from a running game
                              does not inherit its pool, events or camera }
  LoadStage(0);
  GameStateValue := GS_ENDING;
  FOpening.Reset;
end;

procedure TFrm_main.StopMusicTrack;
begin
  KbgmPlayer1.Stop;
end;

procedure TFrm_main.OpeningFade(FadeIn: Boolean);
begin
  { StartFade takes the inverse FadeOut direction. }
  DDDD1.FadeStep := FADE_STEP;
  DDDD1.StartFade(0, not FadeIn);
end;

constructor TFormAudio.Create(AForm: TFrm_main);
begin
  inherited Create;
  FForm := AForm;
end;

procedure TFormAudio.PlayEffect(Id: Integer);
begin
  FForm.DDSD1.Play(Id);
end;

procedure TFormAudio.PlayMusic(Track: Integer; Loop: Boolean);
begin
  { The fade wrapper - see the note on the class. }
  FForm.PlayMusicTrack(Track, Loop, KBGM_STOP_FADE_NEWGAME);
end;

procedure TFormAudio.StopMusic;
begin
  { Stop immediately without fading. }
  FForm.StopMusicTrack;
end;

constructor TFormStartHost.Create(AForm: TFrm_main);
begin
  inherited Create;
  FForm := AForm;
end;

function TFormStartHost.Opening: Boolean;
begin
  Result := FForm.OpeningStep;
end;

procedure TFormStartHost.PlayMusic(Track: Integer; Loop: Boolean;
                                   FadeSeconds: Integer);
begin
  FForm.PlayMusicTrack(Track, Loop, FadeSeconds);
end;

{ Replaces the current numbered ending slide. A negative index clears it. }
procedure TFrm_main.EndingPicture(Index: Integer);
begin
  FreeAndNil(FEndingBmp);
  if (Index >= 0) and (FArchive <> nil) then
    FEndingBmp := FArchive.LoadBitmapByName(Format(ENDING_PICTURE_FMT, [Index]));
end;

{ Replaces the ending image with a named full-screen asset. }
procedure TFrm_main.EndingPictureNamed(const Name: string);
begin
  FreeAndNil(FEndingBmp);
  if FArchive <> nil then
    FEndingBmp := FArchive.LoadBitmapByName(Name);
end;

{ Phase 2, the staff roll: seventeen crops of one sheet, scrolling. Ending.pas
  holds where each one has got to. }
procedure TFrm_main.DrawEndingCredits;
var
  CreditIndex: Integer;
begin
  DDDD1.Canvas.Brush.Color := clBlack;
  DDDD1.Canvas.FillRect(Rect(0, 0, SCREEN_W, SCREEN_H));
  if FEndingBmp = nil then
    Exit;
  for CreditIndex := 0 to CREDITS_ENTRIES - 1 do
    if FEnding.CreditOnScreen(CreditIndex) then
      DDDD1.Canvas.CopyRect(
        Rect(FEnding.CreditX(CreditIndex), FEnding.CreditY[CreditIndex],
             FEnding.CreditX(CreditIndex)
               + CREDITS_LAYOUT[CreditIndex][CREDITS_W],
             FEnding.CreditY[CreditIndex]
               + CREDITS_LAYOUT[CreditIndex][CREDITS_H]),
        FEndingBmp.Canvas,
        Rect(CREDITS_LAYOUT[CreditIndex][CREDITS_SX],
             CREDITS_LAYOUT[CreditIndex][CREDITS_SY],
             CREDITS_LAYOUT[CreditIndex][CREDITS_SX]
               + CREDITS_LAYOUT[CreditIndex][CREDITS_W],
             CREDITS_LAYOUT[CreditIndex][CREDITS_SY]
               + CREDITS_LAYOUT[CreditIndex][CREDITS_H]));
end;

{ Phases 3 and 4: one crop of the phase-2 sheet, its right edge growing, drawn
  at the same place each time so the picture fills in. }
procedure TFrm_main.DrawEndingStill;
var
  SourceRight: Integer;
begin
  DDDD1.Canvas.Brush.Color := clBlack;
  DDDD1.Canvas.FillRect(Rect(0, 0, SCREEN_W, SCREEN_H));
  SourceRight := FEnding.StillRight;
  if (FEndingBmp = nil) or (SourceRight < 0) then
    Exit;
  DDDD1.Canvas.CopyRect(
    Rect(STILL_X, STILL_Y,
         STILL_X + (SourceRight - STILL_SRC_LEFT),
         STILL_Y + (STILL_SRC_BOTTOM - STILL_SRC_TOP)),
    FEndingBmp.Canvas,
    Rect(STILL_SRC_LEFT, STILL_SRC_TOP, SourceRight, STILL_SRC_BOTTOM));
end;

{ Phase 5: Option.bmp, then a line a second over it. }
procedure TFrm_main.DrawEndingResults;
var
  RevealedLines, GalleryIndex, SourceX: Integer;
  PlayerState: TPlayerState;
begin
  if FEndingBmp <> nil then
    DDDD1.Canvas.Draw(0, 0, FEndingBmp)
  else
  begin
    DDDD1.Canvas.Brush.Color := clBlack;
    DDDD1.Canvas.FillRect(Rect(0, 0, SCREEN_W, SCREEN_H));
  end;
  if FFont = nil then
    Exit;

  PlayerState := FSession.Player;
  RevealedLines := FEnding.ResultsRevealed;

  if RevealedLines > 1 then
  begin
    FFont.TextOut(DDDD1.Canvas, RESULT_TITLE_X, RESULT_TITLE_Y,
                  RESULT_TITLE, RESULT_LABEL_VARIANT);
    FFont.TextOut(DDDD1.Canvas, RESULT_TITLE_X, RESULT_RULE_Y,
                  RESULT_RULE, RESULT_LABEL_VARIANT);
  end;
  if RevealedLines > 2 then
  begin
    FFont.TextOut(DDDD1.Canvas, RESULT_LABEL_X, RESULT_TIME_Y,
                  RESULT_TIME_LABEL, RESULT_LABEL_VARIANT);
    FFont.TextOut(DDDD1.Canvas, RESULT_VALUE_X, RESULT_TIME_Y,
                  EndingTimeText(PlayerState.ElapsedSec), RESULT_VALUE_VARIANT);
  end;
  if RevealedLines > 3 then
  begin
    FFont.TextOut(DDDD1.Canvas, RESULT_LABEL_X, RESULT_MANA_Y,
                  RESULT_MANA_LABEL, RESULT_LABEL_VARIANT);
    FFont.TextOut(DDDD1.Canvas, RESULT_VALUE_X, RESULT_MANA_Y,
                  EndingPercentText(PlayerState.Counter), RESULT_VALUE_VARIANT);
  end;
  if (RevealedLines > 4) and (FSurfaces[GALLERY_SURFACE] <> nil) then
    for GalleryIndex := 0 to GALLERY_COUNT - 1 do
    begin
      { A locked entry is the one dark cell; an unlocked one is its own. }
      if PlayerState.Progress[GALLERY_FIRST_FLAG + GalleryIndex] = 0 then
        SourceX := GALLERY_DARK_X
      else
        SourceX := (GalleryIndex + GALLERY_LIT_COL0) * GALLERY_CELL;
      DDDD1.Canvas.CopyRect(
        Rect(GalleryIndex * GALLERY_STEP + GALLERY_X0, GALLERY_Y,
             GalleryIndex * GALLERY_STEP + GALLERY_X0 + GALLERY_CELL,
             GALLERY_Y + (GALLERY_SRC_BOTTOM - GALLERY_SRC_TOP)),
        FSurfaces[GALLERY_SURFACE].Canvas,
        Rect(SourceX, GALLERY_SRC_TOP, SourceX + GALLERY_CELL,
             GALLERY_SRC_BOTTOM));
    end;
  if RevealedLines > 5 then
    { The rank flickers - its variant is the frame timer mod 3. }
    FFont.TextOut(DDDD1.Canvas, RANK_X, RANK_Y,
                  FEnding.RankName(PlayerState.Counter, PlayerState.ElapsedSec),
                  FEnding.Timer mod RANK_VARIANTS);
end;

function TFrm_main.EndingConfirm: Boolean;
begin
  Result := ConfirmPressed(FSession.Input);
end;

procedure TFrm_main.EndingFade(Step: Integer; FadeOut: Boolean);
begin
  DDDD1.FadeStep := Step;
  DDDD1.StartFade(0, FadeOut);
end;

function TFrm_main.EndingMusicPlaying: Boolean;
begin
  Result := KbgmPlayer1.IsPlaying;
end;

function TFrm_main.EndingFadeBusy: Boolean;
begin
  Result := DDDD1.FadeBusy;
end;



{ Phase 1, the slide show: the picture at (0x28, 8) and two rows of outlined
  text under it. Ending.pas holds which slide and which words; where they go
  is the host's. }
procedure TFrm_main.DrawEndingSlide;
begin
  DDDD1.Canvas.Brush.Color := clBlack;
  DDDD1.Canvas.FillRect(Rect(0, 0, SCREEN_W, SCREEN_H));
  if (FEndingBmp <> nil) and (FEnding.SlideImage >= 0) then
    DDDD1.Canvas.StretchDraw(
      Rect(ENDING_PIC_X, ENDING_PIC_Y,
           ENDING_PIC_X + ENDING_PIC_W, ENDING_PIC_Y + ENDING_PIC_H),
      FEndingBmp);
  Game_DrawTextOutlined(ENDING_LINE_X, ENDING_LINE1_Y, FEnding.SlideLine(0),
                        ENDING_TEXT_OUTLINE, ENDING_TEXT_FILL, 10,
                        DDDD1.Canvas);
  Game_DrawTextOutlined(ENDING_LINE_X, ENDING_LINE2_Y, FEnding.SlideLine(1),
                        ENDING_TEXT_OUTLINE, ENDING_TEXT_FILL, 10,
                        DDDD1.Canvas);
end;

procedure TFrm_main.EndingMusic(Track: Integer; Loop: Boolean);
begin
  KbgmPlayer1.Play(Track, Loop);
end;

procedure TFrm_main.EndingStopMusicFade(FadeSeconds: Integer);
begin
  KbgmPlayer1.StopOrFade(FadeSeconds);
end;

{ Resets title state and assets; the menu renderer draws the background. }
procedure TFrm_main.TitleInit;
begin
  FSession.ResetState(0);
  { Load_Stage_Assets(Self, nil) - stage 0, which is also what rebuilds the
    font sheet in surface slot 0. }
  FStageLoaded := -1;
  LoadStage(0);

  { Track 0 initializes the MIDI device and runs once. }
  KbgmPlayer1.Play(0, False);

  { ScreenPhase is shared with the game-over screen, the opening and the
    message box, so a title reached from any of them starts mid-phase. }
  ScreenPhase := 0;
  TitleSubMode := 0;
  GameStateValue := GS_TITLE_MENU;

  { Allow the audio device to settle once after startup. }
  if not FTitleSlept then
  begin
    FTitleSlept := True;
    Sleep(TITLE_INIT_SLEEP_MS);
  end;

  { The volume sweep over all 57 effect buffers, which is the last thing it
    does and the reason it comes after the sleep. }
  DDSD1.Volume := Settings.Volume;
end;

{ What Title_MainMenu reaches out for on NEW GAME / CONTINUE, and for the
  gallery. Callbacks so Title.pas stays off the session and the archive. }
{ The options volume row reapplies volume to all effect buffers. }
{ Stage_Begin's first two statements: the fader's step is 4 - which FADE_STEP
  already is - and then FUN_0044DC48(fader, 0, 0), a fade IN. }
{ GameState_Reset also clears the message box and the overlay, which live
  here rather than on the session. }
procedure TFrm_main.SessionResetHost;
begin
  FDialogue.Reset;
end;

procedure TFrm_main.StageBeginFade;
begin
  DDDD1.FadeStep := FADE_STEP;
  DDDD1.StartFade(0, False);
end;

procedure TFrm_main.TitleVolume;
begin
  DDSD1.Volume := Settings.Volume;
end;

procedure TFrm_main.TitleResetState;
begin
  FSession.ResetState(0);
end;

procedure TFrm_main.TitleResetOpening;
begin
  FOpening.Reset;
end;

{ Loads the selected gallery image. }
procedure TFrm_main.TitleGallery(Slot: Integer);
begin
  FreeAndNil(FEndingBmp);
  if FArchive <> nil then
    FEndingBmp := FArchive.LoadBitmapByName(Format('omake%.2d.bmp', [Slot]));
end;

{ Form adapters used by the game-over screen. }
procedure TFrm_main.GameOverRestart;
begin
  FSession.ResetState(0);
  { Load_Stage_Assets(MainForm, nil) - stage 0, the placeholder row, which is
    what reloads surface slot 0 and forces the font rebuild below. }
  FStageLoaded := -1;
  LoadStage(0);
end;

function TFrm_main.EntityWorldFading: Boolean;
begin
  Result := DDDD1.FadeBusy;
end;

function TFrm_main.GameOverMusicPlaying: Boolean;
begin
  Result := KbgmPlayer1.IsPlaying;
end;

procedure TFrm_main.GameOverFade(FadeIn: Boolean);
begin
  DDDD1.FadeStep := FADE_STEP;
  DDDD1.StartFade(0, not FadeIn);
end;

procedure TFrm_main.GameOverMusic(Track: Integer);
begin
  KbgmPlayer1.Play(Track, False);
end;

{ Phase 2 of the game-over screen: surface slot 3, whole screen, no HUD. }
procedure TFrm_main.DrawGameOver;
begin
  if FSurfaces[GAMEOVER_SURFACE] <> nil then
    DDDD1.Canvas.Draw(0, 0, FSurfaces[GAMEOVER_SURFACE]);
end;

{ HUD counter, elapsed time, and animated life icons. }
const
  { Life-icon ping-pong animation. }
  LIFE_ANIM_X: array[0..3] of Integer = (19, 38, 57, 38);
  LIFE_ANIM_TICKS = 8;      { advances once the timer passes 8 }
  LIFE_ICON_W = $12;        { 0x86 - 0x74 }
  LIFE_ICON_H = $14;
  LIFE_ICON_X0 = $74;       { source x of the unlit icon }
  LIFE_ICON_Y = 8;          { on screen }
  LIFE_ICON_STEP = $10;

  { Counter goals selected by Player.TargetIndex. }
  COUNTER_TARGETS: array[0..11] of Integer =
    (20, 50, 70, 130, 160, 400, 999, 30, 90, 270, 999, 0);

procedure TFrm_main.DrawHud;
var
  Secs, I, Target: Integer;
  Sheet: TBitmap;
begin
  if FFont = nil then Exit;
  Sheet := FSurfaces[1];

  { Draw the counter icon followed by its '@ ' glyph and values. }
  if Sheet <> nil then
    DDDD1.DrawSprite(Sheet, 7, $12, Rect($60, 0, $74, 10));

  Target := 0;
  if (FSession.Player.TargetIndex >= 0) and
     (FSession.Player.TargetIndex <= High(COUNTER_TARGETS)) then
    Target := COUNTER_TARGETS[FSession.Player.TargetIndex];
  { The padded format aligns both values; Trim removes its outer padding before
    the '@ ' prefix is added. }
  FFont.TextOut(DDDD1.Canvas, 8, $20,
    '@ ' + Trim(Format('%3d/%-3d', [FSession.Player.Counter, Target])), 0);

  { Labels and digits use separate font variants. }
  FFont.TextOut(DDDD1.Canvas, $D0, $E0, 'TIME', 2);
  Secs := FSession.Player.ElapsedSec;
  FFont.TextOut(DDDD1.Canvas, $F8, $E0,
    Format('%.2d:%.2d:%.2d', [Secs div 3600, (Secs div 60) mod 60, Secs mod 60]), 0);

  { Life-icon animation advances only while the HUD is drawn. }
  Inc(FLifeAnimTimer);
  if FLifeAnimTimer > LIFE_ANIM_TICKS then
  begin
    FLifeAnimTimer := 0;
    FLifeAnimIndex := (FLifeAnimIndex + 1) and 3;
    FLifeAnimX := LIFE_ANIM_X[FLifeAnimIndex];
  end;

  { Normalize invalid life counts loaded from save data. }
  if FSession.Player.Lives < 0 then
    FSession.Player.Lives := 0;
  if FSession.Player.MaxLives < FSession.Player.Lives then
    FSession.Player.Lives := FSession.Player.MaxLives;

  if Sheet = nil then Exit;
  { Lit icons run 1..Lives, unlit ones Lives+1..MaxLives, both at i*0x10 + 9. }
  for I := 1 to FSession.Player.Lives do
    DDDD1.DrawSprite(Sheet, I * LIFE_ICON_STEP + 9, LIFE_ICON_Y,
      Rect(FLifeAnimX + LIFE_ICON_X0, 0,
           FLifeAnimX + LIFE_ICON_X0 + LIFE_ICON_W, LIFE_ICON_H));
  for I := FSession.Player.Lives + 1 to FSession.Player.MaxLives do
    DDDD1.DrawSprite(Sheet, I * LIFE_ICON_STEP + 9, LIFE_ICON_Y,
      Rect(LIFE_ICON_X0, 0, LIFE_ICON_X0 + LIFE_ICON_W, LIFE_ICON_H));
end;

{ Sound requests from the title screen. See notes/audio_map.md for which index
  is which. }
procedure TFrm_main.TitleSound(Index: Integer);
begin
  DDSD1.Play(Index);
end;

{ Step 5: the state machine. }
{ The arms that run BEFORE the entity update. }
procedure TFrm_main.DispatchPre;
begin
  case GameStateValue of
    GS_TITLE_INIT:
      { Initialize title state, music, and effect volume. }
      TitleInit;
    GS_STAGE_BEGIN:
      begin
        { Load form-owned assets before session terrain, events, camera, and
          player setup consume them. }
        LoadStage(Settings.CurrentStage);
        FSession.SetFrames(FSprites);
        { Configure terrain, background animation, and event scripts. }
        FSession.LoadStageAssets(Settings.CurrentStage);
        FSession.BeginStage(Settings.CurrentStage, GameStateValue);
        FDialogue.Bind(FSession.Events, FSession.Runner, @FSession.Player,
                       FSession.Pool, FSession.World);
        { Sub-op 14 modifies the primary tile map. }
        FDialogue.Map := FMap;
        { Stage_Begin hands the box drawer p_Surfaces[1] with its origin
          at (0,0) - FUN_0044DE18. }
        if FSurfaces <> nil then
          FDialogue.FrameSheet := FSurfaces[BOX_SHEET_SLOT];
        FDialogue.SaveFileName := FDataDir + 'data' + PathDelim + 'save.dat';
      end;
    GS_PLAY,
    GS_STATE_140:
      { Event spawning and script execution precede the entity update and
        continue while a message box is active. }
      FSession.TickPre(GameStateValue);
  end;
end;

{ The arms that run AFTER it. }
procedure TFrm_main.DispatchPost;
var
  Mode: TStartMode;
begin
  case GameStateValue of
    { AFTER the entity update: frame 1 of a real session runs Title_Init,
      then Entity_UpdateAll, then Title_MainMenu. Both arms in one frame,
      because Title_Init sets the state to 20 before this dispatch reads it -
      which is also why the very first frame draws the menu rather than
      showing a blank one. }
    GS_TITLE_MENU:
      begin
        { DRAW FIRST, THEN INPUT - the order inside Title_MainMenu, where
          each sub-mode arm draws and only then reads the stick.

          It matters because TitleSubMode is OVERLOADED: on NEW GAME or
          CONTINUE the menu arm stores MenuIndex into it to carry the choice
          into state 40, reusing the variable that means OPTIONS here. Update
          first and the options screen appears for one frame on the way into
          CONTINUE.

          It also makes the cursor lag by design - the highlight drawn is the
          position BEFORE this frame's input. }
        FTitleScreen.Draw(DDDD1.Canvas, FFont, FSurfaces[1], FSurfaces[2],
                          FEndingBmp);
        FTitleScreen.Update(FMoveY, FMoveX, FConfirm);
      end;
    GS_PLAYER_INIT:
      begin
        { Apply new-game or saved state, music, unlocks, and opening flow. }
        if FTitleScreen.SubMode = 1 then
          Mode := smContinue
        else
          Mode := smNewGame;
        GameStartOrLoad(FSession.Player, Settings, Mode, FStartHost, True,
                        FDataDir + 'data' + PathDelim + 'save.dat',
                        GameStateValue);
      end;
    { GS_PLAY_ALT hosts the game-over phase machine. }
    GS_PLAY_ALT:
      begin
        { Query live fade state so phase transitions wait for each dissolve. }
        if FGameOver.Update(DDDD1.FadeBusy,
                            ConfirmPressed(FSession.Input), GameStateValue) then
          DrawGameOver;
      end;
    GS_PLAY,
    GS_STATE_140:
      begin
        { While an overlay is active it drives script advancement. }
        if FDialogue.Active then
        begin
          { Dialogue is dismissed by input; the power-up panel closes when its
            fanfare ends.

            The session does NOT stop while the box is up - entities keep
            updating through a conversation. What stops is
            Entity_PlayerTouch, and that gating belongs to the handlers. }
          if FDialogue.Mode = omPanel then
            FDialogue.Update(not KbgmPlayer1.IsPlaying, FSession.Input,
                             GameStateValue)
          else
            FDialogue.Update(FSession.Input.Button[0] and not FConfirmLatch,
                             FSession.Input, GameStateValue);
        end;
        DrawScene;
      end;
    GS_PAUSE:
      begin
        { Draw the pause menu over a cleared screen, not the frozen scene. }
        FPause.Update(FSession.Input, GameStateValue);
        FPause.Draw(DDDD1.Canvas, FFont, SCREEN_W, SCREEN_H);
      end;
    GS_ENDING:
      begin
        FEnding.Update(Settings, FSession.Player, GameStateValue);
        { The ending owns the whole screen: slide show, staff roll, stills,
          and the results panel. }
        case ScreenPhase of
          1:    DrawEndingSlide;
          2:    DrawEndingCredits;
          3, 4: DrawEndingStill;
          5:    DrawEndingResults;
        end;
      end;
    GS_QUIT:
      begin
        Application.OnIdle := nil;
        Application.Terminate;
      end;
  end;
end;

procedure TFrm_main.FormPaint(Sender: TObject);
begin
  DDDD1.Present;
end;

{ Two intentional input details:
  Escape while ALREADY paused quits rather than resuming - resuming is the
  pause menu's own PAUSE_CONTINUE entry - and Ctrl+R compares Shift for
  EQUALITY with $04, so Ctrl+Shift+R deliberately does not fire, which is
  why this is `Shift = [ssCtrl]` and not `ssCtrl in Shift`. }
procedure TFrm_main.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    if GameStateValue = GS_PAUSE then
    begin
      GameStateValue := GS_QUIT;
      Exit;
    end;
    EnterPause;
  end;

  if (Key = Ord('R')) and (Shift = [ssCtrl]) then
    GameStateValue := GS_TITLE_INIT;

  { DIVERGENCE DIV-002: menus also accept virtual-key input here. }
  { Keyboard fallback for menu navigation. Remove when all input-device paths
    provide equivalent polling. }
  case Key of
    VK_UP:                 FMoveY := -1;
    VK_DOWN:               FMoveY := 1;
    VK_LEFT:               FMoveX := -1;
    VK_RIGHT:              FMoveX := 1;
    VK_RETURN, VK_SPACE,
    VK_Z:                  FConfirm := True;
  end;
  Joy.KeyDown(Key);
end;

procedure TFrm_main.FormKeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  Joy.KeyUp(Key);
end;

{ Saves runtime settings and releases form-owned resources. }
procedure TFrm_main.FormDestroy(Sender: TObject);
begin
  { Give the multimedia timer period back - raising it is process-wide. }
  EndFrameClock;
  Application.OnIdle := nil;
  if FDataDir <> '' then
    SaveSettings(FDataDir);
  FFont.Free;
  FTitleScreen.Free;
  { FDialogue is the session's EventHost, and the session does not own it. }
  FSession.Free;
  FDialogue.Free;
  FPowerBmp.Free;
  FreeAndNil(FOpeningBmp);
  FStartHost.Free;
  FMap.Free;
  FStages.Free;
  FSprites.Free;
  FSurfaces.Free;   { owns FTitle }
  FArchive.Free;
  { Stop the audio device before the component tree is torn down - the feed
    thread holds a pointer to the mixer. }
  KbgmPlayer1.Close;
  DDSD1.Close;
  { FGameOver, FPause, FOpening and FEnding are process-lifetime helpers at
    present. Freeing them changes the frozen runtime image, so that shutdown
    cleanup belongs in a separately approved fidelity batch. }
end;

end.
