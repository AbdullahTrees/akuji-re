{ Directions - the game's 64-step angle system.

  Everything that moves on a heading uses this: a direction is an integer 0..63
  around the circle, and velocities come out of a lookup table rather than from
  floating point. There is no FPU code anywhere in the game's own layer.

  Recovered from three places:

    0x004513E0  angle between two points, as an integer, no division
    0x00461738  the homing/steering step (see TurnToward)
    0x00468B14  the velocity table, 64 ints
    0x00468C14  a second 64-int table, used for the Y component

  The two tables are adjacent - the first ends exactly where the second begins,
  and the eight ints after the second are pointers - so both are exactly 64
  entries. They are also not independent: table2[i] = table1[(i + 16) mod 64]
  for all 64 entries, which is the quarter-turn relationship between sine and
  cosine. So there is really one table, emitted twice.

  The table's address is confirmed from a second direction: the global at
  0x0046CEE4 holds 0x00468B14 in the file image, and Entity_SpawnDebris
  @ 0x00461874 indexes it with Random($40) to pick a heading for each particle.
  A 64-entry random index into this exact address is independent evidence both
  that DIR_COUNT is 64 and that the table starts where it was read from.

  Its closed form is exact for every entry:

      DIR_COS[i] = trunc(32 * cos(i * 2*Pi / 64))

  - truncated toward zero, not rounded. It is kept here verbatim rather than
  generated at startup, because the truncation is what the original shipped and
  a rounding difference of one unit would slowly desynchronise any movement
  that accumulates.

  Screen Y grows downward, so the Y table is negated sine and direction 16
  points UP:

      0 = +X (right)    16 = -Y (up)    32 = -X (left)    48 = +Y (down) }

unit Directions;

{$MODE DELPHI}{$H+}

interface

const
  DIR_COUNT   = 64;    { steps in a full turn }
  DIR_MASK    = 63;
  DIR_SCALE   = 32;    { the table's amplitude, and its value at direction 0 }
  DIR_QUARTER = 16;    { the sine/cosine offset }

  DIR_RIGHT = 0;
  DIR_UP    = 16;
  DIR_LEFT  = 32;
  DIR_DOWN  = 48;

  { Verbatim from 0x00468B14. }
  DIR_COS: array[0..DIR_COUNT - 1] of Integer = (
      32,   31,   31,   30,   29,   28,   26,   24,
      22,   20,   17,   15,   12,    9,    6,    3,
       0,   -3,   -6,   -9,  -12,  -15,  -17,  -20,
     -22,  -24,  -26,  -28,  -29,  -30,  -31,  -31,
     -32,  -31,  -31,  -30,  -29,  -28,  -26,  -24,
     -22,  -20,  -17,  -15,  -12,   -9,   -6,   -3,
       0,    3,    6,    9,   12,   15,   17,   20,
      22,   24,   26,   28,   29,   30,   31,   31);

{ Velocity components for a direction, at the table's own scale. Out-of-range
  directions wrap rather than fault; the original relies on its callers having
  wrapped already, but every one of them does. }
function DirVelX(Dir: Integer): Integer;
function DirVelY(Dir: Integer): Integer;

{ Angle_Between @ 0x004513E0. Integer atan2 in 64ths, with no division and no
  floating point: it walks the sixteen sub-steps of a quadrant and stops where
  the cross product changes sign. }
function AngleBetween(X1, Y1, X2, Y2: Integer): Integer;

{ One steering step, from 0x00461738: turn Facing one unit toward Target,
  taking the shorter way round.

  Note the asymmetry - the threshold is 33 when turning down and 32 when
  turning up. That is in the original and is reproduced rather than tidied: at
  a delta of exactly 32, which is dead opposite, the two branches pick
  different directions, so an entity facing exactly away from its target turns
  a consistent way instead of jittering. }
procedure TurnToward(var Facing: Integer; Target: Integer);

{ Wraps any integer into 0..63. }
function WrapDir(Dir: Integer): Integer;

implementation

function WrapDir(Dir: Integer): Integer;
begin
  Result := Dir and DIR_MASK;
end;

function DirVelX(Dir: Integer): Integer;
begin
  Result := DIR_COS[Dir and DIR_MASK];
end;

function DirVelY(Dir: Integer): Integer;
begin
  { The original reads a second table; it is this one rotated a quarter turn. }
  Result := DIR_COS[(Dir + DIR_QUARTER) and DIR_MASK];
end;

function AngleBetween(X1, Y1, X2, Y2: Integer): Integer;
var
  Dx, Dy, Base, Step, I: Integer;
begin
  Dx := X2 - X1;
  Dy := Y2 - Y1;

  if Dx < 0 then
  begin
    Base := $20;
    Dx := -Dx;
    if Dy < 0 then
    begin
      Dy := -Dy;
      Step := -1;
    end
    else
      Step := 1;
  end
  else
  begin
    Base := 0;
    if Dy < 0 then
    begin
      Dy := -Dy;
      Step := 1;
    end
    else
      Step := -1;
  end;

  { Fourth quadrant counts down from a full turn rather than up from zero. }
  if (Base = 0) and (Step = -1) then
    Base := $40;

  I := 0;
  while I <> $10 do
  begin
    { (16 - i) * dy < (i + 1) * dx, written as a subtraction so it stays exact
      in integers. This is where dy/dx crosses the sub-step's slope. }
    if (($10 - I) * Dy) - ((I + 1) * Dx) < 0 then
      Break;
    Inc(Base, Step);
    Inc(I);
  end;

  if Base > $3F then
    Dec(Base, $40);
  Result := Base;
end;

procedure TurnToward(var Facing: Integer; Target: Integer);
var
  Delta: Integer;
begin
  Delta := Target - Facing;
  if Delta < 0 then
  begin
    if Abs(Delta) < $21 then
      Dec(Facing)
    else
      Inc(Facing);
  end
  else if Delta > 0 then
  begin
    if Abs(Delta) < $20 then
      Inc(Facing)
    else
      Dec(Facing);
  end;

  { The original adds or subtracts a full turn once, rather than masking - the
    delta can never push Facing more than one step outside the range. }
  if Facing < 0 then
    Inc(Facing, DIR_COUNT);
  if Facing > DIR_COUNT - 1 then
    Dec(Facing, DIR_COUNT);
end;

end.
