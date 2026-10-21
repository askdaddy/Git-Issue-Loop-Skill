#!/usr/bin/env bash
# Black-box strict-read contracts; no semantic Agent behavior is simulated here.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export INTAKE_CALLS="$W/calls"
mkdir "$W/bin"
cat > "$W/bin/reader" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "$INTAKE_CALLS"
case "$*" in
 'auth status'*) exit 0 ;;
 'login list'*) printf 'fixture https://codeberg.org\n'; exit 0 ;;
esac
case "$*" in
 *--comments*)
  [[ "${COMMENTS_FAIL:-0}" == 0 ]] || { echo 'fixture comments unavailable' >&2; exit 42; }
  [[ "${COMMENTS_EMPTY:-0}" == 0 ]] || exit 0
  echo 'comment: previous verified intake'; exit 0 ;;
 'issue view '*|'issues '*)
  [[ "${BODY_FAIL:-0}" == 0 ]] || { echo 'fixture body unavailable' >&2; exit 41; }
  printf 'number: 44\ntitle: external report\nlabels: bug\n'; exit 0 ;;
 *) echo 'UNEXPECTED WRITE OR COMMAND' >&2; exit 99 ;;
esac
STUB
chmod +x "$W/bin/reader"
for c in gh glab tea; do cp "$W/bin/reader" "$W/bin/$c"; done
export PATH="$W/bin:$PATH"
git init -q "$W/repo"; cd "$W/repo"
git remote add origin https://github.com/owner/repo.git
checks=0
for host in github.com gitlab.com codeberg.org; do
 git remote set-url origin "https://$host/owner/repo.git"
 : > "$INTAKE_CALLS"
 output="$(bash "$ROOT/scripts/git-ops.sh" issue get 44 --strict)"
 [[ "$output" == *'external report'* && "$output" == *'previous verified intake'* ]]
 checks=$((checks+1))
 : > "$INTAKE_CALLS"
 if output="$(BODY_FAIL=1 bash "$ROOT/scripts/git-ops.sh" issue get 44 --strict 2>&1)"; then echo 'FAIL body failure hidden'; exit 1; fi
 [[ "$output" == *'正文读取失败'* ]]
 [[ "$(cat "$INTAKE_CALLS")" != *--comments* ]]
 checks=$((checks+1))
 : > "$INTAKE_CALLS"
 if output="$(COMMENTS_FAIL=1 bash "$ROOT/scripts/git-ops.sh" issue get 44 --strict 2>&1)"; then echo 'FAIL comments failure hidden'; exit 1; fi
 [[ "$output" == *'严格模式停止'* && "$output" == *'fixture comments unavailable'* ]]
 checks=$((checks+1))
 output="$(COMMENTS_EMPTY=1 bash "$ROOT/scripts/git-ops.sh" issue get 44 --strict)"
 [[ "$output" == *'external report'* && "$output" != *'previous verified intake'* ]]
 checks=$((checks+1))
 output="$(COMMENTS_FAIL=1 bash "$ROOT/scripts/git-ops.sh" issue get 44)"
 [[ "$output" == *'external report'* ]]
 checks=$((checks+1))
 [[ "$(cat "$INTAKE_CALLS")" != *' edit '* && "$(cat "$INTAKE_CALLS")" != *' label '* && "$(cat "$INTAKE_CALLS")" != *' comment '* ]]
 echo "PASS $host: strict success/body failure/comment failure/empty comments/legacy compatibility; no writes"
done
: > "$INTAKE_CALLS"
for args in 'get 44 --unknown' 'get 44 --strict extra' 'get'; do
 if bash "$ROOT/scripts/git-ops.sh" issue $args > "$W/out" 2>&1; then echo 'FAIL bad parameters accepted'; exit 1; fi
done
[[ ! -s "$INTAKE_CALLS" ]]
echo "PASS $checks three-platform cases and invalid-argument zero-call checks"
echo 'RESULT PASS'
