#!/usr/bin/env python3
"""Generate akuji_trace.js - a Frida script that traces the ORIGINAL binary.

    python tools/make_trace.py [--out DIR] [--group G ...]

WHY THIS EXISTS

Everything this project knows came from reading akuji.exe, not from running it.
That is a structural blind spot rather than a small one: static reading cannot
say which path is actually taken, what a global holds when a handler runs, or
whether a phase the code can reach is ever reached in play. Several of the open
questions are exactly that shape - Ending.pas records phase 1 as "a HOLE,
nothing in the original leaves it", which is either a misreading or a callback
firing from somewhere, and no amount of re-reading settles it.

Ghidra's emulator does not help here. It runs chosen bytes with chosen inputs;
it is not the game playing. Frida attaches to the real process, so the answer
comes from the program actually running.

WHY IT IS GENERATED

The addresses come from notes/game_functions.txt, the project's address
authority. Hand-copying sixty of them into a JS file would create a second,
drifting copy of the database - and a trace with one wrong address is worse
than no trace, because it still looks like evidence.

GROUPS, because tracing everything at 60 FPS is not usable:

    frame    the idle loop - emits a frame marker, so two logs can be lined up
    state    title, opening, ending, pause, game-over, state reset
    entity   spawn, destroy, the update loop, player touch
    event    the script interpreter and its steps
    load     asset and stage loading, which run once at startup
    all      every named game function, including the 78 entity handlers

Default is frame+state+load: quiet enough to read, and it answers the "what
actually happens at boot" question. Add groups as needed.

USAGE

    python tools/make_trace.py                  writes into the 1.1 (D) gamedir
    cd "<gamedir>" && frida -f akuji.exe -l akuji_trace.js

The log lands beside the exe as akuji_trace.log.
"""

import argparse
import os
import re

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(REPO, 'notes', 'game_functions.txt')
DEFAULT_OUT = os.path.join(REPO, 'English Translated Version 1.1 (D)')

# Globals sampled on every logged call - the ones the open questions are about.
#
# SEVERAL OF THESE ARE POINTERS, not the variable. The first trace run made that
# unmissable: gameState, screenPhase and titleSubMode read back as 0x47EF98,
# 0x47EF9C and 0x47EFA0 - three consecutive addresses that never changed across
# 862 frames of sitting on the title menu, where the state must have been 20.
#
# The disassembly settles it. At 0x00459EE5:
#
#     mov edx, DWORD PTR ds:0x46d06c    ; load
#     mov edx, DWORD PTR [edx]          ; DEREFERENCE
#     sub edx, 0x3c                     ; compare with 60, which is GS_PLAY
#
# so 0x0046D06C holds a pointer and the Integer lives at 0x0047EF98. Nothing in
# the binary ever stores to 0x0046D06C, which fits: it is set up once and only
# ever read through.
#
# Rather than hard-code which is which and be wrong again, the script prints the
# raw dword AND, when the raw value looks like a pointer into the data range,
# what it points at - as `name*=`. The log then shows its own working.
GLOBALS = [
    (0x0046D06C, 'gameState'),
    (0x0046CBBC, 'savedState'),
    (0x0046CC14, 'screenPhase'),
    (0x0046D174, 'screenTimer'),
    (0x0046D298, 'screenStep'),
    (0x0046CEF8, 'titleSubMode'),
    (0x0046CF88, 'menuIndex'),
    (0x0046E040, 'randSeed'),
]

GROUPS = {
    'frame':  [r'^TFrm_main_AppIdle$'],
    'state':  [r'^Title_', r'^Opening_', r'^Ending_', r'^PauseMenu_',
               r'^GameOver_', r'^GameState_Reset$', r'^Game_StartOrLoad$',
               r'^Stage_Begin$', r'^TFrm_main_DDDD1Init$',
               r'^Display_SetFullScreen$', r'^MessageBox_Update$',
               r'^PowerUp_Show$', r'^Overlay_Update$'],
    'entity': [r'^Entity_Spawn$', r'^Entity_Destroy$', r'^Entity_UpdateAll$',
               r'^Entity_PlayerTouch$', r'^Entity_UpdateDying$',
               r'^Player_Update$'],
    'event':  [r'^Event', r'^EventScript_'],
    'load':   [r'^Load_', r'^Sounds_LoadAll$', r'^Terrain_Configure$',
               r'^entry$', r'^TFrm_main_FormDestroy$'],
    'all':    [r'.'],
}


def read_db():
    out = []
    for line in open(DB, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split()
        if len(parts) >= 2:
            out.append((int(parts[0], 16), parts[1]))
    return out


def pick(funcs, groups):
    pats = []
    for g in groups:
        pats += GROUPS[g]
    rx = [re.compile(p) for p in pats]
    return [(a, n) for a, n in funcs if any(r.search(n) for r in rx)]


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default=DEFAULT_OUT)
    ap.add_argument('--group', action='append', choices=sorted(GROUPS),
                    help='repeatable; default: frame state load')
    args = ap.parse_args()
    groups = args.group or ['frame', 'state', 'load']

    funcs = read_db()
    chosen = pick(funcs, groups)
    if not chosen:
        print('no functions matched %s' % groups)
        return 2

    tbl = ',\n'.join('  [0x%06x, "%s"]' % (a, n) for a, n in chosen)
    gtbl = ',\n'.join('  [0x%06x, "%s"]' % (a, n) for a, n in GLOBALS)

    js = (JS_TEMPLATE
          .replace('@@FUNCS@@', tbl)
          .replace('@@GLOBALS@@', gtbl)
          .replace('@@GROUPS@@', ' '.join(groups))
          .replace('@@COUNT@@', str(len(chosen))))

    if not os.path.isdir(args.out):
        print('no such directory: %s' % args.out)
        return 2
    dest = os.path.join(args.out, 'akuji_trace.js')
    with open(dest, 'w', newline='\n', encoding='utf-8') as fh:
        fh.write(js)

    print('wrote %s' % dest)
    print('  %d functions hooked; groups: %s' % (len(chosen), ' '.join(groups)))
    print()
    print('  cd "%s"' % args.out)
    print('  frida -f akuji.exe -l akuji_trace.js')
    print()
    print('  play for a bit, close the game, and the log is akuji_trace.log')
    return 0


JS_TEMPLATE = r'''/* akuji_trace.js - GENERATED by tools/make_trace.py. Do not edit by hand.
 *
 * Groups: @@GROUPS@@   (@@COUNT@@ functions)
 *
 * Traces the ORIGINAL akuji.exe while it actually runs, which is the one thing
 * reading it cannot do. Addresses come from notes/game_functions.txt, the
 * project's address authority, so a wrong address here would have to be wrong
 * there too.
 *
 *   cd "<gamedir>"
 *   frida -f akuji.exe -l akuji_trace.js
 *
 * Output goes to akuji_trace.log beside the exe.
 *
 * READ THE LOG AS A SEQUENCE, NOT A TRANSCRIPT. Entry is logged, not exit, so
 * nesting is implied by order rather than shown. That is deliberate: logging
 * both doubles the volume, and what the open questions need is which functions
 * run, in what order, and with what state - not how long each took.
 */

'use strict';

var IMAGE_BASE = ptr(0x400000);       /* the PE's preferred base */
var MAX_LINES = 400000;               /* a cap, so a long session cannot fill
                                         the disk unnoticed */

var FUNCS = [
@@FUNCS@@
];

var GLOBALS = [
@@GLOBALS@@
];

function findModule() {
    /* mainModule is the reliable one under -f; the others are fallbacks for
     * attaching to an already-running game by name or pid. */
    try {
        if (Process.mainModule) { return Process.mainModule; }
    } catch (e) { /* fall through */ }
    var m = null;
    try { m = Process.findModuleByName('akuji.exe'); } catch (e) { m = null; }
    if (m) { return m; }
    var mods = Process.enumerateModules();
    for (var i = 0; i < mods.length; i++) {
        if (mods[i].name.toLowerCase().indexOf('akuji') !== -1) {
            return mods[i];
        }
    }
    return null;
}

var mod = findModule();
if (mod === null) {
    console.log('akuji_trace: could not find the akuji module - nothing hooked');
} else {

/* Everything is read through the slide rather than at the literal address, so
 * this works whether or not the image loads at its preferred base. */
var slide = mod.base.sub(IMAGE_BASE);

/* akuji.exe is a 32-bit PE, so the registers below are the 32-bit names. If
 * this ever runs somewhere else the field names would be wrong and the log
 * would be silently useless, so say so rather than produce one. */
if (Process.arch !== 'ia32') {
    console.log('akuji_trace: expected a 32-bit process, got ' + Process.arch +
                ' - the register names below would be wrong; not hooking');
    throw new Error('wrong architecture');
}

/* Beside the exe, not in the CWD: under -f the working directory is whatever
 * the spawn inherited, and a log that lands somewhere unpredictable is a log
 * nobody finds. */
var logPath = 'akuji_trace.log';
try {
    /* No backslash literal here on purpose: this string travels
     * through a Python template, and counting escape layers is how
     * the last three versions of this line came out wrong. */
    var BS = String.fromCharCode(92);
    var sep = mod.path.lastIndexOf(BS);
    if (sep < 0) { sep = mod.path.lastIndexOf('/'); }
    if (sep > 0) { logPath = mod.path.substring(0, sep + 1) + 'akuji_trace.log'; }
} catch (e) { /* keep the relative fallback */ }
var log = new File(logPath, 'w');
var nLines = 0;
var frame = 0;
var capped = false;

function emit(s) {
    if (capped) { return; }
    if (nLines >= MAX_LINES) {
        log.write('--- capped at ' + MAX_LINES + ' lines ---\n');
        log.flush();
        capped = true;
        return;
    }
    nLines++;
    log.write(s + '\n');
    if ((nLines & 0x3ff) === 0) { log.flush(); }
}

/* Zero-valued globals are omitted, so a name APPEARING in the log is itself
 * the signal that something left zero - which is what makes a phase change
 * visible without diffing every line.
 *
 * Some of these cells hold a POINTER to the variable rather than the variable
 * (see the note in make_trace.py). Anything that looks like a pointer into the
 * image's data range is followed and reported as `name*=`, so the log shows
 * both and never silently reports an address as though it were a value. */
var DATA_LO = 0x460000, DATA_HI = 0x4A0000;

function globalsText() {
    var parts = [];
    for (var i = 0; i < GLOBALS.length; i++) {
        var name = GLOBALS[i][1];
        var v = null;
        try { v = slide.add(GLOBALS[i][0]).readS32(); } catch (e) { v = null; }
        if (v === null || v === 0) { continue; }
        var looksPtr = (v >= DATA_LO && v < DATA_HI);
        if (looksPtr) {
            var d = null;
            try { d = ptr(v).readS32(); } catch (e) { d = null; }
            if (d !== null) {
                parts.push(name + '*=' + d);
                continue;
            }
        }
        parts.push(name + '=' + v);
    }
    return parts.join(' ');
}

emit('# akuji_trace  base=' + mod.base + ' slide=' + slide);
emit('# groups: @@GROUPS@@');
emit('# columns: frame  function  eax edx ecx [stack0,stack1]  | globals');
emit('# a global at zero is omitted, so a name appearing IS the change');

for (var i = 0; i < FUNCS.length; i++) {
    (function (addr, name) {
        var isFrame = (name === 'TFrm_main_AppIdle');
        try {
            Interceptor.attach(slide.add(addr), {
                onEnter: function () {
                    var c = this.context;
                    if (isFrame) {
                        frame++;
                        /* The frame marker is what lets two logs be lined up.
                         * Without it a diff drifts by one call and never
                         * recovers. */
                        emit('--- frame ' + frame + ' --- ' + globalsText());
                        return;
                    }
                    var stk = '';
                    try {
                        stk = ' [' + c.esp.add(4).readS32() + ',' +
                                     c.esp.add(8).readS32() + ']';
                    } catch (e) { stk = ''; }
                    emit(frame + '  ' + name +
                         '  ' + c.eax.toInt32() +
                         ' ' + c.edx.toInt32() +
                         ' ' + c.ecx.toInt32() + stk +
                         '  | ' + globalsText());
                }
            });
        } catch (e) {
            console.log('akuji_trace: could not hook ' + name + ' @ 0x' +
                        addr.toString(16) + ': ' + e.message);
        }
    })(FUNCS[i][0], FUNCS[i][1]);
}

console.log('akuji_trace: base ' + mod.base + ', ' + FUNCS.length +
            ' hooks, writing ' + logPath);

rpc.exports = {
    flush: function () { log.flush(); return nLines; },
    lines: function () { return nLines; }
};

}
'''


if __name__ == '__main__':
    raise SystemExit(main())
