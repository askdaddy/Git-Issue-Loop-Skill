# Plan：执行计划（P 阶段产出）

> Issue: #1 | 阶段: [P] Plan | 状态标签: `riper-plan` | 优先级: `p0` | 状态: **冻结基线**
> 产出角色: PM（见 `roles/planner.md`）
> 输入: `docs/issues/1/design.md`（选定方案 A：脚本内聚增强 + Issue 即状态存储）

**角色分工约束（T0）**：步骤 1~16、20 的代码修改只能由**开发**执行；步骤 17~19 为文档改动，其中 `SKILL.md` / `roles/` / `references/` 属项目文档，由**开发**在本轮统一落盘（PM 已于 [R]/[I] 阶段完成 `docs/issues/1/` 下的 spec 与 design）。QA 只写 `test/`，禁改业务代码。

**SDD 铁律**：Execute 阶段必须严格逐条执行下述步骤，禁止跳过、禁止合并、禁止自由发挥。每完成一项将 `[ ]` 改为 `[x]`。发现计划有误必须中断执行、回退本阶段修订、再继续。

**状态流转**：开工 `riper-execute` → 交付 `riper-review` → 通过 `riper-verified` / 退回 `riper-plan` / 阻塞 `riper-blocked`。

**design 风险修正（取证后下调）**：design「边界情况 1」将 `riper-retry-*` 与 `riper-*` 前缀重叠列为最大实现风险。[P] 阶段已实测取证：现有 `is_status_label` 采用全名精确匹配（`for x in ${STATUS_LABELS}; do [[ "${x}" == "${l}" ]]`），`riper-retry-1` 不会被状态族误收，排他清理循环亦只遍历 `STATUS_LABELS`。风险等级由「中高」下调为「低」，但**仍保留步骤 20 的回归验证**以防实现走样。

---

## 原子任务清单

### A 组：基础设施

### 步骤 1：新增 `log_debug` 并完成输出降噪

- **编号**: 1
- **完成状态**: [x] ✅ 已验证：默认静默（status 切换仅 1 行输出、容错移除 0 行）；`GIT_OPS_VERBOSE=1` 还原 debug 细节；exit code 保持 0/1 不变
- **涉及文件**: `scripts/git-ops.sh`（`log_info` / `log_error` 附近、`raw_label_add` 419~439、`raw_label_remove` 442~473）
- **逻辑说明**: 在日志函数区新增 `log_debug()`，仅当环境变量 `GIT_OPS_VERBOSE=1` 时输出（否则丢弃）。将 `raw_label_remove` 三个平台分支中 `|| log_info "标签 'xxx' 已不存在或已移除。"` 改为 `|| log_debug ...`；将 `raw_label_add` 三平台分支的 CLI 标准输出重定向为 `>/dev/null`（裸 URL 不再刷屏）。**必须保留 `|| ` 的容错语义，不得改变任何 exit code。**
- **验收标准**:
  - `GIT_OPS_VERBOSE` 未设置时，`issue status <N> <状态>` 的输出**只有 1 行**结果汇总，无裸 URL、无「已不存在或已移除」
  - `GIT_OPS_VERBOSE=1` 时，上述细节日志重新出现
  - 标签操作成功与失败的 exit code 与改动前一致（成功 0 / 失败 1）

### 步骤 2：新增 `RETRY_LABELS` 常量与 `label_meta()` 元数据表

- **编号**: 2
- **完成状态**: [x] ✅ 已验证：14/14 标签全覆盖；`label_meta p0`→B60205、`riper-verified`→0E8A16；未知标签 exit=1
- **涉及文件**: `scripts/git-ops.sh`（第 274~278 行常量区之后）
- **逻辑说明**: 新增第四族常量 `RETRY_LABELS="riper-retry-1 riper-retry-2 riper-retry-3"`。新增函数 `label_meta <标签名>`，输出该标签的 `颜色 描述`（空格分隔，颜色为 6 位 hex 不带 `#`），覆盖 `p0~p3`（B60205/D93F0B/FBCA04/CCCCCC，描述为艾森豪威尔四象限释义）、7 个 `riper-*`（0052CC/5319E7/1D76DB/FEF2C0/F9D0C4/0E8A16/B60205）、3 个 `riper-retry-*`；未知标签返回非 0。颜色与描述取值须与本轮 bootstrap 已建标签一致。
- **验收标准**:
  - `label_meta p0` 输出以 `B60205` 开头；`label_meta riper-verified` 输出以 `0E8A16` 开头
  - `label_meta not-exist` 返回非 0 退出码
  - 全部 14 个标签（4+7+3）均有元数据，无遗漏

---

### B 组：`labels init`（P0 / E1）

### 步骤 3：新增 `raw_label_create()` 三平台幂等创建

- **编号**: 3
- **完成状态**: [x] ✅ 已验证：随步骤 4 实测——标签已存在走 updated 分支（11 个）、不存在走 created 分支（3 个 retry），均 exit 0；tea 分支已写明降级声明
- **涉及文件**: `scripts/git-ops.sh`（标签底层操作区，`raw_label_add` 之前）
- **逻辑说明**: 新增 `raw_label_create <名称> <颜色> <描述>`，按 `detect_platform` 路由：gh 用 `gh label create NAME --color HEX --description DESC`，失败（已存在）则回退 `gh label edit NAME --color HEX --description DESC`；glab 用 `glab label create NAME --color "#HEX" --description DESC`，失败回退 `glab label edit`；tea 用 `tea labels create NAME`（tea 不支持颜色/描述时仅创建，并 `log_debug` 声明降级）。须遵循 `local __plat; __plat="$(detect_platform)" || exit 1` 模式（C6）。
- **验收标准**:
  - 标签不存在时执行 → 远端新增该标签，exit 0
  - 标签已存在时**重复执行** → 不报错、不中断，exit 0（幂等，A3）
  - 三平台分支均存在且各自调用对应 CLI 的 label 子命令（可用 stub CLI 验证）

### 步骤 4：新增 `cmd_labels_init()` + 顶层路由 + usage

- **编号**: 4
- **完成状态**: [x] ✅ 已验证：`labels init`→「标签体系就绪：14/14」exit 0；重复执行仍 14/14（幂等）；`labels` 缺 init→exit 1；`--help` 含说明；`--role hacker`→exit 1、`--role reviewer`→exit 0；未带 --role 仅警告放行
- **涉及文件**: `scripts/git-ops.sh`（新增 `cmd_labels_init`；`main()` 顶层 `case` 增加 `labels)` 分支；`usage()` 文本）
- **逻辑说明**: `cmd_labels_init` 遍历 `PRIORITY_LABELS`、`STATUS_LABELS`、`RETRY_LABELS` 三族全部 14 个标签，对每个调用 `label_meta` 取颜色描述后调用 `raw_label_create`；逐个输出 `created/updated/skipped` 进度行；末尾汇总「标签体系就绪：14/14」。`main()` 增加顶层 `labels init` 路由（`labels` 后必须跟 `init`，否则 `usage`）。该命令**不限角色**（属仓库级配置），但需 `check_permission labels-init` 走一次角色合法性校验。usage 增加对应说明行。
- **验收标准**:
  - `./scripts/git-ops.sh labels init` 在标签已全存在的仓库上执行 → exit 0，汇总显示 14/14
  - `./scripts/git-ops.sh labels` （缺 `init`）→ 打印 usage 并 exit 1
  - `./scripts/git-ops.sh --help` 输出中含 `labels init` 说明
  - 未携带 `--role` 时可执行（仅提示跳过权限校验）

---

### C 组：`issue list`（P0 / E2）

### 步骤 5：新增 `raw_issue_list()` 三平台列表取数

- **编号**: 5
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`（`cmd_issue_get` 附近）
- **逻辑说明**: 新增 `raw_issue_list <state>`（state ∈ open/closed/all），输出**每行一个 Issue 的机读中间格式**：`编号<TAB>状态<TAB>标题<TAB>标签(逗号分隔)`。gh 用 `gh issue list --state STATE --json number,title,labels --jq '.[] | ...'`（gh 内置 jq，零外部依赖，C7）；glab 用 `glab issue list` 文本解析；tea 用 `tea issues --state STATE` 文本解析。glab/tea 若无法取得标签列，则该列输出空字符串并由上层标注 `(标签不可用)`（C2 显式降级）。
- **验收标准**:
  - 在本仓库执行能列出 Issue #1，且行内含 `p0` 与 `riper-plan` 标签
  - `--state closed` / `--state all` 分别只列已关闭 / 全部 Issue
  - 输出为 TAB 分隔的四列，无表头、无装饰色（便于上层排序）

### 步骤 6：新增 `cmd_issue_list()` 筛选与优先级排序

- **编号**: 6
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`
- **逻辑说明**: 新增 `cmd_issue_list [--state open|closed|all] [--status <riper-*>] [--priority <p0~p3>]`。实现：调用 `raw_issue_list` 取全量 → 按 `--status` / `--priority` 过滤（对标签列做精确匹配）→ 按优先级排序（为每行加 `0/1/2/3/4` 序号前缀，`p0→0`…`p3→3`，无优先级→4，`sort -n` 后去前缀，Bash 3.2 兼容）→ 以对齐表格输出 `编号 优先级 状态 标题`；无优先级的行在优先级列显式打印 `(无)`。参数非法（如 `--priority p9`）→ `log_error` + exit 1。
- **验收标准**:
  - 无任何筛选参数时列出全部 open Issue，且 `p0` 排在 `p1` 之前、无优先级者排在最后并标注 `(无)`
  - `--status riper-plan` 只返回状态标签为 `riper-plan` 的 Issue
  - `--priority p0` 只返回带 `p0` 的 Issue
  - `--priority p9` → 报错并 exit 1，错误信息列出合法值

### 步骤 7：`issue list` 路由 + 放宽 `issue` 分支守卫 + usage

- **编号**: 7
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`（`main()` 第 680~683 行守卫、`issue` 子命令 `case`、`usage()`）
- **逻辑说明**: 将 `issue` 分支的 `if [[ $# -lt 2 ]]; then usage; fi` 放宽为 `if [[ $# -lt 1 ]]; then usage; fi`（否则单参数的 `issue list` 被拦截 —— spec §2 已取证的实现约束）；在子命令 `case` 中新增 `list)` 分支，解析可选筛选参数后调用 `cmd_issue_list`。usage 增加 `issue list` 及其三个筛选参数说明。**放宽守卫后须确认其余子命令的参数个数校验不受影响**（各分支自身的 `[[ $# -eq N ]] || usage` 仍在）。
- **验收标准**:
  - `./scripts/git-ops.sh issue list` 正常执行（不再被守卫拦成 usage）
  - `./scripts/git-ops.sh issue`（无子命令）→ 仍打印 usage 并 exit 1
  - `./scripts/git-ops.sh issue get`（缺参数）→ 仍打印 usage 并 exit 1，证明守卫放宽未破坏既有校验
  - `--help` 输出含 `issue list` 说明

---

### D 组：重试计数持久化（P1 / E3）

### 步骤 8：新增 `is_retry_label()` 并扩展 `check_permission`

- **编号**: 8
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`（第 281~291 行判定函数区、第 309~364 行 `check_permission`）
- **逻辑说明**: 新增 `is_retry_label()`（结构同 `is_priority_label`，遍历 `RETRY_LABELS` 全名精确匹配）。`check_permission` 增加两个 action：`retry-incr`（仅 `reviewer` 放行，PM / 开发拒绝，理由「重试计数由 QA 在审查 FAIL 时登记」）、`retry-read`（三角色均放行）。同时在 `label-add|label-remove` 分支的互斥族判定中**追加 `is_retry_label`**，使 `issue label <N> add riper-retry-1` 被拒绝并提示改用 `issue retry`。
- **验收标准**:
  - `--role reviewer issue retry 1 incr` 通过权限校验
  - `--role planner issue retry 1 incr` → 权限拒绝，exit 1
  - `--role developer issue retry 1 incr` → 权限拒绝，exit 1
  - `--role planner issue retry 1 get` → 放行（只读不限角色）
  - `--role planner issue label 1 add riper-retry-1` → 被拒并提示改用 `issue retry`

### 步骤 9：新增 `cmd_issue_retry()` 排他实现

- **编号**: 9
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`
- **逻辑说明**: 新增 `cmd_issue_retry <N> <incr|get|reset>`。`get`：读当前 Issue 标签，命中 `riper-retry-K` 则输出数字 K，无则输出 `0`（供调用方判定是否超限）。`incr`：`check_permission retry-incr` → 取当前值 K → 若 K≥3 则 `log_error`「已达重试上限 3 次，应转 riper-blocked」并 exit 1 → 否则移除全部 `RETRY_LABELS` 再写入 `riper-retry-$((K+1))`（复用排他模式）。`reset`：移除全部 `RETRY_LABELS`（供新一轮闭环开始时清零），不限角色。取当前值须复用步骤 14 的 JSON 能力或独立的标签读取函数，**不得解析人类可读文本中的颜色/装饰**。
- **验收标准**:
  - 初始无 retry 标签时 `retry <N> get` 输出 `0`
  - 连续三次 `--role reviewer retry <N> incr` 后 `get` 输出 `3`，且 Issue 上**只有** `riper-retry-3` 一个 retry 标签（排他）
  - 第四次 `incr` → 报错提示转 `riper-blocked`，exit 1，标签仍为 `riper-retry-3`
  - `retry <N> reset` 后 `get` 输出 `0`
  - `incr` 操作不影响 `p0` 与 `riper-*` 状态标签（跨族无误删）

### 步骤 10：`issue retry` 路由 + usage

- **编号**: 10
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`（`main()` 的 `issue` 子命令 `case`、`usage()`）
- **逻辑说明**: 在 `issue` 子命令 `case` 中新增 `retry)` 分支，校验 `$# -eq 2` 且第二参数 ∈ `incr|get|reset`（否则 usage），调用 `cmd_issue_retry`。usage 增加 `issue retry <num> <incr|get|reset>` 说明行，并注明「incr 仅 QA 可用」。
- **验收标准**:
  - `issue retry 1`（缺动作）→ usage，exit 1
  - `issue retry 1 foo`（非法动作）→ usage，exit 1
  - `--help` 输出含 `issue retry` 说明与 QA 限定说明

---

### E 组：可写区域 `guard`（P1 / E4）

### 步骤 11：新增 `role_writable_paths()` 白名单

- **编号**: 11
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`（`status_allowed` 附近）
- **逻辑说明**: 新增 `role_writable_paths <role>`，输出该角色的可写路径前缀白名单（空格分隔），取值须与 T0 铁律 1 及 `roles/*.md` 表述同源：`planner` → `docs/`；`developer` → 全部路径**减去** `test/` 与 `docs/`（但放行 `docs/issues/*/plan.md`，因开发需勾选完成状态）；`reviewer` → `test/` 与 `docs/issues/*/verify-report.md`。非法角色 → `log_error` + exit 1。实现须避免 Bash 4+ 语法（C1）。
- **验收标准**:
  - `role_writable_paths planner` 输出含 `docs/`
  - `role_writable_paths reviewer` 输出含 `test/`
  - `role_writable_paths hacker` → 报错 exit 1
  - 三者的白名单互不相同，且与 `SKILL.md` §1 persona 表「可写区域」列一致

### 步骤 12：新增 `cmd_guard()` 越界检测

- **编号**: 12
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`
- **逻辑说明**: 新增 `cmd_guard <role>`。以 `git status --porcelain` 取全部变更文件（天然覆盖已暂存 + 未暂存 + 未跟踪），逐个比对 `role_writable_paths` 白名单：命中前缀或匹配通配（如 `docs/issues/*/plan.md`）→ 放行；否则计入越界清单。输出：合规时 `log_info "guard(<role>) 通过：N 个变更文件均在可写区域内"` 并 exit 0；越界时 `log_error` 逐行列出越界路径 + 该角色的可写区域说明，exit 1。无任何变更时 exit 0 并提示「无待检变更」。**排除 `.tmp/` 等 .gitignore 已忽略路径**（`git status --porcelain` 本身不列出被忽略文件，需确认不误报）。
- **验收标准**:
  - PM 角色下仅改 `docs/issues/1/spec.md` → `guard planner` exit 0
  - PM 角色下改动 `scripts/git-ops.sh` → `guard planner` exit 1 且输出中含该越界路径
  - QA 角色下新增 `test/foo.sh` → `guard reviewer` exit 0
  - QA 角色下改动 `scripts/git-ops.sh` → `guard reviewer` exit 1
  - 开发角色下改 `docs/issues/1/plan.md` → exit 0；改 `docs/issues/1/spec.md` → exit 1
  - 工作区干净时 → exit 0

### 步骤 13：`guard` 顶层路由 + `check_permission` 扩展 + usage

- **编号**: 13
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`（`main()` 顶层 `case`、`check_permission`、`usage()`）
- **逻辑说明**: `main()` 顶层 `case` 新增 `guard)` 分支：要求 `$# -eq 1`（角色名），调用 `cmd_guard`。`check_permission` 新增 action `guard`：三角色均放行（自检属合法动作），非法角色名拒绝。usage 增加 `guard <role>` 说明，并注明「提交前必跑」。
- **验收标准**:
  - `./scripts/git-ops.sh guard planner` 可执行
  - `./scripts/git-ops.sh guard`（缺角色）→ usage，exit 1
  - `./scripts/git-ops.sh guard foo` → 报错 exit 1
  - `--help` 输出含 `guard` 说明

---

### F 组：`issue get --json`（P1 / E5）

### 步骤 14：`cmd_issue_get` 增加 `--json` 主路径（gh）

- **编号**: 14
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`（`cmd_issue_get` 第 371~390 行、`main()` 的 `get)` 分支）
- **逻辑说明**: `cmd_issue_get <num> [--json]`。无 `--json` 时行为**完全不变**（保持 C8 零回归）。带 `--json` 时输出单行统一 schema：`{"schema":1,"_source":"<gh|glab|tea>","number":N,"title":"...","state":"OPEN|CLOSED","priority":"p0|null","status":"riper-*|null","retry":0,"labels":["..."]}`。gh 分支用 `gh issue view N --json number,title,state,labels --jq` 提取原始值（gh 内置 jq，满足 C7），再由脚本用 `printf` 组装；`priority` / `status` / `retry` 由脚本在标签数组中按三族常量匹配推导（无匹配输出 `null` / `0`）。标题中的双引号与反斜杠须转义。`main()` 的 `get)` 分支参数校验由 `$# -eq 1` 放宽为 `$# -eq 1 || $# -eq 2`，且第二参数只接受 `--json`。
- **验收标准**:
  - `issue get 1 --json` 输出**单行**合法 JSON，含 `schema`、`_source`、`priority`、`status`、`retry` 字段
  - 对 Issue #1 而言 `priority` 为 `"p0"`、`status` 为当前 `riper-*` 值、`_source` 为 `"gh"`
  - `issue get 1`（不带 --json）输出与改动前一致（人类可读含评论）
  - `issue get 1 --foo` → usage，exit 1
  - 无优先级标签的 Issue，`priority` 输出 `null` 而非报错

### 步骤 15：`--json` 的 glab / tea 降级实现 + usage

- **编号**: 15
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`（`cmd_issue_get` 的 glab / tea 分支、`usage()`）
- **逻辑说明**: glab 分支用 `glab issue view N` 文本解析标题/状态/标签（复用第 456~459 行 `sed` 提取 `Labels:` 行的既有先例）；tea 分支用 `tea issues N` 同理解析。任一字段解析不到时输出 `null`，并在 `_source` 中标明来源平台（C2 显式降级声明）；同时 `log_debug` 提示「该平台 JSON 字段由文本解析而来，可能不完整」。usage 补 `issue get <num> [--json]` 说明。
- **验收标准**:
  - 用 stub `glab` / `tea`（输出模拟文本）执行 `issue get 1 --json` → 仍输出合法 JSON，`_source` 分别为 `"glab"` / `"tea"`
  - stub 输出缺少标签行时 → `labels` 为 `[]`、`priority` 为 `null`，**不报错、不 exit 1**
  - `--help` 输出含 `--json` 说明

---

### G 组：doctor 与文档同步（E6）

### 步骤 16：`cmd_doctor` 追加标签体系就绪检查

- **编号**: 16
- **完成状态**: [ ]
- **涉及文件**: `scripts/git-ops.sh`（`cmd_doctor` 第 615~647 行）
- **逻辑说明**: 在授权检查之后追加第 5 步：用 `gh label list --limit 200` / `glab label list` / `tea labels` 取远端标签名集合，比对 `PRIORITY_LABELS` + `STATUS_LABELS` + `RETRY_LABELS` 共 14 个；全部存在 → `log_info "标签体系就绪：14/14"`；有缺失 → `log_error` 列出缺失清单 + 提示执行 `./scripts/git-ops.sh labels init` + **exit 1**（与 CLI 未授权同级，因缺标签必然导致闭环失败）。**网络不可达或 label list 命令失败时**，不得误报「标签缺失」，须 `log_error` 说明「无法获取远端标签（网络或权限问题）」并 exit 1。
- **验收标准**:
  - 在本仓库（已 bootstrap）执行 `doctor` → 输出含「标签体系就绪：14/14」，exit 0
  - 用 stub CLI 模拟仅返回默认 10 个标签 → doctor 列出 14 个缺失项、提示 `labels init`、exit 1
  - 用 stub CLI 模拟 `label list` 失败 → 提示网络/权限问题而非「标签缺失」，exit 1
  - 前四步（环境/路由/安装/授权）输出与改动前一致

### 步骤 17：`SKILL.md` 四处同步

- **编号**: 17
- **完成状态**: [ ]
- **涉及文件**: `SKILL.md`
- **逻辑说明**: (a) 新增 **§0.1「首次使用：标签体系初始化」**，说明克隆仓库后须先跑 `labels init`，并说明 `doctor` 会检查标签就绪；(b) T0 铁律追加一条：**提交前必须执行 `guard <当前角色>`，越界即 T0 事故**，并如实声明 guard 只能校验区域级越界、无法校验「是否超出 plan 范围」（design 边界 4）；(c) §1.2 标签体系由三族改为**四族**，补 `riper-retry-1/2/3` 说明（仅 QA 可 incr）；(d) §3.6 状态判定中的「计入重试计数」改为明确调用 `issue retry <N> incr` / `get`，「重试 3 次仍有 FAIL」改为「`retry get` 返回 3」；(e) §4 快速用法补 `labels init` / `issue list` / `guard` 三行；(f) §0「Git 操作」条目补上新增子命令清单。
- **验收标准**:
  - `SKILL.md` 含 §0.1 章节，且文中出现 `labels init` 命令示例
  - T0 铁律条目数由 8 增至 9，新增条目含 `guard` 与其能力边界声明
  - §1.2 出现「四族」与 `riper-retry-` 字样
  - §3.6 出现 `issue retry` 命令，且不再依赖 Agent 自行记忆计数
  - §4 快速用法含 `issue list`、`labels init`、`guard` 三条
  - 全文无「三族标签」等与实现矛盾的残留表述

### 步骤 18：`roles/*.md` 三文件补 guard 义务

- **编号**: 18
- **完成状态**: [ ]
- **涉及文件**: `roles/planner.md`、`roles/developer.md`、`roles/reviewer.md`
- **逻辑说明**: 三个文件各在「Issue 操作权限」小节后新增一条 `guard` 约定，内容与各自 T0 可写区域严格一致：PM 声明「提交/交付前跑 `guard planner`，可写区域仅 `docs/`」；开发声明「提交前跑 `guard developer`，禁写 `test/`、除 `docs/issues/<N>/plan.md` 外禁写 `docs/`」；QA 声明「交付验收报告前跑 `guard reviewer`，可写区域仅 `test/` 与 `docs/issues/<N>/verify-report.md`」。并在各自「必须做」清单中加入对应条目。表述须与步骤 11 的白名单**逐字对应**，避免文档与实现漂移。
- **验收标准**:
  - 三个文件均出现 `guard <角色>` 字样与对应可写区域清单
  - 三处声明的可写区域与 `role_writable_paths` 实际返回值一致
  - 三个文件均保留开头「用户可随时修改本文件」的提示（未被覆盖）

### 步骤 19：`references/cli-setup.md` 追加标签初始化章节

- **编号**: 19
- **完成状态**: [ ]
- **涉及文件**: `references/cli-setup.md`
- **逻辑说明**: 在 §0「一键自检」之后新增一节「标签体系初始化」，内容含：为何需要（priority/status 依赖标签存在，缺失即 `'p0' not found`）、命令 `./scripts/git-ops.sh labels init`、幂等说明、14 个标签清单（4 优先级 + 7 状态 + 3 重试）、doctor 会检查该项、以及各平台所需的最小权限（GitHub 需 `repo` scope 才能建标签）。
- **验收标准**:
  - 文档含「标签体系初始化」小节与 `labels init` 命令示例
  - 列出的 14 个标签名与 `PRIORITY_LABELS`/`STATUS_LABELS`/`RETRY_LABELS` 完全一致
  - 说明了缺失标签时的典型报错文案 `'p0' not found`

---

### H 组：自检与回归

### 步骤 20：语法检查、权限回归与新能力 stub 验证

- **编号**: 20
- **完成状态**: [ ]
- **涉及文件**: 无（纯验证，不改动交付物）
- **逻辑说明**: (a) `bash -n scripts/git-ops.sh` 语法检查；(b) 回归既有权限矩阵 10 条用例（developer close/reopen/priority 拒绝、planner status riper-execute 拒绝、reviewer priority 拒绝、label add 互斥族拒绝、以及 3 条放行路径），确认 exit code 与改动前一致；(c) 用 stub `gh` / `glab` / `tea` 验证新增命令的三平台路由（`labels init`、`issue list`、`issue get --json`）确实调用了对应 CLI 的子命令；(d) 验证 `riper-retry-*` 不被状态族排他清理误删（design 边界 1 的回归确认）；(e) 确认 macOS 自带 Bash 3.2 可运行（`/bin/bash --version` 为 3.2 时执行 `labels init` 与 `guard` 不报语法错）。
- **验收标准**:
  - `bash -n` 通过，无语法错误
  - 既有 10 条权限用例结果与改动前**逐条一致**（7 拒 3 放）
  - stub 验证显示三平台分别调用了 `gh label`/`glab label`/`tea labels`、`gh issue list`/`glab issue list`/`tea issues`、`gh issue view --json`/文本解析
  - `issue status <N> riper-execute` 执行后 `riper-retry-*` 标签仍存在
  - 以 Bash 3.2 执行新增命令无 `syntax error` / `declare: -A: invalid option`

---

## 提交策略

- **分 4 批提交**，每批完成后先跑步骤 20 的 (a)(b) 两项快速自检：
  1. 步骤 1~4（基础设施 + `labels init`）→ `feat: 标签体系初始化与输出降噪 (#1)`
  2. 步骤 5~10（`issue list` + 重试持久化）→ `feat: Issue 列表筛选排序与重试计数持久化 (#1)`
  3. 步骤 11~16（`guard` + `--json` + doctor）→ `feat: 可写区域 guard、结构化输出与 doctor 标签检查 (#1)`
  4. 步骤 17~20（文档同步 + 回归）→ `docs: SKILL/roles/references 同步四族标签与 guard 铁律 (#1)`
- **提交前检查（按批次区分门禁 —— 依修订 #1）**：
  - **批次 1、2**：`bash -n` 语法检查 + 既有权限矩阵回归（步骤 20 的 a、b 两项）+ **人工核对** `git status --porcelain` 变更清单，确认改动文件均落在计划「涉及文件」范围内。此阶段 `guard` 尚未实现：既不得因缺该命令而跳过提交，也不得为了自检而提前实现 `guard`（那会违反步骤顺序与「禁止自由发挥」）。
  - **批次 3、4**：`bash -n` + 权限矩阵回归 + **必须实际执行 `./scripts/git-ops.sh guard developer` 且 exit 0** 方可提交（步骤 13 交付后门禁恢复）。
- 提交信息一律引用 `(#1)`（SKILL.md §3.4 第 4 条）。

## 计划修订记录

| 修订 # | 原因 | 变更内容 | 时间 |
|--------|------|----------|------|
| 1 | **提交策略顺序缺陷**（开发在批次 1 提交前发现）：原策略要求「提交前检查：`bash -n` 语法、`guard <当前角色>` 越界自检」，但 `guard` 在步骤 11~13 才实现，导致批次 1、2 的提交门禁不可能满足。命中 `roles/developer.md`「计划有误（顺序不对、验收标准不可能满足）」，已立即中断执行并退回 [P] | 提交策略按批次区分门禁：批次 1、2 以 `bash -n` + 权限矩阵回归 + 人工核对 `git status --porcelain` 变更清单**替代** `guard`；批次 3、4 起 `guard` 已可用，恢复原门禁。步骤 1~16 的实现内容与验收标准**未作任何变更** | 2026-09-09 |

---
*本计划写回 Issue 后即冻结；任何修订必须走"中断→回退→更新→再同步"流程。*
