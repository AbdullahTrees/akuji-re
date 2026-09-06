{ Self-tests that drive a whole session: dialogue, pausing, the game-over
  path, continuing from a save, and the ending. }

unit SessionTests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, TypInfo,
  QdaArchive, SoundTable, WaveFile, AudioMixer, AudioOut, MidiFile, KbgmPlayer,
  Directions, Entities, EventScripts, EventCommands, PlayerState, GameState,
  Stages, Camera, TileMaps, Player, EntityHandlers, EventRunner, GameSession,
  SpritePool, Sprites, Dialogue, BgAnime, UnitInit, Title, Ending, Opening,
  GameFont, DDDDComponent, Surfaces,
  Graphics;

function SelfTestSession(Log: TStrings): Integer;

implementation

uses
  TestSupport, EntityTests;

{ --selftest-session runs integrated frames using shipped stage, map, and event
  data. Sound and sprite backends are omitted; gameplay dispatch is real. }

{ The message box's page splitting, against the shipped text.

  Sub-op 3 waits for the dialogue box to advance the script. This test checks
  page splitting against every shipped text line without requiring a screen. }
function TestDialogue(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  Page, Rest, Src: string;
  Prompt: Boolean;
  P2: TPlayerState;
  I, J, Bad, Lines, Prompts, Pages, MaxPages, N: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Lines := 0; Prompts := 0; Pages := 0; MaxPages := 0;
  Log.Add('');
  Log.Add('--- the message box ---');

  { --- yes/no answers are represented by two mutually exclusive flags --- }
  begin
    FillChar(P2, SizeOf(P2), 0);
    P2.Progress[MB_ANSWER_YES] := 9;   { junk, to prove both are WRITTEN }
    P2.Progress[MB_ANSWER_NO] := 9;
    DialogueAnswer(P2, 0);
    Want(P2.Progress[MB_ANSWER_YES] = 1, 'Yes did not set Progress[3]');
    Want(P2.Progress[MB_ANSWER_NO] = 0, 'Yes did not clear Progress[4]');

    DialogueAnswer(P2, 1);
    Want(P2.Progress[MB_ANSWER_YES] = 0, 'No did not clear Progress[3]');
    Want(P2.Progress[MB_ANSWER_NO] = 1, 'No did not set Progress[4]');
  end;

  { --- PowerUp_Show's grant table, from 0x00456698 ------------------- }
  { The weapon's two guards are the only conditional part, and they are the
    part a tidy rewrite would lose: picking up Fire after Charge must not
    demote you. Each is checked in both directions. }
  begin
    FillChar(P2, SizeOf(P2), 0);
    PowerUpGrant(P2, 0);
    Want(P2.Weapon = 1, 'variant 0 did not give weapon 1 from nothing');
    PowerUpGrant(P2, 0);
    Want(P2.Weapon = 1, 'variant 0 re-applied over an existing weapon');
    PowerUpGrant(P2, 1);
    Want(P2.Weapon = 2, 'variant 1 did not raise the weapon to 2');
    PowerUpGrant(P2, 2);
    Want(P2.Weapon = 3, 'variant 2 did not give weapon 3');
    PowerUpGrant(P2, 0);
    Want(P2.Weapon = 3, 'Fire after Charge demoted the weapon');
    PowerUpGrant(P2, 1);
    Want(P2.Weapon = 3, 'Fire+ after Charge demoted the weapon');

    { ...but variant 1 refuses only the value 3, so Fire+ over Fire+ DOES
      re-apply. Not the same function as max(), and pinned so it stays. }
    FillChar(P2, SizeOf(P2), 0);
    P2.Weapon := 2;
    PowerUpGrant(P2, 1);
    Want(P2.Weapon = 2, 'Fire+ over Fire+ did not stay at 2');

    FillChar(P2, SizeOf(P2), 0);
    P2.JumpStrength := DEFAULT_JUMP_STRENGTH;
    PowerUpGrant(P2, 3);
    Want(P2.JumpStrength = $84,
         Format('variant 3 left the jump at %d, want $84',
                [P2.JumpStrength]));

    for I := ABILITY_DASH to ABILITY_GLIDE do
    begin
      FillChar(P2, SizeOf(P2), 0);
      PowerUpGrant(P2, I);
      Want(P2.Head[I] = 1,
           Format('variant %d did not set Head[%d]', [I, I]));
      Want(P2.Weapon = 0,
           Format('variant %d touched the weapon', [I]));
    end;

    { Stage 1's pickup is 0024-A-0004, and 4 is the dash. }
    Want(PowerUpName(4) = 'Dash    ',
         'variant 4 is not the dash: ' + PowerUpName(4));
    Want(PowerUpName(9) = '', 'a variant past the table returned a name');
  end;

  { The four codes, on text taken straight out of tk002. }
  Page := SplitPage('Will you save the game? \w', Rest, Prompt);
  Want(Prompt, 'a \w line did not raise the prompt');
  Want(Trim(Page) = 'Will you save the game?',
       'the prompt page came out as "' + Page + '"');

  Page := SplitPage('Saving completed! \e', Rest, Prompt);
  Want(not Prompt, 'a \e line raised a prompt');
  Want(Rest = '', 'a \e line left something after it: "' + Rest + '"');

  Page := SplitPage('Touching a Devil Statue can \nsave your game. \kYou may '
                    + 'want to save now. \e', Rest, Prompt);
  Want(Pos('\k', Page) = 0, 'the page kept its own \k');
  Want(Pos('You may', Rest) > 0,
       'a \k line did not leave the next page behind: "' + Rest + '"');

  { And every line in every shipped tk file must split without looping. A
    page that produced no progress would hang the box the same way the
    missing box hung the script. }
  S := TEventScript.Create;
  try
    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for J := 0 to S.LineCount - 1 do
      begin
        Inc(Lines);
        Src := S.Lines[J];
        N := 0;
        repeat
          { Src and Rest must be DIFFERENT variables - SplitPage clears its
            out parameter on entry, and aliasing them blanks the input before
            it is read. That is not hypothetical: it is the bug this sweep
            found in TDialogueBox.TakePage. }
          Page := SplitPage(Src, Rest, Prompt);
          Src := Rest;
          Inc(N);
          Inc(Pages);
          if Prompt then
            Inc(Prompts);
        until (Src = '') or (N > 32);
        if N > 32 then
        begin
          Log.Add(Format('  stage %d line %d never finished splitting: %s',
            [I, J, S.Lines[J]]));
          Inc(Bad);
        end;
        if N > MaxPages then
          MaxPages := N;
      end;
    end;
  finally
    S.Free;
  end;

  Log.Add(Format('tk lines split: %d into %d pages, longest %d, %d prompts',
    [Lines, Pages, MaxPages, Prompts]));

  { Pinned so a splitter that returned nothing could not pass vacuously. The
    44 prompts are the same 44 EventRunner.pas counts from the other side -
    the \w lines that its scratch-flag guards depend on. }
  { The shipped totals, counted independently: 66 tk files, 203 lines, 63 of
    them carrying \w and 52 carrying \k. Pinned so a splitter that returned
    nothing could not pass by comparing nothing - which is exactly what it did
    on the first run, when the sweep aliased its own input and every line came
    back empty. }
  if Lines <> 203 then
  begin
    Log.Add(Format('  FAILED: %d tk lines, want 203 - wrong game directory?',
      [Lines]));
    Inc(Bad);
  end;
  if Prompts <> 63 then
  begin
    Log.Add(Format('  FAILED: %d prompt pages, want the 63 lines carrying \w',
      [Prompts]));
    Inc(Bad);
  end;
  if MaxPages < 2 then
  begin
    Log.Add('  FAILED: no line split into more than one page, but 52 carry \k');
    Inc(Bad);
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('OK - every shipped line splits into pages and terminates');
end;

type
  { Counts the three things GameOver_Update asks its host to do. It does NOT
    override anything the screen itself decides - a double that answers the
    question under test only tests the double. }
  TGameOverProbe = class
  public
    Restarts, Fades, Tunes: Integer;
    { Starting a track makes it play - that is the point of the fix, so the
      double has to model it rather than hold a constant. }
    Playing: Boolean;
    procedure Restart;
    procedure Fade(FadeIn: Boolean);
    procedure Music(Track: Integer);
    function  IsPlaying: Boolean;
  end;

procedure TGameOverProbe.Restart;
begin Inc(Restarts); end;
procedure TGameOverProbe.Fade(FadeIn: Boolean);
begin Inc(Fades); end;
procedure TGameOverProbe.Music(Track: Integer);
begin
  Inc(Tunes);
  if Track <> GAMEOVER_MIDI then Tunes := -1000;
  Playing := True;
end;

function TGameOverProbe.IsPlaying: Boolean;
begin Result := Playing; end;

{ Input_ConfirmPressed @ 0x00466E4C and GameOver_Update @ 0x00461A44.
  Confirm is a rising edge on either action button. }
function TestConfirmAndGameOver(Log: TStrings): Integer;
var
  Inp: TInputState;
  G: TGameOverScreen;
  Probe: TGameOverProbe;
  GS, Bad: Integer;
  Drawn: Boolean;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- confirm, and the game-over screen ---');

  FillChar(Inp, SizeOf(Inp), 0);
  Want(not ConfirmPressed(Inp), 'confirm fired with nothing pressed');

  Inp.Button[0] := True;
  Want(ConfirmPressed(Inp), 'button 0 pressed did not confirm');
  Inp.ButtonLatch[0] := True;
  Want(not ConfirmPressed(Inp), 'button 0 HELD still confirmed - it is an edge');

  FillChar(Inp, SizeOf(Inp), 0);
  Inp.Button[1] := True;
  Want(ConfirmPressed(Inp), 'button 1 pressed did not confirm - both count');
  Inp.ButtonLatch[1] := True;
  Want(not ConfirmPressed(Inp), 'button 1 held still confirmed');

  { The phase machine, with no fader: 0 and 1 run in successive frames and
    2 holds until the music stops or confirm arrives. }
  Probe := TGameOverProbe.Create;
  G := TGameOverScreen.Create;
  try
    G.OnRestart := Probe.Restart;
    G.OnFade := Probe.Fade;
    G.OnMusic := Probe.Music;
    G.OnMusicPlaying := Probe.IsPlaying;

    { SILENT AT THE START, which is the drowning case: PS_FELL calls
      StopMusic before the death timer ever reaches DEATH_HOLD, so the
      screen begins with nothing playing. Phase 1 starts the game-over tune
      itself, and phase 2 must see THAT, not the silence it began in. With
      the answer passed in as an argument this read False and the screen was
      dismissed in the same frame it appeared. }
    Probe.Playing := False;
    ScreenPhase := 0;
    TitleSubMode := 7;
    GS := GS_PLAY_ALT;

    Drawn := G.Update(False, False, GS);
    Want(not Drawn, 'phase 0 drew something');
    Want(ScreenPhase = 1, 'phase 0 did not step to 1');
    Want(Probe.Fades = 1, 'phase 0 did not ask for a fade');

    Drawn := G.Update(False, False, GS);
    Want(Drawn, 'phase 2 did not draw');
    Want(ScreenPhase = 2, 'phase 1 did not step to 2');
    Want(Probe.Restarts = 1, 'the run was not torn down');
    Want(Probe.Tunes = 1, 'the game-over tune was not started');
    Want(TitleSubMode = 0, 'the title sub-mode was not cleared');
    Want(GS = GS_PLAY_ALT, 'the state left 100 too early');

    { Held input does not end the screen while its tune is playing. }
    Drawn := G.Update(False, False, GS);
    Want(Drawn and (GS = GS_PLAY_ALT),
         'the screen ended while the music ran - a death that stopped the '
         + 'stage music first never showed a game-over screen at all');
    { ... and confirm cuts it short. }
    G.Update(False, True, GS);
    Want(GS = GS_TITLE_INIT, 'confirm did not return to the title');
    Want(ScreenPhase = 0, 'the phase was not reset on the way out');

    { And the music running out ends it on its own. }
    ScreenPhase := 2;
    GS := GS_PLAY_ALT;
    Probe.Playing := False;
    G.Update(False, False, GS);
    Want(GS = GS_TITLE_INIT, 'the screen outlived its own music');
  finally
    G.Free;
    Probe.Free;
  end;

  Result := Bad;
  if Bad = 0 then
    Log.Add('confirm is an edge on either button, and the game-over screen '
      + 'runs its three phases');
end;

{ A two-page message driven the way the FRAME LOOP drives it.

  There was already a test for the box's paging and it passed while the game
  looped forever, because it drove TDialogueBox alone. The loop needed the
  other half: EventScript_Execute runs EVERY FRAME while the state is 140, so
  a sub-op 3 arm whose one-shot guard gets cleared re-raises page 1 for ever.
  That is what ScreenPhase did once the \k page turn started clearing it, and
  no box-only test could see it.

  So this drives both, in the frame loop's order, and requires the whole
  message to finish. }
function TestMessageLoop(Log: TStrings; const GameDir: string): Integer;
var
  Bad, I, Ev, Frames: Integer;
  Sc: TEventScript;
  R: TEventRunner;
  D: TDialogueBox;
  Pool: TEntityPool;
  Inp: TInputState;
  P: TPlayerState;
  GS: Integer;
  Seen1, Seen2: string;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then
    begin
      Log.Add('  FAIL: ' + What);
      Inc(Bad);
    end;
  end;

  { one frame, in AppIdle's order: the script first, then the box }
  procedure Frame(Confirm: Boolean);
  begin
    if GS = GS_STATE_140 then
      R.Execute(D, Sc, P, GS);
    if D.Active then
      D.Update(Confirm, Inp, GS);
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- a two-page message finishes, driven as the frame loop does ---');

  Sc := TEventScript.Create;
  R := TEventRunner.Create;
  D := TDialogueBox.Create;
  Pool := TEntityPool.Create;
  try
    Sc.Load(GameDir, 13);
    D.Bind(Sc, R, @P, Pool, nil);
    FillChar(Inp, SizeOf(Inp), 0);
    FillChar(P, SizeOf(P), 0);
    P.Progress[0] := 1;

    { stage 13's sign: one step, 0000-03-0002, which is the two-page line }
    Ev := -1;
    for I := 0 to Sc.Count - 1 do
      if Pos('03-0002', Sc[I].ParamB) > 0 then
      begin
        Ev := I;
        Break;
      end;
    Want(Ev >= 0, 'stage 13 has no 0000-03-0002 record - nothing exercised');

    if Ev >= 0 then
    begin
      GS := GS_PLAY;
      R.StartEvent(Sc, Ev, 0, P, GS);
      Want(GS = GS_STATE_140, 'the script did not enter state 140');

      { Type page 1 out. The box is not up until Execute has run a frame, so
        the wait is "not up yet OR still typing" - checking only for TYPING
        exits immediately, before the first frame, and tests nothing. }
      Frames := 0;
      while ((not D.Active) or (D.BoxMode = MB_MODE_TYPING))
            and (Frames < 2000) do
      begin
        Frame(False);
        Inc(Frames);
      end;
      Seen1 := D.VisibleLine[0];
      Want(D.BoxMode = MB_MODE_WAITKEY,
           Format('page 1 ended in mode %d, want %d', [D.BoxMode,
                  MB_MODE_WAITKEY]));

      { one confirm, then let it type page 2 - WITH Execute running each frame,
        which is what re-raised page 1 }
      Frame(True);
      Frames := 0;
      while ((not D.Active) or (D.BoxMode = MB_MODE_TYPING))
            and (Frames < 2000) do
      begin
        Frame(False);
        Inc(Frames);
      end;
      Seen2 := D.VisibleLine[0];
      Want(Seen2 <> Seen1,
           Format('after the page turn the box still reads %s - sub-op 3 '
             + 're-raised page 1, which is the reported infinite loop',
             [Seen2]));

      { and it must be escapable }
      Frame(True);
      Want(not D.Active, 'the box would not close');
      Want(GS = GS_PLAY,
           Format('the script left the state at %d, want GS_PLAY - the '
                  + 'player is stuck in the message', [GS]));
      Log.Add(Format('two-page message: %s -> %s -> closed',
                     [Copy(Seen1, 1, 12), Copy(Seen2, 1, 12)]));
    end;
  finally
    Pool.Free;
    D.Free;
    R.Free;
    Sc.Free;
  end;
  Result := Bad;
end;

type
  { Every tile is the kill tile, so a single vertical move must be lethal. }
  TAllKillTiles = class(TTileSource)
  public
    function TileAt(TileX, TileY: Integer): Integer; override;
  end;

function TAllKillTiles.TileAt(TileX, TileY: Integer): Integer;
begin
  Result := 29;
end;

{ The kill tile, from Terrain_Configure and Camera_ApplyMoveY.

  Terrain_Configure writes it beside the solid threshold - 0x1D for terrains
  1..8, 1000 for terrain 9 - and Camera_ApplyMoveY ends with
  Entity_CheckKillTiles, the xref at 0x00459E73. The check was implemented and
  called from NOWHERE, so the surf could be walked into and fallen through.
  The value was also computed by the terrain setup and thrown away. }
function TestKillTileWiring(Log: TStrings): Integer;
var
  Bad, Slot: Integer;
  Pool: TEntityPool;
  World: TEntityWorld;
  Killer: TAllKillTiles;
  L: TLayerInfo;
  Inp2: TInputState;
  P2: TPlayerState;
  GS2, Frames: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then
    begin
      Log.Add('  FAIL: ' + What);
      Inc(Bad);
    end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- the kill tile kills on a vertical move ---');

  Pool := TEntityPool.Create;
  World := TEntityWorld.Create;
  Killer := TAllKillTiles.Create;
  try
    FillChar(L, SizeOf(L), 0);
    L.TileW := 32;  L.TileH := 32;
    L.OriginX := POSITION_BIAS;  L.OriginY := POSITION_BIAS;
    World.Tiles := Killer;
    World.Layer := L;

    Slot := Pool.Spawn(EKIND_MINOR, 1, 0, 0);
    Want(Slot <> SLOT_NONE, 'could not spawn a test entity');
    if Slot <> SLOT_NONE then
    begin
      { A BOX WITH AREA. Spawn copies the type row, whose insets and tile
        offsets can leave the sweep empty - Top past Bottom - and then nothing
        is examined and the test proves nothing whichever way the code goes.
        Set the geometry the check actually reads. }
      Pool.SetField(Slot, EF_POS_X, POSITION_BIAS);
      Pool.SetField(Slot, EF_POS_Y, POSITION_BIAS);
      Pool.SetField(Slot, EF_EXTENT_X, 32);
      Pool.SetField(Slot, EF_EXTENT_Y, 32);
      Pool.SetField(Slot, EF_BOX_OFS_X, 0);
      Pool.SetField(Slot, EF_BOX_OFS_Y, 0);
      Pool.SetField(Slot, EF_TILE_OFS_X, 0);
      Pool.SetField(Slot, EF_TILE_OFS_Y, 0);
      World.KillTile := 29;                { every tile reads 29 }
      Pool.SetField(Slot, EF_STATE, 0);
      ApplyMoveY(L, Pool.Entity(Slot)^.Raw[EF_POS_Y],
                 Pool.Entity(Slot)^.Raw[EF_VEL_Y], False, False,
                 Pool.Entity(Slot), World);
      Want(Pool.Field(Slot, EF_STATE) = KILL_TILE_STATE,
           Format('a vertical move onto the kill tile left EF_STATE at %d, '
             + 'want %d - Camera_ApplyMoveY ends with Entity_CheckKillTiles, '
             + 'and without it the player falls through the water',
             [Pool.Field(Slot, EF_STATE), KILL_TILE_STATE]));

      World.KillTile := 30;                { now nothing matches }
      Pool.SetField(Slot, EF_STATE, 0);
      ApplyMoveY(L, Pool.Entity(Slot)^.Raw[EF_POS_Y],
                 Pool.Entity(Slot)^.Raw[EF_VEL_Y], False, False,
                 Pool.Entity(Slot), World);
      Want(Pool.Field(Slot, EF_STATE) = 0,
           'an ordinary tile killed the entity');

      { --- and dying that way must REACH the game-over screen ----------
        Reported: drowning kills but never shows the game-over screen, while
        other deaths do. PS_FELL counts PF_ANIM_TIMER up to DEATH_HOLD and
        then sets the state - and PF_ANIM_TIMER is EF_BLOCK_B, which is the
        very field Entity_CheckKillTiles zeroes. If anything re-runs the check
        while the player is dying, the timer restarts for ever. }
      World.KillTile := 29;
      Pool.SetField(Slot, EF_STATE, 0);
      Pool.SetField(Slot, EF_BLOCK_B, 0);
      ApplyMoveY(L, Pool.Entity(Slot)^.Raw[EF_POS_Y],
                 Pool.Entity(Slot)^.Raw[EF_VEL_Y], False, False,
                 Pool.Entity(Slot), World);
      Want(Pool.Field(Slot, EF_STATE) = KILL_TILE_STATE, 'not killed');
      Log.Add(Format('after the kill: state %d, death timer %d',
                     [Pool.Field(Slot, EF_STATE),
                      Pool.Field(Slot, EF_BLOCK_B)]));

      Log.Add('kill tile: lethal at 29, harmless at 30');

      { --- and PS_FELL must REACH the game-over screen -----------------
        Reported: drowning kills but no game-over screen appears, while other
        deaths show one. PS_FELL counts PF_ANIM_TIMER to DEATH_HOLD and then
        sets the state to 100. Driven here directly, with no kill tile in
        reach, so nothing can interfere. }
      World.Tiles := nil;
      Pool.SetField(Slot, EF_STATE, KILL_TILE_STATE);
      { 1, not 0: the timer-zero branch spawns debris and touches the music
        device, which a bare TEntityWorld answers abstractly. The countdown is
        what is under test. }
      Pool.SetField(Slot, EF_BLOCK_B, 1);
      FillChar(Inp2, SizeOf(Inp2), 0);
      FillChar(P2, SizeOf(P2), 0);
      GS2 := GS_PLAY;
      GameStateValue := GS_PLAY;
      Frames := 0;
      while (GameStateValue = GS_PLAY) and (Frames < 400) do
      begin
        PlayerUpdate(Pool.Entity(Slot)^, P2, L, Inp2, World, GS2);
        Inc(Frames);
      end;
      Want(GameStateValue = GS_PLAY_ALT,
           Format('after %d frames in PS_FELL the state is %d, want %d - '
             + 'drowning never reaches the game-over screen. Death timer '
             + 'ended at %d, DEATH_HOLD is %d',
             [Frames, GameStateValue, GS_PLAY_ALT,
              Pool.Field(Slot, EF_BLOCK_B), DEATH_HOLD]));
    end;
  finally
    Killer.Free;
    World.Free;
    Pool.Free;
  end;
  Result := Bad;
end;

{ Unlocking a door must DESTROY its entity, not merely kill it.

  Reported: after unlocking a door, the closed-door sprite followed the player
  around the room. That is the signature of a stale sprite - Entity_UpdateAll
  skips dead entities, so a sprite left behind is never repositioned again and
  holds the SCREEN coordinates it last had.

  0x00454790's disable branch, the one that fires the moment a BlockedBy flag
  goes up, ends with Entity_Destroy - confirmed by the xref at 0x004548E3 -
  and 0x00461400 hides the sprite, zeroes its depth and sets EF_SPRITE to -1.
  Kill sets EF_ALIVE and nothing else. }
function TestDisableDestroys(Log: TStrings; const GameDir: string): Integer;
var
  Bad, I, J, Slot, GS: Integer;
  S: TEventScript;
  R: TEventRunner;
  Pool: TEntityPool;
  World: TCountingWorld;
  Spr: TSpritePool;
  P: TPlayerState;
  L: TLayerInfo;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then
    begin
      Log.Add('  FAIL: ' + What);
      Inc(Bad);
    end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- a disabled event DESTROYS its entity ---');

  S := TEventScript.Create;
  R := TEventRunner.Create;
  Pool := TEntityPool.Create;
  World := TCountingWorld.Create;
  Spr := TSpritePool.Create;
  try
    { Attach a sprite sink so the release assertion exercises a real handle. }
    Pool.Sprites := Spr;
    World.Sprites := Spr;
    World.Pool := Pool;
    FillChar(L, SizeOf(L), 0);
    L.TileW := 32;  L.TileH := 32;
    L.MapTilesX := 100;  L.MapTilesY := 100;
    L.OriginX := POSITION_BIAS;  L.OriginY := POSITION_BIAS;

    { Find any shipped record that carries a forbidding flag and places
      something - that is the door's shape. }
    Slot := SLOT_NONE;
    for I := 1 to 65 do
    begin
      S.Load(GameDir, I);
      for J := 0 to S.Count - 1 do
        if (S[J].BlockedBy <> 0) and (S[J].BlockedBy < PROGRESS_LENGTH) then
        begin
          Pool.Clear;
          FillChar(P, SizeOf(P), 0);
          P.Progress[0] := 1;
          GS := GS_PLAY;
          R.SpawnNearCamera(S, Pool, L, S[J].TileX, S[J].TileY, P, GS, World);
          if S[J].Active then
          begin
            Slot := S[J].EntitySlot;
            { the precondition, stated out loud }
            Want(Pool.Field(Slot, EF_SPRITE) <> SPRITE_NONE,
                 'the placed entity has no sprite, so releasing it proves '
                 + 'nothing - this test needs a sprite sink');
            { now set the forbidding flag, as unlocking the door does }
            P.Progress[S[J].BlockedBy] := 1;
            R.SpawnNearCamera(S, Pool, L, S[J].TileX, S[J].TileY, P, GS, World);
            Break;
          end;
        end;
      if Slot <> SLOT_NONE then
        Break;
    end;

    Want(Slot <> SLOT_NONE,
         'no shipped record with a forbidding flag placed anything - this '
         + 'test exercised nothing');

    { --- and the kill tile actually kills ------------------------------
      Camera_ApplyMoveY ends with Entity_CheckKillTiles - the xref at
      0x00459E73 - so a vertical move onto the stage's kill tile puts the
      entity into EF_STATE 10. The check was implemented and called from
      nowhere, which is why the surf could be fallen through. }
    if Slot <> SLOT_NONE then
    begin
      Want(not Pool.Alive[Slot], 'the disabled event left its entity alive');
      Want(Pool.Field(Slot, EF_SPRITE) = SPRITE_NONE,
           Format('the entity was killed but its sprite handle is still %d - '
             + 'Entity_UpdateAll skips dead entities, so that sprite is never '
             + 'moved again and follows the camera',
             [Pool.Field(Slot, EF_SPRITE)]));
      Log.Add('disable path: entity destroyed and its sprite released');
    end;
  finally
    Spr.Free;
    World.Free;
    Pool.Free;
    R.Free;
    S.Free;
  end;
  Result := Bad;
end;

{ Compare the options screen's level, key, and gallery labels with akuji.exe.
  Pointer cells use the DATA bias; the string bodies use the CODE bias. }
function TestOptionTables(Log: TStrings; const GameDir: string): Integer;
var
  Bad, I: Integer;
  F: TFileStream;
  Exe: string;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then
    begin
      Log.Add('  FAIL: ' + What);
      Inc(Bad);
    end;
  end;

  function Dword(VA, Bias: Integer): Integer;
  begin
    F.Position := VA - Bias;
    F.ReadBuffer(Result, 4);
  end;

  { A Delphi AnsiString literal: the length sits in the four bytes before it. }
  function Str(VA: Integer): string;
  var
    N: Integer;
  begin
    Result := '';
    N := Dword(VA - 4, DATA_VA_BIAS);
    if (N <= 0) or (N > 40) then
    begin
      N := Dword(VA - 4, CODE_VA_BIAS);
      if (N <= 0) or (N > 40) then
        Exit;
      F.Position := VA - CODE_VA_BIAS;
    end
    else
      F.Position := VA - DATA_VA_BIAS;
    SetLength(Result, N);
    F.ReadBuffer(Result[1], N);
  end;

  { cell -> table base -> the Index'th pointer -> the string it names }
  function Entry(Cell, Index: Integer): string;
  begin
    Result := Str(Dword(Dword(Cell, DATA_VA_BIAS) + Index * 4, DATA_VA_BIAS));
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- the options screen''s tables, read out of akuji.exe ---');

  Exe := OriginalExe(GameDir);
  if Exe = '' then
  begin
    Log.Add('  FAIL: no original akuji.exe in the game directory');
    Result := 1;
    Exit;
  end;

  F := TFileStream.Create(Exe, fmOpenRead or fmShareDenyNone);
  try
    for I := Low(LEVEL_NAMES) to High(LEVEL_NAMES) do
      Want(Entry(OPT_LEVEL_NAME_CELL, I) = LEVEL_NAMES[I],
           Format('GAME LEVEL %d is %s in the image and %s here',
                  [I, Entry(OPT_LEVEL_NAME_CELL, I), LEVEL_NAMES[I]]));

    for I := Low(LEVEL_VARIANTS) to High(LEVEL_VARIANTS) do
      Want(Dword(Dword(OPT_LEVEL_VARIANT_CELL, DATA_VA_BIAS) + I * 4,
                 DATA_VA_BIAS) = LEVEL_VARIANTS[I],
           Format('GAME LEVEL %d draws in variant %d in the image and %d here',
                  [I, Dword(Dword(OPT_LEVEL_VARIANT_CELL, DATA_VA_BIAS)
                            + I * 4, DATA_VA_BIAS), LEVEL_VARIANTS[I]]));

    for I := Low(KEY_NAMES) to High(KEY_NAMES) do
      Want(Entry(OPT_KEY_NAME_CELL, I) = KEY_NAMES[I],
           Format('key %d is %s in the image and %s here',
                  [I, Entry(OPT_KEY_NAME_CELL, I), KEY_NAMES[I]]));

    for I := Low(OMAKE_NAMES) to High(OMAKE_NAMES) do
      Want(Entry(OPT_OMAKE_NAME_CELL, I) = OMAKE_NAMES[I],
           Format('gallery %d is %s in the image and %s here',
                  [I, Entry(OPT_OMAKE_NAME_CELL, I), OMAKE_NAMES[I]]));

    Log.Add(Format('options tables: %d levels, %d keys, %d gallery slots, '
      + 'all matching the image',
      [Length(LEVEL_NAMES), Length(KEY_NAMES), Length(OMAKE_NAMES)]));
  finally
    F.Free;
  end;
  Result := Bad;
end;

{ Sprite draw ORDER, from 0x0044D1E0 and 0x00464D30.

  The buckets are drawn in ASCENDING depth - low first, so low ends up BEHIND -
  and the type table makes the consequence concrete: the player is depth 4
  while signs, save statues and mana stones are 1, doors and orbs 2, monsters
  3. Reversing this order would draw scenery on top of Akuji.

  Bucket 0 is never drawn at all; the original's loop starts at 1, and
  Entity_Destroy zeroes EF_DEPTH, so 0 means destroyed or inert. Within one
  bucket the pool is walked from the LAST slot down, so a lower slot number
  draws later and therefore in front. }
function TestSpriteOrder(Log: TStrings): Integer;
var
  Bad, I: Integer;
  Pool: TSpritePool;
  Dest, Pic: TBitmap;
  Title: TTitleScreen;
  Sign, Door, Player, Dead, Hidden, Other: Integer;
  Order: TSpriteOrder;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then
    begin
      Log.Add('  FAIL: ' + What);
      Inc(Bad);
    end;
  end;

  function PosOf(Handle: Integer): Integer;
  var
    K: Integer;
  begin
    Result := -1;
    for K := 0 to High(Order) do
      if Order[K] = Handle then
        Exit(K);
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- the sprite draw order ---');

  Pool := TSpritePool.Create;
  try
    { Allocated in this order on purpose: the player takes a LOWER slot than
      the sign, so slot order alone would draw it first. Only depth may decide. }
    Player := Pool.AllocSprite(0);
    Sign   := Pool.AllocSprite(0);
    Door   := Pool.AllocSprite(0);
    Dead   := Pool.AllocSprite(0);
    Hidden := Pool.AllocSprite(0);
    Other  := Pool.AllocSprite(0);

    Pool.SetDepth(Player, 4);   Pool.SetVisible(Player, True);
    Pool.SetDepth(Sign, 1);     Pool.SetVisible(Sign, True);
    Pool.SetDepth(Door, 2);     Pool.SetVisible(Door, True);
    Pool.SetDepth(Dead, 0);     Pool.SetVisible(Dead, True);
    Pool.SetDepth(Hidden, 3);   Pool.SetVisible(Hidden, False);
    Pool.SetDepth(Other, 1);    Pool.SetVisible(Other, True);

    Order := Pool.DrawOrder;

    Want(PosOf(Player) >= 0, 'the player is not drawn at all');
    Want(PosOf(Sign) >= 0, 'the sign is not drawn at all');

    { The bug, stated as the thing the player sees. }
    Want(PosOf(Player) > PosOf(Sign),
         Format('the sign (depth 1) is drawn at %d and the player (depth 4) '
           + 'at %d - the player must be drawn LATER so it appears in FRONT',
           [PosOf(Sign), PosOf(Player)]));
    Want(PosOf(Player) > PosOf(Door),
         'the door (depth 2) is drawn after the player (depth 4)');
    Want(PosOf(Door) > PosOf(Sign),
         'the door (depth 2) is drawn before the sign (depth 1)');

    Want(PosOf(Dead) = -1,
         'a depth-0 sprite was drawn - bucket 0 is never drawn, and '
         + 'Entity_Destroy zeroes EF_DEPTH');
    Want(PosOf(Hidden) = -1, 'an invisible sprite was drawn');

    { Within one bucket: the pool is walked backwards, so the HIGHER slot
      number is emitted first and the lower one draws in front. }
    Want(PosOf(Other) < PosOf(Sign),
         Format('within depth 1, slot %d was drawn before slot %d - the '
           + 'original walks the pool from the last slot down',
           [Sign, Other]));

    Want(Length(Order) = 4,
         Format('%d sprites in the order, want 4 - two are excluded',
                [Length(Order)]));

    Log.Add(Format('draw order: %d sprites, player at position %d of %d',
                   [Length(Order), PosOf(Player), Length(Order)]));

    { --- the gallery picture is actually DRAWN ------------------------
      0x00462330's third arm blits the loaded surface over the whole screen.
      Draw had arms for the menu and the options page and NONE for the
      gallery, so choosing an image loaded the bitmap and showed whatever was
      already there. Painted into a real canvas and read back, because the
      defect was a missing branch - nothing short of the pixel proves it. }
    Dest := TBitmap.Create;
    Pic := TBitmap.Create;
    Title := TTitleScreen.Create;
    try
      Dest.SetSize(64, 64);
      Dest.Canvas.Brush.Color := clBlack;
      Dest.Canvas.FillRect(0, 0, 64, 64);
      Pic.SetSize(64, 64);
      Pic.Canvas.Brush.Color := clRed;
      Pic.Canvas.FillRect(0, 0, 64, 64);

      TitleSubMode := TSM_OMAKE;
      Title.Draw(Dest.Canvas, nil, nil, nil, Pic);
      Want(Dest.Canvas.Pixels[8, 8] = clRed,
           'the gallery sub-mode drew nothing - Draw has no TSM_OMAKE arm, so '
           + 'the picture is loaded and never blitted');

      { and it must not paint the gallery over the ordinary menu }
      Dest.Canvas.Brush.Color := clBlack;
      Dest.Canvas.FillRect(0, 0, 64, 64);
      TitleSubMode := TSM_MENU;
      Title.Draw(Dest.Canvas, nil, nil, nil, Pic);
      Want(Dest.Canvas.Pixels[8, 8] <> clRed,
           'the gallery picture was drawn while in the ordinary menu');
      TitleSubMode := TSM_MENU;
    finally
      Title.Free;
      Pic.Free;
      Dest.Free;
    end;
  finally
    Pool.Free;
  end;
  Result := Bad;
end;

{ Event_Begin's second argument is a frame countdown. Opcode-4 puzzle checks
  begin at four and re-run when it reaches zero. Stage 14 provides a shipped
  opcode-4 record for this test. }
function TestEventDelay(Log: TStrings; const GameDir: string): Integer;
var
  Bad, I, Fours: Integer;
  Sc: TEventScript;
  R: TEventRunner;
  P: TPlayerState;
  GS: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then
    begin
      Log.Add('  FAIL: ' + What);
      Inc(Bad);
    end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- the event delay re-fires the puzzle checkers ---');

  Sc := TEventScript.Create;
  R := TEventRunner.Create;
  try
    Sc.Load(GameDir, 14);
    Fours := 0;
    for I := 0 to Sc.Count - 1 do
      if Sc[I].Opcode = EVOP_ALWAYS then
        Inc(Fours);
    Want(Fours > 0,
         'stage 14 carries no opcode-4 record - this test exercises nothing');

    FillChar(P, SizeOf(P), 0);
    GS := GS_PLAY;

    { Arm the delay the way the spawn walk does, then put the state back as if
      the script had finished. }
    for I := 0 to Sc.Count - 1 do
      if Sc[I].Opcode = EVOP_ALWAYS then
      begin
        R.StartEvent(Sc, I, EVENT_BEGIN_FROM_SPAWN, P, GS);
        Break;
      end;
    Want(GS = GS_STATE_140, 'starting a checker did not enter state 140');
    GS := GS_PLAY;

    { Three ticks must NOT re-fire it: the delay is four. }
    R.TickDelay(Sc, P, GS);
    R.TickDelay(Sc, P, GS);
    R.TickDelay(Sc, P, GS);
    Want(GS = GS_PLAY,
         Format('the checker re-fired after three frames (state %d) - the '
                + 'delay is meant to be %d', [GS, EVENT_BEGIN_FROM_SPAWN]));

    { The fourth does. }
    R.TickDelay(Sc, P, GS);
    Want(GS = GS_STATE_140,
         Format('after %d frames the checker did not re-fire - state %d, want '
                + '%d. The delay is stored and never counted',
                [EVENT_BEGIN_FROM_SPAWN, GS, GS_STATE_140]));

    { And it does not keep firing: the re-fire arms a delay of 0. }
    GS := GS_PLAY;
    for I := 1 to 20 do
      R.TickDelay(Sc, P, GS);
    Want(GS = GS_PLAY,
         'the checker kept re-firing - a delay of 0 must not count down');

    Log.Add(Format('event delay: %d opcode-4 records in stage 14, re-fires '
                   + 'after %d frames', [Fours, EVENT_BEGIN_FROM_SPAWN]));
  finally
    R.Free;
    Sc.Free;
  end;
  Result := Bad;
end;

{ Exercise MessageBox_Update @ 0x00456038 with shipped dialogue. Text appears
  in two-byte units every third frame, input fast-forwards it, and the page's
  terminal marker selects the following mode and optional prompt. }
function TestTypewriter(Log: TStrings; const GameDir: string): Integer;
var
  Bad, I, K, Seen, Plain: Integer;
  FoundKey, FoundPrompt: Boolean;
  D: TDialogueBox;
  Sc: TEventScript;
  Inp: TInputState;
  GS: Integer;
  L: string;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then
    begin
      Log.Add('  FAIL: ' + What);
      Inc(Bad);
    end;
  end;

  { The first script line whose opening eight characters carry no marker, so
    the expected prefixes are the line's own text and nothing has to
    re-implement the splitter to know them. }
  function PlainLine: Integer;
  var
    N: Integer;
  begin
    Result := -1;
    for N := 0 to Sc.LineCount - 1 do
      if (Length(Sc.Lines[N]) >= 10)
         and (Pos('\', Copy(Sc.Lines[N], 1, 8)) = 0) then
      begin
        Result := N;
        Exit;
      end;
  end;

begin
  Bad := 0;
  FoundKey := False;
  FoundPrompt := False;
  Log.Add('');
  Log.Add('--- the typewriter, and the two icons ---');

  Sc := TEventScript.Create;
  D := TDialogueBox.Create;
  try
    { Stage 2 contains both ordinary dialogue and the first \w prompt. }
    Sc.Load(GameDir, 2);
    if Sc.LineCount = 0 then
    begin
      Log.Add('  FAIL: stage 1 loaded no dialogue lines');
      Result := 1;
      Exit;
    end;
    D.Bind(Sc, nil, nil, nil, nil);
    FillChar(Inp, SizeOf(Inp), 0);
    GS := GS_STATE_140;

    Plain := PlainLine;
    Want(Plain >= 0, 'no shipped line starts with eight marker-free chars');
    if Plain >= 0 then
    begin
      L := Sc.Lines[Plain];
      D.ShowLine(Plain);
      Want(D.BoxMode = MB_MODE_TYPING,
           'a fresh page is not in the typing mode');
      Want(D.VisibleLine[0] = '',
           Format('the box showed "%s" before a single frame ran - the page '
             + 'is printed, not typed', [D.VisibleLine[0]]));

      { Two frames must reveal NOTHING: the counter has to pass 2. }
      D.Update(False, Inp, GS);
      D.Update(False, Inp, GS);
      Want(D.VisibleLine[0] = '',
           Format('after two frames the box already reads "%s" - the reveal '
             + 'is meant to take three', [D.VisibleLine[0]]));

      { The third uncovers exactly one TWO-byte unit. }
      D.Update(False, Inp, GS);
      Want(D.VisibleLine[0] = Copy(L, 1, 2),
           Format('the third frame revealed "%s", want "%s" - one two-byte '
             + 'unit', [D.VisibleLine[0], Copy(L, 1, 2)]));

      { Six more frames is two more units, at the same rate. }
      for I := 1 to 6 do
        D.Update(False, Inp, GS);
      Want(D.VisibleLine[0] = Copy(L, 1, 6),
           Format('nine frames revealed "%s", want "%s"',
                  [D.VisibleLine[0], Copy(L, 1, 6)]));

      { --- the fast-forward -------------------------------------------- }
      D.ShowLine(Plain);
      Inp.Button[0] := True;
      D.Update(False, Inp, GS);
      Want(D.VisibleLine[0] = Copy(L, 1, 2),
           Format('holding a button revealed "%s" on the first frame, want '
             + '"%s" - the fast-forward is not wired',
             [D.VisibleLine[0], Copy(L, 1, 2)]));
      Inp.Button[0] := False;
    end;

    { --- run a whole page out and see which mode it lands in ------------ }
    for K := 0 to Sc.LineCount - 1 do
    begin
      D.ShowLine(K);
      Seen := 0;
      Inp.Button[0] := True;      { fast-forward, or this takes all day }
      while (D.BoxMode = MB_MODE_TYPING) and (Seen < 4000) do
      begin
        D.Update(False, Inp, GS);
        Inc(Seen);
      end;
      Inp.Button[0] := False;
      Want(D.BoxMode <> MB_MODE_TYPING,
           Format('line %d never finished typing in %d frames', [K, Seen]));
      if D.BoxMode = MB_MODE_TYPING then
        Break;
    end;

    { --- the \k prompt icon animates ------------------------------------ }
    for K := 0 to Sc.LineCount - 1 do
    begin
      D.ShowLine(K);
      Seen := 0;
      Inp.Button[0] := True;
      while (D.BoxMode = MB_MODE_TYPING) and (Seen < 4000) do
      begin
        D.Update(False, Inp, GS);
        Inc(Seen);
      end;
      Inp.Button[0] := False;
      if D.BoxMode = MB_MODE_WAITKEY then
      begin
        FoundKey := True;
        Seen := D.AnimFrame;
        for I := 1 to 5 do
          D.Update(False, Inp, GS);
        Want(D.AnimFrame <> Seen,
             'the \k prompt icon did not advance after five frames - it is '
             + 'meant to cycle six steps');
        Break;
      end;
    end;

    { --- the \w hand: horizontal, and it animates ------------------------ }
    for K := 0 to Sc.LineCount - 1 do
    begin
      D.ShowLine(K);
      Seen := 0;
      Inp.Button[0] := True;
      while (D.BoxMode = MB_MODE_TYPING) and (Seen < 4000) do
      begin
        D.Update(False, Inp, GS);
        Inc(Seen);
      end;
      Inp.Button[0] := False;
      if D.BoxMode = MB_MODE_PROMPT then
      begin
        FoundPrompt := True;
        Want(D.Choice = 0, 'the prompt did not start on Yes');
        Inp.AxisX := 1;
        Inp.Moving := False;
        D.Update(False, Inp, GS);
        Want(D.Choice = 1,
             'right did not move the prompt to No - the original moves this '
             + 'on AxisX, not on up and down');
        D.Update(False, Inp, GS);
        Want(D.Choice = 1, 'the choice ran past No instead of clamping');
        Inp.AxisX := -1;
        D.Update(False, Inp, GS);
        Want(D.Choice = 0, 'left did not move the prompt back to Yes');
        Inp.AxisX := 0;

        Seen := D.AnimFrame;
        for I := 1 to 9 do
          D.Update(False, Inp, GS);
        Want(D.AnimFrame <> Seen,
             'the yes/no hand did not advance after nine frames');
        Break;
      end;
    end;

    { Require both page types so conditional assertions cannot pass vacuously. }
    Want(FoundKey,
         'no page in this script ended in \k - the prompt-icon assertions '
         + 'never ran');
    Want(FoundPrompt,
         'no page in this script ended in \w - the yes/no assertions never '
         + 'ran, so the axis it reads was not checked at all');

    Log.Add(Format('typewriter: two bytes every three frames; \k icon cycles '
      + '%d steps, hand %d; both icons exercised',
      [MB_KEY_FRAMES, MB_HAND_FRAMES]));

    { --- a MULTI-PAGE message must reach its last page ------------------
      Reported: 'Your Fire has increased!' looped forever and the rest of the
      message was never reachable. That line is tk013's third, and it is two
      pages joined by \k. Driven here the way a player does it: type the page
      out, press confirm once, and the SECOND page must appear and differ. }
    Sc.Load(GameDir, 13);
    if Sc.LineCount > 2 then
    begin
      D.ShowLine(2);
      Seen := 0;
      Inp.Button[0] := True;
      while (D.BoxMode = MB_MODE_TYPING) and (Seen < 4000) do
      begin
        D.Update(False, Inp, GS);
        Inc(Seen);
      end;
      Inp.Button[0] := False;
      L := D.VisibleLine[0];
      Want(D.BoxMode = MB_MODE_WAITKEY,
           Format('page 1 of the two-page message ended in mode %d, want %d',
                  [D.BoxMode, MB_MODE_WAITKEY]));

      { one confirm, exactly as a player gives it }
      D.Update(True, Inp, GS);
      Seen := 0;
      Inp.Button[0] := True;
      while (D.BoxMode = MB_MODE_TYPING) and (Seen < 4000) do
      begin
        D.Update(False, Inp, GS);
        Inc(Seen);
      end;
      Inp.Button[0] := False;
      Want(D.VisibleLine[0] <> L,
           Format('after the confirm the box still reads %s - it looped back '
             + 'to page 1 instead of advancing', [D.VisibleLine[0]]));
      Want(D.BoxMode = MB_MODE_END,
           Format('page 2 ended in mode %d, want %d - the message must be '
             + 'escapable', [D.BoxMode, MB_MODE_END]));
    end;
  finally
    D.Free;
    Sc.Free;
  end;
  Result := Bad;
end;

{ Pause > RESET must reach the TITLE, and must not carry the confirm with it.

  Reported symptom: "Pause > Reset brought me back to the last saved location,
  equivalent to being on the menu and selecting Continue - the game thought the
  pause menu was the main menu." Both menus index the SAME cursor global
  (0x0046CF88) and RESET is row 1 in the pause menu while CONTINUE is row 1 in
  the title menu, so a cursor that survives the transition, or a confirm that
  does, lands on Continue and loads the save.

  Every step is checked separately, because the end state alone cannot say
  WHICH of the three carried over. }
function TestPauseFlow(Log: TStrings): Integer;
var
  Bad: Integer;
  Inp: TInputState;
  Pause: TPauseMenu;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then
    begin
      Log.Add('  FAIL: ' + What);
      Inc(Bad);
    end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- pause > reset goes to the title, not to Continue ---');

  Pause := TPauseMenu.Create;
  try
    { Enter pause from play, with the cursor somewhere that is not 0 so the
      stash is observable. }
    GameStateValue := GS_PLAY;
    MenuIndex := 3;
    EnterPause;
    Want(GameStateValue = GS_PAUSE, 'ESC did not enter the pause state');
    Want(SavedGameState = GS_PLAY, 'the paused state was not stashed');
    Want(SavedMenuIndex = 3, 'the cursor was not stashed');
    Want(MenuIndex = 0, 'the pause cursor did not start at 0');

    { Select RESET and confirm on button 0. }
    FillChar(Inp, SizeOf(Inp), 0);
    ScreenPhase := 1;          { past the one-shot init }
    MenuIndex := PAUSE_RESTART;
    Inp.Button[0] := True;
    Pause.Update(Inp, GameStateValue);

    Want(GameStateValue = GS_TITLE_INIT,
         Format('pause RESET left the state at %d, want GS_TITLE_INIT %d - '
           + 'anything else is a different screen entirely',
           [GameStateValue, GS_TITLE_INIT]));

    { THE LEAK. The button is still physically down on the next frame, so if
      the latch did not go up the title menu sees a fresh confirm and acts on
      whatever row the cursor is on. }
    Want(not ConfirmPressed(Inp),
         'the confirm was not latched - it survives into the title screen and '
         + 'fires there, which is how RESET turns into CONTINUE');
    Want(Inp.ButtonLatch[0], 'ButtonLatch[0] was not set by the pause confirm');

    { --- the confirm FALLS THROOUGH -----------------------------------
      Every arm of 0x00461EE4's confirm ends in `JMP 0x00462024`, the CANCEL
      test - not the epilogue at 0x004620C7 - so after a confirm the cancel
      test and then the movement block still run. Two observable consequences.

      First: the cursor still moves on the frame you confirm. }
    FillChar(Inp, SizeOf(Inp), 0);
    ScreenPhase := 1;
    MenuIndex := PAUSE_RESTART;
    GameStateValue := GS_PAUSE;
    Inp.Button[0] := True;
    Inp.AxisY := 1;
    Inp.Moving := False;
    Pause.Update(Inp, GameStateValue);
    Want(GameStateValue = GS_TITLE_INIT,
         'the confirm did not take');
    Want(MenuIndex = PAUSE_RESTART + 1,
         Format('the cursor is %d after confirming with down held, want %d - '
           + 'the confirm must fall through to the movement block',
           [MenuIndex, PAUSE_RESTART + 1]));

    { Second: a cancel in the SAME frame wins, because it runs after the
      confirm and writes the state again. }
    FillChar(Inp, SizeOf(Inp), 0);
    ScreenPhase := 1;
    MenuIndex := PAUSE_RESTART;
    SavedGameState := GS_PLAY;
    GameStateValue := GS_PAUSE;
    Inp.Button[0] := True;                          { confirm }
    Inp.Button[PAUSE_CANCEL_BUTTON] := True;        { and cancel }
    Pause.Update(Inp, GameStateValue);
    Want(GameStateValue = GS_PLAY,
         Format('confirm and cancel in one frame left the state at %d, want '
           + 'the cancel to win at %d - it runs after the confirm',
           [GameStateValue, GS_PLAY]));

    Log.Add(Format('pause: reset -> state %d, confirm latched %s',
                   [GameStateValue, BoolToStr(Inp.ButtonLatch[0], True)]));
  finally
    Pause.Free;
  end;
  Result := Bad;
end;

{ TResetSpy mirrors GameState_Reset's MenuIndex side effect so the title test
  verifies that the selected command is captured before the reset. }
type
  TResetSpy = class
    Fired: Boolean;
    FadeFired: Boolean;
    procedure Reset;
    procedure Fade;
  end;


procedure TResetSpy.Fade;
begin
  FadeFired := True;
end;

procedure TResetSpy.Reset;
begin
  Fired := True;
  { Exactly what TGameSession.ResetState does to the shared cursor. }
  MenuIndex := 0;
end;

{ CONTINUE must load rather than start a new game. Game_StartOrLoad
  @ 0x00462F40 selects the path through p_TitleSubMode, so this test drives the
  title confirmation and loader together. }
function TestContinueLoadsSave(Log: TStrings; const ScratchDir: string): Integer;
var
  Bad, GS: Integer;
  T: TTitleScreen;
  P: TPlayerState;
  Cfg: TGameSettings;
  Host: TStartHost;
  Spy: TResetSpy;
  SaveName: string;
  F: TFileStream;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then
    begin
      Log.Add('  FAIL: ' + What);
      Inc(Bad);
    end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- CONTINUE loads the save ---');

  { The menu half. Down once from NEW GAME is CONTINUE, and confirming it must
    leave the sub-mode at 1 - which is the only thing the loader looks at. }
  T := TTitleScreen.Create;
  Spy := TResetSpy.Create;
  try
    T.OnResetState := Spy.Reset;
    MenuIndex := 0;
    T.Update(1, 0, False);
    Want(T.Index = 1,
         Format('one press of down left the cursor on %d, want CONTINUE at 1',
                [T.Index]));
    T.Update(0, 0, True);
    Want(Spy.Fired, 'confirming did not run GameState_Reset');
    Want(T.SubMode = 1,
         Format('confirming CONTINUE left the sub-mode at %d, want 1 - at 0 '
           + 'the loader starts a new game instead. The index must be read '
           + 'BEFORE GameState_Reset, which zeroes it', [T.SubMode]));
  finally
    Spy.Free;
    T.Free;
  end;

  { The loader half, against a save that cannot be confused with a new game:
    a stage no new game starts on, and an ability a new game clears. }
  SaveName := IncludeTrailingPathDelimiter(ScratchDir) + 'save.dat';
  FillChar(P, SizeOf(P), 0);
  P.SavedStage := 7;
  P.Head[ABILITY_DASH] := 1;
  P.MusicTrack := 1;
  F := TFileStream.Create(SaveName, fmCreate);
  try
    F.WriteBuffer(P, SizeOf(P));
  finally
    F.Free;
  end;

  Host := TStartHost.Create;
  try
    FillChar(Cfg, SizeOf(Cfg), 0);
    FillChar(P, SizeOf(P), 0);
    GS := 0;
    ScreenPhase := 7;      { must be cleared - see below }
    GameStartOrLoad(P, Cfg, smContinue, Host, True, SaveName, GS);
    { Statement 2 of 0x00462F40: ScreenPhase := 0, between the opening gate
      and the state write. Seeded so the clear is observable. }
    Want(ScreenPhase = 0,
         Format('GameStartOrLoad left ScreenPhase at %d - it clears it at '
                + '00462F66, right after the opening gate', [ScreenPhase]));
    Want(Cfg.CurrentStage = 7,
         Format('CONTINUE resumed at stage %d, want the saved stage 7 - '
           + 'stage %d is where a NEW GAME starts',
           [Cfg.CurrentStage, START_STAGE]));
    Want(P.Head[ABILITY_DASH] = 1,
         'CONTINUE cleared the dash ability - the defaults were written over '
         + 'the load instead of under it');

    { And the other direction, or the test above would pass on a loader that
      always loads. }
    FillChar(Cfg, SizeOf(Cfg), 0);
    FillChar(P, SizeOf(P), 0);
    GS := 0;
    GameStartOrLoad(P, Cfg, smNewGame, Host, True, SaveName, GS);
    Want(Cfg.CurrentStage = START_STAGE,
         Format('NEW GAME started at stage %d, want %d - it read the save',
                [Cfg.CurrentStage, START_STAGE]));
    Want(P.Head[ABILITY_DASH] = 0,
         'NEW GAME kept the saved dash ability');
  finally
    Host.Free;
  end;

  Log.Add(Format('continue: sub-mode 1, resumed stage %d, dash %d',
                 [7, 1]));
  Result := Bad;
end;

{ Ending_Update @ 0x00463624: the completion percentage, the rank, and the two
  sets of persistent flags it banks.

  Every expectation here is a LITERAL. The percentage in particular is not
  compared against Counter div 4, because the whole point is that the original
  is not Counter div 4 at two values - `python tools/x87_sim.py ending` is the
  independent reader that says which two, and it is run by tools/check.sh. }
function TestEnding(Log: TStrings): Integer;
var
  S: TGameSettings;
  P: TPlayerState;
  Bad, I: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- the ending screen ---');

  Want(EndingPercent(0) = 0, 'zero collected is not zero percent');
  Want(EndingPercent(400) = 100, 'all four hundred is not a hundred percent');
  Want(EndingPercent(7) = 1, '7 of 400 should truncate to 1');
  Want(EndingPercent(200) = 50, '200 of 400 should be 50');
  { The two the original gets wrong. }
  Want(EndingPercent(212) = 52, 'counter 212 should read 52, not 53');
  Want(EndingPercent(236) = 58, 'counter 236 should read 58, not 59');
  Want(EndingPercent(213) = 53, 'counter 213 is not one of the two');
  Want(EndingPercent(237) = 59, 'counter 237 is not one of the two');

  { A long run, so the time gate never fires and the percentage gates decide. }
  Want(EndingRank(200, 9999) = 0, '50 percent should not beat the first gate');
  Want(EndingRank(204, 9999) = 1, '51 percent should reach rank 1');
  Want(EndingRank(284, 9999) = 2, '71 percent should reach rank 2');
  Want(EndingRank(364, 9999) = 3, '91 percent should reach rank 3');
  { And the time gate overriding a poor percentage. }
  Want(EndingRank(0, 1800) = 4, 'thirty minutes exactly should reach rank 4');
  Want(EndingRank(400, 1801) = 3,
       'one second over thirty minutes should not reach rank 4');

  FillChar(S, SizeOf(S), 0);
  FillChar(P, SizeOf(P), 0);
  P.Counter := 364;  P.ElapsedSec := 9999;
  EndingApplyUnlocks(S, P);
  Want(S.ExtraDoor1 = 1, 'rank 3 did not unlock the first door');
  Want(S.ExtraDoor2 = 0, 'rank 3 unlocked the second door too');

  FillChar(S, SizeOf(S), 0);
  P.Counter := 0;  P.ElapsedSec := 1800;
  EndingApplyUnlocks(S, P);
  Want((S.ExtraDoor1 = 1) and (S.ExtraDoor2 = 1),
       'a fast run did not unlock both doors');

  { The gallery: one byte per flag, in order, and never taken away. }
  FillChar(S, SizeOf(S), 0);
  FillChar(P, SizeOf(P), 0);
  P.Progress[GALLERY_FIRST_FLAG + 3] := 1;
  EndingApplyUnlocks(S, P);
  Want(S.GalleryUnlocked[3] = 1, 'gallery flag 3 did not carry across');
  for I := 0 to GALLERY_COUNT - 1 do
    if I <> 3 then
      Want(S.GalleryUnlocked[I] = 0, Format('gallery entry %d unlocked itself', [I]));

  S.GalleryUnlocked[5] := 1;
  FillChar(P, SizeOf(P), 0);
  EndingApplyUnlocks(S, P);
  Want(S.GalleryUnlocked[5] = 1, 'a worse run took a gallery entry away');

  Want(EndingTimeText(3725) = '01:02:05', 'the clock does not format h:mm:ss');
  { NOT '052%'. The format string is '%03d%%', which looks like C's zero-pad
    and is not: Delphi's Format parses the digits as a WIDTH, leading zero and
    all, and pads with spaces. So the original prints a space, not a zero. }
  Want(EndingPercentText(212) = ' 52%',
       'the percentage should be space-padded to three - %03d is a width');
  Want(EndingPercentText(400) = '100%', 'a full run should not be padded');

  Result := Bad;
  if Bad = 0 then
    Log.Add('the percentage carries the original''s two off-by-ones, and the '
      + 'rank banks the right flags');
end;

function SelfTestSession(Log: TStrings): Integer;
var
  GameDir: string;
  Stages: TStageTable;
  Map: TTileMap;
  Frames: TSpriteSet;
  S: TGameSession;
  GS, I, Bad, StartY, Fell, Moved, StartX, Slot: Integer;
  Placed, LiveAfter, Stage, T, J, NoSprite, EvI, K: Integer;
  FadeSpy: TResetSpy;
  Types, Blind, Surv: string;
  PlacedIn, SurvivedIn: array[0..ENTITY_TYPE_COUNT - 1] of Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');

  Stages := TStageTable.Create;
  Map := TTileMap.Create;
  S := nil;
  try
    if Stages.Load(GameDir) <= 0 then
    begin
      Log.Add('FAILED: no stage table');
      Result := 1;
      Exit;
    end;
    if not Map.Load(GameDir, Stages.Layer[1, 0]) then
    begin
      Log.Add('FAILED: could not load stage 1''s map');
      Result := 1;
      Exit;
    end;

    { The sprite frames are not decoration: an entity's extents are read off
      its sprite every frame, so without them nothing has a size and nothing
      collides. That is exactly how this test failed the first time it ran. }
    Frames := TSpriteSet.Create;
    Frames.LoadSet(GameDir, Stages.SpriteSet[1]);

    S := TGameSession.Create(GameDir, Stages, Map);
    S.SetFrames(Frames);

    { --- a stage begins --------------------------------------------- }
    InitNewGame(S.Player, 0);
    ApplySessionFlags(S.Player, 0);
    GS := GS_STAGE_BEGIN;
    { Stage_Begin @ 0x00462210 clears the title sub-mode. TSM_OPTIONS is 1 and
      the CONTINUE sub-mode is also 1 - one variable, two meanings - so a stage
      that does not clear it sends the next visit to the title screen straight
      to the OPTIONS page. Seeded with TSM_OPTIONS so the clear is observable;
      a test that starts at 0 cannot tell a clear from a no-op. }
    { Load_Stage_Assets runs first, as the form runs it - the terrain, the
      background animator and the events are its work, not Stage_Begin's. }
    S.LoadStageAssets(1);
    TitleSubMode := TSM_OPTIONS;

    { --- Stage_Begin's first four statements --------------------------
      Seeded so each clear is OBSERVABLE: a test that starts at zero cannot
      tell a clear from a no-op.

      The scratch flag is the monster bug. GameState_Reset wipes
      Progress[4000..4500], and every type-29 monster in rooms 3 and 4 uses
      that range as its BlockedBy - so a flag left set makes
      Events_SpawnNearCamera disable the event forever and the monster never
      returns. Stage_Begin called no reset at all. }
    ScreenPhase := 9;
    S.Player.Progress[PROGRESS_SCRATCH_FIRST] := 1;
    S.Player.Progress[PROGRESS_LENGTH - 1] := 1;
    S.Player.Progress[PROGRESS_SCRATCH_FIRST - 1] := 1;   { must SURVIVE }
    FadeSpy := TResetSpy.Create;
    S.OnStartFade := FadeSpy.Fade;

    S.BeginStage(1, GS);

    { WATER KILLS. Terrain_Configure writes the kill tile beside the solid
      threshold - 29 for terrains 1..8, 1000 for terrain 9 - and
      Camera_ApplyMoveY ends with Entity_CheckKillTiles, which puts the
      entity into EF_STATE 10 on contact. The value was computed and thrown
      away, so the player fell through the surf instead of dying. }
    Want(S.World.KillTile = 29,
         Format('stage 1 gave kill tile %d, want 29 - the value Terrain_Configure returns was discarded', [S.World.KillTile]));

    Want(TitleSubMode = TSM_MENU,
         Format('BeginStage left the title sub-mode at %d - the title screen '
           + 'will come back up on its options page', [TitleSubMode]));
    Want(S.Player.Progress[PROGRESS_SCRATCH_FIRST] = 0,
         'BeginStage did not clear the scratch progress flags - a killed '
         + 'monster stays blocked forever and never respawns');
    Want(S.Player.Progress[PROGRESS_LENGTH - 1] = 0,
         'the scratch clear stops short of the end of the block');
    Want(S.Player.Progress[PROGRESS_SCRATCH_FIRST - 1] = 1,
         'the scratch clear ran BELOW 4000 and wiped real progress');
    Want(ScreenPhase = 0, 'BeginStage did not clear ScreenPhase');
    Want(FadeSpy.FadeFired,
         'BeginStage did not start the fade - room transitions never '
         + 'dissolve, which is statements 1 and 2');

    Log.Add(Format('stage 1: terrain %d, solid threshold %d, %d events, '
      + 'map %dx%d tiles of %dx%d',
      [S.World.TerrainId, S.World.SolidThreshold, S.Events.Count,
       Map.MapWidth, Map.MapHeight, Map.TileWidth, Map.TileHeight]));

    Want(GS = GS_PLAY, Format('BeginStage left the state at %d, want %d',
                              [GS, GS_PLAY]));
    Want(S.World.SolidThreshold > 0,
         'the solid threshold is 0 - every tile would be walkable');
    Want(S.Events.Count > 0, 'stage 1 loaded no events');
    Want(S.Pool.Alive[0], 'the player is not in slot 0 after BeginStage');
    Want(S.Pool.LiveCount = 1,
         Format('BeginStage left %d entities, want just the player',
                [S.Pool.LiveCount]));
    Want(S.Layer.TileW = 32, 'the layer did not take the map''s tile size');

    { The world's copy of the layer must be the session's, or every collision
      query reads a stale origin. This is exactly the class of mistake that
      only appears once things are connected. }
    Want(S.World.Layer.TileW = S.Layer.TileW,
         'the world''s layer is not the session''s');
    Want(S.World.Layer.OriginY = S.Layer.OriginY,
         'the world''s layer origin is stale');

    { --- frames run ------------------------------------------------- }
    StartY := S.Pool.PosY(0);
    StartX := S.Pool.PosX(0);
    Log.Add('');
    { The first frames of a stage, kept because they are the whole story: the
      player is placed in mid air, falls, and lands. Getting here took a
      sprite pool - see SpritePool.pas - and the trace is what showed why. }
    Log.Add('  frame state posY  velY  worldRow  tile');
    for I := 1 to 120 do
    begin
      if I <= 5 then
        Log.Add(Format('  %5d %5d %5d %5d %9d %5d',
          [I, S.Pool.Field(0, EF_STATE),
           PixelOf(S.Pool.Field(0, EF_POS_Y)),
           S.Pool.Field(0, EF_VEL_Y),
           (PixelOf(S.Layer.OriginY) + PixelOf(S.Pool.Field(0, EF_POS_Y)))
             div 32,
           Map.TileAtRaw(
             (PixelOf(S.Layer.OriginX) + PixelOf(S.Pool.Field(0, EF_POS_X)))
               div 32,
             (PixelOf(S.Layer.OriginY) + PixelOf(S.Pool.Field(0, EF_POS_Y)))
               div 32)]));
      S.Frame(GS);
    end;
    Log.Add(Format('  extents %d x %d, sprite handle %d, frames %d',
      [S.Pool.Field(0, EF_EXTENT_X), S.Pool.Field(0, EF_EXTENT_Y),
       S.Pool.Field(0, EF_SPRITE), Frames.Count]));
    Want(S.Pool.Field(0, EF_SPRITE) <> SPRITE_NONE,
         'the player got no sprite, so it has no extents and cannot collide');
    Want(S.Pool.Field(0, EF_EXTENT_X) > 0,
         'the player has zero width - Entity_UpdateAll is not reading the '
         + 'sprite');

    { A translated handler gives its entity a sprite of its own. An
      UNtranslated one leaves the anim id Entity_Spawn wrote, which is the
      type table's column 0 - and that column is 0 for all 81 types, so an
      untranslated entity wears sprite 0, which is Akuji standing. Stage 1
      places three type-16 signs; before that handler existed they looked
      exactly like the player, and nothing here could tell. }
    Slot := -1;
    for I := 1 to 63 do
      if S.Pool.Alive[I] and (S.Pool.Field(I, EF_TYPE) = 16) then
        Slot := I;
    if Slot < 0 then
      Log.Add('  (stage 1 placed no sign; the sprite check is skipped)')
    else
    begin
      Want(S.Pool.Field(Slot, EF_ANIM_ID) = 54,
           Format('the sign is on sprite %d, want 54 - sprite 0 means its '
             + 'handler never ran', [S.Pool.Field(Slot, EF_ANIM_ID)]));
      Want(S.Pool.Field(Slot, EF_ANIM_ID) <> S.Pool.Field(0, EF_ANIM_ID),
           'the sign and the player are on the same sprite');
    end;
    Log.Add('');

    Fell := S.Pool.PosY(0) - StartY;
    Log.Add(Format('120 idle frames: player moved %d sub-pixels down, %d across',
      [Fell, S.Pool.PosX(0) - StartX]));
    Log.Add(Format('  live entities now %d, game state %d',
      [S.Pool.LiveCount, GS]));

    Want(S.Pool.Alive[0], 'the player stopped existing during 120 idle frames');
    Want(Fell > 0,
         'the player did not fall at all - gravity or the tile query is not '
         + 'reaching the entity');
    { And it must STOP falling: an entity that never lands means the collision
      query is answering TILE_NONE, which is what a missing tile source looks
      like. }
    StartY := S.Pool.PosY(0);
    for I := 1 to 120 do
      S.Frame(GS);
    Want(S.Pool.PosY(0) = StartY,
         Format('the player is still falling after 240 frames (%d more '
           + 'sub-pixels) - nothing is solid', [S.Pool.PosY(0) - StartY]));

    { --- input reaches the controller -------------------------------- }
    StartX := S.Pool.PosX(0);
    S.Input.AxisX := 1;
    for I := 1 to 60 do
      S.Frame(GS);
    S.Input.AxisX := 0;
    Moved := S.Pool.PosX(0) - StartX;
    Log.Add(Format('60 frames holding right: moved %d sub-pixels (%d px)',
      [Moved, Moved div 32]));
    Want(Moved > 0, 'holding right moved the player nowhere - input is not '
         + 'reaching the controller');
    { And it must move at the speed the controller's own constant predicts:
      AxisX shl PLAYER_WALK_SHIFT is 32 sub-pixels, which is exactly one pixel
      a frame. 60 frames, 60 pixels. Pinning the NUMBER rather than "it moved"
      is what makes this a check on the wiring and not just on liveness. }
    Want(Moved = 60 * (1 shl PLAYER_WALK_SHIFT),
         Format('walking 60 frames moved %d sub-pixels, want %d - one pixel '
           + 'a frame', [Moved, 60 * (1 shl PLAYER_WALK_SHIFT)]));

    { What is actually on screen at the start of a stage, and where. }
    Log.Add('');
    Log.Add('  live entities after the opening frames:');
    Log.Add('    slot  type  anim  screenX  screenY  spriteW  spriteH  vis');
    for I := 0 to 63 do
      if S.Pool.Alive[I] then
        Log.Add(Format('    %4d  %4d  %4d  %7d  %7d  %7d  %7d  %s',
          [I, S.Pool.Field(I, EF_TYPE), S.Pool.Field(I, EF_ANIM_ID),
           PixelOf(S.Pool.Field(I, EF_POS_X)),
           PixelOf(S.Pool.Field(I, EF_POS_Y)),
           S.Pool.Field(I, EF_EXTENT_X), S.Pool.Field(I, EF_EXTENT_Y),
           BoolToStr(S.Sprites.GetVisible(S.Pool.Field(I, EF_SPRITE)), True)]));
    Log.Add('');

    { --- the animated background tiles -------------------------------- }
    { The tick's whole effect is to repoint a tile id at another cell of the
      tileset, so every instance of that tile animates at once. Stage 1 is
      terrain 1, which declares two tracks: tile 7 cycling 7,8,9,8 and tile 17
      cycling 17,18,19,18, both at 8 ticks a frame. }
    if S.BgAnim = nil then
    begin
      Log.Add('  FAILED: terrain 1 built no background animator');
      Inc(Bad);
    end
    else
    begin
      Want(S.BgAnim.TrackCount = 2,
           Format('terrain 1 has %d tracks, want 2', [S.BgAnim.TrackCount]));
      Want(S.BgAnim.TrackTile(0) = 7,
           Format('track 0 animates tile %d, want 7', [S.BgAnim.TrackTile(0)]));

      { Nothing initialises the timer, so the FIRST tick already shows frame 0
        rather than waiting 8 frames. A timer that started at 8 would look
        almost right and be one frame late for ever. }
      S.BgAnim.Restart;
      StartX := S.Map.TileDef(7).Left;
      S.TickBackground;
      Want(S.Map.TileDef(7).Left = TileSrcX(7, 32, 10),
           'the first tick did not put tile 7 on its own cell');
      Want(S.BgAnim.TrackCursor(0) = 1,
           Format('after one tick the cursor is %d, want 1',
                  [S.BgAnim.TrackCursor(0)]));

      { Then it holds for 8 ticks, and the ninth advances. }
      for I := 1 to 7 do
        S.TickBackground;
      Want(S.BgAnim.TrackCursor(0) = 1,
           Format('the cursor moved after %d ticks, want it to hold for 8',
                  [8]));
      S.TickBackground;
      Want(S.BgAnim.TrackCursor(0) = 2,
           'the cursor did not advance on the eighth tick');
      Want(S.Map.TileDef(7).Left = TileSrcX(8, 32, 10),
           'tile 7 is not showing tile 8''s cell on frame 1');

      { And the cycle is 7,8,9,8 - four frames, then back to the start. }
      for I := 1 to 8 * 2 do
        S.TickBackground;
      Want(S.BgAnim.TrackCursor(0) = 0,
           Format('after four frames the cursor is %d, want it wrapped to 0',
                  [S.BgAnim.TrackCursor(0)]));
      Want(S.Map.TileDef(7).Left = TileSrcX(8, 32, 10),
           'the fourth frame of 7,8,9,8 is not tile 8');
      Log.Add(Format('background: %d tracks, tile %d cycling through its '
        + 'four frames', [S.BgAnim.TrackCount, S.BgAnim.TrackTile(0)]));
    end;

    { --- the camera follows, and only outside the dead zone ---------- }
    { The layer must not move while the player is inside the dead zone, and
      must move once it leaves. Rather than assume where the player is, walk
      a frame at a time and record the screen position at which the camera
      FIRST moves - that pins DEADZONE_RIGHT from behaviour instead of
      restating the constant. }
    StartX := PixelOf(S.Layer.OriginX);
    Moved := -1;
    S.Input.AxisX := 1;
    for I := 1 to 200 do
    begin
      S.Frame(GS);
      if (Moved < 0) and (PixelOf(S.Layer.OriginX) <> StartX) then
        Moved := PixelOf(S.Pool.Field(0, EF_POS_X));
    end;
    S.Input.AxisX := 0;
    Log.Add(Format('walking right: camera first moved at player x %d, '
      + 'ended player x %d camera x %d',
      [Moved, PixelOf(S.Pool.Field(0, EF_POS_X)),
       PixelOf(S.Layer.OriginX)]));

    Want(Moved >= 0,
         'the camera never followed - the player walked off the right of the '
         + 'screen instead of the view scrolling');
    { 177 written out, not DEADZONE_RIGHT: an expectation phrased in terms of
      the constant it is checking cannot fail. }
    Want(Moved >= 177,
         Format('the camera started scrolling at player x %d, before the '
           + 'dead zone edge at 177', [Moved]));
    { Once scrolling, the walk goes into the view and the player stays put. }
    Want(PixelOf(S.Pool.Field(0, EF_POS_X)) <= 180,
         Format('the player is at screen x %d - the scroll is not absorbing '
           + 'the walk', [PixelOf(S.Pool.Field(0, EF_POS_X))]));
    { How FAR it scrolls depends on the map - the player meets walls and
      gaps - so the check is that it scrolled at all and that it stopped
      inside the limit the original computes: (MapTilesX - 10) * TileW, read
      off Camera_ShouldScrollX at 0x00459C1C. }
    Want(PixelOf(S.Layer.OriginX) > StartX,
         Format('the view did not scroll: %d', [PixelOf(S.Layer.OriginX)]));
    Want(PixelOf(S.Layer.OriginX) <= (Map.MapWidth - 10) * Map.TileWidth,
         Format('the view scrolled to %d, past the map limit %d',
           [PixelOf(S.Layer.OriginX),
            (Map.MapWidth - 10) * Map.TileWidth]));

    { --- the scroll carry stops when the scroll does ------------------ }
    { Entity_UpdateAll adds LayerInfo.Delta to every non screen-space entity,
      which is how the world carries things along as the view moves.
      TFrm_main_AppIdle zeroes the delta at the top of EVERY frame, so the
      carry lasts exactly one frame. Leave it set and every entity drifts for
      ever after a single scroll - which looked like items flying off the top
      of the screen. Find a spawned entity, let go of the controls, and
      require it to stay where it is. }
    Slot := -1;
    for I := 1 to 63 do
      if S.Pool.Alive[I] then
        Slot := I;
    if Slot < 0 then
      Log.Add('  (nothing but the player is alive; the carry is not tested)')
    else
    begin
      StartX := S.Pool.PosX(Slot);
      StartY := S.Pool.PosY(Slot);
      for I := 1 to 60 do
        S.Frame(GS);
      Want((S.Pool.PosX(Slot) = StartX) and (S.Pool.PosY(Slot) = StartY),
           Format('entity %d drifted %d,%d sub-pixels over 60 idle frames '
             + 'after the view scrolled - the layer delta is not being '
             + 'cleared each frame',
             [Slot, S.Pool.PosX(Slot) - StartX, S.Pool.PosY(Slot) - StartY]));
      Want(S.Layer.DeltaX = 0,
           Format('the layer delta is still %d at the end of a frame',
                  [S.Layer.DeltaX]));
    end;

    { --- the event table places entities ----------------------------- }
    { Walk the camera over the whole map and count what gets placed. If the
      spawn walk were not wired, or the camera tile were computed wrongly,
      this would be zero while everything above still passed. }
    Placed := 0;
    for I := 0 to Map.MapWidth - 1 do
    begin
      S.SetCamera(I * 32, PixelOf(S.Layer.OriginY));
      S.Frame(GS);
      if S.Pool.LiveCount > Placed then
        Placed := S.Pool.LiveCount;
    end;
    LiveAfter := S.Pool.LiveCount;
    Log.Add(Format('camera swept across the map: at most %d entities live at '
      + 'once, %d at the end, %d sprites held',
      [Placed, LiveAfter, S.Sprites.LiveCount]));
    Want(Placed > 1,
         'sweeping the camera placed nothing - the event spawn walk is not '
         + 'connected, or the camera tile is wrong');

    { Every entity holds a sprite, and the pool is 256. If sprites were not
      released the sweep would exhaust it and later spawns would silently
      fail - which is what a screen slowly filling with stuck sprites looks
      like. One handle per live entity, exactly. }
    Want(S.Sprites.LiveCount = LiveAfter,
         Format('%d entities are holding %d sprites',
                [LiveAfter, S.Sprites.LiveCount]));

    { --- and the same for EVERY early room ---------------------------
      The sweep above only ever ran stage 1, which places no monsters at
      all - so it could pass while every later room came up empty, and
      that is exactly the symptom being chased. Rooms are reloaded the way
      a door does it: map, sprite frames, then BeginStage. What each room
      places is logged by type, because "nothing spawned" and "the wrong
      thing spawned" look identical from a count. }
    NoSprite := 0;
    Blind := '';
    FillChar(PlacedIn, SizeOf(PlacedIn), 0);
    FillChar(SurvivedIn, SizeOf(SurvivedIn), 0);
    for Stage := 1 to Stages.Count - 1 do
    begin
      if (Stage >= Stages.Count) or (Stages.Layer[Stage, 0] = LAYER_NONE) then
        Continue;
      if not Map.Load(GameDir, Stages.Layer[Stage, 0]) then
      begin
        Log.Add(Format('room %d: its map would not load', [Stage]));
        Inc(Bad);
        Continue;
      end;
      Frames.LoadSet(GameDir, Stages.SpriteSet[Stage]);
      S.SetFrames(Frames);
      InitNewGame(S.Player, 0);
      ApplySessionFlags(S.Player, 0);
      GS := GS_STAGE_BEGIN;
      S.LoadStageAssets(Stage);
      S.BeginStage(Stage, GS);

      Types := '';
      Placed := 0;
      { BOTH axes. Sweeping only X held the camera at whatever row the
        player happened to start on, and rooms 2 and 7 - whose events all sit
        at tile Y 5 - came up empty purely because that row was never in the
        window. A one-axis sweep of a two-axis window is not a sweep. }
      for J := 0 to Map.MapHeight - 1 do
      for I := 0 to Map.MapWidth - 1 do
      begin
        S.SetCamera(I * Map.TileWidth, J * Map.TileHeight);
        S.Frame(GS);
        for Slot := 1 to 255 do
          if S.Pool.Alive[Slot] then
          begin
            Inc(Placed);
            T := S.Pool.Field(Slot, EF_TYPE);
            if Pos(Format(' %d ', [T]), Types) = 0 then
              Types := Types + Format(' %d ', [T]);
            { The gap between "it exists" and "you can see it". An entity with
              no sprite handle updates, collides and is never drawn - which is
              precisely what a missing monster looks like from the player's
              side, and no placement count can see it. }
            if S.Pool.Field(Slot, EF_SPRITE) = SPRITE_NONE then
            begin
              Inc(NoSprite);
              if Pos(Format('t%d ', [T]), Blind) = 0 then
                Blind := Blind + Format('t%d ', [T]);
            end;
          end;
      end;
      { PLACED IS NOT ALIVE. The sweep above moves the camera every frame, so
        it counts each entity on the frame it spawns - a monster that its own
        handler kills on frame 2 is counted exactly the same as one that
        stands there waiting for you. So park the camera on each event in turn
        and let the room RUN, then ask which types are still there. A type that
        spawns everywhere and survives nowhere is invisible in every count
        taken so far, and is what "the monsters do not exist" looks like from
        the inside. }
      Surv := '';
      for EvI := 0 to S.Events.Count - 1 do
      begin
        if S.Events[EvI].Opcode = EVOP_ALWAYS then
          Continue;
        S.SetCamera((S.Events[EvI].TileX - 5) * Map.TileWidth,
                    (S.Events[EvI].TileY - 3) * Map.TileHeight);
        for K := 1 to 90 do
          S.Frame(GS);
        for Slot := 1 to 255 do
          if S.Pool.Alive[Slot] then
          begin
            T := S.Pool.Field(Slot, EF_TYPE);
            if Pos(Format(' %d ', [T]), Surv) = 0 then
              Surv := Surv + Format(' %d ', [T]);
          end;
      end;
      { Per-room this is NOISE, not a signal: a walking monster that wanders
        off the edge is SUPPOSED to be culled, so "did not survive here" is
        normal for anything mobile. What is not normal is a type that the
        shipped data places and that survives in NO room anywhere - that one
        cannot be explained by where it walked. Counted across the whole game
        and judged at the end. }
      for T := 0 to ENTITY_TYPE_COUNT - 1 do
      begin
        if Pos(Format(' %d ', [T]), Types) > 0 then
          Inc(PlacedIn[T]);
        if Pos(Format(' %d ', [T]), Surv) > 0 then
          Inc(SurvivedIn[T]);
      end;

      Log.Add(Format('room %d: %d events, %d placements, types%s | survives%s',
                     [Stage, S.Events.Count, Placed, Types, Surv]));
      Want(S.Events.Count = 0 = (Placed = 0),
           Format('room %d loaded %d events and placed %d entities - a room '
             + 'with events that places nothing is the missing-monster bug',
             [Stage, S.Events.Count, Placed]));
    end;
    { A LOG, NOT AN ASSERTION, and the reason is worth keeping. The obvious
      reading of this list - "these types spawn and are instantly lost" - is
      wrong for most of it. Type 3 heads the list at 45 rooms and is a PUFF:
      EntityUpdate_Type03 animates it through T3_FRAMES and then destroys it
      itself. Types 4..7 share EffectLatch, which arms a death timer on their
      first update. Short-lived effects self-destructing is the behaviour, not
      a defect, and asserting on it fails the gate on correct code.

      The counter is also not what its name suggests: it counts types seen
      ALIVE during the sweep, which includes effects spawned by other entities'
      handlers, not only what the event table places.

      It stays because it did answer the question it was written for - the
      early rooms the bug was reported against place monsters AND keep them,
      types 21 and 29 among them - and because a type that is genuinely lost
      would appear here first. Read it, do not gate on it. }
    for T := 0 to ENTITY_TYPE_COUNT - 1 do
      if (PlacedIn[T] > 0) and (SurvivedIn[T] = 0) then
        Log.Add(Format('  note: type %d seen alive in %d rooms, in none of '
                       + 'them after 90 frames', [T, PlacedIn[T]]));

    Log.Add(Format('all %d rooms swept; %d placements held no sprite%s',
      [Stages.Count - 1, NoSprite,
       Copy(' (types ' + Blind + ')', 1, 200 * Ord(NoSprite > 0))]));
    { Not every blind entity is a bug: types 18, 20 and 32 are the inert
      markers - two have no handler arm at all and the third updates while
      drawing nothing. Anything ELSE coming up blind is a monster nobody can
      see, so the assertion is on the type list, not on the count. }
    for T := 0 to ENTITY_TYPE_COUNT - 1 do
      if (Pos(Format('t%d ', [T]), Blind) > 0)
         and (T <> 18) and (T <> 20) and (T <> 32) then
        Want(False,
             Format('type %d is placed by the shipped data and holds no '
               + 'sprite handle - it updates, collides, and is never drawn',
               [T]));
  finally
    S.Free;
    Frames.Free;
    Map.Free;
    Stages.Free;
  end;

  Inc(Bad, TestDialogue(Log, GameDir));
  Inc(Bad, TestConfirmAndGameOver(Log));
  Inc(Bad, TestEnding(Log));
  Inc(Bad, TestContinueLoadsSave(Log, GetTempDir));
  Inc(Bad, TestPauseFlow(Log));
  Inc(Bad, TestTypewriter(Log, GameDir));
  Inc(Bad, TestEventDelay(Log, GameDir));
  Inc(Bad, TestSpriteOrder(Log));
  Inc(Bad, TestOptionTables(Log, GameDir));
  Inc(Bad, TestDisableDestroys(Log, GameDir));
  Inc(Bad, TestKillTileWiring(Log));
  Inc(Bad, TestMessageLoop(Log, GameDir));

  Result := Bad;
  Log.Add('');
  if Result = 0 then
    Log.Add('OK - a stage begins, frames run, and the parts reach each other')
  else
    Log.Add('FAILED');
end;

end.
