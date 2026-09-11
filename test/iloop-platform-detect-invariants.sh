#!/usr/bin/env bash
# Black-box contract checks for Issue #10 (self-hosted platform detection).
# Verifies detect_platform identifies the hosting system before routing to a CLI,
# and never blindly falls back to gh for unrecognized (self-hosted) hosts.
# Run from repository root: bash test/iloop-platform-detect-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITOPS="${ROOT}/scripts/git-ops.sh"
CLI_SETUP="${ROOT}/references/cli-setup.md"
FAILS=0

assert_grep() {
  local file="$1" pat="$2" msg="$3"
  if ! grep -Eq -- "$pat" "$file"; then
    echo "FAIL $msg"
    echo "  file=$file pattern=$pat"
    FAILS=$((FAILS + 1))
  else
    echo "PASS $msg"
  fi
}

assert_no_grep() {
  local file="$1" pat="$2" msg="$3"
  if grep -Eq -- "$pat" "$file"; then
    echo "FAIL $msg"
    echo "  file=$file forbidden=$pat"
    grep -nE -- "$pat" "$file" | head -n 5
    FAILS=$((FAILS + 1))
  else
    echo "PASS $msg"
  fi
}

# probe_platform <remote-url>: run `git-ops.sh platform` inside a throwaway repo
# whose origin is <remote-url>. Sets PROBE_RC / PROBE_OUT (last stdout line) / PROBE_ERR.
# Black-box: exercises the same code path Agent uses, without touching the real repo.
PROBE_RC=0; PROBE_OUT=""; PROBE_ERR=""
probe_platform() {
  local url="$1" d errfile
  d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" remote add origin "$url"
  errfile="${d}/err"
  PROBE_RC=0
  PROBE_OUT="$(cd "$d" && bash "$GITOPS" platform 2>"$errfile")" || PROBE_RC=$?
  PROBE_OUT="$(printf '%s' "$PROBE_OUT" | tail -1)"
  PROBE_ERR="$(cat "$errfile" 2>/dev/null || true)"
  rm -rf "$d"
}

# assert_platform <url> <expected-cli> <msg>: Layer-1 heuristics are deterministic and
# require neither the CLI to be installed nor authed (platform subcommand does not gate on auth).
assert_platform() {
  local url="$1" want="$2" msg="$3"
  probe_platform "$url"
  if [[ "$PROBE_RC" -eq 0 && "$PROBE_OUT" == "$want" ]]; then
    echo "PASS $msg ($url -> $PROBE_OUT)"
  else
    echo "FAIL $msg ($url -> rc=$PROBE_RC out='$PROBE_OUT' want='$want')"
    FAILS=$((FAILS + 1))
  fi
}

echo "=== step 1a: Layer-1 hostname heuristics (no regression, auth-independent) ==="
assert_platform "https://github.com/o/r.git"       "gh"   "github.com -> gh"
assert_platform "git@github.com:o/r.git"           "gh"   "github.com (ssh form) -> gh"
assert_platform "https://github.corp.com/o/r.git"  "gh"   "GitHub Enterprise github.corp.com -> gh"
assert_platform "https://gitlab.com/o/r.git"       "glab" "gitlab.com -> glab"
assert_platform "https://gitlab.corp.com/o/r.git"  "glab" "self-hosted *gitlab* -> glab"
assert_platform "https://gitea.corp.com/o/r.git"   "tea"  "self-hosted *gitea* -> tea"
assert_platform "https://forgejo.internal/o/r.git" "tea"  "*forgejo* -> tea"
assert_platform "https://codeberg.org/o/r.git"     "tea"  "codeberg.org -> tea"

echo "=== step 1b: Layer-3 unknown self-hosted host must NOT route to gh ==="
# A .invalid host is guaranteed to match no heuristic and be claimed by no CLI,
# so this is deterministic across machines regardless of installed/authed CLIs.
probe_platform "https://selfhost-nonmatch.invalid/o/r.git"
if [[ "$PROBE_RC" -ne 0 ]]; then
  echo "PASS unknown host exits non-zero (rc=$PROBE_RC)"
else
  echo "FAIL unknown host must exit non-zero, got rc=0 (out='$PROBE_OUT')"
  FAILS=$((FAILS + 1))
fi
if printf '%s' "$PROBE_OUT" | grep -qx 'gh'; then
  echo "FAIL unknown host routed to gh (stdout='$PROBE_OUT')"
  FAILS=$((FAILS + 1))
else
  echo "PASS unknown host does not route to gh (stdout='$PROBE_OUT')"
fi
if printf '%s' "$PROBE_ERR" | grep -q '无法识别自建实例平台'; then
  echo "PASS unknown host prints self-host guidance on stderr"
else
  echo "FAIL unknown host missing self-host guidance on stderr"
  FAILS=$((FAILS + 1))
fi
if printf '%s' "$PROBE_ERR" | grep -q 'glab auth login --hostname selfhost-nonmatch.invalid'; then
  echo "PASS guidance names glab auth for the unrecognized host"
else
  echo "FAIL guidance missing 'glab auth login --hostname <host>'"
  FAILS=$((FAILS + 1))
fi

echo "=== step 1c: detection helpers wired in (structural evidence) ==="
assert_grep "$GITOPS" 'detect_by_registry' "detect_by_registry helper present"
assert_grep "$GITOPS" 'print_selfhost_guide' "print_selfhost_guide helper present"
assert_grep "$GITOPS" '\*github\*\)' "GHE fast-path (*github*) present"

echo "=== step 2: docs consistent with layered detection ==="
assert_no_grep "$GITOPS" '识别平台，回退到 gh|按已安装 CLI 依次兜底' "old blind gh fallback removed from git-ops.sh"
assert_no_grep "$GITOPS" '盲选' "no '盲选' phrasing left in git-ops.sh"
assert_no_grep "$CLI_SETUP" '回退到 gh|盲选' "no '回退到 gh'/'盲选' in cli-setup.md"
assert_grep "$CLI_SETUP" '授权注册表|自建实例' "cli-setup.md documents self-hosted registry routing"

echo "=== out of scope: fix is committed (no uncommitted diff on git-ops.sh) ==="
if git -C "$ROOT" diff HEAD -- scripts/git-ops.sh | grep -q .; then
  echo "FAIL scripts/git-ops.sh has uncommitted diff"
  FAILS=$((FAILS + 1))
else
  echo "PASS git-ops.sh clean vs HEAD"
fi

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
