#!/usr/bin/env bash
# Black-box regression checks for Issue #16.
# Verifies tea registry detection drains large output without SIGPIPE false-negatives.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BIN="${WORK}/bin"
mkdir -p "$BIN"
cat > "${BIN}/tea" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-} ${2:-}" == "login list" ]]; then
  echo "https://registry-only.example  gitea  user  <token>"
  seq 1 20000 | sed 's/^/padding-row-/'
fi
STUB
chmod +x "${BIN}/tea"

make_repo() {
  local name="$1" url="$2"
  local dir="${WORK}/${name}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" remote add origin "$url"
  printf '%s' "$dir"
}

REGISTERED="$(make_repo registered https://registry-only.example/o/r.git)"
UNREGISTERED="$(make_repo unregistered https://other-only.example/o/r.git)"
FAILS=0

echo "=== registered host with large tea output ==="
for i in $(seq 1 20); do
  out=""
  rc=0
  out="$(cd "$REGISTERED" && PATH="$BIN:$PATH" bash "$GITOPS" platform 2>/dev/null)" || rc=$?
  result="$(printf '%s\n' "$out" | tail -1)"
  if [[ "$rc" -eq 0 && "$result" == "tea" ]]; then
    echo "PASS run ${i}: registered host -> tea"
  else
    echo "FAIL run ${i}: rc=${rc} result='${result}'"
    FAILS=$((FAILS + 1))
  fi
done

echo "=== unregistered host remains rejected ==="
out=""
rc=0
out="$(cd "$UNREGISTERED" && PATH="$BIN:$PATH" bash "$GITOPS" platform 2>/dev/null)" || rc=$?
result="$(printf '%s\n' "$out" | tail -1)"
if [[ "$rc" -ne 0 && "$result" != "tea" && "$result" != "gh" ]]; then
  echo "PASS unregistered host rejected (rc=${rc}, out='${out}')"
else
  echo "FAIL unregistered host accepted or routed (rc=${rc}, result='${result}')"
  FAILS=$((FAILS + 1))
fi

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=${FAILS}"
  exit 1
fi
echo "RESULT PASS count=0"
