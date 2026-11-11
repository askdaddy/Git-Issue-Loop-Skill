#!/usr/bin/env bash
# Black-box contracts for the offline global feedback queue (#70). Fixtures only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/q"
export ILOOP_FEEDBACK_DIR="$WORK/q" FEEDBACK_CALL_LOG="$WORK/calls" PRIVATE_SECRET=PRIVATE_SECRET_MUST_NOT_APPEAR
for tool in gh glab tea curl wget; do
  cat > "$WORK/bin/$tool" <<STUB
#!/usr/bin/env bash
printf 'called\n' >> "$FEEDBACK_CALL_LOG"
exit 0
STUB
  chmod +x "$WORK/bin/$tool"
done
export PATH="$WORK/bin:$PATH"
FB=(bash "$ROOT/scripts/feedback.sh")

# add: id format, entry fields, offline allowlist metadata.
id1="$("${FB[@]}" add bug 'queue-summary' 'queue-detail')"
id2="$("${FB[@]}" add protocol 'ROLE-001 operation-denied at doctor')"
id3="$("${FB[@]}" add doc 'doc error summary')"
[[ "$id1" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{4}$ ]] || { echo 'FAIL entry id format'; exit 1; }
entry="$WORK/q/entries/$id1.md"
for field in 'schema: 2' "id: $id1" 'category: bug' 'summary: queue-summary' 'detail: queue-detail' 'status: pending' 'rule: none'; do
  grep -q "^- $field\$" "$entry" || { echo "FAIL missing field $field"; exit 1; }
done
grep -qE '^- created: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$entry" || { echo 'FAIL created utc'; exit 1; }
grep -q "^- skill-sha: $(git -C "$ROOT" rev-parse HEAD)$" "$entry" || { echo 'FAIL skill sha'; exit 1; }
expect_tag="$(git -C "$ROOT" describe --tags --exact-match HEAD 2>/dev/null || echo unknown)"
grep -q "^- skill-tag: $expect_tag\$" "$entry" || { echo 'FAIL skill tag'; exit 1; }

# add: invalid category / newline / empty summary fail without echoing secrets.
if out="$("${FB[@]}" add feature-request "$PRIVATE_SECRET" 2>&1)"; then echo 'FAIL accepted invalid category'; exit 1; fi
[[ "$out" != *PRIVATE_SECRET* ]] || { echo 'FAIL echoed secret on invalid category'; exit 1; }
if "${FB[@]}" add bug "$(printf 'a\nb')" >/dev/null 2>&1; then echo 'FAIL accepted newline summary'; exit 1; fi
if "${FB[@]}" add bug '' >/dev/null 2>&1; then echo 'FAIL accepted empty summary'; exit 1; fi
echo 'PASS add fields, id format and rejections without secret echo'

# add: default path resolves under HOME, never the real one.
home_id="$(env -u ILOOP_FEEDBACK_DIR HOME="$WORK/home" "${FB[@]}" add behavior 'default-home-entry')"
[[ -f "$WORK/home/.agents/iloop-feedback/entries/$home_id.md" ]] || { echo 'FAIL default queue path'; exit 1; }
echo 'PASS default queue path resolves under HOME fixture'

# add: unwritable queue root fails loudly with guidance.
mkdir -p "$WORK/ro" && chmod 500 "$WORK/ro"
if env ILOOP_FEEDBACK_DIR="$WORK/ro/q" "${FB[@]}" add bug x >"$WORK/ro.out" 2>&1; then
  chmod 700 "$WORK/ro"; echo 'FAIL writable check missing'; exit 1
fi
chmod 700 "$WORK/ro"
grep -q 'ILOOP_FEEDBACK_DIR' "$WORK/ro.out" || { echo 'FAIL readonly guidance'; exit 1; }
echo 'PASS unwritable queue root fails with fix guidance'

# list: pending filter, all scope, empty state.
"${FB[@]}" dismiss "$id3" >/dev/null
pending="$("${FB[@]}" list)"
[[ "$(printf '%s\n' "$pending" | grep -c .)" -eq 2 ]] || { echo 'FAIL pending row count'; exit 1; }
[[ "$pending" == *"$id1"* && "$pending" == *"$id2"* && "$pending" != *"$id3"* ]] || { echo 'FAIL pending filter'; exit 1; }
[[ "$("${FB[@]}" list all | grep -c .)" -eq 3 ]] || { echo 'FAIL all row count'; exit 1; }
empty="$(env ILOOP_FEEDBACK_DIR="$WORK/none" "${FB[@]}" list)" && [[ "$empty" == "0" ]] || { echo 'FAIL empty state'; exit 1; }
echo 'PASS list pending/all filtering and empty state'

# show: full entry vs unknown/traversal ids.
"${FB[@]}" show "$id2" | grep -q '^- summary: ROLE-001 operation-denied at doctor$' || { echo 'FAIL show content'; exit 1; }
if "${FB[@]}" show 20260101T000000Z-dead >/dev/null 2>&1; then echo 'FAIL show unknown id'; exit 1; fi
if "${FB[@]}" show '../../etc/passwd' >/dev/null 2>&1; then echo 'FAIL show traversal id'; exit 1; fi
echo 'PASS show known ids only'

# dismiss/reported: one-way state machine with URL backfill.
if "${FB[@]}" dismiss "$id3" >/dev/null 2>&1; then echo 'FAIL double dismiss'; exit 1; fi
url='https://github.com/askdaddy/Git-Issue-Loop-Skill/issues/99'
"${FB[@]}" reported "$id2" "$url" >/dev/null
rep="$WORK/q/entries/$id2.md"
grep -q '^- status: reported$' "$rep" && grep -q "^- reported-url: $url\$" "$rep" \
  && grep -qE '^- reported-at: [0-9]{4}-[0-9]{2}-[0-9]{2}T' "$rep" || { echo 'FAIL reported backfill'; exit 1; }
if "${FB[@]}" reported "$id2" "$url" >/dev/null 2>&1; then echo 'FAIL double reported'; exit 1; fi
if "${FB[@]}" dismiss "$id2" >/dev/null 2>&1; then echo 'FAIL dismiss after reported'; exit 1; fi
if "${FB[@]}" reported "$id1" 'http://plain.example/x' >/dev/null 2>&1; then echo 'FAIL non-https url'; exit 1; fi
echo 'PASS one-way state machine and reported backfill'

# Whole queue lifecycle stayed offline; nothing landed outside fixtures.
[[ ! -e "$WORK/calls" ]] || { echo 'FAIL platform/network call leaked'; exit 1; }
[[ ! -e "$HOME/.agents/iloop-feedback" ]] || { echo 'FAIL real home touched'; exit 1; }
echo 'PASS zero platform/network calls and real home untouched'

# draft: schema-1 draft output unchanged (old suite covers it fully).
"${FB[@]}" draft permission suspected | grep -q 'rule: ROLE-001' || { echo 'FAIL draft compat'; exit 1; }
echo 'PASS draft subcommand backward compatible'

# Protocol wiring: positive text checks, then negative direction on stripped copies.
SKILL="$ROOT/SKILL.md"; DOC="$ROOT/references/feedback-loop.md"; CL="$ROOT/CHANGELOG.md"
assert_text() { # file pattern label
  grep -q "$2" "$1" || { echo "FAIL text: $3"; exit 1; }
  grep -v "$2" "$1" > "$WORK/stripped" || true
  if grep -q "$2" "$WORK/stripped"; then echo "FAIL negative direction: $3"; exit 1; fi
}
assert_text "$SKILL" 'feedback.sh add <bug|protocol|doc|behavior>' 'SKILL add protocol line'
assert_text "$SKILL" '闭环终点反馈询问' 'SKILL ask point: loop end'
assert_text "$SKILL" '挂起时若全局反馈待上报队列非空' 'SKILL ask point: buffer suspend'
assert_text "$SKILL" '退出前若全局反馈待上报队列非空' 'SKILL ask point: buffer exit'
assert_text "$SKILL" '不收集功能建议' 'SKILL correction-only semantics'
assert_text "$SKILL" '唯一例外：§3.8 全局反馈队列' 'SKILL buffer exclusion'
assert_text "$DOC" '~/.agents/iloop-feedback/entries/<ID>.md' 'DOC queue path'
assert_text "$DOC" 'pending → reported | dismissed' 'DOC state machine'
assert_text "$DOC" '用户授权沉淀的用户数据' 'DOC harmonized wording'
assert_text "$DOC" 'reported <ID> <issue-url>` 回填队列条目' 'DOC upstream backfill step'
assert_text "$CL" '## \[Unreleased\]' 'CHANGELOG unreleased section'
assert_text "$CL" '\(#70\)' 'CHANGELOG issue reference'
echo 'PASS protocol wiring text checks, positive and negative directions'

# The pre-existing feedback suite must keep passing unmodified.
bash "$ROOT/test/iloop-feedback-invariants.sh" >/dev/null || { echo 'FAIL legacy feedback suite'; exit 1; }
echo 'PASS legacy feedback invariants unmodified'

echo 'RESULT PASS'
