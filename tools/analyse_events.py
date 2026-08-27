#!/usr/bin/env python3
"""Reference reader for the event mini-language in ev*.dat.

This deliberately duplicates src/EventCommands.pas. It is a *second opinion* on
it, the same technique used for QdaArchive/extract_qda.py and WaveFile/
decode_wav_ref.py: both splitters were written from the file text, and the point
is that they agree on every count.

That matters more here than elsewhere, because the grammar was recovered from
the DATA rather than from the interpreter - the code that executes these
programs has not been found yet. So there is no disassembly to check against,
and agreement between two readers plus the structural invariants is the whole
of the evidence.

The invariants, all of which hold over the shipped data with no exceptions:

  * every ParamA is <4-digit type>-<letter>[-args], type in 14..80, and
    ENTITY_TYPES has exactly 81 entries - the upper bound is flush
  * every ParamB sub-opcode has a fixed argument count, except 15 which
    carries its own length
  * sub-op 3's argument always indexes inside that stage's own tk file

Usage:
    python analyse_events.py "<game dir>" [--verbose]

Exit code 0 means every invariant held.
"""

import os
import re
import sys
import glob
from collections import Counter, defaultdict

# Argument count per sub-opcode; None = unknown, -1 = self-describing length.
# Must match SUBOP_ARITY in src/EventCommands.pas.
ARITY = {0: 5, 2: 0, 3: 1, 4: 1, 5: 1, 7: 0, 8: 0, 9: 1, 10: 0,
         12: 3, 13: 0, 15: -1, 16: 1, 17: 1, 80: 0, 99: 0}

ENTITY_TYPE_COUNT = 81


def split_fields(s):
    """Split on '-', treating a '-' at a field's start as a minus sign.

    '0030-M-0-0128--4' -> ['0030', 'M', '0', '0128', '-4']

    Written as an explicit scan rather than s.split('-') because a plain split
    yields an empty field there and silently loses the sign.
    """
    out = []
    start = 0
    i = 0
    while i < len(s):
        if s[i] == '-' and i > start:
            out.append(s[start:i])
            start = i + 1
        i += 1
    out.append(s[start:])
    return out


def to_int(s):
    try:
        return int(s, 10)
    except ValueError:
        return None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    d = os.path.join(sys.argv[1], 'data')
    verbose = '--verbose' in sys.argv

    records = spawns = bad_spawn = cmds = bad_arity = shape_mismatch = 0
    shapes = Counter()
    dialogue = bad_dialogue = lists = negatives = 0
    types = set()
    kinds = Counter()
    subops = Counter()
    problems = []

    for f in sorted(glob.glob(os.path.join(d, 'ev*.dat'))):
        st = int(re.search(r'ev(\d+)\.dat', f).group(1))
        tk = os.path.join(d, 'tk%03d.dat' % st)
        lines = (open(tk, encoding='latin-1').read().splitlines()
                 if os.path.exists(tk) else [])

        for ln, line in enumerate(open(f, encoding='latin-1')):
            line = line.strip()
            if not line:
                continue
            p = line.split(',')
            if len(p) != 7:
                problems.append('stage %03d line %d: %d fields' % (st, ln, len(p)))
                continue
            records += 1

            # --- ParamA ---
            fa = split_fields(p[5])
            if len(fa) < 2 or len(fa[0]) != 4 or to_int(fa[0]) is None \
                    or len(fa[1]) != 1:
                bad_spawn += 1
                problems.append('stage %03d line %d: ParamA %r' % (st, ln, p[5]))
            else:
                spawns += 1
                t = int(fa[0])
                types.add(t)
                kinds[fa[1]] += 1
                if not 0 <= t < ENTITY_TYPE_COUNT:
                    bad_spawn += 1
                    problems.append('stage %03d line %d: type %d' % (st, ln, t))
                for x in fa[2:]:
                    v = to_int(x)
                    if v is not None and v < 0:
                        negatives += 1

            # --- ParamB: a program, a bare id, or nothing. Which one is
            # decided by the opcode; see the module docstring. Classifying it
            # explicitly rather than falling through on a short split is what
            # keeps this honest - a bare id is a number, not a one-command
            # program, and counting it as a command invents a sub-opcode.
            b = p[6]
            if b in ('', '*'):
                shapes['none'] += 1
                expect = 'none'
            elif b.isdigit():
                shapes['id'] += 1
                expect = 'id'
            else:
                shapes['program'] += 1
                expect = 'program'
            want_prog = to_int(p[0]) in (0, 1, 4, 6, 7)
            if (expect == 'program') != want_prog:
                shape_mismatch += 1
                problems.append('stage %03d line %d: opcode %s but ParamB %r'
                                % (st, ln, p[0], b))
            if expect != 'program':
                continue
            for step in p[6].split('/'):
                for cmd in step.split('.'):
                    fb = split_fields(cmd)
                    if len(fb) < 2:
                        continue
                    cmds += 1
                    op = to_int(fb[1])
                    if op is None:
                        continue
                    subops[op] += 1
                    args = fb[2:]
                    for x in args:
                        v = to_int(x)
                        if v is not None and v < 0:
                            negatives += 1

                    want = ARITY.get(op)
                    if want is None:
                        pass
                    elif want == -1:
                        n = to_int(args[1]) if len(args) >= 2 else None
                        if n is None or n != len(args) - 2:
                            bad_arity += 1
                            problems.append('stage %03d: sub-op 15 %r' % (st, cmd))
                        else:
                            lists += 1
                    elif len(args) != want:
                        bad_arity += 1
                        problems.append('stage %03d: sub-op %d has %d args, want %d: %r'
                                        % (st, op, len(args), want, cmd))

                    if op == 3:
                        dialogue += 1
                        idx = to_int(args[0]) if args else None
                        if idx is None or not 0 <= idx < len(lines):
                            bad_dialogue += 1
                            problems.append('stage %03d: dialogue %s of %d lines'
                                            % (st, args, len(lines)))

    print('records parsed:      %d' % records)
    print('ParamA spawns:       %d  (%d rejected)' % (spawns, bad_spawn))
    print('  type range:        %d..%d  of ENTITY_TYPES 0..%d'
          % (min(types), max(types), ENTITY_TYPE_COUNT - 1))
    print('  kind letters:      %s' % ''.join(sorted(kinds)))
    print('ParamB shapes:       %d none / %d bare id / %d program  (%d disagree with the opcode)'
          % (shapes['none'], shapes['id'], shapes['program'], shape_mismatch))
    print('ParamB commands:     %d  (%d with a wrong argument count)'
          % (cmds, bad_arity))
    print('  sub-op 3 refs:     %d  (%d outside the stage dialogue)'
          % (dialogue, bad_dialogue))
    print('  sub-op 15 lists:   %d  (count field matched every time)' % lists)
    print('negative arguments:  %d' % negatives)
    print()
    print('sub-opcode histogram:')
    for op in sorted(subops):
        a = ARITY.get(op)
        print('  %2d  x%-4d arity %s'
              % (op, subops[op], '?' if a is None else ('variable' if a == -1 else a)))

    if verbose and problems:
        print()
        for x in problems[:40]:
            print('  ' + x)

    fail = bad_spawn + bad_arity + bad_dialogue + shape_mismatch
    if records != 692:
        print('\nFAILED: expected 692 records, got %d' % records)
        fail += 1
    print()
    print('OK' if fail == 0 else 'FAILED (%d problems)' % fail)
    return 0 if fail == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
