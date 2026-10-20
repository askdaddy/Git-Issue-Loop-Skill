#!/usr/bin/env bash
# Sourced by git-ops.sh. Explicit-role primitives; orchestration stays in protocol.
integration_fail() { log_error "$*"; return 1; }
integration_verified() {
  local labels
  labels="$(raw_issue_labels "$1")" || return 1
  printf '%s\n' "$labels" | grep -Fx 'riper-verified' >/dev/null || integration_fail '集成前必须有 riper-verified。'
}
integration_clean() {
  [[ -z "$(git status --porcelain)" ]] || { integration_fail '工作区不干净，停止集成。'; return 1; }
  [[ ! -f "$(git rev-parse --git-path MERGE_HEAD)" ]] || { integration_fail '合并尚未结束。'; return 1; }
}
integration_head() {
  local branch="riper/$1" remote_sha
  [[ "$(current_branch)" == "$branch" ]] || { integration_fail '必须位于本 Issue 的 riper 分支。'; return 1; }
  integration_clean || return 1
  integration_verified "$1" || return 1
  if [[ "$2" == remote ]]; then
    remote_sha="$(git ls-remote --exit-code origin "refs/heads/$branch")" || return 1
    [[ "${remote_sha%%[[:space:]]*}" == "$(git rev-parse HEAD)" ]] || { integration_fail '远端分支不等于本地已验收 HEAD，先推送或重新验收。'; return 1; }
  fi
}
cmd_integration() {
  local action="${1:-}"; [[ $# -gt 0 ]] || usage; shift
  # New write-capable commands never inherit the legacy missing-role bypass.
  case "$action:${ROLE}" in
    local:developer|push:reviewer|pr-list:reviewer|pr-view:reviewer|pr-create:reviewer|release-view:reviewer|release-create:reviewer) ;;
    *) integration_fail '集成动作需要显式角色：local=developer，其余=reviewer。'; return 1 ;;
  esac
  local num branch db plat sha remote_sha tag notes
  case "$action" in
    push)
      [[ $# -eq 1 ]] && valid_issue_num "$1" || usage
      num="$1"; integration_head "$num" local || return 1
      git push origin "refs/heads/riper/$num:refs/heads/riper/$num"
      ;;
    local)
      [[ $# -eq 2 ]] && valid_issue_num "$1" || usage
      num="$1"; branch="$2"; db="$(default_branch)" || return 1
      [[ "$branch" != "$db" && "$branch" != "riper/$num" && "$(current_branch)" == "$branch" ]] || { integration_fail '降级要求显式非默认目标分支，且 cwd 已在该分支。'; return 1; }
      is_linked_worktree || { integration_fail '本地降级只允许独立 linked worktree。'; return 1; }
      integration_clean || return 1
      integration_verified "$num" || return 1
      git show-ref --verify --quiet "refs/heads/riper/$num" || return 1
      if ! git merge --no-ff --no-edit "refs/heads/riper/$num"; then
        log_error '本地合并失败；保留现场，不自动解冲。冲突路径（为空则可能不是冲突）：'
        git diff --name-only --diff-filter=U >&2
        return 1
      fi
      log_info '仅本地合并；Issue 保持 open，不满足上游交付或清理条件。'
      ;;
    pr-list|pr-view|pr-create)
      case "$action" in
        pr-list) [[ $# -eq 1 ]] && valid_issue_num "$1" || usage ;;
        pr-view) [[ $# -eq 1 ]] && valid_issue_num "$1" || usage ;;
        pr-create) [[ $# -eq 3 ]] && valid_issue_num "$1" && [[ -n "$2" && -f "$3" ]] || usage ;;
      esac
      plat="$(detect_platform)" || return 1; require_cli "$plat"
      if [[ "$action" == pr-view ]]; then
        case "$plat" in gh) gh pr view "$1" ;; glab) glab mr view "$1" ;; tea) tea_cmd pulls "$1" ;; esac
        return
      fi
      num="$1"; branch="riper/$num"; db="$(default_branch)" || return 1
      if [[ "$action" == pr-list ]]; then
        # Human checks all pages and matches base/head; no JSON-parser dependency.
        case "$plat" in
          gh) gh pr list --state all --head "$branch" --base "$db" --limit 100 ;;
          glab) glab mr list --all --source-branch "$branch" --target-branch "$db" --per-page 100 ;;
          tea) tea_cmd pulls list --state all --fields index,state,url,head,base --limit 100 ;;
        esac
      else
        integration_head "$num" remote || return 1
        case "$plat" in
          gh) gh pr create --head "$branch" --base "$db" --title "$2" --body-file "$3" ;;
          glab) glab mr create --source-branch "$branch" --target-branch "$db" --title "$2" --description-file "$3" --yes ;;
          tea) tea_cmd pulls create --head "$branch" --base "$db" --title "$2" --description-file "$3" ;;
        esac
      fi
      ;;
    release-view|release-create)
      [[ $# -ge 1 && "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage
      tag="$1"; plat="$(detect_platform)" || return 1
      [[ "$plat" == gh ]] || { integration_fail 'GitHub Release 仅支持 gh，其他平台停止。'; return 1; }
      require_cli gh
      if [[ "$action" == release-view ]]; then
        [[ $# -eq 1 ]] || usage
        gh release view "$tag"; return
      fi
      [[ $# -eq 2 && "$2" =~ ^[0-9a-f]{40}$ ]] || usage
      sha="$2"; integration_clean || return 1
      [[ "$(git rev-parse HEAD)" == "$sha" ]] || { integration_fail 'HEAD 与发布 SHA 不一致。'; return 1; }
      db="$(default_branch)" || return 1
      remote_sha="$(git ls-remote --exit-code origin "refs/heads/$db")" || return 1
      [[ "${remote_sha%%[[:space:]]*}" == "$sha" ]] || { integration_fail '默认上游不等于发布 SHA。'; return 1; }
      # Both exact tag and peeled tag are queried: annotated tags are rejected.
      remote_sha="$(git ls-remote --exit-code origin "refs/tags/$tag" "refs/tags/$tag^{}")" || return 1
      [[ "$remote_sha" == "$sha"$'\t'"refs/tags/$tag" ]] || { integration_fail '远端需存在匹配 SHA 的 lightweight tag。'; return 1; }
      [[ -f CHANGELOG.md ]] || { integration_fail '缺 CHANGELOG.md。'; return 1; }
      notes="$(awk -v heading="## [${tag#v}]" 'index($0,heading)==1 {found=1; next} found && /^## / {exit} found {print}' CHANGELOG.md)"
      [[ -n "${notes//[[:space:]]/}" ]] || { integration_fail 'CHANGELOG 无对应非空版本段。'; return 1; }
      # gh create is a single attempt: an existing Release is not edited/replaced.
      local notes_file rc=0
      notes_file="$(mktemp)" || return 1
      printf '%s\n' "$notes" > "$notes_file"
      gh release create "$tag" --verify-tag --target "$db" --title "$tag" --notes-file "$notes_file" || rc=$?
      rm -f "$notes_file"
      [[ "$rc" -eq 0 ]] || { log_error 'Release 未确认创建，保留 tag；先 release-view 回读再决定恢复。'; return "$rc"; }
      gh release view "$tag"
      ;;
    *) usage ;;
  esac
}
