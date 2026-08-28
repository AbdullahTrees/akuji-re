{ Dialogue - the message box, and the reason a sign used to lock the game.

  Sub-op 3 shows a line and then WAITS. EventScript_Execute sets its wait flag
  and returns; nothing in the interpreter ever advances the step. What does is
  the message box itself - FUN_004568D0 @ 0x004568D0 ends with

      if (not still busy) { ...; dialogueActive := 0; EventScript_AdvanceStep(); }

  so the box is what drives the script forward. With no box, a script that
  reached sub-op 3 sat in GS_STATE_140 for ever and the game was locked. That
  is not a bug in the interpreter; it is a missing collaborator, and reading a
  sign found it immediately.

  ## What is faithful here and what is not

  FAITHFUL, from the shipped text and from FUN_004568D0:

    * the control codes, which are in the tk files and readable directly:
        \n  line break within a page
        \k  end of page, wait, then continue with the next
        \e  end of the message
        \w  a yes/no prompt whose answer goes in Progress[3]
      The \w reading is not a guess - see EventRunner.pas: all 86 alternatives
      in the shipped data that guard on a scratch flag guard on flag 3, and
      every one of them has a \w line earlier in its own program.

    * the box moves out of the player's way. FUN_004568D0 reads the player
      sprite's y and puts the box at y 0x88 when the player is above 0x79,
      and at 0 otherwise - so it never covers the character talking.

    * three text lines per page, 16 pixels apart, starting 0x1C below the box.

  NOT YET FAITHFUL, and marked so rather than quietly approximated: the
  original draws the frame through a DirectDraw component (FUN_0044DE3C) and
  its text through Game_DrawTextOutlined, which takes a fill and an outline
  colour. This draws a filled rectangle and plain font text. The GEOMETRY is
  the original's; the decoration is not. }

unit Dialogue;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, GameFont, PlayerState, EventRunner, EventScripts,
  GameState;

const
  { FUN_004568D0's numbers. The box flips to the lower half of the screen when
    the player is in the upper half. }
  BOX_X        = $30;   { 48 }
  BOX_TEXT_X   = $3C;   { 60 }
  BOX_LOW_Y    = $88;   { 136, when the player is high on screen }
  BOX_HIGH_Y   = 0;
  BOX_PLAYER_SPLIT = $79;   { 121 }
  BOX_FIRST_LINE = $1C;     { 28 below the box origin }
  BOX_LINE_STEP  = $10;     { 16 }
  BOX_W          = 224;
  BOX_H          = 72;
  BOX_LINES      = 3;

type
  { The message box as the interpreter's collaborator. It owns no drawing
    surface - the form hands it a canvas - and it advances the script itself,
    which is what the original does. }
  TDialogueBox = class(TEventHost)
  private
    FActive: Boolean;
    FLines: array[0..BOX_LINES - 1] of string;
    FRest: string;            { pages still to come, after a \k }
    FPrompt: Boolean;         { this page ended in \w }
    FChoice: Integer;         { 0 = yes, 1 = no }
    FScript: TEventScript;
    FRunner: TEventRunner;
    FPlayer: PPlayerState;
    procedure TakePage(const Text: string);
  public
    { Where the script and the state it answers into live. Set once. }
    procedure Bind(AScript: TEventScript; ARunner: TEventRunner;
                   APlayer: PPlayerState);

    { TEventHost. Sub-op 3 lands here. }
    procedure ShowLine(Index: Integer); override;

    { One frame. Confirm is the edge, not the level. Returns True while the
      box is up, which is the caller's cue to step no game logic. }
    function Update(Confirm, Up, Down: Boolean; var AGameState: Integer): Boolean;

    procedure Draw(Dest: TCanvas; Font: TGameFont; PlayerScreenY: Integer);

    property Active: Boolean read FActive;
  end;

{ Splits one page off the front of a message: everything up to \k or \e.
  Returns the page, and leaves the remainder in Rest. Exposed for testing. }
function SplitPage(const Text: string; out Rest: string;
                   out Prompt: Boolean): string;

implementation

function SplitPage(const Text: string; out Rest: string;
                   out Prompt: Boolean): string;
var
  I: Integer;
begin
  Rest := '';
  Prompt := False;
  I := 1;
  while I < Length(Text) do
  begin
    if Text[I] = '\' then
      case Text[I + 1] of
        'k':
          begin
            { End of page. The rest is the next page. }
            Result := Copy(Text, 1, I - 1);
            Rest := Copy(Text, I + 2, MaxInt);
            Exit;
          end;
        'e':
          begin
            Result := Copy(Text, 1, I - 1);
            Exit;
          end;
        'w':
          begin
            Prompt := True;
            Result := Copy(Text, 1, I - 1);
            Rest := Copy(Text, I + 2, MaxInt);
            Exit;
          end;
      end;
    Inc(I);
  end;
  Result := Text;
end;

procedure TDialogueBox.TakePage(const Text: string);
var
  Src, Page, Line: string;
  N, P: Integer;
begin
  { COPY FIRST. Update calls TakePage(FRest), and SplitPage's Rest is an out
    parameter bound to that same FRest - so the first thing SplitPage does,
    clearing Rest, would blank the string it is about to read. A const string
    parameter is a reference, not a snapshot. Every message with a \k would
    have lost its second page. }
  Src := Text;
  Page := SplitPage(Src, FRest, FPrompt);
  for N := 0 to BOX_LINES - 1 do
    FLines[N] := '';

  { \n breaks a page into its three lines. }
  N := 0;
  while (Page <> '') and (N < BOX_LINES) do
  begin
    P := Pos('\n', Page);
    if P = 0 then
    begin
      Line := Page;
      Page := '';
    end
    else
    begin
      Line := Copy(Page, 1, P - 1);
      Page := Copy(Page, P + 2, MaxInt);
    end;
    FLines[N] := Trim(Line);
    Inc(N);
  end;

  FChoice := 0;
end;

procedure TDialogueBox.Bind(AScript: TEventScript; ARunner: TEventRunner;
                            APlayer: PPlayerState);
begin
  FScript := AScript;
  FRunner := ARunner;
  FPlayer := APlayer;
end;

procedure TDialogueBox.ShowLine(Index: Integer);
begin
  if (FScript = nil) or (Index < 0) or (Index >= FScript.LineCount) then
  begin
    { A line that does not exist must not leave the script waiting for a box
      that never opens - that is the lock again, one level down. }
    FActive := False;
    Exit;
  end;
  FActive := True;
  TakePage(FScript.Lines[Index]);
end;

function TDialogueBox.Update(Confirm, Up, Down: Boolean;
                             var AGameState: Integer): Boolean;
begin
  Result := FActive;
  if not FActive then
    Exit;

  if FPrompt then
  begin
    if Up then FChoice := 0;
    if Down then FChoice := 1;
  end;

  if not Confirm then
    Exit;

  if FPrompt then
  begin
    { Progress[3] is the answer, and the guarded steps that follow read it. }
    if FPlayer <> nil then
      FPlayer^.Progress[3] := Ord(FChoice = 0);
    FPrompt := False;
  end;

  if FRest <> '' then
  begin
    TakePage(FRest);
    Exit;
  end;

  { Done. Closing the box is what advances the script - see the header. }
  FActive := False;
  Result := False;
  if (FRunner <> nil) and (FPlayer <> nil) then
    FRunner.AdvanceStep(FPlayer^, AGameState);
end;

procedure TDialogueBox.Draw(Dest: TCanvas; Font: TGameFont;
                            PlayerScreenY: Integer);
var
  BoxY, I: Integer;
begin
  if not FActive then
    Exit;

  { Out of the player's way, as FUN_004568D0 does it. }
  if PlayerScreenY < BOX_PLAYER_SPLIT then
    BoxY := BOX_LOW_Y
  else
    BoxY := BOX_HIGH_Y;

  Dest.Brush.Color := TColor($200000);
  Dest.Pen.Color := TColor($C0C0FF);
  Dest.Rectangle(BOX_X, BoxY + 8, BOX_X + BOX_W, BoxY + 8 + BOX_H);

  if Font = nil then
    Exit;
  for I := 0 to BOX_LINES - 1 do
    if FLines[I] <> '' then
      Font.TextOut(Dest, BOX_TEXT_X, BoxY + BOX_FIRST_LINE + I * BOX_LINE_STEP,
                   FLines[I], 0);

  if FPrompt then
  begin
    Font.TextOut(Dest, BOX_TEXT_X + 120,
                 BoxY + BOX_FIRST_LINE + BOX_LINE_STEP,
                 'YES', Ord(FChoice <> 0) * 2);
    Font.TextOut(Dest, BOX_TEXT_X + 160,
                 BoxY + BOX_FIRST_LINE + BOX_LINE_STEP,
                 'NO', Ord(FChoice <> 1) * 2);
  end;
end;

end.
