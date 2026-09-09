# Git Issue Loop Skill

[简体中文](README_CN.md)

`iloop` is an Agent Skill for running an issue-driven RIPER engineering loop:
**Research → Innovation → Plan → Execute → Review**. It treats the Git Issue
body, comments, and labels as the source of truth, while keeping local Markdown
documents as durable working copies and fallbacks.

The Skill works with GitHub, GitLab, Gitea, and Forgejo through their official
CLIs: `gh`, `glab`, and `tea`.

## What it provides

- A `/iloop` entry point for a complete RIPER loop, planning-only work, review,
  or environment diagnostics.
- Strict role separation: Planner owns specification and planning, Developer
  implements the approved plan, and Reviewer performs black-box acceptance.
- Spec-driven delivery: the plan is a frozen contract and changes to it require
  an explicit return to the planning stage.
- Exclusive Issue-label families for priority (`p0`–`p3`) and RIPER status.
- `scripts/git-ops.sh`, which detects the hosting platform from `git remote`,
  routes to the official CLI, and checks role permissions.

## Install the latest stable release

Give a Git-capable Agent this single instruction:

> Install the latest `iloop` Skill from `https://github.com/askdaddy/Git-Issue-Loop-Skill.git` into `~/.agent/skills/iloop`. Safely update an existing installation only when it is from the same repository and has no local changes; otherwise stop and report the conflict. Verify `SKILL.md` after installation.

“Latest” means the highest stable `vX.Y.Z` Git tag. It never means tracking
`main` or installing an alpha, beta, or release candidate. The Agent should
report the resolved tag and commit SHA after a successful installation.

The full staging, validation, backup, update, and rollback protocol is in
[INSTALL.md](INSTALL.md). Its machine-readable counterpart is
[skill-manifest.json](skill-manifest.json).

> A stable `vX.Y.Z` tag must be published before latest-release installation is
> available. A compliant Agent fails closed when no stable tag exists; it must
> not fall back to `main`.

## Get started

1. Refresh the Agent host so that it discovers `~/.agent/skills/iloop`.
2. Open the target Git repository and run the environment check from that
   repository root:

   ```bash
   ~/.agent/skills/iloop/scripts/git-ops.sh doctor
   ```

3. Complete any reported CLI installation or authentication step yourself; do
   not put tokens in the repository or ask an Agent to enter credentials.
4. Start the workflow with `/iloop`, or ask the Agent to plan or review an
   issue.

For an initial label setup in a repository, run:

```bash
~/.agent/skills/iloop/scripts/git-ops.sh labels init
```

## Requirements

- Git and an Agent host that loads Skills from `~/.agent/skills/`.
- macOS, or Windows running the supplied shell script from Git Bash. Linux is
  not currently a supported runtime target.
- The official Issue CLI for the target remote: `gh` for GitHub, `glab` for
  GitLab, or `tea` for Gitea and Forgejo.
- An authenticated CLI account with permission to read and write Issues and
  labels.

See [references/cli-setup.md](references/cli-setup.md) for platform-specific
installation and authentication guidance.

## Project layout

```text
SKILL.md                 Skill contract and RIPER workflow
INSTALL.md               Agent-managed Git installation protocol
skill-manifest.json      Machine-readable installation contract
scripts/git-ops.sh       Platform routing, Issue operations, and safeguards
roles/                   Planner, Developer, and Reviewer role instructions
templates/               Spec, design, plan, and verification-report templates
references/              CLI setup guidance
```

## Stable releases

`main` is the development branch. Each stable release must use a new immutable
`vX.Y.Z` tag and should have a matching GitHub Release containing its change
notes. Pre-release tags use a SemVer suffix such as `-beta.1` and are skipped by
the default installer.

For the normative workflow rules, see [SKILL.md](SKILL.md). For the Chinese
version of this introduction, see [README_CN.md](README_CN.md).
