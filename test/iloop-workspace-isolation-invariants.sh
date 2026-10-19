#!/usr/bin/env bash
# Black-box contract checks for Issue #23 (per-Issue workspace isolation).
# Covers `workspace status|start|finish`, the guard parallel-pollution diagnostic
# and the optional `guard <role> <N>` issue-number check.
#
# Every worktree/branch scenario is built inside a throwaway fixture repo under
# $WORK (a mktemp dir removed by the EXIT trap). The real repository is only ever
# read from: no worktree, branch or file is created, modified or deleted in it.
# The fixture's `origin` is a local bare repo, so nothing here touches the network.
#
# Run from repository root: bash test/iloop-workspace-isolation-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
FAILS=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

# chk <cond-rc> <msg>: cond-rc 0 => pass
chk() { if [[ "$1" -eq 0 ]]; then pass "$2"; else fail "$2"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Real-repo state snapshots, to prove this test leaves no trace (step 10 AC8/AC9).
REAL_WT_BEFORE="$(git -C "$ROOT" worktree list | wc -l | tr -d ' ')"
REAL_STATUS_BEFORE="$(git -C "$ROOT" status --porcelain)"

RC=0; OUT=""
# run <cwd> <args...>: black-box invocation of the same entry point Agents use.
run() {
  local d="$1"; shift
  RC=0
  OUT="$( cd "$d" && bash "$GITOPS" "$@" 2>&1 )" || RC=$?
}

has()  { printf '%s' "$OUT" | grep -qF -- "$1"; }
hasE() { printf '%s' "$OUT" | grep -qE -- "$1"; }

#############################################################################
echo "=== fixture: local bare origin + primary worktree ahead of upstream ==="

# The fixture must contain scripts/git-ops.sh at origin/main so that worktrees
# created from the upstream baseline are realistic; we still invoke the real
# $GITOPS by absolute path, so the code under test is never the fixture copy.
git init -q --bare -b main "$WORK/bare.git"
git clone -q "$WORK/bare.git" "$WORK/seed" 2>/dev/null || true
(
  cd "$WORK/seed"
  git config user.email t@t.t; git config user.name t
  mkdir -p scripts docs/issues/1 test
  echo '#!/usr/bin/env bash' > scripts/git-ops.sh
  for f in docs/issues/1/spec.md docs/issues/1/plan.md test/foo.sh README.md; do echo x > "$f"; done
  git add -A
  git commit -qm "seed"
  git push -q origin main
)
git clone -q "$WORK/bare.git" "$WORK/repo" 2>/dev/null || true
REPO="$WORK/repo"
(
  cd "$REPO"
  git config user.email t@t.t; git config user.name t
  git remote set-head origin -a >/dev/null
  # A local-only commit makes `main` ahead of `origin/main`, which is what lets us
  # observe "baseline is the upstream, not the local branch" (C10).
  echo local-only >> README.md
  git commit -qam "local-only, never pushed"
)
PRIM="$(cd "$REPO" && pwd -P)"
WTROOT="$(dirname "$PRIM")/.iloop-worktrees/$(basename "$PRIM")"
ORIGIN_URL="$(git -C "$REPO" remote get-url origin)"

if [[ "$ORIGIN_URL" == /* && -d "$ORIGIN_URL" ]]; then
  pass "step10-AC10 fixture origin is a local path ($ORIGIN_URL), no network needed"
else
  fail "step10-AC10 fixture origin is not a local path: $ORIGIN_URL"
fi
if [[ "$(git -C "$REPO" rev-parse main)" != "$(git -C "$REPO" rev-parse origin/main)" ]]; then
  pass "fixture main is ahead of origin/main (C10 observable)"
else
  fail "fixture main is not ahead of origin/main; C10 would be unobservable"
fi

#############################################################################
echo "=== step 1: workspace status (AC2/3/4/5/6/7) ==="

S_BEFORE="$(cd "$REPO" && git status --porcelain)"
W_BEFORE="$(git -C "$REPO" worktree list)"
H_BEFORE="$(git -C "$REPO" rev-parse HEAD)"

run "$REPO" workspace status
chk "$RC" "step1-AC2 status in primary worktree exits 0 (rc=$RC)"
has "主工作树" && pass "step1-AC2 output names 主工作树" || fail "step1-AC2 output lacks 主工作树"
hasE "当前分支：main" && pass "step1-AC2 output reports the current branch" || fail "step1-AC2 output lacks the current branch"
hasE "未提交变更文件数：[0-9]+" && pass "step1-AC2 output reports a dirty-file count" || fail "step1-AC2 output lacks a dirty-file count"
has "分支非 riper/<N> 形态" && pass "step1-AC4 branch main reports 非 riper/<N> 形态 and still exits 0" \
  || fail "step1-AC4 branch main lacks the 非 riper/<N> 形态 note"

# step1-AC5: status is read-only (no side effects on index, worktrees or HEAD).
S_AFTER="$(cd "$REPO" && git status --porcelain)"
W_AFTER="$(git -C "$REPO" worktree list)"
H_AFTER="$(git -C "$REPO" rev-parse HEAD)"
if [[ "$S_BEFORE" == "$S_AFTER" && "$W_BEFORE" == "$W_AFTER" && "$H_BEFORE" == "$H_AFTER" ]]; then
  pass "step1-AC5 status left status/worktree-list/HEAD byte-identical"
else
  fail "step1-AC5 status mutated the repository"
fi

run "$REPO" workspace
[[ "$RC" -eq 1 ]] && has "Usage:" \
  && pass "step1-AC6 bare 'workspace' prints usage and exits 1" \
  || fail "step1-AC6 bare 'workspace' rc=$RC"
run "$REPO" workspace bogus
[[ "$RC" -eq 1 ]] && has "Usage:" \
  && pass "step1-AC7 'workspace bogus' prints usage and exits 1" \
  || fail "step1-AC7 'workspace bogus' rc=$RC"

#############################################################################
echo "=== step 2: workspace start in the primary worktree (AC1/3/4/5/6/8/9/10/11) ==="

run "$REPO" workspace start 101
chk "$RC" "step2-AC1 'workspace start 101' exits 0 (rc=$RC)"
WT101="$WTROOT/101"
GOT101="$(cd "$WT101" 2>/dev/null && pwd -P || echo MISSING)"
[[ "$GOT101" == "$WT101" && -d "$WT101" ]] \
  && pass "step2-AC6 worktree path is $WT101 (outside the repo, under ../.iloop-worktrees/<repo>/101)" \
  || fail "step2-AC6 worktree path is $GOT101, want $WT101"
case "$WT101" in
  "$PRIM"/*) fail "step2-AC6 worktree path is inside the primary worktree" ;;
  *)         pass "step2-AC6 worktree path is not inside the primary worktree" ;;
esac
[[ "$(git -C "$WT101" symbolic-ref --short HEAD)" == "riper/101" ]] \
  && pass "step2-AC3 HEAD branch in the new worktree is riper/101" \
  || fail "step2-AC3 HEAD branch is $(git -C "$WT101" symbolic-ref --short HEAD 2>&1)"
if git -C "$WT101" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  fail "step2-AC4 riper/101 has an upstream configured (--no-track not honoured)"
else
  pass "step2-AC4 riper/101 has no upstream (--no-track honoured)"
fi
WT101_HEAD="$(git -C "$WT101" rev-parse HEAD)"
[[ "$WT101_HEAD" == "$(git -C "$REPO" rev-parse origin/main)" ]] \
  && pass "step2-AC5 worktree HEAD equals origin/main" \
  || fail "step2-AC5 worktree HEAD $WT101_HEAD != origin/main $(git -C "$REPO" rev-parse origin/main)"
[[ "$WT101_HEAD" != "$(git -C "$REPO" rev-parse main)" ]] \
  && pass "step2-AC5 worktree HEAD differs from the ahead-of-upstream local main (baseline is upstream)" \
  || fail "step2-AC5 worktree HEAD equals local main; baseline was not the upstream"
printf '%s' "$OUT" | grep -qE '路径：/' \
  && pass "step2-AC1 start output carries an absolute worktree path" \
  || fail "step2-AC1 start output lacks an absolute path"

WTCOUNT_BEFORE="$(git -C "$REPO" worktree list | wc -l | tr -d ' ')"
SHA_BEFORE="$(git -C "$REPO" rev-parse riper/101)"
run "$REPO" workspace start 101
[[ "$RC" -ne 0 ]] && pass "step2-AC8 repeated start 101 exits non-zero (rc=$RC)" \
  || fail "step2-AC8 repeated start 101 exited 0"
[[ "$(git -C "$REPO" rev-parse riper/101)" == "$SHA_BEFORE" ]] \
  && pass "step2-AC8 riper/101 still points at $SHA_BEFORE (nothing destroyed)" \
  || fail "step2-AC8 riper/101 moved after the refused repeat"
[[ "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" == "$WTCOUNT_BEFORE" ]] \
  && pass "step2-AC8 worktree count unchanged by the refused repeat" \
  || fail "step2-AC8 worktree count changed by the refused repeat"

for n in 0 abc -1 1.5; do
  run "$REPO" workspace start "$n"
  [[ "$RC" -ne 0 ]] && pass "step2-AC9 'workspace start $n' exits non-zero" \
    || fail "step2-AC9 'workspace start $n' exited 0"
done

# step2-AC10: no origin at all -> must refuse, hint at --base, create nothing.
git init -q -b main "$WORK/noorigin"
(
  cd "$WORK/noorigin"
  git config user.email t@t.t; git config user.name t
  echo x > f.txt; git add -A; git commit -qm init
)
NO_WT_BEFORE="$(git -C "$WORK/noorigin" worktree list | wc -l | tr -d ' ')"
run "$WORK/noorigin" workspace start 102
[[ "$RC" -ne 0 ]] && pass "step2-AC10 start without an origin exits non-zero" \
  || fail "step2-AC10 start without an origin exited 0"
has "--base" && pass "step2-AC10 refusal hints at --base <ref>" \
  || fail "step2-AC10 refusal does not mention --base"
if git -C "$WORK/noorigin" show-ref --verify -q refs/heads/riper/102; then
  fail "step2-AC10 riper/102 was created despite the refusal"
else
  pass "step2-AC10 no branch created"
fi
[[ "$(git -C "$WORK/noorigin" worktree list | wc -l | tr -d ' ')" == "$NO_WT_BEFORE" ]] \
  && pass "step2-AC10 no worktree created" \
  || fail "step2-AC10 worktree count changed"

# step2-AC11: target path already exists -> refuse without touching it.
mkdir -p "$WTROOT/103"
echo precious > "$WTROOT/103/PRECIOUS.txt"
run "$REPO" workspace start 103
[[ "$RC" -ne 0 ]] && pass "step2-AC11 start onto an existing directory exits non-zero" \
  || fail "step2-AC11 start onto an existing directory exited 0"
[[ -f "$WTROOT/103/PRECIOUS.txt" ]] && pass "step2-AC11 pre-existing content left intact" \
  || fail "step2-AC11 pre-existing content was overwritten or removed"
if git -C "$REPO" show-ref --verify -q refs/heads/riper/103; then
  fail "step2-AC11 riper/103 was created despite the refusal"
else
  pass "step2-AC11 no branch created"
fi
rm -rf "$WTROOT/103"

#############################################################################
echo "=== step 3: normalization inside a linked worktree (AC1/2/4/5/6) ==="

git -C "$REPO" worktree add -q --detach "$WORK/wt-det" origin/main
(
  cd "$WORK/wt-det"
  git config user.email t@t.t; git config user.name t
  echo host > host.txt; git add host.txt
  git commit -qm "host-made commit while detached"
)
DET_SHA="$(git -C "$WORK/wt-det" rev-parse HEAD)"
WT_COUNT_BEFORE="$(git -C "$REPO" worktree list | wc -l | tr -d ' ')"

# step1-AC3: inside a linked worktree, status must say so and still point at the
# real primary root (not at cwd, and not at cwd's parent).
DET_PHYS="$(cd "$WORK/wt-det" && pwd -P)"
run "$WORK/wt-det" workspace status
chk "$RC" "step1-AC3 status inside a linked worktree exits 0 (rc=$RC)"
has "linked worktree" && pass "step1-AC3 output says linked worktree" \
  || fail "step1-AC3 output does not say linked worktree"
REPORTED_PRIMARY="$(printf '%s\n' "$OUT" | sed -n 's/^.*主工作树：//p' | head -1)"
[[ "$REPORTED_PRIMARY" == "$PRIM" ]] \
  && pass "step1-AC3 reported primary root is the fixture repo ($PRIM)" \
  || fail "step1-AC3 reported primary root '$REPORTED_PRIMARY' != '$PRIM'"
[[ "$REPORTED_PRIMARY" != "$DET_PHYS" ]] \
  && pass "step1-AC3 reported primary root is not the current directory" \
  || fail "step1-AC3 reported primary root equals the current directory"
[[ "$REPORTED_PRIMARY" != "$(dirname "$DET_PHYS")" ]] \
  && pass "step1-AC3 reported primary root is not the current directory's parent" \
  || fail "step1-AC3 reported primary root equals cwd's parent"

run "$WORK/wt-det" workspace start 111
chk "$RC" "step3-AC1 start inside a detached linked worktree exits 0 (rc=$RC)"
[[ "$(git -C "$WORK/wt-det" rev-parse --abbrev-ref HEAD)" == "riper/111" ]] \
  && pass "step3-AC1 HEAD branch became riper/111" \
  || fail "step3-AC1 HEAD branch is $(git -C "$WORK/wt-det" rev-parse --abbrev-ref HEAD 2>&1)"
# step1-AC4 other half: a riper/<N> branch must be parsed back into its Issue number.
run "$WORK/wt-det" workspace status
[[ "$RC" -eq 0 ]] && has "归属 Issue：#111" \
  && pass "step1-AC4 branch riper/111 is parsed into 归属 Issue：#111" \
  || fail "step1-AC4 branch riper/111 was not parsed into an Issue number (rc=$RC)"
if git -C "$WORK/wt-det" rev-list riper/111 | grep -qF "$DET_SHA"; then
  pass "step3-AC2 the pre-existing detached commit $DET_SHA is still reachable"
else
  fail "step3-AC2 detached commit $DET_SHA became unreachable (work lost)"
fi
[[ -f "$WORK/wt-det/host.txt" ]] && pass "step3-AC2 host working file survived" \
  || fail "step3-AC2 host working file disappeared"
[[ "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" == "$WT_COUNT_BEFORE" ]] \
  && pass "step3-AC4 no nested worktree was created (count $WT_COUNT_BEFORE)" \
  || fail "step3-AC4 worktree count changed: nesting happened"

HEAD_BEFORE="$(git -C "$WORK/wt-det" rev-parse HEAD)"
run "$WORK/wt-det" workspace start 111
[[ "$RC" -eq 0 ]] && pass "step3-AC5 re-running start 111 is idempotent (exit 0)" \
  || fail "step3-AC5 idempotent re-run exited $RC"
[[ "$(git -C "$WORK/wt-det" rev-parse HEAD)" == "$HEAD_BEFORE" ]] \
  && pass "step3-AC5 HEAD unchanged by the idempotent re-run" \
  || fail "step3-AC5 HEAD moved on the idempotent re-run"
[[ "$(git -C "$REPO" worktree list | wc -l | tr -d ' ')" == "$WT_COUNT_BEFORE" ]] \
  && pass "step3-AC5 worktree count unchanged by the idempotent re-run" \
  || fail "step3-AC5 worktree count changed on the idempotent re-run"

run "$WORK/wt-det" workspace start 112
[[ "$RC" -ne 0 ]] && pass "step3-AC6 start 112 inside riper/111 exits non-zero" \
  || fail "step3-AC6 start 112 inside riper/111 exited 0"
has "111" && pass "step3-AC6 refusal names the owning Issue 111" \
  || fail "step3-AC6 refusal does not name the owning Issue"
[[ "$(git -C "$WORK/wt-det" rev-parse --abbrev-ref HEAD)" == "riper/111" ]] \
  && pass "step3-AC6 branch is still riper/111 (not reassigned)" \
  || fail "step3-AC6 branch changed to $(git -C "$WORK/wt-det" rev-parse --abbrev-ref HEAD)"

#############################################################################
echo "=== step 4: workspace finish (AC1/2/3/4/5) ==="

# AC2: dirty worktree must be refused, leaving both directory and branch in place.
run "$REPO" workspace start 121
WT121="$WTROOT/121"
echo dirt > "$WT121/dirty.txt"
run "$REPO" workspace finish 121
[[ "$RC" -ne 0 ]] && pass "step4-AC2 finish on a dirty worktree exits non-zero" \
  || fail "step4-AC2 finish on a dirty worktree exited 0"
has "dirty.txt" && pass "step4-AC2 refusal names the dirty file" \
  || fail "step4-AC2 refusal does not name the dirty file"
[[ -d "$WT121" ]] && pass "step4-AC2 worktree directory kept" || fail "step4-AC2 worktree directory removed"
git -C "$REPO" show-ref --verify -q refs/heads/riper/121 \
  && pass "step4-AC2 branch kept" || fail "step4-AC2 branch removed"
rm -f "$WT121/dirty.txt"

# AC3: clean but unmerged must be refused, pointing at integration.
run "$REPO" workspace start 122
WT122="$WTROOT/122"
(
  cd "$WT122"
  git config user.email t@t.t; git config user.name t
  echo w > w.txt; git add w.txt; git commit -qm "unmerged work"
)
run "$REPO" workspace finish 122
[[ "$RC" -ne 0 ]] && pass "step4-AC3 finish on an unmerged branch exits non-zero" \
  || fail "step4-AC3 finish on an unmerged branch exited 0"
if has "#25" || has "集成"; then
  pass "step4-AC3 refusal points at integration (#25)"
else
  fail "step4-AC3 refusal does not mention integration or #25"
fi
[[ -d "$WT122" ]] && pass "step4-AC3 worktree kept" || fail "step4-AC3 worktree removed"
git -C "$REPO" show-ref --verify -q refs/heads/riper/122 \
  && pass "step4-AC3 branch kept" || fail "step4-AC3 branch removed"

# AC4: unknown issue number must fail loudly, not silently succeed.
run "$REPO" workspace finish 999
[[ "$RC" -ne 0 ]] && pass "step4-AC4 finish on a nonexistent riper/999 exits non-zero" \
  || fail "step4-AC4 finish on a nonexistent branch exited 0"
has "riper/999" && pass "step4-AC4 message names the missing branch" \
  || fail "step4-AC4 message does not name the missing branch"

# AC1: merged and clean -> removed worktree, removed branch.
run "$REPO" workspace start 123
WT123="$WTROOT/123"
(
  cd "$WT123"
  git config user.email t@t.t; git config user.name t
  echo m > m.txt; git add m.txt; git commit -qm "merged work"
)
(
  cd "$REPO"
  git merge -q --no-edit riper/123 >/dev/null
  git push -q origin main
)
git -C "$REPO" merge-base --is-ancestor riper/123 origin/main \
  && pass "step4-AC1 precondition: riper/123 is merged into origin/main" \
  || fail "step4-AC1 precondition failed: riper/123 is not merged"
run "$REPO" workspace finish 123
chk "$RC" "step4-AC1 finish on a merged clean worktree exits 0 (rc=$RC)"
[[ ! -d "$WT123" ]] && pass "step4-AC1 worktree directory removed" || fail "step4-AC1 worktree directory still there"
if git -C "$REPO" worktree list | grep -qF "$WT123"; then
  fail "step4-AC1 worktree still listed"
else
  pass "step4-AC1 worktree no longer listed"
fi
[[ -z "$(git -C "$REPO" branch --list 'riper/123')" ]] \
  && pass "step4-AC1 branch riper/123 deleted" || fail "step4-AC1 branch riper/123 survived"

# AC5: the empty parent directory is kept, never recursively deleted.
run "$REPO" workspace finish 101
chk "$RC" "step4-AC5 finishing the merged, clean riper/101 exits 0 (rc=$RC)"
run "$REPO" workspace finish 121
chk "$RC" "step4-AC5 finishing the now-clean riper/121 exits 0 (rc=$RC)"
if [[ -d "$WTROOT" ]]; then
  pass "step4-AC5 parent directory $WTROOT still exists"
  LEFTOVER="$(ls -A "$WTROOT" 2>/dev/null | tr '\n' ' ')"
  # riper/122 is deliberately still unmerged, so it must still be there.
  case " $LEFTOVER " in
    *" 122 "*) pass "step4-AC5 the refused riper/122 worktree is still in place" ;;
    *)         fail "step4-AC5 riper/122 worktree vanished; leftover='$LEFTOVER'" ;;
  esac
else
  fail "step4-AC5 parent directory $WTROOT was deleted"
fi

#############################################################################
echo "=== issue #30: workspace finish called from inside the target worktree ==="

# git does not refuse to remove the worktree you are standing in: it removes it, and
# the next git call then dies on a vanished cwd. Every finish call above runs from
# $REPO, which is exactly why that shipped unnoticed. These cases call it from inside.

# A freshly started worktree sits at origin/main with no commits of its own, so it is
# trivially "merged" and clean -- no merge/push dance needed to reach the removal path.
run "$REPO" workspace start 141
WT141="$WTROOT/141"
chk "$RC" "issue30 precondition: start 141 exits 0 (rc=$RC)"

run "$WT141" workspace finish 141
chk "$RC" "issue30-AC1 finish from inside the target worktree exits 0 (rc=$RC)"
[[ ! -d "$WT141" ]] && pass "issue30-AC1 worktree directory removed" \
  || fail "issue30-AC1 worktree directory still there"
if git -C "$REPO" worktree list | grep -qF "$WT141"; then
  fail "issue30-AC1 worktree still listed"
else
  pass "issue30-AC1 worktree no longer listed"
fi
[[ -z "$(git -C "$REPO" branch --list 'riper/141')" ]] \
  && pass "issue30-AC1 branch riper/141 deleted (not left half-finished)" \
  || fail "issue30-AC1 branch riper/141 survived -- finish stopped halfway"
[[ -d "$WTROOT" ]] && pass "issue30-AC1 parent directory kept" \
  || fail "issue30-AC1 parent directory was deleted"
has "cd $PRIM" && pass "issue30-AC4 the stranded-shell hint names the primary worktree path" \
  || fail "issue30-AC4 no cd hint after removing the caller's own directory"

# Same, but invoked from a subdirectory of the worktree.
run "$REPO" workspace start 142
WT142="$WTROOT/142"
mkdir -p "$WT142/sub"
run "$WT142/sub" workspace finish 142
chk "$RC" "issue30-AC2 finish from a subdirectory of the worktree exits 0 (rc=$RC)"
[[ ! -d "$WT142" ]] && pass "issue30-AC2 worktree directory removed" \
  || fail "issue30-AC2 worktree directory still there"
[[ -z "$(git -C "$REPO" branch --list 'riper/142')" ]] \
  && pass "issue30-AC2 branch riper/142 deleted" || fail "issue30-AC2 branch riper/142 survived"
has "cd $PRIM" && pass "issue30-AC2 subdirectory caller also gets the cd hint" \
  || fail "issue30-AC2 no cd hint for a subdirectory caller"

# From the primary worktree the hint must stay quiet -- otherwise it is pure noise.
run "$REPO" workspace start 143
run "$REPO" workspace finish 143
chk "$RC" "issue30-AC3 finish from the primary worktree still exits 0 (rc=$RC)"
[[ ! -d "$WTROOT/143" ]] && pass "issue30-AC3 worktree directory removed" \
  || fail "issue30-AC3 worktree directory still there"
if has "cd $PRIM"; then
  fail "issue30-AC3 the stranded-shell hint fired for a primary-worktree caller"
else
  pass "issue30-AC3 no cd hint when the caller was never inside the removed directory"
fi

#############################################################################
echo "=== step 5: guard parallel-pollution diagnostic (AC1/2/4) ==="

echo x > "$REPO/scripts/violation.tmp"
run "$REPO" guard planner
[[ "$RC" -eq 1 ]] && pass "step5-AC1 guard planner on a violating change still exits 1" \
  || fail "step5-AC1 guard planner rc=$RC, want 1"
if has "主工作树" && has "workspace start"; then
  pass "step5-AC1 diagnostic names 主工作树 and points at workspace start"
else
  fail "step5-AC1 diagnostic missing (主工作树 / workspace start)"
fi
rm -f "$REPO/scripts/violation.tmp"

echo x > "$WORK/wt-det/scripts/violation.tmp"
run "$WORK/wt-det" guard planner
[[ "$RC" -eq 1 ]] && pass "step5-AC2 guard planner in a linked worktree still exits 1" \
  || fail "step5-AC2 guard planner in linked worktree rc=$RC, want 1"
if has "workspace start"; then
  fail "step5-AC2 the parallel-pollution diagnostic leaked into a linked worktree"
else
  pass "step5-AC2 no parallel-pollution diagnostic inside a linked worktree"
fi
rm -f "$WORK/wt-det/scripts/violation.tmp"

run "$REPO" guard planner
[[ "$RC" -eq 0 ]] && pass "step5-AC4 guard planner on a clean tree exits 0" \
  || fail "step5-AC4 guard planner on a clean tree rc=$RC"
has "无待检变更" && pass "step5-AC4 clean-tree wording preserved" \
  || fail "step5-AC4 clean-tree wording changed"
if has "workspace start"; then
  fail "step5-AC4 diagnostic printed on a clean tree (must stay silent)"
else
  pass "step5-AC4 no diagnostic on a clean tree"
fi

#############################################################################
echo "=== step 6: guard <role> [N] issue-number check (AC2/3/4/5/7) ==="

run "$WORK/wt-det" guard developer 111
chk "$RC" "step6-AC2 guard developer 111 on riper/111 exits 0 (rc=$RC)"
run "$WORK/wt-det" guard developer 112
[[ "$RC" -eq 1 ]] && pass "step6-AC3 guard developer 112 on riper/111 exits 1" \
  || fail "step6-AC3 guard developer 112 on riper/111 rc=$RC"
has "111" && pass "step6-AC3 message names the owning Issue 111" \
  || fail "step6-AC3 message does not name the owning Issue"
run "$REPO" guard developer 111
chk "$RC" "step6-AC4 guard developer 111 on main warns but exits 0 (rc=$RC)"
run "$REPO" guard developer abc
[[ "$RC" -eq 1 ]] && pass "step6-AC5 guard developer abc exits 1" || fail "step6-AC5 guard developer abc rc=$RC"
run "$REPO" guard developer 1 2
[[ "$RC" -eq 1 ]] && has "Usage:" \
  && pass "step6-AC7 guard developer 1 2 prints usage and exits 1" \
  || fail "step6-AC7 guard developer 1 2 rc=$RC"

#############################################################################
echo "=== step 3 AC7: a linked worktree on a foreign branch is never switched ==="

# `main` can only be checked out in one worktree, so the primary vacates it first.
git -C "$REPO" switch -q -c qa-dev-branch
git -C "$REPO" worktree add -q "$WORK/wt-main" main
run "$WORK/wt-main" workspace start 131
[[ "$RC" -ne 0 ]] && pass "step3-AC7 start inside a linked worktree on main exits non-zero" \
  || fail "step3-AC7 start inside a linked worktree on main exited 0"
[[ "$(git -C "$WORK/wt-main" rev-parse --abbrev-ref HEAD)" == "main" ]] \
  && pass "step3-AC7 branch is still main (no git switch happened)" \
  || fail "step3-AC7 branch changed to $(git -C "$WORK/wt-main" rev-parse --abbrev-ref HEAD)"

#############################################################################
echo "=== step 10 AC8/AC9: no residue in the real repository ==="

REAL_WT_AFTER="$(git -C "$ROOT" worktree list | wc -l | tr -d ' ')"
REAL_STATUS_AFTER="$(git -C "$ROOT" status --porcelain)"
[[ "$REAL_WT_BEFORE" == "$REAL_WT_AFTER" ]] \
  && pass "step10-AC8 real repo worktree count unchanged ($REAL_WT_BEFORE)" \
  || fail "step10-AC8 real repo worktree count $REAL_WT_BEFORE -> $REAL_WT_AFTER"
[[ "$REAL_STATUS_BEFORE" == "$REAL_STATUS_AFTER" ]] \
  && pass "step10-AC9 real repo status --porcelain unchanged" \
  || { fail "step10-AC9 real repo was modified"; echo "  before=[$REAL_STATUS_BEFORE]"; echo "  after=[$REAL_STATUS_AFTER]"; }

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
