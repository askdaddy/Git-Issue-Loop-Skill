# CLI 安装与授权指南（gh / glab / tea）

> 本 Skill 的 **CLI 优先原则**：所有 Issue 操作一律优先使用本地官方 CLI —— GitHub 用 `gh`、GitLab 用 `glab`、Gitea/Forgejo 用 `tea`，由 `scripts/git-ops.sh` 依据 `git remote -v` 自动路由。
> **禁止**改用 REST API + 手写 token、网页点击或其他方式绕行。
>
> 支持平台：**macOS** 与 **Windows**（Windows 必须在 Git Bash 中运行脚本，不支持 CMD / PowerShell）。

## 0. 一键自检

```bash
./scripts/git-ops.sh doctor
```

输出会依次给出：运行环境 → 路由到的 CLI → 安装状态 → 授权状态 → 标签体系就绪（15/15）。
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

**为何需要**：`issue priority` / `issue status` / `issue retry` / `issue claim` 都依赖平台上已存在对应标签；标签缺失时这些命令会因平台报 `'p0' not found`（或同类「标签不存在」错误）而 `exit 1`，导致闭环在第一次设置优先级/状态时就卡死（bootstrap 死锁）。

**命令**（新仓库克隆后、进入 RIPER 循环前执行一次）：

```bash
./scripts/git-ops.sh labels init
```

- **幂等边界**：GitHub / GitLab 的标签不存在则创建，已存在则更新颜色与描述；Gitea / Forgejo 因当前 tea 路径无更新能力，已有同名标签会跳过，不会同步颜色和描述。Gitea 对非 scoped 名称不查重，脚本以「先查存在再创建」避免重复。CLI、网络或权限失败仍会返回非零退出码。
- **doctor 会检查**：`./scripts/git-ops.sh doctor` 的最后一步会比对远端标签是否齐全，缺失即列出清单、提示运行 `labels init` 并 `exit 1`；若 `label list` 本身失败（网络/权限），则报「无法获取远端标签」而非误报「标签缺失」。

**15 个内置标签清单**（与脚本各族常量完全一致）：

| 族 | 标签 |
|----|------|
| 优先级（4） | `p0` `p1` `p2` `p3` |
| 状态（7） | `riper-research` `riper-innovation` `riper-plan` `riper-execute` `riper-review` `riper-verified` `riper-blocked` |
| 重试（3） | `riper-retry-1` `riper-retry-2` `riper-retry-3` |
| 认领（1，非排他） | `riper-claimed` |

**检查边界**：doctor 确认标签名称是否齐全，不验证颜色、描述或标签更新能力。已有 15 个标签时 doctor 通过，不代表 `labels init` 的更新分支一定成功。初始化失败应按 CLI 原始错误区分参数不兼容、网络与权限问题，不能仅凭 FAILED 判定为未授权。

**权限**：账号及凭据都必须允许目标仓库的标签管理。GitHub classic PAT 的 `repo` scope 与 fine-grained token 的仓库权限不是同一套表达；交互登录与凭据要求见 [gh auth login](https://cli.github.com/manual/gh_auth_login)。GitLab 还受实例版本和项目角色限制，不能把 Developer 当作统一的最小角色，见 [GitLab 标签权限](https://docs.gitlab.com/user/project/labels/)。Gitea / Forgejo 需核对目标实例、仓库写权限与 token 授权范围。

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

Token 方式（企业内网 / 无浏览器环境）：由使用者在 GitHub → Settings → Developer settings → Personal access tokens 生成。`gh auth login --with-token` 的 classic PAT 最小 scopes 按官方手册为 `repo`、`read:org`、`gist`；fine-grained PAT 建议通过 `GH_TOKEN` 使用，并按目标仓库和实际操作配置权限，不能照搬 classic scopes。参见 [gh auth login](https://cli.github.com/manual/gh_auth_login)。

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

- 自建实例证书问题：按管理员提供的 CA 证书配置 `glab config set ca_cert /path/to/ca.pem --host gitlab.your-corp.com`。`check_update false` 只关闭更新提示，不能修复证书信任；参见 [glab 连接配置](https://docs.gitlab.com/cli/connection/)。
- glab 1.130.0 的标签更新要求数字 ID：v0.6.18 起脚本按名称精确匹配、分页查询 ID，再执行 `glab label edit --label-id <ID>`；`--name` 或位置参数不能用于该更新命令。查询失败或 ID 无效时停止，保留 CLI 失败详情。参见 [glab label edit](https://docs.gitlab.com/cli/label/edit/)。
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

## 自由标签补建

经有权角色调用 `git-ops.sh --role <角色> issue label <N> add "<自由标签>"` 时，GitHub、GitLab、Gitea / Forgejo 均先检查仓库级标签；缺失才创建，已有标签不改颜色和描述。新建自由标签使用中性色：gh/tea 为 `ededed`，glab 为 `#ededed`。

列表读取失败时不盲目创建。创建失败后仍尝试添加：若添加成功，说明标签实际存在（例如并发创建或列表未覆盖）；两步都失败时返回非零并报告创建前置错误与添加失败。优先级、状态、重试与认领受管族不通过该路径补建，继续使用专用命令。

以上行为有 stub CLI 回归覆盖；真实 gh/glab/tea 网络环境及版本差异仍须按实际 CLI 输出核验，不能以测试夹具代替平台实测。

## 冒烟沙箱

对真实平台执行写操作的冒烟必须只落在**一次性沙箱仓库**上，而那需要你先授权建立：

```bash
./scripts/git-ops.sh smoke sandbox create [--name <n>]   # 建私有沙箱，输出 owner/repo
./scripts/git-ops.sh smoke sandbox delete <repo> --yes   # 用完删除
./scripts/git-ops.sh smoke require-origin <dir> <沙箱>   # 运行前硬闸
```

- 默认名带 `iloop-smoke-<UTC>`；`--name` 也必须含 `iloop-smoke`，否则拒绝。
- `delete` 必须显式 `--yes`，且名字含 `iloop-smoke`；真实仓库名一律拒绝，防误删。
- **`require-origin` 是硬闸**：fixture 的 `origin` 不指向沙箱时直接失败，绝不回退到真实仓库。缺这道闸时，fixture 临时目录被清理后 `origin` 回退，诊断命令改掉了真实 Issue（#87）。
- 删除仓库需要额外 scope：GitHub 的 token 通常只有 `repo`，删除还要 `delete_repo`；缺失时 `delete` 会给出 `gh auth refresh -h github.com -s delete_repo`，残留沙箱须手工清理。
- glab / tea 的实跑尚未验证；本节的命令按平台路由，但不保证 glab 侧已实测。
