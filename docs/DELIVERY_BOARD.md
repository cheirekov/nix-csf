# DELIVERY BOARD — nix-csf

Last updated: 2026-02-24  
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

| ID | Status | Title | Focus |
|---|---|---|---|
| T-035 | IN_PROGRESS | Local list overlap audit and conflict reporting | Implement deterministic dedupe/overlap artifacts + metrics/logging + operator docs |

### NEXT

| Priority | ID | Status | Title | Acceptance focus |
|---|---|---|---|---|
| 1 | T-036 | TODO | Script/runbook completeness pass | One-page index + per-script usage examples + operator workflows |
| 2 | TBD | TODO | Release-candidate hardening | VM burn-in stability + documentation freeze |

### LATER

| Priority | ID | Status | Title |
|---|---|---|---|
| 1 | TBD | TODO | Optional Netdata plugin-noise cleanup (`otel/freeipmi/logs-management` tuning profile) |

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
| T-013 | DONE | Troubleshooting command set and runbook |
| T-014 | DONE | Strict apply semantics + deny precedence hardening |
| T-015 | DONE | Cluster policy schema v2 (`allow`/`deny`/`ignore` + revision/TTL) |
| T-016 | DONE | Dynamic offender propagation (rate-limit ban sync) |
| T-017 | DONE | ICMP policy profiles (legacy/off/safe/diagnostic/open + optional rate limits) |
| T-018 | DONE | Country allow-by-port (`CC_ALLOW_PORTS` parity) |
| T-019 | DONE | Grafana/Prometheus monitoring pack |
| T-020 | DONE | Cluster auth/token lifecycle and secret handling |
| T-021 | DONE | Firewall coexistence profile (Docker and dynamic daemons) |
| T-022 | DONE | Hybrid local+remote list reconciliation |
| T-024 | DONE | Cluster control-plane and snapshot publisher POC |
| T-025 | DONE | `nix-csfctl` operator workflow POC (allow/deny/ignore mutations) |
| T-026 | DONE | Dynamic escalation policy POC (`N` temp bans => permanent deny + audit) |
| T-027 | DONE | P0 feed reliability hotfix (Spamhaus endpoint update + parser compatibility for semicolon/ipset feeds) |
| T-028 | DONE | Legacy CSF list import bridge (`csf.allow/deny/ignore`) |
| T-029 | DONE | LFD-like detector POC (Nix-native) |
| T-030 | DONE | fail2ban adapter/coexistence profile |
| T-023 | DONE | Netdata monitoring integration |
| T-031 | DONE | Netdata metrics readability hotfix (`/var/lib/nix-csf` traversal for non-root collectors) |
| T-032 | DONE | Netdata charts.d execution hotfix (`systemd-cat-native` PATH wiring) |
| T-033 | DONE | Netdata charts.d discovery fix + process hard-rule hardening |
| T-034 | DONE | CSF advanced rule import parity (`tcp|in|...`) |
| T-037 | DONE | Validation lane split (`validate-agent` no-build + operator-manual full `nix build`) |

## Triage protocol

Use severity labels:

- `P0` security break / lockout risk
- `P1` stability/regression
- `P2` quality gap
- `P3` enhancement

Template: `docs/TRIAGE_NOTE_TEMPLATE.md`
