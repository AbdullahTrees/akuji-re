#!/usr/bin/env python3
"""Keep notes/audited.md honest, and freeze what it says is verified.

    python tools/audited.py            check
    python tools/audited.py --list     list by status (--unverified default;
                                       also --matches --fixed --emudiff)
    python tools/audited.py --bless    rewrite notes/audited.lock

notes/audited.md is ONE row per game-layer function, and the STATUS says what
evidence exists and therefore whether the function may be edited:

    MATCHES / FIXED   read against a fresh decompile. FROZEN
    EMUDIFF           an entity handler, verified by running the original's own
                      machine code. Changeable, but re-run emudiff after
    UNVERIFIED        no evidence. Free to change

THE FREEZE, CLAUDE.md section 3a. A MATCHES or FIXED function went through two
passes: a first that too often wrote the SPECIFICATION into Pascal - a comment
describing the binary beside code that did something else - and a second that
read the disassembly, implemented the behaviour, and tested it. That second
pass is the only reason the row can be trusted, and an edit made in passing
throws it away silently.

Each frozen row names the Pascal implementing it, fingerprinted into
notes/audited.lock with COMMENTS STRIPPED and whitespace normalised - prose and
layout stay free, a changed statement does not. `--bless` rewrites the lock and
IS the approval gesture.

It cannot prove an audit was thorough. It only stops the table describing a
repository that no longer exists.
"""

import hashlib
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(REPO, 'notes', 'audited.md')
LOCK = os.path.join(REPO, 'notes', 'audited.lock')
AUTHORITY = os.path.join(REPO, 'notes', 'game_functions.txt')

FROZEN_STATES = ('MATCHES', 'FIXED')
ALL_STATES = FROZEN_STATES + ('EMUDIFF', 'UNVERIFIED')


def authority():
    """The population. A hand-written list of what is left drifts away from
    this the moment one is audited - this file used to carry one that said
    eight when the truth was fifty-nine."""
    out = []
    for line in open(AUTHORITY, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        p = line.split()
        if len(p) >= 2 and re.fullmatch(r'[0-9A-Fa-f]{8}', p[0]):
            out.append(('0x' + p[0].lower(), p[1]))
    return out


def rows():
    """The one table. Five columns; the three-column supporting table below it
    is skipped by the length check rather than by position."""
    out = []
    for line in open(LEDGER, encoding='utf-8'):
        if not line.startswith('| 0x'):
            continue
        c = [x.strip() for x in line.strip().strip('|').split('|')]
        if len(c) != 5:
            continue
        out.append({'addr': c[0].lower(), 'name': c[1].strip('`'),
                    'status': c[2], 'impl': c[3].strip('`').strip(),
                    'why': c[4]})
    return out


def routine_body(unit, name):
    """One routine's implementation, comments stripped and whitespace
    normalised. None if it cannot be found - a frozen function that no longer
    exists is exactly what this catches."""
    path = os.path.join(REPO, 'src', unit)
    if not os.path.exists(path):
        return None
    text = open(path, encoding='utf-8', errors='replace').read()
    head = re.compile(r'^(?:procedure|function)\s+' + re.escape(name)
                      + r'(?![A-Za-z0-9_])', re.M)
    starts = [m.start() for m in head.finditer(text)]
    if not starts:
        return None
    after = text[starts[-1]:]
    m = re.compile(r'\n(?:procedure|function)\s+[A-Za-z_]', re.M).search(after, 1)
    body = after[:m.start()] if m else after
    body = re.sub(r'\{(?!\$)[^}]*\}', ' ', body, flags=re.S)
    body = re.sub(r'\(\*.*?\*\)', ' ', body, flags=re.S)
    body = re.sub(r'//[^\n]*', ' ', body)
    return re.sub(r'\s+', ' ', body).strip()


def main():
    table = rows()
    inv = authority()
    known = {a for a, _ in inv}
    bad = []
    seen = {}

    for r in table:
        if r['addr'] in seen:
            bad.append('%s appears twice in the table' % r['addr'])
        seen[r['addr']] = r
        if r['status'] not in ALL_STATES:
            bad.append('%s has status %r, not one of %s'
                       % (r['addr'], r['status'], ', '.join(ALL_STATES)))
        if r['addr'] not in known:
            bad.append('%s is in the table but not in game_functions.txt'
                       % r['addr'])
        if r['status'] in FROZEN_STATES:
            if not r['impl']:
                bad.append('%s is %s but names no implementation, so it cannot '
                           'be frozen' % (r['addr'], r['status']))
            elif len(r['why']) < 40:
                bad.append('%s is %s but does not say what was compared'
                           % (r['addr'], r['status']))

    for addr, name in inv:
        if addr not in seen:
            bad.append('%s %s is in the authority and missing from the table'
                       % (addr, name))

    now = {}
    for r in table:
        if r['status'] not in FROZEN_STATES or not r['impl']:
            continue
        parts = r['impl'].split()
        if len(parts) != 2:
            bad.append('%s has an unreadable implementation %r - want '
                       '"Unit.pas Routine"' % (r['addr'], r['impl']))
            continue
        unit, rout = parts
        body = routine_body(unit, rout)
        key = '%s %s %s' % (r['addr'], unit, rout)
        now[key] = (hashlib.sha256(body.encode('utf-8')).hexdigest()[:16]
                    if body is not None else 'MISSING')
        if body is None:
            bad.append('%s is frozen and its Pascal cannot be found' % key)

    if '--list' in sys.argv:
        want = 'UNVERIFIED'
        for st in ALL_STATES:
            if '--' + st.lower() in sys.argv:
                want = st
        for addr, name in inv:
            if seen.get(addr, {}).get('status') == want:
                print('  %s  %s' % (addr, name))
        print('%d %s' % (sum(1 for r in table if r['status'] == want), want))
        return 0

    if '--bless' in sys.argv:
        with open(LOCK, 'w', encoding='utf-8', newline='\n') as fh:
            fh.write('# Fingerprints of the frozen rows in notes/audited.md -\n'
                     '# every function whose status is MATCHES or FIXED.\n'
                     '# Comments and whitespace are excluded, so only a change\n'
                     '# of BEHAVIOUR moves a hash.\n#\n'
                     '# Rewritten only by --bless, which is the approval\n'
                     '# gesture CLAUDE.md section 3a requires. Never run it to\n'
                     '# make the gate go quiet.\n')
            for k in sorted(now):
                fh.write('%s  %s\n' % (now[k], k))
        print('blessed %d frozen implementations' % len(now))
        return 0

    if not os.path.exists(LOCK):
        print('FAIL: notes/audited.lock is missing. Create it once with '
              '--bless.')
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
            bad.append('%s is newly frozen and has no fingerprint' % k)
        elif old[k] != v:
            bad.append('FROZEN FUNCTION CHANGED: %s\n'
                       '      Audited against the disassembly; not to be '
                       'edited as collateral.\n'
                       '      If it really is wrong: say so, quote the '
                       'disassembly, and ASK - CLAUDE.md 3a\n'
                       '      requires approval BEFORE the edit, then a '
                       're-audit, then --bless.' % k)
    for k in old:
        if k not in now:
            bad.append('%s has a fingerprint but is no longer frozen' % k)

    if bad:
        print('FAIL - notes/audited.md no longer describes this repository:')
        for b in bad:
            print('  ' + b)
        return 1

    c = {st: sum(1 for r in table if r['status'] == st) for st in ALL_STATES}
    print('%d game functions: %d matched, %d fixed (%d frozen), %d by emudiff, '
          '%d unverified' % (len(table), c['MATCHES'], c['FIXED'], len(now),
                             c['EMUDIFF'], c['UNVERIFIED']))
    return 0


if __name__ == '__main__':
    sys.exit(main())
