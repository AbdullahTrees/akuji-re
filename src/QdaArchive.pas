{ QdaArchive - reader for the game's QDA0 archive (bmp.qda).

  Format recovered 2026-08-27 and validated: the directory size plus the sum of
  every entry size equals the file length exactly.

    0x00   4      zero
    0x04   4      magic "QDA0"
    0x08   4      entry count (44 in bmp.qda)
    0x0C   244    zero padding to 0x100
    0x100  n*268  directory
    ...           file data, in directory order

    entry, 268 bytes:
      +0x00  4    absolute offset of data
      +0x04  4    size
      +0x08  4    size again - the format has room for compression but
                  bmp.qda stores everything uncompressed
      +0x0C  256  NUL-terminated name

  Contents are plain uncompressed 24-bit BMPs, so TBitmap loads them directly.

  NOTE: names in the archive mix case (sys.BMP, title.BMP, omake01.bmp) while
  the .dat metadata refers to them in lowercase. Lookups here are
  case-insensitive for that reason - matching case-sensitively silently fails
  on about a third of the archive.

  Reference extractor: tools/extract_qda.py }

unit QdaArchive;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, Graphics;

const
  QDA_MAGIC      = 'QDA0';
  QDA_DIR_OFFSET = $100;
  QDA_ENTRY_SIZE = 268;
  QDA_NAME_SIZE  = 256;

type
  EQdaError = class(Exception);

  TQdaEntry = record
    Name: string;
    Offset: LongWord;
    Size: LongWord;
  end;

  TQdaArchive = class
  private
    FStream: TFileStream;
    FEntries: array of TQdaEntry;
    function GetCount: Integer;
    function GetEntry(Index: Integer): TQdaEntry;
    procedure ReadDirectory;
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;

    { -1 when absent. Case-insensitive - see the note above. }
    function IndexOf(const AName: string): Integer;

    { Caller owns the returned bitmap. }
    function LoadBitmap(Index: Integer): TBitmap;
    function LoadBitmapByName(const AName: string): TBitmap;

    { Raw bytes, for anything that is not a bitmap. }
    procedure LoadRaw(Index: Integer; Dest: TStream);

    property Count: Integer read GetCount;
    property Entries[Index: Integer]: TQdaEntry read GetEntry;
  end;

implementation

constructor TQdaArchive.Create(const FileName: string);
begin
  inherited Create;
  FStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  ReadDirectory;
end;

destructor TQdaArchive.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;

procedure TQdaArchive.ReadDirectory;
var
  Magic: array[0..3] of AnsiChar;
  Count_, I, Accounted: LongWord;
  NameBuf: array[0..QDA_NAME_SIZE - 1] of AnsiChar;
begin
  FStream.Position := 4;
  FStream.ReadBuffer(Magic, 4);
  if Magic <> QDA_MAGIC then
    raise EQdaError.CreateFmt('not a QDA0 archive (magic "%s")', [Magic]);

  Count_ := FStream.ReadDWord;
  SetLength(FEntries, Count_);

  Accounted := QDA_DIR_OFFSET + Count_ * QDA_ENTRY_SIZE;
  for I := 0 to Count_ - 1 do
  begin
    FStream.Position := QDA_DIR_OFFSET + I * QDA_ENTRY_SIZE;
    FEntries[I].Offset := FStream.ReadDWord;
    FEntries[I].Size   := FStream.ReadDWord;
    FStream.ReadDWord;   { size repeated; equal in every known archive }
    FStream.ReadBuffer(NameBuf, QDA_NAME_SIZE);
    FEntries[I].Name := string(PAnsiChar(@NameBuf[0]));
    Inc(Accounted, FEntries[I].Size);
  end;

  { The archive should account for itself exactly. If it does not, the entry
    layout has been misread and every offset below is suspect. }
  if Accounted <> LongWord(FStream.Size) then
    raise EQdaError.CreateFmt(
      'directory accounts for %d bytes but the file is %d - format mismatch',
      [Accounted, FStream.Size]);
end;

function TQdaArchive.GetCount: Integer;
begin
  Result := Length(FEntries);
end;

function TQdaArchive.GetEntry(Index: Integer): TQdaEntry;
begin
  if (Index < 0) or (Index >= Length(FEntries)) then
    raise EQdaError.CreateFmt('entry index %d out of range', [Index]);
  Result := FEntries[Index];
end;

function TQdaArchive.IndexOf(const AName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FEntries) do
    if SameText(FEntries[I].Name, AName) then
      Exit(I);
  Result := -1;
end;

procedure TQdaArchive.LoadRaw(Index: Integer; Dest: TStream);
var
  E: TQdaEntry;
begin
  E := GetEntry(Index);
  FStream.Position := E.Offset;
  Dest.CopyFrom(FStream, E.Size);
  Dest.Position := 0;
end;

function TQdaArchive.LoadBitmap(Index: Integer): TBitmap;
var
  Mem: TMemoryStream;
begin
  Mem := TMemoryStream.Create;
  try
    LoadRaw(Index, Mem);
    Result := TBitmap.Create;
    try
      Result.LoadFromStream(Mem);
    except
      Result.Free;
      raise;
    end;
  finally
    Mem.Free;
  end;
end;

function TQdaArchive.LoadBitmapByName(const AName: string): TBitmap;
var
  I: Integer;
begin
  I := IndexOf(AName);
  if I < 0 then
    raise EQdaError.CreateFmt('"%s" is not in the archive', [AName]);
  Result := LoadBitmap(I);
end;

end.
