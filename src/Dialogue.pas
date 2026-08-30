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
  the original's; the decoration is not.

  ## The OTHER message box: MessageBox_Update @ 0x00456038

  There are two of these functions, not one. 0x004568D0 is the half this unit
  was written from; 0x00456038 is the half AppIdle runs whenever the mode
  global at 0x0046CF28 is non-zero, and it is the one with the typewriter and
  the yes/no prompt. It was carried in the notes as `TitleMenu_Update`, which
  it is not - it has no menu in it. Renamed here rather than in Ghidra alone.

  Everything below is read from it, and the constants are in the MB_ block.

  ITS FOUR MARKERS ARE ORDERED, and the order is not the order the tk files
  list them in:

      \w  ->  mode 4, the yes/no prompt
      \e  ->  mode 3, the message is over
      \k  ->  mode 2, wait for a key
      
  ->  a line break, and the only one that does not end the scan

  IT READS TWO BYTES AT A TIME. Copy(text, k*2 - 1, 2) - the text is
  Shift-JIS and a "character" is a pair. That is also why the character that
  suppresses the typewriter click is 0x81 0x40, the FULL-WIDTH space, and not
  ASCII 0x20.

  ITS ANSWER IS TWO FLAGS, NOT ONE. This unit wrote Progress[3] alone. The
  original writes both:

      Yes  ->  Progress[3] := 1;  Progress[4] := 0
      No   ->  Progress[3] := 0;  Progress[4] := 1

  so a script can guard on either answer directly instead of having to
  negate. EventRunner.pas already records Progress[1..4] as scratch; this
  says what the fourth one is for. Fixed below.

  WHAT IS STILL THE HOST'S. The typewriter's per-character delay lives in a
  global at 0x0046CBA4 and is driven by the same input the box reads; the
  wait-for-key prompt is a six-frame cycle out of a table at 0x0046D050 drawn
  from surface slot 1; and the yes/no cursor is a sprite from the same slot,
  moved 0x34 pixels for the second option. Those are recorded as constants
  and left to whatever draws. }

unit Dialogue;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, GameFont, PlayerState, EventRunner, EventScripts,
  TileMaps,
  GameState, Entities, SoundTable;

const

  { --- MessageBox_Update @ 0x00456038 ---------------------------------------
    The constants of the other message box. See the unit header for what it
    is and why it is not the title menu it was filed as. }

  { The mode global at 0x0046CF28, and the marker that selects each. }
  MB_MODE_IDLE   = 0;
  MB_MODE_TYPING = 1;
  MB_MODE_WAITKEY = 2;      { \k }
  MB_MODE_END     = 3;      { \e }
  MB_MODE_PROMPT  = 4;      { \w }

  { Sub-op 80's phases, on the same ScreenPhase counter the ending and the
    game-over screen use. }
  SOULGET_IDLE    = 0;
  SOULGET_PLAYING = 1;
  SOULGET_FADING  = 2;
  { AutoLoadMidis[11] - the byte offset in the original is 0x2C. }
  SOULGET_MIDI    = 11;

  { The text is Shift-JIS and it is scanned a PAIR of bytes at a time, so the
    character that suppresses the typewriter click is the full-width space,
    not ASCII 0x20. }
  MB_FULLWIDTH_SPACE = #$81#$40;

  { Where the box goes: below the player if the player is high on the screen,
    above if not. 0x79 is the test, 0x88 the low position. }
  MB_PLAYER_HIGH  = $79;
  MB_BOX_LOW_Y    = $88;
  MB_BOX_HIGH_Y   = 0;
  { The frame, then three lines 16 apart starting 0x1C down. }
  MB_FRAME_X      = $30;
  MB_FRAME_DY     = $10;
  MB_TEXT_X       = $3C;
  MB_LINE_FIRST   = $1C;
  MB_LINE_STEP    = $10;
  MB_LINES        = 3;
  { Game_DrawTextOutlined's two colours, fill then outline. }
  MB_FILL         = $FFFFFF;
  MB_OUTLINE      = $735400;

  { The wait-for-key prompt: a six-frame cycle from the table at 0x0046D050,
    stepped every five frames, drawn from surface slot 1. }
  MB_PROMPT_TABLE_ADDR = $0046D050;
  MB_PROMPT_FRAMES = 6;
  MB_PROMPT_TICKS  = 4;
  MB_PROMPT_X      = $F8;
  MB_PROMPT_DY     = $40;

  { The yes/no prompt. The two words are one literal with the spacing baked
    in, and the cursor moves 0x34 for the second. }
  MB_PROMPT_TEXT   = 'Yes       No  ';
  MB_PROMPT_TEXT_X = $70;
  MB_PROMPT_TEXT_DY = $3C;
  MB_CURSOR_X      = $60;
  MB_CURSOR_STEP   = $34;
  MB_SND_OPEN      = $D;    { on entering the prompt }
  MB_SND_MOVE      = 0;     { and on each move }
  MB_SND_CHOOSE    = 1;

  { The two scratch flags the answer lands in. }
  MB_ANSWER_YES = 3;
  MB_ANSWER_NO  = 4;

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

  { THE BOX IS TILED, NOT FILLED. 0x0044DE3C draws a nine-slice out of an 8x8
    sheet: four corners, four edges, and a tiled centre. The call is

        FUN_0044DE3C(obj, 0x30, boxY + 0x10, 8, 0x1B)

    so 27 tiles across and 8 down, which is where BOX_W 224 and BOX_H 72 come
    from - (27+1)*8 and (8+1)*8. The size had been worked out correctly and
    then drawn as a single Rectangle, which is why the panel came out a flat
    slab in the wrong colours: the colours are the SHEET's, not ours to pick.

    The sheet is set by Stage_Begin:

        FUN_0044DE18(obj, p_Surfaces[1], 0, 0)

    so it is surface slot 1 with its origin at (0,0) - the top-left 24x24
    pixels, read as a 3x3 grid of 8x8 tiles. }
  BOX_TILE       = 8;
  BOX_COLS       = $1B;     { 27 }
  BOX_ROWS       = 8;
  BOX_FRAME_DY   = $10;     { boxY + 16, not + 8 }
  BOX_SHEET_SLOT = 1;
  BOX_LINES      = 3;

  { Overlay_Update @ 0x004568D0 has two modes and this is the other one: the
    full-screen power-up panel. It blits a 320x240 picture over everything and
    draws ONE line, centred, near the bottom. The 6 is the original's own
    character step for this line - `(0x140 - len * 6) >> 1` - which is not the
    8 the tile font advances by, so the panel's text is a different metric and
    almost certainly a different sheet. Recorded, not yet reproduced. }
  { Colours, straight off the Game_DrawTextOutlined call sites. FUN_00406aa8
    takes r, g, b and returns a TColor, which is BGR - so RGB(200,$E6,$FF)
    is $FFE6C8. }
  BOX_TEXT_FILL    = $FFE6C8;   { RGB(200, $E6, $FF), Overlay_Update 0x004569xx }
  BOX_TEXT_OUTLINE = $735400;   { RGB(0, $54, $73) }
  PANEL_TEXT_FILL    = $FFFFFF; { RGB($FF, $FF, $FF), Overlay_Update 0x00456980 }
  PANEL_TEXT_OUTLINE = $FF0000; { RGB(0, 0, $FF) }

  { The yes/no prompt colours. The geometry and the wording were already
    recorded in the MB_ block above when MessageBox_Update was read -
    MB_PROMPT_TEXT, MB_PROMPT_TEXT_X $70 and MB_PROMPT_TEXT_DY $3C - and that
    reading stands: it is ONE padded string on the THIRD line, not two draws on
    the second, which is what this used to do.

    The SELECTION is a sprite, not a highlight on the text: the choice index at
    0x0046CF70 places a cursor, MB_CURSOR_X plus MB_CURSOR_STEP. Drawing it
    needs the surface layer, so for now both options show with nothing marking
    which is chosen. Left that way rather than keeping the old two-colour
    highlight, which was a highlight the original does not have. }
  MB_PROMPT_FILL    = $FFFFFF;
  MB_PROMPT_OUTLINE = $735400;

  PANEL_TEXT_Y  = $D8;   { 216 }
  PANEL_CHAR_W  = 6;
  PANEL_W       = $140;

{ 0x00456038's answer write, both flags. Choice 0 is Yes. Separate from the
  box so it can be checked without one. }
procedure DialogueAnswer(var P: TPlayerState; Choice: Integer);

type
  { What the overlay needs to know about the world it interrupts. }
  TOverlayMode = (omBox, omPanel);

  { What PowerUp_Show needs from the audio layer. Callbacks rather than direct
    calls so this unit stays clear of the component layer, the same way
    Title.pas and Ending.pas do. }
  TOverlaySound = procedure(Id: Integer) of object;
  TOverlayMusic = procedure(Track: Integer; Loop: Boolean) of object;
  { 0x00450EDC before the fanfare, 0x00450EF0 when it finishes. The first
    remembers what was playing; the second brings it back, looping. }
  TOverlayRememberMusic = procedure of object;
  TOverlayResumeMusic = procedure of object;
  TOverlayStartFade = procedure(FadeOut: Boolean) of object;
  TOverlayFadeBusy = function: Boolean of object;
  TOverlaySoulGetDone = procedure of object;
  { 0x00450FD0 - "is a track still playing". Phase 1 waits on it. }
  TOverlayMusicBusy = function: Boolean of object;

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
    { PowerUp_Show ends with Entity_Destroy, which needs the world's event
      bookkeeping and its sprite sink - a bare pool cannot hide a sprite. }
    FWorld: TEntityWorld;
    FActive: Boolean;
    FLines: array[0..BOX_LINES - 1] of string;
    FRest: string;            { pages still to come, after a \k }
    FPrompt: Boolean;         { this page ended in \w }
    FChoice: Integer;         { 0 = yes, 1 = no }
    FScript: TEventScript;
    FRunner: TEventRunner;
    FPlayer: PPlayerState;
    FOnSound: TOverlaySound;
    FOnMusic: TOverlayMusic;
    FOnRememberMusic: TOverlayRememberMusic;
    FOnResumeMusic: TOverlayResumeMusic;
    FOnStartFade: TOverlayStartFade;
    FOnFadeBusy: TOverlayFadeBusy;
    FOnFadeMusic: TOverlayMusic;
    FMap: TTileMap;
    FSaveFileName: string;
    FFrameSheet: TBitmap;
    FOnSoulGetDone: TOverlaySoulGetDone;
    FOnMusicBusy: TOverlayMusicBusy;
    procedure TakePage(const Text: string);
    procedure PlaceAt(PlayerTileX, PlayerTileY, CamTileX, CamTileY: Integer);
    function EventSlot(EventId: Integer): Integer;
    function MusicBusy: Boolean;
    procedure DrawFrame(Dest: TCanvas; X, Y, Rows, Cols: Integer);
  public
    { Where the script and the state it answers into live. Set once. }
    procedure Bind(AScript: TEventScript; ARunner: TEventRunner;
                   APlayer: PPlayerState; APool: TEntityPool;
                   AWorld: TEntityWorld = nil);

    { TEventHost. Sub-op 3 lands here. }
    procedure ShowLine(Index: Integer); override;

    { TEventHost. Sub-op 10 lands here - the ability pickup. PowerUp_Show
      grants by the EVENT'S ENTITY's variant, so the overlay has to reach the
      pool to find it, exactly as the original reaches p_Entities through the
      event table. }
    procedure SubMode; override;

    { Sub-op 0 and sub-op 1: the stage load and the warp. Both carry TILE
      coordinates and convert them identically - and the conversion was
      already read and written down in PlayerState.pas, complete with the
      asymmetric +16 / +19, long before anything called it.

      Nothing overrode either, so LoadStage did nothing at all: the interpreter
      set GS_STAGE_BEGIN, the stage number never changed, and the stage
      reloaded itself. Walking out of room 1 put you back in room 1. }
    procedure LoadStage(Stage, PlayerTileX, PlayerTileY,
                        CamTileX, CamTileY: Integer); override;
    procedure WarpPlayer(PlayerTileX, PlayerTileY,
                         CamTileX, CamTileY: Integer); override;

    { Sub-op 8 @ 0x004557xx: Entity_Destroy on the event's own entity, then
      advance. The interpreter advances; this only destroys. }
    procedure DestroyEventEntity(EventId: Integer); override;
    { Sub-op 16 @ 0x00455Fxx: writes EF_STATE (+0x20) on the event's entity. }
    procedure SetEventEntityState(EventId, Value: Integer); override;
    { The screen fade, which lives on the display component - see
      DDDDComponent. Routed through callbacks so this unit stays off it. }
    procedure StartFade(Out_: Boolean); override;
    function FadeBusy: Boolean; override;
    { Sub-op 12. The FADE play path, 0x00450F74, not the hard-cut one - the
      interpreter's two calls are at 0x00455AAF and 0x00455AFB and both go
      through it. }
    procedure PlayMusic(Track: Integer; Loop: Boolean); override;
    { Sub-op 14 @ 0x00455Exx: TileMap_Set on layer 0. }
    procedure SetTile(X, Y, Tile: Integer); override;
    { Sub-op 13 @ 0x00455Dxx. Writes the RESUME POINT into the record first -
      the stage, the player's live position and the camera - and only then
      dumps all 0x11E4 bytes over data\save.dat. }
    procedure SaveGame(var P: TPlayerState); override;
    { Sub-op 80, `soulget` @ 0x00455Exx - a THREE-PHASE machine on ScreenPhase,
      not a one-shot, and the only route to the ending:

          phase 0   -> 1   effect $10, playlist entry 11 once, destroy the
                           entity that was touched
          phase 1   -> 2   once the music has stopped, fade OUT
          phase 2   -> 0   once the fade has landed, fade IN, reset the game
                           state, reload the title assets, and set
                           GameState 150 with the opening's counters cleared

      The middle phase is why it cannot be a single call: it waits a track
      and a fade, which is thirty frames on its own. }
    procedure SoulGet; override;

    { 0x004568D0, Overlay_Update. One frame of the box. Confirm is the edge,
      not the level. Returns True while the box is up, which is the caller's
      cue to step no game logic.

      The address goes here rather than only in the unit header because this
      IS that function - the whole unit was written from it, and it sat in
      the backlog as "described, not implemented" purely because nothing
      carried the address where the coverage tool looks. }
    procedure PlayBoxSound(Index: Integer);
    function Update(Confirm: Boolean; MoveX: Integer; Moving: Boolean;
                    var AGameState: Integer): Boolean;

    procedure Draw(Dest: TCanvas; Font: TGameFont; PlayerScreenY: Integer);

    property Active: Boolean read FActive;
    property Mode: TOverlayMode read FMode;
    property OnSound: TOverlaySound read FOnSound write FOnSound;
    property OnMusic: TOverlayMusic read FOnMusic write FOnMusic;
    property OnRememberMusic: TOverlayRememberMusic read FOnRememberMusic
                                                    write FOnRememberMusic;
    property OnResumeMusic: TOverlayResumeMusic read FOnResumeMusic
                                                write FOnResumeMusic;
    property OnStartFade: TOverlayStartFade read FOnStartFade
                                            write FOnStartFade;
    property OnFadeBusy: TOverlayFadeBusy read FOnFadeBusy write FOnFadeBusy;
    { Sub-op 12 fades; the power-up fanfare cuts. Two different wrappers in
      the original, so two callbacks here. }
    property OnFadeMusic: TOverlayMusic read FOnFadeMusic write FOnFadeMusic;
    property Map: TTileMap read FMap write FMap;
    { Where sub-op 13 writes. The original hard-codes data\save.dat relative
      to the working directory; this is given the resolved path. }
    property SaveFileName: string read FSaveFileName write FSaveFileName;
    { p_Surfaces[1], the sheet the box frame is tiled from. }
    property FrameSheet: TBitmap read FFrameSheet write FFrameSheet;
    { What phase 2 needs and this unit cannot reach: GameState_Reset, the
      title asset load and the font definition all live on the form. }
    property OnSoulGetDone: TOverlaySoulGetDone read FOnSoulGetDone
                                                write FOnSoulGetDone;
    property OnMusicBusy: TOverlayMusicBusy read FOnMusicBusy
                                            write FOnMusicBusy;
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

procedure DialogueAnswer(var P: TPlayerState; Choice: Integer);
begin
  P.Progress[MB_ANSWER_YES] := Ord(Choice = 0);
  P.Progress[MB_ANSWER_NO]  := Ord(Choice <> 0);
end;

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
  { Sound 0xD - kakunin, "confirmation" - the moment a \w prompt comes up.
    0x00456038 plays it on mode 4's first frame, which is this moment. }
  if FPrompt then
  begin
    FChoice := 0;
    PlayBoxSound(SND_KAKUNIN);
  end;
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
                            APlayer: PPlayerState; APool: TEntityPool;
                            AWorld: TEntityWorld);
begin
  FScript := AScript;
  FRunner := ARunner;
  FPlayer := APlayer;
  FPool := APool;
  FWorld := AWorld;
end;

{ Where a destination in tiles lands in the player state. The original does
  this five times in a row at 0x004553B2..0x004554C2, reading each argument
  out of the step at a fixed column and multiplying by the LAYER's tile size -
  not by a constant 32, which is why the layer has to be reachable here. }
procedure TDialogueBox.PlaceAt(PlayerTileX, PlayerTileY,
                               CamTileX, CamTileY: Integer);
var
  TW, TH: Integer;
begin
  if FPlayer = nil then
    Exit;
  { The shipped maps are all 32x32, but the map header carries the size and
    the original multiplies by the LAYER's value, so this does too. The
    fallback is only for a world that has not loaded a map yet. }
  TW := 32;
  TH := 32;
  if FWorld <> nil then
  begin
    if FWorld.Layer.TileW > 0 then TW := FWorld.Layer.TileW;
    if FWorld.Layer.TileH > 0 then TH := FWorld.Layer.TileH;
  end;
  FPlayer^.SpawnX  := PlayerTileX * TW + SPAWN_CENTRE_X;
  FPlayer^.SpawnY  := PlayerTileY * TH + SPAWN_CENTRE_Y;
  FPlayer^.ScrollX := CamTileX * TW;
  FPlayer^.ScrollY := CamTileY * TH;
end;

procedure TDialogueBox.LoadStage(Stage, PlayerTileX, PlayerTileY,
                                 CamTileX, CamTileY: Integer);
begin
  { 0x004553B8 - the stage number goes straight into the settings, and
    Stage_Begin reads it back. The interpreter sets GS_STAGE_BEGIN itself. }
  Settings.CurrentStage := Stage;
  PlaceAt(PlayerTileX, PlayerTileY, CamTileX, CamTileY);
end;

procedure TDialogueBox.WarpPlayer(PlayerTileX, PlayerTileY,
                                  CamTileX, CamTileY: Integer);
begin
  { Sub-op 1: the same placement without a stage change. }
  PlaceAt(PlayerTileX, PlayerTileY, CamTileX, CamTileY);
end;

{ The event's own entity, which is what sub-ops 8 and 16 both operate on:
  pool + eventTable[EventId].EntitySlot. }
function TDialogueBox.EventSlot(EventId: Integer): Integer;
begin
  Result := SLOT_NONE;
  if (FScript <> nil) and (EventId >= 0) and (EventId < FScript.Count) then
    Result := FScript[EventId].EntitySlot;
end;

procedure TDialogueBox.DestroyEventEntity(EventId: Integer);
var
  Slot: Integer;
begin
  Slot := EventSlot(EventId);
  if (Slot = SLOT_NONE) or (FPool = nil) then
    Exit;
  { Entity_Destroy, not a kill - the same distinction that left the power-up
    orb on screen. DropLoot is 0 at this call site. }
  if FWorld <> nil then
    FWorld.DestroyEntity(FPool.Entity(Slot)^, False)
  else
    FPool.Kill(Slot);
end;

procedure TDialogueBox.SetEventEntityState(EventId, Value: Integer);
var
  Slot: Integer;
begin
  Slot := EventSlot(EventId);
  if (Slot = SLOT_NONE) or (FPool = nil) then
    Exit;
  FPool.SetField(Slot, EF_STATE, Value);
end;

procedure TDialogueBox.PlayMusic(Track: Integer; Loop: Boolean);
begin
  if Assigned(FOnFadeMusic) then
    FOnFadeMusic(Track, Loop);
end;

procedure TDialogueBox.SetTile(X, Y, Tile: Integer);
begin
  if FMap <> nil then
    FMap.SetTileRaw(X, Y, Tile);
end;

{ The nine-slice, tile for tile as 0x0044DE3C draws it.

  Source tiles come from a 3x3 grid at the sheet's origin: column 0 is the left
  edge, 1 the middle, 2 the right; row 0 the top, 1 the middle, 2 the bottom.
  The destination runs 0..Cols and 0..Rows INCLUSIVE - the original draws its
  far corner at Cols*8, so a 27-column box is 28 tiles wide. }
procedure TDialogueBox.DrawFrame(Dest: TCanvas; X, Y, Rows, Cols: Integer);
var
  Col, Row, SrcCol, SrcRow: Integer;

  procedure Tile(DX, DY, SC, SR: Integer);
  begin
    FFrameSheet.Transparent := False;
    Dest.CopyRect(
      Rect(DX, DY, DX + BOX_TILE, DY + BOX_TILE),
      FFrameSheet.Canvas,
      Rect(SC * BOX_TILE, SR * BOX_TILE,
           SC * BOX_TILE + BOX_TILE, SR * BOX_TILE + BOX_TILE));
  end;

begin
  if FFrameSheet = nil then
    Exit;
  for Row := 0 to Rows do
  begin
    if Row = 0 then
      SrcRow := 0
    else if Row = Rows then
      SrcRow := 2
    else
      SrcRow := 1;
    for Col := 0 to Cols do
    begin
      if Col = 0 then
        SrcCol := 0
      else if Col = Cols then
        SrcCol := 2
      else
        SrcCol := 1;
      Tile(X + Col * BOX_TILE, Y + Row * BOX_TILE, SrcCol, SrcRow);
    end;
  end;
end;

procedure TDialogueBox.SaveGame(var P: TPlayerState);
begin
  { The resume point, in the original's order. Note these are the LIVE
    position and camera converted back to pixels, not the values the stage
    started at - saving mid-room has to come back to the same spot.

    The conversion is PixelOf: subtract the bias, and for a negative subtract
    bias-31 instead so the shift truncates toward zero. The original writes
    that idiom out four times in a row at 0x00455Dxx. }
  P.SavedStage := Settings.CurrentStage;
  if FPool <> nil then
  begin
    P.SpawnX := PixelOf(FPool.Field(SLOT_SINGLE_FIRST, EF_POS_X));
    P.SpawnY := PixelOf(FPool.Field(SLOT_SINGLE_FIRST, EF_POS_Y));
  end;
  if FWorld <> nil then
  begin
    P.ScrollX := PixelOf(FWorld.Layer.OriginX);
    P.ScrollY := PixelOf(FWorld.Layer.OriginY);
  end;
  if FSaveFileName <> '' then
    SaveTo(P, FSaveFileName);
end;

function TDialogueBox.MusicBusy: Boolean;
begin
  Result := Assigned(FOnMusicBusy) and FOnMusicBusy;
end;

procedure TDialogueBox.SoulGet;
begin
  { The order below is the original's, and it is NOT phase order: the
    music-finished test is written first and reads the phase the previous
    frame left, so phase 0 falls through to phase 1 on the same frame it
    starts. Reproduced rather than tidied into a case. }
  if (ScreenPhase = SOULGET_PLAYING) and (not MusicBusy) then
  begin
    ScreenPhase := SOULGET_FADING;
    StartFade(True);
  end;

  if ScreenPhase = SOULGET_IDLE then
  begin
    ScreenPhase := SOULGET_PLAYING;
    if Assigned(FOnSound) then
      FOnSound(POWERUP_SOUND);
    { Playlist entry 11, and NOT looping - it is what phase 1 waits on. }
    if Assigned(FOnMusic) then
      FOnMusic(SOULGET_MIDI, False);
    DestroyEventEntity(FRunner.EventId);
  end;

  if (ScreenPhase = SOULGET_FADING) and (not FadeBusy) then
  begin
    StartFade(False);
    ScreenPhase := SOULGET_IDLE;
    TitleSubMode := 0;
    if Assigned(FOnSoulGetDone) then
      FOnSoulGetDone;
  end;
end;

procedure TDialogueBox.StartFade(Out_: Boolean);
begin
  if Assigned(FOnStartFade) then
    FOnStartFade(Out_);
end;

function TDialogueBox.FadeBusy: Boolean;
begin
  Result := Assigned(FOnFadeBusy) and FOnFadeBusy;
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

  { NO ALIVENESS TEST. This used to read
        if (Slot = SLOT_NONE) or (not FPool.Alive[Slot]) then Exit;
    and the second half was a softlock on every power-up in the game.

    By the time sub-op 10 runs, the entity is ALREADY DEAD - the touch that
    fired the event destroyed it earlier in the same frame. The trace of the
    original shows both, in order, at frame 9056:

        Entity_Destroy  4657908      <- the touch
        EventScript_Execute
        PowerUp_Show                 <- reads the same entity anyway
        Entity_Destroy  4657908      <- and destroys it again

    PowerUp_Show @ 0x00456698 indexes the pool straight off the event table
    and reads +0x18 with no check of any kind. The fields survive a kill, so
    the variant is still there to read. Our guard turned that into an early
    return that raised no panel AND never advanced the script, which is a
    state nothing can leave.

    The SLOT_NONE half stays: it guards an out-of-range index, which in Pascal
    is a crash rather than a behaviour, and the original cannot reach it
    because the slot comes from an event that placed an entity. }
  if Slot = SLOT_NONE then
    Exit;

  Variant := FPool.Field(Slot, EF_VARIANT);

  { The audio comes FIRST, before the panel is raised - that is the original's
    order, and the fanfare is what dismisses the panel again. Without the stop
    the looping stage music keeps IsPlaying true forever and the overlay never
    closes; that was the softlock on the dash orb. }
  if Assigned(FOnSound) then
    FOnSound(POWERUP_SOUND);
  { REMEMBER, not stop. 0x00450EDC only copies the current track's name
    aside; the stop happens inside the play below, which is 0x00450F14. }
  if Assigned(FOnRememberMusic) then
    FOnRememberMusic;
  if Assigned(FOnMusic) then
    FOnMusic(POWERUP_MIDI, False);

  FMode := omPanel;
  FActive := True;
  PowerUpGrant(FPlayer^, Variant);
  FPanelText := POWERUP_PREFIX + PowerUpName(Variant) + POWERUP_SUFFIX;

  { PowerUp_Show ends with Entity_Destroy @ 0x00461400, NOT a bare kill.
    FPool.Kill only clears EF_ALIVE; the destroy also hides the sprite and
    zeroes the depth, which is what actually makes the orb stop being drawn.
    Killing it left the ball sitting there after the panel closed. }
  if FWorld <> nil then
    FWorld.DestroyEntity(FPool.Entity(Slot)^, False)
  else
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

procedure TDialogueBox.PlayBoxSound(Index: Integer);
begin
  if Assigned(FOnSound) then
    FOnSound(Index);
end;

function TDialogueBox.Update(Confirm: Boolean; MoveX: Integer;
                             Moving: Boolean;
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
    { Overlay_Update's order when the fanfare ends: restore the music FIRST,
      then clear the overlay, then advance the script. }
    if Assigned(FOnResumeMusic) then
      FOnResumeMusic;
    FActive := False;
    Result := False;
    FPanelText := '';
    if (FRunner <> nil) and (FPlayer <> nil) then
      FRunner.AdvanceStep(FPlayer^, AGameState);
    Exit;
  end;

  { THE PROMPT IS HORIZONTAL. 0x00456038's mode 4 draws "Yes       No  " as one
    string at x 0x70 and puts the cursor at choice * 0x34 + 0x60 - side by
    side - and moves it on AxisX:

        if ((*(int *)p_InputState != 0) && (p_InputState[0x10] == 0)) {
            PlaySound(0);
            *PTR_DAT_0046cf70 += *(int *)p_InputState;
            clamp to 0..1

    p_InputState + 0 is AxisX and +0x10 is Moving, so it is a fresh press of
    left or right, and the delta is ADDED and then clamped rather than each
    direction selecting a fixed side. This took Up and Down, which is the one
    axis the original does not read here. }
  if FPrompt and (MoveX <> 0) and not Moving then
  begin
    PlayBoxSound(SND_PI);
    Inc(FChoice, MoveX);
    if FChoice < 0 then FChoice := 0;
    if FChoice > 1 then FChoice := 1;
  end;

  if not Confirm then
    Exit;

  if FPrompt then
  begin
    { Sound 1 on choosing, which the original plays before it writes. }
    PlayBoxSound(SND_OK);
    { BOTH flags, which is what 0x00456038 writes - see the header. Writing
      only Progress[3] left every script that guards on "No" unable to see
      the answer at all. }
    if FPlayer <> nil then
      DialogueAnswer(FPlayer^, FChoice);
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
    { Centred on a 6-pixel step - the original computes
      (0x140 - len * 6) >> 1 and then draws with a PROPORTIONAL font, so the
      step is a centring convention rather than the real glyph width. }
    Game_DrawTextOutlined((PANEL_W - Length(FPanelText) * PANEL_CHAR_W) div 2,
                          PANEL_TEXT_Y, FPanelText,
                          PANEL_TEXT_OUTLINE, PANEL_TEXT_FILL,
                          OUTLINED_FONT_SIZE, Dest);
    Exit;
  end;

  { Out of the player's way, as Overlay_Update does it. }
  if PlayerScreenY < BOX_PLAYER_SPLIT then
    BoxY := BOX_LOW_Y
  else
    BoxY := BOX_HIGH_Y;

  DrawFrame(Dest, BOX_X, BoxY + BOX_FRAME_DY, BOX_ROWS, BOX_COLS);

  for I := 0 to BOX_LINES - 1 do
    if FLines[I] <> '' then
      Game_DrawTextOutlined(BOX_TEXT_X,
                            BoxY + BOX_FIRST_LINE + I * BOX_LINE_STEP,
                            FLines[I], BOX_TEXT_OUTLINE, BOX_TEXT_FILL,
                            OUTLINED_FONT_SIZE, Dest);

  if FPrompt then
    Game_DrawTextOutlined(MB_PROMPT_TEXT_X, BoxY + MB_PROMPT_TEXT_DY,
                          MB_PROMPT_TEXT,
                          MB_PROMPT_OUTLINE, MB_PROMPT_FILL,
                          OUTLINED_FONT_SIZE, Dest);
end;

end.
