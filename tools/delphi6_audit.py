#!/usr/bin/env python3
"""What would stop this compiling under Borland Delphi 6.

    python tools/delphi6_audit.py [--detail]

WHY

The target changed. The goal is no longer "a Free Pascal program that plays
like the original" but "a Delphi 6 project for x86 Win32 that compiles to a
near-replica of akuji.exe" - which is a much stronger claim and a much better
one, because the original was built by Delphi 3 and a Delphi 6 build shares its
compiler lineage, its calling convention, its RTL shape and its word size.

That also means every FPC-and-Lazarus-ism in the tree is now a defect rather
than a convenience. This finds them.

WHAT IT KNOWS

Delphi 6 shipped in 2001. Everything below postdates it, and each pattern here
is something the compiler will reject outright rather than warn about:

    {$MODE ...}          an FPC directive; Delphi has no modes
    Exit(value)          Delphi 2009
    for .. in ..         Delphi 2005
    TBytes               Delphi 2007
    StrictDelimiter      Delphi 2006
    strict private       Delphi 2005
    inline;              Delphi 2005
    generics             Delphi 2009
    QWord, PtrInt, ...   FPC types with no Delphi spelling
    SarLongint and kin   FPC intrinsics
    GetTickCount64       a Vista API, and not in the Delphi 6 RTL either
    LCL units            Lazarus only - Delphi has the VCL

It is a FLOOR, not a ceiling: a clean run does not mean the project compiles,
only that none of these specific things are in the way. The real blockers that
no regex can see are the component layer - DDDDComponent and friends stand in
for a DirectX suite that a Delphi 6 build would want to use directly - and the
form resource, which is a Lazarus .lfm where Delphi wants a .dfm.
"""

import argparse
import glob
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# pattern, what it is, what Delphi 6 wants instead
RULES = [
    (r'\{\$MODE\b',            'FPC mode directive',
                               'delete; Delphi has no modes'),
    (r'\{\$modeswitch\b',      'FPC modeswitch',
                               'delete'),
    (r'\bExit\s*\(',           'Exit(value)',
                               'Result := x; Exit;'),
    (r'\bfor\s+\w+\s+in\b',    'for..in',
                               'an index loop'),
    (r'\bTBytes\b',            'TBytes',
                               'array of Byte'),
    (r'\bStrictDelimiter\b',   'TStringList.StrictDelimiter',
                               'split by hand'),
    (r'\bstrict\s+(private|protected)\b', 'strict visibility',
                               'private / protected'),
    (r'\)\s*;\s*inline\s*;',   'inline directive',
                               'drop it'),
    (r'\b(generic|specialize)\b', 'generics',
                               'a concrete type'),
    (r'\b(QWord|PtrInt|PtrUInt|SizeInt|SizeUInt|ValReal|CodePointer)\b',
                               'FPC-only type',
                               'Int64 / Integer / Pointer'),
    (r'\b(SarLongint|SarInt64|SarSmallint|RolDWord|RorDWord|BsfDWord|BsrDWord)\b',
                               'FPC intrinsic',
                               'write the arithmetic out'),
    (r'\bGetTickCount64\b',    'GetTickCount64',
                               'timeGetTime - which is what the original uses'),
    (r'\b(LCLType|LCLIntf|LCLProc|LazUTF8|LazFileUtils|FileUtil|Interfaces)\b',
                               'Lazarus unit',
                               'the VCL equivalent'),
    (r'\bDefault\s*\(',        'Default(T)',
                               'zero it by hand'),
    (r'\bTThread\.\w+\s*:=',   'modern TThread property',
                               'check against Delphi 6 TThread'),
]

SKIP_DIRS = {'lib', 'backup'}


def sources():
    for pat in ('src/*.pas', 'src/*.lpr', 'src/*.inc'):
        for f in sorted(glob.glob(os.path.join(REPO, pat))):
            if os.path.basename(os.path.dirname(f)) in SKIP_DIRS:
                continue
            yield f


def strip_comments(text):
    """Pascal { } and (* *) and // - so a comment naming a construct does not
    count as using it. Two checks in this project have already failed that
    way."""
    # A COMPILER DIRECTIVE IS NOT A COMMENT. {$MODE DELPHI} looks exactly like
    # one, so the first version of this stripped every directive in the tree and
    # reported zero of them - a false negative in a checker, which is worse than
    # no checker. Directives are kept; only real comments go.
    text = re.sub(r'\{(?!\$)[^}]*\}', ' ', text)
    text = re.sub(r'\(\*.*?\*\)', ' ', text, flags=re.S)
    text = re.sub(r'//[^\n]*', ' ', text)
    return text


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--detail', action='store_true',
                    help='list every hit with its line, not just the totals')
    args = ap.parse_args()

    counts = {}
    hits = []
    files = 0
    for f in sources():
        files += 1
        raw = open(f, encoding='utf-8', errors='replace').read()
        text = strip_comments(raw)
        lines = text.split('\n')
        rawlines = raw.split('\n')
        for pat, what, instead in RULES:
            rx = re.compile(pat, re.I)
            for n, line in enumerate(lines, 1):
                if rx.search(line):
                    counts[what] = counts.get(what, 0) + 1
                    hits.append((what, os.path.basename(f), n,
                                 rawlines[n - 1].strip()[:70], instead))

    print('%d source files scanned\n' % files)
    if not counts:
        print('nothing here that Delphi 6 rejects outright')
        return 0

    width = max(len(k) for k in counts)
    for what, instead in [(w, i) for _, w, i in RULES]:
        if what in counts:
            print('  %-*s %4d   -> %s' % (width, what, counts[what], instead))
    print('\n  %-*s %4d' % (width, 'TOTAL', sum(counts.values())))

    if args.detail:
        print()
        for what, fn, n, line, _ in hits:
            print('  %-28s %s:%d  %s' % (what, fn, n, line))

    print('\nA FLOOR, NOT A CEILING. A clean run means none of these specific')
    print('things are in the way, not that the project compiles. The blockers')
    print('no regex can see are the component layer standing in for a DirectX')
    print('suite, and the Lazarus .lfm form resource where Delphi wants .dfm.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
