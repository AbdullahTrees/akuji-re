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
  Stages, Camera, TileMaps, Player, EntityHandlers,
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
  T: TEntityType;
  PosBad, Expect, ColBad, Kind0, Kind1, Kind2: Integer;
  EdgeBad, EdgeChecked, Cam, Ext, PosI, ED, Edge, Saved: Integer;
  LT: TLayerInfo;
  EE: TEntity;
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
  { --- the type table's decoded columns -------------------------------------

    Entity_Spawn copies column 5 to EF_SCREEN_SPACE and column 10 to
    EF_CULL_OFFSCREEN, and Entity_UpdateAll uses both as booleans - one gates
    adding the layer scroll, the other gates off-screen culling. If either ever
    held a value other than 0 or 1 the reading would be wrong, so check it.

    Column 7 is never copied by Entity_Spawn at all. It is zero throughout the
    shipped table, and those two facts are what make it a dead column rather
    than an undiscovered field. }
  ColBad := 0;
  Kind0 := 0; Kind1 := 0; Kind2 := 0;
  for I := 0 to ENTITY_TYPE_COUNT - 1 do
  begin
    T := EntityType(I);
    if (T.Raw[TYPE_COL_SCREEN_SPACE] < 0) or (T.Raw[TYPE_COL_SCREEN_SPACE] > 1) then
    begin
      Log.Add(Format('  type %d: column 5 is %d, expected a boolean',
        [I, T.Raw[TYPE_COL_SCREEN_SPACE]]));
      Inc(ColBad);
    end;
    if (T.Raw[TYPE_COL_CULL_OFFSCREEN] < 0) or (T.Raw[TYPE_COL_CULL_OFFSCREEN] > 1) then
    begin
      Log.Add(Format('  type %d: column 10 is %d, expected a boolean',
        [I, T.Raw[TYPE_COL_CULL_OFFSCREEN]]));
      Inc(ColBad);
    end;
    if T.Raw[TYPE_COL_UNUSED] <> 0 then
    begin
      Log.Add(Format('  type %d: column 7 is %d, but nothing ever reads it',
        [I, T.Raw[TYPE_COL_UNUSED]]));
      Inc(ColBad);
    end;
  end;
  Log.Add(Format('type table: cols 5 and 10 boolean, col 7 dead - %d violations over %d types',
    [ColBad, ENTITY_TYPE_COUNT]));
  Inc(Result, ColBad);

  { --- column 15 is EF_SOLID ---------------------------------------------
    Entity_Spawn's mapping puts column 15 at int $3E, and Entity_SolidCollideX
    and ...Y read that as a solidity KIND: 1 blocks the player in Y only,
    2 in X only, 3 or more in both. If that reading is right the shipped table
    should be almost all zeroes with a handful of level furniture, which is
    exactly what it is - and nothing should be 3 or more, because the game has
    no entity that blocks both ways. }
  ColBad := 0;
  Kind0 := 0; Kind1 := 0; Kind2 := 0;
  for I := 0 to ENTITY_TYPE_COUNT - 1 do
  begin
    T := EntityType(I);
    case T.Raw[TYPE_COL_SOLID] of
      0: Inc(Kind0);
      1: Inc(Kind1);
      2: Inc(Kind2);
    else
      Log.Add(Format('  type %d: solidity kind %d - the game has no such case',
        [I, T.Raw[TYPE_COL_SOLID]]));
      Inc(ColBad);
    end;
  end;
  Log.Add(Format('type table col 15 (EF_SOLID): %d inert, %d floor-only, %d wall-only',
    [Kind0, Kind1, Kind2]));
  Inc(Result, ColBad);
  if (Kind0 <> 76) or (Kind1 <> 4) or (Kind2 <> 1) then
  begin
    Log.Add(Format('FAILED: expected 76 / 4 / 1, got %d / %d / %d',
      [Kind0, Kind1, Kind2]));
    Inc(Result);
  end;


  { --- TileEdgeDistX/Y land flush on a tile boundary ------------------------

    The claim is that the returned distance puts the box edge EXACTLY on a tile
    edge - that is the whole purpose of the function, and it is checkable
    without knowing anything else about the map:

      moving left,  the box's left edge ends on a multiple of the tile width
      moving right, its right edge ends on the last pixel of a tile

    Swept over a range of positions, extents and camera offsets. Also checks
    the sign (left is never positive, right never negative) and the range
    (never a whole tile or more), and the bias-cancellation claim in the
    header - shifting the position by a whole number of tiles must not change
    the answer, which is why the missing POSITION_BIAS subtraction is harmless. }
  EdgeBad := 0; EdgeChecked := 0;
  FillChar(LT, SizeOf(LT), 0);
  LT.TileW := 32; LT.TileH := 32;
  LT.MapTilesX := 100; LT.MapTilesY := 100;
  FillChar(EE, SizeOf(EE), 0);
  for Cam := 0 to 40 do
  begin
    LT.OriginX := Cam * 32;
    LT.OriginY := Cam * 32;
    for Ext := 0 to 40 do
    begin
      EE.Raw[EF_EXTENT_X] := Ext;
      EE.Raw[EF_EXTENT_Y] := Ext;
      for PosI := 0 to 40 do
      begin
        EE.Raw[EF_POS_X] := POSITION_BIAS + (PosI * 7) * 32;
        EE.Raw[EF_POS_Y] := POSITION_BIAS + (PosI * 7) * 32;

        ED := TileEdgeDistX(EE, LT, -1);
        Inc(EdgeChecked);
        if ED > 0 then Inc(EdgeBad);
        if -ED >= LT.TileW * 32 then Inc(EdgeBad);
        Edge := OriginPixel(EE.Raw[EF_POS_X]) - (EE.Raw[EF_EXTENT_X] div 2)
                + EE.Raw[EF_BOX_OFS_X] + EE.Raw[EF_TILE_OFS_X]
                + (OriginPixel(LT.OriginX) mod LT.TileW) + ED div 32;
        if Edge mod LT.TileW <> 0 then
        begin
          Inc(EdgeBad);
          if EdgeBad <= 3 then
            Log.Add(Format('  left: cam %d ext %d pos %d -> edge %d, not on a'
              + ' %d boundary', [Cam, Ext, PosI * 7, Edge, LT.TileW]));
        end;

        ED := TileEdgeDistX(EE, LT, 1);
        Inc(EdgeChecked);
        if ED < 0 then Inc(EdgeBad);
        if ED >= LT.TileW * 32 then Inc(EdgeBad);
        { The -1 is the function's own: it measures the right edge as the LAST
          pixel inside the box, not the first outside it. Leaving it out of
          this reference made every right-move case "fail" while the function
          was correct. }
        Edge := OriginPixel(EE.Raw[EF_POS_X]) + (EE.Raw[EF_EXTENT_X] div 2)
                - EE.Raw[EF_BOX_OFS_X] + EE.Raw[EF_TILE_OFS_X]
                + (OriginPixel(LT.OriginX) mod LT.TileW) - 1 + ED div 32;
        if Edge mod LT.TileW <> LT.TileW - 1 then
        begin
          Inc(EdgeBad);
          if EdgeBad <= 3 then
            Log.Add(Format('  right: cam %d ext %d pos %d -> edge %d, not the'
              + ' last pixel of a tile', [Cam, Ext, PosI * 7, Edge]));
        end;

        { the Y twin must agree with the X one on identical inputs }
        if TileEdgeDistY(EE, LT, -1) <> TileEdgeDistX(EE, LT, -1) then
          Inc(EdgeBad);
        if TileEdgeDistY(EE, LT, 1) <> TileEdgeDistX(EE, LT, 1) then
          Inc(EdgeBad);

        { bias cancellation: a whole number of tiles changes nothing }
        Saved := EE.Raw[EF_POS_X];
        EE.Raw[EF_POS_X] := Saved + 64 * LT.TileW * 32;
        if TileEdgeDistX(EE, LT, -1) <> ED - ED then ;    { keep ED live }
        if TileEdgeDistX(EE, LT, 1) <> ED then
        begin
          Inc(EdgeBad);
          if EdgeBad <= 3 then
            Log.Add('  shifting the position by 64 tiles changed the answer');
        end;
        EE.Raw[EF_POS_X] := Saved;
      end;
    end;
  end;
  Log.Add(Format('TileEdgeDist lands flush on a tile edge: %d cases, %d violations',
    [EdgeChecked, EdgeBad]));
  Inc(Result, EdgeBad);
  if EdgeChecked <> 41 * 41 * 41 * 2 then
  begin
    Log.Add('FAILED: the edge-distance sweep did not run');
    Inc(Result);
  end;

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
  SelfBlock, AlwaysOK, Always, BadCond, MaxTileX, MaxTileY: Integer;
  Pickup, PickupNoId, PlainWithId, TouchKind, TypeId: Integer;
  Ev: TEventRecord;
  ByOpcode: array[0..15] of Integer;
  ByDifficulty: array[0..2] of Integer;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');
  Log.Add('stage  events  dialogue');

  for I := 0 to High(ByOpcode) do
    ByOpcode[I] := 0;
  Total := 0; Lines := 0; Empty := 0; Flags := 0;
  SelfBlock := 0; AlwaysOK := 0; Always := 0; BadCond := 0;
  Pickup := 0; PickupNoId := 0; PlainWithId := 0;
  MaxTileX := 0; MaxTileY := 0;
  for I := 0 to 2 do ByDifficulty[I] := 0;

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
          begin
            Inc(Flags);
            { The flag an opcode-5 event sets is its own BlockedBy, so picking
              the thing up is what stops it ever coming back. If this ever
              stops holding, either the field scatter or the reading of
              csv 1/csv 2 as spawn conditions is wrong. }
            if Idx = Ev.BlockedBy then
              Inc(SelfBlock);
          end;
        end;

        { Opcode 4 is spawned regardless of the camera and started at once.
          All nine are the same construction - see EventScripts.pas. }
        if Ev.Opcode = EVOP_ALWAYS then
        begin
          Inc(Always);
          if (Ev.NeedsFlag = 0) and (Ev.BlockedBy <> 0) and
             (Ev.TileX = 1) and (Ev.TileY = 1) then
            Inc(AlwaysOK);
        end;

        { Both conditions index the progress block, or are 0 for "no
          condition". Anything else would be writing outside the save. }
        if (Ev.NeedsFlag < 0) or (Ev.NeedsFlag >= PROGRESS_LENGTH) or
           (Ev.BlockedBy < 0) or (Ev.BlockedBy >= PROGRESS_LENGTH) then
          Inc(BadCond);

        { Difficulty is published as Progress[10] / [5] / [6] for levels
          0 / 1 / 2 by Game_StartOrLoad. }
        if Ev.NeedsFlag = 10 then Inc(ByDifficulty[0]);
        if Ev.NeedsFlag = 5  then Inc(ByDifficulty[1]);
        if Ev.NeedsFlag = 6  then Inc(ByDifficulty[2]);

        { Opcode 9's ParamB is read by the touch handler of the entity it
          places, not by anything that looks at the opcode. Kinds 2 and 5 parse
          it as a progress flag; every other kind never touches it - and would
          raise on '*' if it did. So the partition has to be exact. }
        if Ev.Opcode = 9 then
        begin
          TypeId := StrToIntDef(Copy(Ev.ParamA, 1, 4), -1);
          TouchKind := -1;
          if (TypeId >= 0) and (TypeId < ENTITY_TYPE_COUNT) then
            TouchKind := ENTITY_TYPES[TypeId].Raw[3];
          if (TouchKind = 2) or (TouchKind = 5) then
          begin
            Inc(Pickup);
            if ClassifyParamB(Ev.ParamB) <> pbId then
              Inc(PickupNoId);
          end
          else if ClassifyParamB(Ev.ParamB) = pbId then
            Inc(PlainWithId);
        end;

        if Ev.TileX > MaxTileX then MaxTileX := Ev.TileX;
        if Ev.TileY > MaxTileY then MaxTileY := Ev.TileY;
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
  Log.Add(Format('  ... whose flag is also their own BlockedBy:        %d', [SelfBlock]));
  Log.Add(Format('opcode 4 events: %d, of the documented shape: %d', [Always, AlwaysOK]));
  Log.Add(Format('spawn conditions outside the progress block:       %d', [BadCond]));
  Log.Add(Format('records gated on difficulty 0 / 1 / 2:  %d / %d / %d',
    [ByDifficulty[0], ByDifficulty[1], ByDifficulty[2]]));
  Log.Add(Format('largest event tile: %d, %d', [MaxTileX, MaxTileY]));
  Log.Add(Format('opcode 9 placing a touch-kind 2 or 5 type: %d, of which %d'
    + ' carry no flag id', [Pickup, PickupNoId]));
  Log.Add(Format('opcode 9 carrying a flag id for any other kind: %d', [PlainWithId]));
  Log.Add(Format('progress block: %d bytes from offset %d',
    [PROGRESS_LENGTH, PROGRESS_START]));
  Inc(Result, BadCond);

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

  { These three are what make csv 1 and csv 2 a decode rather than a guess.
    Each is an ALL-or-nothing pattern over the shipped data: 154 of 154, and
    9 of 9. A wrong field scatter, or the two conditions swapped, breaks them
    immediately. }
  if SelfBlock <> Flags then
  begin
    Log.Add(Format('FAILED: %d of %d opcode-5 events set a flag other than their'
      + ' own BlockedBy', [Flags - SelfBlock, Flags]));
    Inc(Result);
  end;
  if (Always <> 9) or (AlwaysOK <> Always) then
  begin
    Log.Add(Format('FAILED: expected 9 opcode-4 events all of the documented'
      + ' shape, got %d of which %d match', [Always, AlwaysOK]));
    Inc(Result);
  end;
  { A collectible with no flag would raise on StrToInt('*'); a non-collectible
    with one would mean something else reads it. Neither happens. }
  if (Pickup <> 127) or (PickupNoId <> 0) or (PlainWithId <> 0) then
  begin
    Log.Add(Format('FAILED: expected 127 opcode-9 collectibles all carrying a'
      + ' flag and nothing else carrying one, got %d / %d missing / %d extra',
      [Pickup, PickupNoId, PlainWithId]));
    Inc(Result);
  end;
  if (ByDifficulty[0] <> 5) or (ByDifficulty[1] <> 23) or (ByDifficulty[2] <> 40) then
  begin
    Log.Add(Format('FAILED: expected 5 / 23 / 40 difficulty-gated records, got'
      + ' %d / %d / %d',
      [ByDifficulty[0], ByDifficulty[1], ByDifficulty[2]]));
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
  SpawnPosChecked, SpawnPosMismatch: Integer;
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
  SpawnPosChecked := 0; SpawnPosMismatch := 0;
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

          { The same trick as for ParamB below: read each argument a SECOND
            way, at the fixed character positions Events_SpawnNearCamera copies
            from, and require the two to agree. The positions differ per letter
            - 8/13 for '/', 8/10/15 for M, 8/11 for R - so a mis-split grammar
            could not agree across all six. }
          for K := 0 to Sp.ArgCount - 1 do
            if SpawnArgPosition(Sp.Kind, K, AStart, ALen) then
            begin
              Inc(SpawnPosChecked);
              PosVal := StrToIntDef(Trim(Copy(Sp.Raw, AStart, ALen)), MaxInt);
              if PosVal <> Sp.Args[K] then
              begin
                Log.Add(Format('  stage %d event %d: ParamA kind %s arg %d -'
                  + ' split says %d, position %d..%d says %d: %s',
                  [I, J, Sp.Kind, K, Sp.Args[K], AStart, AStart + ALen - 1,
                   PosVal, Sp.Raw]));
                Inc(SpawnPosMismatch);
              end;
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
  Log.Add(Format('ParamA the same way, against Events_SpawnNearCamera: %d args compared, %d disagree',
    [SpawnPosChecked, SpawnPosMismatch]));
  Log.Add(Format('negative arguments:  %d', [Negatives]));
  Log.Add('');
  Log.Add('sub-opcode histogram:');
  for I := 0 to High(SubOpUse) do
    if SubOpUse[I] > 0 then
      Log.Add(Format('  %2d  x%-4d arity %d', [I, SubOpUse[I], SUBOP_ARITY[I]]));
  Log.Add('');

  Inc(Result, BadSpawn + BadArity + BadDialogue + ShapeMismatch + BadKindArity
              + BadGuard + PosMismatch + SpawnPosMismatch);

  { Same trap as --selftest-events: an empty load must not pass. These are the
    counts in the shipped data. }
  if Records <> 692 then
  begin
    Log.Add(Format('FAILED: expected 692 records, got %d - wrong game directory?',
      [Records]));
    Inc(Result);
  end
  else if SpawnPosChecked <> 419 then
  begin
    { 13 '/' x2 + 245 'A' x1 + 38 'M' x3 + 15 'R' x2 + 2 'J' x2 = 419. Pinned
      so that a SpawnArgPosition which quietly returned False for everything
      could not make the comparison vacuous. }
    Log.Add(Format('FAILED: expected 419 ParamA positional args compared, got %d',
      [SpawnPosChecked]));
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
  M: TTileMap;
  I, C, N, MaxTile, With29, Safe29, Terr, Tile, TX, TY, Bad: Integer;
  Has29: Boolean;
  SurfEqSpr, MapEqRow, ThemeEqSurf, MapsPresent, Terrain3, Terrain4: Integer;
  LayerBad: Integer;
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
    Terrain3 := 0; Terrain4 := 0; LayerBad := 0;
    DeadOK := True;
    Anomalies := '';

    for I := 0 to N - 1 do
    begin
      R := T[I];
      if R.Raw[0] = R.Raw[1] then Inc(SurfEqSpr);
      { rec[5] is the tileset surface slot for layer 0, and Load_Stage_Assets
        passes it to Terrain_Configure as well. Layers 1 and 2 are unused, so
        their map index AND their tileset are both -1 - the two triples have to
        agree or the reading of csv 5..7 as tilesets is wrong. }
      for C := 1 to STAGE_LAYERS - 1 do
        if (R.Raw[2 + C] = LAYER_NONE) <> (R.Raw[STAGE_TILESET + C] = LAYER_NONE) then
        begin
          Log.Add(Format('  row %d layer %d: map %d but tileset %d - they disagree',
            [I, C, R.Raw[2 + C], R.Raw[STAGE_TILESET + C]]));
          Inc(LayerBad);
        end;
      if (I > 0) and (R.Raw[STAGE_TILESET] <> 6) then
      begin
        Log.Add(Format('  row %d: layer 0 tileset is %d, expected surface slot 6',
          [I, R.Raw[STAGE_TILESET]]));
        Inc(LayerBad);
      end;

      if R.Raw[18] = 3 then Inc(Terrain3);
      if R.Raw[18] = 4 then Inc(Terrain4);
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
    { The two terrain values Entity_SpawnDebris actually branches on. If these
      counts move, the reading of csv 15 as a terrain id needs revisiting. }
    Log.Add(Format('terrain 3 (water01) / terrain 4 (water02): %d / %d stages',
      [Terrain3, Terrain4]));
    Log.Add(Format('csv 5..7 tilesets agree with csv 2..4 maps:  %d violations',
      [LayerBad]));
    Inc(Result, LayerBad);
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
    if (Terrain3 <> 10) or (Terrain4 <> 13) then
    begin
      Log.Add(Format('FAILED: expected 10 stages of terrain 3 and 13 of terrain 4,'
        + ' got %d and %d', [Terrain3, Terrain4]));
      Inc(Result);
    end;
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

  { --- The terrain tables, against every shipped map ------------------------

    Terrain_Configure sets two globals per terrain: the solid-tile threshold
    and the kill tile. Three things follow, and all three are properties of the
    DATA, so they can fail:

      * every tile id in every map is inside the tileset, 0..99 - which is what
        makes the terrain-9 kill tile of 1000 mean "no instant death" rather
        than "tile 1000"
      * 29 is below every threshold, so the kill tile is always walk-into. It
        has to be, or nothing could reach it
      * tile 29 appears in exactly 7 maps, and the one where it is NOT lethal
        is the one terrain-9 stage }
  Bad := 0; MaxTile := -1; With29 := 0; Safe29 := 0;
  M := TTileMap.Create;
  try
    for I := 1 to 65 do
    begin
      if not M.Load(GameDir, I) then
        Continue;
      Has29 := False;
      for TY := 0 to M.MapHeight - 1 do
        for TX := 0 to M.MapWidth - 1 do
        begin
          Tile := M[TX, TY];
          if Tile > MaxTile then MaxTile := Tile;
          if Tile >= M.SheetCols * M.SheetRows then
          begin
            Inc(Bad);
            if Bad <= 3 then
              Log.Add(Format('  map %.3d: tile %d at %d,%d is outside the %dx%d sheet',
                [I, Tile, TX, TY, M.SheetCols, M.SheetRows]));
          end;
          if Tile = KILL_TILE then Has29 := True;
        end;
      if Has29 then
      begin
        Inc(With29);
        Terr := T[I].Raw[18];
        if (Terr >= 0) and (Terr <= TERRAIN_MAX) and
           (TERRAIN_KILL_TILE[Terr] <> KILL_TILE) then
          Inc(Safe29);
      end;
    end;
  finally
    M.Free;
  end;

  Log.Add('');
  Log.Add(Format('largest tile id in any map: %d  (tilesets are %d tiles)',
    [MaxTile, TILESET_IDS]));
  Log.Add(Format('tiles outside their own tileset:        %d', [Bad]));
  Log.Add(Format('maps containing the kill tile %d:       %d, of which %d are'
    + ' in a terrain where it is harmless', [KILL_TILE, With29, Safe29]));
  Inc(Result, Bad);

  if MaxTile >= KILL_TILE_NONE then
  begin
    Log.Add(Format('FAILED: a tile id of %d exists, so terrain 9''s kill tile'
      + ' of %d is not out of range after all', [MaxTile, KILL_TILE_NONE]));
    Inc(Result);
  end;
  for I := 1 to TERRAIN_MAX do
    if KILL_TILE >= TERRAIN_SOLID_THRESHOLD[I] then
    begin
      Log.Add(Format('FAILED: terrain %d makes tile %d solid, so nothing could'
        + ' ever walk into it', [I, KILL_TILE]));
      Inc(Result);
    end;
  if (With29 <> 7) or (Safe29 <> 1) then
  begin
    Log.Add(Format('FAILED: expected the kill tile in 7 maps with exactly 1'
      + ' harmless, got %d and %d', [With29, Safe29]));
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

{ ---------------------------------------------------------------------------
  --selftest-player <gamedir> : the camera, the player's tables, and the two
  small helpers the whole movement path shares.

  Four independent things, none checkable by "does it load":

  1. THE SCROLL CLAMP against the real maps. Camera.pas claims the layer stops
     at (MapTiles - 10) * TileW horizontally and (MapTiles - 7.5) * TileH
     vertically. If that is right it equals MapPixels - ScreenSize EXACTLY on
     every map, with no slack. All 65 shipped maps are checked. Rounding 7.5 to
     7 or 8, or swapping the tile width for the height, fails at once.

  2. THE DEAD ZONE, swept over every pixel of the screen and both signs of
     velocity against a plain restatement of the rule, plus a clamp check so
     that a version which had lost the bounds test entirely cannot pass.

     The four boundary numbers below are written out as LITERALS on purpose.
     They were Camera.DEADZONE_* at first, and that version passed happily with
     DEADZONE_RIGHT moved from 177 to 176 - the comparison was against the same
     constant it was meant to be checking, so it could only ever catch a change
     in the logic, never in the numbers. Do not tidy these back into the
     constants.

  3. ApproachZero and RectOverlap. ApproachZero is swept for the property that
     matters - never cross zero, never grow, always move - and RectOverlap
     against brute force over a grid of boxes, with a control so that a
     predicate which is simply always true cannot pass.

  4. THE SPRITE TABLES: six of them, contiguous, and in the base set the
     right-facing sprite is the left-facing one plus ten.
  --------------------------------------------------------------------------- }

function SelfTestPlayer(Log: TStrings): Integer;
var
  GameDir: string;
  M: TTileMap;
  L: TLayerInfo;
  P: TPlayerState;
  I, J, K, V, Step, Before, Bad, Checked: Integer;
  Want, Got, Overlaps, SndId: Integer;
  Nm: string;
  Exe: TMemoryStream;
  ExeName: string;
  Table: array of Integer;
  A, B: Entities.TBox;
  RefOverlap, GotOverlap, Scroll, RefScroll: Boolean;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');

  { --- 1. the scroll clamp, against every shipped map --------------------- }
  Bad := 0; Checked := 0;
  M := TTileMap.Create;
  try
    for I := 1 to 65 do
    begin
      if not M.Load(GameDir, I) then
        Continue;
      Inc(Checked);
      FillChar(L, SizeOf(L), 0);
      L.TileW := M.TileWidth;    L.TileH := M.TileHeight;
      L.MapTilesX := M.MapWidth; L.MapTilesY := M.MapHeight;

      Want := M.MapWidth * M.TileWidth - SCREEN_W;
      Got := Camera.MaxScrollX(L);
      if Got <> Want then
      begin
        Inc(Bad);
        if Bad <= 5 then
          Log.Add(Format('  map %.3d: max scroll X %d, expected %d',
            [I, Got, Want]));
      end;
      Want := M.MapHeight * M.TileHeight - SCREEN_H;
      Got := Camera.MaxScrollY(L);
      if Got <> Want then
      begin
        Inc(Bad);
        if Bad <= 5 then
          Log.Add(Format('  map %.3d: max scroll Y %d, expected %d',
            [I, Got, Want]));
      end;
    end;
  finally
    M.Free;
  end;
  Log.Add(Format('scroll clamp = map size - screen size:   %d maps, %d mismatches',
    [Checked, Bad]));
  Inc(Result, Bad);
  if Checked <> 65 then
  begin
    Log.Add(Format('FAILED: expected 65 maps, read %d - wrong game directory?',
      [Checked]));
    Inc(Result);
  end;

  { --- 2. the dead zone ---------------------------------------------------
    A map big enough that the bounds check never fires, so this isolates the
    zone itself. }
  FillChar(L, SizeOf(L), 0);
  L.TileW := 32; L.TileH := 32; L.MapTilesX := 1000; L.MapTilesY := 1000;
  L.OriginX := 200 * 32; L.OriginY := 200 * 32;
  Bad := 0;
  for I := 0 to SCREEN_W - 1 do
    for J := 0 to 1 do
    begin
      V := 32 - 64 * J;
      Scroll := Camera.ShouldScrollX(L, I, V);
      RefScroll := ((I < 144) and (V < 0)) or ((I >= 177) and (V > 0));
      if Scroll <> RefScroll then Inc(Bad);
    end;
  for I := 0 to SCREEN_H - 1 do
    for J := 0 to 1 do
    begin
      V := 32 - 64 * J;
      Scroll := Camera.ShouldScrollY(L, I, V);
      RefScroll := ((I < 104) and (V < 0)) or ((I >= 137) and (V > 0));
      if Scroll <> RefScroll then Inc(Bad);
    end;
  Log.Add(Format('dead zone over every screen pixel:      %d disagreements',
    [Bad]));
  Inc(Result, Bad);

  Bad := 0;
  for I := 0 to SCREEN_W - 1 do
    if Camera.ShouldScrollX(L, I, 0) then Inc(Bad);
  for I := 0 to SCREEN_H - 1 do
    if Camera.ShouldScrollY(L, I, 0) then Inc(Bad);
  Log.Add(Format('a still entity never scrolls:           %d violations', [Bad]));
  Inc(Result, Bad);

  L.OriginX := Camera.MaxScrollX(L) shl POSITION_SHIFT;
  L.OriginY := Camera.MaxScrollY(L) shl POSITION_SHIFT;
  if Camera.ShouldScrollX(L, SCREEN_W - 1, 32) or
     Camera.ShouldScrollY(L, SCREEN_H - 1, 32) then
  begin
    Log.Add('FAILED: the layer scrolls past the edge of the map');
    Inc(Result);
  end
  else
    Log.Add('the clamp stops the layer at the map edge: yes');

  { --- 3a. ApproachZero --------------------------------------------------- }
  Bad := 0; Checked := 0;
  for V := -600 to 600 do
    for Step := 1 to 16 do
    begin
      Before := V;
      I := V;
      Entities.ApproachZero(I, Step);
      Inc(Checked);
      if (Before > 0) and ((I < 0) or (I > Before)) then Inc(Bad);
      if (Before < 0) and ((I > 0) or (I < Before)) then Inc(Bad);
      if (Before = 0) and (I <> 0) then Inc(Bad);
      if Abs(I) > Abs(Before) then Inc(Bad);
      if (Before <> 0) and (I = Before) then Inc(Bad);
    end;
  Log.Add(Format('ApproachZero over %d cases:          %d violations',
    [Checked, Bad]));
  Inc(Result, Bad);

  { --- 3b. RectOverlap against brute force -------------------------------- }
  Bad := 0; Checked := 0; Overlaps := 0;
  for I := 0 to 19 do
    for J := 0 to 19 do
      for K := 0 to 3 do
      begin
        A.L := 0;  A.T := 0;  A.R := 10 + K;  A.B := 10 + K;
        B.L := I - 10; B.T := J - 10; B.R := B.L + 8; B.B := B.T + 8;
        RefOverlap := (A.L < B.R) and (B.L < A.R) and
                      (A.T < B.B) and (B.T < A.B);
        GotOverlap := Entities.RectOverlap(A, B, 0, 0);
        Inc(Checked);
        if GotOverlap <> RefOverlap then Inc(Bad);
        if RefOverlap then Inc(Overlaps);
      end;
  Log.Add(Format('RectOverlap over %d box pairs:       %d disagreements, %d overlapping',
    [Checked, Bad, Overlaps]));
  Inc(Result, Bad);
  if (Overlaps = 0) or (Overlaps = Checked) then
  begin
    Log.Add('FAILED: the box grid is degenerate - the comparison proves nothing');
    Inc(Result);
  end;

  { --- 4. the sprite tables, read back out of akuji.exe --------------------
    Writing the addresses out and checking they tile end to end proves nothing:
    the compiler folds constant arithmetic, and an earlier version of this
    check emitted "unreachable code" warnings for every branch because it had
    already decided the answer. The claim is about the BINARY, so the binary is
    what has to be read.

    One contiguous run of 20 dwords at 0x0046BB9C covers all six tables. If any
    address, stride, or the right-then-left order were wrong, the values would
    not line up. }
  Bad := 0;
  Exe := TMemoryStream.Create;
  try
    ExeName := IncludeTrailingPathDelimiter(GameDir) + 'akuji.exe';
    if not FileExists(ExeName) then
    begin
      Log.Add('FAILED: akuji.exe is not in the game directory');
      Inc(Result);
    end
    else
    begin
      Exe.LoadFromFile(ExeName);
      SetLength(Table, 20);
      Exe.Position := PLAYER_SPRITE_BASE - DATA_VA_BIAS;
      Exe.ReadBuffer(Table[0], 20 * SizeOf(Integer));

      for I := 0 to 4 do
      begin
        if Table[I]      <> SPR_GROUND[0][I] then Inc(Bad);
        if Table[5 + I]  <> SPR_GROUND[1][I] then Inc(Bad);
        if Table[10 + I] <> SPR_AIR[0][I]    then Inc(Bad);
        if Table[15 + I] <> SPR_AIR[1][I]    then Inc(Bad);
      end;
      Log.Add(Format('sprite tables match akuji.exe at 0x%.6X:   %d of 20 wrong',
        [PLAYER_SPRITE_BASE, Bad]));
      Inc(Result, Bad);

      { And the three later tables, at the addresses this file claims. }
      Bad := 0;
      SetLength(Table, 8);
      Exe.Position := $0046BBEC - DATA_VA_BIAS;
      Exe.ReadBuffer(Table[0], 8 * SizeOf(Integer));
      for I := 0 to 3 do
      begin
        if Table[I]     <> SPR_GLIDE[0][I] then Inc(Bad);
        if Table[4 + I] <> SPR_GLIDE[1][I] then Inc(Bad);
      end;
      SetLength(Table, 6);
      Exe.Position := $0046BC0C - DATA_VA_BIAS;
      Exe.ReadBuffer(Table[0], 6 * SizeOf(Integer));
      if (Table[0] <> SPR_AIRDASH[0][0]) or (Table[1] <> SPR_AIRDASH[0][1]) or
         (Table[2] <> SPR_AIRDASH[1][0]) or (Table[3] <> SPR_AIRDASH[1][1]) or
         (Table[4] <> SPR_KNOCKBACK[0])  or (Table[5] <> SPR_KNOCKBACK[1]) then
        Inc(Bad);
      Log.Add(Format('glide, air dash and knockback tables:      %d wrong', [Bad]));
      Inc(Result, Bad);

      { Type 14's item table, 16 variants x 4 frames, read back the same way. }
      Bad := 0;
      SetLength(Table, ITEM_VARIANTS * ITEM_FRAMES);
      Exe.Position := ITEM_SPRITE_TABLE_ADDR - DATA_VA_BIAS;
      Exe.ReadBuffer(Table[0], ITEM_VARIANTS * ITEM_FRAMES * SizeOf(Integer));
      for I := 0 to ITEM_VARIANTS - 1 do
        for J := 0 to ITEM_FRAMES - 1 do
          if Table[I * ITEM_FRAMES + J] <> ITEM_SPRITES[I][J] then
            Inc(Bad);
      Log.Add(Format('type 14 item table at 0x%.6X:            %d of %d wrong',
        [ITEM_SPRITE_TABLE_ADDR, Bad, ITEM_VARIANTS * ITEM_FRAMES]));
      Inc(Result, Bad);
    end;
  finally
    Exe.Free;
  end;

  { The +10 relation between the two facings of the base character set. It is
    what fixes the index order as right-then-left rather than the reverse. }
  Bad := 0;
  for I := 0 to 2 do
    if SPR_GROUND[0][I] - SPR_GROUND[1][I] <> SPRITE_FACING_STRIDE then Inc(Bad);
  for I := 0 to 4 do
    if SPR_AIR[0][I] - SPR_AIR[1][I] <> SPRITE_FACING_STRIDE then Inc(Bad);
  if SPR_KNOCKBACK[0] - SPR_KNOCKBACK[1] <> SPRITE_FACING_STRIDE then Inc(Bad);
  if SPR_DEATH[0] - SPR_DEATH[1] <> SPRITE_FACING_STRIDE then Inc(Bad);
  Log.Add(Format('right sprite = left + 10 in the base set: %d violations', [Bad]));
  Inc(Result, Bad);


  { --- every sound constant matches its recovered file name -----------------
    The numbers come from the call sites in Player_Update and
    Entity_UpdateDying; the names come from a static AnsiString array at
    0x00468D50 whose length was read off the unit finalisation. Two entirely
    separate recoveries, so requiring each constant to land on a plausibly-named
    file is a real cross-check rather than a restatement. }
  Bad := 0;
  for I := 0 to 12 do
  begin
    case I of
      0: begin SndId := SND_JUMP;        Nm := 'jump';    end;
      1: begin SndId := SND_LAND_HARD;   Nm := 'yuka';    end;
      2: begin SndId := SND_ATTACK;      Nm := 'shot';    end;
      3: begin SndId := SND_CHARGE_FULL; Nm := 'power';   end;
      4: begin SndId := SND_CHARGED;     Nm := 'shot';    end;
      5: begin SndId := SND_LAND_SOFT;   Nm := 'yuka';    end;
      6: begin SndId := SND_GLIDE;       Nm := 'pon';     end;
      7: begin SndId := SND_AIRDASH;     Nm := 'pon';     end;
      8: begin SndId := SND_DEATH;       Nm := 'voice';   end;
      9: begin SndId := SND_DASH_START;  Nm := 'puu';     end;
     10: begin SndId := SND_BOM03;       Nm := 'bom03';   end;
     11: begin SndId := 17;              Nm := 'hit01';   end;
    else begin SndId := $10;             Nm := 'get01';   end;
    end;
    if (SndId < 0) or (SndId >= SOUND_COUNT) or (Pos(Nm, SoundNames[SndId]) = 0) then
    begin
      Log.Add(Format('  sound %d is %s, expected a name containing "%s"',
        [SndId, SoundNames[SndId], Nm]));
      Inc(Bad);
    end;
  end;
  Log.Add(Format('sound constants match their recovered names: %d wrong of 13',
    [Bad]));
  Inc(Result, Bad);

  { --- 5. the shipped save ------------------------------------------------ }
  if LoadSave(P, IncludeTrailingPathDelimiter(GameDir) + 'data' + PathDelim +
              'save.dat') then
  begin
    Log.Add('');
    Log.Add(Format('save.dat: stage %d, lives %d/%d, %ds, weapon %d, jump %d',
      [P.SavedStage, P.Lives, P.MaxLives, P.ElapsedSec, P.Weapon,
       P.JumpStrength]));
    Log.Add(Format('  abilities: dash %d, wall kick %d, air dash %d, glide %d',
      [P.Head[ABILITY_DASH], P.Head[ABILITY_WALLKICK],
       P.Head[ABILITY_AIRDASH], P.Head[ABILITY_GLIDE]]));
    { Pinned exactly. The claim is that these four bytes are the abilities and
      that the shipped save is early enough to have only the first. If the file
      is ever replaced these numbers change and the reading has to be redone
      rather than quietly adjusted. }
    if (P.Head[ABILITY_DASH] <> 1) or (P.Head[ABILITY_WALLKICK] <> 0) or
       (P.Head[ABILITY_AIRDASH] <> 0) or (P.Head[ABILITY_GLIDE] <> 0) then
    begin
      Log.Add('FAILED: the shipped save no longer has exactly the dash unlocked');
      Inc(Result);
    end;
    if P.Progress[0] <> 1 then
    begin
      Log.Add('FAILED: progress flag 0 is not set - guard 0000 is not always true');
      Inc(Result);
    end;
    if P.Lives > P.MaxLives then
    begin
      Log.Add('FAILED: lives exceed the maximum');
      Inc(Result);
    end;
    if P.JumpStrength < DEFAULT_FIELD11D0 then
    begin
      Log.Add('FAILED: jump strength is below the starting value');
      Inc(Result);
    end;
  end
  else
  begin
    Log.Add('FAILED: could not read the shipped save');
    Inc(Result);
  end;

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - the camera, the helpers and the player tables all hold')
  else
    Log.Add('FAILED');
end;

{ ---------------------------------------------------------------------------
  --selftest-trace : run the player controller over a scripted input sequence
  and check the result against numbers derived from the constants.

  This is the first check of BEHAVIOUR rather than of data, and it is worth
  being clear about what it can and cannot show. It cannot show that the
  reconstruction matches akuji.exe - only a differential run against the
  original can do that, and it does not exist yet. What it does is:

    * fix the controller against silent drift, by pinning a trace
    * check the movement numbers against arithmetic done independently of the
      code: walking is AxisX shl 5 = 32 sub-pixels = exactly 1 pixel a frame,
      the dash is shl 6 so exactly 2, a jump leaves at -JumpStrength and gains
      PLAYER_GRAVITY a frame so its apex is JumpStrength div 4 frames up
    * and be the SHAPE the differential test needs: same start state, same
      input script, a trace to diff

  The world is flat and empty: floor at pixel 200, a wall at pixel 300, no
  solids, no sound. Deterministic - RandomBelow is a counter, not Random - so
  the trace is reproducible.
  --------------------------------------------------------------------------- }

type
  TFlatWorld = class(TPlayerWorld)
  public
    FloorY, WallX, Nonce: Integer;
    Sounds: string;
    Spawns: Integer;
    function TileAtX(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer; override;
    function TileAtY(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer; override;
    function EdgeDistX(const E: TEntity; Delta: Integer): Integer; override;
    function EdgeDistY(const E: TEntity; Delta: Integer): Integer; override;
    function SolidCollideX(const E: TEntity; Delta: Integer; SkipSoft: Boolean): Boolean; override;
    function SolidCollideY(const E: TEntity; Delta: Integer; SkipSoft: Boolean): Boolean; override;
    function Spawn(Kind, TypeId, X, Y: Integer): Integer; override;
    { Not used by the trace, but left abstract it would be a runtime
      abstract-method error the first time a handler destroyed something. }
    procedure DestroyEntity(var E: TEntity; DropLoot: Boolean); override;
    procedure SetSpawnField(Slot, IntIndex, Value: Integer); override;
    procedure SpawnDebris(const E: TEntity; Kind: Integer); override;
    procedure PlaySound(Id: Integer); override;
    function RandomBelow(N: Integer): Integer; override;
  end;

procedure TFlatWorld.DestroyEntity(var E: TEntity; DropLoot: Boolean);
begin
  E.Raw[EF_ALIVE] := 0;
end;

function TFlatWorld.TileAtX(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer;
begin
  if EntityPixelX(E) + Delta div 32 >= WallX then
    Result := SolidThreshold
  else
    Result := 0;
end;

function TFlatWorld.TileAtY(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer;
begin
  if EntityPixelY(E) + Delta div 32 >= FloorY then
    Result := SolidThreshold
  else
    Result := 0;
end;

function TFlatWorld.EdgeDistX(const E: TEntity; Delta: Integer): Integer;
begin
  Result := (WallX - 1 - EntityPixelX(E)) * 32;
  if Result < 0 then Result := 0;
  if Result > Delta then Result := Delta;
end;

function TFlatWorld.EdgeDistY(const E: TEntity; Delta: Integer): Integer;
begin
  Result := (FloorY - 1 - EntityPixelY(E)) * 32;
  if Result < 0 then Result := 0;
  if Result > Delta then Result := Delta;
end;

function TFlatWorld.SolidCollideX(const E: TEntity; Delta: Integer; SkipSoft: Boolean): Boolean;
begin
  Result := False;
end;

function TFlatWorld.SolidCollideY(const E: TEntity; Delta: Integer; SkipSoft: Boolean): Boolean;
begin
  OnTopOfSolid := False;
  Result := False;
end;

function TFlatWorld.Spawn(Kind, TypeId, X, Y: Integer): Integer;
begin
  Inc(Spawns);
  Result := 0;
end;

procedure TFlatWorld.SetSpawnField(Slot, IntIndex, Value: Integer);
begin
end;

procedure TFlatWorld.SpawnDebris(const E: TEntity; Kind: Integer);
begin
  Inc(Spawns);
end;

procedure TFlatWorld.PlaySound(Id: Integer);
begin
  Sounds := Sounds + IntToStr(Id) + ' ';
end;

function TFlatWorld.RandomBelow(N: Integer): Integer;
begin
  { Not Random: the trace has to be reproducible. }
  Nonce := (Nonce + 7) mod N;
  Result := Nonce;
end;

function SelfTestTrace(Log: TStrings): Integer;
var
  W: TFlatWorld;
  E: TEntity;
  P: TPlayerState;
  L: TLayerInfo;
  Inp: TInputState;
  Down: array[0..3] of Boolean;
  I, F, StartX, Apex, ApexFrame, Landed, DashVX, StopFrame: Integer;
  Trace, Trace2: string;

  procedure StepIn(AGameState, AxisX, AxisY: Integer; Jump, Attack: Boolean);
  begin
    Inp.AxisX := AxisX;
    Inp.AxisY := AxisY;
    Inp.Button[0] := Jump;
    Inp.Button[1] := Attack;
    Down[0] := Jump; Down[1] := Attack; Down[2] := False; Down[3] := False;
    PlayerUpdate(E, P, L, Inp, W, AGameState);
    InputEndOfFrame(Inp, Down);
  end;

  procedure Step(AxisX, AxisY: Integer; Jump, Attack: Boolean);
  begin
    StepIn(GS_PLAY, AxisX, AxisY, Jump, Attack);
  end;

  { Reset SETTLES for three frames before handing back, and that is not
    padding. An entity placed on the ground has PF_LANDED = 0, so its first
    update runs the whole just-landed sequence: soft landing sound, state 3,
    velocity zeroed. That is the original's behaviour and it is correct - but
    it means frame 1 is never a normal frame, and a jump pressed on frame 1 has
    its edge eaten by a state the controller will not jump out of. Measuring
    from frame 1 is how the first version of this test produced four wrong
    failures. }
  procedure Reset;
  var
    K: Integer;
  begin
    FillChar(E, SizeOf(E), 0);
    FillChar(Inp, SizeOf(Inp), 0);
    E.Raw[EF_ALIVE] := 1;
    E.Raw[EF_TYPE] := 1;
    E.Raw[EF_EXTENT_X] := 16;
    E.Raw[EF_EXTENT_Y] := 16;
    E.Raw[EF_POS_X] := POSITION_BIAS + 100 * 32;
    E.Raw[EF_POS_Y] := POSITION_BIAS + 199 * 32;
    E.Raw[PF_STATE] := PS_GROUND;
    for K := 1 to 3 do
      Step(0, 0, False, False);
    W.Sounds := '';
    W.Spawns := 0;
  end;

begin
  Result := 0;
  W := TFlatWorld.Create;
  try
    W.FloorY := 200;
    W.WallX := 300;
    W.SolidThreshold := $32;
    W.Fading := False;

    FillChar(P, SizeOf(P), 0);
    P.JumpStrength := DEFAULT_FIELD11D0;      { 0x68 = 104 }
    P.MaxLives := 3;
    P.Lives := 3;
    P.Weapon := 0;

    { A SINGLE-SCREEN room: 10 x 7 tiles. Both max-scroll values then come out
      at or below zero, so ShouldScroll* can never fire and the entity really
      moves. That matters more than it sounds - the first version of this test
      used a 1000-tile map, and the player hung in mid-air at pixel 155 with
      its velocity climbing, because everything past the dead zone was being
      applied to the LAYER. The floor here is defined in entity-pixel space,
      which does not move when the layer does, so it was unreachable.

      A test world is either single-screen, or it has to model tiles in world
      space. This one is single-screen; 5a below widens it deliberately. }
    FillChar(L, SizeOf(L), 0);
    L.TileW := 32; L.TileH := 32;
    L.MapTilesX := 10; L.MapTilesY := 7;

    { --- 1. standing still ------------------------------------------------ }
    Reset;
    for I := 1 to 20 do Step(0, 0, False, False);
    Log.Add(Format('idle 20 frames:   state %d, x %d, y %d, vy %d',
      [E.Raw[PF_STATE], EntityPixelX(E), EntityPixelY(E), E.Raw[EF_VEL_Y]]));
    if (E.Raw[EF_VEL_Y] <> 0) or (EntityPixelX(E) <> 100) then
    begin
      Log.Add('FAILED: standing still does not stand still');
      Inc(Result);
    end;

    { --- 2. walking: AxisX shl 5 is 32 sub-pixels, exactly one pixel ------- }
    Reset;
    StartX := EntityPixelX(E);
    for I := 1 to 10 do Step(1, 0, False, False);
    Log.Add(Format('walk right 10:    x %d -> %d  (expected +10)',
      [StartX, EntityPixelX(E)]));
    if EntityPixelX(E) - StartX <> 10 then
    begin
      Log.Add(Format('FAILED: walking moved %d pixels in 10 frames, expected 10',
        [EntityPixelX(E) - StartX]));
      Inc(Result);
    end;

    { --- 3. the double tap ------------------------------------------------- }
    Reset;
    Step(1, 0, False, False);          { first tap opens the window }
    Step(0, 0, False, False);
    Step(1, 0, False, False);          { second tap, but the ability is LOCKED }
    Step(1, 0, False, False);
    Log.Add(Format('double tap, ability locked:   state %d (expected %d)',
      [E.Raw[PF_STATE], PS_GROUND]));
    if E.Raw[PF_STATE] <> PS_GROUND then
    begin
      Log.Add('FAILED: dashed without the ability unlocked');
      Inc(Result);
    end;

    Reset;
    P.Head[ABILITY_DASH] := 1;
    Step(1, 0, False, False);
    Step(0, 0, False, False);
    Step(1, 0, False, False);          { the dash STARTS here ... }
    Step(1, 0, False, False);          { ... and reaches its speed here }
    DashVX := E.Raw[EF_VEL_X];
    Log.Add(Format('double tap, ability unlocked: state %d, vx %d (expected %d, %d)',
      [E.Raw[PF_STATE], DashVX, PS_DASH, 1 shl PLAYER_DASH_SHIFT]));
    if (E.Raw[PF_STATE] <> PS_DASH) or (DashVX <> 1 shl PLAYER_DASH_SHIFT) then
    begin
      Log.Add('FAILED: the double tap did not start a dash at twice walking speed');
      Inc(Result);
    end;
    P.Head[ABILITY_DASH] := 0;

    { --- 4. a jump, from the constants -------------------------------------
      Leaves at -JumpStrength and gains PLAYER_GRAVITY a frame, so it is still
      rising for JumpStrength div PLAYER_GRAVITY frames. }
    Reset;
    Apex := 999; ApexFrame := 0; Landed := 0; StopFrame := 0;
    Trace := ''; Trace2 := '';
    for F := 1 to 90 do
    begin
      Step(0, 0, F <= 40, False);      { hold jump for 40 frames }
      if EntityPixelY(E) < Apex then
      begin
        Apex := EntityPixelY(E);
        ApexFrame := F;
      end;
      if (StopFrame = 0) and (E.Raw[EF_VEL_Y] >= 0) then
        StopFrame := F;
      if (Landed = 0) and (F > 3) and (E.Raw[PF_STATE] = PS_LANDING) then
        Landed := F;
      if F <= 6 then
        Trace := Trace + Format('%d:%d/%d ', [F, EntityPixelY(E), E.Raw[EF_VEL_Y]]);
      if (F >= 50) and (F <= 56) then
        Trace2 := Trace2 + Format('%d:%d/%d/s%d ',
          [F, EntityPixelY(E), E.Raw[EF_VEL_Y], E.Raw[PF_STATE]]);
    end;
    Log.Add('jump trace y/vy:  ' + Trace);
    Log.Add('landing 50..56:   ' + Trace2);
    Log.Add(Format('jump:             apex %d px up, vy hit 0 at frame %d,'
      + ' landed frame %d', [199 - Apex, StopFrame, Landed]));
    Log.Add(Format('  sounds:         %s', [W.Sounds]));
    { The apex is asserted on the VELOCITY, not on the pixel position. Velocity
      is in 1/32 pixel, so the last few frames of a rise move less than a whole
      pixel and the pixel minimum is reached several frames before vy crosses
      zero - which is exactly what the pixel version of this check reported. }
    { JumpStrength div PLAYER_GRAVITY frames of gravity, PLUS the launch frame.
      The jump impulse is applied in the GROUNDED branch, and gravity only in
      the airborne one, so the frame that leaves the ground gets the impulse
      and no gravity. Hence 26 + 1. Getting this wrong is how the check first
      read, and the +1 is a fact about the original's ordering, not a fudge. }
    if StopFrame <> P.JumpStrength div PLAYER_GRAVITY + 1 then
    begin
      Log.Add(Format('FAILED: vy reached 0 at frame %d, but -%d rising at +%d'
        + ' a frame, plus the launch frame, takes %d',
        [StopFrame, P.JumpStrength, PLAYER_GRAVITY,
         P.JumpStrength div PLAYER_GRAVITY + 1]));
      Inc(Result);
    end;
    if Landed = 0 then
    begin
      Log.Add('FAILED: the jump never landed');
      Inc(Result);
    end;
    if Pos(IntToStr(SND_JUMP) + ' ', W.Sounds) <> 1 then
    begin
      Log.Add('FAILED: the jump did not play the jump sound first');
      Inc(Result);
    end;

    { --- 5a. the dead zone stops the PLAYER, not the world -----------------
      On a big map, walking right past pixel 177 scrolls the layer instead of
      moving the entity, so the player's own position stops there. That is the
      camera doing its job, and it is worth pinning because it looks like a bug
      the first time you see it. }
    L.MapTilesX := 1000;
    L.OriginX := 0;
    Reset;
    for I := 1 to 400 do Step(1, 0, False, False);
    Log.Add(Format('walk right on a big map: x %d, layer origin %d px'
      + '  (dead zone at %d)',
      [EntityPixelX(E), L.OriginX div 32, Camera.DEADZONE_RIGHT]));
    if EntityPixelX(E) <> Camera.DEADZONE_RIGHT then
    begin
      Log.Add(Format('FAILED: expected the player to stop at the dead zone'
        + ' edge %d, got %d', [Camera.DEADZONE_RIGHT, EntityPixelX(E)]));
      Inc(Result);
    end;
    if L.OriginX <= 0 then
    begin
      Log.Add('FAILED: the player stopped but the layer never scrolled');
      Inc(Result);
    end;

    { --- 5b. and on a map too small to scroll, it reaches the wall --------- }
    L.MapTilesX := 10;
    L.OriginX := 0;
    Reset;
    for I := 1 to 400 do Step(1, 0, False, False);
    Log.Add(Format('walk into the wall:      x %d (wall at %d)',
      [EntityPixelX(E), W.WallX]));
    if EntityPixelX(E) >= W.WallX then
    begin
      Log.Add('FAILED: walked through the wall');
      Inc(Result);
    end;
    if EntityPixelX(E) <> W.WallX - 1 then
    begin
      Log.Add(Format('FAILED: stopped at %d, not flush against the wall at %d',
        [EntityPixelX(E), W.WallX - 1]));
      Inc(Result);
    end;
    { --- 6. the glide, and the bug it carries -------------------------------
      Entering needs Up, no horizontal input, having jumped, and the ability.
      Once in, the ORIGINAL's vertical clamp writes the horizontal velocity -
      see Player.pas. This checks the state is reached, not that the bug is
      pleasant. }
    Reset;
    P.Head[ABILITY_GLIDE] := 1;
    Step(0, 0, True, False);                    { jump }
    for I := 1 to 4 do Step(0, 0, True, False);
    Step(0, -1, False, False);                  { Up in the air }
    Log.Add(Format('glide entry:      state %d (expected %d)',
      [E.Raw[PF_STATE], PS_SPECIAL1]));
    if E.Raw[PF_STATE] <> PS_SPECIAL1 then
    begin
      Log.Add('FAILED: Up in the air with the glide unlocked did not glide');
      Inc(Result);
    end;

    { The same input WITHOUT the ability must do nothing - otherwise the
      ability gate is not being read at all. }
    Reset;
    P.Head[ABILITY_GLIDE] := 0;
    Step(0, 0, True, False);
    for I := 1 to 4 do Step(0, 0, True, False);
    Step(0, -1, False, False);
    Log.Add(Format('glide entry, locked: state %d (expected %d)',
      [E.Raw[PF_STATE], PS_AIRBORNE]));
    if E.Raw[PF_STATE] = PS_SPECIAL1 then
    begin
      Log.Add('FAILED: glided without the ability unlocked');
      Inc(Result);
    end;

    { --- 7. the GS_PLAY guard -------------------------------------------
      Player_Update returns straight after the clock unless GameState is 60.
      This check exists because the guard was MISSING from the first version of
      Player.pas - the audit against a fresh decompile found it, and without a
      test it could go missing again. The clock must still run; nothing else
      may. }
    Reset;
    StartX := EntityPixelX(E);
    F := P.ElapsedSec * 60 + P.Field11C0;
    for I := 1 to 120 do
      StepIn(GS_PAUSE, 1, 0, True, True);
    Log.Add('');
    Log.Add(Format('120 frames while paused: x %d (was %d), state %d, clock +%d',
      [EntityPixelX(E), StartX, E.Raw[PF_STATE],
       (P.ElapsedSec * 60 + P.Field11C0) - F]));
    if EntityPixelX(E) <> StartX then
    begin
      Log.Add('FAILED: the player moved while the game was not in play');
      Inc(Result);
    end;
    if (P.ElapsedSec * 60 + P.Field11C0) - F <> 120 then
    begin
      Log.Add('FAILED: the play clock did not run while paused - it should');
      Inc(Result);
    end;

  finally
    W.Free;
  end;

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - the controller behaves as its own constants predict')
  else
    Log.Add('FAILED');
end;

{ ---------------------------------------------------------------------------
  --selftest-entities <gamedir> : Entity_UpdateAll.

  Three checks, and the first is the one that matters.

  1. HANDLER_ADDR against the BINARY. The switch is not a chain of compares -
     the compiler emitted `JMP [EAX*4 + 0x00460924]`, so akuji.exe carries an
     81-entry jump table naming every arm. This reads that table, follows each
     arm to its CALL, and compares the 78 resulting addresses against the ones
     transcribed into EntityHandlers.pas. A slip in any of 78 hand-copied
     addresses would be invisible any other way, and "types 0, 18 and 20 have no
     arm" stops being a claim and becomes a measurement: they are exactly the
     entries pointing at the default target.

  2. ScaleByPercent against exact arithmetic, with the exceptions named.

     Away from a tie - Half * Percent = 50 (mod 100) - the FPU's error is far
     too small to move the answer, so exact integer arithmetic is the reference.
     At a tie it decides, and it does not always land on round-half-even: over
     half-extents 0..1024 and percentages 0..100 it deviates in exactly SIXTY
     places, which X87_DEVIATIONS lists by value. Both the values and the COUNT
     are asserted, so an implementation that deviates anywhere else fails even
     if it gets these sixty right.

  3. The loop's own behaviour, driven through counting stubs. Entity_PlayerTouch
     and Entity_TakeProjectileHits are not translated yet, and the dispatcher
     calls them through nil-able procedure variables precisely so that a test
     can put counters there - which is what pins the slot boundary, the type-68
     special case and the mid-loop abandon without needing either function.
  --------------------------------------------------------------------------- }

type
  { A TTileSource over a shipped map, so the collision arithmetic can be swept
    against real data rather than against a fixture built to suit it. }
  TMapTiles = class(TTileSource)
  public
    Map: TTileMap;
    function TileAt(TileX, TileY: Integer): Integer; override;
  end;

  { And one over a grid the test writes, for the cases a real map has no reason
    to contain. Probes records every lookup so the SWEEP can be checked, not
    just its answer. }
  TGridTiles = class(TTileSource)
  public
    W, H: Integer;
    Cells: array[0..63, 0..63] of Integer;
    Probes: string;
    function TileAt(TileX, TileY: Integer): Integer; override;
  end;

  TStubSprites = class(TSpriteSink)
  public
    Vis:  array[0..15] of Boolean;
    Anim: array[0..15] of Integer;
    SW, SH: array[0..15] of Integer;   { what Width/Height will report }
    PX, PY, PZ: array[0..15] of Integer;
    procedure SetVisible(Handle: Integer; Visible: Boolean); override;
    function  GetVisible(Handle: Integer): Boolean; override;
    procedure SetAnim(Handle, AnimId: Integer); override;
    function  Width(Handle: Integer): Integer; override;
    function  Height(Handle: Integer): Integer; override;
    procedure SetPos(Handle, X, Y: Integer); override;
    procedure SetDepth(Handle, Depth: Integer); override;
  end;

  TCountingWorld = class(TEntityWorld)
  public
    Killed: Integer;
    Sounds: Integer;
    LastSound: Integer;
    { NOTE: Pool is NOT redeclared here. It lives on TEntityWorld, and
      declaring it again shadowed the base field - the double's Spawn used
      one and Entity_Destroy used the other, which was nil, so every
      cross-entity effect silently did nothing while the test still saw a
      pool. It does NOT override SpawnDebris or RandomBelow either: a double
      that overrides the thing under test only tests the double. }
    function TileAtX(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer; override;
    function TileAtY(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer; override;
    function EdgeDistX(const E: TEntity; Delta: Integer): Integer; override;
    function EdgeDistY(const E: TEntity; Delta: Integer): Integer; override;
    function SolidCollideX(const E: TEntity; Delta: Integer; SkipSoft: Boolean): Boolean; override;
    function SolidCollideY(const E: TEntity; Delta: Integer; SkipSoft: Boolean): Boolean; override;
    function Spawn(Kind, TypeId, X, Y: Integer): Integer; override;
    procedure DestroyEntity(var E: TEntity; DropLoot: Boolean); override;
    procedure SetSpawnField(Slot, IntIndex, Value: Integer); override;
    procedure PlaySound(Id: Integer); override;
  end;

function TMapTiles.TileAt(TileX, TileY: Integer): Integer;
begin
  Result := Map.TileAtRaw(TileX, TileY);
end;

function TGridTiles.TileAt(TileX, TileY: Integer): Integer;
begin
  Probes := Probes + Format('%d,%d ', [TileX, TileY]);
  if (TileX < 0) or (TileY < 0) or (TileX >= W) or (TileY >= H) then
    Exit(0);
  Result := Cells[TileX][TileY];
end;

procedure TStubSprites.SetVisible(Handle: Integer; Visible: Boolean);
begin Vis[Handle] := Visible; end;
function TStubSprites.GetVisible(Handle: Integer): Boolean;
begin Result := Vis[Handle]; end;
procedure TStubSprites.SetAnim(Handle, AnimId: Integer);
begin Anim[Handle] := AnimId; end;
function TStubSprites.Width(Handle: Integer): Integer;
begin Result := SW[Handle]; end;
function TStubSprites.Height(Handle: Integer): Integer;
begin Result := SH[Handle]; end;
procedure TStubSprites.SetPos(Handle, X, Y: Integer);
begin PX[Handle] := X; PY[Handle] := Y; end;
procedure TStubSprites.SetDepth(Handle, Depth: Integer);
begin PZ[Handle] := Depth; end;

function TCountingWorld.TileAtX(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer;
begin Result := 0; end;
function TCountingWorld.TileAtY(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer;
begin Result := 0; end;
function TCountingWorld.EdgeDistX(const E: TEntity; Delta: Integer): Integer;
begin Result := 0; end;
function TCountingWorld.EdgeDistY(const E: TEntity; Delta: Integer): Integer;
begin Result := 0; end;
function TCountingWorld.SolidCollideX(const E: TEntity; Delta: Integer; SkipSoft: Boolean): Boolean;
begin Result := False; end;
function TCountingWorld.SolidCollideY(const E: TEntity; Delta: Integer; SkipSoft: Boolean): Boolean;
begin Result := False; end;
function TCountingWorld.Spawn(Kind, TypeId, X, Y: Integer): Integer;
begin
  if Pool = nil then
    Exit(SLOT_NONE);
  Result := Pool.Spawn(Kind, TypeId, X, Y);
end;
procedure TCountingWorld.DestroyEntity(var E: TEntity; DropLoot: Boolean);
begin
  Inc(Killed);
  inherited DestroyEntity(E, DropLoot);
end;
procedure TCountingWorld.SetSpawnField(Slot, IntIndex, Value: Integer);
begin
  if Pool <> nil then
    Pool.SetField(Slot, IntIndex, Value);
end;
procedure TCountingWorld.PlaySound(Id: Integer);
begin
  Inc(Sounds);
  LastSound := Id;
end;
var
  { The dispatcher's two hooks are plain procedures, so their bookkeeping has to
    be global. TouchAbortAt is how the mid-loop abandon is provoked: the touch
    on that slot changes the game state, exactly as a touch that starts an event
    script would. }
  TouchCount, HitCount: Integer;
  TouchSlots: string;
  TouchAbortAt: Integer;
  EntityTestState: Integer;

procedure CountTouch(var E: TEntity; World: TEntityWorld);
begin
  Inc(TouchCount);
  TouchSlots := TouchSlots + Format('%d ', [E.Raw[EF_SLOT]]);
  if E.Raw[EF_SLOT] = TouchAbortAt then
    EntityTestState := GS_TITLE_INIT;
end;

procedure CountHit(var E: TEntity; World: TEntityWorld);
begin
  Inc(HitCount);
end;

{ (Half * Percent) / 100 rounded half to even, done in integers so that it
  cannot share a rounding mistake with the code under test. }
function ExactPercent(Half, Percent: Integer): Integer;
var
  N, Q, R: Int64;
begin
  N := Int64(Half) * Percent;
  Q := N div 100;
  R := N mod 100;
  if R > 50 then
    Inc(Q)
  else if R = 50 then
    if Odd(Q) then Inc(Q);
  Result := Integer(Q);
end;

const
  { (half, percent, result) at every point where the x87 sequence disagrees with
    exact round-half-even, over half-extents 0..1024 and percentages 0..100 -
    the whole domain, not just the twelve percentages the shipped table happens
    to use. Sixty places out of 103,525.

    These come from an exact rational simulation of FDIV/FMULP/FISTP at 64-bit
    significands, written separately from the Pascal. That is what makes this a
    check rather than a restatement of the code under test.

    They cluster: every one is a tie, half * percent = 50 (mod 100), and the
    runs restart at powers of two, which is the ulp structure showing through.
    Sweeping the FULL percentage range rather than the shipped twelve is
    deliberate - a mutation that mishandles the exactly-half-an-ulp case is
    invisible at the shipped percentages and shows up at 65. }
  X87_DEVIATIONS: array[0..59, 0..2] of Integer = (
    (  50,  59,   29), (  75,  42,   31), (  95,  30,   29),
    ( 150,  21,   31), ( 150,  53,   79), ( 175,  30,   53),
    ( 190,  15,   29), ( 190,  65,  123), ( 195,  30,   59),
    ( 325,  18,   59), ( 325,  66,  215), ( 325,  78,  253),
    ( 335,  30,  101), ( 350,  15,   53), ( 350,  53,  185),
    ( 350,  65,  227), ( 355,  30,  107), ( 375,  30,  113),
    ( 375,  54,  203), ( 390,  15,   59), ( 390,  65,  253),
    ( 395,  30,  119), ( 415,  30,  125), ( 475,  26,  123),
    ( 550,  53,  291), ( 625,  18,  113), ( 625,  66,  413),
    ( 625,  78,  487), ( 650,   9,   59), ( 650,  33,  215),
    ( 650,  39,  253), ( 650,  59,  383), ( 655,  30,  197),
    ( 670,  15,  101), ( 670,  65,  435), ( 675,  30,  203),
    ( 695,  30,  209), ( 710,  15,  107), ( 710,  65,  461),
    ( 715,  30,  215), ( 725,  66,  479), ( 735,  30,  221),
    ( 750,  15,  113), ( 750,  27,  203), ( 750,  53,  397),
    ( 750,  65,  487), ( 755,  30,  227), ( 775,  30,  233),
    ( 775,  54,  419), ( 790,  15,  119), ( 795,  30,  239),
    ( 815,  30,  245), ( 830,  15,  125), ( 835,  30,  251),
    ( 850,  59,  501), ( 875,  26,  227), ( 875,  54,  473),
    ( 950,  13,  123), ( 950,  53,  503), ( 975,  26,  253));

{ --- 4. Entity_TileCollideX/Y @ 0x00457300 / 0x004574DC ------------------

  The first check is the one that matters and it uses SHIPPED DATA. An entity
  small enough to sit inside one tile is placed at the centre of every tile of a
  real map in turn, and asked what it would hit moving one sub-pixel right. The
  answer must be that tile when the map says it is solid and TILE_NONE when it
  does not - for all of them.

  That sweep is what pins the index arithmetic, and the -128 in particular. The
  tile index is built from two separately-rounded pixel conversions and then
  biased by 128 tiles, and 128 is only right because BOTH the layer origin and
  the entity position carry POSITION_BIAS. Get that wrong by one and the whole
  map misaligns; get the rounding wrong and it misaligns near the edges only.
  Neither could hide behind a hand-built fixture. }
function TestTileCollide(Log: TStringList; const GameDir: string): Integer;
const
  SOLID = 50;
var
  Map: TTileMap;
  Tiles: TMapTiles;
  Grid: TGridTiles;
  L, L2: TLayerInfo;
  E: TEntity;
  TX, TY, Got, Want, Bad, Solids, Diff, A, B: Integer;
  ProbeA, ProbeB: string;

  procedure PlaceAt(PxX, PxY, ExtX, ExtY: Integer);
  begin
    FillChar(E, SizeOf(E), 0);
    E.Raw[EF_POS_X]    := (PxX shl POSITION_SHIFT) + POSITION_BIAS;
    E.Raw[EF_POS_Y]    := (PxY shl POSITION_SHIFT) + POSITION_BIAS;
    E.Raw[EF_EXTENT_X] := ExtX;
    E.Raw[EF_EXTENT_Y] := ExtY;
  end;

begin
  Result := 0;
  Log.Add('');
  Log.Add('--- Entity_TileCollideX/Y ---');

  FillChar(L, SizeOf(L), 0);
  L.OriginX := POSITION_BIAS;
  L.OriginY := POSITION_BIAS;
  L.TileW := 32;
  L.TileH := 32;

  { --- 4a. every tile of a shipped map ---------------------------------- }
  Map := TTileMap.Create;
  Tiles := TMapTiles.Create;
  try
    Tiles.Map := Map;
    if not Map.Load(GameDir, 1) then
    begin
      Log.Add('FAILED: could not load map 001');
      Inc(Result);
    end
    else if (Map.TileWidth <> 32) or (Map.TileHeight <> 32) then
    begin
      Log.Add(Format('FAILED: map 001 is %dx%d tiles, the arithmetic assumes 32',
        [Map.TileWidth, Map.TileHeight]));
      Inc(Result);
    end
    else
    begin
      Bad := 0;
      Solids := 0;
      for TY := 0 to Map.MapHeight - 1 do
        for TX := 0 to Map.MapWidth - 1 do
        begin
          PlaceAt(TX * 32 + 16, TY * 32 + 16, 2, 2);
          Want := Map.TileAtRaw(TX, TY);
          if Want >= SOLID then
            Inc(Solids)
          else
            Want := TILE_NONE;
          Got := EntityTileCollideX(E, L, Tiles, SOLID, 1, 0, False);
          if Got <> Want then
          begin
            if Bad < 5 then
              Log.Add(Format('  tile (%d,%d): got %d, map says %d',
                [TX, TY, Got, Want]));
            Inc(Bad);
          end;
          { and the Y mirror, moving down, must agree tile for tile }
          if EntityTileCollideY(E, L, Tiles, SOLID, 1, 0, False) <> Want then
          begin
            Inc(Bad);
            if Bad < 8 then
              Log.Add(Format('  tile (%d,%d): Y disagrees with X', [TX, TY]));
          end;
        end;
      Log.Add(Format('map 001, %dx%d tiles (%d of them solid): %d wrong',
        [Map.MapWidth, Map.MapHeight, Solids, Bad]));
      Inc(Result, Bad);
      if Solids = 0 then
      begin
        Log.Add('FAILED: no solid tiles in map 001 - the sweep proved nothing');
        Inc(Result);
      end;
    end;
  finally
    Tiles.Free;
    Map.Free;
  end;

  { --- 4b. the things a real map cannot show ----------------------------- }
  Grid := TGridTiles.Create;
  try
    Grid.W := 20;
    Grid.H := 15;

    { A standing entity is never blocked - the whole body is inside if Delta
      <> 0, which is why Player_Update can ask about EF_VEL_X unconditionally. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := 60;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    if EntityTileCollideX(E, L, Grid, SOLID, 0, 0, False) <> TILE_NONE then
    begin
      Log.Add('FAILED: a zero delta reported a collision');
      Inc(Result);
    end;

    { The leading edge sweeps the WHOLE cross-axis span. A 40-tall entity
      centred in tile row 5 spans rows 4..6, so a wall at its feet stops it. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][6] := 61;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 20, 40);
    Grid.Probes := '';
    Got := EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    Log.Add(Format('40-tall entity, wall at its feet: got %d, probed [%s]',
      [Got, Trim(Grid.Probes)]));
    if Got <> 61 then
    begin
      Log.Add('FAILED: the sweep did not reach the bottom of the box');
      Inc(Result);
    end;
    if Trim(Grid.Probes) <> '5,4 5,5 5,6' then
    begin
      Log.Add('FAILED: the swept span should be rows 4..6 of column 5');
      Inc(Result);
    end;

    { One row further down is outside the box and must not be seen. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][7] := 61;
    if EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False) <> TILE_NONE then
    begin
      Log.Add('FAILED: the sweep reached past the bottom of the box');
      Inc(Result);
    end;

    { Left and right edges are not symmetric: the right one carries a -1
      because it is the last pixel inside the box. Centre 183 puts the right
      edge in tile 6 and the left edge in tile 5. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[6][5] := 62;
    PlaceAt(183, 5 * 32 + 16, 20, 2);
    A := EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    B := EntityTileCollideX(E, L, Grid, SOLID, -1, 0, False);
    Log.Add(Format('edges at centre 183: moving right %d, moving left %d',
      [A, B]));
    if (A <> 62) or (B <> TILE_NONE) then
    begin
      Log.Add('FAILED: the two edges should straddle the tile boundary here');
      Inc(Result);
    end;

    { Scrolling is a ROUNDING decision, not a semantic one. It only decides
      which of the two pixel conversions carries the 1/32 remainder, so the sum
      can differ by one PIXEL - and that changes the tile only where the pixel
      it moves across is a tile boundary.

      A first version of this check compared the returned tile over a row of
      identical solid tiles and found no difference anywhere in 1024 cases,
      which proved nothing at all: the answer was the same tile VALUE either
      way. It compares the probed COLUMN now, and sweeps the entity across two
      whole tiles so a boundary is actually crossed. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    for TX := 0 to 19 do
      Grid.Cells[TX][5] := 63;
    Diff := 0;
    for TX := 160 to 223 do
    begin
      PlaceAt(TX, 5 * 32 + 16, 20, 2);
      E.Raw[EF_POS_X] := E.Raw[EF_POS_X] + 20;   { fraction on the entity }
      L.OriginX := POSITION_BIAS;                { and none on the layer }
      Grid.Probes := '';
      EntityTileCollideX(E, L, Grid, SOLID, 20, 0, False);
      ProbeA := Trim(Grid.Probes);
      Grid.Probes := '';
      EntityTileCollideX(E, L, Grid, SOLID, 20, 0, True);
      ProbeB := Trim(Grid.Probes);
      if ProbeA <> ProbeB then
      begin
        Inc(Diff);
        if Diff = 1 then
          Log.Add(Format('  at centre %d: not scrolling probes %s, scrolling '
            + 'probes %s', [TX, ProbeA, ProbeB]));
      end;
      { Counting differences cannot see an INVERTED flag - swapping the two
        answers leaves the count identical, and a mutation that did exactly
        that survived a run of this test. So pin which answer is which at a
        position worked out by hand: the entity carries a 20/32 pixel
        fraction and the layer none, so moving the ENTITY crosses into tile 6
        while moving the LAYER leaves it in tile 5. }
      if TX = 182 then
      begin
        if ProbeA <> '6,5' then
        begin
          Log.Add(Format('FAILED: not scrolling should probe 6,5, got %s',
            [ProbeA]));
          Inc(Result);
        end;
        if ProbeB <> '5,5' then
        begin
          Log.Add(Format('FAILED: scrolling should probe 5,5, got %s',
            [ProbeB]));
          Inc(Result);
        end;
      end;
    end;
    L.OriginX := POSITION_BIAS;
    Log.Add(Format('scrolling flag across two tiles of travel: changes the '
      + 'column in %d of 64 positions', [Diff]));
    if Diff = 0 then
    begin
      Log.Add('FAILED: the scrolling flag never mattered - it should, by '
        + 'rounding');
      Inc(Result);
    end;
    if Diff > 8 then
    begin
      Log.Add('FAILED: it should shift a boundary, not change the answer '
        + 'everywhere');
      Inc(Result);
    end;

    { The right edge's -1 is only visible when the edge lands on the LAST
      pixel of a tile. A 20-wide entity centred at 182 has its right edge at
      191, the last pixel of tile 5; drop the -1 and it becomes 192, the first
      of tile 6. The earlier edge case used centre 183, where both readings
      land in tile 6 and the -1 is invisible - and a mutation that removed it
      survived because of that. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[6][5] := 64;
    PlaceAt(182, 5 * 32 + 16, 20, 2);
    Got := EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    Log.Add(Format('right edge flush with tile 5''s last pixel: %d', [Got]));
    if Got <> TILE_NONE then
    begin
      Log.Add('FAILED: the right edge should still be inside tile 5');
      Inc(Result);
    end;

    { A tile EXACTLY at the threshold is solid - the test is >=, not >. Nothing
      else in this file uses a tile equal to the threshold, so a mutation to >
      survived. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := SOLID;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    Got := EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    if Got <> SOLID then
    begin
      Log.Add(Format('FAILED: a tile equal to the threshold must be solid, '
        + 'got %d', [Got]));
      Inc(Result);
    end;

    { The cross-axis span converts each term to pixels SEPARATELY. Summing
      first differs only by the carry of the two 1/32 fractions, and only
      matters where that carry crosses a tile edge - which needs the entity on
      a tile boundary AND both fractions set. At pixel Y 160 with 20/32 on each,
      the correct reading spans rows 4..5 and the summed one only row 5. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    PlaceAt(176, 160, 2, 2);
    E.Raw[EF_POS_Y] := E.Raw[EF_POS_Y] + 20;
    L.OriginY := POSITION_BIAS + 20;
    Grid.Probes := '';
    EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    L.OriginY := POSITION_BIAS;
    Log.Add(Format('cross-axis span with fractions on both: [%s]',
      [Trim(Grid.Probes)]));
    if Trim(Grid.Probes) <> '5,4 5,5' then
    begin
      Log.Add('FAILED: each term must be rounded to pixels on its own');
      Inc(Result);
    end;

    { The Y sweep divides its own axis by TileH. Every shipped map is 32x32, so
      swapping it for TileW is invisible against real data; this uses a
      synthetic 32x16 layer purely to tell the two apart. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    L2 := L;
    L2.TileH := 16;
    PlaceAt(176, 176, 2, 2);
    Grid.Probes := '';
    EntityTileCollideY(E, L2, Grid, SOLID, 1, 0, False);
    Log.Add(Format('Y sweep on a 32x16 layer probes [%s]', [Trim(Grid.Probes)]));
    if Trim(Grid.Probes) <> '5,139' then
    begin
      Log.Add('FAILED: the Y sweep must divide its own axis by TileH');
      Inc(Result);
    end;

    { The map wraps horizontally, because TileMap_Get has no bounds check.
      Column -1 is the previous row's last column. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    PlaceAt(-1 * 32 + 16, 5 * 32 + 16, 2, 2);
    Grid.Probes := '';
    EntityTileCollideX(E, L, Grid, SOLID, 1, 0, False);
    Log.Add(Format('an entity off the left edge probes [%s]',
      [Trim(Grid.Probes)]));
    if Trim(Grid.Probes) <> '-1,5' then
    begin
      Log.Add('FAILED: off-map lookups should be passed through, not clamped');
      Inc(Result);
    end;

    { And the wrap itself, which lives in TTileMap.TileAtRaw rather than in the
      collision code - the grid stub above never exercises it, which is why a
      mutation that clamped instead of wrapping survived. Column -1 of row N is
      the last column of row N-1, because the original indexes
      Data[X + Y * Width] with no check at all. }
    Map := TTileMap.Create;
    try
      if Map.Load(GameDir, 1) then
      begin
        Bad := 0;
        Solids := 0;
        for TY := 1 to Map.MapHeight - 1 do
        begin
          if Map.TileAtRaw(-1, TY) <> Map.TileAtRaw(Map.MapWidth - 1, TY - 1) then
            Inc(Bad);
          if Map.TileAtRaw(Map.MapWidth, TY - 1) <> Map.TileAtRaw(0, TY) then
            Inc(Bad);
          if Map.TileAtRaw(-1, TY) <> 0 then
            Inc(Solids);
        end;
        Log.Add(Format('horizontal wrap over %d rows: %d wrong, %d of them '
          + 'non-zero', [Map.MapHeight - 1, Bad, Solids]));
        Inc(Result, Bad);
        if Solids = 0 then
        begin
          Log.Add('FAILED: every wrapped lookup was 0 - a clamp would pass too');
          Inc(Result);
        end;
      end;
    finally
      Map.Free;
    end;

  finally
    Grid.Free;
  end;
end;

{ --- 5. the four adjacent sprite tables, and their EXTENTS ---------------

  This exists because of a real defect. Type 14's table was recorded as sixteen
  rows of four and it is TWO, and the old check could not see it: it read
  ITEM_VARIANTS * ITEM_FRAMES ints out of akuji.exe and compared them, so the
  length it verified was the very constant under test. Shrinking sixteen to two
  makes it read eight values instead of sixty-four, and it passes either way.

  Reading N values and finding they match proves the VALUES. To pin N you need
  a fact from outside the table, and here the layout supplies one: the region is
  a run of small const arrays laid end to end, each reached through its own
  pointer global, so a table ends exactly where the next one begins. This
  collects every pointer into the region straight out of the binary and requires
  the successor of each table's base to be base + length.

  That would have caught the sixteen immediately - the next pointer after
  0x0046BDA0 is 0x0046BDC0, thirty-two bytes on. }
function TestSpriteTables(Log: TStringList; const GameDir: string): Integer;
const
  { Where the pointer globals live, and the span of table bodies they address.
    Both are deliberately generous; a stray dword that happened to look like a
    pointer could only ever make a table look SHORTER, never longer, so this
    cannot pass something it should fail. }
  PTRS_LO = $0046C400;  PTRS_HI = $0046D400;
  BODY_LO = $0046B800;  BODY_HI = $0046C400;
var
  Exe: TMemoryStream;
  ExeName: string;
  Buf: array of Cardinal;
  Starts: array of Cardinal;
  I, J, K, Bad, Got: Integer;
  V, Next: Cardinal;

  { The smallest table start strictly greater than Base. }
  function Successor(Base: Cardinal): Cardinal;
  var
    N: Integer;
  begin
    Result := High(Cardinal);
    for N := 0 to High(Starts) do
      if (Starts[N] > Base) and (Starts[N] < Result) then
        Result := Starts[N];
  end;

  procedure CheckTable(const Name: string; Ptr, Base: Cardinal; Ints: Integer);
  var
    Held, Want: Cardinal;
  begin
    Exe.Position := Int64(Ptr) - DATA_VA_BIAS;
    Exe.ReadBuffer(Held, SizeOf(Held));
    if Held <> Base then
    begin
      Log.Add(Format('  %s: [0x%.6X] holds 0x%.6X, not 0x%.6X',
        [Name, Ptr, Held, Base]));
      Inc(Bad);
    end;
    Want := Base + Cardinal(Ints) * 4;
    if Successor(Base) <> Want then
    begin
      Log.Add(Format('  %s: claims %d ints, but the next table starts at '
        + '0x%.6X, not 0x%.6X', [Name, Ints, Successor(Base), Want]));
      Inc(Bad);
    end;
  end;

begin
  Result := 0;
  Log.Add('');
  Log.Add('--- the sprite tables at 0x0046BDA0 and their extents ---');

  Exe := TMemoryStream.Create;
  try
    ExeName := IncludeTrailingPathDelimiter(GameDir) + 'akuji.exe';
    if not FileExists(ExeName) then
    begin
      Log.Add('FAILED: akuji.exe is not in the game directory');
      Exit(1);
    end;
    Exe.LoadFromFile(ExeName);

    { Every pointer global into the region, read out of the binary. }
    SetLength(Buf, (PTRS_HI - PTRS_LO) div 4);
    Exe.Position := Int64(PTRS_LO) - DATA_VA_BIAS;
    Exe.ReadBuffer(Buf[0], Length(Buf) * SizeOf(Cardinal));
    SetLength(Starts, 0);
    for I := 0 to High(Buf) do
    begin
      V := Buf[I];
      if (V < BODY_LO) or (V >= BODY_HI) then
        Continue;
      K := -1;
      for J := 0 to High(Starts) do
        if Starts[J] = V then K := J;
      if K < 0 then
      begin
        SetLength(Starts, Length(Starts) + 1);
        Starts[High(Starts)] := V;
      end;
    end;
    Log.Add(Format('%d distinct table starts between 0x%.6X and 0x%.6X',
      [Length(Starts), BODY_LO, BODY_HI]));
    if Length(Starts) < 20 then
    begin
      Log.Add('FAILED: too few table starts found - the scan window is wrong '
        + 'and every extent below would pass vacuously');
      Inc(Result);
    end;

    Bad := 0;
    CheckTable('type 14', ITEM_SPRITE_TABLE_PTR, ITEM_SPRITE_TABLE_ADDR,
               ITEM_VARIANTS * ITEM_FRAMES);
    CheckTable('type 24', ITEM24_TABLE_PTR, ITEM24_TABLE_ADDR, ITEM24_VARIANTS);
    CheckTable('type 24 beat', ITEM24_BEAT_PTR, ITEM24_BEAT_ADDR,
               ITEM24_BEAT_FRAMES);
    CheckTable('type 25', ITEM25_TABLE_PTR, ITEM25_TABLE_ADDR, ITEM25_VARIANTS);
    CheckTable('type 27', SAVE_POINT_PTR, SAVE_POINT_ADDR, SAVE_POINT_FRAMES);
    Log.Add(Format('four tables, pointer and extent: %d wrong', [Bad]));
    Inc(Result, Bad);

    { And the values, now that the lengths mean something. }
    Bad := 0;
    SetLength(Buf, 64);
    Exe.Position := Int64(ITEM24_TABLE_ADDR) - DATA_VA_BIAS;
    Exe.ReadBuffer(Buf[0], ITEM24_VARIANTS * SizeOf(Cardinal));
    for I := 0 to ITEM24_VARIANTS - 1 do
      if Integer(Buf[I]) <> ITEM24_SPRITES[I] then Inc(Bad);
    Exe.Position := Int64(ITEM24_BEAT_ADDR) - DATA_VA_BIAS;
    Exe.ReadBuffer(Buf[0], ITEM24_BEAT_FRAMES * SizeOf(Cardinal));
    for I := 0 to ITEM24_BEAT_FRAMES - 1 do
      if Integer(Buf[I]) <> ITEM24_BEAT_SPRITES[I] then Inc(Bad);
    Exe.Position := Int64(ITEM25_TABLE_ADDR) - DATA_VA_BIAS;
    Exe.ReadBuffer(Buf[0], ITEM25_VARIANTS * SizeOf(Cardinal));
    for I := 0 to ITEM25_VARIANTS - 1 do
      if Integer(Buf[I]) <> ITEM25_SPRITES[I] then Inc(Bad);
    Log.Add(Format('type 24 and 25 table values: %d wrong', [Bad]));
    Inc(Result, Bad);

    { Variant 8's single sprite in the flat table is the first frame of its
      two-frame one. Two tables written independently agreeing on that is what
      says variant 8 really is the entry the special case is about. }
    if ITEM24_SPRITES[ITEM24_BEAT_VARIANT] <> ITEM24_BEAT_SPRITES[0] then
    begin
      Log.Add('FAILED: variant 8 disagrees with its own animation table');
      Inc(Result);
    end;
  finally
    Exe.Free;
  end;
end;

{ --- 6. types 24 and 25 -------------------------------------------------- }
function TestItemHandlers(Log: TStringList): Integer;
var
  W: TCountingWorld;
  E: TEntity;
  I, StartY, MinY, MaxY, Beats: Integer;
  Frames: string;

  procedure Fresh(Variant: Integer);
  begin
    FillChar(E, SizeOf(E), 0);
    E.Raw[EF_ALIVE]   := 1;
    E.Raw[EF_VARIANT] := Variant;
    E.Raw[EF_POS_X]   := POSITION_BIAS;
    E.Raw[EF_POS_Y]   := POSITION_BIAS;
    W.Sounds := 0;
    W.LastSound := -1;
  end;

begin
  Result := 0;
  Log.Add('');
  Log.Add('--- types 24 and 25 ---');
  W := TCountingWorld.Create;
  try
    { Type 25 is scenery: one table lookup, and nothing else may move. }
    for I := 0 to ITEM25_VARIANTS - 1 do
    begin
      Fresh(I);
      EntityUpdate_Type25(E);
      if E.Raw[EF_ANIM_ID] <> ITEM25_SPRITES[I] then
      begin
        Log.Add(Format('FAILED: type 25 variant %d gave sprite %d, want %d',
          [I, E.Raw[EF_ANIM_ID], ITEM25_SPRITES[I]]));
        Inc(Result);
      end;
      if (E.Raw[EF_POS_X] <> POSITION_BIAS)
      or (E.Raw[EF_POS_Y] <> POSITION_BIAS)
      or (E.Raw[EF_FACING] <> 0) or (E.Raw[EF_TIMER] <> 0) then
      begin
        Log.Add('FAILED: type 25 changed something other than its sprite');
        Inc(Result);
      end;
    end;
    Log.Add(Format('type 25: %d variants, sprite only', [ITEM25_VARIANTS]));

    { Type 27 alternates two frames every nine, and freezes outside play. }
    Fresh(0);
    Frames := '';
    for I := 1 to 20 do
    begin
      EntityUpdate_Type27(E, GS_PLAY);
      Frames := Frames + Format('%d', [E.Raw[EF_FLAG1C]]);
    end;
    Log.Add(Format('type 27 over 20 frames: %s', [Frames]));
    if Frames <> '00000000111111111000' then
    begin
      Log.Add('FAILED: the save point should flip every 9 frames');
      Inc(Result);
    end;
    Fresh(0);
    for I := 1 to 20 do
      EntityUpdate_Type27(E, GS_PAUSE);
    if (E.Raw[EF_FLAG1C] <> 0) or (E.Raw[EF_BLOCK_B] <> 0) then
    begin
      Log.Add('FAILED: the save point animated while the game was not in play');
      Inc(Result);
    end;
    if E.Raw[EF_ANIM_ID] <> SAVE_POINT_SPRITES[0] then
    begin
      Log.Add('FAILED: the save point should still set its sprite outside play');
      Inc(Result);
    end;

    { Type 24 bobs, and the bob CLOSES. DIR_COS sums to zero over its 64
      entries, so 64 frames of DirVelY must return the entity to exactly where
      it started - a property of the direction table, not of this handler, which
      is what makes it worth asserting. }
    Fresh(0);
    StartY := E.Raw[EF_POS_Y];
    MinY := StartY;
    MaxY := StartY;
    for I := 1 to DIR_COUNT do
    begin
      EntityUpdate_Type24(E, GS_PLAY, W);
      if E.Raw[EF_POS_Y] < MinY then MinY := E.Raw[EF_POS_Y];
      if E.Raw[EF_POS_Y] > MaxY then MaxY := E.Raw[EF_POS_Y];
    end;
    Log.Add(Format('type 24 after a full 64-frame bob: net y %d, travelled %d '
      + 'sub-pixels (%d px), facing %d',
      [E.Raw[EF_POS_Y] - StartY, MaxY - MinY,
       (MaxY - MinY) div 32, E.Raw[EF_FACING]]));
    if E.Raw[EF_POS_Y] <> StartY then
    begin
      Log.Add('FAILED: a whole period of the bob should net to zero');
      Inc(Result);
    end;
    if E.Raw[EF_FACING] <> 0 then
    begin
      Log.Add('FAILED: the phase should have wrapped back to 0');
      Inc(Result);
    end;
    { The net-to-zero above is only interesting if it moved in between. It does
      NOT move on the first frame - DirVelY(0) is DIR_COS[16], the sine's zero
      crossing - so this looks at the whole excursion rather than one step. }
    if MaxY - MinY = 0 then
    begin
      Log.Add('FAILED: the bob never moved at all');
      Inc(Result);
    end;

    { Outside GS_PLAY it sets its sprite and freezes. }
    Fresh(0);
    EntityUpdate_Type24(E, GS_PAUSE, W);
    if (E.Raw[EF_POS_Y] <> POSITION_BIAS) or (E.Raw[EF_FACING] <> 0) then
    begin
      Log.Add('FAILED: type 24 bobbed while the game was not in play');
      Inc(Result);
    end;
    if E.Raw[EF_ANIM_ID] <> ITEM24_SPRITES[0] then
    begin
      Log.Add('FAILED: type 24 should still set its sprite outside play');
      Inc(Result);
    end;

    { An ordinary variant is silent and does not animate. }
    Fresh(0);
    for I := 1 to 200 do
      EntityUpdate_Type24(E, GS_PLAY, W);
    if W.Sounds <> 0 then
    begin
      Log.Add(Format('FAILED: variant 0 played %d sound(s)', [W.Sounds]));
      Inc(Result);
    end;
    if E.Raw[EF_FLAG1C] <> 0 then
    begin
      Log.Add('FAILED: variant 0 should not advance a frame');
      Inc(Result);
    end;

    { Variant 8 alternates EVERY frame - its counter is compared against zero,
      so it resets on the frame it is incremented - and beats every 61. }
    Fresh(ITEM24_BEAT_VARIANT);
    Frames := '';
    for I := 1 to 6 do
    begin
      EntityUpdate_Type24(E, GS_PLAY, W);
      Frames := Frames + Format('%d ', [E.Raw[EF_ANIM_ID]]);
    end;
    Log.Add(Format('type 24 variant 8, six frames: %s', [Trim(Frames)]));
    if Trim(Frames) <> '480 481 480 481 480 481' then
    begin
      Log.Add('FAILED: variant 8 should alternate every single frame');
      Inc(Result);
    end;

    Fresh(ITEM24_BEAT_VARIANT);
    for I := 1 to 610 do
      EntityUpdate_Type24(E, GS_PLAY, W);
    Beats := W.Sounds;
    Log.Add(Format('type 24 variant 8 over 610 frames: %d heartbeat(s), '
      + 'last sound %d (%s)', [Beats, W.LastSound,
      SoundNames[W.LastSound]]));
    if Beats <> 10 then
    begin
      Log.Add('FAILED: want 10 beats - one every 61 frames');
      Inc(Result);
    end;
    if W.LastSound <> SND_KODOU then
    begin
      Log.Add('FAILED: the beat should be kodou.wav');
      Inc(Result);
    end;
  finally
    W.Free;
  end;
end;

{ --- Entity_Destroy @ 0x00461400 -----------------------------------------

  Four debts settled in four directions, and two of them are what makes this
  worth testing rather than assuming: a dying projectile hands a shot back to
  its owner, and a class-5 parent takes its children with it.

  The shot-count check is the interesting one. It reads the owner's slot from
  the projectile's int 1 and decrements the owner's int $15 - which is exactly
  the pair the Player.pas audit arrived at from the other side, when it moved
  PF_OWNER from $04 to $01. Two functions written weeks apart agreeing on an
  undocumented field pair is the strongest evidence available short of running
  the original. }
function TestDestroy(Log: TStringList): Integer;
var
  W: TCountingWorld;
  Pool: TEntityPool;
  Owner, Shot, Parent, Kid, N, I: Integer;
begin
  Result := 0;
  Log.Add('');
  Log.Add('--- Entity_Destroy ---');
  Pool := TEntityPool.Create;
  W := TCountingWorld.Create;
  try
    W.Pool := Pool;

    { A projectile gives its owner a shot back. }
    Owner := Pool.Spawn(EKIND_ACTOR, 1, 0, 0);
    Pool.SetField(Owner, EF_SHOTS, 2);
    Shot := Pool.Spawn(EKIND_MINOR, 2, 0, 0);
    Pool.SetField(Shot, EF_CLASS, DESTROY_CLASS_PROJECTILE);
    Pool.SetField(Shot, EF_OWNER, Owner);
    Pool.SetField(Shot, EF_SPRITE, SPRITE_NONE);
    Pool.SetField(Shot, EF_EVENT_ID, -1);
    W.DestroyEntity(Pool.Entity(Shot)^, False);
    Log.Add(Format('projectile destroyed: owner shots 2 -> %d, slot alive %d',
      [Pool.Field(Owner, EF_SHOTS), Pool.Field(Shot, EF_ALIVE)]));
    if Pool.Field(Owner, EF_SHOTS) <> 1 then
    begin
      Log.Add('FAILED: a dying projectile should return a shot to its owner');
      Inc(Result);
    end;
    if Pool.Field(Shot, EF_ALIVE) <> 0 then
    begin
      Log.Add('FAILED: the slot should be free');
      Inc(Result);
    end;

    { A parent takes its two children with it, and they take no loot. }
    Pool.Clear;
    Parent := Pool.Spawn(EKIND_MINOR, 3, 0, 0);
    Pool.SetField(Parent, EF_CLASS, DESTROY_CLASS_PARENT);
    Pool.SetField(Parent, EF_SPRITE, SPRITE_NONE);
    Pool.SetField(Parent, EF_EVENT_ID, -1);
    for I := 0 to 1 do
    begin
      Kid := Pool.Spawn(EKIND_MINOR, 4, 0, 0);
      Pool.SetField(Kid, EF_SPRITE, SPRITE_NONE);
      Pool.SetField(Kid, EF_EVENT_ID, -1);
      Pool.SetField(Parent, EF_CHILD_A + I, Kid);
    end;
    W.Killed := 0;
    W.DestroyEntity(Pool.Entity(Parent)^, False);
    N := 0;
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] then Inc(N);
    Log.Add(Format('parent destroyed: %d destroy call(s), %d slot(s) left alive',
      [W.Killed, N]));
    if N <> 0 then
    begin
      Log.Add('FAILED: the children should have gone with the parent');
      Inc(Result);
    end;

    { The no-drop flag. Column 8 non-zero means never drop, and the roll is
      not even taken - which is observable because the RNG does not advance. }
    Pool.Clear;
    Parent := Pool.Spawn(EKIND_MINOR, 5, 0, 0);
    Pool.SetField(Parent, EF_SPRITE, SPRITE_NONE);
    Pool.SetField(Parent, EF_EVENT_ID, -1);
    Pool.SetField(Parent, EF_NO_DROP, 1);
    RandomSeed := 4242;
    W.DestroyEntity(Pool.Entity(Parent)^, True);
    if RandomSeed <> 4242 then
    begin
      Log.Add('FAILED: a no-drop entity should not even roll');
      Inc(Result);
    end;
    N := 0;
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = DROP_TYPE) then Inc(N);
    if N <> 0 then
    begin
      Log.Add('FAILED: a no-drop entity dropped something');
      Inc(Result);
    end;

    { And with the flag clear it does roll - over enough tries the drop rate
      should land near the 76-in-256 the threshold implies. }
    N := 0;
    RandomSeed := 1;
    for I := 1 to 2000 do
    begin
      Pool.Clear;
      Parent := Pool.Spawn(EKIND_MINOR, 5, 0, 0);
      Pool.SetField(Parent, EF_SPRITE, SPRITE_NONE);
      Pool.SetField(Parent, EF_EVENT_ID, -1);
      W.DestroyEntity(Pool.Entity(Parent)^, True);
      if Pool.LiveCount > 0 then
        Inc(N);
    end;
    Log.Add(Format('drop rate over 2000 kills: %d (%.1f%%), threshold implies '
      + '%.1f%%', [N, N / 20.0, (DROP_ROLL - 1 - DROP_THRESHOLD) / 2.56]));
    if (N < 500) or (N > 700) then
    begin
      Log.Add('FAILED: the drop rate is nowhere near 76 in 256');
      Inc(Result);
    end;
  finally
    W.Free;
    Pool.Free;
  end;
end;

{ --- Entity_SpawnDebris @ 0x00461874 -------------------------------------

  This one cannot be checked against the original by emulation: it calls
  PlaySound, which reaches into the DirectSound component, and the emulator
  models the instruction set rather than the process. So it is checked against
  its own arithmetic instead, which is weaker and worth saying plainly.

  What IS pinned exactly is the RNG underneath it - Delphi's Random is
  differential-tested against 0x00402AC4 - so the scatter is reproducible even
  though the burst as a whole is not emulable. }
function TestSpawnDebris(Log: TStringList): Integer;
var
  W: TCountingWorld;
  Pool: TEntityPool;
  E: TEntity;
  I, N, Slot: Integer;
  Lifts, Kinds, Frames: string;
begin
  Result := 0;
  Log.Add('');
  Log.Add('--- Entity_SpawnDebris ---');
  Pool := TEntityPool.Create;
  W := TCountingWorld.Create;
  try
    W.Pool := Pool;
    W.TerrainId := TERRAIN_WATER_A;
    W.Layer.DeltaX := 64;
    W.Layer.DeltaY := -32;

    FillChar(E, SizeOf(E), 0);
    E.Raw[EF_POS_X] := POSITION_BIAS + 100 * 32;
    E.Raw[EF_POS_Y] := POSITION_BIAS + 50 * 32;

    RandomSeed := 12345;
    W.Sounds := 0;
    W.SpawnDebris(E, DEBRIS_SPLASH);

    N := 0;
    Lifts := '';
    Kinds := '';
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = EF_DEBRIS_TYPE) then
      begin
        Inc(N);
        Lifts := Lifts + Format('%d ', [Pool.Field(I, EF_VEL_Y)]);
        Kinds := Kinds + Format('%d ', [Pool.Field(I, EF_STATE)]);
      end;
    Log.Add(Format('kind 0 on water terrain: %d particles, sound %d (%s)',
      [N, W.LastSound, SoundNames[W.LastSound]]));
    Log.Add(Format('  lifts %s / states %s', [Trim(Lifts), Trim(Kinds)]));

    if N <> EF_DEBRIS_SPEEDS then
    begin
      Log.Add(Format('FAILED: the burst is always %d particles, got %d',
        [EF_DEBRIS_SPEEDS, N]));
      Inc(Result);
    end;
    if Trim(Lifts) <> '-32 -40 -48 -56 -64' then
    begin
      Log.Add('FAILED: the fan should be (i + 4) * -8');
      Inc(Result);
    end;
    if Trim(Kinds) <> '1 1 1 1 1' then
    begin
      Log.Add('FAILED: every particle should carry Kind + 1 in EF_STATE');
      Inc(Result);
    end;
    if (W.Sounds <> 1) or (W.LastSound <> SND_WATER01) then
    begin
      Log.Add('FAILED: terrain 3 should splash - water01, once');
      Inc(Result);
    end;

    { Terrain that is not water says nothing at all for kind 0. }
    Pool.Clear;
    W.TerrainId := 1;
    W.Sounds := 0;
    W.SpawnDebris(E, DEBRIS_SPLASH);
    if W.Sounds <> 0 then
    begin
      Log.Add('FAILED: only terrains 3 and 4 make a noise on kind 0');
      Inc(Result);
    end;

    { Kind 2 numbers its particles' frames in order; kind 1 randomises them. }
    Pool.Clear;
    W.Sounds := 0;
    W.SpawnDebris(E, DEBRIS_SHATTER);
    Frames := '';
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = EF_DEBRIS_TYPE) then
        Frames := Frames + Format('%d ', [Pool.Field(I, EF_FLAG1C)]);
    Log.Add(Format('kind 2 frames: %s, sound %d (%s)',
      [Trim(Frames), W.LastSound, SoundNames[W.LastSound]]));
    if Trim(Frames) <> '0 1 2 3 4' then
    begin
      Log.Add('FAILED: a shatter should fan through its frames in order');
      Inc(Result);
    end;
    if W.LastSound <> SND_BOM04 then
    begin
      Log.Add('FAILED: kind 2 is bom04');
      Inc(Result);
    end;

    { The layer delta is taken back out of the spawn position, so a particle
      does not get scrolled twice on the frame it is born. }
    Pool.Clear;
    W.SpawnDebris(E, DEBRIS_SHATTER);
    Slot := -1;
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = EF_DEBRIS_TYPE) then
      begin
        Slot := I;
        Break;
      end;
    if Slot >= 0 then
    begin
      Log.Add(Format('spawn x %d (parent %d, layer delta %d)',
        [Pool.Field(Slot, EF_POS_X) - POSITION_BIAS,
         E.Raw[EF_POS_X] - POSITION_BIAS, W.Layer.DeltaX]));
      if Pool.Field(Slot, EF_POS_X) - POSITION_BIAS
         <> (E.Raw[EF_POS_X] - POSITION_BIAS) - W.Layer.DeltaX then
      begin
        Log.Add('FAILED: the layer delta should be subtracted at spawn');
        Inc(Result);
      end;
    end;

    { And the scatter is reproducible, because the RNG is. }
    Pool.Clear;
    RandomSeed := 999;
    W.SpawnDebris(E, DEBRIS_IMPACT);
    Lifts := '';
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = EF_DEBRIS_TYPE) then
        Lifts := Lifts + Format('%d ', [Pool.Field(I, EF_VEL_X)]);
    Pool.Clear;
    RandomSeed := 999;
    W.SpawnDebris(E, DEBRIS_IMPACT);
    Kinds := '';
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = EF_DEBRIS_TYPE) then
        Kinds := Kinds + Format('%d ', [Pool.Field(I, EF_VEL_X)]);
    Log.Add(Format('same seed, same scatter: [%s]', [Trim(Lifts)]));
    if Lifts <> Kinds then
    begin
      Log.Add('FAILED: the same seed must give the same burst');
      Inc(Result);
    end;
    if Trim(Lifts) = '0 0 0 0 0' then
    begin
      Log.Add('FAILED: every particle got zero horizontal speed');
      Inc(Result);
    end;
  finally
    W.Free;
    Pool.Free;
  end;
end;

function SelfTestEntities(Log: TStringList): Integer;
var
  GameDir, ExeName: string;
  Exe: TMemoryStream;
  Table: array[0..ENTITY_TYPE_COUNT - 1] of Cardinal;
  Arm: array[0..15] of Byte;
  I, J, Bad, Rel, Target, NoArm, Half, Pct, Got, Want, Ties: Integer;
  Pool: TEntityPool;
  W: TCountingWorld;
  S: TStubSprites;
  P: TPlayerState;
  L: TLayerInfo;
  Inp: TInputState;
  E: PEntity;

  procedure Place(Slot, TypeId, Sprite, PxX, PxY: Integer);
  var
    Q: PEntity;
  begin
    Q := Pool.Entity(Slot);
    FillChar(Q^, SizeOf(TEntity), 0);
    Q^.Raw[EF_SLOT]   := Slot;
    Q^.Raw[EF_ALIVE]  := 1;
    Q^.Raw[EF_TYPE]   := TypeId;
    Q^.Raw[EF_SPRITE] := Sprite;
    Q^.Raw[EF_BYTE94] := 1;
    Q^.Raw[EF_POS_X]  := (PxX shl POSITION_SHIFT) + POSITION_BIAS;
    Q^.Raw[EF_POS_Y]  := (PxY shl POSITION_SHIFT) + POSITION_BIAS;
  end;

  procedure Run(AState: Integer);
  begin
    EntityTestState := AState;
    TouchCount := 0;
    HitCount := 0;
    TouchSlots := '';
    EntityUpdateAll(Pool, W, S, P, L, Inp, EntityTestState);
  end;

begin
  Result := 0;
  GameDir := ParamStr(2);
  if GameDir = '' then
    GameDir := ExtractFilePath(ParamStr(0));

  Log.Add('=== Entity_UpdateAll @ 0x004608BC ===');
  Log.Add('');

  { --- 1. the switch, read out of akuji.exe ------------------------------ }
  Bad := 0;
  NoArm := 0;
  Exe := TMemoryStream.Create;
  try
    ExeName := IncludeTrailingPathDelimiter(GameDir) + 'akuji.exe';
    if not FileExists(ExeName) then
    begin
      Log.Add('FAILED: akuji.exe is not in the game directory');
      Inc(Result);
    end
    else
    begin
      Exe.LoadFromFile(ExeName);
      Exe.Position := HANDLER_JUMP_TABLE - CODE_VA_BIAS;
      Exe.ReadBuffer(Table[0], ENTITY_TYPE_COUNT * SizeOf(Cardinal));

      for I := 0 to ENTITY_TYPE_COUNT - 1 do
      begin
        if Table[I] = HANDLER_NO_ARM_TARGET then
        begin
          Inc(NoArm);
          if HANDLER_ADDR[I] <> HANDLER_NONE then
          begin
            Log.Add(Format('  type %d: exe says no arm, table names 0x%.6X',
              [I, HANDLER_ADDR[I]]));
            Inc(Bad);
          end;
          Continue;
        end;

        { Every arm is `MOV EAX,EBX` then `CALL rel32`, except the two that pass
          no entity at all and start with the CALL. }
        Exe.Position := Int64(Table[I]) - CODE_VA_BIAS;
        Exe.ReadBuffer(Arm[0], SizeOf(Arm));
        J := -1;
        if Arm[0] = $E8 then J := 0
        else if (Arm[0] = $8B) and (Arm[1] = $C3) and (Arm[2] = $E8) then J := 2;
        if J < 0 then
        begin
          Log.Add(Format('  type %d: arm at 0x%.6X is not MOV/CALL', [I, Table[I]]));
          Inc(Bad);
          Continue;
        end;
        Rel := PInteger(@Arm[J + 1])^;
        Target := Integer(Table[I]) + J + 5 + Rel;
        if Cardinal(Target) <> HANDLER_ADDR[I] then
        begin
          Log.Add(Format('  type %d: exe 0x%.6X, table 0x%.6X',
            [I, Target, HANDLER_ADDR[I]]));
          Inc(Bad);
        end;
      end;

      Log.Add(Format('jump table at 0x%.6X: %d arms, %d types with none, %d wrong',
        [HANDLER_JUMP_TABLE, ENTITY_TYPE_COUNT - NoArm, NoArm, Bad]));
      Inc(Result, Bad);

      if NoArm <> 3 then
      begin
        Log.Add(Format('FAILED: expected 3 types with no arm, found %d', [NoArm]));
        Inc(Result);
      end;
    end;
  finally
    Exe.Free;
  end;

  { --- 2. ScaleByPercent over its whole domain --------------------------- }
  Bad := 0;
  Got := 0;
  Ties := 0;
  for Half := 0 to 1024 do
    for Pct := 0 to 100 do
    begin
      if (Half * Pct) mod 100 = 50 then
        Inc(Ties);
      Want := ExactPercent(Half, Pct);
      for J := 0 to High(X87_DEVIATIONS) do
        if (X87_DEVIATIONS[J][0] = Half) and (X87_DEVIATIONS[J][1] = Pct) then
        begin
          Want := X87_DEVIATIONS[J][2];
          Break;
        end;
      if ScaleByPercent(Half, Pct) <> Want then
      begin
        if Bad < 5 then
          Log.Add(Format('  half %d pct %d: got %d, x87 %d',
            [Half, Pct, ScaleByPercent(Half, Pct), Want]));
        Inc(Bad);
      end;
      if ScaleByPercent(Half, Pct) <> ExactPercent(Half, Pct) then
        Inc(Got);
    end;
  Log.Add('');
  Log.Add(Format('ScaleByPercent over 1025 x 101 cases (%d of them ties): '
    + '%d wrong', [Ties, Bad]));
  Log.Add(Format('  places where the x87 beats round-half-even: %d, want %d',
    [Got, Length(X87_DEVIATIONS)]));
  Inc(Result, Bad);
  if Got <> Length(X87_DEVIATIONS) then
  begin
    Log.Add('FAILED: the set of x87 deviations is not the one the simulation found');
    Inc(Result);
  end;

  { --- 3. the loop ------------------------------------------------------- }
  Pool := TEntityPool.Create;
  W := TCountingWorld.Create;
  S := TStubSprites.Create;
  try
    FillChar(P, SizeOf(P), 0);
    FillChar(Inp, SizeOf(Inp), 0);
    FillChar(L, SizeOf(L), 0);
    L.TileW := 32; L.TileH := 32; L.MapTilesX := 20; L.MapTilesY := 15;
    EntityPlayerTouch := @CountTouch;
    EntityTakeProjectileHits := @CountHit;
    TouchAbortAt := -1;
    W.Pool := Pool;

    { (a) the scroll is carried, unless the type is screen-space. }
    Pool.Clear;
    L.DeltaX := 64; L.DeltaY := -32;
    Place($21, 3, SPRITE_NONE, 100, 100);
    Place($22, 3, SPRITE_NONE, 100, 100);
    Pool.Entity($22)^.Raw[EF_SCREEN_SPACE] := 1;
    Run(GS_PLAY);
    Log.Add('');
    Log.Add(Format('scroll carry: world x %d y %d, screen-space x %d y %d',
      [EntityPixelX(Pool.Entity($21)^), EntityPixelY(Pool.Entity($21)^),
       EntityPixelX(Pool.Entity($22)^), EntityPixelY(Pool.Entity($22)^)]));
    if (EntityPixelX(Pool.Entity($21)^) <> 102)
    or (EntityPixelY(Pool.Entity($21)^) <> 99) then
    begin
      Log.Add('FAILED: a world entity did not follow the scroll');
      Inc(Result);
    end;
    if (EntityPixelX(Pool.Entity($22)^) <> 100)
    or (EntityPixelY(Pool.Entity($22)^) <> 100) then
    begin
      Log.Add('FAILED: a screen-space entity followed the scroll');
      Inc(Result);
    end;
    L.DeltaX := 0; L.DeltaY := 0;

    { The dispatcher's arms actually reach the handlers they name. Every other
      check of types 24 and 25 calls them DIRECTLY, so a case arm wired to the
      wrong handler goes unnoticed - and one did, until this was added: pointing
      type 25's arm at EntityUpdate_Type14 survived the whole suite. }
    Pool.Clear;
    Place($21, 25, SPRITE_NONE, 160, 120);
    Pool.Entity($21)^.Raw[EF_VARIANT] := 2;
    Place($22, 24, SPRITE_NONE, 160, 120);
    Pool.Entity($22)^.Raw[EF_VARIANT] := 3;
    Place($23, 27, SPRITE_NONE, 160, 120);
    Run(GS_PLAY);
    Log.Add('');
    Log.Add(Format('dispatch: type 25 var 2 -> sprite %d (want %d), '
      + 'type 24 var 3 -> sprite %d (want %d)',
      [Pool.Entity($21)^.Raw[EF_ANIM_ID], ITEM25_SPRITES[2],
       Pool.Entity($22)^.Raw[EF_ANIM_ID], ITEM24_SPRITES[3]]));
    if Pool.Entity($21)^.Raw[EF_ANIM_ID] <> ITEM25_SPRITES[2] then
    begin
      Log.Add('FAILED: the type 25 arm did not reach EntityUpdate_Type25');
      Inc(Result);
    end;
    if Pool.Entity($22)^.Raw[EF_ANIM_ID] <> ITEM24_SPRITES[3] then
    begin
      Log.Add('FAILED: the type 24 arm did not reach EntityUpdate_Type24');
      Inc(Result);
    end;
    if Pool.Entity($23)^.Raw[EF_ANIM_ID] <> SAVE_POINT_SPRITES[0] then
    begin
      Log.Add('FAILED: the type 27 arm did not reach EntityUpdate_Type27');
      Inc(Result);
    end;

    { (b) the sprite is placed by its top-left, the entity is its centre. }
    Pool.Clear;
    S.SW[1] := 20; S.SH[1] := 11;
    Place($21, 3, 1, 160, 120);
    Pool.Entity($21)^.Raw[EF_DEPTH] := 3;
    Run(GS_PLAY);
    E := Pool.Entity($21);
    Log.Add(Format('sprite: pos (%d,%d) extent %dx%d depth %d',
      [S.PX[1], S.PY[1], E^.Raw[EF_EXTENT_X], E^.Raw[EF_EXTENT_Y], S.PZ[1]]));
    if (S.PX[1] <> 150) or (S.PY[1] <> 115) then
    begin
      Log.Add('FAILED: sprite not centred on the entity (want 150,115)');
      Inc(Result);
    end;
    if (E^.Raw[EF_EXTENT_X] <> 20) or (E^.Raw[EF_EXTENT_Y] <> 11) then
    begin
      Log.Add('FAILED: extents did not come from the sprite');
      Inc(Result);
    end;
    if S.PZ[1] <> 3 then
    begin
      Log.Add('FAILED: explicit depth not passed through');
      Inc(Result);
    end;

    { and the -1 depth, which no shipped type uses but the code still has. }
    Pool.Clear;
    Place($21, 3, 1, 160, 120);
    Pool.Entity($21)^.Raw[EF_DEPTH] := DEPTH_BY_SCREEN_Y;
    Run(GS_PLAY);
    if S.PZ[1] <> S.PY[1] then
    begin
      Log.Add(Format('FAILED: depth -1 should sort by screen Y (%d, got %d)',
        [S.PY[1], S.PZ[1]]));
      Inc(Result);
    end;

    { (c) the death timer is also the flicker, and it hides on ODD frames. }
    Pool.Clear;
    Place($21, 3, 1, 160, 120);
    Pool.Entity($21)^.Raw[EF_DEATH_TIMER] := 5;
    Run(GS_PLAY);
    if S.Vis[1] then
    begin
      Log.Add('FAILED: visible on an odd death-timer frame');
      Inc(Result);
    end;
    Pool.Entity($21)^.Raw[EF_DEATH_TIMER] := 6;
    Run(GS_PLAY);
    if not S.Vis[1] then
    begin
      Log.Add('FAILED: hidden on an even death-timer frame');
      Inc(Result);
    end;

    { (d) timers tick in play, and freeze in the pause menu and in state 140. }
    Pool.Clear;
    Place($21, 3, SPRITE_NONE, 160, 120);
    Pool.Entity($21)^.Raw[EF_TIMER] := 10;
    Pool.Entity($21)^.Raw[EF_DEATH_TIMER] := 10;
    Run(GS_PLAY);
    Run(GS_PAUSE);
    Run(GS_STATE_140);
    E := Pool.Entity($21);
    Log.Add(Format('timers after play/pause/140: timer %d death %d',
      [E^.Raw[EF_TIMER], E^.Raw[EF_DEATH_TIMER]]));
    if (E^.Raw[EF_TIMER] <> 9) or (E^.Raw[EF_DEATH_TIMER] <> 9) then
    begin
      Log.Add('FAILED: only the GS_PLAY frame should have ticked the timers');
      Inc(Result);
    end;

    { (e) the touch boundary: SLOT_MINOR_FIRST, not one either side of it. }
    Pool.Clear;
    Place(SLOT_ACTOR_LAST, 3, SPRITE_NONE, 160, 120);
    Place(SLOT_MINOR_FIRST, 3, SPRITE_NONE, 160, 120);
    Run(GS_PLAY);
    Log.Add('');
    Log.Add(Format('touch: %d call(s) from slots [%s], %d projectile pass(es)',
      [TouchCount, Trim(TouchSlots), HitCount]));
    if (TouchCount <> 1) or (HitCount <> 1)
    or (Trim(TouchSlots) <> IntToStr(SLOT_MINOR_FIRST)) then
    begin
      Log.Add(Format('FAILED: only slot %d should be touch-tested',
        [SLOT_MINOR_FIRST]));
      Inc(Result);
    end;

    { (f) type 68 in state 3: touched once down in the actor slots, and TWICE
      up in the minor slots, because the special case does not exclude them. }
    Pool.Clear;
    Place(5, TYPE_TOUCH_IN_STATE_3, SPRITE_NONE, 160, 120);
    Pool.Entity(5)^.Raw[EF_STATE] := 3;
    Run(GS_PLAY);
    Log.Add(Format('type 68 state 3 in an actor slot: %d touch(es)', [TouchCount]));
    if TouchCount <> 1 then
    begin
      Log.Add('FAILED: type 68 in state 3 should be touched once here');
      Inc(Result);
    end;

    Pool.Clear;
    Place($30, TYPE_TOUCH_IN_STATE_3, SPRITE_NONE, 160, 120);
    Pool.Entity($30)^.Raw[EF_STATE] := 3;
    Run(GS_PLAY);
    Log.Add(Format('type 68 state 3 in a minor slot: %d touch(es)', [TouchCount]));
    if TouchCount <> 2 then
    begin
      Log.Add('FAILED: type 68 in state 3 should be touched twice in a minor slot');
      Inc(Result);
    end;

    { and state 2 gets nothing extra. }
    Pool.Clear;
    Place(5, TYPE_TOUCH_IN_STATE_3, SPRITE_NONE, 160, 120);
    Pool.Entity(5)^.Raw[EF_STATE] := 2;
    Run(GS_PLAY);
    if TouchCount <> 0 then
    begin
      Log.Add('FAILED: type 68 outside state 3 should not be touched here');
      Inc(Result);
    end;

    { (g) a touch that changes the game state abandons the rest of the frame.

      The touch log alone cannot show this, and a first version of this check
      that relied on it passed against a build with the abandon removed. The
      reason is that the loop ALSO skips the touch pass for any slot whose
      iteration starts outside GS_PLAY, so the touches stop either way. What
      only the abandon stops is the work that happens BEFORE that guard - the
      timer tick - so that is what this looks at. }
    Pool.Clear;
    for I := $21 to $25 do
    begin
      Place(I, 3, SPRITE_NONE, 160, 120);
      Pool.Entity(I)^.Raw[EF_TIMER] := 100;
    end;
    TouchAbortAt := $22;
    Run(GS_PLAY);
    TouchAbortAt := -1;
    Log.Add('');
    Log.Add(Format('abandon on state change: touched [%s], timers %d %d %d %d %d',
      [Trim(TouchSlots), Pool.Entity($21)^.Raw[EF_TIMER],
       Pool.Entity($22)^.Raw[EF_TIMER], Pool.Entity($23)^.Raw[EF_TIMER],
       Pool.Entity($24)^.Raw[EF_TIMER], Pool.Entity($25)^.Raw[EF_TIMER]]));
    if Trim(TouchSlots) <> '33 34' then
    begin
      Log.Add('FAILED: the loop should stop touching after the state changed');
      Inc(Result);
    end;
    for I := $23 to $25 do
      if Pool.Entity(I)^.Raw[EF_TIMER] <> 100 then
      begin
        Log.Add(Format('FAILED: slot %d was still updated after the abandon', [I]));
        Inc(Result);
      end;

    { (h) the pool is 289 slots and the loop walks 256 of them. An entity above
      the line is spawnable and is never updated - reproduced, not corrected. }
    Pool.Clear;
    L.DeltaX := 320;
    Place(ENTITY_UPDATE_COUNT, 3, SPRITE_NONE, 100, 100);
    Place(ENTITY_UPDATE_COUNT - 1, 3, SPRITE_NONE, 100, 100);
    Run(GS_PLAY);
    L.DeltaX := 0;
    Log.Add(Format('slot %d moved to %d, slot %d stayed at %d',
      [ENTITY_UPDATE_COUNT - 1, EntityPixelX(Pool.Entity(ENTITY_UPDATE_COUNT - 1)^),
       ENTITY_UPDATE_COUNT, EntityPixelX(Pool.Entity(ENTITY_UPDATE_COUNT)^)]));
    if EntityPixelX(Pool.Entity(ENTITY_UPDATE_COUNT)^) <> 100 then
    begin
      Log.Add('FAILED: a slot above the loop bound was updated');
      Inc(Result);
    end;
    if EntityPixelX(Pool.Entity(ENTITY_UPDATE_COUNT - 1)^) = 100 then
    begin
      Log.Add('FAILED: the last slot inside the bound was NOT updated');
      Inc(Result);
    end;
    if EntitiesLive <> 1 then
    begin
      Log.Add(Format('FAILED: EntitiesLive counted %d, want 1', [EntitiesLive]));
      Inc(Result);
    end;

    { (i) culling, and only for the types that ask for it. }
    Pool.Clear;
    W.Killed := 0;
    Place($21, 3, SPRITE_NONE, 5000, 120);
    Place($22, 3, SPRITE_NONE, 5000, 120);
    Pool.Entity($21)^.Raw[EF_CULL_OFFSCREEN] := 1;
    Run(GS_PLAY);
    Log.Add('');
    Log.Add(Format('off-screen cull: %d destroyed, culling entity alive=%d, '
      + 'other alive=%d', [W.Killed, Pool.Entity($21)^.Raw[EF_ALIVE],
      Pool.Entity($22)^.Raw[EF_ALIVE]]));
    if (W.Killed <> 1) or (Pool.Entity($22)^.Raw[EF_ALIVE] <> 1) then
    begin
      Log.Add('FAILED: exactly the EF_CULL_OFFSCREEN entity should be destroyed');
      Inc(Result);
    end;

    { (j) the box fields are rebuilt every frame from the sprite, and only in
      GS_PLAY. Type 1's row is 30/20/30/30, so a 40-wide sprite gives 6. }
    Pool.Clear;
    S.SW[2] := 40; S.SH[2] := 40;
    Place($21, 3, 2, 160, 120);
    E := Pool.Entity($21);
    E^.Raw[EF_BOX_PCT_X]   := 30;
    E^.Raw[EF_BOX_PCT_Y]   := 20;
    E^.Raw[EF_INSET_PCT_X] := 30;
    E^.Raw[EF_INSET_PCT_Y] := 30;
    Run(GS_PLAY);
    Log.Add(Format('boxes from a 40x40 sprite at 30/20/30/30: %d %d %d %d',
      [E^.Raw[EF_BOX_OFS_X], E^.Raw[EF_BOX_OFS_Y],
       E^.Raw[EF_HITBOX_INSET_X], E^.Raw[EF_HITBOX_INSET_Y]]));
    if (E^.Raw[EF_BOX_OFS_X] <> 6) or (E^.Raw[EF_BOX_OFS_Y] <> 4)
    or (E^.Raw[EF_HITBOX_INSET_X] <> 6) or (E^.Raw[EF_HITBOX_INSET_Y] <> 6) then
    begin
      Log.Add('FAILED: want 6 4 6 6');
      Inc(Result);
    end;

    E^.Raw[EF_BOX_OFS_X] := -1;
    Run(GS_PAUSE);
    if E^.Raw[EF_BOX_OFS_X] <> -1 then
    begin
      Log.Add('FAILED: the boxes were rebuilt outside GS_PLAY');
      Inc(Result);
    end;

  finally
    EntityPlayerTouch := nil;
    EntityTakeProjectileHits := nil;
    S.Free;
    W.Free;
    Pool.Free;
  end;

  Inc(Result, TestSpawnDebris(Log));
  Inc(Result, TestDestroy(Log));
  Inc(Result, TestTileCollide(Log, GameDir));
  Inc(Result, TestSpriteTables(Log, GameDir));
  Inc(Result, TestItemHandlers(Log));

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - the dispatcher matches the switch in the binary and behaves '
      + 'as read')
  else
    Log.Add('FAILED');
end;


{ ---------------------------------------------------------------------------
  --emudiff <emu-output> : diff the reconstruction against the ORIGINAL.

  This is the verification tier the project did not have. Everything else here
  checks the reconstruction against EVIDENCE - two readers agreeing, structure
  that validates itself, mutations that must be caught. None of it can say the
  Pascal computes what akuji.exe computes. Only running both can.

  The record said that needed a 32-bit toolchain. That was wrong, and the error
  is worth keeping: what needs one is a logging PROXY DLL, because a 32-bit
  process can only load 32-bit DLLs. Executing 32-bit code needs no 32-bit
  compiler - Ghidra ships a p-code emulator and analyzeHeadless runs scripts
  without a GUI, so the original's own bytes can be run with chosen inputs.

  ghidra_scripts/EmuDiff.java produces a file of

      <name> <hexaddr> <eax> <edx> <ecx> [stack args]  -> <result>

  where the result is what the ORIGINAL returned. This reads that back,
  recomputes each case with the reconstruction, and requires them to agree.
  tools/emudiff.py drives both halves.

  WHAT IT CANNOT REACH. The emulator models the instruction set, not the
  process: no Windows, no imports, no VCL. A function that calls the RTL or
  touches a handle faults, and that is an honest boundary rather than a bug.
  Leaf routines and arithmetic run fine, which is where the risk actually is.
  --------------------------------------------------------------------------- }

{ Delphi returns in EAX; the emulator reports it as an unsigned 32-bit value. }
function AsSigned(V: Int64): Integer;
begin
  if V > $7FFFFFFF then
    V := V - $100000000;
  Result := Integer(V);
end;

function EmuDiff(Log: TStringList): Integer;
var
  Src, F: TStringList;
  I, J, Arrow, Addr, Got, Want, Bad, Ran, Faulted, NoRef: Integer;
  Line, Name: string;
  Stk: array[0..7] of Integer;
  NStk: Integer;
  E, E2: TEntity;
  L: TLayerInfo;
  BoxA, BoxB: TBox;
  IsBool: Boolean;

  function Num(const S: string): Integer;
  begin
    if (Length(S) > 2) and (S[1] = '0') and (LowerCase(S[2]) = 'x') then
      Result := StrToInt('$' + Copy(S, 3, MaxInt))
    else if (Length(S) > 3) and (S[1] = '-') and (S[2] = '0')
         and (LowerCase(S[3]) = 'x') then
      Result := -StrToInt('$' + Copy(S, 4, MaxInt))
    else
      Result := StrToInt(S);
  end;

  { The value of key=... on this line, or Def when it is absent. }
  function Key(const K: string; Def: Integer): Integer;
  var
    N: Integer;
  begin
    Result := Def;
    for N := 0 to F.Count - 1 do
      if Copy(F[N], 1, Length(K) + 1) = K + '=' then
      begin
        Result := Num(Copy(F[N], Length(K) + 2, MaxInt));
        Exit;
      end;
  end;

  procedure ReadStack;
  var
    N, P: Integer;
    V, Part: string;
  begin
    NStk := 0;
    for N := 0 to F.Count - 1 do
      if Copy(F[N], 1, 4) = 'stk=' then
      begin
        V := Copy(F[N], 5, MaxInt);
        while V <> '' do
        begin
          P := Pos(',', V);
          if P = 0 then
          begin
            Part := V;
            V := '';
          end
          else
          begin
            Part := Copy(V, 1, P - 1);
            V := Copy(V, P + 1, MaxInt);
          end;
          if (Part <> '') and (NStk <= High(Stk)) then
          begin
            Stk[NStk] := Num(Part);
            Inc(NStk);
          end;
        end;
        Exit;
      end;
  end;

  { Rebuild the entity and layer the case was generated from, out of the f.*
    fields carried on the line. The emulator got the same values as raw bytes;
    this is the same setup expressed as records. }
  procedure BuildEntityAndLayer;
  begin
    FillChar(E, SizeOf(E), 0);
    FillChar(L, SizeOf(L), 0);
    E.Raw[EF_POS_X]    := Key('f.pos', 0);
    E.Raw[EF_POS_Y]    := Key('f.pos', 0);
    E.Raw[EF_EXTENT_X] := Key('f.ext', 0);
    E.Raw[EF_EXTENT_Y] := Key('f.ext', 0);
    E.Raw[EF_BOX_OFS_X] := Key('f.ofs', 0);
    E.Raw[EF_BOX_OFS_Y] := Key('f.ofs', 0);
    L.OriginX := Key('f.ox', 0);
    L.OriginY := Key('f.oy', 0);
    L.TileW   := Key('f.tile', 32);
    L.TileH   := Key('f.tile', 32);
  end;

begin
  Result := 0;
  Bad := 0; Ran := 0; Faulted := 0; NoRef := 0;
  if not FileExists(ParamStr(2)) then
  begin
    Log.Add('FAILED: no emulator output at ' + ParamStr(2));
    Exit(1);
  end;

  Src := TStringList.Create;
  F := TStringList.Create;
  try
    Src.LoadFromFile(ParamStr(2));
    Log.Add('=== the reconstruction against the original ===');
    Log.Add('');

    for I := 0 to Src.Count - 1 do
    begin
      Line := Trim(Src[I]);
      if (Line = '') or (Line[1] = '#') then
        Continue;

      F.Clear;
      F.Delimiter := ' ';
      F.StrictDelimiter := False;
      F.DelimitedText := Line;
      if (F.Count < 4) or (F[0] <> 'CASE') then
        Continue;

      Arrow := -1;
      for J := 0 to F.Count - 1 do
        if F[J] = '->' then Arrow := J;
      if Arrow < 0 then
        Continue;
      if F[Arrow + 1] = 'FAULT' then
      begin
        Inc(Faulted);
        Continue;
      end;
      if F[Arrow + 1] = 'BADSPEC' then
      begin
        Log.Add('  bad spec line: ' + Line);
        Inc(Result);
        Continue;
      end;

      Name := F[1];
      Addr := Num(F[2]);
      ReadStack;
      Want := AsSigned(StrToInt64(F[Arrow + 1]));
      IsBool := False;

      case Addr of
        $004513E0:
          Got := AngleBetween(Key('eax', 0), Key('edx', 0),
                              Key('ecx', 0), Stk[0]);
        $0045114C:
          begin
            if Key('edx', 0) < Key('eax', 0) then Got := -1
            else if Key('eax', 0) < Key('edx', 0) then Got := 1
            else Got := 0;
          end;
        $00457150:
          begin
            BuildEntityAndLayer;
            Got := TileEdgeDistX(E, L, Key('f.delta', 0));
          end;
        $00457228:
          begin
            BuildEntityAndLayer;
            Got := TileEdgeDistY(E, L, Key('f.delta', 0));
          end;
        $00402AC4:
          begin
            RandomSeed := Cardinal(Key('f.seed', 0));
            Got := DelphiRandom(Key('f.n', 0));
          end;
        $00451354:
          begin
            BoxA.L := Key('f.al', 0);  BoxA.T := Key('f.at', 0);
            BoxA.R := Key('f.ar', 0);  BoxA.B := Key('f.ab', 0);
            BoxB.L := Key('f.bl', 0);  BoxB.T := Key('f.bt', 0);
            BoxB.R := Key('f.br', 0);  BoxB.B := Key('f.bb', 0);
            Got := Ord(RectOverlap(BoxA, BoxB, Key('f.sx', 0),
                                   Key('f.sy', 0)));
            IsBool := True;
          end;
        $00457F98:
          begin
            FillChar(E, SizeOf(E), 0);
            FillChar(E2, SizeOf(E2), 0);
            E.Raw[EF_POS_X] := Key('f.apos', 0);
            E.Raw[EF_POS_Y] := Key('f.apos', 0);
            E.Raw[EF_EXTENT_X] := Key('f.aext', 0);
            E.Raw[EF_EXTENT_Y] := Key('f.aext', 0);
            E.Raw[EF_HITBOX_INSET_X] := Key('f.ains', 0);
            E.Raw[EF_HITBOX_INSET_Y] := Key('f.ains', 0);
            E2.Raw[EF_POS_X] := Key('f.bpos', 0);
            E2.Raw[EF_POS_Y] := Key('f.apos', 0);
            E2.Raw[EF_EXTENT_X] := Key('f.bext', 0);
            E2.Raw[EF_EXTENT_Y] := Key('f.bext', 0);
            E2.Raw[EF_HITBOX_INSET_X] := Key('f.bins', 0);
            E2.Raw[EF_HITBOX_INSET_Y] := Key('f.bins', 0);
            Got := Ord(EntitiesOverlap(E, E2, Key('f.sx', 1),
                                       Key('f.sy', 1)));
            IsBool := True;
          end;
      else
        Inc(NoRef);
        Continue;
      end;

      { A Delphi Boolean comes back in AL, and the original leaves whatever
        was in the register in the upper 24 bits - Rect_Overlap literally
        builds its result as CONCAT31(shrinkY shr 8, 1). So a boolean is
        compared on the low byte only. }
      if IsBool then
        Want := Ord((Want and $FF) <> 0);

      Inc(Ran);
      if Got <> Want then
      begin
        if Bad < 15 then
          Log.Add(Format('  %-26s original %d, reconstruction %d',
            [Name, Want, Got]));
        Inc(Bad);
      end;
    end;

    Log.Add(Format('%d cases compared, %d disagree', [Ran, Bad]));
    if Faulted > 0 then
      Log.Add(Format('%d faulted in the emulator - it models the instruction '
        + 'set, not the process', [Faulted]));
    if NoRef > 0 then
      Log.Add(Format('%d had no Pascal counterpart to compare against',
        [NoRef]));
    Inc(Result, Bad);
    if Ran = 0 then
    begin
      Log.Add('FAILED: nothing was actually compared');
      Inc(Result);
    end;
  finally
    F.Free;
    Src.Free;
  end;

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - the reconstruction agrees with akuji.exe on every case run')
  else
    Log.Add('FAILED');
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
      else if ParamStr(1) = '--selftest-player' then
        Result := SelfTestPlayer(Log)
      else if ParamStr(1) = '--selftest-trace' then
        Result := SelfTestTrace(Log)
      else if ParamStr(1) = '--selftest-entities' then
        Result := SelfTestEntities(Log)
      else if ParamStr(1) = '--emudiff' then
        Result := EmuDiff(Log)
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
     (ParamStr(1) = '--selftest-stages') or
     (ParamStr(1) = '--selftest-player') or
     (ParamStr(1) = '--selftest-trace') or
     (ParamStr(1) = '--selftest-entities') or
     (ParamStr(1) = '--emudiff') then
  begin
    ExitCode := RunSelfTest;
    Exit;
  end;

  Application.Initialize;
  Application.Title := 'Akuji the Demon';
  Application.CreateForm(TFrm_main, Frm_main);
  Application.Run;
end.
