---
name: iloop
description: >-
  Issue 驱动的 RIPER 研发闭环工作流，显式调用入口为斜杠命令 /iloop。当用户输入 /iloop，
  或要求"落地 issues"、"排 plan"、"验收 git issues"、"推进迭代"，或给出一个目标要求
  从零开始闭环（如"我要实现 X"、"从零做一个 X"、"新目标：X"），或提到 RIPER、SDD、
  Issue 驱动开发、研发闭环时触发。自动完成 目标登记→研究→创新→计划→执行→审查 循环
  （目标登记会把一句目标自动转化为 Issue 再进循环），
  支持 GitHub / GitLab / Gitea / Forgejo（gh / glab / tea），并在阶段切换时自动加载
  Agent Persona（PM=planner / developer / QA=reviewer）。启动时按 Issue 的 RIPER
  状态分发角色，0 帧切入当前阶段，而不是总从研究起手。每会话对照官方仓库最高
  稳定 tag 检查 Skill 是否有更新，有则询问用户是否升级，不得自行切换。
---

# iloop（git-issue-loop）：Issue 驱动的 RIPER 研发闭环

本 Skill 将 Git Issue 的生命周期与 RIPER 工作流深度融合。
输入是一个 Issue 编号，或一句目标描述（经 [G] 目标登记自动创建为 Issue）；输出是一个通过验收、状态为 `riper-verified` 且已关闭的研发闭环。

**角色简称**：Planner = **PM**（产品/架构），Developer = **开发**，Reviewer = **QA**（质量）。

## 调用入口与交互协议

**显式入口**：斜杠命令 `/iloop`（命令名 = Skill 名 `iloop`）。
自然语言（"落地 issues"、"排 plan"、"验收 git issues"、"推进迭代"）同样可以触发。

**裸 `/iloop`（无任何参数）进入时，自动挑选最该处理的 Issue**，三项信息取默认值、不再向用户追问：

1. **目标 Issue**：由 §3.0.1 第 0 层的「自动挑选」子程序选出唯一一个候选（p0→p3、同优先级编号升序，跳过阻塞与重试超限）。
2. **执行范围**：默认所选 Issue 的**完整闭环**（按其当前阶段 0 帧切入 → … → `riper-verified` 关闭，或 `riper-blocked` 停止）；**每次调用只处理 1 个**，推进下一个需再敲一次 `/iloop`。
3. **落盘方式**：沿用默认——阶段文档主路径写回 Issue 评论，仅当远程 Issue 不可用时降级写入本地 `docs/issues/<N>/`；QA 测试脚本默认 `test/`。

自动挑选**不直接开工**：Agent 必须先呈报「候选 + 选择理由 + 跳过项及原因」，经用户确认（或改选）后才加载角色进入该 Issue 的闭环（见 §3.0.1 第 0 层）。用户已给出编号、目标或阶段意图时，显式入口优先于自动挑选。
容错：若用户在 `/iloop` 后直接带了编号或阶段意图（如 `/iloop 42`、"只排 plan"），直接采用，不再追问该项。

**help 子命令（终止型，优先识别）**：`/iloop help`（等价 `/iloop --help`、`/iloop -h`，或自然语言「帮助 / 用法 / 怎么用 / 什么版本」）命中后**只输出「精简用法速览 + 本地版本号」随即停止**——**不**加载任何 `roles/*.md`、**不**跑 doctor / `labels init`、**不**进入 RIPER 循环、**不**改 Issue 状态、**不**写评论、**不**建 Issue；纯本地即可应答，**不依赖 doctor / CLI 授权**。help 意图**优先于「一句新目标」识别**（见 §3.0.1 第 0 层），杜绝把 “help” 当成目标去 [G] 建 Issue。

- **输出（精简速览五要素，一屏可读）**：①**定位**（Issue 驱动的 RIPER 研发闭环）②**调用入口**（`/iloop` + 自然语言触发）③**RIPER 六阶段**（[G] 目标登记 → [R] 研究 → [I] 创新 → [P] 计划 → [E] 执行 → [R] 审查）④**三角色**（PM=planner / 开发=developer / QA=reviewer）⑤**版本号**。
- **版本号来源**：以**当前 `SKILL.md` 所在目录**为 Skill 根（默认 `~/.agents/skills/iloop`，**非**目标项目仓库），现场执行 `git -C <Skill根> describe --tags --exact-match HEAD`（与 `check-update.sh` 的 `LOCAL_REF` 同算法）；失败兜底显示 `untagged (<short-sha>)`（`git -C <Skill根> rev-parse --short HEAD`）。**纯本地、不联网**，**不**把 `skill-manifest.json` 的 `skill.version` 当作已安装版本。
- **边界**：help 只展示**本地版本**；「检查更新 / 有没有新版」走 §3.0 的 `check-update.sh`（联网对比最高稳定 tag），二者不混。

**目标直入（Goal Bootstrap）**：当 `/iloop` 参数（或自然语言意图）是一句**目标描述**而非 Issue 编号时，进入 §3.1 [G] 目标登记阶段：PM 将目标结构化为 Issue 草稿、经用户确认后创建并设置优先级，再经 §3.0.1 分发进入闭环（新建 Issue 状态为 `riper-research`，故落入 [R]）。触发示例："我要实现 X"、"从零做一个 X"、"新目标：X"。

## T0 铁律（最高优先级，与任何规则冲突时以此为准）

1. **PM 与 QA 不得改动任何业务代码**——只读代码。违反即 T0 事故。
   - PM 的唯一可写文件区域：`docs/`，且**仅用于降级落盘**（见铁律 3；远程可用时产出一律评论写回 Issue）。
   - QA 的唯一可写区域：`test/`（黑盒测试脚本），禁止改动被测业务代码。
   - 开发是唯一有权改动业务代码的角色，且**仅限 `plan.md` 覆盖范围**。
2. **PM 产出的文档主路径写回 Issue**：spec / design / plan 全文以 Issue 评论形式写入；远程可用时**禁止额外落盘本地副本（不做双写冗余）**。
3. **降级 fallback**：仅当远程 Issue 不可用（CLI 缺失 / 未授权 / 平台不支持 / API 调用失败 / 单条内容超出平台限制）时，才降级写入本地 `docs/issues/<N>/`（spec.md / design.md / plan.md / verify-report.md，基于 `templates/` 填充；用户显性指定其他路径时以用户为准），并在 Issue 恢复可用后于评论中引用该文件路径。
4. **QA 偏向黑盒测试**：优先从外部可观测行为验证（CLI / API / 端到端），不深入实现细节做白盒断言。
   如需编写测试脚本，**默认生成到项目的 `test/` 目录**，除非用户显性指定其他路径。
5. **每个 Issue 必须有优先级**：由 PM 在 [G]/[R] 阶段按艾森豪威尔矩阵判定并设置 `p0`~`p3`；
   未设置优先级的 Issue 不得进入 [I] 创新阶段。任何角色新建 Issue 后，也必须立即由 PM 补设优先级。
6. **优先级与状态标签必须用平台原生 label 能力表达，禁止写进 Issue 标题**；两族标签各自**排他**（同时只能存在一个）。
7. 上述权限由 `git-ops.sh --role <角色>` 在脚本层硬性强制，Agent 不得以任何方式绕过。
8. **Issue 操作必须优先使用本地官方 CLI**（GitHub→`gh`，GitLab→`glab`，Gitea/Forgejo→`tea`），由 `git-ops.sh` 自动路由；**禁止**改用 REST API + 手写 token、网页点击或其他绕行方式。本地缺 CLI 或未授权时，**必须停下来把安装/授权指南交给用户**，不得代填凭据、不得跳过 Issue 写回步骤。
9. **提交前必须执行 `./scripts/git-ops.sh guard <当前角色>`，越界即 T0 事故**：脚本以 `git status --porcelain` 比对角色可写区域白名单（PM=`docs/`；开发=除 `test/` 与 `docs/` 外全部，但放行 `docs/issues/<N>/plan.md`；QA=`test/` 与 `docs/issues/<N>/verify-report.md`），命中越界路径即 `exit 1`，必须修正后再提交。**能力边界（如实声明）**：`guard` 只能校验「区域级越界」（文件落在哪个目录），**无法**校验「是否超出 `plan.md` 范围」——后者仍依赖角色自律与 [R] 审查阶段的越界判定。

## 0. 核心约定

- **唯一事实来源**：Issue（正文 + 评论 + 标签）为主；本地 `docs/issues/<N>/` 仅为**降级 fallback，不是持久化副本**——远程可用时不得双写。
- **降级落盘位置**：`docs/issues/<N>/`（spec.md / design.md / plan.md / verify-report.md），基于 `templates/` 填充，仅当远程 Issue 不可用时使用；用户显性指定时以用户为准。
- **测试脚本位置**：QA 的黑盒测试脚本默认落 `test/`；用户显性指定时以用户为准。
- **Git 操作**：一律通过 `scripts/git-ops.sh` 执行，禁止直接调用 `gh` / `glab` / `tea`。Agent 调用时**必须携带 `--role <当前角色>`**，脚本按 §1.1 权限矩阵与 §1.2 标签体系硬性校验。子命令清单：`issue list|get|comment|create|close|reopen|priority|status|retry|label`、`labels init`、`guard <role>`、`platform`、`doctor`。
- **平台路由**：脚本通过 `git remote -v` 自动检测并路由到对应 CLI，Agent 无需关心托管平台差异。
- **前置自检**：进入循环前先跑 `./scripts/git-ops.sh doctor`（检查运行环境 + CLI 安装 + 授权状态）。不就绪时脚本会输出安装/授权指南并 `exit 1`，Agent 必须中止循环、把指南**原样呈现给用户**，待用户完成后重跑 `doctor` 再继续；完整指南见 `references/cli-setup.md`。
- **凭据安全**：禁止代用户输入 token，禁止将凭据写入仓库文件、脚本、`.env` 或提交到版本库。
- **运行环境**：仅支持 macOS 与 Windows。Windows 下 `git-ops.sh` 必须在 Git Bash 中运行（随 Git for Windows 自带），不支持 CMD / PowerShell。macOS 宿主默认 shell 常为 zsh；Agent 执行安装/更新协议等**内联 shell** 时必须用 **bash**（zsh 缺 `shopt` / `nullglob` 等 bash 内建，直接跑会 `command not found`）。随附脚本已带 `#!/usr/bin/env bash`，经 `./script.sh` 调用恒在 bash 下运行、天然安全。

## 1. 多角色驱动机制（Persona Loading）

**先完成 §3.0.1 启动分发，再按分发结果读取对应的一份角色文件。** 禁止为了「看看该不该调研」而预加载 PM。Skill 更新检查、doctor 与 `labels init` 不需要角色。

**进入分发指定的 RIPER 阶段之前，必须先完成该阶段的角色切换：**

| 阶段 | 角色文件 | 角色 | 可写区域 |
|------|----------|------|----------|
| [G] 目标登记 | `roles/planner.md` | PM | Issue（创建 + 评论） |
| [R] 研究 | `roles/planner.md` | PM | `docs/` + Issue |
| [I] 创新 | `roles/planner.md` | PM（保持） | `docs/` + Issue |
| [P] 计划 | `roles/planner.md` | PM（保持） | `docs/` + Issue |
| [E] 执行 | `roles/developer.md` | 开发 | 业务代码（限 plan 范围）+ `docs/issues/<N>/plan.md` 勾选 |
| [R] 审查 | `roles/reviewer.md` | QA | `test/` + `docs/issues/<N>/verify-report.md` + Issue |

角色切换规则：

1. Agent **必须先完整读取** `roles/` 目录下对应角色文件的全部内容。
2. 进入 **[I] / [P] / [E] / [R]审查** 之前，还必须先完整读取 `references/lazy-ladder.md`（最少代码梯子）。[G]/[R]研究 不读。
3. 严格按照文件中的指令设定当前的角色、语气、行为边界和约束，直到本阶段结束。
4. 角色文件可被用户随时修改；每次进入阶段都重新读取，**不得缓存上一次的角色设定**。
5. 未完成角色加载前，禁止产出任何该阶段的工作成果。

### 1.1 Issue 操作权限矩阵

| 操作 | PM (planner) | 开发 (developer) | QA (reviewer) |
|------|--------------|------------------|---------------|
| 创建 Issue | ✅ | ✅（仅限登记计划外发现） | ✅ |
| 评论 Issue | ✅ | ✅ | ✅ |
| 关闭 Issue | ✅（仅限无效/重复/被取代） | ❌ | ✅（闭环终点关闭权） |
| 重开 Issue | ✅ | ❌ | ✅（仅纠正误关） |
| 设置优先级 | ✅ | ❌ | ❌ |
| 改动业务代码 | ❌（T0） | ✅（限 plan 范围） | ❌（T0） |

### 1.2 标签体系

**（1）优先级族（必须，排他，艾森豪威尔矩阵）**

| 标签 | 象限 | 含义 |
|------|------|------|
| `p0` | 重要且紧急 | 立即处理，阻塞发布/线上事故 |
| `p1` | 重要不紧急 | 排期处理，核心价值与关键技术债 |
| `p2` | 紧急不重要 | 尽快处理但可委派，低价值高时限 |
| `p3` | 不重要不紧急 | backlog，择机处理 |

设置方式：`./scripts/git-ops.sh --role planner issue priority <N> <p0|p1|p2|p3>`（脚本自动清理同族其他标签）。

**（2）状态族（必须，排他，描述 RIPER 各阶段）**

`riper-research` → `riper-innovation` → `riper-plan` → `riper-execute` → `riper-review` → `riper-verified`；异常终态 `riper-blocked`。

| 状态 | 可设置角色 |
|------|-----------|
| `riper-research` / `riper-innovation` / `riper-plan` | PM（`riper-plan` QA 也可设置，用于 FAIL 退回） |
| `riper-execute` / `riper-review` | 开发 |
| `riper-verified` / `riper-blocked` | QA（`riper-blocked` 开发也可设置，用于遭遇阻塞） |

切换方式：`./scripts/git-ops.sh --role <角色> issue status <N> <状态>`（脚本自动清理同族其他状态）。

**（3）重试计数族（排他，持久化 QA 审查 FAIL 的轮次）**

`riper-retry-1` → `riper-retry-2` → `riper-retry-3`（同时只存在一个，达 3 即上限）。把"已重试几次"落到 Issue 标签上，避免依赖 Agent 跨会话记忆。

| 操作 | 可设置角色 | 说明 |
|------|-----------|------|
| `issue retry <N> incr` | **仅 QA（reviewer）** | 审查 FAIL 退回 `riper-plan` 时登记 +1；当前已为 `riper-retry-3` 时拒绝并提示转 `riper-blocked` |
| `issue retry <N> get` | 三角色（只读） | 输出当前 K（无 retry 标签输出 `0`），供判定是否超限 |
| `issue retry <N> reset` | 三角色 | 清零（移除全部 `riper-retry-*`），新一轮闭环开始时用 |

唯一入口：`./scripts/git-ops.sh --role reviewer issue retry <N> <incr|get|reset>`（脚本自动排他清理同族）。`issue label` 子命令被禁止触碰本族。

**（4）自由标签（可选，不排他）**：Agent 可自行定义用于上下文召回，如 `module/auth`、`type/bug`、`area/cli`。
通过 `issue label <N> add|remove <标签>` 操作；脚本禁止用该子命令触碰上述三个互斥族（优先级 / 状态 / 重试）。

## 2. SDD 核心原则（Spec-Driven Development，不可违反）

1. **计划即契约**：Execute 阶段必须逐条满足 `plan.md` 中的步骤与验收标准，**禁止跳过、禁止合并、禁止添加计划外功能**。HOW（实现路径）由 `references/lazy-ladder.md` 约束：在验收范围内取更高 rung 的最短 diff；合法改道须按该文件格式评论。验收标准冻结 WHAT；涉及文件与逻辑说明是建议，不是牢笼。
2. **计划有误必回退**：发现计划有误（缺步骤、错文件、顺序不对）必须：立即**中断执行** → 退回 Plan 阶段更新 `plan.md` 并同步评论到 Issue → 再从更新后的步骤继续。严禁"边改边做、事后补计划"。
3. **验收只认计划**：Review 阶段只依据 `plan.md` 中的验收标准判定 PASS/FAIL，不接受"代码能跑就算过"。
4. **文档先行**：任何代码提交之前，对应的 spec / design / plan 必须已经存在且填充完整。

## 3. RIPER 状态机循环

### 3.0 前置自检（每轮循环开始前）

1. **Skill 更新检查（先于 doctor；本会话尚未执行过时）**：以**当前加载的 `SKILL.md` 所在目录**为 Skill 根（默认 `~/.agents/skills/iloop`，不是目标项目仓库根），执行：
   `bash <Skill根>/scripts/check-update.sh`
   无角色。比较本地 `git describe --tags --exact-match`（失败则为 untagged + HEAD SHA）与清单 `distribution.repository` 上最高稳定 tag（`vX.Y.Z`，忽略预发布）。**禁止**用目标项目 `git remote`，**禁止**把 `skill-manifest.json` 的 `skill.version` 当作已安装版本。
   - `status=current`（exit 0）→ 继续 doctor。
   - `status=update-available`（exit 2）→ 向用户展示 `local_ref` 与 `latest_tag`，询问**升级**或**本次跳过**。Agent **不得自行升级**。升级则只执行 `INSTALL.md` 的一句话协议，完成后提醒刷新宿主会话；本轮默认停止（协议已变），用户明确要求继续才用**新** Skill 重入 §3.0。跳过则继续 doctor。
   - `status=untagged`（exit 2）→ 说明当前为非稳定安装并列出 `latest_tag`；默认继续本轮，用户也可选择改去安装稳定版。
   - 检查失败（exit 1，含网络 / 非 git / 无稳定 tag）→ 在对话中声明后**不阻塞**，继续 doctor。
2. 执行 `./scripts/git-ops.sh doctor`（在**目标项目**仓库根）：依次确认运行环境（macOS / Windows Git Bash）、remote 路由到的 CLI、CLI 已安装、CLI 已授权。
3. doctor 通过后，若本次会话尚未执行过，运行 `./scripts/git-ops.sh labels init`（幂等）：确保优先级 / 状态 / 重试 / 自由标签所需的 14 个内置标签（4 优先级 + 7 状态 + 3 重试）在平台上存在，避免后续 `issue priority` / `issue status` / `issue retry` 因标签缺失而中止。doctor 也会检查这套标签是否就绪，缺失即 `exit 1` 并提示运行 `labels init`。
4. **全部通过** → 进入 §3.0.1 启动分发。**禁止在分发完成之前读取任何 `roles/*.md`。**
5. **CLI 缺失或未授权** → 立即中止，把脚本输出的安装/授权指南（或 `references/cli-setup.md` 对应章节）原样交给用户，说明需要完成的具体动作；用户确认完成后重跑 `doctor`，通过再从中断阶段继续。
6. 严禁绕行：不得改用 curl + REST API、不得猜测/代填 token、不得跳过 Issue 侧的读写步骤。

### 3.0.1 启动分发（Dispatch，无角色）

doctor / `labels init` 通过后、加载任何角色之前执行。本层是协议查表，不是第四个 Persona：不读业务代码、不写 spec、不为了「看看该不该调研」而预加载 PM。

**状态先后（用于「更早」比较）**：

`(无 riper-* ) < riper-research < riper-innovation < riper-plan < riper-execute < riper-review < riper-verified`

`riper-blocked` 不参与前进：分发到此后停止并报告卡点，等待人工介入。

#### 第 0 层：调用分类（只看用户这句话）

| 输入 | 去向 |
|------|------|
| help / 用法 / 版本（`/iloop help`、`--help`、`-h`、「帮助 / 用法 / 怎么用 / 什么版本」） | 输出精简用法速览 + 本地版本号后**停止**：不加载角色、不进 RIPER 循环、不改 Issue 状态 |
| 一句新目标（无 Issue 编号） | §3.1 `[G]`，然后加载 PM |
| 编号 /「落地 #N」 | 对该 N 进入第 1 层 |
| 「推进迭代」 | 列出 open Issue（p0→p3），对**每个**进入第 1 层 |
| 「只验收 / 只排 plan / 重做研究」等口头覆盖 | 记录覆盖项，再进入第 1 层（覆盖优先于标签，须先说明对状态的影响） |
| 仅环境自检 / doctor | 停在自检，不加载角色 |
| **裸 `/iloop`（无任何参数与意图词）** | **自动挑选**子程序（见下）→ 呈报待确认 → 对选中编号进入第 1 层 |

**help 优先**：help / 用法 / 版本意图**先于**「一句新目标」匹配（表首行即 help），避免把 “help”「用法」当成目标去 `[G]` 建 Issue。上表六条显式路由**均优先于**自动挑选；裸 `/iloop` 是最末兜底路由。

**自动挑选**：只读、无角色、不写回 Issue。用户显性指定编号 / 目标 / 阶段意图时不触发本路径。

1. **取候选四元组**（仅经 `git-ops.sh` 只读子命令；**禁止**为此提前加载任何 `roles/*.md`，禁止写状态/写标签/写评论）：`issue list --state open` 给出编号、优先级、RIPER 状态；retry 值逐个调 `issue retry <N> get`（列表**不含** retry 列）。若列表无标签列（glab/tea 降级，优先级/状态显示 `(无)`），改逐条 `issue get <N>` 读真实标签，并在报告中**标注该降级依据**，禁止按 `(无)` 占位静默误选。<!-- lazy-ladder: 逐条 retry get，open 量大时改 issue list 输出补 retry 列 -->
2. **排序**：p0 → p1 → p2 → p3 → 无优先级；同键按编号升序（更老的先收尾）。该顺序由本步负责，不依赖 `issue list` 的打印顺序。
3. **跳过规则**：`riper-blocked`（等人工介入）、`riper-retry-3`（重试超限）、`riper-verified` 但未关闭（异常态，仅提示人工关闭/重开，不改状态），三者均不参选并须写明原因。
4. **呈报并等确认**：输出候选清单，每条含 `编号 / 优先级 / RIPER 状态 / retry 值 / 是否跳过及原因`，末行给出选中项与一句话理由；**停在此处等用户确认或改选**，不得选完直接开工。改选任一编号等同显式 `/iloop <编号>`，重新进第 1 层分发。
5. **终止分支**：无 open Issue → 报告空态并指向 `[G]` 目标登记，**禁止**自动建 Issue、不加载角色；全部候选被跳过 → 报告各自卡点原因后停止，不改任何状态（对齐 `riper-blocked 不参与前进`）。
6. 挑选报告是对话内产物，**不落盘、不写 Issue 评论**（避免污染 Issue 这一唯一事实来源）。

**执行范围是上限，分发结果是入口（C9）**：完整闭环可走到 `riper-verified`；只到计划则入口已是 `[E]`/`[R]审查` 时报告并停止，不擅自回退阶段；只做验收若非用户覆盖，不得把仍在执行中的 Issue 强行改成审查。

#### 第 1 层：阶段分发（Issue 证据）

对编号 N 执行 `./scripts/git-ops.sh issue get <N>`（此时仍无角色；`get` 不限角色）。从标签读取唯一 `riper-*`、`p0`–`p3`、`riper-retry-*`。用下列标记扫描评论与降级文件 `docs/issues/<N>/`（命中任一即视为产物存在）：

| 产物 | 评论或文件标记 |
|------|----------------|
| spec | `# Spec` 或 `阶段: [R] Research` |
| design | `# Design` 或 `阶段: [I] Innovation` |
| plan | `# Plan` 或 `阶段: [P] Plan` |
| verify-report | `Verify Report` / `verify-report`，或同时含 `阶段: [R] Review` 与逐项 PASS/FAIL |

自定义评论标题须保留上表标记，否则产物检测会漏。

**证据阶段**：无 spec → 早于研究；有 spec 无 design → 研究完成；有 design 无 plan → 创新完成；有冻结 plan → 计划完成；有 verify-report 或 retry>0 且状态为 `riper-plan` → FAIL 回退修计划（不要当第一版 plan 来写）。

**切入点 = min(标签声称阶段, 证据阶段)**。标签超前于产物时，以产物为准往回退（例如标了 `riper-execute` 但没有 plan → `[P]`）。

| 切入点（回退后） | 0 帧角色 | 进入 |
|------------------|----------|------|
| 无 `riper-*` 且无 plan / `riper-research` | PM | §3.2 `[R]`；已有 spec 则补缺口，不从零重开调研 |
| `riper-innovation` | PM | §3.3 `[I]` |
| `riper-plan`（含 FAIL 修计划） | PM | §3.4 `[P]` |
| `riper-execute`，或无 `riper-*` 但已有冻结 plan | 开发 | §3.5 `[E]`，从计划未勾选项继续 |
| `riper-review` | QA | §3.6 `[R] 审查` |
| `riper-verified` | 无 | 报告已闭环，不加载角色、不改状态；除非用户明示重开并重做 |
| `riper-blocked` | 无 | 报告卡点，停止 |

GitHub/GitLab 的 Open **不等于**可写代码。无 `riper-*` 且无冻结 plan → `[R]`，禁止直接交给开发。

**glab/tea 降级**：`issue get` 看不到标签时，在对话中声明降级，改用产物标记；产物也没有则当无状态，切入 `[R]`。不要为此改用 REST API，也不要为此去实现 `issue get --json`。

**状态写入（C6）**：进入某 §3.x 时，`issue status` 对齐该阶段仅当：当前无状态、当前等于本阶段、当前早于本阶段，或本次切入来自产物回退（证据早于标签，允许把超前标签拉回证据阶段），或用户显性「重做某阶段」，或 QA FAIL 退回 `riper-plan`。禁止在分发结果不是 `[R]` 时把 `riper-execute` / `riper-review` / `riper-verified` 改回 `riper-research`。

分发结束后**才**读取对应的一份 `roles/*.md`，从该节现有步骤继续，不重跑被跳过的阶段。

### 状态流转图

```
目标描述（一句，可选入口）
   │ 第 0 层：新目标 → PM [G] 草稿 → 确认 → create → 优先级 → riper-research
   ▼
Issue(编号 N)
   │ 启动分发（§3.0.1）：读标签 + 产物，取较早者；口头覆盖优先
   ▼
  ┌─────────┬─────────┬─────────┬─────────┬──────────┐
  ▼         ▼         ▼         ▼         ▼          ▼
 [R]研究  [I]创新   [P]计划   [E]执行  [R]审查   verified/blocked
  PM        PM        PM       开发      QA      报告后停止
 riper-    riper-    riper-    riper-   riper-
 research  innovation plan     execute  review
              ▲                  │         │
              │   计划有误       │  FAIL（QA 退回 riper-plan）
              └──────────────────┴────┬────┘
                                      │ 重试 ≤ 3 次
                             全部 PASS │
                                      ▼
                   riper-verified → QA 关闭 Issue
                   （超限：riper-blocked，人工介入）
```

### 3.1 [G] 目标登记阶段（Goal Bootstrap）— PM

仅当用户给的是**目标描述**而非 Issue 编号时进入（编号输入走 §3.0.1 第 1 层分发，不默认研究）。

1. **加载角色**：读取 `roles/planner.md`，切换为 PM。
2. **只读调研**：围绕目标快速拉取相关代码上下文（涉及模块、现状、约束），全程只读（T0）。
3. **结构化为 Issue 草稿**：
   - 标题 = 动词 + 可交付物（如"支持从零创建 Issue 的目标直入入口"）；**禁止**含优先级/状态字样（T0 铁律 6）；
   - 正文 = 原始目标（用户原话）+ 背景与调研摘要 + 粗粒度验收意向 + 优先级判定依据 + 目标来源；
   - 本阶段**不产出 spec / design / plan**（那是 [R]/[I]/[P] 的职责）；草稿只需达到"可进入研究阶段的需求陈述"标准。
4. **歧义消解**：目标模糊到写不出验收意向时，在**对话中**向用户提问（此时 Issue 尚不存在，不走 Issue 评论提问路径），直到可成稿。
5. **草稿确认**：将标题 + 正文草稿呈给用户过目，确认或按反馈修订后再创建；用户明确表示本次免确认时可直接创建。
6. **创建并初始化**（依次执行）：
   - `./scripts/git-ops.sh --role planner issue create "<标题>" "<正文>"` → 取得编号 N；
   - `./scripts/git-ops.sh --role planner issue priority <N> <p0|p1|p2|p3>`；
   - `./scripts/git-ops.sh --role planner issue status <N> riper-research`；
   - `./scripts/git-ops.sh --role planner issue comment <N> "由目标直入 [G] 创建，原始目标：<用户原话>"`。
7. **大目标拆分**：判定目标过大时，拆分为多个 Issue（逐个执行第 6 步），在主 Issue 评论中登记拆分关系，随后按 p0→p3 顺序逐个进入循环（同"推进迭代"语义）。
8. 完成后进入 §3.0.1 启动分发（编号 N 此时为 `riper-research`，第 1 层将落入 §3.2 [R]）。

### 3.2 [R] 研究阶段（Research）— PM

仅当 §3.0.1 分发结果为 `[R]` 时进入本节。禁止在分发结果不是研究时执行本节（含禁止「先切 `riper-research` 再调研」）。

1. **加载角色**：读取 `roles/planner.md`，切换为 PM。
2. `./scripts/git-ops.sh --role planner issue get <N>` 获取 Issue 详情（标题、正文、评论、标签）。
3. **校验并设置优先级**（艾森豪威尔矩阵；[G] 目标登记已设置过则校验沿用，不重复设置）：`./scripts/git-ops.sh --role planner issue priority <N> <p0|p1|p2|p3>`。
4. **对齐状态**：分发已判定入口为研究，执行 `./scripts/git-ops.sh --role planner issue status <N> riper-research`。若标签曾超前于产物，这是把状态拉回证据阶段（C6 允许的产物回退），不是把合法的执行/审查 Issue 打回研究。
5. 阅读正文与全部评论，**只读**拉取相关代码上下文（涉及文件、模块、依赖）。
6. 按 `templates/spec.md` 提炼规范：原始需求、上下文代码、核心约束、澄清假设。
   - **已有 spec**（评论或降级文件命中 §3.0.1 产物标记）：只补缺口或澄清，**禁止从零重开调研**；spec 已完整则进入 §3.0.1 让下一阶段接手（通常为 `[I]`）。
   - **尚无 spec**：全文以评论写入 Issue → `./scripts/git-ops.sh --role planner issue comment <N> "<spec 全文>"`，不落盘本地；
   - **降级 fallback**（CLI 缺失 / 未授权 / 平台不支持 / API 失败 / 内容超限时）：写入 `docs/issues/<N>/spec.md`，并在 Issue 恢复后评论引用该文件路径。
7. 若需求存在无法用假设消解的歧义，在 Issue 下评论提问并暂停循环，等待用户回复。

### 3.3 [I] 创新阶段（Innovation）— PM

1. **保持 PM 角色**（若切换过会话，重新读取 `roles/planner.md`）。
2. 切换状态：`./scripts/git-ops.sh --role planner issue status <N> riper-innovation`。
3. 基于 spec 思考**至少两种**技术方案，按复杂度、风险、可测性、可维护性、与现有代码契合度、**代码量**、**是否新依赖**对比，选定最终方案并说明理由（先读 `references/lazy-ladder.md`）。
4. design 全文评论写回 Issue（主路径，基于 `templates/design.md` 组织）；仅当远程 Issue 不可用时降级写入 `docs/issues/<N>/design.md`。
5. **全程只读代码，不得产出或修改任何实现代码（T0）。**

### 3.4 [P] 计划阶段（Plan）— PM

1. **保持 PM 角色**。
2. 切换状态：`./scripts/git-ops.sh --role planner issue status <N> riper-plan`。
3. 基于 design 拆解**极细粒度**原子任务：每步只做一件事，含编号、涉及文件、逻辑说明、验收标准、完成状态 `[ ]`。**验收标准冻结 WHAT**（可观察结果，禁止把实现类名/新建文件当作验收项）；**涉及文件与逻辑说明是建议 HOW，不冻结**。
4. **主路径不落盘**：plan 随下一步的合并评论写回 Issue；仅当远程 Issue 不可用时降级填充 `docs/issues/<N>/plan.md`（基于 `templates/plan.md`）。
5. 将 spec、design、plan 三份内容合并评论写回 Issue：
   `./scripts/git-ops.sh --role planner issue comment <N> "<三份文档合并内容>"`。
6. 计划写回 Issue 后即视为**冻结基线**；后续修改必须走"中断→回退→更新→再同步"流程，并登记在 plan 的"计划修订记录"中。

### 3.5 [E] 执行阶段（Execute）— 开发

1. **加载角色**：先读 `references/lazy-ladder.md`，再读 `roles/developer.md`，切换为开发。
2. 切换状态：`./scripts/git-ops.sh --role developer issue status <N> riper-execute`。
3. 严格逐项执行计划：
   - 主路径（plan 在 Issue 评论中）：每完成一项（或按合理批次）将勾选进度评论同步到 Issue；
   - 降级模式（存在本地 `docs/issues/<N>/plan.md`）：每完成一项将 `[ ]` 改为 `[x]` 并落盘更新；
   - HOW 按梯子取更高 rung；因复用/标准库/原生/已装依赖/一行而改道时，评论 `步骤 N: skipped: …, used: …, add when: …`；
   - 遵守 SDD 原则：发现计划有误（含想砍掉本步需求）→ 中断 → 回退 Plan 阶段（PM 修订）→ 再继续；
   - 遭遇无法推进的阻塞 → `./scripts/git-ops.sh --role developer issue status <N> riper-blocked` 并评论说明。
4. 按仓库既有规范提交代码，提交信息引用 Issue 编号（如 `... (#N)`）。
5. 交付审查：`./scripts/git-ops.sh --role developer issue status <N> riper-review`。

### 3.6 [R] 审查阶段（Review）— QA

1. **加载角色**：先读 `references/lazy-ladder.md`，再读 `roles/reviewer.md`，切换为 QA。
2. 对照计划（Issue 评论中的 plan，或降级产生的本地 `plan.md`）每一步的验收标准，**以黑盒方式**执行测试与代码审查（读代码属只读，禁止修改业务代码，T0）。PASS/FAIL 只认验收标准 + 越界行为（多余功能或未批准新依赖）；多碰文件本身不 FAIL。
3. 如需编写测试脚本，默认生成到 `test/` 目录（用户显性指定时以用户为准）。
4. 按 `templates/verify-report.md` 生成 verify-report 全文并评论写回 Issue：逐项判定、证据、失败原因分析；附加检查含可删清单（`delete:` / `stdlib:` / `native:` / `yagni:` / `shrink:`），**不单独 FAIL、不阻塞判定、不计入重试**。
5. 仅当远程 Issue 不可用时降级写入 `docs/issues/<N>/verify-report.md`，恢复后在评论中引用。

### 3.7 状态判定（Loop Control）

- **全部 PASS**：
  1. `./scripts/git-ops.sh --role reviewer issue status <N> riper-verified`；
  2. 评论总结闭环结论；
  3. 由 QA 执行 `./scripts/git-ops.sh --role reviewer issue close <N>` 关闭 Issue（关闭权专属 QA），结束循环。
- **存在 FAIL**：
  1. 登记重试计数（**防死循环：最多重试 3 次**）：`./scripts/git-ops.sh --role reviewer issue retry <N> incr`（排他写入 `riper-retry-K`，不依赖 Agent 记忆）；
  2. QA 退回计划：`./scripts/git-ops.sh --role reviewer issue status <N> riper-plan`，并评论失败分析；
  3. PM 修订计划（主路径在 Issue 评论中修订；降级模式下修订本地 `plan.md`）并同步评论；
  4. 重新走 [E] → [R]。
- **重试已达上限仍有 FAIL**（`./scripts/git-ops.sh --role reviewer issue retry <N> get` 返回 `3`，此时 `incr` 也会被拒绝）：停止循环，`./scripts/git-ops.sh --role reviewer issue status <N> riper-blocked`，在 Issue 下评论说明卡点，等待人工介入。

## 4. 快速用法

```
/iloop                        → 自动挑选：doctor 自检后按 p0→p3（同键编号升序）挑出最该处理的 1 个 open Issue，呈报候选/理由/跳过项待用户确认，再按 §3.0.1 第 1 层推进该单完整闭环
/iloop help                   → 输出技能用法（精简速览）+ 版本号（Skill 根 git describe），随即终止：不加载角色、不进循环
/iloop 我要实现 XXX            → 目标直入：[G] 登记（草稿经确认后建 Issue 并设优先级）→ 分发后落入 [R] 再闭环
"从零做一个 X" / "新目标：X"    → 同上：从目标创建 Issue 后经分发进入循环
"落地 issue #42"              → doctor 后经 §3.0.1 按 #42 当前状态 0 帧切入对应角色与阶段
"推进迭代"                    → 扫描 open issue，按优先级 p0→p3 排序，对每个走第 1 层分发
"验收 git issues"             → 口头覆盖：对目标 issue 执行 [R] 审查（须说明对状态的影响）
"排 plan，不要执行"           → 口头覆盖：只走到计划写回（入口已超过计划则报告并停止）
"检查环境 / cli 没装"          → 执行 doctor，输出安装与授权指南
"检查 skill 更新"              → 在 Skill 根运行 scripts/check-update.sh；有更高稳定 tag 则询问是否按 INSTALL.md 升级
```

**常用脚本子命令（一律经 `scripts/git-ops.sh`，携带 `--role`）**：

```
./scripts/git-ops.sh labels init                                  → 初始化 14 个内置标签（4 优先级 + 7 状态 + 3 重试，幂等；新仓库首次必跑）
./scripts/git-ops.sh issue list [--state open|closed|all] [--status <riper-*>] [--priority <p0..p3>]
                                                                  → 列出 Issue，按优先级 p0→p3 排序（glab/tea 无标签列时降级）
./scripts/git-ops.sh --role reviewer issue retry <N> <incr|get|reset> → 重试计数持久化（incr 仅 QA；get/reset 不限角色）
./scripts/git-ops.sh guard <role>                                 → 可写区域越界自检（提交前必跑；越界 exit 1）
./scripts/git-ops.sh doctor                                       → 环境 + CLI + 授权 + 标签体系就绪自检
```

## 5. 安装与注册（让 `/iloop` 生效）

本 Skill 以 GitHub 仓库分发。默认安装位置为 `~/.agents/skills/iloop`，目录名必须与 frontmatter 的 `name`（`iloop`）一致。面向 Agent 的安装入口、版本解析和安全切换协议见仓库根目录的 `INSTALL.md`；机器可读约束见 `skill-manifest.json`。同源更新时旧安装备份为 `~/.agents/backups/iloop.backup-<时间戳>`（**不在** `skills/` 下：部分宿主会把点目录也当成技能扫描，隐藏前缀不足以避免第二条 `/iloop`）。暂存克隆到 `${TMPDIR:-/tmp}/iloop.staging-<随机值>`。同源更新时先 clone staging，再按 staging 内 `INSTALL.md` / `skill-manifest.json` 做备份与切换。

**用户只需说一句话**：

> 请从 `https://github.com/askdaddy/Git-Issue-Loop-Skill.git` 安装最新版 `iloop` 到 `~/.agents/skills/iloop`；若已有同源安装则安全更新，若目录非同源或存在本地修改则停止并报告；完成后验证 `SKILL.md`。

其中“最新版”由 Agent 解析为远端最高的稳定 `vX.Y.Z` 标签（忽略 `-alpha`、`-beta`、`-rc` 等预发布标签），而不是直接跟踪 `main`。实际安装完成后，Agent 必须报告解析到的 tag 和 commit SHA。

注册后刷新宿主会话，输入 `/iloop` 即可调用。进入具体项目执行闭环前，仍须在该项目仓库根目录运行 `./scripts/git-ops.sh doctor`。
