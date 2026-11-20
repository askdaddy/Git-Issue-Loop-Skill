# 项目文档导航与维护

本项目由 Skill 指令、角色协议、模板与 Bash CLI 包装器组成；没有 Node 构建步骤。稳定版本见根目录 [README](../README_CN.md) 与 [CHANGELOG](../CHANGELOG.md)，开发中的文档调整不等于已发布或已同步到用户安装。

## 当前资料

| 内容 | 拥有该规则的文档或实现 |
|---|---|
| 项目介绍与快速开始 | [English](../README.md)、[简体中文](../README_CN.md) |
| RIPER、角色权限与恢复 | [SKILL.md](../SKILL.md)、[角色文件](../roles/) |
| 安装、备份、更新与回滚 | [INSTALL.md](../INSTALL.md)、[skill-manifest.json](../skill-manifest.json) |
| CLI 安装、授权与标签初始化 | [CLI 指南](../references/cli-setup.md) |
| 平台路由、标签、Issue 与 guard 的实际行为 | [git-ops.sh](../scripts/git-ops.sh) |
| 第三方报告与外部贡献 | [Issue 接入](../references/issue-intake.md)、[贡献接入](../references/contribution-intake.md) |
| 阶段思考方法与显式点名 | [思考方法](../references/thinking-methods.md)、[阶段模板](../templates/) |
| 最少代码原则 | [实现梯子](../references/lazy-ladder.md) |
| PR 交付与版本发布 | [集成契约](../references/integration.md)、[integration.sh](../scripts/integration.sh) |
| 运行时事件、离线草稿与全局纠错队列 | [输出契约](../references/runtime-output.md)、[反馈协议](../references/feedback-loop.md)、[feedback.sh](../scripts/feedback.sh) |
| 阶段产物格式 | [templates/](../templates/) |
| 回归套件与人工协议场景 | [test/](../test/) |

脚本检查只覆盖实现中的权限、路径和命令条件，不证明阶段材料的语义质量。文档声明与实现有偏差时应记录差异并修复，不能用历史验收记录替代当前验证。

## 本地维护检查

在仓库根目录用 Bash 执行：

```bash
# 检查补丁中的空白问题
git diff --check

# 语法检查，不触发远端写入
for script in scripts/*.sh test/*.sh; do
  bash -n "$script" || exit 1
done

# 全部 shell 回归套件；失败即停
for suite in test/*-invariants.sh; do
  bash "$suite" || exit 1
done
```

测试中的 CLI 使用临时仓库和 stub；它们不能证明真实 GitLab / tea 的所有版本均兼容，也不等同于独立 Agent 端到端验收。`test/*.md` 是人工场景，不由上述 shell 循环执行。发布前按[集成契约](../references/integration.md#稳定发布tag-与-github-release-缺一不可)在最终提交上运行全部 shell 测试，核对版本清单、中英文 README 与 CHANGELOG；不修改既有稳定 tag。

文档对齐时，分别核对以下来源：

- README 的稳定版链接：远端最高稳定 tag 与对应 Release；manifest 的版本字段不等于当前安装版本。
- 中英文 README 的测试数量：`test/*-invariants.sh` 的实际文件数；历史 CHANGELOG / 验收报告保留当时的数量。
- 功能介绍、命令入口与目录说明：当前 SKILL、脚本与 references，尤其是阶段思考方法、全局反馈队列和自由标签补建。
- 本地 Markdown 链接与锚点：目标文件和标题存在；历史材料中的旧引用按历史背景解释。

只对齐文档时不必递增版本、移动稳定 tag 或更新本机安装；相关变更随后续明确授权的版本发布分发。

`doctor` 与 `labels init` 面向当前目标仓库的远端，后者会写标签，不属于纯本地卫生检查。doctor 仅检查名称齐全，不能证明标签颜色、描述或更新权限可用。

## 历史材料与仓库卫生

[Issue #1](https://github.com/askdaddy/Git-Issue-Loop-Skill/issues/1) 的 [spec](issues/1/spec.md)、[design](issues/1/design.md)、[plan](issues/1/plan.md) 是早期自举留下的历史记录。保留其当时的行号、14 标签方案、设计备选和验收叙述用于追溯，不把它们改写成当前的 15 标签实现，也不据此推断 Issue 当前状态。

新增阶段文档仍遵循 SKILL.md：远端 Issue 是唯一事实来源，仅在远端不可用时降级写 `docs/issues/<N>/`，恢复后引用本地证据。历史文件的留存不授权新的双写副本。

`test/` 与历史文档是受版本控制的项目资料。临时仓库、测试日志、凭据和安装备份不应混入提交；`.gitignore` 仅屏蔽常见本地产物。安装 staging 位于系统临时目录，旧安装备份位于 `~/.agents/backups/`，均不放入仓库或 Skills 扫描目录。全局纠错队列位于 `~/.agents/iloop-feedback/`，同样是仓库外用户数据，不作为临时文件清理。清理历史证据、分支或 worktree 前须核对归属与交付状态，不批量删除。
