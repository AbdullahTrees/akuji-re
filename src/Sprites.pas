{ Sprites - the sprite frame table, translated from Load_Sprite_Sheets
  @ 0x004660B8.

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

  Frames are numbered sequentially across the whole file - the original keeps
  one running counter (local_c) over every line, so a frame's id depends on how
  many frames the preceding lines produced. Ids are therefore only meaningful
  per set.

  Validated against the real data: all 79 lines across spr000..spr009 have
  exactly seven fields, expanding to 4702 frames overall, around 500 per set. }

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

    { Blits frame Index at (X, Y). Transparency follows the surface bitmap's
      own setting; the original passes flag 0x11 to TDDDD_DrawSprite, which has
      not been decoded yet - see the note in CLAUDE.md. }
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
  L, I, Next: Integer;
  SurfIdx, FrameW, FrameH, Cols, Rows, OriginX, OriginY: Integer;
  SrcX, SrcY: Integer;
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
    Next := 0;
    for L := 0 to Lines.Count - 1 do
    begin
      if Trim(Lines[L]) = '' then
        Continue;
      Fields.CommaText := Lines[L];
      if Fields.Count < 7 then
        Continue;

      SurfIdx := StrToIntDef(Trim(Fields[0]), 0);
      FrameW  := StrToIntDef(Trim(Fields[1]), 0);
      FrameH  := StrToIntDef(Trim(Fields[2]), 0);
      Cols    := StrToIntDef(Trim(Fields[3]), 0);
      Rows    := StrToIntDef(Trim(Fields[4]), 0);
      OriginX := StrToIntDef(Trim(Fields[5]), 0);
      OriginY := StrToIntDef(Trim(Fields[6]), 0);
      if (Cols <= 0) or (Rows <= 0) then
        Continue;

      SetLength(FFrames, Next + Cols * Rows);
      for I := 0 to Cols * Rows - 1 do
      begin
        SrcX := (I mod Cols) * FrameW + OriginX;
        SrcY := (I div Cols) * FrameH + OriginY;
        FFrames[Next].Surface := SurfIdx;
        FFrames[Next].Src := Rect(SrcX, SrcY, SrcX + FrameW, SrcY + FrameH);
        Inc(Next);
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
  F: TSpriteFrame;
  Bmp: TBitmap;
begin
  F := GetFrame(Index);
  if F.Surface < 0 then Exit;
  if ASurfaces = nil then Exit;
  Bmp := ASurfaces[F.Surface];
  if Bmp = nil then Exit;

  Dest.CopyRect(
    Rect(X, Y, X + (F.Src.Right - F.Src.Left), Y + (F.Src.Bottom - F.Src.Top)),
    Bmp.Canvas, F.Src);
end;

end.
