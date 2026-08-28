#!/usr/bin/env bash
# Mutation testing: apply a deliberate defect, rebuild, and require the gate to
# NOTICE. A check that cannot fail is not a check.
#
# Usage:  tools/mutate.sh <mutations-file> [game dir]
#
# The mutations file is a series of records separated by lines of '==='.
# Each record is:
#
#     name of the mutation
#     path/to/file.pas
#     ---
#     the exact text to replace (one or more lines)
#     --->
#     what to replace it with (one or more lines)
#
# Everything below is scar tissue from a run that went wrong, and each guard is
# load-bearing:
#
#   * A LOCK. Two copies of the previous script ran at once, each restoring the
#     other's mutation over the top. The tree ended up with two live defects and
#     a BACKUP that already contained one, so the backup could not be trusted to
#     recover it; that took a reset to HEAD and a replay of the patch script
#     that had generated the work.
#
#   * A TIMEOUT on the test run. A mutation that turns a loop bound into
#     `while Row <= Row` does not make the self-test fail, it makes it HANG, and
#     the suite blocked silently for twenty minutes behind one stuck process
#     holding a lock on akuji.exe. A hang is a kill, not a wait.
#
#   * A VERIFIED RESTORE. After putting a file back, compare it against the
#     baseline and stop the run outright if it differs. Continuing from a bad
#     restore is what turned one problem into three.
#
#   * STRAY PROCESS CLEANUP. A hung akuji.exe keeps the executable locked, and
#     every later build then fails with "Can't create object file", which reads
#     like a compile error and is not one.
#
#   * Restores COPY the baseline back. Never `git checkout` - on an untracked
#     file that silently does nothing, which once left a mutation live through a
#     run that reported PASSED.

set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME="${2:-$REPO/English Translated Version 1.1 (D)}"
LAZBUILD="${LAZBUILD:-/e/lazarus/lazbuild.exe}"
TEST_TIMEOUT="${TEST_TIMEOUT:-120}"
SELFTEST="${SELFTEST:---selftest-entities}"
SPEC="${1:-}"

if [ -z "$SPEC" ] || [ ! -f "$SPEC" ]; then
    echo "usage: tools/mutate.sh <mutations-file> [game dir]" >&2
    exit 2
fi

LOCK="$REPO/.mutate.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "FAIL: $LOCK exists - another mutation run is in progress." >&2
    echo "      If you are certain there is not, remove it and try again." >&2
    exit 2
fi

BASE="$(mktemp -d 2>/dev/null || echo "${TEMP:-/tmp}/mutate_base_$$")"
mkdir -p "$BASE"

FILES=""

kill_strays() {
    if command -v taskkill >/dev/null 2>&1; then
        taskkill //F //IM akuji.exe >/dev/null 2>&1 || true
    else
        pkill -f 'akuji.exe' >/dev/null 2>&1 || true
    fi
}

baseline() {
    local f="$1"
    case " $FILES " in
        *" $f "*) return ;;
    esac
    FILES="$FILES $f"
    mkdir -p "$BASE/$(dirname "$f")"
    cp "$REPO/$f" "$BASE/$f"
}

restore_all() {
    local f
    for f in $FILES; do
        cp "$BASE/$f" "$REPO/$f"
    done
}

restore_ok() {
    local f
    for f in $FILES; do
        cmp -s "$BASE/$f" "$REPO/$f" || return 1
    done
    return 0
}

cleanup() {
    restore_all
    kill_strays
    rmdir "$LOCK" 2>/dev/null
}
trap cleanup EXIT INT TERM

apply() {  # file old new
    python - "$REPO/$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(path, 'rb').read()
crlf = b'\r\n' in raw
s = raw.decode('utf-8').replace('\r\n', '\n')
if s.count(old) != 1:
    sys.stderr.write('anchor matched %d times\n' % s.count(old))
    sys.exit(1)
s = s.replace(old, new)
if crlf:
    s = s.replace('\n', '\r\n')
open(path, 'wb').write(s.encode('utf-8'))
PY
}

pass=0; fail=0; skipped=0

run_one() {  # name file old new
    local name="$1" file="$2" old="$3" new="$4" rc

    baseline "$file"
    if ! apply "$file" "$old" "$new"; then
        printf '  %-46s COULD NOT APPLY\n' "$name"
        skipped=$((skipped + 1))
        restore_all
        return
    fi

    kill_strays
    if ! "$LAZBUILD" -B "$REPO/src/akuji.lpi" > /dev/null 2>&1; then
        # A mutation that will not compile is still one the gate caught.
        printf '  %-46s killed (build)\n' "$name"
        pass=$((pass + 1))
    else
        timeout "$TEST_TIMEOUT" "$REPO/src/akuji.exe" "$SELFTEST" "$GAME" > /dev/null 2>&1
        rc=$?
        if [ "$rc" -eq 0 ]; then
            printf '  %-46s SURVIVED\n' "$name"
            fail=$((fail + 1))
        elif [ "$rc" -eq 124 ]; then
            printf '  %-46s killed (hung)\n' "$name"
            pass=$((pass + 1))
        else
            printf '  %-46s killed\n' "$name"
            pass=$((pass + 1))
        fi
    fi

    kill_strays
    restore_all
    if ! restore_ok; then
        echo "FAIL: the restore did not put the tree back. Stopping before" >&2
        echo "      that spreads into the next mutation." >&2
        exit 3
    fi
}

echo "=== mutation testing: $(basename "$SPEC") ==="

# One record per line with every field base64'd: the old and new text are
# multi-line by nature and would otherwise break a line-oriented read.
python - "$SPEC" <<'PY' > "$BASE/parsed"
import sys, base64
# Windows Python turns every print into CRLF on a redirected stdout, which
# leaves a stray carriage return on the last field of every record and makes
# base64 refuse to decode it.
sys.stdout.reconfigure(newline='\n')
text = open(sys.argv[1], encoding='utf-8').read().replace('\r\n', '\n')
def enc(x):
    return base64.b64encode(x.encode('utf-8')).decode('ascii')
for rec in text.split('\n===\n'):
    rec = rec.strip('\n')
    if not rec.strip():
        continue
    head, _, body = rec.partition('\n---\n')
    old, _, new = body.partition('\n--->\n')
    lines = head.strip().split('\n')
    print(' '.join(enc(v) for v in (lines[0].strip(), lines[1].strip(), old, new)))
PY

d64() { printf '%s' "$1" | base64 -d; }

while read -r n_b f_b o_b w_b; do
    [ -z "${n_b:-}" ] && continue
    w_b="${w_b%$'\r'}"          # belt and braces against a stray carriage return
    run_one "$(d64 "$n_b")" "$(d64 "$f_b")" "$(d64 "$o_b")" "$(d64 "$w_b")"
done < "$BASE/parsed"

restore_all
kill_strays
"$LAZBUILD" -B "$REPO/src/akuji.lpi" > /dev/null 2>&1

echo
echo "killed $pass, survived $fail, could not apply $skipped"
if [ "$fail" -ne 0 ] || [ "$skipped" -ne 0 ]; then
    exit 1
fi
echo "every mutation was caught"
