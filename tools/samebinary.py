#!/usr/bin/env python3
"""Does src/akuji.exe still produce v1.0's machine code, and if not, where?

    python tools/samebinary.py             # did anything move?
    python tools/samebinary.py --where     # ...and which functions
    python tools/samebinary.py --record    # adopt this build as the baseline

WHY THIS IS NOT A HASH OF THE FILE

The obvious constraint for the cleanup phase - "the source must still compile
to the same executable" - is not checkable as a file hash, for two reasons that
were measured rather than assumed:

  * The build carries DWARF. Five sections (/4, /19, /31, /45, /57) hold it,
    /19 alone is 21MB of the 28MB file, and it contains every identifier.
    RENAMING ANYTHING CHANGES THEM. A file hash would forbid exactly the work
    this phase exists to do.

  * The whole-file hash is not even stable across rebuilds of IDENTICAL
    source. lazbuild recompiles only what changed, and the debug sections come
    out laid differently depending on which units were touched.

What IS stable, checked both ways:

    a comment-only edit            -> every section identical
    renaming a used constant       -> DWARF differs, real sections identical
    literal -> named constant      -> DWARF differs, real sections identical
    introducing a local variable   -> .text CHANGED

So the constraint is on the sections that become the running program:

    .text .data .rdata .pdata .idata .rsrc .CRT

If those match v1.0 the executable behaves identically - same machine code,
same constants, same resources, same imports.

--where NAMES THE FUNCTIONS THAT MOVED, which is what makes an exception
reviewable: a named list instead of a 2MB diff. It finds them without a map
file and without touching the build:

  * .pdata is a table of RUNTIME_FUNCTION - begin RVA, end RVA, unwind info -
    one per function, which x86-64 PE requires for stack unwinding. 11091 of
    them here, covering 1.9MB of the 2.0MB .text.
  * the linker left a COFF symbol table with FPC's mangled names.
    ENTITYHANDLERS_$$_ENTITYUPDATE_TYPE07$... becomes
    EntityHandlers.EntityUpdate_Type07. 7698 of the 11091 get a real name; the
    rest are RTL and LCL bodies with no symbol, and show as sub_XXXXXXXX.

A COFF symbol's Value is an offset within ITS SECTION, not an RVA. Forgetting
to add the section base still matched 918 of 9717 symbols by coincidence,
which looks enough like success to ship. It does not.

WHAT A FAILURE MEANS

Not necessarily a mistake. A deliberate fix to a real infidelity SHOULD move
.text, and then the baseline is re-recorded with --record and the reason goes
in the commit message - see notes/v1.0_handover.md for when that is allowed.
What must not happen is .text moving without anyone noticing.
"""

import hashlib
import io
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EXE = os.path.join(ROOT, 'src', 'akuji.exe')
SECTIONS = os.path.join(HERE, 'v1.0_sections.json')
FUNCTIONS = os.path.join(HERE, 'v1.0_functions.json')

# The sections that become the running program. Everything else in the file is
# debug information, which identifiers reach and behaviour does not.
REAL = ('.text', '.data', '.rdata', '.pdata', '.idata', '.rsrc', '.CRT')


def pe_sections(d):
    pe = struct.unpack_from('<I', d, 0x3C)[0]
    nsec = struct.unpack_from('<H', d, pe + 6)[0]
    optsize = struct.unpack_from('<H', d, pe + 20)[0]
    off = pe + 24 + optsize
    out = {}
    for _ in range(nsec):
        name = d[off:off + 8].rstrip(b'\0').decode('latin-1')
        vsz, va, rsz, raw = struct.unpack_from('<IIII', d, off + 8)
        out[name] = (va, vsz, raw, rsz)
        off += 40
    return pe, out


def demangle(n):
    """FPC's mangling, reduced to something a person can read.

    UNIT_$$_PROC$ARGTYPES        -> Unit.Proc
    UNIT_$_TCLASS_$__METHOD$ARGS -> Unit.TClass.Method

    The unit separator comes BEFORE the name, so the argument signature can
    only be stripped from what follows it."""
    raw = n
    unit = ''
    if '_$$_' in n:
        unit, n = n.split('_$$_', 1)
    elif '_$_' in n:
        unit, n = n.split('_$_', 1)
    n = re.sub(r'_\$__?', '.', n)        # method separator
    n = n.split('$', 1)[0]               # now the signature is safe to drop
    parts = [x for x in ([unit] + n.split('.')) if x]
    if not parts:
        return raw
    return '.'.join(x.title() if x.isupper() else x for x in parts)


def symbols(d, pe, text_index, text_va):
    """start RVA -> a readable name.

    A COFF symbol's Value is the offset within ITS SECTION, not an RVA, so the
    section's VirtualAddress has to be added before it will line up with
    .pdata. Without that the two agree only by coincidence - 918 times out of
    9717 here, which looks enough like success to be missed."""
    psym, nsym = struct.unpack_from('<II', d, pe + 12)
    if not psym or not nsym:
        return {}
    strtab = psym + nsym * 18
    out = {}
    i = 0
    while i < nsym:
        rec = d[psym + 18 * i:psym + 18 * i + 18]
        val, secnum, _typ, cls, aux = struct.unpack_from('<IhHBB', rec, 8)
        if rec[:4] == b'\0\0\0\0':
            o = struct.unpack_from('<I', rec, 4)[0]
            e = d.index(b'\0', strtab + o)
            name = d[strtab + o:e].decode('latin-1')
        else:
            name = rec[:8].rstrip(b'\0').decode('latin-1')
        if secnum == text_index and cls in (2, 3) and val not in out:
            if not name.startswith('.'):
                out[val + text_va] = name
        i += 1 + aux
    return out


def functions(path):
    """name -> sha of that function's bytes."""
    d = open(path, 'rb').read()
    pe, sec = pe_sections(d)
    tva, _tvsz, traw, trsz = sec['.text']
    pva, pvsz, praw, _prsz = sec['.pdata']
    names = symbols(d, pe, list(sec).index('.text') + 1, tva)

    out = {}
    seen = {}
    for i in range(pvsz // 12):
        b, e, _u = struct.unpack_from('<III', d, praw + 12 * i)
        if e <= b:
            continue
        off = traw + (b - tva)
        if off < traw or off + (e - b) > traw + trsz:
            continue
        raw = names.get(b)
        nm = demangle(raw) if raw else 'sub_%08X' % b
        # two symbols can share a body; keep both names distinguishable
        seen[nm] = seen.get(nm, 0) + 1
        if seen[nm] > 1:
            nm = '%s#%d' % (nm, seen[nm])
        out[nm] = hashlib.sha256(d[off:off + (e - b)]).hexdigest()[:16]
    return out


def section_digest(path):
    d = open(path, 'rb').read()
    _pe, sec = pe_sections(d)
    out = {}
    for n in REAL:
        if n in sec:
            _va, _vsz, raw, rsz = sec[n]
            out[n] = hashlib.sha256(d[raw:raw + rsz]).hexdigest()
    return out


def load(path):
    return json.loads(io.open(path, encoding='utf-8').read())


def save(path, obj, flat=False):
    io.open(path, 'w', encoding='utf-8').write(
        json.dumps(obj, indent=0 if flat else 2, sort_keys=True) + chr(10))


def main():
    if not os.path.isfile(EXE):
        print('no src/akuji.exe - build first')
        return 2

    sec_now = section_digest(EXE)

    if '--record' in sys.argv:
        save(SECTIONS, sec_now)
        fn_now = functions(EXE)
        save(FUNCTIONS, fn_now, flat=True)
        print('recorded %d sections and %d function bodies as the baseline'
              % (len(sec_now), len(fn_now)))
        return 0

    if not os.path.isfile(SECTIONS):
        print('no baseline - run with --record')
        return 2

    sec_want = load(SECTIONS)
    moved = sorted(n for n in set(sec_want) | set(sec_now)
                   if sec_want.get(n) != sec_now.get(n))

    if not moved:
        print('same machine code as v1.0 - %d sections match '
              '(debug info is not compared, and does not have to)'
              % len(sec_want))
        return 0

    print('CHANGED: %s' % ', '.join(moved))

    if '--where' in sys.argv and os.path.isfile(FUNCTIONS):
        fn_want = load(FUNCTIONS)
        fn_now = functions(EXE)
        changed = sorted(k for k in fn_want
                         if k in fn_now and fn_want[k] != fn_now[k])
        gone = sorted(set(fn_want) - set(fn_now))
        new = sorted(set(fn_now) - set(fn_want))

        def show(title, names, limit=40):
            if not names:
                return
            print()
            print('%s (%d):' % (title, len(names)))
            for n in names[:limit]:
                print('    %s' % n)
            if len(names) > limit:
                print('    ... and %d more' % (len(names) - limit))

        show('CHANGED - these bodies emit different instructions', changed)
        show('GONE - removed, or the left half of a rename', gone)
        show('NEW - added, or the right half of a rename', new)
    elif '--where' not in sys.argv:
        print('(run again with --where to see which functions)')

    print()
    print('Something moved. If it was a rename or a named constant, that is a')
    print('bug in the edit, not in this tool. If it was a deliberate fidelity')
    print('fix, re-record with --record and say why - notes/v1.0_handover.md.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
