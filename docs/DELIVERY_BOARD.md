# DELIVERY BOARD — nix-csf

Last updated: 2026-02-20  
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
| T-015 | TODO | Cluster policy schema v2 (`allow`/`deny`/`ignore` + revision/TTL) | centralized list governance model |

### NEXT

| Priority | ID | Status | Title | Acceptance focus |
|---|---|---|---|---|
| 1 | T-015 | TODO | Cluster policy schema v2 (`allow`/`deny`/`ignore` + revision/TTL) | centralized list governance model |
| 2 | T-016 | TODO | Dynamic offender propagation (rate-limit ban sync) | CSF-like temporary cluster blocks |
| 3 | T-017 | TODO | ICMP policy profiles (type/rate controls) | safer ICMP defaults + explicit tuning |
| 4 | T-018 | TODO | Country allow-by-port (`CC_ALLOW_PORTS` parity) | per-port country allow model |
| 5 | T-019 | TODO | Grafana/Prometheus monitoring pack | dashboards + alert rules + runbook |
| 6 | T-020 | TODO | Cluster auth/token lifecycle and secret handling | secure token distribution/rotation |
| 7 | T-013 | TODO | Troubleshooting command set and runbook | operator troubleshooting speed |

### LATER

| Priority | ID | Status | Title |
|---|---|---|---|
| 1 | T-016 | TODO | Dynamic offender propagation (rate-limit ban sync) |
| 2 | T-018 | TODO | Country allow-by-port (`CC_ALLOW_PORTS` parity) |
| 3 | T-013 | TODO | Troubleshooting command set and runbook |

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
| T-008 | DONE | NixOS VM integration tests (multi-scenario) |
| T-009 | DONE | Release automation and module versioning |
| T-010 | DONE | Cluster policy propagation model |
| T-011 | DONE | Documentation use-case catalog expansion |
| T-012 | DONE | Preset threat profiles (server/workstation/edge) |
| T-014 | DONE | Strict apply semantics + deny precedence hardening |

## Triage protocol

Use severity labels:

- `P0` security break / lockout risk
- `P1` stability/regression
- `P2` quality gap
- `P3` enhancement

Template: `docs/TRIAGE_NOTE_TEMPLATE.md`
