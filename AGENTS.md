# AGENTS

This repository uses a role-based delivery workflow for long-running implementation.

## Active roles

- `PM/BA`
  - Owns priority, acceptance, and batch scope control.
- `Security Architect`
  - Owns policy safety defaults and threat-model alignment.
- `Nix Module Engineer`
  - Owns module API and NixOS integration quality.
- `Threat Intel Engineer`
  - Owns remote feed source quality and update semantics.
- `QA/Release Engineer`
  - Owns validation and release readiness criteria.

## Source of truth

- Team rules: `docs/TEAM_OPERATING_RULES.md`
- Delivery board: `docs/DELIVERY_BOARD.md`
- Session contract: `docs/SESSION_BRIEF.md`
- Changelog: `docs/PM_BA_CHANGELOG.md`

## Workflow

1. Pick one `TODO` ticket from board.
2. Move it to `IN_PROGRESS`.
3. Implement and validate.
4. Update changelog and session brief.
5. Mark ticket `DONE` (or `BLOCKED` with reason).
