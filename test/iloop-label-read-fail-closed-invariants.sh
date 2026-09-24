#!/usr/bin/env bash
# Black-box regression checks for Issue #21.
# Exercises glab/tea machine-readable label reads, legacy fallback, and fail-closed updates.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
FAILS=0

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

make_repo() {
  local name="$1" url="$2"
  local dir="${WORK}/${name}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$url"
  printf '%s' "$dir"
}

mkdir -p "$WORK/glabbin"
cat > "$WORK/glabbin/glab" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == "auth" ]] && exit 0
if [[ "${1:-} ${2:-}" == "issue view" ]]; then
  if [[ " $* " == *" --output json "* ]]; then
    case "${GLAB_MODE:-json}" in
      json)
        echo "__ILOOP_LABELS_OK__"
        cat "${LABEL_STATE}"
        exit 0 ;;
      empty)
        echo "__ILOOP_LABELS_OK__"
        exit 0 ;;
      fallback|fail) exit 1 ;;
    esac
  fi
  case "${GLAB_MODE:-json}" in
    fallback)
      printf 'labels:\t%s\n' "$(paste -sd, "${LABEL_STATE}")"
      exit 0 ;;
    fail) exit 1 ;;
    *) printf 'title:\tstub\nlabels:\t%s\n' "$(paste -sd, "${LABEL_STATE}")"; exit 0 ;;
  esac
fi
if [[ "${1:-} ${2:-}" == "issue update" ]]; then
  prev=""
  for arg in "$@"; do
    if [[ "$prev" == "--unlabel" ]]; then
      grep -Fxv -- "$arg" "${LABEL_STATE}" > "${LABEL_STATE}.tmp" || true
      mv "${LABEL_STATE}.tmp" "${LABEL_STATE}"
    elif [[ "$prev" == "--label" ]]; then
      grep -Fxq -- "$arg" "${LABEL_STATE}" 2>/dev/null || printf '%s\n' "$arg" >> "${LABEL_STATE}"
    fi
    prev="$arg"
  done
  exit 0
fi
exit 0
STUB
chmod +x "$WORK/glabbin/glab"

mkdir -p "$WORK/teabin"
cat > "$WORK/teabin/tea" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-} ${2:-}" == "login list" ]] && { echo "https://gitea.example.com user <token>"; exit 0; }
if [[ "${1:-} ${2:-}" == "labels list" ]]; then
  echo "│ ID │ Color │ Name │ Description │"
  i=0
  for name in p0 p1 p2 p3; do i=$((i + 1)); printf '│ %d │ c0ffee │ %s │ stub │\n' "$i" "$name"; done
  exit 0
fi
if [[ "${1:-}" == "issues" && "${2:-}" == "edit" ]]; then
  prev=""
  for arg in "$@"; do
    if [[ "$prev" == "--remove-labels" ]]; then
      grep -Fxv -- "$arg" "${LABEL_STATE}" > "${LABEL_STATE}.tmp" || true
      mv "${LABEL_STATE}.tmp" "${LABEL_STATE}"
    elif [[ "$prev" == "--add-labels" ]]; then
      grep -Fxq -- "$arg" "${LABEL_STATE}" 2>/dev/null || printf '%s\n' "$arg" >> "${LABEL_STATE}"
    fi
    prev="$arg"
  done
  exit 0
fi
if [[ "${1:-}" == "issues" ]]; then
  if [[ " $* " == *" --output json "* && " $* " == *" --fields labels "* ]]; then
    case "${TEA_MODE:-json}" in
      json)
        first=1
        printf '{"labels":['
        while IFS= read -r name; do
          [[ -z "$name" ]] && continue
          [[ "$first" -eq 0 ]] && printf ','
          printf '{"name":"%s"}' "$name"
          first=0
        done < "${LABEL_STATE}"
        printf ']}\n'
        exit 0 ;;
      empty) echo '{"labels":[]}'; exit 0 ;;
      fallback|fail) exit 1 ;;
    esac
  fi
  case "${TEA_MODE:-json}" in
    fallback) printf 'Labels:\t%s\n' "$(paste -sd, "${LABEL_STATE}")"; exit 0 ;;
    fail) exit 1 ;;
    *) printf 'labels:\t%s\n' "$(paste -sd, "${LABEL_STATE}")"; exit 0 ;;
  esac
fi
exit 0
STUB
chmod +x "$WORK/teabin/tea"

GLAB_REPO="$(make_repo glab https://gitlab.example.com/o/r.git)"
TEA_REPO="$(make_repo tea https://gitea.example.com/o/r.git)"

run_priority() {
  local repo="$1" bin="$2" mode_name="$3" mode_value="$4" target="$5"
  RC=0; OUT=""; ERR="${WORK}/err"
  : > "$ERR"
  if [[ "$mode_name" == "GLAB_MODE" ]]; then
    OUT="$(cd "$repo" && LABEL_STATE="$LABEL_STATE" GLAB_MODE="$mode_value" PATH="$bin:$PATH" bash "$GITOPS" --role planner issue priority 1 "$target" 2>"$ERR")" || RC=$?
  else
    OUT="$(cd "$repo" && LABEL_STATE="$LABEL_STATE" TEA_MODE="$mode_value" PATH="$bin:$PATH" bash "$GITOPS" --role planner issue priority 1 "$target" 2>"$ERR")" || RC=$?
  fi
}

echo "=== glab machine-readable and fallback paths ==="
LABEL_STATE="$WORK/glab.state"; export LABEL_STATE
printf 'P0\np0\nRIPER-EXECUTE\n' > "$LABEL_STATE"
run_priority "$GLAB_REPO" "$WORK/glabbin" GLAB_MODE json p1
[[ "$RC" -eq 0 ]] && pass "glab JSON priority update exits 0" || fail "glab JSON rc=$RC"
[[ "$(grep -Eic '^p[0-3]$' "$LABEL_STATE")" -eq 1 ]] && grep -Fxq p1 "$LABEL_STATE" \
  && pass "glab JSON removes uppercase/lowercase duplicates and keeps p1" \
  || fail "glab JSON final labels: $(tr '\n' ' ' < "$LABEL_STATE")"
grep -Fxq RIPER-EXECUTE "$LABEL_STATE" && pass "glab preserves cross-family label" || fail "glab removed cross-family label"

printf 'P3\n' > "$LABEL_STATE"
run_priority "$GLAB_REPO" "$WORK/glabbin" GLAB_MODE fallback p0
[[ "$RC" -eq 0 ]] && grep -Fxq p0 "$LABEL_STATE" && ! grep -Fxq P3 "$LABEL_STATE" \
  && pass "glab verified text fallback removes P3" || fail "glab fallback failed"

: > "$LABEL_STATE"
run_priority "$GLAB_REPO" "$WORK/glabbin" GLAB_MODE empty p2
[[ "$RC" -eq 0 ]] && grep -Fxq p2 "$LABEL_STATE" && pass "glab valid empty labels succeeds" || fail "glab empty labels failed"

printf 'P0\n' > "$LABEL_STATE"
run_priority "$GLAB_REPO" "$WORK/glabbin" GLAB_MODE fail p1
[[ "$RC" -ne 0 ]] && pass "glab unreadable labels fails closed" || fail "glab unreadable labels rc=0"
grep -Fxq P0 "$LABEL_STATE" && ! grep -Fxq p1 "$LABEL_STATE" && pass "glab failure does not add p1" || fail "glab failure mutated target labels"
grep -q '不能保证同族标签排他' "$ERR" && pass "glab failure explains exclusivity risk" || fail "glab failure missing diagnostic"

echo "=== tea machine-readable and fallback paths ==="
LABEL_STATE="$WORK/tea.state"; export LABEL_STATE
printf 'P0\np0\nRIPER-EXECUTE\n' > "$LABEL_STATE"
run_priority "$TEA_REPO" "$WORK/teabin" TEA_MODE json p1
[[ "$RC" -eq 0 ]] && pass "tea JSON priority update exits 0" || fail "tea JSON rc=$RC"
[[ "$(grep -Eic '^p[0-3]$' "$LABEL_STATE")" -eq 1 ]] && grep -Fxq p1 "$LABEL_STATE" \
  && pass "tea JSON removes uppercase/lowercase duplicates and keeps p1" \
  || fail "tea JSON final labels: $(tr '\n' ' ' < "$LABEL_STATE")"
grep -Fxq RIPER-EXECUTE "$LABEL_STATE" && pass "tea preserves cross-family label" || fail "tea removed cross-family label"

printf 'P3\n' > "$LABEL_STATE"
run_priority "$TEA_REPO" "$WORK/teabin" TEA_MODE fallback p0
[[ "$RC" -eq 0 ]] && grep -Fxq p0 "$LABEL_STATE" && ! grep -Fxq P3 "$LABEL_STATE" \
  && pass "tea verified text fallback accepts Labels field" || fail "tea fallback failed"

: > "$LABEL_STATE"
run_priority "$TEA_REPO" "$WORK/teabin" TEA_MODE empty p2
[[ "$RC" -eq 0 ]] && grep -Fxq p2 "$LABEL_STATE" && pass "tea valid empty labels succeeds" || fail "tea empty labels failed"

printf 'P0\n' > "$LABEL_STATE"
run_priority "$TEA_REPO" "$WORK/teabin" TEA_MODE fail p1
[[ "$RC" -ne 0 ]] && pass "tea unreadable labels fails closed" || fail "tea unreadable labels rc=0"
grep -Fxq P0 "$LABEL_STATE" && ! grep -Fxq p1 "$LABEL_STATE" && pass "tea failure does not add p1" || fail "tea failure mutated target labels"
grep -q '不能保证同族标签排他' "$ERR" && pass "tea failure explains exclusivity risk" || fail "tea failure missing diagnostic"

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
