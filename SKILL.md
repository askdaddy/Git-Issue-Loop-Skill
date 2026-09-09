---
name: iloop
description: >-
  Issue 驱动的 RIPER 研发闭环工作流，显式调用入口为斜杠命令 /iloop。当用户输入 /iloop，
  或要求"落地 issues"、"排 plan"、"验收 git issues"、"推进迭代"，或提到 RIPER、SDD、
  Issue 驱动开发、研发闭环时触发。自动完成 研究→创新→计划→执行→审查 五阶段循环，
  支持 GitHub / GitLab / Gitea / Forgejo（gh / glab / tea），并在阶段切换时自动加载
  Agent Persona（PM=planner / developer / QA=reviewer）。
---

# iloop（git-issue-loop）：Issue 驱动的 RIPER 研发闭环

本 Skill 将 Git Issue 的生命周期与 RIPER 工作流深度融合。
输入是一个 Issue 编号，输出是一个通过验收、状态为 `riper-verified` 且已关闭的研发闭环。

**角色简称**：Planner = **PM**（产品/架构），Developer = **开发**，Reviewer = **QA**（质量）。

## 调用入口与交互协议

**显式入口**：斜杠命令 `/iloop`（命令名 = Skill 名 `iloop`）。
自然语言（"落地 issues"、"排 plan"、"验收 git issues"、"推进迭代"）同样可以触发。

**无参数进入时，必须先问清三件事再开工**（用户已给出的信息不得重复追问）：

1. **目标 Issue**：编号是多少？若用户不确定，先跑 `./scripts/git-ops.sh doctor`，再列出 open issues（按优先级 p0→p3 排序）供选择。
2. **执行范围**：完整闭环（R→I→P→E→R）/ 只到计划（R→I→P）/ 只做验收（R 审查）/ 仅环境自检（doctor）。
3. **落盘确认**：阶段文档主路径写回 Issue 评论，仅当远程 Issue 不可用时才降级写入本地 `docs/issues/<N>/`（降级目录是否沿用默认）；QA 测试脚本默认 `test/` —— 是否沿用默认（用户显性指定时以用户为准）。

问清后进入 §3.0 前置自检与 RIPER 循环。
容错：若用户在 `/iloop` 后直接带了编号或阶段意图（如 `/iloop 42`、"只排 plan"），直接采用，不再追问该项。

## T0 铁律（最高优先级，与任何规则冲突时以此为准）

1. **PM 与 QA 不得改动任何业务代码**——只读代码。违反即 T0 事故。
   - PM 的唯一可写文件区域：`docs/`，且**仅用于降级落盘**（见铁律 3；远程可用时产出一律评论写回 Issue）。
   - QA 的唯一可写区域：`test/`（黑盒测试脚本），禁止改动被测业务代码。
   - 开发是唯一有权改动业务代码的角色，且**仅限 `plan.md` 覆盖范围**。
2. **PM 产出的文档主路径写回 Issue**：spec / design / plan 全文以 Issue 评论形式写入；远程可用时**禁止额外落盘本地副本（不做双写冗余）**。
3. **降级 fallback**：仅当远程 Issue 不可用（CLI 缺失 / 未授权 / 平台不支持 / API 调用失败 / 单条内容超出平台限制）时，才降级写入本地 `docs/issues/<N>/`（spec.md / design.md / plan.md / verify-report.md，基于 `templates/` 填充；用户显性指定其他路径时以用户为准），并在 Issue 恢复可用后于评论中引用该文件路径。
4. **QA 偏向黑盒测试**：优先从外部可观测行为验证（CLI / API / 端到端），不深入实现细节做白盒断言。
   如需编写测试脚本，**默认生成到项目的 `test/` 目录**，除非用户显性指定其他路径。
5. **每个 Issue 必须有优先级**：由 PM 在 [R] 阶段按艾森豪威尔矩阵判定并设置 `p0`~`p3`；
   未设置优先级的 Issue 不得进入 [I] 创新阶段。任何角色新建 Issue 后，也必须立即由 PM 补设优先级。
6. **优先级与状态标签必须用平台原生 label 能力表达，禁止写进 Issue 标题**；两族标签各自**排他**（同时只能存在一个）。
7. 上述权限由 `git-ops.sh --role <角色>` 在脚本层硬性强制，Agent 不得以任何方式绕过。
8. **Issue 操作必须优先使用本地官方 CLI**（GitHub→`gh`，GitLab→`glab`，Gitea/Forgejo→`tea`），由 `git-ops.sh` 自动路由；**禁止**改用 REST API + 手写 token、网页点击或其他绕行方式。本地缺 CLI 或未授权时，**必须停下来把安装/授权指南交给用户**，不得代填凭据、不得跳过 Issue 写回步骤。

## 0. 核心约定

- **唯一事实来源**：Issue（正文 + 评论 + 标签）为主；本地 `docs/issues/<N>/` 仅为**降级 fallback，不是持久化副本**——远程可用时不得双写。
- **降级落盘位置**：`docs/issues/<N>/`（spec.md / design.md / plan.md / verify-report.md），基于 `templates/` 填充，仅当远程 Issue 不可用时使用；用户显性指定时以用户为准。
- **测试脚本位置**：QA 的黑盒测试脚本默认落 `test/`；用户显性指定时以用户为准。
- **Git 操作**：一律通过 `scripts/git-ops.sh` 执行，禁止直接调用 `gh` / `glab` / `tea`。Agent 调用时**必须携带 `--role <当前角色>`**，脚本按 §1.1 权限矩阵与 §1.2 标签体系硬性校验。
- **平台路由**：脚本通过 `git remote -v` 自动检测并路由到对应 CLI，Agent 无需关心托管平台差异。
- **前置自检**：进入循环前先跑 `./scripts/git-ops.sh doctor`（检查运行环境 + CLI 安装 + 授权状态）。不就绪时脚本会输出安装/授权指南并 `exit 1`，Agent 必须中止循环、把指南**原样呈现给用户**，待用户完成后重跑 `doctor` 再继续；完整指南见 `references/cli-setup.md`。
- **凭据安全**：禁止代用户输入 token，禁止将凭据写入仓库文件、脚本、`.env` 或提交到版本库。
- **运行环境**：仅支持 macOS 与 Windows。Windows 下 `git-ops.sh` 必须在 Git Bash 中运行（随 Git for Windows 自带），不支持 CMD / PowerShell。

## 1. 多角色驱动机制（Persona Loading）

**进入任何 RIPER 阶段之前，必须先完成角色切换：**

| 阶段 | 角色文件 | 角色 | 可写区域 |
|------|----------|------|----------|
| [R] 研究 | `roles/planner.md` | PM | `docs/` + Issue |
| [I] 创新 | `roles/planner.md` | PM（保持） | `docs/` + Issue |
| [P] 计划 | `roles/planner.md` | PM（保持） | `docs/` + Issue |
| [E] 执行 | `roles/developer.md` | 开发 | 业务代码（限 plan 范围）+ `docs/issues/<N>/plan.md` 勾选 |
| [R] 审查 | `roles/reviewer.md` | QA | `test/` + `docs/issues/<N>/verify-report.md` + Issue |

角色切换规则：

1. Agent **必须先完整读取** `roles/` 目录下对应角色文件的全部内容。
2. 严格按照文件中的指令设定当前的角色、语气、行为边界和约束，直到本阶段结束。
3. 角色文件可被用户随时修改；每次进入阶段都重新读取，**不得缓存上一次的角色设定**。
4. 未完成角色加载前，禁止产出任何该阶段的工作成果。

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

**（3）自由标签（可选，不排他）**：Agent 可自行定义用于上下文召回，如 `module/auth`、`type/bug`、`area/cli`。
通过 `issue label <N> add|remove <标签>` 操作；脚本禁止用该子命令触碰上述两个互斥族。

## 2. SDD 核心原则（Spec-Driven Development，不可违反）

1. **计划即契约**：Execute 阶段必须严格逐条执行 `plan.md` 中的步骤，**禁止跳过、禁止合并、禁止自由发挥、禁止添加计划外功能**。
2. **计划有误必回退**：发现计划有误（缺步骤、错文件、顺序不对）必须：立即**中断执行** → 退回 Plan 阶段更新 `plan.md` 并同步评论到 Issue → 再从更新后的步骤继续。严禁"边改边做、事后补计划"。
3. **验收只认计划**：Review 阶段只依据 `plan.md` 中的验收标准判定 PASS/FAIL，不接受"代码能跑就算过"。
4. **文档先行**：任何代码提交之前，对应的 spec / design / plan 必须已经存在且填充完整。

## 3. RIPER 状态机循环

### 3.0 前置自检（每轮循环开始前）

1. 执行 `./scripts/git-ops.sh doctor`：依次确认运行环境（macOS / Windows Git Bash）、remote 路由到的 CLI、CLI 已安装、CLI 已授权。
2. **全部通过** → 进入 [R] 研究阶段。
3. **CLI 缺失或未授权** → 立即中止，把脚本输出的安装/授权指南（或 `references/cli-setup.md` 对应章节）原样交给用户，说明需要完成的具体动作；用户确认完成后重跑 `doctor`，通过再从中断阶段继续。
4. 严禁绕行：不得改用 curl + REST API、不得猜测/代填 token、不得跳过 Issue 侧的读写步骤。

### 状态流转图

```
Issue(编号 N)
   │ PM: 设优先级 p0~p3
   ▼
[R] 研究 ──► [I] 创新 ──► [P] 计划 ──► [E] 执行 ──► [R] 审查
 riper-       riper-        riper-       riper-        riper-
 research     innovation    plan         execute       review
                 ▲                        │              │
                 │        计划有误        │   FAIL(QA 退回 riper-plan)
                 └────────────────────────┴──────┬───────┘
                                                  │ 重试 ≤ 3 次
                                         全部 PASS │
                                                  ▼
                              riper-verified → QA 关闭 Issue
                              （超限：riper-blocked，人工介入）
```

### 3.1 [R] 研究阶段（Research）— PM

1. **加载角色**：读取 `roles/planner.md`，切换为 PM。
2. `./scripts/git-ops.sh --role planner issue get <N>` 获取 Issue 详情（标题、正文、评论、标签）。
3. **判定并设置优先级**（艾森豪威尔矩阵）：`./scripts/git-ops.sh --role planner issue priority <N> <p0|p1|p2|p3>`。
4. 切换状态：`./scripts/git-ops.sh --role planner issue status <N> riper-research`。
5. 阅读正文与全部评论，**只读**拉取相关代码上下文（涉及文件、模块、依赖）。
6. 按 `templates/spec.md` 提炼规范：原始需求、上下文代码、核心约束、澄清假设。
   - **主路径**：spec 全文以评论写入 Issue → `./scripts/git-ops.sh --role planner issue comment <N> "<spec 全文>"`，不落盘本地；
   - **降级 fallback**（CLI 缺失 / 未授权 / 平台不支持 / API 失败 / 内容超限时）：写入 `docs/issues/<N>/spec.md`，并在 Issue 恢复后评论引用该文件路径。
7. 若需求存在无法用假设消解的歧义，在 Issue 下评论提问并暂停循环，等待用户回复。

### 3.2 [I] 创新阶段（Innovation）— PM

1. **保持 PM 角色**（若切换过会话，重新读取 `roles/planner.md`）。
2. 切换状态：`./scripts/git-ops.sh --role planner issue status <N> riper-innovation`。
3. 基于 spec 思考**至少两种**技术方案，按复杂度、风险、可测性、可维护性、与现有代码契合度对比，选定最终方案并说明理由。
4. design 全文评论写回 Issue（主路径，基于 `templates/design.md` 组织）；仅当远程 Issue 不可用时降级写入 `docs/issues/<N>/design.md`。
5. **全程只读代码，不得产出或修改任何实现代码（T0）。**

### 3.3 [P] 计划阶段（Plan）— PM

1. **保持 PM 角色**。
2. 切换状态：`./scripts/git-ops.sh --role planner issue status <N> riper-plan`。
3. 基于 design 拆解**极细粒度**原子任务：每步只做一件事，含编号、涉及文件、逻辑说明、验收标准、完成状态 `[ ]`。
4. **主路径不落盘**：plan 随下一步的合并评论写回 Issue；仅当远程 Issue 不可用时降级填充 `docs/issues/<N>/plan.md`（基于 `templates/plan.md`）。
5. 将 spec、design、plan 三份内容合并评论写回 Issue：
   `./scripts/git-ops.sh --role planner issue comment <N> "<三份文档合并内容>"`。
6. 计划写回 Issue 后即视为**冻结基线**；后续修改必须走"中断→回退→更新→再同步"流程，并登记在 plan 的"计划修订记录"中。

### 3.4 [E] 执行阶段（Execute）— 开发

1. **加载角色**：读取 `roles/developer.md`，切换为开发。
2. 切换状态：`./scripts/git-ops.sh --role developer issue status <N> riper-execute`。
3. 严格逐项执行计划：
   - 主路径（plan 在 Issue 评论中）：每完成一项（或按合理批次）将勾选进度评论同步到 Issue；
   - 降级模式（存在本地 `docs/issues/<N>/plan.md`）：每完成一项将 `[ ]` 改为 `[x]` 并落盘更新；
   - 遵守 SDD 原则：发现计划有误 → 中断 → 回退 Plan 阶段（PM 修订）→ 再继续；
   - 遭遇无法推进的阻塞 → `./scripts/git-ops.sh --role developer issue status <N> riper-blocked` 并评论说明。
4. 按仓库既有规范提交代码，提交信息引用 Issue 编号（如 `... (#N)`）。
5. 交付审查：`./scripts/git-ops.sh --role developer issue status <N> riper-review`。

### 3.5 [R] 审查阶段（Review）— QA

1. **加载角色**：读取 `roles/reviewer.md`，切换为 QA。
2. 对照计划（Issue 评论中的 plan，或降级产生的本地 `plan.md`）每一步的验收标准，**以黑盒方式**执行测试与代码审查（读代码属只读，禁止修改业务代码，T0）。
3. 如需编写测试脚本，默认生成到 `test/` 目录（用户显性指定时以用户为准）。
4. 按 `templates/verify-report.md` 生成 verify-report 全文并评论写回 Issue：逐项判定、证据、失败原因分析；
5. 仅当远程 Issue 不可用时降级写入 `docs/issues/<N>/verify-report.md`，恢复后在评论中引用。

### 3.6 状态判定（Loop Control）

- **全部 PASS**：
  1. `./scripts/git-ops.sh --role reviewer issue status <N> riper-verified`；
  2. 评论总结闭环结论；
  3. 由 QA 执行 `./scripts/git-ops.sh --role reviewer issue close <N>` 关闭 Issue（关闭权专属 QA），结束循环。
- **存在 FAIL**：
  1. 计入重试计数（**防死循环：最多重试 3 次**）；
  2. QA 退回计划：`./scripts/git-ops.sh --role reviewer issue status <N> riper-plan`，并评论失败分析；
  3. PM 修订计划（主路径在 Issue 评论中修订；降级模式下修订本地 `plan.md`）并同步评论；
  4. 重新走 [E] → [R]。
- **重试 3 次仍有 FAIL**：停止循环，`./scripts/git-ops.sh --role reviewer issue status <N> riper-blocked`，在 Issue 下评论说明卡点，等待人工介入。

## 4. 快速用法

```
/iloop                        → 无参数进入：先问目标 Issue / 执行范围 / 落盘确认，再跑 doctor 自检
"落地 issue #42"              → 先跑 doctor 自检，再从 [R] 研究阶段开始完整循环（先定优先级）
"推进迭代"                    → 扫描 open issue，按优先级 p0→p3 排序逐个进入循环
"验收 git issues"             → 对状态为 riper-review 的 issue 执行 [R] 审查阶段
"排 plan，不要执行"           → 只走 [R]→[I]→[P]，到计划写回为止
"检查环境 / cli 没装"          → 执行 doctor，输出安装与授权指南
```

## 5. 安装与注册（让 `/iloop` 生效）

本 Skill 以 GitHub 仓库分发。默认安装位置为 `~/.agents/skills/iloop`，目录名必须与 frontmatter 的 `name`（`iloop`）一致。面向 Agent 的安装入口、版本解析和安全切换协议见仓库根目录的 `INSTALL.md`；机器可读约束见 `skill-manifest.json`。

**用户只需说一句话**：

> 请从 `https://github.com/askdaddy/Git-Issue-Loop-Skill.git` 安装最新版 `iloop` 到 `~/.agents/skills/iloop`；若已有同源安装则安全更新，若目录非同源或存在本地修改则停止并报告；完成后验证 `SKILL.md`。

其中“最新版”由 Agent 解析为远端最高的稳定 `vX.Y.Z` 标签（忽略 `-alpha`、`-beta`、`-rc` 等预发布标签），而不是直接跟踪 `main`。实际安装完成后，Agent 必须报告解析到的 tag 和 commit SHA。

注册后刷新宿主会话，输入 `/iloop` 即可调用。进入具体项目执行闭环前，仍须在该项目仓库根目录运行 `./scripts/git-ops.sh doctor`。
