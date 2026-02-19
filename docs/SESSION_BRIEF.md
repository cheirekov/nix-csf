# Session Brief

Last updated: 2026-02-19  
Owner: PM/BA + Codex

## 1) Batch contract

- Batch type: `DAY (2-4h)`
- Active ticket: `T-011` (Documentation use-case catalog expansion).
- Goal: provide operator-focused deployment examples that make feature adoption and verification straightforward.
- In scope:
  - publish a dedicated operator use-case catalog doc,
  - include concrete snippets for web/SSH/geo/blocklist/cluster/offline/observability scenarios,
  - include operator verification commands for apply/refresh/rules/metrics checks,
  - link catalog from README for discoverability.
- Out of scope:
  - preset profile layer (`T-012`),
  - troubleshooting runbook expansion (`T-013`).
- Stop/rollback condition:
  - documentation examples mismatch actual module options or create contradictory failure-mode guidance.

## 2) Definition of done

- `docs/USE_CASES.md` exists with operator-oriented scenarios and command checks.
- README includes explicit pointer to the catalog.
- Board/changelog/roadmap/session docs are aligned to mark `T-011` done and queue `T-012`.
- Validation evidence is captured in changelog/session notes.

## 3) End-of-batch result

- Decision: `continue`
- Completed:
  - `T-011` documentation use-case catalog expansion:
    - added `docs/USE_CASES.md` with seven operator scenarios,
    - added baseline operational check command set,
    - added README link to the full use-case catalog.
- Validation evidence:
  - `./scripts/validate.sh`
- Next ticket candidate:
  - `T-012` preset threat profiles (server/workstation/edge).
