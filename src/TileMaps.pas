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

  All 65 shipped files satisfy size = 24 + MapWidth*MapHeight*2 exactly. }

unit TileMaps;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Types, Surfaces;

const
  MAP_HEADER_SIZE = 24;

{ Where a tile id's picture sits in its tileset - row-major, from Load_Map
  @ 0x00466340, which pushes them to TileMap_DefineTile Y first and whose Rect
  builder takes that pair as (top, left). Here rather than inline because two
  unrelated things need them: the drawing code below, and Stages.pas's terrain
  animation table. }
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

{ Load_Map's registration loop, verbatim in effect:

      TileMap_DefineTile(map, i, surface, 1,
                         (i / SheetCols) * TileHeight,
                         (i % SheetCols) * TileWidth)

  for i in 0 .. SheetCols * SheetRows - 1. }
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

{ Positive modulus. Delphi's mod returns a negative answer for a negative
  operand; TileMap_Draw @ 0x0044D818 spells the negative case out, so this
  does too. }
function WrapMod(A, Span: Integer): Integer;
begin
  if Span <= 0 then
    Exit(0);
  if A < 0 then
    Result := ((Span - A - 1) div Span) * Span + A
  else
    Result := A mod Span;
end;

{ TileMap_Draw @ 0x0044D818. The map is a TORUS: the scroll is reduced modulo
  the map's pixel size and the tile indices wrap at both edges.

  This clamped until 2026-09-01, which agrees with wrapping on every shipped
  map because the camera never leaves them. It diverges the moment one does -
  a 448-pixel-tall map with the new game's ScrollY of 448 drew nothing at all.
  See notes/divergences.md. }
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
      { 0xFFFF is the original's "no tile"; it falls out of the range test. }
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
