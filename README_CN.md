# Git Issue Loop Skill

[English](README.md)

`iloop` 是一个面向 Agent 的 Issue 驱动 RIPER 研发闭环 Skill：
**研究（Research）→ 创新（Innovation）→ 计划（Plan）→ 执行（Execute）→ 审查（Review）**。
它以 Git Issue 的正文、评论和标签为唯一事实来源，同时保留本地 Markdown 文档作为持久化工作副本和 fallback。

Skill 通过官方 CLI 支持 GitHub、GitLab、Gitea 和 Forgejo：分别是 `gh`、`glab`、`tea`。

## 提供的能力

- `/iloop` 入口，可执行完整 RIPER 闭环、仅计划、验收或环境自检。
- 严格角色分工：Planner 负责规范和计划，Developer 按已批准计划实施，Reviewer 进行黑盒验收。
- 规格驱动交付：计划是冻结契约；任何计划变更都必须显式退回计划阶段。
- 优先级（`p0`–`p3`）和 RIPER 状态均使用互斥的 Issue 标签族表达。
- `scripts/git-ops.sh` 根据 `git remote` 自动识别平台、调用官方 CLI，并校验角色权限。

## 安装最新稳定版

将下面这一句话交给能够操作 Git 的 Agent：

> 请从 `https://github.com/askdaddy/Git-Issue-Loop-Skill.git` 安装最新版 `iloop` 到 `~/.agent/skills/iloop`；若已有同源安装则仅在无本地修改时安全更新，否则停止并报告冲突；安装完成后验证 `SKILL.md`。

这里的“最新版”指远端最高的稳定 `vX.Y.Z` Git tag，不跟踪 `main`，也不安装 alpha、beta 或 RC 等预发布版本。成功后，Agent 应报告实际解析的 tag 与 commit SHA。

完整的暂存、校验、备份、更新和回滚协议见 [INSTALL.md](INSTALL.md)；其机器可读版本见 [skill-manifest.json](skill-manifest.json)。

> 必须先发布至少一个稳定 `vX.Y.Z` tag，“安装最新版”才可用。若找不到稳定 tag，合规的 Agent 必须 fail closed，不能退化安装 `main`。

## 快速开始

1. 刷新 Agent 宿主会话，使其发现 `~/.agent/skills/iloop`。
2. 打开目标 Git 仓库，并在该仓库根目录执行环境自检：

   ```bash
   ~/.agent/skills/iloop/scripts/git-ops.sh doctor
   ```

3. 若自检提示缺少 CLI 或未授权，请由使用者自行完成安装和授权；不要将 token 写入仓库，也不要要求 Agent 代填凭据。
4. 输入 `/iloop`，或让 Agent 对指定 Issue 进行计划或验收。

首次在一个仓库中使用时，可初始化标签体系：

```bash
~/.agent/skills/iloop/scripts/git-ops.sh labels init
```

## 运行要求

- Git，以及会从 `~/.agent/skills/` 加载 Skill 的 Agent 宿主。
- macOS，或在 Git Bash 中运行随附脚本的 Windows。当前尚未声明支持 Linux。
- 与目标 remote 对应的官方 Issue CLI：GitHub 使用 `gh`，GitLab 使用 `glab`，Gitea / Forgejo 使用 `tea`。
- 一个已完成授权、且有 Issue 与标签读写权限的 CLI 账号。

平台相关的安装与授权说明见 [references/cli-setup.md](references/cli-setup.md)。

## 项目结构

```text
SKILL.md                 Skill 契约与 RIPER 工作流
INSTALL.md               Agent 管理的 Git 安装协议
skill-manifest.json      机器可读的安装契约
scripts/git-ops.sh       平台路由、Issue 操作与安全约束
roles/                   Planner、Developer、Reviewer 的角色说明
templates/               spec、design、plan、verify-report 模板
references/              CLI 配置说明
```

## 稳定版发布约定

`main` 是开发分支。每个稳定版都必须创建新的、不可复用的 `vX.Y.Z` tag，并应发布对应的 GitHub Release 记录变更说明。预发布版本必须使用类似 `-beta.1` 的 SemVer 后缀，默认安装器会自动跳过。

规范性工作流规则见 [SKILL.md](SKILL.md)。英文版项目介绍见 [README.md](README.md)。
