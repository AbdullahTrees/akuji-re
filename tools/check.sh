#!/usr/bin/env bash
# Build the reconstruction and run every check. Exits non-zero if anything fails.
#
# Use it as a commit gate:
#
#     tools/check.sh && git commit -m "..."
#
# The point is that it is ONE command, so a broken build cannot slip through a
# shell chain. That has happened twice: a run piped through `tail` reported the
# pipe's exit status instead of the program's and made a failing --selftest look
# green, and a `;` between the build and the commit let non-compiling source get
# committed. Both were invisible at a glance.
#
# It also fixes the quoting. The game directory has spaces in its name, and an
# unquoted expansion word-splits it - which has produced both false passes (a
# self-test that loaded nothing and had no way to fail) and false failures.
#
# Usage: tools/check.sh [game dir]

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME="${1:-$REPO/English Translated Version 1.1 (D)}"
LAZBUILD="${LAZBUILD:-/e/lazarus/lazbuild.exe}"
SCRATCH="$(mktemp -d 2>/dev/null || echo "${TEMP:-/tmp}/akuji_check_$$")"
mkdir -p "$SCRATCH"

fail=0
note() { printf '%s\n' "$*"; }

if [ ! -d "$GAME/data" ]; then
    note "FAIL: no game data at: $GAME"
    note "      pass the game directory as the first argument"
    exit 2
fi

note "=== build ==="
if ! "$LAZBUILD" "$REPO/src/akuji.lpi" > "$SCRATCH/build.log" 2>&1; then
    note "FAIL: build"
    grep -iE "error|fatal" "$SCRATCH/build.log" | head -20
    exit 1
fi
grep -E "lines compiled" "$SCRATCH/build.log" | tail -1

# Warnings are not fatal, but they should be seen rather than buried.
if grep -qiE "^\S+\([0-9]+,[0-9]+\) (Warning|Error)" "$SCRATCH/build.log"; then
    note "--- compiler warnings ---"
    grep -iE "^\S+\([0-9]+,[0-9]+\) (Warning|Error)" "$SCRATCH/build.log" | head -10
fi

EXE="$REPO/src/akuji.exe"

# akuji.exe is a GUI-subsystem binary: it writes src/selftest.log and prints
# nothing to stdout. Read the log AND the unpiped exit code - never pipe the run
# itself, or $? belongs to the pipe.
run() {
    local name="$1"; shift
    rm -f "$REPO/src/selftest.log"
    "$EXE" "$name" "$@" > /dev/null 2>&1
    local rc=$?
    local last=""
    [ -f "$REPO/src/selftest.log" ] && last="$(grep -E '^(OK|FAILED)' "$REPO/src/selftest.log" | tail -1)"
    printf '  %-22s exit=%d  %s\n' "$name" "$rc" "$last"
    [ $rc -ne 0 ] && fail=1
    return 0
}

note ""
note "=== self-tests ==="
run --selftest          "$GAME/bmp.qda" "$SCRATCH"
run --selftest-audio    "$GAME"
run --selftest-midi     "$GAME"
run --selftest-dir      "$GAME"
run --selftest-events   "$GAME"
run --selftest-script   "$GAME"
run --selftest-stages   "$GAME"
run --selftest-player   "$GAME"
run --selftest-trace    "$GAME"
run --selftest-entities "$GAME"
run --selftest-runner   "$GAME"
run --selftest-session  "$GAME"
run --selftest-settings "$GAME" "$SCRATCH"

note ""
note ""
note "=== how much is CODE, not commentary ==="
python "$REPO/tools/implemented.py" 2>/dev/null | tail -4 | sed 's/^/  /'
note ""
note "=== reference implementations ==="
ref() {
    local name="$1"; shift
    python "$REPO/tools/$name.py" "$@" > /dev/null 2>&1
    local rc=$?
    printf '  %-22s exit=%d\n' "$name" "$rc"
    [ $rc -ne 0 ] && fail=1
    return 0
}
mkdir -p "$SCRATCH/pcm"
rm -f "$REPO/src/selftest.log"
"$EXE" --selftest-audio "$GAME" "$SCRATCH/pcm" > /dev/null 2>&1
ref decode_wav_ref  "$GAME" "$SCRATCH/pcm"
ref parse_midi_ref  "$GAME"
ref analyse_events  "$GAME"

# The x87 models. `check` is the one behind ScaleByPercent; `ending` prints the
# two counters at which the ending screen's percentage comes out a point low,
# and src/Ending.pas carries those two as a literal - so this is the second
# reader that says the literal is right.
ref x87_sim check

# The two builds of akuji.exe. The claim src/ leans on is that no INSTRUCTION
# differs between them - so every oddity reproduced here is the author's and
# not a translator's patch. --strict fails if a differing run outside .rsrc
# stops being a string.
if [ -f "$REPO/akuji_ver101/akuji.exe" ]; then
    ref bindiff --strict
else
    printf '  %-22s skipped - akuji_ver101 is not present
' "bindiff"
fi
python "$REPO/tools/x87_sim.py" ending > "$SCRATCH/ending.log" 2>&1
if grep -q '(212, 236)' "$SCRATCH/ending.log"; then
    printf '  %-22s exit=0  the two ending deviations still are 212 and 236
'         "x87_sim ending"
else
    printf '  %-22s FAILED  the ending deviations moved
' "x87_sim ending"
    fail=1
fi

note ""
note "=== records agree with the database ==="
# function_map.md is the meaning authority, game_functions.txt the address
# authority. If they disagree, one is stale and reading cannot tell you which.
python "$REPO/tools/check_function_map.py" > "$SCRATCH/fmap.log" 2>&1
rc=$?
printf '  %-22s exit=%d  %s\n' "function_map" "$rc" \
    "$(grep -E '^(OK|FAILED)' "$SCRATCH/fmap.log" | tail -1)"
[ $rc -ne 0 ] && { fail=1; grep -E '^  0x' "$SCRATCH/fmap.log" | head -10; }

note ""
note "=== scalar constants appear in their own handler's code ==="
# The 181 pins cover const ARRAYS; nothing covered the loose velocities and
# gravities. Three were wrong the same way - a negative literal transcribed
# as its low byte, so -$B0 for 0xFFFFFFB0, which is really -$50.
python "$REPO/tools/const_immediates.py" > "$SCRATCH/consts.log" 2>&1
rc=$?
printf '  %-22s exit=%d  %s
' "const_immediates" "$rc"     "$(grep -E 'scalar constants checked' "$SCRATCH/consts.log" | tail -1)"
[ $rc -ne 0 ] && { fail=1; grep -B1 'fold IS present' "$SCRATCH/consts.log" | head -8; }

note ""
note "=== the frame loop still has the shape the real game has ==="
# The defect this guards was a wrong PLACE, not a wrong value, and all
# thirteen behavioural self-tests passed both before and after the fix - they
# drive a session directly and never touch the frame loop's structure.
python "$REPO/tools/frame_shape.py" > "$SCRATCH/frame.log" 2>&1
rc=$?
printf '  %-22s exit=%d  %s
' "frame_shape" "$rc"     "$(tail -1 "$SCRATCH/frame.log")"
[ $rc -ne 0 ] && { fail=1; cat "$SCRATCH/frame.log" | head -8; }

note ""
note "=== table lengths are pinned from OUTSIDE the table ==="
# The 181 value-pins in --selftest-entities cannot catch a short table: the
# count they check with comes from the array being checked. This bounds each
# table by the address of the next one instead.
python "$REPO/tools/table_extents.py" > "$SCRATCH/extents.log" 2>&1
rc=$?
printf '  %-22s exit=%d  %s
' "table_extents" "$rc"     "$(grep -E 'flush against' "$SCRATCH/extents.log" | tail -1 | sed 's/^ *//')"
[ $rc -ne 0 ] && { fail=1; sed -n '/OVERRUNS/,$p' "$SCRATCH/extents.log" | head -10; }

note ""
note "=== the Ghidra scripts still compile ==="
# analyzeHeadless compiles a script at run time, so a typo in EmuDiff.java
# only surfaces two minutes into a headless run. javac says it in a second,
# and says it against the real API rather than my memory of it.
bash "$REPO/tools/javac_check.sh" || fail=1

note ""
note "=== the divergence ledger agrees with the source ==="
# Every place we knowingly differ from the binary has to be written down. This
# cannot find an UNdeclared divergence - only the differential tests can - but
# it stops a declared one rotting, and it refuses to let a mistranslation be
# filed as an acceptable difference instead of being fixed.
python "$REPO/tools/divergences.py" > "$SCRATCH/div.log" 2>&1
rc=$?
printf '  %-22s exit=%d  %s
' "divergences" "$rc"     "$(grep -E '^[0-9]+ divergences' "$SCRATCH/div.log" | tail -1)"
[ $rc -ne 0 ] && { fail=1; sed -n '/^FAIL/,$p' "$SCRATCH/div.log" | head -12; }

note ""
note "=== negative control: a wrong directory must FAIL ==="
rm -f "$REPO/src/selftest.log"
"$EXE" --selftest-script "$SCRATCH/definitely-not-here" > /dev/null 2>&1
rc=$?
printf '  %-22s exit=%d  %s\n' "bad game dir" "$rc" \
    "$([ $rc -ne 0 ] && echo 'good, it failed' || echo 'BAD - a test that cannot fail is not a test')"
[ $rc -eq 0 ] && fail=1

rm -rf "$SCRATCH"
note ""
if [ $fail -eq 0 ]; then
    note "ALL CHECKS PASSED"
    exit 0
fi
note "CHECKS FAILED"
exit 1
