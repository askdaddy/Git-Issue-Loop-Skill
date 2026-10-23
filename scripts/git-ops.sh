#!/usr/bin/env bash
# ============================================================================
# git-ops.sh —— 跨平台 Git Issue CLI 封装（GitHub / GitLab / Gitea / Forgejo）
#
# 适用环境（仅支持以下两个平台）：
#   - macOS（zsh / bash 均可执行本脚本）
#   - Windows（需在 Git Bash 中运行，随 Git for Windows 自带；
#     不支持在 CMD / PowerShell 直接运行）
#
# 通过 `git remote -v` 自动检测托管平台，分层路由到对应 CLI：
#   1) 主机名启发式（快路径）：
#        github.com / *github*（GitHub Enterprise） -> gh
#        gitlab.com / *gitlab*                      -> glab
#        *gitea* / *forgejo* / codeberg.org         -> tea
#   2) 主机名无关键字（自建实例常见）：查各已安装 CLI 的授权注册表，该 host
#      被哪个 CLI 授权就路由到哪个（gh/glab: auth status --hostname；tea: login list）。
#   3) 仍无法判定：显式失败（exit 1）并输出该 host 的授权指引，绝不默认路由到 gh。
#      自建 GitLab/Gitea 必须先授权对应 CLI（glab/tea），不能用 gh 访问。
#
# 用法：
#   ./git-ops.sh --role <planner|developer|reviewer> <子命令> ...
#
#   完整子命令清单以 usage() 为唯一事实来源（不带参数运行 ./git-ops.sh 即打印）：
#   issue list|get|comment|create|close|reopen|priority|status|retry|claim|label、
#   labels init、guard <role> [num]、workspace status|start|finish、platform、doctor。
#   排他语义：priority / status / retry 三族各自同时只保留一个标签，
#   由脚本在写入时自动清理同族其他标签。认领 riper-claimed 非排他，不参与此清理。
#
# CLI 优先原则：
#   Issue 操作一律优先使用本地官方 CLI（GitHub->gh，GitLab->glab，Gitea/Forgejo->tea）。
#   本地缺 CLI 或未授权时，本脚本不会静默失败也不会改走其他途径，
#   而是输出对应平台的安装 + 授权指南并以 exit 1 中止，由 Agent 转交给用户处理。
#   完整指南见 references/cli-setup.md。
#
# 标签族（前三个互斥，由脚本强制排他；合计 15 个内置标签 = 4 + 7 + 3 + 1）：
#   - 优先级 p0~p3，按艾森豪威尔矩阵定义：
#       p0 = 重要且紧急    p1 = 重要不紧急
#       p2 = 紧急不重要    p3 = 不重要不紧急
#     优先级只能用平台 label 能力表达，禁止写进 Issue 标题。
#   - 状态 riper-research / riper-innovation / riper-plan / riper-execute /
#     riper-review / riper-verified / riper-blocked（描述 RIPER 各阶段，同时只能一个）
#   - 重试计数 riper-retry-1 / -2 / -3（QA 审查 FAIL 退回计划的轮次，达 3 即上限须转
#     riper-blocked）；incr 仅 reviewer 可用，get/reset 不限角色。
#   - 认领 riper-claimed（第四类，受管但**不排他**）：多会话并行时标记某 Issue 已被
#     某会话认领，自动挑选跳过之。由 issue claim <N> claim|release|get 操作，计入内置标签。
#   - 自由标签（第五类，**不排他**）由 Agent 自定义，便于上下文召回（如 module/xxx、
#     type/bug），经 issue label add|remove 操作，不计入上述 15 个内置标签。
#
# 权限硬校验（--role，也可用环境变量 GIT_OPS_ROLE 指定）：
#   - close / reopen 仅 planner / reviewer 可用，Developer 调用直接拒绝；
#   - priority 仅 planner 可设置；
#   - status 按角色白名单：
#       planner   riper-research / riper-innovation / riper-plan
#       developer riper-execute / riper-review / riper-blocked
#       reviewer  riper-plan（FAIL 退回） / riper-verified / riper-blocked
#   - retry incr 仅 reviewer 可用（get / reset 不限角色）；
#   - claim claim/release/get 不限角色（跨会话协调信号，非状态裁决）；对已认领 Issue
#     执行 claim 会被拒绝（不抢占），硬校验在 cmd_issue_claim 内；
#   - label add/remove 不限角色，但禁止操作上述三个互斥标签族与认领族（优先级 / 状态 /
#     重试 / 认领，须用专用子命令）；
#   - 未指定 --role 时仅打印警告并放行（便于人工直接调用）。
# ============================================================================

set -euo pipefail

# 结构化运行事件（opt-in，FD3 NDJSON）。契约见 references/runtime-output.md。
# 默认完全关闭；只有 main 路由到受覆盖命令时才 arm，其他命令零事件、零额外调用。
# shellcheck source=runtime-events.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/runtime-events.sh"

# ---------------------------------------------------------------------------
# 辅助函数
# ---------------------------------------------------------------------------
log_info()  { printf '[git-ops] %s\n' "$*"; }
log_error() { printf '[git-ops][ERROR] %s\n' "$*" >&2; }

# 细节日志：仅当 GIT_OPS_VERBOSE=1 时输出。
# 排他清理会产生大量「标签不存在」噪音、CLI 成功时会吐裸 URL，
# 默认静默以免淹没真正的错误；排查问题时设 GIT_OPS_VERBOSE=1 可还原全部细节。
log_debug() {
  if [[ "${GIT_OPS_VERBOSE:-0}" == "1" ]]; then
    printf '[git-ops][debug] %s\n' "$*"
  fi
}

usage() {
  cat <<'EOF'
Usage:
  git-ops.sh [--role <planner|developer|reviewer>] <command> ...

  角色用于 Issue 操作权限硬校验（也可用环境变量 GIT_OPS_ROLE 指定）：
    close / reopen 仅 planner / reviewer 可用，Developer 直接拒绝；
    priority 仅 planner 可设；status 按角色白名单校验。

Commands:
  git-ops.sh issue list [--state open|closed|all] [--status <riper-*>] [--priority <p0|p1|p2|p3>]
                                                  列出 Issue（按优先级 p0→p3 排序；glab/tea 无标签列时降级）
  git-ops.sh issue get <num> [--strict]            获取正文与评论；strict 时任一读取失败即停止
  git-ops.sh issue comment <num> "<content>"       给 Issue 添加评论
  git-ops.sh issue create "<title>" "<body>"       创建新 Issue
  git-ops.sh issue close <num>                     关闭 Issue
  git-ops.sh issue reopen <num>                    重新打开 Issue
  git-ops.sh issue priority <num> <p0|p1|p2|p3|none>    设置优先级；none 仅显式 PM 清空并回读
  git-ops.sh issue status <num> <riper-*|none>          切换状态；none 仅显式角色清其有权状态
  git-ops.sh issue retry <num> <incr|get|reset>    重试计数持久化（排他 riper-retry-K；incr 仅 QA 可用）
  git-ops.sh issue claim <num> <claim|release|get> 认领互斥（非排他 riper-claimed；claim 写标签+审计评论，已认领则拒绝抢占）
  git-ops.sh issue label <num> add <label>         添加自由标签（上下文召回用）
  git-ops.sh issue label <num> remove <label>      移除自由标签
  git-ops.sh labels init                            初始化标签体系（4 优先级 + 7 状态 + 3 重试 + 1 认领，幂等）
  git-ops.sh guard <role> [num]                    可写区域越界自检（提交前必跑；role=planner|developer|reviewer；
                                                    num=Issue 编号，给出时额外校验当前分支是否为 riper/<num>）
  git-ops.sh workspace status                       报告工作区隔离状态（主/linked、分支、归属 Issue、worktree 清单）
  git-ops.sh workspace start <num> [--base <ref>]   为 Issue <num> 建立隔离工作区（仓库外 worktree + riper/<num> 分支，基于上游）
  git-ops.sh workspace finish <num>                 清理 Issue <num> 的本地工作区（仅干净且已合并进上游时；不含推送/合并）
  git-ops.sh integration push|pr-list|pr-view <N>     QA 集成原语（pr-view 参数为 PR 编号）
  git-ops.sh integration pr-create <N> <title> <body-file>
  git-ops.sh integration local <N> <target-branch>    开发显式本地降级；仅 linked worktree，保持 open
  git-ops.sh integration release-view <vX.Y.Z>
  git-ops.sh integration release-create <vX.Y.Z> <SHA>  QA GitHub Release；需独立发布授权与全套件通过
  git-ops.sh platform                               打印检测到的托管平台
  git-ops.sh doctor                                 自检：运行环境 → CLI 路由 → 安装 → 授权 → 15 个内置标签就绪
                                                    （任一项不就绪即输出指南并 exit 1）
EOF
  exit 1
}

# ---------------------------------------------------------------------------
# 自建实例识别（离线）：主机名无平台关键字时，查各已安装 CLI 的授权/配置注册表，
# 判断该 host 归属哪个平台。命中返回对应 CLI（gh|glab|tea），都不命中返回非 0。
# 顺序 gh -> glab -> tea（多命中取首个）；未安装的 CLI 跳过，查询异常一律视为未命中。
# ---------------------------------------------------------------------------
detect_by_registry() {
  local host="$1"

  # gh / glab：`auth status --hostname <host>` 对「已授权该 host」退出 0，对陌生 host 退出非 0
  #（实测 gh 对非 GitHub host 恒退出非 0，故不会误认领自建 GitLab/Gitea）
  if command -v gh >/dev/null 2>&1 && gh auth status --hostname "${host}" >/dev/null 2>&1; then
    echo "gh"
    return 0
  fi
  if command -v glab >/dev/null 2>&1 && glab auth status --hostname "${host}" >/dev/null 2>&1; then
    echo "glab"
    return 0
  fi
  # tea：login list 的 URL / SSH HOST 列含该 host 即视为已登记
  # lazy-ladder: fixed-string 子串匹配，多个含相同子串的 tea 登录取首个命中；
  #              需精确到 host+端口唯一时再改为按列解析比对。
  if command -v tea >/dev/null 2>&1 && tea login list 2>/dev/null | grep -F -- "${host}" >/dev/null; then
    echo "tea"
    return 0
  fi
  return 1
}

# 自建实例无法识别时的授权指引（输出到 stderr）：列出三平台针对该 host 的授权命令
print_selfhost_guide() {
  local host="$1"
  {
    printf '────────────── 无法识别自建实例平台：%s ──────────────\n' "${host}"
    printf '主机名无平台关键字，且没有任何已安装 CLI 授权过该实例。\n'
    printf '为避免误用 gh 访问非 GitHub 平台，请先为该自建实例授权对应 CLI，脚本据此识别路由：\n\n'
    printf '  [自建 GitLab]         glab auth login --hostname %s\n' "${host}"
    printf '  [自建 Gitea/Forgejo]  tea login add            # 实例 URL 填 https://%s\n' "${host}"
    printf '  [GitHub Enterprise]   gh auth login --hostname %s\n\n' "${host}"
    printf '[完成后重试] ./scripts/git-ops.sh doctor\n'
    printf '[完整指南] references/cli-setup.md\n'
  } >&2
}

# ---------------------------------------------------------------------------
# 平台检测：解析 git remote -v 的首个 origin URL
# 返回值：gh | glab | tea
# ---------------------------------------------------------------------------
detect_platform() {
  # 必须在 git 仓库内执行
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_error "当前目录不是 git 仓库，无法检测远程平台。"
    exit 1
  fi

  # 取第一个 remote URL（优先 fetch 行，去重）
  local remote_url
  remote_url="$(git remote -v | awk '/\(fetch\)/{print $2; exit}')"
  if [[ -z "${remote_url}" ]]; then
    # 某些环境 git remote -v 不带 (fetch) 标记，退化为取第一行
    remote_url="$(git remote -v | awk 'NR==1{print $2}')"
  fi
  if [[ -z "${remote_url}" ]]; then
    log_error "未找到任何 git remote，无法检测托管平台。"
    exit 1
  fi

  local host
  # 兼容 https://host/owner/repo.git 与 git@host:owner/repo.git 两种形式
  if [[ "${remote_url}" == git@* ]]; then
    host="${remote_url#git@}"
    host="${host%%:*}"
  else
    host="${remote_url#*://}"
    host="${host%%/*}"
    host="${host%%:*}" # 去掉端口
  fi
  # 转小写（tr 写法兼容 macOS 自带 Bash 3.2 与 Windows Git Bash，无需 Bash 4+）
  host="$(printf '%s' "${host}" | tr '[:upper:]' '[:lower:]')"

  case "${host}" in
    github.com)
      echo "gh"
      ;;
    gitlab.com|*gitlab*)
      echo "glab"
      ;;
    *gitea*|*forgejo*|*codeberg.org)
      echo "tea"
      ;;
    *github*)
      # GitHub Enterprise（如 github.corp.com）：非精确 github.com 的启发式快路径
      echo "gh"
      ;;
    *)
      # 主机名无平台关键字（自建实例常见）：查各已安装 CLI 的授权注册表，识别该 host
      # 真正归属哪个平台后再路由。绝不默认路由到 gh —— 用 gh 访问自建 GitLab/Gitea 会失败甚至
      # 误操作；无法判定时显式失败并给出授权指引。
      local registry_cli
      if registry_cli="$(detect_by_registry "${host}")"; then
        # 诊断走 stderr：detect_platform 的 stdout 是返回值通道，不可污染
        log_debug "remote host '${host}' 无平台关键字，按已授权 CLI 注册表识别为 ${registry_cli}。" >&2
        echo "${registry_cli}"
      else
        log_error "无法识别 remote host '${host}' 属于哪个平台（无 CLI 已授权该实例）。"
        print_selfhost_guide "${host}"
        exit 1
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# tea 仓库显式指定：tea 0.15.x 无法解析 SSH alias 形式的 remote（如 gitea:owner/repo.git），
# 会报 "remote repository required"，必须显式传 --repo owner/repo
# ---------------------------------------------------------------------------

# 从 remote URL 解析 owner/repo；解析失败返回非零
compute_repo_slug() {
  local url
  url="$(git remote -v | awk '/\(fetch\)/{print $2; exit}')"
  [[ -z "${url}" ]] && url="$(git remote -v | awk 'NR==1{print $2}')"
  [[ -z "${url}" ]] && return 1
  url="${url#*://}"   # 去协议（https:// ssh://）
  url="${url#git@}"   # 去 git@ 用户前缀
  url="${url/:/\/}"   # 首个冒号归一为斜杠（git@host:path / alias:path / host:port/path 均覆盖；owner/repo 恒为末两段）
  url="${url%.git}"
  url="${url%/}"
  local owner repo
  repo="${url##*/}"
  owner="${url%/*}"
  owner="${owner##*/}"
  [[ -z "${owner}" || -z "${repo}" ]] && return 1
  printf '%s/%s' "${owner}" "${repo}"
}

# tea 包装器：能解析出 slug 时在参数尾部显式追加 --repo（tea 0.15.x 的 --repo
# 定义在各叶子子命令上，非全局 flag，置于参数尾部对 pflag 混排解析最稳）
tea_cmd() {
  local slug
  if slug="$(compute_repo_slug)"; then
    tea "$@" --repo "${slug}"
  else
    tea "$@"
  fi
}

# ---------------------------------------------------------------------------
# CLI 就绪检查：安装 + 授权（未就绪时输出指南并中止）
# ---------------------------------------------------------------------------

# 识别宿主系统（仅支持 macOS 与 Windows/Git Bash）
detect_os() {
  case "$(uname -s 2>/dev/null)" in
    Darwin*) echo "macos" ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT) echo "windows" ;;
    *) echo "unsupported" ;;
  esac
}

# 输出安装指南（仅针对当前缺失的 CLI）
print_install_guide() {
  local cli="$1" os
  os="$(detect_os)"
  {
    printf '────────────── 安装指南：%s ──────────────\n' "${cli}"
    printf '本 Skill 仅支持 macOS 与 Windows（Windows 需在 Git Bash 中运行）；当前系统识别为：%s\n\n' "${os}"
    case "${cli}" in
      gh)
        printf '[macOS]\n  brew install gh\n\n'
        printf '[Windows]（任选一种）\n  winget install --id GitHub.cli\n  scoop install gh\n\n'
        printf '[官方文档] https://cli.github.com/\n' ;;
      glab)
        printf '[macOS]\n  brew install glab\n\n'
        printf '[Windows]（任选一种）\n  winget install --id glab.glab\n  scoop install glab\n\n'
        printf '[官方文档] https://gitlab.com/gitlab-org/cli\n' ;;
      tea)
        printf '[macOS]\n  brew install tea\n\n'
        printf '[Windows] 从官方 Release 下载二进制并加入 PATH\n  https://dl.gitea.com/tea/\n\n'
        printf '[官方文档] https://gitea.com/gitea/tea\n' ;;
    esac
    printf '\n[完整指南] references/cli-setup.md\n'
  } >&2
}

# 输出授权指南（仅针对当前 CLI）
print_auth_guide() {
  local cli="$1"
  {
    printf '────────────── 授权指南：%s ──────────────\n' "${cli}"
    case "${cli}" in
      gh)
        printf '  gh auth login        # 交互选择 GitHub.com / 自建实例 + HTTPS/SSH + 浏览器或 token\n'
        printf '  gh auth login --hostname github.your-corp.com   # 企业自建实例\n'
        printf '  gh auth status       # 验证；token 需含 repo 权限（Issue 读写）\n'
        printf '  非交互环境：export GH_TOKEN=xxx\n' ;;
      glab)
        printf '  glab auth login                                   # gitlab.com\n'
        printf '  glab auth login --hostname gitlab.your-corp.com    # 自建 GitLab\n'
        printf '  glab auth status                                  # 验证；token scope 需含 api\n'
        printf '  非交互环境：export GITLAB_TOKEN=xxx（自建实例另需 GITLAB_HOST）\n' ;;
      tea)
        printf '  tea login add        # 交互输入：登录名 / 实例 URL / access token\n'
        printf '                       # token 获取：Gitea -> Settings -> Applications -> Generate New Token\n'
        printf '                       # 权限需含 read:issue 与 write:issue\n'
        printf '  tea login list       # 验证已配置的登录\n'
        printf '  tea login use <name> # 多实例时切换默认登录\n' ;;
    esac
    printf '\n[完成后重试] ./scripts/git-ops.sh doctor\n'
    printf '[安全] 请勿将 token 写入仓库文件或提交到版本库；也不要要求 Agent 代填凭据。\n'
    printf '[完整指南] references/cli-setup.md\n'
  } >&2
}

# 检测 CLI 是否已授权
check_auth() {
  local cli="$1"
  case "${cli}" in
    gh)   gh auth status >/dev/null 2>&1 ;;
    glab) glab auth status >/dev/null 2>&1 ;;
    # tea 无 auth status：以 login list 是否列出实例 URL 判断。
    # 不用 grep -q：它匹配即退出，tea 尚未写完时收 SIGPIPE 退 141，配合 set -o pipefail
    # 会把已授权误判为失败（实测约 14/30）；无 -q 时 grep 读尽 stdin，无此问题。
    tea)  tea login list 2>/dev/null | grep -i 'http' >/dev/null ;;
    *)    return 1 ;;
  esac
}

# 本次脚本调用内已验证过授权的 CLI（避免重复调用 auth status 拖慢批量标签操作）
_AUTH_OK_CLI=""

# 确保 CLI 已安装且已授权；任一不满足则输出指南并 exit 1
require_cli() {
  local cli="$1"

  if ! command -v "${cli}" >/dev/null 2>&1; then
    log_error "未安装 CLI：${cli}。无法操作 Issue，请按下方指南安装后重试。"
    print_install_guide "${cli}"
    print_auth_guide "${cli}"
    exit 1
  fi

  # 同一次调用内已验证过则跳过
  if [[ "${_AUTH_OK_CLI}" == "${cli}" ]]; then
    return 0
  fi

  if ! check_auth "${cli}"; then
    log_error "CLI ${cli} 已安装但未授权（或授权已失效/网络不可达）。请按下方指南完成授权。"
    print_auth_guide "${cli}"
    exit 1
  fi

  _AUTH_OK_CLI="${cli}"
}

# ---------------------------------------------------------------------------
# 角色权限硬校验 + 互斥标签族管理
#
# 角色来源（优先级）：--role 参数 > 环境变量 GIT_OPS_ROLE > 空（警告放行）
# 权限矩阵：
#   - close / reopen 仅 planner / reviewer 可用；Developer 直接拒绝；
#   - priority 仅 planner 可设置；
#   - status 按角色白名单校验；
#   - label add/remove 不限角色，但不得触碰互斥标签族；
#   - labels init 不限角色（属仓库级配置初始化，非 Issue 操作）；
#   - create / comment / get 不限角色。
# ---------------------------------------------------------------------------
ROLE="${GIT_OPS_ROLE:-}"

# 互斥标签族定义（同时只能存在一个）
# 优先级：艾森豪威尔矩阵 p0=重要且紧急 p1=重要不紧急 p2=紧急不重要 p3=不重要不紧急
PRIORITY_LABELS="p0 p1 p2 p3"
# 状态：RIPER 各阶段 + 终态
STATUS_LABELS="riper-research riper-innovation riper-plan riper-execute riper-review riper-verified riper-blocked"
# 重试计数：QA 审查 FAIL 退回计划的次数（第三族，同样排他；达 3 次后须转 riper-blocked）
# 存于 Issue 标签而非本地文件，以保证跨会话 / 跨机器 / 跨 agent 可见（Issue 为唯一事实来源）
RETRY_LABELS="riper-retry-1 riper-retry-2 riper-retry-3"
# 认领：多会话并行时标记 Issue 已被某会话认领（第四类，受管但**不排他**，计入内置标签）。
# 与 retry 同构——把「谁认领了」落到 Issue 标签而非依赖 Agent 跨会话记忆；自动挑选跳过已认领项。
# 仅经 issue claim <N> claim|release|get 操作（保证标签与审计评论同时落地），禁用 issue label 触碰。
CLAIM_LABELS="riper-claimed"

# 标签元数据：输出「颜色 描述」，颜色为 6 位 hex（不带 #），供 labels init 建标签时使用。
# 覆盖全部 15 个内置标签（4 优先级 + 7 状态 + 3 重试 + 1 认领）；未知标签返回非 0。
label_meta() {
  case "$1" in
    p0) echo "B60205 艾森豪威尔：重要且紧急 — 立即处理，阻塞发布/线上事故" ;;
    p1) echo "D93F0B 艾森豪威尔：重要不紧急 — 排期处理，核心价值与关键技术债" ;;
    p2) echo "FBCA04 艾森豪威尔：紧急不重要 — 尽快处理但可委派，低价值高时限" ;;
    p3) echo "CCCCCC 艾森豪威尔：不重要不紧急 — backlog，择机处理" ;;
    riper-research)   echo "0052CC RIPER [R] 研究：PM 提炼 spec、判定优先级" ;;
    riper-innovation) echo "5319E7 RIPER [I] 创新：PM 多方案对比与选型" ;;
    riper-plan)       echo "1D76DB RIPER [P] 计划：PM 拆解原子任务，基线冻结" ;;
    riper-execute)    echo "FEF2C0 RIPER [E] 执行：开发逐项落地 plan" ;;
    riper-review)     echo "F9D0C4 RIPER [R] 审查：QA 黑盒验收" ;;
    riper-verified)   echo "0E8A16 RIPER 终态：全部 PASS，由 QA 关闭 Issue" ;;
    riper-blocked)    echo "B60205 RIPER 异常终态：重试超限或遭遇阻塞，需人工介入" ;;
    riper-retry-1)    echo "FBCA04 RIPER 重试计数：审查 FAIL 退回 1 次（仅 QA 可递增）" ;;
    riper-retry-2)    echo "D93F0B RIPER 重试计数：审查 FAIL 退回 2 次（仅 QA 可递增）" ;;
    riper-retry-3)    echo "B60205 RIPER 重试计数：审查 FAIL 退回 3 次，已达上限须转 riper-blocked" ;;
    riper-claimed)    echo "000000 RIPER 认领：该 Issue 已被某会话认领，自动挑选跳过（非排他，经 issue claim 操作）" ;;
    *) return 1 ;;
  esac
}

# 判定标签是否属于优先级族 / 状态族
is_priority_label() {
  local l="$1" x
  for x in ${PRIORITY_LABELS}; do [[ "${x}" == "${l}" ]] && return 0; done
  return 1
}

is_status_label() {
  local l="$1" x
  for x in ${STATUS_LABELS}; do [[ "${x}" == "${l}" ]] && return 0; done
  return 1
}

# 判定标签是否属于重试计数族（riper-retry-1/2/3）
is_retry_label() {
  local l="$1" x
  for x in ${RETRY_LABELS}; do [[ "${x}" == "${l}" ]] && return 0; done
  return 1
}

# 判定标签是否属于认领族（riper-claimed；受管非排他，仅经 issue claim 操作）
is_claim_label() {
  local l="$1" x
  for x in ${CLAIM_LABELS}; do [[ "${x}" == "${l}" ]] && return 0; done
  return 1
}

# 判定某角色是否可将状态切到指定值
status_allowed() {
  local role="$1" status="$2"
  case "${role}:${status}" in
    # Planner（PM）：研究 / 创新 / 计划三阶段
    planner:riper-research|planner:riper-innovation|planner:riper-plan) return 0 ;;
    # Developer：开始执行 / 交付审查 / 遭遇阻塞
    developer:riper-execute|developer:riper-review|developer:riper-blocked) return 0 ;;
    # Reviewer（QA）：FAIL 退回计划 / 验收通过 / 阻塞
    reviewer:riper-plan|reviewer:riper-verified|reviewer:riper-blocked) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 角色可写区域（T0 铁律 1 的脚本化；与 SKILL.md §1 persona 表 / roles/*.md 同源）
#   planner   → 仅 docs/（降级落盘）
#   reviewer  → 仅 test/ 与 docs/issues/*/verify-report.md
#   developer → 业务代码：除 test/ 与 docs/ 外全部，但放行 docs/issues/*/plan.md（勾选完成状态）
# role_writable_paths 输出人类可读白名单（供 guard 失败时回显 + 验收 grep）；
# path_writable 做实际放行判定。二者必须同步修改，避免文档与实现漂移。
# ---------------------------------------------------------------------------
role_writable_paths() {
  local role="$1"
  case "${role}" in
    planner)   printf '%s\n' "docs/" ;;
    reviewer)  printf '%s\n' "test/" "docs/issues/*/verify-report.md" ;;
    developer) printf '%s\n' "（业务代码：除 test/ 与 docs/ 外全部）" "docs/issues/*/plan.md" ;;
    *)
      log_error "未知角色：${role}（应为 planner / developer / reviewer）。"
      exit 1
      ;;
  esac
}

# 判定单个路径是否落在该角色的可写区域内（Bash 3.2 兼容：用 case 通配，禁 declare -A）
path_writable() {
  local role="$1" path="$2"
  case "${role}" in
    planner)
      case "${path}" in
        docs/*) return 0 ;;
        *)      return 1 ;;
      esac
      ;;
    reviewer)
      case "${path}" in
        test/*)                          return 0 ;;
        docs/issues/*/verify-report.md)  return 0 ;;
        *)                               return 1 ;;
      esac
      ;;
    developer)
      case "${path}" in
        docs/issues/*/plan.md) return 0 ;;  # 例外先于 docs/ 拒绝
        test/*)                return 1 ;;
        docs/*)                return 1 ;;
        *)                     return 0 ;;  # 业务代码默认放行
      esac
      ;;
    *)
      log_error "未知角色：${role}（应为 planner / developer / reviewer）。"
      exit 1
      ;;
  esac
}

# 校验操作权限；越权直接报错退出
# 用法：check_permission <close|reopen|priority|status|label-add|label-remove> [值]
check_permission() {
  local action="$1" value="${2:-}"

  # 未指定角色：警告后放行（人工直接调用场景）
  if [[ -z "${ROLE}" ]]; then
    log_info "未指定 --role，跳过权限硬校验（Agent 调用时建议携带 --role）。"
    printf '%s\n' '[iloop-feedback] rule=ROLE-001 scope=unattributed (not a confirmed violation)' >&2
    return 0
  fi

  case "${ROLE}" in
    planner|developer|reviewer) ;;
    *)
      log_error "未知角色：${ROLE}（应为 planner / developer / reviewer）。"
      exit 1
      ;;
  esac

  case "${action}" in
    close|reopen)
      if [[ "${ROLE}" == "developer" ]]; then
        printf '%s\n' '[iloop-feedback] rule=ROLE-001 outcome=intercepted' >&2
        log_error "权限拒绝：Developer 禁止 ${action} Issue（执行者无权自我判定完成）。"
        _iloop_evt_mark "denied" "ROLE-001" "permission-denied" "none"
        exit 1
      fi
      ;;
    priority)
      if [[ "${ROLE}" != "planner" ]]; then
        printf '%s\n' '[iloop-feedback] rule=ROLE-001 outcome=intercepted' >&2
        log_error "权限拒绝：优先级仅 PM（planner）可在研究阶段判定设置。"
        _iloop_evt_mark "denied" "ROLE-001" "permission-denied" "none"
        exit 1
      fi
      if [[ "${value}" != none ]] && ! is_priority_label "${value}"; then
        log_error "非法优先级：'${value}'（合法值：${PRIORITY_LABELS}，艾森豪威尔矩阵）。"
        exit 1
      fi
      ;;
    status-clear)
      # 角色名已验证；按当前实际状态逐项校验，不能借 none 越权。
      ;;
    status)
      if ! is_status_label "${value}"; then
        log_error "非法状态：'${value}'（合法值：${STATUS_LABELS}）。"
        exit 1
      fi
      if ! status_allowed "${ROLE}" "${value}"; then
        printf '%s\n' '[iloop-feedback] rule=ROLE-001 outcome=intercepted' >&2
        log_error "权限拒绝：角色 ${ROLE} 无权将状态切换为 '${value}'。"
        _iloop_evt_mark "denied" "ROLE-001" "permission-denied" "none"
        exit 1
      fi
      ;;
    label-add|label-remove)
      # 互斥标签族必须走专用子命令，否则无法保证排他性
      if is_priority_label "${value}" || is_status_label "${value}"; then
        log_error "标签 '${value}' 属于互斥标签族，请改用 'issue priority' / 'issue status' 子命令；显式 none 可按角色权限清空该族。"
        exit 1
      fi
      if is_retry_label "${value}"; then
        log_error "标签 '${value}' 属于重试计数族（排他），请改用 'issue retry <num> incr|get|reset' 子命令。"
        exit 1
      fi
      if is_claim_label "${value}"; then
        log_error "标签 '${value}' 属认领族，请改用 'issue claim <num> claim|release|get' 子命令（保证标签与审计评论同时落地）。"
        exit 1
      fi
      ;;
    retry-incr)
      # 重试计数仅由 QA 在审查 FAIL 退回时登记，PM / 开发不得自增（防止执行者刷计数）
      if [[ "${ROLE}" != "reviewer" ]]; then
        printf '%s\n' '[iloop-feedback] rule=ROLE-001 outcome=intercepted' >&2
        log_error "权限拒绝：重试计数由 QA（reviewer）在审查 FAIL 时登记，${ROLE} 无权 incr。"
        _iloop_evt_mark "denied" "ROLE-001" "permission-denied" "none"
        exit 1
      fi
      ;;
    retry-read)
      # 只读：三角色均放行（get / reset 不限角色）
      ;;
    claim-read|claim-write)
      # 认领是跨会话协调信号、非 Issue 状态裁决，三角色（及无角色）均放行；
      # 「不抢占已认领」的硬校验在 cmd_issue_claim 内实现，不在此处按角色限制。
      ;;
    guard)
      # 提交前自检属合法动作，三角色均放行；这里校验位置参数中的目标角色名是否合法
      case "${value}" in
        planner|developer|reviewer) ;;
        *)
          log_error "guard：未知角色 '${value}'（应为 planner / developer / reviewer）。"
          _iloop_evt_mark "denied" "ROLE-001" "permission-denied" "none"
          exit 1
          ;;
      esac
      ;;
    *)
      # create / comment / get 等不限角色
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 子命令实现
# ---------------------------------------------------------------------------

# 列出 Issue：输出机读中间格式，每行「编号<TAB>状态<TAB>标题<TAB>标签(逗号分隔)」
# 用法：raw_issue_list <open|closed|all>
# 降级声明（C2）：仅 gh 能取到标签列；glab / tea 的列表输出不含标签，
# 此时第四列输出空字串，由上层 cmd_issue_list 标注「(标签不可用)」并禁用标签类筛选。
raw_issue_list() {
  local state="$1"
  local __plat
  __plat="$(detect_platform)" || exit 1
  case "${__plat}" in
    gh)
      require_cli gh
      # gh 内置 --jq，无需外部 jq（C7）；@tsv 保证四列以 TAB 分隔
      gh issue list --state "${state}" --limit 200 \
        --json number,title,labels,state \
        --jq '.[] | [.number, .state, .title, ([.labels[].name] | join(","))] | @tsv'
      ;;
    glab)
      require_cli glab
      log_debug "glab 列表输出不含标签列，已降级：--status / --priority 筛选在本平台不可用。" >&2
      # glab 默认仅列 open；--closed 列已关闭；--all 列全部
      local glab_flag=""
      case "${state}" in
        closed) glab_flag="--closed" ;;
        all)    glab_flag="--all" ;;
      esac
      # 输出形如：#12  标题文本；提取编号与标题，状态列用入参回填
      glab issue list ${glab_flag} 2>/dev/null \
        | sed -n 's/^#\([0-9][0-9]*\)[[:space:]][[:space:]]*\(.*\)$/\1	\2/p' \
        | while IFS="$(printf '\t')" read -r n t; do
            printf '%s\t%s\t%s\t\n' "${n}" "${state}" "${t}"
          done
      ;;
    tea)
      require_cli tea
      log_debug "tea 列表输出不含标签列，已降级：--status / --priority 筛选在本平台不可用。" >&2
      # tea 的 --state 仅支持 open / closed；all 时不传该参数
      if [[ "${state}" == "all" ]]; then
        tea_cmd issues 2>/dev/null \
          | sed -n 's/#\([0-9][0-9]*\)[[:space:]][[:space:]]*\(.*\)$/\1	\2/p' \
          | while IFS="$(printf '\t')" read -r n t; do
              printf '%s\t%s\t%s\t\n' "${n}" "${state}" "${t}"
            done
      else
        tea_cmd issues --state "${state}" 2>/dev/null \
          | sed -n 's/#\([0-9][0-9]*\)[[:space:]][[:space:]]*\(.*\)$/\1	\2/p' \
          | while IFS="$(printf '\t')" read -r n t; do
              printf '%s\t%s\t%s\t\n' "${n}" "${state}" "${t}"
            done
      fi
      ;;
  esac
}

# 列出 Issue：在 raw_issue_list 的四列 TAB 中间格式上做筛选 + 优先级排序 + 对齐输出。
# 用法：cmd_issue_list [--state open|closed|all] [--status <riper-*>] [--priority <p0|p1|p2|p3>]
# 排序键：p0<p1<p2<p3<无优先级；Bash 3.2 兼容（加数字前缀 sort -n 后剥离，禁 declare -A）。
cmd_issue_list() {
  local state="open" want_status="" want_prio=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --state)    [[ $# -ge 2 ]] || { log_error "--state 需要参数（open|closed|all）。"; exit 1; };    state="$2";       shift 2 ;;
      --status)   [[ $# -ge 2 ]] || { log_error "--status 需要参数（riper-*）。"; exit 1; };            want_status="$2"; shift 2 ;;
      --priority) [[ $# -ge 2 ]] || { log_error "--priority 需要参数（p0|p1|p2|p3）。"; exit 1; };      want_prio="$2";   shift 2 ;;
      *) log_error "未知参数：'$1'（合法：--state open|closed|all / --status <riper-*> / --priority <p0|p1|p2|p3>）。"; exit 1 ;;
    esac
  done

  case "${state}" in
    open|closed|all) ;;
    *) log_error "非法 --state：'${state}'（合法值：open closed all）。"; exit 1 ;;
  esac
  if [[ -n "${want_prio}" ]] && ! is_priority_label "${want_prio}"; then
    log_error "非法 --priority：'${want_prio}'（合法值：${PRIORITY_LABELS}）。"; exit 1
  fi
  if [[ -n "${want_status}" ]] && ! is_status_label "${want_status}"; then
    log_error "非法 --status：'${want_status}'（合法值：${STATUS_LABELS}）。"; exit 1
  fi

  local raw
  raw="$(raw_issue_list "${state}")"
  if [[ -z "${raw}" ]]; then
    log_info "（无 state='${state}' 的 Issue）"
    return 0
  fi

  # 探测标签列是否可用（glab/tea 列表降级时第四列为空 → C2 显式降级）
  local labels_avail=0 _n _s _t _l
  while IFS="$(printf '\t')" read -r _n _s _t _l; do
    [[ -n "${_l}" ]] && { labels_avail=1; break; }
  done <<EOF_RAW
${raw}
EOF_RAW
  if [[ "${labels_avail}" -eq 0 ]]; then
    log_debug "本平台列表输出不含标签列（C2 降级）：优先级/状态显示为 (无)，标签类筛选不可用。" >&2
    if [[ -n "${want_status}" || -n "${want_prio}" ]]; then
      log_error "本平台（glab/tea）列表不含标签列，--status / --priority 筛选不可用，已忽略该筛选。"
    fi
    want_status=""; want_prio=""
  fi

  # 过滤 + 计算排序键 → 输出「key<TAB>num<TAB>prio<TAB>status<TAB>title」→ 排序 → 对齐表格
  {
    local num st title labels tok prio disp key
    while IFS="$(printf '\t')" read -r num st title labels; do
      [[ -z "${num}" ]] && continue
      prio=""; disp=""
      for tok in $(printf '%s' "${labels}" | tr ',' ' '); do
        case "${tok}" in
          p0|p1|p2|p3)   [[ -z "${prio}" ]] && prio="${tok}" ;;
          riper-retry-*) : ;;
          riper-claimed) : ;;  # 认领标签非状态，排除出状态列（否则污染自动挑选读取）
          riper-*)       [[ -z "${disp}" ]] && disp="${tok}" ;;
        esac
      done
      if [[ -n "${want_status}" ]]; then
        case ",${labels}," in *",${want_status},"*) ;; *) continue ;; esac
      fi
      if [[ -n "${want_prio}" ]]; then
        case ",${labels}," in *",${want_prio},"*) ;; *) continue ;; esac
      fi
      [[ -z "${prio}" ]] && prio="(无)"
      [[ -z "${disp}" ]] && disp="${st}"
      case "${prio}" in p0) key=0 ;; p1) key=1 ;; p2) key=2 ;; p3) key=3 ;; *) key=4 ;; esac
      printf '%s\t%s\t%s\t%s\t%s\n' "${key}" "${num}" "${prio}" "${disp}" "${title}"
    done <<EOF_ROWS
${raw}
EOF_ROWS
  } | sort -t"$(printf '\t')" -k1,1n -k2,2n | {
    printf '%-7s %-7s %-19s %s\n' "编号" "优先级" "状态" "标题"
    local key num prio disp title
    while IFS="$(printf '\t')" read -r key num prio disp title; do
      printf '%-7s %-7s %-19s %s\n' "#${num}" "${prio}" "${disp}" "${title}"
    done
  }
}

# 严格读取用于接入和标签审计；旧入口保留评论 best-effort 兼容。
cmd_issue_get() {
  local num="$1" strict="${2:-}" __plat
  local -a reader
  __plat="$(detect_platform)" || return 1
  require_cli "${__plat}"
  case "${__plat}" in
    gh) reader=(gh issue view "${num}") ;;
    glab) reader=(glab issue view "${num}") ;;
    tea) reader=(tea_cmd issues "${num}") ;;
  esac
  if ! "${reader[@]}"; then
    log_error "Issue 正文读取失败，停止；不得依据部分输出修正标签。"
    return 1
  fi
  if [[ "${strict}" == "--strict" ]]; then
    if ! "${reader[@]}" --comments; then
      log_error "Issue 评论读取失败，严格模式停止；不得将部分输出当完整输入。"
      return 1
    fi
  else
    "${reader[@]}" --comments 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# 添加评论：gh/glab 支持 `issue comment <num> -b/--body`；tea 使用 issues 命令组
cmd_issue_comment() {
  local num="$1" content="$2"
  # 平台检测失败时必须显式报错退出（命令替换的失败会被 case 吞掉）
  local __plat write_rc=0
  __plat="$(detect_platform)" || exit 1
  { case "${__plat}" in
      gh)
        require_cli gh
        gh issue comment "${num}" --body "${content}"
        ;;
      glab)
        require_cli glab
        glab issue note "${num}" --message "${content}"
        ;;
      tea)
        require_cli tea
        # tea 0.15.1：评论实体是 comments 子命令（issues 视图无 --comment flag）
        tea_cmd comments add "${num}" "${content}"
        ;;
    esac
  } || write_rc=$?
  if [[ "${write_rc}" -ne 0 ]]; then
    _iloop_evt_mark "failed" "unknown" "write-failed" "unknown"
    return "${write_rc}"
  fi
  _iloop_evt_mark "success" "unknown" "completed" "remote-write"
}

# ---------------------------------------------------------------------------
# 标签底层操作（各平台原生命令）
# ---------------------------------------------------------------------------

# 在仓库中创建标签（幂等）：不存在则创建，已存在则更新颜色与描述，两者均不报错。
# 用法：raw_label_create <名称> <颜色(6位hex，不带#)> <描述>
# 输出：向 stdout 打印 created / updated（供上层汇总）；两者均失败时 return 1。
# 注：require_cli 成功路径静默，因此 stdout 只包含本函数的结果字串；
#     内部 log_debug 必须重定向到 stderr，否则会污染上层 $(...) 捕获。
raw_label_create() {
  local name="$1" color="$2" desc="$3"
  local __plat
  __plat="$(detect_platform)" || exit 1
  case "${__plat}" in
    gh)
      require_cli gh
      if gh label create "${name}" --color "${color}" --description "${desc}" >/dev/null 2>&1; then
        printf 'created'
      elif gh label edit "${name}" --color "${color}" --description "${desc}" >/dev/null 2>&1; then
        printf 'updated'
      else
        return 1
      fi
      ;;
    glab)
      require_cli glab
      # glab 的 --color 需带 # 前缀；新版 glab（>=1.118）要求 --name，旧版接受位置参数，故两者都试
      if glab label create --name "${name}" --color "#${color}" --description "${desc}" >/dev/null 2>&1 \
         || glab label create "${name}" --color "#${color}" --description "${desc}" >/dev/null 2>&1; then
        printf 'created'
      elif glab label edit --name "${name}" --color "#${color}" --description "${desc}" >/dev/null 2>&1 \
         || glab label edit "${name}" --color "#${color}" --description "${desc}" >/dev/null 2>&1; then
        printf 'updated'
      else
        return 1
      fi
      ;;
    tea)
      require_cli tea
      # tea 0.15.x 支持 --name/--color/--description（--color 必填，缺省会报 invalid color format）；
      # 无 label edit 能力。⚠️ Gitea 对非 scoped 标签名不查重（实测重复 labels init 会产生同名重复标签），
      # create 恒成功，幂等性必须靠「先查存在再创建」保证（与 raw_label_add 的查重谓词一致）：
      if tea_cmd labels list 2>/dev/null \
            | awk -F'│' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$4); print $4}' \
            | grep -Fxq -- "${name}"; then
        log_debug "tea 标签 '${name}' 已存在（Gitea 不查重名，跳过 create）。" >&2
        printf 'updated'
      elif tea_cmd labels create --name "${name}" --color "${color}" --description "${desc}" >/dev/null 2>&1; then
        printf 'created'
      else
        return 1
      fi
      ;;
  esac
}

# 写入前的正向目标证明。只接收十进制编号，失败/字段缺失/旧 CLI 均关闭写路径。
# GitLab 的 Issue/MR IID 独立，因此不以同号 MR 是否存在作为判据。
require_issue_target() {
  local num="$1" plat kind="unknown" out="" line idx item_kind url extra count=0
  case "${num}" in ''|0*|*[!0-9]*) log_error "Issue 编号必须是无前导零的正整数。"; return 1 ;; esac
  plat="$(detect_platform)" || return 1
  require_cli "${plat}"
  case "${plat}" in
    gh)
      kind="$(gh issue view "${num}" --json number,url --jq \
        "if .number == ${num} and (.url | endswith(\"/issues/${num}\")) then \"issue\" elif .number == ${num} and (.url | endswith(\"/pull/${num}\")) then \"pull-request\" else \"unknown\" end" 2>/dev/null)" || kind=unknown
      if [[ "${kind}" != issue && "${kind}" != pull-request ]]; then
        out="$(gh pr view "${num}" --json number,url --jq \
          "if .number == ${num} and (.url | endswith(\"/pull/${num}\")) then \"pull-request\" else \"unknown\" end" 2>/dev/null)" || out=unknown
        [[ "${out}" != pull-request ]] || kind=pull-request
      fi
      ;;
    glab)
      kind="$(glab issue view "${num}" --output json --jq \
        "if .iid == ${num} and (.web_url | endswith(\"/-/issues/${num}\")) then \"issue\" elif .iid == ${num} and (.web_url | endswith(\"/-/merge_requests/${num}\")) then \"pull-request\" else \"unknown\" end" 2>/dev/null)" || kind=unknown
      ;;
    tea)
      # 只请求固定字段，拒绝旧版本忽略格式、额外行、错编号或未知 kind。
      if out="$(tea_cmd issues "${num}" --output tsv --fields index,kind,url 2>/dev/null)"; then
        kind=unknown
        while IFS= read -r line; do
          line="${line%$'\r'}"
          [[ -n "${line}" ]] || continue
          [[ "${line}" != $'index\tkind\turl' && "${line}" != $'INDEX\tKIND\tURL' ]] || continue
          count=$((count + 1))
          IFS=$'\t' read -r idx item_kind url extra <<< "${line}"
          [[ "${idx}" == "${num}" && -z "${extra}" ]] || continue
          case "${item_kind}:${url}" in
            issue:http*/issues/"${num}"|Issue:http*/issues/"${num}") kind=issue ;;
            pull:http*/pulls/"${num}"|Pull:http*/pulls/"${num}"|pull-request:http*/pulls/"${num}") kind=pull-request ;;
          esac
        done <<< "${out}"
        [[ "${count}" -eq 1 ]] || kind=unknown
      fi
      ;;
  esac
  case "${kind}" in
    issue) return 0 ;;
    pull-request) log_error "#${num} 是 Pull Request / Merge Request，不是 Issue；已拒绝标签写入。" ;;
    *) log_error "无法确认 #${num} 是 Issue（${plat} 读取失败、字段缺失或格式不支持）；已拒绝标签写入。" ;;
  esac
  _iloop_evt_mark "failed" "unknown" "target-check-failed" "none"
  return 1
}

# 清空路径不复用 best-effort remove：真实失败必须上抛，不能伪报清空成功。
raw_label_remove_checked() {
  local num="$1" label="$2" plat
  plat="$(detect_platform)" || return 1
  require_cli "${plat}"
  case "${plat}" in
    gh) gh issue edit "${num}" --remove-label "${label}" >/dev/null ;;
    glab) glab issue update "${num}" --unlabel "${label}" >/dev/null ;;
    tea) tea_cmd issues edit "${num}" --remove-labels "${label}" >/dev/null ;;
  esac
}

# 先读、全量权限预检、按实际名称删除、再读核验；不改无关族、不盲重试。
clear_issue_family() {
  local num="$1" family="$2" current remaining lab lc touched=0 member
  current="$(raw_issue_labels "${num}")" || { log_error "读取标签失败，未开始清空。"; return 1; }
  # 全量预检必须在第一条删除前完成，防止混合有权/无权状态被部分清空。
  while IFS= read -r lab; do
    lc="$(printf '%s' "${lab}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${family}" == status ]] && is_status_label "${lc}" && ! status_allowed "${ROLE}" "${lc}"; then
      log_error "权限拒绝：${ROLE} 无权清空状态 '${lab}'；未删除任何标签。"
      _iloop_evt_mark "denied" "ROLE-001" "permission-denied" "none"
      return 1
    fi
  done <<< "${current}"
  while IFS= read -r lab; do
    lc="$(printf '%s' "${lab}" | tr '[:upper:]' '[:lower:]')"
    member=0
    if [[ "${family}" == priority ]]; then is_priority_label "${lc}" && member=1; else is_status_label "${lc}" && member=1; fi
    [[ "${member}" -eq 1 ]] || continue
    if ! raw_label_remove_checked "${num}" "${lab}"; then
      log_error "清空 ${family} 失败，可能部分完成；请回读核对，未自动重试。"
      _iloop_evt_mark "partial" "unknown" "family-cleanup-failed" "unknown"
      return 1
    fi
    touched=1
  done <<< "${current}"
  if ! remaining="$(raw_issue_labels "${num}")"; then
    log_error "清空后回读失败，结果未确认；未报告成功。"
    _iloop_evt_mark "failed" "unknown" "family-cleanup-failed" "unknown"
    return 1
  fi
  while IFS= read -r lab; do
    lc="$(printf '%s' "${lab}" | tr '[:upper:]' '[:lower:]')"
    member=0
    if [[ "${family}" == priority ]]; then is_priority_label "${lc}" && member=1; else is_status_label "${lc}" && member=1; fi
    if [[ "${member}" -eq 1 ]]; then
      log_error "清空后仍存在 ${family} 族标签，结果未确认；未自动重试。"
      _iloop_evt_mark "failed" "unknown" "family-cleanup-failed" "unknown"
      return 1
    fi
  done <<< "${remaining}"
  if [[ "${touched}" -eq 1 ]]; then
    _iloop_evt_mark "success" "unknown" "completed" "remote-write"
  else
    _iloop_evt_mark "success" "unknown" "completed" "none"
  fi
  log_info "已清空 ${family} 族标签（回读确认，无关标签未写入）。"
}

# 给 Issue 添加标签
raw_label_add() {
  local num="$1" label="$2"
  local __plat
  __plat="$(detect_platform)" || exit 1
  case "${__plat}" in
    gh)
      require_cli gh
      gh issue edit "${num}" --add-label "${label}" >/dev/null
      ;;
    glab)
      require_cli glab
      glab issue update "${num}" --label "${label}" >/dev/null 2>/dev/null \
        || glab issue label "${num}" "${label}" >/dev/null # 新旧版本 glab 兼容
      ;;
    tea)
      require_cli tea
      # tea 0.15.1 无 labels add 子命令，打标签走 issues edit --add-labels；
      # 自由标签可能尚未存在：仅在缺失时创建（Gitea 对非 scoped 名称不查重，
      # 无条件 create 会翻倍制造同名标签），需带 --color
      if ! tea_cmd labels list 2>/dev/null \
            | awk -F'│' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$4); print $4}' \
            | grep -Fxq -- "${label}"; then
        tea_cmd labels create --name "${label}" --color ededed >/dev/null 2>&1 || true
      fi
      tea_cmd issues edit "${num}" --add-labels "${label}" >/dev/null
      ;;
  esac
}

# 移除 Issue 标签（尽力而为：目标标签不存在时不报错）
raw_label_remove() {
  local num="$1" label="$2"
  local __plat
  __plat="$(detect_platform)" || exit 1
  case "${__plat}" in
    gh)
      require_cli gh
      gh issue edit "${num}" --remove-label "${label}" >/dev/null 2>/dev/null \
        || log_debug "标签 '${label}' 已不存在或已移除。"
      ;;
    glab)
      require_cli glab
      # 用官方 --unlabel 直接移除；勿改回解析 issue view 文本：
      # glab 1.118 输出键为小写 labels:（大写匹配恒为空），且 --label 为增量语义，
      # 「取现有标签剔除后整体覆盖」并不成立
      glab issue update "${num}" --unlabel "${label}" >/dev/null 2>/dev/null \
        || log_debug "标签 '${label}' 已不存在或已移除。"
      ;;
    tea)
      require_cli tea
      # tea 0.15.1 移除标签走 issues edit --remove-labels（issues 视图无 --unlabel flag）
      tea_cmd issues edit "${num}" --remove-labels "${label}" >/dev/null 2>/dev/null \
        || log_debug "标签 '${label}' 已不存在或已移除。"
      ;;
  esac
}

# 读取某 Issue 的标签名（每行一个，保留原始大小写）。机读优先；旧 CLI 才降级解析文本。
# 成功且无标签：无输出、return 0。CLI 失败或输出无法确认 labels 字段：return 1。
raw_issue_labels() {
  local num="$1"
  local __plat out
  __plat="$(detect_platform)" || exit 1
  case "${__plat}" in
    gh)
      require_cli gh
      gh issue view "${num}" --json labels --jq '.labels[].name' 2>/dev/null
      ;;
    glab)
      require_cli glab
      # 新版 glab 用内置 jq 输出 sentinel + 标签，sentinel 使「空标签」可与失败区分。
      if out="$(glab issue view "${num}" --output json \
          --jq '"__ILOOP_LABELS_OK__", (.labels[] | if type == "string" then . else .name end)' \
          2>/dev/null)" && [[ "${out%%$'\n'*}" == "__ILOOP_LABELS_OK__" ]]; then
        printf '%s\n' "${out}" | sed '1d' | grep -v '^$' || true
        return 0
      fi
      # 旧版降级：只有明确看见 labels 字段才把空结果视为成功。
      if ! out="$(glab issue view "${num}" 2>/dev/null)" \
         || ! printf '%s\n' "${out}" | grep -Eq '^[Ll]abels:[[:space:]]*'; then
        return 1
      fi
      printf '%s\n' "${out}" \
        | sed -n 's/^[Ll]abels:[[:space:]]*\(.*\)$/\1/p' \
        | tr ',' '\n' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | grep -v '^$' || true
      ;;
    tea)
      require_cli tea
      # tea 0.16+ 可按字段输出 JSON；labels 数组为空也是可确认的成功结果。
      if out="$(tea_cmd issues "${num}" --output json --fields labels 2>/dev/null)" \
         && printf '%s\n' "${out}" | grep -Eq '"labels"[[:space:]]*:'; then
        printf '%s\n' "${out}" \
          | grep -Eo '"name"[[:space:]]*:[[:space:]]*"[^"]*"' \
          | sed 's/^"name"[[:space:]]*:[[:space:]]*"//; s/"$//' || true
        return 0
      fi
      # 旧版降级与 glab 一致：文本必须显式包含 labels 字段。
      if ! out="$(tea_cmd issues "${num}" 2>/dev/null)" \
         || ! printf '%s\n' "${out}" | grep -Eq '^[Ll]abels:[[:space:]]*'; then
        return 1
      fi
      printf '%s\n' "${out}" \
        | sed -n 's/^[Ll]abels:[[:space:]]*\(.*\)$/\1/p' \
        | tr ',' '\n' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
        | grep -v '^$' || true
      ;;
    *) return 1 ;;
  esac
}

# 大小写不敏感的同族排他清理（两步，兼顾 #14 读独立性与 #19 大小写变体）：
#   步骤1：无条件移除全族规范形（除 keep）——不依赖读取，即使 raw_issue_labels 失败
#          也能清掉小写规范标签（保留 #14「移除不依赖文本解析」的健壮性契约）。
#   步骤2：再读 Issue 现有标签，补移「小写属于本族但本身非规范形」的大小写变体
#          （如 P0 之于 p0）——根因：GitLab 大小写敏感，deepwiki/历史遗留的大写变体
#          精确匹配清不掉，与新加小写并存为「P0p0」且每次设置复发。读取失败则本步跳过，
#          步骤1 已兜底规范形。
# 用法：raw_label_remove_family_ci <num> <keep> <family-member>...（keep 为空则清全族）
raw_label_remove_family_ci() {
  local num="$1" keep="$2"; shift 2
  local f actual actual_lc f_lc infamily is_canonical current
  # 步骤1：无条件移除全族规范形（除 keep）
  for f in "$@"; do
    [[ "${f}" == "${keep}" ]] && continue
    raw_label_remove "${num}" "${f}" || true
  done
  # 步骤2：补移大小写变体（仅非规范形，避免与步骤1重复调用）
  if ! current="$(raw_issue_labels "${num}")"; then
    log_error "无法读取 Issue #${num} 的实际标签，不能保证同族标签排他；已停止添加目标标签。"
    return 1
  fi
  while IFS= read -r actual; do
    [[ -z "${actual}" ]] && continue
    [[ "${actual}" == "${keep}" ]] && continue
    is_canonical=0
    for f in "$@"; do
      [[ "${actual}" == "${f}" ]] && { is_canonical=1; break; }
    done
    [[ "${is_canonical}" -eq 1 ]] && continue
    actual_lc="$(printf '%s' "${actual}" | tr '[:upper:]' '[:lower:]')"
    infamily=0
    for f in "$@"; do
      f_lc="$(printf '%s' "${f}" | tr '[:upper:]' '[:lower:]')"
      [[ "${actual_lc}" == "${f_lc}" ]] && { infamily=1; break; }
    done
    if [[ "${infamily}" -eq 1 ]]; then
      raw_label_remove "${num}" "${actual}" || true
    fi
  done <<< "${current}"
}

# 取远端「仓库级」全部标签名（每行一个），供 doctor 校验标签体系是否就绪。
# 关键区分：CLI/网络失败时 return 1（doctor 据此报「无法获取远端标签」而非「标签缺失」）。
#   gh   —— `gh label list --json name`（可靠机读）
#   glab —— `glab label list --output json`（可靠机读）；旧版 fallback 文本首列
#   tea  —— `tea labels list` 盒式表，名字在第 4 个 │ 字段（与 raw_label_create 同解析）
raw_label_names() {
  local __plat out
  __plat="$(detect_platform)" || return 1
  case "${__plat}" in
    gh)
      require_cli gh
      if ! out="$(gh label list --limit 200 --json name --jq '.[].name' 2>/dev/null)"; then return 1; fi
      ;;
    glab)
      require_cli glab
      # glab >=1.7 支持 --output json；1.118 起文本首列变为 ID 而非名称
      if out="$(glab label list --output json 2>/dev/null)"; then
        out="$(printf '%s\n' "${out}" | grep -o '"name":"[^"]*"' | sed 's/^"name":"//;s/"$//')"
      else
        if ! out="$(glab label list 2>/dev/null)"; then return 1; fi
        out="$(printf '%s\n' "${out}" | awk 'NF {print $1}')"
      fi
      ;;
    tea)
      require_cli tea
      if ! out="$(tea_cmd labels list 2>/dev/null)"; then return 1; fi
      out="$(printf '%s\n' "${out}" | awk -F'│' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$4); print $4}' | grep -v '^$' || true)"
      ;;
    *) return 1 ;;
  esac
  printf '%s\n' "${out}"
}

# 按仓库标签筛选全部 Issue（每行一个编号，包含 open / closed）。
# 空结果成功；CLI 不支持可靠机读或请求失败时 return 1。
raw_issue_numbers_by_label() {
  local label="$1"
  local __plat out page
  __plat="$(detect_platform)" || return 1
  case "${__plat}" in
    gh)
      require_cli gh
      gh issue list --state all --label "${label}" --limit 1000 \
        --json number --jq '.[].number' 2>/dev/null
      ;;
    glab)
      require_cli glab
      page=1
      while :; do
        if ! out="$(glab issue list --all --label "${label}" --page "${page}" --per-page 100 \
            --output json --jq '.[].iid' 2>/dev/null)"; then
          return 1
        fi
        [[ -z "${out}" ]] && break
        printf '%s\n' "${out}"
        [[ "$(printf '%s\n' "${out}" | grep -c .)" -lt 100 ]] && break
        page=$((page + 1))
      done
      ;;
    tea)
      require_cli tea
      if ! out="$(tea_cmd issues --state all --labels "${label}" --limit 1000 \
          --output json --fields index 2>/dev/null)"; then
        return 1
      fi
      printf '%s\n' "${out}" \
        | grep -Eo '"index"[[:space:]]*:[[:space:]]*[0-9]+' \
        | sed 's/.*:[[:space:]]*//' || true
      ;;
    *) return 1 ;;
  esac
}

# 删除仓库级标签。Issue 关联必须由调用方先迁移并验证。
raw_repository_label_delete() {
  local label="$1"
  local __plat out id ids=""
  __plat="$(detect_platform)" || return 1
  case "${__plat}" in
    gh)
      require_cli gh
      gh label delete "${label}" --yes >/dev/null 2>&1
      ;;
    glab)
      require_cli glab
      glab label delete "${label}" >/dev/null 2>&1
      ;;
    tea)
      require_cli tea
      if ! out="$(tea_cmd labels list --limit 1000 2>/dev/null)"; then return 1; fi
      ids="$(printf '%s\n' "${out}" | awk -F'│' -v want="${label}" '
        {
          id=$2; name=$4
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
          if (name == want && id ~ /^[0-9]+$/) print id
        }')"
      [[ -n "${ids}" ]] || return 1
      while IFS= read -r id; do
        [[ -z "${id}" ]] && continue
        tea_cmd labels delete --id "${id}" >/dev/null 2>&1 || return 1
      done <<< "${ids}"
      ;;
    *) return 1 ;;
  esac
}

# GitHub 标签名大小写不区分，不能创建 P0 / p0 两个标签；原生 rename 可无损规范化。
raw_repository_label_rename_gh() {
  local from="$1" to="$2"
  require_cli gh
  gh label edit "${from}" --name "${to}" >/dev/null 2>&1
}

# 将仓库级优先级标签统一为 p0-p3。glab / tea 允许大小写变体并存，
# 必须先迁移并验证全部 Issue 关联，再删除仓库变体；失败时保留变体以便重试。
normalize_repository_priority_labels() {
  local labels actual canonical plat issues num current remaining
  if ! labels="$(raw_label_names)"; then
    log_error "无法读取仓库标签目录，不能规范化优先级标签。"
    return 1
  fi
  plat="$(detect_platform)" || return 1

  while IFS= read -r actual; do
    [[ -z "${actual}" ]] && continue
    canonical="$(printf '%s' "${actual}" | tr '[:upper:]' '[:lower:]')"
    is_priority_label "${canonical}" || continue
    [[ "${actual}" == "${canonical}" ]] && continue

    if [[ "${plat}" == "gh" ]]; then
      if ! raw_repository_label_rename_gh "${actual}" "${canonical}"; then
        log_error "仓库优先级标签 '${actual}' 重命名为 '${canonical}' 失败。"
        return 1
      fi
      log_info "normalized ${actual} -> ${canonical}（GitHub 原生重命名，Issue 关联保留）。"
      continue
    fi

    if ! issues="$(raw_issue_numbers_by_label "${actual}")"; then
      log_error "无法枚举仓库标签 '${actual}' 关联的全部 Issue；请升级 ${plat} 后重试。"
      return 1
    fi
    while IFS= read -r num; do
      [[ -z "${num}" ]] && continue
      raw_label_add "${num}" "${canonical}" || return 1
      raw_label_remove "${num}" "${actual}" || return 1
      if ! current="$(raw_issue_labels "${num}")"; then
        log_error "迁移后无法验证 Issue #${num} 的标签；仓库变体 '${actual}' 保留。"
        return 1
      fi
      if ! printf '%s\n' "${current}" | grep -Fxq -- "${canonical}" \
         || printf '%s\n' "${current}" | grep -Fxq -- "${actual}"; then
        log_error "Issue #${num} 的 '${actual}' -> '${canonical}' 迁移验证失败；仓库变体保留。"
        return 1
      fi
      log_info "migrated Issue #${num}: ${actual} -> ${canonical}."
    done <<< "${issues}"

    if ! raw_repository_label_delete "${actual}"; then
      log_error "Issue 迁移完成，但仓库标签变体 '${actual}' 删除失败。"
      return 1
    fi
    log_info "deleted repository label variant ${actual}."
  done <<< "${labels}"

  if ! remaining="$(raw_label_names)"; then return 1; fi
  while IFS= read -r actual; do
    [[ -z "${actual}" ]] && continue
    canonical="$(printf '%s' "${actual}" | tr '[:upper:]' '[:lower:]')"
    if is_priority_label "${canonical}" && [[ "${actual}" != "${canonical}" ]]; then
      log_error "仓库优先级标签规范化未收敛，仍存在 '${actual}'。"
      return 1
    fi
  done <<< "${remaining}"
}

# ---------------------------------------------------------------------------
# 自由标签（上下文召回用）：禁止操作互斥标签族
# ---------------------------------------------------------------------------
cmd_issue_label() {
  local num="$1" action="$2" label="$3"

  # 权限硬校验：互斥族标签必须走专用子命令
  check_permission "label-${action}" "${label}"

  if [[ "${action}" == "add" ]]; then
    raw_label_add "${num}" "${label}"
  else
    raw_label_remove "${num}" "${label}"
  fi
}

# ---------------------------------------------------------------------------
# 优先级设置（艾森豪威尔矩阵 p0~p3）：排他——先移除同族其他标签再写入
# ---------------------------------------------------------------------------
cmd_issue_priority() {
  local num="$1" priority="$2"

  if [[ "${priority}" == none && -z "${ROLE}" ]]; then
    log_error "清空优先级必须显式指定 --role planner。"; return 1
  fi
  check_permission priority "${priority}"
  require_issue_target "${num}" || return 1
  if [[ "${priority}" == none ]]; then clear_issue_family "${num}" priority; return; fi

  # 排他性保证：同族其他优先级标签一律移除（大小写不敏感，含 P0 之类变体）
  if ! raw_label_remove_family_ci "${num}" "${priority}" ${PRIORITY_LABELS}; then
    _iloop_evt_mark "failed" "unknown" "family-cleanup-failed" "unknown"
    return 1
  fi
  _iloop_evt_mark "" "" "family-cleaned" ""
  local add_rc=0
  raw_label_add "${num}" "${priority}" || add_rc=$?
  if [[ "${add_rc}" -ne 0 ]]; then
    # 清理已完成、目标标签未确认写入：只声明子步骤完成，不伪称无副作用。
    _iloop_evt_mark "partial" "unknown" "add-failed" "label-cleanup-only"
    return "${add_rc}"
  fi
  _iloop_evt_mark "success" "unknown" "completed" "remote-write"
  log_info "优先级已设为 ${priority}（艾森豪威尔矩阵，同族标签已排他清理）。"
}

# ---------------------------------------------------------------------------
# RIPER 状态切换：排他——先移除同族其他状态再写入
# ---------------------------------------------------------------------------
cmd_issue_status() {
  local num="$1" status="$2"

  if [[ "${status}" == none ]]; then
    [[ -n "${ROLE}" ]] || { log_error "清空状态必须显式指定 --role；仅可清当前角色有权设置的状态。"; return 1; }
    check_permission status-clear
    require_issue_target "${num}" || return 1
    clear_issue_family "${num}" status
    return
  fi
  check_permission status "${status}"
  require_issue_target "${num}" || return 1

  # 排他性保证：同族其他状态标签一律移除（大小写不敏感，含大写变体）
  if ! raw_label_remove_family_ci "${num}" "${status}" ${STATUS_LABELS}; then
    _iloop_evt_mark "failed" "unknown" "family-cleanup-failed" "unknown"
    return 1
  fi
  _iloop_evt_mark "" "" "family-cleaned" ""
  local add_rc=0
  raw_label_add "${num}" "${status}" || add_rc=$?
  if [[ "${add_rc}" -ne 0 ]]; then
    # 清理已完成、目标标签未确认写入：只声明子步骤完成，不伪称无副作用。
    _iloop_evt_mark "partial" "unknown" "add-failed" "label-cleanup-only"
    return "${add_rc}"
  fi
  _iloop_evt_mark "success" "unknown" "completed" "remote-write"
  log_info "状态已切换为 ${status}（同族状态标签已排他清理）。"
}

# ---------------------------------------------------------------------------
# 重试计数持久化：把 QA 审查 FAIL 的轮次落到排他的 riper-retry-K 标签上。
# 用法：cmd_issue_retry <num> <incr|get|reset>
#   get   —— 读当前 K（命中 riper-retry-K 输出 K，无则输出 0）；不限角色（retry-read）。
#   incr  —— 仅 QA：K≥3 则报错转 riper-blocked；否则排他清理后写入 riper-retry-$((K+1))。
#   reset —— 排他清理全部 retry 标签（新一轮闭环清零）；不限角色。
# 跨族安全：仅触碰 RETRY_LABELS，绝不影响 p0~p3 与 riper-* 状态标签。
# ---------------------------------------------------------------------------
cmd_issue_retry() {
  local num="$1" action="$2"
  case "${action}" in
    incr) check_permission retry-incr; require_issue_target "${num}" || return 1 ;;
    reset) check_permission retry-read; require_issue_target "${num}" || return 1 ;;
  esac

  # 读当前重试计数 K：扫描该 Issue 标签，命中 riper-retry-<K>（大小写不敏感）取 K，否则 0
  local cur=0 lab lab_lc current
  if ! current="$(raw_issue_labels "${num}")"; then
    log_error "无法读取 Issue #${num} 的实际标签，不能确定当前重试计数。"
    return 1
  fi
  while IFS= read -r lab; do
    [[ -z "${lab}" ]] && continue
    lab_lc="$(printf '%s' "${lab}" | tr '[:upper:]' '[:lower:]')"
    case "${lab_lc}" in
      riper-retry-[1-9]) cur="${lab_lc#riper-retry-}" ;;
    esac
  done <<< "${current}"

  case "${action}" in
    get)
      check_permission retry-read
      printf '%s\n' "${cur}"
      ;;
    reset)
      raw_label_remove_family_ci "${num}" "" ${RETRY_LABELS} || return 1
      log_info "重试计数已清零（移除全部 riper-retry-* 标签）。"
      ;;
    incr)
      if [[ "${cur}" -ge 3 ]]; then
        log_error "已达重试上限 3 次（当前 riper-retry-${cur}），应转 riper-blocked 等待人工介入，不再自增。"
        exit 1
      fi
      local next=$((cur + 1))
      # 排他：先移除同族其他 retry 标签（大小写不敏感），再写入 next
      raw_label_remove_family_ci "${num}" "riper-retry-${next}" ${RETRY_LABELS} || return 1
      raw_label_add "${num}" "riper-retry-${next}"
      log_info "重试计数已登记为 riper-retry-${next}（同族已排他清理）。"
      ;;
    *)
      usage
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 组织认领/释放审计评论载体：动作 + git 用户 + UTC 时间戳 + worktree 路径 + 分支 + 主机名。
# 供人工审计与陈旧认领判定。任一字段不可得时占位降级（不报错）——审计信息尽力而为，
# 缺失不阻断认领。命令替换一律 `|| true`：set -e 下 git config/hostname 失败会误杀赋值。
# 用法：claim_audit_body <claim|release> <num>
claim_audit_body() {
  local action="$1" num="$2"
  local user email ts wt br host verb
  user="$(git config user.name 2>/dev/null || true)";  [[ -n "${user}"  ]] || user="(未知)"
  email="$(git config user.email 2>/dev/null || true)"; [[ -n "${email}" ]] || email="(未知)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"; [[ -n "${ts}" ]] || ts="(未知)"
  wt="$(git rev-parse --show-toplevel 2>/dev/null || true)"; [[ -n "${wt}" ]] || wt="$(pwd -P)"
  br="$(current_branch 2>/dev/null || true)"; [[ -n "${br}" ]] || br="(非分支/detached)"
  host="$(hostname 2>/dev/null || true)"; [[ -n "${host}" ]] || host="(未知)"
  if [[ "${action}" == "claim" ]]; then verb="认领"; else verb="释放"; fi
  printf '%s\n' \
    "RIPER ${verb}：Issue #${num}" \
    "" \
    "- 动作：${action}" \
    "- 会话标识：${user} <${email}> @ ${host}" \
    "- 时间戳（UTC）：${ts}" \
    "- worktree 路径：${wt}" \
    "- 分支：${br}" \
    "" \
    "> 由 issue claim 自动组织。认领是跨会话尽力而为的信号、非硬锁；同机硬闸为 workspace start 的 riper/<N> 分支快失败。"
}

# ---------------------------------------------------------------------------
# 认领互斥：把「某 Issue 已被某会话认领」落到非排他的 riper-claimed 标签 + 审计评论。
# 用法：cmd_issue_claim <num> <claim|release|get>
#   get     —— 输出 claimed / unclaimed（廉价可靠读取，供自动挑选跳过判定；不限角色）。
#   claim   —— 已认领则回显既有认领并 exit 1（拒绝抢占，C7）；否则写标签 + 审计评论。
#   release —— 移除标签 + 释放评论；未认领时幂等只报告。
# 跨族安全：仅触碰 CLAIM_LABELS，绝不影响 p0~p3 / riper-* 状态 / riper-retry-*。
# 尽力而为：读后写非原子，真·同时竞态可能双双通过检查；同机硬闸是 workspace 分支快失败。
# ---------------------------------------------------------------------------
cmd_issue_claim() {
  local num="$1" action="$2"

  # 读当前是否已认领（大小写不敏感命中 riper-claimed）
  local claimed=0 lab lab_lc current
  if ! current="$(raw_issue_labels "${num}")"; then
    log_error "无法读取 Issue #${num} 的实际标签，不能确定认领状态。"
    return 1
  fi
  while IFS= read -r lab; do
    [[ -z "${lab}" ]] && continue
    lab_lc="$(printf '%s' "${lab}" | tr '[:upper:]' '[:lower:]')"
    [[ "${lab_lc}" == "riper-claimed" ]] && claimed=1
  done <<< "${current}"

  case "${action}" in
    get)
      check_permission claim-read
      if [[ "${claimed}" -eq 1 ]]; then printf '%s\n' "claimed"; else printf '%s\n' "unclaimed"; fi
      ;;
    claim)
      check_permission claim-write
      if [[ "${claimed}" -eq 1 ]]; then
        # C7：不抢占。回显既有认领信号，处置权交回人工/用户。
        log_error "Issue #${num} 已被认领（存在 riper-claimed 标签）——本脚本不会抢占。"
        log_error "请查看该 Issue 最近的认领评论确认持有者（会话/时间/worktree/分支）："
        log_error "  ./scripts/git-ops.sh issue get ${num}"
        log_error "陈旧认领的处置权属于用户；确认无主后再由人工执行 release。"
        exit 1
      fi
      raw_label_add "${num}" "riper-claimed"
      cmd_issue_comment "${num}" "$(claim_audit_body claim "${num}")"
      log_info "已认领 Issue #${num}（写入 riper-claimed 标签 + 审计评论）。"
      ;;
    release)
      check_permission claim-write
      if [[ "${claimed}" -eq 0 ]]; then
        log_info "Issue #${num} 未被认领，无需释放（幂等）。"
        return 0
      fi
      raw_label_remove "${num}" "riper-claimed"
      cmd_issue_comment "${num}" "$(claim_audit_body release "${num}")"
      log_info "已释放 Issue #${num} 的认领（移除 riper-claimed 标签 + 释放评论）。"
      ;;
    *)
      usage
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 创建 Issue：gh/glab 均支持 create；tea 优先 issue create，失败时回退 issues create
# ---------------------------------------------------------------------------
cmd_issue_create() {
  local title="$1" body="$2"
  # 平台检测失败时必须显式报错退出（命令替换的失败会被 case 吞掉）
  local __plat
  __plat="$(detect_platform)" || exit 1
  case "${__plat}" in
    gh)
      require_cli gh
      gh issue create --title "${title}" --body "${body}"
      ;;
    glab)
      require_cli glab
      glab issue create --title "${title}" --description "${body}"
      ;;
    tea)
      require_cli tea
      # tea 0.15.1：正文 flag 是 --description（--body 不存在；singular `tea issue` 组不存在）
      tea_cmd issues create --title "${title}" --description "${body}"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 关闭 Issue：gh/glab 均支持 close；tea 优先 issues close，失败时回退 issue close
# ---------------------------------------------------------------------------
cmd_issue_close() {
  local num="$1"

  # 权限硬校验：Developer 禁止关闭 Issue
  check_permission close

  # 平台检测失败时必须显式报错退出（命令替换的失败会被 case 吞掉）
  local __plat
  __plat="$(detect_platform)" || exit 1
  case "${__plat}" in
    gh)
      require_cli gh
      gh issue close "${num}"
      ;;
    glab)
      require_cli glab
      glab issue close "${num}"
      ;;
    tea)
      require_cli tea
      tea_cmd issues close "${num}" 2>/dev/null || tea_cmd issue close "${num}"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 重开 Issue：gh/glab 均支持 reopen；tea 优先 issues reopen，失败时回退 issue reopen
# ---------------------------------------------------------------------------
cmd_issue_reopen() {
  local num="$1"

  # 权限硬校验：Developer 禁止重开 Issue
  check_permission reopen

  # 平台检测失败时必须显式报错退出（命令替换的失败会被 case 吞掉）
  local __plat
  __plat="$(detect_platform)" || exit 1
  case "${__plat}" in
    gh)
      require_cli gh
      gh issue reopen "${num}"
      ;;
    glab)
      require_cli glab
      glab issue reopen "${num}"
      ;;
    tea)
      require_cli tea
      tea_cmd issues reopen "${num}" 2>/dev/null || tea_cmd issue reopen "${num}"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 标签体系初始化：幂等创建/更新全部 15 个内置标签（三互斥族 + 认领 riper-claimed）
# 新仓库首次使用本 Skill 前必须执行；否则 issue priority / status 会因
# 平台侧标签不存在而报 'p0' not found 并 exit 1（bootstrap 死锁）。
# ---------------------------------------------------------------------------
cmd_labels_init() {
  # 不限角色，但仍走一次校验以拦截非法角色名
  check_permission labels-init

  local l meta color desc result ok=0 fail=0 total=0

  for l in ${PRIORITY_LABELS} ${STATUS_LABELS} ${RETRY_LABELS} ${CLAIM_LABELS}; do
    total=$((total + 1))
    if ! meta="$(label_meta "${l}")"; then
      log_error "内部错误：标签 '${l}' 缺少元数据（label_meta 未覆盖）。"
      fail=$((fail + 1))
      continue
    fi
    color="${meta%% *}"
    desc="${meta#* }"
    if result="$(raw_label_create "${l}" "${color}" "${desc}")"; then
      printf '  %-8s %-18s #%s\n' "${result}" "${l}" "${color}"
      ok=$((ok + 1))
    else
      printf '  %-8s %-18s\n' "FAILED" "${l}"
      log_error "标签 '${l}' 创建/更新失败（检查 CLI 权限：GitHub 需 repo scope）。"
      fail=$((fail + 1))
    fi
  done

  if [[ "${fail}" -eq 0 ]] && ! normalize_repository_priority_labels; then
    fail=$((fail + 1))
  fi

  printf '\n'
  if [[ "${fail}" -eq 0 ]]; then
    log_info "标签体系就绪：${ok}/${total}（优先级 4 + 状态 7 + 重试 3 + 认领 1）。"
  else
    log_error "标签体系不完整：成功 ${ok}/${total}，失败 ${fail} 个。"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# 自检：平台路由 + CLI 安装 + 授权状态；未就绪时输出指南并 exit 1
# 建议在进入 RIPER 循环前先跑一次
# ---------------------------------------------------------------------------
cmd_doctor() {
  local os plat
  os="$(detect_os)"

  case "${os}" in
    macos)   log_info "运行环境：macOS" ;;
    windows) log_info "运行环境：Windows（Git Bash）" ;;
    *)
      log_error "运行环境不受支持（检测为：${os}）。本 Skill 仅支持 macOS 与 Windows（Git Bash）。"
      ;;
  esac

  # 平台检测（需在 git 仓库内）
  plat="$(detect_platform)" || exit 1
  log_info "根据 remote 路由到 CLI：${plat}"

  # 安装检查
  if ! command -v "${plat}" >/dev/null 2>&1; then
    log_error "未安装 ${plat}。"
    print_install_guide "${plat}"
    print_auth_guide "${plat}"
    exit 1
  fi
  log_info "${plat} 已安装：$(command -v "${plat}")"

  # 授权检查
  if ! check_auth "${plat}"; then
    log_error "${plat} 未授权（或授权已失效 / 网络不可达）。"
    print_auth_guide "${plat}"
    exit 1
  fi
  log_info "${plat} 授权正常，可以开始 RIPER 闭环。"

  # 标签体系就绪检查（缺标签必然导致 issue priority/status 报 'p0' not found 而闭环失败）
  local remote_labels
  if ! remote_labels="$(raw_label_names)"; then
    log_error "无法获取远端标签（网络或权限问题）——非「标签缺失」，请检查连通性与 ${plat} 授权后重试。"
    exit 1
  fi

  local want all="${PRIORITY_LABELS} ${STATUS_LABELS} ${RETRY_LABELS} ${CLAIM_LABELS}"
  local total=0 missing=""
  for want in ${all}; do
    total=$((total + 1))
    if ! printf '%s\n' "${remote_labels}" | grep -Fxq -- "${want}"; then
      missing="${missing}  - ${want}"$'\n'
    fi
  done

  if [[ -z "${missing}" ]]; then
    log_info "标签体系就绪：${total}/${total}（优先级 4 + 状态 7 + 重试 3 + 认领 1）。"
  else
    log_error "标签体系不完整，缺失以下标签："
    printf '%s' "${missing}" >&2
    log_error "请执行 ./scripts/git-ops.sh labels init 初始化后重试。"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# 可写区域越界自检（T0 铁律 1 的脚本化）：提交前必跑。
# 以 `git status --porcelain` 取全部变更（已暂存 + 未暂存 + 未跟踪；被 .gitignore
# 忽略的天然不列出），逐个比对 role_writable_paths / path_writable 白名单。
# 能力边界：只能校验「区域级越界」，无法校验「是否超出 plan 范围」（design 边界 4）。
# 用法：cmd_guard <role> [Issue 编号]
#   给出编号时额外校验当前分支是否为 riper/<该编号>；分支非 riper/* 形态只提示不失败。
# ---------------------------------------------------------------------------
cmd_guard() {
  local role="$1" num="${2:-}"

  # 校验目标角色合法性（非法角色 → exit 1）；guard 动作三角色均放行
  check_permission guard "${role}"
  role_writable_paths "${role}" >/dev/null

  # Issue 号一致性校验放在这里而非 check_permission：后者在 ROLE 为空（未带 --role）
  # 时会提前 return，校验不会执行，而 guard <role> <N> 必须无条件生效。
  if [[ -n "${num}" ]]; then
    if ! valid_issue_num "${num}"; then
      log_error "guard：Issue 编号必须是正整数（收到：'${num}'）。"
      _iloop_evt_mark "failed" "unknown" "" "none"
      exit 1
    fi
    local cur owner=""
    cur="$(current_branch)" || true
    if [[ -n "${cur}" ]]; then
      owner="$(issue_of_branch "${cur}")" || true
    fi
    if [[ -n "${owner}" ]]; then
      if [[ "${owner}" != "${num}" ]]; then
        printf '%s\n' '[iloop-feedback] rule=WORKSPACE-001 outcome=suspected' >&2
        log_error "guard：当前分支 ${cur} 属 Issue #${owner}，与给定的 Issue #${num} 不一致。"
        log_error "请切到 Issue #${num} 的工作区，或用正确编号：./scripts/git-ops.sh guard ${role} ${owner}"
        _iloop_evt_mark "failed" "WORKSPACE-001" "branch-mismatch" "none"
        exit 1
      fi
    else
      log_info "提示：当前工作区不在 ${BRANCH_PREFIX}/<N> 分支上（${cur:-detached HEAD}），跳过 Issue 号一致性校验。"
      log_info "      并行推进请先执行：./scripts/git-ops.sh workspace start ${num}"
    fi
  fi

  local changed
  changed="$(git status --porcelain)"
  if [[ -z "${changed}" ]]; then
    log_info "guard(${role}) 通过：无待检变更（工作区干净）。"
    _iloop_evt_mark "success" "unknown" "clean" "none"
    return 0
  fi

  # 并行污染诊断：只在主工作树出现。多会话共用同一个主工作树时，下列变更可能来自
  # 别的会话 / 别的 Issue，会被本自检当成本角色越界。纯提示，不影响判定与 exit code。
  if ! is_linked_worktree; then
    log_info "提示：当前在主工作树。若存在并行会话，下列变更可能不属于本角色 / 本 Issue，"
    log_info "      并会让本自检把无辜的并行判成越界。并行推进请先执行：./scripts/git-ops.sh workspace start <N>"
  fi

  local total=0 violated=0 line path violations=""
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    # porcelain 格式：XY<space>path；重命名为 "old -> new"，取新路径
    path="${line:3}"
    case "${path}" in
      *" -> "*) path="${path##* -> }" ;;
    esac
    path="${path%\"}"; path="${path#\"}"
    total=$((total + 1))
    if ! path_writable "${role}" "${path}"; then
      violated=$((violated + 1))
      violations="${violations}  - ${path}"$'\n'
    fi
  done <<EOF_STATUS
${changed}
EOF_STATUS

  if [[ "${violated}" -eq 0 ]]; then
    log_info "guard(${role}) 通过：${total} 个变更文件均在可写区域内。"
    _iloop_evt_mark "success" "unknown" "completed" "none"
    return 0
  fi

  printf '%s\n' '[iloop-feedback] rule=WORKSPACE-001 outcome=suspected' >&2
  log_error "guard(${role}) 失败：${violated}/${total} 个变更越界（T0 事故）。越界路径："
  printf '%s' "${violations}" >&2
  log_error "角色 ${role} 的可写区域："
  role_writable_paths "${role}" >&2
  _iloop_evt_mark "failed" "WORKSPACE-001" "violations" "none"
  exit 1
}

# ---------------------------------------------------------------------------
# 工作区隔离（git worktree / 分支）：多会话并行操作同一仓库时的物理隔离层
#
# 模型：一 Issue 一 worktree 一分支。分支名 riper/<N>（仅由 Issue 编号派生），
# 基分支恒为 origin/<默认分支>（不基于本地分支，避免携带他人未推送的提交），
# worktree 根在仓库外 ../.iloop-worktrees/<repo>/<N>（避免测试套件 glob/find
# 误扫其他会话的文件）。
#
# 只依赖 git 内建子命令，不依赖平台 CLI，故本段一律不调用 require_cli ——
# 无 CLI 授权的环境也能建工作区（与 doctor 的强授权要求解耦）。
# 属环境级操作（同 doctor / labels init / platform），不做角色门控；
# 但它不豁免 guard：guard 仍在提交前跑。
#
# 严禁破坏性命令：reset --hard / clean / checkout . / branch -D /
# worktree remove --force。有未提交改动或未合并提交时一律停下报告，不丢弃任何一方。
# ---------------------------------------------------------------------------

WORKTREE_ROOT_NAME=".iloop-worktrees"
BRANCH_PREFIX="riper"

repo_toplevel() {
  git rev-parse --show-toplevel
}

git_dir_abs() {
  git rev-parse --absolute-git-dir
}

# 主仓库的 git dir（绝对路径）。--git-common-dir 的输出可能相对 cwd，故用 cd+pwd
# 转绝对；不用 --path-format=absolute（需 git 2.31+，Apple git 未必满足）。
# 必须用 pwd -P（物理路径）：git rev-parse --absolute-git-dir 返回物理解析结果，
# 而裸 pwd 返回逻辑路径。macOS 上 /tmp -> /private/tmp 等符号链接会让两者字符串不等，
# 导致 is_linked_worktree 把主工作树误判为 linked。
git_common_dir_abs() {
  local d
  d="$(git rev-parse --git-common-dir)" || return 1
  ( cd "${d}" && pwd -P )
}

# 主工作树根 = common git dir 的父目录。
# lazy-ladder: 上限为标准布局 <root>/.git；GIT_DIR 被外部改写、submodule 或
#              worktree-of-worktree 等非标准布局会算错，届时改读 common dir 下的
#              worktrees 注册表。
primary_toplevel() {
  local gcd
  gcd="$(git_common_dir_abs)" || return 1
  dirname "${gcd}"
}

# 当前是否处于 linked worktree（而非主工作树）
is_linked_worktree() {
  local gd gcd
  gd="$(git_dir_abs)" || return 1
  gcd="$(git_common_dir_abs)" || return 1
  [[ "${gd}" != "${gcd}" ]]
}

# 当前分支名；detached HEAD 时返回非 0
current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null
}

# 默认分支（只读本地 ref，不联网）：origin/HEAD 由 git clone 设置
default_branch_local() {
  local ref
  ref="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" || return 1
  [[ -n "${ref}" ]] || return 1
  printf '%s\n' "${ref#origin/}"
}

# 默认分支（本地探测失败时联网问远端）。两者都失败返回非 0 —— 调用方必须停下报告，
# 绝不回退到本地分支（回退即违背「基于上游」的约定）。
default_branch() {
  local ref
  if ref="$(default_branch_local)"; then
    printf '%s\n' "${ref}"
    return 0
  fi
  ref="$(git remote show origin 2>/dev/null | sed -n 's/^[[:space:]]*HEAD branch: //p')" || return 1
  [[ -n "${ref}" ]] || return 1
  printf '%s\n' "${ref}"
}

# worktree 根：<主工作树父目录>/.iloop-worktrees/<repo>/<N>
# 基准必须是主工作树而非 cwd —— 否则在 linked worktree 内调用会算出错误路径。
wt_root() {
  local n="$1" primary
  primary="$(primary_toplevel)" || return 1
  printf '%s/%s/%s/%s\n' \
    "$(dirname "${primary}")" "${WORKTREE_ROOT_NAME}" "$(basename "${primary}")" "${n}"
}

# 从 riper/<N> 解析 Issue 号；非该形态返回非 0
issue_of_branch() {
  local b="$1"
  case "${b}" in
    "${BRANCH_PREFIX}"/*) printf '%s\n' "${b#"${BRANCH_PREFIX}"/}" ;;
    *)                    return 1 ;;
  esac
}

# Issue 编号必须是正整数（拒绝空串、非数字、0、负数、小数）
valid_issue_num() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0)           return 1 ;;
    *)           return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# workspace status：只读报告工作区隔离状态。不联网、无副作用。
# ---------------------------------------------------------------------------
cmd_workspace_status() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_error "当前不在 git 工作树内，无法判定工作区状态。"
    exit 1
  fi

  local top primary branch issue db counts dirty
  top="$(repo_toplevel)" || exit 1

  if is_linked_worktree; then
    log_info "工作区类型：linked worktree（已隔离）"
  else
    log_info "工作区类型：主工作树"
  fi
  log_info "当前工作树：${top}"

  if branch="$(current_branch)"; then
    log_info "当前分支：${branch}"
    if issue="$(issue_of_branch "${branch}")"; then
      log_info "归属 Issue：#${issue}"
    else
      log_info "归属 Issue：无（分支非 ${BRANCH_PREFIX}/<N> 形态）"
    fi
  else
    log_info "当前分支：无（detached HEAD @ $(git rev-parse --short HEAD)）"
    log_info "归属 Issue：无 —— detached HEAD 无分支身份，其改动无法合并 / 回滚 / 追溯。"
    log_info "修复方式：./scripts/git-ops.sh workspace start <N>（会挂上 ${BRANCH_PREFIX}/<N> 并保留现有提交）"
  fi

  if primary="$(primary_toplevel)"; then
    log_info "主工作树：${primary}"
    log_info "worktree 根：$(dirname "${primary}")/${WORKTREE_ROOT_NAME}/$(basename "${primary}")"
  fi

  if db="$(default_branch_local)" && git rev-parse --verify -q "origin/${db}" >/dev/null 2>&1; then
    log_info "基分支：origin/${db}"
    counts="$(git rev-list --left-right --count "origin/${db}...HEAD" 2>/dev/null)" || counts=""
    if [[ -n "${counts}" ]]; then
      log_info "相对基分支：落后 ${counts%%$'\t'*} / 领先 ${counts##*$'\t'}"
    fi
  else
    log_info "基分支：本地未能探测（origin/HEAD 缺失）；workspace start 会联网兜底，或用 --base <ref> 指定"
  fi

  dirty="$(git status --porcelain | grep -c . || true)"
  log_info "未提交变更文件数：${dirty}"

  log_info "worktree 清单："
  git worktree list | sed 's/^/[git-ops]   /'

  if ! is_linked_worktree && [[ "${dirty}" != "0" ]]; then
    log_info "注意：你在主工作树且有 ${dirty} 个未提交变更。若存在并行会话，这些变更可能不属于本角色 / 本 Issue，"
    log_info "      并会让 guard 把无辜的并行判成越界。并行推进请先执行：./scripts/git-ops.sh workspace start <N>"
  fi
}

# ---------------------------------------------------------------------------
# linked worktree 内的规范化（C11）：绝不新建 worktree，只把当前工作区挂到 riper/<N>
#
# 四态状态机：
#   已在 riper/<N>        → 幂等，报告就绪
#   在 riper/<M>（M≠N）   → 拒绝：工作区已属 Issue M，不得挪用
#   detached HEAD         → git switch -c riper/<N>，保留宿主已有提交，并声明基线非上游
#   其他分支（如 main）    → 拒绝且不切换：擅自 switch 会丢失该会话的上下文
#
# 失败一律 return 1（由调用方 exit），不在 helper 里直接退出。
# ---------------------------------------------------------------------------
normalize_linked_workspace() {
  local num="$1" branch="$2" cur sha db

  if cur="$(current_branch)"; then
    case "${cur}" in
      "${branch}")
        log_info "工作区已就绪（幂等）：Issue #${num}"
        log_info "  分支：${branch}（linked worktree，未做任何改动）"
        log_info "  路径：$(pwd -P)"
        return 0
        ;;
      "${BRANCH_PREFIX}"/*)
        log_error "当前工作区已属 Issue #${cur#"${BRANCH_PREFIX}"/}（分支 ${cur}），不得挪用于 Issue #${num}。"
        log_error "本脚本未做任何 git 写操作。请在主工作树为 Issue #${num} 另建工作区："
        log_error "  cd $(primary_toplevel) && ./scripts/git-ops.sh workspace start ${num}"
        return 1
        ;;
      *)
        log_error "当前工作区停在分支 ${cur}，不是 ${BRANCH_PREFIX}/<N> 形态。"
        log_error "本脚本不会擅自切换分支（会丢失该会话的上下文），未做任何 git 写操作。"
        return 1
        ;;
    esac
  fi

  # detached HEAD：宿主（如 codex / Qoder 的 worktree 隔离）建了工作区却没给分支身份。
  # 用 switch -c 就地挂分支，宿主已产生的提交全部保留在新分支上。
  sha="$(git rev-parse --short HEAD)"
  if git show-ref --verify --quiet "refs/heads/${branch}"; then
    log_error "分支 ${branch} 已存在，而当前工作区是 detached HEAD @ ${sha}。"
    log_error "本脚本不会自动删除或复用它。请人工确认后处置："
    log_error "  git worktree list           # 看它是否已绑定别的工作区"
    log_error "  git branch -d ${branch}     # 确认无用后再由你手工删除"
    return 1
  fi
  if ! git switch -c "${branch}"; then
    log_error "git switch -c ${branch} 失败。"
    return 1
  fi

  db="$(default_branch_local 2>/dev/null || printf '<未探测>')"
  log_info "工作区已规范化：Issue #${num}"
  log_info "  分支：${branch}（由 detached HEAD 就地挂载，原有提交全部保留）"
  log_info "  路径：$(pwd -P)"
  log_info "  基线：detached HEAD @ ${sha}，**不是** origin/${db}——"
  log_info "        宿主建工作区时可能已带入本地或他处提交，请自行确认基线是否符合预期。"
  return 0
}

# ---------------------------------------------------------------------------
# workspace start <N> [--base <ref>]：为 Issue N 建立隔离工作区
#
# 主工作树   → fetch 后基于 origin/<默认分支> 自建仓库外 worktree + riper/<N> 分支
# linked 树  → 不嵌套创建，只把当前工作区规范化到 riper/<N>（见 normalize_linked_workspace）
# 基分支恒为上游：绝不回退到本地分支，否则会携带他人未推送的提交。
# ---------------------------------------------------------------------------
cmd_workspace_start() {
  local num="" base=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base)
        if [[ $# -lt 2 ]]; then
          log_error "--base 需要一个 <ref> 参数。"
          exit 1
        fi
        base="$2"; shift 2
        ;;
      -*)
        log_error "workspace start：未知选项 '$1'（Issue 编号必须是正整数）。"
        exit 1
        ;;
      *)
        if [[ -z "${num}" ]]; then
          num="$1"; shift
        else
          log_error "workspace start：多余参数 '$1'。"
          exit 1
        fi
        ;;
    esac
  done

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_error "当前不在 git 工作树内，无法建立工作区。"
    exit 1
  fi
  if ! valid_issue_num "${num}"; then
    log_error "Issue 编号必须是正整数（收到：'${num:-<空>}'）。"
    exit 1
  fi

  local branch="${BRANCH_PREFIX}/${num}"

  # linked worktree 内绝不新建 worktree（C11 不嵌套）；必须先于「分支已存在」判断，
  # 否则幂等重入（已在 riper/<N>）会被那条快失败误伤。
  if is_linked_worktree; then
    normalize_linked_workspace "${num}" "${branch}" || exit 1
    return 0
  fi

  # 分支已存在 → 快失败。兼作本地互斥信号：该 Issue 可能已被另一会话认领。
  # 不自动删除或复用（A4 + 禁破坏性操作）。
  if git show-ref --verify --quiet "refs/heads/${branch}"; then
    log_error "分支 ${branch} 已存在——该 Issue 可能已被另一会话认领，或上次异常退出残留。"
    log_error "本脚本不会自动删除或复用它。请人工确认后处置："
    log_error "  git worktree list           # 看它是否已绑定工作区"
    log_error "  git branch -d ${branch}     # 确认无用后再由你手工删除"
    exit 1
  fi

  # --- 主工作树：基于上游自建 worktree ---
  local db base_ref wt abs

  # 路径冲突先于 fetch 检查：纯本地判断，避免为注定失败的调用打一次网络。
  if ! wt="$(wt_root "${num}")"; then
    log_error "无法计算 worktree 根路径（主工作树解析失败）。"
    exit 1
  fi
  if [[ -e "${wt}" ]]; then
    log_error "目标路径已存在：${wt}"
    log_error "本脚本不会覆盖或删除它。请人工确认其内容后处置。"
    exit 1
  fi

  if [[ -n "${base}" ]]; then
    if ! git rev-parse --verify -q "${base}" >/dev/null 2>&1; then
      log_error "--base 指定的 ref 不存在：'${base}'。"
      exit 1
    fi
    base_ref="${base}"
  else
    if ! db="$(default_branch)"; then
      log_error "无法探测默认分支（origin/HEAD 缺失，且 git remote show origin 失败）。"
      log_error "本脚本不会回退到本地分支——那会携带他人未推送的提交。"
      log_error "请显式指定基分支：./scripts/git-ops.sh workspace start ${num} --base <ref>"
      exit 1
    fi
    log_info "默认分支：${db}"
    if ! git fetch -q origin "${db}"; then
      log_error "git fetch origin ${db} 失败（网络不可达或权限不足）。"
      log_error "离线时请显式指定一个本地 ref：./scripts/git-ops.sh workspace start ${num} --base <ref>"
      exit 1
    fi
    base_ref="origin/${db}"
  fi

  # --no-track 为必需项：不加时 git 会把 riper/<N> 设为 tracking origin/<默认分支>，
  # 导致 push.default=simple 下的推送因分支名与上游名不一致而被拒。
  if ! git worktree add --no-track -b "${branch}" "${wt}" "${base_ref}"; then
    log_error "git worktree add 失败（基分支：${base_ref}）。"
    exit 1
  fi

  abs="$(cd "${wt}" && pwd -P)"
  log_info "工作区已建立：Issue #${num}"
  log_info "  分支：${branch}（基于 ${base_ref}，未设 upstream）"
  log_info "  路径：${abs}"
  log_info "后续所有仓库内命令必须以该绝对路径为 cwd——宿主可能在每次调用后重置 cwd，"
  log_info "故请用 'cd ${abs} && …' 前缀或工具的工作目录参数，不要假设 cwd 会延续。"
}

# 绑定到指定分支的 worktree 路径；没有绑定则输出空（返回 0）。
# porcelain 每个条目内 worktree 行先于 branch 行，故累积 path 再匹配即可。
worktree_of_branch() {
  local want="refs/heads/$1" path="" line
  while IFS= read -r line; do
    case "${line}" in
      "worktree "*) path="${line#worktree }" ;;
      "branch "*)
        if [[ "${line#branch }" == "${want}" ]]; then
          printf '%s\n' "${path}"
          return 0
        fi
        ;;
    esac
  done < <(git worktree list --porcelain)
  return 0
}

# ---------------------------------------------------------------------------
# workspace finish <N>：清理 Issue N 的本地工作区（A1：仅本地，不含推送 / PR / 合并）
#
# 顺序即安全闸门：定位 → 干净性 → 已合并进 origin/<默认分支> → 移除 worktree → 删分支。
# 任一闸门不过就停下报告，绝不丢弃任何一方（C3：不用 remove --force、不用 branch -D）。
#
# 已合并判定只读本地的 origin/<默认分支> 引用，不 fetch：远端刚合并而本地未 fetch 时
# 会判为「未合并」而拒绝——偏保守，且离线可用。
# 空的父目录 .iloop-worktrees/<repo> 保留，不递归删除（C3）。
# ---------------------------------------------------------------------------
cmd_workspace_finish() {
  local num="$1"
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_error "当前不在 git 工作树内，无法清理工作区。"
    exit 1
  fi
  if ! valid_issue_num "${num}"; then
    log_error "Issue 编号必须是正整数（收到：'${num:-<空>}'）。"
    exit 1
  fi

  local branch="${BRANCH_PREFIX}/${num}"
  if ! git show-ref --verify --quiet "refs/heads/${branch}"; then
    log_error "分支 ${branch} 不存在——Issue #${num} 没有可清理的本地工作区。"
    log_error "现有工作区："
    git worktree list | sed 's/^/  /' >&2
    exit 1
  fi

  # 分支可能没绑任何 worktree（例如上次创建中断的残留），此时跳过移除只删分支。
  local wt dirty db
  wt="$(worktree_of_branch "${branch}")"

  if [[ -n "${wt}" ]]; then
    dirty="$(git -C "${wt}" status --porcelain)"
    if [[ -n "${dirty}" ]]; then
      log_error "工作区有未提交改动，拒绝清理（不丢弃任何一方）：${wt}"
      printf '%s\n' "${dirty}" | sed 's/^/  /' >&2
      log_error "请先提交，或人工处置这些改动后重试。"
      exit 1
    fi
  fi

  if ! db="$(default_branch_local)"; then
    log_error "无法本地探测默认分支（origin/HEAD 缺失），无法确认 ${branch} 是否已合并。"
    log_error "无法确认时本脚本不会删除工作区。请先执行：git remote set-head origin -a"
    exit 1
  fi
  if ! git rev-parse --verify -q "refs/remotes/origin/${db}" >/dev/null 2>&1; then
    log_error "本地不存在 origin/${db} 引用，无法确认 ${branch} 是否已合并。"
    log_error "无法确认时本脚本不会删除工作区。请先执行：git fetch origin ${db}"
    exit 1
  fi
  git fetch origin "refs/heads/${db}:refs/remotes/origin/${db}" || { log_error "无法刷新上游，拒绝清理。"; exit 1; }
  if ! git merge-base --is-ancestor "${branch}" "origin/${db}"; then
    log_error "${branch} 尚未合并进 origin/${db}，拒绝清理（会丢失未集成的工作）。"
    log_error "请先完成集成（推送分支 + 开 PR + 合并，集成契约见 #25），再回来清理。"
    log_error "未合并的提交："
    git log --oneline "origin/${db}..${branch}" | sed 's/^/  /' >&2
    exit 1
  fi

  # 移除会让 cwd 消失（调用者可能正站在 ${wt} 里），紧随其后的 git 调用会因
  # "Unable to read current working directory" 失败，把命令打成「目录已删、分支还在」
  # 的半途状态。故在任何删除动作之前先把 cwd 挪到主工作树，建立「移除后 cwd 恒有效」的不变量。
  # 无条件执行：本来就在主工作树时 cd 幂等，比先判断 cwd 是否在 ${wt} 内更短、边界更少。
  local caller_cwd primary
  caller_cwd="$(pwd -P)"
  if ! primary="$(primary_toplevel)"; then
    log_error "无法解析主工作树路径；已在删除任何东西之前停下。"
    exit 1
  fi
  if ! cd "${primary}"; then
    log_error "无法进入主工作树 ${primary}；已在删除任何东西之前停下。"
    exit 1
  fi

  if [[ -n "${wt}" ]]; then
    if ! git worktree remove "${wt}"; then
      log_error "git worktree remove 失败：${wt}"
      exit 1
    fi
    log_info "已移除工作区：${wt}"
  else
    log_info "分支 ${branch} 未绑定任何 worktree（疑似上次创建中断的残留），跳过移除。"
  fi

  # advice.forceDeleteBranch=false：git 默认会在拒绝 -d 时附一句「run 'git branch -D …'」，
  # 那等于本工具在建议破坏性命令（C2/C3 禁止）。用 per-invocation 的 -c 关掉，不改用户配置；
  # 真实原因（error: … is not fully merged）仍然照常输出。老版本 git 无此 advice 键时无害。
  if ! git -c advice.forceDeleteBranch=false branch -d "${branch}"; then
    # 不猜测原因：走到这里时「已合并进 origin/<默认分支>」的闸门已经通过，
    # 失败原因只可能来自 git 自己的判定（HEAD 不含它且无 upstream、被别的 worktree 占用等），
    # git 的 stderr 未重定向、已直接可见，叠加一句硬编码归因只会把人引向错方向。
    log_error "git branch -d ${branch} 失败，原因见 git 在上面给出的输出。"
    log_error "此时工作区目录已移除、分支 ${branch} 仍在，处于半途状态。"
    log_error "请按 git 的原因人工处置后补删分支：git branch -d ${branch}"
    exit 1
  fi
  log_info "已删除分支：${branch}"
  log_info "Issue #${num} 的本地工作区清理完毕；空的父目录按约定保留。"

  # 只在调用者真的站在被删目录里时才提示，避免对从主工作树调用的正常情况制造噪音。
  if [[ -n "${wt}" ]]; then
    case "${caller_cwd}" in
      "${wt}"|"${wt}"/*)
        log_info "注意：你调用时所在的目录已随工作区一并删除，请切回主工作树：cd ${primary}"
        ;;
    esac
  fi
}

# ---------------------------------------------------------------------------
# 参数路由（主入口）
# ---------------------------------------------------------------------------
main() {
  # 解析全局选项 --role <planner|developer|reviewer>（优先于环境变量 GIT_OPS_ROLE）
  if [[ "${1:-}" == "--role" ]]; then
    [[ $# -ge 2 ]] || usage
    ROLE="$2"
    shift 2
  fi

  if [[ $# -lt 1 ]]; then
    usage
  fi

  local cmd="$1"
  shift

  case "${cmd}" in
    integration)
      source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/integration.sh"
      cmd_integration "$@"
      ;;
    platform)
      [[ $# -eq 0 ]] || usage
      # 平台检测失败时必须显式报错退出（命令替换的失败会被 case / 子 shell 吞掉）
      local plat
      plat="$(detect_platform)" || exit 1
      log_info "检测到平台 CLI：${plat}"
      printf '%s\n' "${plat}"
      ;;
    labels)
      # 仓库级标签体系初始化：仅接受 `labels init`
      if [[ $# -ne 1 || "$1" != "init" ]]; then
        usage
      fi
      cmd_labels_init
      ;;
    doctor)
      [[ $# -eq 0 ]] || usage
      cmd_doctor
      ;;
    guard)
      # 第二参数（Issue 编号）可选；超出 2 个走 usage
      [[ $# -ge 1 && $# -le 2 ]] || usage
      _iloop_evt_arm "guard" "${2:-}"
      cmd_guard "$@"
      ;;
    workspace)
      # 工作区隔离（环境级操作，不限角色）。子命令各自的参数校验在其分支内完成。
      if [[ $# -lt 1 ]]; then
        usage
      fi
      local wsub="$1"
      shift
      case "${wsub}" in
        status)
          [[ $# -eq 0 ]] || usage
          cmd_workspace_status
          ;;
        start)
          # 编号与 --base 的校验在 cmd_workspace_start 内完成（需要给出精确错误文案）
          [[ $# -ge 1 ]] || usage
          cmd_workspace_start "$@"
          ;;
        finish)
          [[ $# -eq 1 ]] || usage
          cmd_workspace_finish "$1"
          ;;
        *)
          usage
          ;;
      esac
      ;;
    issue)
      # list 子命令的参数全为可选，故守卫放宽为 `$# -lt 1`（裸 `issue` 仍报 usage）；
      # 其余子命令在各自分支内做 `[[ $# -eq N ]] || usage` 精确校验，不受影响。
      if [[ $# -lt 1 ]]; then
        usage
      fi
      local sub="$1"
      shift
      case "${sub}" in
        list)
          cmd_issue_list "$@"
          ;;
        get)
          [[ $# -eq 1 || ( $# -eq 2 && "$2" == "--strict" ) ]] || usage
          cmd_issue_get "$@"
          ;;
        comment)
          [[ $# -eq 2 ]] || usage
          _iloop_evt_arm "issue.comment" "$1"
          cmd_issue_comment "$1" "$2"
          ;;
        label)
          [[ $# -eq 3 ]] || usage
          case "$2" in
            add|remove) ;;
            *) usage ;;
          esac
          cmd_issue_label "$1" "$2" "$3"
          ;;
        priority)
          [[ $# -eq 2 ]] || usage
          _iloop_evt_arm "issue.priority" "$1"
          cmd_issue_priority "$1" "$2"
          ;;
        status)
          [[ $# -eq 2 ]] || usage
          _iloop_evt_arm "issue.status" "$1"
          cmd_issue_status "$1" "$2"
          ;;
        retry)
          [[ $# -eq 2 ]] || usage
          case "$2" in
            incr|get|reset) ;;
            *) usage ;;
          esac
          cmd_issue_retry "$1" "$2"
          ;;
        claim)
          [[ $# -eq 2 ]] || usage
          case "$2" in
            claim|release|get) ;;
            *) usage ;;
          esac
          cmd_issue_claim "$1" "$2"
          ;;
        create)
          [[ $# -eq 2 ]] || usage
          cmd_issue_create "$1" "$2"
          ;;
        close)
          [[ $# -eq 1 ]] || usage
          cmd_issue_close "$1"
          ;;
        reopen)
          [[ $# -eq 1 ]] || usage
          cmd_issue_reopen "$1"
          ;;
        *)
          usage
          ;;
      esac
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      log_error "未知命令：${cmd}"
      usage
      ;;
  esac
}

main "$@"
