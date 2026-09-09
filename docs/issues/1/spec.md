# Spec：需求规范（R 阶段产出）

> Issue: #1 | 标题: 增强 git-ops.sh：标签初始化、Issue 列表、重试持久化、可写区域 guard、结构化输出
> 阶段: [R] Research | 状态标签: `riper-research` | 优先级: `p0`
> 产出角色: PM（见 `roles/planner.md`）
>
> **主路径已执行**：本 spec 全文以 Issue 评论形式写入；本文件为持久化副本（同时兼作 fallback）。

## 0. 优先级判定（艾森豪威尔矩阵，必填）

| 象限 | 标签 | 是否命中 |
|------|------|----------|
| 重要且紧急 | `p0` | ✅ **命中** |
| 重要不紧急 | `p1` | ❌ |
| 紧急不重要 | `p2` | ❌ |
| 不重要不紧急 | `p3` | ❌ |

**最终优先级**：`p0`（已用平台 label 设置，排他，未写进标题）

**判定理由**：

- **重要性**：两项 P0 缺失使本 Skill 在任何新仓库上**完全不可用**——实测 `issue priority` / `issue status` 因标签不存在返回 `'p0' not found`（`exit=1`），而「设优先级」与「切状态」是 RIPER 每一阶段的必经动作。三项 P1 缺失则使 T0 铁律（可写区域隔离）与防死循环机制（重试 ≤3 次）**形同虚设**，约束只存在于文档层。
- **紧急性**：本 Issue 自身即为 bootstrap 死锁的受害者——必须由用户一次性授权手工建标签，闭环才能启动。任何新用户克隆仓库后首次运行都会撞上同一堵墙，属「阻塞发布」级别。

## 1. 原始需求

用户在 Skill 全景评审后确认增强范围为 **P0 + P1 五项**，并要求以 `/iloop` 自举（dogfooding）方式跑完整 RIPER 闭环落地。Issue 正文范围表摘录：

| 级别 | 增强项 | 现状问题（证据） |
|---|---|---|
| P0 | `issue labels init`：幂等创建 `p0~p3` + `riper-*` 标签 | 远端仅有 GitHub 默认 10 个标签，`p0` / `riper-*` 均不存在 |
| P0 | `issue list`：按状态 / 优先级筛选并排序 | SKILL.md 第 25、220、221 行共 4 处依赖列表能力，脚本零实现 |
| P1 | 重试计数持久化 | §3.6「最多重试 3 次」仅存在于 Agent 上下文，会话压缩或换窗口即丢失 |
| P1 | 可写区域 `guard` | T0 铁律 1「PM / QA 禁改业务代码」代码层零强制 |
| P1 | `issue get --json` 结构化输出 | 现输出各平台人类可读文本，无法机器判定「是否已设优先级」 |

明确排除（P2 / P3）：`resume` 断点续跑、Git 侧 branch / commit / PR 封装、多 Issue 批量编排、回归测试套件、README、多宿主注册、glab / tea 实机验证。

### 1.1 补充信息（来自 Issue 评论与用户决策）

- **评论 1（PM，阻塞记录）**：实测确认标签缺失导致 priority / status 全部失败；澄清「退出码空值」系 zsh（`$pipestatus[1]`）与 bash（`${PIPESTATUS[0]}`）语法差异造成的**测试假象**，非脚本缺陷；附带发现排他清理会产生 7~10 行噪音日志，淹没真实错误。
- **用户决策 1**：授权一次性手工 bootstrap 建标签。已执行，远端标签数 10 → 21（新增 11）。
- **用户决策 2**：要求把「标签体系初始化」写进 SKILL.md，并纳入 `doctor` 自检项，从根上消除该类死锁。

## 2. 上下文代码（PM 只读，T0 禁改代码）

| 类型 | 位置 | 说明 |
|------|------|------|
| 执行层 | `scripts/git-ops.sh`（739 行 / 26 函数） | 待增强主体 |
| 编排层 | `SKILL.md`（241 行） | 第 25 / 220 / 221 行依赖未实现的 list 能力；需新增 §0.1 |
| 认知层 | `roles/{planner,developer,reviewer}.md` | guard 的「可写区域」定义来源（T0 铁律 1） |
| 参考层 | `references/cli-setup.md`（136 行） | doctor 指南输出格式的参照 |

**关键代码位置（只读取证）**：

| 行号 | 内容 | 与本轮的关系 |
|------|------|-------------|
| 56 | `set -euo pipefail` | 全局生效，新增代码须遵守；避免 `[[ ]] && cmd` 短路形式 |
| 276 / 278 | `PRIORITY_LABELS` / `STATUS_LABELS` | 标签清单**唯一权威定义**，`labels init` 必须复用而非另建常量 |
| 281~305 | `is_priority_label` / `is_status_label` / `status_allowed` | 新增子命令的校验可复用 |
| 309~364 | `check_permission` | 新增子命令须接入；`guard` 需扩展 action 类型 |
| 371~390 | `cmd_issue_get` | `--json` 改造点 |
| 419~473 | `raw_label_add` / `raw_label_remove` | 三平台差异封装点，`labels init` 应参照其容错风格 |
| 494~528 | `cmd_issue_priority` / `cmd_issue_status` | 排他实现；噪音日志源头（`raw_label_remove` 的 `\|\| log_info`） |
| 615~647 | `cmd_doctor` | 需追加「标签体系就绪」检查项 |
| 680~683 | `main()` 的 `issue` 分支守卫 `if [[ $# -lt 2 ]]` | **实现约束**：单参数的 `issue list` 会被拦截，必须同步放宽 |

### 2.1 现状与差距

`git-ops.sh` 当前把「平台差异」与「权限校验」封装得很完整，但能力面只覆盖**单个已知编号 Issue 的写操作**。缺口有三类：

1. **发现能力缺失**：无 `list`，Agent 无法回答「有哪些待办 Issue」「哪些处于 `riper-review`」，只能违规直接调 `gh issue list`，与 §0「禁止直接调用 gh / glab / tea」冲突。
2. **前置条件无保障**：标签体系是 priority / status 的隐含前置，却无任何命令创建它，doctor 也不检查——导致新仓库首次运行必然失败（本 Issue 已实测复现）。
3. **状态与约束不落地**：重试计数只活在 Agent 上下文；T0「PM / QA 禁改代码」无任何机器校验；`issue get` 输出不可机读，Agent 无法可靠判定「是否已设优先级」这条 T0 门禁。

## 3. 核心约束

- [ ] **C1**：仅支持 macOS + Windows(Git Bash)；**不得引入 Bash 4+ 语法**（如 `${var,,}`、关联数组 `declare -A`），macOS 自带 Bash 3.2 必须可运行。
- [ ] **C2**：gh / glab / tea 三平台能力对等；确实无法对等时须 fallback 并**显式声明降级行为**，禁止静默失败。
- [ ] **C3**：不得削弱既有 `--role` 权限硬校验；新增子命令必须接入 `check_permission`。
- [ ] **C4**：标签清单唯一权威来源为 `PRIORITY_LABELS` / `STATUS_LABELS`，禁止在脚本、SKILL.md、模板中多处硬编码具体标签名。
- [ ] **C5**：T0 铁律——PM / QA 禁改业务代码；本 Issue 的 [E] 阶段由 developer 角色执行。
- [ ] **C6**：遵守 `set -euo pipefail`；命令替换失败须显式 `|| exit 1`（历史 bug：`case "$(cmd)"` 会吞掉子 shell 内的 `exit`）。
- [ ] **C7**：不引入外部依赖（`jq` / `python` 等）；JSON 输出优先复用各 CLI 原生能力，必要时用 `printf` 手工构造。
- [ ] **C8**：既有 11 项子命令与权限矩阵**零回归**。

## 4. 澄清与假设

- **A1**：重试计数持久化载体——假设采用 **Issue 标签**（如 `riper-retry-1/2/3`）而非本地文件，理由：跨机器 / 跨会话可见，与「唯一事实来源是 Issue」一致。最终选型在 [I] 阶段对比后确定。
- **A2**：`guard` 的检查基准——假设以 `git status --porcelain` 与 `git diff --name-only`（含 `HEAD` 与工作区）的**并集**为待检查文件集，比对角色可写区域前缀白名单。
- **A3**：`labels init` 的幂等语义——假设「标签已存在则更新颜色与描述，不报错、不中断」。
- **A4**：`--json` 输出——假设复用 CLI 原生 JSON 能力（`gh --json`、`glab -F`、`tea --fields`），映射为统一 schema，至少含 `number / title / state / priority / status / labels`。
- **A5**：噪音日志——假设将「已不存在或已移除」降级为静默或单行汇总，**不得影响 exit code**。
- **A6**：本 Issue 的 bootstrap 手工建标签属用户显性授权的一次性例外，不视为对 C3 / §0 约定的破坏；`labels init` 交付后该例外不再需要。

## 5. 验收范围（初步）

- **E1** `issue labels init`：幂等创建 / 更新 11 个标签（`p0~p3` + 7 个 `riper-*`），三平台路由正确。
- **E2** `issue list`：支持按状态 / 优先级 / open 筛选，输出按 `p0→p3` 排序。
- **E3** 重试计数持久化：可读取、可递增、可重置，跨会话有效，且与 §3.6 的「≤3 次」门禁联动。
- **E4** `guard <role>`：越界文件 → `exit 1` 并列出越界路径；合规 → `exit 0`。
- **E5** `issue get --json`：统一 schema 输出，含可直接判定的 `priority` / `status` 字段。
- **E6** `doctor` 纳入标签就绪检查 + SKILL.md 新增 §0.1「首次使用：标签体系初始化」。
- **E7** 附带修复：排他清理的噪音日志降级。

---
*本规范是后续 design / plan 的唯一输入，修改需同步评论到 Issue。*
