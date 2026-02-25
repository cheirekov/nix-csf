# Team Operating Rules

Purpose: keep this firewall project moving with one clear lane at a time.

## Team roles

- `PM/BA`
  - Owns scope, acceptance criteria, and release gate decisions.
- `Security Architect`
  - Owns threat model, firewall policy defaults, and hard safety constraints.
- `Nix Module Engineer`
  - Owns module API, NixOS integration, and backward compatibility.
- `Threat Intel Engineer`
  - Owns country feed and blocklist source quality.
- `QA/Release Engineer`
  - Owns validation matrix and release artifacts.

## Hard rules

1. Exactly one ticket may be `IN_PROGRESS`.
2. Every code change must map to a ticket in `docs/DELIVERY_BOARD.md`.
3. Every patch batch must add an entry in `docs/PM_BA_CHANGELOG.md`.
4. No hidden behavior change; if behavior changes, docs must be updated in the same batch.
5. Security-default posture is explicit:
   - default inbound policy is `drop` unless a ticket says otherwise.
6. Country/blocklist remote feeds must be optional and failure-aware (`failOpen` vs fail-closed behavior).
7. New feature ideas go to triage; only `P0` and `P1` can interrupt active work.
8. Before starting a batch, update `docs/SESSION_BRIEF.md`.
9. A ticket is done only when code, docs, and validation evidence are aligned.
10. Process guard is mandatory in continuous engineering mode:
   - no code handoff without same-batch updates to `README.md` + relevant runbook docs,
   - no status handoff without board/changelog/session updates,
   - no exception for patch releases.
11. Every production hotfix must add at least one regression guard (eval/test/assertion) in the same batch.
12. Validation lanes are split and mandatory:
   - Agent lane: `./scripts/validate-agent.sh` only (no `nix build`).
   - Operator lane: `./scripts/validate-capture.sh` (full `nix build` + VM checks).
13. Ticket closure requires operator evidence for full validation:
   - either `[nix-csf] validation succeeded`,
   - or failure summary log path from `.artifacts/validate/*-summary.log`.

## Definition of done

- Module code updated.
- Documentation updated (README + relevant docs).
- Process artifacts updated (`docs/DELIVERY_BOARD.md`, `docs/PM_BA_CHANGELOG.md`, `docs/SESSION_BRIEF.md`).
- Ticket status updated in board.
- Changelog entry includes risk impact and validation evidence.

## Continuous engineering handoff checklist

Before any handoff response:

1. `Code`: feature/hotfix changes applied.
2. `Docs`: README + feature runbook updated in same batch.
3. `Process`: board + changelog + session brief updated.
4. `Guard`: at least one eval/test/assertion added or updated for the changed behavior.
5. `Operator`: provide exact verification commands for production users.
