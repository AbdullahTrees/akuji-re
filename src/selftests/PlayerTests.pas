{ Self-tests for the camera, the player tables, and the helpers the whole
  movement path shares. }

unit PlayerTests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, TypInfo,
  QdaArchive, SoundTable, WaveFile, AudioMixer, AudioOut, MidiFile, KbgmPlayer,
  Directions, Entities, EventScripts, EventCommands, PlayerState, GameState,
  Stages, Camera, TileMaps, Player, EntityHandlers, EventRunner, GameSession,
  SpritePool, Sprites, Dialogue, BgAnime, UnitInit, Title, Ending, Opening,
  GameFont, DDDDComponent, Surfaces,
  MsClock;

function SelfTestPlayer(Log: TStrings): Integer;

implementation

uses
  TestSupport;

{ ---------------------------------------------------------------------------
  --selftest-player <gamedir> : the camera, the player's tables, and the two
  small helpers the whole movement path shares.

  Four independent things, none checkable by "does it load":

  1. THE SCROLL CLAMP against the real maps. Camera.pas claims the layer stops
     at (MapTiles - 10) * TileW horizontally and (MapTiles - 7.5) * TileH
     vertically. If that is right it equals MapPixels - ScreenSize EXACTLY on
     every map, with no slack. All 65 shipped maps are checked. Rounding 7.5 to
     7 or 8, or swapping the tile width for the height, fails at once.

  2. THE DEAD ZONE, swept over every pixel of the screen and both signs of
     velocity against a plain restatement of the rule, plus a clamp check so
     that a version which had lost the bounds test entirely cannot pass.

     The four boundary numbers below are written out as LITERALS on purpose.
     They were Camera.DEADZONE_* at first, and that version passed happily with
     DEADZONE_RIGHT moved from 177 to 176 - the comparison was against the same
     constant it was meant to be checking, so it could only ever catch a change
     in the logic, never in the numbers. Do not tidy these back into the
     constants.

  3. ApproachZero and RectOverlap. ApproachZero is swept for the property that
     matters - never cross zero, never grow, always move - and RectOverlap
     against brute force over a grid of boxes, with a control so that a
     predicate which is simply always true cannot pass.

  4. THE SPRITE TABLES: six of them, contiguous, and in the base set the
     right-facing sprite is the left-facing one plus ten.
  --------------------------------------------------------------------------- }

{ Game_StartOrLoad @ 0x00462F40.

  NEW GAME and CONTINUE differ by one branch, so what is worth checking is not
  each path on its own but what the ORDER of the writes makes true: that a
  continue is a new game with a file read over the top, that a failed read
  therefore leaves a playable new game, and that difficulty survives the read
  because the session flags are applied afterwards. }
type
  { Counts the calls the original makes through the form, and can hold the
    cutscene open. }
  TStartStub = class(TStartHost)
  public
    Busy: Boolean;
    Tracks: string;
    { How the PREVIOUS track was stopped on each call. The new game fades over
      two seconds and a continue stops dead, and those go through two
      different wrappers in the original - 0x00450F74 and 0x00450F14. }
    Fades: string;
    function Opening: Boolean; override;
    procedure PlayMusic(Track: Integer; Loop: Boolean;
                        FadeSeconds: Integer); override;
  end;

function TStartStub.Opening: Boolean;
begin
  Result := Busy;
end;

procedure TStartStub.PlayMusic(Track: Integer; Loop: Boolean;
                               FadeSeconds: Integer);
begin
  Tracks := Tracks + Format('%d ', [Track]);
  Fades := Fades + Format('%d ', [FadeSeconds]);
end;

{ Stage_Begin @ 0x00462210.

  Most of it is host calls, so what is worth checking is the part that is not:
  the three conversions that say what SpawnX, SpawnY and ScrollX/Y mean, and
  the ORDER, since loading the assets replaces what the other two read. }
type
  TStageHostStub = class(TStageHost)
  public
    Calls: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure PrepareDisplay; override;
    procedure ResetInput; override;
    procedure LoadStageAssets(StageIndex: Integer); override;
    procedure DefineFont; override;
    procedure SetBackgroundSurface; override;
  end;

constructor TStageHostStub.Create;
begin
  inherited Create;
  Calls := TStringList.Create;
end;

destructor TStageHostStub.Destroy;
begin
  Calls.Free;
  inherited Destroy;
end;

procedure TStageHostStub.PrepareDisplay;
begin Calls.Add('display'); end;
procedure TStageHostStub.ResetInput;
begin Calls.Add('input'); end;
procedure TStageHostStub.LoadStageAssets(StageIndex: Integer);
begin Calls.Add(Format('assets %d', [StageIndex])); end;
procedure TStageHostStub.DefineFont;
begin Calls.Add('font'); end;
procedure TStageHostStub.SetBackgroundSurface;
begin Calls.Add('background'); end;

function TestStageBegin(Log: TStrings): Integer;
var
  P: TPlayerState;
  L: TLayerInfo;
  Pool: TEntityPool;
  H: TStageHostStub;
  GS, Slot, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- Stage_Begin ---');

  Pool := TEntityPool.Create;
  H := TStageHostStub.Create;
  try
    InitNewGame(P, 0);
    P.SpawnX := 96;
    P.SpawnY := 115;
    P.ScrollX := 64;
    P.ScrollY := 448;
    P.SpawnFacing := $10;
    FillChar(L, SizeOf(L), 0);
    GS := GS_STAGE_BEGIN;

    StageBegin(Pool, L, P, H, 7, GS);

    { The state exists for exactly one frame and this is what ends it. }
    Want(GS = GS_PLAY,
         Format('Stage_Begin left the state at %d, want %d', [GS, GS_PLAY]));

    { The assets must be loaded BEFORE the origin and the spawn, because
      loading replaces the tilemaps and surfaces they read. Checking the whole
      sequence rather than "assets were loaded" is what pins that. }
    Want(H.Calls.CommaText = 'display,input,"assets 7",font,background',
         'the setup ran in the order ' + H.Calls.CommaText);

    { ScrollX/Y are PIXELS; the layer origin is 1/32 pixel, biased. }
    Want(L.OriginX = (64 shl 5) + POSITION_BIAS,
         Format('origin x is %d, want %d',
                [L.OriginX, (64 shl 5) + POSITION_BIAS]));
    Want(L.OriginY = (448 shl 5) + POSITION_BIAS,
         Format('origin y is %d, want %d',
                [L.OriginY, (448 shl 5) + POSITION_BIAS]));

    { The player is slot 0 - EKIND_SINGLE has exactly one slot, which is what
      lets every homing entity read p_Entities[0] with no indirection. }
    Slot := SLOT_NONE;
    if Pool.Alive[0] then
      Slot := 0;
    Want(Slot = 0, 'Stage_Begin did not put the player in slot 0');
    if Slot = 0 then
    begin
      Want(Pool.Field(0, EF_TYPE) = 1,
           Format('the player spawned as type %d, want 1',
                  [Pool.Field(0, EF_TYPE)]));
      { SpawnX/Y are pixels too, and PosX gives them back unbiased. 96 pixels
        is 3072 in 1/32 units - the numbers are written out rather than
        recomputed from the field, so a changed shift is visible. }
      Want(Pool.PosX(0) = 3072,
           Format('the player spawned at x=%d, want 96 pixels = 3072',
                  [Pool.PosX(0)]));
      Want(Pool.PosY(0) = 3680,
           Format('the player spawned at y=%d, want 115 pixels = 3680',
                  [Pool.PosY(0)]));
      Want(Pool.Field(0, EF_FACING) = $10,
           Format('the player faces %d, want the saved $10',
                  [Pool.Field(0, EF_FACING)]));
      Want(Pool.LiveCount = 1,
           Format('Stage_Begin spawned %d entities, want 1',
                  [Pool.LiveCount]));
    end;

    { A default new game lands where Game_StartOrLoad's constants say: tile 3
      across, and 19 pixels into tile 3 down. The asymmetry is the point. }
    Pool.Clear;
    InitNewGame(P, 0);
    FillChar(L, SizeOf(L), 0);
    GS := GS_STAGE_BEGIN;
    StageBegin(Pool, L, P, H, 1, GS);
    Want(Pool.PosX(0) = 96 * 32, 'the default spawn is not 96 pixels across');
    Want(Pool.PosY(0) = 115 * 32, 'the default spawn is not 115 pixels down');
    { And the two axes really are offset differently. 96 is tile 3 flush; 115
      is tile 3 plus 19: the spawn is placed by the feet, not centred. }
    Want(DEFAULT_SPAWN_X = 3 * 32,
         Format('the default X %d is not flush with tile 3',
                [DEFAULT_SPAWN_X]));
    Want(DEFAULT_SPAWN_Y = 3 * 32 + 19,
         Format('the default Y %d is not tile 3 plus 19', [DEFAULT_SPAWN_Y]));
    Want(SPAWN_FOOT_Y <> SPAWN_CENTRE_X,
         'the two spawn offsets have become equal; the original has 16 and 19');
  finally
    H.Free;
    Pool.Free;
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('OK - assets first, then the origin and the player, then GS_PLAY');
end;

function TestGameStart(Log: TStrings; const GameDir: string): Integer;
var
  P: TPlayerState;
  Cfg: TGameSettings;
  H: TStartStub;
  GS, Bad, SavedStage, SavedMusic, SavedDiff: Integer;
  SaveName, TempSave: string;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

  procedure FreshSettings(Level: Integer);
  begin
    FillChar(Cfg, SizeOf(Cfg), 0);
    Cfg.GameLevel := Level;
    Cfg.CurrentStage := 999;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- Game_StartOrLoad ---');
  SaveName := IncludeTrailingPathDelimiter(GameDir) + 'data' + PathDelim
              + 'save.dat';

  H := TStartStub.Create;
  try
    { --- the cutscene holds everything back -------------------------- }
    FreshSettings(1);
    FillChar(P, SizeOf(P), $AB);
    GS := GS_TITLE_MENU;
    H.Busy := True;
    Want(not GameStartOrLoad(P, Cfg, smNewGame, H, True, SaveName, GS),
         'the cutscene was running but the game started anyway');
    Want(GS = GS_TITLE_MENU,
         'the game state moved on while the cutscene was still running');
    Want(Cfg.CurrentStage = 999,
         'the settings were touched while the cutscene was still running');
    Want(H.Tracks = '', 'music started while the cutscene was still running');
    Want(P.Progress[0] = $AB,
         'the player state was written while the cutscene was still running');

    { CONTINUE does not wait for it. That is what says the gate is on the
      new-game path specifically and not on the function. }
    H.Busy := True;
    H.Tracks := '';
    H.Fades := '';
    FreshSettings(1);
    GS := GS_TITLE_MENU;
    Want(GameStartOrLoad(P, Cfg, smContinue, H, True, SaveName, GS),
         'CONTINUE waited for the opening cutscene');

    { --- a new game -------------------------------------------------- }
    H.Busy := False;
    H.Tracks := '';
    H.Fades := '';
    FreshSettings(1);
    GS := GS_TITLE_MENU;
    Want(GameStartOrLoad(P, Cfg, smNewGame, H, True, SaveName, GS),
         'a new game would not start');
    Want(GS = GS_STAGE_BEGIN,
         Format('a new game left the state at %d, want %d',
                [GS, GS_STAGE_BEGIN]));
    { Written out, not START_STAGE. An expectation phrased in terms of the
      constant it is checking moves with it and cannot fail. }
    Want(Cfg.CurrentStage = 1,
         Format('a new game starts at stage %d, want 1', [Cfg.CurrentStage]));
    Want(P.MusicTrack = 1,
         Format('a new game set music track %d, want 1', [P.MusicTrack]));
    Want(Trim(H.Tracks) = '1', 'the new game played ' + H.Tracks);
    { The new game FADES the previous track out; a continue cuts it. Two
      different wrappers in the original - 0x00450F74 and 0x00450F14 - and the
      two-second value is KBGMFadeOut's own arithmetic, read out of the
      Kbgm32.dll that ships beside the exe. }
    Want(Trim(H.Fades) = IntToStr(KBGM_STOP_FADE_NEWGAME),
         'the new game stopped the previous track with fade "' + Trim(H.Fades)
         + '", want ' + IntToStr(KBGM_STOP_FADE_NEWGAME));
    Want(P.Lives = DEFAULT_LIVES, 'a new game does not start on three lives');
    Want(P.SpawnX = 96, Format('the spawn point is x=%d, want 96 pixels',
                               [P.SpawnX]));
    Want(P.SpawnY = 115, Format('the spawn point is y=%d, want 115 pixels',
                                [P.SpawnY]));
    Want(P.Progress[0] = 1, 'flag 0 is not set, so no 0000 guard would hold');
    Want(P.Head[ABILITY_DASH] = 0, 'a new game starts with the dash unlocked');
    { GameLevel 1 publishes itself as flag 5. }
    Want((P.Progress[5] = 1) and (P.Progress[6] = 0) and (P.Progress[10] = 0),
         'difficulty 1 did not publish itself as Progress[5]');

    { --- the two persistent unlocks ---------------------------------- }
    FreshSettings(0);
    GS := GS_TITLE_MENU;
    GameStartOrLoad(P, Cfg, smNewGame, H, True, SaveName, GS);
    Want((P.Progress[PROGRESS_EXTRA_DOOR_1] = 0)
         and (P.Progress[PROGRESS_EXTRA_DOOR_2] = 0),
         'the extra doors are open without the settings saying so');

    { ONE at a time. Setting both and checking both is symmetric, so swapping
      the two flag numbers is invisible to it - which is exactly what a
      mutation did. Each byte has to be shown to reach its own flag and not
      the other one. }
    FreshSettings(0);
    Cfg.ExtraDoor1 := 1;
    GS := GS_TITLE_MENU;
    GameStartOrLoad(P, Cfg, smNewGame, H, True, SaveName, GS);
    Want(P.Progress[1185] = 1,
         'settings +0x1C did not reach Progress[1185]');
    Want(P.Progress[1194] = 0,
         'settings +0x1C reached Progress[1194], which belongs to +0x1D');

    FreshSettings(0);
    Cfg.ExtraDoor2 := 1;
    GS := GS_TITLE_MENU;
    GameStartOrLoad(P, Cfg, smNewGame, H, True, SaveName, GS);
    Want(P.Progress[1194] = 1,
         'settings +0x1D did not reach Progress[1194]');
    Want(P.Progress[1185] = 0,
         'settings +0x1D reached Progress[1185], which belongs to +0x1C');

    { --- continue using a deterministic temporary save ------------------
      The game-owned save is reported for information only; assertions use a
      fixture built by this test. }
    if LoadSave(P, SaveName) then
      Log.Add(Format('data\save.dat is stage %d, music %d, difficulty %d '
        + '(read for information only)',
        [P.SavedStage, P.MusicTrack, P.Difficulty]))
    else
      Log.Add('  (no data\save.dat - it is not needed)');

    SavedStage := 42;
    SavedMusic := 7;
    SavedDiff  := 2;
    TempSave := GetTempDir(False) + 'akuji_selftest_continue.dat';
    FillChar(P, SizeOf(P), 0);
    P.SavedStage := SavedStage;
    P.MusicTrack := SavedMusic;
    P.Difficulty := SavedDiff;
    P.Lives := DEFAULT_LIVES;
    P.Head[ABILITY_DASH] := 1;
    if not SaveTo(P, TempSave) then
      Log.Add('  (could not write ' + TempSave + ' - the continue path is '
        + 'not exercised)')
    else
    begin
      H.Tracks := '';
      H.Fades := '';
      FreshSettings(0);
      GS := GS_TITLE_MENU;
      Want(GameStartOrLoad(P, Cfg, smContinue, H, True, TempSave, GS),
           'a continue with a readable save returned False');
      Want(Cfg.CurrentStage = SavedStage,
           Format('a continue went to stage %d, want the saved %d',
                  [Cfg.CurrentStage, SavedStage]));
      Want(P.MusicTrack = SavedMusic,
           Format('a continue plays track %d, want the saved %d',
                  [P.MusicTrack, SavedMusic]));
      Want(Trim(H.Tracks) = IntToStr(SavedMusic),
           'the continue played ' + H.Tracks);
      Want(Trim(H.Fades) = IntToStr(KBGM_STOP_HARD),
           'the continue stopped with fade "' + Trim(H.Fades) + '", want '
           + IntToStr(KBGM_STOP_HARD));
      Want(P.Head[ABILITY_DASH] = 1,
           'the continue did not restore the abilities in the save');
      Want(P.Progress[0] = 1, 'the continue left flag 0 clear');

      { WITH the archive - which is what the shipped game does - the loaded
        difficulty stands, even though the settings say 0. }
      Want(P.Difficulty = SavedDiff,
           Format('with the archive a continue kept difficulty %d, want the'
             + ' saved %d and not the settings 0', [P.Difficulty, SavedDiff]));

      { WITHOUT it the second write fires and the settings win. This is the
        anomaly in the header; it is dead in the shipped game and is asserted
        so that it stays reproduced rather than quietly dropped. }
      FreshSettings(0);
      GS := GS_TITLE_MENU;
      GameStartOrLoad(P, Cfg, smContinue, H, False, TempSave, GS);
      Want(P.Difficulty = 0,
           Format('without the archive a continue kept difficulty %d, want 0'
             + ' from the settings', [P.Difficulty]));
      { Difficulty 0 publishes itself as Progress[10], and the saved 2 would
        have published itself as Progress[6] - so this is what says the
        session flags were republished and not merely left. }
      Want((P.Progress[10] = 1) and (P.Progress[6] = 0),
           'the second difficulty write did not republish the session flags');
      DeleteFile(TempSave);
    end;

    { --- a continue against a save that DISAGREES with the defaults --- }
    { The shipped save happens to hold music track 1, which is also the track
      a new game starts on - so it cannot show whether a continue plays the
      SAVED track or the default one. A mutation that replaced the saved track
      with the default passed against it. Build a save that differs. }
    if LoadSave(P, SaveName) then
    begin
      TempSave := GetTempDir(False) + 'akuji_selftest_save.dat';
      P.SavedStage := 42;
      P.MusicTrack := 7;
      { Session flags that CONTRADICT the difficulty they are stored beside.
        A save cannot really be inconsistent, but the point of applying the
        flags after the load is that whatever the file says about 5, 6 and 10
        is overwritten - so the only way to see that happening is to make the
        file wrong. InitNewGame publishes them too, which is why the later
        call is invisible on the new-game path and this is the one place it
        can be caught at all. }
      P.Difficulty := 2;
      P.Progress[5]  := 1;
      P.Progress[6]  := 0;
      P.Progress[10] := 1;
      if not SaveTo(P, TempSave) then
        Log.Add('  (could not write ' + TempSave + ' - skipped)')
      else
      begin
        H.Tracks := '';
        H.Fades := '';
        FreshSettings(0);
        GS := GS_TITLE_MENU;
        GameStartOrLoad(P, Cfg, smContinue, H, True, TempSave, GS);
        Want(Cfg.CurrentStage = 42,
             Format('a continue went to stage %d, want the saved 42',
                    [Cfg.CurrentStage]));
        Want(P.MusicTrack = 7,
             Format('a continue kept music track %d, want the saved 7',
                    [P.MusicTrack]));
        Want(Trim(H.Tracks) = '7',
             'the continue played ' + H.Tracks + ', want the saved track 7');
        Want((P.Progress[6] = 1) and (P.Progress[5] = 0)
             and (P.Progress[10] = 0),
             Format('the session flags were not republished after the load:'
               + ' 5=%d 6=%d 10=%d, want 0/1/0 for the saved difficulty 2',
               [P.Progress[5], P.Progress[6], P.Progress[10]]));
        DeleteFile(TempSave);
      end;
    end;

    { --- a continue with no save at all ------------------------------ }
    H.Tracks := '';
    H.Fades := '';
    FreshSettings(0);
    GS := GS_TITLE_MENU;
    Want(GameStartOrLoad(P, Cfg, smContinue, H, True,
                         GameDir + PathDelim + 'no-such-save.dat', GS),
         'a continue with no save file returned False');
    Want(Cfg.CurrentStage = 1,
         Format('a failed load left stage %d, want a clean new game at 1',
                [Cfg.CurrentStage]));
    Want(P.Lives = DEFAULT_LIVES,
         'a failed load did not leave a playable new game');
    Want(P.Progress[0] = 1, 'a failed load left flag 0 clear');
    Want(Trim(H.Tracks) = '1',
         'a failed load played ' + H.Tracks + ', want the default track');
  finally
    H.Free;
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('OK - a continue is a new game with a file read over the top');
end;

{ The screen fade's TIMING, against 0x0044DC48 and 0x0044DC70.

  The counter starts at 0 for a fade out and 0x78 for a fade in, moves by the
  step the caller wrote to +0x10 - always 4 - and the busy flag clears when the
  level goes STRICTLY outside 0..0x78. That last detail is why the count is 31
  and not 30: the level reaches 0x78 on tick 30 and is still busy, because the
  test is `> 0x78`, and only tick 31 pushes it to 124 and ends it.

  Clamping the level at the boundary, which is the obvious way to write this,
  ends every fade one frame early. }
function TestFade(Log: TStrings): Integer;
var
  D: TDDDD;
  Ticks: Integer;

  function RunFade(FadeOut: Boolean): Integer;
  begin
    D.StartFade(0, FadeOut);
    Result := 0;
    while D.FadeBusy and (Result < 1000) do
    begin
      D.TickFade;
      Inc(Result);
    end;
  end;

begin
  Result := 0;
  D := TDDDD.Create(nil);
  try
    Ticks := RunFade(True);
    if Ticks <> FADE_TICKS then
    begin
      Log.Add(Format('FAILED: a fade OUT took %d ticks, want %d',
                     [Ticks, FADE_TICKS]));
      Inc(Result);
    end;
    Ticks := RunFade(False);
    if Ticks <> FADE_TICKS then
    begin
      Log.Add(Format('FAILED: a fade IN took %d ticks, want %d',
                     [Ticks, FADE_TICKS]));
      Inc(Result);
    end;
    { And the direction: out starts clear, in starts covered. }
    D.StartFade(0, True);
    if D.FadeLevel <> 0 then
    begin
      Log.Add(Format('FAILED: a fade OUT starts at level %d, want 0',
                     [D.FadeLevel]));
      Inc(Result);
    end;
    D.StartFade(0, False);
    if D.FadeLevel <> FADE_FULL then
    begin
      Log.Add(Format('FAILED: a fade IN starts at level %d, want %d',
                     [D.FadeLevel, FADE_FULL]));
      Inc(Result);
    end;
    if Result = 0 then
      Log.Add(Format('  fade: %d ticks each way, out from 0, in from %d',
                     [FADE_TICKS, FADE_FULL]));
  finally
    D.Free;
  end;
end;

{ The frame clock's RESOLUTION, which is what the frame rate actually rests on.

  The limiter proceeds when the elapsed time reaches FRAME_MS, so the clock's
  step size is the frame rate's floor. GetTickCount64 steps 15-16 ms on Windows,
  which put the game at 40 fps against the original's 62; timeGetTime steps 1 ms
  once the multimedia timer period is raised.

  Measured, not asserted about: the tolerance is deliberately loose - anything
  at or under 5 ms passes - because the point is to tell a 1 ms clock from a
  15.6 ms one, and a loaded machine must not make that a flaky test. }
function TestFrameClock(Log: TStrings): Integer;
var
  A, B, Step, Worst, Seen: DWord;
  Guard: Integer;
begin
  Result := 0;
  BeginFrameClock;
  try
    Worst := 0;
    Seen := 0;
    Guard := 0;
    A := FrameClockMs;
    while (Seen < 8) and (Guard < 20000000) do
    begin
      B := FrameClockMs;
      if B <> A then
      begin
        Step := B - A;
        if Step > Worst then
          Worst := Step;
        A := B;
        Inc(Seen);
      end;
      Inc(Guard);
    end;
    if Seen < 8 then
    begin
      Log.Add('FAILED: the frame clock did not advance - it cannot pace a '
        + 'frame loop at all');
      Inc(Result);
    end
    else if Worst > FRAME_CLOCK_MAX_STEP_MS then
    begin
      Log.Add(Format('FAILED: the frame clock steps %d ms at worst. That is '
        + 'the GetTickCount64 granularity, and it holds the game to about '
        + '40 fps where the original runs at 62', [Worst]));
      Inc(Result);
    end
    else
      Log.Add(Format('  frame clock steps %d ms at worst over %d samples',
                     [Worst, Seen]));
  finally
    EndFrameClock;
  end;
end;

{ Verify the outlined-text font against the ShortString stored in akuji.exe. }
function TestOutlinedFontName(Log: TStrings; const GameDir: string): Integer;
var
  F: TFileStream;
  Buf: TBytes;
  Path, Found: string;
  I, N: Integer;

  function HasShortString(const Want: string): Boolean;
  var
    K, J: Integer;
  begin
    Result := False;
    for K := 0 to N - Length(Want) - 2 do
      if (Buf[K] = Byte(Length(Want))) then
      begin
        for J := 1 to Length(Want) do
          if Char(Buf[K + J]) <> Want[J] then
            Break
          else if J = Length(Want) then
            Exit(True);
      end;
  end;

  function HasText(const Want: string): Boolean;
  var
    K, J: Integer;
  begin
    Result := False;
    for K := 0 to N - Length(Want) - 1 do
    begin
      for J := 1 to Length(Want) do
        if Char(Buf[K + J - 1]) <> Want[J] then
          Break
        else if J = Length(Want) then
          Exit(True);
    end;
  end;

begin
  Result := 0;
  Path := OriginalExe(GameDir);
  if not FileExists(Path) then
  begin
    Log.Add('FAILED: no akuji.exe to pin the font name against');
    Exit(1);
  end;
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    N := F.Size;
    SetLength(Buf, N);
    F.ReadBuffer(Buf[0], N);
  finally
    F.Free;
  end;

  if not HasShortString(OUTLINED_FONT_NAME) then
  begin
    Log.Add(Format('FAILED: %s is not a ShortString in akuji.exe',
                   [OUTLINED_FONT_NAME]));
    Inc(Result);
  end;
  if HasText('Arial') then
  begin
    Log.Add('FAILED: Arial IS in the binary after all - re-read '
      + 'Game_DrawTextOutlined before trusting the note beside it');
    Inc(Result);
  end;
  if Result = 0 then
  begin
    Found := OUTLINED_FONT_NAME;
    Log.Add(Format('  outlined text draws in "%s", size %d; no Arial in the '
      + 'image', [Found, OUTLINED_FONT_SIZE]));
  end;
  I := 0; { silence the unused-variable hint }
  if I <> 0 then Exit;
end;

{ The opening cutscene's timing, pinned to a captured game session:

      slide 1..7   480 frames each     8 seconds
      slide 8      120 frames          2 seconds
      slide 9      480 frames          8 seconds
      slide 10     765 frames          waits on the music, not the timer

  TOpeningScreen must reproduce these counts under the same input and music
  conditions. }
function TestOpeningTiming(Log: TStrings): Integer;
var
  Op: TOpeningScreen;
  Frames, Slide, Held, I: Integer;
  MusicOn, Running: Boolean;
  Counts: array[1..OPENING_SLIDES] of Integer;
begin
  Result := 0;
  for I := 1 to OPENING_SLIDES do
    Counts[I] := 0;

  Op := TOpeningScreen.Create;
  try
    Op.Reset;
    Slide := 0;
    Held := 0;
    Frames := 0;
    { The music runs under slides 9 and 10 and is what ends slide 10. Modelled
      as "still playing for 765 frames after slide 10 begins", which is what the
      trace measured. }
    MusicOn := True;
    Running := True;
    while Running and (Frames < 20000) do
    begin
      if (Op.Slide = OPENING_SLIDES) and (Held >= 765) then
        MusicOn := False;
      Running := Op.Update(False, MusicOn, False);
      Inc(Frames);
      if Op.Slide <> Slide then
      begin
        if (Slide >= 1) and (Slide <= OPENING_SLIDES) then
          Counts[Slide] := Held;
        Slide := Op.Slide;
        Held := 0;
      end;
      Inc(Held);
    end;
    if (Slide >= 1) and (Slide <= OPENING_SLIDES) and (Counts[Slide] = 0) then
      Counts[Slide] := Held;

    for I := 1 to OPENING_SLIDES do
    begin
      if I = 8 then
      begin
        if Counts[I] <> 120 then
        begin
          Log.Add(Format('FAILED: slide 8 held %d frames, the game held 120',
                         [Counts[I]]));
          Inc(Result);
        end;
      end
      else if I = OPENING_SLIDES then
      begin
        if Counts[I] < 700 then
        begin
          Log.Add(Format('FAILED: slide 10 held %d frames - it should wait on '
            + 'the music, which the trace had running for 765', [Counts[I]]));
          Inc(Result);
        end;
      end
      else if Counts[I] <> 480 then
      begin
        Log.Add(Format('FAILED: slide %d held %d frames, the game held 480',
                       [I, Counts[I]]));
        Inc(Result);
      end;
    end;
    if Result = 0 then
      Log.Add(Format('  opening: ten slides in %d frames, every hold matching '
        + 'the traced game', [Frames]));
  finally
    Op.Free;
  end;
end;

{ Check PixelOf and OriginPixel across the sign boundary. POSITION_ROUND is
  untyped, so FPC widens the subtraction before shifting; changing its type or
  hoisting the expression could alter negative-coordinate rounding. }
function TestPixelConversion(Log: TStrings): Integer;
var
  Offset, Want, GotPx, GotOrigin: Integer;
  Bad: Integer;

  { Add the negative correction before the arithmetic shift to model integer
    division truncated toward zero without restating the implementation. }
  function OriginalIdiom(V: Integer): Integer;
  begin
    if V < 0 then
      Result := SarLongint(V + ((1 shl POSITION_SHIFT) - 1), POSITION_SHIFT)
    else
      Result := SarLongint(V, POSITION_SHIFT);
  end;

begin
  Result := 0;
  Bad := 0;
  Offset := -4096;
  while Offset <= 4096 do
  begin
    Want := OriginalIdiom(Offset);
    GotPx := PixelOf(Offset + POSITION_BIAS);
    GotOrigin := OriginPixel(Offset);
    if (GotPx <> Want) or (GotOrigin <> Want) then
    begin
      if Bad < 6 then
        Log.Add(Format('  offset %d: original %d, PixelOf %d, OriginPixel %d',
                       [Offset, Want, GotPx, GotOrigin]));
      Inc(Bad);
    end;
    Inc(Offset);
  end;
  if Bad > 0 then
  begin
    Log.Add(Format('FAILED: %d of 8193 pixel conversions disagree with the '
      + 'original idiom', [Bad]));
    Inc(Result, 1);
  end
  else
    Log.Add('  pixel conversion matches across 8193 offsets, both signs');
end;

function SelfTestPlayer(Log: TStrings): Integer;
var
  GameDir: string;
  SavePath: string;
  M: TTileMap;
  L: TLayerInfo;
  P: TPlayerState;
  I, J, K, V, Step, Before, Bad, Checked: Integer;
  Want, Got, Overlaps, SndId: Integer;
  Nm: string;
  Exe: TMemoryStream;
  ExeName: string;
  Table: array of Integer;
  A, B: Entities.TBox;
  RefOverlap, GotOverlap, Scroll, RefScroll: Boolean;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');

  { --- 1. the scroll clamp, against every shipped map --------------------- }
  Bad := 0; Checked := 0;
  M := TTileMap.Create;
  try
    for I := 1 to 65 do
    begin
      if not M.Load(GameDir, I) then
        Continue;
      Inc(Checked);
      FillChar(L, SizeOf(L), 0);
      L.TileW := M.TileWidth;    L.TileH := M.TileHeight;
      L.MapTilesX := M.MapWidth; L.MapTilesY := M.MapHeight;

      Want := M.MapWidth * M.TileWidth - SCREEN_W;
      Got := Camera.MaxScrollX(L);
      if Got <> Want then
      begin
        Inc(Bad);
        if Bad <= 5 then
          Log.Add(Format('  map %.3d: max scroll X %d, expected %d',
            [I, Got, Want]));
      end;
      Want := M.MapHeight * M.TileHeight - SCREEN_H;
      Got := Camera.MaxScrollY(L);
      if Got <> Want then
      begin
        Inc(Bad);
        if Bad <= 5 then
          Log.Add(Format('  map %.3d: max scroll Y %d, expected %d',
            [I, Got, Want]));
      end;
    end;
  finally
    M.Free;
  end;
  Log.Add(Format('scroll clamp = map size - screen size:   %d maps, %d mismatches',
    [Checked, Bad]));
  Inc(Result, Bad);
  if Checked <> 65 then
  begin
    Log.Add(Format('FAILED: expected 65 maps, read %d - wrong game directory?',
      [Checked]));
    Inc(Result);
  end;

  { --- 2. the dead zone ---------------------------------------------------
    A map big enough that the bounds check never fires, so this isolates the
    zone itself. }
  { A layer origin ALWAYS carries POSITION_BIAS - Stage_Begin writes
    ScrollX * 0x20 + 0x10000 - and Camera_ShouldScroll* subtracts it back off
    with the -0x10000 / -0xFFE1 pair. These fixtures used bare pixel values,
    which only worked while the Pascal used the non-subtracting conversion.
    Biasing them is not a test change to suit the code: it is the fixture
    being made to look like a layer the game could actually produce. }
  FillChar(L, SizeOf(L), 0);
  L.TileW := 32; L.TileH := 32; L.MapTilesX := 1000; L.MapTilesY := 1000;
  L.OriginX := (200 shl POSITION_SHIFT) + POSITION_BIAS;
  L.OriginY := (200 shl POSITION_SHIFT) + POSITION_BIAS;
  Bad := 0;
  for I := 0 to SCREEN_W - 1 do
    for J := 0 to 1 do
    begin
      V := 32 - 64 * J;
      Scroll := Camera.ShouldScrollX(L, I, V);
      RefScroll := ((I < 144) and (V < 0)) or ((I >= 177) and (V > 0));
      if Scroll <> RefScroll then Inc(Bad);
    end;
  for I := 0 to SCREEN_H - 1 do
    for J := 0 to 1 do
    begin
      V := 32 - 64 * J;
      Scroll := Camera.ShouldScrollY(L, I, V);
      RefScroll := ((I < 104) and (V < 0)) or ((I >= 137) and (V > 0));
      if Scroll <> RefScroll then Inc(Bad);
    end;
  Log.Add(Format('dead zone over every screen pixel:      %d disagreements',
    [Bad]));
  Inc(Result, Bad);

  Bad := 0;
  for I := 0 to SCREEN_W - 1 do
    if Camera.ShouldScrollX(L, I, 0) then Inc(Bad);
  for I := 0 to SCREEN_H - 1 do
    if Camera.ShouldScrollY(L, I, 0) then Inc(Bad);
  Log.Add(Format('a still entity never scrolls:           %d violations', [Bad]));
  Inc(Result, Bad);

  L.OriginX := (Camera.MaxScrollX(L) shl POSITION_SHIFT) + POSITION_BIAS;
  L.OriginY := (Camera.MaxScrollY(L) shl POSITION_SHIFT) + POSITION_BIAS;
  if Camera.ShouldScrollX(L, SCREEN_W - 1, 32) or
     Camera.ShouldScrollY(L, SCREEN_H - 1, 32) then
  begin
    Log.Add('FAILED: the layer scrolls past the edge of the map');
    Inc(Result);
  end
  else
    Log.Add('the clamp stops the layer at the map edge: yes');

  { --- 3a. ApproachZero --------------------------------------------------- }
  Bad := 0; Checked := 0;
  for V := -600 to 600 do
    for Step := 1 to 16 do
    begin
      Before := V;
      I := V;
      Entities.ApproachZero(I, Step);
      Inc(Checked);
      if (Before > 0) and ((I < 0) or (I > Before)) then Inc(Bad);
      if (Before < 0) and ((I > 0) or (I < Before)) then Inc(Bad);
      if (Before = 0) and (I <> 0) then Inc(Bad);
      if Abs(I) > Abs(Before) then Inc(Bad);
      if (Before <> 0) and (I = Before) then Inc(Bad);
    end;
  Log.Add(Format('ApproachZero over %d cases:          %d violations',
    [Checked, Bad]));
  Inc(Result, Bad);

  { --- 3b. RectOverlap against brute force -------------------------------- }
  Bad := 0; Checked := 0; Overlaps := 0;
  for I := 0 to 19 do
    for J := 0 to 19 do
      for K := 0 to 3 do
      begin
        A.L := 0;  A.T := 0;  A.R := 10 + K;  A.B := 10 + K;
        B.L := I - 10; B.T := J - 10; B.R := B.L + 8; B.B := B.T + 8;
        RefOverlap := (A.L < B.R) and (B.L < A.R) and
                      (A.T < B.B) and (B.T < A.B);
        GotOverlap := Entities.RectOverlap(A, B, 0, 0);
        Inc(Checked);
        if GotOverlap <> RefOverlap then Inc(Bad);
        if RefOverlap then Inc(Overlaps);
      end;
  Log.Add(Format('RectOverlap over %d box pairs:       %d disagreements, %d overlapping',
    [Checked, Bad, Overlaps]));
  Inc(Result, Bad);
  if (Overlaps = 0) or (Overlaps = Checked) then
  begin
    Log.Add('FAILED: the box grid is degenerate - the comparison proves nothing');
    Inc(Result);
  end;

  { --- 4. sprite tables read directly from akuji.exe -----------------------
    Reading the contiguous 20-dword region independently checks table values,
    addresses, stride, and facing order. }
  Bad := 0;
  Exe := TMemoryStream.Create;
  try
    ExeName := OriginalExe(GameDir);
    if not FileExists(ExeName) then
    begin
      Log.Add('FAILED: akuji.exe is not in the game directory');
      Inc(Result);
    end
    else
    begin
      Exe.LoadFromFile(ExeName);
      SetLength(Table, 20);
      Exe.Position := PLAYER_SPRITE_BASE - DATA_VA_BIAS;
      Exe.ReadBuffer(Table[0], 20 * SizeOf(Integer));

      for I := 0 to 4 do
      begin
        if Table[I]      <> SPR_GROUND[0][I] then Inc(Bad);
        if Table[5 + I]  <> SPR_GROUND[1][I] then Inc(Bad);
        if Table[10 + I] <> SPR_AIR[0][I]    then Inc(Bad);
        if Table[15 + I] <> SPR_AIR[1][I]    then Inc(Bad);
      end;
      Log.Add(Format('sprite tables match akuji.exe at 0x%.6X:   %d of 20 wrong',
        [PLAYER_SPRITE_BASE, Bad]));
      Inc(Result, Bad);

      { And the three later tables, at the addresses this file claims. }
      Bad := 0;
      SetLength(Table, 8);
      Exe.Position := $0046BBEC - DATA_VA_BIAS;
      Exe.ReadBuffer(Table[0], 8 * SizeOf(Integer));
      for I := 0 to 3 do
      begin
        if Table[I]     <> SPR_GLIDE[0][I] then Inc(Bad);
        if Table[4 + I] <> SPR_GLIDE[1][I] then Inc(Bad);
      end;
      SetLength(Table, 6);
      Exe.Position := $0046BC0C - DATA_VA_BIAS;
      Exe.ReadBuffer(Table[0], 6 * SizeOf(Integer));
      if (Table[0] <> SPR_AIRDASH[0][0]) or (Table[1] <> SPR_AIRDASH[0][1]) or
         (Table[2] <> SPR_AIRDASH[1][0]) or (Table[3] <> SPR_AIRDASH[1][1]) or
         (Table[4] <> SPR_KNOCKBACK[0])  or (Table[5] <> SPR_KNOCKBACK[1]) then
        Inc(Bad);
      Log.Add(Format('glide, air dash and knockback tables:      %d wrong', [Bad]));
      Inc(Result, Bad);

      { Type 14's item table, 16 variants x 4 frames, read back the same way. }
      Bad := 0;
      SetLength(Table, MANA_VARIANTS * MANA_FRAMES);
      Exe.Position := MANA_SPRITE_TABLE_ADDR - DATA_VA_BIAS;
      Exe.ReadBuffer(Table[0], MANA_VARIANTS * MANA_FRAMES * SizeOf(Integer));
      for I := 0 to MANA_VARIANTS - 1 do
        for J := 0 to MANA_FRAMES - 1 do
          if Table[I * MANA_FRAMES + J] <> MANA_SPRITES[I][J] then
            Inc(Bad);
      Log.Add(Format('type 14 item table at 0x%.6X:            %d of %d wrong',
        [MANA_SPRITE_TABLE_ADDR, Bad, MANA_VARIANTS * MANA_FRAMES]));
      Inc(Result, Bad);
    end;
  finally
    Exe.Free;
  end;

  { The +10 relation between the two facings of the base character set. It is
    what fixes the index order as right-then-left rather than the reverse. }
  Bad := 0;
  for I := 0 to 2 do
    if SPR_GROUND[0][I] - SPR_GROUND[1][I] <> SPRITE_FACING_STRIDE then Inc(Bad);
  for I := 0 to 4 do
    if SPR_AIR[0][I] - SPR_AIR[1][I] <> SPRITE_FACING_STRIDE then Inc(Bad);
  if SPR_KNOCKBACK[0] - SPR_KNOCKBACK[1] <> SPRITE_FACING_STRIDE then Inc(Bad);
  if SPR_DEATH[0] - SPR_DEATH[1] <> SPRITE_FACING_STRIDE then Inc(Bad);
  Log.Add(Format('right sprite = left + 10 in the base set: %d violations', [Bad]));
  Inc(Result, Bad);


  { --- sound constants agree with the executable's file-name table -------- }
  Bad := 0;
  for I := 0 to 12 do
  begin
    case I of
      0: begin SndId := SND_JUMP;        Nm := 'jump';    end;
      1: begin SndId := SND_LAND_HARD;   Nm := 'yuka';    end;
      2: begin SndId := SND_ATTACK;      Nm := 'shot';    end;
      3: begin SndId := SND_CHARGE_FULL; Nm := 'power';   end;
      4: begin SndId := SND_CHARGED;     Nm := 'shot';    end;
      5: begin SndId := SND_LAND_SOFT;   Nm := 'yuka';    end;
      6: begin SndId := SND_GLIDE;       Nm := 'pon';     end;
      7: begin SndId := SND_AIRDASH;     Nm := 'pon';     end;
      8: begin SndId := SND_DEATH;       Nm := 'voice';   end;
      9: begin SndId := SND_DASH_START;  Nm := 'puu';     end;
     10: begin SndId := SND_BOM03;       Nm := 'bom03';   end;
     11: begin SndId := 17;              Nm := 'hit01';   end;
    else begin SndId := $10;             Nm := 'get01';   end;
    end;
    if (SndId < 0) or (SndId >= SOUND_COUNT) or (Pos(Nm, SoundNames[SndId]) = 0) then
    begin
      Log.Add(Format('  sound %d is %s, expected a name containing "%s"',
        [SndId, SoundNames[SndId], Nm]));
      Inc(Bad);
    end;
  end;
  Log.Add(Format('sound constants match their recovered names: %d wrong of 13',
    [Bad]));
  Inc(Result, Bad);

  { --- 5. immutable shipped-save fixture ----------------------------------
    Never use <game>/data/save.dat because normal play overwrites it. A missing
    fixture skips this evidence check; tests/fixtures/README.md explains how to
    restore it. }
  SavePath := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests'
              + PathDelim + 'fixtures' + PathDelim + 'save.dat';
  if not FileExists(SavePath) then
  begin
    Log.Add('');
    Log.Add('SKIP: the pinned save fixture is missing - see '
      + 'tests/fixtures/README.md. Restore data/save.dat from a fresh copy '
      + 'of the English release; the copy in the game directory is written '
      + 'over whenever the game saves.');
  end
  else if LoadSave(P, SavePath) then
  begin
    Log.Add('');
    Log.Add(Format('save.dat: stage %d, lives %d/%d, %ds, weapon %d, jump %d',
      [P.SavedStage, P.Lives, P.MaxLives, P.ElapsedSec, P.Weapon,
       P.JumpStrength]));
    Log.Add(Format('  abilities: dash %d, wall kick %d, air dash %d, glide %d',
      [P.Head[ABILITY_DASH], P.Head[ABILITY_WALLKICK],
       P.Head[ABILITY_AIRDASH], P.Head[ABILITY_GLIDE]]));
    { Pinned exactly. The claim is that these four bytes are the abilities and
      that this save is early enough to have only the first. If the file is
      ever replaced these numbers change and the reading has to be redone
      rather than quietly adjusted.

      PROVENANCE: the file distributed with the English release was lost on
      2026-08-30, overwritten by a playtest before anything tracked it. What
      sits in tests/fixtures now is a real game-written early save supplied on
      2026-08-31 - stage 2, 46 seconds, the starting jump and weapon, and the
      dash alone - which is the same shape and is equally good evidence that
      LoadSave reads the real format, because the game wrote it. It is NOT
      claimed to be the shipped bytes, and nothing here should say it is. }
    if (P.Head[ABILITY_DASH] <> 1) or (P.Head[ABILITY_WALLKICK] <> 0) or
       (P.Head[ABILITY_AIRDASH] <> 0) or (P.Head[ABILITY_GLIDE] <> 0) then
    begin
      Log.Add('FAILED: the save fixture no longer has exactly the dash unlocked');
      Inc(Result);
    end;
    if P.Progress[0] <> 1 then
    begin
      Log.Add('FAILED: progress flag 0 is not set - guard 0000 is not always true');
      Inc(Result);
    end;
    if P.Lives > P.MaxLives then
    begin
      Log.Add('FAILED: lives exceed the maximum');
      Inc(Result);
    end;
    if P.JumpStrength < DEFAULT_JUMP_STRENGTH then
    begin
      Log.Add('FAILED: jump strength is below the starting value');
      Inc(Result);
    end;
  end
  else
  begin
    Log.Add('FAILED: the save fixture is present and could not be read');
    Inc(Result);
  end;

  Inc(Result, TestGameStart(Log, GameDir));
  Inc(Result, TestStageBegin(Log));
  Inc(Result, TestPixelConversion(Log));
  Inc(Result, TestOpeningTiming(Log));
  Inc(Result, TestOutlinedFontName(Log, GameDir));
  Inc(Result, TestFrameClock(Log));
  Inc(Result, TestFade(Log));

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - the camera, the helpers and the player tables all hold')
  else
    Log.Add('FAILED');
end;

end.
