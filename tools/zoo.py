#!/usr/bin/env python3
"""Replace stage 1 with a ZOO: every entity type caged, labelled by a sign.

WHY A ZOO AND NOT A ROW

An earlier attempt appended entities to every shipped stage, which was far too
blunt. This touches exactly three files, backs each up first, and --restore
puts them back:

    map/001.map        the starting room's tiles
    data/ev001.dat     its entity and sign placements
    data/tk001.dat     its message text

Nothing in src/ changes. CLAUDE.md keeps the Pascal a faithful reproduction,
so the zoo is DATA the unmodified game loads - the binary rendering it is the
same binary that renders the game.

THE LAYOUT

One long corridor. Above it, a row of sealed cells four tiles apart, each
holding one entity type. Below each cell, a sign.

    row 0        border
    rows 1-4     cell interior, the creature stands on the cell floor
    row 5        CELL FLOOR - solid, and what keeps the creature off you
    rows 6-9     the corridor you walk in
    row 10       corridor floor
    rows 11-13   fill

Walk right, read each sign with the button, look at the cage above it.

TILES

Stage 1 is terrain 1, whose solid threshold is 0x32 - ids >= 50 are solid,
below that you walk through. Both values are taken from the shipped map so the
room looks like the game: 97 is its commonest wall and 1 its commonest air.

SIGNS

A sign is type 16 with opcode 1 (touch+button) and a ParamB script of
`0000-03-NNNN`, sub-op 3 being DIALOGUE and NNNN the line index into
tk001.dat. That is exactly the shape of the shipped signs, e.g.
`1,0000,0000,0004,0017,0016-*,0000-03-0000`.

WHAT WILL ESCAPE

The cage is tiles, so anything that ignores tiles ignores the cage. Type 51
steers at the player through terrain, and the flyers drift. That is worth
knowing rather than worth fixing - it identifies them as surely as the sign
does.

USAGE

    python tools/zoo.py --install "English Translated Version 1.1 (D)"
    src/akuji.exe
    python tools/zoo.py --restore "English Translated Version 1.1 (D)"
"""

import os
import struct
import sys

# WHICH TYPES A SET CAN SHOW. data/sprNNN.dat is per sprite set, and a frame
# in it names a surface INDEX, so a type placed under the wrong set indexes
# into a sheet that does not hold its art and draws as whatever is at that
# index. That is why every boss looked like type 31 when the whole roster was
# caged under stage 1's set: 31 is in set 1 and they are not.
#
# So the zoo is per sprite set, and the set is chosen by rewriting stage 1's
# row in data/stage.dat - where the surface and sprite columns are equal in
# every shipped row, so both move together.
#
# Derived by tools/zoo.py --sets from the shipped stage.dat and ev*.dat: for
# each set, the types that any stage using that set actually places.
# For each sprite set: the types some stage using it actually places, plus the
# TERRAIN and the two tile ids to build the room out of.
#
# The tiles cannot be fixed. Surface index 6 is bg00N.bmp, a DIFFERENT sheet
# per set, so ids 97/1 - the commonest wall and air of stage 1's map - draw as
# something else entirely under any other set. Each row's wall and air are the
# commonest solid and non-solid tile of the largest shipped map using that set,
# judged against that terrain's own threshold, so every room looks like a room
# the game actually ships.
#
# terrain matters twice: it sets the solid threshold the wall has to clear, and
# Terrain_Configure animates tiles for terrains 1..4 by hard-coded id.
SETS = {
    #      types                                            terr wall air
    0: ([14],                                                  1,  97,  1),
    1: ([14, 16, 21, 22, 24, 25, 27, 29, 30, 31, 37],          1,  97,  1),
    2: ([14, 15, 16, 20, 21, 23, 24, 25, 27, 29, 30, 37, 38,
         40, 41, 42, 43],                                      2,  81,  0),
    3: ([14, 15, 16, 20, 21, 22, 24, 25, 27, 29, 37, 43, 45,
         46, 47, 49, 50, 51, 54],                              3,  88,  0),
    4: ([14, 16, 20, 23, 24, 25, 27, 29, 37, 43, 45, 47, 52,
         56, 58, 59, 60, 61, 64],                              4,  81,  0),
    5: ([14, 15, 16, 20, 21, 22, 24, 25, 27, 29, 40, 43, 62,
         63, 64, 65],                                          5,  84,  0),
    6: ([14, 16, 20, 21, 22, 24, 25, 27, 38, 43, 58, 66, 69,
         70, 76],                                              6,  81,  0),
    7: ([20, 25, 73],                                          6,  81,  0),
    8: ([14, 15, 16, 20, 24, 25, 27, 43, 62, 63, 65, 67, 71],  8,  78,  0),
    9: ([25, 37, 77, 80],                                      9,  88,  0),
}

TILE_W = TILE_H = 32
SHEET_C = SHEET_R = 10

PITCH = 4          # 3-tile cell + 1-tile divider
LEFT = 6           # cages start here; the spawn shaft is at tile 3
SPAWN_X = 3        # DEFAULT_SPAWN_X is 0x60 = 96px = tile 3

# THE HEIGHT AND THE ROWS ARE NOT ARBITRARY. A new game starts with
# PlayerState.ScrollY = DEFAULT_SCROLL_Y = 0x1C0 = 448 pixels = tile 14, and
# Stage_Begin sets the camera straight from it with no clamp, so row 14 is
# where the screen opens and the exhibit has to be there.
#
# Everything is one tile high and stacked, so a creature sits directly above
# the player's head with a single floor tile between them:
#
#   14  cage ceiling
#   15  THE CREATURE
#   16  cage floor - the only thing keeping it off you
#   17  the corridor you walk, and the signs
#   18  corridor floor
H = 24
CAGE_CEIL_Y = 14
ENTITY_Y = 15
CELL_FLOOR_Y = 16
CORRIDOR_Y = 17
CORRIDOR_FLOOR_Y = 18
SIGN_Y = CORRIDOR_Y

TARGETS = ('map/001.map', 'data/ev001.dat', 'data/tk001.dat',
           'data/stage.dat')


def set_stage1_sets(gamedir, sprite_set, terrain):
    """Point stage 1 at another surface/sprite set and terrain.

    Surface and sprite are equal in every shipped row and have to move
    together: a sprite frame names a surface INDEX, so the two files are only
    meaningful as a pair. Terrain is the last column."""
    p = os.path.join(gamedir, 'data', 'stage.dat')
    lines = open(p, encoding='latin-1').read().splitlines()
    f = lines[1].split(',')
    tab = chr(9)
    f[0] = '%d' % sprite_set
    f[1] = tab + '%d' % sprite_set
    f[15] = tab + '%d' % terrain
    lines[1] = ','.join(f)
    nl = chr(10)
    with open(p, 'w', encoding='latin-1', newline=nl) as fh:
        fh.write(nl.join(lines) + nl)


def build_map(width, types, wall, air):
    t = [wall] * (width * H)

    def put(x, y, v):
        if 0 <= x < width and 0 <= y < H:
            t[y * width + x] = v

    # carve the two one-tile rows out of solid rock
    for x in range(1, width - 1):
        put(x, ENTITY_Y, air)
        put(x, CORRIDOR_Y, air)

    # a divider between neighbouring cages, in the creature's row only, so the
    # corridor below stays open end to end
    for i in range(len(types) + 1):
        put(LEFT + i * PITCH - 1, ENTITY_Y, wall)

    # the spawn shaft: the player appears at tile 3 row 3 and drops to the
    # corridor. It must not open the creature row, or they would all escape
    # down it.
    for y in range(1, CORRIDOR_Y):
        if y != ENTITY_Y:
            put(SPAWN_X, y, air)

    hdr = struct.pack('<6i', width, H, TILE_W, TILE_H, SHEET_C, SHEET_R)
    return hdr + struct.pack('<%dH' % (width * H), *t)


def install(gamedir, sprite_set):
    types, terrain, wall, air = SETS[sprite_set]
    for rel in TARGETS:
        p = os.path.join(gamedir, rel.replace('/', os.sep))
        if os.path.isfile(p) and not os.path.isfile(p + '.orig'):
            open(p + '.orig', 'wb').write(open(p, 'rb').read())

    set_stage1_sets(gamedir, sprite_set, terrain)

    width = LEFT + len(types) * PITCH + 3
    open(os.path.join(gamedir, 'map', '001.map'), 'wb').write(
        build_map(width, types, wall, air))

    ev, tk, legend = [], [], []
    for i, t in enumerate(types):
        x = LEFT + i * PITCH
        ev.append('0,0000,0000,%04d,%04d,%04d-*,*' % (x, ENTITY_Y, t))
        ev.append('1,0000,0000,%04d,%04d,0016-*,0000-03-%04d'
                  % (x, SIGN_Y, i))
        tk.append('TYPE %d ' % t + chr(92) + 'e')
        legend.append((x, t))

    d = os.path.join(gamedir, 'data')
    open(os.path.join(d, 'ev001.dat'), 'w', encoding='latin-1').write(
        '\n'.join(ev) + '\n')
    open(os.path.join(d, 'tk001.dat'), 'w', encoding='latin-1').write(
        '\n'.join(tk) + '\n')

    print('zoo installed: set %d, terrain %d, tiles %d/%d, %d cages, map %dx%d'
          % (sprite_set, terrain, wall, air, len(types), width, H))
    print('originals kept alongside each target as *.orig')
    print()
    print('  tile x   type')
    for x, t in legend:
        print('  %6d   %d' % (x, t))


def restore(gamedir):
    n = 0
    for rel in TARGETS:
        p = os.path.join(gamedir, rel.replace('/', os.sep))
        if os.path.isfile(p + '.orig'):
            open(p, 'wb').write(open(p + '.orig', 'rb').read())
            os.remove(p + '.orig')
            n += 1
    print('restored %d files' % n)


def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ('--install', '--restore'):
        print(__doc__)
        return 2
    g = sys.argv[2]
    if not os.path.isdir(os.path.join(g, 'data')):
        print('no data/ under %s' % g)
        return 2
    if sys.argv[1] == '--restore':
        restore(g)
        return 0
    sprite_set = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    if sprite_set not in SETS:
        print('sprite set must be one of %s' % sorted(SETS))
        return 2
    install(g, sprite_set)
    return 0


if __name__ == '__main__':
    sys.exit(main())
