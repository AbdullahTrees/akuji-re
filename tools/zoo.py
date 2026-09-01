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

TYPES = [14, 15, 16, 20, 21, 22, 23, 24, 25, 27, 29, 30, 31, 37, 38, 40, 41,
         42, 43, 45, 46, 47, 49, 50, 51, 52, 54, 56, 58, 59, 60, 61, 62, 63,
         64, 65, 66, 67, 69, 70, 71, 73, 76, 77, 80]

WALL, AIR = 97, 1
TILE_W = TILE_H = 32
SHEET_C = SHEET_R = 10

PITCH = 4          # 3-tile cell + 1-tile divider
LEFT = 6           # cages start here; the spawn shaft is at tile 3
SPAWN_X = 3        # DEFAULT_SPAWN_X is 0x60 = 96px = tile 3

# THE HEIGHT AND THE ROWS ARE NOT ARBITRARY. A new game starts with
# PlayerState.ScrollY = DEFAULT_SCROLL_Y = 0x1C0 = 448 pixels = tile 14, and
# Stage_Begin sets the camera straight from it. Nothing clamps that: the
# original's Camera_ApplyMoveY only ADDS VelY when a scroll is called for, so
# a camera that starts outside the map stays outside it.
#
# A first attempt made the map 14 tiles tall - exactly 448 pixels - so the
# camera began precisely at the bottom edge, the draw loop ran zero times and
# the screen was black with the player somewhere off it. The map has to be
# tall enough that row 14 is real, and the interesting part has to BE at
# row 14, because that is where the camera opens.
H = 24
CAGE_CEIL_Y = 11
CELL_FLOOR_Y = 16          # cages occupy rows 12..15
CORRIDOR_FLOOR_Y = 20      # corridor is rows 17..19
ENTITY_Y = 15              # stands on the cage floor
SIGN_Y = 19                # stands on the corridor floor

TARGETS = ('map/001.map', 'data/ev001.dat', 'data/tk001.dat')


def build_map(width):
    t = [AIR] * (width * H)

    def put(x, y, v):
        if 0 <= x < width and 0 <= y < H:
            t[y * width + x] = v

    # everything above the cages is solid rock, so the player falls down the
    # one shaft rather than wandering across the roof
    for x in range(width):
        for y in range(0, CAGE_CEIL_Y + 1):
            put(x, y, WALL)
        put(x, CELL_FLOOR_Y, WALL)           # cage floor / corridor ceiling
        put(x, CORRIDOR_FLOOR_Y, WALL)       # corridor floor
        for y in range(CORRIDOR_FLOOR_Y + 1, H):
            put(x, y, WALL)                  # fill below
    for y in range(H):
        put(0, y, WALL)
        put(width - 1, y, WALL)

    # the dividers between cages
    for i in range(len(TYPES) + 1):
        x = LEFT + i * PITCH - 1
        for y in range(CAGE_CEIL_Y + 1, CELL_FLOOR_Y):
            put(x, y, WALL)

    # the spawn shaft: the player appears at tile 3 row 3 and drops into the
    # corridor. Everything from the surface down to the corridor is opened.
    for y in range(1, CORRIDOR_FLOOR_Y):
        put(SPAWN_X, y, AIR)

    hdr = struct.pack('<6i', width, H, TILE_W, TILE_H, SHEET_C, SHEET_R)
    return hdr + struct.pack('<%dH' % (width * H), *t)


def install(gamedir):
    for rel in TARGETS:
        p = os.path.join(gamedir, rel.replace('/', os.sep))
        if os.path.isfile(p) and not os.path.isfile(p + '.orig'):
            open(p + '.orig', 'wb').write(open(p, 'rb').read())

    width = LEFT + len(TYPES) * PITCH + 3
    open(os.path.join(gamedir, 'map', '001.map'), 'wb').write(build_map(width))

    ev, tk, legend = [], [], []
    for i, t in enumerate(TYPES):
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

    print('zoo installed: %d cages, map %dx%d' % (len(TYPES), width, H))
    print('originals kept as map/001.map.orig, data/ev001.dat.orig, '
          'data/tk001.dat.orig')
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
    (install if sys.argv[1] == '--install' else restore)(g)
    return 0


if __name__ == '__main__':
    sys.exit(main())
