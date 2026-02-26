# Release Candidate Decision

Date: 2026-02-26  
Owners: PM/BA + Security Architect + QA/Release Engineer

## Decision

Recommendation: `GO` for first release-candidate tag.

Rationale:

1. Full operator validation succeeded.
2. Burn-in run succeeded (`3/3` consecutive full validations).
3. Release hardening checklist is implemented and documented.
4. No active `P0`/`P1` blockers recorded in current board artifacts.

## Evidence

1. Operator validation result:
   - `[nix-csf] validation succeeded`
2. Burn-in command:
   - `./scripts/validate-burnin.sh --runs 3`
3. Burn-in summary:
   - `/home/yc/work/nix-csf/.artifacts/validate/burnin-20260226T065638Z-summary.log`
4. Hardening references:
   - `docs/RELEASE_CANDIDATE_HARDENING.md`
   - `docs/RELEASE.md`

## Cut checklist

1. Confirm working tree is committed and tagged release inputs are frozen.
2. Run:
   - `./scripts/validate-capture.sh`
3. Optionally repeat:
   - `./scripts/validate-burnin.sh --runs 3`
4. Perform release dry-run:
   - `./scripts/release.sh --version <semver> --dry-run`
5. Create release:
   - `./scripts/release.sh --version <semver>`
6. Push tag when approved:
   - `./scripts/release.sh --version <semver> --push`

## Rollback framing

If post-tag regression is detected:

1. Freeze further rollout.
2. Reproduce with `./scripts/validate-capture.sh`.
3. File triage note with failing summary/logs.
4. Publish patch release (`PATCH` bump) after fix validation.
