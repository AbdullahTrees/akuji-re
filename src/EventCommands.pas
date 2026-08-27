{ EventCommands - the mini-language inside an event record's two string fields.

  EventScripts.pas loads ev%.03d.dat and gets seven CSV fields per record. Two
  of them are strings that are not values at all - they are programs. This unit
  parses them.

  ## Status of this decode

  IMPORTANT: unlike the record layout, which was read out of Load_Event_Scripts
  @ 0x00465B50, the GRAMMAR here was recovered from the shipped data, not from
  the disassembly. The interpreter has not been found yet. See CLAUDE.md 14 for
  what that means: this is tier-2 evidence (self-validating structure) and tier-3
  (cross-corroboration), not tier-1.

  So the SHAPE below is solid - it is checked against all 692 records and the
  invariants hold with zero exceptions - but the MEANING of most sub-opcodes is
  deliberately absent. A sub-opcode gets a name here only when something outside
  this file agrees with it. Everything else stays a number.

  ## ParamA (csv 5) - what the event places

      <type>-<kind>[-<arg>...]

      0014-*              379x  no arguments
      0024-A-0004         245x  one argument
      0015-/-1036-002      13x  two arguments
      0021-M-0-0160-04     38x  three arguments
      0066-R-01-008        15x  two arguments
      0080-J-0008-0010      2x  two arguments

  <type> is four digits and lands in 14..80 across all 692 records, never
  outside. ENTITY_TYPES has exactly 81 entries (0..80), so the upper bound is
  flush against the table - that is the cross-corroboration, and it is why
  TypeId is the name. Types 0..13 never appear, which fits them being spawned
  by code (player, projectiles) rather than placed by a stage.

  <kind> is a single letter, and it is an ARITY MARKER - exactly the role the
  sub-opcode plays in ParamB. The count is fixed per letter with no exceptions:

      *  0 args  379x      /  2 args   13x      R  2 args   15x
      A  1 arg   245x      J  2 args    2x      M  3 args   38x

  The letter is a property of the PLACEMENT, not of the type: six types (14,
  38, 40, 43, 62, 65) appear both ways. Every one of those mixes only '*' with
  'A' - the same entity placed with or without a parameter - and no type mixes
  anything else. So '*' is the plain form and the letters select a parameter
  shape.

  M and J and R carry SIGNED arguments and are the reason ParseFields exists:
  in 0030-M-0-0128--4 the last field is -4, so '-' is both the separator and
  the minus sign.

  ## ParamB (csv 6) - three shapes, chosen by the opcode

  ParamB is NOT always a program. Its shape is decided entirely by csv 0, with
  no exceptions anywhere in the shipped data:

      opcode 0,1,4,6,7   a program           307
      opcode 5           a bare id           154
      opcode 9           a bare id, or '*'   231  (127 + 104)

  That the partition is total is itself evidence the split is right: a wrong
  reading would leave stragglers. And opcode 5's bare id is corroborated from
  outside the data - Entity_Destroy @ 0x00461400 takes ParamB's first four
  characters as a progress-flag index, which only makes sense if ParamB is a
  plain number there. Opcode 5 also stores that same number in csv 2, and the
  two agree in all 154 cases.

  A program is:

      step / step / ...           '/' separates steps
      cmd . cmd . ...             '.' separates commands within a step
      <target>-<subop>[-<arg>...] '-' separates fields within a command

  Every sub-opcode has a fixed argument count except 15, which is
  self-describing. The arities below are observed over all 692 records:

      subop  uses  args   subop  uses  args
        00    136    5      12     16    3
        03    149    1      13     43    0
        04     57    1      15     13    variable
        05      8    1      16     18    1
        07      8    0      17      8    1
        08      7    0      80      3    0
        09     20    1      99     22    0
        10     10    0

  Fixed arity across 500+ commands with no exceptions is what makes this a
  decode rather than a guess - a mis-split grammar would not produce it.

  ## The two sub-opcodes that have outside support

  03 (SUBOP_DIALOGUE): its single argument is an index into the stage's
     tk%.03d.dat, the file Load_Event_Scripts reads alongside the ev file. All
     149 references across all 66 stages land inside their own stage's line
     count, none out of range. A wrong reading would overrun somewhere.

  15 (SUBOP_LIST): arg[1] is a count and exactly that many items follow. True
     for all 13 uses, with counts 2..5. The field is redundant with the item
     count, so it can only be a length.

  Opcode 5 gives a third, separate cross-check that the record layout is right:
  csv2 (Field20) equals csv6 (ParamB) as a number in all 154 cases, and
  Entity_Destroy @ 0x00461400 parses ParamB's first four characters to get the
  progress-flag index. Two independently-loaded fields agreeing 154/154 means
  the scatter in EventScripts.pas put both in the right place. }

unit EventCommands;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils, Classes;

const
  { Named only because something outside this file corroborates them. }
  SUBOP_DIALOGUE = 3;    { arg[0] indexes the stage's tk file }
  SUBOP_LIST     = 15;   { arg[1] is a count; that many items follow }

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

  { One command: <target>-<subop>[-args]. Raw is kept so that a command whose
    meaning is still unknown can be round-tripped or logged verbatim. }
  TEventCommand = record
    Target:   Integer;
    SubOp:    Integer;
    ArgCount: Integer;
    Args:     array[0..MAX_CMD_ARGS - 1] of Integer;
    Raw:      string;
  end;

  TEventCommandArray = array of TEventCommand;

  { One step of a ParamB program - the commands between two '/'. }
  TEventStep = record
    Commands: TEventCommandArray;
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

{ Number of commands across every step, for reporting. }
function CommandCount(const Prog: TEventProgram): Integer;

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
  Result.Target := -1;
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
    Result.Target := StrToIntDef(F[0], -1);
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

      SetLength(Result[S].Commands, Cmds.Count);
      for C := 0 to Cmds.Count - 1 do
        Result[S].Commands[C] := ParseCommand(Cmds[C]);
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
    Inc(Result, Length(Prog[S].Commands));
end;

end.
