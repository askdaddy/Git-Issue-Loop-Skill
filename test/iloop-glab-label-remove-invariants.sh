#!/usr/bin/env bash
# Black-box contract checks for Issue #14 (glab label removal silent failure).
# Stubs glab 1.118 behaviour — `issue view` prints lowercase `labels:`, unknown
# flags are rejected — and drives git-ops.sh inside a throwaway repo whose origin
# routes to glab. Removal must be issued as `glab issue update <N> --unlabel <l>`.
# Run from repository root: bash test/iloop-glab-label-remove-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
FAILS=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

# --- fixture: throwaway repo + stub glab ------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/proj"
git -C "$WORK/proj" init -q
git -C "$WORK/proj" remote add origin https://gitlab.com/o/r.git

cat > "$WORK/bin/glab" <<'STUB'
#!/usr/bin/env bash
# Stub of glab 1.118: records every call, mimics real output/flags.
echo "$*" >> "${STUB_LOG:?}"
if [[ "${1:-}" == "auth" ]]; then exit 0; fi
if [[ "${1:-} ${2:-}" == "issue view" ]]; then
  printf 'title:\tstub issue\nstate:\topen\nauthor:\tstub_user\nlabels:\tp1, riper-research, riper-plan\ncomments:\t0\nassignees:\t\n--\nstub body\n'
  exit 0
fi
if [[ "${1:-} ${2:-}" != "issue update" ]]; then
  echo "Unknown command" >&2
  exit 1
fi
# issue update: only --label / --unlabel exist in 1.118 (verified against --help)
prev=""
for a in "$@"; do
  if [[ "$a" == "--remove-label" ]]; then
    echo "Unknown flag: --remove-label" >&2
    exit 1
  fi
  if [[ "$prev" == "--unlabel" && "$a" == "nonexistent" ]]; then
    echo "ERROR: label 'nonexistent' does not exist on this issue" >&2
    exit 1
  fi
  prev="$a"
done
exit 0
STUB
chmod +x "$WORK/bin/glab"

# probe <args...>: run git-ops.sh with the stub on PATH inside the fixture repo.
# Sets RC / OUT / ERR / CALLS (recorded CLI invocations).
RC=0; OUT=""; ERR=""; CALLS=""
probe() {
  local log="$WORK/calls.log" errfile="$WORK/stderr"
  : > "$log"
  RC=0
  OUT="$( cd "$WORK/proj" && STUB_LOG="$log" PATH="$WORK/bin:$PATH" bash "$GITOPS" "$@" 2>"$errfile" )" || RC=$?
  ERR="$(cat "$errfile" 2>/dev/null || true)"
  CALLS="$log"
}

unlabel_set() { sed -n 's/.*--unlabel \([^ ]*\).*/\1/p' "$1" | sort | tr '\n' ' '; }
expected_set() { printf '%s\n' "$@" | sort | tr '\n' ' '; }

echo "=== step 1a: free-label removal uses official --unlabel (rc=0, no view parse) ==="
probe issue label 7 remove type/bug
if [[ "$RC" -eq 0 ]]; then pass "issue label remove exits 0 (rc=$RC)"; else fail "issue label remove rc=$RC, want 0"; fi
if [[ "$(unlabel_set "$CALLS")" == "type/bug " ]]; then
  pass "removal issued as: issue update 7 --unlabel type/bug"
else
  fail "unexpected unlabel set: '$(unlabel_set "$CALLS")'"
fi
if grep -q 'issue update 7 --unlabel type/bug' "$CALLS"; then
  pass "stub recorded the exact --unlabel invocation"
else
  fail "stub did not record 'issue update 7 --unlabel type/bug'"
fi
if grep -q 'issue view' "$CALLS"; then
  fail "removal path still calls 'issue view' (parse dependency left behind)"
else
  pass "removal path performs no 'issue view' call"
fi
if grep -q -- '--remove-label' "$CALLS"; then
  fail "removal path still uses the non-existent --remove-label flag"
else
  pass "no --remove-label flag reaches the CLI"
fi

echo "=== step 1b: removing a label that does not exist stays best-effort ==="
probe issue label 7 remove nonexistent
if [[ "$RC" -eq 0 ]]; then pass "missing label removal exits 0 (rc=$RC)"; else fail "missing label removal rc=$RC, want 0"; fi
if [[ -z "$ERR" || "$ERR" != *"ERROR"* ]]; then
  pass "no ERROR output on missing label"
else
  fail "ERROR surfaced on missing label: $ERR"
fi
if grep -q 'issue update 7 --unlabel nonexistent' "$CALLS"; then
  pass "missing label still issued via --unlabel (CLI-side error swallowed)"
else
  fail "missing label not issued via --unlabel"
fi

echo "=== step 1c: status exclusivity really removes the other 6 status labels ==="
probe issue status 7 riper-plan
if [[ "$RC" -eq 0 ]]; then pass "issue status exits 0 (rc=$RC)"; else fail "issue status rc=$RC, want 0"; fi
want_status="$(expected_set riper-blocked riper-execute riper-innovation riper-research riper-review riper-verified)"
got_status="$(unlabel_set "$CALLS")"
if [[ "$got_status" == "$want_status" ]]; then
  pass "6 exclusive unlabel calls for all non-target status labels"
else
  fail "status unlabel set: '$got_status', want '$want_status'"
fi
if grep -q 'issue update 7 --label riper-plan$' "$CALLS"; then
  pass "target status label added after cleanup"
else
  fail "target status label not added"
fi

echo "=== step 1d: priority exclusivity really removes the other 3 priority labels ==="
probe issue priority 7 p2
if [[ "$RC" -eq 0 ]]; then pass "issue priority exits 0 (rc=$RC)"; else fail "issue priority rc=$RC, want 0"; fi
want_prio="$(expected_set p0 p1 p3)"
got_prio="$(unlabel_set "$CALLS")"
if [[ "$got_prio" == "$want_prio" ]]; then
  pass "3 exclusive unlabel calls for all non-target priority labels"
else
  fail "priority unlabel set: '$got_prio', want '$want_prio'"
fi
if grep -q 'issue update 7 --label p2$' "$CALLS"; then
  pass "target priority label added after cleanup"
else
  fail "target priority label not added"
fi

echo "=== step 1e: structural evidence — broken pattern removed from script ==="
if [[ "$(grep -c 'glab issue view' "$GITOPS")" -eq 1 ]] && grep -q 'glab issue view "${num}" --comments' "$GITOPS"; then
  pass "'glab issue view' remains only in cmd_issue_get"
else
  fail "'glab issue view' occurrences: $(grep -c 'glab issue view' "$GITOPS" || true) (want 1, in cmd_issue_get)"
fi
if grep -qE 'glab issue update.*--remove-label' "$GITOPS"; then
  fail "git-ops.sh still issues 'glab issue update ... --remove-label'"
else
  pass "no 'glab issue update ... --remove-label' left in git-ops.sh"
fi
if grep -qE 's/\^[Ll]abels' "$GITOPS"; then
  fail "git-ops.sh still parses a 'Labels:' line"
else
  pass "no 'Labels:' text-parse left in git-ops.sh"
fi
if grep -q -- '--unlabel' "$GITOPS"; then
  pass "git-ops.sh uses the official --unlabel flag"
else
  fail "git-ops.sh does not use --unlabel"
fi

echo "=== out of scope: fix is committed (no uncommitted diff on git-ops.sh) ==="
if git -C "$ROOT" diff HEAD -- scripts/git-ops.sh | grep -q .; then
  fail "scripts/git-ops.sh has uncommitted diff"
else
  pass "git-ops.sh clean vs HEAD"
fi

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
