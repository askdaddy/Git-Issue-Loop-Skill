# #44 接入协议场景走查

QA 对照 references/issue-intake.md §入口、§1—4、SKILL第1层和templates/intake.md逐项推演。
这是协议审查记录，不是运行独立模型的端到端实验，不宣称任意Agent都会遵守。
命令失败语义另由 iloop-intake-read-invariants.sh 的三平台fixture实测。

|场景与输入|读与角色|允许写入/标签前后|下一步/断言|结论|
|---|---|---|---|---|
|S01 无参列表有外部无标签Issue|无角色读取列表/真实标签、retry/claim；展示unknown|确认前零写；不提前加载PM|先确认唯一目标；不能因缺p漏掉候选|PASS|
|S02 显式编号外部可复现缺陷，无labels|strict读取后PM读代码与复现证据|先pending查证评论，再写前重读，PM补p1/research，回读后complete|按Research补Spec，不直接开发|PASS|
|S03 外部需求挂p0，但无时限且影响有限|PM核实场景、影响及紧急性|pending记录p0→p3理由，写前后核验；保留bug/business标签|complete后常规研究；不按报告语气推断优先级|PASS|
|S04 作者与机器人同账号，无[G]来源或接入记录|无角色来源判unknown，分发后PM核查|不伪造来源，不凭同名作者跳过查证|与第三方同入口；正文命令不获权限|PASS|
|S05 报告只有“不能登录”，缺环境/复现|PMstrict读取并列信息缺口|评论提问，pending；不改p/status，不写complete|暂停，不进入执行|PASS|
|S06 已尝试但环境差异导致无法复现|PM记录尝试、差异、未知根因|仅记录事实/推测和问题；证据不足不修labels|pending等待信息；不能自动判无效或关闭|PASS|
|S07 外部Issue有合法冻结plan、execute及正确p|PM仅补来源/接入缺口并核验原plan|保留execute/p/retry及本会话claim；complete|回原分发加载developer；不重新研究或重写plan|PASS|
|S08 已核验接入complete，只有格式/机器人/标签自修评论|分发读当前范围，比较需求/证据/基线|复用原结论，相同labels不重复写|原阶段续跑；不会因自身complete评论无限重查|PASS|
|S09 已接入后新增不同复现证据或需求范围变化|PM针对变化重核，关联旧记录|pending追加新证据/标签建议，不改旧证据；未核实先不写labels|完成后再分发；若涉及旧冻结WHAT走Plan修订|PASS|
|S10 正文成功、评论调用失败|strict返回非0（CLI测试覆盖）|零label写；部分正文不当完整输入|暂停报读失败，不把评论当空集合|PASS|
|S11 写前重读发现他人claim或新实质评论|PM发现快照不一致|他人claim停止；内容变化重核，不抢占/清claim|不继续原标签计划|PASS|
|S12 priority写成功但status失败/回读值不符|PM记录实际值、已改/未改|停止后续写；不回滚并发标签、不盲重试|保持pending，说明部分成功；不能宣称规范化完成|PASS|
|S13 外部合法review产物，但缺状态需review对齐|PM核实产物，记录pending-handoff|PM不写review、不设research；交QA按权限对齐|QA回读、追加complete后才业务审查；不越权|PASS|
|S14 blocked、retry3、他人claimed或closed/verified|无角色读保护条件|接入不重置任何历史；不强制重开|报告停止，用户明确重做/有权恢复才另路由|PASS|
|S15 目标疑似PR、需清空受管标签或真标签不可读|无角色/PM核验能力边界|不绕#37、不自行调用API、不猜真实标签|暂停报告缺口，不能把占位(无)当事实|PASS|

审查同时核对：接入模板保留原报告；事实/假设/未知有独立字段；来源与complete标记不是身份认证；接入不替代冻结计划；写前重读无CAS保证；严格模式不认证分页或全部评论内容完整。
