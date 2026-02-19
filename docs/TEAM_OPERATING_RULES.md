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

## Definition of done

- Module code updated.
- Documentation updated (README + relevant docs).
- Ticket status updated in board.
- Changelog entry includes risk impact and validation evidence.
