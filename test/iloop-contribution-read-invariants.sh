#!/usr/bin/env bash
# Black-box PR read permissions/routing, not an Agent E2E simulation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export CALLS="$W/calls"
mkdir "$W/bin"
cat > "$W/bin/reader" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "$CALLS"
case "$*" in
 'auth status'*) exit 0 ;;
 'login list'*) printf 'fixture https://codeberg.org\n'; exit 0 ;;
 'pr view '*|'mr view '*|'pulls '*)
   [[ "${READ_FAIL:-0}" == 0 ]] || { echo 'fixture read failed' >&2; exit 42; }
   echo 'fixture external PR: author contributor, head abc'; exit 0 ;;
 *) echo 'unexpected command' >&2; exit 99 ;;
esac
STUB
for c in gh glab tea; do cp "$W/bin/reader" "$W/bin/$c"; chmod +x "$W/bin/$c"; done
export PATH="$W/bin:$PATH"
unset GIT_OPS_ROLE || true
git init -q "$W/repo"; cd "$W/repo"
git remote add origin https://github.com/owner/repo.git
G="$ROOT/scripts/git-ops.sh"
for host in github.com gitlab.com codeberg.org; do
 git remote set-url origin "https://$host/owner/repo.git"
 for role in planner developer reviewer; do
  : > "$CALLS"
  result="$(bash "$G" --role "$role" integration pr-view 73)"
  [[ "$result" == *'fixture external PR'* ]]
  calls="$(cat "$CALLS")"
  case "$host" in
   github.com)
    [[ "$calls" == *'gh pr view 73 --json url,state,baseRefName,headRefName,headRefOid,'* ]]
    for field in body comments reviews author baseRefOid headRepository headRepositoryOwner closingIssuesReferences updatedAt; do
     [[ "$calls" == *"$field"* ]]
    done ;;
   gitlab.com) [[ "$calls" == *'glab mr view 73'* ]] ;;
   codeberg.org) [[ "$calls" == *'tea pulls 73'* ]] ;;
  esac
  if result="$(READ_FAIL=1 bash "$G" --role "$role" integration pr-view 73 2>&1)"; then echo 'FAIL hidden read error'; exit 1; fi
  [[ "$result" == *'fixture read failed'* ]]
 done
 echo "PASS $host: all roles read outside riper workspace; read failures propagate"
done
for role in planner developer reviewer; do
 for bad in 0 00 01 -1 1.5 x --web; do
  : > "$CALLS"
  if bash "$G" --role "$role" integration pr-view "$bad" >/dev/null 2>&1; then echo "FAIL invalid $bad"; exit 1; fi
  [[ ! -s "$CALLS" ]]
 done
 : > "$CALLS"
 if bash "$G" --role "$role" integration pr-view 73 extra >/dev/null 2>&1; then exit 1; fi
 [[ ! -s "$CALLS" ]]
done
for role in '' unknown; do
 : > "$CALLS"
 if bash "$G" --role "$role" integration pr-view 73 >/dev/null 2>&1; then exit 1; fi
 [[ ! -s "$CALLS" ]]
done
: > "$CALLS"
if bash "$G" integration pr-view 73 >/dev/null 2>&1; then exit 1; fi
[[ ! -s "$CALLS" ]]
for role in planner developer; do
 for action in push pr-list pr-create release-view release-create; do
  : > "$CALLS"
  if bash "$G" --role "$role" integration "$action" 73 >/dev/null 2>&1; then exit 1; fi
  [[ ! -s "$CALLS" ]]
 done
done
echo 'PASS invalid arguments/roles zero platform calls; write permissions unchanged'
echo 'RESULT PASS'
