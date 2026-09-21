# CLI 安装与授权指南（gh / glab / tea）

> 本 Skill 的 **CLI 优先原则**：所有 Issue 操作一律优先使用本地官方 CLI —— GitHub 用 `gh`、GitLab 用 `glab`、Gitea/Forgejo 用 `tea`，由 `scripts/git-ops.sh` 依据 `git remote -v` 自动路由。
> **禁止**改用 REST API + 手写 token、网页点击或其他方式绕行。
>
> 支持平台：**macOS** 与 **Windows**（Windows 必须在 Git Bash 中运行脚本，不支持 CMD / PowerShell）。

## 0. 一键自检

```bash
./scripts/git-ops.sh doctor
```

输出会依次给出：运行环境 → 路由到的 CLI → 安装状态 → 授权状态 → 标签体系就绪（14/14）。
任一项不就绪时，脚本会打印对应的安装/授权指南（或缺失标签清单 + `labels init` 提示）并以 `exit 1` 中止——此时 **Agent 必须停止 RIPER 循环，把指南原样呈现给用户**，等用户完成后再继续。

单独查看路由结果：

```bash
./scripts/git-ops.sh platform    # 输出 gh / glab / tea
```

### 平台识别与自建实例路由

`git-ops.sh` 按 `git remote` 主机名**分层识别**平台，再路由到对应 CLI：

1. **主机名启发式（快路径）**：`github.com` 或含 `github`（GitHub Enterprise）→ `gh`；`gitlab.com` 或含 `gitlab` → `glab`；含 `gitea` / `forgejo` 或 `codeberg.org` → `tea`。
2. **授权注册表**（主机名无关键字时，自建实例常见）：查询各**已安装** CLI 是否已授权该 host —— `gh` / `glab` 用 `auth status --hostname <host>`、`tea` 用 `login list`，命中哪个就路由到哪个。
3. **无法判定则显式失败**：脚本 `exit 1` 并打印该 host 的授权指引，**绝不默认路由到 `gh`**。

> **自建实例必须先授权对应 CLI**：自建 GitLab 用 `glab auth login --hostname <host>`、自建 Gitea/Forgejo 用 `tea login add`（实例 URL 填 `https://<host>`）、GitHub Enterprise 用 `gh auth login --hostname <host>`。授权后脚本才能据注册表识别归属。**用 `gh` 访问自建 GitLab/Gitea 一定失败**——它们不是同一套 API。

### 标签体系初始化

**为何需要**：`issue priority` / `issue status` / `issue retry` 都依赖平台上已存在对应标签；标签缺失时这些命令会因平台报 `'p0' not found`（或同类「标签不存在」错误）而 `exit 1`，导致闭环在第一次设置优先级/状态时就卡死（bootstrap 死锁）。

**命令**（新仓库克隆后、进入 RIPER 循环前执行一次）：

```bash
./scripts/git-ops.sh labels init
```

- **幂等**：标签不存在则创建，已存在则更新颜色与描述；重复执行安全，不会报错也不会产生重复标签（Gitea 对非 scoped 名称不查重，脚本以「先查存在再创建」保证幂等）。
- **doctor 会检查**：`./scripts/git-ops.sh doctor` 的最后一步会比对远端标签是否齐全，缺失即列出清单、提示运行 `labels init` 并 `exit 1`；若 `label list` 本身失败（网络/权限），则报「无法获取远端标签」而非误报「标签缺失」。

**14 个内置标签清单**（与脚本三族常量完全一致）：

| 族 | 标签 |
|----|------|
| 优先级（4） | `p0` `p1` `p2` `p3` |
| 状态（7） | `riper-research` `riper-innovation` `riper-plan` `riper-execute` `riper-review` `riper-verified` `riper-blocked` |
| 重试（3） | `riper-retry-1` `riper-retry-2` `riper-retry-3` |

**各平台最小权限**：建标签需要写权限——GitHub 的 `gh` 需 `repo` scope（仅 `read` 不足以创建标签）；GitLab 的 `glab` 需 Developer 及以上角色；Gitea/Forgejo 的 `tea` 需对仓库有写权限。权限不足时 `labels init` 会在对应标签上报 FAILED 并 `exit 1`。

## 1. GitHub → `gh`

### 安装

```bash
# macOS
brew install gh

# Windows（任选一种；安装后在 Git Bash 中使用）
winget install --id GitHub.cli
scoop install gh
```

官方文档：<https://cli.github.com/>

### 授权

```bash
gh auth login
# 交互选择：GitHub.com 或 GitHub Enterprise Server
#          HTTPS 或 SSH
#          浏览器登录（推荐）或粘贴 Personal Access Token
gh auth status        # 验证
```

Token 方式（企业内网 / 无浏览器环境）：在 GitHub → Settings → Developer settings → Personal access tokens 生成，**需勾选 `repo` 权限**（Issue 读写）；自建实例还需 `read:org`（按需）。

非交互环境可用环境变量：

```bash
export GH_TOKEN=ghp_xxx        # 或 GITHUB_TOKEN
```

### 常见问题

- `gh auth status` 报 401/403：token 过期或权限不足，重新 `gh auth login`。
- 企业自建实例：`gh auth login --hostname github.your-corp.com`。
- 多账号：`gh auth switch`。

## 2. GitLab → `glab`

### 安装

```bash
# macOS
brew install glab

# Windows（任选一种）
winget install --id glab.glab
scoop install glab
```

官方文档：<https://gitlab.com/gitlab-org/cli>

### 授权

```bash
glab auth login                                    # gitlab.com
glab auth login --hostname gitlab.your-corp.com     # 自建 GitLab
glab auth status                                    # 验证
```

Token 方式：GitLab → Preferences → Access Tokens 生成，**scope 需含 `api`**（Issue 读写、标签管理）。

非交互环境：

```bash
export GITLAB_TOKEN=glpat-xxx
export GITLAB_HOST=gitlab.your-corp.com   # 自建实例
```

### 常见问题

- 自建实例证书问题：`glab config set check_update false`，或配置 `SSL_CERT_FILE`。
- 标签移除行为随 glab 版本略有差异，本 Skill 的 `git-ops.sh` 已做新旧版本兼容回退。

## 3. Gitea / Forgejo → `tea`

### 安装

```bash
# macOS
brew install tea

# Windows：从官方 Release 下载二进制并加入 PATH
#   https://dl.gitea.com/tea/
```

官方文档：<https://gitea.com/gitea/tea>

### 授权

```bash
tea login add
# 交互输入：login 名称 / 实例 URL（如 https://gitea.your-corp.com）/ access token
tea login list      # 验证已配置的登录
tea login use <name>   # 多实例时切换默认登录
```

Token 获取：Gitea/Forgejo → Settings → Applications → **Generate New Token**，权限需含 `read:issue` 与 `write:issue`。

### 常见问题

- `tea` 无 `auth status` 命令，本 Skill 以 `tea login list` 是否列出实例 URL 判定授权状态。
- 多实例仓库：确保 `tea login use` 指向当前 remote 对应的实例。
- 部分 tea 版本的 issue 子命令命名有差异，`git-ops.sh` 已对 `issue/issues` 两种写法做回退兼容。

## 4. Agent 行为约定（缺 CLI / 未授权时）

1. **立即停止**当前 RIPER 阶段，不做任何"绕过"尝试（不改用 curl + API、不猜测 token、不跳过 Issue 写回步骤）。
2. 把 `git-ops.sh doctor` 的输出（含安装/授权指南）**原样呈现给用户**，并指明需要用户完成的具体动作。
3. **禁止代用户输入凭据**，禁止把 token 写入仓库文件、脚本、`.env` 或提交到版本库。
4. 用户确认完成后，重新执行 `./scripts/git-ops.sh doctor` 验证，通过后再从中断的阶段继续。
5. 若用户明确表示"暂不配置 CLI"，则本轮循环终止，已在本地 `docs/issues/<N>/` 产出的文档保留，Issue 侧写回动作留待 CLI 就绪后补做。
