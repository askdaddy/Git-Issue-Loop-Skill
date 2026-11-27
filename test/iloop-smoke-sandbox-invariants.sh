#!/usr/bin/env bash
# Black-box contracts for `smoke sandbox` / `smoke require-origin` (#95).
#
# Why this exists: the #87 incident came from a fixture whose origin fell back to
# the real repository, so a diagnostic command edited a real Issue. `require-origin`
# is the guard against exactly that; `sandbox create/delete` is the one-command
# lifecycle that makes a real sandbox the only place a smoke run can write.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${STUB_LOG:-/dev/null}"
case "${1:-} ${2:-}" in
  "auth status") printf 'github.com\n  - Active account: true\n' ;;
  "api user")    printf 'testowner\n' ;;
  "repo create") printf 'created %s\n' "${3:-}" ;;
  "repo delete") printf 'deleted %s\n' "${3:-}" ;;
esac
exit 0
STUB
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH" STUB_LOG="$WORK/calls"

# ---------------------------------------------------------------------------
# create: default name carries the marker and a UTC stamp
# ---------------------------------------------------------------------------
out="$(bash "$GITOPS" smoke sandbox create 2>&1)" || true
case "$out" in
  *"/iloop-smoke-"*) pass "create names the sandbox with the marker + UTC stamp" ;;
  *) fail "create produced no marker name: $out" ;;
esac

out="$(bash "$GITOPS" smoke sandbox create --name iloop-smoke-custom 2>&1)" || true
case "$out" in
  *"iloop-smoke-custom"*) pass "create honours --name when it carries the marker" ;;
  *) fail "create ignored --name: $out" ;;
esac

# ---------------------------------------------------------------------------
# create: a name without the marker is refused (keeps sandboxes identifiable)
# ---------------------------------------------------------------------------
if bash "$GITOPS" smoke sandbox create --name plain-name >/dev/null 2>&1; then
  fail "create accepted a name without the marker"
else
  pass "create refuses a name without the marker"
fi

# ---------------------------------------------------------------------------
# delete: needs an explicit --yes (never delete by accident)
# ---------------------------------------------------------------------------
if bash "$GITOPS" smoke sandbox delete testowner/iloop-smoke-x >/dev/null 2>&1; then
  fail "delete ran without --yes"
else
  pass "delete refuses without --yes"
fi

# ---------------------------------------------------------------------------
# delete: refuses anything that is not a sandbox
# ---------------------------------------------------------------------------
if bash "$GITOPS" smoke sandbox delete testowner/real-project --yes >/dev/null 2>&1; then
  fail "delete accepted a non-sandbox name"
else
  pass "delete refuses a non-sandbox name"
fi

# ---------------------------------------------------------------------------
# require-origin: the guard that prevents the #87 incident
# ---------------------------------------------------------------------------
git -C "$WORK" init -q sandbox 2>/dev/null || { mkdir -p "$WORK/sandbox"; git -C "$WORK/sandbox" init -q; }
git -C "$WORK/sandbox" remote add origin "https://github.com/testowner/iloop-smoke-x.git"

if bash "$GITOPS" smoke require-origin "$WORK/sandbox" testowner/iloop-smoke-x >/dev/null 2>&1; then
  pass "require-origin accepts the sandbox"
else
  fail "require-origin rejected its own sandbox"
fi

# The incident scenario: the fixture's origin fell back to the real repository.
git -C "$WORK/sandbox" remote set-url origin "https://github.com/askdaddy/Git-Issue-Loop-Skill.git"
if bash "$GITOPS" smoke require-origin "$WORK/sandbox" testowner/iloop-smoke-x >/dev/null 2>&1; then
  fail "require-origin accepted the REAL repository (the #87 incident)"
else
  pass "require-origin refuses the real repository (#87 incident guarded)"
fi

# No origin at all must fail closed too.
mkdir -p "$WORK/bare" && git -C "$WORK/bare" init -q
if bash "$GITOPS" smoke require-origin "$WORK/bare" testowner/iloop-smoke-x >/dev/null 2>&1; then
  fail "require-origin accepted a repo with no origin"
else
  pass "require-origin refuses a repo with no origin"
fi

# A non-git directory must fail closed.
mkdir -p "$WORK/notgit"
if bash "$GITOPS" smoke require-origin "$WORK/notgit" testowner/iloop-smoke-x >/dev/null 2>&1; then
  fail "require-origin accepted a non-git directory"
else
  pass "require-origin refuses a non-git directory"
fi

# ---------------------------------------------------------------------------
# no credentials are read or written by these commands
# ---------------------------------------------------------------------------
# Scope this to the smoke functions: the auth guide legitimately *mentions*
# GH_TOKEN as advice, so a whole-file grep would be a false positive.
# Only the three smoke functions, not their requires or the shared auth guide.
smoke_body="$(
  for fn in cmd_smoke_sandbox_create cmd_smoke_sandbox_delete cmd_smoke_require_origin; do
    sed -n "/^${fn}()/,/^}/p" "$GITOPS"
  done
)"
# Match credential *variables* and secret files only; the delete guidance legitimately
# says the word "token" when explaining a missing scope.
if printf '%s\n' "$smoke_body" | grep -Eq 'GH_TOKEN|GITHUB_TOKEN|GITLAB_TOKEN|\$\.env|\.env\b|glpat|ghp_'; then
  fail "smoke commands read or write credentials"
else
  pass "smoke commands never touch credentials"
fi

# ---------------------------------------------------------------------------
# the live smoke suite must not hardcode a single forge host (#95)
# ---------------------------------------------------------------------------
if grep -Eq 'https://github\.com/\$\{SMOKE_REPO\}' "${ROOT}/test/iloop-live-smoke-invariants.sh"; then
  fail "live smoke still hardcodes github.com for the sandbox"
else
  pass "live smoke resolves the sandbox host generically"
fi

echo "----------------------------------------"
if [[ "$FAILS" -eq 0 ]]; then
  echo "ALL PASS"
  exit 0
fi
echo "FAILURES: $FAILS"
exit 1
