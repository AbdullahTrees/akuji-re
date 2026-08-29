#!/usr/bin/env python3
"""Drive the differential test: run the ORIGINAL, then diff the reconstruction.

    python tools/emudiff.py [--gamedir DIR] [--keep] [case-set ...]

Three steps, all of which this handles:

  1. build a spec of calls into akuji.exe
  2. run ghidra_scripts/EmuDiff.java under analyzeHeadless, which executes the
     original's machine code for each and appends its answer
  3. run `akuji.exe --emudiff <that file>`, which recomputes each case with the
     reconstruction and requires the two to agree

WHY IT LOOKS LIKE THIS

The spec and the results are ONE file. The emulator echoes each input line with
its answer appended, so the file the Pascal reads still carries everything the
case was built from - which means the two halves cannot drift out of step, and
a failing case can be re-run by hand from its own line.

Fields on a CASE line: eax=, edx=, ecx= are the register arguments; stk= is any
further ones; mem=ADDR:HEX places memory first (BSS is not in the PE, so
anything reached through a global has to be written); get=ADDR:LEN reads memory
back AFTER the call; f.* carries values the Pascal side needs to rebuild a
record, and the emulator ignores them.

get= is what lets this reach past arithmetic. A leaf function's answer is EAX,
but an entity handler returns nothing meaningful - its answer is the entity it
MUTATED. Reading the entity back turns "does it compute the same number" into
"does it leave the same 260 bytes", which is the question that actually matters
for 8,800 lines of handlers.

WHAT IT CANNOT DO. The emulator models the instruction set, not the process -
no Windows, no imports, no VCL - so a function that calls the RTL faults. That
is reported, never skipped silently.

HOW FAR THAT ACTUALLY REACHES was assumed rather than measured, and the
assumption was wrong. The header used to say the case sets were leaf routines
"because that is what the emulator can run", which quietly wrote off the entity
layer - 8,832 lines, the largest and least-verified body of code in the
project. The `handler_probe` and `handler_live` sets went and asked:

    all 78 entity handlers, zeroed entity          78 returned, 0 faulted
    all 78 in four states each, entity ALIVE      312 returned, 0 faulted

The live sweep is the one that counts. A zeroed entity is dead and has no
sprite, so most handlers take an early exit and "nothing faulted" would be a
statement about early exits; the live sweep drives them through real paths with
a sprite handle, HP, timers and velocity. Not one faulted.

AND "NOT ONE FAULTED" IS WEAKER THAN IT SOUNDS. The emu_sanity controls write
through a wild pointer and read through one, and BOTH RETURN - only executing
unmapped memory actually stops the emulator. So an unmapped read yields zero
silently, and a handler reaching a global nobody placed sees 0 and takes a
plausible-looking branch with nothing to announce it. Completing is not the
same as running against sane state, and the first version of this note ran
those two together.

--poison-diff is what settles it, by filling the globals region with 0x00 and
then 0xA5 and diffing: a case whose answer moves depends on memory nobody set
up. Over the live sweep:

    312 cases, 4 moved - all four are type 69

So 308 of 312 read only what the case placed and are trustworthy inputs for
comparison; type 69 reaches a global that has to be mapped before its result
means anything. That is the honest shape of the reach claim - much stronger
than "leaf routines only", and not the blank cheque that "0 faulted" alone
would have been.

What it does NOT yet say is that they AGREE - reaching a handler and having a
Pascal counterpart wired up to compare it against are different jobs, and most
handlers take a TEntityWorld, which is our abstraction over globals the original
reads directly. Each of those has to be mapped before its case can compare.
"""

import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GHIDRA = r'C:\Users\Abdullah\Documents\ghidra_12.0.4_PUBLIC\support\analyzeHeadless.bat'

# Where the game keeps things, from notes/function_map.md.
P_LAYERINFO = 0x00483BF4          # the layer array itself, stride 0x20
ENTITY_AT = 0x60000000            # scratch: somewhere to put a TEntity
ENTITY_INTS = 0x41
RANDOM_SEED_ADDR = 0x0046E040   # Delphi's RandSeed, in BSS

# The globals region: DATA through the end of BSS. --poison fills this with a
# byte so that reading something nobody placed becomes visible.
GLOBALS_LO = 0x00468000
GLOBALS_HI = 0x004A0000

# THE GAME STATE IS A GLOBAL IN THE ORIGINAL, AND A PARAMETER IN OURS.
#
# Our handlers take AGameState because that is the honest way to express a
# dependency in Pascal. The original reads it, every time, through a pointer:
#
#     mov edx, ds:0x46d06c    ; the POINTER, not the value
#     mov edx, [edx]          ; the value
#     sub edx, 0x3c           ; against 60, GS_PLAY
#
# So a case has to place both cells or the emulator reads an unmapped 0 while
# the Pascal is handed 60, and the two run different code while looking like
# they are being compared. That accounted for most of the first sweep's 247
# disagreements.
GAMESTATE_PTR = 0x0046D06C      # the pointer cell
GAMESTATE_AT = 0x60002000       # scratch: where we point it

# THE SOLID-TILE THRESHOLD, and the same class of problem.
#
# Terrain_Configure sets it per terrain; the handlers reach it as
# *PTR_DAT_0046cc44, and that pointer - which IS in the file - resolves to
# 0x00484EF4, exactly where Entities.pas already records it.
#
# Left unplaced it reads 0, and "tile >= 0" is true of every tile, so an
# unmapped tilemap looks SOLID EVERYWHERE. Type 37 was landing and going to
# state 2 on our side while the original stayed airborne at state 1. Terrain 0's
# value is 0x32, so with no tilemap the tiles read 0, nothing is solid, and both
# sides agree about that.
SOLID_THRESHOLD_AT = 0x00484EF4
SOLID_THRESHOLD = 0x32


def ints(vals):
    return ''.join('%08x' % (v & 0xFFFFFFFF) for v in vals)


def le(vals):
    """hex of little-endian int32s, which is what mem= wants"""
    return ''.join(struct.pack('<i', v).hex() for v in vals)


def layer_mem(origin_x=0, origin_y=0, dx=0, dy=0, tw=32, th=32, mx=30, my=24):
    """TLayerInfo: OriginX OriginY DeltaX DeltaY TileW TileH MapTilesX MapTilesY"""
    return 'mem=0x%X:%s' % (P_LAYERINFO,
                            le([origin_x, origin_y, dx, dy, tw, th, mx, my]))


def entity_mem(at=None, **fields):
    """A whole TEntity, zeroed except for the int indices given."""
    raw = [0] * ENTITY_INTS
    for k, v in fields.items():
        raw[int(k[1:])] = v            # keys look like i30
    return 'mem=0x%X:%s' % (ENTITY_AT if at is None else at, le(raw))


ENTITY_B = ENTITY_AT + 0x104          # a second TEntity, right after the first
BOX_A = 0x60001000                    # two bare TBox records
BOX_B = 0x60001100


# --------------------------------------------------------------------------
# case sets
# --------------------------------------------------------------------------

def cases_angle():
    """Angle_Between @ 0x4513E0 vs Directions.AngleBetween. Pure integer."""
    out = ['# Angle_Between(X1,Y1,X2,Y2) - EAX,EDX,ECX then one stack arg']
    span = (-100, -40, -13, -3, -1, 0, 1, 3, 13, 40, 100)
    for dx in span:
        for dy in span:
            out.append('CASE ang_%d_%d 0x4513E0 eax=0 edx=0 ecx=%d stk=%d'
                       % (dx, dy, dx, dy))
    return out


def cases_compare():
    """The three-way compare at 0x45114C. Trivial, but it pins the harness."""
    out = ['# Compare(a,b) @ 0x45114C']
    for a in (-5, -1, 0, 1, 5):
        for b in (-5, -1, 0, 1, 5):
            out.append('CASE cmp_%d_%d 0x45114C eax=%d edx=%d' % (a, b, a, b))
    return out


def cases_edgedist():
    """Entity_TileEdgeDistX/Y vs Entities.TileEdgeDistX/Y.

    Two register arguments - the entity pointer and the delta - and it reaches
    the layer through a global, so both the entity and the layer have to be
    placed in memory first.

    DELTA ZERO IS DELIBERATELY EXCLUDED. The original initialises its result to
    the entity POINTER and only overwrites it in the two signed branches, so a
    zero delta returns an address cast to an integer. Entities.pas returns 0
    instead and says so. Including it here would report a disagreement that is
    a recorded decision rather than a defect - so it is left out on purpose,
    and this comment is why.
    """
    out = ['# Entity_TileEdgeDistX/Y - entity in EAX, delta in EDX']
    lay = layer_mem(origin_x=0x10000 + 7, origin_y=0x10000 + 19)
    for pos in (0x10000, 0x10000 + 100, 0x10000 + 517, 0x10000 - 40):
        for ext in (0, 2, 20, 33):
            for ofs in (0, 3):
                for delta in (-64, -33, -1, 1, 33, 64):
                    ent = entity_mem(i30=pos, i31=pos, i38=ext, i39=ext,
                                     i40=ofs, i41=ofs)
                    tag = 'tedx_%d_%d_%d_%d' % (pos & 0xFFFF, ext, ofs, delta)
                    out.append(
                        'CASE %s 0x457150 eax=0x%X edx=%d %s %s '
                        'f.pos=%d f.ext=%d f.ofs=%d f.delta=%d '
                        'f.ox=%d f.oy=%d f.tile=32'
                        % (tag, ENTITY_AT, delta, lay, ent,
                           pos, ext, ofs, delta, 0x10000 + 7, 0x10000 + 19))
                    out.append(
                        'CASE %s 0x457228 eax=0x%X edx=%d %s %s '
                        'f.pos=%d f.ext=%d f.ofs=%d f.delta=%d '
                        'f.ox=%d f.oy=%d f.tile=32'
                        % (tag.replace('tedx', 'tedy'), ENTITY_AT, delta,
                           lay, ent, pos, ext, ofs, delta,
                           0x10000 + 7, 0x10000 + 19))
    return out


def cases_rect():
    """Rect_Overlap @ 0x451354 vs Entities.RectOverlap.

    Two bare boxes by pointer, plus a per-axis shrink. The original returns the
    flag in AL ONLY - on a hit it builds EAX as CONCAT31(shrinkY >> 8, 1), so
    the upper 24 bits are whatever happened to be in that argument. The
    comparison therefore has to mask to the low byte, and a shrink big enough
    to make those bits non-zero is included on purpose so that a harness which
    forgot to mask would fail here.
    """
    out = ['# Rect_Overlap(A, B, shrinkX, shrinkY) - pointers in EAX, EDX']
    boxes = [(0, 0, 10, 10), (5, 5, 15, 15), (10, 10, 20, 20),
             (-5, -5, 5, 5), (0, 0, 1, 1), (100, 100, 140, 120)]
    for i, a in enumerate(boxes):
        for j, b in enumerate(boxes):
            # A NEGATIVE shrink expands the test instead of tightening it,
            # which is the only way to get a TRUE result whose upper 24 bits
            # are also dirty: the original returns CONCAT31(shrinkY shr 8, 1),
            # so -256 makes those bits 0xFFFFFF. A large positive shrink can
            # never do it - it stops anything overlapping at all, which is how
            # a first version of this quietly failed to exercise the masking.
            for sx, sy in ((0, 0), (2, 2), (0x300, 0x300), (-256, -256)):
                out.append(
                    'CASE rect_%d_%d_%d 0x451354 eax=0x%X edx=0x%X ecx=%d '
                    'stk=%d mem=0x%X:%s mem=0x%X:%s '
                    'f.al=%d f.at=%d f.ar=%d f.ab=%d '
                    'f.bl=%d f.bt=%d f.br=%d f.bb=%d f.sx=%d f.sy=%d'
                    % (i, j, sx, BOX_A, BOX_B, sx, sy,
                       BOX_A, le(list(a)), BOX_B, le(list(b)),
                       a[0], a[1], a[2], a[3], b[0], b[1], b[2], b[3], sx, sy))
    return out


def cases_boxes():
    """Entity_BoxesOverlap @ 0x457F98 vs Entities.EntitiesOverlap.

    Two entities in memory. The SECOND one's extents get multiplied by the two
    scale arguments before its box is built; the first is always used at its
    own size.
    """
    out = ['# Entity_BoxesOverlap(a, b, scaleX, scaleY)']
    base = 0x10000
    for dx in (0, 9, 20, 41):
        for exta in (8, 21):
            for extb in (8, 21):
                for ins in (0, 3):
                    for scale in (1, 2):
                        ea = entity_mem(at=ENTITY_AT, i30=base, i31=base,
                                        i38=exta, i39=exta, i42=ins, i43=ins)
                        eb = entity_mem(at=ENTITY_B, i30=base + dx * 32,
                                        i31=base, i38=extb, i39=extb,
                                        i42=ins, i43=ins)
                        out.append(
                            'CASE box_%d_%d_%d_%d_%d 0x457F98 eax=0x%X '
                            'edx=0x%X ecx=%d stk=%d %s %s '
                            'f.apos=%d f.aext=%d f.ains=%d '
                            'f.bpos=%d f.bext=%d f.bins=%d f.sx=%d f.sy=%d'
                            % (dx, exta, extb, ins, scale, ENTITY_AT,
                               ENTITY_B, scale, scale, ea, eb,
                               base, exta, ins, base + dx * 32, extb, ins,
                               scale, scale))
    return out


def cases_random():
    """Delphi's Random(N) @ 0x402AC4 vs Entities.DelphiRandom.

    Two instructions and a widening multiply, and the game's debris scatter,
    item drops and effect frames all run off it - so reproducing it exactly is
    what makes any of that replayable rather than merely plausible.

    The seed is a global in BSS, which a PE does not store, so each case writes
    it first. That also makes every case independent: the emulator builds a
    fresh machine per call, so the seed is whatever mem= put there.
    """
    out = ["# Delphi Random(N) - N in EAX, seed at 0x0046E040"]
    seeds = [0, 1, 0xDEADBEEF, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 12345]
    for sd in seeds:
        for n in (2, 3, 64, 100, 1000, 0x7FFFFFFF):
            out.append('CASE rnd_%X_%d 0x402AC4 eax=%d mem=0x%X:%s '
                       'f.seed=%d f.n=%d'
                       % (sd, n, n, RANDOM_SEED_ADDR, le([sd if sd < 2**31
                                                          else sd - 2**32]),
                          sd if sd < 2**31 else sd - 2**32, n))
    return out


def cases_handler_pure():
    """The two entity handlers that are pure functions of their entity.

    Type 16 @ 0x0045A944 sets one field. Type 25 @ 0x0045A4F0 indexes a
    three-entry sprite table by EF_VARIANT.

    These are first because they need nothing but an entity: no player
    position, no layer, no pool, no RNG. Everything else in EntityHandlers
    takes a TEntityWorld, which is OUR abstraction over globals the original
    reads directly, and each of those globals has to be placed by hand before
    a handler can be run. Proving the readback path on a handler that needs
    none of that separates "does get= work" from "did I map the globals right".

    THE VARIANT SWEEP IS A PREDICTION, not a regression test. Our type 25
    clamps EF_VARIANT to 0..2; the note beside it says the original indexes
    unchecked. Both cannot be true. Variants 3, 4 and -1 are in the sweep to
    settle it, and are expected to disagree if the note is right.
    """
    out = ['# type 16 @ 0x0045A944 and type 25 @ 0x0045A4F0 - entity in EAX,',
           '# and the whole entity read back afterwards']
    get = 'get=0x%X:%d' % (ENTITY_AT, ENTITY_INTS * 4)
    for v in (0, 1, 2, 3, 4, -1, 7):
        # Outside 0..2 type 25 runs off its table, which DIV-010 declares we do
        # not reproduce. Tagged so those cases invert: they must differ.
        div = '' if 0 <= v <= 2 else ' f.div=10'
        out.append('CASE t16_v%d 0x0045A944 eax=0x%X %s %s f.variant=%d'
                   % (v, ENTITY_AT, entity_mem(i6=v), get, v))
        out.append('CASE t25_v%d 0x0045A4F0 eax=0x%X %s %s f.variant=%d%s'
                   % (v, ENTITY_AT, entity_mem(i6=v), get, v, div))
    return out


def handler_addrs():
    """HANDLER_ADDR out of EntityHandlers.pas: the jump table, by type."""
    src = open(os.path.join(REPO, 'src', 'EntityHandlers.pas'),
               encoding='utf-8').read()
    i = src.index('HANDLER_ADDR: array')
    body = src[src.index('(', i) + 1:src.index(');', i)]
    # Strip the { 0..3 } row comments FIRST. Splitting on ',' and then taking
    # the part before '{' silently ate the entry after every comment - 61
    # handlers instead of 81 - which is the kind of quiet undercount that looks
    # like a finding rather than a bug.
    body = re.sub(r'[{][^}]*[}]', ' ', body)
    out = []
    for tok in body.replace(chr(10), ' ').split(','):
        tok = tok.strip()
        if tok.startswith('$'):
            out.append(int(tok[1:], 16))
    return out


def cases_handler_probe():
    """One call into EVERY handler, to find out which the emulator can run.

    This answers a sizing question rather than a correctness one, and it is
    worth its own set because the answer decides how much of the game this
    technique can ever reach. The emulator models the instruction set, not the
    process - a handler that calls the RTL, or reaches the sprite engine and
    from there DirectDraw, will fault. Which ones those are was unknown, and
    guessing at it is exactly the habit this project is trying to break.

    Every case gets a zeroed entity and a zeroed seed, so a handler that reads
    a global sees zero rather than garbage. That is not a realistic state, and
    it is not meant to be: the question here is only "does it come back".
    """
    out = ['# one call per handler, zeroed entity - reconnaissance, not a diff']
    get = 'get=0x%X:%d' % (ENTITY_AT, ENTITY_INTS * 4)
    for typ, addr in enumerate(handler_addrs()):
        if addr == 0:
            continue
        out.append('CASE probe_t%d 0x%08X eax=0x%X edx=60 %s %s '
                   'mem=0x%X:%s f.probe=%d'
                   % (typ, addr, ENTITY_AT, entity_mem(), get,
                      RANDOM_SEED_ADDR, le([1]), typ))
    return out


def cases_handler_probe_live():
    """The probe again, but with an entity that is ALIVE and mid-behaviour.

    The zeroed probe says every handler returns. That is weaker than it sounds:
    a zeroed entity is dead, has no sprite, and its state and timers are 0, so
    most handlers take an early exit and never reach the code that could fault.
    "Nothing faulted" would then be a statement about the early exits.

    So this drives them down real paths - alive, a sprite handle, non-zero
    state, HP, timers and velocity, several distinct states per handler - and
    asks the same question of code that is actually doing something. The point
    is to make the reach claim survive its own caveat rather than to compare
    anything.
    """
    out = ['# every handler with a LIVE entity in several states']
    get = 'get=0x%X:%d' % (ENTITY_AT, ENTITY_INTS * 4)
    for typ, addr in enumerate(handler_addrs()):
        if addr == 0:
            continue
        for st in (0, 1, 2, 3):
            gs = 60         # GS_PLAY, which is when entities actually run
            solid = SOLID_THRESHOLD
            # Types whose sprite table is shorter than the sweep's range, so
            # an out-of-range state or variant makes the original run off the
            # end of it. DIV-011: we clamp, it does not. Tagged so the case
            # asserts the difference instead of reporting it.
            div = ''
            if (typ, st) in ((2, 3), (7, 2), (14, 2), (38, 2)):
                div = ' f.div=11'
            ent = entity_mem(**{
                'i%d' % 0x00: 3,          # slot
                'i%d' % 0x02: 1,          # alive
                'i%d' % 0x03: typ,        # type
                'i%d' % 0x04: 7,          # a sprite handle
                # NOT st. Variant and state are different fields, and using
                # one number for both pushed type 25 past its three-entry
                # table, so a state sweep reported DIV-010 as a fresh failure.
                'i%d' % 0x06: st % 3,   # variant
                'i%d' % 0x08: st,         # state
                'i%d' % 0x1C: 5,          # timer
                'i%d' % 0x1D: st,         # death timer
                'i%d' % 0x1E: 0x10000 + (40 << 5),   # pos x
                'i%d' % 0x1F: 0x10000 + (30 << 5),   # pos y
                'i%d' % 0x20: 8,          # vel x
                'i%d' % 0x21: -4,         # vel y
                'i%d' % 0x22: 1,          # facing
                'i%d' % 0x24: 3,          # hp
            })
            out.append('CASE live_t%d_s%d 0x%08X eax=0x%X edx=%d %s %s '
                       'mem=0x%X:%s %s mem=0x%X:%s mem=0x%X:%s '
                       'mem=0x%X:%s '
                       'f.probe=%d f.gamestate=%d f.seed=%d f.solid=%d%s'
                       % (typ, st, addr, ENTITY_AT, gs, ent, get,
                          RANDOM_SEED_ADDR, le([12345]), layer_mem(),
                          GAMESTATE_PTR, le([GAMESTATE_AT]),
                          GAMESTATE_AT, le([gs]),
                          SOLID_THRESHOLD_AT, le([solid]),
                          typ, gs, 12345, solid, div))
    return out


def cases_emu_sanity():
    """Negative controls: cases the emulator MUST fault on.

    "78 handlers, 0 faulted" is only worth something if a fault is a thing that
    can happen. If the emulator quietly returned zero for unmapped memory
    instead of stopping, every one of those handlers could have been reading
    garbage and reporting success, and the sweep would have measured nothing.

    So this asks the question directly: write through a wild pointer, read
    through one, and execute an address that is not code. All three must come
    back FAULT. --sanity checks that and exits non-zero if any of them
    RETURNED, which is the failure that matters here.
    """
    wild = 0x11000000        # nothing is mapped there and nothing places it
    return [
        '# negative controls - every one of these must FAULT',
        '# a handler writing through a wild entity pointer',
        'CASE sanity_mustfault_write 0x0045A944 eax=0x%X' % wild,
        '# a handler READING through one',
        'CASE sanity_mustfault_read 0x0045A4F0 eax=0x%X' % wild,
        '# and executing memory that is not code',
        'CASE sanity_mustfault_exec 0x%X eax=0' % wild,
    ]


SETS = {
    'emu_sanity': cases_emu_sanity,
    'handler_probe': cases_handler_probe,
    'handler_live': cases_handler_probe_live,
    'handler_pure': cases_handler_pure,
    'random': cases_random,
    'compare': cases_compare,
    'angle': cases_angle,
    'edgedist': cases_edgedist,
    'rect': cases_rect,
    'boxes': cases_boxes,
}


def run_emulator(work, staged, spec, out, tag=''):
    """One headless run. Returns 0 on success."""
    proj = os.path.join(work, 'proj' + tag)
    os.makedirs(proj, exist_ok=True)
    cmd = [GHIDRA, proj, 'EmuDiff' + tag, '-import', staged, '-noanalysis',
           '-scriptPath', os.path.join(REPO, 'ghidra_scripts'),
           '-postScript', 'EmuDiff.java', spec, out, '-deleteProject']
    r = subprocess.run(cmd, capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if 'EmuDiff:' in line or 'ERROR' in line:
            print('  ' + line.split('> ', 1)[-1].strip())
    if not os.path.exists(out):
        print('the emulator produced no output')
        print(r.stdout[-3000:])
        return 1
    return 0


def answers(path):
    """case name -> everything after the arrow."""
    got = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        if not line.startswith('CASE') or ' -> ' not in line:
            continue
        name = line.split()[1]
        got[name] = line.split(' -> ', 1)[1].strip()
    return got


def poison_diff(work, staged, lines):
    """Run the same cases under two different poison fills and report movers.

    An unmapped read returns zero here rather than faulting - emu_sanity proves
    it - so a handler reaching a global nobody placed sees 0 and takes a
    plausible branch, silently. Two fills turn that silence into a difference:
    a case whose answer is identical under both read only what the case placed;
    a case whose answer MOVED depends on memory nobody set up, and its result
    means nothing until that global is mapped.
    """
    runs = {}
    for byte in (0x00, 0xA5):
        fill = 'fill=0x%X:%d:%d' % (GLOBALS_LO, GLOBALS_HI - GLOBALS_LO, byte)
        poisoned = [(l + ' ' + fill) if l.startswith('CASE') else l
                    for l in lines]
        spec = os.path.join(work, 'spec_%02x.txt' % byte)
        with open(spec, 'w', newline=chr(10)) as fh:
            fh.write(chr(10).join(poisoned) + chr(10))
        out = os.path.join(work, 'out_%02x.txt' % byte)
        print('  poison 0x%02X:' % byte)
        if run_emulator(work, staged, spec, out, tag='p%02x' % byte) != 0:
            return 1
        runs[byte] = answers(out)

    a, b = runs[0x00], runs[0xA5]
    shared = sorted(set(a) & set(b))
    movers = [n for n in shared if a[n] != b[n]]
    print()
    print('%d cases run under both fills' % len(shared))
    if not movers:
        print('none moved - every case read only what it placed itself')
        return 0
    print('%d MOVED - these read memory nobody placed, so their agreement '
          'with the reconstruction (or disagreement) means nothing yet:'
          % len(movers))
    for n in movers[:40]:
        print('  %-24s 0x00 -> %s' % (n, a[n][:60]))
        print('  %-24s 0xA5 -> %s' % ('', b[n][:60]))
    if len(movers) > 40:
        print('  ... and %d more' % (len(movers) - 40))
    return 1


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('sets', nargs='*', default=list(SETS),
                    help='which case sets to run (default: all)')
    ap.add_argument('--gamedir',
                    default=os.path.join(REPO, 'English Translated Version 1.1 (D)'))
    ap.add_argument('--keep', action='store_true',
                    help='keep the work directory')
    ap.add_argument('--sanity', action='store_true',
                    help='also require every sanity_mustfault_* case to FAULT')
    ap.add_argument('--poison-diff', action='store_true',
                    help='run every case twice under two different poison '
                         'fills and report which answers moved - those read a '
                         'global nobody placed')
    ap.add_argument('--poison', type=int, metavar='BYTE',
                    help='fill the globals region with BYTE before each case. '
                         'Run twice with different bytes and diff: any case '
                         'whose answer moved read a global nobody placed.')
    args = ap.parse_args()

    for s in args.sets:
        if s not in SETS:
            print('unknown case set %r; have: %s' % (s, ', '.join(SETS)))
            return 2

    work = tempfile.mkdtemp(prefix='emudiff_')
    try:
        exe = os.path.join(args.gamedir, 'akuji.exe')
        if not os.path.exists(exe):
            print('no akuji.exe under %s' % args.gamedir)
            return 2
        # A path with spaces upsets analyzeHeadless; copy it somewhere plain.
        staged = os.path.join(work, 'orig_akuji.exe')
        shutil.copy(exe, staged)

        lines = []
        for s in args.sets:
            lines += SETS[s]()

        if args.poison is not None:
            # Underneath every case, so an explicit mem= still wins. An unmapped
            # read does NOT fault here - emu_sanity proves it - so without this
            # a handler reading an unplaced global silently sees zero and takes
            # a real-looking branch. Two runs with different bytes turn that
            # silence into a difference.
            fill = 'fill=0x%X:%d:%d' % (GLOBALS_LO, GLOBALS_HI - GLOBALS_LO,
                                        args.poison & 0xFF)
            lines = [(l + ' ' + fill) if l.startswith('CASE') else l
                     for l in lines]
        spec = os.path.join(work, 'spec.txt')
        with open(spec, 'w', newline='\n') as fh:
            fh.write('\n'.join(lines) + '\n')
        ncase = sum(1 for l in lines if l.startswith('CASE'))
        print('%d cases across %d set(s)' % (ncase, len(args.sets)))

        out = os.path.join(work, 'out.txt')
        if run_emulator(work, staged, spec, out) != 0:
            return 1

        if args.poison_diff:
            return poison_diff(work, staged, lines)

        # The negative controls are checked here rather than on the Pascal
        # side, because what they assert is a property of the EMULATOR: that it
        # stops on a bad access instead of inventing a zero.
        sane = 0
        if args.sanity:
            bad = []
            for line in open(out, encoding='utf-8', errors='replace'):
                if 'sanity_mustfault_' not in line:
                    continue
                sane += 1
                if '-> FAULT' not in line:
                    bad.append(line.strip())
            if sane == 0:
                print('  --sanity asked for, but no control cases were run '
                      '(add the emu_sanity set)')
                return 1
            if bad:
                print('  %d of %d controls RETURNED instead of faulting - the '
                      'emulator is not stopping on bad access, so "0 faulted" '
                      'elsewhere means nothing:' % (len(bad), sane))
                for b in bad:
                    print('    %s' % b[:160])
                return 1
            print('  %d negative controls all faulted, as they must' % sane)

        rec = subprocess.run([os.path.join(REPO, 'src', 'akuji.exe'),
                              '--emudiff', out], capture_output=True, text=True)
        log = os.path.join(REPO, 'src', 'selftest.log')
        if os.path.exists(log):
            print()
            print(open(log, encoding='utf-8', errors='replace').read().strip())
        return rec.returncode
    finally:
        if args.keep:
            print('\nwork kept at %s' % work)
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
