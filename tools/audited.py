#!/usr/bin/env python3
"""Keep notes/audited.md honest.

    python tools/audited.py

WHY

notes/audited.md claims "this function's Pascal has been read against a fresh
decompile and here is what was compared". That claim ages badly in exactly the
way this project keeps getting caught by: the code moves, the note does not,
and the next audit reads it and believes it.

Three things are checked, and none of them can prove an audit was actually
done - only that the list still describes this repository:

  * every audited address still appears somewhere in src/, so a function that
    was renamed or deleted cannot sit in the list looking verified
  * no address is in BOTH the audited table and the "NOT yet audited" list,
    which is the mistake you make when you audit one and forget to move it
  * every row names what was compared, because "audited" with no detail is the
    kind of claim the file exists to replace

It cannot tell you the audit was thorough. Nothing can. It only stops the list
from quietly describing a repository that no longer exists.
"""

import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(REPO, 'notes', 'audited.md')
ADDR = re.compile(r'0x00[0-9A-Fa-f]{6}')


def main():
    if not os.path.exists(LEDGER):
        print('FAIL: notes/audited.md is missing')
        return 1
    text = open(LEDGER, encoding='utf-8').read()

    head, _, tail = text.partition('## NOT yet audited')
    rows = [l for l in head.split('\n') if l.startswith('| 0x')]

    audited = {}
    bad = []
    for r in rows:
        cells = [c.strip() for c in r.strip('|').split('|')]
        a = cells[0].lower()
        audited[a] = cells
        # A row has to say what was compared. Four columns in the flow table,
        # three in the supporting one; the last cell is the detail either way.
        if len(cells) < 3 or len(cells[-1]) < 40:
            bad.append('%s: the row does not say what was compared' % a)

    src = ''
    for root, _, files in os.walk(os.path.join(REPO, 'src')):
        if os.path.basename(root) in ('lib', 'backup'):
            continue
        for f in files:
            if f.endswith(('.pas', '.lpr', '.inc')):
                src += open(os.path.join(root, f), encoding='utf-8',
                            errors='replace').read()
    src_low = src.lower()

    for a in audited:
        if a not in src_low:
            bad.append('%s is listed as audited and appears nowhere in src/ - '
                       'it was renamed or removed and the row was left behind'
                       % a)

    for a in {m.lower() for m in ADDR.findall(tail)}:
        if a in audited:
            bad.append('%s is in BOTH the audited table and the not-yet list'
                       % a)

    matches = sum(1 for c in audited.values() if 'MATCHES' in c[2])
    fixed = sum(1 for c in audited.values() if 'FIXED' in c[2])
    todo = len({m.lower() for m in ADDR.findall(tail)})

    if bad:
        print('FAIL - notes/audited.md no longer describes this repository:')
        for b in bad:
            print('  ' + b)
        return 1

    print('%d functions audited (%d matched, %d needed a fix), %d still to do'
          % (len(audited), matches, fixed, todo))
    return 0


if __name__ == '__main__':
    sys.exit(main())
