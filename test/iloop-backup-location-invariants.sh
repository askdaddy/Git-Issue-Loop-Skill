#!/usr/bin/env bash
# Black-box contract checks: install backups/staging must live outside skills/.
# Hidden prefixes under ~/.agents/skills/ are not enough — some Agent hosts scan
# dot directories and register a second /iloop. Long-lived backups must not use
# /tmp (conflicts with keep-all-until-user-deletes).
# Run from repository root: bash test/iloop-backup-location-invariants.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="${ROOT}/SKILL.md"
INSTALL="${ROOT}/INSTALL.md"
MANIFEST="${ROOT}/skill-manifest.json"
README="${ROOT}/README.md"
README_CN="${ROOT}/README_CN.md"
FAILS=0

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
assert_grep "$MANIFEST" '"backupRetention": "keep-all-until-user-deletes"' "retention still keep-all-until-user-deletes"

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

echo "=== step 3 docs mention the outside-skills backup path ==="
assert_grep "$SKILL" '~/\.agents/backups/iloop\.backup-' "SKILL.md backup path is outside skills/"
assert_grep "$SKILL" '\$\{TMPDIR:-/tmp\}/iloop\.staging-' "SKILL.md staging path is TMPDIR"
assert_no_grep "$SKILL" '~/\.agents/skills/\.iloop\.backup-' "SKILL.md does not keep skills/ hidden backups"
assert_grep "$README" '~/\.agents/backups/iloop\.backup-' "README backup path is outside skills/"
assert_no_grep "$README" '~/\.agents/skills/\.iloop\.backup-' "README does not keep skills/ hidden backups"
assert_grep "$README_CN" '~/\.agents/backups/iloop\.backup-' "README_CN backup path is outside skills/"
assert_no_grep "$README_CN" '~/\.agents/skills/\.iloop\.backup-' "README_CN does not keep skills/ hidden backups"

echo "=== C1 guard: no business-script changes ==="
if git -C "$ROOT" diff HEAD -- scripts/git-ops.sh | grep -q .; then
  echo "FAIL git-ops.sh has a diff vs HEAD (C1)"
  FAILS=$((FAILS + 1))
else
  echo "PASS git-ops.sh unchanged vs HEAD (C1)"
fi

if [[ "$FAILS" -ne 0 ]]; then
  echo "RESULT FAIL count=$FAILS"
  exit 1
fi
echo "RESULT PASS count=0"
exit 0
