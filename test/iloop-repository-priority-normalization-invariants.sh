#!/usr/bin/env bash
# Black-box regression checks for Issue #22: repository-level P0/p0 normalization.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

make_repo() {
  local name="$1" url="$2" dir="${WORK}/$1"
  mkdir -p "$dir"; git -C "$dir" init -q; git -C "$dir" remote add origin "$url"
  printf '%s' "$dir"
}

write_common_issue_ops='\
remove_label() { grep -Fxv -- "$2" "$1" > "$1.tmp" || true; mv "$1.tmp" "$1"; }\
add_label() { grep -Fxq -- "$2" "$1" 2>/dev/null || printf "%s\\n" "$2" >> "$1"; }'

mkdir -p "$WORK/ghbin"
cat > "$WORK/ghbin/gh" <<'STUB'
#!/usr/bin/env bash
set -e
echo "$*" >> "$CALL_LOG"
remove_label() { grep -Fxv -- "$2" "$1" > "$1.tmp" || true; mv "$1.tmp" "$1"; }
add_label() { grep -Fxq -- "$2" "$1" 2>/dev/null || printf '%s\n' "$2" >> "$1"; }
[[ "${1:-}" == "auth" ]] && exit 0
if [[ "${1:-} ${2:-}" == "label list" ]]; then
  while IFS= read -r name; do printf '%s\n' "$name"; done < "$CATALOG"
  exit 0
fi
if [[ "${1:-} ${2:-}" == "label create" ]]; then
  name="${3:-}"; lc="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r old; do [[ "$(printf '%s' "$old" | tr '[:upper:]' '[:lower:]')" == "$lc" ]] && exit 1; done < "$CATALOG"
  printf '%s\n' "$name" >> "$CATALOG"; exit 0
fi
if [[ "${1:-} ${2:-}" == "label edit" ]]; then
  from="${3:-}"; prev=""; to=""
  for a in "$@"; do [[ "$prev" == "--name" ]] && to="$a"; prev="$a"; done
  [[ -z "$to" ]] && exit 0
  sed "s/^${from}$/${to}/" "$CATALOG" > "$CATALOG.tmp"; mv "$CATALOG.tmp" "$CATALOG"
  for f in "$ISSUES"/*; do sed "s/^${from}$/${to}/" "$f" > "$f.tmp"; mv "$f.tmp" "$f"; done
  exit 0
fi
if [[ "${1:-} ${2:-}" == "issue list" ]]; then
  prev=""; label=""; for a in "$@"; do [[ "$prev" == "--label" ]] && label="$a"; prev="$a"; done
  for f in "$ISSUES"/*; do grep -Fxq -- "$label" "$f" && basename "$f"; done; exit 0
fi
if [[ "${1:-} ${2:-}" == "issue edit" ]]; then
  num="$3"; prev=""; for a in "$@"; do
    [[ "$prev" == "--add-label" ]] && add_label "$ISSUES/$num" "$a"
    [[ "$prev" == "--remove-label" ]] && remove_label "$ISSUES/$num" "$a"
    prev="$a"
  done; exit 0
fi
if [[ "${1:-} ${2:-}" == "issue view" ]]; then cat "$ISSUES/$3"; exit 0; fi
exit 0
STUB
chmod +x "$WORK/ghbin/gh"

mkdir -p "$WORK/glabbin"
cat > "$WORK/glabbin/glab" <<'STUB'
#!/usr/bin/env bash
set -e
echo "$*" >> "$CALL_LOG"
remove_label() { grep -Fxv -- "$2" "$1" > "$1.tmp" || true; mv "$1.tmp" "$1"; }
add_label() { grep -Fxq -- "$2" "$1" 2>/dev/null || printf '%s\n' "$2" >> "$1"; }
[[ "${1:-}" == "auth" ]] && exit 0
if [[ "${1:-} ${2:-}" == "label list" ]]; then
  first=1; printf '['; while IFS= read -r name; do [[ $first -eq 0 ]] && printf ','; printf '{"name":"%s"}' "$name"; first=0; done < "$CATALOG"; printf ']\n'; exit 0
fi
if [[ "${1:-} ${2:-}" == "label create" ]]; then
  prev=""; name=""; for a in "$@"; do [[ "$prev" == "--name" ]] && name="$a"; prev="$a"; done
  [[ -z "$name" ]] && name="${3:-}"; grep -Fxq -- "$name" "$CATALOG" && exit 1; printf '%s\n' "$name" >> "$CATALOG"; exit 0
fi
if [[ "${1:-} ${2:-}" == "label edit" ]]; then exit 0; fi
if [[ "${1:-} ${2:-}" == "label delete" ]]; then
  [[ "${FAIL_MODE:-}" == delete ]] && exit 1
  remove_label "$CATALOG" "$3"; exit 0
fi
if [[ "${1:-} ${2:-}" == "issue list" ]]; then
  prev=""; label=""; for a in "$@"; do [[ "$prev" == "--label" ]] && label="$a"; prev="$a"; done
  for f in "$ISSUES"/*; do grep -Fxq -- "$label" "$f" && basename "$f"; done; exit 0
fi
if [[ "${1:-} ${2:-}" == "issue update" ]]; then
  num="$3"; prev=""; for a in "$@"; do
    [[ "$prev" == "--label" ]] && add_label "$ISSUES/$num" "$a"
    if [[ "$prev" == "--unlabel" ]]; then
      [[ "${FAIL_MODE:-}" == remove ]] && exit 1
      remove_label "$ISSUES/$num" "$a"
    fi
    prev="$a"
  done; exit 0
fi
if [[ "${1:-} ${2:-}" == "issue view" ]]; then
  [[ "${FAIL_MODE:-}" == verify ]] && exit 1
  echo __ILOOP_LABELS_OK__; cat "$ISSUES/$3"; exit 0
fi
exit 0
STUB
chmod +x "$WORK/glabbin/glab"

mkdir -p "$WORK/teabin"
cat > "$WORK/teabin/tea" <<'STUB'
#!/usr/bin/env bash
set -e
echo "$*" >> "$CALL_LOG"
remove_label() { grep -Fxv -- "$2" "$1" > "$1.tmp" || true; mv "$1.tmp" "$1"; }
add_label() { grep -Fxq -- "$2" "$1" 2>/dev/null || printf '%s\n' "$2" >> "$1"; }
[[ "${1:-} ${2:-}" == "login list" ]] && { echo 'https://gitea.example.test user token'; exit 0; }
if [[ "${1:-} ${2:-}" == "labels list" ]]; then
  echo '│ ID │ Color │ Name │ Description │'; i=0
  while IFS= read -r name; do i=$((i+1)); printf '│ %d │ c0ffee │ %s │ stub │\n' "$i" "$name"; done < "$CATALOG"; exit 0
fi
if [[ "${1:-} ${2:-}" == "labels create" ]]; then
  prev=""; name=""; for a in "$@"; do [[ "$prev" == "--name" ]] && name="$a"; prev="$a"; done
  grep -Fxq -- "$name" "$CATALOG" || printf '%s\n' "$name" >> "$CATALOG"; exit 0
fi
if [[ "${1:-} ${2:-}" == "labels delete" ]]; then
  prev=""; id=""; for a in "$@"; do [[ "$prev" == "--id" ]] && id="$a"; prev="$a"; done
  sed -n "${id}p" "$CATALOG" > "$CATALOG.name"; name="$(cat "$CATALOG.name")"; remove_label "$CATALOG" "$name"; exit 0
fi
if [[ "${1:-}" == "issues" && "${2:-}" == "edit" ]]; then
  num="$3"; prev=""; for a in "$@"; do
    [[ "$prev" == "--add-labels" ]] && add_label "$ISSUES/$num" "$a"
    [[ "$prev" == "--remove-labels" ]] && remove_label "$ISSUES/$num" "$a"
    prev="$a"
  done; exit 0
fi
if [[ "${1:-}" == "issues" && "${2:-}" =~ ^[0-9]+$ ]]; then
  num="$2"; printf '{"labels":['; first=1; while IFS= read -r name; do [[ $first -eq 0 ]] && printf ','; printf '{"name":"%s"}' "$name"; first=0; done < "$ISSUES/$num"; printf ']}\n'; exit 0
fi
if [[ "${1:-}" == "issues" ]]; then
  prev=""; label=""; for a in "$@"; do [[ "$prev" == "--labels" ]] && label="$a"; prev="$a"; done
  printf '['; first=1; for f in "$ISSUES"/*; do if grep -Fxq -- "$label" "$f"; then [[ $first -eq 0 ]] && printf ','; printf '{"index":%s}' "$(basename "$f")"; first=0; fi; done; printf ']\n'; exit 0
fi
exit 0
STUB
chmod +x "$WORK/teabin/tea"

run_case() {
  local platform="$1" url="$2" bin="$3"
  local repo="$WORK/repo-$platform" catalog="$WORK/catalog-$platform" issues="$WORK/issues-$platform" log="$WORK/log-$platform"
  mkdir -p "$repo" "$issues"; git -C "$repo" init -q; git -C "$repo" remote add origin "$url"
  if [[ "$platform" == gh ]]; then
    printf 'P0\nfree-label\n' > "$catalog"
  else
    printf 'P0\np0\nfree-label\n' > "$catalog"
  fi
  printf 'P0\nfree-label\n' > "$issues/1"; printf 'P0\n' > "$issues/2"; : > "$log"
  RC=0
  (cd "$repo" && CATALOG="$catalog" ISSUES="$issues" CALL_LOG="$log" PATH="$bin:$PATH" bash "$GITOPS" labels init >/dev/null 2>&1) || RC=$?
  [[ $RC -eq 0 ]] && pass "$platform labels init exits 0" || fail "$platform labels init rc=$RC"
  [[ "$(grep -Eic '^p[0-3]$' "$catalog")" -eq 4 ]] && ! grep -Fxq P0 "$catalog" && pass "$platform catalog canonicalized" || fail "$platform catalog=$(tr '\n' ' ' < "$catalog")"
  grep -Fxq p0 "$issues/1" && ! grep -Fxq P0 "$issues/1" && grep -Fxq free-label "$issues/1" && pass "$platform open issue migrated" || fail "$platform issue1 migration"
  grep -Fxq p0 "$issues/2" && ! grep -Fxq P0 "$issues/2" && pass "$platform closed issue migrated" || fail "$platform issue2 migration"
  if [[ "$platform" != gh ]]; then
    add_line="$(grep -n 'issue update 1 --label p0\|issues edit 1 --add-labels p0' "$log" | head -n1 | cut -d: -f1)"
    remove_line="$(grep -n 'issue update 1 --unlabel P0\|issues edit 1 --remove-labels P0' "$log" | head -n1 | cut -d: -f1)"
    delete_line="$(grep -n 'label delete P0\|labels delete --id' "$log" | tail -n1 | cut -d: -f1)"
    [[ -n "$add_line" && -n "$remove_line" && -n "$delete_line" && $add_line -lt $remove_line && $remove_line -lt $delete_line ]] \
      && pass "$platform migration order add-remove-delete" || fail "$platform migration order"
  fi
  before="$(cat "$catalog"; cat "$issues/1"; cat "$issues/2")"
  (cd "$repo" && CATALOG="$catalog" ISSUES="$issues" CALL_LOG="$log" PATH="$bin:$PATH" bash "$GITOPS" labels init >/dev/null 2>&1) || fail "$platform second init failed"
  after="$(cat "$catalog"; cat "$issues/1"; cat "$issues/2")"
  [[ "$before" == "$after" ]] && pass "$platform second init idempotent" || fail "$platform second init changed state"
}

run_case gh https://github.com/o/r.git "$WORK/ghbin"
run_case glab https://gitlab.com/o/r.git "$WORK/glabbin"
run_case tea https://gitea.example.test/o/r.git "$WORK/teabin"

run_glab_failure() {
  local mode="$1" repo="$WORK/fail-$1" catalog="$WORK/fail-$1.catalog" issues="$WORK/fail-$1.issues" log="$WORK/fail-$1.log"
  mkdir -p "$repo" "$issues"; git -C "$repo" init -q; git -C "$repo" remote add origin https://gitlab.com/o/r.git
  printf 'P0\np0\n' > "$catalog"; printf 'P0\n' > "$issues/9"; : > "$log"
  RC=0
  (cd "$repo" && FAIL_MODE="$mode" CATALOG="$catalog" ISSUES="$issues" CALL_LOG="$log" PATH="$WORK/glabbin:$PATH" bash "$GITOPS" labels init >/dev/null 2>&1) || RC=$?
  [[ $RC -ne 0 ]] && pass "glab $mode failure exits non-zero" || fail "glab $mode failure returned 0"
  grep -Fxq P0 "$catalog" && pass "glab $mode failure preserves repository variant" || fail "glab $mode failure deleted P0"
}

run_glab_failure remove
run_glab_failure verify
run_glab_failure delete

if [[ "$FAILS" -ne 0 ]]; then echo "RESULT FAIL count=$FAILS"; exit 1; fi
echo 'RESULT PASS count=0'
