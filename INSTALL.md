# Git 安装 `iloop`

`iloop` 是一个静态 Skill 仓库：安装过程只通过 Git 获取并登记文件，不下载或执行远程安装脚本。默认目标目录为 `~/.agents/skills/iloop`。

## 给 Agent 的一句话

> 请从 `https://github.com/askdaddy/Git-Issue-Loop-Skill.git` 安装最新版 `iloop` 到 `~/.agents/skills/iloop`；若已有同源安装则安全更新，若目录非同源或存在本地修改则停止并报告；完成后验证 `SKILL.md`。

用户无需指定版本。“最新版”是**远端最高的稳定 SemVer 标签**：只接受 `vX.Y.Z`，不接受 `main`、分支名或 `vX.Y.Z-alpha.1`、`vX.Y.Z-beta.1`、`vX.Y.Z-rc.1` 等预发布标签。

## Agent 安装协议

Agent 收到上述请求后，必须按此协议执行；不得将“最新版”简化为直接检出 `main`。

**执行环境（必须）**：本协议的所有 shell 逻辑必须在 **bash** 下执行——把逻辑写进临时 `.sh` 跑 `bash file.sh`，或用 `bash -c '<逻辑>'`；**不得**依赖宿主默认 shell。现代 macOS 默认 shell 是 zsh（亦有 fish），缺 `shopt`、`nullglob` 等 bash 内建，直接跑会 `command not found` 而中断协议（本次约定即源于一次实测：迁移循环用 `shopt -s nullglob` 在 zsh 下退出码 127）。随附脚本已带 `#!/usr/bin/env bash`，经 `./script.sh` 调用恒在 bash 下运行、天然安全。

1. 确认 Git 可用，并创建 `~/.agents/skills/` 与 `~/.agents/backups/`（若不存在）。
2. 从 `https://github.com/askdaddy/Git-Issue-Loop-Skill.git` 拉取 tags，选择最高的符合 `^v[0-9]+\.[0-9]+\.[0-9]+$` 的 tag。没有稳定 tag 时失败并报告，不得回退到 `main`。
3. 将该 tag 克隆到 `${TMPDIR:-/tmp}/iloop.staging-<随机值>`（**禁止**放在 `~/.agents/skills/` 下，含隐藏前缀；部分宿主会把 `skills/` 里的点目录也当成技能扫描），以 detached HEAD 检出；记录 `git rev-parse HEAD` 的 commit SHA。
   从步骤 3 完成后起，必须改读 staging 目录内的 `INSTALL.md` 与 `skill-manifest.json`，并按那份协议执行步骤 4 及之后的备份与切换；不得使用 live 目录 `~/.agents/skills/iloop` 或会话开始时缓存的旧协议来决定 `backupDir` / `backupPrefix` / `stagingDir`、残留迁移或是否切换。
4. 读取 `skill-manifest.json`，确认仓库 URL、`SKILL.md`、`scripts/git-ops.sh`、角色文件、模板和 CLI 指南均存在；确认 `SKILL.md` 的 frontmatter `name` 是 `iloop`，且 `scripts/git-ops.sh` 可执行。
5. 若 `~/.agents/skills/iloop` 不存在，将 staging 目录 `mv` 为目标目录。若已存在，先检查其 `remote.origin.url` 是否等于清单中的仓库 URL、工作区是否干净：
   - 同源且干净：将旧目录重命名为 `~/.agents/backups/iloop.backup-<时间戳>`，再将 staging `mv` 为目标目录。
   - 非同源或有本地修改：停止，不覆盖、不删除，并报告原因和目录路径。
   备份必须在 `~/.agents/skills/` **之外**。不得把长期备份放到 `/tmp` 或 `$TMPDIR`（系统会清理临时目录，与 `backupRetention: keep-all-until-user-deletes` 冲突）。隐藏前缀（`.iloop.backup-*`）不足以避免重复 `/iloop`：部分 Agent 仍会扫描点目录。
6. 最后报告：目标目录、解析到的 tag、commit SHA、备份路径（若有），以及验证结果。报告完成后必须提醒用户刷新 Agent 宿主会话。仅当目标项目实际运行 `/iloop` 时，才在那个项目仓库根目录执行 `./scripts/git-ops.sh doctor`。

建议先完成 staging 校验再切换目录；任一步失败都保留现有的有效安装。安装协议不使用 `git reset --hard`、`git clean` 或对既有目录的递归删除。

## 更新与回滚

更新使用相同的一句话请求。Agent 重新解析最新稳定 tag。已安装版本判定仅用于是否需要更新，不得当作 `backupPrefix` 来源：在 live 目录 `~/.agents/skills/iloop` 执行 `git describe --tags --exact-match`；若失败，则比较该目录 `git rev-parse HEAD` 与远端目标 tag 的 commit SHA。两者都失败则停止并报告，不得假设需要或不需要更新。禁止把 `skill-manifest.json` 的 `skill.version` 当作已安装 tag。只有在判定出的已安装 tag（或 SHA）与目标 tag 不同时才执行 staging → 验证 → 备份 → 切换。

在备份 → 切换完成前（以及每次合规更新时），必须把仍留在 `~/.agents/skills/` 下的旧备份与残留 staging **迁出该目录**（含隐藏前缀）。仅改名；不删除；不修改备份内部文件。若目标路径已存在，停止并报告该路径，不覆盖、不删除。

迁出对象与目标：

- `$SKILLS/iloop.backup-*` 与 `$SKILLS/.iloop.backup-*` → `~/.agents/backups/iloop.backup-<时间戳>`（去掉可选的点前缀）
- `$SKILLS/iloop.staging-*` 与 `$SKILLS/.iloop.staging-*` → `${TMPDIR:-/tmp}/iloop.staging-<原后缀>`（去掉可选的点前缀）

迁移写法**不得依赖 bash-only 的 `shopt -s nullglob`**（zsh 无此内建）；改用存在性检查处理「无匹配」，在 bash 下执行（见「Agent 安装协议 · 执行环境」）：

```bash
SKILLS="${HOME}/.agents/skills"
BACKUP_DIR="${HOME}/.agents/backups"
STAGING_DIR="${TMPDIR:-/tmp}"
mkdir -p "$BACKUP_DIR"

for d in "$SKILLS"/iloop.backup-* "$SKILLS"/.iloop.backup-*; do
  [ -e "$d" ] || continue                        # 无匹配时 glob 保留字面量，靠存在性检查跳过
  base="${d##*/}"
  base="${base#.}"                               # .iloop.backup-TS → iloop.backup-TS
  tgt="$BACKUP_DIR/$base"
  if [ -e "$tgt" ]; then echo "ABORT: $tgt 已存在，停止（不覆盖、不删除）"; exit 1; fi
  mv "$d" "$tgt"                                # 仅改名，不删除
done

for d in "$SKILLS"/iloop.staging-* "$SKILLS"/.iloop.staging-*; do
  [ -e "$d" ] || continue
  base="${d##*/}"
  base="${base#.}"
  tgt="$STAGING_DIR/$base"
  if [ -e "$tgt" ]; then echo "ABORT: $tgt 已存在，停止（不覆盖、不删除）"; exit 1; fi
  mv "$d" "$tgt"
done
```

回滚时，Agent 必须列出 `~/.agents/backups/iloop.backup-*`；若 `~/.agents/skills/` 下仍存在 `iloop.backup-*` 或 `.iloop.backup-*`，也一并列出，供用户选择。备份默认全部保留。未经用户明确指定，不能删除备份，也不能自动回滚。

## 启动时的版本检查

`/iloop` 在目标项目 `doctor` **之前**、每会话一次，于**当前加载的 `SKILL.md` 所在目录**（默认 `~/.agents/skills/iloop`）运行 `scripts/check-update.sh`。比较本地 `git describe --tags --exact-match`（失败则用 HEAD SHA）与 `skill-manifest.json` 里 `distribution.repository` 的最高稳定 `vX.Y.Z` tag。

- 有更高稳定版：向用户展示本地 tag 与远端 latest，询问是否按上文一句话升级。**Agent 不得自行切换安装。**
- 检查失败（网络、非 git、无稳定 tag）不阻止后续 doctor 与闭环。
- 禁止用目标项目的 `git remote` 作为检查源；禁止把 `skill.version` 当作已安装 tag。

## 发行者约定

- `main` 是开发分支，不能作为默认安装源。
- 每个稳定发行版创建一个不可重用的 `vX.Y.Z` tag，并发布对应的 GitHub Release，用于承载变更说明。
- 改动 `INSTALL.md` 或 `skill-manifest.json` 的 `installation` 段必须随下一个新的稳定 `vX.Y.Z` tag 发布；未打 tag 前，「安装最新版」不会拿到该协议变更。
- 预发布版必须带 SemVer 预发布后缀，默认安装器会跳过它们。
- 推荐对稳定 tag 签名。高安全环境可在本地通过 `git tag -v <tag>` 验签；验签失败时不安装。
