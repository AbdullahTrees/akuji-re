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
  Stages, Camera, TileMaps, Player, EntityHandlers, EventRunner, GameSession,
  SpritePool, Sprites, Dialogue, BgAnime, UnitInit, Title, Ending, Opening,
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
  else if PosChecked <> 1014 then
  begin
    { 988 before sub-op 15's two leading fields were given positions; its 13
      uses contribute 26 more. }
    Log.Add(Format('FAILED: expected 1014 positional args compared, got %d',
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

{ The animated tiles Terrain_Configure declares, checked against the literals
  in the function itself.

  Every one of the thirty frames is written into the binary TWICE over: once
  as the tile id the track belongs to and its position in a run, and once as
  the source pixel coordinates the drawing needs. TERRAIN_ANIM stores only the
  ids; this recomputes the coordinates through TileMaps' TileSrcX/TileSrcY and
  requires all sixty numbers to come back.

  That makes it a real check in two directions at once. It pins the table, and
  it pins the div/mod AXIS ORDER, which TileMaps.pas had believed on the
  strength of the drawing code alone and flagged as the line to revisit if
  tiles ever came out transposed. Under the obvious x/y reading not one of the
  six tracks lands on its own tile. }
function TestTerrainAnim(Log: TStrings): Integer;
const
  { Read straight off 0x004645B0, in the order the arms declare them:
    terrain, then track, then frame. Each pair is (srcY, srcX) - the two
    values pushed to MyBgAnime_AddFrame @ 0x0044E25C, whose third argument is
    8 every time. Y comes first, as it does in Load_Map. }
  LITERALS: array[0..29, 0..1] of Integer = (
    { terrain 1, tile 7  } ($00, $E0), ($00, $100), ($00, $120), ($00, $100),
    { terrain 1, tile 17 } ($20, $E0), ($20, $100), ($20, $120), ($20, $100),
    { terrain 2, tile 75 } ($E0, $A0), ($E0, $C0),  ($E0, $E0),  ($E0, $100),
                           ($E0, $120),
    { terrain 3, tile 17 } ($20, $E0), ($20, $100), ($20, $120), ($20, $100),
    { terrain 3, tile 7  } ($00, $E0), ($00, $100), ($00, $120), ($00, $100),
    { terrain 4, tile 15 } ($20, $A0), ($20, $C0),  ($20, $E0),  ($20, $100),
                           ($20, $120),
    { terrain 4, tile 63 } ($C0, $60), ($C0, $80),  ($C0, $A0),  ($C0, $80)
  );
  SHEET_COLS = 10;
  TILE_PX    = 32;

  { The two values every arm of 0x004645B0 writes, transcribed from the
    disassembly rather than from the table under test. Comparing
    TerrainConfigure's answer against TERRAIN_SOLID_THRESHOLD only says the
    function reads the table; it says nothing about whether the table is
    right, and a mutation that swapped two entries walked through both. }
  BIN_THRESHOLD: array[1..9] of Integer =
    ($32, $32, $3C, $32, $46, $3C, $3C, $3C, $50);
  BIN_KILL: array[1..9] of Integer =
    ($1D, $1D, $1D, $1D, $1D, $1D, $1D, $1D, 1000);
var
  Terr, Track, Frame, N, Tracks, Frames, Obvious, Thr, Kill, Bad: Integer;
  A: TTerrainAnim;
  Id, GotX, GotY: Integer;
begin
  Bad := 0;
  N := 0;
  Tracks := 0;
  Frames := 0;
  Log.Add('');
  Log.Add('--- Terrain_Configure''s animated tiles ---');

  for Terr := 1 to TERRAIN_MAX do
  begin
    A := TERRAIN_ANIM[Terr];
    Inc(Tracks, A.TrackCount);
    for Track := 0 to A.TrackCount - 1 do
    begin
      { A track's first frame is always its own tile - the animation starts
        from the picture that is already there. Six of six. }
      if A.Tracks[Track].Frames[0] <> A.Tracks[Track].TileId then
      begin
        Log.Add(Format('FAILED: terrain %d track %d animates tile %d but'
          + ' starts on %d', [Terr, Track, A.Tracks[Track].TileId,
                              A.Tracks[Track].Frames[0]]));
        Inc(Bad);
      end;

      for Frame := 0 to A.Tracks[Track].FrameCount - 1 do
      begin
        Inc(Frames);
        if N > High(LITERALS) then
        begin
          Log.Add('FAILED: more frames in the table than the function declares');
          Inc(Bad);
          Break;
        end;
        Id   := A.Tracks[Track].Frames[Frame];
        GotX := TileSrcX(Id, TILE_PX, SHEET_COLS);
        GotY := TileSrcY(Id, TILE_PX, SHEET_COLS);
        { LITERALS[N][0] is the FIRST pushed value, which is srcY. }
        if (GotY <> LITERALS[N][0]) or (GotX <> LITERALS[N][1]) then
        begin
          Log.Add(Format('FAILED: terrain %d track %d frame %d is tile %d ->'
            + ' (x %d, y %d), but 0x004645B0 pushes (y %d, x %d)',
            [Terr, Track, Frame, Id, GotX, GotY,
             LITERALS[N][0], LITERALS[N][1]]));
          Inc(Bad);
        end;
        Inc(N);
      end;
    end;
  end;

  Log.Add(Format('tracks: %d   frames: %d   coordinate pairs compared: %d',
    [Tracks, Frames, N]));

  { Pinned so that a table which quietly lost its contents could not pass by
    comparing nothing. Seven tracks over four terrains - 2, 1, 2, 2 - and
    thirty frames is what the function has. }
  if (Tracks <> 7) or (N <> 30) then
  begin
    Log.Add(Format('FAILED: expected 7 tracks and 30 frames, got %d and %d',
      [Tracks, N]));
    Inc(Bad);
  end;

  { And the TRANSPOSED reading must not reproduce them, or the comparison
    above would be true of both and could not tell them apart. It reproduces
    exactly one of the thirty, and that one cannot be helped: tile 77 sits on
    the sheet's DIAGONAL, where div and mod are equal, so both readings put it
    at (224, 224). Asserting "the transposed reading matches nothing" would be
    false; asserting "it matches only where the tile is diagonal" is the
    actual invariant, and no accident can satisfy it.

    This ran the OTHER WAY ROUND and passed, which is why the reconstruction
    drew a transposed map for so long. The two hypotheses differ only by also
    swapping which pushed argument is which, so this table alone could never
    decide between them - it fits both. Rendering map 001 with each reading
    and looking at it could, and did. }
  N := 0;
  Obvious := 0;
  for Terr := 1 to TERRAIN_MAX do
  begin
    A := TERRAIN_ANIM[Terr];
    for Track := 0 to A.TrackCount - 1 do
      for Frame := 0 to A.Tracks[Track].FrameCount - 1 do
      begin
        Id := A.Tracks[Track].Frames[Frame];
        { The transposed reading: srcY from mod, srcX from div. }
        if ((Id mod SHEET_COLS) * TILE_PX = LITERALS[N][0])
           and ((Id div SHEET_COLS) * TILE_PX = LITERALS[N][1]) then
        begin
          Inc(Obvious);
          if (Id div SHEET_COLS) <> (Id mod SHEET_COLS) then
          begin
            Log.Add(Format('FAILED: tile %d is off the diagonal yet both axis'
              + ' readings place it at (%d, %d)',
              [Id, LITERALS[N][0], LITERALS[N][1]]));
            Inc(Bad);
          end;
        end;
        Inc(N);
      end;
  end;
  Log.Add(Format('the row-major reading places all %d; the transposed one'
    + ' places %d, and only on the diagonal', [N, Obvious]));

  { --- the switch itself --------------------------------------------- }
  for Terr := 1 to TERRAIN_MAX do
  begin
    Thr := -1;
    Kill := -1;
    TerrainConfigure(Terr, Thr, Kill, A);
    if (Thr <> BIN_THRESHOLD[Terr]) or (Kill <> BIN_KILL[Terr]) then
    begin
      Log.Add(Format('FAILED: terrain %d configured (%d, %d), but 0x004645B0'
        + ' writes (%d, %d)',
        [Terr, Thr, Kill, BIN_THRESHOLD[Terr], BIN_KILL[Terr]]));
      Inc(Bad);
    end;
    { The kill tile has to be a tile you can walk INTO or nothing could ever
      touch it - so it must be below the threshold - except for terrain 9,
      whose kill tile is deliberately outside the id space altogether. }
    if (Kill < TILESET_IDS) and (Kill >= Thr) then
    begin
      Log.Add(Format('FAILED: terrain %d''s kill tile %d is at or above its'
        + ' solid threshold %d, so it could never be entered',
        [Terr, Kill, Thr]));
      Inc(Bad);
    end;
    if (Terr >= 5) and (A.TrackCount <> 0) then
    begin
      Log.Add(Format('FAILED: terrain %d built %d animated tiles; only 1..4 do',
        [Terr, A.TrackCount]));
      Inc(Bad);
    end;
  end;

  { The default arm writes nothing at all. That is the behaviour, not an
    oversight: a terrain id outside 1..9 falls through the jump table and the
    two globals keep whatever the last stage put there. }
  Thr := 12345;
  Kill := 6789;
  TerrainConfigure(0, Thr, Kill, A);
  if (Thr <> 12345) or (Kill <> 6789) or (A.TrackCount <> 0) then
  begin
    Log.Add(Format('FAILED: terrain 0 changed the configuration to (%d, %d)'
      + ' with %d tracks; the default arm writes nothing',
      [Thr, Kill, A.TrackCount]));
    Inc(Bad);
  end;
  TerrainConfigure(TERRAIN_MAX + 1, Thr, Kill, A);
  if (Thr <> 12345) or (Kill <> 6789) then
  begin
    Log.Add('FAILED: a terrain id past the end wrote to the globals');
    Inc(Bad);
  end;
  if Obvious <> 1 then
  begin
    Log.Add(Format('FAILED: expected exactly one diagonal frame (tile 77),'
      + ' found %d', [Obvious]));
    Inc(Bad);
  end;

  Result := Bad;
end;

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

  Inc(Result, TestTerrainAnim(Log));

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

{ Game_StartOrLoad @ 0x00462F40.

  NEW GAME and CONTINUE differ by one branch, so what is worth checking is not
  each path on its own but what the ORDER of the writes makes true: that a
  continue is a new game with a file read over the top, that a failed read
  therefore leaves a playable new game, and that difficulty survives the read
  because the session flags are applied afterwards. }
type
  { Counts the calls the original makes through the form, and can hold the
    cutscene open. }
  TStartStub = class(TStartHost)
  public
    Busy: Boolean;
    Tracks: string;
    function Opening: Boolean; override;
    procedure PlayMusic(Track: Integer; Restart: Boolean); override;
  end;

function TStartStub.Opening: Boolean;
begin
  Result := Busy;
end;

procedure TStartStub.PlayMusic(Track: Integer; Restart: Boolean);
begin
  Tracks := Tracks + Format('%d ', [Track]);
end;

{ Stage_Begin @ 0x00462210.

  Most of it is host calls, so what is worth checking is the part that is not:
  the three conversions that say what SpawnX, SpawnY and ScrollX/Y mean, and
  the ORDER, since loading the assets replaces what the other two read. }
type
  TStageHostStub = class(TStageHost)
  public
    Calls: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure PrepareDisplay; override;
    procedure ResetInput; override;
    procedure LoadStageAssets(StageIndex: Integer); override;
    procedure DefineFont; override;
    procedure SetBackgroundSurface; override;
  end;

constructor TStageHostStub.Create;
begin
  inherited Create;
  Calls := TStringList.Create;
end;

destructor TStageHostStub.Destroy;
begin
  Calls.Free;
  inherited Destroy;
end;

procedure TStageHostStub.PrepareDisplay;
begin Calls.Add('display'); end;
procedure TStageHostStub.ResetInput;
begin Calls.Add('input'); end;
procedure TStageHostStub.LoadStageAssets(StageIndex: Integer);
begin Calls.Add(Format('assets %d', [StageIndex])); end;
procedure TStageHostStub.DefineFont;
begin Calls.Add('font'); end;
procedure TStageHostStub.SetBackgroundSurface;
begin Calls.Add('background'); end;

function TestStageBegin(Log: TStrings): Integer;
var
  P: TPlayerState;
  L: TLayerInfo;
  Pool: TEntityPool;
  H: TStageHostStub;
  GS, Slot, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- Stage_Begin ---');

  Pool := TEntityPool.Create;
  H := TStageHostStub.Create;
  try
    InitNewGame(P, 0);
    P.SpawnX := 96;
    P.SpawnY := 115;
    P.ScrollX := 64;
    P.ScrollY := 448;
    P.SpawnFacing := $10;
    FillChar(L, SizeOf(L), 0);
    GS := GS_STAGE_BEGIN;

    StageBegin(Pool, L, P, H, 7, GS);

    { The state exists for exactly one frame and this is what ends it. }
    Want(GS = GS_PLAY,
         Format('Stage_Begin left the state at %d, want %d', [GS, GS_PLAY]));

    { The assets must be loaded BEFORE the origin and the spawn, because
      loading replaces the tilemaps and surfaces they read. Checking the whole
      sequence rather than "assets were loaded" is what pins that. }
    Want(H.Calls.CommaText = 'display,input,"assets 7",font,background',
         'the setup ran in the order ' + H.Calls.CommaText);

    { ScrollX/Y are PIXELS; the layer origin is 1/32 pixel, biased. }
    Want(L.OriginX = (64 shl 5) + POSITION_BIAS,
         Format('origin x is %d, want %d',
                [L.OriginX, (64 shl 5) + POSITION_BIAS]));
    Want(L.OriginY = (448 shl 5) + POSITION_BIAS,
         Format('origin y is %d, want %d',
                [L.OriginY, (448 shl 5) + POSITION_BIAS]));

    { The player is slot 0 - EKIND_SINGLE has exactly one slot, which is what
      lets every homing entity read p_Entities[0] with no indirection. }
    Slot := SLOT_NONE;
    if Pool.Alive[0] then
      Slot := 0;
    Want(Slot = 0, 'Stage_Begin did not put the player in slot 0');
    if Slot = 0 then
    begin
      Want(Pool.Field(0, EF_TYPE) = 1,
           Format('the player spawned as type %d, want 1',
                  [Pool.Field(0, EF_TYPE)]));
      { SpawnX/Y are pixels too, and PosX gives them back unbiased. 96 pixels
        is 3072 in 1/32 units - the numbers are written out rather than
        recomputed from the field, so a changed shift is visible. }
      Want(Pool.PosX(0) = 3072,
           Format('the player spawned at x=%d, want 96 pixels = 3072',
                  [Pool.PosX(0)]));
      Want(Pool.PosY(0) = 3680,
           Format('the player spawned at y=%d, want 115 pixels = 3680',
                  [Pool.PosY(0)]));
      Want(Pool.Field(0, EF_FACING) = $10,
           Format('the player faces %d, want the saved $10',
                  [Pool.Field(0, EF_FACING)]));
      Want(Pool.LiveCount = 1,
           Format('Stage_Begin spawned %d entities, want 1',
                  [Pool.LiveCount]));
    end;

    { A default new game lands where Game_StartOrLoad's constants say: tile 3
      across, and 19 pixels into tile 3 down. The asymmetry is the point. }
    Pool.Clear;
    InitNewGame(P, 0);
    FillChar(L, SizeOf(L), 0);
    GS := GS_STAGE_BEGIN;
    StageBegin(Pool, L, P, H, 1, GS);
    Want(Pool.PosX(0) = 96 * 32, 'the default spawn is not 96 pixels across');
    Want(Pool.PosY(0) = 115 * 32, 'the default spawn is not 115 pixels down');
    { And the two axes really are offset differently. 96 is tile 3 flush; 115
      is tile 3 plus 19, which is SPAWN_CENTRE_Y and not SPAWN_CENTRE_X. }
    Want(DEFAULT_SPAWN_X = 3 * 32,
         Format('the default X %d is not flush with tile 3',
                [DEFAULT_SPAWN_X]));
    Want(DEFAULT_SPAWN_Y = 3 * 32 + 19,
         Format('the default Y %d is not tile 3 plus 19', [DEFAULT_SPAWN_Y]));
    Want(SPAWN_CENTRE_Y <> SPAWN_CENTRE_X,
         'the two spawn offsets have become equal; the original has 16 and 19');
  finally
    H.Free;
    Pool.Free;
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('OK - assets first, then the origin and the player, then GS_PLAY');
end;

function TestGameStart(Log: TStrings; const GameDir: string): Integer;
var
  P: TPlayerState;
  Cfg: TGameSettings;
  H: TStartStub;
  GS, Bad, SavedStage, SavedMusic, SavedDiff: Integer;
  SaveName, TempSave: string;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

  procedure FreshSettings(Level: Integer);
  begin
    FillChar(Cfg, SizeOf(Cfg), 0);
    Cfg.GameLevel := Level;
    Cfg.CurrentStage := 999;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- Game_StartOrLoad ---');
  SaveName := IncludeTrailingPathDelimiter(GameDir) + 'data' + PathDelim
              + 'save.dat';

  H := TStartStub.Create;
  try
    { --- the cutscene holds everything back -------------------------- }
    FreshSettings(1);
    FillChar(P, SizeOf(P), $AB);
    GS := GS_TITLE_MENU;
    H.Busy := True;
    Want(not GameStartOrLoad(P, Cfg, smNewGame, H, True, SaveName, GS),
         'the cutscene was running but the game started anyway');
    Want(GS = GS_TITLE_MENU,
         'the game state moved on while the cutscene was still running');
    Want(Cfg.CurrentStage = 999,
         'the settings were touched while the cutscene was still running');
    Want(H.Tracks = '', 'music started while the cutscene was still running');
    Want(P.Progress[0] = $AB,
         'the player state was written while the cutscene was still running');

    { CONTINUE does not wait for it. That is what says the gate is on the
      new-game path specifically and not on the function. }
    H.Busy := True;
    H.Tracks := '';
    FreshSettings(1);
    GS := GS_TITLE_MENU;
    Want(GameStartOrLoad(P, Cfg, smContinue, H, True, SaveName, GS),
         'CONTINUE waited for the opening cutscene');

    { --- a new game -------------------------------------------------- }
    H.Busy := False;
    H.Tracks := '';
    FreshSettings(1);
    GS := GS_TITLE_MENU;
    Want(GameStartOrLoad(P, Cfg, smNewGame, H, True, SaveName, GS),
         'a new game would not start');
    Want(GS = GS_STAGE_BEGIN,
         Format('a new game left the state at %d, want %d',
                [GS, GS_STAGE_BEGIN]));
    { Written out, not START_STAGE. An expectation phrased in terms of the
      constant it is checking moves with it and cannot fail. }
    Want(Cfg.CurrentStage = 1,
         Format('a new game starts at stage %d, want 1', [Cfg.CurrentStage]));
    Want(P.MusicTrack = 1,
         Format('a new game set music track %d, want 1', [P.MusicTrack]));
    Want(Trim(H.Tracks) = '1', 'the new game played ' + H.Tracks);
    Want(P.Lives = DEFAULT_LIVES, 'a new game does not start on three lives');
    Want(P.SpawnX = 96, Format('the spawn point is x=%d, want 96 pixels',
                               [P.SpawnX]));
    Want(P.SpawnY = 115, Format('the spawn point is y=%d, want 115 pixels',
                                [P.SpawnY]));
    Want(P.Progress[0] = 1, 'flag 0 is not set, so no 0000 guard would hold');
    Want(P.Head[ABILITY_DASH] = 0, 'a new game starts with the dash unlocked');
    { GameLevel 1 publishes itself as flag 5. }
    Want((P.Progress[5] = 1) and (P.Progress[6] = 0) and (P.Progress[10] = 0),
         'difficulty 1 did not publish itself as Progress[5]');

    { --- the two persistent unlocks ---------------------------------- }
    FreshSettings(0);
    GS := GS_TITLE_MENU;
    GameStartOrLoad(P, Cfg, smNewGame, H, True, SaveName, GS);
    Want((P.Progress[PROGRESS_EXTRA_DOOR_1] = 0)
         and (P.Progress[PROGRESS_EXTRA_DOOR_2] = 0),
         'the extra doors are open without the settings saying so');

    { ONE at a time. Setting both and checking both is symmetric, so swapping
      the two flag numbers is invisible to it - which is exactly what a
      mutation did. Each byte has to be shown to reach its own flag and not
      the other one. }
    FreshSettings(0);
    Cfg.ExtraDoor1 := 1;
    GS := GS_TITLE_MENU;
    GameStartOrLoad(P, Cfg, smNewGame, H, True, SaveName, GS);
    Want(P.Progress[1185] = 1,
         'settings +0x1C did not reach Progress[1185]');
    Want(P.Progress[1194] = 0,
         'settings +0x1C reached Progress[1194], which belongs to +0x1D');

    FreshSettings(0);
    Cfg.ExtraDoor2 := 1;
    GS := GS_TITLE_MENU;
    GameStartOrLoad(P, Cfg, smNewGame, H, True, SaveName, GS);
    Want(P.Progress[1194] = 1,
         'settings +0x1D did not reach Progress[1194]');
    Want(P.Progress[1185] = 0,
         'settings +0x1D reached Progress[1185], which belongs to +0x1C');

    { --- a continue, against a save this test BUILDS --------------------

      This used to read the game's own data\save.dat and assert against
      whatever was in it - the difficulty in particular, because the two
      branches below only differ when the save disagrees with the settings.

      That is not a fixture, it is whatever the last person to play left
      behind. It broke exactly that way: the shipped save was difficulty 2,
      someone played to a save point, and the file became a difficulty-0
      run - at which point the test could no longer tell its two branches
      apart. It said so and failed rather than passing vacuously, which is
      the only reason this was noticed at all.

      So it builds its own now, and the real save.dat is read for one
      informational line and nothing else. }
    if LoadSave(P, SaveName) then
      Log.Add(Format('data\save.dat is stage %d, music %d, difficulty %d '
        + '(read for information only)',
        [P.SavedStage, P.MusicTrack, P.Difficulty]))
    else
      Log.Add('  (no data\save.dat - it is not needed)');

    SavedStage := 42;
    SavedMusic := 7;
    SavedDiff  := 2;
    TempSave := GetTempDir(False) + 'akuji_selftest_continue.dat';
    FillChar(P, SizeOf(P), 0);
    P.SavedStage := SavedStage;
    P.MusicTrack := SavedMusic;
    P.Difficulty := SavedDiff;
    P.Lives := DEFAULT_LIVES;
    P.Head[ABILITY_DASH] := 1;
    if not SaveTo(P, TempSave) then
      Log.Add('  (could not write ' + TempSave + ' - the continue path is '
        + 'not exercised)')
    else
    begin
      H.Tracks := '';
      FreshSettings(0);
      GS := GS_TITLE_MENU;
      Want(GameStartOrLoad(P, Cfg, smContinue, H, True, TempSave, GS),
           'a continue with a readable save returned False');
      Want(Cfg.CurrentStage = SavedStage,
           Format('a continue went to stage %d, want the saved %d',
                  [Cfg.CurrentStage, SavedStage]));
      Want(P.MusicTrack = SavedMusic,
           Format('a continue plays track %d, want the saved %d',
                  [P.MusicTrack, SavedMusic]));
      Want(Trim(H.Tracks) = IntToStr(SavedMusic),
           'the continue played ' + H.Tracks);
      Want(P.Head[ABILITY_DASH] = 1,
           'the continue did not restore the abilities in the save');
      Want(P.Progress[0] = 1, 'the continue left flag 0 clear');

      { WITH the archive - which is what the shipped game does - the loaded
        difficulty stands, even though the settings say 0. }
      Want(P.Difficulty = SavedDiff,
           Format('with the archive a continue kept difficulty %d, want the'
             + ' saved %d and not the settings 0', [P.Difficulty, SavedDiff]));

      { WITHOUT it the second write fires and the settings win. This is the
        anomaly in the header; it is dead in the shipped game and is asserted
        so that it stays reproduced rather than quietly dropped. }
      FreshSettings(0);
      GS := GS_TITLE_MENU;
      GameStartOrLoad(P, Cfg, smContinue, H, False, TempSave, GS);
      Want(P.Difficulty = 0,
           Format('without the archive a continue kept difficulty %d, want 0'
             + ' from the settings', [P.Difficulty]));
      { Difficulty 0 publishes itself as Progress[10], and the saved 2 would
        have published itself as Progress[6] - so this is what says the
        session flags were republished and not merely left. }
      Want((P.Progress[10] = 1) and (P.Progress[6] = 0),
           'the second difficulty write did not republish the session flags');
      DeleteFile(TempSave);
    end;

    { --- a continue against a save that DISAGREES with the defaults --- }
    { The shipped save happens to hold music track 1, which is also the track
      a new game starts on - so it cannot show whether a continue plays the
      SAVED track or the default one. A mutation that replaced the saved track
      with the default passed against it. Build a save that differs. }
    if LoadSave(P, SaveName) then
    begin
      TempSave := GetTempDir(False) + 'akuji_selftest_save.dat';
      P.SavedStage := 42;
      P.MusicTrack := 7;
      { Session flags that CONTRADICT the difficulty they are stored beside.
        A save cannot really be inconsistent, but the point of applying the
        flags after the load is that whatever the file says about 5, 6 and 10
        is overwritten - so the only way to see that happening is to make the
        file wrong. InitNewGame publishes them too, which is why the later
        call is invisible on the new-game path and this is the one place it
        can be caught at all. }
      P.Difficulty := 2;
      P.Progress[5]  := 1;
      P.Progress[6]  := 0;
      P.Progress[10] := 1;
      if not SaveTo(P, TempSave) then
        Log.Add('  (could not write ' + TempSave + ' - skipped)')
      else
      begin
        H.Tracks := '';
        FreshSettings(0);
        GS := GS_TITLE_MENU;
        GameStartOrLoad(P, Cfg, smContinue, H, True, TempSave, GS);
        Want(Cfg.CurrentStage = 42,
             Format('a continue went to stage %d, want the saved 42',
                    [Cfg.CurrentStage]));
        Want(P.MusicTrack = 7,
             Format('a continue kept music track %d, want the saved 7',
                    [P.MusicTrack]));
        Want(Trim(H.Tracks) = '7',
             'the continue played ' + H.Tracks + ', want the saved track 7');
        Want((P.Progress[6] = 1) and (P.Progress[5] = 0)
             and (P.Progress[10] = 0),
             Format('the session flags were not republished after the load:'
               + ' 5=%d 6=%d 10=%d, want 0/1/0 for the saved difficulty 2',
               [P.Progress[5], P.Progress[6], P.Progress[10]]));
        DeleteFile(TempSave);
      end;
    end;

    { --- a continue with no save at all ------------------------------ }
    H.Tracks := '';
    FreshSettings(0);
    GS := GS_TITLE_MENU;
    Want(GameStartOrLoad(P, Cfg, smContinue, H, True,
                         GameDir + PathDelim + 'no-such-save.dat', GS),
         'a continue with no save file returned False');
    Want(Cfg.CurrentStage = 1,
         Format('a failed load left stage %d, want a clean new game at 1',
                [Cfg.CurrentStage]));
    Want(P.Lives = DEFAULT_LIVES,
         'a failed load did not leave a playable new game');
    Want(P.Progress[0] = 1, 'a failed load left flag 0 clear');
    Want(Trim(H.Tracks) = '1',
         'a failed load played ' + H.Tracks + ', want the default track');
  finally
    H.Free;
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('OK - a continue is a new game with a file read over the top');
end;

{ The opening cutscene's timing, against the frame counts the REAL GAME
  produced. tools/make_trace.py captured a 20,304 frame session; the slide
  counter changed at these frames:

      slide 1..7   480 frames each     8 seconds
      slide 8      120 frames          2 seconds
      slide 9      480 frames          8 seconds
      slide 10     765 frames          waits on the music, not the timer

  This drives TOpeningScreen with the same inputs and requires the same counts.
  It is the one test here whose expected values come from the original running
  rather than from the original being read.

  It exists because the cutscene was NOT RUNNING AT ALL. Opening.pas was correct
  the whole time and nothing called it: GmMain passed GameStartOrLoad a bare
  TStartHost, whose Opening returns False unconditionally, so the gate that is
  supposed to hold the whole of starting a game never closed. }
function TestOpeningTiming(Log: TStrings): Integer;
var
  Op: TOpeningScreen;
  Frames, Slide, Held, I: Integer;
  MusicOn, Running: Boolean;
  Counts: array[1..OPENING_SLIDES] of Integer;
begin
  Result := 0;
  for I := 1 to OPENING_SLIDES do
    Counts[I] := 0;

  Op := TOpeningScreen.Create;
  try
    Op.Reset;
    Slide := 0;
    Held := 0;
    Frames := 0;
    { The music runs under slides 9 and 10 and is what ends slide 10. Modelled
      as "still playing for 765 frames after slide 10 begins", which is what the
      trace measured. }
    MusicOn := True;
    Running := True;
    while Running and (Frames < 20000) do
    begin
      if (Op.Slide = OPENING_SLIDES) and (Held >= 765) then
        MusicOn := False;
      Running := Op.Update(False, MusicOn, False);
      Inc(Frames);
      if Op.Slide <> Slide then
      begin
        if (Slide >= 1) and (Slide <= OPENING_SLIDES) then
          Counts[Slide] := Held;
        Slide := Op.Slide;
        Held := 0;
      end;
      Inc(Held);
    end;
    if (Slide >= 1) and (Slide <= OPENING_SLIDES) and (Counts[Slide] = 0) then
      Counts[Slide] := Held;

    for I := 1 to OPENING_SLIDES do
    begin
      if I = 8 then
      begin
        if Counts[I] <> 120 then
        begin
          Log.Add(Format('FAILED: slide 8 held %d frames, the game held 120',
                         [Counts[I]]));
          Inc(Result);
        end;
      end
      else if I = OPENING_SLIDES then
      begin
        if Counts[I] < 700 then
        begin
          Log.Add(Format('FAILED: slide 10 held %d frames - it should wait on '
            + 'the music, which the trace had running for 765', [Counts[I]]));
          Inc(Result);
        end;
      end
      else if Counts[I] <> 480 then
      begin
        Log.Add(Format('FAILED: slide %d held %d frames, the game held 480',
                       [I, Counts[I]]));
        Inc(Result);
      end;
    end;
    if Result = 0 then
      Log.Add(Format('  opening: ten slides in %d frames, every hold matching '
        + 'the traced game', [Frames]));
  finally
    Op.Free;
  end;
end;

{ PixelOf and OriginPixel across NEGATIVE inputs, which is where they were
  broken and where nothing tested them.

  Both were a literal transcription of Delphi's codegen for `div 32` on a
  signed value - `if v < 0 then v := v + 31; v := v sar 5` - written with `shr`
  where the original has an arithmetic shift. On the face of it that is the
  same defect --emudiff found in type 49's bob, and I recorded it as one.

  IT WAS NOT. Both were giving correct answers, because POSITION_ROUND is an
  untyped constant and `Integer - 65505` no longer fits in an Integer, so FPC
  widens the expression to Int64; the shift happens in 64 bits and truncates
  back, which for every value in range matches an arithmetic shift. Type 49
  differed only in that its operand was a plain Integer variable, with nothing
  to trigger the widening.

  So this test does not guard a fix. It guards an ACCIDENT: the behaviour is
  correct for a reason not visible at the call site, and a typed constant or a
  hoisted temporary would silently remove it. The model below is the original's
  own idiom computed independently, checked across the sign boundary, and it
  holds for the `shr` form and the `div` form alike - which is precisely the
  point, since it is the third form, the one someone refactors into later, that
  it exists to catch. }
function TestPixelConversion(Log: TStrings): Integer;
var
  Offset, Want, GotPx, GotOrigin: Integer;
  Bad: Integer;

  { What the original computes: add the correction when negative, then an
    ARITHMETIC shift - which together are truncation toward zero. Written out
    rather than as `div` so the test does not simply restate the code. }
  function OriginalIdiom(V: Integer): Integer;
  begin
    if V < 0 then
      Result := SarLongint(V + ((1 shl POSITION_SHIFT) - 1), POSITION_SHIFT)
    else
      Result := SarLongint(V, POSITION_SHIFT);
  end;

begin
  Result := 0;
  Bad := 0;
  Offset := -4096;
  while Offset <= 4096 do
  begin
    Want := OriginalIdiom(Offset);
    GotPx := PixelOf(Offset + POSITION_BIAS);
    GotOrigin := OriginPixel(Offset);
    if (GotPx <> Want) or (GotOrigin <> Want) then
    begin
      if Bad < 6 then
        Log.Add(Format('  offset %d: original %d, PixelOf %d, OriginPixel %d',
                       [Offset, Want, GotPx, GotOrigin]));
      Inc(Bad);
    end;
    Inc(Offset);
  end;
  if Bad > 0 then
  begin
    Log.Add(Format('FAILED: %d of 8193 pixel conversions disagree with the '
      + 'original idiom', [Bad]));
    Inc(Result, 1);
  end
  else
    Log.Add('  pixel conversion matches across 8193 offsets, both signs');
end;

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
  { A layer origin ALWAYS carries POSITION_BIAS - Stage_Begin writes
    ScrollX * 0x20 + 0x10000 - and Camera_ShouldScroll* subtracts it back off
    with the -0x10000 / -0xFFE1 pair. These fixtures used bare pixel values,
    which only worked while the Pascal used the non-subtracting conversion.
    Biasing them is not a test change to suit the code: it is the fixture
    being made to look like a layer the game could actually produce. }
  FillChar(L, SizeOf(L), 0);
  L.TileW := 32; L.TileH := 32; L.MapTilesX := 1000; L.MapTilesY := 1000;
  L.OriginX := (200 shl POSITION_SHIFT) + POSITION_BIAS;
  L.OriginY := (200 shl POSITION_SHIFT) + POSITION_BIAS;
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

  L.OriginX := (Camera.MaxScrollX(L) shl POSITION_SHIFT) + POSITION_BIAS;
  L.OriginY := (Camera.MaxScrollY(L) shl POSITION_SHIFT) + POSITION_BIAS;
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

  Inc(Result, TestGameStart(Log, GameDir));
  Inc(Result, TestStageBegin(Log));
  Inc(Result, TestPixelConversion(Log));
  Inc(Result, TestOpeningTiming(Log));

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
    function TileAtX(const E: TEntity; Delta: Integer; Scrolling: Boolean;
                     DeltaY: Integer = 0): Integer; override;
    function TileAtY(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer; override;
    function EdgeDistX(const E: TEntity; Delta: Integer): Integer; override;
    function EdgeDistY(const E: TEntity; Delta: Integer): Integer; override;
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

function TFlatWorld.TileAtX(const E: TEntity; Delta: Integer;
                               Scrolling: Boolean; DeltaY: Integer): Integer;
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

{ NOTE: TFlatWorld no longer overrides SolidCollideX/Y. Those are implemented
  on TEntityWorld now, and with no Pool attached the real code finds no solids
  and returns False - which is exactly what the override used to fake. }
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
    { Biased, like every layer the game builds - see the note in the camera
      section above. With a bare 0 the vertical clamp reads the origin as
      2048 pixels ABOVE the map and lets the view move instead of the entity,
      so a jump never comes down. }
    L.OriginX := POSITION_BIAS;
    L.OriginY := POSITION_BIAS;

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
    L.OriginX := POSITION_BIAS;
    Reset;
    for I := 1 to 400 do Step(1, 0, False, False);
    Log.Add(Format('walk right on a big map: x %d, layer origin %d px'
      + '  (dead zone at %d)',
      [EntityPixelX(E), PixelOf(L.OriginX), Camera.DEADZONE_RIGHT]));
    if EntityPixelX(E) <> Camera.DEADZONE_RIGHT then
    begin
      Log.Add(Format('FAILED: expected the player to stop at the dead zone'
        + ' edge %d, got %d', [Camera.DEADZONE_RIGHT, EntityPixelX(E)]));
      Inc(Result);
    end;
    if PixelOf(L.OriginX) <= 0 then
    begin
      Log.Add('FAILED: the player stopped but the layer never scrolled');
      Inc(Result);
    end;

    { --- 5b. and on a map too small to scroll, it reaches the wall --------- }
    L.MapTilesX := 10;
    L.OriginX := POSITION_BIAS;
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
    ProgressSet: string;
    FlagFor: Integer;
    { NOTE: Pool is NOT redeclared here. It lives on TEntityWorld, and
      declaring it again shadowed the base field - the double's Spawn used
      one and Entity_Destroy used the other, which was nil, so every
      cross-entity effect silently did nothing while the test still saw a
      pool. It does NOT override SpawnDebris or RandomBelow either: a double
      that overrides the thing under test only tests the double. }
    function TileAtX(const E: TEntity; Delta: Integer; Scrolling: Boolean;
                     DeltaY: Integer = 0): Integer; override;
    function TileAtY(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer; override;
    function EdgeDistX(const E: TEntity; Delta: Integer): Integer; override;
    function EdgeDistY(const E: TEntity; Delta: Integer): Integer; override;
    function Spawn(Kind, TypeId, X, Y: Integer): Integer; override;
    procedure DestroyEntity(var E: TEntity; DropLoot: Boolean); override;
    procedure SetSpawnField(Slot, IntIndex, Value: Integer); override;
    procedure PlaySound(Id: Integer); override;
    function EventProgressIndex(EventId: Integer): Integer; override;
    procedure SetProgress(Index: Integer); override;
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

function TCountingWorld.TileAtX(const E: TEntity; Delta: Integer;
                                   Scrolling: Boolean; DeltaY: Integer): Integer;
begin Result := 0; end;
function TCountingWorld.TileAtY(const E: TEntity; Delta: Integer; Scrolling: Boolean): Integer;
begin Result := 0; end;
function TCountingWorld.EdgeDistX(const E: TEntity; Delta: Integer): Integer;
begin Result := 0; end;
function TCountingWorld.EdgeDistY(const E: TEntity; Delta: Integer): Integer;
begin Result := 0; end;
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

function TCountingWorld.EventProgressIndex(EventId: Integer): Integer;
begin
  { Stands in for looking ParamB up in the event table. -1 means "no event",
    which is what the base class says when nothing is wired. }
  if EventId < 0 then
    Exit(-1);
  Result := FlagFor;
end;

procedure TCountingWorld.SetProgress(Index: Integer);
begin
  ProgressSet := ProgressSet + Format('%d ', [Index]);
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

procedure CountTouch(var E, Player: TEntity; var P: TPlayerState;
                     var Inp: TInputState; World: TEntityWorld);
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
{ Entity_CheckKillTiles @ 0x004576B4.

  Unlike Entity_TileCollide*, which sweep a one-dimensional span along one
  edge, this walks the entity's whole tile RECTANGLE. TGridTiles records every
  lookup, so the shape of the sweep is checked and not merely its answer -
  which is the difference between "it found the tile" and "it looked where the
  original looks". }
function TestKillTiles(Log: TStringList): Integer;
const
  KILL = KILL_TILE;   { terrains 1..8; Stages.pas has the table }
var
  Grid: TGridTiles;
  L: TLayerInfo;
  E: TEntity;
  Bad: Integer;

  procedure PlaceAt(PxX, PxY, ExtX, ExtY: Integer);
  begin
    FillChar(E, SizeOf(E), 0);
    E.Raw[EF_POS_X]    := (PxX shl POSITION_SHIFT) + POSITION_BIAS;
    E.Raw[EF_POS_Y]    := (PxY shl POSITION_SHIFT) + POSITION_BIAS;
    E.Raw[EF_EXTENT_X] := ExtX;
    E.Raw[EF_EXTENT_Y] := ExtY;
  end;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('FAILED: ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- Entity_CheckKillTiles ---');

  FillChar(L, SizeOf(L), 0);
  L.OriginX := POSITION_BIAS;
  L.OriginY := POSITION_BIAS;
  L.TileW := 32;
  L.TileH := 32;

  { The 0x80 the original subtracts from both tile coordinates is not a magic
    number: the layer origin and the entity position EACH carry POSITION_BIAS,
    which is 2048 pixels, and 2048 / 32 is 64 tiles. Two of them is 128. So
    TILE_BIAS_TILES is a consequence of the bias appearing twice in the sum,
    and if the bias ever changed this would have to change with it. }
  Want(TILE_BIAS_TILES = 2 * ((POSITION_BIAS shr POSITION_SHIFT) div 32),
       Format('TILE_BIAS_TILES is %d but two lots of the origin bias is %d',
              [TILE_BIAS_TILES,
               2 * ((POSITION_BIAS shr POSITION_SHIFT) div 32)]));

  Grid := TGridTiles.Create;
  try
    Grid.W := 20;
    Grid.H := 15;

    { --- the tile under a small entity ---------------------------------- }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    E.Raw[EF_STATE] := 3;
    E.Raw[EF_BLOCK_B] := 77;
    Grid.Probes := '';
    EntityCheckKillTiles(E, L, Grid, KILL);
    { 10 written out, not KILL_TILE_STATE. An expectation phrased in terms of
      the constant it is checking moves with it and cannot fail - which this
      one did not, until a mutation set KILL_TILE_STATE to 11 and walked
      straight past. Fourth time on this project; tools/README.md keeps count. }
    Want(E.Raw[EF_STATE] = 10,
         Format('standing on the kill tile left the state at %d, want 10',
                [E.Raw[EF_STATE]]));
    Want(E.Raw[EF_BLOCK_B] = 0,
         Format('the state counter was left at %d, want 0',
                [E.Raw[EF_BLOCK_B]]));
    Log.Add(Format('small entity on a kill tile: probed [%s]',
      [Trim(Grid.Probes)]));

    { --- an ordinary tile does nothing ---------------------------------- }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := KILL - 1;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    E.Raw[EF_STATE] := 3;
    E.Raw[EF_BLOCK_B] := 77;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Want(E.Raw[EF_STATE] = 3, 'a tile one below the kill tile killed anyway');
    Want(E.Raw[EF_BLOCK_B] = 77, 'a near miss still cleared the counter');

    { --- the WHOLE box is swept, both axes ------------------------------ }
    { A 20 x 40 entity centred in tile (5,5) spans columns 4..5 and rows 4..6.
      Tile Collide would only sweep one edge; this must reach all six. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 20, 40);
    Grid.Probes := '';
    EntityCheckKillTiles(E, L, Grid, KILL);
    Log.Add(Format('20x40 entity at tile (5,5): probed [%s]',
      [Trim(Grid.Probes)]));
    Want(Trim(Grid.Probes) = '5,4 5,5 5,6',
         'the swept rectangle is not columns 5..5 by rows 4..6');

    { An entity exactly one tile tall fills its row and NO more. The -1 on the
      trailing edge is the only thing keeping it out of the next one, and it
      shows up only when the bottom edge lands exactly on a tile boundary -
      every other fixture here divides the same way with or without it. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][6] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 32);
    Grid.Probes := '';
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Log.Add(Format('exactly one tile tall: probed [%s]', [Trim(Grid.Probes)]));
    Want(Trim(Grid.Probes) = '5,5',
         'a box flush with the tile boundary spilled into the next row');
    Want(E.Raw[EF_STATE] = 3,
         'a box flush with the tile boundary was killed by the row below it');

    { EF_BOX_OFS_* is an INSET: added on the leading edge and subtracted on
      the trailing one, so it pulls both sides in. Adding it on both would
      slide the box instead, and with the offset at 0 - as it is in every
      fixture above - the two are the same thing. Give it a real value. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][4] := KILL;
    Grid.Cells[5][6] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 96);      { spans rows 4..6 }
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Want(E.Raw[EF_STATE] = 10, 'a 96-tall entity did not reach rows 4 and 6');

    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 96);
    E.Raw[EF_BOX_OFS_Y] := 32;                     { pulls both ends in a tile }
    Grid.Probes := '';
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Log.Add(Format('96 tall with a 32 inset: probed [%s]', [Trim(Grid.Probes)]));
    Want(Trim(Grid.Probes) = '5,5',
         'the inset did not pull BOTH ends of the box in');
    Want(E.Raw[EF_STATE] = 3,
         'the inset box still reached the kill tiles above and below it');

    { A kill tile at the bottom of that box is found... }
    Grid.Cells[5][6] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 20, 40);
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Want(E.Raw[EF_STATE] = KILL_TILE_STATE,
         'a kill tile at the entity''s feet was missed');

    { ...and one row further down is outside it and must not be. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][7] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 20, 40);
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Want(E.Raw[EF_STATE] = 3, 'the sweep reached a row below the box');

    { A wide entity reaches sideways too, which is what makes this a
      rectangle rather than a column. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[6][5] := KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 80, 2);
    Grid.Probes := '';
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Log.Add(Format('80-wide entity at tile (5,5): probed [%s]',
      [Trim(Grid.Probes)]));
    Want(E.Raw[EF_STATE] = KILL_TILE_STATE,
         'a kill tile beside a wide entity was missed');

    { --- the low sixteen bits, and only those --------------------------- }
    { The original compares MOVZX EAX,AX against the global, so a tile whose
      low word is the kill tile matches however high the rest is. No shipped
      map has such a word; the masking is reproduced because it is there. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := $10000 + KILL;
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL);
    Want(E.Raw[EF_STATE] = KILL_TILE_STATE,
         'the comparison is not masked to sixteen bits');

    { And terrain 9's kill tile, 1000, is outside the id space every tileset
      can produce - which is what makes that terrain survivable. Asked here
      the only way a fixture can: a map that does not contain it. }
    FillChar(Grid.Cells, SizeOf(Grid.Cells), 0);
    Grid.Cells[5][5] := 99;          { the largest id any 10x10 tileset has }
    PlaceAt(5 * 32 + 16, 5 * 32 + 16, 2, 2);
    E.Raw[EF_STATE] := 3;
    EntityCheckKillTiles(E, L, Grid, KILL_TILE_NONE);
    Want(E.Raw[EF_STATE] = 3,
         'the highest tile id a tileset can hold matched terrain 9''s kill tile');
  finally
    Grid.Free;
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('OK - the whole box is swept, nothing outside it is, '
      + 'and the match is masked');
end;

{ Types 8 and 26 - the two effects that destroy themselves.

  These are worth their own check because their failure mode is silence. An
  effect whose handler is missing does not crash or look obviously wrong: it
  just never dies, and the screen slowly fills with immortal entities wearing
  sprite 0. Nothing in the dispatcher can notice. So what is asserted here is
  that each one DOES reach its Entity_Destroy, and on which frame. }
function TestEffectHandlers(Log: TStringList): Integer;
var
  W: TCountingWorld;
  E: TEntity;
  I, Bad, Died, Frames: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

  procedure Fresh(TypeId: Integer);
  begin
    FillChar(E, SizeOf(E), 0);
    E.Raw[EF_ALIVE] := 1;
    E.Raw[EF_TYPE] := TypeId;
    E.Raw[EF_SPRITE] := SPRITE_NONE;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- the self-destructing effects ---');
  W := TCountingWorld.Create;
  try
    { --- type 8: four frames, five ticks each --------------------------- }
    Fresh(8);
    Died := -1;
    for I := 1 to 60 do
    begin
      if E.Raw[EF_ALIVE] <> 0 then
        EntityUpdate_Type08(E, GS_PLAY, W);
      if (Died < 0) and (E.Raw[EF_ALIVE] = 0) then
        Died := I;
    end;
    Log.Add(Format('type 8 lived %d frames', [Died]));
    { Four frames of five ticks is 20, and the destroy lands ON the twentieth
      rather than after it: the check follows the increment inside the same
      call, so the tick that carries the counter past the last index also
      destroys the entity. There is no extra frame. }
    Want(Died = 20,
         Format('type 8 died on frame %d, want 20 - four frames of five '
           + 'ticks, with the destroy on the last of them', [Died]));

    { Its sprite comes from the frame counter, so it must have walked the
      whole table rather than sitting on one. }
    Fresh(8);
    EntityUpdate_Type08(E, GS_PLAY, W);
    Want(E.Raw[EF_ANIM_ID] = 50, 'type 8 does not start on sprite 50');
    for I := 1 to 5 do
      EntityUpdate_Type08(E, GS_PLAY, W);
    Want(E.Raw[EF_ANIM_ID] = 51,
         Format('after five ticks type 8 is on sprite %d, want 51',
                [E.Raw[EF_ANIM_ID]]));

    { Outside play it freezes: the sprite is still written, the timer is not. }
    Fresh(8);
    for I := 1 to 60 do
      EntityUpdate_Type08(E, GS_STATE_140, W);
    Want(E.Raw[EF_ALIVE] <> 0, 'type 8 died during an event script');
    Want(E.Raw[EF_ANIM_ID] = 50, 'type 8 animated during an event script');

    { --- the whole family, by the property that matters ---------------- }
    { An effect that never reaches its Entity_Destroy is invisible to every
      other check and fills the screen over minutes. So each one is driven to
      exhaustion and required to end - or, for the three that deliberately do
      not, required to STILL BE ALIVE. Getting that backwards is exactly the
      bug this catches, in either direction. }
    for I := 3 to 13 do
    begin
      if I = 8 then
        Continue;                { covered in detail above }
      Fresh(I);
      E.Raw[EF_VEL_X] := 32;     { types 3 and 6 need a direction to animate }
      Died := -1;
      for Frames := 1 to 400 do
      begin
        if E.Raw[EF_ALIVE] = 0 then
          Break;
        case I of
          3:  EntityUpdate_Type03(E, GS_PLAY, W);
          4:  EntityUpdate_Type04(E, GS_PLAY, W);
          5:  EntityUpdate_Type05(E, GS_PLAY, W);
          6:  EntityUpdate_Type06(E, GS_PLAY, W);
          7:  EntityUpdate_Type07(E, GS_PLAY, W);
          9:  EntityUpdate_Type09(E, GS_PLAY);
          10: EntityUpdate_Type10(E, GS_PLAY, W);
          11: EntityUpdate_Type11(E, GS_PLAY);
          12: EntityUpdate_Type12(E, GS_PLAY);
          13: EntityUpdate_Type13(E, GS_PLAY, W);
        end;
        if (Died < 0) and (E.Raw[EF_ALIVE] = 0) then
          Died := Frames;
      end;
      { 9, 11 and 12 have no Entity_Destroy at all - they are culled
        off-screen instead, which is a different mechanism. }
      if (I = 9) or (I = 11) or (I = 12) then
        Want(Died < 0,
             Format('type %d ended itself on frame %d; it has no '
               + 'Entity_Destroy and should be culled instead', [I, Died]))
      else
        Want(Died > 0,
             Format('type %d never ended in 400 frames - it would stay on '
               + 'screen for ever wearing sprite %d',
               [I, E.Raw[EF_ANIM_ID]]));
      if Died > 0 then
        Log.Add(Format('  type %2d ended on frame %d', [I, Died]));
    end;

    { --- type 26: rises, then goes --------------------------------------- }
    Fresh(26);
    E.Raw[EF_POS_Y] := POSITION_BIAS;
    Died := -1;
    for I := 1 to 60 do
    begin
      if E.Raw[EF_ALIVE] <> 0 then
        EntityUpdate_Type26(E, GS_PLAY, W);
      if (Died < 0) and (E.Raw[EF_ALIVE] = 0) then
        Died := I;
    end;
    Log.Add(Format('type 26 lived %d frames and rose %d sub-pixels',
      [Died, POSITION_BIAS - E.Raw[EF_POS_Y]]));
    Want(Died = 31,
         Format('type 26 died on frame %d, want 31 - the count must EXCEED 30',
                [Died]));
    { It rose on every frame it was alive, 16 sub-pixels each. }
    Want(POSITION_BIAS - E.Raw[EF_POS_Y] = 31 * $10,
         Format('type 26 rose %d sub-pixels, want %d',
                [POSITION_BIAS - E.Raw[EF_POS_Y], 31 * $10]));

    { The variant is the whole difference between the two messages, and
      Entity_TouchPickup is what sets it - 0 for an ordinary stone, 1 when the
      stone completed a target. }
    Fresh(26);
    EntityUpdate_Type26(E, GS_PLAY, W);
    Want(E.Raw[EF_ANIM_ID] = 83,
         Format('variant 0 shows sprite %d, want 83', [E.Raw[EF_ANIM_ID]]));
    Fresh(26);
    E.Raw[EF_VARIANT] := 1;
    EntityUpdate_Type26(E, GS_PLAY, W);
    Want(E.Raw[EF_ANIM_ID] = 99,
         Format('variant 1 shows sprite %d, want 99', [E.Raw[EF_ANIM_ID]]));
  finally
    W.Free;
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('OK - both effects reach their Entity_Destroy');
end;

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
  0x0046BDA0 is 0x0046BDC0, thirty-two bytes on.

  SWEEPING THE REST

  The four tables above were checked this way and the other eighty were not,
  which left the same class of defect free to sit in any of them. Pin() below
  applies the identical test to EVERY table any handler records an address
  for, and separates two things the old wording ran together:

    * the EXTENT - how many ints the binary lays down at that address, pinned
      from outside by where the next table begins
    * the READ COUNT - how many of them a handler can reach

  They are usually the same and sometimes not, and a table where they differ
  is exactly where a length gets recorded wrong. Requiring both, and requiring
  the recorded values to be a PREFIX of what the binary holds, means a table
  can be short on purpose but not by accident.

  Running it for the first time found two: type 26's table is four ints and
  was recorded as two, and type 37's is six and was recorded as five. Type 26
  is reachable - its handler indexes by EF_VARIANT with no bound - so that one
  was a real under-record; type 37's sixth int is unreachable behind a mod 5,
  so five stays the read count and six is now stated as the extent. }
function TestSpriteTables(Log: TStringList; const GameDir: string): Integer;
const
  { Where the pointer globals live, and the span of table bodies they address.
    Both are deliberately generous; a stray dword that happened to look like a
    pointer could only ever make a table look SHORTER, never longer, so this
    cannot pass something it should fail. }
  { The CODE section, for the write-only scan below. }
  CODE_LO = $00401000;  CODE_HI = $00468000;
  PTRS_LO = $0046C400;  PTRS_HI = $0046D400;
  { Wide enough to take in the sound table at 0x00468E34 as well as the run of
    sprite tables. Widening only ADDS starts below every existing base, so it
    cannot change an extent that was already pinned. }
  { The run of table bodies does not stop at 0x0046C400 - bodies and pointer
    globals interleave above it, and type 57's hatch table is at 0x0046C460.
    Widening the body window only ADDS starts above every base already pinned,
    so it cannot change an extent that already passed. }
  BODY_LO = $00468000;  BODY_HI = $0046D400;
var
  Exe: TMemoryStream;
  ExeName: string;
  Buf: array of Cardinal;
  Starts: array of Cardinal;
  I, J, K, Bad, Got, Swept, N: Integer;
  Code: array of Byte;
  Op, Op2: array[0..1] of Byte;
  Init, Ctr, Held: Cardinal;
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

  { Extent, front, and values in one go. Ints is what the binary lays down;
    Want/WantCount is what we recorded, which may be shorter when a handler
    cannot reach the rest - but must never be longer, and must be a prefix. }
  procedure Pin(const Name: string; Base: Cardinal; Ints: Integer;
                Want: PInteger; WantCount: Integer);
  var
    Vals: array of Integer;
    N: Integer;
    IsStart: Boolean;
  begin
    Inc(Swept);
    IsStart := False;
    for N := 0 to High(Starts) do
      if Starts[N] = Base then IsStart := True;
    if not IsStart then
    begin
      Log.Add(Format('  %s: 0x%.6X is not the target of any pointer global, '
        + 'so nothing pins its front', [Name, Base]));
      Inc(Bad);
      Exit;
    end;

    if Successor(Base) <> Base + Cardinal(Ints) * 4 then
    begin
      Log.Add(Format('  %s: claims %d ints, but the next table starts at '
        + '0x%.6X, not 0x%.6X',
        [Name, Ints, Successor(Base), Base + Cardinal(Ints) * 4]));
      Inc(Bad);
      Exit;
    end;

    if WantCount > Ints then
    begin
      Log.Add(Format('  %s: %d values recorded but the table holds only %d',
        [Name, WantCount, Ints]));
      Inc(Bad);
      Exit;
    end;

    SetLength(Vals, Ints);
    Exe.Position := Int64(Base) - DATA_VA_BIAS;
    Exe.ReadBuffer(Vals[0], Ints * SizeOf(Integer));
    for N := 0 to WantCount - 1 do
      if Vals[N] <> PInteger(PtrUInt(Want) + PtrUInt(N * SizeOf(Integer)))^ then
      begin
        Log.Add(Format('  %s: entry %d is %d in the exe, %d here',
          [Name, N, Vals[N],
           PInteger(PtrUInt(Want) + PtrUInt(N * SizeOf(Integer)))^]));
        Inc(Bad);
      end;
  end;

  { A table whose handler reads only element 0, recorded as a scalar. }
  procedure PinOne(const Name: string; Base: Cardinal; Ints, Want: Integer);
  begin
    Pin(Name, Base, Ints, @Want, 1);
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

    { --- every table any handler records an address for -------------------
      Generated once from the binary and kept by hand since. A new handler
      adds its line here; a table with no line here is a table whose length
      nothing checks. }
    Bad := 0;
    Swept := 0;
    Pin('type 14 sprites', ITEM_SPRITE_TABLE_ADDR, 8, @ITEM_SPRITES[0][0], 8);
    Pin('type 24 sprites', ITEM24_TABLE_ADDR, 16, @ITEM24_SPRITES[0], 16);
    Pin('type 24 beat', ITEM24_BEAT_ADDR, 2, @ITEM24_BEAT_SPRITES[0], 2);
    Pin('type 25 sprites', ITEM25_TABLE_ADDR, 3, @ITEM25_SPRITES[0], 3);
    Pin('type 27 sprites', SAVE_POINT_ADDR, 2, @SAVE_POINT_SPRITES[0], 2);
    Pin('drop sprites', DROP_TABLE_ADDR, 2, @DROP_SPRITES[0], 2);
    Pin('type 2 sprites', T2_TABLE_ADDR, 12, @T2_SPRITES[0][0], 12);
    Pin('type 3 sprites', T3_TABLE_ADDR, 6, @T3_SPRITES[0][0], 6);
    Pin('type 4 sprites', T4_TABLE_ADDR, 2, @T4_SPRITES[0], 2);
    Pin('type 5 sprites', T5_TABLE_ADDR, 4, @T5_SPRITES[0], 4);
    Pin('type 6 sprites', T6_TABLE_ADDR, 8, @T6_SPRITES[0][0], 8);
    Pin('type 7 sprites', T7_TABLE_ADDR, 8, @T7_SPRITES[0][0], 8);
    Pin('type 8 sprites', TYPE8_TABLE_ADDR, 4, @TYPE8_SPRITES[0], 4);
    PinOne('type 9 sprite', T9_TABLE_ADDR, 1, T9_SPRITE);
    Pin('type 10 sprites', T10_TABLE_ADDR, 6, @T10_SPRITES[0], 6);
    Pin('type 11 sprites', T11_TABLE_ADDR, 4, @T11_SPRITES[0], 4);
    Pin('type 12 sprites', T12_TABLE_ADDR, 4, @T12_SPRITES[0], 4);
    Pin('type 13 splash', T13_SPLASH_TABLE_ADDR, 3, @T13_SPLASH_SPRITES[0], 3);
    Pin('type 13 shard 3', T13_SHARD3_TABLE_ADDR, 12,
        @T13_SHARD3_SPRITES[0], 12);
    PinOne('type 13 state 2', T13_STATE2_TABLE_ADDR, 2, T13_STATE2_SPRITE);
    Pin('type 13 shard 4', T13_SHARD4_TABLE_ADDR, 12,
        @T13_SHARD4_SPRITES[0], 12);
    PinOne('type 13 state 3', T13_STATE3_TABLE_ADDR, 5, T13_STATE3_SPRITE);
    Pin('type 15 sprites', T15_TABLE_ADDR, 2, @T15_SPRITES[0], 2);
    PinOne('type 16 sign', SIGN_SPRITE_ADDR, 1, SIGN_SPRITE);
    PinOne('type 21 sprite', T21_TABLE_ADDR, 1, T21_SPRITE);
    PinOne('type 22 sprite', TYPE22_SPRITE_ADDR, 1, TYPE22_SPRITE);
    PinOne('type 23 sprite', T23_TABLE_ADDR, 1, T23_SPRITE);
    Pin('type 26 sprites', TYPE26_TABLE_ADDR, 4, @TYPE26_SPRITES[0], 4);
    Pin('type 28 sprites', T28_TABLE_ADDR, 4, @T28_SPRITES[0], 4);
    Pin('type 29 sprites', T29_TABLE_ADDR, 4, @T29_SPRITES[0], 4);
    Pin('type 30 sprites', T30_TABLE_ADDR, 4, @T30_SPRITES[0][0], 4);
    Pin('type 31 sprites', T31_TABLE_ADDR, 5, @T31_SPRITES[0], 5);
    Pin('type 31 hp bonus', T31_HP_BONUS_ADDR, 3, @T31_HP_BONUS[0], 3);
    Pin('type 31 wait', T31_WAIT_ADDR, 3, @T31_WAIT[0], 3);
    Pin('type 31 rate', T31_RATE_ADDR, 3, @T31_RATE[0], 3);
    Pin('type 33 sprites', BOOM_TABLE_ADDR, 6, @BOOM_SPRITES[0], 6);
    Pin('type 34 sprites', T34_TABLE_ADDR, 5, @T34_SPRITES[0], 5);
    Pin('type 34 rate', T34_RATE_ADDR, 3, @T34_RATE[0], 3);
    Pin('type 35 sprites', T35_TABLE_ADDR, 8, @T35_SPRITES[0], 8);
    { six ints, five reachable - the sixth is behind a mod 5 }
    Pin('type 37 sprites', T37_TABLE_ADDR, 6, @T37_SPRITES[0], T37_FRAMES);
    Pin('type 38 sprites', T38_TABLE_ADDR, 8, @T38_SPRITES[0][0], 8);
    Pin('type 38 wait', T38_WAIT_ADDR, 3, @T38_WAIT[0], 3);
    Pin('type 39 sprites', T39_TABLE_ADDR, 10, @T39_SPRITES[0], 10);
    Pin('type 39 speed', T39_SPEED_ADDR, 3, @T39_SPEED[0], 3);
    Pin('type 39 wind', T39_WIND_ADDR, 3, @T39_WIND[0], 3);
    Pin('type 40 sprites', T40_TABLE_ADDR, 8, @T40_SPRITES[0][0], 8);
    Pin('type 40 cooldown', T40_COOLDOWN_ADDR, 3, @T40_COOLDOWN[0], 3);
    Pin('type 41 sprites', T41_TABLE_ADDR, 6, @T41_SPRITES[0], 6);
    Pin('type 41 wait', T41_WAIT_ADDR, 3, @T41_WAIT[0], 3);
    Pin('type 42 rise len', T42_RISE_LEN_ADDR, 3, @T42_RISE_LEN[0], 3);
    Pin('type 42 recover', T42_RECOVER_ADDR, 3, @T42_RECOVER[0], 3);
    Pin('type 42 shots', T42_SHOTS_ADDR, 3, @T42_SHOTS[0], 3);
    Pin('type 42 hp bonus', T42_HP_BONUS_ADDR, 3, @T42_HP_BONUS[0], 3);
    Pin('type 42 sprites', T42_TABLE_ADDR, 7, @T42_SPRITES[0], 7);
    Pin('type 42 angles', T42_ANGLES_ADDR, 6, @T42_ANGLES[0], 6);
    Pin('type 43 sprites', T43_TABLE_ADDR, 4, @T43_SPRITES[0], 4);
    Pin('type 44 sprites', T44_TABLE_ADDR, 8, @T44_SPRITES[0], 8);
    Pin('type 45 sprites', T45_TABLE_ADDR, 5, @T45_SPRITES[0], 5);
    Pin('type 45 tough', T45_TOUGH_ADDR, 3, @T45_TOUGH[0], 3);
    Pin('type 46 sprites', T46_TABLE_ADDR, 5, @T46_SPRITES[0], 5);
    Pin('type 46 range', T46_RANGE_ADDR, 3, @T46_RANGE[0], 3);
    Pin('type 46 turn', T46_TURN_ADDR, 3, @T46_TURN[0], 3);
    Pin('type 46 speed', T46_SPEED_ADDR, 3, @T46_SPEED[0], 3);
    Pin('type 47 sprites', T47_TABLE_ADDR, 5, @T47_SPRITES[0], 5);
    Pin('type 47 wait', T47_WAIT_ADDR, 3, @T47_WAIT[0], 3);
    Pin('type 47 rest', T47_REST_ADDR, 3, @T47_REST[0], 3);
    { four ints, two reachable - the spawn loop counts down from 2 }
    Pin('type 47 angles', T47_ANGLES_ADDR, 4, @T47_ANGLES[0], 2);
    Pin('type 48 sprites', T48_TABLE_ADDR, 4, @T48_SPRITES[0], 4);
    Pin('type 49 sprites', T49_TABLE_ADDR, 4, @T49_SPRITES[0], 4);
    Pin('type 49 range', T49_RANGE_ADDR, 3, @T49_RANGE[0], 3);
    Pin('type 49 rest', T49_REST_ADDR, 3, @T49_REST[0], 3);
    Pin('type 50 sprites', T50_TABLE_ADDR, 6, @T50_SPRITES[0], 6);
    Pin('type 50 patrol', T50_PATROL_ADDR, 3, @T50_PATROL[0], 3);
    Pin('type 50 hold', T50_HOLD_ADDR, 3, @T50_HOLD[0], 3);
    Pin('type 51 sprites', T51_TABLE_ADDR, 4, @T51_SPRITES[0], 4);
    Pin('type 52 hp', T52_HP_ADDR, 3, @T52_HP[0], 3);
    Pin('type 52 count', T52_COUNT_ADDR, 3, @T52_COUNT[0], 3);
    Pin('type 52 speed', T52_SPEED_ADDR, 3, @T52_SPEED[0], 3);
    Pin('type 52 timing', T52_TIMING_ADDR, 3, @T52_TIMING[0], 3);
    Pin('type 52 sprites', T52_TABLE_ADDR, 8, @T52_SPRITES[0][0], 8);
    Pin('type 53 sprites', T53_TABLE_ADDR, 10, @T53_SPRITES[0][0], 10);
    Pin('type 54 sprites', T54_TABLE_ADDR, 2, @T54_SPRITES[0], 2);
    Pin('type 54 hp', T54_HP_ADDR, 3, @T54_HP[0], 3);
    Pin('type 54 hops', T54_HOP_ADDR, 8, @T54_HOP[0][0], 8);
    Pin('type 55 fly sprites', T55_FLY_TABLE_ADDR, 8, @T55_FLY_SPRITES[0], 8);
    Pin('type 55 trail sprites', T55_TRAIL_TABLE_ADDR, 7,
        @T55_TRAIL_SPRITES[0], 7);
    Pin('type 56 sprites', T56_TABLE_ADDR, 3, @T56_SPRITES[0], 3);
    Pin('type 56 skew', T56_SKEW_ADDR, 3, @T56_SKEW[0], 3);
    Pin('type 56 count', T56_COUNT_ADDR, 3, @T56_COUNT[0], 3);
    Pin('type 56 speed', T56_SPEED_ADDR, 3, @T56_SPEED[0], 3);
    { three ints - frame 2 is the dormant sprite, 0 and 1 the awake pair }
    Pin('type 57 v0 sprites', T57_V0_TABLE_ADDR, 4, @T57_V0_SPRITES[0], 4);
    Pin('type 57 v1 sprites', T57_V1_TABLE_ADDR, 8, @T57_V1_SPRITES[0], 8);
    Pin('type 57 v2 sprites', T57_V2_TABLE_ADDR, 8, @T57_V2_SPRITES[0], 8);
    Pin('type 57 v3 sprites', T57_V3_TABLE_ADDR, 3, @T57_V3_SPRITES[0], 3);
    Pin('type 57 hatch', T57_V3_HATCH_ADDR, 3, @T57_V3_HATCH[0], 3);
    Pin('type 58 sprites', T58_TABLE_ADDR, 3, @T58_SPRITES[0], 3);
    Pin('type 59 sprites', T59_TABLE_ADDR, 6, @T59_SPRITES[0], 6);
    Pin('type 59 speed', T59_SPEED_ADDR, 3, @T59_SPEED[0], 3);
    Pin('type 60 sprites', T60_TABLE_ADDR, 8, @T60_SPRITES[0][0], 8);
    Pin('type 60 speed', T60_SPEED_ADDR, 3, @T60_SPEED[0], 3);
    Pin('type 60 rage', T60_RAGE_ADDR, 3, @T60_RAGE[0], 3);
    Pin('type 60 turn', T60_TURN_ADDR, 3, @T60_TURN[0], 3);
    Pin('type 61 sprites', T61_TABLE_ADDR, 4, @T61_SPRITES[0], 4);
    Pin('type 61 speed', T61_SPEED_ADDR, 3, @T61_SPEED[0], 3);
    Pin('type 62 sprites', T62_TABLE_ADDR, 4, @T62_SPRITES[0][0], 4);
    Pin('type 62 speed', T62_SPEED_ADDR, 3, @T62_SPEED[0], 3);
    Pin('type 63 sprites', T63_TABLE_ADDR, 8, @T63_SPRITES[0][0], 8);
    Pin('type 63 shot speed', T63_SHOT_SPD_ADDR, 3, @T63_SHOT_SPD[0], 3);
    Pin('type 63 fire at', T63_FIRE_AT_ADDR, 3, @T63_FIRE_AT[0], 3);
    Pin('type 63 recover', T63_RECOVER_ADDR, 3, @T63_RECOVER[0], 3);
    Pin('type 63 cooldown', T63_COOLDOWN_ADDR, 3, @T63_COOLDOWN[0], 3);
    Pin('type 64 sprites', T64_TABLE_ADDR, 2, @T64_SPRITES[0], 2);
    Pin('type 64 wait', T64_WAIT_ADDR, 3, @T64_WAIT[0], 3);
    Pin('type 64 rest', T64_REST_ADDR, 3, @T64_REST[0], 3);
    Pin('type 64 rise', T64_RISE_ADDR, 3, @T64_RISE[0], 3);
    Pin('type 65 sprites', T65_TABLE_ADDR, 2, @T65_SPRITES[0], 2);
    Pin('type 65 hops', T65_HOP_ADDR, 2, @T65_HOP[0], 2);
    Pin('type 66 anchor sprites', T66_V0_TABLE_ADDR, 3, @T66_V0_SPRITES[0], 3);
    Pin('type 66 satellite sprites', T66_V1_TABLE_ADDR, 2,
        @T66_V1_SPRITES[0], 2);
    Pin('type 67 sprites', T67_TABLE_ADDR, 5, @T67_SPRITES[0], 5);
    Pin('type 67 cooldown', T67_COOLDOWN_ADDR, 3, @T67_COOLDOWN[0], 3);
    Pin('type 67 range', T67_RANGE_ADDR, 3, @T67_RANGE[0], 3);
    Pin('type 68 sprites', T68_TABLE_ADDR, 8, @T68_SPRITES[0], 8);
    Pin('type 68 insets', T68_INSET_ADDR, 8, @T68_INSET[0], 8);
    Pin('type 69 sprites', T69_TABLE_ADDR, 4, @T69_SPRITES[0], 4);
    Pin('type 70 v0 sprites', T70_V0_TABLE_ADDR, 5, @T70_V0_SPRITES[0], 5);
    Pin('type 70 v1 sprites', T70_V1_TABLE_ADDR, 5, @T70_V1_SPRITES[0], 5);
    Pin('type 71 sprites', T71_TABLE_ADDR, 12, @T71_SPRITES[0][0], 12);
    Pin('type 71 walk', T71_WALK_ADDR, 3, @T71_WALK[0], 3);
    Pin('type 71 rest', T71_REST_ADDR, 3, @T71_REST[0], 3);
    Pin('type 72 faller sprites', T72_V0_TABLE_ADDR, 8, @T72_V0_SPRITES[0], 8);
    Pin('type 72 flyer sprites', T72_V1_TABLE_ADDR, 16, @T72_V1_SPRITES[0], 16);
    Pin('type 72 speed', T72_SPEED_ADDR, 3, @T72_SPEED[0], 3);
    Pin('type 72 trail rate', T72_TRAIL_ADDR, 3, @T72_TRAIL[0], 3);
    Pin('type 72 trail sprites', T72_V2_TABLE_ADDR, 4, @T72_V2_SPRITES[0], 4);
    Pin('type 73 sprites', T73_TABLE_ADDR, 5, @T73_SPRITES[0], 5);
    Pin('type 73 wait', T73_WAIT_ADDR, 3, @T73_WAIT[0], 3);
    Pin('type 73 charge', T73_CHARGE_ADDR, 3, @T73_CHARGE[0], 3);
    Pin('type 74 charge sprites', T74_V0_TABLE_ADDR, 5, @T74_V0_SPRITES[0], 5);
    Pin('type 74 shot sprites', T74_V1_TABLE_ADDR, 4, @T74_V1_SPRITES[0], 4);
    Pin('type 74 skew', T74_SKEW_ADDR, 3, @T74_SKEW[0], 3);
    Pin('type 74 count', T74_COUNT_ADDR, 3, @T74_COUNT[0], 3);
    Pin('type 74 speed', T74_SPEED_ADDR, 3, @T74_SPEED[0], 3);
    Pin('type 75 sprites', T75_TABLE_ADDR, 8, @T75_SPRITES[0], 8);
    Pin('type 76 sprites', T76_TABLE_ADDR, 2, @T76_SPRITES[0], 2);
    Pin('type 76 period', T76_PERIOD_ADDR, 3, @T76_PERIOD[0], 3);
    Pin('type 76 speed', T76_SPEED_ADDR, 3, @T76_SPEED[0], 3);
    { The final boss. Each phase's sprite row is exactly as wide as the
      highest frame that phase's own script can reach - the check below
      re-derives that from the action table, so the two readings have to keep
      agreeing. }
    Pin('type 77 phase 0-1', T77_P01_TABLE_ADDR, 20, @T77_P01_SPRITES[0][0], 20);
    Pin('type 77 phase 2', T77_P2_TABLE_ADDR, 28, @T77_P2_SPRITES[0][0], 28);
    Pin('type 77 phase 3', T77_P3_TABLE_ADDR, 26, @T77_P3_SPRITES[0][0], 26);
    Pin('type 77 phase 4', T77_P4_TABLE_ADDR, 12, @T77_P4_SPRITES[0][0], 12);
    Pin('type 77 phase 5', T77_P5_TABLE_ADDR, 16, @T77_P5_SPRITES[0][0], 16);
    Pin('type 77 phase 6', T77_P6_TABLE_ADDR, 2, @T77_P6_SPRITES[0], 2);
    Pin('type 77 hp', T77_HP_ADDR, 18, @T77_HP[0][0], 18);
    Pin('type 77 burst vx', T77_BURST_VX_ADDR, 6, @T77_BURST_VX[0], 6);
    Pin('type 77 burst vy', T77_BURST_VY_ADDR, 6, @T77_BURST_VY[0], 6);
    Pin('type 77 burst count', T77_BURST_ADDR, 3, @T77_BURST[0], 3);
    Pin('type 77 slam', T77_SLAM_ADDR, 4, @T77_SLAM[0], 4);
    Pin('type 77 lob', T77_SHOT_ADDR, 3, @T77_SHOT[0], 3);
    Pin('type 77 step', T77_STEP_ADDR, 36, @T77_STEP[0][0], 36);
    Pin('type 77 action', T77_ACTION_ADDR, 36, @T77_ACTION[0][0], 36);
    Pin('type 77 divisor', T77_DIVISOR_ADDR, 3, @T77_DIVISOR[0], 3);
    Pin('type 77 slam divisor', T77_SLAM_DIV_ADDR, 3, @T77_SLAM_DIV[0], 3);
    Pin('type 77 lob divisor', T77_SHOT_DIV_ADDR, 3, @T77_SHOT_DIV[0], 3);
    Pin('type 77 lob speed', T77_LOB_SPEED_ADDR, 3, @T77_LOB_SPEED[0], 3);
    Pin('type 78 idle sprite', T78_IDLE_TABLE_ADDR, 2, @T78_IDLE_SPRITES[0], 2);
    Pin('type 78 idle x', T78_IDLE_X_ADDR, 2, @T78_IDLE_X[0], 2);
    Pin('type 78 slam sprites', T78_SLAM_TABLE_ADDR, 8,
        @T78_SLAM_SPRITES[0][0], 8);
    Pin('type 78 slam x', T78_SLAM_X_ADDR, 8, @T78_SLAM_X[0][0], 8);
    Pin('type 78 slam y', T78_SLAM_Y_ADDR, 4, @T78_SLAM_Y[0], 4);
    Pin('type 78 lob sprites', T78_LOB_TABLE_ADDR, 6, @T78_LOB_SPRITES[0][0], 6);
    Pin('type 78 lob x', T78_LOB_X_ADDR, 6, @T78_LOB_X[0][0], 6);
    Pin('type 78 lob y', T78_LOB_Y_ADDR, 3, @T78_LOB_Y[0], 3);
    Pin('type 79 v0 sprites', T79_V0_TABLE_ADDR, 2, @T79_V0_SPRITES[0], 2);
    Pin('type 79 v0 x', T79_V0_X_ADDR, 2, @T79_V0_X[0], 2);
    Pin('type 79 v1 sprites', T79_V1_TABLE_ADDR, 2, @T79_V1_SPRITES[0], 2);
    Pin('type 79 v1 x', T79_V1_X_ADDR, 2, @T79_V1_X[0], 2);
    Pin('type 79 v1 y', T79_V1_Y_ADDR, 1, @T79_V1_Y[0], 1);
    Pin('type 79 v2 sprites', T79_V2_TABLE_ADDR, 2, @T79_V2_SPRITES[0], 2);
    Pin('type 79 v2 x', T79_V2_X_ADDR, 2, @T79_V2_X[0], 2);
    Pin('type 79 v2 y', T79_V2_Y_ADDR, 1, @T79_V2_Y[0], 1);
    Pin('type 79 v3 sprites', T79_V3_TABLE_ADDR, 4, @T79_V3_SPRITES[0][0], 4);
    Pin('type 79 v4 sprites', T79_V4_TABLE_ADDR, 4, @T79_V4_SPRITES[0], 4);
    Pin('type 79 v5 sprites', T79_V5_TABLE_ADDR, 6, @T79_V5_SPRITES[0], 6);
    Pin('type 80 v0 sprites', T80_V0_TABLE_ADDR, 3, @T80_V0_SPRITES[0], 3);
    Pin('type 80 v1 sprites', T80_V1_TABLE_ADDR, 4, @T80_V1_SPRITES[0], 4);
    Pin('hit sounds', HIT_SOUND_ADDR, 4, @HIT_SOUNDS[0], HIT_SOUND_COUNT);
    Log.Add(Format('the whole sweep - %d tables, extent and values: %d wrong',
      [Swept, Bad]));
    Inc(Result, Bad);

    { --- the unit initialization table, re-derived from the binary --------
      UnitInit.pas claims fifteen compiler-emitted unit init/finalize pairs,
      all of one shape, each touching a counter that nothing reads. Every
      part of that is checked here rather than trusted, because eight of
      those addresses spent a long time in the backlog looking like unread
      game logic and the claim that they are not is the whole point. }
    Bad := 0;
    if not FileExists(ExeName) then Inc(Bad);
    SetLength(Code, CODE_HI - CODE_LO);
    Exe.Position := Int64(CODE_LO) - CODE_VA_BIAS;
    Exe.ReadBuffer(Code[0], Length(Code));
    for I := 0 to UNIT_INIT_COUNT - 1 do
    begin
      Init := UNIT_INIT_ADDR[I];
      Ctr  := UNIT_INIT_COUNTER[I];

      { the initialization half: `inc dword ptr [counter]` at +0x11 }
      Exe.Position := Int64(Init) + $11 - CODE_VA_BIAS;
      Exe.ReadBuffer(Op, 2);
      Exe.ReadBuffer(Held, 4);
      if (Op[0] <> $FF) or (Op[1] <> $05) or (Held <> Ctr) then
      begin
        Log.Add(Format('  unit %d at 0x%.6X: not an inc of 0x%.6X',
          [I, Init, Ctr]));
        Inc(Bad);
      end;

      { the finalization half: `sub dword ptr [counter], 1` then `ret` }
      Exe.Position := Int64(Init) + UNIT_INIT_STUB_GAP - CODE_VA_BIAS;
      Exe.ReadBuffer(Op, 2);
      Exe.ReadBuffer(Held, 4);
      Exe.ReadBuffer(Op2, 2);
      if (Op[0] <> $83) or (Op[1] <> $2D) or (Held <> Ctr)
         or (Op2[0] <> $01) or (Op2[1] <> $C3) then
      begin
        Log.Add(Format('  unit %d at 0x%.6X: finalization is not a dec of '
          + '0x%.6X followed by ret', [I, Init + UNIT_INIT_STUB_GAP, Ctr]));
        Inc(Bad);
      end;

      { and the counter is WRITE-ONLY: its address appears in the code
        section exactly twice, which is those two instructions and nothing
        else. This is the claim that makes the stubs safe to ignore. }
      N := 0;
      for J := 0 to Length(Code) - 4 do
        if PCardinal(@Code[J])^ = Ctr then Inc(N);
      if N <> 2 then
      begin
        Log.Add(Format('  counter 0x%.6X is referenced %d times in the code '
          + 'section, not 2 - something reads it', [Ctr, N]));
        Inc(Bad);
      end;
    end;

    { the table itself ends where UnitInit.pas says, and its last entry is a
      pair like all the others }
    Exe.Position := Int64(UNIT_INIT_TABLE_END) - CODE_VA_BIAS;
    Exe.ReadBuffer(Held, 4);
    if Held <> 0 then
    begin
      Log.Add(Format('  the init table does not terminate at 0x%.6X',
        [UNIT_INIT_TABLE_END]));
      Inc(Bad);
    end;
    Exe.Position := Int64(UNIT_INIT_TABLE_END) - 8 - CODE_VA_BIAS;
    Exe.ReadBuffer(Held, 4);
    Exe.ReadBuffer(V, 4);
    if (Held - V <> UNIT_INIT_STUB_GAP)
       or (V <> UNIT_INIT_ADDR[UNIT_INIT_COUNT - 1]) then
    begin
      Log.Add('  the last table entry is not the last recorded unit');
      Inc(Bad);
    end;

    if Bad = 0 then
      Log.Add(Format('%d unit init/finalize pairs, all one shape, every '
        + 'counter write-only', [UNIT_INIT_COUNT]));
    Inc(Result, Bad);

    { --- the final boss's rows are as wide as its script needs -------------
      Two facts pinned independently: the sprite row widths come from the
      binary's pointer layout, and the reachable frames come from the action
      table's own values. Nothing connects them except the claim in
      EntityHandlers.pas that each phase's row is exactly as wide as the
      highest frame that phase's script can reach. That is checked here.

      HIGHEST_FRAME_OF maps each action to the top frame it can produce; the
      state-1 idle contributes 1 to every phase. Phase 0 is exempt because it
      SHARES phase 1's table and therefore has slack. }
    Bad := 0;
    for I := 0 to T77_PHASES - 1 do
    begin
      Got := 1;                          { the idle animation, frames 0..1 }
      for J := 0 to T77_STEPS - 1 do
      begin
        case T77_ACTION[I][J] of
          0, 2: K := 1;
          3, 7: K := 5;
          4:    K := 9;
          5:    K := 12;
          6:    K := 13;
          8:    K := 7;
        else
          K := -1;
          Log.Add(Format('  type 77 phase %d step %d: unknown action %d',
            [I, J, T77_ACTION[I][J]]));
          Inc(Bad);
        end;
        if K > Got then Got := K;
      end;

      case I of
        0: N := High(T77_P01_SPRITES[0]);
        1: N := High(T77_P01_SPRITES[0]);
        2: N := High(T77_P2_SPRITES[0]);
        3: N := High(T77_P3_SPRITES[0]);
        4: N := High(T77_P4_SPRITES[0]);
      else N := High(T77_P5_SPRITES[0]);
      end;

      if I = 0 then
      begin
        if Got > N then
        begin
          Log.Add(Format('  type 77 phase 0 reaches frame %d, past the %d it '
            + 'shares with phase 1', [Got, N]));
          Inc(Bad);
        end;
      end
      else if Got <> N then
      begin
        Log.Add(Format('  type 77 phase %d reaches frame %d but its row ends '
          + 'at %d', [I, Got, N]));
        Inc(Bad);
      end;
    end;
    if Bad = 0 then
      Log.Add('type 77: five of six phase rows end exactly where the script '
        + 'stops reaching, and phase 0 fits inside phase 1''s');
    Inc(Result, Bad);

    { --- claims of the form "these two tables hold the same numbers" ------
      Each table above is pinned to its own address, so these do not re-check
      the values. What they check is the RELATIONSHIP, which is stated in
      prose in EntityHandlers.pas and would otherwise rot silently if either
      side were ever corrected. }
    Bad := 0;
    for I := 0 to 2 do
    begin
      if T52_HP[I] <> T54_HP[I] then Inc(Bad);
      if T56_SKEW[I]  <> T74_SKEW[I]  then Inc(Bad);
      if T56_COUNT[I] <> T74_COUNT[I] then Inc(Bad);
      if T56_SPEED[I] <> T74_SPEED[I] then Inc(Bad);
    end;
    if Bad <> 0 then
      Log.Add(Format('FAILED: %d duplicated-table claims no longer hold', [Bad]))
    else
      Log.Add('the two boss hp tables and the two fan tables still agree');
    Inc(Result, Bad);

    { A sweep that checked nothing would also report zero wrong. }
    if Swept < 80 then
    begin
      Log.Add('FAILED: the sweep is too small to be the whole set');
      Inc(Result);
    end;


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

{ --- Entity_TouchPickup / Entity_TouchHeal @ 0x00458274 / 0x00458490 -----

  The Mana Stone's own arithmetic. The interesting boundary is that the
  counter goes up BEFORE the target is compared, so a stone that lands you
  exactly on the target counts as reaching it - which is the difference
  between < and <= and is worth a case of its own. }
function TestTouchHandlers(Log: TStringList): Integer;
var
  W: TCountingWorld;
  Pool: TEntityPool;
  P: TPlayerState;
  Slot, Fx: Integer;

  procedure Fresh(Variant, Counter, TargetIdx: Integer);
  begin
    Pool.Clear;
    FillChar(P, SizeOf(P), 0);
    P.Counter := Counter;
    P.TargetIndex := TargetIdx;
    P.Lives := 1;
    P.MaxLives := 3;
    Slot := Pool.Spawn(EKIND_MINOR, 5, 0, 0);
    Pool.SetField(Slot, EF_VARIANT, Variant);
    Pool.SetField(Slot, EF_SPRITE, SPRITE_NONE);
    Pool.SetField(Slot, EF_EVENT_ID, 7);
    W.Sounds := 0;
    W.LastSound := -1;
    W.ProgressSet := '';
    W.FlagFor := 42;
  end;

  function EffectVariant: Integer;
  var
    I: Integer;
  begin
    Result := -1;
    for I := 0 to ENTITY_COUNT - 1 do
      if Pool.Alive[I] and (Pool.Field(I, EF_TYPE) = PICKUP_EFFECT_TYPE) then
        Exit(Pool.Field(I, EF_VARIANT));
  end;

begin
  Result := 0;
  Log.Add('');
  Log.Add('--- Entity_TouchPickup / Entity_TouchHeal ---');
  Pool := TEntityPool.Create;
  W := TCountingWorld.Create;
  try
    W.Pool := Pool;

    { A small stone is worth one, a large one ten, and neither reaches the
      first goal of 20 from zero. }
    Fresh(0, 0, 0);
    EntityTouchPickup(Pool.Entity(Slot)^, P, W);
    Fx := EffectVariant;
    Log.Add(Format('small stone: counter %d, sound %d (%s), effect variant %d, '
      + 'flags [%s]', [P.Counter, W.LastSound, SoundNames[W.LastSound], Fx,
      Trim(W.ProgressSet)]));
    if P.Counter <> MANA_SMALL then
    begin
      Log.Add('FAILED: a variant 0 stone is worth one');
      Inc(Result);
    end;
    if W.LastSound <> SND_GET01 then
    begin
      Log.Add('FAILED: a small stone is get01');
      Inc(Result);
    end;
    if Fx <> PICKUP_FX_NORMAL then
    begin
      Log.Add('FAILED: the effect should be the plain one');
      Inc(Result);
    end;
    if Trim(W.ProgressSet) <> '42' then
    begin
      Log.Add('FAILED: the event''s progress flag should be set');
      Inc(Result);
    end;
    if P.MaxLives <> 3 then
    begin
      Log.Add('FAILED: no level-up was due');
      Inc(Result);
    end;

    Fresh(1, 0, 0);
    EntityTouchPickup(Pool.Entity(Slot)^, P, W);
    if (P.Counter <> MANA_LARGE) or (W.LastSound <> SND_GET02) then
    begin
      Log.Add('FAILED: a variant 1 stone is worth ten, and is get02');
      Inc(Result);
    end;

    { EXACTLY reaching the target counts, because the counter is raised
      before the comparison. One below it does not. }
    Fresh(0, MANA_TARGETS[0] - 1, 0);
    EntityTouchPickup(Pool.Entity(Slot)^, P, W);
    Log.Add(Format('stone landing exactly on goal %d: lives %d/%d, target now '
      + '%d, sound %s, effect %d',
      [MANA_TARGETS[0], P.Lives, P.MaxLives, P.TargetIndex,
       SoundNames[W.LastSound], EffectVariant]));
    if (P.TargetIndex <> 1) or (P.MaxLives <> 4) or (P.Lives <> 4) then
    begin
      Log.Add('FAILED: reaching the goal raises the maximum and refills');
      Inc(Result);
    end;
    if W.LastSound <> SND_POWER02 then
    begin
      Log.Add('FAILED: a level-up is power02');
      Inc(Result);
    end;
    if EffectVariant <> PICKUP_FX_LEVELUP then
    begin
      Log.Add('FAILED: the effect should be the level-up one');
      Inc(Result);
    end;

    Fresh(0, MANA_TARGETS[0] - 2, 0);
    EntityTouchPickup(Pool.Entity(Slot)^, P, W);
    if P.TargetIndex <> 0 then
    begin
      Log.Add('FAILED: one short of the goal is not reaching it');
      Inc(Result);
    end;

    { The heal refills and does nothing else to the maximum. }
    Fresh(0, 5, 0);
    EntityTouchHeal(Pool.Entity(Slot)^, P, W);
    Log.Add(Format('heal: lives %d/%d, counter %d, sound %s, effect %d',
      [P.Lives, P.MaxLives, P.Counter, SoundNames[W.LastSound],
       EffectVariant]));
    if (P.Lives <> 3) or (P.MaxLives <> 3) then
    begin
      Log.Add('FAILED: a heal refills to the maximum and does not raise it');
      Inc(Result);
    end;
    if P.Counter <> 5 then
    begin
      Log.Add('FAILED: a heal is not a mana stone');
      Inc(Result);
    end;
    if (W.LastSound <> SND_KACHI02) or (EffectVariant <> PICKUP_FX_HEAL) then
    begin
      Log.Add('FAILED: the heal has its own sound and effect variant');
      Inc(Result);
    end;

    { Past the end of the goal table nothing can be reached. }
    if ManaTarget(MANA_TARGET_COUNT) <> MaxInt then
    begin
      Log.Add('FAILED: past the table the goal must be unreachable');
      Inc(Result);
    end;
  finally
    W.Free;
    Pool.Free;
  end;
end;

{ --- Entity_SolidCollideX/Y @ 0x00456B4C / 0x00456E0C --------------------

  Three asymmetries between the two sweeps are the whole point of testing
  these, and each has a case below:

    softness is PER AXIS - kind 1 is soft in X, kind 2 is soft in Y
    the Y sweep has NO zero-delta guard, so resting on a platform still
      reports a collision
    landing on top writes PushX as well as PushY, which is what carries a
      rider along with a moving platform

  Positions are placed one pixel apart on purpose: the push is then exactly
  one pixel in 1/32 units, which is a number that can be predicted by hand
  rather than read off the implementation. }
function TestSolidCollide(Log: TStringList): Integer;
const
  EXT = 20;
var
  W: TCountingWorld;
  Pool: TEntityPool;
  Subject, Solid: Integer;

  procedure Place(Slot, PxX, PxY, SolidKind: Integer);
  begin
    Pool.SetField(Slot, EF_POS_X, POSITION_BIAS + PxX * 32);
    Pool.SetField(Slot, EF_POS_Y, POSITION_BIAS + PxY * 32);
    Pool.SetField(Slot, EF_EXTENT_X, EXT);
    Pool.SetField(Slot, EF_EXTENT_Y, EXT);
    Pool.SetField(Slot, EF_HITBOX_INSET_X, 0);
    Pool.SetField(Slot, EF_HITBOX_INSET_Y, 0);
    Pool.SetField(Slot, EF_SOLID, SolidKind);
    Pool.SetField(Slot, EF_EVENT_ID, -1);
  end;

  procedure Reset(SolidKind: Integer);
  begin
    Pool.Clear;
    Subject := Pool.Spawn(EKIND_SINGLE, 1, 0, 0);      { slot 0 }
    Solid := Pool.Spawn(EKIND_MINOR, 2, 0, 0);
    Place(Subject, 100, 100, 0);
    Place(Solid, 120, 120, SolidKind);
    W.PushX := 0;
    W.PushY := 0;
    W.OnTopOfSolid := False;
  end;

begin
  Result := 0;
  Log.Add('');
  Log.Add('--- Entity_SolidCollideX/Y ---');
  Pool := TEntityPool.Create;
  W := TCountingWorld.Create;
  try
    W.Pool := Pool;

    { Moving one pixel into a solid one pixel away pushes back one pixel. }
    Reset(3);
    Place(Solid, 120, 100, 3);
    if not W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: a solid one pixel away should block');
      Inc(Result);
    end;
    Log.Add(Format('blocked moving right: PushX %d (1/32 px)', [W.PushX]));
    if W.PushX <> -32 then
    begin
      Log.Add('FAILED: want a one-pixel push back, -32');
      Inc(Result);
    end;

    { A zero delta does nothing on X ...

      The solid is at 119 so the boxes ALREADY OVERLAP without moving. At 120
      they merely touch and the sweep would answer False whether the guard
      existed or not - which is exactly how a first version of this case let a
      mutation that deleted the guard survive. }
    Reset(3);
    Place(Solid, 119, 100, 3);
    if W.SolidCollideX(Pool.Entity(Subject)^, 0, False) then
    begin
      Log.Add('FAILED: the X sweep should ignore a zero delta');
      Inc(Result);
    end;
    if not W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: ... but a non-zero delta must still see that solid');
      Inc(Result);
    end;

    { ... but the Y sweep has no such guard, which is how resting on a
      platform keeps reporting one.

      The solid sits at 119, not 120, so the boxes genuinely OVERLAP with no
      movement at all. At 120 they exactly touch, and RectOverlap compares
      with a strict <, so touching is not overlapping - a first version of
      this case put them at 120 and failed for that reason rather than for
      the one it was testing. }
    Reset(3);
    Place(Solid, 100, 119, 3);
    if not W.SolidCollideY(Pool.Entity(Subject)^, 0, False) then
    begin
      Log.Add('FAILED: the Y sweep must still act on a zero delta');
      Inc(Result);
    end;

    { Landing on top: within tolerance it marks the ride and carries the
      rider along with the platform AND with this frame's scroll. }
    Reset(3);
    Place(Solid, 100, 120, 3);
    W.Layer.DeltaX := 64;                { two pixels of scroll }
    W.SolidCollideY(Pool.Entity(Subject)^, 32, False);
    Log.Add(Format('landed: onTop %d, ridden %d, PushY %d, PushX %d',
      [Ord(W.OnTopOfSolid), Pool.Field(Solid, EF_RIDDEN), W.PushY, W.PushX]));
    if not W.OnTopOfSolid then
    begin
      Log.Add('FAILED: within 8 pixels of the top should count as on top');
      Inc(Result);
    end;
    if Pool.Field(Solid, EF_RIDDEN) <> 1 then
    begin
      Log.Add('FAILED: the platform should be marked ridden');
      Inc(Result);
    end;
    if W.PushY <> -32 then
    begin
      Log.Add('FAILED: want a one-pixel vertical push, -32');
      Inc(Result);
    end;
    if W.PushX <> 64 then
    begin
      Log.Add('FAILED: riding should carry the layer delta into PushX');
      Inc(Result);
    end;
    W.Layer.DeltaX := 0;

    { The on-top tolerance is EXCLUSIVE. Placed so the gap is exactly 8, which
      is the only distance that tells < from <=; every other case in this file
      sits at a gap of 1 and cannot see the difference. }
    Reset(3);
    Place(Solid, 100, 113, 3);
    W.SolidCollideY(Pool.Entity(Subject)^, 32, False);
    Log.Add(Format('gap of exactly %d: onTop %d (want 0)',
      [SOLID_TOP_TOLERANCE, Ord(W.OnTopOfSolid)]));
    if W.OnTopOfSolid then
    begin
      Log.Add('FAILED: a gap of exactly 8 is NOT on top - the test is < 8');
      Inc(Result);
    end;
    Reset(3);
    Place(Solid, 100, 114, 3);
    W.SolidCollideY(Pool.Entity(Subject)^, 32, False);
    if not W.OnTopOfSolid then
    begin
      Log.Add('FAILED: a gap of 7 IS on top');
      Inc(Result);
    end;

    { Softness is per axis. Kind 1 is soft in X and solid in Y; kind 2 the
      other way round. Nothing here is soft when SkipSoft is off. }
    Reset(SOLID_SOFT_IN_X);
    Place(Solid, 120, 100, SOLID_SOFT_IN_X);
    if W.SolidCollideX(Pool.Entity(Subject)^, 32, True) then
    begin
      Log.Add('FAILED: kind 1 should be soft in X');
      Inc(Result);
    end;
    if not W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: kind 1 still blocks X when SkipSoft is off');
      Inc(Result);
    end;

    Reset(SOLID_SOFT_IN_Y);
    Place(Solid, 100, 120, SOLID_SOFT_IN_Y);
    if W.SolidCollideY(Pool.Entity(Subject)^, 32, True) then
    begin
      Log.Add('FAILED: kind 2 should be soft in Y');
      Inc(Result);
    end;
    if not W.SolidCollideY(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: kind 2 still blocks Y when SkipSoft is off');
      Inc(Result);
    end;

    { And the pair is genuinely crossed over: kind 1 is NOT soft in Y. }
    Reset(SOLID_SOFT_IN_X);
    Place(Solid, 100, 120, SOLID_SOFT_IN_X);
    if not W.SolidCollideY(Pool.Entity(Subject)^, 32, True) then
    begin
      Log.Add('FAILED: kind 1 is soft in X only, not in Y');
      Inc(Result);
    end;

    { The air dash phases through EF_VULN_KIND $5C - the same fact
      Player_UpdateAirDash was written from. }
    Reset(3);
    Place(Solid, 120, 100, 3);
    Pool.SetField(Solid, EF_VULN_KIND, SOLID_PHASE_VULN);
    Pool.SetField(Subject, EF_STATE, SOLID_STATE_AIRDASH);
    if W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: the air dash should phase through vuln kind $5C');
      Inc(Result);
    end;
    Pool.SetField(Subject, EF_STATE, 0);
    if not W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: any other state is blocked by it');
      Inc(Result);
    end;

    { An entity never blocks itself. }
    Pool.Clear;
    Subject := Pool.Spawn(EKIND_MINOR, 2, 0, 0);
    Place(Subject, 100, 100, 3);
    if W.SolidCollideX(Pool.Entity(Subject)^, 32, False) then
    begin
      Log.Add('FAILED: an entity blocked itself');
      Inc(Result);
    end;
  finally
    W.Free;
    Pool.Free;
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

    { --- every arm in the jump table has a Pascal case --------------------
      The comment in EntityHandlers.pas used to say "the other N arms are
      untranslated" and was maintained by hand. Now that the count is zero
      the claim is worth checking rather than writing down: drive ONE entity
      of every armed type through EntityUpdateAll and require the
      fall-through counter to stay at zero. Table[] came out of akuji.exe's
      own jump table above, so the list of types being demanded is the
      binary's, not ours.

      The three types with no arm are demanded to fall through, which also
      proves the counter is wired up and the check is not vacuous. }
    Bad := 0;
    for I := 0 to ENTITY_TYPE_COUNT - 1 do
    begin
      Pool.Clear;
      Place($21, I, SPRITE_NONE, 160, 120);
      EntitiesUnhandled := 0;
      Run(GS_PLAY);
      if (Table[I] <> HANDLER_NO_ARM_TARGET) and (EntitiesUnhandled <> 0) then
      begin
        Log.Add(Format('  type %d has an arm at 0x%.6X but no case',
          [I, Table[I]]));
        Inc(Bad);
      end;
      if (Table[I] = HANDLER_NO_ARM_TARGET) and (EntitiesUnhandled = 0) then
      begin
        Log.Add(Format('  type %d has no arm but the case handled it', [I]));
        Inc(Bad);
      end;
    end;
    Log.Add('');
    if Bad = 0 then
      Log.Add(Format('all %d armed types reach a case, and the %d unarmed '
        + 'ones fall through', [ENTITY_TYPE_COUNT - NoArm, NoArm]))
    else
      Log.Add(Format('FAILED: %d types disagree with the jump table', [Bad]));
    Inc(Result, Bad);
    Pool.Clear;

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
    { Put the real one back, not nil - it is the default now. }
    EntityPlayerTouch := @PlayerTouch;
    EntityTakeProjectileHits := nil;
    S.Free;
    W.Free;
    Pool.Free;
  end;

  Inc(Result, TestSpawnDebris(Log));
  Inc(Result, TestDestroy(Log));
  Inc(Result, TestSolidCollide(Log));
  Inc(Result, TestTouchHandlers(Log));
  Inc(Result, TestTileCollide(Log, GameDir));
  Inc(Result, TestKillTiles(Log));
  Inc(Result, TestSpriteTables(Log, GameDir));
  Inc(Result, TestItemHandlers(Log));
  Inc(Result, TestEffectHandlers(Log));

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - the dispatcher matches the switch in the binary and behaves '
      + 'as read')
  else
    Log.Add('FAILED');
end;


{ ---------------------------------------------------------------------------
  --selftest-runner <gamedir> : the event interpreter, running.

  EventRunner.pas is the four functions that make a script HAPPEN. Nothing else
  in this project exercised them: --selftest-script proves the grammar parses,
  which is a different claim entirely. A parser agreeing with itself says
  nothing about whether the machine that consumes it steps, waits and branches
  the way the original's does.

  What makes this checkable without a renderer is that the twelve logic
  sub-opcodes are implemented outright and the six presentation ones go through
  TEventHost. Put a recording host underneath and the control flow becomes
  fully observable: which lines were shown, in what order, whether the save
  actually happened.

  ## The save point is the whole system in one record

  All 43 stages that have one carry a byte-identical Devil Statue:

      1,0000,0000,tx,ty,0027-*,0000-03-0000/0003-13/0003-03-0001

  Three steps. Show line 0; if flag 3 is set, save; if flag 3 is set, show
  line 1. And line 0 of every one of those stages' tk files is

      Will you save the game? \w

  where \w is the yes/no prompt. So Progress[3] IS the answer, and the two
  guarded steps are the yes branch. That is what "Progress[1..4] are scratch"
  means in practice, and the data says something much sharper than the note
  did: of the 86 alternatives in the whole shipped set that guard on a scratch
  flag, all 86 guard on flag 3 specifically, and every one has a \w prompt
  earlier in its own program. 86 of 86, no exceptions. Flags 1, 2 and 4 are
  written only by sub-op 6, which no shipped event uses.

  The converse holds 43 times out of 44. The exception is stage 4's

      1,0000,0000,0004,0006,0016-*,0000-03-0000

  a type-16 sign - the plain read-a-plaque entity, 62 of them in the game -
  whose one step shows line 0 of tk004. tk004 has three lines and the statue
  owns the first two, so this sign asks "Will you save the game?", takes an
  answer and stops. It is the only one of the 62 signs pointing at a \w line.
  Left alone: this reproduces the shipped data, it does not correct it.
  --------------------------------------------------------------------------- }

type
  { A host that writes down what it was asked to do, so the control flow can be
    asserted on rather than merely observed not to crash. }
  TTraceHost = class(TEventHost)
  public
    Trace: TStringList;
    Saves: Integer;
    Fading: Boolean;      { what FadeBusy answers }
    constructor Create;
    destructor Destroy; override;
    procedure ShowLine(Index: Integer); override;
    procedure PlaySound(Id: Integer); override;
    procedure PlayMusic(Track: Integer; Loop: Boolean); override;
    procedure SetTile(X, Y, Tile: Integer); override;
    procedure DestroyEventEntity(EventId: Integer); override;
    procedure SetEventEntityState(EventId, Value: Integer); override;
    procedure LoadStage(Stage, PlayerTileX, PlayerTileY,
                        CamTileX, CamTileY: Integer); override;
    procedure WarpPlayer(PlayerTileX, PlayerTileY,
                         CamTileX, CamTileY: Integer); override;
    procedure SoulGet; override;
    procedure SubMode; override;
    procedure SaveGame(var P: TPlayerState); override;
    procedure StartFade(Out_: Boolean); override;
    function FadeBusy: Boolean; override;
  end;

constructor TTraceHost.Create;
begin
  inherited Create;
  Trace := TStringList.Create;
end;

destructor TTraceHost.Destroy;
begin
  Trace.Free;
  inherited Destroy;
end;

procedure TTraceHost.ShowLine(Index: Integer);
begin Trace.Add(Format('line %d', [Index])); end;
procedure TTraceHost.PlaySound(Id: Integer);
begin Trace.Add(Format('sound %d', [Id])); end;
procedure TTraceHost.PlayMusic(Track: Integer; Loop: Boolean);
begin Trace.Add(Format('music %d', [Track])); end;
procedure TTraceHost.SetTile(X, Y, Tile: Integer);
begin Trace.Add(Format('tile %d,%d=%d', [X, Y, Tile])); end;
procedure TTraceHost.DestroyEventEntity(EventId: Integer);
begin Trace.Add(Format('destroy %d', [EventId])); end;
procedure TTraceHost.SetEventEntityState(EventId, Value: Integer);
begin Trace.Add(Format('state %d=%d', [EventId, Value])); end;
procedure TTraceHost.LoadStage(Stage, PlayerTileX, PlayerTileY,
                               CamTileX, CamTileY: Integer);
begin Trace.Add(Format('stage %d at %d,%d cam %d,%d',
  [Stage, PlayerTileX, PlayerTileY, CamTileX, CamTileY])); end;
procedure TTraceHost.WarpPlayer(PlayerTileX, PlayerTileY,
                                CamTileX, CamTileY: Integer);
begin Trace.Add(Format('warp %d,%d cam %d,%d',
  [PlayerTileX, PlayerTileY, CamTileX, CamTileY])); end;
procedure TTraceHost.SoulGet;
begin Trace.Add('soul'); end;
procedure TTraceHost.SubMode;
begin Trace.Add('submode'); end;
procedure TTraceHost.SaveGame(var P: TPlayerState);
begin Trace.Add('save'); Inc(Saves); end;
procedure TTraceHost.StartFade(Out_: Boolean);
begin Trace.Add(Format('fade %d', [Ord(Out_)])); end;
function TTraceHost.FadeBusy: Boolean;
begin Result := Fading; end;

{ A fresh player state with the session flags Game_StartOrLoad would have
  applied - Progress[0] := 1 above all, which every 0000- default depends on. }
procedure FreshPlayer(out P: TPlayerState);
begin
  InitNewGame(P, 0);
  ApplySessionFlags(P, 0);
end;

{ Find the first opcode-4 record in the given stage. -1 if none - most stages
  have none at all: the nine puzzle checkers live in stages 14, 20, 31, 37, 48,
  57, 58, 60 and 61. }
function FindChecker(S: TEventScript): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to S.Count - 1 do
    if S[I].Opcode = EVOP_ALWAYS then
      Exit(I);
end;

{ Find the record carrying a particular program. -1 if none. }
function FindByProgram(S: TEventScript; const Prog: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to S.Count - 1 do
    if S[I].ParamB = Prog then
      Exit(I);
end;

{ Run frames until the script leaves GS_STATE_140 or the budget runs out.

  The dialogue box and the sub-mode screen are what advance their own steps in
  the game - Execute only starts them - so this stands in for both, finishing
  each instantly. Everything else advances itself. Returns the frame count, or
  -1 if the budget was exhausted, which is the "this program hangs" answer.

  The stand-in only fires when the frame did NOT advance on its own. Without
  that it skipped steps: a save step advances into a dialogue step, and asking
  "is the current sub-op a dialogue" straight after Execute then advanced past
  the dialogue before it had ever run. The save point's second line went
  missing and the trace assertion caught it. }
function DriveToEnd(R: TEventRunner; Host: TEventHost; S: TEventScript;
                    var P: TPlayerState; var GS: Integer;
                    Budget: Integer): Integer;
var
  Frames, Was: Integer;
begin
  Frames := 0;
  while (GS = GS_STATE_140) and (Frames < Budget) do
  begin
    Was := R.StepIndex;
    R.Execute(Host, S, P, GS);
    Inc(Frames);
    if (R.StepIndex = Was)
       and ((R.CurrentSubOp = SUBOP_DIALOGUE)
            or (R.CurrentSubOp = SUBOP_SUBMODE)) then
      R.AdvanceStep(P, GS);
  end;
  if GS = GS_STATE_140 then
    Result := -1
  else
    Result := Frames;
end;

{ --- 1. the save point, both answers ------------------------------------- }

function TestSavePoint(Log: TStrings; const GameDir: string): Integer;
const
  STATUE = '0000-03-0000/0003-13/0003-03-0001';
var
  S: TEventScript;
  R: TEventRunner;
  H: TTraceHost;
  P: TPlayerState;
  GS, Idx, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then
    begin
      Log.Add('  ' + What);
      Inc(Bad);
    end;
  end;

begin
  Bad := 0;
  Log.Add('the Devil Statue, run end to end:');

  S := TEventScript.Create;
  R := TEventRunner.Create;
  H := TTraceHost.Create;
  try
    S.Load(GameDir, 2);
    Idx := FindByProgram(S, STATUE);
    if Idx < 0 then
    begin
      Log.Add('  FAILED: stage 2 has no save point - wrong game directory?');
      Result := 1;
      Exit;
    end;
    Want(S.Lines[0] = 'Will you save the game? \w',
         'line 0 of tk002 is not the save prompt: ' + S.Lines[0]);

    { --- the answer is NO --------------------------------------------- }
    FreshPlayer(P);
    { Set the scratch flag BEFORE starting, so that an Event_Begin which failed
      to clear it would run the yes branch and be caught here. }
    P.Progress[3] := 1;
    GS := GS_PLAY;
    R.StartEvent(S, Idx, 0, P, GS);

    Want(GS = GS_STATE_140, 'starting a script did not enter GS_STATE_140');
    Want(P.Progress[3] = 0, 'Event_Begin did not clear the scratch flag');
    Want(R.StepIndex = 0, Format('first step is %d, want 0', [R.StepIndex]));
    Want(R.CurrentStep = '0000-03-0000', 'first step chose ' + R.CurrentStep);
    Want(R.CurrentSubOp = SUBOP_DIALOGUE,
         Format('first sub-op is %d, want 3', [R.CurrentSubOp]));

    R.Execute(H, S, P, GS);
    Want(H.Trace.CommaText = '"line 0"',
         'the prompt was not shown once: ' + H.Trace.CommaText);
    Want(R.StepIndex = 0, 'the dialogue step advanced by itself');

    { A second frame while the box is up must not show it again. }
    R.Execute(H, S, P, GS);
    Want(H.Trace.Count = 1, 'the prompt was shown twice: ' + H.Trace.CommaText);

    { The box closes on NO, so flag 3 stays clear; the box is what advances. }
    R.AdvanceStep(P, GS);
    Want(R.StepIndex = 1, 'the dialogue did not advance to step 1');
    Want(R.CurrentStep = '', 'step 1 ran with flag 3 clear: ' + R.CurrentStep);

    Want(DriveToEnd(R, H, S, P, GS, 32) >= 0, 'the no branch did not finish');
    Want(GS = GS_PLAY, 'running off the end did not return to GS_PLAY');
    Want(R.Finished, 'the runner does not report itself finished');
    Want(H.Saves = 0, 'the game was SAVED after answering no');
    Want(H.Trace.Count = 1,
         'the no branch did more than show the prompt: ' + H.Trace.CommaText);

    { --- the answer is YES -------------------------------------------- }
    H.Trace.Clear;
    H.Saves := 0;
    FreshPlayer(P);
    GS := GS_PLAY;
    R.StartEvent(S, Idx, 0, P, GS);
    R.Execute(H, S, P, GS);

    { The prompt's answer. It is the only thing that differs between the two
      runs, and it is one byte. }
    P.Progress[3] := 1;
    R.AdvanceStep(P, GS);

    Want(R.CurrentStep = '0003-13', 'the yes branch chose ' + R.CurrentStep);
    Want(R.CurrentSubOp = SUBOP_SAVE,
         Format('step 1 sub-op is %d, want 13', [R.CurrentSubOp]));

    Want(DriveToEnd(R, H, S, P, GS, 32) >= 0, 'the yes branch did not finish');
    Want(GS = GS_PLAY, 'the yes branch did not return to GS_PLAY');
    Want(H.Saves = 1, Format('the game was saved %d times, want 1', [H.Saves]));
    Want(H.Trace.CommaText = '"line 0",save,"line 1"',
         'the yes branch trace is ' + H.Trace.CommaText);
  finally
    H.Free;
    R.Free;
    S.Free;
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - one byte of Progress[3] is the whole branch, both ways');
end;

{ --- 2. Event_Begin's bookkeeping ---------------------------------------- }

function TestEventBegin(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  P: TPlayerState;
  GS, I, A, B, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('Event_Begin:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  try
    S.Load(GameDir, 2);
    A := -1; B := -1;
    for I := 0 to S.Count - 1 do
      if ClassifyParamB(S[I].ParamB) = pbProgram then
        if A < 0 then A := I else if B < 0 then B := I;
    if (A < 0) or (B < 0) then
    begin
      Log.Add('  FAILED: stage 2 has fewer than two programs');
      Result := 1;
      Exit;
    end;

    { Exactly Progress[1..4] are cleared, and nothing else. Flag 0 is the
      always-true default and clearing it would break every 0000- guard in the
      game; the world flags around the scratch block must survive too. }
    FreshPlayer(P);
    for I := 0 to 12 do
      P.Progress[I] := 1;
    P.Progress[1006] := 1;
    GS := GS_PLAY;
    R.StartEvent(S, A, 7, P, GS);

    for I := 1 to 4 do
      Want(P.Progress[I] = 0,
           Format('Progress[%d] survived Event_Begin', [I]));
    Want(P.Progress[0] = 1, 'Event_Begin cleared Progress[0], the default guard');
    for I := 5 to 12 do
      Want(P.Progress[I] = 1,
           Format('Event_Begin cleared Progress[%d], outside the scratch block', [I]));
    Want(P.Progress[1006] = 1, 'Event_Begin cleared a world flag');
    Want(R.EventId = A, 'Event_Begin did not record which event it started');
    Want(R.Arg = 7, 'Event_Begin did not record its argument');

    { One script at a time - and the lock IS the game state, not a flag. A
      second start while GS_STATE_140 must leave the first one untouched. }
    R.StartEvent(S, B, 0, P, GS);
    Want(R.EventId = A,
         Format('a second script started over the first: event %d', [R.EventId]));

    { Out of GS_STATE_140 the same call goes through. That is what says the
      guard is the state rather than an accident of the data. }
    GS := GS_PLAY;
    R.StartEvent(S, B, 0, P, GS);
    Want(R.EventId = B, 'a script would not start from GS_PLAY');
  finally
    R.Free;
    S.Free;
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - the scratch block is cleared, the world is not, '
      + 'and the state is the lock');
end;

{ --- 3. the backwards alternative scan ----------------------------------- }

function TestBackwardsScan(Log: TStrings; const GameDir: string): Integer;
const
  { A real shipped sign in stage 1: line 1 normally, line 3 once flag 1006 is
    set. Both alternatives are satisfiable at once, since flag 0 is always set,
    so this is exactly the case that tells the two scan directions apart. }
  TWO_WAY = '0000-03-0001.1006-03-0003';
var
  S: TEventScript;
  R: TEventRunner;
  H: TTraceHost;
  P: TPlayerState;
  GS, Idx, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('the alternative scan:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  H := TTraceHost.Create;
  try
    S.Load(GameDir, 1);
    Idx := FindByProgram(S, TWO_WAY);
    if Idx < 0 then
    begin
      Log.Add('  FAILED: stage 1 no longer carries ' + TWO_WAY);
      Result := 1;
      Exit;
    end;

    FreshPlayer(P);
    GS := GS_PLAY;
    R.StartEvent(S, Idx, 0, P, GS);
    Want(R.CurrentStep = '0000-03-0001',
         'with 1006 clear the step chose ' + R.CurrentStep);
    R.Execute(H, S, P, GS);
    Want(H.Trace.CommaText = '"line 1"', 'showed ' + H.Trace.CommaText);

    H.Trace.Clear;
    FreshPlayer(P);
    P.Progress[1006] := 1;
    GS := GS_PLAY;
    R.StartEvent(S, Idx, 0, P, GS);
    Want(R.CurrentStep = '1006-03-0003',
         'with 1006 set the step chose ' + R.CurrentStep
         + ' - a FORWARDS scan would take the 0000 default, which is why it is'
         + ' written first');
    R.Execute(H, S, P, GS);
    Want(H.Trace.CommaText = '"line 3"', 'showed ' + H.Trace.CommaText);

    { And a step none of whose guards hold does nothing and moves on. There is
      no such step in the shipped data with flag 0 always set, so it is built:
      clearing Progress[0] falsifies the default too. }
    FreshPlayer(P);
    P.Progress[0] := 0;
    GS := GS_PLAY;
    R.StartEvent(S, Idx, 0, P, GS);
    Want(R.CurrentStep = '',
         'a step with no satisfied guard chose ' + R.CurrentStep);
    H.Trace.Clear;
    Want(DriveToEnd(R, H, S, P, GS, 16) >= 0, 'an empty step did not advance');
    Want(H.Trace.Count = 0, 'an empty step did something: ' + H.Trace.CommaText);
    Want(GS = GS_PLAY, 'an all-empty program did not return to GS_PLAY');
  finally
    H.Free;
    R.Free;
    S.Free;
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - the LAST satisfied alternative wins, and none is not an error');
end;

{ --- 4. the waiting sub-opcodes ------------------------------------------ }

function TestWaiting(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  H: TTraceHost;
  P: TPlayerState;
  GS, I, Idx, Frames, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('the ops that span frames:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  H := TTraceHost.Create;
  try
    { --- sub-op 17: a wait of N lasts N + 1 frames --------------------
      Stage 14's checker is the simplest: two switches, then the wait. }
    S.Load(GameDir, 14);
    Idx := FindChecker(S);
    if Idx < 0 then
    begin
      Log.Add('  FAILED: stage 14 has no opcode-4 checker');
      Result := 1;
      Exit;
    end;

    { Drive it to the wait step by hand: set the flags its list wants so the
      first step passes, then count frames on the second. }
    FreshPlayer(P);
    P.Progress[4000] := 1;
    P.Progress[4001] := 1;
    GS := GS_PLAY;
    R.StartEvent(S, Idx, EVENT_BEGIN_FROM_SPAWN, P, GS);
    R.Execute(H, S, P, GS);       { the flag list, which advances }

    if R.CurrentSubOp <> SUBOP_WAIT then
      Log.Add(Format('  the checker did not reach its wait: sub-op %d, step %s',
        [R.CurrentSubOp, R.CurrentStep]))
    else
    begin
      Frames := 0;
      while (R.CurrentSubOp = SUBOP_WAIT) and (Frames < 64) do
      begin
        R.Execute(H, S, P, GS);
        Inc(Frames);
      end;
      { The argument is 000010 and the cursor is compared AFTER it increments,
        so the step ends on the eleventh frame, not the tenth. }
      Want(Frames = 11,
           Format('a wait of 10 took %d frames, want 11', [Frames]));
    end;

    { --- sub-op 0: the fade gates the load ---------------------------- }
    H.Trace.Clear;
    S.Load(GameDir, 2);
    Idx := -1;
    for I := 0 to S.Count - 1 do
      if (ClassifyParamB(S[I].ParamB) = pbProgram)
         and (Copy(S[I].ParamB, 6, 2) = '00') then
        Idx := I;
    if Idx < 0 then
      Log.Add('  FAILED: stage 2 has no program starting with a stage load')
    else
    begin
      FreshPlayer(P);
      GS := GS_PLAY;
      H.Fading := True;           { the fade is still running }
      R.StartEvent(S, Idx, 0, P, GS);
      R.Execute(H, S, P, GS);
      Want(H.Trace.CommaText = '"fade 1"',
           'the fade out was not started, or the load ran anyway: '
           + H.Trace.CommaText);
      Want(GS = GS_STATE_140, 'the stage loaded while the fade was still busy');
      R.Execute(H, S, P, GS);
      Want(H.Trace.Count = 1, 'the fade was started twice');

      H.Fading := False;          { the fade lands }
      R.Execute(H, S, P, GS);
      Want(GS = GS_STAGE_BEGIN,
           Format('after the fade the state is %d, want %d',
                  [GS, GS_STAGE_BEGIN]));
      Want(Pos('stage ', H.Trace.CommaText) > 0,
           'the stage was never loaded: ' + H.Trace.CommaText);
    end;
  finally
    H.Free;
    R.Free;
    S.Free;
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - the wait is inclusive and the fade really does gate the load');
end;

{ --- 5. the flag list, which is the whole of the nine puzzle checkers ----- }

function TestFlagList(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  H: TTraceHost;
  P: TPlayerState;
  Prog: TEventProgram;
  Cmd: TEventCommand;
  GS, I, J, Idx, Target, Count, Item, Checkers, Lists, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

  { Set every flag the list wants to the value it wants, except that item
    Except_ (or none, when it is -1) is set to the opposite. }
  procedure Arm(const C: TEventCommand; Except_: Integer);
  var
    K, Flag, Wanted: Integer;
  begin
    for K := 0 to C.Args[1] - 1 do
    begin
      Flag := C.Args[2 + K] mod 10000;
      Wanted := C.Args[2 + K] div 10000;
      if K = Except_ then
        Wanted := 1 - Wanted;
      P.Progress[Flag] := Wanted;
    end;
  end;

begin
  Bad := 0;
  Checkers := 0;
  Lists := 0;
  Log.Add('sub-op 15, the flag list:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  H := TTraceHost.Create;
  try
    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for Idx := 0 to S.Count - 1 do
      begin
        if S[Idx].Opcode <> EVOP_ALWAYS then
          Continue;
        Prog := ParseProgram(S[Idx].ParamB);
        if Length(Prog) = 0 then
          Continue;
        Inc(Checkers);
        Cmd := Prog[0].Alternatives[0];
        if Cmd.SubOp <> SUBOP_TEST_FLAGS then
        begin
          { Stage 58's checker is `1157-04-1158/1158-09-0032` - a plain set-flag
            behind a guard rather than a list. Drive it anyway: it is the only
            place in the shipped data where sub-op 4's effect is observable
            from a script alone, and without it a SET_FLAG that CLEARED its
            flag passed every check here. }
          if Cmd.SubOp = SUBOP_SET_FLAG then
          begin
            FreshPlayer(P);
            GS := GS_PLAY;
            R.StartEvent(S, Idx, EVENT_BEGIN_FROM_SPAWN, P, GS);
            R.Execute(H, S, P, GS);
            Want(P.Progress[Cmd.Args[0]] = 0,
                 Format('  stage %d: flag %d was set with guard %d clear',
                        [I, Cmd.Args[0], Cmd.Guard]));

            FreshPlayer(P);
            P.Progress[Cmd.Guard] := 1;
            GS := GS_PLAY;
            R.StartEvent(S, Idx, EVENT_BEGIN_FROM_SPAWN, P, GS);
            R.Execute(H, S, P, GS);
            Want(P.Progress[Cmd.Args[0]] = 1,
                 Format('  stage %d: guard %d set but flag %d did not go up',
                        [I, Cmd.Guard, Cmd.Args[0]]));

            { It sets its own forbidding flag - the property that does hold
              for all nine, and the one that retires this one. }
            Want(Cmd.Args[0] = S[Idx].BlockedBy,
                 Format('  stage %d: sets flag %d but its csv 2 is %d',
                        [I, Cmd.Args[0], S[Idx].BlockedBy]));
          end;
          Continue;
        end;
        Inc(Lists);
        Target := Cmd.Args[0];
        Count := Cmd.Args[1];

        { All conditions met: the target flag goes up. }
        FreshPlayer(P);
        Arm(Cmd, -1);
        GS := GS_PLAY;
        R.StartEvent(S, Idx, EVENT_BEGIN_FROM_SPAWN, P, GS);
        R.Execute(H, S, P, GS);
        Want(P.Progress[Target] = 1,
             Format('  stage %d: all %d conditions met but flag %d is clear',
                    [I, Count, Target]));

        { Any ONE condition wrong and it must not. Every item is tried, so an
          implementation that only read the first would fail here. }
        for J := 0 to Count - 1 do
        begin
          FreshPlayer(P);
          Arm(Cmd, J);
          GS := GS_PLAY;
          R.StartEvent(S, Idx, EVENT_BEGIN_FROM_SPAWN, P, GS);
          R.Execute(H, S, P, GS);
          Item := Cmd.Args[2 + J];
          Want(P.Progress[Target] = 0,
               Format('  stage %d: item %d (%.5d) wrong but flag %d went up',
                      [I, J, Item, Target]));
        end;
      end;
    end;
  finally
    H.Free;
    R.Free;
    S.Free;
  end;

  { Nine opcode-4 records in the whole game, of which EIGHT carry a flag list.

    EventScripts.pas said all nine were the same construction - flag list, set
    a flag, wait, sound 32, disable with sub-op 7 - and "nine of nine, no
    exceptions". This test is what found that wrong. Stage 58's is

        4,0000,1158,0001,0001,0020-*,1157-04-1158/1158-09-0032

    no list, no wait, and no sub-op 7. It sets 1158 when 1157 is already set,
    then plays the same sound 32. What retires it is the other mechanism: 1158
    is its own csv 2, so the next spawn sweep disables the record. The claim
    that survives is the one that always mattered - all nine set their own
    forbidding flag - and there turn out to be two ways of leaving.

    Pinning both counts is what stops a change that made ParseProgram return
    nothing from passing here vacuously. }
  if (Checkers <> 9) or (Lists <> 8) then
  begin
    Log.Add(Format('  FAILED: %d opcode-4 checkers carrying %d flag lists,'
      + ' want 9 and 8', [Checkers, Lists]));
    Inc(Bad);
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - all 8 flag lists, and every one of their conditions,'
      + ' tested both ways');
end;

{ --- 6. every shipped program runs to completion ------------------------- }

function TestEveryProgram(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  H: TTraceHost;
  P: TPlayerState;
  GS, I, J, Frames, Programs, Hung, Lines, Bad: Integer;
begin
  Bad := 0;
  Programs := 0; Hung := 0; Lines := 0;
  S := TEventScript.Create;
  R := TEventRunner.Create;
  H := TTraceHost.Create;
  try
    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for J := 0 to S.Count - 1 do
      begin
        if ClassifyParamB(S[J].ParamB) <> pbProgram then
          Continue;
        Inc(Programs);
        H.Trace.Clear;
        FreshPlayer(P);
        GS := GS_PLAY;
        R.StartEvent(S, J, 0, P, GS);
        { 4 steps at most, the longest wait is 11 frames, and every other op
          finishes in one. 64 is comfortable room and still catches a hang. }
        Frames := DriveToEnd(R, H, S, P, GS, 64);
        if Frames < 0 then
        begin
          Log.Add(Format('  stage %d event %d did not finish: %s  (stuck on %s)',
            [I, J, S[J].ParamB, R.CurrentStep]));
          Inc(Hung);
        end;
        Inc(Lines, H.Trace.Count);
      end;
    end;
  finally
    H.Free;
    R.Free;
    S.Free;
  end;

  Log.Add(Format('programs driven to completion: %d  (%d hung)',
    [Programs, Hung]));
  Log.Add(Format('host calls made:               %d', [Lines]));
  Inc(Bad, Hung);

  { --selftest-script counts 307 programs in the shipped data by an entirely
    separate route. Pinning it here is what stops this sweep from passing
    because it ran over nothing. }
  if Programs <> 307 then
  begin
    Log.Add(Format('  FAILED: expected 307 programs, got %d'
      + ' - wrong game directory?', [Programs]));
    Inc(Bad);
  end;
  if Lines = 0 then
  begin
    Log.Add('  FAILED: 307 programs and not one reached the host');
    Inc(Bad);
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - no shipped program hangs, and every one does something');
end;

{ --- 7. Events_SpawnNearCamera ------------------------------------------- }

function TestSpawnWindow(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  Pool: TEntityPool;
  P: TPlayerState;
  L: TLayerInfo;
  GS, I, Idx, Tx, Ty, Slot, Live, Bad: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

  { One sweep with the camera at the given tile; True if the record under test
    now holds an entity. The script is RELOADED each time, because its
    in-window and has-entity marks are what the sweep reads. }
  function SpawnsAt(CamX, CamY: Integer): Boolean;
  begin
    S.Load(GameDir, 2);
    Pool.Clear;
    GS := GS_PLAY;
    R.SpawnNearCamera(S, Pool, L, CamX, CamY, P, GS);
    Result := S[Idx].Active;
  end;

begin
  Bad := 0;
  Log.Add('Events_SpawnNearCamera:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  Pool := TEntityPool.Create;
  try
    FillChar(L, SizeOf(L), 0);
    L.TileW := 32;
    L.TileH := 32;
    L.MapTilesX := 128;
    L.MapTilesY := 128;
    L.OriginX := POSITION_BIAS;      { the camera at the map origin }
    L.OriginY := POSITION_BIAS;
    FreshPlayer(P);

    S.Load(GameDir, 2);
    { A record with no flag conditions, so only the window decides. }
    Idx := -1;
    for I := 0 to S.Count - 1 do
      if (S[I].NeedsFlag = 0) and (S[I].BlockedBy = 0)
         and (S[I].Opcode <> EVOP_ALWAYS) then
        Idx := I;
    if Idx < 0 then
    begin
      Log.Add('  FAILED: stage 2 has no unconditional record');
      Result := 1;
      Exit;
    end;
    Tx := S[Idx].TileX;
    Ty := S[Idx].TileY;

    { The window is CamTile - 2 < tile < CamTile + 12 across, so the camera may
      sit anywhere in Tx - 11 .. Tx + 1 and no further either way. Both edges
      are tested from BOTH sides, which is what pins a strict < against a <=. }
    Want(SpawnsAt(Tx - 11, Ty), 'did not spawn at the far edge of the window');
    Want(not SpawnsAt(Tx - 12, Ty), 'spawned one tile beyond the far edge');
    Want(SpawnsAt(Tx + 1, Ty), 'did not spawn at the near edge');
    Want(not SpawnsAt(Tx + 2, Ty), 'spawned one tile beyond the near edge');

    { Down the screen the window is shorter: 7.5 tiles plus the same margin.
      Note that the half tile is not observable here - tile < Cam + 9.5 and
      tile < Cam + 10 accept exactly the same integers - so this pins the
      integer boundary and nothing finer. }
    Want(SpawnsAt(Tx, Ty - 9), 'did not spawn at the bottom of the window');
    Want(not SpawnsAt(Tx, Ty - 10), 'spawned one tile below the window');
    Want(SpawnsAt(Tx, Ty + 1), 'did not spawn at the top of the window');
    Want(not SpawnsAt(Tx, Ty + 2), 'spawned one tile above the window');

    { In the window, the entity lands in the MIDDLE of its tile and remembers
      which record put it there.

      The 512 is written out rather than spelled SPAWN_TILE_CENTRE on purpose.
      Both were the constant to begin with, and mutation testing walked
      straight past a build with SPAWN_TILE_CENTRE set to 0: the assertion
      moved with the thing it was checking, so it could not fail. An
      expectation must be independent of what it is testing or it is only
      restating it. Same for the forced extent below. }
    SpawnsAt(Tx, Ty);
    Slot := S[Idx].EntitySlot;
    Want(Pool.Alive[Slot], 'the spawned slot is not alive');
    Want(Pool.PosX(Slot) = Tx * 32 * 32 + 512,
         Format('spawned at x=%d, want %d',
                [Pool.PosX(Slot), Tx * 32 * 32 + 512]));
    Want(Pool.PosY(Slot) = Ty * 32 * 32 + 512,
         Format('spawned at y=%d, want %d',
                [Pool.PosY(Slot), Ty * 32 * 32 + 512]));
    Want(Pool.Field(Slot, EF_EVENT_ID) = Idx,
         'the entity does not remember its event');

    { A second sweep must not place a second copy. This is what +0x05 is for,
      and it is the difference the notes had recorded as one idea. Count the
      whole pool, not this record's slot: the sweep places every record in the
      window, so what says nothing was duplicated is that the total did not
      move and this record still holds the slot it had. }
    Live := Pool.LiveCount;
    R.SpawnNearCamera(S, Pool, L, Tx, Ty, P, GS);
    Want(Pool.LiveCount = Live,
         Format('a second sweep took the pool from %d entities to %d',
                [Live, Pool.LiveCount]));
    Want(S[Idx].EntitySlot = Slot, 'a second sweep moved the entity');

    { Walk the camera away. The record still holds its entity, so the in-window
      mark must STAY - clearing it is what would let it spawn again. }
    R.SpawnNearCamera(S, Pool, L, Tx + 40, Ty, P, GS);
    Want(S[Idx].InWindow,
         'leaving the window cleared the mark while the entity was still out');

    { And now the case the two marks exist to tell apart. Kill the entity
      without moving the camera, exactly as Entity_Destroy would: the
      has-entity mark goes down but the in-window mark stays up, and the sweep
      must NOT place a replacement. Dropping the in-window test entirely
      survived every other check here, because a record that spawns
      successfully is left holding an entity anyway - this is the only state
      in which the two differ. }
    S.SetActive(Idx, False);
    Pool.Kill(Slot);
    Live := Pool.LiveCount;
    R.SpawnNearCamera(S, Pool, L, Tx, Ty, P, GS);
    Want(not S[Idx].Active,
         'an entity that died inside the window was replaced at once');
    Want(Pool.LiveCount = Live,
         Format('the sweep after a death took the pool from %d to %d',
                [Live, Pool.LiveCount]));

    { Leave the window with no entity and the mark clears, so it can come
      back next time. That is the other half of the same pair. }
    R.SpawnNearCamera(S, Pool, L, Tx + 40, Ty, P, GS);
    Want(not S[Idx].InWindow,
         'leaving the window with no entity did not clear the mark');
    R.SpawnNearCamera(S, Pool, L, Tx, Ty, P, GS);
    Want(S[Idx].Active, 'the record never came back after leaving the window');

    { --- the forbidding flag retires the record for good --------------- }
    S.Load(GameDir, 2);
    Pool.Clear;
    FreshPlayer(P);
    Idx := -1;
    for I := 0 to S.Count - 1 do
      if (S[I].BlockedBy <> 0) and (S[I].NeedsFlag = 0) then
        Idx := I;
    if Idx < 0 then
      Log.Add('  FAILED: stage 2 has no record with a forbidding flag')
    else
    begin
      Tx := S[Idx].TileX;
      Ty := S[Idx].TileY;
      GS := GS_PLAY;
      R.SpawnNearCamera(S, Pool, L, Tx, Ty, P, GS);
      Want(S[Idx].Active, 'a record with its flag clear did not spawn');
      Slot := S[Idx].EntitySlot;

      P.Progress[S[Idx].BlockedBy] := 1;
      R.SpawnNearCamera(S, Pool, L, Tx, Ty, P, GS);
      Want(S[Idx].Opcode = EVOP_DISABLED,
           'the forbidding flag did not disable the record');
      Want(S[Idx].TileX = EVENT_DISABLED_TILE,
           'the disabled record was not moved off the map');
      Want(not Pool.Alive[Slot], 'the disabled record kept its entity');
    end;

    { --- opcode 4 ignores the window entirely -------------------------- }
    S.Load(GameDir, 14);
    Pool.Clear;
    FreshPlayer(P);
    Idx := FindChecker(S);
    if Idx < 0 then
      Log.Add('  FAILED: stage 14 has no opcode-4 checker')
    else
    begin
      GS := GS_PLAY;
      { A camera nowhere near tile (1,1), where all nine checkers sit. }
      R.SpawnNearCamera(S, Pool, L, 90, 90, P, GS);
      Want(S[Idx].Active, 'an opcode-4 checker did not spawn out of the window');
      Want(GS = GS_STATE_140,
           'an opcode-4 checker was placed but its script did not start');
      Want(Pool.Field(S[Idx].EntitySlot, EF_EXTENT_X) = 32,
           Format('type 20 got extent x %d, want a whole tile',
                  [Pool.Field(S[Idx].EntitySlot, EF_EXTENT_X)]));
      Want(Pool.Field(S[Idx].EntitySlot, EF_EXTENT_Y) = 32,
           Format('type 20 got extent y %d, want a whole tile',
                  [Pool.Field(S[Idx].EntitySlot, EF_EXTENT_Y)]));
    end;
  finally
    Pool.Free;
    R.Free;
    S.Free;
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - both window edges, the placement, the duplicate guard '
      + 'and the retirement path');
end;

{ --- 8. ParamA's letter decides what the placement carries --------------- }

function TestSpawnArgs(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  R: TEventRunner;
  Pool: TEntityPool;
  P: TPlayerState;
  L: TLayerInfo;
  Sp: TEventSpawn;
  GS, I, J, Idx, Slot, Seen, Bad: Integer;
  Letters: string;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Seen := 0;
  Letters := '';
  Log.Add('ParamA, applied on spawn:');
  S := TEventScript.Create;
  R := TEventRunner.Create;
  Pool := TEntityPool.Create;
  try
    FillChar(L, SizeOf(L), 0);
    L.TileW := 32; L.TileH := 32;
    L.MapTilesX := 128; L.MapTilesY := 128;
    L.OriginX := POSITION_BIAS; L.OriginY := POSITION_BIAS;

    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for J := 0 to S.Count - 1 do
      begin
        Sp := ParseSpawn(S[J].ParamA);
        if (not Sp.Valid) or (Sp.Kind = '*') or (Sp.Kind = '/') then
          Continue;
        if Pos(Sp.Kind, Letters) = 0 then
          Letters := Letters + Sp.Kind;

        { RELOAD, do not merely clear the pool. The in-window and has-entity
          marks live in the script, not the pool, so a script left over from
          the previous record's sweep reports every nearby record as already
          placed - and the test then reads a stale slot out of a pool that has
          just been emptied. That read 0 for every field and looked exactly
          like ApplySpawnArgs doing nothing at all. }
        S.Load(GameDir, I);
        Pool.Clear;
        FreshPlayer(P);
        GS := GS_PLAY;
        Idx := J;
        R.SpawnNearCamera(S, Pool, L, S[J].TileX, S[J].TileY, P, GS);
        if not S[Idx].Active then
          Continue;          { a flag condition kept it out; not this test }
        Slot := S[Idx].EntitySlot;
        Inc(Seen);

        case Sp.Kind of
          'A':
            Want(Pool.Field(Slot, EF_VARIANT) = Sp.Args[0],
                 Format('stage %d event %d: A gave variant %d, want %d',
                        [I, J, Pool.Field(Slot, EF_VARIANT), Sp.Args[0]]));
          'M':
            begin
              Want(Pool.Field(Slot, EF_STATE) = Sp.Args[0],
                   Format('stage %d event %d: M state %d, want %d',
                          [I, J, Pool.Field(Slot, EF_STATE), Sp.Args[0]]));
              { The heading is given in eighths of the 64-step turn. }
              Want(Pool.Field(Slot, EF_FACING) = Sp.Args[2] * 8,
                   Format('stage %d event %d: M facing %d, want %d',
                          [I, J, Pool.Field(Slot, EF_FACING), Sp.Args[2] * 8]));
            end;
          'R':
            Want(Pool.Field(Slot, EF_FACING) = Sp.Args[0],
                 Format('stage %d event %d: R facing %d, want %d',
                        [I, J, Pool.Field(Slot, EF_FACING), Sp.Args[0]]));
          'J':
            { A nudge in whole pixels off the tile centre. }
            Want(Pool.PosX(Slot)
                   = S[Idx].TileX * 32 * 32 + SPAWN_TILE_CENTRE + Sp.Args[0] * 32,
                 Format('stage %d event %d: J x %d, want %d',
                        [I, J, Pool.PosX(Slot),
                         S[Idx].TileX * 32 * 32 + SPAWN_TILE_CENTRE
                         + Sp.Args[0] * 32]));
        end;
      end;
    end;

    { The gated form separately, because it needs a flag set to do anything at
      all - and the point of it is that one placement covers a before and an
      after. }
    S.Load(GameDir, 0);
    Idx := -1;
    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for J := 0 to S.Count - 1 do
      begin
        Sp := ParseSpawn(S[J].ParamA);
        if Sp.Valid and (Sp.Kind = '/') and (S[J].NeedsFlag = 0)
           and (S[J].BlockedBy = 0) then
        begin
          Idx := J;
          Break;
        end;
      end;
      if Idx >= 0 then
        Break;
    end;
    if Idx < 0 then
      Log.Add('  FAILED: no unconditional gated placement anywhere')
    else
    begin
      Sp := ParseSpawn(S[Idx].ParamA);

      Pool.Clear;
      FreshPlayer(P);
      GS := GS_PLAY;
      R.SpawnNearCamera(S, Pool, L, S[Idx].TileX, S[Idx].TileY, P, GS);
      Slot := S[Idx].EntitySlot;
      Want(Pool.Field(Slot, EF_STATE) = 0,
           'the gated form applied its state with the flag clear');

      S.Load(GameDir, I);
      Pool.Clear;
      FreshPlayer(P);
      P.Progress[Sp.Args[0]] := 1;
      GS := GS_PLAY;
      R.SpawnNearCamera(S, Pool, L, S[Idx].TileX, S[Idx].TileY, P, GS);
      Slot := S[Idx].EntitySlot;
      Want(Pool.Field(Slot, EF_STATE) = Sp.Args[1],
           Format('the gated form gave state %d with flag %d set, want %d',
                  [Pool.Field(Slot, EF_STATE), Sp.Args[0], Sp.Args[1]]));
    end;
  finally
    Pool.Free;
    R.Free;
    S.Free;
  end;

  Log.Add(Format('placements checked: %d, kinds %s', [Seen, Letters]));
  if Seen < 200 then
  begin
    Log.Add(Format('  FAILED: only %d placements reached, want at least 200',
      [Seen]));
    Inc(Bad);
  end;
  Result := Bad;
  if Result = 0 then
    Log.Add('  OK - every letter puts its fields where the interpreter reads them');
end;

function SelfTestRunner(Log: TStrings): Integer;
var
  GameDir: string;
begin
  Result := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');

  Inc(Result, TestSavePoint(Log, GameDir));      Log.Add('');
  Inc(Result, TestEventBegin(Log, GameDir));     Log.Add('');
  Inc(Result, TestBackwardsScan(Log, GameDir));  Log.Add('');
  Inc(Result, TestWaiting(Log, GameDir));        Log.Add('');
  Inc(Result, TestFlagList(Log, GameDir));       Log.Add('');
  Inc(Result, TestSpawnWindow(Log, GameDir));    Log.Add('');
  Inc(Result, TestSpawnArgs(Log, GameDir));      Log.Add('');
  Inc(Result, TestEveryProgram(Log, GameDir));

  Log.Add('');
  if Result = 0 then
    Log.Add('OK - the interpreter steps, branches, waits and spawns as read')
  else
    Log.Add('FAILED');
end;

{ ---------------------------------------------------------------------------
  --selftest-session <gamedir> : the pieces, connected.

  Every other self-test checks one function against a fixture built for it.
  None of them can catch two correct functions being wired together wrongly,
  and until now nothing was wired at all - GmMain.pas did not reference
  Entities, Player, Camera or EventRunner, so the entire translated game had
  no caller.

  This runs FRAMES. A real stage table, a real map, the real event table, and
  the actual dispatcher; the only things stubbed are sound and sprites, and
  both are legitimately absent rather than faked.

  What it can show is that the parts fit: that a stage begins, that the player
  exists and is affected by gravity and terrain, that events place entities as
  the camera moves, and that a frame does not throw. What it cannot show is
  that any of it matches akuji.exe - that still needs the differential
  harness, and a frame is far past what the emulator can reach.
  --------------------------------------------------------------------------- }

{ The message box's page splitting, against the shipped text.

  Reading a sign locked the game: sub-op 3 waits and only the box advances the
  script, so with no box the script never moved. This checks the part of the
  box that is decidable without a screen - how a tk line becomes pages - and
  it checks it against every line the game ships rather than against invented
  strings. }
function TestDialogue(Log: TStrings; const GameDir: string): Integer;
var
  S: TEventScript;
  Page, Rest, Src: string;
  Prompt: Boolean;
  P2: TPlayerState;
  I, J, Bad, Lines, Prompts, Pages, MaxPages, N: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Lines := 0; Prompts := 0; Pages := 0; MaxPages := 0;
  Log.Add('');
  Log.Add('--- the message box ---');

  { --- the yes/no answer is TWO flags, from 0x00456038 ---------------- }
  { It used to write Progress[3] alone, so every script guarding on "No" saw
    nothing. Both directions are checked, with literal expectations. }
  begin
    FillChar(P2, SizeOf(P2), 0);
    P2.Progress[MB_ANSWER_YES] := 9;   { junk, to prove both are WRITTEN }
    P2.Progress[MB_ANSWER_NO] := 9;
    DialogueAnswer(P2, 0);
    Want(P2.Progress[MB_ANSWER_YES] = 1, 'Yes did not set Progress[3]');
    Want(P2.Progress[MB_ANSWER_NO] = 0, 'Yes did not clear Progress[4]');

    DialogueAnswer(P2, 1);
    Want(P2.Progress[MB_ANSWER_YES] = 0, 'No did not clear Progress[3]');
    Want(P2.Progress[MB_ANSWER_NO] = 1, 'No did not set Progress[4]');
  end;

  { --- PowerUp_Show's grant table, from 0x00456698 ------------------- }
  { The weapon's two guards are the only conditional part, and they are the
    part a tidy rewrite would lose: picking up Fire after Charge must not
    demote you. Each is checked in both directions. }
  begin
    FillChar(P2, SizeOf(P2), 0);
    PowerUpGrant(P2, 0);
    Want(P2.Weapon = 1, 'variant 0 did not give weapon 1 from nothing');
    PowerUpGrant(P2, 0);
    Want(P2.Weapon = 1, 'variant 0 re-applied over an existing weapon');
    PowerUpGrant(P2, 1);
    Want(P2.Weapon = 2, 'variant 1 did not raise the weapon to 2');
    PowerUpGrant(P2, 2);
    Want(P2.Weapon = 3, 'variant 2 did not give weapon 3');
    PowerUpGrant(P2, 0);
    Want(P2.Weapon = 3, 'Fire after Charge demoted the weapon');
    PowerUpGrant(P2, 1);
    Want(P2.Weapon = 3, 'Fire+ after Charge demoted the weapon');

    { ...but variant 1 refuses only the value 3, so Fire+ over Fire+ DOES
      re-apply. Not the same function as max(), and pinned so it stays. }
    FillChar(P2, SizeOf(P2), 0);
    P2.Weapon := 2;
    PowerUpGrant(P2, 1);
    Want(P2.Weapon = 2, 'Fire+ over Fire+ did not stay at 2');

    FillChar(P2, SizeOf(P2), 0);
    P2.JumpStrength := DEFAULT_FIELD11D0;
    PowerUpGrant(P2, 3);
    Want(P2.JumpStrength = $84,
         Format('variant 3 left the jump at %d, want $84',
                [P2.JumpStrength]));

    for I := ABILITY_DASH to ABILITY_GLIDE do
    begin
      FillChar(P2, SizeOf(P2), 0);
      PowerUpGrant(P2, I);
      Want(P2.Head[I] = 1,
           Format('variant %d did not set Head[%d]', [I, I]));
      Want(P2.Weapon = 0,
           Format('variant %d touched the weapon', [I]));
    end;

    { Stage 1's pickup is 0024-A-0004, and 4 is the dash. }
    Want(PowerUpName(4) = 'Dash    ',
         'variant 4 is not the dash: ' + PowerUpName(4));
    Want(PowerUpName(9) = '', 'a variant past the table returned a name');
  end;

  { The four codes, on text taken straight out of tk002. }
  Page := SplitPage('Will you save the game? \w', Rest, Prompt);
  Want(Prompt, 'a \w line did not raise the prompt');
  Want(Trim(Page) = 'Will you save the game?',
       'the prompt page came out as "' + Page + '"');

  Page := SplitPage('Saving completed! \e', Rest, Prompt);
  Want(not Prompt, 'a \e line raised a prompt');
  Want(Rest = '', 'a \e line left something after it: "' + Rest + '"');

  Page := SplitPage('Touching a Devil Statue can \nsave your game. \kYou may '
                    + 'want to save now. \e', Rest, Prompt);
  Want(Pos('\k', Page) = 0, 'the page kept its own \k');
  Want(Pos('You may', Rest) > 0,
       'a \k line did not leave the next page behind: "' + Rest + '"');

  { And every line in every shipped tk file must split without looping. A
    page that produced no progress would hang the box the same way the
    missing box hung the script. }
  S := TEventScript.Create;
  try
    for I := 0 to 65 do
    begin
      S.Load(GameDir, I);
      for J := 0 to S.LineCount - 1 do
      begin
        Inc(Lines);
        Src := S.Lines[J];
        N := 0;
        repeat
          { Src and Rest must be DIFFERENT variables - SplitPage clears its
            out parameter on entry, and aliasing them blanks the input before
            it is read. That is not hypothetical: it is the bug this sweep
            found in TDialogueBox.TakePage. }
          Page := SplitPage(Src, Rest, Prompt);
          Src := Rest;
          Inc(N);
          Inc(Pages);
          if Prompt then
            Inc(Prompts);
        until (Src = '') or (N > 32);
        if N > 32 then
        begin
          Log.Add(Format('  stage %d line %d never finished splitting: %s',
            [I, J, S.Lines[J]]));
          Inc(Bad);
        end;
        if N > MaxPages then
          MaxPages := N;
      end;
    end;
  finally
    S.Free;
  end;

  Log.Add(Format('tk lines split: %d into %d pages, longest %d, %d prompts',
    [Lines, Pages, MaxPages, Prompts]));

  { Pinned so a splitter that returned nothing could not pass vacuously. The
    44 prompts are the same 44 EventRunner.pas counts from the other side -
    the \w lines that its scratch-flag guards depend on. }
  { The shipped totals, counted independently: 66 tk files, 203 lines, 63 of
    them carrying \w and 52 carrying \k. Pinned so a splitter that returned
    nothing could not pass by comparing nothing - which is exactly what it did
    on the first run, when the sweep aliased its own input and every line came
    back empty. }
  if Lines <> 203 then
  begin
    Log.Add(Format('  FAILED: %d tk lines, want 203 - wrong game directory?',
      [Lines]));
    Inc(Bad);
  end;
  if Prompts <> 63 then
  begin
    Log.Add(Format('  FAILED: %d prompt pages, want the 63 lines carrying \w',
      [Prompts]));
    Inc(Bad);
  end;
  if MaxPages < 2 then
  begin
    Log.Add('  FAILED: no line split into more than one page, but 52 carry \k');
    Inc(Bad);
  end;

  Result := Bad;
  if Result = 0 then
    Log.Add('OK - every shipped line splits into pages and terminates');
end;

type
  { Counts the three things GameOver_Update asks its host to do. It does NOT
    override anything the screen itself decides - a double that answers the
    question under test only tests the double. }
  TGameOverProbe = class
  public
    Restarts, Fades, Tunes: Integer;
    procedure Restart;
    procedure Fade(FadeIn: Boolean);
    procedure Music(Track: Integer);
  end;

procedure TGameOverProbe.Restart;
begin Inc(Restarts); end;
procedure TGameOverProbe.Fade(FadeIn: Boolean);
begin Inc(Fades); end;
procedure TGameOverProbe.Music(Track: Integer);
begin
  Inc(Tunes);
  if Track <> GAMEOVER_MIDI then Tunes := -1000;
end;

{ Input_ConfirmPressed @ 0x00466E4C and GameOver_Update @ 0x00461A44.

  The confirm half exists because the reconstruction had it wrong in two
  ways at once - a level instead of an edge, and only one of the two
  buttons - and neither would have shown up in a test that only ever pressed
  and released cleanly. The expectations here are literals, not derived from
  the function under test. }
function TestConfirmAndGameOver(Log: TStrings): Integer;
var
  Inp: TInputState;
  G: TGameOverScreen;
  Probe: TGameOverProbe;
  GS, Bad: Integer;
  Drawn: Boolean;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- confirm, and the game-over screen ---');

  FillChar(Inp, SizeOf(Inp), 0);
  Want(not ConfirmPressed(Inp), 'confirm fired with nothing pressed');

  Inp.Button[0] := True;
  Want(ConfirmPressed(Inp), 'button 0 pressed did not confirm');
  Inp.ButtonLatch[0] := True;
  Want(not ConfirmPressed(Inp), 'button 0 HELD still confirmed - it is an edge');

  FillChar(Inp, SizeOf(Inp), 0);
  Inp.Button[1] := True;
  Want(ConfirmPressed(Inp), 'button 1 pressed did not confirm - both count');
  Inp.ButtonLatch[1] := True;
  Want(not ConfirmPressed(Inp), 'button 1 held still confirmed');

  { The phase machine, with no fader: 0 and 1 run in successive frames and
    2 holds until the music stops or confirm arrives. }
  Probe := TGameOverProbe.Create;
  G := TGameOverScreen.Create;
  try
    G.OnRestart := Probe.Restart;
    G.OnFade := Probe.Fade;
    G.OnMusic := Probe.Music;

    ScreenPhase := 0;
    TitleSubMode := 7;
    GS := GS_PLAY_ALT;

    Drawn := G.Update(False, True, False, GS);
    Want(not Drawn, 'phase 0 drew something');
    Want(ScreenPhase = 1, 'phase 0 did not step to 1');
    Want(Probe.Fades = 1, 'phase 0 did not ask for a fade');

    Drawn := G.Update(False, True, False, GS);
    Want(Drawn, 'phase 2 did not draw');
    Want(ScreenPhase = 2, 'phase 1 did not step to 2');
    Want(Probe.Restarts = 1, 'the run was not torn down');
    Want(Probe.Tunes = 1, 'the game-over tune was not started');
    Want(TitleSubMode = 0, 'the title sub-mode was not cleared');
    Want(GS = GS_PLAY_ALT, 'the state left 100 too early');

    { Held while the tune plays ... }
    Drawn := G.Update(False, True, False, GS);
    Want(Drawn and (GS = GS_PLAY_ALT), 'the screen ended while the music ran');
    { ... and confirm cuts it short. }
    G.Update(False, True, True, GS);
    Want(GS = GS_TITLE_INIT, 'confirm did not return to the title');
    Want(ScreenPhase = 0, 'the phase was not reset on the way out');

    { And the music running out ends it on its own. }
    ScreenPhase := 2;
    GS := GS_PLAY_ALT;
    G.Update(False, False, False, GS);
    Want(GS = GS_TITLE_INIT, 'the screen outlived its own music');
  finally
    G.Free;
    Probe.Free;
  end;

  Result := Bad;
  if Bad = 0 then
    Log.Add('confirm is an edge on either button, and the game-over screen '
      + 'runs its three phases');
end;

{ Ending_Update @ 0x00463624: the completion percentage, the rank, and the two
  sets of persistent flags it banks.

  Every expectation here is a LITERAL. The percentage in particular is not
  compared against Counter div 4, because the whole point is that the original
  is not Counter div 4 at two values - `python tools/x87_sim.py ending` is the
  independent reader that says which two, and it is run by tools/check.sh. }
function TestEnding(Log: TStrings): Integer;
var
  S: TGameSettings;
  P: TPlayerState;
  Bad, I: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  Log.Add('');
  Log.Add('--- the ending screen ---');

  Want(EndingPercent(0) = 0, 'zero collected is not zero percent');
  Want(EndingPercent(400) = 100, 'all four hundred is not a hundred percent');
  Want(EndingPercent(7) = 1, '7 of 400 should truncate to 1');
  Want(EndingPercent(200) = 50, '200 of 400 should be 50');
  { The two the original gets wrong. }
  Want(EndingPercent(212) = 52, 'counter 212 should read 52, not 53');
  Want(EndingPercent(236) = 58, 'counter 236 should read 58, not 59');
  Want(EndingPercent(213) = 53, 'counter 213 is not one of the two');
  Want(EndingPercent(237) = 59, 'counter 237 is not one of the two');

  { A long run, so the time gate never fires and the percentage gates decide. }
  Want(EndingRank(200, 9999) = 0, '50 percent should not beat the first gate');
  Want(EndingRank(204, 9999) = 1, '51 percent should reach rank 1');
  Want(EndingRank(284, 9999) = 2, '71 percent should reach rank 2');
  Want(EndingRank(364, 9999) = 3, '91 percent should reach rank 3');
  { And the time gate overriding a poor percentage. }
  Want(EndingRank(0, 1800) = 4, 'thirty minutes exactly should reach rank 4');
  Want(EndingRank(400, 1801) = 3,
       'one second over thirty minutes should not reach rank 4');

  FillChar(S, SizeOf(S), 0);
  FillChar(P, SizeOf(P), 0);
  P.Counter := 364;  P.ElapsedSec := 9999;
  EndingApplyUnlocks(S, P);
  Want(S.ExtraDoor1 = 1, 'rank 3 did not unlock the first door');
  Want(S.ExtraDoor2 = 0, 'rank 3 unlocked the second door too');

  FillChar(S, SizeOf(S), 0);
  P.Counter := 0;  P.ElapsedSec := 1800;
  EndingApplyUnlocks(S, P);
  Want((S.ExtraDoor1 = 1) and (S.ExtraDoor2 = 1),
       'a fast run did not unlock both doors');

  { The gallery: one byte per flag, in order, and never taken away. }
  FillChar(S, SizeOf(S), 0);
  FillChar(P, SizeOf(P), 0);
  P.Progress[GALLERY_FIRST_FLAG + 3] := 1;
  EndingApplyUnlocks(S, P);
  Want(S.Unknown2C[3] = 1, 'gallery flag 3 did not carry across');
  for I := 0 to GALLERY_COUNT - 1 do
    if I <> 3 then
      Want(S.Unknown2C[I] = 0, Format('gallery entry %d unlocked itself', [I]));

  S.Unknown2C[5] := 1;
  FillChar(P, SizeOf(P), 0);
  EndingApplyUnlocks(S, P);
  Want(S.Unknown2C[5] = 1, 'a worse run took a gallery entry away');

  Want(EndingTimeText(3725) = '01:02:05', 'the clock does not format h:mm:ss');
  { NOT '052%'. The format string is '%03d%%', which looks like C's zero-pad
    and is not: Delphi's Format parses the digits as a WIDTH, leading zero and
    all, and pads with spaces. So the original prints a space, not a zero. }
  Want(EndingPercentText(212) = ' 52%',
       'the percentage should be space-padded to three - %03d is a width');
  Want(EndingPercentText(400) = '100%', 'a full run should not be padded');

  Result := Bad;
  if Bad = 0 then
    Log.Add('the percentage carries the original''s two off-by-ones, and the '
      + 'rank banks the right flags');
end;

function SelfTestSession(Log: TStrings): Integer;
var
  GameDir: string;
  Stages: TStageTable;
  Map: TTileMap;
  Frames: TSpriteSet;
  S: TGameSession;
  GS, I, Bad, StartY, Fell, Moved, StartX, Slot: Integer;
  Placed, LiveAfter: Integer;

  procedure Want(Cond: Boolean; const What: string);
  begin
    if not Cond then begin Log.Add('  ' + What); Inc(Bad); end;
  end;

begin
  Bad := 0;
  GameDir := ParamStr(2);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add('');

  Stages := TStageTable.Create;
  Map := TTileMap.Create;
  S := nil;
  try
    if Stages.Load(GameDir) <= 0 then
    begin
      Log.Add('FAILED: no stage table');
      Result := 1;
      Exit;
    end;
    if not Map.Load(GameDir, Stages.Layer[1, 0]) then
    begin
      Log.Add('FAILED: could not load stage 1''s map');
      Result := 1;
      Exit;
    end;

    { The sprite frames are not decoration: an entity's extents are read off
      its sprite every frame, so without them nothing has a size and nothing
      collides. That is exactly how this test failed the first time it ran. }
    Frames := TSpriteSet.Create;
    Frames.LoadSet(GameDir, Stages.SpriteSet[1]);

    S := TGameSession.Create(GameDir, Stages, Map);
    S.SetFrames(Frames);

    { --- a stage begins --------------------------------------------- }
    InitNewGame(S.Player, 0);
    ApplySessionFlags(S.Player, 0);
    GS := GS_STAGE_BEGIN;
    S.BeginStage(1, GS);

    Log.Add(Format('stage 1: terrain %d, solid threshold %d, %d events, '
      + 'map %dx%d tiles of %dx%d',
      [S.World.TerrainId, S.World.SolidThreshold, S.Events.Count,
       Map.MapWidth, Map.MapHeight, Map.TileWidth, Map.TileHeight]));

    Want(GS = GS_PLAY, Format('BeginStage left the state at %d, want %d',
                              [GS, GS_PLAY]));
    Want(S.World.SolidThreshold > 0,
         'the solid threshold is 0 - every tile would be walkable');
    Want(S.Events.Count > 0, 'stage 1 loaded no events');
    Want(S.Pool.Alive[0], 'the player is not in slot 0 after BeginStage');
    Want(S.Pool.LiveCount = 1,
         Format('BeginStage left %d entities, want just the player',
                [S.Pool.LiveCount]));
    Want(S.Layer.TileW = 32, 'the layer did not take the map''s tile size');

    { The world's copy of the layer must be the session's, or every collision
      query reads a stale origin. This is exactly the class of mistake that
      only appears once things are connected. }
    Want(S.World.Layer.TileW = S.Layer.TileW,
         'the world''s layer is not the session''s');
    Want(S.World.Layer.OriginY = S.Layer.OriginY,
         'the world''s layer origin is stale');

    { --- frames run ------------------------------------------------- }
    StartY := S.Pool.PosY(0);
    StartX := S.Pool.PosX(0);
    Log.Add('');
    { The first frames of a stage, kept because they are the whole story: the
      player is placed in mid air, falls, and lands. Getting here took a
      sprite pool - see SpritePool.pas - and the trace is what showed why. }
    Log.Add('  frame state posY  velY  worldRow  tile');
    for I := 1 to 120 do
    begin
      if I <= 5 then
        Log.Add(Format('  %5d %5d %5d %5d %9d %5d',
          [I, S.Pool.Field(0, EF_STATE),
           PixelOf(S.Pool.Field(0, EF_POS_Y)),
           S.Pool.Field(0, EF_VEL_Y),
           (PixelOf(S.Layer.OriginY) + PixelOf(S.Pool.Field(0, EF_POS_Y)))
             div 32,
           Map.TileAtRaw(
             (PixelOf(S.Layer.OriginX) + PixelOf(S.Pool.Field(0, EF_POS_X)))
               div 32,
             (PixelOf(S.Layer.OriginY) + PixelOf(S.Pool.Field(0, EF_POS_Y)))
               div 32)]));
      S.Frame(GS);
    end;
    Log.Add(Format('  extents %d x %d, sprite handle %d, frames %d',
      [S.Pool.Field(0, EF_EXTENT_X), S.Pool.Field(0, EF_EXTENT_Y),
       S.Pool.Field(0, EF_SPRITE), Frames.Count]));
    Want(S.Pool.Field(0, EF_SPRITE) <> SPRITE_NONE,
         'the player got no sprite, so it has no extents and cannot collide');
    Want(S.Pool.Field(0, EF_EXTENT_X) > 0,
         'the player has zero width - Entity_UpdateAll is not reading the '
         + 'sprite');

    { A translated handler gives its entity a sprite of its own. An
      UNtranslated one leaves the anim id Entity_Spawn wrote, which is the
      type table's column 0 - and that column is 0 for all 81 types, so an
      untranslated entity wears sprite 0, which is Akuji standing. Stage 1
      places three type-16 signs; before that handler existed they looked
      exactly like the player, and nothing here could tell. }
    Slot := -1;
    for I := 1 to 63 do
      if S.Pool.Alive[I] and (S.Pool.Field(I, EF_TYPE) = 16) then
        Slot := I;
    if Slot < 0 then
      Log.Add('  (stage 1 placed no sign; the sprite check is skipped)')
    else
    begin
      Want(S.Pool.Field(Slot, EF_ANIM_ID) = 54,
           Format('the sign is on sprite %d, want 54 - sprite 0 means its '
             + 'handler never ran', [S.Pool.Field(Slot, EF_ANIM_ID)]));
      Want(S.Pool.Field(Slot, EF_ANIM_ID) <> S.Pool.Field(0, EF_ANIM_ID),
           'the sign and the player are on the same sprite');
    end;
    Log.Add('');

    Fell := S.Pool.PosY(0) - StartY;
    Log.Add(Format('120 idle frames: player moved %d sub-pixels down, %d across',
      [Fell, S.Pool.PosX(0) - StartX]));
    Log.Add(Format('  live entities now %d, game state %d',
      [S.Pool.LiveCount, GS]));

    Want(S.Pool.Alive[0], 'the player stopped existing during 120 idle frames');
    Want(Fell > 0,
         'the player did not fall at all - gravity or the tile query is not '
         + 'reaching the entity');
    { And it must STOP falling: an entity that never lands means the collision
      query is answering TILE_NONE, which is what a missing tile source looks
      like. }
    StartY := S.Pool.PosY(0);
    for I := 1 to 120 do
      S.Frame(GS);
    Want(S.Pool.PosY(0) = StartY,
         Format('the player is still falling after 240 frames (%d more '
           + 'sub-pixels) - nothing is solid', [S.Pool.PosY(0) - StartY]));

    { --- input reaches the controller -------------------------------- }
    StartX := S.Pool.PosX(0);
    S.Input.AxisX := 1;
    for I := 1 to 60 do
      S.Frame(GS);
    S.Input.AxisX := 0;
    Moved := S.Pool.PosX(0) - StartX;
    Log.Add(Format('60 frames holding right: moved %d sub-pixels (%d px)',
      [Moved, Moved div 32]));
    Want(Moved > 0, 'holding right moved the player nowhere - input is not '
         + 'reaching the controller');
    { And it must move at the speed the controller's own constant predicts:
      AxisX shl PLAYER_WALK_SHIFT is 32 sub-pixels, which is exactly one pixel
      a frame. 60 frames, 60 pixels. Pinning the NUMBER rather than "it moved"
      is what makes this a check on the wiring and not just on liveness. }
    Want(Moved = 60 * (1 shl PLAYER_WALK_SHIFT),
         Format('walking 60 frames moved %d sub-pixels, want %d - one pixel '
           + 'a frame', [Moved, 60 * (1 shl PLAYER_WALK_SHIFT)]));

    { What is actually on screen at the start of a stage, and where. }
    Log.Add('');
    Log.Add('  live entities after the opening frames:');
    Log.Add('    slot  type  anim  screenX  screenY  spriteW  spriteH  vis');
    for I := 0 to 63 do
      if S.Pool.Alive[I] then
        Log.Add(Format('    %4d  %4d  %4d  %7d  %7d  %7d  %7d  %s',
          [I, S.Pool.Field(I, EF_TYPE), S.Pool.Field(I, EF_ANIM_ID),
           PixelOf(S.Pool.Field(I, EF_POS_X)),
           PixelOf(S.Pool.Field(I, EF_POS_Y)),
           S.Pool.Field(I, EF_EXTENT_X), S.Pool.Field(I, EF_EXTENT_Y),
           BoolToStr(S.Sprites.GetVisible(S.Pool.Field(I, EF_SPRITE)), True)]));
    Log.Add('');

    { --- the animated background tiles -------------------------------- }
    { The tick's whole effect is to repoint a tile id at another cell of the
      tileset, so every instance of that tile animates at once. Stage 1 is
      terrain 1, which declares two tracks: tile 7 cycling 7,8,9,8 and tile 17
      cycling 17,18,19,18, both at 8 ticks a frame. }
    if S.BgAnim = nil then
    begin
      Log.Add('  FAILED: terrain 1 built no background animator');
      Inc(Bad);
    end
    else
    begin
      Want(S.BgAnim.TrackCount = 2,
           Format('terrain 1 has %d tracks, want 2', [S.BgAnim.TrackCount]));
      Want(S.BgAnim.TrackTile(0) = 7,
           Format('track 0 animates tile %d, want 7', [S.BgAnim.TrackTile(0)]));

      { Nothing initialises the timer, so the FIRST tick already shows frame 0
        rather than waiting 8 frames. A timer that started at 8 would look
        almost right and be one frame late for ever. }
      S.BgAnim.Restart;
      StartX := S.Map.TileDef(7).Left;
      S.TickBackground;
      Want(S.Map.TileDef(7).Left = TileSrcX(7, 32, 10),
           'the first tick did not put tile 7 on its own cell');
      Want(S.BgAnim.TrackCursor(0) = 1,
           Format('after one tick the cursor is %d, want 1',
                  [S.BgAnim.TrackCursor(0)]));

      { Then it holds for 8 ticks, and the ninth advances. }
      for I := 1 to 7 do
        S.TickBackground;
      Want(S.BgAnim.TrackCursor(0) = 1,
           Format('the cursor moved after %d ticks, want it to hold for 8',
                  [8]));
      S.TickBackground;
      Want(S.BgAnim.TrackCursor(0) = 2,
           'the cursor did not advance on the eighth tick');
      Want(S.Map.TileDef(7).Left = TileSrcX(8, 32, 10),
           'tile 7 is not showing tile 8''s cell on frame 1');

      { And the cycle is 7,8,9,8 - four frames, then back to the start. }
      for I := 1 to 8 * 2 do
        S.TickBackground;
      Want(S.BgAnim.TrackCursor(0) = 0,
           Format('after four frames the cursor is %d, want it wrapped to 0',
                  [S.BgAnim.TrackCursor(0)]));
      Want(S.Map.TileDef(7).Left = TileSrcX(8, 32, 10),
           'the fourth frame of 7,8,9,8 is not tile 8');
      Log.Add(Format('background: %d tracks, tile %d cycling through its '
        + 'four frames', [S.BgAnim.TrackCount, S.BgAnim.TrackTile(0)]));
    end;

    { --- the camera follows, and only outside the dead zone ---------- }
    { The layer must not move while the player is inside the dead zone, and
      must move once it leaves. Rather than assume where the player is, walk
      a frame at a time and record the screen position at which the camera
      FIRST moves - that pins DEADZONE_RIGHT from behaviour instead of
      restating the constant. }
    StartX := PixelOf(S.Layer.OriginX);
    Moved := -1;
    S.Input.AxisX := 1;
    for I := 1 to 200 do
    begin
      S.Frame(GS);
      if (Moved < 0) and (PixelOf(S.Layer.OriginX) <> StartX) then
        Moved := PixelOf(S.Pool.Field(0, EF_POS_X));
    end;
    S.Input.AxisX := 0;
    Log.Add(Format('walking right: camera first moved at player x %d, '
      + 'ended player x %d camera x %d',
      [Moved, PixelOf(S.Pool.Field(0, EF_POS_X)),
       PixelOf(S.Layer.OriginX)]));

    Want(Moved >= 0,
         'the camera never followed - the player walked off the right of the '
         + 'screen instead of the view scrolling');
    { 177 written out, not DEADZONE_RIGHT: an expectation phrased in terms of
      the constant it is checking cannot fail. }
    Want(Moved >= 177,
         Format('the camera started scrolling at player x %d, before the '
           + 'dead zone edge at 177', [Moved]));
    { Once scrolling, the walk goes into the view and the player stays put. }
    Want(PixelOf(S.Pool.Field(0, EF_POS_X)) <= 180,
         Format('the player is at screen x %d - the scroll is not absorbing '
           + 'the walk', [PixelOf(S.Pool.Field(0, EF_POS_X))]));
    { How FAR it scrolls depends on the map - the player meets walls and
      gaps - so the check is that it scrolled at all and that it stopped
      inside the limit the original computes: (MapTilesX - 10) * TileW, read
      off Camera_ShouldScrollX at 0x00459C1C. }
    Want(PixelOf(S.Layer.OriginX) > StartX,
         Format('the view did not scroll: %d', [PixelOf(S.Layer.OriginX)]));
    Want(PixelOf(S.Layer.OriginX) <= (Map.MapWidth - 10) * Map.TileWidth,
         Format('the view scrolled to %d, past the map limit %d',
           [PixelOf(S.Layer.OriginX),
            (Map.MapWidth - 10) * Map.TileWidth]));

    { --- the scroll carry stops when the scroll does ------------------ }
    { Entity_UpdateAll adds LayerInfo.Delta to every non screen-space entity,
      which is how the world carries things along as the view moves.
      TFrm_main_AppIdle zeroes the delta at the top of EVERY frame, so the
      carry lasts exactly one frame. Leave it set and every entity drifts for
      ever after a single scroll - which looked like items flying off the top
      of the screen. Find a spawned entity, let go of the controls, and
      require it to stay where it is. }
    Slot := -1;
    for I := 1 to 63 do
      if S.Pool.Alive[I] then
        Slot := I;
    if Slot < 0 then
      Log.Add('  (nothing but the player is alive; the carry is not tested)')
    else
    begin
      StartX := S.Pool.PosX(Slot);
      StartY := S.Pool.PosY(Slot);
      for I := 1 to 60 do
        S.Frame(GS);
      Want((S.Pool.PosX(Slot) = StartX) and (S.Pool.PosY(Slot) = StartY),
           Format('entity %d drifted %d,%d sub-pixels over 60 idle frames '
             + 'after the view scrolled - the layer delta is not being '
             + 'cleared each frame',
             [Slot, S.Pool.PosX(Slot) - StartX, S.Pool.PosY(Slot) - StartY]));
      Want(S.Layer.DeltaX = 0,
           Format('the layer delta is still %d at the end of a frame',
                  [S.Layer.DeltaX]));
    end;

    { --- the event table places entities ----------------------------- }
    { Walk the camera over the whole map and count what gets placed. If the
      spawn walk were not wired, or the camera tile were computed wrongly,
      this would be zero while everything above still passed. }
    Placed := 0;
    for I := 0 to Map.MapWidth - 1 do
    begin
      S.SetCamera(I * 32, PixelOf(S.Layer.OriginY));
      S.Frame(GS);
      if S.Pool.LiveCount > Placed then
        Placed := S.Pool.LiveCount;
    end;
    LiveAfter := S.Pool.LiveCount;
    Log.Add(Format('camera swept across the map: at most %d entities live at '
      + 'once, %d at the end, %d sprites held',
      [Placed, LiveAfter, S.Sprites.LiveCount]));
    Want(Placed > 1,
         'sweeping the camera placed nothing - the event spawn walk is not '
         + 'connected, or the camera tile is wrong');

    { Every entity holds a sprite, and the pool is 256. If sprites were not
      released the sweep would exhaust it and later spawns would silently
      fail - which is what a screen slowly filling with stuck sprites looks
      like. One handle per live entity, exactly. }
    Want(S.Sprites.LiveCount = LiveAfter,
         Format('%d entities are holding %d sprites',
                [LiveAfter, S.Sprites.LiveCount]));
  finally
    S.Free;
    Frames.Free;
    Map.Free;
    Stages.Free;
  end;

  Inc(Bad, TestDialogue(Log, GameDir));
  Inc(Bad, TestConfirmAndGameOver(Log));
  Inc(Bad, TestEnding(Log));

  Result := Bad;
  Log.Add('');
  if Result = 0 then
    Log.Add('OK - a stage begins, frames run, and the parts reach each other')
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

  TWO CHANNELS, not one. A leaf function's answer is EAX and an integer
  comparison is the whole test. An entity HANDLER returns nothing meaningful:
  its answer is the entity it mutated. So a case may also carry `get=<hex>`
  after the arrow - the bytes the emulator read back out of the original's
  entity - and this compares those against the same region of ours, naming the
  int index that differs rather than dumping 260 bytes at the reader.

  AND A CASE MAY BE EXPECTED TO DIFFER. `f.div=<n>` marks a case that exercises
  a declared entry in notes/divergences.md - somewhere we knowingly do not
  reproduce the original. Those cases invert: agreement is the failure, because
  it means the ledger describes a divergence that is no longer there.

  That inversion is the point. A category D entry in the ledger is a claim about
  what the original does and what we do instead, and prose cannot be wrong
  loudly. This makes the claim executable: the original's actual behaviour is
  printed beside ours on every run, and the entry cannot quietly outlive the
  code it describes.

  WHAT IT CANNOT REACH. The emulator models the instruction set, not the
  process: no Windows, no imports, no VCL. A function that calls the RTL or
  touches a handle faults, and that is an honest boundary rather than a bug.

  It reaches further than this note used to claim. "Leaf routines and
  arithmetic" was a guess that went unchecked for a long time and wrote off the
  entity layer on the strength of it. All 78 entity handlers run to completion
  in the emulator, including 312 cases on a LIVE entity in four states - see
  tools/emudiff.py's handler_probe and handler_live. Being reachable is not the
  same as being compared: most handlers take a TEntityWorld, our abstraction
  over globals the original reads directly, and each needs mapping first.
  --------------------------------------------------------------------------- }

{ Where tools/emudiff.py places the entity a handler is run on. Scratch, well
  clear of the image, and both halves have to agree on it. }
const
  EMU_ENTITY_AT = $60000000;
  { How many disagreements to print before summarising. High
    enough to see a whole sweep's worth: truncating at 15 hid
    two thirds of the first entity-layer run. }
  EMUDIFF_REPORT_CAP = 80;

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
  IsBool, HasMem: Boolean;
  WantMem, GotMem: string;
  Divergent, DivConfirmed, DivStale, HandlerType, HSlot: Integer;
  HW: TCountingWorld;
  HPool: TEntityPool;
  HP: TPlayerState;
  HL: TLayerInfo;
  HInp: TInputState;

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

  { The entity the emulator was GIVEN, decoded from the case's own mem= entry.

    This replaces rebuilding it out of a handful of f.* fields. That worked
    while the cases were arithmetic on two or three fields and broke the moment
    a handler was run on a fully populated entity: the Pascal started from
    FillChar and the emulator from 260 specified bytes, so every field the
    f.* list did not mention came back as a difference. Reading the same mem=
    both sides read removes a whole class of harness-shaped failures, and it
    means a new case set needs no new f.* mapping at all. }
  function LoadEntityFromMem(At: LongWord; var Ent: TEntity): Boolean;
  var
    N, Idx, B: Integer;
    Want, Hex: string;
    V: LongWord;
  begin
    Result := False;
    FillChar(Ent, SizeOf(Ent), 0);
    Want := 'mem=0x' + LowerCase(IntToHex(At, 1)) + ':';
    for N := 0 to F.Count - 1 do
      if LowerCase(Copy(F[N], 1, Length(Want))) = LowerCase(Want) then
      begin
        Hex := Copy(F[N], Length(Want) + 1, MaxInt);
        for Idx := 0 to High(Ent.Raw) do
        begin
          if (Idx + 1) * 8 > Length(Hex) then
            Break;
          V := 0;
          for B := 0 to 3 do
            V := V or (LongWord(StrToInt('$' + Copy(Hex, Idx * 8 + B * 2 + 1, 2)))
                       shl (B * 8));
          Ent.Raw[Idx] := Integer(V);
        end;
        Exit(True);
      end;
  end;

  { The entity as the emulator would have read it back: little-endian int32s,
    lowercase hex, which is exactly what EmuDiff.java's get= emits. }
  function HexOfEntity(const Ent: TEntity): string;
  var
    N, B: Integer;
    V: LongWord;
  begin
    Result := '';
    for N := 0 to High(Ent.Raw) do
    begin
      V := LongWord(Ent.Raw[N]);
      for B := 0 to 3 do
        Result := Result + LowerCase(IntToHex((V shr (B * 8)) and $FF, 2));
    end;
  end;

  { The get= value carried AFTER the arrow, which is the original's answer.
    A get= before the arrow would be the request, so the search starts past
    it. Empty when the case has no memory channel. }
  function WantedMem(From: Integer): string;
  var
    N: Integer;
  begin
    Result := '';
    for N := From to F.Count - 1 do
      if Copy(F[N], 1, 4) = 'get=' then
      begin
        Result := LowerCase(Copy(F[N], 5, MaxInt));
        Exit;
      end;
  end;

  { The entity type whose handler lives at this address, or -1.

    ONE ARM FOR ALL 78. The alternative was 78 hand-written case arms here,
    each rebuilding the same entity and calling one handler - which is a second
    copy of the dispatcher, in the test, free to drift from the real one. This
    reads the same HANDLER_ADDR table --selftest-entities already checks
    against the binary's jump table, and dispatches through the same
    EntityRunHandler the frame loop uses. }
  function HandlerTypeForAddr(A: Integer): Integer;
  var
    N: Integer;
  begin
    Result := -1;
    for N := 0 to High(HANDLER_ADDR) do
      if (HANDLER_ADDR[N] <> 0) and (Cardinal(A) = HANDLER_ADDR[N]) then
        Exit(N);
  end;

  { Which int index first differs, so a failure points at a field instead of
    at 520 hex digits. -1 when they agree. }
  function FirstDifferingInt(const A, B: string): Integer;
  var
    N: Integer;
  begin
    Result := -1;
    for N := 0 to (Length(A) div 8) - 1 do
      if Copy(A, N * 8 + 1, 8) <> Copy(B, N * 8 + 1, 8) then
        Exit(N);
    if A <> B then
      Result := Length(A) div 8;
  end;

begin
  Result := 0;
  Bad := 0; Ran := 0; Faulted := 0; NoRef := 0;
  DivConfirmed := 0; DivStale := 0;
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
      HandlerType := HandlerTypeForAddr(Addr);
      Want := AsSigned(StrToInt64(F[Arrow + 1]));
      IsBool := False;
      WantMem := WantedMem(Arrow + 1);
      GotMem := '';
      HasMem := False;
      Divergent := Key('f.div', 0);

      { An entity handler, dispatched generically. The emulator jumped straight
        to the address, so EF_TYPE has to agree with the type whose handler
        that is - otherwise EntityRunHandler would switch somewhere else and
        the two would be running different code while appearing to compare. }
      if HandlerType >= 0 then
      begin
        LoadEntityFromMem(EMU_ENTITY_AT, E);
        if E.Raw[EF_TYPE] <> HandlerType then
        begin
          Log.Add(Format('  %-26s case is at type %d''s handler but the entity '
            + 'says type %d - it would dispatch elsewhere',
            [Name, HandlerType, E.Raw[EF_TYPE]]));
          Inc(Bad);
          Continue;
        end;
        HPool := TEntityPool.Create;
        HW := TCountingWorld.Create;
        try
          HW.Pool := HPool;
          FillChar(HP, SizeOf(HP), 0);
          FillChar(HL, SizeOf(HL), 0);
          FillChar(HInp, SizeOf(HInp), 0);
          RandomSeed := Cardinal(Key('f.seed', 0));

          { THE ENTITY GOES INTO THE POOL, AT ITS OWN SLOT, AND THE HANDLER
            RUNS ON THAT COPY.

            Not a detail. Several handlers reach back through the pool by slot
            index rather than through the reference they were handed - Steer
            @ 0x00461738 is the clearest, taking a slot number and working on
            FSlots[Slot]. Run the handler on a standalone record and those
            writes land on a different entity, so the record read back is
            missing everything the helper did. That is what made types 46, 48,
            51, 55 and 57 all differ on int 19: our Steer was correct and was
            faithfully updating the wrong entity.

            In the original there is no distinction to get wrong - the handler
            is passed a pointer straight into the pool array. Putting the
            entity in the pool is what makes the two the same storage. }
          HSlot := E.Raw[EF_SLOT];
          if (HSlot < 0) or (HSlot >= ENTITY_COUNT) then
          begin
            Log.Add(Format('  %-26s EF_SLOT is %d, outside the pool',
                           [Name, HSlot]));
            Inc(Bad);
            Inc(Ran);
            Continue;
          end;
          HPool.Entity(HSlot)^ := E;
          { The game state the ORIGINAL will read out of its global, not
            the register - see the note in tools/emudiff.py. }
          EntityRunHandler(HPool.Entity(HSlot)^, HP, HL, HInp, HW,
                           Key('f.gamestate', 0));
          GotMem := HexOfEntity(HPool.Entity(HSlot)^);
          HasMem := True;
          Got := 0;
        finally
          HW.Free;
          HPool.Free;
        end;
        Inc(Ran);
      end
      else
      case Addr of
        $004513E0:
          Got := AngleBetween(Key('eax', 0), Key('edx', 0),
                              Key('ecx', 0), Stk[0]);
        $0045114C:
          { The real function now, not a restatement of it here. }
          Got := Compare(Key('eax', 0), Key('edx', 0));
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
        { The two handlers that are pure functions of their entity. Both are
          run on an entity built the same way the emulator's was, and the
          whole record is handed back for comparison. }
        $0045A944:
          begin
            LoadEntityFromMem(EMU_ENTITY_AT, E);
            EntityUpdate_Type16_Sign(E);
            GotMem := HexOfEntity(E);
            HasMem := True;
            Got := 0;
          end;
        $0045A4F0:
          begin
            LoadEntityFromMem(EMU_ENTITY_AT, E);
            EntityUpdate_Type25(E);
            GotMem := HexOfEntity(E);
            HasMem := True;
            Got := 0;
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

      if HandlerType < 0 then
        Inc(Ran);

      { The memory channel, where there is one. EAX is not compared for a
        handler: it returns whatever its last expression left behind, which is
        not a value the original means anything by. }
      if HasMem then
      begin
        if WantMem = '' then
        begin
          Log.Add(Format('  %-26s asked for memory back and the emulator '
            + 'returned none', [Name]));
          Inc(Bad);
        end
        else if Divergent <> 0 then
        begin
          { A declared divergence. Differing is what the ledger predicts, so
            AGREEING is the failure - the entry would be describing something
            that is no longer true. }
          if WantMem = GotMem then
          begin
            Log.Add(Format('  %-26s DIV-%.3d says this should differ from the '
              + 'original and it does not - the ledger entry is stale',
              [Name, Divergent]));
            Inc(DivStale);
            Inc(Bad);
          end
          else
          begin
            J := FirstDifferingInt(WantMem, GotMem);
            Log.Add(Format('  %-26s DIV-%.3d confirmed: entity int %d, '
              + 'original %s, ours %s', [Name, Divergent, J,
              Copy(WantMem, J * 8 + 1, 8), Copy(GotMem, J * 8 + 1, 8)]));
            Inc(DivConfirmed);
          end;
        end
        else if WantMem <> GotMem then
        begin
          J := FirstDifferingInt(WantMem, GotMem);
          if Bad < EMUDIFF_REPORT_CAP then
            Log.Add(Format('  %-26s entity int %d: original %s, '
              + 'reconstruction %s', [Name, J,
              Copy(WantMem, J * 8 + 1, 8), Copy(GotMem, J * 8 + 1, 8)]));
          Inc(Bad);
        end;
      end
      else if Got <> Want then
      begin
        if Bad < EMUDIFF_REPORT_CAP then
          Log.Add(Format('  %-26s original %d, reconstruction %d',
            [Name, Want, Got]));
        Inc(Bad);
      end;
    end;

    Log.Add(Format('%d cases compared, %d disagree', [Ran, Bad]));
    if DivConfirmed > 0 then
      Log.Add(Format('%d declared divergence(s) exercised and confirmed - the '
        + 'original really does differ there', [DivConfirmed]));
    if DivStale > 0 then
      Log.Add(Format('%d declared divergence(s) no longer exist - fix '
        + 'notes/divergences.md', [DivStale]));
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
      else if ParamStr(1) = '--selftest-runner' then
        Result := SelfTestRunner(Log)
      else if ParamStr(1) = '--selftest-session' then
        Result := SelfTestSession(Log)
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

{ entry @ 0x0046716C - the .dpr program block, which Delphi compiles into a
  function of its own. Four statements:

      Application.Initialize
      Application.Title := 'Akuji the Demon'
      Application.CreateForm(TFrm_main, Frm_main)
      Application.Run

  and everything the game does hangs off the last one, because
  TApplication.Run's idle handler is TFrm_main_AppIdle.

  The self-test dispatch above the four is OURS. DIVERGENCE DIV-007: it is
  not in the original
  and it is deliberately before Application.Initialize so a test run never
  creates a window.

  This is the one routine in the language with no declaration to hang an
  address on, which is why it sat in the backlog looking unwritten;
  tools/implemented.py now recognises a program block specifically. }
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
     (ParamStr(1) = '--selftest-runner') or
     (ParamStr(1) = '--selftest-session') or
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
