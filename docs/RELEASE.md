# Release and Compatibility Policy

Last updated: 2026-02-19

## Version source of truth

- Project/module version is stored in `VERSION`.
- Public release tags must be `v<semver>` (example: `v0.2.0`).

## SemVer policy

- `MAJOR` (`X.0.0`): breaking changes in module API or default behavior.
- `MINOR` (`0.X.0` / `X.Y.0`): backward-compatible new options/features.
- `PATCH` (`0.0.X` / `X.Y.Z`): backward-compatible fixes, test improvements, documentation corrections.

## Compatibility commitments

- Existing option names and types are kept stable within a major line.
- Default behavior changes that can affect traffic policy require:
  - explicit changelog callout,
  - migration guidance in README/docs,
  - validation evidence in `docs/PM_BA_CHANGELOG.md`.
- Deprecations are expected to keep at least one minor release overlap before removal.

## Release automation

Use `scripts/release.sh`:

```bash
# Dry run (checks + validation, no commit/tag):
./scripts/release.sh --version 0.2.0 --dry-run

# Create release commit + tag:
./scripts/release.sh --version 0.2.0

# Create and push release:
./scripts/release.sh --version 0.2.0 --push
```

The script performs:

- SemVer format validation,
- clean working tree gate (unless `--allow-dirty`),
- tag collision check,
- optional full validation (`./scripts/validate.sh`),
- `VERSION` update, release commit, and annotated tag creation.

## Release gate checklist

- `docs/SESSION_BRIEF.md` reflects active release ticket scope.
- `docs/DELIVERY_BOARD.md` and `docs/PM_BA_CHANGELOG.md` are updated.
- `nix flake check "path:$(pwd)" --all-systems --no-build` passes.
- `./scripts/validate.sh` passes.
- README reflects any behavior/API changes in the release.
