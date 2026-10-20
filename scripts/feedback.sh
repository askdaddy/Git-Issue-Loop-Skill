#!/usr/bin/env bash
# Offline allowlist-only draft. Never ingest business logs or submit feedback.
set -euo pipefail
usage() {
  printf '%s\n' 'Usage: feedback.sh draft <permission|guard|evidence> <suspected|confirmed|intercepted|false-positive>' >&2
  exit 1
}
[[ $# -eq 3 && "$1" == draft ]] || usage
case "$2" in
  permission) rule=ROLE-001; symptom=operation-denied; source=check_permission; expected='Role-authorized operation'; actual='Operation denied' ;;
  guard) rule=WORKSPACE-001; symptom=workspace-mismatch; source=guard; expected='Changes and branch within role/Issue scope'; actual='Workspace check failed; attribution requires review' ;;
  evidence) rule=ISSUE-001; symptom=stage-evidence-gap; source=agent-review; expected='Priority, state and stage evidence consistent'; actual='Reported evidence gap; requires review' ;;
  *) usage ;;
esac
case "$3" in suspected|confirmed|intercepted|false-positive) classification="$3" ;; *) usage ;; esac
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sha="$(git -C "$root" rev-parse HEAD 2>/dev/null)" || sha=unknown
[[ "$sha" =~ ^[0-9a-f]{40,64}$ ]] || sha=unknown
ref="$(git -C "$root" describe --tags --exact-match HEAD 2>/dev/null)" || ref=unknown
[[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || ref=unknown
# An ancestor repository is not this Skill's metadata (e.g. copied non-Git tree).
if [[ ! -e "$root/.git" ]]; then sha=unknown; ref=unknown; fi
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
