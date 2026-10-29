#!/usr/bin/env bash
# Black-box contract checks for the session-sticky iloop buffer.
# Frozen WHAT:
#   1. An effective invocation enters a session-level buffer; help/doctor-only do not.
#   2. Asking/confirming/blocking suspends the buffer instead of exiting it.
#   3. The next user message resumes the same Issue/stage/role/scope.
#   4. Only an explicit exit leaves; exit does not change Issue state or release the claim.
#   5. Buffer state is conversational only (no local state file).
# Run from repository root: bash test/iloop-buffer-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${ROOT}/SKILL.md"
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

assert_file "$SKILL"
assert_file "${ROOT}/README.md"
assert_file "${ROOT}/README_CN.md"

echo "=== step 1 buffer 定义与进入条件 ==="
assert_grep "$SKILL" '### 会话 buffer' "buffer section exists"
assert_grep "$SKILL" '粘性' "buffer is described as sticky"
assert_grep "$SKILL" '不是退出' "suspension is explicitly not exit"
assert_grep "$SKILL" '裸 `/iloop`' "bare invocation is an entry condition"
assert_grep "$SKILL" '自然语言闭环触发' "natural-language triggers enter the buffer"
assert_grep "$SKILL" 'help 不激活 buffer' "help does not activate the buffer"
assert_grep "$SKILL" 'help 只输出速览并保持当前挂起态' "help preserves an active suspension"
assert_grep "$SKILL" '不进入\*\*：`/iloop help`' "one-shot requests are excluded"
assert_grep "$SKILL" '即使随后停在 doctor/授权' "doctor failure is a suspension, not an exit"

echo "=== step 2 每条消息的处理顺序 ==="
assert_grep "$SKILL" '退出判定（最高优先）' "exit check runs first"
assert_grep "$SKILL" '恢复判定' "resume check runs second"
assert_grep "$SKILL" '内容归类' "new input is classified after resume"
assert_grep "$SKILL" '不得自行退出' "agent cannot exit on its own"
assert_grep "$SKILL" '一次一个目标' "buffer holds one active target"
assert_grep "$SKILL" '「暂停」.*这不是退出' "pause is not treated as exit"
assert_grep "$SKILL" '新目标 / 新编号' "new target is classified inside the buffer"
assert_grep "$SKILL" '不静默丢弃旧目标' "old target is not silently dropped"
assert_grep "$SKILL" '旧目标的 Issue 状态和认领保持原样' "old target keeps its state and claim"

echo "=== step 3 恢复语义 ==="
assert_grep "$SKILL" '同一 Issue、同一阶段、同一角色、同一执行范围' "resume keeps issue/stage/role/scope"
assert_grep "$SKILL" '不得把它当成新的独立请求' "reply is not reclassified as a new request"
assert_grep "$SKILL" '恢复后的第一条消息输出' "resume announces the resume point"
assert_grep "$SKILL" 'issue get <N> --strict' "resume performs a cheap remote-state check"
assert_grep "$SKILL" '重读对应 `roles/\*\.md`' "role file is re-read when absent from context"
assert_grep "$SKILL" '已通过且环境未变的 doctor' "resume does not repeat completed setup"
assert_grep "$SKILL" '等待环境、授权或升级决定' "environment waits resume by rerunning the check"
assert_grep "$SKILL" '远端阶段、认领或终态已变化' "remote divergence forces re-dispatch"

echo "=== step 4 挂起协议 ==="
assert_grep "$SKILL" '\[iloop-buffer\]' "suspension header exists"
assert_grep "$SKILL" '等待:<具体事项>' "header carries the concrete wait item"
assert_grep "$SKILL" '恢复:<§3\.x 步骤>' "header carries the resume point"
assert_grep "$SKILL" 'pending\(G\)' "header covers an uncreated goal draft"
assert_grep "$SKILL" 'pending\(pick\)' "header covers an unconfirmed auto-pick"
assert_grep "$SKILL" '不关闭 Issue、不设 `riper-blocked`' "suspension is not a terminal state"
assert_grep "$SKILL" '不释放认领' "suspension keeps the claim"
assert_grep "$SKILL" '不得自行假设用户答复继续' "agent must not fabricate a reply"

echo "=== step 5 退出协议 ==="
assert_grep "$SKILL" '/iloop exit' "exit command exists"
assert_grep "$SKILL" '/iloop stop' "stop alias exists"
assert_grep "$SKILL" '退出 iloop' "Chinese exit phrase exists"
assert_grep "$SKILL" '结束 iloop' "second Chinese exit phrase exists"
assert_grep "$SKILL" 'exit iloop' "English exit phrase exists"
assert_grep "$SKILL" '交接摘要' "exit prints a handoff summary"
assert_grep "$SKILL" '不写 Issue 状态' "exit does not write Issue state"
assert_grep "$SKILL" '认领默认保留' "exit keeps the claim by default"
assert_grep "$SKILL" 'issue claim <N> release' "exit reports how to release the claim"
assert_grep "$SKILL" '挂起在 \[G\] 草稿或自动挑选确认时.*丢弃' "exit discards an uncreated draft"
assert_grep "$SKILL" '新会话需重新' "new sessions are not buffered"

echo "=== step 6 buffer 前置于调用分类 ==="
assert_grep "$SKILL" 'buffer 前置' "layer 0 has a buffer preamble"
assert_grep "$SKILL" '本表只对 buffer 内真正的新输入分类' "layer 0 excludes exit/resume"
assert_grep "$SKILL" '退出优先于 help' "exit outranks help"
assert_grep "$SKILL" '按 §\*\*会话 buffer\*\* 协议判定显性退出或挂起恢复' "§3.0 checks buffer first"
assert_grep "$SKILL" '\| 显性退出.*\|' "layer 0 table has an explicit exit row"
assert_grep "$SKILL" '不自动关闭、不自动释放认领' "exit row forbids automatic state changes"

echo "=== step 7 quick usage and README ==="
assert_grep "$SKILL" '/iloop exit.*显性退出 buffer' "§4 documents /iloop exit"
assert_grep "$SKILL" '一次有效调用后会话保持 buffer' "§4 states the sticky behavior"
assert_grep "${ROOT}/README_CN.md" '会话粘性 buffer' "Chinese README documents the buffer"
assert_grep "${ROOT}/README_CN.md" '/iloop exit' "Chinese README documents exit"
assert_grep "${ROOT}/README.md" 'session-sticky iloop buffer' "English README documents the buffer"
assert_grep "${ROOT}/README.md" '/iloop exit' "English README documents exit"
assert_grep "${ROOT}/README.md" '22 shell invariant suites' "English README suite count is current"

echo "=== step 8 conversational state only ==="
assert_no_grep "$SKILL" '\.loop-state' "SKILL.md must not introduce .loop-state"
assert_grep "$SKILL" '不新增本地状态文件' "buffer explicitly creates no state file"

echo "=== step 9 role-level suspension ==="
for role in planner developer reviewer; do
  assert_file "${ROOT}/roles/${role}.md"
  assert_grep "${ROOT}/roles/${role}.md" '不是退出 iloop' "${role} stop conditions are suspensions"
  assert_grep "${ROOT}/roles/${role}.md" '\[iloop-buffer\]' "${role} emits the buffer header"
done

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"