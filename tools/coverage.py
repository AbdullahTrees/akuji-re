#!/usr/bin/env python3
"""How much of the game's own code has a Pascal counterpart yet.

The other tools check that our READERS agree with the game's data. This one
checks something different and structural: that for each function in the game
layer of akuji.exe there is a place in the Pascal that says it came from there.

It works because the reconstruction records provenance in the source. Every
translated routine carries the original's address in a comment, e.g.

    { DrawHud - HUD_Draw @ 0x00461BA8. }

so scanning src/*.pas for addresses in the game range and intersecting with
notes/game_functions.txt gives a real, re-runnable coverage figure rather than
a feeling about progress.

What it does NOT prove: that the translation is correct, or that the call graph
matches. An address mentioned in a comment only means someone looked at that
function. Treat the number as "surveyed", not "verified" - the verification
tiers are the --selftest modes and their reference scripts.

Usage:
    python coverage.py [--missing] [--repo <path>]
"""

import os
import re
import sys

GAME_LO = 0x454790   # see the header of notes/game_functions.txt
GAME_HI = 0x467200

# Only the 0x form. Pascal's own $0045B3EC form is deliberately NOT matched:
# EntityHandlers.HANDLER_ADDR lists all 78 arms of Entity_UpdateAll's switch as
# data, and counting those as coverage would take the figure from 34% to 85%
# without a line of any handler having been read. A table of addresses is a
# to-do list, not a translation.
ADDR_RE = re.compile(r"0x([0-9A-Fa-f]{6,8})")


def load_game_functions(path):
    funcs = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            addr, _, name = line.partition("  ")
            try:
                funcs[int(addr, 16)] = name.strip()
            except ValueError:
                continue
    return funcs


def scan_sources(src_dir):
    """address -> set of files that mention it."""
    found = {}
    for name in sorted(os.listdir(src_dir)):
        if not name.lower().endswith((".pas", ".lpr")):
            continue
        text = open(os.path.join(src_dir, name), encoding="utf-8",
                    errors="replace").read()
        for m in ADDR_RE.finditer(text):
            addr = int(m.group(1), 16)
            if GAME_LO <= addr < GAME_HI:
                found.setdefault(addr, set()).add(name)
    return found


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if "--repo" in sys.argv:
        repo = sys.argv[sys.argv.index("--repo") + 1]
    show_missing = "--missing" in sys.argv

    funcs = load_game_functions(os.path.join(repo, "notes", "game_functions.txt"))
    found = scan_sources(os.path.join(repo, "src"))

    covered = {a: n for a, n in funcs.items() if a in found}
    missing = {a: n for a, n in funcs.items() if a not in found}

    # Addresses cited in the source that are not known game functions. Usually
    # a data address or a mid-function label, but a typo lands here too.
    unknown = sorted(a for a in found if a not in funcs)

    print("game-layer functions: %d  (0x%06X..0x%06X)"
          % (len(funcs), GAME_LO, GAME_HI - 1))
    print("referenced in src/:    %d" % len(covered))
    print("not yet touched:       %d" % len(missing))
    print("coverage:              %.1f%%" % (100.0 * len(covered) / max(len(funcs), 1)))
    print()

    print("referenced:")
    for addr in sorted(covered):
        where = ", ".join(sorted(found[addr]))
        print("  %08x  %-32s %s" % (addr, covered[addr], where))

    if show_missing:
        print()
        print("not yet touched:")
        for addr in sorted(missing):
            print("  %08x  %s" % (addr, missing[addr]))

    if unknown:
        print()
        print("addresses cited in src/ that are not game functions (%d):"
              % len(unknown))
        for addr in unknown[:20]:
            print("  %08x  %s" % (addr, ", ".join(sorted(found[addr]))))
        if len(unknown) > 20:
            print("  ... and %d more" % (len(unknown) - 20))

    return 0


if __name__ == "__main__":
    sys.exit(main())
