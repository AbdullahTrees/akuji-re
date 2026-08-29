#!/usr/bin/env python3
"""Which game functions have EXECUTABLE Pascal, and which only have prose.

WHY THIS EXISTS

`coverage.py` counts an address as covered if it is *mentioned* anywhere in
`src/`, which deliberately means "someone looked at this". That is a useful
number and it is not the number you want before saying a function is done,
because it cannot tell these two apart:

    { 0x00457880. Builds the player's box and this entity's, then
      switches on EF_TOUCH_KIND into seven handlers. }        <- prose
    procedure EntityPlayerTouch(...);                          <- but nil

    { 0x004608BC. Walks slots 0..$FF and for each live one... }
    procedure EntityUpdateAll(...);                            <- real code

Both mention the address. Only one runs. This project accumulated roughly a
dozen functions that had been read carefully, written up in detail, and never
turned into code — the findings sat in comments where nothing could execute or
test them.

THE RULE

A routine **implements** an address when that address appears in the comment
block **immediately above its declaration** — no blank line, no other statement
in between. That is already the house style, so this mostly just reads it back:

    { 0x0045A540. The save point's idle animation. }
    procedure EntityUpdate_Type27(var E: TEntity; AGameState: Integer);

An address mentioned anywhere else is DESCRIBED: real knowledge, not yet code.

THE NEAR MISS, AND WHY IT GETS ITS OWN LIST

The rule is strict on purpose - it is what stopped prose being counted as code.
But strictness cuts both ways, and it has now mis-filed a FINISHED translation
four times:

    Sounds_LoadAll      the loop was TAudioMixer.LoadAll all along
    Overlay_Update      Dialogue.pas was written from it end to end
    HUD_Draw            TFrm_main.DrawHud, complete down to the icon animation
    entry               the .dpr block, which is not a declaration at all

Each time the code existed and the address simply was not in the comment block
immediately above the declaration - one comment too high, or with a const
section in between. Filed as "read but never written", which is the opposite
of the truth, and each took a read of the whole routine to notice.

So the summary now also lists NEAR MISSES: addresses that appear in the same
file as a routine but not where the rule can see them. That is not a loosening
- nothing moves into the implemented count - it just stops the failure being
silent. A near miss is either a misplaced address or a genuine description
sitting next to unrelated code, and the two are told apart by reading.

An abstract method is NOT an implementation, and neither is an override inside
a test double. Both are filtered out, because both are exactly the shape of the
thing this is meant to catch.

USAGE

    python tools/implemented.py               summary plus the described list
    python tools/implemented.py --all         every function, classified
    python tools/implemented.py --described   just the backlog, for planning
"""

import argparse
import os
import re
import sys

GAME_LO = 0x454790
GAME_HI = 0x467200

DECL = re.compile(
    r'^\s*(function|procedure|constructor|destructor)\s+([A-Za-z_][\w.]*)')
ADDR = re.compile(r'0x([0-9A-Fa-f]{6,8})')

# A declaration that is abstract, or that lives in a test double, is a promise
# rather than an implementation.
ABSTRACT = re.compile(r'\bvirtual;\s*abstract\b|\babstract;', re.I)
TEST_CLASS = re.compile(r'\b(TFlatWorld|TCountingWorld|TStubSprites|'
                        r'TMapTiles|TGridTiles)\b')


def load_functions(path):
    out = {}
    for line in open(path, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        a, _, n = line.partition('  ')
        try:
            out[int(a, 16)] = n.strip()
        except ValueError:
            pass
    return out


# How far past a comment block a declaration may sit and still make the block
# a plausible near miss. Big enough to jump a const section, small enough that
# an address in a table at the top of a unit does not reach the first routine.
NEAR_LINES = 40


def scan(src_dir):
    """address -> list of (file, routine) that implement it."""
    impl = {}
    mentioned = {}
    near = {}
    for name in sorted(os.listdir(src_dir)):
        if not name.lower().endswith(('.pas', '.lpr')):
            continue
        path = os.path.join(src_dir, name)
        lines = open(path, encoding='utf-8', errors='replace').read().split('\n')

        for i, ln in enumerate(lines):
            for m in ADDR.finditer(ln):
                a = int(m.group(1), 16)
                if GAME_LO <= a < GAME_HI:
                    mentioned.setdefault(a, set()).add(name)

        # Walk comment blocks and see what declaration follows each.
        i = 0
        while i < len(lines):
            if '{' in lines[i] and not lines[i].lstrip().startswith('//'):
                start = i
                depth = 0
                while i < len(lines):
                    depth += lines[i].count('{') - lines[i].count('}')
                    if depth <= 0:
                        break
                    i += 1
                block = '\n'.join(lines[start:i + 1])
                j = i + 1
                while j < len(lines) and not lines[j].strip():
                    j += 1
                if j < len(lines) and j - i <= 1:
                    m = DECL.match(lines[j])
                    if m and not ABSTRACT.search(lines[j]):
                        # look a couple of lines on for a split declaration
                        tail = '\n'.join(lines[j:j + 3])
                        if not ABSTRACT.search(tail) and not TEST_CLASS.search(block):
                            for am in ADDR.finditer(block):
                                a = int(am.group(1), 16)
                                if GAME_LO <= a < GAME_HI:
                                    impl.setdefault(a, []).append(
                                        (name, m.group(2)))
            i += 1

        # A near miss: the address sits in a COMMENT BLOCK that is followed
        # by a routine declaration within NEAR_LINES - close enough that the
        # block is plausibly about that routine - but not immediately above
        # it, so the strict rule above did not pair them.
        #
        # The first version of this just asked "is the address anywhere in a
        # file that declares routines", which flagged all six remaining
        # addresses including the ones that are genuinely only prose. A
        # signal that fires on everything is not a signal. Requiring a
        # declaration NEARBY is what makes it mean something.
        i = 0
        while i < len(lines):
            if '{' in lines[i] and not lines[i].lstrip().startswith('//'):
                start = i
                depth = 0
                while i < len(lines):
                    depth += lines[i].count('{') - lines[i].count('}')
                    if depth <= 0:
                        break
                    i += 1
                block = '\n'.join(lines[start:i + 1])
                addrs = [int(m.group(1), 16) for m in ADDR.finditer(block)]
                addrs = [a for a in addrs if GAME_LO <= a < GAME_HI]
                if addrs:
                    for j in range(i + 1, min(i + 1 + NEAR_LINES, len(lines))):
                        m = DECL.match(lines[j])
                        if m and not ABSTRACT.search(lines[j]):
                            for a in addrs:
                                if a not in impl:
                                    near.setdefault(a, set()).add(
                                        '%s:%s' % (name, m.group(2)))
                            break
            i += 1
    return impl, mentioned, near


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--repo', default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--described', action='store_true')
    args = ap.parse_args()

    funcs = load_functions(os.path.join(args.repo, 'notes',
                                        'game_functions.txt'))
    impl, mentioned, near = scan(os.path.join(args.repo, 'src'))

    implemented = sorted(a for a in funcs if a in impl)
    described = sorted(a for a in funcs if a not in impl and a in mentioned)
    untouched = sorted(a for a in funcs if a not in impl and a not in mentioned)

    if args.described or not args.all:
        print('DESCRIBED BUT NOT IMPLEMENTED - read, written up, no code: %d'
              % len(described))
        for a in described:
            flag = '  <- NEAR MISS' if a in near else ''
            print('   0x%06X  %-34s %s%s'
                  % (a, funcs[a], ', '.join(sorted(mentioned[a])),
                     flag + (' ' + ', '.join(sorted(near[a])) if a in near
                             else '')))
        print()
        hits = [a for a in described if a in near]
        if hits:
            print('%d of those are NEAR MISSES: the address is in a file that '
                  'declares' % len(hits))
            print('routines, so the code may already exist with the address in '
                  'the wrong place.')
            print('That has been the answer four times. Read before writing.')
            print()

    if args.all:
        print('IMPLEMENTED: %d' % len(implemented))
        for a in implemented:
            who = ', '.join('%s:%s' % p for p in impl[a])
            print('   0x%06X  %-34s %s' % (a, funcs[a], who))
        print()
        print('UNTOUCHED: %d' % len(untouched))
        for a in untouched:
            print('   0x%06X  %s' % (a, funcs[a]))
        print()

    total = len(funcs)
    print('game-layer functions : %d' % total)
    print('implemented          : %d  (%.1f%%)'
          % (len(implemented), 100.0 * len(implemented) / total))
    print('described only       : %d' % len(described))
    print('untouched            : %d' % len(untouched))
    return 0


if __name__ == '__main__':
    sys.exit(main())
