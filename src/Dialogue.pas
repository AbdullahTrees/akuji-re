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
  GameState, Entities;

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

  { Overlay_Update @ 0x004568D0 has two modes and this is the other one: the
    full-screen power-up panel. It blits a 320x240 picture over everything and
    draws ONE line, centred, near the bottom. The 6 is the original's own
    character step for this line - `(0x140 - len * 6) >> 1` - which is not the
    8 the tile font advances by, so the panel's text is a different metric and
    almost certainly a different sheet. Recorded, not yet reproduced. }
  PANEL_TEXT_Y  = $D8;   { 216 }
  PANEL_CHAR_W  = 6;
  PANEL_W       = $140;

type
  { What the overlay needs to know about the world it interrupts. }
  TOverlayMode = (omBox, omPanel);

  { The message overlay as the interpreter's collaborator. It owns no drawing
    surface - the form hands it a canvas - and it advances the script itself,
    which is what the original does.

    ONE object with two modes, because that is what Overlay_Update is: the
    same per-frame function, the same active flag, the same three strings, and
    a mode selector at 0x0046CDA0 deciding whether to draw a three-line box or
    a full-screen panel. Splitting them into two classes would lose the fact
    that only one can be up at a time - which is exactly what sub-op 10's arm
    guards on. }
  TDialogueBox = class(TEventHost)
  private
    FMode: TOverlayMode;
    FPanelText: string;
    FPool: TEntityPool;
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
                   APlayer: PPlayerState; APool: TEntityPool);

    { TEventHost. Sub-op 3 lands here. }
    procedure ShowLine(Index: Integer); override;

    { TEventHost. Sub-op 10 lands here - the ability pickup. PowerUp_Show
      grants by the EVENT'S ENTITY's variant, so the overlay has to reach the
      pool to find it, exactly as the original reaches p_Entities through the
      event table. }
    procedure SubMode; override;

    { One frame. Confirm is the edge, not the level. Returns True while the
      box is up, which is the caller's cue to step no game logic. }
    function Update(Confirm, Up, Down: Boolean; var AGameState: Integer): Boolean;

    procedure Draw(Dest: TCanvas; Font: TGameFont; PlayerScreenY: Integer);

    property Active: Boolean read FActive;
    property Mode: TOverlayMode read FMode;
    { The panel stays up for as long as its fanfare plays - Overlay_Update
      asks the music player and closes when it stops. The form owns the
      player, so it answers. }
    property PanelText: string read FPanelText;
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
                            APlayer: PPlayerState; APool: TEntityPool);
begin
  FScript := AScript;
  FRunner := ARunner;
  FPlayer := APlayer;
  FPool := APool;
end;

procedure TDialogueBox.SubMode;
var
  Slot, Variant: Integer;
begin
  { Sub-op 10's arm at 0x0045597C runs PowerUp_Show only when the overlay is
    not already up. }
  if FActive then
    Exit;
  if (FScript = nil) or (FPool = nil) or (FPlayer = nil) or (FRunner = nil) then
    Exit;

  Slot := SLOT_NONE;
  if (FRunner.EventId >= 0) and (FRunner.EventId < FScript.Count) then
    Slot := FScript[FRunner.EventId].EntitySlot;
  if (Slot = SLOT_NONE) or (not FPool.Alive[Slot]) then
    Exit;

  Variant := FPool.Field(Slot, EF_VARIANT);
  PowerUpGrant(FPlayer^, Variant);

  FMode := omPanel;
  FActive := True;
  FPanelText := POWERUP_PREFIX + PowerUpName(Variant) + POWERUP_SUFFIX;

  { PowerUp_Show destroys the entity it granted from. }
  FPool.Kill(Slot);
  FScript.SetActive(FRunner.EventId, False);
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
  FMode := omBox;
  TakePage(FScript.Lines[Index]);
end;

function TDialogueBox.Update(Confirm, Up, Down: Boolean;
                             var AGameState: Integer): Boolean;
begin
  Result := FActive;
  if not FActive then
    Exit;

  { The panel is not dismissed by the player. Overlay_Update keeps it while
    the fanfare plays and closes it when the music stops, so the caller passes
    that in as Confirm - see the property comment. }
  if FMode = omPanel then
  begin
    if not Confirm then
      Exit;
    FActive := False;
    Result := False;
    FPanelText := '';
    if (FRunner <> nil) and (FPlayer <> nil) then
      FRunner.AdvanceStep(FPlayer^, AGameState);
    Exit;
  end;

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

  if FMode = omPanel then
  begin
    { The original blits bmp\power.bmp over the whole screen first. The form
      has the surfaces; this draws only the line, centred by the original's
      own 6-pixel step. }
    if Font <> nil then
      Font.TextOut(Dest, (PANEL_W - Length(FPanelText) * PANEL_CHAR_W) div 2,
                   PANEL_TEXT_Y, FPanelText, 0);
    Exit;
  end;

  { Out of the player's way, as Overlay_Update does it. }
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
