{ MidiFile - Standard MIDI File reader.

  The original did not parse MIDI itself; it handed a filename to Kbgm32.dll
  (KBGMLoadFile) and that third-party engine did the sequencing. Kbgm32 is a
  32-bit Windows DLL with no source, so it leaves with the rest of the platform
  layer and the sequencing has to be done here.

  What the game ships (all 15 files surveyed, no exceptions):

      format 1 throughout, 48 ticks per quarter note throughout
      1 to 16 tracks; every MTrk chunk intact, no trailing bytes
      main01.mid and end05.mid are byte-identical - the ending reuses the main
      theme, which is worth knowing before hunting for a bug in the playlist

  midi/init.mid is not music. It is one track of metadata and three SysEx
  messages: a GM Reset (F0 7E 7F 09 01 F7) and two Roland GS parameter writes.
  That is the whole of the "SysEx risk" recorded against this project - there is
  no per-note SysEx anywhere. GM Reset is universal and the two GS messages are
  ignored harmlessly by anything that is not a Roland module, so playing init
  first is safe on a modern synth.

  This unit only reads and flattens; it makes no sound. Tracks are parsed
  separately and then k-way merged into one list ordered by absolute tick, and
  absolute microseconds are computed up front from the tempo map so the player
  never accumulates rounding error across a five-minute loop. }

unit MidiFile;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

type
  TMidiEventKind = (mekShort, mekSysEx, mekTempo, mekEndOfTrack);

  TMidiEvent = record
    Tick: LongWord;        { absolute, in file ticks }
    TimeUs: Int64;         { absolute, in microseconds from the start }
    Kind: TMidiEventKind;
    { mekShort: status in bits 0..7, data1 in 8..15, data2 in 16..23 - packed
      the way midiOutShortMsg wants it.
      mekTempo: microseconds per quarter note. }
    Msg: LongWord;
    Blob: TBytes;          { mekSysEx only, including the leading F0 }
  end;

  TMidiEventArray = array of TMidiEvent;

  TMidiFile = class
  private
    FEvents: TMidiEventArray;
    FDivision: Word;
    FFormat: Word;
    FTrackCount: Word;
    FDurationUs: Int64;
    function GetEvent(Index: Integer): TMidiEvent;
    function GetCount: Integer;
    procedure ComputeTimes;
  public
    destructor Destroy; override;

    function LoadFromFile(const FileName: string): Boolean;
    procedure Clear;

    property Count: Integer read GetCount;
    property Events[Index: Integer]: TMidiEvent read GetEvent; default;
    property Division: Word read FDivision;
    property Format: Word read FFormat;
    property TrackCount: Word read FTrackCount;
    property DurationUs: Int64 read FDurationUs;
  end;

implementation

const
  DEFAULT_TEMPO_US = 500000;   { 120 bpm, the SMF default when no tempo is set }

type
  TReader = record
    Data: TBytes;
    Pos: Integer;
    Limit: Integer;
  end;

function ReadByte(var R: TReader): Byte;
begin
  if R.Pos >= R.Limit then
    Exit(0);
  Result := R.Data[R.Pos];
  Inc(R.Pos);
end;

function ReadBE32(var R: TReader): LongWord;
begin
  Result := (LongWord(ReadByte(R)) shl 24) or (LongWord(ReadByte(R)) shl 16) or
            (LongWord(ReadByte(R)) shl 8) or LongWord(ReadByte(R));
end;

function ReadBE16(var R: TReader): Word;
begin
  Result := (Word(ReadByte(R)) shl 8) or Word(ReadByte(R));
end;

{ Variable-length quantity: seven bits per byte, high bit set on every byte but
  the last. Four bytes is the format's own limit. }
function ReadVLQ(var R: TReader): LongWord;
var
  B: Byte;
  N: Integer;
begin
  Result := 0;
  N := 0;
  repeat
    B := ReadByte(R);
    Result := (Result shl 7) or (B and $7F);
    Inc(N);
  until ((B and $80) = 0) or (N >= 4) or (R.Pos >= R.Limit);
end;

{ Clears a TMidiEvent field by field. FillChar must not be used on a record
  holding a dynamic array: it would overwrite the reference without releasing
  it, leaking the SysEx blob of the previous event. }
procedure ClearEvent(var E: TMidiEvent);
begin
  E.Tick := 0;
  E.TimeUs := 0;
  E.Kind := mekShort;
  E.Msg := 0;
  E.Blob := nil;
end;

destructor TMidiFile.Destroy;
begin
  Clear;
  inherited Destroy;
end;

function TMidiFile.GetCount: Integer;
begin
  Result := Length(FEvents);
end;

function TMidiFile.GetEvent(Index: Integer): TMidiEvent;
begin
  if (Index < 0) or (Index >= Length(FEvents)) then
  begin
    { Assigned field by field rather than via ClearEvent: the compiler cannot
      see that a managed function result is already initialised, and warns. }
    Result.Tick := 0;
    Result.TimeUs := 0;
    Result.Msg := 0;
    Result.Blob := nil;
    Result.Kind := mekEndOfTrack;
    Exit;
  end;
  Result := FEvents[Index];
end;

procedure TMidiFile.Clear;
begin
  SetLength(FEvents, 0);
  FDivision := 0;
  FFormat := 0;
  FTrackCount := 0;
  FDurationUs := 0;
end;

{ Walks the merged list once, converting ticks to microseconds as the tempo map
  dictates. Doing this up front rather than during playback is what keeps a long
  loop from drifting. }
procedure TMidiFile.ComputeTimes;
var
  I: Integer;
  Tempo: LongWord;
  LastTick: LongWord;
  Acc: Int64;
begin
  Tempo := DEFAULT_TEMPO_US;
  LastTick := 0;
  Acc := 0;
  for I := 0 to High(FEvents) do
  begin
    if FDivision > 0 then
      Acc := Acc + (Int64(FEvents[I].Tick - LastTick) * Tempo) div FDivision;
    LastTick := FEvents[I].Tick;
    FEvents[I].TimeUs := Acc;
    if FEvents[I].Kind = mekTempo then
      Tempo := FEvents[I].Msg;
  end;
  FDurationUs := Acc;
end;

{ Parses one MTrk body into a tick-ordered event list. R.Pos must be at the
  first delta time and TrackEnd just past the last byte of the chunk. }
function ParseTrack(var R: TReader; TrackEnd: Integer): TMidiEventArray;
var
  Tick: LongWord;
  Status, RunningStatus, D1, D2, MetaType: Byte;
  Len: LongWord;
  Ev: TMidiEvent;
  N, I: Integer;
begin
  Result := nil;
  N := 0;
  Tick := 0;
  RunningStatus := 0;

  while R.Pos < TrackEnd do
  begin
    Inc(Tick, ReadVLQ(R));
    if R.Pos >= TrackEnd then
      Break;

    Status := R.Data[R.Pos];
    if Status >= $80 then
    begin
      Inc(R.Pos);
      { F0/F7/FF are not channel messages and must not become the running
        status - a track that reuses running status after a SysEx would
        otherwise decode as garbage. }
      if Status < $F0 then
        RunningStatus := Status;
    end
    else
      Status := RunningStatus;

    if Status = 0 then
      Break;   { running status with nothing to run - corrupt track }

    ClearEvent(Ev);
    Ev.Tick := Tick;

    case Status and $F0 of
      $80, $90, $A0, $B0, $E0:
        begin
          D1 := ReadByte(R);
          D2 := ReadByte(R);
          Ev.Kind := mekShort;
          Ev.Msg := Status or (LongWord(D1) shl 8) or (LongWord(D2) shl 16);
        end;
      $C0, $D0:
        begin
          D1 := ReadByte(R);
          Ev.Kind := mekShort;
          Ev.Msg := Status or (LongWord(D1) shl 8);
        end;
    else
      case Status of
        $FF:
          begin
            MetaType := ReadByte(R);
            Len := ReadVLQ(R);
            if MetaType = $51 then
            begin
              { Set Tempo: three bytes of microseconds per quarter. }
              Ev.Kind := mekTempo;
              Ev.Msg := (LongWord(ReadByte(R)) shl 16) or
                        (LongWord(ReadByte(R)) shl 8) or
                         LongWord(ReadByte(R));
              if Len > 3 then
                Inc(R.Pos, Integer(Len) - 3);
            end
            else if MetaType = $2F then
            begin
              Ev.Kind := mekEndOfTrack;
              Inc(R.Pos, Integer(Len));
            end
            else
            begin
              { Track names, copyright, lyrics - carried by the file but not
                needed to make sound. Skipped, not stored. }
              Inc(R.Pos, Integer(Len));
              Continue;
            end;
          end;
        $F0, $F7:
          begin
            Len := ReadVLQ(R);
            Ev.Kind := mekSysEx;
            SetLength(Ev.Blob, Len + 1);
            Ev.Blob[0] := Status;
            for I := 0 to Integer(Len) - 1 do
              Ev.Blob[I + 1] := ReadByte(R);
          end;
      else
        { An unknown status byte means the stream is out of sync; abandoning the
          track is safer than guessing a length and desynchronising the rest. }
        Break;
      end;
    end;

    if N >= Length(Result) then
      SetLength(Result, (Length(Result) * 2) + 256);
    Result[N] := Ev;
    Inc(N);
  end;

  SetLength(Result, N);
end;

function TMidiFile.LoadFromFile(const FileName: string): Boolean;
var
  S: TFileStream;
  All: TBytes;
  R: TReader;
  ChunkID, ChunkLen, HeaderLen: LongWord;
  T, K, I, Total, Best, TrackEnd: Integer;
  Tracks: array of TMidiEventArray;
  Cursor: array of Integer;
  BestTick: LongWord;
begin
  Result := False;
  Clear;
  if not FileExists(FileName) then
    Exit;

  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if S.Size < 14 then
      Exit;
    SetLength(All, S.Size);
    S.ReadBuffer(All[0], S.Size);
  finally
    S.Free;
  end;

  R.Data := All;
  R.Pos := 0;
  R.Limit := Length(All);

  ChunkID := ReadBE32(R);
  if ChunkID <> $4D546864 then   { 'MThd' }
    Exit;
  HeaderLen := ReadBE32(R);
  FFormat := ReadBE16(R);
  FTrackCount := ReadBE16(R);
  FDivision := ReadBE16(R);
  { SMPTE division has the top bit set and means frames per second, not ticks
    per quarter. None of the 15 files use it; refuse rather than mis-time. }
  if ((FDivision and $8000) <> 0) or (FDivision = 0) then
    Exit;
  { Skip any header bytes beyond the six we understand. }
  R.Pos := 8 + Integer(HeaderLen);

  SetLength(Tracks, FTrackCount);
  T := 0;
  while (T < FTrackCount) and (R.Pos + 8 <= R.Limit) do
  begin
    ChunkID := ReadBE32(R);
    ChunkLen := ReadBE32(R);
    if ChunkID <> $4D54726B then   { 'MTrk' - skip anything else by length }
    begin
      Inc(R.Pos, ChunkLen);
      Continue;
    end;
    TrackEnd := R.Pos + Integer(ChunkLen);
    if TrackEnd > R.Limit then
      TrackEnd := R.Limit;
    Tracks[T] := ParseTrack(R, TrackEnd);
    R.Pos := TrackEnd;
    Inc(T);
  end;

  { k-way merge. Each track is already tick-ordered, so repeatedly taking the
    lowest-tick head is both correct and stable: ties go to the lower-numbered
    track, which preserves the file's own precedence (track 0 carries tempo in
    a format 1 file, so its events land before the notes they govern).

    This replaces sorting the concatenation, which would be quadratic - boss01
    alone holds tens of thousands of events. }
  Total := 0;
  for I := 0 to T - 1 do
    Inc(Total, Length(Tracks[I]));
  if Total = 0 then
    Exit;

  SetLength(FEvents, Total);
  SetLength(Cursor, T);
  for I := 0 to T - 1 do
    Cursor[I] := 0;

  for I := 0 to Total - 1 do
  begin
    Best := -1;
    BestTick := 0;
    for K := 0 to High(Cursor) do
      if Cursor[K] < Length(Tracks[K]) then
        if (Best < 0) or (Tracks[K][Cursor[K]].Tick < BestTick) then
        begin
          Best := K;
          BestTick := Tracks[K][Cursor[K]].Tick;
        end;
    if Best < 0 then
    begin
      SetLength(FEvents, I);
      Break;
    end;
    FEvents[I] := Tracks[Best][Cursor[Best]];
    Inc(Cursor[Best]);
  end;

  ComputeTimes;
  Result := Length(FEvents) > 0;
end;

end.
