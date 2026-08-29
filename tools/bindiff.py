#!/usr/bin/env python3
"""Diff two akuji.exe builds, and say whether any INSTRUCTION changed.

WHY THIS EXISTS

The binary this project reads is a fan translation. That raises a question the
disassembly alone cannot answer: when a handler does something odd - type 61
accelerating AWAY from the player, the ending percentage coming out a point
low, type 55 multiplying its own velocity every frame - is that the author's
code, or something a translator patched?

A second release answers it. If two builds differ only in string literals and
resources, then every function between them is untouched, and everything read
out of either one is the author's.

WHAT IT FOUND

    English Translated Version 1.1 (D)   502,784 bytes, dated 2020
    akuji_ver101                         502,788 bytes, dated 2003

    1,701 of 502,784 bytes differ - 0.34 percent - and every one of them is a
    PE header field, a string literal, or a resource. DATA, .idata, .rdata and
    .reloc are byte-identical, and not one instruction byte differs.

The identical .reloc is the load-bearing part. Relocations name every absolute
address the loader fixes up, so if a single function had moved, grown, or been
re-targeted, that table would have changed. It did not.

DATA being identical matters nearly as much: all 187 tables --selftest-entities
pins live there, so every one of those numbers is the author's.

The strings that did change, in the game's own address range, are three:

    0x00456692   'Yes       No  '   vs  'Yes         No'
    0x004568B1   ' was recovered!'  vs  '] is discovered!'
    0x004671D2   'Akuji the Demon'  vs  'Akuji Window'

plus the ability-name table at 0x00451E74 ('Fire+', 'Jump++' against 'Fire
Plus', 'Hi-Jumping') and two Windows font names, 'MS Sans Serif' against
Shift-JIS 'MS Gothic'.

WHAT IT DOES NOT GIVE

Both binaries are ENGLISH. ver101 is Do-jin Nyuu's 2003 patch and 1.1 (D) is a
later revision of the same translation of the same game build. So this is
translation versus translation, NOT version history of Buster's own code, and
it cannot show which behaviour the author later considered a bug. That would
need his untranslated original.

USAGE

    python tools/bindiff.py                    the two builds in this repo
    python tools/bindiff.py A.exe B.exe        any two
    python tools/bindiff.py --strict           exit non-zero if a differing run
                                               outside .rsrc is not a string
"""

import os
import struct
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_A = os.path.join(HERE, 'English Translated Version 1.1 (D)', 'akuji.exe')
DEFAULT_B = os.path.join(HERE, 'akuji_ver101', 'akuji.exe')


# --- which bytes belong to a Delphi 3 string literal ------------------------
#
# Two weaker versions of this were wrong first, and both are worth recording
# because they are the obvious things to try.
#
#   * A printability test calls machine code text often enough to be useless.
#   * "Does the whole run fit inside ONE literal" got three of the four real
#     cases wrong, for two separate reasons: the ability-name table is an ARRAY
#     of literals so a run crosses dozens of them, and where the translation
#     SHORTENED a string the run continues past the shorter one into padding.
#
# So mark the literals once, and ask of each differing BYTE whether it is in
# one. Delphi lays a constant down as
#
#     dd  -1          refcount, 0xFFFFFFFF for a constant
#     dd  length
#     db  text..., 0, padded to 4
#
# An implausible length, or text that is not mostly printable, rejects the
# candidate - so a stray 0xFFFFFFFF inside real code cannot manufacture a
# literal and hide a code change behind it.

def literal_map(blob, lo, hi):
    covered = bytearray(len(blob))
    i = lo
    while i < hi - 8:
        if blob[i:i + 4] == b'\xff\xff\xff\xff':
            ln = struct.unpack_from('<i', blob, i + 4)[0]
            if 0 < ln < 4096 and i + 8 + ln <= len(blob):
                txt = blob[i + 8:i + 8 + ln]
                ok = sum(1 for c in txt
                         if c == 0 or 32 <= c < 127 or 0x81 <= c <= 0xFC)
                if ok >= len(txt) * 0.9:
                    end = i + 8 + ln + 1        # the NUL
                    end += (-end) % 4           # and the alignment padding
                    for k in range(i, min(end, len(blob))):
                        covered[k] = 1
                    i = end
                    continue
        i += 1

    # And the OTHER kind. The VCL stores TFont.Name as a ShortString - a length
    # byte then that many characters, no refcount header - so the literal
    # record scan above cannot see it, and the one run this tool could not
    # explain on its first outing was exactly that: 'MS Sans Serif  ' against
    # Shift-JIS 'MS P Gothic', both fifteen bytes behind a 0x0F.
    #
    # CAUTION: this second scan is LOOSE. Any byte 4..64 followed by that many
    # printable bytes is marked, so it could in principle mask a code change
    # that happens to look like a ShortString. It is a convenience for
    # re-running, not the evidence. The evidence is that .reloc and DATA are
    # byte-identical - relocations would have moved if any function had - and
    # that all four CODE runs were read by hand before this was written.
    i = lo
    while i < hi - 1:
        ln = blob[i]
        if 4 <= ln <= 64 and i + 1 + ln <= len(blob):
            txt = blob[i + 1:i + 1 + ln]
            ok = sum(1 for c in txt if 32 <= c < 127 or 0x81 <= c <= 0xFC)
            if ok == len(txt):
                for k in range(i, i + 1 + ln):
                    covered[k] = 1
                i += 1 + ln
                continue
        i += 1
    return covered


def literal_at(blob, off, back=4096):
    """The text of the literal containing off, for reporting."""
    for h in range(off, max(0, off - back) - 1, -1):
        if struct.unpack_from('<i', blob, h)[0] != -1:
            continue
        ln = struct.unpack_from('<i', blob, h + 4)[0]
        if 0 < ln < 4096 and h + 8 <= off < h + 8 + ln + 4:
            return blob[h + 8:h + 8 + ln]
    return b''


def sections(blob):
    pe = struct.unpack_from('<I', blob, 0x3C)[0]
    nsec = struct.unpack_from('<H', blob, pe + 6)[0]
    opt = struct.unpack_from('<H', blob, pe + 20)[0]
    base = struct.unpack_from('<I', blob, pe + 24 + 28)[0]
    out = []
    for i in range(nsec):
        o = pe + 24 + opt + i * 40
        name = blob[o:o + 8].rstrip(b'\0').decode('latin1')
        vsz, va, rsz, ptr = struct.unpack_from('<IIII', blob, o + 8)
        out.append((name, base + va, ptr, rsz))
    return out


def locate(secs, off):
    for name, va, ptr, rsz in secs:
        if ptr <= off < ptr + rsz:
            return name, va + (off - ptr)
    return 'header', None


def main():
    args = [x for x in sys.argv[1:] if not x.startswith('--')]
    strict = '--strict' in sys.argv
    if len(args) >= 2:
        pa, pb = args[0], args[1]
    else:
        pa, pb = DEFAULT_A, DEFAULT_B
    for p in (pa, pb):
        if not os.path.exists(p):
            print('missing: %s' % p)
            return 2

    a = open(pa, 'rb').read()
    b = open(pb, 'rb').read()
    secs = sections(a)
    n = min(len(a), len(b))
    print('%s  %d bytes' % (os.path.basename(os.path.dirname(pa)), len(a)))
    print('%s  %d bytes' % (os.path.basename(os.path.dirname(pb)), len(b)))

    diff = [i for i in range(n) if a[i] != b[i]]
    print('\n%d of %d bytes differ (%.2f%%)'
          % (len(diff), n, 100.0 * len(diff) / n))
    if not diff:
        return 0

    runs = []
    start = prev = diff[0]
    for i in diff[1:]:
        if i - prev > 64:
            runs.append((start, prev))
            start = i
        prev = i
    runs.append((start, prev))

    # Sections that came through untouched are the strongest single fact here,
    # so they are printed even though each is an absence.
    print()
    for name, va, ptr, rsz in secs:
        if rsz == 0:
            continue
        d = sum(1 for i in range(rsz)
                if ptr + i < n and a[ptr + i] != b[ptr + i])
        print('  %-8s %6d of %6d bytes differ%s'
              % (name, d, rsz, '   <- identical' if d == 0 else ''))

    code = [x for x in secs if x[0] == 'CODE'][0]
    cova = literal_map(a, code[2], code[2] + code[3])
    covb = literal_map(b, code[2], code[2] + code[3])

    print('\n%d runs:' % len(runs))
    bad = 0
    for s0, e0 in runs:
        name, va = locate(secs, s0)
        inlit = all(cova[k] and covb[k]
                    for k in range(s0, e0 + 1) if a[k] != b[k])
        kind = 'string' if inlit else 'NOT A STRING'
        if not inlit and name not in ('header', '.rsrc'):
            bad += 1
        print('  file 0x%06X..0x%06X  %5d bytes  %-8s %s  %s'
              % (s0, e0, e0 - s0 + 1, name,
                 ('VA 0x%08X' % va) if va else '          ', kind))
        if inlit:
            print('        A: %r' % literal_at(a, s0)[:56])
            print('        B: %r' % literal_at(b, s0)[:56])

    print()
    if bad == 0:
        print('every differing run outside the PE header and .rsrc is a string '
              'literal - no instruction byte differs between the two builds')
    else:
        print('%d run(s) outside .rsrc are NOT string literals - something '
              'other than text changed' % bad)
    return 1 if (strict and bad) else 0


if __name__ == '__main__':
    sys.exit(main())
