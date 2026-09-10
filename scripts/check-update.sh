#!/usr/bin/env bash
# ============================================================================
# check-update.sh —— 比较本 Skill 安装与官方仓库最高稳定 tag
#
# 在 Skill 根（本脚本的上级目录）运行，不读取目标项目的 git remote。
# 本地版本：git describe --tags --exact-match，失败则为 none + HEAD SHA。
# 远端 latest：git ls-remote 后筛选 ^v[0-9]+.[0-9]+.[0-9]+$ （无预发布后缀）。
# 禁止把 skill-manifest.json 的 skill.version 当作 local_ref。
#
# 退出码：
#   0  status=current
#   2  status=update-available | untagged（须提示人类）
#   1  检查失败（网络 / 非 git / 无稳定 tag）；调用方不阻塞闭环
#
# 无网络单测：
#   check-update.sh --compare <localTag> <latestTag>
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

emit() {
  printf '%s=%s\n' "$1" "$2"
}

is_stable_tag() {
  # 精确 vX.Y.Z，拒绝 v1.0.0-beta.1
  case "$1" in
    v[0-9]*.[0-9]*.[0-9]*)
      local rest="${1#v}"
      case "${rest}" in
        *[!0-9.]*|*.*.*.*) return 1 ;;
      esac
      local IFS=.
      # shellcheck disable=SC2086
      set -- ${rest}
      [[ $# -eq 3 && -n "$1" && -n "$2" && -n "$3" ]] || return 1
      return 0
      ;;
    *) return 1 ;;
  esac
}

# $1 < $2  → 0；否则 1
semver_lt() {
  local a="${1#v}" b="${2#v}"
  local IFS=.
  set -- ${a}
  local a1="${1:-0}" a2="${2:-0}" a3="${3:-0}"
  set -- ${b}
  local b1="${1:-0}" b2="${2:-0}" b3="${3:-0}"
  if [ "${a1}" -lt "${b1}" ]; then return 0; fi
  if [ "${a1}" -gt "${b1}" ]; then return 1; fi
  if [ "${a2}" -lt "${b2}" ]; then return 0; fi
  if [ "${a2}" -gt "${b2}" ]; then return 1; fi
  if [ "${a3}" -lt "${b3}" ]; then return 0; fi
  return 1
}

emit_result() {
  local status="$1" local_ref="$2" local_sha="$3" latest_tag="$4" latest_sha="$5" repository="$6"
  emit status "${status}"
  emit local_ref "${local_ref}"
  emit local_sha "${local_sha}"
  emit latest_tag "${latest_tag}"
  emit latest_sha "${latest_sha}"
  emit repository "${repository}"
}

decide_and_exit() {
  local local_ref="$1" local_sha="$2" latest_tag="$3" latest_sha="$4" repository="$5"
  if [[ -z "${latest_tag}" ]]; then
    emit_result error "${local_ref}" "${local_sha}" "" "${latest_sha}" "${repository}"
    exit 1
  fi
  if [[ "${local_ref}" == "${latest_tag}" ]]; then
    emit_result current "${local_ref}" "${local_sha}" "${latest_tag}" "${latest_sha}" "${repository}"
    exit 0
  fi
  if [[ -n "${local_sha}" && -n "${latest_sha}" && "${local_sha}" == "${latest_sha}" ]]; then
    emit_result current "${local_ref}" "${local_sha}" "${latest_tag}" "${latest_sha}" "${repository}"
    exit 0
  fi
  if [[ "${local_ref}" != "none" ]] && is_stable_tag "${local_ref}"; then
    if semver_lt "${local_ref}" "${latest_tag}"; then
      emit_result update-available "${local_ref}" "${local_sha}" "${latest_tag}" "${latest_sha}" "${repository}"
      exit 2
    fi
    emit_result current "${local_ref}" "${local_sha}" "${latest_tag}" "${latest_sha}" "${repository}"
    exit 0
  fi
  emit_result untagged "${local_ref}" "${local_sha}" "${latest_tag}" "${latest_sha}" "${repository}"
  exit 2
}

read_repository() {
  local f="${ROOT}/skill-manifest.json"
  if [[ ! -f "${f}" ]]; then
    echo "check-update: missing ${f}" >&2
    exit 1
  fi
  # 不用 jq；禁止用 skill.version 作为 local_ref
  sed -n 's/.*"repository": *"\([^"]*\)".*/\1/p' "${f}" | head -n 1
}

compare_mode() {
  local local_tag="$1" latest_tag="$2"
  if ! is_stable_tag "${latest_tag}"; then
    emit_result error "${local_tag}" "" "${latest_tag}" "" "compare"
    exit 1
  fi
  if ! is_stable_tag "${local_tag}"; then
    decide_and_exit none "" "${latest_tag}" "" "compare"
  fi
  decide_and_exit "${local_tag}" "" "${latest_tag}" "" "compare"
}

pick_highest_stable() {
  # stdin: git ls-remote --tags --refs 行：sha TAB refs/tags/name
  local best="" best_sha="" sha ref tag
  while IFS="$(printf '\t')" read -r sha ref; do
    tag="${ref#refs/tags/}"
    is_stable_tag "${tag}" || continue
    if [[ -z "${best}" ]] || semver_lt "${best}" "${tag}"; then
      best="${tag}"
      best_sha="${sha}"
    fi
  done
  if [[ -z "${best}" ]]; then
    return 1
  fi
  printf '%s %s\n' "${best}" "${best_sha}"
}

if [[ "${1:-}" == "--compare" ]]; then
  [[ $# -eq 3 ]] || { echo "usage: check-update.sh --compare <localTag> <latestTag>" >&2; exit 1; }
  compare_mode "$2" "$3"
fi

REPO="$(read_repository)"
if [[ -z "${REPO}" ]]; then
  echo "check-update: repository URL not found in skill-manifest.json" >&2
  exit 1
fi

if ! git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "check-update: ${ROOT} is not a git work tree" >&2
  exit 1
fi

LOCAL_SHA="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || true)"
LOCAL_REF="none"
if DESC="$(git -C "${ROOT}" describe --tags --exact-match HEAD 2>/dev/null)"; then
  LOCAL_REF="${DESC}"
fi

REMOTE_OUT=""
if ! REMOTE_OUT="$(GIT_TERMINAL_PROMPT=0 git ls-remote --tags --refs "${REPO}" 2>/dev/null)"; then
  echo "check-update: git ls-remote failed for ${REPO}" >&2
  exit 1
fi

PICK="$(printf '%s\n' "${REMOTE_OUT}" | pick_highest_stable)" || {
  echo "check-update: no stable vX.Y.Z tags at ${REPO}" >&2
  exit 1
}
LATEST_TAG="${PICK%% *}"
LATEST_SHA="${PICK#* }"

decide_and_exit "${LOCAL_REF}" "${LOCAL_SHA}" "${LATEST_TAG}" "${LATEST_SHA}" "${REPO}"
