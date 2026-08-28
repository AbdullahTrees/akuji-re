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
  Want, Got, Overlaps: Integer;
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
    procedure SetSpawnField(Slot, IntIndex, Value: Integer); override;
    procedure SpawnDebris(const E: TEntity; Kind: Integer); override;
    procedure PlaySound(Id: Integer); override;
    function RandomBelow(N: Integer): Integer; override;
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
     (ParamStr(1) = '--selftest-trace') then
  begin
    ExitCode := RunSelfTest;
    Exit;
  end;

  Application.Initialize;
  Application.Title := 'Akuji the Demon';
  Application.CreateForm(TFrm_main, Frm_main);
  Application.Run;
end.
