#!/usr/bin/env bash
# Black-box contract checks for Issue #1 (git-ops.sh enhancement, re-baselined
# plan revision #2). Covers the four delivered capabilities + the cross-family
# and Bash-3.2 invariants from plan step 20:
#   (a) bash -n syntax
#   (b) permission-matrix regression, now including the retry family
#   (c) three-platform routing for: issue list / issue retry / guard / doctor
#       label-readiness check  (stub gh/glab/tea, throwaway repos by hostname)
#   (d) riper-retry-* survives status-family exclusive cleanup (design edge 1)
#   (e) Bash 3.2 compatibility (no `declare -A`; runs under macOS /bin/bash)
# Steps 14-15 (issue get --json) were DROPPED per revision #2 — not tested here.
# Run from repository root: bash test/iloop-issue-list-retry-guard-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ALL14="p0 p1 p2 p3 riper-research riper-innovation riper-plan riper-execute riper-review riper-verified riper-blocked riper-retry-1 riper-retry-2 riper-retry-3"

# ===========================================================================
# stub: gh — state-backed labels so add/remove/view/list are consistent.
#   $GH_LABELS        repo-level label names (one per line) for `label list`
#   $GH_ISSUES        issue meta: num<TAB>state<TAB>title  (one per line)
#   $GH_LABELDIR/<n>  per-issue label names (one per line), mutable
# ===========================================================================
mkdir -p "$WORK/ghbin"
cat > "$WORK/ghbin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${STUB_LOG:-/dev/null}"
[[ "${1:-} ${2:-}" == "auth status" ]] && exit 0
if [[ "${1:-} ${2:-}" == "label list" ]]; then
  [[ "${GH_LABELS_FAIL:-0}" == "1" ]] && { echo "network unreachable" >&2; exit 1; }
  cat "${GH_LABELS:-/dev/null}" 2>/dev/null
  exit 0
fi
if [[ "${1:-} ${2:-}" == "issue list" ]]; then
  # emit num<TAB>state<TAB>title<TAB>comma-labels (mirrors gh --jq @tsv output)
  while IFS="$(printf '\t')" read -r n s t; do
    [[ -z "${n:-}" ]] && continue
    labs=""
    if [[ -f "${GH_LABELDIR:-/dev/null}/$n" ]]; then
      labs="$(paste -sd, "${GH_LABELDIR}/$n" 2>/dev/null)"
    fi
    printf '%s\t%s\t%s\t%s\n' "$n" "$s" "$t" "$labs"
  done < "${GH_ISSUES:-/dev/null}"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "issue view" ]]; then
  num="${3:-}"
  # only the --json labels path is used by raw_issue_labels
  if [[ -f "${GH_LABELDIR:-/dev/null}/$num" ]]; then cat "${GH_LABELDIR}/$num"; fi
  exit 0
fi
if [[ "${1:-} ${2:-}" == "issue edit" ]]; then
  num="${3:-}"; shift 3
  f="${GH_LABELDIR:-/dev/null}/$num"
  mode=""
  for a in "$@"; do
    case "$a" in
      --add-label)    mode="add" ;;
      --remove-label) mode="rem" ;;
      *) [[ -n "$mode" ]] && {
           case "$mode" in
             add) grep -Fxq -- "$a" "$f" 2>/dev/null || echo "$a" >> "$f" ;;
             rem) grep -vxF -- "$a" "$f" > "$f.tmp" 2>/dev/null || true; mv "$f.tmp" "$f" ;;
           esac; mode=""
         } ;;
    esac
  done
  exit 0
fi
exit 0
STUB
chmod +x "$WORK/ghbin/gh"

# ===========================================================================
# stub: glab — text issue output plus JSON repository-label output.
#   $GLAB_LABELS  repo-level names for `label list --output json`
#   $GLAB_LABELDIR/<n>  per-issue labels (comma file), mutable
#   GLAB_LABELS_FAIL=1  makes `label list` exit 1
# ===========================================================================
mkdir -p "$WORK/glabbin"
cat > "$WORK/glabbin/glab" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${STUB_LOG:-/dev/null}"
[[ "${1:-}" == "auth" ]] && exit 0
if [[ "${1:-} ${2:-}" == "label list" ]]; then
  [[ "${GLAB_LABELS_FAIL:-0}" == "1" ]] && { echo "net down" >&2; exit 1; }
  if [[ " $* " == *" --output json "* ]]; then
    first=1
    printf '['
    while IFS= read -r name; do
      [[ -z "$name" ]] && continue
      [[ "$first" -eq 0 ]] && printf ','
      printf '{"name":"%s"}' "$name"
      first=0
    done < "${GLAB_LABELS:-/dev/null}"
    printf ']\n'
  else
    cat "${GLAB_LABELS:-/dev/null}" 2>/dev/null
  fi
  exit 0
fi
if [[ "${1:-} ${2:-}" == "issue list" ]]; then
  # glab list output: "#<n>  <title>" — NO label column (degradation path)
  while IFS="$(printf '\t')" read -r n s t; do
    [[ -z "${n:-}" ]] && continue
    printf '#%s  %s\n' "$n" "$t"
  done < "${GLAB_ISSUES:-/dev/null}"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "issue view" ]]; then
  num="${3:-}"
  printf 'title:\tstub\nstate:\topen\n'
  if [[ -f "${GLAB_LABELDIR:-/dev/null}/$num" ]]; then
    printf 'labels:\t%s\n' "$(cat "${GLAB_LABELDIR}/$num")"
  fi
  exit 0
fi
if [[ "${1:-} ${2:-}" == "issue update" ]]; then
  num="${3:-}"; shift 3
  f="${GLAB_LABELDIR:-/dev/null}/$num"
  add=""; rem=""
  prev=""
  for a in "$@"; do
    [[ "$prev" == "--label" ]]   && add="$a"
    [[ "$prev" == "--unlabel" ]] && rem="$a"
    prev="$a"
  done
  cur=""; [[ -f "$f" ]] && cur="$(cat "$f")"
  # comma-separated list manipulation
  IFS=',' read -ra arr <<< "$cur"
  out=()
  for x in "${arr[@]}"; do x="${x// /}"; [[ -n "$x" && "$x" != "$rem" ]] && out+=("$x"); done
  [[ -n "$add" ]] && { dup=0; for x in "${out[@]:-}"; do [[ "$x" == "$add" ]] && dup=1; done; [[ $dup -eq 0 ]] && out+=("$add"); }
  ( IFS=','; echo "${out[*]:-}" > "$f" )
  exit 0
fi
exit 0
STUB
chmod +x "$WORK/glabbin/glab"

# ===========================================================================
# stub: tea — Gitea box table for `labels list` (name = $4 by -F'│');
#   `issues <n>` prints lowercase `labels:` line; `issues edit` mutates.
# ===========================================================================
mkdir -p "$WORK/teabin"
cat > "$WORK/teabin/tea" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "${STUB_LOG:-/dev/null}"
[[ "${1:-} ${2:-}" == "login list" ]] && { echo "https://gitea.example.com  gitea  someuser  <token>"; exit 0; }
[[ "${1:-}" == "login" ]] && exit 0
if [[ "${1:-} ${2:-}" == "labels list" ]]; then
  [[ "${TEA_LABELS_FAIL:-0}" == "1" ]] && { echo "net down" >&2; exit 1; }
  echo "│ ID │ Color │ Name │ Description │"
  i=0
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    i=$((i+1)); printf '│ %d │ c0ffee │ %s │ stub │\n' "$i" "$n"
  done < "${TEA_LABELS:-/dev/null}"
  exit 0
fi
if [[ "${1:-}" == "issues" ]]; then
  # `issues` (list) vs `issues <n>` (view) vs `issues edit <n> ...`
  if [[ "${2:-}" == "edit" ]]; then
    num="${3:-}"; shift 3
    f="${TEA_LABELDIR:-/dev/null}/$num"
    add=""; rem=""; prev=""
    for a in "$@"; do
      [[ "$prev" == "--add-labels" ]]    && add="$a"
      [[ "$prev" == "--remove-labels" ]] && rem="$a"
      prev="$a"
    done
    cur=""; [[ -f "$f" ]] && cur="$(cat "$f")"
    IFS=',' read -ra arr <<< "$cur"
    out=()
    for x in "${arr[@]}"; do x="${x// /}"; [[ -n "$x" && "$x" != "$rem" ]] && out+=("$x"); done
    [[ -n "$add" ]] && { dup=0; for x in "${out[@]:-}"; do [[ "$x" == "$add" ]] && dup=1; done; [[ $dup -eq 0 ]] && out+=("$add"); }
    ( IFS=','; echo "${out[*]:-}" > "$f" )
    exit 0
  fi
  if [[ -n "${2:-}" && "${2:-}" =~ ^[0-9]+$ ]]; then
    num="${2:-}"
    printf 'title: stub\n'
    if [[ -f "${TEA_LABELDIR:-/dev/null}/$num" ]]; then
      printf 'labels: %s\n' "$(cat "${TEA_LABELDIR}/$num")"
    fi
    exit 0
  fi
  # list
  while IFS="$(printf '\t')" read -r n s t; do
    [[ -z "${n:-}" ]] && continue
    printf '#%s  %s\n' "$n" "$t"
  done < "${TEA_ISSUES:-/dev/null}"
  exit 0
fi
exit 0
STUB
chmod +x "$WORK/teabin/tea"

# make_repo <name> <origin-url>
make_repo() {
  local d="$WORK/$1"; mkdir -p "$d"; git -C "$d" init -q; git -C "$d" remote add origin "$2"; echo "$d"
}
GH_REPO="$(make_repo gh   https://github.com/o/r.git)"
GLAB_REPO="$(make_repo glab https://gitlab.com/o/r.git)"
TEA_REPO="$(make_repo tea  https://gitea.example.com/o/r.git)"

# probe <repo> <binpath> <args...>: sets RC / OUT / ERR / LOG
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
echo "=== (a) bash -n syntax ==="
if bash -n "$GITOPS" 2>"$WORK/syn.err"; then pass "bash -n git-ops.sh"; else fail "bash -n: $(cat "$WORK/syn.err")"; fi

#############################################################################
echo "=== (e) Bash 3.2: no associative arrays; runs under /bin/bash ==="
# strip comments before scanning so doc text like "禁 declare -A" is not a false hit
if sed 's/#.*//' "$GITOPS" | grep -nE 'declare[[:space:]]+-A|typeset[[:space:]]+-A' >/dev/null; then
  fail "found declare -A in code (Bash 4+ only)"; sed 's/#.*//' "$GITOPS" | grep -nE 'declare[[:space:]]+-A'
else
  pass "no declare -A / typeset -A in code"
fi
BINBASH="$(command -v /bin/bash || true)"
if [[ -n "$BINBASH" ]]; then
  echo "  /bin/bash version: $(/bin/bash --version | head -1)"
  # smoke-run new commands under /bin/bash (gh stub) — must not syntax-error
  export GH_LABELDIR="$WORK/ghlab" GH_ISSUES="$WORK/ghissues.tsv" GH_LABELS="$WORK/ghrepolabels"
  mkdir -p "$GH_LABELDIR"; printf '1\tOPEN\tissue one\n' > "$GH_ISSUES"; : > "$GH_LABELDIR/1"
  printf '%s\n' $ALL14 > "$GH_LABELS"
  if ( cd "$GH_REPO" && PATH="$WORK/ghbin:$PATH" /bin/bash "$GITOPS" issue list >/dev/null 2>&1 ); then
    pass "/bin/bash issue list runs"
  else
    fail "/bin/bash issue list errored"
  fi
  if ( cd "$GH_REPO" && PATH="$WORK/ghbin:$PATH" /bin/bash "$GITOPS" guard developer >/dev/null 2>&1 ); then
    pass "/bin/bash guard runs"
  else
    fail "/bin/bash guard errored"
  fi
  unset GH_LABELDIR GH_ISSUES GH_LABELS
fi

#############################################################################
echo "=== (c-1) issue list on gh: priority sort, filters, validation ==="
export GH_LABELDIR="$WORK/ghlab" GH_ISSUES="$WORK/ghissues.tsv" GH_LABELS="$WORK/ghrepolabels"
mkdir -p "$GH_LABELDIR"
printf '%s\n' $ALL14 > "$GH_LABELS"
# fixture: #1 p0/execute, #2 p1/research, #3 (no priority)/plan, #4 p0/verified
printf '1\tOPEN\talpha\n2\tOPEN\tbeta\n3\tOPEN\tgamma\n4\tOPEN\tdelta\n' > "$GH_ISSUES"
printf 'p0\nriper-execute\n'   > "$GH_LABELDIR/1"
printf 'p1\nriper-research\n'  > "$GH_LABELDIR/2"
printf 'riper-plan\n'          > "$GH_LABELDIR/3"
printf 'p0\nriper-verified\n'  > "$GH_LABELDIR/4"

probe "$GH_REPO" "$WORK/ghbin" issue list
if [[ "$RC" -eq 0 ]]; then pass "issue list exit 0"; else fail "issue list rc=$RC err=$ERR"; fi
# order: p0 group (#1,#4 by number) then p1 (#2) then (无) (#3)
order="$(printf '%s' "$OUT" | grep -oE '#[0-9]+' | tr '\n' ' ')"
if [[ "$order" == "#1 #4 #2 #3 " ]]; then pass "priority sort p0<p1<(无), num tiebreak ($order)"; else fail "bad sort order: $order"; fi
if printf '%s' "$OUT" | grep -q '(无)'; then pass "no-priority row shows (无)"; else fail "missing (无) marker"; fi

probe "$GH_REPO" "$WORK/ghbin" issue list --priority p0
got="$(printf '%s' "$OUT" | grep -oE '#[0-9]+' | tr '\n' ' ')"
[[ "$got" == "#1 #4 " ]] && pass "--priority p0 -> #1 #4" || fail "--priority p0 got '$got'"

probe "$GH_REPO" "$WORK/ghbin" issue list --status riper-research
got="$(printf '%s' "$OUT" | grep -oE '#[0-9]+' | tr '\n' ' ')"
[[ "$got" == "#2 " ]] && pass "--status riper-research -> #2" || fail "--status riper-research got '$got'"

probe "$GH_REPO" "$WORK/ghbin" issue list --priority p9
[[ "$RC" -eq 1 ]] && pass "--priority p9 -> exit 1" || fail "--priority p9 rc=$RC (want 1)"
printf '%s' "$ERR" | grep -q 'p0' && pass "p9 error lists legal values" || fail "p9 error missing legal-value list"

probe "$GH_REPO" "$WORK/ghbin" issue list --state bogus
[[ "$RC" -eq 1 ]] && pass "--state bogus -> exit 1" || fail "--state bogus rc=$RC (want 1)"

echo "=== (c-1b) issue list degradation on glab/tea (no label column) ==="
export GLAB_LABELDIR="$WORK/glablab" GLAB_ISSUES="$WORK/glabissues.tsv" GLAB_LABELS="$WORK/glabrepolabels"
mkdir -p "$GLAB_LABELDIR"; printf '%s\n' $ALL14 > "$GLAB_LABELS"
printf '1\topen\talpha\n2\topen\tbeta\n' > "$GLAB_ISSUES"
probe "$GLAB_REPO" "$WORK/glabbin" issue list
if [[ "$RC" -eq 0 ]]; then pass "glab issue list exit 0 (degraded)"; else fail "glab issue list rc=$RC"; fi
printf '%s' "$OUT" | grep -q '(无)' && pass "glab degraded rows show (无)" || fail "glab degraded missing (无)"
probe "$GLAB_REPO" "$WORK/glabbin" issue list --priority p0
if [[ "$RC" -eq 0 ]]; then pass "glab --priority ignored without crash (exit 0)"; else fail "glab --priority rc=$RC"; fi
printf '%s' "$ERR" | grep -qi 'glab\|tea\|标签' && pass "glab emits label-unavailable notice" || fail "glab missing degradation notice"

export TEA_LABELDIR="$WORK/tealab" TEA_ISSUES="$WORK/teaissues.tsv" TEA_LABELS="$WORK/tearepolabels"
mkdir -p "$TEA_LABELDIR"; printf '%s\n' $ALL14 > "$TEA_LABELS"
printf '1\topen\talpha\n' > "$TEA_ISSUES"
probe "$TEA_REPO" "$WORK/teabin" issue list
[[ "$RC" -eq 0 ]] && pass "tea issue list exit 0 (degraded)" || fail "tea issue list rc=$RC"

echo "=== (c-1c) routing evidence: issue list calls each platform's CLI ==="
probe "$GH_REPO" "$WORK/ghbin" issue list   >/dev/null; grep -q 'issue list' "$LOG"   && pass "gh: 'gh issue list' invoked"   || fail "gh issue list not invoked"
probe "$GLAB_REPO" "$WORK/glabbin" issue list >/dev/null; grep -q 'issue list' "$LOG" && pass "glab: 'glab issue list' invoked" || fail "glab issue list not invoked"
probe "$TEA_REPO" "$WORK/teabin" issue list  >/dev/null; grep -q 'issues' "$LOG"      && pass "tea: 'tea issues' invoked"      || fail "tea issues not invoked"

#############################################################################
echo "=== (c-2) issue retry on gh: exclusive persistence + cap + cross-family ==="
printf 'p0\nriper-execute\n' > "$GH_LABELDIR/1"   # reset issue 1 labels
probe "$GH_REPO" "$WORK/ghbin" --role reviewer issue retry 1 get
[[ "$OUT" == "0" ]] && pass "initial retry get -> 0" || fail "initial get='$OUT' (want 0)"

for i in 1 2 3; do probe "$GH_REPO" "$WORK/ghbin" --role reviewer issue retry 1 incr; done
probe "$GH_REPO" "$WORK/ghbin" --role reviewer issue retry 1 get
[[ "$OUT" == "3" ]] && pass "after 3 incr, get -> 3" || fail "after 3 incr get='$OUT'"
retrylabels="$(grep -c '^riper-retry-' "$GH_LABELDIR/1" || true)"
[[ "$retrylabels" == "1" ]] && pass "exactly one riper-retry-* label (exclusive)" || fail "retry label count=$retrylabels"
grep -Fxq 'riper-retry-3' "$GH_LABELDIR/1" && pass "the one retry label is riper-retry-3" || fail "expected riper-retry-3"
grep -Fxq 'p0' "$GH_LABELDIR/1" && pass "cross-family: p0 intact after incr" || fail "p0 lost after incr"
grep -Fxq 'riper-execute' "$GH_LABELDIR/1" && pass "cross-family: riper-execute intact after incr" || fail "status lost after incr"

probe "$GH_REPO" "$WORK/ghbin" --role reviewer issue retry 1 incr
[[ "$RC" -eq 1 ]] && pass "4th incr -> exit 1 (cap)" || fail "4th incr rc=$RC (want 1)"
printf '%s' "$ERR" | grep -q 'riper-blocked' && pass "cap error mentions riper-blocked" || fail "cap error missing riper-blocked"
grep -Fxq 'riper-retry-3' "$GH_LABELDIR/1" && pass "label stays riper-retry-3 after cap" || fail "cap mutated label"

probe "$GH_REPO" "$WORK/ghbin" --role reviewer issue retry 1 reset
probe "$GH_REPO" "$WORK/ghbin" --role reviewer issue retry 1 get
[[ "$OUT" == "0" ]] && pass "after reset, get -> 0" || fail "after reset get='$OUT'"
grep -Fxq 'p0' "$GH_LABELDIR/1" && pass "reset preserves p0 (cross-family)" || fail "reset dropped p0"

echo "=== (c-2b) issue retry routing on glab + tea (lowercase labels: parse) ==="
echo "p0,riper-retry-2" > "$GLAB_LABELDIR/1"
probe "$GLAB_REPO" "$WORK/glabbin" --role reviewer issue retry 1 get
[[ "$OUT" == "2" ]] && pass "glab retry get parses lowercase labels: -> 2" || fail "glab get='$OUT' (want 2)"
echo "p1,riper-retry-1" > "$TEA_LABELDIR/1"
probe "$TEA_REPO" "$WORK/teabin" --role reviewer issue retry 1 get
[[ "$OUT" == "1" ]] && pass "tea retry get parses lowercase labels: -> 1" || fail "tea get='$OUT' (want 1)"

echo "=== (c-2c) issue retry permission: incr reviewer-only ==="
probe "$GH_REPO" "$WORK/ghbin" --role planner issue retry 1 incr
[[ "$RC" -eq 1 ]] && pass "planner incr denied" || fail "planner incr rc=$RC (want 1)"
probe "$GH_REPO" "$WORK/ghbin" --role developer issue retry 1 incr
[[ "$RC" -eq 1 ]] && pass "developer incr denied" || fail "developer incr rc=$RC (want 1)"
probe "$GH_REPO" "$WORK/ghbin" --role planner issue retry 1 get
[[ "$RC" -eq 0 ]] && pass "planner get allowed (read)" || fail "planner get rc=$RC (want 0)"
probe "$GH_REPO" "$WORK/ghbin" --role planner issue label 1 add riper-retry-1
[[ "$RC" -eq 1 ]] && pass "label add riper-retry-1 denied (mutual-exclusion)" || fail "label add retry rc=$RC (want 1)"

echo "=== (c-2d) issue retry arg validation ==="
probe "$GH_REPO" "$WORK/ghbin" issue retry 1
[[ "$RC" -eq 1 ]] && pass "retry missing action -> exit 1" || fail "retry missing action rc=$RC"
probe "$GH_REPO" "$WORK/ghbin" issue retry 1 foo
[[ "$RC" -eq 1 ]] && pass "retry bad action -> exit 1" || fail "retry bad action rc=$RC"

#############################################################################
echo "=== (d) riper-retry-* survives status-family exclusive cleanup ==="
printf 'p0\nriper-execute\nriper-retry-2\n' > "$GH_LABELDIR/1"
probe "$GH_REPO" "$WORK/ghbin" --role developer issue status 1 riper-review
grep -Fxq 'riper-retry-2' "$GH_LABELDIR/1" && pass "status switch preserves riper-retry-2" || fail "status cleanup deleted retry label"
grep -Fxq 'riper-review' "$GH_LABELDIR/1" && pass "status switched to riper-review" || fail "status not applied"
grep -Fxq 'riper-execute' "$GH_LABELDIR/1" && fail "old status riper-execute not cleaned" || pass "old status cleaned (exclusive)"

#############################################################################
echo "=== (d-2) case-insensitive family cleanup: uppercase variants removed (#19) ==="
# gh stub 的 add/remove 用 grep -Fx（大小写敏感），模拟 GitLab：P0 与 p0 可并存。
# 设置优先级时必须清掉大写变体 P0，否则复发为「P0p0」。
printf 'P0\nRIPER-EXECUTE\n' > "$GH_LABELDIR/1"
probe "$GH_REPO" "$WORK/ghbin" --role planner issue priority 1 p1
grep -Fxq 'p1' "$GH_LABELDIR/1" && pass "priority p1 applied" || fail "p1 not applied"
grep -Fxq 'P0' "$GH_LABELDIR/1" && fail "uppercase P0 survived priority cleanup (P0p0 bug)" || pass "uppercase P0 removed (case-insensitive)"
grep -Fxq 'p0' "$GH_LABELDIR/1" && fail "lowercase p0 present unexpectedly" || pass "no lowercase p0 duplicate"
grep -Fxq 'RIPER-EXECUTE' "$GH_LABELDIR/1" && pass "cross-family: status variant untouched by priority cmd" || fail "priority cmd wrongly removed status label"

# 状态切换同样清大写变体 RIPER-EXECUTE，且不动跨族 p1
probe "$GH_REPO" "$WORK/ghbin" --role developer issue status 1 riper-review
grep -Fxq 'riper-review' "$GH_LABELDIR/1" && pass "status riper-review applied" || fail "riper-review not applied"
grep -Fxq 'RIPER-EXECUTE' "$GH_LABELDIR/1" && fail "uppercase RIPER-EXECUTE survived status cleanup" || pass "uppercase status variant removed (case-insensitive)"
grep -Fxq 'p1' "$GH_LABELDIR/1" && pass "cross-family: p1 intact after status switch" || fail "status cmd wrongly removed priority p1"

# retry get/incr 对大写变体大小写不敏感：RIPER-RETRY-2 应读成 2，incr 到 3 而非重置为 1
printf 'RIPER-RETRY-2\n' > "$GH_LABELDIR/1"
probe "$GH_REPO" "$WORK/ghbin" --role reviewer issue retry 1 get
[[ "$OUT" == "2" ]] && pass "retry get reads uppercase RIPER-RETRY-2 -> 2" || fail "retry get='$OUT' (want 2, case-insensitive)"
probe "$GH_REPO" "$WORK/ghbin" --role reviewer issue retry 1 incr
grep -Fxq 'riper-retry-3' "$GH_LABELDIR/1" && pass "retry incr from uppercase variant -> riper-retry-3 (no reset)" || fail "expected riper-retry-3 after incr"
grep -Fxq 'RIPER-RETRY-2' "$GH_LABELDIR/1" && fail "uppercase RIPER-RETRY-2 survived incr cleanup" || pass "uppercase retry variant removed (case-insensitive)"

#############################################################################
echo "=== (c-3) guard writable-area matrix (throwaway repo) ==="
GREPO="$(make_repo guardrepo https://github.com/o/r.git)"
mkdir -p "$GREPO/scripts" "$GREPO/docs/issues/1" "$GREPO/test"
for f in scripts/git-ops.sh docs/issues/1/spec.md docs/issues/1/plan.md docs/issues/1/verify-report.md test/foo.sh README.md; do
  echo x > "$GREPO/$f"
done
git -C "$GREPO" add -A >/dev/null 2>&1
git -C "$GREPO" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
gchk() { # <role> <want-rc> <file> <new|edit> <desc>
  local role="$1" want="$2" file="$3" mode="$4" desc="$5"
  git -C "$GREPO" checkout -q . 2>/dev/null || true; git -C "$GREPO" clean -qfd 2>/dev/null || true
  if [[ "$mode" == new ]]; then mkdir -p "$GREPO/$(dirname "$file")"; echo y > "$GREPO/$file"; else echo y >> "$GREPO/$file"; fi
  local rc=0
  ( cd "$GREPO" && bash "$GITOPS" guard "$role" >/dev/null 2>&1 ) || rc=$?
  [[ "$rc" == "$want" ]] && pass "guard $role $desc (rc=$rc)" || fail "guard $role $desc rc=$rc want=$want"
}
gchk planner   0 docs/issues/1/spec.md         edit "edits spec.md -> allow"
gchk planner   1 scripts/git-ops.sh            edit "edits scripts -> deny"
gchk reviewer  0 test/foo2.sh                  new  "new test/foo2.sh -> allow"
gchk reviewer  1 scripts/git-ops.sh            edit "edits scripts -> deny"
gchk reviewer  0 docs/issues/1/verify-report.md edit "edits verify-report -> allow"
gchk developer 0 docs/issues/1/plan.md         edit "edits plan.md -> allow"
gchk developer 1 docs/issues/1/spec.md         edit "edits spec.md -> deny"
gchk developer 0 scripts/git-ops.sh            edit "edits scripts -> allow"
gchk developer 1 test/foo.sh                   edit "edits test -> deny"
git -C "$GREPO" checkout -q . 2>/dev/null || true; git -C "$GREPO" clean -qfd 2>/dev/null || true
rc=0; ( cd "$GREPO" && bash "$GITOPS" guard developer >/dev/null 2>&1 ) || rc=$?
[[ "$rc" -eq 0 ]] && pass "guard clean tree -> exit 0" || fail "guard clean tree rc=$rc"
rc=0; ( cd "$GREPO" && bash "$GITOPS" guard hacker >/dev/null 2>&1 ) || rc=$?
[[ "$rc" -eq 1 ]] && pass "guard hacker -> exit 1" || fail "guard hacker rc=$rc"
rc=0; ( cd "$GREPO" && bash "$GITOPS" guard >/dev/null 2>&1 ) || rc=$?
[[ "$rc" -eq 1 ]] && pass "guard missing arg -> exit 1" || fail "guard missing arg rc=$rc"

#############################################################################
echo "=== (c-4) doctor label-readiness: full / partial / fail ==="
export GH_LABELS="$WORK/ghrepolabels"
printf '%s\n' $ALL14 > "$GH_LABELS"
probe "$GH_REPO" "$WORK/ghbin" doctor
[[ "$RC" -eq 0 ]] && pass "doctor full 14 labels -> exit 0" || fail "doctor full rc=$RC"
printf '%s' "$OUT" | grep -q '14/14' && pass "doctor prints 14/14" || fail "doctor missing 14/14"
printf 'bug\ndocumentation\n' > "$GH_LABELS"
probe "$GH_REPO" "$WORK/ghbin" doctor
[[ "$RC" -eq 1 ]] && pass "doctor partial -> exit 1" || fail "doctor partial rc=$RC"
printf '%s' "$ERR$OUT" | grep -q 'labels init' && pass "doctor partial hints labels init" || fail "doctor partial missing labels-init hint"
printf '%s\n' $ALL14 > "$GH_LABELS"; GH_LABELS_FAIL=1 probe "$GH_REPO" "$WORK/ghbin" doctor
[[ "$RC" -eq 1 ]] && pass "doctor label-list fail -> exit 1" || fail "doctor fail rc=$RC"
printf '%s' "$ERR$OUT" | grep -q '无法获取远端标签' && pass "doctor fail says network/permission (not 'missing')" || fail "doctor fail wrong wording"
printf '%s' "$ERR$OUT" | grep -q '缺失以下标签' && fail "doctor fail misreported as missing labels" || pass "doctor fail does NOT misreport missing"
unset GH_LABELS_FAIL

echo "=== (c-4b) doctor label-readiness routing on glab + tea ==="
export GLAB_LABELS="$WORK/glabrepolabels"; printf '%s\n' $ALL14 > "$GLAB_LABELS"
probe "$GLAB_REPO" "$WORK/glabbin" doctor
[[ "$RC" -eq 0 ]] && pass "glab doctor 14/14 -> exit 0" || fail "glab doctor rc=$RC err=$ERR"
export TEA_LABELS="$WORK/tearepolabels"; printf '%s\n' $ALL14 > "$TEA_LABELS"
probe "$TEA_REPO" "$WORK/teabin" doctor
[[ "$RC" -eq 0 ]] && pass "tea doctor 14/14 -> exit 0" || fail "tea doctor rc=$RC err=$ERR"
GLAB_LABELS_FAIL=1 probe "$GLAB_REPO" "$WORK/glabbin" doctor
[[ "$RC" -eq 1 ]] && pass "glab doctor label-list fail -> exit 1" || fail "glab doctor fail rc=$RC"

#############################################################################
echo "=== (b) permission-matrix regression (deny paths expect exit 1) ==="
pchk() { local desc="$1" want="$2"; shift 2; probe "$GH_REPO" "$WORK/ghbin" "$@"; [[ "$RC" == "$want" ]] && pass "$desc (rc=$RC)" || fail "$desc rc=$RC want=$want"; }
pchk "developer close denied"        1 --role developer issue close 1
pchk "developer reopen denied"       1 --role developer issue reopen 1
pchk "developer priority denied"     1 --role developer issue priority 1 p0
pchk "planner status execute denied" 1 --role planner issue status 1 riper-execute
pchk "reviewer priority denied"      1 --role reviewer issue priority 1 p0
pchk "label add priority denied"     1 --role planner issue label 1 add p0
pchk "label add status denied"       1 --role planner issue label 1 add riper-plan
pchk "label add retry denied"        1 --role planner issue label 1 add riper-retry-1
pchk "bad role on gated denied"      1 --role hacker issue priority 1 p0
# allow paths
probe "$GH_REPO" "$WORK/ghbin" --role reviewer issue retry 1 get; [[ "$RC" -eq 0 ]] && pass "reviewer retry get allowed" || fail "reviewer get rc=$RC"
probe "$GH_REPO" "$WORK/ghbin" --role developer issue status 1 riper-execute; [[ "$RC" -eq 0 ]] && pass "developer status execute allowed" || fail "dev status rc=$RC"

echo "=== (c-5) usage / --help advertise new commands ==="
probe "$GH_REPO" "$WORK/ghbin" --help
for kw in "issue list" "issue retry" "guard <role>" "labels init"; do
  printf '%s' "$OUT$ERR" | grep -q "$kw" && pass "--help contains '$kw'" || fail "--help missing '$kw'"
done
probe "$GH_REPO" "$WORK/ghbin" issue
[[ "$RC" -eq 1 ]] && pass "bare 'issue' -> exit 1" || fail "bare issue rc=$RC"
probe "$GH_REPO" "$WORK/ghbin" issue get
[[ "$RC" -eq 1 ]] && pass "'issue get' missing arg -> exit 1 (guard relax didn't break)" || fail "issue get rc=$RC"

#############################################################################
if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
