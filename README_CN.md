# Git Issue Loop Skill

[English](README.md)

当前稳定版：[v0.6.14](https://github.com/askdaddy/Git-Issue-Loop-Skill/releases/tag/v0.6.14)。版本变更见 [CHANGELOG.md](CHANGELOG.md)。

`iloop` 是一个面向 Agent 的 Issue 驱动 RIPER 研发闭环 Skill：
**目标登记（Goal）→ 研究（Research）→ 创新（Innovation）→ 计划（Plan）→ 执行（Execute）→ 审查（Review）**。
给一句目标也可以：Planner 会先把目标整理成草稿、经你确认后登记为 Issue，再进入闭环（目标直入）。
它以 Git Issue 的正文、评论和标签为唯一事实来源；本地 Markdown 文档（`docs/issues/<N>/`）仅在远程 Issue 不可用时作为降级 fallback，不做双写冗余。

Skill 通过官方 CLI 支持 GitHub、GitLab、Gitea 和 Forgejo：分别是 `gh`、`glab`、`tea`。

## 提供的能力

- `/iloop` 入口，可执行完整 RIPER 闭环、仅计划、验收、环境自检，或 `help`（输出用法速览 + 本地已安装版本）。
- 会话粘性 buffer：一次有效调用后，提问、等待确认或报告阻塞都只是**挂起**而非退出；用户回复即回到同一 Issue、阶段、角色与执行范围继续。只有 `/iloop exit` / `退出 iloop` 等显性指令或新会话才离开；退出默认保留认领，不自动改 Issue 状态。
- Issue 正文来源标记：经 `git-ops.sh issue create` 创建的 Issue 自动追加可见页脚，包含 Skill 仓库 URL、版本、短 SHA、角色、入口与 UTC 时间；它是来源说明而非身份认证，缺失不改变接入、阶段保护或权限判定。
- 裸 `/iloop` 自动挑选：只读扫描 open Issue，按 `p0`→`p3`、同优先级编号升序排序，跳过阻塞 / 重试超限 / 已验收未关闭 / 已认领者，呈报候选清单、选择理由与跳过项；**等用户确认后**才加载角色，且每次调用只处理 1 个 Issue。
- 启动分发：编号入口先判断接入需要，再按 RIPER 状态与阶段产物续跑。外部或来源未知的报告先由 Planner 查证、最小修正标签，保留合法进度。
- 启动时对照官方仓库最高稳定 tag 检查 Skill 是否有更新；有则询问是否升级，不自动切换。
- 目标直入：给 `/iloop` 一句目标而非 Issue 编号，Planner 会整理草稿、经确认后创建 Issue 并设优先级，再经分发进入闭环（新建 Issue 会落入研究）。
- 严格角色分工：Planner 负责规范和计划，Developer 按已批准计划实施，Reviewer 进行黑盒验收。
- 规格驱动交付：计划是冻结契约；任何计划变更都必须显式退回计划阶段。
- 最少代码梯子（`references/lazy-ladder.md`）约束 HOW：在验收范围内取最短 diff；合法改道须留一行 `skipped:` 评论。
- 三个互斥的 Issue 标签族——优先级（`p0`–`p3`）、RIPER 状态、重试计数（`riper-retry-1`–`3`）——外加一个受管非排他的认领标签（`riper-claimed`，标记 Issue 已被某会话认领，使并行会话的自动挑选跳过它），合计 15 个内置标签，由 `labels init` 幂等创建；它还会安全迁移仓库级 `P0` 等历史大小写变体所关联的 open/closed Issue，验证成功后再删除变体，失败时保留变体并停止。
- T0 硬边界：Planner 与 Reviewer 禁改业务代码；提交前 `guard <role>` 会用 `git status` 比对角色可写区域，越界即 `exit 1`。
- `scripts/git-ops.sh` 根据 `git remote` 自动识别平台、调用官方 CLI、按角色硬性校验 Issue 操作权限，且拒绝改走 REST API 或代填凭据。
- 面向并行会话的按 Issue 工作区隔离：只有分支不等于隔离——共用一个克隆的会话共享同一个 HEAD 与 index 锁。因此 `workspace start <N>` 会在**仓库外** `../.iloop-worktrees/<repo>/<N>` 建一个真正的 `git worktree`，挂上 `riper/<N>` 分支，基分支恒为 `origin/<默认分支>` 而**不是本地分支**，所以不会继承别的会话尚未推送的提交。`workspace status` 只读报告你在哪个工作树、哪条分支、归属哪个 Issue；`workspace finish <N>` 仅在工作区干净且已合并进上游时才清理，否则拒绝而不是丢弃任何一方；`guard <role> <N>` 会额外校验当前分支是否就是 `riper/<N>`。
- 运行时反馈：角色操作被拒绝、工作区越界或 Issue 阶段证据缺失时，先纠偏任务，再生成脱敏离线草稿；向维护上游提交须明确授权。
- 可选的结构化运行输出：`issue priority`、`issue status`、`issue comment`、`guard` 可在调用者预先打开的 fd3 上输出一条 NDJSON 事件（`ILOOP_EVENTS_FD=3`）；并提供区分「脚本观察事实 / Agent 声明 / 未验证」的阶段摘要模板（`templates/run-summary.md`）。默认关闭：不写本地事件日志、不联网，不改变 stdout、stderr 与退出码。契约见[运行时输出](references/runtime-output.md)。
- QA 通过核验后的 PR 交付，合并与发布另需授权；仅本地交付时 Issue 保持 open。
- `test/` 下 23 组 shell 不变量测试，覆盖 stub CLI 行为与契约检查；第三方接入场景走查属于协议审阅，不等同于独立 Agent 端到端测试。

## 第三方 Issue 接入

`/iloop <N>` 和裸 `/iloop` 经确认的目标都会先判断是否需要接入。外部或来源未知、尚无有效接入记录的 Issue 交给 Planner，先查证，再修标签：

1. 读取正文、评论、来源与既有阶段证据。缺陷调查复现条件与根因，需求核对场景与范围；区分事实、假设和未知，信息不足时暂停澄清。
2. 在原 Issue 记录查证结论，按角色权限最小修正优先级与阶段标签。保留无关标签、合法阶段进度、重试计数和认领历史，写后回读核验。
3. 回到常规 RIPER 分发。复用有效接入证据，仅复核实质变化；接入记录不替代规格或冻结计划。

`issue get <N> --strict` 在正文或评论的 CLI 调用失败时停止，不保证分页完整或内容语义正确。详见[接入协议](references/issue-intake.md)与[接入记录模板](templates/intake.md)。

## 运行时反馈闭环

角色操作被拒绝、guard 越界或阶段证据缺失时，先纠偏当前任务。`scripts/feedback.sh draft` 仅输出有限字段的离线草稿，不写文件、不自动上报。向维护仓库写入前，Agent 必须脱敏、查重，并取得对本次写入的授权。

正向结果包括成功拦截、安全恢复、反馈促成回归修复和误报纠正。修复发布后仍处于“待观察”，有后续运行证据才能标为“已验证”。反馈不替代产品验收，也不自动消耗 QA 重试次数。详见[反馈协议](references/feedback-loop.md)。

## 集成交付与发布

QA PASS → `riper-verified` → 推送并核验 PR 交付 → 写回证据 → 关闭 Issue 并释放认领。验收通过、PR 交付、进入上游与版本发布是不同里程碑。离线或仅本地合并时 Issue 保持 open；清理工作区要求确认已进入上游。

合并 PR 与稳定版发布另需授权。完整稳定发布必须在全套测试通过后，创建新 tag 和对应的 GitHub Release。详见[集成与发布契约](references/integration.md)。

## 安装最新稳定版

将下面这一句话交给能够操作 Git 的 Agent：

> 请从 `https://github.com/askdaddy/Git-Issue-Loop-Skill.git` 安装最新版 `iloop` 到 `~/.agents/skills/iloop`；若已有同源安装则仅在无本地修改时安全更新，否则停止并报告冲突；安装完成后验证 `SKILL.md`。

这里的“最新版”指远端最高的稳定 `vX.Y.Z` Git tag，不跟踪 `main`，也不安装 alpha、beta 或 RC 等预发布版本。成功后，Agent 应报告实际解析的 tag 与 commit SHA。

完整的暂存、校验、备份、更新和回滚协议见 [INSTALL.md](INSTALL.md)；其机器可读版本见 [skill-manifest.json](skill-manifest.json)。同源更新时旧安装备份为 `~/.agents/backups/iloop.backup-<时间戳>`（不在 `skills/` 下；隐藏前缀不足以避免部分宿主把点目录登记为第二条 `/iloop`）。暂存克隆到 `${TMPDIR:-/tmp}/iloop.staging-<随机值>`。同源更新时先 clone staging，再按 staging 内契约做备份与切换；新安装验证通过后只保留最近一份备份，更早的 `iloop.backup-*` 会被清理。

> 必须先发布至少一个稳定 `vX.Y.Z` tag，“安装最新版”才可用。若找不到稳定 tag，合规的 Agent 必须 fail closed，不能退化安装 `main`。

## 快速开始

1. 刷新 Agent 宿主会话，使其发现 `~/.agents/skills/iloop`。
2. 打开目标 Git 仓库，并在该仓库根目录执行环境自检：

   ```bash
   ~/.agents/skills/iloop/scripts/git-ops.sh doctor
   ```

3. 若自检提示缺少 CLI 或未授权，请由使用者自行完成安装和授权；不要将 token 写入仓库，也不要要求 Agent 代填凭据。
4. 输入 `/iloop`：不带参数时会自动挑选最该处理的 1 个 open Issue，并先呈报候选清单与理由等你确认；也可以直接给 Issue 编号、给一句目标，或让 Agent 只排计划、只做验收。

常用调用：

| 调用 | 行为 |
|---|---|
| `/iloop` | 呈报候选并等待确认，每次处理一个 Issue。 |
| `/iloop #44` | 读取目标、判断接入需要，再按证据续跑当前阶段。 |
| `/iloop 我要实现 X` | 先起草目标 Issue，经确认后创建。 |
| `/iloop help` | 仅显示用法与本地版本，不进入闭环，也不激活 buffer。 |
| `/iloop exit` | 显性退出 buffer，输出交接摘要；不关 Issue、不自动释放认领。 |
| `排 plan，不要执行` | 在请求范围内推进，计划完成后停止。 |

进入 buffer 后，中途回答确认、补充需求或提问都不会退出；回复会从挂起点继续。只有显性退出或新会话才离开。

首次在一个仓库中使用时，可初始化标签体系：

```bash
~/.agents/skills/iloop/scripts/git-ops.sh labels init
```

## 运行要求

- Git，以及会从 `~/.agents/skills/` 加载 Skill 的 Agent 宿主。
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
scripts/check-update.sh  对照远端最高稳定 tag 检查已安装 Skill 是否有更新
scripts/feedback.sh      生成有限字段的离线反馈草稿
scripts/runtime-events.sh 可选的 fd3 NDJSON 运行事件输出
roles/                   Planner、Developer、Reviewer 的角色说明
templates/               intake、spec、design、plan、verify-report 与阶段摘要模板
references/              CLI 配置、第三方接入、反馈、集成、运行时输出与最少代码梯子
test/                    shell 不变量测试与第三方接入协议走查
CHANGELOG.md             稳定版本变更记录
docs/issues/<N>/         降级落盘的阶段文档，仅当远程 Issue 平台不可用时写入
```

## 稳定版发布约定

`main` 是开发分支。每个稳定版都必须创建新的、不可复用的 `vX.Y.Z` tag，并发布对应的 GitHub Release 记录变更说明。预发布版本必须使用类似 `-beta.1` 的 SemVer 后缀，默认安装器会自动跳过。改动安装协议（`INSTALL.md` 或 `skill-manifest.json` 的 `installation`）必须随新的稳定 `vX.Y.Z` tag 发布。

规范性工作流规则见 [SKILL.md](SKILL.md)。英文版项目介绍见 [README.md](README.md)，稳定版本历史见 [CHANGELOG.md](CHANGELOG.md)。

## 安全修复标签

`issue priority`、`issue status` 与 `issue retry incr/reset` 写标签前，由官方 CLI 正向确认目标是 Issue；PR、元数据无法确认或旧 CLI 不支持可靠格式时停止，禁止静默放行。其他 Issue 命令尚未统一类型检查。

有明确理由的修复可用 `--role planner issue priority N none` 或 `--role <角色> issue status N none`。状态清空仅限该角色有权设置的实际状态；混有无权状态时整体拒绝。操作保留无关标签，删除后回读确认；无角色、读取/删除失败或族标签残留均不能报告成功。不清 retry/claim、不绕过接入和终态保护，不提供历史 PR 标签修复例外；多次请求之间没有事务保证。
