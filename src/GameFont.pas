{ GameFont - the game's bitmap font, translated from Game_DrawText @ 0x004511EC
  and Font_Define @ 0x004511A0.

  Font_Define fills a table at 0x0046E8A4 (0x20-byte stride, so several fonts
  can be defined). Four callers register font 0, always with the same nine
  arguments and never any other id - Title_Init @ 0x00462184, Stage_Begin @
  0x0046228E, GameOver_Update @ 0x00461AD3 and 0x00455F92. Re-registering the
  same font on every screen change is redundant, and it is what makes the
  arguments checkable: four independent copies of the same nine numbers.

      Font_Define(0, p_Surfaces[0], $20, $140, 8, 8, 9, 9, $5F)
                     surface   first  screenW  adv  ?  cellH cellW last

  The FIFTH argument - the second 8 - is stored at +0x18 and never read by
  anything. Game_DrawText uses +0x14 (the advance) for both the horizontal
  step and nothing else; there is no vertical advance because it draws one
  line. A field the writer fills and no reader touches.

  Game_DrawText then indexes the sheet:

      idx = ch - FirstChar
      col = idx mod 32            srcX = col * CellW
      row = idx div 32            srcY = row * CellH + CellH * Variant * 2
      dest x = X + charIndex * Advance
      centred: X = (ScreenW - Length(S) * Advance) div 2

  Note the axis order. This is the OBVIOUS one - column from mod, row from div
  - and it is the opposite of how a TILESET is indexed, where TileMaps.pas
  takes x from div and y from mod. The two sheets really do disagree in the
  original; they are cut by different code and neither is a mistake in the
  other's terms. Worth stating plainly, because the tileset order looks like a
  bug until you find the second function that confirms it.

  Verified against font9x9-01.bmp in bmp.qda: 288x54 is exactly 32 columns by
  6 rows of 9x9 cells - three colour variants of 64 glyphs each, which is the
  range $20..$5F. Note that is space through underscore: the font has NO
  LOWERCASE, which is why every string in the game is upper case.

  Colours, sampled from the sheet: all variants share a black background (the
  colour key) and a dark brown outline (61,35,35). Only the fill differs -
  variant 0 white, 1 pink (255,123,123), 2 peach (255,188,133). }

unit GameFont;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics;

const
  FONT_FIRST_CHAR = $20;   { space }
  FONT_LAST_CHAR  = $5F;   { underscore - no lowercase in the sheet }
  FONT_COLS       = 32;    { glyphs per sheet row }
  FONT_CELL_W     = 9;
  FONT_CELL_H     = 9;
  FONT_ADVANCE    = 8;     { one pixel less than the cell, so glyphs overlap }
  FONT_VARIANTS   = 3;
  FONT_KEY_COLOR  = clBlack;

type
  TGameFont = class
  private
    { Glyphs are pre-cut because LCL will not do a transparent blit from a
      sub-rectangle - Draw() honours TBitmap.Transparent, CopyRect does not.
      64 glyphs x 3 variants of 9x9 is trivial to hold. }
    FGlyphs: array of TBitmap;
    FVariants: Integer;
    function GlyphIndex(Ch: Char; AVariant: Integer): Integer;
  public
    constructor Create(Sheet: TBitmap);
    destructor Destroy; override;

    procedure TextOut(Dest: TCanvas; X, Y: Integer; const S: string;
                      AVariant: Integer = 0);
    { Centred in ScreenW, matching Game_DrawText's param_4 = 1 path. }
    procedure TextOutCentered(Dest: TCanvas; Y: Integer; const S: string;
                              ScreenW: Integer = 320; AVariant: Integer = 0);
    function TextWidth(const S: string): Integer;

    property Variants: Integer read FVariants;
  end;

implementation

constructor TGameFont.Create(Sheet: TBitmap);
var
  V, I, Col, Row, SrcX, SrcY: Integer;
  G: TBitmap;
begin
  inherited Create;
  FVariants := Sheet.Height div (FONT_CELL_H * 2);
  if FVariants < 1 then FVariants := 1;
  if FVariants > FONT_VARIANTS then FVariants := FONT_VARIANTS;

  SetLength(FGlyphs, FVariants * (FONT_LAST_CHAR - FONT_FIRST_CHAR + 1));

  for V := 0 to FVariants - 1 do
    for I := 0 to FONT_LAST_CHAR - FONT_FIRST_CHAR do
    begin
      Col := I mod FONT_COLS;
      Row := I div FONT_COLS;
      SrcX := Col * FONT_CELL_W;
      SrcY := Row * FONT_CELL_H + FONT_CELL_H * V * 2;

      G := TBitmap.Create;
      G.SetSize(FONT_CELL_W, FONT_CELL_H);
      G.Canvas.CopyRect(Rect(0, 0, FONT_CELL_W, FONT_CELL_H), Sheet.Canvas,
        Rect(SrcX, SrcY, SrcX + FONT_CELL_W, SrcY + FONT_CELL_H));
      G.TransparentColor := FONT_KEY_COLOR;
      G.Transparent := True;

      FGlyphs[V * (FONT_LAST_CHAR - FONT_FIRST_CHAR + 1) + I] := G;
    end;
end;

destructor TGameFont.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FGlyphs) do
    FGlyphs[I].Free;
  inherited Destroy;
end;

function TGameFont.GlyphIndex(Ch: Char; AVariant: Integer): Integer;
var
  C: Integer;
begin
  C := Ord(Ch);
  { Game_DrawText silently skips anything outside the range. Lowercase is
    folded up rather than dropped, since the sheet has no lowercase and the
    original's strings are all upper case anyway. }
  if (C >= Ord('a')) and (C <= Ord('z')) then
    Dec(C, 32);
  if (C < FONT_FIRST_CHAR) or (C > FONT_LAST_CHAR) then
    Exit(-1);
  if (AVariant < 0) or (AVariant >= FVariants) then
    AVariant := 0;
  Result := AVariant * (FONT_LAST_CHAR - FONT_FIRST_CHAR + 1)
            + (C - FONT_FIRST_CHAR);
end;

procedure TGameFont.TextOut(Dest: TCanvas; X, Y: Integer; const S: string;
  AVariant: Integer);
var
  I, G: Integer;
begin
  for I := 1 to Length(S) do
  begin
    G := GlyphIndex(S[I], AVariant);
    if G >= 0 then
      Dest.Draw(X + (I - 1) * FONT_ADVANCE, Y, FGlyphs[G]);
  end;
end;

function TGameFont.TextWidth(const S: string): Integer;
begin
  Result := Length(S) * FONT_ADVANCE;
end;

procedure TGameFont.TextOutCentered(Dest: TCanvas; Y: Integer; const S: string;
  ScreenW: Integer; AVariant: Integer);
begin
  TextOut(Dest, (ScreenW - TextWidth(S)) div 2, Y, S, AVariant);
end;

end.
