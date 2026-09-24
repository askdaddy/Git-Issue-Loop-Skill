#!/usr/bin/env bash
# Black-box contract checks for Issue #9 (skill update check).
# Run from repository root: bash test/iloop-check-update-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${ROOT}/SKILL.md"
INSTALL="${ROOT}/INSTALL.md"
MANIFEST="${ROOT}/skill-manifest.json"
SCRIPT="${ROOT}/scripts/check-update.sh"
FAILS=0

assert_file() {
  if [[ ! -f "$1" ]]; then
    echo "FAIL missing file: $1"
    FAILS=$((FAILS + 1))
  else
    echo "PASS exists $1"
  fi
}

assert_grep() {
  local file="$1" pat="$2" msg="$3"
  if ! grep -Eq -- "$pat" "$file"; then
    echo "FAIL $msg"
    echo "  file=$file pattern=$pat"
    FAILS=$((FAILS + 1))
  else
    echo "PASS $msg"
  fi
}

assert_no_grep() {
  local file="$1" pat="$2" msg="$3"
  if grep -Eq -- "$pat" "$file"; then
    echo "FAIL $msg"
    echo "  file=$file forbidden=$pat"
    FAILS=$((FAILS + 1))
  else
    echo "PASS $msg"
  fi
}

echo "=== step 1 check-update.sh ==="
assert_file "$SCRIPT"
chmod +x "$SCRIPT" 2>/dev/null || true

out1="$("$SCRIPT" --compare v0.3.0 v0.4.0 2>/dev/null || true)"
ec1=0
"$SCRIPT" --compare v0.3.0 v0.4.0 >/dev/null 2>&1 || ec1=$?
if [[ "$ec1" -eq 2 ]] && printf '%s\n' "$out1" | grep -q '^status=update-available$' \
  && printf '%s\n' "$out1" | grep -q '^latest_tag=' \
  && printf '%s\n' "$out1" | grep -q '^repository='; then
  echo "PASS --compare v0.3.0 v0.4.0 → exit 2 update-available + keys"
else
  echo "FAIL --compare v0.3.0 v0.4.0 (exit=$ec1)"
  printf '%s\n' "$out1"
  FAILS=$((FAILS + 1))
fi

ec2=0
"$SCRIPT" --compare v0.4.0 v0.4.0 >/dev/null 2>&1 || ec2=$?
out2="$("$SCRIPT" --compare v0.4.0 v0.4.0 2>/dev/null || true)"
if [[ "$ec2" -eq 0 ]] && printf '%s\n' "$out2" | grep -q '^status=current$'; then
  echo "PASS --compare v0.4.0 v0.4.0 → exit 0 current"
else
  echo "FAIL --compare v0.4.0 v0.4.0 (exit=$ec2)"
  FAILS=$((FAILS + 1))
fi

ec3=0
"$SCRIPT" --compare v0.4.0 v0.4.0-beta.1 >/dev/null 2>&1 || ec3=$?
out3="$("$SCRIPT" --compare v0.4.0 v0.4.0-beta.1 2>/dev/null || true)"
if [[ "$ec3" -eq 1 ]] && printf '%s\n' "$out3" | grep -qv '^status=update-available$'; then
  echo "PASS pre-release latest is not treated as a higher stable tag"
else
  echo "FAIL pre-release compared as upgrade (exit=$ec3)"
  printf '%s\n' "$out3"
  FAILS=$((FAILS + 1))
fi

if grep -Eq '^[^#]*git remote|^[^#]*git-ops.sh doctor' "$SCRIPT"; then
  echo "FAIL script must not use project git remote or doctor"
  FAILS=$((FAILS + 1))
else
  echo "PASS script does not call git remote / doctor"
fi

if grep -q 'describe --tags --exact-match' "$SCRIPT" && ! grep -Eq 'local_ref=.*\$\{?version' "$SCRIPT"; then
  echo "PASS local_ref sourced from git describe --exact-match"
else
  echo "FAIL local_ref source unclear"
  FAILS=$((FAILS + 1))
fi

echo "=== step 2 SKILL.md protocol ==="
assert_grep "$SKILL" '先于 doctor' "update check is before doctor"
assert_grep "$SKILL" '不得自行升级' "must not self-upgrade"
assert_grep "$SKILL" '本会话尚未执行过' "once per session"
assert_grep "$SKILL" '不阻塞' "failure does not block the loop"
assert_grep "$SKILL" '更新检查.*不需要角色|不需要角色' "no persona required for the check"

echo "=== step 3 docs / manifest ==="
assert_grep "$INSTALL" '启动时的版本检查|check-update' "INSTALL documents startup check"
assert_grep "$INSTALL" '不得自行切换|询问是否' "INSTALL says the user decides"
assert_grep "${ROOT}/README_CN.md" '稳定 tag|更新' "Chinese README mentions update check"
assert_grep "${ROOT}/README.md" 'stable git tag|ask before upgrading' "English README mentions update check"
assert_grep "$MANIFEST" '"version": "0.6.4"' "skill.version is 0.6.4"
assert_grep "$MANIFEST" 'scripts/check-update.sh' "requiredPaths includes check-update.sh"

if git -C "$ROOT" diff HEAD -- scripts/git-ops.sh | grep -q .; then
  echo "FAIL git-ops.sh has a diff vs HEAD"
  FAILS=$((FAILS + 1))
else
  echo "PASS git-ops.sh unchanged vs HEAD"
fi

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
