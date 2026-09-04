{ Compatibility stubs for the unit initialization table. The counters are
  write-only and have no gameplay effect. }

unit UnitInit;

{$MODE DELPHI}{$H+}

interface

const
  { Compatibility entries in initialization order. }
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
  { One counter per compatibility entry. They are write-only and intentionally
    grouped because no entry has distinct behavior. }
  UnitInitCount: array[0..UNIT_INIT_COUNT - 1] of Integer;

procedure UnitInitialize(Index: Integer);

procedure UnitFinalize(Index: Integer);

{ Initialize in table order and finalize in reverse order. }
procedure UnitInitializeAll;
procedure UnitFinalizeAll;

implementation

procedure UnitInitialize(Index: Integer);
begin
  if (Index < 0) or (Index >= UNIT_INIT_COUNT) then
    Exit;
  Inc(UnitInitCount[Index]);
end;

procedure UnitFinalize(Index: Integer);
begin
  if (Index < 0) or (Index >= UNIT_INIT_COUNT) then
    Exit;
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
