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
#   ./git-ops.sh issue get <num>
#   ./git-ops.sh issue comment <num> "<content>"
#   ./git-ops.sh issue create "<title>" "<body>"
#   ./git-ops.sh issue close <num>
#   ./git-ops.sh issue reopen <num>
#   ./git-ops.sh issue priority <num> <p0|p1|p2|p3>     # 排他：同时只保留一个优先级
#   ./git-ops.sh issue status <num> <riper-*>           # 排他：同时只保留一个 RIPER 状态
#   ./git-ops.sh issue label <num> add <label>          # 自由标签（上下文召回用）
#   ./git-ops.sh issue label <num> remove <label>
#   ./git-ops.sh platform                               # 仅打印检测到的平台
#   ./git-ops.sh doctor                                 # 自检：CLI 是否安装 + 是否已授权
#
# CLI 优先原则：
#   Issue 操作一律优先使用本地官方 CLI（GitHub->gh，GitLab->glab，Gitea/Forgejo->tea）。
#   本地缺 CLI 或未授权时，本脚本不会静默失败也不会改走其他途径，
#   而是输出对应平台的安装 + 授权指南并以 exit 1 中止，由 Agent 转交给用户处理。
#   完整指南见 references/cli-setup.md。
#
# 标签族（互斥，由脚本强制排他）：
#   - 优先级 p0~p3，按艾森豪威尔矩阵定义：
#       p0 = 重要且紧急    p1 = 重要不紧急
#       p2 = 紧急不重要    p3 = 不重要不紧急
#     优先级只能用平台 label 能力表达，禁止写进 Issue 标题。
#   - 状态 riper-research / riper-innovation / riper-plan / riper-execute /
#     riper-review / riper-verified / riper-blocked（描述 RIPER 各阶段，同时只能一个）
#   - 其他标签由 Agent 自定义，便于上下文召回（如 module/xxx、type/bug）
#
# 权限硬校验（--role，也可用环境变量 GIT_OPS_ROLE 指定）：
#   - close / reopen 仅 planner / reviewer 可用，Developer 调用直接拒绝；
#   - priority 仅 planner 可设置；
#   - status 按角色白名单：
#       planner   riper-research / riper-innovation / riper-plan
#       developer riper-execute / riper-review / riper-blocked
#       reviewer  riper-plan（FAIL 退回） / riper-verified / riper-blocked
#   - label add/remove 不限角色，但禁止操作上述两个互斥标签族（须用专用子命令）；
#   - 未指定 --role 时仅打印警告并放行（便于人工直接调用）。
# ============================================================================

set -euo pipefail

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
  git-ops.sh issue get <num>                       获取 Issue 详情（含正文与评论）
  git-ops.sh issue comment <num> "<content>"       给 Issue 添加评论
  git-ops.sh issue create "<title>" "<body>"       创建新 Issue
  git-ops.sh issue close <num>                     关闭 Issue
  git-ops.sh issue reopen <num>                    重新打开 Issue
  git-ops.sh issue priority <num> <p0|p1|p2|p3>    设置优先级（艾森豪威尔矩阵，排他）
  git-ops.sh issue status <num> <riper-*>          切换 RIPER 状态（排他）
  git-ops.sh issue label <num> add <label>         添加自由标签（上下文召回用）
  git-ops.sh issue label <num> remove <label>      移除自由标签
  git-ops.sh labels init                            初始化标签体系（4 优先级 + 7 状态 + 3 重试，幂等）
  git-ops.sh platform                               打印检测到的托管平台
  git-ops.sh doctor                                 自检：CLI 安装与授权状态（缺失时输出指南）
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
  if command -v tea >/dev/null 2>&1 && tea login list 2>/dev/null | grep -Fq -- "${host}"; then
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
# 重试计数：QA 审查 FAIL 退回计划的次数（第四族，同样排他；达 3 次后须转 riper-blocked）
# 存于 Issue 标签而非本地文件，以保证跨会话 / 跨机器 / 跨 agent 可见（Issue 为唯一事实来源）
RETRY_LABELS="riper-retry-1 riper-retry-2 riper-retry-3"

# 标签元数据：输出「颜色 描述」，颜色为 6 位 hex（不带 #），供 labels init 建标签时使用。
# 覆盖四族全部 14 个标签（4 优先级 + 7 状态 + 3 重试）；未知标签返回非 0。
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

# 校验操作权限；越权直接报错退出
# 用法：check_permission <close|reopen|priority|status|label-add|label-remove> [值]
check_permission() {
  local action="$1" value="${2:-}"

  # 未指定角色：警告后放行（人工直接调用场景）
  if [[ -z "${ROLE}" ]]; then
    log_info "未指定 --role，跳过权限硬校验（Agent 调用时建议携带 --role）。"
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
        log_error "权限拒绝：Developer 禁止 ${action} Issue（执行者无权自我判定完成）。"
        exit 1
      fi
      ;;
    priority)
      if [[ "${ROLE}" != "planner" ]]; then
        log_error "权限拒绝：优先级仅 PM（planner）可在研究阶段判定设置。"
        exit 1
      fi
      if ! is_priority_label "${value}"; then
        log_error "非法优先级：'${value}'（合法值：${PRIORITY_LABELS}，艾森豪威尔矩阵）。"
        exit 1
      fi
      ;;
    status)
      if ! is_status_label "${value}"; then
        log_error "非法状态：'${value}'（合法值：${STATUS_LABELS}）。"
        exit 1
      fi
      if ! status_allowed "${ROLE}" "${value}"; then
        log_error "权限拒绝：角色 ${ROLE} 无权将状态切换为 '${value}'。"
        exit 1
      fi
      ;;
    label-add|label-remove)
      # 互斥标签族必须走专用子命令，否则无法保证排他性
      if is_priority_label "${value}" || is_status_label "${value}"; then
        log_error "标签 '${value}' 属于互斥标签族，请改用 'issue priority' / 'issue status' 子命令（保证排他性）。"
        exit 1
      fi
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

# 获取 Issue 详情：gh/glab/tea 均支持 `issue view <num> --comments`
cmd_issue_get() {
  local num="$1"
  # 平台检测失败时必须显式报错退出（命令替换的失败会被 case 吞掉）
  local __plat
  __plat="$(detect_platform)" || exit 1
  case "${__plat}" in
    gh)
      require_cli gh
      gh issue view "${num}" --comments
      ;;
    glab)
      require_cli glab
      glab issue view "${num}" --comments
      ;;
    tea)
      require_cli tea
      tea_cmd issues "${num}" --comments
      ;;
  esac
}

# 添加评论：gh/glab 支持 `issue comment <num> -b/--body`；tea 使用 issues 命令组
cmd_issue_comment() {
  local num="$1" content="$2"
  # 平台检测失败时必须显式报错退出（命令替换的失败会被 case 吞掉）
  local __plat
  __plat="$(detect_platform)" || exit 1
  case "${__plat}" in
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

  check_permission priority "${priority}"

  # 排他性保证：同族其他优先级标签一律移除（不存在时忽略）
  local l
  for l in ${PRIORITY_LABELS}; do
    if [[ "${l}" == "${priority}" ]]; then
      continue
    fi
    raw_label_remove "${num}" "${l}" || true
  done
  raw_label_add "${num}" "${priority}"
  log_info "优先级已设为 ${priority}（艾森豪威尔矩阵，同族标签已排他清理）。"
}

# ---------------------------------------------------------------------------
# RIPER 状态切换：排他——先移除同族其他状态再写入
# ---------------------------------------------------------------------------
cmd_issue_status() {
  local num="$1" status="$2"

  check_permission status "${status}"

  local l
  for l in ${STATUS_LABELS}; do
    if [[ "${l}" == "${status}" ]]; then
      continue
    fi
    raw_label_remove "${num}" "${l}" || true
  done
  raw_label_add "${num}" "${status}"
  log_info "状态已切换为 ${status}（同族状态标签已排他清理）。"
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
# 标签体系初始化：幂等创建/更新四族全部 14 个标签
# 新仓库首次使用本 Skill 前必须执行；否则 issue priority / status 会因
# 平台侧标签不存在而报 'p0' not found 并 exit 1（bootstrap 死锁）。
# ---------------------------------------------------------------------------
cmd_labels_init() {
  # 不限角色，但仍走一次校验以拦截非法角色名
  check_permission labels-init

  local l meta color desc result ok=0 fail=0 total=0

  for l in ${PRIORITY_LABELS} ${STATUS_LABELS} ${RETRY_LABELS}; do
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

  printf '\n'
  if [[ "${fail}" -eq 0 ]]; then
    log_info "标签体系就绪：${ok}/${total}（优先级 4 + 状态 7 + 重试 3）。"
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
          [[ $# -eq 1 ]] || usage
          cmd_issue_get "$1"
          ;;
        comment)
          [[ $# -eq 2 ]] || usage
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
          cmd_issue_priority "$1" "$2"
          ;;
        status)
          [[ $# -eq 2 ]] || usage
          cmd_issue_status "$1" "$2"
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
