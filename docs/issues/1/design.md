# Design：技术方案（I 阶段产出）

> Issue: #1 | 阶段: [I] Innovation | 状态标签: `riper-innovation` | 优先级: `p0`
> 产出角色: PM（见 `roles/planner.md`）——**全程只读代码，T0 禁止产出或修改任何实现代码**
> 输入: `docs/issues/1/spec.md`（含 C1~C8 约束与 A1~A6 假设）

## 0. 方案概览

要在**不引入外部依赖、不使用 Bash 4+ 语法**的前提下，为 `git-ops.sh` 补齐「发现（list）／前置保障（labels init + doctor）／状态持久化（retry）／约束强制（guard）／机读输出（--json）」五类能力。核心分歧在于**状态存哪里**：方案 A 以 Issue 标签为唯一状态载体，方案 B 引入本地状态文件。

---

## 方案 A：脚本内聚增强 + 「Issue 即状态存储」

### 实现思路

全部能力加进单文件 `scripts/git-ops.sh`（预计 739 → 约 1150 行），状态一律存在 Issue 标签上：

1. **`labels init`（顶层命令）**：遍历 `PRIORITY_LABELS` / `STATUS_LABELS` / 新增 `RETRY_LABELS` 三个常量，逐个「创建，失败则更新」，实现幂等。标签的颜色与描述集中定义在一个函数里，避免散落。
2. **`issue list`**：调用各 CLI 原生列表命令并附标签信息，本地按 `p0→p3` 排序（给每行加序号前缀 → `sort -n` → 去前缀，Bash 3.2 兼容）；无优先级的 Issue 排在末尾并显式标注 `(无优先级)`。支持 `--status <riper-*>` / `--priority <p0~p3>` / `--state open|closed|all` 筛选。
3. **重试计数 = 第四标签族**：新增排他族 `RETRY_LABELS="riper-retry-1 riper-retry-2 riper-retry-3"`，配 `issue retry <N> <incr|get|reset>` 子命令。`incr` 复用现成的「先清同族再写入」排他逻辑；`get` 输出当前次数（无标签则为 0）；达到 3 时由调用方转 `riper-blocked`。
4. **`guard <role>`（顶层命令）**：以 `git status --porcelain` 取全部变更文件，比对角色可写区域前缀白名单，越界则列出路径并 `exit 1`。
5. **`issue get --json`**：脚本用 `printf` 手工构造统一 schema，字段值来源分平台——gh 用其**内置** `--jq` 逐字段取（零外部依赖），glab / tea 走文本解析（复用第 456~459 行已有的 `sed` 提取先例）。输出含 `schema` 与 `_source` 字段以便消费方判断可信度。
6. **`doctor` 追加第 5 步**：用 `gh label list` / `glab label list` / `tea labels` 取远端标签，比对三族清单；缺失即 `log_error` + 提示 `labels init` + `exit 1`（与「CLI 未授权」同级，因为缺标签必然导致闭环失败）。
7. **输出降噪**：新增 `log_debug`（受 `GIT_OPS_VERBOSE=1` 控制），把 `raw_label_remove` 的「已不存在或已移除」与 `raw_label_add` 的裸 URL 全部降级为 debug，默认只保留一行结果汇总。

### 优点

- **零新增文件、零外部依赖**，满足 C1 / C7；不改变现有目录结构与安装方式。
- **状态跨机器 / 跨会话 / 跨 agent 可见**：换台机器、换个 agent（Codex / ZCode / Qoder）接手同一个 Issue，重试次数一目了然 —— 直接命中 spec「会话压缩或换窗口即丢失」的痛点。
- 与 SKILL.md §0「**唯一事实来源：Issue（正文 + 评论 + 标签）**」完全一致，不引入第二个事实来源。
- 高度复用现有机制：排他逻辑、`check_permission`、`detect_platform`、`require_cli` 全部原样复用，回归面小（利于 C8）。

### 缺点 / 风险

- 单文件膨胀至约 1150 行，可读性下降（可用分节注释缓解）。
- 标签总数 11 → 14，仓库标签列表变长；`riper-retry-*` 与 `riper-*` 状态族前缀重叠，`is_status_label` 必须精确匹配全名，否则 `riper-retry-1` 会被误判为状态族而被排他清理误删 —— **这是本方案最大的实现风险点**。
- 状态表达能力有限：只能存「重试到第几次」，存不了时间戳、阶段耗时等历史。

---

## 方案 B：脚本 + 本地状态目录

### 实现思路

前 2、4、5、6、7 项与方案 A 相同，**唯重试计数改为本地状态文件** `docs/issues/<N>/.loop-state`（`KEY=VALUE` 行式格式，规避 Bash 3.2 无关联数组、且无 `jq` 时解析 JSON 的脆弱性）：

```
RETRY_COUNT=2
LAST_STAGE=review
UPDATED_AT=2026-09-09T10:00:00Z
```

配 `issue retry <N> <incr|get|reset>` 读写该文件；`.gitignore` 需决定是否纳入版本控制。

### 优点

- 状态表达力强，可承载时间戳、阶段耗时、历史轨迹，为 P2 的 `resume` 断点续跑预留了天然载体。
- 不增加标签数量，仓库标签体系保持 11 个，干净。
- 读写不依赖网络，离线可用，速度快。

### 缺点 / 风险

- **制造了第二个事实来源**，与 SKILL.md §0 直接冲突：Issue 上看不出重试了几次，QA 在 Issue 里无法据此判定是否该转 `riper-blocked`。
- **跨机器 / 跨 agent 不可见**：若 `.loop-state` 不入版本控制，换机器即丢（正是 spec 要解决的痛点）；若入版本控制，则每轮重试都产生一次提交噪音，且并行处理多 Issue 时易冲突。
- 需要额外决策 `.gitignore` 策略，增加用户认知负担。
- 文件读写 + 格式解析引入新的失败模式（文件损坏、并发写、权限），且这些失败**无法在 Issue 上留痕**。

---

## 对比分析

| 维度 | 方案 A（Issue 标签存状态） | 方案 B（本地状态文件） |
|------|--------------------------|----------------------|
| 实现复杂度 | 低——复用现成排他逻辑，仅加一个标签族 | 中——需新增文件读写、格式解析、gitignore 策略 |
| 风险 | 中——`riper-retry-*` 与 `riper-*` 前缀重叠可能导致误删（可用精确匹配 + 测试覆盖消解） | 中高——第二事实来源与 Issue 状态不一致时，行为难以预测 |
| 可测性 | **高**——状态可直接在 Issue 页面肉眼验证，QA 黑盒可测 | 低——需读本地文件，且换机器即失效，黑盒验证困难 |
| 可维护性 | 中——单文件膨胀至约 1150 行 | 中——多出状态文件格式契约需长期维护 |
| 与现有代码契合度 | **高**——`cmd_issue_priority` / `cmd_issue_status` 的排他模式可 1:1 复用 | 低——引入全新的持久化范式，与现有代码无共通模式 |
| 满足 spec 约束 | C1~C8 全满足；与 §0「唯一事实来源」一致 | 违背 §0「唯一事实来源」；C2 降级行为更难声明 |
| 跨 agent 协作（用户核心诉求） | **✅ 天然支持** | ❌ 不支持 |

## 最终选定：**方案 A**

**选定理由**：

1. **用户的原始诉求是「多 agent（Codex / ZCode / Qoder）共用同一套 Issue 驱动闭环」**。状态存在 Issue 标签上，才能让任意 agent、任意机器接手时看到同一份事实；方案 B 的本地文件天然做不到这一点，属结构性出局。
2. **可测性直接决定 QA 能否黑盒验收**。方案 A 的状态在 Issue 页面肉眼可见，QA 无需读本地文件即可判定「重试是否超限」；这与 T0 铁律 4「QA 偏向黑盒测试」强相关。
3. **实现风险可控且有明确消解手段**：`riper-retry-*` 前缀重叠问题，通过让 `is_status_label` 严格全名匹配 + 在 `STATUS_LABELS` 排他循环中显式跳过 retry 族即可消解，并可被 QA 用一条测试直接覆盖。
4. 满足全部 C1~C8 约束，尤其 C7（无 `jq` / `python`）与 C8（零回归）。

**放弃方案 B 的理由**：制造第二个事实来源，与 SKILL.md §0 及用户的多 agent 协作诉求正面冲突；其唯一优势（状态表达力强）服务的是 P2 的 `resume`，而 `resume` 本轮明确不在范围内 —— 为尚未排期的需求承担当下的架构债务，不划算。若将来做 `resume`，可在方案 A 之上叠加本地缓存作为**加速层**（而非事实来源），届时不必推翻现有设计。

---

## 选定方案的技术要点

**关键文件 / 模块**：

| 文件 | 改动性质 |
|------|---------|
| `scripts/git-ops.sh` | 主体增强：新增 6 个函数 + 3 个顶层/子命令路由 + 降噪改造 |
| `SKILL.md` | 新增 §0.1「首次使用：标签体系初始化」；§3.6 重试计数改为调用 `issue retry`；§4 快速用法补 `list` / `labels init` |
| `roles/{planner,developer,reviewer}.md` | 各补一条 guard 调用义务与可写区域清单（与 `guard` 白名单保持同源表述） |
| `references/cli-setup.md` | 追加标签初始化章节，与 doctor 输出呼应 |

**关键接口 / 数据结构变更**：

- 新增常量 `RETRY_LABELS="riper-retry-1 riper-retry-2 riper-retry-3"`，与 `PRIORITY_LABELS` / `STATUS_LABELS` 并列为第四族（满足 C4：标签清单只在脚本常量中定义一次）。
- 新增命令：`labels init`（顶层）、`issue list [筛选]`、`issue retry <N> <incr|get|reset>`、`issue get <N> --json`、`guard <role>`（顶层）。
- `check_permission` 扩展 action：`retry`（仅 QA 可 `incr`，因为退回计数发生在审查 FAIL 时；PM / 开发可读不可增）、`guard`（三角色均可自检）、`labels-init`（不限角色，属仓库配置）。
- `main()` 中 `issue` 分支守卫由 `[[ $# -lt 2 ]]` 放宽为 `[[ $# -lt 1 ]]`，否则单参数的 `issue list` 会被拦截（spec §2 已取证的实现约束）。
- 统一 JSON schema：`{"schema":1,"_source":"gh","number":1,"title":"...","state":"OPEN","priority":"p0","status":"riper-research","retry":0,"labels":[...]}`。

**需要注意的边界情况**：

1. **前缀重叠**：`is_status_label "riper-retry-1"` 必须返回 false，否则 `issue status` 的排他清理会误删重试标签。这是最高优先级的回归测试点。
2. **`labels init` 幂等**：标签已存在时走「更新颜色与描述」分支，不得报错、不得中断（A3）。
3. **`list` 无优先级**：T0 铁律 5 要求所有 Issue 有优先级，但历史 Issue 可能漏设；`list` 必须把它们排在末尾并显式标注，而非丢弃或报错 —— 这本身就是有价值的合规巡检能力。
4. **`guard` 的能力边界**：只能校验**区域级**越界（`docs/` vs `test/` vs 业务代码），无法校验「开发是否只改了 plan 覆盖范围内的文件」——后者需解析 `plan.md` 的文件清单，过于脆弱，明确留作 P2，本轮不做，且在 SKILL.md 中如实声明该边界。
5. **`guard` 的基准**：需同时覆盖已暂存与未暂存改动（`git status --porcelain` 天然覆盖两者），并排除 `.tmp/`、`docs/issues/<N>/` 中本角色的合法产出。
6. **`--json` 的平台降级**：glab / tea 走文本解析，字段可能缺失；缺失字段输出 `null` 而非报错，并由 `_source` 字段告知消费方数据来源（C2 要求的显式降级声明）。
7. **降噪不得改变 exit code**：`raw_label_remove` 的容错分支仍需 `|| true` 语义，仅去掉日志输出（A5）。
8. **doctor 的离线场景**：标签检查需访问远端；网络不可达时应给出明确提示而非误报「标签缺失」。

---
*本方案是 plan.md 拆解的唯一依据，修改需同步评论到 Issue。*
