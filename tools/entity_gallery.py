#!/usr/bin/env python3
"""Build a GAME DIRECTORY containing a room with one of every entity type.

WHY THIS EXISTS

The reconstruction calls most entity handlers EntityUpdate_TypeNN, which is a
number rather than a name. Putting a name to each one needs somebody to SEE
the creature next to its type number, and the fastest way to do that is a room
containing one of each.

WHY IT IS A TOOL AND NOT A GAME MODE

CLAUDE.md: the Pascal must be a faithful reproduction, and must not carry code
the original does not have. A gallery drawn by the game would be exactly that,
however carefully it was gated behind a flag. So nothing here touches src/ -
this writes a modified copy of the game DATA and the unmodified akuji.exe is
pointed at it. The binary that renders the gallery is the same binary that
renders the game.

WHAT IT WRITES

A copy of the game directory with one stage's ev*.dat replaced by a row of
placements, one per entity type, one tile apart:

    0,0000,0000,<x>,<y>,00NN-*,*

  opcode 0        touch, so the entity is spawned when the camera reaches it
                  and its script does not run on its own. Opcode 4 would spawn
                  it anywhere but also fire Event_Begin, which is not wanted.
  flags 0000      no required or forbidding progress flag, so it always places
  ParamA 00NN-*   type NN, ParamA kind '*', which Events_SpawnNearCamera reads
                  as "carries nothing" - no variant, no state, no block A
  ParamB *        a real value in the shipped data; the entity has no script

The row is placed at a tileY the chosen stage ALREADY uses, so the ground
under it is known to be real rather than guessed at.

TYPES

The 45 the shipped stages actually place, from tools/entity_usage.py. The rest
are spawned by other entities (children, effects, debris) and would show
nothing standing on their own.

USAGE

    python tools/entity_gallery.py --install "English Translated Version 1.1 (D)"
    src/akuji.exe                       # run normally; the row is in every room
    python tools/entity_gallery.py --restore "English Translated Version 1.1 (D)"

WHY IT INSTALLS IN PLACE

The game does NOT take a data directory on the command line. FindGameData
scans fixed paths relative to the executable; ParamStr(1) is read by the
--selftest modes only. So writing a modified copy elsewhere and pointing the
game at it does nothing - the copy is never loaded. It has to go into the
directory the game already finds.

Every ev*.dat is backed up to ev*.dat.orig on the first install and put back
by --restore, so this is reversible and never destroys the shipped data.

WHY EVERY STAGE

A new game leaves Settings.CurrentStage at 0 and an event script decides where
you actually end up, so predicting the room is unreliable. Appending the row
to every stage means it is wherever you are. The stage's own events are KEPT -
the row is appended, not substituted - so the game still plays normally.
"""

import os
import sys
from collections import Counter

# The types the shipped stages place - tools/entity_usage.py, 45 of them.
TYPES = [14, 15, 16, 20, 21, 22, 23, 24, 25, 27, 29, 30, 31, 37, 38, 40, 41,
         42, 43, 45, 46, 47, 49, 50, 51, 52, 54, 56, 58, 59, 60, 61, 62, 63,
         64, 65, 66, 67, 69, 70, 71, 73, 76, 77, 80]

START_X = 6          # leave the player's spawn clear
STEP_X = 1           # one tile apart; the screen is 10 tiles wide


def ev_files(gamedir):
    d = os.path.join(gamedir, 'data')
    return sorted(f for f in os.listdir(d)
                  if f.startswith('ev') and f.endswith('.dat'))


def install(gamedir):
    d = os.path.join(gamedir, 'data')
    n = 0
    for name in ev_files(gamedir):
        path = os.path.join(d, name)
        orig = path + '.orig'
        if not os.path.isfile(orig):
            with open(path, 'rb') as fh:
                open(orig, 'wb').write(fh.read())
        # always rebuild from the pristine copy, so re-installing is idempotent
        base = open(orig, encoding='latin-1').read().rstrip(chr(10))

        ys = Counter()
        for line in base.split(chr(10)):
            f = [c.strip() for c in line.split(',')]
            if len(f) >= 5 and f[4].isdigit():
                ys[int(f[4])] += 1
        row_y = ys.most_common(1)[0][0] if ys else 8

        rows = ['0,0000,0000,%04d,%04d,%04d-*,*' % (START_X + i * STEP_X,
                                                    row_y, t)
                for i, t in enumerate(TYPES)]
        out = (base + chr(10) if base else '') + chr(10).join(rows) + chr(10)
        open(path, 'w', encoding='latin-1').write(out)
        n += 1
    print('installed the gallery row into %d stages of %s' % (n, gamedir))
    print('originals saved beside them as ev*.dat.orig')
    print()
    print('  tile x   type')
    for i, t in enumerate(TYPES):
        print('  %6d   %d' % (START_X + i * STEP_X, t))


def restore(gamedir):
    d = os.path.join(gamedir, 'data')
    n = 0
    for name in ev_files(gamedir):
        path = os.path.join(d, name)
        orig = path + '.orig'
        if os.path.isfile(orig):
            with open(orig, 'rb') as fh:
                open(path, 'wb').write(fh.read())
            os.remove(orig)
            n += 1
    print('restored %d stages of %s' % (n, gamedir))


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ('--install', '--restore'):
        print(__doc__)
        return 2
    gamedir = sys.argv[2]
    if not os.path.isdir(os.path.join(gamedir, 'data')):
        print('no data/ under %s' % gamedir)
        return 2
    (install if sys.argv[1] == '--install' else restore)(gamedir)
    return 0


if __name__ == '__main__':
    sys.exit(main())
