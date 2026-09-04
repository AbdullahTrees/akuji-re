{ Ending screen for game state 150, entered by event sub-op 80 (`soulget`).
  It is the results screen, and it is where the game's two persistent unlock
  sets are earned: the two extra doors into the last map, and the seven
  gallery entries. Both are banked at once, in EndingApplyUnlocks.

  Presentation is expressed as a phase machine; the form host draws pictures,
  credits, stills, and results. }

unit Ending;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, GameState, PlayerState;

const
  { Total number of collectible mana stones. }
  ENDING_TOTAL = 400;

  { Completion and time thresholds used to calculate rank. }
  RANK_PCT_1 = 50;
  RANK_PCT_2 = 70;
  RANK_PCT_3 = 90;
  RANK_TIME  = 1800;        { 0x708 seconds - thirty minutes }

  { Progress[1186..1192], the seven gallery flags. 1185 and 1194 are the two
    doors, so this is the middle of a run of nine. }
  GALLERY_FIRST_FLAG = 1186;
  GALLERY_COUNT      = 7;

  { AutoLoadMidis[14] is midi\end05, which the sequence plays under itself. }
  ENDING_MIDI = 14;

  { Phase 1: six one-based slides. }
  ENDING_SLIDES = 6;

  { bmp\ed%.3d.bmp, or -1 for a slide that is text only. }
  ENDING_IMAGE: array[0..ENDING_SLIDES - 1] of Integer = (1, 2, 3, 3, -1, 4);

  { Indexes ENDING_TEXT; the slide's second line is the entry after it. }
  ENDING_TEXT_ID: array[0..ENDING_SLIDES - 1] of Integer = (0, 2, 4, 6, 8, 10);

  ENDING_SECONDS: array[0..ENDING_SLIDES - 1] of Integer = (8, 8, 2, 8, 4, 8);
  ENDING_SECONDS_SCALE = $3C;   { the table is in seconds; Timer is in frames }

  ENDING_TEXT: array[0..11] of string = (
    '    Light covered Akuji as',
    '    he broke the last seal... ',
    ' He''s transforming back!',            '',
    'What''s going on?!?',                  '',
    'His horns are all that grew..!',       '',
    '  Akuji learned a lesson. ',           '',
    'Disgusted, he decides to  ',
    'not cause mischief anymore. ');

  { Slides 4 and 6 hold until their own music ENDS instead of counting down,
    which is why those two are started UNLOOPED. }
  ENDING_SLIDE_WAIT_A = 4;
  ENDING_SLIDE_WAIT_B = 6;
  ENDING_MIDI_SLIDE_1 = 10;
  ENDING_MIDI_SLIDE_4 = 12;
  ENDING_MIDI_SLIDE_6 = 13;
  ENDING_SLIDE_STOP_AT = 3;   { the slide that stops midi 10 }

  { Timer sentinel used while the final slide waits for its fade-out. }
  ENDING_WAIT_FADE = 999;

  { --- Phase 2, the staff roll. Ending_ShowPicture(0x140, 0xF0, 'ed005.bmp')
    puts one full-screen sheet up and the roll scrolls SEVENTEEN crops of it
    past the camera; nothing else is drawn.

    Each entry moves up ONE pixel every third frame - Credits_Tick counts to
    2 and then advances every entry at once - and is drawn centred, at
    (0x140 - Width) div 2, while -Height <= Y < 0xF1. The roll is over when
    the LAST entry reaches the screen's vertical centre, which is why the
    trailing entry sits so far down the sheet. }
  CREDITS_PICTURE = 'ed005.bmp';
  CREDITS_TICKS = 2;          { advance when the counter passes this }
  CREDITS_STEP = 1;           { pixels per advance }
  CREDITS_BOTTOM = $F1;       { one past the last row that still draws }
  CREDITS_CENTRE_Y = $78;     { the last entry's finish line, less half its height }
  CREDITS_ENTRIES = 17;
  CREDITS_SCREEN_W = $140;    { the roll centres against the whole screen }

  { Y, Height, Width, SrcY, SrcX - the argument order Surface_AppendEntry
    stores them in, which is not the order it takes them. }
  CREDITS_LAYOUT: array[0..CREDITS_ENTRIES - 1, 0..4] of Integer = (
    ($0F0, $10, $B0, $000, $000),
    ($130, $10, $50, $000, $0B0),
    ($140, $10, $50, $010, $0C0),
    ($160, $4B, 100, $040, $000),
    ($1F0, $10, $40, $000, $100),
    ($200, $10, $50, $010, $0C0),
    ($220, $4B, 100, $040, 100),
    ($2B0, $10, $40, $010, $030),
    ($2C0, $10, $30, $010, $110),
    ($2E0, $4B, 100, $040, 200),
    ($370, $10, $50, $010, $070),
    ($380, $10, $40, $020, $000),
    ($3A0, $4B, 100, $08B, $000),
    ($430, $10, $30, $010, $000),
    ($440, $10, $50, $010, $0C0),
    ($460, $4B, 100, $08B, 100),
    ($550, $10, $10, $030, $000));

  CREDITS_Y = 0;  CREDITS_H = 1;  CREDITS_W = 2;
  CREDITS_SY = 3; CREDITS_SX = 4;

  { --- Phases 3 and 4, the four stills. Each is the SAME crop of the phase-2
    sheet grown to the right - top and bottom fixed, only the right edge moves
    - held a second each and drawn at one place, so the picture fills in
    rather than changing. Phase 4 then holds the widest for 600 frames. }
  STILL_COUNT = 4;
  STILL_SRC_LEFT = $40;  STILL_SRC_TOP = $20;  STILL_SRC_BOTTOM = $40;
  STILL_SRC_RIGHT: array[0..STILL_COUNT - 1] of Integer =
    ($5C, $7A, $93, $B3);
  STILL_X = $66;  STILL_Y = $68;
  STILL_FRAMES = $3C;         { one second each }
  STILL_HOLD_FRAMES = 600;    { phase 4, on the widest crop }
  SND_STILL_STEP = $0E;
  SND_STILL_LAST = $0C;       { on the one that ends phase 3 }
  RESULTS_MIDI = 6;

  { --- Phase 5, the results screen. One line a second over Option.bmp. }
  RESULTS_PICTURE = 'Option.bmp';
  RESULTS_LINE_FRAMES = $3C;
  RESULTS_LAST_LINE = 6;
  SND_RESULT_LINE = 1;
  SND_RESULT_RANK = $2C;

  RESULT_TITLE = '---- RESULT ----';
  RESULT_RULE  = '----------------';
  RESULT_TITLE_X = $60;  RESULT_TITLE_Y = $30;  RESULT_RULE_Y = $B8;
  RESULT_LABEL_X = $68;  RESULT_VALUE_X = $98;
  RESULT_TIME_Y  = $50;  RESULT_MANA_Y  = $60;
  RESULT_TIME_LABEL = 'TIME';
  RESULT_MANA_LABEL = 'MANA';
  { Game_DrawText's variant: 2 for the labels, 0 for the numbers. }
  RESULT_LABEL_VARIANT = 2;
  RESULT_VALUE_VARIANT = 0;

  { The seven gallery icons, off surface 4. A lit one is its own 0x20 cell;
    an unlocked-nothing one is the single dark cell at 0x120. }
  GALLERY_X0 = $28;   GALLERY_STEP = $22;   GALLERY_Y = $78;
  GALLERY_CELL = $20;
  GALLERY_SRC_TOP = $A0;  GALLERY_SRC_BOTTOM = $C0;
  GALLERY_LIT_COL0 = 2;      { lit icon i is cell (i + 2) }
  GALLERY_DARK_X = $120;
  GALLERY_SURFACE = 4;

  { EndingRank returns an index into these five labels. }
  RANK_NAMES: array[0..4] of string =
    ('RANK C', 'RANK B', 'RANK A', 'RANK S', 'RANK SS');
  RANK_X = $88;  RANK_Y = $A8;
  { The rank line flickers: its variant is the frame timer mod 3. }
  RANK_VARIANTS = 3;

  { Confirm parks this in Step and the screen waits for its fade, exactly as
    the last slide of phase 1 parks it in Timer. }
  RESULTS_LEAVING = 999;

  { Kbgm_StopOrFade's argument. }
  MUSIC_STOP_HARD = 0;
  MUSIC_STOP_FADE = 2;
  { The fader step each part of the ending asks for. }
  FADE_STEP_SLIDES = 4;
  FADE_STEP_RESULTS = 2;

  { Where the host puts the slide: the picture at (0x28, 8) at 240x180, and
    the two lines left-aligned at x 0x38. }
  ENDING_PIC_X = $28;    ENDING_PIC_Y = 8;
  ENDING_PIC_W = $F0;    ENDING_PIC_H = $B4;
  ENDING_LINE_X  = $38;
  ENDING_LINE1_Y = 200;
  ENDING_LINE2_Y = $D8;
  { Game_RGB(0xFF, 0xDF, 0xA3) over Game_RGB(0x7E, 0x5B, 0x35). }
  ENDING_TEXT_FILL    = $A3DFFF;
  ENDING_TEXT_OUTLINE = $355B7E;
  { Numbered ending pictures share this filename pattern. }
  ENDING_PICTURE_FMT = 'ed%.3d.bmp';
  { Delphi treats the zero in '%03d' as part of the width, not a zero-padding
    flag, so percentages are padded with spaces. }
  ENDING_TIME_FMT    = '%.2d:%.2d:%.2d';
  ENDING_PERCENT_FMT = '%03d%%';

type
  { Presentation callbacks supplied by the host form. }
  TEndingPicture = procedure(Index: Integer) of object;
  TEndingMusic = procedure(Track: Integer; Loop: Boolean) of object;

{ Completion percentage including the two x87 rounding edge cases below. }
function EndingPercent(Counter: Integer): Integer;

const
  { Extended-precision intermediate rounding makes these two counters display
    one percentage point low. Neither edge case crosses a rank threshold. }
  ENDING_PCT_DEVIATIONS: array[0..1] of Integer = (212, 236);

{ Calculate the rank used by the results display and door unlocks. }
function EndingRank(Counter, ElapsedSec: Integer): Integer;

{ Apply the persistent door and gallery rewards earned by the results screen. }
procedure EndingApplyUnlocks(var S: TGameSettings; const P: TPlayerState);

{ The two strings the screen prints beside the rank. }
function EndingTimeText(ElapsedSec: Integer): string;
function EndingPercentText(Counter: Integer): string;

type
  { Six-phase ending state machine. ScreenPhase selects the phase; Step and
    Timer track progress within it. }
  { Asked, not handed in - the same reason the game-over screen asks. Phase 1
    starts a track and then waits for it in a later frame of the same run. }
  TEndingQuery = function: Boolean of object;
  { Phases 2 and 5 name their picture outright rather than numbering it -
    Ending_ShowPicture takes a filename - so they cannot go through
    OnPicture's ed%.3d.bmp. }
  TEndingPictureNamed = procedure(const Name: string) of object;
  { The sound effects the stills and the result lines tick over on. }
  TEndingMusicCue = procedure(Id: Integer) of object;
  { Kbgm_StopOrFade's argument: 0 stops at once, 2 fades. Phase 4 and the
    results screen both fade, and phase 4 then WAITS for the track to finish
    falling - a hard stop there makes that wait instant. }
  TEndingMusicStop = procedure(FadeSeconds: Integer) of object;
  { The caller sets the fader's step before starting it, so this carries it. }
  TEndingFade = procedure(Step: Integer; FadeOut: Boolean) of object;

  TEndingScreen = class
  private
    FOnPicture: TEndingPicture;
    FOnMusic: TEndingMusic;
    FOnStopMusic: TEndingMusicStop;
    FOnPictureNamed: TEndingPictureNamed;
    FOnSound: TEndingMusicCue;
    FOnConfirm: TEndingQuery;
    FOnFade: TEndingFade;
    FOnMusicPlaying: TEndingQuery;
    FOnFadeBusy: TEndingQuery;

  public
    { Step within the current phase. }
    Step: Integer;
    { Frame timer shared by the timed ending phases. }
    Timer: Integer;

    { The staff roll's live Y for each entry; everything else about an entry
      is static and lives in CREDITS_LAYOUT. }
    CreditY: array[0..CREDITS_ENTRIES - 1] of Integer;
    CreditTicks: Integer;
    CreditsDone: Boolean;

    procedure Update(var S: TGameSettings; const P: TPlayerState;
                     var AGameState: Integer);

    { What the host draws for the current slide. Image is -1 when the slide
      carries no picture; Line 0 and 1 are its two rows of text. }
    function SlideImage: Integer;
    function SlideLine(N: Integer): string;

    { True while entry I is on screen. The host draws CREDITS_LAYOUT's crop of
      the phase-2 picture at (CreditX(I), CreditY[I]). }
    function CreditOnScreen(I: Integer): Boolean;
    function CreditX(I: Integer): Integer;
    procedure CreditsTick;

    { Phases 3 and 4: the right edge of the crop to show, or -1 for none. }
    function StillRight: Integer;
    { Phase 5: how many result lines have been revealed, and the rank text. }
    function ResultsRevealed: Integer;
    function RankName(Counter, ElapsedSec: Integer): string;

    property OnPicture: TEndingPicture read FOnPicture write FOnPicture;
    property OnPictureNamed: TEndingPictureNamed
      read FOnPictureNamed write FOnPictureNamed;
    property OnSound: TEndingMusicCue read FOnSound write FOnSound;
    property OnConfirm: TEndingQuery read FOnConfirm write FOnConfirm;

    property OnMusicPlaying: TEndingQuery
      read FOnMusicPlaying write FOnMusicPlaying;
    property OnFadeBusy: TEndingQuery read FOnFadeBusy write FOnFadeBusy;
    property OnFade: TEndingFade read FOnFade write FOnFade;
    property OnMusic: TEndingMusic read FOnMusic write FOnMusic;
    property OnStopMusic: TEndingMusicStop read FOnStopMusic write FOnStopMusic;
  end;

implementation

function EndingPercent(Counter: Integer): Integer;
var
  DeviationIndex: Integer;
begin
  { Name the two platform-rounding exceptions rather than relying on the host
    floating-point implementation. }
  Result := Counter div 4;
  for DeviationIndex := 0 to High(ENDING_PCT_DEVIATIONS) do
    if Counter = ENDING_PCT_DEVIATIONS[DeviationIndex] then
      Dec(Result);
end;

function EndingRank(Counter, ElapsedSec: Integer): Integer;
var
  CompletionPercent: Integer;
begin
  CompletionPercent := EndingPercent(Counter);
  Result := 0;
  if CompletionPercent > RANK_PCT_1 then Result := 1;
  if CompletionPercent > RANK_PCT_2 then Result := 2;
  if CompletionPercent > RANK_PCT_3 then Result := 3;
  { Checked AFTER the percentage gates and overriding them, so a fast run
    ranks top however little it collected. }
  if ElapsedSec <= RANK_TIME then Result := 4;
end;

procedure EndingApplyUnlocks(var S: TGameSettings; const P: TPlayerState);
var
  Rank, GalleryIndex: Integer;
begin
  Rank := EndingRank(P.Counter, P.ElapsedSec);
  if Rank >= 3 then
    S.ExtraDoor1 := 1;
  if Rank >= 4 then
  begin
    S.ExtraDoor1 := 1;
    S.ExtraDoor2 := 1;
  end;

  { One gallery byte per progress flag, in order, and only ever set - a
    previously unlocked entry is never taken away by a worse run. }
  for GalleryIndex := 0 to GALLERY_COUNT - 1 do
    if P.Progress[GALLERY_FIRST_FLAG + GalleryIndex] <> 0 then
      S.GalleryUnlocked[GalleryIndex] := 1;
end;

function EndingTimeText(ElapsedSec: Integer): string;
begin
  Result := Format(ENDING_TIME_FMT,
    [ElapsedSec div 3600, (ElapsedSec div 60) mod 60, ElapsedSec mod 60]);
end;

function EndingPercentText(Counter: Integer): string;
begin
  Result := Format(ENDING_PERCENT_FMT, [EndingPercent(Counter)]);
end;

procedure TEndingScreen.CreditsTick;
var
  CreditIndex, LastCredit: Integer;
  Advance: Boolean;
begin
  Advance := False;
  if not CreditsDone then
  begin
    Inc(CreditTicks);
    if CreditTicks > CREDITS_TICKS then
    begin
      Advance := True;
      CreditTicks := 0;
    end;
  end;

  for CreditIndex := 0 to CREDITS_ENTRIES - 1 do
  begin
    if Advance then
      Dec(CreditY[CreditIndex], CREDITS_STEP);
    { This compatibility branch is unreachable because the roll completes when
      the final entry reaches the center, before it moves above the screen. }
    if (CreditIndex = CREDITS_ENTRIES - 1)
    and (CreditY[CreditIndex] < -CREDITS_LAYOUT[CreditIndex][CREDITS_H]) then
      Advance := True;
  end;

  LastCredit := CREDITS_ENTRIES - 1;
  if CreditY[LastCredit] < CREDITS_CENTRE_Y
     - CREDITS_LAYOUT[LastCredit][CREDITS_H] div 2 then
    CreditsDone := True;
end;

function TEndingScreen.CreditOnScreen(I: Integer): Boolean;
begin
  Result := (I >= 0) and (I < CREDITS_ENTRIES)
        and (CreditY[I] >= -CREDITS_LAYOUT[I][CREDITS_H])
        and (CreditY[I] < CREDITS_BOTTOM);
end;

function TEndingScreen.CreditX(I: Integer): Integer;
begin
  Result := 0;
  if (I < 0) or (I >= CREDITS_ENTRIES) then
    Exit;
  Result := (CREDITS_SCREEN_W - CREDITS_LAYOUT[I][CREDITS_W]) div 2;
end;

function TEndingScreen.SlideImage: Integer;
begin
  if (Step < 1) or (Step > ENDING_SLIDES) then
    Exit(-1);
  Result := ENDING_IMAGE[Step - 1];
end;

function TEndingScreen.SlideLine(N: Integer): string;
var
  TextIndex: Integer;
begin
  Result := '';
  if (Step < 1) or (Step > ENDING_SLIDES) or (N < 0) or (N > 1) then
    Exit;
  TextIndex := ENDING_TEXT_ID[Step - 1] + N;
  if (TextIndex >= 0) and (TextIndex <= High(ENDING_TEXT)) then
    Result := ENDING_TEXT[TextIndex];
end;

procedure TEndingScreen.Update(var S: TGameSettings; const P: TPlayerState;
                               var AGameState: Integer);
var
  CreditIndex: Integer;
begin
  if ScreenPhase = 0 then
  begin
    ScreenPhase := 1;
    Step := 0;
    Timer := 0;
    if Assigned(FOnStopMusic) then
      FOnStopMusic(MUSIC_STOP_HARD);
    Exit;
  end;

  if ScreenPhase = 1 then
  begin
    { Waiting on the fade out that follows the last slide. }
    if Timer = ENDING_WAIT_FADE then
    begin
      if not (Assigned(FOnFadeBusy) and FOnFadeBusy()) then
      begin
        if Assigned(FOnStopMusic) then
          FOnStopMusic(MUSIC_STOP_HARD);
        ScreenPhase := 2;
        Step := 0;
        Timer := 0;
      end;
      Exit;
    end;

    { Slides 4 and 6 do not count down at all - they end when their track
      does, which is why the countdown is skipped for them rather than the
      test being widened. }
    if (Step <> ENDING_SLIDE_WAIT_A) and (Step <> ENDING_SLIDE_WAIT_B) then
      Dec(Timer);

    if (Timer < 1)
    or (not (Assigned(FOnMusicPlaying) and FOnMusicPlaying())
        and ((Step = ENDING_SLIDE_WAIT_A) or (Step = ENDING_SLIDE_WAIT_B))) then
    begin
      Inc(Step);
      { Do not read a duration after advancing past the final slide. }
      if Step <= ENDING_SLIDES then
        Timer := ENDING_SECONDS[Step - 1] * ENDING_SECONDS_SCALE;

      if Step = 1 then
        if Assigned(FOnMusic) then FOnMusic(ENDING_MIDI_SLIDE_1, True);
      if Step = ENDING_SLIDE_STOP_AT then
        if Assigned(FOnStopMusic) then FOnStopMusic(MUSIC_STOP_HARD);
      { Unlooped, so that the slide can wait for it to finish. }
      if Step = ENDING_SLIDE_WAIT_A then
        if Assigned(FOnMusic) then FOnMusic(ENDING_MIDI_SLIDE_4, False);
      if Step = ENDING_SLIDE_WAIT_B then
        if Assigned(FOnMusic) then FOnMusic(ENDING_MIDI_SLIDE_6, False);

      if Step > ENDING_SLIDES then
      begin
        { Pinned on the last slide, which stays on screen through the fade. }
        Step := ENDING_SLIDES;
        Timer := ENDING_WAIT_FADE;
        if Assigned(FOnFade) then
          FOnFade(FADE_STEP_SLIDES, True);
        Exit;
      end;

      if Assigned(FOnPicture) then
        FOnPicture(SlideImage);
    end;
    Exit;
  end;

  if ScreenPhase = 2 then
  begin
    if Step = 0 then
    begin
      Step := 1;
      if Assigned(FOnPictureNamed) then
        FOnPictureNamed(CREDITS_PICTURE);
      for CreditIndex := 0 to CREDITS_ENTRIES - 1 do
        CreditY[CreditIndex] := CREDITS_LAYOUT[CreditIndex][CREDITS_Y];
      CreditTicks := 0;
      CreditsDone := False;
      if Assigned(FOnMusic) then
        FOnMusic(ENDING_MIDI, True);
    end;

    CreditsTick;
    if CreditsDone then
    begin
      ScreenPhase := 3;
      Step := 0;
      Timer := 0;
    end;
    Exit;
  end;

  { Phase 3: four stills, one a second. Step 4 is never drawn here - reaching
    it hands over to phase 4, which shows that crop itself. }
  if ScreenPhase = 3 then
  begin
    Inc(Timer);
    if Timer > STILL_FRAMES then
    begin
      Timer := 0;
      if Step < STILL_COUNT then
      begin
        Inc(Step);
        if Step = STILL_COUNT then
        begin
          if Assigned(FOnSound) then FOnSound(SND_STILL_LAST);
          ScreenPhase := 4;
          Step := 0;
          Timer := 0;
        end
        else
          if Assigned(FOnSound) then FOnSound(SND_STILL_STEP);
      end;
    end;
    Exit;
  end;

  { Phase 4: hold the widest crop, fade the music out, and leave when it has
    actually stopped. }
  if ScreenPhase = 4 then
  begin
    if Step = 0 then
    begin
      Inc(Timer);
      if Timer > STILL_HOLD_FRAMES then
      begin
        Step := 1;
        Timer := 0;
        { A FADE, not a stop - the wait below is for it to finish falling. }
        if Assigned(FOnStopMusic) then FOnStopMusic(MUSIC_STOP_FADE);
      end;
    end;
    if (Step = 1) and not (Assigned(FOnMusicPlaying) and FOnMusicPlaying()) then
    begin
      ScreenPhase := 5;
      Step := 0;
      Timer := 0;
      if Assigned(FOnMusic) then FOnMusic(RESULTS_MIDI, True);
    end;
    Exit;
  end;

  { Phase 5: results and persistent unlocks. Rewards are banked once when the
    screen appears. }
  if ScreenPhase = 5 then
  begin
    if Step = 0 then
    begin
      if Assigned(FOnFade) then FOnFade(FADE_STEP_RESULTS, False);
      if Assigned(FOnPictureNamed) then FOnPictureNamed(RESULTS_PICTURE);
      Step := 1;
      EndingApplyUnlocks(S, P);
    end;

    Inc(Timer);
    if (Timer > RESULTS_LINE_FRAMES) then
    begin
      Timer := 0;
      if (Step < RESULTS_LAST_LINE) and (Step <> RESULTS_LEAVING) then
      begin
        Inc(Step);
        if Assigned(FOnSound) then
          if Step = RESULTS_LAST_LINE then FOnSound(SND_RESULT_RANK)
          else FOnSound(SND_RESULT_LINE);
      end;
    end;

    { Confirm is only offered once the rank is up. }
    if (Step >= RESULTS_LAST_LINE) and (Step <> RESULTS_LEAVING)
    and (Assigned(FOnConfirm) and FOnConfirm()) then
    begin
      Step := RESULTS_LEAVING;
      if Assigned(FOnFade) then FOnFade(FADE_STEP_RESULTS, True);
    end;

    if (Step = RESULTS_LEAVING)
    and not (Assigned(FOnFadeBusy) and FOnFadeBusy()) then
    begin
      { The music FADES here and the screen fades back IN, so the title
        arrives out of a dissolve rather than a cut. }
      if Assigned(FOnStopMusic) then FOnStopMusic(MUSIC_STOP_FADE);
      if Assigned(FOnFade) then FOnFade(FADE_STEP_RESULTS, False);
      ScreenPhase := 0;
      AGameState := GS_TITLE_INIT;
    end;
  end;
end;

function TEndingScreen.StillRight: Integer;
begin
  Result := -1;
  if (ScreenPhase = 4) then
    Exit(STILL_SRC_RIGHT[STILL_COUNT - 1]);
  if (ScreenPhase = 3) and (Step >= 1) and (Step <= STILL_COUNT) then
    Result := STILL_SRC_RIGHT[Step - 1];
end;

function TEndingScreen.ResultsRevealed: Integer;
begin
  if Step = RESULTS_LEAVING then
    Exit(RESULTS_LAST_LINE);
  Result := Step;
end;

function TEndingScreen.RankName(Counter, ElapsedSec: Integer): string;
var
  Rank: Integer;
begin
  Rank := EndingRank(Counter, ElapsedSec);
  if (Rank < 0) or (Rank > High(RANK_NAMES)) then
    Rank := 0;
  Result := RANK_NAMES[Rank];
end;

end.
