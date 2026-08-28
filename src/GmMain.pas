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
  QdaArchive, Title, GameFont, Surfaces, Sprites, Stages, TileMaps, PlayerState,
  Entities, GameSession, SpritePool, Dialogue;

type
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
    FStartHost: TStartHost;
    { The message box. It is the session's TEventHost, so sub-op 3 reaches it
      directly - and closing it is what advances the script, exactly as
      FUN_004568D0 does. Without one, reading a sign locked the game. }
    FDialogue: TDialogueBox;
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
    procedure DispatchState;
    procedure FormPaint(Sender: TObject);
    procedure DrawScene;
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
  { TODO: read system.ini -> input device, fullscreen }
  { TODO: init input, sprite engine }

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

    { The running game. It borrows the stage table and the map; the form keeps
      owning both, and the surfaces and sprite sheets with them. }
    FSession := TGameSession.Create(DataDir, FStages, FMap);
    { Game_StartOrLoad's presentation hooks. The base class does nothing,
      which is right until Opening_Update and the playlist are translated -
      an opening that never runs is a cutscene that finishes instantly, and
      that is a truthful stub rather than a skipped step. }
    FStartHost := TStartHost.Create;
    FDialogue := TDialogueBox.Create;
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
procedure TFrm_main.DispatchState;
var
  Mode: TStartMode;
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
        { Stage_Begin @ 0x00462210. The ASSETS are the form's - it owns the
          surfaces and the sprite sheets - and everything after them is the
          session's: terrain, events, camera, and the player entity. The
          order is the original's and it matters, because the session reads
          the map and the frames the load has just replaced. }
        LoadStage(Settings.CurrentStage);
        FSession.SetFrames(FSprites);
        FSession.BeginStage(Settings.CurrentStage, GameStateValue);
        FDialogue.Bind(FSession.Events, FSession.Runner, @FSession.Player);
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
    GS_PLAY,
    GS_PLAY_ALT,
    GS_STATE_140:
      begin
        { While the box is up it - not the interpreter - drives the script,
          and no game logic steps. That is the original's shape: sub-op 3
          waits, and FUN_004568D0 is what calls EventScript_AdvanceStep. }
        if FDialogue.Active then
          FDialogue.Update(FSession.Input.Button[0] and not FConfirmLatch,
                           FSession.Input.AxisY < 0, FSession.Input.AxisY > 0,
                           GameStateValue)
        else
          FSession.Frame(GameStateValue);
        DrawScene;
      end;
    GS_PAUSE:
      { PauseMenu_Update @ 0x00461EE4 is not translated. What IS wrong to do
        is nothing at all: the frame is cleared at the top of every AppIdle,
        so a state that paints nothing leaves a black screen - which is what
        pausing looked like. Redraw the frozen scene and step no logic. }
      DrawScene;
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

  { DIVERGENCE, not part of the original handler. The original reads movement
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
  Application.OnIdle := nil;
  if FDataDir <> '' then
    SaveSettings(FDataDir);
  FFont.Free;
  FTitleScreen.Free;
  { FDialogue is the session's EventHost, and the session does not own it. }
  FSession.Free;
  FDialogue.Free;
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
