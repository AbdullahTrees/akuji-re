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

    python tools/entity_gallery.py "English Translated Version 1.1 (D)" out/gallery
    src/akuji.exe out/gallery

Start a new game and walk right. The legend below tells you which tile holds
which type; the order is also simply ascending, so counting works too.
"""

import os
import shutil
import sys
from collections import Counter

# The types the shipped stages place - tools/entity_usage.py, 45 of them.
TYPES = [14, 15, 16, 20, 21, 22, 23, 24, 25, 27, 29, 30, 31, 37, 38, 40, 41,
         42, 43, 45, 46, 47, 49, 50, 51, 52, 54, 56, 58, 59, 60, 61, 62, 63,
         64, 65, 66, 67, 69, 70, 71, 73, 76, 77, 80]

START_X = 6          # leave the player's spawn clear
STEP_X = 1           # one tile apart; the screen is 10 tiles wide


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    stage = int(sys.argv[3]) if len(sys.argv) > 3 else 1

    ev = os.path.join(src, 'data', 'ev%03d.dat' % stage)
    if not os.path.isfile(ev):
        print('no such stage file: %s' % ev)
        return 2

    # Reuse a row the stage already puts entities on, so the floor is real.
    ys = Counter()
    for line in open(ev, encoding='latin-1'):
        f = [c.strip() for c in line.split(',')]
        if len(f) >= 5 and f[4].isdigit():
            ys[int(f[4])] += 1
    if not ys:
        print('stage %d places nothing; pick another' % stage)
        return 2
    row_y = ys.most_common(1)[0][0]

    if os.path.isdir(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst)

    out = []
    legend = []
    for i, t in enumerate(TYPES):
        x = START_X + i * STEP_X
        out.append('0,0000,0000,%04d,%04d,%04d-*,*' % (x, row_y, t))
        legend.append((x, row_y, t))

    with open(os.path.join(dst, 'data', 'ev%03d.dat' % stage), 'w',
              encoding='latin-1') as fh:
        fh.write('\n'.join(out) + '\n')

    print('gallery written: %s' % dst)
    print('stage %d, row y=%d, %d types from tile x=%d'
          % (stage, row_y, len(TYPES), START_X))
    print()
    print('  run:  src/akuji.exe "%s"' % dst)
    print('  then: new game, walk right')
    print()
    print('  tile x   type')
    for x, y, t in legend:
        print('  %6d   %d' % (x, t))
    return 0


if __name__ == '__main__':
    sys.exit(main())
