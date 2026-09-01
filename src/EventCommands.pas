{ EventCommands - the mini-language in an event record's two string fields.

  ParamB is a PROGRAM: '/' splits steps, '.' splits the alternatives within a
  step. Both separators are single-character literals in the binary, at
  0x00455098 and 0x0045520C.

  An alternative's leading number is a GUARD - the progress flag that has to
  be set for it to run - not a target.

  THE INTERPRETER READS FIXED POSITIONS, not fields. EventScript_Execute
  @ 0x00455210 pulls Copy(alt, 6, 2) for the sub-opcode and then Copy at 9,
  14, 19, 24 and 29 for arguments, so the zero-padding in the data is
  load-bearing rather than cosmetic. This unit splits on '-' instead, which
  accepts everything the fixed-position reader does and more.

  Sub-opcode meanings are in the SUBOP_ constants below. Two behave unlike the
  rest: 15 tests a counted list of flags before setting one, and 80 never
  advances the step - it drives its own three phases and ends in GS_ENDING.

  Derivation and the full opcode/ParamA census: notes/event_language.md }

unit EventCommands;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Classes;

const
  { All from EventScript_Execute @ 0x00455210. The four with no name in the
    original sense - 1, 6, 11, 14 - never occur in the shipped data; they are
    listed in the header but given no constant here, since nothing uses them. }
  SUBOP_LOAD_STAGE   = 0;
  SUBOP_DIALOGUE     = 3;    { arg[0] indexes the stage's tk file }
  SUBOP_SET_FLAG     = 4;
  SUBOP_CLEAR_FLAG   = 5;
  SUBOP_DISABLE_EVENT = 7;
  SUBOP_DESTROY      = 8;
  SUBOP_PLAY_SOUND   = 9;
  SUBOP_SUBMODE      = 10;
  SUBOP_PLAY_MUSIC   = 12;
  SUBOP_SAVE         = 13;
  SUBOP_TEST_FLAGS   = 15;   { arg[1] is a count; that many items follow }
  SUBOP_ENTITY_FIELD = 16;
  SUBOP_WAIT         = 17;
  SUBOP_SOUL_GET     = 80;
  SUBOP_NOP          = 99;

  { Kept as the old name so existing callers still compile. }
  SUBOP_LIST = SUBOP_TEST_FLAGS;

  MAX_CMD_ARGS = 12;     { the widest observed is sub-op 15 with 7 }

  { The six ParamA kind letters and the argument count each one takes. Held as
    two parallel strings/arrays rather than a case so KindArity can report an
    unknown letter instead of silently accepting it. }
  KIND_LETTERS: string = '*A/JRM';
  KIND_ARITY: array[1..6] of Integer = (0, 1, 2, 2, 2, 3);

  { Argument count per sub-opcode, or ARITY_VARIABLE / ARITY_UNKNOWN.
    Index is the sub-opcode; the table is what the data shows, and
    CheckArity is what enforces it. }
  ARITY_UNKNOWN  = -1;
  ARITY_VARIABLE = -2;

  SUBOP_ARITY: array[0..99] of Integer = (
    { 00 }  5, -1,  0,  1,  1,  1, -1,  0,  0,  1,
    { 10 }  0, -1,  3,  0, -1, -2,  1,  1, -1, -1,
    { 20 } -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    { 30 } -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    { 40 } -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    { 50 } -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    { 60 } -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    { 70 } -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    { 80 }  0, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    { 90 } -1, -1, -1, -1, -1, -1, -1, -1, -1,  0);

type
  { What a record's ParamB actually holds. See the header: this is a function of
    the opcode, not something to sniff per record - but ClassifyParamB does look
    at the text, so that a disagreement with OpcodeExpects shows up as a failure
    instead of being assumed away. }
  TParamBKind = (pbNone, pbId, pbProgram);

  { One alternative: <guard>-<subop>[-args]. Raw is kept so that one whose
    meaning is still unknown can be round-tripped or logged verbatim. }
  TEventCommand = record
    Guard:    Integer;   { progress-flag index; runs only if that flag is set }
    SubOp:    Integer;
    ArgCount: Integer;
    Args:     array[0..MAX_CMD_ARGS - 1] of Integer;
    Raw:      string;
  end;

  TEventCommandArray = array of TEventCommand;

  { One step of a ParamB program - the alternatives between two '/'. Despite
    holding several, a step performs at most ONE of them; see SelectAlternative
    and the header. The field is called Alternatives rather than Commands
    deliberately: an earlier version of this unit read them as commands that all
    run, which is wrong. }
  TEventStep = record
    Alternatives: TEventCommandArray;
  end;

  TEventProgram = array of TEventStep;

  { ParamA: what the event places. }
  TEventSpawn = record
    TypeId:   Integer;    { 14..80; indexes ENTITY_TYPES }
    Kind:     Char;       { '*' 'A' '/' 'M' 'R' 'J' }
    ArgCount: Integer;
    Args:     array[0..MAX_CMD_ARGS - 1] of Integer;
    Raw:      string;
    Valid:    Boolean;
  end;

{ Splits on '-' while treating a '-' that introduces digits as a minus sign, so
  '0030-M-0-0128--4' yields ('0030','M','0','0128','-4') rather than an empty
  field. This is the only subtle piece of the grammar; everything downstream
  depends on it. }
procedure ParseFields(const S: string; Dest: TStrings);

{ ParamA. Valid is False when the leading field is not four digits or the type
  is outside ENTITY_TYPES - the original would simply index out of bounds. }
function ParseSpawn(const ParamA: string): TEventSpawn;

{ Classifies ParamB by looking at the text: '' or '*' is pbNone, all digits is
  pbId, anything else is pbProgram. }
function ClassifyParamB(const ParamB: string): TParamBKind;

{ The shape ParamB has for a given opcode, from the shipped data. pbNone means
  the opcode is not one of the seven that occur. }
function OpcodeExpects(Opcode: Integer): TParamBKind;

{ ParamB as a program. pbNone and pbId both yield a zero-length program rather
  than a bogus one-command step - a bare id like '1048' is a number, and reading
  it as a command would invent a sub-opcode that is not there. }
function ParseProgram(const ParamB: string): TEventProgram;

{ ParamB as a bare id, or -1 when it is not one. }
function ParseId(const ParamB: string): Integer;

{ True when Cmd's argument count agrees with SUBOP_ARITY, including sub-op 15's
  self-describing length. Unknown sub-opcodes pass - absence of evidence is not
  a violation. }
function CheckArity(const Cmd: TEventCommand): Boolean;

{ Arguments the kind letter takes, or -1 if the letter is not one of the six. }
function KindArity(Kind: Char): Integer;

{ True when a parsed ParamA's argument count matches its kind letter. An
  unknown letter fails, unlike an unknown sub-opcode - there are only six and a
  seventh would mean the grammar is incomplete. }
function CheckSpawnArity(const Sp: TEventSpawn): Boolean;

{ The character position and width the interpreter reads argument N from, for
  the given sub-opcode. Returns False when the sub-opcode has no argument N.
  Positions are 1-based, matching Delphi's Copy and the addresses in the header.

  This exists so --selftest-script can read the data the way the ORIGINAL does
  and compare it against the dash-split parse. }
function ArgPosition(SubOp, Index: Integer; out Start, Len: Integer): Boolean;

{ The same thing for ParamA: where Events_SpawnNearCamera copies argument
  Index for a placement of kind Kind. False when that kind has no argument
  there. Positions and widths are read out of the function; see the header. }
function SpawnArgPosition(Kind: Char; Index: Integer;
  out Start, Len: Integer): Boolean;

{ Number of alternatives across every step, for reporting. }
function CommandCount(const Prog: TEventProgram): Integer;

{ The alternative a step selects for the given progress flags, or -1 when none
  qualifies and the step does nothing. Reproduces EventScript_AdvanceStep's
  backwards scan exactly, including that the LAST matching alternative wins. }
function SelectAlternative(const Step: TEventStep;
  const Progress: array of Byte): Integer;

implementation

procedure ParseFields(const S: string; Dest: TStrings);
var
  I, Start: Integer;
begin
  Dest.Clear;
  I := 1;
  Start := 1;
  while I <= Length(S) do
  begin
    if S[I] = '-' then
    begin
      if I > Start then
      begin
        { A '-' with something before it ends the field. }
        Dest.Add(Copy(S, Start, I - Start));
        Start := I + 1;
      end;
      { Otherwise the '-' IS the field's first character, i.e. a minus sign, and
        Start is left pointing at it so the sign survives into the number. This
        is the whole reason the splitter is hand-written: in '0030-M-0-0128--4'
        the run '--' is a separator followed by a sign, and a plain Split would
        yield an empty field and lose the -4. }
      Inc(I);
      Continue;
    end;
    Inc(I);
  end;
  Dest.Add(Copy(S, Start, Length(S) - Start + 1));
end;

function DigitsOnly(const S: string): Boolean;
var
  I, First: Integer;
begin
  Result := False;
  if S = '' then
    Exit;
  First := 1;
  if S[1] = '-' then
  begin
    if Length(S) = 1 then
      Exit;
    First := 2;
  end;
  for I := First to Length(S) do
    if not (S[I] in ['0'..'9']) then
      Exit;
  Result := True;
end;

function ParseSpawn(const ParamA: string): TEventSpawn;
var
  F: TStringList;
  I: Integer;
begin
  Result.TypeId := -1;
  Result.Kind := #0;
  Result.ArgCount := 0;
  Result.Raw := ParamA;
  Result.Valid := False;
  for I := 0 to MAX_CMD_ARGS - 1 do
    Result.Args[I] := 0;

  F := TStringList.Create;
  try
    ParseFields(ParamA, F);
    if F.Count < 2 then
      Exit;
    if (Length(F[0]) <> 4) or not DigitsOnly(F[0]) then
      Exit;
    if Length(F[1]) <> 1 then
      Exit;

    Result.TypeId := StrToIntDef(F[0], -1);
    Result.Kind := F[1][1];
    for I := 2 to F.Count - 1 do
    begin
      if Result.ArgCount >= MAX_CMD_ARGS then
        Break;
      Result.Args[Result.ArgCount] := StrToIntDef(F[I], 0);
      Inc(Result.ArgCount);
    end;
    Result.Valid := True;
  finally
    F.Free;
  end;
end;

function ParseCommand(const S: string): TEventCommand;
var
  F: TStringList;
  I: Integer;
begin
  Result.Guard := -1;
  Result.SubOp := -1;
  Result.ArgCount := 0;
  Result.Raw := S;
  for I := 0 to MAX_CMD_ARGS - 1 do
    Result.Args[I] := 0;

  F := TStringList.Create;
  try
    ParseFields(S, F);
    if F.Count < 2 then
      Exit;
    Result.Guard := StrToIntDef(F[0], -1);
    Result.SubOp := StrToIntDef(F[1], -1);
    for I := 2 to F.Count - 1 do
    begin
      if Result.ArgCount >= MAX_CMD_ARGS then
        Break;
      Result.Args[Result.ArgCount] := StrToIntDef(F[I], 0);
      Inc(Result.ArgCount);
    end;
  finally
    F.Free;
  end;
end;

function ClassifyParamB(const ParamB: string): TParamBKind;
begin
  if (ParamB = '') or (ParamB = '*') then
    Exit(pbNone);
  if DigitsOnly(ParamB) then
    Exit(pbId);
  Result := pbProgram;
end;

function OpcodeExpects(Opcode: Integer): TParamBKind;
begin
  case Opcode of
    0, 1, 4, 6, 7: Result := pbProgram;
    5:             Result := pbId;
    { Opcode 9 is the one that varies - 127 bare ids and 104 '*'. Both are
      "not a program", so the caller checks ClassifyParamB for the difference. }
    9:             Result := pbId;
  else
    Result := pbNone;
  end;
end;

function ParseId(const ParamB: string): Integer;
begin
  if ClassifyParamB(ParamB) <> pbId then
    Exit(-1);
  Result := StrToIntDef(ParamB, -1);
end;

function ParseProgram(const ParamB: string): TEventProgram;
var
  Steps, Cmds: TStringList;
  S, C: Integer;
begin
  { nil, not SetLength(...,0): the result is a dynamic array, so SetLength would
    read it before it is assigned and FPC rightly warns. }
  Result := nil;
  if ClassifyParamB(ParamB) <> pbProgram then
    Exit;

  Steps := TStringList.Create;
  Cmds := TStringList.Create;
  try
    Steps.Delimiter := '/';
    Steps.StrictDelimiter := True;
    Steps.DelimitedText := ParamB;

    SetLength(Result, Steps.Count);
    for S := 0 to Steps.Count - 1 do
    begin
      Cmds.Delimiter := '.';
      Cmds.StrictDelimiter := True;
      Cmds.DelimitedText := Steps[S];

      SetLength(Result[S].Alternatives, Cmds.Count);
      for C := 0 to Cmds.Count - 1 do
        Result[S].Alternatives[C] := ParseCommand(Cmds[C]);
    end;
  finally
    Cmds.Free;
    Steps.Free;
  end;
end;

function KindArity(Kind: Char): Integer;
var
  I: Integer;
begin
  I := Pos(Kind, KIND_LETTERS);
  if I = 0 then
    Exit(-1);
  Result := KIND_ARITY[I];
end;

function CheckSpawnArity(const Sp: TEventSpawn): Boolean;
var
  Want: Integer;
begin
  if not Sp.Valid then
    Exit(False);
  Want := KindArity(Sp.Kind);
  if Want < 0 then
    Exit(False);
  Result := Sp.ArgCount = Want;
end;

function CheckArity(const Cmd: TEventCommand): Boolean;
var
  Want: Integer;
begin
  if (Cmd.SubOp < 0) or (Cmd.SubOp > High(SUBOP_ARITY)) then
    Exit(False);

  Want := SUBOP_ARITY[Cmd.SubOp];
  if Want = ARITY_UNKNOWN then
    Exit(True);

  if Want = ARITY_VARIABLE then
  begin
    { Sub-op 15: args are <id> <count> then <count> items. }
    if Cmd.ArgCount < 2 then
      Exit(False);
    Exit(Cmd.Args[1] = Cmd.ArgCount - 2);
  end;

  Result := Cmd.ArgCount = Want;
end;

function CommandCount(const Prog: TEventProgram): Integer;
var
  S: Integer;
begin
  Result := 0;
  for S := 0 to High(Prog) do
    Inc(Result, Length(Prog[S].Alternatives));
end;

function ArgPosition(SubOp, Index: Integer; out Start, Len: Integer): Boolean;
begin
  Start := 0;
  Len := 0;
  Result := True;
  case SubOp of
    SUBOP_LOAD_STAGE:
      if (Index >= 0) and (Index <= 4) then
      begin
        Start := 9 + Index * 5;   { 9, 14, 19, 24, 29 }
        Len := 4;
      end
      else
        Result := False;
    SUBOP_DIALOGUE, SUBOP_SET_FLAG, SUBOP_CLEAR_FLAG, SUBOP_PLAY_SOUND:
      if Index = 0 then begin Start := 9; Len := 4; end else Result := False;
    SUBOP_PLAY_MUSIC:
      case Index of
        0: begin Start := 9;  Len := 3; end;
        1: begin Start := 13; Len := 1; end;
        2: begin Start := 15; Len := 1; end;
      else
        Result := False;
      end;
    SUBOP_ENTITY_FIELD:
      if Index = 0 then begin Start := 9; Len := 3; end else Result := False;
    SUBOP_WAIT:
      if Index = 0 then begin Start := 9; Len := 6; end else Result := False;
    SUBOP_TEST_FLAGS:
      { Only the two LEADING fields are at fixed positions - the flag to set
        and how many items follow. The items themselves are then at
        17 + 6*N, but they are not arguments in the arity sense and the
        interpreter reads them with its own stride, so they are not here. }
      case Index of
        0: begin Start := 9;  Len := 4; end;
        1: begin Start := 14; Len := 2; end;
      else
        Result := False;
      end;
  else
    { 7, 8, 10, 13, 80, 99 take no arguments. }
    Result := False;
  end;
end;

function SpawnArgPosition(Kind: Char; Index: Integer;
  out Start, Len: Integer): Boolean;
begin
  Start := 0;
  Len := 0;
  Result := True;
  case Kind of
    'A': if Index = 0 then begin Start := 8; Len := 4; end else Result := False;
    '/': case Index of
           0: begin Start := 8;  Len := 4; end;
           1: begin Start := 13; Len := 3; end;
         else Result := False;
         end;
    'M': case Index of
           0: begin Start := 8;  Len := 1; end;
           1: begin Start := 10; Len := 4; end;
           2: begin Start := 15; Len := 2; end;
         else Result := False;
         end;
    'R': case Index of
           0: begin Start := 8;  Len := 2; end;
           1: begin Start := 11; Len := 3; end;
         else Result := False;
         end;
    'J': case Index of
           0: begin Start := 8;  Len := 4; end;
           1: begin Start := 13; Len := 4; end;
         else Result := False;
         end;
  else
    Result := False;      { '*' takes none, and so does an unknown letter }
  end;
end;

function SelectAlternative(const Step: TEventStep;
  const Progress: array of Byte): Integer;
var
  I, G: Integer;
begin
  { Backwards, first match wins - so of several qualifying alternatives it is
    the LAST one in the file that runs. }
  for I := High(Step.Alternatives) downto 0 do
  begin
    G := Step.Alternatives[I].Guard;
    if (G >= 0) and (G <= High(Progress)) and (Progress[G] <> 0) then
      Exit(I);
  end;
  Result := -1;
end;

end.
