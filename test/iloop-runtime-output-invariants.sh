#!/usr/bin/env bash
# Black-box contract checks for Issue #49 (opt-in runtime output + stage summary).
#
# Every probe runs git-ops.sh through macOS /bin/bash (Bash 3.2) against throwaway
# repositories and stub gh / glab / tea CLIs. The event channel is exercised through
# a caller-opened fd 3; no network or real Issue write is performed.
#
# Run from repository root: bash test/iloop-runtime-output-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
RUNTIME_EVENTS="${ROOT}/scripts/runtime-events.sh"
DOC="${ROOT}/references/runtime-output.md"
TEMPLATE="${ROOT}/templates/run-summary.md"
SCENARIOS="${ROOT}/test/iloop-runtime-output-scenarios.md"
FAILS=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" == "$want" ]]; then pass "$msg"; else fail "$msg (got='$got' want='$want')"; fi
}

assert_grep() {
  local file="$1" pat="$2" msg="$3"
  if grep -Eq -- "$pat" "$file"; then pass "$msg"; else fail "$msg (file=$file pat=$pat)"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Stubs. Each records its invocations to STUB_LOG so tests can prove that the
# event channel never replays a remote write.
# ---------------------------------------------------------------------------
mkdir -p "$WORK/ghbin" "$WORK/glabbin" "$WORK/teabin"

cat > "$WORK/ghbin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "${STUB_LOG:-/dev/null}"
case "$1 $2" in "auth status") exit 0 ;; esac
if [[ "$1 $2" == "issue view" ]]; then
  if [[ " $* " == *" --json labels "* ]]; then
    [[ "${GH_LABELS_FAIL:-0}" == "1" ]] && exit 1
    cat "${GH_LABELS:-/dev/null}"; exit 0
  fi
  echo "#7 stub"; exit 0
fi
if [[ "$1 $2" == "issue edit" ]]; then
  if [[ " $* " == *" --add-label "* && "${GH_ADD_FAIL:-0}" == "1" ]]; then exit 7; fi
  exit 0
fi
if [[ "$1 $2" == "issue comment" ]]; then
  [[ "${GH_COMMENT_FAIL:-0}" == "1" ]] && exit 6
  echo "https://github.com/o/r/issues/7#issuecomment-1"; exit 0
fi
exit 0
STUB
chmod +x "$WORK/ghbin/gh"

cat > "$WORK/glabbin/glab" <<'STUB'
#!/usr/bin/env bash
echo "glab $*" >> "${STUB_LOG:-/dev/null}"
if [[ "$1 $2" == "auth status" ]]; then exit 0; fi
if [[ "$1 $2" == "issue note" ]]; then
  [[ "${GLAB_COMMENT_FAIL:-0}" == "1" ]] && exit 5
  echo "https://gitlab.com/o/r/-/issues/7#note_1"; exit 0
fi
exit 0
STUB
chmod +x "$WORK/glabbin/glab"

cat > "$WORK/teabin/tea" <<'STUB'
#!/usr/bin/env bash
echo "tea $*" >> "${STUB_LOG:-/dev/null}"
if [[ "$1 $2" == "login list" ]]; then
  echo "https://gitea.example.com  gitea  someuser  token"; exit 0
fi
if [[ "$1 $2" == "comments add" ]]; then
  [[ "${TEA_COMMENT_FAIL:-0}" == "1" ]] && exit 4
  echo "https://gitea.example.com/o/r/issues/7#issuecomment-1"; exit 0
fi
exit 0
STUB
chmod +x "$WORK/teabin/tea"

make_repo() {
  local d="$WORK/$1" url="$2"
  mkdir -p "$d"; git -C "$d" init -q; git -C "$d" remote add origin "$url"
  echo "tracked" > "$d/tracked.txt"
  git -C "$d" add tracked.txt
  git -C "$d" -c user.name=t -c user.email=t@e commit -qm init
  echo "$d"
}
GH_REPO="$(make_repo gh https://github.com/o/r.git)"
GLAB_REPO="$(make_repo glab https://gitlab.com/o/r.git)"
TEA_REPO="$(make_repo tea https://gitea.example.com/o/r.git)"
printf 'p1\nriper-plan\n' > "$WORK/labels"

# ---------------------------------------------------------------------------
# probe <repo> <bin> <file|dir|closed|default> [ENV=VAL...] -- <args...>
# Sets RC / OUT / ERR / EV; CALLS is the CLI invocation log for this probe.
# ---------------------------------------------------------------------------
RC=0; OUT=""; ERR=""; EV=""; CALLS=""
probe() {
  local repo="$1" bin="$2" mode="$3"; shift 3
  local envargs=() a
  while [[ $# -gt 0 && "$1" != "--" ]]; do envargs+=("$1"); shift; done
  [[ "${1:-}" == "--" ]] && shift

  local outfile="$WORK/stdout" errfile="$WORK/stderr" evfile="$WORK/events" callfile="$WORK/calls.log"
  : > "$outfile"; : > "$errfile"; : > "$evfile"; : > "$callfile"
  RC=0
  (
    cd "$repo"
    export PATH="$bin:$PATH" STUB_LOG="$callfile" GH_LABELS="$WORK/labels"
    for a in ${envargs[@]+"${envargs[@]}"}; do export "$a"; done
    case "$mode" in
      file)    exec 3>"$evfile"; export ILOOP_EVENTS_FD=3 ;;
      dir)     exec 3<"$WORK";   export ILOOP_EVENTS_FD=3 ;;
      closed)  export ILOOP_EVENTS_FD=3 ;;
      default) exec 3>"$evfile" ;;
      *)       fail "bad probe mode $mode"; return 1 ;;
    esac
    /bin/bash "$GITOPS" "$@" >"$outfile" 2>"$errfile"
  ) || RC=$?
  OUT="$(cat "$outfile")"; ERR="$(cat "$errfile")"; EV="$(cat "$evfile")"; CALLS="$(cat "$callfile")"
}

event_count() {
  local n
  n="$(grep -c . "$WORK/events" 2>/dev/null || true)"
  [[ -n "$n" ]] || n=0
  echo "$n"
}

# event_field <file> <key>
event_field() {
  python3 - "$1" "$2" <<'PY'
import json, sys
lines = [l for l in open(sys.argv[1]) if l.strip()]
if len(lines) != 1:
    print("<count:%d>" % len(lines)); raise SystemExit(0)
d = json.loads(lines[0])
print(d.get(sys.argv[2], "<missing>"))
PY
}

# assert_event <file> <key> <expected> <msg>
assert_event() {
  local got
  got="$(event_field "$1" "$2")"
  assert_eq "$got" "$3" "$4"
}

assert_keys() {
  if python3 - "$1" <<'PY'
import json, sys
d = json.loads(open(sys.argv[1]).read().strip())
expect = {"schema","run_id","event_id","time","skill_tag","skill_sha","issue","role",
          "action","result","rule","exit_code","duration_ms","checkpoint","side_effects"}
raise SystemExit(0 if set(d) == expect else 1)
PY
  then pass "$2"; else fail "$2"; fi
}

assert_no_secret() {
  local f="$1" s="$2" msg="$3"
  if grep -Fq -- "$s" "$f"; then fail "$msg"; else pass "$msg"; fi
}

echo "=== step 1: format, syntax, links, and contract enums ==="
for s in "$GITOPS" "$RUNTIME_EVENTS"; do
  if /bin/bash -n "$s" 2>/dev/null; then pass "bash -n $(basename "$s")"; else fail "bash -n $(basename "$s")"; fi
done
if python3 -m json.tool "$ROOT/skill-manifest.json" >/dev/null 2>&1; then pass "manifest JSON valid"; else fail "manifest JSON valid"; fi
for p in scripts/runtime-events.sh references/runtime-output.md templates/run-summary.md; do
  if [[ -f "$ROOT/$p" ]]; then pass "exists $p"; else fail "exists $p"; fi
done
for p in scripts/runtime-events.sh references/runtime-output.md templates/run-summary.md; do
  assert_grep "$ROOT/skill-manifest.json" "$p" "manifest requiredPaths includes $p"
done

# Relative Markdown links in the touched documents must resolve.
link_fail=0
for f in "$ROOT/SKILL.md" "$ROOT/README.md" "$ROOT/README_CN.md" "$DOC" "$TEMPLATE" \
         "$ROOT/references/feedback-loop.md" "$ROOT/roles/planner.md" \
         "$ROOT/roles/developer.md" "$ROOT/roles/reviewer.md"; do
  base="$(dirname "$f")"
  while IFS= read -r link; do
    case "$link" in http://*|https://*|mailto:*|\#*) continue ;; esac
    link="${link%%#*}"
    [[ -z "$link" ]] && continue
    [[ -e "$base/$link" ]] || { fail "broken link in $(basename "$f"): $link"; link_fail=1; }
  done < <(grep -oE '\]\([^)]+\)' "$f" | sed 's/^](//; s/)$//')
done
[[ "$link_fail" -eq 0 ]] && pass "relative Markdown links resolve"

for v in success denied failed partial; do
  assert_grep "$DOC" "\`$v\`" "contract documents result=$v"
done
for v in none unknown label-cleanup-only remote-write; do
  assert_grep "$DOC" "\`$v\`" "contract documents side_effects=$v"
done
for v in requested permission-denied family-cleaned family-cleanup-failed add-failed write-failed branch-mismatch violations clean completed; do
  assert_grep "$DOC" "\`$v\`" "contract documents checkpoint=$v"
done
for v in 'issue\.priority' 'issue\.status' 'issue\.comment' 'guard'; do
  assert_grep "$DOC" "$v" "contract documents action $v"
done
assert_grep "$DOC" 'ILOOP_EVENTS_FD=3' "contract documents enablement"
assert_grep "$DOC" 'ILOOP_RUN_ID' "contract documents cross-process run id"
assert_grep "$DOC" 'SIGKILL' "contract documents the SIGKILL limitation"
assert_grep "$DOC" '1000ms' "contract documents duration precision"
assert_grep "$TEMPLATE" 'iloop-summary run_id=' "template carries the dedupe marker"
for field in '当前阶段 / 角色' '进入依据' '已完成' '未完成' '下一步' '等待原因' '前序 run'; do
  assert_grep "$TEMPLATE" "$field" "template includes $field"
done
for tag in 'script-observed' 'agent-declared' 'unverified'; do
  assert_grep "$DOC" "\[$tag\]" "contract documents provenance $tag"
done

echo "=== step 2: default off and output compatibility ==="
probe "$GH_REPO" "$WORK/ghbin" default -- --role developer issue status 7 riper-review
default_rc=$RC; default_out=$OUT; default_err=$ERR
assert_eq "$(event_count)" "0" "default (no ILOOP_EVENTS_FD) emits zero events"
probe "$GH_REPO" "$WORK/ghbin" closed ILOOP_EVENTS_FD=3 -- --role developer issue status 7 riper-review
assert_eq "$(event_count)" "0" "closed fd emits zero events"
assert_eq "$RC" "$default_rc" "closed fd keeps exit code"
assert_eq "$OUT" "$default_out" "closed fd keeps stdout"
assert_eq "$ERR" "$default_err" "closed fd keeps stderr"

probe "$GH_REPO" "$WORK/ghbin" file -- --role developer issue status 7 riper-review
success_rc=$RC; success_out=$OUT; success_err=$ERR
assert_eq "$(event_count)" "1" "enabled success emits exactly one event"
assert_eq "$RC" "$default_rc" "event run keeps exit code"
assert_eq "$OUT" "$default_out" "event run keeps stdout"
assert_eq "$ERR" "$default_err" "event run keeps stderr"
cp "$WORK/events" "$WORK/e_success"

echo "=== step 3: event envelope and success fields ==="
f="$WORK/e_success"
assert_keys "$f" "event has exactly the documented field set"
assert_event "$f" schema "iloop.runtime.v1" "schema"
assert_event "$f" role "developer" "role"
assert_event "$f" issue "7" "issue"
assert_event "$f" action "issue.status" "action"
assert_event "$f" result "success" "result success"
assert_event "$f" rule "unknown" "rule unknown"
assert_event "$f" checkpoint "completed" "checkpoint completed"
assert_event "$f" side_effects "remote-write" "side_effects remote-write"
assert_event "$f" exit_code "0" "exit_code 0"
if [[ "$(event_field "$f" run_id)" =~ ^r-[0-9a-f]{32}$ ]]; then pass "run_id format"; else fail "run_id format"; fi
if [[ "$(event_field "$f" event_id)" =~ ^e-[0-9a-f]{32}$ ]]; then pass "event_id format"; else fail "event_id format"; fi
if [[ "$(event_field "$f" time)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then pass "time is UTC RFC3339"; else fail "time is UTC RFC3339"; fi
if [[ "$(event_field "$f" skill_tag)" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || "$(event_field "$f" skill_tag)" == "unknown" ]]; then pass "skill_tag stable or unknown"; else fail "skill_tag stable or unknown"; fi
if [[ "$(event_field "$f" skill_sha)" =~ ^[0-9a-f]{40,64}$ || "$(event_field "$f" skill_sha)" == "unknown" ]]; then pass "skill_sha valid or unknown"; else fail "skill_sha valid or unknown"; fi
if [[ "$(event_field "$f" duration_ms)" =~ ^[0-9]+$ || "$(event_field "$f" duration_ms)" == "unknown" ]]; then pass "duration_ms numeric or unknown"; else fail "duration_ms numeric or unknown"; fi

echo "=== step 4: four result kinds ==="
# denied: developer may not set riper-verified
probe "$GH_REPO" "$WORK/ghbin" file -- --role developer issue status 7 riper-verified
assert_eq "$(event_count)" "1" "denied emits one event"
assert_eq "$RC" "1" "denied exit code"
assert_event "$WORK/events" result "denied" "denied result"
assert_event "$WORK/events" rule "ROLE-001" "denied rule"
assert_event "$WORK/events" checkpoint "permission-denied" "denied checkpoint"
assert_event "$WORK/events" side_effects "none" "denied side_effects"
probe "$GH_REPO" "$WORK/ghbin" file -- --role developer issue status 7 riper-verified
denied_rc=$RC; denied_out=$OUT; denied_err=$ERR
probe "$GH_REPO" "$WORK/ghbin" default -- --role developer issue status 7 riper-verified
assert_eq "$RC" "$denied_rc" "denied: default keeps exit code"
assert_eq "$OUT" "$denied_out" "denied: default keeps stdout"
assert_eq "$ERR" "$denied_err" "denied: default keeps stderr"

# failed: label read fails before any confirmed write
probe "$GH_REPO" "$WORK/ghbin" file GH_LABELS_FAIL=1 -- --role developer issue status 7 riper-review
assert_eq "$RC" "1" "failed exit code"
assert_event "$WORK/events" result "failed" "failed result"
assert_event "$WORK/events" rule "unknown" "failed rule stays unknown"
assert_event "$WORK/events" checkpoint "family-cleanup-failed" "failed checkpoint"
assert_event "$WORK/events" side_effects "unknown" "failed side_effects unknown"

# partial: family cleanup succeeds, target add fails with the CLI's own code
probe "$GH_REPO" "$WORK/ghbin" file GH_ADD_FAIL=1 -- --role developer issue status 7 riper-review
assert_eq "$RC" "7" "partial preserves the CLI exit code"
assert_eq "$(event_count)" "1" "partial emits one event"
assert_event "$WORK/events" result "partial" "partial result"
assert_event "$WORK/events" checkpoint "add-failed" "partial checkpoint"
assert_event "$WORK/events" side_effects "label-cleanup-only" "partial side_effects"
assert_eq "$(printf '%s\n' "$CALLS" | grep -c -- '--add-label')" "1" "partial does not replay the add call"

echo "=== step 5: unknown fields, malformed ids, and redaction ==="
probe "$GH_REPO" "$WORK/ghbin" file -- issue status 7 riper-review
assert_event "$WORK/events" role "unknown" "no explicit role becomes unknown"
assert_event "$WORK/events" result "success" "no-role operation still succeeds"

probe "$GH_REPO" "$WORK/ghbin" file ILOOP_RUN_ID=r-NOTVALID-SECRET -- --role developer issue status 7 riper-review
assert_event "$WORK/events" run_id "unknown" "malformed run_id becomes unknown"
assert_no_secret "$WORK/events" "NOTVALID" "malformed run_id is not echoed"

RID="r-0123456789abcdef0123456789abcdef"
probe "$GH_REPO" "$WORK/ghbin" file ILOOP_RUN_ID="$RID" -- --role developer issue status 7 riper-review
cp "$WORK/events" "$WORK/e_run1"
assert_event "$WORK/e_run1" run_id "$RID" "valid run_id is preserved"
probe "$GH_REPO" "$WORK/ghbin" file ILOOP_RUN_ID="$RID" -- --role developer issue status 7 riper-review
cp "$WORK/events" "$WORK/e_run2"
assert_event "$WORK/e_run2" run_id "$RID" "run_id crosses processes"
if [[ "$(event_field "$WORK/e_run1" event_id)" != "$(event_field "$WORK/e_run2" event_id)" ]]; then pass "event_id differs per process"; else fail "event_id differs per process"; fi

SECRET_BODY="TOKEN=super-secret-value /Users/private/path https://private.example/x"
probe "$GH_REPO" "$WORK/ghbin" file -- --role reviewer issue comment 7 "$SECRET_BODY"
assert_eq "$(event_count)" "1" "comment emits one event"
assert_event "$WORK/events" action "issue.comment" "comment action"
assert_event "$WORK/events" result "success" "comment success"
assert_no_secret "$WORK/events" "super-secret-value" "comment body token is not captured"
assert_no_secret "$WORK/events" "/Users/private/path" "comment body path is not captured"
assert_no_secret "$WORK/events" "private.example" "comment body URL is not captured"
assert_no_secret "$WORK/events" "$WORK" "skill/working paths are not captured"

echo "=== step 6: guard outcomes ==="
probe "$GH_REPO" "$WORK/ghbin" file -- --role developer guard developer 7
assert_event "$WORK/events" action "guard" "guard action"
assert_event "$WORK/events" result "success" "clean guard succeeds"
assert_event "$WORK/events" checkpoint "clean" "clean guard checkpoint"
assert_event "$WORK/events" side_effects "none" "clean guard has no side effects"

printf 'x\n' > "$GH_REPO/src.txt"
probe "$GH_REPO" "$WORK/ghbin" file -- --role planner guard planner
assert_eq "$RC" "1" "guard violation exit code"
assert_event "$WORK/events" result "failed" "guard violation fails"
assert_event "$WORK/events" rule "WORKSPACE-001" "guard violation rule"
assert_event "$WORK/events" checkpoint "violations" "guard violation checkpoint"
rm -f "$GH_REPO/src.txt"

git -C "$GH_REPO" switch -q -c riper/9
probe "$GH_REPO" "$WORK/ghbin" file -- --role developer guard developer 7
assert_event "$WORK/events" result "failed" "branch mismatch fails"
assert_event "$WORK/events" checkpoint "branch-mismatch" "branch mismatch checkpoint"
git -C "$GH_REPO" switch -q -

echo "=== step 7: failing fd, foreign cwd, non-git Skill ==="
probe "$GH_REPO" "$WORK/ghbin" file -- --role developer issue status 7 riper-review
fd_rc=$RC; fd_out=$OUT
probe "$GH_REPO" "$WORK/ghbin" dir -- --role developer issue status 7 riper-review
assert_eq "$(event_count)" "0" "failing fd writes no event"
assert_eq "$RC" "$fd_rc" "failing fd keeps exit code"
assert_eq "$OUT" "$fd_out" "failing fd keeps stdout"

mkdir -p "$WORK/foreign"
RC=0; OUT=""; ERR=""; EV=""
(
  cd "$WORK/foreign"
  export PATH="$WORK/ghbin:$PATH" STUB_LOG="$WORK/calls.log"
  exec 3>"$WORK/events"
  ILOOP_EVENTS_FD=3 /bin/bash "$GITOPS" --role developer guard developer >"$WORK/stdout" 2>"$WORK/stderr"
) || RC=$?
EV="$(cat "$WORK/events")"
assert_eq "$(event_count)" "1" "foreign cwd still emits one event"
assert_no_secret "$WORK/events" "$WORK" "foreign cwd path is not captured"
if [[ "$(event_field "$WORK/events" skill_sha)" =~ ^[0-9a-f]{40,64}$ ]]; then
  pass "skill metadata resolves from the Skill root, not cwd"
else
  fail "skill metadata resolves from the Skill root, not cwd"
fi

mkdir -p "$WORK/nongit/scripts"
cp "$GITOPS" "$RUNTIME_EVENTS" "$WORK/nongit/scripts/"
probe "$GH_REPO" "$WORK/ghbin" file -- --role developer issue status 7 riper-review
: > "$WORK/events"
(
  cd "$GH_REPO"
  export PATH="$WORK/ghbin:$PATH" STUB_LOG="$WORK/calls.log" GH_LABELS="$WORK/labels"
  exec 3>"$WORK/events"
  ILOOP_EVENTS_FD=3 /bin/bash "$WORK/nongit/scripts/git-ops.sh" --role developer issue status 7 riper-review >/dev/null 2>&1
) || true
assert_event "$WORK/events" skill_tag "unknown" "non-git Skill tag is unknown"
assert_event "$WORK/events" skill_sha "unknown" "non-git Skill SHA is unknown"

echo "=== step 8: three-platform CLI fixtures ==="
probe "$GLAB_REPO" "$WORK/glabbin" file -- --role reviewer issue comment 7 "glab note"
assert_eq "$(event_count)" "1" "glab emits one event"
assert_event "$WORK/events" action "issue.comment" "glab action"
assert_event "$WORK/events" result "success" "glab success"
grep -q '^glab issue note 7 --message glab note$' "$WORK/calls.log" && pass "glab CLI invoked once" || fail "glab CLI invoked once"

probe "$TEA_REPO" "$WORK/teabin" file -- --role reviewer issue comment 7 "tea note"
assert_eq "$(event_count)" "1" "tea emits one event"
assert_event "$WORK/events" action "issue.comment" "tea action"
assert_event "$WORK/events" result "success" "tea success"
grep -q '^tea comments add 7 tea note --repo o/r$' "$WORK/calls.log" && pass "tea CLI invoked once" || fail "tea CLI invoked once"

echo "=== step 9: summary scenarios are documented and separated from E2E ==="
if [[ -f "$SCENARIOS" ]]; then pass "scenario walkthrough exists"; else fail "scenario walkthrough exists"; fi
for node in boot-dispatch stage-handoff pause resume close; do
  assert_grep "$SCENARIOS" "$node" "scenarios cover $node"
done
for reason in '等待用户' '环境' '计划缺陷' 'QA FAIL' '认领冲突'; do
  assert_grep "$SCENARIOS" "$reason" "scenarios cover pause reason: $reason"
done
assert_grep "$SCENARIOS" '协议走查' "scenarios label themselves as a protocol walkthrough"
assert_grep "$SCENARIOS" 'not.*Agent E2E|不等同.*Agent.*E2E|不是独立' "scenarios do not claim Agent E2E"
assert_grep "$SCENARIOS" '真实运行证据' "scenarios separate fixture and real-run evidence"
assert_grep "$SCENARIOS" 'fixture' "scenarios name fixture evidence"

echo "=== step 10: existing suite compatibility is recorded separately ==="
if grep -q 'test/\*\.sh' "$ROOT/README.md" 2>/dev/null || [[ -d "$ROOT/test" ]]; then
  pass "existing test inventory present"
else
  fail "existing test inventory present"
fi

echo ""
if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0