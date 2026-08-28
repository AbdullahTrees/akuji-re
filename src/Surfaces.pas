{ Surfaces - the game's surface table, translated from Load_Surface_Textures
  @ 0x00465E9C.

  The original:
    - frees the 32 slots in p_Surfaces (0x0046D344)
    - builds "data\surf" + Format('%.03d', SetIndex) + ".dat"
    - loads it into a TStringList
    - for each line: CommaText it into a second list, then
        field[0] = bitmap name
        field[1] = width       (StrToInt)
        field[2] = height      (StrToInt)
      creates a surface of that size and loads the bitmap into it
    - source depends on p_UseArchive (0x0046CCB4), which DDDD1Init sets to 1:
        1 -> from bmp.qda, by name
        0 -> from a loose file, "bmp\" + name

  Known slot meanings so far, from callers:
    0  the 9x9 font sheet   (Title_Init registers it as font 0)
    1  title menu background
    2  options background

  Note the width/height columns are the size the game wants the surface to be,
  which is not always the bitmap's own size. They are carried here so that
  discrepancy stays visible rather than being silently dropped. }

unit Surfaces;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics, QdaArchive;

const
  MAX_SURFACES = 32;   { the original frees exactly 0x20 slots }

type
  TSurfaceSlot = record
    Name: string;
    Width: Integer;
    Height: Integer;
    Bitmap: TBitmap;
  end;

  TSurfaceSet = class
  private
    FSlots: array[0..MAX_SURFACES - 1] of TSurfaceSlot;
    FCount: Integer;
    FArchive: TQdaArchive;
    function GetBitmap(Index: Integer): TBitmap;
    function GetSlot(Index: Integer): TSurfaceSlot;
    procedure Clear;
  public
    constructor Create(AArchive: TQdaArchive);
    destructor Destroy; override;

    { Loads data\surf%.03d.dat relative to ADataDir. Returns how many slots
      were filled. Missing bitmaps leave the slot's Bitmap nil rather than
      raising - the original tolerates gaps too. }
    function LoadSet(const ADataDir: string; SetIndex: Integer): Integer;

    property Count: Integer read FCount;
    property Bitmaps[Index: Integer]: TBitmap read GetBitmap; default;
    property Slots[Index: Integer]: TSurfaceSlot read GetSlot;
  end;

implementation

constructor TSurfaceSet.Create(AArchive: TQdaArchive);
begin
  inherited Create;
  FArchive := AArchive;
end;

destructor TSurfaceSet.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TSurfaceSet.Clear;
var
  I: Integer;
begin
  for I := 0 to MAX_SURFACES - 1 do
  begin
    FreeAndNil(FSlots[I].Bitmap);
    FSlots[I].Name := '';
    FSlots[I].Width := 0;
    FSlots[I].Height := 0;
  end;
  FCount := 0;
end;

function TSurfaceSet.GetBitmap(Index: Integer): TBitmap;
begin
  if (Index < 0) or (Index >= MAX_SURFACES) then
    Exit(nil);
  Result := FSlots[Index].Bitmap;
end;

function TSurfaceSet.GetSlot(Index: Integer): TSurfaceSlot;
begin
  if (Index < 0) or (Index >= MAX_SURFACES) then
  begin
    Result.Name := '';
    Result.Width := 0;
    Result.Height := 0;
    Result.Bitmap := nil;
    Exit;
  end;
  Result := FSlots[Index];
end;

{ Load_Surface_Textures @ 0x00465E9C. }
function TSurfaceSet.LoadSet(const ADataDir: string; SetIndex: Integer): Integer;
var
  Lines, Fields: TStringList;
  FileName: string;
  I: Integer;
begin
  Clear;
  FileName := IncludeTrailingPathDelimiter(ADataDir) + 'data' + PathDelim +
              Format('surf%.3d.dat', [SetIndex]);
  if not FileExists(FileName) then
    Exit(0);

  Lines := TStringList.Create;
  Fields := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    for I := 0 to Lines.Count - 1 do
    begin
      if I >= MAX_SURFACES then
        Break;
      if Trim(Lines[I]) = '' then
        Continue;

      { The original sets .CommaText, which splits on commas AND whitespace -
        the files are comma+tab separated, so both matter. }
      Fields.CommaText := Lines[I];
      if Fields.Count < 3 then
        Continue;

      FSlots[I].Name := Trim(Fields[0]);
      FSlots[I].Width := StrToIntDef(Trim(Fields[1]), 0);
      FSlots[I].Height := StrToIntDef(Trim(Fields[2]), 0);

      if (FArchive <> nil) and (FArchive.IndexOf(FSlots[I].Name) >= 0) then
        FSlots[I].Bitmap := FArchive.LoadBitmapByName(FSlots[I].Name);

      Inc(FCount);
    end;
  finally
    Fields.Free;
    Lines.Free;
  end;
  Result := FCount;
end;

end.
