#!/usr/bin/env python3
"""One address, two variables - the defect that has now shipped three times.

    python tools/shadow_globals.py

WHY

The original's state lives in globals. This reconstruction declares them in
GameState.pas with the original's address in a trailing comment:

    MenuIndex: Integer = 0;        // p_MenuIndex       0x0046CF88

The failure is not getting an address wrong. It is declaring the global AND
keeping a private field beside it that claims the SAME address in its own
comment, so two variables carry one of the original's. Each half then works
perfectly on its own copy and the two silently disagree.

It has happened three times, and every one reached the player:

    0x0046CF88  MenuIndex   vs TTitleScreen.FIndex
                the pause menu and the title menu each kept their own cursor
    0x0046CEF8  TitleSubMode vs TTitleScreen.FSubMode
                Stage_Begin cleared the global, GmMain read the field, and a
                CONTINUE left the title screen showing its OPTIONS page
    0x0046CF88  again, in the same file as the first

Neither the behavioural self-tests nor the coverage counter can see this: both
declarations exist, both have code, and a test that drives one half never
notices the other half is a different variable.

WHAT IT DOES

Collects every address named in a comment anywhere in src/, and reports any
address that is claimed by more than one DECLARATION. A declaration is a line
that declares storage - a field, a var, a typed constant - as opposed to prose
that merely mentions the address, which is why the address alone is not enough
and the line has to look like a declaration.

It cannot prove two declarations are the same variable, only that they claim
the same address. That is exactly the question worth a human's attention.
"""

import glob
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ADDR = re.compile(r'0x00[0-9A-Fa-f]{6}')
# `Name: Type` or `Name: Type = value` - a line that reserves storage. The
# leading anchor keeps `Result := Foo` and prose out.
DECL = re.compile(r'^\s*(F?[A-Za-z_]\w*)\s*:\s*[A-Za-z_]')


# THE ORIGINAL REALLY DOES KEEP TWO OF THESE, and a checker that cannot say so
# is a checker people learn to ignore.
#
# Four settings live twice in akuji.exe: as a loose global the game reads every
# frame, and as a byte in the 56-byte settings record that system.dat holds.
# DDDD1Init loads the record and scatters it into the globals; FormDestroy @
# 0x00466644 gathers the globals back into the record and writes the file. Two
# variables, one meaning, genuinely - so the pair below is expected, and only an
# identifier OUTSIDE each pair is a finding.
ALLOWED = {
    '0x0046cdb8': ({'DebugLogFlag', 'DebugLog'},
                   'system.dat +0x1B and the loose p_DebugLog'),
    '0x0046ce60': ({'SoftwareVsyncFlag', 'SoftwareVsync'},
                   'system.dat +0x18 and the loose p_SoftwareVsync'),
    '0x0046d268': ({'FullScreenFlag', 'FullScreenOn'},
                   'system.dat +0x1A and the loose p_FullScreenOn'),
    '0x0046d2e4': ({'WaitOnFlag', 'WaitOn'},
                   'system.dat +0x19 and the loose p_WaitOn'),
}


def main():
    claims = {}
    for pat in ('src/*.pas', 'src/*.lpr', 'src/*.inc'):
        for path in sorted(glob.glob(os.path.join(REPO, pat))):
            name = os.path.basename(path)
            for n, line in enumerate(
                    open(path, encoding='utf-8', errors='replace'), 1):
                m = DECL.match(line)
                if not m:
                    continue
                for a in ADDR.findall(line):
                    claims.setdefault(a.lower(), []).append(
                        (name, n, m.group(1), line.strip()[:66]))

    shared = {}
    for a, v in claims.items():
        idents = {ident for _, _, ident, _ in v}
        if len(idents) < 2:
            continue
        allowed = ALLOWED.get(a)
        # An allowed PAIR stays allowed; a third claimant on the same address
        # is exactly the defect, and FLimitFrames was found that way.
        if allowed and idents <= allowed[0]:
            continue
        shared[a] = v

    print('%d addresses claimed by a declaration' % len(claims))
    if not shared:
        print('no address is claimed by two different declarations')
        return 0

    print('\n%d ADDRESS(ES) CLAIMED BY MORE THAN ONE DECLARATION:\n'
          % len(shared))
    for a in sorted(shared):
        print('  %s' % a)
        for f, n, ident, text in shared[a]:
            print('      %-18s %s:%d  %s' % (ident, f, n, text))
        print()
    print('Two variables for one of the original\'s globals. Each half works on')
    print('its own copy and they disagree silently - see the header for the')
    print('three times this has already reached the player.')
    return 1


if __name__ == '__main__':
    sys.exit(main())
