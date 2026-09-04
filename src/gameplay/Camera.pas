{ Camera movement and its asymmetric scrolling dead zone. Movement outside
  the dead zone updates the layer origin instead of the
  entity position. Entity positions therefore remain in world coordinates and
  can stay unchanged while the view scrolls. }

unit Camera;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Entities;

const
  { The first pixels inside each edge of the scrolling dead zone. }
  DEADZONE_LEFT   = $90;   { 144; the test is  Pixel <  LEFT   and moving left }
  DEADZONE_RIGHT  = $B1;   { 177; the test is  Pixel >= RIGHT  and moving right }
  DEADZONE_TOP    = $68;   { 104 }
  DEADZONE_BOTTOM = $89;   { 137 }

  { The 320x240 viewport expressed in 32-pixel tiles. The fractional height
    keeps the partly visible bottom row in the scroll calculation. }
  VIEW_TILES_X: Single = 10.0;
  VIEW_TILES_Y: Single = 7.5;

{ How far the layer origin may travel before the view leaves the map:
  (MapTiles - VIEW_TILES) * TileSize. }
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
  { Tile heights are integral, but the viewport height may include half a
    tile. Truncation converts the resulting limit to a pixel coordinate. }
  Result := Trunc((L.MapTilesY - VIEW_TILES_Y) * L.TileH);
end;

{ Convert the biased destination before comparing it with map bounds. }
function ShouldScrollX(const L: TLayerInfo; PixelX, Vel: Integer): Boolean;
var
  DestinationPixel: Integer;
begin
  Result := False;
  if not (((PixelX < DEADZONE_LEFT) and (Vel < 0)) or
          ((PixelX >= DEADZONE_RIGHT) and (Vel > 0))) then
    Exit;
  DestinationPixel := PixelOf(L.OriginX + Vel);
  if (Vel < 0) and (DestinationPixel < 0) then
    Exit;
  if (Vel > 0) and (DestinationPixel > MaxScrollX(L)) then
    Exit;
  Result := True;
end;

function ShouldScrollY(const L: TLayerInfo; PixelY, Vel: Integer): Boolean;
var
  DestinationPixel: Integer;
begin
  Result := False;
  if not (((PixelY < DEADZONE_TOP) and (Vel < 0)) or
          ((PixelY >= DEADZONE_BOTTOM) and (Vel > 0))) then
    Exit;
  DestinationPixel := PixelOf(L.OriginY + Vel);
  if (Vel < 0) and (DestinationPixel < 0) then
    Exit;
  if (Vel > 0) and (DestinationPixel > MaxScrollY(L)) then
    Exit;
  Result := True;
end;

procedure ApplyMoveX(var L: TLayerInfo; var Pos, Vel: Integer;
                     Scroll, Blocked: Boolean);
var
  PreviousOrigin: Integer;
begin
  Pos := Pos + Vel;
  if Scroll then
  begin
    PreviousOrigin := L.OriginX;
    Pos := Pos - Vel;              // put it back; the world moves instead
    L.OriginX := L.OriginX + Vel;
    L.DeltaX := (OriginPixel(PreviousOrigin) - OriginPixel(L.OriginX))
      shl POSITION_SHIFT;
  end;
  if Blocked then
    Vel := 0;
end;

procedure ApplyMoveY(var L: TLayerInfo; var Pos, Vel: Integer;
                     Scroll, Blocked: Boolean;
                     E: PEntity; World: TEntityWorld);
var
  PreviousOrigin: Integer;
begin
  Pos := Pos + Vel;
  if Scroll then
  begin
    PreviousOrigin := L.OriginY;
    Pos := Pos - Vel;
    L.OriginY := L.OriginY + Vel;
    L.DeltaY := (OriginPixel(PreviousOrigin) - OriginPixel(L.OriginY))
      shl POSITION_SHIFT;
  end;
  if Blocked then
    Vel := 0;

  { ApplyMoveY always checks the entity's bounds for lethal terrain after
    movement. Keeping the check here covers every player movement state. }
  if (E <> nil) and (World <> nil) then
    EntityCheckKillTiles(E^, L, World.Tiles, World.KillTile);
end;

end.
