#!/usr/bin/env python3
"""Keep notes/audited.md honest, and freeze what it says is verified.

    python tools/audited.py            check
    python tools/audited.py --list     list by status (--unverified default;
                                       also --matches --fixed --partial
                                       --emudiff)
    python tools/audited.py --bless    rewrite notes/audited.lock

THREE TABLES, because there are three kinds of thing this project reimplements:

  1. game-layer functions - population is notes/game_functions.txt, all 149,
     and every one must have a row
  2. the component layer - the DirectX and audio suite we replace wholesale.
     NOT a complete population; there is no authority file, only the addresses
     our own source cites
  3. binary layouts - records whose offsets or size must match the original's
     memory

THE FREEZE, CLAUDE.md section 3a. A MATCHES, FIXED or PARTIAL row has been read
against a fresh decompile, and that pass is expensive enough that an edit made
in passing to fix something else silently destroys it - leaving a row that says
verified beside code it no longer describes. So each frozen row names the Pascal
implementing it and is fingerprinted into notes/audited.lock with COMMENTS
STRIPPED and whitespace normalised: prose and layout stay free, a changed
statement does not. `--bless` rewrites the lock and IS the approval gesture.

It cannot prove an audit was thorough. It only stops the tables describing a
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

FROZEN_STATES = ('MATCHES', 'FIXED', 'PARTIAL')
ALL_STATES = FROZEN_STATES + ('EMUDIFF', 'UNVERIFIED')

SEC_GAME = '## 1. Game-layer functions'
SEC_COMP = '## 2. The component layer'
SEC_LAY = '## 3. Binary layouts'
SEC_END = '## Supporting routines'


def authority():
    out = []
    for line in open(AUTHORITY, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        p = line.split()
        if len(p) >= 2 and re.fullmatch(r'[0-9A-Fa-f]{8}', p[0]):
            out.append(('0x' + p[0].lower(), p[1]))
    return out


def section(text, start, end):
    i = text.find(start)
    j = text.find(end, i + 1) if i >= 0 else -1
    if i < 0:
        return ''
    return text[i:j] if j > i else text[i:]


def fn_rows(block):
    """addr | name | status | impl | why"""
    out = []
    for line in block.split('\n'):
        if not line.startswith('| 0x'):
            continue
        c = [x.strip() for x in line.strip().strip('|').split('|')]
        if len(c) != 5:
            continue
        out.append({'addr': c[0].lower(), 'name': c[1].strip('`'),
                    'status': c[2], 'impl': c[3].strip('`').strip(),
                    'why': c[4]})
    return out


def lay_rows(block):
    """record | unit | status | why"""
    out = []
    for line in block.split('\n'):
        if not line.startswith('| `T'):
            continue
        c = [x.strip() for x in line.strip().strip('|').split('|')]
        if len(c) != 4:
            continue
        out.append({'rec': c[0].strip('`'), 'unit': c[1], 'status': c[2],
                    'why': c[3]})
    return out


def normalise(body):
    body = re.sub(r'\{(?!\$)[^}]*\}', ' ', body, flags=re.S)
    body = re.sub(r'\(\*.*?\*\)', ' ', body, flags=re.S)
    body = re.sub(r'//[^\n]*', ' ', body)
    return re.sub(r'\s+', ' ', body).strip()


def routine_body(unit, name):
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
    return normalise(after[:m.start()] if m else after)


def record_body(unit, name):
    """A record declaration, from `TName = record` to its matching end. Depth
    counted on the words, because a variant part nests another `record`."""
    path = os.path.join(REPO, 'src', unit)
    if not os.path.exists(path):
        return None
    text = open(path, encoding='utf-8', errors='replace').read()
    m = re.search(r'(?<![A-Za-z0-9_])' + re.escape(name)
                  + r'\s*=\s*(?:packed\s+)?record(?![A-Za-z0-9_])', text)
    if not m:
        return None
    stripped = normalise(text[m.start():])
    depth = 0
    for t in re.finditer(r'(?<![A-Za-z0-9_])(record|end)(?![A-Za-z0-9_])',
                         stripped):
        if t.group(1) == 'record':
            depth += 1
        else:
            depth -= 1
            if depth == 0:
                return stripped[:t.end()]
    return None


def main():
    text = open(LEDGER, encoding='utf-8').read()
    game = fn_rows(section(text, SEC_GAME, SEC_COMP))
    comp = fn_rows(section(text, SEC_COMP, SEC_LAY))
    lays = lay_rows(section(text, SEC_LAY, SEC_END))
    inv = authority()
    known = {a for a, _ in inv}
    bad = []
    now = {}

    def check(rows, checked_against_authority, label):
        seen = set()
        for r in rows:
            if r['addr'] in seen:
                bad.append('%s appears twice in %s' % (r['addr'], label))
            seen.add(r['addr'])
            if r['status'] not in ALL_STATES:
                bad.append('%s has status %r' % (r['addr'], r['status']))
            if checked_against_authority and r['addr'] not in known:
                bad.append('%s is in %s but not in game_functions.txt'
                           % (r['addr'], label))
            if r['status'] in FROZEN_STATES:
                if len(r['why']) < 40:
                    bad.append('%s is %s but does not say what was compared'
                               % (r['addr'], r['status']))
                if r['impl']:
                    p = r['impl'].split()
                    if len(p) != 2:
                        bad.append('%s has an unreadable implementation %r'
                                   % (r['addr'], r['impl']))
                    else:
                        b = routine_body(p[0], p[1])
                        k = '%s %s %s' % (r['addr'], p[0], p[1])
                        now[k] = (hashlib.sha256(b.encode()).hexdigest()[:16]
                                  if b is not None else 'MISSING')
                        if b is None:
                            bad.append('%s is frozen and its Pascal cannot be '
                                       'found' % k)
        return seen

    seen_game = check(game, True, 'the game table')
    check(comp, False, 'the component table')
    for addr, name in inv:
        if addr not in seen_game:
            bad.append('%s %s is in the authority and missing from the game '
                       'table' % (addr, name))

    for r in lays:
        if r['status'] not in ALL_STATES:
            bad.append('%s has status %r' % (r['rec'], r['status']))
        if r['status'] in FROZEN_STATES:
            if len(r['why']) < 40:
                bad.append('%s is %s but does not say what was compared'
                           % (r['rec'], r['status']))
            b = record_body(r['unit'], r['rec'])
            k = 'layout %s %s' % (r['unit'], r['rec'])
            now[k] = (hashlib.sha256(b.encode()).hexdigest()[:16]
                      if b is not None else 'MISSING')
            if b is None:
                bad.append('%s is frozen and its record cannot be found' % k)

    if '--list' in sys.argv:
        want = 'UNVERIFIED'
        for st in ALL_STATES:
            if '--' + st.lower() in sys.argv:
                want = st
        n = 0
        for r in game + comp:
            if r['status'] == want:
                print('  %s  %s' % (r['addr'], r['name']))
                n += 1
        for r in lays:
            if r['status'] == want:
                print('  layout    %s' % r['rec'])
                n += 1
        print('%d %s' % (n, want))
        return 0

    if '--bless' in sys.argv:
        with open(LOCK, 'w', encoding='utf-8', newline='\n') as fh:
            fh.write('# Fingerprints of every frozen row in notes/audited.md.\n'
                     '# Comments and whitespace are excluded, so only a change\n'
                     '# of BEHAVIOUR or LAYOUT moves a hash.\n#\n'
                     '# Rewritten only by --bless, which is the approval\n'
                     '# gesture CLAUDE.md section 3a requires. Never run it to\n'
                     '# make the gate go quiet.\n')
            for k in sorted(now):
                fh.write('%s  %s\n' % (now[k], k))
        print('blessed %d frozen implementations' % len(now))
        return 0

    if not os.path.exists(LOCK):
        print('FAIL: notes/audited.lock is missing. Create it with --bless.')
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
            bad.append('FROZEN AND CHANGED: %s\n'
                       '      Verified against the disassembly; not to be '
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

    def tally(rows):
        return {s: sum(1 for r in rows if r['status'] == s) for s in ALL_STATES}
    g, c, l = tally(game), tally(comp), tally(lays)
    print('game %d: %d matched, %d fixed, %d emudiff, %d unverified'
          % (len(game), g['MATCHES'], g['FIXED'], g['EMUDIFF'],
             g['UNVERIFIED']))
    print('component %d: %d matched, %d unverified   layouts %d: %d matched, '
          '%d partial, %d unverified'
          % (len(comp), c['MATCHES'], c['UNVERIFIED'], len(lays),
             l['MATCHES'], l['PARTIAL'], l['UNVERIFIED']))
    print('%d frozen' % len(now))
    return 0


if __name__ == '__main__':
    sys.exit(main())
