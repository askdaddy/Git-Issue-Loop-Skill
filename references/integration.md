# 集成、关闭与发布契约

## 默认交付

验收 PASS → QA `issue status N riper-verified` → QA 推分支并交付 PR → 回读写回 → QA `issue close N` → 释放认领。
`riper-verified` 表示验收通过，不表示已合并；关闭表示已交付 PR 或有已进入上游的证据，不必等待人工合并 PR。
已有 verified 但尚未交付的 open Issue，报告待集成，不直接关闭；自动挑选仍跳过这种异常态，用户可显式要求集成。

1. 在 `riper/N` 干净工作区检查验收对应 HEAD 未变；检查目标仓库 remote、默认分支、未混入别的 Issue 提交。
2. `./scripts/git-ops.sh --role reviewer integration push N`，只向 origin 的同名分支推送，无 force。
3. `integration pr-list N` 查同 base/head 的 open/closed PR（tea 需人工核对 head/base）。输出最多 100 条；若达到上限或无法完整确认，停止报告去重未完成，不能直接 create。已有 PR 用 `integration pr-view PR编号` 回读；同名已关闭未合并需交回用户，不能盲目重建。用户可在官方 CLI 的人工流程完成分页，Agent 不绕过包装器。
4. 无重复时用 `integration pr-create N "标题" 正文文件`（gh/glab/tea）。正文描述问题、行为及验证，引用 Issue，避免 `Closes/Fixes/Resolves #N`，由 QA 独立关闭。
5. 回读 PR URL、base/head、提交 SHA 和状态；若输出不充分或平台不可用停止，不假定创建失败或成功。若创建成功但写回失败，保留 PR URL 并先查询再恢复，避免重复。将证据评论回 Issue，随后 QA 关闭并释放认领。

PR 原语只负责单次平台操作；跨步骤去重、分页、SHA 回读、验收证据与关闭是 Agent 必须执行的协议，不宣称脚本自动认证了这些证据。PR 创建前脚本检查远端 head 等于本地已验收 HEAD；QA 必须核对该 HEAD 与报告一致，标签不是加密证明。
默认**不自动合并**。不因为授权 /iloop 就得到合并或发布授权；没有 merge PR 子命令。

## 权限矩阵

|动作|PM|开发|QA|额外要求|
|---|---|---|---|---|
|push / PR list/view/create|禁止|禁止|允许|显式 --role reviewer；只交付验收过的提交|
|本地 --no-ff 合并|禁止|允许|禁止|显式 --role developer；用户明确目标工作区及分支|
|GitHub Release view/create|禁止|禁止|允许|独立发布授权、全套件通过、固定版本/SHA|
|PR 合并|禁止自动执行|禁止自动执行|禁止自动执行|由用户处理|
|workspace finish|既有环境能力保留|既有环境能力保留|收尾负责|显式 --role reviewer；最新上游已合并且干净|

新的 integration 命令缺角色即拒绝，不继承旧命令的人工兼容放行。角色参数不等于独立身份认证。
QA 可以创建 PR、tag 和 Release 等元数据，不得编辑业务代码、CHANGELOG 或解决冲突；这些由开发按冻结计划处理。

## 离线与冲突

推送或 PR 未交付时保持 Issue open，写卡点；无法推进由有权限角色设 riper-blocked 并释放认领，恢复后重新核验和认领。不要把网络失败自动归因为权限不足。
本地降级不是自动失败兜底：先呈报目标独立工作区和非默认目标分支，经用户明确指定再由开发执行：
`./scripts/git-ops.sh --role developer integration local N TARGET`
调用者必须已在该独立 linked worktree 的 TARGET 上，不能在别人使用的工作区运行。命令不切分支；拒绝主工作树、默认分支、本 Issue 源分支、脏工作区或进行中的 merge。目标可由用户预先准备，Agent 不擅自切换共享 main。
仅本地合并不满足交付，**保持 open**。失败保留现场，列冲突路径；空路径可能是其他错误，不伪报冲突。停止并评论，设 blocked，不自动 abort、解冲或以 ours/theirs 选边，不执行 reset --hard/clean。

## 清理

PR 已交付不等于允许删除。`workspace finish N` 在 fetch 最新 origin 默认分支后，仍要求干净且源分支是该上游祖先，才移除 worktree 并安全删除分支。不删除远端分支。
离线/未合并/无法确定均保留。squash/rebase 合并不一定包含原分支祖先；脚本保守拒绝，人工复核，不能用 force 删除绕过。

## 稳定发布：tag 与 GitHub Release 缺一不可

发布单独征得用户对版本、SHA、目标仓库和操作的授权。普通交付不自动 bump、merge 或发布。
1. 开发按计划更新 CHANGELOG，QA 在候选 SHA 上运行全套 `test/*.sh`，记录每个结果。任一失败或未运行禁止打 tag；回归通过不证明已发布。
2. 核验 SHA 已进入 origin 默认分支、工作区干净；查本地及远端稳定 `vX.Y.Z` 均不存在。确认既有 tag 类型，本仓库为 lightweight，其他类型停止研究，不擅自切换格式。
3. 经授权 QA 用显式 Git tag/push 命令创建 lightweight tag 并只推该 tag（不 push --tags，不 force）；本地已有、远端已有、SHA 不同均不重用。这里 Git tag 是显式本地 Git 元数据动作；平台 Release 必须走包装器。与既有代码提交命令相同，不改动业务内容。
4. 确认远端 tag 指向候选 SHA 后，`./scripts/git-ops.sh --role reviewer integration release-create vX.Y.Z SHA`。仅 gh；其他平台不称为 GitHub Release。脚本要求远端 lightweight tag、默认分支与 HEAD 同 SHA，提取 CHANGELOG 的该版本正文，用 --verify-tag / --target 默认分支 / --title tag / --notes-file。默认非 draft、非 prerelease。
5. `integration release-view vX.Y.Z` 回读 URL、tag、draft/prerelease、正文和目标提交，原生页面的 targetCommitish 不能替代 tag SHA 验证。Release 必须与 CHANGELOG 版本段一致。缺任一部分不得报告发布完成。

全套件通过和发布授权是协议闸门，release-create 不会替用户认证这两件事。它不会创建或移动 tag，也不会修改现有 Release。
部分失败：tag 已创建但未推送、tag 已推送但 Release 未创建分别报告；不删 tag 回滚。恢复前检查 tag 的 SHA 和类型、Release 是否存在；只补缺失一步，不重建 tag、不覆盖 Release。创建报错可能是请求已成功但响应丢失，先 view 再决定；已有 Release 只回读核验。默认分支已经移动时，create 保守拒绝，须重新研究具体版本的安全恢复，不将旧 tag 指向新提交。
