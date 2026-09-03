{ RIFF/WAVE reader for mono PCM effects. The loader walks arbitrary chunks and
  normalizes 8-bit or 16-bit input at 11025 or 22050 Hz to signed 16-bit mono
  at MIX_RATE. }

unit WaveFile;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils;

const
  { The mix rate is chosen so that no fractional resampling is ever needed:
    22050 sources pass through 1:1 and 11025 sources duplicate 2:1. Picking
    44100 would have meant interpolating every file for no audible gain. }
  MIX_RATE = 22050;

type
  TSampleArray = array of SmallInt;

  TWaveData = record
    Samples: TSampleArray;   { mono, signed 16-bit, at MIX_RATE }
    SourceRate: Integer;     { rate as found in the file, kept for reporting }
    SourceBits: Integer;
    SourceChannels: Integer;
  end;

{ Loads and normalises. Returns False if the file is missing or is not
  something we can decode; W.Samples is empty in that case. }
function LoadWave(const FileName: string; out W: TWaveData): Boolean;

{ Duration in milliseconds, for diagnostics. }
function WaveDurationMs(const W: TWaveData): Integer;

implementation

type
  TChunkHeader = packed record
    ID: array[0..3] of AnsiChar;
    Size: LongWord;
  end;

  { The 16 bytes common to every WAVEFORMAT; cbSize and any extension that
    follows are skipped by the chunk walk. }
  TWaveFormat = packed record
    FormatTag: Word;
    Channels: Word;
    SamplesPerSec: LongWord;
    AvgBytesPerSec: LongWord;
    BlockAlign: Word;
    BitsPerSample: Word;
  end;

const
  WAVE_FORMAT_PCM = 1;

function WaveDurationMs(const W: TWaveData): Integer;
begin
  Result := (Length(W.Samples) * 1000) div MIX_RATE;
end;

{ Converts raw PCM to signed 16-bit mono. 8-bit WAV is unsigned with 128 as
  silence; 16-bit is signed with 0 as silence - the classic RIFF asymmetry. }
function DecodePCM(const Raw: array of Byte; Bits, Channels: Integer): TSampleArray;
var
  BytesPerSample, FrameCount, FrameIndex, ChannelIndex, SampleSum: Integer;
  ByteOffset: Integer;
begin
  BytesPerSample := Bits div 8;
  if (BytesPerSample = 0) or (Channels = 0) then
    Exit(nil);
  FrameCount := Length(Raw) div (BytesPerSample * Channels);
  SetLength(Result, FrameCount);
  for FrameIndex := 0 to FrameCount - 1 do
  begin
    SampleSum := 0;
    for ChannelIndex := 0 to Channels - 1 do
    begin
      ByteOffset := (FrameIndex * Channels + ChannelIndex) * BytesPerSample;
      if Bits = 8 then
        Inc(SampleSum, (Raw[ByteOffset] - 128) * 256)
      else
        Inc(SampleSum, SmallInt(Raw[ByteOffset]
                                or (Raw[ByteOffset + 1] shl 8)));
    end;
    { Downmix by averaging. Every shipped effect is mono, so this path is
      defensive only - it exists so a stereo file cannot corrupt the buffer. }
    Result[FrameIndex] := SampleSum div Channels;
  end;
end;

{ Integer-ratio upsample by sample duplication. Only ever called with
  Factor = 2, for the 11025 Hz files. }
function Upsample(const Src: TSampleArray; Factor: Integer): TSampleArray;
var
  SourceIndex, CopyIndex: Integer;
begin
  if Factor <= 1 then
    Exit(Src);
  SetLength(Result, Length(Src) * Factor);
  for SourceIndex := 0 to High(Src) do
    for CopyIndex := 0 to Factor - 1 do
      Result[SourceIndex * Factor + CopyIndex] := Src[SourceIndex];
end;

function LoadWave(const FileName: string; out W: TWaveData): Boolean;
var
  Stream: TFileStream;
  Chunk: TChunkHeader;
  RiffType: array[0..3] of AnsiChar;
  WaveFormat: TWaveFormat;
  RawSamples: array of Byte;
  HaveFormat, HaveData: Boolean;
  NextChunk: Int64;
begin
  Result := False;
  FillChar(W, SizeOf(W), 0);
  W.Samples := nil;
  if not FileExists(FileName) then
    Exit;

  HaveFormat := False;
  HaveData := False;
  FillChar(WaveFormat, SizeOf(WaveFormat), 0);

  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if Stream.Size < 12 then
      Exit;
    Stream.ReadBuffer(Chunk, SizeOf(Chunk));
    Stream.ReadBuffer(RiffType, 4);
    if (Chunk.ID <> 'RIFF') or (RiffType <> 'WAVE') then
      Exit;

    { Walk every chunk. 'fact' sits between 'fmt ' and 'data' in 49 of the 57
      files, so skipping by size rather than assuming an order is required. }
    while Stream.Position + SizeOf(Chunk) <= Stream.Size do
    begin
      Stream.ReadBuffer(Chunk, SizeOf(Chunk));
      { RIFF chunks are word-aligned: an odd size is followed by a pad byte
        that is not counted in Size. }
      NextChunk := Stream.Position + Chunk.Size + (Chunk.Size and 1);

      if Chunk.ID = 'fmt ' then
      begin
        if Chunk.Size >= SizeOf(WaveFormat) then
        begin
          Stream.ReadBuffer(WaveFormat, SizeOf(WaveFormat));
          HaveFormat := True;
        end;
      end
      else if Chunk.ID = 'data' then
      begin
        if Chunk.Size > 0 then
        begin
          SetLength(RawSamples, Chunk.Size);
          Stream.ReadBuffer(RawSamples[0], Chunk.Size);
          HaveData := True;
        end;
      end;

      if NextChunk > Stream.Size then
        Break;
      Stream.Position := NextChunk;
    end;
  finally
    Stream.Free;
  end;

  if not (HaveFormat and HaveData) then
    Exit;
  if WaveFormat.FormatTag <> WAVE_FORMAT_PCM then
    Exit;
  if not (WaveFormat.BitsPerSample in [8, 16]) then
    Exit;
  if (WaveFormat.Channels < 1) or (WaveFormat.Channels > 2) then
    Exit;
  if WaveFormat.SamplesPerSec = 0 then
    Exit;

  W.SourceRate := WaveFormat.SamplesPerSec;
  W.SourceBits := WaveFormat.BitsPerSample;
  W.SourceChannels := WaveFormat.Channels;
  W.Samples := DecodePCM(RawSamples, WaveFormat.BitsPerSample,
                         WaveFormat.Channels);

  { Every shipped rate divides MIX_RATE exactly. A file at some other rate is
    left at its own rate and will play at the wrong pitch rather than being
    dropped - loud and obvious beats silently missing. }
  if (W.SourceRate < MIX_RATE) and (MIX_RATE mod W.SourceRate = 0) then
    W.Samples := Upsample(W.Samples, MIX_RATE div Integer(W.SourceRate));

  Result := Length(W.Samples) > 0;
end;

end.
