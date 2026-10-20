#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="$ROOT/scripts/git-ops.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export REAL_GIT="$(command -v git)" CALLS="$W/calls" NOTES="$W/notes"
mkdir "$W/bin"
cat > "$W/bin/git" <<'STUB'
#!/usr/bin/env bash
case "$1" in
 ls-remote)
  [[ "${REMOTE_FAIL:-0}" == 0 ]] || exit 1
  case "$*" in
   *refs/tags*) [[ "${MISSING_TAG:-0}" == 0 ]] || exit 2; printf '%s\trefs/tags/v9.9.9\n' "${TAG_SHA:-$SHA}"; [[ "${ANNOTATED:-0}" == 0 ]] || printf '%s\trefs/tags/v9.9.9^{}\n' "$SHA" ;;
   *refs/heads*) printf '%s\trefs/heads/main\n' "${REMOTE_SHA:-$SHA}" ;;
  esac; exit 0 ;;
 push) printf 'git %s\n' "$*" >> "$CALLS"; exit 0 ;;
 fetch) [[ "${FETCH_FAIL:-0}" == 0 ]] || exit 1; exit 0 ;;
esac
exec "$REAL_GIT" "$@"
STUB
cat > "$W/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$CALLS"
if [[ "$1 $2" == 'issue view' ]]; then printf '%s\n' riper-verified; fi
if [[ "$1 $2" == 'release create' ]]; then
 while [[ $# -gt 0 ]]; do if [[ "$1" == --notes-file ]]; then cp "$2" "$NOTES"; break; fi; shift; done
 [[ "${CREATE_FAIL:-0}" == 0 ]] || exit 1
fi
STUB
for c in glab tea; do
 cat > "$W/bin/$c" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "$CALLS"
if [[ "$*" == 'login list' ]]; then printf 'fixture https://codeberg.org\n'; fi
if [[ "$*" == *'issue view'* ]]; then printf '__ILOOP_LABELS_OK__\nriper-verified\n'; fi
if [[ "$*" == *'issues '* ]]; then printf '{"labels":[{"name":"riper-verified"}]}\n'; fi
STUB
 chmod +x "$W/bin/$c"
done
chmod +x "$W/bin/git" "$W/bin/gh"
export PATH="$W/bin:$PATH"
git init -q "$W/repo"; cd "$W/repo"
git config user.name fixture; git config user.email fixture@example.invalid
git checkout -qb main
printf 'base\n' > file
printf '# Changelog\n\n## [9.9.9] - date\n\nExact release notes\n\n## [9.9.8]\nOld notes\n' > CHANGELOG.md
git add .; git commit -qm base
git remote add origin https://github.com/owner/repo.git
git update-ref refs/remotes/origin/main HEAD
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git checkout -qb riper/25
export SHA="$(git rev-parse HEAD)"
: > "$CALLS"
for role in planner developer; do
 if bash "$G" --role "$role" integration push 25 > /dev/null 2>&1; then exit 1; fi
done
if env -u GIT_OPS_ROLE bash "$G" integration push 25 > /dev/null 2>&1; then exit 1; fi
[[ ! -s "$CALLS" ]]
echo 'PASS role refusal before writes'
bash "$G" --role reviewer integration push 25 > /dev/null
[[ "$(cat "$CALLS")" == *'git push origin refs/heads/riper/25:refs/heads/riper/25'* ]]
printf body > "$W/body"
for host in github.com gitlab.com codeberg.org; do
 git remote set-url origin "https://$host/owner/repo.git"
 bash "$G" --role reviewer integration pr-list 25 > /dev/null
 bash "$G" --role reviewer integration pr-view 7 > /dev/null
 bash "$G" --role reviewer integration pr-create 25 'Title' "$W/body" > /dev/null
done
for expected in 'gh pr create --head riper/25 --base main' 'glab mr create --source-branch riper/25 --target-branch main' 'tea pulls create --head riper/25 --base main'; do [[ "$(cat "$CALLS")" == *"$expected"* ]]; done
[[ "$(cat "$CALLS")" == *'gh pr view 7 --json url,state,baseRefName,headRefName,headRefOid'* ]]
echo 'PASS explicit branch push and three-platform PR routing; GitHub delivery metadata requested'
git remote set-url origin https://github.com/owner/repo.git
before="$(wc -l < "$CALLS")"
if REMOTE_SHA=bad bash "$G" --role reviewer integration pr-create 25 Title "$W/body" > /dev/null 2>&1; then exit 1; fi
[[ "$(tail -1 "$CALLS")" != *'pr create'* ]]
printf dirty >> file
if bash "$G" --role reviewer integration push 25 > /dev/null 2>&1; then exit 1; fi
git restore file
if bash "$G" --role reviewer integration release-create invalid "$SHA" > /dev/null 2>&1; then exit 1; fi
if MISSING_TAG=1 bash "$G" --role reviewer integration release-create v9.9.9 "$SHA" > /dev/null 2>&1; then exit 1; fi
if TAG_SHA=bad bash "$G" --role reviewer integration release-create v9.9.9 "$SHA" > /dev/null 2>&1; then exit 1; fi
if REMOTE_SHA=bad bash "$G" --role reviewer integration release-create v9.9.9 "$SHA" > /dev/null 2>&1; then exit 1; fi
if ANNOTATED=1 bash "$G" --role reviewer integration release-create v9.9.9 "$SHA" > /dev/null 2>&1; then exit 1; fi
if bash "$G" --role reviewer integration release-create v9.9.8 "$SHA" > /dev/null 2>&1; then exit 1; fi
bash "$G" --role reviewer integration release-create v9.9.9 "$SHA" > /dev/null
[[ "$(cat "$NOTES")" == *'Exact release notes'* && "$(cat "$NOTES")" != *'Old notes'* ]]
[[ "$(cat "$CALLS")" == *'--verify-tag --target main --title v9.9.9 --notes-file'* ]]
if CREATE_FAIL=1 bash "$G" --role reviewer integration release-create v9.9.9 "$SHA" > /dev/null 2>&1; then exit 1; fi
[[ ! -e .git/refs/tags/v9.9.9 ]]
echo 'PASS PR SHA/dirty rejection; release tag/SHA/version checks, exact notes and failure preservation'
# Real local Git: independent target succeeds, conflict remains unresolved.
printf 'source\n' > file; git add file; git commit -qm source
git worktree add -q -b local-delivery "$W/local" main
cd "$W/local"
bash "$G" --role developer integration local 25 local-delivery > "$W/local-result"
[[ "$(git rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" == 3 ]]
[[ "$(cat "$W/local-result")" == *'保持 open'* ]]
if bash "$G" --role reviewer integration local 25 local-delivery >/dev/null 2>&1; then exit 1; fi
cd "$W/repo"
git worktree add -q -b conflict-target "$W/conflict" main
cd "$W/conflict"
printf 'other\n' > file; git add file; git commit -qm other
if bash "$G" --role developer integration local 25 conflict-target > "$W/conflict-result" 2>&1; then exit 1; fi
[[ -f "$(git rev-parse --git-path MERGE_HEAD)" && "$(git diff --name-only --diff-filter=U)" == file ]]
cd "$W/repo"; git checkout -q main
if bash "$G" --role developer integration local 25 main >/dev/null 2>&1; then exit 1; fi
# Cleanup must not delete worktrees when fetch fails or branch is unmerged.
if FETCH_FAIL=1 bash "$G" --role reviewer workspace finish 25 > /dev/null 2>&1; then exit 1; fi
[[ -d "$W/repo" ]] && git show-ref --verify --quiet refs/heads/riper/25
if bash "$G" --role reviewer workspace finish 25 > /dev/null 2>&1; then exit 1; fi
git show-ref --verify --quiet refs/heads/riper/25
echo 'PASS real local no-ff merge, conflict preservation, default-target refusal and cleanup fail-closed'
echo 'RESULT PASS'
