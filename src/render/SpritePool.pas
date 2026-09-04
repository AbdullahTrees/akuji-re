{ Fixed pool of live sprites. Entity collision extents come from the allocated
  sprite frame, so allocation and release are gameplay-critical as well as
  visual. Released slots are hidden, reset to depth zero, and reused. }

unit SpritePool;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Types, Entities, Sprites, Surfaces;

const
  { Entity spawning fails when all slots are occupied. }
  SPRITE_POOL_SIZE = 256;

  { Main sprite depths and the separate above-interface layer. }
  SPRITE_DEPTH_FIRST     = 1;   { bucket 0 is never drawn }
  SPRITE_DEPTH_MAIN_LAST = 7;
  SPRITE_DEPTH_TOP       = 8;   { drawn after the HUD, not with the rest }

type
  { The slot numbers to draw, already in order - see DrawOrder. }
  TSpriteOrder = array of Integer;

  TSpriteSlot = record
    Used:    Boolean;
    Visible: Boolean;
    AnimId:  Integer;
    X, Y:    Integer;
    Depth:   Integer;
  end;

  TSpritePool = class(TSpriteSink)
  private
    FSlots: array[0..SPRITE_POOL_SIZE - 1] of TSpriteSlot;
    FFrames: TSpriteSet;
    function FrameRect(AnimId: Integer; out FrameBounds: TRect): Boolean;
  public
    constructor Create;
    procedure Clear;

    { Live handles survive frame-table changes; animation ids are set-local. }
    property Frames: TSpriteSet read FFrames write FFrames;

    function AllocSprite(AnimId: Integer): Integer; override;
    procedure ReleaseSprite(Handle: Integer); override;

    procedure SetVisible(Handle: Integer; Visible: Boolean); override;
    function  GetVisible(Handle: Integer): Boolean; override;
    procedure SetAnim(Handle, AnimId: Integer); override;
    function  Width(Handle: Integer): Integer; override;
    function  Height(Handle: Integer): Integer; override;
    procedure SetPos(Handle, X, Y: Integer); override;
    procedure SetDepth(Handle, Depth: Integer); override;

    { Draws every visible sprite, shallowest depth last. }
    { The screen shake displaces every live sprite by the same amount, once a
      frame, AFTER Entity_UpdateAll has written their positions - so it is a
      displacement of this frame's value, not an accumulation. }
    procedure ShiftY(Delta: Integer);
    function DrawOrder: TSpriteOrder;
    procedure DrawAll(Dest: TCanvas; ASurfaces: TSurfaceSet);
    procedure DrawTop(Dest: TCanvas; ASurfaces: TSurfaceSet);

    function LiveCount: Integer;
  end;

implementation

constructor TSpritePool.Create;
begin
  inherited Create;
  Clear;
end;

procedure TSpritePool.Clear;
var
  Slot: Integer;
begin
  for Slot := 0 to SPRITE_POOL_SIZE - 1 do
  begin
    FSlots[Slot].Used := False;
    FSlots[Slot].Visible := False;
    FSlots[Slot].AnimId := -1;
    FSlots[Slot].X := 0;
    FSlots[Slot].Y := 0;
    FSlots[Slot].Depth := 0;
  end;
end;

function TSpritePool.FrameRect(AnimId: Integer; out FrameBounds: TRect): Boolean;
begin
  Result := False;
  FrameBounds := Rect(0, 0, 0, 0);
  if (FFrames = nil) or (AnimId < 0) or (AnimId >= FFrames.Count) then
    Exit;
  FrameBounds := FFrames[AnimId].Src;
  Result := True;
end;

function TSpritePool.AllocSprite(AnimId: Integer): Integer;
var
  Slot: Integer;
begin
  for Slot := 0 to SPRITE_POOL_SIZE - 1 do
    if not FSlots[Slot].Used then
    begin
      FSlots[Slot].Used := True;
      FSlots[Slot].Visible := True;
      FSlots[Slot].AnimId := AnimId;
      FSlots[Slot].X := 0;
      FSlots[Slot].Y := 0;
      FSlots[Slot].Depth := 0;
      Exit(Slot);
    end;
  { Full. Entity_Spawn treats this as a failed spawn and drops the entity. }
  Result := SPRITE_NONE;
end;

procedure TSpritePool.ReleaseSprite(Handle: Integer);
begin
  if (Handle < 0) or (Handle >= SPRITE_POOL_SIZE) then
    Exit;
  FSlots[Handle].Used := False;
  FSlots[Handle].Visible := False;
  FSlots[Handle].Depth := 0;
end;

procedure TSpritePool.SetVisible(Handle: Integer; Visible: Boolean);
begin
  if (Handle >= 0) and (Handle < SPRITE_POOL_SIZE) then
    FSlots[Handle].Visible := Visible;
end;

function TSpritePool.GetVisible(Handle: Integer): Boolean;
begin
  Result := (Handle >= 0) and (Handle < SPRITE_POOL_SIZE)
            and FSlots[Handle].Visible;
end;

procedure TSpritePool.SetAnim(Handle, AnimId: Integer);
begin
  if (Handle >= 0) and (Handle < SPRITE_POOL_SIZE) then
    FSlots[Handle].AnimId := AnimId;
end;

function TSpritePool.Width(Handle: Integer): Integer;
var
  FrameBounds: TRect;
begin
  Result := 0;
  if (Handle < 0) or (Handle >= SPRITE_POOL_SIZE) then
    Exit;
  if FrameRect(FSlots[Handle].AnimId, FrameBounds) then
    Result := FrameBounds.Right - FrameBounds.Left;
end;

function TSpritePool.Height(Handle: Integer): Integer;
var
  FrameBounds: TRect;
begin
  Result := 0;
  if (Handle < 0) or (Handle >= SPRITE_POOL_SIZE) then
    Exit;
  if FrameRect(FSlots[Handle].AnimId, FrameBounds) then
    Result := FrameBounds.Bottom - FrameBounds.Top;
end;

procedure TSpritePool.SetPos(Handle, X, Y: Integer);
begin
  if (Handle >= 0) and (Handle < SPRITE_POOL_SIZE) then
  begin
    FSlots[Handle].X := X;
    FSlots[Handle].Y := Y;
  end;
end;

procedure TSpritePool.SetDepth(Handle, Depth: Integer);
begin
  if (Handle >= 0) and (Handle < SPRITE_POOL_SIZE) then
    FSlots[Handle].Depth := Depth;
end;

function TSpritePool.LiveCount: Integer;
var
  Slot: Integer;
begin
  Result := 0;
  for Slot := 0 to SPRITE_POOL_SIZE - 1 do
    if FSlots[Slot].Used then
      Inc(Result);
end;

{ Draw lower depths first, placing higher depths in front. Depth zero is
  reserved for destroyed or inert entities and is not drawn. Within a depth,
  lower slot numbers draw later and therefore appear in front. }
procedure TSpritePool.ShiftY(Delta: Integer);
var
  Slot: Integer;
begin
  for Slot := 0 to SPRITE_POOL_SIZE - 1 do
    if FSlots[Slot].Used then
      Inc(FSlots[Slot].Y, Delta);
end;

function TSpritePool.DrawOrder: TSpriteOrder;
var
  Depth, I, N: Integer;
begin
  SetLength(Result, SPRITE_POOL_SIZE);
  N := 0;
  for Depth := SPRITE_DEPTH_FIRST to SPRITE_DEPTH_MAIN_LAST do
    for I := SPRITE_POOL_SIZE - 1 downto 0 do
      if FSlots[I].Used and FSlots[I].Visible
         and (FSlots[I].Depth = Depth) then
      begin
        Result[N] := I;
        Inc(N);
      end;
  SetLength(Result, N);
end;

procedure TSpritePool.DrawAll(Dest: TCanvas; ASurfaces: TSurfaceSet);
var
  Order: TSpriteOrder;
  I: Integer;
begin
  if (FFrames = nil) or (ASurfaces = nil) then
    Exit;
  Order := DrawOrder;
  for I := 0 to High(Order) do
    FFrames.Draw(Dest, ASurfaces, FSlots[Order[I]].AnimId,
                 FSlots[Order[I]].X, FSlots[Order[I]].Y);
end;

{ Draw the dedicated above-interface sprite layer after the HUD and dialogue. }
procedure TSpritePool.DrawTop(Dest: TCanvas; ASurfaces: TSurfaceSet);
var
  I: Integer;
begin
  if (FFrames = nil) or (ASurfaces = nil) then
    Exit;
  for I := SPRITE_POOL_SIZE - 1 downto 0 do
    if FSlots[I].Used and FSlots[I].Visible
       and (FSlots[I].Depth = SPRITE_DEPTH_TOP) then
      FFrames.Draw(Dest, ASurfaces, FSlots[I].AnimId,
                   FSlots[I].X, FSlots[I].Y);
end;

end.
