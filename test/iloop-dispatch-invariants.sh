#!/usr/bin/env bash
# Black-box contract checks for Issue #6 (iloop stage dispatch).
# Run from repository root: bash test/iloop-dispatch-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${ROOT}/SKILL.md"
FAILS=0

assert_file() {
  if [[ ! -f "$1" ]]; then
    echo "FAIL missing file: $1"
    FAILS=$((FAILS + 1))
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

assert_file "$SKILL"
assert_file "${ROOT}/roles/planner.md"
assert_file "${ROOT}/roles/developer.md"
assert_file "${ROOT}/roles/reviewer.md"
assert_file "${ROOT}/README.md"
assert_file "${ROOT}/README_CN.md"

echo "=== step 1 §3.0 / §3.0.1 ==="
assert_no_grep "$SKILL" '否则直接进入 \[R\] 研究阶段' "§3.0 must not send non-goals straight to Research"
assert_grep "$SKILL" '3\.0\.1|启动分发' "§3.0.1 dispatch section exists"
assert_grep "$SKILL" '一句新目标' "layer 0 includes new goal"
assert_grep "$SKILL" '落地 #N|编号' "layer 0 includes issue number"
assert_grep "$SKILL" '推进迭代' "layer 0 includes backlog scan"
assert_grep "$SKILL" '只验收|只排 plan|重做研究' "layer 0 includes verbal override"
assert_grep "$SKILL" 'doctor' "layer 0 includes doctor"
assert_grep "$SKILL" 'riper-research' "layer 1 includes riper-research"
assert_grep "$SKILL" 'riper-innovation' "layer 1 includes riper-innovation"
assert_grep "$SKILL" 'riper-plan' "layer 1 includes riper-plan"
assert_grep "$SKILL" 'riper-execute' "layer 1 includes riper-execute"
assert_grep "$SKILL" 'riper-review' "layer 1 includes riper-review"
assert_grep "$SKILL" 'riper-verified' "layer 1 includes riper-verified"
assert_grep "$SKILL" 'riper-blocked' "layer 1 includes riper-blocked"
assert_grep "$SKILL" '分发完成之前读取任何 `roles/\*\.md`|禁止在分发完成之前读取' "must not load roles before dispatch"
assert_grep "$SKILL" '禁止把更后状态改回本阶段|禁止在分发结果不是' "C6 no backward status write"

echo "=== step 2 diagram ==="
assert_grep "$SKILL" '启动分发|dispatch' "state diagram mentions dispatch"
assert_grep "$SKILL" '\[E\]执行|\[E\] 执行' "diagram has execute branch"
assert_grep "$SKILL" '\[R\]审查|\[R\] 审查' "diagram has review branch"

echo "=== step 3 §1 ==="
assert_grep "$SKILL" '先完成 §3\.0\.1 启动分发' "§1 dispatch before persona"
assert_grep "$SKILL" 'roles/planner.md' "§1 still has planner mapping"
assert_grep "$SKILL" 'roles/developer.md' "§1 still has developer mapping"
assert_grep "$SKILL" 'roles/reviewer.md' "§1 still has reviewer mapping"

echo "=== step 4 §3.1 ==="
assert_no_grep "$SKILL" '编号输入直接从 §3\.2' "must not hard-wire numbers into §3.2"
assert_no_grep "$SKILL" '编号输入直接从研究' "must not hard-wire numbers into Research"
assert_grep "$SKILL" '完成后进入 §3\.0\.1 启动分发' "§3.1 step 8 enters dispatch"

echo "=== step 5 §3.2 ==="
assert_grep "$SKILL" '仅当 §3\.0\.1 分发结果为 `\[R\]` 时进入本节' "§3.2 gated on dispatch"
assert_grep "$SKILL" '禁止从零重开调研' "§3.2 fills gaps instead of restarting research"

echo "=== step 6 frontmatter / §4 ==="
assert_grep "$SKILL" '0 帧|分发角色' "frontmatter mentions dispatch or frame-0"
assert_no_grep "$SKILL" '落地 issue #42.*从 \[R\] 研究阶段开始|落地 issue #42.*从研究阶段开始完整循环' "§4 numbered entry is not Research-only"
assert_grep "$SKILL" '对每个走第 1 层分发' "§4 backlog scan uses layer 1 dispatch"

echo "=== step 7 planner ==="
assert_grep "${ROOT}/roles/planner.md" '分发|0 帧' "planner mentions dispatch/frame-0"
assert_grep "${ROOT}/roles/planner.md" 'C6|riper-execute' "planner forbids unsolicited backward status"

echo "=== step 8 developer ==="
assert_grep "${ROOT}/roles/developer.md" '分发|0 帧' "developer mentions dispatch/frame-0"
assert_grep "${ROOT}/roles/developer.md" '禁止关闭' "developer still cannot close issues"

echo "=== step 9 reviewer ==="
assert_grep "${ROOT}/roles/reviewer.md" '分发|0 帧' "reviewer mentions dispatch/frame-0"
assert_grep "${ROOT}/roles/reviewer.md" '禁止改动任何业务代码' "reviewer T0 intact"
assert_grep "${ROOT}/roles/reviewer.md" '关闭权专属本角色' "reviewer close right intact"

echo "=== step 10 README_CN ==="
assert_grep "${ROOT}/README_CN.md" '分发|0 帧|按状态切入' "Chinese README mentions dispatch"
assert_no_grep "${ROOT}/README_CN.md" '再从研究阶段进入闭环' "Chinese README does not force Research for all numbered entries"

echo "=== step 11 README ==="
assert_grep "${ROOT}/README.md" 'dispatch|frame-0' "English README mentions dispatch"
assert_grep "${ROOT}/README.md" 'instead of always starting at Research' "English README numbered entry is not always Research"

echo "=== out of scope: no git-ops / loop-state ==="
if git -C "$ROOT" diff HEAD -- scripts/git-ops.sh | grep -q .; then
  echo "FAIL scripts/git-ops.sh has uncommitted diff"
  FAILS=$((FAILS + 1))
else
  echo "PASS git-ops.sh clean vs HEAD (not part of #6 commit set)"
fi
assert_no_grep "$SKILL" '\.loop-state' "SKILL.md must not introduce .loop-state"

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
