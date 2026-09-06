#!/usr/bin/env python3
"""Which game functions have EXECUTABLE Pascal, and which only have prose.

WHY THIS EXISTS

`coverage.py` counts an address as covered if it is *mentioned* anywhere, which
deliberately means "someone looked at this". That is a useful number and it is
not the number you want before saying a function is done, because it cannot
tell a routine that runs from a routine that was only written up. This project
accumulated roughly a dozen functions that had been read carefully, described
in detail, and never turned into code - the findings sat where nothing could
execute or test them.

WHERE THE MAPPING LIVES

`notes/implemented_map.tsv`: one row per game-layer function, giving the
address, its Ghidra name, and the routine in `src/` that carries the
behaviour. This tool checks that every target really has a body.

It used to work the other way round - the address had to appear in the comment
block immediately above the declaration, and the mapping was recovered by
scanning `src/`. That was wrong twice over. It put decompilation bookkeeping in
source comments, which are for explaining how the game works, not how it was
recovered; and because the convention was invisible to the compiler, a
reformatting pass took the count from 149 to 14 with everything still building
and every self-test still green. A ledger fails loudly instead: a row whose
target does not exist is an error naming the row.

WHAT COUNTS AS A BODY

An implementation at column 0 in the unit named by the row:

    procedure TEntityWorld.SolidCollideX(...);   <- yes
      function SolidCollideX(...): Boolean;      <- no, an interface declaration

Interface and class declarations are indented, so anchoring at column 0 tells
them apart. An abstract method is not an implementation, and neither is an
override inside a test double; both are exactly the shape of the thing this is
meant to catch, so both are rejected.

USAGE

    python tools/implemented.py               summary plus anything missing
    python tools/implemented.py --all         every row, classified
    python tools/implemented.py --missing     just the backlog, for planning
"""

import argparse
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(REPO, 'notes', 'implemented_map.tsv')

# A body is a definition at column 0. Interface and class-member declarations
# are indented, which is what keeps them out.
BODY = r'(?m)^(?:procedure|function|constructor|destructor)\s+{}\s*[(;:]'

# The .lpr's main block is not a declaration at all, so it gets its own shape.
PROGRAM_BLOCK = re.compile(r'(?m)^begin\s*$')

TEST_DOUBLE = re.compile(r'\b(TFlatWorld|TCountingWorld|TStubSprites|'
                         r'TStartStub|TStageHostStub|TRecordingWorld)\b')


class Row:
    def __init__(self, addr, name, unit, routine):
        self.addr = addr
        self.name = name
        self.unit = unit
        self.routine = routine
        self.status = 'missing'
        self.detail = ''

    @property
    def target(self):
        return '%s:%s' % (self.unit, self.routine)


def load_ledger(path):
    rows = []
    for lineno, line in enumerate(open(path, encoding='utf-8'), 1):
        line = line.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) != 3:
            sys.exit('%s:%d: want 3 tab-separated columns, got %d'
                     % (path, lineno, len(parts)))
        addr, name, target = (p.strip() for p in parts)
        unit, _, routine = target.partition(':')
        if not routine:
            sys.exit('%s:%d: target %r has no routine after the colon'
                     % (path, lineno, target))
        rows.append(Row(int(addr, 16), name, unit, routine))
    return rows


def classify(rows):
    """Fill in each row's status by looking for its body in src/."""
    cache = {}
    for row in rows:
        path = os.path.join(REPO, 'src', row.unit.replace('/', os.sep))
        if row.unit not in cache:
            if not os.path.exists(path):
                cache[row.unit] = None
            else:
                cache[row.unit] = open(path, encoding='utf-8',
                                       errors='replace').read()
        text = cache[row.unit]

        if text is None:
            row.detail = 'no such unit: src/%s' % row.unit
            continue

        if row.routine == 'program block':
            if PROGRAM_BLOCK.search(text):
                row.status = 'implemented'
            else:
                row.detail = 'no main block in %s' % row.unit
            continue

        match = re.search(BODY.format(re.escape(row.routine)), text)
        if not match:
            row.detail = 'no body for %s in %s' % (row.routine, row.unit)
            continue

        # A method of a test double is not the game's implementation.
        if TEST_DOUBLE.search(row.routine):
            row.detail = '%s is a test double' % row.routine
            continue

        row.status = 'implemented'
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--all', action='store_true',
                    help='list every row and how it was classified')
    ap.add_argument('--missing', action='store_true',
                    help='list only the rows with no body')
    args = ap.parse_args()

    rows = classify(load_ledger(LEDGER))
    done = [r for r in rows if r.status == 'implemented']
    missing = [r for r in rows if r.status != 'implemented']

    if args.all:
        for r in sorted(rows, key=lambda r: r.addr):
            mark = ' ' if r.status == 'implemented' else '!'
            print('%s 0x%06X  %-34s %s' % (mark, r.addr, r.name, r.target))
        print()
    elif args.missing:
        for r in sorted(missing, key=lambda r: r.addr):
            print('  0x%06X  %-34s %s' % (r.addr, r.name, r.detail))
        if not missing:
            print('  nothing missing')
        print()
    elif missing:
        print('NOT IMPLEMENTED:')
        for r in sorted(missing, key=lambda r: r.addr):
            print('  0x%06X  %-34s %s' % (r.addr, r.name, r.detail))
        print()

    total = len(rows)
    pct = (100.0 * len(done) / total) if total else 0.0
    print('game-layer functions : %d' % total)
    print('implemented          : %d  (%.1f%%)' % (len(done), pct))
    print('missing              : %d' % len(missing))

    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
