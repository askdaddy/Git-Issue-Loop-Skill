#!/usr/bin/env bash
# Offline allowlist-only feedback tool. The local queue subcommands never
# ingest business logs, touch the network, or call platform CLIs; upstream
# submission stays agent+user driven per references/feedback-loop.md.
set -euo pipefail
usage() {
  printf '%s\n' 'Usage:' \
    '  feedback.sh draft <permission|guard|evidence> <suspected|confirmed|intercepted|false-positive>' \
    '  feedback.sh add <bug|protocol|doc|behavior> "<summary>" ["<detail>"]' \
    '  feedback.sh list [pending|all]' \
    '  feedback.sh show <id>' \
    '  feedback.sh dismiss <id>' \
    '  feedback.sh reported <id> <https-url>' >&2
  exit 1
}
fail() { printf 'feedback: %s\n' "$1" >&2; exit 1; }

queue_root() {
  local root="${ILOOP_FEEDBACK_DIR:-}"
  if [[ -z "$root" ]]; then
    [[ -n "${HOME:-}" ]] || fail 'HOME 未设置且未提供 ILOOP_FEEDBACK_DIR'
    root="$HOME/.agents/iloop-feedback"
  fi
  printf '%s' "$root"
}

# Skill tag/sha of this installation; unknown outside a Git checkout.
skill_meta() {
  local root sha ref
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  sha="$(git -C "$root" rev-parse HEAD 2>/dev/null)" || sha=unknown
  [[ "$sha" =~ ^[0-9a-f]{40,64}$ ]] || sha=unknown
  ref="$(git -C "$root" describe --tags --exact-match HEAD 2>/dev/null)" || ref=unknown
  [[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || ref=unknown
  # An ancestor repository is not this Skill's metadata (e.g. copied non-Git tree).
  if [[ ! -e "$root/.git" ]]; then sha=unknown; ref=unknown; fi
  printf '%s\n%s\n' "$ref" "$sha"
}

entry_file() { printf '%s/entries/%s.md' "$(queue_root)" "$1"; }
entry_field() { sed -n "s/^- $2: //p" "$1" | head -n 1; }
require_id() { [[ "$1" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}$ ]] || usage; }

require_pending() {
  local status
  status="$(entry_field "$1" status)"
  [[ "$status" == pending ]] || fail "条目 $2 已是终态（${status}），不允许再变更；复活请手工编辑条目文件"
}

# Rewrite one entry in place via temp+mv (portable awk; BSD/GNU sed differ).
rewrite_entry() {
  local file="$1" status="$2" url="$3" at="$4" tmp
  tmp="$(dirname "$file")/.tmp-rewrite-$5"
  awk -v s="$status" -v u="$url" -v a="$at" '
    /^- status: / { print "- status: " s; next }
    /^- reported-url: / { print "- reported-url: " u; next }
    /^- reported-at: / { print "- reported-at: " a; next }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

cmd_add() {
  local category="$1" summary="$2" detail="${3:-none}" meta ref sha
  case "$category" in bug|protocol|doc|behavior) ;; *) usage ;; esac
  [[ -n "$summary" ]] || usage
  [[ -z "$detail" ]] && detail=none
  [[ "$summary" != *$'\n'* && "$detail" != *$'\n'* ]] || fail 'summary/detail 必须单行输入；多行细节请事后手工编辑条目文件'
  local root entries id file tmp attempts=0
  root="$(queue_root)"
  entries="$root/entries"
  if ! mkdir -p "$entries" 2>/dev/null; then
    fail "无法创建队列目录 ${entries}；请检查父目录权限，或设置 ILOOP_FEEDBACK_DIR 指向可写目录"
  fi
  while :; do
    id="$(date -u +%Y%m%dT%H%M%SZ)-$(printf '%04x' $((RANDOM & 0xffff)))"
    file="$entries/$id.md"
    [[ -e "$file" ]] || break
    attempts=$((attempts + 1))
    [[ "$attempts" -lt 5 ]] || fail '无法生成唯一 ID，请重试'
  done
  meta="$(skill_meta)"
  ref="${meta%%$'\n'*}"
  sha="${meta#*$'\n'}"
  tmp="$entries/.tmp-$id"
  {
    printf '%s\n\n' '# iloop Feedback Entry'
    printf '%s\n' \
      "- schema: 2" \
      "- id: $id" \
      "- created: $(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "- skill-tag: $ref" \
      "- skill-sha: $sha" \
      "- category: $category" \
      "- rule: none" \
      "- summary: $summary" \
      "- detail: $detail" \
      "- status: pending" \
      "- reported-url: none" \
      "- reported-at: none" \
      "- attribution: unknown" \
      "- feedback-state: 待归因" \
      "- regression: unknown" \
      "- fix-commit: unknown" \
      "- release: unknown"
    printf '\nThis entry is local user data pending user-authorized reporting;\nit is not a submitted report. Review references/feedback-loop.md first.\n'
  } > "$tmp"
  mv "$tmp" "$file"
  printf '%s\n' "$id"
}

# lazy-ladder: plain directory scan, fine up to hundreds of entries; add an index if this ever matters.
cmd_list() {
  local scope="${1:-pending}" f count=0
  case "$scope" in pending|all) ;; *) usage ;; esac
  local entries
  entries="$(queue_root)/entries"
  [[ -d "$entries" ]] || { printf '0\n'; return 0; }
  for f in "$entries"/*.md; do
    [[ -e "$f" ]] || break
    [[ "$scope" == pending && "$(entry_field "$f" status)" != pending ]] && continue
    printf '%s %s %s %s %s\n' \
      "$(entry_field "$f" id)" "$(entry_field "$f" created)" \
      "$(entry_field "$f" category)" "$(entry_field "$f" status)" "$(entry_field "$f" summary)"
    count=$((count + 1))
  done
  [[ "$count" -eq 0 ]] && printf '0\n'
  return 0
}

cmd_show() {
  local id="$1" file
  require_id "$id"
  file="$(entry_file "$id")"
  [[ -f "$file" ]] || fail "条目不存在: $id"
  cat "$file"
}

cmd_dismiss() {
  local id="$1" file
  require_id "$id"
  file="$(entry_file "$id")"
  [[ -f "$file" ]] || fail "条目不存在: $id"
  require_pending "$file" "$id"
  rewrite_entry "$file" dismissed "$(entry_field "$file" reported-url)" "$(entry_field "$file" reported-at)" "$id"
  printf '%s\n' "$id dismissed"
}

cmd_reported() {
  local id="$1" url="$2" file
  require_id "$id"
  [[ "$url" =~ ^https:// ]] || usage
  file="$(entry_file "$id")"
  [[ -f "$file" ]] || fail "条目不存在: $id"
  require_pending "$file" "$id"
  rewrite_entry "$file" reported "$url" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$id"
  printf '%s\n' "$id reported"
}

cmd_draft() {
  local rule symptom source expected actual classification meta ref sha
  case "$1" in
    permission) rule=ROLE-001; symptom=operation-denied; source=check_permission; expected='Role-authorized operation'; actual='Operation denied' ;;
    guard) rule=WORKSPACE-001; symptom=workspace-mismatch; source=guard; expected='Changes and branch within role/Issue scope'; actual='Workspace check failed; attribution requires review' ;;
    evidence) rule=ISSUE-001; symptom=stage-evidence-gap; source=agent-review; expected='Priority, state and stage evidence consistent'; actual='Reported evidence gap; requires review' ;;
    *) usage ;;
  esac
  case "$2" in suspected|confirmed|intercepted|false-positive) classification="$2" ;; *) usage ;; esac
  meta="$(skill_meta)"
  ref="${meta%%$'\n'*}"
  sha="${meta#*$'\n'}"
  cat <<DRAFT
# iloop Feedback Draft

- schema: 1
- target: https://github.com/askdaddy/Git-Issue-Loop-Skill.git
- authorization: not-submitted; requires user review
- rule: $rule
- fingerprint: $rule/$symptom
- event: $(date -u +%Y%m%dT%H%M%SZ)-$$
- skill-tag: $ref
- skill-sha: $sha
- classification: $classification
- role: unknown
- stage: unknown
- expected: $expected
- actual: $actual
- detection-source: $source
- evidence: unknown
- impact: unknown
- action: unknown
- attribution: unknown
- related-task: unknown
- related-event: unknown
- duplicate-feedback: unknown
- feedback-state: 待归因
- regression: unknown
- fix-commit: unknown
- release: unknown
- environment: unknown
- observation-window: unknown
- observation-denominator: unknown
- observation-result: 无法判断

This is a draft, not evidence of a confirmed violation or a submitted report.
Review minimal redacted evidence and classification before any submission.
DRAFT
}

case "${1:-}" in
  draft) shift; [[ $# -eq 2 ]] || usage; cmd_draft "$@" ;;
  add) shift; [[ $# -ge 2 && $# -le 3 ]] || usage; cmd_add "$@" ;;
  list) shift; [[ $# -le 1 ]] || usage; cmd_list "${1:-pending}" ;;
  show) shift; [[ $# -eq 1 ]] || usage; cmd_show "$1" ;;
  dismiss) shift; [[ $# -eq 1 ]] || usage; cmd_dismiss "$1" ;;
  reported) shift; [[ $# -eq 2 ]] || usage; cmd_reported "$1" "$2" ;;
  *) usage ;;
esac
