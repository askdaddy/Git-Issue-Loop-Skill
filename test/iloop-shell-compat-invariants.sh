#!/usr/bin/env bash
# Black-box contract checks for Issue #11 (shell compatibility).
# The install/update protocol is executed by the Agent as inline shell on the host's
# default shell (zsh on modern macOS), which lacks bash builtins like shopt/nullglob.
# These checks assert the docs require bash and give a zsh-safe migration snippet,
# and that no business script was touched (C1).
# Run from repository root: bash test/iloop-shell-compat-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${ROOT}/SKILL.md"
INSTALL="${ROOT}/INSTALL.md"
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

echo "=== step 0 target docs exist ==="
assert_file "$INSTALL"
assert_file "$SKILL"

echo "=== step 1 INSTALL.md: protocol shell must run under bash ==="
assert_grep "$INSTALL" 'shell 逻辑必须在.*bash' "protocol shell logic must run under bash"
assert_grep "$INSTALL" '依赖宿主默认 shell' "forbids relying on the host default shell"
assert_grep "$INSTALL" 'zsh' "names zsh as a host default shell"
assert_grep "$INSTALL" 'shopt' "names shopt as a missing bash builtin (root cause)"
assert_grep "$INSTALL" 'nullglob' "names nullglob as a missing bash builtin (root cause)"
assert_grep "$INSTALL" 'bash file\.sh' "gives actionable 'bash file.sh'"
assert_grep "$INSTALL" 'bash -c' "gives actionable 'bash -c'"
assert_grep "$INSTALL" '#!/usr/bin/env bash' "notes bundled scripts carry a bash shebang"
assert_grep "$INSTALL" 'git reset --hard.*git clean.*递归删除' "keeps no-destructive-git guarantee (reset/clean/recursive delete)"
assert_grep "$INSTALL" '非同源或有本地修改：停止' "keeps fail-on-foreign-or-dirty (stop)"

echo "=== step 2 INSTALL.md: migration is zsh-safe (shopt/nullglob only as counter-example) ==="
assert_grep "$INSTALL" '不得依赖 bash-only 的.*shopt -s nullglob' "frames shopt/nullglob as bash-only to avoid"
assert_grep "$INSTALL" '\[ -e ' "migration uses an existence check '[ -e ]'"
assert_grep "$INSTALL" '\|\| continue' "guards the no-match case with '|| continue'"
assert_grep "$INSTALL" '仅改名；不删除' "keeps rename-only (no delete) semantics"
assert_grep "$INSTALL" '已存在，停止（不覆盖、不删除）' "aborts if the target exists (no overwrite/delete)"

echo "=== step 3 SKILL.md §0 runtime env: zsh host + bash for Agent inline shell ==="
assert_grep "$SKILL" '运行环境.*zsh' "§0 runtime env names zsh"
assert_grep "$SKILL" '内联 shell.*必须用.*bash' "§0 requires bash for Agent inline shell"
assert_grep "$SKILL" 'Git Bash' "keeps the Windows Git Bash requirement"
assert_grep "$SKILL" '不支持 CMD / PowerShell' "keeps CMD/PowerShell unsupported"

echo "=== C1 guard: no business-script changes ==="
if git -C "$ROOT" diff HEAD -- scripts/git-ops.sh | grep -q .; then
  echo "FAIL git-ops.sh has a diff vs HEAD (C1)"
  FAILS=$((FAILS + 1))
else
  echo "PASS git-ops.sh unchanged vs HEAD (C1)"
fi

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
