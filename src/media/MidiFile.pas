{ Standard MIDI File reader. Tracks are parsed separately, merged by absolute
  tick, and assigned absolute microsecond timestamps from the tempo map. Sound
  output is handled by MidiOut. }

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
  CurrentByte: Byte;
  ByteCount: Integer;
begin
  Result := 0;
  ByteCount := 0;
  repeat
    CurrentByte := ReadByte(R);
    Result := (Result shl 7) or (CurrentByte and $7F);
    Inc(ByteCount);
  until ((CurrentByte and $80) = 0) or (ByteCount >= 4)
        or (R.Pos >= R.Limit);
end;

{ Clears a TMidiEvent field by field. FillChar must not be used on a record
  holding a dynamic array: it would overwrite the reference without releasing
  it, leaking the SysEx blob of the previous event. }
procedure ClearEvent(var MidiEvent: TMidiEvent);
begin
  MidiEvent.Tick := 0;
  MidiEvent.TimeUs := 0;
  MidiEvent.Kind := mekShort;
  MidiEvent.Msg := 0;
  MidiEvent.Blob := nil;
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
  EventIndex: Integer;
  TempoUs: LongWord;
  LastTick: LongWord;
  ElapsedUs: Int64;
begin
  TempoUs := DEFAULT_TEMPO_US;
  LastTick := 0;
  ElapsedUs := 0;
  for EventIndex := 0 to High(FEvents) do
  begin
    if FDivision > 0 then
      ElapsedUs := ElapsedUs
                   + (Int64(FEvents[EventIndex].Tick - LastTick) * TempoUs)
                     div FDivision;
    LastTick := FEvents[EventIndex].Tick;
    FEvents[EventIndex].TimeUs := ElapsedUs;
    if FEvents[EventIndex].Kind = mekTempo then
      TempoUs := FEvents[EventIndex].Msg;
  end;
  FDurationUs := ElapsedUs;
end;

{ Parses one MTrk body into a tick-ordered event list. R.Pos must be at the
  first delta time and TrackEnd just past the last byte of the chunk. }
function ParseTrack(var R: TReader; TrackEnd: Integer): TMidiEventArray;
var
  Tick: LongWord;
  Status, RunningStatus, Data1, Data2, MetaType: Byte;
  DataLength: LongWord;
  MidiEvent: TMidiEvent;
  EventCount, ByteIndex: Integer;
begin
  Result := nil;
  EventCount := 0;
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

    ClearEvent(MidiEvent);
    MidiEvent.Tick := Tick;

    case Status and $F0 of
      $80, $90, $A0, $B0, $E0:
        begin
          Data1 := ReadByte(R);
          Data2 := ReadByte(R);
          MidiEvent.Kind := mekShort;
          MidiEvent.Msg := Status or (LongWord(Data1) shl 8)
                           or (LongWord(Data2) shl 16);
        end;
      $C0, $D0:
        begin
          Data1 := ReadByte(R);
          MidiEvent.Kind := mekShort;
          MidiEvent.Msg := Status or (LongWord(Data1) shl 8);
        end;
    else
      case Status of
        $FF:
          begin
            MetaType := ReadByte(R);
            DataLength := ReadVLQ(R);
            if MetaType = $51 then
            begin
              { Set Tempo: three bytes of microseconds per quarter. }
              MidiEvent.Kind := mekTempo;
              MidiEvent.Msg := (LongWord(ReadByte(R)) shl 16) or
                               (LongWord(ReadByte(R)) shl 8) or
                                LongWord(ReadByte(R));
              if DataLength > 3 then
                Inc(R.Pos, Integer(DataLength) - 3);
            end
            else if MetaType = $2F then
            begin
              MidiEvent.Kind := mekEndOfTrack;
              Inc(R.Pos, Integer(DataLength));
            end
            else
            begin
              { Track names, copyright, lyrics - carried by the file but not
                needed to make sound. Skipped, not stored. }
              Inc(R.Pos, Integer(DataLength));
              Continue;
            end;
          end;
        $F0, $F7:
          begin
            DataLength := ReadVLQ(R);
            MidiEvent.Kind := mekSysEx;
            SetLength(MidiEvent.Blob, DataLength + 1);
            MidiEvent.Blob[0] := Status;
            for ByteIndex := 0 to Integer(DataLength) - 1 do
              MidiEvent.Blob[ByteIndex + 1] := ReadByte(R);
          end;
      else
        { An unknown status byte means the stream is out of sync; abandoning the
          track is safer than guessing a length and desynchronising the rest. }
        Break;
      end;
    end;

    if EventCount >= Length(Result) then
      SetLength(Result, (Length(Result) * 2) + 256);
    Result[EventCount] := MidiEvent;
    Inc(EventCount);
  end;

  SetLength(Result, EventCount);
end;

function TMidiFile.LoadFromFile(const FileName: string): Boolean;
var
  Stream: TFileStream;
  FileData: TBytes;
  Reader: TReader;
  ChunkID, ChunkLen, HeaderLen: LongWord;
  TrackCount, CandidateTrack, EventIndex, TotalEvents, BestTrack: Integer;
  TrackEnd: Integer;
  Tracks: array of TMidiEventArray;
  TrackCursor: array of Integer;
  BestTick: LongWord;
begin
  Result := False;
  Clear;
  if not FileExists(FileName) then
    Exit;

  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if Stream.Size < 14 then
      Exit;
    SetLength(FileData, Stream.Size);
    Stream.ReadBuffer(FileData[0], Stream.Size);
  finally
    Stream.Free;
  end;

  Reader.Data := FileData;
  Reader.Pos := 0;
  Reader.Limit := Length(FileData);

  ChunkID := ReadBE32(Reader);
  if ChunkID <> $4D546864 then   { 'MThd' }
    Exit;
  HeaderLen := ReadBE32(Reader);
  FFormat := ReadBE16(Reader);
  FTrackCount := ReadBE16(Reader);
  FDivision := ReadBE16(Reader);
  { SMPTE division has the top bit set and means frames per second, not ticks
    per quarter. None of the 15 files use it; refuse rather than mis-time. }
  if ((FDivision and $8000) <> 0) or (FDivision = 0) then
    Exit;
  { Skip any header bytes beyond the six we understand. }
  Reader.Pos := 8 + Integer(HeaderLen);

  SetLength(Tracks, FTrackCount);
  TrackCount := 0;
  while (TrackCount < FTrackCount)
        and (Reader.Pos + 8 <= Reader.Limit) do
  begin
    ChunkID := ReadBE32(Reader);
    ChunkLen := ReadBE32(Reader);
    if ChunkID <> $4D54726B then   { 'MTrk' - skip anything else by length }
    begin
      Inc(Reader.Pos, ChunkLen);
      Continue;
    end;
    TrackEnd := Reader.Pos + Integer(ChunkLen);
    if TrackEnd > Reader.Limit then
      TrackEnd := Reader.Limit;
    Tracks[TrackCount] := ParseTrack(Reader, TrackEnd);
    Reader.Pos := TrackEnd;
    Inc(TrackCount);
  end;

  { k-way merge. Each track is already tick-ordered, so repeatedly taking the
    lowest-tick head is both correct and stable: ties go to the lower-numbered
    track, which preserves the file's own precedence (track 0 carries tempo in
    a format 1 file, so its events land before the notes they govern).

    This replaces sorting the concatenation, which would be quadratic - boss01
    alone holds tens of thousands of events. }
  TotalEvents := 0;
  for EventIndex := 0 to TrackCount - 1 do
    Inc(TotalEvents, Length(Tracks[EventIndex]));
  if TotalEvents = 0 then
    Exit;

  SetLength(FEvents, TotalEvents);
  SetLength(TrackCursor, TrackCount);
  for EventIndex := 0 to TrackCount - 1 do
    TrackCursor[EventIndex] := 0;

  for EventIndex := 0 to TotalEvents - 1 do
  begin
    BestTrack := -1;
    BestTick := 0;
    for CandidateTrack := 0 to High(TrackCursor) do
      if TrackCursor[CandidateTrack] < Length(Tracks[CandidateTrack]) then
        if (BestTrack < 0)
           or (Tracks[CandidateTrack][TrackCursor[CandidateTrack]].Tick
               < BestTick) then
        begin
          BestTrack := CandidateTrack;
          BestTick := Tracks[CandidateTrack][TrackCursor[CandidateTrack]].Tick;
        end;
    if BestTrack < 0 then
    begin
      SetLength(FEvents, EventIndex);
      Break;
    end;
    FEvents[EventIndex] := Tracks[BestTrack][TrackCursor[BestTrack]];
    Inc(TrackCursor[BestTrack]);
  end;

  ComputeTimes;
  Result := Length(FEvents) > 0;
end;

end.
