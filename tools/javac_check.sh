#!/usr/bin/env bash
# Compile the Ghidra scripts against the install's own jars.
#
# analyzeHeadless compiles a script at run time, so a typo in EmuDiff.java only
# surfaces two minutes into a headless run, buried in Ghidra's log. javac says
# the same thing in a second, and says it against the REAL API rather than
# against my memory of it - which is the point: the emulator API is not
# something to guess at.
set -u
GHIDRA="${GHIDRA_HOME:-/c/Users/Abdullah/Documents/ghidra_12.0.4_PUBLIC}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$GHIDRA/Ghidra" ]; then
    echo "  javac_check           SKIP - no Ghidra at $GHIDRA"
    exit 0
fi
if ! command -v javac > /dev/null 2>&1; then
    echo "  javac_check           SKIP - no javac on PATH"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

find "$GHIDRA/Ghidra" -name '*.jar' | while read -r f; do cygpath -w "$f"; done \
    > "$TMP/cp.txt"
CP="$(paste -sd';' "$TMP/cp.txt")"

rc=0
for f in "$HERE"/ghidra_scripts/*.java; do
    if ! javac -nowarn -proc:none -cp "$CP" -d "$TMP/out" "$f" \
            > "$TMP/err.log" 2>&1; then
        echo "  $(basename "$f")  FAILED"
        grep -E '^\S+\.java:[0-9]+: error' "$TMP/err.log" | head -6
        rc=1
    fi
done
[ $rc -eq 0 ] && echo "  ghidra scripts        all $(ls "$HERE"/ghidra_scripts/*.java | wc -l | tr -d ' ') compile"
exit $rc
