#!/usr/bin/env bash
# Black-box contract checks for Issue #15 (git-ops.sh tea/glab CLI compatibility).
# Stubs tea 0.15.x and glab (1.118 "--name required" + an older positional-only
# variant), drives git-ops.sh inside throwaway repos routed by HOSTNAME HEURISTIC
# (*gitea* -> tea, gitlab.com -> glab) so detect_platform never touches the
# unfixed registry path (line 125, out of scope per spec A2).
#
# Verifies the three frozen acceptance criteria from plan.md:
#   step 1: tea check_auth never false-negatives via grep -q SIGPIPE + pipefail
#   step 2: glab label create/edit use --name first, positional fallback (old glab)
#   step 3: tea labels init is idempotent — no `labels create` for existing labels
# Run from repository root: bash test/iloop-cli-compat-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
FAILS=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# stub: tea 0.15.x
#   login list  -> prints an instance URL (contains http) + padding >64KB so a
#                  `grep -q` consumer would early-exit and SIGPIPE the writer.
#                  TEA_NO_LOGIN=1 prints nothing (unauthorized control).
#   labels list -> Gitea table; the label name sits at the field the production
#                  awk reads (-F'│', $4). State-backed so create persists.
#   labels create -> ALWAYS succeeds (Gitea does not dedupe non-scoped names).
# ---------------------------------------------------------------------------
mkdir -p "$WORK/teabin"
cat > "$WORK/teabin/tea" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "\${STUB_LOG:-/dev/null}"
if [[ "\${1:-} \${2:-}" == "login list" ]]; then
  if [[ "\${TEA_NO_LOGIN:-0}" == "1" ]]; then exit 0; fi
  echo "https://gitea.example.com  gitea  someuser  <token>"
  # >64KB of padding so a 'grep -q' consumer that exits after the first match
  # closes the pipe while this writer is still blocked -> SIGPIPE (141). The
  # bare 'exit' propagates that status (real tea dies the same way); the fixed
  # 'grep -i ... >/dev/null' reads it all, so the writer completes with 0.
  seq 1 20000 | sed 's/^/padding-row-/'
  exit
fi
if [[ "\${1:-} \${2:-}" == "labels list" ]]; then
  echo "│ ID │ Color │ Name │ Description │"
  if [[ -f "\${TEA_STATE:-/dev/null}" ]]; then
    i=0
    while IFS= read -r n; do
      [[ -z "\$n" ]] && continue
      i=\$((i+1))
      printf '│ %d │ c0ffee │ %s │ stub │\n' "\$i" "\$n"
    done < "\${TEA_STATE:-/dev/null}"
  fi
  exit 0
fi
if [[ "\${1:-} \${2:-}" == "labels create" ]]; then
  prev=""; nm=""
  for a in "\$@"; do [[ "\$prev" == "--name" ]] && nm="\$a"; prev="\$a"; done
  [[ -n "\$nm" ]] && echo "\$nm" >> "\${TEA_STATE:-/dev/null}"
  exit 0
fi
exit 0
STUB
chmod +x "$WORK/teabin/tea"

# ---------------------------------------------------------------------------
# stub: glab.  GLAB_MODE=new  -> 1.118: requires --name, rejects positional.
#              GLAB_MODE=old  -> legacy: rejects --name, accepts positional.
#   create: succeeds only if the label is new (else exit 1, "already exists").
#   edit:   succeeds only if the label exists.
# ---------------------------------------------------------------------------
mkdir -p "$WORK/glabbin"
cat > "$WORK/glabbin/glab" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "\${STUB_LOG:-/dev/null}"
if [[ "\${1:-}" == "auth" ]]; then exit 0; fi
if [[ "\${1:-}" != "label" ]]; then exit 0; fi
sub="\${2:-}"
prev=""; nm=""; has_name=0
for a in "\$@"; do [[ "\$prev" == "--name" ]] && { nm="\$a"; has_name=1; }; prev="\$a"; done
pos="\${3:-}"
case "\${GLAB_MODE:-new}" in
  new) [[ \$has_name -eq 0 ]] && { echo "The --name flag is required" >&2; exit 1; } ;;
  old) [[ \$has_name -eq 1 ]] && { echo "unknown flag: --name" >&2; exit 1; } ;;
esac
eff="\$nm"; [[ \$has_name -eq 0 ]] && eff="\$pos"
st="\${GLAB_STATE:-/dev/null}"
if [[ "\$sub" == "create" ]]; then
  if grep -Fxq -- "\$eff" "\$st" 2>/dev/null; then echo "label already exists" >&2; exit 1; fi
  echo "\$eff" >> "\$st"; exit 0
elif [[ "\$sub" == "edit" ]]; then
  if grep -Fxq -- "\$eff" "\$st" 2>/dev/null; then exit 0; fi
  echo "label not found" >&2; exit 1
fi
exit 0
STUB
chmod +x "$WORK/glabbin/glab"

# make_repo <name> <origin-url>
make_repo() {
  local d="$WORK/$1"
  mkdir -p "$d"; git -C "$d" init -q; git -C "$d" remote add origin "$2"
  echo "$d"
}
GITEA_REPO="$(make_repo gitea https://gitea.example.com/o/r.git)"
GLAB_REPO="$(make_repo glab https://gitlab.com/o/r.git)"

# probe <repo> <binpath> <args...>: run git-ops.sh with stub on PATH.
# Sets RC / OUT / ERR / LOG (path to recorded CLI invocations).
RC=0; OUT=""; ERR=""; LOG=""
probe() {
  local repo="$1" bin="$2"; shift 2
  LOG="$WORK/calls.log"; : > "$LOG"
  local errfile="$WORK/stderr"; : > "$errfile"
  RC=0
  OUT="$( cd "$repo" && STUB_LOG="$LOG" PATH="$bin:$PATH" bash "$GITOPS" "$@" 2>"$errfile" )" || RC=$?
  ERR="$(cat "$errfile" 2>/dev/null || true)"
}

#############################################################################
echo "=== step 1: tea check_auth — no SIGPIPE false-negative under pipefail ==="

# 1a: behavioral — doctor on gitea fixture must pass 20/20 (random 141 == bug).
ok=0
for i in $(seq 1 20); do
  probe "$GITEA_REPO" "$WORK/teabin" doctor
  [[ "$RC" -eq 0 ]] && ok=$((ok + 1))
done
if [[ "$ok" -eq 20 ]]; then
  pass "tea doctor authorized 20/20 runs (no random SIGPIPE 141)"
else
  fail "tea doctor authorized only ${ok}/20 runs (SIGPIPE false-negative present)"
fi

# 1b: evidence — the OLD `grep -q` form against the same stub is unreliable,
#     proving the fix is load-bearing (informational, not a gate).
oldfail=0
for i in $(seq 1 20); do
  if ! ( set -o pipefail
         STUB_LOG=/dev/null PATH="$WORK/teabin:$PATH" \
           tea login list 2>/dev/null | grep -qi 'http' ); then
    oldfail=$((oldfail + 1))
  fi
done
echo "  evidence: legacy 'grep -qi' form failed ${oldfail}/20 vs fixed form 0/20"

# 1c: negative control — no login listed => unauthorized (rc != 0), not a false pass.
RC=0
OUT="$( cd "$GITEA_REPO" && TEA_NO_LOGIN=1 STUB_LOG=/dev/null PATH="$WORK/teabin:$PATH" bash "$GITOPS" doctor 2>/dev/null )" || RC=$?
if [[ "$RC" -ne 0 ]]; then pass "tea doctor exits non-zero when no login is listed (rc=$RC)"; else fail "tea doctor wrongly authorized with empty login list"; fi

# 1d: structural — production tea auth pipeline no longer uses grep -q.
if grep -nE "tea login list 2>/dev/null \| grep -[A-Za-z]*q" "$GITOPS" | grep -v 'grep -Fq -- "\${host}"' >/dev/null 2>&1; then
  fail "a tea 'login list | grep -q' auth pipeline still exists"
  grep -nE "tea login list .*grep -[A-Za-z]*q" "$GITOPS"
else
  pass "no 'grep -q' left in the tea check_auth pipeline"
fi
if grep -q "tea login list 2>/dev/null | grep -i 'http' >/dev/null" "$GITOPS"; then
  pass "check_auth tea branch reads all stdin (grep -i ... >/dev/null)"
else
  fail "check_auth tea branch not using the read-all form"
fi

#############################################################################
echo "=== step 2: glab label create/edit — --name first, positional fallback ==="

# 2a: new glab (1.118, requires --name): first init creates all 14, no FAILED.
: > "$WORK/glab_new.state"
GLAB_MODE=new; export GLAB_MODE
GLAB_STATE="$WORK/glab_new.state"; export GLAB_STATE
probe "$GLAB_REPO" "$WORK/glabbin" labels init
if [[ "$RC" -eq 0 ]]; then pass "new-glab labels init exits 0"; else fail "new-glab labels init rc=$RC (want 0); err=$ERR"; fi
if printf '%s' "$OUT" | grep -q 'FAILED'; then fail "new-glab labels init reported FAILED"; printf '%s\n' "$OUT" | grep FAILED; else pass "new-glab labels init: no FAILED"; fi
if printf '%s' "$OUT" | grep -qE 'created|updated'; then pass "new-glab labels init reported created/updated"; else fail "new-glab labels init produced no created/updated lines"; fi
if grep -qE 'label create --name ' "$LOG"; then pass "new-glab used 'label create --name'"; else fail "new-glab did not use 'label create --name'"; LOGCAT="$(cat "$LOG")"; echo "  log: $LOGCAT"; fi
if grep -qE 'label create [^-]' "$LOG"; then fail "new-glab still issued a positional 'label create' (should require --name)"; else pass "new-glab issued no positional-only create as primary"; fi

# 2b: new glab second run -> create fails (exists), edit --name path used => updated.
: > "$LOG"
probe "$GLAB_REPO" "$WORK/glabbin" labels init
if [[ "$RC" -eq 0 ]]; then pass "new-glab second labels init exits 0 (idempotent)"; else fail "new-glab second labels init rc=$RC"; fi
if printf '%s' "$OUT" | grep -q 'FAILED'; then fail "new-glab second init reported FAILED"; else pass "new-glab second init: no FAILED"; fi
if grep -qE 'label edit --name ' "$LOG"; then pass "new-glab fallback used 'label edit --name' on existing labels"; else fail "new-glab did not reach 'label edit --name'"; fi

# 2c: old glab (positional-only): --name rejected, positional fallback works.
: > "$WORK/glab_old.state"
GLAB_MODE=old; export GLAB_MODE
GLAB_STATE="$WORK/glab_old.state"; export GLAB_STATE
probe "$GLAB_REPO" "$WORK/glabbin" labels init
if [[ "$RC" -eq 0 ]]; then pass "old-glab labels init exits 0 (backward compatible)"; else fail "old-glab labels init rc=$RC; err=$ERR"; fi
if printf '%s' "$OUT" | grep -q 'FAILED'; then fail "old-glab labels init reported FAILED"; else pass "old-glab labels init: no FAILED"; fi
if grep -qE 'label create [^-]' "$LOG"; then pass "old-glab used positional 'label create' fallback"; else fail "old-glab did not fall back to positional create"; fi
unset GLAB_MODE GLAB_STATE

#############################################################################
echo "=== step 3: tea labels init — idempotent, no duplicate creates ==="

: > "$WORK/tea.state"
TEA_STATE="$WORK/tea.state"; export TEA_STATE

probe "$GITEA_REPO" "$WORK/teabin" labels init
if [[ "$RC" -eq 0 ]]; then pass "tea first labels init exits 0"; else fail "tea first labels init rc=$RC; err=$ERR"; fi
first_creates="$(grep -c 'labels create' "$LOG" || true)"
if [[ "$first_creates" -eq 14 ]]; then pass "tea first init created 14 labels"; else fail "tea first init created ${first_creates} labels (want 14)"; fi

: > "$LOG"
probe "$GITEA_REPO" "$WORK/teabin" labels init
if [[ "$RC" -eq 0 ]]; then pass "tea second labels init exits 0"; else fail "tea second labels init rc=$RC; err=$ERR"; fi
second_creates="$(grep -c 'labels create' "$LOG" || true)"
if [[ "$second_creates" -eq 0 ]]; then pass "tea second init issued 0 'labels create' (idempotent)"; else fail "tea second init issued ${second_creates} 'labels create' (duplicates!)"; fi
if printf '%s' "$OUT" | grep -q 'FAILED'; then fail "tea second init reported FAILED"; else pass "tea second init: no FAILED"; fi

dup="$(sort "$WORK/tea.state" | uniq -d | tr '\n' ' ')"
if [[ -z "$dup" ]]; then pass "tea label state has no duplicate names after two inits"; else fail "duplicate tea labels: $dup"; fi
state_n="$(grep -c . "$WORK/tea.state" || true)"
if [[ "$state_n" -eq 14 ]]; then pass "tea state holds exactly 14 labels"; else fail "tea state holds ${state_n} labels (want 14)"; fi
unset TEA_STATE

#############################################################################
echo "=== scope & hygiene ==="

# Out-of-scope guard: detect_platform tea registry path (line 125) must be UNCHANGED.
if grep -q 'tea login list 2>/dev/null | grep -Fq -- "${host}"' "$GITOPS"; then
  pass "detect_platform registry probe (spec A2) left untouched — no scope creep"
else
  fail "detect_platform line 125 was modified (out of #15 scope)"
fi

# Syntax + committed.
if bash -n "$GITOPS"; then pass "bash -n scripts/git-ops.sh OK"; else fail "bash -n failed"; fi
if git -C "$ROOT" diff HEAD -- scripts/git-ops.sh | grep -q .; then
  fail "scripts/git-ops.sh has uncommitted diff"
else
  pass "git-ops.sh clean vs HEAD (fix committed)"
fi

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
