{ Main form and frame loop. Published component field names must match
  GmMain.lfm because resource streaming binds them by name. AppIdle implements
  TFrm_main_AppIdle @ 0x00464D30. }

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
    FLastFrame: DWord;     // p_LastFrameTime 0x0046D1E0
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
    { The callback shape the opening and the power-up panel want. Both go
      through 0x00450F14, which stops dead - fade 0 - so this is not a
      convenience default, it is the value those two call sites use. }
    procedure PlayMusicCut(Track: Integer; Loop: Boolean);
    { 0x00450F74 - stop with a two-second fade, then play. }
    procedure PlayMusicFading(Track: Integer; Loop: Boolean);
    { 0x00450EDC / 0x00450EF0 - see KbgmPlayer.pas. }
    procedure RememberMusicTrack;
    procedure ResumeMusicTrack;
    { The screen fade lives on the display component - 0x0044DC48 and the
      object at 0x0046CB6C. }
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

{ ---------------------------------------------------------------------------
  DDDD1Init - TFrm_main_DDDD1Init @ 0x00465584

  Startup loads data\system.dat over defaults, applies system.ini, initializes
  subsystems, and finally installs the idle handler.
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

{ TFrm_main_DDDD1Init @ 0x00465584. The whole boot, in the original's order:
  defaults into the settings record, system.dat over the top, system.ini over
  THAT for two fields, then every global the frame loop reads.

  Two things worth knowing about the settings record:

    * +0x1A, fullscreen, DEFAULTS TO 1. It stands only when system.ini is
      missing - the INI read sets it unconditionally either way.
    * +0x28, the gallery selection, is zeroed AFTER the file is read, so it
      does not persist across a run even though it sits inside the 56 bytes
      written back.

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

    { system.ini carries [disp] fullscreen and [device] input, and both
      overwrite what system.dat just supplied. Two deliberate exactnesses:

        * the fullscreen compare is case-SENSITIVE (@LStrCmp at 0x004656D8),
          so 'ON', 'On' and ' on ' all mean WINDOWED.
        * input goes through the one-argument StrToInt at 0x00465708, which
          RAISES on anything it cannot parse - including the empty string a
          missing key returns. A malformed [device] input takes the original
          down at start-up, so it takes this down too.

      The shipped file parses the same either way. }
    { DataDir, not ExtractFilePath(ParamStr(0)). In the original the two are
      the SAME directory - akuji.exe ships beside system.ini - but this build
      lives in src/ and finds the data with FindGameData, so every other path
      here goes through DataDir and this one must too.

      It matters because StrToInt below is faithful and RAISES on the empty
      string a missing key returns. }
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
  { The original calls MainForm.DDSD1.Play straight from the title function;
    routing it through a callback keeps Title.pas off the component layer. }
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

  { SoftwareVsync, the global at 0x0046CE60 - not a field of this form. The
    options screen toggles that global (Title_MainMenu's case 6 does
    `*p_SoftwareVsync ^= 1`) and DDDD1Init loads it from system.dat +0x18, so a
    private copy set to True once made the option inert: every frame was
    limited whatever the setting said. }
  if SoftwareVsync and (Elapsed < FRAME_MS) then
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

  { TWO DISPATCHES WITH THE ENTITY UPDATE BETWEEN THEM, because Title_Init
    changes the state before the second dispatch reads it - frame 1 of a
    real session runs Title_Init, Entity_UpdateAll, then Title_MainMenu.
    Which arm goes where is from the trace, not from reading: see
    notes/trace_findings.md. }
  FSession.BeginFrame;
  DispatchPre;
  { 0x00464D30 counts the event delay down HERE - between the state-60/140
    spawn-and-script block and the state-10/30 one. Those are separate `if`s on
    the same state value in the original and mutually exclusive arms of one
    case here, so no frame runs both and the position is equivalent. }
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
  { The fade advances once a frame, which is what lets FadeBusy fall to False
    after thirty of them and the interpreter's wait finish.

    NOT WHILE PAUSED - the original guards this with the same state test it
    just used for PauseMenu_Update, so a room transition caught mid-fade
    holds where it is until you unpause instead of running to completion
    behind the menu. }
  if GameStateValue <> GS_PAUSE then
    DDDD1.TickFade;

  { The frame loop's own way into the pause menu, at 0x00464D30, beside
    FormKeyDown's VK_ESCAPE - both write the same four globals, so both call
    EnterPause. The guards are the original's: not while already paused, and
    not on the title screen's OPTIONS page, where this button is that screen's
    back key instead. }
  if (GameStateValue <> GS_PAUSE)
     and not ((GameStateValue = GS_TITLE_MENU) and (TitleSubMode = TSM_OPTIONS))
     and FSession.Input.Button[PAUSE_CANCEL_BUTTON]
     and not FSession.Input.ButtonLatch[PAUSE_CANCEL_BUTTON] then
    EnterPause;

  { DIVERGENCE DIV-002. These stand in for the Joy poll the original runs at
    the top of every frame, which overwrites the previous frame's values
    unconditionally - so they must live exactly one frame and be cleared HERE,
    for every state, not inside whichever arm happens to consume them. A state
    that does not clear them hands them to whatever runs next, and screen
    changes make that a different screen's input.

    The frame boundary rather than the top: these are fed by WM_KEYDOWN between
    frames, so this is where a key event stops being this frame's input. That
    placement belongs to the stand-in and goes when DIV-002 does. }
  FMoveY := 0;
  FMoveX := 0;
  FConfirm := False;

  { Step 7. Must come after the dispatch: the handlers read Moving and the
    button latches expecting the PREVIOUS frame's values. The original's
    equivalent block sits here too - after the pause check, before the
    present. }
  InputStep7;
  DrawDebugOverlay;       { 0x00466888, and off unless system.dat +0x1B is set }
  DDDD1.Present;          { step 8  - TDDDD_Present  0x00449D00 }

  Done := False;          { keep the loop running }
end;

{ Step 2-3: the original polled Joy through one of three device paths chosen by
  Settings+0x34, then read 4 buttons through p_KeyMap into p_InputState+0x1C.

  The axes are the two-key form the original's are: left and right both held
  cancel to zero rather than one winning, which is what a real d-pad does and
  what the controller's double-tap window assumes. }
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

  { p_InputState[0x34], computed here in 0x00464D30 immediately after the same
    four-button poll and never anywhere else:

        p_InputState[0x34] = 0;
        if ((btn0 && !latch0) || (btn1 && !latch1) || (btn2 && !latch2))
            p_InputState[0x34] = 1;

    THREE buttons, not the two Input_ConfirmPressed tests - the pause/cancel
    button counts here as well. }
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
  { Sprite bucket 8, which 0x00464D30 draws after the HUD and the message box
    rather than with the rest. Nothing shipped reaches it - see DrawTop. }
  FSession.Sprites.DrawTop(DDDD1.Canvas, FSurfaces);
end;

{ Load_Stage_Assets @ 0x00465A1C. The record's rec[0] selects the surface set,
  rec[1] the sprite set, and rec[2..4] up to three map layers with -1 meaning
  none. The original skips a reload when the set is already current; the same
  guard is kept here via FStageLoaded. }
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

{ 0x00466888. The debug overlay, and the only reader of the two counters
  Entity_UpdateAll maintains. All of it is behind the DebugLog flag from
  system.dat +0x1B, which is off in the shipped settings.

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
    updating. The original subtracts in 32 bits because it has nothing
    else. }
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

{ 0x00466C78. The fullscreen toggle, called from FormKeyDown. Either
  direction can fail - no 320x240 at 16 bits going in, a desktop under 16-bit
  colour coming out - and the original's answer to both is a Shift-JIS message
  box and then Close. Restoring the border style only when NOT running from
  bmp.qda is a quirk of the original, not a rule.

  The mode change belongs to the DirectDraw component this replaces wholesale,
  so what is reproducible here is the decision and the window geometry. }
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
  { Every caller writes the step to self+0x10 first and passes Mode 0 - and it
    has to be written, not assumed: the field persists, and the ending's
    results screen leaves 2 in it. Every event-script site writes 4
    (0x00455331, 0x0045536E, 0x004554FD, 0x0045553A, 0x00455712, 0x00455E8C,
    0x00455F41). }
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
  { Opening_Update makes the same pair of calls every other screen does -
    self+0x10 := 4, then 0x0044DC48 with the direction. The argument here is
    named FadeIn and StartFade takes FadeOut, so it inverts. }
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
  { FUN_00450CBC with a fade of 0 - a hard stop. }
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

{ 0x00464484. One ending picture at a time: free whatever surface is up,
  build a 320x240 one, and load `ed%.3d.bmp` into it - from bmp.qda when the
  archive is in use and from bmp\ loose otherwise, which is the same pair of
  format strings every other loader here uses.

  The original keeps the surface in a global at 0x0046D1F0 and frees it on
  the next call; holding one TBitmap is the same lifetime. }
procedure TFrm_main.EndingPicture(Index: Integer);
begin
  FreeAndNil(FEndingBmp);
  { The original frees the surface unconditionally and only creates a new one
    when the slide has an image, so a -1 leaves the screen without one. }
  if (Index >= 0) and (FArchive <> nil) then
    FEndingBmp := FArchive.LoadBitmapByName(Format(ENDING_PICTURE_FMT, [Index]));
end;

{ Ending_ShowPicture @ 0x00464484. Phases 2 and 5 name their picture instead
  of numbering it, and it is full screen rather than the slide's panel. }
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

{ The original writes the step to the fader's +0x10 and then starts it. }
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

{ Title_Init @ 0x0046214C, in the order the original does it. It does NOT
  draw - Title_MainMenu paints the background every frame. }
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

  { ScreenPhase is shared with the game-over screen, the opening and the
    message box, so a title reached from any of them starts mid-phase. }
  ScreenPhase := 0;
  TitleSubMode := 0;
  GameStateValue := GS_TITLE_MENU;

  { 360 ms of nothing, once per run, guarded by a flag at 0x0046CFE8.
    Reproduced rather than dropped: a pause just after the audio device was
    opened is more likely load-bearing than decorative. }
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
{ The options screen's volume row, which the original follows with the same
  57-channel sweep Title_Init ends on. }
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
  { Stage_Begin @ 0x00462229 writes 4 like the rest. }
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

{ The fader's +0x0D, which Player_Update dereferences at the point of use. }
function TFrm_main.EntityWorldFading: Boolean;
begin
  Result := DDDD1.FadeBusy;
end;

{ FUN_00450FD0, which GameOver_Update calls from inside its phase-2 block
  rather than being handed the answer. }
function TFrm_main.GameOverMusicPlaying: Boolean;
begin
  Result := KbgmPlayer1.IsPlaying;
end;

procedure TFrm_main.GameOverFade(FadeIn: Boolean);
begin
  { The original sets +0x10 on the object at 0x0046CB6C and calls 0x0044DC48
    with FadeIn as its third argument - 0x00461A7E and 0x00461B2D, both 4. }
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

{ HUD_Draw @ 0x00461BA8: a "%3d/%-3d" counter, an h:mm:ss timer, and a row of
  life icons filled through Lives and empty through MaxLives. }
{ ---------------------------------------------------------------------------
  DrawHud - HUD_Draw @ 0x00461BA8.

  The counter begins at (8, 32), the TIME label precedes the timer, and lives
  are animated sprite icons across the top of the screen.
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
  { TRIMMED, and the format is padded on purpose so that it has something to
    trim. 0x00461BA8 runs the result of Format through 0x00407D44 - which is
    Trim: skip bytes < 0x21 from the front, drop them from the back, Copy what
    is left - and only then concatenates the '@ ' in front of it. '%3d' right
    aligns the count in three columns and '%-3d' left aligns the goal, so the
    untrimmed string is '  0/2  '; without the Trim the '@ ' is followed by two
    spaces and the number sits two glyphs right of where it belongs. }
  FFont.TextOut(DDDD1.Canvas, 8, $20,
    '@ ' + Trim(Format('%3d/%-3d', [FSession.Player.Counter, Target])), 0);

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
      { Title_Init @ 0x0046214C. The asset load and the font definition
        already happen in DDDD1Init, so what this adds is the music and the
        volume sweep over all 57 effect buffers. }
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
        { The rest of Load_Stage_Assets - terrain, the background animator and
          the event scripts. Both are its callers in the original; neither is
          Stage_Begin's. }
        FSession.LoadStageAssets(Settings.CurrentStage);
        FSession.BeginStage(Settings.CurrentStage, GameStateValue);
        FDialogue.Bind(FSession.Events, FSession.Runner, @FSession.Player,
                       FSession.Pool, FSession.World);
        { Sub-op 14 writes a tile, and the original writes to p_TileMaps[0]. }
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
        { Game_StartOrLoad @ 0x00462F40 handles save/new-game state, unlocks,
          music, session flags, and the opening cutscene. }
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
        { GameOver_Update @ 0x00461A44 waits on the FADER between its
          phases, so FadeBusy has to be the live one. Hard-code it False and
          phase 0 falls straight into phase 1 in the same frame, and BOTH
          dissolves are invisible. }
        if FGameOver.Update(DDDD1.FadeBusy,
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
            panel is dismissed by its own fanfare finishing. One call, two
            sources of done, because the original is one function with two
            modes.

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
{ FormKeyDown @ 0x004665C8. Two things that read as bugs and are not:
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

procedure TFrm_main.FormKeyUp(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  Joy.KeyUp(Key);
end;

{ FormDestroy @ 0x00466644 - really the settings writer: the loose runtime
  globals go back into the record, all 56 bytes over data\system.dat, and the
  fullscreen flag is mirrored into system.ini. The original also dumps
  'debug.log' first when the debug flag is set; that is not reproduced. }
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
