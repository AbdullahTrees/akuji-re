{ WaveFile - RIFF/WAVE reader.

  The original read its effects with the winmm mmio* RIFF calls
  (mmioOpen / mmioDescend / mmioRead / mmioAscend / mmioClose). Those are a
  Windows API, so they leave with the rest of the platform layer; this is the
  same job done in plain Pascal.

  What the game actually ships (all 57 files surveyed, no exceptions):

      format tag  1 (PCM) everywhere - no ADPCM, no compression
      channels    1 everywhere
      44 files    22050 Hz, 8-bit
       9 files    11025 Hz, 8-bit
       3 files    22050 Hz, 16-bit
       1 file     11025 Hz, 16-bit

  49 of the 57 carry a 'fact' chunk between 'fmt ' and 'data'. That is unusual
  for uncompressed PCM and it is the one thing a naive reader gets wrong: a
  parser that assumes 'data' follows 'fmt ' immediately reads the fact chunk as
  audio. The chunk walk below is therefore a real walk, not an assumption.

  Everything is normalised on load to signed 16-bit mono at MIX_RATE, so the
  mixer never has to branch on source format. }

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
  BytesPerSample, Frames, I, C, Acc: Integer;
  P: Integer;
begin
  BytesPerSample := Bits div 8;
  if (BytesPerSample = 0) or (Channels = 0) then
    Exit(nil);
  Frames := Length(Raw) div (BytesPerSample * Channels);
  SetLength(Result, Frames);
  for I := 0 to Frames - 1 do
  begin
    Acc := 0;
    for C := 0 to Channels - 1 do
    begin
      P := (I * Channels + C) * BytesPerSample;
      if Bits = 8 then
        Inc(Acc, (Raw[P] - 128) * 256)
      else
        Inc(Acc, SmallInt(Raw[P] or (Raw[P + 1] shl 8)));
    end;
    { Downmix by averaging. Every shipped effect is mono, so this path is
      defensive only - it exists so a stereo file cannot corrupt the buffer. }
    Result[I] := Acc div Channels;
  end;
end;

{ Integer-ratio upsample by sample duplication. Only ever called with
  Factor = 2, for the 11025 Hz files. }
function Upsample(const Src: TSampleArray; Factor: Integer): TSampleArray;
var
  I, J: Integer;
begin
  if Factor <= 1 then
    Exit(Src);
  SetLength(Result, Length(Src) * Factor);
  for I := 0 to High(Src) do
    for J := 0 to Factor - 1 do
      Result[I * Factor + J] := Src[I];
end;

function LoadWave(const FileName: string; out W: TWaveData): Boolean;
var
  S: TFileStream;
  Hdr: TChunkHeader;
  RiffType: array[0..3] of AnsiChar;
  Fmt: TWaveFormat;
  Raw: array of Byte;
  HaveFmt, HaveData: Boolean;
  Next: Int64;
begin
  Result := False;
  FillChar(W, SizeOf(W), 0);
  W.Samples := nil;
  if not FileExists(FileName) then
    Exit;

  HaveFmt := False;
  HaveData := False;
  FillChar(Fmt, SizeOf(Fmt), 0);

  S := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    if S.Size < 12 then
      Exit;
    S.ReadBuffer(Hdr, SizeOf(Hdr));
    S.ReadBuffer(RiffType, 4);
    if (Hdr.ID <> 'RIFF') or (RiffType <> 'WAVE') then
      Exit;

    { Walk every chunk. 'fact' sits between 'fmt ' and 'data' in 49 of the 57
      files, so skipping by size rather than assuming an order is required. }
    while S.Position + SizeOf(Hdr) <= S.Size do
    begin
      S.ReadBuffer(Hdr, SizeOf(Hdr));
      { RIFF chunks are word-aligned: an odd size is followed by a pad byte
        that is not counted in Size. }
      Next := S.Position + Hdr.Size + (Hdr.Size and 1);

      if Hdr.ID = 'fmt ' then
      begin
        if Hdr.Size >= SizeOf(Fmt) then
        begin
          S.ReadBuffer(Fmt, SizeOf(Fmt));
          HaveFmt := True;
        end;
      end
      else if Hdr.ID = 'data' then
      begin
        if Hdr.Size > 0 then
        begin
          SetLength(Raw, Hdr.Size);
          S.ReadBuffer(Raw[0], Hdr.Size);
          HaveData := True;
        end;
      end;

      if Next > S.Size then
        Break;
      S.Position := Next;
    end;
  finally
    S.Free;
  end;

  if not (HaveFmt and HaveData) then
    Exit;
  if Fmt.FormatTag <> WAVE_FORMAT_PCM then
    Exit;
  if not (Fmt.BitsPerSample in [8, 16]) then
    Exit;
  if (Fmt.Channels < 1) or (Fmt.Channels > 2) then
    Exit;
  if Fmt.SamplesPerSec = 0 then
    Exit;

  W.SourceRate := Fmt.SamplesPerSec;
  W.SourceBits := Fmt.BitsPerSample;
  W.SourceChannels := Fmt.Channels;
  W.Samples := DecodePCM(Raw, Fmt.BitsPerSample, Fmt.Channels);

  { Every shipped rate divides MIX_RATE exactly. A file at some other rate is
    left at its own rate and will play at the wrong pitch rather than being
    dropped - loud and obvious beats silently missing. }
  if (W.SourceRate < MIX_RATE) and (MIX_RATE mod W.SourceRate = 0) then
    W.Samples := Upsample(W.Samples, MIX_RATE div Integer(W.SourceRate));

  Result := Length(W.Samples) > 0;
end;

end.
