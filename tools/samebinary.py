#!/usr/bin/env python3
"""Does src/akuji.exe still produce v1.0's machine code?

    python tools/samebinary.py [--record]

WHY THIS IS NOT A HASH OF THE FILE

The obvious constraint for the cleanup phase - "the source must still compile
to the same executable" - is not checkable as a file hash, for two reasons
that were measured rather than assumed:

  * The build carries DWARF. Five sections (/4, /19, /31, /45, /57) hold it,
    /19 alone is 21MB of the 28MB file, and it contains every identifier.
    RENAMING ANYTHING CHANGES THEM. A file hash would forbid exactly the work
    this phase exists to do.

  * The whole-file hash is not even stable across rebuilds of IDENTICAL
    source. lazbuild recompiles only what changed, and the debug sections come
    out laid differently depending on which units were touched. Two clean
    builds agree; a clean build and an incremental one need not.

What IS stable, and was checked both ways:

    a comment-only edit          -> every section identical
    renaming a used constant     -> DWARF differs, every real section identical
    rebuild after reverting      -> DWARF differs, every real section identical

So the constraint is on the sections that become the running program:

    .text .data .rdata .pdata .idata .rsrc .CRT

If those match v1.0, the executable behaves identically - the machine code,
the constants, the resources and the import table are the same bytes. If one
of them moves, something changed that a rename cannot explain, and that is
exactly what this phase must not do silently.

WHAT A FAILURE MEANS

Not necessarily a mistake. A deliberate fix to a real defect SHOULD move
.text, and then the baseline is re-recorded with --record and the reason goes
in the commit message. What must not happen is .text moving without anyone
noticing.
"""

import hashlib
import io
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EXE = os.path.join(ROOT, 'src', 'akuji.exe')
BASELINE = os.path.join(HERE, 'v1.0_sections.json')

# The sections that become the running program. Everything else in the file is
# debug information, which identifiers reach and behaviour does not.
REAL = ('.text', '.data', '.rdata', '.pdata', '.idata', '.rsrc', '.CRT')


def sections(path):
    """name -> raw bytes, straight out of the PE section table."""
    d = open(path, 'rb').read()
    pe = struct.unpack_from('<I', d, 0x3C)[0]
    count = struct.unpack_from('<H', d, pe + 6)[0]
    optsize = struct.unpack_from('<H', d, pe + 20)[0]
    off = pe + 24 + optsize
    out = {}
    for _ in range(count):
        name = d[off:off + 8].rstrip(b'\0').decode('latin-1')
        _vsz, _va, rsz, raw = struct.unpack_from('<IIII', d, off + 8)
        out[name] = d[raw:raw + rsz]
        off += 40
    return out


def digest(path):
    s = sections(path)
    return dict((n, hashlib.sha256(s[n]).hexdigest()) for n in REAL if n in s)


def main():
    if not os.path.isfile(EXE):
        print('no src/akuji.exe - build first')
        return 2

    now = digest(EXE)

    if '--record' in sys.argv:
        io.open(BASELINE, 'w', encoding='utf-8').write(
            json.dumps(now, indent=2, sort_keys=True) + '\n')
        print('recorded %d sections as the baseline:' % len(now))
        for n in sorted(now):
            print('  %-8s %s' % (n, now[n][:16]))
        return 0

    if not os.path.isfile(BASELINE):
        print('no baseline - run with --record')
        return 2

    want = json.loads(io.open(BASELINE, encoding='utf-8').read())
    bad = []
    for n in sorted(set(want) | set(now)):
        if want.get(n) != now.get(n):
            bad.append(n)

    if not bad:
        print('same machine code as v1.0 - %d sections match '
              '(debug info is not compared, and does not have to)' % len(want))
        return 0

    print('CHANGED: %s' % ', '.join(bad))
    print()
    print('Something moved that a rename cannot explain. Either the edit')
    print('changed behaviour, or it was a deliberate fix - in which case')
    print('re-record with --record and say why in the commit message.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
