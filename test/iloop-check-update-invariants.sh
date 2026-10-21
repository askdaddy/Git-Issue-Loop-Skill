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
assert_grep "$MANIFEST" '"version": "0.6.9"' "skill.version is 0.6.9"
assert_grep "$MANIFEST" 'scripts/check-update.sh' "requiredPaths includes check-update.sh"

echo "=== step 4 failure-path observability (offline, git shim) ==="
GIT_REAL="$(command -v git)"
PATH_REAL="$PATH"
REPO_URL="$(sed -n 's/.*"repository": *"\([^"]*\)".*/\1/p' "$MANIFEST" | head -n 1)"
assert_grep "$SKILL" '无法确认是否为最新版|无法确认.*最新版' "SKILL.md: must tell user the version is unconfirmed"
assert_grep "$SKILL" 'check-update: git:|git 失败原因' "SKILL.md: must relay git's own failure cause"
assert_grep "$SKILL" '检查失败.*local_ref' "SKILL.md: failure bullet still requires local_ref"
assert_grep "$INSTALL" '无法确认是否为最新版' "INSTALL.md: failure path says unconfirmed"

# 用 PATH 上的 git 假程序让远端 ls-remote 失败，其余 git 调用透传真 git；
# 脚本必须：exit 1 + 透出 git 原因 + 仍输出 status=error/local_ref/repository=。
if [[ "$(uname)" == "Darwin" ]]; then
  SHIM_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/iloop.shim.XXXXXX")"
else
  SHIM_DIR="$(mktemp -d)"
fi
cat > "${SHIM_DIR}/git" <<SHIM
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ "\$a" == "ls-remote" ]]; then
    echo "fatal: unable to access '${REPO_URL}': Failed to connect to github.com port 443" >&2
    exit 128
  fi
done
exec ${GIT_REAL} "\$@"
SHIM
chmod +x "${SHIM_DIR}/git"

SHIM_ERR_FILE="$(mktemp "${TMPDIR:-/tmp}/iloop-shim-err.XXXXXX")"
set +e
SHIM_OUT="$(PATH="${SHIM_DIR}:${PATH_REAL}" "${SCRIPT}" 2>"${SHIM_ERR_FILE}")"
SHIM_EC=$?
set -e
SHIM_ERR="$(cat "${SHIM_ERR_FILE}" 2>/dev/null || true)"
rm -f "${SHIM_ERR_FILE}"
rm -rf "${SHIM_DIR}"

if [[ "$SHIM_EC" -eq 1 ]]; then
  echo "PASS ls-remote failure → exit 1"
else
  echo "FAIL ls-remote failure exit=$SHIM_EC (want 1)"
  echo "  stdout=$SHIM_OUT"
  echo "  stderr=$SHIM_ERR"
  FAILS=$((FAILS + 1))
fi

if printf '%s\n' "$SHIM_ERR" | grep -q '^check-update: git: fatal:'; then
  echo "PASS git's own stderr is surfaced (prefixed check-update: git:)"
else
  echo "FAIL git failure cause missing from stderr"
  echo "  stderr=$SHIM_ERR"
  FAILS=$((FAILS + 1))
fi

for k in '^status=error$' '^local_ref=' '^repository='; do
  if printf '%s\n' "$SHIM_OUT" | grep -Eq -- "$k"; then
    echo "PASS failure output still machine-readable: $k"
  else
    echo "FAIL failure output missing $k"
    echo "  stdout=$SHIM_OUT"
    FAILS=$((FAILS + 1))
  fi
done

if printf '%s\n' "$SHIM_OUT" | grep -Eq '^local_ref=(none|v[0-9])'; then
  echo "PASS local_ref carried through the failure path"
else
  echo "FAIL local_ref lost on failure"
  echo "  stdout=$SHIM_OUT"
  FAILS=$((FAILS + 1))
fi

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
