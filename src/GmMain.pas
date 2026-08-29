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
  IniFiles, QdaArchive, Title, Ending, Opening, GameFont, Surfaces, Sprites, Stages, TileMaps, PlayerState,
  Entities, GameSession, SpritePool, Dialogue;

type
  { Forward, so the host below can hold one. }
  TFrm_main = class;

  { WHY THIS EXISTS. GameStartOrLoad asks its host `Opening` and returns
    immediately while that is True - the cutscene gates the whole of starting a
    game, exactly as Game_StartOrLoad does in the original, where Opening_Update
    is called every frame the state is 40 and nothing else happens until it is
    over.

    GmMain was passing a bare TStartHost, whose Opening returns False
    unconditionally. So the gate never closed, the cutscene never ran, and the
    story section simply did not appear. Opening.pas was correct the whole time
    - the trace confirms its slide timings frame for frame - and had nothing
    calling it. }
  { THE SAME OMISSION A THIRD TIME. TSessionAudio's two methods are no-op
    defaults so that a session with no audio is a configuration rather than a
    crash - and nothing ever overrode them, so event sub-op 9 (sound) and
    sub-op 12 (music) both ran silently.

    Sub-op 12 goes through 0x00450F74, the FADE wrapper: EventScript_Execute
    calls it twice, at 0x00455AAF with CL=0 and 0x00455AFB with CL=1, so the
    two arms differ in looping and both fade the previous track out over two
    seconds. }
  TFormAudio = class(TSessionAudio)
  private
    FForm: TFrm_main;
  public
    constructor Create(AForm: TFrm_main);
    procedure PlayEffect(Id: Integer); override;
    procedure PlayMusic(Track: Integer; Loop: Boolean); override;
  end;

  TFormStartHost = class(TStartHost)
  private
    FForm: TFrm_main;
  public
    constructor Create(AForm: TFrm_main);
    function Opening: Boolean; override;
    { AND PlayMusic, which was the same omission twice over. GameStartOrLoad
      starts the stage music - playlist entry 1, midi\main01, looping on a new
      game, or the saved MusicTrack on a continue - by calling this, and the
      base class does nothing. So stage 1 ran in silence, for exactly the
      reason the cutscene never appeared. }
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
    FLastFrame: DWord;     // p_LastFrameTime 0x0046D1E0
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
    FStartHost: TStartHost;
    { The message box. It is the session's TEventHost, so sub-op 3 reaches it
      directly - and closing it is what advances the script, exactly as
      FUN_004568D0 does. Without one, reading a sign locked the game. }
    FDialogue: TDialogueBox;
    { bmp\power.bmp, the panel's backdrop. Loaded once - PowerUp_Show builds
      the surface every time and frees it when the panel closes, which is a
      lifetime detail, not a behaviour. }
    FPowerBmp: TBitmap;
    FGameOver: TGameOverScreen;
    FPause: TPauseMenu;
    FOpening: TOpeningScreen;
    FTitleSlept: Boolean;     { the once-only flag at 0x0046CFE8 }
    FEnding: TEndingScreen;
    { 0x00466888's three pieces of state. The stamp and the running count are
      locals of the original's own once-a-second sample. }
    FDebugStamp: DWord;
    FDebugFrames: Integer;
    FDebugFps: Integer;
    FUseArchive: Boolean;     { p_UseArchive 0x0046CCB4 }
    FEndingBmp: TBitmap;      { the surface at 0x0046D1F0 }
    FOpeningBmp: TBitmap;     { bmp\op%.3d.bmp, one slide at a time }
    FConfirmLatch: Boolean;
    { The running game. Everything that used to be inlined here - the player
      state, the camera, the entity pool, the events - lives in it now, so
      FPlayer below is gone and FSession.Player is the one copy. }
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
    { The callback shape the opening and the power-up panel want. Both go
      through 0x00450F14, which stops dead - fade 0 - so this is not a
      convenience default, it is the value those two call sites use. }
    procedure PlayMusicCut(Track: Integer; Loop: Boolean);
    procedure StopMusicTrack;
    procedure OpeningFade(FadeIn: Boolean);
    procedure EndingPicture(Index: Integer);
    procedure EndingMusic(Track: Integer; Loop: Boolean);
    procedure EndingStopMusic;
    procedure TitleResetState;
    procedure TitleResetOpening;
    procedure TitleGallery(Slot: Integer);
    procedure TitleInit;
    procedure GameOverRestart;
    procedure GameOverFade(FadeIn: Boolean);
    procedure GameOverMusic(Track: Integer);
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

{ TFrm_main_DDDD1Init @ 0x00465584. The whole boot, in the original's order:
  defaults into the settings record, system.dat over the top, system.ini over
  THAT for two fields, then every global the frame loop reads.

  Two things about the settings the record had wrong or missing:

    * +0x1A, fullscreen, DEFAULTS TO 1, not 0. CLAUDE.md said 1,0,0,0 for the
      four flag bytes and it is 1,0,1,0. The default is almost always
      overwritten anyway, because the INI read sets +0x1A unconditionally - 1
      when [disp] fullscreen is exactly 'on', 0 otherwise - so it only stands
      when system.ini is missing.
    * +0x28, the gallery selection, is zeroed AFTER the file is read, so it
      does not persist across a run even though it sits inside the 56 bytes
      that get written back.

  The last thing it does before installing the idle handler is clear the flag
  at 0x0046CFE8, which is what arms Title_Init's one-off 360 ms sleep. }
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

    { The original writes its defaults into p_Settings and then lets
      FileRead(h, p_Settings, 0x38) overwrite them, so a missing or short
      system.dat simply leaves the defaults standing. Same here: the record's
      initial value is the default and LoadSettings only reports whether the
      file was actually applied. }
    LoadSettings(DataDir);

    { system.ini sits beside the EXE, not in data\. Two fields, and both
      overwrite what system.dat just supplied. }
    Ini := TIniFile.Create(ExtractFilePath(ParamStr(0)) + 'system.ini');
    try
      Settings.FullScreenFlag :=
        Ord(LowerCase(Trim(Ini.ReadString('disp', 'fullscreen', ''))) = 'on');
      Settings.InputDevice :=
        StrToIntDef(Trim(Ini.ReadString('device', 'input', '')), 0);
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

    { The running game. It borrows the stage table and the map; the form keeps
      owning both, and the surfaces and sprite sheets with them. }
    FSession := TGameSession.Create(DataDir, FStages, FMap);
    { Replace the no-op audio the session builds for itself. }
    FSession.Audio.Free;
    FSession.Audio := TFormAudio.Create(Self);
    { Game_StartOrLoad's presentation hooks. The base class does nothing,
      which is right until Opening_Update and the playlist are translated -
      an opening that never runs is a cutscene that finishes instantly, and
      that is a truthful stub rather than a skipped step. }
    FStartHost := TFormStartHost.Create(Self);
    FDialogue := TDialogueBox.Create;
    FPowerBmp := FArchive.LoadBitmapByName('power.bmp');
    FSession.EventHost := FDialogue;

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

  { DDDD1Init @ 0x00465584 calls the fullscreen toggle at 0x0046572C with
    the flag it has just loaded out of system.dat. It is not a key binding. }
  SetFullScreen(FullScreenOn);

  FTitleScreen := TTitleScreen.Create;
  FGameOver := TGameOverScreen.Create;
  FPause := TPauseMenu.Create;
  FOpening := TOpeningScreen.Create;
  SetPauseSound(TitleSound);
  FEnding := TEndingScreen.Create;
  FEnding.OnPicture := EndingPicture;
  FEnding.OnMusic := EndingMusic;
  FEnding.OnStopMusic := EndingStopMusic;
  { PowerUp_Show's fanfare. The panel closes when this track ends, so without
    it the overlay was waiting on the looping stage music - see Dialogue.pas. }
  FDialogue.OnSound := TitleSound;
  FDialogue.OnMusic := PlayMusicCut;
  FDialogue.OnStopMusic := StopMusicTrack;
  FOpening.OnPicture := OpeningPicture;
  FOpening.OnMusic := PlayMusicCut;
  FOpening.OnStopMusic := StopMusicTrack;
  FOpening.OnFade := OpeningFade;
  FGameOver.OnRestart := GameOverRestart;
  FGameOver.OnFade := GameOverFade;
  FGameOver.OnMusic := GameOverMusic;
  { The original calls MainForm.DDSD1.Play straight from the title function;
    routing it through a callback keeps Title.pas off the component layer. }
  FTitleScreen.OnSound := TitleSound;
  FTitleScreen.OnResetState := TitleResetState;
  FTitleScreen.OnResetOpening := TitleResetOpening;
  FTitleScreen.OnGallery := TitleGallery;
  FLimitFrames := True;
  { Raise the multimedia timer period before the first frame: without it
    the Sleep(1) below takes about 15.6 ms and caps the rate anyway. }
  BeginFrameClock;
  FLastFrame := FrameClockMs;

  { The rest of the original's global reset, in its order. }
  Randomize;
  FillChar(FSession.Input, SizeOf(FSession.Input), 0);
  EntitiesLive := 0;
  EntitiesDrawn := 0;
  GameStateValue := GS_TITLE_INIT;
  SavedGameState := 0;
  { 0x0046CFE8 - armed here, spent once by Title_Init. }
  FTitleSlept := False;

  { The original: Application.FOnIdle := TFrm_main_AppIdle (+0xD8/+0xDC). }
  Application.OnIdle := AppIdle;
end;

{ ---------------------------------------------------------------------------
  AppIdle - TFrm_main_AppIdle @ 0x00464D30, the frame loop.

  DIVERGENCE DIV-001: the original set Done := False unconditionally and then
  spin-waited on timeGetTime until >15 ms had elapsed, which pegs a CPU core at
  100%. Here the frame is paced with a real sleep and Done is left True when
  there is time to spare, so the process idles properly between frames. Same
  ~60 FPS target, none of the burn.
  --------------------------------------------------------------------------- }
procedure TFrm_main.AppIdle(Sender: TObject; var Done: Boolean);
var
  Now_, Elapsed: DWord;
begin
  { FrameClockMs is timeGetTime. Reading the other one stepped 15-16 ms and
    held the game to 40 fps against the original's 62 - see GameState.pas.
    DWord arithmetic on purpose: the clock wraps every 49 days and the
    subtraction wraps with it, exactly as the original's does. }
  Now_ := FrameClockMs;
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
  { The animated background tiles, once a frame and OUTSIDE the state
    dispatch - which is where AppIdle ticks them, so a wall keeps moving
    behind a dialogue box or a pause. }
  FSession.TickBackground;

  { TWO DISPATCHES WITH THE ENTITY UPDATE BETWEEN THEM.

    This used to be one DispatchState with the session tick inside the play
    arm, and the trace in notes/trace_findings.md says that is not the shape.
    Frame 1 of a real session runs Title_Init, then Entity_UpdateAll, then
    Title_MainMenu - two different state arms in one frame, with the entity
    update in the middle, because Title_Init changes the state before the
    second dispatch reads it.

    Which arm goes where is not a guess either; it is what the log shows:

        before      10 Title_Init, 30 Stage_Begin,
                    60 SpawnNearCamera, 140 SpawnNearCamera + script
        between     Entity_UpdateAll, every state, every frame
        after       20 Title_MainMenu, 40 Game_StartOrLoad,
                    130 PauseMenu_Update, 140 MessageBox_Update, 60 HUD }
  FSession.BeginFrame;
  DispatchPre;
  FSession.TickEntities(GameStateValue);
  DispatchPost;
  { TODO step 7: button edge-detection and repeat timers }
  DrawDebugOverlay;       { 0x00466888, and off unless system.dat +0x1B is set }
  DDDD1.Present;          { step 8  - TDDDD_Present  0x00449D00 }

  Done := False;          { keep the loop running }
end;

{ Step 2-3: the original polled Joy through one of three device paths chosen by
  Settings+0x34, then read 4 buttons through p_KeyMap into p_InputState+0x1C.

  The axes are the two-key form the original's are: left and right both held
  cancel to zero rather than one winning, which is what a real d-pad does and
  what the controller's double-tap window assumes. }
procedure TFrm_main.PollInput;
var
  I: Integer;
begin
  Joy.Update;

  { The previous frame's buttons become the latch, which is what turns a held
    key into an edge. Player_Update reads both. }
  for I := 0 to 3 do
    FSession.Input.ButtonLatch[I] := FSession.Input.Button[I];

  FSession.Input.AxisX := Ord(Joy.IsDown(abRight)) - Ord(Joy.IsDown(abLeft));
  FSession.Input.AxisY := Ord(Joy.IsDown(abDown)) - Ord(Joy.IsDown(abUp));
  FSession.Input.Moving := (FSession.Input.AxisX <> 0)
                           or (FSession.Input.AxisY <> 0);

  { The confirm edge the message box needs, taken before Button[0] is
    overwritten below. }
  FConfirmLatch := FSession.Input.Button[0];

  FSession.Input.Button[0] := Joy.IsDown(abAction1);
  FSession.Input.Button[1] := Joy.IsDown(abAction2);
  FSession.Input.Button[2] := Joy.IsDown(abAction3);
  FSession.Input.Button[3] := Joy.IsDown(abAux1);

  { The double-tap window. Player_Update opens it and this counts it down. }
  if FSession.Input.HoldTimer > 0 then
  begin
    Dec(FSession.Input.HoldTimer);
    if FSession.Input.HoldTimer = 0 then
    begin
      FSession.Input.HeldX := 0;
      FSession.Input.HeldY := 0;
    end;
  end;
end;

{ The map, then the sprites, then the HUD. The camera is the session's layer
  origin, not the player state's ScrollX/Y - those are only the value the
  stage STARTED at, and reading them here is why the view never scrolled. }
procedure TFrm_main.DrawScene;
begin
  { The TILESET, rec[5 + layer], not the surface SET, rec[0]. The two are
    different numbers - a set is a file to load, a tileset is a slot inside
    the set once it is loaded - and passing rec[0] here drew surface slot 1,
    which is the menu background, so the map came out black. Terrain_Configure
    settles it: the original hands TMYBGANIME p_Surfaces[rec[5]] for exactly
    this layer. Stage 1 is set 1, tileset slot 6. }
  if (FMap <> nil) and (FStages <> nil) then
    FMap.Draw(DDDD1.Canvas, FSurfaces,
              FStages.Tileset[Settings.CurrentStage, 0],
              PixelOf(FSession.Layer.OriginX), PixelOf(FSession.Layer.OriginY),
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

{ 0x00466888. The debug overlay, and the only reader of the two counters
  Entity_UpdateAll maintains. Entities.pas records them as "nothing inside
  the update loop reads them back" - this is what reads them, from outside.

  Three lines at x 0, y 0, 8 and 16:

      FPS:  frames counted between two GetTickCount samples a second apart
      OBJ:  0x0046D20C, live entity slots        (EntitiesLive)
      S P:  0x0046D210, slots that also drew     (EntitiesDrawn)

  The whole thing is behind the DebugLog flag from system.dat +0x1B, which
  is off in the shipped settings - so none of it is normally visible.

  The FPS counter is a once-a-second SAMPLE, not an average: the frame count
  is latched and zeroed when a second has elapsed, so the number on screen is
  the previous second's total. }
procedure TFrm_main.DrawDebugOverlay;
var
  Now: DWord;
begin
  if not DebugLog then Exit;

  Now := FrameClockMs;
  if Int64(Now) - Int64(FDebugStamp) > 1000 then
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

{ 0x00466C78. The fullscreen toggle, called from FormKeyDown.

  Going IN: ask the display component for 320x240 at 16 bits. If that fails
  it shows a Shift-JIS message box - "the full screen cannot be used" - and
  closes the form. Then it hides the cursor.

  Coming OUT: if the desktop is under 16-bit colour it shows the other
  message - "please change the display mode" - and closes; otherwise it
  restores the mode, resizes the form back to 320x240, re-centres it, and
  shows the cursor. The border style is only restored when the game is NOT
  running from bmp.qda, which is a quirk of the original and not a rule.

  The mode change itself belongs to the DirectDraw component, which this
  reconstruction replaces wholesale, so what is reproducible here is the
  decision and the window geometry. The two message strings are recorded
  because they are the only Japanese text in the executable outside the
  dialogue files. }
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
    { The original only restores the border when p_UseArchive is clear. }
    if not FUseArchive then
      BorderStyle := bsSingle;
    Position := poScreenCenter;
    Screen.Cursor := crDefault;
  end;
end;

{ 0x00464484. One ending picture at a time: free whatever surface is up,
  build a 320x240 one, and load `ed%.3d.bmp` into it - from bmp.qda when the
  archive is in use and from bmp\ loose otherwise, which is the same pair of
  format strings every other loader here uses.

  The original keeps the surface in a global at 0x0046D1F0 and frees it on
  the next call; holding one TBitmap is the same lifetime. }
{ One frame of the cutscene. True while it is still running, which is what
  holds GameStartOrLoad at the door.

  The trace has this at 4726 frames for ten slides - 480 each for 1..7, 120 for
  the short slide 8, 480 for 9, and 765 for slide 10, which waits on the music
  rather than on its own timer. Opening.pas already modelled all of that
  correctly; nothing was driving it. }
function TFrm_main.OpeningStep: Boolean;
begin
  { No fader is modelled, so FadeBusy is always False - DIVERGENCE DIV-005.
    The sequence is the same, it just has no dissolve. }
  Result := FOpening.Update(ConfirmPressed(FSession.Input),
                            KbgmPlayer1.IsPlaying, False);
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

procedure TFrm_main.StopMusicTrack;
begin
  KbgmPlayer1.Stop;
end;

procedure TFrm_main.OpeningFade(FadeIn: Boolean);
begin
  { DIVERGENCE DIV-005 - no fader is modelled. }
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

procedure TFrm_main.EndingPicture(Index: Integer);
begin
  FreeAndNil(FEndingBmp);
  if FArchive <> nil then
    FEndingBmp := FArchive.LoadBitmapByName(Format(ENDING_PICTURE_FMT, [Index]));
end;

procedure TFrm_main.EndingMusic(Track: Integer; Loop: Boolean);
begin
  KbgmPlayer1.Play(Track, Loop);
end;

procedure TFrm_main.EndingStopMusic;
begin
  KbgmPlayer1.Stop;
end;

{ Title_Init @ 0x0046214C, in the order the original does it.

  Three things were missing from the version this replaces, all of them
  before the music:

    * GameState_Reset(mode 0) is the FIRST thing it does. Without it, entering
      the title from a running game left the pool, the events and the camera
      as they were.
    * ScreenPhase and the title sub-mode are both cleared. ScreenPhase is the
      counter the game-over screen, the opening and the message box share, so
      a title reached from any of them would have inherited a live phase.
    * a once-only Sleep of 0x168 ms, guarded by a flag at 0x0046CFE8 that is
      set the first time through. It is 360 milliseconds of nothing, exactly
      once per run, and it is reproduced rather than dropped because a pause
      at the point the audio device has just been opened is more likely to be
      load-bearing than decorative.

  It does NOT draw. The old version blitted the title background here; the
  original leaves that to Title_MainMenu, which paints it every frame.

  The Font_Define arguments match GameFont.pas exactly - 32 columns, 9x9
  cells, 8 pixel advance, last character 0x5F - which is independent
  confirmation of constants first read off the font sheet itself. }
procedure TFrm_main.TitleInit;
begin
  FSession.ResetState(0);
  { Load_Stage_Assets(Self, nil) - stage 0, which is also what rebuilds the
    font sheet in surface slot 0. }
  FStageLoaded := -1;
  LoadStage(0);

  { Track 0 is init.mid: a GM Reset and two Roland GS writes, not music. The
    original passes 0 as the repeat flag - a one-shot reset would not loop. }
  KbgmPlayer1.Play(0, False);

  ScreenPhase := 0;
  TitleSubMode := 0;
  GameStateValue := GS_TITLE_MENU;

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
procedure TFrm_main.TitleResetState;
begin
  FSession.ResetState(0);
end;

procedure TFrm_main.TitleResetOpening;
begin
  FOpening.Reset;
end;

{ 0x00462BE9: 'omake%.02d.bmp' through the same loader the ending uses. }
procedure TFrm_main.TitleGallery(Slot: Integer);
begin
  FreeAndNil(FEndingBmp);
  if FArchive <> nil then
    FEndingBmp := FArchive.LoadBitmapByName(Format('omake%.2d.bmp', [Slot]));
end;

{ The three things GameOver_Update needs from the form. Callbacks rather
  than direct calls so Title.pas stays clear of the component layer, exactly
  as the title screen's sound already is. }
procedure TFrm_main.GameOverRestart;
begin
  FSession.ResetState(0);
  { Load_Stage_Assets(MainForm, nil) - stage 0, the placeholder row, which is
    what reloads surface slot 0 and forces the font rebuild below. }
  FStageLoaded := -1;
  LoadStage(0);
end;

procedure TFrm_main.GameOverFade(FadeIn: Boolean);
begin
  { DIVERGENCE DIV-005. No fader is modelled. Recorded rather than dropped:
    the original
    sets +0x10 on the object at 0x0046CB6C and calls 0x0044DC48 with
    FadeIn as its third argument. }
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

{ HUD_Draw @ 0x00461BA8: a "%3d/%-3d" counter, an h:mm:ss timer, and a row of
  life icons - filled up to Lives, empty out to MaxLives. Icon graphics are not
  wired yet, so the count is shown as text. }
{ ---------------------------------------------------------------------------
  DrawHud - HUD_Draw @ 0x00461BA8.

  The earlier version of this was guesswork and got three things wrong: the
  counter was at (0, 8) rather than (8, 32), the 'TIME' label was missing, and
  lives were drawn as the text 'LIFE n/m'. The original draws lives as SPRITE
  ICONS across the top of the screen, one per life, and the icon is animated.
  --------------------------------------------------------------------------- }
const
  { Source x offsets of the life icon's animation frames, from the 4-int table
    at 0x0046CB44. Three distinct frames played as a ping-pong. }
  LIFE_ANIM_X: array[0..3] of Integer = (19, 38, 57, 38);
  LIFE_ANIM_TICKS = 8;      { advances once the timer passes 8 }
  LIFE_ICON_W = $12;        { 0x86 - 0x74 }
  LIFE_ICON_H = $14;
  LIFE_ICON_X0 = $74;       { source x of the unlit icon }
  LIFE_ICON_Y = 8;          { on screen }
  LIFE_ICON_STEP = $10;

  { The right-hand value of the '%3d/%-3d' counter is NOT a player-state field.
    Game_DrawText is handed PTR_DAT_0046D2B4[PlayerState+0x11DC], a 12-int
    table of goals at 0x00468EC4 that ends exactly where the ability-name array
    at 0x00468EF4 begins. So +0x11DC is an INDEX into this, not the target. }
  COUNTER_TARGETS: array[0..11] of Integer =
    (20, 50, 70, 130, 160, 400, 999, 30, 90, 270, 999, 0);

{ HUD_Draw @ 0x00461BA8. The address is repeated here, immediately above the
  declaration, because that is the only place tools/implemented.py looks - and
  with the const block above sitting between this routine and its write-up, a
  finished translation was being filed as unread prose. Fourth time that has
  happened; see the note in implemented.py. }
procedure TFrm_main.DrawHud;
var
  Secs, I, Target: Integer;
  Sheet: TBitmap;
begin
  if FFont = nil then Exit;
  Sheet := FSurfaces[1];    { *(p_Surfaces + 4) - slot 1 }

  { The counter icon, then '@ ' + the count. The '@' is a real glyph in the
    9x9 sheet, not punctuation - the original concatenates the literal '@ '
    at 0x00461EB8 in front of the formatted number. }
  if Sheet <> nil then
    DDDD1.DrawSprite(Sheet, 7, $12, Rect($60, 0, $74, 10));

  Target := 0;
  if (FSession.Player.TargetIndex >= 0) and
     (FSession.Player.TargetIndex <= High(COUNTER_TARGETS)) then
    Target := COUNTER_TARGETS[FSession.Player.TargetIndex];
  FFont.TextOut(DDDD1.Canvas, 8, $20,
    '@ ' + Format('%3d/%-3d', [FSession.Player.Counter, Target]), 0);

  { Variant 2 for the label, 0 for the digits - the original passes exactly
    these as Game_DrawText's fifth argument. }
  FFont.TextOut(DDDD1.Canvas, $D0, $E0, 'TIME', 2);
  Secs := FSession.Player.ElapsedSec;
  FFont.TextOut(DDDD1.Canvas, $F8, $E0,
    Format('%.2d:%.2d:%.2d', [Secs div 3600, (Secs div 60) mod 60, Secs mod 60]), 0);

  { Advance the icon animation. The original ticks this inside HUD_Draw, so its
    speed is tied to the HUD being drawn rather than to the frame loop. }
  Inc(FLifeAnimTimer);
  if FLifeAnimTimer > LIFE_ANIM_TICKS then
  begin
    FLifeAnimTimer := 0;
    FLifeAnimIndex := (FLifeAnimIndex + 1) and 3;
    FLifeAnimX := LIFE_ANIM_X[FLifeAnimIndex];
  end;

  { The original clamps the stored lives here rather than at the point of
    damage, so a corrupt save is corrected by drawing the HUD. }
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

{ Step 5: the state machine. Values and handler addresses in GameState.pas. }
{ The arms that run BEFORE the entity update. }
procedure TFrm_main.DispatchPre;
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
      TitleInit;
    GS_STAGE_BEGIN:
      begin
        { Stage_Begin @ 0x00462210. The ASSETS are the form's - it owns the
          surfaces and the sprite sheets - and everything after them is the
          session's: terrain, events, camera, and the player entity. The
          order is the original's and it matters, because the session reads
          the map and the frames the load has just replaced. }
        LoadStage(Settings.CurrentStage);
        FSession.SetFrames(FSprites);
        FSession.BeginStage(Settings.CurrentStage, GameStateValue);
        FDialogue.Bind(FSession.Events, FSession.Runner, @FSession.Player,
                       FSession.Pool);
      end;
    GS_PLAY,
    GS_STATE_140:
      { Spawning near the camera and the event script, both ahead of the
        entity update. Unconditional now: this used to be skipped entirely
        whenever a message box was up, and the trace shows the script running
        on all 2213 frames of state 140, box or no box. }
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
        FTitleScreen.Update(FMoveY, FMoveX, FConfirm);
        FMoveY := 0;
        FMoveX := 0;
        FConfirm := False;
        FTitleScreen.Draw(DDDD1.Canvas, FFont, FSurfaces[1], FSurfaces[2]);
      end;
    GS_PLAYER_INIT:
      begin
        { Game_StartOrLoad @ 0x00462F40. This used to be an inlined
          approximation - load the save or start fresh, then go. The real one
          is in PlayerState.pas and does considerably more: the settings
          unlocks, the music, the session flags AFTER the load, and the
          opening cutscene gate on a new game. }
        if FTitleScreen.SubMode = 1 then
          Mode := smContinue
        else
          Mode := smNewGame;
        GameStartOrLoad(FSession.Player, Settings, Mode, FStartHost, True,
                        FDataDir + 'data' + PathDelim + 'save.dat',
                        GameStateValue);
      end;
    { 0x00461A44. State 100 is GAME OVER, and it was running the play frame -
      the dispatch grouped it with 60 and 140 because all three call
      HUD_Draw, which is the one thing they do share. }
    GS_PLAY_ALT:
      begin
        { No fader is modelled yet, so FadeBusy is always False and the
          screen steps straight from 0 to 2. That is a configuration, not a
          stub: the sequence is the same, it just has no dissolve. }
        if FGameOver.Update(False, KbgmPlayer1.IsPlaying,
                            ConfirmPressed(FSession.Input), GameStateValue) then
          DrawGameOver;
      end;
    GS_PLAY,
    GS_STATE_140:
      begin
        { While the box is up it - not the interpreter - drives the script,
          and no game logic steps. That is the original's shape: sub-op 3
          waits, and FUN_004568D0 is what calls EventScript_AdvanceStep. }
        if FDialogue.Active then
        begin
          { The three-line box is dismissed by the player; the full-screen
            panel is dismissed by its own fanfare finishing, which is what
            Overlay_Update asks the music player. One call, two sources of
            "done", because the original has one function with two modes.

            The `else FSession.Frame` that used to sit here is gone: the
            session no longer stops while the box is up. MessageBox_Update and
            Entity_UpdateAll were logged in the same frames, so entities do
            keep updating through a conversation - what stops during one is
            Entity_PlayerTouch, which the log finds in state 60 and nowhere
            else. That gating belongs to the handlers, not to us. }
          if FDialogue.Mode = omPanel then
            FDialogue.Update(not KbgmPlayer1.IsPlaying, False, False,
                             GameStateValue)
          else
            FDialogue.Update(FSession.Input.Button[0] and not FConfirmLatch,
                             FSession.Input.AxisY < 0, FSession.Input.AxisY > 0,
                             GameStateValue);
        end;
        DrawScene;
      end;
    GS_PAUSE:
      begin
        { The original BLACKS THE SCREEN OUT and draws the menu over it - it
          does not show the frozen game behind. This used to redraw the scene,
          which looked more considerate and is not what the game does. }
        FPause.Update(FSession.Input, GameStateValue);
        FPause.Draw(DDDD1.Canvas, FFont, SCREEN_W, SCREEN_H);
      end;
    GS_ENDING:
      begin
        FEnding.Update(Settings, FSession.Player, GameStateValue);
        DrawScene;
      end;
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
{ ---------------------------------------------------------------------------
  FormKeyDown @ 0x004665C8.

  Now translated from the real function rather than guessed. The whole of the
  original is:

      if Key = VK_ESCAPE then
      begin
        if GameState = $82 then begin GameState := 999; Exit end;
        SavedMenuIndex := MenuIndex;  MenuIndex := 0;
        SavedGameState := GameState;  GameState := $82;
      end;
      if (Key = $52) and (Shift = $04) then GameState := 10;

  Two corrections to what was here before:

    - Escape while already paused QUITS. It does not resume. Resuming is the
      pause menu's own PAUSE_CONTINUE entry, which is what calls LeavePause.
    - Ctrl+R is a soft reset back to the title. Shift is compared for EQUALITY
      with $04, not tested for membership, so Ctrl+Shift+R deliberately does
      not fire - reproduced with `Shift = [ssCtrl]` rather than `ssCtrl in`.
  --------------------------------------------------------------------------- }
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

  { DIVERGENCE DIV-002, not part of the original handler. The original reads movement
    and buttons from the Joy component in the frame loop, through one of three
    DirectInput paths; none of that is implemented yet, so the menus are driven
    from the keyboard here instead. Delete this block once Joy polls for real. }
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

{ There was no OnKeyUp at all, so Joy.Down only ever gained bits and a key
  pressed once stayed down for the rest of the session. That did not show
  while nothing read Joy.Down; the moment the controller did, it would have
  meant walking right forever. }
procedure TFrm_main.FormKeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  Joy.KeyUp(Key);
end;

{ ---------------------------------------------------------------------------
  FormDestroy @ 0x00466644 - which is really the settings writer.

  The original copies the loose runtime globals back into the settings record
  and writes all 56 bytes over data\system.dat, then mirrors the fullscreen
  flag into system.ini's [disp] section as 'on' or 'off'. It also dumps
  'debug.log' first when the debug flag is set, and that is not reproduced.

  Note the order: p_KeyMap[0..3] -> +0x08..+0x14, then the four flag bytes,
  then the write. GlobalsToSettings does the flags; the key map already lives
  in the record.
  --------------------------------------------------------------------------- }
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
  { TODO: teardown - the original released the sprite engine and surfaces }
end;

end.
