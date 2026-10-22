#!/usr/bin/env bash
# ============================================================================
# runtime-events.sh —— iloop.runtime.v1 结构化运行事件（opt-in，FD3 NDJSON）
#
# 契约见 references/runtime-output.md。本文件由 git-ops.sh 显式 source，
# 自身不产生任何顶层副作用。
#
# 启用方式（默认完全关闭）：
#   调用者预先打开 fd3，并设置 ILOOP_EVENTS_FD=3：
#     exec 3>events.ndjson
#     ILOOP_EVENTS_FD=3 ./scripts/git-ops.sh --role developer issue status 42 riper-execute
#
# 首版覆盖：issue priority / issue status / issue comment / guard。
# 约束：
#   - 每个进程最多一条完成事件；
#   - 只写 fd3，不写日志文件、不联网、不采集参数正文/路径/URL；
#   - 观测失败不得改变 stdout / stderr / 原退出码，不得重放远端写入；
#   - 未知保持 unknown，禁止猜测；
#   - Bash 3.2 / Windows Git Bash 兼容（indexed arrays only，无 associative array）。
# ============================================================================

_ILOOP_EVT_ACTIVE=0
_ILOOP_EVT_EMITTED=0
_ILOOP_EVT_ACTION="unknown"
_ILOOP_EVT_ISSUE="unknown"
_ILOOP_EVT_ROLE="unknown"
_ILOOP_EVT_RESULT="failed"
_ILOOP_EVT_RULE="unknown"
_ILOOP_EVT_CHECKPOINT="requested"
_ILOOP_EVT_SIDE_EFFECTS="none"
_ILOOP_EVT_START=""
_ILOOP_EVT_RUN_ID="unknown"
_ILOOP_EVT_SKILL_TAG="unknown"
_ILOOP_EVT_SKILL_SHA="unknown"

# 把自由值收敛为固定白名单字符；不符合的一律 unknown（脱敏兜底）。
_iloop_evt_safe() {
  case "${1:-}" in
    '')                 printf '%s' 'unknown' ;;
    *[!A-Za-z0-9._:-]*) printf '%s' 'unknown' ;;
    *)                  printf '%s' "$1" ;;
  esac
}

# 128-bit 随机十六进制（32 字符）；生成失败输出空串并由调用方置 unknown。
_iloop_evt_rand_hex() {
  local hex=""
  hex="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')" || return 1
  case "${hex}" in
    *[!0-9a-f]*) return 1 ;;
  esac
  [[ ${#hex} -eq 32 ]] || return 1
  printf '%s\n' "${hex}"
}

# Skill tag/SHA 只读本地 git 元数据；非 git 安装或字段不合规时保持 unknown。
_iloop_evt_skill_meta() {
  local root tag sha
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd 2>/dev/null)" || return 0
  [[ -e "${root}/.git" ]] || return 0

  tag="$(git -C "${root}" describe --tags --exact-match HEAD 2>/dev/null)" || tag=""
  case "${tag}" in
    v[0-9]*.[0-9]*.[0-9]*) _ILOOP_EVT_SKILL_TAG="$(_iloop_evt_safe "${tag}")" ;;
  esac

  sha="$(git -C "${root}" rev-parse HEAD 2>/dev/null)" || sha=""
  case "${sha}" in
    *[!0-9a-f]*) sha="" ;;
  esac
  if [[ ${#sha} -ge 40 && ${#sha} -le 64 ]]; then
    _ILOOP_EVT_SKILL_SHA="${sha}"
  fi
  return 0
}

# 为受覆盖命令启用事件并注册 EXIT trap。
# 用法：_iloop_evt_arm <action> [issue]
_iloop_evt_arm() {
  local action="$1" issue="${2:-}" rid=""

  # 仅显式 ILOOP_EVENTS_FD=3 且调用者确实打开了 fd3 时启用。
  [[ "${ILOOP_EVENTS_FD:-}" == "3" ]] || return 0
  ( : >&3 ) 2>/dev/null || return 0

  _ILOOP_EVT_ACTIVE=1
  _ILOOP_EVT_ACTION="$(_iloop_evt_safe "${action}")"

  case "${issue}" in
    ''|*[!0-9]*|0) _ILOOP_EVT_ISSUE="unknown" ;;
    *)              _ILOOP_EVT_ISSUE="${issue}" ;;
  esac

  case "${ROLE:-}" in
    planner|developer|reviewer) _ILOOP_EVT_ROLE="${ROLE}" ;;
    *)                          _ILOOP_EVT_ROLE="unknown" ;;
  esac

  if [[ -n "${ILOOP_RUN_ID:-}" ]]; then
    # 用户显式传入：不合规即 unknown，绝不回显原值。
    if [[ "${ILOOP_RUN_ID}" =~ ^r-[0-9a-f]{32}$ ]]; then
      _ILOOP_EVT_RUN_ID="${ILOOP_RUN_ID}"
    else
      _ILOOP_EVT_RUN_ID="unknown"
    fi
  else
    rid="$(_iloop_evt_rand_hex)" || rid=""
    if [[ -n "${rid}" ]]; then
      _ILOOP_EVT_RUN_ID="r-${rid}"
    else
      _ILOOP_EVT_RUN_ID="unknown"
    fi
  fi

  _ILOOP_EVT_START="$(date -u +%s 2>/dev/null)" || _ILOOP_EVT_START=""
  trap '_iloop_evt_exit "$?"' EXIT
  return 0
}

# 在命令路径上标记已观察到的事实。空参数表示不改动该字段。
# 用法：_iloop_evt_mark <result> <rule> <checkpoint> <side_effects>
_iloop_evt_mark() {
  [[ "${_ILOOP_EVT_ACTIVE}" -eq 1 ]] || return 0

  case "${1:-}" in
    success|denied|failed|partial) _ILOOP_EVT_RESULT="$1" ;;
  esac
  [[ -n "${2:-}" ]] && _ILOOP_EVT_RULE="$(_iloop_evt_safe "$2")"
  [[ -n "${3:-}" ]] && _ILOOP_EVT_CHECKPOINT="$(_iloop_evt_safe "$3")"
  case "${4:-}" in
    none|unknown|label-cleanup-only|remote-write) _ILOOP_EVT_SIDE_EFFECTS="$4" ;;
  esac
  return 0
}

# EXIT trap：发出至多一条完成事件。任何失败都被吞掉，不影响原退出码。
_iloop_evt_exit() {
  local rc="${1:-}" now="" ts="unknown" duration="unknown" eid="" rid=""
  local exit_json duration_json

  [[ "${_ILOOP_EVT_ACTIVE}" -eq 1 ]] || return 0
  [[ "${_ILOOP_EVT_EMITTED}" -eq 0 ]] || return 0
  _ILOOP_EVT_EMITTED=1

  case "${rc}" in
    ''|*[!0-9]*) rc="unknown" ;;
  esac

  # 进程正常返回 0 且命令路径未显式标记时，按机械事实记为 success；
  # 这只表示本次受覆盖操作返回成功，不表示阶段完成或验收 PASS。
  if [[ "${_ILOOP_EVT_RESULT}" == "failed" && "${rc}" == "0" ]]; then
    _ILOOP_EVT_RESULT="success"
  fi

  now="$(date -u +%s 2>/dev/null)" || now=""
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || ts="unknown"
  [[ -n "${ts}" ]] || ts="unknown"
  if [[ -n "${_ILOOP_EVT_START}" && -n "${now}" ]]; then
    duration=$(( (now - _ILOOP_EVT_START) * 1000 ))
    [[ "${duration}" -ge 0 ]] || duration="unknown"
  fi

  _iloop_evt_skill_meta

  if [[ "${_ILOOP_EVT_RUN_ID}" == "unknown" ]]; then
    rid="$(_iloop_evt_rand_hex)" || rid=""
    # 用户显式传入的非法 run_id 保持 unknown，不因重试而替换成新 ID。
    [[ -z "${ILOOP_RUN_ID:-}" && -n "${rid}" ]] && _ILOOP_EVT_RUN_ID="r-${rid}"
  fi

  eid="$(_iloop_evt_rand_hex)" || eid=""
  [[ -n "${eid}" ]] && eid="e-${eid}" || eid="unknown"

  case "${rc}" in
    unknown) exit_json='"unknown"' ;;
    *)       exit_json="${rc}" ;;
  esac
  case "${duration}" in
    unknown) duration_json='"unknown"' ;;
    *)       duration_json="${duration}" ;;
  esac

  # 子 shell 隔离写入：fd3 关闭 / 只读 / 管道断开 / 写入失败都只影响该子 shell。
  # 外层 stdout 也指向 /dev/null：某些 shell 在 `>&3` 失败时会把缓冲内容落回原 stdout，
  # 这里确保观测失败绝不污染调用者的标准输出。
  (
    printf '{"schema":"iloop.runtime.v1","run_id":"%s","event_id":"%s","time":"%s","skill_tag":"%s","skill_sha":"%s","issue":"%s","role":"%s","action":"%s","result":"%s","rule":"%s","exit_code":%s,"duration_ms":%s,"checkpoint":"%s","side_effects":"%s"}\n' \
      "${_ILOOP_EVT_RUN_ID}" "${eid}" "${ts}" \
      "${_ILOOP_EVT_SKILL_TAG}" "${_ILOOP_EVT_SKILL_SHA}" \
      "${_ILOOP_EVT_ISSUE}" "${_ILOOP_EVT_ROLE}" "${_ILOOP_EVT_ACTION}" \
      "${_ILOOP_EVT_RESULT}" "${_ILOOP_EVT_RULE}" \
      "${exit_json}" "${duration_json}" \
      "${_ILOOP_EVT_CHECKPOINT}" "${_ILOOP_EVT_SIDE_EFFECTS}" >&3
  ) >/dev/null 2>/dev/null || true

  return 0
}