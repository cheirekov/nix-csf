# DELIVERY BOARD — nix-csf

Last updated: 2026-02-25  
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
| T-047 | IN_PROGRESS | Integration test expansion for gateway + detector flows | VM scenarios for NAT/forward/egress and detector/escalation/cluster propagation paths |

### NEXT

| Priority | ID | Status | Title | Acceptance focus |
|---|---|---|---|---|
| 1 | T-048 | TODO | Documentation and deployment blueprints for Stage 1/2 | End-to-end examples (gateway, bastion, app, clustered nodes) |
| 2 | TBD | TODO | Release-candidate hardening | VM burn-in stability + documentation freeze |

### LATER

| Priority | ID | Status | Title |
|---|---|---|---|
| 1 | TBD | TODO | Optional Netdata plugin-noise cleanup (`otel/freeipmi/logs-management` tuning profile) |
| 2 | TBD | TODO | Optional policy-as-code authoring helper (`nix-csfctl policy compile`) |

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
| T-035 | DONE | Local list overlap audit and conflict reporting |
| T-036 | DONE | Script/runbook completeness pass |
| T-037 | DONE | Validation lane split (`validate-agent` no-build + operator-manual full `nix build`) |
| T-038 | DONE | README information architecture and documentation index refresh |
| T-039 | DONE | Epic kickoff: firewall-ownership + LFD expansion staged plan |
| T-040 | DONE | NAT datapath foundation (nix-csf as gateway firewall) |
| T-041 | DONE | Forwarding policy matrix (interface/zone aware) |
| T-042 | DONE | Optional egress policy controls |
| T-043 | DONE | LFD detector framework v2 |
| T-044 | DONE | Built-in detector pack v2 |
| T-045 | DONE | Escalation engine v2 |
| T-046 | DONE | Cluster propagation semantics v2 |

## Triage protocol

Use severity labels:

- `P0` security break / lockout risk
- `P1` stability/regression
- `P2` quality gap
- `P3` enhancement

Template: `docs/TRIAGE_NOTE_TEMPLATE.md`
