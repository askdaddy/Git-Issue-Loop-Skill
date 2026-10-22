# 阶段摘要（Run Summary）

> 协议见 `references/runtime-output.md`。阈值：只在启动/分发、阶段交接、暂停、恢复、结束五类节点使用；已有业务 Issue 时按关键节点/合理批次写回评论，无 Issue、只读候选、help 或未确认目标不写。

<!-- iloop-summary run_id=<r-32hex|unknown> node=<1..n> -->

- **节点**: `boot-dispatch` | `stage-handoff` | `pause` | `resume` | `close`
- **当前阶段 / 角色**: <RIPER 阶段> / <PM | 开发 | QA>
- **进入依据**: <Issue 标签、有效产物、用户覆盖或证据，标明来源>
- **已完成**: <带 `[script-observed]` / `[agent-declared]` 标记>
- **未完成**: <带 `[unverified]` 标记>
- **下一步**: <动作与负责角色>
- **等待原因**: <等待用户 / 环境缺失 / 计划缺陷 / QA FAIL / 认领冲突；无事写「无」>
- **前序 run**: <resume 时填写上一 run_id，否则「无」>
- **证据**: <事件 run_id、退出码、提交 SHA、Issue/PR 链接或「unknown」>

> 脚本 `success` 只表示受覆盖操作返回成功，不表示阶段完成或验收 PASS。未知保持 unknown；写回前先去重，写回后核对评论 URL/ID。不要在本摘要中复制 spec/design/plan 全文。