#!/usr/bin/env python3
"""Check each handler's scalar constants actually appear in that handler's code.

    python tools/const_immediates.py [--all]

WHY

The 181 table pins cover const ARRAYS. Nothing covered scalar constants - the
velocities, gravities and reload counts written straight into the source as
`T44_LAUNCH_VY = -$B0` - and one of those was wrong for a long time.

The disassembly writes that launch velocity as the literal `0xFFFFFFB0`. That
is -80, which is -$50: the low byte is the two's complement, not the magnitude.
Transcribed as -$B0 it became -176, and the entity left the ground at more than
twice the right speed. --emudiff found it, but only because the probe happened
to drive type 44 through the one state that uses it; nothing would have found
the same slip in a state the sweep does not reach.

There are 28 negative hex constants in the handlers and the same misreading is
available in every one of them.

WHAT IT DOES

A constant that a handler really uses appears in that handler's machine code as
an immediate. So: take every `T<nn>_NAME = <value>` constant, find handler nn's
byte range, and look for the value's 32-bit little-endian encoding inside it.

    found        the constant is in the code, at the value we claim
    NOT FOUND    it is not - either the value is wrong, or it is not an
                 immediate (computed, folded, or an 8-bit form)

A miss is a PROMPT, not a verdict. The compiler encodes small values in one
byte, folds constant arithmetic, and some of these constants are ours rather
than the original's. What the check is good at is the specific case it was
written for: a value that is out by exactly the two's-complement fold, where the
WRONG value is absent and the RIGHT one is present a few bytes away. That pair
of facts is close to conclusive, and the report calls it out.
"""

import argparse
import os
import re
import struct
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(REPO, 'English Translated Version 1.1 (D)', 'akuji.exe')
SRC = os.path.join(REPO, 'src', 'EntityHandlers.pas')

CODE_VA_BIAS = 0x400C00          # CODE: VA 0x401000 at raw 0x400
CONST_RE = re.compile(r'^\s*T(\d+)_([A-Z0-9_]+)\s*=\s*(-?\$[0-9A-Fa-f]+|-?\d+)\s*;',
                      re.M)


def handler_addrs():
    src = open(SRC, encoding='utf-8').read()
    i = src.index('HANDLER_ADDR: array')
    body = src[src.index('(', i) + 1:src.index(');', i)]
    body = re.sub(r'[{][^}]*[}]', ' ', body)
    return [int(t.strip()[1:], 16) for t in body.replace(chr(10), ' ').split(',')
            if t.strip().startswith('$')]


def value_of(tok):
    neg = tok.startswith('-')
    t = tok.lstrip('-')
    v = int(t[1:], 16) if t.startswith('$') else int(t)
    return -v if neg else v


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--all', action='store_true',
                    help='list every constant, not only the misses')
    args = ap.parse_args()

    if not os.path.exists(EXE):
        print('no akuji.exe to check against')
        return 0

    blob = open(EXE, 'rb').read()
    addrs = handler_addrs()
    ordered = sorted(a for a in addrs if a)

    def span(typ):
        a = addrs[typ] if typ < len(addrs) else 0
        if not a:
            return None
        nxt = next((x for x in ordered if x > a), a + 0x400)
        lo = a - CODE_VA_BIAS
        hi = min(nxt - CODE_VA_BIAS, lo + 0x1000)
        return blob[lo:hi]

    src = open(SRC, encoding='utf-8').read()
    checked = misses = folds = 0
    reports = []

    for m in CONST_RE.finditer(src):
        typ, name, tok = int(m.group(1)), m.group(2), m.group(3)
        if typ >= len(addrs) or not addrs[typ]:
            continue
        # *_ADDR constants are DATA addresses reached through a pointer global,
        # so they are never immediates in the handler and swamped the report -
        # 177 misses, none of them meaningful. Their extents and values are
        # covered by table_extents.py and the 181 pins instead.
        if name.endswith('_ADDR'):
            continue
        code = span(typ)
        if not code:
            continue
        v = value_of(tok)
        # A small POSITIVE is encoded in one byte and would match noise
        # everywhere, so skip those. Negatives are NOT skipped: `mov dword ptr
        # [e], 0xFFFFFFB0` carries the full four-byte immediate, and those are
        # precisely the constants this exists to check - the first version of
        # this filter said `-0x8000 < v < 0x100` and quietly excluded every one
        # of them, which is how a checker ends up reporting 39 clean results
        # about the constants nobody was worried about.
        if 0 <= v < 0x100:
            continue
        checked += 1
        enc = struct.pack('<i', v)
        if enc in code:
            if args.all:
                reports.append(('found', typ, name, tok, ''))
            continue
        misses += 1
        # The specific slip this exists for: is the two's-complement fold there
        # instead? -$B0 written for 0xFFFFFFB0, whose real value is -$50.
        note = ''
        if v < 0 and -0x100 < v:
            alt = -(0x100 + v)          # -0xB0 -> -0x50
            if struct.pack('<i', alt) in code:
                note = ('the fold IS present: -$%X. This looks like 0xFFFFFF%02X '
                        'transcribed as its low byte' % (abs(alt), abs(v)))
                folds += 1
        reports.append(('MISSING', typ, name, tok, note))

    for kind, typ, name, tok, note in reports:
        if kind == 'found':
            print('  found    T%d_%s = %s' % (typ, name, tok))
        else:
            print('  MISSING  T%d_%s = %s  not an immediate in handler %d'
                  % (typ, name, tok, typ))
            if note:
                print('           %s' % note)

    print('\n%d scalar constants checked, %d not found as immediates, '
          '%d of those look like a two\'s-complement misread'
          % (checked, misses, folds))
    if folds:
        print('a fold match is close to conclusive: the value we claim is '
              'absent and the one the fold predicts is present')
    return 1 if folds else 0


if __name__ == '__main__':
    sys.exit(main())
