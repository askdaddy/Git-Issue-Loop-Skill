# Git 安装 `iloop`

`iloop` 是一个静态 Skill 仓库：安装过程只通过 Git 获取并登记文件，不下载或执行远程安装脚本。默认目标目录为 `~/.agents/skills/iloop`。

## 给 Agent 的一句话

> 请从 `https://github.com/askdaddy/Git-Issue-Loop-Skill.git` 安装最新版 `iloop` 到 `~/.agents/skills/iloop`；若已有同源安装则安全更新，若目录非同源或存在本地修改则停止并报告；完成后验证 `SKILL.md`。

用户无需指定版本。“最新版”是**远端最高的稳定 SemVer 标签**：只接受 `vX.Y.Z`，不接受 `main`、分支名或 `vX.Y.Z-alpha.1`、`vX.Y.Z-beta.1`、`vX.Y.Z-rc.1` 等预发布标签。

## Agent 安装协议

Agent 收到上述请求后，必须按此协议执行；不得将“最新版”简化为直接检出 `main`。

1. 确认 Git 可用，并创建 `~/.agents/skills/`（若不存在）。
2. 从 `https://github.com/askdaddy/Git-Issue-Loop-Skill.git` 拉取 tags，选择最高的符合 `^v[0-9]+\.[0-9]+\.[0-9]+$` 的 tag。没有稳定 tag 时失败并报告，不得回退到 `main`。
3. 将该 tag 克隆到 `~/.agents/skills/.iloop.staging-<随机值>`，以 detached HEAD 检出；记录 `git rev-parse HEAD` 的 commit SHA。
4. 读取 `skill-manifest.json`，确认仓库 URL、`SKILL.md`、`scripts/git-ops.sh`、角色文件、模板和 CLI 指南均存在；确认 `SKILL.md` 的 frontmatter `name` 是 `iloop`，且 `scripts/git-ops.sh` 可执行。
5. 若 `~/.agents/skills/iloop` 不存在，切换 staging 目录为目标目录。若已存在，先检查其 `remote.origin.url` 是否等于清单中的仓库 URL、工作区是否干净：
   - 同源且干净：将旧目录重命名为 `iloop.backup-<时间戳>`，再切换 staging 目录。
   - 非同源或有本地修改：停止，不覆盖、不删除，并报告原因和目录路径。
6. 最后报告：目标目录、解析到的 tag、commit SHA，以及验证结果。仅当目标项目实际运行 `/iloop` 时，才在那个项目仓库根目录执行 `./scripts/git-ops.sh doctor`。

建议先完成 staging 校验再切换目录；任一步失败都保留现有的有效安装。安装协议不使用 `git reset --hard`、`git clean` 或对既有目录的递归删除。

## 更新与回滚

更新使用相同的一句话请求。Agent 重新解析最新稳定 tag，只有在它与已安装 tag 不同时才执行 staging → 验证 → 备份 → 切换。

回滚时，Agent 应列出 `iloop.backup-*` 目录供用户选择；未经用户明确指定，不能删除备份，也不能自动回滚。

## 发行者约定

- `main` 是开发分支，不能作为默认安装源。
- 每个稳定发行版创建一个不可重用的 `vX.Y.Z` tag，并发布对应的 GitHub Release，用于承载变更说明。
- 预发布版必须带 SemVer 预发布后缀，默认安装器会跳过它们。
- 推荐对稳定 tag 签名。高安全环境可在本地通过 `git tag -v <tag>` 验签；验签失败时不安装。
