#!/usr/bin/env python3
"""Drive the differential test: run the ORIGINAL, then diff the reconstruction.

    python tools/emudiff.py [--gamedir DIR] [--keep] [case-set ...]

Three steps, all of which this handles:

  1. build a spec of calls into akuji.exe
  2. run ghidra_scripts/EmuDiff.java under analyzeHeadless, which executes the
     original's machine code for each and appends its answer
  3. run `akuji.exe --emudiff <that file>`, which recomputes each case with the
     reconstruction and requires the two to agree

WHY IT LOOKS LIKE THIS

The spec and the results are ONE file. The emulator echoes each input line with
its answer appended, so the file the Pascal reads still carries everything the
case was built from - which means the two halves cannot drift out of step, and
a failing case can be re-run by hand from its own line.

Fields on a CASE line: eax=, edx=, ecx= are the register arguments; stk= is any
further ones; mem=ADDR:HEX places memory first (BSS is not in the PE, so
anything reached through a global has to be written); f.* carries values the
Pascal side needs to rebuild a record, and the emulator ignores them.

WHAT IT CANNOT DO. The emulator models the instruction set, not the process -
no Windows, no imports, no VCL - so a function that calls the RTL faults. That
is reported, never skipped silently. It is also why the case sets below are
leaf routines and arithmetic: that is both what the emulator can run and where
the reconstruction's risk actually is.
"""

import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GHIDRA = r'C:\Users\Abdullah\Documents\ghidra_12.0.4_PUBLIC\support\analyzeHeadless.bat'

# Where the game keeps things, from notes/function_map.md.
P_LAYERINFO = 0x00483BF4          # the layer array itself, stride 0x20
ENTITY_AT = 0x60000000            # scratch: somewhere to put a TEntity
ENTITY_INTS = 0x41


def ints(vals):
    return ''.join('%08x' % (v & 0xFFFFFFFF) for v in vals)


def le(vals):
    """hex of little-endian int32s, which is what mem= wants"""
    return ''.join(struct.pack('<i', v).hex() for v in vals)


def layer_mem(origin_x=0, origin_y=0, dx=0, dy=0, tw=32, th=32, mx=30, my=24):
    """TLayerInfo: OriginX OriginY DeltaX DeltaY TileW TileH MapTilesX MapTilesY"""
    return 'mem=0x%X:%s' % (P_LAYERINFO,
                            le([origin_x, origin_y, dx, dy, tw, th, mx, my]))


def entity_mem(**fields):
    """A whole TEntity, zeroed except for the int indices given."""
    raw = [0] * ENTITY_INTS
    for k, v in fields.items():
        raw[int(k[1:])] = v            # keys look like i30
    return 'mem=0x%X:%s' % (ENTITY_AT, le(raw))


# --------------------------------------------------------------------------
# case sets
# --------------------------------------------------------------------------

def cases_angle():
    """Angle_Between @ 0x4513E0 vs Directions.AngleBetween. Pure integer."""
    out = ['# Angle_Between(X1,Y1,X2,Y2) - EAX,EDX,ECX then one stack arg']
    span = (-100, -40, -13, -3, -1, 0, 1, 3, 13, 40, 100)
    for dx in span:
        for dy in span:
            out.append('CASE ang_%d_%d 0x4513E0 eax=0 edx=0 ecx=%d stk=%d'
                       % (dx, dy, dx, dy))
    return out


def cases_compare():
    """The three-way compare at 0x45114C. Trivial, but it pins the harness."""
    out = ['# Compare(a,b) @ 0x45114C']
    for a in (-5, -1, 0, 1, 5):
        for b in (-5, -1, 0, 1, 5):
            out.append('CASE cmp_%d_%d 0x45114C eax=%d edx=%d' % (a, b, a, b))
    return out


def cases_edgedist():
    """Entity_TileEdgeDistX/Y vs Entities.TileEdgeDistX/Y.

    Two register arguments - the entity pointer and the delta - and it reaches
    the layer through a global, so both the entity and the layer have to be
    placed in memory first.

    DELTA ZERO IS DELIBERATELY EXCLUDED. The original initialises its result to
    the entity POINTER and only overwrites it in the two signed branches, so a
    zero delta returns an address cast to an integer. Entities.pas returns 0
    instead and says so. Including it here would report a disagreement that is
    a recorded decision rather than a defect - so it is left out on purpose,
    and this comment is why.
    """
    out = ['# Entity_TileEdgeDistX/Y - entity in EAX, delta in EDX']
    lay = layer_mem(origin_x=0x10000 + 7, origin_y=0x10000 + 19)
    for pos in (0x10000, 0x10000 + 100, 0x10000 + 517, 0x10000 - 40):
        for ext in (0, 2, 20, 33):
            for ofs in (0, 3):
                for delta in (-64, -33, -1, 1, 33, 64):
                    ent = entity_mem(i30=pos, i31=pos, i38=ext, i39=ext,
                                     i40=ofs, i41=ofs)
                    tag = 'tedx_%d_%d_%d_%d' % (pos & 0xFFFF, ext, ofs, delta)
                    out.append(
                        'CASE %s 0x457150 eax=0x%X edx=%d %s %s '
                        'f.pos=%d f.ext=%d f.ofs=%d f.delta=%d '
                        'f.ox=%d f.oy=%d f.tile=32'
                        % (tag, ENTITY_AT, delta, lay, ent,
                           pos, ext, ofs, delta, 0x10000 + 7, 0x10000 + 19))
                    out.append(
                        'CASE %s 0x457228 eax=0x%X edx=%d %s %s '
                        'f.pos=%d f.ext=%d f.ofs=%d f.delta=%d '
                        'f.ox=%d f.oy=%d f.tile=32'
                        % (tag.replace('tedx', 'tedy'), ENTITY_AT, delta,
                           lay, ent, pos, ext, ofs, delta,
                           0x10000 + 7, 0x10000 + 19))
    return out


SETS = {
    'compare': cases_compare,
    'angle': cases_angle,
    'edgedist': cases_edgedist,
}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('sets', nargs='*', default=list(SETS),
                    help='which case sets to run (default: all)')
    ap.add_argument('--gamedir',
                    default=os.path.join(REPO, 'English Translated Version 1.1 (D)'))
    ap.add_argument('--keep', action='store_true',
                    help='keep the work directory')
    args = ap.parse_args()

    for s in args.sets:
        if s not in SETS:
            print('unknown case set %r; have: %s' % (s, ', '.join(SETS)))
            return 2

    work = tempfile.mkdtemp(prefix='emudiff_')
    try:
        exe = os.path.join(args.gamedir, 'akuji.exe')
        if not os.path.exists(exe):
            print('no akuji.exe under %s' % args.gamedir)
            return 2
        # A path with spaces upsets analyzeHeadless; copy it somewhere plain.
        staged = os.path.join(work, 'orig_akuji.exe')
        shutil.copy(exe, staged)

        lines = []
        for s in args.sets:
            lines += SETS[s]()
        spec = os.path.join(work, 'spec.txt')
        with open(spec, 'w', newline='\n') as fh:
            fh.write('\n'.join(lines) + '\n')
        ncase = sum(1 for l in lines if l.startswith('CASE'))
        print('%d cases across %d set(s)' % (ncase, len(args.sets)))

        out = os.path.join(work, 'out.txt')
        proj = os.path.join(work, 'proj')
        os.makedirs(proj, exist_ok=True)
        cmd = [GHIDRA, proj, 'EmuDiff', '-import', staged, '-noanalysis',
               '-scriptPath', os.path.join(REPO, 'ghidra_scripts'),
               '-postScript', 'EmuDiff.java', spec, out, '-deleteProject']
        r = subprocess.run(cmd, capture_output=True, text=True)
        for line in r.stdout.splitlines():
            if 'EmuDiff:' in line or 'ERROR' in line:
                print('  ' + line.split('> ', 1)[-1].strip())
        if not os.path.exists(out):
            print('the emulator produced no output')
            print(r.stdout[-3000:])
            return 1

        rec = subprocess.run([os.path.join(REPO, 'src', 'akuji.exe'),
                              '--emudiff', out], capture_output=True, text=True)
        log = os.path.join(REPO, 'src', 'selftest.log')
        if os.path.exists(log):
            print()
            print(open(log, encoding='utf-8', errors='replace').read().strip())
        return rec.returncode
    finally:
        if args.keep:
            print('\nwork kept at %s' % work)
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
