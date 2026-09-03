# The event mini-language: how it was decoded

Moved out of src/events/EventCommands.pas on 2026-09-01. The unit now carries
the findings; this is the working-out behind them, kept verbatim.


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
