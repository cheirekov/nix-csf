# DELIVERY BOARD — nix-csf

Last updated: 2026-02-19  
Owner: PM/BA + Security Architect + Nix Module Engineer

## North Star

Ship a production-usable NixOS firewall module that is:

- easy to configure declaratively,
- secure by default,
- compatible with flakes and non-flake setups,
- extensible toward CSF-like modern features.

## Work rules

- WIP limit: one `IN_PROGRESS` ticket only.
- Every `DONE` ticket must include:
  - changelog entry in `docs/PM_BA_CHANGELOG.md`
  - session note update in `docs/SESSION_BRIEF.md`
  - validation evidence

## NOW / NEXT / LATER

### NOW

| ID | Status | Title | Scope freeze |
|---|---|---|---|
| T-003 | TODO | Country filter policy modes (`deny` + `allow`) | No per-port country logic in this ticket |

### NEXT

| Priority | ID | Status | Title | Acceptance focus |
|---|---|---|---|---|
| 1 | T-003 | TODO | Country filter policy modes (`deny` + `allow`) | safe semantics and tests |
| 2 | T-004 | TODO | Per-port country policy (`CC_DENY_PORTS` style) | minimal ergonomic API |
| 3 | T-005 | TODO | Blocklist source catalog + schema | trusted source governance |

### LATER

| Priority | ID | Status | Title |
|---|---|---|---|
| 1 | T-006 | TODO | Stateful rate-limit presets (SYN flood, conn flood) |
| 2 | T-007 | TODO | Structured logging and metrics exporter |
| 3 | T-008 | TODO | NixOS VM integration tests |
| 4 | T-009 | TODO | Release automation and module versioning |

## Completed baseline

| ID | Status | Title |
|---|---|---|
| T-000 | DONE | Project bootstrap + team operating model |
| T-001 | DONE | Core `services.nixCsf` module and boot/refresh pipeline |
| T-002 | DONE | Validation pipeline (`flake check` + VM smoke test) |

## Triage protocol

Use severity labels:

- `P0` security break / lockout risk
- `P1` stability/regression
- `P2` quality gap
- `P3` enhancement

Template: `docs/TRIAGE_NOTE_TEMPLATE.md`
