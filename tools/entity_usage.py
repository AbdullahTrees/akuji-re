#!/usr/bin/env python3
"""What the shipped stages actually place, and with what arguments.

WHY THIS EXISTS

There are 78 entity-type handlers left to translate and no reason to do them in
address order. This says which types the 66 shipped `ev*.dat` files actually
place, how often, in how many stages, under which trigger opcodes, and what
range their ParamA argument takes.

That last column is the useful one twice over:

  * it PRIORITISES. Type 25 is placed 160 times across all 65 stages; most types
    appear once or twice. Translating the common ones first buys more of the
    game per function read.
  * it CORROBORATES. When a handler indexes a table by ParamA and the observed
    argument range is exactly 0..N-1 for a table of N entries, the table and its
    use agree from both directions - which is much stronger evidence for the
    table's length than either fact alone. Cross-check with tools/table_bounds.py.

It also finds types that are placed but have NO handler arm, which is how "type
20 is an inert marker" stopped being a guess: 9 placements, all opcode 4, and no
arm in the dispatcher's jump table.

AND THE SCRIPTS. `--paramb` groups by the ParamB program rather than the type,
which is what identified the save point: type 27 appears exactly once in each of
43 stages, always opcode 1, and with a ParamB that is byte-identical in all 43 -
say a line, test a flag, SAVE, say another line.

USAGE

    python tools/entity_usage.py <gamedir>
    python tools/entity_usage.py <gamedir> --type 25
    python tools/entity_usage.py <gamedir> --paramb
"""

import argparse
import collections
import glob
import os
import re
import sys

# csv 0 opcode, 1 required flag, 2 forbidding flag, 3 tileX, 4 tileY,
# 5 ParamA, 6 ParamB - see src/EventScripts.pas for the whole record.
OPCODES = {
    0: 'touch',
    1: 'touch+button',
    2: 'push (unused)',
    3: 'push+confirm (unused)',
    4: 'puzzle checker',
    5: 'sets a flag',
    6: 'on being shot',
    7: 'on destroy',
    9: 'collectible',
}


def split_args(rest):
    """Split ParamA's tail on '-', treating a leading '-' as a minus sign."""
    args, cur = [], ''
    for ch in rest:
        if ch == '-' and cur != '':
            args.append(cur)
            cur = ''
        elif ch == '-' and cur == '':
            cur = '-'
        else:
            cur += ch
    if cur != '':
        args.append(cur)
    return args


def load(gamedir):
    rows = []
    pat = os.path.join(gamedir, 'data', 'ev*.dat')
    for path in sorted(glob.glob(pat)):
        stage = int(re.search(r'ev(\d+)', os.path.basename(path)).group(1))
        for line in open(path, encoding='latin-1'):
            f = [x.strip() for x in line.strip().split(',')]
            if len(f) != 7:
                continue
            m = re.match(r'^(\d{4})(?:-(.)(?:-(.*))?)?$', f[5])
            if not m:
                continue
            args = split_args(m.group(3) or '')
            rows.append(dict(stage=stage, op=int(f[0]), req=f[1], forb=f[2],
                             tx=int(f[3]), ty=int(f[4]),
                             type=int(m.group(1)), kind=m.group(2) or '',
                             args=args, pa=f[5], pb=f[6]))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('gamedir')
    ap.add_argument('--type', type=int, help='detail for one type')
    ap.add_argument('--paramb', action='store_true',
                    help='group by ParamB program instead')
    args = ap.parse_args()

    rows = load(args.gamedir)
    if not rows:
        print('no event records found under %s/data' % args.gamedir)
        return 2

    if args.type is not None:
        sel = [r for r in rows if r['type'] == args.type]
        print('type %d: %d records across %d stages'
              % (args.type, len(sel), len({r['stage'] for r in sel})))
        if not sel:
            return 1
        print('  opcodes   : %s'
              % ', '.join('%d %s x%d' % (o, OPCODES.get(o, '?'), n)
                          for o, n in
                          sorted(collections.Counter(r['op'] for r in sel).items())))
        print('  ParamA    : %s'
              % ', '.join('%s x%d' % kv for kv in
                          collections.Counter(r['pa'] for r in sel).most_common(6)))
        a0 = collections.Counter(int(r['args'][0]) for r in sel
                                 if r['args'] and re.fullmatch(r'-?\d+', r['args'][0]))
        if a0:
            lo, hi = min(a0), max(a0)
            print('  arg 0     : %d distinct, range %d..%d %s'
                  % (len(a0), lo, hi,
                     '- FLUSH with a %d-entry table' % (hi + 1)
                     if lo == 0 and len(a0) == hi + 1 else ''))
            print('              %s' % sorted(a0.items()))
        print('  tiles     : x %d..%d, y %d..%d'
              % (min(r['tx'] for r in sel), max(r['tx'] for r in sel),
                 min(r['ty'] for r in sel), max(r['ty'] for r in sel)))
        pbs = collections.Counter(r['pb'] for r in sel)
        print('  ParamB    : %d distinct' % len(pbs))
        for pb, n in pbs.most_common(6):
            print('     x%-4d %s' % (n, pb))
        return 0

    if args.paramb:
        by = collections.defaultdict(list)
        for r in rows:
            by[(r['type'], r['pb'])].append(r)
        print('type / ParamB programs used in more than one stage, '
              'most widespread first')
        print()
        items = sorted(by.items(), key=lambda kv: -len({r['stage'] for r in kv[1]}))
        for (t, pb), sel in items[:25]:
            stages = len({r['stage'] for r in sel})
            if stages < 2:
                continue
            print('  type %-3d in %2d stages, %2d records  %s'
                  % (t, stages, len(sel), pb[:70]))
        return 0

    cnt = collections.Counter(r['type'] for r in rows)
    stages = collections.defaultdict(set)
    ops = collections.defaultdict(collections.Counter)
    for r in rows:
        stages[r['type']].add(r['stage'])
        ops[r['type']][r['op']] += 1

    print('%d event records, %d distinct types placed' % (len(rows), len(cnt)))
    print()
    print('type  count  stages  opcodes')
    for t, n in cnt.most_common():
        o = ','.join('%d:%d' % kv for kv in sorted(ops[t].items()))
        print('%4d  %5d  %6d  %s' % (t, n, len(stages[t]), o))
    return 0


if __name__ == '__main__':
    sys.exit(main())
