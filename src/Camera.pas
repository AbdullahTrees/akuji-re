{ Camera - the scrolling dead zone. Four functions every moving thing goes
  through:

      0x00459C1C  Camera_ShouldScrollX    0x00459D9C  Camera_ApplyMoveX
      0x00459CD8  Camera_ShouldScrollY    0x00459E08  Camera_ApplyMoveY

  THERE IS NO CAMERA-FOLLOWS-PLAYER CODE. Each movement step asks whether the
  entity is outside a dead zone and still heading out; if so the move is
  applied to the LAYER instead - the entity's position is put back and the
  scroll origin takes the delta.

  So an entity's position is a WORLD position, and the player's simply STOPS
  CHANGING while the view is scrolling. Anything that infers "the player moved
  because its position changed" is wrong for that reason.

  Dead zone, against SCREEN_W 320 / SCREEN_H 240:

      X   below 144, or at/above 177     (asymmetric: it brackets the
      Y   below 104, or at/above 137      player's width, not a point)

  Scrolling stops at the map edge:

      max scroll X = (MapWidthTiles  - 10.0) * TileWidth
      max scroll Y = (MapHeightTiles -  7.5) * TileHeight

  The Y constant is a 4-byte float at 0x00459D98 - the only FPU code in the
  game layer - because 240 is not a whole number of 32-pixel tiles. Rounding
  it would leave a black strip or cut the bottom row. --selftest-camera checks
  both against all 65 shipped maps. }

unit Camera;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Entities;

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
                     Scroll, Blocked: Boolean;
                     E: PEntity = nil; World: TEntityWorld = nil);

implementation

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

{ Camera_ShouldScrollX @ 0x00459C1C.

  The destination is converted with PixelOf, NOT OriginPixel - the original
  writes `origin + vel - 0x10000`, and `- 0xFFE1` when that goes negative,
  which is 0x10000 minus 31. That is the bias-subtracting form.

  It was OriginPixel here, which leaves POSITION_BIAS in: 2048 pixels of it.
  MaxScrollX for a 30-tile map is 640, so the "would this take the view off
  the map?" test compared 2048-and-up against 640 and refused EVERY scroll.
  The camera never followed the player at all, and the player simply walked
  off the right of the screen.

  The two conversions are one character apart in the source and 2048 pixels
  apart in effect. Nothing caught it because no test moved a camera; the
  session self-test does now, and it walks the player out of the dead zone
  and requires the view to follow. }
function ShouldScrollX(const L: TLayerInfo; PixelX, Vel: Integer): Boolean;
var
  Dest: Integer;
begin
  Result := False;
  if not (((PixelX < DEADZONE_LEFT) and (Vel < 0)) or
          ((PixelX >= DEADZONE_RIGHT) and (Vel > 0))) then
    Exit;
  Dest := PixelOf(L.OriginX + Vel);
  if (Vel < 0) and (Dest < 0) then
    Exit;
  if (Vel > 0) and (Dest > MaxScrollX(L)) then
    Exit;
  Result := True;
end;

{ Camera_ShouldScrollY @ 0x00459CD8. }
function ShouldScrollY(const L: TLayerInfo; PixelY, Vel: Integer): Boolean;
var
  Dest: Integer;
begin
  Result := False;
  if not (((PixelY < DEADZONE_TOP) and (Vel < 0)) or
          ((PixelY >= DEADZONE_BOTTOM) and (Vel > 0))) then
    Exit;
  Dest := PixelOf(L.OriginY + Vel);
  if (Vel < 0) and (Dest < 0) then
    Exit;
  if (Vel > 0) and (Dest > MaxScrollY(L)) then
    Exit;
  Result := True;
end;

{ Camera_ApplyMoveX @ 0x00459D9C. }
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

{ Camera_ApplyMoveY @ 0x00459E08. }
procedure ApplyMoveY(var L: TLayerInfo; var Pos, Vel: Integer;
                     Scroll, Blocked: Boolean;
                     E: PEntity; World: TEntityWorld);
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

  { 0x00459E08 ends with Entity_CheckKillTiles(entity, 0), unconditionally -
    the xref at 0x00459E73 - and that is what makes water lethal. The comment
    that stood here guessed it "recomputes the entity's tile-grid indices" and
    said it was not reproduced until it had been read. Read now: 0x004576B4
    sweeps the entity's box over the tile grid and, on the stage's kill tile,
    sets EF_STATE to 10 and clears +0x48. Without it the player fell through
    the water instead of dying.

    It lives HERE rather than at the call sites because the original puts it
    here: all four of its callers are player states, and a check that has to be
    remembered four times is one that gets forgotten once. }
  if (E <> nil) and (World <> nil) then
    EntityCheckKillTiles(E^, L, World.Tiles, World.KillTile);
end;

end.
