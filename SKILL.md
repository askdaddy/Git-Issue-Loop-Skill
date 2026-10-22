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
输入是一个 Issue 编号，或一句目标描述（经 [G] 目标登记自动创建为 Issue）；目标是完成验收与 PR 交付后关闭 Issue；仅计划、无法验证、阻塞或未交付时按实际结果停止，不把关闭作为无条件承诺。

**角色简称**：Planner = **PM**（产品/架构），Developer = **开发**，Reviewer = **QA**（质量）。

## 调用入口与交互协议

**显式入口**：斜杠命令 `/iloop`（命令名 = Skill 名 `iloop`）。
自然语言（"落地 issues"、"排 plan"、"验收 git issues"、"推进迭代"）同样可以触发。

**裸 `/iloop`（无任何参数）进入时，自动挑选最该处理的 Issue**，三项信息取默认值、不再向用户追问：

1. **目标 Issue**：由 §3.0.1 第 0 层的「自动挑选」子程序选出唯一一个候选（p0→p3、同优先级编号升序，跳过阻塞与重试超限）。
2. **执行范围**：默认所选 Issue 的**完整闭环**（按其当前阶段 0 帧切入 → 验收与PR交付后关闭，或在缺口/阻塞处停止）；**每次调用只处理 1 个**，推进下一个需再敲一次 `/iloop`。
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
   - QA 的可写区域：`test/` 与仅降级时的 `docs/issues/<N>/verify-report.md`，禁止改动被测业务代码。
   - 开发是唯一有权改动业务代码的角色，且**仅限 `plan.md` 覆盖范围**。
2. **PM 产出的文档主路径写回 Issue**：spec / design / plan 全文以 Issue 评论形式写入；远程可用时**禁止额外落盘本地副本（不做双写冗余）**。
3. **降级 fallback**：仅当远程 Issue 不可用（CLI 缺失 / 未授权 / 平台不支持 / API 调用失败 / 单条内容超出平台限制）时，才降级写入本地 `docs/issues/<N>/`（intake.md / spec.md / design.md / plan.md / verify-report.md，基于 `templates/` 填充；用户显性指定其他路径时以用户为准），并在 Issue 恢复可用后于评论中引用该文件路径。
4. **QA 偏向黑盒测试**：优先从外部可观测行为验证（CLI / API / 端到端），不深入实现细节做白盒断言。
   如需编写测试脚本，**默认生成到项目的 `test/` 目录**，除非用户显性指定其他路径。
5. **每个 Issue 必须有优先级**：由 PM 在 [G]/[T]/[R] 阶段查证后按艾森豪威尔矩阵判定并设置 `p0`~`p3`；
   未设置优先级的 Issue 不得进入 [I] 创新阶段。任何角色新建 Issue 后，也必须立即由 PM 补设优先级。
6. **优先级与状态标签必须用平台原生 label 能力表达，禁止写进 Issue 标题**；优先级、状态、重试计数三族标签各自**排他**（同时只能存在一个，详见 §1.2）。
7. 脚本强制检查其实现覆盖的角色动作、受管标签和路径边界；阶段证据、关闭理由、计划范围及授权由 Agent 按协议核验，不能宣称脚本认证了内容质量。Agent 不得绕过权限。
8. **Issue 操作必须优先使用本地官方 CLI**（GitHub→`gh`，GitLab→`glab`，Gitea/Forgejo→`tea`），由 `git-ops.sh` 自动路由；**禁止**改用 REST API + 手写 token、网页点击或其他绕行方式。本地缺 CLI 或未授权时，**必须停下来把安装/授权指南交给用户**，不得代填凭据、不得跳过 Issue 写回步骤。
9. **提交前必须执行 `./scripts/git-ops.sh guard <当前角色> <N>`，越界即 T0 事故**：脚本以 `git status --porcelain` 比对角色可写区域白名单（PM=`docs/`；开发=除 `test/` 与 `docs/` 外全部，但放行 `docs/issues/<N>/plan.md`；QA=`test/` 与 `docs/issues/<N>/verify-report.md`），命中越界路径即 `exit 1`，必须修正后再提交。`<N>` 为当前 Issue 编号：给出后脚本会额外校验当前分支是否为 `riper/<N>`，不一致即 `exit 1`（防止把改动提交到别的 Issue 的工作区）；分支非 `riper/*` 形态时只提示不失败。**能力边界（如实声明）**：`guard` 只能校验「区域级越界」（文件落在哪个目录），**无法**校验「是否超出 `plan.md` 范围」——后者仍依赖角色自律与 [R] 审查阶段的越界判定。此外 `guard` 取的是 cwd 全量变更，多会话共用主工作树时可能把别人的改动算到本角色头上，脚本会额外打印一段并行污染诊断并指向 `workspace start <N>`（诊断不改变判定与 exit code）。

## 0. 核心约定

- **唯一事实来源**：Issue（正文 + 评论 + 标签）为主；本地 `docs/issues/<N>/` 仅为**降级 fallback，不是持久化副本**——远程可用时不得双写。
- **降级落盘位置**：`docs/issues/<N>/`（intake.md / spec.md / design.md / plan.md / verify-report.md），基于 `templates/` 填充，仅当远程 Issue 不可用时使用；用户显性指定时以用户为准。
- **测试脚本位置**：QA 的黑盒测试脚本默认落 `test/`；用户显性指定时以用户为准。
- **平台操作**：Issue / PR / Release 经 `scripts/git-ops.sh` 执行，禁止直接调用 `gh` / `glab` / `tea`。加载角色后的操作必须携带 `--role <当前角色>`；无角色入口仅可执行自检、标签初始化与分发所需只读命令，不为通过权限检查伪造角色。本地 Git 读写与经授权的 tag 操作按对应阶段执行。脚本按 §1.1 权限矩阵与 §1.2 标签体系硬性校验。子命令清单：`issue list|get|comment|create|close|reopen|priority|status|retry|claim|label`、`labels init`、`guard <role> [N]`、`workspace status|start|finish`、`platform`、`doctor`。
- **工作区隔离（并行会话必须遵守）**：一 Issue 一 worktree 一分支。开工前先 `./scripts/git-ops.sh workspace start <N>`，脚本会在**仓库外** `../.iloop-worktrees/<repo>/<N>` 建 worktree 并挂 `riper/<N>` 分支。基分支恒为 `origin/<默认分支>`，**不基于本地分支**——本地分支可能带着别的会话尚未推送的提交。已经在 linked worktree 内时**不嵌套创建**，只把当前工作区规范化到 `riper/<N>`（detached HEAD 就地挂分支并保留原提交）。收尾用 `workspace finish <N>`（仅当工作区干净且已合并进 `origin/<默认分支>`，否则拒绝清理）；推送 / PR 属集成阶段，见 references/integration.md；默认不自动合并。
- **认领互斥（并行会话必须遵守）**：`workspace start <N>` 成功（先过同机 `riper/<N>` 分支快失败这道硬闸）后，立即 `./scripts/git-ops.sh issue claim <N> claim` 写远端认领信号（`riper-claimed` 标签 + 审计评论），使其他会话的自动挑选跳过本 Issue；若 `claim` 报告"已被认领"则**不抢占**，停下交回用户。释放在闭环终态执行（见 §3.7）。认领是尽力而为信号、非硬锁（详见 §1.2(4)）。
- **cwd 会被宿主重置**：`workspace start` 输出的是 worktree 的**绝对路径**，宿主可能在每次工具调用后把 cwd 重置回会话起点。故后续所有仓库内命令都必须以该绝对路径为 cwd（`cd <绝对路径> && …` 前缀，或使用工具自带的工作目录参数），**不得假设 cwd 会延续**；不确定时先跑 `./scripts/git-ops.sh workspace status` 确认自己在哪个工作树、哪条分支、归属哪个 Issue。
- **平台路由**：脚本通过 `git remote -v` 自动检测并路由到对应 CLI，Agent 无需关心托管平台差异。
- **前置自检**：先分类调用；help 终止、仅检查更新等独立请求按入口处理，其余进入循环前先跑 `./scripts/git-ops.sh doctor`（检查运行环境 + CLI 安装 + 授权状态）。不就绪时脚本会输出安装/授权指南并 `exit 1`，Agent 必须中止循环、把指南**原样呈现给用户**，待用户完成后重跑 `doctor` 再继续；完整指南见 `references/cli-setup.md`。
- **凭据安全**：禁止代用户输入 token，禁止将凭据写入仓库文件、脚本、`.env` 或提交到版本库。
- **运行环境**：仅支持 macOS 与 Windows。Windows 下 `git-ops.sh` 必须在 Git Bash 中运行（随 Git for Windows 自带），不支持 CMD / PowerShell。macOS 宿主默认 shell 常为 zsh；Agent 执行安装/更新协议等**内联 shell** 时必须用 **bash**（zsh 缺 `shopt` / `nullglob` 等 bash 内建，直接跑会 `command not found`）。随附脚本已带 `#!/usr/bin/env bash`，经 `./script.sh` 调用恒在 bash 下运行、天然安全。

## 1. 多角色驱动机制（Persona Loading）

**先完成 §3.0.1 启动分发（含第三方接入路由判断），再按分发结果读取对应的一份角色文件。** 禁止为了「看看该不该调研」而预加载 PM。Skill 更新检查、doctor 与 `labels init` 不需要角色。

**进入分发指定的 RIPER 阶段之前，必须先完成该阶段的角色切换：**

| 阶段 | 角色文件 | 角色 | 可写区域 |
|------|----------|------|----------|
| [T] 第三方接入（前置，非新状态） | `roles/planner.md` | PM | Issue 评论；仅降级 docs/ |
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
| push / PR / Release 元数据 | ❌ | ❌ | ✅（按集成契约） |
| 本地降级合并 | ❌ | ✅（用户显式指定目标） | ❌ |
| PR 自动合并 | ❌ | ❌ | ❌ |
| 工作区清理 | 环境能力保留 | 环境能力保留 | 收尾负责（已进上游） |
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
| `issue retry <N> reset` | 三角色 | 清零（移除全部 `riper-retry-*`），仅用户明确授权重置时用；恢复、接入或重新调用不得自动清零 |

唯一入口：`./scripts/git-ops.sh --role reviewer issue retry <N> <incr|get|reset>`（脚本自动排他清理同族）。`issue label` 子命令被禁止触碰本族。

**（4）认领族（受管，不排他，多会话互斥信号）**

`riper-claimed`：标记某 Issue 已被某会话认领，自动挑选跳过之。与 `riper-retry-*` 同构——把"谁认领了"落到 Issue 标签，不依赖 Agent 跨会话记忆。它是**受管内置标签**（由 `labels init` 创建、`doctor` 校验，故内置标签总数为 15 = 4 + 7 + 3 + 1），但**非排他**（不属上述三互斥族，`is_priority/status/retry_label` 均不匹配它）。

| 操作 | 可用角色 | 说明 |
|------|----------|------|
| `issue claim <N> claim` | 三角色 | 写 `riper-claimed` 标签 + 一条审计评论（会话标识 / UTC 时间戳 / worktree 路径 / 分支）；**若已被认领则拒绝并回显既有认领，不抢占** |
| `issue claim <N> release` | 三角色 | 移除标签 + 释放评论；未认领时幂等只报告 |
| `issue claim <N> get` | 三角色（只读） | 输出 `claimed` / `unclaimed`，供自动挑选廉价可靠读取（同构 `retry get`） |

唯一入口：`./scripts/git-ops.sh issue claim <N> <claim|release|get>`。`issue label` 子命令被禁止触碰本族（保证标签与审计评论同时落地）。

**认领时机与局限**：认领应在 `workspace start <N>` 成功（先过同机分支快失败这道硬闸）之后再写远端信号；释放在闭环终态（`riper-verified`）或转 `riper-blocked` 时执行。**陈旧认领（长时间无状态推进）只报告、不自动抢占**——抢占属影响他人工作的动作，处置权交回用户。**认领是尽力而为的信号、非硬分布式锁**：两会话可能都读到"未认领"而先后写入，真·同时竞态无法靠标签消除，同机硬闸是 workspace 的 `riper/<N>` 分支快失败。

**（5）自由标签（可选，不排他）**：Agent 可自行定义用于上下文召回，如 `module/auth`、`type/bug`、`area/cli`。
通过 `issue label <N> add|remove <标签>` 操作；脚本禁止用该子命令触碰上述受管族（优先级 / 状态 / 重试 / 认领）。

## 2. SDD 核心原则（Spec-Driven Development，不可违反）

1. **计划即契约**：Execute 阶段必须逐条满足 `plan.md` 中的步骤与验收标准，**禁止跳过、禁止合并、禁止添加计划外功能**。HOW（实现路径）由 `references/lazy-ladder.md` 约束：在验收范围内取更高 rung 的最短 diff；合法改道须按该文件格式评论。验收标准冻结 WHAT；涉及文件与逻辑说明是建议，不是牢笼。
2. **计划有误必回退**：发现计划有误（缺步骤、错文件、顺序不对）必须：立即**中断执行** → 退回 Plan 阶段更新 `plan.md` 并同步评论到 Issue → 再从更新后的步骤继续。严禁"边改边做、事后补计划"。
3. **验收只认计划**：Review 阶段依据冻结验收与明确边界按 §2.1 判定 PASS/FAIL/无法验证，不接受"代码能跑就算过"。
4. **文档先行**：任何代码提交之前，对应的 spec / design / plan 必须已经存在且填充完整。

### 2.1 判定、交接与强制边界

本节定义跨角色共同决策；角色文件引用本节，不另设一套出口。Skill 内的 T0 仅表示本协议优先级，不覆盖用户指令或宿主的更高层指令。

|判定|证据条件|后续|
|---|---|---|
|PASS|当前基线的验收项已实际验证满足，且无确认越界|全部 PASS 后才能进入集成交付|
|FAIL|实际证据证明违反冻结验收或角色/计划边界|QA 登记一次该轮失败，退 plan；PM 确认或修订后开发继续|
|无法验证|环境、权限或证据不足，不能确定是否满足|保留未知；不当产品失败，不因此增加 retry，不得判全部通过|

不能用后续建议新增验收；明确越界仍可 FAIL。同一审查轮次多个失败只增加一次 retry；已记录的同一报告恢复不重复增加。重试3表示自动重试预算已用完；恢复须核验既有记录，不通过接入/重跑/reset绕过。

每次交接在原 Issue 评论记录：Issue/仓库、有效产物版本与链接、当前状态/下一角色、已验证提交 SHA（没有则 unknown）、已完成/未完成项、验证方式与判定、阻塞/恢复条件及授权范围。主路径不建本地交接副本。

[T] 的 pending-handoff 只授权下一有权角色进行已记录的标签对齐；严格回读并追加 complete 后才开始业务工作。开发、QA 同样必须核对，不凭已有 plan 越过该闸门。

脚本只强制其实现覆盖的命令权限和路径；不认证角色身份、语义质量、关闭证据或授权。guard 失败先停止并核对归属，不删除他人变更。无角色兼容放行不能作为 Agent 绕过依据。缺 CLI/授权时停止远端流程并交指南；fallback 只保存可支持的未完成产物，不等于通过自检、读取完整或获得继续执行许可。

## 3. RIPER 状态机循环

### 3.0 前置自检（每轮循环开始前）

先识别 §3.0.1 第0层的调用意图，再执行本节。help 直接本地应答并停止；仅检查更新只运行 check-update；仅 doctor 完成诊断后停止，不初始化标签。复核/建议类请求只读回答，不自动当新目标建票；用户授权开票后才进入 [G]。进入 Issue 闭环才执行下列完整前置流程。doctor 因缺标签失败时，先确认 CLI/授权成功，再执行 labels init 并重跑 doctor；其他失败不得用初始化标签掩盖。

1. **Skill 更新检查（先于 doctor；本会话尚未执行过时）**：以**当前加载的 `SKILL.md` 所在目录**为 Skill 根（默认 `~/.agents/skills/iloop`，不是目标项目仓库根），执行：
   `bash <Skill根>/scripts/check-update.sh`
   无角色。比较本地 `git describe --tags --exact-match`（失败则为 untagged + HEAD SHA）与清单 `distribution.repository` 上最高稳定 tag（`vX.Y.Z`，忽略预发布）。**禁止**用目标项目 `git remote`，**禁止**把 `skill-manifest.json` 的 `skill.version` 当作已安装版本。
   - `status=current`（exit 0）→ 继续 doctor。
   - `status=update-available`（exit 2）→ 向用户展示 `local_ref` 与 `latest_tag`，询问**升级**或**本次跳过**。Agent **不得自行升级**。升级则只执行 `INSTALL.md` 的一句话协议，完成后提醒刷新宿主会话；本轮默认停止（协议已变），用户明确要求继续才用**新** Skill 重入 §3.0。跳过则继续 doctor。
   - `status=untagged`（exit 2）→ 说明当前为非稳定安装并列出 `latest_tag`；默认继续本轮，用户也可选择改去安装稳定版。
   - 检查失败（exit 1，含网络 / 非 git / 无稳定 tag）→ **必须**把脚本给出的 git 失败原因（`check-update: git: …` 行）与 `local_ref`（当前已安装的版本）一并转述给用户，并明确说明**「本次无法确认是否为最新版」**；声明后**不阻塞**，继续 doctor。禁止只说「更新检查失败」了事。
2. 执行 `./scripts/git-ops.sh doctor`（在**目标项目**仓库根）：依次确认运行环境（macOS / Windows Git Bash）、remote 路由到的 CLI、CLI 已安装、CLI 已授权。
3. doctor 通过后，若本次会话尚未执行过，运行 `./scripts/git-ops.sh labels init`（幂等）：确保优先级 / 状态 / 重试 / 认领所需的 15 个内置标签（4 优先级 + 7 状态 + 3 重试 + 1 认领）在平台上存在，并规范化仓库级 `P0`–`P3` 等优先级大小写变体；迁移其 open/closed Issue 关联并回读验证后才删除变体，任一步失败即保留变体并 `exit 1`。doctor 也会检查这套标签是否就绪，缺失即 `exit 1` 并提示运行 `labels init`。
4. **全部通过** → 进入 §3.0.1 启动分发。**禁止在分发完成之前读取任何 `roles/*.md`。**
5. **CLI 缺失或未授权** → 立即中止，把脚本输出的安装/授权指南（或 `references/cli-setup.md` 对应章节）原样交给用户，说明需要完成的具体动作；用户确认完成后重跑 `doctor`，通过再从中断阶段继续。
6. 严禁绕行：不得改用 curl + REST API、不得猜测/代填 token、不得跳过 Issue 侧的读写步骤。

### 3.0.1 启动分发（Dispatch，无角色）

doctor / `labels init` 通过后、加载任何角色之前执行。本层是协议查表，不是第四个 Persona：路由判断不读业务代码、不写 spec、不为了「看看该不该调研」而预加载 PM。判定需要第三方接入时，先完成接入路由分发，再进入 PM 前置查证，完成后返回普通分发。

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

1. **取候选四元组**（仅经 `git-ops.sh` 只读子命令；**禁止**为此提前加载任何 `roles/*.md`，禁止写状态/写标签/写评论）：`issue list --state open` 给出编号、优先级、RIPER 状态；retry 值逐个调 `issue retry <N> get`、认领状态逐个调 `issue claim <N> get`（列表**不含** retry / 认领列，二者单独读；`riper-claimed` 已被排除出状态列，不会污染 RIPER 状态）。若列表无标签列（glab/tea 降级，优先级/状态显示 `(无)`），改逐条 `issue get <N>` 读真实标签，并在报告中**标注该降级依据**，禁止按 `(无)` 占位静默误选。<!-- lazy-ladder: 逐条 retry get / claim get，open 量大时改 issue list 输出补 retry / 认领列 -->
2. **排序**：p0 → p1 → p2 → p3 → 无优先级；同键按编号升序（更老的先收尾）。无标签/未分类/来源 unknown 的候选必须展示，标注需接入；此时不分析业务代码、不修标签。该顺序由本步负责，不依赖 `issue list` 的打印顺序。
3. **跳过规则**：`riper-blocked`（等人工介入）、`riper-retry-3`（重试超限）、`riper-verified` 但未关闭（异常态，仅提示人工关闭/重开，不改状态）、`riper-claimed`（已被其他会话认领，`issue claim <N> get` 输出 `claimed`），四者均不参选并须写明原因。陈旧认领只报告、不自动抢占（抢占属影响他人工作的动作，交回用户）。
4. **呈报并等确认**：输出候选清单，每条含 `编号 / 优先级 / RIPER 状态 / retry 值 / 认领状态 / 是否跳过及原因`，末行给出选中项与一句话理由；**停在此处等用户确认或改选**，不得选完直接开工。改选任一编号等同显式 `/iloop <编号>`，重新进第 1 层分发。
5. **终止分支**：无 open Issue → 报告空态并指向 `[G]` 目标登记，**禁止**自动建 Issue、不加载角色；全部候选被跳过 → 报告各自卡点原因后停止，不改任何状态（对齐 `riper-blocked 不参与前进`）。
6. 挑选报告是对话内产物，**不落盘、不写 Issue 评论**（避免污染 Issue 这一唯一事实来源）。

**执行范围是上限，分发结果是入口（C9）**：完整闭环可走到 `riper-verified`；只到计划则入口已是 `[E]`/`[R]审查` 时报告并停止，不擅自回退阶段；只做验收若非用户覆盖，不得把仍在执行中的 Issue 强行改成审查。

#### 第 1 层：阶段分发（Issue 证据）

对编号 N 执行 `./scripts/git-ops.sh issue get <N> --strict`（此时仍无角色；`get` 不限角色）。正文或评论读取失败即暂停，禁止将部分输出当完整依据。从标签读取唯一 `riper-*`、`p0`–`p3`、`riper-retry-*`。用下列标记扫描评论与降级文件 `docs/issues/<N>/`（命中只视为候选产物，不证明有效或冻结）：

| 产物 | 评论或文件标记 |
|------|----------------|
| spec | `# Spec` 或 `阶段: [R] Research` |
| design | `# Design` 或 `阶段: [I] Innovation` |
| plan | `# Plan` 或 `阶段: [P] Plan` |
| verify-report | `Verify Report` / `verify-report`，或同时含 `阶段: [R] Review` 与逐项 PASS/FAIL |

自定义评论标题须保留上表标记，否则产物检测会漏。

**第三方接入路由（先于普通阶段切入）**：按 [接入协议](references/issue-intake.md) 先保护 closed/verified/blocked、retry 上限及他人认领，再核对来源和既有接入记录。已核验目标直入 [G] 且需求/产物一致可原阶段续跑；外部或来源 unknown、未有效接入或内容实质变化者，分发为 PM 的 `[T]` 前置入口，**此时完成接入路由分发后才加载 planner.md**，不得在候选初筛时预加载角色。不要只看作者、标签或标题认定来自 Skill。

PM 按 templates/intake.md 先查证、评论待确认问题/标签建议，再写前重读、按权限最小修正 labels、写后回读。接入自身不改业务代码；未查清或读取/修标签失败则暂停；不能用接入重置合法阶段、retry、claim。PM 不得设置超出其权限的状态，有权角色交接完成前不得开始业务工作。已完成且无实质变化时复用，不重复调查。

接入完成回到本层按下面证据规则分发；Research 引用接入证据只补缺口。`[T]` 没有新状态标签，不替代研究/冻结计划；详情、字段、并发及 #37 能力边界均见接入协议。裸入口仅对用户已确认目标执行本段，显式编号共用本段。


**有效性核验**：标题标记只定位候选；按评论时间与明确修订关系找到当前基线，检查所属 Issue、原始需求/验收范围、内容完整性、待解问题、计划冻结记录与代码基线适用性。新评论不自动取代旧基线；相互冲突或无法确定有效版本时暂停澄清，不把标题、空模板、旧 PASS 当有效证据。

**证据阶段**：以下 spec/design/plan 均指有效产物。仅首版或明确替代当前基线的成功阶段产物推进；FAIL 后最新 plan 的 PM 确认/修订必须晚于对应失败报告，否则仍属修计划。无 spec → 早于研究；有 spec 无 design → 研究完成；有 design 无 plan → 创新完成；有冻结 plan → 计划完成；有 verify-report 或 retry>0 且状态为 `riper-plan` → FAIL 回退修计划（不要当第一版 plan 来写）。

**先保护终态与协调信号，再核验产物决定切入点**。有效 spec 完成后可由 research 进入 innovation，有效 design 完成后可由 innovation 进入 plan；已冻结 plan 且非 FAIL 修订中可由 plan 进入 execute，按 C6 对齐状态，避免停在同阶段反复分发。证据不足时以证据支持的阶段限制超前标签；不能机械取 min 而阻止已完成阶段合法前进。标签超前于产物时，以产物为准往回退（例如标了 `riper-execute` 但没有 plan → `[P]`）。

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

**glab/tea 降级**：列表看不到标签时严格读取目标真实标签；严格详情仍缺标签/认领/终态保护所需字段时暂停，不能仅靠产物标记把不可见状态当无状态或重写标签。不要为此改用 REST API，也不要为此去实现 `issue get --json`。

**状态写入（C6）**：进入某 §3.x 时，`issue status` 对齐该阶段仅当：当前无状态、当前等于本阶段、当前早于本阶段，或本次切入来自产物回退（证据早于标签，允许把超前标签拉回证据阶段），或用户显性「重做某阶段」，或 QA FAIL 退回 `riper-plan`。禁止在分发结果不是 `[R]` 时把 `riper-execute` / `riper-review` / `riper-verified` 改回 `riper-research`。

分发结束后**才**读取对应的一份 `roles/*.md`，从该节现有步骤继续，不重跑被跳过的阶段。

### 状态流转图

```
目标描述（一句，可选入口）
   │ 第 0 层：新目标 → PM [G] 草稿 → 确认 → create → 优先级 → riper-research
   ▼
Issue(编号 N)
   │ 严格读取 → 终态/认领保护 → 必要时 PM [T] 查证与标签对齐
   │ 启动分发（§3.0.1）：核验有效产物；合法续跑；口头覆盖受权限约束
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
                   riper-verified → QA 推送并核验 PR → 写回证据 → 关闭并释放认领
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
5. 如有有效接入记录，先引用其已核验证据与问题，仅补缺口，不重复调查。阅读正文与全部评论，**只读**拉取相关代码上下文（涉及文件、模块、依赖）。
6. 按 `templates/spec.md` 提炼规范：原始需求、上下文代码、核心约束、澄清假设。
   - **已有 spec**（评论或降级文件命中 §3.0.1 产物标记）：只补缺口或澄清，**禁止从零重开调研**；spec 已完整则进入 §3.0.1 让下一阶段接手（通常为 `[I]`）。
   - **尚无 spec**：全文以评论写入 Issue → `./scripts/git-ops.sh --role planner issue comment <N> "<spec 全文>"`，不落盘本地；
   - **降级 fallback**（CLI 缺失 / 未授权 / 平台不支持 / API 失败 / 内容超限时）：写入 `docs/issues/<N>/spec.md`，并在 Issue 恢复后评论引用该文件路径。
7. 若需求存在无法用假设消解的歧义，在 Issue 下评论提问并暂停循环，等待用户回复。

### 3.3 [I] 创新阶段（Innovation）— PM

1. **重新读取 `roles/planner.md` 与梯子**，保持 PM 角色。
2. 切换状态：`./scripts/git-ops.sh --role planner issue status <N> riper-innovation`。
3. 基于 spec 思考**至少两种**技术方案，按复杂度、风险、可测性、可维护性、与现有代码契合度、**代码量**、**是否新依赖**对比，选定最终方案并说明理由（先读 `references/lazy-ladder.md`）。
4. design 全文评论写回 Issue（主路径，基于 `templates/design.md` 组织）；仅当远程 Issue 不可用时降级写入 `docs/issues/<N>/design.md`。
5. **全程只读代码，不得产出或修改任何实现代码（T0）。**

### 3.4 [P] 计划阶段（Plan）— PM

1. **重新读取 `roles/planner.md` 与梯子**，保持 PM 角色。
2. 切换状态：`./scripts/git-ops.sh --role planner issue status <N> riper-plan`。
3. 基于 design 拆解**极细粒度**原子任务：每步只做一件事，含编号、涉及文件、逻辑说明、验收标准、完成状态 `[ ]`。**验收标准冻结 WHAT**（可观察结果，禁止把实现类名/新建文件当作验收项）；**涉及文件与逻辑说明是建议 HOW，不冻结**。
4. **主路径不落盘**：plan 随下一步的独立评论写回 Issue；仅当远程 Issue 不可用时降级填充 `docs/issues/<N>/plan.md`（基于 `templates/plan.md`）。
5. 仅评论写回本次 plan 全文，并引用当前有效 spec、design 的评论链接或标识，不重复粘贴三份全文；修订时说明替代的基线与变化。
   `./scripts/git-ops.sh --role planner issue comment <N> "<plan 全文与输入引用>"`。
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
4. 按仓库既有规范提交代码，提交信息引用 Issue 编号（如 `... (#N)`）。**代码必须提交到本 Issue 的 `riper/<N>` 分支，不得提交到默认分支**（见 §0 工作区隔离）；提交前跑 `./scripts/git-ops.sh --role developer guard developer <N>`，它会同时校验可写区域与「当前分支是否就是 `riper/<N>`」。
5. 交付审查：`./scripts/git-ops.sh --role developer issue status <N> riper-review`。

### 3.6 [R] 审查阶段（Review）— QA

1. **加载角色**：先读 `references/lazy-ladder.md`，再读 `roles/reviewer.md`，切换为 QA。
2. 对照计划（Issue 评论中的 plan，或降级产生的本地 `plan.md`）每一步的验收标准，**以黑盒方式**执行测试与代码审查（读代码属只读，禁止修改业务代码，T0）。PASS/FAIL/无法验证按 §2.1 判定，只认验收标准 + 越界行为（多余功能或未批准新依赖）；多碰文件本身不 FAIL。
3. 如需编写测试脚本，默认生成到 `test/` 目录（用户显性指定时以用户为准）。
4. 按 `templates/verify-report.md` 生成 verify-report 全文并评论写回 Issue：逐项判定、证据、失败原因分析；附加检查含可删清单（`delete:` / `stdlib:` / `native:` / `yagni:` / `shrink:`），**不单独 FAIL、不阻塞判定、不计入重试**。
5. 仅当远程 Issue 不可用时降级写入 `docs/issues/<N>/verify-report.md`，恢复后在评论中引用。

### 3.7 状态判定（Loop Control）

集成原语：`git-ops.sh --role reviewer integration push|pr-list|pr-view|pr-create|release-view|release-create`；本地降级仅 developer 的 `integration local`。参数和矩阵见 [集成与发布](references/integration.md)。发布需独立授权且 tag + GitHub Release 两部分完成，不能随 Issue 自动发布。

- **全部 PASS**：
  1. `./scripts/git-ops.sh --role reviewer issue status <N> riper-verified`；
  2. 评论总结闭环结论；
  3. QA 按 [集成契约](references/integration.md) 执行 `integration push <N>`、PR 查重/创建/回读，并将 URL、base/head 与已验收提交评论回 Issue；默认不自动合并。离线或无推送权限仅本地合并仍保持 open，无法继续则报告并按权限转 blocked。
  4. 仅在 PR 交付已确认（或有已进上游证据）后，由 QA 执行 `./scripts/git-ops.sh --role reviewer issue close <N>` 关闭 Issue（关闭权专属 QA），结束循环；
  5. 释放认领：`./scripts/git-ops.sh issue claim <N> release`（移除 `riper-claimed` + 释放评论；闭环终态不再占用该 Issue）。
- **无法验证且无已确认 FAIL**：不设置 verified、不关闭、不增加 retry；报告缺失环境/证据、已完成项与恢复条件。无法推进时由开发/QA 按权限转 blocked 并释放认领，恢复后严格重读与分发。
- **存在已确认 FAIL**（即使同时有无法验证项）：
  1. 登记重试计数（**防死循环：最多重试 3 次**）：`./scripts/git-ops.sh --role reviewer issue retry <N> incr`（排他写入 `riper-retry-K`，不依赖 Agent 记忆）；
  2. QA 退回计划：`./scripts/git-ops.sh --role reviewer issue status <N> riper-plan`，并评论失败分析；
  3. PM 核对根因：计划有误才修订并登记；仅实现缺陷则评论确认冻结基线仍有效和重做范围，不改验收标准。PM 不能写 execute，切开发后由开发对齐状态；
  4. 重新走 [E] → [R]。
- **重试已达上限仍有 FAIL**（`./scripts/git-ops.sh --role reviewer issue retry <N> get` 返回 `3`，此时 `incr` 也会被拒绝）：停止循环，`./scripts/git-ops.sh --role reviewer issue status <N> riper-blocked`，在 Issue 下评论说明卡点，并 `./scripts/git-ops.sh issue claim <N> release` 释放认领（本会话不再持有，待人工介入后可重新认领），等待人工介入。

## 3.8 运行时反馈闭环

发现角色操作被拒绝、guard 越界或 Issue 阶段证据缺失时，先保留原拒绝和任务纠偏，再按 [反馈协议](references/feedback-loop.md) 组织事实、离线草稿、去重、授权提交与维护验证。阶段交接必须检查标签、产物与未完成验收。反馈不替代 QA、不自动计入 retry；疑似问题不直接归责。

`bash <Skill根>/scripts/feedback.sh draft <permission|guard|evidence> <suspected|confirmed|intercepted|false-positive>` 仅输出有限字段草稿，不联网、不落盘、不上报；所有角色可用。上游写入必须明确授权并经维护工作副本的 git-ops.sh，详见协议。

## 3.9 运行时输出与阶段摘要（可选观测）

默认关闭。开启后脚本只把结构化事件写入**调用者预先打开的 fd3**（`exec 3>…` + `ILOOP_EVENTS_FD=3`），不写日志文件、不联网；首版覆盖 `issue priority` / `issue status` / `issue comment` / `guard`。字段枚举、`run_id` 跨进程传递、失败隔离与脱敏边界见 [运行时输出契约](references/runtime-output.md)。

Agent 在启动/分发、阶段交接、暂停、恢复、结束时按 [阶段摘要模板](templates/run-summary.md) 说明当前阶段与角色、进入依据、已完成/未完成、下一步与等待原因，区分 `[script-observed]`、`[agent-declared]` 与 `[unverified]`，并关联 `run_id`。已有业务 Issue 仅在关键节点按合理批次写回评论；无 Issue、只读候选、help 或未确认目标不写评论；不复制 spec/design/plan 全文，不建本地双写或事件日志。

**边界**：脚本操作成功不等于阶段完成或验收 PASS；摘要写回失败或部分完成须如实报告，重试前先去重，不盲目重复评论。事件与摘要都不改变角色权限、远端写入语义或产品验收判定。

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
./scripts/git-ops.sh labels init                                  → 初始化 15 个内置标签并规范化仓库级优先级大小写变体（幂等；新仓库首次必跑）
./scripts/git-ops.sh issue list [--state open|closed|all] [--status <riper-*>] [--priority <p0..p3>]
                                                                  → 列出 Issue，按优先级 p0→p3 排序（glab/tea 无标签列时降级）
./scripts/git-ops.sh --role reviewer issue retry <N> <incr|get|reset> → 重试计数持久化（incr 仅 QA；get/reset 不限角色）
./scripts/git-ops.sh issue claim <N> <claim|release|get>          → 认领互斥（非排他 riper-claimed；claim 写标签+审计评论，已认领则拒绝抢占；release 释放；get 读 claimed/unclaimed）
./scripts/git-ops.sh guard <role> [N]                             → 可写区域越界自检（提交前必跑；越界 exit 1；给出 N 则同时校验当前分支是否为 riper/<N>）
./scripts/git-ops.sh workspace status                             → 报告当前在哪个工作树/分支、归属哪个 Issue、worktree 清单（只读，随时可跑）
./scripts/git-ops.sh workspace start <N>                          → 为 Issue N 建隔离工作区：仓库外 ../.iloop-worktrees/<repo>/<N> + riper/<N> 分支，基于 origin/<默认分支>
./scripts/git-ops.sh workspace finish <N>                         → 清理 Issue N 的本地工作区（仅当干净且已合并进上游；不推送、不合并）
./scripts/git-ops.sh doctor                                       → 环境 + CLI + 授权 + 标签体系就绪自检
exec 3>events.ndjson; ILOOP_EVENTS_FD=3 ./scripts/git-ops.sh …     → 受覆盖命令向 fd3 写一条 NDJSON 事件（默认关闭，契约见 references/runtime-output.md）
```

## 5. 安装与注册（让 `/iloop` 生效）

本 Skill 以 GitHub 仓库分发。默认安装位置为 `~/.agents/skills/iloop`，目录名必须与 frontmatter 的 `name`（`iloop`）一致。面向 Agent 的安装入口、版本解析和安全切换协议见仓库根目录的 `INSTALL.md`；机器可读约束见 `skill-manifest.json`。同源更新时旧安装备份为 `~/.agents/backups/iloop.backup-<时间戳>`（**不在** `skills/` 下：部分宿主会把点目录也当成技能扫描，隐藏前缀不足以避免第二条 `/iloop`）。暂存克隆到 `${TMPDIR:-/tmp}/iloop.staging-<随机值>`。同源更新时先 clone staging，再按 staging 内 `INSTALL.md` / `skill-manifest.json` 做备份与切换。

**用户只需说一句话**：

> 请从 `https://github.com/askdaddy/Git-Issue-Loop-Skill.git` 安装最新版 `iloop` 到 `~/.agents/skills/iloop`；若已有同源安装则安全更新，若目录非同源或存在本地修改则停止并报告；完成后验证 `SKILL.md`。

其中“最新版”由 Agent 解析为远端最高的稳定 `vX.Y.Z` 标签（忽略 `-alpha`、`-beta`、`-rc` 等预发布标签），而不是直接跟踪 `main`。实际安装完成后，Agent 必须报告解析到的 tag 和 commit SHA。

注册后刷新宿主会话，输入 `/iloop` 即可调用。进入具体项目执行闭环前，仍须在该项目仓库根目录运行 `./scripts/git-ops.sh doctor`。
