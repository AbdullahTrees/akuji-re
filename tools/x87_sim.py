#!/usr/bin/env python3
"""Exact simulation of an x87 FPU sequence, in rational arithmetic.

WHY THIS EXISTS

`Entity_UpdateAll` rebuilds four collision-box fields every frame as

    FILD  half-extent        ; an integer
    FILD  percent            ; an integer, 0..100
    FDIV  dword [100.0]      ; a Single
    FMULP                    ; half * (percent/100)
    CALL  @ROUND             ; FISTP, round half to even

Delphi runs the x87 with precision control set to **64-bit significands**.
FPC on x86-64 has no such type - `Extended` is an alias for `Double`, 8 bytes,
which this project checked rather than assumed - so NO floating-point expression
can reproduce the original on that target. It is not a theoretical difference:
over half-extents 0..1024 and percentages 0..100 the 80-bit and 64-bit answers
differ in 118 of 103,525 cases, and three of those are reachable from the
shipped entity type table with a sprite no wider than the screen.

So `EntityHandlers.ScaleByPercent` does the whole thing in integers. This script
is the reference that says the integer model is right, and it is deliberately
written a completely different way - `fractions.Fraction`, explicit rounding to a
p-bit significand - so that agreeing with it means something.

WHAT IT DOES

    python tools/x87_sim.py check      compare the integer model against the
                                       80-bit simulation over the whole domain
    python tools/x87_sim.py table      regenerate the X87_DEVIATIONS table that
                                       --selftest-entities asserts, as Pascal
    python tools/x87_sim.py compare    show how 80-bit, 64-bit and exact
                                       arithmetic differ, and where

GENERALISING IT

`fpu()` is not specific to this game. Any Borland/Delphi binary doing integer
arithmetic through the FPU has the same problem, and the same fix: simulate the
rounding exactly, then reproduce it in integers. The interesting part is that
EVERY disagreement with exact arithmetic turns out to be a TIE - the exact value
landing on x.5 - because away from a tie the FPU's ~1e-19 relative error cannot
reach the rounding boundary. That is what makes an integer model tractable:
handle the ties, and everything else is plain division.
"""

import sys
from fractions import Fraction as F


# --------------------------------------------------------------------------
# the simulation
# --------------------------------------------------------------------------

def round_to_significand(x: F, p: int) -> F:
    """Round exact rational x to a p-bit significand, round-half-to-even.

    p = 64 is the x87 at Delphi's default precision control; p = 53 is a
    double, which is what FPC gives on x86-64.
    """
    if x == 0:
        return F(0)
    neg = x < 0
    x = abs(x)
    e = 0
    while x * F(2) ** (-e) >= F(2) ** p:
        e += 1
    while x * F(2) ** (-e) < F(2) ** (p - 1):
        e -= 1
    scaled = x * F(2) ** (-e)
    fl = scaled.numerator // scaled.denominator
    rem = scaled - fl
    if rem > F(1, 2) or (rem == F(1, 2) and fl % 2 == 1):
        fl += 1
    r = F(fl) * F(2) ** e
    return -r if neg else r


def round_half_even(x: F) -> int:
    fl = x.numerator // x.denominator
    rem = x - fl
    if rem > F(1, 2):
        return fl + 1
    if rem == F(1, 2):
        return fl + 1 if fl % 2 == 1 else fl
    return fl


def fpu(half: int, pct: int, p: int = 64) -> int:
    """FILD half; FILD pct; FDIV Single(100.0); FMULP; FISTP.

    100.0 is exact as a Single, so the only roundings are the divide, the
    multiply, and the store.
    """
    d = round_to_significand(F(pct, 100), p)
    m = round_to_significand(F(half) * d, p)
    return round_half_even(m)


def exact(half: int, pct: int) -> int:
    """What the arithmetic says, with no floating point anywhere."""
    return round_half_even(F(half * pct, 100))


# --------------------------------------------------------------------------
# the integer model - this is what EntityHandlers.ScaleByPercent implements
# --------------------------------------------------------------------------

def scale_by_percent(half: int, pct: int) -> int:
    """Reproduce fpu(half, pct, 64) using only integers.

    Away from a tie the exact value is at least 1/100 from a .5 boundary while
    the FPU's relative error is about 1e-19, so plain division gives it. At a
    tie - half*pct = 50 (mod 100) - the hardware's own error decides, and the
    tail of this function works out which way.
    """
    sign = 1
    if half < 0:
        sign, half = -sign, -half
    if pct < 0:
        sign, pct = -sign, -pct
    if half == 0 or pct == 0:
        return 0

    n = half * pct
    q, r = divmod(n, 100)
    if r > 50:
        return sign * (q + 1)
    if r < 50:
        return sign * q

    # S normalises pct/100 to a 64-bit significand: 100 <= pct*2^k < 200.
    k = 0
    if pct < 100:
        while (pct << k) < 100:
            k += 1
    else:
        while (pct >> -k) >= 200:
            k -= 1
    s = 63 + k

    # T = D*100 - pct*2^S, the divide's rounding error scaled up; |T| <= 50.
    # It follows from pct*2^S mod 200 alone, which is why no 128-bit product is
    # needed anywhere. The mod 200 rather than 100 carries the parity that a
    # tie-inside-the-tie needs.
    r200 = (pct * pow(2, s, 200)) % 200
    g = r200 % 100
    if g < 50:
        t = -g
    elif g > 50:
        t = 100 - g
    else:
        t = 50 if r200 >= 100 else -50

    if t != 0:
        # Compare |half*T| / (100 * 2^S) against half an ulp of V = q + 1/2.
        v2 = 2 * q + 1
        ev = -1
        while (1 << (ev + 2)) <= v2:
            ev += 1
        x = s + ev - 64
        lhs = abs(half * t)
        rhs = 100 << x if x >= 0 else 100
        if x < 0:
            lhs <<= -x
        if lhs > rhs:
            return sign * (q + 1 if t > 0 else q)

    # The second rounding pulled the product back onto the tie exactly, so the
    # store rounds half to even.
    return sign * (q if q % 2 == 0 else q + 1)


# --------------------------------------------------------------------------

HALVES = range(0, 1025)
PCTS = range(0, 101)

# every percentage the shipped entity type table uses in columns 11..14
SHIPPED = [0, 5, 10, 20, 30, 33, 40, 50, 60, 70, 75, 80]


def cmd_check():
    bad = []
    for h in HALVES:
        for c in PCTS:
            if scale_by_percent(h, c) != fpu(h, c, 64):
                bad.append((h, c, scale_by_percent(h, c), fpu(h, c, 64)))
    n = len(HALVES) * len(PCTS)
    print('integer model vs 80-bit simulation over %d cases: %d disagree'
          % (n, len(bad)))
    for r in bad[:20]:
        print('   half=%d pct=%d  model=%d  x87=%d' % r)
    return 1 if bad else 0


def cmd_table():
    rows = [(h, c, fpu(h, c, 64))
            for h in HALVES for c in PCTS if fpu(h, c, 64) != exact(h, c)]
    print('  { %d places where the x87 sequence disagrees with exact' % len(rows))
    print('    round-half-even. Regenerate with: python tools/x87_sim.py table }')
    print('  X87_DEVIATIONS: array[0..%d, 0..2] of Integer = (' % (len(rows) - 1))
    for i in range(0, len(rows), 3):
        chunk = ', '.join('(%4d, %3d, %4d)' % r for r in rows[i:i + 3])
        end = ',' if i + 3 < len(rows) else ');'
        print('    ' + chunk + end)
    return 0


def cmd_compare():
    d_ext = d_dbl = d_both = 0
    reachable = []
    for h in HALVES:
        for c in PCTS:
            e, a, b = exact(h, c), fpu(h, c, 64), fpu(h, c, 53)
            d_ext += a != e
            d_dbl += b != e
            if a != b:
                d_both += 1
                if c in SHIPPED and h <= 160:
                    reachable.append((h, c, a, b))
    n = len(HALVES) * len(PCTS)
    print('cases                          : %d' % n)
    print('80-bit differs from exact      : %d' % d_ext)
    print('64-bit differs from exact      : %d' % d_dbl)
    print('80-bit differs from 64-bit     : %d' % d_both)
    print()
    print('of those, reachable from the shipped table with a sprite no wider')
    print('than the screen (percent in the shipped set, half-extent <= 160):')
    for h, c, a, b in reachable:
        print('   half=%-4d pct=%-3d  x87=%-4d double=%d' % (h, c, a, b))
    print()
    print('every disagreement with exact arithmetic is a TIE - half*pct = 50')
    print('(mod 100) - which is what makes the integer model tractable.')
    return 0


def main():
    cmds = {'check': cmd_check, 'table': cmd_table, 'compare': cmd_compare}
    what = sys.argv[1] if len(sys.argv) > 1 else 'check'
    if what not in cmds:
        print(__doc__)
        return 2
    return cmds[what]()


if __name__ == '__main__':
    sys.exit(main())
