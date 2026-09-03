{ Reader for the QDA0 bitmap archive:

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

  Entries are uncompressed BMPs. Names use inconsistent case, so lookups are
  case-insensitive. }

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

    { Returns -1 when absent. }
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
  EntryCount, EntryIndex, AccountedSize: LongWord;
  NameBuffer: array[0..QDA_NAME_SIZE - 1] of AnsiChar;
begin
  FStream.Position := 4;
  FStream.ReadBuffer(Magic, 4);
  if Magic <> QDA_MAGIC then
    raise EQdaError.CreateFmt('not a QDA0 archive (magic "%s")', [Magic]);

  EntryCount := FStream.ReadDWord;
  SetLength(FEntries, EntryCount);

  AccountedSize := QDA_DIR_OFFSET + EntryCount * QDA_ENTRY_SIZE;
  for EntryIndex := 0 to EntryCount - 1 do
  begin
    FStream.Position := QDA_DIR_OFFSET + EntryIndex * QDA_ENTRY_SIZE;
    FEntries[EntryIndex].Offset := FStream.ReadDWord;
    FEntries[EntryIndex].Size   := FStream.ReadDWord;
    FStream.ReadDWord;   { size repeated; equal in every known archive }
    FStream.ReadBuffer(NameBuffer, QDA_NAME_SIZE);
    FEntries[EntryIndex].Name := string(PAnsiChar(@NameBuffer[0]));
    Inc(AccountedSize, FEntries[EntryIndex].Size);
  end;

  { The archive should account for itself exactly. If it does not, the entry
    layout has been misread and every offset below is suspect. }
  if AccountedSize <> LongWord(FStream.Size) then
    raise EQdaError.CreateFmt(
      'directory accounts for %d bytes but the file is %d - format mismatch',
      [AccountedSize, FStream.Size]);
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
  EntryIndex: Integer;
begin
  for EntryIndex := 0 to High(FEntries) do
    if SameText(FEntries[EntryIndex].Name, AName) then
      Exit(EntryIndex);
  Result := -1;
end;

procedure TQdaArchive.LoadRaw(Index: Integer; Dest: TStream);
var
  Entry: TQdaEntry;
begin
  Entry := GetEntry(Index);
  FStream.Position := Entry.Offset;
  Dest.CopyFrom(FStream, Entry.Size);
  Dest.Position := 0;
end;

function TQdaArchive.LoadBitmap(Index: Integer): TBitmap;
var
  Buffer: TMemoryStream;
begin
  Buffer := TMemoryStream.Create;
  try
    LoadRaw(Index, Buffer);
    Result := TBitmap.Create;
    try
      Result.LoadFromStream(Buffer);
    except
      Result.Free;
      raise;
    end;
  finally
    Buffer.Free;
  end;
end;

function TQdaArchive.LoadBitmapByName(const AName: string): TBitmap;
var
  EntryIndex: Integer;
begin
  EntryIndex := IndexOf(AName);
  if EntryIndex < 0 then
    raise EQdaError.CreateFmt('"%s" is not in the archive', [AName]);
  Result := LoadBitmap(EntryIndex);
end;

end.
