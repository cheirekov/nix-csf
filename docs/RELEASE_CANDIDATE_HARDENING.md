# Release-Candidate Hardening

Last updated: 2026-02-25  
Owners: PM/BA + Security Architect + QA/Release Engineer

Purpose: define the hard gate before recommending first stable production rollout.

## 1) Exit criteria

All items must be satisfied:

1. Full operator validation succeeds: `./scripts/validate-capture.sh`.
2. No open `P0`/`P1` triage notes.
3. Documentation freeze checklist completed.
4. Security validation runbook is executed (or explicitly waived with reason): `docs/SECURITY_VALIDATION_RUNBOOK.md`.
5. Release evidence bundle is captured and attached to changelog/session notes.

## 2) Environment matrix

Run validation in both environments when available:

1. KVM-enabled host (primary signal; expected performance path).
2. TCG fallback host (slow-path resilience; optional if capacity-constrained).

If TCG is used only for incident debugging, mark it explicitly in evidence notes.

## 3) Burn-in workflow

Recommended sequence:

1. Agent lane sanity:
   - `./scripts/validate-agent.sh`
2. Operator lane full run:
   - `./scripts/validate-capture.sh`
3. Repeat full run at least twice more across fresh rebuilds/reboots.

Minimum evidence target:

- 3 consecutive successful full operator runs.

If any run fails:

1. Capture summary path from `.artifacts/validate/*.log`.
2. Capture failing derivation log with `nix log <drv>`.
3. File triage note and block release gate until resolved.

## 4) Evidence bundle

For each candidate release record:

1. Validation summaries from `.artifacts/validate/`.
2. `git rev-parse HEAD` for the validated commit.
3. `nix flake metadata` snapshot (inputs + lock state).
4. Explicit note whether run used KVM or TCG fallback.
5. Security runbook evidence bundle from `.artifacts/security/` (or waiver note).

## 5) Documentation freeze checklist

Before tagging:

1. `README.md` reflects current feature set and links.
2. `docs/DEPLOYMENT_BLUEPRINTS.md` is aligned with module options.
3. `docs/RELEASE.md` and this document reflect the actual gate.
4. `docs/SECURITY_VALIDATION_RUNBOOK.md` is aligned with current controls/detectors.
5. `docs/DELIVERY_BOARD.md`, `docs/ROADMAP.md`, `docs/PM_BA_CHANGELOG.md`, `docs/SESSION_BRIEF.md` are consistent.

## 6) RC decision

RC recommendation is allowed only if:

1. burn-in evidence is complete,
2. no blocking tickets remain in `IN_PROGRESS`,
3. release checklist in `docs/RELEASE.md` is green.
