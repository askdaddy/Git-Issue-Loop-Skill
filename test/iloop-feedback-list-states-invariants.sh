#!/usr/bin/env bash
# Black-box checks for Issue #94: `feedback.sh list` must let a caller tell
# "nothing pending" apart from "reported-only queue" and "empty queue".
#
# The contract is split by stream: stdout keeps the historical "0" (so every
# caller that tests `out == "0"` keeps working), while stderr carries a hint
# naming how many entries exist outside the requested scope.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FB="${ROOT}/scripts/feedback.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

make_entry() {
  local dir="$1" id="$2" status="$3" summary="$4"
  mkdir -p "$dir/entries"
  {
    printf -- '- schema: 2\n'
    printf -- '- id: %s\n' "$id"
    printf -- '- category: doc\n'
    printf -- '- summary: %s\n' "$summary"
    printf -- '- status: %s\n' "$status"
  } > "$dir/entries/${id}.md"
}

run_list() {
  local dir="$1"; shift
  ( ILOOP_FEEDBACK_DIR="$dir" bash "$FB" list "$@" 2>"$WORK/err.txt" )
}

# ---------------------------------------------------------------------------
# (1) a missing queue directory stays silent and prints "0"
# ---------------------------------------------------------------------------
out="$(run_list "$WORK/missing" || true)"
[[ "$out" == "0" ]] && pass "missing queue prints 0" || fail "missing queue printed '$out'"
[[ ! -s "$WORK/err.txt" ]] && pass "missing queue says nothing on stderr" \
  || fail "missing queue wrote stderr: $(cat "$WORK/err.txt")"

# ---------------------------------------------------------------------------
# (2) an existing but empty queue is identical to a missing one
# ---------------------------------------------------------------------------
mkdir -p "$WORK/empty/entries"
out="$(run_list "$WORK/empty" || true)"
[[ "$out" == "0" ]] && pass "empty queue prints 0" || fail "empty queue printed '$out'"
[[ ! -s "$WORK/err.txt" ]] && pass "empty queue says nothing on stderr" \
  || fail "empty queue wrote stderr"

# ---------------------------------------------------------------------------
# (3) reported-only queue: still "0" on stdout, but distinguishable on stderr
# ---------------------------------------------------------------------------
make_entry "$WORK/reported" "20260101T000000Z-aaaa" reported "only-reported"
out="$(run_list "$WORK/reported" || true)"
[[ "$out" == "0" ]] && pass "reported-only queue keeps 0 on stdout" \
  || fail "reported-only queue changed stdout to '$out'"
if grep -q '1' "$WORK/err.txt" && grep -q 'list all' "$WORK/err.txt"; then
  pass "reported-only queue hints at the hidden entry on stderr"
else
  fail "reported-only queue gave no usable hint: $(cat "$WORK/err.txt")"
fi

# (4) dismissed entries count too
make_entry "$WORK/dismissed" "20260101T000000Z-bbbb" dismissed "only-dismissed"
out="$(run_list "$WORK/dismissed" || true)"
[[ "$out" == "0" ]] && gref=1 || gref=0
if [[ "$gref" -eq 1 ]] && grep -q '1' "$WORK/err.txt"; then
  pass "dismissed-only queue keeps 0 and still hints"
else
  fail "dismissed-only queue: stdout=[$out] stderr=$(cat "$WORK/err.txt")"
fi

# ---------------------------------------------------------------------------
# (5) a pending entry lists normally and the hint is silent
# ---------------------------------------------------------------------------
make_entry "$WORK/pending" "20260102T000000Z-cccc" pending "listed-entry"
make_entry "$WORK/pending" "20260101T000000Z-dddd" reported "hidden-entry"
out="$(run_list "$WORK/pending" || true)"
case "$out" in
  *"20260102T000000Z-cccc"*) pass "pending entry is still listed normally" ;;
  *) fail "pending entry missing from output: $out" ;;
esac
case "$out" in
  *"20260101T000000Z-dddd"*) fail "reported entry leaked into the pending listing" ;;
  *) pass "reported entry stays out of the pending listing" ;;
esac
[[ ! -s "$WORK/err.txt" ]] && pass "no hint when something is actually pending" \
  || fail "hint shown despite a pending entry: $(cat "$WORK/err.txt")"

# ---------------------------------------------------------------------------
# (6) `list all` shows every entry and never hints
# ---------------------------------------------------------------------------
out="$(run_list "$WORK/reported" all || true)"
case "$out" in
  *"20260101T000000Z-aaaa"*) pass "list all shows reported entries" ;;
  *) fail "list all hid the reported entry: $out" ;;
esac
[[ ! -s "$WORK/err.txt" ]] && pass "list all never hints" \
  || fail "list all wrote stderr"

# ---------------------------------------------------------------------------
# (7) the reverse check: the hint is what makes (3) pass, not the word "0"
# ---------------------------------------------------------------------------
if grep -q 'list all' "$FB"; then
  pass "hint text is present in the implementation"
else
  fail "implementation has no hint text (reported-only would look like empty)"
fi

echo "----------------------------------------"
if [[ "$FAILS" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
fi
echo "FAILURES: $FAILS"
exit 1
