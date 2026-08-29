#!/usr/bin/env python3
"""Check every recorded table's LENGTH against the table that follows it.

    python tools/table_extents.py [--verbose]

WHY THIS EXISTS, AND WHY THE 181 EXISTING PINS DO NOT COVER IT

--selftest-entities pins 181 tables by reading the bytes out of akuji.exe and
comparing them against the Pascal array. That is a real check and it catches a
mistyped value instantly. It cannot catch a SHORT TABLE, and the reason is
structural rather than an oversight:

    Pin('type 7 sprites', T7_TABLE_ADDR, 8, @T7_SPRITES[0][0], 8);

The count is 8 because the array has 8 entries. If the array should have had 12,
the pin compares the first 8, finds them correct, and passes. The declared
length is both the thing being checked and the thing doing the checking.

Type 7 is where this came from, and the story is worth keeping intact because
the tool's first act was to correct its own author. --emudiff ran type 7 with
EF_VARIANT 2, the original answered 50 where ours answered 40, and reading the
image at index 8 gave (50, 51, 52, 53). The next address I had recorded was
T9's, 0x30 further on, which made a third row look obvious. So I added one.

It is type 8's table. TYPE8_SPRITES sits at 0x0046BCCC, exactly 0x20 past T7's,
and this tool flagged the twelve-int T7_SPRITES as an overrun within minutes of
being written. The 50 is type 8's first sprite, reached by the original running
off the end of type 7's - an unchecked index, like DIV-010, not a missing row.

Which is the whole argument for checking extents from outside: the values that
follow a table are evidence about the NEXT table, and the next address you
happen to have written down is not necessarily the next one that exists.

WHAT THIS DOES INSTEAD

A table's end is pinned by what comes AFTER it. Sort every recorded table
address; the next address along is an upper bound on the one before it. Then:

    declared bytes >  gap    the table CANNOT be that long - it would run into
                             the next table. This is an error.
    declared bytes <  gap    it might be short, or there might be something
                             else in between. Reported for review.
    declared bytes == gap    flush, and the strongest state: the table's length
                             is corroborated from outside itself.

The == case is the point. It is the same argument that makes T6_ROWS credible -
0x0046BCAC minus 0x0046BC8C is 0x20, two rows of four - and, applied to the
right neighbour, the argument that showed T7_ROWS was right all along.

WHAT IT CANNOT DO. It only knows about tables that HAVE a recorded address, so
a table between two known ones is invisible and shows up as its predecessor
looking short. That is why a shortfall is reported rather than failed on: the
gap is an upper bound, not a length.
"""

import argparse
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = ['EntityHandlers.pas', 'Entities.pas', 'Player.pas', 'Stages.pas',
           'Directions.pas', 'EventCommands.pas', 'Title.pas', 'Ending.pas',
           'Opening.pas', 'PlayerState.pas', 'Dialogue.pas']

ADDR_RE = re.compile(r'^\s*([A-Z][A-Z0-9_]*?(?:_ADDR|_TABLE_ADDR))\s*=\s*\$([0-9A-Fa-f]{6,8})\s*;',
                     re.M)
ARR_RE = re.compile(
    r'^\s*([A-Z][A-Z0-9_]*)\s*:\s*array\[([^\]]+)\]\s+of\s+(\w+)\s*=\s*\((.*?)\);',
    re.M | re.S)


def parse_arrays(text):
    """name -> element count, for constant arrays of integers."""
    out = {}
    for m in ARR_RE.finditer(text):
        name, dims, typ, body = m.groups()
        if typ.lower() not in ('integer', 'cardinal', 'longint', 'byte',
                               'shortint', 'word', 'smallint'):
            continue
        # Count leaf elements: strip nested parens and count commas.
        flat = body.replace('(', ' ').replace(')', ' ')
        flat = re.sub(r'\{[^}]*\}', ' ', flat)
        items = [x for x in flat.split(',') if x.strip()]
        out[name] = (len(items), typ.lower())
    return out


def elem_size(typ):
    return {'byte': 1, 'shortint': 1, 'word': 2, 'smallint': 2}.get(typ, 4)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--verbose', action='store_true',
                    help='list every table, not only the ones worth looking at')
    args = ap.parse_args()

    addrs = {}       # NAME_ADDR -> va
    arrays = {}
    for fn in SOURCES:
        p = os.path.join(REPO, 'src', fn)
        if not os.path.exists(p):
            continue
        text = open(p, encoding='utf-8').read()
        for m in ADDR_RE.finditer(text):
            addrs[m.group(1)] = int(m.group(2), 16)
        arrays.update(parse_arrays(text))

    # Pair an address constant with ITS array, and only its array.
    #
    # THE LOOSE VERSION OF THIS WAS WRONG AND LOUDLY SO. Matching any array
    # whose name started with the address's stem meant T64_TABLE_ADDR (stem
    # 'T64') claimed T64_WAIT, which lives eight bytes further on behind its own
    # T64_WAIT_ADDR - so the tool reported three overruns that were entirely its
    # own doing. A checker whose false positives look exactly like its true ones
    # is worse than no checker, because the first three findings teach you to
    # ignore it.
    #
    # So: exact stem match, or the stem plus one of the conventional suffixes,
    # and if more than one array still matches, pair NOTHING and say so.
    SUFFIXES = ('_SPRITES', '_TABLE', '_VALUES', '_FRAMES')
    paired, ambiguous = [], []
    for aname, va in addrs.items():
        stem = aname[:-len('_TABLE_ADDR')] if aname.endswith('_TABLE_ADDR')             else aname[:-len('_ADDR')]
        cands = [ (arr, n, typ) for arr, (n, typ) in arrays.items()
                  if arr == stem or any(arr == stem + sfx for sfx in SUFFIXES) ]
        if len(cands) == 1:
            paired.append((va, aname, cands[0][0], cands[0][1], cands[0][2]))
        elif len(cands) > 1:
            ambiguous.append((aname, [c[0] for c in cands]))

    paired.sort()
    print('%d tables with both an address and an array\n' % len(paired))

    errors, shorts, flush = [], [], 0
    for i, (va, aname, arr, n, typ) in enumerate(paired):
        declared = n * elem_size(typ)
        if i + 1 < len(paired):
            gap = paired[i + 1][0] - va
        else:
            gap = None
        if gap is None or gap <= 0:
            continue
        if declared > gap:
            errors.append((va, aname, arr, n, declared, gap))
        elif declared == gap:
            flush += 1
            if args.verbose:
                print('  flush   0x%08X %-26s %d bytes' % (va, arr, declared))
        else:
            shorts.append((va, aname, arr, n, declared, gap))

    print('  %d flush against the next table - length corroborated from '
          'outside' % flush)
    print('  %d shorter than the gap - reviewable, not necessarily wrong'
          % len(shorts))
    print('  %d LONGER than the gap - these cannot be right' % len(errors))

    if errors:
        print('\nOVERRUNS - the declared array reaches into the next table:')
        for va, aname, arr, n, declared, gap in errors:
            print('  0x%08X %-26s %d entries = %d bytes, but only %d to the '
                  'next table' % (va, arr, n, declared, gap))

    if args.verbose and shorts:
        print('\nshort of the gap (often just an unrecorded table in between):')
        for va, aname, arr, n, declared, gap in shorts:
            print('  0x%08X %-26s %d bytes declared, %d to the next'
                  % (va, arr, declared, gap))

    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
