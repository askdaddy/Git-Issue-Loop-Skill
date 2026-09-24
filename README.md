# Git Issue Loop Skill

[简体中文](README_CN.md)

`iloop` is an Agent Skill for running an issue-driven RIPER engineering loop:
**Goal registration → Research → Innovation → Plan → Execute → Review**. A plain
goal works too: the Planner drafts, confirms, and files it as an issue before the
loop starts (goal bootstrap). It treats the Git Issue
body, comments, and labels as the source of truth; local Markdown documents in
`docs/issues/<N>/` are used only as a degraded fallback when the remote Issue
platform is unavailable, never as redundant duplicates.

The Skill works with GitHub, GitLab, Gitea, and Forgejo through their official
CLIs: `gh`, `glab`, and `tea`.

## What it provides

- A `/iloop` entry point for a complete RIPER loop, planning-only work, review,
  environment diagnostics, or `help` (usage plus the locally installed version).
- Auto-pick on a bare `/iloop`: scans open issues read-only, orders them
  `p0`→`p3` then by ascending number, skips blocked / retry-capped /
  verified-but-open ones, and reports the candidate list with its reasoning and
  skipped items. It waits for your confirmation before loading any role, and
  handles exactly one issue per invocation.
- Stage-aware dispatch: a numbered issue loads the matching frame-0 role from
  its RIPER status (and artifacts), instead of always starting at Research.
- On start, compare the installed Skill against the highest stable git tag and
  ask before upgrading; never switch installs unattended.
- Goal bootstrap: hand `/iloop` a plain goal instead of an issue number, and
  the Planner drafts it, confirms with you, files the issue, and enters the
  loop via dispatch (a newly created issue lands in Research).
- Strict role separation: Planner owns specification and planning, Developer
  implements the approved plan, and Reviewer performs black-box acceptance.
- Spec-driven delivery: the plan is a frozen contract and changes to it require
  an explicit return to the planning stage.
- A minimum-code ladder (`references/lazy-ladder.md`) constraining HOW: take the
  shortest diff that still meets the frozen acceptance criteria, and leave a
  one-line `skipped:` comment for any legitimate detour.
- Three exclusive Issue-label families — priority (`p0`–`p3`), RIPER status, and
  retry count (`riper-retry-1`–`3`) — totalling 14 built-in labels that
  `labels init` creates idempotently.
- Hard T0 boundaries: the Planner and Reviewer may not touch business code, and
  `guard <role>` verifies the writable area against `git status` before a commit.
- `scripts/git-ops.sh`, which detects the hosting platform from `git remote`,
  routes to the official CLI, enforces per-role Issue permissions, and refuses to
  fall back to REST APIs or hand-entered credentials.
- 12 black-box invariant suites under `test/` that drive stub `gh` / `glab` /
  `tea` binaries in throwaway repositories.

## Install the latest stable release

Give a Git-capable Agent this single instruction:

> Install the latest `iloop` Skill from `https://github.com/askdaddy/Git-Issue-Loop-Skill.git` into `~/.agents/skills/iloop`. Safely update an existing installation only when it is from the same repository and has no local changes; otherwise stop and report the conflict. Verify `SKILL.md` after installation.

“Latest” means the highest stable `vX.Y.Z` Git tag. It never means tracking
`main` or installing an alpha, beta, or release candidate. The Agent should
report the resolved tag and commit SHA after a successful installation.

The full staging, validation, backup, update, and rollback protocol is in
[INSTALL.md](INSTALL.md). Its machine-readable counterpart is
[skill-manifest.json](skill-manifest.json). Same-origin updates rename the
previous install to `~/.agents/backups/iloop.backup-<timestamp>` (outside
`skills/`; a hidden prefix under `skills/` is not enough, because some Agent
hosts still scan dot directories and register a second `/iloop`). Staging
clones to `${TMPDIR:-/tmp}/iloop.staging-<id>`. Same-origin updates clone
staging first, then follow that staging `INSTALL.md` / `skill-manifest.json`
for backup and switch.

> A stable `vX.Y.Z` tag must be published before latest-release installation is
> available. A compliant Agent fails closed when no stable tag exists; it must
> not fall back to `main`.

## Get started

1. Refresh the Agent host so that it discovers `~/.agents/skills/iloop`.
2. Open the target Git repository and run the environment check from that
   repository root:

   ```bash
   ~/.agents/skills/iloop/scripts/git-ops.sh doctor
   ```

3. Complete any reported CLI installation or authentication step yourself; do
   not put tokens in the repository or ask an Agent to enter credentials.
4. Start the workflow with `/iloop`. With no arguments it auto-picks the single
   most actionable open issue and reports the candidate list for your
   confirmation first. You can also pass an issue number, hand it a plain goal,
   or ask the Agent to only plan or only review.

For an initial label setup in a repository, run:

```bash
~/.agents/skills/iloop/scripts/git-ops.sh labels init
```

## Requirements

- Git and an Agent host that loads Skills from `~/.agents/skills/`.
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
scripts/check-update.sh  Compares the installed Skill against the highest stable tag
roles/                   Planner, Developer, and Reviewer role instructions
templates/               Spec, design, plan, and verification-report templates
references/              CLI setup guidance and the minimum-code ladder
test/                    Black-box invariant suites driving stub gh / glab / tea
docs/issues/<N>/         Degraded-fallback stage documents, written only when the
                         remote Issue platform is unavailable
```

## Stable releases

`main` is the development branch. Each stable release must use a new immutable
`vX.Y.Z` tag and should have a matching GitHub Release containing its change
notes. Pre-release tags use a SemVer suffix such as `-beta.1` and are skipped by
the default installer. Changes to the install protocol (`INSTALL.md` or
`skill-manifest.json` `installation`) must ship in a new stable `vX.Y.Z` tag.

For the normative workflow rules, see [SKILL.md](SKILL.md). For the Chinese
version of this introduction, see [README_CN.md](README_CN.md).
