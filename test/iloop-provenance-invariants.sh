#!/usr/bin/env bash
# Black-box contract checks for Issue provenance footer (Issue #58).
#
# Frozen WHAT:
#   1. `issue create` appends a VISIBLE footer (no hidden HTML comment).
#   2. The footer contains the Skill repository URL
#      https://github.com/askdaddy/Git-Issue-Loop-Skill
#   3. It records version (or `untagged`), short SHA, role, entry, UTC time.
#   4. The original body is preserved and the footer comes after it.
#   5. Entry defaults to `issue-create` and honors ILOOP_PROVENANCE_ENTRY.
#   6. No local absolute path leaks into the Issue body.
#
# Run from repository root: bash test/iloop-provenance-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
FAILS=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Stub gh: auth succeeds; issue create captures --body and returns a URL.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" ]]; then exit 0; fi
if [[ "${1:-}" == "issue" && "${2:-}" == "create" ]]; then
  prev=""; body=""
  for a in "$@"; do
    [[ "$prev" == "--body" ]] && body="$a"
    prev="$a"
  done
  printf '%s' "$body" > "${STUB_BODY:?}"
  echo "https://github.com/example/target/issues/1"
  exit 0
fi
exit 0
STUB
chmod +x "$WORK/bin/gh"

# Stub glab: auth succeeds; issue create captures --description.
cat > "$WORK/bin/glab" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" ]]; then exit 0; fi
if [[ "${1:-}" == "issue" && "${2:-}" == "create" ]]; then
  prev=""; body=""
  for a in "$@"; do
    [[ "$prev" == "--description" ]] && body="$a"
    prev="$a"
  done
  printf '%s' "$body" > "${STUB_BODY:?}"
  echo "https://gitlab.com/example/target/-/issues/1"
  exit 0
fi
exit 0
STUB
chmod +x "$WORK/bin/glab"

# Stub tea: login list succeeds; issues create captures --description.
cat > "$WORK/bin/tea" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "login" && "${2:-}" == "list" ]]; then
  echo "https://gitea.example.com  gitea  someuser  <token>"
  exit 0
fi
if [[ "${1:-}" == "issues" && "${2:-}" == "create" ]]; then
  prev=""; body=""
  for a in "$@"; do
    [[ "$prev" == "--description" ]] && body="$a"
    prev="$a"
  done
  printf '%s' "$body" > "${STUB_BODY:?}"
  echo "https://gitea.example.com/example/target/issues/1"
  exit 0
fi
exit 0
STUB
chmod +x "$WORK/bin/tea"

make_repo() {
  local name="$1" origin="$2"
  mkdir -p "$WORK/$name"
  git -C "$WORK/$name" init -q
  git -C "$WORK/$name" remote add origin "$origin"
}

make_repo repo-gh "https://github.com/example/target.git"
make_repo repo-glab "https://gitlab.com/example/target.git"
make_repo repo-tea "https://gitea.example.com/example/target.git"

create_issue() {
  local repo="$1" entry="${2:-}"
  rm -f "$WORK/body.txt"
  if [[ -n "$entry" ]]; then
    (cd "$WORK/$repo" && PATH="$WORK/bin:$PATH" STUB_BODY="$WORK/body.txt" \
      ILOOP_PROVENANCE_ENTRY="$entry" \
      bash "$GITOPS" --role planner issue create "标题" \
      "原始正文第一行
原始正文第二行") >/dev/null 2>&1
  else
    (cd "$WORK/$repo" && PATH="$WORK/bin:$PATH" STUB_BODY="$WORK/body.txt" \
      bash "$GITOPS" --role planner issue create "标题" \
      "原始正文第一行
原始正文第二行") >/dev/null 2>&1
  fi
}

if ! create_issue repo-gh; then
  fail "gh issue create exited non-zero"
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
if [[ ! -f "$WORK/body.txt" ]]; then
  fail "stub CLI did not capture a body"
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi

echo "=== step 1: original body preserved + visible marker + repo URL ==="
if grep -Fq '原始正文第一行' "$WORK/body.txt" && grep -Fq '原始正文第二行' "$WORK/body.txt"; then
  pass "original body lines are preserved"
else
  fail "original body lines were lost"
fi
if grep -Fq '由 **iloop Skill** 创建' "$WORK/body.txt"; then
  pass "visible '由 iloop Skill 创建' marker exists"
else
  fail "visible marker is missing"
fi
if grep -Fq 'https://github.com/askdaddy/Git-Issue-Loop-Skill' "$WORK/body.txt"; then
  pass "Skill repository URL is present"
else
  fail "Skill repository URL is missing"
fi
if grep -Fq '<!--' "$WORK/body.txt"; then
  fail "provenance marker must be visible, not a hidden HTML comment"
else
  pass "marker is not a hidden HTML comment"
fi

echo "=== step 2: version / SHA / role / entry / UTC time ==="
if grep -Eq '`(v[0-9]+\.[0-9]+\.[0-9]+|untagged)`' "$WORK/body.txt"; then
  pass "version or untagged fallback is recorded"
else
  fail "version/untagged token is missing"
fi
if grep -Eq '\(`([0-9a-f]{7,40}|unknown)`\)' "$WORK/body.txt"; then
  pass "short SHA or unknown fallback is recorded"
else
  fail "short SHA/unknown token is missing"
fi
if grep -Fq '角色 `planner`' "$WORK/body.txt"; then
  pass "role is recorded"
else
  fail "role is missing"
fi
if grep -Fq '入口 `issue-create`' "$WORK/body.txt"; then
  pass "default entry is issue-create"
else
  fail "default entry is missing"
fi
if grep -Eq '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$WORK/body.txt"; then
  pass "UTC timestamp is recorded"
else
  fail "UTC timestamp is missing"
fi

echo "=== step 3: footer position and no path leak ==="
orig_line="$(grep -n '原始正文第二行' "$WORK/body.txt" | head -n 1 | cut -d: -f1)"
marker_line="$(grep -n '由 \*\*iloop Skill\*\* 创建' "$WORK/body.txt" | head -n 1 | cut -d: -f1)"
if [[ -n "$orig_line" && -n "$marker_line" && "$marker_line" -gt "$orig_line" ]]; then
  pass "footer is appended after the original body"
else
  fail "footer is not positioned after the original body"
fi
if grep -Fq "$ROOT" "$WORK/body.txt"; then
  fail "body leaks the local Skill root path"
else
  pass "body does not leak the local Skill root path"
fi

echo "=== step 4: entry override ==="
if ! create_issue repo-gh goal-bootstrap; then
  fail "issue create with ILOOP_PROVENANCE_ENTRY exited non-zero"
elif grep -Fq '入口 `goal-bootstrap`' "$WORK/body.txt"; then
  pass "ILOOP_PROVENANCE_ENTRY overrides the entry label"
else
  fail "entry override was not recorded"
fi

echo "=== step 5: gh / glab / tea platform coverage ==="
for platform in glab tea; do
  if ! create_issue "repo-$platform"; then
    fail "${platform} issue create exited non-zero"
  elif grep -Fq '由 **iloop Skill** 创建' "$WORK/body.txt" \
    && grep -Fq 'https://github.com/askdaddy/Git-Issue-Loop-Skill' "$WORK/body.txt"; then
    pass "${platform} creation carries the visible provenance footer"
  else
    fail "${platform} creation is missing the provenance footer"
  fi
done

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"