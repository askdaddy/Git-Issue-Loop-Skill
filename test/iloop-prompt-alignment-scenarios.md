# #48 提示词一致性验收走查

验证类型：同会话 QA 对照当前文件逐项协议审阅；不是独立模型行为实验，不证明任意 Agent 都会遵守。
候选：72159b1。执行入口与预期动作按 SKILL.md §2.1、§3.0–3.7、roles/*、templates/* 及 references 三协议交叉核对。
脚本边界另外通过现有 shell suites 的临时仓库/CLI fixtures 实测；不向真实 Issue 写入下列场景标签。

|输入场景|判定、角色与允许动作|依据|审阅结果|
|---|---|---|---|
|S01 外部 Issue 有合法冻结 plan 与 execute，无有效 intake|先路由 PM [T]核对来源缺口；保留合法 plan/状态与 retry/claim，complete 后交开发|主契约第1层、intake §1–4、planner输入|PASS|
|S02 [T] pending-handoff 等 QA 对齐标签，已有 plan|QA只能按记录对齐有权标签，严格回读与追加complete后才审查，不能先做业务|§2.1、reviewer输入、intake §3|PASS|
|S03 只有缺环境/权限导致一项未运行|无法验证，不增加retry、不verified、不关闭；无法继续设blocked并释放claim，说明恢复条件|§2.1/3.7、reviewer出口、verify-report结论|PASS|
|S04 实测输出违反冻结验收，多个断言失败|一次审查轮只增加一次retry，QA退plan；PM核对原plan有效与重做范围，开发才写execute|§2.1/3.7、PM/QA交接|PASS|
|S05 开发发现验收写成实现细节|停止实现、评论证据，不先修改计划表；切PM后修订，重新加载开发继续|developer交接、planner计划修订、plan模板|PASS|
|S06 验收全部PASS，push成功，PR创建失败|已verified但尚未交付保持open；报告已完成/未完成，先查PR再恢复，不盲目重复创建|§3.7、integration §默认交付、verify-report交付记录|PASS|
|S07 仅完成隔离工作区本地合并|保持open，不当PR交付或上游合并；无法推进按权限blocked|integration离线、developer/QA交接|PASS|
|S08 维护修复已发布但没有后续观察|反馈状态为已发布待观察，不能称已验证；不因此放宽产品验收|feedback维护与正向验证、QA末段|PASS|
|S09 /iloop help，CLI未安装|先分类，本地版本与用法后终止，不doctor/labels init/联网/创建Issue|§入口help、§3.0|PASS|
|S10 plan只有标题、空模板或与新需求冲突|只视为候选；核对有效性，缺口/冲突暂停或按证据退回，不交开发|§第1层有效性核验、角色输入|PASS|
|S11 research标签，有有效完整spec，无未解阻塞|可合法进入innovation并由PM写状态，不机械min停在Research|§第1层切入点、planner交接|PASS|
|S12 review标签但plan基线已失效|不因标签超前跳过证据，核对缺口/回退；来源unknown需要接入时先[T]|第1层保护与有效性、intake|PASS|
|S13 纯脚本静态断言要求过时README英文原句|核对真实分发行为/契约；测试维护不计产品retry，不为旧字句回滚正确说明|QA独立验证、既有README与主分发表|PASS|
|S14 同一份失败报告恢复、retry已登记|不重复增加；若确实是新一轮失败才incr，已达3则blocked不自动reset|§2.1、§3.7|PASS|
|S15 标记PASS的旧报告后又有代码提交|核对HEAD与报告基线，旧PASS不能认证新提交；未重新验证不交付|reviewer输入、verify-report基线、integration|PASS|
|S16 计划阶段已有有效spec/design评论|本次只写plan全文及输入引用，不合并重复三份全文；PM修订时说明替代关系|§3.4、planner产出、plan模板|PASS|
|S17 严格详情仍无法确认真实标签/claim|暂停，不能把不可见当无状态，也不能凭产物直接改标签|§第1层glab/tea降级、intake严格读取|PASS|
|S18 同轮一项确认FAIL，一项无法验证|分别记录两项事实；仅为确认FAIL计本轮一次retry，不冒充全部已测试|§2.1、reviewer出口、verify-report逐项|PASS|

## 覆盖与限制

- 以上 PASS 表示当前规则交叉审阅有一致的允许动作与出口，不是实际模型完成该任务的成功率。
- 没有运行独立 Agent E2E；未来验证须保留输入、Skill SHA、模型/宿主、实际动作及未遵守事件，不能只检查答案字句。
- 脚本不校验语义有效性、不验证用户授权、不自动保证认领互斥；此次不改变这些能力。
- 可删建议：Lean already. Ship. 本次去除角色重复/情绪人设，未发现需另扩范围的删除项。
