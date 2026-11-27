#!/usr/bin/env bash
# Opt-in live CLI smoke skeleton (#81).
#
# The other suites stub every CLI call, so they can only assert the formats the
# implementation *expects*; real platform drift (#26 gh/glab split, #37 GitLab
# Work Items, #70 Gitea list misreport) lives in that blind spot.
#
# This suite exercises the real `git-ops.sh` stack end-to-end. It is OFF by
# default: without ILOOP_SMOKE_REPO it skips, so no existing suite gains a
# network or write dependency. Point it at a disposable sandbox repository:
#
#   ILOOP_SMOKE_REPO=owner/sandbox-repo bash test/iloop-live-smoke-invariants.sh
#
# Writes only ever target that sandbox repository, never this one.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
WORK="$(mktemp -d)"
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

# ---------------------------------------------------------------------------
# Skip vs fail are different outcomes and must stay distinguishable (C5):
#   unset ILOOP_SMOKE_REPO          -> "not enabled", skip, rc 0
#   set but the sandbox is unusable -> "enabled but broken", FAIL, rc != 0
# ---------------------------------------------------------------------------
# Self-check: the two outcomes must remain distinguishable, so a broken sandbox
# can never masquerade as "not enabled". This probes the decision logic itself
# (a nested run of this suite would recurse), using a stub gh that always fails.
mkdir -p "$WORK/probe-bin"
cat > "$WORK/probe-bin/gh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
chmod +x "$WORK/probe-bin/gh"

decide() {
  # Mirrors the branch order below: unset -> skip, set-but-unreachable -> fail.
  local repo="$1"
  if [[ -z "$repo" ]]; then echo "SKIP"; return 0; fi
  if ! PATH="$WORK/probe-bin:$PATH" gh repo view "$repo" --json name >/dev/null 2>&1; then
    echo "FAIL"
    return 1
  fi
  echo "RUN"
  return 0
}

skip_verdict=""; skip_rc=0
skip_verdict="$(decide "")" || skip_rc=$?
fail_verdict=""; fail_rc=0
fail_verdict="$(decide "owner/nonexistent")" || fail_rc=$?
[[ "$skip_verdict" == "SKIP" && "$skip_rc" -eq 0 ]] \
  || { echo 'FAIL live smoke: unset repo must skip with rc 0'; exit 1; }
[[ "$fail_verdict" == "FAIL" && "$fail_rc" -ne 0 ]] \
  || { echo 'FAIL live smoke: unreachable repo must fail, not skip'; exit 1; }
echo 'PASS live smoke: skip and fail stay distinguishable'

SMOKE_REPO="${ILOOP_SMOKE_REPO:-}"
if [[ -z "$SMOKE_REPO" ]]; then
  echo "SKIP live smoke: ILOOP_SMOKE_REPO not set (this suite is opt-in)."
  echo "SKIP live smoke: set ILOOP_SMOKE_REPO=<owner>/<sandbox-repo> to enable."
  rm -rf "$WORK"
  exit 0
fi

cleanup() {
  # Report leftovers loudly instead of pretending a failed cleanup succeeded.
  local rc=$?
  if [[ -n "${SMOKE_ISSUE:-}" && "${SMOKE_CLEANED:-0}" != "1" ]]; then
    echo "RESIDUE live smoke: issue ${SMOKE_ISSUE} (${SMOKE_REPO}) was not closed"
    [[ "$rc" -eq 0 ]] && rc=1
  fi
  if [[ -n "${SMOKE_LABEL:-}" && "${SMOKE_LABEL_CLEANED:-0}" != "1" ]]; then
    echo "RESIDUE live smoke: label ${SMOKE_LABEL} (${SMOKE_REPO}) was not removed"
    [[ "$rc" -eq 0 ]] && rc=1
  fi
  rm -rf "$WORK"
  exit "$rc"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Isolate: a throwaway git repo whose origin is the sandbox, so git-ops.sh
# routes to the sandbox and never writes through this repository's remote.
#
# The host is resolved from the CLI that will run, not hardcoded to github.com
# (#95). `smoke require-origin` then re-checks the result before any write.
# ---------------------------------------------------------------------------
SANDBOX="$WORK/sandbox"
mkdir -p "$SANDBOX"
git -C "$SANDBOX" init -q

if [[ "$SMOKE_REPO" == http://* || "$SMOKE_REPO" == https://* ]]; then
  sandbox_url="$SMOKE_REPO"
else
  sandbox_host="github.com"
  case "$(bash "$GITOPS" platform 2>/dev/null | tail -1)" in
    tea)  host_line="$(tea login list 2>/dev/null | sed -n 's|.*\(https\{0,1\}://[^ ]*\).*|\1|p' | head -1)"
          [[ -n "$host_line" ]] && sandbox_host="${host_line#*://}" ;;
    glab) sandbox_host="${GITLAB_HOST:-gitlab.com}" ;;
  esac
  sandbox_url="https://${sandbox_host}/${SMOKE_REPO}"
fi
git -C "$SANDBOX" remote add origin "${sandbox_url%.git}.git" 2>/dev/null || true

# Reachability through the same wrapper the run will use.
if ! ( cd "$SANDBOX" && bash "$GITOPS" issue list --state open ) >/dev/null 2>&1; then
  echo "FAIL live smoke: sandbox repo '$SMOKE_REPO' is unreachable or not authorized."
  echo "FAIL live smoke: check that ILOOP_SMOKE_REPO names a disposable repo you own,"
  echo "FAIL live smoke: or create one with: git-ops.sh smoke sandbox create"
  exit 1
fi
echo "PASS sandbox repo reachable: $SMOKE_REPO"

if bash "$GITOPS" smoke require-origin "$SANDBOX" "$sandbox_url" >/dev/null 2>&1; then
  pass "throwaway origin points at the sandbox"
else
  fail "throwaway origin does not point at the sandbox"
fi

run_ops() { ( cd "$SANDBOX" && bash "$GITOPS" "$@" ); }

# ---------------------------------------------------------------------------
# Minimal loop through the real wrapper: create -> labels init -> free label ->
# status -> read -> close. Every write goes through git-ops.sh (C4).
# ---------------------------------------------------------------------------
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
SMOKE_LABEL="area/smoke-${stamp}"

if ! create_out="$(run_ops --role planner issue create \
      "live smoke ${stamp}" "Temporary issue created by test/iloop-live-smoke-invariants.sh (#81); safe to delete." 2>&1)"; then
  echo "$create_out"
  fail "issue create through git-ops.sh"
else
  SMOKE_ISSUE="$(printf '%s\n' "$create_out" | grep -oE '/issues/[0-9]+' | tail -1 | tr -dc '0-9')"
  if [[ -n "$SMOKE_ISSUE" ]]; then
    pass "issue create through git-ops.sh (#${SMOKE_ISSUE})"
  else
    fail "issue create did not report an issue number"
  fi
fi

if [[ -z "${SMOKE_ISSUE:-}" ]]; then
  echo "FAIL live smoke: cannot continue without an issue number."
  exit 1
fi

# Managed families (p0-p3 / riper-*) only exist after `labels init`. The stub
# suites never noticed because their fixtures pre-seed the labels; a fresh sandbox
# repo has none, so this step is what the live run actually exposed (#83).
if run_ops labels init >/dev/null 2>&1; then
  pass "labels init through git-ops.sh"
else
  fail "labels init through git-ops.sh"
fi

if run_ops --role planner issue priority "$SMOKE_ISSUE" p3 >/dev/null 2>&1; then
  pass "issue priority through git-ops.sh"
else
  fail "issue priority through git-ops.sh"
fi

if run_ops --role planner issue label "$SMOKE_ISSUE" add "$SMOKE_LABEL" >/dev/null 2>&1; then
  pass "free label add through git-ops.sh"
else
  fail "free label add through git-ops.sh"
fi

if run_ops --role planner issue status "$SMOKE_ISSUE" riper-research >/dev/null 2>&1; then
  pass "issue status through git-ops.sh"
else
  fail "issue status through git-ops.sh"
fi

if run_ops issue get "$SMOKE_ISSUE" --strict >/dev/null 2>&1; then
  pass "issue get --strict through git-ops.sh"
else
  fail "issue get --strict through git-ops.sh"
fi

# Cleanup runs before the trap can report residue. Removing the label from the
# issue is not enough: the repo-level label *definition* is what survives, so the
# live run deletes it too (a stub fixture never has to).
if run_ops issue label "$SMOKE_ISSUE" remove "$SMOKE_LABEL" >/dev/null 2>&1; then
  pass "free label removed from the issue"
else
  fail "free label removal from the issue"
fi
if gh label delete "$SMOKE_LABEL" --repo "$SMOKE_REPO" --yes >/dev/null 2>&1; then
  SMOKE_LABEL_CLEANED=1
  pass "free label definition deleted from the sandbox"
else
  fail "free label definition deletion"
fi

if run_ops --role reviewer issue close "$SMOKE_ISSUE" >/dev/null 2>&1; then
  SMOKE_CLEANED=1
  pass "sandbox issue closed"
else
  fail "sandbox issue close"
fi

echo "----------------------------------------"
if [[ "$FAILS" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
fi
echo "FAILURES: $FAILS"
exit 1
