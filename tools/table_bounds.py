#!/usr/bin/env python3
"""Find where a Delphi const array ENDS, by looking at its neighbours.

WHY THIS EXISTS

Recovering a table from a binary, it is easy to get the values right and the
LENGTH wrong, and a self-test that reads N values out of the exe and compares
them cannot tell you - especially if it computes N from the constant it is
verifying. That happened here: a sprite table was recorded as 16 rows of 4 and
is 2, and the check passed either way because shrinking the constant just made
it read fewer values.

The extent needs a fact from OUTSIDE the table. Delphi lays typed constants out
consecutively in declaration order and reaches each through its own pointer
global, so:

    a table ends where the next table begins

which this script computes by collecting every pointer-shaped dword that points
into the region and sorting them.

TWO CORROBORATIONS WORTH CHECKING BY HAND AFTERWARDS

  * count the READERS of the pointer global. One reader means no other type
    could need more rows. `--readers` does this.
  * check the table is flush with its USE. If the handler indexes it by a field
    whose observed range in the shipped data is 0..N-1 and the table has exactly
    N entries, the two agree from both directions. That is much stronger than
    either alone, and it is what settled all four tables at 0x0046BDA0.

BEWARE THE NEAR MISS. Two tables adjacent in memory, both plausible, is exactly
how the 16-versus-2 error happened: the evidence for 16 was real but belonged to
the NEXT table along, which genuinely is indexed 0..15.

USAGE

    python tools/table_bounds.py <exe> --region 0x468000 0x46D400
    python tools/table_bounds.py <exe> --at 0x46BDA0
    python tools/table_bounds.py <exe> --ptr 0x46CBA0 --readers
"""

import argparse
import struct
import sys

# PE section biases for this binary: VA = file offset + bias.
DATA_VA_BIAS = 0x401A00
CODE_VA_BIAS = 0x400C00

# Where Delphi put the pointer globals in this exe. Generous on purpose: a
# stray dword that happens to look like a pointer can only ever make a table
# look SHORTER, never longer, so it cannot hide a too-long claim.
#
# The default REGION below is the same span --selftest-entities sweeps. It used
# to stop at 0x0046C400 on the assumption that the pointer globals began there
# and the bodies ended - and they interleave instead. A table body above that
# line then had no visible successor and the tool said "not the start of any
# table", which reads like a wrong address rather than a window that is too
# small. Type 57's hatch table at 0x0046C460 is one of those.
PTRS_LO, PTRS_HI = 0x0046C400, 0x0046D400


def load(path):
    with open(path, 'rb') as fh:
        return fh.read()


def dwords(data, lo, hi, bias):
    """(va, value) for every dword in [lo, hi)."""
    for va in range(lo, hi, 4):
        off = va - bias
        if 0 <= off <= len(data) - 4:
            yield va, struct.unpack('<I', data[off:off + 4])[0]


def table_starts(data, body_lo, body_hi):
    """Distinct addresses in the region that some pointer global points at."""
    found = {}
    for va, val in dwords(data, PTRS_LO, PTRS_HI, DATA_VA_BIAS):
        if body_lo <= val < body_hi:
            found.setdefault(val, []).append(va)
    return found


def readers(data, target, code_hi=0x468000):
    """Every place in the code section that mentions this address literally."""
    pat = struct.pack('<I', target)
    out, start = [], 0
    while True:
        i = data.find(pat, start)
        if i < 0:
            break
        va = i + CODE_VA_BIAS
        if va < code_hi:
            out.append(va)
        start = i + 1
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('exe')
    ap.add_argument('--region', nargs=2, metavar=('LO', 'HI'),
                    default=['0x468000', '0x46D400'],
                    help='the span of table bodies to partition')
    ap.add_argument('--at', metavar='VA', help='report the extent of one table')
    ap.add_argument('--ptr', metavar='VA', help='resolve a pointer global first')
    ap.add_argument('--readers', action='store_true',
                    help='also count code references to the pointer')
    ap.add_argument('--ints', type=int, default=0,
                    help='print this many ints of each table body')
    args = ap.parse_args()

    data = load(args.exe)
    lo, hi = int(args.region[0], 0), int(args.region[1], 0)
    starts = table_starts(data, lo, hi)
    ordered = sorted(starts)

    def body(va, n):
        off = va - DATA_VA_BIAS
        return list(struct.unpack('<%di' % n, data[off:off + 4 * n]))

    if args.ptr:
        p = int(args.ptr, 0)
        off = p - DATA_VA_BIAS
        base = struct.unpack('<I', data[off:off + 4])[0]
        print('[0x%06X] -> 0x%06X' % (p, base))
        if args.readers:
            r = readers(data, p)
            print('  readers of the pointer: %s' % ', '.join('0x%06X' % x for x in r))
            if len(r) == 1:
                print('  exactly one reader, so no other caller can need more rows')
        args.at = hex(base)

    if args.at:
        base = int(args.at, 0)
        if base not in starts:
            print('0x%06X is not the start of any table in the region.' % base)
            print('It may be an address INSIDE one - which is worth knowing, '
                  'because that is')
            print('what a wrong extent looks like.')
            nearest = [s for s in ordered if s <= base]
            if nearest:
                print('  nearest start at or below: 0x%06X' % nearest[-1])
            return 1
        after = [s for s in ordered if s > base]
        end = after[0] if after else hi
        n = (end - base) // 4
        print('table at 0x%06X' % base)
        print('  pointed at by : %s'
              % ', '.join('0x%06X' % v for v in starts[base]))
        print('  next start    : 0x%06X' % end)
        print('  extent        : %d bytes = %d ints' % (end - base, n))
        if n <= 64:
            print('  values        : %s' % body(base, n))
        for p in starts[base]:
            r = readers(data, p)
            print('  readers of 0x%06X: %s'
                  % (p, ', '.join('0x%06X' % x for x in r) or 'none'))
        return 0

    print('%d distinct table starts in 0x%06X..0x%06X' % (len(ordered), lo, hi))
    print()
    print('  start     ints  pointer(s)')
    for i, base in enumerate(ordered):
        end = ordered[i + 1] if i + 1 < len(ordered) else hi
        n = (end - base) // 4
        ptrs = ', '.join('0x%06X' % v for v in starts[base])
        line = '  0x%06X  %4d  %s' % (base, n, ptrs)
        if args.ints and n:
            line += '  %s' % body(base, min(n, args.ints))
        print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main())
