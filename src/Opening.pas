{ The opening cutscene - Opening_Update @ 0x00463154.

  Ten slides, each a picture and two lines of outlined text, on a timer.

  IT IS NOT A GAME STATE. That was recorded for a long time as the handler for
  GameState 150 and it is not: 150 calls Ending_Update, and this function's
  ONLY caller is Game_StartOrLoad. So the opening is part of starting a game
  rather than a state the loop dispatches to, which is why nothing in the
  state machine ever reaches it.

  THE THREE TABLES, all indexed by slide - 1, so slide numbers run 1..10:

      0x00468F14  picture   1 1 2 3 4 5 5 -1 6 6
      0x00468F64  seconds   8 8 8 8 8 8 8  2 8 8
      0x00468F3C  text      0 2 4 6 8 10 12 14 16 18

  The picture id repeats - slides 1 and 2 share op001, 6 and 7 share op005,
  9 and 10 share op006 - so six images carry ten slides. Slide 8 has NO
  picture, id -1, and is also the only short one at two seconds: it is
  "    And now...      " alone on black.

  The text table is just slide * 2. It is written out as a table anyway, and
  the pairs it indexes are consecutive - so every slide takes two lines, drawn
  at y 200 and y 0xD8.

  MUSIC is stepped by slide, not by the timer: slide 1 starts `midi\\open01`
  looping, slide 8 stops it, and slide 9 starts `midi\\open02` NOT looping.
  Which is what slide 10 then waits on - past slide 10 the timer stops being
  decremented at all and the only thing that advances it is the music
  finishing. Confirm skips straight to the end at any point.

  THE STRINGS ARE THE TRANSLATOR'S. This narration and the ability-name table
  are the two things tools/bindiff.py finds changed between the 2003 and 2020
  releases, so what is reproduced here is the 1.1 (D) wording specifically.
  Everything else in this unit is the author's.

  Its timer and slide counter are the SAME two globals the ending screen uses
  as its timer and step - 0x0046D174 and 0x0046D298 - alongside the shared
  ScreenPhase. Three screens, one set of scratch. }

unit Opening;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Graphics, GameState, GameFont;

const
  OPENING_SLIDES = 10;

  { 0x00468F14. -1 means no picture at all. }
  OPENING_PICTURE_ADDR = $00468F14;
  OPENING_PICTURE: array[0..OPENING_SLIDES - 1] of Integer =
    (1, 1, 2, 3, 4, 5, 5, -1, 6, 6);

  { 0x00468F64, in SECONDS - the handler multiplies by 60. }
  OPENING_SECONDS_ADDR = $00468F64;
  OPENING_SECONDS: array[0..OPENING_SLIDES - 1] of Integer =
    (8, 8, 8, 8, 8, 8, 8, 2, 8, 8);

  { 0x00468F3C, and it is exactly slide * 2. }
  OPENING_TEXT_ADDR = $00468F3C;
  OPENING_TEXT_INDEX: array[0..OPENING_SLIDES - 1] of Integer =
    (0, 2, 4, 6, 8, 10, 12, 14, 16, 18);

  { The twenty lines at 0x00468F8C. Entry 15 is nil in the binary, which is
    why slide 8 shows one line and not two. Trailing spaces are the
    original's - the text is centred by eye, not by the renderer. }
  OPENING_LINES: array[0..19] of string = (
    'A demon named "Akuji" once  ',
    'terrorized this land. ',
    'Akuji''s mischief brought  ',
    'misfortune upon the people. ',
    'One day, a hero came to the   ',
    'kingdom to slay Akuji.',
    'After an amazing battle, the  ',
    'hero was victorious.          ',
    'The hero was praised and wed',
    'the princess to become the king.',
    'But Akuji''s powers were only    ',
    'sealed in nine stones.',
    'The stones were hidden in a ',
    'deep labyrinth.   ',
    '    And now...      ',
    '',
    'Akuji is recovering them',
    'to seek revenge on the hero...',
    'In this underground labyrinth,',
    'the nine stones lie sealed.     ');

  FRAMES_PER_SECOND = 60;
  OPENING_DONE = 999;       { the timer's sentinel }

  { The picture: a 180x240 surface drawn at (0x28, 8). }
  OPENING_PIC_W = $B4;
  OPENING_PIC_H = $F0;
  OPENING_PIC_X = $28;
  OPENING_PIC_Y = 8;

  { Game_DrawTextOutlined, fill then outline - the same pair the ending screen
    and the message box use. }
  OPENING_TEXT_X  = $38;
  OPENING_LINE1_Y = 200;
  OPENING_LINE2_Y = $D8;
  OPENING_FILL    = $A3DFFF;    { RGB(0xFF, 0xDF, 0xA3) }
  OPENING_OUTLINE = $355B7E;    { RGB(0x7E, 0x5B, 0x35) }

  OPENING_MIDI_IN  = 5;     { AutoLoadMidis[5]  - midi\open01, looping }
  OPENING_MIDI_OUT = 8;     { AutoLoadMidis[8]  - midi\open02, once }
  OPENING_MUSIC_IN_SLIDE  = 1;
  OPENING_MUSIC_OFF_SLIDE = 8;
  OPENING_MUSIC_OUT_SLIDE = 9;

  { bmp\op%.3d.bmp loose, op%.3d.bmp inside the archive. }
  OPENING_PICTURE_FMT = 'op%.3d.bmp';

type
  TOpeningPicture = procedure(Id: Integer) of object;
  TOpeningMusic = procedure(Track: Integer; Loop: Boolean) of object;
  TOpeningStopMusic = procedure of object;
  TOpeningFade = procedure(FadeIn: Boolean) of object;

  TOpeningScreen = class
  private
    FOnPicture: TOpeningPicture;
    FOnMusic: TOpeningMusic;
    FOnStopMusic: TOpeningStopMusic;
    FOnFade: TOpeningFade;
    procedure EnterSlide(N: Integer);
  public
    { 0x0046D298 and 0x0046D174, shared with the ending screen. }
    Slide: Integer;
    Timer: Integer;

    procedure Reset;

    { 0x00463154. One frame. Returns False once the sequence is over, which
      is when the timer has reached its sentinel AND the fader has gone idle.
      MusicPlaying is asked every frame because slide 10 waits on it. }
    function Update(Confirm, MusicPlaying, FadeBusy: Boolean): Boolean;

    procedure Draw(C: TCanvas; F: TGameFont; Picture: TBitmap);

    property OnPicture: TOpeningPicture read FOnPicture write FOnPicture;
    property OnMusic: TOpeningMusic read FOnMusic write FOnMusic;
    property OnStopMusic: TOpeningStopMusic read FOnStopMusic
                                            write FOnStopMusic;
    property OnFade: TOpeningFade read FOnFade write FOnFade;
  end;

{ The picture id for a slide, and -1 when it has none. Indexes the table the
  way the original does - slide - 1 - and returns -1 rather than reading past
  the end, which the original does not check. DIVERGENCE DIV-004; Update clamps
  Slide to 1..10 first, so the guard never fires. }
function OpeningPictureFor(ASlide: Integer): Integer;

implementation

function OpeningPictureFor(ASlide: Integer): Integer;
begin
  if (ASlide < 1) or (ASlide > OPENING_SLIDES) then
    Exit(-1);
  Result := OPENING_PICTURE[ASlide - 1];
end;

procedure TOpeningScreen.Reset;
begin
  Slide := 0;
  Timer := 0;
end;

procedure TOpeningScreen.EnterSlide(N: Integer);
var
  Id: Integer;
begin
  Timer := OPENING_SECONDS[N - 1] * FRAMES_PER_SECOND;

  if N = OPENING_MUSIC_IN_SLIDE then
    if Assigned(FOnMusic) then
      FOnMusic(OPENING_MIDI_IN, True);
  if N = OPENING_MUSIC_OFF_SLIDE then
    if Assigned(FOnStopMusic) then
      FOnStopMusic;
  if N = OPENING_MUSIC_OUT_SLIDE then
    if Assigned(FOnMusic) then
      FOnMusic(OPENING_MIDI_OUT, False);

  Id := OpeningPictureFor(N);
  if (Id <> -1) and Assigned(FOnPicture) then
    FOnPicture(Id);
end;

function TOpeningScreen.Update(Confirm, MusicPlaying,
                               FadeBusy: Boolean): Boolean;
begin
  Result := True;

  if Timer = OPENING_DONE then
  begin
    { Held until the fade has landed, then everything is torn down. }
    if not FadeBusy then
    begin
      if Assigned(FOnFade) then
        FOnFade(True);
      if Assigned(FOnStopMusic) then
        FOnStopMusic;
      Result := False;
    end;
    Exit;
  end;

  if Slide <> OPENING_SLIDES then
    Dec(Timer);

  if (Timer < 1) or ((Slide = OPENING_SLIDES) and not MusicPlaying) then
  begin
    Inc(Slide);
    if Slide > OPENING_SLIDES then
    begin
      { Past the last slide: clamp, arm the sentinel, and start the fade. }
      Slide := OPENING_SLIDES;
      Timer := OPENING_DONE;
      if Assigned(FOnFade) then
        FOnFade(False);
      Exit;
    end;
    EnterSlide(Slide);
  end;

  if Confirm then
  begin
    Timer := OPENING_DONE;
    if Assigned(FOnFade) then
      FOnFade(False);
  end;
end;

procedure TOpeningScreen.Draw(C: TCanvas; F: TGameFont; Picture: TBitmap);
var
  T: Integer;
begin
  if (Slide < 1) or (Slide > OPENING_SLIDES) then
    Exit;

  if (OpeningPictureFor(Slide) <> -1) and (Picture <> nil) then
    C.Draw(OPENING_PIC_X, OPENING_PIC_Y, Picture);

  T := OPENING_TEXT_INDEX[Slide - 1];
  { Game_DrawTextOutlined @ 0x00451004, exactly as Opening_Update calls it at
    0x00463572 and 0x004635B4 - x 0x38, y 200 and 0xD8, outline then fill,
    size 10, on the component's canvas.

    This used to go through the 9x9 bitmap font, which is why the text came out
    in capitals: that sheet holds $20..$5F and has NO LOWERCASE. The original
    never uses it here. }
  Game_DrawTextOutlined(OPENING_TEXT_X, OPENING_LINE1_Y, OPENING_LINES[T],
                        OPENING_OUTLINE, OPENING_FILL, OUTLINED_FONT_SIZE, C);
  if T + 1 <= High(OPENING_LINES) then
    Game_DrawTextOutlined(OPENING_TEXT_X, OPENING_LINE2_Y, OPENING_LINES[T + 1],
                          OPENING_OUTLINE, OPENING_FILL, OUTLINED_FONT_SIZE, C);
end;

end.
