#!/usr/bin/env bash
# Black-box contract checks for Issue #13 (/iloop help subcommand).
# Plan froze WHAT: SKILL.md must document a TERMINATING `help` subcommand that prints a
# concise usage overview + the local skill version (from `git describe --tags --exact-match`
# at the Skill root, offline, NOT manifest skill.version), is recognized BEFORE "a new goal",
# and adds zero new code (Option A: pure SKILL.md doc convention).
# These checks grep the doc for the frozen acceptance wording of steps 1-3, and guard that
# no business script / manifest changed and no scripts/help.sh was added.
# Per the #11 C6 lesson: "version is NOT manifest skill.version" is asserted POSITIVELY
# (doc contains `describe --tags --exact-match HEAD` and the forbidding sentence), never as
# a negative "doc must not contain skill.version" (the doc cites skill.version as a counter-example).
# Run from repository root: bash test/iloop-help-invariants.sh
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

echo "=== step 0 target doc exists ==="
assert_file "$SKILL"

echo "=== step 1 调用入口 help 段: 触发 / 终止语义 / 版本来源 / 五要素 ==="
assert_grep "$SKILL" 'help 子命令.*用法.*版本' "调用入口 help 段同时含 help / 用法 / 版本"
assert_grep "$SKILL" '/iloop help' "主触发 /iloop help 存在"
assert_grep "$SKILL" '/iloop --help' "等价触发 /iloop --help 存在"
assert_grep "$SKILL" '/iloop -h' "等价触发 /iloop -h 存在"
assert_grep "$SKILL" '随即停止|后.*停止' "help 命中后停止（终止语义）"
assert_grep "$SKILL" '不.*加载.*roles' "终止: 不加载角色 roles/*.md"
assert_grep "$SKILL" '不.*进入 RIPER 循环' "终止: 不进入 RIPER 循环"
assert_grep "$SKILL" '不.*改 Issue 状态' "终止: 不改 Issue 状态"
assert_grep "$SKILL" '不.*写评论' "终止: 不写评论"
assert_grep "$SKILL" '不.*建 Issue' "终止: 不建 Issue"
assert_grep "$SKILL" '不依赖 doctor / CLI 授权' "help 不依赖 doctor / CLI 授权"
assert_grep "$SKILL" 'describe --tags --exact-match HEAD' "版本号来源 describe --tags --exact-match HEAD（正向断言, 遵 C6 教训）"
assert_grep "$SKILL" 'SKILL\.md.*所在目录.*Skill 根' "版本取自 Skill 根（当前 SKILL.md 所在目录）"
assert_grep "$SKILL" '纯本地.*不联网' "版本号纯本地、不联网"
assert_grep "$SKILL" '不.*skill\.version.*当作已安装版本' "文中正向声明不以 manifest skill.version 为已安装版本"
assert_grep "$SKILL" '精简速览五要素' "精简速览五要素标题存在"
assert_grep "$SKILL" '定位.*调用入口.*RIPER 六阶段.*三角色.*版本号' "五要素齐全（定位/调用入口/RIPER六阶段/三角色/版本号）"

echo "=== step 2 §3.0.1 第0层分类表: help 行 + 优先 + 既有5类保留 ==="
assert_grep "$SKILL" '\| help / 用法 / 版本' "§3.0.1 第0层表含 help 行"
assert_grep "$SKILL" '输出精简用法速览.*停止.*不加载角色' "help 行终止去向（停止/不加载角色/不进循环）"
assert_grep "$SKILL" '(先于|优先于).*一句新目标' "help 意图先于/优先于『一句新目标』识别"
assert_grep "$SKILL" '一句新目标（无 Issue 编号）' "既有分类行保留: 一句新目标"
assert_grep "$SKILL" '编号 /「落地 #N」' "既有分类行保留: 编号 / 落地 #N"
assert_grep "$SKILL" '「推进迭代」' "既有分类行保留: 推进迭代"
assert_grep "$SKILL" '口头覆盖' "既有分类行保留: 口头覆盖"
assert_grep "$SKILL" '仅环境自检 / doctor' "既有分类行保留: 仅环境自检 doctor"

echo "=== step 3 §4 快速用法: /iloop help 示例 + 既有示例保留 ==="
assert_grep "$SKILL" '/iloop help.*→.*用法.*版本' "§4 /iloop help 示例含用法 + 版本"
assert_grep "$SKILL" '/iloop 我要实现 XXX' "§4 既有示例保留: 目标直入"
assert_grep "$SKILL" '"推进迭代".*扫描 open issue' "§4 既有示例保留: 推进迭代"
assert_grep "$SKILL" '检查 skill 更新' "§4 既有示例保留: 检查 skill 更新"
assert_grep "$SKILL" '落地 issue #42' "§4 既有示例保留: 落地 issue #42"

echo "=== guards (C5 + Option A): no business-script / manifest change, no help.sh ==="
if git -C "$ROOT" diff HEAD -- scripts/git-ops.sh | grep -q .; then
  echo "FAIL git-ops.sh has a diff vs HEAD (C5)"
  FAILS=$((FAILS + 1))
else
  echo "PASS git-ops.sh unchanged vs HEAD (C5)"
fi
if git -C "$ROOT" diff HEAD -- skill-manifest.json | grep -q .; then
  echo "FAIL skill-manifest.json has a diff vs HEAD (C5)"
  FAILS=$((FAILS + 1))
else
  echo "PASS skill-manifest.json unchanged vs HEAD (C5)"
fi
if [[ -f "${ROOT}/scripts/help.sh" ]]; then
  echo "FAIL scripts/help.sh exists (Option A must add zero new files)"
  FAILS=$((FAILS + 1))
else
  echo "PASS no scripts/help.sh (Option A: zero new files)"
fi

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
