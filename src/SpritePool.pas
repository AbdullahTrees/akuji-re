{ SpritePool - the pool of live sprite objects, as Entity_UpdateAll sees it.

  The original keeps sprites in a Delphi TList at 0x0046D35C; EF_SPRITE is the
  index into it and FUN_0044CFB8 is nothing but TList.Get. Entity_Spawn
  allocates one for every entity whose type table column 0 is not -1, and
  FAILS THE WHOLE SPAWN when the 256-object pool is full.

  ## Why this had to exist before anything could move

  Entities.pas recorded the missing allocation as "a divergence that matters
  only once sprites are drawn from it". That was wrong, and integration is
  what showed it. An entity's EXTENTS are not stored anywhere - Entity_UpdateAll
  reads them off the sprite every frame:

      E[EF_EXTENT_X] := Sprites.Width(handle)
      E[EF_EXTENT_Y] := Sprites.Height(handle)

  and every collision query is built from HalfExtent of those. With no sprite
  pool the player's extents stayed 0, which made Entity_TileCollideY compute
  LastCol one BELOW Col, so its loop body never ran once and it answered
  TILE_NONE for every tile in the game. The player fell through the world
  forever, and no unit test could see it because they all set extents by hand.

  So the sprite pool is not presentation. It is where the collision sizes come
  from, and a session without one has no collision at all.

  ## Release

  Entity_Destroy hides the sprite and sets its depth to 0, and that is all the
  original does - there is no free call, so allocation must be reusing slots
  in exactly that state. Rather than infer a scan rule from two writes, this
  makes the release explicit: TEntityWorld.DestroyEntity calls ReleaseSprite
  after the two writes the original makes. The observable behaviour is the
  same and the intent is not left implied. }

unit SpritePool;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Types, Entities, Sprites, Surfaces;

const
  { The original's pool is 256 objects, and Entity_Spawn failing when it is
    full is real behaviour rather than a guard. }
  SPRITE_POOL_SIZE = 256;

  { The depth buckets 0x00464D30 draws, and the two it treats specially. }
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
    function FrameRect(AnimId: Integer; out R: TRect): Boolean;
  public
    constructor Create;
    procedure Clear;

    { The frame table the current stage's sprite set loaded. Swapping it does
      not disturb live handles - an anim id means whatever the CURRENT set
      says, which is the original's behaviour and why ids are only meaningful
      per set. }
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
  I: Integer;
begin
  for I := 0 to SPRITE_POOL_SIZE - 1 do
  begin
    FSlots[I].Used := False;
    FSlots[I].Visible := False;
    FSlots[I].AnimId := -1;
    FSlots[I].X := 0;
    FSlots[I].Y := 0;
    FSlots[I].Depth := 0;
  end;
end;

function TSpritePool.FrameRect(AnimId: Integer; out R: TRect): Boolean;
begin
  Result := False;
  R := Rect(0, 0, 0, 0);
  if (FFrames = nil) or (AnimId < 0) or (AnimId >= FFrames.Count) then
    Exit;
  R := FFrames[AnimId].Src;
  Result := True;
end;

function TSpritePool.AllocSprite(AnimId: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to SPRITE_POOL_SIZE - 1 do
    if not FSlots[I].Used then
    begin
      FSlots[I].Used := True;
      FSlots[I].Visible := True;
      FSlots[I].AnimId := AnimId;
      FSlots[I].X := 0;
      FSlots[I].Y := 0;
      FSlots[I].Depth := 0;
      Exit(I);
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
  R: TRect;
begin
  Result := 0;
  if (Handle < 0) or (Handle >= SPRITE_POOL_SIZE) then
    Exit;
  if FrameRect(FSlots[Handle].AnimId, R) then
    Result := R.Right - R.Left;
end;

function TSpritePool.Height(Handle: Integer): Integer;
var
  R: TRect;
begin
  Result := 0;
  if (Handle < 0) or (Handle >= SPRITE_POOL_SIZE) then
    Exit;
  if FrameRect(FSlots[Handle].AnimId, R) then
    Result := R.Bottom - R.Top;
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
  I: Integer;
begin
  Result := 0;
  for I := 0 to SPRITE_POOL_SIZE - 1 do
    if FSlots[I].Used then
      Inc(Result);
end;

{ THE DRAW ORDER, and it was inverted.

  0x0044D1E0 buckets every visible sprite by its depth, and 0x00464D30 then
  draws the buckets in ASCENDING order:

      for (i = 1; i != 8; i++) FUN_0044D31C(sprites, i);
      ...
      if (*p_GameState != 10) FUN_0044D31C(sprites, 8);

  so a LOW depth is drawn first and ends up BEHIND, and a high depth is drawn
  last and ends up in front. This drew `MaxDepth downto 0`, which is exactly
  backwards, and the type table says what that costs: the player is depth 4
  while signs, save statues and mana stones are 1, doors and orbs 2, and
  monsters 3. Every one of them was landing on top of Akuji.

  BUCKET 0 IS NEVER DRAWN. The original's loop starts at 1, and that is not an
  oversight - Entity_Destroy zeroes EF_DEPTH, so depth 0 is the destroyed and
  the inert. Types 18 and 20 carry it and have no sprite at all.

  WITHIN a bucket the original walks the pool from the LAST slot to the first,
  so a lower slot number draws later and therefore in front of a higher one at
  the same depth. }
procedure TSpritePool.ShiftY(Delta: Integer);
var
  I: Integer;
begin
  for I := 0 to SPRITE_POOL_SIZE - 1 do
    if FSlots[I].Used then
      Inc(FSlots[I].Y, Delta);
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

{ Bucket 8, which 0x00464D30 draws AFTER the HUD and the message box rather
  than with the others - the only sprite layer that sits over the interface.
  No shipped record places the one type that carries depth 8 (type 13), so
  nothing reaches this today; it exists so that the layer is where the original
  puts it rather than folded into the pass above. }
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
