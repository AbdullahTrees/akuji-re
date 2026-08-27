{ EventCommands - the mini-language inside an event record's two string fields.

  EventScripts.pas loads ev%.03d.dat and gets seven CSV fields per record. Two
  of them are strings that are not values at all - they are programs. This unit
  parses them.

  ## Status of this decode

  The separator hierarchy is now TIER-1: it was inferred from the data first,
  then confirmed in the code.

      Event_Begin @ 0x00454EF4      StringReplace(ParamB, '/', ',') then
                                    CommaText   ->  '/' splits STEPS
      EventScript_AdvanceStep
        @ 0x0045509C                StringReplace(step, '.', ',') then
                                    CommaText   ->  '.' splits ALTERNATIVES

  Both separators were read straight out of the binary as single-character
  AnsiString literals with refcount -1, at 0x00455098 and 0x0045508C for the
  first pair and 0x0045520C and 0x00455200 for the second. This is the program
  itself saying what its separators are, not an inference from the data.

  The sub-opcodes are decoded too, from the interpreter itself:
  EventScript_Execute @ 0x00455210, the state-140 handler. See the table below.

  ## The interpreter reads FIXED POSITIONS, not dash-separated fields

  This unit splits on '-'. The original does not - it pulls fixed character
  ranges out of the string with Copy:

      Copy(alt, 6, 2)     the sub-opcode
      Copy(alt, 9, 4)     first argument      (widths vary by sub-opcode)
      Copy(alt, 14, 4)    second
      Copy(alt, 19, 4)    third
      Copy(alt, 24, 4)    fourth
      Copy(alt, 29, 4)    fifth

  which is why every number in the data is zero-padded to a fixed width: the
  padding is load-bearing, not cosmetic. It also explains '0030-M-0-0128--4'
  cleanly, since a fixed-position read picks up the '-4' without needing to know
  that '-' is overloaded.

  The two strategies were compared over every alternative in the shipped data
  and agree on all 505 fixed-arity ones. Splitting is kept here because it is
  more legible and it rejects malformed input instead of silently reading
  whatever sits at an offset - but the positions above are the ground truth, and
  --selftest-script checks the two against each other.

  ## Sub-opcodes, from EventScript_Execute

      op  args  what it does
      --  ----  ---------------------------------------------------------------
       0   5    load stage: Settings[0] := a1; player and camera tiles from
                a2..a5, scaled by the layer's tile size; GameState := 30
       1   4    (never used in the shipped data) enter stage, spawn the player
                at a1,a2 and GameState := 60
       3   1    DIALOGUE - show line a1 of the stage's tk file
       4   1    Progress[a1] := 1
       5   1    Progress[a1] := 0
       6   1    (unused) compare a1 (8 chars) against PlayerState+0x11C8
       7   0    disable this event - Opcode := -1 and its x,y := -0x20
       8   0    destroy this event's entity
       9   1    play sound effect a1 through DDSD1
      10   0    calls 0x00456698 when the flag at 0x0046CD00 is clear
      11   1    (unused) PlayerState+0x11C8 += a1 (8 chars)
      12   3    play music: a1 is a MIDI index, then two 1-char flags at
                positions 13 and 15 comparing against '1' and '0'
      13   0    SAVE - writes PlayerState over data\save.dat, 0x11E4 bytes
      14   3    (unused) set a map tile
      15   var  test a list of flags, then set one - see below
      16   1    sets +0x20 on this event's entity
      17   1    WAIT - a1 (6 chars) frames, then advance
      80   0    plays sound 0x10 and MIDI 11 ('soulget'), destroys the entity,
                reloads stage 0 and goes to GameState 150
      99   0    do nothing; just advance to the next step

  Every one of those argument counts matches the arity this unit had already
  inferred from the data, which is the cross-check that the field split is
  right.

  ## Sub-op 15 in detail

      <guard>-15-<flag to set>-<count>-<item><item>...

  Count is 2 chars at position 14; each item is 6 chars starting at position 17,
  being a 1-char expected value then a 4-char flag index. The expected value is
  compared against '1' (0x00456000) and '0' (0x0045600C), so 14000 reads as
  "flag 4000 must be 1" and 04000 as "flag 4000 must be 0". If every item
  matches, Progress[a1] := 1.

  That is why both 1nnnn and 0nnnn forms appear in the data.

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

  ## ParamA is READ now, not inferred

  All of the above was worked out from the data before the code that consumes
  it was found. Events_SpawnNearCamera @ 0x00454790 is that code, and it agrees
  with every part of it.

  The six letters are one-character AnsiString literals sitting in a row at
  0x00454EB4..0x00454EF0, tested in this order, each with the usual Delphi
  refcount of -1 and length 1:

      /   A   M   R   J   *

  Exactly the six the data showed, from a completely independent direction.

  Like the interpreter in ParamB, this one reads FIXED POSITIONS rather than
  splitting on '-'. The type is Copy(ParamA, 1, 4), and then, per letter:

      letter  arguments                        what each becomes
      ------  -------------------------------  ---------------------------
      *       none                             -
      A       (8,4)                            entity int 6
      /       (8,4) (13,3)                     IF Progress[a1]=1 THEN
                                               EF_STATE := a2
      M       (8,1) (10,4) (15,2)              EF_STATE, EF_HP,
                                               int 0x22 := a3 shl 3
      R       (8,2) (11,3)                     int 0x22 := a1, EF_HP := a2
      J       (8,4) (13,4)                     nudges the spawn position by
                                               a1, a2 PIXELS

  Every argument in all 692 records sits at exactly the position its letter's
  entry above copies from - checked by --selftest-script. The positions differ
  per letter (8/13, 8, 8/10/15, 8/11, 8/13), so this is not a coincidence that
  a wrong split could survive.

  A seventh form exists in the code for the case where the letter matches none
  of the six: seven 4-character fields at positions 6, 11, 16, 21, 26, 31 and
  36, filling int 6, EF_EXTENT_X, EF_EXTENT_Y and ints 0x3A..0x3D. No shipped
  record takes it.

  ONE CAUTION. int 0x22 is EF_FACING for the player and for effects the code
  spawns, where it is a heading 0..63. The values M and R put there are -4..4
  and -32..32 - signed and far too small to be headings - so 0x22 is another
  slot with more than one role, like EF_HP. Do not assume a placed enemy's
  0x22 is an angle.

  ## The leading number is a GUARD, not a target

  Each alternative begins with four digits. That number indexes the player's
  progress flags, and EventScript_AdvanceStep uses it to choose which
  alternative runs:

      for i := Count - 1 downto 0 do
        if Progress[StrToInt(Copy(item[i], 1, 4))] = 1 then
          begin  step := item[i];  break  end
        else
          step := ''

  So alternatives are scanned BACKWARDS and the last one whose flag is set wins.
  Exactly one runs, or none at all. That is why they are written general-first:
  flag 0 is set in the shipped save and no event ever writes it, so an
  alternative guarded on 0000 always matches and acts as the default - placed
  first precisely because the backwards scan reaches it last.

  23 of the 24 multi-alternative steps follow that convention. The one that does
  not is 0008-80.0000-12-007-1-1, where the order is reversed: the 0000 branch
  is tested first, always matches, and 0008-80 can never run. That looks like an
  authoring slip in the original data rather than a misreading here, and it is
  reproduced rather than corrected.

  All 23 distinct guard values fall inside the 4501-byte progress block.

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

      step / step / ...          '/' separates steps, which run in order
      alt . alt . ...            '.' separates ALTERNATIVES; exactly one runs
      <guard>-<subop>[-<arg>...] '-' separates fields within an alternative

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
  csv2 (BlockedBy) equals csv6 (ParamB) as a number in all 154 cases, and
  Entity_Destroy @ 0x00461400 parses ParamB's first four characters to get the
  progress-flag index. Two independently-loaded fields agreeing 154/154 means
  the scatter in EventScripts.pas put both in the right place. }

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
  else
    { 7, 8, 10, 13, 80, 99 take no arguments; 15 is variable and is checked by
      its own rule rather than by position. }
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
