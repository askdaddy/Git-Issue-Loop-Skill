# #49 运行时输出与阶段摘要验收走查

验证类型：同会话 QA 对照当前文件逐项协议审阅，配合 `test/iloop-runtime-output-invariants.sh` 的 stub CLI 黑盒测试。**这是协议走查与 fixture 验证，不是独立 Agent E2E**；它不证明任意宿主/模型都会按摘要协议行动，也不向真实 Issue 写入下列场景标签。

候选基线：`ef55e91`（执行交接）上的 QA 测试新增提交。判定依据：Issue #49 冻结 plan 步骤 1–3、`references/runtime-output.md`、`templates/run-summary.md`、SKILL.md §2.1/§3.7/§3.9。

## 五类节点与等待原因

| 场景 | 输入 | 摘要应有的状态 / 依据 / 下一步 | 依据 | 审阅结果 |
|---|---|---|---|---|
| S01 `boot-dispatch` | 会话启动，doctor 通过，分发到 `[E]` | 当前阶段/角色、进入依据（标签+产物）、已完成/未完成；无 Issue 时不写评论 | SKILL §3.0.1、runtime-output 节点表 | PASS |
| S02 `stage-handoff` | 开发完成实现，切 `riper-review` | 记录有效 plan、HEAD SHA、已跑测试、未验证项、下一角色；按批次写回并回读评论 URL | SKILL §2.1/§3.5、模板 | PASS |
| S03 `pause`：等待用户 | 需求歧义无法用假设消解 | 明确等待原因与需要用户回答的问题；不伪造完成 | SKILL §3.2、runtime-output pause | PASS |
| S04 `pause`：环境失败 | 缺 CLI/授权或测试环境不可用 | 记录 `[unverified]` 与恢复条件；不增加 retry、不判 PASS | SKILL §2.1/§3.7 | PASS |
| S05 `pause`：计划缺陷 | 实现发现验收不可满足或写成 HOW | 停止实现，交 PM 修订；摘要不宣称原计划已满足 | roles/developer 停止条件、SKILL §3.4 | PASS |
| S06 `pause`：QA FAIL | 黑盒证据违反冻结验收 | 只登记一次本轮 retry，退 `riper-plan`；摘要区分确认失败与无法验证 | SKILL §3.7、§2.1 | PASS |
| S07 `pause`：认领冲突 | 目标 Issue 已被其他会话认领 | 不抢占，报告既有认领（会话/时间/worktree/分支）并停止 | SKILL §1.2(4)、§3.0.1 | PASS |
| S08 `resume` | 从暂停/blocked/重试恢复 | 开启新 `run_id`，摘要记录前序 run；先严格读取 Issue 去重，再继续 | runtime-output run_id、写回规则 | PASS |
| S09 `close` | 全部 PASS 或转 blocked | 说明验证证据、交付状态或卡点；未交付不得宣称关闭/发布完成 | SKILL §3.7、§2.1 | PASS |
| S10 写回失败/部分完成 | 评论写入失败或回读不一致 | 如实报告失败/部分完成，保留已做动作；重试前先查标记，不盲目重复评论 | runtime-output 写回规则 | PASS |

## 证据分层检查

| 检查项 | 期望 | 依据 | 结果 |
|---|---|---|---|
| 事件成功被写成阶段完成 | 不允许；`success` 只表示受覆盖调用返回成功 | runtime-output「result 语义」、SKILL §3.9 | PASS |
| 未知被补成确定结论 | 不允许；保持 `[unverified]` / `unknown` | runtime-output「证据分层」 | PASS |
| 摘要复制 spec/design/plan 全文 | 不允许；只引用 | SKILL §3.4/§3.9 | PASS |
| 无 Issue / help / 只读候选 | 不写 Issue 评论，只在对话反馈 | runtime-output 写回规则 | PASS |
| 去重标记与回读 | 写回前查 `<!-- iloop-summary run_id=... node=... -->`，写后核对 URL/ID | 模板、写回规则 | PASS |
| 观测影响原行为 | 不允许；stdout/stderr/exit 与远端调用不因事件改变 | runtime-output 失败隔离；shell 测试 step 2/4/7 | PASS |

## fixture 证据与真实运行证据

**fixture 证据（本走查 + `test/iloop-runtime-output-invariants.sh`）**

- stub `gh` / `glab` / `tea` 在黑盒下验证：默认零事件、四类 `result`、`unknown`/畸形 ID/脱敏、跨进程 `run_id`、关闭与失败 fd、foreign cwd、非 git Skill、单次写入不重放。
- 结论只适用于被 stub 的 CLI 契约与当前脚本实现，不代表真实平台网络/权限行为。

**真实运行证据（独立于 fixture）**

- Issue #49 开发交接评论：<https://github.com/askdaddy/Git-Issue-Loop-Skill/issues/49#issuecomment-6334214910>。
- QA 验收报告（本轮 verify-report）与最终 PR 交付链接另行回读记录。
- 真实运行只用于核对摘要字段与交接可读性，不替代 fixture 对事件契约的断言。

## 覆盖与限制

- 上面 PASS 表示当前规则与脚本行为交叉核对一致，不是实际模型完成该任务的统计成功率。
- 未运行独立 Agent E2E；未来验证须保留输入、Skill SHA、模型/宿主、实际动作与未遵守事件。
- 事件通道的覆盖范围固定为 `issue priority` / `issue status` / `issue comment` / `guard`；其他命令无事件承诺，不据此推断其行为。