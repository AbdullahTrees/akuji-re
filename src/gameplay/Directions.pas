{ The 64-step integer direction system. Velocity components come from a
  truncated fixed-point cosine table:

      DIR_COS[i] = trunc(32 * cos(i * 2*Pi / 64))

  The constants are stored explicitly to avoid platform-dependent rounding.
  Screen Y grows downward, so direction 16 points up:

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

  { Fixed-point cosine values for one full turn. }
  DIR_COS: array[0..DIR_COUNT - 1] of Integer = (
      32,   31,   31,   30,   29,   28,   26,   24,
      22,   20,   17,   15,   12,    9,    6,    3,
       0,   -3,   -6,   -9,  -12,  -15,  -17,  -20,
     -22,  -24,  -26,  -28,  -29,  -30,  -31,  -31,
     -32,  -31,  -31,  -30,  -29,  -28,  -26,  -24,
     -22,  -20,  -17,  -15,  -12,   -9,   -6,   -3,
       0,    3,    6,    9,   12,   15,   17,   20,
      22,   24,   26,   28,   29,   30,   31,   31);

{ Velocity components wrap directions into the valid range. }
function DirVelX(Dir: Integer): Integer;
function DirVelY(Dir: Integer): Integer;

{ Integer atan2 in 64ths, with no division or floating point. It walks the
  sixteen sub-steps of a quadrant and stops where the cross product changes
  sign. }
function AngleBetween(X1, Y1, X2, Y2: Integer): Integer;

{ Turn Facing one unit toward Target by the shorter direction.

  The asymmetric 33/32 thresholds give a stable turn direction when Facing and
  Target are exactly opposite. }
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
  { Y is the cosine table rotated by one quarter turn. }
  Result := DIR_COS[(Dir + DIR_QUARTER) and DIR_MASK];
end;

function AngleBetween(X1, Y1, X2, Y2: Integer): Integer;
var
  DeltaX, DeltaY, BaseDirection, DirectionStep, SubStep: Integer;
begin
  DeltaX := X2 - X1;
  DeltaY := Y2 - Y1;

  if DeltaX < 0 then
  begin
    BaseDirection := $20;
    DeltaX := -DeltaX;
    if DeltaY < 0 then
    begin
      DeltaY := -DeltaY;
      DirectionStep := -1;
    end
    else
      DirectionStep := 1;
  end
  else
  begin
    BaseDirection := 0;
    if DeltaY < 0 then
    begin
      DeltaY := -DeltaY;
      DirectionStep := 1;
    end
    else
      DirectionStep := -1;
  end;

  { Fourth quadrant counts down from a full turn rather than up from zero. }
  if (BaseDirection = 0) and (DirectionStep = -1) then
    BaseDirection := $40;

  SubStep := 0;
  while SubStep <> $10 do
  begin
    { (16 - i) * dy < (i + 1) * dx, written as a subtraction so it stays exact
      in integers. This is where dy/dx crosses the sub-step's slope. }
    if (($10 - SubStep) * DeltaY) - ((SubStep + 1) * DeltaX) < 0 then
      Break;
    Inc(BaseDirection, DirectionStep);
    Inc(SubStep);
  end;

  if BaseDirection > $3F then
    Dec(BaseDirection, $40);
  Result := BaseDirection;
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

  { Delta can move Facing only one step outside the valid range. }
  if Facing < 0 then
    Inc(Facing, DIR_COUNT);
  if Facing > DIR_COUNT - 1 then
    Dec(Facing, DIR_COUNT);
end;

end.
