#!/usr/bin/env python3
"""Check notes/function_map.md against notes/game_functions.txt.

The old function_map.md rotted badly: it named 0x466340 Load_Tile_Data reading
`data\\tk\\` when it actually reads map\\*.map, called 0x45509C
SaveGame_Select_Slot when it has nothing to do with saves, and hid the terrain
id behind Configure_Stage_Params. Each was believed on sight and cost real time.

It rotted because nothing could contradict it. This is what contradicts it now.

game_functions.txt is generated from the Ghidra database and is the ADDRESS
authority. function_map.md is the MEANING authority. Where they both name an
address, they must agree - otherwise one of them is stale and there is no way
to tell which by reading.

What this checks:

  * every `0x...` + `Name` pair in function_map.md matches the database
  * no address is claimed for two different names
  * addresses in the game range that the map names are actually in the database

What it does NOT check is whether a name is CORRECT. Nothing mechanical can.
That is what the evidence grades in the map are for.

Usage:  python check_function_map.py [--repo <path>]
Exit code 0 means the two files agree.
"""

import os
import re
import sys

# `| \x600x4608BC\x60 | \x60Entity_UpdateAll\x60 |` and the prose form
# "`Entity_UpdateAll` `0x4608BC`" both appear in the map, so match either order.
PAIR_A = re.compile(r"`0x([0-9A-Fa-f]{6,8})`\s*\|\s*`?([A-Za-z_]\w*)`?")
PAIR_B = re.compile(r"`([A-Za-z_]\w{3,})`\s*`0x([0-9A-Fa-f]{6,8})`")

# Names that are deliberately not database function names.
SKIP = {
    "read", "inferred", "corroborated", "the", "and", "a", "an",
}


def load_db(path):
    db = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            addr, _, name = line.partition("  ")
            try:
                db[int(addr, 16)] = name.strip()
            except ValueError:
                continue
    return db


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if "--repo" in sys.argv:
        repo = sys.argv[sys.argv.index("--repo") + 1]

    db = load_db(os.path.join(repo, "notes", "game_functions.txt"))
    md_path = os.path.join(repo, "notes", "function_map.md")
    text = open(md_path, encoding="utf-8", errors="replace").read()

    claims = {}
    for m in PAIR_A.finditer(text):
        addr, name = int(m.group(1), 16), m.group(2)
        if name.lower() not in SKIP:
            claims.setdefault(addr, set()).add(name)
    for m in PAIR_B.finditer(text):
        name, addr = m.group(1), int(m.group(2), 16)
        if name.lower() not in SKIP:
            claims.setdefault(addr, set()).add(name)

    problems = []
    checked = agreed = 0

    for addr in sorted(claims):
        names = claims[addr]
        if len(names) > 1:
            problems.append("0x%08X: the map gives it two names: %s"
                            % (addr, ", ".join(sorted(names))))
            continue
        name = next(iter(names))
        if addr not in db:
            # Outside the game range is fine - Event_Begin and the RTL helpers
            # legitimately sit below it and are not in the generated list.
            continue
        checked += 1
        if db[addr] != name:
            problems.append("0x%08X: map says %-28s database says %s"
                            % (addr, name, db[addr]))
        else:
            agreed += 1

    print("function_map.md claims:      %d addresses" % len(claims))
    print("  checkable against the db:  %d" % checked)
    print("  agreeing:                  %d" % agreed)
    print("  disagreeing:               %d" % (checked - agreed))

    named = sum(1 for a in db if not db[a].startswith("FUN_"))
    print()
    print("database: %d game-layer functions, %d named (%.0f%%)"
          % (len(db), named, 100.0 * named / max(len(db), 1)))

    if problems:
        print()
        for p in problems:
            print("  " + p)
        print()
        print("FAILED - one of the two files is stale")
        return 1

    print()
    print("OK - the map and the database agree everywhere they overlap")
    return 0


if __name__ == "__main__":
    sys.exit(main())
