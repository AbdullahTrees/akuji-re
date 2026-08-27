{ Akuji the Demon - Free Pascal / Lazarus source port.

  This file is a faithful reconstruction of the original Delphi .dpr program
  block, recovered from `entry` at 0x0046716c in akuji.exe:

      Delphi_RTL_Init(&LAB_00466ee4);
      TApplication_Initialize();
      TApplication_SetTitle(Application, "Akuji the Demon");
      TApplication_CreateForm(Application, PTR_PTR_00464b54, MainForm);
      TApplication_Run(Application);
      Delphi_Halt0();

  The unit name GmMain was recovered from the class RTTI (TTypeData.UnitName
  for TFrm_main). See CLAUDE.md section 5.

  Two notes on the entry point. Its address is 0x0046716C, taken from the PE
  header's AddressOfEntryPoint rather than from a guess - an earlier version of
  this comment said 0x004671AC, which is only the CreateForm CALL inside it.

  And the title literal at 0x004671CC is odd: its Delphi length field reads 12,
  but the bytes that follow are 'Akuji the Demon' + NUL, which is 15. The form
  resource's Caption is unambiguously 'Akuji the Demon', so that is what is
  used here; the discrepancy is recorded rather than resolved. }

program akuji;

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces,   // LCL widgetset - must come first
  Forms,
  GmMain in 'GmMain.pas' {Frm_main},
  QdaArchive, SoundTable, WaveFile, AudioMixer, AudioOut, MidiFile,
  KbgmPlayer, Directions, Entities, EventScripts, EventCommands, PlayerState, GameState,
  Stages,
  Classes, SysUtils, TypInfo;

{ $R *.res  -- re-enable once Lazarus generates akuji.res (icon/manifest) }

{ ---------------------------------------------------------------------------
  Self-tests.

  These exist because "it compiles and a window appears" proves almost nothing
  about a reconstruction. Each mode below re-reads the game's own shipped data
  and dumps what our reader made of it, so an independent implementation (the
  scripts in tools/) can diff the two. Agreement between two readers written
  from the same evidence is the strongest check available without the original
  source - see the verification note in CLAUDE.md.

  Output goes to selftest.log beside the executable: this is a GUI-subsystem
  binary with no console attached, so WriteLn goes nowhere.
  --------------------------------------------------------------------------- }

{ --selftest <qda> [outdir] : archive reader. }
function SelfTestArchive(Log: TStrings): Integer;
var
  A: TQdaArchive;
  I: Integer;
  Raw: TMemoryStream;
  OutDir: string;
begin
  Result := 0;
  OutDir := '';
  if ParamCount >= 3 then
    OutDir := IncludeTrailingPathDelimiter(ParamStr(3));

  A := TQdaArchive.Create(ParamStr(2));
  try
    Log.Add(Format('archive: %s', [ParamStr(2)]));
    Log.Add(Format('entries: %d', [A.Count]));
    for I := 0 to A.Count - 1 do
    begin
      Log.Add(Format('%-18s off=%-9d size=%d',
        [A.Entries[I].Name, A.Entries[I].Offset, A.Entries[I].Size]));
      if OutDir <> '' then
      begin
        Raw := TMemoryStream.Create;
        try
          A.LoadRaw(I, Raw);
          Raw.SaveToFile(OutDir + A.Entries[I].Name);
        finally
          Raw.Free;
        end;
      end;
    end;
    Log.Add('OK');
  finally
    A.Free;
  end;
end;

{ Additive 32-bit checksum over the decoded samples. Cheap, order-sensitive,
  and trivial to reproduce in another language - which is the whole point. }
function SampleChecksum(const W: TWaveData): LongWord;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(W.Samples) do
    Result := ((Result shl 1) or (Result shr 31)) xor LongWord(Word(W.Samples[I]));
end;

{ --selftest-audio <gamedir> [outdir] : the sound-effect path.

  Decodes all 57 effects and reports the source format of each. If outdir is
  given, the normalised PCM (signed 16-bit mono at MIX_RATE) is written there
  as raw .pcm so tools/decode_wav_ref.py can compare byte for byte. }
function SelfTestAudio(Log: TStrings): Integer;
var
  GameDir, OutDir, Path: string;
  I, Ok, Missing: Integer;
  W: TWaveData;
  F: TFileStream;
begin
  Result := 0;
  GameDir := ParamStr(2);
  OutDir := '';
  if ParamCount >= 3 then
    OutDir := IncludeTrailingPathDelimiter(ParamStr(3));

  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add(Format('table entries: %d   mix rate: %d Hz', [SOUND_COUNT, MIX_RATE]));
  Log.Add('');
  Log.Add('idx name              rate  bits ch  samples     ms  checksum');

  Ok := 0;
  Missing := 0;
  for I := 0 to SOUND_COUNT - 1 do
  begin
    Path := SoundPath(GameDir, I);
    if not LoadWave(Path, W) then
    begin
      Log.Add(Format('%3d %-17s MISSING OR UNDECODABLE (%s)',
        [I, SoundNames[I], Path]));
      Inc(Missing);
      Continue;
    end;
    Inc(Ok);
    Log.Add(Format('%3d %-17s %5d %5d %2d %8d %6d  %8.8x',
      [I, SoundNames[I], W.SourceRate, W.SourceBits, W.SourceChannels,
       Length(W.Samples), WaveDurationMs(W), SampleChecksum(W)]));

    if (OutDir <> '') and (Length(W.Samples) > 0) then
    begin
      F := TFileStream.Create(Format('%s%.2d.pcm', [OutDir, I]), fmCreate);
      try
        F.WriteBuffer(W.Samples[0], Length(W.Samples) * SizeOf(SmallInt));
      finally
        F.Free;
      end;
    end;
  end;

  Log.Add('');
  Log.Add(Format('decoded %d of %d, %d missing', [Ok, SOUND_COUNT, Missing]));
  if Ok = 0 then
    Log.Add('FAILED: nothing decoded at all - wrong game directory?');

  { The original's attenuation curve, tabulated so it can be checked against
    the disassembly by hand: SetVolume((10 - v) * -0x1C2), hundredths of a dB. }
  Log.Add('');
  Log.Add('volume curve (settings +0x24 -> DirectSound mB -> linear gain):');
  for I := 0 to VOLUME_MAX do
    Log.Add(Format('  v=%2d  %6d mB  gain %.5f',
      [I, (VOLUME_MAX - I) * VOLUME_STEP_MB, VolumeToGain(I) / 65536.0]));

  if Missing > 0 then
    Result := 1
  else
    Log.Add('OK');
end;

{ --selftest-midi <gamedir> : the music path.

  Parses every track in the playlist and reports what the reader made of it.
  The event checksum covers the MERGED stream, so it validates the k-way merge
  and the running-status handling, not just the chunk walk - a parser that
  merged tracks in the wrong order would still report the right event count.
  tools/parse_midi_ref.py recomputes the same numbers independently. }
function SelfTestMidi(Log: TStrings): Integer;
const
  { The playlist, from the form resource; it also sits in the executable as a
    static array[0..14] of AnsiString at VA 0x00468D14. }
  PLAYLIST: array[0..14] of string = (
    'init', 'main01', 'gameover', 'boss01', 'itemget', 'open01', 'end01',
    'main02', 'open02', 'boss02', 'end02', 'soulget', 'end03', 'end04',
    'end05');
var
  GameDir, Path: string;
  I, J, Bad: Integer;
  M: TMidiFile;
  Ev: TMidiEvent;
  Sum: LongWord;
begin
  Result := 0;
  GameDir := IncludeTrailingPathDelimiter(ParamStr(2));
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');
  Log.Add('name        fmt trks  div   events   ms  checksum');

  Bad := 0;
  M := TMidiFile.Create;
  try
    for I := 0 to High(PLAYLIST) do
    begin
      Path := GameDir + 'midi' + PathDelim + PLAYLIST[I] + '.mid';
      if not M.LoadFromFile(Path) then
      begin
        Log.Add(Format('%-11s PARSE FAILED (%s)', [PLAYLIST[I], Path]));
        Inc(Bad);
        Continue;
      end;

      Sum := 0;
      for J := 0 to M.Count - 1 do
      begin
        Ev := M[J];
        Sum := ((Sum shl 1) or (Sum shr 31)) xor Ev.Tick;
        Sum := ((Sum shl 1) or (Sum shr 31)) xor Ev.Msg;
        Sum := ((Sum shl 1) or (Sum shr 31)) xor LongWord(Ord(Ev.Kind));
      end;

      Log.Add(Format('%-11s %3d %4d %4d %8d %6d  %8.8x',
        [PLAYLIST[I], M.Format, M.TrackCount, M.Division, M.Count,
         M.DurationUs div 1000, Sum]));
    end;
  finally
    M.Free;
  end;

  Log.Add('');
  Log.Add(Format('parsed %d of %d', [Length(PLAYLIST) - Bad, Length(PLAYLIST)]));
  if Bad > 0 then
    Result := 1
  else
    Log.Add('OK');
end;

{ --playtest <gamedir> [seconds] : make actual noise.

  The other self-tests prove the decoders agree with an independent reader, but
  they never open a device, so they cannot tell you whether anything is audible.
  This one opens both devices, plays a handful of effects with gaps, then plays
  a real music track, and records exactly what each step reported. If it is
  silent, selftest.log says which stage failed rather than leaving you guessing.

  Note that midi/init.mid is a GM Reset and two Roland GS writes with no notes
  in it at all, so playing track 0 is correctly silent. main01 is used here. }
function PlayTest(Log: TStrings): Integer;
const
  { A spread of formats: 8-bit and 16-bit, 11025 and 22050. }
  DEMO: array[0..5] of Integer = (
    SND_PI, SND_OK, SND_NG, SND_JUMP, SND_BELL, SND_POWER01);
var
  GameDir: string;
  Mixer: TAudioMixer;
  Device: TAudioOut;
  Music: TKbgmPlayer;
  I, Secs: Integer;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Secs := 20;
  if ParamCount >= 3 then
    Secs := StrToIntDef(ParamStr(3), 20);

  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');

  Mixer := TAudioMixer.Create;
  Device := TAudioOut.Create(Mixer);
  Music := TKbgmPlayer.Create(nil);
  try
    Log.Add(Format('effects loaded: %d of %d',
      [Mixer.LoadAll(GameDir), SOUND_COUNT]));

    if not Device.Start then
    begin
      Log.Add('AUDIO DEVICE FAILED: ' + Device.LastError);
      Result := 1;
    end
    else
    begin
      Log.Add('audio device: open');
      Mixer.Volume := VOLUME_MAX;
      for I := Low(DEMO) to High(DEMO) do
      begin
        Log.Add(Format('  playing %2d  %s', [DEMO[I], SoundNames[DEMO[I]]]));
        Mixer.Play(DEMO[I]);
        Sleep(900);
      end;
      { All at once, to prove the mixer really mixes rather than cutting to the
        newest sound. }
      Log.Add('  playing all six together');
      for I := Low(DEMO) to High(DEMO) do
        Mixer.Play(DEMO[I]);
      Sleep(2000);
    end;

    { The playlist normally arrives by streaming the form; there is no form
      here, so fill it the same way the .lfm does. }
    Music.AutoLoadMidis.Add('midi\main01');
    if not Music.Open(GameDir) then
      Log.Add('MIDI DEVICE FAILED: opened=' + BoolToStr(Music.Opened, True))
    else
    begin
      Log.Add('midi device: open');
      Music.Volume := KBGM_VOLUME_MAX;
      Music.Play(0, True);
      Log.Add(Format('  playing midi\main01 for %d seconds', [Secs]));
      Sleep(Secs * 1000);
      Music.FadeOut(1500);
      Sleep(2000);
      Log.Add('  faded out');
    end;
  finally
    Music.Free;
    Device.Free;
    Mixer.Free;
  end;

  Log.Add('');
  if Result = 0 then
    Log.Add('OK');
end;

{ --mixdump <gamedir> <out.wav> : render the mixer to a file, no device.

  This splits "the decoder and mixer produce sound" from "the machine plays
  sound", which --playtest cannot: waveOut reports success whether or not
  anything reaches your speakers. If the WAV this writes sounds right in any
  player, everything up to AudioOut is correct and the problem is the device,
  the default output, or the volume. If it is silent, the fault is ours.

  Peak and RMS are reported too, so the log answers the question even without
  listening to the file. }
function MixDump(Log: TStrings): Integer;
const
  DEMO: array[0..5] of Integer = (
    SND_PI, SND_OK, SND_NG, SND_JUMP, SND_BELL, SND_POWER01);
  BLOCK = 1024;                 { frames per mix call }
  TOTAL_SECS = 8;
var
  GameDir, OutName: string;
  Mixer: TAudioMixer;
  Buf: array of SmallInt;
  F: TFileStream;
  TotalFrames, Done, Next, I, Peak, V, Clipped: Integer;
  Sum: Int64;
  DataBytes: LongWord;
  W: LongWord;
  H: Word;

  procedure W32(X: LongWord);
  begin
    F.WriteBuffer(X, 4);
  end;

  procedure W16(X: Word);
  begin
    F.WriteBuffer(X, 2);
  end;

  procedure WTag(const S: string);
  var
    B: array[0..3] of AnsiChar;
  begin
    B[0] := S[1]; B[1] := S[2]; B[2] := S[3]; B[3] := S[4];
    F.WriteBuffer(B, 4);
  end;

begin
  Result := 0;
  GameDir := ParamStr(2);
  OutName := ParamStr(3);
  if OutName = '' then
    OutName := ExtractFilePath(ParamStr(0)) + 'mixdump.wav';

  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add(Format('writing:  %s', [OutName]));
  Log.Add('');

  Mixer := TAudioMixer.Create;
  try
    Log.Add(Format('effects loaded: %d of %d',
      [Mixer.LoadAll(GameDir), SOUND_COUNT]));
    Mixer.Volume := VOLUME_MAX;

    { Rounded up to a whole number of mix blocks, because the render loop below
      writes whole blocks. Declaring 22050*8 frames and then writing 177152
      leaves the RIFF size fields disagreeing with the file, which some players
      accept and others truncate. }
    TotalFrames := ((MIX_RATE * TOTAL_SECS + BLOCK - 1) div BLOCK) * BLOCK;
    DataBytes := LongWord(TotalFrames) * MIX_CHANNELS * 2;
    SetLength(Buf, BLOCK * MIX_CHANNELS);

    F := TFileStream.Create(OutName, fmCreate);
    try
      { Canonical 44-byte RIFF/WAVE header, 22050 Hz 16-bit stereo. }
      WTag('RIFF');  W32(36 + DataBytes);  WTag('WAVE');
      WTag('fmt ');  W32(16);
      H := 1;              W16(H);                    { PCM }
      H := MIX_CHANNELS;   W16(H);
      W := MIX_RATE;       W32(W);
      W := MIX_RATE * MIX_CHANNELS * 2; W32(W);       { byte rate }
      H := MIX_CHANNELS * 2; W16(H);                  { block align }
      H := 16;             W16(H);                    { bits }
      WTag('data');  W32(DataBytes);

      Peak := 0;
      Sum := 0;
      Done := 0;
      Next := 0;
      Clipped := 0;
      while Done < TotalFrames do
      begin
        { Trigger one effect per second, then all six together at the end. }
        if Done >= Next then
        begin
          I := Next div MIX_RATE;
          if I <= High(DEMO) then
            Mixer.Play(DEMO[I])
          else
            for I := Low(DEMO) to High(DEMO) do
              Mixer.Play(DEMO[I]);
          Inc(Next, MIX_RATE);
        end;

        Mixer.MixInto(@Buf[0], BLOCK);
        F.WriteBuffer(Buf[0], BLOCK * MIX_CHANNELS * 2);

        for I := 0 to BLOCK - 1 do
        begin
          V := Buf[I * MIX_CHANNELS];
          { -32768 has no positive counterpart, so Abs would overflow and
            report 32768 - a peak one above full scale, which looks like a bug
            in the mixer rather than in the meter. Negate the other way. }
          if V < 0 then
            V := -(V + 1);
          if V > Peak then
            Peak := V;
          Sum := Sum + Int64(Buf[I * MIX_CHANNELS]) * Buf[I * MIX_CHANNELS];
          if (Buf[I * MIX_CHANNELS] >= 32767) or
             (Buf[I * MIX_CHANNELS] <= -32768) then
            Inc(Clipped);
        end;
        Inc(Done, BLOCK);
      end;
    finally
      F.Free;
    end;

    Log.Add('');
    Log.Add(Format('rendered %d frames (%.2f s), peak %d of 32767, RMS %.1f',
      [TotalFrames, TotalFrames / MIX_RATE, Peak, Sqrt(Sum / Done)]));
    { Six effects at full volume will sum past full scale. The original summed
      in DirectSound and clipped too, so this is faithful rather than a defect -
      but it should be visible rather than silently absorbed. }
    Log.Add(Format('clipped samples: %d of %d (%.2f%%)',
      [Clipped, Done, (Clipped * 100.0) / Done]));
    if Peak = 0 then
    begin
      Log.Add('SILENT - the fault is in the decoder or mixer, not the device.');
      Result := 1;
    end
    else
    begin
      Log.Add('Non-silent. Play the file above to confirm it sounds right;');
      Log.Add('if it does, decoding and mixing are fine and the device is not.');
    end;
  finally
    Mixer.Free;
  end;

  if Result = 0 then
    Log.Add('OK');
end;

{ --selftest-dir : the 64-step direction system. Needs no game data.

  Checks three things about Directions.pas that the binary lets us assert:

    1. DIR_COS is exactly trunc(32 * cos(i * 2*Pi / 64)) for all 64 entries.
       That closed form was derived from the shipped table, so this catches a
       transcription slip in either direction.
    2. The Y table really is the X table rotated a quarter turn, which is the
       identity that let the second 64-int table at 0x00468C14 be dropped.
    3. AngleBetween round-trips: stepping away from the origin along direction
       d and asking for the angle back gives d again. This is the real test of
       the integer atan2 - it exercises all four quadrant branches and the
       sixteen sub-steps, with no floating point anywhere. }
function SelfTestDirections(Log: TStrings): Integer;
var
  E: TEntity;
  PosBad, Expect: Integer;
  I, D, Got, Bad, RoundTrips: Integer;
  Expected: Integer;
  X, Y: Integer;
begin
  Result := 0;
  Bad := 0;

  Log.Add('DIR_COS vs trunc(32 * cos(i * 2Pi / 64)):');
  for I := 0 to DIR_COUNT - 1 do
  begin
    Expected := Trunc(32.0 * Cos(I * 2.0 * Pi / DIR_COUNT));
    if DIR_COS[I] <> Expected then
    begin
      Log.Add(Format('  i=%2d table=%3d closed form=%3d', [I, DIR_COS[I], Expected]));
      Inc(Bad);
    end;
  end;
  Log.Add(Format('  %d mismatches', [Bad]));

  Log.Add('');
  Log.Add('DirVelY(d) = DIR_COS[(d + 16) mod 64]:');
  I := 0;
  for D := 0 to DIR_COUNT - 1 do
    if DirVelY(D) <> DIR_COS[(D + DIR_QUARTER) and DIR_MASK] then
      Inc(I);
  Log.Add(Format('  %d mismatches', [I]));
  Inc(Bad, I);

  Log.Add('');
  Log.Add('AngleBetween round-trip (origin -> a point along each direction):');
  RoundTrips := 0;
  I := 0;
  for D := 0 to DIR_COUNT - 1 do
  begin
    { Scaled up so truncation in the table does not move the point into the
      neighbouring sub-step. }
    X := DirVelX(D) * 64;
    Y := DirVelY(D) * 64;
    Got := AngleBetween(0, 0, X, Y);
    Inc(RoundTrips);
    if Got <> D then
    begin
      Log.Add(Format('  dir %2d -> (%6d,%6d) -> %2d', [D, X, Y, Got]));
      Inc(I);
    end;
  end;
  Log.Add(Format('  %d of %d directions round-tripped exactly',
    [RoundTrips - I, RoundTrips]));
  Inc(Bad, I);

  Log.Add('');
  { The record size is checked in Entities' initialization section rather than
    here: comparing SizeOf against a constant is folded at compile time, so the
    compiler proves it and then warns that the failure branch is unreachable. }
  { --- the position -> pixel conversion -------------------------------------

    Entity_IsOffScreen @ 0x004580BC removes POSITION_BIAS and shifts right by
    5, but for negatives it subtracts POSITION_BIAS-31 first. An arithmetic
    shift floors, so without that correction a negative position would round
    the wrong way and an entity just off the left edge would be judged one
    pixel further out than the original judges it.

    This checks the Pascal against the rule stated independently: truncation
    toward zero of (raw - bias) / 32. Getting this wrong is invisible in normal
    play and shows up only at the screen edges, so it is worth pinning. }
  PosBad := 0;
  for I := -4000 to 4000 do
  begin
    E.Raw[EF_POS_X] := POSITION_BIAS + I;
    Expect := I div 32;   { Pascal div truncates toward zero, like the original }
    if EntityPixelX(E) <> Expect then
    begin
      if PosBad < 5 then
        Log.Add(Format('  offset %d: EntityPixelX = %d, expected %d',
          [I, EntityPixelX(E), Expect]));
      Inc(PosBad);
    end;
  end;
  Log.Add(Format('position -> pixel over -4000..4000: %d disagreements', [PosBad]));
  Inc(Result, PosBad);

  { IsOffScreen's bounds are 320x240 with a margin of Margin*extent. }
  E.Raw[EF_EXTENT_X] := 16;
  E.Raw[EF_EXTENT_Y] := 16;
  E.Raw[EF_POS_Y] := POSITION_BIAS;
  E.Raw[EF_POS_X] := POSITION_BIAS + 160 * 32;
  if IsOffScreen(E, 1) then
  begin
    Log.Add('  FAILED: an entity at x=160 is not off screen');
    Inc(Result);
  end;
  E.Raw[EF_POS_X] := POSITION_BIAS + (SCREEN_W + 17) * 32;
  if not IsOffScreen(E, 1) then
  begin
    Log.Add(Format('  FAILED: x=%d with extent 16 should be off screen',
      [SCREEN_W + 17]));
    Inc(Result);
  end;
  Log.Add('IsOffScreen: on-screen and past-the-margin cases both correct');
  Log.Add('');

  Log.Add(Format('entity pool: %d slots of %d bytes (SizeOf(TEntity) = %d), %d types',
    [ENTITY_COUNT, ENTITY_BYTES, SizeOf(TEntity), ENTITY_TYPE_COUNT]));

  Log.Add('');
  if Bad > 0 then
  begin
    Log.Add(Format('FAILED: %d problems', [Bad]));
    Result := 1;
  end
  else
    Log.Add('OK');
end;

{ --selftest-events <gamedir> : the per-stage event tables and dialogue.

  Load_Event_Scripts reads two files per stage, so this walks all 66 stages and
  reports what came back. Every line in the shipped data has exactly seven
  fields, so any line the loader skips is a decode failure rather than a quirk
  of the data. Opcode-5 events are additionally required to resolve to an index
  inside the progress block - if that ever fails, the reading of Entity_Destroy
  is wrong. }
function SelfTestEvents(Log: TStrings): Integer;
var
  GameDir: string;
  S: TEventScript;
  I, J, Total, Lines, Empty, Flags, Idx: Integer;
  Ev: TEventRecord;
  ByOpcode: array[0..15] of Integer;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');
  Log.Add('stage  events  dialogue');

  for I := 0 to High(ByOpcode) do
    ByOpcode[I] := 0;
  Total := 0; Lines := 0; Empty := 0; Flags := 0;

  S := TEventScript.Create;
  try
    for I := 0 to 65 do
    begin
      if S.Load(GameDir, I) = 0 then
        Inc(Empty);
      Inc(Total, S.Count);
      Inc(Lines, S.LineCount);
      Log.Add(Format('%5d  %6d  %8d', [I, S.Count, S.LineCount]));

      for J := 0 to S.Count - 1 do
      begin
        Ev := S[J];
        if (Ev.Opcode >= 0) and (Ev.Opcode <= High(ByOpcode)) then
          Inc(ByOpcode[Ev.Opcode]);
        if Ev.Opcode = EVOP_SET_PROGRESS then
        begin
          Idx := ProgressIndexOf(Ev.ParamB);
          if (Idx < 0) or (Idx >= PROGRESS_LENGTH) then
          begin
            Log.Add(Format('  stage %d event %d: opcode 5, ParamB=%s -> %d OUT OF RANGE',
              [I, J, Ev.ParamB, Idx]));
            Inc(Result);
          end
          else
            Inc(Flags);
        end;
      end;
    end;
  finally
    S.Free;
  end;

  Log.Add('');
  Log.Add(Format('%d events across 66 stages, %d dialogue lines, %d stages with none',
    [Total, Lines, Empty]));
  Log.Add('');
  Log.Add('opcode histogram:');
  for I := 0 to High(ByOpcode) do
    if ByOpcode[I] > 0 then
      Log.Add(Format('  %2d  x%d', [I, ByOpcode[I]]));
  Log.Add('');
  Log.Add(Format('opcode 5 events resolving to a valid progress flag: %d', [Flags]));
  Log.Add(Format('progress block: %d bytes from offset %d',
    [PROGRESS_LENGTH, PROGRESS_START]));

  { A test that passes when it loaded nothing is worse than no test: point it
    at the wrong directory and it would report OK having checked zero events.
    The shipped data has 692 events and 203 dialogue lines, so anything less
    than a full load is a failure, not an empty pass. }
  if Total = 0 then
  begin
    Log.Add('FAILED: no events loaded at all - wrong game directory?');
    Inc(Result);
  end
  else if (Total <> 692) or (Lines <> 203) then
  begin
    Log.Add(Format('FAILED: expected 692 events and 203 dialogue lines, got %d and %d',
      [Total, Lines]));
    Inc(Result);
  end;

  Log.Add('');
  if Result > 0 then
    Log.Add(Format('FAILED: %d problems', [Result]))
  else
    Log.Add('OK');
end;

{ --selftest-settings <gamedir> <scratchdir> : the 56-byte settings record.

  This one matters more than it looks. FormDestroy WRITES data\system.dat back
  on exit, so a wrong field mapping would not merely misread the file - it
  would corrupt the player's settings the first time the game is closed. A
  round trip is the only cheap way to know the layout is right.

  Loads the real file, saves into a scratch directory, and compares the two
  byte for byte. Nothing is written to the game directory. }
function SelfTestSettings(Log: TStrings): Integer;
var
  GameDir, Scratch, SrcName, DstName: string;
  A, B: TMemoryStream;
  I, Diff: Integer;
  PA, PB: PByte;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Scratch := IncludeTrailingPathDelimiter(ParamStr(3));

  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add(Format('scratch:  %s', [Scratch]));
  Log.Add('');

  if not LoadSettings(GameDir) then
  begin
    Log.Add('FAILED: could not load data\system.dat');
    Exit(1);
  end;

  Log.Add(Format('SizeOf(TGameSettings) = %d (must be 56)', [SizeOf(TGameSettings)]));
  Log.Add('');
  Log.Add(Format('  +00 CurrentStage   %d', [Settings.CurrentStage]));
  Log.Add(Format('  +04 GameLevel      %d', [Settings.GameLevel]));
  Log.Add(Format('  +08 KeyMap         %d, %d, %d, %d',
    [Settings.KeyMap[0], Settings.KeyMap[1], Settings.KeyMap[2], Settings.KeyMap[3]]));
  Log.Add(Format('  +18 SoftwareVsync  %d', [Settings.SoftwareVsyncFlag]));
  Log.Add(Format('  +19 WaitOn         %d', [Settings.WaitOnFlag]));
  Log.Add(Format('  +1A FullScreen     %d', [Settings.FullScreenFlag]));
  Log.Add(Format('  +1B DebugLog       %d', [Settings.DebugLogFlag]));
  Log.Add(Format('  +24 Volume         %d', [Settings.Volume]));
  Log.Add(Format('  +28 GallerySel     %d', [Settings.GallerySel]));
  Log.Add(Format('  +34 InputDevice    %d', [Settings.InputDevice]));
  Log.Add('');

  ForceDirectories(Scratch + 'data');
  if not SaveSettings(Scratch) then
  begin
    Log.Add('FAILED: could not write the scratch copy');
    Exit(1);
  end;

  SrcName := IncludeTrailingPathDelimiter(GameDir) + 'data' + PathDelim + 'system.dat';
  DstName := Scratch + 'data' + PathDelim + 'system.dat';
  A := TMemoryStream.Create;
  B := TMemoryStream.Create;
  try
    A.LoadFromFile(SrcName);
    B.LoadFromFile(DstName);
    Log.Add(Format('original %d bytes, round-tripped %d bytes', [A.Size, B.Size]));
    if A.Size <> B.Size then
    begin
      Log.Add('FAILED: sizes differ');
      Exit(1);
    end;
    Diff := 0;
    PA := PByte(A.Memory);
    PB := PByte(B.Memory);
    for I := 0 to A.Size - 1 do
      if PA[I] <> PB[I] then
      begin
        if Diff < 8 then
          Log.Add(Format('  byte +%.2X: original %.2X, round-tripped %.2X',
            [I, PA[I], PB[I]]));
        Inc(Diff);
      end;
    Log.Add(Format('%d differing bytes', [Diff]));
    if Diff > 0 then
      Result := 1;
  finally
    B.Free;
    A.Free;
  end;

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - load/save is byte-exact, so FormDestroy will not corrupt system.dat')
  else
    Log.Add('FAILED - do NOT let FormDestroy write settings until this passes');
end;

{ ---------------------------------------------------------------------------
  --selftest-script : the event mini-language.

  EventCommands.pas recovered its grammar from the shipped data rather than
  from the interpreter, so the only thing holding it up is that the structure
  checks out with no exceptions. This re-checks that from the Pascal side, and
  it is a genuine second opinion: tools/analyse_events.py reaches the same
  numbers from an independent splitter written straight from the file text.

  A grammar that were mis-split would not produce fixed arities, so any failure
  here means the reading is wrong, not that the data is odd.
  --------------------------------------------------------------------------- }

function SelfTestScript(Log: TStrings): Integer;
var
  GameDir: string;
  S: TEventScript;
  Ev: TEventRecord;
  Sp: TEventSpawn;
  Prog: TEventProgram;
  Cmd: TEventCommand;
  I, J, K, L: Integer;
  Records, Spawns, BadSpawn, Cmds, BadArity, Dialogue, BadDialogue, Lists: Integer;
  Negatives, N: Integer;
  Nones, Ids, Progs, ShapeMismatch, BadKindArity, BadGuard: Integer;
  PosChecked, PosMismatch, AStart, ALen, PosVal: Integer;
  GuardSeen: array[0..PROGRESS_LENGTH - 1] of Boolean;
  DistinctGuards: Integer;
  Kind: TParamBKind;
  MinType, MaxType: Integer;
  SubOpUse: array[0..99] of Integer;
  Kinds: string;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');

  Records := 0; Spawns := 0; BadSpawn := 0; Cmds := 0; BadArity := 0;
  Dialogue := 0; BadDialogue := 0; Lists := 0; Negatives := 0;
  Nones := 0; Ids := 0; Progs := 0; ShapeMismatch := 0; BadKindArity := 0;
  BadGuard := 0; DistinctGuards := 0; PosChecked := 0; PosMismatch := 0;
  for I := 0 to PROGRESS_LENGTH - 1 do
    GuardSeen[I] := False;
  MinType := MaxInt; MaxType := -1;
  Kinds := '';
  for I := 0 to High(SubOpUse) do
    SubOpUse[I] := 0;

  S := TEventScript.Create;
  try
    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for J := 0 to S.Count - 1 do
      begin
        Ev := S[J];
        Inc(Records);

        { --- ParamA: the thing the event places --- }
        Sp := ParseSpawn(Ev.ParamA);
        if not Sp.Valid then
        begin
          Log.Add(Format('  stage %d event %d: ParamA does not parse: %s',
            [I, J, Ev.ParamA]));
          Inc(BadSpawn);
        end
        else
        begin
          Inc(Spawns);
          if Sp.TypeId < MinType then MinType := Sp.TypeId;
          if Sp.TypeId > MaxType then MaxType := Sp.TypeId;
          if (Sp.TypeId < 0) or (Sp.TypeId >= ENTITY_TYPE_COUNT) then
          begin
            Log.Add(Format('  stage %d event %d: type %d outside ENTITY_TYPES',
              [I, J, Sp.TypeId]));
            Inc(BadSpawn);
          end;
          if Pos(Sp.Kind, Kinds) = 0 then
            Kinds := Kinds + Sp.Kind;
          for K := 0 to Sp.ArgCount - 1 do
            if Sp.Args[K] < 0 then
              Inc(Negatives);

          { The kind letter fixes the argument count: * 0, A 1, / J R 2, M 3. }
          if not CheckSpawnArity(Sp) then
          begin
            Log.Add(Format('  stage %d event %d: kind %s takes %d args, got %d: %s',
              [I, J, Sp.Kind, KindArity(Sp.Kind), Sp.ArgCount, Sp.Raw]));
            Inc(BadKindArity);
          end;
        end;

        { --- ParamB: a program, a bare id, or nothing --- }
        Kind := ClassifyParamB(Ev.ParamB);
        case Kind of
          pbNone:    Inc(Nones);
          pbId:      Inc(Ids);
          pbProgram: Inc(Progs);
        end;

        { The shape must be the one the opcode implies. This is the check that
          would have caught reading a bare id like '1048' as a command. }
        if (Kind = pbProgram) <> (OpcodeExpects(Ev.Opcode) = pbProgram) then
        begin
          Log.Add(Format('  stage %d event %d: opcode %d implies %s but ParamB is %s: %s',
            [I, J, Ev.Opcode,
             GetEnumName(TypeInfo(TParamBKind), Ord(OpcodeExpects(Ev.Opcode))),
             GetEnumName(TypeInfo(TParamBKind), Ord(Kind)), Ev.ParamB]));
          Inc(ShapeMismatch);
        end;

        Prog := ParseProgram(Ev.ParamB);
        for K := 0 to High(Prog) do
          for L := 0 to High(Prog[K].Alternatives) do
          begin
            Cmd := Prog[K].Alternatives[L];
            Inc(Cmds);
            if (Cmd.SubOp >= 0) and (Cmd.SubOp <= High(SubOpUse)) then
              Inc(SubOpUse[Cmd.SubOp]);

            for N := 0 to Cmd.ArgCount - 1 do
              if Cmd.Args[N] < 0 then
                Inc(Negatives);

            { The leading number is a progress-flag guard, so it must index the
              progress block - EventScript_AdvanceStep reads Progress[it]. }
            if (Cmd.Guard < 0) or (Cmd.Guard >= PROGRESS_LENGTH) then
            begin
              Log.Add(Format('  stage %d event %d: guard %d outside the progress block: %s',
                [I, J, Cmd.Guard, Cmd.Raw]));
              Inc(BadGuard);
            end
            else if not GuardSeen[Cmd.Guard] then
            begin
              GuardSeen[Cmd.Guard] := True;
              Inc(DistinctGuards);
            end;

            if not CheckArity(Cmd) then
            begin
              Log.Add(Format('  stage %d event %d: sub-op %d has %d args: %s',
                [I, J, Cmd.SubOp, Cmd.ArgCount, Cmd.Raw]));
              Inc(BadArity);
            end;

            if Cmd.SubOp = SUBOP_LIST then
              Inc(Lists);

            { Read the SAME alternative the way EventScript_Execute does - fixed
              character positions - and require it to agree with the dash split.
              The two strategies are independent, so agreement over the whole
              data set is what says the field boundaries are right. }
            for N := 0 to Cmd.ArgCount - 1 do
              if ArgPosition(Cmd.SubOp, N, AStart, ALen) then
              begin
                Inc(PosChecked);
                PosVal := StrToIntDef(Trim(Copy(Cmd.Raw, AStart, ALen)), MaxInt);
                if PosVal <> Cmd.Args[N] then
                begin
                  Log.Add(Format('  stage %d event %d: sub-op %d arg %d - split says %d,'
                    + ' position %d..%d says %d: %s',
                    [I, J, Cmd.SubOp, N, Cmd.Args[N], AStart, AStart + ALen - 1,
                     PosVal, Cmd.Raw]));
                  Inc(PosMismatch);
                end;
              end;

            { Sub-op 3's argument must index this stage's own dialogue file.
              This is the check that ties the grammar to a second file. }
            if Cmd.SubOp = SUBOP_DIALOGUE then
            begin
              Inc(Dialogue);
              if (Cmd.Args[0] < 0) or (Cmd.Args[0] >= S.LineCount) then
              begin
                Log.Add(Format('  stage %d event %d: dialogue %d but tk%.3d has %d lines',
                  [I, J, Cmd.Args[0], I, S.LineCount]));
                Inc(BadDialogue);
              end;
            end;
          end;
      end;
    end;
  finally
    S.Free;
  end;

  Log.Add(Format('records parsed:      %d', [Records]));
  Log.Add(Format('ParamA spawns:       %d  (%d rejected)', [Spawns, BadSpawn]));
  Log.Add(Format('  type range:        %d..%d  of ENTITY_TYPES 0..%d',
    [MinType, MaxType, ENTITY_TYPE_COUNT - 1]));
  Log.Add(Format('  kind letters:      %s  (%d with a wrong argument count)',
    [Kinds, BadKindArity]));
  Log.Add(Format('ParamB shapes:       %d none / %d bare id / %d program  (%d disagree with the opcode)',
    [Nones, Ids, Progs, ShapeMismatch]));
  Log.Add(Format('ParamB alternatives: %d  (%d with a wrong argument count)',
    [Cmds, BadArity]));
  Log.Add(Format('  sub-op 3 refs:     %d  (%d outside the stage dialogue)',
    [Dialogue, BadDialogue]));
  Log.Add(Format('  sub-op 15 lists:   %d  (count field matched every time)', [Lists]));
  Log.Add(Format('  guards:            %d distinct, all inside the %d-byte progress block (%d outside)',
    [DistinctGuards, PROGRESS_LENGTH, BadGuard]));
  Log.Add(Format('  dash-split vs the interpreter''s fixed positions: %d args compared, %d disagree',
    [PosChecked, PosMismatch]));
  Log.Add(Format('negative arguments:  %d', [Negatives]));
  Log.Add('');
  Log.Add('sub-opcode histogram:');
  for I := 0 to High(SubOpUse) do
    if SubOpUse[I] > 0 then
      Log.Add(Format('  %2d  x%-4d arity %d', [I, SubOpUse[I], SUBOP_ARITY[I]]));
  Log.Add('');

  Inc(Result, BadSpawn + BadArity + BadDialogue + ShapeMismatch + BadKindArity
              + BadGuard + PosMismatch);

  { Same trap as --selftest-events: an empty load must not pass. These are the
    counts in the shipped data. }
  if Records <> 692 then
  begin
    Log.Add(Format('FAILED: expected 692 records, got %d - wrong game directory?',
      [Records]));
    Inc(Result);
  end
  else if (Spawns <> 692) or (Cmds = 0) or (Dialogue <> 149) or (Lists <> 13) then
  begin
    Log.Add(Format('FAILED: expected 692 spawns / 149 dialogue refs / 13 lists,'
      + ' got %d / %d / %d', [Spawns, Dialogue, Lists]));
    Inc(Result);
  end
  { The signed-field split is the one fragile part of the grammar: '-' is both
    the separator and the minus sign, and an earlier version of ParseFields
    dropped the sign, turning -4 into 4. Nothing above would have noticed - the
    arity and range checks all still passed. The shipped data holds exactly 22
    negative arguments, so pinning that count is what makes the bug visible. }
  else if Negatives <> 22 then
  begin
    Log.Add(Format('FAILED: expected 22 negative arguments, got %d'
      + ' - ParseFields is losing or inventing minus signs', [Negatives]));
    Inc(Result);
  end
  else if PosChecked <> 988 then
  begin
    Log.Add(Format('FAILED: expected 988 positional args compared, got %d',
      [PosChecked]));
    Inc(Result);
  end
  else if DistinctGuards <> 23 then
  begin
    Log.Add(Format('FAILED: expected 23 distinct guards, got %d', [DistinctGuards]));
    Inc(Result);
  end
  else if (Nones <> 104) or (Ids <> 281) or (Progs <> 307) then
  begin
    Log.Add(Format('FAILED: expected 104 none / 281 id / 307 program, got %d / %d / %d',
      [Nones, Ids, Progs]));
    Inc(Result);
  end;

  if Result = 0 then
    Log.Add('OK - grammar holds over every record with no exceptions')
  else
    Log.Add('FAILED - the grammar in EventCommands.pas is wrong somewhere');
end;

{ ---------------------------------------------------------------------------
  --selftest-stages : the stage table.

  Most of stage.dat's 16 columns are constant across all 66 rows, so the useful
  thing to check is not "does it load" but "do the relationships still hold" -
  csv0 = csv1, csv2 = row number, csv15 = csv0 except at row 58, and the seven
  dead columns still dead. Those are what Stages.pas's header claims, and this
  is what stops the claims rotting.

  It also checks the flush fit that makes the row-number reading credible: 65
  map files for rows 1..65, with row 0 the placeholder.
  --------------------------------------------------------------------------- }

function SelfTestStages(Log: TStrings): Integer;
var
  GameDir: string;
  T: TStageTable;
  R: TStageRecord;
  I, C, N: Integer;
  SurfEqSpr, MapEqRow, ThemeEqSurf, MapsPresent: Integer;
  DeadOK: Boolean;
  Anomalies: string;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');

  T := TStageTable.Create;
  try
    N := T.Load(GameDir);
    Log.Add(Format('rows loaded: %d', [N]));
    if N <> 66 then
    begin
      Log.Add('FAILED: expected 66 rows - wrong game directory?');
      Log.Add('');
      Log.Add('FAILED');
      Exit(1);
    end;

    SurfEqSpr := 0; MapEqRow := 0; ThemeEqSurf := 0; MapsPresent := 0;
    DeadOK := True;
    Anomalies := '';

    for I := 0 to N - 1 do
    begin
      R := T[I];
      if R.Raw[0] = R.Raw[1] then Inc(SurfEqSpr);
      if R.Raw[18] = R.Raw[0] then Inc(ThemeEqSurf)
      else
        Anomalies := Anomalies + Format(' row %d (art %d, theme %d)',
          [I, R.Raw[0], R.Raw[18]]);

      if I = 0 then
      begin
        { The placeholder row: no map, and csv5 is -1 rather than 6. }
        if (R.Raw[2] = LAYER_NONE) and (R.Raw[5] = LAYER_NONE) then
          Inc(MapEqRow);
      end
      else
      begin
        if R.Raw[2] = I then Inc(MapEqRow);
        if FileExists(IncludeTrailingPathDelimiter(GameDir) + 'map' + PathDelim +
                      Format('%.3d.map', [R.Raw[2]])) then
          Inc(MapsPresent);
      end;

      { csv 8..14 land in rec[11..17] and are zero throughout. }
      for C := 11 to 17 do
        if R.Raw[C] <> 0 then
          DeadOK := False;

      { csv 3,4,6,7 are -1 throughout. }
      if (R.Raw[3] <> LAYER_NONE) or (R.Raw[4] <> LAYER_NONE) or
         (R.Raw[6] <> LAYER_NONE) or (R.Raw[7] <> LAYER_NONE) then
        DeadOK := False;
    end;

    Log.Add(Format('csv0 = csv1 (art set is one field):     %d of %d', [SurfEqSpr, N]));
    Log.Add(Format('csv2 = row number (row 0 = no map):     %d of %d', [MapEqRow, N]));
    Log.Add(Format('map file present for rows 1..65:        %d of %d', [MapsPresent, N - 1]));
    Log.Add(Format('csv15 = csv0:                           %d of %d', [ThemeEqSurf, N]));
    if Anomalies <> '' then
      Log.Add('  differing:' + Anomalies);
    Log.Add(Format('csv3/4/6/7 all -1 and csv8..14 all 0:   %s',
      [BoolToStr(DeadOK, 'yes', 'NO')]));
    Log.Add('');

    if SurfEqSpr <> N then
    begin
      Log.Add('FAILED: surface set and sprite set are not always equal');
      Inc(Result);
    end;
    if MapEqRow <> N then
    begin
      Log.Add('FAILED: csv2 is not the row number');
      Inc(Result);
    end;
    if MapsPresent <> N - 1 then
    begin
      Log.Add(Format('FAILED: %d of %d map files missing',
        [N - 1 - MapsPresent, N - 1]));
      Inc(Result);
    end;
    { 65 of 66, the exception being row 58. Pinned exactly: if this ever became
      66 the field would be redundant, and if it dropped further the reading of
      it as a near-shadow of the art set would be wrong. }
    if ThemeEqSurf <> 65 then
    begin
      Log.Add(Format('FAILED: expected csv15 to equal csv0 on exactly 65 rows, got %d',
        [ThemeEqSurf]));
      Inc(Result);
    end;
    if not DeadOK then
    begin
      Log.Add('FAILED: a column documented as constant is not');
      Inc(Result);
    end;
  finally
    T.Free;
  end;

  if Result = 0 then
    Log.Add('OK - every documented relationship in Stages.pas still holds')
  else
    Log.Add('FAILED - Stages.pas describes the data wrongly');
end;

function RunSelfTest: Integer;
var
  Log: TStringList;
begin
  Result := 0;
  Log := TStringList.Create;
  try
    try
      if ParamStr(1) = '--selftest-audio' then
        Result := SelfTestAudio(Log)
      else if ParamStr(1) = '--selftest-midi' then
        Result := SelfTestMidi(Log)
      else if ParamStr(1) = '--playtest' then
        Result := PlayTest(Log)
      else if ParamStr(1) = '--mixdump' then
        Result := MixDump(Log)
      else if ParamStr(1) = '--selftest-dir' then
        Result := SelfTestDirections(Log)
      else if ParamStr(1) = '--selftest-events' then
        Result := SelfTestEvents(Log)
      else if ParamStr(1) = '--selftest-settings' then
        Result := SelfTestSettings(Log)
      else if ParamStr(1) = '--selftest-script' then
        Result := SelfTestScript(Log)
      else if ParamStr(1) = '--selftest-stages' then
        Result := SelfTestStages(Log)
      else
        Result := SelfTestArchive(Log);
    except
      on E: Exception do
      begin
        Log.Add(Format('FAILED: %s: %s', [E.ClassName, E.Message]));
        Result := 1;
      end;
    end;
  finally
    Log.SaveToFile(ExtractFilePath(ParamStr(0)) + 'selftest.log');
    Log.Free;
  end;
end;

begin
  if (ParamStr(1) = '--selftest') or (ParamStr(1) = '--selftest-audio') or
     (ParamStr(1) = '--selftest-midi') or (ParamStr(1) = '--playtest') or
     (ParamStr(1) = '--mixdump') or (ParamStr(1) = '--selftest-dir') or
     (ParamStr(1) = '--selftest-events') or
     (ParamStr(1) = '--selftest-settings') or
     (ParamStr(1) = '--selftest-script') or
     (ParamStr(1) = '--selftest-stages') then
  begin
    ExitCode := RunSelfTest;
    Exit;
  end;

  Application.Initialize;
  Application.Title := 'Akuji the Demon';
  Application.CreateForm(TFrm_main, Frm_main);
  Application.Run;
end.
