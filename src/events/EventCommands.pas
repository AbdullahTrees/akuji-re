{ Parser for the event mini-language stored in ParamA and ParamB.

  ParamB is a PROGRAM: '/' splits steps, '.' splits the alternatives within a
  step.

  An alternative's leading number is a GUARD - the progress flag that has to
  be set for it to run - not a target.

  Command fields are zero-padded to fixed positions in the data. This parser
  splits on `-` while preserving compatible values.

  Sub-opcodes 15 and 80 have special control flow: 15 consumes a counted flag
  list, while 80 owns a three-phase sequence and does not advance normally. }

unit EventCommands;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Classes;

const
  { Sub-opcodes 1, 6, 11, and 14 do not occur in the shipped data. }
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

  { One ParamB step. At most one guarded alternative executes. }
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

{ ParamA. Valid is False when the leading field is not four digits. }
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
  Positions are 1-based, matching Copy. }
function ArgPosition(SubOp, Index: Integer; out Start, Len: Integer): Boolean;

{ The same fixed-column lookup for a ParamA placement. Returns False when the
  placement kind has no argument at Index. }
function SpawnArgPosition(Kind: Char; Index: Integer;
  out Start, Len: Integer): Boolean;

{ Number of alternatives across every step, for reporting. }
function CommandCount(const Prog: TEventProgram): Integer;

{ The alternative a step selects for the given progress flags, or -1 when none
  qualifies. The last matching alternative wins. }
function SelectAlternative(const Step: TEventStep;
  const Progress: array of Byte): Integer;

implementation

procedure ParseFields(const S: string; Dest: TStrings);
var
  CharacterIndex, FieldStart: Integer;
begin
  Dest.Clear;
  CharacterIndex := 1;
  FieldStart := 1;
  while CharacterIndex <= Length(S) do
  begin
    if S[CharacterIndex] = '-' then
    begin
      if CharacterIndex > FieldStart then
      begin
        { A '-' with something before it ends the field. }
        Dest.Add(Copy(S, FieldStart, CharacterIndex - FieldStart));
        FieldStart := CharacterIndex + 1;
      end;
      { Otherwise the '-' IS the field's first character, i.e. a minus sign, and
        Start is left pointing at it so the sign survives into the number. This
        is the whole reason the splitter is hand-written: in '0030-M-0-0128--4'
        the run '--' is a separator followed by a sign, and a plain Split would
        yield an empty field and lose the -4. }
      Inc(CharacterIndex);
      Continue;
    end;
    Inc(CharacterIndex);
  end;
  Dest.Add(Copy(S, FieldStart, Length(S) - FieldStart + 1));
end;

function DigitsOnly(const S: string): Boolean;
var
  CharacterIndex, FirstDigit: Integer;
begin
  Result := False;
  if S = '' then
    Exit;
  FirstDigit := 1;
  if S[1] = '-' then
  begin
    if Length(S) = 1 then
      Exit;
    FirstDigit := 2;
  end;
  for CharacterIndex := FirstDigit to Length(S) do
    if not (S[CharacterIndex] in ['0'..'9']) then
      Exit;
  Result := True;
end;

function ParseSpawn(const ParamA: string): TEventSpawn;
var
  Fields: TStringList;
  FieldIndex: Integer;
begin
  Result.TypeId := -1;
  Result.Kind := #0;
  Result.ArgCount := 0;
  Result.Raw := ParamA;
  Result.Valid := False;
  for FieldIndex := 0 to MAX_CMD_ARGS - 1 do
    Result.Args[FieldIndex] := 0;

  Fields := TStringList.Create;
  try
    ParseFields(ParamA, Fields);
    if Fields.Count < 2 then
      Exit;
    if (Length(Fields[0]) <> 4) or not DigitsOnly(Fields[0]) then
      Exit;
    if Length(Fields[1]) <> 1 then
      Exit;

    Result.TypeId := StrToIntDef(Fields[0], -1);
    Result.Kind := Fields[1][1];
    for FieldIndex := 2 to Fields.Count - 1 do
    begin
      if Result.ArgCount >= MAX_CMD_ARGS then
        Break;
      Result.Args[Result.ArgCount] := StrToIntDef(Fields[FieldIndex], 0);
      Inc(Result.ArgCount);
    end;
    Result.Valid := True;
  finally
    Fields.Free;
  end;
end;

function ParseCommand(const S: string): TEventCommand;
var
  Fields: TStringList;
  FieldIndex: Integer;
begin
  Result.Guard := -1;
  Result.SubOp := -1;
  Result.ArgCount := 0;
  Result.Raw := S;
  for FieldIndex := 0 to MAX_CMD_ARGS - 1 do
    Result.Args[FieldIndex] := 0;

  Fields := TStringList.Create;
  try
    ParseFields(S, Fields);
    if Fields.Count < 2 then
      Exit;
    Result.Guard := StrToIntDef(Fields[0], -1);
    Result.SubOp := StrToIntDef(Fields[1], -1);
    for FieldIndex := 2 to Fields.Count - 1 do
    begin
      if Result.ArgCount >= MAX_CMD_ARGS then
        Break;
      Result.Args[Result.ArgCount] := StrToIntDef(Fields[FieldIndex], 0);
      Inc(Result.ArgCount);
    end;
  finally
    Fields.Free;
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
  StepStrings, CommandStrings: TStringList;
  StepIndex, CommandIndex: Integer;
begin
  { nil, not SetLength(...,0): the result is a dynamic array, so SetLength would
    read it before it is assigned and FPC rightly warns. }
  Result := nil;
  if ClassifyParamB(ParamB) <> pbProgram then
    Exit;

  StepStrings := TStringList.Create;
  CommandStrings := TStringList.Create;
  try
    StepStrings.Delimiter := '/';
    StepStrings.StrictDelimiter := True;
    StepStrings.DelimitedText := ParamB;

    SetLength(Result, StepStrings.Count);
    for StepIndex := 0 to StepStrings.Count - 1 do
    begin
      CommandStrings.Delimiter := '.';
      CommandStrings.StrictDelimiter := True;
      CommandStrings.DelimitedText := StepStrings[StepIndex];

      SetLength(Result[StepIndex].Alternatives, CommandStrings.Count);
      for CommandIndex := 0 to CommandStrings.Count - 1 do
        Result[StepIndex].Alternatives[CommandIndex] :=
          ParseCommand(CommandStrings[CommandIndex]);
    end;
  finally
    CommandStrings.Free;
    StepStrings.Free;
  end;
end;

function KindArity(Kind: Char): Integer;
var
  KindIndex: Integer;
begin
  KindIndex := Pos(Kind, KIND_LETTERS);
  if KindIndex = 0 then
    Exit(-1);
  Result := KIND_ARITY[KindIndex];
end;

function CheckSpawnArity(const Sp: TEventSpawn): Boolean;
var
  ExpectedArity: Integer;
begin
  if not Sp.Valid then
    Exit(False);
  ExpectedArity := KindArity(Sp.Kind);
  if ExpectedArity < 0 then
    Exit(False);
  Result := Sp.ArgCount = ExpectedArity;
end;

function CheckArity(const Cmd: TEventCommand): Boolean;
var
  ExpectedArity: Integer;
begin
  if (Cmd.SubOp < 0) or (Cmd.SubOp > High(SUBOP_ARITY)) then
    Exit(False);

  ExpectedArity := SUBOP_ARITY[Cmd.SubOp];
  if ExpectedArity = ARITY_UNKNOWN then
    Exit(True);

  if ExpectedArity = ARITY_VARIABLE then
  begin
    { Sub-op 15: args are <id> <count> then <count> items. }
    if Cmd.ArgCount < 2 then
      Exit(False);
    Exit(Cmd.Args[1] = Cmd.ArgCount - 2);
  end;

  Result := Cmd.ArgCount = ExpectedArity;
end;

function CommandCount(const Prog: TEventProgram): Integer;
var
  StepIndex: Integer;
begin
  Result := 0;
  for StepIndex := 0 to High(Prog) do
    Inc(Result, Length(Prog[StepIndex].Alternatives));
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
  AlternativeIndex, GuardIndex: Integer;
begin
  { Backwards, first match wins - so of several qualifying alternatives it is
    the LAST one in the file that runs. }
  for AlternativeIndex := High(Step.Alternatives) downto 0 do
  begin
    GuardIndex := Step.Alternatives[AlternativeIndex].Guard;
    if (GuardIndex >= 0) and (GuardIndex <= High(Progress))
       and (Progress[GuardIndex] <> 0) then
      Exit(AlternativeIndex);
  end;
  Result := -1;
end;

end.
