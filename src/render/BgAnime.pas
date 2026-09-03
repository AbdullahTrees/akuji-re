{ Animated background tiles. Each track redefines one tile's source cell, so
  every occurrence of that tile animates together. A zero timer displays the
  first frame on the next Tick and then holds each frame for its configured
  duration. }

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
    { The map whose tile-definition table is rewritten. }
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
  TrackIndex, FrameIndex: Integer;
begin
  inherited Create;
  FMap := AMap;
  FCount := Anim.TrackCount;
  if FCount > TERRAIN_ANIM_TRACKS then
    FCount := TERRAIN_ANIM_TRACKS;

  for TrackIndex := 0 to FCount - 1 do
  begin
    FTracks[TrackIndex].TileId := Anim.Tracks[TrackIndex].TileId;
    FTracks[TrackIndex].FrameCount := Anim.Tracks[TrackIndex].FrameCount;
    FTracks[TrackIndex].Cursor := 0;
    FTracks[TrackIndex].Timer := 0;
    for FrameIndex := 0 to TERRAIN_ANIM_FRAMES - 1 do
      FTracks[TrackIndex].Frames[FrameIndex] :=
        Anim.Tracks[TrackIndex].Frames[FrameIndex];
  end;
end;

procedure TBgAnime.Restart;
var
  TrackIndex: Integer;
begin
  for TrackIndex := 0 to FCount - 1 do
  begin
    FTracks[TrackIndex].Cursor := 0;
    FTracks[TrackIndex].Timer := 0;
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
  TrackIndex, FrameIndex, SourceTile: Integer;
begin
  if FMap = nil then
    Exit;

  for TrackIndex := 0 to FCount - 1 do
  begin
    Dec(FTracks[TrackIndex].Timer);
    if FTracks[TrackIndex].Timer >= 1 then
      Continue;

    FrameIndex := FTracks[TrackIndex].Cursor;
    if (FrameIndex < 0) or (FrameIndex >= TERRAIN_ANIM_FRAMES) then
      FrameIndex := 0;

    { The frame's picture is another tile's cell. Stages.pas stores the frames
      as tile IDS because that is what the data means; the original stores the
      coordinates it computed from them, and --selftest-stages checks the two
      agree over all thirty frames. }
    SourceTile := FTracks[TrackIndex].Frames[FrameIndex];
    FMap.DefineTile(FTracks[TrackIndex].TileId,
                    TileSrcY(SourceTile, FMap.TileHeight, FMap.SheetCols),
                    TileSrcX(SourceTile, FMap.TileWidth, FMap.SheetCols));

    FTracks[TrackIndex].Timer := TERRAIN_ANIM_TICKS;

    Inc(FTracks[TrackIndex].Cursor);
    if FTracks[TrackIndex].Cursor >= FTracks[TrackIndex].FrameCount then
      FTracks[TrackIndex].Cursor := 0;
  end;
end;

end.
