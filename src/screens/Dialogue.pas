{ Dialogue box and power-up overlay. Event sub-op 3 waits until the dialogue
  box closes; the box then advances the script. Control codes are:
        \n  line break within a page
        \k  end of page, wait, then continue with the next
        \e  end of the message
        \w  a yes/no prompt whose answer goes in Progress[3]
  Pages contain three lines spaced 16 pixels apart. The box is placed above or
  below the player to avoid covering them. MessageBox_Update @ 0x00456038
  handles the typewriter and yes/no prompt.

  Markers are scanned in the priority order \w, \e, \k, \n. Text is processed
  in two-byte units for Shift-JIS compatibility. Prompt answers update
  complementary scratch flags: Progress[3] for yes and Progress[4] for no. }

unit Dialogue;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, GameFont, PlayerState, EventRunner, EventScripts,
  TileMaps,
  GameState, Entities, SoundTable;

const

  { MessageBox_Update @ 0x00456038. }

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

  { --- MessageBox_Update's typewriter and its two icons -------------------
    All four numbers below are the original's, and the units matter.

    THE REVEAL IS IN TWO-BYTE UNITS. 0x00456038 rebuilds the visible lines
    every frame by scanning Copy(text, i * 2 - 1, 2) from the page start to a
    cursor, so one step of that cursor uncovers TWO bytes. The text is
    Shift-JIS, which is what the pairing is for; in the English build that
    means two ASCII letters appear at a time. It is also why every marker is
    exactly two characters - they have to land on the same grid to be seen. }
  MB_REVEAL_TICKS   = 2;    { counter > 2, so a step every THIRD frame }

  { The \k prompt: six animation steps over a four-cell strip, 0 16 32 48 32
    16 - a ping-pong, read from the table at 0x0046CB2C through the pointer
    cell at 0x0046D050. }
  MB_KEY_FRAMES     = 6;
  MB_KEY_ANIM_TICKS = 4;    { timer > 4, so a step every FIFTH frame }
  MB_KEY_SPRITE_X: array[0..MB_KEY_FRAMES - 1] of Integer =
    (0, 16, 32, 48, 32, 16);

  { The yes/no hand: two frames, and slower. }
  MB_HAND_FRAMES     = 2;
  MB_HAND_ANIM_TICKS = 8;   { timer > 8, so a step every NINTH frame }

  { Both icons come out of surface slot 1 - the same sheet as the box frame -
    from a strip that starts 0x20 in. The \k prompt is the top row and the
    hand is the row below it, both 16x16:

        key   Rect(x + 0x20, 0,    x + 0x30, 0x10)   at (0xF8, box + 0x40)
        hand  Rect(f * 16 + 0x20, 0x10, ... 0x20)    at (c * 0x34 + 0x60,
                                                         box + 0x3C) }
  MB_ICON_SIZE   = $10;
  MB_ICON_SRC_X  = $20;
  MB_KEY_SRC_Y   = $00;
  MB_HAND_SRC_Y  = $10;
  MB_KEY_ICON_X  = $F8;
  MB_KEY_ICON_DY = $40;
  MB_HAND_ICON_X    = $60;
  MB_HAND_ICON_STEP = $34;
  MB_HAND_ICON_DY   = $3C;

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
    defined by MB_PROMPT_TEXT, MB_PROMPT_TEXT_X, and MB_PROMPT_TEXT_DY: one
    padded string on the third line.

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
    FBoxMode: Integer;        { p_MessageMode 0x0046CF28 - MB_MODE_* }
    FPageText: string;        { the page being typed, markers stripped }
    FReveal: Integer;         { p_Reveal 0x0046CF24, in TWO-BYTE units }
    FRevealTimer: Integer;    { 0x0046CBA4 }
    FAnimFrame: Integer;      { 0x0046D320 + 0x10 }
    FAnimTimer: Integer;      { 0x0046D320 + 0x14 }
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
    procedure DrawIcon(Dest: TCanvas; X, Y, SrcX, SrcY: Integer);
  public
    { Where the script and the state it answers into live. Set once. }
    { GameState_Reset's share of this object - see the body. }
    procedure Reset;
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
    { Sub-op 9. Every gallery book is `0000-04-118N/0000-09-0016/0000-08` -
      set the flag, play effect 16 (SND_GET01), destroy the entity - so the
      pickup sound is the script's, not the touch handler's. This override was
      missing, so Host.PlaySound reached TEventHost's empty default and the
      books were collected in silence. }
    function MessageBusy: Boolean; override;
    procedure PlaySound(Id: Integer); override;
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
    function  GetVisibleLine(Index: Integer): string;
    procedure BuildLines;
    function  RevealUnits: Integer;
    procedure EndOfPage;
    function Update(Confirm: Boolean; const Inp: TInputState;
                    var AGameState: Integer): Boolean;

    procedure Draw(Dest: TCanvas; Font: TGameFont; PlayerScreenY: Integer);

    property Active: Boolean read FActive;
    { Read-only, for the tests. Observation only - nothing here gates any
      behaviour, and the original has no counterpart because in the original
      these ARE the globals 0x0046CF28, 0x0046D320+0x10 and 0x0046CF70. }
    property BoxMode: Integer read FBoxMode;
    property AnimFrame: Integer read FAnimFrame;
    property Choice: Integer read FChoice;
    property VisibleLine[Index: Integer]: string read GetVisibleLine;
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
  CharacterIndex: Integer;
begin
  Rest := '';
  Prompt := False;
  CharacterIndex := 1;
  while CharacterIndex < Length(Text) do
  begin
    if Text[CharacterIndex] = '\' then
      case Text[CharacterIndex + 1] of
        'k':
          begin
            { End of page. The rest is the next page. }
            Result := Copy(Text, 1, CharacterIndex - 1);
            Rest := Copy(Text, CharacterIndex + 2, MaxInt);
            Exit;
          end;
        'e':
          begin
            Result := Copy(Text, 1, CharacterIndex - 1);
            Exit;
          end;
        'w':
          begin
            Prompt := True;
            Result := Copy(Text, 1, CharacterIndex - 1);
            Rest := Copy(Text, CharacterIndex + 2, MaxInt);
            Exit;
          end;
      end;
    Inc(CharacterIndex);
  end;
  Result := Text;
end;

procedure TDialogueBox.TakePage(const Text: string);
var
  SourceText, PageText, UnusedLine: string;
  UnusedLineIndex, UnusedPosition: Integer;
begin
  { These unused locals preserve the v1.0 runtime image's stack/finalization
    shape. }
  { COPY FIRST. Update calls TakePage(FRest), and SplitPage's Rest is an out
    parameter bound to that same FRest - so the first thing SplitPage does,
    clearing Rest, would blank the string it is about to read. A const string
    parameter is a reference, not a snapshot. Every message with a \k would
    have lost its second page. }
  SourceText := Text;
  PageText := SplitPage(SourceText, FRest, FPrompt);

  { Keep the page whole and split only the revealed prefix into visible lines. }
  FPageText := PageText;
  FReveal := 0;
  FRevealTimer := 0;
  FAnimFrame := 0;
  FAnimTimer := 0;
  FChoice := 0;
  FBoxMode := MB_MODE_TYPING;
  BuildLines;
end;

{ How many two-byte units the page holds - see MB_REVEAL_TICKS. An odd length
  still has a last unit, hence the round up. }
function TDialogueBox.RevealUnits: Integer;
begin
  Result := (Length(FPageText) + 1) div 2;
end;

{ The visible lines, rebuilt from scratch each frame exactly as 0x00456038
  does it: walk the page in two-byte units up to the cursor, start a new line
  on \n, append anything else. }
procedure TDialogueBox.BuildLines;
var
  UnitIndex, LineIndex: Integer;
  Pair: string;
begin
  for LineIndex := 0 to BOX_LINES - 1 do
    FLines[LineIndex] := '';
  LineIndex := 0;
  for UnitIndex := 1 to FReveal do
  begin
    if LineIndex >= BOX_LINES then
      Break;
    Pair := Copy(FPageText, UnitIndex * 2 - 1, 2);
    if Pair = '\n' then
      Inc(LineIndex)
    else
      FLines[LineIndex] := FLines[LineIndex] + Pair;
  end;
end;

{ What happens when the last character has been uncovered. The marker that
  ended the page decides, and SplitPage has already told us which it was. }
procedure TDialogueBox.EndOfPage;
begin
  FAnimFrame := 0;
  FAnimTimer := 0;
  if FPrompt then
  begin
    { Mode 4's first frame plays 0xD - kakunin, "confirmation". }
    FBoxMode := MB_MODE_PROMPT;
    FChoice := 0;
    PlayBoxSound(SND_KAKUNIN);
  end
  else if FRest <> '' then
    FBoxMode := MB_MODE_WAITKEY
  else
    FBoxMode := MB_MODE_END;
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
  TileWidth, TileHeight: Integer;
begin
  if FPlayer = nil then
    Exit;
  { The shipped maps are all 32x32, but the map header carries the size and
    the original multiplies by the LAYER's value, so this does too. The
    fallback is only for a world that has not loaded a map yet. }
  TileWidth := 32;
  TileHeight := 32;
  if FWorld <> nil then
  begin
    if FWorld.Layer.TileW > 0 then
      TileWidth := FWorld.Layer.TileW;
    if FWorld.Layer.TileH > 0 then
      TileHeight := FWorld.Layer.TileH;
  end;
  FPlayer^.SpawnX  := PlayerTileX * TileWidth + SPAWN_CENTRE_X;
  FPlayer^.SpawnY  := PlayerTileY * TileHeight + SPAWN_FOOT_Y;
  FPlayer^.ScrollX := CamTileX * TileWidth;
  FPlayer^.ScrollY := CamTileY * TileHeight;
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

{ 0x0046CF28 non-zero: a three-line box is up. The panel is the overlay's
  flag (0x0046CD00) and is guarded separately, by SubMode. }
function TDialogueBox.MessageBusy: Boolean;
begin
  Result := FActive and (FMode = omBox);
end;

procedure TDialogueBox.PlaySound(Id: Integer);
begin
  PlayBoxSound(Id);
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
{ One 16x16 cell of slot 1's icon strip, which starts MB_ICON_SRC_X in.
  Opaque, exactly as DrawFrame blits the box out of the same sheet - the real
  one goes through TDDDD_DrawSprite with the component's colour key, which is
  DIV-008's territory rather than this unit's. }
procedure TDialogueBox.DrawIcon(Dest: TCanvas; X, Y, SrcX, SrcY: Integer);
begin
  if FFrameSheet = nil then
    Exit;
  FFrameSheet.Transparent := False;
  Dest.CopyRect(
    Rect(X, Y, X + MB_ICON_SIZE, Y + MB_ICON_SIZE),
    FFrameSheet.Canvas,
    Rect(MB_ICON_SRC_X + SrcX, SrcY,
         MB_ICON_SRC_X + SrcX + MB_ICON_SIZE, SrcY + MB_ICON_SIZE));
end;

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

  { Do not require the event entity to be alive. Power-up events destroy their
    entity before sub-op 10 reads its retained variant. SLOT_NONE is still
    rejected to avoid an invalid pool access. }
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

function TDialogueBox.GetVisibleLine(Index: Integer): string;
begin
  if (Index < 0) or (Index >= BOX_LINES) then
    Result := ''
  else
    Result := FLines[Index];
end;

procedure TDialogueBox.PlayBoxSound(Index: Integer);
begin
  if Assigned(FOnSound) then
    FOnSound(Index);
end;

function TDialogueBox.Update(Confirm: Boolean; const Inp: TInputState;
                             var AGameState: Integer): Boolean;
var
  Ch: string;
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

  case FBoxMode of

    { --- 1, the typewriter ------------------------------------------------
      Inc the counter; on the third frame - or on ANY input, which is the
      fast-forward - uncover one two-byte unit and click. The click is
      suppressed for the full-width space and nothing else. }
    MB_MODE_TYPING:
      begin
        Inc(FRevealTimer);
        if (FRevealTimer > MB_REVEAL_TICKS) or (Inp.AxisY <> 0)
           or Inp.Button[0] or Inp.Button[1] then
        begin
          FRevealTimer := 0;
          if FReveal < RevealUnits then
          begin
            Inc(FReveal);
            Ch := Copy(FPageText, FReveal * 2 - 1, 2);
            if Ch <> MB_FULLWIDTH_SPACE then
              PlayBoxSound(SND_PI);
            BuildLines;
          end;
          if FReveal >= RevealUnits then
            EndOfPage;
        end;
      end;

    { --- 2, \k: wait for a key, with the animated button prompt ----------- }
    MB_MODE_WAITKEY:
      begin
        Inc(FAnimTimer);
        if FAnimTimer > MB_KEY_ANIM_TICKS then
        begin
          FAnimTimer := 0;
          FAnimFrame := (FAnimFrame + 1) mod MB_KEY_FRAMES;
        end;
        if ((Inp.AxisY <> 0) and not Inp.Moving) or Confirm then
        begin
          { The original clears the shared sub-phase here as well as advancing
            - 0x00456038's mode-2 arm is
                PTR_DAT_0046cc14 = 0; reveal++; pageStart = reveal; mode = 1;
            and 0x0046CC14 is ScreenPhase, the same global the pause menu and
            the game-over screen step through. It went unnoticed while this
            unit had no way to say so. }
          ScreenPhase := 0;
          TakePage(FRest);
        end;
      end;

    { --- 3, \e: the message is over -------------------------------------- }
    MB_MODE_END:
      begin
        if ((Inp.AxisX <> 0) and not Inp.Moving)
           or ((Inp.AxisY <> 0) and not Inp.Moving) or Confirm then
        begin
          FActive := False;
          Result := False;
          if (FRunner <> nil) and (FPlayer <> nil) then
            FRunner.AdvanceStep(FPlayer^, AGameState);
        end;
      end;

    { --- 4, \w: the yes/no prompt, with the animated hand ------------------
      HORIZONTAL. Mode 4 draws "Yes       No  " as one string at x 0x70 and
      puts the hand at choice * 0x34 + 0x60 - side by side - and moves the
      choice on AxisX with the Moving guard, ADDING the delta and then
      clamping rather than each direction selecting a fixed side. This once
      took Up and Down, which is the one axis the original does not read. }
    MB_MODE_PROMPT:
      begin
        if (Inp.AxisX <> 0) and not Inp.Moving then
        begin
          PlayBoxSound(SND_PI);
          Inc(FChoice, Inp.AxisX);
          if FChoice < 0 then FChoice := 0;
          if FChoice > 1 then FChoice := 1;
        end;
        Inc(FAnimTimer);
        if FAnimTimer > MB_HAND_ANIM_TICKS then
        begin
          FAnimTimer := 0;
          FAnimFrame := (FAnimFrame + 1) mod MB_HAND_FRAMES;
        end;
        if Confirm then
        begin
          { Sound 1 on choosing, which the original plays before it writes. }
          PlayBoxSound(SND_OK);
          { BOTH flags, which is what 0x00456038 writes - see the header.
            Writing only Progress[3] left every script that guards on "No"
            unable to see the answer at all. }
          if FPlayer <> nil then
            DialogueAnswer(FPlayer^, FChoice);
          FPrompt := False;
          FActive := False;
          Result := False;
          if (FRunner <> nil) and (FPlayer <> nil) then
            FRunner.AdvanceStep(FPlayer^, AGameState);
        end;
      end;
  end;
end;

{ What GameState_Reset @ 0x004653C8 zeroes on this side: the message box's
  page start and reveal cursor (0x0046CC98, 0x0046CF24), its mode
  (0x0046CF28), and the overlay's flag and mode (0x0046CD00, 0x0046CDA0).
  Called through TGameSession.OnResetHost, because the reset belongs to the
  session and this object belongs to the form.

  Placed ABOVE Draw deliberately: Draw is the last routine in this unit, so
  its frozen fingerprint runs to end-of-file and anything appended after it
  would move the hash without changing a statement. }
procedure TDialogueBox.Reset;
begin
  FActive := False;
  FMode := omBox;
  FBoxMode := MB_MODE_TYPING;
  FPageText := '';
  FRest := '';
  FPanelText := '';
  FReveal := 0;
  FRevealTimer := 0;
  FAnimFrame := 0;
  FAnimTimer := 0;
  FChoice := 0;
  FPrompt := False;
  BuildLines;
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

  { The two icons, both 16x16 out of slot 1's strip. Keyed off the MODE, not
    off FPrompt: the Yes/No line and its hand appear only once the page has
    finished typing, which is what mode 4 means. }
  if FBoxMode = MB_MODE_WAITKEY then
    DrawIcon(Dest, MB_KEY_ICON_X, BoxY + MB_KEY_ICON_DY,
             MB_KEY_SPRITE_X[FAnimFrame], MB_KEY_SRC_Y);

  if FBoxMode = MB_MODE_PROMPT then
  begin
    Game_DrawTextOutlined(MB_PROMPT_TEXT_X, BoxY + MB_PROMPT_TEXT_DY,
                          MB_PROMPT_TEXT,
                          MB_PROMPT_OUTLINE, MB_PROMPT_FILL,
                          OUTLINED_FONT_SIZE, Dest);
    DrawIcon(Dest, FChoice * MB_HAND_ICON_STEP + MB_HAND_ICON_X,
             BoxY + MB_HAND_ICON_DY,
             FAnimFrame * MB_ICON_SIZE, MB_HAND_SRC_Y);
  end;
end;

end.
