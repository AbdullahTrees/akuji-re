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
    second global at 0x0046D298. Phase 1 is a HOLE - nothing in the original
    leaves it - which is the same shape the game-over screen has, where the
    fade is what moves it on. }
  TEndingScreen = class
  private
    FOnPicture: TEndingPicture;
    FOnMusic: TEndingMusic;
    FOnStopMusic: TEndingStopMusic;
  public
    { 0x0046D298, the step inside a phase. }
    Step: Integer;
    { 0x0046D174, the frame timer the staff roll and the rank line read. }
    Timer: Integer;

    procedure Update(var S: TGameSettings; const P: TPlayerState;
                     var AGameState: Integer);

    property OnPicture: TEndingPicture read FOnPicture write FOnPicture;
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
    { And nothing here leaves phase 1 - see the note on the class. }
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
