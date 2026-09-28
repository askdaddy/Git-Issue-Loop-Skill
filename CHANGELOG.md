# Changelog

All notable changes to stable `iloop` releases are recorded here. Releases use
immutable `vX.Y.Z` tags; installation follows the highest stable tag rather
than `main`.

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
