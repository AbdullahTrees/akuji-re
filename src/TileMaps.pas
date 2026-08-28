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
  way round. See the unit header. }
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

procedure TTileMap.Draw(Dest: TCanvas; ASurfaces: TSurfaceSet;
  SurfaceIndex, OffsetX, OffsetY, ViewW, ViewH: Integer);
var
  Sheet: TBitmap;
  X0, Y0, X1, Y1, TX, TY, Idx, SrcX, SrcY, DX, DY: Integer;
begin
  if (ASurfaces = nil) or (Length(FTiles) = 0) then Exit;
  Sheet := ASurfaces[SurfaceIndex];
  if Sheet = nil then Exit;

  X0 := OffsetX div FTileW;
  Y0 := OffsetY div FTileH;
  X1 := (OffsetX + ViewW) div FTileW + 1;
  Y1 := (OffsetY + ViewH) div FTileH + 1;
  if X0 < 0 then X0 := 0;
  if Y0 < 0 then Y0 := 0;
  if X1 > FMapW then X1 := FMapW;
  if Y1 > FMapH then Y1 := FMapH;

  for TY := Y0 to Y1 - 1 do
    for TX := X0 to X1 - 1 do
    begin
      Idx := GetTile(TX, TY);
      if Idx >= FSheetCols * FSheetRows then
        Continue;

      { From the per-tile table, not recomputed - see FTileDefs. }
      if (Idx < 0) or (Idx >= Length(FTileDefs)) then
        Continue;

      DX := TX * FTileW - OffsetX;
      DY := TY * FTileH - OffsetY;
      Dest.CopyRect(Rect(DX, DY, DX + FTileW, DY + FTileH), Sheet.Canvas,
                    FTileDefs[Idx]);
    end;
end;

end.
