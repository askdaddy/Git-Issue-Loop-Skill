# Plan：执行计划（P 阶段产出）

> Issue: #1 | 阶段: [P] Plan | 状态标签: `riper-plan` | 优先级: `p0` | 状态: **冻结基线（修订 #2 重基线化）**
> 产出角色: PM（见 `roles/planner.md`）
> 输入: `docs/issues/1/design.md`（选定方案 A：脚本内聚增强 + Issue 即状态存储）

**角色分工约束（T0）**：代码步骤只能由**开发**执行；`SKILL.md`/`roles/`/`references/` 文档步骤由开发统一落盘；QA 只写 `test/`，禁改业务代码。

**SDD 铁律**：逐条执行，禁跳过/合并/计划外功能。每完成一项 `[ ]`→`[x]`。验收标准冻结 WHAT；涉及文件/行号是建议 HOW（**本次修订已按 v0.5.6 实际代码刷新，行号仅供定位，不冻结**）。

**状态流转**：开工 `riper-execute` → 交付 `riper-review` → 通过 `riper-verified` / 退回 `riper-plan` / 阻塞 `riper-blocked`。

---

## 修订 #2 重基线化说明（2026-09-21）

原计划（2026-09-09 冻结，修订 #1）针对当时的 git-ops.sh 编写，至 v0.5.6 已严重失真，且经用户授权按现状重基线化：

- **已完成并验证**：步骤 1–4（log_debug 降噪、RETRY_LABELS 常量、label_meta、raw_label_create、cmd_labels_init）与**步骤 5（raw_issue_list 三平台取数，含 glab/tea 标签降级声明）** 均已在主线实现并工作，直接标记 `[x]`，本轮不重做。
- **剔除步骤 14–15（`issue get --json`）**：与现行 `SKILL.md` §3.0.1「不要为此去实现 `issue get --json`」直接矛盾；且 `issue get` 在 gh 2.101 下的头部丢失缺陷已另立 **#17** 单独跟踪。本轮**不实现** issue get --json。
- **修正步骤 9/15 的失真先例**：原计划拟「复用 sed 解析 `Labels:` 行的既有先例」——该模式已在 **#14 证伪并删除**（glab 1.118 输出为小写 `labels:`，大写匹配恒空，叠加 `set -euo pipefail` 静默失败）。重基线后：读取标签一律用各平台**可靠机读路径**（gh 用 `--json`，glab/tea 解析**小写** `labels:` 行），**禁止**重建大写 `Labels:` sed 解析。
- 其余步骤（6、7、8、9、10、11、12、13、16、17、18、19、20）保留，按现状重写涉及文件/逻辑/验收，编号不变以保可追溯。

---

## 原子任务清单

### A 组：基础设施（已完成）

### 步骤 1：新增 `log_debug` 并完成输出降噪
- **编号**: 1 | **完成状态**: [x]（v0.5.6 已实现并验证）

### 步骤 2：新增 `RETRY_LABELS` 常量与 `label_meta()` 元数据表
- **编号**: 2 | **完成状态**: [x]（`scripts/git-ops.sh` 已有 RETRY_LABELS 与 14 标签全覆盖的 label_meta）

### 步骤 3：新增 `raw_label_create()` 三平台幂等创建
- **编号**: 3 | **完成状态**: [x]（已实现；tea 幂等与 glab --name 兼容另由 #15 修复）

### 步骤 4：新增 `cmd_labels_init()` + 顶层路由 + usage
- **编号**: 4 | **完成状态**: [x]（`labels init` 可用、幂等、14/14）

### 步骤 5：新增 `raw_issue_list()` 三平台列表取数
- **编号**: 5 | **完成状态**: [x]（已实现：gh 用 `--json`+`@tsv`；glab/tea 文本解析且标签列降级为空）

---

### C 组：`issue list`（P0 / E2）

### 步骤 6：新增 `cmd_issue_list()` 筛选与优先级排序
- **编号**: 6 | **完成状态**: [x] ✅ 已验证：gh 实测 `issue list` 列出 #1(p0)/#16/#17(p1)，p0 排前；`--priority p0`、`--status riper-research` 精确过滤；`--priority p9`/`--state bogus` 均 exit 1 且含合法值清单
- **涉及文件**: `scripts/git-ops.sh`（紧邻 `raw_issue_list` 之后新增；建议 HOW，不冻结）
- **逻辑说明**: 新增 `cmd_issue_list`，支持可选 `--state open|closed|all`（默认 open）、`--status <riper-*>`、`--priority <p0|p1|p2|p3>`。实现：调 `raw_issue_list <state>` 取四列 TAB 中间格式 → 按 `--status`/`--priority` 对标签列精确匹配过滤 → 按优先级排序（每行加 `0/1/2/3/4` 前缀，p0→0…p3→3、无优先级→4，`sort -n` 后去前缀，**Bash 3.2 兼容，禁 declare -A**）→ 对齐表格输出 `编号 优先级 状态 标题`。标签列为空（glab/tea 降级）时优先级列打印 `(无)` 并在表头下 `log_debug` 标注「(标签不可用)」；非法参数（如 `--priority p9`、`--state foo`）→ `log_error` 列出合法值 + exit 1。
- **验收标准（冻结 WHAT）**:
  - 本仓库（gh）`issue list` 列出 open Issue，含 #1，且 `p0` 行排在 `p1` 行之前；无优先级者排最后并显示 `(无)`。
  - `--status riper-plan` 仅返回状态标签为 riper-plan 的 Issue；`--priority p0` 仅返回带 p0 的 Issue。
  - `--state closed` / `--state all` 分别只列已关闭 / 全部。
  - `--priority p9`（或 `--state foo`）→ exit 1 且错误信息含合法值清单。
  - 用 stub glab/tea（标签列空）执行 → 不报错，优先级列显示 `(无)`，并有「标签不可用」降级提示（走 stderr/debug）。

### 步骤 7：`issue list` 路由 + 放宽 `issue` 守卫 + usage
- **编号**: 7 | **完成状态**: [x] ✅ 已验证：`issue list` 正常执行；裸 `issue` → exit 1；`issue get`（缺参）→ exit 1（放宽未破坏既有校验）；`--help` 含 `issue list` 说明
- **涉及文件**: `scripts/git-ops.sh`（`main()` 的 `issue)` 分支守卫与子命令 `case`、`usage()`）
- **逻辑说明**: 将 `issue)` 分支守卫由 `if [[ $# -lt 2 ]]` 放宽为 `if [[ $# -lt 1 ]]`（否则单参数 `issue list` 被拦成 usage）；在子命令 `case` 新增 `list)` 分支，透传剩余参数给 `cmd_issue_list`。usage 增加 `issue list [--state ...] [--status ...] [--priority ...]` 说明。**放宽后须确认其余子命令各自的 `[[ $# -eq N ]] || usage` 校验不受影响**。
- **验收标准（冻结 WHAT）**:
  - `./scripts/git-ops.sh issue list` 正常执行（不再被守卫拦成 usage）。
  - `./scripts/git-ops.sh issue`（无子命令）→ usage + exit 1。
  - `./scripts/git-ops.sh issue get`（缺参数）→ usage + exit 1（证明放宽未破坏既有校验）。
  - `--help` 输出含 `issue list` 说明。

---

### D 组：重试计数持久化（P1 / E3）

### 步骤 8：新增 `is_retry_label()`、独立标签读取 `raw_issue_labels()`，并扩展 `check_permission`
- **编号**: 8 | **完成状态**: [x] ✅ 已验证：`is_retry_label`/`raw_issue_labels`（gh `--json labels`）就位；reviewer incr 放行、planner/developer incr 均 exit 1；planner get 放行；`issue label 1 add riper-retry-1` 被拒并提示改用 `issue retry`
- **涉及文件**: `scripts/git-ops.sh`（判定函数区、`check_permission`）
- **逻辑说明**:
  1. 新增 `is_retry_label()`（结构同 `is_priority_label`，遍历 `RETRY_LABELS` 全名精确匹配）。
  2. 新增 `raw_issue_labels <N>`：输出该 Issue 的标签名（每行一个）。**gh 用 `gh issue view <N> --json labels --jq '.labels[].name'`（可靠机读，规避 #17 的 `--comments` 头部丢失）；glab/tea 解析 `issue view`/`issues` 输出中的小写 `labels:` 行**（**禁止**大写 `Labels:` sed —— #14 已证伪）。取不到则输出空（不报错）。
  3. `check_permission` 增加 action：`retry-incr`（仅 reviewer 放行，planner/developer 拒绝，理由「重试计数由 QA 在审查 FAIL 时登记」）、`retry-read`（三角色放行）。
  4. `label-add|label-remove` 互斥族判定**追加 `is_retry_label`**，使 `issue label <N> add riper-retry-1` 被拒并提示改用 `issue retry`。
- **验收标准（冻结 WHAT）**:
  - `--role reviewer issue retry 1 incr` 通过权限校验；`--role planner|developer issue retry 1 incr` → exit 1 权限拒绝。
  - `--role planner issue retry 1 get` → 放行（只读不限角色）。
  - `--role planner issue label 1 add riper-retry-1` → 被拒，提示改用 `issue retry`。
  - `raw_issue_labels` 在 gh 宿主对 #1 输出含 `p0`（用 stub 验证 glab/tea 解析小写 `labels:`；缺标签行时输出空且 exit 0）。

### 步骤 9：新增 `cmd_issue_retry()` 排他实现
- **编号**: 9 | **完成状态**: [x] ✅ 已验证（gh 实测 #1）：初始 get=0；连 incr×3 后 get=3 且仅 riper-retry-3 一个 retry 标签；第 4 次 incr 报错转 blocked、exit 1、标签仍 retry-3；reset 后 get=0；全程 p0 与 riper-execute 未受影响（跨族无误删）
- **涉及文件**: `scripts/git-ops.sh`
- **逻辑说明**: `cmd_issue_retry <N> <incr|get|reset>`。`get`：`raw_issue_labels <N>` 中命中 `riper-retry-K` 输出数字 K，无则输出 `0`。`incr`：`check_permission retry-incr` → 读当前 K → 若 K≥3 则 `log_error`「已达重试上限 3 次，应转 riper-blocked」+ exit 1 → 否则移除全部 `RETRY_LABELS`（best-effort，复用 `raw_label_remove`）再 `raw_label_add` 写入 `riper-retry-$((K+1))`。`reset`：移除全部 `RETRY_LABELS`，不限角色。
- **验收标准（冻结 WHAT）**:
  - 初始无 retry 标签时 `retry <N> get` 输出 `0`。
  - 连续三次 `--role reviewer retry <N> incr` 后 `get` 输出 `3`，且 Issue 上**只有** `riper-retry-3` 一个 retry 标签（排他）。
  - 第四次 `incr` → 报错提示转 `riper-blocked`、exit 1，标签仍为 `riper-retry-3`。
  - `retry <N> reset` 后 `get` 输出 `0`。
  - `incr` 不影响 `p0` 与 `riper-*` 状态标签（跨族无误删）。

### 步骤 10：`issue retry` 路由 + usage
- **编号**: 10 | **完成状态**: [x] ✅ 已验证：`issue retry 1`（缺动作）→ usage exit 1；`issue retry 1 foo`（非法动作）→ usage exit 1；`--help` 含 `issue retry` 与「incr 仅 QA」说明
- **涉及文件**: `scripts/git-ops.sh`（`issue` 子命令 `case`、`usage()`）
- **逻辑说明**: `issue` 子命令 `case` 新增 `retry)`：校验 `$# -eq 2` 且第二参数 ∈ `incr|get|reset`（否则 usage），调 `cmd_issue_retry`。usage 增加 `issue retry <num> <incr|get|reset>`（注明 incr 仅 QA）。
- **验收标准（冻结 WHAT）**:
  - `issue retry 1`（缺动作）→ usage + exit 1；`issue retry 1 foo`（非法动作）→ usage + exit 1。
  - `--help` 输出含 `issue retry` 说明与 QA 限定。

---

### E 组：可写区域 `guard`（P1 / E4）

### 步骤 11：新增 `role_writable_paths()` 白名单
- **编号**: 11 | **完成状态**: [x] ✅ 已验证：`role_writable_paths planner` 含 `docs/`、`reviewer` 含 `test/`、`developer` 含 plan.md 例外；三者互不相同；`hacker` → exit 1。配套 `path_writable` 做实际判定（Bash 3.2 case 通配，无 declare -A）
- **涉及文件**: `scripts/git-ops.sh`（`status_allowed` 附近）
- **逻辑说明**: `role_writable_paths <role>` 输出空格分隔的可写路径前缀白名单，与 T0 铁律 1 / `roles/*.md` 同源：`planner`→`docs/`；`developer`→除 `test/` 与 `docs/` 外全部，但放行 `docs/issues/*/plan.md`；`reviewer`→`test/` 与 `docs/issues/*/verify-report.md`。非法角色 → `log_error` + exit 1。**禁 Bash 4+ 语法（C1）**。
- **验收标准（冻结 WHAT）**:
  - `role_writable_paths planner` 输出含 `docs/`；`reviewer` 含 `test/`；三者互不相同且与 SKILL.md §1 persona 表「可写区域」一致。
  - `role_writable_paths hacker` → 报错 exit 1。

### 步骤 12：新增 `cmd_guard()` 越界检测
- **编号**: 12 | **完成状态**: [x] ✅ 已验证（throwaway repo 10 例全过）：planner 改 spec.md→0、改 scripts→1；reviewer 新增 test→0、改 scripts→1、改 verify-report→0；developer 改 plan.md→0、改 spec.md→1、改 scripts→0、改 test→1；干净工作区→0
- **涉及文件**: `scripts/git-ops.sh`
- **逻辑说明**: `cmd_guard <role>`。以 `git status --porcelain` 取全部变更（已暂存+未暂存+未跟踪；被 .gitignore 忽略的天然不列出），逐个比对白名单：命中前缀或通配（`docs/issues/*/plan.md` 等）→ 放行；否则计入越界。合规 → `log_info "guard(<role>) 通过：N 个变更文件均在可写区域内"` + exit 0；越界 → `log_error` 逐行列越界路径 + 该角色可写区域说明 + exit 1；无变更 → exit 0 提示「无待检变更」。
- **验收标准（冻结 WHAT）**:
  - planner 仅改 `docs/issues/1/spec.md` → `guard planner` exit 0；planner 改 `scripts/git-ops.sh` → exit 1 且输出含该越界路径。
  - reviewer 新增 `test/foo.sh` → `guard reviewer` exit 0；reviewer 改 `scripts/git-ops.sh` → exit 1。
  - developer 改 `docs/issues/1/plan.md` → exit 0；改 `docs/issues/1/spec.md` → exit 1。
  - 工作区干净 → exit 0。

### 步骤 13：`guard` 顶层路由 + `check_permission` 扩展 + usage
- **编号**: 13 | **完成状态**: [x] ✅ 已验证：`guard developer` 在本仓库 exit 0；`guard`（缺角色）→ usage exit 1；`guard hacker`→exit 1；`--help` 含 `guard <role>`（注明提交前必跑）；check_permission 新增 guard action
- **涉及文件**: `scripts/git-ops.sh`（`main()` 顶层 `case`、`check_permission`、`usage()`）
- **逻辑说明**: 顶层 `case` 新增 `guard)`：要求 `$# -eq 1`，调 `cmd_guard`。`check_permission` 新增 action `guard`（三角色放行，非法角色拒绝）。usage 增加 `guard <role>`（注明「提交前必跑」）。
- **验收标准（冻结 WHAT）**:
  - `guard planner` 可执行；`guard`（缺角色）→ usage + exit 1；`guard foo` → 报错 exit 1；`--help` 含 `guard` 说明。

---

### G 组：doctor 与文档同步（E6）

### 步骤 16：`cmd_doctor` 追加标签体系就绪检查
- **编号**: 16 | **完成状态**: [x] ✅ 已验证：本仓库 doctor 输出「标签体系就绪：14/14」exit 0；stub 仅返回部分标签 → 列缺失清单 + 提示 labels init + exit 1；stub 使 label list 失败 → 报「无法获取远端标签（网络或权限问题）」（非「标签缺失」）+ exit 1；前四步输出不变
- **涉及文件**: `scripts/git-ops.sh`（`cmd_doctor`，授权检查之后）
- **逻辑说明**: 授权检查后追加第 5 步：取远端标签名集合（gh `gh label list --limit 200 --json name --jq '.[].name'`；glab `glab label list`；tea `tea labels`），比对 14 个（PRIORITY+STATUS+RETRY）。全在 → `log_info "标签体系就绪：14/14"`；有缺失 → `log_error` 列缺失清单 + 提示 `./scripts/git-ops.sh labels init` + exit 1；**label list 命令本身失败/网络不可达 → `log_error`「无法获取远端标签（网络或权限问题）」+ exit 1，不得误报「标签缺失」**。前四步输出保持不变。
- **验收标准（冻结 WHAT）**:
  - 本仓库 `doctor` → 输出含「标签体系就绪：14/14」，exit 0。
  - stub CLI 仅返回默认 10 标签 → doctor 列缺失项、提示 labels init、exit 1。
  - stub CLI 使 `label list` 失败 → 提示网络/权限问题（非「标签缺失」）、exit 1。
  - 前四步（环境/路由/安装/授权）输出与改动前一致。

### 步骤 17：`SKILL.md` 同步（四族 retry / 新命令 / guard 铁律）
- **编号**: 17 | **完成状态**: [x] ✅ 已验证：§1.2 补第四族 riper-retry（排他、incr 仅 QA）；§3.7「计入重试计数」改为 `issue retry incr`、「重试 3 次」改为 `retry get` 返回 3；§4 补 issue list/retry/guard/labels init；§0 Git 操作补子命令清单；T0 新增第 9 条 guard 铁律含能力边界声明；全文无「三族」残留、无新增「实现 issue get --json」指引（仅保留 §3.0.1 既有禁止表述）
- **涉及文件**: `SKILL.md`
- **逻辑说明**: (a) §1.2 标签体系正式补**第四族 `riper-retry-1/2/3`**（排他，仅 QA 可 incr），与既有「优先级/状态/自由标签」并列；(b) §1.2 后或 §3.7 明确 `issue retry <N> incr|get|reset` 为重试计数唯一入口，§3.7「计入重试计数」改为调用 `issue retry incr`、「重试 3 次」改为「`retry get` 返回 3」；(c) §4 快速用法补 `issue list` / `issue retry` / `guard` / `labels init` 行；(d) §0「Git 操作」补新增子命令清单；(e) T0 铁律追加「提交前必须 `guard <当前角色>`，越界即 T0 事故」，并**如实声明 guard 只校验区域级越界、无法校验是否超出 plan 范围**。**不得新增「实现 issue get --json」相关表述**（与 §3.0.1 现行约束一致）。
- **验收标准（冻结 WHAT）**:
  - SKILL.md §1.2 出现「四族」语义与 `riper-retry-`；§3.7/§1.2 出现 `issue retry`；§4 含 `issue list`/`guard`/`labels init`；T0 铁律新增含 `guard` 及其能力边界声明。
  - 全文无「三族标签」等与实现矛盾的残留；无「实现 issue get --json」的新增指引。

### 步骤 18：`roles/*.md` 三文件补 guard 义务
- **编号**: 18 | **完成状态**: [x] ✅ 已验证：三文件均在「Issue 操作权限」补 guard 约定 + 「必须做」补对应条目；声明的可写区域与 `role_writable_paths` 实际输出逐字一致（planner=docs/；reviewer=test/+verify-report；developer=禁 test/、除 plan.md 外禁 docs/）；开头「用户可随时修改本文件」提示 3/3 保留
- **涉及文件**: `roles/planner.md`、`roles/developer.md`、`roles/reviewer.md`
- **逻辑说明**: 各在「Issue 操作权限」小节后新增一条 `guard` 约定，与各自 T0 可写区域**逐字对应**步骤 11 白名单：PM「提交/交付前跑 `guard planner`，可写区域仅 `docs/`」；开发「提交前跑 `guard developer`，禁写 `test/`、除 `docs/issues/<N>/plan.md` 外禁写 `docs/`」；QA「交付验收报告前跑 `guard reviewer`，可写区域仅 `test/` 与 `docs/issues/<N>/verify-report.md`」。并在各自「必须做」清单加对应条目。保留各文件开头「用户可随时修改本文件」提示。
- **验收标准（冻结 WHAT）**:
  - 三文件均出现 `guard <角色>` 与对应可写区域清单，且与 `role_writable_paths` 实际返回一致；开头提示未被覆盖。

### 步骤 19：`references/cli-setup.md` 追加标签初始化章节
- **编号**: 19 | **完成状态**: [x] ✅ 已验证：cli-setup.md 新增「标签体系初始化」小节（§0 之后），含 labels init 示例、幂等说明、14 标签清单（与三族常量逐字一致）、doctor 检查说明、各平台最小权限（GitHub 需 repo scope）、典型报错 `'p0' not found`
- **涉及文件**: `references/cli-setup.md`
- **逻辑说明**: 新增「标签体系初始化」一节：为何需要（priority/status 依赖标签存在，缺失即 `'p0' not found`）、命令 `./scripts/git-ops.sh labels init`、幂等说明、14 标签清单（4+7+3）、doctor 会检查该项、各平台最小权限（GitHub 需 `repo` scope 建标签）。
- **验收标准（冻结 WHAT）**:
  - 文档含「标签体系初始化」小节与 `labels init` 示例；14 标签名与三族常量完全一致；说明缺失时典型报错 `'p0' not found`。

---

### H 组：自检与回归

### 步骤 20：语法检查、权限回归与新能力 stub 验证
- **编号**: 20 | **完成状态**: [ ]
- **涉及文件**: 无（纯验证）
- **逻辑说明**: (a) `bash -n scripts/git-ops.sh`；(b) 回归既有权限矩阵用例（developer close/reopen/priority 拒绝、planner status riper-execute 拒绝、reviewer priority 拒绝、label add 互斥族拒绝含**新增 retry 族**、放行路径），exit code 与改动前一致；(c) stub `gh`/`glab`/`tea` 验证新命令三平台路由（`issue list`、`issue retry`、`guard`、doctor 标签检查）调用了对应 CLI 子命令；(d) 验证 `riper-retry-*` 不被状态族排他清理误删；(e) 确认 macOS Bash 3.2 可运行新增命令（无 `declare: -A` 等）。**全部以 `test/` 下黑盒 invariant 脚本固化（QA 职责）。**
- **验收标准（冻结 WHAT）**:
  - `bash -n` 通过；既有权限用例逐条一致；新命令 stub 路由正确；`issue status <N> riper-execute` 后 `riper-retry-*` 仍在；Bash 3.2 无语法错。

---

## 提交策略

- **分批提交**，每批后跑步骤 20 的 (a)(b) 快速自检：
  1. 步骤 6–7（issue list）→ `feat: wire up issue list with filtering and priority sort (#1)`
  2. 步骤 8–10（retry 持久化）→ `feat: persist RIPER retry count via issue retry (#1)`
  3. 步骤 11–13、16（guard + doctor 标签检查）→ `feat: add writable-area guard and doctor label-readiness check (#1)`
  4. 步骤 17–19（文档同步）→ `docs: sync SKILL/roles/references for retry family, guard and issue list (#1)`
- **提交门禁（依修订 #1 的分批思想 + 本轮 guard 在批次 3 才就绪）**：
  - 批次 1、2：`bash -n` + 权限矩阵回归 + 人工核对 `git status --porcelain` 变更均在「涉及文件」范围内（guard 尚未实现，不得为自检提前实现 guard）。
  - 批次 3、4：`bash -n` + 权限矩阵回归 + **实际执行 `./scripts/git-ops.sh guard developer` 且 exit 0** 方可提交。
- 提交信息一律引用 `(#1)`。

## 计划修订记录

| 修订 # | 原因 | 变更内容 | 时间 |
|--------|------|----------|------|
| 1 | 提交策略顺序缺陷（guard 在步骤 11~13 才实现，批次 1/2 门禁不可能满足） | 提交策略按批次区分门禁；步骤实现与验收未变 | 2026-09-09 |
| 2 | **计划相对 v0.5.6 严重失真 + 与现行 SKILL.md 冲突**：steps5-7 中 5 已实现而 6-7 未接路由；step15 引用 #14 已证伪删除的大写 `Labels:` sed 先例；steps14-15 的 `issue get --json` 与 SKILL.md §3.0.1「不要实现 issue get --json」矛盾；全部行号过期。经用户授权按现状重基线化（执行有价值剩余、剔除 issue get --json） | 标记步骤 1–5 为 `[x]` 已完成；**剔除步骤 14–15**（issue get --json，交 #17）；步骤 8/9 改为新增独立 `raw_issue_labels` 读取标签（gh 用 `--json`、glab/tea 解析**小写** `labels:`，禁大写 sed）；步骤 6/7/11/12/13/16/17/18/19/20 按 v0.5.6 实际代码刷新涉及文件与验收；行号降级为定位提示不冻结 | 2026-09-21 |

---
*本计划写回 Issue 后即冻结；任何修订必须走"中断→回退→更新→再同步"流程。*
