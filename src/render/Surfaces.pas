{ Surface-table loader (Load_Surface_Textures @ 0x00465E9C). Each row in
  data\surfNNN.dat supplies a bitmap name and target dimensions. Bitmaps are
  loaded from bmp.qda when available or from the loose bmp directory. }

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
      raising. }
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
  Slot: Integer;
begin
  for Slot := 0 to MAX_SURFACES - 1 do
  begin
    FreeAndNil(FSlots[Slot].Bitmap);
    FSlots[Slot].Name := '';
    FSlots[Slot].Width := 0;
    FSlots[Slot].Height := 0;
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
  Slot: Integer;
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
    for Slot := 0 to Lines.Count - 1 do
    begin
      if Slot >= MAX_SURFACES then
        Break;
      if Trim(Lines[Slot]) = '' then
        Continue;

      { The original sets .CommaText, which splits on commas AND whitespace -
        the files are comma+tab separated, so both matter. }
      Fields.CommaText := Lines[Slot];
      if Fields.Count < 3 then
        Continue;

      FSlots[Slot].Name := Trim(Fields[0]);
      FSlots[Slot].Width := StrToIntDef(Trim(Fields[1]), 0);
      FSlots[Slot].Height := StrToIntDef(Trim(Fields[2]), 0);

      if (FArchive <> nil) and (FArchive.IndexOf(FSlots[Slot].Name) >= 0) then
        FSlots[Slot].Bitmap := FArchive.LoadBitmapByName(FSlots[Slot].Name);

      Inc(FCount);
    end;
  finally
    Fields.Free;
    Lines.Free;
  end;
  Result := FCount;
end;

end.
