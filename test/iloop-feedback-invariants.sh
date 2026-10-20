#!/usr/bin/env bash
# Black-box safety and feedback contracts for #40. All mutations use fixtures.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/business" "$WORK/copy/scripts"
export FEEDBACK_CALL_LOG="$WORK/calls"
for tool in gh glab tea curl wget; do
  cat > "$WORK/bin/$tool" <<'STUB'
#!/usr/bin/env bash
printf 'called\n' >> "$FEEDBACK_CALL_LOG"
exit 0
STUB
  chmod +x "$WORK/bin/$tool"
done
export PATH="$WORK/bin:$PATH"
export PRIVATE_SECRET=PRIVATE_SECRET_MUST_NOT_APPEAR
cd "$WORK/business"
before="$(ls -a)"
count=0
for scenario in permission guard evidence; do
 for classification in suspected confirmed intercepted false-positive; do
  output="$(bash "$ROOT/scripts/feedback.sh" draft "$scenario" "$classification")"
  case "$scenario" in permission) rule=ROLE-001;; guard) rule=WORKSPACE-001;; evidence) rule=ISSUE-001;; esac
  for field in "rule: $rule" "fingerprint: $rule/" "classification: $classification" 'authorization: not-submitted' 'evidence: unknown' 'observation-result: 无法判断' 'related-event: unknown'; do
   [[ "$output" == *"$field"* ]] || { echo "FAIL missing $field"; exit 1; }
  done
  [[ "$output" != *PRIVATE_SECRET* && "$output" != *"$WORK"* ]]
  [[ "$output" == *"skill-sha: $(git -C "$ROOT" rev-parse HEAD)"* ]]
  count=$((count+1))
 done
done
[[ "$(ls -a)" == "$before" && ! -e "$WORK/calls" ]]
echo "PASS $count combinations: foreign cwd, safe fields, no writes or platform/network calls"
for args in 'draft PRIVATE_SECRET_MUST_NOT_APPEAR suspected' 'draft guard PRIVATE_SECRET_MUST_NOT_APPEAR' 'draft guard suspected PRIVATE_SECRET_MUST_NOT_APPEAR'; do
 if output="$(bash "$ROOT/scripts/feedback.sh" $args 2>&1)"; then echo 'FAIL accepted invalid arguments'; exit 1; fi
 [[ "$output" != *PRIVATE_SECRET* ]]
done
echo 'PASS invalid/extra inputs fail without echoing secrets'
cp "$ROOT/scripts/feedback.sh" "$WORK/copy/scripts/feedback.sh"
output="$(bash "$WORK/copy/scripts/feedback.sh" draft evidence suspected)"
[[ "$output" == *'skill-sha: unknown'* && "$output" == *'skill-tag: unknown'* ]]
echo 'PASS non-Git Skill copy remains usable with unknown version'
git init -q "$WORK/fixture"
cd "$WORK/fixture"
git config user.email fixture@example.invalid
git config user.name fixture
git remote add origin https://github.com/example/fixture.git
mkdir scripts
printf 'base\n' > scripts/base
git add .
git commit -qm base
git checkout -qb riper/40
if output="$(bash "$ROOT/scripts/git-ops.sh" --role developer issue close 40 2>&1)"; then exit 1; else [[ $? -eq 1 ]]; fi
[[ "$output" == *'rule=ROLE-001 outcome=intercepted'* && ! -e "$WORK/calls" ]]
if output="$(bash "$ROOT/scripts/git-ops.sh" --role planner guard planner 41 2>&1)"; then exit 1; else [[ $? -eq 1 ]]; fi
[[ "$output" == *'rule=WORKSPACE-001'* && ! -e "$WORK/calls" ]]
printf 'changed\n' >> scripts/base
if output="$(bash "$ROOT/scripts/git-ops.sh" --role planner guard planner 40 2>&1)"; then exit 1; else [[ $? -eq 1 ]]; fi
[[ "$output" == *'rule=WORKSPACE-001'* && "$output" == *'scripts/base'* && ! -e "$WORK/calls" ]]
# Intentional compatibility check with a stub: absence of role still allows close.
output="$(bash "$ROOT/scripts/git-ops.sh" issue close 40 2>&1)"
[[ "$output" == *'scope=unattributed'* && -f "$WORK/calls" ]]
echo 'PASS role/guard refusals retain exit 1, original diagnostic and zero CLI calls; no-role compatibility retained'
echo 'RESULT PASS'
