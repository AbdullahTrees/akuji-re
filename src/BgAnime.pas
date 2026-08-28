{ BgAnime - TMYBGANIME, the animated background tiles.

  The class name is in the binary at 0x0044E1AA. Terrain_Configure builds one
  for terrains 1..4 and Stages.pas carries the tracks it declares; this is the
  object itself and the per-frame tick that makes them move.

      0x0044E1B8  TMYBGANIME.Create(TileMap, TrackCount, Surface)
      0x0044E224  MyBgAnime_BeginTrack(Self, Track, TileId, FrameCount)
      0x0044E25C  MyBgAnime_AddFrame(Self, Track, Ticks, SrcY, SrcX)
      0x0044E2C0  MyBgAnime_Tick(Self)          <- called once a frame

  ## What it animates is the TILESET, not the screen

  The tick's only effect is a TileMap_DefineTile call: it repoints a tile id at
  a different cell of the tileset. So every instance of that tile in the map
  animates together, and nothing has to know where they are. That is why a
  handful of tracks can animate a whole wall, and it is why TTileMap had to
  gain a per-tile source table before this could work at all - a Draw that
  recomputed the cell from the id would be correct until something animated,
  and then could not be.

  ## The track record

  One field does double duty, and reproducing that matters. Self+0x10 is the
  track array, 0x14 bytes each:

      +0x00  tile id            read as a WORD by the tick
      +0x04  play cursor        which frame is showing
      +0x08  frame count        AddFrame increments this as it fills, so it is
                                the WRITE cursor while building and the COUNT
                                afterwards - the same int
      +0x0C  timer              counts down
      +0x10  frames, 0x0C each: ticks, srcX, srcY

  ## The timer

  Nothing initialises the timer, so it starts at 0 from the array allocation.
  The first tick decrements it to -1, finds it below 1, and shows frame 0
  immediately - then loads the frame's own tick count. From 8 that is eight
  decrements before the next advance, so a frame holds for 8 game frames and
  the first one appears on the very first tick rather than 8 frames in.
  Reproduced as written; a timer initialised to Ticks would delay the start by
  one frame and look almost right. }

unit BgAnime;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Types, TileMaps, Stages;

type
  TBgTrack = record
    TileId:     Integer;
    Cursor:     Integer;    { +0x04, which frame is showing }
    FrameCount: Integer;    { +0x08 }
    Timer:      Integer;    { +0x0C }
    Frames:     array[0..TERRAIN_ANIM_FRAMES - 1] of Integer;  { frame tile ids }
  end;

  TBgAnime = class
  private
    FMap: TTileMap;
    FTracks: array[0..TERRAIN_ANIM_TRACKS - 1] of TBgTrack;
    FCount: Integer;
  public
    { The map whose tile table this rewrites. The original also holds the
      surface, because its TileMap_DefineTile takes one; ours already knows
      which sheet it draws from, so there is nothing to carry. }
    constructor Create(AMap: TTileMap; const Anim: TTerrainAnim);

    { 0x0044E2C0. One frame. }
    procedure Tick;

    { Puts every track back on frame 0 with a spent timer, which is the state
      Create leaves and the state a fresh stage wants. }
    procedure Restart;

    property TrackCount: Integer read FCount;
    function TrackTile(Index: Integer): Integer;
    function TrackCursor(Index: Integer): Integer;
  end;

implementation

constructor TBgAnime.Create(AMap: TTileMap; const Anim: TTerrainAnim);
var
  T, F: Integer;
begin
  inherited Create;
  FMap := AMap;
  FCount := Anim.TrackCount;
  if FCount > TERRAIN_ANIM_TRACKS then
    FCount := TERRAIN_ANIM_TRACKS;

  for T := 0 to FCount - 1 do
  begin
    FTracks[T].TileId := Anim.Tracks[T].TileId;
    FTracks[T].FrameCount := Anim.Tracks[T].FrameCount;
    FTracks[T].Cursor := 0;
    FTracks[T].Timer := 0;
    for F := 0 to TERRAIN_ANIM_FRAMES - 1 do
      FTracks[T].Frames[F] := Anim.Tracks[T].Frames[F];
  end;
end;

procedure TBgAnime.Restart;
var
  T: Integer;
begin
  for T := 0 to FCount - 1 do
  begin
    FTracks[T].Cursor := 0;
    FTracks[T].Timer := 0;
  end;
end;

function TBgAnime.TrackTile(Index: Integer): Integer;
begin
  if (Index < 0) or (Index >= FCount) then
    Exit(-1);
  Result := FTracks[Index].TileId;
end;

function TBgAnime.TrackCursor(Index: Integer): Integer;
begin
  if (Index < 0) or (Index >= FCount) then
    Exit(-1);
  Result := FTracks[Index].Cursor;
end;

procedure TBgAnime.Tick;
var
  T, F, SrcTile: Integer;
begin
  if FMap = nil then
    Exit;

  for T := 0 to FCount - 1 do
  begin
    Dec(FTracks[T].Timer);
    if FTracks[T].Timer >= 1 then
      Continue;

    F := FTracks[T].Cursor;
    if (F < 0) or (F >= TERRAIN_ANIM_FRAMES) then
      F := 0;

    { The frame's picture is another tile's cell. Stages.pas stores the frames
      as tile IDS because that is what the data means; the original stores the
      coordinates it computed from them, and --selftest-stages checks the two
      agree over all thirty frames. }
    SrcTile := FTracks[T].Frames[F];
    FMap.DefineTile(FTracks[T].TileId,
                    TileSrcY(SrcTile, FMap.TileHeight, FMap.SheetCols),
                    TileSrcX(SrcTile, FMap.TileWidth, FMap.SheetCols));

    FTracks[T].Timer := TERRAIN_ANIM_TICKS;

    Inc(FTracks[T].Cursor);
    if FTracks[T].Cursor >= FTracks[T].FrameCount then
      FTracks[T].Cursor := 0;
  end;
end;

end.
