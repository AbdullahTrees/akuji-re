#!/usr/bin/env python3
"""Push tools/entity_names.csv into both projects.

    python tools/apply_entity_names.py [--dry-run]

WHY A TOOL AND NOT A HAND EDIT

The names came from someone PLAYING the game, one entity at a time, in a zoo
room built per sprite set. That is the only source for most of them - the
disassembly says what type 61 does, not that it is a HenaHena - so the csv is
the record and this replays it. Running it twice is a no-op, and a name changed
in the csv is changed in both projects by running it again.

WHAT IT TOUCHES

  src/*.pas          EntityUpdate_TypeNN        -> EntityUpdate_TypeNN_<Name>
  notes/audited.md   the same, in the Ghidra-name column, so the ledger keeps
                     naming the function it is a row about

The Ghidra side is printed rather than applied: the MCP bridge is interactive
and the project has to be saved in the GUI afterwards, so a script cannot
finish the job and pretending otherwise would leave the two out of step.

The TNN_ constant prefixes are deliberately left alone. T42_SPRITES beside
EntityUpdate_Type42_Boss_TealBlobSlammer already reads, and renaming two
hundred constants would be churn with no reader benefit.
"""

import io
import os
import re
import sys

from source_tree import source_files, unit_path

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CSV = os.path.join(HERE, 'entity_names.csv')


def load_names():
    """type -> Name, skipping rows still unidentified."""
    out = {}
    for line in io.open(CSV, encoding='latin-1'):
        line = line.strip()
        if not line or line.startswith('#') or line.startswith('type,'):
            continue
        f = line.split(',', 2)
        if len(f) < 2 or not f[0].isdigit():
            continue
        name, note = f[1].strip(), (f[2] if len(f) > 2 else '')
        if not name or name.startswith('Type_') or 'UNCONFIRMED' in note:
            continue
        if not re.match(r'^[A-Za-z][A-Za-z0-9_]*$', name):
            print('skipping type %s: %r is not an identifier' % (f[0], name))
            continue
        out[int(f[0])] = name
    return out


def retarget(text, names):
    """Rewrite every EntityUpdate_TypeNN, with or without an existing suffix."""
    def sub(m):
        typ = int(m.group(1))
        if typ not in names:
            return m.group(0)
        return 'EntityUpdate_Type%d_%s' % (typ, names[typ])
    return re.sub(r'\bEntityUpdate_Type(\d+)(?:_[A-Za-z0-9_]+)?', sub, text)


def main():
    dry = '--dry-run' in sys.argv
    names = load_names()
    print('%d named types' % len(names))

    targets = source_files(ROOT, ('.pas', '.lpr'))
    targets.append(os.path.join(ROOT, 'notes', 'audited.md'))

    for path in targets:
        # newline='' both ways: read and write the file's own line
        # endings untouched, so this never shows up as a whole-file diff.
        old = io.open(path, encoding='utf-8', errors='surrogateescape',
                      newline='').read()
        new = retarget(old, names)
        if new == old:
            continue
        n = sum(1 for _ in re.finditer(r'\bEntityUpdate_Type\d+', old))
        print('%-28s %d references' % (os.path.relpath(path, ROOT), n))
        if not dry:
            io.open(path, 'w', encoding='utf-8',
                    errors='surrogateescape', newline='').write(new)

    print()
    print('Ghidra side - apply with rename_function_by_address, then SAVE the')
    print('project in the GUI or the edits are lost:')
    handlers = unit_path(ROOT, 'EntityHandlers.pas')
    src = io.open(handlers, encoding='utf-8', errors='surrogateescape',
                  newline='').read()
    m = re.search(r'HANDLER_ADDR[^=]*=\s*\((.*?)\);', src, re.S)
    addrs = re.findall(r'\$([0-9A-Fa-f]{8})', m.group(1)) if m else []
    for typ, name in sorted(names.items()):
        if typ < len(addrs) and addrs[typ] != '00000000':
            print('  0x%s  EntityUpdate_Type%d_%s' % (addrs[typ], typ, name))
    return 0


if __name__ == '__main__':
    sys.exit(main())
