#!/usr/bin/env bash
# Black-box contract checks for Issue #24 (riper-claimed issue claim mutex).
# Verifies, from the CLI boundary only (stub gh + throwaway repo):
#   - labels init / doctor manage 15 built-in labels incl. riper-claimed, and
#     doctor fails closed when riper-claimed is missing;
#   - `issue claim <N> get|claim|release` reads/writes the non-exclusive label,
#     posts an audit comment carrying the four payload fields, refuses to
#     preempt an existing claim, and releases idempotently;
#   - `issue list` never leaks riper-claimed into the status column;
#   - `issue label add riper-claimed` is blocked (must use the claim subcommand);
#   - claiming leaves the priority / status families untouched.
# Run from repository root: bash test/iloop-claim-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/proj" "$WORK/lab"
git -C "$WORK/proj" init -q
git -C "$WORK/proj" remote add origin https://github.com/o/r.git
git -C "$WORK/proj" config user.name "smoke-user"
git -C "$WORK/proj" config user.email "smoke@example.com"

# --- stub gh: state-backed repo labels + per-issue labels + comment log ------
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-} ${2:-}" == "auth status" ]] && exit 0
if [[ "${1:-} ${2:-}" == "label list" ]]; then
  cat "${REPO_LABELS:-/dev/null}" 2>/dev/null; exit 0
fi
if [[ "${1:-} ${2:-}" == "label create" ]]; then
  name="${3:-}"
  if grep -Fxq -- "${name}" "${REPO_LABELS:-/dev/null}" 2>/dev/null; then exit 1; fi
  printf '%s\n' "${name}" >> "${REPO_LABELS:-/dev/null}"; exit 0
fi
if [[ "${1:-} ${2:-}" == "label edit" ]]; then
  name="${3:-}"
  grep -Fxq -- "${name}" "${REPO_LABELS:-/dev/null}" 2>/dev/null && exit 0 || exit 1
fi
if [[ "${1:-} ${2:-}" == "issue list" ]]; then
  while IFS="$(printf '\t')" read -r n s t; do
    [[ -z "${n:-}" ]] && continue
    labs=""; [[ -f "${GH_LABELDIR:-/dev/null}/$n" ]] && labs="$(paste -sd, "${GH_LABELDIR:-/dev/null}/$n" 2>/dev/null)"
    printf '%s\t%s\t%s\t%s\n' "$n" "$s" "$t" "$labs"
  done < "${GH_ISSUES:-/dev/null}"; exit 0
fi
if [[ "${1:-} ${2:-}" == "issue view" ]]; then
  num="${3:-}"; [[ -f "${GH_LABELDIR:-/dev/null}/$num" ]] && cat "${GH_LABELDIR:-/dev/null}/$num"; exit 0
fi
if [[ "${1:-} ${2:-}" == "issue edit" ]]; then
  num="${3:-}"; shift 3; f="${GH_LABELDIR:-/dev/null}/$num"; mode=""
  for a in "$@"; do case "$a" in
    --add-label) mode="add" ;; --remove-label) mode="rem" ;;
    *) [[ -n "$mode" ]] && { case "$mode" in
         add) grep -Fxq -- "$a" "$f" 2>/dev/null || echo "$a" >> "$f" ;;
         rem) grep -vxF -- "$a" "$f" > "$f.tmp" 2>/dev/null || true; mv "$f.tmp" "$f" ;;
       esac; mode=""; } ;;
  esac; done; exit 0
fi
if [[ "${1:-} ${2:-}" == "issue comment" ]]; then
  printf '%s\n' "$*" >> "${COMMENT_LOG:-/dev/null}"; exit 0
fi
exit 0
STUB
chmod +x "$WORK/bin/gh"

ALL15="p0 p1 p2 p3 riper-research riper-innovation riper-plan riper-execute riper-review riper-verified riper-blocked riper-retry-1 riper-retry-2 riper-retry-3 riper-claimed"
export REPO_LABELS="$WORK/repolabels"
export GH_LABELDIR="$WORK/lab"
export GH_ISSUES="$WORK/issues.tsv"
export COMMENT_LOG="$WORK/comments.log"
printf '%s\n' $ALL15 > "$REPO_LABELS"
printf '%s\t%s\t%s\n' 99 OPEN 'smoke issue' > "$GH_ISSUES"
: > "$GH_LABELDIR/99"
: > "$COMMENT_LOG"

RC=0; OUT=""
run() { RC=0; OUT="$( cd "$WORK/proj" && PATH="$WORK/bin:$PATH" bash "$GITOPS" "$@" 2>&1 </dev/null )" || RC=$?; }
last() { grep -vE '^\[git-ops\]' <<<"$OUT" | grep -v '^$' | tail -1; }
has_label() { grep -Fxq -- "$2" "$GH_LABELDIR/$1" 2>/dev/null; }

echo "=== (1) labels init manages 15 built-in labels incl. riper-claimed ==="
run labels init
[[ "$RC" -eq 0 ]] && pass "labels init exits 0" || fail "labels init rc=$RC"
grep -q '15/15' <<<"$OUT" && pass "labels init reports 15/15" || fail "labels init missing 15/15: $OUT"
grep -q 'riper-claimed' <<<"$OUT" && pass "labels init lists riper-claimed" || fail "labels init did not list riper-claimed"
run labels init
[[ "$RC" -eq 0 ]] && pass "labels init idempotent (2nd run exits 0)" || fail "labels init 2nd rc=$RC"
grep -q 'FAILED' <<<"$OUT" && fail "labels init 2nd run reported FAILED" || pass "labels init 2nd run: no FAILED"

echo "=== (2) doctor: 15/15 pass, missing riper-claimed fails closed ==="
run doctor
[[ "$RC" -eq 0 ]] && pass "doctor exits 0 with 15 labels" || fail "doctor rc=$RC; out=$OUT"
grep -q '15/15' <<<"$OUT" && pass "doctor reports 15/15" || fail "doctor missing 15/15"
printf '%s\n' p0 p1 p2 p3 riper-research riper-innovation riper-plan riper-execute riper-review riper-verified riper-blocked riper-retry-1 riper-retry-2 riper-retry-3 > "$REPO_LABELS"
run doctor
[[ "$RC" -eq 1 ]] && pass "doctor exits 1 when riper-claimed missing" || fail "doctor should fail without riper-claimed, rc=$RC"
grep -q 'riper-claimed' <<<"$OUT" && pass "doctor lists riper-claimed as missing" || fail "doctor did not name riper-claimed"
grep -q 'labels init' <<<"$OUT" && pass "doctor hints labels init" || fail "doctor missing labels-init hint"
printf '%s\n' $ALL15 > "$REPO_LABELS"

echo "=== (3) claim get reflects claim state ==="
run issue claim 99 get
[[ "$(last)" == "unclaimed" ]] && pass "claim get -> unclaimed (fresh issue)" || fail "claim get got '$(last)', want unclaimed"

echo "=== (4) claim writes label + audit comment with the four payload fields ==="
run --role developer issue claim 99 claim
[[ "$RC" -eq 0 ]] && pass "claim exits 0" || fail "claim rc=$RC; out=$OUT"
has_label 99 riper-claimed && pass "riper-claimed label written" || fail "riper-claimed label absent"
grep -q 'RIPER 认领' "$COMMENT_LOG" && pass "audit comment posted" || fail "no audit comment"
grep -q 'smoke-user' "$COMMENT_LOG" && pass "audit comment carries git user" || fail "audit comment missing git user"
grep -q '时间戳' "$COMMENT_LOG" && pass "audit comment carries timestamp field" || fail "audit comment missing timestamp field"
grep -q 'worktree 路径' "$COMMENT_LOG" && pass "audit comment carries worktree path field" || fail "audit comment missing worktree field"
grep -q '分支' "$COMMENT_LOG" && pass "audit comment carries branch field" || fail "audit comment missing branch field"
run issue claim 99 get
[[ "$(last)" == "claimed" ]] && pass "claim get -> claimed" || fail "claim get got '$(last)', want claimed"

echo "=== (5) re-claim is refused (no preempt), posts no new comment ==="
before="$(grep -c . "$COMMENT_LOG" || true)"
run issue claim 99 claim
[[ "$RC" -ne 0 ]] && pass "re-claim refused (rc=$RC)" || fail "re-claim should refuse, rc=$RC"
grep -q '已被认领' <<<"$OUT" && pass "refusal names existing claim" || fail "refusal message missing"
after="$(grep -c . "$COMMENT_LOG" || true)"
[[ "$before" == "$after" ]] && pass "no new comment on refused re-claim" || fail "refused re-claim posted a comment ($before -> $after)"

echo "=== (6) issue list never leaks riper-claimed into the status column ==="
printf '%s\n' riper-research riper-claimed > "$GH_LABELDIR/99"
run issue list --state open
row="$(grep '^#99' <<<"$OUT" || true)"
grep -q 'riper-research' <<<"$row" && pass "status column shows riper-research" || fail "status column missing riper-research: $row"
grep -q 'riper-claimed' <<<"$row" && fail "riper-claimed leaked into list row: $row" || pass "riper-claimed excluded from list row"
printf '%s\n' riper-claimed > "$GH_LABELDIR/99"
run issue list --state open
row="$(grep '^#99' <<<"$OUT" || true)"
grep -q 'riper-claimed' <<<"$row" && fail "status column shows riper-claimed when it is the only riper-* label: $row" || pass "status column falls back (no riper-claimed) when claim is sole riper-* label"

echo "=== (7) issue label add riper-claimed is blocked (must use claim) ==="
run --role planner issue label 99 add riper-claimed
[[ "$RC" -ne 0 ]] && pass "issue label add riper-claimed refused (rc=$RC)" || fail "issue label add riper-claimed should be refused"
grep -q 'issue claim' <<<"$OUT" && pass "refusal points to issue claim subcommand" || fail "refusal does not point to claim subcommand"

echo "=== (8) release removes label + is idempotent ==="
printf '%s\n' p2 riper-research riper-claimed > "$GH_LABELDIR/99"
: > "$COMMENT_LOG"
run --role reviewer issue claim 99 release
[[ "$RC" -eq 0 ]] && pass "release exits 0" || fail "release rc=$RC"
has_label 99 riper-claimed && fail "riper-claimed still present after release" || pass "riper-claimed removed"
grep -q 'RIPER 释放' "$COMMENT_LOG" && pass "release comment posted" || fail "no release comment"
run issue claim 99 get
[[ "$(last)" == "unclaimed" ]] && pass "claim get -> unclaimed after release" || fail "claim get got '$(last)' after release"
run issue claim 99 release
[[ "$RC" -eq 0 ]] && pass "release on unclaimed is idempotent (rc=0)" || fail "release on unclaimed rc=$RC"

echo "=== (9) claiming leaves priority / status families untouched ==="
printf '%s\n' p2 riper-research > "$GH_LABELDIR/99"
run --role developer issue claim 99 claim
has_label 99 p2 && pass "priority p2 preserved through claim" || fail "priority p2 lost"
has_label 99 riper-research && pass "status riper-research preserved through claim" || fail "status riper-research lost"
run issue claim 99 release

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
