#!/usr/bin/env python3
"""Every witnessed field offset must be asserted somewhere that runs.

    python tools/layout_lock.py

WHY

A record whose offsets must match the original's memory rots silently. The
declarations carry the evidence - a `// +0xNNN` on a field is a claim that the
disassembly was seen to touch that offset - but a comment does not fail a
build. Three of the four size guards were `Assert`s in `initialization`
sections, and FPC compiles assertions out unless -Sa is passed, which this
project does not pass: falsifying one to `SizeOf(TEntity) = 999` on 2026-08-31
changed nothing, so they had never run.

And a size check is not enough on its own. Two same-sized fields can swap and
leave SizeOf untouched, which is precisely the failure that misreads a save
file - `Lives` and `MaxLives` swapped is a valid record of the right length.

So --selftest-layouts asserts every offset at runtime, and this checks that
--selftest-layouts is COMPLETE: annotate a new field and forget the assertion
and the gate says so, rather than the annotation quietly becoming decoration.
"""

import os
import re
import sys

from source_tree import unit_path

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# record declaration -> the unit it lives in
RECORDS = [
    ('TPlayerState', 'TPlayerState = packed record', 'PlayerState.pas'),
    ('TInputState', 'TInputState = record', 'GameState.pas'),
    ('TGameSettings', 'TGameSettings = record', 'GameState.pas'),
]


def annotated(rec, decl, unit):
    """(field, offset) for every field carrying a witnessed +0xNNN."""
    text = open(unit_path(REPO, unit), encoding='utf-8').read()
    i = text.index(decl)
    j = text.index('end;', i)
    out = {}
    for line in text[i:j].split('\n'):
        m = re.match(r'\s*([A-Za-z_]\w*)\s*:\s*[^;]+;\s*//\s*\+0x([0-9A-Fa-f]+)',
                     line)
        if m:
            out[m.group(1)] = int(m.group(2), 16)
    return out


def asserted():
    """(record, field) -> offset, from the Off(...) calls in the suite."""
    text = open(os.path.join(REPO, 'src', 'akuji.lpr'), encoding='utf-8').read()
    i = text.find('function SelfTestLayouts')
    if i < 0:
        return None
    body = text[i:text.index('\nend;', i)]
    out = {}
    for m in re.finditer(r"Off\('(\w+)\.(\w+)'[^;]*\$([0-9A-Fa-f]+)\)", body):
        out[(m.group(1), m.group(2))] = int(m.group(3), 16)
    return out


def main():
    got = asserted()
    if got is None:
        print('FAIL: SelfTestLayouts is gone - nothing checks the layouts at '
              'runtime any more')
        return 1

    bad = []
    total = 0
    for rec, decl, unit in RECORDS:
        want = annotated(rec, decl, unit)
        total += len(want)
        for field, off in sorted(want.items(), key=lambda kv: kv[1]):
            key = (rec, field)
            if key not in got:
                bad.append('%s.%s is annotated +0x%X and nothing asserts it - '
                           'add an Off() line to SelfTestLayouts'
                           % (rec, field, off))
            elif got[key] != off:
                bad.append('%s.%s is annotated +0x%X but asserted +0x%X - one '
                           'of the two is wrong and only the disassembly says '
                           'which' % (rec, field, off, got[key]))
        for r, f in got:
            if r == rec and f not in want:
                bad.append('%s.%s is asserted but no longer annotated - either '
                           'the field went away or its evidence did' % (r, f))

    if bad:
        print('FAIL - a witnessed offset is not locked down:')
        for b in bad:
            print('  %s' % b)
        return 1

    print('%d witnessed offsets, every one asserted at runtime' % total)
    return 0


if __name__ == '__main__':
    sys.exit(main())
