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
