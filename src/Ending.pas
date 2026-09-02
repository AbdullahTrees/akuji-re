{ The ending screen - GameState 150, entered by event sub-op 80, `soulget`.
  It is the results screen, and it is where the game's two persistent unlock
  sets are earned: the two extra doors into the last map, and the seven
  gallery entries. Both are banked at once, in EndingApplyUnlocks.

  The screen itself is a long presentation - pictures from bmp.qda, seventeen
  sprite registrations, a staff roll over midi\end05 - and all of that belongs
  to the DirectDraw component this project replaces wholesale. What is here is
  the part that is the game's: the phase machine, the arithmetic and the flags.
  The host draws. }

unit Ending;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, GameState, PlayerState;

const
  { 0x00464420 and 0x00464424, the two floats the percentage is built from.
    So 400 is the game's collectible total, which also settles the right-hand
    side of HUD_Draw's "%3d/%-3d". }
  ENDING_TOTAL = 400;

  { The three percentage gates and the time gate, from 0x00463E39. }
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

  { --- Phase 1, the slide show. Six slides, indexed 1..6, so entry 0 is slide
    one. Both extents are pinned from outside: ENDING_SECONDS' seventh int
    reads as a string pointer, and ENDING_TEXT's twelfth entry is 'EASY',
    which Title.pas already records at 0x00452308 as the level names. }
  ENDING_SLIDES = 6;

  ENDING_IMAGE_ADDR = $00468FDC;
  { bmp\ed%.3d.bmp, or -1 for a slide that is text only. }
  ENDING_IMAGE: array[0..ENDING_SLIDES - 1] of Integer = (1, 2, 3, 3, -1, 4);

  ENDING_TEXT_ID_ADDR = $00468FF4;
  { Indexes ENDING_TEXT; the slide's second line is the entry after it. }
  ENDING_TEXT_ID: array[0..ENDING_SLIDES - 1] of Integer = (0, 2, 4, 6, 8, 10);

  ENDING_SECONDS_ADDR = $0046900C;
  ENDING_SECONDS: array[0..ENDING_SLIDES - 1] of Integer = (8, 8, 2, 8, 4, 8);
  ENDING_SECONDS_SCALE = $3C;   { the table is in seconds; Timer is in frames }

  ENDING_TEXT_ADDR = $00469024;
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

  { Timer holds this instead of a count while the last slide waits on its fade
    out. 999 is a sentinel in the original too, in both the slide and the
    timer, and means "waiting on a fade" rather than a number of frames. }
  ENDING_WAIT_FADE = 999;

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
  { bmp\ed%.3d.bmp - 0x00464450 loose, 0x00464468 inside the archive. }
  ENDING_PICTURE_FMT = 'ed%.3d.bmp';
  { 0x00464410 and 0x00464440. The second one is a trap for anyone reading it
    as C: Delphi's Format has no zero-pad flag, so '%03d' is a WIDTH of three
    padded with SPACES. The percentage prints as ' 52%', not '052%'. }
  ENDING_TIME_FMT    = '%.2d:%.2d:%.2d';
  ENDING_PERCENT_FMT = '%03d%%';

type
  { What the host has to supply. Each is one call the original makes into the
    component layer, named for what it means rather than for the component. }
  TEndingPicture = procedure(Index: Integer) of object;
  TEndingMusic = procedure(Track: Integer; Loop: Boolean) of object;
  TEndingStopMusic = procedure of object;

{ The completion percentage, INCLUDING the two places the original's x87
  route comes out a point low - see the header. }
function EndingPercent(Counter: Integer): Integer;

const
  { The only two counters at which the original disagrees with Counter div 4.
    It divides, rounds to 64 bits, multiplies and rounds again, and at these
    two the result lands one ulp below the integer - then 0x00402948 loads
    control word 0x1D6C, rounding toward zero, so it truncates rather than
    rounding back up and 53% prints as 52%. Delphi's Round would not have.

    Neither crosses a rank gate, so only the printed number is affected. Found
    with exact rationals, as tools/x87_sim.py does for ScaleByPercent; the
    self-test walks all 401 counters against that model. }
  ENDING_PCT_DEVIATIONS: array[0..1] of Integer = (212, 236);

{ 0x00463E39. The rank, and the only thing the door unlocks depend on. }
function EndingRank(Counter, ElapsedSec: Integer): Integer;

{ 0x00463E5C and 0x00463D88. Both sets of persistent flags, in one place
  because they are earned on one screen and written to one file. }
procedure EndingApplyUnlocks(var S: TGameSettings; const P: TPlayerState);

{ The two strings the screen prints beside the rank. }
function EndingTimeText(ElapsedSec: Integer): string;
function EndingPercentText(Counter: Integer): string;

type
  { 0x00463624. The sequence itself, reduced to what is not presentation.

    Its phases run on GameState.ScreenPhase, the counter it shares with the
    game-over screen and the message box, and its step within a phase on a
    second global at 0x0046D298.

    PHASE 1 IS THE SLIDE SHOW, and it is easy to miss: the original tests the
    phase 0, 2, 3, 4, 5, else, so phase 1 is the unlabelled `else` at the
    BOTTOM of the function rather than where you would look for it. Step is
    the slide there and Timer counts its frames down.

    Phases 2, 3 and 4 - the credits, the four stills and the hold - are
    presentation over the component this project replaces, so only their
    bookkeeping is here. notes/ending_sequence.md has all six. }
  { Asked, not handed in - the same reason the game-over screen asks. Phase 1
    starts a track and then waits for it in a later frame of the same run. }
  TEndingQuery = function: Boolean of object;

  TEndingScreen = class
  private
    FOnPicture: TEndingPicture;
    FOnMusic: TEndingMusic;
    FOnStopMusic: TEndingStopMusic;
    FOnMusicPlaying: TEndingQuery;
    FOnFadeBusy: TEndingQuery;
    FOnStartFade: TEndingStopMusic;
  public
    { 0x0046D298, the step inside a phase. }
    Step: Integer;
    { 0x0046D174, the frame timer the staff roll and the rank line read. }
    Timer: Integer;

    procedure Update(var S: TGameSettings; const P: TPlayerState;
                     var AGameState: Integer);

    { What the host draws for the current slide. Image is -1 when the slide
      carries no picture; Line 0 and 1 are its two rows of text. }
    function SlideImage: Integer;
    function SlideLine(N: Integer): string;

    property OnPicture: TEndingPicture read FOnPicture write FOnPicture;
    property OnMusicPlaying: TEndingQuery
      read FOnMusicPlaying write FOnMusicPlaying;
    property OnFadeBusy: TEndingQuery read FOnFadeBusy write FOnFadeBusy;
    property OnStartFade: TEndingStopMusic
      read FOnStartFade write FOnStartFade;
    property OnMusic: TEndingMusic read FOnMusic write FOnMusic;
    property OnStopMusic: TEndingStopMusic read FOnStopMusic write FOnStopMusic;
  end;

implementation

function EndingPercent(Counter: Integer): Integer;
var
  I: Integer;
begin
  { Counter div 4 is the arithmetic the expression MEANS. It is not what the
    original computes at two of the 401 counters, so those two are named
    rather than recomputed - doing the division in Double here would land
    somewhere else again, and somewhere else is not the original either. }
  Result := Counter div 4;
  for I := 0 to High(ENDING_PCT_DEVIATIONS) do
    if Counter = ENDING_PCT_DEVIATIONS[I] then
      Dec(Result);
end;

function EndingRank(Counter, ElapsedSec: Integer): Integer;
var
  Pct: Integer;
begin
  Pct := EndingPercent(Counter);
  Result := 0;
  if Pct > RANK_PCT_1 then Result := 1;
  if Pct > RANK_PCT_2 then Result := 2;
  if Pct > RANK_PCT_3 then Result := 3;
  { Checked AFTER the percentage gates and overriding them, so a fast run
    ranks top however little it collected. }
  if ElapsedSec <= RANK_TIME then Result := 4;
end;

procedure EndingApplyUnlocks(var S: TGameSettings; const P: TPlayerState);
var
  Rank, I: Integer;
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
  for I := 0 to GALLERY_COUNT - 1 do
    if P.Progress[GALLERY_FIRST_FLAG + I] <> 0 then
      S.GalleryUnlocked[I] := 1;
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

function TEndingScreen.SlideImage: Integer;
begin
  if (Step < 1) or (Step > ENDING_SLIDES) then
    Exit(-1);
  Result := ENDING_IMAGE[Step - 1];
end;

function TEndingScreen.SlideLine(N: Integer): string;
var
  I: Integer;
begin
  Result := '';
  if (Step < 1) or (Step > ENDING_SLIDES) or (N < 0) or (N > 1) then
    Exit;
  I := ENDING_TEXT_ID[Step - 1] + N;
  if (I >= 0) and (I <= High(ENDING_TEXT)) then
    Result := ENDING_TEXT[I];
end;

procedure TEndingScreen.Update(var S: TGameSettings; const P: TPlayerState;
                               var AGameState: Integer);
begin
  if ScreenPhase = 0 then
  begin
    ScreenPhase := 1;
    Step := 0;
    Timer := 0;
    if Assigned(FOnStopMusic) then
      FOnStopMusic;
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
          FOnStopMusic;
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
      { The original reads ENDING_SECONDS[Step - 1] here even when Step has
        reached 7, one past the table - and then overwrites Timer with the
        sentinel in the branch below, so the overrun value is never used.
        Guarded rather than reproduced; DIV-011's class. }
      if Step <= ENDING_SLIDES then
        Timer := ENDING_SECONDS[Step - 1] * ENDING_SECONDS_SCALE;

      if Step = 1 then
        if Assigned(FOnMusic) then FOnMusic(ENDING_MIDI_SLIDE_1, True);
      if Step = ENDING_SLIDE_STOP_AT then
        if Assigned(FOnStopMusic) then FOnStopMusic;
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
        if Assigned(FOnStartFade) then
          FOnStartFade;
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
      if Assigned(FOnPicture) then
        FOnPicture(0);
      if Assigned(FOnMusic) then
        FOnMusic(ENDING_MIDI, True);
    end;
    Inc(Timer);
    Exit;
  end;

  { Phases 3, 4 and 5 walk the staff roll and then the results. The flags are
    banked when the results appear, which is phase 5 - once, and before the
    player can leave. }
  if ScreenPhase >= 3 then
  begin
    Inc(Timer);
    if (ScreenPhase = 5) and (Step = 0) then
    begin
      Step := 1;
      EndingApplyUnlocks(S, P);
    end;
  end;
end;

end.
