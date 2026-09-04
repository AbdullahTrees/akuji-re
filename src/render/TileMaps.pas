{ Level tilemaps use this little-endian layout:

      int32  MapWidth      tiles
      int32  MapHeight     tiles
      int32  TileWidth     pixels
      int32  TileHeight    pixels
      int32  SheetCols     tileset columns
      int32  SheetRows     tileset rows
      uint16 [MapWidth * MapHeight]   tile indices, row-major

  The `TileMaps` unit name avoids a collision with LazUtils' `Maps` unit. }

unit TileMaps;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Types, Surfaces;

const
  MAP_HEADER_SIZE = 24;

{ Return a tile's row-major source position in its tileset. These helpers are
  shared by map drawing and terrain animation. }
function TileSrcX(TileId, TileW, SheetCols: Integer): Integer;
function TileSrcY(TileId, TileH, SheetCols: Integer): Integer;

type
  TTileMap = class
  private
    FMapW, FMapH: Integer;
    FTileW, FTileH: Integer;
    FSheetCols, FSheetRows: Integer;
    FTiles: array of Word;
    { Mutable source rectangles let background animation redefine one tile id
      everywhere it appears. }
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

    { Raw collision lookup. Unlike GetTile, the linear index permits an X outside
      0..MapWidth-1 to index the neighbouring row, so collision wraps
      horizontally for anything that walks off the side.

      An index outside the allocation returns 0. Drawing uses GetTile because a
      viewport needs two-dimensional bounds checking. }
    function TileAtRaw(X, Y: Integer): Integer;
    { Script-facing tile writer. Map entries are stored as unsigned words;
      invalid coordinates are ignored to protect the tile allocation. }
    procedure SetTileRaw(X, Y, Tile: Integer);

    { Repoint one tile id at a different tileset cell. Background animation
      changes this definition so every instance redraws with the new frame. }
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

function TTileMap.LoadFromFile(const FileName: string): Boolean;
var
  Stream: TFileStream;
  ExpectedSize: Int64;
begin
  Result := False;
  SetLength(FTiles, 0);
  if not FileExists(FileName) then
    Exit;

  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if Stream.Size < MAP_HEADER_SIZE then
      Exit;
    FMapW      := Integer(Stream.ReadDWord);
    FMapH      := Integer(Stream.ReadDWord);
    FTileW     := Integer(Stream.ReadDWord);
    FTileH     := Integer(Stream.ReadDWord);
    FSheetCols := Integer(Stream.ReadDWord);
    FSheetRows := Integer(Stream.ReadDWord);

    if (FMapW <= 0) or (FMapH <= 0) then
      Exit;

    { Every shipped map satisfies this exactly, so a mismatch means the header
      has been misread rather than that the file is merely unusual. }
    ExpectedSize := MAP_HEADER_SIZE + Int64(FMapW) * FMapH * 2;
    if Stream.Size <> ExpectedSize then
      Exit;

    SetLength(FTiles, FMapW * FMapH);
    Stream.ReadBuffer(FTiles[0], FMapW * FMapH * 2);
    BuildTileDefs;
    Result := True;
  finally
    Stream.Free;
  end;
end;

procedure TTileMap.BuildTileDefs;
var
  TileId, TileCount, SourceX, SourceY: Integer;
begin
  TileCount := FSheetCols * FSheetRows;
  SetLength(FTileDefs, TileCount);
  for TileId := 0 to TileCount - 1 do
  begin
    SourceX := TileSrcX(TileId, FTileW, FSheetCols);
    SourceY := TileSrcY(TileId, FTileH, FSheetCols);
    FTileDefs[TileId] := Rect(SourceX, SourceY,
                              SourceX + FTileW, SourceY + FTileH);
  end;
end;

{ SrcY precedes SrcX to match the animation data and all callers. A tilemap
  owns its tileset selection, so redefining a tile only needs to replace its
  source rectangle. Invalid tile identifiers are ignored. }
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
  TileIndex: Integer;
begin
  TileIndex := X + Y * FMapW;
  if (TileIndex < 0) or (TileIndex >= FMapW * FMapH) then
    Exit(0);
  Result := FTiles[TileIndex];
end;

procedure TTileMap.SetTileRaw(X, Y, Tile: Integer);
begin
  if (X < 0) or (Y < 0) or (X >= FMapW) or (Y >= FMapH) then
    Exit;
  FTiles[Y * FMapW + X] := Word(Tile);
end;

{ Positive modulus for scroll offsets on either side of the origin. }
function WrapMod(A, Span: Integer): Integer;
begin
  if Span <= 0 then
    Exit(0);
  if A < 0 then
    Result := ((Span - A - 1) div Span) * Span + A
  else
    Result := A mod Span;
end;

{ Draw the map as a torus: reduce scrolling by the map's pixel dimensions and
  wrap tile coordinates at both edges. }
procedure TTileMap.Draw(Dest: TCanvas; ASurfaces: TSurfaceSet;
  SurfaceIndex, OffsetX, OffsetY, ViewW, ViewH: Integer);
var
  TileSheet: TBitmap;
  MapPixelWidth, MapPixelHeight, ScrollX, ScrollY: Integer;
  StartPixelX, StartPixelY, YRemainder: Integer;
  FirstColumn, FirstRow, ColumnCount, RowCount: Integer;
  RowOffset, ColumnOffset, Column, Row, PixelX, PixelY, TileId: Integer;
begin
  if (ASurfaces = nil) or (Length(FTiles) = 0) then
    Exit;
  TileSheet := ASurfaces[SurfaceIndex];
  if TileSheet = nil then
    Exit;

  MapPixelWidth := FMapW * FTileW;
  MapPixelHeight := FMapH * FTileH;
  if (MapPixelWidth <= 0) or (MapPixelHeight <= 0) then
    Exit;

  ScrollX := WrapMod(OffsetX, MapPixelWidth);
  ScrollY := WrapMod(OffsetY, MapPixelHeight);

  { Negative, so the tile straddling the left edge is drawn too. }
  StartPixelX := -(ScrollX mod FTileW);
  YRemainder  := ScrollY mod FTileH;
  StartPixelY := -YRemainder;

  FirstColumn := (StartPixelX + ScrollX) div FTileW;
  FirstRow := (StartPixelY + ScrollY) div FTileH;

  ColumnCount := ((ViewW + FTileW - StartPixelX) - 1) div FTileW;
  RowCount := (ViewH + FTileH + YRemainder - 1) div FTileH;

  Row := WrapMod(FirstRow, FMapH);
  PixelY := StartPixelY;
  for RowOffset := 0 to RowCount - 1 do
  begin
    Column := WrapMod(FirstColumn, FMapW);
    PixelX := StartPixelX;
    for ColumnOffset := 0 to ColumnCount - 1 do
    begin
      { $FFFF is the empty-tile marker and fails the definition range test. }
      TileId := GetTile(Column, Row);
      if (TileId >= 0) and (TileId < Length(FTileDefs)) then
        Dest.CopyRect(Rect(PixelX, PixelY,
                           PixelX + FTileW, PixelY + FTileH),
                      TileSheet.Canvas, FTileDefs[TileId]);
      Inc(PixelX, FTileW);
      Inc(Column);
      if Column >= FMapW then
        Column := 0;
    end;
    Inc(PixelY, FTileH);
    Inc(Row);
    if Row >= FMapH then
      Row := 0;
  end;
end;

end.
