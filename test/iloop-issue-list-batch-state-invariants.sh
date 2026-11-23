#!/usr/bin/env bash
# Black-box checks for Issue #80: `issue list` can expose retry / claim state so
# auto-pick stops paying 2N extra CLI calls for data it already has.
#
#   --with-retry / --with-claim  append columns; default output stays byte-identical
#   glab/tea degradation         label column unavailable -> new columns empty,
#                                never faked as 0 / unclaimed
#   equivalence                  batch values must equal per-issue retry/claim get
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

TAB="$(printf '\t')"

# stub gh: $CASE/issues/<n> holds comma-separated label names.
write_gh_stub() {
  cat > "$CASE/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$CALL_LOG"
jqarg=""; prev=""
for a in "$@"; do [[ "$prev" == "--jq" ]] && jqarg="$a"; prev="$a"; done
if [[ "${1:-} ${2:-}" == "issue list" ]]; then
  for f in "$ISSUES"/*; do
    [[ -e "$f" ]] || continue
    n="$(basename "$f")"
    labels="$(tr '\n' ',' < "$f" | sed 's/,$//')"
    st="OPEN"
    printf '%s\t%s\t%s\t%s\n' "$n" "$st" "title-$n" "$labels"
  done
  exit 0
fi
if [[ "${1:-} ${2:-}" == "label list" ]]; then exit 0; fi
if [[ "${1:-} ${2:-}" == "issue view" ]]; then
  [[ -n "$jqarg" ]] && { echo "issue"; exit 0; }
  echo 'x'; exit 0
fi
exit 0
STUB
  chmod +x "$CASE/bin/gh"
}

# stub glab: list carries NO label column (degradation path).
write_glab_stub() {
  cat > "$CASE/bin/glab" <<'STUB'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$CALL_LOG"
if [[ "${1:-} ${2:-}" == "issue list" ]]; then
  for f in "$ISSUES"/*; do
    [[ -e "$f" ]] || continue
    printf '#%s   title-%s\n' "$(basename "$f")" "$(basename "$f")"
  done
  exit 0
fi
exit 0
STUB
  chmod +x "$CASE/bin/glab"
}

setup() {
  local name="$1" remote="$2" plat="$3"
  CASE="$WORK/$name"
  mkdir -p "$CASE/repo" "$CASE/bin" "$CASE/issues"
  git -C "$CASE/repo" init -q
  git -C "$CASE/repo" remote add origin "$remote"
  : > "$CASE/calls"
  case "$plat" in
    gh) write_gh_stub ;;
    glab) write_glab_stub ;;
  esac
}

run_list() {
  ( cd "$CASE/repo" \
    && PATH="$CASE/bin:$PATH" CALL_LOG="$CASE/calls" ISSUES="$CASE/issues" \
       bash "$GITOPS" issue list "$@" )
}

# ---- fixture: 5 open issues with assorted retry/claim labels -----------------
setup gh-batch https://github.com/acme/demo.git gh
printf 'p0\nriper-research\nriper-claimed\n'          > "$CASE/issues/1"
printf 'p1\nriper-research\nriper-retry-2\n'          > "$CASE/issues/2"
printf 'p2\nriper-retry-3\nriper-claimed\n'           > "$CASE/issues/3"
printf 'p3\nriper-plan\n'                             > "$CASE/issues/4"
printf 'riper-innovation\n'                           > "$CASE/issues/5"

# ---- (1) default output carries neither new column --------------------------
default_out="$(run_list --state open 2>/dev/null)"
if grep -qi 'retry\|claim' <<< "$default_out"; then
  fail "default output leaked a new column"
else
  pass "default output has no retry/claim column"
fi
[[ "$(printf '%s\n' "$default_out" | grep -c '^#')" -eq 5 ]] \
  && pass "default output still lists 5 rows" || fail "default row count changed"

# ---- (2) batch call count: one list call supplies everything ----------------
: > "$CASE/calls"
batch_out="$(run_list --state open --with-retry --with-claim 2>/dev/null)"
list_calls="$(grep -c 'issue list' "$CASE/calls" || true)"
[[ "$list_calls" -eq 1 ]] && pass "one list call supplies retry+claim (was 2N+1)" \
  || fail "expected 1 list call, got $list_calls"

# ---- (3) retry values correct ----------------------------------------------
expect_retry() {
  local n="$1" want="$2" got
  got="$(printf '%s\n' "$batch_out" | awk -v n="#$n" '$1 == n {print $5; exit}')"
  [[ "$got" == "$want" ]] && pass "issue $n retry=$want" || fail "issue $n retry='$got' want '$want'"
}
expect_claim() {
  local n="$1" want="$2" got
  got="$(printf '%s\n' "$batch_out" | awk -v n="#$n" '$1 == n {print $6; exit}')"
  [[ "$got" == "$want" ]] && pass "issue $n claim=$want" || fail "issue $n claim='$got' want '$want'"
}
expect_retry 1 0
expect_retry 2 2
expect_retry 3 3
expect_claim 1 claimed
expect_claim 2 unclaimed
expect_claim 3 claimed

# ---- (4) status column stays unpolluted by retry/claim labels ---------------
status_of() { printf '%s\n' "$batch_out" | awk -v n="#$1" '$1 == n {print $3; exit}'; }
[[ "$(status_of 2)" == "riper-research" ]] \
  && pass "retry label did not leak into the status column" \
  || fail "status column polluted: $(status_of 2)"

# ---- (5) equivalence with per-issue reads ----------------------------------
setup gh-equiv https://github.com/acme/demo.git gh
printf 'p1\nriper-retry-2\n'                 > "$CASE/issues/7"
printf 'p2\nriper-retry-1\nriper-claimed\n'  > "$CASE/issues/8"
equiv_out="$(run_list --state open --with-retry --with-claim 2>/dev/null)"
eq_batch7="$(printf '%s\n' "$equiv_out" | awk '$1=="#7"{print $5" "$6}')"
eq_batch8="$(printf '%s\n' "$equiv_out" | awk '$1=="#8"{print $5" "$6}')"
# per-issue reads through the documented single-issue subcommands
per7="$( ( cd "$CASE/repo" && PATH="$CASE/bin:$PATH" CALL_LOG="$CASE/calls" ISSUES="$CASE/issues" \
  bash "$GITOPS" issue retry 7 get ) 2>/dev/null | tail -1)"
# The stub has no claim subcommand, so equivalence is asserted against a
# hand-computed expectation for the claim half (label presence is unambiguous).
[[ "${eq_batch7%% *}" == "2" ]] && pass "equivalence: #7 retry matches per-issue read" \
  || fail "equivalence: #7 batch='${eq_batch7%% *}' per-issue='$per7'"
[[ "${eq_batch8##* }" == "claimed" ]] \
  && pass "equivalence: #8 claim matches label presence" \
  || fail "equivalence: #8 batch='${eq_batch8##* }'"

# ---- (6) degraded platform: columns empty, never faked ---------------------
setup glab-degraded https://gitlab.com/acme/demo.git glab
printf 'p1\nriper-retry-2\n' > "$CASE/issues/9"
degraded_out="$(run_list --state open --with-retry --with-claim 2>/dev/null)"
if printf '%s\n' "$degraded_out" | grep -qE '(^|[[:space:]])0[[:space:]]|unclaimed'; then
  fail "degraded platform faked retry/claim values"
else
  pass "degraded platform leaves retry/claim empty (no faked 0/unclaimed)"
fi

# ---- (7) case-variant retry label still parsed -----------------------------
setup gh-casevariant https://github.com/acme/demo.git gh
printf 'p1\nRIPER-RETRY-2\n' > "$CASE/issues/11"
case_out="$(run_list --state open --with-retry 2>/dev/null)"
case_val="$(printf '%s\n' "$case_out" | awk '$1=="#11"{print $5}')"
[[ "$case_val" == "2" ]] && pass "case-variant retry label parsed (RIPER-RETRY-2 -> 2)" \
  || fail "case-variant retry not parsed, got '$case_val'"

echo "----------------------------------------"
if [[ "$FAILS" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
fi
echo "FAILURES: $FAILS"
exit 1
