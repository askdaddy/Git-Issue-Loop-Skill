# Git Issue Loop Skill

[简体中文](README_CN.md)

Current stable release: [v0.6.12](https://github.com/askdaddy/Git-Issue-Loop-Skill/releases/tag/v0.6.12). See [CHANGELOG.md](CHANGELOG.md) for release history.

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
- A session-sticky iloop buffer: after an effective invocation, clarifying
  questions, confirmations, and blocked reports suspend rather than exit the
  loop. Your reply resumes the same Issue, stage, role, and scope; only an
  explicit `/iloop exit` (or equivalent, such as `退出 iloop`) or a new session
  leaves. Exit keeps the claim and does not change Issue state by itself.
- Auto-pick on a bare `/iloop`: scans open issues read-only, orders them
  `p0`→`p3` then by ascending number, skips blocked / retry-capped /
  verified-but-open / claimed ones, and reports the candidate list with its reasoning and
  skipped items. It waits for your confirmation before loading any role, and
  handles exactly one issue per invocation.
- Stage-aware dispatch: after checking whether intake is needed, a numbered
  issue resumes the role and stage supported by its RIPER status and artifacts.
  External or unknown-origin reports first receive Planner-led investigation
  and minimal label correction; valid existing progress is preserved.
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
  retry count (`riper-retry-1`–`3`) — plus a managed non-exclusive claim label
  (`riper-claimed`, marking an Issue as taken so parallel sessions' auto-pick
  skips it), totalling 15 built-in labels that
  `labels init` creates idempotently. It also canonicalizes repository-level
  priority variants such as `P0` without losing their open or closed Issue
  associations; migration failures stop before the repository variant is
  deleted.
- Hard T0 boundaries: the Planner and Reviewer may not touch business code, and
  `guard <role>` verifies the writable area against `git status` before a commit.
- `scripts/git-ops.sh`, which detects the hosting platform from `git remote`,
  routes to the official CLI, enforces per-role Issue permissions, and refuses to
  fall back to REST APIs or hand-entered credentials.
- Per-Issue workspace isolation for parallel sessions. A branch alone is not
  isolation: sessions sharing one clone share a single HEAD and index lock.
  `workspace start <N>` therefore builds a real `git worktree` outside the
  repository at `../.iloop-worktrees/<repo>/<N>`, on a `riper/<N>` branch based
  on `origin/<default branch>` and never on a local branch, so a session cannot
  inherit another session's unpushed commits. `workspace status` reports which
  work tree, branch, and Issue you are in; `workspace finish <N>` cleans up only
  once the work is clean and already merged upstream, and refuses rather than
  discards work otherwise; `guard <role> <N>` additionally verifies that the
  current branch really is `riper/<N>`.
- Runtime feedback for permission refusals, workspace violations, and missing
  Issue evidence: correct the task, prepare a redacted offline draft, and submit
  to maintainers only with explicit authorization.
- Optional structured runtime output: `issue priority`, `issue status`,
  `issue comment`, and `guard` emit one NDJSON event on a caller-opened fd 3
  (`ILOOP_EVENTS_FD=3`), plus a provenance-aware stage summary template
  (`templates/run-summary.md`) that separates script-observed facts, Agent
  declarations, and unverified items. Off by default: no local event log, no
  network, and no change to stdout, stderr, or exit codes. See the
  [runtime output contract](references/runtime-output.md).
- QA delivery through a verified pull request, with separate authorization for
  merging and publishing. Local-only delivery keeps the Issue open.
- 22 shell invariant suites under `test/`, covering CLI behavior through stubs
  and contract checks. The intake scenario walkthroughs are protocol reviews,
  not independent Agent end-to-end tests.

## Third-party Issue intake

Both `/iloop <N>` and the confirmed target from bare `/iloop` check whether the
Issue needs intake. External or unknown-origin Issues without valid intake
records go to the Planner, who verifies the report before changing labels:

1. Read the body, comments, provenance, and existing stage evidence. Investigate
   reproduction and root cause for bugs, or the scenario and scope for requests.
   Record facts, hypotheses, and unknowns; pause when information is insufficient.
2. Record findings in the original Issue, then minimally correct priority and
   stage labels within role permissions. Preserve unrelated labels, valid stage
   progress, retry counts, and claim history; reread to verify the changes.
3. Resume normal RIPER dispatch. Reuse valid intake findings and revisit only
   material changes; intake does not replace the specification or frozen plan.

`issue get <N> --strict` stops when a body or comment CLI call fails. It does
not certify pagination completeness or semantic accuracy. See the
[intake protocol](references/issue-intake.md) and [record template](templates/intake.md).

## Runtime feedback

Permission refusals, workspace guard failures, and missing stage evidence first
trigger task correction. `scripts/feedback.sh draft` produces a limited-field,
offline draft; it does not write files or submit a report. Before writing to the
maintainer repository, the Agent must redact the content, check duplicates, and
obtain authorization for that write.

Positive results include successful interception, safe recovery, regression
fixes, and corrected false positives. A published fix stays “awaiting observation”
until later runtime evidence supports verification. Feedback does not replace
product acceptance or automatically consume QA retries. See the
[feedback protocol](references/feedback-loop.md).

## Integration and releases

QA PASS → `riper-verified` → push and verify PR delivery → record evidence →
close the Issue and release its claim. Acceptance, PR delivery, upstream merge,
and publication are separate milestones. Offline or local-only merges keep the
Issue open. Workspace cleanup requires confirmed upstream integration.

PR merging and stable publication require separate authorization. A complete
stable publication includes both a new tag and a matching GitHub Release, after
the full test suite passes. See the [integration contract](references/integration.md).

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

Common invocations:

| Invocation | Behavior |
|---|---|
| `/iloop` | Present candidates and wait for confirmation; handle one Issue. |
| `/iloop #44` | Read the target, check intake, then resume the supported stage. |
| `/iloop Build X` | Draft a goal Issue and create it after confirmation. |
| `/iloop help` | Show usage and the installed version; stop without entering the loop or activating the buffer. |
| `/iloop exit` | Leave the buffer explicitly and print a handoff summary; keep the Issue open and the claim held. |
| `Plan only; do not execute` | Stop after planning, within the requested scope. |

Once in the buffer, answering a confirmation, adding scope, or asking a side
question does not exit; the reply resumes the suspended step. Only an explicit
exit or a new session leaves.

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
scripts/feedback.sh      Generates offline, limited-field feedback drafts
scripts/runtime-events.sh Opt-in NDJSON runtime events written to fd 3
roles/                   Planner, Developer, and Reviewer role instructions
templates/               Intake, spec, design, plan, verification-report, and run-summary templates
references/              CLI setup, intake, feedback, integration, runtime output, minimum-code ladder
test/                    Shell invariant suites and intake protocol walkthroughs
CHANGELOG.md             Stable-release change history
docs/issues/<N>/         Degraded-fallback stage documents, written only when the
                         remote Issue platform is unavailable
```

## Stable releases

`main` is the development branch. Each stable release must use a new immutable
`vX.Y.Z` tag and a matching GitHub Release containing its change
notes. Pre-release tags use a SemVer suffix such as `-beta.1` and are skipped by
the default installer. Changes to the install protocol (`INSTALL.md` or
`skill-manifest.json` `installation`) must ship in a new stable `vX.Y.Z` tag.

For the normative workflow rules, see [SKILL.md](SKILL.md). For the Chinese
version of this introduction, see [README_CN.md](README_CN.md). Stable release
history is recorded in [CHANGELOG.md](CHANGELOG.md).

## Safe label repair

Label-writing `issue priority`, `issue status` and `issue retry incr/reset`
require positive Issue identity from the official CLI. PRs and unconfirmed
metadata are rejected before writes; unsupported older CLI formats fail closed.
Other Issue operations do not yet share this type check.

For an explicitly justified repair, use `--role planner issue priority N none`,
or `--role <role> issue status N none`. Status clearing is limited to states
that role may set; mixed unauthorized states reject the entire clear. These
commands preserve unrelated labels and verify removal by rereading. Missing
roles, failed reads/removals and remaining family labels cannot report success.
They do not clear claims/retries, bypass intake/terminal protections, or repair
historical PR labels. There is no cross-request transaction guarantee.
