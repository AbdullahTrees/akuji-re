{ The game's unit initialization and finalization sections.

  WHY THIS FILE EXISTS

  Eight addresses sat in the "untranslated game function" backlog for a long
  time looking like handlers nobody had read yet:

      0x00456B14  0x00459E7C  0x0045B3B4  0x0045BC8C
      0x0045ED50  0x0045F824  0x00460884  0x00461A0C

  They are not game logic. They are compiler-emitted unit INITIALIZATION
  stubs, and each one's entire body is a single increment.

  WHAT SAYS SO

  A zero-terminated table of pointer PAIRS sits immediately before `entry` at
  0x0046716C, running up to its terminator at 0x00467164. That is Delphi's
  unit initialization table: each entry is (finalization, initialization), and
  in every single entry the two differ by exactly 0x30 bytes.

  Fifteen of its entries point into the game's own address range:

      init        finit       counter
      0x00456B14  0x00456B44  0x00484FA0
      0x00458570  0x004585A0  0x00484FB8
      0x00459E7C  0x00459EAC  0x00484FBC
      0x0045A9D8  0x0045AA08  0x00484FC0
      0x0045B3B4  0x0045B3E4  0x00484FC4
      0x0045BC8C  0x0045BCBC  0x00484FC8
      0x0045C3F8  0x0045C428  0x00484FCC
      0x0045CE40  0x0045CE70  0x00484FD0
      0x0045ED50  0x0045ED80  0x00484FD4
      0x0045F824  0x0045F854  0x00484FD8
      0x00460884  0x004608B4  0x00484FDC
      0x00461A0C  0x00461A3C  0x00484FE0
      0x00464578  0x004645A8  0x00484FE4
      0x00464B1C  0x00464B4C  0x00484FE8
      0x00466E84  0x00466EB4  0x00484FF0

  and all fifteen have byte-for-byte the same shape:

      initialization      finalization
        push ebp            sub  [counter], 1
        mov  ebp, esp       ret
        xor  eax, eax
        push ebp          ( seven bytes, no frame at all )
        push @handler
        push fs:[eax]
        mov  fs:[eax], esp
        inc  [counter]      <- the whole body
        ...unwind...
        ret

  So each unit does `Inc(Counter)` when it starts and `Dec(Counter)` when it
  shuts down, guarded by an exception frame the compiler puts round every
  initialization section.

  THE COUNTERS ARE WRITE-ONLY

  This is the part worth stating plainly, because it is what makes these
  functions safe to reproduce as they are. Every reference to every one of the
  fifteen counters is one of those two instructions. `inc` and `sub` are
  read-modify-write, so a naive xref listing shows two "reads" per counter and
  looks like something consumes them - nothing does. No branch anywhere tests
  one, nothing copies one, and none of them is written to the save file.

  They therefore have NO OBSERVABLE BEHAVIOUR. Reproducing them changes
  nothing; leaving them out would also change nothing. They are here so that
  eight entries stop being mistaken for unread game logic, and so the next
  person to see 0x0045ED50 in a call graph does not spend an afternoon on it.

  --selftest-entities re-derives the whole table above straight out of
  akuji.exe, so if any of this is wrong the gate says so rather than this
  comment quietly aging. }

unit UnitInit;

{$MODE DELPHI}{$H+}

interface

const
  { The game-range entries of Delphi's unit initialization table. Ordered as
    the table orders them, which is the order the units initialize in. }
  UNIT_INIT_COUNT = 15;

  UNIT_INIT_TABLE_END = $00467164;   { the zero terminator }
  UNIT_INIT_STUB_GAP  = $30;         { finalization = initialization + this }

  UNIT_INIT_ADDR: array[0..UNIT_INIT_COUNT - 1] of LongWord =
    ($00456B14, $00458570, $00459E7C, $0045A9D8, $0045B3B4,
     $0045BC8C, $0045C3F8, $0045CE40, $0045ED50, $0045F824,
     $00460884, $00461A0C, $00464578, $00464B1C, $00466E84);

  UNIT_INIT_COUNTER: array[0..UNIT_INIT_COUNT - 1] of LongWord =
    ($00484FA0, $00484FB8, $00484FBC, $00484FC0, $00484FC4,
     $00484FC8, $00484FCC, $00484FD0, $00484FD4, $00484FD8,
     $00484FDC, $00484FE0, $00484FE4, $00484FE8, $00484FF0);

var
  { 0x00484FA0 .. 0x00484FF0. One per unit, incremented by that unit's
    initialization and decremented by its finalization, and read by nothing.
    Kept as an array rather than fifteen separate globals because nothing
    distinguishes them beyond their address. }
  UnitInitCount: array[0..UNIT_INIT_COUNT - 1] of Integer;

{ 0x00456B14, 0x00458570, 0x00459E7C, 0x0045A9D8, 0x0045B3B4, 0x0045BC8C,
  0x0045C3F8, 0x0045CE40, 0x0045ED50, 0x0045F824, 0x00460884, 0x00461A0C,
  0x00464578, 0x00464B1C, 0x00466E84. Every one of the fifteen unit
  initialization stubs, which differ only in which counter they touch. }
procedure UnitInitialize(Index: Integer);

{ 0x00456B44 and the fourteen others at initialization + 0x30. }
procedure UnitFinalize(Index: Integer);

{ What the original does at startup and shutdown: walk the table forwards to
  initialize and backwards to finalize. Delphi's own loop, not the game's. }
procedure UnitInitializeAll;
procedure UnitFinalizeAll;

implementation

procedure UnitInitialize(Index: Integer);
begin
  if (Index < 0) or (Index >= UNIT_INIT_COUNT) then
    Exit;
  { The exception frame the compiler wraps this in has nothing to catch: a
    plain Inc cannot raise. Reproduced as a bare Inc. }
  Inc(UnitInitCount[Index]);
end;

procedure UnitFinalize(Index: Integer);
begin
  if (Index < 0) or (Index >= UNIT_INIT_COUNT) then
    Exit;
  { And the finalization half really has no frame at all - seven bytes. }
  Dec(UnitInitCount[Index]);
end;

procedure UnitInitializeAll;
var
  I: Integer;
begin
  for I := 0 to UNIT_INIT_COUNT - 1 do
    UnitInitialize(I);
end;

procedure UnitFinalizeAll;
var
  I: Integer;
begin
  for I := UNIT_INIT_COUNT - 1 downto 0 do
    UnitFinalize(I);
end;

end.
