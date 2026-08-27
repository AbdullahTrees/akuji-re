{ Camera - the scrolling dead zone, translated from four functions that every
  moving thing in the game goes through:

      0x00459C1C  Camera_ShouldScrollX    "should the world move instead?"
      0x00459CD8  Camera_ShouldScrollY
      0x00459D9C  Camera_ApplyMoveX       commit the move, one way or the other
      0x00459E08  Camera_ApplyMoveY

  ## The trick

  There is no camera-follows-player code anywhere. Instead every movement step
  asks whether the entity is outside a dead zone in the middle of the screen
  and heading further out. If it is, the move is applied to the LAYER rather
  than to the entity: the entity's position is put back and the layer's scroll
  origin takes the delta instead. The player then appears to stay put while
  the world slides underneath, which is the same thing seen from the other side
  and costs nothing extra.

  Consequently the entity's stored position is a WORLD position and the layer
  origin is subtracted at draw time, but the player's world position simply
  stops changing while it is scrolling. Anything that assumes "the player moved
  because its position changed" is wrong for exactly this reason.

  ## The dead zone

      X   scroll below 144, or at/above 177     (SCREEN_W = 320, centre 160)
      Y   scroll below 104, or at/above 137      (SCREEN_H = 240, centre 120)

  The X pair is asymmetric about the centre because it brackets the player's
  own width rather than a point.

  ## The clamp, and why one of them is a float

  Scrolling stops when the view reaches the edge of the map:

      max scroll X = (MapWidthTiles  - 10.0) * TileWidth
      max scroll Y = (MapHeightTiles -  7.5) * TileHeight

  10 is 320/32 and 7.5 is 240/32. The X constant is an integer in the binary
  and the Y constant is the 4-byte float 0x40F00000 at 0x00459D98 - the only
  FPU code in the game's own layer, and it is there because 240 is not a whole
  number of 32-pixel tiles. Rounding it to 7 or 8 would leave a strip of black
  or cut the bottom row off.

  Both are checked against the shipped maps by --selftest-camera: for all 65
  of them the formula equals MapPixels - ScreenSize EXACTLY, with no slack. A
  wrong constant, a wrong field, or the wrong one of the pair would not survive
  that on even one map, let alone all 65. }

unit Camera;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils;

const
  { The dead zone, read out of the two ShouldScroll functions. The comparisons
    there are >= LEFT / <= RIGHT on the pixel position, so these are the first
    pixel INSIDE the zone on each side. }
  DEADZONE_LEFT   = $90;   { 144; the test is  Pixel <  LEFT   and moving left }
  DEADZONE_RIGHT  = $B1;   { 177; the test is  Pixel >= RIGHT  and moving right }
  DEADZONE_TOP    = $68;   { 104 }
  DEADZONE_BOTTOM = $89;   { 137 }

  { The screen, in whole tiles. Held as Single because 240/32 is not an
    integer; see the header. }
  VIEW_TILES_X: Single = 10.0;
  VIEW_TILES_Y: Single = 7.5;

type
  { p_LayerInfo @ 0x00483BF4. A plain global struct, not a pointer - the
    original indexes it directly.

    Origin is in the same biased 1/32-pixel units as an entity position, so
    PixelOf applies to it unchanged. Delta is what the layer moved THIS frame,
    in 1/32 pixel, and exists so the parallax and the riding code can follow a
    scroll they did not cause. }
  TLayerInfo = record
    OriginX:    Integer;   // +0x00
    OriginY:    Integer;   // +0x04
    DeltaX:     Integer;   // +0x08
    DeltaY:     Integer;   // +0x0C
    TileW:      Integer;   // +0x10
    TileH:      Integer;   // +0x14
    MapTilesX:  Integer;   // +0x18
    MapTilesY:  Integer;   // +0x1C
  end;

{ How far the layer origin may travel before the view leaves the map. }
function MaxScrollX(const L: TLayerInfo): Integer;
function MaxScrollY(const L: TLayerInfo): Integer;

{ Would moving by Vel scroll the layer instead of the entity? PixelX/PixelY are
  the entity's CURRENT screen position, already converted. }
function ShouldScrollX(const L: TLayerInfo; PixelX, Vel: Integer): Boolean;
function ShouldScrollY(const L: TLayerInfo; PixelY, Vel: Integer): Boolean;

{ Commit the move. Pos and Vel are the entity's, in 1/32 pixel and biased.
  Scroll comes from ShouldScroll*; Blocked says a collision already clamped
  Vel, in which case the velocity is also zeroed. }
procedure ApplyMoveX(var L: TLayerInfo; var Pos, Vel: Integer;
                     Scroll, Blocked: Boolean);
procedure ApplyMoveY(var L: TLayerInfo; var Pos, Vel: Integer;
                     Scroll, Blocked: Boolean);

implementation

uses
  Entities;

{ The original rounds the layer origin with `if x < 0 then x := x + 31` and no
  bias subtraction, where an entity position gets the biased form. The bias
  cancels in the subtraction that follows it, so this is not a discrepancy -
  but it is why this is written out rather than reusing PixelOf. }
function OriginPixel(Raw: Integer): Integer;
begin
  if Raw < 0 then
    Result := (Raw + 31) shr POSITION_SHIFT
  else
    Result := Raw shr POSITION_SHIFT;
end;

function MaxScrollX(const L: TLayerInfo): Integer;
begin
  Result := (L.MapTilesX - 10) * L.TileW;
end;

function MaxScrollY(const L: TLayerInfo): Integer;
begin
  { Trunc, not Round: FCOMPP against the integer pixel value is a plain
    ordered compare, so the fractional half is simply carried through. With
    TileH = 32 the product is exact anyway. }
  Result := Trunc((L.MapTilesY - VIEW_TILES_Y) * L.TileH);
end;

function ShouldScrollX(const L: TLayerInfo; PixelX, Vel: Integer): Boolean;
var
  Dest: Integer;
begin
  Result := False;
  if not (((PixelX < DEADZONE_LEFT) and (Vel < 0)) or
          ((PixelX >= DEADZONE_RIGHT) and (Vel > 0))) then
    Exit;
  Dest := OriginPixel(L.OriginX + Vel);
  if (Vel < 0) and (Dest < 0) then
    Exit;
  if (Vel > 0) and (Dest > MaxScrollX(L)) then
    Exit;
  Result := True;
end;

function ShouldScrollY(const L: TLayerInfo; PixelY, Vel: Integer): Boolean;
var
  Dest: Integer;
begin
  Result := False;
  if not (((PixelY < DEADZONE_TOP) and (Vel < 0)) or
          ((PixelY >= DEADZONE_BOTTOM) and (Vel > 0))) then
    Exit;
  Dest := OriginPixel(L.OriginY + Vel);
  if (Vel < 0) and (Dest < 0) then
    Exit;
  if (Vel > 0) and (Dest > MaxScrollY(L)) then
    Exit;
  Result := True;
end;

procedure ApplyMoveX(var L: TLayerInfo; var Pos, Vel: Integer;
                     Scroll, Blocked: Boolean);
var
  Before: Integer;
begin
  Pos := Pos + Vel;
  if Scroll then
  begin
    Before := L.OriginX;
    Pos := Pos - Vel;              // put it back; the world moves instead
    L.OriginX := L.OriginX + Vel;
    L.DeltaX := (OriginPixel(Before) - OriginPixel(L.OriginX)) shl POSITION_SHIFT;
  end;
  if Blocked then
    Vel := 0;
end;

procedure ApplyMoveY(var L: TLayerInfo; var Pos, Vel: Integer;
                     Scroll, Blocked: Boolean);
var
  Before: Integer;
begin
  Pos := Pos + Vel;
  if Scroll then
  begin
    Before := L.OriginY;
    Pos := Pos - Vel;
    L.OriginY := L.OriginY + Vel;
    L.DeltaY := (OriginPixel(Before) - OriginPixel(L.OriginY)) shl POSITION_SHIFT;
  end;
  if Blocked then
    Vel := 0;
  { The original also calls 0x004576B4(entity, 0) here, which recomputes the
    entity's tile-grid indices after the move. Not reproduced until it is read;
    callers of this unit must not assume those are up to date. }
end;

end.
