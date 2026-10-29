# Changelog

All notable changes to stable `iloop` releases are recorded here. Releases use
immutable `vX.Y.Z` tags; installation follows the highest stable tag rather
than `main`.

## [Unreleased]

### Fixed

- GitLab target checks accept both `/-/issues/<iid>` and `/-/work_items/<iid>`
  URLs, so newer GitLab Work Items issues can be tagged; merge-request URLs
  remain rejected. (#64)

### Validation

- Added a Work Items URL regression assertion to the target/clear invariants;
  23 shell suites pass.

## [0.6.14] - 2026-10-29

### Changed

- Skill upgrades now keep only the most recent `iloop.backup-*` after the new
  installation passes verification. Older backups are pruned only after a
  successful switch and verification; failed upgrades retain all backups.
  Pruning is limited to direct `~/.agents/backups/iloop.backup-*` directories
  and never follows symlinks. (#61)

### Validation

- Backup-location invariants now execute the documented prune snippet against
  old, current, symlink, file, and non-matching entries; 23 shell suites pass.

## [0.6.13] - 2026-10-29

### Added

- Every Issue created through `git-ops.sh issue create` now ends with a visible
  provenance footer containing the Skill repository URL
  (https://github.com/askdaddy/Git-Issue-Loop-Skill), installed version, short
  SHA, role, entry mode, and UTC timestamp. `[G]` marks the entry as
  `goal-bootstrap`; other roles default to `issue-create`. The footer is a
  source note, not authentication, and does not change intake or permissions.
  (#58)

### Fixed

- Issue-label writes now verify that the target is an Issue before touching
  labels, rejecting PR/MR numbers on GitHub, GitLab, and Gitea/Forgejo.
  `issue priority` and `issue status` gained an explicit `none` clear path with
  role-scoped validation and readback; retry increments and resets use the same
  target check. Partial repairs report the first clear failure without claiming
  completion, and emitted events stay within the existing schema. (#37)

### Validation

- Added a shell invariant suite for the provenance footer, including the repo
  URL, version/SHA fallback, role/entry, UTC timestamp, original-body
  preservation, and absence of local paths.
- Added target-validation and scoped-family repair coverage; the documented
  suite inventory is now checked dynamically. All 23 shell suites pass. (#37)

## [0.6.12] - 2026-10-22

### Added

- A session-sticky iloop buffer. After an effective invocation, clarifying
  questions, confirmations, environment handoffs, and blocked reports suspend
  the workflow instead of exiting it. The next user message resumes the same
  Issue, stage, role, and scope; only an explicit `/iloop exit` (or equivalent)
  or a new session leaves. Exit prints a handoff summary and keeps the claim;
  remote Issue labels remain the cross-session source of truth.

### Validation

- Added a shell invariant suite covering buffer entry, suspension, resume,
  explicit exit, help-without-activation, and non-terminal semantics.

## [0.6.11] - 2026-10-22

### Changed

- Aligned the main workflow, all three role prompts, and handoff templates.
  PASS, confirmed FAIL, and unable-to-verify results now have distinct exits;
  missing evidence or environment alone does not consume QA retries. (#48)
- Unified PR delivery before Issue closure, Planner-owned frozen-plan revisions,
  intake handoff gates, and evidence validity checks. Completed valid artifacts
  can advance without repeatedly restarting the same stage. (#48)
- Restructured role prompts around entry, inputs, permitted actions, outputs,
  handoff and stopping conditions, replacing emotional personas with explicit
  evidence requirements. Script enforcement and Agent protocol guarantees are
  described separately. Runtime CLI permissions and labels are unchanged. (#48)
- Plan comments reference the current spec and design instead of duplicating
  all three documents; revised acceptance templates capture baseline versions,
  tested commits, unknown results and delivery evidence. (#48, #27)
- Updated project guides in both languages for intake, feedback, integration,
  invocation examples and the 19 shell suites. (#47)

### Validation

- Added 18 prompt-alignment protocol walkthroughs and maintained dispatch
  assertions against the normative contract rather than obsolete prose.
  Walkthroughs are same-session protocol reviews, not independent Agent E2E
  tests or evidence of real-world compliance rates. (#48)

## [0.6.10] - 2026-10-21

### Added

- Third-party Issue intake for both explicit Issue IDs and the confirmed target
  from a bare invocation. The planner verifies the report before normalizing
  labels, records facts and unknowns, and resumes the evidence-based stage. (#44)
- An intake record template and protocol for source evidence, reproduction or
  requirement investigation, label-change auditing, review of changed inputs,
  and reuse of still-valid findings. Existing valid progress, unrelated labels,
  retry counts and claim history are preserved. (#44)
- `issue get <N> --strict`: body or comment command failures stop the read with
  an explicit error. Legacy reads retain best-effort comment compatibility.
  Strict mode does not certify pagination completeness or semantic accuracy.
- Three-platform strict-read tests and documented intake scenario walkthroughs.
  Protocol walkthroughs are distinguished from independent Agent E2E tests.

### Changed

- Stage dispatch checks whether external or unknown-origin Issues need intake;
  bare-invocation candidate discovery stays read-only until user confirmation.
  Research reuses verified intake evidence rather than repeating investigation.
- The GitLab comment-read regression check now verifies the observable CLI call
  instead of depending on a literal internal source expression. (#44)

## [0.6.9] - 2026-10-21

### Added

- Runtime feedback protocol for evidence-based attribution, task correction,
  redacted maintainer drafts, duplicate review, explicit submission authorization,
  and links from fixes to regression checks, releases and later observations.
  Suspected violations, confirmed violations, successful interception and false
  positive corrections are recorded separately. (#40)
- Offline allowlist-only feedback drafts for permission, workspace and Issue
  evidence problems. Draft generation does not submit reports or persist logs;
  unknown context stays unknown. (#40)
- Stable diagnostic rule codes on permission and workspace refusals, preserving
  existing decisions and exit codes; missing-role compatibility is marked as
  unattributed rather than a confirmed violation. (#40)
- Black-box feedback tests covering twelve draft combinations, secret-safe input
  rejection, foreign working directories, absent Git metadata and refusal safety.

### Changed

- Stage handoffs now link to the feedback protocol while preserving the PR
  delivery and release responsibilities introduced in v0.6.8. Feedback does not
  consume ordinary product QA retries or claim production improvement without
  an adequate observation window. (#40)

## [0.6.8] - 2026-10-20

### Added

- Explicit-role integration primitives for branch pushes, GitHub/GitLab/Gitea
  pull requests, isolated local fallback merges, and GitHub Release metadata.
  Release creation checks the published lightweight tag, expected commit,
  default branch and version-specific CHANGELOG notes. (#25)
- Black-box integration tests for role denial, platform routing, local merge
  conflicts, release preconditions and cleanup failure safety. (#25)

### Changed

- QA closes an accepted Issue only after a pull request has been delivered and
  its branch/commit evidence recorded, or upstream integration is confirmed.
  Offline or local-only merges keep the Issue open. Pull requests are not
  merged automatically; publication requires separate authorization. (#25)
- Workspace cleanup refreshes the upstream reference before checking ancestry.
  Unmerged, uncertain or squash/rebase-only ancestry is retained for review.
- GitHub pull request inspection returns base/head branches and the head SHA
  so delivery can be checked against the accepted commit. (#25)

## [0.6.7] - 2026-10-20

### Added

- Cross-session claim mutex for auto-pick. A bare `/iloop` picks deterministically
  (p0→p3, then number ascending) and, per protocol, writes nothing to the Issue,
  so two parallel sessions would select the same Issue and both start work. A new
  managed **non-exclusive** label `riper-claimed` marks an Issue as taken, and
  auto-pick now skips claimed Issues with a stated reason — homomorphic to
  `riper-retry-*`: the "who took it" signal lives on the Issue, not in
  cross-session agent memory. (#24)
- `issue claim <N> <claim|release|get>`, mirroring `issue retry`:
  - `get` prints `claimed` / `unclaimed` — a cheap, reliable read for auto-pick
    that keeps the claim signal out of `issue list` (source separation, like retry).
  - `claim` writes the label **and** an audit comment carrying the git user, UTC
    timestamp, worktree path, and branch, and **refuses to preempt** an Issue that
    is already claimed (exit 1, echoing the existing claim) so stale claims stay a
    human decision.
  - `release` removes the label with a release comment and is idempotent when the
    Issue is unclaimed.
- The built-in label set grows from 14 to **15** (4 priority + 7 status + 3 retry
  + 1 claim). `labels init` creates `riper-claimed` and `doctor` now fails closed
  until it exists; the count text is synced across `SKILL.md`,
  `references/cli-setup.md`, and both READMEs.

### Changed

- `issue list` excludes `riper-claimed` from the status column so a claim can
  never be misread as a RIPER stage, and `issue label add/remove` is blocked from
  the claim family — forcing `issue claim` so the audit comment always lands.
- Claiming is documented honestly as a best-effort signal, not a hard lock: two
  sessions can both read "unclaimed" before either writes. The same-machine hard
  gate remains `workspace start`'s `riper/<N>` branch fast-fail (from 0.6.6).

## [0.6.6] - 2026-10-19

### Added

- Per-Issue workspace isolation for parallel sessions. A branch alone is not
  isolation: two sessions in one clone share a single HEAD and `.git/index.lock`,
  so `git checkout` by one is global to the other. `workspace start <N>` now
  builds a real `git worktree` outside the repository at
  `../.iloop-worktrees/<repo>/<N>` on a `riper/<N>` branch.
- The baseline is always `origin/<default branch>`, never a local branch, so a
  session cannot silently inherit another session's unpushed commits. When the
  default branch cannot be resolved the command stops and asks for `--base`
  instead of falling back.
- `workspace status` reports, read-only and offline, which work tree and branch
  you are in, which Issue it belongs to, how far it is from the upstream
  baseline, and the full worktree list.
- Inside a linked worktree `workspace start <N>` never nests. It normalizes
  instead: idempotent when already on `riper/<N>`, refused when the work tree
  belongs to another Issue, and for a detached HEAD left behind by a host it
  attaches `riper/<N>` in place, preserving every existing commit and stating
  that the baseline is that commit rather than the upstream.
- `workspace finish <N>` cleans up locally behind three gates — clean, verifiable,
  and already merged into `origin/<default branch>` — and refuses rather than
  discards work when any gate fails. It never uses `worktree remove --force` or
  `branch -D`, and keeps the empty parent directory.
- `guard <role> <N>` optionally verifies that the current branch really is
  `riper/<N>`, so a change cannot be committed into another Issue's work tree.
  Omitting `<N>` keeps the previous behavior byte for byte.
- `guard` now prints a parallel-pollution diagnostic when it runs in the primary
  work tree with pending changes, pointing at `workspace start <N>`. The
  diagnostic never alters the verdict or the exit code.

### Fixed

- `check-update.sh` now surfaces git's own failure cause and the locally
  installed `local_ref` when the update check fails, and `SKILL.md` requires the
  Agent to relay both and say plainly that the version could not be confirmed,
  instead of reporting a bare "update check failed".
- `workspace finish <N>` survived being run from inside the very work tree it
  removes. git does not refuse to delete the work tree you are standing in: it
  deletes it, and the following `git branch -d` then dies on the vanished working
  directory, leaving a half-finished state plus an error blaming the merge status.
  The command now moves to the primary work tree before removing anything, so the
  working directory stays valid, and tells a stranded shell where to `cd` back.
- `git branch -d` failures no longer assert an unverified cause. The message
  states which command and branch failed, leaves git's own reason visible, admits
  the half-finished state, and gives a `-d` recovery command. The tool also no
  longer relays git's `branch -D` hint, since it must never recommend a
  destructive command.

### Tested

- Added `test/iloop-workspace-isolation-invariants.sh`, a black-box suite of 99
  assertions covering `workspace status|start|finish`, the guard diagnostic, and
  the Issue-number check. Every worktree and branch scenario is built inside a
  throwaway fixture whose `origin` is a local bare repository: no network, no
  change to the real repository, no residue. It also passes when run from inside a
  target work tree, which is the case the original gap hid behind.
- Removed eleven working-tree-coupled guards across the suite. Each asserted
  `git diff HEAD -- <path>` was empty, which only ever sees uncommitted edits and
  never the commit set, so the scope claims they advertised never held. Their real
  effect was to fail the suite whenever anyone had work in progress, which made
  "test before committing" impossible. Three files that already grepped
  `scripts/git-ops.sh` now assert the same pattern against the committed blob
  instead; the other eight were deleted with every genuine assertion kept.
  Counter-proofs confirm the suites still fail when the code they cover breaks.
- Avoided a SIGPIPE false negative in the new committed-blob guards: `grep -q`
  exits on first match, so under `pipefail` `git show` dies of SIGPIPE and the
  pipeline reports 141, reading a present pattern as absent.

### Documentation

- `SKILL.md` gained two §0 conventions — workspace isolation, and the fact that
  the host resets the working directory between calls so every command must carry
  an absolute path — plus the Issue-numbered `guard` form in T0 rule 9 and the
  `riper/<N>` commit requirement in the [E] phase.
- All three role files now open their required-actions list with a workspace
  prerequisite, and state that `workspace` is environment-level and role-agnostic
  but never exempts anyone from `guard`.
- Documented workspace isolation in `README.md` and `README_CN.md`, and corrected
  both to the actual number of invariant suites under `test/`.

Issues: [#23](https://github.com/askdaddy/Git-Issue-Loop-Skill/issues/23),
[#30](https://github.com/askdaddy/Git-Issue-Loop-Skill/issues/30),
[#31](https://github.com/askdaddy/Git-Issue-Loop-Skill/issues/31)
Pull request: [#29](https://github.com/askdaddy/Git-Issue-Loop-Skill/pull/29)

## [0.6.5] - 2026-09-28

### Fixed

- Canonicalize repository-level priority labels such as `P0` to `p0` during
  `labels init`, closing the scope gap left by the earlier Issue-level cleanup.
- Preserve every open and closed Issue association by adding the canonical
  label, removing the variant, and verifying the result before deleting the
  repository-level variant.
- Fail closed when Issue enumeration, migration verification, or repository
  label deletion fails, leaving the variant available for a safe retry.

### Tested

- Added black-box GitHub, GitLab, and Gitea/Forgejo coverage for migration
  order, open and closed Issues, idempotency, and remove/verify/delete failure
  recovery.
- Updated the legacy glab compatibility stub to model repository label-list
  output used by normalization.

### Documentation

- Documented repository-level priority normalization in `README.md`,
  `README_CN.md`, and `SKILL.md`.

Issue: [#22](https://github.com/askdaddy/Git-Issue-Loop-Skill/issues/22)

[0.6.5]: https://github.com/askdaddy/Git-Issue-Loop-Skill/compare/v0.6.4...v0.6.5
[0.6.6]: https://github.com/askdaddy/Git-Issue-Loop-Skill/compare/v0.6.5...v0.6.6
