#!/usr/bin/env bash
# Black-box regression checks for Issue #26:
#   `issue label add` must auto-create missing FREE labels on gh / glab (tea already did),
#   must never create outside the free-label namespace, and must not swallow create failures.
#
# Fixtures: stub gh / glab / tea on PATH. `$CATALOG` is the repo-level label list,
# `$CALL_LOG` records every CLI invocation, `$ISSUES/<n>` holds an issue's labels.
# FAIL_MODE-ish switches: CREATE_FAIL=1 / ADD_FAIL=1 / LIST_FAIL=1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

# ---------------------------------------------------------------------------
# stubs
# ---------------------------------------------------------------------------
write_gh_stub() {
  cat > "$CASE/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$CALL_LOG"
add_label() { grep -Fxq -- "$2" "$1" 2>/dev/null || printf '%s\n' "$2" >> "$1"; }
[[ "${1:-}" == "auth" ]] && exit 0
if [[ "${1:-} ${2:-}" == "label list" ]]; then
  [[ "${LIST_FAIL:-0}" == "1" ]] && { echo "network unreachable" >&2; exit 1; }
  while IFS= read -r n; do printf '%s\n' "$n"; done < "$CATALOG"; exit 0
fi
if [[ "${1:-} ${2:-}" == "label create" ]]; then
  [[ "${CREATE_FAIL:-0}" == "1" ]] && { echo "HTTP 403: no permission" >&2; exit 1; }
  printf '%s\n' "${3:-}" >> "$CATALOG"; exit 0
fi
if [[ "${1:-} ${2:-}" == "issue edit" ]]; then
  num="${3:-}"; prev=""; for a in "$@"; do
    if [[ "$prev" == "--add-label" ]]; then
      [[ "${ADD_FAIL:-0}" == "1" ]] && { echo "could not add label '$a'" >&2; exit 1; }
      grep -Fxq -- "$a" "$CATALOG" || { echo "label '$a' not found" >&2; exit 1; }
      add_label "$ISSUES/$num" "$a"
    fi
    prev="$a"
  done; exit 0
fi
exit 0
STUB
  chmod +x "$CASE/bin/gh"
}

write_glab_stub() {
  cat > "$CASE/bin/glab" <<'STUB'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$CALL_LOG"
add_label() { grep -Fxq -- "$2" "$1" 2>/dev/null || printf '%s\n' "$2" >> "$1"; }
[[ "${1:-}" == "auth" ]] && exit 0
if [[ "${1:-} ${2:-}" == "label list" ]]; then
  [[ "${LIST_FAIL:-0}" == "1" ]] && { echo "network unreachable" >&2; exit 1; }
  first=1; printf '['
  while IFS= read -r n; do [[ $first -eq 0 ]] && printf ','; printf '{"name":"%s"}' "$n"; first=0; done < "$CATALOG"
  printf ']\n'; exit 0
fi
if [[ "${1:-} ${2:-}" == "label create" ]]; then
  [[ "${CREATE_FAIL:-0}" == "1" ]] && { echo "403 Forbidden" >&2; exit 1; }
  prev=""; name=""; color=""; for a in "$@"; do
    [[ "$prev" == "--name" ]] && name="$a"
    [[ "$prev" == "--color" ]] && color="$a"
    prev="$a"
  done
  [[ -z "$name" ]] && name="${3:-}"
  printf '%s\n' "${name}" >> "$CATALOG"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "issue update" ]]; then
  [[ "${ADD_FAIL:-0}" == "1" ]] && { echo "add failed" >&2; exit 1; }
  num="${3:-}"; prev=""; for a in "$@"; do
    if [[ "$prev" == "--label" ]]; then
      grep -Fxq -- "$a" "$CATALOG" || { echo "label '$a' not found" >&2; exit 1; }
      add_label "$ISSUES/$num" "$a"
    fi
    prev="$a"
  done; exit 0
fi
if [[ "${1:-} ${2:-}" == "issue label" ]]; then
  [[ "${ADD_FAIL:-0}" == "1" ]] && { echo "add failed" >&2; exit 1; }
  exit 0
fi
exit 0
STUB
  chmod +x "$CASE/bin/glab"
}

write_tea_stub() {
  cat > "$CASE/bin/tea" <<'STUB'
#!/usr/bin/env bash
set -e
printf '%s\n' "$*" >> "$CALL_LOG"
add_label() { grep -Fxq -- "$2" "$1" 2>/dev/null || printf '%s\n' "$2" >> "$1"; }
[[ "${1:-} ${2:-}" == "login list" ]] && { echo 'https://gitea.example.test user token'; exit 0; }
if [[ "${1:-} ${2:-}" == "labels list" ]]; then
  [[ "${LIST_FAIL:-0}" == "1" ]] && { echo "network unreachable" >&2; exit 1; }
  echo '│ ID │ Color │ Name │ Description │'; i=0
  while IFS= read -r n; do i=$((i+1)); printf '│ %d │ ededed │ %s │ stub │\n' "$i" "$n"; done < "$CATALOG"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "labels create" ]]; then
  [[ "${CREATE_FAIL:-0}" == "1" ]] && { echo "403 no permission" >&2; exit 1; }
  prev=""; name=""; for a in "$@"; do [[ "$prev" == "--name" ]] && name="$a"; prev="$a"; done
  printf '%s\n' "$name" >> "$CATALOG"
  exit 0
fi
if [[ "${1:-}" == "issues" && "${2:-}" == "edit" ]]; then
  [[ "${ADD_FAIL:-0}" == "1" ]] && { echo "add failed" >&2; exit 1; }
  num="$3"; prev=""; for a in "$@"; do
    if [[ "$prev" == "--add-labels" ]]; then
      grep -Fxq -- "$a" "$CATALOG" || { echo "label '$a' not found" >&2; exit 1; }
      add_label "$ISSUES/$num" "$a"
    fi
    prev="$a"
  done; exit 0
fi
exit 0
STUB
  chmod +x "$CASE/bin/tea"
}

# ---------------------------------------------------------------------------
# case helpers
# ---------------------------------------------------------------------------
setup_case() {
  local name="$1" remote="$2" platform="$3"
  CASE="$WORK/$name"
  mkdir -p "$CASE/repo" "$CASE/bin" "$CASE/issues"
  git -C "$CASE/repo" init -q
  git -C "$CASE/repo" remote add origin "$remote"
  : > "$CASE/catalog"
  printf 'seed\n' > "$CASE/issues/1"
  : > "$CASE/calls"
  case "$platform" in
    gh) write_gh_stub ;;
    glab) write_glab_stub ;;
    tea) write_tea_stub ;;
  esac
}

run_add() {
  ( cd "$CASE/repo" \
    && PATH="$CASE/bin:$PATH" CALL_LOG="$CASE/calls" CATALOG="$CASE/catalog" ISSUES="$CASE/issues" \
       bash "$GITOPS" --role planner issue label 1 add "$1" )
}

create_count() {
  local n
  n="$(grep -cE 'labels? create' "$CASE/calls" || true)"
  printf '%s' "${n:-0}"
}

issue1_has() { grep -Fxq -- "$1" "$CASE/issues/1"; }

# ---------------------------------------------------------------------------
# (1) gh: missing label -> create once, then add
# ---------------------------------------------------------------------------
setup_case gh-missing https://github.com/acme/demo.git gh
set +e; out="$(run_add area/cli 2>&1)"; rc=$?; set -e
[[ "$rc" -eq 0 ]] && pass "gh missing: exit 0" || fail "gh missing: exit $rc (want 0): $out"
[[ "$(create_count)" == "1" ]] && pass "gh missing: exactly 1 'label create'" || fail "gh missing: $(create_count) creates (want 1)"
issue1_has area/cli && pass "gh missing: issue carries the label" || fail "gh missing: label absent on issue"
[[ -n "$(grep -n 'label create' "$CASE/calls" || true)" ]] \
  && [[ "$(grep -n 'label create' "$CASE/calls" | head -1 | cut -d: -f1)" -lt "$(grep -n -- '--add-label' "$CASE/calls" | head -1 | cut -d: -f1)" ]] \
  && pass "gh missing: create precedes add" || fail "gh missing: create did not precede add"

# ---------------------------------------------------------------------------
# (2) gh: existing label -> no create
# ---------------------------------------------------------------------------
setup_case gh-existing https://github.com/acme/demo.git gh
printf 'area/cli\n' > "$CASE/catalog"
set +e; run_add area/cli >/dev/null 2>&1; rc=$?; set -e
[[ "$rc" -eq 0 ]] && pass "gh existing: exit 0" || fail "gh existing: exit $rc (want 0)"
[[ "$(create_count)" == "0" ]] && pass "gh existing: 0 'label create'" || fail "gh existing: $(create_count) creates (want 0)"

# ---------------------------------------------------------------------------
# (3) gh: create and add both fail -> non-zero with both causes
# ---------------------------------------------------------------------------
setup_case gh-both-fail https://github.com/acme/demo.git gh
set +e; out="$(CREATE_FAIL=1 ADD_FAIL=1 run_add area/cli 2>&1)"; rc=$?; set -e
[[ "$rc" -ne 0 ]] && pass "gh both-fail: non-zero exit" || fail "gh both-fail: exit 0 (want non-zero)"
grep -q 'label create 失败' <<< "$out" && pass "gh both-fail: create failure surfaced" || fail "gh both-fail: create failure swallowed: $out"
grep -q '添加标签' <<< "$out" && pass "gh both-fail: add failure surfaced" || fail "gh both-fail: add failure missing: $out"

# ---------------------------------------------------------------------------
# (4) gh: create fails but add succeeds (label actually existed) -> success
# ---------------------------------------------------------------------------
setup_case gh-race https://github.com/acme/demo.git gh
printf 'area/cli\n' > "$CASE/catalog"
set +e; out="$(CREATE_FAIL=1 run_add area/cli 2>&1)"; rc=$?; set -e
[[ "$rc" -eq 0 ]] && pass "gh race: add-after-create-failure exits 0" || fail "gh race: exit $rc (want 0): $out"

# ---------------------------------------------------------------------------
# (5) glab: missing -> create once with #-prefixed colour, then add
# ---------------------------------------------------------------------------
setup_case glab-missing https://gitlab.com/acme/demo.git glab
set +e; out="$(run_add area/cli 2>&1)"; rc=$?; set -e
[[ "$rc" -eq 0 ]] && pass "glab missing: exit 0" || fail "glab missing: exit $rc (want 0): $out"
[[ "$(create_count)" == "1" ]] && pass "glab missing: exactly 1 'label create'" || fail "glab missing: $(create_count) creates (want 1)"
grep -q -- 'label create --name area/cli --color #ededed' "$CASE/calls" \
  && pass "glab missing: colour passed as #ededed" || fail "glab missing: unexpected create args: $(grep 'label create' "$CASE/calls" || true)"

# ---------------------------------------------------------------------------
# (6) glab: existing -> no create
# ---------------------------------------------------------------------------
setup_case glab-existing https://gitlab.com/acme/demo.git glab
printf 'area/cli\n' > "$CASE/catalog"
set +e; run_add area/cli >/dev/null 2>&1; rc=$?; set -e
[[ "$rc" -eq 0 ]] && pass "glab existing: exit 0" || fail "glab existing: exit $rc (want 0)"
[[ "$(create_count)" == "0" ]] && pass "glab existing: 0 'label create'" || fail "glab existing: $(create_count) creates (want 0)"

# ---------------------------------------------------------------------------
# (7) glab: both fail -> non-zero with create cause
# ---------------------------------------------------------------------------
setup_case glab-both-fail https://gitlab.com/acme/demo.git glab
set +e; out="$(CREATE_FAIL=1 ADD_FAIL=1 run_add area/cli 2>&1)"; rc=$?; set -e
[[ "$rc" -ne 0 ]] && pass "glab both-fail: non-zero exit" || fail "glab both-fail: exit 0 (want non-zero)"
grep -q 'label create 失败' <<< "$out" && pass "glab both-fail: create failure surfaced" || fail "glab both-fail: swallowed: $out"

# ---------------------------------------------------------------------------
# (8) tea: missing -> create once (pre-check kept: Gitea does not dedupe names)
# ---------------------------------------------------------------------------
setup_case tea-missing https://gitea.example.test/acme/demo.git tea
set +e; out="$(run_add area/cli 2>&1)"; rc=$?; set -e
[[ "$rc" -eq 0 ]] && pass "tea missing: exit 0" || fail "tea missing: exit $rc (want 0): $out"
[[ "$(create_count)" == "1" ]] && pass "tea missing: exactly 1 'labels create'" || fail "tea missing: $(create_count) creates (want 1)"

# ---------------------------------------------------------------------------
# (9) tea: existing -> no create
# ---------------------------------------------------------------------------
setup_case tea-existing https://gitea.example.test/acme/demo.git tea
printf 'area/cli\n' > "$CASE/catalog"
set +e; run_add area/cli >/dev/null 2>&1; rc=$?; set -e
[[ "$rc" -eq 0 ]] && pass "tea existing: exit 0" || fail "tea existing: exit $rc (want 0)"
[[ "$(create_count)" == "0" ]] && pass "tea existing: 0 'labels create'" || fail "tea existing: $(create_count) creates (want 0)"

# ---------------------------------------------------------------------------
# (10) tea: create failure must NOT be swallowed (regression: former '|| true')
# ---------------------------------------------------------------------------
setup_case tea-both-fail https://gitea.example.test/acme/demo.git tea
set +e; out="$(CREATE_FAIL=1 ADD_FAIL=1 run_add area/cli 2>&1)"; rc=$?; set -e
[[ "$rc" -ne 0 ]] && pass "tea both-fail: non-zero exit" || fail "tea both-fail: exit 0 (want non-zero)"
grep -q 'labels create 失败' <<< "$out" && pass "tea both-fail: create failure surfaced" || fail "tea both-fail: swallowed: $out"

# ---------------------------------------------------------------------------
# (11) label listing failure -> fail-closed, never create
# ---------------------------------------------------------------------------
setup_case gh-list-fail https://github.com/acme/demo.git gh
set +e; out="$(LIST_FAIL=1 ADD_FAIL=1 run_add area/cli 2>&1)"; rc=$?; set -e
[[ "$(create_count)" == "0" ]] && pass "list failure: no blind create" || fail "list failure: $(create_count) creates (want 0)"
[[ "$rc" -ne 0 ]] && pass "list failure: non-zero exit" || fail "list failure: exit 0 (want non-zero)"

# ---------------------------------------------------------------------------
# (12) managed families: never auto-created, even as case variants
# ---------------------------------------------------------------------------
setup_case gh-families https://github.com/acme/demo.git gh
fam_rc_bad=0
for lab in p0 P1 riper-plan RIPER-PLAN riper-retry-1 riper-claimed; do
  set +e; run_add "$lab" >/dev/null 2>&1; rc=$?; set -e
  [[ "$rc" -ne 0 ]] || { fam_rc_bad=1; echo "  (unexpectedly accepted: $lab)"; }
done
[[ "$fam_rc_bad" -eq 0 ]] && pass "families: every managed label/variant refused" || fail "families: a managed label was accepted"
[[ "$(create_count)" == "0" ]] && pass "families: 0 'label create' for managed families" || fail "families: $(create_count) creates (want 0)"
set +e; run_add area/cli >/dev/null 2>&1; rc=$?; set -e
[[ "$rc" -eq 0 ]] && pass "families: free label still accepted alongside" || fail "families: free label rejected (exit $rc)"

echo "----------------------------------------"
if [[ "$FAILS" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
fi
echo "FAILURES: $FAILS"
exit 1
