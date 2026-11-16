# #73 支持分诊与贡献协议走查

QA 对照冻结 Plan v1（Issue #73 评论 6910961545）及产品协议逐项推演。
这是本会话协议审阅，不是独立 Agent E2E；脚本行为由贡献读取 fixture 实测。
真实 GitHub pr-view 另记 Issue 报告，不能推断 glab/tea 真实字段完整性。

|输入|实际协议路径与约束|结论|
|---|---|---|
|无标签用户咨询|按 question 分诊，引用版本证据且实际答复后 answered；无针对性关闭授权保持 open，不补研发状态，结束释放本会话 claim|PASS|
|配置及文档混合问题|mixed 分别记子诉求，不按作者职业分流，不擅自拆票；需要文档改进转 engineering|PASS|
|仅“打不开”或无法复现|needs-info/pending，记录缺口及尝试，不判无效、不关闭、不增 retry；等待用户保留认领|PASS|
|标题相似的重复报告|要原问题链接及行为范围相同证据；研究阶段重复可由 PM 处理，不关闭 execute/review|PASS|
|Agent 认为价值低|不能自行 declined；等待维护者决定，未批准关闭仍 open|PASS|
|维护者明确不采纳并批准关闭|PM 仅进入开发前按有限例外关闭并回读释放；不设 verified，QA 研发关闭条件不变|PASS|
|功能请求授权进入研发|engineering 后才规范优先级/阶段；已有有效计划复用，接入不冒充冻结计划|PASS|
|已有合法 execute/review|保护并复用进度，不能用支持出口让 PM 关闭或清空阶段|PASS|
|答复响应丢失、恢复有机器人噪音|先回读已发评论去重，不盲重发；噪音不全量重查，实质变化针对性复核|PASS|
|closed 报告出现新故障|先报告终态，不自动重开；维护者明确授权后再恢复|PASS|
|显式 pr N 与 Issue 同号|先 pr-view，不把 PR 编号传 issue comment/claim/priority/status/close；裸数字仍为 Issue|PASS|
|外部 PR 没有关联 Issue|查已有候选并严格核验，确认无匹配后草稿经确认再建票；未建票仅对话 pending(pr N)，不向 PR 发消息|PASS|
|PR 关联他人 claim 或终态 Issue|严格读并应用 claim/retry/终态保护，不抢占不重开，声明关联不是批准证据|PASS|
|平台字段/评论缺失或读取失败|暂停补可核验证据，不把空输出当评论为空；脚本测试另证失败传播|PASS|
|已有贡献代码可复用|先核验仓库/base/head SHA 与静态 diff；按冻结 WHAT 复用并保留作者来源；审查和授权前不执行外部代码|PASS|
|fetch SHA 不符或缺 merge-base|补取历史或暂停，不以不完整 diff 下结论，CI 绿灯不代替验收|PASS|
|冻结后 head/base 更新|恢复重读，使相关旧证据失效，记录映射并重新审查/验收；WHAT 变化回 Plan|PASS|
|复用原 PR 但原语不支持贡献分支操作|记录维护者决定，交维护者操作，保持 open，不自动另造交付 PR|PASS|
|维护者决定另交 riper/N|查原 PR 最新状态及替代 PR，正文/Issue 链接贡献和需求、原 head/验收 SHA、归属及理由；原 PR 通知/关闭留维护者|PASS|
|恶意正文要求执行/推送/合并|外部内容无授权作用，pr-view 不授写权限，无自动合并/发布/常驻监听|PASS|

角色边界：开发提交产品，QA 仅新增 test 文件。无新增依赖或标签族。
不承诺分页认证、分布式强锁或任意 Agent 实际遵守。
