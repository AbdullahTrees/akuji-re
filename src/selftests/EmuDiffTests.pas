{ The differential harness against the reference executable, and the map probe
  that dumps what a shipped stage actually contains. }

unit EmuDiffTests;

{$MODE DELPHI}{$H+}

interface

uses
  Classes, SysUtils, TypInfo,
  QdaArchive, SoundTable, WaveFile, AudioMixer, AudioOut, MidiFile, KbgmPlayer,
  Directions, Entities, EventScripts, EventCommands, PlayerState, GameState,
  Stages, Camera, TileMaps, Player, EntityHandlers, EventRunner, GameSession,
  SpritePool, Sprites, Dialogue, BgAnime, UnitInit, Title, Ending, Opening,
  GameFont, DDDDComponent, Surfaces,
  Graphics;

function EmuDiff(Log: TStringList): Integer;
function SelfTestMapProbe(Log: TStringList): Integer;

implementation

uses
  EntityTests;

{ --emudiff <emu-output> compares deterministic Pascal results with cases run
  against akuji.exe by ghidra_scripts/EmuDiff.java and tools/emudiff.py.

  Ordinary cases compare EAX. Handler cases may additionally provide get=<hex>
  for the mutated entity bytes. f.div=<n> marks an intentional divergence from
  notes/divergences.md and therefore requires the two results to differ.

  The emulator has no Windows, import, or VCL environment. Routines that depend
  on those services remain outside this comparison. }

{ Where tools/emudiff.py places the entity a handler is run on. Scratch, well
  clear of the image, and both halves have to agree on it. }
const
  EMU_ENTITY_AT = $60000000;
  { Show enough disagreements to cover a complete handler sweep. }
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
  I, J, Arrow, Addr, Got, Want, Bad, Ran, Faulted, NoRef, Controls: Integer;
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
  Bad := 0; Ran := 0; Faulted := 0; NoRef := 0; Controls := 0;
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

      { A negative control asks whether the emulator FAULTS, not whether the
        two agree. Two of them sit at handler addresses and pass a wild entity
        pointer, so comparing them would report the unmapped memory's zeroed
        type as a disagreement. tools/emudiff.py --sanity is what judges these. }
      if Key('f.control', 0) <> 0 then
      begin
        Inc(Controls);
        Continue;
      end;

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
          { The same value the case placed at 0x00484EF4. Left at 0 our
            side treats every tile as solid, because the test is
            `tile >= threshold` and an absent tilemap reads 0. }
          HW.SolidThreshold := Key('f.solid', 0);
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
            EntityUpdate_Type16_InfoSign(E);
            GotMem := HexOfEntity(E);
            HasMem := True;
            Got := 0;
          end;
        $0045A4F0:
          begin
            LoadEntityFromMem(EMU_ENTITY_AT, E);
            EntityUpdate_Type25_Door(E);
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
    if Controls > 0 then
      Log.Add(Format('%d negative controls not compared - they are judged by '
        + 'whether they faulted', [Controls]));
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

{ --- Map-loading probe -----------------------------------------------------
  Run GmMain's stage-loading sequence and report the selected map, tileset,
  terrain, surface, and draw results. }
function SelfTestMapProbe(Log: TStringList): Integer;
var
  GameDir: string;
  Stages: TStageTable;
  Map: TTileMap;
  Arch: TQdaArchive;
  Surf: TSurfaceSet;
  Bmp: TBitmap;
  L: TLayerInfo;
  MapId, Tileset, Terrain, Stage, Painted, PX, PY: Integer;
begin
  Result := 0;
  GameDir := IncludeTrailingPathDelimiter(ParamStr(2));
  Stage := StrToIntDef(ParamStr(3), 1);
  Log.Add(Format('game dir: %s', [GameDir]));
  Log.Add(Format('stage:    %d', [Stage]));

  Stages := TStageTable.Create;
  Map := TTileMap.Create;
  try
    if Stages.Load(GameDir) <= 0 then
    begin
      Log.Add('FAILED: stage table did not load');
      Exit(1);
    end;
    Log.Add(Format('stage table rows: %d', [Stages.Count]));
    if (Stage < 0) or (Stage >= Stages.Count) then
    begin
      Log.Add('FAILED: stage out of range');
      Exit(1);
    end;

    MapId   := Stages.Layer[Stage, 0];
    Tileset := Stages.Tileset[Stage, 0];
    Terrain := Stages.TerrainId[Stage];
    Log.Add(Format('Layer[%d,0]   = %d   (the map file to load)', [Stage, MapId]));
    Log.Add(Format('Tileset[%d,0] = %d   (surface slot to draw from)', [Stage, Tileset]));
    Log.Add(Format('TerrainId[%d] = %d', [Stage, Terrain]));

    if MapId = LAYER_NONE then
    begin
      Log.Add('FAILED: no map for this stage - nothing would draw and');
      Log.Add('        nothing would be solid, which is black plus a fall');
      Exit(1);
    end;

    if not Map.Load(GameDir, MapId) then
    begin
      Log.Add(Format('FAILED: map %.3d did not load', [MapId]));
      Exit(1);
    end;
    Log.Add(Format('map %.3d: %dx%d tiles, tile %dx%d, sheet %dx%d',
      [MapId, Map.MapWidth, Map.MapHeight, Map.TileWidth, Map.TileHeight,
       Map.SheetCols, Map.SheetRows]));

    { --- and now actually DRAW it, which is where black comes from ------- }
    Arch := TQdaArchive.Create(GameDir + 'bmp.qda');
    Surf := TSurfaceSet.Create(Arch);
    Bmp := TBitmap.Create;
    try
      Surf.LoadSet(GameDir, Stages.SurfaceSet[Stage]);
      Log.Add(Format('surface set %d loaded; slot %d is %s',
        [Stages.SurfaceSet[Stage], Tileset,
         BoolToStr(Surf[Tileset] <> nil, 'present', 'NIL')]));

      Bmp.SetSize(SCREEN_W, SCREEN_H);
      Bmp.Canvas.Brush.Color := clBlack;
      Bmp.Canvas.FillRect(0, 0, SCREEN_W, SCREEN_H);
      Map.Draw(Bmp.Canvas, Surf, Tileset, 0, 0, SCREEN_W, SCREEN_H);

      Painted := 0;
      for PY := 0 to SCREEN_H - 1 do
        for PX := 0 to SCREEN_W - 1 do
          if Bmp.Canvas.Pixels[PX, PY] <> clBlack then
            Inc(Painted);
      Log.Add(Format('pixels painted at origin 0,0: %d of %d',
        [Painted, SCREEN_W * SCREEN_H]));

      { The camera clamp for a map this shape, and what the screen looks like
        at the bottom-right corner it allows. A map SHORTER than the old one
        has a smaller MaxScrollY, and an origin past it draws nothing. }
      FillChar(L, SizeOf(L), 0);
      L.TileW := Map.TileWidth;    L.TileH := Map.TileHeight;
      L.MapTilesX := Map.MapWidth; L.MapTilesY := Map.MapHeight;
      Log.Add(Format('MaxScrollX = %d, MaxScrollY = %d',
        [Camera.MaxScrollX(L), Camera.MaxScrollY(L)]));

      { AND at the camera a NEW GAME actually starts with. Stage_Begin sets
        the origin straight from PlayerState.ScrollX/ScrollY and nothing
        clamps it, so this is the view the player really gets. }
      Bmp.Canvas.FillRect(0, 0, SCREEN_W, SCREEN_H);
      Map.Draw(Bmp.Canvas, Surf, Tileset, 0, DEFAULT_SCROLL_Y,
               SCREEN_W, SCREEN_H);
      Painted := 0;
      for PY := 0 to SCREEN_H - 1 do
        for PX := 0 to SCREEN_W - 1 do
          if Bmp.Canvas.Pixels[PX, PY] <> clBlack then
            Inc(Painted);
      Log.Add(Format('pixels painted at the NEW GAME camera (0,%d): %d',
        [DEFAULT_SCROLL_Y, Painted]));
      if Painted = 0 then
      begin
        Log.Add('FAILED: black on a new game - the camera opens outside the map');
        Exit(1);
      end;

      Bmp.Canvas.FillRect(0, 0, SCREEN_W, SCREEN_H);
      Map.Draw(Bmp.Canvas, Surf, Tileset,
               Camera.MaxScrollX(L), Camera.MaxScrollY(L), SCREEN_W, SCREEN_H);
      Painted := 0;
      for PY := 0 to SCREEN_H - 1 do
        for PX := 0 to SCREEN_W - 1 do
          if Bmp.Canvas.Pixels[PX, PY] <> clBlack then
            Inc(Painted);
      Log.Add(Format('pixels painted at the clamped corner: %d', [Painted]));

      { OUT OF RANGE ON PURPOSE. The original wraps - the scroll is taken
        modulo the map's pixel size - so one whole map height down must show
        the top of the map again, not blackness. This is the regression test
        for the clamp-versus-wrap bug. }
      Bmp.Canvas.FillRect(0, 0, SCREEN_W, SCREEN_H);
      Map.Draw(Bmp.Canvas, Surf, Tileset,
               0, Map.MapHeight * Map.TileHeight, SCREEN_W, SCREEN_H);
      Painted := 0;
      for PY := 0 to SCREEN_H - 1 do
        for PX := 0 to SCREEN_W - 1 do
          if Bmp.Canvas.Pixels[PX, PY] <> clBlack then
            Inc(Painted);
      Log.Add(Format('pixels painted one map-height down (must wrap): %d',
        [Painted]));
      if Painted = 0 then
      begin
        Log.Add('FAILED: the map CLAMPED instead of wrapping');
        Exit(1);
      end;
      if Painted = 0 then
      begin
        Log.Add('FAILED: the map drew NOTHING - this is the black screen');
        Exit(1);
      end;
    finally
      Bmp.Free;
      Surf.Free;
      Arch.Free;
    end;

    Log.Add('');
    Log.Add('OK - the load path produced a map and it draws');
  finally
    Map.Free;
    Stages.Free;
  end;
end;

end.
