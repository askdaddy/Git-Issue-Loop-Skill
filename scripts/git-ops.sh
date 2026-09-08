#!/usr/bin/env bash
# ============================================================================
# git-ops.sh —— 跨平台 Git Issue CLI 封装（GitHub / GitLab / Gitea / Forgejo）
#
# 适用环境（仅支持以下两个平台）：
#   - macOS（zsh / bash 均可执行本脚本）
#   - Windows（需在 Git Bash 中运行，随 Git for Windows 自带；
#     不支持在 CMD / PowerShell 直接运行）
#
# 通过 `git remote -v` 自动检测托管平台，路由到对应 CLI：
#   - github.com            -> gh
#   - gitlab.com / 自建GitLab -> glab（需 glab 已登录对应实例）
#   - gitea / forgejo       -> tea
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

usage() {
  cat <<'EOF'
Usage:
  git-ops.sh [--role <planner|developer|reviewer>] <command> ...

  角色用于 Issue 操作权限硬校验（也可用环境变量 GIT_OPS_ROLE 指定）：
    close / reopen 仅 planner / reviewer 可用，Developer 直接拒绝；
    priority 仅 planner 可设；status 按角色白名单校验。

Commands:
  git-ops.sh issue get <num>                       获取 Issue 详情（含正文与评论）
  git-ops.sh issue comment <num> "<content>"       给 Issue 添加评论
  git-ops.sh issue create "<title>" "<body>"       创建新 Issue
  git-ops.sh issue close <num>                     关闭 Issue
  git-ops.sh issue reopen <num>                    重新打开 Issue
  git-ops.sh issue priority <num> <p0|p1|p2|p3>    设置优先级（艾森豪威尔矩阵，排他）
  git-ops.sh issue status <num> <riper-*>          切换 RIPER 状态（排他）
  git-ops.sh issue label <num> add <label>         添加自由标签（上下文召回用）
  git-ops.sh issue label <num> remove <label>      移除自由标签
  git-ops.sh platform                               打印检测到的托管平台
  git-ops.sh doctor                                 自检：CLI 安装与授权状态（缺失时输出指南）
EOF
  exit 1
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
    *)
      # 无法从主机名识别时按已安装 CLI 依次兜底
      if command -v gh >/dev/null 2>&1; then
        log_info "无法从 remote host '${host}' 识别平台，回退到 gh。"
        echo "gh"
      elif command -v glab >/dev/null 2>&1; then
        log_info "无法从 remote host '${host}' 识别平台，回退到 glab。"
        echo "glab"
      elif command -v tea >/dev/null 2>&1; then
        log_info "无法从 remote host '${host}' 识别平台，回退到 tea。"
        echo "tea"
      else
        log_error "无法识别 '${host}' 对应的 CLI（gh / glab / tea 均未安装）。"
        exit 1
      fi
      ;;
  esac
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
    # tea 无 auth status：以 login list 是否列出实例 URL 判断
    tea)  tea login list 2>/dev/null | grep -qi 'http' ;;
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
#   - create / comment / get 不限角色。
# ---------------------------------------------------------------------------
ROLE="${GIT_OPS_ROLE:-}"

# 互斥标签族定义（同时只能存在一个）
# 优先级：艾森豪威尔矩阵 p0=重要且紧急 p1=重要不紧急 p2=紧急不重要 p3=不重要不紧急
PRIORITY_LABELS="p0 p1 p2 p3"
# 状态：RIPER 各阶段 + 终态
STATUS_LABELS="riper-research riper-innovation riper-plan riper-execute riper-review riper-verified riper-blocked"

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
      tea issues "${num}" --comments
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
      tea issues "${num}" --comment "${content}"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 标签底层操作（各平台原生命令）
# ---------------------------------------------------------------------------

# 给 Issue 添加标签
raw_label_add() {
  local num="$1" label="$2"
  local __plat
  __plat="$(detect_platform)" || exit 1
  case "${__plat}" in
    gh)
      require_cli gh
      gh issue edit "${num}" --add-label "${label}"
      ;;
    glab)
      require_cli glab
      glab issue update "${num}" --label "${label}" 2>/dev/null \
        || glab issue label "${num}" "${label}" # 新旧版本 glab 兼容
      ;;
    tea)
      require_cli tea
      tea labels add "${label}" 2>/dev/null || true # 标签名不存在时先创建（可失败，忽略）
      tea issues "${num}" --label "${label}"
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
      gh issue edit "${num}" --remove-label "${label}" 2>/dev/null \
        || log_info "标签 '${label}' 已不存在或已移除。"
      ;;
    glab)
      require_cli glab
      # glab 移除标签：先取现有标签，剔除目标后整体覆盖
      local current
      current="$(glab issue view "${num}" 2>/dev/null \
                 | sed -n 's/^Labels:[[:space:]]*//p' \
                 | tr ',' '\n' | sed 's/^ *//;s/ *$//' \
                 | grep -vix "${label}" | paste -sd, -)"
      if [[ -z "${current}" ]]; then
        glab issue update "${num}" --remove-label "${label}" 2>/dev/null \
          || log_info "标签 '${label}' 已不存在或已移除。"
      else
        glab issue update "${num}" --label "${current}"
      fi
      ;;
    tea)
      require_cli tea
      tea issues "${num}" --unlabel "${label}" 2>/dev/null \
        || log_info "标签 '${label}' 已不存在或已移除。"
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
      tea issue create --title "${title}" --body "${body}" 2>/dev/null \
        || tea issues create --title "${title}" --body "${body}"
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
      tea issues close "${num}" 2>/dev/null || tea issue close "${num}"
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
      tea issues reopen "${num}" 2>/dev/null || tea issue reopen "${num}"
      ;;
  esac
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
    doctor)
      [[ $# -eq 0 ]] || usage
      cmd_doctor
      ;;
    issue)
      if [[ $# -lt 2 ]]; then
        usage
      fi
      local sub="$1"
      shift
      case "${sub}" in
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
