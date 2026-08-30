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

AND IT FREEZES THEM. See CLAUDE.md section 3a. An audited function has been
through two passes - one that too often wrote the specification into Pascal, and
one that read the disassembly and implemented it for real - and a later edit made
in passing throws that away silently, leaving a row that says "verified" beside
code it no longer describes.

So the "Frozen implementations" block in notes/audited.md maps each address to
the Pascal that implements it, and every one is fingerprinted into
notes/audited.lock. Comments are stripped and whitespace normalised before
hashing, so prose and layout stay free to change and a changed STATEMENT does
not. A mismatch fails the gate and names the function.

    python tools/audited.py --bless

rewrites the lock. Blessing IS the approval gesture - the user has to have said
yes to a specific change first, and the function then needs re-auditing against
a fresh decompile.
"""

import hashlib
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(REPO, 'notes', 'audited.md')
ADDR = re.compile(r'0x00[0-9A-Fa-f]{6}')


FROZEN = re.compile(r'^\s{4}(0x00[0-9A-Fa-f]{6})\s+(\S+\.pas)\s+(\S+)\s*$', re.M)
LOCK = os.path.join(REPO, 'notes', 'audited.lock')


def routine_body(unit, name):
    """One routine's implementation, comments stripped and whitespace
    normalised. None if it cannot be found - a frozen function that no longer
    exists is exactly what this is here to catch."""
    path = os.path.join(REPO, 'src', unit)
    if not os.path.exists(path):
        return None
    text = open(path, encoding='utf-8', errors='replace').read()
    # The LAST match. A routine may be declared in the interface and defined in
    # the implementation, and it is the definition that carries the behaviour.
    head = re.compile(r'^(?:procedure|function)\s+' + re.escape(name)
                      + r'(?![A-Za-z0-9_])', re.M)
    starts = [m.start() for m in head.finditer(text)]
    if not starts:
        return None
    after = text[starts[-1]:]
    nxt = re.compile(r'\n(?:procedure|function)\s+[A-Za-z_]', re.M)
    m = nxt.search(after, 1)
    body = after[:m.start()] if m else after
    body = re.sub(r'\{(?!\$)[^}]*\}', ' ', body, flags=re.S)
    body = re.sub(r'\(\*.*?\*\)', ' ', body, flags=re.S)
    body = re.sub(r'//[^\n]*', ' ', body)
    return re.sub(r'\s+', ' ', body).strip()


def fingerprints(text):
    out = {}
    for addr, unit, name in FROZEN.findall(text):
        body = routine_body(unit, name)
        key = '%s %s %s' % (addr.lower(), unit, name)
        out[key] = (hashlib.sha256(body.encode('utf-8')).hexdigest()[:16]
                    if body is not None else 'MISSING')
    return out

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

    # --- the freeze, CLAUDE.md section 3a --------------------------------
    now = fingerprints(text)
    bless = '--bless' in sys.argv

    for k, v in now.items():
        if v == 'MISSING':
            bad.append('%s is frozen and its Pascal cannot be found - it was '
                       'renamed or removed' % k)

    if bless:
        with open(LOCK, 'w', encoding='utf-8', newline='\n') as fh:
            fh.write('# Fingerprints of the frozen implementations listed in\n'
                     '# notes/audited.md. Comments and whitespace are excluded,\n'
                     '# so only a change of BEHAVIOUR moves a hash.\n'
                     '#\n'
                     '# Rewritten only by `python tools/audited.py --bless`,\n'
                     '# which is the approval gesture required by CLAUDE.md\n'
                     '# section 3a. Do not run it to make the gate go quiet.\n')
            for k in sorted(now):
                fh.write('%s  %s\n' % (now[k], k))
        print('blessed %d frozen implementations into notes/audited.lock'
              % len(now))
        return 0

    if not os.path.exists(LOCK):
        print('FAIL: notes/audited.lock is missing. Create it once with '
              '`python tools/audited.py --bless`.')
        return 1

    old = {}
    for line in open(LOCK, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        h, _, k = line.partition('  ')
        old[k] = h

    for k, v in now.items():
        if k not in old:
            bad.append('%s is newly frozen and has no fingerprint - bless it '
                       'once its audit row is written' % k)
        elif old[k] != v:
            bad.append('FROZEN FUNCTION CHANGED: %s\n'
                       '      It was audited against the disassembly and must '
                       'not be edited as collateral.\n'
                       '      If it really is wrong: say so, quote the '
                       'disassembly, and ASK - CLAUDE.md section 3a\n'
                       '      requires approval BEFORE the edit, then a '
                       're-audit, then --bless.' % k)
    for k in old:
        if k not in now:
            bad.append('%s has a fingerprint but is no longer listed as frozen'
                       % k)

    if bad:
        print('FAIL - notes/audited.md no longer describes this repository:')
        for b in bad:
            print('  ' + b)
        return 1

    print('%d functions audited (%d matched, %d needed a fix), %d still to do; '
          '%d frozen' % (len(audited), matches, fixed, todo, len(now)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
