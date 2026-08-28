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

type
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
    procedure DrawAll(Dest: TCanvas; ASurfaces: TSurfaceSet);

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

procedure TSpritePool.DrawAll(Dest: TCanvas; ASurfaces: TSurfaceSet);
var
  Depth, I: Integer;
  MaxDepth: Integer;
begin
  if (FFrames = nil) or (ASurfaces = nil) then
    Exit;

  MaxDepth := 0;
  for I := 0 to SPRITE_POOL_SIZE - 1 do
    if FSlots[I].Used and (FSlots[I].Depth > MaxDepth) then
      MaxDepth := FSlots[I].Depth;

  { Deepest first, so the shallowest ends up on top. Entity_UpdateAll's
    DEPTH_BY_SCREEN_Y types get their depth from screen Y, which is what makes
    something lower on the screen draw in front. }
  for Depth := MaxDepth downto 0 do
    for I := 0 to SPRITE_POOL_SIZE - 1 do
      if FSlots[I].Used and FSlots[I].Visible
         and (FSlots[I].Depth = Depth) then
        FFrames.Draw(Dest, ASurfaces, FSlots[I].AnimId,
                     FSlots[I].X, FSlots[I].Y);
end;

end.
