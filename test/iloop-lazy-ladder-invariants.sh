#!/usr/bin/env bash
# Black-box contract checks for Issue #8 (lazy-code ladder / C2).
# Run from repository root: bash test/iloop-lazy-ladder-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
    grep -nE -- "$pat" "$file" | head -n 5
    FAILS=$((FAILS + 1))
  else
    echo "PASS $msg"
  fi
}

LADDER="${ROOT}/references/lazy-ladder.md"
MANIFEST="${ROOT}/skill-manifest.json"
SKILL="${ROOT}/SKILL.md"

echo "=== step 1 ladder file ==="
assert_file "$LADDER"
assert_grep "$LADDER" 'YAGNI' "ladder names YAGNI"
assert_grep "$LADDER" '标准库' "ladder names stdlib"
assert_grep "$LADDER" '原生' "ladder names native"
assert_grep "$LADDER" 'skipped:' "ladder has skipped: format"
assert_grep "$LADDER" 'add when:' "ladder has add when: format"
assert_grep "$LADDER" 'ponytail' "ladder attributes ponytail"
assert_grep "$LADDER" 'MIT' "ladder names MIT"
assert_no_grep "$LADDER" '/ponytail[[:space:]]+lite' "ladder does not expose /ponytail lite as a command"

echo "=== step 2 manifest ==="
assert_grep "$MANIFEST" 'references/lazy-ladder.md' "requiredPaths includes lazy-ladder"
assert_grep "$MANIFEST" '"version": "0.5.0"' "skill.version is 0.5.0"
if python3 -m json.tool "$MANIFEST" >/dev/null; then
  echo "PASS manifest is valid JSON"
else
  echo "FAIL manifest is not valid JSON"
  FAILS=$((FAILS + 1))
fi

echo "=== step 3 SDD + persona load ==="
assert_grep "$SKILL" 'references/lazy-ladder.md' "SKILL points at lazy-ladder"
assert_grep "$SKILL" '禁止添加计划外功能' "SDD still forbids extra features"
assert_grep "$SKILL" '进入 \*\*\[I\] / \[P\] / \[E\] / \[R\]审查\*\* 之前|还必须先完整读取 `references/lazy-ladder.md`' "§1 requires reading the ladder"

echo "=== step 4 RIPER stages ==="
assert_grep "$SKILL" '代码量' "§3.3 includes 代码量"
assert_grep "$SKILL" '新依赖' "§3.3 includes 新依赖"
assert_grep "$SKILL" '验收标准冻结 WHAT|逻辑说明是建议 HOW' "§3.4 splits WHAT/HOW"
assert_grep "$SKILL" '更高 rung|改道' "§3.5 allows redirect"
assert_grep "$SKILL" '可删清单' "§3.6 has delete-list"
assert_grep "$SKILL" '不单独 FAIL|不阻塞' "§3.6 delete-list is non-blocking"

echo "=== step 5 planner ==="
assert_grep "${ROOT}/roles/planner.md" 'references/lazy-ladder.md' "planner loads ladder"
assert_grep "${ROOT}/roles/planner.md" '代码量' "planner [I] has 代码量"
assert_grep "${ROOT}/roles/planner.md" '新依赖' "planner [I] has 新依赖"
assert_grep "${ROOT}/roles/planner.md" '可观察|WHAT' "planner [P] freezes WHAT"
assert_grep "${ROOT}/roles/planner.md" '建议 HOW|不冻结' "planner [P] HOW is advisory"

echo "=== step 6 developer ==="
assert_grep "${ROOT}/roles/developer.md" 'references/lazy-ladder.md' "developer loads ladder"
assert_grep "${ROOT}/roles/developer.md" 'skipped:' "developer redirect skipped:"
assert_grep "${ROOT}/roles/developer.md" 'used:' "developer redirect used:"
assert_grep "${ROOT}/roles/developer.md" 'add when:' "developer redirect add when:"
assert_no_grep "${ROOT}/roles/developer.md" '涉及哪些文件就改哪些文件' "developer file list is not an absolute cage"
assert_grep "${ROOT}/roles/developer.md" '禁止在 `test/` 下新增或修改验收测试脚本' "developer still cannot write test/"
assert_grep "${ROOT}/roles/developer.md" '禁止添加计划外功能' "developer still forbids extra features"

echo "=== step 7 reviewer ==="
assert_grep "${ROOT}/roles/reviewer.md" 'references/lazy-ladder.md' "reviewer loads ladder"
assert_grep "${ROOT}/roles/reviewer.md" '新依赖|行为' "reviewer overrun is behavior/deps"
assert_grep "${ROOT}/roles/reviewer.md" 'delete:' "reviewer tag delete:"
assert_grep "${ROOT}/roles/reviewer.md" 'stdlib:' "reviewer tag stdlib:"
assert_grep "${ROOT}/roles/reviewer.md" 'native:' "reviewer tag native:"
assert_grep "${ROOT}/roles/reviewer.md" 'yagni:' "reviewer tag yagni:"
assert_grep "${ROOT}/roles/reviewer.md" 'shrink:' "reviewer tag shrink:"
assert_grep "${ROOT}/roles/reviewer.md" '不单独 FAIL|不阻塞判定' "reviewer delete-list does not FAIL alone"

echo "=== step 8 design template ==="
assert_grep "${ROOT}/templates/design.md" '代码量' "design template has 代码量"
assert_grep "${ROOT}/templates/design.md" '新依赖' "design template has 新依赖"

echo "=== step 9 plan template ==="
assert_grep "${ROOT}/templates/plan.md" '不冻结' "plan template marks HOW unfrozen"
assert_grep "${ROOT}/templates/plan.md" 'WHAT' "plan template marks WHAT"
assert_grep "${ROOT}/templates/plan.md" '禁止计划外功能' "plan template forbids extra features"
assert_no_grep "${ROOT}/templates/plan.md" '禁止自由发挥' "plan template no longer bans all HOW discretion"

echo "=== step 10 verify-report template ==="
assert_grep "${ROOT}/templates/verify-report.md" 'delete:' "verify-report tag delete:"
assert_grep "${ROOT}/templates/verify-report.md" 'stdlib:' "verify-report tag stdlib:"
assert_grep "${ROOT}/templates/verify-report.md" 'native:' "verify-report tag native:"
assert_grep "${ROOT}/templates/verify-report.md" 'yagni:' "verify-report tag yagni:"
assert_grep "${ROOT}/templates/verify-report.md" 'shrink:' "verify-report tag shrink:"
assert_grep "${ROOT}/templates/verify-report.md" 'Lean already. Ship.|net:' "verify-report has net/Lean closer"
assert_grep "${ROOT}/templates/verify-report.md" '不阻塞' "verify-report delete-list non-blocking"
assert_grep "${ROOT}/templates/verify-report.md" '新依赖|行为' "verify-report overrun is behavior/deps"

echo "=== out of scope ==="
if git -C "$ROOT" diff HEAD -- scripts/git-ops.sh | grep -q .; then
  echo "FAIL scripts/git-ops.sh has uncommitted diff"
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
