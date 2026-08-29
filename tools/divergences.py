#!/usr/bin/env python3
"""Gate the divergence ledger against the source.

    python tools/divergences.py [--list]

The project's rule is that the Pascal matches the binary and that the binary's
bugs are reproduced rather than fixed. Every knowing exception has to be written
down in notes/divergences.md, and this makes that enforceable instead of
aspirational.

It fails if:

  * a `DIVERGENCE DIV-nnn` marker in src/ has no ledger entry
  * a ledger entry has no marker and did not declare `sites: none`
  * a marker sits in a file the entry does not list
  * an id is used twice
  * a category B entry - "component not built yet" - has no exit condition,
    which is what stops a temporary scaffold becoming permanent
  * anything is filed category A, which would mean a mistranslation was written
    down as acceptable instead of being fixed

WHAT IT CANNOT DO. It checks that declared divergences are declared truthfully.
It cannot find an UNdeclared one - nothing can, short of the differential tests
in notes/verification.md. This raises the cost of drifting silently; it does not
make it impossible.
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(REPO, 'notes', 'divergences.md')
SRC = os.path.join(REPO, 'src')

MARKER = re.compile(r'DIVERGENCE\s+(DIV-\d{3})')
HEADING = re.compile(r'^##\s+(DIV-\d{3})\s+-\s+(.+?)\s*$')
FIELD = re.compile(r'^-\s+(category|sites|exit|behaviour|original):\s*(.*)$')


def read_ledger():
    entries, order, cur = {}, [], None
    dupes = []
    for line in open(LEDGER, encoding='utf-8'):
        m = HEADING.match(line)
        if m:
            i = m.group(1)
            if i in entries:
                dupes.append(i)
            cur = {'id': i, 'title': m.group(2), 'sites': [], 'body': []}
            entries[i] = cur
            order.append(i)
            continue
        if cur is None:
            continue
        f = FIELD.match(line)
        if f:
            k, v = f.group(1), f.group(2).strip()
            if k == 'sites':
                # "none" may carry a trailing explanation of what stands
                # in for the missing line, so match the word, not the field.
                none = v.split(' - ')[0].strip().lower() == 'none'
                cur['sites'] = [] if none else [
                    s.strip() for s in v.split(',') if s.strip()]
                cur['sites_none'] = none
            else:
                cur[k] = v
        cur['body'].append(line.rstrip('\n'))
    return entries, order, dupes


def scan_src():
    found = {}
    for root, _, files in os.walk(SRC):
        for fn in sorted(files):
            if not fn.lower().endswith(('.pas', '.lpr', '.inc')):
                continue
            p = os.path.join(root, fn)
            rel = os.path.relpath(p, REPO).replace(chr(92), '/')
            for n, line in enumerate(open(p, encoding='utf-8',
                                          errors='replace'), 1):
                for m in MARKER.finditer(line):
                    found.setdefault(m.group(1), []).append((rel, n))
    return found


def main():
    if not os.path.exists(LEDGER):
        print('missing %s' % LEDGER)
        return 2
    entries, order, dupes = read_ledger()
    found = scan_src()
    bad = []

    for i in dupes:
        bad.append('%s is declared twice in the ledger' % i)

    for i, sites in sorted(found.items()):
        if i not in entries:
            where = ', '.join('%s:%d' % s for s in sites)
            bad.append('%s marked in source but not in the ledger (%s)'
                       % (i, where))
            continue
        declared = set(entries[i]['sites'])
        for rel, n in sites:
            if declared and rel not in declared:
                bad.append('%s marked at %s:%d, which the entry does not list '
                           '(lists %s)' % (i, rel, n, ', '.join(sorted(declared))))

    for i in order:
        e = entries[i]
        cat = e.get('category', '')
        if cat not in ('B', 'C', 'D'):
            if cat == 'A':
                bad.append('%s is filed category A - a mistranslation is a '
                           'defect to fix, never a divergence to record' % i)
            else:
                bad.append('%s has no usable category (got %r)' % (i, cat))
        if cat == 'B' and not e.get('exit'):
            bad.append('%s is category B but names no exit condition - a '
                       'temporary scaffold with no way to retire it' % i)
        if not e.get('behaviour'):
            bad.append('%s does not say whether it affects behaviour' % i)
        if not e.get('sites_none') and i not in found:
            bad.append('%s is in the ledger but no source marks it - either '
                       'the divergence is gone and the entry should be too, '
                       'or the marker was lost in an edit' % i)

    if '--list' in sys.argv:
        for i in order:
            e = entries[i]
            where = found.get(i, [])
            print('%s  [%s]  %s' % (i, e.get('category', '?'), e['title']))
            print('      %s' % (', '.join('%s:%d' % s for s in where)
                                or '(no source site - stands for a whole unit)'))

    n_b = sum(1 for i in order if entries[i].get('category') == 'B')
    print('\n%d divergences: %d B (temporary), %d C (toolchain), %d D (refusal)'
          % (len(order), n_b,
             sum(1 for i in order if entries[i].get('category') == 'C'),
             sum(1 for i in order if entries[i].get('category') == 'D')))

    if bad:
        print('\nFAIL')
        for b in bad:
            print('  %s' % b)
        return 1
    print('ledger and source agree')
    return 0


if __name__ == '__main__':
    sys.exit(main())
