{ TileMaps - level tilemaps, translated from Load_Map @ 0x00466340.

  NOTE the unit name. It cannot be called "Maps": LazUtils already ships a Maps
  unit (TMap/TMapIterator) and LCL's Themes -> LCLIntf chain depends on it.
  Shadowing it breaks the LCL build with a misleading
  "Can't find unit LCLIntf used by Themes".

  Reads map\%.03d.map. Binary, little-endian:

      int32  MapWidth      tiles
      int32  MapHeight     tiles
      int32  TileWidth     pixels
      int32  TileHeight    pixels
      int32  SheetCols     tileset columns
      int32  SheetRows     tileset rows
      uint16 [MapWidth * MapHeight]   tile indices, row-major

  Validated: all 65 files satisfy size = 24 + MapWidth*MapHeight*2 exactly.
  001.map is 30x24 tiles of 32x32 - a 960x768 level from a 10x10 tileset.

  The original registers SheetCols*SheetRows tile graphics from a surface,
  cutting cell (i mod SheetCols, i div SheetCols), then fills the map:

      x = (i mod SheetCols) * TileWidth
      y = (i div SheetCols) * TileHeight

  which is the ordinary row-major reading, and Load_Map @ 0x00466340 is where
  it comes from:

      TileMap_DefineTile(map, i, surface, 1,
                         (i / SheetCols) * TileHeight,   <- Y
                         (i % SheetCols) * TileWidth)    <- X

  Note that Y is passed BEFORE X. TileMap_DefineTile hands the pair straight
  to the Rect builder as Rect(arg6, arg5, arg6 + TileW, arg5 + TileH), so
  arg5 is the top and arg6 the left, with no ambiguity.

  ## The transposition that was not there

  This header used to claim the opposite - x from div, y from mod - and call
  it "the other way round from the obvious reading, reproduced rather than
  corrected". That was wrong, and it is worth recording how it survived so
  long. The prose above it always said "cutting cell (i mod, i div)", which is
  right; only the formula below disagreed, because arg5 was read as X. Two
  contradictory statements sat in one comment and nothing compared them.

  It was then "confirmed" from Terrain_Configure, which hard-codes both the
  tile id and the source coordinates of thirty animation frames. Both readings
  fit those numbers - the transposed one only if you ALSO swap which pushed
  argument is which - and the swap that agreed with this file was chosen
  instead of testing both. That is confirmation bias, not evidence.

  What settled it was rendering map 001 with each reading and looking: the
  row-major one produces the room the game shows, and the transposed one
  produces scattered tiles on black, which is exactly what the reconstruction
  was drawing. }

unit TileMaps;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Types, Surfaces;

const
  MAP_HEADER_SIZE = 24;

{ Where a tile id's picture sits in its tileset - row-major, from Load_Map
  @ 0x00466340. Here rather than inline because two unrelated things need
  them: the drawing code below, and Stages.pas's terrain animation table. }
function TileSrcX(TileId, TileW, SheetCols: Integer): Integer;
function TileSrcY(TileId, TileH, SheetCols: Integer): Integer;

type
  TTileMap = class
  private
    FMapW, FMapH: Integer;
    FTileW, FTileH: Integer;
    FSheetCols, FSheetRows: Integer;
    FTiles: array of Word;
    { One source rect per tile id, exactly as the original's component keeps
      one 0x18-byte record per tile at Self+4+index*0x18. Load_Map fills it
      once with the row-major cell and NOTHING else would ever change it - but
      TMYBGANIME does, every few frames, which is the whole mechanism behind
      an animated background: it redefines the TILE, so every instance of that
      id on screen animates together. Computing the cell at draw time instead
      would look identical until something animates, and then it could not. }
    FTileDefs: array of TRect;
    procedure BuildTileDefs;
    function GetTile(X, Y: Integer): Word;
  public
    function LoadFromFile(const FileName: string): Boolean;
    { Loads map\%.03d.map relative to AGameDir. }
    function Load(const AGameDir: string; MapIndex: Integer): Boolean;

    { Draws the map into Dest using ASurfaces[SurfaceIndex] as the tileset.
      OffsetX/Y scroll the view; only visible tiles are touched. }
    procedure Draw(Dest: TCanvas; ASurfaces: TSurfaceSet; SurfaceIndex: Integer;
                   OffsetX, OffsetY, ViewW, ViewH: Integer);

    property MapWidth: Integer read FMapW;
    property MapHeight: Integer read FMapH;
    property TileWidth: Integer read FTileW;
    property TileHeight: Integer read FTileH;
    property SheetCols: Integer read FSheetCols;
    property SheetRows: Integer read FSheetRows;
    property Tiles[X, Y: Integer]: Word read GetTile; default;

    { TileMap_Get @ 0x0044DB5C, which is what the COLLISION code calls and is
      not the same function as GetTile above. It is one line - the Word at
      Data[X + Y * MapWidth] - with no bounds check at all, so an X outside
      0..MapWidth-1 indexes into the neighbouring row and the map wraps
      horizontally for anything that walks off the side. That is reproduced
      here because collision can reach it.

      What is NOT reproduced: an index outside the array altogether, which the
      original reads anyway. This returns 0 there. Drawing keeps GetTile, whose
      clamp is right for a viewport. }
    function TileAtRaw(X, Y: Integer): Integer;
    { Sub-op 14's writer - 0x0044DB3C, the setter beside TileMap_Get. The
      original stores a WORD, which is what the .map file holds, and it does
      not bounds-check; refusing out of range here is a guard against a Pascal
      range error rather than a behaviour, since a bad index in the original
      would corrupt a neighbouring row. }
    procedure SetTileRaw(X, Y, Tile: Integer);

    { 0x0044DAE0, TileMap_DefineTile. Repoints one tile id at a different cell
      of the tileset. This is how TMYBGANIME animates a background: it changes
      the TILE, so every instance of it redraws. }
    procedure DefineTile(TileId, SrcY, SrcX: Integer);
    function TileDef(TileId: Integer): TRect;
    function TileDefCount: Integer;
  end;

implementation

function TileSrcX(TileId, TileW, SheetCols: Integer): Integer;
begin
  if SheetCols = 0 then
    Exit(0);
  Result := (TileId mod SheetCols) * TileW;
end;

function TileSrcY(TileId, TileH, SheetCols: Integer): Integer;
begin
  if SheetCols = 0 then
    Exit(0);
  Result := (TileId div SheetCols) * TileH;
end;

function TTileMap.Load(const AGameDir: string; MapIndex: Integer): Boolean;
begin
  Result := LoadFromFile(IncludeTrailingPathDelimiter(AGameDir) + 'map' +
                         PathDelim + Format('%.3d.map', [MapIndex]));
end;

{ Load_Map @ 0x00466340. }
function TTileMap.LoadFromFile(const FileName: string): Boolean;
var
  S: TFileStream;
  Expected: Int64;
begin
  Result := False;
  SetLength(FTiles, 0);
  if not FileExists(FileName) then
    Exit;

  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if S.Size < MAP_HEADER_SIZE then
      Exit;
    FMapW      := Integer(S.ReadDWord);
    FMapH      := Integer(S.ReadDWord);
    FTileW     := Integer(S.ReadDWord);
    FTileH     := Integer(S.ReadDWord);
    FSheetCols := Integer(S.ReadDWord);
    FSheetRows := Integer(S.ReadDWord);

    if (FMapW <= 0) or (FMapH <= 0) then
      Exit;

    { Every shipped map satisfies this exactly, so a mismatch means the header
      has been misread rather than that the file is merely unusual. }
    Expected := MAP_HEADER_SIZE + Int64(FMapW) * FMapH * 2;
    if S.Size <> Expected then
      Exit;

    SetLength(FTiles, FMapW * FMapH);
    S.ReadBuffer(FTiles[0], FMapW * FMapH * 2);
    BuildTileDefs;
    Result := True;
  finally
    S.Free;
  end;
end;

{ Load_Map's registration loop, verbatim in effect:

      TileMap_DefineTile(map, i, surface, 1,
                         (i / SheetCols) * TileHeight,
                         (i % SheetCols) * TileWidth)

  for i in 0 .. SheetCols * SheetRows - 1. }
procedure TTileMap.BuildTileDefs;
var
  I, N, X, Y: Integer;
begin
  N := FSheetCols * FSheetRows;
  SetLength(FTileDefs, N);
  for I := 0 to N - 1 do
  begin
    X := TileSrcX(I, FTileW, FSheetCols);
    Y := TileSrcY(I, FTileH, FSheetCols);
    FTileDefs[I] := Rect(X, Y, X + FTileW, Y + FTileH);
  end;
end;

{ 0x0044DAE0. Note the argument order - SrcY before SrcX - which is the
  original's, and the reason it is kept is that every caller writes them that
  way round. See the unit header.

  THE ORIGINAL MAKES THREE WRITES per tile, into a 0x18-byte record at
  Self+4+id*0x18: the surface at +0, the rect at +4, and a byte at +0x14. This
  writes only the rect, and the rect is exact. Both omissions are safe and the
  callers are why - FUN_0044E2C0 (the anim tick) and Load_Tile_Data both pass a
  LITERAL 1 for the byte, and the surface is fixed per tilemap, chosen once by
  the loader and merely handed back by the animator, which is why BgAnime notes
  that this map already knows which sheet it draws from.

  THE BOUNDS CHECK IS OURS. The original masks the id with 0xffff and writes
  regardless, so an id past the 1026 records corrupts memory. Refusing to
  reproduce that is deliberate, and the guard cannot fire for either caller -
  both derive the id from the sheet dimensions. DIV-012 corroborates the layout
  from the other side. }
procedure TTileMap.DefineTile(TileId, SrcY, SrcX: Integer);
begin
  if (TileId < 0) or (TileId >= Length(FTileDefs)) then
    Exit;
  FTileDefs[TileId] := Rect(SrcX, SrcY, SrcX + FTileW, SrcY + FTileH);
end;

function TTileMap.TileDef(TileId: Integer): TRect;
begin
  if (TileId < 0) or (TileId >= Length(FTileDefs)) then
    Exit(Rect(0, 0, 0, 0));
  Result := FTileDefs[TileId];
end;

function TTileMap.TileDefCount: Integer;
begin
  Result := Length(FTileDefs);
end;

function TTileMap.GetTile(X, Y: Integer): Word;
begin
  if (X < 0) or (Y < 0) or (X >= FMapW) or (Y >= FMapH) then
    Exit(0);
  Result := FTiles[Y * FMapW + X];
end;

function TTileMap.TileAtRaw(X, Y: Integer): Integer;
var
  Idx: Integer;
begin
  Idx := X + Y * FMapW;
  if (Idx < 0) or (Idx >= FMapW * FMapH) then
    Exit(0);
  Result := FTiles[Idx];
end;

procedure TTileMap.SetTileRaw(X, Y, Tile: Integer);
begin
  if (X < 0) or (Y < 0) or (X >= FMapW) or (Y >= FMapH) then
    Exit;
  FTiles[Y * FMapW + X] := Word(Tile);
end;

{ The original's positive modulus, both branches. TileMap_Draw @ 0x0044D818
  reduces the scroll by it before doing anything else:

      if (scroll < 0) scroll = ((span - scroll) - 1) / span * span + scroll;
      else            scroll = scroll % span;

  Delphi's own mod would give a negative answer for a negative scroll, which
  is why the original spells the negative case out. }
function WrapMod(A, Span: Integer): Integer;
begin
  if Span <= 0 then Exit(0);
  if A < 0 then
    Result := ((Span - A - 1) div Span) * Span + A
  else
    Result := A mod Span;
end;

{ TileMap_Draw @ 0x0044D818.

  THE MAP WRAPS. This is the whole point of the function and it was missed on
  the first pass, which clamped instead:

      if X1 > FMapW then X1 := FMapW;
      if Y1 > FMapH then Y1 := FMapH;

  The original does not clamp anywhere. It reduces the scroll modulo the map's
  PIXEL size (+0x60A0 and +0x60A4), and then wraps the tile indices as it
  walks - `if (mapTilesX <= col) col = 0` at the right edge and the same for
  the row at the bottom. So the map is a torus: scroll past the edge and the
  opposite edge comes round.

  HOW THE DIFFERENCE SURFACED. Every shipped map is big enough that the camera
  never leaves it, so clamping and wrapping agree on all 65 of them and the
  bug was invisible. A hand-made map exactly 448 pixels tall then put the
  camera at DEFAULT_SCROLL_Y = 0x1C0 = 448 - precisely one map-height down -
  and the two readings diverged completely: the original wrapped to the top
  and drew the room, while this clamped every row away and drew nothing, so
  the screen was black and the player appeared to fall through the world.

  Nothing in the shipped game changes as a result of this fix; it only stops
  being wrong outside the range the shipped data happens to use. }
procedure TTileMap.Draw(Dest: TCanvas; ASurfaces: TSurfaceSet;
  SurfaceIndex, OffsetX, OffsetY, ViewW, ViewH: Integer);
var
  Sheet: TBitmap;
  MapPxW, MapPxH, SX, SY: Integer;
  StartPxX, StartPxY, RemY: Integer;
  FirstCol, FirstRow, Cols, Rows: Integer;
  R, C, Col, Row, PxX, PxY, Idx: Integer;
begin
  if (ASurfaces = nil) or (Length(FTiles) = 0) then Exit;
  Sheet := ASurfaces[SurfaceIndex];
  if Sheet = nil then Exit;

  MapPxW := FMapW * FTileW;
  MapPxH := FMapH * FTileH;
  if (MapPxW <= 0) or (MapPxH <= 0) then Exit;

  SX := WrapMod(OffsetX, MapPxW);
  SY := WrapMod(OffsetY, MapPxH);

  { The first column starts at a NEGATIVE pixel offset when the scroll is not
    a whole tile, so the partly-visible tile at the left is drawn too. }
  StartPxX := -(SX mod FTileW);
  RemY     := SY mod FTileH;
  StartPxY := -RemY;

  FirstCol := (StartPxX + SX) div FTileW;
  FirstRow := (StartPxY + SY) div FTileH;

  Cols := ((ViewW + FTileW - StartPxX) - 1) div FTileW;
  Rows := (ViewH + FTileH + RemY - 1) div FTileH;

  Row := WrapMod(FirstRow, FMapH);
  PxY := StartPxY;
  for R := 0 to Rows - 1 do
  begin
    Col := WrapMod(FirstCol, FMapW);
    PxX := StartPxX;
    for C := 0 to Cols - 1 do
    begin
      Idx := GetTile(Col, Row);
      { The original skips 0xFFFF - "no tile" - and complains about anything
        above 0x400; here anything without a definition is simply skipped. }
      if (Idx >= 0) and (Idx < Length(FTileDefs)) then
        Dest.CopyRect(Rect(PxX, PxY, PxX + FTileW, PxY + FTileH),
                      Sheet.Canvas, FTileDefs[Idx]);
      Inc(PxX, FTileW);
      Inc(Col);
      if Col >= FMapW then
        Col := 0;
    end;
    Inc(PxY, FTileH);
    Inc(Row);
    if Row >= FMapH then
      Row := 0;
  end;
end;

end.
