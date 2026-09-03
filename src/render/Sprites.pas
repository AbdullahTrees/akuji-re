{ Sprite frame-table loader (Load_Sprite_Sheets @ 0x004660B8).

  Reads data\spr%.03d.dat. Each line is CommaText with seven integer fields:

      [0] surfaceIndex   into the surface table
      [1] frameWidth
      [2] frameHeight
      [3] cols
      [4] rows
      [5] originX        top-left of the grid within the surface
      [6] originY

  and expands to cols*rows frames:

      srcX = (i mod cols) * frameWidth  + originX
      srcY = (i div cols) * frameHeight + originY

  Frames are numbered sequentially across the whole file, so frame ids are
  meaningful only within the currently loaded set. }

unit Sprites;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, Types, Surfaces;

type
  TSpriteFrame = record
    Surface: Integer;   { index into the TSurfaceSet }
    Src: TRect;
  end;

  TSpriteSet = class
  private
    FFrames: array of TSpriteFrame;
    function GetFrame(Index: Integer): TSpriteFrame;
    function GetCount: Integer;
  public
    { Returns the number of frames registered. }
    function LoadSet(const ADataDir: string; SetIndex: Integer): Integer;

    { Blits frame Index at (X, Y) using the surface bitmap's transparency. }
    procedure Draw(Dest: TCanvas; ASurfaces: TSurfaceSet;
                   Index, X, Y: Integer);

    property Count: Integer read GetCount;
    property Frames[Index: Integer]: TSpriteFrame read GetFrame; default;
  end;

implementation

function TSpriteSet.GetCount: Integer;
begin
  Result := Length(FFrames);
end;

function TSpriteSet.GetFrame(Index: Integer): TSpriteFrame;
begin
  if (Index < 0) or (Index >= Length(FFrames)) then
  begin
    Result.Surface := -1;
    Result.Src := Rect(0, 0, 0, 0);
    Exit;
  end;
  Result := FFrames[Index];
end;

{ Load_Sprite_Sheets @ 0x004660B8. }
function TSpriteSet.LoadSet(const ADataDir: string; SetIndex: Integer): Integer;
var
  Lines, Fields: TStringList;
  FileName: string;
  LineIndex, FrameIndex, NextFrame: Integer;
  SurfaceIndex, FrameWidth, FrameHeight, ColumnCount, RowCount: Integer;
  OriginX, OriginY, SourceX, SourceY: Integer;
begin
  SetLength(FFrames, 0);
  FileName := IncludeTrailingPathDelimiter(ADataDir) + 'data' + PathDelim +
              Format('spr%.3d.dat', [SetIndex]);
  if not FileExists(FileName) then
    Exit(0);

  Lines := TStringList.Create;
  Fields := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    NextFrame := 0;
    for LineIndex := 0 to Lines.Count - 1 do
    begin
      if Trim(Lines[LineIndex]) = '' then
        Continue;
      Fields.CommaText := Lines[LineIndex];
      if Fields.Count < 7 then
        Continue;

      SurfaceIndex := StrToIntDef(Trim(Fields[0]), 0);
      FrameWidth   := StrToIntDef(Trim(Fields[1]), 0);
      FrameHeight  := StrToIntDef(Trim(Fields[2]), 0);
      ColumnCount  := StrToIntDef(Trim(Fields[3]), 0);
      RowCount     := StrToIntDef(Trim(Fields[4]), 0);
      OriginX      := StrToIntDef(Trim(Fields[5]), 0);
      OriginY      := StrToIntDef(Trim(Fields[6]), 0);
      if (ColumnCount <= 0) or (RowCount <= 0) then
        Continue;

      SetLength(FFrames, NextFrame + ColumnCount * RowCount);
      for FrameIndex := 0 to ColumnCount * RowCount - 1 do
      begin
        SourceX := (FrameIndex mod ColumnCount) * FrameWidth + OriginX;
        SourceY := (FrameIndex div ColumnCount) * FrameHeight + OriginY;
        FFrames[NextFrame].Surface := SurfaceIndex;
        FFrames[NextFrame].Src := Rect(SourceX, SourceY,
                                       SourceX + FrameWidth,
                                       SourceY + FrameHeight);
        Inc(NextFrame);
      end;
    end;
  finally
    Fields.Free;
    Lines.Free;
  end;
  Result := Length(FFrames);
end;

procedure TSpriteSet.Draw(Dest: TCanvas; ASurfaces: TSurfaceSet;
  Index, X, Y: Integer);
var
  Frame: TSpriteFrame;
  Surface: TBitmap;
begin
  Frame := GetFrame(Index);
  if Frame.Surface < 0 then Exit;
  if ASurfaces = nil then Exit;
  Surface := ASurfaces[Frame.Surface];
  if Surface = nil then Exit;

  Dest.CopyRect(
    Rect(X, Y, X + (Frame.Src.Right - Frame.Src.Left),
         Y + (Frame.Src.Bottom - Frame.Src.Top)),
    Surface.Canvas, Frame.Src);
end;

end.
