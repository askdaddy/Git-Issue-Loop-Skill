#!/usr/bin/env bash
# Black-box contract checks: install backups/staging must live outside skills/.
# Hidden prefixes under ~/.agents/skills/ are not enough — some Agent hosts scan
# dot directories and register a second /iloop. Long-lived backups must not use
# /tmp (conflicts with keep-latest-one).
# Run from repository root: bash test/iloop-backup-location-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${ROOT}/SKILL.md"
INSTALL="${ROOT}/INSTALL.md"
MANIFEST="${ROOT}/skill-manifest.json"
README="${ROOT}/README.md"
README_CN="${ROOT}/README_CN.md"
FAILS=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

assert_file() {
  if [[ ! -f "$1" ]]; then
    echo "FAIL missing file: $1"
    FAILS=$((FAILS + 1))
  else
    echo "PASS exists $1"
  fi
}

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

echo "=== step 0 target files exist ==="
assert_file "$INSTALL"
assert_file "$MANIFEST"
assert_file "$SKILL"
assert_file "$README"
assert_file "$README_CN"

echo "=== step 1 manifest: backup/staging outside skills/ ==="
assert_grep "$MANIFEST" '"backupDir": "~/\.agents/backups"' "manifest backupDir is ~/.agents/backups"
assert_grep "$MANIFEST" '"backupPrefix": "iloop\.backup-"' "manifest backupPrefix has no skills/ hidden prefix"
assert_grep "$MANIFEST" '"stagingDir": "\$\{TMPDIR:-/tmp\}"' "manifest stagingDir is TMPDIR"
assert_grep "$MANIFEST" '"stagingPrefix": "iloop\.staging-"' "manifest stagingPrefix has no skills/ hidden prefix"
assert_no_grep "$MANIFEST" '"backupPrefix": "\.iloop\.backup-"' "manifest does not keep hidden backupPrefix"
assert_no_grep "$MANIFEST" '"stagingPrefix": "\.iloop\.staging-"' "manifest does not keep hidden stagingPrefix"
assert_grep "$MANIFEST" '"backupRetention": "keep-latest-one"' "retention keeps only the latest backup"
assert_grep "$MANIFEST" '"backupRetentionCount": 1' "retention count is one"

echo "=== step 2 INSTALL.md: new locations + leftover migration ==="
assert_grep "$INSTALL" '~/\.agents/backups/iloop\.backup-' "INSTALL backups go to ~/.agents/backups"
assert_grep "$INSTALL" '\$\{TMPDIR:-/tmp\}/iloop\.staging-' "INSTALL staging goes to TMPDIR"
assert_grep "$INSTALL" '禁止.*放在.*~/\.agents/skills' "INSTALL forbids staging under skills/"
assert_grep "$INSTALL" '不得把长期备份放到 `/tmp`|不得把长期备份放到 `/tmp` 或 `\$TMPDIR`' "INSTALL forbids long-lived backups in tmp"
assert_grep "$INSTALL" '隐藏前缀.*不足以|点目录也当成技能' "INSTALL explains hidden prefix is insufficient"
assert_grep "$INSTALL" 'SKILLS/\.iloop\.backup-\*|\$SKILLS/\.iloop\.backup-\*' "INSTALL migrates leftover hidden backups out of skills/"
assert_grep "$INSTALL" 'SKILLS/\.iloop\.staging-\*|\$SKILLS/\.iloop\.staging-\*' "INSTALL migrates leftover hidden staging out of skills/"
assert_grep "$INSTALL" 'BACKUP_DIR="\$\{HOME\}/\.agents/backups"' "migration snippet writes to ~/.agents/backups"
assert_grep "$INSTALL" 'STAGING_DIR="\$\{TMPDIR:-/tmp\}"' "migration snippet writes leftover staging to TMPDIR"
assert_grep "$INSTALL" 'base="\$\{base#\.\}"' "strips leftover hidden prefix when renaming"
assert_no_grep "$INSTALL" 'tgt="\$BASE/\.\$\{d##\*/\}"' "migration no longer hides in-place under skills/"
assert_grep "$INSTALL" '回滚.*~/\.agents/backups/iloop\.backup-' "rollback lists ~/.agents/backups"
assert_no_grep "$INSTALL" '将旧目录重命名为 `~/\.agents/skills/' "new backups are not renamed into skills/"
assert_grep "$INSTALL" '升级成功.*只保留.*iloop\.backup-' "INSTALL keeps only the latest backup after success"
assert_grep "$INSTALL" '验证失败.*不得清理|任一步失败.*保留全部备份' "INSTALL forbids pruning after failed verification"
assert_grep "$INSTALL" '不跟随符号链接' "INSTALL does not follow symlinks during pruning"
assert_grep "$INSTALL" '<!-- backup-prune:start -->' "INSTALL exposes an executable prune snippet"

echo "=== step 3 docs mention the outside-skills backup path ==="
assert_grep "$SKILL" '~/\.agents/backups/iloop\.backup-' "SKILL.md backup path is outside skills/"
assert_grep "$SKILL" '\$\{TMPDIR:-/tmp\}/iloop\.staging-' "SKILL.md staging path is TMPDIR"
assert_no_grep "$SKILL" '~/\.agents/skills/\.iloop\.backup-' "SKILL.md does not keep skills/ hidden backups"
assert_grep "$README" '~/\.agents/backups/iloop\.backup-' "README backup path is outside skills/"
assert_no_grep "$README" '~/\.agents/skills/\.iloop\.backup-' "README does not keep skills/ hidden backups"
assert_grep "$README_CN" '~/\.agents/backups/iloop\.backup-' "README_CN backup path is outside skills/"
assert_no_grep "$README_CN" '~/\.agents/skills/\.iloop\.backup-' "README_CN does not keep skills/ hidden backups"

echo "=== step 4 prune snippet behavior ==="
SNIPPET="$WORK/prune.sh"
awk '/<!-- backup-prune:start -->/{f=1;next} /<!-- backup-prune:end -->/{f=0} f' "$INSTALL" | sed '/^```/d' > "$SNIPPET"
assert_file "$SNIPPET"

PRUNE="$WORK/backups"
mkdir -p "$PRUNE/iloop.backup-20260101-000001" \
         "$PRUNE/iloop.backup-20260102-000002" \
         "$PRUNE/iloop.backup-20260103-000003" \
         "$PRUNE/other.backup-keep"
touch "$PRUNE/iloop.backup-file"
ln -s "$PRUNE/iloop.backup-20260103-000003" "$PRUNE/iloop.backup-symlink"
KEEP="$PRUNE/iloop.backup-20260103-000003"

RC=0
OUT="$(ILOOP_BACKUP_DIR="$PRUNE" ILOOP_BACKUP_KEEP="$KEEP" bash "$SNIPPET" 2>&1)" || RC=$?
if [[ "$RC" -eq 0 ]]; then
  pass "prune snippet exits 0 on a valid backup set"
else
  fail "prune snippet exited $RC on a valid backup set"
  echo "$OUT"
fi
if [[ -d "$KEEP" ]]; then
  pass "current backup is retained"
else
  fail "current backup was removed"
fi
if [[ ! -e "$PRUNE/iloop.backup-20260101-000001" && ! -e "$PRUNE/iloop.backup-20260102-000002" ]]; then
  pass "older backups are removed"
else
  fail "older backups were not removed"
fi
if [[ -L "$PRUNE/iloop.backup-symlink" ]]; then
  pass "symlink backup is skipped"
else
  fail "symlink backup was followed or removed"
fi
if [[ -e "$PRUNE/other.backup-keep" && -e "$PRUNE/iloop.backup-file" ]]; then
  pass "non-matching and non-directory entries are retained"
else
  fail "non-matching or non-directory entries were removed"
fi
if printf '%s' "$OUT" | grep -Fq 'backup_prune_removed=2 failed=0'; then
  pass "prune snippet reports removed/failed counts"
else
  fail "prune snippet summary is missing or wrong"
  echo "$OUT"
fi

RC=0
OUT="$(ILOOP_BACKUP_DIR="$PRUNE" ILOOP_BACKUP_KEEP="$WORK/not-a-backup" bash "$SNIPPET" 2>&1)" || RC=$?
if [[ "$RC" -ne 0 ]]; then
  pass "prune snippet rejects a KEEP path outside the backup prefix"
else
  fail "prune snippet accepted an invalid KEEP path"
fi
if [[ -d "$KEEP" ]]; then
  pass "invalid KEEP leaves the current backup untouched"
else
  fail "invalid KEEP removed the current backup"
fi

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
