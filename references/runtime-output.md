# 运行时输出与阶段摘要

本协议是 iloop 的可选观测层，服务于诊断与交接可读性。它不改变角色权限、远端写入语义或产品验收判定；Issue 仍是唯一事实来源，不建本地事件日志。判定与交接统一见 SKILL.md §2.1，反馈流程见 `references/feedback-loop.md`。

观测层分两部分：**脚本运行事件**（机器可读，opt-in）与**阶段摘要**（对话与 Issue 评论，人可读）。二者都是观测结果，不等于阶段完成或验收 PASS。

## A. 结构化运行事件（iloop.runtime.v1）

### 启用与通道

默认完全关闭。调用者需要同时做两件事：

```bash
exec 3>events.ndjson
ILOOP_EVENTS_FD=3 ./scripts/git-ops.sh --role developer issue status 42 riper-execute
```

- 只有 `ILOOP_EVENTS_FD=3` **且** 调用者预先打开 fd3 时才启用；其他值或未打开 fd3 时不产生任何事件，也不报错。
- 事件只写 fd3，每行一个 JSON 对象（NDJSON）。不写日志文件、不联网、不实现指标后端、不自动上报。
- 一个进程最多产生一条「完成事件」，在进程退出时写出；不做事务性追踪。
- 未指定的字段一律为 `unknown`，禁止猜测或从自由文本推断。

### 首版覆盖范围（冻结）

| `action` | 命令 | 说明 |
|---|---|---|
| `issue.priority` | `issue priority <N> <p0..p3>` | 参数合法、进入该命令路径即纳入 |
| `issue.status` | `issue status <N> <riper-*>` | 同上 |
| `issue.comment` | `issue comment <N> <body>` | 仅顶层命令；claim 等内部审计评论不额外产生事件 |
| `guard` | `guard <role> [N]` | 不发起远端写入 |

其他命令（`issue list/get/create/close/reopen/label/retry/claim`、`labels init`、`workspace *`、`platform`、`doctor`、`integration *`）首版**不覆盖**，不产生事件。未覆盖命令也不代表其行为不可观测，只是本契约不作机器可读承诺。事件同样不覆盖 Agent 的思考、工具选择或其他宿主行为。

### 包络字段

| 字段 | 类型 | 取值 |
|---|---|---|
| `schema` | string | 固定 `iloop.runtime.v1` |
| `run_id` | string | `r-` + 32 位小写十六进制；无法确认时 `unknown` |
| `event_id` | string | `e-` + 32 位小写十六进制；无法确认时 `unknown` |
| `time` | string | UTC `YYYY-MM-DDTHH:MM:SSZ`；无法确认时 `unknown` |
| `skill_tag` | string | 稳定 tag `vX.Y.Z`；非 git 安装或无法确认时 `unknown` |
| `skill_sha` | string | 40–64 位小写十六进制；无法确认时 `unknown` |
| `issue` | string | 正整数 Issue 编号；不适用或无法确认时 `unknown` |
| `role` | string | `planner` / `developer` / `reviewer`；未显式指定或非法时 `unknown` |
| `action` | string | 上表四个动作之一 |
| `result` | string | `success` / `denied` / `failed` / `partial` |
| `rule` | string | `ROLE-001` / `WORKSPACE-001` / `unknown` |
| `exit_code` | number | 进程原始退出码；无法确认时字符串 `"unknown"` |
| `duration_ms` | number | 秒级时钟折算（精度 1000ms）；无法确认时字符串 `"unknown"` |
| `checkpoint` | string | 固定枚举，见下 |
| `side_effects` | string | `none` / `unknown` / `label-cleanup-only` / `remote-write` |

`checkpoint` 固定取以下值之一：`requested`、`permission-denied`、`family-cleaned`、`family-cleanup-failed`、`add-failed`、`write-failed`、`branch-mismatch`、`violations`、`clean`、`completed`。

### result 语义

| `result` | 含义 |
|---|---|
| `success` | 受覆盖操作返回成功。**不表示**阶段完成、验收 PASS 或后续步骤已执行 |
| `denied` | 在任何远端写入前被角色权限拒绝（`ROLE-001`） |
| `failed` | 受覆盖操作失败；副作用见 `side_effects` |
| `partial` | 排他清理子步骤已完成，但目标标签写入未确认成功 |

### side_effects 语义

| 值 | 含义 |
|---|---|
| `none` | 未发生远端写入（权限拒绝、guard、只读路径） |
| `unknown` | 可能已发生远端写入，但当前证据不能确认；不得声称「没有写入」 |
| `label-cleanup-only` | priority/status 的同族清理子步骤已完成，目标标签添加失败 |
| `remote-write` | 受覆盖的远端写入调用返回成功 |

### run_id、event_id 与跨进程关联

- `run_id` 与 `event_id` 均来自 128-bit 随机值；`event_id` 在同一 run 内唯一，跨进程不做去重。
- 调用者显式传入 `ILOOP_RUN_ID` 可把多个进程关联到同一次运行；必须匹配 `r-[0-9a-f]{32}`。不合法的值输出 `unknown`，**不回显**原值，也不会被替换成新 ID。
- 未传入时每个进程各自生成 `run_id`；需要关联时由调用者显式传递，不依赖环境继承之外的自发机制。
- 恢复（resume）开启新的 `run_id`，并在阶段摘要中记录前序 `run_id`；不把恢复伪装成同一次运行。

### 失败隔离与脱敏

- 事件写入失败、fd3 关闭或读端断开都不改变原始 stdout、stderr 与退出码，不重放远端调用，不覆盖原始错误。
- 默认只输出固定枚举、校验后的数字与 ID、Skill tag/SHA。绝不采集命令参数正文、Issue 正文、日志、环境变量、凭据、源码、绝对路径、私有 URL 或完整对话。
- 未知角色保留 `role: unknown`（无法归因），不等于已确认违规。

### 已知限制

- 无事务语义：事件只描述「这次受覆盖调用返回了什么」，不保证多步操作的原子性。
- 秒级时钟：`duration_ms` 精度为 1000ms。
- 进程被 SIGKILL 或宿主强杀时，EXIT trap 不执行，可能没有完成事件。
- 不是审计日志，不能替代 Issue 评论、反馈流程或 QA 验收；不提供跨运行统计与看板。

## B. 阶段摘要

### 五类节点

| 节点 | 触发时机 | 主要去向 |
|---|---|---|
| `boot-dispatch` | 会话启动、doctor 之后、分发决定角色与阶段时 | 对话 |
| `stage-handoff` | 角色/阶段交接（研究→创新、计划→执行、执行→审查等） | 对话；已有业务 Issue 时按批次写回 |
| `pause` | 等待用户答复、环境/权限缺失、计划缺陷、QA FAIL、认领冲突 | 对话；必要时写回 Issue |
| `resume` | 从暂停、blocked 或重试中恢复 | 对话；写回时关联前序 `run_id` |
| `close` | 验收通过、交付完成、转 blocked 或本轮终止 | 对话；Issue 评论按闭环规则 |

摘要必须说明：当前阶段与角色、进入依据、已完成项、未完成项、下一步，以及等待原因（若有）。未到达的节点不得伪报完成。

### 证据分层

每一条结论都要标明来源：

- `[script-observed]`：来自本次运行事件或 `git-ops.sh` 明确输出（如标签、退出码、事件字段）。
- `[agent-declared]`：Agent 的判断或声明，尚未被脚本或测试证实。
- `[unverified]`：缺少环境、权限或证据，保持未知。

脚本操作成功只能记作 `[script-observed] success`，不得据此宣称阶段完成或产品验收 PASS；QA 的 PASS 只能来自独立验收。

摘要关联 `run_id` 与节点序号；恢复时同时记录前序 `run_id`。

### 写回规则

- 对话摘要：每次启动、交接、暂停、恢复、结束时都给出。
- Issue 评论：仅针对**已存在且已获授权**的业务 Issue，在关键节点或合理批次写回；不逐命令刷屏。
- 不写评论的场景：help、只读候选列表、Issue 尚未创建、目标未确认、只读审计。观测需求不额外建票。
- 去重标记：评论首行使用 `<!-- iloop-summary run_id=<run_id> node=<n> -->`。重试前先严格读取 Issue 确认该标记是否存在；写回后回读评论 URL/ID 作为成功依据。
- 写回失败或部分完成须如实报告，不盲目重试；不得声称已写回。
- 不复制 spec/design/plan 全文，不建本地双写；远程 Issue 不可用时沿用既有 fallback 与「缺 CLI/授权即停止」规则。
- 不引入本地事件日志、遥测后端、指标系统或自动修正标签/阶段的能力。

### 事件与摘要的关系

事件是脚本侧的机器事实；摘要是 Agent 侧的组织与解释。摘要可以引用事件的 `run_id`、`result`、`rule`、`checkpoint`，但不得把 `success` 扩写成「阶段已完成」，也不得把 `unknown` 补成确定结论。

## 示例

事件（单行 NDJSON，写入 fd3）：

```json
{"schema":"iloop.runtime.v1","run_id":"r-0123456789abcdef0123456789abcdef","event_id":"e-fedcba9876543210fedcba9876543210","time":"2026-10-22T06:00:00Z","skill_tag":"v0.6.11","skill_sha":"178b0fb61a4c253c861cdf90b446255a018641b7","issue":"42","role":"developer","action":"issue.status","result":"success","rule":"unknown","exit_code":0,"duration_ms":0,"checkpoint":"completed","side_effects":"remote-write"}
```

阶段摘要（Issue 评论）：

```markdown
# 阶段摘要

<!-- iloop-summary run_id=r-0123456789abcdef0123456789abcdef node=2 -->

- 节点: stage-handoff
- 当前阶段 / 角色: [E] 执行 → [R] 审查 / 开发 → QA
- 进入依据: [script-observed] 状态标签已切到 `riper-review`；[agent-declared] 计划步骤 1–2 已完成
- 已完成: 事件契约实现与文档；既有 19 组不变量测试通过
- 未完成: QA 黑盒验收尚未执行
- 下一步: QA 按冻结 plan 第 3 步验收
- 证据: 事件 run_id（见上）与提交 SHA
```