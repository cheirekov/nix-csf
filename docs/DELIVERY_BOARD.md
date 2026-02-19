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
| T-008 | TODO | NixOS VM integration tests | broader scenario coverage |

### NEXT

| Priority | ID | Status | Title | Acceptance focus |
|---|---|---|---|---|
| 1 | T-008 | TODO | NixOS VM integration tests | broader scenario coverage |
| 2 | T-009 | TODO | Release automation and module versioning | repeatable publish flow |
| 3 | T-010 | TODO | Cluster policy propagation model | centralized allow/deny governance |

### LATER

| Priority | ID | Status | Title |
|---|---|---|---|
| 1 | T-009 | TODO | Release automation and module versioning |
| 2 | T-010 | TODO | Cluster policy propagation model |
| 3 | T-011 | TODO | Documentation use-case catalog expansion |

## Completed baseline

| ID | Status | Title |
|---|---|---|
| T-000 | DONE | Project bootstrap + team operating model |
| T-001 | DONE | Core `services.nixCsf` module and boot/refresh pipeline |
| T-002 | DONE | Validation pipeline (`flake check` + VM smoke test) |
| T-003 | DONE | Country filter policy modes (`deny` + `allow`) |
| T-004 | DONE | Per-port country policy (`CC_DENY_PORTS` style) |
| T-005 | DONE | Blocklist source catalog + schema |
| T-006 | DONE | Stateful rate-limit presets (`synFlood`, `connFlood`) |
| T-007 | DONE | Structured logging + Prometheus textfile metrics |

## Triage protocol

Use severity labels:

- `P0` security break / lockout risk
- `P1` stability/regression
- `P2` quality gap
- `P3` enhancement

Template: `docs/TRIAGE_NOTE_TEMPLATE.md`
