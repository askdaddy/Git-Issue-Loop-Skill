#!/usr/bin/env bash
# Black-box contract checks for Issue #20 (bare /iloop auto-pick).
# Two planes:
#   (A) protocol contract — SKILL.md must route a bare /iloop to a read-only
#       auto-pick (defaults instead of the three questions), with the ordering,
#       the three skip states, the glab/tea degradation, the report fields, the
#       confirm stop, and the two terminal branches all stated; the old
#       "must ask three questions first" precondition must be gone.
#   (B) data-availability — a mixed stub backlog proves every pick input
#       (num / priority / status / retry) is obtainable from the read-only
#       subcommands alone, and that applying the documented rules yields exactly
#       one winner. Retry never appears in `issue list`, and the glab no-label
#       column path is covered as the degradation case.
# Run from repository root: bash test/iloop-bare-iloop-autopick-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${ROOT}/SKILL.md"
GITOPS="${ROOT}/scripts/git-ops.sh"
FAILS=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

has() {  # has <pattern> <label>  (ERE, SKILL.md)
  if grep -qE -- "$1" "$SKILL"; then pass "$2"; else fail "$2 — pattern absent: $1"; fi
}
lacks() {
  if grep -qE -- "$1" "$SKILL"; then fail "$2 — pattern still present: $1"; else pass "$2"; fi
}

echo "=== (A1) bare entry: defaults replace the three questions ==="
has '裸 `/iloop`（无任何参数）进入时，自动挑选最该处理的 Issue' "entry section declares auto-pick for a bare /iloop"
has '1\. \*\*目标 Issue\*\*：由 §3\.0\.1 第 0 层的「自动挑选」子程序选出唯一一个候选' "target issue default = auto-pick result"
has '2\. \*\*执行范围\*\*：默认所选 Issue 的\*\*完整闭环\*\*' "scope default = full closed loop for that one issue"
has '3\. \*\*落盘方式\*\*：沿用默认' "fallback default stated without asking"
has '每次调用只处理 1 个' "one issue per invocation"
lacks '必须先问清三件事|无参数进入时，必须先问|仍先问清目标 Issue' "old three-questions precondition removed"
has '容错：若用户在 `/iloop` 后直接带了编号或阶段意图' "explicit-input fast path retained"

echo "=== (A2) layer 0 routing ==="
has '\| \*\*裸 `/iloop`（无任何参数与意图词）\*\* \| \*\*自动挑选\*\*子程序（见下）→ 呈报待确认 → 对选中编号进入第 1 层 \|' "layer 0 has the bare-entry route"
has '六条显式路由\*\*均优先于\*\*自动挑选；裸 `/iloop` 是最末兜底路由' "explicit routes keep precedence over auto-pick"
has '\*\*自动挑选\*\*：只读、无角色、不写回 Issue' "auto-pick is read-only, role-free, writes nothing"
has '禁止\*\*为此提前加载任何 `roles/\*\.md`，禁止写状态/写标签/写评论' "no role loading and no writes before dispatch (C1)"

echo "=== (A3) pick inputs, ordering, skip rules, degradation ==="
has '`issue list --state open` 给出编号、优先级、RIPER 状态' "list supplies num/priority/status"
has 'retry 值逐个调 `issue retry <N> get`（列表\*\*不含\*\* retry 列）' "retry comes from retry get, not from list (C11)"
has 'p0 → p1 → p2 → p3 → 无优先级；同键按编号升序' "ordering rule is written down"
has '该顺序由本步负责，不依赖 `issue list` 的打印顺序' "ordering owned by the pick step"
has '`riper-blocked`（等人工介入）' "skip state: blocked"
has '`riper-retry-3`（重试超限）' "skip state: retry cap"
has '`riper-verified` 但未关闭（异常态，仅提示人工关闭/重开，不改状态）' "skip state: verified-but-open"
has '改逐条 `issue get <N>` 读真实标签' "degradation switches to per-issue get (C10)"
has '并在报告中\*\*标注该降级依据\*\*，禁止按 `\(无\)` 占位静默误选' "degradation must be reported, never silent"

echo "=== (A4) report fields, confirm stop, terminal branches, no persistence ==="
has '每条含 `编号 / 优先级 / RIPER 状态 / retry 值 / 是否跳过及原因`' "report carries the four-tuple plus skip reason"
has '末行给出选中项与一句话理由' "report ends with the pick and a reason"
has '\*\*停在此处等用户确认或改选\*\*，不得选完直接开工' "agent stops for confirmation before work"
has '改选任一编号等同显式 `/iloop <编号>`，重新进第 1 层分发' "user re-pick re-enters layer 1"
has '无 open Issue → 报告空态并指向 .\[G\].' "empty backlog branch"
has '\*\*禁止\*\*自动建 Issue、不加载角色' "empty branch must not create issues or load roles"
has '全部候选被跳过 → 报告各自卡点原因后停止，不改任何状态' "all-skipped branch reports and stops"
has '挑选报告是对话内产物，\*\*不落盘、不写 Issue 评论\*\*' "pick report is not persisted (C9)"

echo "=== (A5) other entry points unchanged ==="
has '/iloop                        → 自动挑选：doctor 自检后按 p0→p3（同键编号升序）挑出最该处理的 1 个 open Issue' "quick-usage bare row matches new semantics"
has '/iloop 我要实现 XXX' "goal bootstrap row intact"
has '"落地 issue #42"' "explicit number row intact"
has '"推进迭代"                    → 扫描 open issue' "backlog scan row intact"
has '/iloop help                   → 输出技能用法' "help row intact"
if grep -q '自动挑选报告只是入口路由产物' "${ROOT}/roles/planner.md"; then pass "planner role: pick report is not a spec input"; else fail "planner role: pick report boundary missing"; fi

# ===========================================================================
# (B) data availability — stub gh + throwaway repo routed by origin hostname
# ===========================================================================
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/ghproj" "$WORK/glabproj" "$WORK/lab" "$WORK/glablab"
git -C "$WORK/ghproj" init -q
git -C "$WORK/ghproj" remote add origin https://github.com/o/r.git
git -C "$WORK/glabproj" init -q
git -C "$WORK/glabproj" remote add origin https://gitlab.com/o/r.git

cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-} ${2:-}" == "auth status" ]]; then exit 0; fi
if [[ "${1:-} ${2:-}" == "issue list" ]]; then
  while IFS="$(printf '\t')" read -r n s t; do
    [[ -z "${n:-}" ]] && continue
    labs=""
    [[ -f "$GH_LABELDIR/$n" ]] && labs="$(paste -sd, "$GH_LABELDIR/$n" 2>/dev/null)"
    printf '%s\t%s\t%s\t%s\n' "$n" "$s" "$t" "$labs"
  done < "$GH_ISSUES"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "issue view" ]]; then
  num="${3:-}"
  [[ -f "$GH_LABELDIR/$num" ]] && cat "$GH_LABELDIR/$num"
  exit 0
fi
exit 0
STUB
cat > "$WORK/bin/glab" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" ]]; then exit 0; fi
if [[ "${1:-} ${2:-}" == "issue list" ]]; then
  while IFS="$(printf '\t')" read -r n s t; do
    [[ -z "${n:-}" ]] && continue
    printf '#%s  %s\n' "$n" "$t"
  done < "$GLAB_ISSUES"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "issue view" ]]; then
  num="${3:-}"
  printf 'title:\tstub\nstate:\topen\nlabels:\t%s\n' "$(paste -sd, "$GLAB_LABELDIR/$num" 2>/dev/null)"
  exit 0
fi
exit 0
STUB
chmod +x "$WORK/bin/gh" "$WORK/bin/glab"

# mixed backlog: 32 retry-capped, 33 blocked, 34 eligible p0 (no status label),
# 31 p1, 35 p2 open-but-verified, 36 no priority at all.
# Titles are deliberately neutral so column-content greps cannot match by accident.
printf '%s\t%s\t%s\n' 31 OPEN 'alpha' 32 OPEN 'bravo' 33 OPEN 'charlie' \
  34 OPEN 'delta' 35 OPEN 'echo' 36 OPEN 'foxtrot' > "$WORK/issues.tsv"
printf '%s\n' p1 riper-plan   > "$WORK/lab/31"
printf '%s\n' p0 riper-execute riper-retry-3      > "$WORK/lab/32"
printf '%s\n' p0 riper-blocked                    > "$WORK/lab/33"
printf '%s\n' p0 riper-retry-2                    > "$WORK/lab/34"
printf '%s\n' p2 riper-verified                   > "$WORK/lab/35"
printf '%s\n' riper-research                      > "$WORK/lab/36"
printf '%s\n' p0 riper-execute riper-retry-3 > "$WORK/glablab/41"
printf '%s\n' p1 riper-plan                  > "$WORK/glablab/42"
printf '%s\t%s\t%s\n' 41 OPEN 'golf' 42 OPEN 'hotel' > "$WORK/gissues.tsv"

# run <project> <ENV=v ...> -- <git-ops args...> — captures stdout only (rc kept in RC)
RC=0; OUT=""
run() {
  local proj="$1"; shift
  local envs=()
  while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  RC=0
  # </dev/null: 循环内调用时隔离 stdin，避免继承 here-string 的剩余行
  OUT="$( cd "$proj" && env "${envs[@]}" PATH="$WORK/bin:$PATH" bash "$GITOPS" "$@" 2>/dev/null </dev/null )" || RC=$?
}
pick_rows() { grep -E '^#[0-9]+' <<<"$OUT" || true; }

echo "=== (B1) issue list enumerates candidates with priority and status ==="
run "$WORK/ghproj" GH_ISSUES="$WORK/issues.tsv" GH_LABELDIR="$WORK/lab" -- issue list --state open
if [[ "$RC" -eq 0 ]]; then pass "issue list exits 0"; else fail "issue list rc=$RC"; fi
rows="$(pick_rows)"
if [[ "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" -eq 6 ]]; then
  pass "all 6 open candidates enumerated"
else
  fail "expected 6 rows, got: $(printf '%s\n' "$rows" | wc -l | tr -d ' ')"
fi
if grep -q 'retry' <<<"$rows"; then
  fail "retry leaked into issue list output (pick would need a second source, doc says list has no retry column)"
else
  pass "no retry column in issue list (C11 source separation holds)"
fi
# sorted by priority then number: p0 group (#32,#33,#34) precedes p1 (#31)
first_row="$(printf '%s\n' "$rows" | head -1)"
if grep -q '^#32 ' <<<"$first_row"; then
  pass "list ordering groups p0 ahead of p1/p2/#36"
else
  fail "unexpected first row: $first_row"
fi

echo "=== (B2) retry value is readable per issue, including the capped one ==="
for pair in "32 3" "34 2" "31 0" "33 0"; do
  set -- $pair
  run "$WORK/ghproj" GH_ISSUES="$WORK/issues.tsv" GH_LABELDIR="$WORK/lab" -- issue retry "$1" get
  got="$(grep -vE '^\[git-ops\]' <<<"$OUT" | tail -1)"
  if [[ "$got" == "$2" ]]; then pass "retry get $1 → $2"; else fail "retry get $1 → '$got', want '$2'"; fi
done

echo "=== (B3) status/priority of every candidate readable via issue get ==="
run "$WORK/ghproj" GH_ISSUES="$WORK/issues.tsv" GH_LABELDIR="$WORK/lab" -- issue get 33
if grep -qx 'riper-blocked' <<<"$OUT"; then
  pass "issue get exposes the blocked label (skip rule judgeable per issue)"
else
  fail "issue get 33 did not expose riper-blocked"
fi

echo "=== (B4) documented rules over read-only data select exactly one winner ==="
# model of the protocol: own the ordering (p0→p3→无优先级, then number ascending),
# skip riper-blocked / riper-retry-3 / riper-verified-open, take the first survivor.
run "$WORK/ghproj" GH_ISSUES="$WORK/issues.tsv" GH_LABELDIR="$WORK/lab" -- issue list --state open
eligible=""
while IFS= read -r line; do
  [[ "$line" == \#* ]] || continue
  num="${line#\#}"; num="${num%% *}"
  prio="$(printf '%s' "$line" | awk '{print $2}')"
  stat="$(printf '%s' "$line" | awk '{print $3}')"
  case "$prio" in p0) k=0 ;; p1) k=1 ;; p2) k=2 ;; p3) k=3 ;; *) k=4 ;; esac
  skip=0
  [[ "$stat" == "riper-blocked" || "$stat" == "riper-verified" ]] && skip=1
  run "$WORK/ghproj" GH_ISSUES="$WORK/issues.tsv" GH_LABELDIR="$WORK/lab" -- issue retry "$num" get
  [[ "$(grep -vE '^\[git-ops\]' <<<"$OUT" | tail -1)" == "3" ]] && skip=1
  [[ "$skip" -eq 0 ]] && eligible="${eligible}${k}	${num}
"
done <<< "$(pick_rows)"
won="$(printf '%s' "$eligible" | sort -t"$(printf '\t')" -k1,1n -k2,2n | head -1 | tr '\t' ':')"
winner_count="$(printf '%s' "$eligible" | grep -c . || true)"
if [[ "$won" == "0:34" ]]; then pass "pick resolves to #34 (p0, not blocked, retry=2)"; else fail "pick resolved to '$won', want '0:34'"; fi
if [[ "$won" == "4:36" ]]; then fail "(无) priority candidate outranked p0 — ordering not owned by the pick step"; fi
if [[ "$winner_count" -ge 2 ]]; then pass "eligibility kept other valid candidates ($winner_count: #31/#34/#36)"; else fail "expected ≥2 eligible, got $winner_count"; fi
for n in 32 33 35; do
  if printf '%s' "$eligible" | grep -q "	${n}$"; then
    fail "#${n} should have been skipped but was eligible"
  else
    pass "#${n} skipped by the documented rules"
  fi
done

echo "=== (B5) glab degradation: list hides labels, issue get restores them ==="
run "$WORK/glabproj" GLAB_ISSUES="$WORK/gissues.tsv" GLAB_LABELDIR="$WORK/glablab" -- issue list --state open
if grep -F '(无)' <<<"$OUT" | grep -q '^#41'; then
  pass "glab list shows (无) placeholders (pick would be blind without degradation path)"
else
  fail "expected (无) placeholder rows, got: $(pick_rows)"
fi
run "$WORK/glabproj" GLAB_ISSUES="$WORK/gissues.tsv" GLAB_LABELDIR="$WORK/glablab" -- issue get 41
if grep -q 'p0' <<<"$OUT" && grep -q 'riper-retry-3' <<<"$OUT"; then
  pass "degraded platform still yields real labels via issue get (C10 path works)"
else
  fail "issue get 41 missing real labels on glab path"
fi

echo "=== scope evidence: fix is committed, git-ops.sh untouched by #20 ==="
if git -C "$ROOT" diff HEAD --name-only -- scripts/git-ops.sh templates/ | grep -q .; then
  fail "git-ops.sh or templates/ changed (design §5 forbids it)"
else
  pass "scripts/git-ops.sh and templates/ untouched vs HEAD"
fi

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
